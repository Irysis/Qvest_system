# =============================================================
# WT-D20260529_001 FLOW — Low-turnover variant (mandate turnover<=6/yr)
# Levers: (a) longer-horizon flow factors only (60d, persistence, concentration)
#         (b) signal smoothing (3m EMA of composite)
#         (c) buffer-zone hysteresis (keep_n=20, entry_n=12) to cut churn
# =============================================================
suppressMessages({library(data.table); library(arrow); library(lubridate)})
options(warn=1)
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
COST_BPS <- 15
d <- readRDS(file.path(OUT,"diag_v2.rds"))
panel <- copy(d$panel)
INV <- grep("^INV", names(panel), value=TRUE)

# (a) longer-horizon mechanism-diverse contrarian subset (lower turnover by construction)
pick_lt <- c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d",
             "INV09_Flow_Persistence","INV11_Foreign_Concentration",
             "INV07_Retail_Contrarian")
panel[, alpha_raw := -rowMeans(.SD,na.rm=TRUE), .SDcols=pick_lt]
panel[, alpha_raw := (alpha_raw-mean(alpha_raw,na.rm=TRUE))/sd(alpha_raw,na.rm=TRUE), by=Date]

# (b) 3-month EMA smoothing of each ticker's signal (PIT-safe: only past)
setorder(panel, Ticker, Date)
ema <- function(x, a=0.5){ out<-x; for(i in 2:length(x)) if(!is.na(x[i])&&!is.na(out[i-1])) out[i]<-a*x[i]+(1-a)*out[i-1]; out }
panel[, alpha_sm := { o<-alpha_raw; if(length(o)>1) ema(o, a=0.5) else o }, by=Ticker]
panel[, alpha_sm := (alpha_sm-mean(alpha_sm,na.rm=TRUE))/sd(alpha_sm,na.rm=TRUE), by=Date]
panel <- panel[!is.na(alpha_sm) & !is.na(exret_fwd_1m)]

# IC of smoothed alpha
ic <- panel[, .(ic=if(.N>=20) cor(alpha_sm,exret_fwd_1m,method="spearman") else NA, bad=bad[1]), by=Date][!is.na(ic)]
nm<-nrow(ic); mic<-mean(ic$ic); icir<-mic/sd(ic$ic); ht<-mic/(sd(ic$ic)/sqrt(nm))
nw<-{x<-ic$ic-mic;L<-3;g0<-mean(x^2);gj<-sapply(1:L,function(j)mean(x[-(1:j)]*x[-((nm-j+1):nm)]));w<-1-(1:L)/(L+1);mic/sqrt((g0+2*sum(w*gj))/nm)}
icb<-mean(ic[bad==TRUE]$ic); icn<-mean(ic[bad==FALSE]$ic)
cat(sprintf("LOW-TURN alpha: IC=%.4f ICIR=%.3f Harvey-t=%.2f NW-t=%.2f | crisis IC=%.4f normal=%.4f ratio=%.3f\n",
  mic,icir,ht,nw,icb,icn,icb/icn))
ic[, period:=fifelse(Date<as.Date("2015-01-01"),"P1",fifelse(Date<as.Date("2020-01-01"),"P2","P3"))]
sub<-ic[,.(ic=mean(ic),n=.N,pos=mean(ic>0)),by=period][order(period)]; print(sub)
subperiod_stability<-mean(sub$ic>0)

# (c) buffer-zone hysteresis portfolio: hold until rank drops below keep_n=25; enter from entry_n=12
setorder(panel, Date, -alpha_sm)
panel[, rk := frank(-alpha_sm, ties.method="first"), by=Date]
dates <- sort(unique(panel$Date))
ENTRY<-12L; KEEP<-25L; N<-20L
held <- character(0); hold_list <- vector("list",length(dates))
for(i in seq_along(dates)){
  dd <- panel[Date==dates[i]][order(rk)]
  rkmap <- setNames(dd$rk, dd$Ticker)
  # keep current holders still within KEEP
  keep <- intersect(held, dd$Ticker); keep <- keep[ rkmap[keep] <= KEEP ]
  # fill from top entry candidates not already held
  cand <- dd$Ticker[ dd$rk <= ENTRY ]
  newp <- union(keep, cand)
  if(length(newp) > N){ # trim to N by best rank
    newp <- newp[ order(rkmap[newp]) ][1:N]
  } else if(length(newp) < N){ # fill more from next best
    extra <- setdiff(dd$Ticker, newp); extra <- extra[order(rkmap[extra])]
    newp <- c(newp, head(extra, N-length(newp)))
  }
  hold_list[[i]] <- newp; held <- newp
}
# returns + turnover
port <- rbindlist(lapply(seq_along(dates), function(i){
  tk <- hold_list[[i]]
  dd <- panel[Date==dates[i] & Ticker %in% tk]
  data.table(Date=dates[i], pret=mean(dd$exret_fwd_1m,na.rm=TRUE))
}))
to_m <- sapply(2:length(dates), function(i){ a<-hold_list[[i-1]]; b<-hold_list[[i]]; length(setdiff(b,a))/length(b) })
turnover_annual <- mean(to_m)*2*12
cost_m <- mean(to_m)*2*(COST_BPS/1e4)
port[, pret_net := pret - cost_m]
pm<-mean(port$pret_net); ps<-sd(port$pret_net); npa<-nrow(port)
pat<-pm/(ps/sqrt(npa))
nwpa<-{x<-port$pret_net-pm;L<-3;g0<-mean(x^2);gj<-sapply(1:L,function(j)mean(x[-(1:j)]*x[-((npa-j+1):npa)]));w<-1-(1:L)/(L+1);pm/sqrt((g0+2*sum(w*gj))/npa)}
sr<-pm/ps*sqrt(12)
sk<-{x<-port$pret_net;m<-mean(x);s<-sd(x);mean((x-m)^3)/s^3}; ku<-{x<-port$pret_net;m<-mean(x);s<-sd(x);mean((x-m)^4)/s^4}
emc<-0.5772156649; n_trials<-15
z_e<-(1-emc)*qnorm(1-1/n_trials)+emc*qnorm(1-1/(n_trials*exp(1)))
SRm<-pm/ps; SR0<-z_e/sqrt(npa)
dsr<-pnorm((SRm-SR0)*sqrt(npa-1)/sqrt(1-sk*SRm+(ku-1)/4*SRm^2))
cat(sprintf("\n=== LOW-TURN PORTFOLIO (buffer keep=%d entry=%d) ===\nmonthly net excess=%.4f%% ann=%.2f%% port-alpha t=%.2f NW-t=%.2f net-SR=%.3f TURNOVER=%.2f/yr DSR=%.3f\n",
  KEEP,ENTRY,pm*100,((1+pm)^12-1)*100,pat,nwpa,sr,turnover_annual,dsr))

saveRDS(list(pick=pick_lt,mic=mic,icir=icir,ht=ht,nw=nw,icb=icb,icn=icn,ax001=icb/icn,
  sub=sub,subperiod_stability=subperiod_stability,turnover_annual=turnover_annual,
  pm=pm,pat=pat,nwpa=nwpa,sr=sr,dsr=dsr,npa=npa,panel=panel,
  cost_m=cost_m,sk=sk,ku=ku), file.path(OUT,"diag_lowturn.rds"))
cat("\n[diag_lowturn] saved.\n")
