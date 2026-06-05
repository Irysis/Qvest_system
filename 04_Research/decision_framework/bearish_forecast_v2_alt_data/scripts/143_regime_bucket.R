## ============================================================
## Cycle 56B Step 2 — Regime Bucket Audit (training feasibility)
##
## Purpose:
##   Per-regime per-fold training feasibility check. MoE expert는
##   해당 regime training data만 사용 → 각 regime의 train 기간
##   bear event 수 (y_tail_q126=1) 확인.
##
## 4-fold Walk-forward training period (53H mirror):
##   FINAL_TRAIN: 1995-01-01 ~ 2015-12-31
##   각 regime expert는 이 기간의 해당 regime 부분만 학습
##
## Per-regime feasibility:
##   - 최소 1000 train days
##   - 최소 30 bear events (y_tail_q126==1)
##   - 충족 X regime은 MoE에서 fallback (sample-weighted full panel learning)
##
## Output:
##   outputs/01_data/regime_bucket_train_summary.csv
##   outputs/04_evaluation/cycle56b_step2_regime_bucket_audit.json
## ============================================================

cat("============================================================\n")
cat("Cycle 56B Step 2 — Regime Bucket Audit\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(BASE_DIR,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
OUT_DATA <- file.path(WS_DIR, "outputs/01_data")
OUT_EVAL <- file.path(WS_DIR, "outputs/04_evaluation")

# ============================================================
# 1. Load regime daily + targets
# ============================================================
cat("[1] Load regime daily + targets\n")

regime_daily <- as.data.table(read_parquet(
  file.path(OUT_DATA, "regime_daily_lag1.parquet")))
targets <- as.data.table(read_parquet(
  file.path(WS_DIR, "outputs/02_targets/targets_long_horizon.parquet")))

regime_daily[, Date := as.Date(Date)]
targets[, Date := as.Date(Date)]

dt <- merge(regime_daily, targets[, .(Date, y_tail_q15, y_tail_q126)],
            by = "Date", all.x = TRUE)
setorder(dt, Date)

cat(sprintf("  merged rows: %d\n", nrow(dt)))

# ============================================================
# 2. Train period (1995-01-01 ~ 2015-12-31) regime + bear feasibility
# ============================================================
cat("\n[2] FINAL_TRAIN period (1995-2015) regime × bear stats\n")

train_dt <- dt[Date >= as.Date("1995-01-01") &
                Date <= as.Date("2015-12-31") &
                !is.na(regime_state)]
cat(sprintf("  train rows (non-NA regime): %d\n", nrow(train_dt)))

regime_train_q126 <- train_dt[, .(
  n_days = .N,
  n_bear_q126 = sum(y_tail_q126 == 1, na.rm = TRUE),
  bear_rate_q126 = round(mean(y_tail_q126 == 1, na.rm = TRUE), 4),
  n_bear_q15 = sum(y_tail_q15 == 1, na.rm = TRUE),
  bear_rate_q15 = round(mean(y_tail_q15 == 1, na.rm = TRUE), 4),
  first_date = min(Date),
  last_date = max(Date)
), by = regime_state]
setorder(regime_train_q126, regime_state)

cat("\n  Per-regime train stats:\n")
print(regime_train_q126)

# Feasibility flags
regime_train_q126[, feasible_q126 := n_days >= 1000 & n_bear_q126 >= 30]
regime_train_q126[, feasible_q15 := n_days >= 1000 & n_bear_q15 >= 30]

cat("\n  Feasibility (n_days>=1000 & n_bear>=30):\n")
print(regime_train_q126[, .(regime_state, n_days, n_bear_q126, feasible_q126,
                             n_bear_q15, feasible_q15)])

# ============================================================
# 3. Per-fold train period regime breakdown (5 walk-forward folds)
# ============================================================
cat("\n[3] Per-fold train regime breakdown\n")

folds <- list(
  list(name = "Fold1_Lehman",     train_start = "1995-01-01", train_end = "2007-12-31"),
  list(name = "Fold2_EuroAfter",  train_start = "1995-01-01", train_end = "2009-12-31"),
  list(name = "Fold3_CyprusTT",   train_start = "1995-01-01", train_end = "2011-12-31"),
  list(name = "Fold4_KRLowVol",   train_start = "1995-01-01", train_end = "2013-12-31"),
  list(name = "Fold5_BestSignal", train_start = "1995-01-01", train_end = "2015-12-31")
)

fold_breakdown <- list()
for (fi in folds) {
  fd <- dt[Date >= as.Date(fi$train_start) & Date <= as.Date(fi$train_end) &
            !is.na(regime_state)]
  reg_b <- fd[, .(n_days = .N,
                   n_bear_q126 = sum(y_tail_q126 == 1, na.rm = TRUE),
                   n_bear_q15 = sum(y_tail_q15 == 1, na.rm = TRUE)),
              by = regime_state]
  reg_b[, fold := fi$name]
  reg_b[, train_end := fi$train_end]
  fold_breakdown[[fi$name]] <- reg_b
}
fold_dt <- rbindlist(fold_breakdown)
setorder(fold_dt, fold, regime_state)

cat("\n  Per-fold per-regime breakdown:\n")
print(fold_dt)

# ============================================================
# 4. OOS regime breakdown (2018-2026)
# ============================================================
cat("\n[4] OOS period (2018-2026) regime × bear breakdown\n")

oos_dt <- dt[Date >= as.Date("2018-01-01") & Date <= as.Date("2026-04-30") &
              !is.na(regime_state)]

oos_regime <- oos_dt[, .(
  n_days = .N,
  n_bear_q126 = sum(y_tail_q126 == 1, na.rm = TRUE),
  bear_rate_q126 = round(mean(y_tail_q126 == 1, na.rm = TRUE), 4),
  n_bear_q15 = sum(y_tail_q15 == 1, na.rm = TRUE),
  bear_rate_q15 = round(mean(y_tail_q15 == 1, na.rm = TRUE), 4)
), by = regime_state]
setorder(oos_regime, regime_state)
cat("\n  OOS per-regime stats:\n")
print(oos_regime)

# ============================================================
# 5. Save artifacts
# ============================================================
fwrite(regime_train_q126,
       file.path(OUT_DATA, "regime_bucket_train_summary.csv"))
fwrite(fold_dt,
       file.path(OUT_DATA, "regime_bucket_per_fold_summary.csv"))
fwrite(oos_regime,
       file.path(OUT_DATA, "regime_bucket_oos_summary.csv"))

audit <- list(
  cycle = "56B_step2_regime_bucket",
  train_period = list(start = "1995-01-01", end = "2015-12-31"),
  train_regime_stats = lapply(seq_len(nrow(regime_train_q126)), function(i) {
    as.list(regime_train_q126[i])
  }),
  feasibility_threshold = list(min_n_days = 1000L, min_n_bear = 30L),
  fold_breakdown = lapply(seq_len(nrow(fold_dt)), function(i) {
    as.list(fold_dt[i])
  }),
  oos_regime_stats = lapply(seq_len(nrow(oos_regime)), function(i) {
    as.list(oos_regime[i])
  }),
  feasibility_summary = list(
    q126_feasible_regimes = regime_train_q126[feasible_q126 == TRUE]$regime_state,
    q126_infeasible_regimes = regime_train_q126[feasible_q126 == FALSE]$regime_state,
    q15_feasible_regimes = regime_train_q126[feasible_q15 == TRUE]$regime_state,
    q15_infeasible_regimes = regime_train_q126[feasible_q15 == FALSE]$regime_state
  )
)

write_json(audit, file.path(OUT_EVAL, "cycle56b_step2_regime_bucket_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")

cat("\n[done] regime_bucket_train_summary.csv + per_fold + oos summaries\n")
cat("        cycle56b_step2_regime_bucket_audit.json\n")
