## WT-D20260809_001 P1 — CH-A(비용 반사실) + CH-C(breadth 진단)
## 사전등록 고정: cost 15->0 은 counterfactual_diag / N>25 는 진단 전용(자본 주장 금지)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_001")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

P <- readRDS(file.path(OUT, "p0_panels.rds"))
A <- P$A; ret <- P$ret; bench <- P$bench; liq <- P$liq; size_dt <- P$size_dt
say("입력 재확인: scores %d행 %d개월 · ret %d행 · bench %d행",
    nrow(A), uniqueN(A$Date), nrow(ret), nrow(bench))

S_raw <- A[, .(Date, Ticker, score = M26_Revenue_Mom)][!is.na(score)]

runarm <- function(top_n, cost_bps, tag) {
  r <- canonical_screen_bt(S_raw, ret, bench, top_n = as.integer(top_n),
                           cost_bps_oneway = cost_bps,
                           liq_dt = liq, liq_min = 2e8,
                           run_id = paste0("WT_D20260809_001_", tag),
                           strategy_id = paste0("M26_", tag),
                           diag_dual_basis = TRUE, size_dt = size_dt)
  ew <- r$diag_ew_universe
  data.table(
    tag = tag, top_n = top_n, cost_bps = cost_bps, n_months = r$n_months,
    port_t_capw   = r$portfolio_alpha_t_nw_lag3,
    alpha_ann     = r$alpha_annualized,
    net_sr        = r$net_sr,
    ir            = r$information_ratio,
    turnover_ann  = r$turnover_annual,
    port_t_ew     = if (!is.null(ew)) ew$portfolio_alpha_t_nw_lag3 else NA_real_,
    alpha_ann_ew  = if (!is.null(ew)) ew$alpha_annualized else NA_real_,
    oos_ret       = if (!is.null(ew)) ew$oos_retention_approx else NA_real_,
    post2017_t    = if (!is.null(ew)) ew$post2017_t_nw_lag3 else NA_real_)
}

## ---- CH-A: 비용 반사실 (선별·비중·기간 동일, 비용만 변화) --------------------
say("=== CH-A 비용 반사실 (top_n=25 고정) ===")
A15 <- runarm(25, 15, "n25_cost15_NET")        # 실측 기준선 (자본 라벨 가능)
A0  <- runarm(25,  0, "n25_cost00_COUNTERFACTUAL")  # ★반사실 진단 — 자본 주장 불가
CHA <- rbind(A15, A0)
print(CHA[, .(tag, top_n, cost_bps, n_months, port_t_capw = round(port_t_capw, 3),
              alpha_ann = round(alpha_ann, 4), turnover_ann = round(turnover_ann, 2),
              port_t_ew = round(port_t_ew, 3))])
d_t   <- A0$port_t_capw - A15$port_t_capw
d_a   <- A0$alpha_ann   - A15$alpha_ann
say("  ★비용 채널 크기: PORT_t %+.3f -> %+.3f (D %+.3f) · alpha_ann %+.4f -> %+.4f (D %+.4f = 연 %.2f%%p)",
    A15$port_t_capw, A0$port_t_capw, d_t, A15$alpha_ann, A0$alpha_ann, d_a, d_a * 100)
say("  ★회계 대조: turnover %.2f/yr x 15bps = 연 %.2f%%p (실과금 예상치)",
    A15$turnover_ann, A15$turnover_ann * 0.0015 * 100)
say("  ★D1 조건: gross(0bps) PORT_t >= 2.95 AND net < 2.95 ?  gross=%.3f net=%.3f -> %s",
    A0$port_t_capw, A15$port_t_capw,
    (A0$port_t_capw >= 2.95 && A15$port_t_capw < 2.95))

## ---- CH-C: breadth 진단 (N>25 = 진단 전용) -----------------------------------
say("=== CH-C breadth 진단 (cost 15bps 고정) ===")
say("  ★N>25 는 Production Constraints 밖 — 진단 전용. 자본 주장/챔피언 승격 금지(사전등록 고정).")
CHC <- rbindlist(lapply(c(15, 25, 50, 75), function(n)
  runarm(n, 15, sprintf("n%02d_cost15%s", n, if (n > 25) "_DIAGONLY" else ""))))
print(CHC[, .(top_n, n_months, port_t_capw = round(port_t_capw, 3),
              alpha_ann = round(alpha_ann, 4), net_sr = round(net_sr, 3),
              turnover_ann = round(turnover_ann, 2), port_t_ew = round(port_t_ew, 3),
              oos_ret = round(oos_ret, 3), post2017_t = round(post2017_t, 3))])
d50_25 <- CHC[top_n == 50, port_t_capw] - CHC[top_n == 25, port_t_capw]
say("  ★D3 조건: PORT_t(50) - PORT_t(25) > 1.0 ?  %+.3f -> %s", d50_25, (d50_25 > 1.0))

## ---- 비용 무관 breadth (CH-A x CH-C 교차, 진단) ------------------------------
say("=== 교차 진단: 비용 0 에서의 breadth (비용/슬롯 분리) ===")
CHX <- rbindlist(lapply(c(15, 25, 50, 75), function(n)
  runarm(n, 0, sprintf("n%02d_cost00_DIAGONLY", n))))
print(CHX[, .(top_n, port_t_capw = round(port_t_capw, 3), alpha_ann = round(alpha_ann, 4),
              turnover_ann = round(turnover_ann, 2), port_t_ew = round(port_t_ew, 3))])

saveRDS(list(cha = CHA, chc = CHC, chx = CHX), file.path(OUT, "p1_results.rds"))
fwrite(rbind(CHA, CHC, CHX), file.path(OUT, "p1_arms.csv"))
say("=== P1 완료 → p1_results.rds / p1_arms.csv ===")
