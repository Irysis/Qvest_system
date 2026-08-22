## WT-D20260822_002 · P5 — advisory 배터리 + alpha_package.json / alpha_validation.json 발행
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260822_002/p5_emit_package.R")'

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT  <- "stage_artifacts/WT-D20260822_002"
SRC  <- "stage_artifacts/fq233_probe0_20260813"
MBX  <- "qepm/mailbox/worktask/WT-D20260822_002"
P2 <- readRDS(file.path(OUT,"p2_arms.rds")); P3 <- readRDS(file.path(OUT,"p3_verdict.rds"))
P4 <- readRDS(file.path(OUT,"p4_diagnostics.rds"))
RES <- P2$RES; SC <- P2$SC; CP <- P3$CP; PRIM <- c("SEL_RANK","SEL_PEARSON","SEL_MEANDEPTH")

cat("=== 1) advisory 배터리 (Step 4-B — 게이트 아님, 기록 의무) ===\n")
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))[, anchor := as.Date(anchor)]
fwd <- pan[, .(Date = anchor, Ticker = as.character(Ticker), fwd = fwd_ret_1m)][is.finite(fwd)]
adv <- rbindlist(lapply(PRIM, function(a) {
  j <- merge(SC[[a]], fwd, by = c("Date","Ticker"))
  ic <- j[, .(ic = if (.N >= 30L) stats::cor(score, fwd, method="spearman") else NA_real_), by = Date][is.finite(ic)]
  icp <- j[, .(ic = if (.N >= 30L) stats::cor(score, fwd, method="pearson") else NA_real_), by = Date][is.finite(ic)]
  ## 십분위 단조성: 월별 십분위 평균수익의 Spearman(분위지수, 평균수익) 중앙값
  mono <- j[, { d <- cut(frank(score), breaks = quantile(frank(score), 0:10/10), include.lowest = TRUE, labels = FALSE)
                m <- tapply(fwd, d, mean); if (length(m) < 10L) NA_real_ else stats::cor(seq_along(m), m, method="spearman") },
            by = Date]$V1
  sp <- j[, .(y = as.integer(format(Date, "%Y")))][, y]
  p1 <- ic[Date <  as.Date("2014-01-01"), mean(ic)]
  p2 <- ic[Date >= as.Date("2014-01-01") & Date < as.Date("2020-01-01"), mean(ic)]
  p3 <- ic[Date >= as.Date("2020-01-01"), mean(ic)]
  subp <- mean(c(p1,p2,p3) > 0)
  data.table(arm = a, n_months = nrow(ic), rank_ic = mean(ic$ic), rank_ic_sd = sd(ic$ic),
             icir_monthly = mean(ic$ic)/sd(ic$ic), icir_ann = mean(ic$ic)/sd(ic$ic)*sqrt(12),
             harvey_t_rank_ic_nw3 = .nw_t_mean(ic$ic, lag=3L),
             pearson_ic = mean(icp$ic), pearson_t_nw3 = .nw_t_mean(icp$ic, lag=3L),
             monotonicity = median(mono, na.rm=TRUE), subperiod_stability = subp,
             ic_p1 = p1, ic_p2 = p2, ic_p3 = p3)
}))
print(adv)

cat("\n=== 2) confidence_vector (live 2026-08) ===\n")
LIVE <- as.data.table(read_parquet(file.path(OUT,"alpha_vector_live_202608.parquet")))
prev <- SC$SEL_PEARSON[Date == max(Date)]           # 2026-07 홀딩월 스코어 (직전 랭크 기준)
mkconf <- function(armid) {
  L <- LIVE[arm == armid]
  fs <- strsplit(L$selected[1], "\\|")[[1]]
  pl <- pan[anchor == as.Date("2026-08-01")]
  Z <- as.matrix(pl[, ..fs]); nv <- rowSums(is.finite(Z))
  d <- data.table(Ticker = as.character(pl$Ticker), n_fac = nv)
  L2 <- merge(L, d, by = "Ticker")
  L2[, pr_now := frank(alpha_score)/.N]
  pv <- prev[, .(Ticker, pr_prev = frank(score)/.N)]
  L2 <- merge(L2, pv, by = "Ticker", all.x = TRUE)
  L2[, stab := ifelse(is.na(pr_prev), 0.5, 1 - abs(pr_now - pr_prev))]
  ## 데이터 가용성 0.4 + 랭크 안정성 0.3 + 부기간 IC 안정성 0.3 (arm 공통 스칼라)
  sstab <- adv[arm == armid, subperiod_stability]
  L2[, confidence := pmin(1, pmax(0, 0.4*(n_fac/5) + 0.3*stab + 0.3*sstab))]
  L2[, .(Ticker, alpha_score, confidence)]
}
CONF <- mkconf("SEL_PEARSON")
cat(sprintf("  SEL_PEARSON live: %d종목 · confidence 중앙 %.3f [%.3f, %.3f]\n",
            nrow(CONF), median(CONF$confidence), min(CONF$confidence), max(CONF$confidence)))

