#==============================================================================
# CREATIVE SCREEN — Hawkes Self-Excitation of Smart-Money Flow
#
# Idea: model daily smart-money (Foreign+Institutional) NET-BUY arrivals as a
#       self-exciting (Hawkes) point process per ticker:
#           lambda(t) = mu + sum_{t_i < t} alpha * exp(-beta*(t - t_i))
#       branching ratio  n = alpha/beta  (flow-clustering persistence)
#       residual intensity slope = recent rise/fall of the exciting term.
#
# We DO NOT run full per-ticker MLE (unstable on short noisy daily series).
# Instead we use a LIGHTWEIGHT recursive intensity (Ozaki recursion) on a
# fixed decay grid for beta, choose beta by recursive pseudo-likelihood, and
# read off a stable branching ratio + intensity slope. This is the "cheap"
# screen estimator; a full MLE belongs to formal research only if this passes.
#
# SCREEN ONLY: read-only signal -> forward Rank-IC / ICIR / Harvey-t(NW on
#   rank-IC series) + orthogonality (residual IC after INV01/INV05/INV09) +
#   subperiod stability. NO backtest, NO portfolio, NO admission.
#
# PIT: all flow features use Date < sig_date (strict t-1, C2). Forward label
#   only looks forward. Lockbox 2023-12-22 strict (normal research).
#   shift convention: forward return = shift(Close, n=H, type="lead")/Close-1.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(dplyr); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_CREATIVE_SCREEN", "hawkes_flow_self_excitation")
set.seed(42)

LOCKBOX_CUTOFF <- as.Date("2023-12-22")  # normal-research lockbox (strict)
H_FWD          <- 21L                     # forward holding horizon (~1 month)
HAWKES_WIN     <- 250L                    # daily history window for Hawkes fit
MIN_FLOW_OBS   <- 120L                    # min usable daily flow obs per ticker
LIQ_THRESHOLD  <- 2e8                     # 20d avg traded value (PIT t-1)
N_MIN_CS       <- 40L                     # min names per cross-section

cat("=== Hawkes Smart-Money Self-Excitation SCREEN ===\n")
cat("Lockbox cutoff:", as.character(LOCKBOX_CUTOFF), " | H_FWD:", H_FWD, "\n")

#-----------------------------------------------------------------------------#
# 1. Load data (read-only)                                                     #
#-----------------------------------------------------------------------------#
cat("[1] loading investor_wide + RAWDATA ...\n")
INV <- as.data.table(read_parquet(file.path(PROJ, ".cache/investor_stock/investor_wide.parquet")))
INV[, Date := as.Date(Date)]
setkey(INV, Ticker, Date)

# RAWDATA: only the columns we need, only dates we need (post-2009 for speed/coverage)
rd_ds <- open_dataset(file.path(PROJ, ".cache/RAWDATA.parquet"))
RAW <- rd_ds |>
  filter(Date >= as.Date("2010-01-01")) |>
  select(Date, Ticker, K200, KQ150, Size, Close, Vol, Ret) |>
  collect() |> as.data.table()
RAW[, Date := as.Date(Date)]
setkey(RAW, Ticker, Date)
cat("    INV rows:", nrow(INV), " RAW rows:", nrow(RAW), "\n")

# Smart money daily net buy + binary buy "event"
INV[, smart := Foreign + Institutional]
INV[, ev := as.integer(!is.na(smart) & smart > 0)]   # net-buy event

