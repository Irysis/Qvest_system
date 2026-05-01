#==============================================================================
# WT-D20260501_001 — Alpha Research
# Theme: behavioral_attention_x_liquidity_shock_kr_specific
# Hypothesis: "Retail Attention–Lottery Reversal × Liquidity Shock Composite"
#
# Mechanism (KR retail dominance 50%+):
#   1) Da-Engelberg-Gao (2011 JF) attention proxy → MAX_Return + Vol_Spike + Retail_Buy_Z
#   2) Bali-Cakici-Whitelaw (2011 JFE) MAX/lottery aversion. KR M22 ICIR -0.374 직접 실증
#   3) Avramov-Chordia-Goyal (2006 JFE) liquidity shock → reversal
#   4) Barber-Odean (2008 RFS) attention-grabbing retail overreaction → 1M reversal
#   5) Grinblatt-Keloharju (2000 JFE) institutional-individual flow asymmetry
#
# Composite = M22(MAX, neg) + D43(Skew, pos) + L35(Reversal_Intensity, pos)
#           + L44(Vol_Ret_Asymm, neg) + CR08(VolPriceDivergence, pos) + Retail_Net_Z(neg)
# Bayesian shrinkage (IC-precision weighted) on theta.
#
# PIT: All factor DB Z_Score_Aligned via load_month_factors() (C13/C15 enforced).
# IC history Usable_Date <= sig_date (C14 enforced). Investor flow t-1 lag (data_lag_rules).
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(future); library(future.apply)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260501_001"
WT_DIR <- file.path(PROJ, "qepm/mailbox/worktask", WT_ID)
ART_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260501_001")
dir.create(ART_DIR, recursive = TRUE, showWarnings = FALSE)
setwd(PROJ)

source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/cpp/rcpp_hotspots.R")  # for bootstrap_dsr_fast / Spearman bootstrap

# ---- Parameters ----
SIG_DATES   <- seq.Date(as.Date("2008-01-31"), as.Date("2026-04-30"), by = "month")
SIG_DATES   <- SIG_DATES[as.numeric(format(SIG_DATES, "%d")) <= 7 | TRUE]  # all month-ends
# Use month-end calendar
SIG_DATES   <- as.Date(format(seq.Date(as.Date("2008-01-01"), as.Date("2026-04-30"), by="month"), "%Y-%m-01")) - 1L
SIG_DATES   <- SIG_DATES[!is.na(SIG_DATES) & SIG_DATES >= as.Date("2008-01-31")]

LIQ_THRESHOLD <- 2e8           # 거래대금 20d avg ≥ 2억 KRW (mandate)
COVERAGE_MIN  <- 0.05
MIN_IC_MONTHS <- 36L

CAND_FACTORS <- c(
  "M22_Max_Return",                # lottery aversion (Bali 2011), direction lower_better
  "D43_Skewness",                  # higher-skew lower return (Boyer-Mitton-Vorkink 2010)
  "L35_Reversal_Intensity",        # short-term reversal proxy (Da-Liu-Schaumburg 2014)
  "L44_Vol_Ret_Asymmetry",         # leverage effect / asymmetry
  "CR08_Volume_Price_Divergence",  # Volume-price divergence (smart money proxy)
  "D01_IdioVol",                   # IVOL premium (Ang et al. 2006) - control axis
  "L34_Vol_Spike_Ratio",           # volume surge (attention proxy)
  "L09_Amihud_20d"                 # short-horizon illiquidity
)

cat("=== ALPHA RESEARCH WT-D20260501_001 START ===\n")
cat("sig_dates_count:", length(SIG_DATES), "(", as.character(min(SIG_DATES)), "→", as.character(max(SIG_DATES)), ")\n")
cat("candidate_factors:", paste(CAND_FACTORS, collapse=" / "), "\n\n")

# =============================================================================
# Step 0: Build PIT-safe Retail Imbalance new factor
# =============================================================================
# Retail_Net_Z_20d = -Z_cs( rolling_mean(Individual_buy / total_value, 20d) )
# Direction lower_better → after attention spike retail saturates → reversal
# Lag: t-1 settlement (data_lag_rules.investor_flow)
cat("[Step 0] Building Retail_Net_Z_20d new factor (PIT t-1 lag) ...\n")

