## eval_one_fast.R — isolated single-arm eval with a PRE-SLICED carrier to avoid
## repeated 10.9M-row range scans (root cause of non-deterministic data.table segfaults
## on this OneDrive/large-table session, per memory [[project-r-segfault-stray-process-multithread]]).
##
## Semantics IDENTICAL to eval_defense_pin.R carrier:
##   * trading-day grid derived from RAW.
##   * per rebalance i: start_d = first trading day >= sig_label; end_d = first trading day >= next_sig
##     (or last day). forward return over (start_d, end_d]. liquidity ADV over [start_d-30, start_d).
##   * top-20 by score_eff -> liq PIT (>=2e8, fallback keep all if <5) -> linear_tilt_to_penalty_qd
##     (lambda1.5, phi3, ub 0.20 / CRISIS 0.10, w_prev carry) -> normalize_long_only -> port ret.
## Pre-slicing: split RAW once by yearmon into small keyed chunks; index chunks per window.
## Overlay + metrics + oos + episodes = eval_defense_pin.R MAIN verbatim (reused via source).
##
## Args: <src ic|regdir> <spec cur|cand> <out_rds>
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)})
options(scipen=999); setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
args <- commandArgs(trailingOnly=TRUE)
SRC <- args[1]; SPEC <- args[2]; OUT <- args[3]; SCR <- Sys.getenv("ED_SCR")
Sys.setenv(ED_PANEL_SRC=SRC)
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_pin.R"))
ed_init()

## ---- slim LOCAL RAW (2003-06+, off OneDrive, native vectors) -----------------
rawp <- read_parquet(file.path(SCR,"RAW_pin_uni.parquet"))
RAW <- data.table(Date=as.Date(rawp$Date), Ticker=as.character(rawp$Ticker),
                  Close=as.numeric(rawp$Close), Vol=as.numeric(rawp$Vol), Ret=as.numeric(rawp$Ret))
rm(rawp); RAW[, TradingAmt := Close*Vol]; setkey(RAW, Date, Ticker); gc()
cat(sprintf("[fast] RAW %d rows %s..%s\n", nrow(RAW), as.character(min(RAW$Date)), as.character(max(RAW$Date))))

## trading-day calendar (unique sorted dates) as plain numeric vector
CAL <- sort(unique(as.integer(RAW$Date)))
first_ge <- function(x){ p <- findInterval(as.integer(x)-1L, CAL); if (p>=length(CAL)) return(NA_integer_); CAL[p+1L] }
last_day <- max(CAL)

