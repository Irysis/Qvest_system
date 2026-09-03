#!/usr/bin/env Rscript
#==============================================================================
# reinforce_auto_parallel.R — 강화 무인 러너 **병렬 배치** (도훈 지시 2026-08-30 "병렬로 실행")
#
# 왜 별도 파일인가 (reinforce_auto_run.R 과의 관계):
#   순차 러너는 claim mutex 로 **한 번에 한 칸**을 강제한다. 그 상태로 동시에 띄우면
#   다음 칸이 `attempts_used + 1` 이라 **넷 다 같은 칸**을 잡는다.
#   그래서 병렬은 구조를 바꾼다 — **원장 쓰기를 실행에서 떼어낸다**:
#     ① 사전 등록  : 순차 (rf_append_attempt — 원장 단독 접근)
#     ② 실행       : 병렬 (rf_cell_worker.R — 원장 미접근, 결과를 자기 JSON 에만 기록)
#     ③ 결과 수집  : 순차 (rf_record_result)
#   read-modify-write 경합이 원천적으로 없다.
#
# ★같은 블록 안에서만 병렬화한다. 블록 경계를 넘으면 안 되는 이유:
#   B2/B3 는 B1 승자 위에 서고 B4 는 B1~B3 승자 위에 선다. 승자가 확정되기 전에
#   다음 블록을 띄우면 **결정되지 않은 값 위에서 측정**하게 된다(공허한 시도).
#   이 규칙이 없으면 2026-08-30 의 "공허한 LOO" 사고가 병렬로 4배가 된다.
#
# 사용: Rscript reinforce_auto_parallel.R        (설정의 parallel_cells 만큼)
# 하드 가드는 순차 러너와 동일 — kill switch · claim · daily_cap · 자본 경계.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
# ★검사가 격리 사본을 쓸 수 있게 — 공유 설정을 검사가 직접 만지면 그 창에 tick 이 끼어든다
CFG_P  <- { .c <- Sys.getenv("QVEST_RF_CONFIG", "")
            if (nzchar(.c) && file.exists(.c)) .c
            else file.path(ROOT, "06_Registry/reinforce_auto_config.json") }
PROG_P <- file.path(ROOT, "06_Registry/reinforce_program.json")
LOG_P  <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
# ★검사가 격리 사본을 쓸 수 있게 — 공유 claim 을 검사가 지우면 그 창에 tick 이 끼어들어
#   살아있는 배치 옆에 둘째 배치가 뜼다(원장 경합). 설정 격리(QVEST_RF_CONFIG)와 같은 형태.
CLAIM  <- { .cl <- Sys.getenv("QVEST_RF_CLAIM", "")
           if (nzchar(.cl)) .cl else file.path(ROOT, ".cache/reinforce_auto.claim") }
WDIR   <- file.path(ROOT, ".cache/rf_parallel")
dir.create(dirname(LOG_P), recursive = TRUE, showWarnings = FALSE)
dir.create(WDIR, recursive = TRUE, showWarnings = FALSE)

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "parallel"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rf_par] %s %s\n", event,
              paste(names(rec)[-(1:3)], unlist(lapply(rec[-(1:3)], function(z) substr(paste(z, collapse=","), 1, 80))),
                    sep = "=", collapse = " ")))
}

# ★등록 거부 누적 횟수 (entry·셀 코드 단위). 커서가 코드 기반이 된 뒤로 거부된 칸은
#   다음 tick 에 그대로 다시 잡힌다 — 회복은 되지만 **결정론적 거부에는 출구가 없다**
#   (2026-08-31 B3_11 16회 제자리 사고와 같은 형태). 그래서 상한을 두고 멈춰 세운다.
.append_fail_count <- function(code, bid) {
  if (!file.exists(LOG_P)) return(0L)
  tryCatch(sum(vapply(readLines(LOG_P, warn = FALSE), function(l) {
    if (!grepl('"append_failed"', l, fixed = TRUE)) return(FALSE)
    r <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
    !is.null(r) && identical(as.character(r$code %||% ""), code) &&
      identical(as.character(r$base_id %||% ""), bid)
  }, logical(1))), error = function(e) 0L)
}

CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled"); quit(status = 0) }
NPAR      <- as.integer(CFG$parallel_cells %||% 4L)
DAILY_CAP <- as.integer(CFG$daily_cap %||% 8L)
STALE_H   <- as.numeric(CFG$claim_stale_hours %||% 6)
# ★한 칸의 재시도 상한. 재개는 일시적 실패를 살리는 장치지 무한 재시도가 아니다.
MAX_RETRY <- as.integer(CFG$cell_max_retry %||% 2L)

done_today <- 0L
if (file.exists(LOG_P)) {
  today <- format(Sys.Date(), "%Y-%m-%d")
  done_today <- tryCatch(sum(vapply(readLines(LOG_P, warn = FALSE), function(l) {
    o <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
    isTRUE(!is.null(o) && identical(o$event, "cell_done") && startsWith(o$ts %||% "", today))
  }, logical(1))), error = function(e) 0L)
}
if (done_today >= DAILY_CAP) { jlog("halt_daily_cap", done = done_today, cap = DAILY_CAP); quit(status = 0) }

# ★claim 획득·해제는 rf_claim.R 하나. 2026-08-30 실사고 2회 — 배치 종료 후 unlink 이 조용히
#   실패해 빈 claim 이 남았고, 그러면 stale_hours(6h) 가 찰 때까지 전 tick 이 halt_claimed 로
#   물러난다. 그 로그는 **정상 대기와 글자 그대로 같아서** 아무도 못 본다(부팅 때 본 1.5h 공백).
#   그래서 owner.json(pid) 을 남기고, 다음 실행이 그 pid 사망을 보면 나이 무관 즉시 회수한다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_claim.R")))
# ★위임 호출에서는 부모가 이미 claim 을 쥐고 있다 — 자식이 다시 잡으려 하면 자기 부모에게 막혀
#   아무 일도 못 하고 끝난다(2026-08-30 실사고: halt_exhausted_delegate → halt_claimed 가 8분마다
#   2시간 반 동안 반복, 소진 전이가 영영 안 됐다). 부모가 이 플래그로 "이미 잡았다" 를 알린다.
.CLAIM_HELD <- nzchar(Sys.getenv("QVEST_RF_CLAIM_HELD", ""))
.ac <- if (.CLAIM_HELD) list(ok = TRUE, reason = "inherited", age_h = NA_real_,
                            owner_pid = NA_integer_, note = "") else
       rf_claim_acquire(CLAIM, stale_hours = STALE_H)
if (!isTRUE(.ac$ok)) {
  if (identical(.ac$reason, "race")) jlog("halt_claim_race")
  else jlog("halt_claimed", age_h = round(.ac$age_h %||% NA_real_, 2), owner_pid = .ac$owner_pid %||% NA)
  quit(status = 0)
}
if (nzchar(.ac$note %||% "")) jlog("claim_stale_reclaim", note = .ac$note)

