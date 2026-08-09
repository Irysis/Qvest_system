#!/usr/bin/env Rscript
# =============================================================================
# p0g_recompute.R — P0 헤드라인 수치 단일 패스 재산출 (보고 동반 실측)
#   저장값 echo 가 아니라 패널에서 다시 계산한다. 계약 함수만 사용.
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0g_recompute.log"), split = TRUE)
cat(sprintf("run_at=%s  (재산출 — 저장값 인용 아님)\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
cat(sprintf("[0] 입력 실측: %d months %s..%s | scrap=%d elite=%d\n",
            nrow(sub), min(sub$ym), max(sub$ym), length(scrap_ok), length(elite_ok)))

## ── (1) 중복 → 유효 독립 ─────────────────────────────────────────────
M0 <- as.matrix(sub[, ..scrap_ok])
keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop = FALSE])
M <- M0[rowsc, keepc, drop = FALSE]; ids <- scrap_ok[keepc]
bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
dig <- apply(M, 2, function(x) paste0(sprintf("%.10f", x), collapse = "|"))
C <- cor(M); diag(C) <- 0
hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[, 1] < hi[, 2], , drop = FALSE]
comp <- local({
  par <- seq_len(ncol(M)); fnd <- function(x) { while (par[x] != x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) { a <- fnd(hi[r,1]); b <- fnd(hi[r,2]); if (a != b) par[b] <- a }
  vapply(seq_len(ncol(M)), fnd, integer(1))
})
reps <- vapply(unique(comp), function(g) which(comp == g)[1], integer(1))
cat(sprintf("[1] 중복: 완전커버 %d개 → 고유 수익벡터 %d → corr>=0.999 병합 유효독립 **%d** (축소 %.1f%%) | 최대 중복그룹 %d개\n",
            ncol(M), length(unique(dig)), length(reps), 100*(1-length(reps)/ncol(M)),
            max(table(dig))))
Mu <- M[, reps, drop = FALSE]
A <- Mu - matrix(bmw, nrow(Mu), ncol(Mu))
pc <- prcomp(scale(A), center = FALSE); ev <- pc$sdev^2
cat(sprintf("[1b] dedup 후 구조: PC1 share=%.3f  eff-N=%.2f  active corr median=%.3f\n",
            ev[1]/sum(ev), sum(ev)^2/sum(ev^2), median(cor(A)[upper.tri(cor(A))])))

## ── (2) 성과 (계약 함수만) ───────────────────────────────────────────
ewp <- function(Mx, dd) {
  W <- matrix(1/ncol(Mx), nrow(Mx), ncol(Mx))
  Return.portfolio(xts(Mx, order.by = dd), weights = xts(W, order.by = dd), rebalance_on = NA)
}
stat <- function(pr, lab, bmr = NULL) {
  ar <- table.AnnualizedReturns(pr, scale = 12); m <- as.numeric(maxDrawdown(pr))
  s <- sprintf("  %-16s CAGR=%6.2f%%  SR=%5.3f  MDD=%5.1f%%  Calmar=%5.3f", lab,
               100*ar[1,1], ar[3,1], 100*m, ar[1,1]/m)
  if (!is.null(bmr)) { a <- as.numeric(pr) - bmr[seq_len(length(pr))]
    s <- paste0(s, sprintf("  active=%+.3f%%/m t=%+.3f", 100*mean(a), t.test(a)$statistic)) }
  cat(s, "\n"); invisible(list(cagr=as.numeric(ar[1,1]), sr=as.numeric(ar[3,1]), mdd=m))
}
cat("[2] 성과 (metric_type=diagnostic_precheck):\n")
r_scrap <- stat(ewp(Mu, dtw), "SCRAP EW(85)", bmw)
Me0 <- as.matrix(sub[, ..elite_ok])[rowsc, , drop = FALSE]
oke <- colSums(is.finite(Me0)) == nrow(Me0)
r_elite <- stat(ewp(Me0[, oke, drop = FALSE], dtw), sprintf("ELITE EW(%d)", sum(oke)), bmw)
r_bm <- stat(xts(bmw, order.by = dtw), "BENCHMARK")

## ── (3) 지속성 ───────────────────────────────────────────────────────
cat("[3] 지속성:\n")
h <- floor(nrow(A)/2)
ir1 <- colMeans(A[1:h, ]) / apply(A[1:h, ], 2, sd)
a2 <- colMeans(A[(h+1):nrow(A), ])
qz <- cut(rank(ir1), 4, labels = c("Q1worst","Q2","Q3","Q4best"))
tq <- tapply(a2, qz, function(z) 100*mean(z))
cat(sprintf("  무조건부: IS 4분위별 OOS active(%%/m) = [%s]  spearman=%+.4f\n",
            paste(sprintf("%+.3f", tq), collapse=", "), cor(ir1, a2, method="spearman")))
st <- ifelse(bmw <= -0.05, "DOWN", ifelse(bmw >= 0.05, "SURGE", "FLAT"))
for (s in c("DOWN","FLAT","SURGE")) {
  i1 <- which(st == s & seq_along(st) <= h); i2 <- which(st == s & seq_along(st) > h)
  cat(sprintf("  상태조건부 %-5s (n=%3d): spearman(전반 n=%d, 후반 n=%d) = %+.4f\n",
              s, sum(st==s), length(i1), length(i2),
              cor(colMeans(A[i1,,drop=FALSE]), colMeans(A[i2,,drop=FALSE]), method="spearman")))
}

## ── (4) 잔차 직교 + 음성 대조 ────────────────────────────────────────
f1 <- as.numeric(pc$x[,1]); f1 <- f1/sd(f1)
tv <- apply(A, 2, function(y) summary(lm(y ~ f1))$coefficients[1,3])
set.seed(20260809)
nl <- replicate(50, sum(apply(A[sample(nrow(A)),,drop=FALSE], 2,
                              function(y) summary(lm(y ~ f1))$coefficients[1,3]) > 2))
cat(sprintf("[4] 잔차 직교: n(t>+2)=%d / %d  기대오탐=%.1f  | 음성대조(행셔플 50회) mean=%.1f q95=%.1f\n",
            sum(tv > 2), length(tv), 0.025*length(tv), mean(nl), quantile(nl, .95)))

## ── (5) MDD 천장 (독립 3번째 표본) ───────────────────────────────────
set.seed(777)
mm <- c(); cl <- c()
for (i in 1:300) {
  k <- sample(c(5,10,20,40), 1); pk <- sample(ncol(Mu), k)
  W <- matrix(0, nrow(Mu), ncol(Mu)); W[, pk] <- 1/k
  pr <- Return.portfolio(xts(Mu, order.by=dtw), weights=xts(W, order.by=dtw), rebalance_on=NA)
  ar <- table.AnnualizedReturns(pr, scale=12); m <- as.numeric(maxDrawdown(pr))
  mm <- c(mm, m); cl <- c(cl, as.numeric(ar[1,1])/m)
}
cat(sprintf("[5] MDD 천장 (독립 3차 표본 n=300): MDD min=%.1f%% median=%.1f%% | Calmar max=%.3f q95=%.3f  vs HARD 0.64\n",
            100*min(mm), 100*median(mm), max(cl), quantile(cl,.95)))

write_json(list(metric_type="diagnostic_precheck", run_at=format(Sys.time()),
  n_months=nrow(Mu), n_effective=length(reps),
  scrap=r_scrap, elite=r_elite, bm=r_bm,
  oos_by_is_quartile=as.list(tq), resid_t_gt2=sum(tv>2), null_q95=as.numeric(quantile(nl,.95)),
  mdd_min=min(mm), calmar_max=max(cl)),
  file.path(OUT, "p0g_recompute.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("[done]\n"); sink()
