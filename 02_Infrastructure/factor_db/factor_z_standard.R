## factor_z_standard.R
##
## Qvest Outlier 처리 표준 (도훈 결정, 2026-04-29)
##
## 검증 근거 (실측 backtest):
##   STR_1631_SYN_05 4-way Outlier Handling 비교 (2026-04-29):
##     - baseline (MAX21d 80% trim):       SR 1.134 / MDD -52% / TO 300%
##     - Variant A (winsorize 1%/99%):     SR 1.286 / MDD -48% / TO 284% ← 채택
##     - Variant B (robust median/MAD):    SR 1.230 / MDD -47%
##     - Variant C (winsorize + robust):   SR 1.254 / MDD -48%
##   Variant A 모든 Long-window robustness + 거래비용 우위로 표준 채택.
##
## 표준:
##   1. Universe filter — corporate action 명확 식별 (range trim 아님)
##      AdminStock == 0 & TradingHalt == 0 & UnfaithfulDisc == 0
##   2. Cross-sectional z-score — winsorize 1%/99% 후 (x - mean) / sd
##   3. 학계 표준 (Fama-French 1992/2015, Asness QMJ 2019, MSCI/S&P 인덱스)

## ─────────────────────────────────────────────────────
## winsorize_1_99 — 1%/99% percentile cap
## ─────────────────────────────────────────────────────
winsorize_1_99 <- function(x) {
  qs <- quantile(x, c(0.01, 0.99), na.rm = TRUE)
  pmin(pmax(x, qs[1]), qs[2])
}

## ─────────────────────────────────────────────────────
## winsorize_pq — 일반화 (custom percentile)
## ─────────────────────────────────────────────────────
winsorize_pq <- function(x, lower = 0.01, upper = 0.99) {
  qs <- quantile(x, c(lower, upper), na.rm = TRUE)
  pmin(pmax(x, qs[1]), qs[2])
}

## ─────────────────────────────────────────────────────
## z_safe_winsorize — Qvest 표준 cross-sectional z-score
##   - winsorize 1%/99% 적용 후 (x - mean) / sd
##   - 입력: numeric vector
##   - 출력: 같은 길이 numeric vector (모두 NA면 NA 반환)
##   - 도훈 명령 (2026-04-29 정도 회복): factor 처리 표준
## ─────────────────────────────────────────────────────
z_safe_winsorize <- function(x) {
  nv <- sum(!is.na(x))
  if (nv < 3L) return(rep(NA_real_, length(x)))
  x_w <- winsorize_1_99(x)
  mu <- mean(x_w, na.rm = TRUE)
  s  <- sd(x_w, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  (x_w - mu) / s
}

## ─────────────────────────────────────────────────────
## z_safe_robust — Lopez de Prado robust z (MDD-우선시)
##   - robust statistics (median + MAD) 기반
##   - heavy fat-tail factor에 안정 (e.g. distress factor)
##   - 표준 아님 (참조용). 채택 시 backtest 검증 필요.
## ─────────────────────────────────────────────────────
z_safe_robust <- function(x) {
  nv <- sum(!is.na(x))
  if (nv < 3L) return(rep(NA_real_, length(x)))
  med <- median(x, na.rm = TRUE)
  mad_val <- 1.4826 * mad(x, na.rm = TRUE)  # consistent with sd for normal
  if (is.na(mad_val) || mad_val < 1e-10) return(rep(NA_real_, length(x)))
  (x - med) / mad_val
}

## ─────────────────────────────────────────────────────
## universe_corp_action_filter — Qvest 표준 universe filter
##   - SIG_SNAP-style data.table 입력 (Date / Ticker / LIQ_20d /
##     AdminStock / TradingHalt / UnfaithfulDisc 컬럼 필요)
##   - LIQ_20d >= liq_threshold (default 2e8)
##   - corp action (AdminStock / TradingHalt / UnfaithfulDisc) 모두 0 또는 NA
##   - MAX21d range trim 미적용 (baseline 폐기)
## ─────────────────────────────────────────────────────
universe_corp_action_filter <- function(sig_snap, sig_date,
                                         liq_threshold = 2e8) {
  sig_snap[Date == sig_date & !is.na(LIQ_20d) & LIQ_20d >= liq_threshold &
            (is.na(AdminStock) | AdminStock == 0) &
            (is.na(TradingHalt) | TradingHalt == 0) &
            (is.na(UnfaithfulDisc) | UnfaithfulDisc == 0)]
}

## ─────────────────────────────────────────────────────
## Standard SIG_SNAP columns required for Qvest factor pipelines
## ─────────────────────────────────────────────────────
.QVEST_SIGSNAP_COLS <- c("Date", "Ticker", "Close", "LIQ_20d",
                          "MAX21d", "AdminStock", "TradingHalt",
                          "UnfaithfulDisc")

build_standard_sig_snap <- function(rawdata, all_sig_dates) {
  cols_avail <- intersect(.QVEST_SIGSNAP_COLS, names(rawdata))
  rawdata[Date %in% all_sig_dates & !is.na(Close), ..cols_avail]
}

cat("[factor_z_standard] Loaded — Qvest outlier 처리 표준 (Variant A 2026-04-29).\n")
cat("  Functions: winsorize_1_99 / winsorize_pq / z_safe_winsorize /\n")
cat("             z_safe_robust / universe_corp_action_filter / build_standard_sig_snap\n")