main <- function() {
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
# ── 처치 전달 판정 헬퍼 — ★정본은 rf_spec_sig.R (2026-09-03 추출)
#   .fkeys 가 이 파일과 reinforce_auto_run.R 에 중복 정의돼 있었고, 커버리지 색인이
#   세 번째 복제본을 만들 참이었다. 서명이 갈리면 "같은 포트폴리오" 판정이 소비자마다 달라진다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE))
PROG <- fromJSON(PROG_P, simplifyVector = FALSE)
led <- rf_load(1L, ROOT)
act <- Filter(function(e) identical(e$status, "active"), led$entries)
if (!length(act)) { jlog("halt_no_active_entry"); return(0L) }
E <- act[[1]]; BID <- E$base_id
used <- as.integer(E$attempts_used %||% 0L); MAXA <- as.integer(led$max_attempts %||% 25L)
cells <- do.call(c, lapply(PROG$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))

# ★미측정(등록만 된) 칸 — **소진 판정보다 먼저** 본다. 등록됐는데 실행이 실패한 칸을
#   exhausted 로 넘기면 그 칸이 영구 소실된다(2026-08-30 실사고: 워커 4개 미기동으로 17~20 이 빈 채 소비).
# ★단 terminal 로 닫힌 칸은 제외한다. 재개는 *일시적* 실패만 상정한 장치였는데, 구조적 실패
#   (같은 스펙이면 같은 자리에서 죽는 것)에는 출구가 없어 루프가 제자리를 돌았다
#   (2026-08-31 실사고: B3_11 이 00:16~07:46 사이 16회 동일 실패, used 15 고정).
#   terminal 은 성공 위장이 아니다 — essence 는 여전히 없고, 재개 대상에서만 빠진다.
pending <- Filter(function(a) (is.null(a$essence) || is.null(a$essence$port_t)) && !isTRUE(a$terminal),
                  E$attempts)

if (!length(pending) && used >= MAXA) { jlog("halt_exhausted_delegate", used = used)
  # ★Windows 에서 system2(env=) 는 무시된다(실측 2026-08-30: 자식이 로그 한 줄도 안 남겼다).
  #   부모 환경에 심어 자식이 상속하게 한다.
  Sys.setenv(QVEST_RF_CLAIM_HELD = "1")
  on.exit(Sys.unsetenv("QVEST_RF_CLAIM_HELD"), add = TRUE)
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_run.R")),
          wait = TRUE)
  Sys.unsetenv("QVEST_RF_CLAIM_HELD"); return(0L) }

# 기저 논문 — 전략의 출처. B1 등록부 셀(계열 맵에 없는 계열)과 B5 오버레이 셀의 근거로 쓴다.
# ★배치 선정보다 **앞에** 둔다 — B1 picker 가 fallback_paper 로 받아야 하기 때문이다.
.base_paper <- tryCatch({
  ap <- file.path(E$base_artifacts %||% "", "authoritative_remeasure.json")
  if (nzchar(ap) && file.exists(ap)) fromJSON(ap, simplifyVector = FALSE)$replication$source_paper else NULL
}, error = function(e) NULL)

# ── ★블록 순서 적응 (C층 · 도훈 승인 2026-09-03) ─────────────────────────────
#   실측 근거: B1 승자 port_t 1.578 위에 오버레이를 마지막에 얹자 다섯 칸이 -0.78~0.72 로 무너졌다.
#   구판 순서는 **오버레이 없는 구성**을 최적화한 뒤 위험 통제를 나중에 붙인다 —
#   그런데 출하되는 구성에는 오버레이가 있다. 최적화 대상과 출하 대상이 어긋나 있었다.
#   규칙은 사전 선언(rf_block_order_decide)이고, 결정은 다음 배치 **전에** 원장에 한 번만 쓴다.
.blk_order <- as.character(E$block_order %||% character(0))
if (!length(.blk_order) && used >= 5L && !length(pending)) {
  .dec <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_lesson.R"), local = TRUE))
    rf_block_order_decide(E, PROG, root = ROOT)
  }, error = function(e) { jlog("block_order_decide_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.dec) && length(.dec$order)) {
    ok_rec <- tryCatch({ rf_record_block_order(1L, BID, .dec$order, .dec$reason,
                                               adaptive = isTRUE(.dec$adaptive), root = ROOT); TRUE },
                       error = function(e) { jlog("block_order_record_failed", err = conditionMessage(e)); FALSE })
    if (isTRUE(ok_rec)) {
      .blk_order <- .dec$order
      jlog("block_order_decided", order = paste(.dec$order, collapse = ">"),
           adaptive = isTRUE(.dec$adaptive), reason = substr(.dec$reason, 1, 130))
    }
  }
}
if (length(.blk_order)) {
  # 안정 정렬 — 블록 안 칸 순서는 그대로. 소비된 B1 은 순서 1이라 자리를 지킨다.
  .bk  <- vapply(cells, function(c) as.character(c$block %||% ""), character(1))
  .rnk <- match(.bk, .blk_order); .rnk[is.na(.rnk)] <- 99L
  cells <- cells[order(.rnk, seq_along(cells))]
}

# ── ★블록 경계 강제: 같은 블록 안에서만 묶는다 (재개분이 없을 때만 신규 배치) ──
batch <- list(); first <- NULL
if (!length(pending) && used < length(cells)) {
  # ★커서는 개수가 아니라 **아직 자리가 빈 셀 코드**에서 뽑는다 (2026-09-04 · 정본 rf_spec_sig.R).
  #   구판 `cells[[used + 1L]]` 은 등록 거부 1건에 격자 위치가 영구히 어긋났다 —
  #   그 칸은 영영 안 재고 다른 칸이 두 번 탄다(실측 사연은 rf_spec_sig.R 주석).
  .free <- .rf_free_cells(cells, E$attempts)
  if (!length(.free)) { jlog("halt_no_free_cell", used = used,
                             taken = length(.rf_taken_codes(E$attempts, cells))); return(0L) }
  first <- cells[[.free[1]]]
  for (k in .free) {
    if (length(batch) >= NPAR) break
    if (!identical(cells[[k]]$block, first$block)) break
    batch[[length(batch) + 1L]] <- cells[[k]]
  }
  # ★예산 축이 둘이다 — 하루 상한과 25칸 상한. 상한을 넘겨 등록하면 원장이 거부하고,
  #   그 거부가 곧 격자 훼손이었다. 넘길 일을 애초에 만들지 않는다.
  room <- max(0L, min(DAILY_CAP - done_today, MAXA - used))
  if (length(batch) > room) batch <- batch[seq_len(room)]

# ★B1(멀티팩터) 칸도 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**
#   (도훈 2026-09-01). 구판은 팩터 5종이 격자에 문자로 박혀 있어 **모든 논문이 같은 5팩터**를
#   썼다 — 331종을 등록해 두고 5종만 쓴 셈이다. 격자의 B1 cells 는 스냅샷일 뿐 정본이 아니다.
#   ★시드 오프셋 = 원장 누적 entry 수. 이게 없으면 그리디가 결정론이라 전 논문이 같은 사슬을
#     받아 총 조합이 entry 수와 무관하게 5개로 고정된다(계열 라운드로빈으로 회전).
if (length(batch) && identical(first$block, "B1")) {
  .done_fsets <- unique(unlist(lapply(E$attempts, function(a) {
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
    s0 <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(s0)) NULL else paste(sort(vapply(.rp_all_factors(s0),
      function(f) as.character(f$id %||% ""), character(1))), collapse = "+")
  })))
  .fp <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R")))
                    rf_pick_factor_sets(length(batch), exclude = .done_fsets %||% character(0),
                                        seed_offset = length(led$entries),
                                        depths = unlist(PROG$blocks[[1]]$depths %||% list()),
                                        fallback_paper = .base_paper, root = ROOT) },
                  error = function(e) { jlog("factor_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.fp) && length(.fp$cells)) {
    for (j in seq_along(batch)) if (j <= length(.fp$cells)) {
      .c <- .fp$cells[[j]]; .c$code <- batch[[j]]$code; .c$block <- "B1"; .c$axis <- "multifactor"
      batch[[j]] <- .c
    }
    jlog("factor_arms_picked", seed = .fp$seed_id, offset = .fp$seed_offset,
         chain = paste(.fp$picked_ids, collapse = ","), pool = .fp$n_available,
         max_rho = round(.fp$max_rho %||% NA_real_, 4), asof = .fp$substrate_asof,
         excl_no_ic = length(.fp$excluded_no_ic), excl_axis = length(.fp$excluded_axis))
  } else {
    jlog("factor_arms_fallback", note = "picker 미산출 — 격자 스냅샷 셀로 진행(측정은 계속된다)")
  }
}

