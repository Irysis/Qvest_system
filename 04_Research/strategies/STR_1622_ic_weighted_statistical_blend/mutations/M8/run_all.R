cat("=== STR_1622_M8: 5F IC-Weighted + DD Brake 6/20 (C9 t-1 lag) ===\n")
## M8: 기존 5팩터 IC-weighted 구조 유지 + DD Brake 오버레이 추가
## Harvey et al. 2016 + Moreira & Muir 2017
set.seed(1622); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")

PROJ_ROOT  <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR  <- file.path(PROJ_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJ_ROOT, ".cache")
STR_DIR    <- file.path(PROJ_ROOT, "04_Research/strategies/STR_1622_ic_weighted_statistical_blend")
MUT_DIR    <- file.path(STR_DIR, "mutations/M8")
OUTPUT_DIR <- file.path(MUT_DIR, "output")
dir.create(OUTPUT_DIR, recursive=TRUE, showWarnings=FALSE)

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
suppressPackageStartupMessages(library(data.table))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(arrow))
suppressPackageStartupMessages(library(xts))

# ─── Data Load ───────────────────────────────────────────────────────────────
res <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose=FALSE)

# ─── Factor DB ───────────────────────────────────────────────────────────────
LIQ_THRESHOLD  <- 2e8
N_FACTORS      <- 5L
N_FACTORS_EW   <- 1.0 / N_FACTORS
FLOOR_W        <- 0.05
CAP_W          <- 0.40
IC_WINDOW      <- 12L
LAMBDA         <- 0.5
NEEDED_FACTORS <- c("C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA",
                    "D01_IdioVol", "M25_Earnings_Mom_Streak")

pq_files <- list.files(file.path(CACHE_DIR, "factor_db"), pattern="\\.parquet$", full.names=TRUE)
ds <- open_dataset(pq_files, format="parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
FDB_ALL[, Usable_Date := Date]
setnames(FDB_ALL, "Z_Score", "Z_Score_Aligned")  # C13
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows\n", nrow(FDB_ALL)))

# ─── Monthly Dates ────────────────────────────────────────────────────────────
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by=YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n=20L, align="right"), n=1L, type="lag"), by=Ticker]
RAWDATA[, FwdRet := shift(Ret, n=-1L, type="lead"), by=Ticker]

fdb_dates   <- sort(unique(FDB_ALL$Date))
factor_list <- vector("list", length(monthly_dates))
ic_history  <- list()
n_done <- 0L; n_skipped <- 0L

# ─── Factor Engine Loop ───────────────────────────────────────────────────────
for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdb_d <- max(valid_fdb)
  fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE & Usable_Date <= sig_d]
  if (nrow(fdt) == 0L) fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20, FwdRet)]
  fdt_wide <- merge(fdt_wide, liq, by="Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  ic_current <- setNames(rep(NA_real_, N_FACTORS), NEEDED_FACTORS)
  for (fn in NEEDED_FACTORS) {
    if (fn %in% names(fdt_wide)) {
      vals <- fdt_wide[[fn]]; fwd <- fdt_wide$FwdRet
      mask <- !is.na(vals) & !is.na(fwd)
      if (sum(mask) >= 20L)
        ic_current[fn] <- cor(rank(vals[mask]), rank(fwd[mask]), method="spearman")
    }
  }
  ic_history[[as.character(sig_d)]] <- ic_current
  past_dates <- names(ic_history)[as.Date(names(ic_history)) < sig_d]

  if (length(past_dates) == 0L) {
    weights <- setNames(rep(N_FACTORS_EW, N_FACTORS), NEEDED_FACTORS)
  } else {
    window_dates <- tail(past_dates, IC_WINDOW)
    ic_mat  <- do.call(rbind, lapply(window_dates, function(d) ic_history[[d]]))
    ic_mean <- colMeans(ic_mat, na.rm=TRUE)
    ic_abs  <- abs(ic_mean); ic_abs[is.na(ic_abs)] <- 0
    ic_sum  <- sum(ic_abs)
    ic_norm <- if (ic_sum > 0) ic_abs / ic_sum else rep(N_FACTORS_EW, N_FACTORS)
    weights_raw <- LAMBDA * ic_norm + (1 - LAMBDA) * N_FACTORS_EW
    weights_raw <- pmax(weights_raw, FLOOR_W); weights_raw <- pmin(weights_raw, CAP_W)
    weights <- weights_raw / sum(weights_raw); names(weights) <- NEEDED_FACTORS
  }

  fdt_wide[, Score := 0.0]; total_w <- 0
  for (fn in NEEDED_FACTORS) {
    w <- weights[fn]
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last="keep", ties.method="average") /
             sum(!is.na(fdt_wide[[fn]]))
      fdt_wide[, Score := Score + w * rnk]; total_w <- total_w + w
    }
  }
  if (total_w == 0) { n_skipped <- n_skipped + 1L; next }
  fdt_wide[, Score := Score / total_w]
  fdt_wide[, Date := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark=","), n_done, n_skipped))
