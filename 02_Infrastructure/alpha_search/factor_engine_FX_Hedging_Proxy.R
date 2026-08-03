# =============================================================================
# factor_engine_FX_Hedging_Proxy.R
# Strategy: FX Hedging Disclosure Score (Financial Proxy)
# Paper: AWARE-FX (arxiv 2607.27611) - Qi Wang (2026)
# KR Adaptation: DART 재무제표 파생상품 보유액 / 총자산 비율로 FX 헤징 공시 proxy
#
# 논문 원형: NLP로 사업보고서 텍스트의 strict FX hedging score 산출
#   "strict FX score is negatively associated with FX exposure"
#   high hedging score = 환율 관리 기업 = FX risk 낮음 → long
#
# KR 구현 제약:
#   - DART 사업보고서 텍스트 미구축 → 재무제표 파생상품 잔액으로 proxy
#   - 파생상품자산+부채 / 총자산 비율 = 헤징 활동 강도 측정
#   - metric_type = 'proxy' (텍스트 기반 NLP score 아님)
#
# PIT 규칙 (C4):
#   - 연간 재무제표: bsns_year=t → 사용 가능 시작일 = t+1년 3월 31일
#   - 각 월말 시그널 날짜에 pit_available_date <= Date인 최신 연도값 사용
#   - 동일시점 순환참조 없음, 전체표본 통계 없음
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 파생상품 proxy 데이터 로드 -------------------------------------------------
cat("[FX_Hedging_Proxy] Loading DART derivative data...\n")

suppressPackageStartupMessages(library(arrow))

QM_ROOT_PATH <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
.dart_path <- file.path(QM_ROOT_PATH, ".cache/dart/dart_raw_financials.parquet")

.dart_raw <- tryCatch(
  as.data.table(arrow::read_parquet(.dart_path)),
  error = function(e) {
    cat("[ERROR] dart_raw_financials load failed:", conditionMessage(e), "\n")
    NULL
  }
)

