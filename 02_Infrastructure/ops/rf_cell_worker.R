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

wr <- function(o) write(toJSON(o, auto_unbox = TRUE, pretty = TRUE, null = "null"), OUT_P)
SPEC <- fromJSON(SPEC_P, simplifyVector = FALSE)
PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
AX <- PROG$fixed_axes

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
    send_telegram = FALSE)
}, error = function(e) structure(list(err = conditionMessage(e)), class = "rf_err"))

if (inherits(res, "rf_err")) {
  wr(list(n = N, code = SPEC$code, ok = FALSE, err = res$err)); quit(status = 1)
}

ar <- res$authoritative_remeasure_path %||% file.path(res$out_dir %||% "", "authoritative_remeasure.json")
if (!file.exists(ar)) {
  # 산출 루트에서 이 run 의 것을 고른다 (병렬이므로 mtime 최신 = 남의 것일 수 있어 strategy_name 으로 대조)
  cand <- list.files(file.path(ROOT, "stage_artifacts/replication"),
                     pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
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
                       spec = SPEC_P, source = "authoritative_remeasure.json")))
quit(status = 0)
