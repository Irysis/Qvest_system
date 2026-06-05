#==============================================================================
# WT-D20260528_003 v3.7 — Step 1: Top 12 Single Factor IC Validation
#
# Hypothesis: Factor DB Phase 1 untapped audit + Phase 3 orthogonal selection
# 12 single factor (ICIR_5y 0.57+) — single-factor IC re-verification per sig_date
# PIT C1 + C13 + C14 + C15 정합 (load_month_factors connector mandatory)
#
# Output:
#   - outputs/v3_7/top12_factor_panel.parquet (Date × Ticker × 12 Z_aligned)
#   - outputs/v3_7/top12_single_factor_ic.json (per-factor rank IC + ICIR per period)
#   - outputs/v3_7/top12_subperiod_stability.json (3-chunk subperiod IC)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_WT-D20260528_003_v3_7")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")
UNIVERSE_K200 <- file.path(BASE, ".cache/universe_support/us_k200.parquet")
UNIVERSE_KQ150 <- file.path(BASE, ".cache/universe_support/us_kq150.parquet")

# PIT C15: load_month_factors connector
source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

# ---- Constants ----
SIGNAL_CUTOFF <- as.Date("2023-12-22")  # PIT lockbox (정규 리서치 - alpha-research scope)
TOP12 <- c("D43_Skewness", "D44_Kurtosis", "L44_Vol_Ret_Asymmetry",
           "CR08_Volume_Price_Divergence", "Q07_Earnings_Stability",
           "M22_Max_Return", "L42_Vol_Skewness", "CR01_Sector_Comovement",
           "Q11_Net_Margin", "D22_Tracking_Error", "Q32_Interest_Coverage",
           "L33_AbsRet_Vol_Corr")

cat("[Step 1: Top 12 single factor IC validation] === START ===\n")
cat("  SIGNAL_CUTOFF:", as.character(SIGNAL_CUTOFF), "\n")
cat("  N factors:", length(TOP12), "\n\n")

t0 <- Sys.time()

# ---- 1. Universe (K200 ∪ KQ150 intersection) per sig_date ----
cat("[1] Loading K200 + KQ150 universe ...\n")
k200 <- as.data.table(read_parquet(UNIVERSE_K200))
kq150 <- as.data.table(read_parquet(UNIVERSE_KQ150))
k200[, Date := as.Date(Date)]
kq150[, Date := as.Date(Date)]

# Sig date list: month-end from 2005-01-31 to 2023-11-30 (≤ SIGNAL_CUTOFF)
sig_dates_all <- sort(unique(k200$Date))
sig_dates <- sig_dates_all[sig_dates_all <= SIGNAL_CUTOFF & sig_dates_all >= as.Date("2005-01-31")]
cat("  Total sig_dates:", length(sig_dates), "\n")
cat("  Range:", as.character(min(sig_dates)), "-", as.character(max(sig_dates)), "\n")

# Build universe set per Date: K200=1 ∪ KQ150=1
k200_in <- k200[K200 == 1, .(Date, Ticker)]
kq150_in <- kq150[KQ150 == 1, .(Date, Ticker)]
universe_set <- unique(rbind(k200_in, kq150_in))
setkey(universe_set, Date, Ticker)
cat("  Universe rows (K200 ∪ KQ150):", nrow(universe_set), "\n")

# ---- 2. Load rawdata (price + sector) ----
cat("\n[2] Loading rawdata price/return + sector ...\n")
rd <- as.data.table(read_parquet(RAWDATA,
                                 col_select = c("Date","Ticker","Close","Ret","Sector","Vol","Size")))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)

# 1M forward return for IC (use Close pivot)
# For each sig_d in sig_dates: forward 1M return = Close[next_sig_d] / Close[sig_d] - 1
# Build monthly Close panel
monthly_close <- rd[Date %in% sig_dates, .(Date, Ticker, Close)]
setkey(monthly_close, Ticker, Date)
monthly_close[, fwd_close := shift(Close, n = 1L, type = "lead"), by = Ticker]
monthly_close[, fwd_ret := fwd_close / Close - 1]

# ---- 3. Per sig_date: load Z_aligned for Top 12 factors ----
cat("\n[3] Per-sig_date factor load + Z extraction ...\n")
panel_list <- vector("list", length(sig_dates))

