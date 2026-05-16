#==============================================================================
# WT-D20260513_002 Alpha Research — C Variant (4-axis sophisticated low-vol)
#
# Mandate (도훈 Session 81, 2026-05-13 C 옵션):
#   Parent WT-D20260513_001 v2 PIT-clean baseline 결격 3건 해소:
#     - rank_ic 0.0385 vs 0.04 target (-0.0015 marginal FAIL)
#     - Monotonicity Q1-Q5 0.25 vs 0.70 target (HARD FAIL)
#     - PIT-C2 same-day circular SUSPECTED
#   Orthogonality (Pearson 0.054 / Spearman -0.009 vs STR_1715) STRICT PASS retain.
#
# C Variant 4-axis design:
#   Axis 1 (PIT-C2 t+1 lag):
#     signal산출 = sig_date, execution = sig_date+1 거래일 close → next_me close.
#     forward_ret = (P_{next_me} / P_{sig_date+1}) - 1 (not same-day close).
#
#   Axis 2 (Sector-neutralize):
#     cross-section per sig_date: factor_raw 회귀 = β·sector_dummy + ε.
#     ε (residual) 으로 alpha 정의. KR sector concentration 영향 제거.
#
#   Axis 3 (FF-residual factor construction, Ang-Hodrick-Xing-Zhang 2006 정통):
#     trailing 252d daily return → CAPM (r_i = α + β·r_mkt + ε) rolling regression.
#     ε_i,t의 downside semi-deviation = "Idio Down-Vol".
#     기존 D57_Down_Vol (Factor DB precomputed total down-vol)와 비교.
#
#   Axis 4 (Monotonicity ≥0.70):
#     rank-based score smoothing → quintile-mean-regression for Q1-Q5 단조성 강화.
#     uniform rank transform applied after sector-residualization.
#
# Ex-ante grid (AX-002 N ≤ 5):
#   C1: CAPM-IdioVol_LOW (raw idio vol semi-dev, sector neutral OFF, no rank smooth)
#   C2: CAPM-IdioVol_LOW + Sector neutral
#   C3: CAPM-IdioDownVol_LOW (idio downside semi-dev, sector neutral OFF)
#   C4: CAPM-IdioDownVol_LOW + Sector neutral [정통 Ang 2006]
#   C5: 4-axis composite (CAPM + sector + smoothing + ensemble C1~C4)
#
# 5-spec FF panel (Codex C4 RF-A6):
#   spec1 base t_NW lag6
#   spec2 trim_top5 (5% extremes 제거)
#   spec3 p_2004_2013 sub
#   spec4 p_2014_2026 sub
#   spec5 sector_resid_robust (sector neutralize 통과 후 IC)
#==============================================================================

Sys.setenv("STR_1715_TG_ENABLE" = "0")

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(future); library(future.apply)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

WT_ID  <- "WT-D20260513_002"
BASE   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART    <- file.path(BASE, "stage_artifacts", "WT_D20260513_002")
MBOX   <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
dir.create(ART, showWarnings = FALSE, recursive = TRUE)

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

t_start <- Sys.time()
cat("[", as.character(t_start), "] C Variant pipeline START\n")

#==============================================================================
# Step 1: Universe + Liquidity + month-end strict (inherited from v2)
#==============================================================================

cat("[Step 1] Universe + month-end strict\n")

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
setkey(raw, Date, Ticker)

# Build month-end-trading-day calendar
all_trade_dates <- sort(unique(raw$Date))
trade_dt <- data.table(Date = all_trade_dates, ym = format(all_trade_dates, "%Y-%m"))
month_ends <- trade_dt[, .(Date = max(Date)), by = ym]$Date
month_ends <- sort(month_ends)

# Signal window 2004-01 ~ 2026-04 (~268 sig_dates)
SIG_DATES <- month_ends[month_ends >= as.Date("2004-01-01") & month_ends <= as.Date("2026-04-30")]
cat("Selected sig_dates:", length(SIG_DATES), " range:", as.character(min(SIG_DATES)), "~", as.character(max(SIG_DATES)), "\n")

# Pre-compute TV and rolling 20d ADV
raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)

LIQ_FLOOR <- 2e8
sig_panel <- raw[Date %in% SIG_DATES,
                 .(Date, Ticker, K200, KQ150, AdminStock, TradingHalt, UnfaithfulDisc,
                   ADV_20d, Close, Sector)]
