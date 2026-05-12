#==============================================================================
# WT-D20260508_006 — IPCA Conditional Latent Factor (KR)
#
# Pipeline:
#   1. Load monthly factor DB (288 char) for date range
#   2. Universe filter: KOSPI200 ∪ KOSDAQ150 + liquidity 2e8 KRW + t-1 PIT
#   3. Forward returns (1M, t to t+1)
#   4. Characteristic selection (limit ≤ 5 to satisfy method-shopping cap)
#   5. Train IPCA on train/validation window (lockbox isolation)
#   6. Diagnostics: ICIR, Harvey-t, decile monotonicity, subperiod, Bailey-LdP DSR
#   7. Forward 2026-05 alpha prediction
#   8. Orthogonality vs Hybrid 70/15/15 (target cor < 0.25)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(future)
  library(future.apply)
})

WT_ID <- "WT-D20260508_006"
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
OUT_STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
dir.create(OUT_WT_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(PROJECT_ROOT, "04_Research/strategies/WT_D20260508_006_IPCA/ipca_core.R"))

#==============================================================================
# 1. Configuration (자율 선택)
#==============================================================================

CONFIG <- list(
  # Train window (PIT-safe, lockbox excluded)
  train_start  = "2010-01-01",
  train_end    = "2022-12-31",   # ~13y train
  validation_start = "2023-01-01",
  validation_end   = "2024-12-31",  # 2y val
  # Lockbox: 2025-01-01 ~ 2026-04-30 (forward 2026-05 prediction only)
  lockbox_start = "2025-01-01",
  forward_signal_date = "2026-04-30",  # use 2026-04 char → predict 2026-05 ret

  # Universe filter
  liquidity_floor_won_20d = 2e8,
  universe_label = "KR_top342",   # KOSPI200 ∪ KOSDAQ150

  # IPCA hyperparams (자율: K=4 — KPS 2019 K=6 영문 36 char baseline; KR 5 char → K=4)
  K = 4L,
  unrestricted = TRUE,            # need Γ_α for alpha prediction
  max_iter = 100L,
  tol = 1e-6,

  # Characteristic selection (method-shopping cap = 5)
  # KR Factor DB 288 → select 5 well-known cross-section anomalies
  characteristics = c(
    "V01_BM",       # Value: Book/Market (Fama-French 1993)
    "M01_Mom_12_1", # Momentum: 12m-1m return (Jegadeesh-Titman 1993)
    "Q01_GPA",      # Quality: Gross profit / asset (Novy-Marx 2013)
    "S01_Size",     # Size (Banz 1981 / Fama-French 1992)
    "L02_Turnover"  # Liquidity: turnover
  ),
  min_n_per_period = 30L
)

cat("[ipca-kr] config:\n")
print(CONFIG)

#==============================================================================
# 2. Load monthly returns (build forward returns)
#==============================================================================

cat("\n[1/8] Loading rawdata for forward returns ...\n")

raw_path <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
raw <- as.data.table(read_parquet(raw_path))
raw <- raw[Date >= as.Date(CONFIG$train_start) - 60 &
           Date <= as.Date("2026-05-31")]

# Monthly returns (use month-end Close, drop missing/admin/halt)
raw[, YearMonth := format(Date, "%Y%m")]
raw <- raw[!is.na(Close) & is.finite(Close) & is.finite(Vol) & Vol > 0]

# Month-end snapshot (last trading day per month per ticker)
me_snap <- raw[, .SD[which.max(Date)], by = .(Ticker, YearMonth),
               .SDcols = c("Date", "Close", "Vol", "Size", "Sector",
                           "K200", "KQ150", "AdminStock", "TradingHalt", "BM_Ret")]
setorder(me_snap, Ticker, Date)

# 20d ADV (won) — proxy = last 20 trading days mean(Close × Vol)
raw_won <- copy(raw)
raw_won[, won := Close * Vol]
raw_won[, adv20_won := frollmean(won, 20L), by = Ticker]
adv20_me <- raw_won[, .SD[which.max(Date)],
                    by = .(Ticker, YearMonth), .SDcols = c("Date", "adv20_won")]
me_snap <- merge(me_snap, adv20_me[, .(Ticker, YearMonth, adv20_won)],
                 by = c("Ticker", "YearMonth"), all.x = TRUE)

