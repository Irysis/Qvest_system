#!/usr/bin/env Rscript
# =============================================================================
# p0h_base_parity.R — base 재현 불일치의 원인을 가른다 (추정 금지, 실측)
#
# 관측: 같은 "dedup 85 EW" 인데 두 산출이 갈린다.
#   내 p0g      CAGR 11.04 SR 0.620 MDD 40.5
#   에이전트     CAGR 11.64 SR 0.649 MDD 40.5   (meta: rebalance_on="months")
#   MDD 만 정확히 일치 → 구성은 같고 *수익 합성 경로*가 다르다는 가설.
#
# 후보 원인 3종을 각각 켜고 끄며 어느 것이 차이를 만드는지 격리한다:
#   C1 rebalance_on = NA vs "months"
#   C2 dedup 대표 선택 규칙 (첫 인덱스 vs 다른 규칙)
#   C3 행 필터 (complete-case vs NA-인지 가중)
#
# ★ base 가 다르면 arm-vs-base paired t 가 통째로 달라진다(같은 필터가 base 에 따라
#   ΔIR +0.169 / -0.149 로 뒤집힌 전례). 어느 쪽이 정본인지 확정하고 간다.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p0h_parity.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
dts <- as.Date(paste0(sub$ym, "01"), "%Y%m%d")
M0 <- as.matrix(sub[, ..scrap_ok])
keepc <- which(colSums(is.finite(M0)) >= 253)
rowsc <- complete.cases(M0[, keepc, drop = FALSE])
M <- M0[rowsc, keepc, drop = FALSE]; dtw <- dts[rowsc]
cat(sprintf("[0] 공통 입력: %d months x %d modules (complete-case)\n", nrow(M), ncol(M)))

## dedup 성분 (규칙 고정: corr>=0.999 union-find)
C <- cor(M); diag(C) <- 0
hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[, 1] < hi[, 2], , drop = FALSE]
comp <- local({
  par <- seq_len(ncol(M)); fnd <- function(x) { while (par[x] != x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) { a <- fnd(hi[r,1]); b <- fnd(hi[r,2]); if (a != b) par[b] <- a }
  vapply(seq_len(ncol(M)), fnd, integer(1))
})
grp <- unique(comp)
cat(sprintf("[0b] dedup 성분 수 = %d\n", length(grp)))

met <- function(pr, lab) {
  ar <- table.AnnualizedReturns(pr, scale = 12); m <- as.numeric(maxDrawdown(pr))
  cat(sprintf("  %-46s CAGR=%6.2f%%  SR=%6.4f  MDD=%6.3f%%\n", lab, 100*ar[1,1], ar[3,1], 100*m))
  c(cagr = 100*as.numeric(ar[1,1]), sr = as.numeric(ar[3,1]), mdd = 100*m)
}
build <- function(reps, rebal) {
  Mu <- M[, reps, drop = FALSE]
  W <- matrix(1/ncol(Mu), nrow(Mu), ncol(Mu))
  Return.portfolio(xts(Mu, order.by = dtw), weights = xts(W, order.by = dtw), rebalance_on = rebal)
}

cat("\n=== [C1] rebalance_on 축 (대표=첫 인덱스 고정) ===\n")
reps_first <- vapply(grp, function(g) which(comp == g)[1], integer(1))
r_na <- met(build(reps_first, NA),       "reps=first · rebalance_on=NA")
r_mo <- met(build(reps_first, "months"), "reps=first · rebalance_on='months'")
cat(sprintf("  → C1 효과: ΔCAGR=%+.3f%%p  ΔSR=%+.4f  ΔMDD=%+.3f%%p\n",
            r_mo["cagr"]-r_na["cagr"], r_mo["sr"]-r_na["sr"], r_mo["mdd"]-r_na["mdd"]))

cat("\n=== [C2] dedup 대표 선택 규칙 축 (rebalance_on 고정) ===\n")
rule <- list(
  first     = vapply(grp, function(g) which(comp == g)[1], integer(1)),
  last      = vapply(grp, function(g) tail(which(comp == g), 1), integer(1)),
  best_sr   = vapply(grp, function(g) { ix <- which(comp == g)
                     ix[which.max(apply(M[, ix, drop=FALSE], 2, function(x) mean(x)/sd(x)))] }, integer(1)),
  worst_sr  = vapply(grp, function(g) { ix <- which(comp == g)
                     ix[which.min(apply(M[, ix, drop=FALSE], 2, function(x) mean(x)/sd(x)))] }, integer(1))
)
res2 <- list()
for (nm in names(rule)) res2[[nm]] <- met(build(rule[[nm]], NA), sprintf("reps=%-9s · rebalance_on=NA", nm))
sp <- range(vapply(res2, function(z) z["cagr"], numeric(1)))
cat(sprintf("  → C2 효과: CAGR 범위 %.2f ~ %.2f (%.3f%%p 폭)  SR 범위 %.4f ~ %.4f\n",
            sp[1], sp[2], diff(sp),
            min(vapply(res2, function(z) z["sr"], numeric(1))),
            max(vapply(res2, function(z) z["sr"], numeric(1)))))

cat("\n=== [C3] 성분 평균(대표 대신 그룹 평균) — 대표 선택 임의성 제거안 ===\n")
Mg <- sapply(grp, function(g) rowMeans(M[, comp == g, drop = FALSE]))
Wg <- matrix(1/ncol(Mg), nrow(Mg), ncol(Mg))
r_grp <- met(Return.portfolio(xts(Mg, order.by = dtw), weights = xts(Wg, order.by = dtw), rebalance_on = NA),
             "성분 평균(대표 임의성 제거) · rebalance_on=NA")

cat("\n=== [판정] ===\n")
cat(sprintf("  타깃(에이전트 보고): CAGR 11.64  SR 0.6486  MDD 40.521\n"))
cands <- c(list(`C1:months`=r_mo, `C1:NA`=r_na), setNames(res2, paste0("C2:", names(res2))),
           list(`C3:groupmean`=r_grp))
for (nm in names(cands)) {
  z <- cands[[nm]]
  cat(sprintf("  %-18s |ΔCAGR|=%.3f |ΔSR|=%.4f |ΔMDD|=%.4f %s\n", nm,
              abs(z["cagr"]-11.64), abs(z["sr"]-0.6486), abs(z["mdd"]-40.5209),
              if (abs(z["cagr"]-11.64)<0.02 && abs(z["sr"]-0.6486)<0.002) "  <== 재현" else ""))
}
cat("\n  ★ 정본 권고: 대표 선택 임의성이 base 를 흔들면(C2 폭 참조) 성분 평균(C3)이 임의성 없는 기준.\n")
cat("    어느 것을 쓰든 **arm 과 base 가 동일 규칙**이어야 paired 비교가 성립한다.\n")

write_json(list(metric_type="diagnostic_precheck",
                c1_na=as.list(r_na), c1_months=as.list(r_mo),
                c2=lapply(res2, as.list), c3_groupmean=as.list(r_grp),
                target_agent=list(cagr=11.64, sr=0.6486, mdd=40.5209)),
           file.path(OUT, "p0h_base_parity.json"), auto_unbox=TRUE, digits=NA, pretty=TRUE)
cat("\n[done]\n"); sink()
