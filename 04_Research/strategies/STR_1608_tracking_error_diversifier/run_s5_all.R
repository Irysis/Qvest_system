cat("=== STR_1608 S5: Tracking_Error_Diversifier 9 Mutations ===\n")
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); set.seed(1608)
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

NEEDED <- c("D22_Tracking_Error","V14_EBIT_EV","C19_Composite_Earnings","D58_Vol_Asymmetry","Q01_GPA")
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
ds <- open_dataset(file.path(PROJECT_ROOT, ".cache", "factor_db"), format="parquet")
FDB_ALL <- ds |> filter(Factor_Name %in% NEEDED) |> collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
rm(ds); gc(verbose=FALSE)
cat(sprintf("  FDB loaded: %s rows\n", format(nrow(FDB_ALL), big.mark=",")))

LIQ_THRESHOLD <- 2e8
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD=max(Date)), by=YM]$SD)
monthly_dates <- monthly_dates[monthly_dates >= as.Date("2005-07-01")]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align="right"), 1L, type="lag"), by=Ticker]
fdb_dates <- sort(unique(FDB_ALL$Date))

sim_parent <- readRDS(file.path(SCRIPT_DIR, "sim_result.rds"))

build_factors <- function(factors, label) {
  fl <- vector("list", length(monthly_dates)); nd <- 0L
  for (i in seq_along(monthly_dates)) {
    sig_d <- as.Date(monthly_dates[i])
    vf <- fdb_dates[fdb_dates <= sig_d]; if (length(vf) == 0) next
    fdt <- FDB_ALL[Date == max(vf) & Factor_Name %in% factors]
    if (nrow(fdt) == 0) next
    fw <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20, Sector)]
    fw <- merge(fw, liq, by="Ticker")[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
    if (nrow(fw) < 30) next
    fcols <- intersect(factors, names(fw)); if (length(fcols) == 0) next
    fw[, Score := rowMeans(.SD, na.rm=TRUE), .SDcols=fcols]
    fw <- fw[!is.na(Score)]
    fw[, Score := Score - mean(Score, na.rm=TRUE), by=Sector]
    fw[, Date := sig_d]
    fl[[i]] <- fw[!is.na(Score), .(Date, Ticker, Score)]; nd <- nd + 1L
  }
  F <- rbindlist(fl[!sapply(fl, is.null)]); setorder(F, Date, -Score)
  cat(sprintf("  [%s] %d dates\n", label, nd)); F
}

