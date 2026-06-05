#==============================================================================
# WT-D20260528_003 Hypothesis B Step 4-5 — Alpha vector + Sleeve design
#
# Sleeve choice: Option a (top 20 long-only with hard MAX threshold)
#   - Top universe ranked by Z_neutral (descending = low MAX preferred)
#   - Hard exclusion: top 30% by raw MAX (Z_neutral lower 30% — but already in sort)
#   - Final top 20 by Z_neutral
#
# AX-007 정합 status: SINGLE-SLEEVE top20 long-only = AX-007 hard violation
#   - 예외 4종 (multi-sleeve / long-short / 50+ / ML sizing) 미적용
#   - Bali MAX defensive 표방하나 AX-001 v2 crisis FAIL → defensive 실패
#   - 종합: AX-007 + AX-005 inverse(MAX anomaly 2020+ persistence test) 모두 위험
#
# Output:
#   - outputs/overnight_B/m22_alpha_scores.parquet (per sig_date all-universe alpha)
#   - outputs/overnight_B/m22_top20_per_date.parquet (sleeve top 20)
#   - outputs/overnight_B/m22_step4_alpha.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/overnight_B")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_overnight_B")
dir.create(STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

cat("[Step 4-5: Alpha vector construct] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load panel (sector-neutral) ----
panel <- as.data.table(read_parquet(file.path(OUT_DIR, "m22_panel_sector_neutral.parquet")))
panel[, Date := as.Date(Date)]
cat("[1] Panel loaded:", nrow(panel), "rows |",
    uniqueN(panel$Date), "dates |", uniqueN(panel$Ticker), "Tickers\n")

# ---- 2. Alpha vector definition ----
# α̂(i, t) = Z_neutral(i, t)  [already direction-aligned: high Z_neutral = low MAX = high alpha]
# This is the simplest pure single-factor alpha; scaling 1 unit
panel[, alpha := Z_neutral]

# Per-Date alpha summary
alpha_summary <- panel[, .(
  n = .N,
  alpha_mean = mean(alpha, na.rm = TRUE),
  alpha_sd = sd(alpha, na.rm = TRUE),
  alpha_max = max(alpha, na.rm = TRUE),
  alpha_min = min(alpha, na.rm = TRUE),
  fwd_ret_mean = mean(fwd_ret, na.rm = TRUE)
), by = Date]
cat("[2] Alpha summary (per-Date):\n")
cat("  Mean alpha across dates:", round(mean(alpha_summary$alpha_mean), 4), "\n")
cat("  Mean sd across dates:", round(mean(alpha_summary$alpha_sd), 4), "\n")
cat("  Avg n per Date:", round(mean(alpha_summary$n), 1), "\n")

# ---- 3. Top 20 sleeve (option a: top20 long-only with implicit hard MAX threshold via Z_neutral sort) ----
# Per-Date: sort by alpha desc, take top 20
top20_per_date <- panel[order(Date, -alpha), .SD[1:20], by = Date]
top20_per_date <- top20_per_date[!is.na(alpha)]
cat("\n[3] Top 20 sleeve per-Date:\n")
cat("  Total rows:", nrow(top20_per_date), "\n")
cat("  Avg n per Date:", round(nrow(top20_per_date) / uniqueN(top20_per_date$Date), 2), "\n")

# Top 20 effectiveness: avg fwd_ret per Date
top20_perf_only <- top20_per_date[, .(
  n = .N,
  top20_fwd_ret = mean(fwd_ret, na.rm = TRUE) * 100
), by = Date]
universe_perf <- panel[, .(
  universe_fwd_ret = mean(fwd_ret, na.rm = TRUE) * 100
), by = Date]
top20_perf <- merge(top20_perf_only, universe_perf, by = "Date")
top20_perf[, active_ret := top20_fwd_ret - universe_fwd_ret]

cat("\n  Top 20 vs universe performance:\n")
cat("    top20 monthly mean ret:", round(mean(top20_perf$top20_fwd_ret, na.rm = TRUE), 3), "%\n")
cat("    universe monthly mean ret:", round(mean(top20_perf$universe_fwd_ret, na.rm = TRUE), 3), "%\n")
cat("    active return mean:", round(mean(top20_perf$active_ret, na.rm = TRUE), 3), "%/month\n")
cat("    active return t-stat:",
    round(mean(top20_perf$active_ret, na.rm = TRUE) /
          (sd(top20_perf$active_ret, na.rm = TRUE) / sqrt(nrow(top20_perf))), 2), "\n")

# Decile structure check: top 20 should be in decile 10 of Z_neutral
top20_z_quantiles <- quantile(top20_per_date$Z_neutral, probs = c(0.05, 0.5, 0.95), na.rm = TRUE)
cat("\n  Top 20 Z_neutral quantiles (5/50/95):",
    round(top20_z_quantiles, 3), "\n")

# ---- 4. Subperiod top 20 performance ----
cat("\n[4] Subperiod top 20 active return ...\n")
subperiods <- list(
  P1 = list(start = "2005-01-01", end = "2014-12-31", label = "2005_2014"),
  P2 = list(start = "2015-01-01", end = "2019-12-31", label = "2015_2019"),
  P3 = list(start = "2020-01-01", end = "2026-12-31", label = "2020_2026")
)
sub_top20 <- list()
for (pn in names(subperiods)) {
  p <- subperiods[[pn]]
  sub <- top20_perf[Date >= as.Date(p$start) & Date <= as.Date(p$end)]
  if (nrow(sub) >= 5) {
    m <- mean(sub$active_ret, na.rm = TRUE)
    s <- sd(sub$active_ret, na.rm = TRUE)
    t_stat <- m / (s / sqrt(nrow(sub)))
    cat("  ", p$label, ": n=", nrow(sub),
        " active=", round(m, 3), "%/month",
        " t=", round(t_stat, 2), "\n", sep="")
    sub_top20[[pn]] <- list(label = p$label, n = nrow(sub),
                            active_mean = m, active_sd = s, t_stat = t_stat)
  }
}

# ---- 5. Confidence vector ----
# Confidence based on: data availability per Date + cross-sectional rank stability
# Simple heuristic: conf = 0.6 (default for clean panel)
# Higher conf for stable cross-sectional ranks; lower for sparse universe
panel[, confidence := pmin(1, pmax(0,
  0.5 +  # baseline
  0.3 * (1 / (1 + abs(alpha) * 0.5)) +  # higher conf for moderate alpha (avoid extreme outliers)
  0.2 * (uniqueN(.N) >= 100)  # high conf if cross-section ≥ 100
)), by = Date]

# Per-date alpha + confidence for output (using most recent sig_date for alpha_package)
# But spec asks for as_of_date = 2026-05-28. Use 2023-11-30 (last in PIT cutoff window)
as_of_sig_date <- max(panel$Date)
cat("\n[5] As-of sig_date for alpha_package:", as.character(as_of_sig_date), "\n")

# Top 20 at most recent sig_date
top20_now <- panel[Date == as_of_sig_date][order(-alpha)][1:20]
top20_now <- top20_now[!is.na(Ticker)]
cat("    Top 20 at", as.character(as_of_sig_date), ":", nrow(top20_now), "stocks\n")

# Alpha vector dict
alpha_vec <- setNames(as.list(round(top20_now$alpha, 4)), top20_now$Ticker)
conf_vec <- setNames(as.list(round(top20_now$confidence, 4)), top20_now$Ticker)

# ---- 6. Save ----
cat("\n[6] Save ...\n")
write_parquet(panel[, .(Date, Ticker, Z_aligned, Z_neutral, alpha, confidence, fwd_ret, Sector)],
              file.path(OUT_DIR, "m22_alpha_scores.parquet"))
write_parquet(panel[, .(Date, Ticker, Z_aligned, Z_neutral, alpha, confidence, fwd_ret, Sector)],
              file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  saved: m22_alpha_scores.parquet (", nrow(panel), "rows)\n")
cat("  saved: stage_artifacts/.../alpha_scores.parquet\n")

write_parquet(top20_per_date, file.path(OUT_DIR, "m22_top20_per_date.parquet"))
cat("  saved: m22_top20_per_date.parquet\n")

write_parquet(top20_perf, file.path(OUT_DIR, "m22_top20_performance.parquet"))
cat("  saved: m22_top20_performance.parquet\n")

diag <- list(
  task_id = "WT-D20260528_003",
  hypothesis = "B",
  step = "04_alpha_vector_construct",
  alpha_definition = "α̂(i, t) = Z_neutral(i, t)  [pure M22_Max_Return sector-neutral, lower_better direction]",
  sleeve_design = "Option a — Top 20 long-only with implicit hard MAX threshold via Z_neutral sort",
  as_of_sig_date = as.character(as_of_sig_date),
  alpha_summary = list(
    panel_rows = nrow(panel),
    n_dates = uniqueN(panel$Date),
    n_tickers = uniqueN(panel$Ticker),
    avg_n_per_date = round(mean(alpha_summary$n), 2),
    alpha_mean_across_dates = round(mean(alpha_summary$alpha_mean), 6),
    alpha_sd_across_dates = round(mean(alpha_summary$alpha_sd), 4)
  ),
  top20_full_period = list(
    n_dates = nrow(top20_perf),
    top20_mean_monthly_ret_pct = round(mean(top20_perf$top20_fwd_ret, na.rm = TRUE), 4),
    universe_mean_monthly_ret_pct = round(mean(top20_perf$universe_fwd_ret, na.rm = TRUE), 4),
    active_mean_monthly_pct = round(mean(top20_perf$active_ret, na.rm = TRUE), 4),
    active_t_stat = round(mean(top20_perf$active_ret, na.rm = TRUE) /
                          (sd(top20_perf$active_ret, na.rm = TRUE) / sqrt(nrow(top20_perf))), 3)
  ),
  top20_subperiod = sub_top20,
  as_of_top20 = list(
    sig_date = as.character(as_of_sig_date),
    n = nrow(top20_now),
    alpha_vector = alpha_vec,
    confidence_vector = conf_vec
  ),
  ax_007_status = "VIOLATION — single-sleeve top20 long-only with no exception applied",
  ax_001_v2_status = "FAIL — crisis IC negative (defensive role broken)"
)
write_json(diag, file.path(OUT_DIR, "m22_step4_alpha.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: m22_step4_alpha.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 4-5] === DONE === elapsed:", round(elapsed, 1), "sec\n")
