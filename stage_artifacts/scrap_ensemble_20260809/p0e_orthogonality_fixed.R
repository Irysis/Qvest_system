#!/usr/bin/env Rscript
# =============================================================================
# p0e_orthogonality_fixed.R — p0d [C] 의 두 결함을 고쳐 재측정.
#
# ★결함 1 (퇴화): complete.cases(195 모듈) = 20개월 / 253. n<<p 로 PCA 무의미.
#   → 커버리지 필터 후 공통창 확보로 교체. 커버리지 실측을 먼저 출력한다(가정 금지).
# ★결함 2 (항등식): Ac 를 열-중심화한 뒤 lm(y ~ f1) 의 절편을 '잔차 알파'라 불렀다.
#   중심화하면 mean(y)=0, mean(f1)=0 이므로 절편은 **항상 정확히 0** — 측정이 아니라 산술.
#   실측 증거: 195개 전부 alpha=+0.000, t=+0.00, n(t>2)=0 (기대 오탐 4.9 인데 0 = 사망 신호).
#   → 중심화하지 않은 active 를 종속변수로, PC1 은 별도 표준화 데이터에서 산출해 회귀.
#
# ★그리고 p0/p0b 가 보고한 "PC1 share 0.805 · eff-N 1.5" 도 같은 20개월 표본 산물 →
#   본 스크립트 수치로 대체한다(이전 값 인용 금지).
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0e.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts_all <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
Ms_full <- as.matrix(sub[, ..scrap_ok]); bmv_full <- sub$bm
n0 <- nrow(Ms_full)
cat(sprintf("=== [0] INPUT SHAPE: %d months x %d scrap modules (%s..%s) ===\n",
            n0, ncol(Ms_full), min(sub$ym), max(sub$ym)))

# ── 커버리지 실측 (가정 금지) ──
cov_m <- colSums(is.finite(Ms_full))
cat(sprintf("  module coverage (months): min=%d q25=%.0f median=%.0f q75=%.0f max=%d\n",
            min(cov_m), quantile(cov_m, .25), median(cov_m), quantile(cov_m, .75), max(cov_m)))
cat("  coverage histogram:\n"); print(table(cut(cov_m, c(0, 60, 120, 180, 220, 253), include.lowest = TRUE)))
breadth <- rowSums(is.finite(Ms_full))
cat(sprintf("  month breadth: min=%d median=%.0f max=%d | months with breadth>=150: %d\n",
            min(breadth), median(breadth), max(breadth), sum(breadth >= 150)))

# ── 공통창 선택: 커버리지 상위 모듈 + 그 위 complete case ──
best <- NULL
for (thr in c(253, 250, 240, 230, 220, 200, 180)) {
  keep_c <- which(cov_m >= thr)
  if (length(keep_c) < 30) next
  M <- Ms_full[, keep_c, drop = FALSE]; rows <- complete.cases(M)
  if (sum(rows) < 100) next
  best <- list(thr = thr, cols = keep_c, rows = which(rows))
  cat(sprintf("  [window] cov>=%d -> %d modules x %d complete months\n", thr, length(keep_c), sum(rows)))
  break
}
if (is.null(best)) stop("공통창 확보 실패 — 커버리지 구조 재검토 필요")
cols <- best$cols; rows <- best$rows
Msw <- Ms_full[rows, cols, drop = FALSE]; bmw <- bmv_full[rows]; dtsw <- dts_all[rows]
Aw <- Msw - matrix(bmw, length(rows), length(cols))       # active, 중심화 안 함
cat(sprintf("  ★공통창 확정: %d months x %d modules (%s..%s)\n",
            nrow(Aw), ncol(Aw), format(min(dtsw), "%Y%m"), format(max(dtsw), "%Y%m")))
R <- list(window = list(cov_threshold = best$thr, n_months = nrow(Aw), n_modules = ncol(Aw),
                        start = format(min(dtsw), "%Y%m"), end = format(max(dtsw), "%Y%m")))

