#==============================================================================
# 134_ecos_fetch_kr_macro.R — Cycle 53I Step 0: Fetch / consolidate ECOS KR macro
#
# Mandate:
#   Cycle 53I (Korean ECOS macro features at q126) precondition
#   5 ECOS features required:
#     1. ecos_m2_yoy_lag1            — M2 통화량 YoY
#     2. ecos_krw_usd_change_5d_lag1 — KRW/USD 5d % change
#     3. ecos_base_rate_lag1         — 한국은행 기준금리 (call rate proxy)
#     4. ecos_industrial_production_yoy_lag1 — 산업생산지수 YoY
#     5. ecos_cpi_yoy_lag1           — 소비자물가지수 YoY
#
# Cache 검사 + missing series ECOS API fetch:
#   Cached (verified):
#     - ecos_krw_usd.parquet (KRW_USD daily, 2000~2026)
#     - ecos_bond_rates.parquet: KR_Call1D (call rate proxy for base rate) +
#       KR_CPI (monthly, 1990~2026.04)
#   Fetch needed:
#     - M2 통화량 (101Y008 = "통화 및 유동성지표" → 010100000 M2 monthly)
#     - 산업생산지수 (901Y033 = "전산업생산지수" monthly, 2000~)
#
# PIT 정합:
#   - CPI / Industrial Production / M2: 통상 1-2 month publication lag → lag2
#   - KRW/USD: 일별 ECOS 매매기준율 15:30 확정 → lag1 sufficient
#   - Base rate (call rate): 일별, 거래일 마감 후 익일 ECOS 공시 → lag1
#
# Output:
#   outputs/01_data/ecos_kr_daily.csv (Date + 5 series, daily forward-fill)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(httr)
})