for (i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]

  # PIT C14: load_month_factors uses Usable_Date <= sig_date 자동
  panel_long <- tryCatch(load_month_factors(sig_d), error = function(e) NULL)
  if (is.null(panel_long)) next
  panel_long <- as.data.table(panel_long)

  # Filter to Top 12
  panel_long_top <- panel_long[Factor_Name %in% TOP12]
  if (nrow(panel_long_top) == 0) next

  # Wide pivot: Ticker × 12 factor Z_aligned
  panel_wide <- dcast(panel_long_top, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  panel_wide[, Date := sig_d]

  # Universe filter (K200 ∪ KQ150 at this Date)
  univ_at_d <- universe_set[Date == sig_d, Ticker]
  if (length(univ_at_d) == 0) {
    # Fallback: latest universe before sig_d
    last_u_d <- max(universe_set$Date[universe_set$Date <= sig_d])
    univ_at_d <- universe_set[Date == last_u_d, Ticker]
  }
  panel_wide <- panel_wide[Ticker %in% univ_at_d]

  panel_list[[i]] <- panel_wide

  if (i %% 30 == 0) cat("  ", i, "/", length(sig_dates), "(", as.character(sig_d), ") rows=", nrow(panel_wide), "\n")
}

panel <- rbindlist(panel_list, use.names = TRUE, fill = TRUE)
panel[, Date := as.Date(Date)]
setcolorder(panel, c("Date", "Ticker", TOP12))
cat("\n  Panel total rows:", nrow(panel), "\n")
cat("  Panel unique sig_dates:", uniqueN(panel$Date), "\n")
cat("  Panel unique Tickers:", uniqueN(panel$Ticker), "\n\n")

# ---- 4. Merge forward return for IC ----
cat("[4] Merge forward 1M return ...\n")
panel <- merge(panel, monthly_close[, .(Date, Ticker, fwd_ret)],
               by = c("Date", "Ticker"), all.x = TRUE)
panel_ic <- panel[!is.na(fwd_ret)]
cat("  Panel with fwd_ret:", nrow(panel_ic), "rows | unique dates:", uniqueN(panel_ic$Date), "\n")

# ---- 5. Per-factor cross-sectional rank IC per Date ----
cat("\n[5] Computing rank IC per Date per factor ...\n")
ic_per_factor <- list()
for (fc in TOP12) {
  ic_dt <- panel_ic[!is.na(get(fc)), .(
    n = .N,
    rank_ic = if (.N >= 10) suppressWarnings(cor(get(fc), fwd_ret, method = "spearman")) else NA_real_
  ), by = Date]
  ic_dt <- ic_dt[!is.na(rank_ic)]
  ic_per_factor[[fc]] <- ic_dt
}

# Per-factor full-period ICIR
factor_summary <- data.table()
for (fc in TOP12) {
  ic_dt <- ic_per_factor[[fc]]
  if (nrow(ic_dt) < 5) next
  m <- mean(ic_dt$rank_ic, na.rm = TRUE)
  s <- sd(ic_dt$rank_ic, na.rm = TRUE)
  icir <- if (!is.na(s) && s > 0) m / s else NA_real_
  factor_summary <- rbind(factor_summary, data.table(
    Factor_Name = fc,
    n_dates = nrow(ic_dt),
    rank_ic_mean = m,
    rank_ic_sd = s,
    icir_full = icir,
    rank_ic_t = m / (s / sqrt(nrow(ic_dt)))
  ))
}
print(factor_summary)
cat("\n")

# ---- 6. Subperiod stability (3-chunk: 2005-2014 / 2015-2019 / 2020-2026) ----
cat("[6] Subperiod stability 3-chunk ...\n")
subperiods <- list(
  P1 = list(start = "2005-01-01", end = "2014-12-31"),
  P2 = list(start = "2015-01-01", end = "2019-12-31"),
  P3 = list(start = "2020-01-01", end = "2026-12-31")
)

