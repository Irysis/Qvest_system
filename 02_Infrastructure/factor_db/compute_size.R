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

  # --- S02: Float_Size = -log(estimated_shares × Close) ---
  # 유통주식 정보가 별도로 없으면 Size와 동일 프록시 사용
  # estimated_shares = Size / Close → Float_Size ≈ -log(Size)
  # FUND에 SharesOutstanding 있으면 그걸 사용
  if (!is.null(FUND) && nrow(FUND) > 0) {
    # FUND is pre-filtered (FUND_pit) by builder — avoid copy+filter overhead
    fund <- FUND  # already Factor_Date <= sig_d from builder

    shares_data <- NULL
    if ("Item" %in% names(fund)) {
      shares_sub <- fund[Item == "SharesOutstanding"]
      if (nrow(shares_sub) > 0) {
        setorder(shares_sub, Ticker, Factor_Date)
        shares_data <- shares_sub[, .SD[.N], by = Ticker][, .(Ticker, Shares = Value)]
      }
    } else if ("SharesOutstanding" %in% names(fund)) {
      if ("Factor_Date" %in% names(fund)) {
        setorder(fund, Ticker, Factor_Date)
        shares_data <- fund[!is.na(SharesOutstanding), .SD[.N], by = Ticker][, .(Ticker, Shares = SharesOutstanding)]
      } else {
        shares_data <- fund[!is.na(SharesOutstanding), .(Ticker, Shares = SharesOutstanding)]
      }
    }

    if (!is.null(shares_data) && nrow(shares_data) > 0) {
      merged <- merge(latest[, .(Ticker, Close)], shares_data, by = "Ticker")
      merged <- merged[Shares > 0 & Close > 0]
      if (nrow(merged) > 0) {
        s02 <- merged[, .(Ticker, Factor_Name = "S02_Float_Size",
                          Raw_Value = -log(Shares * Close))]
        s02 <- s02[is.finite(Raw_Value)]
        if (nrow(s02) > 0) results[["S02"]] <- s02
      }
    }
  }

  # S02 fallback: use Size as proxy
  if (!"S02" %in% names(results)) {
    s02 <- latest[, .(Ticker, Factor_Name = "S02_Float_Size",
                       Raw_Value = -log(Size))]
    s02 <- s02[is.finite(Raw_Value)]
    if (nrow(s02) > 0) results[["S02"]] <- s02
  }

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)
  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_size.R loaded (S01~S02)\n")
