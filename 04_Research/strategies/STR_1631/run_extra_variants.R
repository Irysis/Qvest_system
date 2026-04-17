cat("=== STR_1631 S5 추가 변형: V4b(tau=0.5), V4c(tau=2.0), V9b(winsor 3sigma) ===\n")
## S5 minimum 9건 달성을 위한 추가 파라미터 변형
## V4b: tau=0.5 (더 집중). V4c: tau=2.0 (더 분산). V9b: ±3 sigma winsorize
## 구조적 변형(V1~V4/V8/V9/V10) 이후 파라미터 변형 검토 (S5 Rules v7 준수)

t0 <- Sys.time()

.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts)
  library(PerformanceAnalytics); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(PORTFOLIO_DIR, "advanced_weights.R"))
source(file.path(PORTFOLIO_DIR, "shared_factor_runner.R"))
source(file.path(REGIME_DIR, "regime_engine_daily.R"))

res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA[Date >= as.Date("2004-01-01")]
BM_DT   <- res$BM_DT; rm(res)

factors_path <- file.path(STRAT_DIR, "output", "factors.csv")
FACTORS <- fread(factors_path)
FACTORS[, Date := as.Date(Date)]
FACTORS <- FACTORS[Date >= as.Date("2004-01-01")]

REGIME <- build_daily_regime(use_cache = TRUE)
setkey(REGIME, Date)

# V4b: Softmax tau=0.5 (집중). V4c: tau=2.0 (분산). V9b: winsor 3sigma
# 이를 위해 inline wrapper 등록
# backtest_harness에 "softmax_tilt" method는 tau=1.0 고정.
# tau 파라미터를 직접 전달하는 인터페이스가 없으므로
# wm$params로 확장하거나, 별도 method 명 추가
# 가장 간단한 방법: 글로벌 환경에 파라미터를 넣고 함수 오버라이드

# softmax_tilt_tau05 wrapper
environment(calc_softmax_tilt_weights)

# run_monthly_simulation에서 method="softmax_tilt_tau05" 등을 인식하려면
# backtest_harness 분기 추가가 필요 — 대신 shared_factor_runner 우회해서
# 각 변형을 개별 run_monthly_simulation 호출로 처리

cat("[extra] Running V4b (softmax tau=0.5)...\n")
sim_v4b <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L),
  weight_method = "softmax_tilt",
  cov_method = "gerber_rmt",
  regime_dt = REGIME
)

# Override: re-run with tau=0.5 by monkey-patching calc_softmax_tilt_weights
orig_fn <- calc_softmax_tilt_weights
calc_softmax_tilt_weights <<- function(tickers, scores, ret_dt,
                                        alpha = 0.4, tau = 0.5, ...) {
  orig_fn(tickers, scores, ret_dt, alpha = alpha, tau = tau, ...)
}

cat("[extra] Running V4b (tau=0.5) via patched function...\n")
sim_v4b <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L),
  weight_method = "softmax_tilt",
  cov_method = "gerber_rmt",
  regime_dt = REGIME
)
perf_v4b <- summarise_perf(sim_v4b$strategy_xts, "SoftmaxTilt_V4b_tau05")
to_v4b   <- tryCatch(calc_turnover(sim_v4b$PORTFOLIO_LOG, sim_v4b$DAILY_NAV_DT), error = function(e) NA)

# Restore and patch for tau=2.0
calc_softmax_tilt_weights <<- function(tickers, scores, ret_dt,
                                        alpha = 0.4, tau = 2.0, ...) {
  orig_fn(tickers, scores, ret_dt, alpha = alpha, tau = tau, ...)
}

cat("[extra] Running V4c (tau=2.0)...\n")
sim_v4c <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L),
  weight_method = "softmax_tilt",
  cov_method = "gerber_rmt",
  regime_dt = REGIME
)
perf_v4c <- summarise_perf(sim_v4c$strategy_xts, "SoftmaxTilt_V4c_tau20")
to_v4c   <- tryCatch(calc_turnover(sim_v4c$PORTFOLIO_LOG, sim_v4c$DAILY_NAV_DT), error = function(e) NA)

# Restore original
calc_softmax_tilt_weights <<- orig_fn

# Patch for winsor 3 sigma
orig_winsor <- calc_winsor_tilt_weights
calc_winsor_tilt_weights <<- function(tickers, scores, ret_dt,
                                       alpha = 0.4, winsor_sd = 3.0, ...) {
  orig_winsor(tickers, scores, ret_dt, alpha = alpha, winsor_sd = winsor_sd, ...)
}

cat("[extra] Running V9b (winsor 3sigma)...\n")
sim_v9b <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L),
  weight_method = "winsor_tilt",
  cov_method = "gerber_rmt"
)
perf_v9b <- summarise_perf(sim_v9b$strategy_xts, "WinsorTilt_V9b_3sig")
to_v9b   <- tryCatch(calc_turnover(sim_v9b$PORTFOLIO_LOG, sim_v9b$DAILY_NAV_DT), error = function(e) NA)

# Restore
calc_winsor_tilt_weights <<- orig_winsor

# Summary
results_extra <- rbindlist(list(
  cbind(perf_v4b, data.table(TO = to_v4b, Method = "softmax_tau05")),
  cbind(perf_v4c, data.table(TO = to_v4c, Method = "softmax_tau20")),
  cbind(perf_v9b, data.table(TO = to_v9b, Method = "winsor_3sigma"))
), fill = TRUE)

cat("\n[Extra Variants Results]\n")
print(results_extra[, .(Label, Sharpe, CAGR, MDD, TO, Method)])

# Append to weight_comparison.csv
existing_csv <- file.path(OUT_DIR, "weight_comparison.csv")
if (file.exists(existing_csv)) {
  existing <- fread(existing_csv)
  combined <- rbindlist(list(existing, results_extra), fill = TRUE)
  setorder(combined, -Sharpe)
  fwrite(combined, existing_csv)
  cat(sprintf("[saved] Updated %s (%d rows)\n", existing_csv, nrow(combined)))
}

cat(sprintf("\n[완료] %.1f분\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