subperiod_dt <- data.table()
for (fc in TOP12) {
  ic_dt <- ic_per_factor[[fc]]
  row <- list(Factor_Name = fc)
  for (pn in names(subperiods)) {
    sub_ic <- ic_dt[Date >= as.Date(subperiods[[pn]]$start) &
                    Date <= as.Date(subperiods[[pn]]$end)]
    if (nrow(sub_ic) >= 5) {
      m <- mean(sub_ic$rank_ic, na.rm = TRUE)
      s <- sd(sub_ic$rank_ic, na.rm = TRUE)
      row[[paste0(pn, "_n")]] <- nrow(sub_ic)
      row[[paste0(pn, "_ic")]] <- m
      row[[paste0(pn, "_icir")]] <- if (!is.na(s) && s > 0) m / s else NA_real_
    } else {
      row[[paste0(pn, "_n")]] <- nrow(sub_ic)
      row[[paste0(pn, "_ic")]] <- NA_real_
      row[[paste0(pn, "_icir")]] <- NA_real_
    }
  }
  # Stability: ratio of min(|ICIR|) / max(|ICIR|) (sign-agnostic)
  icirs <- c(row$P1_icir, row$P2_icir, row$P3_icir)
  icirs <- icirs[!is.na(icirs)]
  if (length(icirs) >= 2) {
    row$stability <- min(abs(icirs)) / max(abs(icirs))
  } else {
    row$stability <- NA_real_
  }
  subperiod_dt <- rbind(subperiod_dt, as.data.table(row), fill = TRUE)
}
print(subperiod_dt)
cat("\n")

# ---- 7. 5y ICIR (recent 60-month) ----
cat("[7] Recent 5y ICIR ...\n")
recent_cutoff <- as.Date("2018-12-31")  # 5y prior to 2023-12 cutoff
recent_dt <- data.table()
for (fc in TOP12) {
  ic_dt <- ic_per_factor[[fc]]
  recent_ic <- ic_dt[Date >= recent_cutoff]
  if (nrow(recent_ic) < 12) next
  m <- mean(recent_ic$rank_ic, na.rm = TRUE)
  s <- sd(recent_ic$rank_ic, na.rm = TRUE)
  recent_dt <- rbind(recent_dt, data.table(
    Factor_Name = fc,
    n_dates_5y = nrow(recent_ic),
    rank_ic_mean_5y = m,
    icir_5y = if (!is.na(s) && s > 0) m / s else NA_real_
  ))
}
print(recent_dt)
cat("\n")

# ---- 8. Save outputs ----
cat("[8] Save outputs ...\n")
write_parquet(panel, file.path(OUT_DIR, "top12_factor_panel.parquet"))
cat("  saved: top12_factor_panel.parquet (", nrow(panel), "rows)\n")

# IC per factor per Date (long format)
ic_long <- rbindlist(lapply(names(ic_per_factor), function(fc) {
  dt <- ic_per_factor[[fc]]
  dt[, Factor_Name := fc]
  dt
}), use.names = TRUE)
write_parquet(ic_long, file.path(OUT_DIR, "top12_ic_per_date.parquet"))
cat("  saved: top12_ic_per_date.parquet (", nrow(ic_long), "rows)\n")

# Diagnostics JSON
diag <- list(
  task_id = "WT-D20260528_003",
  step = "01_top12_single_factor_validation",
  signal_cutoff = as.character(SIGNAL_CUTOFF),
  n_factors = length(TOP12),
  n_sig_dates_total = length(sig_dates),
  panel_rows = nrow(panel),
  panel_with_fwd_ret = nrow(panel_ic),
  universe = "KOSPI200_KOSDAQ150_union",
  factor_summary_full = lapply(seq_len(nrow(factor_summary)), function(i) as.list(factor_summary[i])),
  subperiod_stability = lapply(seq_len(nrow(subperiod_dt)), function(i) as.list(subperiod_dt[i])),
  recent_5y_icir = lapply(seq_len(nrow(recent_dt)), function(i) as.list(recent_dt[i])),
  pit_compliance = list(
    C14 = "Usable_Date <= sig_date via load_month_factors() auto",
    C15 = "load_month_factors connector path used",
    C13 = "Z_Score_Aligned only (no FLIP_SIGN)"
  )
)
write_json(diag, file.path(OUT_DIR, "top12_single_factor_ic.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: top12_single_factor_ic.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 1] === DONE === elapsed:", round(elapsed, 1), "sec\n")