run_bt <- function(FACTORS, name, dir_name) {
  RD <- copy(RAWDATA_ORIG)
  sim <- tryCatch(run_monthly_simulation(RAWDATA=RD, BM_DT=BM_DT, FACTORS=FACTORS, n_holdings=30L,
    weight_method="equal", commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L)),
    error=function(e) { cat("ERR:", e$message, "\n"); NULL })
  if (is.null(sim)) return(NULL)
  od <- file.path(SCRIPT_DIR, dir_name); dir.create(od, showWarnings=FALSE, recursive=TRUE)
  p <- summarise_perf(sim$strategy_xts, name)
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", name, p$Sharpe, p$CAGR, p$MDD))
  generate_charts(sim, output_dir=od, strategy_name=name)
  fwrite(rbind(p, summarise_perf(sim$bm_xts, "BM")), file.path(od, "performance.csv"))
  saveRDS(sim, file.path(od, "sim_result.rds"))
  source(file.path(INFRA_DIR, "hurdle_gate.R"))
  h <- run_hurdle_gate(sim_result=sim, strategy_name=name, output_dir=od)
  jsonlite::write_json(h, file.path(od, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
  cat(sprintf("  %s: Grade=%s Score=%.1f\n", name, h$grade, h$total_score %||% h$score %||% 0))
  list(perf=p, hurdle=h, sim=sim)
}

AR <- list()

cat("\n--- M1: D22+V14 ---\n")
r <- run_bt(build_factors(c("D22_Tracking_Error","V14_EBIT_EV"),"M1"), "M1_D22_V14", "output_s5_M1")
if (!is.null(r)) AR[["M1"]] <- r

cat("\n--- M2: D22+C19 ---\n")
r <- run_bt(build_factors(c("D22_Tracking_Error","C19_Composite_Earnings"),"M2"), "M2_D22_C19", "output_s5_M2")
if (!is.null(r)) AR[["M2"]] <- r

cat("\n--- M3: D22+D58 ---\n")
r <- run_bt(build_factors(c("D22_Tracking_Error","D58_Vol_Asymmetry"),"M3"), "M3_D22_D58", "output_s5_M3")
if (!is.null(r)) AR[["M3"]] <- r

cat("\n--- M4: D22+Q01 ---\n")
r <- run_bt(build_factors(c("D22_Tracking_Error","Q01_GPA"),"M4"), "M4_D22_Q01", "output_s5_M4")
if (!is.null(r)) AR[["M4"]] <- r

cat("\n--- M5: D22 sector-neutral ---\n")
r <- run_bt(build_factors(c("D22_Tracking_Error"),"M5"), "M5_D22_SectorNeutral", "output_s5_M5")
if (!is.null(r)) AR[["M5"]] <- r

cat("\n--- M6: D22+V14 quarterly rebalance ---\n")
F6_base <- build_factors(c("D22_Tracking_Error","V14_EBIT_EV"), "M6_quarterly")
q_months <- c(3,6,9,12)
F6_q <- F6_base[as.integer(format(Date, "%m")) %in% q_months]
all_m <- sort(unique(F6_base$Date))
F6_ff <- rbindlist(lapply(all_m, function(d) {
  prev <- F6_q[Date <= d]; if (nrow(prev) == 0) return(NULL)
  rows <- prev[Date == max(prev$Date)]; rows[, Date := d]; rows
}))
if (nrow(F6_ff) > 0) {
  r <- run_bt(F6_ff, "M6_Quarterly", "output_s5_M6"); if (!is.null(r)) AR[["M6"]] <- r
}

# M7: Best + IVol
cat("\n--- M7: Best IVol weighted ---\n")
best_sr <- -Inf; best_nm <- "M1"
for (mn in c("M1","M2","M3","M4")) if (mn %in% names(AR) && AR[[mn]]$perf$Sharpe > best_sr) { best_sr <- AR[[mn]]$perf$Sharpe; best_nm <- mn }
cat(sprintf("  Best: %s (SR=%.3f)\n", best_nm, best_sr))
best_rds <- file.path(SCRIPT_DIR, paste0("output_s5_", best_nm), "sim_result.rds")
best_factors_map <- list(M1=c("D22_Tracking_Error","V14_EBIT_EV"), M2=c("D22_Tracking_Error","C19_Composite_Earnings"),
  M3=c("D22_Tracking_Error","D58_Vol_Asymmetry"), M4=c("D22_Tracking_Error","Q01_GPA"))
if (file.exists(best_rds)) {
  F7 <- build_factors(best_factors_map[[best_nm]], "M7_base")
  RD7 <- copy(RAWDATA_ORIG)
  sim7 <- tryCatch(run_monthly_simulation(RAWDATA=RD7, BM_DT=BM_DT, FACTORS=F7, n_holdings=30L,
    weight_method="ivol", commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L)),
    error=function(e) { cat("M7 ivol ERR:", e$message, "\n"); NULL })
  if (!is.null(sim7)) {
    od7 <- file.path(SCRIPT_DIR,"output_s5_M7"); dir.create(od7, showWarnings=FALSE, recursive=TRUE)
    p7 <- summarise_perf(sim7$strategy_xts, "M7_IVol")
    cat(sprintf("  M7: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", p7$Sharpe, p7$CAGR, p7$MDD))
    generate_charts(sim7, output_dir=od7, strategy_name="M7_IVol")
    fwrite(rbind(p7, summarise_perf(sim7$bm_xts,"BM")), file.path(od7,"performance.csv"))
    saveRDS(sim7, file.path(od7,"sim_result.rds"))
    source(file.path(INFRA_DIR,"hurdle_gate.R"))
    h7 <- run_hurdle_gate(sim_result=sim7, strategy_name="M7_IVol", output_dir=od7)
    jsonlite::write_json(h7, file.path(od7,"hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
    AR[["M7"]] <- list(perf=p7, hurdle=h7)
  }
}

# M8: Best + DD 6/20
cat("\n--- M8: Best + DD 6/20 ---\n")
if (file.exists(best_rds)) {
  bsim <- readRDS(best_rds)
  brr <- as.numeric(bsim$strategy_xts); brr[is.na(brr)] <- 0; bnf <- length(brr)
  bnav <- cumprod(1+brr); bdd <- 1-bnav/cummax(bnav)
  bddl <- c(0, bdd[-bnf])
  bde <- fifelse(bddl <= 0.06, 1, fifelse(bddl >= 0.20, 0, pmax(0, 1-(bddl-0.06)/(0.20-0.06))))
  cx8 <- xts(brr*bde, order.by=as.Date(index(bsim$strategy_xts))); names(cx8) <- "Strategy"
  sim8 <- bsim; sim8$strategy_xts <- cx8
  od8 <- file.path(SCRIPT_DIR,"output_s5_M8"); dir.create(od8, showWarnings=FALSE, recursive=TRUE)
  p8 <- summarise_perf(cx8, "M8_DD6_20")
  cat(sprintf("  M8: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", p8$Sharpe, p8$CAGR, p8$MDD))
  generate_charts(sim8, output_dir=od8, strategy_name="M8_DD6_20")
  fwrite(rbind(p8, summarise_perf(sim8$bm_xts,"BM")), file.path(od8,"performance.csv"))
  saveRDS(sim8, file.path(od8,"sim_result.rds"))
  source(file.path(INFRA_DIR,"hurdle_gate.R"))
  h8 <- run_hurdle_gate(sim_result=sim8, strategy_name="M8_DD6_20", output_dir=od8)
  jsonlite::write_json(h8, file.path(od8,"hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
  cat(sprintf("  M8: Grade=%s Score=%.1f\n", h8$grade, h8$total_score %||% h8$score %||% 0))
  AR[["M8"]] <- list(perf=p8, hurdle=h8)
}

# M9: Best + DD 6/20 + Regime
cat("\n--- M9: Best + DD 6/20 + Regime ---\n")
tryCatch({
  source(file.path(REGIME_DIR, "regime_signal.R")); sdt <- load_regime_signal()
  if (file.exists(best_rds)) {
    bsim9 <- readRDS(best_rds)
    brr9 <- as.numeric(bsim9$strategy_xts); brr9[is.na(brr9)] <- 0; bnf9 <- length(brr9)
    bnav9 <- cumprod(1+brr9); bddl9 <- c(0, (1-bnav9/cummax(bnav9))[-bnf9])
    bde9 <- fifelse(bddl9 <= 0.06, 1, fifelse(bddl9 >= 0.20, 0, pmax(0, 1-(bddl9-0.06)/(0.20-0.06))))
    brd9 <- as.Date(index(bsim9$strategy_xts))
    bcp9 <- sapply(seq_len(bnf9), function(j) { row <- sdt[Date <= brd9[j]]; if (nrow(row)>0) tail(row$Cash_Pct,1) else 0 })
    bcl9 <- c(0, bcp9[-bnf9]); bre9 <- 1-bcl9
    cx9 <- xts(brr9*bde9*bre9, order.by=brd9); names(cx9) <- "Strategy"
    sim9 <- bsim9; sim9$strategy_xts <- cx9
    od9 <- file.path(SCRIPT_DIR,"output_s5_M9"); dir.create(od9, showWarnings=FALSE, recursive=TRUE)
    p9 <- summarise_perf(cx9, "M9_DD_Regime")
    cat(sprintf("  M9: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", p9$Sharpe, p9$CAGR, p9$MDD))
    generate_charts(sim9, output_dir=od9, strategy_name="M9_DD_Regime")
    fwrite(rbind(p9, summarise_perf(sim9$bm_xts,"BM")), file.path(od9,"performance.csv"))
    saveRDS(sim9, file.path(od9,"sim_result.rds"))
    source(file.path(INFRA_DIR,"hurdle_gate.R"))
    h9 <- run_hurdle_gate(sim_result=sim9, strategy_name="M9_DD_Regime", output_dir=od9)
    jsonlite::write_json(h9, file.path(od9,"hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
    cat(sprintf("  M9: Grade=%s Score=%.1f\n", h9$grade, h9$total_score %||% h9$score %||% 0))
    AR[["M9"]] <- list(perf=p9, hurdle=h9)
  }
}, error=function(e) cat("M9 ERR:", e$message, "\n"))

cat("\n\n=== STR_1608 S5 SUMMARY ===\n")
cat(sprintf("%-6s|%-6s|%7s|%8s|%7s\n","Mut","Grade","SR","CAGR%","MDD%"))
for (mn in paste0("M", 1:9)) {
  if (mn %in% names(AR)) {
    r <- AR[[mn]]; g <- r$hurdle$grade %||% r$hurdle$verdict$grade %||% "?"
    cat(sprintf("%-6s|%-6s|%7.3f|%8.2f|%7.1f\n", mn, g, r$perf$Sharpe, r$perf$CAGR, r$perf$MDD))
  }
}

tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  best_m <- names(which.max(sapply(AR, function(x) x$perf$Sharpe)))
  if (!is.null(best_m)) {
    best_od <- file.path(SCRIPT_DIR, paste0("output_s5_", best_m))
    hr <- jsonlite::fromJSON(file.path(best_od, "hurdle_result.json"))
    tg_strategy_result_with_chart(paste0("STR_1608_S5_", best_m), hr, best_od)
  }
}, error=function(e) cat("[TG]", e$message, "\n"))

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue","AvgTV20")) if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(FDB_ALL); gc(verbose=FALSE)
cat("\n=== STR_1608 S5 COMPLETE ===\n")
