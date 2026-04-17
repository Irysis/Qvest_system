cat("=== STR_1642 VD+: Low-Beta 3F Diversifier + Regime(MRS 20) + DD Brake(10/25) ===\n")
## 핵심아이디어: STR_1642 S1 기반 S5 Overlay Mutation (VD+ 패턴)
## STR_1631 VD+: Regime(MRS Caution 20) + DD Brake(10/25) → MDD 49%→25.4% 달성 전례 적용
## S5 목표: MDD 66.8% → 45% 미만 (Hard FAIL 탈출)
## PIT:
##   C5 : Regime MRS 이미 t-1 lagged (apply_regime_overlay 내부, 추가 shift 금지)
##   C9 : DD Brake = c(1.0, head(exp_raw, -1))  t-1 lag 필수
##   C13: Z_Score_Aligned만 사용 (factor_engine.R 그대로)
## RoleBias_Diversifier

set.seed(1642)
options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_NAME   <- "LowBeta_3F_VDplus"
STRATEGY_ID     <- "STR_1642_VDplus"
STRATEGY_FAMILY <- "accrual_microstructure_quality"
QEPM_AUTO_COMMIT <- TRUE

t0 <- Sys.time()

# ---- 경로 설정 (normalizePath 금지 — WSL 한글 경로 버그) ----
SCRIPT_DIR <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) getwd()
)
INFRA_DIR <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")
if (!file.exists(file.path(INFRA_DIR, "config.R"))) {
  INFRA_DIR <- file.path(
    "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
    "02_Infrastructure"
  )
}

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
library(data.table)
library(xts)
library(arrow)
library(ggplot2)
library(scales)
library(jsonlite)

# ---- output 디렉토리 ----
output_dir <- file.path(SCRIPT_DIR, "output")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Preflight Check ----
tryCatch({
  source(file.path(VALIDATION_DIR, "preflight_memory.R"))
  preflight_check(STRATEGY_ID, family = STRATEGY_FAMILY)
}, error = function(e) cat("[Preflight]", e$message, "\n"))

# ---- 상수 ----
LIQ_THRESHOLD  <- 2e8
STR_START_DATE <- as.Date("2002-01-01")
SIGNAL_START_DATE <- as.Date("2002-07-01")

cat("\n[Phase 1] Loading RAWDATA + factor engine (S1 base)...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

RAWDATA <- RAWDATA[Date >= STR_START_DATE]
RAWDATA_ORIG <- copy(RAWDATA)

cat(sprintf("  [Filter] RAWDATA: %s ~ %s (%s rows)\n",
            min(RAWDATA$Date), max(RAWDATA$Date),
            format(nrow(RAWDATA), big.mark = ",")))

# ---- Factor Engine (S1과 동일 — STR_1642 원본 사용) ----
# factor_engine.R은 S1 디렉토리에 존재. 복사하지 않고 참조.
S1_DIR <- file.path(SCRIPT_DIR, "..", "STR_1642_lowbeta_3f_diversifier")
if (!file.exists(file.path(S1_DIR, "factor_engine.R"))) {
  stop("STR_1642 S1 factor_engine.R not found at: ", S1_DIR)
}
source(file.path(S1_DIR, "factor_engine.R"))

stopifnot(
  is.data.table(FACTORS),
  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),
  nrow(FACTORS) > 0
)
cat(sprintf("  [FACTORS] %d rows | %d dates\n", nrow(FACTORS), uniqueN(FACTORS$Date)))

cat("\n[Phase 2] Pure factor backtest (N=20, EW, BZ 35/20, NO overlay = S1 base)...\n")
RAWDATA <- copy(RAWDATA_ORIG)

sim_base <- run_monthly_simulation(
  RAWDATA       = RAWDATA,
  BM_DT         = BM_DT,
  FACTORS       = FACTORS,
  n_holdings    = 20L,
  weight_method = "equal",
  commission    = 0.0015,
  buffer_zone   = list(keep_n = 35L, entry_n = 20L)
)