#-----------------------------------------------------------------------------#
# 2. Lightweight Hawkes recursive estimator (Ozaki recursion)                  #
#    For an exponential kernel alpha*exp(-beta*dt), the recursive sum          #
#       A_i = exp(-beta*(t_i - t_{i-1})) * (1 + A_{i-1})                        #
#    Intensity just before event i: lambda_i = mu + alpha * A_i                #
#    We choose beta from a small grid by maximizing a recursive Poisson        #
#    pseudo-likelihood; given beta we get closed-form-ish mu, alpha via simple #
#    moment fit. Returns branching ratio n=alpha/beta and recent slope.        #
#    Time unit = trading days (event times = day index of net-buy days).       #
#-----------------------------------------------------------------------------#
hawkes_features <- function(ev_vec) {
  # ev_vec: integer 0/1 over consecutive trading days (chronological, oldest first)
  T_len <- length(ev_vec)
  if (T_len < 60L) return(NULL)
  t_idx <- which(ev_vec == 1L)           # event day indices (1..T)
  k <- length(t_idx)
  base_rate <- k / T_len
  if (k < 10L || base_rate <= 0 || base_rate >= 1) return(NULL)

  # candidate decay rates (per day). n must be < 1 for stationarity.
  beta_grid <- c(0.10, 0.20, 0.35, 0.50, 0.80, 1.20)
  best <- list(ll = -Inf)

  for (beta in beta_grid) {
    # recursion A_i for excitation at each event time (Ogata/Ozaki)
    A <- numeric(k)
    if (k >= 2L) for (i in 2:k) {
      A[i] <- exp(-beta * (t_idx[i] - t_idx[i-1])) * (1 + A[i-1])
    }
    # moment-style fit: mean intensity at events ~= mu + alpha*mean(A)
    # constrain mu>0, alpha>0; use grid over branching ratio share s in (0,1)
    mA <- mean(A)
    # total compensator over [1,T]: int lambda = mu*T + (alpha/beta)*sum(1-exp(-beta*(T - t_i)))
    decay_tail <- sum(1 - exp(-beta * (T_len - t_idx)))
    # try a few splits of base intensity between background and self-excitation
    for (s in c(0.1, 0.25, 0.4, 0.55, 0.7, 0.85)) {
      # s = fraction of events attributable to self-excitation (branching ratio proxy)
      n_br <- s                              # branching ratio target
      alpha <- n_br * beta
      mu <- base_rate * (1 - n_br)
      if (mu <= 0) next
      lam_i <- mu + alpha * A                # intensity just before each event
      if (any(lam_i <= 0)) next
      # Poisson-process log-likelihood: sum log lambda_i - integral lambda
      integral <- mu * T_len + alpha / beta * decay_tail
      ll <- sum(log(lam_i)) - integral
      if (is.finite(ll) && ll > best$ll) {
        best <- list(ll = ll, beta = beta, alpha = alpha, mu = mu,
                     n_br = n_br, A = A, lam_i = lam_i)
      }
    }
  }
  if (!is.finite(best$ll)) return(NULL)

  beta <- best$beta; alpha <- best$alpha; mu <- best$mu

  # residual intensity (self-excitation term) over a recent vs prior window,
  # evaluated on the day grid (not only event days) for a smooth slope.
  # excitation(t) = alpha * sum_{t_i < t} exp(-beta*(t - t_i))
  exc <- numeric(T_len)
  carry <- 0
  prev_day <- 0L
  ei <- 1L
  # build day-by-day excitation via decay carry
  last_t <- 0L
  acc <- 0
  for (d in 1:T_len) {
    # decay accumulator from previous day
    if (d > 1L) acc <- acc * exp(-beta)
    exc[d] <- alpha * acc
    if (ev_vec[d] == 1L) acc <- acc + 1  # event today contributes to FUTURE days
  }
  # residual intensity slope: recent 21d mean exc vs prior 21d mean exc
  if (T_len >= 63L) {
    recent <- mean(exc[(T_len - 20L):T_len])
    prior  <- mean(exc[(T_len - 41L):(T_len - 21L)])
    slope  <- recent - prior
    rising <- as.integer(slope > 0)
  } else { recent <- exc[T_len]; prior <- NA_real_; slope <- NA_real_; rising <- NA_integer_ }

  resid_intensity_now <- exc[T_len]    # current excitation level

  list(
    branching_ratio = best$n_br,
    beta = beta,
    resid_intensity = resid_intensity_now,
    intensity_slope = slope,
    rising = rising,
    base_rate = base_rate,
    n_events = length(t_idx)
  )
}

