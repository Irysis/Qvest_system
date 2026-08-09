#!/usr/bin/env Rscript
# =============================================================================
# p0i_pc1_is_beta.R — 마지막 살아있는 축의 운명을 가르는 검정
#
# 배경: 적대검증(p3_rho)이 상태-조건부 지속성의 정체를 **시장 베타**로 확정했다
#   (DOWN spearman(beta, 상태평균 active) = -0.975 · SURGE +0.985 · 잔차화 시 rho 음수 붕괴).
#   ⇒ 상태-조건부 멤버십 선택 = 베타 베팅 = 노출 스케일 축 = WT-D20260809_002 소관.
#
# 남은 축 = **잔차 직교 선택** (PC1 회귀 잔차 알파 t>+2 가 16/85, 음성대조 q95=2.0).
# 그런데 PC1(분산 0.643)이 사실상 시장 요인이면 이 축도 베타로 수렴한다.
#
# 본 검정이 답할 것:
#   Q1. PC1 == 시장인가? (PC1 점수 vs 벤치 수익 / PC1 부하 vs 모듈 베타)
#   Q2. 잔차 알파 16건은 그냥 저베타 모듈인가?
#   Q3. **시장 베타를 직접 제거**해도 잔차 알파가 살아남는가? (PC1 아닌 관측 벤치로)
#   Q4. 살아남은 것이 있다면 그 부분집합의 앙상블은 base 를 이기는가 (상한 진단)
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0i_pc1_beta.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop = FALSE])
M <- M0[rowsc, keepc, drop = FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
C <- cor(M); diag(C) <- 0; hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[,1] < hi[,2], , drop=FALSE]
comp <- local({ par <- seq_len(ncol(M)); f <- function(x){while(par[x]!=x) x<-par[x]; x}
  if (nrow(hi)) for (r in seq_len(nrow(hi))) { a<-f(hi[r,1]); b<-f(hi[r,2]); if (a!=b) par[b]<-a }
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp == g)[1], integer(1))
Mu <- M[, reps, drop = FALSE]; ids <- colnames(M)[reps]
n <- nrow(Mu); K <- ncol(Mu)
A <- Mu - matrix(bmw, n, K)          # active
cat(sprintf("=== [0] %d months x %d dedup modules ===\n", n, K))

## ── Q1. PC1 == 시장? ─────────────────────────────────────────────────
cat("\n=== [Q1] PC1 은 시장 요인인가 ===\n")
pcA <- prcomp(scale(A), center = FALSE); f1A <- as.numeric(pcA$x[,1])
pcT <- prcomp(scale(Mu), center = FALSE); f1T <- as.numeric(pcT$x[,1])
evA <- pcA$sdev^2; evT <- pcT$sdev^2
cat(sprintf("  active PC1 share=%.3f | total-return PC1 share=%.3f\n", evA[1]/sum(evA), evT[1]/sum(evT)))
cat(sprintf("  cor(총수익 PC1 점수, 벤치수익) = %+.4f   R^2=%.3f\n",
            cor(f1T, bmw), cor(f1T, bmw)^2))
cat(sprintf("  cor(active PC1 점수, 벤치수익)  = %+.4f   R^2=%.3f\n",
            cor(f1A, bmw), cor(f1A, bmw)^2))
beta <- apply(Mu, 2, function(y) as.numeric(coef(lm(y ~ bmw))[2]))
loadA <- pcA$rotation[,1]; loadT <- pcT$rotation[,1]
cat(sprintf("  모듈 베타: median=%.3f [5%%,95%%]=[%.3f, %.3f]\n",
            median(beta), quantile(beta,.05), quantile(beta,.95)))
cat(sprintf("  spearman(총수익 PC1 부하, 베타) = %+.4f\n", cor(loadT, beta, method="spearman")))
cat(sprintf("  spearman(active  PC1 부하, 베타) = %+.4f\n", cor(loadA, beta, method="spearman")))
q1 <- list(pc1_active_share=evA[1]/sum(evA), pc1_total_share=evT[1]/sum(evT),
           cor_pc1total_bm=cor(f1T,bmw), cor_pc1active_bm=cor(f1A,bmw),
           sp_loadT_beta=cor(loadT,beta,method="spearman"),
           sp_loadA_beta=cor(loadA,beta,method="spearman"))

## ── Q2. 잔차 알파 16건 = 저베타 모듈인가 ────────────────────────────
cat("\n=== [Q2] PC1-잔차 알파 상위군의 베타 분포 ===\n")
f1s <- f1A/sd(f1A)
fitPC <- t(apply(A, 2, function(y){ m<-summary(lm(y ~ f1s))$coefficients; c(m[1,1], m[1,3]) }))
sel <- which(fitPC[,2] > 2)
cat(sprintf("  PC1-잔차 t>+2 : %d 건\n", length(sel)))
cat(sprintf("  그 %d 건 베타: median=%.3f [min,max]=[%.3f, %.3f]  | 전체 median=%.3f\n",
            length(sel), median(beta[sel]), min(beta[sel]), max(beta[sel]), median(beta)))
cat(sprintf("  베타 백분위: 선택군 median = 전체의 %.1f 분위\n",
            100*mean(beta <= median(beta[sel]))))
