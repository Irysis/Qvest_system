cat("=== STR_1519 S5: 9 Mutations ===\n")
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); set.seed(1519)
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

# --- Factor DB load (1회만) ---
NEEDED <- c("M25_Earnings_Mom_Streak","V24_Residual_Income","C19_Composite_Earnings","L22_Ret_Autocorr")
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

# --- Helpers ---
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

run_overlay_on_sim <- function(base_sim, exp_vec, name, dir_name) {
  rr <- as.numeric(base_sim$strategy_xts); rr[is.na(rr)] <- 0
  rd <- as.Date(index(base_sim$strategy_xts))
  n <- length(rr)
  if(length(exp_vec) != n) {
    exp_vec2 <- rep(1, n)
    idx <- seq_len(min(length(exp_vec), n))
    exp_vec2[idx] <- exp_vec[idx]
    exp_vec <- exp_vec2
  }
  fr <- rr * exp_vec
  cx <- xts(fr, order.by=rd); names(cx) <- "Strategy"
  sim2 <- base_sim; sim2$strategy_xts <- cx
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

# -------------------------------------------------------
cat("\n--- M1: M25_Earnings_Mom_Streak standalone ---\n")
F1 <- build_factors(function(fw,sd) {
  fn <- "M25_Earnings_Mom_Streak"
  if(!fn %in% names(fw)) return(NULL)
  fw <- fw[!is.na(get(fn))]
  if(nrow(fw)<20) return(NULL)
  fw[,Score:=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
  fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M1")
r<-run_bt(F1,"M1_M25_standalone","output_s5_M1"); if(!is.null(r)) AR[["M1"]]<-r

# -------------------------------------------------------
cat("\n--- M2: V24_Residual_Income standalone ---\n")
F2 <- build_factors(function(fw,sd) {
  fn <- "V24_Residual_Income"
  if(!fn %in% names(fw)) return(NULL)
  fw <- fw[!is.na(get(fn))]
  if(nrow(fw)<20) return(NULL)
  fw[,Score:=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
  fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M2")
r<-run_bt(F2,"M2_V24_standalone","output_s5_M2"); if(!is.null(r)) AR[["M2"]]<-r

# -------------------------------------------------------
cat("\n--- M3: M25+V24+C19 3F EW Score ---\n")
F3 <- build_factors(function(fw,sd) {
  fns3 <- c("M25_Earnings_Mom_Streak","V24_Residual_Income","C19_Composite_Earnings")
  fw[,Score:=0]; nc<-0L
  for(fn in fns3) {
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[,paste0("R_",fn):=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
      fw[,Score:=Score+(1/3)*get(paste0("R_",fn))]; nc<-nc+1L
    }
  }
  if(nc==0L) return(NULL)
  fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M3")
r<-run_bt(F3,"M3_M25_V24_C19","output_s5_M3"); if(!is.null(r)) AR[["M3"]]<-r

# -------------------------------------------------------
cat("\n--- M4: M25+V24+L22 3F (cross-family) ---\n")
F4 <- build_factors(function(fw,sd) {
  fns4 <- c("M25_Earnings_Mom_Streak","V24_Residual_Income","L22_Ret_Autocorr")
  fw[,Score:=0]; nc<-0L
  for(fn in fns4) {
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[,paste0("R_",fn):=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
      fw[,Score:=Score+(1/3)*get(paste0("R_",fn))]; nc<-nc+1L
    }
  }
  if(nc==0L) return(NULL)
  fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M4")
r<-run_bt(F4,"M4_M25_V24_L22","output_s5_M4"); if(!is.null(r)) AR[["M4"]]<-r

# -------------------------------------------------------
cat("\n--- M5: Best M1~M4 + Regime v7.1 ---\n")
best_sr_m <- -Inf; best_nm_m <- "M1"
for(mn in c("M1","M2","M3","M4")) {
  if(mn %in% names(AR) && AR[[mn]]$perf$Sharpe > best_sr_m) {
    best_sr_m <- AR[[mn]]$perf$Sharpe; best_nm_m <- mn
  }
}
cat(sprintf("  Best base: %s (SR=%.3f)\n", best_nm_m, best_sr_m))
tryCatch({
  source(file.path(INFRA_DIR,"regime_signal.R"))
  sdt <- load_regime_signal()
  bsp5 <- file.path(SCRIPT_DIR, paste0("output_s5_",best_nm_m), "sim_result.rds")
  if(file.exists(bsp5)) {
    bsim5 <- readRDS(bsp5)
    rd5 <- as.Date(index(bsim5$strategy_xts))
    nf5 <- length(rd5)
    cp5 <- numeric(nf5)
    for(j in seq_len(nf5)) { row<-sdt[Date<=rd5[j]]; if(nrow(row)>0) cp5[j]<-tail(row$Cash_Pct,1) else cp5[j]<-0 }
    cl5 <- c(0, cp5[-nf5]); re5 <- 1-cl5
    r <- run_overlay_on_sim(bsim5, re5, "M5_Best_Regime", "output_s5_M5")
    if(!is.null(r)) AR[["M5"]] <- r
  } else cat("  M5: base sim not found\n")
}, error=function(e) cat("M5 ERR:",e$message,"\n"))

# -------------------------------------------------------
cat("\n--- M6: Best M1~M4 + DD 6/20 + Regime ---\n")
tryCatch({
  bsp6 <- file.path(SCRIPT_DIR, paste0("output_s5_",best_nm_m), "sim_result.rds")
  if(file.exists(bsp6)) {
    bsim6 <- readRDS(bsp6)
    rr6 <- as.numeric(bsim6$strategy_xts); rr6[is.na(rr6)] <- 0
    rd6 <- as.Date(index(bsim6$strategy_xts))
    nf6 <- length(rr6)
    nav6 <- cumprod(1+rr6); dd6_vec <- 1-nav6/cummax(nav6)
    dd6_lag <- c(0, dd6_vec[-nf6])
    dd6 <- fifelse(dd6_lag<=0.06, 1,
      fifelse(dd6_lag>=0.20, 0.30,
        pmax(0.30, 1-(dd6_lag-0.06)/(0.20-0.06)*0.70)))
    cp6 <- numeric(nf6)
    for(j in seq_len(nf6)) { row<-sdt[Date<=rd6[j]]; if(nrow(row)>0) cp6[j]<-tail(row$Cash_Pct,1) else cp6[j]<-0 }
    cl6 <- c(0, cp6[-nf6]); re6 <- 1-cl6
    r <- run_overlay_on_sim(bsim6, dd6*re6, "M6_Best_DD6_20_Regime", "output_s5_M6")
    if(!is.null(r)) AR[["M6"]] <- r
  } else cat("  M6: base sim not found\n")
}, error=function(e) cat("M6 ERR:",e$message,"\n"))

# -------------------------------------------------------
cat("\n--- M7: M25+V24 sector-neutral ---\n")
F7 <- build_factors(function(fw,sd) {
  rd_sec <- RAWDATA[Date==sd, .(Ticker, Sector=if("Sector" %in% names(RAWDATA)) Sector else "ALL")]
  fw <- merge(fw, rd_sec, by="Ticker", all.x=TRUE)
  fw[is.na(Sector), Sector:="ALL"]
  fw[, Score:=0]; nc<-0L
  for(fn in c("M25_Earnings_Mom_Streak","V24_Residual_Income")) {
    if(fn %in% names(fw) && sum(!is.na(fw[[fn]]))>10) {
      fw[, paste0("R_",fn) := frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn))), by=Sector]
      fw[, Score:=Score+0.5*get(paste0("R_",fn))]; nc<-nc+1L
    }
  }
  if(nc==0L) return(NULL)
  fw[,Date:=sd]; fw[!is.na(Score),.(Date,Ticker,Score)]
}, "M7")
r<-run_bt(F7,"M7_sector_neutral","output_s5_M7"); if(!is.null(r)) AR[["M7"]]<-r

# -------------------------------------------------------
cat("\n--- M8: M25+V24 3-month smoothing ---\n")
fl8 <- list()
for(i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  vf <- fdb_dates[fdb_dates <= sig_d]
  if(length(vf)<1) next
  use <- tail(vf, 3)
  fdt <- FDB_ALL[Date %in% use & Coverage==TRUE & Factor_Name %in% c("M25_Earnings_Mom_Streak","V24_Residual_Income")]
  if(nrow(fdt)==0) next
  avg <- fdt[, .(Z_avg=mean(Z_Score_Aligned,na.rm=TRUE)), by=.(Ticker,Factor_Name)]
  avg_w <- dcast(avg, Ticker~Factor_Name, value.var="Z_avg")
  liq <- RAWDATA[Date==sig_d, .(Ticker,AvgTV20)]
  avg_w <- merge(avg_w, liq, by="Ticker")[!is.na(AvgTV20) & AvgTV20>=LIQ_THRESHOLD]
  if(nrow(avg_w)<20) next
  avg_w[, Score:=0]; nc8<-0L
  for(fn in c("M25_Earnings_Mom_Streak","V24_Residual_Income")) {
    if(fn %in% names(avg_w) && sum(!is.na(avg_w[[fn]]))>10) {
      avg_w[, paste0("R_",fn):=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
      avg_w[, Score:=Score+0.5*get(paste0("R_",fn))]; nc8<-nc8+1L
    }
  }
  if(nc8==0L) next
  avg_w[, Date:=sig_d]
  fl8[[length(fl8)+1]] <- avg_w[!is.na(Score), .(Date,Ticker,Score)]
}
if(length(fl8)>0) {
  F8 <- rbindlist(fl8); setorder(F8,Date,-Score)
  cat(sprintf("  [M8] %d dates\n",length(fl8)))
  r<-run_bt(F8,"M8_3mo_smoothing","output_s5_M8"); if(!is.null(r)) AR[["M8"]]<-r
} else cat("  M8: no data\n")

# -------------------------------------------------------
cat("\n--- M9: M25+V24 ICIR-weighted (expanding 36mo) ---\n")
# ICIR-weighted: compute rolling 36-month ICIR for each factor, weight proportionally
fl9 <- list()
all_fdb_dates_sorted <- sort(unique(FDB_ALL$Date))

for(i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  vf <- fdb_dates[fdb_dates <= sig_d]
  if(length(vf)<12) next
  # Expanding window up to 36 months for ICIR
  icir_window <- tail(vf, min(36L, length(vf)))

  # Compute IC per month for each factor
  ic_list <- list()
  for(fn_icir in c("M25_Earnings_Mom_Streak","V24_Residual_Income")) {
    ics <- sapply(icir_window, function(d) {
      fdt_i <- FDB_ALL[Date==d & Coverage==TRUE & Factor_Name==fn_icir]
      if(nrow(fdt_i)<10) return(NA_real_)
      rd_next <- RAWDATA[Date > d, .(Ticker, Ret, Date)]
      if(nrow(rd_next)==0) return(NA_real_)
      nd <- min(rd_next$Date)
      rd_next <- rd_next[Date==nd, .(Ticker, Ret)]
      merged <- merge(fdt_i[,.(Ticker,Z_Score_Aligned)], rd_next, by="Ticker")
      if(nrow(merged)<10) return(NA_real_)
      cor(merged$Z_Score_Aligned, merged$Ret, use="complete.obs", method="spearman")
    })
    ics <- ics[!is.na(ics)]
    if(length(ics)<3) { ic_list[[fn_icir]] <- 0.5; next }
    icir_val <- mean(ics)/(stats::sd(ics)+1e-8)*sqrt(12)
    ic_list[[fn_icir]] <- max(0, icir_val)
  }

  total_icir <- sum(unlist(ic_list)) + 1e-8
  fdt_cur <- FDB_ALL[Date==max(vf) & Coverage==TRUE]
  if(nrow(fdt_cur)==0) next
  fw9 <- dcast(fdt_cur, Ticker~Factor_Name, value.var="Z_Score_Aligned")
  liq <- RAWDATA[Date==sig_d, .(Ticker,AvgTV20)]
  fw9 <- merge(fw9, liq, by="Ticker")[!is.na(AvgTV20) & AvgTV20>=LIQ_THRESHOLD]
  if(nrow(fw9)<20) next

  fw9[, Score:=0]
  for(fn in c("M25_Earnings_Mom_Streak","V24_Residual_Income")) {
    w_icir <- ic_list[[fn]] / total_icir
    if(fn %in% names(fw9) && sum(!is.na(fw9[[fn]]))>10) {
      fw9[, paste0("R_",fn):=frank(get(fn),na.last="keep",ties.method="average")/sum(!is.na(get(fn)))]
      fw9[, Score:=Score+w_icir*get(paste0("R_",fn))]
    }
  }
  fw9[, Date:=sig_d]
  fl9[[length(fl9)+1]] <- fw9[!is.na(Score), .(Date,Ticker,Score)]
}
if(length(fl9)>0) {
  F9 <- rbindlist(fl9); setorder(F9,Date,-Score)
  cat(sprintf("  [M9] %d dates\n",length(fl9)))
  r<-run_bt(F9,"M9_ICIR_weighted","output_s5_M9"); if(!is.null(r)) AR[["M9"]]<-r
} else cat("  M9: no data\n")

# -------------------------------------------------------
cat("\n\n=== STR_1519 S5 SUMMARY ===\n")
cat(sprintf("%-6s|%-5s|%-6s|%6s|%7s|%8s|%7s\n","Mut","Cat","Grade","Score","SR","CAGR%","MDD%"))
cats <- c(M1="C",M2="C",M3="C",M4="C",M5="F",M6="F",M7="A",M8="B",M9="E")
for(mn in c("M1","M2","M3","M4","M5","M6","M7","M8","M9")) {
  if(mn %in% names(AR)) {
    r<-AR[[mn]]
    g<-if(!is.null(r$hurdle$grade)) r$hurdle$grade else if(!is.null(r$hurdle$verdict$grade)) r$hurdle$verdict$grade else "?"
    s<-if(!is.null(r$hurdle$total_score)) r$hurdle$total_score else if(!is.null(r$hurdle$score)) r$hurdle$score else 0
    cat(sprintf("%-6s|%-5s|%-6s|%6.1f|%7.3f|%8.2f|%7.1f\n",mn,cats[mn],g,s,r$perf$Sharpe,r$perf$CAGR,r$perf$MDD))
  } else {
    cat(sprintf("%-6s|%-5s|%-6s|%6s|%7s|%8s|%7s\n",mn,cats[mn],"ERR","--","--","--","--"))
  }
}

if("YM" %in% names(RAWDATA)) RAWDATA[,YM:=NULL]
for(col in c("TradingValue","AvgTV20")) if(col %in% names(RAWDATA)) RAWDATA[,(col):=NULL]
rm(FDB_ALL); gc(verbose=FALSE)
cat("\n=== STR_1519 S5 COMPLETE ===\n")
