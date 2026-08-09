## WT-D20260809_001 P5 — 회전율 레버의 **paired** 직접 검정
## 왜: P2/P4 는 arm 별 PORT_t 를 나란히 놓고 비교했다. 그건 차이의 유의성이 아니다.
##     레포 규약(FQ-090 next_action 3호): "paired NW lag-3 t 로 차이 유의성 직접 검정(비율 해석 금지)".
## 동일 월·동일 벤치이므로 paired 차이 = ret_net(K) - ret_net(1).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_001")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p5] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")

P <- readRDS(file.path(OUT, "p0_panels.rds"))
S0 <- P$A[, .(Date, Ticker, score = M26_Revenue_Mom)][!is.na(score)]
dts <- sort(unique(S0$Date)); idx <- data.table(Date = dts, mi = seq_along(dts))

stale_phase <- function(K, off) {
  if (K == 1L) return(copy(S0))
  ix <- copy(idx)[, blk := (mi - 1L + off) %/% K]
  ix[, src_mi := min(mi), by = blk]
  src <- merge(ix[, .(Date, src_mi)], idx[, .(src_Date = Date, src_mi = mi)], by = "src_mi")
  merge(S0[, .(src_Date = Date, Ticker, score)], src[, .(Date, src_Date)],
        by = "src_Date", allow.cartesian = TRUE)[, .(Date, Ticker, score)]
}
series <- function(K, off) {
  r <- canonical_screen_bt(stale_phase(K, off), P$ret, P$bench, top_n = 25L,
                           cost_bps_oneway = 15, liq_dt = P$liq, liq_min = 2e8,
                           run_id = sprintf("p5_K%d_%d", K, off),
                           strategy_id = sprintf("M26_K%d_%d", K, off), diag_dual_basis = FALSE)
  list(pr = as.data.table(r$period_returns), port_t = r$portfolio_alpha_t_nw_lag3,
       turn = r$turnover_annual)
}

BASE <- series(1L, 0L)
say("기준선 K=1: PORT_t %.3f · turnover %.2f · %d개월", BASE$port_t, BASE$turn, nrow(BASE$pr))

rows <- list()
for (K in c(2L, 3L, 6L)) {
  for (off in 0:(K - 1L)) {
    X <- series(K, off)
    M <- merge(BASE$pr[, .(date, base = ret_net)], X$pr[, .(date, arm = ret_net)], by = "date")
    d <- M$arm - M$base
    t_nw <- .nw_t_mean(d, lag = 3L)
    req <- required_effect(n = length(d), t_threshold = 2.0, sd_monthly = sd(d), design = "full")
    rows[[length(rows) + 1L]] <- data.table(
      K = K, offset = off, n = length(d),
      d_ann_pct = mean(d) * 12 * 100, d_sd = sd(d), paired_t_nw3 = t_nw,
      required_ann_pct = req$required_annual * 100,
      arm_port_t = X$port_t, arm_turnover = X$turn)
  }
}
PR <- rbindlist(rows)
PR[, verdict := fifelse(abs(paired_t_nw3) >= 2.0, "SIGNIFICANT",
                 fifelse(abs(d_ann_pct) >= required_ann_pct, "NULL_POWERED", "INCONCLUSIVE_UNDERPOWERED"))]
print(PR[, .(K, offset, n, d_ann_pct = round(d_ann_pct, 3), paired_t_nw3 = round(paired_t_nw3, 3),
             required_ann_pct = round(required_ann_pct, 3), arm_port_t = round(arm_port_t, 3),
             arm_turnover = round(arm_turnover, 2), verdict)])

say("=== K별 위상 요약 (paired 차이) ===")
SUM <- PR[, .(n_phase = .N, d_ann_mean = mean(d_ann_pct),
              t_mean = mean(paired_t_nw3), t_min = min(paired_t_nw3), t_max = max(paired_t_nw3),
              n_sig_pos = sum(paired_t_nw3 >= 2), n_sig_neg = sum(paired_t_nw3 <= -2),
              turn_mean = mean(arm_turnover)), by = K]
print(SUM[, .(K, n_phase, d_ann_mean = round(d_ann_mean, 3), t_mean = round(t_mean, 3),
              t_min = round(t_min, 3), t_max = round(t_max, 3), n_sig_pos, n_sig_neg,
              turn_mean = round(turn_mean, 2))])

say("★판정: 어느 (K, 위상) 조합에서도 paired |t| >= 2.0 인 개선이 있는가? %s",
    any(PR$paired_t_nw3 >= 2.0))
say("★검정력: paired 차이 sd 기준 필요 효과 = 연 %.2f%% ~ %.2f%% (관측 폭 %.2f%% ~ %.2f%%)",
    min(PR$required_ann_pct), max(PR$required_ann_pct), min(PR$d_ann_pct), max(PR$d_ann_pct))

saveRDS(list(paired = PR, summary = SUM), file.path(OUT, "p5_results.rds"))
fwrite(PR, file.path(OUT, "p5_paired.csv"))
say("=== P5 완료 ===")
