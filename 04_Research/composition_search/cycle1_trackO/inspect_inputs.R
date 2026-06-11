# ============================================================
# Track O prereg input inspection (NO candidate measurement)
# Verifies layer5 panel mechanics so the prereg recomposition
# formula is written correctly. ASCII output only.
# ============================================================
suppressPackageStartupMessages({ library(data.table) })

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
l5 <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)

cat(sprintf("[range] realized_ym: %s .. %s | n=%d\n",
            min(l5$realized_ym), max(l5$realized_ym), nrow(l5)))

# column ranges
for (cn in c("beta_threshold_lag", "m4_weight_lag", "beta_R05_V2")) {
  v <- l5[[cn]]
  cat(sprintf("[range] %s: min=%.4f max=%.4f | months<1 = %d | distinct vals = %d\n",
              cn, min(v), max(v), sum(v < 1 - 1e-12), uniqueN(round(v, 6))))
}

# distinct values of each beta path (small sets expected if thresholded)
cat("[vals] beta_threshold_lag distinct:", paste(sort(unique(round(l5$beta_threshold_lag, 4))), collapse=", "), "\n")
cat("[vals] m4_weight_lag distinct:", paste(sort(unique(round(l5$m4_weight_lag, 4))), collapse=", "), "\n")
cat("[vals] beta_R05_V2 distinct:", paste(sort(unique(round(l5$beta_R05_V2, 4))), collapse=", "), "\n")

# product paths
l5[, g_inc := beta_threshold_lag * m4_weight_lag]            # AR x M4 (non-R05 combine)
l5[, b_tot := g_inc * beta_R05_V2]                           # total incumbent exposure
cat(sprintf("[prod] g_inc(ARxM4): min=%.4f | months<1 = %d | months in [0.25,0.5) = %d | months<0.25 = %d\n",
            min(l5$g_inc), sum(l5$g_inc < 1 - 1e-12),
            sum(l5$g_inc >= 0.25 & l5$g_inc < 0.5), sum(l5$g_inc < 0.25)))
cat(sprintf("[prod] b_tot(incl R05): min=%.4f | months<0.5 = %d | months<0.25 = %d (B2: 45 / 6)\n",
            min(l5$b_tot), sum(l5$b_tot < 0.5), sum(l5$b_tot < 0.25)))

# db_thr identity check: is db_thr == |delta(g_inc)|?
dg <- c(0, abs(diff(l5$g_inc)))
cat(sprintf("[id1] db_thr vs |delta(ARxM4 product)| max|diff| = %.3e\n", max(abs(l5$db_thr - dg))))

# alt: db_thr == |delta(beta_threshold_lag)| only?
dthr <- c(0, abs(diff(l5$beta_threshold_lag)))
cat(sprintf("[id2] db_thr vs |delta(beta_threshold_lag)| max|diff| = %.3e\n", max(abs(l5$db_thr - dthr))))

# db_R05_V2 identity: |delta(beta_R05_V2)|?
dr05 <- c(0, abs(diff(l5$beta_R05_V2)))
cat(sprintf("[id3] db_R05_V2 vs |delta(beta_R05_V2)| max|diff| = %.3e\n", max(abs(l5$db_R05_V2 - dr05))))

# alt: db_R05_V2 == |delta(total b)| - check
dtot <- c(0, abs(diff(l5$b_tot)))
cat(sprintf("[id4] db_thr+db_R05_V2 vs |delta(b_tot)| max|diff| = %.3e\n",
            max(abs(l5$db_thr + l5$db_R05_V2 - dtot))))

# closure check (verified previously 7.6e-16, re-run here)
l5[, recomp := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
      db_thr * 0.0015 - db_R05_V2 * 0.0015]
cat(sprintf("[id5] ret_L5_V2 recomposition max|diff| = %.3e\n", max(abs(l5$recomp - l5$ret_L5_V2))))

# IS/OOS month counts for prereg
cat(sprintf("[split] IS 2005-01..2018-12 n=%d | OOS 2019-01..end n=%d | pre-2005 n=%d\n",
            l5[realized_ym >= "2005-01" & realized_ym <= "2018-12", .N],
            l5[realized_ym >= "2019-01", .N],
            l5[realized_ym < "2005-01", .N]))
cat(sprintf("[split] 2017+ subperiod n=%d\n", l5[realized_ym >= "2017-01", .N]))
