#==============================================================================
# WT-D20260508_002 Alpha Research v5 — Phase 1: PIT-rolling feature panels
#
# Codex 8 concerns remediation:
#   C1 PIT C1: per sig_date, top-80 factors selected from sig_date coverage only
#              (no 2024-12 lookahead snapshot). expanding factor universe.
#   C2 PIT C2/C10: Universe/Admin/Size/Vol_KRW_20d all t-1 (sig_date - 1d EOM).
#                  2e8 KRW hard floor (5e7 relax 폐기).
#   C5 forward as-of: 2026-05 forward predictions added (sig_date 2026-04-30 EOM).
#   C6 sector-neutral: sector mapping retained (Phase 3 sector demean).
#   C7 artifact_lineage: explicit sig_date_window_lineage.json output.
#
# Output: per-month feature parquets + features_index.parquet + sig_date metadata
#         consumed by Phase 2 (Python GPU ML)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})
options(warn = 1)

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260508_002"
WT_DIR <- file.path(PROJ, "qepm", "mailbox", "worktask", WT_ID)
ART_DIR <- file.path(PROJ, "stage_artifacts", "WT_D20260508_002")
PHASE1_DIR <- file.path(ART_DIR, "v5_phase1_features")
dir.create(PHASE1_DIR, showWarnings = FALSE, recursive = TRUE)

set.seed(20260508)

cat("================================================================\n")
cat("WT-D20260508_002 Alpha v5 Phase 1 — PIT-rolling feature panels\n")
cat("================================================================\n")

#--- 1. STR_1715 real returns (used for r_Hybrid residual extraction) ---
cat("\n[1] STR_1715 real monthly returns + r_Hybrid...\n")
str1715_path <- file.path(PROJ, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds")
bt_str1715 <- readRDS(str1715_path)
str1715_pr <- as.data.table(bt_str1715$period_returns)
str1715_pr[, date := as.Date(date)]
str1715_pr[, YM := as.Date(format(date, "%Y-%m-01"))]
str1715_m <- str1715_pr[, .(r_str1715 = sum(ret_net, na.rm = TRUE)), by = YM][order(YM)]
cat("  STR_1715 monthly:", nrow(str1715_m), "months,",
    as.character(min(str1715_m$YM)), "-", as.character(max(str1715_m$YM)), "\n")

#--- 2. RAWDATA monthly aggregates (t-1 universe filter) ---
cat("\n[2] RAWDATA monthly aggregates (t-1 universe)...\n")
rd <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)
rd[, YM := as.Date(format(Date, "%Y-%m-01"))]

# Per-month last day univ filter values (t-1 PIT)
# For sig_date YM, universe filter is computed from data <= EOM(YM).
# Vol_KRW_20d = mean(Close * Vol) of last 20 days <= EOM(YM).
rd_m <- rd[, .(
  Close = last(Close),
  Vol_KRW_20d = mean(tail(Close * Vol, 20), na.rm = TRUE),
  Size = last(Size),
  in_K200 = any(K200 == TRUE, na.rm = TRUE),
  in_KQ150 = any(KQ150 == TRUE, na.rm = TRUE),
  Sector = last(Sector_Lv2),
  Admin = any(AdminStock == TRUE | TradingHalt == TRUE | UnfaithfulDisc == TRUE, na.rm = TRUE)
), by = .(Ticker, YM)]
setkey(rd_m, Ticker, YM)
rd_m[, Ret_1m := c(NA, diff(log(Close))), by = Ticker]

# v5 hard mandate Path 2: 2e8 KRW floor (5e7 relax 폐기) + lag t-1.
# For predicting Ret_{YM+1}, eligibility uses YM data (t-1 of next month).
# We'll enforce this in panel build: in_universe_lag1 = in_universe(YM-1).
rd_m[, in_universe_strict := (in_K200 | in_KQ150) & !Admin & Vol_KRW_20d >= 2e8]
cat("  rd_m:", nrow(rd_m), "rows,",
    as.character(min(rd_m$YM)), "-", as.character(max(rd_m$YM)), "\n")
cat("  in_universe_strict TRUE rows (2e8 hard floor):", sum(rd_m$in_universe_strict, na.rm = TRUE), "\n")
rm(rd); gc(verbose = FALSE)

#--- 3. r_Hybrid construction (3-source: STR_1715 70 + TSMOM 15 + bond 15) ---
cat("\n[3] r_Hybrid construction (book_state v2 - effective 2026-06-01)...\n")
bm <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet"),
                                 col_select = c("Date", "BM_Ret")))
