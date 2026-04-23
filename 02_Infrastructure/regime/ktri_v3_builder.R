#==============================================================================
# KTRI v3 Signal Builder (Market Breadth 기반, v2.0 — 2026-04-24)
#
# Purpose: 원본 KTRI_v3_reinforced.R 소실 → market breadth + volatility 기반 재구축.
#
# Input:
#   .cache/RAWDATA.parquet — 전 종목 daily OHLCV (Date, Ticker, Close, Ret, Market)
#   .cache/benchmark.parquet — KOSPI (BM_Close, BM_Ret) fallback IKS200
#
# Output schema (tg_regime_briefing 호환):
#   DATE        날짜
#   KTRI        0~100 breadth + trend composite
#   VEA         0~100 volatility/exposure score
#   IKS200      KOSPI close (briefing fwd20 계산용)
#   Delta_KTRI  5-day change (briefing direction)
#   Action_v3   zone label (Strong Add / Neutral / Defensive Bias / Strong Hedge 등)
#
# KTRI Composite:
#   - 40% above_MA200_pct  — 200일 MA 초과 종목 비율 (breadth 핵심)
#   - 25% adv_dec_ratio    — 상승/하락 종목 비율
#   - 15% kospi_trend_z    — KOSPI 252d trend z-score
#   - 20% pct_positive_20d — 20일 연속 양수 수익률 종목 비율
#
# VEA:
#   - 70% kospi_vol20_z    — KOSPI 20d volatility z (높을수록 stressful)
#   - 30% dispersion_z     — cross-sectional volatility dispersion
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
}
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")

KTRI_V3_OUT_DIR <- file.path(PROJECT_ROOT, "04_Research/regime_comparison/output")
KTRI_V3_CSV <- file.path(KTRI_V3_OUT_DIR, "ktri_v3_signals.csv")

.z_to_score <- function(z) pmax(0, pmin(100, 50 + 12.5 * z))

.rolling_z <- function(x, w = 252L) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < w) next
    win <- x[(i - w + 1L):i]
    m <- mean(win, na.rm = TRUE)
    s <- sd(win, na.rm = TRUE)
    out[i] <- if (is.finite(s) && s > 0) (x[i] - m) / s else 0
  }
  out
}

.zone_v3 <- function(ktri, vea) {
  # bins: KTRI <40, 40-60, >60 / VEA <60, 60-70, >70 → 9 zones
  k_bin <- if (is.na(ktri)) NA_character_
           else if (ktri < 40) "K_Low"
           else if (ktri < 60) "K_Mid" else "K_High"
  v_bin <- if (is.na(vea)) NA_character_
           else if (vea < 60) "V_Low"
           else if (vea < 70) "V_Mid" else "V_High"
  if (is.na(k_bin) || is.na(v_bin)) return("Unknown")
  zone <- switch(paste(k_bin, v_bin, sep = "_"),
    K_High_V_Low = "Strong Add",
    K_High_V_Mid = "Add (Scaled)",
    K_High_V_High = "Trend Up / Vol Risk",
    K_Mid_V_Low = "Neutral+",
    K_Mid_V_Mid = "Neutral",
    K_Mid_V_High = "Neutral-Defensive",
    K_Low_V_Low = "Weakness Easing",
    K_Low_V_Mid = "Defensive Bias",
    K_Low_V_High = "Strong Hedge",
    "Unknown")
  zone
}

#─── Core: KOSPI breadth 계산 ─────────────────────────────────
.compute_breadth <- function(dt) {
  # Input: long-format rawdata (Date, Ticker, Close, Ret)
  # Output: Date-level breadth metrics
  setorder(dt, Ticker, Date)

  # 종목별 MA200 + MA50 계산
  dt[, MA200 := frollmean(Close, 200L, na.rm = TRUE), by = Ticker]
  dt[, above_MA200 := as.integer(Close > MA200)]

  # 일별 집계
  daily <- dt[!is.na(Close), .(
    n_total         = .N,
    n_above_MA200   = sum(above_MA200, na.rm = TRUE),
    n_advance       = sum(Ret > 0, na.rm = TRUE),
    n_decline       = sum(Ret < 0, na.rm = TRUE),
    mean_ret        = mean(Ret, na.rm = TRUE),
    sd_ret          = sd(Ret, na.rm = TRUE)
  ), by = Date]

  daily[, above_MA200_pct := n_above_MA200 / pmax(1, n_total)]
  daily[, adv_dec_ratio := n_advance / pmax(1, n_advance + n_decline)]

  # Rolling 20d positive return %
  setorder(daily, Date)
  daily[, pos20_pct := frollmean(as.numeric(mean_ret > 0), 20L, na.rm = TRUE)]

  # Cross-sectional dispersion z
  daily[, disp_z := .rolling_z(sd_ret, w = 252L)]

  daily
}

