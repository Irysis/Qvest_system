#!/usr/bin/env Rscript
# =============================================================================
# p0j_null_fixed.R — p0i [Q3] 음성 대조 설계 오류 수정 + 재검정
#
# ★내 버그: 시장조정 회귀 lm(y ~ bmw) 의 음성 대조로 **y 의 행만 셔플**했다.
#   그러면 y 와 bmw 의 시간 대응이 깨져 베타가 0 으로 붕괴하고,
#   절편이 '모듈 평균수익 전체(시장수익 포함, 약 +1.2%/m)'를 흡수한다.
#   → 귀무에서 t>+2 가 85개 중 80.8개(!) 나온 것. 검사기가 죽은 것이지 신호가 아니다.
#   실측 증거: 음성대조 mean=80.8 q95=84.0 vs 실측 19 (귀무가 실측을 압도 = 사망 신호)
#
#   ※ p0e/p0f 의 PC1 회귀는 종속변수가 **active**(벤치 기차감)라 같은 셔플이 정상 작동했다
#     (귀무 mean 1.1 q95 2.0 vs 실측 16). 그쪽 결과는 유효.
#
# 올바른 귀무 = "알파 0, 베타 유지":  y_null_i = beta_i * bm + shuffle(resid_i)
#   회귀는 관측 순서에 불변이므로 (y,bm) 쌍 동시 셔플은 무의미 → 잔차만 셔플해야 한다.
#   시간 구조를 더 보존하려면 블록 부트스트랩(block=12) 판본도 함께 본다.
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0j_null.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop = FALSE])
M <- M0[rowsc, keepc, drop = FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
C <- cor(M); diag(C) <- 0; hi <- which(C >= 0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); f<-function(x){while(par[x]!=x)x<-par[x];x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a}
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; n <- nrow(Mu); K <- ncol(Mu)
cat(sprintf("=== [0] %d months x %d dedup modules ===\n", n, K))

## 실측
fit <- t(apply(Mu, 2, function(y){ m<-summary(lm(y ~ bmw))$coefficients; c(m[1,1], m[1,3], m[2,1]) }))
colnames(fit) <- c("alpha","t","beta")
obs <- sum(fit[,"t"] > 2)
cat(sprintf("[1] 실측 시장조정 알파 t>+2 = %d / %d   (기대오탐 %.1f)\n", obs, K, 0.025*K))

resid_mat <- sapply(seq_len(K), function(j) residuals(lm(Mu[,j] ~ bmw)))
beta <- fit[,"beta"]

cat("\n=== [2] 음성 대조 A — 잘못된 판본 재현 (y 행 셔플) ===\n")
set.seed(20260809)
badn <- replicate(100, { yp <- Mu[sample(n), , drop=FALSE]
  sum(apply(yp, 2, function(y) summary(lm(y ~ bmw))$coefficients[1,3]) > 2) })
cat(sprintf("  귀무 t>+2: mean=%.1f  q95=%.1f  vs 실측 %d   ⇒ 귀무 > 실측 = 검사기 사망\n",
            mean(badn), quantile(badn,.95), obs))
cat(sprintf("  진단: 셔플판 베타 median=%.4f (원본 %.3f) — 베타 파괴 확인\n",
            median(apply(Mu[sample(n),,drop=FALSE], 2, function(y) coef(lm(y ~ bmw))[2])), median(beta)))

cat("\n=== [3] 음성 대조 B — 올바른 판본: 알파 0 · 베타 유지 (잔차 셔플) ===\n")
nullB <- replicate(300, {
  ix <- sample(n)
  yn <- sweep(resid_mat[ix, , drop=FALSE], 2, 0, "+") + outer(bmw, beta)
  sum(apply(yn, 2, function(y) summary(lm(y ~ bmw))$coefficients[1,3]) > 2)
})
cat(sprintf("  귀무 t>+2: mean=%.2f  sd=%.2f  q95=%.1f  max=%d  vs 실측 %d\n",
            mean(nullB), sd(nullB), quantile(nullB,.95), max(nullB), obs))
cat(sprintf("  경험적 p(귀무 >= 실측) = %.4f\n", mean(nullB >= obs)))

cat("\n=== [4] 음성 대조 C — 블록 부트스트랩(block=12, 시간구조 보존) ===\n")
blk <- 12L
nullC <- replicate(300, {
  starts <- sample(seq_len(n - blk + 1), ceiling(n/blk), replace = TRUE)
  ix <- head(unlist(lapply(starts, function(s) s:(s+blk-1))), n)
  yn <- resid_mat[ix, , drop=FALSE] + outer(bmw, beta)
  sum(apply(yn, 2, function(y) summary(lm(y ~ bmw))$coefficients[1,3]) > 2)
})
cat(sprintf("  귀무 t>+2: mean=%.2f  sd=%.2f  q95=%.1f  max=%d  vs 실측 %d\n",
            mean(nullC), sd(nullC), quantile(nullC,.95), max(nullC), obs))
cat(sprintf("  경험적 p(귀무 >= 실측) = %.4f\n", mean(nullC >= obs)))

cat("\n=== [5] 양성 대조 — 알파를 주입하면 검사기가 잡는가 (검사기 생존 확인) ===\n")
for (inj in c(0.002, 0.005)) {
  pos <- replicate(50, {
    ix <- sample(n)
    yn <- resid_mat[ix, , drop=FALSE] + outer(bmw, beta) + inj
    sum(apply(yn, 2, function(y) summary(lm(y ~ bmw))$coefficients[1,3]) > 2)
  })
  cat(sprintf("  알파 +%.1f%%/m 주입: 검출 t>+2 mean=%.1f / %d  (검사기 %s)\n",
              100*inj, mean(pos), K, if (mean(pos) > mean(nullC)+3*sd(nullC)) "작동" else "둔감"))
}

cat("\n=== [6] 판정 ===\n")
pB <- mean(nullB >= obs); pC <- mean(nullC >= obs)
cat(sprintf("  실측 %d / %d · 올바른 귀무 q95 = %.1f(셔플) / %.1f(블록)\n",
            obs, K, quantile(nullB,.95), quantile(nullC,.95)))
if (pC < 0.05 && pB < 0.05) {
  cat("  ⇒ 시장조정 알파 다수성은 두 귀무 모두에서 유의. 신호 실재.\n")
} else {
  cat(sprintf("  ⇒ 유의하지 않음 (p_shuffle=%.3f p_block=%.3f). '19건 유의'는 철회.\n", pB, pC))
}
cat("  ※ 단 다수성 유의 != 개별 모듈 자격. 개별은 여전히 다중검정 보정 대상.\n")

write_json(list(metric_type="diagnostic_precheck", observed=obs, n_modules=K,
                null_bad_mean=mean(badn), null_bad_q95=as.numeric(quantile(badn,.95)),
                null_shuffle_mean=mean(nullB), null_shuffle_q95=as.numeric(quantile(nullB,.95)),
                p_shuffle=pB, null_block_mean=mean(nullC),
                null_block_q95=as.numeric(quantile(nullC,.95)), p_block=pC),
           file.path(OUT,"p0j_null_fixed.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