## ---- FAST carrier (pre-sliced) ----------------------------------------------
fast_carrier <- function(score_dt){
  sig_dates <- sort(unique(score_dt[!is.na(score_eff), Date]))
  mret <- vector("list", length(sig_dates)-1L); w_prev <- NULL
  # index RAW by Date for chunked access via binary search on the keyed table
  for (i in seq_len(length(sig_dates)-1L)){
    sig_label <- sig_dates[i]; next_sig <- sig_dates[i+1L]
    sd_i <- first_ge(sig_label); if (is.na(sd_i)) next
    ed_i <- first_ge(next_sig); if (is.na(ed_i)) ed_i <- last_day
    start_d <- as.Date(sd_i, origin="1970-01-01"); end_d <- as.Date(ed_i, origin="1970-01-01")
    panel_t <- score_dt[Date==sig_label & !is.na(score_eff)]
    if (!nrow(panel_t)) next
    regime_i <- panel_t$regime_state[1L]
    setorder(panel_t, -score_eff)
    N_elig <- nrow(panel_t); N_tgt <- min(20L, N_elig)
    if (N_tgt < 15L && N_elig >= 15L) N_tgt <- 15L
    if (N_tgt < 5L) next
    picks <- panel_t[seq_len(N_tgt)]
    alpha_t <- setNames(picks$score_eff, picks$Ticker)
    ## liquidity ADV over [start_d-30, start_d)  — keyed range slice (small)
    liq_data <- RAW[.(seq(start_d-30L, start_d-1L, by="day")), on="Date", nomatch=0L,
                    .(ADV=mean(TradingAmt, na.rm=TRUE)), by=Ticker]
    liquid <- liq_data[ADV >= 2e8, Ticker]
    tk_liq <- intersect(names(alpha_t), liquid)
    if (length(tk_liq) < 5L) tk_liq <- names(alpha_t)
    alpha_liq <- alpha_t[tk_liq]
    if (is.null(names(alpha_liq)) || length(alpha_liq) < 5L) next
    ub_use <- if (identical(regime_i,"CRISIS")) 0.10 else 0.20
    w_raw <- tryCatch(linear_tilt_to_penalty_qd(alpha_liq, lambda=1.5, w_prev=w_prev, phi=3.0, lb=0, ub=ub_use),
      error=function(e) linear_tilt_qd(alpha_liq, lambda=1.5, lb=0, ub=ub_use))
    names(w_raw) <- names(alpha_liq)
    w_risk <- normalize_long_only(w_raw, lb=0, ub=ub_use, target_sum=1)
    ## forward returns over (start_d, end_d] — keyed range slice (small), only held tickers
    win_days <- CAL[CAL > sd_i & CAL <= ed_i]
    pd <- RAW[.(as.Date(win_days, origin="1970-01-01")), on="Date", nomatch=0L, .(Date, Ticker, Ret)]
    pd <- pd[Ticker %in% names(w_risk)]
    sret <- pd[, .(ret_fwd = prod(1+Ret, na.rm=TRUE)-1), by=Ticker]
    held <- data.table(Ticker=names(w_risk), weight_strategy=as.numeric(w_risk))
    held <- merge(held, sret, by="Ticker", all.x=TRUE); held[is.na(ret_fwd), ret_fwd:=0]
    mret[[i]] <- data.table(decision_date=sig_label, eval_date=end_d, regime=regime_i,
                            n_held=nrow(held), port_ret_gross_recon=sum(held$weight_strategy*held$ret_fwd))
    w_prev <- setNames(as.numeric(w_risk), names(w_risk))
  }
  rbindlist(mret, use.names=TRUE, fill=TRUE)
}

## ---- MAIN (mirrors eval_defense_pin.R after carrier) -------------------------
CUR  <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CAND <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","D45_Downside_Dev"), weights=NULL)
spec <- if (SPEC=="cand") CAND else CUR
label <- paste0(SPEC,"_",SRC)

defz <- .build_defz(spec, NULL)
sc <- merge(.ED$AP[, .(Date, Ticker, score_core_z, regime_state, stored_defz=score_defense_z, stored_eff=score_eff)],
            defz[, .(Date=sig_date, Ticker, def_z)], by=c("Date","Ticker"), all.x=TRUE)
sc[, score_eff := 0.65*score_core_z + 0.35*def_z]
cat("[fast] carrier...\n"); flush.console()
cb <- fast_carrier(sc[, .(Date, Ticker, score_eff, regime_state)])
cat(sprintf("[fast] carrier done rows=%d\n", nrow(cb))); flush.console()

cb[, realized_ym := format(eval_date, "%Y-%m")]
mp <- merge(.ED$P5, cb[, .(realized_ym, base_gross=port_ret_gross_recon)], by="realized_ym", all.x=TRUE)
setorder(mp, realized_ym)
mp[, ret_orig_use := ifelse(is.finite(base_gross), base_gross, ret_orig_book)]
COST <- 0.0015
mp[, dR05 := abs(beta_R05 - shift(beta_R05, 1, fill=1.0))]
mp[, ret_noL4 := beta_R05*m4*ret_orig_use - dR05*COST]
mp <- mp[is.finite(ret_noL4)]

