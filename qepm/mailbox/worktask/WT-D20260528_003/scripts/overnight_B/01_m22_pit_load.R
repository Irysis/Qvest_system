#==============================================================================
# WT-D20260528_003 Hypothesis B Step 1 — M22_Max_Return PIT-clean load
#
# Bali-Cakici-Whitelaw 2011 JFE 99(2) MAX anomaly pure (single factor) in KR market.
# Direction: lower_better (high MAX → underperform). align_factor_direction → Z_aligned
# 자동 flip (low MAX raw → high Z_aligned).
#
# PIT compliance:
#   - C1: Walk-forward expanding (per sig_date), no full-sample
#   - C10: Liquidity 2e8 t-1 PIT
#   - C13: Z_Score_Aligned only (NO FLIP_SIGN, NO NEGATE)
#   - C14: load_month_factors() Usable_Date <= sig_date 자동
#   - C15: factor_db_connector 경유 (no direct parquet load)
#   - Cycle 51 shift convention: type="lead" + n=1L (forward direction)
#
# SIGNAL_CUTOFF: 2023-12-22 (정규 alpha-research lockbox)
# Universe: KOSPI200 ∪ KOSDAQ150 union (request.json mandate)
# Forecast horizon: 1M monthly
#
# Output:
#   - outputs/overnight_B/m22_panel_pit.parquet (Date × Ticker × Z_aligned + raw + fwd_ret + sector + liq)
#   - outputs/overnight_B/m22_step1_diag.json (panel size + PIT compliance)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)

OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/overnight_B")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")
UNIVERSE_K200 <- file.path(BASE, ".cache/universe_support/us_k200.parquet")
UNIVERSE_KQ150 <- file.path(BASE, ".cache/universe_support/us_kq150.parquet")

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# PIT C15: load_month_factors connector
source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

# ---- Constants ----
SIGNAL_CUTOFF <- as.Date("2023-12-22")  # PIT lockbox (정규 리서치 - alpha-research scope)
TARGET_FACTOR <- "M22_Max_Return"
LIQ_THRESHOLD <- 2e8  # 2e8 KRW (mandate)
LIQ_WINDOW_DAYS <- 20  # 20d avg TV
START_DATE <- as.Date("2005-01-31")

cat("[Step 1: M22_Max_Return PIT-clean load] === START ===\n")
cat("  SIGNAL_CUTOFF:", as.character(SIGNAL_CUTOFF), "\n")
cat("  TARGET_FACTOR:", TARGET_FACTOR, "\n")
cat("  LIQ_THRESHOLD:", LIQ_THRESHOLD, "KRW (20d avg TV t-1)\n\n")

t0 <- Sys.time()

# ---- 1. Universe (K200 ∪ KQ150 union) per sig_date ----
cat("[1] Loading K200 + KQ150 universe ...\n")
k200 <- as.data.table(read_parquet(UNIVERSE_K200))
kq150 <- as.data.table(read_parquet(UNIVERSE_KQ150))
k200[, Date := as.Date(Date)]
kq150[, Date := as.Date(Date)]

sig_dates_all <- sort(unique(k200$Date))
sig_dates <- sig_dates_all[sig_dates_all <= SIGNAL_CUTOFF & sig_dates_all >= START_DATE]
cat("  Total sig_dates:", length(sig_dates), "\n")
cat("  Range:", as.character(min(sig_dates)), "-", as.character(max(sig_dates)), "\n")

k200_in <- k200[K200 == 1, .(Date, Ticker)]
kq150_in <- kq150[KQ150 == 1, .(Date, Ticker)]
universe_set <- unique(rbind(k200_in, kq150_in))
setkey(universe_set, Date, Ticker)
cat("  Universe rows (K200 ∪ KQ150 union):", nrow(universe_set), "\n")

# ---- 2. Load rawdata (price + sector + Vol) ----
cat("\n[2] Loading rawdata price/return/Vol/Sector ...\n")
rd <- as.data.table(read_parquet(RAWDATA,
                                 col_select = c("Date","Ticker","Close","Ret","Sector","Vol","Size")))
rd[, Date := as.Date(Date)]
setkey(rd, Ticker, Date)