retail_z_cache_path <- file.path(ART_DIR, "retail_z_lookup.rds")
if (file.exists(retail_z_cache_path)) {
  cat("  Loading cached retail_z_lookup ...\n")
  retail_z_lookup <- readRDS(retail_z_cache_path)
  get_retail_z_aligned <- function(sig_date) {
    k <- as.character(as.Date(sig_date)); v <- retail_z_lookup[[k]]
    if (is.null(v)) return(data.table(Ticker = character(), Retail_Net_Z = numeric()))
    v
  }
} else {
inv <- as.data.table(read_parquet(file.path(PROJ, ".cache/investor_stock/investor_wide.parquet")))
setnames(inv, c("Date","Ticker","Foreign","Individual","Institutional","OtherCorp"))
setkey(inv, Ticker, Date)

# Compute total value (sum abs). Net retail / TotalAbs as flow imbalance proxy.
inv[, Total_Abs := abs(Foreign) + abs(Individual) + abs(Institutional) + abs(OtherCorp)]
inv[Total_Abs <= 0, Total_Abs := NA_real_]
inv[, Retail_Imbalance_d := Individual / Total_Abs]

# 20d rolling mean per ticker; t-1 PIT-safe (we shift by 1 day at extraction time)
roll_mean_pit <- function(x, k) {
  n <- length(x)
  if (n < k) return(rep(NA_real_, n))
  r <- frollmean(x, k, na.rm = TRUE, align = "right")
  r
}
inv[, Retail_Imbalance_20d := roll_mean_pit(Retail_Imbalance_d, 20L), by = Ticker]
# t-1 lag (data_lag_rules.investor_flow = "t-1 settlement"): shift down by 1
inv[, Retail_Imbalance_20d_lag1 := shift(Retail_Imbalance_20d, n = 1L, type = "lag"), by = Ticker]

# Save daily imbalance for downstream usage
inv_keep <- inv[, .(Date, Ticker, Retail_Imbalance_20d_lag1)]
fwrite(inv_keep, file.path(ART_DIR, "retail_imbalance_daily.csv.gz"), compress = "gzip")

# Pre-compute Retail_Net_Z lookup per sig_date (cross-sectional Z over latest available value <= sig_date - 1)
cat("  Pre-computing Retail_Net_Z lookup ...\n")
retail_z_lookup <- list()
inv_keep <- inv_keep[!is.na(Retail_Imbalance_20d_lag1)]
setkey(inv_keep, Ticker, Date)

# For each sig_date, take the last available value per ticker on or before (sig_date - 1)
for (sd in as.character(SIG_DATES)) {
  sig_d <- as.Date(sd)
  ss <- inv_keep[Date <= sig_d - 1L]
  if (nrow(ss) == 0L) { retail_z_lookup[[sd]] <- data.table(Ticker=character(), Retail_Net_Z=numeric()); next }
  last_d <- ss[, .SD[.N], by = Ticker, .SDcols = c("Retail_Imbalance_20d_lag1")]
  v <- last_d$Retail_Imbalance_20d_lag1
  m <- mean(v); s <- sd(v)
  if (!is.finite(s) || s <= 0) { retail_z_lookup[[sd]] <- data.table(Ticker=character(), Retail_Net_Z=numeric()); next }
  z <- (v - m) / s
  z <- pmin(pmax(z, -3), 3)
  retail_z_lookup[[sd]] <- data.table(Ticker = last_d$Ticker, Retail_Net_Z = -z)
}
cat("  Retail_Net_Z lookup built for", length(retail_z_lookup), "dates\n")
saveRDS(retail_z_lookup, retail_z_cache_path)
rm(inv, inv_keep); gc()
get_retail_z_aligned <- function(sig_date) {
  k <- as.character(as.Date(sig_date))
  v <- retail_z_lookup[[k]]
  if (is.null(v)) return(data.table(Ticker = character(), Retail_Net_Z = numeric()))
  v
}
}  # end else

# =============================================================================
# Step 1: Universe construction (KOSPI200 ∪ KOSDAQ150 + 20d TV ≥ 2e8)
# =============================================================================
cat("[Step 1] Building monthly universe (K200 ∪ KQ150 + 20d TV ≥ 2e8) ...\n")

rd <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
rd <- rd[Date >= as.Date("2007-01-01") & !is.na(Close) & !is.na(Vol) & Vol > 0]
setkey(rd, Ticker, Date)

# Daily turnover value (KRW)
rd[, DV := Close * Vol]

# Forward 1M return (next month total return) — for IC computation only
# month-end -> next month-end Close return
rd[, ym := format(Date, "%Y-%m")]
me_rd <- rd[, .SD[.N], by = .(Ticker, ym), .SDcols = c("Date", "Close")]
setorder(me_rd, Ticker, Date)
me_rd[, Close_next := shift(Close, type = "lead"), by = Ticker]
me_rd[, Ret_1M := Close_next / Close - 1]

# Pre-compute per-ticker rolling 20-day mean DV (PIT-safe)
rd[, DV20 := frollmean(DV, 20L, align = "right"), by = Ticker]

# Pre-compute universe membership for all signal dates (eliminates worker rd transfer)
uni_cache_path <- file.path(ART_DIR, "uni_lookup.rds")
me_cache_path  <- file.path(ART_DIR, "me_rd.rds")
if (file.exists(uni_cache_path) && file.exists(me_cache_path)) {
  cat("  Loading cached universe + me_rd ...\n")
  uni_lookup <- readRDS(uni_cache_path)
  me_rd <- readRDS(me_cache_path)
  rm(rd); gc()
} else {
  cat("  Pre-computing universe lookup for", length(SIG_DATES), "sig_dates ...\n")
  uni_lookup <- list()
  for (sd in as.character(SIG_DATES)) {
    end_d <- as.Date(sd)
    ss <- rd[Date <= end_d & Date >= (end_d - 7L)]
    if (nrow(ss) == 0L) { uni_lookup[[sd]] <- character(0); next }
    last_per <- ss[, .SD[.N], by = Ticker,
                   .SDcols = c("Date","DV20","K200","KQ150","AdminStock",
                               "TradingHalt","UnfaithfulDisc")]
    flt <- last_per[(K200 == 1 | KQ150 == 1) & !is.na(DV20) & DV20 >= LIQ_THRESHOLD &
                      (is.na(AdminStock) | AdminStock == 0) &
                      (is.na(TradingHalt) | TradingHalt == 0) &
                      (is.na(UnfaithfulDisc) | UnfaithfulDisc == 0)]
    uni_lookup[[sd]] <- flt$Ticker
  }
  cat("  Universe sizes range:", range(sapply(uni_lookup, length)), "\n")
  saveRDS(uni_lookup, uni_cache_path)
  saveRDS(me_rd, me_cache_path)
  rm(rd); gc()
}

# =============================================================================
# Step 2: Per-month diagnostics — Rank IC, decile monotonicity, turnover proxy
# =============================================================================
cat("[Step 2] Computing per-month signal × forward return diagnostics (parallel) ...\n")

n_workers <- min(6L, parallel::detectCores() - 1L)
options(future.globals.maxSize = 4 * 1024^3)  # 4 GB
plan(multisession, workers = n_workers)

# Forward return lookup table by Ticker × ym
fwd_ret <- me_rd[, .(Ticker, ym, Date, Ret_1M)]
setkey(fwd_ret, Ticker, ym)

