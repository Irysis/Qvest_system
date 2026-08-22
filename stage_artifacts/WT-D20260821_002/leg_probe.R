## 다리 분해 — 분포-표적 우위가 long leg 인가 short leg 인가
## KR 공매도 불가(mechanism.friction 이 명명한 마찰)이므로 short leg 우위는 long-only 로 회수 불가.
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
frd <- as.data.table(S$frd)
## ★플레이스홀더 월 배제 — 2026-09-01 은 Ret_1m 이 347종목 전부 정확히 0 (미실현 forward).
##   NA 가 아니라 0 이라 !is.na 필터를 통과한다. co-primary 는 벤치 조인에서 이미 탈락(n=198)했으나
##   본 진단은 그것을 그대로 통과시켜 199개월로 집계했다 — 결손을 정상값으로 내려앉히는 형태라 차단한다.
.ph <- frd[is.finite(Ret_1m), .(sd_r = sd(Ret_1m)), by = Date][sd_r == 0, Date]
if (length(.ph)) { cat("[leg_probe] 플레이스홀더 월 배제:", format(.ph), "\n"); frd <- frd[!Date %in% .ph] }
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x); m <- mean(x); e <- x - m
  s <- sum(e^2)/n; for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }
arms <- list(armA = S$panels$armA[, .(Date, Ticker, sc = as.numeric(score))],
             armB = S$panels$armB[, .(Date, Ticker, sc = as.numeric(q50))],
             armC = S$panels$armC[, .(Date, Ticker, sc = as.numeric(score))])
leg <- list(); degen <- list()
for (nm in names(arms)) {
  X <- merge(as.data.table(arms[[nm]]), frd[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  X <- X[is.finite(sc) & is.finite(Ret_1m)]
  nd <- X[, .(sd_sc = sd(sc)), by = Date][sd_sc == 0 | !is.finite(sd_sc), .N]
  degen[[nm]] <- nd
  L <- X[, {
    n <- .N; k <- max(1L, floor(n*0.1)); r <- frank(-sc, ties.method = "first")
    u <- mean(Ret_1m)
    .(uni = u,
      long_excess  = mean(Ret_1m[r <= k]) - u,        # 상위 10% − 유니버스 (long-only 회수 가능)
      short_excess = u - mean(Ret_1m[r > n - k]),     # 유니버스 − 하위 10% (공매도 필요)
      top25_excess = mean(Ret_1m[r <= min(25L, n)]) - u)}, by = Date]
  leg[[nm]] <- list(
    long_excess_monthly = mean(L$long_excess), long_excess_t = nw_t(L$long_excess),
    long_excess_annual_pct = 100*12*mean(L$long_excess),
    short_excess_monthly = mean(L$short_excess), short_excess_t = nw_t(L$short_excess),
    short_excess_annual_pct = 100*12*mean(L$short_excess),
    top25_excess_annual_pct = 100*12*mean(L$top25_excess), top25_excess_t = nw_t(L$top25_excess),
    n_months = nrow(L), n_degenerate_months = nd)
}
cat("=== 다리 분해 (유니버스 평균 대비 초과, 연 %p) ===\n")
cat(sprintf("%-5s | %-24s | %-24s | %-22s | 퇴화월\n", "arm", "LONG 상위10% (회수가능)", "SHORT 하위10% (회수불가)", "top-25 (실소비)"))
for (nm in names(leg)) { o <- leg[[nm]]
  cat(sprintf("%-5s | %+7.3f%%p (t %+6.3f)     | %+7.3f%%p (t %+6.3f)     | %+7.3f%%p (t %+6.3f) | %d\n",
      nm, o$long_excess_annual_pct, o$long_excess_t,
      o$short_excess_annual_pct, o$short_excess_t,
      o$top25_excess_annual_pct, o$top25_excess_t, o$n_degenerate_months)) }
cat("\n=== armA 대비 차 (연 %p) ===\n")
for (nm in c("armB","armC")) {
  cat(sprintf("%s−armA : LONG %+7.3f%%p | SHORT %+7.3f%%p | top25 %+7.3f%%p\n", nm,
      leg[[nm]]$long_excess_annual_pct - leg$armA$long_excess_annual_pct,
      leg[[nm]]$short_excess_annual_pct - leg$armA$short_excess_annual_pct,
      leg[[nm]]$top25_excess_annual_pct - leg$armA$top25_excess_annual_pct)) }
write_json(leg, "stage_artifacts/WT-D20260821_002/leg_probe.json",
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
