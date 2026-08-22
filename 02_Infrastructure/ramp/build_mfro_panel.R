## build_mfro_panel.R — MFRO(Multi-Factor Rotation Overlay) 월간 패널 빌더
## 산출: 종목×월 팩터 z(21종) + 유니버스 + Size + 유동성 + 익월 수익 → outputs/ramp/mfro_panel.parquet
## PIT: load_month_factors() 경유(C13/14/15). 월말 sd 의 z → 익월(sd+1M) 수익에 적용(dec_lag=1).
suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/factor_db/factor_db_connector.R")
pg<-function(...)cat(sprintf(...))

FAC<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
       Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
       Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
       Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
       LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
       Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
       Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
       ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")

rd<-as.data.table(read_parquet(".cache/rawdata.parquet",
     col_select=c("Date","Ticker","Ret","Size","Close","Vol","K200","KQ150")))
rd[,Date:=as.Date(Date)]
rd<-rd[Date>=as.Date("2005-01-01") & is.finite(Ret) & is.finite(Size) & Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]
rd<-rd[inuniv==TRUE]; setorder(rd,Ticker,Date)
## 유동성: 20일 평균 거래대금 (t-1 PIT, C10)
rd[,tv:=Close*Vol]
rd[,adv20:=shift(frollmean(tv,20,align="right"),1),by=Ticker]
rd[,ym:=format(Date,"%Y-%m")]
pg("rawdata rows=%d tickers=%d\n",nrow(rd),uniqueN(rd$Ticker))

## 월말 거래일 (완결 월만)
alld<-sort(unique(rd$Date)); ymv<-format(alld,"%Y-%m")
rebal<-alld[!duplicated(ymv,fromLast=TRUE)]
rebal<-rebal[rebal>=as.Date("2005-12-01") & rebal<=as.Date("2026-07-31")]
pg("rebal n=%d (%s ~ %s)\n",length(rebal),as.character(min(rebal)),as.character(max(rebal)))

## 월간 종목 수익 (익월 적용용)
mret<-rd[,.(mret=prod(1+Ret)-1, Size_eom=last(Size)),by=.(Ticker,ym)]
setorder(mret,Ticker,ym)
mret[,fwd_ret:=shift(mret,1,type="lead"),by=Ticker]      # 익월 수익 = 결정월 z 의 표적
mret[,fwd_ym:=shift(ym,1,type="lead"),by=Ticker]

rows<-vector("list",length(rebal))
for(i in seq_along(rebal)){ sd<-rebal[i]; ymi<-format(sd,"%Y-%m")
  uni<-rd[Date==sd,.(Ticker,Size,adv20)]
  if(nrow(uni)<30) next
  f<-tryCatch(as.data.table(load_month_factors(sd,factor_names=unname(FAC))),error=function(e)NULL)
  if(is.null(f)||nrow(f)==0) next
  f<-f[Factor_Name %in% unname(FAC),.(Ticker,Factor_Name,Z=Z_Score_Aligned)]
  inv<-setNames(names(FAC),unname(FAC)); f[,fk:=inv[Factor_Name]]
  W<-dcast(f,Ticker~fk,value.var="Z",fun.aggregate=function(x)mean(x,na.rm=TRUE))
  ## ★열 이름 충돌 방지 (2026-08-22): uni 의 Size(시총)와 팩터 S01_Size 가 같은 이름이라
  ##   merge 가 Size.x/Size.y 로 갈랐다 — 팩터 열이 조용히 사라지는 계통. 병합 전에 개명한다.
  setnames(uni,"Size","mktcap")
  M<-merge(uni,W,by="Ticker")
  if(any(grepl("\.(x|y)$",names(M)))) stop("[build_mfro_panel] 병합 후 열이름 충돌: ",
    paste(grep("\.(x|y)$",names(M),value=TRUE),collapse=","))
  M<-merge(M,mret[ym==ymi,.(Ticker,fwd_ret,fwd_ym)],by="Ticker",all.x=TRUE)
  M[,`:=`(ym=ymi,rebal=sd)]
  rows[[i]]<-M
  if(i%%24==0) pg("  %d/%d %s (n=%d)\n",i,length(rebal),ymi,nrow(M))
}
P<-rbindlist(rows,fill=TRUE)
miss<-setdiff(names(FAC),names(P)); if(length(miss)) pg("★결측 팩터 열: %s\n",paste(miss,collapse=","))
pg("패널 행=%d · 월=%d · 종목=%d\n",nrow(P),uniqueN(P$ym),uniqueN(P$Ticker))
pg("월당 종목수 중앙=%d (범위 %d~%d)\n",as.integer(median(P[,.N,by=ym]$N)),min(P[,.N,by=ym]$N),max(P[,.N,by=ym]$N))
pg("fwd_ret 결측 비율 %.3f%% (마지막 월은 정상 결측)\n",100*mean(is.na(P$fwd_ret)))
write_parquet(P,"outputs/ramp/mfro_panel.parquet")
pg("저장: outputs/ramp/mfro_panel.parquet\n")
cat("PANEL_DONE\n")
