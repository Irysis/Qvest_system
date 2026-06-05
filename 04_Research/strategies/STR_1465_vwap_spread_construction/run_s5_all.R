cat("=== STR_1465 S5: 9 Mutations (SF09 VWAP Spread) ===\n")
## 핵심: L40_VWAP_Spread base (SR 0.554, B) → C19 anchor + overlay
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); set.seed(1465)
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow); library(dplyr)

res <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose=FALSE)

NEEDED <- c("L40_VWAP_Spread","C19_Composite_Earnings",
            "Q04_Piotroski_F_Score","D01_IdioVol","L22_Ret_Autocorr")
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

build_factors <- function(scoring_fn, label, liq_thresh=LIQ_THRESHOLD) {
  fl <- vector("list", length(monthly_dates)); nd <- 0L
  for(i in seq_along(monthly_dates)) {
    sig_d <- as.Date(monthly_dates[i])
    vf <- fdb_dates[fdb_dates <= sig_d]
    if(length(vf)==0) next
    fdt <- FDB_ALL[Date==max(vf) & Coverage==TRUE]
    if(nrow(fdt)==0) next
    fw <- dcast(fdt, Ticker~Factor_Name, value.var="Z_Score_Aligned")
    liq <- RAWDATA[Date==sig_d, .(Ticker,AvgTV20,Sector)]
    fw <- merge(fw, liq, by="Ticker")
    fw <- fw[!is.na(AvgTV20) & AvgTV20>=liq_thresh]
    if(nrow(fw)<20) next
    r <- tryCatch(scoring_fn(copy(fw), sig_d), error=function(e) NULL)
    if(!is.null(r) && nrow(r)>0) { fl[[i]] <- r; nd <- nd+1L }
  }
  F <- rbindlist(fl[!sapply(fl,is.null)]); setorder(F,Date,-Score)
  cat(sprintf("  [%s] %d dates\n",label,nd)); F
}