# Forward 1M return (Close[t+1] / Close[t] - 1)
me_snap[, Close_next := shift(Close, -1L, type = "lag"), by = Ticker]
me_snap[, ret_fwd1m := Close_next / Close - 1]
# Winsorize forward returns ±20% to limit outlier dominance
me_snap[, ret_fwd1m := pmax(pmin(ret_fwd1m, 0.40), -0.40)]

cat("[1/8] me_snap:", nrow(me_snap), "rows;",
    "ticker count:", uniqueN(me_snap$Ticker), "\n")

#==============================================================================
# 3. Universe filter (PIT t-1)
#==============================================================================

cat("\n[2/8] Universe filter ...\n")

# Universe at month-end t: must be K200 OR KQ150 ∈ {1, TRUE} as-of t
# AND adv20_won >= 2e8 (PIT - using ADV20 ending t, signal applied t+1 already)
# AND not Admin/Halt
me_snap[, in_universe := (
    ((K200 == 1) %in% TRUE | (KQ150 == 1) %in% TRUE) &
    !is.na(adv20_won) &
    adv20_won >= CONFIG$liquidity_floor_won_20d &
    (is.na(AdminStock) | AdminStock != 1) &
    (is.na(TradingHalt) | TradingHalt != 1)
)]

# Show universe sizes per month
univ_sizes <- me_snap[in_universe == TRUE, .N, by = YearMonth]
cat("[2/8] universe sizes by month (last 12):\n")
print(tail(univ_sizes[order(YearMonth)], 12))

#==============================================================================
# 4. Build characteristic panels (PIT-safe via load_month_factors)
#==============================================================================

cat("\n[3/8] Building characteristic panels via load_month_factors() ...\n")

# Iterate month-ends in train + val + lockbox windows
all_yms <- sort(unique(me_snap$YearMonth))
all_yms <- all_yms[all_yms >= format(as.Date(CONFIG$train_start), "%Y%m") &
                   all_yms <= format(as.Date(CONFIG$forward_signal_date), "%Y%m")]
cat("[3/8] periods to load:", length(all_yms), "\n")

# Helper: for each month-end, load factors via connector and pivot to wide
load_one_month <- function(ym) {
  d <- as.Date(paste0(substr(ym,1,4), "-", substr(ym,5,6), "-01"))
  d_eom <- seq(d, length.out = 2, by = "month")[2] - 1
  # use month-end as sig_date
  sig_d <- d_eom
  ft <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) NULL
  )
  if (is.null(ft) || nrow(ft) == 0) return(NULL)
  setDT(ft)
  # Filter to selected characteristics
  ft <- ft[Factor_Name %in% CONFIG$characteristics]
  if (nrow(ft) == 0L) return(NULL)
  # Pivot wide: Ticker × Factor → Z_Score_Aligned
  wide <- dcast(ft, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  wide[, YearMonth := ym]
  wide
}

t0 <- Sys.time()
plan(multisession, workers = min(8L, parallel::detectCores() - 1L))
chunks <- future_lapply(all_yms, load_one_month)
plan(sequential)
chunks <- chunks[!vapply(chunks, is.null, logical(1))]
char_panel <- rbindlist(chunks, fill = TRUE, use.names = TRUE)
cat("[3/8] char_panel built in", round(as.numeric(Sys.time() - t0, units = "secs"), 1),
    "s — rows:", nrow(char_panel), "\n")

# Coverage check per characteristic
for (ch in CONFIG$characteristics) {
  if (ch %in% names(char_panel)) {
    cov_pct <- mean(!is.na(char_panel[[ch]]))
    cat(sprintf("  %-20s coverage=%.2f\n", ch, cov_pct))
  } else {
    cat("  ", ch, " NOT IN PANEL — exclude\n")
  }
}

# Drop chars not in panel
present_chars <- intersect(CONFIG$characteristics, names(char_panel))
if (length(present_chars) < 3L) {
  stop("[ipca-kr] insufficient characteristics — need >= 3, got ", length(present_chars))
}

#==============================================================================
# 5. Merge characteristics + universe + forward returns
#==============================================================================

cat("\n[4/8] Merge characteristics + universe + forward returns ...\n")

panel <- merge(
  me_snap[in_universe == TRUE, .(Ticker, YearMonth, Date, ret_fwd1m, Sector,
                                  Size, BM_Ret)],
  char_panel,
  by = c("Ticker", "YearMonth"),
  all.x = FALSE  # only stocks in both universe and factor DB
)

