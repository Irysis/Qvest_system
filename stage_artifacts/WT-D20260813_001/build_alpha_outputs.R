## WT-D20260813_001 — alpha_scores.parquet + advisory diagnostics + alpha_validation.json
## measure_q90.R 산출을 소비. 판정 수치 재계산 금지 — 읽어서 패키징.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
source("02_Infrastructure/config.R")
SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260813_001"

full <- readRDS(file.path(OUT, "measure_q90_full.rds"))
Q <- full$Q
verdict <- fromJSON(file.path(OUT, "q90_paired_verdict.json"))
fals    <- fromJSON(file.path(OUT, "q90_falsification.json"))

## ── alpha_scores.parquet : 월별 q90 예측 점수 (ticker × month) = alpha score panel ──
sc <- as.data.table(read_parquet(file.path(OUT, "q90_model_scores.parquet")))
sc[, Date := as.Date(Date)]
alpha_panel <- sc[, .(Date, sig_date = as.Date(sig_date), Ticker = as.character(Ticker),
                      alpha_score = as.numeric(score))]
write_parquet(alpha_panel, file.path(OUT, "alpha_scores.parquet"))
cat(sprintf("alpha_scores.parquet 저장 — %d행 · %d개월\n", nrow(alpha_panel), uniqueN(alpha_panel$Date)))

## ── advisory 진단: rank-IC / ICIR / monotonicity(decile) / subperiod / Harvey-t / DSR ──
## rank-IC 는 python diag(-0.0281)와 동일 축: 패널 sig_date+Ticker 의 fwd_ret_1m 에 조인
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, sig_date := as.Date(sig_date)]
scj <- merge(sc[, .(sig_date = as.Date(sig_date), Ticker = as.character(Ticker), score)],
             pan[, .(sig_date, Ticker = as.character(Ticker), Ret_1m = fwd_ret_1m)],
             by = c("sig_date","Ticker"))
ic_m <- scj[is.finite(Ret_1m) & is.finite(score),
            .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = sig_date][is.finite(ic)]
rank_ic <- mean(ic_m$ic); ic_sd <- sd(ic_m$ic); icir <- rank_ic/ic_sd
harvey_t <- rank_ic / (ic_sd / sqrt(nrow(ic_m)))

## monotonicity: decile 평균 forward return 단조성 (spearman of decile idx vs mean ret)
scj[, dec := as.integer(cut(frank(score)/.N, breaks = seq(0,1,0.1), include.lowest = TRUE)), by = sig_date]
dec_ret <- scj[is.finite(Ret_1m), .(mr = mean(Ret_1m)), by = .(sig_date, dec)][
              , .(mr = mean(mr)), by = dec][order(dec)]
monotonicity <- suppressWarnings(cor(dec_ret$dec, dec_ret$mr, method = "spearman"))

## subperiod stability: 3구간 total SR 부호/크기 일관 (period_returns)
pr <- as.data.table(Q$pr)[, date := as.Date(date)]
sub <- function(lo, hi) { x <- pr[date >= as.Date(lo) & date < as.Date(hi), ret_net]
  if (length(x) < 6) NA_real_ else mean(x)/sd(x)*sqrt(12) }
s1 <- sub("2008-01-01","2015-01-01"); s2 <- sub("2015-01-01","2020-01-01"); s3 <- sub("2020-01-01","2027-01-01")
subs <- c(s1,s2,s3); subs <- subs[is.finite(subs)]
subperiod_stability <- if (length(subs) >= 2) min(subs)/max(subs) else NA_real_

## DSR (chain 진단 — 게이트 아님): active net SR 기반, n_trials=1(단일 primary)
active <- pr$ret_net - as.data.table(Q$pr)$benchmark_ret
sr <- mean(active)/sd(active)
## Bailey-Lopez de Prado DSR: skew/kurt 보정, n_trials=1 → deflation 최소
n <- length(active); sk <- { m<-mean(active); s<-sd(active); mean(((active-m)/s)^3) }
ku <- { m<-mean(active); s<-sd(active); mean(((active-m)/s)^4) }
sr_star <- 0  # 단일 시행 기준선
dsr_z <- (sr - sr_star) * sqrt(n-1) / sqrt(1 - sk*sr + (ku-1)/4*sr^2)
dsr <- pnorm(dsr_z)

cat(sprintf("advisory: rank_ic %+.4f · icir %+.3f · harvey_t %+.3f · monotonicity %+.3f · subperiod %.3f · DSR %.3f\n",
            rank_ic, icir, harvey_t, monotonicity, subperiod_stability, dsr))

