# =============================================================================
# census v3 targeted — val_rd_wc reconstructed composite, FORMAL scoring
#   run_monthly_simulation (daily NAV engine) -> build_bt_result (frequency=daily)
#   -> audit_bt_result -> essence_score(selection_type="chain")
#   metric_type = backtested (forge-authoritative ladder, measurement-graduation s1~s3)
#
# Composite variant: env CENSUS_VARIANT in {A, B} (default A)
#   A: score = value_z(mean of 6 value Z, n_val>=3) + Z(IN03) + Z(XF_LL05) + 0.5*Z(R05)
#   B: score = mean(value_z, Z(IN03), Z(XF_LL05)) + 0.5*Z(R05)
#   (missing non-value components treated as 0 in A / na.rm mean in B)
# Universe: K200 u KQ150 (PIT), liq 20d ADV>=2e8 t-1, bad-flag excl. (chunks from sweep)
# n_holdings=25, weight_method=equal, commission=15bps (engine flat per-rebalance buy;
#   B0 known limit: accurate near TO~6x/yr, overstated for TO<~3x — note recorded)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT    <- file.path(PROJECT_ROOT, "04_Research/factor_db/census_v3_targeted")
CHUNKS <- file.path(OUT, "fz_chunks")
VARIANT <- Sys.getenv("CENSUS_VARIANT", "A")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/essence_score.R"))

VALUE_FACTORS <- c("V02_EP","V14_EBIT_EV","V07_EV_EBITDA","V20_SP","V13_EV_Sales","V01_BM")

# ---- 1. composite scores from sweep chunks (already universe+liq filtered) ----
cat("[1] Building composite FACTORS from fz_chunks (variant ", VARIANT, ")...\n", sep = "")
chunk_files <- list.files(CHUNKS, pattern = "^fz_\\d{6}\\.parquet$", full.names = TRUE)
stopifnot(length(chunk_files) > 200)
FZ <- rbindlist(lapply(chunk_files, function(p) as.data.table(read_parquet(p))), fill = TRUE)
CW <- dcast(FZ[Factor_Name %in% c(VALUE_FACTORS, "IN03_RD_to_Market",
                                  "XF_LL05_WorkingCapital","R05_Tail_Risk")],
            ym + Ticker ~ Factor_Name, value.var = "Z")
vcols <- intersect(VALUE_FACTORS, names(CW))
CW[, n_val := rowSums(!is.na(.SD)), .SDcols = vcols]
CW[, value_z := rowMeans(.SD, na.rm = TRUE), .SDcols = vcols]
CW[n_val < 3, value_z := NA_real_]
.z0 <- function(x) fifelse(is.na(x), 0, x)
for (cc in c("IN03_RD_to_Market","XF_LL05_WorkingCapital","R05_Tail_Risk"))
  if (!cc %in% names(CW)) CW[, (cc) := NA_real_]

if (VARIANT == "A") {
  CW[, Score := value_z + .z0(IN03_RD_to_Market) + .z0(XF_LL05_WorkingCapital) +
                0.5 * .z0(R05_Tail_Risk)]
} else {
  CW[, Score := rowMeans(cbind(value_z, IN03_RD_to_Market, XF_LL05_WorkingCapital),
                         na.rm = TRUE) + 0.5 * .z0(R05_Tail_Risk)]
}
CW <- CW[!is.na(Score)]

# ---- 2. RAWDATA + month-end sig dates ----
cat("[2] load_rawdata...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
RAWDATA <- RAWDATA[Date >= as.Date("2006-01-01")]
BM_DT   <- BM_DT[Date >= as.Date("2006-01-01")]

RAWDATA[, ym := format(Date, "%Y%m")]
me_dates <- RAWDATA[, .(eom = max(Date)), by = ym]
RAWDATA[, ym := NULL]
FACTORS <- merge(CW[, .(ym, Ticker, Score)], me_dates, by = "ym")[, .(Date = eom, Ticker, Score)]
cat(sprintf("   FACTORS: rows=%d months=%d range=%s..%s\n",
            nrow(FACTORS), uniqueN(FACTORS$Date),
            as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date))))

# ---- 3. daily simulation (formal engine) ----
cat("[3] run_monthly_simulation (n=25, equal, 15bps)...\n")
sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
                              n_holdings = 25L, commission = 0.0015,
                              weight_method = "equal")