#─── Build KTRI v3 ────────────────────────────────────────────
build_ktri_v3 <- function(output = KTRI_V3_CSV, cache_cutoff_years = 15L) {
  # Load RAWDATA (15년만 — speed)
  rawdata_path <- file.path(CACHE_DIR, "RAWDATA.parquet")
  if (!file.exists(rawdata_path)) {
    rawdata_path <- file.path(CACHE_DIR, "rawdata.parquet")
  }
  if (!file.exists(rawdata_path)) {
    stop("[ktri_v3] RAWDATA cache not found")
  }

  cat(sprintf("[ktri_v3] Loading RAWDATA (cutoff: last %d years)...\n", cache_cutoff_years))
  raw <- as.data.table(read_parquet(rawdata_path))
  raw[, Date := as.Date(Date)]

  # KOSPI 종목만 + 최근 15년
  cutoff <- Sys.Date() - (cache_cutoff_years * 365L + 60L)
  kospi <- raw[Market == "KOSPI" & Date >= cutoff & !is.na(Close),
               .(Date, Ticker, Close, Ret)]
  cat(sprintf("[ktri_v3] KOSPI subset: %d rows, %d tickers, %s ~ %s\n",
              nrow(kospi), uniqueN(kospi$Ticker),
              min(kospi$Date), max(kospi$Date)))

  # Breadth 계산
  cat("[ktri_v3] Computing breadth...\n")
  daily <- .compute_breadth(kospi)

  # KOSPI index (benchmark.parquet)
  bench <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bench[, Date := as.Date(Date)]
  setnames(bench, "BM_Close", "IKS200")

  daily <- merge(daily, bench[, .(Date, IKS200)], by = "Date", all.x = TRUE)
  setorder(daily, Date)

  # KOSPI trend z + vol20 z
  daily[, kospi_trend_z := .rolling_z(IKS200, w = 252L)]
  daily[, kospi_ret := IKS200 / shift(IKS200, 1L) - 1]
  daily[, vol20 := frollapply(kospi_ret, 20L, sd, align = "right")]
  daily[, vol20_z := .rolling_z(vol20, w = 252L)]

  # KTRI composite (0~100)
  daily[, KTRI := 100 * (
    0.40 * above_MA200_pct +
    0.25 * adv_dec_ratio +
    0.15 * pmax(0, pmin(1, 0.5 + kospi_trend_z / 4)) +
    0.20 * ifelse(is.na(pos20_pct), 0.5, pos20_pct)
  )]

  # VEA composite
  daily[, VEA := 0.7 * .z_to_score(vol20_z) + 0.3 * .z_to_score(disp_z)]

  # Bounds
  daily[, KTRI := pmax(0, pmin(100, KTRI))]
  daily[, VEA := pmax(0, pmin(100, VEA))]

  # Delta_KTRI (5-day change) + Action_v3 (zone label)
  daily[, Delta_KTRI := KTRI - shift(KTRI, 5L)]
  daily[, Action_v3 := mapply(.zone_v3, KTRI, VEA)]

  # Output (briefing 호환 schema)
  out <- daily[!is.na(KTRI) & !is.na(IKS200),
               .(DATE = Date, KTRI, VEA, IKS200, Delta_KTRI, Action_v3)]

  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  fwrite(out, output)

  cat(sprintf("[ktri_v3] built: %d rows | %s ~ %s\n",
              nrow(out), min(out$DATE), max(out$DATE)))
  cat(sprintf("[ktri_v3] latest: KTRI=%.2f, VEA=%.2f, Δ5d=%+.2f, zone=%s\n",
              out[.N, KTRI], out[.N, VEA],
              out[.N, Delta_KTRI], out[.N, Action_v3]))
  cat(sprintf("[ktri_v3] saved: %s\n", output))

  invisible(out)
}

build_ktri_v3_safe <- function() {
  tryCatch(build_ktri_v3(),
           error = function(e) {
             cat(sprintf("[ktri_v3] build failed: %s\n", e$message))
             invisible(NULL)
           })
}

cat("[ktri_v3_builder.R v2.0 market-breadth] Loaded. Functions:\n")
cat("  build_ktri_v3(output, cache_cutoff_years=15)\n")
cat("  build_ktri_v3_safe()\n")