perf_base <- summarise_perf(sim_base$strategy_xts, "S1_Base")
perf_bm   <- summarise_perf(sim_base$bm_xts, "BM")
cat(sprintf("  [S1 Base] CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_base$CAGR, perf_base$Sharpe, perf_base$MDD))

# ════════════════════════════════════════════════════════════════
# Phase 3: Regime 3-Layer Overlay (Enhanced Caution threshold=20)
#   MRS 이미 t-1 lagged (apply_regime_overlay.R 내부)
#   추가 shift() 금지 — 이중 lag는 t-2 오류
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 3] Regime Overlay (Enhanced Caution MRS=20)...\n")

source(file.path(REGIME_DIR, "regime_engine_daily.R"))
source(file.path(REGIME_DIR, "apply_regime_overlay.R"))

REGIME <- build_daily_regime(use_cache = TRUE)
setkey(REGIME, Date)

# Inverse ETF (KODEX 인버스 — 없으면 -BM proxy)
# CACHE_DIR: config.R에서 정의됨 (file.path(PROJECT_ROOT, ".cache"))
inv_path <- file.path(CACHE_DIR, "kodex_inverse_114800.csv")

INV_DT <- tryCatch({
  if (file.exists(inv_path)) {
    dt <- fread(inv_path); dt[, Date := as.Date(Date)]; setkey(dt, Date)
    cat(sprintf("  [Regime] Inverse ETF loaded: %d rows\n", nrow(dt)))
    dt
  } else {
    cat("  [Regime] No inverse ETF — using -BM proxy.\n")
    NULL
  }
}, error = function(e) { cat("  [Regime] inv ETF load err:", e$message, "\n"); NULL })

# apply_regime_overlay: caution_threshold=20 (Enhanced, vs default 30)
# crisis_threshold: MRS>=60 + axes>=5 + consec>=3 (default)
overlay_sim <- apply_regime_overlay(
  sim_result        = sim_base,
  regime_dt         = REGIME,
  BM_DT             = BM_DT,
  inv_dt            = INV_DT,
  crisis_threshold  = list(mrs = 60, axes = 5, consec = 3),
  caution_threshold = 20L   # Enhanced: 20 (vs STR_1631 base 30)
)

perf_overlay <- summarise_perf(overlay_sim$strategy_xts, "Regime_Overlay")
cat(sprintf("  [Regime] CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_overlay$CAGR, perf_overlay$Sharpe, perf_overlay$MDD))

# Layer 분포 출력
cat(sprintf("  Layer: Normal=%.1f%% Caution=%.1f%% Crisis=%.1f%%\n",
            overlay_sim$overlay_stats$normal_days / nrow(overlay_sim$DAILY_NAV_DT) * 100,
            overlay_sim$overlay_stats$caution_days / nrow(overlay_sim$DAILY_NAV_DT) * 100,
            overlay_sim$overlay_stats$crisis_days / nrow(overlay_sim$DAILY_NAV_DT) * 100))

# ════════════════════════════════════════════════════════════════
# Phase 4: DD Brake (10/25) on top of Regime Overlay
#   C9 준수: dd_exp_lag = c(1.0, head(exp_raw, -1))  t-1 lag
#   Ref: Grossman & Zhou (1993) CPPI, L-728 (base SR > 1.0 required)
#   STR_1631 VD+: DD Brake(10/25) → MDD 49%→25.4%
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 4] DD Brake (10/25) — C9 t-1 lag 준수...\n")

DD_TRIGGER  <- 0.10   # 10% drawdown → 감소 시작
DD_MAX_EXIT <- 0.25   # 25% drawdown → 최소 노출 (30%)
DD_MIN_EXP  <- 0.30   # 최소 노출 30%

nav_overlay <- copy(overlay_sim$DAILY_NAV_DT)
setkey(nav_overlay, Date)

# 사용할 수익률: Ret_overlay (regime overlay 적용 후)
if (!"Ret_overlay" %in% names(nav_overlay)) {
  stop("[FATAL] Ret_overlay column not found in overlay DAILY_NAV_DT")
}

# NAV 재계산 (overlay로부터)
nav_overlay[, NAV_regime := {
  DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_overlay)
}]

# Drawdown 계산
nav_overlay[, DD := (NAV_regime - cummax(NAV_regime)) / cummax(NAV_regime)]  # 음수

# DD Brake 노출 계산 (t 시점)
# exp_raw[t]: t 시점의 NAV 기준 DD에 따른 권고 노출
nav_overlay[, exp_raw := fifelse(
  DD >= -DD_TRIGGER,
  1.0,
  fifelse(
    DD <= -DD_MAX_EXIT,
    DD_MIN_EXP,
    DD_MIN_EXP + (1.0 - DD_MIN_EXP) * (DD + DD_MAX_EXIT) / (DD_MAX_EXIT - DD_TRIGGER)
  )
)]

# C9 CRITICAL: t-1 lag — 오늘의 노출은 어제의 DD 기준
# dd_exp_lag[t] = exp_raw[t-1]
nav_overlay[, dd_exp_lag := c(1.0, head(exp_raw, -1))]

# 최종 수익률
nav_overlay[, Ret_final := Ret_overlay * dd_exp_lag]
nav_overlay[, NAV_final := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_final)]

