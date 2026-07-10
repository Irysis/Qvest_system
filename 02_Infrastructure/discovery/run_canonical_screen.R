# run_canonical_screen.R — W1 브릿지 (2026-07-02)
# discovery_explore.py::canonical_confirm 이 호출. Python이 3 parquet(scores/returns/bench)를
# CS_SCRATCH에 쓰고 이 래퍼를 source → canonical_screen_bt(contract 경유) → cs_result.json 회신.
# 자체합성 없음: PORT_t(NW lag-3)·IR·alpha는 build_benchmark_compare(forge 동일 함수)가 산출.
# 실행: Rscript -e "source('<abs>/run_canonical_screen.R')"  (env: QM_ROOT, CS_SCRATCH, CS_TOPN)
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
root    <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
scratch <- Sys.getenv("CS_SCRATCH", ".")
top_n   <- as.integer(Sys.getenv("CS_TOPN", "25"))
ppy     <- as.integer(Sys.getenv("CS_PPY", "12"))   # periods/year: 월간12 / 분기4

# contract 명시 source (canonical_screen_bt.R의 .CANON_DIR sys.frame 해석이 중첩 source에서
# 실패 → build_benchmark_compare 미정의 문제 회피. 절대경로로 먼저 로드).
source(file.path(root, "02_Infrastructure", "contracts", "backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure", "contracts", "canonical_screen_bt.R"))

rd <- function(f) { x <- as.data.table(read_parquet(file.path(scratch, f))); x[, Date := as.Date(Date)]; x }
res <- tryCatch({
  scores  <- rd("cs_scores.parquet")     # Date, Ticker, score
  returns <- rd("cs_returns.parquet")    # Date, Ticker, Ret_1m (forward 1M)
  bench   <- rd("cs_bench.parquet")      # Date, BM_Ret (forward 1M)
  # (F-3 2026-07-10) diag_dual_basis=FALSE 명시 — 이 브릿지는 cs_result.json 스칼라 회신 계약
  #   (구 ~1KB). 진단 2필드(diag_ew_universe/diag_cap_tier)는 여기서 미산출(소비자 없음 + 회신 비대화 방지).
  canonical_screen_bt(scores, returns, bench, top_n = top_n, cost_bps_oneway = 15,
                      periods_per_year = ppy, diag_dual_basis = FALSE)
}, error = function(e) list(error = conditionMessage(e)))

res$benchmark_compare <- NULL; res$period_returns <- NULL   # data.table 필드는 스칼라 회신에서 제외
jsonlite::write_json(res, file.path(scratch, "cs_result.json"), auto_unbox = TRUE, na = "null")
cat("[run_canonical_screen] n_months=", if (is.null(res$n_months)) NA else res$n_months,
    " port_t=", if (is.null(res$portfolio_alpha_t_nw_lag3)) NA else round(res$portfolio_alpha_t_nw_lag3,2), "\n")
