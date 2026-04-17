#==============================================================================
# C19 × V24 Interaction Score — 5-way Comparison Backtest
# Analysis: 분석용 스크립트 (Codex gate 미적용)
#
# 핵심 아이디어:
#   "컨센 좋은데 싼 종목" = C19_Composite_Earnings × V24_Residual_Income 교차
#   이익 추정치 상향(consensus) AND 자본비용 초과 이익(residual income) 동시 충족
#
# Scoring variants:
#   A) Additive:       Z(C19) + Z(V24)       — 둘 다 높으면 좋음
#   B) Multiplicative: Z(C19) × Z(V24)       — 둘 다 높아야 높음 (교차)
#   C) Minimum:        min(Z(C19), Z(V24))   — 양쪽 다 상위여야 선택
#   D) C19 단독
#   E) V24 단독
#
# PIT 준수:
#   C13: Z_Score_Aligned만 사용, 수동 방향 반전 금지
#   C14: Usable_Date <= sig_date (Factor DB 기본 준수)
#   C15: Factor DB via rbindlist bulk preload (loop 내 parquet 로드 금지, L-534)
#   오버레이 없음 (S1 순수 팩터, VT/DD/Regime 금지)
#==============================================================================

cat("=== C19 x V24 Interaction Score Analysis ===\n")
cat("시작 시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ── 0. 인프라 로드 ─────────────────────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ── 1. Factor DB Bulk Preload (원칙 1: rbindlist 1회, 필요 팩터만) ───────────
cat("[Step 1] Factor DB bulk preload — C19 & V24 only\n")

NEEDED <- c("C19_Composite_Earnings", "V24_Residual_Income")

fdb_files <- sort(list.files(
  file.path(CACHE_DIR, "factor_db"),
  pattern = "^factor_db_\\d{6}\\.parquet$",
  full.names = TRUE
))
cat(sprintf("  > %d parquet files found\n", length(fdb_files)))

# C13 준수: Z_Score_Aligned = Z_Score * ic_sign
# IC 방향을 IC history에서 사전 계산 (C13: 수동 방향 반전 금지, IC-driven 방향만)
source(file.path(INFRA_DIR, "factor_db/factor_db_connector.R"))

ic_path <- file.path(CACHE_DIR, "factor_db", "factor_ic_monthly.parquet")
if (file.exists(ic_path)) {
  ic_hist <- as.data.table(read_parquet(ic_path))
  ic_dir <- ic_hist[Factor_Name %in% NEEDED,
                    .(Mean_IC = mean(IC, na.rm = TRUE)), by = Factor_Name]
  ic_dir[, ic_sign := fifelse(Mean_IC >= 0, 1L, -1L)]
  cat(sprintf("  > IC 방향 (C13 준수):\n"))
  for (fn in NEEDED) {
    sgn <- ic_dir[Factor_Name == fn, ic_sign]
    sgn <- if (length(sgn) == 0L) 1L else sgn
    cat(sprintf("    %s: ic_sign=%d (Mean_IC=%.4f)\n",
                fn,
                sgn,
                ic_dir[Factor_Name == fn, Mean_IC]))
  }
} else {
  cat("  > IC history 없음: ic_sign=1 (both factors assumed higher-better)\n")
  ic_dir <- data.table(
    Factor_Name = NEEDED,
    ic_sign     = c(1L, 1L)
  )
}

FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  # C13 준수: Z_Score_Aligned 계산 (직접 parquet 로드이므로 수동 ic_sign 적용)
  dt <- dt[Factor_Name %in% NEEDED]
  if (nrow(dt) == 0L) return(NULL)
  # ic_sign 적용하여 Z_Score_Aligned 생성
  dt <- merge(dt, ic_dir[, .(Factor_Name, ic_sign)],
              by = "Factor_Name", all.x = TRUE)
  dt[is.na(ic_sign), ic_sign := 1L]
  dt[, Z_Score_Aligned := Z_Score * ic_sign]
  # Date 컬럼 확인
  if ("Date" %in% names(dt)) {
    dt[, .(Ticker, Factor_Name, Z_Score_Aligned, Date)]
  } else {
    ym_str <- regmatches(basename(f), regexpr("\\d{6}", basename(f)))
    yr <- as.integer(substr(ym_str, 1, 4))
    mo <- as.integer(substr(ym_str, 5, 6))
    dt[, Date := as.Date(sprintf("%04d-%02d-28", yr, mo))]
    dt[, .(Ticker, Factor_Name, Z_Score_Aligned, Date)]
  }
}), fill = TRUE, use.names = TRUE)

