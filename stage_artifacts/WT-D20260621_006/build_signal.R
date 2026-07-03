# WT-D20260621_006 — Liquidity Improvement Trend Momentum — signal construction
# PIT: all signal data Date<=sig_date (C1 rolling). Cross-sectional z per sig_date.
suppressMessages({library(arrow); library(data.table); library(dplyr)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
options(warn=1)

PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROOT)
OUT <- file.path(PROOT, "stage_artifacts/WT-D20260621_006")

# ---- 1. Load rawdata (only needed cols) ----
ds <- open_dataset(".cache/rawdata.parquet")
raw <- ds %>%
  filter(Date >= as.Date("2004-01-01")) %>%   # need 1yr lookback before 2005 grid
  select(Date, Ticker, Close, Vol, Ret, K200, KQ150, AdminStock, TradingHalt) %>%
  collect() %>% as.data.table()
raw[, Date := as.Date(Date)]
setorder(raw, Ticker, Date)
cat("rawdata rows:", nrow(raw), " tickers:", uniqueN(raw$Ticker), "\n")

# DolVol + daily ILLIQ (Amihud on KRW dollar volume)
raw[, DolVol := Close * Vol]
raw[, ILLIQ := fifelse(!is.na(Ret) & DolVol > 0, abs(Ret)/DolVol, NA_real_)]

# ---- 2. Monthly sig_date grid = month-end trading days, 2005-01 .. latest ----
all_dts <- sort(unique(raw$Date))
dt_dt <- data.table(Date=all_dts, ym=format(all_dts, "%Y-%m"))
month_end <- dt_dt[, .(Date=max(Date)), by=ym]
sig_grid <- month_end[Date >= as.Date("2005-01-01"), Date]
cat("sig_grid months:", length(sig_grid), " from", as.character(min(sig_grid)), "to", as.character(max(sig_grid)), "\n")

# ---- 3+4. Per sig_date: trailing-W window log-Amihud OLS slope ----
# Returns function: given W, recency_min, frac_min, estimator -> scores_dt(Date,Ticker,SIGNAL_raw,score)
compute_scores <- function(W=126L, recency_min=10L, frac_min=0.60, estimator="OLS") {
  out_list <- vector("list", length(sig_grid))
  for (k in seq_along(sig_grid)) {
    sd <- sig_grid[k]
    # eligible universe at sig_date
    univ <- raw[Date==sd & (K200==1 | KQ150==1) & (AdminStock==0|is.na(AdminStock)) & (TradingHalt==0|is.na(TradingHalt)), unique(Ticker)]
    if (length(univ)==0) next
    # trailing window: last W trading days <= sd, per ticker (use calendar slice then per-ticker tail)
    win <- raw[Date<=sd & Ticker %in% univ, .(Date,Ticker,ILLIQ)]
    # keep only last W obs per ticker (by Date desc) — but window defined on trading days present
    # Use global last-W trading dates as window boundary (uniform window)
    wdates <- tail(all_dts[all_dts<=sd], W)
    win <- win[Date %in% wdates & !is.na(ILLIQ)]
    if (nrow(win)==0) next
    # winsorize ILLIQ per ticker-window at 1/99
    win[, `:=`(lo=quantile(ILLIQ,.01,na.rm=T,type=7), hi=quantile(ILLIQ,.99,na.rm=T,type=7)), by=Ticker]
    win[, ILLIQw := pmin(pmax(ILLIQ,lo),hi)]
    win[, LOGILLIQ := log(ILLIQw + 1e-12)]
    # rank-of-day within ticker window (time index)
    setorder(win, Ticker, Date)
    win[, drank := seq_len(.N), by=Ticker]
    # gates: nobs >= frac_min*W ; recency last-20 trading-dates traded >=recency_min
    last20 <- tail(wdates, 20)
    rec <- win[Date %in% last20, .(rec_n=.N), by=Ticker]
    agg <- win[, .(nobs=.N), by=Ticker]
    agg <- merge(agg, rec, by="Ticker", all.x=TRUE)
    agg[is.na(rec_n), rec_n:=0L]
    keep <- agg[nobs >= frac_min*W & rec_n >= recency_min, Ticker]
    win <- win[Ticker %in% keep]
    if (nrow(win)==0) next
    # standardized tau per ticker
    win[, tau := { m<-mean(drank); s<-sd(drank); if(is.na(s)||s==0) rep(0,.N) else (drank-m)/s }, by=Ticker]
    # slope estimator
    if (estimator=="OLS") {
      sl <- win[, .(slope = { vt<-sum((tau-mean(tau))^2); if(vt<=0) NA_real_ else sum((tau-mean(tau))*(LOGILLIQ-mean(LOGILLIQ)))/vt }), by=Ticker]
    } else if (estimator=="decay") {
      hl <- 42
      sl <- win[, {
        wts <- exp(-(max(drank)-drank)/hl)
        wm_t <- sum(wts*tau)/sum(wts); wm_y <- sum(wts*LOGILLIQ)/sum(wts)
        vt <- sum(wts*(tau-wm_t)^2)
        sval <- if(vt<=0) NA_real_ else sum(wts*(tau-wm_t)*(LOGILLIQ-wm_y))/vt
        .(slope=sval)
      }, by=Ticker]
    } else if (estimator=="TheilSen") {
      sl <- win[, {
        # thinned pairwise (every 3rd) for cost
        idx <- seq(1,.N,by=3); n2<-length(idx)
        if(n2<3){ .(slope=NA_real_) } else {
          x<-tau[idx]; y<-LOGILLIQ[idx]
          ii<-combn(n2,2)
          dx<-x[ii[2,]]-x[ii[1,]]; dy<-y[ii[2,]]-y[ii[1,]]
          ok<-dx!=0
          .(slope = if(sum(ok)==0) NA_real_ else median(dy[ok]/dx[ok]))
        }
      }, by=Ticker]
    }
    sl <- sl[!is.na(slope)]
    if (nrow(sl)==0) next
    sl[, SIGNAL_raw := -slope]   # negate: improving liquidity = high
    # cross-sectional z + winsor +/-3
    mu<-mean(sl$SIGNAL_raw); sg<-sd(sl$SIGNAL_raw)
    if(is.na(sg)||sg==0) next
    sl[, score := pmin(pmax((SIGNAL_raw-mu)/sg, -3), 3)]
    sl[, Date := sd]
    out_list[[k]] <- sl[, .(Date,Ticker,SIGNAL_raw,score)]
  }
  rbindlist(out_list)
}

# ---- Build PRIMARY config first ----
t0<-Sys.time()
scores_primary <- compute_scores(W=126L, recency_min=10L, frac_min=0.60, estimator="OLS")
cat("PRIMARY scores rows:", nrow(scores_primary), " months:", uniqueN(scores_primary$Date),
    " elapsed:", round(as.numeric(Sys.time()-t0,units="secs"),1),"s\n")
saveRDS(scores_primary, file.path(OUT,"scores_primary.rds"))

# ---- forward 1M returns (compound daily Ret over next month) ----
# monthly return per ticker between consecutive sig_dates
ret_panel <- raw[, .(Date,Ticker,Ret)]
# map each daily Ret to the month-end bucket it belongs to going FORWARD from sig
# build month index
mes <- sort(sig_grid)
# For each ticker, forward return from month-end m to month-end m+1 = prod(1+Ret over (m, m+1]) - 1
# Use standard compounding via cumulative; harness convention: realized forward
raw[, ym := format(Date, "%Y-%m")]
# month label of each day -> map to the sig month-end of that month
ym_to_me <- month_end[, setNames(Date, ym)]
raw[, me := ym_to_me[ym]]
# monthly compounded return per ticker per month-end
monret <- raw[!is.na(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, me)]
setnames(monret, "me", "Date")
# forward: Ret_1m at sig_date sd = monret of the NEXT month-end
me_order <- data.table(Date=mes, nxt=shift(mes, -1))
monret <- merge(monret, me_order, by="Date")
fwd <- monret[, .(Date, Ticker, fwd_to=nxt)]
# Ret_1m(sd) = mret at nxt month
nxtret <- monret[, .(Date, Ticker, mret)]
returns_dt <- merge(me_order[, .(Date, nxt)], nxtret, by.x="nxt", by.y="Date", allow.cartesian=TRUE)
returns_dt <- returns_dt[, .(Date, Ticker, Ret_1m=mret)]
returns_dt <- returns_dt[!is.na(Ret_1m)]
cat("returns_dt rows:", nrow(returns_dt), " months:", uniqueN(returns_dt$Date), "\n")
saveRDS(returns_dt, file.path(OUT,"returns_dt.rds"))

# ---- liquidity adv: trailing 20d mean DolVol as of t-1 ----
setorder(raw, Ticker, Date)
raw[, adv20 := frollmean(DolVol, 20, align="right"), by=Ticker]
# as of t-1: shift by 1 within ticker
raw[, adv20_lag := shift(adv20, 1), by=Ticker]
liq_dt <- raw[Date %in% sig_grid, .(Date, Ticker, adv=adv20_lag)]
liq_dt <- liq_dt[!is.na(adv)]
saveRDS(liq_dt, file.path(OUT,"liq_dt.rds"))
cat("liq_dt rows:", nrow(liq_dt), "\n")

# ---- benchmark monthly ----
b <- as.data.table(read_parquet(".cache/benchmark.parquet"))
b[, Date := as.Date(Date)]
b[, ym := format(Date,"%Y-%m")]
bmon <- b[, .(BM_Close=last(BM_Close)), by=ym]
setorder(bmon, ym)
bmon[, BM_Ret := BM_Close/shift(BM_Close)-1]
# map ym -> month-end sig date
bmon <- merge(bmon, month_end[, .(ym, Date)], by="ym")
# forward BM: BM_Ret of NEXT month (align with returns_dt forward convention)
bmon <- merge(me_order[, .(Date, nxt)], bmon[, .(nxt=Date, BM_Ret)], by="nxt")
bench_dt <- bmon[, .(Date, BM_Ret)][!is.na(BM_Ret)]
saveRDS(bench_dt, file.path(OUT,"bench_dt.rds"))
cat("bench_dt rows:", nrow(bench_dt), " sample:", paste(round(head(bench_dt$BM_Ret,3),4),collapse=","), "\n")

cat("=== build_signal.R DONE ===\n")
