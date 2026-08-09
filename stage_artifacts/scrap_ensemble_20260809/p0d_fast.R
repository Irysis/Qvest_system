#!/usr/bin/env Rscript
# p0d_fast.R — p0c 의 결정 관문만 분리 (랜덤서치 [B] 제외). 즉답용.
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0d_fast.log"), split = TRUE)

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
J <- na.omit(merge(.ew(scrap_ok), .ew(elite_ok), xts(sub$bm, order.by = dts_all)))
colnames(J) <- c("scrap", "elite", "bm")
ix <- match(index(J), dts_all)
Ms <- as.matrix(sub[, ..scrap_ok])[ix, , drop = FALSE]
Me <- as.matrix(sub[, ..elite_ok])[ix, , drop = FALSE]
bmv <- as.numeric(J$bm); dts <- index(J); n <- nrow(J)
cat(sprintf("=== INPUT: %d months %s..%s | scrap=%d elite=%d ===\n", n,
            format(min(dts), "%Y%m"), format(max(dts), "%Y%m"), ncol(Ms), ncol(Me)))
R <- list()
ALL <- cbind(Ms, Me); grp <- c(rep("SCRAP", ncol(Ms)), rep("ELITE", ncol(Me)))
act <- ALL - matrix(bmv, n, ncol(ALL))

cat("\n=== [A] RANK PERSISTENCE — '폐지' 라벨에 전방 정보가 있는가 ===\n")
rhos <- c(); ns <- c()
for (t in seq(48, n - 12, by = 6)) {
  tw <- act[(t - 35):t, , drop = FALSE]; fw <- act[(t + 1):(t + 12), , drop = FALSE]
  ok <- colSums(is.finite(tw)) >= 30 & colSums(is.finite(fw)) >= 10
  if (sum(ok) < 30) next
  a <- colMeans(tw[, ok, drop = FALSE], na.rm = TRUE) / apply(tw[, ok, drop = FALSE], 2, sd, na.rm = TRUE)
  b <- colMeans(fw[, ok, drop = FALSE], na.rm = TRUE)
  k <- is.finite(a) & is.finite(b); if (sum(k) < 30) next
  rhos <- c(rhos, cor(a[k], b[k], method = "spearman")); ns <- c(ns, sum(k))
}
tstat <- mean(rhos) / (sd(rhos) / sqrt(length(rhos)))
cat(sprintf("  [A2] rolling trailing36m-IR -> forward12m: n_win=%d  mean rho=%+.4f  sd=%.4f  t=%+.3f  frac>0=%.3f  med n_mod=%.0f\n",
            length(rhos), mean(rhos), sd(rhos), tstat, mean(rhos > 0), median(ns)))
R$persistence <- list(n_windows = length(rhos), mean_rho = mean(rhos), sd = sd(rhos),
                      t = tstat, frac_pos = mean(rhos > 0))

h <- floor(n / 2)
ir1 <- colMeans(act[1:h, , drop = FALSE], na.rm = TRUE) / apply(act[1:h, , drop = FALSE], 2, sd, na.rm = TRUE)
a2  <- colMeans(act[(h + 1):n, , drop = FALSE], na.rm = TRUE)
ok <- is.finite(ir1) & is.finite(a2) & colSums(is.finite(act[1:h, ])) >= 36 & colSums(is.finite(act[(h+1):n, ])) >= 36
cat(sprintf("  [A3] half-split n1=%d n2=%d (%d mod): spearman(IS IR, OOS act)=%+.4f  pearson=%+.4f\n",
            h, n - h, sum(ok), cor(ir1[ok], a2[ok], method = "spearman"), cor(ir1[ok], a2[ok])))
qq <- cut(rank(ir1[ok]), 4, labels = c("Q1worst", "Q2", "Q3", "Q4best"))
tabq <- tapply(a2[ok], qq, function(z) 100 * mean(z))
cat("       IS 4분위별 OOS active(%/m): "); print(round(tabq, 3))
gap <- mean(a2[ok & grp == "ELITE"]) - mean(a2[ok & grp == "SCRAP"])
cat(sprintf("  [A4] 라벨 OOS 유효성: SCRAP=%+.3f%%/m  ELITE=%+.3f%%/m  gap=%+.3f%%/m (=%.2f%%/yr)\n",
            100 * mean(a2[ok & grp == "SCRAP"]), 100 * mean(a2[ok & grp == "ELITE"]), 100 * gap, 100 * gap * 12))
R$half_split <- list(n = sum(ok), spearman = cor(ir1[ok], a2[ok], method = "spearman"),
                     oos_by_quartile = as.list(tabq), label_oos_gap_pm = gap)

cat("\n=== [C] PC1 REMOVAL — 직교 폐지 모듈이 존재하는가 ===\n")
A <- act[, grp == "SCRAP", drop = FALSE]; cc <- complete.cases(A)
cat(sprintf("  complete-case months=%d/%d\n", sum(cc), n))
Ac <- scale(A[cc, , drop = FALSE], center = TRUE, scale = FALSE)
pc <- prcomp(Ac, center = FALSE); ev <- pc$sdev^2
cat(sprintf("  PC var share: PC1=%.3f PC2=%.3f PC3=%.3f  cum3=%.3f\n",
            ev[1]/sum(ev), ev[2]/sum(ev), ev[3]/sum(ev), sum(ev[1:3])/sum(ev)))
