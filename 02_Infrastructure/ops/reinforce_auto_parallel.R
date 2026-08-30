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

CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled"); quit(status = 0) }
NPAR      <- as.integer(CFG$parallel_cells %||% 4L)
DAILY_CAP <- as.integer(CFG$daily_cap %||% 8L)
STALE_H   <- as.numeric(CFG$claim_stale_hours %||% 6)

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
PROG <- fromJSON(PROG_P, simplifyVector = FALSE)
led <- rf_load(1L, ROOT)
act <- Filter(function(e) identical(e$status, "active"), led$entries)
if (!length(act)) { jlog("halt_no_active_entry"); return(0L) }
E <- act[[1]]; BID <- E$base_id
used <- as.integer(E$attempts_used %||% 0L); MAXA <- as.integer(led$max_attempts %||% 20L)
cells <- do.call(c, lapply(PROG$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))

# ★미측정(등록만 된) 칸 — **소진 판정보다 먼저** 본다. 등록됐는데 실행이 실패한 칸을
#   exhausted 로 넘기면 그 칸이 영구 소실된다(2026-08-30 실사고: 워커 4개 미기동으로 17~20 이 빈 채 소비).
pending <- Filter(function(a) is.null(a$essence) || is.null(a$essence$port_t), E$attempts)

if (!length(pending) && used >= MAXA) { jlog("halt_exhausted_delegate", used = used)
  # ★Windows 에서 system2(env=) 는 무시된다(실측 2026-08-30: 자식이 로그 한 줄도 안 남겼다).
  #   부모 환경에 심어 자식이 상속하게 한다.
  Sys.setenv(QVEST_RF_CLAIM_HELD = "1")
  on.exit(Sys.unsetenv("QVEST_RF_CLAIM_HELD"), add = TRUE)
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_run.R")),
          wait = TRUE)
  Sys.unsetenv("QVEST_RF_CLAIM_HELD"); return(0L) }

# ── ★블록 경계 강제: 같은 블록 안에서만 묶는다 (재개분이 없을 때만 신규 배치) ──
batch <- list(); first <- NULL
if (!length(pending) && used < length(cells)) {
  first <- cells[[used + 1L]]
  k <- used + 1L
  while (k <= min(length(cells), MAXA) && length(batch) < NPAR) {
    if (!identical(cells[[k]]$block, first$block)) break
    batch[[length(batch) + 1L]] <- cells[[k]]; k <- k + 1L
  }
  room <- max(0L, DAILY_CAP - done_today)
  if (length(batch) > room) batch <- batch[seq_len(room)]

# ★B5(오버레이) 칸은 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**
#   (도훈 2026-08-30 "오버레이 방법론을 특정하는건 별로인데"). 이미 측정한 팔은 제외하므로
#   승격 사슬·다음 논문에서 같은 다섯 개를 반복 측정하지 않는다. 격자의 B5 cells 는 스냅샷일 뿐이다.
if (length(batch) && identical(first$block, "B5")) {
  .done_arms <- unique(unlist(lapply(E$attempts, function(a) {
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
    s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(s)) NULL else s$overlay$arm_id
  })))
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
  out <- if (!is.null(cd) && nzchar(cd)) .cell_by_code(cd) else NULL
  if (is.null(out) && w$n <= length(cells)) out <- cells[[w$n]]
  out
}
.blk <- if (!is.null(first)) first$block else "B4"   # 재개분은 스펙이 이미 있어 승자를 다시 안 쓴다
w1 <- if (!identical(.blk, "B1")) .winner_of("B1", "port_t") else NULL
if (!length(pending) && !identical(.blk, "B1") && is.null(w1)) {
  jlog("halt_no_b1_winner", block = .blk); return(1L) }
w2 <- .winner_of("B2", "port_t"); w3 <- .winner_of("B3", "calmar")

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