# Drop rows missing any characteristic OR ret_fwd1m
panel_full <- panel[complete.cases(panel[, ..present_chars]) & !is.na(ret_fwd1m)]
cat("[4/8] merged panel: full obs =", nrow(panel_full), " incl_lockbox\n")

# Add intercept (constant column = 1) — KPS 2019 always include
panel_full[, CONST := 1]
char_cols <- c("CONST", present_chars)
L_dim <- length(char_cols)
cat("[4/8] L (characteristics incl CONST) =", L_dim, "\n")

# ---- Cross-section standardization per period (KPS 2019 standard: rank then scale) ----
# Note: factor_db Z_Score_Aligned is already cross-sectionally Z-scored.
# CONST stays at 1. Other chars retained as-is (already Z-aligned).
# Re-z within universe at each period (since universe filter changes coverage)
for (ch in present_chars) {
  panel_full[, (ch) := scale(get(ch))[, 1], by = YearMonth]
  panel_full[is.na(get(ch)), (ch) := 0]
}

#==============================================================================
# 6. Split train / validation / lockbox
#==============================================================================

panel_full[, period_class := fcase(
  Date <= as.Date(CONFIG$train_end), "train",
  Date <= as.Date(CONFIG$validation_end), "validation",
  default = "lockbox"
)]

cat("\n[5/8] Period split:\n")
print(panel_full[, .N, by = period_class])

train_dt <- panel_full[period_class == "train"]
val_dt   <- panel_full[period_class == "validation"]
lock_dt  <- panel_full[period_class == "lockbox"]

# Build IPCA panels (per-period Z and R)
build_one <- function(dt) {
  dates <- sort(unique(dt$YearMonth))
  Z_list <- list(); R_list <- list(); ticker_list <- list()
  for (i in seq_along(dates)) {
    sub <- dt[YearMonth == dates[i]]
    if (nrow(sub) < CONFIG$min_n_per_period) next
    Z_list[[length(Z_list) + 1]] <- as.matrix(sub[, ..char_cols])
    R_list[[length(R_list) + 1]] <- sub$ret_fwd1m
    ticker_list[[length(ticker_list) + 1]] <- sub$Ticker
  }
  list(Z = Z_list, R = R_list, tickers = ticker_list,
       periods = dates[seq_len(length(Z_list))])
}

train_panels <- build_one(train_dt)
val_panels   <- build_one(val_dt)
lock_panels  <- build_one(lock_dt)

cat("[5/8] train periods:", length(train_panels$Z),
    " val periods:", length(val_panels$Z),
    " lockbox periods:", length(lock_panels$Z), "\n")

#==============================================================================
# 7. Fit IPCA (train), evaluate on validation
#==============================================================================

cat("\n[6/8] Fitting IPCA ALS K=", CONFIG$K, " unrestricted=", CONFIG$unrestricted, " ...\n",
    sep="")

t0 <- Sys.time()
fit <- ipca_fit(
  Z_list = train_panels$Z,
  R_list = train_panels$R,
  K = CONFIG$K,
  max_iter = CONFIG$max_iter,
  tol = CONFIG$tol,
  unrestricted = CONFIG$unrestricted,
  verbose = TRUE
)
elapsed <- round(as.numeric(Sys.time() - t0, units = "secs"), 1)
cat("[6/8] IPCA fit elapsed:", elapsed, "s\n")

train_r2 <- ipca_r2(fit, train_panels$Z, train_panels$R)
cat("[6/8] train R2:", round(train_r2$total_r2, 4), "\n")

# Out-of-sample on validation: re-estimate F via projection, hold Γ fixed
# F_t = (Γ' Z_t' Z_t Γ)^{-1} Γ' Z_t' R_t — but for OOS prediction we use Γ_α only
# (alpha-only mode). Validation R2 = correlation of Γ_α-prediction with realized
val_alphas <- list()
val_returns <- list()
for (i in seq_along(val_panels$Z)) {
  Z_t <- val_panels$Z[[i]]
  R_t <- val_panels$R[[i]]
  alpha_pred <- as.numeric(Z_t %*% fit$Gamma_alpha)
  val_alphas[[i]] <- alpha_pred
  val_returns[[i]] <- R_t
}

