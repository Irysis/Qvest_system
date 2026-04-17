## H_1674 Individual Contrarian Flow — Quant R2 추가 분석
## S0 Debate Round 2 — Quintile 역전 원인 분해 + Reversal 상관 + 스무딩
## PIT 준수: C1(rolling), C2(t-1 lag), C13(Z_Score_Aligned)
## 작성: Forge (Quant 역할), 2026-04-12

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

cat("=== H_1674 R2 추가 분석 시작 ===\n")
cat("시작:", format(Sys.time()), "\n\n")

ROOT   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ARTDIR <- file.path(ROOT, "stage_artifacts")

# ── 0. 데이터 로드 (1회) ────────────────────────────────────────
cat("[0] 데이터 로드...\n")
inv <- as.data.table(read_parquet(file.path(ROOT, ".cache/investor_stock/investor_wide.parquet")))
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))
cat("    investor:", nrow(inv), "x", ncol(inv), "\n")
cat("    rawdata :", nrow(raw), "x", ncol(raw), "\n")

# ── 1. 월간 집계 (investor) ────────────────────────────────────
inv[, YM := format(Date, "%Y-%m")]
inv[, Ticker := as.character(Ticker)]
monthly_ind <- inv[, .(
  Ind_NetBuy = sum(Individual, na.rm = TRUE),
  n_days = .N
), by = .(YM, Ticker)]

# NextYM helper
get_next_ym <- function(ym_vec) {
  d <- as.Date(paste0(ym_vec, "-01"))
  format(as.Date(format(d + 32, "%Y-%m-01")), "%Y-%m")
}
monthly_ind[, NextYM := get_next_ym(YM)]

# ── 2. 월간 수익률 + 사이즈 + 거래대금 (rawdata) ───────────────
raw[, YM := format(Date, "%Y-%m")]
raw[, Ticker := as.character(Ticker)]
raw[, TradingVal := Vol * Close]

monthly_raw <- raw[, .(
  MonRet       = prod(1 + Ret, na.rm = TRUE) - 1,
  AvgTradingVal = mean(TradingVal, na.rm = TRUE),
  AvgSize      = mean(Size, na.rm = TRUE),
  AvgClose     = mean(Close, na.rm = TRUE),
  n_days       = .N
), by = .(YM, Ticker)]

# 섹터 정보 (필요 시) — RAWDATA에 BM_Ret 있으면 근사 사용
# 실제 섹터는 없으므로 size 분위로 대체

# ── 3. 전월 수익률(1M Reversal) 계산 ────────────────────────────
# C2: t-1 lag 필수
setorder(monthly_raw, Ticker, YM)
monthly_raw[, PrevMonRet := shift(MonRet, 1, type = "lag"), by = Ticker]
# PrevMonRet = 이전달 수익률 → 같은 달에 신호로 사용 가능 (t-1 lag 준수)

# ── 4. 결합 (신호 t → 수익률 t+1) ───────────────────────────────
cat("[4] 신호-수익률 결합 (1달 lag)...\n")
merged <- merge(
  monthly_ind[, .(YM, Ticker, Ind_NetBuy, NextYM)],
  monthly_raw[, .(YM, Ticker, MonRet, AvgTradingVal, AvgSize, PrevMonRet)],
  by.x = c("NextYM", "Ticker"),
  by.y = c("YM", "Ticker"),
  all = FALSE
)
setnames(merged, "YM", "SigYM")
merged[, RetYM := NextYM]

# 유동성 필터
LIQ_THRESHOLD <- 2e8
merged_liq <- merged[AvgTradingVal >= LIQ_THRESHOLD]
cat("    유동성 필터 통과:", nrow(merged_liq), "/", nrow(merged), "\n")

# 신호: 개인 순매도 = -Ind_NetBuy
merged_liq[, Signal_raw := -Ind_NetBuy]

# ── 5. 사이즈 분위 정의 (나중에 쓸 공통 변수) ──────────────────
merged_liq[, LogSize := log(AvgSize + 1)]
merged_liq[, SizeQ5  := cut(LogSize, breaks = quantile(LogSize, probs = seq(0,1,0.2), na.rm=TRUE),
                            include.lowest = TRUE, labels = FALSE), by = SigYM]

# ── 6. Cross-sectional Z-score (전체, size-neutral) ─────────────
merged_liq[, Signal_SN := {
  tmp <- Signal_raw
  m   <- mean(tmp, na.rm = TRUE)
  s   <- sd(tmp, na.rm = TRUE)
  if (is.na(s) || s == 0) rep(0, .N) else (tmp - m) / s
}, by = .(SigYM, SizeQ5)]

