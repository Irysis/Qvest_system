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
#   환율:   DEXKOUS (KRW/USD) — ★수집만(원본 보존·타 소비자 호환). PIT 결합 사용 금지:
#           decision_register PIT-C11-CONVENTIONS ① → 원/달러는 ECOS 731Y001(.cache/ecos_krw_usd.parquet)
#           을 쓴다. fred_availability 규칙에서 DEXKOUS·KRW_USD 는 status=prohibited(결합 거부).
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
#
# ★PIT C11 수리 (2026-09-24 · 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md V-14·1-3):
#   fred_compute_regime() 의 월 행 = 그 달 마지막 한국 거래일 15:30 KST 까지 **공표된** 관측만
#   (fred_availability.R::fred_asof_join · 규칙 06_Registry/fred_availability_rules.json — 이 파일에
#   오프셋 수치 없음). 구판은 월내 마지막 관측(같은 날짜 미국 종가·미공표 주간값·같은 달 CPI)을 실었다.
#   Asof_Date 열 = 그 행의 결정일. CPI_YoY = 날짜 기준 12개월 변화(CONVENTIONS ③).
#   merge_regime_to_signals() 는 Asof_Date ≤ 신호일로 결합한다(구판: 월말 라벨 roll, lag 없음).
#   값은 최신 빈티지(ALFRED 미수집 — 안 C): 개정 계열은 C1·C11 미해소 라벨.
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

  # 글로벌 위험선호 / Canary (RE16_Canary_Signal source) — 2026-05-29 추가
  # FRED SP500 라이선스 제약: 최근 ~10년만 제공 (현재 2016-05-31~). 그 이전은
  # 데이터 자체가 FRED에서 미제공 → RE16은 2016-08 이후만 backfill 가능 (정직).
  list(id = "SP500",     name = "SP500",              freq = "d",
       desc = "S&P 500 Index (canary momentum, ~10y FRED license window)"),

  # 환율 (Exchange Rates)
  # ★PIT C11: 수집은 유지(원본 보존 · AE 등 미이관 소비자 호환)하되 결합 사용 금지 —
  #   decision_register PIT-C11-CONVENTIONS ① → ECOS 731Y001(ECOS_KRW_USD). 아래 pit 필드는 표식이다.
  list(id = "DEXKOUS",   name = "KRW_USD",            freq = "d",
       desc = "Korean Won / US Dollar",
       pit = "prohibited", replacement = "ECOS_KRW_USD"),

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

#------------------------------------------------------------------------------
# 4a. PIT C11 가용시점 도우미 (2026-09-24) — 규칙·결합은 fred_availability.R 가 정본
#     도우미가 없으면 fail-closed(stop): 호출자(fred_run_pipeline·daily_refresh)의 tryCatch 가
#     잡아 구 macro_regime 을 보존한다 — 관측일 결합판을 새로 쓰지 않는다.
#------------------------------------------------------------------------------
.fc_need_fred_avail <- function() {
  if (exists("fred_asof_join", mode = "function") && exists("fred_series_rule", mode = "function"))
    return(invisible(TRUE))
  cands <- unique(c(if (exists("DATA_DIR")) file.path(DATA_DIR, "fred_availability.R"),
                    if (exists("FUNC_PATH")) file.path(FUNC_PATH, "data", "fred_availability.R"),
                    file.path(PROJECT_ROOT, "02_Infrastructure", "data", "fred_availability.R")))
  p <- cands[file.exists(cands)][1]
  if (is.na(p)) stop("[fred] fred_availability.R 없음 — 가용시점 결합 불가(fail-closed)")
  source(p)
  invisible(TRUE)
}

.fc_kr_calendar <- function() {
  .fc_need_fred_avail()
  fred_kr_calendar(file.path(CACHE_DIR, "trading_calendar.parquet"))
}

# long(Date, Series, Series_ID, Value) 또는 wide(Date × 친근명 — 구 호출 규약) → long
.fc_as_long <- function(x) {
  x <- as.data.table(x)
  if (all(c("Date", "Series", "Value") %in% names(x))) {
    sid <- if ("Series_ID" %in% names(x)) as.character(x$Series_ID) else as.character(x$Series)
    out <- data.table(Date = as.Date(x$Date), Series = as.character(x$Series),
                      Series_ID = sid, Value = as.numeric(x$Value))
  } else {
    cols <- setdiff(names(x), c("Date", "YM"))
    out <- melt(x[, c("Date", cols), with = FALSE], id.vars = "Date",
                variable.name = "Series", value.name = "Value", variable.factor = FALSE)
    out <- out[, .(Date = as.Date(Date), Series = as.character(Series),
                   Series_ID = as.character(Series), Value = as.numeric(Value))]
  }
  out[!is.na(Date) & !is.na(Value)]
}

