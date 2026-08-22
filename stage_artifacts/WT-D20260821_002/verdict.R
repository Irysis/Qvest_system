## verdict.R — WT-D20260821_002 판정 (PREREG §3 단계 3)
## 전제: gate_lock.json 이 이미 고정됨. 바인딩 프레임 = F3L (사다리 최상위 통과).
## ★F1·F2 는 FRAME_REJECTED_UNDERPOWERED — 이 스크립트도 그 프레임의 평균·t 를 산출하지 않는다.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(xts); library(PerformanceAnalytics)
                                library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
T0 <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z"); cat("[verdict] start ", T0, "\n")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/essence_score.R")           # .essence_dsr (진단)
source("02_Infrastructure/contracts/required_effect_size.R")
source("stage_artifacts/WT-D20260821_002/frame_lib.R")
OUT <- "stage_artifacts/WT-D20260821_002"

LOCK <- fromJSON(file.path(OUT, "gate_lock.json"))
BIND <- LOCK$binding_frame
stopifnot(identical(BIND, "F3L"))
cat(sprintf("[verdict] 잠금 확인: binding_frame = %s\n", BIND))

S  <- readRDS(file.path(OUT, "step0_inputs.rds"))
GS <- readRDS(file.path(OUT, "gate_series.rds"))
frd <- S$frd; bench_dt <- S$bench_dt
sc <- list(armA = S$panels$armA[, .(Date, Ticker, score = as.numeric(score))],
           armB = S$panels$armB[, .(Date, Ticker, score = as.numeric(q50))],
           armC = S$panels$armC[, .(Date, Ticker, score = as.numeric(score))])

## ---------------------------------------------------------------- 1. co-primary paired t
res <- list()
for (arm in c("armA","armB","armC")) {
  r <- frame_screen_bt(sc[[arm]], frd, bench_dt, frame = BIND, cost_bps_oneway = 15,
                       metrics = TRUE, run_id = "FQ233_FRAME_20260821",
                       strategy_id = paste0("FQ233_F3L_", arm))
  px <- xts(r$period_returns$ret_net, order.by = as.Date(r$period_returns$date))
  r$total_sr <- as.numeric(SharpeRatio.annualized(px, Rf = 0, scale = 12, geometric = FALSE))
  r$cagr <- as.numeric(Return.annualized(px, scale = 12, geometric = TRUE))
  r$mdd  <- as.numeric(maxDrawdown(px))
  r$calmar <- as.numeric(CalmarRatio(px, scale = 12))
  res[[arm]] <- r
}
prA <- res$armA$period_returns[, .(date, a = ret_net)]
coprimary <- list()
for (pn in c("c_vs_a", "b_vs_a")) {
  arm <- if (pn == "c_vs_a") "armC" else "armB"
  prX <- res[[arm]]$period_returns[, .(date, x = ret_net)]
  j <- merge(prA, prX, by = "date"); d <- j$x - j$a
  stopifnot(nrow(j) == 198L)
  tt <- nw_t(d)
  g <- GS$G[frame == BIND & pair == pn]
  lab <- if (tt >=  2.0) "SUPPORTED_DISCRETIZATION_MASKED" else
         if (tt <= -2.0) "INFERIOR_POWERED" else
         if (isTRUE(g$mde_annual <= 0.030)) "POWERED_NULL_BREADTH_SCOPED" else "INCONCLUSIVE"
  coprimary[[pn]] <- list(
    pair = pn, arm = arm, frame = BIND, n_months = nrow(j),
    mean_diff_monthly = mean(d), mean_diff_annual_pct = 100*12*mean(d),
    diff_sd_monthly = as.numeric(g$diff_sd_monthly),
    nw3_t = tt, threshold = 2.0,
    mde_annual_pct = 100*as.numeric(g$mde_annual),
    nw_inflation_measured = as.numeric(g$nw_inflation),
    effect_over_mde = abs(mean(d)*12) / as.numeric(g$mde_annual),
    label = lab)
  cat(sprintf("  [%s] 월평균차 %+.5f (연 %+.3f%%p) · NW3 t %+.4f · MDE 연 %.3f%%p → %s\n",
              pn, mean(d), 100*12*mean(d), tt, 100*as.numeric(g$mde_annual), lab))
  coprimary[[pn]]$diff_series <- data.table(date = j$date, d = d)
}