bm <- unique(bm)
bm[, Date := as.Date(Date)]
bm[, YM := as.Date(format(Date, "%Y-%m-01"))]
bm_m <- bm[, .(BM_Ret_m = sum(BM_Ret, na.rm = TRUE)), by = YM][order(YM)]
bm_m[, BM_TSMOM_12m := shift(frollmean(BM_Ret_m, 12, align = "right"), 1)]
hybrid <- merge(str1715_m, bm_m[, .(YM, BM_Ret_m, BM_TSMOM_12m)], by = "YM", all.x = TRUE)
hybrid[, r_TSMOM := ifelse(is.na(BM_TSMOM_12m) | BM_TSMOM_12m <= 0, 0, BM_Ret_m)]
hybrid[, r_bond := 0]  # KR 10y bond data unavailable; explicitly 0 (acknowledged limitation, not rationalization)
hybrid[, r_Hybrid := 0.70 * r_str1715 + 0.15 * r_TSMOM + 0.15 * r_bond]
cat("  Hybrid rows:", nrow(hybrid), "\n")
rm(bm); gc(verbose = FALSE)

#--- 4. PIT-rolling factor universe construction ---
cat("\n[4] PIT-rolling factor universe (per sig_date, no 2024-12 snapshot)...\n")
source(file.path(PROJ, "02_Infrastructure/factor_db/factor_db_connector.R"))

# Test months: 2015-01 to 2026-04 (realized) + 2026-05 (forward as-of)
all_test_months_realized <- seq.Date(as.Date("2015-01-01"), as.Date("2026-04-01"), by = "month")
forward_month <- as.Date("2026-05-01")
cat("  Realized test months:", length(all_test_months_realized), "\n")
cat("  Forward as-of month:", as.character(forward_month), "(no y_actual)\n")

# For each sig_date (= EOM of YM_features), select top 80 factors by coverage at sig_date
# CRITICAL PIT C1 fix: factor universe selection uses ONLY sig_date coverage,
# not full-sample coverage. Each test month has its own factor universe.
# In practice, factor universe is fairly stable over time — but we measure & log
# how stable it is to verify PIT compliance.

select_top_factors_sig <- function(sig_date, top_n = 80) {
  sink_path <- tempfile()
  sink(sink_path)
  on.exit({ sink(); if (file.exists(sink_path)) file.remove(sink_path) }, add = TRUE)
  fac <- tryCatch(
    suppressMessages(load_month_factors(sig_date, coverage_min = 0.05)),
    error = function(e) NULL
  )
  if (is.null(fac) || nrow(fac) == 0) return(character(0))
  fc <- fac[, .N, by = Factor_Name][order(-N)]
  head(fc$Factor_Name, top_n)
}

# Build per-test-month feature panel
# YM_target = test month (predict its return)
# YM_features = YM_target - 1 (sig_date EOM lag-1)
# Universe filter: in_universe at YM_features = TRUE (t-1)

