# Diagnose (1) beta=0.735 and (2) magnitude gap 0.032 vs 0.122
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
setDTthreads(1); suppressWarnings(arrow::set_io_thread_count(1))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
dd   <- file.path(root,"stage_artifacts/pg2_defense_drawdown")
master <- fread(file.path(root,"stage_artifacts/pg2_defense_survey/defense_survey_master.csv"), encoding="UTF-8")
cand   <- fread(file.path(root,"stage_artifacts/pg2_defense_survey/step1_defense_candidates.csv"), encoding="UTF-8")
dir_map <- setNames(master$direction, master$code)
pf <- file.path(root,".cache/discovery/explore_panel.parquet")
sch<- names(read_parquet(pf, as_data_frame=FALSE)$schema)
use_codes <- intersect(cand$code, sch)
dt <- as.data.table(read_parquet(pf, col_select=c("ym","Ticker","fwd_ret_1m",use_codes)))
dt[, ym:=as.character(ym)]
mkt<- fread(file.path(dd,"market_fwd.csv")); mkt[,ym:=as.character(ym)]
epi<- fread(file.path(dd,"episodes.csv"))

ymseq <- function(a,b){ai<-as.integer(substr(a,1,4))*12+as.integer(substr(a,6,7));bi<-as.integer(substr(b,1,4))*12+as.integer(substr(b,6,7))
  sapply(ai:bi,function(x){y<-(x-1)%/%12;m<-(x-1)%%12+1;sprintf("%04d-%02d",y,m)})}
ep_months <- lapply(seq_len(nrow(epi)),function(i) ymseq(epi$peak_ym[i],epi$trough_ym[i])[-1])
names(ep_months)<-epi$name

# ---- Diagnose beta: is fwd_ret_1m already an EW of the SAME universe as market_fwd? ----
# market_fwd may be cap-weighted KOSPI200 (benchmark.parquet) while panel EW is small-cap tilted.
ewall <- dt[!is.na(fwd_ret_1m), .(ew=mean(fwd_ret_1m), med=median(fwd_ret_1m), n=.N), by=ym]
chk <- merge(ewall, mkt[,.(ym,market_fwd)], by="ym")
cat("cor(ew_all, market_fwd) =", round(cor(chk$ew,chk$market_fwd),3),
    " beta =", round(coef(lm(ew~market_fwd,chk))[2],3), "\n")
cat("mean ew_all =", round(mean(chk$ew),4), " mean market_fwd =", round(mean(chk$market_fwd),4), "\n")
cat("sd ew_all =", round(sd(chk$ew),4), " sd market_fwd =", round(sd(chk$market_fwd),4), "\n")
# => if sd(market) > sd(ew), beta<1 is just cap-weighted benchmark being more volatile (small-cap EW damped). Not an alignment bug.

build_active <- function(code, topn=25){
  d<-dt[!is.na(get(code))&!is.na(fwd_ret_1m),.(ym,z=get(code),r=fwd_ret_1m)]
  sgn<-if(identical(dir_map[[code]],"lower_better"))-1 else 1; d[,z:=z*sgn]
  d<-d[order(ym,-z)]; port<-d[,.(port_ret=mean(head(r,topn))),by=ym]
  merge(port,mkt[,.(ym,market_fwd)],by="ym")[,active:=port_ret-market_fwd][]
}

# ---- Magnitude: compare 3 aggregations for D48 ----
a <- build_active("D48_VaR_5pct",25); setkey(a,ym)
comp <- rbindlist(lapply(names(ep_months),function(e){
  ms<-ep_months[[e]]; sub<-a[ym%in%ms]
  mean_monthly <- mean(sub$active)
  # cumulative: compound port and market separately over episode, then diff
  cum_port <- prod(1+sub$port_ret)-1
  cum_mkt  <- prod(1+sub$market_fwd)-1
  cum_active <- cum_port - cum_mkt
  data.table(episode=e, n=nrow(sub), mean_monthly=mean_monthly, cum_active=cum_active)
}))
cat("\n=== D48 aggregation compare (their reported epact by episode) ===\n")
print(comp)
cat("median mean_monthly =", round(median(comp$mean_monthly),4),
    " median cum_active =", round(median(comp$cum_active),4), "\n")
# their reported epact_GFC_2008_2009-01 for D48 = 0.0986, epact_Euro_2011=0.1664, median=0.1222

cat("\nDONE\n")
