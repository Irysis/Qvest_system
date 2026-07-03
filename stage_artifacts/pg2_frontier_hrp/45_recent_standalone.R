suppressPackageStartupMessages({library(data.table);library(sandwich);library(lmtest)})
OUT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"
nwt<-function(x,lag=3L){x<-as.numeric(x);x<-x[is.finite(x)];n<-length(x);if(n<10)return(NA);as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=lag,prewhite=FALSE))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
rfiles<-c("runs_cheap.rds","runs_heavytail.rds")
rf2<-list.files(OUT,pattern="^runs_regime_.*rds$",full.names=TRUE)
allruns<-list()
for(f in c(file.path(OUT,rfiles),rf2)) if(file.exists(f)) allruns<-c(allruns,readRDS(f))
res<-rbindlist(lapply(names(allruns),function(k){mg<-allruns[[k]];m21<-mg[realized_ym>="2021-01"]
  data.table(method=k,PORT_t_full=round(nwt(mg$active),3),PORT_t_2021=round(nwt(m21$active),3),
    IR_2021=round(IRf(m21$active),3),n21=nrow(m21))}))
fwrite(res,file.path(OUT,"recent_standalone.csv"))
print(res)
