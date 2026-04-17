cat("=== STR_1631 S5 V8: NCO + Score Tilt ===\n")
## V8: NCO base weight + Score Tilt (alpha=0.4)
## Lopez de Prado (2020) NCO: cluster → within-cluster MinVar → HRP across
## Purpose: NCO의 클러스터 최적화 + Score Tilt 결합. MDD 개선 여부 확인.
## S5 compliance: 9건 달성을 위한 추가 변형 (현재 6건 → 7건)

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

# V8 only
wm_v8 <- list(list(name = "NCOScoreTilt_V8", method = "nco_score_tilt",
                    cov_method = "sample"))

results_v8 <- run_weight_comparison(
  FACTORS = FACTORS, RAWDATA = RAWDATA, BM_DT = BM_DT,
  weight_methods = wm_v8,
  regime_dt = REGIME,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L),
  output_dir = NULL, run_hurdle = FALSE,
  strategy_name = "STR_1631_V8_NCO", parallel = FALSE
)

comp <- results_v8$comparison
cat("\n[V8 NCOScoreTilt Result]\n")
print(comp[, .(Label, Sharpe, CAGR, MDD, TO)])

# Append to existing comparison CSV
existing_csv <- file.path(OUT_DIR, "weight_comparison.csv")
if (file.exists(existing_csv)) {
  existing <- fread(existing_csv)
  combined <- rbindlist(list(existing, comp), fill = TRUE)
  fwrite(combined, existing_csv)
  cat(sprintf("[saved] Appended to %s\n", existing_csv))
}

cat(sprintf("\n[완료] %.1f분\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
