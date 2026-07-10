# H-b v2: flags for ALL tickers (fix KQ150 undercount), proper active series + dual-basis
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT-D20260710_005")

cat("[1] RAWDATA flags for ALL tickers (month-end)...\n"); flush.console()
raw <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"),
  col_select=c("Date","Ticker","UnfaithfulDisc","AdminStock","TradingHalt","Size","K200","KQ150")))
raw[, Date := as.IDate(as.character(Date))]
raw[, ym := as.integer(format(Date,"%Y%m"))]
raw <- raw[ym>=200312]
setkey(raw, Ticker, ym, Date)
me <- raw[raw[, .I[.N], by=.(Ticker,ym)]$V1]
tofl <- function(x){ x[is.na(x)] <- 0; as.integer(x>0) }
me[, u:=tofl(UnfaithfulDisc)][, a:=tofl(AdminStock)][, h:=tofl(TradingHalt)]
me[, anybad := pmax(u,a,h)]
me[, inuniv := as.integer((K200 %in% 1)|(KQ150 %in% 1))]
setorder(me, Ticker, ym)
me[, t12_bad := as.integer(frollapply(anybad,12,function(x) as.integer(any(x>0)),align="right",fill=0)), by=Ticker]

cat("[2] score_eff book + benchmark...\n"); flush.console()
seff <- as.data.table(read_parquet(file.path(OUT,"..","WT_D20260425_010/alpha_scores.parquet"),
  col_select=c("Date","Ticker","score_eff","Ret_1m")))
seff[, ym := as.integer(format(as.IDate(as.character(Date)),"%Y%m"))]
seff <- seff[is.finite(score_eff)&is.finite(Ret_1m)]
M <- merge(seff, me[, .(Ticker,ym,anybad,t12_bad,u,a,h)], by=c("Ticker","ym"), all.x=TRUE)
for(c in c("anybad","t12_bad","u","a","h")) M[is.na(get(c)),(c):=0L]
cat("book-candidate rows w/ current-flag:", sum(M$anybad), " t12:", sum(M$t12_bad),
    " unfaith-specific:", sum(M$u), "\n")
# how many top-25 book holdings are currently flagged?
M[, rk := frank(-score_eff, ties.method="first"), by=ym]
top <- M[rk<=25]
cat("top-25 holdings currently flagged (anybad): ", sum(top$anybad), " of ", nrow(top),
    " (", round(100*mean(top$anybad),3), "%)\n", sep="")
cat("top-25 holdings t12-flagged: ", sum(top$t12_bad), " (", round(100*mean(top$t12_bad),3), "%)\n", sep="")
cat("top-25 holdings unfaith-specific: ", sum(top$u), "\n", sep="")

# benchmark monthly from score_eff panel context: use BM proper -> compound daily BM_Ret per month
bench <- as.data.table(read_parquet(file.path(ROOT,".cache/RAWDATA.parquet"), col_select=c("Date","BM_Ret")))
bench[, ym := as.integer(format(as.IDate(as.character(Date)),"%Y%m"))]
bm <- unique(bench[, .(BM_Ret_d=BM_Ret), by=.(ym)])  # placeholder; compute compound properly:
bm <- bench[, .(BM_m = prod(1+BM_Ret, na.rm=TRUE)-1), by=ym]

pick <- function(dt, excl=NULL){
  dt[, {
    d <- .SD; if(!is.null(excl)) d <- d[get(excl)==0]
    setorder(d,-score_eff); n<-min(25,nrow(d)); list(port=mean(d$Ret_1m[seq_len(n)]))
  }, by=ym, .SDcols=names(dt)]
}
base <- pick(M); exA <- pick(M,"anybad"); exU <- pick(M,"u"); exT <- pick(M,"t12_bad")
cmp <- Reduce(function(x,y) merge(x,y,by="ym"),
  list(base[,.(ym,base=port)], exA[,.(ym,exA=port)], exU[,.(ym,exU=port)], exT[,.(ym,exT=port)]))
cmp <- merge(cmp, bm, by="ym")
nwt <- function(x){x<-x[is.finite(x)];n<-length(x);if(n<12)return(NA);m<-mean(x)
  ac<-acf(x,lag.max=3,plot=FALSE,demean=TRUE)$acf[-1];v<-var(x);s<-v*(1+2*sum((1-(1:3)/n)*ac));m/sqrt(s/n)}
# book-marginal on ACTIVE series (port - bench)
for(v in c("base","exA","exU","exT")) cmp[[paste0("act_",v)]] <- cmp[[v]] - cmp$BM_m
cat("\n=== book-marginal (paired delta of ACTIVE, exclusion - base) ===\n")
for(v in c("exA","exU","exT")){
  d <- cmp[[paste0("act_",v)]] - cmp$act_base
  cat(sprintf("  %s: changed=%d/%d mean_delta=%.5f NWt=%.2f\n", v,
    sum(abs(d)>1e-12), length(d), mean(d), nwt(d)))
}
cat(sprintf("\nbase active mean/mo=%.5f NWt=%.2f (n=%d)\n", mean(cmp$act_base), nwt(cmp$act_base), nrow(cmp)))
saveRDS(list(M=M[,.(Ticker,ym,anybad,t12_bad,u)], cmp=cmp, top_flag_rate=mean(top$anybad),
             top_t12_rate=mean(top$t12_bad)), file.path(OUT,"hb_result_v2.rds"))
cat("DONE\n")