# Cross-section IC per validation period
val_ic <- vapply(seq_along(val_alphas), function(i) {
  if (length(val_alphas[[i]]) < 10) return(NA_real_)
  cor(val_alphas[[i]], val_returns[[i]], method = "spearman")
}, numeric(1))
val_ic <- val_ic[!is.na(val_ic)]
cat("[6/8] validation periods with IC:", length(val_ic),
    " mean IC:", round(mean(val_ic), 4),
    " ICIR:", round(mean(val_ic) / sd(val_ic), 4), "\n")

#==============================================================================
# 8. Diagnostics: in-sample IC + subperiod stability + Harvey-t + Bailey-LdP DSR
#==============================================================================

cat("\n[7/8] Computing diagnostics ...\n")

# -- In-sample IC per train+val period (combined for diagnostics)
all_panels <- list(
  Z = c(train_panels$Z, val_panels$Z),
  R = c(train_panels$R, val_panels$R),
  periods = c(train_panels$periods, val_panels$periods)
)

ic_per_period <- vapply(seq_along(all_panels$Z), function(i) {
  Z_t <- all_panels$Z[[i]]; R_t <- all_panels$R[[i]]
  if (length(R_t) < 10) return(NA_real_)
  alpha_pred <- as.numeric(Z_t %*% fit$Gamma_alpha)
  cor(alpha_pred, R_t, method = "spearman")
}, numeric(1))

ic_dt <- data.table(YearMonth = all_panels$periods, IC = ic_per_period)
ic_dt <- ic_dt[!is.na(IC)]
ic_dt[, year := as.integer(substr(YearMonth, 1, 4))]

mean_ic <- mean(ic_dt$IC, na.rm = TRUE)
sd_ic   <- sd(ic_dt$IC,   na.rm = TRUE)
icir    <- mean_ic / sd_ic
ic_t    <- mean_ic / (sd_ic / sqrt(nrow(ic_dt)))

# Harvey-t = Newey-West adjusted t-stat with lag floor sqrt(T)
nw_lag <- floor(sqrt(nrow(ic_dt)))
ic_centered <- ic_dt$IC - mean_ic
gamma0 <- mean(ic_centered^2)
nw_var <- gamma0
for (l in seq_len(nw_lag)) {
  w <- 1 - l / (nw_lag + 1)
  gl <- mean(ic_centered[(l+1):length(ic_centered)] * ic_centered[1:(length(ic_centered)-l)])
  nw_var <- nw_var + 2 * w * gl
}
harvey_t <- mean_ic / sqrt(nw_var / nrow(ic_dt))

cat("[7/8] mean_ic:", round(mean_ic, 4),
    " ICIR:", round(icir, 4),
    " harvey_t (NW):", round(harvey_t, 4),
    " periods T:", nrow(ic_dt), "\n")

# Subperiod stability
ic_dt[, subperiod := fcase(
  year <= 2014, "2010_2014",
  year <= 2019, "2015_2019",
  default = "2020_2024"
)]
sub_ic <- ic_dt[, .(mean_ic = mean(IC), n = .N), by = subperiod]
cat("[7/8] subperiod IC:\n"); print(sub_ic)
subperiod_stability <- min(sign(sub_ic$mean_ic) * sub_ic$mean_ic) / max(abs(sub_ic$mean_ic))
# fraction of subperiods with positive IC + std-of-mean ratio
sub_pos_frac <- mean(sub_ic$mean_ic > 0)
sub_stability_metric <- sub_pos_frac * (1 - sd(sub_ic$mean_ic) / max(abs(mean(sub_ic$mean_ic)), 1e-6))
sub_stability_metric <- max(min(sub_stability_metric, 1), 0)
cat("[7/8] subperiod_stability:", round(sub_stability_metric, 3),
    " positive_frac:", round(sub_pos_frac, 2), "\n")

# Decile monotonicity
mono_per_period <- vapply(seq_along(all_panels$Z), function(i) {
  Z_t <- all_panels$Z[[i]]; R_t <- all_panels$R[[i]]
  if (length(R_t) < 30) return(NA_real_)
  alpha_pred <- as.numeric(Z_t %*% fit$Gamma_alpha)
  q <- cut(alpha_pred, breaks = quantile(alpha_pred, probs = seq(0,1,0.1), na.rm=TRUE),
           include.lowest = TRUE, labels = 1:10)
  decile_ret <- tapply(R_t, q, mean)
  if (length(decile_ret) < 10 || any(is.na(decile_ret))) return(NA_real_)
  cor(seq(1,10), as.numeric(decile_ret), method = "spearman")
}, numeric(1))
mono_per_period <- mono_per_period[!is.na(mono_per_period)]
mean_mono <- mean(mono_per_period, na.rm = TRUE)
cat("[7/8] decile monotonicity (rank cor d1..d10 vs return):",
    round(mean_mono, 3), "\n")

