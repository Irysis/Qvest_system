## sharpe_standard.R
##
## Qvest Sharpe Ratio 표준 (도훈 채택, 2026-04-29 reference)
##
## **표준 정의** (Lo 2002 / Bailey-LdP 2014 / 도훈 reference 1-5):
##   ER_t = R_p,t - R_f,t        (excess return per period)
##   Sharpe = mean(ER) / sd(ER)  (per-period basis)
##   Annualized = Sharpe × sqrt(N)   (N = 252 for daily, 12 for monthly)
##
## **금지 — 흔한 실수 (도훈 reference 4번)**:
##   ❌ CAGR / vol — geometric annual return / arithmetic vol mixed metric
##   ✅ mean(ER_period) / sd(ER_period) × sqrt(N) — 학술 표준
##
## R_f 처리:
##   - 일간: KR_Gov3Y (ecos_bond_rates.parquet) annual yield → daily 환산
##   - 월간: KR_Gov3Y → monthly 환산
##   - default: Rf = 0 (1990 이전 데이터 부재 시)
##
## 36년 backtest는 금리 regime 큰 변동 — 가능하면 R_f 차감 권장 (도훈 reference 3번 마지막).

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics)
})

cat("[sharpe_standard] Loaded — Qvest 표준 (2026-04-29 도훈 reference 채택).\n")

## ─────────────────────────────────────────────────────
## load_kr_riskfree — KR_Gov3Y 일별 yield → 일별/월별 R_f
## ─────────────────────────────────────────────────────
load_kr_riskfree <- function(
  bond_path = NULL,
  series_name = "KR_Gov3Y",
  basis = c("daily", "monthly")
) {
  basis <- match.arg(basis)
  if (is.null(bond_path)) {
    cand <- c(
      "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/.cache/ecos_bond_rates.parquet",
      file.path(getwd(), ".cache/ecos_bond_rates.parquet")
    )
    bond_path <- cand[file.exists(cand)][1]
  }
  if (is.na(bond_path) || !file.exists(bond_path)) {
    cat("[load_kr_riskfree] bond_path not found — Rf=0 사용\n")
    return(NULL)
  }

  bond <- as.data.table(read_parquet(bond_path))
  bond <- bond[Series == series_name][, .(Date = as.Date(Date), Yield = Value)]
  setorder(bond, Date)
  if (nrow(bond) == 0) return(NULL)

  # KR_Gov3Y is annual percentage yield (e.g. 6.67 = 6.67%)
  bond[, Yield_decimal := Yield / 100]
  if (basis == "daily") {
    # Daily Rf = (1 + annual_yield)^(1/252) - 1
    bond[, Rf := (1 + Yield_decimal)^(1 / 252) - 1]
  } else {
    bond[, Rf := (1 + Yield_decimal)^(1 / 12) - 1]
  }
  bond[, .(Date, Rf, Yield_pct = Yield)]
}

