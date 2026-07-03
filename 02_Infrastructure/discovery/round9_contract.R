# Round 9 계약-grade — default earnings 시리즈를 contract build_benchmark_compare 경유
#   authoritative PORT_t(NW3) / IR / alpha. round9_capital_gate.py의 hand-NW3와 대조.
suppressMessages(library(data.table))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
ser <- fread(file.path(ROOT,".cache/discovery/round9_default_series.csv"))
ser[, date := as.Date(paste0(ym,"-01"))]
setorder(ser, date)

eval_window <- function(s, tag){
  prt <- s[, .(date, ret_net, frequency="monthly")]
  bmt <- s[, .(date, benchmark_ret, benchmark_id="KOSPI200_total_return")]
  bc <- build_benchmark_compare(prt, bmt, run_id=paste0("r9_",tag),
                                strategy_id="earnings_3m_broad_liq", annualization_factor=12)
  g <- function(nm){ v <- bc[metric_name==nm, active_value]; if(length(v)==0) NA_real_ else as.numeric(v[1]) }
  cat(sprintf("[%-8s] n=%3d  PORT_t(NW3)=%+.2f  p=%.3f  IR=%+.2f  alpha_ann=%+.1f%%\n",
              tag, nrow(s), g("Portfolio_Alpha_t_NW_lag3"), g("Portfolio_Alpha_t_pvalue"),
              g("Information_Ratio"), 100*g("Alpha_Annualized")))
}
cat("=== Round 9 계약-grade PORT_t (contract build_benchmark_compare, NW lag-3) ===\n")
cat(sprintf("입력: round9_default_series.csv (broad/H3/top25/EW/liq), n=%d, %s~%s\n",
            nrow(ser), ser$ym[1], ser$ym[nrow(ser)]))
eval_window(ser,                  "full")
eval_window(ser[ym>="2021-01"],   "recent")
eval_window(ser[ym>="2010-01" & ym<="2015-12"], "2010-15")
eval_window(ser[ym>="2016-01" & ym<="2020-12"], "2016-20")
eval_window(ser[ym>="2021-01" & ym<="2023-12"], "21-23")
eval_window(ser[ym>="2024-01"],   "24-26")
cat("=== done — hand-NW3(round9_results.txt)와 대조: 계약값이 authoritative ===\n")