# ★B5(오버레이) 칸은 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**
#   (도훈 2026-08-30 "오버레이 방법론을 특정하는건 별로인데"). 이미 측정한 팔은 제외하므로
#   승격 사슬·다음 논문에서 같은 다섯 개를 반복 측정하지 않는다. 격자의 B5 cells 는 스냅샷일 뿐이다.
if (length(batch) && identical(first$block, "B5")) {
  # ★중첩(v10.2) 이후 overlay 는 단수 객체 또는 층 리스트다. 구판 s$overlay$arm_id 는
  #   리스트에서 NULL 을 내 제외 목록이 통째로 비고, 이미 측정한 팔이 다시 뽑힌다.
  .arm_ids <- .ov_arm_ids   # 정본 = rf_spec_sig.R
  .done_arms <- unique(c(
    unlist(lapply(E$attempts, function(a) {
      sp <- a$essence$spec
      if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
      s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
      if (is.null(s)) NULL else .arm_ids(s$overlay)
    })),
    # ★carry 에 이미 깔린 팔도 제외한다 — 같은 팔을 또 뽑으면 .ov_stack 이 중복을 지워
    #   그 칸이 무처치로 닫힌다(측정 0으로 칸 하나 소각).
    .arm_ids(E$carry$overlay)))
  .done_arms <- .done_arms[nzchar(.done_arms)]
  .pk <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_arms.R")))
                    rf_pick_overlay_arms(length(batch), exclude = .done_arms %||% character(0), root = ROOT) },
                  error = function(e) { jlog("overlay_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.pk) && length(.pk$cells)) {
    for (j in seq_along(batch)) if (j <= length(.pk$cells)) {
      .c <- .pk$cells[[j]]; .c$code <- batch[[j]]$code; .c$block <- "B5"; .c$axis <- "risk_overlay"
      batch[[j]] <- .c
    }
    jlog("overlay_arms_picked", ids = paste(.pk$picked_ids, collapse = ","),
         excluded = paste(.done_arms %||% character(0), collapse = ","))
  }
}
# ★B2(비중) 칸도 등록부에서 뽑는다 (2026-09-03). B1·B5 와 같은 형태 —
#   격자의 B2 cells 는 스냅샷일 뿐이고, 이미 측정한 label 은 제외해 반복 측정을 막는다.
#   구판은 이 호출이 아예 없어 카탈로그 52종이 격자에 한 번도 닿지 않았다.
if (length(batch) && identical(first$block, "B2")) {
  .done_wt <- unique(unlist(lapply(E$attempts, function(a) {
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
    s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(s)) NULL else (s$weighting$label %||% s$weighting$catalog_id)
  })))
  .wk <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_weight_arms.R")))
                    rf_pick_weight_arms(length(batch), exclude = .done_wt %||% character(0)) },
                  error = function(e) { jlog("weight_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.wk) && length(.wk$cells)) {
    for (j in seq_along(batch)) if (j <= length(.wk$cells)) {
      .c <- .wk$cells[[j]]; .c$code <- batch[[j]]$code; .c$block <- "B2"; .c$axis <- "weighting"
      batch[[j]] <- .c
    }
    jlog("weight_arms_picked",
         ids = paste(vapply(.wk$cells, function(c) as.character(c$weighting$label %||% ""), character(1)),
                     collapse = ","),
         excluded = paste(.done_wt %||% character(0), collapse = ","))
  }
}
  if (!length(batch)) { jlog("halt_no_room", room = room); return(0L) }
  jlog("batch_start", block = first$block, n_cells = length(batch),
       codes = paste(vapply(batch, function(c) c$code, character(1)), collapse = ","))
}

# ── 승자 해석 (배치 전체가 같은 승자 위에 선다) ───────────────────────────────
.metric <- function(a, key) { es <- a$essence
  if (is.list(es) && !is.null(es[[key]])) as.numeric(es[[key]]) else NA_real_ }
.cell_by_code <- function(cd) { k <- which(vapply(cells, function(c) identical(c$code, cd), logical(1)))
  if (length(k)) cells[[k[1]]] else NULL }
