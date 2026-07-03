#=============================================================================#
# DVFS + Mahalanobis Turbulence 오버레이 (dvfs_turb)
#
# 베이스 = 청정 기준선 dvfs_remeasure.R(US ETF 2007~, M01/M02/M07/B=11/20bps).
# 추가 = Mahalanobis Turbulence (Kritzman & Li 2010) 위기탐지 오버레이.
#   매 의사결정 시점, eligible 자산 252일 일별수익으로 μ·Σ(Ledoit-Wolf) 추정 →
#   당월말 수익벡터의 turbulence d = (r-μ)Σ⁻¹(r-μ). 과거 turbulence 분포의 90%
#   분위수(expanding, PIT) 초과 시 'turbulent' → EGARCH Spike와 OR로 위기분기 진입.
#   (데이터 동일=원본 대비 turbulence 순효과 격리. 데이터무관 신호라 KR 실투에도 이식.)
#=============================================================================#

pacman::p_load("quantmod","PerformanceAnalytics","tidyverse","magrittr","xts",
               "RiskPortfolios","rugarch","timeSeries","TTR","openxlsx")

egarch_spec <- ugarchspec(variance.model = list(model="eGARCH", garchOrder=c(1,1)),
                          mean.model = list(armaOrder=c(0,0)))
qm_root <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root, "04_Research", "dvaa_dvfs_revalidation")

# ---- 데이터: 원본 청정 기준선과 동일 (US ETF 2007~) ----
symbols_DVFS <- c('SPY','QQQ','IWM','ACWX','EFA','EEM','IYR','GLD','PDBC',
                  'IEF','TLT','LQD','HYG','TIP','AGG','EMB','SHV')
getSymbols(symbols_DVFS, src='yahoo', from='2007-01-01', auto.assign=TRUE)
price_DVFS <- do.call(cbind, lapply(symbols_DVFS, function(x) Ad(get(x)))) %>% setNames(symbols_DVFS)
price_DVFS <- na.locf(price_DVFS)
rets_DVFS  <- Return.calculate(price_DVFS); rets_DVFS <- rets_DVFS[-1, ]
spy_ohlc   <- OHLC(SPY)
spy_sma200 <- SMA(price_DVFS$SPY, n = 200)

ep <- endpoints(rets_DVFS, on='months'); rebalancing_dates <- index(rets_DVFS)[ep]
safe_assets <- c("GLD","TIP","TLT"); cash_asset <- "SHV"
mom_1<-1; mom_3<-3; mom_6<-6; mom_12<-12
B <- 11; garch_window <- 120
bull_market_threshold <- 0.99; bear_market_threshold <- 0.90
trend_confirmation_lookback <- 10; adx_period <- 14; adx_threshold <- 20
N <- length(symbols_DVFS)
turb_window <- 252; turb_q <- 0.90   # turbulence: 252일 추정, 90% 분위수 임계

wts<-list(); wts_sort<-list(); turb_history <- numeric(0)
signal_history <- xts(matrix(NA, nrow=length(rebalancing_dates), ncol=9), order.by=rebalancing_dates)
colnames(signal_history) <- c("VAA_Signal","GARCH_Signal","Final_Decision","Predicted_Vol",
                              "Vol_Threshold","Market_Trend","ADX_Value","Fit_Status","Turbulence")

