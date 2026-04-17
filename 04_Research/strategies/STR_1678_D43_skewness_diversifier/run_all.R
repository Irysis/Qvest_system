cat("=== STR_1678: D43_Skewness Conditional Diversifier — S1 ===\n")
## 핵심아이디어: D43_Skewness 단독 100%. Risk family.
## Diversifier role. ICIR 1.063, C19 상관 <0.10 (독립).
## NORMAL ICIR +0.391 (강함), CRISIS +0.121 (약함) → NORMAL-regime diversifier.
## Variant A: D43 상시 (baseline)
## Variant B: NORMAL(Regime_Score<20)만 D43, CAUTION+CRISIS에서는 Q07 전환
## EW 30종목 + 15bps + 유동성 2e8. 순수 팩터 신호 (S1, 오버레이 없음).
##
## PIT: C1(frollmean rolling, no full-sample) C2(liq_lag=shift(t-1)) C13(Z_Score_Aligned)
##      C15(factor_db_connector 경유, 직접 parquet 금지)
## OPT: rbindlist bulk load 1회, setkey(Date,Ticker)

set.seed(20260416)
t0 <- Sys.time()

# ---- 1. 경로 설정 ----
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 2. 인프라 로드 ----
source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr)
  library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales); library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID  <- "STR_1678"
STRATEGY_FAM <- "risk"
N_HOLD       <- 30L
LIQ_THRESHOLD <- 2e8
COMMISSION   <- 0.0015   # 15bps

# ---- 3. Preflight ----
source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
preflight_check(STRATEGY_ID, family = STRATEGY_FAM)

# ---- 4. RAWDATA (1회 로드) ----
cat("\n[4] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA
BM_DT   <- rw$BM_DT
setDT(RAWDATA)
setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# ---- 5. Factor DB (C15: connector 경유, 1회 bulk load) ----
cat("\n[5] Factor DB — D43_Skewness + Q07_Earnings_Stability (C15 준수)...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

FACTORS_NEEDED <- c("D43_Skewness", "Q07_Earnings_Stability")
CACHE_DIR_FDB  <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(CACHE_DIR_FDB,
                         pattern = "^factor_db_\\d{6}\\.parquet$",
                         full.names = TRUE)
cat(sprintf("    %d monthly parquet files found.\n", length(fdb_files)))

# OPT: rbindlist 1회 bulk load. 루프 내 반복 로드 금지.
fdb <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(f))
  dt[Factor_Name %in% FACTORS_NEEDED]
}))
fdb[, Date := as.Date(Date)]

# C13: Z_Score_Aligned = align_factor_direction() 사용. 수동 방향 반전 절대 금지.
fdb <- align_factor_direction(fdb, .load_registry())
fdb <- fdb[Coverage == TRUE]
setkey(fdb, Date, Ticker)
cat(sprintf("    %d rows | Factors: %s\n", nrow(fdb), paste(unique(fdb$Factor_Name), collapse = ", ")))

# ---- 5b. Regime Signal (C5: t-1 lag) ----
cat("\n[5b] Regime Signal (unified_regime_signal.parquet)...\n")
regime_dt <- as.data.table(read_parquet(file.path(CACHE_DIR, "unified_regime_signal.parquet")))
regime_dt[, Date := as.Date(Date)]
# C5: regime signal은 t-1 기준 적용 — 해당 월 시그널은 다음 월에만 사용
# → shift로 1개월 lag
setorder(regime_dt, Date)
regime_dt[, Regime_Score_Lag := shift(Regime_Score, 1L)]
regime_dt[, Category_Lag := shift(Category, 1L)]
regime_dt <- regime_dt[!is.na(Regime_Score_Lag)]
cat(sprintf("    %d months | Score range: %.1f ~ %.1f\n",
    nrow(regime_dt), min(regime_dt$Regime_Score_Lag, na.rm=TRUE),
    max(regime_dt$Regime_Score_Lag, na.rm=TRUE)))

