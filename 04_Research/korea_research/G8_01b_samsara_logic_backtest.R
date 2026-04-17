cat("=== G8-01b: Samsara Protocol Logic-Based Backtest ===\n")
cat("=== IC가 아닌 Samsara 원래 로직(임계값+국면판단) 그대로 월간 백테스트 ===\n")

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
})
library(data.table)
library(TTR)

# ── 1. 데이터 로드 ────────────────────────────────────────────────
cat("[G8-01b] Step 1: Loading data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT <- res$BM_DT
RAWDATA_ORIG <- copy(RAWDATA)
rm(res)
gc(verbose = FALSE)

# ── 2. Samsara 팩터 계산 (원본 로직 이식) ─────────────────────────
cat("[G8-01b] Step 2: Computing Samsara factors...\n")

setorder(RAWDATA, Ticker, Date)
window_beta <- 60L
window_physics <- 20L

# Beta
RAWDATA[, Beta := {
  if (.N >= window_beta) {
    runCov(Ret, BM_Ret, n = window_beta) /
      (runVar(BM_Ret, n = window_beta) + 1e-8)
  } else rep(NA_real_, .N)
}, by = Ticker]

# Bollinger components
RAWDATA[, Mean_Close := {
  if (.N >= window_physics) runMean(Close, n = window_physics)
  else rep(NA_real_, .N)
}, by = Ticker]

RAWDATA[, SD_Close := {
  if (.N >= window_physics) runSD(Close, n = window_physics)
  else rep(NA_real_, .N)
}, by = Ticker]

# Momentum
RAWDATA[, Momentum := {
  if (.N >= window_physics)
    (Close / shift(Close, n = window_physics)) - 1
  else rep(NA_real_, .N)
}, by = Ticker]

# Residual
RAWDATA[, Residual := Ret - (Beta * BM_Ret)]

# Aleph
RAWDATA[, Aleph := {
  if (sum(!is.na(Residual)) >= window_physics && .N >= window_physics)
    abs(runSum(Residual, n = window_physics)) /
      (runSum(abs(Residual), n = window_physics) + 1e-6)
  else rep(NA_real_, .N)
}, by = Ticker]

# Volatility
RAWDATA[, Volatility := {
  if (sum(!is.na(Residual)) >= window_physics && .N >= window_physics)
    runSD(Residual, n = window_physics)
  else rep(NA_real_, .N)
}, by = Ticker]

# Mean_Res
RAWDATA[, Mean_Res := {
  if (sum(!is.na(Residual)) >= window_physics && .N >= window_physics)
    runMean(Residual, n = window_physics)
  else rep(NA_real_, .N)
}, by = Ticker]

# Psi (빅뱅)
RAWDATA[, Psi := (Residual - Mean_Res) / (Volatility + 1e-6)]

# STP (터널링)
RAWDATA[, STP := (Close - (Mean_Close + 2 * SD_Close)) / Close]

# Gravity (사건의 지평선)
RAWDATA[, Gravity := abs(Momentum) * Aleph]

# LHI (카오스)
RAWDATA[, LHI := {
  if (sum(!is.na(Volatility)) >= window_physics && .N >= window_physics)
    runSD(Volatility, n = window_physics)
  else rep(NA_real_, .N)
}, by = Ticker]

# Cleanup intermediate
for (col in c("Mean_Close", "SD_Close", "Mean_Res", "Momentum"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]

cat(sprintf("  Samsara factors computed: %s rows\n",
            format(nrow(RAWDATA[!is.na(Psi)]), big.mark = ",")))

# ── 3. Samsara 로직 기반 FACTORS 생성 ─────────────────────────────
cat("[G8-01b] Step 3: Building FACTORS with Samsara logic...\n")

# 월말 날짜 추출
RAWDATA[, YM := format(Date, "%Y%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
monthly_dates <- monthly_dates[monthly_dates >= as.Date("2006-01-01")]

# Samsara 임계값 (원본 그대로)
THRESHOLD_GRAVITY <- 1.5
THRESHOLD_ALEPH <- 0.15
LIQ_THRESHOLD <- 2e8

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

factor_list <- vector("list", length(monthly_dates))
mode_log <- vector("list", length(monthly_dates))

for (i in seq_along(monthly_dates)) {
  sig_d <- monthly_dates[i]
  snap <- RAWDATA[Date == sig_d & !is.na(Psi) & !is.na(Aleph) &
                    !is.na(STP) & !is.na(Gravity) & !is.na(LHI)]

  if (nrow(snap) < 30) next

  # 유동성 필터
  snap <- snap[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 20) next

  # === Samsara 국면 판단 ===
  avg_aleph <- mean(snap$Aleph, na.rm = TRUE)
  avg_gravity <- mean(snap$Gravity, na.rm = TRUE)
  avg_psi <- mean(snap$Psi, na.rm = TRUE)

  if (avg_aleph < THRESHOLD_ALEPH) {
    # Buddha: 전량 현금 → 이번 달 종목 선택 안 함
    mode_log[[i]] <- data.table(Date = sig_d, mode = "Buddha_Cash",
                                 avg_aleph = avg_aleph,
                                 avg_gravity = avg_gravity,
                                 avg_psi = avg_psi, n_selected = 0L)
    next
  }

  if (avg_gravity > THRESHOLD_GRAVITY) {
    # Event Horizon: 보유 유지 → 이전 달 그대로 (FACTORS에 이전 달 복사)
    if (i > 1 && !is.null(factor_list[[i - 1]])) {
      prev <- copy(factor_list[[i - 1]])
      prev[, Date := sig_d]
      factor_list[[i]] <- prev
    }
    mode_log[[i]] <- data.table(Date = sig_d, mode = "Event_Horizon",
                                 avg_aleph = avg_aleph,
                                 avg_gravity = avg_gravity,
                                 avg_psi = avg_psi, n_selected = 0L)
    next
  }

  # === Samsara 종목 선별 ===
  # STP > 0 (볼린저 상단 돌파)
  candidates <- snap[STP > 0]
  if (nrow(candidates) < 5) {
    # STP > 0 종목 부족 시 STP 상위 30으로 대체
    setorder(snap, -STP)
    candidates <- head(snap, 30)
  }

  # Gravity 내림차순 Top 20 (Samsara 원본 MAX_HOLDINGS = 20)
  setorder(candidates, -Gravity)
  top <- head(candidates, 20L)

  # 가중치: 1/LHI 역-카오스 가중 (Samsara 원본 로직)
  top[, Raw_Weight := 1 / (LHI + 1e-6)]
  top[, Weight := Raw_Weight / sum(Raw_Weight)]

  # Score: Weight 기반 (backtest_harness 호환)
  top[, Score := Weight]

  samsara_mode <- fifelse(avg_psi > 1.0, "BigBang", "Void_Normal")
  mode_log[[i]] <- data.table(Date = sig_d, mode = samsara_mode,
                               avg_aleph = avg_aleph,
                               avg_gravity = avg_gravity,
                               avg_psi = avg_psi,
                               n_selected = nrow(top))

  top[, Date := sig_d]
  factor_list[[i]] <- top[!is.na(Score), .(Date, Ticker, Score)]
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)
modes <- rbindlist(mode_log[!sapply(mode_log, is.null)])

# Cleanup
for (col in c("YM", "TradingValue", "AvgTV20", "Beta", "Residual",
              "Aleph", "Volatility", "Psi", "STP", "Gravity", "LHI"))
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
gc(verbose = FALSE)

cat(sprintf("  FACTORS: %s rows | %d dates\n",
            format(nrow(FACTORS), big.mark = ","), uniqueN(FACTORS$Date)))
cat(sprintf("  Mode distribution:\n"))
print(table(modes$mode))

# ── 4. 백테스트 ──────────────────────────────────────────────────
cat("\n[G8-01b] Step 4: Running backtest...\n")
RAWDATA <- copy(RAWDATA_ORIG)

sim <- run_monthly_simulation(
  RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
  n_holdings = 20L, weight_method = "score",
  commission = 0.0015,
  buffer_zone = list(keep_n = 50L, entry_n = 25L)
)

# ── 5. 성과 ──────────────────────────────────────────────────────
cat("[G8-01b] Step 5: Performance...\n")
STRATEGY_NAME <- "G8_01b_Samsara_Logic"
out_dir <- "04_Research/korea_research/G8_01b_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

perf <- summarise_perf(sim$strategy_xts, STRATEGY_NAME)
perf_bm <- summarise_perf(sim$bm_xts, "BM")
cat(sprintf("  %s: CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            STRATEGY_NAME, perf$CAGR, perf$Sharpe, perf$MDD))
cat(sprintf("  BM:     CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_bm$CAGR, perf_bm$Sharpe, perf_bm$MDD))

generate_charts(sim, output_dir = out_dir, strategy_name = STRATEGY_NAME)
fwrite(rbind(perf, perf_bm), file.path(out_dir, "performance.csv"))
fwrite(modes, file.path(out_dir, "samsara_modes.csv"))
saveRDS(sim, file.path(out_dir, "sim_result.rds"))

# 허들
RAWDATA <- copy(RAWDATA_ORIG)
source("02_Infrastructure/hurdle_gate.R")
hurdle <- run_hurdle_gate(
  sim_result = sim, FACTORS = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = "04_Research/korea_research/G8_01b_samsara_logic_backtest.R",
  output_dir = out_dir
)
jsonlite::write_json(hurdle, file.path(out_dir, "hurdle_result.json"),
                     auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("  Grade: %s | Score: %.1f\n",
            hurdle$grade, hurdle$verdict$total_score %||% hurdle$score %||% 0))

cat(sprintf("\n[G8-01b] Complete. Output: %s\n", out_dir))
