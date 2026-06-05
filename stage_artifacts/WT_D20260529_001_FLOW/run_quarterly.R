# Quarterly rebalance (every 3rd month) — directly cuts turnover ~3x to hit mandate<=6
suppressMessages({library(data.table); library(arrow); library(lubridate)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
COST_BPS<-15
d <- readRDS(file.path(OUT,"diag_lowturn.rds"))
panel <- copy(d$panel)
setorder(panel, Date, -alpha_sm)
panel[, rk := frank(-alpha_sm, ties.method="first"), by=Date]
dates <- sort(unique(panel$Date))

# rebal months: every 3rd (Mar/Jun/Sep/Dec style — use index mod 3)
run_q <- function(ENTRY, KEEP, N=20L, rebal_every=3L){
  held<-character(0); hl<-vector("list",length(dates))
  for(i in seq_along(dates)){
    dd<-panel[Date==dates[i]]; rkmap<-setNames(dd$rk,dd$Ticker)
    is_rebal <- ((i-1) %% rebal_every)==0
    if(is_rebal || length(held)==0){
      keep<-intersect(held,dd$Ticker); keep<-keep[rkmap[keep]<=KEEP]
      cand<-dd$Ticker[dd$rk<=ENTRY]; newp<-union(keep,cand)
      if(length(newp)>N) newp<-newp[order(rkmap[newp])][1:N]
      else if(length(newp)<N){extra<-setdiff(dd$Ticker,newp);extra<-extra[order(rkmap[extra])];newp<-c(newp,head(extra,N-length(newp)))}
    } else { newp <- intersect(held, dd$Ticker) }  # hold (drop delisted only)
    hl[[i]]<-newp; held<-newp
  }
  # returns each month from current holdings
  port<-rbindlist(lapply(seq_along(dates),function(i){tk<-hl[[i]];dd<-panel[Date==dates[i]&Ticker%in%tk];data.table(Date=dates[i],pret=if(length(tk)) mean(dd$exret_fwd_1m,na.rm=TRUE) else NA)}))
  port<-port[!is.na(pret)]
  # turnover only at rebal months
  to_m<-sapply(2:length(dates),function(i){if(((i-1)%%rebal_every)==0) length(setdiff(hl[[i]],hl[[i-1]]))/max(1,length(hl[[i]])) else 0})
  toa<-sum(to_m)/(length(dates)/12)*2  # total one-way frac/yr *2 sides
  cost_total <- sum(to_m)*2*(COST_BPS/1e4); cost_m<-cost_total/nrow(port)
  port[,pn:=pret-cost_m]; pm<-mean(port$pn);ps<-sd(port$pn);np<-nrow(port)
  pat<-pm/(ps/sqrt(np)); sr<-pm/ps*sqrt(12)
  nwpa<-{x<-port$pn-pm;L<-3;g0<-mean(x^2);gj<-sapply(1:L,function(j)mean(x[-(1:j)]*x[-((np-j+1):np)]));w<-1-(1:L)/(L+1);pm/sqrt((g0+2*sum(w*gj))/np)}
  sk<-{x<-port$pn;m<-mean(x);s<-sd(x);mean((x-m)^3)/s^3};ku<-{x<-port$pn;m<-mean(x);s<-sd(x);mean((x-m)^4)/s^4}
  emc<-0.5772156649;nt<-15;z_e<-(1-emc)*qnorm(1-1/nt)+emc*qnorm(1-1/(nt*exp(1)));SRm<-pm/ps;SR0<-z_e/sqrt(np)
  dsr<-pnorm((SRm-SR0)*sqrt(np-1)/sqrt(1-sk*SRm+(ku-1)/4*SRm^2))
  list(tab=data.table(ENTRY,KEEP,turnover=round(toa,2),ann_net=round(((1+pm)^12-1)*100,2),
    port_t=round(pat,2),nw_t=round(nwpa,2),sr=round(sr,3),dsr=round(dsr,3)), port=port, hl=hl, pm=pm,ps=ps)
}
grid <- CJ(ENTRY=c(8L,12L), KEEP=c(30L,40L,50L))
res <- rbindlist(lapply(seq_len(nrow(grid)), function(i) run_q(grid$ENTRY[i],grid$KEEP[i])$tab))
setorder(res, turnover)
cat("=== QUARTERLY rebalance sweep ===\n"); print(res)
cat("\n--- turnover<=6 ---\n"); print(res[turnover<=6])
# save best feasible (turnover<=6, max port_t)
best <- run_q(12L, 40L)
saveRDS(list(res=res, best_tab=best$tab, port=best$port, hl=best$hl), file.path(OUT,"diag_quarterly.rds"))
cat("\nBest (E12 K40):\n"); print(best$tab)
