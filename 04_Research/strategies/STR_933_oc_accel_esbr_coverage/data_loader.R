## STR_933 data_loader.R
## 역할: parquet 일괄 로드 전담. run_all.R에서 source()로 호출.
## 결과: inv_preloaded, esbr_monthly, coverage_monthly, macro_regime_dt 전역 등록
## PIT: C2 - 모든 rolling 계산은 sig_date 기준 snapshot (t-1 보장)
##       C15 - load_month_factors() 경유로 Factor DB 접근

cat("[data_loader] Loading all parquet sources once...\n")

# OPT-1: parquet 호출 전담 — run_all.R 내 parquet 로드 없음

# ── 1. Investor wide (OtherCorp 전용) ─────────────────────────────────────────
inv_raw <- as.data.table(load_investor(fmt = "wide"))
inv_raw[, Date := as.Date(Date)]
setorder(inv_raw, Ticker, Date)

FLOW_WINDOW_DL <- 40L   # 단기 윈도우 (OC_accel 계산용)
FLOW_LONG_DL   <- 80L   # 장기 윈도우

# OC_40d: 40일 누적 기타법인 순매수
inv_raw[, oc_40d   := frollsum(OtherCorp, n = FLOW_WINDOW_DL, align = "right", na.rm = TRUE), by = Ticker]
# OC_80d: 80일 누적 기타법인 순매수 (장기 기준)
inv_raw[, oc_80d   := frollsum(OtherCorp, n = FLOW_LONG_DL,   align = "right", na.rm = TRUE), by = Ticker]
# active day count (최소 활동 종목 필터용)
inv_raw[, oc_nz    := as.numeric(abs(OtherCorp) > 0)]
inv_raw[, oc_active := frollsum(oc_nz, n = FLOW_WINDOW_DL, align = "right", na.rm = TRUE), by = Ticker]
inv_raw[, c("oc_nz") := NULL]
setkey(inv_raw, Date, Ticker)
assign("inv_preloaded", inv_raw, envir = .GlobalEnv)
cat(sprintf("  inv_preloaded: %d rows | %s ~ %s\n",
  nrow(inv_raw), as.character(min(inv_raw$Date)), as.character(max(inv_raw$Date))))

# ── 2. ESBR consensus (C04_ESBR) ──────────────────────────────────────────────
# C14: Usable_Date <= sig_date 보장 — YM snapshot 방식
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

# ── 3. Coverage expansion (C08_Coverage via Factor DB) ─────────────────────────
# C15: load_month_factors() 경유 필수
# C08_Coverage = 애널리스트 커버리지 수 (raw count)
# Coverage expansion = 1개월 차분 (증가 종목 선호)
# 전체 가용 월 리스트에서 C08_Coverage 로드 → 월간 차분 계산
cat("[data_loader] Loading C08_Coverage from Factor DB...\n")
source(file.path(INFRA_DIR, "factor_db", "factor_db_connector.R"))

# 가용 factor_db parquet 월 목록 탐색
fdb_dir  <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$")
if (length(fdb_files) == 0L) {
  cat("  [WARNING] factor_db parquet 없음 → Coverage 팩터 생략\n")
  assign("coverage_monthly", data.table(YM=character(0), Ticker=character(0), cov_exp=numeric(0)), envir=.GlobalEnv)
} else {
  fdb_yms  <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", fdb_files)
  fdb_yms  <- sort(fdb_yms)

  # 각 월에서 C08_Coverage 추출 (load_month_factors 경유 — C15 준수)
  cov_list <- lapply(fdb_yms, function(ym) {
    sig_d <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
    tryCatch({
      fdb_snap <- load_month_factors(sig_d, coverage_min=0.05)
      fdb_snap <- fdb_snap[Factor_Name == "C08_Coverage", .(Ticker, Z_Score_Aligned)]
      if (nrow(fdb_snap) == 0L) return(NULL)
      fdb_snap[, YM := format(sig_d, "%Y-%m")]
      fdb_snap
    }, error=function(e) NULL)
  })
  cov_list <- cov_list[!sapply(cov_list, is.null)]

  if (length(cov_list) == 0L) {
    cat("  [WARNING] C08_Coverage 데이터 없음 → Coverage 팩터 생략\n")
    assign("coverage_monthly", data.table(YM=character(0), Ticker=character(0), cov_exp=numeric(0)), envir=.GlobalEnv)
  } else {
    cov_dt <- rbindlist(cov_list)
    setorder(cov_dt, Ticker, YM)
    # Coverage expansion: 1개월 차분 (t 대비 t-1 증가량)
    # PIT: 이미 load_month_factors가 sig_date 기준 → 추가 lag 불필요
    cov_dt[, cov_lag1 := shift(Z_Score_Aligned, n=1L, type="lag"), by=Ticker]
    cov_dt[, cov_exp  := Z_Score_Aligned - cov_lag1]
    cov_m <- cov_dt[!is.na(cov_exp), .(YM, Ticker, cov_exp)]
    setkey(cov_m, YM, Ticker)
    assign("coverage_monthly", cov_m, envir = .GlobalEnv)
    cat(sprintf("  coverage_monthly: %d rows | %d tickers | %d months\n",
      nrow(cov_m), uniqueN(cov_m$Ticker), uniqueN(cov_m$YM)))
  }
}

# ── 4. Macro regime ──────────────────────────────────────────────────────────
macro_dt <- load_macro_regime(max_age_days = 30L)
macro_dt[, YM := substr(Date, 1, 7)]
setkey(macro_dt, YM)
assign("macro_regime_dt", macro_dt, envir = .GlobalEnv)
cat(sprintf("  macro_regime_dt: %d rows\n", nrow(macro_dt)))

cat("[data_loader] Done.\n")
