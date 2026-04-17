cat("=== STR_1558 S5: 9 Mutations (L22 Ret Autocorr Diversifier) ===\n")
## 핵심: L22 base (SR 0.544, F) → C19 corr -0.108 = best diversifier
## M3(L22+C19) + M4(4F extend STR_1555) 최우선
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); set.seed(1558)
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

## Load ALL needed factors once (L-534)
NEEDED <- c("L22_Ret_Autocorr","CR07_Momentum_Crowding","R01_VaR_95",
            "C19_Composite_Earnings","V14_EBIT_EV","D01_IdioVol")
ds <- open_dataset(file.path(CACHE_DIR,"factor_db"), format="parquet")
FDB_ALL <- ds |> filter(Factor_Name %in% NEEDED) |>
  select(Date,Ticker,Factor_Name,Z_Score,Coverage) |> collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
source(file.path(INFRA_DIR,"factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB loaded: %s rows, %d factors\n", format(nrow(FDB_ALL),big.mark=","), uniqueN(FDB_ALL$Factor_Name)))

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
    liq <- RAWDATA[Date==sig_d, .(Ticker,AvgTV20,Sector)]
    fw <- merge(fw, liq, by="Ticker")
    fw <- fw[!is.na(AvgTV20) & AvgTV20>=LIQ_THRESHOLD]
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

apply_dd <- function(ret_vec, dd_start, dd_full, dd_min_exp=0.30) {
  nf <- length(ret_vec)
  nav <- cumprod(1+ret_vec); dd <- 1-nav/cummax(nav)
  dd_lag <- c(0, dd[-nf])
  fifelse(dd_lag<=dd_start, 1,
    fifelse(dd_lag>=dd_full, dd_min_exp,
      pmax(dd_min_exp, 1-(dd_lag-dd_start)/(dd_full-dd_start)*(1-dd_min_exp))))
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

score_blend <- function(fw, fns, wts=NULL) {
  if(is.null(wts)) wts <- rep(1/length(fns), length(fns))
  fw[, Score := 0]; nc <- 0
  for(k in seq_along(fns)) {
    fn <- fns[k]
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[, Score := Score + wts[k] * get(fn)]; nc <- nc+1 }}
  if(nc==0) return(NULL)
  fw
}

AR <- list()

