# =============================================================================
# fe_spec_lowfreq_mass.R — 스펙트럼 저주파수 질량 팩터
# =============================================================================
# 논문: "The Science and Practice of Trend-Following Systems"
#       Artur Sepp & Vladimir Lucic (arxiv: 2607.19497, 2026-07-21)
#
# 핵심 이론: trend-following alpha = excess spectral mass at low frequencies
#   - 저주파수 성분(장기 트렌드)에 스펙트럼 에너지가 집중된 자산에서 TF 알파 발생
#   - Poisson-kernel reading: kernel-weighted spectral mass > 1 일 때 시스템 수익
#
# 팩터 정의:
#   spec_lowfreq_mass_i_t = Σ P(f) for f ∈ [0, f_low] ∪ [1-f_low, 1]
#                          -----------------------------------------------
#                          Σ P(f) for all f
#
#   f_low = 1/60  (주기 60일 이상 = 3개월+ 장기 트렌드)
#   P(f)  = |FFT(r_norm)[f]|^2 / n  (파워 스펙트럼 밀도, 1-sided)
#   r_norm = (ret_252 - mean) / sd   (252일 정규화 수익률)
#
# PIT 준수:
#   - t월 말 기준, 과거 252 거래일 수익률 (log-return from Close)
#   - 신호 월 m의 팩터 = m-1월 마지막 거래일 기준 직전 252 거래일
#   - 당월 수익률 미포함 (shift 기준: 월말 종가 대비 직전 252일)
#   - 동일시점 순환참조 없음 (shift(Close,1)/shift(Close,252) 순수 과거)
#
# 보충 (논문 미명시):
#   - 유니버스: KOSPI200 ∪ KOSDAQ150 (PIT 시변 멤버십)
#   - 비용: 15bps 편도
#   - 유동성: 20일 평균 거래대금 ≥ 2e8 KRW
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 스펙트럼 저주파수 질량 함수 (PIT-safe: 과거 윈도우만 사용) -----------
compute_spec_lowfreq_mass <- function(close_vec, f_low = 1/60, window = 252L) {
  n <- length(close_vec)
  if (n < window) return(NA_real_)

  # 직전 window 거래일 수익률 (로그수익률, PIT-safe: close_vec는 과거 데이터만)
  cl <- tail(close_vec, window)
  if (anyNA(cl) || any(cl <= 0)) return(NA_real_)

  ret <- diff(log(cl))  # 길이 = window - 1
  nr  <- length(ret)

  if (nr < 30L || sd(ret) < 1e-8) return(NA_real_)

  # 정규화
  r_norm <- (ret - mean(ret)) / sd(ret)

  # FFT 파워 스펙트럼 (Mod()^2 사용 — Re() 아님)
  sp    <- Mod(fft(r_norm))^2 / nr
  freqs <- (seq_along(sp) - 1L) / nr

  # 저주파수 마스크 (양측 스펙트럼 — 대칭 처리)
  low_mask <- (freqs <= f_low) | (freqs >= (1 - f_low))

  total_power <- sum(sp)
  if (total_power < 1e-10) return(NA_real_)

  sum(sp[low_mask]) / total_power
}

# ---- 월별 롤링 스펙트럼 팩터 계산 ------------------------------------------
# 각 종목별 월말 기준으로 직전 252 거래일 Close를 가져와 FFT 계산
# shift 없이 함수 내부에서 tail(window)로 처리 → PIT-safe
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# 월말 데이터 필터 (유동성 통과 종목만)
.me_dt <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE,
                  .(Date, Ticker, Close, LiqPass)]

# 종목별 Close 패널 구축 (전체 일별 — FFT 윈도우에 필요)
# PIT: 각 월말의 팩터는 해당 월말까지의 과거 252 거래일 Close를 사용
.all_dt <- RAWDATA[!is.na(Close) & Close > 0, .(Date, Ticker, Close)]
setorder(.all_dt, Ticker, Date)

# 월말 기준으로 각 종목의 직전 252일 Close를 슬라이딩 윈도우로 계산
.spec_list <- lapply(unique(.me_dt$Ticker), function(tk) {
  tk_daily <- .all_dt[Ticker == tk]
  setorder(tk_daily, Date)

  tk_ends <- .me_dt[Ticker == tk, Date]

  if (nrow(tk_daily) < 253L || length(tk_ends) == 0L) return(NULL)

  results <- lapply(tk_ends, function(me_date) {
    # PIT: me_date 이하의 과거 데이터만 사용 (me_date 자체 포함 = 당월 말 종가는 알 수 있음)
    past_close <- tk_daily[Date <= me_date, Close]
    score <- compute_spec_lowfreq_mass(past_close, f_low = 1/60, window = 252L)
    if (is.na(score)) return(NULL)
    data.table(Date = me_date, Ticker = tk, Score = score)
  })
  rbindlist(Filter(Negate(is.null), results))
})

.spec_dt <- rbindlist(Filter(Negate(is.null), .spec_list))

cat(sprintf("[fe_spec_lowfreq_mass] 스펙트럼 팩터 계산 완료: rows=%d | tickers=%d | dates=%d\n",
            nrow(.spec_dt), uniqueN(.spec_dt$Ticker), uniqueN(.spec_dt$Date)))

# ---- FACTORS 산출 -----------------------------------------------------------
# 유동성 통과 + 유효 스코어만
FACTORS <- .spec_dt[is.finite(Score) & Score > 0]

cat(sprintf("[fe_spec_lowfreq_mass] FACTORS rows=%d | signal dates=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

# 정리 (임시 변수 제거)
RAWDATA[, .ym := NULL]
rm(.me_dt, .all_dt, .spec_list, .spec_dt)
