# =============================================================================
# CREATIVE CHEAP IC SCREEN — DART Metadata (Timeliness + Structure)
# WT_CREATIVE_SCREEN / dart_metadata_timeliness
# SCREEN ONLY: read-only signal -> forward Rank-IC/ICIR/Harvey-t(NW) + orthogonality + subperiod
# NO backtest / NO portfolio / NO admission.
# PIT: features t-1 backward (rcept_dt < sig_date), forward label only future.
#      lockbox 2023-12-22 strict (regular research). Universe KOSPI200 U KOSDAQ150.
# =============================================================================
suppressMessages({library(data.table); library(arrow)})
set.seed(42)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a)) b else a

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_CREATIVE_SCREEN/dart_metadata_timeliness")
LOCKBOX <- as.Date("2023-12-22")   # regular-research strict cutoff

# ---- 1. DART annual filings (reprt_code 11011) -> metadata -----------------
cat("[1] load DART annual financials (line-item rows)\n")
dart <- as.data.table(read_parquet(file.path(ROOT, ".cache/dart/dart_raw_financials.parquet"),
                                   col_select = c("rcept_no","reprt_code","bsns_year","Ticker")))
dart <- dart[reprt_code == "11011" & !is.na(Ticker) & !is.na(rcept_no)]
dart[, rcept_dt := as.Date(substr(rcept_no, 1, 8), format = "%Y%m%d")]
dart <- dart[!is.na(rcept_dt)]

# per-filing aggregation: line-item count + filing date (1 row per filing)
fil <- dart[, .(n_items = .N, rcept_dt = rcept_dt[1]), by = .(rcept_no, Ticker, bsns_year)]
# Dec-FY assumption (KR norm): legal deadline = 90 days after FY-end = ~ Mar 31 of (bsns_year+1)
fil[, fy_end       := as.Date(paste0(bsns_year, "-12-31"))]
fil[, legal_deadl  := fy_end + 90]                          # statutory annual-report deadline
fil[, lateness_d   := as.numeric(rcept_dt - legal_deadl)]   # >0 late, <0 early (signed days)
# guard: drop filings filed implausibly long after FY end (>1yr -> restatement/late vehicle)
fil <- fil[lateness_d > -120 & lateness_d < 270]

# (a) TIMELINESS signals (per firm-year, relative to firm's own history):
setorder(fil, Ticker, bsns_year)
fil[, lateness_med_self := {
       v <- lateness_d
       sapply(seq_along(v), function(i) if (i == 1L) NA_real_ else median(v[1:(i-1)], na.rm = TRUE))
     }, by = Ticker]                                          # expanding self-median (PIT: past only)
fil[, S_late_rel := lateness_d - lateness_med_self]           # late vs own median (slower than usual = worse)
fil[, S_early    := -lateness_d]                              # earlier filing = higher signal (timeliness/quality)

# (b) STRUCTURE / GRANULARITY signal: per-filing line-item count YoY Δ (firm-internal)
fil[, n_items_prev := shift(n_items, n = 1L, type = "lag"), by = Ticker]   # PIT prior-year, backward lag
fil[, S_gran_dyoy  := n_items - n_items_prev]                # +Δ = more disclosure granularity (transparency up)
fil[, n_items_lvl  := n_items]                               # level (cross-sectional demean done later at sig_date)

# Signal becomes usable AFTER the filing is public: usable_from = rcept_dt
sig_tab <- fil[, .(Ticker, bsns_year, rcept_dt,
                   S_early, S_late_rel, S_gran_dyoy, n_items_lvl)]
sig_tab <- sig_tab[!is.na(rcept_dt)]

# ---- 2. monthly sig_dates + universe + forward 1m return -------------------
cat("[2] load rawdata (returns + universe)\n")
rw <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet"),
                                 col_select = c("Date","Ticker","Ret","Close","K200","KQ150")))