# 원/달러 = ECOS 731Y001 (decision_register PIT-C11-CONVENTIONS ① — DEXKOUS 대체)
.fc_load_ecos_krw <- function() {
  p <- file.path(CACHE_DIR, "ecos_krw_usd.parquet")
  if (!file.exists(p)) return(NULL)
  e <- as.data.table(read_parquet(p, mmap = FALSE))
  if (!all(c("Date", "KRW_USD") %in% names(e))) stop("[fred] ecos_krw_usd.parquet 스키마 불일치: ", p)
  unique(e[!is.na(Date) & !is.na(KRW_USD), .(Date = as.Date(Date), Value = as.numeric(KRW_USD))])
}

fred_compute_regime <- function(macro_dt = NULL, kr_calendar = NULL) {
  .fc_need_fred_avail()
  long <- .fc_as_long(if (is.null(macro_dt)) load_fred_macro(wide = FALSE) else macro_dt)
  cal <- if (is.null(kr_calendar)) .fc_kr_calendar() else sort(unique(as.Date(kr_calendar)))

  cat("[fred] Computing macro regime signals (PIT C11: 월 행 = 그 달 마지막 한국 거래일 15:30 KST 까지 공표분)...\n")

  # 월 목록 = 첫 관측 월 ~ 마지막 관측 월 (구판과 같은 범위). Date = 해당월 말일(구판 규약 유지).
  # ★구판은 월내 마지막 관측(같은 날짜 미국 종가 · 공표 전 주간값 · 같은 달 CPI 라벨)을 실었다(V-14).
  #   새 판: 결정일 Asof_Date = 말일 이하 마지막 한국 거래일, 각 계열 = 그 결정일에 가용한 최신 관측
  #   (fred_asof_join decision_close — 월간 보유(판정서 ② 원칙 c)의 가장 이른 집행 시점 기준이라
  #   close_d_legacy(sig_d)·close_t1(집행일) 어느 쪽에도 미래 정보가 없다).
  m0 <- as.Date(format(min(long$Date), "%Y-%m-01"))
  m1 <- as.Date(format(max(long$Date), "%Y-%m-01"))
  yms <- format(seq(m0, m1, by = "month"), "%Y-%m")
  me  <- as.Date(cut(as.Date(paste0(yms, "-01")) + 31, "month")) - 1
  ii  <- findInterval(as.integer(me), as.integer(cal))
  dec <- rep(NA_integer_, length(yms)); dec[ii > 0L] <- as.integer(cal)[ii[ii > 0L]]
  dec <- as.Date(dec)
  monthly <- data.table(YM = yms, Date = me, Asof_Date = dec)
  ok <- which(!is.na(dec))

  sids <- unique(long[, .(Series_ID, Series)])
  sids <- sids[!duplicated(Series_ID)]
  skipped <- character(0); cpi <- NULL
  for (k in seq_len(nrow(sids))) {
    sid <- sids$Series_ID[k]; nm <- sids$Series[k]
    rule <- tryCatch(fred_series_rule(sid), error = function(e) e)
    if (inherits(rule, "error")) { skipped <- c(skipped, sid); next }   # 규칙 없음·사용 금지 = 결합 안 함
    obs <- unique(long[Series_ID == sid, .(Date, Value)])
    j <- fred_asof_join(dec[ok], obs, sid, mode = "decision_close", kr_calendar = cal)
    monthly[, (nm) := NA_real_]
    set(monthly, ok, nm, j$value)
    if (identical(rule$id, "CPIAUCSL")) {
      cpi_obs <- as.Date(rep(NA_integer_, nrow(monthly))); cpi_obs[ok] <- j$obs_date
      cpi <- list(col = nm, obs_date = cpi_obs, series = obs)
    }
  }
  if (length(skipped))
    cat(sprintf("  결합 제외(규칙 없음·사용 금지 — fail-closed): %s\n", paste(skipped, collapse = ", ")))

  # 원/달러 = ECOS 731Y001. 열 이름 KRW_USD 는 구판 스키마 그대로, 값의 원천만 교체.
  monthly[, KRW_USD := NA_real_]
  ek <- .fc_load_ecos_krw()
  if (!is.null(ek) && nrow(ek)) {
    set(monthly, ok, "KRW_USD",
        fred_asof_join(dec[ok], ek, "ECOS_KRW_USD", mode = "decision_close", kr_calendar = cal)$value)
  } else warning("[fred] ecos_krw_usd.parquet 없음 — KRW_USD NA(KRW_Stress 축 0)")

  ser_cols <- sort(setdiff(names(monthly), c("YM", "Date", "Asof_Date")), method = "radix")
  setcolorder(monthly, c("YM", ser_cols, "Date", "Asof_Date"))

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
    # 날짜 기준 12개월 변화(decision_register PIT-C11-CONVENTIONS ③): 가용 관측 o 의 값 / o−12개월 관측값.
    #   구판 shift(US_CPI, 12)는 행 기준이라 관측이 빠진 달(CPI 2025-10)에 13개월 변화가 됐다.
    #   o−12개월 관측이 없으면 NA.
    if (!is.null(cpi)) {
      o <- cpi$obs_date
      prev <- rep(as.Date(NA), length(o)); has <- !is.na(o)
      prev[has] <- as.Date(sprintf("%04d-%02d-%s", as.integer(format(o[has], "%Y")) - 1L,
                                   as.integer(format(o[has], "%m")), format(o[has], "%d")))
      v_prev <- cpi$series$Value[match(prev, cpi$series$Date)]
      monthly[, CPI_YoY := get(cpi$col) / v_prev - 1]
    } else monthly[, CPI_YoY := NA_real_]
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

  # 저장 (결정일이 없는 달 = 한국 달력 이전 — 싣지 않는다)
  regime_dt <- monthly[!is.na(Date) & !is.na(Asof_Date)]
  setorder(regime_dt, Date)
  # 측정 epoch 표식(parquet R 메타데이터) + ★r1 표식 계약(overlay_pit_guard C11 층 · 통합 검증 BLOCKING):
  #   행 열 avail_date(Date) = Asof_Date(그 행 값이 가용해진 한국 결정일) · 행 열 c11_regime_key.
  .dcf_key <- tryCatch(fred_avail_rules_meta()$regime_key, error = function(e) NA_character_)
  regime_dt[, avail_date := as.Date(Asof_Date)]
  regime_dt[, c11_regime_key := as.character(.dcf_key)]
  setattr(regime_dt, "c11_avail_regime_key", .dcf_key)
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
  regime_dt <- as.data.table(regime_dt)
  # ★PIT C11(2026-09-24, 판정서 1-3 잠재 위반): 결합 키 = 결정일 Asof_Date(그 행 값이 가용해진 한국
  #   거래일). 구판은 월말 라벨 Date 로 lag 없이 roll 결합했다. Asof_Date 가 없는 캐시는 수리 전 판
  #   (월말 라벨 행에 공표 전 값) → 결합 거부(fail-closed). FACTORS Date = 한국 d 종가 결정일(형태 a).
  if (!("Asof_Date" %in% names(regime_dt)))
    stop("[fred] macro_regime 에 Asof_Date 가 없다 — C11 수리 전 캐시(월말 라벨 = 공표 전 값). ",
         "fred_compute_regime() 로 재생성할 것(fail-closed)")

  # Rolling join: 각 시그널 날짜 d 에 Asof_Date ≤ d 인 가장 최근 행
  regime_cols <- intersect(
    names(regime_dt),
    c("VIX", "VIX_Regime", "VIX_Zscore",
      "Term_Spread", "YC_Inversion", "HY_Spread", "Credit_Stress",
      "KRW_USD", "KRW_Stress", "CPI_YoY", "Inflation_Regime",
      "Macro_Risk_Score", "Buddha_Mode")
  )

  regime_sub <- regime_dt[!is.na(Asof_Date), c("Asof_Date", regime_cols), with = FALSE]
  regime_sub[, Asof_Date := as.Date(Asof_Date)]
  setnames(regime_sub, "Asof_Date", "Date")
  setkey(regime_sub, Date)

  # FACTORS는 (Date, Ticker, Score, ...) 형태
  # Date 기준으로 regime 매칭 (Ticker 무관 — macro는 시장 전체)
  unique_dates <- sort(unique(as.Date(FACTORS$Date)))
  date_regime <- regime_sub[data.table(Date = unique_dates), on = "Date", roll = TRUE]

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
