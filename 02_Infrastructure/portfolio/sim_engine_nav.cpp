// sim_engine_nav.cpp — Rcpp daily NAV 이중 루프 최적화
// PIT C9: DD/VT lag 동일 원칙 — 이 함수는 이미 정리된 holdings에만 적용
// run_monthly_simulation() line 784~798 이중 R loop 교체용
//
// 참조 R 정본:
//   run_monthly_simulation()  backtest_harness.R L784~798
//
// Compile: Rcpp::sourceCpp("02_Infrastructure/portfolio/sim_engine_nav.cpp")
//
// 주요 로직:
//   1. rawdata_subset (Ticker, Date_int, Close) → unordered_map 변환
//   2. dates 루프: holdings 합산 (가격 없으면 last_price fallback)
//   3. DataFrame(Date_int, NAV) 반환 (R에서 as.Date() 변환)

#include <Rcpp.h>
#include <unordered_map>
#include <map>
#include <string>
#include <vector>
using namespace Rcpp;

// ─────────────────────────────────────────────────────────────────────────────
// cpp_daily_nav — Daily NAV 계산 (이중 루프 Rcpp 대체)
//
// @param rawdata_subset  DataFrame: Ticker(char), Date_int(int), Close(dbl)
//                        관련 종목 + 기간만 사전 필터 후 전달
// @param tickers         CharacterVector: 보유 종목 코드 (holdings 순서)
// @param shares          NumericVector:   종목별 보유 주식수 (tickers 동일 순서)
// @param last_prices     NumericVector:   종목별 마지막 알려진 가격 (fallback)
// @param dates           IntegerVector:   계산할 날짜들 (int, days since 1970-01-01)
// @param cash            double:          현금 잔액
//
// @return DataFrame: Date_int(int), NAV(dbl)
//         R에서 result$Date <- as.Date(result$Date_int, origin = "1970-01-01")
// ─────────────────────────────────────────────────────────────────────────────
// [[Rcpp::export]]
Rcpp::DataFrame cpp_daily_nav(
    Rcpp::DataFrame rawdata_subset,
    Rcpp::CharacterVector tickers,
    Rcpp::NumericVector shares,
    Rcpp::NumericVector last_prices,
    Rcpp::IntegerVector dates,
    double cash
) {
  int n_tickers = tickers.size();
  int n_dates   = dates.size();

  // ── 1. rawdata_subset → ticker_map: Ticker → (Date_int → Close) ──────────
  // NA Close는 삽입하지 않아 fallback 경로를 타도록 처리
  CharacterVector rd_ticker  = rawdata_subset["Ticker"];
  IntegerVector   rd_date    = rawdata_subset["Date_int"];
  NumericVector   rd_close   = rawdata_subset["Close"];
  int n_rows = rd_ticker.size();

  // outer map: ticker string → inner map: date_int → close
  std::unordered_map<std::string, std::map<int, double>> ticker_map;
  ticker_map.reserve(n_tickers * 2);

  for (int i = 0; i < n_rows; i++) {
    // NA Close 건너뜀 (fallback 처리를 R과 동일하게)
    if (NumericVector::is_na(rd_close[i])) continue;
    std::string tk = Rcpp::as<std::string>(rd_ticker[i]);
    ticker_map[tk][rd_date[i]] = rd_close[i];
  }

  // ── 2. last_prices map 구성 (ticker string → last_price) ─────────────────
  std::unordered_map<std::string, double> last_price_map;
  last_price_map.reserve(n_tickers);
  for (int k = 0; k < n_tickers; k++) {
    last_price_map[Rcpp::as<std::string>(tickers[k])] = last_prices[k];
  }

  // ── 3. shares map 구성 (ticker string → shares) ───────────────────────────
  std::unordered_map<std::string, double> shares_map;
  shares_map.reserve(n_tickers);
  for (int k = 0; k < n_tickers; k++) {
    shares_map[Rcpp::as<std::string>(tickers[k])] = shares[k];
  }

  // ── 4. dates 루프 → NAV 계산 ─────────────────────────────────────────────
  IntegerVector out_dates(n_dates);
  NumericVector out_nav(n_dates);

  for (int di = 0; di < n_dates; di++) {
    int d = dates[di];
    double daily_val = cash;

    for (int k = 0; k < n_tickers; k++) {
      std::string tk = Rcpp::as<std::string>(tickers[k]);
      double sh = shares_map[tk];

      // ticker_map 조회
      auto it_tk = ticker_map.find(tk);
      if (it_tk != ticker_map.end()) {
        auto it_dt = it_tk->second.find(d);
        if (it_dt != it_tk->second.end()) {
          // 가격 존재 → 정상 경로
          daily_val += sh * it_dt->second;
        } else {
          // 해당 날짜 가격 없음 → last_price fallback
          daily_val += sh * last_price_map[tk];
        }
      } else {
        // ticker 자체가 rawdata에 없음 → last_price fallback
        daily_val += sh * last_price_map[tk];
      }
    }

    out_dates[di] = d;
    out_nav[di]   = daily_val;
  }

  return Rcpp::DataFrame::create(
    Rcpp::Named("Date_int") = out_dates,
    Rcpp::Named("NAV")      = out_nav
  );
}