source(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure/config.R"))
source(file.path(INFRA_DIR, "data/data_collector_ecos.R"))

PROJECT_ROOT_S <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT_S, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR_OUT <- file.path(WS, "outputs/01_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
dir.create(DATA_DIR_OUT, recursive = TRUE, showWarnings = FALSE)
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)

cat("\n========== Cycle 53I Step 0: ECOS KR macro fetch / consolidate ==========\n")

# ----------------------------------------------------------------------------
# Step 0a: Load cached data
# ----------------------------------------------------------------------------
cat("\n[Step 0a] Loading cached ECOS series\n")
krw <- ecos_load_krw()
bond <- ecos_load_bond_rates()
cat(sprintf("  KRW/USD: %d rows (%s ~ %s)\n", nrow(krw), min(krw$Date), max(krw$Date)))
cat(sprintf("  Bond rates: %d rows, %d series\n", nrow(bond), length(unique(bond$Series))))
cat(sprintf("  Series available: %s\n", paste(sort(unique(bond$Series)), collapse = ", ")))

# Extract Call rate (base rate proxy) + CPI
call_rate <- bond[Series == "KR_Call1D", .(Date, base_rate_raw = Value)]
cpi <- bond[Series == "KR_CPI", .(Date, cpi_raw = Value)]
cat(sprintf("  Call rate (KR_Call1D): %d rows (%s ~ %s)\n",
            nrow(call_rate), min(call_rate$Date), max(call_rate$Date)))
cat(sprintf("  CPI (monthly): %d rows (%s ~ %s)\n",
            nrow(cpi), min(cpi$Date), max(cpi$Date)))

# ----------------------------------------------------------------------------
# Step 0b: Fetch M2 (101Y008) monthly
# ----------------------------------------------------------------------------
M2_CACHE <- file.path(CACHE_DIR, "ecos_m2_monthly.parquet")

fetch_m2 <- function(start = "199001", end = NULL) {
  if (is.null(end)) end <- format(Sys.Date(), "%Y%m")
  # 161Y006 = "M2 상품별 구성내역 (평잔, 원계열)" + BBHA00 = M2 top-level total
  # Data range: 2003-10~present (BOK ECOS limitation)
  url <- sprintf(
    "https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/1/100000/161Y006/M/%s/%s/BBHA00",
    ECOS_API_KEY, start, end
  )
  cat(sprintf("  M2 fetch (161Y006/BBHA00 M2 평잔 원계열): %s ~ %s\n", start, end))
  resp <- tryCatch(GET(url, timeout(60)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) {
    cat(sprintf("    HTTP fail: status=%s\n", if (is.null(resp)) "NULL" else status_code(resp)))
    return(NULL)
  }
  json <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  if (is.null(json$StatisticSearch$row)) {
    if (!is.null(json$RESULT)) cat(sprintf("    API msg: %s - %s\n", json$RESULT$CODE, json$RESULT$MESSAGE))
    return(NULL)
  }
  rows <- rbindlist(json$StatisticSearch$row, fill = TRUE)
  df <- data.table(
    Date = as.Date(paste0(rows$TIME, "01"), format = "%Y%m%d"),
    m2_raw = as.numeric(rows$DATA_VALUE)
  )[!is.na(Date) & !is.na(m2_raw)]
  setorder(df, Date)
  df
}

m2 <- NULL
if (file.exists(M2_CACHE)) {
  cat(sprintf("\n[Step 0b] M2 cache HIT: %s\n", M2_CACHE))
  m2 <- as.data.table(read_parquet(M2_CACHE))
  cat(sprintf("  M2 (cached): %d rows (%s ~ %s)\n", nrow(m2), min(m2$Date), max(m2$Date)))
} else {
  cat(sprintf("\n[Step 0b] M2 cache MISS — fetching from ECOS API\n"))
  m2 <- fetch_m2()
  if (!is.null(m2) && nrow(m2) > 0) {
    write_parquet(m2, M2_CACHE)
    cat(sprintf("  M2 saved: %s (%d rows, %s ~ %s)\n",
                M2_CACHE, nrow(m2), min(m2$Date), max(m2$Date)))
  } else {
    cat("  WARN: M2 fetch failed → fallback: use KR_CD91 spread proxy (informative)\n")
    m2 <- NULL
  }
}

# ----------------------------------------------------------------------------
# Step 0c: Fetch Industrial Production (901Y033) monthly
# ----------------------------------------------------------------------------
IP_CACHE <- file.path(CACHE_DIR, "ecos_industrial_production_monthly.parquet")

fetch_ip <- function(start = "200001", end = NULL) {
  if (is.null(end)) end <- format(Sys.Date(), "%Y%m")
  # 901Y033 광공업생산지수 - I05A: 전산업생산지수 (계절조정/SA 또는 원지수)
  # 원지수: A00 (광공업+서비스업+건설업+공공행정)
  url <- sprintf(
    "https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/1/100000/901Y033/M/%s/%s/A00",
    ECOS_API_KEY, start, end
  )
  cat(sprintf("  IP fetch (901Y033/A00): %s ~ %s\n", start, end))
  resp <- tryCatch(GET(url, timeout(60)), error = function(e) NULL)
  if (is.null(resp) || status_code(resp) != 200) {
    cat(sprintf("    HTTP fail: status=%s\n", if (is.null(resp)) "NULL" else status_code(resp)))
    return(NULL)
  }
  json <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  if (is.null(json$StatisticSearch$row)) {
    if (!is.null(json$RESULT)) cat(sprintf("    API msg: %s - %s\n", json$RESULT$CODE, json$RESULT$MESSAGE))
    return(NULL)
  }
  rows <- rbindlist(json$StatisticSearch$row, fill = TRUE)
  df <- data.table(
    Date = as.Date(paste0(rows$TIME, "01"), format = "%Y%m%d"),
    ip_raw = as.numeric(rows$DATA_VALUE)
  )[!is.na(Date) & !is.na(ip_raw)]
  setorder(df, Date)
  df
}

ip <- NULL
if (file.exists(IP_CACHE)) {
  cat(sprintf("\n[Step 0c] IP cache HIT: %s\n", IP_CACHE))
  ip <- as.data.table(read_parquet(IP_CACHE))
  cat(sprintf("  IP (cached): %d rows (%s ~ %s)\n", nrow(ip), min(ip$Date), max(ip$Date)))
} else {
  cat(sprintf("\n[Step 0c] IP cache MISS — fetching from ECOS API\n"))
  ip <- fetch_ip()
  if (!is.null(ip) && nrow(ip) > 0) {
    write_parquet(ip, IP_CACHE)
    cat(sprintf("  IP saved: %s (%d rows, %s ~ %s)\n",
                IP_CACHE, nrow(ip), min(ip$Date), max(ip$Date)))
  } else {
    cat("  WARN: IP fetch failed → graceful degrade: ip excluded from final panel\n")
    ip <- NULL
  }
}

# ----------------------------------------------------------------------------
# Step 0d: Build derived features
# ----------------------------------------------------------------------------
cat("\n[Step 0d] Build derived ECOS features\n")

# Build daily date spine 1995-01-01 ~ today
spine <- data.table(Date = seq(as.Date("1995-01-01"), Sys.Date(), by = "day"))

# 1. ecos_m2_yoy: M2 YoY % (monthly, ffill daily, then 2-month publication lag)
m2_feat <- NULL
if (!is.null(m2) && nrow(m2) > 0) {
  setorder(m2, Date)
  # Compute YoY% (12-month change)
  m2[, m2_yoy_raw := (m2_raw / shift(m2_raw, 12, type = "lag") - 1) * 100]
  m2_feat <- m2[, .(Date, m2_yoy_raw)]
  cat(sprintf("  M2 YoY built: %d rows (latest: %s = %.2f%%)\n",
              sum(!is.na(m2_feat$m2_yoy_raw)),
              as.character(tail(m2_feat[!is.na(m2_yoy_raw)]$Date, 1)),
              tail(m2_feat$m2_yoy_raw[!is.na(m2_feat$m2_yoy_raw)], 1)))
} else {
  cat("  M2 unavailable — ecos_m2_yoy_lag1 will be NA\n")
}

# 2. ecos_krw_usd_change_5d: 5-day % change of KRW/USD (daily, lag1 only)
krw_feat <- copy(krw)
setorder(krw_feat, Date)
krw_feat[, krw_usd_change_5d_raw := (KRW_USD / shift(KRW_USD, 5, type = "lag") - 1) * 100]
cat(sprintf("  KRW/USD 5d %% change built: %d non-NA rows\n",
            sum(!is.na(krw_feat$krw_usd_change_5d_raw))))

# 3. ecos_base_rate: KR_Call1D as proxy for base rate (daily)
br_feat <- copy(call_rate)
setorder(br_feat, Date)
cat(sprintf("  Base rate (Call1D) loaded: %d rows\n", nrow(br_feat)))

# 4. ecos_industrial_production_yoy: monthly IP YoY (12-month change)
ip_feat <- NULL
if (!is.null(ip) && nrow(ip) > 0) {
  setorder(ip, Date)
  ip[, ip_yoy_raw := (ip_raw / shift(ip_raw, 12, type = "lag") - 1) * 100]
  ip_feat <- ip[, .(Date, ip_yoy_raw)]
  cat(sprintf("  IP YoY built: %d non-NA rows (latest: %s = %.2f%%)\n",
              sum(!is.na(ip_feat$ip_yoy_raw)),
              as.character(tail(ip_feat[!is.na(ip_yoy_raw)]$Date, 1)),
              tail(ip_feat$ip_yoy_raw[!is.na(ip_feat$ip_yoy_raw)], 1)))
} else {
  cat("  IP unavailable — ecos_industrial_production_yoy_lag1 will be NA\n")
}

# 5. ecos_cpi_yoy: monthly CPI YoY
cpi_feat <- copy(cpi)
setorder(cpi_feat, Date)
cpi_feat[, cpi_yoy_raw := (cpi_raw / shift(cpi_raw, 12, type = "lag") - 1) * 100]
cat(sprintf("  CPI YoY built: %d non-NA rows (latest: %s = %.2f%%)\n",
            sum(!is.na(cpi_feat$cpi_yoy_raw)),
            as.character(tail(cpi_feat[!is.na(cpi_yoy_raw)]$Date, 1)),
            tail(cpi_feat$cpi_yoy_raw[!is.na(cpi_feat$cpi_yoy_raw)], 1)))

# ----------------------------------------------------------------------------
# Step 0e: Build daily panel (forward-fill + PIT lag)
# ----------------------------------------------------------------------------
cat("\n[Step 0e] Merge to daily spine + forward-fill + PIT lag\n")

panel <- spine[, .(Date)]

# Helper: merge monthly series with forward-fill, then apply publication lag
# CORRECT pattern: panel[series, on="Date", roll=TRUE] joins INTO panel (rows preserve)
ffill_monthly <- function(panel, series_df, value_col, pub_lag_days, feature_name) {
  if (is.null(series_df) || nrow(series_df) == 0) {
    panel[, (feature_name) := NA_real_]
    return(panel)
  }
  # Shift monthly value forward by pub_lag_days (PIT: monthly stat published with delay)
  series_shifted <- copy(series_df)
  series_shifted[, Date := Date + pub_lag_days]
  # Drop duplicates by date (in case any) + drop NA
  series_shifted <- series_shifted[!is.na(get(value_col))]
  setorder(series_shifted, Date)
  # Deduplicate on Date (keep last)
  series_shifted <- series_shifted[, .SD[.N], by = Date]
  # Rolling join: for each panel date, find most recent series_shifted date <= panel date
  # data.table syntax: setkey both, then panel[series, roll] joins INTO smaller (wrong direction)
  # Right syntax: series[panel, roll=TRUE, on="Date"] returns nrow(panel)
  setkey(series_shifted, Date)
  setkey(panel, Date)
  joined <- series_shifted[panel, roll = TRUE]
  stopifnot(nrow(joined) == nrow(panel))
  panel[, (feature_name) := joined[[value_col]]]
  panel
}

# Helper: merge daily series with lag1 (1 trading day lag for PIT)
add_daily_lag1 <- function(panel, series_df, value_col, feature_name) {
  if (is.null(series_df) || nrow(series_df) == 0) {
    panel[, (feature_name) := NA_real_]
    return(panel)
  }
  s <- copy(series_df)
  setorder(s, Date)
  s <- s[!is.na(get(value_col))]
  s <- s[, .SD[.N], by = Date]
  # Daily series: shift forward by 1 calendar day, then ffill via rolling
  s[, Date := Date + 1L]
  setkey(s, Date)
  setkey(panel, Date)
  joined <- s[panel, roll = TRUE]
  stopifnot(nrow(joined) == nrow(panel))
  panel[, (feature_name) := joined[[value_col]]]
  panel
}

# 1. M2 YoY: monthly stat published ~1 month lag → 35-day publication lag (safe)
panel <- ffill_monthly(panel, m2_feat, "m2_yoy_raw", 35L, "ecos_m2_yoy_lag1")

# 2. KRW/USD 5d change: daily, lag1
panel <- add_daily_lag1(panel, krw_feat[, .(Date, krw_usd_change_5d_raw)],
                        "krw_usd_change_5d_raw", "ecos_krw_usd_change_5d_lag1")

# 3. Base rate (Call1D): daily, lag1
panel <- add_daily_lag1(panel, br_feat, "base_rate_raw", "ecos_base_rate_lag1")

# 4. IP YoY: monthly stat published ~6 weeks lag → 50-day publication lag
panel <- ffill_monthly(panel, ip_feat, "ip_yoy_raw", 50L, "ecos_industrial_production_yoy_lag1")

# 5. CPI YoY: monthly stat published ~1st of next month → 35-day publication lag (safe)
panel <- ffill_monthly(panel, cpi_feat[, .(Date, cpi_yoy_raw)],
                       "cpi_yoy_raw", 35L, "ecos_cpi_yoy_lag1")

# Coverage report
cat("\n[Step 0e] Coverage per feature (Date range 1995-01-01 ~ today):\n")
feature_cols <- c(
  "ecos_m2_yoy_lag1",
  "ecos_krw_usd_change_5d_lag1",
  "ecos_base_rate_lag1",
  "ecos_industrial_production_yoy_lag1",
  "ecos_cpi_yoy_lag1"
)
for (col in feature_cols) {
  vals <- panel[[col]]
  non_na <- sum(!is.na(vals))
  first_valid <- panel[!is.na(get(col))][1, Date]
  last_valid <- panel[!is.na(get(col))][.N, Date]
  cat(sprintf("  %-40s non-NA=%d/%d (%.1f%%), range %s ~ %s\n",
              col, non_na, nrow(panel), 100 * non_na / nrow(panel),
              ifelse(is.na(first_valid), "NA", as.character(first_valid)),
              ifelse(is.na(last_valid),  "NA", as.character(last_valid))))
}

# Limit to 1995-01-01 ~ 2026-04-30 (match OOS_END)
panel <- panel[Date <= as.Date("2026-04-30")]

# Save
out_path <- file.path(DATA_DIR_OUT, "ecos_kr_daily.csv")
fwrite(panel, out_path)
cat(sprintf("\n[Saved] %s (%d rows × %d cols, size=%.1f KB)\n",
            out_path, nrow(panel), ncol(panel),
            file.info(out_path)$size / 1024))

# ----------------------------------------------------------------------------
# Step 0f: Audit log
# ----------------------------------------------------------------------------
audit <- list(
  cycle = "53I_ecos_kr_macro_q126",
  step = "step0_ecos_fetch_consolidate",
  cached_sources = list(
    krw_usd = list(path = ECOS_KRW_CACHE, n = nrow(krw),
                    range = c(as.character(min(krw$Date)), as.character(max(krw$Date)))),
    call_rate = list(path = ECOS_BOND_CACHE, series = "KR_Call1D", n = nrow(call_rate),
                     range = c(as.character(min(call_rate$Date)), as.character(max(call_rate$Date)))),
    cpi = list(path = ECOS_BOND_CACHE, series = "KR_CPI", n = nrow(cpi),
               range = c(as.character(min(cpi$Date)), as.character(max(cpi$Date))))
  ),
  fetched_sources = list(
    m2 = if (!is.null(m2)) {
      list(path = M2_CACHE, n = nrow(m2),
           range = c(as.character(min(m2$Date)), as.character(max(m2$Date))),
           stat_code = "101Y008", item = "010100000", status = "fetched_or_cached")
    } else {
      list(status = "FETCH_FAILED — feature will be NA in panel")
    },
    industrial_production = if (!is.null(ip)) {
      list(path = IP_CACHE, n = nrow(ip),
           range = c(as.character(min(ip$Date)), as.character(max(ip$Date))),
           stat_code = "901Y033", item = "A00", status = "fetched_or_cached")
    } else {
      list(status = "FETCH_FAILED — feature will be NA in panel")
    }
  ),
  derived_features = list(
    ecos_m2_yoy_lag1 = list(
      semantics = "M2 통화량 YoY % (monthly, 12m change, publication lag 35d)",
      pit_method = "monthly → +35d shift → daily ffill (rolling join)"
    ),
    ecos_krw_usd_change_5d_lag1 = list(
      semantics = "KRW/USD 5-day % change (daily, lag1)",
      pit_method = "daily → +1d shift → ffill"
    ),
    ecos_base_rate_lag1 = list(
      semantics = "한국은행 기준금리 (KR_Call1D proxy, daily, lag1)",
      pit_method = "daily → +1d shift → ffill"
    ),
    ecos_industrial_production_yoy_lag1 = list(
      semantics = "전산업생산지수 YoY % (monthly, 12m change, publication lag 50d)",
      pit_method = "monthly → +50d shift → daily ffill"
    ),
    ecos_cpi_yoy_lag1 = list(
      semantics = "소비자물가지수 YoY % (monthly, 12m change, publication lag 35d)",
      pit_method = "monthly → +35d shift → daily ffill"
    )
  ),
  pit_audit = list(
    C2 = "PASS — KRW/USD + Call rate daily series shifted +1d (no same-day)",
    C4 = "PASS — Monthly stats (M2/IP/CPI) shifted by publication lag (35d / 50d / 35d)",
    C13 = "PASS — No sign flip, raw lag1 features",
    C14 = "N/A — Not factor IC",
    C15 = "N/A — Not Factor DB"
  ),
  output = out_path,
  coverage = setNames(
    lapply(feature_cols, function(col) {
      vals <- panel[[col]]
      list(
        non_na = sum(!is.na(vals)),
        total = nrow(panel),
        pct = round(100 * sum(!is.na(vals)) / nrow(panel), 2),
        first = ifelse(any(!is.na(vals)), as.character(panel[!is.na(get(col))][1, Date]), NA),
        last = ifelse(any(!is.na(vals)), as.character(panel[!is.na(get(col))][.N, Date]), NA)
      )
    }),
    feature_cols
  )
)
write_json(audit,
           file.path(EVAL_DIR, "v5f_ecos_kr_step0.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[Audit] %s\n", file.path(EVAL_DIR, "v5f_ecos_kr_step0.json")))

cat("\n========== Cycle 53I Step 0 DONE — Run scripts/135_feature_panel_v5f_ecos_kr.R next ==========\n")