cat(sprintf("  > FDB_ALL: %s rows | %d tickers | %s ~ %s\n",
            format(nrow(FDB_ALL), big.mark = ","),
            uniqueN(FDB_ALL$Ticker),
            min(FDB_ALL$Date), max(FDB_ALL$Date)))

setkey(FDB_ALL, Date, Ticker, Factor_Name)

# ── 2. Wide format + Interaction Score 계산 ──────────────────────────────────
cat("[Step 2] Wide format pivot + interaction scores\n")

wide <- dcast(FDB_ALL,
              Date + Ticker ~ Factor_Name,
              value.var = "Z_Score_Aligned",
              fun.aggregate = mean)

setnames(wide, "C19_Composite_Earnings", "Z_C19", skip_absent = TRUE)
setnames(wide, "V24_Residual_Income",    "Z_V24", skip_absent = TRUE)
setkey(wide, Date, Ticker)

cat(sprintf("  > Wide: %s rows | %d dates | %d tickers\n",
            format(nrow(wide), big.mark = ","),
            uniqueN(wide$Date),
            uniqueN(wide$Ticker)))
cat(sprintf("  > C19 coverage: %.1f%% | V24 coverage: %.1f%%\n",
            mean(!is.na(wide$Z_C19)) * 100,
            mean(!is.na(wide$Z_V24)) * 100))

# Interaction scores (C13: Z_Score_Aligned 기반, 방향 반전 없음)
# A) Additive
wide[, Score_Add  := Z_C19 + Z_V24]
# B) Multiplicative: 둘 다 양수여야 높음
wide[, Score_Mult := Z_C19 * Z_V24]
# C) Minimum: bottleneck 방식
wide[, Score_Min  := pmin(Z_C19, Z_V24, na.rm = FALSE)]
# D/E) 단독
wide[, Score_C19  := Z_C19]
wide[, Score_V24  := Z_V24]