## ── alpha_validation.json ─────────────────────────────────────────────────────
av <- list(
  round_id = "WT-D20260813_001_Q90", wt_id = "WT-D20260813_001",
  metric_type = "canonical_screen", selection_type = "chain",
  selection_objective = "canonical_port_t",
  primary_selection = list(
    canonical_port_t_nw_lag3 = as.numeric(Q$res$portfolio_alpha_t_nw_lag3),
    canonical_port_t_pvalue = as.numeric(Q$res$portfolio_alpha_t_pvalue),
    total_net_sr = Q$sr_total, active_ir = as.numeric(Q$res$net_sr),
    cagr = Q$cagr, mdd = Q$mdd, calmar = Q$cagr/Q$mdd,
    turnover_annual = as.numeric(Q$res$turnover_annual), n_months = as.numeric(Q$res$n_months)),
  paired_vs_armA = as.list(verdict$paired_vs_armA),
  negative_control_trim5 = as.list(verdict$trim5_control),
  beta_controlled_alpha = list(
    q90 = as.list(verdict$beta_controlled_alpha$q90),
    armA = as.list(verdict$beta_controlled_alpha$armA)),
  falsification = list(F1 = as.list(fals$F1_tail_hit), F2 = as.list(fals$F2_contrib_concentration),
    F3 = as.list(fals$F3_skew_link), combined = as.list(fals$combined)),
  vol_tilt = fromJSON(file.path(OUT, "q90_beta_tilt.json"))$vol_percentile_selected,
  advisory_diagnostics = list(
    rank_ic = rank_ic, icir = icir, harvey_t_stat = harvey_t, monotonicity = monotonicity,
    subperiod_stability = subperiod_stability, deflated_sharpe_ratio = dsr,
    subperiod_sr = list(p2008_2014 = s1, p2015_2019 = s2, p2020_2026 = s3),
    note = "advisory — 선택 권위 아님(measurement-graduation §3). DSR 는 chain 이므로 진단 산출·기록(게이트 아님)."),
  dual_basis_diag = list(
    cap_w_port_t = as.numeric(Q$res$portfolio_alpha_t_nw_lag3),
    ew_universe_port_t = as.numeric(Q$res$diag_ew_universe$portfolio_alpha_t_nw_lag3),
    ew_universe_oos_approx = as.numeric(Q$res$diag_ew_universe$oos_retention_approx),
    ew_universe_post2017_t = as.numeric(Q$res$diag_ew_universe$post2017_t_nw_lag3),
    note = "EW-유니버스 대비 진단(비바인딩). cap-w 판정 권위 불변. §6 mega-cap 벤치 아티팩트 확인용."),
  graduation_gate_check = list(
    portfolio_alpha_t_nw_HARD_2.95 = list(value = as.numeric(Q$res$portfolio_alpha_t_nw_lag3), pass = as.numeric(Q$res$portfolio_alpha_t_nw_lag3) >= 2.95),
    calmar_HARD_0.64 = list(value = Q$cagr/Q$mdd, pass = (Q$cagr/Q$mdd) >= 0.64),
    note = "자본 tier HARD — forge-authoritative 값에만 적용. canonical 수치로 graduation 선언 금지. 전 게이트 미충족(예상 — 표적 형태 판정 라운드)."),
  method_shopping_log = list(candidates_tried = 4,
    method_log = list(
      list(name = "armA_mean_XGB", rank_ic = 0.0074, total_sr = 0.6039, port_t = 0.6301, selected = FALSE, note = "선행 대조군"),
      list(name = "armB_q10_pinball", rank_ic = 0.0438, total_sr = 0.4371, port_t = -1.3404, selected = FALSE),
      list(name = "armB_q50_pinball", rank_ic = 0.0299, total_sr = 0.5140, port_t = -0.4022, selected = FALSE),
      list(name = "q90_pinball_lgbm", rank_ic = -0.0281, total_sr = 0.6061, port_t = 0.9256, selected = TRUE, note = "본 WT primary — arm B 4-arm 관측 후 도달, 독립 사전등록")),
    note = "선행 4-arm(mean/q10/q50/q90) 관측 이력. judge/graduation 에서 다중검정 맥락으로 소비. arm 들은 같은 패널·피처 공유 = 비독립."),
  verdict = verdict$verdict_overall,
  verdict_detail = list(perf = verdict$verdict_perf, F1 = fals$F1_tail_hit$verdict,
    F2 = fals$F2_contrib_concentration$verdict, F3 = fals$F3_skew_link$verdict))
write_json(av, file.path(OUT, "alpha_validation.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
cat("alpha_validation.json 저장 완료\n")
saveRDS(list(rank_ic=rank_ic, icir=icir, harvey_t=harvey_t, monotonicity=monotonicity,
             subperiod_stability=subperiod_stability, dsr=dsr, dec_ret=dec_ret), file.path(OUT,"advisory_diag.rds"))
