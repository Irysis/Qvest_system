## STR_1722 Phase 3 — Combined Orthogonality + Top-K Selection
##
## Inputs:
##   - Phase 1: factor_db_untapped_icir_ranking.parquet (269 factor ICIR ranking)
##   - Phase 2: statistical_breakout_factor_panel.parquet (8 new factor, 107k rows)
##   - per_stock_features.parquet (forward 21d return label)
##
## Logic:
##   1. Phase 2 신규 8 factor에 대해 cross-section IC + ICIR 산출 (PIT forward 21d)
##   2. Phase 1 Top 30 (recent 5y) + Phase 2 8 factor = 38 candidate factor
##   3. Pairwise Z-score correlation matrix (per-Date z + average across sig_dates)
##   4. Greedy orthogonal selection: |cor|<0.5 filter, iterative top-ICIR selection
##
## Output:
##   - outputs/phase3_combined_icir.parquet
##   - outputs/phase3_correlation_matrix.parquet
##   - outputs/phase3_orthogonal_top_k.parquet
##   - outputs/phase3_summary.meta.json

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

BASE <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT_DIR <- file.path(BASE, "04_Research/decision_framework/factor_untapped/outputs")
FEAT_PATH <- file.path(BASE, "04_Research/decision_framework/cross_section_distribution/outputs/per_stock_features.parquet")
P1_PATH <- file.path(OUT_DIR, "factor_db_untapped_icir_ranking.parquet")
P2_PATH <- file.path(OUT_DIR, "statistical_breakout_factor_panel.parquet")
FDB_DIR <- file.path(BASE, ".cache/factor_db")

cat("[1] Load Phase 1 ranking + Phase 2 panel\n")
p1 <- as.data.table(read_parquet(P1_PATH))
p2 <- as.data.table(read_parquet(P2_PATH))
p2[, Date := as.Date(Date)]
cat(sprintf("  Phase 1: %d factors | Phase 2: %d rows x %d new factors\n",
            nrow(p1), nrow(p2), 8))

cat("[2] Load features panel (forward 21d return label)\n")
feat <- as.data.table(read_parquet(FEAT_PATH,
                                    col_select = c("Date", "Ticker", "K200", "KQ150",
                                                    "ret_h_21d_forward")))
feat[, Date := as.Date(Date)]
feat[, in_universe := (K200 == 1.0 | KQ150 == 1.0)]
feat <- feat[in_universe == TRUE & !is.na(ret_h_21d_forward)]
feat[, fwd_ret := ret_h_21d_forward / 100.0]
# Winsorize 99.5% (학술 정합)
q_lo <- quantile(feat$fwd_ret, 0.0025, na.rm = TRUE)
q_hi <- quantile(feat$fwd_ret, 0.9975, na.rm = TRUE)
feat[fwd_ret < q_lo, fwd_ret := q_lo]
feat[fwd_ret > q_hi, fwd_ret := q_hi]
feat <- feat[, .(Date, Ticker, fwd_ret)]
cat(sprintf("  features: %d rows after universe + winsorize\n", nrow(feat)))

cat("[3] Phase 2 8-factor cross-section IC + ICIR (PIT forward 21d)\n")

# Snap Phase 2 daily to monthly sig_date by month-end matching
sig_dates <- sort(unique(p2$Date))
# Merge Phase 2 with features by (Date, Ticker)
# Phase 2 Date is monthly; feat Date is daily — need monthly snapshot of feat
feat[, ym := format(Date, "%Y-%m")]
feat_monthly <- feat[, .SD[which.max(Date)], by = .(ym, Ticker)]

# For phase 2 alignment, match by ym (year-month) of Date
p2[, ym := format(Date, "%Y-%m")]

# Merge by (ym, Ticker)
merged <- merge(p2, feat_monthly[, .(ym, Ticker, fwd_ret)],
                by = c("ym", "Ticker"), all.x = TRUE)
merged <- merged[!is.na(fwd_ret)]
cat(sprintf("  merged Phase 2 + forward return: %d rows\n", nrow(merged)))

# Per-Date Spearman IC for each Phase 2 factor
new_factors <- c("p_breakout_up", "p_breakout_down", "e_fpt", "hurst",
                  "perm_entropy", "recurrence_interval", "dd_recovery", "ou_half_life")