.winner_of <- function(bid, by = "port_t") {
  idx <- which(vapply(cells, function(c) identical(c$block, bid), logical(1)))
  cand <- Filter(function(a) { if (is.null(a$essence)) return(FALSE); cd <- a$essence$cell_code
    if (!is.null(cd) && nzchar(cd)) startsWith(cd, paste0(bid, "_")) else (a$n %in% idx) }, E$attempts)
  if (!length(cand)) return(NULL)
  v <- vapply(cand, function(a) .metric(a, by), numeric(1)); if (all(is.na(v))) return(NULL)
  w <- cand[[which.max(replace(v, !is.finite(v), -Inf))]]; cd <- w$essence$cell_code
  # ★승자는 **측정된 spec 파일**에서 읽는다 — 격자에서 코드로 조회하면 안 된다(2026-09-01).
  #   B1·B5 셀은 이제 배치 시점에 등록부에서 뽑히므로 **격자에 존재하지 않는다**.
  #   격자를 조회하면 실제로 이긴 구성이 아니라 스냅샷 셀이 나오고, B2/B3/B4 가 이기지도 않은
  #   구성 위에 서게 된다. 격자를 손보는 순간 조용히 엇갈리는 것과 같은 계통의 병이다.
  #   spec 은 factors/weighting/universe/overlay/root_paper 를 그대로 들고 있어 드롭인이다.
  out <- NULL
  .sp <- w$essence$spec
  if (!is.null(.sp) && nzchar(.sp) && file.exists(.sp))
    out <- tryCatch(fromJSON(.sp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(out) && !is.null(cd) && nzchar(cd)) out <- .cell_by_code(cd)   # 구 entry 폴백
  if (is.null(out) && w$n <= length(cells)) out <- cells[[w$n]]
  # 승자의 지표를 함께 실어 보낸다 — 채택 여부(기준선 초과)를 호출부가 판정할 수 있게.
  if (!is.null(out)) attr(out, "best_val") <- max(replace(v, !is.finite(v), -Inf))
  out
}

# ── ★carry 기준선 게이트 (도훈 지시 2026-08-31 "기준선 미달이면 carry 유지") ──
#   승계 entry 의 기준선은 **부모 승자 성능**이다. 블록 승자가 그걸 못 넘었다면 그 블록은
#   개선을 찾지 못한 것이고, 그런 승자를 다음 블록에 얹으면 뒤 블록 전체가 **더 나쁜 구성**
#   위에서 측정된다. 실측 2026-08-31: 기저 신호가 강한 논문에서 팩터를 하나 얹으면 등가중
#   컴포짓이 기저 가중을 1/2 -> 1/3 로 낮춰, B1 다섯 칸 어느 것도 기준선(2.63)을 못 넘었다
#   (최고 0.814). 그런데도 승자를 얹으면 B2~B4 가 전부 희석된 구성 위에서 돈다.
#   ★carry 가 없는 최초 entry 에는 기준선이 없다 — 항상 채택한다(게이트 무발화).
.carry_base <- if (!is.null(E$carry)) suppressWarnings(as.numeric(E$parent$best_port_t %||% NA)) else NA_real_
.beats_carry <- function(w, tag) {
  if (is.null(w) || !is.finite(.carry_base)) return(TRUE)
  bv <- suppressWarnings(as.numeric(attr(w, "best_val") %||% NA))
  okv <- is.finite(bv) && bv > .carry_base
  if (!okv) jlog("winner_below_carry_base", block = tag, best_val = bv, carry_base = .carry_base,
                 note = "블록이 개선을 못 찾음 — 그 축은 carry 유지(승자 미채택)")
  okv
}
.blk <- if (!is.null(first)) first$block else "B4"   # 재개분은 스펙이 이미 있어 승자를 다시 안 쓴다
w1 <- if (!identical(.blk, "B1")) .winner_of("B1", "port_t") else NULL
if (!length(pending) && !identical(.blk, "B1") && is.null(w1)) {
  jlog("halt_no_b1_winner", block = .blk); return(1L) }
w2 <- .winner_of("B2", "port_t"); w3 <- .winner_of("B3", "calmar")

# ★B5 승자의 오버레이 — .winner_of 가 이미 승자의 spec 을 돌려주므로 그 안의 overlay 를 쓴다.
#   (격자 B5 cells 는 스냅샷이라 실제로 돈 arm 과 다를 수 있다 — 승자 기준 = calmar,
#    오버레이의 목적이 낙폭이기 때문이다. 격자 B5.select_winner_by 와 정합.)
w5 <- .winner_of("B5", "calmar")
.w5_overlay <- w5$overlay

# 승자의 팩터 축을 집합으로 정규화 — 등록부 셀은 factors(복수), 구 격자 셀은 factor2(단수)
.win_factors <- function(w) {
  if (is.null(w)) return(NULL)
  if (!is.null(w$factors) && length(w$factors)) return(w$factors)
  if (!is.null(w$factor2)) return(list(w$factor2))
  NULL
}

# ★B5(오버레이)는 블록 승자가 아니라 **지금까지의 전체 최고 구성** 위에 얹는 층이다.
#   격자 셀은 자기가 바꾼 축만 들고 있으므로(예: B3_12 는 universe 만) 승자의 **실제 스펙 파일**을
#   읽어 그대로 깐다 — 그래야 "그 전략에 오버레이를 얹었을 때" 를 재는 것이 된다.
.wbest_spec <- NULL
{ .cd0 <- Filter(function(a) !is.null(a$essence), E$attempts)
  if (length(.cd0)) {
    .v0 <- vapply(.cd0, function(a) .metric(a, "port_t"), numeric(1))
    if (!all(is.na(.v0))) {
      .w0 <- .cd0[[which.max(replace(.v0, !is.finite(.v0), -Inf))]]
      .sp0 <- .w0$essence$spec
      if (!is.null(.sp0) && nzchar(.sp0) && file.exists(.sp0))
        .wbest_spec <- tryCatch(fromJSON(.sp0, simplifyVector = FALSE), error = function(e) NULL)
    } } }

# ── ①-0 재개 검사: 등록됐으나 essence 없는 칸이 있으면 **그 칸부터 다시 실행**한다 ──
#   병렬은 등록 → 실행 순서라 실행이 실패하면 칸이 측정 없이 소비된다.
#   재개가 없으면 무인 상태에서 실패 1회 = 칸 영구 소실 (2026-08-30 실사고).
jobs <- list()
if (length(pending)) {
  jlog("resume_pending", n_pending = length(pending),
       ns = paste(vapply(pending, function(a) as.character(a$n), character(1)), collapse = ","))
  for (a in pending) {
    cd <- a$essence$cell_code %||% NULL
    CELL <- if (!is.null(cd)) .cell_by_code(cd) else (if (a$n <= length(cells)) cells[[a$n]] else NULL)
    if (is.null(CELL)) { jlog("resume_skip_unknown_cell", n = a$n); next }
    # entry 별 spec 이 정본. 구 이름(spec_<code>.json)은 이 수리 이전 entry 호환용 폴백이다.
    sp <- file.path(WDIR, sprintf("spec_%s__%s.json", CELL$code, substr(BID, 1, 48)))
    if (!file.exists(sp)) sp <- file.path(WDIR, sprintf("spec_%s.json", CELL$code))
    if (!file.exists(sp)) { jlog("resume_skip_no_spec", n = a$n, code = CELL$code); next }
    jobs[[length(jobs) + 1L]] <- list(n = as.integer(a$n), code = CELL$code, spec = sp,
      name = sprintf("RF_PAR_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
      out = file.path(WDIR, sprintf("result_%s.json", CELL$code)))
  }
  if (length(jobs) > NPAR) jobs <- jobs[seq_len(NPAR)]
}

# ── ① 사전 등록 (순차 — 원장 단독 접근). 재개분이 있으면 건너뛴다 ────────────
# ★이미 측정된 칸들의 서명. 새 칸이 여기 걸리면 같은 포트폴리오를 다시 재는 것이다.
.seen_sig <- list()
for (.a in E$attempts) {
  .sp <- .a$essence$spec
  if (is.null(.sp) || !nzchar(.sp) || !file.exists(.sp)) next
  .so <- tryCatch(fromJSON(.sp, simplifyVector = FALSE), error = function(z) NULL)
  if (!is.null(.so)) .seen_sig[[.spec_sig(.so)]] <- .a$essence$cell_code %||% paste0("n", .a$n)
}
if (!length(jobs)) for (CELL in batch) {
  .no_treatment <- FALSE
  SPEC <- list(code = CELL$code, label = CELL$label, block = CELL$block,
               fixed_axes = PROG$fixed_axes,
               # ★기저 신호는 원장의 충실구현 engine_path 에서 물려받는다 — 논문이 바뀌면 기저도 바뀐다.
               #   경로가 없거나 파일이 없으면 mom_12_1 로 떨어진다(구 entry 하위호환).
               # ★entry 가 base_signal 을 명시하면 그것이 정본이다(결합 entry 는 engine_blend 로
               #   엔진 두 개를 물린다). 명시가 없을 때만 engine_path 하나로 떨어진다 —
               #   구판은 이 분기가 없어 결합 entry 가 단일 엔진으로 **조용히** 돌 뻔했다.
               base_signal = if (!is.null(E$base_signal)) E$base_signal else { .ep <- E$engine_path %||% ""
                 if (nzchar(.ep) && file.exists(.ep)) list(kind = "engine", path = .ep)
                 else list(kind = "mom_12_1") },
               # ★기저 가중 — 등가중이면 팩터 n개에서 논문신호가 1/(1+n) 로 떨어져 결합 깊이와
               #   기저 희석이 교락된다. 격자 fixed_axes 가 정본이고 엔진은 값이 없으면 등가중이다.
               base_weight = PROG$fixed_axes$base_weight,
               # ★팩터 축은 **집합**이다(2026-09-01). 등록부 셀은 factors(복수)를 들고 오고,
               #   구 격자 셀의 factor2(단수)는 길이 1 집합으로 정규화한다.
               factors = (if (!is.null(CELL$factors) && length(CELL$factors)) CELL$factors
                          else if (!is.null(CELL$factor2)) list(CELL$factor2)
                          else if (.beats_carry(w1, "B1")) .win_factors(w1) else NULL),
               weighting = CELL$weighting %||% list(kind = "ew"),
               universe = CELL$universe %||% list(kind = "k200_kq150"))
  if (identical(CELL$block, "B3")) SPEC$weighting <- list(kind = "ew")
  if (identical(CELL$block, "B4")) {
    use <- unlist(CELL$combo$use)
    # ★B4 에는 carry 기준선 게이트를 걸지 않는다. 게이트의 취지는 "개선 못 찾은 승자를
    #   **다음 탐색의 바닥**으로 깔지 말라" 인데(B2·B3 가 B1 위에 서는 자리), B4 는 탐색이
    #   아니라 **분해**다 — 축을 합치고 하나씩 빼서 기여를 가른다. 승자가 기준선을 못
    #   넘었어도 합쳤을 때 어떤지가 이 블록이 재려는 값이다.
    #   ★2026-08-31 실사고: 게이트를 여기까지 걸었더니 아무것도 안 얹혀 네 칸이 같은 t(2.241)를 냈다.
    # ★2026-09-01 4축으로 확장 — 구판은 3축(팩터·비중·유니버스)만 봤는데 그 부분집합 격자는
    #   이미 완비였다(단일 = 각 블록 승자 · 쌍 = LOO · 전체 1). 빈 곳은 칸이 아니라 축이고,
    #   그 축은 오버레이다: A 를 막는 것이 낙폭인데 구판 B4 는 오버레이를 보지 않았다.
    SPEC$factors   <- if ("B1" %in% use) .win_factors(w1) else NULL
    SPEC$weighting <- if ("B2" %in% use && !is.null(w2)) (w2$weighting %||% list(kind="ew")) else list(kind = "ew")
    SPEC$universe  <- if ("B3" %in% use && !is.null(w3)) (w3$universe  %||% list(kind="k200_kq150")) else list(kind = "k200_kq150")
    # ★B5 승자 스펙은 이미 carry 를 포함한 중첩판이라 그대로 쓴다(이중 적용 없음).
    #   B5 를 뺀 칸도 부모의 오버레이는 기저로 남겨야 LOO 대조가 성립한다 —
    #   안 그러면 "B5 제외" 가 이 세대 처치와 부모 위험통제를 동시에 벗기는 두 겹 처치가 된다.
    SPEC$overlay   <- if ("B5" %in% use) .w5_overlay else (E$carry$overlay %||% NULL)
    SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
    jlog("b4_axes", code = CELL$code, use = paste(use, collapse = "+"),
         f = length(SPEC$factors %||% list()), w = SPEC$weighting$kind %||% "?",
         u = SPEC$universe$kind %||% "?", ov = SPEC$overlay$arm_id %||% "none")
  }
  # ── ★승격 entry 의 carry 병합 (도훈 지시 2026-08-30 "B등급 이상 추가 강화") ──
  #   승격은 B+ 를 낸 승자 구성을 **기저로 물려받아** 그 위에서 25칸을 다시 탐색한다.
  #   기저 신호(engine_path)는 그대로다 — 바뀌는 것은 그 위에 깔린 팩터·비중·유니버스다.
  #   축 소유권: 자기 축을 탐색하는 블록은 carry 를 덮는다(B2=비중 · B3=유니버스),
  #   B4 는 **이 entry 안의 승자**를 조합하는 블록이라 carry 가 그 선택을 덮지 않는다.
  if (!is.null(E$carry)) {
    .cur <- SPEC$factors
    if (is.null(.cur)) {
      .cur <- list()
      if (!is.null(SPEC$factor2) && !identical(SPEC$factor2$kind, "none")) .cur <- c(.cur, list(SPEC$factor2))
      if (!is.null(SPEC$factor3)) .cur <- c(.cur, list(SPEC$factor3))
    }
    # ★중복 제거. 스코어는 rowMeans(zb, z1, z2, ...) 등가중이라 같은 팩터가 두 번 들어가면
    #   **기저 신호 가중이 조용히 깎인다**(1/2 -> 1/3). 실측 2026-08-31: 부모 B3_12
    #   factors=[Amihud] PORT_t 2.63 -> 자식 factors=[Amihud,Amihud] 2.251, 기저 캐시 md5 동일.
    #   승계가 물려받은 구성을 희석하면 promote 조건(부모 최고 초과)은 원리상 만족될 수 없다.
    SPEC$factors <- .dedup_factors(c(E$carry$factors %||% list(), .cur))
    SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
    if (!(CELL$block %in% c("B2", "B4")) && !is.null(E$carry$weighting)) SPEC$weighting <- E$carry$weighting
    if (!(CELL$block %in% c("B3", "B4")) && !is.null(E$carry$universe))  SPEC$universe  <- E$carry$universe
    # ★2026-09-03 오버레이 승계 — 구판은 이 줄이 없었다. weighting/universe 는 물려받는데
    #   overlay 만 안 물려받아, 승격된 자식의 B1/B2/B3 는 부모의 위험 통제가 벗겨진 채 돌았다.
    #   팩터는 누적(.dedup_factors)되는데 오버레이는 세대마다 0 으로 리셋된 것이다.
    #   B5 는 자기 축이라 아래에서 **중첩**으로 처리하고, B4 는 부분집합 조립이라 제외한다.
    if (!(CELL$block %in% c("B5", "B4")) && !is.null(E$carry$overlay)) SPEC$overlay <- E$carry$overlay
  }
  # ★B5 오버레이 — 전체 최고 구성을 그대로 깔고 그 위에 노출 스케일만 얹는다
  if (identical(CELL$block, "B5")) {
    if (!is.null(.wbest_spec)) {
      SPEC$factors   <- .wbest_spec$factors
      SPEC$factor2   <- .wbest_spec$factor2
      SPEC$factor3   <- .wbest_spec$factor3
      SPEC$weighting <- .wbest_spec$weighting %||% list(kind = "ew")
      SPEC$universe  <- .wbest_spec$universe  %||% list(kind = "k200_kq150")
    }
    # ★중첩 — carry 의 오버레이를 지우지 않고 그 위에 이 칸의 arm 을 얹는다(v10.2).
    #   구판은 덮어쓰기라 부모가 낙폭을 30% 깎아 승격됐어도 자식 B5 는 그 30% 를 버리고
    #   처음부터 다시 깎았다. 노출은 곱으로 합성된다(rf_cell_engine .ov_compose).
    SPEC$overlay <- .ov_stack(E$carry$overlay, CELL$overlay)
    SPEC$overlay_basis <- CELL$basis %||% ""
    if (!is.null(.base_paper)) SPEC$root_paper <- .base_paper
  }
  # ★무처치 판정은 **조립이 끝난 뒤** 한다. 구판은 carry 병합 블록 안에서 쟀는데,
  #   B5(오버레이)는 그 뒤에 overlay 를 붙이므로 판정 시점엔 팩터·비중·유니버스가 carry 와
  #   같아 전부 "무처치" 로 닫혔다 — 정작 처치인 오버레이가 아직 없을 때 판정한 것이다.
  #   2026-08-31 실사고: B5 다섯 칸이 측정 0건으로 소비돼 25 소진이 찍히고 다음 논문으로
  #   넘어갔다. 계기가 재려는 것(처치가 있나)이 아니라 재기 쉬운 것(그 시점 세 축)을 쟀다.
  #   ★overlay 는 carry 에 없는 축이므로, 오버레이가 붙은 칸은 자동으로 처치 있음이 된다.
  if (!is.null(E$carry)) {
    .no_treatment <- identical(.fkeys(SPEC$factors), .fkeys(E$carry$factors %||% list())) &&
      .same_axis(SPEC$weighting, E$carry$weighting %||% list(kind = "ew")) &&
      .same_axis(SPEC$universe,  E$carry$universe  %||% list(kind = "k200_kq150")) &&
      .same_axis(SPEC$overlay,   E$carry$overlay   %||% list())
  }
  # ★근거 논문 (2026-09-02 수리). 구판의 폴백 사슬(셀 논문 → B1 승자 논문)은
  #   ①B1 이 시드 계열 논문 하나만 붙이고(사슬이 접두 집합 → 4계열 컴포짓 5칸 전부 Amihud 2002)
  #   ②B5 는 자체 논문이 없어 **B1 승자 논문을 차용**했다 — 낙폭 브레이크가 유동성 논문을 인용했고,
  #     위 B5 분기가 넣은 기저 논문(SPEC$root_paper <- .base_paper)은 여기서 덮어써져 죽은 코드였다.
  #   그래서 "같은 root_papers 3회 연속" WARN 이 20칸 연속 발화했다 — 표기 결함을 재고 있었다.
  #   현행: source_paper(단수) = **기저 논문**(이 entry 가 강화하는 논문 — 모든 셀은 그 변형이다).
  #         원장 root_papers(복수) = 기저 + 셀 자체 처치 논문(B2 비중·B3 유니버스) + 팩터 **전 계열** 논문
  #         (+ risk_overlay 는 method 항목 선두). 매핑 없는 계열은 버리지 않고 이름으로 남긴다.
  rp <- .base_paper %||% CELL$root_paper %||% w1$root_paper
  SPEC$root_paper <- rp
  .rpz <- tryCatch({
    if (!exists("rf_root_papers_for")) suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R")))
    rf_root_papers_for(SPEC, base_paper = rp, cell_paper = CELL$root_paper, root = ROOT)
  }, error = function(e) { jlog("root_papers_failed", code = CELL$code, err = conditionMessage(e))
    list(papers = Filter(function(z) is.list(z) && nzchar(as.character(z$url %||% "")), list(rp, CELL$root_paper)),
         families = character(0), unmapped_families = character(0)) })
  .root_papers <- .rpz$papers
  if (identical(CELL$axis, "risk_overlay"))
    .root_papers <- c(list(list(method = CELL$basis %||% CELL$label, url = rp$url %||% "")), .root_papers)
  SPEC$root_papers <- .root_papers
  SPEC$root_paper_families <- .rpz$families
  SPEC$unmapped_families <- .rpz$unmapped_families
  if (length(.rpz$unmapped_families))
    jlog("root_paper_unmapped_family", code = CELL$code, families = paste(.rpz$unmapped_families, collapse = ","))
  # ★sprintf 영길이 붕괴 방어 (2026-09-03). 인자 하나가 NULL/character(0)/NA 면 sprintf 는
  #   경고 없이 character(0) 을 돌려주고, 그 값이 원장에 idea=[] 로 박힌다.
  #   모든 조각을 길이 1 문자열로 강제한 뒤에만 조립한다.
  .s1 <- function(x, alt = "?") {
    x <- suppressWarnings(as.character(x))
    if (!length(x) || is.na(x[[1L]]) || !nzchar(x[[1L]])) alt else x[[1L]]
  }
  SPEC$idea <- sprintf("[무인 병렬 %s] %s — %s/%s · factor2=%s · weighting=%s · universe=%s",
                       .s1(CELL$code), .s1(CELL$label), .s1(CELL$block), .s1(CELL$axis),
                       .s1(SPEC$factor2$id %||% SPEC$factor2$kind, "none"),
                       .s1(SPEC$weighting$kind, "ew"), .s1(SPEC$universe$kind, "k200_kq150"))
  # ★지식 주입(착수 전 의무) — hypothesis_index 죽은 선례 + 직전 교훈. 차단 아님, 기록.
  SPEC <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_preflight.R"))
                     rf_preflight(SPEC, BID) },
                   error = function(e) { jlog("preflight_failed", code = CELL$code, err = conditionMessage(e)); SPEC })
  .pf <- SPEC$preflight
  if (!is.null(.pf) && length(.pf$dead_precedents))
    jlog("preflight_dead_precedent", code = CELL$code,
         kw = paste(names(.pf$dead_precedents), collapse = ","),
         note = "죽은 선례 존재 — 실행은 진행(AX-000: 사실 기록이지 금지 목록 아님)")
  # ★spec 경로에 entry 식별자를 넣는다. 구판은 spec_<code>.json 고정이라 다음 entry 가
  #   같은 이름으로 덮어썼고, 원장이 그 경로를 가리키는 채로 **부모 스펙이 소실**됐다
  #   (2026-08-31: 부모 B3_12 의 spec 을 열면 자식 것이 나온다 — 사후 재현 불가).
  sp <- file.path(WDIR, sprintf("spec_%s__%s.json", CELL$code, substr(BID, 1, 48)))
  # ★등록이 먼저다 (2026-09-03). 구판은 spec 을 먼저 쓰고 등록을 시도해서, 거부된 칸의
  #   산출물이 디스크에 남았다(실측: spec 5 vs 원장 4 — 산출물만 보면 5칸을 돈 것처럼 보인다).
  #   원장이 정본이므로 원장에 없는 칸의 흔적을 남기지 않는다.
  att <- tryCatch(rf_append_attempt(1L, BID, SPEC$idea, CELL$axis, .root_papers, wt_id = NULL, root = ROOT,
                                    unmapped_families = .rpz$unmapped_families,
                                    # ★실제 적재 여부를 넘긴다 — 상수 TRUE 는 거짓 기록이었다
                                    axiom_injected = isTRUE(SPEC$preflight$axiom_injected),
                                    # ★격자 좌표를 등록 시점에 박는다 — 커서의 정본(2026-09-04)
                                    cell_code = CELL$code),
                  error = function(e) { jlog("append_failed", base_id = BID, code = CELL$code,
                                             err = conditionMessage(e)); NULL })
  if (is.null(att)) {
    unlink(sp, force = TRUE)
    # ★거부된 칸은 자리를 잃지 않는다 — 커서가 코드 집합 기반이라 다음 tick 에 다시 잡힌다.
    #   다만 같은 사유로 계속 거부되면 근면하게 제자리를 돌 뿐이므로 상한에서 멈춰 세운다.
    .afc <- .append_fail_count(CELL$code, BID)
    if (.afc >= MAX_RETRY) {
      jlog("halt_append_stuck", code = CELL$code, fails = .afc,
           note = "등록 반복 거부 — 조용히 건너뛰지 않는다. 거부 사유를 고치고 재개할 것")
      break
    }
    next
  }
  write(toJSON(SPEC, auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
  # ★중복 판정 — 배치 안 · entry 안 · **전 entry**(2026-09-03 확장) 세 층을 본다.
  #   먼저 온 칸 하나는 측정하고 나머지를 닫는다. 같은 포트폴리오에 다른 이름을 붙이지 않는다.
  #   전 entry 층을 넓힌 근거: 258 측정 중 고유 서명 230 — 28칸이 이미 잰 구성의 재측정이었고
  #   한 구성은 3개 entry 에 걸쳐 7회 반복됐다. 25칸 예산에서 그만큼이 그냥 날아간 것이다.
  .sig <- .spec_sig(SPEC)
  .dup <- .seen_sig[[.sig]]
  if (is.null(.dup) && !isTRUE(.no_treatment)) {
    .xh <- tryCatch({
      if (!exists(".COVIDX")) {
        suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_coverage.R"), local = TRUE))
        .COVIDX <<- rf_coverage_index(ROOT)
      }
      rf_coverage_find(.sig, .COVIDX, exclude_base = BID)
    }, error = function(e) { jlog("coverage_lookup_failed", err = conditionMessage(e)); NULL })
    if (!is.null(.xh) && nrow(.xh))
      .dup <- sprintf("%s/%s(전 entry · Grade %s)", .xh$base_id[1], .xh$cell_code[1], .xh$grade[1])
  }
  if (!isTRUE(.no_treatment) && !is.null(.dup)) {
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — 기존 칸과 동일 스펙)",
      lessons = sprintf("%s: 스펙 서명이 %s 과 동일 — 같은 포트폴리오를 다시 재지 않는다", CELL$code, .dup),
      terminal = TRUE,
      terminal_reason = sprintf("스펙 중복(%s 와 동일) — factors=%s weighting=%s universe=%s",
        .dup, paste(.fkeys(SPEC$factors), collapse = "+"),
        SPEC$weighting$kind %||% "?", SPEC$universe$kind %||% "?"),
      root = ROOT)
    jlog("cell_duplicate_spec", n = att$n, code = CELL$code, same_as = .dup,
         note = "기존 칸과 스펙 동일 — 미결 종결(실행 안 함)")
    next
  }
  .seen_sig[[.sig]] <- CELL$code
  if (isTRUE(.no_treatment)) {
    # 원장에는 칸이 남되(격자 번호 대응 유지) 측정은 없다. essence 가 없으므로
    # .winner_of 후보에서 자동으로 빠진다 — 무처치 칸이 승자가 되는 경로가 닫힌다.
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — carry 와 동일·처치 미전달)",
      lessons = sprintf("%s: 중복 제거 후 구성이 carry 와 동일 — 같은 포트폴리오에 다른 이름을 붙이지 않는다", CELL$code),
      terminal = TRUE,
      terminal_reason = sprintf("무처치(carry 동일) — factors=%s weighting=%s universe=%s",
        paste(.fkeys(SPEC$factors), collapse = "+"), SPEC$weighting$kind %||% "?", SPEC$universe$kind %||% "?"),
      root = ROOT)
    jlog("cell_no_treatment", n = att$n, code = CELL$code,
         note = "carry 와 동일 — 미결 종결(실행 안 함)")
    next
  }
  jobs[[length(jobs) + 1L]] <- list(n = as.integer(att$n), code = CELL$code, spec = sp,
    name = sprintf("RF_PAR_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
    out = file.path(WDIR, sprintf("result_%s.json", CELL$code)))
}
if (!length(jobs)) { jlog("halt_no_jobs"); return(1L) }