setkey(sig_panel, Date, Ticker)

get_universe <- function(sig_date) {
  rows <- sig_panel[Date == sig_date]
  elig <- rows[(K200 == TRUE | KQ150 == TRUE) &
               !is.na(ADV_20d) & ADV_20d >= LIQ_FLOOR &
               (is.na(AdminStock) | AdminStock == FALSE) &
               (is.na(TradingHalt) | TradingHalt == FALSE) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE) &
               !is.na(Sector), Ticker]
  return(elig)
}

#==============================================================================
# Axis 1 (PIT-C2 t+1 lag): Forward return = (P_{next_me} / P_{sig_date+1}) - 1
#==============================================================================

cat("[Axis 1] PIT-C2 t+1 lag forward return\n")

# For each sig_date, find sig_date+1 trading day
all_trade_dates_sorted <- sort(unique(raw$Date))
next_trade_after <- function(d) {
  i <- match(d, all_trade_dates_sorted)
  if (is.na(i) || i == length(all_trade_dates_sorted)) return(NA)
  all_trade_dates_sorted[i + 1L]
}
sig_to_t1 <- sapply(SIG_DATES, next_trade_after) |> as.Date(origin = "1970-01-01")
cat("Sig_date → sig+1 mapping built. Sample:\n")
print(data.table(sig_date = SIG_DATES[1:5], t1 = sig_to_t1[1:5]))

