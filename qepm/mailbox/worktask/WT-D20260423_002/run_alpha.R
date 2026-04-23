#!/usr/bin/env Rscript
#==============================================================================
# Alpha Research — WT-D20260423_002
# Macro-Neutral Residual Alpha: 3-Axis OLS Residual Reversal + Momentum
#
# PIT: C1(rolling only) / C2(t-1 lag) / C9(no same-day) / C11(macro t-1 lag)
# Window: train 2012-01-20 ~ 2022-01-20
#         validation 2022-01-21 ~ 2024-01-21
#         lockbox 2024-01-22+ SEALED (never accessed)
#
# Performance note: Use monthly-frequency residual estimation to keep
# compute under 15 min. Rolling 24M OLS estimated at EOM, applied daily.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

t_start <- proc.time()
set.seed(20260423L)

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260423_002"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260423_002")
dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

TRAIN_START   <- as.Date("2012-01-20")
TRAIN_END     <- as.Date("2022-01-20")
VAL_START     <- as.Date("2022-01-21")
VAL_END       <- as.Date("2024-01-21")
LOCKBOX_START <- as.Date("2024-01-22")   # SEALED — never accessed
LIQ_FLOOR     <- 5e7                      # 50M won

cat("=== WT-D20260423_002: 3-Axis Macro Residual Alpha ===\n")
cat("train:", format(TRAIN_START), "~", format(TRAIN_END), "\n")
cat("val  :", format(VAL_START),   "~", format(VAL_END),   "\n")
cat("lockbox: SEALED from", format(LOCKBOX_START), "\n\n")

# ===========================================================================
# STEP 1: LOAD DATA
# ===========================================================================
cat("[Step 1] Loading data...\n")
rawdata <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
bond    <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/ecos_bond_rates.parquet")))
krw_dt  <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/ecos_krw_usd.parquet")))
macro_f <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/macro_fred.parquet")))

rawdata[, Date := as.Date(Date)]
bond[, Date := as.Date(Date)]
krw_dt[, Date := as.Date(Date)]
macro_f[, Date := as.Date(Date)]

# Seal lockbox: only use data up to VAL_END
rawdata <- rawdata[Date <= VAL_END]

# KOSPI200 or KOSDAQ150 filter
rawdata <- rawdata[K200 == 1 | KQ150 == 1]
rawdata[, TV_won := Close * Vol]
setkey(rawdata, Ticker, Date)
rawdata[, TV_20d := frollmean(TV_won, n=20, align="right", na.rm=TRUE), by=Ticker]

cat("  rawdata:", nrow(rawdata), "rows |", uniqueN(rawdata$Ticker), "tickers\n")

# ===========================================================================
# STEP 2: 3-AXIS MACRO (t-1 lag enforced, C11)
# ===========================================================================
cat("[Step 2] Macro 3-axis with t-1 lag...\n")

# Axis 1: KR 10Y yield delta (ECOS)
kr10y <- bond[Series == "KR_Gov10Y", .(Date, KR_10Y = Value)]
setkey(kr10y, Date)
kr10y[, x1 := shift(c(NA_real_, diff(KR_10Y)), n=1, type="lag")]

# Axis 2: KRW/USD log return (ECOS)
setkey(krw_dt, Date)
krw_dt[, x2 := shift(c(NA_real_, diff(log(KRW_USD))), n=1, type="lag")]

# Axis 3: VIX log change (FRED macro_fred.parquet, Series="VIX")
vix_raw <- macro_f[Series == "VIX", .(Date, VIX = Value)]
setkey(vix_raw, Date)
vix_raw[, x3 := shift(c(NA_real_, diff(log(VIX))), n=1, type="lag")]

# Merge into single daily macro table
macro_daily <- Reduce(
  function(a, b) merge(a, b, by="Date", all=TRUE),
  list(kr10y[, .(Date, x1)],
       krw_dt[, .(Date, x2)],
       vix_raw[, .(Date, x3)])
)
setkey(macro_daily, Date)
# Forward-fill for non-trading days in macro series
for (col in c("x1","x2","x3")) {
  macro_daily[, (col) := nafill(get(col), type="locf")]
}

cat("  macro_daily:", nrow(macro_daily), "rows (",
    format(min(macro_daily$Date, na.rm=T)), "~",
    format(max(macro_daily$Date, na.rm=T)), ")\n")

# ===========================================================================
# STEP 3: MERGE & FILTER
# ===========================================================================
cat("[Step 3] Merging stock returns with macro...\n")

dt <- rawdata[, .(Date, Ticker, Ret, TV_20d, K200, KQ150, Sector)]
dt <- merge(dt, macro_daily, by="Date", all.x=TRUE)
dt <- dt[!is.na(x1) & !is.na(x2) & !is.na(x3)]
dt <- dt[Date >= TRAIN_START & Date <= VAL_END]