# ── [1] 공통인자 구조 (제대로) ──
cat("\n=== [1] COMMON-FACTOR STRUCTURE (fixed window) ===\n")
Az <- scale(Aw)                                            # 표준화 = 상관 PCA
pc <- prcomp(Az, center = FALSE, scale. = FALSE)
ev <- pc$sdev^2; shr <- ev / sum(ev)
cat(sprintf("  PC1=%.3f PC2=%.3f PC3=%.3f PC4=%.3f PC5=%.3f | cum5=%.3f\n",
            shr[1], shr[2], shr[3], shr[4], shr[5], sum(shr[1:5])))
effN <- sum(ev)^2 / sum(ev^2)
cat(sprintf("  eff-N (participation ratio) = %.2f  over %d modules\n", effN, ncol(Aw)))
cg <- cor(Msw); ca <- cor(Aw); ut <- function(m) m[upper.tri(m)]
cat(sprintf("  corr gross  median=%.3f  | corr active median=%.3f  frac>0.8=%.3f\n",
            median(ut(cg)), median(ut(ca)), mean(ut(ca) > 0.8)))
R$structure <- list(pc1 = shr[1], pc2 = shr[2], pc3 = shr[3], cum5 = sum(shr[1:5]),
                    eff_n = effN, corr_active_median = median(ut(ca)))

# ── [2] 잔차 알파 (중심화 항등식 제거) ──
cat("\n=== [2] RESIDUAL ALPHA vs PC1 (no centering of dependent var) ===\n")
f1 <- as.numeric(pc$x[, 1])
f1 <- f1 / sd(f1)
fit <- t(apply(Aw, 2, function(y) {
  m <- summary(lm(y ~ f1))$coefficients
  c(alpha = m[1, 1], t = m[1, 3], beta = m[2, 1])
}))
cat(sprintf("  잔차 알파: mean=%+.4f%%/m  median=%+.4f%%/m  sd=%.4f%%\n",
            100 * mean(fit[, "alpha"]), 100 * median(fit[, "alpha"]), 100 * sd(fit[, "alpha"])))
cat(sprintf("  n(t>+2)=%d  n(t<-2)=%d  of %d   (기대 오탐 @5%% 양측 = %.1f each)\n",
            sum(fit[, "t"] > 2), sum(fit[, "t"] < -2), nrow(fit), 0.025 * nrow(fit)))
# ★ 음성 대조: 라벨 셔플 (같은 파이프라인이 무작위에서 무엇을 뱉는지)
set.seed(20260809)
null_cnt <- replicate(50, {
  yperm <- Aw[sample(nrow(Aw)), , drop = FALSE]
  tt <- apply(yperm, 2, function(y) summary(lm(y ~ f1))$coefficients[1, 3])
  sum(tt > 2)
})
cat(sprintf("  [음성 대조] 행 셔플 50회: n(t>+2) mean=%.1f  q95=%.1f  vs 실측 %d\n",
            mean(null_cnt), quantile(null_cnt, .95), sum(fit[, "t"] > 2)))
R$resid_alpha <- list(mean_pm = mean(fit[, "alpha"]), n_t_gt2 = sum(fit[, "t"] > 2),
                      n_t_lt2 = sum(fit[, "t"] < -2), n = nrow(fit),
                      null_mean = mean(null_cnt), null_q95 = as.numeric(quantile(null_cnt, .95)))
ord <- order(fit[, "t"], decreasing = TRUE)
cat("  상위 8 잔차-알파 모듈 (ex-post, PIT 아님):\n")
for (i in ord[1:8]) cat(sprintf("    %-34s alpha=%+.3f%%/m t=%+.2f beta_PC1=%+.3f\n",
                                colnames(Aw)[i], 100 * fit[i, "alpha"], fit[i, "t"], fit[i, "beta"]))

# ── [3] 국면×모듈 상호작용: trailing 성과가 아닌 축에 정보가 있는가 ──
cat("\n=== [3] REGIME x MODULE INTERACTION — trailing 아닌 축의 정보량 ===\n")
st <- ifelse(bmw <= -0.05, "DOWN", ifelse(bmw >= 0.05, "SURGE", "FLAT"))
cat("  state counts: "); print(table(st))
# 각 모듈의 상태별 active 평균 → 상태 간 산포가 모듈마다 다른가 (= 로테이션 재료)
sm <- sapply(unique(st), function(s) colMeans(Aw[st == s, , drop = FALSE]))
cat("  모듈별 상태-조건부 active(%/m) 요약:\n")
for (s in colnames(sm)) cat(sprintf("    %-6s mean=%+.3f  sd_across_modules=%.3f  range=[%+.3f, %+.3f]\n",
                                    s, 100*mean(sm[, s]), 100*sd(sm[, s]), 100*min(sm[, s]), 100*max(sm[, s])))