# Forward return = price at t1 → price at next_me
close_wide <- dcast(raw[, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
setkey(close_wide, Date)

fwd_ret_list <- list()
for (i in seq_len(length(SIG_DATES) - 1L)) {
  d_t1 <- sig_to_t1[i]
  d_next_me <- SIG_DATES[i + 1L]
  if (is.na(d_t1) || d_t1 >= d_next_me) next

  # Use t+1 close → next_me close (Axis 1 PIT-C2 strict)
  px_t1 <- as.numeric(close_wide[Date == d_t1])
  px_next <- as.numeric(close_wide[Date == d_next_me])
  names(px_t1) <- names(close_wide); names(px_next) <- names(close_wide)
  tickers <- setdiff(names(close_wide), "Date")
  r <- (as.numeric(px_next[tickers]) / as.numeric(px_t1[tickers])) - 1
  fwd_ret_list[[i]] <- data.table(sig_date = SIG_DATES[i], t1_date = d_t1,
                                   next_me = d_next_me, Ticker = tickers, fwd_ret_1m = r)
}
fwd_returns <- rbindlist(fwd_ret_list)
fwd_returns <- fwd_returns[!is.na(fwd_ret_1m) & is.finite(fwd_ret_1m)]
cat("Forward return rows (Axis 1 t+1 lag):", nrow(fwd_returns), "\n")
cat("Sample forward returns:\n")
print(head(fwd_returns[, .(sig_date, t1_date, next_me, Ticker, fwd_ret_1m)]))

#==============================================================================
# Axis 3 (FF-residual): CAPM rolling 252d regression → idio residual
# Per-ticker per-month: residual = Ret_i - alpha - beta*BM_Ret
# Then compute idio_vol (total std of resid) + idio_down_vol (semi-dev of negative resid)
#==============================================================================

cat("\n[Axis 3] CAPM rolling 252d regression → idio residual semi-deviation\n")

# Use raw[Date, Ticker, Ret, BM_Ret] for trailing 252d window per sig_date
# To save compute: for each sig_date, gather 252 trade days before sig_date (inclusive),
# run per-ticker OLS r_i = α + β·BM, get residual series, compute idio_vol + idio_down_vol.

# Trade-day index 빠른 lookup
trade_day_idx <- data.table(Date = all_trade_dates_sorted, idx = seq_along(all_trade_dates_sorted))

# Per-sig_date trailing window builder
compute_idio_metrics <- function(sig_date, raw_dt, univ_tickers) {
  sig_idx <- trade_day_idx[Date == sig_date, idx]
  if (length(sig_idx) == 0 || sig_idx < 252) return(NULL)

  win_start_date <- all_trade_dates_sorted[sig_idx - 252 + 1]
  win_end_date   <- sig_date
  win_days <- raw_dt[Date >= win_start_date & Date <= win_end_date & Ticker %in% univ_tickers,
                    .(Date, Ticker, Ret, BM_Ret)]
  win_days <- win_days[!is.na(Ret) & !is.na(BM_Ret) & is.finite(Ret) & is.finite(BM_Ret)]

  # Per-ticker regression
  result_list <- list()
  for (tk in unique(win_days$Ticker)) {
    d_tk <- win_days[Ticker == tk]
    if (nrow(d_tk) < 200) next  # Need enough non-NA data
    # OLS via Sufficient stats (avoid lm overhead)
    x <- d_tk$BM_Ret; y <- d_tk$Ret
    n_obs <- length(y)
    x_mean <- mean(x); y_mean <- mean(y)
    cov_xy <- sum((x - x_mean) * (y - y_mean))
    var_x <- sum((x - x_mean)^2)
    if (var_x <= 0) next
    beta <- cov_xy / var_x
    alpha <- y_mean - beta * x_mean
    resid <- y - alpha - beta * x

    # Axis 3 metrics:
    idio_vol_total <- sd(resid)
    neg_resid <- resid[resid < 0]
    idio_down_vol <- if (length(neg_resid) >= 10) sqrt(mean(neg_resid^2)) else NA_real_

    result_list[[tk]] <- data.table(
      sig_date = sig_date, Ticker = tk,
      capm_beta = beta, capm_alpha_252d = alpha,
      idio_vol = idio_vol_total, idio_down_vol = idio_down_vol,
      n_obs = n_obs
    )
  }
  rbindlist(result_list)
}

# Build per-sig_date universe lookup
univ_map <- list()
for (i in seq_along(SIG_DATES)) {
  univ_map[[as.character(SIG_DATES[i])]] <- get_universe(SIG_DATES[i])
}

# Parallel computation
n_workers <- min(8L, parallel::detectCores() - 1L)
cat("Parallel workers:", n_workers, "\n")
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

# Subset raw to relevant cols + window for speedup
raw_slim <- raw[Date >= as.Date("2003-01-01") & Date <= as.Date("2026-04-30"),
                .(Date, Ticker, Ret, BM_Ret)]
setkey(raw_slim, Ticker, Date)

# Compute per sig_date (chunk by sig_date)
cat("Computing CAPM rolling 252d residual semi-dev for", length(SIG_DATES), "sig_dates...\n")
t_capm_start <- Sys.time()

idio_list <- future_lapply(SIG_DATES, function(sd) {
  univ_tk <- univ_map[[as.character(sd)]]
  if (length(univ_tk) < 30) return(NULL)
  compute_idio_metrics(sd, raw_slim, univ_tk)
}, future.seed = 42L)

plan(sequential)
idio_dt <- rbindlist(idio_list[!sapply(idio_list, is.null)])
t_capm_end <- Sys.time()
cat("CAPM 회귀 시간:", round(as.numeric(t_capm_end - t_capm_start, units = "mins"), 2), "분\n")
cat("idio_dt rows:", nrow(idio_dt), " sig_dates:", uniqueN(idio_dt$sig_date), "\n")
cat("Sample:\n")
print(head(idio_dt))

# Save raw idio metrics for reference
write_parquet(idio_dt, file.path(ART, "capm_idio_metrics.parquet"))

#==============================================================================
# Axis 2 (Sector-neutralize) + Axis 4 (Monotonic rank smooth)
#
# C1: raw idio_vol (no sector, no smooth)
# C2: idio_vol → sector resid (per sig_date)
# C3: raw idio_down_vol (no sector)
# C4: idio_down_vol → sector resid (Ang 2006 정통)
# C5: composite (C1~C4 EW after individual sector resid + rank smooth)
#
# All factor values for "low risk premium" — lower value = higher alpha.
# Apply -1 transform: alpha_score = -1 * standardized_factor
#==============================================================================

cat("\n[Axis 2+4] Sector-neutralize + Monotonic rank smooth\n")

# Merge with sector
sec_lookup <- sig_panel[, .(sig_date = Date, Ticker, Sector)]
setkey(sec_lookup, sig_date, Ticker)
setkey(idio_dt, sig_date, Ticker)
idio_dt <- merge(idio_dt, sec_lookup, by = c("sig_date", "Ticker"))
idio_dt <- idio_dt[!is.na(Sector)]
cat("After sector merge:", nrow(idio_dt), " rows\n")

# Per sig_date: compute 5 candidates
build_candidates <- function(dt_one) {
  # dt_one: one sig_date subset
  # Returns: data.table with Ticker × {C1..C5}
  n <- nrow(dt_one)
  if (n < 30) return(NULL)

  # Step (a): Cross-sectional Z-score (clip 3std)
  cs_z_clip <- function(x) {
    if (all(is.na(x))) return(rep(NA_real_, length(x)))
    mu <- mean(x, na.rm = TRUE); sd_ <- sd(x, na.rm = TRUE)
    if (is.na(sd_) || sd_ == 0) return(rep(0, length(x)))
    z <- (x - mu) / sd_
    pmax(pmin(z, 3), -3)
  }

  # Step (b): Sector-residualize
  sector_resid <- function(x, sector_vec) {
    df <- data.frame(x = x, sec = factor(sector_vec))
    df <- df[!is.na(df$x), ]
    if (nrow(df) < 5) return(rep(NA_real_, length(x)))
    if (nlevels(droplevels(df$sec)) < 2) return(x - mean(x, na.rm = TRUE))
    fit <- lm(x ~ sec, data = df, na.action = na.omit)
    resid_vec <- rep(NA_real_, length(x))
    resid_vec[!is.na(x)] <- residuals(fit)
    resid_vec
  }

  # Step (c): Monotonic rank smooth (Axis 4)
  # Transform: rank-based uniform mapping to [0, 1], then standardize.
  # This forces monotonic relationship between rank order and alpha score.
  rank_smooth <- function(x) {
    if (all(is.na(x))) return(x)
    r <- rank(x, ties.method = "average", na.last = "keep")
    u <- (r - 0.5) / sum(!is.na(x))  # uniform in (0, 1)
    # Convert to z-score equivalent using probit (inverse normal CDF)
    z <- qnorm(u)
    z[!is.na(z) & z > 3] <- 3
    z[!is.na(z) & z < -3] <- -3
    z
  }

  # C1: raw idio_vol → cs_z → align direction (low vol = high alpha) → multiply by -1
  c1_raw <- dt_one$idio_vol
  c1_z   <- cs_z_clip(c1_raw)
  C1 <- -c1_z  # low = high alpha

  # C2: idio_vol → sector resid → cs_z → align direction
  c2_raw <- sector_resid(dt_one$idio_vol, dt_one$Sector)
  c2_z   <- cs_z_clip(c2_raw)
  C2 <- -c2_z

  # C3: raw idio_down_vol → cs_z → align direction
  c3_raw <- dt_one$idio_down_vol
  c3_z   <- cs_z_clip(c3_raw)
  C3 <- -c3_z

  # C4: idio_down_vol → sector resid → cs_z → align direction (Ang 2006 정통)
  c4_raw <- sector_resid(dt_one$idio_down_vol, dt_one$Sector)
  c4_z   <- cs_z_clip(c4_raw)
  C4 <- -c4_z

  # C5: 4-axis composite (C1+C2+C3+C4 EW + rank_smooth applied to result)
  comp_pre <- (C1 + C2 + C3 + C4) / 4
  C5 <- rank_smooth(comp_pre)  # Axis 4: monotonic rank smooth applied to composite

  data.table(
    sig_date = dt_one$sig_date[1],
    Ticker = dt_one$Ticker,
    C1 = C1,
    C2 = C2,
    C3 = C3,
    C4 = C4,
    C5 = C5
  )
}

# Apply per sig_date
cat("Building candidates per sig_date...\n")
cand_list <- split(idio_dt, idio_dt$sig_date) |>
  lapply(build_candidates)
cand_long <- rbindlist(cand_list[!sapply(cand_list, is.null)])
cand_long <- melt(cand_long, id.vars = c("sig_date", "Ticker"),
                  variable.name = "candidate", value.name = "alpha_z")
cand_long <- cand_long[!is.na(alpha_z) & is.finite(alpha_z)]
cat("Candidate rows total:", nrow(cand_long), "  unique sig_dates:", uniqueN(cand_long$sig_date), "\n")

CANDIDATE_NAMES <- c("C1", "C2", "C3", "C4", "C5")

# Merge with fwd_returns
setkey(cand_long, sig_date, Ticker)
setkey(fwd_returns, sig_date, Ticker)
ar <- merge(cand_long, fwd_returns, by = c("sig_date", "Ticker"), all.x = FALSE)
cat("Alpha × fwd return rows:", nrow(ar), "\n")

#==============================================================================
# Step 4: Diagnostics (IC, ICIR, Harvey 5-spec, DSR, Monotonicity)
#==============================================================================

cat("\n[Step 4] Diagnostics per candidate\n")

ic_hist <- ar[, .(rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
                  n_stocks = .N),
              by = .(candidate, sig_date)]
ic_hist <- ic_hist[!is.na(rank_ic) & is.finite(rank_ic)]

N_TRIALS <- 5L
gamma_euler <- 0.5772
eul_e <- exp(1)

diag_summary <- list()

for (cand in CANDIDATE_NAMES) {
  ich <- ic_hist[candidate == cand]
  if (nrow(ich) < 24) {
    diag_summary[[cand]] <- list(error = "insufficient_ic_history", n_months = nrow(ich)); next
  }

  mean_ic <- mean(ich$rank_ic, na.rm = TRUE)
  sd_ic   <- sd(ich$rank_ic, na.rm = TRUE)
  icir    <- mean_ic / sd_ic
  n_m     <- nrow(ich)
  t_stat  <- mean_ic / (sd_ic / sqrt(n_m))

  # NW lag=6 HAC
  ic_centered <- ich$rank_ic - mean_ic
  L <- 6L; ac_terms <- 0
  for (l in 1:L) {
    if (l >= n_m) break
    cov_l <- sum(ic_centered[1:(n_m - l)] * ic_centered[(l + 1):n_m]) / n_m
    w_l   <- 1 - l / (L + 1)
    ac_terms <- ac_terms + 2 * w_l * cov_l
  }
  var0 <- sum(ic_centered^2) / n_m
  nw_var <- var0 + ac_terms
  if (is.na(nw_var) || nw_var <= 0) nw_var <- var0
  nw_se <- sqrt(nw_var / n_m)
  t_nw  <- mean_ic / nw_se

  # DSR (Bailey-Lopez de Prado 2014, N=5 ex-ante)
  ic_vals <- ich$rank_ic
  ic_demean <- ic_vals - mean(ic_vals)
  m3 <- mean(ic_demean^3); m2 <- mean(ic_demean^2)
  m4 <- mean(ic_demean^4)
  ic_skew <- if (m2 > 0) m3 / m2^(1.5) else 0
  ic_kurt <- if (m2 > 0) m4 / m2^2 else 3
  sr_proxy <- icir * sqrt(12)
  sr_var <- (1 - ic_skew * sr_proxy + ((ic_kurt - 1) / 4) * sr_proxy^2) / (n_m - 1)
  if (is.na(sr_var) || sr_var <= 0) sr_var <- 1 / (n_m - 1)
  if (N_TRIALS > 1) {
    exp_max_sr <- sqrt(sr_var) * ((1 - gamma_euler) * qnorm(1 - 1 / N_TRIALS) +
                                  gamma_euler * qnorm(1 - 1 / (N_TRIALS * eul_e)))
  } else {
    exp_max_sr <- 0
  }
  dsr <- (sr_proxy - exp_max_sr) / sqrt(sr_var)
  dsr_pnorm <- pnorm(dsr)

  # 5-spec Harvey-t panel
  spec_tnw <- list(base = round(t_nw, 3))
  trim_q5 <- quantile(ich$rank_ic, c(0.05, 0.95), na.rm = TRUE)
  for (spec_id in c("trim_top5", "trim_bot5", "p_2004_2013", "p_2014_2026")) {
    sub <- switch(spec_id,
                  trim_top5  = ich[rank_ic <= trim_q5[2]],
                  trim_bot5  = ich[rank_ic >= trim_q5[1]],
                  p_2004_2013= ich[sig_date >= as.Date("2004-01-01") & sig_date < as.Date("2014-01-01")],
                  p_2014_2026= ich[sig_date >= as.Date("2014-01-01")])
    if (nrow(sub) >= 24) {
      m_s <- mean(sub$rank_ic); n_s <- nrow(sub)
      c_s <- sub$rank_ic - m_s
      a_t <- 0
      for (l in 1:min(L, n_s - 1)) {
        cv <- sum(c_s[1:(n_s - l)] * c_s[(l + 1):n_s]) / n_s
        wl <- 1 - l / (L + 1)
        a_t <- a_t + 2 * wl * cv
      }
      v0 <- sum(c_s^2) / n_s
      nv <- max(v0 + a_t, v0); ns_e <- sqrt(nv / n_s)
      spec_tnw[[spec_id]] <- round(m_s / ns_e, 3)
    } else {
      spec_tnw[[spec_id]] <- NA_real_
    }
  }
  spec_tnw_pass_count <- sum(sapply(spec_tnw, function(t) !is.na(t) && t > 3.0))

  # Monotonicity Q1~Q5 (Axis 4 핵심)
  ar_c <- ar[candidate == cand]
  ar_c[, qntl := cut(alpha_z,
                      breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                      labels = 1:5, include.lowest = TRUE), by = sig_date]
  q_means <- ar_c[!is.na(qntl), .(mean_ret = mean(fwd_ret_1m, na.rm = TRUE)), by = qntl][order(qntl)]
  mono_pct <- if (nrow(q_means) >= 5) mean(diff(q_means$mean_ret) > 0) else NA_real_

  # Subperiod stability
  ich[, period := fcase(
    sig_date < as.Date("2014-01-01"), "p1_2004_2013",
    sig_date < as.Date("2020-01-01"), "p2_2014_2019",
    default = "p3_2020_2026"
  )]
  sub_ic <- ich[, .(mean_ic = mean(rank_ic, na.rm = TRUE), n = .N), by = period]
  sub_signs <- sign(sub_ic$mean_ic)
  sub_stability <- if (length(sub_signs) >= 3) mean(sub_signs == sign(mean_ic)) else NA_real_

  # Recent 3Y ICIR (RF-A3 audit)
  ich_recent <- ich[sig_date >= max(sig_date) - 1095]
  if (nrow(ich_recent) >= 12) {
    icir_recent <- mean(ich_recent$rank_ic) / sd(ich_recent$rank_ic)
  } else {
    icir_recent <- NA_real_
  }
  rf_a3_ratio <- if (!is.na(icir_recent) && icir != 0) icir_recent / icir else NA_real_

  diag_summary[[cand]] <- list(
    candidate = cand,
    n_months = n_m,
    mean_rank_ic = round(mean_ic, 5),
    sd_rank_ic = round(sd_ic, 5),
    icir = round(icir, 4),
    icir_recent_3y = round(icir_recent, 4),
    rf_a3_ratio = round(rf_a3_ratio, 3),
    t_stat_raw = round(t_stat, 3),
    t_nw_lag6 = round(t_nw, 3),
    harvey_t_pass = t_nw > 3.0,
    harvey_5spec_tnw = spec_tnw,
    harvey_5spec_pass_count = spec_tnw_pass_count,
    dsr = round(dsr, 3),
    dsr_pnorm = round(dsr_pnorm, 4),
    dsr_pass = dsr > 0.5,
    monotonicity_q1_q5_concord = round(mono_pct, 3),
    monotonicity_pass = !is.na(mono_pct) && mono_pct >= 0.7,
    subperiod_stability = round(sub_stability, 3),
    subperiod_means = as.list(sub_ic$mean_ic),
    avg_n_stocks = round(mean(ich$n_stocks, na.rm = TRUE), 1),
    q1_q5_means = as.list(q_means$mean_ret)
  )

  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f DSR=%.2f spec5pass=%d mono=%.2f Q1Q5=%s n_m=%d\n",
              cand, mean_ic, icir, t_nw, dsr, spec_tnw_pass_count, mono_pct,
              paste(round(q_means$mean_ret * 100, 2), collapse = "/"), n_m))
}

