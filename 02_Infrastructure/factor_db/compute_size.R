#==============================================================================
# compute_size.R — Size Factor 계산 모듈 (S01~S02)
#
# 함수: compute_size(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
# 반환: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT 준수: Date <= sig_date (당일 가격 사용 가능)
# 방향: 소형주 프리미엄 → -log(MarketCap)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

compute_size <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sig_d <- as.Date(sig_date)
  results <- list()

  # --- 가격 데이터 준비 (PIT: Date <= sig_date) ---
  # RAWDATA is pre-sliced (Date <= sig_d) and setkey(Date, Ticker) by builder.
  # No need for copy+filter — just use the maximum date available.
  rd <- RAWDATA  # already filtered & keyed

  if (nrow(rd) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # sig_date 당일 또는 가장 최근 거래일 데이터
  # setorder + .SD[.N] is faster than which.max(Date) per group
  max_date_rd <- max(rd$Date, na.rm = TRUE)
  latest <- rd[Date == max_date_rd]

  # 필수 컬럼: Close, Size
  if (!all(c("Close", "Size") %in% names(latest))) {
    warning("[compute_size] Missing required columns: Close, Size")
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # Size = Market Cap (RAWDATA의 Size 컬럼은 시가총액)
  # estimated_shares = Size / Close
  latest <- latest[!is.na(Close) & !is.na(Size) & Close > 0 & Size > 0]

  if (nrow(latest) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # --- S01: Size = -log(Market Cap) ---
  # Size 컬럼이 이미 시가총액이면 직접 사용
  # Size = Close × Shares → MarketCap = Size
  s01 <- latest[, .(Ticker, Factor_Name = "S01_Size",
                     Raw_Value = -log(Size))]
  s01 <- s01[is.finite(Raw_Value)]
  if (nrow(s01) > 0) results[["S01"]] <- s01

  # --- S02: Float_Size = -log(시가총액 × 유동주식비율) — (2026-11-16 재정의) 구판은 재무 FUND 의 SharesOutstanding(= 시가총액 ÷ 종가로
  #   만든 합성값)을 써서 사실상 -log(Size) = S01 과 같았다. 이제 RAWDATA 의 퀀티 유동주식비율(Float · % · 그날 값)로 유동 시가총액을 쓴다.
  #   Float 이 없는 종목은 -log(Size)(구판과 같은 대체).
  if ("Float" %in% names(latest)) {
    s02 <- latest[, .(Ticker, Factor_Name = "S02_Float_Size",
                      Raw_Value = fifelse(is.finite(Float) & Float > 0, -log(Size * Float / 100), -log(Size)))]
  } else {
    s02 <- latest[, .(Ticker, Factor_Name = "S02_Float_Size", Raw_Value = -log(Size))]
  }
  s02 <- s02[is.finite(Raw_Value)]
  if (nrow(s02) > 0) results[["S02"]] <- s02

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_size.R loaded (S01~S02)\n")