# 상태-조건부 순위의 지속성 (전반/후반 분할)
hh <- floor(nrow(Aw) / 2)
pers <- list()
for (s in unique(st)) {
  i1 <- which(st == s & seq_along(st) <= hh); i2 <- which(st == s & seq_along(st) > hh)
  if (length(i1) < 8 || length(i2) < 8) { cat(sprintf("    %-6s n1=%d n2=%d <8 skip\n", s, length(i1), length(i2))); next }
  v1 <- colMeans(Aw[i1, , drop = FALSE]); v2 <- colMeans(Aw[i2, , drop = FALSE])
  rho <- cor(v1, v2, method = "spearman")
  cat(sprintf("    %-6s 상태-조건부 순위 지속성 spearman(전반,후반)=%+.4f  (n1=%d n2=%d)\n", s, rho, length(i1), length(i2)))
  pers[[s]] <- list(rho = rho, n1 = length(i1), n2 = length(i2))
}
R$regime_interaction <- list(state_counts = as.list(table(st)), persistence = pers)

# ── [4] MDD 하한: 롱온리 조합으로 도달 가능한 최소 낙폭 ──
cat("\n=== [4] MDD FLOOR — 롱온리 조합의 구조적 하한 (ex-post, 상한 진단) ===\n")
set.seed(20260809)
Mz <- Msw
res_mdd <- c(); res_cal <- c()
for (i in 1:600) {
  k <- sample(c(5, 10, 20, 40), 1); pick <- sample(ncol(Mz), k)
  W <- matrix(0, nrow(Mz), ncol(Mz)); W[, pick] <- 1 / k
  pr <- Return.portfolio(xts(Mz, order.by = dtsw), weights = xts(W, order.by = dtsw), rebalance_on = NA)
  ar <- table.AnnualizedReturns(pr, scale = 12); m <- as.numeric(maxDrawdown(pr))
  res_mdd <- c(res_mdd, m); res_cal <- c(res_cal, as.numeric(ar[1, 1]) / m)
}
cat(sprintf("  600 random subsets: MDD min=%.1f%% q05=%.1f%% median=%.1f%% max=%.1f%%\n",
            100*min(res_mdd), 100*quantile(res_mdd, .05), 100*median(res_mdd), 100*max(res_mdd)))
cat(sprintf("                      Calmar max=%.3f q95=%.3f median=%.3f  | HARD 문턱 0.64\n",
            max(res_cal), quantile(res_cal, .95), median(res_cal)))
cat(sprintf("  ⇒ 무작위 조합조차 도달 못하는 영역이면 ML 선택으로도 못 간다(선택은 이 분포 안에서만 고른다).\n"))
# 벤치 MDD
bmx <- xts(bmw, order.by = dtsw)
cat(sprintf("  [ref] BM MDD=%.1f%%  | 창 내 SCRAP EW MDD=%.1f%%\n",
            100*as.numeric(maxDrawdown(bmx)),
            100*as.numeric(maxDrawdown(Return.portfolio(xts(Mz, order.by=dtsw),
                 weights=xts(matrix(1/ncol(Mz), nrow(Mz), ncol(Mz)), order.by=dtsw), rebalance_on=NA)))))
R$mdd_floor <- list(n_try = 600, mdd_min = min(res_mdd), mdd_q05 = as.numeric(quantile(res_mdd, .05)),
                    mdd_median = median(res_mdd), calmar_max = max(res_cal),
                    calmar_q95 = as.numeric(quantile(res_cal, .95)), hard_threshold = 0.64)

R$meta <- list(metric_type = "diagnostic_precheck",
               supersedes = "p0_inventory.json 의 PC1 share 0.805 / eff-N 1.5 (20개월 complete-case 산물) 및 p0d_fast.json 의 [C] 전체(중심화 항등식) — 인용 금지",
               note = "ex-post 선택 항목은 상한 진단 전용(PIT 아님).")
write_json(R, file.path(OUT, "p0e_orthogonality.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
cat("\n[done]\n"); sink()