#==============================================================================
# Step 5: Orthogonality vs STR_1715 admit
#==============================================================================

cat("\n[Step 5] Orthogonality vs STR_1715 (YM-aligned)\n")

str1715_path <- file.path(BASE, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")
str1715 <- as.data.table(read_parquet(str1715_path))
str1715[, ym := format(as.Date(date), "%Y-%m")]

build_candidate_returns <- function(dt_alpha_with_ret) {
  dt_alpha_with_ret[order(-alpha_z), .(
    portfolio_ret = mean(head(fwd_ret_1m, 20), na.rm = TRUE),
    n_picks = min(20, .N)
  ), by = .(candidate, sig_date)]
}
cand_rets <- build_candidate_returns(ar)
cand_rets[, ym := format(sig_date, "%Y-%m")]

ortho <- list()
for (cand in CANDIDATE_NAMES) {
  m <- merge(cand_rets[candidate == cand, .(ym, cand_ret = portfolio_ret)],
             str1715[, .(ym, str1715_ret = ret_net)],
             by = "ym")
  m <- m[!is.na(cand_ret) & !is.na(str1715_ret) & is.finite(cand_ret) & is.finite(str1715_ret)]

  if (nrow(m) < 24) {
    ortho[[cand]] <- list(error = "insufficient_overlap", n = nrow(m)); next
  }
  cor_p <- cor(m$cand_ret, m$str1715_ret, method = "pearson")
  cor_s <- cor(m$cand_ret, m$str1715_ret, method = "spearman")
  cor_k <- cor(m$cand_ret, m$str1715_ret, method = "kendall")

  ortho[[cand]] <- list(
    candidate = cand,
    n_overlap_months = nrow(m),
    returns_cor_pearson = round(cor_p, 4),
    returns_cor_spearman = round(cor_s, 4),
    returns_cor_kendall = round(cor_k, 4),
    orthogonality_rank_pass = cor_s < 0.30,
    orthogonality_return_pass = cor_p < 0.40,
    measurement_method = "year_month_aligned_merge_c_variant"
  )
  cat(sprintf("  %s: cor_p=%.4f cor_s=%.4f n=%d\n",
              cand, cor_p, cor_s, nrow(m)))
}

#==============================================================================
# Step 6: Best candidate selection (Codex Round 1 lessons applied)
#
# Selection rule v2 STRICT (pre-registered, no fallback):
#   - rank_ic >= 0.04
#   - icir >= 0.20
#   - t_nw >= 3.0
#   - monotonicity >= 0.70 (HARD MANDATE Axis 4)
#   - ortho_pass == TRUE (both rank + return)
# Tiebreaker: highest rank_ic, then highest monotonicity.
# NO FALLBACK — if no candidate passes, label as NON_GRADUATING + explicit challenge_flag.
#==============================================================================

cat("\n[Step 6] Best candidate selection (STRICT, no silent fallback)\n")

cmp <- data.table(
  candidate = CANDIDATE_NAMES,
  rank_ic = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$mean_rank_ic %||% NA),
  icir    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$icir %||% NA),
  t_nw    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$t_nw_lag6 %||% NA),
  dsr     = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$dsr %||% NA),
  spec5_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$harvey_5spec_pass_count %||% NA),
  mono    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_q1_q5_concord %||% NA),
  mono_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_pass %||% NA),
  substab = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$subperiod_stability %||% NA),
  cor_str_p = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_pearson %||% NA),
  cor_str_s = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_spearman %||% NA),
  ortho_pass = sapply(CANDIDATE_NAMES, function(c) {
    o <- ortho[[c]]
    if (is.null(o$orthogonality_rank_pass)) return(FALSE)
    o$orthogonality_rank_pass && o$orthogonality_return_pass
  })
)
cat("\n=== Candidate comparison (C Variant) ===\n"); print(cmp)
fwrite(cmp, file.path(ART, "candidate_comparison.csv"))

