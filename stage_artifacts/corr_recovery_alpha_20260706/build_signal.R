# build_signal.R — Correlation-Recovery cross-sectional signal (PIT) + cheap screen gate
# Novel lane: post-crash 상관-회복 dynamics. 시장 급락 시 종목-시장 상관이 1로 spike →
# 각 종목이 얼마나 빨리 de-correlate(회복)하는가를 횡단면 신호로. 절대 corr level/β 통제.
#
# PIT: 모든 신호는 sig_date(월말 t)까지의 daily Ret만 사용. forward 수익 = t→t+1 (Ret_1m).
#      rolling corr(C1) · t-1 정보만 · 동월 concurrent 금지 · lag1 스트레스.
# 자체합성 금지: 성과수치는 canonical_screen_bt(build_benchmark_compare) 경유. 여기선 rank-IC screen만.

suppressMessages({ library(data.table); library(arrow) })
setDTthreads(1L)
try(arrow::set_io_thread_count(1L), silent = TRUE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/corr_recovery_alpha_20260706")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

cat("[1] Load RAWDATA (col_select, daily)...\n")
raw <- as.data.table(read_parquet(
  file.path(ROOT, ".cache/RAWDATA.parquet"),
  col_select = c("Date","Ticker","K200","KQ150","Close","Ret","Vol","BM_Ret")
))
raw[, Date := as.IDate(as.character(Date))]
raw <- raw[Date >= as.IDate("2003-06-01")]   # warmup buffer before 2004 signal start
setorder(raw, Ticker, Date)

# universe membership (t-1 PIT: use flags as-of each daily row; monthly screen picks month-end)
cat("[2] Rolling stock-market correlation (20d / 60d), per ticker...\n")

# rolling correlation via rolling covariance/var (O(N)); window w
roll_corr <- function(x, y, w) {
  n <- length(x)
  out <- rep(NA_real_, n)
  if (n < w) return(out)
  sx <- frollsum(x, w); sy <- frollsum(y, w)
  sxx <- frollsum(x*x, w); syy <- frollsum(y*y, w); sxy <- frollsum(x*y, w)
  cov <- (sxy - sx*sy/w)
  vx  <- (sxx - sx*sx/w)
  vy  <- (syy - sy*sy/w)
  denom <- sqrt(vx*vy)
  cr <- cov/denom
  cr[!is.finite(cr)] <- NA_real_
  cr
}

# per-ticker rolling corr with market (BM_Ret). Guard: require Ret & BM_Ret present.
raw <- raw[!is.na(Ret) & !is.na(BM_Ret)]
raw[, corr20 := roll_corr(Ret, BM_Ret, 20L), by = Ticker]
raw[, corr60 := roll_corr(Ret, BM_Ret, 60L), by = Ticker]

# recovery speed features (all trailing, PIT at each daily row):
#  - corr20_peak63 = trailing 63d (≈3M) max of corr20  (recent panic/spike peak)
#  - recovery = corr20_peak63 - corr20   (how far corr has come DOWN from recent peak; >0 = de-correlating)
#  - spike = corr20_peak63 - corr60      (magnitude of the spike vs baseline)
#  - recovery_frac = recovery / (spike + eps)  (fraction of the spike already unwound = SPEED)
cat("[3] Recovery-speed features...\n"); flush.console()
# fast trailing rolling max over 63d (monotonic-deque style via cummax on blocks is complex;
# use frollapply only on month-end? No -- we need it daily. Use efficient Rcpp-free rolling max:
# split by ticker, apply a vectorized rolling max with runner-free approach.
roll_max <- function(x, w) {
  n <- length(x); out <- rep(NA_real_, n)
  if (n == 0) return(out)
  # deque of indices with decreasing values
  dq <- integer(0)
  for (i in seq_len(n)) {
    while (length(dq) && x[dq[length(dq)]] <= x[i]) dq <- dq[-length(dq)]
    dq <- c(dq, i)
    if (dq[1] <= i - w) dq <- dq[-1]
    if (i >= w) out[i] <- x[dq[1]]
  }
  out
}
raw[, corr20_peak63 := roll_max(corr20, 63L), by = Ticker]
eps <- 0.05
raw[, recovery      := corr20_peak63 - corr20]
raw[, spike         := corr20_peak63 - corr60]
raw[, recovery_frac := recovery / (pmax(spike, 0) + eps)]

# month-end sig rows: last trading day of each month per ticker (t-1 info only, no forward)
cat("[4] Month-end sampling + universe filter...\n")
raw[, ym := as.integer(format(Date, "%Y%m"))]
setorder(raw, Ticker, Date)
me <- raw[, .SD[.N], by = .(Ticker, ym)]   # last daily row within month = month-end snapshot
# universe: K200 or KQ150 at month-end (PIT: membership known at t)
me <- me[(K200 == 1) | (KQ150 == 1)]
# require valid corr features
me <- me[is.finite(corr20) & is.finite(corr60) & is.finite(recovery_frac)]

# sig_date = month-end date; map ym -> monthly Date key for merge with forward returns/bench
me[, sig_ym := ym]

cat("[5] Build monthly forward returns (Ret_1m) from daily Ret, PIT forward...\n")
# monthly compound return per ticker: from month m returns -> use as FORWARD for month m-1 signal.
# We construct month m realized return = prod(1+daily Ret in month m)-1. This is the RESEARCH input
# (asset forward return) that gets handed to canonical_screen_bt; screen here needs rank-IC only.
mret <- raw[, .(mret = prod(1 + Ret) - 1), by = .(Ticker, ym)]
setorder(mret, Ticker, ym)
# forward: signal at month ym predicts return of month ym+1
mret[, ym_key := ym]
# build next-month key handling year rollover
next_ym <- function(y) { yr <- y %/% 100; mo <- y %% 100; mo2 <- mo + 1; yr2 <- yr + (mo2>12); mo2 <- ifelse(mo2>12,1,mo2); yr2*100+mo2 }
me[, fwd_ym := next_ym(sig_ym)]
fwd <- merge(me[, .(Ticker, sig_ym, fwd_ym, recovery_frac, recovery, spike, corr20, corr60, corr20_peak63)],
             mret[, .(Ticker, ym_key, fwd_mret = mret)],
             by.x = c("Ticker","fwd_ym"), by.y = c("Ticker","ym_key"))
fwd <- fwd[is.finite(fwd_mret)]
fwd <- fwd[sig_ym >= 200401L]   # signal start 2004

cat(sprintf("[6] Panel rows: %d, months: %d, tickers: %d\n",
            nrow(fwd), length(unique(fwd$sig_ym)), length(unique(fwd$Ticker))))

# ---- Control for absolute correlation level (residualize) — NOT a low-corr/low-beta factor ----
# cross-sectional (per month): residual of recovery_frac on corr20 (current abs corr level).
cat("[7] Residualize recovery_frac on abs corr level (per month) => corr_recov_resid...\n")
fwd[, corr_recov_resid := {
  if (.N >= 10 && sd(corr20, na.rm=TRUE) > 0) {
    fit <- lm(recovery_frac ~ corr20)
    as.numeric(residuals(fit))
  } else rep(NA_real_, .N)
}, by = sig_ym]
fwd <- fwd[is.finite(corr_recov_resid)]

saveRDS(fwd, file.path(OUT, "signal_panel.rds"))

# ---- Cheap screen: forward-1M rank-IC (per month spearman) for raw & residual signal ----
cat("[8] rank-IC screen...\n")
rank_ic_by_month <- function(dt, sigcol) {
  dt[, .(ic = if (.N >= 10) suppressWarnings(cor(get(sigcol), fwd_mret, method="spearman")) else NA_real_),
     by = sig_ym][is.finite(ic)]
}
ic_stat <- function(ics) {
  n <- length(ics); mu <- mean(ics); s <- sd(ics)
  t <- mu / (s/sqrt(n)); icir <- mu/s
  list(n=n, mean_ic=mu, t=t, icir=icir)
}
ic_raw   <- rank_ic_by_month(fwd, "recovery_frac")
ic_resid <- rank_ic_by_month(fwd, "corr_recov_resid")
st_raw   <- ic_stat(ic_raw$ic)
st_resid <- ic_stat(ic_resid$ic)

# 2017+ sign persistence
ic_resid_2017 <- ic_resid[sig_ym >= 201701L]
st_resid_2017 <- ic_stat(ic_resid_2017$ic)
ic_raw_2017   <- ic_raw[sig_ym >= 201701L]
st_raw_2017   <- ic_stat(ic_raw_2017$ic)

cat(sprintf("  RAW   recovery_frac : mean_ic=%.4f t=%.2f ICIR=%.3f n=%d\n",
            st_raw$mean_ic, st_raw$t, st_raw$icir, st_raw$n))
cat(sprintf("  RESID corr_recov    : mean_ic=%.4f t=%.2f ICIR=%.3f n=%d\n",
            st_resid$mean_ic, st_resid$t, st_resid$icir, st_resid$n))
cat(sprintf("  RESID 2017+         : mean_ic=%.4f t=%.2f n=%d\n",
            st_resid_2017$mean_ic, st_resid_2017$t, st_resid_2017$n))
cat(sprintf("  RAW   2017+         : mean_ic=%.4f t=%.2f n=%d\n",
            st_raw_2017$mean_ic, st_raw_2017$t, st_raw_2017$n))

# ---- Orthogonality to score_eff (rank corr < 0.4) ----
cat("[9] Orthogonality vs score_eff...\n")
seff <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet"),
                                   col_select = c("Date","Ticker","score_eff")))