# xts 변환
final_xts <- xts(nav_overlay$Ret_final, order.by = nav_overlay$Date)
names(final_xts) <- "Strategy"

perf_final <- summarise_perf(final_xts, "VDplus_Final")
cat(sprintf("  [VDplus] CAGR=%.2f%% SR=%.3f MDD=%.1f%%\n",
            perf_final$CAGR, perf_final$Sharpe, perf_final$MDD))
cat(sprintf("  [DD Brake] Mean exposure: %.3f\n",
            mean(nav_overlay$dd_exp_lag, na.rm = TRUE)))

# ════════════════════════════════════════════════════════════════
# Phase 5: Hurdle Gate
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 5] Hurdle Gate...\n")

# hurdle gate용 sim 구성
sim_final <- list(
  strategy_xts  = final_xts,
  bm_xts        = sim_base$bm_xts,
  DAILY_NAV_DT  = nav_overlay[, .(Date,
                                   NAV = NAV_final,
                                   Strategy_Ret = Ret_final)],
  PORTFOLIO_LOG = sim_base$PORTFOLIO_LOG
)

# sim_final 캐시 저장
saveRDS(sim_final, file.path(output_dir, "sim_final.rds"))

source(file.path(INFRA_DIR, "hurdle_gate.R"))
hurdle <- run_hurdle_gate(
  sim_result    = sim_final,
  FACTORS       = FACTORS,
  strategy_name = STRATEGY_NAME,
  strategy_file = file.path(SCRIPT_DIR, "run_all.R"),  # set.seed() 인식용
  output_dir    = output_dir
)
jsonlite::write_json(hurdle,
  file.path(output_dir, "hurdle_result.json"),
  auto_unbox = TRUE, pretty = TRUE)

cat(sprintf("  Grade: %s | Score: %.1f\n",
            hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0))

# ════════════════════════════════════════════════════════════════
# Phase 6: Chart 생성 (equity_curve + drawdown)
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 6] Generating charts...\n")

generate_charts(sim_final, output_dir = output_dir, strategy_name = STRATEGY_NAME)

