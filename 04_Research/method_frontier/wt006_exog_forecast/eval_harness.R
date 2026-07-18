# eval_harness.R — 스타일팩터 예측 theta의 canonical 실측 공용 하네스 (WT-006 R2 밤샘 lane 공용)
# 목적: 각 예측모델 lane이 측정을 재구현하지 않고 eval_theta(theta_dt,label)만 호출 → 일관·정확 실측.
# theta_dt: data.table(date, family, theta) — family∈{value,quality,momentum,low_vol,size,dividend}, theta≥0, sum=1/date.
# 반환: list(port_t=cap-w KOSPI200 portfolio_alpha_t_nw_lag3, ew_uni_t, oos_ret(3분할 중앙값), net_sr, calmar,
#            turnover, paired_vs_mom_t, paired_vs_static_t, n_months, lag1_port_t)
# ★PIT: 이 하네스는 *측정*만 한다. theta의 walk-forward PIT(무 look-ahead)는 lane 책임.
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts)})
setDTthreads(1)
.EH_ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(.EH_ROOT)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
.W5 <- "04_Research/method_frontier/wt005_factor_timing"
.fams <- c("value","quality","momentum","low_vol","size","dividend")

.FAM  <- as.data.table(read_parquet(file.path(.W5,"family_z_panel.parquet"))); .FAM[,Date:=as.Date(Date)]
.FEAT <- as.data.table(read_parquet(file.path(.W5,"family_feature_panel.parquet"))); .FEAT[,date:=as.Date(date)]
.Rg <- as.data.table(read_parquet(file.path(.W5,"grid_returns.parquet"))); .Rg[,Date:=as.Date(Date)]
.BMg<- as.data.table(read_parquet(file.path(.W5,"grid_bench.parquet"))); .BMg[,Date:=as.Date(Date)]
.LQg<- as.data.table(read_parquet(file.path(.W5,"grid_liq.parquet"))); .LQg[,Date:=as.Date(Date)]
.size_dt <- .FAM[, .(Date,Ticker,size=Size)]
.oos_dates <- sort(unique(as.Date(read_parquet(file.path(.W5,"theta_transformer_ensemble.parquet"))$date)))

if(!exists(".nw_t_mean")) {
  .nw_t_mean <- function(x, lag=3){ x<-x[is.finite(x)]; n<-length(x); if(n<8) return(NA_real_)
    m<-mean(x); e<-x-m; g0<-sum(e^2)/n; v<-g0
    for(l in 1:lag){ if(l>=n) break; c<-sum(e[1:(n-l)]*e[(l+1):n])/n; v<-v+2*(1-l/(lag+1))*c }
    se<-sqrt(v/n); if(!is.finite(se)||se<=0) return(NA_real_); m/se }
}
.canon <- function(score_dt){
  S <- score_dt[!is.na(score), .(Date,Ticker,score)]; S <- S[Date %in% .Rg$Date & Date %in% .oos_dates]
  canonical_screen_bt(S, .Rg, .BMg, top_n=25L, cost_bps_oneway=15, liq_dt=.LQg, liq_min=2e8,
                      run_id="wt006r2", strategy_id="wt006r2", periods_per_year=12L, diag_dual_basis=TRUE, size_dt=.size_dt)
}
.score_from_theta <- function(th){
  th <- as.data.table(th); th[,date:=as.Date(date)]
  W <- dcast(th, date ~ family, value.var="theta")
  for(fk in .fams) if(!(fk %in% names(W))) W[[fk]] <- 0
  setnames(W, .fams, paste0("th_",.fams))
  M <- merge(.FAM, W, by.x="Date", by.y="date"); sc <- numeric(nrow(M))
  for(fk in .fams){ z<-M[[fk]]; w<-M[[paste0("th_",fk)]]; z[is.na(z)]<-0; w[is.na(w)]<-0; sc<-sc+w*z }
  M[, score:=sc]; M[, .(Date,Ticker,score)]
}
.active_series <- function(res){ pr<-res$period_returns; pr[,active:=ret_net-benchmark_ret]; pr[,.(date,active,ret_net)] }
.calmar_of <- function(pr){ x<-xts(pr$ret_net,order.by=as.Date(pr$date)); n<-nrow(x)
  ann<-prod(1+coredata(x))^(12/n)-1; mdd<-as.numeric(maxDrawdown(x)); if(!is.finite(mdd)||mdd<=0) return(NA); ann/mdd }