## ---------------------------------------------------------------- 2. 반증 축 2: 왜도 × diff 연속 상호작용
## 왜도 추정기 = r33_profile_stage2.R::skew 자구 승계 (frame_lib.R)
## (2a) 1차 — frd$Ret_1m 월별 횡단면 (R31/R32/R33 인용 근거와 동일 정의)
sk_m <- frd[, .(skew_cs = skew(Ret_1m), n_names = .N,
                disp_cs = stats::sd(Ret_1m)), by = Date][order(Date)]
## (2b) 2차 — .cache/RAWDATA.parquet 일간 수익 파생 (설계 field_dictionary A1 자구)
sk_d <- tryCatch({
  rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
                                   col_select = c("Date","Ticker","Ret")))
  rd[, Date := as.Date(Date)]
  rd <- rd[is.finite(Ret) & Ret > -1 & Ret < 5]
  rd[, ym := format(Date, "%Y%m")]
  ## 월내 종목별 일간 수익 합산이 아니라, 월내 **일별 횡단면 왜도의 월 평균**
  ## (= 일간 축에서 본 횡단면 비대칭. 월간 접기 전 관측 — v8.4 일별 축 정합)
  dsk <- rd[, .(sk_day = skew(Ret), n = .N), by = .(Date, ym)][n >= 50]
  dsk[, .(skew_daily_cs = mean(sk_day, na.rm = TRUE), n_days = .N), by = ym]
}, error = function(e) { cat("  [축2b] RAWDATA 파생 실패:", conditionMessage(e), "\n"); NULL })

axis2 <- list()
for (pn in names(coprimary)) {
  D <- copy(coprimary[[pn]]$diff_series)
  ## (2a)
  X <- merge(D, sk_m[, .(date = Date, skew_cs, disp_cs)], by = "date")
  fit <- lm(d ~ skew_cs, data = X)
  ct  <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3, prewhite = FALSE, adjust = TRUE))
  ## 공동 통제: 분산(disp) 동시 투입 — '단순 변동성 노출 차'로의 재귀속 가능성 점검
  fit2 <- lm(d ~ skew_cs + disp_cs, data = X)
  ct2  <- coeftest(fit2, vcov. = NeweyWest(fit2, lag = 3, prewhite = FALSE, adjust = TRUE))
  a2 <- list(
    source = "monthly_cross_sectional_skew_of_Ret_1m (frd — R31/R32/R33 정의 승계)",
    n = nrow(X),
    skew_mean = mean(X$skew_cs), skew_sd = stats::sd(X$skew_cs),
    slope = unname(ct[2,1]), se_nw3 = unname(ct[2,2]), t_nw3 = unname(ct[2,3]),
    p_nw3 = unname(ct[2,4]),
    slope_ctrl_disp = unname(ct2[2,1]), t_ctrl_disp = unname(ct2[2,3]),
    disp_slope = unname(ct2[3,1]), disp_t = unname(ct2[3,3]),
    ## 해석 보조: 왜도 1sd 이동이 diff 를 연 몇 %p 움직이는가
    effect_per_1sd_skew_annual_pct = 100*12*unname(ct[2,1])*stats::sd(X$skew_cs))
  ## (2b)
  if (!is.null(sk_d)) {
    X2 <- copy(D)[, ym := format(date, "%Y%m")]
    X2 <- merge(X2, sk_d, by = "ym")
    if (nrow(X2) >= 24) {
      f3 <- lm(d ~ skew_daily_cs, data = X2)
      c3 <- coeftest(f3, vcov. = NeweyWest(f3, lag = 3, prewhite = FALSE, adjust = TRUE))
      a2$daily_variant <- list(
        source = "mean within-month DAILY cross-sectional skew (.cache/RAWDATA.parquet — A1 자구)",
        n = nrow(X2), skew_mean = mean(X2$skew_daily_cs), skew_sd = stats::sd(X2$skew_daily_cs),
        slope = unname(c3[2,1]), t_nw3 = unname(c3[2,3]), p_nw3 = unname(c3[2,4]),
        effect_per_1sd_skew_annual_pct = 100*12*unname(c3[2,1])*stats::sd(X2$skew_daily_cs))
    } else a2$daily_variant <- list(status = "unavailable", note = "겹치는 달 < 24")
  } else a2$daily_variant <- list(status = "unavailable", note = "RAWDATA 파생 실패")
  axis2[[pn]] <- a2
  cat(sprintf("  [축2/%s] 월간CS 기울기 %+.5f · NW3 t %+.3f (1sd 왜도 → 연 %+.3f%%p) | 일간CS t %s\n",
              pn, a2$slope, a2$t_nw3, a2$effect_per_1sd_skew_annual_pct,
              if (!is.null(a2$daily_variant$t_nw3)) sprintf("%+.3f", a2$daily_variant$t_nw3) else "NA"))
}

