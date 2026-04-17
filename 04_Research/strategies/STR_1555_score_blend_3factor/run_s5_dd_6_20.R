cat("=== STR_1555 S5 Mutation: DD 6/20 Tightening (RP + Regime v7.1) ===\n")
## S5 mutation: DD_START 8→6, DD_FULL 22→20. RP weighting + Regime v7.1 유지. MDD 25% 목표.
## Parent: fixed_rp_dd_regime SR=1.080 CAGR=16.09 MDD=29.8
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); set.seed(1555)
SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error=function(e) getwd())
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R")))
  INFRA_DIR <- file.path("/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot", "02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow); library(dplyr)

MUTATION_NAME <- "STR_1555_DD6_20_RP"
DD_START <- 0.06   # tightened from 0.08
DD_FULL  <- 0.20   # tightened from 0.22
DD_FLOOR <- 0.30   # exposure floor at full brake

cat(sprintf("[Config] DD_START=%.0f%% DD_FULL=%.0f%% Floor=%.0f%%\n",
            DD_START*100, DD_FULL*100, DD_FLOOR*100))

# --- Data Load ---
res <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose=FALSE)

# --- Factor DB: C19(60%) + V14(20%) + D01(20%) ---
NEEDED <- c("C19_Composite_Earnings", "V14_EBIT_EV", "D01_IdioVol")
WEIGHTS <- c(C19_Composite_Earnings=0.60, V14_EBIT_EV=0.20, D01_IdioVol=0.20)
ds <- open_dataset(file.path(CACHE_DIR, "factor_db"), format="parquet")
FDB_ALL <- ds |> filter(Factor_Name %in% NEEDED) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |> collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows\n", nrow(FDB_ALL)))

LIQ_THRESHOLD <- 2e8
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD=max(Date)), by=YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n=20L, align="right"), n=1L, type="lag"), by=Ticker]
fdb_dates <- sort(unique(FDB_ALL$Date))

# --- Build Factors (60/20/20 score blend) ---
cat("\n[Phase 1] Building factors (60/20/20)...\n")
factor_list <- vector("list", length(monthly_dates)); n_done <- 0L
for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  vf <- fdb_dates[fdb_dates <= sig_d]
  if (length(vf) == 0L) next
  fdt <- FDB_ALL[Date == max(vf) & Coverage == TRUE]
  if (nrow(fdt) == 0L) next
  fw <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fw <- merge(fw, liq, by="Ticker")[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fw) < 20L) next
  fw[, Score := 0.0]; tw <- 0
  for (fn in NEEDED) {
    w <- WEIGHTS[fn]
    if (fn %in% names(fw) && sum(!is.na(fw[[fn]])) > 10L) {
      fw[, paste0("R_",fn) := frank(get(fn), na.last="keep", ties.method="average") /
                                   sum(!is.na(get(fn)))]
      fw[, Score := Score + w * get(paste0("R_",fn))]; tw <- tw + w
    }
  }
  if (tw == 0) next
  fw[, Score := Score / tw]; fw[, Date := sig_d]
  factor_list[[i]] <- fw[!is.na(Score), .(Date, Ticker, Score)]; n_done <- n_done + 1L
}
FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)
cat(sprintf("  FACTORS: %s rows | %d dates\n", format(nrow(FACTORS), big.mark=","), n_done))

# --- Phase 2: Backtest with Risk Parity stock weighting ---
cat("\n[Phase 2] Backtest with Risk Parity stock weighting...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim_rp <- tryCatch(
  run_monthly_simulation(RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FACTORS, n_holdings=30L,
    weight_method="riskparity", commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L)),
  error=function(e) {
    cat("[WARN] riskparity failed:", e$message, "— fallback to equal\n")
    RAWDATA <- copy(RAWDATA_ORIG)
    run_monthly_simulation(RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FACTORS, n_holdings=30L,
      weight_method="equal", commission=0.0015, buffer_zone=list(keep_n=50L, entry_n=25L))
  }
)
p_rp <- summarise_perf(sim_rp$strategy_xts, "RP_pure")
cat(sprintf("  RP pure: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", p_rp$Sharpe, p_rp$CAGR, p_rp$MDD))

