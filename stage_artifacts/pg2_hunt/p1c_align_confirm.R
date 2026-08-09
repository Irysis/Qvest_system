## p1c — offset +2 의 **독립 확인** (상관 0.9375 는 결정적이지만 정확일치 0 이라 2차 증거를 요구)
## 지문 = 시장 극단월. 2008-10(금융위기)·2020-03(코로나) 같은 달은 어느 계열에서도 최저다.
## 두 계열의 극단월 라벨이 offset 만큼 어긋나 있으면 정렬이 확증된다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1c] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d, "%Y"))*12L + as.integer(format(d, "%m"))
lab <- function(m) sprintf("%04d-%02d", (m-1L) %/% 12L, (m-1L) %% 12L + 1L)

B <- bm_load_incumbent(); B[, m := mi(date)]
M <- readRDS(file.path(OUT, "mkt.rds")); CB <- as.data.table(M$bench)[, .(Date, BM_Ret)][, m := mi(Date)]
CBw <- CB[m >= min(B$m) - 3L & m <= max(B$m) + 3L]

say("=== 1. 극단월 지문 (하위 6개월) ===")
p_lo <- B[order(benchmark_ret)][1:6, .(pg2_label = lab(m), ret = round(benchmark_ret, 4))]
c_lo <- CBw[order(BM_Ret)][1:6, .(cand_label = lab(m), ret = round(BM_Ret, 4))]
say("  PG2 벤치 최저 6: %s", paste(sprintf("%s(%.3f)", p_lo$pg2_label, p_lo$ret), collapse=" "))
say("  후보 벤치 최저 6: %s", paste(sprintf("%s(%.3f)", c_lo$cand_label, c_lo$ret), collapse=" "))

say("=== 2. 극단월 offset 실측 (하위 10 · 상위 10 각각) ===")
for (side in c("lo","hi")) {
  pp <- if (side=="lo") B[order(benchmark_ret)][1:10, m] else B[order(-benchmark_ret)][1:10, m]
  cc <- if (side=="lo") CBw[order(BM_Ret)][1:10, m] else CBw[order(-BM_Ret)][1:10, m]
  ## 각 PG2 극단월에 대해 가장 가까운 후보 극단월과의 차
  dif <- vapply(pp, function(x) { d <- x - cc; d[which.min(abs(d))] }, integer(1))
  tb <- table(dif)
  say("  [%s] PG2월 - 후보월 분포: %s", side,
      paste(sprintf("%s개월:%d건", names(tb), as.integer(tb)), collapse=" "))
  say("       최빈 offset = %+s (%d/10)", names(tb)[which.max(tb)], max(tb))
}

say("=== 3. 특정 사건 직접 조회 ===")
for (ev in c("2008-10","2020-03","2008-11","2022-09")) {
  y <- as.integer(substr(ev,1,4)); mo <- as.integer(substr(ev,6,7)); k <- y*12L+mo
  pv <- B[m == k, benchmark_ret]; cv <- CBw[m == k, BM_Ret]
  cv2 <- CBw[m == k - 2L, BM_Ret]
  say("  %s : PG2 %s · 후보(동월) %s · 후보(m-2) %s", ev,
      if (length(pv)) sprintf("%+.4f", pv) else "없음",
      if (length(cv)) sprintf("%+.4f", cv) else "없음",
      if (length(cv2)) sprintf("%+.4f", cv2) else "없음")
}

say("=== 4. ★독립 확인 종합 ===")
X0 <- merge(B[, .(m, pg2=benchmark_ret)], CBw[, .(m, cand=BM_Ret)], by="m")
X2 <- merge(B[, .(m, pg2=benchmark_ret)], copy(CBw)[, .(m = m+2L, cand=BM_Ret)], by="m")
say("  offset 0: n=%d cor=%.4f · 부호일치 %.1f%%", nrow(X0), cor(X0$pg2,X0$cand),
    100*mean(sign(X0$pg2)==sign(X0$cand)))
say("  offset+2: n=%d cor=%.4f · 부호일치 %.1f%%", nrow(X2), cor(X2$pg2,X2$cand),
    100*mean(sign(X2$pg2)==sign(X2$cand)))
say("  ⇒ 부호일치까지 offset+2 가 우월하면 정렬 확증")

say("=== 5. ★잔여 불일치의 정체 (offset+2 에서도 정확일치 0) ===")
d2 <- X2$pg2 - X2$cand
say("  차이: 평균 %+.5f · sd %.5f · 최대절대 %.4f", mean(d2), sd(d2), max(abs(d2)))
say("  회귀 pg2 ~ cand: 기울기 %.4f · 절편 %+.5f · R2 %.4f",
    coef(lm(pg2~cand, X2))[2], coef(lm(pg2~cand, X2))[1], summary(lm(pg2~cand, X2))$r.squared)
say("  ⇒ 기울기~1·절편~0 이면 **같은 지수 다른 빈티지**, 기울기가 1에서 멀면 다른 계열")
say("  ★어느 쪽이든 ΔIR 은 PG2 벤치 단일 기준이라 무관 — 슬리브 standalone 수치만 basis 라벨 필요")
