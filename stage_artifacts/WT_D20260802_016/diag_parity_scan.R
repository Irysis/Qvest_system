# diag_parity_scan.R — WT-016 parity STOP 진단: layer5 행 <-> 달력월 정렬 β-스캔
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
say <- function(fmt, ...) cat(sprintf(paste0("[diag] ", fmt, "\n"), ...))
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
bench <- as.data.table(SI$bench); bench[, Date := as.Date(Date)]
# bench: Date=d0(전월말), BM_Ret = 홀딩월(month(d0)+1) 실현 벤치수익
bench[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
BM <- bench[, .(ym = hold_ym, bm = BM_Ret)]

L5 <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
L5 <- L5[, .(return_ym, realized_ym, ret_orig = as.numeric(ret_orig), ret_L5_V5 = as.numeric(ret_L5_V5))]

R <- readRDS("stage_artifacts/WT_D20260802_016/wt016_eval_results.rds")
# 저장 전 stop이었을 수 있음 — 존재 확인
if (!file.exists("stage_artifacts/WT_D20260802_016/wt016_eval_results.rds")) stop("rds 없음")

# ── 1. layer5 ret_orig vs 벤치: return_ym 기준 offset 스캔 ───────────────────
say("--- ret_orig vs BM (조인키 = return_ym + offset k) ---")
for (k in -2:2) {
  X <- merge(L5[, .(ym = ym_add(return_ym, k), r = ret_orig)], BM, by = "ym")
  say("  k=%+d: cor=%.4f β=%.3f n=%d", k, X[, cor(r, bm)],
      X[, cov(r, bm) / var(bm)], nrow(X))
}
# ── 2. layer5 ret_orig vs 내 bare base ret_net (스크린 계층 동일성) ──────────
# 주: rds 저장이 stop으로 미도달일 수 있어 재구성 대신 저장분 사용 불가 시 skip
if (!is.null(R$cells$base_bare$period_returns)) {
  MB <- as.data.table(R$cells$base_bare$period_returns)[, .(date, mine = ret_net)]
  MB[, ym := ym_add(format(date, "%Y-%m"), 1L)]   # 홀딩월
  say("--- ret_orig vs 내 base/bare ret_net (조인키 = return_ym + offset k) ---")
  for (k in -2:2) {
    X <- merge(L5[, .(ym = ym_add(return_ym, k), r = ret_orig)], MB[, .(ym, mine)], by = "ym")
    say("  k=%+d: cor=%.4f mean(book-mine)=%+.5f n=%d", k, X[, cor(r, mine)],
        X[, mean(r - mine)], nrow(X))
  }
  # L5 계층 동일 스캔
  say("--- ret_L5_V5 vs 내 base/OVERLAY ret_net ---")
  MO <- as.data.table(R$cells$base_ov$period_returns)[, .(date, mine = ret_net)]
  MO[, ym := ym_add(format(date, "%Y-%m"), 1L)]
  for (k in -2:2) {
    X <- merge(L5[, .(ym = ym_add(return_ym, k), r = ret_L5_V5)], MO[, .(ym, mine)], by = "ym")
    say("  k=%+d: cor=%.4f n=%d", k, X[, cor(r, mine)], nrow(X))
  }
}
# ── 3. 대안 정렬 가설: realized_ym이 진짜 수익월인 경우 ──────────────────────
say("--- ret_orig vs BM (조인키 = realized_ym) ---")
X <- merge(L5[, .(ym = realized_ym, r = ret_orig)], BM, by = "ym")
say("  realized_ym: cor=%.4f n=%d", X[, cor(r, bm)], nrow(X))