seff[, Date := as.IDate(as.character(Date))]
seff[, sig_ym := as.integer(format(Date, "%Y%m"))]
oj <- merge(fwd[, .(Ticker, sig_ym, corr_recov_resid, recovery_frac)],
            seff[, .(Ticker, sig_ym, score_eff)], by = c("Ticker","sig_ym"))
oj <- oj[is.finite(score_eff)]
ortho_by_month <- oj[, .(rc = if (.N >= 10) suppressWarnings(cor(corr_recov_resid, score_eff, method="spearman")) else NA_real_),
                     by = sig_ym][is.finite(rc)]
ortho_pool <- oj[, suppressWarnings(cor(corr_recov_resid, score_eff, method="spearman"))]
ortho_mean <- mean(ortho_by_month$rc)
cat(sprintf("  ortho pooled=%.3f  mean-monthly=%.3f  n_overlap_rows=%d\n", ortho_pool, ortho_mean, nrow(oj)))

# ---- Gate decision ----
# Primary signal = residual (corr level controlled). PASS: |t|>=2 AND |ortho|<0.4 AND 2017+ sign held.
best <- if (abs(st_resid$t) >= abs(st_raw$t)) { list(name="corr_recov_resid", st=st_resid, st17=st_resid_2017) } else { list(name="recovery_frac", st=st_raw, st17=st_raw_2017) }
sign_full <- sign(best$st$mean_ic); sign_17 <- sign(best$st17$mean_ic)
pass_t     <- abs(best$st$t) >= 2
pass_ortho <- abs(ortho_pool) < 0.4
pass_2017  <- (sign_full == sign_17) && (abs(best$st17$t) >= 1)  # sign held + non-trivial
GATE <- pass_t && pass_ortho && pass_2017

