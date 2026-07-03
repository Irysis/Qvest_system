#=============================================================================#
# DVFS + DCC-GARCH 방어자산 선택 (dvfs_dcc)
#
# 베이스 = 청정 기준선 remeasure(US ETF 2007~, M01/M02/M07/B=11/20bps).
# 추가 = DCC-GARCH(Engle 2002) 시변상관으로 '방어 보유자산'을 선택.
#   매 리밸런스 직전 2년(504일) SPY+안전자산(GLD/TIP/TLT) 4종 DCC 재적합(PIT) →
#   SPY-각 안전자산 시변상관 ρ_t. Risk-Off/Absolute_Defense 시 모멘텀 대신
#   '시장과 가장 음(-)상관' 안전자산 선택(모든 ρ>0.2 동조 시 SHV 현금).
#   ★ breadth 기준(cash_b=모멘텀최고)은 원본 불변 — 방어 보유자산(cash_def)만 DCC.
#   목적: 2022형 채권-주식 동조(원본 -9.26% 주범) 회피.
#=============================================================================#

suppressMessages({
  pacman::p_load("quantmod","PerformanceAnalytics","tidyverse","magrittr","xts",
                 "RiskPortfolios","rugarch","rmgarch","timeSeries","TTR","openxlsx")
})

egarch_spec <- ugarchspec(variance.model=list(model="eGARCH",garchOrder=c(1,1)), mean.model=list(armaOrder=c(0,0)))
qm_root <- Sys.getenv("QM_ROOT", unset="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root,"04_Research","dvaa_dvfs_revalidation")

symbols_DVFS <- c('SPY','QQQ','IWM','ACWX','EFA','EEM','IYR','GLD','PDBC','IEF','TLT','LQD','HYG','TIP','AGG','EMB','SHV')
getSymbols(symbols_DVFS, src='yahoo', from='2007-01-01', auto.assign=TRUE)
price_DVFS <- do.call(cbind, lapply(symbols_DVFS, function(x) Ad(get(x)))) %>% setNames(symbols_DVFS)
price_DVFS <- na.locf(price_DVFS)
rets_DVFS  <- Return.calculate(price_DVFS); rets_DVFS <- rets_DVFS[-1,]
spy_ohlc <- OHLC(SPY); spy_sma200 <- SMA(price_DVFS$SPY, n=200)

ep <- endpoints(rets_DVFS,on='months'); rebalancing_dates <- index(rets_DVFS)[ep]
safe_assets <- c("GLD","TIP","TLT"); cash_asset <- "SHV"
mom_1<-1;mom_3<-3;mom_6<-6;mom_12<-12; B<-11; garch_window<-120
bull_market_threshold<-0.99; bear_market_threshold<-0.90
trend_confirmation_lookback<-10; adx_period<-14; adx_threshold<-20; N<-length(symbols_DVFS)
dcc_pos_thr <- 0.2; dcc_win <- 504   # 동조 임계 / DCC 적합 윈도우(2년)

# ---- DCC-GARCH spec (SPY + 안전자산 4종) ----
dcc_assets <- c("SPY","GLD","TIP","TLT")
uspec <- multispec(replicate(length(dcc_assets),
  ugarchspec(mean.model=list(armaOrder=c(0,0),include.mean=TRUE),
             variance.model=list(model='sGARCH',garchOrder=c(1,1)), distribution.model='norm')))
dcc_spec <- dccspec(uspec=uspec, dccOrder=c(1,1), distribution='mvnorm')

get_dcc_cor <- function(i) {
  wi <- max(1, ep[i]-dcc_win+1):ep[i]
  win <- rets_DVFS[wi, dcc_assets]; win <- win[complete.cases(win), ]
  if (nrow(win) < 250) return(NULL)
  fit <- tryCatch(dccfit(dcc_spec, data=as.matrix(win), fit.control=list(eval.se=FALSE)), error=function(e) NULL)
  if (is.null(fit)) return(NULL)
  R <- tryCatch(rcor(fit), error=function(e) NULL); if (is.null(R)) return(NULL)
  Rl <- R[,,dim(R)[3]]
  setNames(as.numeric(Rl["SPY", c("GLD","TIP","TLT")]), c("GLD","TIP","TLT"))
}

wts<-list(); wts_sort<-list(); dcc_log <- list()
for (i in 13:(length(ep))) {
  current_date <- index(rets_DVFS)[ep[i]]
  sub_ret_mom_1<-rets_DVFS[ep[i-mom_1]:ep[i],]; sub_ret_mom_3<-rets_DVFS[ep[i-mom_3]:ep[i],]
  sub_ret_mom_6<-rets_DVFS[ep[i-mom_6]:ep[i],]; sub_ret_mom_12<-rets_DVFS[ep[i-mom_12]:ep[i],]
  cum_1<-Return.cumulative(sub_ret_mom_1);cum_3<-Return.cumulative(sub_ret_mom_3)
  cum_6<-Return.cumulative(sub_ret_mom_6);cum_12<-Return.cumulative(sub_ret_mom_12)
  cum_wm<-(cum_1*6+cum_3*6+cum_6*6+cum_12*1)/19
  mom_window_full<-rets_DVFS[ep[i-mom_12]:ep[i],]
  eligible<-colnames(mom_window_full)[colSums(is.na(mom_window_full))==0]
  cw<-setNames(as.numeric(cum_wm),colnames(cum_wm))
  predicted_vol<-NA; vol_threshold<-NA; market_trend_ret<-NA; current_adx<-NA

  csp<-as.numeric(price_DVFS[current_date,"SPY"]); css<-as.numeric(spy_sma200[current_date])
  vol_percentile_threshold<-0.95
  if(!is.na(csp)&&!is.na(css)) vol_percentile_threshold<-if(csp>css) bull_market_threshold else bear_market_threshold

  garch_signal<-"Stable"
  if(i>13){
    prev_weights<-wts[[i-13]]; safe_held<-names(prev_weights)[prev_weights>0 & names(prev_weights)%in%safe_assets]
    safe_elig0<-intersect(safe_assets,eligible); if(length(safe_elig0)==0) safe_elig0<-safe_assets
    prev_safe<-if(length(safe_held)==0) names(which.min(cw[safe_elig0])) else safe_held[1]
    gdw<-rets_DVFS[(ep[i]-garch_window+1):ep[i], prev_safe]
    fit<-tryCatch(ugarchfit(spec=egarch_spec,data=gdw,solver='hybrid'),error=function(e)NULL)
    rv_fb<-function() sd(as.numeric(tail(rets_DVFS[1:ep[i],prev_safe],garch_window)),na.rm=TRUE)*sqrt(252)
    if(!is.null(fit)&&inherits(fit,"uGARCHfit")){pv<-as.numeric(sigma(ugarchforecast(fit,n.ahead=1)))*sqrt(252); if(!is.finite(pv)) pv<-rv_fb()} else pv<-rv_fb()
    predicted_vol<-pv
    hv<-rollapply(rets_DVFS[,prev_safe],width=garch_window,FUN=sd,align="right")*sqrt(252)
    vol_threshold<-quantile(hv[1:ep[i]],vol_percentile_threshold,na.rm=TRUE)
    if(isTRUE(is.finite(pv)&&is.finite(vol_threshold)&&pv>vol_threshold)) garch_signal<-"Spike"
  }

  # breadth 기준(cash_b=모멘텀최고; 원본 불변)
  safe_elig<-intersect(safe_assets,eligible); if(length(safe_elig)==0) safe_elig<-intersect(safe_assets,colnames(cum_wm))
  cash_b<-names(which.max(cw[safe_elig]))
  b<-cw[eligible]<cw[cash_b]; P_wt<-ifelse(sum(b,na.rm=TRUE)/length(eligible)>B/length(symbols_DVFS),1,0)

  # ★ 방어 보유자산(cash_def) — DCC 시변상관 기반
  dcc_cor<-get_dcc_cor(i)
  if(!is.null(dcc_cor)){
    cors<-dcc_cor[intersect(names(dcc_cor),safe_elig)]
    if(length(cors)==0) cash_def<-cash_b
    else if(all(cors>dcc_pos_thr)) cash_def<-if(cash_asset%in%eligible) cash_asset else cash_b
    else cash_def<-names(which.min(cors))
  } else cash_def<-cash_b
  dcc_log[[length(dcc_log)+1]]<-data.frame(date=as.character(current_date),
    gld=if(!is.null(dcc_cor))round(dcc_cor["GLD"],3)else NA, tip=if(!is.null(dcc_cor))round(dcc_cor["TIP"],3)else NA,
    tlt=if(!is.null(dcc_cor))round(dcc_cor["TLT"],3)else NA, cash_b=cash_b, cash_def=cash_def)

  if(garch_signal=="Stable"){ final_decision<-ifelse(P_wt==1,"Risk-Off","Risk-On")
  } else {
    market_trend_ret<-Return.cumulative(rets_DVFS[(ep[i]-trend_confirmation_lookback+1):ep[i],"SPY"])
    is_tn<-as.numeric(market_trend_ret)<0
    current_adx<-as.numeric(xts::last(ADX(spy_ohlc,n=adx_period)[paste0("/",current_date)])$ADX)
    is_ts<-!is.na(current_adx)&&current_adx>adx_threshold
    if(is_tn&&is_ts){ risky_elig<-intersect(setdiff(symbols_DVFS,cash_asset),eligible)
      rma<-mean(cw[risky_elig],na.rm=TRUE); if(is.na(rma)) rma<- -1
      final_decision<-ifelse(rma<0,"Absolute_Defense",ifelse(P_wt==1,"Risk-Off","Risk-On"))
    } else final_decision<-ifelse(P_wt==1,"Risk-Off","Risk-On")
  }

  wt<-setNames(rep(0,N),symbols_DVFS)
  if(final_decision=="Risk-On"){ risky_elig<-intersect(setdiff(symbols_DVFS,cash_asset),eligible)
    top4<-names(sort(cw[risky_elig],decreasing=TRUE)); top4<-top4[seq_len(min(4,length(top4)))]
    if(length(top4)>=2){covmat<-cov(sub_ret_mom_3[,top4],use="complete.obs")
      erc<-tryCatch(optimalPortfolio(covmat,control=list(type='erc',constraint='lo')),error=function(e){iv<-1/sqrt(diag(covmat));iv/sum(iv)}); wt[top4]<-erc
    } else if(length(top4)==1) wt[top4]<-1 else wt[cash_def]<-1
  } else if(final_decision=="Risk-Off") wt[cash_def]<-1 else wt[cash_asset]<-1   # ★ Risk-Off에 DCC cash_def

  wts[[i-12]]<-xts(t(wt),order.by=index(rets_DVFS[ep[i]]))
  wts_sort[[i-12]]<-wts[[i-12]]%>%as.data.frame()%>%relocate(colnames(price_DVFS))
}

wts_VAA_DVFS<-do.call(rbind,wts_sort)
rets_acct<-rets_DVFS; rets_acct[is.na(rets_acct)]<-0
P<-Return.portfolio(rets_acct,wts_VAA_DVFS,wealth.index=TRUE,verbose=TRUE)
to<-rowSums(abs(P$BOP.Weight-xts::lag.xts(P$EOP.Weight)),na.rm=TRUE); to[1]<-rowSums(abs(coredata(P$BOP.Weight)[1,,drop=FALSE]),na.rm=TRUE)
P$net<-P$returns - xts(to,order.by=index(P$BOP.Weight))*0.002
check<-cbind(P$net,rets_acct$SPY)%>%na.omit(); colnames(check)<-c("DVFS_dcc","SPY")
stratStats<-function(x){s<-rbind(table.AnnualizedReturns(x),maxDrawdown(x));s[5,]<-s[1,]/s[4,];s[6,]<-s[1,]/UlcerIndex(x);rownames(s)[4:6]<-c("MaxDD","Calmar","UlcerPI");s}

cat("\n===== DVFS_dcc (DCC-GARCH 방어자산선택) vs 원본 =====\n원본: CAGR 14.30 / SR 0.854 / MDD 22.83 / Calmar 0.626\n\n")
print(round(stratStats(check),4))
cat("\n2008 GFC:", round(as.numeric(Return.cumulative(check["2008-01/2009-06","DVFS_dcc"]))*100,2),
    "% / 2022:", round(as.numeric(Return.cumulative(check["2022","DVFS_dcc"]))*100,2), "% (원본 2022 -9.26%)\n")
dcc_df<-do.call(rbind,dcc_log)
cat("\n방어자산이 모멘텀과 달라진 월 수:", sum(dcc_df$cash_b!=dcc_df$cash_def,na.rm=TRUE), "/", nrow(dcc_df), "\n")
cat("2022 DCC 상관·선택:\n"); print(dcc_df[grepl("2022",dcc_df$date),])
write.xlsx(dcc_df, file.path(out_dir,"dvfs_dcc_log.xlsx"))
saveRDS(P$net, file.path(out_dir,"dvfs_dcc_net.rds"))
cat("\n저장:", out_dir, "\n")
