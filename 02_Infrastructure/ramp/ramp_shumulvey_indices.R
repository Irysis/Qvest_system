## ramp_shumulvey_indices.R — Shu & Mulvey (2024, arXiv 2410.14841) 충실 구현 STAGE 1.
## 논문의 7개 롱온리 스타일팩터 인덱스(Market + Value/Size/Momentum/Quality/LowVol/Growth)를
##   한국 raw에서 직접 구성. 펀더멘털 팩터는 FactorDB composite(load_month_factors, PIT C13/14/15)
##   를 가져와 tilt 점수로 사용(도훈 mandate: "FactorDB 구현된 거 가져와 써도 돼").
## 인덱스 = 월리밸 cap-weighted top-tercile tilt(MSCI smart-beta 방식, ~1/3 종목 cap-weight).
## 일별 인덱스 수익 = held set 고정(월), 일별 VW(전일 Size 가중, drift). active = factor - market.
## PIT: 월말 t 신호 → 익월 t+1 보유(1기 지연). 산출: outputs/ramp/shumulvey_index_returns.parquet
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(2); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
PG<-".cache/_smv_idx_prog.txt"; cat("start\n",file=PG); pg<-function(...)cat(sprintf(...),file=PG,append=TRUE)

## 논문 팩터 → FactorDB composite (전수조사 매핑). SMV_FACSET=broad → 전 패밀리 de-corr 광역셋(~21).
SMV_FACSET<-Sys.getenv("SMV_FACSET","paper6")
if(SMV_FACSET=="broad"){
  FAC<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
         Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
         Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
         Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
         LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
         Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
         Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
         ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
}else{
  FAC<-c(Value="V12_Composite_Value", Size="S01_Size", Momentum="M09_Composite_Mom",
         Quality="Q08_Composite_Quality", LowVol="D03_RealVol", Growth="GR07_Composite_Growth")
}
IDX<-c("Market",names(FAC))  # 1 market + N factor indices

