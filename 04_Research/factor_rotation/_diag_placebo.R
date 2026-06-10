suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts) })
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||!is.finite(a)) b else a
PROJ <- "G:/Quant_Module_Moltbot"
s  <- readRDS(file.path(PROJ, "04_Research/strategies/STR_valearn_70_top25/sim_result.rds"))
d  <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]; setorder(d, Date)
bm <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1]))
d <- merge(d, bm, by="Date", all.x=TRUE)
RG <- as.data.table(read_parquet(file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")))[!is.na(Category), .(Date=as.Date(Date), Category)]; setorder(RG, Date)
q <- data.table(Date=d$Date); res <- RG[q, on=.(Date), roll=TRUE]; d[, cat_me := res$Category]
d[, reg := shift(cat_me, 1L)]; d[is.na(reg), reg:="NEUTRAL"]
nM<-nrow(d); k<-floor(nM*0.65)  # essence_score uses 65/35 on active for oos_retention
srm<-function(x){x<-x[is.finite(x)];if(length(x)<2||sd(x)==0)return(NA);mean(x)/sd(x)*sqrt(12)}
oos_ret_active <- function(net){ a <- net - d$bm; a<-a[is.finite(a)]; n<-length(a); kk<-floor(n*0.65)
  ii<-srm(a[1:kk]); oo<-srm(a[(kk+1):n]); if(is.finite(ii)&&ii>0.05) oo/ii else NA_real_ }
apply_ov <- function(label, e_d){ prev<-1; rn<-numeric(nM)
  for(i in 1:nM){ e<-if(d$reg[i]==label) e_d else 1; r<-e*d$r[i]; if(abs(e-prev)>1e-9) r<-r-abs(e-prev)*(15/1e4); prev<-e; rn[i]<-r }; rn }
cat("placebo: de-risk EACH regime at e=0.0 -> OOS_retention(active 65/35) + full MDD:\n")
mddm<-function(x){n<-cumprod(1+x);as.numeric(1-min(n/cummax(n)))}
base<-d$r
cat(sprintf("  baseline           oos_ret=%.3f  MDD=%.3f\n", oos_ret_active(base), mddm(base)))
for(lab in c("RISK_ON","CAUTION","NEUTRAL","CRISIS","RISK_OFF")){
  net<-apply_ov(lab,0.0); cat(sprintf("  derisk %-9s e0.0  oos_ret=%.3f  MDD=%.3f  netSR=%.3f\n",
    lab, oos_ret_active(net)%||%NA, mddm(net), srm(net))) }
# count: in how many of the 5 single-regime de-risks does CAUTION rank best on oos_ret?
res2 <- sapply(c("RISK_ON","CAUTION","NEUTRAL","CRISIS","RISK_OFF"), function(lab){ oos_ret_active(apply_ov(lab,0.0)) })
cat("\nranking by oos_ret (higher=better):\n"); print(sort(res2, decreasing=TRUE, na.last=TRUE))
