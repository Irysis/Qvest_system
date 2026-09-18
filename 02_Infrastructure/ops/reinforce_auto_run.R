#!/usr/bin/env Rscript
#==============================================================================
# ★퇴역 (2026-09-05 도훈 지시 "분기 제거 — parallel 로 단일화")
#   실행 경로는 reinforce_auto_parallel.R 하나다. 이 파일은 **사료**로 남는다
#   (회귀 가드 8종이 문자열로 참조 중 — 08_Tests/reinforcement/*, 08_Tests/worktask/).
#
#   왜 퇴역했나: v10.4 핵심 3종이 여기 안 들어왔다 —
#     ① B1 LLM 설계 소비(rf_b1_design_cells)  ② 블록 전이 설계(rfbd_cells)
#     ③ entry 예산 상향(25 + max(0, B1 설계칸 − 5) · rf_record_entry_budget)
#   그래서 이 러너로 도는 entry 는 항상 폴백 5칸 · 예산 25 고정이었다. 같은 도훈 지시를
#   인용한 주석만 아래 105~109 행에 복사돼 있어 **읽으면 있는 것처럼 보였다**.
#   순차 실행이 필요하면 reinforce_auto_config.json::parallel_cells = 1 로 둔다.
#
#   탈출구: QVEST_RF_ALLOW_SEQ=1 이면 이 가드를 넘긴다(디버깅 전용 — 측정에 쓰지 말 것).
#==============================================================================
if (!nzchar(Sys.getenv("QVEST_RF_ALLOW_SEQ"))) {
  cat("[reinforce_auto_run] ★퇴역된 러너입니다 — 실행 경로는 reinforce_auto_parallel.R 하나입니다.
")
  cat("  이 러너에는 B1 LLM 설계 · 블록 전이 설계 · entry 예산 상향(25+max(0,B1칸-5))이 없어
")
  cat("  폴백 5칸 · 예산 25 고정으로 돕니다. 순차가 필요하면 parallel_cells=1 을 쓰세요.
")
  cat("  디버깅 목적이면 QVEST_RF_ALLOW_SEQ=1 로 실행하십시오.
")
  quit(status = 3L)
}
#==============================================================================
# reinforce_auto_run.R — 강화 프로세스 **무인 러너** (도훈 지시 2026-08-30 "모든 작업을 무인화")
#
# ★헌법 변경점: v10 은 "무인 파이프라인은 수집까지만"(CLAUDE.md · alpha_search_queue_run.sh:2 ·
#   auto_spawn_queue.R "라운드 개시는 세션")이었다. 도훈이 이 경계를 명시적으로 풀었다.
#   대신 **LLM 무인 개시가 아니라 규칙 무인 개시**다 — 셀은 06_Registry/reinforce_program.json
#   격자에서 나오고 엔진은 rf_cell_engine.R 하나이며, 이 러너는 어떤 코드도 생성하지 않는다.
#
# 1회 호출 = 강화 시도 1칸 (블록당 5칸 × 5블록 = 25칸 · B1→B2→B3→B5→B4). 스케줄러가 반복 호출한다.
#
# 흐름:
#   kill switch → claim(mutex) → 원장 active entry → 다음 칸 결정 → 셀 스펙 조립
#   → run_paper_replication → 권위 등급 → rf_record_result → 분기
# 분기:
#   Grade A      → judge_request 발행 + 텔레그램 + **자동 정지**(BOOK 등록은 도훈 confirm)
#   25칸 소진    → status=exhausted + 텔레그램 → reinforce_auto_next_paper.R 이 다음 논문 개시
#   그 외        → 조용히 종료(다음 호출이 다음 칸)
#
# 하드 가드:
#   - kill switch: 06_Registry/reinforce_auto_config.json {enabled:false} → 전면 정지
#   - claim mutex: dir.create 원자성 + stale 재점유 (cleaner_claim.R 전례)
#   - 자본 경계: book_state / 05_Production 에 도달하는 코드 없음 (쓰기 = 원장·로그·산출물)
#   - 예산: 1일 최대 칸 수 상한(daily_cap) — 폭주 backstop
#   - 내구 기록: .cache/reinforce_auto_log.jsonl append
#   - 실패는 조용히 넘기지 않는다: 예외를 로그+경보로 남기고 exit 1
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
# ★강화 셀은 원장 entry 를 새로 열지 않는다 (자기증식 차단)
Sys.setenv(QVEST_NO_LEDGER_OPEN = "1")

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
dir.create(dirname(LOG_P), recursive = TRUE, showWarnings = FALSE)

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rf_auto] %s %s\n", event,
              paste(names(rec)[-(1:2)], unlist(lapply(rec[-(1:2)], function(z) substr(paste(z, collapse=","), 1, 90))),
                    sep = "=", collapse = " ")))
}