merged_liq <- merged_liq[!is.na(Signal_SN) & !is.na(MonRet)]

# ── 7. Sub-period 컬럼 ──────────────────────────────────────────
merged_liq[, Period := fcase(
  SigYM <= "2009-12", "2000-2009",
  SigYM <= "2019-12", "2010-2019",
  default              = "2020-2026"
)]

# ──────────────────────────────────────────────────────────────────
# [A] QUINTILE 역전 원인 분해
# ──────────────────────────────────────────────────────────────────
cat("\n\n======================================\n")
cat("[A] Quintile 역전 원인 분해\n")
cat("======================================\n")

# Quintile 할당 (전체)
merged_liq[, Quintile := {
  qb <- unique(quantile(Signal_SN, probs = seq(0, 1, 0.2), na.rm = TRUE))
  if (length(qb) < 3) rep(3L, .N)
  else as.integer(cut(Signal_SN, breaks = qb, include.lowest = TRUE, labels = FALSE))
}, by = SigYM]

cat("\n--- A1: Quintile별 종목 특성 (전체 기간) ---\n")
q_char <- merged_liq[!is.na(Quintile), .(
  AvgMonRet    = mean(MonRet,         na.rm = TRUE) * 100,
  MedianRet    = median(MonRet,       na.rm = TRUE) * 100,
  AvgSize_log  = mean(LogSize,        na.rm = TRUE),
  AvgTradVal_B = mean(AvgTradingVal,  na.rm = TRUE) / 1e9,
  N            = .N,
  N_months     = uniqueN(SigYM)
), by = Quintile]
setorder(q_char, Quintile)
print(q_char)

cat("\n--- A2: Quintile별 수익률 — Sub-period 분해 ---\n")
q_subp <- merged_liq[!is.na(Quintile), .(
  AvgMonRet = mean(MonRet, na.rm = TRUE) * 100,
  N         = .N
), by = .(Quintile, Period)]
setorder(q_subp, Period, Quintile)
print(q_subp)

cat("\n--- A3: Q1 vs Q5 — 크기 분포 비교 ---\n")
q1q5_size <- merged_liq[Quintile %in% c(1L, 5L), .(
  AvgLogSize  = mean(LogSize, na.rm = TRUE),
  Q25_LogSize = quantile(LogSize, 0.25, na.rm = TRUE),
  Q75_LogSize = quantile(LogSize, 0.75, na.rm = TRUE),
  AvgTradVal  = mean(AvgTradingVal, na.rm = TRUE) / 1e9,
  N           = .N
), by = Quintile]
print(q1q5_size)

cat("\n--- A4: Q1 종목 — '낙하칼' vs '과매도 반등' 검증 ---\n")
# Q1(개인 순매도 최다): 이미 전월에 하락했는가 vs 앞으로 반등하는가
q1_lag <- merged_liq[Quintile == 1L & !is.na(PrevMonRet), .(
  PrevRet_mean   = mean(PrevMonRet, na.rm = TRUE) * 100,  # 직전달 이미 하락했나?
  MonRet_mean    = mean(MonRet,     na.rm = TRUE) * 100,  # 다음달 반등하나?
  PrevRet_neg_pct = mean(PrevMonRet < 0, na.rm = TRUE) * 100,  # 직전달 음수 비율
  N              = .N
)]
cat("  Q1 직전달 평균수익률:", round(q1_lag$PrevRet_mean, 3), "% (음수면 '낙하칼')\n")
cat("  Q1 다음달 평균수익률:", round(q1_lag$MonRet_mean, 3), "% (양수면 '반등')\n")
cat("  Q1 직전달 음수 비율:", round(q1_lag$PrevRet_neg_pct, 1), "%\n")

q5_lag <- merged_liq[Quintile == 5L & !is.na(PrevMonRet), .(
  PrevRet_mean   = mean(PrevMonRet, na.rm = TRUE) * 100,
  MonRet_mean    = mean(MonRet,     na.rm = TRUE) * 100,
  PrevRet_pos_pct = mean(PrevMonRet > 0, na.rm = TRUE) * 100,
  N              = .N
)]
cat("  Q5 직전달 평균수익률:", round(q5_lag$PrevRet_mean, 3), "%\n")
cat("  Q5 다음달 평균수익률:", round(q5_lag$MonRet_mean, 3), "%\n")
cat("  Q5 직전달 양수 비율:", round(q5_lag$PrevRet_pos_pct, 1), "%\n")