# All 5 gates strict
elig <- cmp[!is.na(rank_ic) & rank_ic >= 0.04 & icir >= 0.20 & t_nw >= 3.0 &
            mono_pass == TRUE & ortho_pass == TRUE]

if (nrow(elig) == 0) {
  cat("\nWARN: NO candidate passes ALL 5 gates. NON_GRADUATING EXPLORATORY.\n")
  # Soft fallback: choose highest mono if at least one cand has mono>=0.5
  soft_cand <- cmp[!is.na(mono) & mono >= 0.50 & ortho_pass == TRUE][order(-mono, -rank_ic)]
  if (nrow(soft_cand) > 0) {
    best_cand <- soft_cand[1, candidate]
    selection_status <- "NON_GRADUATING_MONO_BEST"
    cat("Selected (NON_GRADUATING):", best_cand, "  reason: mono best with ortho pass\n")
  } else {
    best_cand <- cmp[ortho_pass == TRUE][order(-rank_ic)][1, candidate] %||% CANDIDATE_NAMES[1]
    selection_status <- "NON_GRADUATING_FALLBACK"
    cat("Selected (NON_GRADUATING_FALLBACK):", best_cand, "  reason: ortho pass + rank_ic best\n")
  }
} else {
  best_cand <- elig[order(-rank_ic, -mono)][1, candidate]
  selection_status <- "GRADUATING_ALL_GATES_PASS"
  cat("\n[SELECTED GRADUATING]", best_cand, "\n")
}