#-----------------------------------------------------------------------------#
# 3. Control factors INV01 / INV05 / INV09 (raw, PIT t-1) computed inline      #
#    from the SAME daily history window so they share the as-of timing.        #
#-----------------------------------------------------------------------------#
control_factors <- function(sub, size_val) {
  # sub: ticker daily history (chronological) with cols Foreign, Institutional, smart
  n <- nrow(sub)
  if (n < 60L) return(list(INV01=NA, INV05=NA, INV09=NA))
  F20 <- sum(tail(sub$Foreign, 20L), na.rm=TRUE)
  F60 <- sum(tail(sub$Foreign, 60L), na.rm=TRUE)
  inv01 <- if (!is.na(size_val) && size_val > 0) F20 / size_val else NA_real_
  inv05 <- if (abs(F60) > 1e8) F20 / F60 - 1 else NA_real_
  inv09 <- mean(tail(as.integer(sub$smart > 0), 20L), na.rm=TRUE)  # frac of last 20d F+I>0
  list(INV01 = inv01, INV05 = inv05, INV09 = inv09)
}

#-----------------------------------------------------------------------------#
# 4. sig_dates: month-end trading dates in [2012, lockbox], + liquidity        #
#-----------------------------------------------------------------------------#
trade_dates <- sort(unique(RAW$Date))
trade_dates <- trade_dates[trade_dates <= LOCKBOX_CUTOFF & trade_dates >= as.Date("2012-01-01")]
RAW[, ym := format(Date, "%Y-%m")]
me <- RAW[Date <= LOCKBOX_CUTOFF & Date >= as.Date("2012-01-01"),
          .(Date = max(Date)), by = ym]$Date
sig_dates <- sort(unique(me))
cat("[4] sig_dates:", length(sig_dates), " from", as.character(min(sig_dates)),
    "to", as.character(max(sig_dates)), "\n")

# precompute 20d avg traded value (Vol*Close proxy) for liquidity, PIT t-1
RAW[, tval := Vol * Close]
setorder(RAW, Ticker, Date)
RAW[, liq20 := frollmean(tval, 20L, align = "right"), by = Ticker]

#-----------------------------------------------------------------------------#
# 5. Build signal panel: for each sig_date x universe ticker compute Hawkes    #
#-----------------------------------------------------------------------------#
cat("[5] computing Hawkes signal panel (this is the heavy step)...\n")

# index INV by ticker for fast subset
setkey(INV, Ticker, Date)
setkey(RAW, Ticker, Date)

panel <- vector("list", length(sig_dates))
for (si in seq_along(sig_dates)) {
  sd <- sig_dates[si]
  # universe at sig_date (most recent membership row on/just before sd)
  uni <- RAW[Date == sd & (K200 == 1 | KQ150 == 1) & !is.na(liq20) & liq20 >= LIQ_THRESHOLD,
             .(Ticker, Size)]
  if (nrow(uni) < N_MIN_CS) next
  tickers <- uni$Ticker

  rows <- vector("list", length(tickers))
  for (ti in seq_along(tickers)) {
    tk <- tickers[ti]
    # PIT: strictly before sig_date
    sub <- INV[.(tk)][Date < sd]
    if (nrow(sub) < MIN_FLOW_OBS) next
    sub <- tail(sub[order(Date)], HAWKES_WIN)
    # need contiguous-ish daily series; use ev vector in date order
    hk <- hawkes_features(sub$ev)
    if (is.null(hk)) next
    size_val <- uni$Size[ti]
    ctrl <- control_factors(sub, size_val)
    rows[[ti]] <- data.table(
      sig_date = sd, Ticker = tk,
      branching_ratio = hk$branching_ratio,
      resid_intensity = hk$resid_intensity,
      intensity_slope = hk$intensity_slope,
      rising = hk$rising,
      base_rate = hk$base_rate,
      INV01 = ctrl$INV01, INV05 = ctrl$INV05, INV09 = ctrl$INV09
    )
  }
  rows <- rbindlist(rows[!sapply(rows, is.null)], use.names = TRUE, fill = TRUE)
  if (nrow(rows) >= N_MIN_CS) panel[[si]] <- rows
  if (si %% 12L == 0L) cat("    ...", as.character(sd), " cum names:",
                            sum(sapply(panel[1:si], function(x) if(is.null(x)) 0 else nrow(x))), "\n")
}
panel <- rbindlist(panel[!sapply(panel, is.null)], use.names = TRUE, fill = TRUE)
cat("[5] panel rows:", nrow(panel), " sig_dates:", uniqueN(panel$sig_date), "\n")
stopifnot(nrow(panel) > 0)

