#!/usr/bin/env Rscript
# Cheap SCREEN: Sector-pair mean-reversion (conditional-spread / pair-reversion)
# WT_CREATIVE_SCREEN2 / sector_pair_meanrev
# read-only. NO backtest/admission/full-package. advisory screen only.
#
# Hypothesis (STRUCTURAL alpha, not stock rank-IC): for each sector PAIR, spread_t = log(P_A/P_B)
#   where P = cap-weighted within-universe sector price index. When |z_{t-1}| > 2 (extreme divergence),
#   the H=21d forward spread CHANGE has conditional mean of OPPOSITE sign (mean-reversion).
#   GO iff reversion significant (Newey-West |t|>~2) AND |conditional mean| net of 2-leg round-trip cost
#   is economically meaningful across >=2 pairs and both subperiods.
#
# PIT: z uses spread up to t-1 (shift lag1) with rolling 252d window (C1 no full-sample, C2 no same-day circular).
#      forward label = forward spread change via shift(..., n=H, type='lead') (safe forward form, NOT n=-H+lead).
#      lockbox 2023-12-22 used as subperiod split for alpha-framing stability.
#      Universe = KOSPI200 U KOSDAQ150 (K200|KQ150). Sector = RAWDATA Sector (KSI Lv1).

suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- "stage_artifacts/WT_CREATIVE_SCREEN2/sector_pair_meanrev"
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

H <- 21L; Z_THR <- 2.0; WIN <- 252L
START <- as.Date("2004-01-01")
LOCKBOX <- as.Date("2023-12-22")
COST_RT <- 4 * 0.0015   # 2 legs x 15bps one-way x (enter+exit) = 0.0060 round-trip both legs
MIN_EVENTS <- 20L
MIN_NAMES_SECTOR <- 3L   # need >=3 names in a sector-day to form a stable index

cat("[1] Load rawdata...\n")
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd <- rd[Date >= START & !is.na(Close) & Close > 0 & !is.na(Sector) & Sector != ""]
rd[, in_univ := (K200 == TRUE | KQ150 == TRUE)]
rd <- rd[in_univ == TRUE]
rd[, mcap := Size]   # Size = market cap proxy in RAWDATA
rd <- rd[!is.na(mcap) & mcap > 0]
cat("    rows:", nrow(rd), " sectors:", uniqueN(rd$Sector), " dates:", uniqueN(rd$Date), "\n")

# ---- 2. Cap-weighted daily sector return, then chain to a price index ----
# Use daily Ret (already in rawdata). Cap weight = prior-day mcap to avoid same-day circular (C2):
setorder(rd, Ticker, Date)
rd[, mcap_lag := shift(mcap, 1L, type="lag"), by=Ticker]
rd[, ret := Ret]
rd <- rd[is.finite(ret) & is.finite(mcap_lag) & mcap_lag > 0]

# weight within (Date,Sector) using LAGGED cap (PIT-safe)
sec_ret <- rd[, .(sret = sum(ret * mcap_lag, na.rm=TRUE) / sum(mcap_lag, na.rm=TRUE),
                  n = .N),
              by = .(Date, Sector)]
sec_ret <- sec_ret[n >= MIN_NAMES_SECTOR]
setorder(sec_ret, Sector, Date)

# chain to price index per sector (data prep, NOT strategy synth)
sec_ret[, idx := cumprod(1 + sret), by = Sector]

# wide price-index panel
prc <- dcast(sec_ret, Date ~ Sector, value.var = "idx")
setorder(prc, Date)
sectors <- setdiff(names(prc), "Date")
# keep sectors with sufficient coverage
cov_ok <- sectors[sapply(sectors, function(s) sum(is.finite(prc[[s]])) > (WIN + H + 200))]
cat("    sectors with coverage:", length(cov_ok), "\n")
sectors <- cov_ok

newey_t <- function(x, lag=H) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n < 10) return(c(mean=NA_real_, t=NA_real_, n=n))
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2)/n; s <- g0
  L <- min(lag, n-1)
  for (k in 1:L) { w <- 1 - k/(L+1); gk <- sum(e[(k+1):n]*e[1:(n-k)])/n; s <- s + 2*w*gk }
  se <- sqrt(s/n); c(mean=mu, t=mu/se, n=n)
}

eval_pair <- function(a, b, dmax=NULL) {
  d <- prc[, .(Date, A=get(a), B=get(b))]
  d <- d[is.finite(A) & is.finite(B) & A>0 & B>0]
  if (!is.null(dmax)) d <- d[Date <= dmax]
  if (nrow(d) < WIN + H + 60) return(NULL)
  setorder(d, Date)
  d[, spread := log(A) - log(B)]
  d[, sp_lag := shift(spread, 1L, type="lag")]                 # info as of t-1
  d[, mu := frollmean(sp_lag, WIN, align="right")]
  d[, sdv := frollapply(sp_lag, WIN, sd, align="right")]
  d[, z := (sp_lag - mu)/sdv]
  d[, sp_fwd := shift(spread, H, type="lead")]                 # FORWARD label only
  d[, fwd_chg := sp_fwd - spread]
  ev <- d[is.finite(z) & abs(z) > Z_THR & is.finite(fwd_chg)]
  if (nrow(ev) < MIN_EVENTS) return(list(n=nrow(ev), insufficient=TRUE))
  ev[, rev := -sign(z) * fwd_chg]   # reversion profit (gross) if forward change opposes z
  nw <- newey_t(ev$rev, lag=H)
  list(n=nrow(ev),
       cond_rev_mean = unname(nw["mean"]),
       nw_t = unname(nw["t"]),
       net_mean = unname(nw["mean"]) - COST_RT,
       hit = mean(ev$rev > 0),
       insufficient = FALSE)
}