rw[, Date := as.Date(Date)]
rw <- rw[(K200 == TRUE | KQ150 == TRUE)]                     # KOSPI200 U KOSDAQ150
# month-end calendar
rw[, ym := format(Date, "%Y%m")]
me <- rw[, .(me_date = max(Date)), by = ym]                  # month-end trading day
setkey(me, ym)

# forward 1-month return per ticker: compound daily Ret within next month (label = future only)
# build month-end Close per ticker -> fwd_ret = Close[m+1]/Close[m]-1 (clean monthly, no self-synthesis of NAV)
mec <- rw[me, on = .(Date == me_date), .(Date, Ticker, Close, K200, KQ150), nomatch = 0L]
setorder(mec, Ticker, Date)
mec[, Close_fwd := shift(Close, n = 1L, type = "lead"), by = Ticker]   # FORWARD next month-end (type=lead, n positive)
mec[, fwd_ret   := Close_fwd / Close - 1]
mec[, sig_date  := Date]
mec <- mec[is.finite(fwd_ret) & abs(fwd_ret) < 2]            # drop corp-action outliers

# ---- 3. align signals to each month sig_date (PIT: rcept_dt < sig_date) -----
# For each (Ticker, sig_date) take the MOST RECENT filing whose rcept_dt < sig_date (strictly before).
cat("[3] PIT align: most-recent filing with rcept_dt < sig_date\n")
sig_dates <- sort(unique(mec$sig_date))
sig_dates <- sig_dates[sig_dates <= LOCKBOX]                 # regular-research strict lockbox
setorder(sig_tab, Ticker, rcept_dt)

panel_list <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  cur <- mec[sig_date == sd, .(Ticker, sig_date, fwd_ret)]
  # latest filing strictly before sd
  past <- sig_tab[rcept_dt < sd]
  if (nrow(past) == 0L || nrow(cur) == 0L) next
  latest <- past[, .SD[.N], by = Ticker,
                 .SDcols = c("rcept_dt","S_early","S_late_rel","S_gran_dyoy","n_items_lvl")]
  m <- merge(cur, latest, by = "Ticker")
  # only keep filings still "fresh" (<=14 months old) so signal is the most recent annual report
  m <- m[as.numeric(sd - rcept_dt) <= 425]
  if (nrow(m) >= 20L) panel_list[[i]] <- m
}
panel <- rbindlist(panel_list, use.names = TRUE)
cat(sprintf("   panel rows=%d  months=%d  tickers=%d  date %s..%s\n",
            nrow(panel), uniqueN(panel$sig_date), uniqueN(panel$Ticker),
            min(panel$sig_date), max(panel$sig_date)))

# cross-sectional demean granularity level at each sig_date (per idea: year/cross-sectional demean)
panel[, S_gran_lvl_cs := n_items_lvl - mean(n_items_lvl, na.rm = TRUE), by = sig_date]

SIGNALS <- c("S_early", "S_late_rel", "S_gran_dyoy", "S_gran_lvl_cs")

# ---- 4. forward Rank-IC time-series + ICIR + Harvey-t (NW) ------------------
cat("[4] per-month Spearman rank-IC, ICIR, Harvey-t (Newey-West)\n")
rank_ic_ts <- function(dt, scol) {
  dt2 <- dt[is.finite(get(scol)) & is.finite(fwd_ret)]
  ts <- dt2[, .(ic = if (.N >= 20L) suppressWarnings(cor(get(scol), fwd_ret, method = "spearman")) else NA_real_,
                n  = .N), by = sig_date]
  ts[is.finite(ic)]
}
nw_t <- function(x, L = NULL) {                 # Newey-West t-stat of mean(x)
  x <- x[is.finite(x)]; n <- length(x)
  if (n < 6) return(NA_real_)
  if (is.null(L)) L <- floor(4 * (n/100)^(2/9))
  xc <- x - mean(x); g0 <- sum(xc^2)/n
  v <- g0
  if (L >= 1) for (l in 1:L) { w <- 1 - l/(L+1); gl <- sum(xc[(l+1):n]*xc[1:(n-l)])/n; v <- v + 2*w*gl }
  se <- sqrt(v/n); mean(x)/se
}