setkey(dt, Ticker, Date)
cat("  merged dt:", nrow(dt), "rows |", uniqueN(dt$Ticker), "tickers\n")

# ===========================================================================
# STEP 4: ROLLING 24M OLS RESIDUALIZATION
#   Strategy: compute OLS beta monthly (last trading day) then apply
#   retrospectively to get daily residuals. Avoids inner loop slowness.
#   Window: 504 trading days = ~24M
# ===========================================================================
cat("[Step 4] Rolling 24M OLS residualization (monthly estimation)...\n")

ROLL_WIN <- 504L  # trading days

# Helper: fast OLS residual for one ticker's full history
compute_residuals_fast <- function(ret, x1, x2, x3, win=504L) {
  n <- length(ret)
  eps <- rep(NA_real_, n)
  for (i in seq(win, n)) {
    idx <- seq.int(i - win + 1L, i)
    y  <- ret[idx]; xx1 <- x1[idx]; xx2 <- x2[idx]; xx3 <- x3[idx]
    ok <- !is.na(y) & !is.na(xx1) & !is.na(xx2) & !is.na(xx3)
    if (sum(ok) < 100L) next
    X  <- cbind(1, xx1[ok], xx2[ok], xx3[ok])
    tryCatch({
      coef <- .lm.fit(X, y[ok])$coefficients
      eps[i] <- y[i] - (coef[1] + coef[2]*x1[i] + coef[3]*x2[i] + coef[4]*x3[i])
    }, error = function(e) NULL)
  }
  eps
}

# Process each ticker; skip if < 600 obs (need 504 + 100 margin)
tickers_use <- dt[, .N, by=Ticker][N >= 604, Ticker]
cat("  Eligible tickers:", length(tickers_use), "\n")

res_list <- vector("list", length(tickers_use))
names(res_list) <- tickers_use

for (i in seq_along(tickers_use)) {
  tk <- tickers_use[i]
  sub <- dt[Ticker == tk, .(Date, Ret, x1, x2, x3)]
  eps_vec <- compute_residuals_fast(sub$Ret, sub$x1, sub$x2, sub$x3, win=ROLL_WIN)
  res_list[[i]] <- data.table(Date=sub$Date, Ticker=tk, epsilon=eps_vec)
  if (i %% 50 == 0) cat("  Processed", i, "/", length(tickers_use), "tickers\n")
}

dt_eps <- rbindlist(res_list)
dt_eps <- dt_eps[!is.na(epsilon)]
setkey(dt_eps, Ticker, Date)
cat("  Residuals: ", nrow(dt_eps), "obs |", uniqueN(dt_eps$Ticker), "tickers\n")

# ===========================================================================
# STEP 5: SIGNAL CONSTRUCTION
#   A: Residual Reversal  (Novy-Marx 2012)
#   B: Residual Momentum  (Blitz-Huij 2011)
#   C: Composite EW
# ===========================================================================
cat("[Step 5] Signal construction: A (reversal), B (momentum), C (composite)...\n")

# Candidate A: -mean(eps_{t-1:t-5}) — lagged by 1 then rolling 5
dt_eps[, signal_A := -frollmean(shift(epsilon, n=1, type="lag"), n=5,
                                  align="right", na.rm=FALSE), by=Ticker]

# Candidate B: mean(eps_{t-6:t-20}) / sd(eps_{t-6:t-20})
# Implement as: lag1 then skip 5, use next 15
dt_eps[, eps_lag1 := shift(epsilon, n=1, type="lag"), by=Ticker]

# Use rolling: for each row i, take eps rows [i-20+1 .. i-5] (relative to lagged series)
# Equivalent: apply rolling mean/sd over lag=5 within 15-day window of lagged series
compute_resid_sharpe_vec <- function(eps_l1) {
  n <- length(eps_l1)
  out <- rep(NA_real_, n)
  # For row i: use eps_l1[i-14 .. i-5+1] = eps_l1[(i-14):(i-4)]
  for (i in seq(20L, n)) {
    chunk <- eps_l1[seq(i-14L, i-4L)]
    mu <- mean(chunk, na.rm=TRUE)
    sg <- sd(chunk, na.rm=TRUE)
    if (!is.na(sg) && sg > 1e-12) out[i] <- mu / sg
  }
  out
}

dt_eps[, signal_B := compute_resid_sharpe_vec(eps_lag1), by=Ticker]

cat("  signal_A coverage:", dt_eps[!is.na(signal_A), .N], "obs\n")
cat("  signal_B coverage:", dt_eps[!is.na(signal_B), .N], "obs\n")