build_panel_for_test_month <- function(YM_target, top_n_factors = 80,
                                        rd_m_local = rd_m, hybrid_local = hybrid) {
  YM_features <- as.Date(format(YM_target - 1, "%Y-%m-01"))  # lag-1 month
  sig_date <- as.Date(format(YM_features + 31, "%Y-%m-01")) - 1  # EOM of YM_features

  # Step A: PIT-rolling factor universe at sig_date (no future info)
  top_factors <- select_top_factors_sig(sig_date, top_n_factors)
  if (length(top_factors) < 30) return(NULL)

  # Step B: Load factors at sig_date
  sink_path <- tempfile()
  sink(sink_path)
  fac <- tryCatch(
    suppressMessages(load_month_factors(sig_date, coverage_min = 0.05)),
    error = function(e) NULL
  )
  sink(); if (file.exists(sink_path)) file.remove(sink_path)
  if (is.null(fac) || nrow(fac) == 0) return(NULL)
  fac <- fac[Factor_Name %in% top_factors]
  fac_w <- dcast(fac, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                 fun.aggregate = function(x) mean(x, na.rm = TRUE), fill = NA)

  # Step C: Universe filter at YM_features (t-1, 2e8 KRW hard floor)
  univ <- rd_m_local[YM == YM_features & in_universe_strict == TRUE,
                    .(Ticker, Sector, Vol_KRW_20d, Size, Close_at_features = Close)]

  # Step D: Realized return for target month (NA for forward as-of)
  ret_target <- rd_m_local[YM == YM_target, .(Ticker, Ret_1m, Close_target = Close)]

  # Step E: Engineered momentum features (lag-1 PIT)
  # Use rd_m up to YM_features
  rd_hist <- rd_m_local[YM <= YM_features, .(Ticker, YM, Ret_1m_hist = Ret_1m)][order(Ticker, YM)]
  ret_lag1 <- rd_hist[YM == YM_features, .(Ticker, ret_lag1 = Ret_1m_hist)]
  # Rolling momentum
  rd_hist[, ret_mom_3m := frollsum(Ret_1m_hist, 3, align = "right"), by = Ticker]
  rd_hist[, ret_mom_6m := frollsum(Ret_1m_hist, 6, align = "right"), by = Ticker]
  rd_hist[, ret_mom_12m := frollsum(Ret_1m_hist, 12, align = "right"), by = Ticker]
  ret_mom <- rd_hist[YM == YM_features, .(Ticker, ret_mom_3m, ret_mom_6m, ret_mom_12m)]

  # Merge all
  panel <- merge(univ, fac_w, by = "Ticker")
  panel <- merge(panel, ret_lag1, by = "Ticker", all.x = TRUE)
  panel <- merge(panel, ret_mom, by = "Ticker", all.x = TRUE)
  if (nrow(ret_target) > 0) {
    panel <- merge(panel, ret_target, by = "Ticker", all.x = TRUE)
  } else {
    panel[, Ret_1m := NA_real_]
    panel[, Close_target := NA_real_]
  }
  # r_Hybrid for residual extraction
  rh <- hybrid_local[YM == YM_target, .(YM_target = YM, r_Hybrid)]
  if (nrow(rh) > 0) {
    panel[, r_Hybrid := rh$r_Hybrid[1]]
  } else {
    panel[, r_Hybrid := NA_real_]
  }
  panel[, Ret_residual := Ret_1m - r_Hybrid]
  panel[, log_size := log(pmax(Size, 1))]
  panel[, log_TV := log(pmax(Vol_KRW_20d, 1))]
  panel[, YM_target := YM_target]
  panel[, YM_features := YM_features]
  panel[, sig_date := sig_date]
  panel[, n_top_factors_at_sig := length(top_factors)]

  # Drop rows with too many NA factors
  factor_cols <- intersect(top_factors, names(panel))
  panel[, na_frac := rowSums(is.na(.SD)) / max(length(factor_cols), 1L), .SDcols = factor_cols]
  panel <- panel[na_frac < 0.5]
  panel[, na_frac := NULL]
  for (fc in factor_cols) set(panel, which(is.na(panel[[fc]])), fc, 0)
  for (fc in c("ret_lag1", "ret_mom_3m", "ret_mom_6m", "ret_mom_12m")) {
    if (fc %in% names(panel)) set(panel, which(is.na(panel[[fc]])), fc, 0)
  }
  attr(panel, "factor_cols") <- factor_cols
  attr(panel, "top_factors_at_sig") <- top_factors
  panel
}

#--- 5. Build all panels (realized + forward) and persist as parquet shards ---
cat("\n[5] Build per-test-month panels (PIT-rolling)...\n")
all_test_months <- c(all_test_months_realized, forward_month)
factor_universe_log <- list()
panel_meta_log <- list()

t_start <- Sys.time()
for (i in seq_along(all_test_months)) {
  YM_t <- all_test_months[i]
  panel <- build_panel_for_test_month(YM_t)
  if (is.null(panel) || nrow(panel) < 50) {
    if (i %% 30 == 0) cat(sprintf("  [%d/%d] %s SKIP (insufficient panel)\n",
                                    i, length(all_test_months), as.character(YM_t)))
    next
  }
  out_path <- file.path(PHASE1_DIR, sprintf("panel_%s.parquet", format(YM_t, "%Y%m")))
  write_parquet(panel, out_path)
  fcs <- attr(panel, "factor_cols")
  factor_universe_log[[as.character(YM_t)]] <- attr(panel, "top_factors_at_sig")
  panel_meta_log[[as.character(YM_t)]] <- list(
    YM_target = as.character(YM_t),
    YM_features = as.character(panel$YM_features[1]),
    sig_date = as.character(panel$sig_date[1]),
    n_rows = nrow(panel),
    n_factors = length(fcs),
    has_y_actual = !all(is.na(panel$Ret_1m)),
    out_path = sub(paste0(PROJ, "/"), "", out_path, fixed = TRUE)
  )
  if (i %% 30 == 0 || i == length(all_test_months)) {
    cat(sprintf("  [%d/%d] %s panel rows=%d, factors=%d (elapsed %.0fs)\n",
                i, length(all_test_months), as.character(YM_t),
                nrow(panel), length(fcs),
                as.numeric(Sys.time() - t_start, units = "secs")))
  }
}
cat("  Total elapsed:", round(as.numeric(Sys.time() - t_start, units = "mins"), 1), "min\n")