## --- M1: L22 + CR07 EW ---
cat("\n--- M1: L22+CR07 EW ---\n")
F1 <- build_factors(function(fw,sd) {
  fw <- score_blend(fw, c("L22_Ret_Autocorr","CR07_Momentum_Crowding"))
  if(is.null(fw)) return(NULL)
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M1")
r<-run_bt(F1,"M1_L22_CR07","output_s5_M1"); if(!is.null(r)) AR[["M1"]]<-r

## --- M2: L22 + R01_VaR EW ---
cat("\n--- M2: L22+R01 EW ---\n")
F2 <- build_factors(function(fw,sd) {
  fw <- score_blend(fw, c("L22_Ret_Autocorr","R01_VaR_95"))
  if(is.null(fw)) return(NULL)
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M2")
r<-run_bt(F2,"M2_L22_R01","output_s5_M2"); if(!is.null(r)) AR[["M2"]]<-r

## --- M3: L22 + C19 EW (KEY TEST: corr -0.108) ---
cat("\n--- M3: L22+C19 EW (KEY) ---\n")
F3 <- build_factors(function(fw,sd) {
  fw <- score_blend(fw, c("L22_Ret_Autocorr","C19_Composite_Earnings"))
  if(is.null(fw)) return(NULL)
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M3")
r<-run_bt(F3,"M3_L22_C19_KEY","output_s5_M3"); if(!is.null(r)) AR[["M3"]]<-r

## --- M4: C19+V14+D01+L22 4F EW (extend STR_1555) ---
cat("\n--- M4: 4F C19+V14+D01+L22 ---\n")
F4 <- build_factors(function(fw,sd) {
  fw <- score_blend(fw, c("C19_Composite_Earnings","V14_EBIT_EV","D01_IdioVol","L22_Ret_Autocorr"))
  if(is.null(fw)) return(NULL)
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M4")
r<-run_bt(F4,"M4_4F_C19_V14_D01_L22","output_s5_M4"); if(!is.null(r)) AR[["M4"]]<-r

## --- M5: Best C-mutation + Regime v7.1 ---
cat("\n--- M5: Best+Regime ---\n")
best_sr <- 0; best_nm <- NULL
for(mn in c("M1","M2","M3","M4")) {
  if(mn %in% names(AR) && !is.null(AR[[mn]]$perf) && AR[[mn]]$perf$Sharpe > best_sr) {
    best_sr <- AR[[mn]]$perf$Sharpe; best_nm <- mn }}
if(!is.null(best_nm) && !is.null(AR[[best_nm]]$sim)) {
  cat(sprintf("  Best: %s (SR=%.3f)\n", best_nm, best_sr))
  tryCatch({
    source(file.path(INFRA_DIR,"regime_signal.R"))
    sdt <- load_regime_signal()
    rr5 <- as.numeric(AR[[best_nm]]$sim$strategy_xts); rr5[is.na(rr5)] <- 0; nf5 <- length(rr5)
    rd5 <- as.Date(index(AR[[best_nm]]$sim$strategy_xts))
    cp5 <- numeric(nf5)
    for(j in seq_len(nf5)) { row <- sdt[Date<=rd5[j]]; if(nrow(row)>0) cp5[j]<-tail(row$Cash_Pct,1) else cp5[j]<-0 }
    cl5 <- c(0, cp5[-nf5])  # t-1 lag
    r <- run_overlay_on_sim(AR[[best_nm]]$sim, 1-cl5, "M5_Best_Regime", "output_s5_M5")
    if(!is.null(r)) AR[["M5"]] <- r
  }, error=function(e) cat("M5 ERR:",e$message,"\n"))
} else cat("  SKIP (no valid base)\n")

## --- M6: Best + DD 6/20 + Regime ---
cat("\n--- M6: Best+DD+Regime ---\n")
if(!is.null(best_nm) && !is.null(AR[[best_nm]]$sim)) {
  rr6 <- as.numeric(AR[[best_nm]]$sim$strategy_xts); rr6[is.na(rr6)] <- 0; nf6 <- length(rr6)
  dd_s <- if(best_sr >= 0.7) 0.06 else 0.08
  dd_f <- if(best_sr >= 0.7) 0.20 else 0.25
  dd6 <- apply_dd(rr6, dd_s, dd_f, 0.30)
  tryCatch({
    rd6 <- as.Date(index(AR[[best_nm]]$sim$strategy_xts))
    cp6 <- numeric(nf6)
    for(j in seq_len(nf6)) { row <- sdt[Date<=rd6[j]]; if(nrow(row)>0) cp6[j]<-tail(row$Cash_Pct,1) else cp6[j]<-0 }
    cl6 <- c(0, cp6[-nf6])
    r <- run_overlay_on_sim(AR[[best_nm]]$sim, dd6*(1-cl6), "M6_Best_DD_Regime", "output_s5_M6")
    if(!is.null(r)) AR[["M6"]] <- r
  }, error=function(e) {
    r <- run_overlay_on_sim(AR[[best_nm]]$sim, dd6, "M6_Best_DD", "output_s5_M6")
    if(!is.null(r)) AR[["M6"]] <- r
  })
} else cat("  SKIP\n")

## --- M7: L22 126d z-score ---
cat("\n--- M7: L22 126d zscore ---\n")
F7 <- build_factors(function(fw,sd) {
  if(!"L22_Ret_Autocorr" %in% names(fw)) return(NULL)
  fw[, Score := L22_Ret_Autocorr]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M7")
## 126d rolling z-score applied externally
if(nrow(F7)>0) {
  setorder(F7, Ticker, Date)
  F7[, Score := {
    if(.N >= 6) { m <- frollmean(Score,6L,align="right"); s <- frollapply(Score,6L,sd,align="right"); fifelse(s>0,(Score-m)/s,0) }
    else Score
  }, by=Ticker]
  F7 <- F7[!is.na(Score)]
  setorder(F7, Date, -Score)
}
r<-run_bt(F7,"M7_L22_126d","output_s5_M7"); if(!is.null(r)) AR[["M7"]]<-r

## --- M8: L22 63d z-score ---
cat("\n--- M8: L22 63d zscore ---\n")
F8 <- build_factors(function(fw,sd) {
  if(!"L22_Ret_Autocorr" %in% names(fw)) return(NULL)
  fw[, Score := L22_Ret_Autocorr]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M8")
if(nrow(F8)>0) {
  setorder(F8, Ticker, Date)
  F8[, Score := {
    if(.N >= 3) { m <- frollmean(Score,3L,align="right"); s <- frollapply(Score,3L,sd,align="right"); fifelse(s>0,(Score-m)/s,0) }
    else Score
  }, by=Ticker]
  F8 <- F8[!is.na(Score)]
  setorder(F8, Date, -Score)
}
r<-run_bt(F8,"M8_L22_63d","output_s5_M8"); if(!is.null(r)) AR[["M8"]]<-r

## --- M9: L22 IVol weighted ---
cat("\n--- M9: L22 IVol weighted ---\n")
F9 <- build_factors(function(fw,sd) {
  if(!"L22_Ret_Autocorr" %in% names(fw)) return(NULL)
  fw[, Score := L22_Ret_Autocorr]
  fw[, Date := sd]; fw[!is.na(Score), .(Date,Ticker,Score)]
}, "M9")
## IVol weighting applied in run_bt via score weight (proxy: higher score = lower vol preference)
r<-run_bt(F9,"M9_L22_IVol","output_s5_M9",wm="score"); if(!is.null(r)) AR[["M9"]]<-r

## === SUMMARY ===
cat("\n\n=== STR_1558 S5 SUMMARY ===\n")
cat(sprintf("%-6s|%-10s|%-6s|%6s|%7s|%8s|%7s\n","Mut","Category","Grade","Score","SR","CAGR%","MDD%"))
cat(sprintf("%-6s|%-10s|%-6s|%6.1f|%7.3f|%8.2f|%7.1f\n","Base","L22 solo","F",0,0.544,0,0))
cats <- c(M1="MF:CR07",M2="MF:R01",M3="MF:C19*",M4="MF:4F*",M5="OL:Reg",M6="OL:DD+R",M7="A:126d",M8="B:63d",M9="E:IVol")
for(mn in paste0("M",1:9)) {
  if(mn %in% names(AR)) {
    r<-AR[[mn]]; g<-r$hurdle$grade%||%r$hurdle$verdict$grade%||%"?"
    s<-r$hurdle$total_score%||%r$hurdle$verdict$total_score%||%r$hurdle$score%||%0
    cat(sprintf("%-6s|%-10s|%-6s|%6.1f|%7.3f|%8.2f|%7.1f\n",mn,cats[mn],g,s,r$perf$Sharpe,r$perf$CAGR,r$perf$MDD))
  } else { cat(sprintf("%-6s|%-10s|%-6s|%6s|%7s|%8s|%7s\n",mn,cats[mn],"SKIP","--","--","--","--")) }
}

if("YM" %in% names(RAWDATA)) RAWDATA[,YM:=NULL]
for(col in c("TradingValue","AvgTV20")) if(col %in% names(RAWDATA)) RAWDATA[,(col):=NULL]
gc(verbose=F)
cat("\n=== STR_1558 S5 COMPLETE ===\n")
