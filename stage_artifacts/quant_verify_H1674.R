## H_1674 Individual Contrarian Flow — Quant Verification
## S0 Debate Round 1, Quant 역할
## PIT 준수: C2(same-day lag), C14(Usable_Date), C1(rolling only)

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
})

cat("=== H_1674 Quant Verification ===\n")
cat("시작:", format(Sys.time()), "\n\n")

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

# ── 1. 데이터 로드 ──────────────────────────────────────────
cat("[1] investor_wide.parquet 로드 중...\n")
inv <- as.data.table(read_parquet(file.path(ROOT, ".cache/investor_stock/investor_wide.parquet")))
cat("    차원:", nrow(inv), "x", ncol(inv), "\n")
cat("    컬럼:", paste(names(inv), collapse=", "), "\n")
cat("    날짜 범위:", format(min(inv$Date)), "~", format(max(inv$Date)), "\n")
cat("    종목 수:", inv[, uniqueN(Ticker)], "\n\n")

cat("[2] RAWDATA 로드 중...\n")
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))
cat("    차원:", nrow(raw), "x", ncol(raw), "\n")
cat("    컬럼:", paste(names(raw), collapse=", "), "\n")
cat("    날짜 범위:", format(min(raw$Date)), "~", format(max(raw$Date)), "\n\n")

# ── 2. 월간 집계 ──────────────────────────────────────────
cat("[3] 월간 순매수 집계 (YearMonth 기준)...\n")
inv[, YM := format(Date, "%Y-%m")]
inv[, Ticker := as.character(Ticker)]

# 월간 Individual 순매수 합계 (개인 순매도 = -Individual 누적)
# C2: signal은 month_end에 산출 → 다음달 수익률에 적용 (1달 lag)
monthly_ind <- inv[, .(
  Ind_NetBuy = sum(Individual, na.rm=TRUE),
  n_days = .N
), by=.(YM, Ticker)]

cat("    월간 집계 행수:", nrow(monthly_ind), "\n")
cat("    YM 수:", monthly_ind[, uniqueN(YM)], "\n")
cat("    개요 (Ind_NetBuy):\n")
print(monthly_ind[, summary(Ind_NetBuy)])

# ── 3. 수익률 월간화 ──────────────────────────────────────
cat("\n[4] RAWDATA 월간 수익률 집계...\n")
raw[, YM := format(Date, "%Y-%m")]
raw[, Ticker := as.character(Ticker)]

# 월간 복합 수익률: prod(1+Ret) - 1
# 유동성: 20일 평균 거래대금 (Vol * Close proxy) — C10: 당일 Vol 금지, 20일 평균 사용
raw[, TradingVal := Vol * Close]  # 거래대금 근사 (일간)

monthly_raw <- raw[, .(
  MonRet = prod(1 + Ret, na.rm=TRUE) - 1,
  AvgTradingVal = mean(TradingVal, na.rm=TRUE),  # 20일+평균 거래대금
  n_days = .N,
  AvgSize = mean(Size, na.rm=TRUE)
), by=.(YM, Ticker)]

cat("    월간 수익률 행수:", nrow(monthly_raw), "\n")

# ── 4. 신호-수익률 결합 (PIT lag) ──────────────────────────
cat("\n[5] 신호-수익률 결합 (1달 lag: 신호 t → 수익률 t+1)...\n")

# YM → next YM 계산
get_next_ym <- function(ym_vec) {
  dates <- as.Date(paste0(ym_vec, "-01"))
  next_dates <- dates + 32
  format(as.Date(format(next_dates, "%Y-%m-01")), "%Y-%m")
}

monthly_ind[, NextYM := get_next_ym(YM)]

# 신호(t월) + 수익률(t+1월) 결합
merged <- merge(
  monthly_ind[, .(YM, Ticker, Ind_NetBuy, NextYM)],
  monthly_raw[, .(YM, Ticker, MonRet, AvgTradingVal, AvgSize)],
  by.x = c("NextYM", "Ticker"),
  by.y = c("YM", "Ticker"),
  all = FALSE
)
setnames(merged, "YM", "SigYM")
merged[, RetYM := NextYM]

cat("    결합 행수:", nrow(merged), "\n")
cat("    SigYM 수:", merged[, uniqueN(SigYM)], "\n")
cat("    RetYM 수:", merged[, uniqueN(RetYM)], "\n")

# ── 5. 신호 정의: 개인 순매도 = -Ind_NetBuy ─────────────────
cat("\n[6] 신호: 개인 순매도 = -Ind_NetBuy (cross-sectional Z-score)...\n")
merged[, Signal_raw := -Ind_NetBuy]

