#!/usr/bin/env Rscript
# =============================================================================
# p0m_uncond_control.R — p0l 에 빠져 있던 결정적 대조군
#
# p0l 은 워크포워드 잔차-알파 선택을 (a) base EW · (b) 무작위 와만 비교했다.
# power-bar 에이전트 지적: **무조건부 trailing IR 선택**과 비교하지 않았다.
#   그쪽 rho 추정 = 잔차축 +0.2815 vs 무조건부 +0.2987 → 잔차 선택의 이점 0 예측.
#
# 이 대조가 갈리는 것:
#   · 잔차 ≈ 무조건부 → "직교성"은 수사일 뿐, 신호는 그냥 '잘한 놈 고르기'
#   · 잔차 > 무조건부 → 직교 축이 실제로 추가 정보
#
# 함께 재는 것: 두 선택의 멤버십 겹침(Jaccard) — 성과가 같아도 다른 집합이면 다른 얘기.
# 전부 동일 워크포워드·동일 K 격자·동일 월 집합 (paired 성립 조건).
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0m_uncond.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop = FALSE])
M <- M0[rowsc, keepc, drop=FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
C <- cor(M); diag(C) <- 0; hi <- which(C>=0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); f<-function(x){while(par[x]!=x)x<-par[x];x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a}
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; n <- nrow(Mu); K <- ncol(Mu); A <- Mu - matrix(bmw, n, K)
IS0 <- 60L; rows <- (IS0+1):n
cat(sprintf("=== [0] %d months x %d modules | OOS %d개월 %s..%s ===\n",
            n, K, length(rows), format(dtw[IS0+1],"%Y-%m"), format(dtw[n],"%Y-%m")))

## 선택 규칙 — 전부 t 까지 정보만, t+1 보유
picks_resid <- vector("list", n); picks_uncond <- vector("list", n); picks_ir <- vector("list", n)
for (t in IS0:(n-1)) {
  Ais <- A[1:t, , drop=FALSE]
  pc <- prcomp(scale(Ais), center=FALSE); f1 <- as.numeric(pc$x[,1]); f1 <- f1/sd(f1)
  picks_resid[[t+1]]  <- order(apply(Ais, 2, function(y) summary(lm(y ~ f1))$coefficients[1,3]), decreasing=TRUE)
  picks_uncond[[t+1]] <- order(colMeans(Ais), decreasing=TRUE)                       # 무조건부 평균 active
  picks_ir[[t+1]]     <- order(colMeans(Ais)/apply(Ais,2,sd), decreasing=TRUE)       # 무조건부 IR
}
mkW <- function(pk, kk) { W <- matrix(0, n, K)
  for (t in rows) if (!is.null(pk[[t]])) W[t, pk[[t]][1:kk]] <- 1/kk; W }
ewW <- function() { W <- matrix(0, n, K); W[rows, ] <- 1/K; W }

run <- function(W, base_r=NULL) {
  Mz <- Mu[rows, , drop=FALSE]
  pr <- Return.portfolio(xts(Mz, order.by=dtw[rows]),
                         weights=xts(W[rows,,drop=FALSE], order.by=dtw[rows]), rebalance_on=NA)
  nn <- length(pr); rr <- tail(rows, nn)
  ar <- table.AnnualizedReturns(pr, scale=12); mdd <- as.numeric(maxDrawdown(pr))
  o <- list(cagr=as.numeric(ar[1,1]), sharpe=as.numeric(ar[3,1]), mdd=mdd,
            calmar=as.numeric(ar[1,1])/mdd, series=as.numeric(pr), rr=rr)
  if (!is.null(base_r)) { d <- o$series - base_r
    m <- lm(d ~ 1); o$t <- as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3, prewhite=FALSE))[1,1]); o$pm <- mean(d) }
  o
}
b <- run(ewW())
cat(sprintf("\n[base] EW85  CAGR=%.2f%% SR=%.3f MDD=%.1f%% Calmar=%.3f  (n=%d)\n",
            100*b$cagr, b$sharpe, 100*b$mdd, b$calmar, length(b$series)))

