## arm A basis 정정 — total SR vs active SR
## ★사전등록 §4 의 밴드 [0.30,0.70] 은 참조 "SR 0.493" 재현 여부를 재려던 것이고,
##   그 참조는 전략의 **total Sharpe** 다. 그런데 canonical_screen_bt 의 `net_sr` 은
##   `mean(active)/sd(active)*sqrt(12)` = **active SR(=IR)** 이다(계약 376행).
##   초판이 이 둘을 맞바꿔 읽어 NOT_REPRODUCED_LOW 를 낼 뻔했다 — basis 는 계약에서 읽는다.
## ⚠문턱은 이동하지 않는다. 밴드는 원래 total SR 축에 걸려던 것이고, 여기서 축을 바로잡을 뿐이다.
suppressPackageStartupMessages({library(data.table); library(xts); library(PerformanceAnalytics)})
OUT <- "stage_artifacts/fq233_probe0_20260813"
res <- readRDS(file.path(OUT, "armA_canonical_result.rds"))

pr <- as.data.table(res$period_returns)
cat("period_returns 컬럼:", paste(names(pr), collapse = ", "), "\n")
cat(sprintf("행 %d\n", nrow(pr)))
print(utils::head(pr, 3))

dcol <- intersect(c("Date","date","ym"), names(pr))[1]
pcol <- intersect(c("port_net","ret_net","portfolio_net","port_ret","ret"), names(pr))[1]
bcol <- intersect(c("bm_ret","BM_Ret","bench","benchmark"), names(pr))[1]
cat(sprintf("\n사용 컬럼: date=%s · port=%s · bench=%s\n", dcol, pcol, bcol))
stopifnot(!is.na(dcol), !is.na(pcol))

d  <- as.Date(pr[[dcol]])
px <- xts(as.numeric(pr[[pcol]]), order.by = d)
## ★PerformanceAnalytics 표준 함수만 (자체 합성 금지)
sr_total <- as.numeric(SharpeRatio.annualized(px, Rf = 0, scale = 12, geometric = FALSE))
cagr     <- as.numeric(Return.annualized(px, scale = 12, geometric = TRUE))
mdd      <- as.numeric(maxDrawdown(px))
calmar   <- if (is.finite(mdd) && mdd > 0) cagr / mdd else NA_real_

cat("\n=== basis 별 결과 ===\n")
cat(sprintf("  total net SR  (참조 0.493 과 같은 축) : %+.4f\n", sr_total))
cat(sprintf("  active SR(=IR) (계약 net_sr)          : %+.4f\n", as.numeric(res$net_sr)))
cat(sprintf("  CAGR %.2f%% · MDD %.2f%% · Calmar %.3f · n=%d개월\n",
            100*cagr, 100*mdd, calmar, nrow(pr)))
if (!is.na(bcol)) {
  bxx <- xts(as.numeric(pr[[bcol]]), order.by = d)
  cat(sprintf("  [참고] 벤치 total SR %+.4f · 벤치 CAGR %.2f%%\n",
              as.numeric(SharpeRatio.annualized(bxx, Rf = 0, scale = 12, geometric = FALSE)),
              100*as.numeric(Return.annualized(bxx, scale = 12, geometric = TRUE))))
}

verdict <- if (!is.finite(sr_total)) "MEASUREMENT_FAILED" else
           if (sr_total >= 0.30 && sr_total <= 0.70) "REPRODUCED" else
           if (sr_total < 0.30) "NOT_REPRODUCED_LOW" else "NOT_REPRODUCED_HIGH_CHECK_LEAKAGE"
cat(sprintf("\n★사전등록 §4 판정 (total SR 축): %+.4f vs [0.30, 0.70] → **%s**\n", sr_total, verdict))

saveRDS(list(sr_total = sr_total, active_sr = as.numeric(res$net_sr), cagr = cagr,
             mdd = mdd, calmar = calmar, n_months = nrow(pr), verdict = verdict),
        file.path(OUT, "armA_basis.rds"))
cat("\n저장: armA_basis.rds\n")