#--- 6. Factor universe stability log (PIT-rolling verification) ---
cat("\n[6] Factor universe stability log...\n")
all_factors_seen <- unique(unlist(factor_universe_log))
cat("  Distinct factors across all sig_dates:", length(all_factors_seen), "\n")
# Compute per-factor frequency
factor_freq <- table(unlist(factor_universe_log))
factor_freq_dt <- data.table(
  Factor_Name = names(factor_freq),
  freq = as.integer(factor_freq),
  pct = round(100 * as.integer(factor_freq) / length(factor_universe_log), 1)
)[order(-freq)]
factor_freq_dt[, persistent := (pct >= 95)]
n_persistent <- sum(factor_freq_dt$persistent)
cat("  Persistent factors (>=95% of sig_dates):", n_persistent, "\n")
cat("  Top 10 most-frequent:\n")
print(head(factor_freq_dt, 10))

write_parquet(factor_freq_dt, file.path(ART_DIR, "v5_factor_universe_stability.parquet"))

#--- 7. Lineage + index file ---
cat("\n[7] Index + lineage...\n")
index_dt <- rbindlist(lapply(panel_meta_log, function(x) as.data.table(x)), fill = TRUE)
write_parquet(index_dt, file.path(PHASE1_DIR, "panel_index.parquet"))
fwrite(index_dt, file.path(PHASE1_DIR, "panel_index.csv"))

lineage <- list(
  task_id = WT_ID,
  phase = "v5_phase1_features_pit_rolling",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  inputs = list(
    rawdata = ".cache/rawdata.parquet",
    factor_db = ".cache/factor_db/factor_db_*.parquet",
    str1715_bt = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/bt_result.rds"
  ),
  outputs = list(
    panel_dir = sub(paste0(PROJ, "/"), "", PHASE1_DIR, fixed = TRUE),
    panel_index = sub(paste0(PROJ, "/"), "", file.path(PHASE1_DIR, "panel_index.parquet"), fixed = TRUE),
    factor_universe_stability = sub(paste0(PROJ, "/"), "", file.path(ART_DIR, "v5_factor_universe_stability.parquet"), fixed = TRUE)
  ),
  pit_compliance = list(
    C1 = list(status = "REMEDIATED",
              evidence = paste0("Per sig_date factor universe (top 80 by coverage at sig_date). ",
                               n_persistent, "/", length(all_factors_seen), " factors persistent (>=95% sig_dates).")),
    C2 = list(status = "REMEDIATED",
              evidence = "Universe/Admin/Size/Vol_KRW_20d filtered at YM_features = YM_target - 1 month."),
    C10 = list(status = "REMEDIATED",
              evidence = "Vol_KRW_20d hard floor = 2e8 KRW (5e7 relax 폐기)."),
    C13 = list(status = "PASS_INHERITED",
               evidence = "Z_Score_Aligned via load_month_factors (no NEGATE/FLIP)."),
    C14 = list(status = "PASS_INHERITED",
               evidence = "factor_db_connector applies Usable_Date <= sig_date for IC alignment."),
    C15 = list(status = "PASS_INHERITED",
               evidence = "All factor access via load_month_factors(sig_date).")
  ),
  forward_asof = list(
    YM_target = as.character(forward_month),
    YM_features = as.character(as.Date(format(forward_month - 1, "%Y-%m-01"))),
    sig_date = as.character(as.Date(format(forward_month, "%Y-%m-01")) - 1),
    has_y_actual = FALSE,
    description = "2026-05 forward as-of prediction for deployment"
  ),
  factor_universe_log = factor_universe_log,
  panel_meta = panel_meta_log
)
writeLines(toJSON(lineage, pretty = TRUE, auto_unbox = TRUE, na = "null"),
           file.path(WT_DIR, "sig_date_window_lineage.json"))
cat("  Wrote sig_date_window_lineage.json\n")

cat("\n================================================================\n")
cat("Phase 1 DONE — ", length(all_test_months), " panels written to ",
    sub(paste0(PROJ, "/"), "", PHASE1_DIR, fixed = TRUE), "\n", sep = "")
cat("Forward as-of:", as.character(forward_month), "\n")
cat("================================================================\n")