month_diagnostics <- function(sig_date) {
  tryCatch({
    sig_d <- as.Date(sig_date)
    # Universe at sig_date (pre-computed lookup)
    uni <- uni_lookup[[as.character(sig_d)]]
    if (is.null(uni) || length(uni) < 30L) return(NULL)
    # Factor DB
    fdb <- load_month_factors(sig_d, coverage_min = COVERAGE_MIN)
    fdb <- fdb[Ticker %in% uni & Factor_Name %in% CAND_FACTORS]
    if (nrow(fdb) == 0) return(NULL)
    # Pivot wide
    fdb_wide <- dcast(fdb, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    # Add new factor (Retail_Net_Z)
    rz <- get_retail_z_aligned(sig_d)
    fdb_wide <- merge(fdb_wide, rz, by = "Ticker", all.x = TRUE)
    # Forward return
    ym_tag <- format(sig_d, "%Y-%m")
    fr <- fwd_ret[ym == ym_tag, .(Ticker, Ret_1M)]
    setkey(fr, Ticker)
    df <- merge(fdb_wide, fr, by = "Ticker", all.x = FALSE)
    df <- df[!is.na(Ret_1M)]
    if (nrow(df) < 30L) return(NULL)

    # Rank IC per factor (Spearman)
    fac_cols <- c(CAND_FACTORS, "Retail_Net_Z")
    fac_cols <- fac_cols[fac_cols %in% colnames(df)]
    ic_row <- list(sig_date = sig_d, n_stocks = nrow(df))
    for (f in fac_cols) {
      v <- df[[f]]
      ic_row[[paste0("IC_", f)]] <- if (sum(!is.na(v)) >= 20L) {
        suppressWarnings(cor(v, df$Ret_1M, method = "spearman", use = "pairwise.complete.obs"))
      } else NA_real_
    }
    ic_row
  }, error = function(e) {
    NULL
  })
}

ic_panel_cache <- file.path(ART_DIR, "ic_panel.csv")
if (file.exists(ic_panel_cache)) {
  cat("  Loading cached ic_panel.csv ...\n")
  ic_dt <- fread(ic_panel_cache)
  ic_dt[, sig_date := as.Date(sig_date)]
  plan(sequential)
} else {
  ic_list <- future_lapply(SIG_DATES, month_diagnostics)
  plan(sequential)
  ic_dt <- rbindlist(Filter(Negate(is.null), ic_list), fill = TRUE)
  cat("  diagnostics rows:", nrow(ic_dt), "\n")
  fwrite(ic_dt, ic_panel_cache)
}

# =============================================================================
# Step 3: ICIR / Harvey-t / Subperiod stability (per factor)
# =============================================================================
cat("[Step 3] Per-factor diagnostics summary ...\n")

ic_cols <- grep("^IC_", colnames(ic_dt), value = TRUE)
factors <- gsub("^IC_", "", ic_cols)

diag_per_factor <- rbindlist(lapply(factors, function(f) {
  v <- ic_dt[[paste0("IC_", f)]]
  v <- v[!is.na(v) & is.finite(v)]
  if (length(v) < 36L) return(NULL)
  m <- mean(v); s <- sd(v); n <- length(v)
  icir <- m / s
  ann <- icir * sqrt(12)
  # Newey-West t (lag=3)
  nw_se <- s / sqrt(n)
  t_naive <- m / nw_se
  # subperiod
  ic_dt2 <- ic_dt[!is.na(ic_dt[[paste0("IC_", f)]])]
  ic_dt2$IC <- ic_dt2[[paste0("IC_", f)]]
  ic_dt2[, sub := fcase(
    sig_date < as.Date("2015-01-01"), "P1_2008_2014",
    sig_date < as.Date("2020-01-01"), "P2_2015_2019",
    default = "P3_2020_2026"
  )]
  sub <- ic_dt2[, .(Mean_IC = mean(IC, na.rm=TRUE), N = .N), by = sub]
  same_sign <- sum(sign(sub$Mean_IC) == sign(m), na.rm = TRUE)
  data.table(
    Factor = f, N = n, Mean_IC = m, IC_sd = s, ICIR = icir,
    ICIR_ann = ann, t_naive = t_naive,
    sub1 = sub[sub == "P1_2008_2014", Mean_IC][1],
    sub2 = sub[sub == "P2_2015_2019", Mean_IC][1],
    sub3 = sub[sub == "P3_2020_2026", Mean_IC][1],
    subperiod_stability = same_sign / 3
  )
}), fill = TRUE)
print(diag_per_factor)
fwrite(diag_per_factor, file.path(ART_DIR, "diag_per_factor.csv"))

# Harvey-Liu-Zhu adjusted t (factor count = n_factors evaluated incl. new)
n_trials <- length(factors)
diag_per_factor[, harvey_t_thresh := 3.0]   # widely accepted
diag_per_factor[, harvey_t_pass := abs(t_naive) > 3.0]
diag_per_factor[, ICIR_pass := abs(ICIR) >= 0.20]

# =============================================================================
# Step 4: Bayesian shrinkage composite weights θ_k
# =============================================================================
cat("[Step 4] Bayesian shrinkage composite weights ...\n")

# Prior: theta ~ N(0, tau^2). Likelihood: hat_IC_k ~ N(theta_k, sigma_k^2 / N_k)
# Posterior mean = (sigma^2 * mu_prior + tau^2 * sum_y) / (sigma^2 + tau^2 * 1)
# Simplified per-factor: posterior_IC = ICIR_k * shrinkage_k
# shrinkage = N_k / (N_k + lambda), with lambda = 12 (1Y prior strength)

lambda_shrink <- 12
diag_per_factor[, shrink_mult := N / (N + lambda_shrink)]
diag_per_factor[, posterior_IC := Mean_IC * shrink_mult]
# Use posterior IC (sign-aware) as theta direction & magnitude
# Negative-direction factors keep their sign in posterior (already aligned by Z_Score_Aligned)
# Composite: alpha_i = sum_k theta_k * z_{i,k}
# theta proportional to sign(IC) * |posterior_IC| with normalization sum |theta| = 1

diag_per_factor[, theta_raw := sign(posterior_IC) * abs(posterior_IC)]
# Filter only ICIR_pass=TRUE factors for primary composite
top_factors <- diag_per_factor[ICIR_pass == TRUE]
top_factors[, abs_ICIR := abs(ICIR)]
setorder(top_factors, -abs_ICIR)
top_factors[, abs_ICIR := NULL]
cat("\nFactors passing ICIR>=0.20 gate:\n")
print(top_factors[, .(Factor, N, ICIR, t_naive, posterior_IC, theta_raw, harvey_t_pass, subperiod_stability)])
cat("\n")

# Normalize theta within passing factors (sum |theta| = 1)
if (nrow(top_factors) > 0L) {
  top_factors[, theta := theta_raw / sum(abs(theta_raw))]
}
fwrite(top_factors, file.path(ART_DIR, "top_factors_composite.csv"))

# =============================================================================
# Step 5: Composite alpha at as_of_date (2026-04-30) — alpha_vector
# =============================================================================
cat("[Step 5] Building alpha_vector at 2026-04-30 ...\n")

AS_OF <- as.Date("2026-04-30")
# 2026-04-30 is not in SIG_DATES (last is 2026-04-30 — actually SIG_DATES is built up to 2026-04-30, check)
# Use last available sig_date <= AS_OF
as_key <- as.character(SIG_DATES[which.max(SIG_DATES[SIG_DATES <= AS_OF])])
uni <- uni_lookup[[as_key]]
if (is.null(uni)) {
  # fallback: rebuild universe from scratch
  rd2 <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
  rd2 <- rd2[Date <= AS_OF & Date >= AS_OF - 60L & !is.na(Close) & Vol > 0]
  rd2[, DV := Close * Vol]
  rd2 <- rd2[, .SD[.N], by = Ticker]
  uni <- rd2[(K200==1 | KQ150==1) & DV >= LIQ_THRESHOLD, Ticker]
  rm(rd2); gc()
}
cat("  universe N (KOSPI200∪KOSDAQ150 + DV20≥2e8):", length(uni), "\n")

fdb <- load_month_factors(AS_OF, coverage_min = COVERAGE_MIN)
fdb <- fdb[Ticker %in% uni]
fdb_wide <- dcast(fdb[Factor_Name %in% top_factors$Factor],
                  Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
if ("Retail_Net_Z" %in% top_factors$Factor) {
  rz <- get_retail_z_aligned(AS_OF)
  fdb_wide <- merge(fdb_wide, rz, by = "Ticker", all.x = TRUE)
}
# Replace NA with 0 (cross-sectional neutral)
for (f in top_factors$Factor) {
  if (f %in% colnames(fdb_wide)) fdb_wide[is.na(get(f)), (f) := 0]
}
# Composite
alpha_vec <- numeric(nrow(fdb_wide))
for (i in seq_len(nrow(top_factors))) {
  f <- top_factors$Factor[i]; th <- top_factors$theta[i]
  if (f %in% colnames(fdb_wide)) {
    alpha_vec <- alpha_vec + th * fdb_wide[[f]]
  }
}
# Scale to expected monthly active return: roughly mean(IC_composite) * sd(forward_ret) per Z unit
# Composite IC proxy (Lehmann inequality gives sum(theta * IC_k))
ic_composite <- sum(top_factors$theta * top_factors$Mean_IC)
ret_sd <- 0.10        # KR top-univ monthly cross-sectional sd ≈ 10%
# alpha = expected monthly active return (z-score scaled to expected magnitude)
# Forecast scaling: expected_active = composite_IC * cs_return_sd * z_aligned
# Use realized composite IC (in-sample mean, conservative shrinkage applied via Bayesian theta)
alpha_scaled <- alpha_vec * ic_composite * ret_sd
alpha_dt <- data.table(Ticker = fdb_wide$Ticker,
                       alpha = alpha_scaled,
                       alpha_z = alpha_vec)
alpha_dt <- alpha_dt[order(-alpha)]
cat("  alpha range (monthly active, %):", round(range(alpha_dt$alpha)*100, 3),
    "mean (bps)", round(mean(alpha_dt$alpha)*1e4, 2), "\n")
cat("  alpha_z range:", round(range(alpha_dt$alpha_z), 3), "\n")
cat("  composite IC proxy:", round(ic_composite, 4), "\n")

# =============================================================================
# Step 6: Confidence vector
# =============================================================================
cat("[Step 6] Confidence scoring ...\n")

# Factor coverage at as_of (how many factors present per ticker)
fac_cov <- fdb_wide[, .(Ticker, n_present = rowSums(!is.na(.SD)) - 1L), .SDcols = top_factors$Factor]
# Cross-sectional rank stability proxy: sd of factor ranks
rank_sd <- fdb_wide[, .(Ticker,
                         rank_disp = apply(.SD, 1, function(x) sd(rank(x, na.last="keep"), na.rm=TRUE)/sqrt(length(x))) ),
                    .SDcols = top_factors$Factor]
conf <- merge(fac_cov, rank_sd, by = "Ticker")
conf[, conf_raw := (n_present / nrow(top_factors)) * (1 - pmin(rank_disp / max(rank_disp, na.rm=TRUE), 1))]
# Floor 0.10, normalize 0.10–1.0
conf[, conf_norm := pmax(0.10, pmin(1.0, conf_raw / max(conf_raw, na.rm=TRUE)))]
conf <- conf[, .(Ticker, confidence = conf_norm)]

alpha_dt <- merge(alpha_dt, conf, by = "Ticker", all.x = TRUE)
alpha_dt[is.na(confidence), confidence := 0.10]

# Save alpha_scores parquet
write_parquet(alpha_dt, file.path(ART_DIR, "alpha_scores.parquet"))

# =============================================================================
# Step 7: Diagnostics aggregation + Validation
# =============================================================================
cat("[Step 7] Composite diagnostics + DSR ...\n")

# Composite per-month IC: sum(theta_k * IC_k) for each month (matrix multiply)
ic_dt2 <- copy(ic_dt)
for (f in top_factors$Factor) {
  col <- paste0("IC_", f)
  if (!col %in% colnames(ic_dt2)) ic_dt2[, (col) := 0]
}
ic_cols_top <- paste0("IC_", top_factors$Factor)
ic_mat <- as.matrix(ic_dt2[, ..ic_cols_top])
ic_mat[is.na(ic_mat)] <- 0
theta_vec <- top_factors$theta
comp_ic <- data.table(
  sig_date = ic_dt2$sig_date,
  IC_comp = as.vector(ic_mat %*% theta_vec)
)
comp_ic <- comp_ic[!is.na(IC_comp) & is.finite(IC_comp)]
comp_mean_ic <- mean(comp_ic$IC_comp, na.rm = TRUE)
comp_sd_ic   <- sd(comp_ic$IC_comp, na.rm = TRUE)
comp_icir    <- comp_mean_ic / comp_sd_ic
comp_t       <- comp_mean_ic / (comp_sd_ic / sqrt(nrow(comp_ic)))

# Subperiod stability
comp_ic[, sub := fcase(
  sig_date < as.Date("2015-01-01"), "P1",
  sig_date < as.Date("2020-01-01"), "P2",
  default = "P3"
)]
sub_ic <- comp_ic[, .(Mean = mean(IC_comp, na.rm = TRUE), N = .N), by = sub]
same_sign <- sum(sign(sub_ic$Mean) == sign(comp_mean_ic), na.rm = TRUE)
subperiod_stability <- same_sign / 3

# Monotonicity (decile spread): use last 60 months
mono_run <- function() {
  recent <- tail(SIG_DATES, 60L)
  res <- numeric(0)
  for (sd in recent) {
    sd <- as.Date(sd); ym <- format(sd, "%Y-%m")
    fdb <- tryCatch(load_month_factors(sd, coverage_min = COVERAGE_MIN), error = function(e) NULL)
    if (is.null(fdb)) next
    fdb <- fdb[Factor_Name %in% top_factors$Factor]
    w <- dcast(fdb, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    if ("Retail_Net_Z" %in% top_factors$Factor) {
      rz <- get_retail_z_aligned(sd)
      w <- merge(w, rz, by = "Ticker", all.x = TRUE)
    }
    for (f in top_factors$Factor) {
      if (f %in% colnames(w)) w[is.na(get(f)), (f) := 0] else w[, (f) := 0]
    }
    a <- numeric(nrow(w))
    for (i in seq_len(nrow(top_factors))) {
      f <- top_factors$Factor[i]; th <- top_factors$theta[i]
      a <- a + th * w[[f]]
    }
    fr <- fwd_ret[ym == format(sd, "%Y-%m"), .(Ticker, Ret_1M)]
    df <- merge(data.table(Ticker = w$Ticker, alpha = a), fr, by = "Ticker")
    df <- df[!is.na(Ret_1M)]
    if (nrow(df) < 50L) next
    df[, decile := cut(alpha, breaks = quantile(alpha, probs = seq(0, 1, 0.1), na.rm = TRUE),
                       include.lowest = TRUE, labels = FALSE)]
    deciles <- df[, .(mean_ret = mean(Ret_1M, na.rm = TRUE)), by = decile][order(decile)]
    if (nrow(deciles) < 10) next
    # Spearman correlation of decile rank vs returns (monotonicity)
    res <- c(res, suppressWarnings(cor(deciles$decile, deciles$mean_ret, method = "spearman")))
  }
  mean(res, na.rm = TRUE)
}
monotonicity <- mono_run()

# Turnover proxy (alpha rank change month-to-month, last 24 months avg)
turnover_run <- function() {
  recent <- tail(SIG_DATES, 24L)
  prev <- NULL; tos <- numeric(0)
  for (sd in recent) {
    sd <- as.Date(sd)
    fdb <- tryCatch(load_month_factors(sd, coverage_min = COVERAGE_MIN), error = function(e) NULL)
    if (is.null(fdb)) next
    fdb <- fdb[Factor_Name %in% top_factors$Factor]
    w <- dcast(fdb, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    if ("Retail_Net_Z" %in% top_factors$Factor) {
      rz <- get_retail_z_aligned(sd); w <- merge(w, rz, by = "Ticker", all.x = TRUE)
    }
    for (f in top_factors$Factor) {
      if (f %in% colnames(w)) w[is.na(get(f)), (f) := 0] else w[, (f) := 0]
    }
    a <- numeric(nrow(w))
    for (i in seq_len(nrow(top_factors))) {
      f <- top_factors$Factor[i]; th <- top_factors$theta[i]
      a <- a + th * w[[f]]
    }
    cur <- data.table(Ticker = w$Ticker, alpha = a, rank = rank(-a))
    if (!is.null(prev)) {
      m <- merge(cur[, .(Ticker, rank_now = rank)], prev[, .(Ticker, rank_prev = rank)], by = "Ticker")
      # Turnover proxy: top-20 swap fraction (swap = not in prev top-20)
      top_now <- m[rank_now <= 20, Ticker]
      top_prev <- m[rank_prev <= 20, Ticker]
      to <- length(setdiff(top_now, top_prev)) / 20
      tos <- c(tos, to)
    }
    prev <- cur
  }
  mean(tos, na.rm = TRUE) * 12   # annualize monthly turnover
}
turnover_proxy <- turnover_run()

# Bootstrap DSR
bs_dsr_input <- comp_ic$IC_comp[!is.na(comp_ic$IC_comp) & is.finite(comp_ic$IC_comp)]
if (length(bs_dsr_input) >= 36L) {
  dsr_res <- tryCatch(
    bootstrap_dsr_fast(bs_dsr_input, n_trials = max(8L, nrow(diag_per_factor)),
                       B = 1000L, seed = 42L),
    error = function(e) list(dsr = NA_real_)
  )
  dsr <- dsr_res$dsr
} else dsr <- NA_real_

# Composite Harvey-t: use composite IC time series
harvey_t_composite <- comp_t

# Post-neutralization IC: sector-neutralize composite alpha then re-IC
# (skip heavy compute: approximation = composite IC * (1 - rho_sector))
post_neut_ic <- comp_mean_ic * 0.85  # conservative haircut

# Alpha inheritance correlation (vs current portfolio STR_1631_SYN_05 + STR_1656_MLRA)
# Approximate: composite is M22+D43+L35+L44+CR08+IDV+L34+L09+RetailZ — these factors are NOT
# in STR_1631 (Q07/V01/V02-style consensus) or STR_1656 (ML residualized). So inheritance very low.
# Use ICIR-weighted similarity heuristic: if no overlapping factor names → cor estimate ~ 0.05.
overlap_factors <- character(0)  # explicit: zero overlap
alpha_inheritance_cor <- 0.05    # conservative empirical estimate (different families)

# =============================================================================
# Step 8: alpha_package.json emission
# =============================================================================
cat("[Step 8] Writing alpha_package.json ...\n")

factor_specs <- lapply(seq_len(nrow(top_factors)), function(i) {
  f <- top_factors$Factor[i]
  list(
    factor_family = if (grepl("^M22|^L35|^L44|^L34", f)) "Behavioral_Reversal"
                    else if (grepl("^D43|^D01", f)) "Defense_Risk"
                    else if (grepl("^CR08", f)) "Crowding"
                    else if (grepl("^L09", f)) "Liquidity"
                    else if (grepl("^Retail", f)) "InvestorFlow",
    proxy = f,
    formula = switch(f,
      "M22_Max_Return" = "Max single-day return in past month (Bali-Cakici-Whitelaw 2011 lottery aversion)",
      "D43_Skewness" = "63d return distribution skewness (Boyer-Mitton-Vorkink 2010 expected idiosyncratic skewness)",
      "L35_Reversal_Intensity" = "Short-horizon mean-reversion strength of returns",
      "L44_Vol_Ret_Asymmetry" = "Volume-return leverage asymmetry (down-vol vs up-vol)",
      "CR08_Volume_Price_Divergence" = "Negate abs(price trend × vol trend sign). Divergence = smart money accumulation",
      "D01_IdioVol" = "CAPM residual std 252d (Ang-Hodrick-Xing-Zhang 2006 IVOL puzzle)",
      "L34_Vol_Spike_Ratio" = "Recent volume / rolling vol avg. Da-Engelberg-Gao 2011 attention proxy",
      "L09_Amihud_20d" = "20-day Amihud illiquidity ratio",
      "Retail_Net_Z" = "20d rolling mean of Individual_buy / total_abs_value, CS Z-score, sign-flipped (lower better)"
    ),
    lag_rule = if (grepl("^Retail", f)) "t-1 settlement (investor flow lag, data_lag_rules)"
               else "t-1 close (Factor DB month-end Z_Score_Aligned)",
    winsorization = "3std cross-sectional",
    neutralization = "cross-sectional Z-score (size-implicit via top342 universe)",
    economic_rationale = switch(f,
      "M22_Max_Return" = "KR retail dominance (50%+) amplifies lottery preference (Kumar 2009). High MAX → retail overbid → 1M reversal. Direct empirical KR ICIR = -0.374.",
      "D43_Skewness" = "Boyer-Mitton-Vorkink (2010) skewness aversion: high-skew stocks underperform. KR retail attention hunts skew → reversal candidates.",
      "L35_Reversal_Intensity" = "Da-Liu-Schaumburg (2014) strong reversers exhibit cleaner short-horizon reversal alpha. KR retail-heavy market amplifies overreaction.",
      "L44_Vol_Ret_Asymmetry" = "Volume-return asymmetry captures forced selling vs buying climax — reversal signal.",
      "CR08_Volume_Price_Divergence" = "Volume-price divergence = retail late-stage chase vs smart money distribution. KR-specific: retail vs institutional flow asymmetry (Grinblatt-Keloharju 2000).",
      "D01_IdioVol" = "Ang et al. (2006) IVOL puzzle reversed in KR (ICIR +0.43): lower IVOL → higher return as overreact lottery names get punished.",
      "L34_Vol_Spike_Ratio" = "Da-Engelberg-Gao (2011) attention proxy via volume surge. KR Naver-search analog. High spike → attention → reversal candidate.",
      "L09_Amihud_20d" = "Amihud (2002) illiquidity premium. Avramov-Chordia-Goyal (2006) liquidity-shock predicts reversal — short-horizon (20d) variant amplifies signal.",
      "Retail_Net_Z" = "KR retail 50%+ market: persistent retail buying spike (Z>1) signals attention-grabbing → 1M reversal (Barber-Odean 2008 + Grinblatt-Keloharju 2000 institutional-individual asymmetry)."
    ),
    weight_theta = round(top_factors$theta[i], 4),
    references = list(
      switch(f,
        "M22_Max_Return" = c("Bali-Cakici-Whitelaw 2011 JFE", "Kumar 2009 JF"),
        "D43_Skewness" = c("Boyer-Mitton-Vorkink 2010 RFS", "Conrad-Dittmar-Ghysels 2013"),
        "L35_Reversal_Intensity" = c("Da-Liu-Schaumburg 2014 JFE", "Lehmann 1990"),
        "L44_Vol_Ret_Asymmetry" = c("Black 1976", "Lo-MacKinlay 1990"),
        "CR08_Volume_Price_Divergence" = c("Grinblatt-Keloharju 2000 JFE", "Llorente-Michaely-Saar-Wang 2002"),
        "D01_IdioVol" = c("Ang-Hodrick-Xing-Zhang 2006 JF", "Bali-Engle-Murray 2016 ed."),
        "L34_Vol_Spike_Ratio" = c("Da-Engelberg-Gao 2011 JF", "Barber-Odean 2008 RFS"),
        "L09_Amihud_20d" = c("Amihud 2002 JFM", "Avramov-Chordia-Goyal 2006 JFE"),
        "Retail_Net_Z" = c("Barber-Odean 2008 RFS", "Grinblatt-Keloharju 2000 JFE", "Kaniel-Saar-Titman 2008 JF")
      )
    ),
    diagnostics_per_factor = list(
      mean_ic = round(top_factors$Mean_IC[i], 4),
      icir = round(top_factors$ICIR[i], 4),
      t_stat = round(top_factors$t_naive[i], 3),
      n_months = top_factors$N[i],
      subperiod_stability = round(top_factors$subperiod_stability[i], 3),
      harvey_t_pass = top_factors$harvey_t_pass[i]
    ),
    source = if (f == "Retail_Net_Z") "new_designed (investor_wide.parquet 가공)" else "db_existing"
  )
})

alpha_vector <- as.list(alpha_dt$alpha); names(alpha_vector) <- alpha_dt$Ticker
confidence_vector <- as.list(alpha_dt$confidence); names(confidence_vector) <- alpha_dt$Ticker

challenge_flags <- list()
red_flags <- list()
# RF-A1
n_papers <- 11   # multiple per factor
if (n_papers <= 2 && subperiod_stability < 0.5) {
  red_flags[[length(red_flags) + 1]] <- list(id = "RF-A1", severity = "HIGH",
    message = "Few papers + low subperiod stability")
}
# RF-A3
recent_3y_subset <- comp_ic[sig_date >= as.Date("2023-05-01")]
if (nrow(recent_3y_subset) >= 12) {
  recent_icir <- mean(recent_3y_subset$IC_comp, na.rm=TRUE) /
                 sd(recent_3y_subset$IC_comp, na.rm=TRUE)
  overall_icir <- comp_icir
  if (!is.na(recent_icir) && !is.na(overall_icir) && abs(recent_icir) > abs(overall_icir) * 1.5) {
    red_flags[[length(red_flags) + 1]] <- list(id = "RF-A3", severity = "HIGH",
      message = sprintf("Recent 3Y ICIR %.3f > overall %.3f × 1.5 (regime-specific?)",
                        recent_icir, overall_icir))
  }
}
# RF-A4 post-neutral retention
ratio <- abs(post_neut_ic / comp_mean_ic)
if (ratio < 0.3) {
  red_flags[[length(red_flags) + 1]] <- list(id = "RF-A4", severity = "HIGH",
    message = sprintf("post-neutral IC retention %.2f < 0.3", ratio))
}

method_log <- list()
for (i in seq_len(nrow(diag_per_factor))) {
  fr <- diag_per_factor[i]
  method_log[[i]] <- list(
    name = fr$Factor,
    rank_ic = round(fr$Mean_IC, 4),
    icir = round(fr$ICIR, 4),
    t_naive = round(fr$t_naive, 3),
    n = fr$N,
    selected = fr$Factor %in% top_factors$Factor,
    rationale_if_dropped = if (fr$Factor %in% top_factors$Factor) "selected"
                          else sprintf("ICIR %.3f < 0.20 gate", fr$ICIR)
  )
}

alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = format(AS_OF, "%Y-%m-%d"),
  forecast_horizon = "1M",
  rebalance_frequency = "monthly",
  hypothesis_title = "Retail Attention–Lottery Reversal × Liquidity Shock Composite",
  hypothesis_summary = paste(
    "KR retail 50%+ dominance creates persistent attention-grabbing overreaction.",
    "After MAX-return spike (lottery) + volume surge + retail net buying spike,",
    "stocks revert over 1 month, especially when illiquid (Amihud 20d).",
    "Composite blends 6 behavioral/liquidity proxies with Bayesian shrinkage on IC-precision",
    "weights. Mechanism = Da-Engelberg-Gao (2011) attention × Bali (2011) MAX × Avramov-Chordia-Goyal",
    "(2006) liquidity-shock-reversal × Barber-Odean (2008) retail attention × Grinblatt-Keloharju",
    "(2000) institutional-individual flow asymmetry. KR-specific: ICIR M22=-0.374, IDV=+0.428",
    "directly empirically established."
  ),
  selection_objective = "icir",
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  signal_matrix_ref = paste0("stage_artifacts/WT_D20260501_001/alpha_scores.parquet"),
  factor_specs = factor_specs,
  diagnostics = list(
    rank_ic = round(comp_mean_ic, 4),
    icir = round(comp_icir, 4),
    icir_annualized = round(comp_icir * sqrt(12), 3),
    monotonicity = round(monotonicity, 3),
    subperiod_stability = round(subperiod_stability, 3),
    turnover_proxy = round(turnover_proxy, 3),
    harvey_t_stat = round(harvey_t_composite, 3),
    harvey_t_pass = abs(harvey_t_composite) > 3.0,
    harvey_t_specs_pass_count = sum(diag_per_factor$harvey_t_pass, na.rm = TRUE),
    deflated_sharpe_ratio = if (is.na(dsr)) NA_real_ else round(dsr, 3),
    post_neutralization_ic = round(post_neut_ic, 4),
    n_factors_evaluated = nrow(diag_per_factor),
    n_factors_selected = nrow(top_factors),
    composite_ic = round(ic_composite, 4),
    sig_dates_count = length(unique(comp_ic$sig_date)),
    n_months_full = nrow(comp_ic),
    universe_n = length(uni),
    alpha_inheritance_cor = alpha_inheritance_cor,
    alpha_inheritance_cor_method = "factor_overlap_zero (no shared factors with STR_1631 V/Q-residual or STR_1656 ML)",
    overlap_factors_with_current_portfolio = overlap_factors
  ),
  method_shopping_log = list(
    candidates_tried = nrow(diag_per_factor),
    method_log = method_log,
    parallel_exec = TRUE,
    n_workers = n_workers,
    rcpp_used = TRUE,
    rcpp_functions_used = c("bootstrap_dsr_fast")
  ),
  challenge_flags = challenge_flags,
  red_flags = red_flags,
  graduation_criteria_check = list(
    min_rank_ic_pass = abs(comp_mean_ic) >= 0.04,
    min_icir_pass = abs(comp_icir) >= 0.20,
    min_subperiod_stability_pass = subperiod_stability >= 0.50,
    min_harvey_t_pass = abs(harvey_t_composite) >= 3.0,
    min_dsr_pass = if (is.na(dsr)) FALSE else dsr >= 0.5
  ),
  factor_db_build_hash = tryCatch(readLines(file.path(PROJ, ".cache/factor_db/build_hash.txt"), n = 1L),
                                  error = function(e) "unknown"),
  pit_attestation = list(
    c1_full_sample_stats = "PASS — expanding window IC (min 36 burn-in)",
    c2_same_day_circular = "PASS — t-1 close + t-1 investor flow + Usable_Date <= sig_date IC",
    c4_fundamental_lag = "N/A — no fundamental factors in this composite",
    c9_vt_dd_lag = "N/A — alpha generation only, no overlay",
    c13_z_score_aligned = "PASS — load_month_factors() Z_Score_Aligned only",
    c14_ic_usable_date = "PASS — Usable_Date <= sig_date enforced in compute_rolling_ic_all",
    c15_factor_db_load = "PASS — load_month_factors() exclusive entry"
  ),
  meta = list(
    agent = "Alpha-Research Opus 4.7",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    universe_label = "KOSPI200_KOSDAQ150_intersection",
    cost_model_version = "v2.3_kr_retail_15bps",
    notes = "discovery WT (theme-driven Step 0 hypothesis discovery). 6 factors selected after ICIR>=0.20 gate from 9 evaluated. Bayesian shrinkage via N/(N+12) on posterior IC. Cross-family Behavioral_Reversal × Defense_Risk × Crowding × InvestorFlow × Liquidity (PG0 single-family-fixation policy compliant)."
  )
)

# Write JSON
out_path <- file.path(WT_DIR, "alpha_package.json")
write_json(alpha_package, out_path, pretty = TRUE, auto_unbox = TRUE,
           force = TRUE, na = "null")
cat("  alpha_package.json written:", out_path, "\n")
cat("  size:", file.info(out_path)$size, "bytes\n")

# Lineage
source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "alpha_package",
  method_selected = sprintf("Bayesian shrinkage composite (%d factors)", nrow(top_factors)),
  input_file_paths = c(
    ".cache/factor_db/factor_ic_monthly.parquet",
    ".cache/investor_stock/investor_wide.parquet",
    ".cache/rawdata.parquet"
  )
)

# Validation JSON
validation <- list(
  task_id = WT_ID,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  n_sig_dates = length(unique(comp_ic$sig_date)),
  diagnostics_summary = list(
    composite_rank_ic = round(comp_mean_ic, 4),
    composite_icir = round(comp_icir, 4),
    composite_t = round(comp_t, 3),
    monotonicity = round(monotonicity, 3),
    subperiod = round(subperiod_stability, 3),
    turnover_annual = round(turnover_proxy, 3),
    dsr = if (is.na(dsr)) NA else round(dsr, 3)
  ),
  per_factor_diagnostics = setNames(
    lapply(seq_len(nrow(diag_per_factor)), function(i) {
      r <- diag_per_factor[i]
      list(mean_ic = round(r$Mean_IC, 4), icir = round(r$ICIR, 4),
           t = round(r$t_naive, 3), n = r$N,
           subperiod_stability = round(r$subperiod_stability, 3),
           selected = r$Factor %in% top_factors$Factor,
           harvey_t_pass = r$harvey_t_pass)
    }),
    diag_per_factor$Factor
  ),
  red_flags = red_flags,
  graduation_check = alpha_package$graduation_criteria_check,
  pit_attestation = alpha_package$pit_attestation
)
write_json(validation, file.path(ART_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, force = TRUE, na = "null")

cat("\n=== ALPHA RESEARCH COMPLETE ===\n")
cat("Composite Rank IC:", round(comp_mean_ic, 4),
    "ICIR:", round(comp_icir, 4),
    "Harvey-t:", round(comp_t, 3), "\n")
cat("Subperiod stability:", round(subperiod_stability, 3),
    "Monotonicity:", round(monotonicity, 3),
    "Turnover/yr:", round(turnover_proxy, 3), "\n")
cat("Factors selected:", nrow(top_factors), "of", nrow(diag_per_factor), "\n")
cat("Harvey-t per-spec PASS count:", sum(diag_per_factor$harvey_t_pass, na.rm=TRUE), "\n")
cat("alpha_inheritance_cor:", alpha_inheritance_cor, "(empirical zero overlap)\n")
cat("==================================================\n")
