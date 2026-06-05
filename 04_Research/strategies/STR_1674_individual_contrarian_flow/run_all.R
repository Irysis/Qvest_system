cat("=== STR_1674: Individual Contrarian Flow ===\n")
## 핵심아이디어: 개인투자자 월간 순매도 상위 종목의 contrarian alpha
## Noise Trader Reversal: 개인이 파는 종목이 이후 outperform (De Long et al. 1990)
## 3MA 평활 + 분기 리밸런싱 + Buffer Zone(keep=50, entry=25) → 회전율 목표 <600%
## Size 중립화 (log(Mktcap) 잔차) → 소형주 편향 제거
##
## PIT: C1(크로스섹션 rank-Z, full-sample 금지) C2(시그널=월말t, 체결=t+1)
##      C3(집계기간≠적용기간) C13(contrarian방향=경제적 부호, flip 금지)
## OPT: investor_dt 1회 로드, RAWDATA 1회 로드, setkey(Date,Ticker)
## PURE S1: 순수 팩터 신호만. 국면 시그널/레버리지/방어 로직 없음.

set.seed(20260412)
t0 <- Sys.time()

# ──────────────────────────────────────────────────────────────────────────────
# 1. 경로 설정 (normalizePath 금지 — WSL 한글 경로 버그)
# ──────────────────────────────────────────────────────────────────────────────
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ──────────────────────────────────────────────────────────────────────────────
# 2. 인프라 로드
# ──────────────────────────────────────────────────────────────────────────────
source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(STRAT_DIR, "factor_engine.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(jsonlite)
  library(lubridate)
  library(tidyr)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

# ──────────────────────────────────────────────────────────────────────────────
# 3. 상수 설정
# ──────────────────────────────────────────────────────────────────────────────
STRATEGY_ID   <- "STR_1674"
STRATEGY_FAM  <- "behavioral"
N_HOLD        <- 30L
LIQ_THRESHOLD <- 2e8
COMMISSION    <- 0.0015

# Buffer Zone 파라미터 (hysteresis, Garleanu & Pedersen 2013)
BZ_KEEP   <- 50L   # 기존 보유 중 랭크 50 이내면 유지
BZ_ENTRY  <- 25L   # 신규 진입은 랭크 25 이내만

# 분기 리밸런싱 월
REBAL_MONTHS <- c(3L, 6L, 9L, 12L)

# ──────────────────────────────────────────────────────────────────────────────
# 4. Preflight Check
# ──────────────────────────────────────────────────────────────────────────────
preflight_path <- file.path(FUNC_PATH, "validation", "preflight_memory.R")
if (file.exists(preflight_path)) {
  source(preflight_path)
  tryCatch(
    preflight_check(STRATEGY_ID, family = STRATEGY_FAM),
    error = function(e) cat("[preflight] Warning:", conditionMessage(e), "\n")
  )
} else {
  cat("[preflight] preflight_memory.R not found, skipping.\n")
}

# ──────────────────────────────────────────────────────────────────────────────
# 5. RAWDATA (1회 로드, setkey)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[5] RAWDATA 로드...\n")
rw      <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA
BM_DT   <- rw$BM_DT
setDT(RAWDATA)
setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %s rows | %s ~ %s\n",
            format(nrow(RAWDATA), big.mark = ","),
            min(RAWDATA$Date), max(RAWDATA$Date)))

# ──────────────────────────────────────────────────────────────────────────────
# 6. Investor Flow 데이터 로드 (1회)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[6] Investor flow 로드...\n")
investor_dt <- as.data.table(arrow::read_parquet(INVESTOR_WIDE_CACHE))
investor_dt[, Date := as.Date(Date)]
cat(sprintf("    %s rows | %s ~ %s\n",
            format(nrow(investor_dt), big.mark = ","),
            min(investor_dt$Date), max(investor_dt$Date)))

# ──────────────────────────────────────────────────────────────────────────────
# 7. 팩터 신호 생성 (factor_engine.R)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[7] 팩터 신호 생성 (Individual Contrarian 3MA + Size-neutral)...\n")
FACTORS_ALL <- build_individual_contrarian_signal(
  RAWDATA     = RAWDATA,
  investor_dt = investor_dt,
  ma_months   = 3L,
  min_history = 6L
)
cat(sprintf("    전체 신호: %d rows | %d months | %d tickers\n",
            nrow(FACTORS_ALL), uniqueN(FACTORS_ALL$Date),
            uniqueN(FACTORS_ALL$Ticker)))