cat("\n--- A5: Size 그룹별 Quintile 패턴 (소형 vs 대형) ---\n")
q_by_size <- merged_liq[!is.na(Quintile), .(
  AvgMonRet = mean(MonRet, na.rm = TRUE) * 100,
  N = .N
), by = .(Quintile, SizeQ5)]
setorder(q_by_size, SizeQ5, Quintile)
cat("  (SizeQ5=1: 소형, 5: 대형)\n")
print(q_by_size)

# ──────────────────────────────────────────────────────────────────
# [B] 1-month Reversal 상관
# ──────────────────────────────────────────────────────────────────
cat("\n\n======================================\n")
cat("[B] 1-month Reversal 상관 분석\n")
cat("======================================\n")

# PrevMonRet이 t-1 수익률 → 신호(개인 순매도)와 얼마나 겹치는가?
# C2: PrevMonRet은 이미 t-1 lag된 값 (적법)

rev_data <- merged_liq[!is.na(PrevMonRet) & !is.na(Signal_SN)]

cat("--- B1: 신호(개인순매도 Z) vs 전월수익률 — 월별 상관 ---\n")
rev_cor_monthly <- rev_data[, .(
  corr_raw = cor(Signal_SN, PrevMonRet, use = "complete.obs"),
  N = .N
), by = SigYM]
rev_cor_monthly <- rev_cor_monthly[!is.na(corr_raw) & N >= 20]

cat("  월별 상관계수 평균:", round(mean(rev_cor_monthly$corr_raw), 4), "\n")
cat("  월별 상관계수 SD  :", round(sd(rev_cor_monthly$corr_raw), 4), "\n")
cat("  월별 상관 > 0.30 비율:", round(mean(rev_cor_monthly$corr_raw > 0.30) * 100, 1), "%\n")
cat("  월별 상관 < -0.30 비율:", round(mean(rev_cor_monthly$corr_raw < -0.30) * 100, 1), "%\n")

cat("\n--- B2: Risk Manager KS-2 검증 — 개인 순매도 ≈ 직전달 하락 후 이중측정? ---\n")
# 개인 순매도가 직전달 하락의 결과인지: Signal vs PrevMonRet 부분상관
# 직전달 하락이 클수록 개인이 더 많이 판매 → 상관이 양수(순매도 = 하락 결과)
cat("  양수 상관이면 '역인과(C2 위험)', 음수/0이면 '독립 신호'\n")
overall_corr <- cor(rev_data$Signal_SN, rev_data$PrevMonRet, use = "complete.obs")
cat("  전체 상관계수 (Signal vs PrevMonRet):", round(overall_corr, 4), "\n")

cat("\n--- B3: Reversal 통제 후 잔차 IC ---\n")
# PrevMonRet Z-score → Signal에서 제거 후 잔차 IC
rev_data[, PrevRet_Z := {
  m <- mean(PrevMonRet, na.rm = TRUE)
  s <- sd(PrevMonRet, na.rm = TRUE)
  if (is.na(s) || s == 0) rep(0, .N) else (PrevMonRet - m) / s
}, by = SigYM]

# 잔차 = Signal_SN - beta * PrevRet_Z (단순 선형 제거)
# 월별 OLS로 beta 추정
rev_data[, Signal_Resid := {
  fit <- tryCatch(
    lm(Signal_SN ~ PrevRet_Z)$residuals,
    error = function(e) Signal_SN
  )
  fit
}, by = SigYM]

ic_resid_monthly <- rev_data[, .(
  IC_orig  = cor(Signal_SN,    MonRet, method = "spearman", use = "complete.obs"),
  IC_resid = cor(Signal_Resid, MonRet, method = "spearman", use = "complete.obs"),
  N = .N
), by = SigYM]
ic_resid_monthly <- ic_resid_monthly[!is.na(IC_orig) & !is.na(IC_resid) & N >= 20]

n_resid <- nrow(ic_resid_monthly)
ICIR_orig  <- mean(ic_resid_monthly$IC_orig)  / sd(ic_resid_monthly$IC_orig)  * sqrt(12)
ICIR_resid <- mean(ic_resid_monthly$IC_resid) / sd(ic_resid_monthly$IC_resid) * sqrt(12)

cat("  원래 ICIR     :", round(ICIR_orig, 4), "\n")
cat("  Reversal 제거 후 ICIR:", round(ICIR_resid, 4), "\n")
cat("  ICIR 보존률   :", round(ICIR_resid / ICIR_orig * 100, 1), "%\n")
cat("  결론: ICIR 보존률이 80%+ 이면 독립 alpha, 50% 미만이면 reversal artifact\n")

# ──────────────────────────────────────────────────────────────────
# [C] 3개월 이동평균 스무딩 효과
# ──────────────────────────────────────────────────────────────────
cat("\n\n======================================\n")
cat("[C] 3개월 이동평균 스무딩 효과\n")
cat("======================================\n")