res <- list()
for (s in SIGNALS) {
  ts <- rank_ic_ts(panel, s)
  ic <- ts$ic
  res[[s]] <- list(
    rank_ic   = mean(ic, na.rm = TRUE),
    icir      = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE),    # IR of IC series (per-month, annualize *sqrt(12) below)
    icir_ann  = (mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE)) * sqrt(12),
    harvey_t  = nw_t(ic),
    n_months  = length(ic),
    n_obs     = sum(ts$n),
    pct_pos   = mean(ic > 0, na.rm = TRUE),
    ic_series = ts
  )
  cat(sprintf("   %-16s rankIC=%+.4f  ICIR(m)=%+.3f  Harvey-t=%+.2f  months=%d  pos%%=%.2f\n",
              s, res[[s]]$rank_ic, res[[s]]$icir, res[[s]]$harvey_t, res[[s]]$n_months, res[[s]]$pct_pos))
}

# ---- 5. ORTHOGONALITY: residual IC after controlling content factors -------
cat("[5] orthogonality: residual rank-IC after controlling content factors (ROE/Accrual/Q07/Q08)\n")
CONTROLS <- c("Q02_ROE","Q05_Accrual","Q07_Earnings_Stability","Q08_Composite_Quality","AC07_Operating_Accruals")
fdb_dir <- file.path(ROOT, ".cache/factor_db")
load_controls_for <- function(sd) {
  ym <- format(sd, "%Y%m")
  fp <- file.path(fdb_dir, paste0("factor_db_", ym, ".parquet"))
  if (!file.exists(fp)) return(NULL)
  d <- as.data.table(read_parquet(fp, col_select = c("Date","Ticker","Factor_Name","Z_Score")))
  d <- d[Factor_Name %in% CONTROLS]
  if (nrow(d) == 0L) return(NULL)
  w <- dcast(d, Ticker ~ Factor_Name, value.var = "Z_Score", fun.aggregate = mean)
  w[, sig_date := sd]; w
}
ctrl_list <- lapply(sig_dates, load_controls_for)
ctrl <- rbindlist(ctrl_list, use.names = TRUE, fill = TRUE)

# residualize each signal on controls per month, then re-IC residual vs fwd_ret
partial_res <- list()
for (s in SIGNALS) {
  merged <- merge(panel[, c("Ticker","sig_date","fwd_ret", s), with = FALSE],
                  ctrl, by = c("Ticker","sig_date"))
  ctrl_avail <- intersect(CONTROLS, names(merged))
  if (length(ctrl_avail) == 0L) { partial_res[[s]] <- list(partial_ic = NA_real_, note = "no controls"); next }
  ts <- merged[, {
      ok <- complete.cases(.SD)
      sd_dt <- .SD[ok]
      if (sum(ok) < 25L) .(pic = NA_real_, n = sum(ok)) else {
        f <- as.formula(paste0(s, " ~ ", paste(ctrl_avail, collapse = "+")))
        resid_sig <- residuals(lm(f, data = sd_dt))               # signal orthogonal to content factors
        # also residualize return on controls to get true partial corr
        fr <- residuals(lm(as.formula(paste0("fwd_ret ~ ", paste(ctrl_avail, collapse="+"))), data = sd_dt))
        .(pic = suppressWarnings(cor(resid_sig, fr, method = "spearman")), n = sum(ok))
      }
    }, by = sig_date, .SDcols = c(s, "fwd_ret", ctrl_avail)]
  pic <- ts[is.finite(pic)]$pic
  partial_res[[s]] <- list(
    partial_ic   = mean(pic, na.rm = TRUE),
    partial_t    = nw_t(pic),
    n_months     = length(pic),
    raw_ic       = res[[s]]$rank_ic,
    shrinkage    = mean(pic, na.rm=TRUE) / res[[s]]$rank_ic,
    controls     = ctrl_avail
  )
  cat(sprintf("   %-16s raw=%+.4f  partial(orthog)=%+.4f  partial-t=%+.2f  retain=%.0f%%  ctrls=%d\n",
              s, res[[s]]$rank_ic, partial_res[[s]]$partial_ic, partial_res[[s]]$partial_t,
              100*partial_res[[s]]$shrinkage, length(ctrl_avail)))
}

