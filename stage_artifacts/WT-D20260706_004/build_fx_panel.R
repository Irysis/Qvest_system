# build_fx_panel.R — WT-D20260706_004 Alpha Research
# Hypothesis: rolling KRW/USD-beta (export-sensitivity) factor, regime-conditional on KRW trend.
#
# Outputs (stage_artifacts/WT-D20260706_004/panel/):
#   fx_scores_monthly.parquet   Date, Ticker, beta_fx, beta_fx_2f, beta_mkt, r2   (signal at month-end t, PIT)
#   returns_monthly.parquet     Date, Ticker, Ret_1m                              (FORWARD 1M realized)
#   benchmark_capw.parquet      Date, BM_Ret                                      (KOSPI200 cap-w total return, forward)
#   benchmark_ew.parquet        Date, BM_Ret                                      (EW universe benchmark, forward — mega-cap diagnostic)
#   universe_flags.parquet      Date, Ticker, in_univ, adv20, Size
#   regime_monthly.parquet      Date, krw_usd, krw_ma12, regime (WEAK/STRONG), krw_mom12   (t-observable, no look-ahead)
#
# PIT DESIGN (C1/C2/C10/C11/C14):
#   - FX-beta: per ticker, rolling regression of DAILY excess return on [market return, KRW/USD log-change]
#     over trailing window ENDING at month-end t (60/120/250 trading days). NO full-sample beta (C1).
#     KRW/USD is observed at t (macro, published same-day/next-day — C11: FX spot is contemporaneous, PIT-safe).
#   - Regime label at month t = KRW/USD vs its trailing 12m MA (both computed on data <= t). t-observable.
#     Regime used to CONDITION next-month selection => regime@t drives holding over (t->t+1). No look-ahead.
#   - Forward return Ret_1m = realized (t -> t+1). Universe/ADV at t (C10).

suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260706_004/panel")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

LIQ_MIN <- 2e8   # headline canonical liquidity floor (헌법 2e8). request.json 5e7은 WT-scoped 하한이나 canonical은 2e8 사용.

# ---- 1. RAWDATA daily ----
cat("[fxpanel] loading RAWDATA...\n"); flush.console()
RAW_SCRATCH <- Sys.getenv("RAW_SCRATCH", "")
raw_path <- if (nzchar(RAW_SCRATCH) && file.exists(file.path(RAW_SCRATCH, "RAWDATA.parquet")))
              file.path(RAW_SCRATCH, "RAWDATA.parquet") else ".cache/RAWDATA.parquet"
cat("[fxpanel] raw_path =", raw_path, "\n"); flush.console()
rd <- as.data.table(read_parquet(raw_path))
cat("[fxpanel] rd loaded:", nrow(rd), "rows\n"); flush.console()
rd <- rd[, .(Date, Ticker, K200, KQ150, Close, Vol, Size, Ret, BM_Ret)]
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
cat("[fxpanel] rd sorted\n"); flush.console()

# ---- 2. KRW/USD daily -> daily log change, merge to trading calendar ----
fx <- as.data.table(read_parquet(".cache/ecos_krw_usd.parquet"))
setnames(fx, "KRW_USD", "krw")
fx[, Date := as.Date(Date)]
setorder(fx, Date)
fx[, dlkrw := log(krw) - log(shift(krw, 1))]   # daily KRW/USD log change (>0 = KRW weakening / USD up)

# market daily return proxy = BM_Ret (KOSPI200 index daily return, one per date)
mkt <- unique(rd[!is.na(BM_Ret), .(Date, mkt_ret = BM_Ret)], by = "Date")
setorder(mkt, Date)

# join fx daily change + mkt onto each ticker's daily row (fx spot forward-filled to trading days)
setkey(fx, Date); setkey(mkt, Date)
# forward-fill fx to trading dates (rolling join)
rd_dates <- data.table(Date = sort(unique(rd$Date))); setkey(rd_dates, Date)
fx_tr <- fx[rd_dates, roll = TRUE]                  # krw, dlkrw on trading dates
# dlkrw on trading calendar: recompute from forward-filled krw to avoid gap distortion
setorder(fx_tr, Date)
fx_tr[, dlkrw := log(krw) - log(shift(krw, 1))]
fx_tr <- fx_tr[, .(Date, krw, dlkrw)]

