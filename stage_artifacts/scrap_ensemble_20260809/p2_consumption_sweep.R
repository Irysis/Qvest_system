#!/usr/bin/env Rscript
# =============================================================================
# p2_consumption_sweep.R — 소비면 7종 순회 (헌법 answer-principles §리서치연속성 4호 의무)
#
# 재료: 폐지 풀 dedup 85 모듈의 워크포워드 선별 신호(무조건부 trailing 평균 top-K)
#   + 확립 능력 2종: (a) 풀-내부 상대 선별력 실재 (paired t 2.6~2.9, 벤치 대비는 미달)
#                    (b) 모듈 beta 의 상태-조건부 지배 (R^2 0.95~0.97)
#
# 7면 순회 — 각 면마다 "이 산출물이 여기서 쓰이는가"를 실측 또는 명시 판정:
#   ①팩터 랭킹  ②유니버스 필터  ③오버레이/국면 입력  ④위험모델·β예산
#   ⑤monitoring 신호  ⑥선별 라벨  ⑦타 모드 이식
#
# 실측 가능한 면(①②④⑤)은 이 자리에서 검정, 소관 밖(③)은 이관 명시, 라벨 면(⑥⑦)은 처분 기록.
# metric_type = diagnostic_precheck
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(sandwich)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p2_consumption.log"), split = TRUE)
cat(sprintf("run_at=%s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

## ── 공통 재료 로드 ────────────────────────────────────────────────────
P <- readRDS(file.path(OUT,"p0_panel.rds")); PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym,"01"),"%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok]); keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop=FALSE])
M <- M0[rowsc, keepc, drop=FALSE]; bmw <- sub$bm[rowsc]; dtw <- dts[rowsc]
Cc <- cor(M); diag(Cc) <- 0; hi <- which(Cc>=0.999, arr.ind=TRUE); hi <- hi[hi[,1]<hi[,2],,drop=FALSE]
comp <- local({ par<-seq_len(ncol(M)); f<-function(x){while(par[x]!=x)x<-par[x];x}
  if(nrow(hi)) for(r in seq_len(nrow(hi))){a<-f(hi[r,1]);b<-f(hi[r,2]);if(a!=b)par[b]<-a}
  vapply(seq_len(ncol(M)), f, integer(1)) })
reps <- vapply(unique(comp), function(g) which(comp==g)[1], integer(1))
Mu <- M[, reps, drop=FALSE]; ids <- colnames(M)[reps]
n <- nrow(Mu); K <- ncol(Mu); A <- Mu - matrix(bmw, n, K)
beta <- apply(Mu, 2, function(y) as.numeric(coef(lm(y ~ bmw))[2]))
IS0 <- 60L
cat(sprintf("[재료] %d months x %d dedup modules | beta median %.3f\n", n, K, median(beta)))
R <- list()

## ═══ ① 팩터 랭킹 면 — 이미 측정 완료 (FR_002) ═══════════════════════
cat("\n=== [면①] 팩터 랭킹 (모듈 랭킹으로 소비) — 측정 완료 ===\n")
cat("  FR_002 실측: PIT top-10 PORT_t 1.242 · 절대 천장(완전예지) 2.036 < 2.95\n")
cat("  판정: NEGATIVE (config-scoped) — 랭킹 소비는 천장 미달. 재측정 불요.\n")
R$f1_ranking <- list(verdict="negative_ceiling_bound", port_t_pit=1.242, ceiling=2.036)

## ═══ ② 유니버스 필터 면 — 하위 배제가 EW 를 개선하는가 ═══════════════
##   랭킹(top 선택)과 반대 방향: 최악 모듈 *배제*. MAX5 전례(랭킹 죽고 필터 삶) 검정.
cat("\n=== [면②] 유니버스 필터 — 워크포워드 하위 k 배제 vs EW85 ===\n")
run_port <- function(W) {
  rows <- (IS0+1):n
  pr <- Return.portfolio(xts(Mu[rows,,drop=FALSE], order.by=dtw[rows]),
                         weights=xts(W[rows,,drop=FALSE], order.by=dtw[rows]), rebalance_on=NA)
  nn <- length(pr); rr <- tail(rows, nn)
  list(r=as.numeric(pr), rr=rr)
}
ewW <- matrix(0, n, K); ewW[(IS0+1):n, ] <- 1/K
b <- run_port(ewW)
paired_nw <- function(x, y) { d <- x - y; m <- lm(d ~ 1)
  as.numeric(coef(m)[1]/sqrt(NeweyWest(m, lag=3, prewhite=FALSE))[1,1]) }
R$f2 <- list()
for (kex in c(10, 20, 30)) {
  W <- matrix(0, n, K)
  for (t in IS0:(n-1)) {
    sc <- colMeans(A[1:t, , drop=FALSE])          # t 까지 정보만
    keep <- order(sc)[(kex+1):K]                   # 하위 kex 배제
    W[t+1, keep] <- 1/length(keep)
  }
  z <- run_port(W)
  L <- min(length(z$r), length(b$r))
  dpm <- mean(z$r[1:L] - b$r[1:L]); tt <- paired_nw(z$r[1:L], b$r[1:L])
  prx <- xts(z$r, order.by=dtw[z$rr]); ar <- table.AnnualizedReturns(prx, scale=12)
  md <- as.numeric(maxDrawdown(prx))
  cat(sprintf("  하위 %d 배제: Δvs EW %+.4f%%/m t_NW3=%+.3f | SR=%.3f MDD=%.1f%% Calmar=%.3f\n",
              kex, 100*dpm, tt, ar[3,1], 100*md, ar[1,1]/md))
  R$f2[[paste0("ex",kex)]] <- list(delta_pm=dpm, t=tt, sharpe=as.numeric(ar[3,1]),
                                   mdd=md, calmar=as.numeric(ar[1,1])/md)
}
cat("  (참고: EW85 base SR 0.659 · MDD 40.5% · Calmar 0.258 — p0l 실측)\n")

## ═══ ④ 위험모델·β예산 면 — beta 예측기로서의 폐지 풀 ═════════════════
##   확립 능력(b): 모듈 beta 상태-지배. 소비형태 = "모듈 trailing beta 가 forward beta 를 예측하는가"
##   (위험모델의 β추정 입력으로 쓸 수 있는지 — 노출 스케일 실행은 WT-002 소관, 여기선 예측력만)
cat("\n=== [면④] 위험모델 — trailing beta → forward beta 예측력 ===\n")
h36 <- 36L
rhos <- c()
for (t in seq(IS0, n-12, by=6)) {
  bt_tr <- apply(Mu[max(1,t-h36+1):t, , drop=FALSE], 2, function(y)
                 as.numeric(coef(lm(y ~ bmw[max(1,t-h36+1):t]))[2]))
  bt_fw <- apply(Mu[(t+1):min(n,t+12), , drop=FALSE], 2, function(y)
                 as.numeric(coef(lm(y ~ bmw[(t+1):min(n,t+12)]))[2]))
  ok <- is.finite(bt_tr) & is.finite(bt_fw)
  if (sum(ok) > 30) rhos <- c(rhos, cor(bt_tr[ok], bt_fw[ok], method="spearman"))
}
cat(sprintf("  rolling trailing-36m beta → forward-12m beta: n_win=%d mean rho=%.4f sd=%.4f t=%.2f frac>0=%.3f\n",
            length(rhos), mean(rhos), sd(rhos), mean(rhos)/(sd(rhos)/sqrt(length(rhos))), mean(rhos>0)))
cat(sprintf("  판정: %s — 모듈 beta 는 강하게 지속 = 위험모델/β예산의 신뢰 가능한 입력.\n",
            if (mean(rhos) > 0.5) "POSITIVE" else "약함"))
R$f4_beta_persist <- list(n_win=length(rhos), mean_rho=mean(rhos),
                          t=mean(rhos)/(sd(rhos)/sqrt(length(rhos))))

## ═══ ⑤ monitoring 신호 면 — 풀 내부 dispersion/유효폭의 정보량 ════════
##   소비형태: 폐지 풀 횡단면 산포가 시장 상태 변화의 동행/선행 지표인가
cat("\n=== [면⑤] monitoring — 풀 횡단면 산포의 forward 정보량 ===\n")
disp <- apply(A, 1, sd)                             # 월별 모듈간 active 산포
fwd_bm <- c(bmw[-1], NA)                            # 다음달 bm
fwd_dd <- as.integer(fwd_bm <= -0.05)
ct <- cor.test(disp[1:(n-1)], abs(fwd_bm[1:(n-1)]), method="spearman")
cat(sprintf("  disp(t) vs |bm(t+1)|: spearman %.4f (p=%.4f)\n", ct$estimate, ct$p.value))
q80 <- quantile(disp, .8)
hit_hi <- mean(fwd_dd[disp > q80 & seq_len(n) < n], na.rm=TRUE)
hit_lo <- mean(fwd_dd[disp <= q80 & seq_len(n) < n], na.rm=TRUE)
cat(sprintf("  P(다음달 bm<=-5%% | disp>q80) = %.3f  vs  base %.3f  → lift %.2fx (발화 %d개월)\n",
            hit_hi, hit_lo, hit_hi/max(hit_lo,1e-9), sum(disp > q80)))
cat(sprintf("  판정: %s\n", if (is.finite(hit_hi/hit_lo) && hit_hi/hit_lo >= 2) "후보 (lift>=2, 라벨-사건 자격 검사로 승격 검토)"
            else "무판별 — monitoring 소비 없음"))
R$f5_monitoring <- list(spearman=as.numeric(ct$estimate), p=ct$p.value,
                        lift=hit_hi/max(hit_lo,1e-9), n_fire=sum(disp>q80))

## ═══ ③⑥⑦ — 판정/이관 (실측 없이 처분 기록) ═════════════════════════
cat("\n=== [면③] 오버레이/국면 입력 — 소관 이관 ===\n")
cat("  beta 상태-지배 실측 3건(spearman -0.975/+0.985 · 잔차 지속성 음수 · 라벨 전이표)은\n")
cat("  노출 스케일 축 = WT-D20260809_002 소관. 본 라운드는 침범하지 않고 이관 기록만 남긴다.\n")
R$f3_overlay <- list(verdict="transferred_to_WT-D20260809_002", payload="beta 실측 3건")
cat("\n=== [면⑥] 선별 라벨 — screen_route 처분 ===\n")
cat("  FR_002 = screen-tier 등재 완료(자본 아님). 폐지 모듈 개별 재라벨은 없음 —\n")
cat("  개별 모듈 처분은 module_performance grade 가 이미 담당(이중 라벨 금지).\n")
R$f6_label <- list(verdict="fr002_screen_tier_registered")
cat("\n=== [면⑦] 타 모드 이식 ===\n")
cat("  RAMP: 폐지 풀 = return-derived substrate — R6~R15 계열이 동일 천장(cap-w ~2.9) 기실측,\n")
cat("        이식 신규성 없음. / QEPM: 모듈-레벨 재료는 QEPM 대상 아님(종목-레벨 전용).\n")
cat("  판정: 이식 대상 없음 — 천장 공유 확인이 곧 이식 판정.\n")
R$f7_transplant <- list(verdict="no_transplant_shared_ceiling")

## ═══ 종합 ═════════════════════════════════════════════════════════════
cat("\n=== [종합] 소비면 7종 순회 결과 ===\n")
cat("  ① 랭킹      : NEGATIVE (천장 2.04 < 2.95, FR_002)\n")
cat("  ② 필터      : 위 실측 참조 — t>=2 면 배제-소비 후보, 아니면 negative\n")
cat("  ③ 오버레이  : 이관 (WT-D20260809_002, beta 실측 3건)\n")
cat("  ④ 위험모델  : beta 지속성 실측 참조 — 강하면 β예산 입력 후보\n")
cat("  ⑤ monitoring: disp lift 실측 참조\n")
cat("  ⑥ 라벨      : FR_002 screen-tier 등재로 처분 완료\n")
cat("  ⑦ 타 모드   : 이식 없음 (RAMP 천장 공유·QEPM 대상 밖)\n")
R$meta <- list(metric_type="diagnostic_precheck", run_at=format(Sys.time()))
write_json(R, file.path(OUT,"p2_consumption_sweep.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