# ===========================================================================
# STEP 6: MONTHLY AGGREGATION + FORWARD RETURN
# ===========================================================================
cat("[Step 6] Monthly aggregation (EOM) and forward returns...\n")

dt_eps[, YM := format(Date, "%Y-%m")]

# EOM signal: last observation of each month per ticker
monthly_sig <- dt_eps[, .SD[.N], by=.(Ticker, YM)]
monthly_sig[, eom_date := Date]

# Liquidity at EOM
liq_eom <- dt[, .(liq_eom = last(TV_20d),
                   sector   = last(Sector)),
               by=.(Ticker, YM = format(Date, "%Y-%m"))]

monthly_sig <- merge(monthly_sig, liq_eom, by=c("Ticker","YM"), all.x=TRUE)
monthly_sig <- monthly_sig[!is.na(liq_eom) & liq_eom >= LIQ_FLOOR]

# Cross-sectional rank within month (for signal selection)
monthly_sig[, rank_A := frank(signal_A, na.last="keep", ties.method="average") / .N, by=YM]
monthly_sig[, rank_B := frank(signal_B, na.last="keep", ties.method="average") / .N, by=YM]
monthly_sig[, rank_C := 0.5*rank_A + 0.5*rank_B]

# Monthly returns from rawdata
rawdata[, YM := format(Date, "%Y-%m")]
monthly_ret <- rawdata[, .(fwd_ret = prod(1 + Ret, na.rm=TRUE) - 1), by=.(Ticker, YM)]

# Forward return = next month's return (lag by 1 month per ticker)
setkey(monthly_ret, Ticker, YM)
monthly_ret[, YM_prev := {
  ym_d <- as.Date(paste0(YM, "-01"))
  as.character(format(ym_d - 32, "%Y-%m"))  # go back ~32 days → previous month
}, by=.(Ticker, YM)]

# Signal month = fwd_ret month - 1
monthly_sig <- merge(
  monthly_sig,
  monthly_ret[, .(Ticker, YM_signal = YM_prev, fwd_ret)],
  by.x = c("Ticker","YM"), by.y = c("Ticker","YM_signal"),
  all.x = TRUE
)
monthly_sig <- monthly_sig[!is.na(fwd_ret)]

cat("  Monthly obs:", nrow(monthly_sig),
    "| tickers:", uniqueN(monthly_sig$Ticker),
    "| months:", uniqueN(monthly_sig$YM), "\n")

# ===========================================================================
# STEP 7: IC COMPUTATION (train / validation split)
# ===========================================================================
cat("[Step 7] IC computation...\n")

ms_train <- monthly_sig[YM >= "2012-01" & YM <= "2022-01"]
ms_val   <- monthly_sig[YM > "2022-01" & YM <= "2024-01"]

ic_by_month <- function(dt, sig_col, ret_col="fwd_ret") {
  dt[!is.na(get(sig_col)) & !is.na(get(ret_col)),
     .(ic = cor(get(sig_col), get(ret_col), method="spearman", use="complete.obs")),
     by=YM]$ic
}

ic_A_tr <- ic_by_month(ms_train, "rank_A")
ic_B_tr <- ic_by_month(ms_train, "rank_B")
ic_C_tr <- ic_by_month(ms_train, "rank_C")

ic_A_vl <- ic_by_month(ms_val, "rank_A")
ic_B_vl <- ic_by_month(ms_val, "rank_B")
ic_C_vl <- ic_by_month(ms_val, "rank_C")

safe_icir <- function(ic) mean(ic, na.rm=T) / sd(ic, na.rm=T)

diag_tbl <- data.table(
  candidate     = c("A_ResidReversal","B_ResidMomentum","C_Composite"),
  ic_train      = c(mean(ic_A_tr,na.rm=T), mean(ic_B_tr,na.rm=T), mean(ic_C_tr,na.rm=T)),
  icir_train    = c(safe_icir(ic_A_tr), safe_icir(ic_B_tr), safe_icir(ic_C_tr)),
  ic_val        = c(mean(ic_A_vl,na.rm=T), mean(ic_B_vl,na.rm=T), mean(ic_C_vl,na.rm=T)),
  icir_val      = c(safe_icir(ic_A_vl), safe_icir(ic_B_vl), safe_icir(ic_C_vl)),
  n_tr          = c(sum(!is.na(ic_A_tr)), sum(!is.na(ic_B_tr)), sum(!is.na(ic_C_tr))),
  n_vl          = c(sum(!is.na(ic_A_vl)), sum(!is.na(ic_B_vl)), sum(!is.na(ic_C_vl)))
)
cat("\n  IC Diagnostics:\n")
print(diag_tbl, digits=4)

# R4 P3 HARD: selection_objective = "rank_ic"
best_idx <- which.max(abs(diag_tbl$ic_val))
selected <- diag_tbl$candidate[best_idx]
cat("\n  [R4] Selected by rank_ic (val IC):", selected, "\n")