# Long-short (decile 10 - decile 1) monthly returns
ls_returns <- vapply(seq_along(all_panels$Z), function(i) {
  Z_t <- all_panels$Z[[i]]; R_t <- all_panels$R[[i]]
  if (length(R_t) < 30) return(NA_real_)
  alpha_pred <- as.numeric(Z_t %*% fit$Gamma_alpha)
  q <- cut(alpha_pred, breaks = quantile(alpha_pred, probs = seq(0,1,0.1), na.rm=TRUE),
           include.lowest = TRUE, labels = 1:10)
  d_ret <- tapply(R_t, q, mean)
  if (length(d_ret) < 10) return(NA_real_)
  d_ret[10] - d_ret[1]
}, numeric(1))
ls_returns <- ls_returns[!is.na(ls_returns)]
ls_mean <- mean(ls_returns)
ls_sd   <- sd(ls_returns)
ls_sr   <- ls_mean / ls_sd * sqrt(12)  # annualized

# Bailey-Lopez de Prado DSR
# DSR = ((SR - SR_0) * sqrt(T-1)) / sqrt(1 - γ3*SR + (γ4-1)/4 * SR^2)
# SR_0 = E[max{SR}] for n_trials Sharpe ratios under null. Approx
# SR_0 = sqrt(2*log(n_trials))/sqrt(T) (standard)
# Here n_trials = candidates_tried (5 per method-shopping log)
n_trials <- 5L
T_obs <- length(ls_returns)
SR_obs <- ls_mean / ls_sd  # non-annualized monthly Sharpe
# Skewness, kurtosis (excess) of LS return series
m3 <- mean((ls_returns - ls_mean)^3) / ls_sd^3
m4 <- mean((ls_returns - ls_mean)^4) / ls_sd^4
gamma3 <- m3
gamma4 <- m4 - 3
SR_0 <- sqrt(2 * log(n_trials)) / sqrt(T_obs)
denom <- sqrt(1 - gamma3 * SR_obs + (gamma4) / 4 * SR_obs^2)
dsr <- pnorm((SR_obs - SR_0) * sqrt(T_obs - 1) / denom)
cat("[7/8] LS spread monthly mean=", round(ls_mean*100,3), "% sd=",
    round(ls_sd*100,3), "% annualized SR=", round(ls_sr,3), "\n", sep="")
cat("[7/8] Bailey-LdP DSR (n_trials=", n_trials, " T=", T_obs, "): ",
    round(dsr, 3), "\n", sep="")

# Save IC time series
fwrite(ic_dt, file.path(OUT_STAGE_DIR, "ipca_ic_per_period.csv"))
fwrite(data.table(YearMonth = all_panels$periods[seq_along(ls_returns)],
                  ls_return = ls_returns),
       file.path(OUT_STAGE_DIR, "ipca_ls_returns.csv"))

#==============================================================================
# 8b. Lockbox honest OOS test (2025-01 ~ 2026-04)
#==============================================================================

cat("\n[7b] Lockbox honest OOS test (2025-01 ~ 2026-04, untouched during fit) ...\n")

lock_alphas <- list(); lock_returns <- list()
for (i in seq_along(lock_panels$Z)) {
  Z_t <- lock_panels$Z[[i]]
  R_t <- lock_panels$R[[i]]
  alpha_pred <- as.numeric(Z_t %*% fit$Gamma_alpha)
  lock_alphas[[i]] <- alpha_pred
  lock_returns[[i]] <- R_t
}

lock_ic <- vapply(seq_along(lock_alphas), function(i) {
  if (length(lock_alphas[[i]]) < 10) return(NA_real_)
  cor(lock_alphas[[i]], lock_returns[[i]], method = "spearman")
}, numeric(1))
lock_ic_clean <- lock_ic[!is.na(lock_ic)]
cat("[7b] lockbox periods:", length(lock_ic_clean),
    " mean IC:", round(mean(lock_ic_clean), 4),
    " ICIR:", round(mean(lock_ic_clean) / sd(lock_ic_clean), 4), "\n")

