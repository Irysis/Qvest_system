suppressPackageStartupMessages(library(data.table))
L5 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
L5[, e := as.numeric(m4_weight_lag)*as.numeric(beta_threshold_lag)*as.numeric(beta_R05_V5)]
L5[, ratio := as.numeric(ret_L5_V5)/as.numeric(ret_orig)]
X <- L5[abs(as.numeric(ret_orig)) > 0.01 & is.finite(ratio)]
cat(sprintf("[expo] n=%d cor(e, ratio)=%.4f | |e-ratio| mean=%.4f p95=%.4f max=%.4f\n",
  nrow(X), X[, cor(e, ratio)], X[, mean(abs(e-ratio))], X[, quantile(abs(e-ratio),.95)], X[, max(abs(e-ratio))]))
X[, resid := ratio - e]
cat(sprintf("[expo] resid vs db_R05_V5/ret_orig cor=%.3f (오버레이 스위칭 비용 항 설명 여부)\n",
  X[, cor(resid, as.numeric(db_R05_V5)/as.numeric(ret_orig))]))
bad <- X[abs(e-ratio) > 0.05][, .(return_ym, ret_orig, ret_L5_V5, e, ratio)]
cat(sprintf("[expo] |e-ratio|>0.05 rows: %d\n", nrow(bad))); if(nrow(bad)>0) print(head(bad,5))