# ── ② 실행 (병렬 — 워커는 원장 미접근) ────────────────────────────────────────
for (j in jobs) {
  unlink(j$out, force = TRUE)
  # ★stderr 는 파일명/TRUE/FALSE 만 받는다. "2>&1"(셸 관용구)을 넘기면 R 이 **파일명으로 해석**하고
  #   Windows 에서 '>' 는 부정 문자라 실행이 조용히 죽는다(2026-08-30 실사고 — 워커 4개 전부 미기동).
  .wlog <- file.path(WDIR, sprintf("log_%s.txt", j$code))
  system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R")),
                       shQuote(j$spec), j$n, shQuote(j$name), shQuote(j$out)),
          wait = FALSE, stdout = .wlog, stderr = .wlog)
  jlog("worker_spawn", n = j$n, code = j$code)
}
TIMEOUT_S <- as.integer(CFG$worker_timeout_sec %||% 5400L)
t0 <- Sys.time()
repeat {
  ndone <- sum(vapply(jobs, function(j) file.exists(j$out), logical(1)))
  if (ndone >= length(jobs)) break
  if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > TIMEOUT_S) {
    jlog("worker_timeout", done = ndone, total = length(jobs)); break }
  Sys.sleep(20)
}

# ── ③ 결과 수집 (순차 — 원장 단독 접근) ──────────────────────────────────────
# ★fail_count 는 **지금 원장**에서 읽는다. main() 초입의 E 스냅샷은 신규 배치에서
#   등록(rf_append_attempt)보다 앞서 찍혀 그 칸을 아예 모른다 — 스냅샷을 뒤지면
#   재개분에서만 맞고 신규분에서는 subscript 오류로 배치 전체가 fatal 로 떨어진다.
.fail_count_of <- function(n) {
  e <- tryCatch(Filter(function(x) identical(x$base_id, BID), rf_load(1L, ROOT)$entries)[[1]],
                error = function(z) NULL)
  if (is.null(e)) return(0L)
  a <- Filter(function(x) identical(as.integer(x$n), as.integer(n)), e$attempts)
  if (!length(a)) 0L else as.integer(a[[1]]$fail_count %||% 0L)
}
nb <- 0L
for (j in jobs) {
  if (!file.exists(j$out)) {
    .fc0 <- .fail_count_of(j$n)
    .term <- (.fc0 + 1L) >= MAX_RETRY
    rf_record_result(1L, BID, j$n, grade = "NA (등급 미발행 — 병렬 워커 미완료/시간초과)",
                     lessons = sprintf("워커 산출 부재: %s (로그 %s)", j$out, file.path(WDIR, sprintf("log_%s.txt", j$code))),
                     terminal = .term,
                     terminal_reason = if (.term) sprintf("워커 산출 부재 %d회 연속 — 재시도 상한 %d 도달", .fc0 + 1L, MAX_RETRY) else NULL,
                     root = ROOT)
    jlog("cell_missing", n = j$n, code = j$code, fail_count = .fc0 + 1L, terminal = .term); next
  }
  R <- fromJSON(j$out, simplifyVector = FALSE)
  if (!isTRUE(R$ok)) {
    .err <- R$err %||% "?"
    # ★두 종류의 실패를 가른다. 재개는 하나에만 의미가 있다.
    #   ① 구조적(결정론) — rf_cell_engine 의 "측정 무효" 계열. 처치가 전달되지 않았거나
    #      기저가 그 변환을 지지하지 않는다. 스펙이 그대로면 재실행해도 같은 자리에서 죽는다.
    #      이건 실행 실패가 아니라 **판정**이다 — 미결(미측정)로 닫는다.
    #   ② 일시적 — 워커 미기동·시간초과·자원. 재개가 존재하는 이유. 단 무한은 아니다:
    #      같은 칸이 cell_max_retry 회 실패하면 닫는다(무한 루프는 침묵과 같다).
    .structural <- grepl("측정 무효|처치 미전달", .err)
    .fc0 <- .fail_count_of(j$n)
    .term <- .structural || (.fc0 + 1L) >= MAX_RETRY
    .reason <- if (.structural) sprintf("구조적 미결(결정론) — %s", .err)
               else sprintf("일시 실패 %d회 연속 — 재시도 상한 %d 도달: %s", .fc0 + 1L, MAX_RETRY, .err)
    rf_record_result(1L, BID, j$n,
                     grade = if (.structural) "NA (미결 — 처치 미전달·측정 무효)"
                             else "NA (등급 미발행 — 병렬 실행 실패)",
                     lessons = sprintf("%s 실패: %s", j$code, .err),
                     terminal = .term, terminal_reason = if (.term) .reason else NULL,
                     root = ROOT)
    jlog("cell_error", n = j$n, code = j$code, err = .err,
         structural = .structural, fail_count = .fc0 + 1L, terminal = .term); next
  }
  es <- R$essence
  # ★교훈은 지표 되풀이가 아니라 **기전 서술**이다 (2026-09-03). essence 의 숫자를 그대로
  #   옮겨 적으면 한계 정보량이 0이고, 그게 무인 교훈 269건 중 247건(92%)의 상태였다.
  #   무엇이 막았고 carry 대비 위험·수익이 어느 쪽으로 더 움직였는지를 적는다 — LLM 불필요.
  .carry_es <- tryCatch({
    .cw <- Filter(function(a) is.list(a$essence) && !is.null(a$essence$port_t), E$attempts)
    if (length(.cw)) .cw[[length(.cw)]]$essence else NULL
  }, error = function(e) NULL)
  .lsn <- tryCatch({
    source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_lesson.R"))
    rf_lesson_text(j$code, R$grade, es, carry_es = .carry_es, root = ROOT)
  }, error = function(e) sprintf("[%s] Grade %s (기전 서술 생성 실패: %s)",
                                 j$code, R$grade, conditionMessage(e)))
  rf_record_result(1L, BID, j$n, grade = R$grade, essence = es, artifacts = R$artifacts,
    lessons = .lsn, root = ROOT)
  # ★고정 축 사후 검증 — 공리를 주입하는 대신 산출물에서 재도출해 확인한다
  .vf <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_preflight.R"))
                    rf_preflight_verify_axes(file.path(R$artifacts, "authoritative_remeasure.json"),
                                             PROG$fixed_axes) },
                  error = function(e) list(ok = NA, note = conditionMessage(e)))
  if (identical(.vf$ok, FALSE))
    jlog("AXIS_VIOLATION", n = j$n, code = j$code, violations = paste(.vf$violations, collapse = "; "))
  jlog("cell_done", n = j$n, code = j$code, grade = R$grade,
       port_t = es$port_t, calmar = es$calmar, axes_ok = .vf$ok, artifacts = R$artifacts)
  nb <- nb + 1L
  if (identical(R$grade, "A")) {
    jr <- file.path(ROOT, "qepm/mailbox/judge_request.json")
    dir.create(dirname(jr), recursive = TRUE, showWarnings = FALSE)
    write(toJSON(list(requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), source = "reinforce_auto_parallel",
                      base_id = BID, attempt = j$n, cell = j$code, artifacts = R$artifacts, grade = "A"),
                 auto_unbox = TRUE, pretty = TRUE), jr)
  # ★Grade A 는 **리서치를 멈추지 않는다** (도훈 지시 2026-08-30 "A등급 달성하더라도 리서치가 이어지게").
  #   구판은 enabled=false 로 전 루프를 세웠는데, 그건 **리서치 루프**와 **BOOK 등재 관문**을 뒤섞은 것이다.
  #   후보 하나가 A 를 찍었다고 나머지 칸·다음 논문이 설 이유가 없다. A 는 큐에 쌓이고 루프는 계속 돈다.
  #   ★불변: BOOK 등재는 여전히 Judge(PIT) + 도훈 confirm 을 거친다 — 자동 등재는 없다(헌법).
  .aq <- file.path(ROOT, "06_Registry/grade_a_queue.json")
  .q <- if (file.exists(.aq)) tryCatch(fromJSON(.aq, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(.q) || is.null(.q$entries)) .q <- list(schema = "grade_a_queue_v1",
    note = "essence Grade A 후보 대기열. Judge(PIT) 검증 + 도훈 confirm 후 BOOK 등재. 러너는 여기 쌓기만 하고 멈추지 않는다.",
    entries = list())
  .q$entries[[length(.q$entries) + 1L]] <- list(
    queued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), base_id = BID, attempt = j$n,
    cell = j$code, artifacts = R$artifacts, grade = "A", status = "awaiting_judge")
  write(toJSON(.q, auto_unbox = TRUE, pretty = TRUE, null = "null"), .aq)
    jlog("grade_a_queued", n = j$n, code = j$code, note = "루프 계속 — Judge/BOOK 만 confirm 대기")
    tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
               rf_auto_notify(BID, j$n, kind = "grade_a") }, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  }
}