# 추가: Drawdown 비교 차트 (Base vs Regime vs VD+)
tryCatch({
  base_nav <- as.numeric(cumprod(1 + as.numeric(coredata(sim_base$strategy_xts)))) *
              DEFAULT_INITIAL_CAPITAL
  base_dates <- as.Date(index(sim_base$strategy_xts))

  # Regime overlay NAV
  reg_dt <- overlay_sim$DAILY_NAV_DT[, .(Date, NAV_regime = NAV_overlay)]

  # Final NAV
  final_dt <- nav_overlay[, .(Date, NAV_final)]

  # Base NAV 합치기
  base_dt <- data.table(Date = base_dates, NAV_base = base_nav)

  # 3개 NAV 합산 (공통 날짜)
  comb <- Reduce(function(a, b) merge(a, b, by = "Date", all = FALSE),
                 list(base_dt, reg_dt, final_dt))

  dd_fn <- function(nav) { rm <- cummax(nav); pmax((nav - rm) / rm * 100, -100) }

  comb[, DD_base   := dd_fn(NAV_base)]
  comb[, DD_regime := dd_fn(NAV_regime)]
  comb[, DD_final  := dd_fn(NAV_final)]

  dd_long <- melt(comb, id.vars = "Date",
                  measure.vars = c("DD_base", "DD_regime", "DD_final"),
                  variable.name = "Variant", value.name = "Drawdown")
  dd_long[, Variant := factor(Variant,
    levels = c("DD_base", "DD_regime", "DD_final"),
    labels = c("S1 Base (MDD 66.8%)", "Regime Overlay", "VD+ Final"))]

  g_dd <- ggplot(dd_long, aes(x = Date, y = Drawdown, color = Variant)) +
    geom_line(linewidth = 0.5, alpha = 0.85) +
    geom_hline(yintercept = -45, linetype = "dashed", color = "red3", linewidth = 0.8) +
    annotate("text", x = min(dd_long$Date) + 500, y = -47,
             label = "Hard Fail Threshold (-45%)", color = "red3", size = 3.5) +
    scale_color_manual(values = c("S1 Base (MDD 66.8%)" = "gray60",
                                  "Regime Overlay" = "steelblue",
                                  "VD+ Final" = "darkgreen")) +
    labs(title = "STR_1642 VD+: Drawdown Comparison",
         subtitle = "S1 Base vs Regime Overlay vs VD+ (Regime + DD Brake 10/25)",
         x = NULL, y = "Drawdown (%)") +
    theme_minimal(base_size = 11) +
    theme(legend.position = "bottom")

  ggsave(file.path(output_dir, "drawdown_comparison.png"),
         g_dd, width = 12, height = 6, dpi = 150)
  cat("  [Chart] drawdown_comparison.png 저장 완료.\n")
}, error = function(e) cat("[WARN chart]", e$message, "\n"))

# ════════════════════════════════════════════════════════════════
# Phase 7: Performance 저장 + 비교 요약
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 7] Performance CSV + JSON 저장...\n")

perf_all <- rbind(perf_base, perf_overlay, perf_final, perf_bm)
fwrite(perf_all, file.path(output_dir, "performance.csv"))

# Annual returns 비교 (선택)
tryCatch({
  source(file.path(INFRA_DIR, "strategy_analyzer.R"))
  RAWDATA <- copy(RAWDATA_ORIG)
  run_analysis(sim_final, FACTORS, RAWDATA, BM_DT, output_dir, strategy_name = STRATEGY_ID)
}, error = function(e) cat("[WARN analyzer]", e$message, "\n"))

# ════════════════════════════════════════════════════════════════
# Phase 8: Core(STR_1631) 대비 상관 (핵심 — 0.3 미만이어야 함)
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 8] Core(STR_1631) 대비 상관 분석...\n")

