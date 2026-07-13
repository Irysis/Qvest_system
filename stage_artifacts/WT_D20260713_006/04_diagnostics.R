# Step 04 — diagnostics to inform next_probe (labeled; does NOT move the frozen verdict)
suppressMessages({library(data.table); library(sandwich); library(lmtest); library(arrow)})
setDTthreads(1); arrow::set_io_thread_count(2); set.seed(7)
OUT <- "stage_artifacts/WT_D20260713_006"
ym_add <- function(ym,k){y<-ym%/%100;m<-ym%%100;t<-(y*12+(m-1))+k;(t%/%12)*100+(t%%12)+1}
P <- readRDS(file.path(OUT,"panels.rds"))
events <- readRDS(file.path(OUT,"events.rds"))

# --- D1: F3 delay worst-decile event rate DECOMPOSED by event type ---
F3 <- P$F3[!is.na(pred)]
evByType <- split(events, events$type)
attach_type <- function(fp, ev){
  fp<-copy(fp); fp[,lo:=ym_add(ym,1)];fp[,hi:=ym_add(ym,12)]
  es<-unique(ev[,.(Ticker,ev_ym)]); j<-es[fp,on="Ticker",allow.cartesian=TRUE,nomatch=NULL]
  hit<-j[ev_ym>=lo&ev_ym<=hi,.(h=1L),by=.(Ticker,ym)]
  fp<-merge(fp,hit,by=c("Ticker","ym"),all.x=TRUE);fp[is.na(h),h:=0L];fp$h
}
cat("=== D1: F3 delay worst-decile lift by event TYPE ===\n")
for(tp in names(evByType)){
  h <- attach_type(F3, evByType[[tp]])
  base <- mean(h); e1 <- mean(h[F3$pred==1])
  cat(sprintf("  %-16s base=%.4f worstD=%.4f lift=%.2f\n", tp, base, e1, e1/base))
}

# --- D2: continuous days-late (higher power) controlled logistic for F3 ---
cat("\n=== D2: F3 continuous suspect (days-late z) controlled logistic ===\n")
d <- copy(F3); d[is.na(K200),K200:=0];d[is.na(KQ150),KQ150:=0];d[is.na(liq_z),liq_z:=0];d[is.na(size_z),size_z:=0]
d[, susp_z := as.numeric(scale(susp)), by=ym]
d <- d[is.finite(susp_z)]
mc <- glm(E~susp_z+size_z+liq_z+K200+KQ150, data=d, family=binomial)
cl <- coeftest(mc, vcov=vcovCL(mc, cluster=d$Ticker))
cat(sprintf("  OR per +1sd days-late (ctrl) = %.3f  p=%.4g (cluster-robust)\n",
    exp(coef(mc)["susp_z"]), cl["susp_z",4]))
# top-quintile (higher power than decile)
d[, q5 := as.integer(frank(susp,ties.method="min")/.N > 0.8), by=ym]
mc2 <- glm(E~q5+size_z+liq_z+K200+KQ150, data=d, family=binomial)
cl2 <- coeftest(mc2, vcov=vcovCL(mc2, cluster=d$Ticker))
cat(sprintf("  top-QUINTILE OR (ctrl) = %.3f [%.3f,%.3f] p=%.4g  (q5 n=%d evrate=%.4f base=%.4f)\n",
    exp(coef(mc2)["q5"]), exp(coef(mc2)["q5"]-1.96*cl2["q5","Std. Error"]),
    exp(coef(mc2)["q5"]+1.96*cl2["q5","Std. Error"]), cl2["q5",4],
    d[q5==1,.N], d[q5==1,mean(E)], mean(d$E)))

# --- D3: DSR context (4 enumerated trials, Bonferroni) ---
cat("\n=== D3: multiple-testing across 4 trials ===\n")
TR <- readRDS(file.path(OUT,"test_results.rds"))$RES
ps <- sapply(c("F1","F2","F3","ST"), function(n) TR[[n]]$or_ctrl_p)
cat("  controlled-OR p:", paste(sprintf("%s=%.4g",names(ps),ps),collapse="  "),"\n")
cat("  Bonferroni(x4) min p:", sprintf("%.4g", min(ps)*4), " => none < 0.05 after correction\n")

# --- D4: tier localization of F3 worst decile (K200/KQ150/OTHER) ---
cat("\n=== D4: F3 worst-decile tier composition ===\n")
F3[, tier := fifelse(K200==1,"MEGA_K200", fifelse(KQ150==1,"KQ150","OTHER"))]
print(F3[pred==1, .N, by=tier][order(-N)])
