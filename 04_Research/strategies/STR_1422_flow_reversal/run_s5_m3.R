cat("=== STR_1422 S5-M3: Flow Reversal + DD 8/20 + Tight Buffer ===\n")
## Mutation 3: DD brake (8/20, min_exp=25%) + tighter buffer (keep=40, entry=20)
set.seed(1422); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")

STRATEGY_ID   <- "STR_1422"
STRATEGY_NAME <- "S5_M3_FlowRev_DD8_20_TightBuf"

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA_DIR <- file.path(PROJ_ROOT, "02_Infrastructure")
SCRIPT_DIR <- file.path(PROJ_ROOT, "04_Research/strategies/STR_1422_flow_reversal")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)

# ── Load signal ──
cat("[M3] Loading flow reversal signal...\n")
signal_dt <- as.data.table(read_parquet(file.path(SCRIPT_DIR, "flow_reversal_signal.parquet")))
signal_dt[, Date := as.Date(Date)]
setkey(signal_dt, Date, Ticker)
FACTORS <- signal_dt[, .(Date, Ticker, Score = Z_Score)]

# ── Load RAWDATA + liquidity filter ──
cat("[M3] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose=FALSE)

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align="right"), 1L, type="lag"), by=Ticker]
LIQ_THRESHOLD <- 2e8

liq_snap <- RAWDATA[, .(Date, Ticker, AvgTV20)]
FACTORS <- merge(FACTORS, liq_snap, by=c("Date","Ticker"), all.x=FALSE)
FACTORS <- FACTORS[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD, .(Date, Ticker, Score)]

# ── Base backtest with tighter buffer ──
cat("[M3] Running base backtest (N=30, EW, BZ 40/20 tight)...\n")
sim_base <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 30L, weight_method = "equal", commission = 0.0015,
  buffer_zone = list(keep_n = 40L, entry_n = 20L)
)

raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_ret[is.na(raw_ret)] <- 0
raw_dates <- as.Date(index(sim_base$strategy_xts))
n_f       <- length(raw_ret)

# ── DD Brake 8/20, min_exp=25% (t-1) ──
cat("[M3] Applying DD Brake 8/20...\n")
DD_START <- 0.08; DD_FULL <- 0.20; DD_MIN_EXP <- 0.25
nav_dd   <- cumprod(1 + raw_ret)
dd_pct   <- 1 - nav_dd / cummax(nav_dd)
dd_lag   <- c(0, dd_pct[-n_f])
dd_exp   <- fifelse(dd_lag <= DD_START, 1.0,
              fifelse(dd_lag >= DD_FULL, DD_MIN_EXP,
                pmax(DD_MIN_EXP,
                     1.0 - (dd_lag - DD_START) / (DD_FULL - DD_START) * (1 - DD_MIN_EXP))))
final_ret <- raw_ret * dd_exp

combined_xts <- xts(final_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_base
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+final_ret)*10000, Strategy_Ret=final_ret)

# ── Output ──
output_dir <- file.path(SCRIPT_DIR, "output_s5_m3")
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)

perf    <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  M3: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", perf$Sharpe, perf$CAGR, perf$MDD))
generate_charts(sim, output_dir=output_dir, strategy_name=STRATEGY_NAME)
fwrite(rbind(perf, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(sim_result=sim, FACTORS=FACTORS, strategy_name=STRATEGY_NAME,
                          output_dir=output_dir)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("  Grade: %s Score: %.1f\n", hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0))

tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart("S5_M3_STR_1422", hr, output_dir)
}, error=function(e) cat("[TG]", e$message, "\n"))

cat("=== S5-M3 Complete ===\n")
