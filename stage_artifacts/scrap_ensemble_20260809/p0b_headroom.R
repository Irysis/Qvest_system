#!/usr/bin/env Rscript
# =============================================================================
# p0b_headroom.R — P0 후속: "폐지 앙상블에 실제로 어떤 상금이 있는가"
#
# P0 이 던진 문제:
#   ① SCRAP active PC1 share=0.805, eff-N=1.5 → 195모듈이 사실상 1.5개 베팅
#   ② ORACLE top-10(수익 기준) SR 0.663 vs EW 0.628 → 완전예지에도 헤드룸 ~0
#      ⇒ 단, 그 오라클은 *수익* 정렬이라 사용자 목표축(MDD)과 불일치 = 오라클 오설정
#   ③ SCRAP = 조건부 방어 트레이드 (mild-down 월 active +1.235%, frac>0=0.995)
#
# 본 스크립트가 답할 것:
#   A. ELITE vs SCRAP 조건부 프로파일 (상보적인가 = 로테이션 상금 실재하는가)
#   B. MDD-정렬 오라클 (calmar 목표 완전예지 상한)
#   C. 2-state 스위치 오라클 (ELITE<->SCRAP) 상한
#   D. required_effect_size — 그 상금을 잡으려면 예측기가 얼마나 정확해야 하는가
#   ★ active t 는 P0 에서 길이 불일치 경고 발생 → 본 스크립트는 인덱스 정합 후 재측정
#
# metric_type = diagnostic_precheck (자본 판정 아님)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok; start_ym <- P$start_ym

sub <- PAN[ym >= start_ym & is.finite(bm)]
setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
cat(sprintf("=== [0] INPUT: %d months %s..%s | scrap=%d elite=%d ===\n",
            nrow(sub), min(sub$ym), max(sub$ym), length(scrap_ok), length(elite_ok)))

# ── 동일가중 합성 (계약: Return.portfolio) + 인덱스 정합 반환 ──
ew_series <- function(ids) {
  M <- as.matrix(sub[, ..ids])
  keep <- rowSums(!is.na(M)) >= 3
  W <- !is.na(M[keep, , drop = FALSE]); W <- W / rowSums(W)
  Mz <- M[keep, , drop = FALSE]; Mz[!is.finite(Mz)] <- 0
  Rx <- xts(Mz, order.by = dts[keep]); Wx <- xts(W, order.by = dts[keep])
  pr <- Return.portfolio(Rx, weights = Wx, rebalance_on = NA)
  colnames(pr) <- "r"; pr
}
s_ew <- ew_series(scrap_ok); e_ew <- ew_series(elite_ok)
bm_x <- xts(sub$bm, order.by = dts); colnames(bm_x) <- "bm"
J <- na.omit(merge(s_ew, e_ew, bm_x))          # ★ 인덱스 정합 병합 (P0 경고 원인 제거)
colnames(J) <- c("scrap", "elite", "bm")
cat(sprintf("[align] joined months=%d (%s..%s)\n", nrow(J),
            format(min(index(J)), "%Y%m"), format(max(index(J)), "%Y%m")))

perf <- function(x, lab) {
  ar <- table.AnnualizedReturns(x, scale = 12); mdd <- as.numeric(maxDrawdown(x))
  cat(sprintf("  %-24s CAGR=%6.2f%%  SR=%5.3f  MDD=%5.1f%%  Calmar=%5.3f\n",
              lab, 100 * ar[1, 1], ar[3, 1], 100 * mdd, ar[1, 1] / mdd))
  list(cagr = as.numeric(ar[1, 1]), sharpe = as.numeric(ar[3, 1]),
       mdd = mdd, calmar = as.numeric(ar[1, 1]) / mdd)
}
cat("\n=== [1] BASE (index-aligned) ===\n")
R <- list()
R$scrap <- perf(J$scrap, "SCRAP EW"); R$elite <- perf(J$elite, "ELITE EW"); R$bm <- perf(J$bm, "BENCHMARK")
for (nm in c("scrap", "elite")) {
  act <- as.numeric(J[, nm]) - as.numeric(J$bm)
  tt <- t.test(act)
  cat(sprintf("  %-24s active mean=%+.3f%%/m  t(plain)=%+.3f  n=%d\n",
              paste0(nm, " active"), 100 * mean(act), tt$statistic, length(act)))
  R[[paste0(nm, "_active_t_plain")]] <- as.numeric(tt$statistic)
}
cat(sprintf("  corr(scrap,elite) gross=%.3f  active=%.3f\n",
            cor(as.numeric(J$scrap), as.numeric(J$elite)),
            cor(as.numeric(J$scrap) - as.numeric(J$bm), as.numeric(J$elite) - as.numeric(J$bm))))