cat(sprintf("  spearman(PC1-잔차 t, 베타) = %+.4f\n", cor(fitPC[,2], beta, method="spearman")))

## ── Q3. ★시장 베타를 직접 제거해도 잔차 알파가 사는가 ───────────────
cat("\n=== [Q3] 관측 벤치로 직접 시장조정 — 잔차 알파 생존 검정 ===\n")
fitMK <- t(apply(Mu, 2, function(y){ m<-summary(lm(y ~ bmw))$coefficients; c(m[1,1], m[1,3]) }))
cat(sprintf("  시장조정 알파(절편): mean=%+.4f%%/m  n(t>+2)=%d  n(t<-2)=%d  of %d  기대오탐=%.1f\n",
            100*mean(fitMK[,1]), sum(fitMK[,2] > 2), sum(fitMK[,2] < -2), K, 0.025*K))
set.seed(20260809)
nullMK <- replicate(200, { yp <- Mu[sample(n), , drop=FALSE]
  sum(apply(yp, 2, function(y) summary(lm(y ~ bmw))$coefficients[1,3]) > 2) })
cat(sprintf("  [음성 대조] 행 셔플 200회: mean=%.1f  q95=%.1f  vs 실측 %d\n",
            mean(nullMK), quantile(nullMK,.95), sum(fitMK[,2] > 2)))
## PC1-잔차 생존군과 시장조정 생존군의 겹침
selMK <- which(fitMK[,2] > 2)
cat(sprintf("  PC1-잔차 생존 %d · 시장조정 생존 %d · 교집합 %d (Jaccard %.3f)\n",
            length(sel), length(selMK), length(intersect(sel,selMK)),
            length(intersect(sel,selMK))/length(union(sel,selMK))))
## 이중 제거: 시장 + PC1 둘 다 통제
f1r <- residuals(lm(f1s ~ bmw))                     # PC1 중 시장 직교 성분
fitBOTH <- t(apply(Mu, 2, function(y){ m<-summary(lm(y ~ bmw + f1r))$coefficients; c(m[1,1], m[1,3]) }))
cat(sprintf("  [시장 + PC1잔차 동시통제] n(t>+2)=%d  n(t<-2)=%d  of %d\n",
            sum(fitBOTH[,2] > 2), sum(fitBOTH[,2] < -2), K))
q3 <- list(mk_alpha_t_gt2=sum(fitMK[,2]>2), mk_null_q95=as.numeric(quantile(nullMK,.95)),
           pc1_t_gt2=length(sel), overlap=length(intersect(sel,selMK)),
           both_t_gt2=sum(fitBOTH[,2]>2))

## ── Q4. 생존군 앙상블 (ex-post 상한 진단) ───────────────────────────
cat("\n=== [Q4] 생존군 앙상블 성과 (ex-post 선택 = 상한, PIT 아님) ===\n")
ewx <- function(cols, lab) {
  Mx <- Mu[, cols, drop=FALSE]
  pr <- Return.portfolio(xts(Mx, order.by=dtw),
                         weights=xts(matrix(1/length(cols), n, length(cols)), order.by=dtw),
                         rebalance_on=NA)
  ar <- table.AnnualizedReturns(pr, scale=12); m <- as.numeric(maxDrawdown(pr))
  nn <- length(pr); bb <- bmw[(n-nn+1):n]
  act <- as.numeric(pr) - bb
  bt <- as.numeric(coef(lm(as.numeric(pr) ~ bb))[2])
  cat(sprintf("  %-30s (n_mod=%3d) CAGR=%6.2f%% SR=%5.3f MDD=%5.1f%% Calmar=%5.3f beta=%.3f act=%+.3f%%/m t=%+.2f\n",
              lab, length(cols), 100*ar[1,1], ar[3,1], 100*m, ar[1,1]/m, bt,
              100*mean(act), t.test(act)$statistic))
  list(n=length(cols), cagr=as.numeric(ar[1,1]), sharpe=as.numeric(ar[3,1]), mdd=m,
       calmar=as.numeric(ar[1,1])/m, beta=bt, active_pm=mean(act),
       active_t=as.numeric(t.test(act)$statistic))
}
r_all  <- ewx(seq_len(K), "ALL dedup 85 [base]")
r_mk   <- if (length(selMK) >= 3) ewx(selMK, "시장조정 알파 t>+2 생존군") else NULL
r_pc   <- if (length(sel)   >= 3) ewx(sel,   "PC1-잔차 t>+2 생존군") else NULL
lowb   <- order(beta)[1:20]
r_lowb <- ewx(lowb, "최저 베타 20 [베타 축 대조]")
cat("\n  ★ 판독: 생존군이 '최저 베타 20' 과 성과·베타가 닮으면 그 축은 베타의 다른 이름이다.\n")

R <- list(metric_type="diagnostic_precheck", q1=q1, q3=q3,
          beta_median=median(beta), sel_beta_median=median(beta[sel]),
          sp_residt_beta=cor(fitPC[,2], beta, method="spearman"),
          ens=list(all=r_all, market_adj=r_mk, pc1_resid=r_pc, low_beta20=r_lowb))
write_json(R, file.path(OUT, "p0i_pc1_beta.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