# ---- 6. 유동성 필터 사전 계산 (일간 RAWDATA) ----
cat("\n[6] Liquidity Filter (rolling 20d, t-1 lag)...\n")
# C1: rolling 20일 (full-sample 통계 금지)
RAWDATA[, liq_20d := frollmean(Vol * Close, n = 20L, align = "right"), by = Ticker]
# C2: t-1 lag (same-day circular 금지)
RAWDATA[, liq_lag := shift(liq_20d, 1L), by = Ticker]

# 월말 유동성 스냅샷 (시그널 날짜 기준)
fdb_wide <- dcast(fdb, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
sig_dates <- sort(unique(fdb_wide$Date))  # 월말 날짜들

# 시그널 날짜에서 유동성 lag 추출
liq_snap <- RAWDATA[Date %in% sig_dates, .(Date, Ticker, liq_lag)]
dt_sig <- merge(fdb_wide, liq_snap, by = c("Date", "Ticker"), all.x = TRUE)
cat(sprintf("    Signal dates: %d | dt_sig rows: %d\n", length(sig_dates), nrow(dt_sig)))

# ---- 6b. 월간 수익률 계산 (다음 달 holding period return) ----
cat("\n[6b] Monthly Forward Returns (next month HPR)...\n")
# 월말 시그널 → 다음 달 1일~말일까지 보유 수익률
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_ret_by_ticker <- RAWDATA[, .(
  month_ret = prod(1 + Ret, na.rm = TRUE) - 1
), by = .(YM, Ticker)]
# YM은 해당 월의 수익률. 시그널은 전월 말에 발생 → 전월말 sig → 당월 수익률
# sig_date 2020-06-30 → 다음달 수익률 = 2020-07 YM
monthly_ret_by_ticker[, sig_YM := {
  yr <- as.integer(substr(YM, 1, 4))
  mo <- as.integer(substr(YM, 6, 7))
  # 1개월 전으로 (이 YM의 수익률은 전월 시그널에 대응)
  mo_prev <- mo - 1L
  yr_prev <- yr
  if_else <- ifelse(mo_prev == 0L, TRUE, FALSE)
  mo_prev[if_else] <- 12L
  yr_prev[if_else] <- yr_prev[if_else] - 1L
  sprintf("%04d-%02d", yr_prev, mo_prev)
}]

cat(sprintf("    Monthly returns: %d ticker-months\n", nrow(monthly_ret_by_ticker)))

# ---- 7. 월별 포트폴리오 구성 (Variant A: D43 상시) ----
cat("\n[7] Monthly Portfolio — Variant A: D43 Always...\n")
months_all <- sort(sig_dates)

build_portfolio <- function(dt_sig, months, score_col, n_hold, liq_thr) {
  port_list <- lapply(months, function(m) {
    sub <- dt_sig[Date == m & !is.na(get(score_col)) & !is.na(liq_lag)]
    # C2: liq_lag(t-1)로 필터 — 당일 유동성 사용 금지
    sub <- sub[liq_lag >= liq_thr]
    if (nrow(sub) < n_hold) return(NULL)
    sub[, .score := get(score_col)]
    sub <- sub[order(-.score)]
    top <- head(sub, n_hold)
    top[, .(Date = m, Ticker, Score = .score, Weight = 1.0 / n_hold)]
  })
  rbindlist(port_list[!sapply(port_list, is.null)])
}

port_a <- build_portfolio(dt_sig, months_all, "D43_Skewness", N_HOLD, LIQ_THRESHOLD)
cat(sprintf("    Variant A: %d rows | %d months\n", nrow(port_a), length(unique(port_a$Date))))

# ---- 7b. Variant B: Regime-Conditional (NORMAL→D43, else→Q07) ----
cat("\n[7b] Variant B: NORMAL→D43, CAUTION/CRISIS→Q07...\n")
# Regime_Score < 20 → NORMAL → D43, >= 20 → CAUTION/CRISIS → Q07
regime_lookup <- regime_dt[, .(Date, Regime_Score_Lag)]

port_b_list <- lapply(months_all, function(m) {
  # C5: regime_score는 t-1 lag 적용된 값 사용
  rs <- regime_lookup[Date == m, Regime_Score_Lag]
  if (length(rs) == 0) rs <- 0  # fallback: NORMAL (초기 데이터 부족)

  use_factor <- if (rs < 20) "D43_Skewness" else "Q07_Earnings_Stability"

  sub <- dt_sig[Date == m & !is.na(get(use_factor)) & !is.na(liq_lag)]
  sub <- sub[liq_lag >= LIQ_THRESHOLD]
  if (nrow(sub) < N_HOLD) return(NULL)
  sub[, .score := get(use_factor)]
  sub <- sub[order(-.score)]
  top <- head(sub, N_HOLD)
  top[, .(Date = m, Ticker, Score = .score, Weight = 1.0 / N_HOLD,
          active_factor = use_factor, regime_score = rs)]
})
port_b <- rbindlist(port_b_list[!sapply(port_b_list, is.null)])
cat(sprintf("    Variant B: %d rows | %d months\n", nrow(port_b), length(unique(port_b$Date))))

# D43 vs Q07 활성 비율
if (nrow(port_b) > 0) {
  factor_usage <- port_b[, .(N = .N), by = active_factor]
  cat("    Factor usage:\n")
  print(factor_usage)
}

# ---- 8. 수익률 계산 함수 (월간 forward return 기반) ----
calc_returns <- function(port_dt, monthly_ret_by_ticker, bm_dt, n_hold, commission, label) {
  cat(sprintf("\n[8] Return Calculation — %s...\n", label))
  # port_dt$Date = 시그널 날짜 (월말). 다음 달 수익률을 매칭.
  port_dt[, sig_YM := format(Date, "%Y-%m")]

  # 다음 달 수익률 매칭
  port_dt <- merge(port_dt, monthly_ret_by_ticker[, .(sig_YM, Ticker, fwd_ret = month_ret)],
                   by = c("sig_YM", "Ticker"), all.x = TRUE)

  # 포트폴리오 월간 수익률 (EW)
  monthly_ret <- port_dt[!is.na(fwd_ret), .(port_ret = mean(fwd_ret, na.rm = TRUE)), by = Date]
  setorder(monthly_ret, Date)

  # Turnover 계산
  prev_tk <- NULL
  to_vec  <- numeric(nrow(monthly_ret))
  invisible(lapply(seq_len(nrow(monthly_ret)), function(i) {
    cur_date <- monthly_ret$Date[i]
    cur <- port_dt[Date == cur_date, Ticker]
    if (!is.null(prev_tk)) {
      to_vec[i] <<- 1 - length(intersect(cur, prev_tk)) / n_hold
    }
    prev_tk <<- cur
    NULL
  }))
  monthly_ret[, turnover := to_vec]
  # 수수료 차감
  monthly_ret[turnover > 0, port_ret := port_ret - turnover * commission]

  # BM 월간 수익률 매칭
  bm_monthly <- RAWDATA[Ticker == "A005930"][0]  # dummy — BM_DT 구조 확인
  # BM_DT도 일간이므로 월간으로 집계
  bm_dt_copy <- copy(bm_dt)
  setDT(bm_dt_copy)
  bm_dt_copy[, YM := format(Date, "%Y-%m")]
  bm_monthly <- bm_dt_copy[, .(BM_Ret_Monthly = prod(1 + BM_Ret, na.rm = TRUE) - 1), by = YM]
  # sig_YM → BM의 다음 달 = sig_YM + 1개월
  monthly_ret[, sig_YM := format(Date, "%Y-%m")]
  monthly_ret[, hold_YM := {
    yr <- as.integer(substr(sig_YM, 1, 4))
    mo <- as.integer(substr(sig_YM, 6, 7)) + 1L
    yr[mo > 12L] <- yr[mo > 12L] + 1L
    mo[mo > 12L] <- mo[mo > 12L] - 12L
    sprintf("%04d-%02d", yr, mo)
  }]
  monthly_ret <- merge(monthly_ret, bm_monthly, by.x = "hold_YM", by.y = "YM", all.x = TRUE)
  setnames(monthly_ret, "BM_Ret_Monthly", "BM_Ret")
  setorder(monthly_ret, Date)
  monthly_ret
}

ret_a <- calc_returns(copy(port_a), monthly_ret_by_ticker, BM_DT, N_HOLD, COMMISSION, "Variant A (D43 Always)")
ret_b <- calc_returns(copy(port_b[, .(Date, Ticker, Score, Weight)]), monthly_ret_by_ticker, BM_DT, N_HOLD, COMMISSION, "Variant B (Conditional)")

# ---- 9. 성과 지표 ----
calc_metrics <- function(monthly_ret, label) {
  nav <- cumprod(1 + monthly_ret$port_ret)
  dd  <- nav / cummax(nav) - 1
  n_m <- nrow(monthly_ret)

  cagr     <- as.numeric(tail(nav, 1)^(12 / n_m) - 1)
  sharpe   <- mean(monthly_ret$port_ret) / sd(monthly_ret$port_ret) * sqrt(12)
  mdd      <- min(dd)
  to_ann   <- mean(monthly_ret$turnover[monthly_ret$turnover > 0], na.rm = TRUE) * 12

  monthly_ret[, excess_ret := port_ret - BM_Ret]
  ir <- mean(monthly_ret$excess_ret, na.rm = TRUE) / sd(monthly_ret$excess_ret, na.rm = TRUE) * sqrt(12)

  cat(sprintf("\n=== %s ===\n", label))
  cat(sprintf("  CAGR : %.2f%%\n  SR   : %.3f\n  MDD  : %.1f%%\n  TO   : %.0f%%\n  IR   : %.3f\n  N_months: %d\n",
      cagr*100, sharpe, mdd*100, to_ann*100, ir, n_m))

  list(cagr = cagr, sharpe = sharpe, mdd = mdd, turnover_ann = to_ann,
       ir = ir, n_m = n_m, nav = nav, dd = dd, monthly_ret = monthly_ret)
}

cat("\n[9] Performance Metrics...\n")
met_a <- calc_metrics(ret_a, "Variant A: D43 Always")
met_b <- calc_metrics(ret_b, "Variant B: Conditional (NORMAL→D43, else→Q07)")

# ---- 10. C19 상관 분석 ----
cat("\n[10] C19 Correlation Analysis...\n")
cat("    C19 팩터 직접 계산 (baseline comparison)...\n")

# C19 Factor DB 로드
fdb_c19 <- rbindlist(lapply(fdb_files, function(f) {
  dt_tmp <- as.data.table(arrow::read_parquet(f))
  dt_tmp[Factor_Name == "C19_Composite_Earnings"]
}))
fdb_c19[, Date := as.Date(Date)]
fdb_c19 <- align_factor_direction(fdb_c19, .load_registry())
fdb_c19 <- fdb_c19[Coverage == TRUE]
fdb_c19_wide <- fdb_c19[, .(Date, Ticker, C19_Score = Z_Score_Aligned)]

# 유동성은 이미 RAWDATA에 liq_lag 계산됨 → 시그널 날짜에서 스냅샷
liq_c19 <- RAWDATA[Date %in% sig_dates, .(Date, Ticker, liq_lag)]
dt_c19_sig <- merge(fdb_c19_wide, liq_c19, by = c("Date", "Ticker"), all.x = TRUE)

port_c19 <- build_portfolio(dt_c19_sig, months_all, "C19_Score", N_HOLD, LIQ_THRESHOLD)
ret_c19 <- calc_returns(copy(port_c19), monthly_ret_by_ticker, BM_DT, N_HOLD, COMMISSION, "C19 Reference")

# 월별 수익률 기반 상관
corr_df <- merge(ret_a[, .(Date, ret_d43 = port_ret)],
                 ret_c19[, .(Date, ret_c19 = port_ret)], by = "Date")
corr_df <- merge(corr_df, ret_b[, .(Date, ret_cond = port_ret)], by = "Date")

corr_a_c19 <- cor(corr_df$ret_d43, corr_df$ret_c19, use = "complete.obs")
corr_b_c19 <- cor(corr_df$ret_cond, corr_df$ret_c19, use = "complete.obs")

cat(sprintf("    Variant A (D43) vs C19 correlation: %.3f\n", corr_a_c19))
cat(sprintf("    Variant B (Cond) vs C19 correlation: %.3f\n", corr_b_c19))

# ---- 10b. 국면별 성과 분석 ----
cat("\n[10b] Regime-Conditional Performance...\n")
ret_a_regime <- merge(ret_a[, .(Date, port_ret)], regime_dt[, .(Date, Regime_Score_Lag)], by = "Date")
ret_a_regime[, regime := fifelse(Regime_Score_Lag < 20, "NORMAL", fifelse(Regime_Score_Lag < 40, "CAUTION", "CRISIS"))]

regime_perf <- ret_a_regime[, .(
  mean_ret = mean(port_ret, na.rm = TRUE) * 12,
  vol      = sd(port_ret, na.rm = TRUE) * sqrt(12),
  n_months = .N
), by = regime]
regime_perf[, sr := mean_ret / vol]
cat("    D43 Performance by Regime:\n")
print(regime_perf)

# ---- 11. 출력 저장 ----
cat("\n[11] Save Outputs...\n")
fwrite(ret_a, file.path(OUT_DIR, "performance_A.csv"))
fwrite(ret_b, file.path(OUT_DIR, "performance_B.csv"))

# Equity Curve 차트 (A vs B vs C19)
png(file.path(OUT_DIR, "equity_curve.png"), width = 1100, height = 560)
par(mar = c(4, 4, 3, 8))
nav_a <- cumprod(1 + ret_a$port_ret)
nav_b <- cumprod(1 + ret_b$port_ret)

# C19 ref 날짜 맞추기
corr_common <- merge(ret_a[, .(Date, nav_a = cumprod(1 + port_ret))],
                     ret_b[, .(Date, nav_b = cumprod(1 + port_ret))], by = "Date")
corr_common <- merge(corr_common, ret_c19[, .(Date, nav_c19 = cumprod(1 + port_ret))], by = "Date")

ylim_range <- range(c(corr_common$nav_a, corr_common$nav_b, corr_common$nav_c19), na.rm = TRUE)
plot(as.Date(corr_common$Date), corr_common$nav_a,
     type = "l", col = "steelblue", lwd = 2,
     main = "STR_1678 D43 Skewness Diversifier — A vs B vs C19",
     xlab = "Date", ylab = "NAV", ylim = ylim_range)
lines(as.Date(corr_common$Date), corr_common$nav_b, col = "darkgreen", lwd = 2, lty = 2)
lines(as.Date(corr_common$Date), corr_common$nav_c19, col = "gray50", lwd = 1.5, lty = 3)
abline(h = 1, lty = 2, col = "gray60")
grid(col = "gray90", lty = 1)
legend("topleft", legend = c("A: D43 Always", "B: D43/Q07 Cond", "C19 Ref"),
       col = c("steelblue", "darkgreen", "gray50"), lwd = c(2, 2, 1.5),
       lty = c(1, 2, 3), cex = 0.9, bg = "white")
dev.off()

# Annual Returns 차트 (Variant A)
ret_a[, Year := format(Date, "%Y")]
annual_a <- ret_a[, .(ann_ret = prod(1 + port_ret) - 1), by = Year]
png(file.path(OUT_DIR, "annual_returns.png"), width = 900, height = 480)
par(mar = c(4, 4, 3, 2))
bar_colors <- ifelse(annual_a$ann_ret >= 0, "steelblue", "tomato")
barplot(annual_a$ann_ret * 100, names.arg = annual_a$Year,
        col = bar_colors, main = "STR_1678 D43 Skewness — Annual Returns (%)",
        ylab = "Return (%)", las = 2, cex.names = 0.75)
abline(h = 0, col = "black", lwd = 0.8)
dev.off()

# ---- 12. Hurdle v2.2 인라인 평가 ----
cat("\n[12] Hurdle Gate v2.2...\n")
# Variant A를 기본 평가 대상으로
cagr_a   <- met_a$cagr
sr_a     <- met_a$sharpe
mdd_a    <- met_a$mdd
to_a     <- met_a$turnover_ann

hard_fail <- (abs(mdd_a) > 0.45) || (to_a > 6.0)
score <- 0
score <- score + min(25, max(0, (cagr_a / 0.16) * 15))   # Return axis
score <- score + min(25, max(0, (sr_a / 0.8) * 20))       # Risk axis (SR)
if (abs(mdd_a) > 0.30) score <- score - 5                  # MDD penalty
# Saturation: risk family — low saturation (first few trials)
score <- score - 4
score <- max(0, score)

# Novelty bonus: C19 상관 < 0.30 → +15
novelty_bonus <- 0
if (!is.na(corr_a_c19) && abs(corr_a_c19) < 0.30) {
  novelty_bonus <- 15
} else if (!is.na(corr_a_c19) && abs(corr_a_c19) < 0.50) {
  novelty_bonus <- 6
}
score <- score + novelty_bonus

grade <- if (hard_fail) {
  "F"
} else if (score >= 40 && cagr_a >= 0.16 && sr_a >= 0.8) {
  "A"
} else if (score >= 40 && cagr_a >= 0.12 && sr_a >= 0.6 && novelty_bonus >= 10) {
  "A_NOVEL"
} else if (score >= 25) {
  "B"
} else {
  "C"
}

hurdle_result <- list(
  strategy_id    = STRATEGY_ID,
  grade          = grade,
  grade_v21      = grade,   # backward compat
  score          = round(score, 1),
  hard_fail      = hard_fail,
  cagr           = round(cagr_a, 4),
  sharpe         = round(sr_a, 3),
  mdd            = round(mdd_a, 4),
  turnover_ann   = round(to_a, 3),
  ir             = round(met_a$ir, 3),
  family         = STRATEGY_FAM,
  role_bias      = "RoleBias_Diversifier",
  n_months       = met_a$n_m,
  corr_c19       = round(corr_a_c19, 3),
  novelty_bonus  = novelty_bonus,
  hurdle_version = "v2.2",
  evaluated_at   = as.character(Sys.time()),
  # Variant B 참고 성과
  variant_b      = list(
    cagr    = round(met_b$cagr, 4),
    sharpe  = round(met_b$sharpe, 3),
    mdd     = round(met_b$mdd, 4),
    corr_c19 = round(corr_b_c19, 3)
  )
)

write_json(hurdle_result, file.path(OUT_DIR, "hurdle_result.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  Grade: %s | Score: %.1f | hard_fail: %s | novelty: +%d\n",
    grade, score, hard_fail, novelty_bonus))

# ---- 13. sim_result 저장 ----
sim_result <- list(
  strategy_id  = STRATEGY_ID,
  hypothesis   = "H_1678_D43_skewness_conditional_diversifier",
  factor       = "D43_Skewness",
  blend        = "standalone_100pct",
  role_bias    = "RoleBias_Diversifier",
  hurdle       = hurdle_result,
  regime_perf  = as.list(regime_perf),
  n_months     = met_a$n_m,
  timestamp    = as.character(Sys.time())
)
saveRDS(sim_result, file.path(STRAT_DIR, "sim_result.rds"))

# ---- 14. 요약 보고 ----
cat("\n\n")
cat("================================================================\n")
cat("  STR_1678 D43 Skewness Conditional Diversifier — SUMMARY\n")
cat("================================================================\n")
cat(sprintf("  Variant A (D43 Always):   SR %.3f | CAGR %.1f%% | MDD %.1f%% | TO %.0f%%\n",
    met_a$sharpe, met_a$cagr*100, met_a$mdd*100, met_a$turnover_ann*100))
cat(sprintf("  Variant B (D43/Q07 Cond): SR %.3f | CAGR %.1f%% | MDD %.1f%% | TO %.0f%%\n",
    met_b$sharpe, met_b$cagr*100, met_b$mdd*100, met_b$turnover_ann*100))
cat(sprintf("  C19 Corr: A=%.3f | B=%.3f\n", corr_a_c19, corr_b_c19))
cat(sprintf("  Hurdle: Grade %s | Score %.1f\n", grade, score))
cat(sprintf("  Elapsed: %.1fs\n", as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cat("================================================================\n")
