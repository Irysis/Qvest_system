#!/usr/bin/env Rscript
# =============================================================================
# p0c_persistence.R — P0b 가 드러낸 두 문제를 정면으로 친다.
#
# P0b 실측:
#   ① ELITE 가 4개 시장상태 전부에서 SCRAP 을 지배 (TAIL paired t +3.72, DOWN +4.17)
#      → SCRAP 은 방어적 *상보재*가 아니라 ELITE 의 열화 복제 (active corr 0.766)
#   ② 완전예지 월별 스위치(SR 0.721/MDD 40.0%) < 정적 ELITE(SR 1.126/MDD 24.6%)
#      → 롱온리 모듈 로테이션은 MDD 를 못 잡는다 (β 공유)
#   ③ ★버그: "lossaverse" 오라클이 수익 오라클과 bit-동일 — ifelse(v<0, 3v, v) 는
#      순서보존 변환이라 랭킹 no-op 이었다. 무효 → 진짜 MDD-정렬 오라클로 교체.
#
# ★그러나 ①은 아직 결론이 아니다 — 등급이 **전기간 성과로 부여**됐다면
#   "ELITE 가 낫다"는 동어반복이다. 폐지줍기 명제의 핵심은 정확히 이것:
#   **등급은 앞으로도 유지되는가(persistence)?** 유지 안 되면 '폐지' 라벨은
#   전방 정보가 거의 없고, SCRAP 풀은 핸디캡이 아니다.
#
# 본 스크립트:
#   A. 등급/성과 지속성 (split-sample rank persistence) ← 결정적 관문
#   B. 진짜 MDD-정렬 오라클 (ex-post min-MDD 볼록결합)
#   C. PC1(공통 β 트레이드) 제거 후 잔차 구조 — 직교 폐지 모듈이 존재하는가
#   D. 정적 ELITE/SCRAP 블렌드 곡선 (타이밍 없는 대조)
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
# ── 자립형 재구성 (p0b 가 blend 버그로 중단돼 series.rds 미생성 → p0_panel.rds 에서 직접) ──
P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts_all <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
.ew <- function(ids) {
  M <- as.matrix(sub[, ..ids]); keep <- rowSums(!is.na(M)) >= 3
  W <- !is.na(M[keep, , drop = FALSE]); W <- W / rowSums(W)
  Mz <- M[keep, , drop = FALSE]; Mz[!is.finite(Mz)] <- 0
  Return.portfolio(xts(Mz, order.by = dts_all[keep]),
                   weights = xts(W, order.by = dts_all[keep]), rebalance_on = NA)
}
s_ew <- .ew(scrap_ok); e_ew <- .ew(elite_ok)
J <- na.omit(merge(s_ew, e_ew, xts(sub$bm, order.by = dts_all)))
colnames(J) <- c("scrap", "elite", "bm")
ix_keep <- match(index(J), dts_all)
Ms <- as.matrix(sub[, ..scrap_ok])[ix_keep, , drop = FALSE]
Me <- as.matrix(sub[, ..elite_ok])[ix_keep, , drop = FALSE]
bmv <- as.numeric(J$bm); dts <- index(J); n <- nrow(J)
cat(sprintf("=== [0] INPUT: %d months %s..%s | scrap cols=%d elite cols=%d ===\n",
            n, format(min(dts), "%Y%m"), format(max(dts), "%Y%m"), ncol(Ms), ncol(Me)))
R <- list()
perf <- function(x, lab, quiet = FALSE) {
  ar <- table.AnnualizedReturns(x, scale = 12); mdd <- as.numeric(maxDrawdown(x))
  if (!quiet) cat(sprintf("  %-30s CAGR=%6.2f%%  SR=%5.3f  MDD=%5.1f%%  Calmar=%5.3f\n",
                          lab, 100 * ar[1, 1], ar[3, 1], 100 * mdd, ar[1, 1] / mdd))
  list(cagr = as.numeric(ar[1, 1]), sharpe = as.numeric(ar[3, 1]), mdd = mdd,
       calmar = as.numeric(ar[1, 1]) / mdd)
}
port <- function(M, W, idx = seq_len(nrow(M))) {
  Mz <- M[idx, , drop = FALSE]; Mz[!is.finite(Mz)] <- 0
  Return.portfolio(xts(Mz, order.by = dts[idx]),
                   weights = xts(W[idx, , drop = FALSE], order.by = dts[idx]), rebalance_on = NA)
}

# ═══ [A] 등급 지속성 — 폐지줍기 명제의 결정 관문 ═══════════════════════════
cat("\n=== [A] RANK PERSISTENCE — '폐지' 라벨에 전방 정보가 있는가 ===\n")
ALL <- cbind(Ms, Me)
grp <- c(rep("SCRAP", ncol(Ms)), rep("ELITE", ncol(Me)))
act <- ALL - matrix(bmv, n, ncol(ALL))