# Composite Hawkes signal: rising self-excitation * branching persistence.
# Cross-sectional z within each sig_date so components are comparable.
zc <- function(x) { m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-12) return(rep(0,length(x))); (x-m)/s }
panel[, z_branch := zc(branching_ratio), by = sig_date]
panel[, z_slope  := zc(intensity_slope), by = sig_date]
panel[, z_resid  := zc(resid_intensity), by = sig_date]
# signal: persistence (branching) + rising-turn (slope) emphasis
panel[, hawkes_signal := 0.5 * z_branch + 0.5 * z_slope]

#-----------------------------------------------------------------------------#
# 6. Forward H-day return label (PIT-safe, shift lead convention)              #
#    forward ret r(t->t+H) per ticker = Close[t+H]/Close[t] - 1                #
#-----------------------------------------------------------------------------#
cat("[6] computing forward", H_FWD, "day returns...\n")
setorder(RAW, Ticker, Date)
RAW[, fwd_close := shift(Close, n = H_FWD, type = "lead"), by = Ticker]   # Close[t+H]
RAW[, fwd_ret := fwd_close / Close - 1]
fwd <- RAW[, .(Ticker, sig_date = Date, fwd_ret)]
setkey(fwd, Ticker, sig_date)
setkey(panel, Ticker, sig_date)
panel <- merge(panel, fwd, by = c("Ticker", "sig_date"), all.x = TRUE)
panel <- panel[is.finite(fwd_ret) & is.finite(hawkes_signal)]
cat("    panel with label:", nrow(panel), "\n")

#-----------------------------------------------------------------------------#
# 7. Rank-IC time series + ICIR + Harvey-t (Newey-West) + subperiod stability  #
#-----------------------------------------------------------------------------#
ic_ts <- panel[, .(
  ic = if (.N >= N_MIN_CS) suppressWarnings(cor(hawkes_signal, fwd_ret, method = "spearman", use="complete.obs")) else NA_real_,
  n  = .N
), by = sig_date][is.finite(ic)][order(sig_date)]

rank_ic <- mean(ic_ts$ic)
sd_ic   <- sd(ic_ts$ic)
icir    <- rank_ic / sd_ic
N_obs   <- nrow(ic_ts)
naive_t <- icir * sqrt(N_obs)

# Harvey-t: Newey-West HAC t-stat on the rank-IC series (regress IC ~ 1)
suppressPackageStartupMessages({ library(sandwich); library(lmtest) })
fit <- lm(ic ~ 1, data = ic_ts)
nw_lag <- floor(4 * (N_obs/100)^(2/9))
nw_vcov <- sandwich::NeweyWest(fit, lag = nw_lag, prewhite = FALSE, adjust = TRUE)
harvey_t <- unname(coef(fit)[1] / sqrt(nw_vcov[1,1]))