if (is.null(.dart_raw)) {
  cat("[WARN] DART data unavailable — FACTORS will be empty\n")
  FACTORS <- data.table(Date = as.Date(character(0)), Ticker = character(0), Score = numeric(0))
} else {
  cat("[FX_Hedging_Proxy] DART raw rows:", nrow(.dart_raw), "\n")

  # ---- 파생상품 자산+부채 추출 (재무상태표 BS) ----------------------------------
  .deriv_pattern <- "파생상품자산|파생상품부채|파생금융자산|파생금융부채|유동파생상품|단기파생상품|장기파생상품"
  .deriv_bs <- .dart_raw[
    sj_div == "BS" & grepl(.deriv_pattern, account_nm, ignore.case = FALSE)
  ]

  # 총자산 추출
  .total_assets <- .dart_raw[
    sj_div == "BS" &
      account_nm %in% c("자산총계", "총자산", "자산 합계", "합계(자산)", "Total assets")
  ]

  cat("[FX_Hedging_Proxy] Derivative BS rows:", nrow(.deriv_bs),
      "| Total assets rows:", nrow(.total_assets), "\n")

  # ---- 금액 숫자 변환 -----------------------------------------------------------
  .deriv_bs[, amt := as.numeric(gsub("[,[:space:]]", "", thstrm_amount))]
  .total_assets[, amt := as.numeric(gsub("[,[:space:]]", "", thstrm_amount))]

  # ---- 파생상품 총액 집계 (ticker × bsns_year) ----------------------------------
  .deriv_sum <- .deriv_bs[
    !is.na(amt),
    .(deriv_total = sum(abs(amt), na.rm = TRUE)),
    by = .(Ticker, bsns_year)
  ]

  .assets_sum <- .total_assets[
    !is.na(amt) & amt > 0,
    .(total_assets = max(abs(amt), na.rm = TRUE)),
    by = .(Ticker, bsns_year)
  ]

  cat("[FX_Hedging_Proxy] Deriv sum tickers:", uniqueN(.deriv_sum$Ticker),
      "| Asset sum tickers:", uniqueN(.assets_sum$Ticker), "\n")

  # ---- 헤징 강도 = 파생상품 / 총자산 -------------------------------------------
  .proxy_raw <- merge(.deriv_sum, .assets_sum, by = c("Ticker", "bsns_year"), all = FALSE)
  .proxy_raw[, hedging_ratio := deriv_total / total_assets]
  .proxy_raw <- .proxy_raw[is.finite(hedging_ratio) & hedging_ratio >= 0]

  cat("[FX_Hedging_Proxy] Proxy rows:", nrow(.proxy_raw),
      "| Tickers:", uniqueN(.proxy_raw$Ticker), "\n")
  cat("[FX_Hedging_Proxy] Year range:",
      min(.proxy_raw$bsns_year), "-", max(.proxy_raw$bsns_year), "\n")

  # ---- PIT 날짜: bsns_year+1의 3월 31일 (C4 준수) ----------------------------
  .proxy_raw[, pit_date := as.Date(paste0(bsns_year + 1L, "-03-31"))]

  # ---- 월말 시그널 날짜 추출 ---------------------------------------------------
  RAWDATA[, .ym := format(Date, "%Y-%m")]
  .month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym][, Date]

  # ---- 각 (Ticker, 월말) 에서 PIT-safe 최신 연도값 조인 ----------------------
  # 방법: proxy 테이블에서 pit_date <= 해당 월말인 행만 유지 → 최신 연도 선택
  # data.table rolling join: 월말 Date >= pit_date 방향으로 최신값

  # Signal universe: 월말 × LiqPass 통과 종목
  .signals <- RAWDATA[
    Date %in% .month_ends & LiqPass == TRUE,
    .(Date, Ticker)
  ]

  # proxy를 Ticker, pit_date 기준으로 정렬
  .proxy_sorted <- .proxy_raw[order(Ticker, pit_date), .(Ticker, pit_date, hedging_ratio)]
  setkey(.proxy_sorted, Ticker, pit_date)
  setkey(.signals, Ticker, Date)

  # Rolling join: .signals$Date >= .proxy_sorted$pit_date → 가장 최근 pit_date 값
  .joined <- .proxy_sorted[.signals,
    roll = TRUE,          # last observation carried forward (Date >= pit_date)
    on = .(Ticker = Ticker, pit_date = Date)
  ]
  # 결과: Date가 .signals의 Date, hedging_ratio가 그 시점에 PIT-safe한 최신값

  FACTORS <- .joined[
    !is.na(hedging_ratio) & is.finite(hedging_ratio),
    .(Date, Ticker, Score = hedging_ratio)
  ]

  cat("[FX_Hedging_Proxy] FACTORS rows:", nrow(FACTORS),
      "| signal dates:", uniqueN(FACTORS$Date),
      "| tickers:", uniqueN(FACTORS$Ticker), "\n")
  cat("[FX_Hedging_Proxy] Date range:",
      as.character(min(FACTORS$Date, na.rm = TRUE)), "to",
      as.character(max(FACTORS$Date, na.rm = TRUE)), "\n")

  # Coverage 통계
  .cov <- FACTORS[, .(n = .N), by = Date]
  cat("[FX_Hedging_Proxy] Avg tickers/month:", round(mean(.cov$n), 1),
      "| Min:", min(.cov$n), "| Max:", max(.cov$n), "\n")

  if (mean(.cov$n) < 20) {
    cat("[FX_Hedging_Proxy][WARN] Coverage thin (<20 tickers/month average) — proxy 한계\n")
  }

  # 정리
  RAWDATA[, .ym := NULL]
  rm(.dart_raw, .deriv_bs, .total_assets, .deriv_sum, .assets_sum,
     .proxy_raw, .proxy_sorted, .signals, .joined, .cov, .month_ends,
     .deriv_pattern, QM_ROOT_PATH, .dart_path)
}

cat("[FX_Hedging_Proxy] factor_engine complete. FACTORS:", nrow(FACTORS), "rows\n")
