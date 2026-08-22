## run_dfa_holdings_count_r25.R — R25: 채택팔의 실제 최종 편입 종목수 실측 (제약 max 25 대조)
suppressPackageStartupMessages({library(data.table);library(arrow)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
FAC<-c(Value="V12_Composite_Value", Issuance="V21_Composite_Equity_Issuance", Size="S01_Size",
       Momentum="M09_Composite_Mom", ResidMom="M08_Residual_Mom", Reversal="M11_ST_Reversal",
       Quality="Q08_Composite_Quality", GPA="Q01_GPA", EarnStab="Q07_Earnings_Stability",
       Growth="GR07_Composite_Growth", Investment="IN06_Investment_to_Assets",
       LowVol="D03_RealVol", LowBeta="D02_Beta", TailRisk="R05_Tail_Risk",
       Liquidity="L45_Composite_Liquidity", Accrual="AC18_Accrual_Quality",
       Consensus="C19_Composite_Earnings", SUE="C01_SUE", Crowding="CR07_Momentum_Crowding",
       ForeignFlow="INV01_Foreign_NetBuy_20d", SmartMoney="INV10_Smart_Money_Flow")
## 1) 채택팔 신호로 분기별 선택 팩터 (top-quintile k=5, 코호트 0 기준)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
setorder(mon,medate); NM<-nrow(mon); NF<-length(fac)
S<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM) S[m,fi]<-prod(1+mon[[fac[fi]]][(m-11):m])/prod(1+mon$Market[(m-11):m])-1
sel_months<-seq(13,NM,by=3)
.NS<-as.integer(Sys.getenv("R25_NSAMPLE","0"))
if(.NS>0) sel_months<-sel_months[round(seq(1,length(sel_months),length.out=.NS))]  # 표본 모드
## 2) rawdata 유니버스 (월말)
rd<-as.data.table(read_parquet(".cache/rawdata.parquet",col_select=c("Date","Ticker","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]; rd<-rd[is.finite(Size)&Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; rd<-rd[inuniv==TRUE]
res<-list()
for(m in sel_months){ d<-m-1; if(d<12) next
  s<-S[d,]; pos<-which(is.finite(s)&s>0); if(!length(pos)) next
  if(length(pos)>5) pos<-pos[order(s[pos],decreasing=TRUE)][1:5]
  sd_<-mon$medate[d]
  uni<-rd[Date==sd_,.(Ticker,Size)]; if(nrow(uni)<30) next
  f<-tryCatch(as.data.table(load_month_factors(sd_,factor_names=unname(FAC[fac[pos]]))),error=function(e)NULL)
  if(is.null(f)||nrow(f)==0) next
  fm<-merge(f,uni,by="Ticker")
  sets<-list(); wsum<-c()
  for(pi in seq_along(pos)){ nmf<-fac[pos[pi]]; sub<-fm[Factor_Name==FAC[nmf]]
    if(nrow(sub)<15) next
    thr<-quantile(sub$Z_Score_Aligned,0.6667,na.rm=TRUE); sel<-sub[Z_Score_Aligned>=thr]
    sets[[nmf]]<-data.table(fkey=nmf, Ticker=sel$Ticker, Size=sel$Size,
                            wfac=s[pos[pi]]/sum(s[pos])) }
  if(!length(sets)) next
  A<-rbindlist(sets)
  A[,w_in:=Size/sum(Size),by=fkey]             # 팩터지수 내 cap-weight (★팩터명으로 그룹 — wfac 값 그룹핑은 동값 병합 버그)
  stopifnot(abs(A[,sum(w_in),by=fkey]$V1-1)<1e-9)   # 각 팩터 내 비중합 1 확인
  A[,w:=wfac*w_in]
  agg<-A[,.(w=sum(w)),by=Ticker][order(-w)]
  agg[,w:=w/sum(w)]
  eff<-1/sum(agg$w^2)
  res[[length(res)+1]]<-data.table(ym=mon$ym[m], n_fac=length(sets),
    유니버스=nrow(uni), 팩터당평균=round(mean(sapply(sets,nrow)),1),
    최종종목수=nrow(agg), 실효종목수=round(eff,1),
    상위25비중=round(sum(head(agg$w,25)),3), 최대비중=round(max(agg$w),4))
}
T<-rbindlist(res)
cat("=== R25 채택팔(F1 top-quintile k=5)의 실제 편입 종목수 ===\n")
cat(sprintf("리밸 시점 %d개 측정 (%s ~ %s)\n\n",nrow(T),T$ym[1],T$ym[nrow(T)]))
print(T[seq(1,nrow(T),length.out=min(10,nrow(T)))])
cat(sprintf("\n[요약]\n  최종 편입 종목수: 중앙값 %.0f · 범위 [%d, %d]\n",
  median(T$최종종목수),min(T$최종종목수),max(T$최종종목수)))
cat(sprintf("  실효 종목수(1/HHI): 중앙값 %.1f · 범위 [%.1f, %.1f]\n",
  median(T$실효종목수),min(T$실효종목수),max(T$실효종목수)))
cat(sprintf("  상위 25종목이 담는 비중: 중앙값 %.1f%%\n",100*median(T$상위25비중)))
cat(sprintf("  단일종목 최대비중: 중앙값 %.2f%% · 최대 %.2f%% (제약 상한 20%%)\n",
  100*median(T$최대비중),100*max(T$최대비중)))
cat(sprintf("\n★제약 대조: 종목수 max 25 → 실측 중앙값 %.0f = 제약의 %.1f배\n",
  median(T$최종종목수), median(T$최종종목수)/25))
fwrite(T,"outputs/ramp/dfa_holdings_count_r25_20260822.csv")
cat("\nR25_DONE\n")