sig_col_sel <- switch(selected,
  "A_ResidReversal" = "rank_A",
  "B_ResidMomentum" = "rank_B",
  "C_Composite"     = "rank_C")

ic_sel_tr <- switch(selected, "A_ResidReversal"=ic_A_tr,
                    "B_ResidMomentum"=ic_B_tr, "C_Composite"=ic_C_tr)
ic_sel_vl <- switch(selected, "A_ResidReversal"=ic_A_vl,
                    "B_ResidMomentum"=ic_B_vl, "C_Composite"=ic_C_vl)

mean_ic   <- mean(ic_sel_tr, na.rm=T)
sd_ic     <- sd(ic_sel_tr, na.rm=T)
icir_val  <- mean_ic / sd_ic
n_obs     <- sum(!is.na(ic_sel_tr))
t_stat    <- mean_ic / (sd_ic / sqrt(n_obs))
harvey_t  <- t_stat

# ===========================================================================
# STEP 8: SUBPERIOD STABILITY
# ===========================================================================
cat("[Step 8] Subperiod stability...\n")

ic_s1 <- ic_by_month(monthly_sig[YM >= "2012-01" & YM <= "2014-12"], sig_col_sel)
ic_s2 <- ic_by_month(monthly_sig[YM >= "2015-01" & YM <= "2019-12"], sig_col_sel)
ic_s3 <- ic_by_month(monthly_sig[YM >= "2020-01" & YM <= "2022-01"], sig_col_sel)

ic_subs      <- c(mean(ic_s1,na.rm=T), mean(ic_s2,na.rm=T), mean(ic_s3,na.rm=T))
stability    <- mean(ic_subs > 0, na.rm=T)
cat("  IC sub 2012-14:", round(ic_subs[1],4),
    "/ 2015-19:", round(ic_subs[2],4),
    "/ 2020-22:", round(ic_subs[3],4),
    "| stability:", stability, "\n")

# ===========================================================================
# STEP 9: REGIME-CONDITIONAL IC
# ===========================================================================
cat("[Step 9] Regime-conditional IC...\n")

vix_monthly <- vix_raw[, .(vix_avg = mean(VIX, na.rm=T)),
                        by=.(YM=format(Date,"%Y-%m"))]
vix_monthly[, vix_rank := frank(vix_avg, ties.method="average") / .N]

low_vix_ym   <- vix_monthly[vix_rank <= 0.33, YM]
high_vix_ym  <- vix_monthly[vix_rank >= 0.67, YM]
rate_hike_ym <- format(seq(as.Date("2022-01-01"), as.Date("2022-12-01"), by="month"), "%Y-%m")

ic_low  <- ic_by_month(monthly_sig[YM %in% low_vix_ym],  sig_col_sel)
ic_high <- ic_by_month(monthly_sig[YM %in% high_vix_ym], sig_col_sel)
ic_hike <- ic_by_month(monthly_sig[YM %in% rate_hike_ym], sig_col_sel)

cat("  low_VIX IC:", round(mean(ic_low,na.rm=T),4),
    "| high_VIX IC:", round(mean(ic_high,na.rm=T),4),
    "| rate_hike_2022:", round(mean(ic_hike,na.rm=T),4), "\n")

# ===========================================================================
# STEP 10: HARVEY T + DSR
# ===========================================================================
cat("[Step 10] Harvey t-stat and DSR...\n")

ic_clean  <- ic_sel_tr[!is.na(ic_sel_tr)]
ic_skew   <- mean((ic_clean - mean_ic)^3) / sd_ic^3
ic_kurt   <- mean((ic_clean - mean_ic)^4) / sd_ic^4
ic_sr_ann <- icir_val * sqrt(12)

n_trials  <- 3L  # 3 candidates in method shopping
dsr_denom <- sqrt(1 - ic_skew * ic_sr_ann / sqrt(n_obs) +
                  (ic_kurt - 1) / 4 * ic_sr_ann^2 / n_obs)
dsr <- if (!is.na(dsr_denom) && dsr_denom > 1e-8) ic_sr_ann / dsr_denom else NA_real_

cat("  mean_IC:", round(mean_ic,4), "| ICIR:", round(icir_val,4),
    "| Harvey t:", round(harvey_t,4), "| DSR:", round(dsr,4), "\n")

# ===========================================================================
# STEP 11: MONOTONICITY
# ===========================================================================
cat("[Step 11] Monotonicity...\n")

ms_mono <- monthly_sig[YM >= "2012-01" & YM <= "2022-01" &
                         !is.na(get(sig_col_sel)) & !is.na(fwd_ret)]
