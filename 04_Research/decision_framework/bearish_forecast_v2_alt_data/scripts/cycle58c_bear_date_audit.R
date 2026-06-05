#!/usr/bin/env Rscript
# cycle58c_bear_date_audit.R — Cycle 58C pre-cycle bear_date_audit
#
# Verifies 4 anchor bear dates have valid forward labels in targets_long_horizon_observable
# + y_tail_q15 is not all-NaN
# + cross-market panel + v5g panel + v5f_FIXED2 panel exist
# + v5g BBVA columns identical to v5f_FIXED2 (FIXED2 inheritance audit)
#
# Output: outputs/04_evaluation/cycle58c_bear_date_audit.json

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(jsonlite); library(lubridate)
})

WS <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
setwd(WS)

cat("=", strrep("=", 70), "\n", sep="")
cat("[Cycle 58C] PRE-CYCLE bear_date_audit\n")
cat(strrep("=", 70), "\n", sep="")

# 4 anchor bear dates (Cycle 54B inherit)
BEAR_ANCHORS <- list(
  Lehman_GFC     = as.Date("2008-09-12"),
  Euro_Crisis    = as.Date("2011-08-08"),
  COVID          = as.Date("2020-02-19"),
  Stagflation_22 = as.Date("2022-06-15")
)

# ===== 1. Panel existence =====
panel_paths <- list(
  v5f_FIXED2 = "outputs/01_data/feature_panel_v5f_FIXED2.parquet",
  v5g_cross_market = "outputs/01_data/feature_panel_v5g_cross_market.parquet",
  cross_market_daily = "outputs/01_data/cross_market_daily.parquet",
  targets_observable = "outputs/02_targets/targets_long_horizon_observable.parquet"
)
panel_exists <- sapply(panel_paths, file.exists)
cat("\n[Step 1] Panel existence:\n")
for (n in names(panel_exists)) {
  cat(sprintf("  %-22s %s  %s\n", n, ifelse(panel_exists[n], "OK", "MISSING"), panel_paths[[n]]))
}
stopifnot(all(panel_exists))

# ===== 2. Target file: y_tail_q15 sanity =====
cat("\n[Step 2] Target y_tail_q15 sanity:\n")
tgt <- read_parquet(panel_paths$targets_observable)
tgt$Date <- as.Date(tgt$Date)
n_total <- nrow(tgt)
n_q15_notna <- sum(!is.na(tgt$y_tail_q15))
n_ret_q15_notna <- sum(!is.na(tgt$ret_q15))
n_phantom <- sum(is.na(tgt$ret_q15) & !is.na(tgt$y_tail_q15))
cat(sprintf("  total rows: %d\n", n_total))
cat(sprintf("  y_tail_q15 not-NA: %d (%.2f%%)\n", n_q15_notna, n_q15_notna/n_total*100))
cat(sprintf("  ret_q15 not-NA: %d (%.2f%%)\n", n_ret_q15_notna, n_ret_q15_notna/n_total*100))
cat(sprintf("  phantom rows (y not-NA, ret NA): %d (M6 guard: must be 0)\n", n_phantom))
stopifnot(n_phantom == 0)

# ===== 3. Bear anchor dates =====
cat("\n[Step 3] 4 bear anchor dates check:\n")
anchor_results <- list()
H <- 21L  # forward horizon (days)
for (name in names(BEAR_ANCHORS)) {
  d <- BEAR_ANCHORS[[name]]
  # +21 trading-day window
  window_end <- d + 31L  # ~21 trading days = ~31 calendar days max
  m <- tgt[tgt$Date >= d & tgt$Date <= window_end, c("Date", "y_tail_q15", "ret_q15")]
  if (nrow(m) == 0) {
    anchor_results[[name]] <- list(date = as.character(d), n_window = 0L,
                                   max_y = NA, max_ret = NA, status = "NO_WINDOW")
    cat(sprintf("  %-15s %s  NO_WINDOW (date out of panel range)\n", name, d))
    next
  }
  max_y <- if (all(is.na(m$y_tail_q15))) NA else max(m$y_tail_q15, na.rm = TRUE)
  max_ret <- if (all(is.na(m$ret_q15))) NA else max(abs(m$ret_q15), na.rm = TRUE)
  status <- if (is.na(max_y)) "ALL_NA" else if (max_y == 1) "BEAR_LABELED" else "NO_BEAR_IN_WINDOW"
  anchor_results[[name]] <- list(
    date = as.character(d), n_window = nrow(m),
    max_y_tail_q15 = max_y, max_abs_ret_q15 = round(max_ret, 4),
    status = status
  )
  cat(sprintf("  %-15s %s  n_window=%d  max_y=%s  max_|ret|=%.4f  %s\n",
              name, d, nrow(m), ifelse(is.na(max_y), "NA", as.character(max_y)),
              ifelse(is.na(max_ret), -1, max_ret), status))
}

# ===== 4. v5g BBVA inheritance from v5f_FIXED2 =====
cat("\n[Step 4] v5g BBVA-FIXED2 inheritance audit:\n")
v5f <- read_parquet(panel_paths$v5f_FIXED2)
v5g <- read_parquet(panel_paths$v5g_cross_market)
v5f$Date <- as.Date(v5f$Date)
v5g$Date <- as.Date(v5g$Date)
bbva_cols <- c("bbva_market_z", "bbva_sovereign_z", "bbva_transmission_z", "bbva_macro_composite",
               "bbva_market_z_lag1", "bbva_sovereign_z_lag1", "bbva_transmission_z_lag1", "bbva_macro_composite_lag1")