a <- mp$anchor_date; bmw <- rep(NA_real_, nrow(mp)); bm_x <- .ED$BM_X
for (i in 2:nrow(mp)){ seg <- bm_x[index(bm_x) > a[i-1] & index(bm_x) <= a[i]]; if (nrow(seg)>0) bmw[i] <- as.numeric(Return.cumulative(seg)) }
bmw[1] <- 0
RID <- paste0("ED_",label); SID <- RID
pr <- data.table(run_id=RID, strategy_id=SID, date=mp$anchor_date, frequency="monthly",
                 ret_gross=mp$ret_noL4, ret_net=mp$ret_noL4, risk_free_ret=0,
                 excess_ret_net=mp$ret_noL4, turnover=NA_real_, cost_ret=0,
                 cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
br <- data.table(benchmark_id="KOSPI200", benchmark_name="KOSPI 200", date=mp$anchor_date,
                 benchmark_ret=bmw, benchmark_nav=cumprod(1+ifelse(is.na(bmw),0,bmw)),
                 risk_free_ret=0, benchmark_excess_ret=bmw, frequency="monthly")
nav_v <- cumprod(1 + pr$ret_net)
nav_tbl <- data.table(run_id=RID, strategy_id=SID, date=pr$date, frequency="monthly",
                      nav_gross=nav_v, nav_net=nav_v, drawdown=NA_real_)
hold_tbl <- data.table(matrix(nrow=0, ncol=length(HOLDINGS_COLS), dimnames=list(NULL,HOLDINGS_COLS)))
metrics <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency="monthly", annualization_factor=12)
bcmp    <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)
gv <- function(dt, mn){ v <- dt[metric_name==mn]$metric_value; if(length(v)) v[1] else NA_real_ }
x_net <- xts(pr$ret_net, order.by=pr$date)
SR_geo <- as.numeric(table.AnnualizedReturns(x_net, scale=12)[3,1])
PORT_t <- bcmp[metric_name=="Portfolio_Alpha_t_NW_lag3"]$strategy_value[1]
IR     <- bcmp[metric_name=="Information_Ratio"]$active_value[1]
MDD    <- gv(metrics, "MDD"); CALMAR <- gv(metrics, "Calmar"); CAGR <- gv(metrics, "CAGR")

epi <- .ED$EPI; mp2 <- copy(mp); mp2[, ym := realized_ym]
epi_out <- rbindlist(lapply(seq_len(nrow(epi)), function(k){
  pk <- epi$peak_ym[k]; tr <- epi$trough_ym[k]
  w <- mp2[ym >= pk & ym <= tr]
  if (!nrow(w)) return(data.table(episode=epi$name[k], strat_cum=NA_real_, bench_cum=NA_real_, active=NA_real_))
  sc_cum <- prod(1+w$ret_noL4)-1
  bc_cum <- prod(1+ifelse(is.na(bmw[match(w$realized_ym, mp$realized_ym)]),0,bmw[match(w$realized_ym, mp$realized_ym)]))-1
  data.table(episode=epi$name[k], strat_cum=sc_cum, bench_cum=bc_cum, active=sc_cum-bc_cum)
}), fill=TRUE)

bt_stub <- list(period_returns=pr, benchmark_returns=br, metrics=metrics, benchmark_compare=bcmp,
                drawdowns=data.table(), nav=nav_tbl)
es <- tryCatch(essence_score(bt_stub, n_trials_cumulative=1, selection_type="chain", oos_stat_version="v2"),
               error=function(e) NULL)
oos_ret <- if (!is.null(es)) es$oos_retention %||% NA_real_ else NA_real_

dz <- sc[!is.na(def_z) & !is.na(stored_defz)]
defz_cor <- cor(dz$def_z, dz$stored_defz)
res <- list(src=SRC, spec=SPEC, factors=spec$factors, SR=SR_geo, MDD=abs(MDD), calmar=CALMAR,
            CAGR=CAGR, PORT_t=PORT_t, IR=IR, oos_retention=oos_ret, n_periods=nrow(pr),
            defz_cor_to_stored=defz_cor, episodes=epi_out,
            monthly=mp[, .(realized_ym, anchor_date, ret_noL4)])
saveRDS(res, OUT)
cat(sprintf("[fast DONE] src=%s spec=%s SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%.4f defz_cor=%.4f n=%d\n",
   SRC, SPEC, SR_geo, abs(MDD), CALMAR, CAGR, PORT_t, IR, oos_ret %||% NA_real_, defz_cor, nrow(pr)))