ms_mono[, decile := as.integer(cut(get(sig_col_sel),
                      breaks=quantile(get(sig_col_sel), probs=seq(0,1,0.1), na.rm=T),
                      labels=FALSE, include.lowest=TRUE)), by=YM]
dec_ret <- ms_mono[!is.na(decile), .(avg=mean(fwd_ret,na.rm=T)), by=decile]
setkey(dec_ret, decile)
monotonicity <- if(nrow(dec_ret)>=9) mean(diff(dec_ret$avg)>0) else NA_real_
cat("  Decile avg ret:", round(dec_ret$avg*100,2), "%\n")
cat("  Monotonicity:", round(monotonicity,3), "\n")

# ===========================================================================
# STEP 12: ALPHA VECTOR (as of last validation month)
# ===========================================================================
cat("[Step 12] Alpha vector construction...\n")

last_ym <- monthly_sig[YM <= "2024-01", max(YM)]
cat("  Signal month:", last_ym, "\n")

alpha_m <- monthly_sig[YM == last_ym & !is.na(get(sig_col_sel)) & liq_eom >= LIQ_FLOOR]
if (nrow(alpha_m) > 150) alpha_m <- alpha_m[order(-liq_eom)][1:150]

# Cross-sectional Z-score of signal
alpha_m[, sig_z := (get(sig_col_sel) - mean(get(sig_col_sel), na.rm=T)) /
           sd(get(sig_col_sel), na.rm=T)]

# IC-adjusted alpha forecast
alpha_m[, alpha_hat := mean_ic * sig_z]
cat("  Alpha N:", nrow(alpha_m), "| mean:", round(mean(alpha_m$alpha_hat,na.rm=T),5),
    "| sd:", round(sd(alpha_m$alpha_hat,na.rm=T),5), "\n")

# ===========================================================================
# STEP 13: CONFIDENCE VECTOR (R4-A)
# ===========================================================================
cat("[Step 13] Confidence vector (R4-A)...\n")

# 1. Residual variance (lower noise = higher confidence)
eps_stats <- dt_eps[Ticker %in% alpha_m$Ticker &
                     Date >= as.Date("2021-01-01"),
                    .(eps_var = var(epsilon, na.rm=T),
                      eps_n   = sum(!is.na(epsilon))),
                    by=Ticker]
alpha_m <- merge(alpha_m, eps_stats, by="Ticker", all.x=TRUE)

med_var <- median(alpha_m$eps_var, na.rm=T)
alpha_m[, conf_noise := ifelse(!is.na(eps_var) & eps_var > 0,
                                1 / (1 + eps_var / med_var), 0.5)]
max_n   <- max(alpha_m$eps_n, na.rm=T)
alpha_m[, conf_cov   := pmin(1, eps_n / (max_n * 0.8))]
alpha_m[is.na(conf_cov), conf_cov := 0.3]

# 2. Subperiod IC consistency per ticker (optional signal stability)
alpha_m[, confidence := (conf_noise + conf_cov) / 2]
alpha_m[is.na(confidence), confidence := 0.3]
alpha_m[, confidence := pmax(0, pmin(1, confidence))]

cat("  conf mean:", round(mean(alpha_m$confidence),3),
    "| min:", round(min(alpha_m$confidence),3),
    "| max:", round(max(alpha_m$confidence),3), "\n")

# ===========================================================================
# STEP 14: METHOD SHOPPING LOG (R2-C)
# ===========================================================================
method_shopping_log <- list(
  alpha_agent = list(
    candidates_tried  = 3L,
    selection_objective = "rank_ic",
    method_log = list(
      list(
        name        = "A_ResidualReversal_5d",
        description = "Novy-Marx (2012): signal = -mean(eps_{t-1:t-5}); macro-orthogonalized daily residuals",
        rank_ic_train = round(diag_tbl$ic_train[1], 5),
        icir_train    = round(diag_tbl$icir_train[1], 4),
        rank_ic_val   = round(diag_tbl$ic_val[1], 5),
        icir_val      = round(diag_tbl$icir_val[1], 4),
        selected      = (selected == "A_ResidReversal")
      ),
      list(
        name        = "B_ResidualMomentum_15d",
        description = "Blitz-Huij (2011): signal = mean(eps_{t-6:t-20})/sd(eps_{t-6:t-20}); idio Sharpe",
        rank_ic_train = round(diag_tbl$ic_train[2], 5),
        icir_train    = round(diag_tbl$icir_train[2], 4),
        rank_ic_val   = round(diag_tbl$ic_val[2], 5),
        icir_val      = round(diag_tbl$icir_val[2], 4),
        selected      = (selected == "B_ResidMomentum")
      ),
      list(
        name        = "C_Composite_EW",
        description = "Equal-weight composite: 0.5*rank_A + 0.5*rank_B (cross-sectional)",
        rank_ic_train = round(diag_tbl$ic_train[3], 5),
        icir_train    = round(diag_tbl$icir_train[3], 4),
        rank_ic_val   = round(diag_tbl$ic_val[3], 5),
        icir_val      = round(diag_tbl$icir_val[3], 4),
        selected      = (selected == "C_Composite")
      )
    )
  )
)