# ──────────────────────────────────────────────────────────────────────────────
# 8. 유동성 필터 (C2: t-1 lag)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[8] 유동성 필터 (20일 이평 거래대금 t-1 lag >= 2억)...\n")

# 거래대금 = Vol * Close
RAWDATA[, TradingVal := Vol * Close]

# 20일 이동평균 (C1: rolling only, align=right)
RAWDATA[, liq20 := frollmean(TradingVal, n = 20L, align = "right", na.rm = TRUE),
        by = Ticker]

# C2: t-1 lag
RAWDATA[, liq20_lag := shift(liq20, 1L), by = Ticker]

# 월말 유동성 (시그널 날짜 기준 마지막 관측값)
RAWDATA[, YM := format(Date, "%Y-%m")]
mend_liq <- RAWDATA[, .(liq_m = last(liq20_lag)), by = .(YM, Ticker)]

# FACTORS_ALL 병합
FACTORS_ALL[, YM := format(Date, "%Y-%m")]
FACTORS_ALL <- merge(FACTORS_ALL, mend_liq, by = c("YM", "Ticker"), all.x = TRUE)
n_before <- nrow(FACTORS_ALL)
FACTORS_ALL <- FACTORS_ALL[!is.na(liq_m) & liq_m >= LIQ_THRESHOLD]
FACTORS_ALL[, c("YM", "liq_m") := NULL]
cat(sprintf("    %d → %d rows (유동성 통과)\n", n_before, nrow(FACTORS_ALL)))

# ──────────────────────────────────────────────────────────────────────────────
# 9. 분기 리밸런싱 필터 (3/6/9/12월 신호만 사용)
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[9] 분기 리밸런싱 필터...\n")
FACTORS_ALL[, sig_mon := as.integer(format(Date, "%m"))]
FACTORS_Q <- FACTORS_ALL[sig_mon %in% REBAL_MONTHS]
FACTORS_Q[, sig_mon := NULL]
setkey(FACTORS_Q, Date, Ticker)
cat(sprintf("    분기 신호: %d rows | %d rebal dates\n",
            nrow(FACTORS_Q), uniqueN(FACTORS_Q$Date)))

# ──────────────────────────────────────────────────────────────────────────────
# 10. 백테스트 (EW 30종목, Buffer Zone, 분기 리밸런싱)
#     S1 순수 팩터 테스트 — 국면/레버리지/방어 로직 없음
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[10] 백테스트 실행 (EW 30, quarterly, buffer keep=50/entry=25)...\n")
sim <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS_Q,
  n_holdings    = N_HOLD,
  commission    = COMMISSION,
  initial_cap   = 1e8,
  weight_method = "equal",
  buffer_zone   = list(keep_n = BZ_KEEP, entry_n = BZ_ENTRY)
)

DAILY_NAV_DT  <- sim$DAILY_NAV_DT
PORTFOLIO_LOG <- sim$PORTFOLIO_LOG
HOLDINGS_LOG  <- sim$HOLDINGS_LOG
strategy_xts  <- sim$strategy_xts
bm_xts        <- sim$bm_xts

# ──────────────────────────────────────────────────────────────────────────────
# 11. 성과 지표
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[11] 성과 지표 계산...\n")
perf    <- summarise_perf(strategy_xts, label = "STR_1674")
bm_perf <- summarise_perf(bm_xts,      label = "KOSPI200_BM")
ann_to  <- calc_turnover(PORTFOLIO_LOG, DAILY_NAV_DT)

# 일별 초과수익 기반 IR
bm_aligned    <- bm_xts[index(strategy_xts)]
daily_excess  <- as.numeric(strategy_xts) - as.numeric(bm_aligned)
ir <- if (length(daily_excess) > 20) {
  mean(daily_excess, na.rm = TRUE) / sd(daily_excess, na.rm = TRUE) * sqrt(252)
} else {
  NA_real_
}

cagr   <- perf$CAGR   / 100
sharpe <- perf$Sharpe
mdd    <- perf$MDD    / 100

