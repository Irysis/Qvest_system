# =============================================================================
# factor_engine_spec_mass_lowfreq.R
#   저주파 스펙트럼 질량 팩터 (Spectral Mass at Low Frequencies)
#
# 소스 논문: Sepp & Lucic (2026) "The Science and Practice of Trend-Following
#   Systems" — arXiv:2607.19497. 핵심 명제: 추세추종 알파는 수익률 PSD에서
#   저주파 구간의 초과 질량에서 비롯됨.
#
# 가설: 개별 종목의 trailing 60거래일 일별 log-return periodogram에서
#   저주파(주기 > 30일, f < 1/30) 구간 PSD 합 / 전체 PSD 합이 클수록
#   추세 지속성이 강해 미래 수익률을 예측함. → 상위 종목 매수.
#
# 팩터명: spec_mass_lowfreq_60d
# 산출:   FACTORS(Date, Ticker, Score)
#   Score = sum(PSD[freq < 1/30]) / sum(PSD) — trailing 60거래일 기준
#   높을수록 저주파(추세) 지배 = 매수 우선.
#
# PIT 준수:
#   C1: rolling window 60일 — 전기간 통계 사용 안 함
#   C2: 신호는 월말 당일 포함 직전 60일 Ret 사용 (당일 Ret은 shift(1) 후 lag처리)
#       → 월말 당일의 Ret은 이미 확정된 과거값이므로 동일시점 순환 없음.
#       단 "직전 60 거래일"은 shift를 쓰지 않고 by-ticker rolling slice 방식으로
#       직전 60개 Ret을 사용. 월말 당일 Ret 포함(이미 장 종료 후 확정값) — 이는
#       Close 기반 당일 수익률로서 월말 장 종료 후 신호 생성 시점에 확정 가능.
#   C10: AvgTV20 (t-1 rolling, run_alpha_search가 계산) 기반 유동성 필터 사용
#
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 일별 log-return 계산 (Close 기반, shift(1)로 전일 종가 대비) -----------
# Ret가 이미 RAWDATA에 있으면 그대로 사용, 없으면 Close로 계산
if ("Ret" %in% names(RAWDATA)) {
  RAWDATA[, .log_ret := log(1 + Ret), by = Ticker]
} else {
  RAWDATA[, .log_ret := log(Close / shift(Close, 1L)), by = Ticker]
}

# ---- 저주파 스펙트럼 질량 계산 함수 -----------------------------------------
# spec.pgram: R 기본함수, 비모수 periodogram (Fast Fourier Transform 기반).
#   freq 단위: cycles per sample (1일 = 1 sample).
#   f < 1/30 → 주기 > 30거래일 = 저주파(추세) 구간.
# taper=0: windowing 없음 (추가 bias 회피).
# detrend=TRUE: 선형 추세 제거 후 PSD 추정 (PIT-safe — 해당 윈도우 내부만 사용).

.spec_mass_lowfreq <- function(log_ret_vec, freq_cut = 1/30, min_obs = 20L) {
  x <- log_ret_vec[!is.na(log_ret_vec)]
  if (length(x) < min_obs) return(NA_real_)
  pg <- tryCatch(
    spec.pgram(x, taper = 0, plot = FALSE, detrend = TRUE, fast = FALSE),
    error = function(e) NULL
  )
  if (is.null(pg) || length(pg$spec) == 0L) return(NA_real_)
  total_mass <- sum(pg$spec)
  if (!is.finite(total_mass) || total_mass <= 0) return(NA_real_)
  low_mask <- pg$freq < freq_cut
  if (!any(low_mask)) return(0)
  low_mass  <- sum(pg$spec[low_mask])
  return(low_mass / total_mass)
}

# ---- 월말 날짜 추출 ----------------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_set <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- 월말별 trailing 60거래일 슬라이스로 팩터 계산 --------------------------
# 전략: RAWDATA를 Ticker별로 정렬 후, 각 월말 Date에서 해당 Ticker의
#   직전 60거래일 log_ret를 slice해 spec_mass 계산.
# data.table rolling slice 방식:
#   각 Ticker에 행 인덱스 부여 → 월말 행 기준으로 [idx-59, idx] 구간 추출.

RAWDATA[, .row_idx := .I]  # 전체 행 인덱스 (setorder 후 단조증가 보장)
RAWDATA[, .ticker_idx := seq_len(.N), by = Ticker]  # Ticker 내 순번

# 월말 행만 추출
.me_rows <- RAWDATA[Date %in% .month_ends_set & LiqPass == TRUE,
                    .(Date, Ticker, .row_idx, .ticker_idx)]

# 각 월말 행에 대해 trailing 60 log-ret 슬라이스
# 주: 이 벡터는 [ticker_idx - 59, ticker_idx] 범위의 동일 Ticker 행들
cat("[spec_mass_lowfreq] Computing spectral mass for", nrow(.me_rows),
    "ticker-months... (may take a few minutes)\n")

# Ticker별 log_ret 전체 벡터를 리스트로 캐시 → 빠른 slicing
.lr_list <- RAWDATA[, .(log_ret = list(.log_ret)), by = Ticker]
.lr_map  <- setNames(.lr_list$log_ret, .lr_list$Ticker)

# 계산: 각 월말 행에 대해 trailing 60 윈도우 spec_mass
.me_rows[, Score := {
  tk <- Ticker
  ti <- .ticker_idx
  lr <- .lr_map[[tk]]
  if (is.null(lr)) NA_real_ else {
    start_i <- max(1L, ti - 59L)
    end_i   <- ti
    .spec_mass_lowfreq(lr[start_i:end_i])
  }
}, by = seq_len(nrow(.me_rows))]

# ---- FACTORS 산출 ------------------------------------------------------------
FACTORS <- .me_rows[is.finite(Score),
                    .(Date, Ticker, Score)]

# ---- 임시 컬럼 정리 ---------------------------------------------------------
RAWDATA[, c(".log_ret", ".ym", ".row_idx", ".ticker_idx") := NULL]
rm(.me_rows, .lr_list, .lr_map)
gc(verbose = FALSE)

cat(sprintf("[factor_engine_spec_mass_lowfreq] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