# ---- 3. Pre-compute 20-day rolling Trade Value (Close * Vol) — PIT t-1 ----
# Trade Value at day t = Close[t] * Vol[t]. Rolling 20-day MA shifted t-1.
cat("\n[3] Computing 20d trade value t-1 (PIT C10) ...\n")
rd[, Trade_Value := Close * Vol]
# Rolling 20d mean, then shift by 1 day → represents [t-20, t-1] window available at decision time t
rd[, TV_20d_PIT := {
  # Rolling mean, then 1-day lag
  rm <- frollmean(Trade_Value, n = 20, align = "right", na.rm = TRUE)
  shift(rm, n = 1L, type = "lag")
}, by = Ticker]
cat("  TV_20d_PIT NA rate:", round(mean(is.na(rd$TV_20d_PIT)) * 100, 1), "%\n")

# ---- 4. Monthly Close panel + forward 1M return ----
cat("\n[4] Monthly Close panel + forward 1M return (Cycle 51 shift convention) ...\n")
monthly_panel <- rd[Date %in% sig_dates, .(Date, Ticker, Close, Sector, TV_20d_PIT)]
setkey(monthly_panel, Ticker, Date)
# Forward 1M return: r(t, t+1M) = Close[t+1M] / Close[t] - 1
# data.table shift(n=1L, type="lead") = forward (Cycle 51 compliant)
monthly_panel[, fwd_close := shift(Close, n = 1L, type = "lead"), by = Ticker]
monthly_panel[, fwd_ret := fwd_close / Close - 1]
cat("  Monthly panel rows:", nrow(monthly_panel), "\n")
cat("  Fwd_ret coverage:", round(mean(!is.na(monthly_panel$fwd_ret)) * 100, 1), "%\n")

# Cycle 51 sanity check: forward return direction
# Test on a known KOSPI bear/bull date — simple sample
sample_date <- as.Date("2008-09-30")  # Lehman Brothers bear
if (sample_date %in% monthly_panel$Date) {
  sample_data <- monthly_panel[Date == sample_date & !is.na(fwd_ret)]
  if (nrow(sample_data) > 0) {
    avg_fwd_ret_sample <- mean(sample_data$fwd_ret, na.rm = TRUE)
    cat("  Sanity check 2008-09-30 (Lehman bear): avg fwd_1M ret =",
        round(avg_fwd_ret_sample * 100, 2), "% (negative expected if forward correct)\n")
  }
}

# ---- 5. Per sig_date: M22 Z_aligned load + universe + liquidity filter ----
cat("\n[5] Per-sig_date M22 Z_Score_Aligned extraction (PIT C14 + C15) ...\n")
panel_list <- vector("list", length(sig_dates))
load_fail_count <- 0L

for (i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]

  # PIT C14 + C15: load_month_factors auto-uses Usable_Date <= sig_d
  panel_long <- tryCatch(load_month_factors(sig_d), error = function(e) {
    load_fail_count <<- load_fail_count + 1L
    NULL
  })
  if (is.null(panel_long)) next
  panel_long <- as.data.table(panel_long)

  # Filter to M22 only
  panel_m22 <- panel_long[Factor_Name == TARGET_FACTOR]
  if (nrow(panel_m22) == 0) next

  # Universe filter (K200 ∪ KQ150 at this Date)
  univ_at_d <- universe_set[Date == sig_d, Ticker]
  if (length(univ_at_d) == 0) {
    last_u_d <- max(universe_set$Date[universe_set$Date <= sig_d])
    univ_at_d <- universe_set[Date == last_u_d, Ticker]
  }
  panel_m22 <- panel_m22[Ticker %in% univ_at_d]

  panel_m22[, Date := sig_d]
  panel_list[[i]] <- panel_m22[, .(Date, Ticker, Z_aligned = Z_Score_Aligned)]

  if (i %% 50 == 0) {
    cat("  ", i, "/", length(sig_dates), "(", as.character(sig_d), ") n_ticker=",
        nrow(panel_m22), "\n", sep="")
  }
}

panel_factor <- rbindlist(panel_list, use.names = TRUE, fill = TRUE)
panel_factor[, Date := as.Date(Date)]
cat("\n  Factor panel rows:", nrow(panel_factor), "\n")
cat("  Unique sig_dates:", uniqueN(panel_factor$Date), "\n")
cat("  Unique Tickers:", uniqueN(panel_factor$Ticker), "\n")
cat("  load_month_factors fail count:", load_fail_count, "\n\n")

