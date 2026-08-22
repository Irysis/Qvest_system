## IC→PORT 전이 벽 국소화 — Spearman(순위) 우위가 raw-return 우위로 전이되는가
## 가설: 분포-표적은 '전형 구간 순서'를 개선하나 포트 수익을 지배하는 '극단 실현'을 놓친다.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
frd <- as.data.table(S$frd)
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x); m <- mean(x); e <- x - m
  s <- sum(e^2)/n; for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }
arms <- list(armA = S$panels$armA[, .(Date, Ticker, sc = as.numeric(score))],
             armB = S$panels$armB[, .(Date, Ticker, sc = as.numeric(q50))],
             armC = S$panels$armC[, .(Date, Ticker, sc = as.numeric(score))])
out <- list()
for (nm in names(arms)) {
  X <- merge(as.data.table(arms[[nm]]), frd[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  X <- X[is.finite(sc) & is.finite(Ret_1m)]
  ## 월별: Spearman(순위) vs Pearson(raw) vs Pearson(윈저 1%)
  st <- X[, {
    w <- Ret_1m; q <- quantile(w, c(.01,.99), na.rm=TRUE); wz <- pmin(pmax(w, q[1]), q[2])
    .(sp = cor(sc, Ret_1m, method="spearman"),
      pe = cor(sc, Ret_1m, method="pearson"),
      pw = cor(sc, wz, method="pearson"))}, by = Date][is.finite(sp)]
  ## 분위 스프레드: 상위 10% 평균수익 − 하위 10% (raw), 그리고 중앙값 스프레드
  ds <- X[, {
    r <- frank(-sc, ties.method="first"); n <- .N; k <- max(1L, floor(n*0.1))
    hi <- Ret_1m[r <= k]; lo <- Ret_1m[r > n-k]
    .(mean_spread = mean(hi) - mean(lo), median_spread = median(hi) - median(lo))}, by = Date]
  out[[nm]] <- list(
    spearman_ic = mean(st$sp), spearman_t_nw3 = nw_t(st$sp),
    pearson_ic  = mean(st$pe), pearson_t_nw3  = nw_t(st$pe),
    pearson_winsor1_ic = mean(st$pw), pearson_winsor1_t_nw3 = nw_t(st$pw),
    d10_mean_spread_monthly = mean(ds$mean_spread), d10_mean_spread_t = nw_t(ds$mean_spread),
    d10_median_spread_monthly = mean(ds$median_spread), d10_median_spread_t = nw_t(ds$median_spread),
    n_months = nrow(st))
}
cat("=== 전이 벽 국소화 (n=198) ===\n")
cat(sprintf("%-5s | %-22s | %-22s | %-22s\n", "arm", "Spearman IC (t)", "Pearson IC (t)", "Pearson w1% IC (t)"))
for (nm in names(out)) { o <- out[[nm]]
  cat(sprintf("%-5s | %+.5f (%+6.3f)      | %+.5f (%+6.3f)      | %+.5f (%+6.3f)\n",
      nm, o$spearman_ic, o$spearman_t_nw3, o$pearson_ic, o$pearson_t_nw3,
      o$pearson_winsor1_ic, o$pearson_winsor1_t_nw3)) }
cat("\n=== 상하위 10% 스프레드 (월, raw 수익) ===\n")
for (nm in names(out)) { o <- out[[nm]]
  cat(sprintf("%-5s | 평균차 %+.5f (t %+6.3f) | 중앙값차 %+.5f (t %+6.3f)\n",
      nm, o$d10_mean_spread_monthly, o$d10_mean_spread_t,
      o$d10_median_spread_monthly, o$d10_median_spread_t)) }
write_json(out, "stage_artifacts/WT-D20260821_002/transition_probe.json",
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