# subperiod stability: split IC series into halves, report min/mean ratio
half <- floor(N_obs/2)
ic_h1 <- mean(ic_ts$ic[1:half]); ic_h2 <- mean(ic_ts$ic[(half+1):N_obs])
sub_stability <- if (rank_ic != 0) min(ic_h1, ic_h2) / rank_ic else NA_real_
# also a per-year stability fraction (share of years with same-sign IC)
ic_ts[, yr := format(sig_date, "%Y")]
yr_ic <- ic_ts[, .(ic = mean(ic)), by = yr]
sign_consistency <- mean(sign(yr_ic$ic) == sign(rank_ic))

cat(sprintf("[7] rank-IC=%.4f  ICIR=%.3f  naive_t=%.2f  Harvey_t(NW,lag=%d)=%.2f  N=%d\n",
            rank_ic, icir, naive_t, nw_lag, harvey_t, N_obs))
cat(sprintf("    subperiod: H1=%.4f H2=%.4f  min/mean=%.2f  yr sign-consistency=%.2f\n",
            ic_h1, ic_h2, sub_stability, sign_consistency))

#-----------------------------------------------------------------------------#
# 8. Orthogonality: residual IC after controlling INV01/INV05/INV09           #
#    Per sig_date: orthogonalize hawkes_signal against {INV01,INV05,INV09}     #
#    (cross-sectional OLS), take residual, then rank-IC of residual vs fwd_ret #
#    This is the INCREMENTAL/residual IC (Hawkes beyond flow level/mom/persist)#
#-----------------------------------------------------------------------------#
cat("[8] orthogonality vs INV01/INV05/INV09 ...\n")
panel[, z_inv01 := zc(INV01), by = sig_date]
panel[, z_inv05 := zc(INV05), by = sig_date]
panel[, z_inv09 := zc(INV09), by = sig_date]

resid_ic_ts <- panel[, {
  d <- .SD[is.finite(hawkes_signal) & is.finite(z_inv01) & is.finite(z_inv05) &
             is.finite(z_inv09) & is.finite(fwd_ret)]
  if (nrow(d) >= N_MIN_CS) {
    r <- tryCatch({
      m <- lm(hawkes_signal ~ z_inv01 + z_inv05 + z_inv09, data = d)
      res <- residuals(m)
      suppressWarnings(cor(res, d$fwd_ret, method = "spearman"))
    }, error = function(e) NA_real_)
    .(resid_ic = r, n = nrow(d))
  } else .(resid_ic = NA_real_, n = nrow(d))
}, by = sig_date][is.finite(resid_ic)][order(sig_date)]

resid_rank_ic <- mean(resid_ic_ts$resid_ic)
resid_icir <- resid_rank_ic / sd(resid_ic_ts$resid_ic)
fit2 <- lm(resid_ic ~ 1, data = resid_ic_ts)
nw2 <- sandwich::NeweyWest(fit2, lag = floor(4*(nrow(resid_ic_ts)/100)^(2/9)), prewhite=FALSE, adjust=TRUE)
resid_harvey_t <- unname(coef(fit2)[1] / sqrt(nw2[1,1]))

# correlation of raw hawkes signal vs controls (pooled, for diagnostics)
corr_inv01 <- panel[is.finite(hawkes_signal)&is.finite(INV01), cor(hawkes_signal, INV01, method="spearman")]
corr_inv05 <- panel[is.finite(hawkes_signal)&is.finite(INV05), cor(hawkes_signal, INV05, method="spearman")]
corr_inv09 <- panel[is.finite(hawkes_signal)&is.finite(INV09), cor(hawkes_signal, INV09, method="spearman")]

# also raw univariate IC of each control for context
ctrl_ic <- function(col) {
  s <- panel[, {
    d <- .SD[is.finite(get(col)) & is.finite(fwd_ret)]
    if (nrow(d) >= N_MIN_CS) .(ic = suppressWarnings(cor(d[[col]], d$fwd_ret, method="spearman"))) else .(ic=NA_real_)
  }, by=sig_date][is.finite(ic)]
  mean(s$ic)
}
ic_inv01 <- ctrl_ic("INV01"); ic_inv05 <- ctrl_ic("INV05"); ic_inv09 <- ctrl_ic("INV09")

