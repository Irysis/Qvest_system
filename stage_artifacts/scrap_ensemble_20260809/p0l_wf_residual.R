#!/usr/bin/env Rscript
# =============================================================================
# p0l_wf_residual.R — 살아남은 축(PC1-잔차 직교 알파)의 PIT 워크포워드 회수율
#
# 확정 사실:
#   · 잔차 알파 실재 (16/85, 블록귀무 b=12 max 15 < 실측 16, p<0.001)
#   · 그러나 ex-post 완전예지 선택조차 앙상블 active t=+1.99 (2.0 미달)
#   · 생존군은 저베타 아님 (베타 median 0.836 = 75분위) — 워크플로 A3(저 PC1-베타)와 표적 상이
#
# 본 검정: **PIT 워크포워드**로 같은 축을 골랐을 때 상한의 몇 %를 회수하는가.
#   각 시점 t 에서 t 까지 데이터로만 PC1 추정 → 잔차 알파 t 통계 → 상위 K 선택 → t+1 보유.
#   ex-post 상한과 나란히 놓아 '신호 실재 → 수확 가능' 전이를 직접 측정한다.
#
# 대조:
#   · base = dedup 85 EW (동일 월 집합)
#   · 무작위 K 선택 (음성 대조) — 선택 규칙이 무작위보다 나은가
#   · ex-post 상한 (같은 창)
# metric_type = diagnostic_precheck (자본 판정 아님 · screen-tier)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0l_wf.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
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
A <- Mu - matrix(bmw, n, K)
IS0 <- 60L
cat(sprintf("=== [0] %d months x %d modules | IS 최초 %d개월 → OOS %d개월 (%s..%s) ===\n",
            n, K, IS0, n-IS0, format(dtw[IS0+1],"%Y-%m"), format(dtw[n],"%Y-%m")))

## ── 워크포워드 선택 (PIT: t 까지 정보만) ─────────────────────────────
sel_resid <- function(kk) {
  W <- matrix(0, n, K)
  for (t in IS0:(n-1)) {
    Ais <- A[1:t, , drop=FALSE]
    pc  <- prcomp(scale(Ais), center = FALSE)          # ★ t 까지 데이터로만 PC1 추정
    f1  <- as.numeric(pc$x[,1]); f1 <- f1/sd(f1)
    tv  <- apply(Ais, 2, function(y) summary(lm(y ~ f1))$coefficients[1,3])
    pick <- order(tv, decreasing = TRUE)[1:kk]
    W[t+1, pick] <- 1/kk                                # t 선택 → t+1 보유
  }
  W
}
sel_random <- function(kk, seed) {
  set.seed(seed); W <- matrix(0, n, K)
  for (t in IS0:(n-1)) W[t+1, sample(K, kk)] <- 1/kk
  W
}
sel_expost <- function(kk) {                            # 상한 (PIT 아님)
  pc <- prcomp(scale(A), center=FALSE); f1 <- as.numeric(pc$x[,1]); f1 <- f1/sd(f1)
  tv <- apply(A, 2, function(y) summary(lm(y ~ f1))$coefficients[1,3])
  pick <- order(tv, decreasing=TRUE)[1:kk]
  W <- matrix(0, n, K); W[(IS0+1):n, pick] <- 1/kk; W
}
sel_ew <- function() { W <- matrix(0, n, K); W[(IS0+1):n, ] <- 1/K; W }