## ---------------------------------------------------------------- 3. secondary: 랭크-기울기 진단
## F3L diff 를 armA 랭크 버킷별 기여로 분해: d_t = Σ_i (w^X_i − w^A_i)·r_i
## 효과가 극단 랭크(top-25 상당)에 집중되면 F3L powered null 이 top-25 국소 효과를 배제하지 못함.
rank_slope <- list()
for (pn in names(coprimary)) {
  arm <- coprimary[[pn]]$arm
  A <- copy(sc$armA)[, .(Date, Ticker, sA = score)]
  X <- copy(sc[[arm]])[, .(Date, Ticker, sX = score)]
  M <- merge(A, X, by = c("Date","Ticker"))
  M <- merge(M, frd[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  setorder(M, Date, -sA); M[, rA := seq_len(.N), by = Date]
  setorder(M, Date, -sX); M[, rX := seq_len(.N), by = Date]
  M[, nD := .N, by = Date]
  M[, wA := (nD - rA) / (nD*(nD-1)/2)]
  M[, wX := (nD - rX) / (nD*(nD-1)/2)]
  M[, contrib := (wX - wA) * Ret_1m]
  ## armA 랭크 버킷 (top-25 를 독립 버킷으로 분리 — 자본 프레임 대응)
  M[, bucket := fifelse(rA <= 25L, "rA_001_025",
                fifelse(rA <= 50L, "rA_026_050",
                fifelse(rA <= 100L, "rA_051_100",
                fifelse(rA <= 200L, "rA_101_200", "rA_201_plus"))))]
  bm <- M[, .(c = sum(contrib)), by = .(Date, bucket)]
  tab <- bm[, .(mean_monthly = mean(c), annual_pct = 100*12*mean(c),
                sd_monthly = stats::sd(c), t_nw3 = nw_t(c), n = .N), by = bucket][order(bucket)]
  tot <- coprimary[[pn]]$mean_diff_monthly
  tab[, share_of_total_diff := mean_monthly / tot]
  rank_slope[[pn]] <- tab
  cat(sprintf("\n  [랭크-기울기/%s] (총 월평균차 %+.5f)\n", pn, tot)); print(tab)
}

## ---------------------------------------------------------------- 4. 병기 의무 (F0 + F3L)
bind_tab <- rbindlist(lapply(c("armA","armB","armC"), function(a) data.table(
  frame = BIND, arm = a, total_sr = res[[a]]$total_sr,
  port_t = as.numeric(res[[a]]$portfolio_alpha_t_nw_lag3),
  port_t_p = as.numeric(res[[a]]$portfolio_alpha_t_pvalue),
  active_ir = as.numeric(res[[a]]$information_ratio),
  net_sr_active = res[[a]]$net_sr,
  cagr = res[[a]]$cagr, mdd = res[[a]]$mdd, calmar = res[[a]]$calmar,
  turnover_annual = res[[a]]$turnover_annual,
  avg_n_names = res[[a]]$avg_n_names, eff_n_names = res[[a]]$avg_eff_n_names)))
cat("\n=== 병기: 바인딩 프레임 F3L arm별 (검출 장치 — 운용 성과 주장 아님) ===\n"); print(bind_tab)

## F0 병기 (기존 프레임 — 선행 라운드 대조)
f0_tab <- rbindlist(lapply(c("armA","armB","armC"), function(a) {
  r <- frame_screen_bt(sc[[a]], frd, bench_dt, frame = "F0", cost_bps_oneway = 15, metrics = TRUE,
                       run_id = "FQ233_FRAME_20260821_F0", strategy_id = paste0("F0_", a))
  px <- xts(r$period_returns$ret_net, order.by = as.Date(r$period_returns$date))
  data.table(frame = "F0", arm = a,
             total_sr = as.numeric(SharpeRatio.annualized(px, Rf=0, scale=12, geometric=FALSE)),
             port_t = as.numeric(r$portfolio_alpha_t_nw_lag3),
             mdd = as.numeric(maxDrawdown(px)),
             calmar = as.numeric(CalmarRatio(px, scale = 12)),
             turnover_annual = r$turnover_annual)
}))
cat("\n=== 병기: F0 (top-25 EW, 기존 프레임) ===\n"); print(f0_tab)

## ---------------------------------------------------------------- 5. DSR 진단 (chain — 게이트 아님)
dsr <- sapply(c("armA","armB","armC"), function(a) {
  act <- res[[a]]$period_returns[, ret_net - benchmark_ret]; act <- act[is.finite(act)]
  if (length(act) < 12 || stats::sd(act) <= 0) return(NA_real_)
  mu <- mean(act); s <- stats::sd(act)
  .essence_dsr(mu/s*sqrt(12), length(act), 1, mean(((act-mu)/s)^3), mean(((act-mu)/s)^4), A = 12)
})
cat("\n[진단] DSR(n_trials=1, chain — PSR(0) 퇴화, 게이트 부적용):\n"); print(dsr)

## ---------------------------------------------------------------- 6. F3 (롱숏 원안) 진단 기록
f3_diag <- list(
  status = "diagnostic_only_not_binding",
  reason = "설계 원안 F3(센터드-랭크 Σ|w|=1)는 음의 가중 포함 = 롱숏. 도훈 mandate 2026-06-11 '롱숏 불허 — 검증 단계 포함 전면 long-only, L/S 수치는 판정 근거 사용 금지'. 같은 mandate 의 사상 규칙에 따라 long-only 사상판 F3L 로 사다리 3순위를 대체(PREREG §7).",
  gate_only = as.list(GS$G[frame == "F3", .(pair, diff_sd_monthly, nw_inflation, mde_annual)]),
  note = "F3 의 paired t 는 산출하지 않았다 — 판정 바인딩 금지 대상의 판정량을 만들면 그 자체가 유혹 표면이 된다(armC 사전등록 §3 규율 승계).")

T1 <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z")
write_json(list(
  wt_id = "WT-D20260821_002", round_id = "FQ233_FRAME_20260821",
  step = "verdict", prereg = "PREREG_WT002_20260821.md", gate_lock = "gate_lock.json",
  started_at = T0, finished_at = T1,
  metric_type = "canonical_screen_frame", selection_type = "chain",
  binding_frame = BIND, binding_rule = LOCK$binding_rule_applied,
  coprimary = lapply(coprimary, function(x) { x$diff_series <- NULL; x }),
  axis1 = LOCK$axis1_falsification,
  axis2_skew_interaction = axis2,
  secondary_rank_slope = rank_slope,
  frame_metrics_binding = bind_tab, frame_metrics_F0 = f0_tab,
  dsr_diag_n_trials_1 = as.list(dsr),
  f3_longshort_diagnostic = f3_diag),
  file.path(OUT, "verdict_result.json"), auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null")
saveRDS(list(res = res, coprimary = coprimary, axis2 = axis2, rank_slope = rank_slope,
             sk_m = sk_m, sk_d = sk_d, bind_tab = bind_tab, f0_tab = f0_tab),
        file.path(OUT, "verdict_full.rds"))
cat("\n[verdict] end ", T1, " — 저장: verdict_result.json · verdict_full.rds\n")