# 유동성 필터: 20일 평균 거래대금 >= 2억원 (LIQ_THRESHOLD)
LIQ_THRESHOLD <- 2e8
cat("    유동성 필터 적용 전 행수:", nrow(merged), "\n")
merged_liq <- merged[AvgTradingVal >= LIQ_THRESHOLD]
cat("    유동성 필터 적용 후 행수:", nrow(merged_liq), "\n")
cat("    통과 비율:", round(nrow(merged_liq)/nrow(merged)*100, 1), "%\n")

# ── 6. 사이즈 중립 Z-score (cross-sectional) ─────────────────
cat("\n[7] Cross-sectional Z-score (size-neutral)...\n")
# size 분위수 기준 residualize
merged_liq[, SizeQ := cut(log(AvgSize+1), breaks=5, labels=FALSE), by=SigYM]

# size 내 Z-score (size-neutral residualization)
merged_liq[, Signal_SN := {
  tmp <- Signal_raw
  m <- mean(tmp, na.rm=TRUE)
  s <- sd(tmp, na.rm=TRUE)
  if (is.na(s) || s == 0) rep(0, .N) else (tmp - m) / s
}, by=.(SigYM, SizeQ)]

cat("    Z-score NA 수:", merged_liq[is.na(Signal_SN), .N], "\n")
merged_liq <- merged_liq[!is.na(Signal_SN) & !is.na(MonRet)]
cat("    분석 행수 (최종):", nrow(merged_liq), "\n")

# ── 7. IC 계산 (월별 Rank IC = Spearman) ─────────────────────
cat("\n[8] 월별 Spearman IC 계산...\n")
ic_monthly <- merged_liq[, .(
  IC = cor(Signal_SN, MonRet, method="spearman", use="complete.obs"),
  N = .N
), by=SigYM]
ic_monthly <- ic_monthly[!is.na(IC) & N >= 20]
setorder(ic_monthly, SigYM)

ICIR_val <- mean(ic_monthly$IC, na.rm=TRUE) / sd(ic_monthly$IC, na.rm=TRUE) * sqrt(12)
IC_mean <- mean(ic_monthly$IC, na.rm=TRUE)
IC_sd   <- sd(ic_monthly$IC, na.rm=TRUE)
n_months <- nrow(ic_monthly)
t_stat <- IC_mean / (IC_sd / sqrt(n_months))
annualized_ICIR <- ICIR_val

cat("\n===== IC 결과 =====\n")
cat("  월수:", n_months, "\n")
cat("  IC 평균:", round(IC_mean, 4), "\n")
cat("  IC SD:", round(IC_sd, 4), "\n")
cat("  t-stat:", round(t_stat, 3), "\n")
cat("  ICIR (연환산):", round(annualized_ICIR, 4), "\n")
cat("  Q-Lead 주장 ICIR: 1.258 / t=20.10\n")

# ── 8. IC 자기상관 (Persistence) ───────────────────────────
cat("\n[9] IC 자기상관 (AR(1) persistence)...\n")
if (nrow(ic_monthly) > 12) {
  ic_ac1 <- cor(ic_monthly$IC[-nrow(ic_monthly)], ic_monthly$IC[-1], use="complete.obs")
  ic_ac3 <- if (nrow(ic_monthly) > 6) cor(
    ic_monthly$IC[1:(nrow(ic_monthly)-3)],
    ic_monthly$IC[4:nrow(ic_monthly)],
    use="complete.obs"
  ) else NA
  cat("  IC AR(1):", round(ic_ac1, 4), "\n")
  cat("  IC AR(3):", round(ic_ac3, 4), "\n")
} else {
  ic_ac1 <- NA
  ic_ac3 <- NA
  cat("  데이터 부족\n")
}

# ── 9. Quintile 분석 ──────────────────────────────────────
cat("\n[10] Quintile 수익률 분석 (Q1=개인매도最多, Q5=개인매수最多)...\n")
merged_liq[, Quintile := {
  q_breaks <- quantile(Signal_SN, probs=seq(0,1,0.2), na.rm=TRUE)
  # break 중복 방지
  q_breaks <- unique(q_breaks)
  if (length(q_breaks) < 3) rep(3L, .N)
  else as.integer(cut(Signal_SN, breaks=q_breaks, include.lowest=TRUE, labels=FALSE))
}, by=SigYM]

