## run_one_arm_hardened.R — ONE spec x ONE panel, memory-lean carrier (segfault-hardened).
## Identical construction/metrics to eval_defense_pin.R; only the carrier date-scan is
## replaced with a precomputed trading-date index + split-by-month forward-return map to
## avoid 240x full-scans of the 13.9M-row RAW (the observed segfault locus on this box).
## Verified equivalent: reproduces eval_defense_pin recon numbers within float tol.
## Args: SRC(ic|regdir)  SPEC(cur|cand)  OUTTAG
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); setDTthreads(1L)
suppressWarnings(try(arrow::set_io_thread_count(1L), silent=TRUE))
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(R,"02_Infrastructure/portfolio/strategy_tilt_weights.R"))
source(file.path(R,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(R,"02_Infrastructure/contracts/essence_score.R"))
setDTthreads(1L)
OUT <- file.path(R,"stage_artifacts/pg2_defense_optimize")
S <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"

args <- commandArgs(trailingOnly=TRUE)
SRC <- args[1]; SPEC_ID <- args[2]; OUTTAG <- args[3]
stopifnot(SRC %in% c("ic","regdir"), SPEC_ID %in% c("cur","cand"))
CUR  <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
CAND <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","RE07_Crisis_Beta"), weights=NULL)
spec <- if (SPEC_ID=="cur") CUR else CAND

.winsor_z <- function(x, sigma=2.5){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}
.zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)x-m else (x-m)/s}

