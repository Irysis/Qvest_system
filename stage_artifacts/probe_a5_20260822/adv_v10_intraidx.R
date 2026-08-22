## 지수 내부(종목 레벨) 리밸 회전율 = 백테스트에서 과금되지 않는 비용 — 표본 측정
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
FAC<-c(Value="V12_Composite_Value", Momentum="M09_Composite_Mom", Quality="Q08_Composite_Quality",
       LowVol="D03_RealVol", Size="S01_Size", Reversal="M11_ST_Reversal",
       Liquidity="L45_Composite_Liquidity", ForeignFlow="INV01_Foreign_NetBuy_20d")
rd<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))
rd[,Date:=as.Date(Date)]; rd<-rd[is.finite(Size)&Size>0]
rd[,inuniv:=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]; rd<-rd[inuniv==TRUE]
alld<-sort(unique(rd$Date)); ymv<-format(alld,"%Y-%m"); me<-alld[!duplicated(ymv,fromLast=TRUE)]
me<-me[me>=as.Date("2007-01-01") & me<=as.Date("2026-05-31")]
set.seed(11); anchors<-sort(sample(seq_along(me)[-length(me)], 14))
res<-list()
for(ai in anchors){ d1<-me[ai]; d2<-me[ai+1]
  u1<-rd[Date==d1,.(Ticker,Size)]; u2<-rd[Date==d2,.(Ticker,Size)]
  f1<-tryCatch(as.data.table(load_month_factors(d1,factor_names=unname(FAC))),error=function(e)NULL)
  f2<-tryCatch(as.data.table(load_month_factors(d2,factor_names=unname(FAC))),error=function(e)NULL)
  if(is.null(f1)||is.null(f2)) next
  m1<-merge(f1,u1,by="Ticker"); m2<-merge(f2,u2,by="Ticker")
  for(nm in names(FAC)){ s1<-m1[Factor_Name==FAC[nm]]; s2<-m2[Factor_Name==FAC[nm]]
    if(nrow(s1)<15||nrow(s2)<15) next
    a<-s1[Z_Score_Aligned>=quantile(s1$Z_Score_Aligned,2/3,na.rm=TRUE)]
    b<-s2[Z_Score_Aligned>=quantile(s2$Z_Score_Aligned,2/3,na.rm=TRUE)]
    wa<-a$Size/sum(a$Size); names(wa)<-a$Ticker; wb<-b$Size/sum(b$Size); names(wb)<-b$Ticker
    all_t<-union(names(wa),names(wb)); va<-ifelse(all_t %in% names(wa),wa[all_t],0); vb<-ifelse(all_t %in% names(wb),wb[all_t],0)
    va[is.na(va)]<-0; vb[is.na(vb)]<-0
    res[[length(res)+1]]<-data.table(d=d2,idx=nm,n1=nrow(a),n2=nrow(b),
      oneway=0.5*sum(abs(vb-va)), entry_w=sum(vb[!(all_t %in% names(wa))])) }
  ## Market 지수(전 유니버스 cap-w)
  wa<-u1$Size/sum(u1$Size); names(wa)<-u1$Ticker; wb<-u2$Size/sum(u2$Size); names(wb)<-u2$Ticker
  at<-union(names(wa),names(wb)); va<-ifelse(at %in% names(wa),wa[at],0); vb<-ifelse(at %in% names(wb),wb[at],0)
  va[is.na(va)]<-0; vb[is.na(vb)]<-0
  res[[length(res)+1]]<-data.table(d=d2,idx="Market",n1=nrow(u1),n2=nrow(u2),
    oneway=0.5*sum(abs(vb-va)), entry_w=sum(vb[!(at %in% names(wa))]))
}
R<-rbindlist(res)
S<-R[,.(n_obs=.N, mean_oneway_mo=mean(oneway), median=median(oneway), ann_oneway=mean(oneway)*12,
        drag_15bps_pct_yr=mean(oneway)*12*0.0015*100, mean_entry_w=mean(entry_w)),by=idx][order(-mean_oneway_mo)]
print(S,digits=4)
cat(sprintf("\n  팩터지수 평균(시장 제외): 월 one-way=%.4f -> 연 %.2f | 15bps drag=%.4f%%/yr\n",
  mean(S[idx!="Market"]$mean_oneway_mo), mean(S[idx!="Market"]$ann_oneway),
  mean(S[idx!="Market"]$drag_15bps_pct_yr)))
cat(sprintf("  시장지수 drag=%.4f%%/yr -> active 순드래그 ≈ %.4f%%/yr\n",
  S[idx=="Market"]$drag_15bps_pct_yr, mean(S[idx!="Market"]$drag_15bps_pct_yr)-S[idx=="Market"]$drag_15bps_pct_yr))
fwrite(R,"stage_artifacts/probe_a5_20260822/adv_intraindex_turnover.csv")