cat("[fxpanel] fx_tr/mkt built, merging...\n"); flush.console()
rd <- merge(rd, fx_tr, by = "Date", all.x = TRUE)
rd <- merge(rd, mkt,  by = "Date", all.x = TRUE)
setorder(rd, Ticker, Date)
cat("[fxpanel] merged fx+mkt\n"); flush.console()

# ---- 3. month key + month-end rows + adv20 + monthly forward return ----
rd[, ym := as.Date(cut(Date, "month"))]
rd[, dvalue := Close * Vol]
rd[, adv20 := frollmean(dvalue, 20, align = "right"), by = Ticker]

# month-end row indices per ticker-month (vectorized)
rd[, .grp := .GRP, by = .(Ticker, ym)]
is_last <- rd[, .I[.N], by = .grp]$V1
me <- rd[is_last]
rd[, .grp := NULL]

setorder(me, Ticker, ym)
me[, close_prev := shift(Close, 1), by = Ticker]
me[, mret := Close / close_prev - 1]
me[, Ret_1m := shift(mret, -1), by = Ticker]           # forward 1M realized
me[, in_univ := (K200 == TRUE | KQ150 == TRUE)]

# ---- 4. rolling FX-beta per ticker at each month-end (PIT: window ends at t) ----
# Two-factor daily regression: r_i,d = a + b_mkt*mkt_d + b_fx*dlkrw_d + e, over trailing WINDOW days ending month-end t.
# Also a 1-factor FX beta (r_i on dlkrw) for comparison.
WINDOWS <- c(120L)   # ~6 trading-months. (robustness 60/250 as secondary — run separately)
cat("[fxpanel] computing rolling 2-factor FX-betas (window=120d)...\n")

# We compute per ticker over its daily series, at each month-end index, using trailing WINDOW rows.
# Vectorized-ish: loop tickers (≈350-700), inner rolling via matrix algebra on trailing slice.
setorder(rd, Ticker, Date)
rd[, dret := Ret]   # daily total return

roll_fx_beta <- function(dt_tk, win = 120L, min_obs = 80L) {
  # dt_tk: one ticker, sorted by Date, cols Date, ym, dret, mkt_ret, dlkrw
  n <- nrow(dt_tk)
  # month-end indices
  me_idx <- dt_tk[, .I[.N], by = ym]$V1
  out <- vector("list", length(me_idx))
  y_all <- dt_tk$dret; x1 <- dt_tk$mkt_ret; x2 <- dt_tk$dlkrw
  for (k in seq_along(me_idx)) {
    ei <- me_idx[k]; si <- ei - win + 1L
    if (si < 1L) { out[[k]] <- NULL; next }
    yy <- y_all[si:ei]; a1 <- x1[si:ei]; a2 <- x2[si:ei]
    ok <- is.finite(yy) & is.finite(a1) & is.finite(a2)
    if (sum(ok) < min_obs) { out[[k]] <- NULL; next }
    yy <- yy[ok]; a1 <- a1[ok]; a2 <- a2[ok]
    # 2-factor OLS
    X <- cbind(1, a1, a2)
    cf <- tryCatch(qr.solve(crossprod(X), crossprod(X, yy)), error = function(e) rep(NA_real_, 3))
    yhat <- X %*% cf
    ss_res <- sum((yy - yhat)^2); ss_tot <- sum((yy - mean(yy))^2)
    r2 <- if (ss_tot > 0) 1 - ss_res/ss_tot else NA_real_
    # 1-factor FX beta (univariate)
    b_fx_uni <- tryCatch(cov(yy, a2) / var(a2), error = function(e) NA_real_)
    out[[k]] <- data.table(ym = dt_tk$ym[ei],
                           beta_mkt = cf[2], beta_fx_2f = cf[3],
                           beta_fx = b_fx_uni, r2 = r2)
  }
  rbindlist(out)
}

