cat("=== STR_1422 S5-M2: Flow Reversal + VT15 + DD 5/15 ===\n")
## Mutation 2: VT target 15% + aggressive DD brake (5/15, min_exp=35%)
set.seed(1422); options(scipen=999); Sys.setenv(TZ="Asia/Seoul")

STRATEGY_ID   <- "STR_1422"
STRATEGY_NAME <- "S5_M2_FlowRev_VT15_DD5_15"

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA_DIR <- file.path(PROJ_ROOT, "02_Infrastructure")
SCRIPT_DIR <- file.path(PROJ_ROOT, "04_Research/strategies/STR_1422_flow_reversal")
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table); library(xts); library(arrow)

# ── Load signal ──
cat("[M2] Loading flow reversal signal...\n")
signal_dt <- as.data.table(read_parquet(file.path(SCRIPT_DIR, "flow_reversal_signal.parquet")))
signal_dt[, Date := as.Date(Date)]
setkey(signal_dt, Date, Ticker)
FACTORS <- signal_dt[, .(Date, Ticker, Score = Z_Score)]

# ── Load RAWDATA + liquidity filter ──
cat("[M2] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose=FALSE)

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align="right"), 1L, type="lag"), by=Ticker]
LIQ_THRESHOLD <- 2e8

liq_snap <- RAWDATA[, .(Date, Ticker, AvgTV20)]
FACTORS <- merge(FACTORS, liq_snap, by=c("Date","Ticker"), all.x=FALSE)
FACTORS <- FACTORS[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD, .(Date, Ticker, Score)]

# ── Base backtest ──
cat("[M2] Running base backtest (N=30, EW, BZ 50/25)...\n")
sim_base <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 30L, weight_method = "equal", commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L)
)

raw_ret   <- as.numeric(sim_base$strategy_xts)
raw_ret[is.na(raw_ret)] <- 0
raw_dates <- as.Date(index(sim_base$strategy_xts))
n_f       <- length(raw_ret)

# ── VT 15% (expanding, t-1) ──
cat("[M2] Applying VT 15%...\n")
VT_TARGET <- 0.15
expanding_vol <- numeric(n_f)
for (i in 2:n_f) {
  vol_i <- sd(raw_ret[1:(i-1)]) * sqrt(252)
  expanding_vol[i] <- if (is.na(vol_i) || vol_i < 1e-8) VT_TARGET else vol_i
}
expanding_vol[1] <- VT_TARGET
vt_scalar <- fifelse(expanding_vol > 0, VT_TARGET / expanding_vol, 1.0)
vt_scalar <- pmin(pmax(vt_scalar, 0.3), 1.5)
vt_lagged <- c(1.0, head(vt_scalar, -1))
after_vt  <- raw_ret * vt_lagged

# ── DD Brake 5/15, min_exp=35% (t-1) ──
cat("[M2] Applying DD Brake 5/15...\n")
DD_START <- 0.05; DD_FULL <- 0.15; DD_MIN_EXP <- 0.35
nav_dd <- cumprod(1 + after_vt)
dd_pct <- 1 - nav_dd / cummax(nav_dd)
dd_lag <- c(0, dd_pct[-n_f])
dd_exp <- fifelse(dd_lag <= DD_START, 1.0,
            fifelse(dd_lag >= DD_FULL, DD_MIN_EXP,
              pmax(DD_MIN_EXP,
                   1.0 - (dd_lag - DD_START) / (DD_FULL - DD_START) * (1 - DD_MIN_EXP))))
final_ret <- after_vt * dd_exp

combined_xts <- xts(final_ret, order.by=raw_dates); names(combined_xts) <- "Strategy"
sim <- sim_base
sim$strategy_xts <- combined_xts
sim$bm_xts <- sim_base$bm_xts[raw_dates]
sim$DAILY_NAV_DT <- data.table(Date=raw_dates, NAV=cumprod(1+final_ret)*10000, Strategy_Ret=final_ret)

# ── Output ──
output_dir <- file.path(SCRIPT_DIR, "output_s5_m2")
dir.create(output_dir, showWarnings=FALSE, recursive=TRUE)

perf    <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  M2: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n", perf$Sharpe, perf$CAGR, perf$MDD))
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
  tg_strategy_result_with_chart("S5_M2_STR_1422", hr, output_dir)
}, error=function(e) cat("[TG]", e$message, "\n"))

cat("=== S5-M2 Complete ===\n")