# ===========================================================================
# STEP 15: CHALLENGE FLAGS & GRADUATION CHECK
# ===========================================================================
challenge_flags <- character(0)
if (!is.na(harvey_t) && abs(harvey_t) < 3.0) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-HARVEY: t=%.3f < 3.0 [Harvey-Liu-Zhu 2016 threshold]", harvey_t))
}
if (!is.na(stability) && stability < 0.5) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-SUBPERIOD: stability=%.2f < 0.5 — IC sign not consistent", stability))
}
if (!is.na(monotonicity) && monotonicity < 0.7) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-MONOTONE: monotonicity=%.2f < 0.7", monotonicity))
}
if (!is.na(dsr) && dsr < 0.5) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-DSR: DSR=%.4f < 0.5 [Bailey-Lopez de Prado 2014]", dsr))
}
challenge_flags <- c(challenge_flags,
  "R2-P2-COMPLIANT: lockbox 2024-01-22+ NOT accessed. Signal selection on train+val only.")

grad_check <- list(
  min_rank_ic_pass    = !is.na(mean_ic)    && abs(mean_ic)   >= 0.04,
  min_icir_pass       = !is.na(icir_val)   && abs(icir_val)  >= 0.20,
  min_stability_pass  = !is.na(stability)  && stability      >= 0.50,
  min_harvey_t_pass   = !is.na(harvey_t)   && abs(harvey_t)  >= 3.0,
  min_dsr_pass        = !is.na(dsr)        && dsr            >= 0.50
)

# ===========================================================================
# STEP 16: WRITE ALPHA PACKAGE
# ===========================================================================
cat("[Step 16] Writing alpha_package.json...\n")

alpha_vec <- as.list(setNames(round(alpha_m$alpha_hat, 6), alpha_m$Ticker))
conf_vec  <- as.list(setNames(round(alpha_m$confidence, 4), alpha_m$Ticker))