cat("\n=== 3) factor_specs (live 선별 5종 · registry 메타) ===\n")
reg <- fromJSON(".cache/factor_db/factor_registry.json", simplifyVector = FALSE)
spec_of <- function(armid) {
  fs <- strsplit(LIVE[arm == armid, selected][1], "\\|")[[1]]
  lapply(fs, function(f) { r <- reg[[f]]
    list(factor_id = f,
         factor_family = if (!is.null(r$category)) r$category else "unknown",
         proxy = if (!is.null(r$description)) r$description else if (!is.null(r$name)) r$name else f,
         source = "db_existing (load_month_factors 경유 · Z_Score_Aligned C13)",
         lag_rule = if (!is.null(r$lag_rule)) r$lag_rule else "factor DB 빌더 규약(C4/C14) 승계",
         winsorization = "연결자 단계 표준화 — 본 라운드 추가 절단 없음",
         neutralization = "none (승계 자구 — 재z/중립화 미적용)",
         economic_rationale = "본 라운드는 팩터 발굴이 아니라 **선별 통계량** 라운드다. 개별 팩터의 근거는 factor DB registry 를 따르고, 이 5종은 walk-forward 선별의 산출이지 사전 선택이 아니다.",
         weight_theta = 1/length(fs),
         selected_by = armid) })
}
FSPEC <- unlist(lapply(PRIM, spec_of), recursive = FALSE)
for (s in FSPEC) cat(sprintf("  %-14s %-26s %s\n", s$selected_by, s$factor_id, s$factor_family))

cat("\n=== 4) alpha_validation.json ===\n")
GATE <- P2$GATE; DIV <- P2$DIV; LBL <- P3$LBL
av <- list(
  task_id = "WT-D20260822_002", round_id = "FQ237_RERANK_20260822",
  prereg = "stage_artifacts/WT-D20260822_002/PREREG.json",
  metric_type = "canonical_screen",
  metric_type_note = "canonical_screen_bt 실측(top-25 EW long-only · 15bps). forge-authoritative 아님 — graduation HARD 판정 근거로 쓸 수 없다.",
  n_holding_months = 221L, n_factor_pool = 320L, K = 5L, W = 36L, top_n = 25L,
  reproduction_check = list(passed = as.integer(sum(P2$rep_ok)), total = length(P2$rep_ok),
    detail = list(SEL_RANK_port_t = RES$SEL_RANK$portfolio_alpha_t_nw_lag3,
                  SEL_RANK_prereg = 0.94741,
                  SEL_MEANDEPTH_port_t = RES$SEL_MEANDEPTH$portfolio_alpha_t_nw_lag3,
                  SEL_MEANDEPTH_prereg = 1.77748,
                  coprimary_B_t = CP$B$t_nw3, coprimary_B_prereg = 1.57062)),
  arms = as.list(P4$perf), power_gate = as.list(GATE), ci = as.list(P4$ci),
  coprimary = list(
    A = list(contrast = "SEL_PEARSON - SEL_RANK", n = CP$A$n, mean_monthly = CP$A$mean_m,
             annual_pct = CP$A$ann_pct, t_nw3 = CP$A$t_nw3, t_active_nw3 = CP$A$t_active_nw3,
             label = LBL$A$label, mde_annual_pct = LBL$A$mde, implied_t_threshold = LBL$A$implied_t_threshold),
    B = list(contrast = "SEL_MEANDEPTH - SEL_RANK", n = CP$B$n, mean_monthly = CP$B$mean_m,
             annual_pct = CP$B$ann_pct, t_nw3 = CP$B$t_nw3, t_active_nw3 = CP$B$t_active_nw3,
             label = LBL$B$label, mde_annual_pct = LBL$B$mde, implied_t_threshold = LBL$B$implied_t_threshold)),
  aux_arms = list(negative_control_meddepth_t = P3$AUX$NEG$t_nw3,
                  violation_injection_lookahead_t = P3$AUX$INJ$t_nw3,
                  pit_stress_lag1_t = P3$AUX$LAG1$t_nw3),
  falsification_axis1 = list(
    rho_rank_pearson_median = median(DIV$rho_rank_pearson, na.rm=TRUE),
    rho_rank_meandepth_median = median(DIV$rho_rank_depth, na.rm=TRUE),
    jaccard_rank_pearson_median = median(DIV$jac_rank_pearson, na.rm=TRUE),
    jaccard_rank_meandepth_median = median(DIV$jac_rank_depth, na.rm=TRUE),
    reject_threshold = list(rho = 0.90, jaccard = 0.80), fired = P2$axis1_fire),
  falsification_axis2 = P4$axis2,
  basis_three_way = as.list(P4$basis3),
  robustness = list(R1_liquidity = as.list(P4$R1)),
  advisory_battery = as.list(adv),
  dsr_diagnostic = as.list(P4$dsr),
  selection_type = "chain", sweep_count = 0L
)
write_json(av, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat("  [saved] alpha_validation.json\n")

saveRDS(list(adv = adv, CONF = CONF, FSPEC = FSPEC), file.path(OUT, "p5_inputs.rds"))
cat("[saved] p5_inputs.rds\n")