f1 <- pc$x[, 1]
co <- t(apply(Ac, 2, function(y) { m <- summary(lm(y ~ f1))$coefficients; c(m[1,1], m[1,3]) }))
colnames(co) <- c("alpha", "t")
cat(sprintf("  PC1-잔차 알파: mean=%+.4f%%/m  n(t>+2)=%d  n(t<-2)=%d  of %d  (기대 오탐 @5%%: %.1f)\n",
            100 * mean(co[, "alpha"]), sum(co[, "t"] > 2), sum(co[, "t"] < -2), nrow(co), 0.025 * nrow(co)))
top <- order(co[, "t"], decreasing = TRUE)[1:10]
cat("  상위 10 잔차-알파 모듈:\n")
for (i in top) cat(sprintf("    %-34s alpha=%+.3f%%/m  t=%+.2f\n",
                           colnames(A)[i], 100 * co[i, "alpha"], co[i, "t"]))
R$pc1 <- list(pc1_share = ev[1]/sum(ev), n_t_gt2 = sum(co[, "t"] > 2), n_t_lt2 = sum(co[, "t"] < -2),
              n = nrow(co), expected_fp = 0.025 * nrow(co),
              top10 = as.list(setNames(round(co[top, "t"], 3), colnames(A)[top])))

# 저-PC1 부하 20개 EW
Msz <- Ms; Msz[!is.finite(Msz)] <- 0; avail <- is.finite(Ms)
mkperf <- function(cols, lab) {
  W <- matrix(0, n, ncol(Ms)); W[, cols] <- avail[, cols]
  rs <- rowSums(W); keep <- rs > 0; W[keep, ] <- W[keep, ] / rs[keep]
  pr <- Return.portfolio(xts(Msz[keep, , drop = FALSE], order.by = dts[keep]),
                         weights = xts(W[keep, , drop = FALSE], order.by = dts[keep]), rebalance_on = NA)
  ar <- table.AnnualizedReturns(pr, scale = 12); mdd <- as.numeric(maxDrawdown(pr))
  bmk <- as.numeric(J$bm)[keep]; a <- as.numeric(pr) - bmk[seq_len(length(pr))]
  cat(sprintf("  %-30s CAGR=%6.2f%% SR=%5.3f MDD=%5.1f%% Calmar=%5.3f act=%+.3f%%/m t=%+.2f\n",
              lab, 100*ar[1,1], ar[3,1], 100*mdd, ar[1,1]/mdd, 100*mean(a), t.test(a)$statistic))
  list(cagr=as.numeric(ar[1,1]), sharpe=as.numeric(ar[3,1]), mdd=mdd, calmar=as.numeric(ar[1,1])/mdd,
       active_pm=mean(a), active_t_plain=as.numeric(t.test(a)$statistic))
}
cat("\n  --- 잔차-직교 하위풀 성과 (ex-post 선택 = 상한 진단, PIT 아님) ---\n")
load1 <- abs(pc$rotation[, 1])
R$lowpc1_20 <- mkperf(order(load1)[1:20], "low-PC1 |load| top20 EW")
R$residalpha_20 <- mkperf(order(co[, "t"], decreasing = TRUE)[1:20], "resid-alpha t top20 EW [ex-post]")
R$all_scrap <- mkperf(seq_len(ncol(Ms)), "ALL SCRAP EW [ref]")

cat("\n=== [D] STATIC BLEND (no timing) ===\n")
Rx <- merge(J$elite, J$scrap)
bl <- list()
for (w in c(0, 0.25, 0.5, 0.75, 1)) {
  Wm <- matrix(c(w, 1 - w), nrow = n, ncol = 2, byrow = TRUE)
  p <- Return.portfolio(Rx, weights = xts(Wm, order.by = dts), rebalance_on = NA)
  ar <- table.AnnualizedReturns(p, scale = 12); mdd <- as.numeric(maxDrawdown(p))
  cat(sprintf("  elite=%.2f  CAGR=%6.2f%% SR=%5.3f MDD=%5.1f%% Calmar=%5.3f\n",
              w, 100*ar[1,1], ar[3,1], 100*mdd, ar[1,1]/mdd))
  bl[[sprintf("w%03d", round(100*w))]] <- list(sharpe=as.numeric(ar[3,1]), mdd=mdd, calmar=as.numeric(ar[1,1])/mdd)
}
R$blend <- bl
R$meta <- list(metric_type = "diagnostic_precheck", n_months = n,
               note = "잔차-알파 top20 은 ex-post 선택(PIT 아님) — 상한 진단 전용, 판정 아님.")
write_json(R, file.path(OUT, "p0d_fast.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
cat("\n[done]\n"); sink()
