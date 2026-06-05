# Buffer-zone sweep to hit turnover<=6/yr while preserving portfolio-alpha t>=3
suppressMessages({library(data.table); library(arrow); library(lubridate)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
COST_BPS<-15
d <- readRDS(file.path(OUT,"diag_lowturn.rds"))
panel <- copy(d$panel)   # has alpha_sm, exret_fwd_1m, rk per date
setorder(panel, Date, -alpha_sm)
panel[, rk := frank(-alpha_sm, ties.method="first"), by=Date]
dates <- sort(unique(panel$Date))

run_buffer <- function(ENTRY, KEEP, N=20L){
  held<-character(0); hl<-vector("list",length(dates))
  for(i in seq_along(dates)){
    dd<-panel[Date==dates[i]]; rkmap<-setNames(dd$rk,dd$Ticker)
    keep<-intersect(held,dd$Ticker); keep<-keep[rkmap[keep]<=KEEP]
    cand<-dd$Ticker[dd$rk<=ENTRY]; newp<-union(keep,cand)
    if(length(newp)>N) newp<-newp[order(rkmap[newp])][1:N]
    else if(length(newp)<N){extra<-setdiff(dd$Ticker,newp);extra<-extra[order(rkmap[extra])];newp<-c(newp,head(extra,N-length(newp)))}
    hl[[i]]<-newp; held<-newp
  }
  port<-rbindlist(lapply(seq_along(dates),function(i){tk<-hl[[i]];dd<-panel[Date==dates[i]&Ticker%in%tk];data.table(Date=dates[i],pret=mean(dd$exret_fwd_1m,na.rm=TRUE))}))
  to_m<-sapply(2:length(dates),function(i)length(setdiff(hl[[i]],hl[[i-1]]))/length(hl[[i]]))
  toa<-mean(to_m)*2*12; cost_m<-mean(to_m)*2*(COST_BPS/1e4)
  port[,pn:=pret-cost_m]; pm<-mean(port$pn);ps<-sd(port$pn);np<-nrow(port)
  pat<-pm/(ps/sqrt(np)); sr<-pm/ps*sqrt(12)
  nwpa<-{x<-port$pn-pm;L<-3;g0<-mean(x^2);gj<-sapply(1:L,function(j)mean(x[-(1:j)]*x[-((np-j+1):np)]));w<-1-(1:L)/(L+1);pm/sqrt((g0+2*sum(w*gj))/np)}
  data.table(ENTRY,KEEP,turnover=round(toa,2),ann_net=round(((1+pm)^12-1)*100,2),
             port_t=round(pat,2),nw_t=round(nwpa,2),sr=round(sr,3))
}
grid <- CJ(ENTRY=c(5L,8L,10L,12L), KEEP=c(30L,40L,50L,60L))
res <- rbindlist(lapply(seq_len(nrow(grid)), function(i) run_buffer(grid$ENTRY[i],grid$KEEP[i])))
setorder(res, turnover)
print(res)
cat("\n--- rows with turnover<=6 ---\n")
print(res[turnover<=6])
saveRDS(res, file.path(OUT,"buffer_sweep.rds"))
