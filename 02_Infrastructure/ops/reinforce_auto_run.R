#!/usr/bin/env Rscript
#==============================================================================
# reinforce_auto_run.R — 강화 프로세스 **무인 러너** (도훈 지시 2026-08-30 "모든 작업을 무인화")
#
# ★헌법 변경점: v10 은 "무인 파이프라인은 수집까지만"(CLAUDE.md · alpha_search_queue_run.sh:2 ·
#   auto_spawn_queue.R "라운드 개시는 세션")이었다. 도훈이 이 경계를 명시적으로 풀었다.
#   대신 **LLM 무인 개시가 아니라 규칙 무인 개시**다 — 셀은 06_Registry/reinforce_program.json
#   격자에서 나오고 엔진은 rf_cell_engine.R 하나이며, 이 러너는 어떤 코드도 생성하지 않는다.
#
# 1회 호출 = 강화 시도 1칸 (블록당 5칸 × 4블록 = 20칸). 스케줄러가 반복 호출한다.
#
# 흐름:
#   kill switch → claim(mutex) → 원장 active entry → 다음 칸 결정 → 셀 스펙 조립
#   → run_paper_replication → 권위 등급 → rf_record_result → 분기
# 분기:
#   Grade A      → judge_request 발행 + 텔레그램 + **자동 정지**(BOOK 등록은 도훈 confirm)
#   20칸 소진    → status=exhausted + 텔레그램 → reinforce_auto_next_paper.R 이 다음 논문 개시
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

CFG_P  <- file.path(ROOT, "06_Registry/reinforce_auto_config.json")
PROG_P <- file.path(ROOT, "06_Registry/reinforce_program.json")
LOG_P  <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
CLAIM  <- file.path(ROOT, ".cache/reinforce_auto.claim")
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
if (dir.exists(CLAIM)) {
  age_h <- as.numeric(difftime(Sys.time(), file.info(CLAIM)$mtime, units = "hours"))
  if (is.finite(age_h) && age_h > STALE_H) { unlink(CLAIM, recursive = TRUE); jlog("claim_stale_reclaim", age_h = round(age_h, 2)) }
  else { jlog("halt_claimed", age_h = round(age_h %||% NA, 2)); quit(status = 0) }
}
if (!dir.create(CLAIM, showWarnings = FALSE)) { jlog("halt_claim_race"); quit(status = 0) }
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
MAXA <- as.integer(led$max_attempts %||% 20L)

if (used >= MAXA) {
  jlog("exhaust_reached", base_id = BID, used = used)
  rf_park_or_exhaust <- get0("rf_park_entry", ifnotfound = NULL)
  # 20칸 소진 = exhausted (park 아님 — park 은 도훈 조기중단 전용)
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
CELL <- cells[[used + 1L]]
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
  out <- if (!is.null(cd) && nzchar(cd)) .cell_by_code(cd) else NULL
  if (is.null(out) && w$n <= length(cells)) out <- cells[[w$n]]
  out
}
w1 <- if (!identical(CELL$block, "B1")) .winner_of("B1", "port_t") else NULL
if (!identical(CELL$block, "B1") && is.null(w1)) {
  jlog("halt_no_b1_winner", block = CELL$block,
       note = "B1 승자 미확정 — essence 기입이 없으면 후속 블록을 세울 수 없다")
  return(invisible(1L))
}

SPEC <- list(code = CELL$code, label = CELL$label, block = CELL$block,
             fixed_axes = PROG$fixed_axes,
             base_signal = list(kind = "mom_12_1"),
             factor2  = CELL$factor2  %||% w1$factor2,
             weighting = CELL$weighting %||% list(kind = "ew"),
             universe = CELL$universe %||% list(kind = "k200_kq150"))