# Lockbox LS spread + Sharpe
lock_ls <- vapply(seq_along(lock_alphas), function(i) {
  Z_t <- lock_panels$Z[[i]]; R_t <- lock_panels$R[[i]]
  if (length(R_t) < 30) return(NA_real_)
  alpha_pred <- as.numeric(Z_t %*% fit$Gamma_alpha)
  q <- cut(alpha_pred, breaks = quantile(alpha_pred, probs = seq(0,1,0.1), na.rm=TRUE),
           include.lowest = TRUE, labels = 1:10)
  d_ret <- tapply(R_t, q, mean)
  if (length(d_ret) < 10) return(NA_real_)
  d_ret[10] - d_ret[1]
}, numeric(1))
lock_ls <- lock_ls[!is.na(lock_ls)]
lock_ls_sr <- if (length(lock_ls) > 1) mean(lock_ls)/sd(lock_ls)*sqrt(12) else NA_real_
cat("[7b] lockbox LS spread monthly mean:", round(mean(lock_ls)*100, 3), "% sd:",
    round(sd(lock_ls)*100, 3), "% annualized SR:", round(lock_ls_sr, 3), "\n")

# Lockbox decile monotonicity
lock_mono <- vapply(seq_along(lock_alphas), function(i) {
  Z_t <- lock_panels$Z[[i]]; R_t <- lock_panels$R[[i]]
  if (length(R_t) < 30) return(NA_real_)
  alpha_pred <- as.numeric(Z_t %*% fit$Gamma_alpha)
  q <- cut(alpha_pred, breaks = quantile(alpha_pred, probs = seq(0,1,0.1), na.rm=TRUE),
           include.lowest = TRUE, labels = 1:10)
  decile_ret <- tapply(R_t, q, mean)
  if (length(decile_ret) < 10 || any(is.na(decile_ret))) return(NA_real_)
  cor(seq(1,10), as.numeric(decile_ret), method = "spearman")
}, numeric(1))
lock_mono <- lock_mono[!is.na(lock_mono)]
cat("[7b] lockbox monotonicity:", round(mean(lock_mono, na.rm=TRUE), 3), "\n")

#==============================================================================
# 8c. Predictor lag-1 autocorrelation (PIT diagnostic)
#==============================================================================

cat("\n[7c] Predictor lag-1 autocor diagnostic ...\n")
predictor_autocor <- list()
for (ch in present_chars) {
  vals_per_ticker <- panel_full[, .(ac = if (.N >= 6) cor(get(ch)[1:(.N-1)], get(ch)[2:.N], use="complete.obs") else NA_real_),
                                by = Ticker]
  vals_per_ticker <- vals_per_ticker[!is.na(ac)]
  predictor_autocor[[ch]] <- list(
    median_ac1 = median(vals_per_ticker$ac),
    mean_ac1 = mean(vals_per_ticker$ac),
    pct_high_ac = mean(vals_per_ticker$ac > 0.95)  # >0.95 = stale signal
  )
  cat(sprintf("  %-15s median ac1=%.3f  pct(>0.95)=%.3f\n", ch,
              predictor_autocor[[ch]]$median_ac1,
              predictor_autocor[[ch]]$pct_high_ac))
}

#==============================================================================
# 9. Forward 2026-05 alpha prediction (using 2026-04 characteristics)
#==============================================================================

cat("\n[8/8] Forward 2026-05 prediction ...\n")

# Use latest available month-end factor data (2026-04)
fwd_ym <- format(as.Date(CONFIG$forward_signal_date), "%Y%m")
fwd_panel <- panel_full[YearMonth == fwd_ym]
cat("[8/8] forward universe size:", nrow(fwd_panel), "\n")

if (nrow(fwd_panel) == 0L) {
  # fall back to last available period in lockbox
  last_ym <- max(panel_full$YearMonth)
  cat("[8/8] WARN: no", fwd_ym, "data — using last available", last_ym, "\n")
  fwd_panel <- panel_full[YearMonth == last_ym]
}

Z_fwd <- as.matrix(fwd_panel[, ..char_cols])
alpha_fwd <- as.numeric(Z_fwd %*% fit$Gamma_alpha)
fwd_panel[, alpha_ipca := alpha_fwd]
# Confidence: based on cross-sectional rank stability + factor coverage
# Simple heuristic: |alpha_z| / max(|alpha_z|) bounded [0.3, 1]
alpha_z <- (alpha_fwd - mean(alpha_fwd)) / sd(alpha_fwd)
conf_raw <- pmin(abs(alpha_z) / 2, 1)  # Z=2σ → conf 1
fwd_panel[, confidence := pmax(pmin(conf_raw, 0.95), 0.30)]