# ── 0. kill switch ────────────────────────────────────────────────────────────
CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled", cfg = CFG_P); quit(status = 0) }
DAILY_CAP <- as.integer(CFG$daily_cap %||% 6L)

# 오늘 실행분 상한 (폭주 backstop)
if (file.exists(LOG_P)) {
  today <- format(Sys.Date(), "%Y-%m-%d")
  done_today <- tryCatch({
    ln <- readLines(LOG_P, warn = FALSE)
    sum(vapply(ln, function(l) {
      o <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
      isTRUE(!is.null(o) && identical(o$event, "cell_done") && startsWith(o$ts %||% "", today))
    }, logical(1)))
  }, error = function(e) 0L)
  if (done_today >= DAILY_CAP) { jlog("halt_daily_cap", done = done_today, cap = DAILY_CAP); quit(status = 0) }
}

# ── 1. claim mutex (dir.create 원자성 + stale 재점유) ─────────────────────────
STALE_H <- as.numeric(CFG$claim_stale_hours %||% 6)
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
on.exit(unlink(CLAIM, recursive = TRUE), add = TRUE)   # ★최상위 on.exit 은 no-op이므로 아래 main() 안에서도 정리한다

main <- function() {
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
PROG <- fromJSON(PROG_P, simplifyVector = FALSE)

# ── 2. active entry ───────────────────────────────────────────────────────────
led <- rf_load(1L, ROOT)
act <- Filter(function(e) identical(e$status, "active"), led$entries)
if (!length(act)) { jlog("halt_no_active_entry"); return(invisible(0L)) }
E <- act[[1]]; BID <- E$base_id
used <- as.integer(E$attempts_used %||% 0L)
# ★entry 별 상한 (2026-09-04 도훈 지시). B1 이 설계에 따라 가변 길이가 되면서,
#   전역 25 를 그대로 두면 B1 이 쓴 만큼 뒤 블록이 잘린다 — 실측: B1 14칸 -> B4(결합)가
#   아예 못 돌았다. 각 블록 승자를 합치는 칸을 못 보면 그 entry 는 A 로 갈 길이 없다.
#   "칸 수 제한을 두지 마라" 를 B1 에만 적용하고 총예산에 안 적용한 비대칭을 닫는다.
MAXA <- as.integer(E$max_attempts %||% led$max_attempts %||% 25L)

if (used >= MAXA) {
  jlog("exhaust_reached", base_id = BID, used = used)
  rf_park_or_exhaust <- get0("rf_park_entry", ifnotfound = NULL)
  # 25칸 소진 = exhausted (park 아님 — park 은 도훈 조기중단 전용)
  obj <- rf_load(1L, ROOT)
  for (i in seq_along(obj$entries)) if (identical(obj$entries[[i]]$base_id, BID)) {
    obj$entries[[i]]$status <- "exhausted"
    obj$entries[[i]]$exhausted_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  }
  .rf_write(obj, 1L, ROOT)
  jlog("entry_exhausted", base_id = BID)
  # ★wait=TRUE 여야 한다. wait=FALSE 로 띄우면 부모 Rscript 가 즉시 종료하면서 자식이 함께 죽어
  #   이월이 조용히 안 된다(2026-08-30 실사고: exhausted 는 찍혔는데 요청 파일·로그가 0건).
  #   이월은 수 초짜리라 동기 실행이 비용이 아니다.
  system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"))), wait = TRUE)
  return(invisible(0L))
}

# ── 3. 다음 칸 결정 ───────────────────────────────────────────────────────────
cells <- do.call(c, lapply(PROG$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))
if (used >= length(cells)) { jlog("halt_program_exhausted", used = used); return(invisible(0L)) }
# ★커서는 개수가 아니라 **아직 자리가 빈 셀 코드**에서 뽑는다 (2026-09-04 · 병렬 러너와 동형).
#   구판 `cells[[used + 1L]]` 은 등록이 한 건 거부되면 격자 위치가 영구히 어긋났다.
#   두 러너가 같은 방어를 갖지 않으면 mode 를 바꾸는 순간 한쪽만 안전해진다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE))
.free <- .rf_free_cells(cells, E$attempts)
if (!length(.free)) { jlog("halt_no_free_cell", used = used); return(invisible(0L)) }
CELL <- cells[[.free[1]]]

# ★B1 칸은 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**(2026-09-01, 병렬 러너와 동형).
#   격자의 B1 cells 는 스냅샷일 뿐 정본이 아니다. 두 러너가 다른 팩터를 쓰면 mode 를 바꾸는
#   순간 조용히 다른 실험이 된다 — 같은 계통의 방어가 한쪽에만 깔리는 것을 만들지 않는다.
if (identical(CELL$block, "B1")) {
  .bp <- tryCatch({ ap <- file.path(E$base_artifacts %||% "", "authoritative_remeasure.json")
    if (nzchar(ap) && file.exists(ap)) fromJSON(ap, simplifyVector = FALSE)$replication$source_paper else NULL
  }, error = function(e) NULL)
  .pos <- sum(vapply(cells[seq_len(used + 1L)], function(c) identical(c$block, "B1"), logical(1)))
  .fp <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R")))
                    rf_pick_factor_sets(5L, seed_offset = length(led$entries),
                                        depths = unlist(PROG$blocks[[1]]$depths %||% list()),
                                        fallback_paper = .bp, root = ROOT) },
                  error = function(e) { jlog("factor_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.fp) && length(.fp$cells) >= .pos) {
    .c <- .fp$cells[[.pos]]; .c$code <- CELL$code; .c$block <- "B1"; .c$axis <- "multifactor"
    CELL <- .c
    jlog("factor_arms_picked", seed = .fp$seed_id, offset = .fp$seed_offset, pos = .pos,
         chain = paste(.fp$picked_ids, collapse = ","), pool = .fp$n_available,
         asof = .fp$substrate_asof)
  } else jlog("factor_arms_fallback", note = "picker 미산출 — 격자 스냅샷 셀로 진행")
}
jlog("cell_start", base_id = BID, n = used + 1L, code = CELL$code, label = CELL$label, block = CELL$block)

# ── 4. 이전 블록 승자 주입 (B2/B3/B4 는 B1 승자 위에 선다) ────────────────────
.metric <- function(a, key) {
  es <- a$essence
  if (is.list(es) && !is.null(es[[key]])) return(as.numeric(es[[key]]))
  # essence 미기입 판: lessons 텍스트에서 읽지 않는다(재구성 금지) → NA
  NA_real_
}
# ★승자 판정은 **셀 코드**로 한다 — 위치(n번째 = 격자 n번째)에 의존하면 프로그램을 손보는
#   순간 조용히 엇갈린다. essence$cell_code 가 있으면 그것을, 없으면 위치로 폴백한다.
.cell_by_code <- function(cd) {
  k <- which(vapply(cells, function(c) identical(c$code, cd), logical(1)))
  if (length(k)) cells[[k[1]]] else NULL
}
.winner_of <- function(block_id, by = "port_t") {
  idx <- which(vapply(cells, function(c) identical(c$block, block_id), logical(1)))
  cand <- Filter(function(a) {
    if (is.null(a$essence)) return(FALSE)
    cd <- a$essence$cell_code
    if (!is.null(cd) && nzchar(cd)) startsWith(cd, paste0(block_id, "_")) else (a$n %in% idx)
  }, E$attempts)
  if (!length(cand)) return(NULL)
  vals <- vapply(cand, function(a) .metric(a, by), numeric(1))
  if (all(is.na(vals))) return(NULL)
  w <- cand[[which.max(replace(vals, !is.finite(vals), -Inf))]]
  cd <- w$essence$cell_code
  # ★승자는 **측정된 spec 파일**에서 읽는다 — 격자 코드 조회는 안 된다(2026-09-01, 병렬 러너와 동형).
  #   B1·B5 셀은 배치 시점에 등록부에서 뽑히므로 격자에 존재하지 않는다. 격자를 조회하면
  #   실제로 이긴 구성이 아니라 스냅샷이 나오고 후속 블록이 이기지도 않은 구성 위에 선다.
  out <- NULL
  .sp <- w$essence$spec
  if (!is.null(.sp) && nzchar(.sp) && file.exists(.sp))
    out <- tryCatch(fromJSON(.sp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(out) && !is.null(cd) && nzchar(cd)) out <- .cell_by_code(cd)   # 구 entry 폴백
  if (is.null(out) && w$n <= length(cells)) out <- cells[[w$n]]
  out
}
# 승자의 팩터 축을 집합으로 정규화 — 등록부 셀은 factors(복수), 구 격자 셀은 factor2(단수)
.win_factors <- function(w) {
  if (is.null(w)) return(NULL)
  if (!is.null(w$factors) && length(w$factors)) return(w$factors)
  if (!is.null(w$factor2)) return(list(w$factor2))
  NULL
}
w1 <- if (!identical(CELL$block, "B1")) .winner_of("B1", "port_t") else NULL
if (!identical(CELL$block, "B1") && is.null(w1)) {
  jlog("halt_no_b1_winner", block = CELL$block,
       note = "B1 승자 미확정 — essence 기입이 없으면 후속 블록을 세울 수 없다")
  return(invisible(1L))
}

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
             # ★기저 가중(2026-09-01) — 격자 fixed_axes 가 정본. 값이 없으면 엔진이 등가중으로 돈다.
             base_weight = PROG$fixed_axes$base_weight,
             # ★팩터 축은 집합이다 — 등록부 셀은 factors(복수), 구 격자 셀의 factor2 는 길이 1 로 정규화
             factors = (if (!is.null(CELL$factors) && length(CELL$factors)) CELL$factors
                        else if (!is.null(CELL$factor2)) list(CELL$factor2)
                        else .win_factors(w1)),
             weighting = CELL$weighting %||% list(kind = "ew"),
             universe = CELL$universe %||% list(kind = "k200_kq150"))
if (identical(CELL$block, "B3")) SPEC$weighting <- list(kind = "ew")   # B3 는 비중 고정
if (identical(CELL$block, "B4")) {
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
  use <- unlist(CELL$combo$use)
  # ★LOO 는 "그 축을 빼는" 것이다 — 폴백으로 대체하면 제외가 공허해진다.
  # ★2026-09-01 4축(팩터·비중·유니버스·오버레이). 구판 3축 격자는 이미 완비였고,
  #   빈 곳은 칸이 아니라 축이었다 — A 를 막는 것이 낙폭인데 오버레이를 안 봤다.
  w5 <- .winner_of("B5", "calmar")
  SPEC$factors   <- if ("B1" %in% use) .win_factors(w1) else NULL
  SPEC$weighting <- if ("B2" %in% use && !is.null(w2)) (w2$weighting %||% list(kind="ew")) else list(kind = "ew")
  SPEC$universe  <- if ("B3" %in% use && !is.null(w3)) (w3$universe  %||% list(kind="k200_kq150")) else list(kind = "k200_kq150")
  SPEC$overlay   <- if ("B5" %in% use) w5$overlay else NULL
  SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
  jlog("b4_axes", code = CELL$code, use = paste(use, collapse = "+"),
       f = length(SPEC$factors %||% list()), w = SPEC$weighting$kind %||% "?",
       u = SPEC$universe$kind %||% "?", ov = SPEC$overlay$arm_id %||% "none")
}

# ★entry 식별자 포함 — 구판 고정 이름은 다음 entry 가 덮어써 사후 재현을 불가능하게 했다.
SPEC_P <- file.path(ROOT, ".cache", sprintf("rf_cell_spec_%s__%s.json", CELL$code, substr(BID, 1, 48)))
write(toJSON(SPEC, auto_unbox = TRUE, pretty = TRUE, null = "null"), SPEC_P)

# ── 5. 사전 등록 (원장이 근거 논문을 기계 강제한다) ───────────────────────────
# ── 처치 전달 판정 헬퍼 — ★정본 rf_spec_sig.R 를 읽는다(2026-09-03 중복 제거)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE))
.no_treatment <- FALSE
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
  # ★중복 제거 — 스코어가 rowMeans 등가중이라 같은 팩터가 두 번 들어가면 기저 가중이
  #   조용히 깎인다(1/2 -> 1/3). 병렬 러너와 같은 규칙(2026-08-31 실사고, 실측 2.63 -> 2.251).
  SPEC$factors <- .dedup_factors(c(E$carry$factors %||% list(), .cur))
  SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
  if (!(CELL$block %in% c("B2", "B4")) && !is.null(E$carry$weighting)) SPEC$weighting <- E$carry$weighting
  if (!(CELL$block %in% c("B3", "B4")) && !is.null(E$carry$universe))  SPEC$universe  <- E$carry$universe
  # ★오버레이 승계 (2026-09-03, 병렬 러너와 동일 규약) — 구판은 이 줄이 없어
  #   승격된 자식이 부모의 위험 통제를 벗은 채 B1/B2/B3 를 돌았다.
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
  SPEC$overlay <- .ov_stack(E$carry$overlay, CELL$overlay)   # ★중첩 — 덮어쓰기 아님
  SPEC$overlay_basis <- CELL$basis %||% ""
  if (!is.null(.base_paper)) SPEC$root_paper <- .base_paper
}
# ★무처치 판정은 **조립이 끝난 뒤**. 병렬 러너와 같은 규칙(2026-08-31 실사고: B5 가
#   overlay 를 붙이기 전에 판정돼 다섯 칸이 측정 0건으로 소비됐다).
if (!is.null(E$carry)) {
  .no_treatment <- identical(.fkeys(SPEC$factors), .fkeys(E$carry$factors %||% list())) &&
    .same_axis(SPEC$weighting, E$carry$weighting %||% list(kind = "ew")) &&
    .same_axis(SPEC$universe,  E$carry$universe  %||% list(kind = "k200_kq150")) &&
    .same_axis(SPEC$overlay,   E$carry$overlay   %||% list())
}
# ★근거 논문 (2026-09-02 수리) — 병렬 러너와 같은 규칙(사연은 그쪽 주석·rf_root_papers_for).
#   source_paper(단수) = 기저 논문 · 원장 root_papers(복수) = 기저 + 셀 처치 논문 + 팩터 전 계열 논문.
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
# ★스펙 파일을 다시 쓴다 — 앞선 기록 시점(SPEC_P 최초 write)엔 root_paper/root_papers 가 없었다(B5 분기의
#   root_paper 도 그 뒤에 붙는다). 엔진은 RF_CELL_SPEC 을 실행 시점에 읽으므로 같은 경로에 상위집합을 덮어써도 안전하다.
write(toJSON(SPEC, auto_unbox = TRUE, pretty = TRUE, null = "null"), SPEC_P)
# ★sprintf 영길이 붕괴 방어 (2026-09-03) — 조각 하나가 NULL 이면 idea 전체가 character(0) 이 된다.
.s1 <- function(x, alt = "?") {
  x <- suppressWarnings(as.character(x))
  if (!length(x) || is.na(x[[1L]]) || !nzchar(x[[1L]])) alt else x[[1L]]
}
.blk_rule <- tryCatch(PROG$blocks[[which(vapply(PROG$blocks, function(b) identical(b$id, CELL$block), logical(1)))]]$rule,
                      error = function(e) NULL)
