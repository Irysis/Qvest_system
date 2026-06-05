#==============================================================================
# A6_bbva_macro_builder.R — BBVA Global Macro 4-channel signal
#
# Plan v1.0 alt data based bearish forecast — Sprint 2
#
# 학술 anchor:
#   BBVA Research 2026 (KR-016) — "Geopolitics, Geoeconomics, and Sovereign Risk:
#   Different Shocks, Different Channels"
#   arXiv: 2510.12416 (KR-016 paper_catalog)
#
# 4-Channel Framework:
#   1. Markets channel — VIX + Copper + Init_Claims (실시간 risk)
#   2. Sovereign channel — BBB_Spread + HY_Spread (신용 risk)
#   3. Transmission channel — T10Y2Y + KRW_USD + DGS10 (US→KR 전이)
#   4. News channel — stretch (A2 별도 cycle)
#
# Output: outputs/01_data/A6_bbva_macro.parquet
#   cols: Date, bbva_market_z, bbva_sovereign_z, bbva_transmission_z, bbva_macro_composite
#
# PIT 의무: 모든 z-score expanding window (C1), lag1 (decision_time = next_open)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(zoo)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS_DIR <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
OUT_DIR <- file.path(WS_DIR, "outputs/01_data")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

# Source PIT loader
source(file.path(WS_DIR, "scripts/00_pit_manifest_loader.R"))

# ── Rolling z-score (expanding, min 252) ─────────────────────
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

