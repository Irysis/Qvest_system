## STR_1722 Phase 1 — Factor DB Untapped Audit
##
## Source: .cache/factor_db/factor_ic_monthly.parquet (269 factors, 62885 monthly IC, 2005-01 ~ 2026-02)
##
## Logic:
##   1. Walk-forward expanding ICIR per factor (rolling 60m minimum window)
##   2. Full-period ICIR + last 5y ICIR + last 3y ICIR (multi-window stability)
##   3. Subperiod split (2005-2014 / 2015-2019 / 2020-2026) stability
##   4. Top 30 untapped factor ranking (RF-A2 회피 - single factor 검증)
##
## Output:
##   - outputs/factor_db_untapped_icir_ranking.parquet
##   - outputs/factor_db_untapped_icir_ranking.meta.json

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

BASE <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT_DIR <- file.path(BASE, "04_Research/decision_framework/factor_untapped/outputs")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("[1] Load factor_ic_monthly.parquet\n")
ic <- as.data.table(read_parquet(file.path(BASE, ".cache/factor_db/factor_ic_monthly.parquet")))
ic[, Date := as.Date(Date)]
ic[, Usable_Date := as.Date(Usable_Date)]
setorder(ic, Factor_Name, Date)
cat(sprintf("  rows: %d | factors: %d | range: %s ~ %s\n",
            nrow(ic), uniqueN(ic$Factor_Name),
            as.character(min(ic$Date)), as.character(max(ic$Date))))

cat("[2] Compute full-period / last 5y / last 3y / subperiod ICIR per factor\n")

last_5y_cutoff <- as.Date("2021-02-28")
last_3y_cutoff <- as.Date("2023-02-28")
sp_split_1 <- as.Date("2014-12-31")
sp_split_2 <- as.Date("2019-12-31")

compute_icir <- function(ic_vec) {
  v <- ic_vec[!is.na(ic_vec)]
  if (length(v) < 12) return(NA_real_)
  m <- mean(v)
  s <- sd(v)
  if (is.na(s) || s == 0) return(NA_real_)
  m / s
}

stats <- ic[, .(
  n_months = .N,
  ic_mean_full = mean(IC, na.rm = TRUE),
  icir_full = compute_icir(IC),
  ic_mean_5y = mean(IC[Date >= last_5y_cutoff], na.rm = TRUE),
  icir_5y = compute_icir(IC[Date >= last_5y_cutoff]),
  ic_mean_3y = mean(IC[Date >= last_3y_cutoff], na.rm = TRUE),
  icir_3y = compute_icir(IC[Date >= last_3y_cutoff]),
  icir_sp1 = compute_icir(IC[Date <= sp_split_1]),
  icir_sp2 = compute_icir(IC[Date > sp_split_1 & Date <= sp_split_2]),
  icir_sp3 = compute_icir(IC[Date > sp_split_2]),
  ic_mean_n_stocks = mean(N_Stocks, na.rm = TRUE)
), by = Factor_Name]

stats[, abs_icir_full := abs(icir_full)]
stats[, abs_icir_5y := abs(icir_5y)]
stats[, sp_consistency_ratio := pmin(sign(icir_sp1) * sign(icir_sp2),
                                       sign(icir_sp2) * sign(icir_sp3),
                                       sign(icir_sp1) * sign(icir_sp3), na.rm = TRUE)]
stats[, sp_stable := sign(icir_sp1) == sign(icir_sp2) & sign(icir_sp2) == sign(icir_sp3)]

cat("[3] Top 30 ranking by |icir_full| (full-period) and |icir_5y| (recent 5y)\n")

setorder(stats, -abs_icir_full)
top30_full <- head(stats, 30)
cat("  TOP 30 |icir_full|:\n")
print(top30_full[, .(Factor_Name, n_months, ic_mean_full, icir_full, icir_5y, icir_3y, sp_stable)])

setorder(stats, -abs_icir_5y)
top30_5y <- head(stats[!is.na(icir_5y)], 30)
cat("\n  TOP 30 |icir_5y| (recent 5y, alpha decay 검증):\n")
print(top30_5y[, .(Factor_Name, n_months, icir_full, icir_5y, icir_3y, sp_stable)])

cat("\n[4] Save outputs\n")
out_path <- file.path(OUT_DIR, "factor_db_untapped_icir_ranking.parquet")
write_parquet(stats, out_path)
cat(sprintf("  saved: %s\n", out_path))

summary <- list(
  strategy_id = "STR_1722_Factor_Untapped_Statistical_Breakout",
  phase = "Phase 1 Factor DB Untapped Audit",
  source = ".cache/factor_db/factor_ic_monthly.parquet",
  n_factors_total = uniqueN(ic$Factor_Name),
  n_months_total = nrow(ic),
  date_start = as.character(min(ic$Date)),
  date_end = as.character(max(ic$Date)),
  n_factors_top30_full = nrow(top30_full),
  n_factors_top30_5y = nrow(top30_5y),
  top10_full_period = top30_full[1:10, .(Factor_Name, icir_full = round(icir_full, 4),
                                          icir_5y = round(icir_5y, 4),
                                          sp_stable)],
  top10_5y_recent = top30_5y[1:10, .(Factor_Name, icir_full = round(icir_full, 4),
                                      icir_5y = round(icir_5y, 4),
                                      sp_stable)],
  built_at = as.character(Sys.time())
)
writeLines(toJSON(summary, pretty = TRUE, auto_unbox = TRUE, na = "null"),
           file.path(OUT_DIR, "factor_db_untapped_icir_ranking.meta.json"))
cat("[5] Done\n")
