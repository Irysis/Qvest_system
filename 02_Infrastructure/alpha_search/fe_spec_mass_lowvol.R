# =============================================================================
# fe_spec_mass_lowvol.R — 저주파 스펙트럼 질량 × 저변동성 조건부 subset
#
# 계보: 07-27 spec_mass_lowfreq_60d (STR_AS_20260727_202754_49064, Grade C,
#       score 15.3, CAGR 12.7%, FF3 α 4.28%/yr t=1.47, MDD 61.4%,
#       BM_Corr 0.755, OOS_retention 0.263) 의 next_probe #2 소비.
#
# 원논문: Sepp & Lucic (2026) "The Science and Practice of Trend-Following
#       Systems" arXiv:2607.19497 — 추세 알파의 원천 = 수익률 PSD 저주파 초과질량.
#
# 07-27 base와의 차별점 (chain iteration, IS-only 선택):
#   base : 전 유니버스 횡단에서 spec_mass 상위 25종
#   본건 : 신호일 횡단 **실현변동성 하위 3분위(저변동성)** 안에서만 spec_mass 상위 25종
#   기전 가설: base 진단은 "신호력(CAGR 12.7%·FF3 α 4.28%/yr)은 실재하나
#   MDD 61.4% 구조적 + BM상관 0.755". spec_mass 상위가 고변동 추세주에 쏠려
#   낙폭을 키운다면, 저변동성 조건부는 같은 추세-지속성 신호를 낙폭 계층에서
#   분리해낸다. 개선되면 병목=변동성 노출, 불변이면 병목=신호 자체.
#
# 팩터 정의 (PIT-safe, 전부 후향):
#   spec_mass_t = sum(PSD[f < 1/30]) / sum(PSD),  직전 60거래일 일별 log-return
#   rv20_t      = sd(직전 20거래일 일별 log-return)         (횡단 3분위 절단)
#   Score       = spec_mass_t  (단, rv20_t 가 해당 신호일 횡단 하위 1/3 인 종목만)
#                 그 외 종목은 FACTORS 에서 제외 (배제형 조건부 — 점수 조작 아님)
#   신호일 = 월말 거래일, 수익 실현 = 익월
#
# PIT 체크:
#   C1 rolling only / C2 동일시점 순환 없음 (월말 종가 확정 후 신호 생성)
#   C13 부호반전 없음 (원 방향 유지: 저주파 질량 高 = 매수)
#   횡단 3분위 절단은 **해당 신호일 시점의 횡단 정보만** 사용 (전표본 아님)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

.W_SPEC <- 60L
.W_RV   <- 20L
.F_CUT  <- 1/30
.VOL_Q  <- 1/3   # 하위 3분위

# ---- 1. 일별 log-return ------------------------------------------------------
if ("Ret" %in% names(RAWDATA)) {
  RAWDATA[, .log_ret := log(1 + Ret)]
} else {
  RAWDATA[, .log_ret := log(Close / shift(Close, 1L)), by = Ticker]
}
RAWDATA[!is.finite(.log_ret), .log_ret := NA_real_]

# ---- 2. trailing 20일 실현변동성 (조건부 절단용) ----------------------------
RAWDATA[, .rv20 := frollapply(.log_ret, .W_RV, sd, align = "right",
                              fill = NA_real_), by = Ticker]

# ---- 3. 저주파 스펙트럼 질량 함수 (base 07-27과 동일 구현) ------------------
.spec_mass_lowfreq <- function(log_ret_vec, freq_cut = .F_CUT, min_obs = 20L) {
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
  sum(pg$spec[low_mask]) / total_mass
}

# ---- 4. 월말 행 추출 ---------------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_set <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
RAWDATA[, .ticker_idx := seq_len(.N), by = Ticker]

.me_rows <- RAWDATA[Date %in% .month_ends_set & LiqPass == TRUE &
                      is.finite(.rv20),
                    .(Date, Ticker, .ticker_idx, .rv20)]

cat("[fe_spec_mass_lowvol] ticker-months =", nrow(.me_rows), "\n")

# ---- 5. 저변동성 하위 3분위 조건부 절단 (신호일 횡단, PIT-safe) -------------
.me_rows[, .vol_cut := quantile(.rv20, .VOL_Q, na.rm = TRUE), by = Date]
.me_lv <- .me_rows[.rv20 <= .vol_cut]
cat("[fe_spec_mass_lowvol] low-vol subset rows =", nrow(.me_lv),
    sprintf("(%.1f%% of month-ends)\n", 100 * nrow(.me_lv) / max(1L, nrow(.me_rows))))

# ---- 6. 저변동성 subset 에만 spec_mass 계산 ---------------------------------
.lr_list <- RAWDATA[, .(log_ret = list(.log_ret)), by = Ticker]
.lr_map  <- setNames(.lr_list$log_ret, .lr_list$Ticker)

.me_lv[, Score := {
  lr <- .lr_map[[Ticker]]
  if (is.null(lr)) NA_real_ else {
    ti <- .ticker_idx
    .spec_mass_lowfreq(lr[max(1L, ti - (.W_SPEC - 1L)):ti])
  }
}, by = seq_len(nrow(.me_lv))]

FACTORS <- .me_lv[is.finite(Score), .(Date, Ticker, Score)]

# ---- 7. cleanup --------------------------------------------------------------
RAWDATA[, c(".log_ret", ".rv20", ".ym", ".ticker_idx") := NULL]
rm(.me_rows, .me_lv, .lr_list, .lr_map)
gc(verbose = FALSE)

cat(sprintf(
  "[fe_spec_mass_lowvol] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