# ── [2] 조건부 프로파일: 상보성 검정 ──
cat("\n=== [2] CONDITIONAL PROFILE — ELITE vs SCRAP 상보성 ===\n")
bmv <- as.numeric(J$bm)
buckets <- list(
  `TAIL (bm<=-10%)`   = which(bmv <= -0.10),
  `DOWN (-10%<bm<0)`  = which(bmv > -0.10 & bmv < 0),
  `UP   (0<=bm<+5%)`  = which(bmv >= 0 & bmv < 0.05),
  `SURGE(bm>=+5%)`    = which(bmv >= 0.05)
)
cond <- list()
for (b in names(buckets)) {
  ix <- buckets[[b]]
  if (length(ix) < 3) { cat(sprintf("  %-20s n=%d  <3 skip\n", b, length(ix))); next }
  sa <- as.numeric(J$scrap[ix]) - bmv[ix]; ea <- as.numeric(J$elite[ix]) - bmv[ix]
  d  <- ea - sa
  cat(sprintf("  %-20s n=%3d | scrap_act=%+.3f%% elite_act=%+.3f%% | elite-scrap=%+.3f%% paired_t=%+.3f\n",
              b, length(ix), 100 * mean(sa), 100 * mean(ea), 100 * mean(d),
              if (length(ix) > 2) t.test(d)$statistic else NA))
  cond[[b]] <- list(n = length(ix), scrap_active = mean(sa), elite_active = mean(ea),
                    diff = mean(d), paired_t = as.numeric(t.test(d)$statistic))
}
R$conditional <- cond

# ── [3] MDD-정렬 오라클: 목표축을 바꾼 완전예지 상한 ──
cat("\n=== [3] MDD-ALIGNED ORACLE (ex-post · PIT 아님 · 상한 진단 전용) ===\n")
Ms <- as.matrix(sub[, ..scrap_ok])
ix_keep <- match(index(J), dts); Ms <- Ms[ix_keep, , drop = FALSE]
Me <- as.matrix(sub[, ..elite_ok])[ix_keep, , drop = FALSE]

oracle_pick <- function(M, k, score_fun, lab) {
  n <- nrow(M); W <- matrix(0, n, ncol(M))
  for (i in seq_len(n)) {
    v <- score_fun(M, i); ok <- which(is.finite(v))
    if (length(ok) < k) next
    W[i, ok[order(v[ok], decreasing = TRUE)[1:k]]] <- 1 / k
  }
  keep <- rowSums(W) > 0
  Mz <- M; Mz[!is.finite(Mz)] <- 0
  pr <- Return.portfolio(xts(Mz[keep, , drop = FALSE], order.by = index(J)[keep]),
                         weights = xts(W[keep, , drop = FALSE], order.by = index(J)[keep]),
                         rebalance_on = NA)
  perf(pr, lab)
}
# (a) 수익-정렬 (P0 재현)
R$oracle_ret10 <- oracle_pick(Ms, 10, function(M, i) M[i, ], "ORACLE ret-top10")
# (b) 손실회피-정렬: 당월 하락 최소화 (MDD 표적)
R$oracle_dd10  <- oracle_pick(Ms, 10, function(M, i) { v <- M[i, ]; ifelse(v < 0, v * 3, v) },
                              "ORACLE lossaverse-top10")
# (c) 하락월만 방어 최선 / 상승월은 EW (현실적 상한: 타이밍만 완벽)
{
  n <- nrow(Ms); W <- matrix(0, n, ncol(Ms))
  for (i in seq_len(n)) {
    v <- Ms[i, ]; ok <- which(is.finite(v))
    if (!length(ok)) next
    if (bmv[i] < 0) W[i, ok[order(v[ok], decreasing = TRUE)[1:min(10, length(ok))]]] <- 1 / min(10, length(ok))
    else W[i, ok] <- 1 / length(ok)
  }
  Mz <- Ms; Mz[!is.finite(Mz)] <- 0
  pr <- Return.portfolio(xts(Mz, order.by = index(J)), weights = xts(W, order.by = index(J)), rebalance_on = NA)
  R$oracle_downonly <- perf(pr, "ORACLE down-months-only")
}