for (i in 13:(length(ep))) {
  current_date <- index(rets_DVFS)[ep[i]]
  sub_ret_mom_1 <- rets_DVFS[ep[i-mom_1]:ep[i],]; sub_ret_mom_3 <- rets_DVFS[ep[i-mom_3]:ep[i],]
  sub_ret_mom_6 <- rets_DVFS[ep[i-mom_6]:ep[i],]; sub_ret_mom_12<- rets_DVFS[ep[i-mom_12]:ep[i],]
  cum_1<-Return.cumulative(sub_ret_mom_1); cum_3<-Return.cumulative(sub_ret_mom_3)
  cum_6<-Return.cumulative(sub_ret_mom_6); cum_12<-Return.cumulative(sub_ret_mom_12)
  cum_wm <- (cum_1*6 + cum_3*6 + cum_6*6 + cum_12*1)/19
  mom_window_full <- rets_DVFS[ep[i-mom_12]:ep[i],]
  eligible <- colnames(mom_window_full)[colSums(is.na(mom_window_full))==0]
  cw <- setNames(as.numeric(cum_wm), colnames(cum_wm))

  predicted_vol<-NA; vol_threshold<-NA; market_trend_ret<-NA; current_adx<-NA; fit_status<-NA

  # ---- Mahalanobis Turbulence (PIT: 과거 분포로 판정 후 history 추가) ----
  turb_now <- NA; turbulent <- FALSE
  if (length(eligible) >= 5) {
    win <- rets_DVFS[max(1, ep[i]-turb_window+1):ep[i], eligible, drop=FALSE]
    win <- win[complete.cases(win), , drop=FALSE]
    if (nrow(win) >= length(eligible) + 20) {
      mu <- colMeans(win)
      S  <- tryCatch(RiskPortfolios::covEstimation(as.matrix(win), control=list(type='lw')),
                     error=function(e) cov(as.matrix(win)))
      rl <- as.numeric(win[nrow(win), ])
      turb_now <- tryCatch(as.numeric(mahalanobis(rl, mu, S)), error=function(e) NA)
    }
  }
  if (!is.na(turb_now) && length(turb_history) >= 24) {
    if (turb_now > quantile(turb_history, turb_q, na.rm=TRUE)) turbulent <- TRUE
  }
  if (!is.na(turb_now)) turb_history <- c(turb_history, turb_now)

  current_spy_price<-as.numeric(price_DVFS[current_date,"SPY"]); current_spy_sma200<-as.numeric(spy_sma200[current_date])
  vol_percentile_threshold<-0.95
  if(!is.na(current_spy_price)&&!is.na(current_spy_sma200)) vol_percentile_threshold<-if(current_spy_price>current_spy_sma200) bull_market_threshold else bear_market_threshold

  garch_signal<-"Stable"
  if(i>13){
    prev_weights<-wts[[i-13]]; safe_held<-names(prev_weights)[prev_weights>0 & names(prev_weights)%in%safe_assets]
    safe_elig<-intersect(safe_assets,eligible); if(length(safe_elig)==0) safe_elig<-safe_assets
    prev_safe_asset_held<-if(length(safe_held)==0) names(which.min(cw[safe_elig])) else safe_held[1]
    garch_data_window<-rets_DVFS[(ep[i]-garch_window+1):ep[i], prev_safe_asset_held]
    fit<-tryCatch(ugarchfit(spec=egarch_spec,data=garch_data_window,solver='hybrid'),error=function(e)NULL)
    rv_fb<-function() sd(as.numeric(tail(rets_DVFS[1:ep[i],prev_safe_asset_held],garch_window)),na.rm=TRUE)*sqrt(252)
    if(!is.null(fit)&&inherits(fit,"uGARCHfit")){ pv<-as.numeric(sigma(ugarchforecast(fit,n.ahead=1)))*sqrt(252)
      if(!is.finite(pv)){pv<-rv_fb();fit_status<-2L}else fit_status<-1L } else {pv<-rv_fb();fit_status<-2L}
    predicted_vol<-pv
    hv<-rollapply(rets_DVFS[,prev_safe_asset_held],width=garch_window,FUN=sd,align="right")*sqrt(252)
    vol_threshold<-quantile(hv[1:ep[i]],vol_percentile_threshold,na.rm=TRUE)
    if(isTRUE(is.finite(pv)&&is.finite(vol_threshold)&&pv>vol_threshold)) garch_signal<-"Spike"
  }
  # ★ Turbulence = EGARCH Spike의 '확인 필터'로 사용(아래 분기). OR 방식(추가방어)은 무효로 폐기.

  safe_elig<-intersect(safe_assets,eligible); if(length(safe_elig)==0) safe_elig<-intersect(safe_assets,colnames(cum_wm))
  cash<-names(which.max(cw[safe_elig])); b<-cw[eligible]<cw[cash]
  P_wt<-ifelse(sum(b,na.rm=TRUE)/length(eligible) > B/length(symbols_DVFS),1,0)

  if(garch_signal=="Stable"){ final_decision<-ifelse(P_wt==1,"Risk-Off","Risk-On")
  } else {  # EGARCH Spike — Mahalanobis turbulence로 '확인'(거짓 Spike 필터, ADX/10일 추세확인 대체)
    market_trend_ret<-Return.cumulative(rets_DVFS[(ep[i]-trend_confirmation_lookback+1):ep[i],"SPY"])  # 로깅용
    current_adx<-as.numeric(last(ADX(spy_ohlc,n=adx_period)[paste0("/",current_date)])$ADX)            # 로깅용
    if(turbulent){   # Spike ∧ turbulent = 진짜 위기
      risky_elig<-intersect(setdiff(symbols_DVFS,cash_asset),eligible)
      risky_mom_avg<-mean(cw[risky_elig],na.rm=TRUE); if(is.na(risky_mom_avg)) risky_mom_avg<- -1
      final_decision<-ifelse(risky_mom_avg<0,"Absolute_Defense",ifelse(P_wt==1,"Risk-Off","Risk-On"))
    } else final_decision<-ifelse(P_wt==1,"Risk-Off","Risk-On")   # Spike이나 turbulence 없음 = 거짓 → VAA
  }

  wt<-setNames(rep(0,N),symbols_DVFS)
  if(final_decision=="Risk-On"){
    risky_elig<-intersect(setdiff(symbols_DVFS,cash_asset),eligible)
    top4<-names(sort(cw[risky_elig],decreasing=TRUE)); top4<-top4[seq_len(min(4,length(top4)))]
    if(length(top4)>=2){ covmat<-cov(sub_ret_mom_3[,top4],use="complete.obs")
      erc<-tryCatch(optimalPortfolio(covmat,control=list(type='erc',constraint='lo')),error=function(e){iv<-1/sqrt(diag(covmat));iv/sum(iv)})
      wt[top4]<-erc } else if(length(top4)==1) wt[top4]<-1 else wt[cash]<-1
  } else if(final_decision=="Risk-Off") wt[cash]<-1 else wt[cash_asset]<-1

  wts[[i-12]]<-xts(t(wt),order.by=index(rets_DVFS[ep[i]]))
  wts_sort[[i-12]]<-wts[[i-12]]%>%as.data.frame()%>%relocate(colnames(price_DVFS))
  signal_history[current_date,]<-c(ifelse(P_wt==1,1,0),ifelse(garch_signal=="Spike",1,0),
    match(final_decision,c("Risk-On","Risk-Off","Absolute_Defense")),round(predicted_vol*100,2),
    round(vol_threshold*100,2),round(as.numeric(market_trend_ret)*100,2),round(current_adx,2),
    ifelse(is.na(fit_status),NA,fit_status),round(turb_now,2))
}

