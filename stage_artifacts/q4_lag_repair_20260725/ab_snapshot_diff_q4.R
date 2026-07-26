# ab_snapshot_diff_q4.R — Q4 lag repair A/B: 팩터 레벨 스냅샷 diff (plan §3.3-3 팩터 레벨)
#   old = .cache/pins/q4_pre_20260725/factor_db_YYYYMM.parquet (Feb+Mar 2001..2026, 52개)
#   new = .cache/factor_db/factor_db_YYYYMM.parquet (재빌드 후)
#   + factor_ic_monthly old-vs-new (전월 간접 검출 — Feb 외 월 변화 유무)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(QM)
PIN <- file.path(QM, ".cache/pins/q4_pre_20260725")
NEW <- file.path(QM, ".cache/factor_db")
OUT <- file.path(QM, "stage_artifacts/q4_lag_repair_20260725")
REP5 <- c("V01_BM", "V02_EP", "Q01_GPA", "V11_Shareholder_Yield", "XF_Q06_Op_Margin")
SBBF <- c("Q20_Net_Buyback", "IN04_Net_Equity_Issuance", "V11_Shareholder_Yield")  # SBB/ISSD 파생 별도 관찰

yrs <- 2001:2026
tags <- c(sprintf("%d02", yrs), sprintf("%d03", yrs))
tags <- sort(tags)

diff_rows <- list()
detail_rows <- list()
for (tg in tags) {
  fo <- file.path(PIN, sprintf("factor_db_%s.parquet", tg))
  fn <- file.path(NEW, sprintf("factor_db_%s.parquet", tg))
  if (!file.exists(fo) || !file.exists(fn)) { cat("[skip]", tg, "\n"); next }
  o <- as.data.table(read_parquet(fo, col_select = c("Ticker", "Factor_Name", "Z_Score")))
  n <- as.data.table(read_parquet(fn, col_select = c("Ticker", "Factor_Name", "Z_Score")))
  m <- merge(o, n, by = c("Ticker", "Factor_Name"), all = TRUE, suffixes = c("_old", "_new"))
  m[, changed := (is.na(Z_Score_old) != is.na(Z_Score_new)) |
                 (!is.na(Z_Score_old) & !is.na(Z_Score_new) & abs(Z_Score_old - Z_Score_new) > 1e-9)]
  per_f <- m[, .(n_rows = .N, n_changed = sum(changed)), by = Factor_Name]
  # rank corr for changed factors
  ch_f <- per_f[n_changed > 0, Factor_Name]
  rk <- m[Factor_Name %in% ch_f & !is.na(Z_Score_old) & !is.na(Z_Score_new),
          .(rank_corr = if (.N >= 10) cor(frank(Z_Score_old), frank(Z_Score_new)) else NA_real_,
            mean_abs_drank = if (.N >= 10) mean(abs(frank(Z_Score_old) - frank(Z_Score_new))) else NA_real_),
          by = Factor_Name]
  per_f <- merge(per_f, rk, by = "Factor_Name", all.x = TRUE)
  per_f[, ym := tg]
  diff_rows[[tg]] <- data.table(
    ym = tg, month_type = ifelse(substr(tg, 5, 6) == "02", "FEB", "MAR"),
    n_factors = nrow(per_f), n_factors_changed = sum(per_f$n_changed > 0),
    n_rows_changed = sum(per_f$n_changed),
    min_rank_corr_changed = if (length(ch_f)) suppressWarnings(min(rk$rank_corr, na.rm = TRUE)) else NA_real_
  )
  detail_rows[[tg]] <- per_f[n_changed > 0 | Factor_Name %in% c(REP5, SBBF)]
  cat(sprintf("[%s] factors_changed=%d rows_changed=%d\n", tg,
              sum(per_f$n_changed > 0), sum(per_f$n_changed)))
}
summary_dt <- rbindlist(diff_rows)
detail_dt  <- rbindlist(detail_rows)
fwrite(summary_dt, file.path(OUT, "snapshot_diff_summary.csv"))
fwrite(detail_dt, file.path(OUT, "snapshot_diff_factor_detail.csv"))

cat("\n=== summary by month_type ===\n")
print(summary_dt[, .(n_months = .N, mean_factors_changed = mean(n_factors_changed),
                     max_factors_changed = max(n_factors_changed),
                     total_rows_changed = sum(n_rows_changed)), by = month_type])

cat("\n=== representative 5 detail (FEB months, changed only) ===\n")
print(detail_dt[Factor_Name %in% REP5 & substr(ym, 5, 6) == "02" & n_changed > 0][
  order(Factor_Name, ym)][, .(ym, Factor_Name, n_rows, n_changed, rank_corr, mean_abs_drank)],
  nrows = 200)

cat("\n=== factors changed anywhere (union) ===\n")
ch_union <- detail_dt[n_changed > 0, .(n_months_changed = .N, total_changed = sum(n_changed),
                                       min_rank_corr = suppressWarnings(min(rank_corr, na.rm = TRUE))),
                      by = Factor_Name][order(-total_changed)]
print(ch_union, nrows = 400)
fwrite(ch_union, file.path(OUT, "snapshot_diff_changed_factors_union.csv"))

# ── factor_ic_monthly diff (전월 간접 검출) ──
cat("\n=== factor_ic_monthly old vs new ===\n")
ico <- as.data.table(read_parquet(file.path(PIN, "factor_ic_monthly.parquet")))
icn <- as.data.table(read_parquet(file.path(NEW, "factor_ic_monthly.parquet")))
icm <- merge(ico[, .(Date, Factor_Name, IC_old = IC)],
             icn[, .(Date, Factor_Name, IC_new = IC)],
             by = c("Date", "Factor_Name"), all = TRUE)
icm[, changed := (is.na(IC_old) != is.na(IC_new)) |
                 (!is.na(IC_old) & !is.na(IC_new) & abs(IC_old - IC_new) > 1e-9)]
icm[, mm := format(as.Date(Date), "%m")]
cat(sprintf("IC rows old=%s new=%s | changed=%s (%.2f%%)\n",
            format(nrow(ico), big.mark = ","), format(nrow(icn), big.mark = ","),
            format(sum(icm$changed), big.mark = ","), 100 * mean(icm$changed)))
by_mm <- icm[, .(n = .N, n_changed = sum(changed)), by = mm][order(mm)]
print(by_mm)
fwrite(by_mm, file.path(OUT, "ic_diff_by_calmonth.csv"))
ic_fac <- icm[changed == TRUE, .N, by = Factor_Name][order(-N)]
cat("factors with any IC change:", nrow(ic_fac), "\n")
print(head(ic_fac, 30))
fwrite(ic_fac, file.path(OUT, "ic_diff_by_factor.csv"))
cat("\n[snapshot diff] DONE\n")