# ── [4] 2-STATE 스위치 오라클: ELITE <-> SCRAP ──
cat("\n=== [4] 2-STATE SWITCH ORACLE (ELITE<->SCRAP, 완전예지) ===\n")
sw <- ifelse(as.numeric(J$elite) >= as.numeric(J$scrap), 1, 0)   # 1=elite
Rx <- merge(J$elite, J$scrap); Wx <- xts(cbind(sw, 1 - sw), order.by = index(J))
R$oracle_switch <- perf(Return.portfolio(Rx, weights = Wx, rebalance_on = NA), "ORACLE perfect switch")
cat(sprintf("    switch balance: elite months=%d (%.1f%%) scrap months=%d\n",
            sum(sw), 100 * mean(sw), sum(1 - sw)))
# 50/50 블렌드 (타이밍 없는 대조)
R$blend5050 <- perf(Return.portfolio(Rx, weights = xts(cbind(0.5, 0.5), order.by = index(J)),
                                     rebalance_on = NA), "BLEND 50/50 [no timing]")
# 현실적 스위치: 정확도 p 로 열화시킨 오라클 (상금의 감쇠 곡선)
cat("\n  --- switch skill decay (오라클을 정확도 p 로 열화) ---\n")
set.seed(20260809)
decay <- list()
for (p in c(0.90, 0.80, 0.70, 0.60, 0.55)) {
  vals <- replicate(40, {
    flip <- runif(length(sw)) > p
    s2 <- ifelse(flip, 1 - sw, sw)
    pr <- Return.portfolio(Rx, weights = xts(cbind(s2, 1 - s2), order.by = index(J)), rebalance_on = NA)
    ar <- table.AnnualizedReturns(pr, scale = 12); mdd <- as.numeric(maxDrawdown(pr))
    c(sr = as.numeric(ar[3, 1]), mdd = mdd, calmar = as.numeric(ar[1, 1]) / mdd)
  })
  cat(sprintf("    acc=%.2f  SR=%.3f  MDD=%.1f%%  Calmar=%.3f\n",
              p, mean(vals["sr", ]), 100 * mean(vals["mdd", ]), mean(vals["calmar", ])))
  decay[[sprintf("acc_%02d", round(100 * p))]] <- list(sharpe = mean(vals["sr", ]),
                                                       mdd = mean(vals["mdd", ]),
                                                       calmar = mean(vals["calmar", ]))
}
R$switch_decay <- decay

# ── [5] required effect size (저검정력 함정 사전 차단) ──
cat("\n=== [5] REQUIRED EFFECT SIZE (착수 전 검정력 관문) ===\n")
res_path <- file.path(PROJ, "02_Infrastructure/contracts/required_effect_size.R")
if (file.exists(res_path)) {
  source(res_path)
  cat("  [loaded] required_effect_size.R\n")
} else cat("  [warn] required_effect_size.R 부재\n")
for (b in names(buckets)) {
  ix <- buckets[[b]]; if (length(ix) < 3) next
  d <- (as.numeric(J$elite[ix]) - bmv[ix]) - (as.numeric(J$scrap[ix]) - bmv[ix])
  se <- sd(d) / sqrt(length(d))
  cat(sprintf("  %-20s n=%3d  sd(diff)=%.3f%%/m  se=%.3f%%  |t|=2.0 요구효과=%.3f%%/m (=%.2f%%/yr)  실측=%+.3f%%/m\n",
              b, length(ix), 100 * sd(d), 100 * se, 100 * 2 * se, 100 * 2 * se * 12, 100 * mean(d)))
}

# ── [6] 종목수 제약 실사 (Production Constraints: max 25) ──
cat("\n=== [6] CONSTRAINT REALITY CHECK — 모듈 앙상블의 종목수 ===\n")
cat("  ⚠ 모듈-레벨 NAV 합성은 하위 보유종목 합집합을 만든다. Production Constraint 종목수 max 25 는\n")
cat("    NAV 합성 단계에서 자동 충족되지 않는다 — FR 모드가 이 축을 어떻게 처리하는지 확인 필요(P1 항목).\n")

R$meta <- list(metric_type = "diagnostic_precheck",
               note = "오라클은 ex-post(PIT 아님) 상한 진단 전용. active t 는 plain(NW 미적용).",
               n_months = nrow(J), start = format(min(index(J)), "%Y%m"),
               end = format(max(index(J)), "%Y%m"))
write_json(R, file.path(OUT, "p0b_headroom.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
saveRDS(list(J = J, Ms = Ms, Me = Me, buckets = buckets), file.path(OUT, "p0b_series.rds"))
cat(sprintf("\n[done] -> %s\n", file.path(OUT, "p0b_headroom.json")))
