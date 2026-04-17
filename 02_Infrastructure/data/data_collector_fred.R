#==============================================================================
# Quant Module — FRED API Macro Data Collector
# Version: 1.0.0
#
# Federal Reserve Economic Data (FRED) API를 통해
# 글로벌 매크로 지표를 수집하여 레짐 탐지 및 매크로 팩터에 활용.
#
# 수집 시리즈:
#   금리:   DGS10 (US 10Y), DGS2 (US 2Y), FEDFUNDS, T10Y2Y (Term Spread)
#   변동성: VIXCLS (VIX)
#   환율:   DEXKOUS (KRW/USD)
#   경기:   UNRATE (실업률), CPIAUCSL (CPI), INDPRO (산업생산)
#   유동성: M2SL (M2 통화량), WALCL (Fed Balance Sheet)
#   신용:   BAMLH0A0HYM2 (HY Spread), T10YIE (Breakeven Inflation)
#
# 사용법:
#   source("config.R")
#   source("data_collector_fred.R")
#   fred_fetch_all()                    # 전체 시리즈 수집
#   macro <- load_fred_macro()          # 캐시에서 로드
#   regime <- fred_compute_regime()     # 레짐 시그널 계산
#
# API 제한: 분당 120건 (API key당)
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(httr)
  library(jsonlite)
})

cat("[fred_collector] Loaded.\n")

# ─── Paths ──────────────────────────────────────────────────────────────────
FRED_CACHE <- file.path(CACHE_DIR, "macro_fred.parquet")
FRED_REGIME_CACHE <- file.path(CACHE_DIR, "macro_regime.parquet")

# ─── API Key ────────────────────────────────────────────────────────────────
.load_fred_key <- function() {
  env_path <- file.path(PROJECT_ROOT, ".env")
  if (!file.exists(env_path)) stop("[fred] .env file not found at: ", env_path)

  lines <- readLines(env_path, warn = FALSE)
  for (line in lines) {
    if (grepl("^FRED_API_KEY=", line)) {
      key <- sub("^FRED_API_KEY=", "", trimws(line))
      if (nchar(key) < 10) stop("[fred] FRED_API_KEY is empty or too short in .env")
      return(key)
    }
  }
  stop("[fred] FRED_API_KEY not found in .env")
}

FRED_API_KEY <- .load_fred_key()

# ─── Series Definitions ─────────────────────────────────────────────────────
FRED_SERIES <- list(
  # 금리 (Interest Rates)
  list(id = "DGS10",     name = "US_10Y_Yield",      freq = "d",
       desc = "US Treasury 10-Year Yield"),
  list(id = "DGS2",      name = "US_2Y_Yield",       freq = "d",
       desc = "US Treasury 2-Year Yield"),
  list(id = "FEDFUNDS",  name = "Fed_Funds_Rate",     freq = "m",
       desc = "Federal Funds Effective Rate"),
  list(id = "T10Y2Y",    name = "Term_Spread",        freq = "d",
       desc = "10Y-2Y Treasury Spread (Yield Curve)"),

  # 변동성 (Volatility)
  list(id = "VIXCLS",    name = "VIX",                freq = "d",
       desc = "CBOE VIX Index"),

  # 환율 (Exchange Rates)
  list(id = "DEXKOUS",   name = "KRW_USD",            freq = "d",
       desc = "Korean Won / US Dollar"),

  # 경기 (Economic Activity)
  list(id = "UNRATE",    name = "US_Unemployment",    freq = "m",
       desc = "US Unemployment Rate"),
  list(id = "CPIAUCSL",  name = "US_CPI",             freq = "m",
       desc = "US CPI (All Urban, Seasonally Adj)"),
  list(id = "INDPRO",    name = "US_IndProd",         freq = "m",
       desc = "US Industrial Production Index"),

  # 유동성 (Liquidity)
  list(id = "M2SL",      name = "US_M2",              freq = "m",
       desc = "US M2 Money Stock"),
  list(id = "WALCL",     name = "Fed_BalSheet",       freq = "w",
       desc = "Fed Total Assets (Balance Sheet)"),

  # 신용 (Credit)
  list(id = "BAMLH0A0HYM2", name = "HY_Spread",      freq = "d",
       desc = "ICE BofA US High Yield OAS"),
  list(id = "T10YIE",    name = "Breakeven_Infl",     freq = "d",
       desc = "10-Year Breakeven Inflation Rate"),

  # ─── 레짐엔진 강화 시리즈 (2026-03-14 추가) ────────────────────────────
  # 금융 스트레스 (Financial Stress)
  list(id = "STLFSI4",   name = "StL_Fin_Stress",     freq = "w",
       desc = "St. Louis Fed Financial Stress Index"),
  list(id = "NFCI",      name = "Chi_Fin_Cond",       freq = "w",
       desc = "Chicago Fed National Financial Conditions Index"),

  # 실시간 고용 (Real-time Labor)
  list(id = "ICSA",      name = "Init_Claims",        freq = "w",
       desc = "Initial Unemployment Claims"),

  # 소비 심리 (Consumer Sentiment)
  list(id = "UMCSENT",   name = "UMich_Sentiment",    freq = "m",
       desc = "University of Michigan Consumer Sentiment"),

  # 신용 경색 선행 (Credit Cycle Leading)
  list(id = "DRTSCILM",  name = "Bank_Lending_Std",   freq = "q",
       desc = "Net % Banks Tightening C&I Lending Standards"),

  # 투자적격 스프레드 (IG Credit)
  list(id = "BAMLC0A4CBBB", name = "BBB_Spread",     freq = "d",
       desc = "ICE BofA BBB US Corporate OAS"),

  # 단기 인플레 기대 (Short-term Inflation Expectations)
  list(id = "T5YIE",     name = "Breakeven_5Y",       freq = "d",
       desc = "5-Year Breakeven Inflation Rate"),

  # 경기 선행 (Leading Indicators)
  list(id = "PERMIT",    name = "Housing_Permits",    freq = "m",
       desc = "New Housing Units Authorized (Building Permits)"),

  # 글로벌 성장 (Global Growth Barometer)
  list(id = "PCOPPUSDM", name = "Copper_Price",       freq = "m",
       desc = "Global Copper Price (Dr. Copper)")
)