# ---- 4. contract build + audit + essence ----
cat("[4] build_bt_result + audit + essence_score...\n")
spec <- list(
  strategy_id     = paste0("val_rd_wc_recon_", VARIANT),
  strategy_name   = paste0("val_rd_wc reconstructed (variant ", VARIANT, ")"),
  strategy_family = "census_v3_targeted",
  signal_description = paste(
    "value6 EW Z (V02_EP,V14_EBIT_EV,V07_EV_EBITDA,V20_SP,V13_EV_Sales,V01_BM; n_val>=3)",
    if (VARIANT == "A") "+ Z(IN03_RD_to_Market) + Z(XF_LL05_WorkingCapital)"
    else "mean-combined with Z(IN03_RD_to_Market), Z(XF_LL05_WorkingCapital)",
    "+ 0.5*Z(R05_Tail_Risk); Z_Score_Aligned via load_month_factors (C13/C15)"),
  universe_rule   = "K200 u KQ150 (PIT month-end) & 20d ADV>=2e8 (t-1, C10) & no admin/halt/unfaithful",
  rebalance_frequency = "monthly",
  signal_date_rule    = "month_end",
  execution_date_rule = "month_end_signal_t_plus_1",
  weighting_method    = "equal",
  max_position_weight = 1 / 25,
  max_leverage        = 1.0,
  cash_rule           = "no signal -> cash",
  cost_model          = "flat per-rebalance buy 15bps (engine v2.3; B0 limit noted for low-TO)",
  missing_data_rule   = "missing forward price -> position carried at last close (engine)",
  risk_controls       = "none (S1 pure factor screen - no overlay)",
  lookahead_prevention = "PIT C1-C15: sig=month-end factor Z, exec t+1; liq t-1; membership PIT",
  survivorship_bias_control = "RAWDATA PIT membership (K200/KQ150 time-varying)"
)
run_id <- sprintf("CENSUSV3_VAL_%s_%s", VARIANT, format(Sys.time(), "%Y%m%d%H%M"))
bt <- build_bt_result(sim, spec, run_id = run_id,
                      strategy_id = spec$strategy_id,
                      strategy_version = "census_v3_recon",
                      benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
                      transaction_cost_bps = 15, slippage_bps = 0,
                      risk_free_rate = 0, frequency = "daily",
                      annualization_factor = 252,
                      universe_id = "K200_KQ150_LIQ2E8",
                      code_version = "run_val_formal_v1",
                      created_by_agent = "census_v3_subagent")
bt <- audit_bt_result(bt)
es <- essence_score(bt, n_trials_cumulative = 1, selection_type = "chain")

# ---- 5. emit ----
M  <- as.data.table(bt$metrics)
BC <- as.data.table(bt$benchmark_compare)
getm  <- function(nm) { v <- M[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
getbc <- function(nm) { v <- BC[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
audit_status <- tryCatch({
  a <- as.data.table(bt$audit); if ("status" %in% names(a)) {
    if (any(a$status == "FAIL" & a$severity == "critical")) "FAIL" else
    if (any(a$status == "FAIL")) "WARN" else "PASS" } else NA_character_
}, error = function(e) NA_character_)

out <- list(
  meta = list(task = "census_v3_targeted val_rd_wc formal", variant = VARIANT,
              run_id = run_id, as_of = as.character(Sys.Date()),
              metric_type = "backtested", selection_type = "chain",
              n_trials_cumulative = 1,
              engine = "run_monthly_simulation daily NAV + build_bt_result(freq=daily)"),
  essence = es,
  contract = list(
    sharpe = getm("Sharpe"), cagr = getm("CAGR"), mdd = getm("MDD"),
    calmar = getm("Calmar"),
    turnover_annual = getm("Turnover_Annual"),
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    information_ratio = getbc("Information_Ratio"),
    alpha_annualized = getbc("Alpha_Annualized")
  ),
  audit_status = audit_status,
  anchor = list(port_t = 2.30, mdd = 0.381, sr = 0.85, cagr = 0.168,
                turnover = 5.0, calmar = 0.44, grade = "B",
                note = "old census (pre-winsorize machine, artifacts lost) - memory anchor")
)
write_json(out, file.path(OUT, paste0("val_rd_wc_formal_", VARIANT, ".json")),
           pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null")
saveRDS(bt, file.path(OUT, paste0("val_rd_wc_bt_result_", VARIANT, ".rds")))

cat("\n========== FORMAL SUMMARY (variant ", VARIANT, ") ==========\n", sep = "")
cat(sprintf("grade=%s | PORT_t=%.3f | SR=%.3f | CAGR=%.2f%% | MDD=%.1f%% | Calmar=%.3f | IR=%.3f\n",
            es$grade, es$essence$portfolio_alpha_t_nw_lag3, es$essence$net_sharpe,
            es$essence$cagr * 100, es$essence$mdd * 100, es$essence$calmar,
            es$essence$net_ir))
cat(sprintf("oos_retention=%.3f (splits: %s) | audit=%s\n",
            es$essence$oos_retention,
            paste(es$oos_retention_splits, collapse = ","), audit_status))
cat("DONE_VAL_FORMAL\n")