# ── 텔레그램: 블록 경계를 넘었으면 1회 ────────────────────────────────────────
led2 <- rf_load(1L, ROOT)
E2 <- Filter(function(e) identical(e$base_id, BID), led2$entries)[[1]]
u2 <- as.integer(E2$attempts_used %||% 0L)
# ★조건에 `u2 > used` 를 걸면 **재개 경로에서 영영 안 나간다**(재개는 used 가 이미 최종값).
#   2026-08-30 실사고: 17~20 을 재개로 측정하고도 20/20 텔레그램이 0건이었다.
#   판정 축을 "칸 수가 늘었나" 가 아니라 "이번 배치가 실제로 기록했나(nb>0)" 로 바꾼다.
if (nb > 0L && (u2 %% 5L == 0L || u2 >= MAXA)) {
  # ★"보냈다" 를 예외 부재로 지어내지 않는다 — rf_auto_notify 가 실제 발송 결과를 돌려준다.
  #   구판은 429(레이트 리밋)로 메시지가 유실돼도 sent=true 를 기록했다(2026-08-30 실증 9건).
  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   isTRUE(rf_auto_notify(BID, u2, kind = "block")) },
                 error = function(e) { jlog("telegram_failed", err = conditionMessage(e)); FALSE })
  if (!ok) jlog("telegram_send_failed", n = u2,
                note = "발송 실패 — lock 미생성이므로 다음 tick 이 재발송을 시도한다")
  jlog("telegram_block", n = u2, sent = ok)
  # ★L-code 무인 발행 — SKILL §0 "블록당 L-code 1건" 의 소비자가 없었다(러너 2종 emit_lcode 0건).
  #   세션이 안 오면 그 블록의 학습이 원장 밖에서 증발한다. 텔레그램과 같은 생산자를 쓴다.
  lc <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R"))
                   rf_emit_block_lcode(BID, u2, root = ROOT) },
                 error = function(e) { jlog("lcode_failed", err = conditionMessage(e)); NULL })
  jlog("lcode_block", n = u2, l_code = as.character(lc %||% "NA"))
}
jlog("batch_done", block = (if (!is.null(first)) first$block else "resume"), recorded = nb, used = u2)
0L
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
.rel <- if (.CLAIM_HELD) list(ok = TRUE, reason = "inherited") else rf_claim_release(CLAIM)
if (!isTRUE(.rel$ok)) jlog("claim_release_failed", reason = .rel$reason,
     note = "고아 claim 이 남았다 — owner.json 의 pid 가 죽으면 다음 tick 이 즉시 회수한다")
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