cat("--- C1: 3M MA 신호 구성 ---\n")
# PIT: 3개월 MA는 t, t-1, t-2 월 데이터 사용 → t+1 수익률에 적용 (적법)
setorder(monthly_ind, Ticker, YM)
monthly_ind[, Ind_NetBuy_3MA := frollmean(Ind_NetBuy, n = 3, align = "right",
                                           na.rm = TRUE), by = Ticker]

# 3MA NextYM (lag 1달)
monthly_ind3 <- monthly_ind[!is.na(Ind_NetBuy_3MA)]
monthly_ind3[, NextYM := get_next_ym(YM)]

merged3 <- merge(
  monthly_ind3[, .(YM, Ticker, Ind_NetBuy, Ind_NetBuy_3MA, NextYM)],
  monthly_raw[, .(YM, Ticker, MonRet, AvgTradingVal, AvgSize)],
  by.x = c("NextYM", "Ticker"),
  by.y = c("YM", "Ticker"),
  all = FALSE
)
setnames(merged3, "YM", "SigYM")
merged3 <- merged3[AvgTradingVal >= LIQ_THRESHOLD]

# Z-score (size-neutral)
merged3[, LogSize := log(AvgSize + 1)]
merged3[, SizeQ5 := cut(LogSize, breaks = quantile(LogSize, probs = seq(0,1,0.2), na.rm=TRUE),
                        include.lowest = TRUE, labels = FALSE), by = SigYM]
merged3[, Signal_1M := {
  tmp <- -Ind_NetBuy
  m <- mean(tmp, na.rm=TRUE); s <- sd(tmp, na.rm=TRUE)
  if (is.na(s)||s==0) rep(0,.N) else (tmp-m)/s
}, by = .(SigYM, SizeQ5)]
merged3[, Signal_3MA := {
  tmp <- -Ind_NetBuy_3MA
  m <- mean(tmp, na.rm=TRUE); s <- sd(tmp, na.rm=TRUE)
  if (is.na(s)||s==0) rep(0,.N) else (tmp-m)/s
}, by = .(SigYM, SizeQ5)]
merged3 <- merged3[!is.na(Signal_1M) & !is.na(Signal_3MA) & !is.na(MonRet)]

# ICIR 비교
ic3 <- merged3[, .(
  IC_1M  = cor(Signal_1M,  MonRet, method = "spearman", use = "complete.obs"),
  IC_3MA = cor(Signal_3MA, MonRet, method = "spearman", use = "complete.obs"),
  N = .N
), by = SigYM]
ic3 <- ic3[!is.na(IC_1M) & !is.na(IC_3MA) & N >= 20]
n3  <- nrow(ic3)

ICIR_1M  <- mean(ic3$IC_1M)  / sd(ic3$IC_1M)  * sqrt(12)
ICIR_3MA <- mean(ic3$IC_3MA) / sd(ic3$IC_3MA) * sqrt(12)

cat("  ICIR (1M 원신호):", round(ICIR_1M, 4), "\n")
cat("  ICIR (3M MA)    :", round(ICIR_3MA, 4), "\n")
cat("  월수:", n3, "\n")

# 회전율 비교 (1M vs 3MA Top30 유지율)
compute_to <- function(dt, sig_col) {
  top30 <- dt[, {
    ord <- order(-get(sig_col))
    .(Ticker = Ticker[ord[1:min(30,.N)]])
  }, by = SigYM]
  setorder(top30, SigYM)
  yms <- sort(unique(top30$SigYM))
  overlaps <- numeric(length(yms) - 1)
  for (i in seq_along(overlaps)) {
    p <- top30[SigYM == yms[i],   Ticker]
    c <- top30[SigYM == yms[i+1], Ticker]
    overlaps[i] <- length(intersect(p, c)) / 30
  }
  list(
    avg_overlap  = mean(overlaps, na.rm = TRUE),
    avg_to_monthly = 1 - mean(overlaps, na.rm = TRUE),
    ann_to_pct   = (1 - mean(overlaps, na.rm = TRUE)) * 2 * 12 * 100
  )
}

to_1m  <- compute_to(merged3, "Signal_1M")
to_3ma <- compute_to(merged3, "Signal_3MA")

cat("\n  === 회전율 비교 ===\n")
cat("  1M 원신호  — 연간 회전율:", round(to_1m$ann_to_pct, 0), "%",
    "| Top30 유지율:", round(to_1m$avg_overlap*100, 1), "%\n")