# --- Phase 3: DD 6/20 brake (C9: t-1 lag) ---
cat("\n[Phase 3] DD 6/20 tightening overlay...\n")
rr <- as.numeric(sim_rp$strategy_xts); rr[is.na(rr)] <- 0; nf <- length(rr)
nav <- cumprod(1 + rr); dd_cur <- 1 - nav / cummax(nav)
# C9: DD lag = t-1 (dd_pct[-n] prepended with 0)
dd_lag <- c(0, dd_cur[-nf])
dd_exp <- fifelse(dd_lag <= DD_START, 1.0,
          fifelse(dd_lag >= DD_FULL,  DD_FLOOR,
                  pmax(DD_FLOOR, 1.0 - (dd_lag - DD_START) / (DD_FULL - DD_START) * (1.0 - DD_FLOOR))))

# --- Phase 4: Regime v7.1 overlay (C5: t-1 lag) ---
cat("\n[Phase 4] Regime v7.1 overlay...\n")
re_exp <- rep(1.0, nf)
tryCatch({
  source(file.path(REGIME_DIR, "regime_signal.R"))
  sdt <- load_regime_signal()
  rd <- as.Date(index(sim_rp$strategy_xts))
  cash_pct <- numeric(nf)
  for (j in seq_len(nf)) {
    row <- sdt[Date <= rd[j]]
    if (nrow(row) > 0) cash_pct[j] <- tail(row$Cash_Pct, 1) else cash_pct[j] <- 0
  }
  # C5: regime signal t-1 lag
  cash_lag <- c(0, cash_pct[-nf])
  re_exp <- 1 - cash_lag
  cat(sprintf("  Regime: avg cash=%.1f%% | avg re_exp=%.3f\n",
              mean(cash_lag)*100, mean(re_exp)))
}, error=function(e) cat("  [WARN] Regime load failed:", e$message, "\n"))

# --- Combine: DD × Regime ---
combined_exp <- dd_exp * re_exp
final_ret <- rr * combined_exp
cx_final <- xts(final_ret, order.by=as.Date(index(sim_rp$strategy_xts)))
names(cx_final) <- "Strategy"

sim_out <- sim_rp; sim_out$strategy_xts <- cx_final
p_out <- summarise_perf(cx_final, MUTATION_NAME)
cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
            MUTATION_NAME, p_out$Sharpe, p_out$CAGR, p_out$MDD))

# --- Save output ---
od <- file.path(SCRIPT_DIR, "output_s5_dd_6_20")
dir.create(od, showWarnings=FALSE, recursive=TRUE)
generate_charts(sim_out, output_dir=od, strategy_name=MUTATION_NAME)
fwrite(rbind(p_out, summarise_perf(sim_out$bm_xts, "BM")), file.path(od, "performance.csv"))
saveRDS(sim_out, file.path(od, "sim_result.rds"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim_out, FACTORS=FACTORS, strategy_name=MUTATION_NAME, output_dir=od)
jsonlite::write_json(hurdle, file.path(od, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))

tryCatch({ source(file.path(TELEGRAM_DIR, "telegram_notify.R")); hr <- jsonlite::fromJSON(file.path(od, "hurdle_result.json")); tg_strategy_result_with_chart(paste0("STR_1555 DD6/20"), hr, od) }, error=function(e) cat("[TG]", e$message, "\n"))

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(FDB_ALL); gc(verbose=FALSE)

cat(sprintf("\n=== STR_1555 DD6/20 Mutation Complete. Grade=%s Score=%.1f SR=%.3f CAGR=%.2f MDD=%.1f ===\n",
            hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0,
            p_out$Sharpe, p_out$CAGR, p_out$MDD))
