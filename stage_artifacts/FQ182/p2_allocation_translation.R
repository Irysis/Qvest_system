## FQ-182 P2 — ★배분 함의 직접 계산: "그래서 노출을 늘려야 하나"
## 왜: 적대검증 5렌즈는 왜도 **반전 여부**를 다투지만, 그것이 살아남아도 **배분 결론은 별개**다.
##   평균 비유의(ratio 0.29) + 변동성 크게 증가(2.86) 조합은 평균-분산 기준 노출 **축소** 근거다.
##   왜도 개선이 이를 상쇄하는지는 **효용 위에서 직접 풀어야** 답이 나온다.
## 방법: 모수 가정 없이 **실측 경험분포** 위에서 최적 노출 w* 를 ON/OFF 각각 수치최적화.
##   w*(ON) > w*(OFF) 면 도훈 가설이 **의사결정 수준에서** 지지된다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ182")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")

D <- as.data.table(readRDS(file.path(OUT, "p0.rds"))$D)[order(Date)]
D[, fwd1 := shift(BM_Ret, 1L, type = "lead")]; D <- D[!is.na(fwd1) & !is.na(dd252)]
say("=== 입력 실측 === %d일 · %s ~ %s · 관측단위 daily · forward 수익 사용",
    nrow(D), min(D$Date), max(D$Date))

## CRRA 효용: U(W) = W^(1-g)/(1-g), g=1 이면 log. 노출 w 에서 부의 배수 = 1 + w*r
## ★ w 상한 1.0 (Production Constraints: long-only, 레버리지 금지). w 하한 0.
EU <- function(r, w, g) {
  x <- 1 + w * r
  if (any(x <= 0)) return(-Inf)               # 파산 방지 (레버리지 없으면 발생 안 함)
  if (abs(g - 1) < 1e-9) mean(log(x)) else mean(x^(1-g))/(1-g)
}
opt_w <- function(r, g, wmax = 1.0) {
  f <- function(w) -EU(r, w, g)
  o <- optimize(f, c(0, wmax), tol = 1e-6)
  o$minimum
}

say("=== ★최적 노출 w* (실측 경험분포 · 레버리지 금지 상한 1.0) ===")
say("  ★해석 규약: w*(ON) > w*(OFF) 여야 '위기 뒤 비중 확대' 가 의사결정 수준에서 지지된다.")
rows <- list()
for (thr in c(-0.10, -0.20, -0.30)) {
  on <- D$dd252 <= thr
  rON <- D$fwd1[on]; rOFF <- D$fwd1[!on]
  say("--- dd252 <= %.0f%% (ON %d일 · OFF %d일) ---", thr*100, length(rON), length(rOFF))
  say("    ON  : 평균 %+.5f · sd %.5f · 최악 %.4f", mean(rON), sd(rON), min(rON))
  say("    OFF : 평균 %+.5f · sd %.5f · 최악 %.4f", mean(rOFF), sd(rOFF), min(rOFF))
  for (g in c(1, 2, 5, 10)) {
    wo <- opt_w(rON, g); wf <- opt_w(rOFF, g)
    say("    위험회피 g=%-2g : w*(ON) %.3f · w*(OFF) %.3f · **차이 %+.3f** %s",
        g, wo, wf, wo - wf, if (wo > wf) "(확대 지지)" else "(축소 시사)")
    rows[[length(rows)+1L]] <- data.table(thr = thr*100, gamma = g, w_on = wo, w_off = wf,
                                          diff = wo - wf)
  }
}
R <- rbindlist(rows)

## ★부트스트랩 — w* 차이가 표본 잡음인가 (블록 60일)
say("=== ★w* 차이의 블록 부트스트랩 (60일 블록 300회) ===")
set.seed(20260809)
boot_wdiff <- function(x, on, g, B = 300L, blk = 60L) {
  n <- length(x); nb <- ceiling(n/blk); starts <- seq_len(max(1, n-blk+1)); o <- numeric(0)
  for (b in seq_len(B)) {
    s <- sample(starts, nb, replace = TRUE)
    idx <- as.integer(unlist(lapply(s, function(k) k:min(k+blk-1, n))))[1:n]
    xb <- x[idx]; ob <- on[idx]
    if (sum(ob) < 50 || sum(!ob) < 50) next
    o <- c(o, opt_w(xb[ob], g) - opt_w(xb[!ob], g))
  }
  o
}
for (thr in c(-0.20, -0.30)) {
  on <- D$dd252 <= thr
  for (g in c(2, 5)) {
    bo <- boot_wdiff(D$fwd1, on, g)
    obs <- R[thr == thr*100 & gamma == g, diff]
    obs <- R[abs(thr - thr*100) < 1e-9 & gamma == g, diff]
    d0 <- opt_w(D$fwd1[on], g) - opt_w(D$fwd1[!on], g)
    say("  thr %.0f%% g=%g : 관측 %+.3f · 부트 평균 %+.3f · sd %.3f · **P(차이>0) %.3f**",
        thr*100, g, d0, mean(bo), sd(bo), mean(bo > 0))
  }
}

say("=== ★핵심 대조: 평균만 vs 분포 전체 ===")
say("  '평균-분산만 보면' 과 '실측 분포 전체(왜도·첨도 포함)' 가 다른 답을 주는가?")
for (thr in c(-0.20, -0.30)) {
  on <- D$dd252 <= thr
  rON <- D$fwd1[on]; rOFF <- D$fwd1[!on]
  ## 평균-분산 근사 최적 (g 위험회피): w* ~ mu / (g * sigma^2), 상한 1
  mv_on  <- min(1, max(0, mean(rON)/(2*var(rON))))
  mv_off <- min(1, max(0, mean(rOFF)/(2*var(rOFF))))
  emp_on <- opt_w(rON, 2); emp_off <- opt_w(rOFF, 2)
  say("  thr %.0f%% (g=2): 평균-분산 w* ON %.3f/OFF %.3f (차 %+.3f) | 경험분포 w* ON %.3f/OFF %.3f (차 %+.3f)",
      thr*100, mv_on, mv_off, mv_on-mv_off, emp_on, emp_off, emp_on-emp_off)
  say("    ★왜도·첨도가 답을 바꾸는가: %s",
      if (sign(mv_on-mv_off) != sign(emp_on-emp_off)) "★★부호가 다르다 — 분포 형태가 결론을 뒤집는다" else "부호 동일 — 형태가 결론을 바꾸지 않는다")
}

fwrite(R, file.path(OUT, "p2_optimal_exposure.csv"))
saveRDS(R, file.path(OUT, "p2.rds"))
say("=== P2 완료 ===")