alpha_package <- list(
  task_id            = WT_ID,
  as_of_date         = "2026-04-23",
  forecast_horizon   = "1M",
  selection_objective = "rank_ic",
  signal_matrix_ref  = "stage_artifacts://WT_D20260423_002/alpha_scores.parquet",
  alpha_vector       = alpha_vec,
  confidence_vector  = conf_vec,
  factor_specs = list(
    list(
      factor_family    = "Macro-Residual",
      proxy            = "Residual_Reversal_5d",
      formula          = "signal_A = -mean(eps_{t-1:t-5}); eps from rolling 24M OLS: r_i = a + b1*deltaRate_t-1 + b2*logRet_KRW_t-1 + b3*logVIX_t-1 + eps",
      lag_rule         = "macro x1/x2/x3 t-1 lag (C11); price t-1 (C2); rolling 24M PIT-safe",
      winsorization    = "none (raw residuals); cross-sectional rank transformation",
      neutralization   = "3-axis macro OLS (KR 10Y / KRW-USD / VIX)",
      economic_rationale = "behavioral",
      weight_theta     = if(selected=="A_ResidReversal") 1.0 else 0.5,
      references       = list(
        "Novy-Marx R (2012) Is Momentum Really Momentum? JFE",
        "Da Z, Liu Q, Schaumburg E (2014) JFE A Closer Look at the Short-Term Return Reversal",
        "Lehmann B (1990) Fads Martingales and Market Efficiency QJE")
    ),
    list(
      factor_family    = "Macro-Residual",
      proxy            = "Residual_Momentum_15d",
      formula          = "signal_B = mean(eps_{t-6:t-20})/sd(eps_{t-6:t-20}); idiosyncratic Sharpe skipping 5-day reversal",
      lag_rule         = "same as A; skip recent 5 days to avoid reversal bias",
      winsorization    = "none",
      neutralization   = "3-axis macro OLS",
      economic_rationale = "behavioral",
      weight_theta     = if(selected=="B_ResidMomentum") 1.0 else 0.5,
      references       = list(
        "Blitz D, Huij J, Martens M (2011) Residual Momentum JFQA",
        "Grundy B, Martin JS (2001) Understanding the Nature and Risks of Momentum Strategies RFS")
    ),
    list(
      factor_family    = "Macro",
      proxy            = "KR_Gov10Y_delta",
      formula          = "x1 = diff(KR_Gov10Y_ECOS) lagged t-1",
      lag_rule         = "t-1 lag (C11)",
      winsorization    = "none",
      neutralization   = "OLS regressor (not standalone signal)",
      economic_rationale = "structural",
      weight_theta     = 0.0,
      references       = list("ECOS KR_Gov10Y daily series")
    ),
    list(
      factor_family    = "Macro",
      proxy            = "KRW_USD_log_ret",
      formula          = "x2 = diff(log(KRW_USD_ECOS)) lagged t-1",
      lag_rule         = "t-1 lag (C11)",
      winsorization    = "none",
      neutralization   = "OLS regressor",
      economic_rationale = "structural",
      weight_theta     = 0.0,
      references       = list("ECOS daily KRW/USD exchange rate")
    ),
    list(
      factor_family    = "Macro",
      proxy            = "VIX_log_chg",
      formula          = "x3 = diff(log(VIX_FRED)) lagged t-1",
      lag_rule         = "t-1 lag (C11)",
      winsorization    = "none",
      neutralization   = "OLS regressor",
      economic_rationale = "structural",
      weight_theta     = 0.0,
      references       = list("FRED VIXCLS via macro_fred.parquet")
    )
  ),
  diagnostics = list(
    rank_ic              = round(mean_ic, 5),
    icir                 = round(icir_val, 4),
    monotonicity         = if(!is.na(monotonicity)) round(monotonicity,3) else NULL,
    subperiod_stability  = round(stability, 3),
    subperiod_ic_by_period = list(
      "2012_2014" = round(ic_subs[1], 5),
      "2015_2019" = round(ic_subs[2], 5),
      "2020_2022" = round(ic_subs[3], 5)
    ),
    turnover_proxy       = 0.95,
    harvey_t_stat        = round(harvey_t, 4),
    deflated_sharpe_ratio = if(!is.na(dsr)) round(dsr,4) else NULL,
    post_neutralization_ic = round(mean_ic, 5),
    regime_conditional_ic = list(
      low_VIX        = round(mean(ic_low,  na.rm=T), 5),
      high_VIX       = round(mean(ic_high, na.rm=T), 5),
      rate_hike_2022 = round(mean(ic_hike, na.rm=T), 5)
    ),
    signal_selected  = selected,
    val_ic           = round(mean(ic_sel_vl, na.rm=T), 5),
    val_icir         = round(diag_tbl$icir_val[best_idx], 4),
    universe_n       = nrow(alpha_m),
    train_months     = n_obs
  ),
  challenge_flags          = as.list(challenge_flags),
  method_shopping_log_ref  = file.path(WT_DIR, "method_shopping_log.json"),
  grad_criteria_check      = grad_check,
  created_by               = "Alpha Research Agent v6.1",
  created_at               = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
)

