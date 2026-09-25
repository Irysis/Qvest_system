#!/usr/bin/env Rscript
#==============================================================================
# rf_cell_worker.R — 셀 1칸 **실행 전용 워커** (병렬 배치용, 2026-08-30)
#
# 왜 분리했나: 병렬 실행에서 원장(reinforce_ledger_l1.json)에 동시 쓰기가 나면
#   read-modify-write 경합으로 갱신이 조용히 유실된다. 그래서 워커는 **원장을 만지지 않는다** —
#   실행하고 결과를 자기 JSON 에만 쓴다. 원장 기입은 부모(reinforce_auto_parallel.R)가
#   전부 끝난 뒤 **순차로** 한다.
#
# 사용: Rscript rf_cell_worker.R <spec_json> <n> <strategy_name> <result_json>
# 출력: result_json = {n, code, ok, grade, essence{...}, artifacts, err}
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) stop("usage: rf_cell_worker.R <spec_json> <n> <name> <result_json>")
SPEC_P <- args[1]; N <- as.integer(args[2]); SNAME <- args[3]; OUT_P <- args[4]

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT, RF_CELL_SPEC = SPEC_P)
# ★강화 셀은 원장 entry 를 새로 열지 않는다 (자기증식 차단)
Sys.setenv(QVEST_NO_LEDGER_OPEN = "1")
# ★강화 셀은 '충실구현' L-code 를 발행하지 않는다 (2026-09-23 · 감사 D6-03 · 플랜 P0-M3).
#   구판은 이 스위치가 없어 셀마다 run_paper_replication 이 mode="paper_replication" L-code 를 냈다 —
#   셀 1,106건(재라벨 실측 · 감사 시점 908)이 '충실구현' 교훈으로 적립돼 corpus 47%·hypothesis_index 33% 를 오염시켰다.
#   셀의 교훈은 블록 L-code(rf_block_lcode.R · mode=reinforcement)가 정본이다. 스위치 소비자 = run_paper_replication.R §10.
Sys.setenv(QVEST_RP_NO_LCODE = "1")

wr <- function(o) write(toJSON(o, auto_unbox = TRUE, pretty = TRUE, null = "null"), OUT_P)
SPEC <- fromJSON(SPEC_P, simplifyVector = FALSE)
PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
AX <- PROG$fixed_axes

# ★시행 회계 (2026-09-23 · 감사 D3-01 · 플랜 P0-01). 러너가 등록 시점 계보 누적 측정 시행수를 spec 에 싣는다.
#   강화 셀은 열거 격자 argmax 로 선택되므로 sweep 이다(measurement-graduation §3 chain 자격 ② 미충족).
#   ★spec 에 회계가 없으면(이 수리 이전에 쓰인 spec 의 재개) N 을 **추정하지 않는다** — n=1 + 라벨로 기록한다.
#     sweep·n=1 이면 essence 의 DSR 이 NA 라 A 분기 dsr_ok 가 FALSE → A 는 막히고 B/C/F 는 불변(fail-closed).
#   판정은 순수 함수 하나(.rf_sel_args) — 검사(08_Tests/reinforcement/test_rf_selection_accounting.R)가 이 정의를 파싱해 직접 부른다.
.rf_sel_args <- function(spec) {
  sa <- spec$selection_accounting
  n <- suppressWarnings(as.integer(sa$n_family_at_registration %||% NA)[1])
  ok <- length(n) == 1L && is.finite(n) && n >= 1L
  list(selection_type = "sweep",
       n_trials_cumulative = if (ok) n else 1L,
       n_trials_basis = if (ok) as.character(sa$n_trials_basis %||% "lineage_measured_cells_at_registration")[1]
                        else "unknown_legacy_spec_no_accounting",
       family_root = as.character(sa$family_root %||% NA)[1])
}
.sa <- SPEC$selection_accounting
.SEL <- .rf_sel_args(SPEC)
SEL_TYPE <- .SEL$selection_type; N_TRIALS <- .SEL$n_trials_cumulative; N_BASIS <- .SEL$n_trials_basis

## ★리프레시 배리어 — 셀 시작 2차 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24).
##   진행 중인 tick 이 잠금 생성 **뒤에** 이 워커를 띄운 경우(앞 레인이 오래 도는 사이 daily_refresh 가 시작) —
##   RAWDATA 를 읽는 러너(load_rawdata) **직전**에 판정한다. held 면 rb_cell_wait_s()(기본 600초 · 근거는
##   refresh_barrier.R 머리) 동안 기다리고, 그래도 held 면 측정·등급 기록 없이 끝낸다:
##   ok=FALSE · deferred="refresh_lock" → 부모(reinforce_auto_parallel.R ③)가 원장에 아무것도 쓰지 않는다
##   (등록만 된 칸 = pending → 다음 tick 재개 · fail_count 무증가 · 시도 예산 무소모). F·NA 등급 기록 금지.
##   판정기 불능(error)도 막는다(fail-closed). 잠금 없음이면 아무것도 안 하고 지나간다.
##   ★판정과 load_rawdata 사이 틈은 엔진이 적재 직후 한 번 더 본다(QVEST_RB_ENGINE_RECHECK — rf_cell_engine.R).
.rb_defer <- function(st, waited, why, err = NULL) {
  wr(list(n = N, code = SPEC$code, block = SPEC$block, ok = FALSE, deferred = "refresh_lock", waited_s = waited,
          barrier = list(state = st$state %||% "", lock = st$lock %||% "", pid = st$pid %||% "",
                         reason = st$reason %||% "", path = st$path %||% ""),
          err = err %||% sprintf("[refresh_barrier] %s — %s(lock=%s pid=%s reason=%s) · 측정·등급 기록 없이 종료(다음 tick 재개)",
                                 why, st$state %||% "?", st$lock %||% "", st$pid %||% "", st$reason %||% "")))
  quit(status = 3)
}
.rb_w <- tryCatch({
  .rb_src <- file.path(ROOT, "02_Infrastructure/ops/refresh_barrier.R")
  if (!file.exists(.rb_src)) .rb_src <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/refresh_barrier.R"
  .RBX <- new.env(); sys.source(.rb_src, envir = .RBX, keep.source = FALSE)
  .RBX$rb_wait(.RBX$rb_cell_wait_s(), root = ROOT)
}, error = function(e) list(proceed = FALSE, waited_s = 0, status = list(state = "error", reason = conditionMessage(e))))
if (!isTRUE(.rb_w$proceed)) .rb_defer(.rb_w$status, .rb_w$waited_s, sprintf("셀 시작 대기 %s초 뒤에도 막힘", .rb_w$waited_s))
Sys.setenv(QVEST_RB_ENGINE_RECHECK = "1")

