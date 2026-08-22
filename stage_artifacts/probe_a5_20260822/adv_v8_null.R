QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("stage_artifacts/probe_a5_20260822/adv_v2_engine_lib.R")
library(data.table)
## 동료 스크립트와 동일 seed·동일 소비순서 재현
set.seed(20260822)
B<-400; nl<-numeric(B)
for(i in 1:B){ sc<-which(runif(NM)<1/3); d<-rep(FALSE,NM); d[sc[sc>=13]]<-TRUE; d[13]<-TRUE
  nl[i]<-MET(engine(d,bps=15))$pt }
cat(sprintf("[동일seed] null mean=%.4f sd=%.4f q05=%.3f q95=%.3f | A5 pct=%.3f C1 pct=%.3f\n",
  mean(nl),sd(nl),quantile(nl,.05),quantile(nl,.95),mean(nl<3.23180),mean(nl<2.77483)))
cat(sprintf("   격차 0.457 / sd = %.2f배 | A5-null평균 = %.3f (=%.2f sd)\n",
  0.45697/sd(nl),3.23180-mean(nl),(3.23180-mean(nl))/sd(nl)))
