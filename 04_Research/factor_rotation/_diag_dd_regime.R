suppressPackageStartupMessages({ library(data.table); library(arrow); library(xts) })
PROJ <- "G:/Quant_Module_Moltbot"
s  <- readRDS(file.path(PROJ, "04_Research/strategies/STR_valearn_70_top25/sim_result.rds"))
d  <- as.data.table(s$DAILY_NAV_DT)[, .(Date=as.Date(Date), r=Strategy_Ret)]; setorder(d, Date)
RG <- as.data.table(read_parquet(file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")))[!is.na(Category), .(Date=as.Date(Date), Category)]; setorder(RG, Date)
q <- data.table(Date=d$Date); res <- RG[q, on=.(Date), roll=TRUE]; d[, cat_me := res$Category]
d[, reg_cat := shift(cat_me, 1L)]; d[is.na(reg_cat), reg_cat:="NEUTRAL"]
# drawdown path
d[, nav := cumprod(1+r)]; d[, peak := cummax(nav)]; d[, dd := nav/peak - 1]
cat("worst 12 drawdown months (with the t-1 regime that was driving exposure):\n")
print(d[order(dd)][1:12, .(Date, r=round(r,3), dd=round(dd,3), reg_cat)])
cat("\nmonthly return by regime (FULL period) — where does valearn make/lose money:\n")
srm<-function(x){x<-x[is.finite(x)];if(length(x)<3||sd(x)==0)return(NA);mean(x)/sd(x)*sqrt(12)}
print(d[, .(n=.N, mean=round(mean(r),4), sd=round(sd(r),4), sharpe=round(srm(r),3),
            worst=round(min(r),3), best=round(max(r),3)), by=reg_cat][order(-mean)])
# OOS-only (last 40%) regime returns — the decay
nM<-nrow(d); oos<-d[(floor(nM*0.6)+1):nM]
cat("\nOOS (201712~) monthly return by regime — the OOS decay structure:\n")
print(oos[, .(n=.N, mean=round(mean(r),4), sharpe=round(srm(r),3), worst=round(min(r),3)), by=reg_cat][order(-mean)])
# active vs BM by regime (OOS)
bm <- data.table(Date=as.Date(index(s$bm_xts)), bm=as.numeric(s$bm_xts[,1]))
oos <- merge(oos, bm, by="Date", all.x=TRUE); oos[, act := r - bm]
cat("\nOOS ACTIVE (vs KOSPI200) by regime — is the alpha there at all in OOS:\n")
print(oos[, .(n=.N, act_mean=round(mean(act),4), act_sharpe=round(srm(act),3)), by=reg_cat][order(-act_mean)])