## ─────────────────────────────────────────────────────
## compute_sharpe_standard — 학술 표준 Sharpe (도훈 reference)
##
## 입력:
##   ret_xts: returns time series (xts, daily 또는 monthly)
##   basis: "daily" | "monthly" (자동 추론 또는 명시)
##   rf: Rf 처리 옵션
##     - 0 (default): Rf=0 가정
##     - "kr_gov3y": KR_Gov3Y 자동 차감 (per-period yield 환산)
##     - numeric scalar: per-period rate (e.g. 0.0001 = daily 0.01%)
##     - xts: per-period Rf 시계열 (Date 매칭)
##
## 출력 (list):
##   - sharpe_arithmetic: mean(ER) / sd(ER) (per-period)
##   - sharpe_annualized: × sqrt(N)
##   - mean_excess_per_period
##   - sd_excess_per_period
##   - n_periods
##   - basis
##   - rf_method (어떻게 처리했는지)
##   - rf_avg_annualized (평균 R_f 연율 표시용)
## ─────────────────────────────────────────────────────
compute_sharpe_standard <- function(
  ret_xts,
  basis = c("auto", "daily", "monthly"),
  rf = 0
) {
  basis <- match.arg(basis)

  # 자동 추론: median diff < 5d → daily / 25-35d → monthly
  if (basis == "auto") {
    diffs <- as.numeric(diff(index(ret_xts)))
    md <- median(diffs, na.rm = TRUE)
    basis <- if (is.na(md) || md <= 5) "daily" else "monthly"
  }
  N_per_year <- if (basis == "daily") 252L else 12L

  r <- as.numeric(ret_xts)
  r <- r[!is.na(r)]
  if (length(r) < 30L) {
    return(list(error = "insufficient observations (< 30)",
                n_periods = length(r), basis = basis))
  }

  # ─── R_f 처리 ──────────────────────────────────────
  rf_method <- "Rf=0"
  rf_per_period_vec <- rep(0, length(r))
  rf_avg_annualized <- 0

  if (is.character(rf) && rf == "kr_gov3y") {
    rf_dt <- load_kr_riskfree(basis = basis)
    if (!is.null(rf_dt)) {
      ret_dt <- data.table(Date = index(ret_xts)[!is.na(as.numeric(ret_xts))],
                           Ret = r)
      merged <- rf_dt[ret_dt, on = "Date", roll = TRUE]   # forward-fill Rf
      rf_per_period_vec <- merged$Rf
      rf_per_period_vec[is.na(rf_per_period_vec)] <- 0
      rf_method <- sprintf("KR_Gov3Y_%s_basis", basis)
      rf_avg_annualized <- (1 + mean(rf_per_period_vec, na.rm = TRUE))^N_per_year - 1
    }
  } else if (is.numeric(rf) && length(rf) == 1) {
    rf_per_period_vec <- rep(rf, length(r))
    rf_method <- sprintf("scalar=%.6f_per_%s", rf, basis)
    rf_avg_annualized <- (1 + rf)^N_per_year - 1
  } else if (inherits(rf, "xts") || (is.numeric(rf) && length(rf) > 1)) {
    rf_v <- if (inherits(rf, "xts")) as.numeric(rf) else rf
    rf_per_period_vec <- if (length(rf_v) == length(r)) rf_v else
      rep(mean(rf_v, na.rm = TRUE), length(r))
    rf_method <- sprintf("xts_or_vec_avg=%.6f", mean(rf_per_period_vec, na.rm = TRUE))
    rf_avg_annualized <- (1 + mean(rf_per_period_vec, na.rm = TRUE))^N_per_year - 1
  }

  # ─── Excess returns ──────────────────────────────
  er <- r - rf_per_period_vec

  # ─── 표준 Sharpe — mean(ER) / sd(ER) × sqrt(N) ──
  mean_er <- mean(er, na.rm = TRUE)
  sd_er   <- sd(er, na.rm = TRUE)
  if (is.na(sd_er) || sd_er < 1e-12) {
    return(list(error = "zero variance", basis = basis))
  }

  sharpe_arithmetic <- mean_er / sd_er
  sharpe_annualized <- sharpe_arithmetic * sqrt(N_per_year)

  list(
    sharpe_arithmetic         = round(sharpe_arithmetic, 6),
    sharpe_annualized         = round(sharpe_annualized, 4),
    mean_excess_per_period    = round(mean_er, 8),
    sd_excess_per_period      = round(sd_er, 8),
    annualized_excess_return  = round(mean_er * N_per_year, 6),
    annualized_excess_vol     = round(sd_er * sqrt(N_per_year), 6),
    n_periods                 = length(er),
    basis                     = basis,
    rf_method                 = rf_method,
    rf_avg_annualized         = round(rf_avg_annualized, 6)
  )
}

## ─────────────────────────────────────────────────────
## sharpe_via_perfanalytics — PerformanceAnalytics 표준 호출 검증용
##   Return.portfolio가 산출한 returns에 대해 동일 결과 확인
## ─────────────────────────────────────────────────────
sharpe_via_perfanalytics <- function(ret_xts, rf = 0,
                                       basis = c("auto", "daily", "monthly")) {
  basis <- match.arg(basis)
  if (basis == "auto") {
    diffs <- as.numeric(diff(index(ret_xts)))
    md <- median(diffs, na.rm = TRUE)
    basis <- if (is.na(md) || md <= 5) "daily" else "monthly"
  }
  N_per_year <- if (basis == "daily") 252L else 12L
  rf_scalar <- if (is.numeric(rf) && length(rf) == 1) rf else 0
  sr <- as.numeric(PerformanceAnalytics::SharpeRatio.annualized(
    R = ret_xts, Rf = rf_scalar, scale = N_per_year, geometric = FALSE
  ))
  list(sharpe_annualized = round(sr, 4),
       method = "PerformanceAnalytics::SharpeRatio.annualized(geometric=FALSE)",
       basis = basis, scale = N_per_year)
}

cat("  Functions: load_kr_riskfree / compute_sharpe_standard / sharpe_via_perfanalytics\n")