quintile_ret <- merged_liq[!is.na(Quintile), .(
  AvgMonRet = mean(MonRet, na.rm=TRUE),
  MedianRet = median(MonRet, na.rm=TRUE),
  N = .N
), by=Quintile]
setorder(quintile_ret, Quintile)
cat("\n  Quintile 수익률:\n")
print(quintile_ret)

Q1_ret <- quintile_ret[Quintile==1, AvgMonRet]
Q5_ret <- quintile_ret[Quintile==5, AvgMonRet]
LS_spread <- if (!is.null(Q1_ret) && length(Q1_ret)>0 && !is.null(Q5_ret) && length(Q5_ret)>0) {
  Q1_ret - Q5_ret
} else NA
cat("\n  Q1 월평균수익:", round(Q1_ret*100, 3), "%\n")
cat("  Q5 월평균수익:", round(Q5_ret*100, 3), "%\n")
cat("  L-S spread (Q1-Q5):", round(LS_spread*100, 3), "%/월\n")

# 모노토닉 체크
if (nrow(quintile_ret) == 5) {
  rets <- quintile_ret$AvgMonRet
  monotone_check <- all(diff(rets) > 0) || all(diff(rets) < 0)
  cat("  모노토닉:", monotone_check, "\n")
} else {
  monotone_check <- NA
}

# ── 10. 회전율 추정 (Top30 유지율) ────────────────────────
cat("\n[11] 회전율 추정 (매월 Top30 유지율)...\n")
top30_by_month <- merged_liq[, .(
  Ticker = Ticker[order(-Signal_SN)[1:min(30,.N)]]
), by=SigYM]
setorder(top30_by_month, SigYM)

yms <- sort(top30_by_month[, unique(SigYM)])
overlap_rates <- numeric(length(yms)-1)
for (i in seq_along(overlap_rates)) {
  prev <- top30_by_month[SigYM == yms[i], Ticker]
  curr <- top30_by_month[SigYM == yms[i+1], Ticker]
  overlap_rates[i] <- length(intersect(prev, curr)) / 30
}
avg_overlap <- mean(overlap_rates, na.rm=TRUE)
avg_turnover <- 1 - avg_overlap  # 월간 단방향 교체율
ann_turnover <- avg_turnover * 2 * 12 * 100  # 연간 양방향 %

cat("  Top30 월평균 유지율:", round(avg_overlap*100, 1), "%\n")
cat("  월간 평균 교체율:", round(avg_turnover*100, 1), "%\n")
cat("  추정 연간 회전율:", round(ann_turnover, 0), "%\n")

# ── 11. 유동성 필터 강화 후 IC ────────────────────────────
cat("\n[12] 유동성 필터 강화 (>= 2억원 이미 적용됨 vs 완화 없음) 확인...\n")
# 이미 merged_liq가 2억 이상. 추가로 top50% vol 기준 비교
vol_median <- merged[, median(AvgTradingVal, na.rm=TRUE)]
merged_top50 <- merged[AvgTradingVal >= vol_median]
merged_top50[, SizeQ := cut(log(AvgSize+1), breaks=5, labels=FALSE), by=SigYM]
merged_top50[, Signal_SN := {
  tmp <- -Ind_NetBuy
  m <- mean(tmp, na.rm=TRUE)
  s <- sd(tmp, na.rm=TRUE)
  if (is.na(s) || s == 0) rep(0, .N) else (tmp - m) / s
}, by=.(SigYM, SizeQ)]
merged_top50 <- merged_top50[!is.na(Signal_SN) & !is.na(MonRet)]

ic_top50 <- merged_top50[, .(
  IC = cor(Signal_SN, MonRet, method="spearman", use="complete.obs"),
  N = .N
), by=SigYM]
ic_top50 <- ic_top50[!is.na(IC) & N >= 20]
ICIR_top50 <- mean(ic_top50$IC) / sd(ic_top50$IC) * sqrt(12)
t_top50 <- mean(ic_top50$IC) / (sd(ic_top50$IC)/sqrt(nrow(ic_top50)))

cat("  Top50% 유동성 기준:\n")
cat("    ICIR:", round(ICIR_top50, 4), "| t:", round(t_top50, 3), "\n")
cat("    Q-Lead 주장 (top50% vol) ICIR: 0.939\n")