# ---- 6. Merge with monthly_panel (fwd_ret + Sector + TV_20d_PIT) ----
cat("[6] Merge factor with fwd_ret + Sector + TV_20d_PIT ...\n")
panel <- merge(panel_factor, monthly_panel[, .(Date, Ticker, Close, Sector, fwd_ret, TV_20d_PIT)],
               by = c("Date", "Ticker"), all.x = TRUE)
cat("  Pre-filter rows:", nrow(panel), "\n")

# Liquidity filter: TV_20d_PIT >= 2e8 (PIT t-1, NA excluded)
panel[, liq_pass := !is.na(TV_20d_PIT) & TV_20d_PIT >= LIQ_THRESHOLD]
n_pass_liq <- sum(panel$liq_pass)
cat("  Pass liq (TV_20d_PIT >= 2e8):", n_pass_liq, "(",
    round(n_pass_liq / nrow(panel) * 100, 1), "%)\n")

# Final clean panel: liq pass + has fwd_ret + has Z_aligned
panel_clean <- panel[liq_pass == TRUE & !is.na(fwd_ret) & !is.na(Z_aligned)]
cat("  Clean panel (liq+fwd_ret+Z):", nrow(panel_clean), "rows\n")
cat("  Clean unique sig_dates:", uniqueN(panel_clean$Date), "\n")
cat("  Clean unique Tickers:", uniqueN(panel_clean$Ticker), "\n")
cat("  Clean avg n_ticker per Date:",
    round(nrow(panel_clean) / uniqueN(panel_clean$Date), 1), "\n\n")

# ---- 7. Save ----
cat("[7] Save outputs ...\n")
write_parquet(panel_clean, file.path(OUT_DIR, "m22_panel_pit.parquet"))
cat("  saved: m22_panel_pit.parquet (", nrow(panel_clean), "rows)\n")

diag <- list(
  task_id = "WT-D20260528_003",
  hypothesis = "B",
  step = "01_m22_pit_load",
  signal_cutoff = as.character(SIGNAL_CUTOFF),
  target_factor = TARGET_FACTOR,
  liq_threshold = LIQ_THRESHOLD,
  liq_window_days = LIQ_WINDOW_DAYS,
  start_date = as.character(START_DATE),
  n_sig_dates_total = length(sig_dates),
  load_fail_count = load_fail_count,
  panel_rows_total = nrow(panel),
  panel_rows_clean = nrow(panel_clean),
  n_sig_dates_clean = uniqueN(panel_clean$Date),
  n_tickers_unique = uniqueN(panel_clean$Ticker),
  avg_n_per_date = round(nrow(panel_clean) / uniqueN(panel_clean$Date), 2),
  liq_pass_rate = round(n_pass_liq / nrow(panel) * 100, 2),
  pit_compliance = list(
    C1 = "Walk-forward expanding per sig_date",
    C10 = paste0("TV_20d_PIT t-1 lag, threshold ", LIQ_THRESHOLD, " KRW"),
    C13 = "Z_Score_Aligned only via load_month_factors",
    C14 = "Usable_Date <= sig_date via load_month_factors auto",
    C15 = "factor_db_connector path only (no direct parquet)",
    Cycle_51_shift = "shift(n=1L, type='lead') forward direction (data.table doc-confirmed)"
  ),
  bali_2011_reference = list(
    citation = "Bali, T. G., Cakici, N., & Whitelaw, R. F. (2011). Maxing out: Stocks as lotteries and the cross-section of expected returns. Journal of Financial Economics, 99(2), 427-446.",
    direction = "lower_better",
    economic_rationale = "Investors with lottery preference overpay for high MAX stocks → MAX(t) → 1M return(t+1) negative correlation. KR retail 50%+ predicts strong effect.",
    factor_registry_match = "M22_Max_Return / category=momentum / direction=lower_better / evidence_tier=B"
  )
)
write_json(diag, file.path(OUT_DIR, "m22_step1_diag.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: m22_step1_diag.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 1] === DONE === elapsed:", round(elapsed, 1), "sec\n")