ic_by_date <- list()
for (f in new_factors) {
  ic_list <- merged[!is.na(get(f)) & !is.na(fwd_ret),
                     .(IC = if (.N >= 20) suppressWarnings(cor(get(f), fwd_ret, method = "spearman")) else NA_real_,
                       N = .N),
                     by = Date]
  ic_list[, Factor_Name := f]
  ic_by_date[[f]] <- ic_list
}
ic_df <- rbindlist(ic_by_date)
cat(sprintf("  IC computed: %d (factor, date) pairs\n", nrow(ic_df)))

# ICIR per factor (full / last 5y / last 3y / subperiod stable)
last_5y_cutoff <- as.Date("2021-02-28")
last_3y_cutoff <- as.Date("2023-02-28")
sp1 <- as.Date("2014-12-31")
sp2 <- as.Date("2019-12-31")

compute_icir <- function(v) {
  v2 <- v[!is.na(v)]
  if (length(v2) < 12) return(NA_real_)
  m <- mean(v2); s <- sd(v2)
  if (is.na(s) || s == 0) return(NA_real_)
  m / s
}

p2_stats <- ic_df[, .(
  n_months = sum(!is.na(IC)),
  ic_mean_full = mean(IC, na.rm = TRUE),
  icir_full = compute_icir(IC),
  icir_5y = compute_icir(IC[Date >= last_5y_cutoff]),
  icir_3y = compute_icir(IC[Date >= last_3y_cutoff]),
  sp_stable = sign(compute_icir(IC[Date <= sp1])) ==
              sign(compute_icir(IC[Date > sp1 & Date <= sp2])) &
              sign(compute_icir(IC[Date > sp1 & Date <= sp2])) ==
              sign(compute_icir(IC[Date > sp2]))
), by = Factor_Name]

cat("[4] Phase 2 8 factor ICIR ranking:\n")
p2_stats <- p2_stats[order(-abs(icir_5y))]
print(p2_stats)

cat("[5] Combined 38 candidate (Phase 1 Top 30 + Phase 2 8)\n")
# Phase 1 top 30 by |icir_5y|
p1 <- p1[order(-abs(icir_5y))]
p1_top30 <- head(p1[!is.na(icir_5y)], 30)
p1_top30[, source := "factor_db"]
p2_stats[, source := "statistical_breakout"]
p2_stats[, n_months := as.numeric(n_months)]

# Harmonize columns
common_cols <- c("Factor_Name", "n_months", "ic_mean_full", "icir_full", "icir_5y",
                  "icir_3y", "sp_stable", "source")
p1_top30_sel <- p1_top30[, ..common_cols]
p2_stats_sel <- p2_stats[, ..common_cols]
combined <- rbind(p1_top30_sel, p2_stats_sel)
combined <- combined[order(-abs(icir_5y))]
cat(sprintf("  Combined: %d factors\n", nrow(combined)))
print(head(combined, 40))

write_parquet(combined, file.path(OUT_DIR, "phase3_combined_icir.parquet"))

cat("[6] Pairwise correlation matrix (sig_date avg cross-section Z correlation)\n")
# For each pair of factors, compute Spearman correlation across stocks per sig_date, then avg
# Load Phase 1 factor Z from factor_db (for top 30 factor list)
# Phase 2 already has factor values in p2 panel

# Phase 1: load factor_db Z for top 30 (use load_month_factors)
# This is expensive. Approximation: use Phase 1 IC time series correlation as proxy.
# Better: use actual cross-section Z. Load factor_db parquet for Phase 1 factors at common sig_dates.

cat("  Loading Phase 1 top 30 factor Z from factor_db (monthly parquet)\n")
p1_factor_names <- p1_top30$Factor_Name
fdb_files <- list.files(FDB_DIR, pattern = "^factor_db_[0-9]{6}\\.parquet$", full.names = TRUE)
fdb_list <- list()
for (f in fdb_files) {
  ym <- substr(basename(f), 11, 16)
  if (as.integer(ym) < 200601) next  # match Phase 2 range
  df <- as.data.table(read_parquet(f, col_select = c("Date", "Ticker", "Factor_Name", "Z_Score")))
  df <- df[Factor_Name %in% p1_factor_names]
  if (nrow(df) > 0) fdb_list[[length(fdb_list) + 1]] <- df
}
fdb_long <- rbindlist(fdb_list)
fdb_long[, Date := as.Date(Date)]
cat(sprintf("  Phase 1 factor_db Z: %d rows\n", nrow(fdb_long)))

