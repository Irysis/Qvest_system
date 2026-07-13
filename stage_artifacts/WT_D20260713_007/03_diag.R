# R23 Step 03 — diagnostics on the significance / clustering tension + event-type decomposition + backdating audit
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
suppressMessages({library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); set.seed(42)
OUT <- "stage_artifacts/WT_D20260713_007"
S <- readRDS(file.path(OUT,"target.rds"))
Fh <- copy(S$Fhard); Fh[, sc:=sub("^A","",Ticker)]

wd <- Fh[pred==1]
wde <- wd[E==1]
cat("=== worst-decile event concentration ===\n")
cat("worst-decile obs:", nrow(wd), " events:", nrow(wde), "\n")
cat("distinct tickers carrying worst-decile events:", uniqueN(wde$Ticker), "\n")
cat("events per ticker (top):\n"); print(wde[, .N, by=Ticker][order(-N)][1:min(12,.N)])
cat("worst-decile obs distinct tickers:", uniqueN(wd$Ticker), "\n")

# which severe event TYPE do the 47 worst-decile hits belong to? attach type via forward window
ym_add <- function(ym,k){ y<-ym%/%100; m<-ym%%100; t<-(y*12+(m-1))+k; (t%/%12)*100+(t%%12)+1 }
sev <- S$sev_hard
wd[, lo:=ym_add(ym,1)]; wd[, hi:=ym_add(ym,12)]
sk <- unique(sev[, .(sc, ev_ym, type)]); setkey(sk, sc)
jj <- sk[wd, on="sc", allow.cartesian=TRUE, nomatch=NULL]
hitwd <- jj[ev_ym>=lo & ev_ym<=hi]
cat("\n=== worst-decile forward-hits by severe type (a decision-month can hit multiple) ===\n")
print(unique(hitwd[, .(sc,ym,type)])[, .N, by=type][order(-N)])

# per-type lift: build single-type targets and lift in worst decile
lift_by_type <- function(tp){
  s1 <- sev[type==tp]
  fp <- copy(S$Fhard); fp[, sc:=sub("^A","",Ticker)]
  fp[, lo:=ym_add(ym,1)]; fp[, hi:=ym_add(ym,12)]
  es <- unique(s1[, .(sc,ev_ym)]); setkey(es,sc)
  j <- es[fp, on="sc", allow.cartesian=TRUE, nomatch=NULL]
  h <- j[ev_ym>=lo & ev_ym<=hi, .(E1=1L), by=.(sc,ym)]
  fp <- merge(fp, h, by=c("sc","ym"), all.x=TRUE); fp[is.na(E1),E1:=0L]
  base<-mean(fp$E1); wl<-fp[pred==1,mean(E1)]/base
  c(base=base, lift=wl, wd_ev=fp[pred==1,sum(E1)])
}
cat("\n=== per-type worst-decile lift (severity target components) ===\n")
for(tp in c("Delisting","AdminStock","UnfaithfulDisc")){
  r<-lift_by_type(tp); cat(sprintf("[%s] base=%.5f lift=%.2f worst-decile_events=%d\n", tp, r["base"], r["lift"], r["wd_ev"])) }

# permutation / placebo: shuffle pred label within month, recompute controlled OR 500x -> where does 3.43 sit
cat("\n=== placebo: month-permuted pred, controlled OR null distribution (500 reps) ===\n")
fp <- S$Fhard[!is.na(pred)&is.finite(log_size)]
fp[is.na(K200),K200:=0]; fp[is.na(KQ150),KQ150:=0]; fp[is.na(liq_z),liq_z:=0]; fp[is.na(size_z),size_z:=0]
obs_or <- 3.431
perm_or <- numeric(500)
for(r in 1:500){
  fp[, predP := sample(pred), by=ym]
  m <- tryCatch(glm(E~predP+size_z+liq_z+K200+KQ150,data=fp,family=binomial), error=function(e) NULL)
  perm_or[r] <- if(is.null(m)) NA else exp(coef(m)["predP"])
}
perm_or <- perm_or[is.finite(perm_or)]
cat("placebo OR: median=", round(median(perm_or),3), " q95=", round(quantile(perm_or,.95),3),
    " q99=", round(quantile(perm_or,.99),3), " | p(placebo>=obs 3.43)=", round(mean(perm_or>=obs_or),4), "\n")

# leave-one-ticker-out on controlled OR: how many tickers, if dropped, kill significance (p>0.05)?
cat("\n=== leave-one-ticker-out robustness of controlled OR p<0.05 ===\n")
evtk <- unique(fp[pred==1 & E==1, Ticker])
np <- 0; killed <- c()
for(tk in evtk){
  sub <- fp[Ticker!=tk]
  m <- glm(E~pred+size_z+liq_z+K200+KQ150,data=sub,family=binomial)
  cl <- tryCatch(coeftest(m,vcov=vcovCL(m,cluster=sub$Ticker)), error=function(e) NULL)
  if(is.null(cl)) next
  p <- cl["pred",4]; if(p>=0.05){ np<-np+1; killed<-c(killed,tk) }
}
cat("event-tickers whose removal pushes p>=0.05:", np, "/", length(evtk), "\n")
if(np>0) cat("   killers:", paste(killed,collapse=","), "\n")
cat("\n[03] DONE\n")