#==============================================================================
# 10. Orthogonality vs Hybrid 70/15/15
#==============================================================================

cat("\n[orthogonality] vs reference cross-section alpha ...\n")

# Hybrid 70/15/15 (WT-P20260505_001) is ETF-level inheritance package, no cross-section alphas
# Use last cross-section alpha (WT-D20260508_004) as recent KR cross-section reference
ortho_result <- list(status = "not_evaluated", reason = "no reference alpha package found")

ref_paths <- list(
  hybrid = file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260505_001/alpha_package.json"),
  wt_004 = file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260508_004/alpha_package.json")
)

ortho_set <- list()
for (rname in names(ref_paths)) {
  rp <- ref_paths[[rname]]
  if (!file.exists(rp)) next
  ref <- fromJSON(rp)
  if (is.null(ref$alpha_vector) || length(ref$alpha_vector) == 0L) {
    ortho_set[[rname]] <- list(status = "no_alpha_vector_inherit_only_or_etf_universe")
    next
  }
  r_av <- ref$alpha_vector
  r_dt <- data.table(Ticker = names(r_av), ref_alpha = unlist(r_av))
  cmp <- merge(r_dt, fwd_panel[, .(Ticker, alpha_ipca)], by = "Ticker")
  if (nrow(cmp) < 30L) {
    ortho_set[[rname]] <- list(status = "insufficient_overlap", n_overlap = nrow(cmp))
    next
  }
  cor_p <- cor(cmp$ref_alpha, cmp$alpha_ipca, method = "pearson")
  cor_s <- cor(cmp$ref_alpha, cmp$alpha_ipca, method = "spearman")
  ortho_set[[rname]] <- list(
    status = "evaluated",
    n_overlap = nrow(cmp),
    cor_pearson = cor_p,
    cor_spearman = cor_s,
    target_threshold = 0.25,
    passes_orthogonality = abs(cor_p) < 0.25 && abs(cor_s) < 0.25
  )
  cat("[orthogonality:", rname, "] n=", nrow(cmp),
      " pearson=", round(cor_p, 4),
      " spearman=", round(cor_s, 4),
      " passes(<0.25)=", abs(cor_p) < 0.25 && abs(cor_s) < 0.25, "\n", sep="")
}

ortho_result <- ortho_set

#==============================================================================
# 11. Save artifacts
#==============================================================================

cat("\n[save] artifacts ...\n")

# alpha_scores.parquet
alpha_scores_dt <- fwd_panel[, .(Ticker, alpha_ipca, confidence)]
write_parquet(alpha_scores_dt, file.path(OUT_STAGE_DIR, "alpha_scores.parquet"))

# IPCA factor decomposition (latent F_t)
F_dt <- as.data.table(t(fit$F))
setnames(F_dt, paste0("F", seq_len(CONFIG$K)))
F_dt[, YearMonth := train_panels$periods[seq_len(nrow(F_dt))]]
write_parquet(F_dt, file.path(OUT_STAGE_DIR, "ipca_latent_factors.parquet"))

# Save factor specs (Γ_α + Γ_β rows for each characteristic)
factor_specs_list <- list()
for (k in seq_along(present_chars)) {
  ch <- present_chars[k]
  # Γ_β row (k+1 since CONST is row 1)
  row_idx <- which(char_cols == ch)
  gb_row <- fit$Gamma_beta[row_idx, ]
  ga_row <- fit$Gamma_alpha[row_idx, 1]
  factor_specs_list[[length(factor_specs_list) + 1]] <- list(
    factor_family = switch(ch,
      "V01_BM" = "Value",
      "M01_Mom_12_1" = "Momentum",
      "Q01_GPA" = "Quality",
      "S01_Size" = "Size",
      "L02_Turnover" = "Liquidity",
      "Other"),
    proxy = ch,
    formula = paste0("Z_Score_Aligned of ", ch, " (Factor DB v2.0 PIT-safe)"),
    lag_rule = "monthly t-1 sig_date (load_month_factors)",
    winsorization = "3std (Factor DB built-in)",
    neutralization = "cross-section z-score per period",
    economic_rationale = paste0(
      "KPS 2019 IPCA framework: characteristic acts as instrument for ",
      "latent factor exposure (Γ_β row) AND mispricing (Γ_α row). ",
      "Restricted-to-Unrestricted F-test discriminates risk-premium vs alpha."),
    weight_theta_alpha = ga_row,
    weight_theta_beta_K1 = gb_row[1],
    weight_theta_beta_K2 = gb_row[2],
    weight_theta_beta_K3 = if (length(gb_row) >= 3) gb_row[3] else NA_real_,
    weight_theta_beta_K4 = if (length(gb_row) >= 4) gb_row[4] else NA_real_,
    references = c("Kelly-Pruitt-Su 2019 JFE",
                   "Bryzgalova-Pelger-Zhu 2024 RFS")
  )
}