combs <- t(combn(sectors, 2))
cat("[3] Evaluate", nrow(combs), "pairs (full + pre-lockbox subperiod)...\n")
rows <- list()
for (i in seq_len(nrow(combs))) {
  a <- combs[i,1]; b <- combs[i,2]
  rf <- tryCatch(eval_pair(a,b), error=function(e) NULL)
  if (is.null(rf) || isTRUE(rf$insufficient)) next
  rp  <- tryCatch(eval_pair(a,b, dmax=LOCKBOX), error=function(e) NULL)            # pre-lockbox
  post<- tryCatch(eval_pair(a,b), error=function(e) NULL)                          # full (already)
  rows[[length(rows)+1]] <- data.table(
    pair=paste(a,b,sep=" / "), a=a, b=b,
    n=rf$n, cond_rev_mean=rf$cond_rev_mean, nw_t=rf$nw_t, net_mean=rf$net_mean, hit=rf$hit,
    nw_t_pre = if(!is.null(rp) && isFALSE(rp$insufficient)) rp$nw_t else NA_real_,
    net_mean_pre = if(!is.null(rp) && isFALSE(rp$insufficient)) rp$net_mean else NA_real_,
    n_pre = if(!is.null(rp) && isFALSE(rp$insufficient)) rp$n else NA_integer_
  )
}
tab <- if(length(rows)) rbindlist(rows, fill=TRUE) else data.table()
if (nrow(tab)) setorder(tab, -nw_t)
fwrite(tab, file.path(OUT, "pair_reversion_table.csv"))

# ---- GO/NO-GO ----
n_sig_full <- if(nrow(tab)) sum(tab$nw_t > 2 & tab$net_mean > 0, na.rm=TRUE) else 0
# robust = significant full AND same-sign-significant pre-lockbox AND net positive in both
robust <- if(nrow(tab)) tab[nw_t > 2 & net_mean > 0 & nw_t_pre > 1.5 & net_mean_pre > 0] else data.table()
n_robust <- nrow(robust)
n_continuation <- if(nrow(tab)) sum(tab$nw_t < -2, na.rm=TRUE) else 0
best <- if(nrow(tab)) tab[1] else NULL

res <- list(
  idea="sector_pair_meanrev",
  screen_type="conditional-spread / pair-reversion (structural; |z_{t-1}|>2 -> H=21d forward spread change; Newey-West t; net of 2-leg round-trip)",
  data_source="RAWDATA Sector cap-weighted (lagged-cap) daily index, KSI Lv1, KOSPI200 U KOSDAQ150",
  data_feasible=TRUE,
  H=H, z_thr=Z_THR, roll_win=WIN, cost_round_trip_both_legs=COST_RT,
  start=as.character(START), lockbox=as.character(LOCKBOX),
  n_sectors=length(sectors),
  n_pairs_evaluated=nrow(tab),
  n_pairs_reversion_sig_net_positive_full = n_sig_full,
  n_pairs_robust_full_and_prelockbox = n_robust,
  n_pairs_significant_continuation = n_continuation,
  best_pair = if(!is.null(best)) best$pair else NA,
  best_nw_t = if(!is.null(best)) best$nw_t else NA,
  best_cond_rev_mean_gross = if(!is.null(best)) best$cond_rev_mean else NA,
  best_net_mean = if(!is.null(best)) best$net_mean else NA,
  best_n_events = if(!is.null(best)) best$n else NA,
  best_hit = if(!is.null(best)) best$hit else NA,
  top5 = if(nrow(tab)) tab[1:min(5,nrow(tab)), .(pair,n,cond_rev_mean,nw_t,net_mean,hit,nw_t_pre,net_mean_pre)] else NULL,
  robust_pairs = if(n_robust>0) robust[, .(pair,n,nw_t,net_mean,nw_t_pre,net_mean_pre)] else NULL,
  go = (n_robust >= 2),
  verdict = if (n_robust >= 2)
      "GO_ADVISORY: >=2 pairs show net-positive reversion robust across full+pre-lockbox. Screen is advisory (not tradeable) -> recommend formal canonical/forge follow-up."
    else
      "NO_GO: insufficient net-of-cost reversion robust across subperiods. Screen is advisory only."
)
writeLines(toJSON(res, auto_unbox=TRUE, pretty=TRUE, null="null", na="null", digits=6),
           file.path(OUT, "screen_result.json"))

cat("\n=== SCREEN RESULT ===\n")
cat("n_sectors=", length(sectors), " n_pairs=", nrow(tab), "\n")
cat("n_sig_full(t>2 & net>0)=", n_sig_full, " n_robust(full+pre)=", n_robust,
    " n_continuation(t<-2)=", n_continuation, "\n")
if(!is.null(best)) cat(sprintf("BEST: %s  n=%d  gross=%.5f  nw_t=%.2f  net=%.5f  hit=%.2f\n",
    best$pair, best$n, best$cond_rev_mean, best$nw_t, best$net_mean, best$hit))
cat("GO=", res$go, " | ", res$verdict, "\n")
cat("DONE_OK\n")