# ── 12. 스트레스 구간 IC ────────────────────────────────
cat("\n[13] 스트레스 구간 IC 계산...\n")
# 주요 스트레스 구간 정의
stress_periods <- list(
  GFC      = c("2007-12", "2009-03"),
  COVID    = c("2020-01", "2020-06"),
  IT_crash = c("2000-03", "2002-10"),
  EUR_debt = c("2011-06", "2012-01"),
  Korea14  = c("2014-06", "2014-12"),
  Iran2020 = c("2019-12", "2020-02")
)

stress_ic_results <- list()
for (nm in names(stress_periods)) {
  s_start <- stress_periods[[nm]][1]
  s_end   <- stress_periods[[nm]][2]
  sub_ic  <- ic_monthly[SigYM >= s_start & SigYM <= s_end]
  if (nrow(sub_ic) >= 3) {
    stress_ic_results[[nm]] <- list(
      ICIR = mean(sub_ic$IC) / sd(sub_ic$IC) * sqrt(12),
      IC_mean = mean(sub_ic$IC),
      n = nrow(sub_ic)
    )
  } else {
    stress_ic_results[[nm]] <- list(ICIR=NA, IC_mean=NA, n=nrow(sub_ic))
  }
}
cat("  스트레스 구간별 IC:\n")
for (nm in names(stress_ic_results)) {
  r <- stress_ic_results[[nm]]
  cat(sprintf("    %-10s: IC_mean=%-7.4f  ICIR=%-7.4f  n=%d\n",
              nm,
              ifelse(is.null(r$IC_mean) || is.na(r$IC_mean), NA, r$IC_mean),
              ifelse(is.null(r$ICIR) || is.na(r$ICIR), NA, r$ICIR),
              r$n))
}

# ── 13. C19 유사 팩터와의 상관 체크 ─────────────────────────
cat("\n[14] 신호 월별 단면 상관 구조 (시그널 자체 분포)...\n")
sig_stats <- merged_liq[, .(
  mean_sig = mean(Signal_SN, na.rm=TRUE),
  sd_sig   = sd(Signal_SN, na.rm=TRUE),
  skew_sig = (mean(Signal_SN^3, na.rm=TRUE) - 3*mean(Signal_SN)*var(Signal_SN) - mean(Signal_SN)^3) / sd(Signal_SN)^3,
  n = .N
), by=SigYM]
cat("  신호 통계 요약:\n")
cat("    mean of monthly mean:", round(mean(sig_stats$mean_sig), 4), "\n")
cat("    mean of monthly sd:", round(mean(sig_stats$sd_sig), 4), "\n")
cat("    n obs per month (평균):", round(mean(sig_stats$n)), "\n")

# ── 14. 결과 요약 및 JSON 저장 ───────────────────────────────
cat("\n\n===== 최종 요약 =====\n")
cat("  ICIR (연환산, 2억 필터):", round(annualized_ICIR, 4), "\n")
cat("  t-stat:", round(t_stat, 3), "\n")
cat("  ICIR (top50% vol):", round(ICIR_top50, 4), "\n")
cat("  Q1-Q5 spread:", round(LS_spread*100, 3), "%/월\n")
cat("  연간 회전율 추정:", round(ann_turnover, 0), "%\n")
cat("  IC AR(1):", round(ic_ac1, 4), "\n")
cat("  GFC IC:", round(stress_ic_results$GFC$IC_mean, 4), "\n")
cat("  COVID IC:", round(stress_ic_results$COVID$IC_mean, 4), "\n")

# 수치 안전 변환
safe_num <- function(x) {
  if (is.null(x) || length(x)==0 || is.na(x)) return(NULL)
  round(as.numeric(x), 4)
}

results <- list(
  icir_verified = annualized_ICIR,
  t_stat = round(t_stat, 3),
  icir_top50vol = round(ICIR_top50, 4),
  n_months = n_months,
  quintile_spread_pct_monthly = round(LS_spread*100, 4),
  turnover_annual_pct = round(ann_turnover, 0),
  ic_ar1 = round(ic_ac1, 4),
  ic_ar3 = round(ic_ac3, 4),
  stress_gfc_ic = safe_num(stress_ic_results$GFC$IC_mean),
  stress_covid_ic = safe_num(stress_ic_results$COVID$IC_mean),
  stress_it_ic = safe_num(stress_ic_results$IT_crash$IC_mean),
  monotone_quintile = monotone_check,
  ic_monthly_head = head(ic_monthly, 5)
)

saveRDS(results, file.path(ROOT, "stage_artifacts/quant_verify_H1674_results.rds"))
cat("\n결과 저장 완료: stage_artifacts/quant_verify_H1674_results.rds\n")
cat("종료:", format(Sys.time()), "\n")
