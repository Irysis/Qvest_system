#==============================================================================
# A5_options_higher_moments.R — KRX options implied skew + kurtosis
#
# Plan v1.0 alt data based bearish forecast — Sprint 3
#
# 학술 anchor:
#   Bates 2008 JF — "The Market for Crash Risk"
#   Conrad-Dittmar-Ghysels 2013 RFS — "Ex Ante Skewness and Expected Stock Returns"
#
# Method:
#   ATM = 권리행사가가 spot 근처 (±5% strike)
#   OTM put = strike < spot * 0.95
#   OTM call = strike > spot * 1.05
#   implied skew (proxy) = OTM_put_IV - OTM_call_IV (positive = crash skew)
#   implied kurt (proxy) = (OTM_put_IV + OTM_call_IV) / 2 - ATM_IV
#                          (positive = tail thickness > normal)
#
# Source: .cache/krx_options/{YYYYMMDD}.parquet (4023 daily, 2010-01-04~)
#   cols: BAS_DD / ISU_NM / RGHT_TP_NM (CALL/PUT) / IMP_VOLT / ACC_OPNINT_QTY
#
# ISU_NM format: "코스피200 2601 C 280.0 (정규)"
#   → expiry YYYYMM (2601), type (C/P), strike (280.0)
#
# Output: outputs/01_data/A5_options_higher_moments.parquet
#   cols: Date, k200_implied_skew_z, k200_implied_kurt_z
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
OUT_DIR <- file.path(WS_DIR, "outputs/01_data")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

source(file.path(WS_DIR, "scripts/00_pit_manifest_loader.R"))

# Rolling z-score
rolling_zscore_expanding <- function(x, min_obs = 252) {
  n <- length(x)
  z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    vals <- x[1:i]; vals <- vals[!is.na(vals)]
    if (length(vals) < min_obs) next
    mu <- mean(vals); sg <- sd(vals)
    if (is.na(sg) || sg < 1e-10) next
    z[i] <- (x[i] - mu) / sg
  }
  z
}
lag1 <- function(x) c(NA, head(x, -1))

# Parse ISU_NM → strike only (type은 RGHT_TP_NM 별도 컬럼)
# ISU_NM 패턴: "미니코스피 C 202001 212.5 (정규)" / "코스피200 ..." 등
# strike = "(정규)" 직전 숫자
parse_strike <- function(isu_nm) {
  m <- regmatches(isu_nm, regexpr("[0-9]+\\.?[0-9]*(?= ?\\(정규)", isu_nm, perl = TRUE))
  if (length(m) == 0) return(NA_real_)
  as.numeric(m)
}