#==============================================================================
# 1. Fetch Single Series
#==============================================================================

.fred_fetch_series <- function(series_id, start_date = "2000-01-01",
                                end_date = NULL) {
  if (is.null(end_date)) end_date <- format(Sys.Date(), "%Y-%m-%d")

  url <- "https://api.stlouisfed.org/fred/series/observations"

  resp <- GET(url, query = list(
    series_id  = series_id,
    api_key    = FRED_API_KEY,
    file_type  = "json",
    observation_start = start_date,
    observation_end   = end_date
  ), timeout(30))

  if (status_code(resp) != 200) {
    warning(sprintf("[fred] HTTP %d for %s", status_code(resp), series_id))
    return(NULL)
  }

  body <- content(resp, "text", encoding = "UTF-8")
  json <- tryCatch(fromJSON(body), error = function(e) NULL)

  if (is.null(json) || is.null(json$observations)) return(NULL)

  obs <- as.data.table(json$observations)
  if (nrow(obs) == 0) return(NULL)

  # FRED uses "." for missing values
  obs[, value := suppressWarnings(as.numeric(value))]
  obs[, date := as.Date(date)]
  obs <- obs[!is.na(value), .(Date = date, Value = value)]

  obs
}


#==============================================================================
# 2. Fetch All Series
#==============================================================================

fred_fetch_all <- function(start_date = "2000-01-01") {
  cat(sprintf("[fred] Fetching %d macro series from FRED...\n", length(FRED_SERIES)))

  all_data <- list()

  for (s in FRED_SERIES) {
    cat(sprintf("  > %-20s (%s)... ", s$name, s$id))

    dt <- tryCatch(
      .fred_fetch_series(s$id, start_date),
      error = function(e) {
        cat(sprintf("ERROR: %s\n", e$message))
        NULL
      }
    )

    if (!is.null(dt) && nrow(dt) > 0) {
      dt[, Series := s$name]
      dt[, Series_ID := s$id]
      dt[, Frequency := s$freq]
      all_data[[s$name]] <- dt
      cat(sprintf("%d obs (%s ~ %s)\n", nrow(dt), min(dt$Date), max(dt$Date)))
    } else {
      cat("EMPTY\n")
    }

    Sys.sleep(0.5)  # Rate limit safety
  }

  if (length(all_data) == 0) {
    warning("[fred] No data fetched!")
    return(NULL)
  }

  # Long format → Parquet 저장
  long_dt <- rbindlist(all_data, fill = TRUE)
  write_parquet(long_dt, FRED_CACHE)
  cat(sprintf("\n[fred] Saved %d total observations | %d series\n",
              nrow(long_dt), uniqueN(long_dt$Series)))
  cat(sprintf("[fred] Cache: %s\n", FRED_CACHE))

  # Wide format도 반환 (편의용)
  wide_dt <- dcast(long_dt, Date ~ Series, value.var = "Value")
  setorder(wide_dt, Date)

  invisible(list(long = long_dt, wide = wide_dt))
}