idea <- sprintf("[무인 규칙강화 %s] %s — 격자 %s/%s · factor2=%s · weighting=%s · universe=%s. %s",
                .s1(CELL$code), .s1(CELL$label), .s1(CELL$block), .s1(CELL$axis),
                .s1(SPEC$factor2$id, "none"), .s1(SPEC$weighting$kind, "ew"),
                .s1(SPEC$universe$kind, "k200_kq150"), .s1(CELL$note %||% .blk_rule, ""))
att <- tryCatch(rf_append_attempt(1L, BID, idea, CELL$axis, .root_papers, wt_id = NULL, root = ROOT,
                                  unmapped_families = .rpz$unmapped_families,
                                  axiom_injected = isTRUE(SPEC$preflight$axiom_injected),
                                  # ★격자 좌표를 등록 시점에 박는다 — 커서의 정본(2026-09-04)
                                  cell_code = CELL$code),
                error = function(e) { jlog("halt_append_failed", base_id = BID, code = CELL$code,
                                          err = conditionMessage(e)); NULL })
if (is.null(att)) return(invisible(1L))
N <- as.integer(att$n)
# ★무처치 셀은 실행하지 않는다 — 중복 제거 후 구성이 carry 와 같으면 같은 포트폴리오다.
#   측정하면 수치가 나오고(B3_11 의 all_listed 와 달리 조용하다) 그 칸이 블록 승자가 된다.
if (isTRUE(.no_treatment)) {
  rf_record_result(1L, BID, N, grade = "NA (미결 — carry 와 동일·처치 미전달)",
    lessons = sprintf("%s: 중복 제거 후 구성이 carry 와 동일 — 같은 포트폴리오에 다른 이름을 붙이지 않는다", CELL$code),
    terminal = TRUE,
    terminal_reason = sprintf("무처치(carry 동일) — factors=%s weighting=%s universe=%s",
      paste(.fkeys(SPEC$factors), collapse = "+"), SPEC$weighting$kind %||% "?", SPEC$universe$kind %||% "?"),
    root = ROOT)
  jlog("cell_no_treatment", n = N, code = CELL$code, note = "carry 와 동일 — 미결 종결(실행 안 함)")
  return(invisible(0L))
}