tickers <- unique(rd$Ticker)
cat("[fxpanel] tickers:", length(tickers), "\n")
beta_list <- vector("list", length(tickers))
for (j in seq_along(tickers)) {
  tk <- tickers[j]
  dt_tk <- rd[Ticker == tk, .(Date, ym, dret, mkt_ret, dlkrw)]
  if (nrow(dt_tk) < 100L) next
  b <- roll_fx_beta(dt_tk, win = WINDOWS[1])
  if (!is.null(b) && nrow(b) > 0) { b[, Ticker := tk]; beta_list[[j]] <- b }
  if (j %% 100 == 0) cat("  ", j, "/", length(tickers), "\n")
}
betas <- rbindlist(beta_list, fill = TRUE)
cat("[fxpanel] beta rows:", nrow(betas), " months:", uniqueN(betas$ym), "\n")

# ---- 5. assemble monthly signal panel (signal at month-end t) ----
fx_scores <- merge(me[in_univ == TRUE, .(ym, Ticker, Size, adv20, in_univ)],
                   betas, by = c("ym","Ticker"), all.x = FALSE)
fx_scores <- fx_scores[, .(Date = ym, Ticker, beta_fx, beta_fx_2f, beta_mkt, r2, Size, adv20)]

# ---- 6. returns / universe / benchmarks (cap-w and EW) ----
returns_monthly <- me[!is.na(Ret_1m) & in_univ == TRUE, .(Date = ym, Ticker, Ret_1m)]
universe_flags  <- me[in_univ == TRUE, .(Date = ym, Ticker, in_univ, adv20, Size)]

# cap-w benchmark = KOSPI200 total return (compound daily BM_Ret to monthly, forward-shift)
bm <- unique(rd[!is.na(BM_Ret), .(Date, ym, BM_Ret)], by = "Date")
bm_m <- bm[, .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]  # panel-construction compound (not a strategy return)
setorder(bm_m, ym)
bm_m[, BM_Ret_fwd := shift(bm_mret, -1)]
benchmark_capw <- bm_m[!is.na(BM_Ret_fwd), .(Date = ym, BM_Ret = BM_Ret_fwd)]

# EW benchmark = equal-weight of ALL universe names' forward return (mega-cap diagnostic)
ew <- returns_monthly[, .(BM_Ret = mean(Ret_1m, na.rm = TRUE)), by = Date]
benchmark_ew <- ew[, .(Date, BM_Ret)]

# ---- 7. regime label (t-observable KRW trend) ----
# monthly KRW/USD level at month-end, 12m MA, momentum. regime = WEAK (krw > MA, weakening) / STRONG.
fx[, ym := as.Date(cut(Date, "month"))]
fx_me <- fx[, .SD[.N], by = ym][, .(Date = ym, krw_usd = krw)]
setorder(fx_me, Date)
fx_me[, krw_ma12 := frollmean(krw_usd, 12, align = "right")]
fx_me[, krw_lag12 := shift(krw_usd, 12)]
fx_me[, krw_mom12 := krw_usd / krw_lag12 - 1]
fx_me[, regime := fifelse(is.na(krw_ma12), NA_character_,
                          fifelse(krw_usd >= krw_ma12, "WEAK", "STRONG"))]  # WEAK = KRW above MA = weakening
regime_monthly <- fx_me[, .(Date, krw_usd, krw_ma12, krw_mom12, regime)]

# ---- write ----
write_parquet(fx_scores,        file.path(OUT, "fx_scores_monthly.parquet"))
write_parquet(returns_monthly,  file.path(OUT, "returns_monthly.parquet"))
write_parquet(benchmark_capw,   file.path(OUT, "benchmark_capw.parquet"))
write_parquet(benchmark_ew,     file.path(OUT, "benchmark_ew.parquet"))
write_parquet(universe_flags,   file.path(OUT, "universe_flags.parquet"))
write_parquet(regime_monthly,   file.path(OUT, "regime_monthly.parquet"))

cat(sprintf("[fxpanel] fx_scores: %d rows / %d months (%s..%s)\n",
    nrow(fx_scores), uniqueN(fx_scores$Date),
    as.character(min(fx_scores$Date)), as.character(max(fx_scores$Date))))
cat(sprintf("[fxpanel] regime: WEAK=%d STRONG=%d NA=%d\n",
    regime_monthly[regime=="WEAK", .N], regime_monthly[regime=="STRONG", .N],
    regime_monthly[is.na(regime), .N]))
cat("[fxpanel] DONE\n")