cat("  3MA 스무딩 — 연간 회전율:", round(to_3ma$ann_to_pct, 0), "%",
    "| Top30 유지율:", round(to_3ma$avg_overlap*100, 1), "%\n")

# Quintile (3MA 신호)
merged3[, Q3MA := {
  qb <- unique(quantile(Signal_3MA, probs = seq(0,1,0.2), na.rm=TRUE))
  if (length(qb) < 3) rep(3L, .N)
  else as.integer(cut(Signal_3MA, breaks = qb, include.lowest = TRUE, labels = FALSE))
}, by = SigYM]
q3ma_ret <- merged3[!is.na(Q3MA), .(AvgRet = mean(MonRet, na.rm=TRUE)*100, N=.N), by=Q3MA]
setorder(q3ma_ret, Q3MA)
cat("\n  3MA Quintile 수익률:\n")
print(q3ma_ret)

# ──────────────────────────────────────────────────────────────────
# [D] Sub-period IC 전체 요약
# ──────────────────────────────────────────────────────────────────
cat("\n\n======================================\n")
cat("[D] Sub-period ICIR 요약 (전체 신호)\n")
cat("======================================\n")

ic_monthly <- merged_liq[, .(
  IC = cor(Signal_SN, MonRet, method = "spearman", use = "complete.obs"),
  N  = .N
), by = SigYM]
ic_monthly <- ic_monthly[!is.na(IC) & N >= 20]
setorder(ic_monthly, SigYM)

ic_monthly[, Period := fcase(
  SigYM <= "2009-12", "2000-2009",
  SigYM <= "2019-12", "2010-2019",
  default              = "2020-2026"
)]

ic_by_period <- ic_monthly[, .(
  IC_mean = mean(IC),
  IC_sd   = sd(IC),
  ICIR    = mean(IC) / sd(IC) * sqrt(12),
  t_stat  = mean(IC) / (sd(IC) / sqrt(.N)) ,
  n       = .N
), by = Period]
print(ic_by_period)

cat("\n--- D2: Risk Manager 우려 — 2020 이후 alpha decay ---\n")
ic_post2020 <- ic_monthly[SigYM >= "2020-01"]
ICIR_post20 <- mean(ic_post2020$IC) / sd(ic_post2020$IC) * sqrt(12)
cat("  2020+ ICIR:", round(ICIR_post20, 4), "| n=", nrow(ic_post2020), "\n")
cat("  전체 ICIR:", round(mean(ic_monthly$IC)/sd(ic_monthly$IC)*sqrt(12), 4), "\n")

# ──────────────────────────────────────────────────────────────────
# [E] 결과 저장
# ──────────────────────────────────────────────────────────────────
cat("\n\n======================================\n")
cat("[E] 결과 저장\n")
cat("======================================\n")

res <- list(
  # [A] Quintile 역전
  quintile_characteristics = q_char,
  quintile_by_subperiod    = q_subp,
  q1_prev_ret_mean_pct     = round(q1_lag$PrevRet_mean, 4),
  q1_prev_ret_neg_pct      = round(q1_lag$PrevRet_neg_pct, 1),
  q5_prev_ret_mean_pct     = round(q5_lag$PrevRet_mean, 4),
  q1_next_ret_mean_pct     = round(q1_lag$MonRet_mean, 4),
  q5_next_ret_mean_pct     = round(q5_lag$MonRet_mean, 4),

  # [B] Reversal 상관
  signal_vs_prevret_corr_monthly_mean = round(mean(rev_cor_monthly$corr_raw), 4),
  signal_vs_prevret_corr_overall      = round(overall_corr, 4),
  icir_before_reversal_control        = round(ICIR_orig, 4),
  icir_after_reversal_control         = round(ICIR_resid, 4),
  icir_preservation_pct               = round(ICIR_resid / ICIR_orig * 100, 1),

  # [C] 스무딩
  icir_1m                = round(ICIR_1M, 4),
  icir_3ma               = round(ICIR_3MA, 4),
  ann_to_1m_pct          = round(to_1m$ann_to_pct, 0),
  ann_to_3ma_pct         = round(to_3ma$ann_to_pct, 0),
  top30_overlap_1m_pct   = round(to_1m$avg_overlap * 100, 1),
  top30_overlap_3ma_pct  = round(to_3ma$avg_overlap * 100, 1),

  # [D] Sub-period
  ic_by_period = ic_by_period,
  icir_post2020 = round(ICIR_post20, 4)
)

saveRDS(res, file.path(ARTDIR, "quant_r2_H1674_results.rds"))
cat("결과 저장: stage_artifacts/quant_r2_H1674_results.rds\n")
cat("종료:", format(Sys.time()), "\n")