if (identical(CELL$block, "B3")) SPEC$weighting <- list(kind = "ew")   # B3 는 비중 고정
if (identical(CELL$block, "B4")) {
  w2 <- .winner_of("B2", "port_t"); w3 <- .winner_of("B3", "calmar")
  use <- unlist(CELL$combo$use)
  # ★LOO 는 "그 축을 빼는" 것이다 — 폴백 팩터로 대체하면 제외가 공허해진다.
  #   B1 제외 = 제2팩터 없음(기저 신호 단독). 하드코딩 팩터 금지(2026-08-30 적발·수리).
  SPEC$factor2   <- if ("B1" %in% use) w1$factor2 else list(kind = "none")
  SPEC$weighting <- if ("B2" %in% use && !is.null(w2)) (w2$weighting %||% list(kind="ew")) else list(kind = "ew")
  SPEC$universe  <- if ("B3" %in% use && !is.null(w3)) (w3$universe  %||% list(kind="k200_kq150")) else list(kind = "k200_kq150")
  # 차순위 팩터 셀(factor2_rank=2): B1 에서 port_t 2위 셀의 팩터를 쓴다
  fr <- suppressWarnings(as.integer(CELL$combo$factor2_rank %||% NA))
  if (!is.na(fr) && fr >= 2L) {
    b1 <- Filter(function(a) {
      cd <- a$essence$cell_code; !is.null(a$essence) && !is.null(cd) && startsWith(cd, "B1_")
    }, E$attempts)
    vv <- vapply(b1, function(a) .metric(a, "port_t"), numeric(1))
    ord <- order(replace(vv, !is.finite(vv), -Inf), decreasing = TRUE)
    if (length(ord) >= fr) {
      alt <- .cell_by_code(b1[[ord[fr]]]$essence$cell_code)
      if (!is.null(alt$factor2)) { SPEC$factor2 <- alt$factor2
        jlog("b4_alt_factor", rank = fr, code = alt$code, f2 = alt$factor2$id) }
    }
  }
}

SPEC_P <- file.path(ROOT, ".cache", sprintf("rf_cell_spec_%s.json", CELL$code))
write(toJSON(SPEC, auto_unbox = TRUE, pretty = TRUE, null = "null"), SPEC_P)

# ── 5. 사전 등록 (원장이 근거 논문을 기계 강제한다) ───────────────────────────
rp <- CELL$root_paper %||% w1$root_paper
idea <- sprintf("[무인 규칙강화 %s] %s — 격자 %s/%s · factor2=%s · weighting=%s · universe=%s. %s",
                CELL$code, CELL$label, CELL$block, CELL$axis,
                SPEC$factor2$id %||% "?", SPEC$weighting$kind, SPEC$universe$kind,
                CELL$note %||% PROG$blocks[[which(vapply(PROG$blocks, function(b) identical(b$id, CELL$block), logical(1)))]]$rule)
att <- tryCatch(rf_append_attempt(1L, BID, idea, CELL$axis, list(rp), wt_id = NULL, root = ROOT),
                error = function(e) { jlog("halt_append_failed", err = conditionMessage(e)); NULL })
if (is.null(att)) return(invisible(1L))
N <- as.integer(att$n)

# ── 6. 실행 ───────────────────────────────────────────────────────────────────
suppressMessages(source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")))
UNIV_LABEL <- if (identical(SPEC$universe$kind, "k200_kq150")) "K200_KQ150" else toupper(SPEC$universe$kind)
Sys.setenv(RF_CELL_SPEC = SPEC_P)
res <- tryCatch(
  run_paper_replication(
    strategy_name = sprintf("RF_AUTO_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
    strategy_idea = idea,
    factor_engine_path = file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"),
    portfolio_spec = list(construction = "top_n_long", n = PROG$fixed_axes$n_max,
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
  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   rf_auto_notify(BID, N, kind = "block"); TRUE },
                 error = function(e) { jlog("telegram_failed", n = N, err = conditionMessage(e)); FALSE })
  jlog("telegram_block", n = N, sent = ok)
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

  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   rf_auto_notify(BID, N, kind = "grade_a"); TRUE },
                 error = function(e) { jlog("telegram_failed", n = N, err = conditionMessage(e)); FALSE })
  jlog("telegram_grade_a", n = N, sent = ok)
}
invisible(0L)
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
unlink(CLAIM, recursive = TRUE)
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