corr_val <- NA_real_
tryCatch({
  # STR_1631은 sim_result.rds 대신 daily_nav.csv에 Ret_overlay 보유
  # daily_nav.csv: Date, NAV_base, NAV_overlay, Strategy_Ret, Ret_overlay, MRS, Layer
  core_nav_path <- file.path(SCRIPT_DIR, "..",
                             "STR_1631", "output", "daily_nav.csv")

  if (file.exists(core_nav_path)) {
    core_nav <- fread(core_nav_path)
    core_nav[, Date := as.Date(Date)]
    # STR_1631 overlay 수익률 (월말 기준으로 리샘플)
    # 일별 → 월별 수익률로 변환 (마지막 거래일 누적 수익)
    core_nav[, YM := format(Date, "%Y-%m")]
    core_monthly <- core_nav[, .(
      Date = max(Date),
      Ret_monthly = prod(1 + Ret_overlay) - 1
    ), by = YM]
    setorder(core_monthly, Date)

    strat_ret_vec <- as.numeric(coredata(final_xts))
    strat_dates   <- as.Date(index(final_xts))

    # 전략도 월별로 집계 (이미 월별 리밸런싱이지만 xts는 일별)
    strat_dt <- data.table(Date = strat_dates, Ret = strat_ret_vec)
    strat_dt <- strat_dt[!is.na(Ret)]
    strat_dt[, YM := format(Date, "%Y-%m")]
    strat_monthly <- strat_dt[, .(
      Date = max(Date),
      Ret_monthly = prod(1 + Ret) - 1
    ), by = YM]
    setorder(strat_monthly, Date)

    # 공통 YM 추출
    common_ym <- intersect(core_monthly$YM, strat_monthly$YM)
    if (length(common_ym) >= 36L) {
      cr_c <- core_monthly[YM %in% common_ym, Ret_monthly]
      sr_c <- strat_monthly[YM %in% common_ym, Ret_monthly]
      corr_val <- cor(sr_c, cr_c, use = "complete.obs")
      cat(sprintf("  [Core Corr] STR_1631 대비: %.3f (n=%d개월)\n",
                  corr_val, length(common_ym)))
      cat(sprintf("  [Novelty] max_corr=%.3f → %s\n",
                  abs(corr_val),
                  ifelse(abs(corr_val) < 0.30, "Novelty Bonus +15 ELIGIBLE",
                  ifelse(abs(corr_val) < 0.50, "Novelty Bonus +5~8 eligible", "보너스 없음"))))
    } else {
      cat(sprintf("  [Core Corr] 공통 기간 부족: %d개월\n", length(common_ym)))
    }
  } else {
    cat("  [Core Corr] STR_1631 daily_nav.csv 없음 → 상관 계산 생략.\n")
  }
}, error = function(e) cat("[WARN core corr]", e$message, "\n"))

# ════════════════════════════════════════════════════════════════
# Phase 9: 8대 스트레스 구간 Alpha
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 9] 8대 스트레스 구간 Alpha...\n")

stress_periods <- list(
  list(name = "글로벌 금융위기",       start = "2008-09-01", end = "2009-03-31"),
  list(name = "유럽 재정위기",         start = "2011-07-01", end = "2012-06-30"),
  list(name = "중국 쇼크/원자재 하락", start = "2015-07-01", end = "2016-02-29"),
  list(name = "코로나 충격",           start = "2020-01-01", end = "2020-06-30"),
  list(name = "금리인상 사이클",       start = "2022-01-01", end = "2022-12-31"),
  list(name = "2018 변동성 급등",      start = "2018-10-01", end = "2019-01-31"),
  list(name = "2023 SVB/크레딧 쇼크",  start = "2023-03-01", end = "2023-05-31"),
  list(name = "2024 AI발 반등",        start = "2024-01-01", end = "2024-06-30")
)

strat_ret_vec <- as.numeric(coredata(final_xts))
strat_dates   <- as.Date(index(final_xts))
bm_ret_ts     <- as.numeric(coredata(sim_base$bm_xts))
bm_dates      <- as.Date(index(sim_base$bm_xts))
valid_idx     <- !is.na(strat_ret_vec)

