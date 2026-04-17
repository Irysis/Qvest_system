#==============================================================================
# MRS Regime Engine v7.1 — Stress Period Detection Analysis
# 8대 스트레스 구간 사전 식별 정량 분석
#
# Author: Forge Agent
# Date:   2026-04-08
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
REGIME_DAILY_CACHE <- file.path(CACHE_DIR, "regime_daily_v2.parquet")
BM_CACHE     <- file.path(CACHE_DIR, "benchmark.parquet")

cat("=== MRS Stress Period Detection Analysis ===\n\n")

# ------------------------------------------------------------------------------
# 1. Load regime cache
# ------------------------------------------------------------------------------
cat("[1] Loading REGIME cache...\n")
REGIME <- as.data.table(read_parquet(REGIME_DAILY_CACHE))
REGIME[, Date := as.Date(Date)]
setorder(REGIME, Date)
cat(sprintf("    REGIME rows: %d  |  Date range: %s ~ %s\n\n",
            nrow(REGIME), min(REGIME$Date), max(REGIME$Date)))

# MRS 컬럼 확인
if (!"MRS" %in% names(REGIME)) {
  # 혹시 다른 컬럼명 사용하는 경우
  cat("Available columns:\n"); print(names(REGIME)); stop("MRS column not found")
}

# ------------------------------------------------------------------------------
# 2. Load benchmark returns (for False Positive / Lead Time analysis)
# ------------------------------------------------------------------------------
cat("[2] Loading Benchmark returns...\n")
BM <- as.data.table(read_parquet(BM_CACHE))
BM[, Date := as.Date(Date)]
setorder(BM, Date)
# BM_Ret 컬럼 파악
bm_col <- intersect(c("BM_Ret", "Ret", "Return", "ret"), names(BM))[1]
if (is.na(bm_col)) { cat("BM columns:"); print(names(BM)); stop("No return col") }
setnames(BM, bm_col, "BM_Ret", skip_absent = TRUE)
cat(sprintf("    BM rows: %d  |  Date range: %s ~ %s\n\n",
            nrow(BM), min(BM$Date), max(BM$Date)))