bbva_audit <- list()
for (c in bbva_cols) {
  if (!(c %in% names(v5f)) || !(c %in% names(v5g))) {
    bbva_audit[[c]] <- list(in_v5f = c %in% names(v5f), in_v5g = c %in% names(v5g))
    next
  }
  d <- merge(v5f[, c("Date", c)], v5g[, c("Date", c)], by = "Date", suffixes = c("_v5f","_v5g"))
  d <- d[!is.na(d[[paste0(c, "_v5f")]]) & !is.na(d[[paste0(c, "_v5g")]]), ]
  diff <- abs(d[[paste0(c, "_v5f")]] - d[[paste0(c, "_v5g")]])
  bbva_audit[[c]] <- list(
    n_common = nrow(d),
    max_abs_diff = round(max(diff, na.rm = TRUE), 6),
    n_diff_gt_1e6 = sum(diff > 1e-6, na.rm = TRUE)
  )
  cat(sprintf("  %-32s n_common=%d  max_diff=%.6f  n_diff>1e-6=%d\n",
              c, nrow(d), max(diff, na.rm = TRUE), sum(diff > 1e-6, na.rm = TRUE)))
}
bbva_clean <- all(sapply(bbva_audit, function(x) {
  isTRUE(x$max_abs_diff == 0) || isTRUE(x$n_diff_gt_1e6 == 0)
}))
cat(sprintf("\n  BBVA-FIXED2 inheritance: %s\n",
            ifelse(bbva_clean, "PASS (v5g BBVA cols identical to v5f_FIXED2)", "FAIL")))

# ===== 5. Cross-market columns sanity =====
cat("\n[Step 5] Cross-market columns sanity:\n")
cm <- read_parquet(panel_paths$cross_market_daily)
cm_cols <- setdiff(names(cm), "Date")
cm_audit <- list()
for (c in cm_cols) {
  n_notna <- sum(!is.na(cm[[c]]))
  cm_audit[[c]] <- list(n_notna = n_notna, n_total = nrow(cm),
                         pct_notna = round(n_notna/nrow(cm)*100, 1))
  cat(sprintf("  %-32s n_notna=%d (%.1f%%)\n", c, n_notna, n_notna/nrow(cm)*100))
}

# All cross-market features must end with _lag1 (PIT-safe)
all_lag1 <- all(grepl("_lag1$", cm_cols))
cat(sprintf("\n  All cross-market cols end with _lag1 (PIT-safe): %s\n",
            ifelse(all_lag1, "PASS", "FAIL")))
stopifnot(all_lag1)

# ===== Final verdict =====
n_bear_ok <- sum(sapply(anchor_results, function(x) x$status == "BEAR_LABELED"))
status_pass <- (n_bear_ok >= 2) && bbva_clean && all_lag1 && (n_phantom == 0)

audit <- list(
  cycle = "58C",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  panel_existence = as.list(panel_exists),
  target_sanity = list(
    n_total = n_total,
    n_y_tail_q15_notna = n_q15_notna,
    n_ret_q15_notna = n_ret_q15_notna,
    n_phantom_rows = n_phantom,
    M6_guard = ifelse(n_phantom == 0, "PASS", "FAIL")
  ),
  bear_anchors = anchor_results,
  bbva_FIXED2_inheritance = list(
    columns_audited = length(bbva_audit),
    audit_per_col = bbva_audit,
    overall = ifelse(bbva_clean, "PASS_IDENTICAL", "FAIL")
  ),
  cross_market_audit = list(
    columns = length(cm_cols),
    all_PIT_safe_lag1 = all_lag1,
    per_col = cm_audit
  ),
  pre_cycle_verdict = list(
    n_bear_labeled = n_bear_ok,
    n_bear_total = length(BEAR_ANCHORS),
    overall = ifelse(status_pass, "PASS", "FAIL"),
    rationale = sprintf(
      "%d/%d bear anchors labeled (need >=2 since Lehman/Euro pre-panel); BBVA inheritance %s; M6 guard %s; PIT-safe %s",
      n_bear_ok, length(BEAR_ANCHORS),
      ifelse(bbva_clean, "PASS", "FAIL"),
      ifelse(n_phantom == 0, "PASS", "FAIL"),
      ifelse(all_lag1, "PASS", "FAIL")
    )
  )
)

out_path <- "outputs/04_evaluation/cycle58c_bear_date_audit.json"
writeLines(jsonlite::toJSON(audit, pretty = TRUE, auto_unbox = TRUE), out_path)
cat(sprintf("\n[audit] Saved: %s\n", out_path))

cat("\n", strrep("=", 70), "\n", sep="")
cat(sprintf("[VERDICT] %s — %s\n", audit$pre_cycle_verdict$overall, audit$pre_cycle_verdict$rationale))
cat(strrep("=", 70), "\n", sep="")

if (!status_pass) {
  stop("PRE-CYCLE bear_date_audit FAIL — abort Cycle 58C")
}