#==============================================================================
# 3. Load from Cache
#==============================================================================

load_fred_macro <- function(wide = TRUE) {
  if (!file.exists(FRED_CACHE)) {
    stop("[fred] Macro cache not found. Run fred_fetch_all() first.")
  }

  long_dt <- as.data.table(read_parquet(FRED_CACHE))

  if (wide) {
    wide_dt <- dcast(long_dt, Date ~ Series, value.var = "Value")
    setorder(wide_dt, Date)
    return(wide_dt)
  }

  long_dt
}


#==============================================================================
# 4. Compute Regime Signals (매크로 레짐 지표)
#==============================================================================

fred_compute_regime <- function(macro_dt = NULL) {
  if (is.null(macro_dt)) macro_dt <- load_fred_macro(wide = TRUE)

  cat("[fred] Computing macro regime signals...\n")

  # 월말 데이터로 리샘플링 (전략 시그널과 정렬)
  macro_dt[, YM := format(Date, "%Y-%m")]
  monthly <- macro_dt[, lapply(.SD, function(x) tail(x[!is.na(x)], 1)),
                       by = YM,
                       .SDcols = setdiff(names(macro_dt), c("Date", "YM"))]
  monthly[, Date := as.Date(paste0(YM, "-01")) + 31]  # 대략 월말
  # 실제 월말로 보정
  monthly[, Date := as.Date(format(Date, "%Y-%m-01")) - 1]
  # 월초로 다시 (다음달 1일 - 1일 = 해당월 말일)
  monthly[, Date := as.Date(paste0(YM, "-01"))]
  monthly[, Date := as.Date(cut(Date + 31, "month")) - 1]  # 해당월 말일

  # ── 레짐 시그널 계산 ──

  # 1. Yield Curve Inversion Signal
  #    Term_Spread < 0 → recession warning
  if ("Term_Spread" %in% names(monthly)) {
    monthly[, YC_Inversion := fifelse(
      !is.na(Term_Spread) & Term_Spread < 0, TRUE, FALSE
    )]
    # 3개월 이동평균
    monthly[, Term_Spread_MA3 := frollmean(Term_Spread, 3, align = "right")]
  }

  # 2. VIX Regime
  #    VIX > 30 → High Vol (Risk-off)
  #    VIX > 20 → Elevated
  #    VIX <= 20 → Normal
  if ("VIX" %in% names(monthly)) {
    monthly[, VIX_Regime := fifelse(
      is.na(VIX), "unknown",
      fifelse(VIX > 30, "crisis",
              fifelse(VIX > 20, "elevated", "normal"))
    )]
    monthly[, VIX_MA3 := frollmean(VIX, 3, align = "right")]
    monthly[, VIX_Zscore := (VIX - frollmean(VIX, 12, align = "right")) /
              frollapply(VIX, 12, sd, align = "right")]
  }

  # 3. KRW Stress Signal
  #    KRW/USD 급등 = 원화 약세 = 위험 회피
  if ("KRW_USD" %in% names(monthly)) {
    monthly[, KRW_MA6 := frollmean(KRW_USD, 6, align = "right")]
    monthly[, KRW_Stress := fifelse(
      !is.na(KRW_USD) & !is.na(KRW_MA6) & KRW_USD > KRW_MA6 * 1.05,
      TRUE, FALSE
    )]
  }

  # 4. Credit Stress Signal
  #    HY Spread > 500bp (5.0%) → credit stress
  if ("HY_Spread" %in% names(monthly)) {
    monthly[, Credit_Stress := fifelse(
      !is.na(HY_Spread) & HY_Spread > 5.0, TRUE, FALSE
    )]
    monthly[, HY_Spread_MA3 := frollmean(HY_Spread, 3, align = "right")]
  }

  # 5. Inflation Regime
  #    CPI YoY > 4% → high inflation
  if ("US_CPI" %in% names(monthly)) {
    monthly[, CPI_YoY := US_CPI / shift(US_CPI, 12) - 1]
    monthly[, Inflation_Regime := fifelse(
      is.na(CPI_YoY), "unknown",
      fifelse(CPI_YoY > 0.04, "high",
              fifelse(CPI_YoY > 0.02, "moderate", "low"))
    )]
  }

  # ── 6~10. 레짐엔진 강화 시그널 (2026-03-14 추가) ──

  # 6. Financial Stress Index (STLFSI4)
  #    > 0 → above-average stress, > 1.5 → severe
  if ("StL_Fin_Stress" %in% names(monthly)) {
    monthly[, Fin_Stress_Regime := fifelse(
      is.na(StL_Fin_Stress), "unknown",
      fifelse(StL_Fin_Stress > 1.5, "severe",
              fifelse(StL_Fin_Stress > 0, "elevated", "normal"))
    )]
  }

  # 7. NFCI — negative=loose, positive=tight
  if ("Chi_Fin_Cond" %in% names(monthly)) {
    monthly[, NFCI_Tight := fifelse(
      !is.na(Chi_Fin_Cond) & Chi_Fin_Cond > 0, TRUE, FALSE
    )]
  }

  # 8. Initial Claims — 4주 이동평균 급등 체크
  if ("Init_Claims" %in% names(monthly)) {
    monthly[, Claims_MA3 := frollmean(Init_Claims, 3, align = "right")]
    monthly[, Claims_Spike := fifelse(
      !is.na(Init_Claims) & !is.na(Claims_MA3) & Init_Claims > Claims_MA3 * 1.15,
      TRUE, FALSE
    )]
  }

  # 9. Consumer Sentiment — below 60 = recession warning
  if ("UMich_Sentiment" %in% names(monthly)) {
    monthly[, Sentiment_Weak := fifelse(
      !is.na(UMich_Sentiment) & UMich_Sentiment < 60, TRUE, FALSE
    )]
  }

  # 10. BBB Spread widening — > 2.0% = stress
  if ("BBB_Spread" %in% names(monthly)) {
    monthly[, BBB_Stress := fifelse(
      !is.na(BBB_Spread) & BBB_Spread > 2.0, TRUE, FALSE
    )]
    monthly[, BBB_Spread_MA3 := frollmean(BBB_Spread, 3, align = "right")]
  }

  # ── Composite Macro Regime Score (0-100, 높을수록 위험) ──
  # v1: VIX(30) + YC(25) + HY(25) + KRW(20) = 100
  # v2: 기존 4축 + 신규 5축 = 총 9축, 재배분
  monthly[, Macro_Risk_Score := 0]

  # Axis 1: VIX (max 20)
  if ("VIX" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(VIX_Regime) & VIX_Regime == "crisis", 20,
                      fifelse(!is.na(VIX_Regime) & VIX_Regime == "elevated", 10, 0))]
  }
  # Axis 2: Yield Curve (max 15)
  if ("Term_Spread" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(YC_Inversion) & YC_Inversion, 15, 0)]
  }
  # Axis 3: HY Spread (max 15)
  if ("HY_Spread" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(Credit_Stress) & Credit_Stress, 15, 0)]
  }
  # Axis 4: KRW Stress (max 10)
  if ("KRW_USD" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(KRW_Stress) & KRW_Stress, 10, 0)]
  }
  # Axis 5: Financial Stress Index (max 10)
  if ("StL_Fin_Stress" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(Fin_Stress_Regime) & Fin_Stress_Regime == "severe", 10,
                      fifelse(!is.na(Fin_Stress_Regime) & Fin_Stress_Regime == "elevated", 5, 0))]
  }
  # Axis 6: NFCI Tightening (max 8)
  if ("Chi_Fin_Cond" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(NFCI_Tight) & NFCI_Tight, 8, 0)]
  }
  # Axis 7: Claims Spike (max 8)
  if ("Init_Claims" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(Claims_Spike) & Claims_Spike, 8, 0)]
  }
  # Axis 8: Consumer Sentiment Weak (max 7)
  if ("UMich_Sentiment" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(Sentiment_Weak) & Sentiment_Weak, 7, 0)]
  }
  # Axis 9: BBB Spread Stress (max 7)
  if ("BBB_Spread" %in% names(monthly)) {
    monthly[, Macro_Risk_Score := Macro_Risk_Score +
              fifelse(!is.na(BBB_Stress) & BBB_Stress, 7, 0)]
  }

  # Buddha Mode: Macro_Risk_Score >= 70 → full cash recommended (임계값 유지)
  monthly[, Buddha_Mode := Macro_Risk_Score >= 70]

  # 저장
  regime_dt <- monthly[!is.na(Date)]
  setorder(regime_dt, Date)
  write_parquet(regime_dt, FRED_REGIME_CACHE)

  cat(sprintf("[fred] Regime signals: %d months | %s ~ %s\n",
              nrow(regime_dt), min(regime_dt$Date), max(regime_dt$Date)))
  cat(sprintf("[fred] Cache: %s\n", FRED_REGIME_CACHE))

  # 최근 레짐 요약
  latest <- tail(regime_dt[!is.na(Macro_Risk_Score)], 1)
  if (nrow(latest) > 0) {
    cat(sprintf("\n[fred] Latest regime (%s):\n", latest$Date))
    if ("VIX_Regime" %in% names(latest))
      cat(sprintf("  VIX Regime:     %s (%.1f)\n", latest$VIX_Regime,
                  latest$VIX %||% NA))
    if ("YC_Inversion" %in% names(latest))
      cat(sprintf("  Yield Curve:    %s (spread: %.2f)\n",
                  if (latest$YC_Inversion) "INVERTED" else "Normal",
                  latest$Term_Spread %||% NA))
    if ("Credit_Stress" %in% names(latest))
      cat(sprintf("  Credit:         %s (HY: %.1fbp)\n",
                  if (latest$Credit_Stress) "STRESS" else "Normal",
                  (latest$HY_Spread %||% 0) * 100))
    cat(sprintf("  Risk Score:     %d/100\n", latest$Macro_Risk_Score))
    cat(sprintf("  Buddha Mode:    %s\n", if (latest$Buddha_Mode) "ON" else "OFF"))
  }

  invisible(regime_dt)
}