run <- function(W, lab, base_r = NULL, quiet = FALSE) {
  rows <- (IS0+1):n
  Mz <- Mu[rows, , drop=FALSE]
  pr <- Return.portfolio(xts(Mz, order.by=dtw[rows]),
                         weights=xts(W[rows, , drop=FALSE], order.by=dtw[rows]), rebalance_on=NA)
  nn <- length(pr); rr <- tail(rows, nn)
  ar <- table.AnnualizedReturns(pr, scale=12); mdd <- as.numeric(maxDrawdown(pr))
  act <- as.numeric(pr) - bmw[rr]
  # 회전율: 월별 |Δw| 합 (연율)
  dW <- abs(W[rr, , drop=FALSE] - rbind(0, W[head(rr,-1), , drop=FALSE]))
  turn <- 12 * mean(rowSums(dW)) / 2
  out <- list(lab=lab, n=nn, cagr=as.numeric(ar[1,1]), sharpe=as.numeric(ar[3,1]),
              mdd=mdd, calmar=as.numeric(ar[1,1])/mdd, active_pm=mean(act), turnover=turn,
              series=as.numeric(pr), rows=rr)
  if (!is.null(base_r)) {
    d <- as.numeric(pr) - base_r
    m <- lm(d ~ 1); se <- sqrt(NeweyWest(m, lag=3, prewhite=FALSE))[1,1]
    out$paired_t_nw3 <- as.numeric(coef(m)[1]/se); out$paired_pm <- mean(d)
  }
  if (!quiet) cat(sprintf("  %-30s CAGR=%6.2f%% SR=%5.3f MDD=%5.1f%% Calmar=%5.3f act=%+.3f%%/m TO=%3.0f%% %s\n",
      lab, 100*out$cagr, out$sharpe, 100*out$mdd, out$calmar, 100*out$active_pm, 100*out$turnover,
      if (!is.null(out$paired_t_nw3)) sprintf("| paired vs base %+.3f%%/m t_NW3=%+.3f", 100*out$paired_pm, out$paired_t_nw3) else ""))
  out
}

cat("\n=== [1] base (OOS 창, dedup 85 EW) ===\n")
b <- run(sel_ew(), "BASE EW85")
cat("\n=== [2] 잔차-알파 워크포워드 선택 (PIT) — K 전량 보고 ===\n")
res <- list(); for (kk in c(10, 20, 30)) res[[paste0("wf_K", kk)]] <- run(sel_resid(kk), sprintf("WF resid-alpha K=%d", kk), b$series)
cat("\n=== [3] 음성 대조 — 무작위 K 선택 (동일 회전 구조) ===\n")
rnd <- list()
for (kk in c(10, 20, 30)) {
  ts <- sapply(1:5, function(s) run(sel_random(kk, 1000+s), "", b$series, quiet=TRUE)$paired_t_nw3)
  cat(sprintf("  %-30s paired t_NW3 5시드: [%s]  median=%+.3f\n",
              sprintf("RANDOM K=%d", kk), paste(sprintf("%+.2f", ts), collapse=", "), median(ts)))
  rnd[[paste0("rand_K", kk)]] <- as.list(setNames(ts, paste0("seed", 1:5)))
}
cat("\n=== [4] ex-post 상한 (PIT 아님 — 회수율 분모) ===\n")
exp_ <- list(); for (kk in c(10, 20, 30)) exp_[[paste0("ex_K", kk)]] <- run(sel_expost(kk), sprintf("EX-POST ceiling K=%d", kk), b$series)

cat("\n=== [5] 회수율 = PIT 워크포워드 / ex-post 상한 ===\n")
for (kk in c(10, 20, 30)) {
  w <- res[[paste0("wf_K", kk)]]; e <- exp_[[paste0("ex_K", kk)]]
  rec <- if (abs(e$paired_pm) > 1e-12) w$paired_pm / e$paired_pm else NA
  cat(sprintf("  K=%-3d  WF paired %+.3f%%/m (t %+.2f)  |  상한 %+.3f%%/m (t %+.2f)  |  회수율 %s\n",
              kk, 100*w$paired_pm, w$paired_t_nw3, 100*e$paired_pm, e$paired_t_nw3,
              if (is.na(rec)) "NA" else sprintf("%.1f%%", 100*rec)))
}
cat("\n  ★ 판독: 회수율이 0 근방이면 '신호 실재'와 '수확 가능'은 다른 얘기다 (전이 벽).\n")
cat("     무작위 대조와 구별 안 되면 선택 규칙 자체가 작동 안 한 것.\n")

strip <- function(x) { x$series <- NULL; x$rows <- NULL; x }
write_json(list(metric_type="diagnostic_precheck", is_months=IS0, oos_months=n-IS0,
                base=strip(b), wf=lapply(res, strip), random=rnd, expost=lapply(exp_, strip)),
           file.path(OUT,"p0l_wf_residual.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