.oos_ret_of <- function(pr){ a<-pr$active; n<-length(a); fr<-c(.55,.65,.75); sr<-function(x){s<-sd(x);if(!is.finite(s)||s<=0)return(NA);mean(x)/s*sqrt(12)}
  r<-sapply(fr,function(f){k<-floor(n*f); if(k<6||n-k<6)return(NA); is<-sr(a[1:k]); oo<-sr(a[(k+1):n]); if(is.na(is)||is<=0)return(NA); oo/is}); median(r,na.rm=TRUE) }
.paired_t <- function(a_t, a_s){ mg<-merge(a_t[,.(date,at=active)],a_s[,.(date,as=active)],by="date"); d<-mg$at-mg$as; .nw_t_mean(d,lag=3) }

# ---- 베이스라인 (static_EW, factor_momentum) 사전계산 ----
.FAM[, score_ew := rowMeans(.SD, na.rm=TRUE), .SDcols=.fams]
.mom_theta <- .FEAT[is.finite(tr_12m), {z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9); w<-exp(2*z); .(family=family, theta=w/sum(w))}, by=date]
.a_static <- .active_series(.canon(.FAM[,.(Date,Ticker,score=score_ew)]))
.a_mom    <- .active_series(.canon(.score_from_theta(.mom_theta)))

# ---- lag1 PIT 스트레스: theta를 1개월 shift(전월 가중 사용) → 동월 누출이면 붕괴, clean이면 완만 ----
.lag1_theta <- function(th){ th<-as.data.table(th); th[,date:=as.Date(date)]
  dts<-sort(unique(th$date)); lm<-data.table(date=dts, prevdate=shift(dts,1))[!is.na(prevdate)]
  merge(lm, th[,.(prevdate=date,family,theta)], by="prevdate", allow.cartesian=TRUE)[,.(date,family,theta)] }

#' eval_theta — theta를 canonical 실측
#' @param theta_dt data.table(date, family, theta)
#' @param label 문자열
#' @return named list metrics
eval_theta <- function(theta_dt, label="model"){
  th <- as.data.table(theta_dt); th[,date:=as.Date(date)]
  th <- th[date %in% .oos_dates]
  res <- .canon(.score_from_theta(th)); a <- .active_series(res)
  lag1 <- tryCatch(.canon(.score_from_theta(.lag1_theta(th)))$portfolio_alpha_t_nw_lag3, error=function(e) NA_real_)
  list(label=label, n_months=res$n_months,
       port_t=round(res$portfolio_alpha_t_nw_lag3,3),
       ew_uni_t=round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),
       oos_ret=round(.oos_ret_of(res$period_returns),3),
       net_sr=round(res$net_sr,3), calmar=round(.calmar_of(res$period_returns),3),
       turnover=round(res$turnover_annual,2),
       paired_vs_mom_t=round(.paired_t(a, .a_mom),3),
       paired_vs_static_t=round(.paired_t(a, .a_static),3),
       lag1_port_t=round(lag1,3))
}
.BASELINE_MOM_PORT_T <- round(.canon(.score_from_theta(.mom_theta))$portfolio_alpha_t_nw_lag3, 3)
cat(sprintf("[eval_harness] loaded. OOS=%d (%s~%s). baseline momentum port_t=%.3f. eval_theta(theta_dt,label) ready.\n",
            length(.oos_dates), as.character(min(.oos_dates)), as.character(max(.oos_dates)), .BASELINE_MOM_PORT_T))
