#==============================================================================
# valuation_calculator.R — 밸류에이션 팩터 계산기
#
# RAWDATA(Close, Size) + DART(재무제표) + Consensus(EPS/BPS/DPS) → 밸류에이션 지표
#
# 산출 지표:
#   Forward:  fPER, fPBR, fDY (컨센서스 기반, 일별)
#   Trailing: tPER, tPBR, PSR, PCR, EV_EBITDA (DART 기반, 연간 lag)
#
# Usage:
#   source("02_Infrastructure/valuation_calculator.R")
#   val <- build_valuation()                  # 전체 빌드 + 캐시
#   val <- load_valuation()                   # 캐시 로드
#   val <- load_valuation(start_date="2020-01-01")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

VALUATION_CACHE <- file.path(CACHE_DIR, "valuation.parquet")

#==============================================================================
# build_valuation() — Forward + Trailing 밸류에이션 산출 → parquet 캐시
#==============================================================================
build_valuation <- function(
    rawdata = NULL,
    dart = NULL,
    consensus_dir = CONSENSUS_CACHE,
    output_path = VALUATION_CACHE
) {
  cat("[valuation] Building valuation factors...\n")
  t0 <- Sys.time()

  # ── 1. RAWDATA 로드 (Close, Size = MarketCap) ──
  if (is.null(rawdata)) {
    rawdata <- as.data.table(read_parquet(RAWDATA_CACHE))
    rawdata[, Date := as.Date(Date)]
  }
  price <- rawdata[, .(Date, Ticker, Close, Size)]
  price <- price[!is.na(Close) & Close > 0 & !is.na(Size) & Size > 0]
  # Size는 이미 KRW(원) 단위 시가총액 (DART 재무제표와 동일 단위)
  price[, MCap := Size]
  cat(sprintf("  Price: %s rows | %d tickers\n",
              format(nrow(price), big.mark = ","), uniqueN(price$Ticker)))

  # ── 2. Forward 밸류에이션 (Consensus: 일별, 주당 기준) ──
  cat("  [Forward] Loading consensus...\n")
  fwd <- price[, .(Date, Ticker, Close)]

  # EPS_1Y → Forward PER
  eps_pq <- file.path(consensus_dir, "eps_1y.parquet")
  if (file.exists(eps_pq)) {
    eps <- as.data.table(read_parquet(eps_pq))
    eps[, Date := as.Date(Date)]
    fwd <- merge(fwd, eps[, .(Date, Ticker, eps_1y)], by = c("Date", "Ticker"), all.x = TRUE)
    fwd[, fPER := fifelse(eps_1y > 0, Close / eps_1y, NA_real_)]
    cat(sprintf("    EPS_1Y matched: %s rows\n",
                format(sum(!is.na(fwd$fPER)), big.mark = ",")))
  }

  # BPS_1Y → Forward PBR
  bps_pq <- file.path(consensus_dir, "bps_1y.parquet")
  if (file.exists(bps_pq)) {
    bps <- as.data.table(read_parquet(bps_pq))
    bps[, Date := as.Date(Date)]
    fwd <- merge(fwd, bps[, .(Date, Ticker, bps_1y)], by = c("Date", "Ticker"), all.x = TRUE)
    fwd[, fPBR := fifelse(bps_1y > 0, Close / bps_1y, NA_real_)]
    cat(sprintf("    BPS_1Y matched: %s rows\n",
                format(sum(!is.na(fwd$fPBR)), big.mark = ",")))
  }

  # DPS_1Y → Forward Dividend Yield
  dps_pq <- file.path(consensus_dir, "dps_1y.parquet")
  if (file.exists(dps_pq)) {
    dps <- as.data.table(read_parquet(dps_pq))
    dps[, Date := as.Date(Date)]
    fwd <- merge(fwd, dps[, .(Date, Ticker, dps_1y)], by = c("Date", "Ticker"), all.x = TRUE)
    fwd[, fDY := fifelse(Close > 0 & !is.na(dps_1y), dps_1y / Close, NA_real_)]
    cat(sprintf("    DPS_1Y matched: %s rows\n",
                format(sum(!is.na(fwd$fDY)), big.mark = ",")))
  }

  # Forward 결과 정리
  fwd_cols <- intersect(c("Date", "Ticker", "fPER", "fPBR", "fDY"), names(fwd))
  fwd <- fwd[, ..fwd_cols]

  # ── 3. Trailing 밸류에이션 (DART: 연간, 45일+ lag) ──
  cat("  [Trailing] Loading DART financials...\n")
  if (is.null(dart)) {
    dart_pq <- file.path(CACHE_DIR, "fundamental_dart.parquet")
    if (file.exists(dart_pq)) {
      dart <- as.data.table(read_parquet(dart_pq))
    } else {
      cat("    DART cache not found — trailing ratios skipped.\n")
      dart <- NULL
    }
  }

  if (!is.null(dart) && nrow(dart) > 0) {
    # DART는 연도별, Factor_Date (= 공시일 + lag) 기준으로 매핑
    # Factor_Date가 없으면 bsns_year + 5개월 (5월 리밸런싱) 적용
    if (!"Factor_Date" %in% names(dart)) {
      dart[, Factor_Date := as.Date(sprintf("%d-05-01", bsns_year + 1))]
    }
    dart[, Factor_Date := as.Date(Factor_Date)]

    # 필요한 재무 항목만 추출
    dart_sub <- dart[, .(
      Ticker, Factor_Date, bsns_year,
      NetIncome, TotalEquity, Revenue, OperatingCF,
      EBITDA, TotalDebt, CashAndEquiv
    )]
    dart_sub <- dart_sub[!is.na(Factor_Date)]

    # 가장 최신 재무제표를 각 날짜에 rolling join
    setkey(dart_sub, Ticker, Factor_Date)
    setkey(price, Ticker, Date)

    # Rolling join: 각 (Ticker, Date)에 대해 Factor_Date <= Date인 가장 최근 재무제표 매핑
    trail <- dart_sub[price, roll = Inf, on = .(Ticker, Factor_Date = Date)]
    setnames(trail, "Factor_Date", "Date")

    # Trailing 지표 계산 (DART 재무: 원 단위)
    trail[, `:=`(
      tPER      = fifelse(NetIncome > 0, MCap / NetIncome, NA_real_),
      tPBR      = fifelse(TotalEquity > 0, MCap / TotalEquity, NA_real_),
      PSR       = fifelse(Revenue > 0, MCap / Revenue, NA_real_),
      PCR       = fifelse(OperatingCF > 0, MCap / OperatingCF, NA_real_),
      EV_EBITDA = fifelse(
        EBITDA > 0,
        (MCap + fcoalesce(TotalDebt, 0) - fcoalesce(CashAndEquiv, 0)) / EBITDA,
        NA_real_
      )
    )]

    trail_cols <- c("Date", "Ticker", "tPER", "tPBR", "PSR", "PCR", "EV_EBITDA")
    trail <- trail[, ..trail_cols]
    cat(sprintf("    Trailing PER: %s rows\n",
                format(sum(!is.na(trail$tPER)), big.mark = ",")))
    cat(sprintf("    Trailing PBR: %s rows\n",
                format(sum(!is.na(trail$tPBR)), big.mark = ",")))
    cat(sprintf("    EV/EBITDA: %s rows\n",
                format(sum(!is.na(trail$EV_EBITDA)), big.mark = ",")))
  } else {
    trail <- data.table(Date = as.Date(character()), Ticker = character())
  }

  # ── 4. 합체 (Forward + Trailing) ──
  cat("  Merging forward + trailing...\n")
  val <- merge(fwd, trail, by = c("Date", "Ticker"), all = TRUE)
  val <- val[!is.na(Date)]
  setkey(val, Date, Ticker)

  # Outlier cap (극단값 제거: 0.5th ~ 99.5th percentile by date)
  ratio_cols <- intersect(c("fPER", "fPBR", "fDY", "tPER", "tPBR", "PSR", "PCR", "EV_EBITDA"),
                          names(val))
  for (col in ratio_cols) {
    val[, (col) := {
      x <- get(col)
      q <- quantile(x, c(0.005, 0.995), na.rm = TRUE)
      fifelse(x < q[1] | x > q[2], NA_real_, x)
    }, by = Date]
  }

  # ── 5. 저장 ──
  write_parquet(val, output_path)
  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))

  cat(sprintf("\n[valuation] === 완료 (%d초) ===\n", elapsed))
  cat(sprintf("  기간: %s ~ %s\n", min(val$Date), max(val$Date)))
  cat(sprintf("  종목: %d\n", uniqueN(val$Ticker)))
  cat(sprintf("  총 행: %s\n", format(nrow(val), big.mark = ",")))
  cat(sprintf("  캐시: %s (%.1f MB)\n", basename(output_path),
              file.size(output_path) / 1024 / 1024))

  # 커버리지 요약
  cat("\n  [커버리지]\n")
  for (col in ratio_cols) {
    n <- sum(!is.na(val[[col]]))
    pct <- n / nrow(val) * 100
    cat(sprintf("    %-10s: %8s rows (%5.1f%%)\n", col,
                format(n, big.mark = ","), pct))
  }

  # 삼성전자 샘플
  cat("\n  [삼성전자 최근]\n")
  ss <- val[Ticker == "A005930"][order(-Date)][1:3]
  print(ss)

  invisible(val)
}

#==============================================================================
# load_valuation() — 캐시된 밸류에이션 로드 (backtest_harness 패턴)
#==============================================================================
load_valuation <- function(
    start_date = NULL,
    end_date = NULL,
    cache_path = VALUATION_CACHE
) {
  if (!file.exists(cache_path)) {
    cat("[valuation] Cache not found. Building...\n")
    return(build_valuation())
  }

  dt <- as.data.table(read_parquet(cache_path))
  dt[, Date := as.Date(Date)]

  if (!is.null(start_date)) dt <- dt[Date >= as.Date(start_date)]
  if (!is.null(end_date))   dt <- dt[Date <= as.Date(end_date)]

  cat(sprintf("[valuation] Loaded: %s rows | %d tickers | %s ~ %s\n",
              format(nrow(dt), big.mark = ","), uniqueN(dt$Ticker),
              min(dt$Date), max(dt$Date)))
  dt
}

cat("[valuation_calculator] Loaded.\n")
cat("[valuation_calculator] Functions: build_valuation(), load_valuation()\n")