## 1) rawdata 일별 (universe membership + Size + Ret), col_select
SMV_START<-Sys.getenv("SMV_START","2005-01-01"); SMV_OUT<-Sys.getenv("SMV_OUT","outputs/ramp/shumulvey_index_returns.parquet")
SMV_REBAL0<-Sys.getenv("SMV_REBAL0","2005-12-01")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",
     col_select=c("Date","Ticker","Ret","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]
rd<-rd[Date>=as.Date(SMV_START) & is.finite(Ret) & is.finite(Size) & Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]
rd<-rd[inuniv==TRUE]
setorder(rd,Ticker,Date)
rd[,Size_lag:=shift(Size,1),by=Ticker]   # 전일 시총(VW 가중, PIT)
pg("rawdata loaded rows=%d\n",nrow(rd))

## 2) 월말 거래일 (rebalance dates)
alld<-sort(unique(rd$Date)); ym<-format(alld,"%Y-%m")
rebal<-alld[!duplicated(ym,fromLast=TRUE)]      # 각 월 마지막 거래일
rebal<-rebal[rebal>=as.Date(SMV_REBAL0) & rebal<=as.Date(Sys.getenv("SMV_REBAL_END","2026-05-31"))]  # 기본값 = 구 하드코딩 보존(동작 불변). FQ-239 P0: 완결 월말만 지정할 것(진행월 factor_db 소비 금지)
pg("rebal dates=%d (%s ~ %s)\n",length(rebal),as.character(min(rebal)),as.character(max(rebal)))

## 3) 각 월말: load_month_factors → universe∩covered, 인덱스별 held set (top-tercile cap-w)
held<-list()   # index -> list of data.table(rebal, Ticker)
for(i in seq_along(rebal)){ sd<-rebal[i]
  uni<-rd[Date==sd,.(Ticker,Size)]; if(nrow(uni)<30){next}
  f<-tryCatch(as.data.table(load_month_factors(sd,factor_names=unname(FAC))),error=function(e)NULL)
  if(is.null(f)||nrow(f)==0){next}
  fm<-merge(f,uni,by="Ticker")    # universe ∩ covered, Size 부여
  for(nm in names(FAC)){ sub<-fm[Factor_Name==FAC[nm]]
    if(nrow(sub)<15){next}
    thr<-quantile(sub$Z_Score_Aligned, 2/3, na.rm=TRUE)   # 상위 1/3
    sel<-sub[Z_Score_Aligned>=thr]
    held[[nm]]<-rbind(held[[nm]], data.table(rebal=sd, Ticker=sel$Ticker))
  }
  held[["Market"]]<-rbind(held[["Market"]], data.table(rebal=sd, Ticker=uni$Ticker))
  if(i%%24==0)pg("  holdings %d/%d (%s)\n",i,length(rebal),as.character(sd))
}
pg("holdings built\n")

## 4) 일별 인덱스 수익: 각 거래일 d → 직전 월말(<d) set 적용, VW(Size_lag)
rebI<-as.integer(rebal)
gov_for<-function(dates){ k<-findInterval(as.integer(dates)-1L, rebI); ifelse(k>=1, rebal[pmax(k,1)], as.Date(NA)) }
# 거래일별 governing rebal (PIT: 전 월말)
dmap<-data.table(Date=alld); dmap[,gov:=gov_for(Date)]; dmap<-dmap[!is.na(gov)]

ret_wide<-data.table(Date=dmap$Date)
rd_ret<-rd[,.(Date,Ticker,Ret,Size_lag)]
for(nm in IDX){ H<-held[[nm]]; if(is.null(H)){ret_wide[[nm]]<-NA_real_;next}
  # 거래일 × held membership: governing month's set
  mem<-merge(dmap, H, by.x="gov", by.y="rebal", allow.cartesian=TRUE)[,.(Date,Ticker)]
  x<-merge(mem, rd_ret, by=c("Date","Ticker"))
  x<-x[is.finite(Ret)&is.finite(Size_lag)&Size_lag>0]
  idr<-x[,.(ret=sum(Size_lag*Ret)/sum(Size_lag)),by=Date]
  ret_wide<-merge(ret_wide, idr[,.(Date,ret)], by="Date", all.x=TRUE)
  setnames(ret_wide,"ret",nm)
  pg("  index %s daily built (n=%d)\n",nm,nrow(idr))
}
setorder(ret_wide,Date)
ret_wide<-ret_wide[is.finite(Market)]   # 시장 있는 날만

## 5) 메타 + 저장 (§2.4 규약)
attr(ret_wide,"as_of_date")<-as.character(max(ret_wide$Date))
out<-copy(ret_wide); out[,as_of_date:=max(Date)][,source_version:="shumulvey_v1_factordb_composite"]
write_parquet(out,SMV_OUT)

## 6) sanity: 연율화 active 수익 (factor - market), 논문 부호 대조
cat("\n=== Shu-Mulvey KR 인덱스 — 연율화 수익 & active(팩터-시장) ===\n")
n<-nrow(ret_wide); yrs<-as.numeric(diff(range(ret_wide$Date)))/365.25
ann<-function(r){r<-r[is.finite(r)]; (prod(1+r))^(252/length(r))-1}
mk<-ann(ret_wide$Market)
cat(sprintf("  period: %s ~ %s (%d days, %.1f yr)\n",as.character(min(ret_wide$Date)),as.character(max(ret_wide$Date)),n,yrs))
cat(sprintf("  %-10s ann_ret=%+.2f%%  (market baseline)\n","Market",100*mk))
for(nm in names(FAC)){ ar<-ann(ret_wide[[nm]]); act<-ar-mk
  cat(sprintf("  %-10s ann_ret=%+.2f%%  active=%+.2f%%/yr  cov=%.0f%%\n",nm,100*ar,100*act,100*mean(is.finite(ret_wide[[nm]]))))}
cat("\nSMV_IDX_DONE\n")
