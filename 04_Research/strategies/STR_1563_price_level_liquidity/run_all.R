cat("=== STR_1563: Price Level Liquidity ===\n")
## 핵심아이디어: 주가수준 효과 (L27_Price_Level). Hwang & Lu(2007) JFM.
## 저가주 outperformance anomaly — behavioral bias + transaction cost channel.
## S1 순수 팩터. DD/VT/Regime 없음.
## RoleBias: RoleBias_Diversifier (가격 수준은 Core value/quality alpha와 낮은 상관 예상)
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
set.seed(1563)

STRATEGY_NAME   <- "STR_1563_Price_Level_Liquidity"
STRATEGY_ID     <- "STR_1563"
STRATEGY_FAMILY <- "price_level"
QEPM_AUTO_COMMIT <- TRUE

SCRIPT_DIR <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  if (is.null(d) || d == ".") getwd() else d
}, error = function(e) getwd())
INFRA_DIR <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
library(data.table); library(xts); library(arrow)

tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

## Phase 1: RAWDATA 로드 (1회)
cat("[Phase 1] Loading RAWDATA...\n")
LIQ_THRESHOLD <- 2e8
res <- load_rawdata(use_cache = TRUE)
RAWDATA      <- res$RAWDATA
BM_DT        <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res); gc(verbose = FALSE)

## Phase 2: 유동성 사전 계산 (t-1 lag, C9/C10)
cat("[Phase 2] Precomputing liquidity filter (t-1 lag)...\n")
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(
  frollmean(TradingValue, n = 20L, align = "right"),
  n = 1L, type = "lag"
), by = Ticker]

## Phase 3: 월말 시그널 날짜 구성 (월 마지막 거래일)
cat("[Phase 3] Building monthly signal dates (month-end last trading day)...\n")
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_eom <- RAWDATA[, .(SigDate = max(Date)), by = YM][order(YM)]$SigDate

# 워밍업: 252 거래일 이후부터 (L27 Price Level 팩터 최소 축적)
all_dates     <- sort(unique(RAWDATA$Date))
warmup_cut    <- all_dates[min(252L, length(all_dates))]
monthly_dates <- monthly_eom[monthly_eom > warmup_cut]
cat(sprintf("  Signal dates: %d months  (%s ~ %s)\n",
            length(monthly_dates),
            as.character(min(monthly_dates)),
            as.character(max(monthly_dates))))

## Phase 4: L27_Price_Level 로드 — load_month_factors() 경유 (C15)
cat("[Phase 4] Building FACTORS via load_month_factors() (C15 compliant)...\n")
factor_list <- vector("list", length(monthly_dates))

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  # C15: Factor DB는 반드시 load_month_factors() 경유
  fdt <- tryCatch(
    load_month_factors(sig_d, coverage_min = 0.05),
    error = function(e) NULL
  )
  if (is.null(fdt) || nrow(fdt) == 0L) next

  # L27_Price_Level 필터 + Z_Score_Aligned 사용 (C13)
  fdt <- fdt[Factor_Name == "L27_Price_Level" & !is.na(Z_Score_Aligned)]
  if (nrow(fdt) == 0L) next

  # 유동성 필터 (t-1 lag AvgTV20, C10)
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt <- merge(fdt, liq, by = "Ticker", all.x = FALSE)
  fdt <- fdt[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt) < 20L) next

  # Score = rank percentile (higher Z_Score_Aligned = higher expected return)
  n_valid <- nrow(fdt)
  fdt[, Score := frank(Z_Score_Aligned, na.last = "keep",
                        ties.method = "average") / n_valid]
  fdt[, Date := sig_d]

  factor_list[[i]] <- fdt[, .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(factor_list, use.names = TRUE, fill = TRUE)
setorder(FACTORS, Date, -Score)
cat(sprintf("  FACTORS: %s rows | %d valid dates\n",
            format(nrow(FACTORS), big.mark = ","),
            length(unique(FACTORS$Date))))

stopifnot(
  is.data.table(FACTORS),
  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
  nrow(FACTORS) > 0
)

# 임시 컬럼 정리
RAWDATA[, c("YM", "TradingValue", "AvgTV20") := NULL]

## Phase 5: 백테스트
cat("[Phase 5] Running backtest (N=30, EW, 15bps, BZ=50/25)...\n")
RAWDATA <- copy(RAWDATA_ORIG)
sim <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 30L,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 50L, entry_n = 25L)
)

## Phase 6: 출력 + 허들 게이트
cat("[Phase 6] Output & Hurdle Gate...\n")
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

perf_strat <- summarise_perf(sim$strategy_xts, STRATEGY_ID)
perf_bm    <- summarise_perf(sim$bm_xts,       "BM")
cat(sprintf("  SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
            perf_strat$Sharpe, perf_strat$CAGR, perf_strat$MDD))

generate_charts(sim, output_dir = output_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))
saveRDS(sim, file.path(output_dir, "sim_result.rds"))
saveRDS(sim, file.path(SCRIPT_DIR,  "sim_result.rds"))

# strategy_analyzer (선택)
RAWDATA <- copy(RAWDATA_ORIG)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN analyzer]", e$message, "\n"))

# Hurdle Gate
source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(
  sim_result    = sim,
  FACTORS       = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = file.path(SCRIPT_DIR, "factor_engine.R"),
  output_dir    = output_dir
)
jsonlite::write_json(hurdle, file.path(output_dir, "hurdle_result.json"),
                     auto_unbox = TRUE, pretty = TRUE)

score_val <- hurdle$total_score %||% hurdle$score %||% 0
cat(sprintf("  Grade: %s | Score: %.1f\n", hurdle$grade, score_val))

# 텔레그램 발송
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
  hr <- jsonlite::fromJSON(file.path(output_dir, "hurdle_result.json"))
  tg_strategy_result_with_chart(STRATEGY_ID, hr, output_dir)
}, error = function(e) cat("[TG]", e$message, "\n"))

# QEPM auto-commit
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qh)) {
      source(qh)
      if (exists("hybrid_commit"))
        hybrid_commit(strategy_name = STRATEGY_ID, family = STRATEGY_FAMILY,
                      hurdle_result = hurdle, artifact_paths = list(output_dir))
    }
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

gc(verbose = FALSE)
cat(sprintf("\n=== STR_1563 Complete. Grade=%s Score=%.1f SR=%.3f CAGR=%.2f%% MDD=%.1f%% ===\n",
            hurdle$grade, score_val, perf_strat$Sharpe, perf_strat$CAGR, perf_strat$MDD))
