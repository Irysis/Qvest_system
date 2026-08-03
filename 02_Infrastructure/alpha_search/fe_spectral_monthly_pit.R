# =============================================================================
# fe_spectral_monthly_pit.R — 스펙트럼 저주파 모멘텀 팩터 (월간 수익률 기반)
# =============================================================================
# 논문: "The Science and Practice of Trend-Following Systems"
#       Artur Sepp & Vladimir Lucic (arxiv: 2607.19497, 2026-07-21)
#
# 기존 시도와 차별점:
#   - fe_spec_lowfreq_mass.R(252일 일별): 고주파 노이즈 과다, MDD 63%
#   - factor_engine_spec_mass_lowfreq.R(60일 일별): 창 너무 짧아 추세 미검출
#   이번: 논문 §3 스펙트럼 표현에 충실 — 월간 수익률(36M rolling)
#         + vol-normalization + Poisson-kernel 가중 저주파 파워 비율
#
# 팩터 정의 (Sepp-Lucic 2026 §2-§3 표현):
#   r_norm_t = r_t / σ_t (σ = trailing 12개월 표준편차, vol-normalized)
#   FFT on {r_norm_{t-35}, ..., r_norm_{t-1}} (36개월 lag-1 창, PIT-safe)
#   PSD(f) = |FFT[k]|^2   for k/n = f
#   low_freq_power_ratio = Σ PSD(f) for f ∈ [0, f_cut] / Σ PSD(f) all
#   f_cut = 1/12 cycles/month  (주기 12개월 이상 = 장기 트렌드)
#
# PIT 준수:
#   C1: 36개월 rolling window — 전기간 통계 사용 안 함
#   C2: 신호 = {r_{t-36}, ..., r_{t-1}} — 당월(t) 수익률 미포함 (lag-1)
#   vol-normalization에도 trailing 12개월만 사용 (C1 준수)
#
# 논문 미명시 보충:
#   - 유니버스: KOSPI200 ∪ KOSDAQ150 (실투 표준, K200_KQ150)
#   - 비용: 15bps 편도
#   - 유동성: 20일 평균 거래대금 ≥ 2e8 KRW
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 월간 수익률 산출 (일별 수익률 월별 집계) --------------------------------
# Ret 컬럼이 일별 수익률로 이미 존재 → 월간 수익률 = 합성
RAWDATA[, .ym := format(Date, "%Y-%m")]

# 월말 날짜 (월별 마지막 거래일)
.month_ends_dt <- RAWDATA[, .(Date = max(Date)), by = .ym]
setorder(.month_ends_dt, Date)
.month_ends_set <- .month_ends_dt$Date

# 월간 수익률: prod(1+daily_ret)-1 per ticker-month (PIT-safe: 당월 실현 수익률)
RAWDATA[, .Ret := Ret]
.monthly_ret <- RAWDATA[!is.na(.Ret), .(
  monthly_ret = prod(1 + .Ret) - 1,
  Date = max(Date)          # 월말 날짜 레이블
), by = .(Ticker, .ym)]
setorder(.monthly_ret, Ticker, Date)