# ---- 6. SUBPERIOD STABILITY (split IC series in half) ----------------------
cat("[6] subperiod stability (first half vs second half of IC series)\n")
sub_res <- list()
for (s in SIGNALS) {
  ic_ts <- res[[s]]$ic_series; setorder(ic_ts, sig_date)
  ic <- ic_ts$ic; n <- length(ic); h <- floor(n/2)
  ic1 <- ic[1:h]; ic2 <- ic[(h+1):n]
  sub_res[[s]] <- list(
    ic_first  = mean(ic1, na.rm=TRUE), ic_second = mean(ic2, na.rm=TRUE),
    same_sign = (sign(mean(ic1,na.rm=TRUE)) == sign(mean(ic2,na.rm=TRUE))),
    stability = 1 - abs(mean(ic1,na.rm=TRUE) - mean(ic2,na.rm=TRUE)) / (abs(mean(ic,na.rm=TRUE)) + 1e-6)
  )
  cat(sprintf("   %-16s H1=%+.4f H2=%+.4f same_sign=%s\n",
              s, sub_res[[s]]$ic_first, sub_res[[s]]$ic_second, sub_res[[s]]$same_sign))
}

# ---- 7. write screen JSON --------------------------------------------------
best <- SIGNALS[which.max(sapply(SIGNALS, function(s) abs(res[[s]]$harvey_t)))]
screen <- list(
  wt = "WT_CREATIVE_SCREEN", idea = "dart_metadata_timeliness",
  generated_utc = format(Sys.time(), tz = "UTC", "%Y-%m-%dT%H:%M:%SZ"),
  scope = "SCREEN ONLY — read-only rank-IC + orthogonality + subperiod. No backtest/portfolio/admission.",
  data_feasible = TRUE,
  universe = "KOSPI200 U KOSDAQ150", lockbox = as.character(LOCKBOX),
  panel = list(rows = nrow(panel), months = uniqueN(panel$sig_date),
               tickers = uniqueN(panel$Ticker),
               date_min = as.character(min(panel$sig_date)),
               date_max = as.character(max(panel$sig_date))),
  signals = lapply(SIGNALS, function(s) list(
      name = s,
      rank_ic = round(res[[s]]$rank_ic, 5),
      icir_monthly = round(res[[s]]$icir, 4),
      icir_annualized = round(res[[s]]$icir_ann, 4),
      harvey_t_rankic_nw = round(res[[s]]$harvey_t, 3),
      n_months = res[[s]]$n_months, n_obs = res[[s]]$n_obs,
      pct_positive = round(res[[s]]$pct_pos, 3),
      partial_ic_vs_content = round(partial_res[[s]]$partial_ic, 5),
      partial_t_nw = round(partial_res[[s]]$partial_t %||% NA, 3),
      orthogonality_retain_pct = round(100*partial_res[[s]]$shrinkage, 1),
      subperiod_ic_first = round(sub_res[[s]]$ic_first, 5),
      subperiod_ic_second = round(sub_res[[s]]$ic_second, 5),
      subperiod_same_sign = sub_res[[s]]$same_sign)),
  best_signal = best
)
jsonlite::write_json(screen, file.path(OUT, "screen_result.json"),
                     auto_unbox = TRUE, pretty = TRUE, na = "null")
# also dump IC series for audit
for (s in SIGNALS) fwrite(res[[s]]$ic_series, file.path(OUT, paste0("ic_series_", s, ".csv")))
cat("\n[DONE] screen_result.json written. best_signal =", best, "\n")