# A1. 전기간 등급이 in-sample 인지 확인: 등급별 전기간 active
cat(sprintf("  [A1] 전기간 active mean: SCRAP=%+.3f%%/m  ELITE=%+.3f%%/m  (등급 부여 근거와 동일 표본 = 동어반복 위험)\n",
            100 * mean(colMeans(act[, grp == "SCRAP"], na.rm = TRUE), na.rm = TRUE),
            100 * mean(colMeans(act[, grp == "ELITE"], na.rm = TRUE), na.rm = TRUE)))

# A2. 등급-무관 순수 지속성: trailing 36m 성과 → forward 12m 성과 스피어만 (rolling)
cat("  [A2] trailing-36m 순위 -> forward-12m 순위 스피어만 (등급 라벨 미사용, 전 210 모듈)\n")
rhos <- c(); ns <- c()
for (t in seq(48, n - 12, by = 6)) {
  tw <- act[(t - 35):t, , drop = FALSE]; fw <- act[(t + 1):(t + 12), , drop = FALSE]
  ok <- colSums(is.finite(tw)) >= 30 & colSums(is.finite(fw)) >= 10
  if (sum(ok) < 30) next
  a <- colMeans(tw[, ok, drop = FALSE], na.rm = TRUE) / apply(tw[, ok, drop = FALSE], 2, sd, na.rm = TRUE)
  b <- colMeans(fw[, ok, drop = FALSE], na.rm = TRUE)
  keep <- is.finite(a) & is.finite(b)
  if (sum(keep) < 30) next
  rhos <- c(rhos, cor(a[keep], b[keep], method = "spearman")); ns <- c(ns, sum(keep))
}
cat(sprintf("       n_windows=%d  mean rho=%+.4f  sd=%.4f  t=%+.3f  frac>0=%.3f  median n_mod=%.0f\n",
            length(rhos), mean(rhos), sd(rhos), mean(rhos) / (sd(rhos) / sqrt(length(rhos))),
            mean(rhos > 0), median(ns)))
R$persistence_rolling <- list(n_windows = length(rhos), mean_rho = mean(rhos), sd = sd(rhos),
                              t = mean(rhos) / (sd(rhos) / sqrt(length(rhos))), frac_pos = mean(rhos > 0))

# A3. 하프-스플릿: 전반부 등급화 -> 후반부 성과 (등급이 OOS 에서도 유지되나)
h <- floor(n / 2)
a1 <- colMeans(act[1:h, , drop = FALSE], na.rm = TRUE)
s1 <- apply(act[1:h, , drop = FALSE], 2, sd, na.rm = TRUE)
ir1 <- a1 / s1
a2 <- colMeans(act[(h + 1):n, , drop = FALSE], na.rm = TRUE)
ok <- is.finite(ir1) & is.finite(a2) & colSums(is.finite(act[1:h, ])) >= 36 & colSums(is.finite(act[(h+1):n, ])) >= 36
cat(sprintf("  [A3] half-split (n1=%d n2=%d, %d modules): spearman(IS IR, OOS active)=%+.4f  pearson=%+.4f\n",
            h, n - h, sum(ok), cor(ir1[ok], a2[ok], method = "spearman"), cor(ir1[ok], a2[ok])))
q <- cut(rank(ir1[ok]), 4, labels = c("Q1(worst)", "Q2", "Q3", "Q4(best)"))
tabq <- tapply(a2[ok], q, function(z) 100 * mean(z))
cat("       IS 4분위별 OOS active(%/m): "); print(round(tabq, 3))
R$half_split <- list(n_modules = sum(ok), spearman = cor(ir1[ok], a2[ok], method = "spearman"),
                     oos_by_is_quartile = as.list(tabq))
# ELITE 라벨이 OOS 에서도 유효한가
cat(sprintf("       [label OOS] SCRAP OOS active=%+.3f%%/m  ELITE OOS active=%+.3f%%/m  gap=%+.3f%%\n",
            100 * mean(a2[ok & grp == "SCRAP"]), 100 * mean(a2[ok & grp == "ELITE"]),
            100 * (mean(a2[ok & grp == "ELITE"]) - mean(a2[ok & grp == "SCRAP"]))))
R$label_oos_gap <- as.numeric(mean(a2[ok & grp == "ELITE"]) - mean(a2[ok & grp == "SCRAP"]))

