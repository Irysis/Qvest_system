cat("=== STR_1550 S5: 9 Mutations ===\n")
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); set.seed(1550)
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path("/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow); library(dplyr)

res <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose=FALSE)

NEEDED <- c("C19_Composite_Earnings","C07_ESBR","D01_IdioVol","M25_Earnings_Mom_Streak")
ds <- open_dataset(file.path(CACHE_DIR,"factor_db"), format="parquet")
FDB_ALL <- ds |> filter(Factor_Name %in% NEEDED) |>
  select(Date,Ticker,Factor_Name,Z_Score,Coverage) |> collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
source(file.path(INFRA_DIR,"factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)

LIQ_THRESHOLD <- 2e8
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date,"%Y-%m")]
monthly_dates <- sort(RAWDATA[,.(SD=max(Date)),by=YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L,length(all_dates))]]
RAWDATA[, TradingValue := Close*Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue,n=20L,align="right"),n=1L,type="lag"), by=Ticker]
fdb_dates <- sort(unique(FDB_ALL$Date))

sim_parent <- readRDS(file.path(SCRIPT_DIR,"sim_result.rds"))

build_factors <- function(scoring_fn, label) {
  fl <- vector("list", length(monthly_dates)); nd <- 0L
  for(i in seq_along(monthly_dates)) {
    sig_d <- as.Date(monthly_dates[i])
    vf <- fdb_dates[fdb_dates <= sig_d]
    if(length(vf)==0) next
    fdt <- FDB_ALL[Date==max(vf) & Coverage==TRUE]
    if(nrow(fdt)==0) next
    fw <- dcast(fdt, Ticker~Factor_Name, value.var="Z_Score_Aligned")
    liq <- RAWDATA[Date==sig_d, .(Ticker,AvgTV20)]
    fw <- merge(fw, liq, by="Ticker")
    fw <- fw[!is.na(AvgTV20) & AvgTV20>=LIQ_THRESHOLD]
    if(nrow(fw)<20) next
    r <- tryCatch(scoring_fn(copy(fw), sig_d), error=function(e) NULL)
    if(!is.null(r) && nrow(r)>0) { fl[[i]] <- r; nd <- nd+1L }
  }
  F <- rbindlist(fl[!sapply(fl,is.null)]); setorder(F,Date,-Score)
  cat(sprintf("  [%s] %d dates\n",label,nd)); F
}

run_bt <- function(FACTORS, name, dir_name, nh=30L) {
  RD <- copy(RAWDATA_ORIG)
  sim <- tryCatch(run_monthly_simulation(RAWDATA=RD, BM_DT=BM_DT, FACTORS=FACTORS, n_holdings=nh,
    weight_method="equal", commission=0.0015, buffer_zone=list(keep_n=50L,entry_n=25L)),
    error=function(e){cat("ERR:",e$message,"\n");NULL})
  if(is.null(sim)) return(NULL)
  od <- file.path(SCRIPT_DIR,dir_name); dir.create(od,showWarnings=F,recursive=T)
  p <- summarise_perf(sim$strategy_xts,name)
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",name,p$Sharpe,p$CAGR,p$MDD))
  generate_charts(sim,output_dir=od,strategy_name=name)
  fwrite(rbind(p,summarise_perf(sim$bm_xts,"BM")),file.path(od,"performance.csv"))
  saveRDS(sim,file.path(od,"sim_result.rds"))
  source(file.path(INFRA_DIR,"hurdle_gate.R"))
  h <- run_hurdle_gate(sim_result=sim,strategy_name=name,output_dir=od)
  jsonlite::write_json(h,file.path(od,"hurdle_result.json"),auto_unbox=T,pretty=T)
  list(perf=p, hurdle=h, sim=sim)
}

run_overlay <- function(exp_vec, name, dir_name) {
  rr <- as.numeric(sim_parent$strategy_xts); rr[is.na(rr)] <- 0
  rd <- as.Date(index(sim_parent$strategy_xts))
  fr <- rr * exp_vec
  cx <- xts(fr,order.by=rd); names(cx) <- "Strategy"
  sim2 <- sim_parent; sim2$strategy_xts <- cx
  od <- file.path(SCRIPT_DIR,dir_name); dir.create(od,showWarnings=F,recursive=T)
  p <- summarise_perf(cx,name)
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",name,p$Sharpe,p$CAGR,p$MDD))
  generate_charts(sim2,output_dir=od,strategy_name=name)
  fwrite(rbind(p,summarise_perf(sim2$bm_xts,"BM")),file.path(od,"performance.csv"))
  saveRDS(sim2,file.path(od,"sim_result.rds"))
  source(file.path(INFRA_DIR,"hurdle_gate.R"))
  h <- run_hurdle_gate(sim_result=sim2,strategy_name=name,output_dir=od)
  jsonlite::write_json(h,file.path(od,"hurdle_result.json"),auto_unbox=T,pretty=T)
  list(perf=p, hurdle=h)
}