res <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")))
  UNIV <- if (identical(SPEC$universe$kind, "k200_kq150")) "K200_KQ150" else toupper(SPEC$universe$kind)
  run_paper_replication(
    strategy_name = SNAME, strategy_idea = SPEC$idea %||% SPEC$label %||% SPEC$code,
    factor_engine_path = file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"),
    # ★2026-09-01 수리 — 구판은 `n =` 을 넘겼는데 러너는 `spec$n_max` / `spec$n_long` 을 읽는다.
    #   키가 어긋나 격자의 n_max 가 **한 번도 전달된 적이 없고**, 기본값 25 위에 lfrac 10% 가
    #   곱해져 실제 보유가 3종목이었다(실측: factors_panel 월 25행 -> 보유 3종, 라이브 셀 전부 n_max 3).
    #   ★엔진이 이미 상위 25를 잘라 FACTORS 를 내보내므로 러너가 다시 분위로 자르면 이중 선정이다.
    #   n_long 을 명시해 "엔진이 건넨 것을 그대로 담는다" 로 만든다.
    portfolio_spec = list(construction = "top_n_long",
                          n_long = AX$n_max, n_max = AX$n_max,
                          weighting = SPEC$weighting$kind, rebalance = "monthly"),
    universe = UNIV, source_paper = SPEC$root_paper,
    require_source_paper = FALSE,   # ★강화 레인 — 근거 의무 해제(2026-09-03). 있으면 그대로 기록된다.
    commission_paper = AX$commission_bps / 10000, start_date = AX$start_date,
    send_telegram = FALSE,
    selection_type = SEL_TYPE, n_trials_cumulative = N_TRIALS,
    measurement_tags = list(n_trials_basis = N_BASIS,
                            family_root = as.character(.sa$family_root %||% NA)[1]))
}, error = function(e) structure(list(err = conditionMessage(e)), class = "rf_err"))

if (inherits(res, "rf_err")) {
  # ★엔진이 RAWDATA 적재 직후 재판정에서 잠금을 봤다 — 실패가 아니라 미측정 종료(위 .rb_defer 와 같은 표식 · 2026-09-24)
  if (grepl("[refresh_barrier]", res$err, fixed = TRUE))
    .rb_defer(list(state = "held", reason = "engine_recheck"), .rb_w$waited_s, "RAWDATA 적재 직후 재판정", err = res$err)
  wr(list(n = N, code = SPEC$code, ok = FALSE, err = res$err)); quit(status = 1)
}

ar <- res$authoritative_remeasure_path %||% file.path(res$out_dir %||% "", "authoritative_remeasure.json")
if (!file.exists(ar)) {
  # 산출 루트에서 이 run 의 것을 고른다 (병렬이므로 mtime 최신 = 남의 것일 수 있어 strategy_name 으로 대조)
  cand <- list.files(file.path(ROOT, "stage_artifacts/replication"),
                     pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
  # ★재측정 형제 판(P0-05 · <run>/remeasure_<key>/authoritative_remeasure.json — 원 산출물의 다른 규약 판)은 새 측정이 아니다 —
  #   폴백 후보에서 뺀다(2026-09-24 · 통합 검증 L-B1 · 원장 rebase 형제 위치 = 칸 산출물 안)
  cand <- cand[!grepl("/remeasure_[^/]+/authoritative_remeasure\\.json$", gsub("\\", "/", cand, fixed = TRUE))]
  hit <- Filter(function(f) {
    j <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
    !is.null(j) && identical(j$strategy_name, SNAME)
  }, cand)
  if (length(hit)) ar <- hit[which.max(file.mtime(hit))]
}
if (!file.exists(ar)) { wr(list(n = N, code = SPEC$code, ok = FALSE, err = "authoritative_remeasure.json 부재")); quit(status = 1) }

AR <- fromJSON(ar, simplifyVector = TRUE); es <- AR$essence
wr(list(n = N, code = SPEC$code, block = SPEC$block, ok = TRUE,
        grade = AR$essence_grade, strategy_name = SNAME, artifacts = dirname(ar), spec = SPEC_P,
        essence = list(cell_code = SPEC$code, block = SPEC$block,
                       port_t = es$portfolio_alpha_t_nw_lag3, net_sharpe = es$net_sharpe,
                       cagr = es$cagr, mdd = es$mdd, calmar = es$calmar,
                       oos_retention = es$oos_retention,
                       # ★시행 회계를 원장까지 싣는다(2026-09-23 P0-01) — 산출물에만 있으면 선택 감사가 원장을 못 읽는다
                       dsr = es$dsr, selection_type = AR$selection_type %||% SEL_TYPE,
                       n_trials_cumulative = AR$n_trials_cumulative %||% N_TRIALS,
                       spec = SPEC_P, source = "authoritative_remeasure.json")))
quit(status = 0)