# Wide format Phase 1: Date × Ticker × Factor
fdb_wide <- dcast(fdb_long, Date + Ticker ~ Factor_Name, value.var = "Z_Score")

# Wide format Phase 2: already wide (Date Ticker + 8 columns)
p2_wide <- p2[, c("Date", "Ticker", ..new_factors)]

# Merge Phase 1 + Phase 2
combined_z <- merge(fdb_wide, p2_wide, by = c("Date", "Ticker"), all.x = FALSE, all.y = FALSE)
cat(sprintf("  combined Z panel: %d rows\n", nrow(combined_z)))

# Compute pairwise Spearman correlation across all sig_dates (pool all stock-date observations)
factor_cols <- setdiff(names(combined_z), c("Date", "Ticker"))
n_f <- length(factor_cols)
cor_mat <- matrix(NA_real_, nrow = n_f, ncol = n_f, dimnames = list(factor_cols, factor_cols))
for (i in seq_len(n_f)) {
  for (j in seq_len(n_f)) {
    if (i == j) { cor_mat[i, j] <- 1; next }
    v1 <- combined_z[[factor_cols[i]]]
    v2 <- combined_z[[factor_cols[j]]]
    valid <- !is.na(v1) & !is.na(v2)
    if (sum(valid) < 100) next
    cor_mat[i, j] <- suppressWarnings(cor(v1[valid], v2[valid], method = "spearman"))
  }
}
cor_dt <- as.data.table(cor_mat, keep.rownames = "Factor_Name")
write_parquet(cor_dt, file.path(OUT_DIR, "phase3_correlation_matrix.parquet"))

cat("[7] Greedy orthogonal selection (|cor|<0.5, iterative top-ICIR)\n")
# Combined ICIR for ordering
icir_lookup <- setNames(combined$icir_5y, combined$Factor_Name)
factor_order <- names(sort(abs(icir_lookup), decreasing = TRUE, na.last = TRUE))

selected <- character()
for (f in factor_order) {
  if (!(f %in% factor_cols)) next  # not in cor_mat (no observation overlap)
  if (length(selected) == 0) {
    selected <- f
    next
  }
  max_cor <- max(abs(cor_mat[f, selected]), na.rm = TRUE)
  if (!is.finite(max_cor) || max_cor < 0.5) {
    selected <- c(selected, f)
  }
  if (length(selected) >= 15) break
}

cat(sprintf("  Selected orthogonal factors (|cor|<0.5): %d\n", length(selected)))
orth_dt <- data.table(
  rank = seq_along(selected),
  Factor_Name = selected,
  icir_5y = icir_lookup[selected],
  source = combined[match(selected, combined$Factor_Name)]$source
)
print(orth_dt)
write_parquet(orth_dt, file.path(OUT_DIR, "phase3_orthogonal_top_k.parquet"))

cat("[8] Save summary\n")
summary_list <- list(
  strategy_id = "STR_1722_Factor_Untapped_Statistical_Breakout",
  phase = "Phase 3 Combined Orthogonality",
  n_phase1_top30 = nrow(p1_top30),
  n_phase2_new = length(new_factors),
  n_combined_candidates = nrow(combined),
  n_orthogonal_selected = length(selected),
  orthogonal_top_k = orth_dt,
  phase2_factor_icir = p2_stats[, .(Factor_Name, n_months, ic_mean_full = round(ic_mean_full, 5),
                                     icir_full = round(icir_full, 4),
                                     icir_5y = round(icir_5y, 4),
                                     sp_stable)],
  built_at = as.character(Sys.time())
)
writeLines(toJSON(summary_list, pretty = TRUE, auto_unbox = TRUE, na = "null"),
           file.path(OUT_DIR, "phase3_summary.meta.json"))
cat("[9] Done\n")
