#==============================================================================
# WT-D20260428_003 Iter 10 B v2 — PIT-clean re-evaluation (Codex C2/C3 fix)
#
# CHANGES from v1:
#   - load_month_factors() used (Codex C3/C15 fix)
#   - Z_Score_Aligned only — no manual sign flips (Codex C2/C13 fix)
#   - Q15 + Q05 axes now use Z_Score_Aligned (which already flips IC-negative factors)
#   - Result: ALL 4 axes summed POSITIVELY in Aligned space (no -Z manipulation)
#
# Hypothesis unchanged: MAQGC = mean(A1, A2, A3, A4) ex-ante 4-axis composite
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260428_003")

source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

# Universe + return panel
RAWDATA <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))
setkey(RAWDATA, Date, Ticker)

# Build month-end panel
RAWDATA[, YearMonth := format(Date, "%Y-%m")]
month_end <- RAWDATA[, .(MEnd = max(Date)), by = YearMonth][, MEnd]
RAWDATA_eom <- RAWDATA[Date %in% month_end, .(Date, Ticker, Close, K200, KQ150, Vol)]
setkey(RAWDATA_eom, Ticker, Date)
RAWDATA_eom[, Ret_fwd1M := shift(Close, type = "lead") / Close - 1, by = Ticker]

# Universe: KOSPI200 ∪ KOSDAQ150 + LIQ
build_universe <- function(sig_d) {
  start_d <- sig_d - 30
  uni <- RAWDATA[Date >= start_d & Date <= sig_d,
                 .(AvgTrdVal = mean(Vol * Close, na.rm = TRUE),
                   In_K200 = any(K200 == TRUE, na.rm = TRUE),
                   In_KQ150 = any(KQ150 == TRUE, na.rm = TRUE)), by = Ticker]
  uni[!is.na(AvgTrdVal) & AvgTrdVal >= 5e7 & (In_K200 | In_KQ150), Ticker]
}

# 4 axes — Z_Score_Aligned (higher = better, no manual sign flip)
NEEDED_FACTORS <- c(
  "Q01_GPA", "Q17_ROIC", "Q11_Net_Margin",
  "Q21_Revenue_Growth", "Q22_Earnings_Growth", "Q23_Sustainable_Growth",
  "Q15_Debt_to_Equity", "Q07_Earnings_Stability",
  "Q09_CFOA", "Q05_Accrual"
)

xs_z <- function(x) {
  s <- sd(x, na.rm = TRUE); if (is.na(s) || s < 1e-9) return(rep(NA_real_, length(x)))
  pmin(pmax((x - mean(x, na.rm = TRUE)) / s, -3), 3)
}

build_alpha_pit <- function(sig_d) {
  uni <- build_universe(sig_d)
  if (length(uni) < 50) return(NULL)

  # PIT-safe load via load_month_factors
  fdb <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) == 0) return(NULL)

  # Filter to needed factors + universe
  fdb <- fdb[Ticker %in% uni & Factor_Name %in% NEEDED_FACTORS]
  if (uniqueN(fdb$Factor_Name) < 7) return(NULL)

  # Pivot wide using Z_Score_Aligned ONLY (no manual flip)
  fwide <- dcast(fdb, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                 fun.aggregate = function(x) mean(x, na.rm = TRUE))

  available <- intersect(NEEDED_FACTORS, names(fwide))

  # A1 Profitability: GPA + ROIC + NM (all Aligned, +sum)
  prof_cols <- intersect(c("Q01_GPA", "Q17_ROIC", "Q11_Net_Margin"), names(fwide))
  if (length(prof_cols) == 0) return(NULL)
  fwide[, Z_A1 := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = prof_cols]

  # A2 Growth: Revenue + Earnings + Sustainable G (all Aligned)
  grow_cols <- intersect(c("Q21_Revenue_Growth", "Q22_Earnings_Growth", "Q23_Sustainable_Growth"), names(fwide))
  if (length(grow_cols) == 0) return(NULL)
  fwide[, Z_A2 := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = grow_cols]

  # A3 Safety: Q15_DE Aligned + Q07_ES Aligned (Aligned에서 high=좋음, no manual flip)
  safe_cols <- intersect(c("Q15_Debt_to_Equity", "Q07_Earnings_Stability"), names(fwide))
  if (length(safe_cols) == 0) return(NULL)
  fwide[, Z_A3 := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = safe_cols]

  # A4 CashFlowQuality: Q09_CFOA + Q05_Accrual (둘 다 Aligned, NO manual -)
  cfq_cols <- intersect(c("Q09_CFOA", "Q05_Accrual"), names(fwide))
  if (length(cfq_cols) == 0) return(NULL)
  fwide[, Z_A4 := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = cfq_cols]

  # Composite
  axis_cols <- c("Z_A1", "Z_A2", "Z_A3", "Z_A4")
  fwide[, alpha_raw := rowMeans(.SD, na.rm = TRUE), .SDcols = axis_cols]
  fwide[, alpha := xs_z(alpha_raw)]
  fwide <- fwide[!is.na(alpha)]

  # Spec 2 + 3 alternates
  fwide[, alpha_S2_PS := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = c("Z_A1", "Z_A3")]
  fwide[, alpha_S3_PG := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = c("Z_A1", "Z_A2")]

  fwide[, sig_date := sig_d]
  return(unique(fwide[, .(sig_date, Ticker, Z_A1, Z_A2, Z_A3, Z_A4, alpha, alpha_S2_PS, alpha_S3_PG)],
                by = c("sig_date", "Ticker")))
}