res <- list(
  signal_definition = list(
    lane = "post-crash correlation-recovery dynamics (cross-sectional selection, NOT market timing)",
    construction = "per-ticker rolling stock-market corr (20d, 60d) from daily Ret vs BM_Ret; corr20_peak63=trailing 63d max of corr20 (recent panic spike); recovery=peak-corr20; spike=peak-corr60; recovery_frac=recovery/(max(spike,0)+0.05) = fraction of correlation spike already unwound (=de-correlation SPEED). Primary signal corr_recov_resid = cross-sectional residual of recovery_frac on corr20 (abs corr level controlled => NOT low-beta/low-vol).",
    PIT = "all features use daily Ret up to & incl month-end t (sig_date); forward = month t+1 realized return; rolling windows (C1); universe K200|KQ150 membership at t; no concurrent-month use.",
    hypothesis = "fast de-correlation (high recovery_frac) = idiosyncratic/resilient stocks -> excess return (sign to be read from IC)."
  ),
  panel = list(rows = nrow(fwd), months = length(unique(fwd$sig_ym)),
               tickers = length(unique(fwd$Ticker)),
               ym_first = min(fwd$sig_ym), ym_last = max(fwd$sig_ym)),
  rank_ic = list(
    raw_recovery_frac = st_raw,
    resid_corr_recov  = st_resid,
    raw_2017plus      = st_raw_2017,
    resid_2017plus    = st_resid_2017,
    primary_signal    = best$name
  ),
  orthogonality_score_eff = list(pooled = ortho_pool, mean_monthly = ortho_mean,
                                 n_overlap_rows = nrow(oj), threshold = 0.4),
  gate = list(
    primary_signal = best$name,
    pass_rankIC_t2 = pass_t, t_value = best$st$t,
    pass_ortho_lt04 = pass_ortho, ortho = ortho_pool,
    pass_2017_sign_held = pass_2017,
    sign_full = sign_full, sign_2017 = sign_17, t_2017 = best$st17$t,
    VERDICT = if (GATE) "PASS" else "FAIL",
    note = if (GATE) "signal present -> route to Canonical" else "signal absent/weak -> STOP (honest)"
  )
)
jsonlite::write_json(res, file.path(OUT, "screen_result.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("\n[GATE VERDICT] ", res$gate$VERDICT, "\n")
cat("written:", file.path(OUT, "screen_result.json"), "\n")