stress_results <- lapply(stress_periods, function(sp) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  idx_s <- strat_dates >= s & strat_dates <= e & valid_idx
  if (sum(idx_s) < 3L) {
    cat(sprintf("  %-30s: 데이터 부족\n", sp$name))
    return(list(name = sp$name, n = 0, strat_ret = NA, bm_ret = NA, alpha = NA))
  }
  sr_cum <- prod(1 + strat_ret_vec[idx_s]) - 1

  # BM 같은 기간
  bm_dates_in <- bm_dates >= s & bm_dates <= e & !is.na(bm_ret_ts)
  bm_cum <- if (sum(bm_dates_in) > 0) prod(1 + bm_ret_ts[bm_dates_in]) - 1 else NA_real_
  alpha <- if (!is.na(bm_cum)) sr_cum - bm_cum else NA_real_

  cat(sprintf("  %-30s: 전략=%+.1f%% BM=%+.1f%% Alpha=%+.1f%%\n",
              sp$name, sr_cum * 100,
              ifelse(is.na(bm_cum), 0, bm_cum) * 100,
              ifelse(is.na(alpha), 0, alpha) * 100))
  list(name = sp$name, n = sum(idx_s),
       strat_ret = round(sr_cum, 4),
       bm_ret    = round(ifelse(is.na(bm_cum), 0, bm_cum), 4),
       alpha     = round(ifelse(is.na(alpha), 0, alpha), 4))
})

saveRDS(stress_results, file.path(output_dir, "stress_analysis.rds"))

# ════════════════════════════════════════════════════════════════
# Phase 10: MDD 판정 + S6 진입 가능 여부
# ════════════════════════════════════════════════════════════════
cat("\n[Phase 10] MDD 판정...\n")

mdd_target  <- 45.0
mdd_achieved <- perf_final$MDD
mdd_pass    <- (mdd_achieved < mdd_target)

cat("==========================================================\n")
cat(sprintf("  STR_1642 VD+: CAGR=%.2f%% | SR=%.3f | MDD=%.1f%%\n",
            perf_final$CAGR, perf_final$Sharpe, perf_final$MDD))
cat(sprintf("  MDD 목표: < %.1f%% → %s\n",
            mdd_target,
            ifelse(mdd_pass, "PASS (S6 진입 가능)", "FAIL (재검토 필요)")))
cat(sprintf("  Core(STR_1631) 상관: %s\n",
            ifelse(is.na(corr_val), "계산 불가",
                   sprintf("%.3f (%s)", corr_val,
                           ifelse(abs(corr_val) < 0.30, "저상관 OK",
                           ifelse(abs(corr_val) < 0.50, "중상관", "고상관 주의"))))))
cat(sprintf("  Grade: %s | Score: %.1f\n",
            hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0))
cat("==========================================================\n")

# JSON 결과 저장
result_json <- list(
  strategy_id    = STRATEGY_ID,
  role           = "RoleBias_Diversifier",
  mutation_type  = "VDplus_Regime20_DDBrake10_25",
  mdd_target     = mdd_target,
  mdd_achieved   = mdd_achieved,
  mdd_pass       = mdd_pass,
  s6_eligible    = mdd_pass && !isTRUE(hurdle$hard_fail),
  corr_core_1631 = corr_val,
  perf_base      = as.list(perf_base),
  perf_overlay   = as.list(perf_overlay),
  perf_final     = as.list(perf_final),
  grade          = hurdle$grade,
  score          = hurdle$total_score %||% hurdle$score %||% 0,
  dd_brake_params = list(trigger = DD_TRIGGER, max_exit = DD_MAX_EXIT, min_exp = DD_MIN_EXP),
  regime_params   = list(caution_threshold = 20L,
                          crisis_mrs = 60, crisis_axes = 5, crisis_consec = 3),
  run_time_sec   = as.numeric(difftime(Sys.time(), t0, units = "secs"))
)
jsonlite::write_json(result_json,
  file.path(output_dir, "vdplus_result.json"),
  auto_unbox = TRUE, pretty = TRUE)

