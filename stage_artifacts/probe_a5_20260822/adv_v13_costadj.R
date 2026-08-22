QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R"); library(data.table)
S<-fread("stage_artifacts/probe_a5_20260822/adv_intraindex_turnover_full.csv")
AX<-c("Market",colnames(S12)); dr<-sapply(AX,function(a) S[idx==a]$ann*0.0015)   # 연 비용률
cat("지수내부 연비용(%/yr):\n"); print(round(dr*100,3))
for(scale in c(1,0.5)){
 RET2<-RET; for(j in seq_along(AX)) RET2[,j]<-RET[,j]-scale*dr[j]/12
 ## 재계산: 신호도 비용반영 지수로
 cm<-apply(1+RET2,2,cumprod); S2<-matrix(NA_real_,NM,length(AX)-1)
 for(m in 12:NM){ lo<-m-11L; base<-if(lo==1L) rep(1,NAX) else cm[lo-1L,]
   g<-cm[m,]/base; S2[m,]<-g[-1]/g[1]-1 }
 MK2<-RET2[,1]
 eng2<-function(dec,bps=15){ pr<-gr<-tov<-rep(NA_real_,NM); wprev<-rep(1/NAX,NAX); wcur<-NULL
   for(m in 13:NM){ if(is.null(wcur)||dec[m]) wcur<-tgt_w(S2[m-1L,]) else wcur<-wprev
     dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; gr[m]<-sum(wcur*RET2[m,]); pr[m]<-gr[m]-(bps/1e4)*dlt
     wd<-wcur*(1+RET2[m,]); wprev<-wd/sum(wd) }
   list(pr=pr,gross=gr,tov=tov) }
 cat(sprintf("\n[내부비용 %d%% 반영]\n",round(scale*100)))
 for(nm in c("C1","A5_p0","A5_p1","A5_p2")){ f<-if(nm=="C1")1 else 3; p<-switch(nm,C1=0,A5_p0=0,A5_p1=1,A5_p2=2)
   r<-eng2(dec_freq(f,p)); k<-which(is.finite(r$pr)); a<-r$pr[k]-MK2[k]
   cat(sprintf("  %-6s pt=%.4f  active=%.4f%%/yr  (원판 pt=%.4f)\n",nm,nwt(a),mean(a)*12*100,
     MET(engine(dec_freq(f,p),bps=15))$pt)) }
 ## 앙상블
 PR<-matrix(NA_real_,3,NM); for(p in 0:2) PR[p+1,]<-eng2(dec_freq(3,p))$pr
 ok<-apply(PR,2,function(v)all(is.finite(v))); pe<-colMeans(PR[,ok,drop=F])
 cat(sprintf("  A5E    pt=%.4f  active=%.4f%%/yr\n",nwt(pe-MK2[ok]),mean(pe-MK2[ok])*12*100))
}
