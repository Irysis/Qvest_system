## WT-D20260809_001 P2 — 점수 staleness(리밸 주기) A/B. 예측은 p2_prediction.json 에 측정 전 고정.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_001")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p2] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

P <- readRDS(file.path(OUT, "p0_panels.rds"))
A <- P$A; ret <- P$ret; bench <- P$bench; liq <- P$liq; size_dt <- P$size_dt
S0 <- A[, .(Date, Ticker, score = M26_Revenue_Mom)][!is.na(score)]
say("입력: %d행 · %d개월", nrow(S0), uniqueN(S0$Date))

dts <- sort(unique(S0$Date))
idx <- data.table(Date = dts, mi = seq_along(dts))

## staleness 연산자: 블록 첫 달 점수를 블록 전체에 재사용 (오래된 정보만 사용 = PIT 안전)
stale_scores <- function(K) {
  if (K == 1L) return(copy(S0))
  ix <- copy(idx)[, blk := (mi - 1L) %/% K]
  ix[, src_mi := min(mi), by = blk]
  src <- merge(ix[, .(Date, src_mi)], idx[, .(src_Date = Date, src_mi = mi)], by = "src_mi")
  Sx <- merge(S0[, .(src_Date = Date, Ticker, score)], src[, .(Date, src_Date)],
              by = "src_Date", allow.cartesian = TRUE)
  Sx[, .(Date, Ticker, score)]
}

runK <- function(K) {
  S <- stale_scores(as.integer(K))
  r <- canonical_screen_bt(S, ret, bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq, liq_min = 2e8,
                           run_id = sprintf("WT_D20260809_001_K%d", K),
                           strategy_id = sprintf("M26_K%d", K),
                           diag_dual_basis = TRUE, size_dt = size_dt)
  ew <- r$diag_ew_universe
  data.table(K = K, n_months = r$n_months,
             port_t_capw = r$portfolio_alpha_t_nw_lag3,
             alpha_ann = r$alpha_annualized, net_sr = r$net_sr,
             turnover_ann = r$turnover_annual,
             cost_ann_pct = r$turnover_annual * 0.0015 * 100,
             port_t_ew = if (!is.null(ew)) ew$portfolio_alpha_t_nw_lag3 else NA_real_,
             oos_ret = if (!is.null(ew)) ew$oos_retention_approx else NA_real_)
}

K2 <- rbindlist(lapply(c(1, 2, 3, 6), runK))
print(K2[, .(K, n_months, port_t_capw = round(port_t_capw, 3), alpha_ann = round(alpha_ann, 4),
             turnover_ann = round(turnover_ann, 2), cost_ann_pct = round(cost_ann_pct, 2),
             net_sr = round(net_sr, 3), port_t_ew = round(port_t_ew, 3), oos_ret = round(oos_ret, 3))])

## 항등 검증 (사전등록 필수)
base_t <- K2[K == 1, port_t_capw]
say("★항등 검증: K=1 PORT_t = %.4f vs P1 기준선 1.5441 -> 차이 %.6f",
    base_t, base_t - 1.54410980134402)
if (abs(base_t - 1.54410980134402) > 1e-6) {
  say("★★불일치 — staleness 연산자 구현 오류. 판정 보류.")
} else {
  say("  항등 통과 — 연산자 정상")
}

## 예측 검정
d3 <- K2[K == 3, port_t_capw] - base_t
say("★예측 검정: K=3 PORT_t %+.3f vs K=1 %+.3f -> D %+.3f (falsifier 문턱 +0.30)",
    K2[K == 3, port_t_capw], base_t, d3)
say("  예측(개선 없음) %s", if (d3 < 0.30) "생존" else "반증 — lag1 측정과 모순, 조사 필요")
say("★비용 절감 실측: K=1 연 %.2f%%p -> K=3 연 %.2f%%p (절감 %.2f%%p)",
    K2[K == 1, cost_ann_pct], K2[K == 3, cost_ann_pct],
    K2[K == 1, cost_ann_pct] - K2[K == 3, cost_ann_pct])
say("★gross 알파 손실: K=1 %.2f%% -> K=3 %.2f%% (손실 %.2f%%p)",
    K2[K == 1, alpha_ann] * 100 + K2[K == 1, cost_ann_pct],
    K2[K == 3, alpha_ann] * 100 + K2[K == 3, cost_ann_pct],
    (K2[K == 1, alpha_ann] * 100 + K2[K == 1, cost_ann_pct]) -
    (K2[K == 3, alpha_ann] * 100 + K2[K == 3, cost_ann_pct]))

saveRDS(K2, file.path(OUT, "p2_results.rds"))
fwrite(K2, file.path(OUT, "p2_staleness.csv"))
say("=== P2 완료 ===")