# ── Main: BBVA 4-channel build ──────────────────────────────
build_a6_bbva_macro <- function() {
  cat("[A6 BBVA] Building Global Macro 4-channel signal...\n")

  # Load fred_macro_wide (1990-01~ FRED 확장 inherit from v0.4.2)
  fred_path <- file.path(CACHE_DIR, "fred_macro_wide.parquet")
  if (!file.exists(fred_path)) stop("[A6] fred_macro_wide.parquet missing")

  fred <- as.data.table(read_parquet(fred_path))
  fred[, Date := as.Date(Date)]
  setorder(fred, Date)

  cat(sprintf("[A6] fred_macro_wide loaded: %d rows / %s ~ %s\n",
              nrow(fred), as.character(min(fred$Date)), as.character(max(fred$Date))))

  # Forward-fill monthly/weekly series for daily processing (BBVA framework needs daily granularity)
  for (col in c("Copper_Price", "Init_Claims", "BBB_Spread", "HY_Spread",
                "Fed_Funds_Rate", "Bank_Lending_Std", "Housing_Permits",
                "UMich_Sentiment", "US_M2", "US_CPI", "US_IndProd", "US_Unemployment")) {
    if (col %in% names(fred)) {
      fred[, (col) := zoo::na.locf(get(col), na.rm = FALSE)]
    }
  }

  # ── Channel 1: Markets ───────────────────────────────────
  # VIX (실시간 risk) + Copper (글로벌 cyclical) + Init_Claims (US labor)
  fred[, vix_d := c(NA, diff(VIX))]
  fred[, copper_d := c(NA, diff(log(pmax(Copper_Price, 1e-3))))]
  fred[, claims_d := c(NA, diff(Init_Claims))]

  fred[, vix_d_z := rolling_zscore_expanding(vix_d)]
  fred[, copper_d_z := rolling_zscore_expanding(copper_d)]
  fred[, claims_d_z := rolling_zscore_expanding(claims_d)]

  # Markets composite = (vix_z + copper_z(negative direction) + claims_z) / 3
  # Bearish direction: VIX up, Copper down, Claims up
  fred[, bbva_market_z := (vix_d_z - copper_d_z + claims_d_z) / 3]

  # ── Channel 2: Sovereign ─────────────────────────────────
  # BBB_Spread + HY_Spread (신용 risk premium)
  # 단 BBB/HY Spread = 2023~ 시작 (FRED 1990 확장 후에도 한계)
  fred[, bbb_d := c(NA, diff(BBB_Spread))]
  fred[, hy_d := c(NA, diff(HY_Spread))]
  fred[, bbb_d_z := rolling_zscore_expanding(bbb_d)]
  fred[, hy_d_z := rolling_zscore_expanding(hy_d)]
  fred[, bbva_sovereign_z := (bbb_d_z + hy_d_z) / 2]

  # ── Channel 3: Transmission ──────────────────────────────
  # T10Y2Y inversion + KRW_USD stress + DGS10 (US 장기금리)
  fred[, term_d := c(NA, diff(Term_Spread))]
  fred[, krw_d := c(NA, diff(log(KRW_USD)))]
  fred[, dgs10_d := c(NA, diff(US_10Y_Yield))]

  fred[, term_d_z := rolling_zscore_expanding(term_d)]
  fred[, krw_d_z := rolling_zscore_expanding(krw_d)]
  fred[, dgs10_d_z := rolling_zscore_expanding(dgs10_d)]

  # Bearish: term spread narrow (-), KRW depreciate (+), DGS10 spike (+)
  fred[, bbva_transmission_z := (-term_d_z + krw_d_z + dgs10_d_z) / 3]

  # Markets composite recompute with row-wise na.rm (available channels mean)
  fred[, bbva_market_z := rowMeans(cbind(vix_d_z, -copper_d_z, claims_d_z), na.rm = TRUE)]
  fred[, bbva_market_z := ifelse(is.nan(bbva_market_z), NA_real_, bbva_market_z)]

  fred[, bbva_sovereign_z := rowMeans(cbind(bbb_d_z, hy_d_z), na.rm = TRUE)]
  fred[, bbva_sovereign_z := ifelse(is.nan(bbva_sovereign_z), NA_real_, bbva_sovereign_z)]

  fred[, bbva_transmission_z := rowMeans(cbind(-term_d_z, krw_d_z, dgs10_d_z), na.rm = TRUE)]
  fred[, bbva_transmission_z := ifelse(is.nan(bbva_transmission_z), NA_real_, bbva_transmission_z)]

  # ── Composite (4-channel average, equal-weight, row-wise na.rm) ─
  fred[, bbva_macro_composite := rowMeans(
    cbind(bbva_market_z, bbva_sovereign_z, bbva_transmission_z), na.rm = TRUE)]
  fred[, bbva_macro_composite := ifelse(is.nan(bbva_macro_composite), NA_real_, bbva_macro_composite)]

  # ── PIT lag1 (decision_time = next_open) ────────────────
  fred[, bbva_market_z_lag1 := lag1(bbva_market_z)]
  fred[, bbva_sovereign_z_lag1 := lag1(bbva_sovereign_z)]
  fred[, bbva_transmission_z_lag1 := lag1(bbva_transmission_z)]
  fred[, bbva_macro_composite_lag1 := lag1(bbva_macro_composite)]

  result <- fred[, .(Date,
                     bbva_market_z = bbva_market_z_lag1,
                     bbva_sovereign_z = bbva_sovereign_z_lag1,
                     bbva_transmission_z = bbva_transmission_z_lag1,
                     bbva_macro_composite = bbva_macro_composite_lag1)]

  out_path <- file.path(OUT_DIR, "A6_bbva_macro.parquet")
  write_parquet(result, out_path)

  cat(sprintf("[A6 BBVA] DONE: %d rows / %s ~ %s\n",
              nrow(result), as.character(min(result$Date)), as.character(max(result$Date))))
  cat(sprintf("  bbva_market_z non-NA: %d\n", sum(!is.na(result$bbva_market_z))))
  cat(sprintf("  bbva_sovereign_z non-NA: %d (BBB/HY 2023~ 한계)\n",
              sum(!is.na(result$bbva_sovereign_z))))
  cat(sprintf("  bbva_transmission_z non-NA: %d\n", sum(!is.na(result$bbva_transmission_z))))
  cat(sprintf("  bbva_macro_composite non-NA: %d\n", sum(!is.na(result$bbva_macro_composite))))
  cat(sprintf("  Output: %s\n", out_path))

  invisible(result)
}

if (!interactive() && identical(sys.nframe(), 0L)) {
  build_a6_bbva_macro()
}