# REGIME에 BM_Ret merge
REGIME <- merge(REGIME, BM[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

# ------------------------------------------------------------------------------
# 3. 8대 스트레스 구간 정의
# ------------------------------------------------------------------------------
stress_periods <- list(
  list(label = "9/11 테러",      start = "2001-09-11", end = "2001-11-30"),
  list(label = "GFC (금융위기)", start = "2007-10-01", end = "2009-03-09"),
  list(label = "유럽재정위기",   start = "2011-07-01", end = "2011-12-31"),
  list(label = "차이나쇼크",     start = "2015-06-15", end = "2016-02-29"),
  list(label = "미중무역전쟁",   start = "2018-03-01", end = "2018-12-31"),
  list(label = "COVID 충격",     start = "2020-02-20", end = "2020-03-23"),
  list(label = "금리인상 충격",  start = "2022-01-03", end = "2022-10-12"),
  list(label = "이란전쟁 리스크",start = "2026-03-01", end = "2026-04-08")
)

leads <- c(1L, 5L, 10L, 20L)

# ------------------------------------------------------------------------------
# 4. Hit Rate 분석
# ------------------------------------------------------------------------------
cat("=== [SECTION 1] 8대 스트레스 구간 MRS 사전 식별 (Hit Rate) ===\n\n")

hit_table <- rbindlist(lapply(stress_periods, function(sp) {
  start_dt <- as.Date(sp$start)
  end_dt   <- as.Date(sp$end)

  # 해당 구간 내 BM 최대 낙폭
  regime_period <- REGIME[Date >= start_dt & Date <= end_dt]
  bm_ret_sum    <- NA_real_
  if (nrow(regime_period) > 0 && "BM_Ret" %in% names(regime_period)) {
    cum_ret <- cumprod(1 + replace(regime_period$BM_Ret, is.na(regime_period$BM_Ret), 0))
    bm_ret_sum <- min(cum_ret) - 1  # 기간 내 최대 낙폭 (running min)
  }

  # 최대 낙폭 시점 (실제 저점 날짜)
  trough_date <- NA
  if (nrow(regime_period) > 0 && !is.na(bm_ret_sum)) {
    cum_ret_vec <- cumprod(1 + replace(regime_period$BM_Ret, is.na(regime_period$BM_Ret), 0))
    trough_idx  <- which.min(cum_ret_vec)
    trough_date <- regime_period$Date[trough_idx]
  }

  rows <- lapply(leads, function(lead) {
    check_date <- start_dt - lead

    # 해당 날짜 이전 최근 REGIME 데이터 (roll join)
    avail <- REGIME[Date <= check_date]
    if (nrow(avail) == 0) {
      return(data.table(
        label      = sp$label,
        start      = start_dt,
        lead_days  = lead,
        check_date = check_date,
        MRS        = NA_real_,
        signal     = "DATA_NA",
        hit        = NA,
        bm_max_dd  = bm_ret_sum,
        trough_date= as.Date(trough_date)
      ))
    }
    last_row <- avail[.N]
    mrs_val  <- last_row$MRS

    signal <- if (is.na(mrs_val)) "DATA_NA" else
              if (mrs_val >= 60) "CRISIS" else
              if (mrs_val >= 20) "CAUTION" else "NORMAL"

    data.table(
      label       = sp$label,
      start       = start_dt,
      lead_days   = lead,
      check_date  = check_date,
      MRS         = round(mrs_val, 1),
      signal      = signal,
      hit         = (!is.na(mrs_val) && mrs_val >= 20),
      bm_max_dd   = round(bm_ret_sum * 100, 1),
      trough_date = as.Date(trough_date)
    )
  })
  rbindlist(rows)
}))

# 출력 — 구간별 표
for (sp in stress_periods) {
  sub <- hit_table[label == sp$label]
  cat(sprintf("--- %s (시작: %s, 기간내 최대낙폭: %.1f%%) ---\n",
              sp$label, sub$start[1],
              if (!is.na(sub$bm_max_dd[1])) sub$bm_max_dd[1] else NA))
  for (i in seq_len(nrow(sub))) {
    row <- sub[i]
    cat(sprintf("  %2dd 전 (%s): MRS = %s  [%s]%s\n",
                row$lead_days,
                row$check_date,
                if (is.na(row$MRS)) "N/A" else sprintf("%.1f", row$MRS),
                row$signal,
                if (!is.na(row$hit) && row$hit) " <- HIT" else ""))
  }
  cat(sprintf("  저점 날짜: %s\n\n", sub$trough_date[1]))
}

# 전체 Hit Rate (20일 전 기준)
hit_20d <- hit_table[lead_days == 20 & !is.na(hit)]
hit_rate_20 <- mean(hit_20d$hit) * 100
hit_rate_10 <- mean(hit_table[lead_days == 10 & !is.na(hit)]$hit) * 100
hit_rate_5  <- mean(hit_table[lead_days == 5  & !is.na(hit)]$hit) * 100
hit_rate_1  <- mean(hit_table[lead_days == 1  & !is.na(hit)]$hit) * 100

cat(sprintf("=== 전체 Hit Rate (Caution/Crisis 진입 기준) ===\n"))
cat(sprintf("  1일 전:  %.1f%% (%d/%d)\n", hit_rate_1,
            sum(hit_table[lead_days==1 & !is.na(hit)]$hit),
            nrow(hit_table[lead_days==1 & !is.na(hit)])))
cat(sprintf("  5일 전:  %.1f%% (%d/%d)\n", hit_rate_5,
            sum(hit_table[lead_days==5 & !is.na(hit)]$hit),
            nrow(hit_table[lead_days==5 & !is.na(hit)])))
cat(sprintf("  10일 전: %.1f%% (%d/%d)\n", hit_rate_10,
            sum(hit_table[lead_days==10 & !is.na(hit)]$hit),
            nrow(hit_table[lead_days==10 & !is.na(hit)])))
cat(sprintf("  20일 전: %.1f%% (%d/%d)\n\n", hit_rate_20,
            sum(hit_20d$hit), nrow(hit_20d)))

# ------------------------------------------------------------------------------
# 5. Lead Time 분석
#    스트레스 구간 최대 낙폭 시점 vs MRS 최초 Caution(>=20) 진입 시점
# ------------------------------------------------------------------------------
cat("=== [SECTION 2] Lead Time 분석 (저점 대비 MRS 첫 Caution 진입일) ===\n\n")

lead_time_results <- rbindlist(lapply(stress_periods, function(sp) {
  start_dt <- as.Date(sp$start)
  end_dt   <- as.Date(sp$end)

  # 기간 내 저점 날짜
  regime_period <- REGIME[Date >= start_dt & Date <= end_dt]
  if (nrow(regime_period) == 0 || all(is.na(regime_period$BM_Ret))) {
    return(data.table(label = sp$label, trough_date = NA, first_caution = NA, lead_days = NA_integer_))
  }
  cum_ret   <- cumprod(1 + replace(regime_period$BM_Ret, is.na(regime_period$BM_Ret), 0))
  trough_dt <- regime_period$Date[which.min(cum_ret)]

  # 저점 이전 구간에서 MRS 최초 Caution 진입 날짜
  # (start보다 최대 1년 전부터 탐색)
  search_from <- start_dt - 252L
  window_data <- REGIME[Date >= search_from & Date <= trough_dt]
  caution_rows <- window_data[!is.na(MRS) & MRS >= 20]

  if (nrow(caution_rows) == 0) {
    cat(sprintf("  %s: MRS Caution 미발생 (저점: %s)\n", sp$label, trough_dt))
    return(data.table(label = sp$label, trough_date = trough_dt,
                      first_caution = NA, lead_days = NA_integer_))
  }
  first_caution_dt <- caution_rows$Date[1]
  lead_d           <- as.integer(trough_dt - first_caution_dt)

  cat(sprintf("  %s: 저점=%s, 첫 Caution=%s (MRS=%.1f), Lead=%dd\n",
              sp$label, trough_dt, first_caution_dt,
              caution_rows$MRS[1], lead_d))

  data.table(label        = sp$label,
             trough_date  = trough_dt,
             first_caution= first_caution_dt,
             lead_days    = lead_d)
}))

valid_leads <- lead_time_results[!is.na(lead_days)]$lead_days
avg_lead    <- if (length(valid_leads) > 0) mean(valid_leads) else NA_real_
med_lead    <- if (length(valid_leads) > 0) median(valid_leads) else NA_real_

cat(sprintf("\n  평균 Lead Time: %.1f일\n", avg_lead))
cat(sprintf("  중앙값 Lead Time: %.1f일\n\n", med_lead))

# ------------------------------------------------------------------------------
# 6. False Positive Rate
#    MRS >= 20(Caution) 이후 30일 BM forward return >= -5% (낙폭 없음)
# ------------------------------------------------------------------------------
cat("=== [SECTION 3] False Positive Rate ===\n\n")

# Caution 시작 이벤트 탐색 (연속 Caution의 첫 날만)
setorder(REGIME, Date)
REGIME[, prev_MRS := shift(MRS, 1, type = "lag")]
caution_starts <- REGIME[!is.na(MRS) & MRS >= 20 &
                          (is.na(prev_MRS) | prev_MRS < 20)]

cat(sprintf("  전체 Caution 시작 이벤트: %d건\n", nrow(caution_starts)))

if (nrow(caution_starts) > 0 && "BM_Ret" %in% names(REGIME)) {
  fp_results <- lapply(seq_len(nrow(caution_starts)), function(i) {
    ev_date    <- caution_starts$Date[i]
    fwd_end    <- ev_date + 30L
    fwd_data   <- REGIME[Date > ev_date & Date <= fwd_end & !is.na(BM_Ret)]

    if (nrow(fwd_data) == 0) return(NA)

    fwd_cum <- prod(1 + fwd_data$BM_Ret) - 1
    # False Positive = BM 30일 forward return >= -5% (심각한 낙폭 없음)
    as.integer(fwd_cum >= -0.05)
  })

  fp_vec        <- unlist(fp_results)
  fp_vec        <- fp_vec[!is.na(fp_vec)]
  fp_rate       <- mean(fp_vec) * 100
  true_alarm    <- 100 - fp_rate

  cat(sprintf("  False Positive (30일 BM > -5%%): %.1f%% (%d/%d)\n",
              fp_rate, sum(fp_vec == 1), length(fp_vec)))
  cat(sprintf("  True Alarm Rate:                  %.1f%%\n\n", true_alarm))
} else {
  cat("  BM_Ret 데이터 부족으로 False Positive 계산 불가\n\n")
  fp_rate    <- NA_real_
  true_alarm <- NA_real_
}

# ------------------------------------------------------------------------------
# 7. Crisis-level Hit Rate (MRS >= 60)
# ------------------------------------------------------------------------------
cat("=== [SECTION 4] Crisis-level (MRS>=60) 발생 구간별 확인 ===\n\n")

crisis_20d <- hit_table[lead_days == 20]
for (i in seq_len(nrow(crisis_20d))) {
  row <- crisis_20d[i]
  crisis_flag <- !is.na(row$MRS) && row$MRS >= 60
  cat(sprintf("  %s: MRS=%.1f [%s]\n",
              row$label,
              if (is.na(row$MRS)) 0 else row$MRS,
              if (crisis_flag) "CRISIS" else if (!is.na(row$MRS) && row$MRS >= 20) "CAUTION" else "NORMAL"))
}

# 구간 내 최대 MRS 확인
cat("\n  [구간 내 MRS 최고점]\n")
for (sp in stress_periods) {
  start_dt <- as.Date(sp$start)
  end_dt   <- as.Date(sp$end)
  period   <- REGIME[Date >= start_dt & Date <= end_dt]
  if (nrow(period) > 0) {
    max_mrs  <- max(period$MRS, na.rm = TRUE)
    max_date <- period$Date[which.max(period$MRS)]
    cat(sprintf("  %s: 최대 MRS=%.1f (%s)\n", sp$label, max_mrs, max_date))
  }
}

# ------------------------------------------------------------------------------
# 8. 종합 판정
# ------------------------------------------------------------------------------
cat("\n\n")
cat("=============================================================\n")
cat("  MRS Regime Engine v7.1 — 신뢰도 종합 판정\n")
cat("=============================================================\n")
cat(sprintf("  Hit Rate (20일 전 기준): %.1f%%\n",  hit_rate_20))
cat(sprintf("  Hit Rate (10일 전 기준): %.1f%%\n",  hit_rate_10))
cat(sprintf("  Hit Rate (5일 전 기준):  %.1f%%\n",  hit_rate_5))
cat(sprintf("  Hit Rate (1일 전 기준):  %.1f%%\n",  hit_rate_1))
cat(sprintf("  평균 Lead Time:          %.1f일\n",   avg_lead))
cat(sprintf("  중앙값 Lead Time:        %.1f일\n",   med_lead))
if (!is.na(fp_rate)) {
  cat(sprintf("  False Positive Rate:     %.1f%%\n", fp_rate))
  cat(sprintf("  True Alarm Rate:         %.1f%%\n", true_alarm))
}
cat("\n")

# 판정 로직
reliability <- if (is.na(hit_rate_20)) "판단불가" else
               if (hit_rate_20 >= 75 && (is.na(fp_rate) || fp_rate <= 40)) "STRONG" else
               if (hit_rate_20 >= 50) "MODERATE" else "WEAK"

cat(sprintf("  종합 판정: %s\n", reliability))

if (reliability == "STRONG") {
  cat("  해석: MRS가 주요 스트레스 구간을 20일 전부터 높은 확률로 사전 식별.\n")
  cat("        Caution/Crisis 신호의 신뢰성 높음. S5 Overlay 활용 권장.\n")
} else if (reliability == "MODERATE") {
  cat("  해석: MRS가 부분적으로 스트레스 구간을 사전 식별.\n")
  cat("        특정 구간(갑작스러운 충격류)에 한계 존재.\n")
} else {
  cat("  해석: MRS 사전 식별력 부족. Regime 엔진 보완 필요.\n")
}

cat("=============================================================\n\n")

cat("[DONE] MRS stress detection analysis complete.\n")