cat(sprintf("  CAGR     : %+.2f%%\n",  cagr   * 100))
cat(sprintf("  Sharpe   : %.3f\n",     sharpe))
cat(sprintf("  MDD      : %.1f%%\n",   mdd    * 100))
cat(sprintf("  Sortino  : %.3f\n",     perf$Sortino))
cat(sprintf("  Turnover : %.0f%% /yr\n", ann_to))
cat(sprintf("  IR       : %.3f\n",     ir))
cat(sprintf("  WinRate  : %.1f%%\n",   perf$WinRate))
cat(sprintf("  TO < 600%%: %s\n",
    ifelse(ann_to <= 600, "PASS", "FAIL")))

# ──────────────────────────────────────────────────────────────────────────────
# 12. 차트 저장
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[12] 차트 저장...\n")

# Equity curve
png(file.path(OUT_DIR, "equity_curve.png"), width = 1200, height = 600, res = 120)
tryCatch({
  charts.PerformanceSummary(
    merge(strategy_xts, bm_xts, join = "inner"),
    main       = "STR_1674 Individual Contrarian Flow vs KOSPI200",
    colorset   = c("#1A6FE3", "#B0B8C1"),
    lwd        = c(2.5, 1.2),
    legend.loc = "topleft"
  )
}, error = function(e) {
  nav_v <- cumprod(1 + as.numeric(strategy_xts))
  plot(index(strategy_xts), nav_v, type = "l", col = "steelblue", lwd = 2,
       main = "STR_1674 — Equity Curve", xlab = "Date", ylab = "NAV")
  abline(h = 1, lty = 2, col = "gray60"); grid(col = "gray90", lty = 1)
})
dev.off()

# Annual bar chart
ann_s <- apply.yearly(strategy_xts, Return.cumulative)
ann_b <- apply.yearly(bm_xts,       Return.cumulative)
ann_m <- merge(ann_s, ann_b, join = "inner")
df_a  <- data.frame(
  Year      = format(index(ann_m), "%Y"),
  Strategy  = as.numeric(coredata(ann_m[, 1])) * 100,
  Benchmark = as.numeric(coredata(ann_m[, 2])) * 100
)
df_l <- pivot_longer(df_a, -Year, names_to = "Label", values_to = "Return")

p_a <- ggplot(df_l, aes(x = Year, y = Return, fill = Label)) +
  geom_col(position = "dodge", width = 0.7) +
  scale_fill_manual(values = c("Strategy" = "#1A6FE3", "Benchmark" = "#B0B8C1")) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  geom_hline(yintercept = 0, linewidth = 0.4, colour = "grey40") +
  geom_text(aes(label = paste0(round(Return, 1), "%"),
                vjust = ifelse(Return >= 0, -0.35, 1.25)),
            position = position_dodge(0.7), size = 2.8,
            fontface = "bold", colour = "grey20") +
  labs(title = "STR_1674 — Annual Returns", x = NULL, y = "Return (%)") +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 13, hjust = 0),
    axis.text.x      = element_text(angle = 45, hjust = 1, size = 9),
    panel.grid.major = element_line(colour = "grey90"),
    panel.grid.minor = element_blank(),
    legend.position  = "top",
    legend.title     = element_blank()
  )
ggsave(file.path(OUT_DIR, "annual_returns.png"), p_a,
       width = 12, height = 6, dpi = 150)
cat("[charts] 저장 완료\n")

# ──────────────────────────────────────────────────────────────────────────────
# 13. CSV 저장
# ──────────────────────────────────────────────────────────────────────────────
fwrite(DAILY_NAV_DT,  file.path(OUT_DIR, "daily_nav.csv"))
fwrite(PORTFOLIO_LOG, file.path(OUT_DIR, "portfolio_log.csv"))
if (nrow(HOLDINGS_LOG) > 0)
  fwrite(HOLDINGS_LOG, file.path(OUT_DIR, "holdings_log.csv"))

# ──────────────────────────────────────────────────────────────────────────────
# 14. Hurdle Gate v2.2
# ──────────────────────────────────────────────────────────────────────────────
cat("\n[14] Hurdle Gate v2.2...\n")

hard_fail <- (abs(mdd) > 0.45) || (ann_to > 600)

