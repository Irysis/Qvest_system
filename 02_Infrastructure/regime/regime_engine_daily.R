#==============================================================================
# Daily Regime Engine v2.1 — Production-Ready (PIT C11 가용시점 결합)
# 일별 FRED 기반 9축 국면 판단 (미래참조 배제 — 관측일이 아니라 가용 시각으로 결합)
#
# Author: Regime Scout Agent
# Date:   2026-03-17  ·  v2.1 수리 2026-09-24 (PIT C11 판정서 V-10·V-11 — 아래 2·3항)
#
# DESIGN PRINCIPLES:
#   1. Daily granularity: NO monthly aggregation.
#   2. 가용시점 결합 (PIT C11 — 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md ②):
#      행 d 는 "한국 d일 15:30 KST 결정"(판정서 ② 소비 형태 a)에 쓸 수 있는 정보만 담는다.
#      각 계열은 fred_asof_join(mode = "decision_close")으로 붙는다 — 관측일(미국 날짜·주간/월간
#      라벨)이 아니라 계열별 가용일로. 오프셋 정본 = 06_Registry/fred_availability_rules.json
#      (이 파일에는 오프셋 수치가 없다). 규칙 예: VIX·T10Y2Y = 미국 날짜 < 한국 날짜 ·
#      ICE OAS(HY·BBB) = 한국 d+2 영업일 · NFCI 라벨+6일 · STLFSI4 +7일 · ICSA +6일 ·
#      UMCSENT M+2월 5일 · 원/달러 = ECOS 731Y001(lag 0 — DEXKOUS 사용 금지,
#      decision_register PIT-C11-CONVENTIONS ①).
#      ★구판(v2.0)의 "1 FRED 행 shift" 는 폐기했다. 합친 날짜 격자에서 주간·월간 라벨을 LOCF 한 뒤
#       1행 미는 방식은 공표 전 값을 썼다(V-11: ICSA·STLFSI4 약 4일, NFCI 약 3일, UMCSENT 수주 —
#       2020-03-23 Claims_z 가 03-26 공표분을 썼다). 또 구판 Step 7 의 setnames 가 비지연
#       VIX_z_smooth 와 이름이 겹쳐 출력 VIX_z_smooth 가 같은 날짜 값이었다(V-10).
#       구판 주석의 "T−2 라서 필요 이상 엄격" 도 틀렸다 — 실제로는 미국 T−1 이었다(판정서 1-5).
#   3. 계산 격자 = 일요일을 뺀 모든 역일(가장 이른 관측일 ~ 한국 달력 끝). 행의 존재가 관측에
#      의존하지 않는다. ★구판 격자(FRED 관측일 합집합)는 미공표 관측(예: 아직 공표되지 않은 ICSA
#      토요일 라벨)이 행을 만들어 z-score·평활 창 구성이 미래에 의존했다. 새 격자의 밀도(연 313행)는
#      구판(미국 영업일 + ICSA 토요일, 2010~19 실측 연 308.5행)과 같게 두어 756행·20행 창의 시간 폭을
#      보존한다(한국 거래일만으로 세면 FRED 가 최근 3년만 주는 ICE OAS(HY·BBB)가 756행을 영영 못 채워
#      축 2·4 가 소멸한다). 한국 거래일은 모두 이 격자에 있고, 비거래일 행 값은 가용일이 한국
#      거래일이므로 직전 한국 거래일 행과 같다. 출력 행 = 계산 격자 ∪ FRED 관측일(일요일 라벨 —
#      구판 행 호환, 직전 행을 잇고 계산 창에는 들어가지 않는다).
#   4. Rolling z-score: 756-row window (≈ 2.4yr on the grid above), minimum 252 for warm-up.
#   5. 20-row MA smoothing on z-scores to filter noise.
#   6. 9-axis composite MRS (0-100), compatible with old engine's scale.
#
# ★소비 계약 (판정서 ② 원칙 a/b) — 소비자는 반드시 확인할 것:
#   - 행 d = 한국 d 종가 결정용(형태 a). 한국 d 종가 이후 시작하는 수익에 쓰면 된다.
#   - 노출을 한국 종가→종가 수익 r_t 에 곱하는 소비자(형태 b)는 **직전 한국 거래일 행**을 써야 한다
#     (merge_daily_regime(..., mode = "exposure_return")). 행 t 를 r_t 에 그대로 곱하면 미국 t−1
#     세션(한국 t 05:00~06:15 공개, r_t 창 시작 = 한국 t−1 15:30)이 들어간다.
#     구판 문서의 "MRS 는 이미 t-1 lag 되어 있다(추가 shift 불필요)"는 형태 b 에 대해 틀렸다.
#   - 값은 최신 빈티지다(ALFRED 미수집 — 안 C). NFCI·STLFSI4·ICSA·UMCSENT 등 개정 계열은
#     C1·C11 미해소 라벨(판정서 ② 빈티지 조항).
#
# AXES (total max = 100):
#   Axis 1: VIX              (daily,  max 20 pts) — volatility fear
#   Axis 2: HY Spread        (daily,  max 15 pts) — credit stress
#   Axis 3: Term Spread      (daily,  max 12 pts) — yield curve / recession
#   Axis 4: BBB Spread       (daily,  max 10 pts) — investment-grade stress
#   Axis 5: KRW/USD          (daily,  max  8 pts) — EM/Korea stress (ECOS 731Y001)
#   Axis 6: StL Fin Stress   (weekly, max 10 pts) — financial conditions
#   Axis 7: NFCI             (weekly, max  8 pts) — financial conditions (Chicago)
#   Axis 8: Initial Claims   (weekly, max  8 pts) — labor market deterioration
#   Axis 9: UMich Sentiment  (monthly,max  9 pts) — consumer confidence
#                                     --------
#                                     max 100 pts
#
# USAGE:
#   source("02_Infrastructure/regime/regime_engine_daily.R")
#   regime <- build_daily_regime(target_dates)
#   # regime: data.table(Date, MRS, exposure, n_axes_firing, ...)
#   # 행 d = 한국 d 15:30 결정 시점까지 가용한 정보만(형태 a). r_t 노출용은 mode = "exposure_return".
#   regime_daily_backtest_check()   # 출력 열의 시간축 자체검증(양성 대조 포함 — 08_Tests/regime/test_regime_c11_asof.R)
#
# INTEGRATION:
#   - Replaces merge_regime_to_signals() in strategies
#   - Compatible with Soft MRS (linear ramp) in STR_1034
#   - Cache: .cache/regime_daily_v2.parquet
#==============================================================================