AR <- list()

cat("\n--- M1: C19+C07 ---\n")
F1 <- build_factors(function(fw,sd) {
  fw[,Score:=0]; nc<-0
  for(fn in c("C19_Composite_Earnings","C07_ESBR")) {
    w <- if(fn=="C19_Composite_Earnings") 0.6 else 0.4
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[,paste0("R_",fn):=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
      fw[,Score:=Score+w*get(paste0("R_",fn))]; nc<-nc+1 }}
  if(nc==0) return(NULL); fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M1")
r<-run_bt(F1,"M1_C19_C07","output_s5_M1"); if(!is.null(r)) AR[["M1"]]<-r

cat("\n--- M2: C19+D01 ---\n")
F2 <- build_factors(function(fw,sd) {
  fw[,Score:=0]; nc<-0
  for(fn in c("C19_Composite_Earnings","D01_IdioVol")) {
    w <- if(fn=="C19_Composite_Earnings") 0.6 else 0.4
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[,paste0("R_",fn):=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
      fw[,Score:=Score+w*get(paste0("R_",fn))]; nc<-nc+1 }}
  if(nc==0) return(NULL); fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M2")
r<-run_bt(F2,"M2_C19_D01","output_s5_M2"); if(!is.null(r)) AR[["M2"]]<-r

cat("\n--- M3: C19+M25 ---\n")
F3 <- build_factors(function(fw,sd) {
  fw[,Score:=0]; nc<-0
  for(fn in c("C19_Composite_Earnings","M25_Earnings_Mom_Streak")) {
    w <- if(fn=="C19_Composite_Earnings") 0.6 else 0.4
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[,paste0("R_",fn):=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
      fw[,Score:=Score+w*get(paste0("R_",fn))]; nc<-nc+1 }}
  if(nc==0) return(NULL); fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M3")
r<-run_bt(F3,"M3_C19_M25","output_s5_M3"); if(!is.null(r)) AR[["M3"]]<-r

cat("\n--- M4: DD 8/22 ---\n")
rr <- as.numeric(sim_parent$strategy_xts); rr[is.na(rr)] <- 0; nf <- length(rr)
nav <- cumprod(1+rr); dd <- 1-nav/cummax(nav); dd_lag <- c(0,dd[-nf])
dd_exp <- fifelse(dd_lag<=0.08,1,fifelse(dd_lag>=0.22,0.30,pmax(0.30,1-(dd_lag-0.08)/(0.22-0.08)*0.70)))
r<-run_overlay(dd_exp,"M4_DD8_22","output_s5_M4"); if(!is.null(r)) AR[["M4"]]<-r

cat("\n--- M5: DD+Regime ---\n")
tryCatch({
  source(file.path(INFRA_DIR,"regime_signal.R"))
  sdt <- load_regime_signal()
  rd <- as.Date(index(sim_parent$strategy_xts))
  cp <- numeric(nf)
  for(j in seq_len(nf)) { row<-sdt[Date<=rd[j]]; if(nrow(row)>0) cp[j]<-tail(row$Cash_Pct,1) else cp[j]<-0 }
  cl <- c(0,cp[-nf]); re <- 1-cl
  r<-run_overlay(dd_exp*re,"M5_DD_Regime","output_s5_M5"); if(!is.null(r)) AR[["M5"]]<-r
}, error=function(e) cat("M5 ERR:",e$message,"\n"))

cat("\n--- M6: Regime only ---\n")
tryCatch({
  r<-run_overlay(re,"M6_Regime","output_s5_M6"); if(!is.null(r)) AR[["M6"]]<-r
}, error=function(e) cat("M6 ERR:",e$message,"\n"))

cat("\n--- M7: 3mo lookback ---\n")
fl7 <- list()
for(i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i]); vf <- fdb_dates[fdb_dates<=sig_d]
  if(length(vf)<1) next; use <- tail(vf,3)
  fdt <- FDB_ALL[Date %in% use & Coverage==TRUE & Factor_Name=="C19_Composite_Earnings"]
  if(nrow(fdt)==0) next
  avg <- fdt[,.(Score=mean(Z_Score_Aligned,na.rm=T)),by=Ticker]
  liq <- RAWDATA[Date==sig_d,.(Ticker,AvgTV20)]
  avg <- merge(avg,liq,by="Ticker")[!is.na(AvgTV20)&AvgTV20>=LIQ_THRESHOLD]
  if(nrow(avg)<20) next
  avg[,Date:=sig_d]; fl7[[length(fl7)+1]] <- avg[,.(Date,Ticker,Score)]
}
F7 <- rbindlist(fl7); setorder(F7,Date,-Score)
cat(sprintf("  [M7] %d dates\n",length(fl7)))
r<-run_bt(F7,"M7_3moLookback","output_s5_M7"); if(!is.null(r)) AR[["M7"]]<-r

cat("\n--- M8: Rank ---\n")
F8 <- build_factors(function(fw,sd) {
  if(!"C19_Composite_Earnings" %in% names(fw)) return(NULL)
  fw[,Score:=frank(C19_Composite_Earnings,na.last="keep",ties.method="average")/sum(!is.na(C19_Composite_Earnings))]
  fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M8")
r<-run_bt(F8,"M8_Rank","output_s5_M8"); if(!is.null(r)) AR[["M8"]]<-r

cat("\n--- M9: Best combo + DD+Regime ---\n")
best_sr <- 0; best_nm <- "M1"
for(mn in c("M1","M2","M3")) if(mn %in% names(AR) && AR[[mn]]$perf$Sharpe > best_sr) { best_sr<-AR[[mn]]$perf$Sharpe; best_nm<-mn }
cat(sprintf("  Best combo: %s (SR=%.3f)\n",best_nm,best_sr))
bsp <- file.path(SCRIPT_DIR,paste0("output_s5_",best_nm),"sim_result.rds")
if(file.exists(bsp)) {
  bsim<-readRDS(bsp); brr<-as.numeric(bsim$strategy_xts); brr[is.na(brr)]<-0; bnf<-length(brr)
  bnav<-cumprod(1+brr); bdd<-1-bnav/cummax(bnav); bddl<-c(0,bdd[-bnf])
  bde<-fifelse(bddl<=0.08,1,fifelse(bddl>=0.22,0.30,pmax(0.30,1-(bddl-0.08)/(0.22-0.08)*0.70)))
  brd<-as.Date(index(bsim$strategy_xts)); bcp<-numeric(bnf)
  for(j in seq_len(bnf)){row<-sdt[Date<=brd[j]];if(nrow(row)>0) bcp[j]<-tail(row$Cash_Pct,1) else bcp[j]<-0}
  bcl<-c(0,bcp[-bnf]); bre<-1-bcl
  bfr<-brr*bde*bre; cx9<-xts(bfr,order.by=brd); names(cx9)<-"Strategy"
  sim9<-bsim; sim9$strategy_xts<-cx9
  od9<-file.path(SCRIPT_DIR,"output_s5_M9"); dir.create(od9,showWarnings=F)
  p9<-summarise_perf(cx9,"M9_Best_DD_Regime")
  cat(sprintf("  M9: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",p9$Sharpe,p9$CAGR,p9$MDD))
  generate_charts(sim9,output_dir=od9,strategy_name="M9")
  fwrite(rbind(p9,summarise_perf(sim9$bm_xts,"BM")),file.path(od9,"performance.csv"))
  saveRDS(sim9,file.path(od9,"sim_result.rds"))
  source(file.path(INFRA_DIR,"hurdle_gate.R"))
  h9<-run_hurdle_gate(sim_result=sim9,strategy_name="M9",output_dir=od9)
  jsonlite::write_json(h9,file.path(od9,"hurdle_result.json"),auto_unbox=T,pretty=T)
  AR[["M9"]]<-list(perf=p9,hurdle=h9)
}

cat("\n\n=== STR_1550 S5 SUMMARY ===\n")
cat(sprintf("%-6s|%-5s|%-6s|%6s|%7s|%8s|%7s\n","Mut","Cat","Grade","Score","SR","CAGR%","MDD%"))
cat(sprintf("%-6s|%-5s|%-6s|%6.1f|%7.3f|%8.2f|%7.1f\n","Base","-","C",68.9,1.001,22.69,52.85))
cats<-c(M1="C",M2="C",M3="C",M4="F",M5="F",M6="F",M7="B",M8="A",M9="C+F")
for(mn in c("M1","M2","M3","M4","M5","M6","M7","M8","M9")) {
  if(mn %in% names(AR)) {
    r<-AR[[mn]]; g<-r$hurdle$grade%||%r$hurdle$verdict$grade%||%"?"
    s<-r$hurdle$total_score%||%r$hurdle$verdict$total_score%||%r$hurdle$score%||%0
    cat(sprintf("%-6s|%-5s|%-6s|%6.1f|%7.3f|%8.2f|%7.1f\n",mn,cats[mn],g,s,r$perf$Sharpe,r$perf$CAGR,r$perf$MDD))
  } else { cat(sprintf("%-6s|%-5s|%-6s|%6s|%7s|%8s|%7s\n",mn,cats[mn],"ERR","--","--","--","--")) }
}

if("YM" %in% names(RAWDATA)) RAWDATA[,YM:=NULL]
for(col in c("TradingValue","AvgTV20")) if(col %in% names(RAWDATA)) RAWDATA[,(col):=NULL]
rm(FDB_ALL); gc(verbose=F)
cat("\n=== COMPLETE ===\n")