# ════════════════════════════════════════════════════════════════
# Phase 11: 텔레그램 발송 (이모지 필수, 차트 2개)
# ════════════════════════════════════════════════════════════════
tryCatch({
  source(file.path(TELEGRAM_DIR, "telegram_notify.R"))

  # 차트 1: equity_curve.png
  eq_chart <- file.path(output_dir, "equity_curve.png")
  if (file.exists(eq_chart)) {
    tg_send_photo(eq_chart,
      caption = paste0("[Forge] STR_1642 VDplus S5 Mutation\n",
                       "수익률 곡선: S1 Base vs VD+ 최종"))
  }

  # 차트 2: drawdown_comparison.png
  dd_chart <- file.path(output_dir, "drawdown_comparison.png")
  if (file.exists(dd_chart)) {
    tg_send_photo(dd_chart,
      caption = paste0("[Forge] STR_1642 VDplus\n",
                       "Drawdown 비교: Base vs Regime vs VD+"))
  }

  # 결과 메시지
  msg <- paste0(
    "[Forge] STR_1642 VD+ S5 Overlay Mutation 완료\n\n",
    "[ 전략 구성 ]\n",
    "  팩터: AC17 Accrual Reversal + L22 Ret Autocorr + Q04 Piotroski F\n",
    "  유니버스: Expanding-window CAPM Beta 하위 40%\n",
    "  Overlay 1: Regime 3-Layer (Enhanced Caution MRS=20)\n",
    "  Overlay 2: DD Brake (10%/25%, C9 t-1 lag)\n\n",
    "[ 성과 비교 ]\n",
    sprintf("  S1 Base: CAGR=%.1f%% SR=%.2f MDD=%.1f%%\n",
            perf_base$CAGR, perf_base$Sharpe, perf_base$MDD),
    sprintf("  Regime:  CAGR=%.1f%% SR=%.2f MDD=%.1f%%\n",
            perf_overlay$CAGR, perf_overlay$Sharpe, perf_overlay$MDD),
    sprintf("  VD+:     CAGR=%.1f%% SR=%.2f MDD=%.1f%%\n",
            perf_final$CAGR, perf_final$Sharpe, perf_final$MDD),
    "\n[ 판정 ]\n",
    sprintf("  MDD %.1f%% < 45%% 목표: %s\n",
            mdd_achieved, ifelse(mdd_pass, "PASS (S6 진입 가능)", "FAIL")),
    sprintf("  Grade=%s | Score=%.1f\n",
            hurdle$grade, hurdle$total_score %||% hurdle$score %||% 0),
    sprintf("  Core 상관: %s\n",
            ifelse(is.na(corr_val), "미계산",
                   sprintf("%.3f (%s)", corr_val,
                           ifelse(abs(corr_val) < 0.30, "+15 novelty ELIGIBLE",
                           ifelse(abs(corr_val) < 0.50, "+5~8 eligible", "보너스없음")))))
  )
  tg_send(msg)
}, error = function(e) cat("[TG]", e$message, "\n"))

# ════════════════════════════════════════════════════════════════
# Phase 12: QEPM Auto Commit
# ════════════════════════════════════════════════════════════════
if (isTRUE(QEPM_AUTO_COMMIT)) {
  tryCatch({
    qh <- file.path(dirname(dirname(dirname(SCRIPT_DIR))), "qepm", "scripts", "hybrid_mode.R")
    if (file.exists(qh)) {
      source(qh)
      if (exists("hybrid_commit")) {
        hybrid_commit(
          strategy_name  = STRATEGY_ID,
          family         = STRATEGY_FAMILY,
          hurdle_result  = hurdle,
          artifact_paths = list(output_dir)
        )
      }
    }
  }, error = function(e) cat("[QEPM]", e$message, "\n"))
}

elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n=== STR_1642 VDplus Complete. Grade=%s Score=%.1f | MDD=%.1f%% | %.0fs ===\n",
            hurdle$grade,
            hurdle$total_score %||% hurdle$score %||% 0,
            mdd_achieved,
            as.numeric(elapsed)))