# Method shopping log
method_log <- list(
  candidates_tried = length(CONFIG$characteristics),
  selected = present_chars,
  method_log = lapply(CONFIG$characteristics, function(c) {
    list(name = c, in_panel = c %in% present_chars,
         selected = c %in% present_chars,
         rationale = "well-known KR cross-section anomaly + Factor DB coverage")
  }),
  parallel_exec = TRUE,
  n_workers = min(8L, parallel::detectCores() - 1L),
  rolling_seconds = round(elapsed, 1),
  rcpp_used = FALSE,
  rcpp_rationale = "ALS for L=6, K=4, T=156 not bottleneck (< 1 min). DSR is parametric."
)

# Save run summary
run_summary <- list(
  task_id = WT_ID,
  algo = "IPCA_ALS",
  reference = "Kelly-Pruitt-Su 2019 JFE",
  config = CONFIG,
  characteristics_used = present_chars,
  L_dim = L_dim,
  K = CONFIG$K,
  unrestricted = CONFIG$unrestricted,
  train_periods = length(train_panels$Z),
  validation_periods = length(val_panels$Z),
  iter_used = fit$iter_used,
  converged = fit$converged,
  diagnostics = list(
    train_R2 = train_r2$total_r2,
    mean_IC = mean_ic,
    ICIR = icir,
    Harvey_t_NW = harvey_t,
    NW_lag = nw_lag,
    n_periods = nrow(ic_dt),
    monotonicity = mean_mono,
    subperiod_stability = sub_stability_metric,
    subperiod_breakdown = as.list(sub_ic),
    LS_spread_monthly_mean = ls_mean,
    LS_spread_monthly_sd = ls_sd,
    LS_annualized_SR = ls_sr,
    Bailey_LdP_DSR = dsr,
    n_trials = n_trials,
    validation_mean_IC = mean(val_ic),
    validation_ICIR = mean(val_ic) / sd(val_ic),
    lockbox_mean_IC = mean(lock_ic_clean),
    lockbox_ICIR = mean(lock_ic_clean) / sd(lock_ic_clean),
    lockbox_n_periods = length(lock_ic_clean),
    lockbox_LS_annualized_SR = lock_ls_sr,
    lockbox_monotonicity = mean(lock_mono, na.rm=TRUE),
    predictor_autocor_lag1 = predictor_autocor
  ),
  orthogonality_vs_hybrid = ortho_result,
  forward_prediction = list(
    sig_date = CONFIG$forward_signal_date,
    horizon = "1M",
    n_stocks = nrow(fwd_panel),
    alpha_mean = mean(alpha_fwd),
    alpha_sd = sd(alpha_fwd),
    alpha_top5 = head(fwd_panel[order(-alpha_ipca), .(Ticker, alpha_ipca)], 5)
  ),
  factor_specs_summary = factor_specs_list,
  method_shopping_log = method_log,
  saved_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

write_json(run_summary, file.path(OUT_STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
saveRDS(fit, file.path(OUT_STAGE_DIR, "ipca_fit.rds"))

cat("\n[run_ipca_kr] DONE.\n")
cat("Saved:\n",
    "  ", file.path(OUT_STAGE_DIR, "alpha_scores.parquet"), "\n",
    "  ", file.path(OUT_STAGE_DIR, "ipca_latent_factors.parquet"), "\n",
    "  ", file.path(OUT_STAGE_DIR, "alpha_validation.json"), "\n",
    "  ", file.path(OUT_STAGE_DIR, "ipca_fit.rds"), "\n")