for (col in c("YM", "FwdRet", "TradingValue", "AvgTV20"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(FDB_ALL, ic_history); gc(verbose=FALSE)

# ─── Base Simulation ─────────────────────────────────────────────────────────
cat("\n[Phase 1] Base sim for DD Brake reference...\n")
RAWDATA_ORIG <- copy(RAWDATA)
sim_base <- run_monthly_simulation(
  RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FACTORS,
  n_holdings=30L, weight_method="equal", commission=0.0015,
  buffer_zone=list(keep_n=50L, entry_n=25L)
)

# ─── DD Brake 6/20 (C9) ──────────────────────────────────────────────────────
cat("\n[Phase 2] DD Brake 6/20 (C9 t-1 lag)...\n")
raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_dates <- as.Date(index(sim_base$strategy_xts))
n         <- length(raw_ret)
nav_cum   <- cumprod(1 + raw_ret)
dd_pct    <- 1 - nav_cum / cummax(nav_cum)
dd_lag    <- c(0, dd_pct[-n])  # C9 패턴

position_size <- ifelse(dd_lag > 0.20, 0.50, 1.0)
cat(sprintf("  DD Brake active: %.1f%% of days (mean exposure=%.3f)\n",
            mean(position_size < 1.0) * 100, mean(position_size)))
final_ret <- raw_ret * position_size
sim_final <- sim_base
sim_final$strategy_xts <- xts(final_ret, order.by=raw_dates)
names(sim_final$strategy_xts) <- "Strategy"

# ─── Performance + Hurdle ────────────────────────────────────────────────────
cat("\n[Phase 3] Performance + Hurdle...\n")
RAWDATA <- copy(RAWDATA_ORIG)
perf <- summarise_perf(sim_final$strategy_xts, "STR_1622_M8")
cat(sprintf("  M8: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n", perf$CAGR, perf$Sharpe, perf$MDD))
generate_charts(sim_final, output_dir=OUTPUT_DIR, strategy_name="STR_1622_M8")
fwrite(rbind(perf, summarise_perf(sim_final$bm_xts, "BM")),
       file.path(OUTPUT_DIR, "performance.csv"))
saveRDS(sim_final, file.path(OUTPUT_DIR, "sim_result.rds"))
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim_final, FACTORS=FACTORS,
                          strategy_name="STR_1622_M8",
                          strategy_file=file.path(STR_DIR, "factor_engine.R"),
                          output_dir=OUTPUT_DIR)
jsonlite::write_json(hurdle, file.path(OUTPUT_DIR, "hurdle_result.json"),
                     auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("\n[STR_1622_M8] Grade=%s | Score=%s | SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%\n",
    hurdle$grade %||% "?", hurdle$total_score %||% hurdle$score %||% 0,
    hurdle$metrics$sharpe_ratio %||% perf$Sharpe,
    (hurdle$metrics$cagr %||% perf$CAGR/100) * 100,
    (hurdle$metrics$max_drawdown %||% perf$MDD/100) * 100))
cat("=== M8 Complete ===\n")