# Iterate sig_dates
months_seq <- as.Date(c())
for (y in 2008:2023) {
  for (m in 1:12) {
    if (y == 2023 && m > 11) break
    eom_str <- format(seq(as.Date(sprintf("%d-%02d-01", y, m)), length.out = 2, by = "month")[2] - 1, "%Y-%m-%d")
    months_seq <- c(months_seq, as.Date(eom_str))
  }
}
months_seq <- unique(months_seq)
months_seq <- months_seq[months_seq >= as.Date("2008-01-01") & months_seq <= as.Date("2023-11-30")]

cat(sprintf("Built %d unique month_seq dates (2008-01 ~ 2023-11)\n", length(months_seq)))

panel_list <- list()
for (sig_d in months_seq) {
  res <- tryCatch(build_alpha_pit(as.Date(sig_d)), error = function(e) {
    cat(sprintf("Error at %s: %s\n", sig_d, conditionMessage(e)))
    NULL
  })
  if (!is.null(res)) panel_list[[length(panel_list) + 1]] <- res
}
panel <- rbindlist(panel_list)
cat(sprintf("Built panel: %d rows × %d sig_dates\n", nrow(panel), uniqueN(panel$sig_date)))

# Forward returns
panel <- merge(panel, RAWDATA_eom[, .(sig_date = Date, Ticker, Ret_fwd1M)],
               by = c("sig_date", "Ticker"), all.x = TRUE)
panel <- panel[!is.na(Ret_fwd1M)]

# IC computation
ic_dt <- panel[, .(
  rank_ic_S1 = cor(alpha, Ret_fwd1M, method = "spearman", use = "complete.obs"),
  rank_ic_S2 = cor(alpha_S2_PS, Ret_fwd1M, method = "spearman", use = "complete.obs"),
  rank_ic_S3 = cor(alpha_S3_PG, Ret_fwd1M, method = "spearman", use = "complete.obs"),
  N = .N
), by = sig_date][!is.na(rank_ic_S1)]

hac_t <- function(x, lag = 3) {
  n <- length(x); m <- mean(x, na.rm = TRUE); e <- x - m
  g0 <- sum(e^2, na.rm = TRUE) / n; s2 <- g0
  for (k in 1:lag) {
    gk <- sum(e[(k+1):n] * e[1:(n-k)], na.rm = TRUE) / n
    w <- 1 - k / (lag + 1); s2 <- s2 + 2 * w * gk
  }
  m / sqrt(s2 / n)
}

cat(sprintf("\n=== PIT-CLEAN v2 Diagnostics (n_months=%d) ===\n", nrow(ic_dt)))
for (s in c("S1", "S2", "S3")) {
  v <- ic_dt[[paste0("rank_ic_", s)]]
  m <- mean(v, na.rm = TRUE); sd_v <- sd(v, na.rm = TRUE)
  cat(sprintf("%s rank_ic=%.5f  ICIR=%.3f  NW-t=%.3f  pos=%.3f\n",
              s, m, m/sd_v*sqrt(12), hac_t(v), mean(v > 0, na.rm = TRUE)))
}

# Subperiod
ic_dt[, period := fcase(
  sig_date < as.Date("2015-01-01"), "p1_2008_2014",
  sig_date < as.Date("2020-01-01"), "p2_2015_2019",
  default = "p3_2020_2023"
)]
cat("\nSubperiod stability:\n")
print(ic_dt[, .(IC = mean(rank_ic_S1, na.rm = TRUE),
                ICIR = mean(rank_ic_S1, na.rm = TRUE)/sd(rank_ic_S1, na.rm = TRUE)*sqrt(12),
                pos = mean(rank_ic_S1 > 0, na.rm = TRUE), N = .N), by = period])

# Decile + monotonicity
panel[, decile := cut(alpha, breaks = quantile(alpha, probs = seq(0, 1, 0.1), na.rm = TRUE),
                       labels = 1:10, include.lowest = TRUE), by = sig_date]
dec_ret <- panel[!is.na(decile), .(MeanRet = mean(Ret_fwd1M, na.rm = TRUE)), by = decile]
dec_ret[, decile_num := as.integer(as.character(decile))]
setorder(dec_ret, decile_num)
print(dec_ret)
mono <- cor(dec_ret$decile_num, dec_ret$MeanRet, method = "spearman")
cat(sprintf("Decile rank-cor: %.4f\n", mono))
cat(sprintf("D10-D1 spread: %.5f\n", dec_ret$MeanRet[10] - dec_ret$MeanRet[1]))

# Save PIT-clean panel
saveRDS(panel, file.path(WT_DIR, "alpha_panel_v2_pit_clean.rds"))
cat("\nSaved alpha_panel_v2_pit_clean.rds\n")

# Single-axis ICIR (Codex C7 RF-A2 fix)
cat("\nSingle-axis ICIR:\n")
for (ax in c("Z_A1", "Z_A2", "Z_A3", "Z_A4")) {
  ax_ic <- panel[, .(ic = cor(get(ax), Ret_fwd1M, method = "spearman", use = "complete.obs")), by = sig_date]
  ax_ic <- ax_ic[!is.na(ic)]
  m <- mean(ax_ic$ic, na.rm = TRUE); sd_v <- sd(ax_ic$ic, na.rm = TRUE)
  cat(sprintf("  %s rank_ic=%.5f ICIR=%.3f NW-t=%.3f\n", ax, m, m/sd_v*sqrt(12), hac_t(ax_ic$ic)))
}