cat(sprintf("    residual rank-IC=%.4f  ICIR=%.3f  Harvey_t=%.2f  (vs raw %.4f)\n",
            resid_rank_ic, resid_icir, resid_harvey_t, rank_ic))
cat(sprintf("    spearman corr signal~INV01=%.2f INV05=%.2f INV09=%.2f\n",
            corr_inv01, corr_inv05, corr_inv09))
cat(sprintf("    control raw IC: INV01=%.4f INV05=%.4f INV09=%.4f\n", ic_inv01, ic_inv05, ic_inv09))

#-----------------------------------------------------------------------------#
# 9. Write screen JSON + IC series CSV                                         #
#-----------------------------------------------------------------------------#
screen <- list(
  idea = "Hawkes self-excitation of smart-money (Foreign+Institutional) daily net-buy: branching ratio (clustering persistence) + residual-intensity rising-turn as cross-sectional long ranking signal.",
  estimator = "lightweight Ozaki/Ogata recursive exponential-kernel Hawkes (beta grid + Poisson pseudo-likelihood + branching-ratio split). NOT full MLE.",
  data_feasible = TRUE,
  universe = "KOSPI200 union KOSDAQ150 (K200==1 | KQ150==1), liq20>=2e8",
  horizon_days = H_FWD,
  lockbox_cutoff = as.character(LOCKBOX_CUTOFF),
  n_obs_panel = nrow(panel),
  n_sig_dates = N_obs,
  rank_ic = round(rank_ic, 5),
  icir = round(icir, 4),
  naive_t = round(naive_t, 3),
  harvey_t_rankic_NW = round(harvey_t, 3),
  nw_lag = nw_lag,
  subperiod = list(h1_ic = round(ic_h1,5), h2_ic = round(ic_h2,5),
                   min_over_mean = round(sub_stability,3),
                   yearly_sign_consistency = round(sign_consistency,3)),
  orthogonality = list(
    controls = c("INV01_Foreign_NetBuy_20d","INV05_Foreign_Momentum","INV09_Flow_Persistence"),
    residual_rank_ic = round(resid_rank_ic,5),
    residual_icir = round(resid_icir,4),
    residual_harvey_t = round(resid_harvey_t,3),
    retention_ratio = round(ifelse(rank_ic!=0, resid_rank_ic/rank_ic, NA),3),
    spearman_corr = list(INV01=round(corr_inv01,3), INV05=round(corr_inv05,3), INV09=round(corr_inv09,3)),
    control_raw_ic = list(INV01=round(ic_inv01,5), INV05=round(ic_inv05,5), INV09=round(ic_inv09,5))
  ),
  pit_notes = "features Date<sig_date (C2 strict); forward label shift(Close,n=H,type='lead'); lockbox<=2023-12-22; Usable_Date<=sig_date.",
  caveat = "rank-IC is SCREEN/advisory, NOT tradeable alpha (Cycle2: rank-IC t >> portfolio-alpha t). Pass => recommend formal canonical_screen_bt + forge.",
  generated = as.character(Sys.time())
)
write_json(screen, file.path(OUT, "screen_result.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
fwrite(ic_ts, file.path(OUT, "rank_ic_timeseries.csv"))
fwrite(resid_ic_ts, file.path(OUT, "residual_ic_timeseries.csv"))
fwrite(panel[, .(sig_date, Ticker, branching_ratio, resid_intensity, intensity_slope,
                 hawkes_signal, INV01, INV05, INV09, fwd_ret)],
       file.path(OUT, "signal_panel_sample.csv"))

cat("\n[DONE] wrote screen_result.json + 3 CSVs to:\n  ", OUT, "\n")
cat(toJSON(screen, auto_unbox=TRUE, pretty=TRUE, digits=6), "\n")
