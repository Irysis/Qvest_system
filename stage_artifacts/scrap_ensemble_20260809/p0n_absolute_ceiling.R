#!/usr/bin/env Rscript
# =============================================================================
# p0n_absolute_ceiling.R — 폐지 풀의 **절대 PORT_t 천장** (next_probe 유효성 관문)
#
# FR_002 계약 실측이 내 프레이밍을 교정했다:
#   폐지 풀 EW 대비 paired t 2.598~2.856  ≠  벤치마크 대비 PORT_t 1.242.
#   따라서 "분산 20% 축소로 문턱 도달"이라는 내 next_probe 근거는 무효 —
#   절대 기준에서는 1.242 → 2.95 로 **2.4배**가 필요하다.
#
# 축소추정 라운드를 제안하기 **전에** 답해야 할 것:
#   이 풀에서 **완전예지 선택**의 절대 PORT_t 천장은 얼마인가?
#   천장 < 2.95 라면 선택 정교화(축소추정 포함)는 원리적으로 문턱에 못 간다.
#
# 재는 것:
#   A. ex-post top-K (전표본 active 평균) 의 PORT_t
#   B. 무작위 탐색으로 PORT_t 최대화 (선택의 상한 근사)
#   C. 개별 모듈 최대 PORT_t (단일 최강 모듈)
#   D. 우량 풀(ELITE) 동일 측정 — 대조군 (천장이 풀 성질인지 방법 성질인지)
# metric_type = diagnostic_precheck (ex-post = PIT 아님, 상한 진단 전용)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0n_ceiling.log"), split = TRUE)

P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN <- P$PAN
scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym,"01"),"%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop=FALSE])
M <- M0[rowsc, keepc, drop=FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
C <- cor(M); diag(C) <- 0; hi <- which(C>=0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); f<-function(x){while(par[x]!=x)x<-par[x];x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a}
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; n <- nrow(Mu); K <- ncol(Mu)
Me <- as.matrix(sub[, ..elite_ok])[rowsc, , drop=FALSE]
Me <- Me[, colSums(is.finite(Me)) == n, drop=FALSE]
cat(sprintf("=== [0] %d months | SCRAP dedup %d · ELITE %d ===\n", n, K, ncol(Me)))
cat("    PORT_t = 벤치마크 대비 net active 의 NW lag-3 t (FR_002 계약 지표와 동일 정의)\n")

## PORT_t 계산기 (계약 정의: active = port − bm, NW lag-3)
port_t <- function(Mx, cols, w = NULL) {
  Mz <- Mx[, cols, drop=FALSE]; kk <- length(cols)
  if (is.null(w)) w <- matrix(1/kk, n, kk) else w <- matrix(w, n, kk, byrow=TRUE)
  pr <- Return.portfolio(xts(Mz, order.by=dtw), weights=xts(w, order.by=dtw), rebalance_on=NA)
  nn <- length(pr); bb <- bmw[(n-nn+1):n]
  a <- as.numeric(pr) - bb
  m <- lm(a ~ 1); tt <- as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3, prewhite=FALSE))[1,1])
  ar <- table.AnnualizedReturns(pr, scale=12); md <- as.numeric(maxDrawdown(pr))
  list(t=tt, pm=mean(a), sr=as.numeric(ar[3,1]), cagr=as.numeric(ar[1,1]),
       mdd=md, calmar=as.numeric(ar[1,1])/md)
}

cat("\n=== [A] ex-post top-K (전표본 active 평균 정렬) — 완전예지 선택 ===\n")
sc <- colMeans(Mu - matrix(bmw, n, K))
resA <- list()
for (kk in c(5,10,20,30,50,85)) {
  z <- port_t(Mu, order(sc, decreasing=TRUE)[1:kk])
  cat(sprintf("   K=%-3d PORT_t=%+.3f  active=%+.3f%%/m  SR=%.3f  MDD=%.1f%%  Calmar=%.3f\n",
              kk, z$t, 100*z$pm, z$sr, 100*z$mdd, z$calmar))
  resA[[as.character(kk)]] <- z
}

cat("\n=== [B] 무작위 탐색으로 PORT_t 최대화 (선택 상한 근사) ===\n")
set.seed(20260809)
best <- list(t=-9)
for (i in 1:1500) {
  kk <- sample(c(5,10,15,20,30), 1); pk <- sample(K, kk)
  z <- port_t(Mu, pk)
  if (is.finite(z$t) && z$t > best$t) { best <- z; best$K <- kk; best$pick <- pk }
}
cat(sprintf("   1500회 탐색 최대: PORT_t=%+.3f (K=%d)  active=%+.3f%%/m  SR=%.3f  MDD=%.1f%%  Calmar=%.3f\n",
            best$t, best$K, 100*best$pm, best$sr, 100*best$mdd, best$calmar))

cat("\n=== [C] 개별 모듈 최대 PORT_t (단일 최강) ===\n")
tsingle <- sapply(seq_len(K), function(j) port_t(Mu, j)$t)
cat(sprintf("   개별 85개: max=%+.3f  q95=%+.3f  median=%+.3f  min=%+.3f  | n(>2.95)=%d\n",
            max(tsingle), quantile(tsingle,.95), median(tsingle), min(tsingle), sum(tsingle > 2.95)))

cat("\n=== [D] 대조군 — 우량 풀(ELITE) 동일 측정 ===\n")
ne <- ncol(Me)
scE <- colMeans(Me - matrix(bmw, n, ne))
for (kk in c(5, min(10, ne), ne)) {
  z <- port_t(Me, order(scE, decreasing=TRUE)[1:kk])
  cat(sprintf("   ELITE K=%-3d PORT_t=%+.3f  active=%+.3f%%/m  SR=%.3f  Calmar=%.3f\n",
              kk, z$t, 100*z$pm, z$sr, z$calmar))
}
tE <- sapply(seq_len(ne), function(j) port_t(Me, j)$t)
cat(sprintf("   ELITE 개별 %d개: max=%+.3f  median=%+.3f  | n(>2.95)=%d\n",
            ne, max(tE), median(tE), sum(tE > 2.95)))

cat("\n=== [판정] ===\n")
ceilA <- max(sapply(resA, function(z) z$t)); ceilB <- best$t
cat(sprintf("  폐지 풀 절대 PORT_t 천장: ex-post top-K %+.3f · 무작위탐색 %+.3f · 개별최강 %+.3f  (문턱 2.95)\n",
            ceilA, ceilB, max(tsingle)))
cat(sprintf("  FR_002 실측(PIT) = 1.242 → 천장 대비 회수율 %.1f%%\n", 100*1.242/max(ceilA, ceilB)))
if (max(ceilA, ceilB, max(tsingle)) < 2.95) {
  cat("  ⇒ ★완전예지 선택조차 문턱 미달. **선택 정교화(축소추정 포함)로는 원리적으로 도달 불가**.\n")
  cat("    next_probe 를 '선택 개선'에서 '재료 교체 또는 다른 층'으로 재조준해야 한다.\n")
} else {
  cat("  ⇒ 천장이 문턱을 넘는다. 선택 정교화가 유효한 방향 — 회수율 개선이 표적.\n")
}

write_json(list(metric_type="diagnostic_precheck", threshold=2.95,
                expost_topK=lapply(resA, function(z) list(t=z$t, calmar=z$calmar)),
                random_search_best=list(t=best$t, K=best$K, calmar=best$calmar),
                single_max=max(tsingle), single_n_above=sum(tsingle>2.95),
                elite_single_max=max(tE), fr002_pit=1.242),
           file.path(OUT,"p0n_absolute_ceiling.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