# ── 6. 실행 ───────────────────────────────────────────────────────────────────
suppressMessages(source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")))
UNIV_LABEL <- if (identical(SPEC$universe$kind, "k200_kq150")) "K200_KQ150" else toupper(SPEC$universe$kind)
Sys.setenv(RF_CELL_SPEC = SPEC_P)
res <- tryCatch(
  run_paper_replication(
    strategy_name = sprintf("RF_AUTO_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
    strategy_idea = idea,
    factor_engine_path = file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"),
    # ★2026-09-01 — 워커와 동형. `n =` 은 러너가 읽지 않는 키였다(이중 선정 -> 보유 3종).
    portfolio_spec = list(construction = "top_n_long",
                          n_long = PROG$fixed_axes$n_max, n_max = PROG$fixed_axes$n_max,
                          weighting = SPEC$weighting$kind, rebalance = "monthly"),
    universe = UNIV_LABEL, source_paper = rp,
    commission_paper = PROG$fixed_axes$commission_bps / 10000,
    start_date = PROG$fixed_axes$start_date,
    send_telegram = FALSE),
  error = function(e) { jlog("cell_error", n = N, code = CELL$code, err = conditionMessage(e)); NULL })

if (is.null(res)) {
  rf_record_result(1L, BID, N, grade = "NA (등급 미발행 — 무인 실행 실패, 로그 참조)",
                   lessons = "reinforce_auto_run 실행 예외 — .cache/reinforce_auto_log.jsonl 의 cell_error 참조",
                   root = ROOT)
  return(invisible(1L))
}

# ── 7. 권위 등급 인용 (손계산 금지 — 계약 산출물만) ──────────────────────────
ar_p <- res$authoritative_remeasure_path %||%
        file.path(res$out_dir %||% "", "authoritative_remeasure.json")
if (!file.exists(ar_p)) {
  cand <- list.files(file.path(ROOT, "stage_artifacts/replication"), pattern = "^authoritative_remeasure\\.json$",
                     recursive = TRUE, full.names = TRUE)
  if (length(cand)) ar_p <- cand[which.max(file.mtime(cand))]
}
if (!file.exists(ar_p)) {
  jlog("cell_no_grade", n = N, code = CELL$code)
  rf_record_result(1L, BID, N, grade = "NA (등급 미발행 — authoritative_remeasure.json 부재)",
                   lessons = "계약 미경유 = 미측정. 실패가 아니라 등급 미발행.", root = ROOT)
  return(invisible(1L))
}
AR <- fromJSON(ar_p, simplifyVector = TRUE)
G  <- AR$essence_grade; es <- AR$essence

rf_record_result(1L, BID, N, grade = G,
  essence = list(cell_code = CELL$code, block = CELL$block,      # ★승자 판정이 코드 기반이라 필수
                 port_t = es$portfolio_alpha_t_nw_lag3, net_sharpe = es$net_sharpe,
                 cagr = es$cagr, mdd = es$mdd, calmar = es$calmar, oos_retention = es$oos_retention,
                 spec = SPEC_P, source = "authoritative_remeasure.json"),
  artifacts = dirname(ar_p),
  lessons = sprintf("[무인 %s] %s — Grade %s · PORT_t %.3f · SR %.3f · CAGR %.1f%% · MDD %.1f%% · Calmar %.3f · OOS %+.3f",
                    CELL$code, CELL$label, G, es$portfolio_alpha_t_nw_lag3 %||% NA, es$net_sharpe %||% NA,
                    100*(es$cagr %||% NA), 100*(es$mdd %||% NA), es$calmar %||% NA, es$oos_retention %||% NA),
  root = ROOT)
jlog("cell_done", n = N, code = CELL$code, grade = G,
     port_t = es$portfolio_alpha_t_nw_lag3, calmar = es$calmar, artifacts = dirname(ar_p))

# ── 7b. 텔레그램 (무인 — 블록 완료 5칸마다. 매 칸 발송은 소음이라 묶는다) ─────
if (N %% 5L == 0L && !identical(G, "A")) {
  # ★"보냈다" 를 예외 부재로 지어내지 않는다 — 실제 발송 결과를 받는다(2026-08-31).
  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   isTRUE(rf_auto_notify(BID, N, kind = "block")) },
                 error = function(e) { jlog("telegram_failed", n = N, err = conditionMessage(e)); FALSE })
  if (!ok) jlog("telegram_send_failed", n = N, kind = "block",
                note = "발송 실패 — lock 미생성이므로 다음 tick 이 재발송을 시도한다")
  jlog("telegram_block", n = N, sent = ok)
  # ★L-code 무인 발행 — SKILL §0 "블록당 L-code 1건" 의 소비자가 없었다(러너 2종 emit_lcode 0건).
  #   세션이 안 오면 그 블록의 학습이 원장 밖에서 증발한다. 텔레그램과 같은 생산자를 쓴다.
  lc <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R"))
                   rf_emit_block_lcode(BID, N, root = ROOT) },
                 error = function(e) { jlog("lcode_failed", err = conditionMessage(e)); NULL })
  jlog("lcode_block", n = N, l_code = as.character(lc %||% "NA"))
}