cat("[regime_engine_daily_v2] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

.qvest_root <- function() {
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[regime_engine_daily] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- .qvest_root()
}
if (!exists("CACHE_DIR")) {
  CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
}
if (!exists("FRED_MACRO_CACHE")) {
  FRED_MACRO_CACHE <- file.path(CACHE_DIR, "macro_fred.parquet")
}

# Cache path for computed daily regime
REGIME_DAILY_CACHE <- file.path(CACHE_DIR, "regime_daily_v2.parquet")


#==============================================================================
# INTERNAL: 9축 계열 사양 — 이름 매핑만 담는다(오프셋·lag 수치 없음).
#   rule_id = 06_Registry/fred_availability_rules.json 의 계열 id (가용일 규칙은 거기서 온다)
#   out     = 출력 parquet 의 z_smooth 열 이름 (구판 스키마 그대로)
#==============================================================================
REGIME_DAILY_AXES <- data.table(
  col     = c("VIX", "HY_Spread", "Term_Spread", "BBB_Spread", "KRW_USD",
              "StL_Fin_Stress", "Chi_Fin_Cond", "Init_Claims", "UMich_Sentiment"),
  rule_id = c("VIXCLS", "BAMLH0A0HYM2", "T10Y2Y", "BAMLC0A4CBBB", "ECOS_KRW_USD",
              "STLFSI4", "NFCI", "ICSA", "UMCSENT"),
  source  = c("fred", "fred", "fred", "fred", "ecos",
              "fred", "fred", "fred", "fred"),
  out     = c("VIX_z_smooth", "HY_z_smooth", "TS_z_smooth", "BBB_z_smooth", "KRW_z_smooth",
              "FinStress_z_smooth", "NFCI_z_smooth", "Claims_z_smooth", "Sentiment_z_smooth")
)
REGIME_DAILY_AX_COLS <- c("ax1_VIX", "ax2_HY", "ax3_TS", "ax4_BBB", "ax5_KRW",
                          "ax6_FinStress", "ax7_NFCI", "ax8_Claims", "ax9_Sentiment")


#==============================================================================
# INTERNAL: 가용시점 층(S0) 로드 — 02_Infrastructure/data/fred_availability.R
#   없으면 fail-closed(stop). 호출자(daily_refresh·morning)의 tryCatch 가 잡아 구 캐시를 보존한다 —
#   가용시점 없이 관측일로 결합한 판을 새로 쓰지 않는다.
#==============================================================================
.re_need_fred_avail <- function() {
  if (exists("fred_asof_join", mode = "function") && exists("fred_avail_date", mode = "function"))
    return(invisible(TRUE))
  cands <- unique(c(if (exists("FUNC_PATH")) file.path(FUNC_PATH, "data", "fred_availability.R"),
                    file.path(PROJECT_ROOT, "02_Infrastructure", "data", "fred_availability.R")))
  p <- cands[file.exists(cands)][1]
  if (is.na(p))
    stop("[regime_daily_v2] fred_availability.R 없음 — 가용시점 결합 불가(fail-closed). 후보: ",
         paste(cands, collapse = " | "))
  source(p)
  invisible(TRUE)
}

.re_kr_calendar <- function() {
  .re_need_fred_avail()
  fred_kr_calendar(file.path(CACHE_DIR, "trading_calendar.parquet"))
}

# 계열 1개의 관측(Date = 관측일 라벨, Value). 같은 (Date, Value) 중복만 접는다 —
#   같은 관측일에 다른 값이 있으면 fred_asof_join 이 결합을 거부한다(fail-closed).
.re_series_obs <- function(fred_raw, rule_id, col) {
  x <- if ("Series_ID" %in% names(fred_raw) && any(fred_raw$Series_ID == rule_id, na.rm = TRUE))
    fred_raw[Series_ID == rule_id] else fred_raw[Series == col]
  unique(x[!is.na(Date) & !is.na(Value), .(Date = as.Date(Date), Value = as.numeric(Value))])
}

# 원/달러 = ECOS 731Y001 (decision_register PIT-C11-CONVENTIONS ① — DEXKOUS 대체)
.re_load_ecos_krw <- function() {
  p <- file.path(CACHE_DIR, "ecos_krw_usd.parquet")
  if (!file.exists(p)) return(NULL)
  e <- as.data.table(read_parquet(p, mmap = FALSE))
  if (!all(c("Date", "KRW_USD") %in% names(e)))
    stop("[regime_daily_v2] ecos_krw_usd.parquet 스키마 불일치(Date, KRW_USD 필요): ", p)
  unique(e[!is.na(Date) & !is.na(KRW_USD), .(Date = as.Date(Date), Value = as.numeric(KRW_USD))])
}

#==============================================================================
# INTERNAL: 계산 격자 = 일요일을 뺀 모든 역일 [d0, end] (헤더 3항)
#   행의 존재가 관측에 의존하지 않는다(구판 = FRED 관측일 합집합 → 미공표 라벨이 행을 만들었다).
#   밀도 ≈ 연 313행 = 구판 격자(미국 영업일 + ICSA 토요일 라벨, 2010~19 실측 연 308.5행)와 같게 두어
#   z-score 756행·평활 20행의 시간 폭을 보존한다. 한국 거래일만으로 세면 FRED 가 최근 3년만 주는
#   ICE OAS(HY·BBB)가 756행을 영영 못 채워(한국 거래일 3년 ≈ 745행) 축 2·4 가 소멸한다.
#   d0 = 가장 이른 관측일(2000-01-01) · end = 한국 달력 끝(달력 밖 평일을 거래일로 가정하지 않는다 —
#   달력이 늦으면 그 뒤 관측은 쓰지 않는다: 보수 쪽)
#==============================================================================
.re_compute_grid <- function(d0, end) {
  d0 <- as.Date(d0); end <- as.Date(end)
  if (is.na(d0) || is.na(end) || end < d0) stop("[regime_daily_v2] 계산 격자 범위 부적합")
  days <- seq(d0, end, by = "day")
  days[as.POSIXlt(days)$wday != 0L]
}

#==============================================================================
# INTERNAL: 계산 격자 위의 가용시점 값 (구판: FRED 날짜 격자 LOCF → 1행 shift)
#   반환: list(data = data.table(Date = 계산 격자, <9축 원값>), series, audit, calendar, fred_dates)
#     data 의 각 값 = 그 날 15:30 KST 결정에 가용한 최신 관측(fred_asof_join decision_close —
#     가용일은 한국 거래일이므로 비거래일 행은 직전 한국 거래일 행과 같다)
#     audit = (Date, col, rule_id, obs_date, avail_date) — 각 행이 어느 관측을 썼는지
#==============================================================================

.load_fred_daily_grid <- function(kr_calendar = NULL) {
  .re_need_fred_avail()
  if (!file.exists(FRED_MACRO_CACHE)) {
    stop("[regime_daily_v2] FRED macro cache not found: ", FRED_MACRO_CACHE,
         "\n  Run fred_fetch_all() first.")
  }
  fred_raw <- as.data.table(read_parquet(FRED_MACRO_CACHE, mmap = FALSE))
  fred_raw[, Date := as.Date(Date)]

  cal <- if (is.null(kr_calendar)) .re_kr_calendar() else sort(unique(as.Date(kr_calendar)))
  d0 <- min(fred_raw$Date, na.rm = TRUE)
  kgrid <- .re_compute_grid(d0, max(cal))

  dt <- data.table(Date = kgrid)
  audit <- vector("list", nrow(REGIME_DAILY_AXES))
  for (i in seq_len(nrow(REGIME_DAILY_AXES))) {
    ax <- REGIME_DAILY_AXES[i]
    obs <- if (identical(ax$source, "ecos")) .re_load_ecos_krw() else
      .re_series_obs(fred_raw, ax$rule_id, ax$col)
    if (is.null(obs) || !nrow(obs)) {
      warning(sprintf("[regime_daily_v2] %s(%s) 관측 없음 — 축 값 NA(점수 0)", ax$col, ax$rule_id))
      dt[, (ax$col) := NA_real_]
      next
    }
    j <- fred_asof_join(kgrid, obs, ax$rule_id, mode = "decision_close",
                        kr_calendar = cal, extend_calendar = FALSE)
    dt[, (ax$col) := j$value]
    audit[[i]] <- data.table(Date = kgrid, col = ax$col, rule_id = ax$rule_id,
                             obs_date = j$obs_date, avail_date = j$avail_date)
  }
  list(data = dt, series = REGIME_DAILY_AXES$col, audit = rbindlist(audit),
       calendar = cal, fred_dates = sort(unique(fred_raw$Date[!is.na(fred_raw$Date)])))
}

#==============================================================================
# INTERNAL: Vectorized rolling z-score (much faster than loop)
#==============================================================================

.rolling_zscore <- function(x, window = 756L, min_obs = 252L) {
  # Compute rolling z-score: z[i] = (x[i] - mean(x[i-w+1:i])) / sd(x[i-w+1:i])
  # Uses frollmean/frollapply for speed
  n <- length(x)
  z <- rep(NA_real_, n)

  # Rolling mean and sd
  # [Track R fix 2026-06-12] frollapply 인자명 N -> n (data.table 신버전 API; 구버전 N은
  # 현 머신 1.17+에서 "argument n is missing" 에러 — regime_daily_v2 갱신 중단의 직접 원인)
  roll_mean <- frollmean(x, n = window, align = "right", na.rm = TRUE)
  roll_sd   <- frollapply(x, n = window, FUN = sd, align = "right")

  # For early period (before full window), use expanding window
  # We compute expanding stats for indices min_obs to window-1
  for (i in seq_len(n)) {
    if (i < min_obs) next
    if (is.na(x[i])) next

    if (i < window) {
      # Expanding window
      vals <- x[1:i]
      vals <- vals[!is.na(vals)]
      if (length(vals) >= min_obs) {
        z[i] <- (x[i] - mean(vals)) / max(sd(vals), 1e-8)
      }
    } else {
      # Full rolling window
      if (!is.na(roll_mean[i]) && !is.na(roll_sd[i]) && roll_sd[i] > 1e-8) {
        z[i] <- (x[i] - roll_mean[i]) / roll_sd[i]
      }
    }
  }
  z
}


#==============================================================================
# INTERNAL: Axis scoring functions
# Each axis maps smoothed z-score to a 0-max_pts contribution
# using a sigmoid-like ramp for granularity (not binary threshold)
#==============================================================================

# Continuous ramp: linear interpolation between threshold and saturation
# For "higher = riskier" series (VIX, HY, BBB, KRW, Claims)
.score_ramp_up <- function(z_smooth, max_pts, thresh = 0.5, sat = 2.5) {
  # z_smooth < thresh  -> 0
  # z_smooth in [thresh, sat] -> linear 0..max_pts
  # z_smooth > sat     -> max_pts
  pmin(max_pts, pmax(0, (z_smooth - thresh) / (sat - thresh) * max_pts))
}

# For "lower = riskier" series (Term Spread — inversion = risk)
.score_ramp_down <- function(z_smooth, max_pts, thresh = -0.5, sat = -2.5) {
  # z_smooth > thresh  -> 0
  # z_smooth in [sat, thresh] -> linear max_pts..0
  # z_smooth < sat     -> max_pts
  pmin(max_pts, pmax(0, (thresh - z_smooth) / (thresh - sat) * max_pts))
}

# For sentiment (lower raw value = riskier, but we z-score it, so low z = risk)
.score_ramp_sentiment <- function(z_smooth, max_pts, thresh = -0.5, sat = -2.0) {
  # Low sentiment z-score = high risk
  pmin(max_pts, pmax(0, (thresh - z_smooth) / (thresh - sat) * max_pts))
}


#==============================================================================
# INTERNAL: 순수 계산 — 시간축을 정하지 않는다(어느 관측이 어느 행에 들어가는지는
#   .load_fred_daily_grid 가 정한다). 빌드와 자체검증(regime_daily_backtest_check)이 같이 쓴다.
#==============================================================================

# Step 1-2: 계열별 rolling z-score → MA 평활. 열 이름 = <계열>_z_smooth (내부 이름)
.re_zsmooth <- function(values_dt, z_lookback = 756L, smooth_window = 20L) {
  out <- data.table(Date = values_dt$Date)
  for (col in REGIME_DAILY_AXES$col) {
    x <- if (col %in% names(values_dt)) as.numeric(values_dt[[col]]) else rep(NA_real_, nrow(values_dt))
    z <- .rolling_zscore(x, window = z_lookback, min_obs = 252L)
    out[, (paste0(col, "_z_smooth")) := frollmean(z, n = smooth_window, align = "right", na.rm = TRUE)]
  }
  out
}

# Step 3-4·6: 9축 점수(연속 램프) → MRS · n_axes_firing · exposure (구판과 같은 식·문턱)
.re_axes_mrs <- function(zs) {
  dt <- copy(zs)
  # Axis 1: VIX (max 20) — higher z = riskier
  dt[, ax1_VIX := .score_ramp_up(VIX_z_smooth, max_pts = 20, thresh = 0.5, sat = 2.5)]
  # Axis 2: HY Spread (max 15) — higher z = riskier
  dt[, ax2_HY := .score_ramp_up(HY_Spread_z_smooth, max_pts = 15, thresh = 0.5, sat = 2.5)]
  # Axis 3: Term Spread (max 12) — lower z = riskier (inversion)
  dt[, ax3_TS := .score_ramp_down(Term_Spread_z_smooth, max_pts = 12, thresh = -0.5, sat = -2.5)]
  # Axis 4: BBB Spread (max 10) — higher z = riskier
  dt[, ax4_BBB := .score_ramp_up(BBB_Spread_z_smooth, max_pts = 10, thresh = 0.5, sat = 2.5)]
  # Axis 5: KRW/USD (max 8) — higher z = weaker won = riskier
  dt[, ax5_KRW := .score_ramp_up(KRW_USD_z_smooth, max_pts = 8, thresh = 0.5, sat = 2.5)]
  # Axis 6: StL Financial Stress (max 10) — higher z = riskier
  dt[, ax6_FinStress := .score_ramp_up(StL_Fin_Stress_z_smooth, max_pts = 10,
                                        thresh = 0.3, sat = 2.0)]
  # Axis 7: NFCI (max 8) — higher z = tighter conditions = riskier
  dt[, ax7_NFCI := .score_ramp_up(Chi_Fin_Cond_z_smooth, max_pts = 8,
                                   thresh = 0.3, sat = 2.0)]
  # Axis 8: Initial Claims (max 8) — higher z = labor weakness = riskier
  dt[, ax8_Claims := .score_ramp_up(Init_Claims_z_smooth, max_pts = 8,
                                     thresh = 0.5, sat = 2.5)]
  # Axis 9: UMich Sentiment (max 9) — LOWER z = riskier
  dt[, ax9_Sentiment := .score_ramp_sentiment(UMich_Sentiment_z_smooth,
                                               max_pts = 9,
                                               thresh = -0.5, sat = -2.0)]

  # Replace NAs in axis scores with 0 (missing data = no signal, not risk)
  for (col in REGIME_DAILY_AX_COLS) {
    dt[is.na(get(col)), (col) := 0]
  }

  # Composite MRS (sum of 9 axes, 0-100)
  dt[, MRS := ax1_VIX + ax2_HY + ax3_TS + ax4_BBB + ax5_KRW +
              ax6_FinStress + ax7_NFCI + ax8_Claims + ax9_Sentiment]
  dt[, MRS := pmin(100, pmax(0, MRS))]
  dt[is.na(MRS), MRS := 0]

  # Count axes firing (z_smooth above/below their thresholds)
  dt[, n_axes_firing := {
    n <- 0L
    n <- n + fifelse(!is.na(VIX_z_smooth) & VIX_z_smooth > 1.0, 1L, 0L)
    n <- n + fifelse(!is.na(HY_Spread_z_smooth) & HY_Spread_z_smooth > 1.0, 1L, 0L)
    n <- n + fifelse(!is.na(Term_Spread_z_smooth) & Term_Spread_z_smooth < -1.0, 1L, 0L)
    n <- n + fifelse(!is.na(BBB_Spread_z_smooth) & BBB_Spread_z_smooth > 1.0, 1L, 0L)
    n <- n + fifelse(!is.na(KRW_USD_z_smooth) & KRW_USD_z_smooth > 1.0, 1L, 0L)
    n <- n + fifelse(!is.na(StL_Fin_Stress_z_smooth) & StL_Fin_Stress_z_smooth > 1.0, 1L, 0L)
    n <- n + fifelse(!is.na(Chi_Fin_Cond_z_smooth) & Chi_Fin_Cond_z_smooth > 1.0, 1L, 0L)
    n <- n + fifelse(!is.na(Init_Claims_z_smooth) & Init_Claims_z_smooth > 1.0, 1L, 0L)
    n <- n + fifelse(!is.na(UMich_Sentiment_z_smooth) & UMich_Sentiment_z_smooth < -1.0, 1L, 0L)
    as.integer(n)
  }]

  # Exposure (Soft MRS compatible): 1.0 if MRS < 10 · linear ramp 1.0 -> 0.0 for MRS 10..60 · 0 if >= 60
  # This is the "Soft MRS" approach from L-399
  dt[, exposure := pmax(0, pmin(1, 1 - (MRS - 10) / 50))]
  dt[MRS < 10, exposure := 1.0]
  dt
}

# Step 7: 출력 조립 — 이름 매핑을 명시적으로(구판 setnames 이름 충돌 V-10 재발 방지).
#   extra_dates 중 격자 밖 날짜(일요일 FRED 라벨 — 구판 행 호환)는 직전 격자 행을 잇는다(계산 창 밖).
.re_assemble <- function(sc, extra_dates = NULL) {
  res <- data.table(Date = sc$Date, MRS = sc$MRS, exposure = sc$exposure,
                    n_axes_firing = as.integer(sc$n_axes_firing))
  for (i in seq_len(nrow(REGIME_DAILY_AXES)))
    res[, (REGIME_DAILY_AXES$out[i]) := sc[[paste0(REGIME_DAILY_AXES$col[i], "_z_smooth")]]]
  for (ax in REGIME_DAILY_AX_COLS) res[, (ax) := sc[[ax]]]
  if (length(extra_dates)) {
    ex <- sort(unique(as.Date(extra_dates)))
    ex <- ex[!is.na(ex) & ex > min(res$Date) & !(ex %in% res$Date)]
    if (length(ex)) {
      ext <- res[data.table(Date = ex), on = "Date", roll = TRUE]
      res <- rbind(res, ext, use.names = TRUE)
      setorder(res, Date)
    }
  }
  res
}

.RE_STATE <- new.env(parent = emptyenv())


#==============================================================================
# MAIN: build_daily_regime(target_dates)
#==============================================================================
#' Build daily regime signal — 가용시점 결합(PIT C11) · 9-axis MRS
#'
#' @param target_dates Date vector for output (NULL = all rows)
#' @param z_lookback Rolling z-score window in grid rows (default 756 ≈ 2.4yr — 헤더 3항 계산 격자)
#' @param smooth_window MA smoothing window in grid rows (default 20)
#' @param use_cache If TRUE and cache exists, load from cache (default FALSE)
#' @param verify 캐시 기록 전 출력 시간축 자체검증(regime_daily_backtest_check). FAIL 이면 기록하지 않고
#'   stop (fail-closed — 호출자 tryCatch 가 구 캐시를 보존한다). 기본 TRUE.
#' @return data.table with columns (구판 스키마 그대로):
#'   Date, MRS, exposure, n_axes_firing,
#'   VIX_z_smooth, HY_z_smooth, TS_z_smooth, BBB_z_smooth, KRW_z_smooth,
#'   FinStress_z_smooth, NFCI_z_smooth, Claims_z_smooth, Sentiment_z_smooth,
#'   ax1_VIX, ax2_HY, ax3_TS, ax4_BBB, ax5_KRW,
#'   ax6_FinStress, ax7_NFCI, ax8_Claims, ax9_Sentiment
#'   행 d = 한국 d 15:30 KST 결정 시점까지 가용한 정보(형태 a). r_t 노출은 직전 거래일 행(형태 b).
#' @export
build_daily_regime <- function(target_dates = NULL,
                               z_lookback = 756L,
                               smooth_window = 20L,
                               use_cache = FALSE,
                               verify = TRUE) {

  # --- Check cache ---
  if (use_cache && file.exists(REGIME_DAILY_CACHE)) {
    cached <- as.data.table(read_parquet(REGIME_DAILY_CACHE))
    cached[, Date := as.Date(Date)]
    if (!is.null(target_dates)) {
      target_dt <- data.table(Date = as.Date(target_dates))
      setkey(cached, Date)
      setkey(target_dt, Date)
      cached <- cached[target_dt, roll = TRUE]
    }
    cat(sprintf("[regime_daily_v2] Loaded from cache: %d dates\n", nrow(cached)))
    return(cached)
  }

  cat("[regime_daily_v2] Building 9-axis daily MRS (PIT C11 가용시점 결합)...\n")
  cat(sprintf("  z_lookback=%d, smooth_window=%d (계산 격자 행 — 일요일 제외 역일)\n", z_lookback, smooth_window))

  # --- Load data: 격자 날짜마다 그 날 15:30 KST 결정에 가용한 관측 ---
  grid <- .load_fred_daily_grid()
  vals <- grid$data
  cat(sprintf("  decision grid: %d rows, %s ~ %s\n",
              nrow(vals), min(vals$Date), max(vals$Date)))

  # Step 1-2: rolling z-score + MA 평활
  cat("  Step 1-2: rolling z-scores + MA smoothing...\n")
  zs <- .re_zsmooth(vals, z_lookback = z_lookback, smooth_window = smooth_window)

  # Step 3-4: 9축 점수 + MRS
  cat("  Step 3-4: scoring 9 axes + composite MRS...\n")
  sc <- .re_axes_mrs(zs)

  # Step 5: 추가 shift 없음 — 시점은 가용시점 결합이 이미 정했다(구판의 1 FRED 행 shift 폐기, 헤더 2항).

  # Step 7: 출력 조립 (명시적 이름 매핑 + 격자 밖 FRED 라벨 행 잇기)
  result <- .re_assemble(sc, extra_dates = grid$fred_dates)
  .RE_STATE$last_audit <- grid$audit

  # --- 자체검증(출력 22열의 시간축) — FAIL 이면 캐시를 쓰지 않는다 ---
  if (isTRUE(verify)) {
    ck <- regime_daily_backtest_check(regime = result, z_lookback = z_lookback,
                                      smooth_window = smooth_window, verbose = FALSE)
    if (!isTRUE(ck$pass))
      stop(sprintf(paste0("[regime_daily_v2] 출력 시간축 자체검증 FAIL — 캐시 미기록(fail-closed). ",
                          "기준선 불일치 %d · 누출판 일치 %d · 접두 불일치 %s · 누락 열 %s"),
                   sum(ck$per_col$mism_ref), sum(ck$per_col$hit_same + ck$per_col$hit_lag1),
                   paste(ck$prefix$n_mism, collapse = "/"), paste(ck$missing_cols, collapse = ",")))
    cat("  자체검증 PASS: 출력 22열 = 가용시점 기준선 · 누출판 일치 0 · 접두 불변\n")
  }

  # --- Save full result to cache ---
  # 측정 epoch 표식: 가용시점 규칙 판 키(파일 속성 c11_avail_regime_key) + ★r1 표식 계약(overlay_pit_guard C11 층 ·
  #   통합 검증 BLOCKING '표식 계약 불일치'): 행 열 avail_date(Date) = 행 날짜 — 행 d 의 값은 한국 d 15:30 결정에
  #   가용한 정보만 담는다(형태 a · 격자 밖 FRED 라벨 행은 직전 행을 잇는다) — 와 행 열 c11_regime_key.
  #   소비자는 Date 형 가용일 열 + 현행 규칙 키 일치로 수리판을 알아본다(키가 다르면 stale_epoch = legacy 취급).
  key <- tryCatch(fred_avail_rules_meta()$regime_key, error = function(e) NA_character_)
  result[, avail_date := as.Date(Date)]
  result[, c11_regime_key := as.character(key)]
  setattr(result, "c11_avail_regime_key", key)
  dir.create(dirname(REGIME_DAILY_CACHE), recursive = TRUE, showWarnings = FALSE)
  write_parquet(result, REGIME_DAILY_CACHE)

  # --- Filter to target dates if specified ---
  if (!is.null(target_dates)) {
    target_dt <- data.table(Date = as.Date(target_dates))
    setkey(result, Date)
    setkey(target_dt, Date)
    result <- result[target_dt, roll = TRUE]
  }

  # --- Summary ---
  cat(sprintf("\n[regime_daily_v2] Built: %d dates, %s ~ %s\n",
              nrow(result), min(result$Date), max(result$Date)))
  cat(sprintf("  MRS: mean=%.1f, median=%.1f, max=%.0f\n",
              mean(result$MRS, na.rm = TRUE),
              median(result$MRS, na.rm = TRUE),
              max(result$MRS, na.rm = TRUE)))
  cat(sprintf("  %%MRS>10=%.1f%%, %%MRS>30=%.1f%%, %%MRS>50=%.1f%%\n",
              mean(result$MRS > 10, na.rm = TRUE) * 100,
              mean(result$MRS > 30, na.rm = TRUE) * 100,
              mean(result$MRS > 50, na.rm = TRUE) * 100))
  cat(sprintf("  Exposure: mean=%.2f, min=%.2f\n",
              mean(result$exposure, na.rm = TRUE),
              min(result$exposure, na.rm = TRUE)))
  la <- grid$audit[Date == max(Date)]
  if (nrow(la))
    cat(sprintf("  최신 결정일 %s 사용 관측일: %s\n", max(la$Date),
                paste(sprintf("%s=%s", la$col, format(la$obs_date)), collapse = " ")))
  cat(sprintf("  C11 가용시점 규칙: %s\n", key))
  cat(sprintf("  Cache saved: %s\n", REGIME_DAILY_CACHE))

  result
}

#==============================================================================
# DIAGNOSTICS: regime_daily_diagnostics(target_dates)
# Compare new daily engine vs old monthly engine
#==============================================================================

regime_daily_diagnostics <- function(target_dates = NULL) {
  cat("==============================================================\n")
  cat("[regime_daily_v2] DIAGNOSTICS: Daily vs Monthly comparison\n")
  cat("==============================================================\n\n")

  # --- Build new daily regime ---
  new_regime <- build_daily_regime(target_dates)

  # --- Load old monthly regime ---
  old_path <- file.path(CACHE_DIR, "macro_regime.parquet")
  if (!file.exists(old_path)) {
    cat("  OLD monthly regime cache not found. Skipping comparison.\n")
    return(new_regime)
  }

  old_regime <- as.data.table(read_parquet(old_path))
  old_regime[, Date := as.Date(Date)]
  setnames(old_regime, "Macro_Risk_Score", "MRS_old", skip_absent = TRUE)

  # Rolling join: for each new regime date, get closest old monthly MRS
  old_sub <- old_regime[, .(Date, MRS_old)]
  setkey(old_sub, Date)

  new_regime_cmp <- copy(new_regime)
  setkey(new_regime_cmp, Date)
  merged <- old_sub[new_regime_cmp, roll = TRUE]
  merged[is.na(MRS_old), MRS_old := 0]

  # --- Correlation ---
  valid <- merged[!is.na(MRS) & !is.na(MRS_old)]
  if (nrow(valid) > 100) {
    corr <- cor(valid$MRS, valid$MRS_old, use = "complete.obs")
    cat(sprintf("  Correlation (daily MRS vs monthly MRS): %.3f\n", corr))
    cat(sprintf("  N overlapping dates: %d\n", nrow(valid)))
  }

  # --- Divergence analysis ---
  valid[, diff := MRS - MRS_old]
  cat(sprintf("\n  Divergence stats (new - old):\n"))
  cat(sprintf("    mean=%.1f, sd=%.1f, min=%.1f, max=%.1f\n",
              mean(valid$diff, na.rm=TRUE), sd(valid$diff, na.rm=TRUE),
              min(valid$diff, na.rm=TRUE), max(valid$diff, na.rm=TRUE)))

  # Top 10 dates where signals diverge most
  cat("\n  Top 10 divergence dates (|new - old| largest):\n")
  top_div <- valid[order(-abs(diff))][1:min(10, nrow(valid))]
  for (r in seq_len(nrow(top_div))) {
    row <- top_div[r]
    cat(sprintf("    %s: new_MRS=%.1f, old_MRS=%.0f, diff=%+.1f\n",
                row$Date, row$MRS, row$MRS_old, row$diff))
  }

  # --- Crisis detection comparison ---
  cat("\n  Crisis detection comparison:\n")
  crisis_periods <- list(
    "GFC"     = as.Date(c("2008-09-01", "2009-03-31")),
    "COVID"   = as.Date(c("2020-02-15", "2020-04-30")),
    "Rate2022"= as.Date(c("2022-01-01", "2022-10-31"))
  )

  for (name in names(crisis_periods)) {
    period <- crisis_periods[[name]]
    sub_new <- valid[Date >= period[1] & Date <= period[2]]
    if (nrow(sub_new) == 0) next

    cat(sprintf("\n    %s (%s ~ %s):\n", name, period[1], period[2]))
    cat(sprintf("      New daily MRS: mean=%.1f, max=%.1f\n",
                mean(sub_new$MRS), max(sub_new$MRS)))
    cat(sprintf("      Old monthly MRS: mean=%.1f, max=%.1f\n",
                mean(sub_new$MRS_old), max(sub_new$MRS_old)))

    # First date MRS > 30 (risk alert)
    first_new <- sub_new[MRS > 30][1]
    first_old <- sub_new[MRS_old > 30][1]
    if (!is.na(first_new$Date[1])) {
      cat(sprintf("      First MRS>30 (new): %s\n", first_new$Date))
    } else {
      cat("      First MRS>30 (new): never\n")
    }
    if (!is.na(first_old$Date[1])) {
      cat(sprintf("      First MRS>30 (old): %s\n", first_old$Date))
    } else {
      cat("      First MRS>30 (old): never\n")
    }
  }

  cat("\n==============================================================\n")
  cat("[regime_daily_v2] Diagnostics complete.\n")
  cat("==============================================================\n")

  invisible(merged)
}


#==============================================================================
# VERIFICATION: regime_daily_backtest_check() — **출력 열**의 시간축 자체검증 (PIT C11)
#   구판(:631-667)은 ax1_VIX 만 재계산해 대조했고 출력 열(VIX_z_smooth 등)은 보지 않았다 —
#   그래서 이름 충돌(V-10)과 주간·월간 조기 사용(V-11)을 통과시켰다(판정서 1-2·③ 방어선).
#   이 판은 출력(기본 = 캐시 parquet, 즉 소비자가 읽는 파일)의 22열 전부를 본다:
#     (1) 독립 기준선 일치 — 계열별 가용일(fred_avail_date)과 누적최대 관측 선택을 여기서 따로
#         구현해(엔진의 fred_asof_join 경로를 쓰지 않는다) 재계산한 값과 계산 격자 행 전부가 같아야 한다.
#     (2) 누출판 판별 — 관측일 당일 결합(same-day) · 관측일 다음날 결합(label+1d, 구판식 1행 lag)으로
#         만든 값과 기준선이 갈리는 날, 출력이 누출판과 일치하면 안 된다(일치 0건).
#     (3) 접두 불변 — 시점 T 까지 가용한 관측·T 까지의 격자만으로 다시 계산한 T 행 = 출력의 T 행.
#         계산식 안의 미래 참조(lead·전표본 통계)까지 잡는다.
#     (4) 계산 격자 밖 출력 행(일요일 FRED 라벨) = 직전 격자 행 그대로(계산 창 밖).
#   양성 대조·위반 주입 = 08_Tests/regime/test_regime_c11_asof.R.
#==============================================================================

# 독립 기준선 선택: 가용일 ≤ D 인 관측 중 관측일이 가장 늦은 것
.re_ref_pick <- function(dates, obs_date, avail, value) {
  n <- length(dates)
  ok <- !is.na(avail) & !is.na(obs_date) & !is.na(value)
  if (!any(ok)) return(list(value = rep(NA_real_, n), obs = as.Date(rep(NA_integer_, n))))
  a <- as.integer(avail[ok]); o <- as.integer(obs_date[ok]); v <- as.numeric(value[ok])
  ord <- order(a, o); a <- a[ord]; o <- o[ord]; v <- v[ord]
  rm_o <- cummax(o)
  k <- findInterval(as.integer(dates), a)
  sel <- rep(NA_integer_, n)
  hit <- k > 0L
  sel[hit] <- match(rm_o[k[hit]], o)
  list(value = v[sel], obs = as.Date(o[sel]))
}

.re_check_inputs <- function(cal) {
  fred_raw <- as.data.table(read_parquet(FRED_MACRO_CACHE, mmap = FALSE))
  fred_raw[, Date := as.Date(Date)]
  out <- list()
  for (i in seq_len(nrow(REGIME_DAILY_AXES))) {
    ax <- REGIME_DAILY_AXES[i]
    obs <- if (identical(ax$source, "ecos")) {       # 원천을 엔진 로더와 따로 읽는다(원천 바꿔치기 탐지)
      pe <- file.path(CACHE_DIR, "ecos_krw_usd.parquet")
      if (file.exists(pe)) {
        e <- as.data.table(read_parquet(pe, mmap = FALSE))
        unique(e[!is.na(Date) & !is.na(KRW_USD), .(Date = as.Date(Date), Value = as.numeric(KRW_USD))])
      } else NULL
    } else fred_raw[Series_ID == ax$rule_id & !is.na(Value), .(Date = as.Date(Date), Value = as.numeric(Value))]
    if (is.null(obs) || !nrow(obs)) { out[[ax$col]] <- NULL; next }
    obs <- obs[order(Date)]
    obs[, avail := fred_avail_date(ax$rule_id, Date, kr_calendar = cal)]
    out[[ax$col]] <- obs
  }
  list(obs = out, d0 = min(fred_raw$Date, na.rm = TRUE), fred_dates = sort(unique(fred_raw$Date)))
}

.re_values_from <- function(dates, obs_list, variant = c("pit", "same_day", "label_plus1"), cutoff = NULL) {
  variant <- match.arg(variant)
  vals <- data.table(Date = dates); used <- data.table(Date = dates)
  for (col in REGIME_DAILY_AXES$col) {
    o <- obs_list[[col]]
    if (is.null(o)) { vals[, (col) := NA_real_]; used[, (col) := as.Date(NA)]; next }
    av <- switch(variant, pit = o$avail, same_day = o$Date, label_plus1 = o$Date + 1L)
    if (!is.null(cutoff)) av[is.na(o$avail) | o$avail > as.Date(cutoff)] <- NA   # T 시점에 미가용 = 존재하지 않음
    p <- .re_ref_pick(dates, o$Date, av, o$Value)
    vals[, (col) := p$value]; used[, (col) := p$obs]
  }
  list(values = vals, used = used)
}

regime_daily_backtest_check <- function(check_dates = NULL, regime = NULL, tol = 1e-9,
                                        z_lookback = 756L, smooth_window = 20L, verbose = TRUE) {
  .re_need_fred_avail()
  if (verbose) {
    cat("==============================================================\n")
    cat("[regime_daily_v2] 출력 열 시간축 자체검증 (PIT C11 가용시점)\n")
    cat("==============================================================\n")
  }
  if (is.null(check_dates))
    check_dates <- as.Date(c("2008-09-15", "2020-02-20", "2020-03-23", "2022-01-03"))
  check_dates <- as.Date(check_dates)

  if (is.null(regime)) {
    regime <- if (file.exists(REGIME_DAILY_CACHE))
      as.data.table(read_parquet(REGIME_DAILY_CACHE, mmap = FALSE)) else build_daily_regime(use_cache = FALSE)
  }
  O <- as.data.table(copy(regime)); O[, Date := as.Date(Date)]; setorder(O, Date)
  cmp_cols <- c("MRS", "exposure", "n_axes_firing", REGIME_DAILY_AXES$out, REGIME_DAILY_AX_COLS)
  miss_cols <- setdiff(cmp_cols, names(O))

  cal <- .re_kr_calendar()
  inp <- .re_check_inputs(cal)
  kgrid <- .re_compute_grid(inp$d0, max(cal))

  build_out <- function(v) .re_assemble(.re_axes_mrs(.re_zsmooth(v$values, z_lookback, smooth_window)))
  ref  <- build_out(.re_values_from(kgrid, inp$obs, "pit"))
  lk_s <- build_out(.re_values_from(kgrid, inp$obs, "same_day"))
  lk_1 <- build_out(.re_values_from(kgrid, inp$obs, "label_plus1"))

  OK <- O[Date %in% kgrid]
  cover_missing <- sum(!(kgrid %in% OK$Date))
  OKa <- OK[data.table(Date = kgrid), on = "Date"]
  eqv <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & abs(a - b) <= tol)
  per <- rbindlist(lapply(setdiff(cmp_cols, miss_cols), function(cl) {
    o <- as.numeric(OKa[[cl]]); r <- as.numeric(ref[[cl]])
    s <- as.numeric(lk_s[[cl]]); l1 <- as.numeric(lk_1[[cl]])
    d_s <- !is.na(r) & !is.na(s) & abs(r - s) > tol
    d_1 <- !is.na(r) & !is.na(l1) & abs(r - l1) > tol
    data.table(col = cl, n = length(o), mism_ref = sum(!eqv(o, r)),
               disc_same = sum(d_s), hit_same = sum(d_s & !is.na(o) & abs(o - s) <= tol),
               disc_lag1 = sum(d_1), hit_lag1 = sum(d_1 & !is.na(o) & abs(o - l1) <= tol))
  }))

  # (4) 계산 격자 밖 출력 행(일요일 FRED 라벨) = 직전 격자 행
  NK <- O[!(Date %in% kgrid)]
  pre_first <- sum(NK$Date < min(kgrid))
  NK <- NK[Date > min(kgrid)]
  locf_mism <- 0L
  if (nrow(NK)) {
    expd <- OK[data.table(Date = NK$Date), on = "Date", roll = TRUE]
    for (cl in setdiff(cmp_cols, miss_cols))
      locf_mism <- locf_mism + sum(!eqv(as.numeric(NK[[cl]]), as.numeric(expd[[cl]])))
  }

  # (3) 접두 불변 — T 시점 정보만으로 다시 계산한 T 행
  #     격자도 T 까지로 다시 만든다 — 격자가 관측 존재에 기대면 여기서 갈린다.
  pre <- rbindlist(lapply(check_dates, function(T0) {
    kc <- cal[cal <= T0 & cal >= inp$d0]
    if (!length(kc)) return(NULL)
    Tk <- max(kc)
    kg <- .re_compute_grid(inp$d0, Tk)
    outT <- build_out(.re_values_from(kg, inp$obs, "pit", cutoff = Tk))
    rT <- outT[Date == Tk]; oT <- OK[Date == Tk]
    if (!nrow(oT)) return(data.table(T = Tk, n_mism = NA_integer_, cols = "출력에 T 행 없음"))
    bad <- Filter(function(cl) !isTRUE(eqv(as.numeric(oT[[cl]]), as.numeric(rT[[cl]]))),
                  setdiff(cmp_cols, miss_cols))
    data.table(T = Tk, n_mism = length(bad), cols = paste(head(unlist(bad), 6), collapse = ","))
  }))

  pass <- !length(miss_cols) && cover_missing == 0L && pre_first == 0L &&
    all(per$mism_ref == 0L) && all(per$hit_same == 0L) && all(per$hit_lag1 == 0L) &&
    locf_mism == 0L && nrow(pre) > 0L && all(!is.na(pre$n_mism) & pre$n_mism == 0L)

  if (verbose) {
    if (length(miss_cols)) cat(sprintf("  ✗ 출력에 없는 열: %s\n", paste(miss_cols, collapse = ",")))
    cat(sprintf("  계산 격자 행 %d · 결측 %d · 격자 밖 행 %d(직전 행 잇기 불일치 %d) · 격자 시작 이전 행 %d\n",
                length(kgrid), cover_missing, nrow(NK), locf_mism, pre_first))
    cat("  열별: 기준선 불일치 / 누출판(same-day) 갈림·일치 / 누출판(label+1d) 갈림·일치\n")
    for (i in seq_len(nrow(per))) with(per[i], cat(sprintf("    %-20s %5d | %5d / %5d | %5d / %5d\n",
      col, mism_ref, disc_same, hit_same, disc_lag1, hit_lag1)))
    for (i in seq_len(nrow(pre))) cat(sprintf("  접두 불변 T=%s: 불일치 열 %s %s\n",
      pre$T[i], pre$n_mism[i], pre$cols[i]))
    # 대표 날짜: 각 축이 쓴 관측일
    sp <- .re_values_from(kgrid, inp$obs, "pit")$used
    for (d in check_dates) {
      d <- as.Date(d, origin = "1970-01-01")
      u <- sp[Date == max(cal[cal <= d])]
      if (nrow(u)) cat(sprintf("  %s 결정 사용 관측일: %s\n", u$Date,
        paste(sprintf("%s=%s", REGIME_DAILY_AXES$col,
                      vapply(REGIME_DAILY_AXES$col, function(cl) format(u[[cl]]), "")), collapse = " ")))
    }
    cat(if (pass) "\n  PASS: 출력 열 시간축 = 가용시점 결합(누출판 일치 0 · 접두 불변)\n"
        else "\n  FAIL: 출력 열에 가용시점 위반 또는 기준선 불일치 — 결과 무효 처리 대상\n")
    cat("==============================================================\n")
  }
  invisible(list(pass = pass, per_col = per, prefix = pre, coverage_missing = cover_missing,
                 locf_mism = locf_mism, pre_first_rows = pre_first, missing_cols = miss_cols))
}