## ---- inputs -----------------------------------------------------------------
panel_file <- if (identical(SRC,"ic")) "defense_factor_panel.parquet" else "defense_factor_panel_regdir.parquet"
PANEL <- as.data.table(read_parquet(file.path(OUT,panel_file))); PANEL[, sig_date := as.Date(sig_date)]
ap <- as.data.table(read_parquet(file.path(R,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet"))); ap[, Date := as.Date(Date)]
AP <- ap[, .(Date, Ticker, score_core_z, score_defense_z, score_eff, regime_state)]
raw <- as.data.table(read_parquet(file.path(S,"RAWDATA_pin.parquet"), col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]; raw[, TradingAmt := Close*Vol]; setkey(raw, Date, Ticker)
p5 <- fread(file.path(R,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p5[, anchor_date := as.Date(anchor_date)]; setorder(p5, realized_ym)
P5 <- p5[, .(realized_ym, anchor_date, regime5=regime, beta_R05, m4, ret_orig_book=ret_orig)]
bm <- as.data.table(read_parquet(file.path(S,"benchmark_pin.parquet"))); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date); BM_X <- xts(bm$BM_Ret, order.by=bm$Date)
EPI <- fread(file.path(R,"stage_artifacts/pg2_defense_drawdown/episodes.csv"))
cat(sprintf("[in] SRC=%s SPEC=%s panel_rows=%d raw_rows=%d\n",SRC,SPEC_ID,nrow(PANEL),nrow(raw))); flush.console()

## precomputed sorted unique trading dates (avoids repeated min(raw[Date>=x]) full scans)
TD <- sort(unique(raw$Date))
first_ge <- function(x){ i <- findInterval(x - 1e-9, as.numeric(TD)); if (i>=length(TD)) return(TD[length(TD)]); TD[i+1L] }

## ---- def_z per sig_date (canonical EW, NA propagates) -----------------------
build_defz <- function(spec){
  sds <- sort(unique(PANEL$sig_date)); out <- vector("list", length(sds))
  facs <- spec$factors; w <- setNames(rep(1/length(facs), length(facs)), facs)
  for (i in seq_along(sds)){
    SD <- sds[i]; sub <- PANEL[sig_date==SD & Factor_Name %in% facs]
    if (!nrow(sub)) next
    fw <- dcast(sub, Ticker ~ Factor_Name, value.var="Z_Aligned", fill=NA_real_)
    facp <- intersect(facs, names(fw)); if (!length(facp)) next
    score_vec <- rep(0, nrow(fw))
    for (fn in facp){ cv <- fw[[fn]]; if (all(is.na(cv))) next; score_vec <- score_vec + as.numeric(w[fn])*.winsor_z(cv,2.5) }
    fw[, Score_Defense := score_vec]; fw[, def_z := .zc(Score_Defense)]
    out[[i]] <- fw[, .(sig_date=SD, Ticker, def_z)]
  }
  rbindlist(out, use.names=TRUE, fill=TRUE)
}
defz <- build_defz(spec); cat(sprintf("[defz] rows=%d\n",nrow(defz))); flush.console()

sc <- merge(AP[, .(Date, Ticker, score_core_z, regime_state, stored_defz=score_defense_z, stored_eff=score_eff)],
            defz[, .(Date=sig_date, Ticker, def_z)], by=c("Date","Ticker"), all.x=TRUE)
sc[, score_eff := 0.65*score_core_z + 0.35*def_z]

## ---- carrier walk-forward (memory-lean) -------------------------------------
## Pre-split forward returns by month window using precomputed TD; identical logic to
## eval_defense_pin .carrier_book: top-20 by score_eff -> liq PIT [t-30,t-1)>=2e8 ->
## linear_tilt_to_penalty_qd(1.5,phi3,ub 0.20/CRISIS0.10) -> forward prod(1+Ret)-1.
carrier_book <- function(score_dt){
  sig_dates <- sort(unique(score_dt[!is.na(score_eff), Date]))
  mret <- vector("list", length(sig_dates)-1L); w_prev <- NULL
  setkey(raw, Date)  # key on Date for range scans
  for (i in seq_len(length(sig_dates)-1L)){
    sig_label <- sig_dates[i]; next_sig <- sig_dates[i+1L]
    start_d <- first_ge(sig_label); if (is.na(start_d)) next
    end_d <- first_ge(next_sig); if (is.na(end_d)) end_d <- TD[length(TD)]
    panel_t <- score_dt[Date==sig_label & !is.na(score_eff)]; if (!nrow(panel_t)) next
    regime_i <- panel_t$regime_state[1L]
    setorder(panel_t, -score_eff)
    N_elig <- nrow(panel_t); N_tgt <- min(20L, N_elig); if (N_tgt<15L && N_elig>=15L) N_tgt <- 15L
    if (N_tgt < 5L) next
    picks <- panel_t[seq_len(N_tgt)]; alpha_t <- setNames(picks$score_eff, picks$Ticker)
    ## liquidity PIT window [start_d-30, start_d)
    liq_data <- raw[Date >= (start_d-30L) & Date < start_d, .(ADV=mean(TradingAmt,na.rm=TRUE)), by=Ticker]
    liquid <- liq_data[ADV >= 2e8, Ticker]
    tk_liq <- intersect(names(alpha_t), liquid); if (length(tk_liq) < 5L) tk_liq <- names(alpha_t)
    alpha_liq <- alpha_t[tk_liq]; if (is.null(names(alpha_liq)) || length(alpha_liq) < 5L) next
    ub_use <- if (identical(regime_i,"CRISIS")) 0.10 else 0.20
    w_raw <- tryCatch(linear_tilt_to_penalty_qd(alpha_liq, lambda=1.5, w_prev=w_prev, phi=3.0, lb=0, ub=ub_use),
                      error=function(e) linear_tilt_qd(alpha_liq, lambda=1.5, lb=0, ub=ub_use))
    names(w_raw) <- names(alpha_liq); w_risk <- normalize_long_only(w_raw, lb=0, ub=ub_use, target_sum=1)
    pd <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
    sret <- pd[, .(ret_fwd = prod(1+Ret, na.rm=TRUE)-1), by=Ticker]
    held <- data.table(Ticker=names(w_risk), weight_strategy=as.numeric(w_risk))
    held <- merge(held, sret, by="Ticker", all.x=TRUE); held[is.na(ret_fwd), ret_fwd:=0]
    mret[[i]] <- data.table(decision_date=sig_label, eval_date=end_d, regime=regime_i,
                            n_held=nrow(held), port_ret_gross_recon=sum(held$weight_strategy*held$ret_fwd))
    w_prev <- setNames(as.numeric(w_risk), names(w_risk))
  }
  rbindlist(mret, use.names=TRUE, fill=TRUE)
}
cb <- carrier_book(sc[, .(Date, Ticker, score_eff, regime_state)])
cat(sprintf("[carrier] rows=%d\n",nrow(cb))); flush.console()

## ---- overlay + noL4 + metrics (verbatim to eval_defense_pin) ----------------
cb[, realized_ym := format(eval_date, "%Y-%m")]
mp <- merge(P5, cb[, .(realized_ym, base_gross=port_ret_gross_recon)], by="realized_ym", all.x=TRUE); setorder(mp, realized_ym)
mp[, ret_orig_use := ifelse(is.finite(base_gross), base_gross, ret_orig_book)]
COST <- 0.0015; mp[, dR05 := abs(beta_R05 - shift(beta_R05,1,fill=1.0))]
mp[, ret_noL4 := beta_R05*m4*ret_orig_use - dR05*COST]; mp <- mp[is.finite(ret_noL4)]
a <- mp$anchor_date; bmw <- rep(NA_real_, nrow(mp))
for (i in 2:nrow(mp)){ seg <- BM_X[index(BM_X) > a[i-1] & index(BM_X) <= a[i]]; if (nrow(seg)>0) bmw[i] <- as.numeric(Return.cumulative(seg)) }
bmw[1] <- 0
RID <- paste0("ED_",OUTTAG); SID <- RID
pr <- data.table(run_id=RID, strategy_id=SID, date=mp$anchor_date, frequency="monthly",
  ret_gross=mp$ret_noL4, ret_net=mp$ret_noL4, risk_free_ret=0, excess_ret_net=mp$ret_noL4,
  turnover=NA_real_, cost_ret=0, cash_weight=NA_real_, leverage=NA_real_, n_holdings=NA_integer_)
br <- data.table(benchmark_id="KOSPI200", benchmark_name="KOSPI 200", date=mp$anchor_date,
  benchmark_ret=bmw, benchmark_nav=cumprod(1+ifelse(is.na(bmw),0,bmw)), risk_free_ret=0,
  benchmark_excess_ret=bmw, frequency="monthly")
nav_v <- cumprod(1 + pr$ret_net)
nav_tbl <- data.table(run_id=RID, strategy_id=SID, date=pr$date, frequency="monthly", nav_gross=nav_v, nav_net=nav_v, drawdown=NA_real_)
hold_tbl <- data.table(matrix(nrow=0, ncol=length(HOLDINGS_COLS), dimnames=list(NULL,HOLDINGS_COLS)))
metrics <- build_metrics(nav_tbl, pr, hold_tbl, RID, SID, frequency="monthly", annualization_factor=12)
bcmp    <- build_benchmark_compare(pr, br, RID, SID, annualization_factor=12)
gv <- function(dt, mn){ v <- dt[metric_name==mn]$metric_value; if(length(v)) v[1] else NA_real_ }
SR_geo <- as.numeric(table.AnnualizedReturns(xts(pr$ret_net, order.by=pr$date), scale=12)[3,1])
PORT_t <- bcmp[metric_name=="Portfolio_Alpha_t_NW_lag3"]$strategy_value[1]
IR     <- bcmp[metric_name=="Information_Ratio"]$active_value[1]
MDD    <- gv(metrics,"MDD"); CALMAR <- gv(metrics,"Calmar"); CAGR <- gv(metrics,"CAGR")
## episode active
mp2 <- copy(mp); mp2[, ym := realized_ym]
epi_out <- rbindlist(lapply(seq_len(nrow(EPI)), function(k){
  pk <- EPI$peak_ym[k]; tr <- EPI$trough_ym[k]; w <- mp2[ym>=pk & ym<=tr]
  if (!nrow(w)) return(data.table(episode=EPI$name[k], active=NA_real_))
  sc_cum <- prod(1+w$ret_noL4)-1
  bc_cum <- prod(1+ifelse(is.na(bmw[match(w$realized_ym, mp$realized_ym)]),0,bmw[match(w$realized_ym, mp$realized_ym)]))-1
  data.table(episode=EPI$name[k], strat_cum=sc_cum, bench_cum=bc_cum, active=sc_cum-bc_cum)
}), fill=TRUE)
## oos v2
bt_stub <- list(period_returns=pr, benchmark_returns=br, metrics=metrics, benchmark_compare=bcmp, drawdowns=data.table(), nav=nav_tbl)
es <- tryCatch(essence_score(bt_stub, n_trials_cumulative=1, selection_type="chain", oos_stat_version="v2"), error=function(e){cat("[ess err]",conditionMessage(e),"\n");NULL})
oos_ret <- if (!is.null(es)) es$oos_retention %||% NA_real_ else NA_real_

out <- list(SRC=SRC, SPEC_ID=SPEC_ID, spec=spec$factors,
  SR=SR_geo, MDD=abs(MDD), calmar=CALMAR, CAGR=CAGR, PORT_t=PORT_t, IR=IR,
  oos_retention=oos_ret, n_periods=nrow(pr),
  monthly=mp[, .(realized_ym, anchor_date, beta_R05, m4, ret_orig_use, ret_orig_book, ret_noL4)],
  benchmark=data.table(realized_ym=mp$realized_ym, bmw=bmw),
  episodes=epi_out)
saveRDS(out, file.path(OUT, paste0(OUTTAG,".rds")))
cat(sprintf("[DONE %s] SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%s n=%d\n",
    OUTTAG, SR_geo, abs(MDD), CALMAR, CAGR, PORT_t, IR, paste(round(oos_ret,4),collapse=","), nrow(pr)))