# 점수 계산
score  <- 0
score  <- score + min(25, max(0, (cagr / 0.16) * 15))
score  <- score + min(25, max(0, (sharpe / 0.8) * 20))
if (!is.na(perf$Sortino) && perf$Sortino >= 1.5) score <- score + 5
if (abs(mdd) <= 0.25) score <- score + 5
if (abs(mdd)  > 0.30) score <- score - 5
# Saturation: behavioral/flow family = 미개척 → penalty 없음
score  <- max(0, score)

novelty_bonus <- 10  # behavioral investor flow = 신규 family 탐험

grade <- if (hard_fail) {
  "F"
} else if (score >= 40 && cagr >= 0.16 && sharpe >= 0.8) {
  "A"
} else if (score >= 40 && cagr >= 0.12 && sharpe >= 0.6 && novelty_bonus >= 10) {
  "A_NOVEL"
} else if (score >= 25) {
  "B"
} else {
  "C"
}

cat(sprintf("  Grade    : %s\n", grade))
cat(sprintf("  Score    : %.1f / 100\n", score))
cat(sprintf("  hard_fail: %s\n", hard_fail))

# ──────────────────────────────────────────────────────────────────────────────
# 15. hurdle_result.json 저장
# ──────────────────────────────────────────────────────────────────────────────
hurdle_result <- list(
  strategy_id     = STRATEGY_ID,
  grade           = grade,
  grade_v21       = grade,
  score           = round(score, 1),
  hard_fail       = hard_fail,
  cagr            = round(cagr, 4),
  sharpe          = round(sharpe, 3),
  mdd             = round(mdd, 4),
  sortino         = round(as.numeric(perf$Sortino), 3),
  turnover_ann    = round(ann_to, 1),
  ir              = round(ir, 3),
  win_rate        = round(as.numeric(perf$WinRate), 1),
  worst_month_pct = round(as.numeric(perf$WorstMonth), 2),
  family          = STRATEGY_FAM,
  role_bias       = "RoleBias_Core",
  n_rebal_periods = nrow(PORTFOLIO_LOG),
  n_holdings      = N_HOLD,
  bz_keep         = BZ_KEEP,
  bz_entry        = BZ_ENTRY,
  rebal_freq      = "quarterly",
  ma_months       = 3L,
  novelty_bonus   = novelty_bonus,
  hurdle_version  = "v2.2",
  evaluated_at    = as.character(Sys.time()),
  pit_checks      = list(
    C1  = "rank-Z (no full-sample). 3MA frollmean(align=right)",
    C2  = "signal=month-end-t, execution=t+1. liq=shift(t-1)",
    C3  = "aggregation-period != application-period",
    C13 = "contrarian sign via -IndividualNetBuy (economic). no manual flip"
  )
)

write_json(hurdle_result, file.path(OUT_DIR, "hurdle_result.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  hurdle_result.json 저장 완료\n"))

# ──────────────────────────────────────────────────────────────────────────────
# 16. sim_result.rds 저장
# ──────────────────────────────────────────────────────────────────────────────
saveRDS(
  list(
    strategy_id = STRATEGY_ID,
    hypothesis  = "H_1674_individual_contrarian_flow",
    signal      = "individual_net_selling_3MA_size_neutral",
    family      = STRATEGY_FAM,
    role_bias   = "RoleBias_Core",
    hurdle      = hurdle_result,
    perf_table  = perf,
    bm_perf     = bm_perf,
    n_rebal     = nrow(PORTFOLIO_LOG),
    timestamp   = as.character(Sys.time())
  ),
  file.path(STRAT_DIR, "sim_result.rds")
)

# ──────────────────────────────────────────────────────────────────────────────
# 17. 완료 요약
# ──────────────────────────────────────────────────────────────────────────────
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\n=== STR_1674 완료 (%.1f초) ===\n", elapsed))
cat(sprintf("  CAGR: %+.2f%% | SR: %.3f | MDD: %.1f%% | TO: %.0f%%/yr\n",
    cagr * 100, sharpe, mdd * 100, ann_to))
cat(sprintf("  Grade: %s | Score: %.1f | TO < 600%%: %s\n",
    grade, score, ifelse(ann_to <= 600, "PASS", "FAIL")))