# ═══ [B] 진짜 MDD-정렬 오라클 (ex-post min-MDD 볼록결합) ═══════════════════
cat("\n=== [B] TRUE MDD-ALIGNED ORACLE (ex-post static convex combo, random search) ===\n")
set.seed(20260809)
Msz <- Ms; Msz[!is.finite(Msz)] <- 0
avail <- is.finite(Ms)
best <- list(mdd = 9, calmar = -9)
NTRY <- 4000; K <- 12
for (i in seq_len(NTRY)) {
  pick <- sample(ncol(Ms), K)
  W <- matrix(0, n, ncol(Ms)); W[, pick] <- avail[, pick]
  rs <- rowSums(W); if (any(rs == 0)) next
  W <- W / rs
  pr <- port(Msz, W)
  mdd <- as.numeric(maxDrawdown(pr)); cg <- as.numeric(table.AnnualizedReturns(pr, scale = 12)[1, 1])
  cal <- cg / mdd
  if (mdd < best$mdd) best$mdd <- mdd
  if (cal > best$calmar) { best$calmar <- cal; best$pick <- pick; best$cagr <- cg; best$mdd_at_best <- mdd
                           best$sharpe <- as.numeric(table.AnnualizedReturns(pr, scale = 12)[3, 1]) }
}
cat(sprintf("  random-search %d combos of K=%d over SCRAP (ex-post 선택 = 상한):\n", NTRY, K))
cat(sprintf("    min achievable MDD = %.1f%%   |   best Calmar = %.3f (CAGR %.2f%%, MDD %.1f%%, SR %.3f)\n",
            100 * best$mdd, best$calmar, 100 * best$cagr, 100 * best$mdd_at_best, best$sharpe))
cat(sprintf("    [대조] SCRAP EW MDD=41.6%%  ELITE EW MDD=24.6%%  BM MDD=47.1%%\n"))
R$mdd_oracle <- list(n_try = NTRY, K = K, min_mdd = best$mdd, best_calmar = best$calmar,
                     best_cagr = best$cagr, best_mdd = best$mdd_at_best, best_sharpe = best$sharpe)

# ═══ [C] PC1 제거 후 잔차 구조 ══════════════════════════════════════════════
cat("\n=== [C] PC1 REMOVAL — 직교 폐지 모듈이 존재하는가 ===\n")
A <- act[, grp == "SCRAP", drop = FALSE]
cc <- complete.cases(A)
cat(sprintf("  complete-case months=%d / %d\n", sum(cc), n))
Ac <- scale(A[cc, , drop = FALSE], center = TRUE, scale = FALSE)
pc <- prcomp(Ac, center = FALSE)
ev <- pc$sdev^2
cat(sprintf("  PC1 var share=%.3f  PC2=%.3f  PC3=%.3f\n", ev[1]/sum(ev), ev[2]/sum(ev), ev[3]/sum(ev)))
load1 <- abs(pc$rotation[, 1])
lowpc1 <- order(load1)[1:20]
cat(sprintf("  |PC1 loading| : median=%.4f  low-20 median=%.4f\n", median(load1), median(load1[lowpc1])))
# 저-PC1 20개 EW 의 성과
W <- matrix(0, n, ncol(Ms)); idx_low <- which(grp == "SCRAP")[lowpc1]
W[, idx_low] <- avail[, idx_low]; rs <- rowSums(W); keep <- rs > 0; W[keep, ] <- W[keep, ] / rs[keep]
R$lowpc1_ew <- perf(port(Msz, W, which(keep)), "SCRAP low-PC1 top20 EW")
# PC1 을 회귀로 제거한 잔차 알파
f1 <- pc$x[, 1]
resid_alpha <- apply(Ac, 2, function(y) { m <- lm(y ~ f1); as.numeric(coef(m)[1]) })
resid_t <- apply(Ac, 2, function(y) { m <- lm(y ~ f1); summary(m)$coefficients[1, 3] })
cat(sprintf("  PC1-잔차 알파: mean=%+.4f%%/m  n(t>2)=%d  n(t<-2)=%d  of %d modules\n",
            100 * mean(resid_alpha), sum(resid_t > 2), sum(resid_t < -2), length(resid_t)))
R$pc1_residual <- list(pc1_share = ev[1]/sum(ev), mean_resid_alpha = mean(resid_alpha),
                       n_t_gt2 = sum(resid_t > 2), n_t_lt_neg2 = sum(resid_t < -2), n = length(resid_t))

# ═══ [D] 정적 블렌드 곡선 (타이밍 없는 대조 — 스위치 오라클의 벤치) ══════════
cat("\n=== [D] STATIC BLEND CURVE (ELITE w vs SCRAP 1-w, no timing) ===\n")
Rx <- merge(J$elite, J$scrap)
blend <- list()
for (w in c(0, 0.25, 0.5, 0.75, 1)) {
  Wm <- matrix(c(w, 1 - w), nrow = n, ncol = 2, byrow = TRUE)
  p <- Return.portfolio(Rx, weights = xts(Wm, order.by = dts), rebalance_on = NA)
  blend[[sprintf("w_elite_%03d", round(100 * w))]] <- perf(p, sprintf("blend elite=%.2f", w))
}
R$static_blend <- blend

R$meta <- list(metric_type = "diagnostic_precheck", n_months = n,
               note = "오라클=ex-post 상한(PIT 아님). p0b 의 lossaverse 오라클은 순서보존 no-op 버그로 무효 — 본 스크립트 [B] 가 대체.")
write_json(R, file.path(OUT, "p0c_persistence.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
cat(sprintf("\n[done] -> %s\n", file.path(OUT, "p0c_persistence.json")))