#==============================================================================
# INTEGRATION HELPER: merge_daily_regime(FACTORS)
# Drop-in replacement for merge_regime_to_signals() / merge_regime_signal()
#   mode = "decision_close"  (기본·구판 동작): FACTORS Date d = 한국 d 종가 결정일 → 행 ≤ d
#   mode = "exposure_return" : FACTORS Date t = 수익 r_t(한국 t−1 종가→t 종가)의 날짜
#                              → 직전 한국 거래일 행(판정서 ② 형태 b)
#==============================================================================

merge_daily_regime <- function(FACTORS, regime_dt = NULL,
                               mode = c("decision_close", "exposure_return")) {
  mode <- match.arg(mode)
  if (is.null(regime_dt)) {
    if (file.exists(REGIME_DAILY_CACHE)) {
      regime_dt <- as.data.table(read_parquet(REGIME_DAILY_CACHE))
      regime_dt[, Date := as.Date(Date)]
    } else {
      regime_dt <- build_daily_regime()
    }
  }

  # Prepare for rolling join
  regime_join <- regime_dt[, .(Date = as.Date(Date), MRS, exposure, n_axes_firing)]
  setkey(regime_join, Date)

  # Get unique dates from FACTORS
  sig_dates <- sort(unique(as.Date(FACTORS$Date)))
  look <- if (mode == "decision_close") sig_dates else {
    .re_need_fred_avail()
    fred_decision_date(sig_dates, "exposure_return", kr_calendar = .re_kr_calendar())
  }

  # Rolling join (행 ≤ 결정일)
  m <- regime_join[data.table(Date = look), on = "Date", roll = TRUE]
  matched <- data.table(Date = sig_dates, MRS = m$MRS, exposure = m$exposure,
                        n_axes_firing = m$n_axes_firing)

  # Remove existing regime columns if any
  for (col in c("MRS", "exposure", "n_axes_firing",
                "Macro_Risk_Score", "Regime_Score")) {
    if (col %in% names(FACTORS)) FACTORS[, (col) := NULL]
  }

  FACTORS <- merge(FACTORS, matched, by = "Date", all.x = TRUE)

  n_matched <- sum(!is.na(FACTORS$MRS))
  cat(sprintf("[regime_daily_v2] Merged (%s): %d/%d dates with MRS (%.1f%%)\n", mode,
              n_matched, uniqueN(FACTORS$Date),
              n_matched / max(1, uniqueN(FACTORS$Date)) * 100))

  FACTORS
}


#==============================================================================
# LOADED MESSAGE
#==============================================================================

cat("[regime_engine_daily_v2] Loaded (v2.1 PIT C11 가용시점). Functions:\n")
cat("  build_daily_regime(target_dates)      -- 9-axis daily MRS, 행 d = 한국 d 15:30 결정 가용분\n")
cat("  regime_daily_diagnostics(target_dates) -- compare with old monthly engine\n")
cat("  regime_daily_backtest_check(dates)     -- 출력 열 시간축 자체검증(기준선·누출판·접두 불변)\n")
cat("  merge_daily_regime(FACTORS, mode=)     -- decision_close(행≤d) | exposure_return(직전 거래일 행)\n")