wts_VAA_DVFS<-do.call(rbind,wts_sort)
rets_acct<-rets_DVFS; rets_acct[is.na(rets_acct)]<-0
P<-Return.portfolio(rets_acct,wts_VAA_DVFS,wealth.index=TRUE,verbose=TRUE)
to<-rowSums(abs(P$BOP.Weight-xts::lag.xts(P$EOP.Weight)),na.rm=TRUE); to[1]<-rowSums(abs(coredata(P$BOP.Weight)[1,,drop=FALSE]),na.rm=TRUE)
P$turnover<-xts(to,order.by=index(P$BOP.Weight)); P$net<-P$returns-P$turnover*0.002

check<-cbind(P$net,rets_acct$SPY)%>%na.omit(); colnames(check)<-c("DVFS_turb","SPY")
stratStats<-function(x){s<-rbind(table.AnnualizedReturns(x),maxDrawdown(x));s[5,]<-s[1,]/s[4,];s[6,]<-s[1,]/UlcerIndex(x);rownames(s)[4:6]<-c("MaxDD","Calmar","UlcerPI");s}

cat("\n===== DVFS_turb (Mahalanobis turbulence 오버레이) vs 원본 =====\n")
cat("원본 청정 기준선(remeasure): CAGR 14.30 / SR 0.854 / MDD 22.83 / Calmar 0.626\n\n")
print(round(stratStats(check),4))
cat("\nturbulent 발동 월 수:", sum(signal_history[,"GARCH_Signal"]==1 & !is.na(signal_history[,"Turbulence"]), na.rm=TRUE), "(GARCH_Signal=1 총)\n")
cat("2008 GFC(08.01~09.06):", round(as.numeric(Return.cumulative(check["2008-01/2009-06","DVFS_turb"]))*100,2),
    "% / 2022:", round(as.numeric(Return.cumulative(check["2022","DVFS_turb"]))*100,2), "%\n")
cat("\n최신 보유:\n"); lw<-wts_VAA_DVFS[nrow(wts_VAA_DVFS),,drop=FALSE]; print(round(lw[,as.numeric(lw[1,])>0,drop=FALSE],4))
saveRDS(P$net, file.path(out_dir,"dvfs_turb_net.rds"))
write.xlsx(as.data.frame(round(stratStats(check),4)), file.path(out_dir,"dvfs_turb_stratstats.xlsx"), rowNames=TRUE)
cat("\n저장:", out_dir, "\n")
