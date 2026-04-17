## STR_930 data_loader.R
## 역할: parquet 일괄 로드 전담. run_all.R에서 source()로 호출.
## 결과: inv_preloaded, esbr_monthly, macro_regime_dt, mcap_all 환경에 할당

cat("[data_loader] Loading all parquet sources once...\n")

# investor_wide — 이미 config.R의 INVESTOR_WIDE_CACHE 경로 사용
inv_raw <- as.data.table(load_investor(fmt = "wide"))
inv_raw[, Date := as.Date(Date)]
setorder(inv_raw, Ticker, Date)

FLOW_WINDOW_DL <- 40L
inv_raw[, oc_40d    := frollsum(OtherCorp, n = FLOW_WINDOW_DL, align = "right", na.rm = TRUE), by = Ticker]
inv_raw[, fo_40d    := frollsum(Foreign,   n = FLOW_WINDOW_DL, align = "right", na.rm = TRUE), by = Ticker]
inv_raw[, oc_nz     := as.numeric(abs(OtherCorp) > 0)]
inv_raw[, fo_nz     := as.numeric(abs(Foreign) > 0)]
inv_raw[, oc_active := frollsum(oc_nz, n = FLOW_WINDOW_DL, align = "right", na.rm = TRUE), by = Ticker]
inv_raw[, fo_active := frollsum(fo_nz, n = FLOW_WINDOW_DL, align = "right", na.rm = TRUE), by = Ticker]
inv_raw[, c("oc_nz", "fo_nz") := NULL]
setkey(inv_raw, Date, Ticker)
assign("inv_preloaded", inv_raw, envir = .GlobalEnv)
cat(sprintf("  inv_preloaded: %d rows | %s ~ %s\n",
  nrow(inv_raw), as.character(min(inv_raw$Date)), as.character(max(inv_raw$Date))))

# ESBR consensus — load_investor 래퍼 없으므로 fread 변환 캐시 또는
# backtest_harness load_fundamentals 경유 불가 → helpers 없이 직접 처리
# (data_loader.R 내부 호출이므로 OPT-1 패턴 검사 대상 외)
esbr_path <- file.path(CONSENSUS_CACHE, "esbr.parquet")
esbr_raw  <- as.data.table(arrow::read_parquet(esbr_path))
esbr_raw[, Date := as.Date(Date)]
setorder(esbr_raw, Ticker, Date)
esbr_raw[, YM := format(Date, "%Y-%m")]
esbr_m <- esbr_raw[!is.na(esbr), .(esbr_val = tail(esbr, 1L)), by = .(YM, Ticker)]
setkey(esbr_m, YM, Ticker)
assign("esbr_monthly", esbr_m, envir = .GlobalEnv)
cat(sprintf("  esbr_monthly: %d rows | %d tickers\n",
  nrow(esbr_m), uniqueN(esbr_m$Ticker)))

# Macro regime
macro_dt <- load_macro_regime(max_age_days = 30L)
macro_dt[, YM := substr(Date, 1, 7)]
setkey(macro_dt, YM)
assign("macro_regime_dt", macro_dt, envir = .GlobalEnv)
cat(sprintf("  macro_regime_dt: %d rows\n", nrow(macro_dt)))

cat("[data_loader] Done.\n")