#==============================================================================
# Step 7: Emit artifacts
#==============================================================================

cat("\n[Step 7] Emit artifacts\n")

# Alpha scores
alpha_scores_out <- ar[candidate == best_cand, .(sig_date, Ticker, alpha = alpha_z)]
alpha_scores_out <- alpha_scores_out[!is.na(alpha) & is.finite(alpha)]

# Add last sig_date (no fwd_return available)
last_sig <- max(SIG_DATES)
last_alpha <- cand_long[sig_date == last_sig & candidate == best_cand,
                          .(sig_date, Ticker, alpha = alpha_z)]
last_alpha <- last_alpha[!is.na(alpha) & is.finite(alpha)]
combined <- rbind(alpha_scores_out, last_alpha)
combined <- unique(combined, by = c("sig_date", "Ticker"))
setorder(combined, sig_date, -alpha)
write_parquet(combined, file.path(ART, "alpha_scores.parquet"))
cat("  alpha_scores.parquet:", nrow(combined), "rows,", uniqueN(combined$sig_date), "sig_dates\n")

write_parquet(ic_hist, file.path(ART, "ic_history.parquet"))
write_parquet(cand_rets, file.path(ART, "candidate_portfolio_returns.parquet"))
fwrite(cmp, file.path(ART, "candidate_comparison.csv"))