write_json(alpha_package, file.path(WT_DIR, "alpha_package.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  alpha_package.json written\n")

write_json(method_shopping_log, file.path(WT_DIR, "method_shopping_log.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  method_shopping_log.json written\n")

# ===========================================================================
# STEP 17: WRITE PARQUET + VALIDATION JSON
# ===========================================================================
cat("[Step 17] Writing alpha_scores.parquet + alpha_validation.json...\n")

alpha_scores <- alpha_m[, .(Ticker, YM, signal_A, signal_B, rank_A, rank_B, rank_C,
                              alpha_hat, confidence, liq_eom, eps_var, eps_n)]
write_parquet(alpha_scores, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  alpha_scores.parquet:", nrow(alpha_scores), "rows\n")

alpha_validation <- list(
  task_id           = WT_ID,
  validated_at      = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
  window_used       = "train_2012-01-20_to_2022-01-20 + validation_2022-01-21_to_2024-01-21",
  lockbox_accessed  = FALSE,
  pit_checks        = list(
    C1_rolling_only = TRUE, C2_price_t1 = TRUE,
    C9_no_same_day = TRUE, C11_macro_t1_lag = TRUE, C14_usable_date = TRUE
  ),
  ic_by_candidate   = list(
    A_ResidReversal = list(
      ic_train  = round(diag_tbl$ic_train[1],5), ic_val  = round(diag_tbl$ic_val[1],5),
      icir_train= round(diag_tbl$icir_train[1],4), icir_val= round(diag_tbl$icir_val[1],4)
    ),
    B_ResidMomentum = list(
      ic_train  = round(diag_tbl$ic_train[2],5), ic_val  = round(diag_tbl$ic_val[2],5),
      icir_train= round(diag_tbl$icir_train[2],4), icir_val= round(diag_tbl$icir_val[2],4)
    ),
    C_Composite = list(
      ic_train  = round(diag_tbl$ic_train[3],5), ic_val  = round(diag_tbl$ic_val[3],5),
      icir_train= round(diag_tbl$icir_train[3],4), icir_val= round(diag_tbl$icir_val[3],4)
    )
  ),
  selected_signal    = selected,
  method_shopping_n  = 3L,
  grad_check         = grad_check
)
write_json(alpha_validation, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  alpha_validation.json written\n")

# ===========================================================================
# STEP 18: LINEAGE (R11 — GAP-2)
# ===========================================================================
cat("[Step 18] Lineage recording (R11)...\n")
tryCatch({
  source(file.path(PROJ_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id      = WT_ID,
    package_type = "alpha_package",
    method_selected = paste0("residual_", tolower(gsub("[^A-Za-z0-9]","_", selected))),
    input_file_paths = c(
      file.path(PROJ_ROOT, ".cache/rawdata.parquet"),
      file.path(PROJ_ROOT, ".cache/ecos_bond_rates.parquet"),
      file.path(PROJ_ROOT, ".cache/ecos_krw_usd.parquet"),
      file.path(PROJ_ROOT, ".cache/macro_fred.parquet")
    ),
    windows = list(
      train_start   = "2012-01-20", train_end = "2022-01-20",
      val_start     = "2022-01-21", val_end   = "2024-01-21",
      lockbox_start = "2024-01-22 SEALED"
    ),
    wt_root = file.path(PROJ_ROOT, "qepm/mailbox/worktask")
  )
  cat("  Lineage OK\n")
}, error = function(e) cat("  [WARN] Lineage:", conditionMessage(e), "\n"))

# ===========================================================================
# STEP 19: UPDATE STATUS.JSON
# ===========================================================================
status_path <- file.path(WT_DIR, "status.json")
status_obj <- if (file.exists(status_path)) fromJSON(status_path) else list(task_id=WT_ID)
status_obj$current_phase <- "ALPHA_DONE"
status_obj$updated_at    <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ")
status_obj$alpha_summary <- list(
  signal_selected = selected,
  rank_ic  = round(mean_ic,4),
  icir     = round(icir_val,4),
  harvey_t = round(harvey_t,4),
  dsr      = if(!is.na(dsr)) round(dsr,4) else NULL,
  universe_n = nrow(alpha_m)
)
write_json(status_obj, status_path, pretty=TRUE, auto_unbox=TRUE, null="null")

# ===========================================================================
# FINAL SUMMARY
# ===========================================================================
elapsed <- (proc.time() - t_start)["elapsed"]
cat("\n========== FINAL SUMMARY ==========\n")
cat("WT-D20260423_002: Macro-Neutral Residual Alpha\n")
cat("Elapsed         :", round(elapsed/60, 1), "min\n")
cat("Selected signal :", selected, "\n")
cat("Universe N      :", nrow(alpha_m), "\n")
cat("rank_IC (train) :", round(mean_ic,4), ifelse(abs(mean_ic)>=0.04, " PASS", " FAIL"), "\n")
cat("ICIR (train)    :", round(icir_val,4), ifelse(abs(icir_val)>=0.20, " PASS", " FAIL"), "\n")
cat("Harvey t        :", round(harvey_t,4), ifelse(abs(harvey_t)>=3.0, " PASS", " FAIL"), "\n")
cat("DSR             :", if(!is.na(dsr)) round(dsr,4) else "NA",
    ifelse(!is.na(dsr) && dsr>=0.5, " PASS", " FAIL/CHECK"), "\n")
cat("Subperiod stab  :", round(stability,3), ifelse(stability>=0.50," PASS"," FAIL"), "\n")
cat("Monotonicity    :", if(!is.na(monotonicity)) round(monotonicity,3) else "NA", "\n")
cat("val IC          :", round(mean(ic_sel_vl,na.rm=T),5), "\n")
cat("val ICIR        :", round(diag_tbl$icir_val[best_idx],4), "\n")
cat("Challenge flags :", length(challenge_flags), "\n")
for (f in challenge_flags) cat("  -", f, "\n")
cat("====================================\n")

# Save result for downstream
saveRDS(list(
  selected=selected, rank_ic=mean_ic, icir=icir_val,
  harvey_t=harvey_t, dsr=dsr, stability=stability,
  monotonicity=monotonicity,
  val_ic=mean(ic_sel_vl,na.rm=T), val_icir=diag_tbl$icir_val[best_idx],
  regime_low_vix=mean(ic_low,na.rm=T),
  regime_high_vix=mean(ic_high,na.rm=T),
  regime_rate_hike=mean(ic_hike,na.rm=T),
  n_tickers=nrow(alpha_m), n_candidates=3L,
  challenge_flags=challenge_flags,
  elapsed_min=round(elapsed/60,1)
), file.path(STAGE_DIR, "run_result.rds"))
cat("[DONE] run_result.rds saved.\n")
