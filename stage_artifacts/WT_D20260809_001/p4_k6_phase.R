## WT-D20260809_001 P4 — 자가 적대검증이 적발한 사각: K=6 의 위상 민감도 미검
## P3 은 K=3 만 위상 검정했다(스프레드 0.141). K=6 은 위상이 6개인데 1개만 측정된 상태였다.
## K=6 의 +0.467 이 위상 추첨이면 그 값은 신호가 아니다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_001")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p4] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

P <- readRDS(file.path(OUT, "p0_panels.rds"))
A <- P$A
S0 <- A[, .(Date, Ticker, score = M26_Revenue_Mom)][!is.na(score)]
dts <- sort(unique(S0$Date)); idx <- data.table(Date = dts, mi = seq_along(dts))

stale_phase <- function(K, off) {
  ix <- copy(idx)[, blk := (mi - 1L + off) %/% K]
  ix[, src_mi := min(mi), by = blk]
  src <- merge(ix[, .(Date, src_mi)], idx[, .(src_Date = Date, src_mi = mi)], by = "src_mi")
  Sx <- merge(S0[, .(src_Date = Date, Ticker, score)], src[, .(Date, src_Date)],
              by = "src_Date", allow.cartesian = TRUE)
  Sx[, .(Date, Ticker, score)]
}
runS <- function(S, tag) {
  r <- canonical_screen_bt(S, P$ret, P$bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = P$liq, liq_min = 2e8,
                           run_id = paste0("p4_", tag), strategy_id = paste0("M26_", tag),
                           diag_dual_basis = FALSE)
  data.table(tag = tag, port_t_capw = r$portfolio_alpha_t_nw_lag3,
             alpha_ann = r$alpha_annualized, net_sr = r$net_sr,
             turnover_ann = r$turnover_annual)
}

say("=== K=6 전 위상 (0..5) ===")
P6 <- rbindlist(lapply(0:5, function(o) cbind(offset = o, runS(stale_phase(6L, o), sprintf("K6_ph%d", o)))))
print(P6[, .(offset, port_t_capw = round(port_t_capw, 3), alpha_ann = round(alpha_ann, 4),
             turnover_ann = round(turnover_ann, 2))])
say("  ★K=6 위상 스프레드: %.3f ~ %.3f (폭 %.3f · 중앙값 %.3f · 평균 %.3f)",
    min(P6$port_t_capw), max(P6$port_t_capw), diff(range(P6$port_t_capw)),
    median(P6$port_t_capw), mean(P6$port_t_capw))
say("  ★K=1 기준선 1.544 대비: 위상 중 몇 개가 상회? %d/6 · 최소 위상도 상회? %s",
    sum(P6$port_t_capw > 1.54410980134402), min(P6$port_t_capw) > 1.54410980134402)

say("=== K=2 이상치 재확인 (전 위상 0..1) ===")
P2p <- rbindlist(lapply(0:1, function(o) cbind(offset = o, runS(stale_phase(2L, o), sprintf("K2_ph%d", o)))))
print(P2p[, .(offset, port_t_capw = round(port_t_capw, 3), alpha_ann = round(alpha_ann, 4),
              turnover_ann = round(turnover_ann, 2))])
say("  ★K=2 위상 폭 %.3f — K=2 저하가 위상 고유인지 K 고유인지 판별", diff(range(P2p$port_t_capw)))

## 위상-평균 K 곡선 (위상 추첨 제거)
say("=== 위상-평균 K 곡선 (추첨 성분 제거) ===")
allK <- rbindlist(lapply(c(1L, 2L, 3L, 6L), function(K) {
  offs <- if (K == 1L) 0L else 0:(K - 1L)
  d <- rbindlist(lapply(offs, function(o) runS(stale_phase(K, o), sprintf("K%d_ph%d", K, o))))
  data.table(K = K, n_phase = length(offs),
             port_t_mean = mean(d$port_t_capw), port_t_min = min(d$port_t_capw),
             port_t_max = max(d$port_t_capw),
             alpha_ann_mean = mean(d$alpha_ann), turnover_mean = mean(d$turnover_ann))
}))
allK[, gross_ann_pct := alpha_ann_mean * 100 + turnover_mean * 0.0015 * 100]
print(allK[, .(K, n_phase, port_t_mean = round(port_t_mean, 3),
               port_t_min = round(port_t_min, 3), port_t_max = round(port_t_max, 3),
               alpha_ann_mean = round(alpha_ann_mean, 4),
               turnover_mean = round(turnover_mean, 2),
               gross_ann_pct = round(gross_ann_pct, 2))])

saveRDS(list(k6_phase = P6, k2_phase = P2p, k_curve = allK), file.path(OUT, "p4_results.rds"))
fwrite(allK, file.path(OUT, "p4_k_curve_phase_averaged.csv"))
say("=== P4 완료 ===")