#==============================================================================
# 5. Merge Regime to Signals — 전략 시그널에 매크로 레짐 붙이기
#==============================================================================

merge_regime_to_signals <- function(FACTORS, regime_dt = NULL) {
  if (is.null(regime_dt)) {
    if (!file.exists(FRED_REGIME_CACHE)) {
      stop("[fred] Regime cache not found. Run fred_compute_regime() first.")
    }
    regime_dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
  }

  # Rolling join: 각 시그널 날짜에 가장 가까운 이전 레짐 데이터 매칭
  regime_cols <- intersect(
    names(regime_dt),
    c("Date", "VIX", "VIX_Regime", "VIX_Zscore",
      "Term_Spread", "YC_Inversion", "HY_Spread", "Credit_Stress",
      "KRW_USD", "KRW_Stress", "CPI_YoY", "Inflation_Regime",
      "Macro_Risk_Score", "Buddha_Mode")
  )

  regime_sub <- regime_dt[, ..regime_cols]
  setkey(regime_sub, Date)
  setkey(FACTORS, Date)

  # FACTORS는 (Date, Ticker, Score, ...) 형태
  # Date 기준으로 regime 매칭 (Ticker 무관 — macro는 시장 전체)
  unique_dates <- unique(FACTORS$Date)
  date_regime <- regime_sub[J(unique_dates), roll = TRUE]

  merged <- merge(FACTORS, date_regime, by = "Date", all.x = TRUE,
                  suffixes = c("", "_macro"))

  cat(sprintf("[fred] Merged regime: %d of %d dates matched\n",
              sum(!is.na(merged$Macro_Risk_Score)), uniqueN(merged$Date)))

  merged
}


#==============================================================================
# 6. Master Pipeline
#==============================================================================

fred_run_pipeline <- function(start_date = "2000-01-01") {
  cat("═══════════════════════════════════════════════\n")
  cat("[fred] Starting FRED macro data pipeline\n")
  cat("═══════════════════════════════════════════════\n\n")

  # Step 1: Fetch all series
  cat("── Step 1: Fetch macro series ──\n")
  fred_fetch_all(start_date)

  # Step 2: Compute regime signals
  cat("\n── Step 2: Compute regime signals ──\n")
  fred_compute_regime()

  cat("\n═══════════════════════════════════════════════\n")
  cat("[fred] Pipeline complete!\n")
  cat("═══════════════════════════════════════════════\n")
}