build_a5_options_higher_moments <- function() {
  cat("[A5 Options] Building implied skew + kurtosis from krx_options/...\n")

  opt_dir <- file.path(CACHE_DIR, "krx_options")
  opt_files <- list.files(opt_dir, pattern = "^[0-9]{8}\\.parquet$", full.names = TRUE)
  if (length(opt_files) == 0) stop("[A5] krx_options/ empty")

  cat(sprintf("[A5] Reading %d option files...\n", length(opt_files)))

  # Need K200 spot per day for ATM/OTM classification
  bm <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
  bm[, Date := as.Date(Date)]
  spot_map <- bm[, .(Date, spot = BM_Close)]

  daily_list <- vector("list", length(opt_files))
  pb_n <- length(opt_files)
  for (i in seq_along(opt_files)) {
    if (i %% 500 == 0) cat(sprintf("  Progress %d / %d\n", i, pb_n))
    dt <- tryCatch(as.data.table(read_parquet(opt_files[i])), error = function(e) NULL)
    if (is.null(dt) || nrow(dt) == 0) next
    needed <- c("BAS_DD", "ISU_NM", "RGHT_TP_NM", "IMP_VOLT", "ACC_OPNINT_QTY")
    dt <- dt[, intersect(needed, names(dt)), with = FALSE]
    if (nrow(dt) == 0) next

    dt[, Date := as.Date(BAS_DD, "%Y%m%d")]
    dt[, IMP_VOLT := suppressWarnings(as.numeric(IMP_VOLT))]
    dt[, ACC_OPNINT_QTY := suppressWarnings(as.numeric(ACC_OPNINT_QTY))]
    dt <- dt[!is.na(IMP_VOLT) & IMP_VOLT > 0]
    if (nrow(dt) == 0) next

    # Parse strike (type은 RGHT_TP_NM 별도 컬럼)
    dt[, strike := sapply(ISU_NM, parse_strike)]
    dt[, opt_type := trimws(RGHT_TP_NM)]
    dt <- dt[!is.na(strike) & strike > 0]
    if (nrow(dt) == 0) next

    # Join spot
    this_date <- dt$Date[1]
    sp <- spot_map[Date == this_date]$spot[1]
    if (is.na(sp)) {
      # Find nearest spot
      sp <- spot_map[Date <= this_date][order(-Date)][1]$spot
      if (is.na(sp)) next
    }
    # Strike 단위 정합 fix (2026-05-19):
    #   KRX 옵션 strike는 KOSPI200/10 단위 (예: 212.5 = K200 2125 수준)
    #   benchmark.parquet BM_Close는 KOSPI 종합지수 (~2176) → strike × 10 으로 단위 맞춤
    dt[, moneyness := (strike * 10) / sp]

    # ATM: 0.95~1.05 / OTM put: 0.85~0.95 / OTM call: 1.05~1.15 (liberal range)
    dt[, region := fcase(
      moneyness >= 0.97 & moneyness <= 1.03, "ATM",
      moneyness >= 0.85 & moneyness <  0.97 & opt_type == "PUT",  "OTM_PUT",
      moneyness >  1.03 & moneyness <= 1.15 & opt_type == "CALL", "OTM_CALL",
      default = "OTHER"
    )]

    # OI-weighted IV per region
    region_iv <- dt[region != "OTHER",
                    .(iv_w = sum(IMP_VOLT * ACC_OPNINT_QTY, na.rm = TRUE) /
                              sum(ACC_OPNINT_QTY, na.rm = TRUE)),
                    by = region]

    # Build daily aggregate
    atm <- region_iv[region == "ATM"]$iv_w
    otm_put <- region_iv[region == "OTM_PUT"]$iv_w
    otm_call <- region_iv[region == "OTM_CALL"]$iv_w

    if (length(atm) == 0) atm <- NA_real_
    if (length(otm_put) == 0) otm_put <- NA_real_
    if (length(otm_call) == 0) otm_call <- NA_real_

    daily_list[[i]] <- data.table(
      Date = this_date,
      atm_iv = atm,
      otm_put_iv = otm_put,
      otm_call_iv = otm_call
    )
  }
  daily <- rbindlist(daily_list[!sapply(daily_list, is.null)], fill = TRUE)
  setorder(daily, Date)

  cat(sprintf("[A5] Daily aggregate: %d rows\n", nrow(daily)))

  # implied skew (Bates 2008 proxy) + implied kurt
  daily[, implied_skew := otm_put_iv - otm_call_iv]
  daily[, implied_kurt := (otm_put_iv + otm_call_iv) / 2 - atm_iv]

  # Expanding z-score + lag1
  daily[, k200_implied_skew_z_raw := rolling_zscore_expanding(implied_skew)]
  daily[, k200_implied_kurt_z_raw := rolling_zscore_expanding(implied_kurt)]
  daily[, k200_implied_skew_z := lag1(k200_implied_skew_z_raw)]
  daily[, k200_implied_kurt_z := lag1(k200_implied_kurt_z_raw)]

  # Join to benchmark dates (left join)
  result <- merge(spot_map[, .(Date)], daily[, .(Date, k200_implied_skew_z, k200_implied_kurt_z)],
                  by = "Date", all.x = TRUE)
  setorder(result, Date)

  out_path <- file.path(OUT_DIR, "A5_options_higher_moments.parquet")
  write_parquet(result, out_path)

  cat(sprintf("[A5 Options] DONE: %d rows\n", nrow(result)))
  cat(sprintf("  k200_implied_skew_z non-NA: %d / first non-NA: %s\n",
              sum(!is.na(result$k200_implied_skew_z)),
              as.character(min(result$Date[!is.na(result$k200_implied_skew_z)]))))
  cat(sprintf("  k200_implied_kurt_z non-NA: %d\n",
              sum(!is.na(result$k200_implied_kurt_z))))
  cat(sprintf("  Output: %s\n", out_path))

  invisible(result)
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  build_a5_options_higher_moments()
}