run_bt <- function(FACTORS, name, dir_name, nh=30L, wm="equal") {
  RD <- copy(RAWDATA_ORIG)
  sim <- tryCatch(run_monthly_simulation(RAWDATA=RD, BM_DT=BM_DT, FACTORS=FACTORS, n_holdings=nh,
    weight_method=wm, commission=0.0015, buffer_zone=list(keep_n=50L,entry_n=25L)),
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

apply_dd <- function(ret_vec, dd_start, dd_full, dd_min_exp=0.25) {
  nf <- length(ret_vec)
  nav <- cumprod(1+ret_vec); dd <- 1-nav/cummax(nav)
  dd_lag <- c(0, dd[-nf])
  fifelse(dd_lag<=dd_start, 1,
    fifelse(dd_lag>=dd_full, dd_min_exp,
      pmax(dd_min_exp, 1-(dd_lag-dd_start)/(dd_full-dd_start)*(1-dd_min_exp))))
}

apply_vt <- function(ret_vec, vt_target=0.20) {
  nf <- length(ret_vec)
  vol_exp <- numeric(nf); vol_exp[1] <- 1
  for(j in 2:nf) {
    window <- ret_vec[1:(j-1)]
    realized_vol <- sd(window) * sqrt(252)
    if(is.na(realized_vol) || realized_vol < 0.01) vol_exp[j] <- 1
    else vol_exp[j] <- min(1.5, max(0.2, vt_target / realized_vol))
  }
  c(1, vol_exp[-nf])
}

run_overlay_on_sim <- function(sim_obj, exp_vec, name, dir_name) {
  rr <- as.numeric(sim_obj$strategy_xts); rr[is.na(rr)] <- 0
  fr <- rr * exp_vec
  cx <- xts(fr, order.by=as.Date(index(sim_obj$strategy_xts))); names(cx) <- "Strategy"
  sim2 <- sim_obj; sim2$strategy_xts <- cx
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

## --- M1: C19 60% + L40 40% ---
cat("\n--- M1: C19(60)+L40(40) ---\n")
F1 <- build_factors(function(fw,sd) {
  wts <- c(C19_Composite_Earnings=0.6, L40_VWAP_Spread=0.4)
  fw[, Score := 0]; nc <- 0
  for(fn in names(wts)) {
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[, Score := Score + wts[fn] * get(fn)]; nc <- nc+1 }}
  if(nc==0) return(NULL)
  fw[, Score := Score - mean(Score,na.rm=T), by=Sector]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M1")
r<-run_bt(F1,"M1_C19_L40","output_s5_M1"); if(!is.null(r)) AR[["M1"]]<-r

## --- M2: Q04 + L40 EW ---
cat("\n--- M2: Q04+L40 EW ---\n")
F2 <- build_factors(function(fw,sd) {
  fns <- c("Q04_Piotroski_F_Score","L40_VWAP_Spread")
  fw[, Score := 0]; nc <- 0
  for(fn in fns) {
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[, Score := Score + 0.5 * get(fn)]; nc <- nc+1 }}
  if(nc==0) return(NULL)
  fw[, Score := Score - mean(Score,na.rm=T), by=Sector]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M2")
r<-run_bt(F2,"M2_Q04_L40","output_s5_M2"); if(!is.null(r)) AR[["M2"]]<-r

## --- M3: D01(30) + L40(30) + C19(40) ---
cat("\n--- M3: D01+L40+C19 ---\n")
F3 <- build_factors(function(fw,sd) {
  wts <- c(D01_IdioVol=0.3, L40_VWAP_Spread=0.3, C19_Composite_Earnings=0.4)
  fw[, Score := 0]; nc <- 0
  for(fn in names(wts)) {
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[, Score := Score + wts[fn] * get(fn)]; nc <- nc+1 }}
  if(nc==0) return(NULL)
  fw[, Score := Score - mean(Score,na.rm=T), by=Sector]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M3")
r<-run_bt(F3,"M3_D01_L40_C19","output_s5_M3"); if(!is.null(r)) AR[["M3"]]<-r

## --- M4: DD 8/22 on base ---
cat("\n--- M4: Base+DD(8/22) ---\n")
rr4 <- as.numeric(sim_parent$strategy_xts); rr4[is.na(rr4)] <- 0
dd_exp4 <- apply_dd(rr4, 0.08, 0.22, 0.25)
r <- run_overlay_on_sim(sim_parent, dd_exp4, "M4_DD822", "output_s5_M4")
if(!is.null(r)) AR[["M4"]] <- r

## --- M5: M1 + DD 7/22 + VT 20% ---
cat("\n--- M5: M1+DD(7/22)+VT20 ---\n")
if("M1" %in% names(AR) && !is.null(AR[["M1"]]$sim)) {
  rr5 <- as.numeric(AR[["M1"]]$sim$strategy_xts); rr5[is.na(rr5)] <- 0
  dd5 <- apply_dd(rr5, 0.07, 0.22, 0.25)
  vt5 <- apply_vt(rr5, 0.20)
  r <- run_overlay_on_sim(AR[["M1"]]$sim, dd5 * vt5, "M5_M1_DD_VT", "output_s5_M5")
  if(!is.null(r)) AR[["M5"]] <- r
} else cat("  SKIP (M1 failed)\n")

## --- M6: M1 + Regime ---
cat("\n--- M6: M1+Regime ---\n")
if("M1" %in% names(AR) && !is.null(AR[["M1"]]$sim)) {
  tryCatch({
    source(file.path(INFRA_DIR,"regime_signal.R"))
    sdt <- load_regime_signal()
    rr6 <- as.numeric(AR[["M1"]]$sim$strategy_xts); rr6[is.na(rr6)] <- 0; nf6 <- length(rr6)
    rd6 <- as.Date(index(AR[["M1"]]$sim$strategy_xts))
    cp6 <- numeric(nf6)
    for(j in seq_len(nf6)) { row <- sdt[Date<=rd6[j]]; if(nrow(row)>0) cp6[j]<-tail(row$Cash_Pct,1) else cp6[j]<-0 }
    cl6 <- c(0, cp6[-nf6])  # t-1 lag
    re6 <- 1 - cl6
    r <- run_overlay_on_sim(AR[["M1"]]$sim, re6, "M6_M1_Regime", "output_s5_M6")
    if(!is.null(r)) AR[["M6"]] <- r
  }, error=function(e) cat("M6 ERR:",e$message,"\n"))
} else cat("  SKIP (M1 failed)\n")

## --- M7: Score-weighted (base L40) ---
cat("\n--- M7: Score-weighted ---\n")
F7 <- build_factors(function(fw,sd) {
  if(!"L40_VWAP_Spread" %in% names(fw)) return(NULL)
  fw[, Score := L40_VWAP_Spread]
  fw[, Score := Score - mean(Score,na.rm=T), by=Sector]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M7")
r<-run_bt(F7,"M7_ScoreWt","output_s5_M7",wm="score"); if(!is.null(r)) AR[["M7"]]<-r

## --- M8: L22_Ret_Autocorr substitution ---
cat("\n--- M8: L22_Ret_Autocorr ---\n")
F8 <- build_factors(function(fw,sd) {
  if(!"L22_Ret_Autocorr" %in% names(fw)) return(NULL)
  fw[, Score := L22_Ret_Autocorr]
  fw[, Score := Score - mean(Score,na.rm=T), by=Sector]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M8")
r<-run_bt(F8,"M8_L22","output_s5_M8"); if(!is.null(r)) AR[["M8"]]<-r

## --- M9: Liquidity 5e8 ---
cat("\n--- M9: LIQ 5e8 ---\n")
F9 <- build_factors(function(fw,sd) {
  if(!"L40_VWAP_Spread" %in% names(fw)) return(NULL)
  fw[, Score := L40_VWAP_Spread]
  fw[, Score := Score - mean(Score,na.rm=T), by=Sector]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M9", liq_thresh=5e8)
r<-run_bt(F9,"M9_LIQ5e8","output_s5_M9"); if(!is.null(r)) AR[["M9"]]<-r

## === SUMMARY ===
cat("\n\n=== STR_1465 S5 SUMMARY ===\n")
cat(sprintf("%-6s|%-8s|%-6s|%6s|%7s|%8s|%7s\n","Mut","Category","Grade","Score","SR","CAGR%","MDD%"))
cat(sprintf("%-6s|%-8s|%-6s|%6.1f|%7.3f|%8.2f|%7.1f\n","Base","base","B",0,0.554,0,0))
cats <- c(M1="MF",M2="MF",M3="MF",M4="OL",M5="OL",M6="OL",M7="SW",M8="FS",M9="UNI")
for(mn in paste0("M",1:9)) {
  if(mn %in% names(AR)) {
    r<-AR[[mn]]; g<-r$hurdle$grade%||%r$hurdle$verdict$grade%||%"?"
    s<-r$hurdle$total_score%||%r$hurdle$verdict$total_score%||%r$hurdle$score%||%0
    cat(sprintf("%-6s|%-8s|%-6s|%6.1f|%7.3f|%8.2f|%7.1f\n",mn,cats[mn],g,s,r$perf$Sharpe,r$perf$CAGR,r$perf$MDD))
  } else { cat(sprintf("%-6s|%-8s|%-6s|%6s|%7s|%8s|%7s\n",mn,cats[mn],"ERR","--","--","--","--")) }
}

if("YM" %in% names(RAWDATA)) RAWDATA[,YM:=NULL]
for(col in c("TradingValue","AvgTV20")) if(col %in% names(RAWDATA)) RAWDATA[,(col):=NULL]
gc(verbose=F)
cat("\n=== STR_1465 S5 COMPLETE ===\n")