# ── 3. RAWDATA 1회 로드 ────────────────────────────────────────────────────────
cat("[Step 3] RAWDATA 1회 로드\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Ticker, Date)

cat(sprintf("  > RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(RAWDATA), big.mark = ","),
            min(RAWDATA$Date), max(RAWDATA$Date)))

# ── 4. 월별 유동성 필터 사전 계산 (t-1 month, C10 준수) ─────────────────────
cat("[Step 4] 월별 유동성 필터 (t-1 월 평균 거래대금, C10 준수)\n")

LIQ_THRESHOLD <- 2e8  # 2억원

RAWDATA[, Turnover := Close * Vol]
RAWDATA[, YM := format(Date, "%Y%m")]

liq_monthly <- RAWDATA[, .(LIQ_avg = mean(Turnover, na.rm = TRUE)),
                        by = .(YM, Ticker)]

setorder(liq_monthly, Ticker, YM)
liq_monthly[, LIQ_prev := shift(LIQ_avg, 1L, type = "lag"), by = Ticker]
liq_monthly[, LIQ_pass := (!is.na(LIQ_prev)) & (LIQ_prev >= LIQ_THRESHOLD)]

cat(sprintf("  > 유동성 통과율 (평균): %.1f%%\n",
            mean(liq_monthly$LIQ_pass, na.rm = TRUE) * 100))

# ── 5. Factor Date에 유동성 필터 합산 ────────────────────────────────────────
cat("[Step 5] 팩터 테이블 + 유동성 필터 합산\n")

wide[, YM := format(Date, "%Y%m")]
setkey(wide, YM, Ticker)
setkey(liq_monthly, YM, Ticker)

wide_liq <- merge(wide,
                  liq_monthly[, .(YM, Ticker, LIQ_pass)],
                  by = c("YM", "Ticker"),
                  all.x = TRUE)
wide_liq[is.na(LIQ_pass), LIQ_pass := FALSE]

# 2003 이후 필터
wide_liq <- wide_liq[Date >= as.Date("2003-01-01")]
cat(sprintf("  > 2003+ rows: %s | %s ~ %s\n",
            format(nrow(wide_liq), big.mark = ","),
            min(wide_liq$Date), max(wide_liq$Date)))

# ── 6. 5가지 scoring 방식 백테스트 (순차, 각 gc 호출) ────────────────────────
cat("[Step 6] 5-way 백테스트 시작\n\n")

BT_N      <- 20L
BT_COMM   <- 0.0015     # 15bps
BT_BUF    <- list(keep_n = 30L, entry_n = 20L)

SCORE_COLS <- c(
  "Additive"       = "Score_Add",
  "Multiplicative" = "Score_Mult",
  "Minimum"        = "Score_Min",
  "C19_Alone"      = "Score_C19",
  "V24_Alone"      = "Score_V24"
)

results_list <- list()

for (method_name in names(SCORE_COLS)) {
  score_col <- SCORE_COLS[[method_name]]
  cat(sprintf("  [%s] 시작...\n", method_name))

  FACTORS <- wide_liq[
    LIQ_pass == TRUE & !is.na(get(score_col)),
    .(Date, Ticker, Score = get(score_col))
  ]

  if (nrow(FACTORS) == 0L) {
    cat(sprintf("    WARNING: 유효 데이터 없음, skip\n"))
    next
  }
  setkey(FACTORS, Date, Ticker)
  cat(sprintf("    > Signal rows: %s | dates: %d\n",
              format(nrow(FACTORS), big.mark = ","),
              uniqueN(FACTORS$Date)))

  sim <- tryCatch(
    run_monthly_simulation(
      RAWDATA, BM_DT, FACTORS,
      n_holdings    = BT_N,
      commission    = BT_COMM,
      weight_method = "ew",
      buffer_zone   = BT_BUF
    ),
    error = function(e) {
      cat(sprintf("    ERROR: %s\n", conditionMessage(e)))
      NULL
    }
  )

  if (is.null(sim)) next

  perf <- summarise_perf(sim$strategy_xts, label = method_name)
  perf[, Method := method_name]
  results_list[[method_name]] <- list(perf = perf, sim = sim)

  cat(sprintf("    > CAGR=%.1f%% SR=%.3f MDD=%.1f%% Sortino=%.3f WinRate=%.1f%%\n",
              perf$CAGR * 100,
              perf$Sharpe,
              perf$MDD * 100,
              ifelse(is.na(perf$Sortino), 0, perf$Sortino),
              ifelse(is.na(perf$WinRate), 0, perf$WinRate)))
  gc(verbose = FALSE)
}

# ── 7. 결과 요약 테이블 ───────────────────────────────────────────────────────
cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("결과 요약 — 5-way Comparison\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")

perf_all <- rbindlist(lapply(results_list, function(x) x$perf), fill = TRUE)

perf_display <- perf_all[, .(
  Method,
  `CAGR(%)` = round(CAGR * 100, 2),
  SR        = round(Sharpe, 3),
  `MDD(%)`  = round(MDD  * 100, 2),
  Sortino   = round(Sortino, 3),
  `Win(%)`  = round(WinRate, 1)
)]

cat("\n[ Method | CAGR(%) | SR | MDD(%) | Sortino | Win(%) ]\n")
print(perf_display, row.names = FALSE)

# ── 8. 추가 분석 1: 단면 상관 (Spearman, 월별) ───────────────────────────────
cat("\n")
cat(paste0(rep("-", 60), collapse = ""), "\n")
cat("추가 분석 1: C19 vs V24 단면 Spearman 상관 (월별)\n")
cat(paste0(rep("-", 60), collapse = ""), "\n")

cross_cor <- wide_liq[!is.na(Z_C19) & !is.na(Z_V24), {
  if (.N >= 20L) {
    list(n = .N, spearman_r = cor(Z_C19, Z_V24, method = "spearman"))
  } else {
    list(n = .N, spearman_r = NA_real_)
  }
}, by = Date]

cat(sprintf("  분석 월수:    %d\n",   nrow(cross_cor)))
cat(sprintf("  평균 r:       %.4f\n", mean(cross_cor$spearman_r, na.rm = TRUE)))
cat(sprintf("  중간값:       %.4f\n", median(cross_cor$spearman_r, na.rm = TRUE)))
cat(sprintf("  표준편차:     %.4f\n", sd(cross_cor$spearman_r, na.rm = TRUE)))
cat(sprintf("  r > 0 비율:   %.1f%%\n", mean(cross_cor$spearman_r > 0,    na.rm = TRUE) * 100))
cat(sprintf("  r < -0.1:     %.1f%% (독립적 팩터 기준)\n",
            mean(cross_cor$spearman_r < -0.1, na.rm = TRUE) * 100))

# ── 9. 추가 분석 2: 스트레스 구간별 수익률 ───────────────────────────────────
cat("\n")
cat(paste0(rep("-", 60), collapse = ""), "\n")
cat("추가 분석 2: 주요 스트레스 구간 누적 수익률 (%)\n")
cat(paste0(rep("-", 60), collapse = ""), "\n")

STRESS_PERIODS <- list(
  list(name = "GFC (08-09)",        start = "2008-09-01", end = "2009-03-31"),
  list(name = "유럽 재정위기",       start = "2011-07-01", end = "2012-06-30"),
  list(name = "차이나 쇼크",         start = "2015-06-01", end = "2016-01-31"),
  list(name = "코로나 급락",         start = "2020-02-01", end = "2020-04-30"),
  list(name = "금리 급등 (2022)",    start = "2022-01-01", end = "2022-12-31"),
  list(name = "SVB 위기 (2023-Q1)", start = "2023-03-01", end = "2023-05-31"),
  list(name = "2024H1 밸류업전",    start = "2024-01-01", end = "2024-06-30")
)

stress_rows <- list()
for (sp in STRESS_PERIODS) {
  row <- data.table(Period = sp$name)
  for (method_name in names(results_list)) {
    sim_xts <- results_list[[method_name]]$sim$strategy_xts
    if (is.null(sim_xts)) { row[[method_name]] <- NA_real_; next }
    sub <- sim_xts[
      index(sim_xts) >= as.Date(sp$start) &
      index(sim_xts) <= as.Date(sp$end)
    ]
    if (length(sub) < 2L) {
      row[[method_name]] <- NA_real_
    } else {
      row[[method_name]] <- round((prod(1 + as.numeric(sub)) - 1) * 100, 2)
    }
  }
  stress_rows[[sp$name]] <- row
}

stress_tbl <- rbindlist(stress_rows, fill = TRUE)
print(stress_tbl, row.names = FALSE)

# ── 10. 추가 분석 3: Top-20 Overlap ─────────────────────────────────────────
cat("\n")
cat(paste0(rep("-", 60), collapse = ""), "\n")
cat("추가 분석 3: Top-20 Overlap — C19 단독 vs 각 Interaction 방식\n")
cat(paste0(rep("-", 60), collapse = ""), "\n")

overlap_dates <- wide_liq[
  LIQ_pass == TRUE &
  !is.na(Score_C19) & !is.na(Score_Add) &
  !is.na(Score_Mult) & !is.na(Score_Min) & !is.na(Score_V24),
  unique(Date)
]

overlap_results <- lapply(overlap_dates, function(d) {
  sub <- wide_liq[Date == d & LIQ_pass == TRUE]
  if (nrow(sub) < 20L) return(NULL)

  top_c19  <- head(sub[order(-Score_C19),  Ticker], 20L)
  top_v24  <- head(sub[order(-Score_V24),  Ticker], 20L)
  top_add  <- head(sub[order(-Score_Add),  Ticker], 20L)
  top_mult <- head(sub[order(-Score_Mult), Ticker], 20L)
  top_min  <- head(sub[order(-Score_Min),  Ticker], 20L)

  n <- length(top_c19)
  data.table(
    Date             = d,
    Ovlp_C19_Add    = length(intersect(top_c19, top_add))  / n,
    Ovlp_C19_Mult   = length(intersect(top_c19, top_mult)) / n,
    Ovlp_C19_Min    = length(intersect(top_c19, top_min))  / n,
    Ovlp_C19_V24    = length(intersect(top_c19, top_v24))  / n
  )
})

overlap_dt <- rbindlist(Filter(Negate(is.null), overlap_results), fill = TRUE)

cat(sprintf("  분석 월수: %d\n", nrow(overlap_dt)))
cat(sprintf("  C19 vs Additive   overlap: %.1f%%\n",
            mean(overlap_dt$Ovlp_C19_Add,  na.rm = TRUE) * 100))
cat(sprintf("  C19 vs Multiplicative:     %.1f%%\n",
            mean(overlap_dt$Ovlp_C19_Mult, na.rm = TRUE) * 100))
cat(sprintf("  C19 vs Minimum:            %.1f%%\n",
            mean(overlap_dt$Ovlp_C19_Min,  na.rm = TRUE) * 100))
cat(sprintf("  C19 vs V24 (단독):         %.1f%%\n",
            mean(overlap_dt$Ovlp_C19_V24,  na.rm = TRUE) * 100))
cat("\n  [해석] 100%%=완전동일, 0%%=완전다름\n")
cat("  Multiplicative/Minimum이 낮을수록 Interaction이 독립적 종목 선택\n")

# ── 11. 최종 결론 ─────────────────────────────────────────────────────────────
cat("\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")
cat("최종 결론\n")
cat(paste0(rep("=", 80), collapse = ""), "\n")

if (nrow(perf_all) > 0L) {
  best_sr   <- perf_all[which.max(Sharpe)]
  best_cagr <- perf_all[which.max(CAGR)]
  best_mdd  <- perf_all[which.min(MDD)]

  cat(sprintf("  최고 Sharpe:  %s  (SR=%.3f)\n",  best_sr$Method,   best_sr$Sharpe))
  cat(sprintf("  최고 CAGR:    %s  (%.1f%%)\n",   best_cagr$Method, best_cagr$CAGR * 100))
  cat(sprintf("  최저 MDD:     %s  (%.1f%%)\n",   best_mdd$Method,  best_mdd$MDD  * 100))
}

avg_r <- mean(cross_cor$spearman_r, na.rm = TRUE)
cat(sprintf("\n  C19 × V24 단면 평균 상관 r = %.4f\n", avg_r))
if (avg_r < 0.2) {
  cat("  => 낮은 상관: Interaction이 차별화된 종목군 선택 가능성 높음\n")
} else if (avg_r < 0.5) {
  cat("  => 중간 상관: Interaction 효과 부분적, Additive와 유사 결과 예상\n")
} else {
  cat("  => 높은 상관: 두 팩터가 유사한 종목 선택 → Interaction 효과 제한적\n")
}

cat("\n완료 시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