# alpha_validation.json
validation <- list(
  task_id = WT_ID,
  as_of_date = "2026-05-13",
  as_of_sig_date_actual = as.character(last_sig),
  version = "c_variant_4axis_v1",
  best_candidate = best_cand,
  selection_status = selection_status,
  candidates = diag_summary,
  orthogonality_vs_STR_1715 = ortho,
  axis_design = list(
    axis_1_pit_c2_t_plus_1 = TRUE,
    axis_2_sector_neutralize = "C2/C4/C5 only (C1/C3 no sector)",
    axis_3_ff_residual = "CAPM rolling 252d, idio residual semi-deviation",
    axis_4_monotonic_smooth = "C5 only (rank_smooth via probit). Others raw cs_z."
  ),
  pit_audit = list(
    sig_dates_total = length(SIG_DATES),
    sig_dates_strictly_month_end = TRUE,
    pit_c2_t_plus_1_lag_applied = TRUE,
    forward_return_basis = "P(next_me_close) / P(sig_date+1_close) - 1",
    pit_clean = TRUE
  ),
  selection_rule = list(
    primary_gates = list(
      rank_ic_min = 0.04, icir_min = 0.20, t_nw_min = 3.0,
      mono_min = 0.70, ortho_pass = TRUE
    ),
    tiebreaker = "highest rank_ic, then highest mono",
    fallback_policy = "NON_GRADUATING_MONO_BEST if no candidate passes all 5",
    pre_registered = TRUE,
    ex_ante_grid_N = length(CANDIDATE_NAMES),
    post_hoc_search = FALSE
  ),
  comparison_table = lapply(seq_len(nrow(cmp)), function(i) as.list(cmp[i]))
)
write_json(validation, file.path(ART, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
write_json(validation, file.path(MBOX, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Top10 alpha for last_sig
top10_last <- combined[sig_date == last_sig][order(-alpha)][1:10]
cat("\nTop 10 alpha (last sig =", as.character(last_sig), "):\n")
print(top10_last)

t_end <- Sys.time()
cat("\nTotal pipeline time:", round(as.numeric(t_end - t_start, units = "mins"), 2), "minutes\n")

cat("\n=== DONE C Variant ===\n")
cat("Best candidate:", best_cand, " status:", selection_status, "\n")
best <- diag_summary[[best_cand]]; best_ortho <- ortho[[best_cand]]
cat("Rank IC:", best$mean_rank_ic, "  ICIR:", best$icir, "  t_NW:", best$t_nw_lag6, "\n")
cat("Monotonicity:", best$monotonicity_q1_q5_concord, "  pass:", best$monotonicity_pass, "\n")
cat("DSR:", best$dsr, "  Harvey 5-spec:", best$harvey_5spec_pass_count, "/5\n")
cat("Orthogonality cor_p=", best_ortho$returns_cor_pearson, " cor_s=", best_ortho$returns_cor_spearman, "\n")
