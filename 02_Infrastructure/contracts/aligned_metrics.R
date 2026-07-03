# aligned_metrics.R — 패널↔지표 정합 (2026-07-02 도훈 mandate)
# 배경: 이 생성부의 build_bt_result가 freq/benchmark 미제공으로 예외 → 06/07 지표 미갱신.
#   본 헬퍼가 return_ym(진짜 수익월) 정렬 + KOSPI200(IKS200)으로 07_benchmark_compare를 재산출해
#   패널↔지표를 매 생성 시 정합 유지. (build_bt_result 전역 수정은 별개 infra 과제.)
suppressMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})

write_aligned_metrics <- function(panel_dt, out_dir, run_id, strategy_id,
                                  ret_col = "ret_L5_faith", kospi_path = NULL) {
  panel_dt <- as.data.table(panel_dt)
  if (is.null(kospi_path)) kospi_path <- file.path(Sys.getenv("QM_ROOT","."), ".cache/indices.parquet")
  if (!file.exists(kospi_path) || !("return_ym" %in% names(panel_dt)) || !(ret_col %in% names(panel_dt))) {
    warning("[aligned_metrics] 전제 부족 — 스킵"); return(invisible(FALSE))
  }
  idx <- as.data.table(read_parquet(kospi_path)); idx[, ym := format(as.Date(Date),"%Y-%m")]
  k <- idx[, .(c = data.table::last(kospi200)), by = ym][order(ym)]; k[, kr := c/shift(c) - 1]
  m <- merge(panel_dt[, .(return_ym, br = get(ret_col))], k[, .(return_ym = ym, kr)], by = "return_ym")[order(return_ym)]
  m <- m[is.finite(br) & is.finite(kr)]; if (nrow(m) < 24) { warning("[aligned_metrics] 표본부족"); return(invisible(FALSE)) }
  br <- m$br; kr <- m$kr; act <- br - kr; n <- nrow(m); dts <- as.Date(paste0(m$return_ym, "-01"))
  ps <- m$return_ym[1]; pe <- m$return_ym[n]
  sr_b <- as.numeric(SharpeRatio.annualized(xts(br,dts), Rf=0))
  tot_b <- prod(1+br)-1; tot_k <- prod(1+kr)-1
  beta <- cov(br,kr)/var(kr); alpha <- (mean(br)-beta*mean(kr))*12
  te <- sd(act)*sqrt(12); ir <- mean(act)/sd(act)*sqrt(12); corr <- cor(br,kr)
  fit <- lm(act ~ 1)
  se_nw <- tryCatch(sqrt(sandwich::NeweyWest(fit, lag=3, prewhite=FALSE)[1,1]), error=function(e) sd(act)/sqrt(n))
  tnw <- as.numeric(coef(fit)[1]/se_nw)
  up <- mean(br[kr>0])/mean(kr[kr>0]); dn <- mean(br[kr<0])/mean(kr[kr<0]); hit <- mean(act>0)
  bc <- data.table(run_id=run_id, strategy_id=strategy_id, benchmark_id="KOSPI200_price",
    period_start=ps, period_end=pe, frequency="monthly",
    metric_name=c("Excess_Total_Return","Active_Return_Mean","Tracking_Error","Information_Ratio",
                  "Beta_to_Benchmark","Alpha_Annualized","Portfolio_Alpha_t_NW_lag3","Correlation",
                  "Up_Capture","Down_Capture","Hit_Ratio_vs_BM"),
    strategy_value=c(tot_b, mean(br), NA, NA, beta, alpha, tnw, corr, up, dn, hit),
    benchmark_value=c(tot_k, mean(kr), NA, NA, 1, 0, 0, 1, 1, 1, 0.5),
    active_value=c(tot_b-tot_k, mean(act), te, ir, beta-1, alpha, tnw, corr-1, NA, NA, hit-0.5),
    metric_unit="ratio", observation_count=n)
  fwrite(bc, file.path(out_dir, "07_benchmark_compare.csv"))
  cat(sprintf("[aligned_metrics] 07 정합 재작성: %d월 SR %.2f β %.3f IR %.3f α %.1f%% t_NW %.2f (KOSPI200 return_ym)\n",
              n, sr_b, beta, ir, alpha*100, tnw))
  invisible(TRUE)
}
