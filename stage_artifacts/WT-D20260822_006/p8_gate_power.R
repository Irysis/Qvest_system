## P8 — R1/F1 게이트의 검정력 (자기 적대검증에서 적발한 결손 수리)
suppressPackageStartupMessages({library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
P <- readRDS(file.path(OUT,"p2_arms.rds")); V3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
V4 <- readRDS(file.path(W004,"p4_verdict.rds"))
c0 <- P$act$C0$act; U <- P$U
std <- function(x) (x-mean(x))/sd(x)
nw_slope <- function(y, x) { fit <- lm(y ~ x); b <- coef(fit)[2]; e <- residuals(fit); X <- cbind(1,x)
  bread <- solve(crossprod(X)); meat <- crossprod(X*e); n <- length(e)
  for (l in 1:3) { w <- 1-l/4
    G <- crossprod(X[(l+1):n,,drop=FALSE]*e[(l+1):n], X[1:(n-l),,drop=FALSE]*e[1:(n-l)])
    meat <- meat + w*(G+t(G)) }
  V <- bread %*% meat %*% bread
  list(b=unname(b), se=sqrt(V[2,2]), t=unname(b/sqrt(V[2,2]))) }

hz <- V4$act$ORACLE_K$act - c0
cat("=== R1 게이트 검정력 (여유폭 ~ 상태 기울기) ===\n")
cat(sprintf("  여유폭 계열: 평균 %+.6f/월 (%+.3f %%p/yr) · sd %.6f · AR1 %+.4f\n",
  mean(hz), mean(hz)*12*100, sd(hz), cor(hz[-1], hz[-length(hz)])))
for (nm in c("AGREE","DISP","BEAR")) {
  r <- nw_slope(hz, std(U[[nm]]))
  mde15 <- 1.5*r$se*12*100; mde20 <- 2.0*r$se*12*100
  cat(sprintf("  %-6s slope %+.5f/월 (%+.3f %%p/yr per 1sd) · SE %.5f · t %+.4f\n", nm, r$b, r$b*12*100, r$se, r$t))
  cat(sprintf("         MDE(문턱 t=1.5) = %.3f %%p/yr per 1sd · MDE(t=2.0) = %.3f · 여유폭 평균 대비 %.1f%% / %.1f%%\n",
    mde15, mde20, 100*mde15/(mean(hz)*12*100), 100*mde20/(mean(hz)*12*100)))
}
cat("\n  ★해석 기준: 1sd 상태 변화가 여유폭의 몇 %를 설명해야 검출되는가 = 위 마지막 열.\n")

cat("\n=== F1 게이트 검정력 (2군 IC 차 ~ 분산상태 기울기) ===\n")
D <- V3$D; ok <- is.finite(D)
r <- nw_slope(D[ok], std(U$DISP[ok]))
cat(sprintf("  D_t: n %d · 평균 %+.5f · sd %.5f\n", sum(ok), mean(D[ok]), sd(D[ok])))
cat(sprintf("  slope %+.6f · SE %.6f · t %+.4f · MDE(t=1.5) %.6f (= D_t sd 의 %.1f%%)\n",
  r$b, r$se, r$t, 1.5*r$se, 100*1.5*r$se/sd(D[ok])))
cat(sprintf("  관측 slope 는 MDE 의 %.2f 배 — %s\n", abs(r$b)/(1.5*r$se),
  if (abs(r$b) >= 1.5*r$se) "검출 가능 크기" else "검출 문턱 미만"))
saveRDS(list(hz_stats=list(mean=mean(hz), sd=sd(hz)),
  R1=lapply(setNames(c("AGREE","DISP","BEAR"), c("AGREE","DISP","BEAR")),
            function(n) nw_slope(hz, std(U[[n]]))),
  F1=r), file.path(OUT,"p8_gate_power.rds"))
cat("\n[saved] p8_gate_power.rds\n")