# ── 8. 분기 ───────────────────────────────────────────────────────────────────
if (identical(G, "A")) {
  jlog("grade_a_queued", n = N, code = CELL$code,
       note = "Judge/BOOK 은 도훈 confirm — 단 리서치 루프는 계속 돈다")
  jr <- file.path(ROOT, "qepm/mailbox/judge_request.json")
  dir.create(dirname(jr), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(list(requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                    source = "reinforce_auto_run", base_id = BID, attempt = N,
                    cell = CELL$code, artifacts = dirname(ar_p), grade = "A"),
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
    queued_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), base_id = BID, attempt = N,
    cell = CELL$code, artifacts = dirname(ar_p), grade = "A", status = "awaiting_judge")
  write(toJSON(.q, auto_unbox = TRUE, pretty = TRUE, null = "null"), .aq)

  # ★"보냈다" 를 예외 부재로 지어내지 않는다 — 실제 발송 결과를 받는다(2026-08-31).
  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   isTRUE(rf_auto_notify(BID, N, kind = "grade_a")) },
                 error = function(e) { jlog("telegram_failed", n = N, err = conditionMessage(e)); FALSE })
  if (!ok) jlog("telegram_send_failed", n = N, kind = "grade_a",
                note = "발송 실패 — lock 미생성이므로 다음 tick 이 재발송을 시도한다")
  jlog("telegram_grade_a", n = N, sent = ok)
}
invisible(0L)
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
.rel <- if (.CLAIM_HELD) list(ok = TRUE, reason = "inherited") else rf_claim_release(CLAIM)
# ★표식이 남은 해제는 실패가 아니다(2026-09-19 · 병렬 러너와 동형) — 다음 tick 이 released.json 을 보고 즉시 인수한다.
if (identical(.rel$reason, "marker_left")) jlog("claim_release_marker", reason = .rel$reason,
     note = "디렉터리는 못 지웠지만 해제 표식을 남겼다 — 다음 tick 이 즉시 제자리 인수한다(정보)")
if (!isTRUE(.rel$ok)) jlog("claim_release_failed", reason = .rel$reason, err = .rel$err %||% "",
     note = "디렉터리도 표식도 남았다 — owner.json 의 pid 가 죽으면(빈 고아면 60초 뒤) 다음 tick 이 회수한다")
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