# 기저 논문 — 오버레이 셀은 논문이 아니라 방법이 근거지만, 전략의 출처는 여전히 이 논문이다.
.base_paper <- tryCatch({
  ap <- file.path(E$base_artifacts %||% "", "authoritative_remeasure.json")
  if (nzchar(ap) && file.exists(ap)) fromJSON(ap, simplifyVector = FALSE)$replication$source_paper else NULL
}, error = function(e) NULL)

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
    sp <- file.path(WDIR, sprintf("spec_%s.json", CELL$code))
    if (!file.exists(sp)) { jlog("resume_skip_no_spec", n = a$n, code = CELL$code); next }
    jobs[[length(jobs) + 1L]] <- list(n = as.integer(a$n), code = CELL$code, spec = sp,
      name = sprintf("RF_PAR_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
      out = file.path(WDIR, sprintf("result_%s.json", CELL$code)))
  }
  if (length(jobs) > NPAR) jobs <- jobs[seq_len(NPAR)]
}

# ── ① 사전 등록 (순차 — 원장 단독 접근). 재개분이 있으면 건너뛴다 ────────────
if (!length(jobs)) for (CELL in batch) {
  SPEC <- list(code = CELL$code, label = CELL$label, block = CELL$block,
               fixed_axes = PROG$fixed_axes,
               # ★기저 신호는 원장의 충실구현 engine_path 에서 물려받는다 — 논문이 바뀌면 기저도 바뀐다.
               #   경로가 없거나 파일이 없으면 mom_12_1 로 떨어진다(구 entry 하위호환).
               base_signal = { .ep <- E$engine_path %||% ""
                 if (nzchar(.ep) && file.exists(.ep)) list(kind = "engine", path = .ep)
                 else list(kind = "mom_12_1") },
               factor2 = CELL$factor2 %||% w1$factor2,
               weighting = CELL$weighting %||% list(kind = "ew"),
               universe = CELL$universe %||% list(kind = "k200_kq150"))
  if (identical(CELL$block, "B3")) SPEC$weighting <- list(kind = "ew")
  if (identical(CELL$block, "B4")) {
    use <- unlist(CELL$combo$use)
    SPEC$factor2   <- if ("B1" %in% use) w1$factor2 else list(kind = "none")
    SPEC$weighting <- if ("B2" %in% use && !is.null(w2)) (w2$weighting %||% list(kind="ew")) else list(kind = "ew")
    SPEC$universe  <- if ("B3" %in% use && !is.null(w3)) (w3$universe  %||% list(kind="k200_kq150")) else list(kind = "k200_kq150")
    # ★3팩터 확장 — factor3_rank 가 있으면 B1 그 순위 팩터를 셋째로 얹는다(등가중)
    f3r <- suppressWarnings(as.integer(CELL$combo$factor3_rank %||% NA))
    if (!is.na(f3r)) {
      b1x <- Filter(function(a) { cd <- a$essence$cell_code
        !is.null(a$essence) && !is.null(cd) && startsWith(cd, "B1_") }, E$attempts)
      vx <- vapply(b1x, function(a) .metric(a, "port_t"), numeric(1))
      ox <- order(replace(vx, !is.finite(vx), -Inf), decreasing = TRUE)
      if (length(ox) >= f3r) {
        a3 <- .cell_by_code(b1x[[ox[f3r]]]$essence$cell_code)
        if (!is.null(a3$factor2)) { SPEC$factor3 <- a3$factor2
          jlog("b4_factor3", rank = f3r, code = a3$code, f3 = a3$factor2$id) }
      }
    }
    fr <- suppressWarnings(as.integer(CELL$combo$factor2_rank %||% NA))
    if (!is.na(fr) && fr >= 2L) {
      b1 <- Filter(function(a) { cd <- a$essence$cell_code
        !is.null(a$essence) && !is.null(cd) && startsWith(cd, "B1_") }, E$attempts)
      vv <- vapply(b1, function(a) .metric(a, "port_t"), numeric(1))
      ord <- order(replace(vv, !is.finite(vv), -Inf), decreasing = TRUE)
      if (length(ord) >= fr) { alt <- .cell_by_code(b1[[ord[fr]]]$essence$cell_code)
        if (!is.null(alt$factor2)) { SPEC$factor2 <- alt$factor2; jlog("b4_alt_factor", rank = fr, code = alt$code) } }
    }
  }
  # ── ★승격 entry 의 carry 병합 (도훈 지시 2026-08-30 "B등급 이상 추가 강화") ──
  #   승격은 B+ 를 낸 승자 구성을 **기저로 물려받아** 그 위에서 20칸을 다시 탐색한다.
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
    SPEC$factors <- c(E$carry$factors %||% list(), .cur)
    SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
    if (!(CELL$block %in% c("B2", "B4")) && !is.null(E$carry$weighting)) SPEC$weighting <- E$carry$weighting
    if (!(CELL$block %in% c("B3", "B4")) && !is.null(E$carry$universe))  SPEC$universe  <- E$carry$universe
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
    SPEC$overlay <- CELL$overlay
    SPEC$overlay_basis <- CELL$basis %||% ""
    if (!is.null(.base_paper)) SPEC$root_paper <- .base_paper
  }
  rp <- CELL$root_paper %||% w1$root_paper
  SPEC$root_paper <- rp
  SPEC$idea <- sprintf("[무인 병렬 %s] %s — %s/%s · factor2=%s · weighting=%s · universe=%s",
                       CELL$code, CELL$label, CELL$block, CELL$axis,
                       SPEC$factor2$id %||% SPEC$factor2$kind, SPEC$weighting$kind, SPEC$universe$kind)
  # ★지식 주입(착수 전 의무) — hypothesis_index 죽은 선례 + 직전 교훈. 차단 아님, 기록.
  SPEC <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_preflight.R"))
                     rf_preflight(SPEC, BID) },
                   error = function(e) { jlog("preflight_failed", code = CELL$code, err = conditionMessage(e)); SPEC })
  .pf <- SPEC$preflight
  if (!is.null(.pf) && length(.pf$dead_precedents))
    jlog("preflight_dead_precedent", code = CELL$code,
         kw = paste(names(.pf$dead_precedents), collapse = ","),
         note = "죽은 선례 존재 — 실행은 진행(AX-000: 사실 기록이지 금지 목록 아님)")
  sp <- file.path(WDIR, sprintf("spec_%s.json", CELL$code))
  write(toJSON(SPEC, auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
  att <- tryCatch(rf_append_attempt(1L, BID, SPEC$idea, CELL$axis, list(if (identical(CELL$axis, "risk_overlay")) list(method = CELL$basis %||% CELL$label, url = rp$url %||% "") else rp), wt_id = NULL, root = ROOT),
                  error = function(e) { jlog("append_failed", code = CELL$code, err = conditionMessage(e)); NULL })
  if (is.null(att)) next
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
nb <- 0L
for (j in jobs) {
  if (!file.exists(j$out)) {
    rf_record_result(1L, BID, j$n, grade = "NA (등급 미발행 — 병렬 워커 미완료/시간초과)",
                     lessons = sprintf("워커 산출 부재: %s (로그 %s)", j$out, file.path(WDIR, sprintf("log_%s.txt", j$code))),
                     root = ROOT)
    jlog("cell_missing", n = j$n, code = j$code); next
  }
  R <- fromJSON(j$out, simplifyVector = FALSE)
  if (!isTRUE(R$ok)) {
    rf_record_result(1L, BID, j$n, grade = "NA (등급 미발행 — 병렬 실행 실패)",
                     lessons = sprintf("%s 실패: %s", j$code, R$err %||% "?"), root = ROOT)
    jlog("cell_error", n = j$n, code = j$code, err = R$err %||% "?"); next
  }
  es <- R$essence
  rf_record_result(1L, BID, j$n, grade = R$grade, essence = es, artifacts = R$artifacts,
    lessons = sprintf("[무인 병렬 %s] Grade %s · PORT_t %s · SR %s · CAGR %s · MDD %s · Calmar %s · OOS %s",
      j$code, R$grade, es$port_t %||% "-", es$net_sharpe %||% "-", es$cagr %||% "-",
      es$mdd %||% "-", es$calmar %||% "-", es$oos_retention %||% "-"), root = ROOT)
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
  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   rf_auto_notify(BID, u2, kind = "block"); TRUE },
                 error = function(e) { jlog("telegram_failed", err = conditionMessage(e)); FALSE })
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