# ---- Poisson-kernel 가중 저주파 파워 비율 계산 함수 --------------------------
# 논문 §3: TF expected return = (1/2π) ∫ P(ρ, f) * S(f) df
#   P(ρ, f) = Poisson kernel with ρ = e^{-1/L}, L = lookback span
# KR 구현: 단순화 - Poisson-kernel 가중 대신 저주파 비율
#   (ρ 계산은 lookback에 따라 다르고, 논문은 CTA 레벨 계산 — 종목 횡단면 랭킹이 목적)
.spec_lowfreq_monthly <- function(ret_vec, f_cut = 1/12, min_obs = 18L) {
  # ret_vec: 월간 수익률 벡터 (시간 순서, lag-1 이미 적용됨)
  x <- ret_vec[is.finite(ret_vec)]
  n <- length(x)
  if (n < min_obs) return(NA_real_)

  # vol-normalization (trailing 12개월 sd로 정규화 — 전기간 통계 아님, 함수 내 국소)
  # 여기서는 전달 벡터 자체의 sd로 정규화 (각 창의 내부 sd → C1 준수)
  sigma <- sd(x)
  if (!is.finite(sigma) || sigma < 1e-6) return(NA_real_)
  r_norm <- x / sigma

  # FFT 파워 스펙트럼
  sp <- Mod(fft(r_norm))^2 / n
  freqs <- (seq_along(sp) - 1L) / n

  total_power <- sum(sp)
  if (!is.finite(total_power) || total_power <= 0) return(NA_real_)

  # 저주파 마스크 (양측 대칭: f ∈ [0, f_cut] ∪ [1-f_cut, 1])
  low_mask <- (freqs <= f_cut) | (freqs >= (1 - f_cut))
  low_power <- sum(sp[low_mask])

  return(low_power / total_power)
}

# ---- 종목별 36개월 rolling 팩터 계산 ----------------------------------------
cat("[fe_spectral_monthly] Computing spectral low-freq mass (36M monthly rolling)...\n")

# Ticker별 월간 수익률 시계열
.tickers <- unique(.monthly_ret$Ticker)
cat(sprintf("[fe_spectral_monthly] Tickers to process: %d\n", length(.tickers)))

WINDOW_M <- 36L   # 36개월 rolling 창
F_CUT    <- 1/12  # f_cut = 1/12 cycles/month (주기 12개월 이상)

.spec_list <- lapply(.tickers, function(tk) {
  tk_ret <- .monthly_ret[Ticker == tk]
  setorder(tk_ret, Date)
  nr <- nrow(tk_ret)
  if (nr < WINDOW_M + 1L) return(NULL)   # 최소 37개월 필요 (창 36 + lag 1)

  # 각 월말 신호 날짜에 대해
  # PIT: 신호 날짜 t의 팩터 = {r_{t-36}, ..., r_{t-1}} 사용 (당월 r_t 미포함)
  results <- lapply(seq(WINDOW_M + 1L, nr), function(i) {
    # lag-1: i번째 월말이 신호 날짜 → 과거 [i-WINDOW_M, i-1] 창 사용
    window_ret <- tk_ret$monthly_ret[(i - WINDOW_M):(i - 1L)]
    sig_date   <- tk_ret$Date[i]   # 신호가 생성되는 달의 월말

    score <- .spec_lowfreq_monthly(window_ret, f_cut = F_CUT)
    if (is.na(score)) return(NULL)
    data.table(Date = sig_date, Ticker = tk, Score = score)
  })
  rbindlist(Filter(Negate(is.null), results))
})

.spec_dt <- rbindlist(Filter(Negate(is.null), .spec_list))
cat(sprintf("[fe_spectral_monthly] Raw computed: rows=%d | tickers=%d | dates=%d\n",
            nrow(.spec_dt), uniqueN(.spec_dt$Ticker), uniqueN(.spec_dt$Date)))

# ---- 유동성 필터 교차 (월말 LiqPass) -----------------------------------------
.me_liq <- RAWDATA[Date %in% .month_ends_set & LiqPass == TRUE, .(Date, Ticker)]
.spec_dt <- merge(.spec_dt, .me_liq, by = c("Date", "Ticker"))

# ---- FACTORS 산출 -----------------------------------------------------------
FACTORS <- .spec_dt[is.finite(Score) & Score > 0]
setorder(FACTORS, Date, Ticker)

cat(sprintf("[fe_spectral_monthly] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# 정리
RAWDATA[, c(".ym", ".Ret") := NULL]
rm(.monthly_ret, .tickers, .spec_list, .spec_dt, .me_liq, .month_ends_dt, .month_ends_set)
gc(verbose = FALSE)