KG <- c(10, 20, 30, 40, 50)
cat("\n=== [1] 세 선택 규칙 · K 격자 전량 (argmax 선택 아님 — 곡선 형태 특성화) ===\n")
cat(sprintf("  %-4s | %-28s | %-28s | %-28s\n", "K", "잔차-알파", "무조건부 평균", "무조건부 IR"))
R <- list()
for (kk in KG) {
  a <- run(mkW(picks_resid,  kk), b$series)
  u <- run(mkW(picks_uncond, kk), b$series)
  i <- run(mkW(picks_ir,     kk), b$series)
  cat(sprintf("  %-4d | %+.3f%%/m t=%+.3f Cal=%.3f | %+.3f%%/m t=%+.3f Cal=%.3f | %+.3f%%/m t=%+.3f Cal=%.3f\n",
              kk, 100*a$pm, a$t, a$calmar, 100*u$pm, u$t, u$calmar, 100*i$pm, i$t, i$calmar))
  R[[paste0("K", kk)]] <- list(resid=list(pm=a$pm,t=a$t,calmar=a$calmar,mdd=a$mdd,sharpe=a$sharpe),
                               uncond=list(pm=u$pm,t=u$t,calmar=u$calmar),
                               ir=list(pm=i$pm,t=i$t,calmar=i$calmar))
}

cat("\n=== [2] ★직접 대결 — 잔차 vs 무조건부 (paired, 같은 월) ===\n")
for (kk in KG) {
  a <- run(mkW(picks_resid, kk)); u <- run(mkW(picks_uncond, kk)); i <- run(mkW(picks_ir, kk))
  for (nm in c("평균","IR")) {
    o <- if (nm=="평균") u else i
    d <- a$series - o$series; m <- lm(d ~ 1)
    tt <- as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3, prewhite=FALSE))[1,1])
    cat(sprintf("  K=%-3d 잔차 − 무조건부%-3s : %+.4f%%/m  t_NW3=%+.3f %s\n",
                kk, nm, 100*mean(d), tt, if (abs(tt)>=2) "  <= 유의" else ""))
  }
}

cat("\n=== [3] 멤버십 겹침 (성과가 같아도 집합이 다르면 다른 규칙) ===\n")
for (kk in c(10, 30)) {
  jac <- sapply(rows, function(t) {
    if (is.null(picks_resid[[t]])) return(NA)
    x <- picks_resid[[t]][1:kk]; y <- picks_uncond[[t]][1:kk]
    length(intersect(x,y))/length(union(x,y)) })
  jac2 <- sapply(rows, function(t) {
    if (is.null(picks_resid[[t]])) return(NA)
    x <- picks_resid[[t]][1:kk]; y <- picks_ir[[t]][1:kk]
    length(intersect(x,y))/length(union(x,y)) })
  cat(sprintf("  K=%-3d Jaccard(잔차, 무조건부평균) median=%.3f  |  Jaccard(잔차, 무조건부IR) median=%.3f\n",
              kk, median(jac, na.rm=TRUE), median(jac2, na.rm=TRUE)))
}

cat("\n=== [판정] ===\n")
best_r <- max(sapply(R, function(z) z$resid$t)); best_u <- max(sapply(R, function(z) z$uncond$t))
best_i <- max(sapply(R, function(z) z$ir$t))
cat(sprintf("  K 격자 최대 t : 잔차 %+.3f · 무조건부평균 %+.3f · 무조건부IR %+.3f\n", best_r, best_u, best_i))
cat(sprintf("  ⇒ %s\n", if (best_r > best_u + 0.3 && best_r > best_i + 0.3)
  "잔차 축이 무조건부보다 우월 — 직교성이 추가 정보" else
  "잔차 축이 무조건부와 구별되지 않음 — '직교성' 프레이밍은 철회하고 '단순 성과 선택'으로 서술"))
cat("  ※ K 격자 5점 x 규칙 3종 = 15 trial → 개별 t 는 다중검정 보정 대상(Bonferroni t≈2.94).\n")

write_json(list(metric_type="diagnostic_precheck", K_grid=KG, base=list(cagr=b$cagr,sharpe=b$sharpe,mdd=b$mdd,calmar=b$calmar),
                results=R, best_t=list(resid=best_r, uncond=best_u, ir=best_i)),
           file.path(OUT,"p0m_uncond_control.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
