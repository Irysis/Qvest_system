#!/usr/bin/env Rscript
# overlay_candidate_ab_lh.R — OVERLAY_CANDIDATE 큐 첫 케이스 실측: LH/D2 loser-augment × regime overlay A/B
#   (감사 CAP-P1-1, SC-03/04 소비 배관 — 큐: 02_Infrastructure/regime/overlay_candidate_queue.R)
#
# 대상: LH_D2_loser_augment (smartbeta allstock loser-harvest qm/D0.30/lam0.85 + iskew/amihud/gov 배제,
#       2e8 topn25, screen-tier 3/3). weights = 04_Research/factor_rotation/smartbeta_allstock/D2_winner_weights.parquet
#       (D2_export_weights.py 산출, D2_forge_bridge.R로 contract-grade 검증 완료 PORT_t +3.703).
# 하네스: 02_Infrastructure/ops/auto_regime_overlay_ab.R의 CAT_EXPOSURE/voltarget/이전월-lag 규약 재사용
#       (상수 복제 금지 — NORUN 소싱). 측정 = weighted_screen_bt(=build_benchmark_compare NW lag-3 계약경로,
#       metric_type="weighted_screen"). §1 real-computation 준수, proxy 손계산 없음.
# 시나리오:
#   bare          : D2 그대로 (검증앵커 — D2_forge_result.rds 재현돼야 함)
#   uni_cat       : unified_regime_signal(MSM+FRED+KTRI+VEA) Category → CAT_EXPOSURE 디리스크. 신호 = 직전월(m-1).
#   uni_cat_lag1  : ★clean-timing +1 lag 스트레스(신호 m-2) — 07-02 교훈(동월누출은 placebo로 못 잡음) 의무.
#   voltgt        : trailing 12m vol-target(strictly before, 구조적 PIT).
#   voltgt_lag1   : vol-target 노출 1개월 추가 지연 스트레스.
# 주의(정직 라벨): unified_regime_signal.parquet의 월별 Category가 완전 walk-forward 재적합인지 미보증 —
#   그래서 lag1 스트레스가 의무이고, 결과는 screen-tier A/B이지 자본게이트 통과가 아님.
# 기대치 낮음(KR long-only 시장타이밍 4중 settled-negative — project-pg2-offense-overlay-settled) → cheap-kill 목적.
#
# [2026-07-04 A7a] 오버레이 회전비용 반영 재측정 (전 라운드 deferred — 채택 판단의 전제):
#   각 오버레이 시나리오에 월별 |Δexposure|×15bps(one-way)를 추가 차감한 `<nm>_cost` 변형을 병행 산출.
#   근거: cost_model v2.4 (delta-based — 종목별 Δ보유명목 절대값에 레그당 과금, 2026-06-11 도훈 confirm).
#     exposure 스칼라의 월간 변화 |Δe|는 포트 명목의 |Δe| 비율만큼 매수/매도 1개 레그 발생 → |Δe|×15bps.
#   PG2 recovery-override 교훈 정합 (project-pg2-recovery-override-enhancement): "overlay 회전강화는
#     |Δinv|×15bps 필수" — 동일 규약을 본 A/B에 적용. bare는 exposure≡1 → Δ=0 → 비용 0 (무영향).
#   첫 월 Δ는 0 처리(fill=첫 exposure — 종목레벨 초기 진입비용 traded=1은 weighted_screen_bt가 이미 과금).
#   기존 무비용 수치는 cost_applied=FALSE 행으로 그대로 보존(비교용) + 구 JSON은 *_nocost_20260703 백업.
#   측정경로: 비용 차감 후 시계열을 동일 계약경로 build_benchmark_compare(NW lag-3)로 재측정 —
#     abs_SR/CAGR/MDD 표시식은 weighted_screen_bt L82-85와 자구동일 미러(측정 일관성, proxy 신설 아님).
#
# 실행: Rscript 02_Infrastructure/regime/overlay_candidate_ab_lh.R
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1)
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)

Sys.setenv(QVEST_REGIME_AB_NORUN = "1")   # 하네스 함수/상수만 재사용 (book 캐리어 자동실행 차단)
source("02_Infrastructure/ops/auto_regime_overlay_ab.R")  # CAT_EXPOSURE / VT_* / .prev_month_ym / build_voltarget_exposure / weighted_screen_bt

D2_DIR <- "04_Research/factor_rotation/smartbeta_allstock"
CAND_ID <- "LH_D2_loser_augment"
AB_RESULT_DIR <- "06_Registry/overlay_ab_results"

run_lh_overlay_ab <- function(cost_bps = 15) {
  W <- as.data.table(read_parquet(file.path(D2_DIR, "D2_winner_weights.parquet")))
  R <- as.data.table(read_parquet(file.path(D2_DIR, "D2_returns.parquet")))
  B <- as.data.table(read_parquet(file.path(D2_DIR, "D2_bench.parquet")))
  setnames(W, "ym", "Date"); setnames(R, "ym", "Date"); setnames(B, "ym", "Date")
  W[, Date := as.Date(paste0(Date, "-01"))]
  R[, Date := as.Date(paste0(Date, "-01"))]
  B[, Date := as.Date(paste0(Date, "-01"))]
  R <- R[, .(Date, Ticker, Ret_1m)]

  # bare 포트 gross (voltarget 입력용) — 가중 그대로, 비용 전 (D2 weights는 월별 합1)
  WR <- merge(W, R, by = c("Date", "Ticker"), all.x = TRUE); WR[is.na(Ret_1m), Ret_1m := 0]
  bare_gross <- WR[, .(r = sum(w / sum(w) * Ret_1m)), by = Date]; setorder(bare_gross, Date)

  # unified regime Category → CAT_EXPOSURE (하네스 규약: 신호 = 직전월. lag1 스트레스 = 전전월)
  u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[
    , .(ym_sig = as.character(YM), Category = as.character(Category))]
  build_uni <- function(dates, extra_lag = 0L) {
    dd <- data.table(Date = sort(unique(dates)))
    dd[, ym_sig := .prev_month_ym(Date)]
    if (extra_lag > 0L) for (k in seq_len(extra_lag)) dd[, ym_sig := .prev_month_ym(as.Date(paste0(ym_sig, "-01")))]
    dd[u, on = "ym_sig", Category := i.Category]
    dd[, exposure := as.numeric(CAT_EXPOSURE[Category])]
    dd[is.na(exposure), exposure := 1.0]
    dd
  }
  uni0 <- build_uni(W$Date, extra_lag = 0L)   # 직전월 신호 (하네스 기본)
  uni1 <- build_uni(W$Date, extra_lag = 1L)   # +1 lag 스트레스 (전전월)
  vt0 <- as.data.table(build_voltarget_exposure(copy(bare_gross)))
  vt1 <- copy(vt0); vt1[, exposure := shift(exposure, 1L, fill = 1.0)]   # +1 lag 스트레스

  scen <- list(bare = NULL,
               uni_cat = uni0[, .(Date, exposure)], uni_cat_lag1 = uni1[, .(Date, exposure)],
               voltgt = vt0, voltgt_lag1 = vt1)

  oos_v2 <- function(pr) {   # anchored 3분할 {55/65/75} 중앙값 (essence_score v2 규약, active 기준)
    a <- pr$ret_net - pr$benchmark_ret
    f1 <- function(frac) {
      n <- length(a); k <- floor(n * frac)
      is_sr <- mean(a[1:k]) / sd(a[1:k]) * sqrt(12)
      oos_sr <- mean(a[(k + 1):n]) / sd(a[(k + 1):n]) * sqrt(12)
      if (!is.finite(is_sr) || is_sr <= 0) return(NA_real_)
      oos_sr / is_sr
    }
    median(sapply(c(.55, .65, .75), f1), na.rm = TRUE)
  }

  # [A7a] 오버레이 회전비용 시리즈: |Δexposure|×bps one-way (cost_model v2.4 delta-based 정합).
  #   첫 월 fill=exposure[1] → Δ=0 (종목레벨 초기 진입 traded=1은 weighted_screen_bt가 이미 과금).
  overlay_cost_dt <- function(exp_dt, bps) {
    e <- as.data.table(exp_dt)[, .(Date, exposure)]; setorder(e, Date)
    e[, d_exp := abs(exposure - shift(exposure, 1L, fill = exposure[1]))]
    e[, ov_cost := d_exp * bps / 1e4]
    e[, .(Date, d_exp, ov_cost)]
  }
  # [A7a] 비용 차감 후 동일 계약경로(build_benchmark_compare NW lag-3) 재측정.
  #   abs_SR/CAGR/MDD 식은 weighted_screen_bt L82-85 자구동일 미러(측정 일관성 — proxy 신설 아님).
  remeasure_with_overlay_cost <- function(r, exp_dt, bps, nm) {
    oc <- overlay_cost_dt(exp_dt, bps)
    pr <- copy(r$period_returns)   # date, ret_net, benchmark_ret (무비용 계약 산출)
    pr[oc, on = c(date = "Date"), `:=`(d_exp = i.d_exp, ov_cost = i.ov_cost)]
    pr[is.na(ov_cost), `:=`(d_exp = 0, ov_cost = 0)]
    pr[, ret_net := ret_net - ov_cost]
    rid <- paste0("lh_d2_", nm, "_cost")
    bc <- build_benchmark_compare(
      data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly"),
      data.table(date = pr$date, benchmark_ret = pr$benchmark_ret, benchmark_id = "KOSPI200_total_return"),
      run_id = rid, strategy_id = rid, annualization_factor = 12)
    getbc <- function(mn) { v <- bc[metric_name == mn, active_value]; if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
    active <- pr$ret_net - pr$benchmark_ret
    .mdd <- function(x) { cum <- cumprod(1 + x); min(cum / cummax(cum) - 1, na.rm = TRUE) }
    abs_sr <- mean(pr$ret_net) / stats::sd(pr$ret_net) * sqrt(12)
    cagr <- (prod(1 + pr$ret_net)^(12 / nrow(pr)) - 1)
    mdd <- .mdd(pr$ret_net)
    list(
      row = data.table(
        scenario = paste0(nm, "_cost"), n_months = nrow(pr),
        abs_SR = abs_sr, abs_CAGR = cagr, abs_MDD = mdd,
        IR = getbc("Information_Ratio"), PORT_t = getbc("Portfolio_Alpha_t_NW_lag3"),
        active_SR = mean(active) / stats::sd(active) * sqrt(12),
        oos_ret_v2 = oos_v2(pr),
        calmar = { m <- abs(mdd); if (m > 0) cagr / m else NA_real_ },
        avg_exposure = mean(as.data.table(exp_dt)$exposure, na.rm = TRUE),
        cost_applied = TRUE, avg_abs_dexp_m = mean(pr$d_exp),
        ov_cost_ann_bps = mean(pr$ov_cost) * 12 * 1e4),
      pr = pr)
  }

  res <- list()
  for (nm in names(scen)) {
    r <- weighted_screen_bt(W, R, B, cost_bps_oneway = cost_bps,
                            run_id = paste0("lh_d2_", nm), strategy_id = paste0("lh_d2_", nm),
                            exposure_dt = scen[[nm]])
    avg_exp <- if (is.null(scen[[nm]])) 1.0 else mean(scen[[nm]]$exposure, na.rm = TRUE)
    res[[nm]] <- data.table(
      scenario = nm, n_months = r$n_months,
      abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr, abs_MDD = r$abs_mdd,
      IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3,
      active_SR = r$net_sr, oos_ret_v2 = oos_v2(r$period_returns),
      calmar = { cagr <- r$abs_cagr; mdd <- abs(r$abs_mdd); if (mdd > 0) cagr / mdd else NA_real_ },
      avg_exposure = avg_exp,
      cost_applied = FALSE, avg_abs_dexp_m = 0, ov_cost_ann_bps = 0)
    if (!is.null(scen[[nm]])) {   # [A7a] 오버레이 시나리오만 회전비용 변형 병행 (bare Δ≡0)
      rc <- remeasure_with_overlay_cost(r, scen[[nm]], cost_bps, nm)
      res[[paste0(nm, "_cost")]] <- rc$row
      res[[nm]][, avg_abs_dexp_m := rc$row$avg_abs_dexp_m]   # 무비용 행에도 Δ 크기 참고 기재
      res[[nm]][, ov_cost_ann_bps := rc$row$ov_cost_ann_bps]
      res[[nm]][, cost_applied := FALSE]
    }
  }
  tab <- rbindlist(res, fill = TRUE)

  # AX-001 v2: crisis-conditional — 신호가 CRISIS/CAUTION 라벨한 월의 평균 수익 (bare vs uni 노출)
  cr <- merge(bare_gross, uni0[, .(Date, Category, uni_e = exposure)], by = "Date", all.x = TRUE)
  cr[is.na(uni_e), uni_e := 1.0]
  cr[, crisis := Category %in% c("CRISIS", "CAUTION")]
  crisis_tab <- cr[, .(n = .N, bare_mean = mean(r), uni_mean = mean(r * uni_e)), by = crisis]

  list(tab = tab, crisis = crisis_tab)
}

if (sys.nframe() == 0L && Sys.getenv("QVEST_LH_AB_NORUN") != "1") {
  cat("\n##### OVERLAY_CANDIDATE 첫 케이스 A/B — LH/D2 loser-augment × regime overlay (+1 lag 스트레스 의무) #####\n")
  out <- run_lh_overlay_ab()
  cat("\n=== 시나리오 비교 (weighted_screen_bt / build_benchmark_compare NW lag-3, metric_type=weighted_screen) ===\n")
  print(out$tab, digits = 4)
  cat("\n=== AX-001 crisis-conditional (uni 신호 CRISIS/CAUTION 라벨 월) 월평균 gross ===\n")
  print(out$crisis, digits = 4)

  bare <- out$tab[scenario == "bare"]
  lag_survive <- function(base_nm, lag_nm) {
    b <- out$tab[scenario == base_nm]; l <- out$tab[scenario == lag_nm]
    # 생존 정의: lag1에서도 bare 대비 MDD 완화 유지 AND PORT_t가 bare 대비 유의 열화 없음(개선분 부호 유지)
    list(mdd_improve_base = bare$abs_MDD - b$abs_MDD, mdd_improve_lag1 = bare$abs_MDD - l$abs_MDD,
         dSR_base = b$abs_SR - bare$abs_SR, dSR_lag1 = l$abs_SR - bare$abs_SR)
  }
  s_uni <- lag_survive("uni_cat", "uni_cat_lag1"); s_vt <- lag_survive("voltgt", "voltgt_lag1")
  s_uni_c <- lag_survive("uni_cat_cost", "uni_cat_lag1_cost"); s_vt_c <- lag_survive("voltgt_cost", "voltgt_lag1_cost")
  cat(sprintf("\n[lag1 스트레스] uni_cat: ΔMDD(완화,+가 개선) base %+.3f → lag1 %+.3f | ΔSR base %+.3f → lag1 %+.3f\n",
              -s_uni$mdd_improve_base, -s_uni$mdd_improve_lag1, s_uni$dSR_base, s_uni$dSR_lag1))
  cat(sprintf("[lag1 스트레스] voltgt : ΔMDD(완화,+가 개선) base %+.3f → lag1 %+.3f | ΔSR base %+.3f → lag1 %+.3f\n",
              -s_vt$mdd_improve_base, -s_vt$mdd_improve_lag1, s_vt$dSR_base, s_vt$dSR_lag1))
  cat(sprintf("[lag1+cost ] uni_cat: ΔMDD base %+.3f → lag1 %+.3f | ΔSR base %+.3f → lag1 %+.3f\n",
              -s_uni_c$mdd_improve_base, -s_uni_c$mdd_improve_lag1, s_uni_c$dSR_base, s_uni_c$dSR_lag1))
  cat(sprintf("[lag1+cost ] voltgt : ΔMDD base %+.3f → lag1 %+.3f | ΔSR base %+.3f → lag1 %+.3f\n",
              -s_vt_c$mdd_improve_base, -s_vt_c$mdd_improve_lag1, s_vt_c$dSR_base, s_vt_c$dSR_lag1))

  # [A7a] 신구 대비 — 비용 반영 전/후 (오버레이 시나리오만)
  cat("\n=== [A7a] 오버레이 회전비용(|Δexposure|×15bps one-way) 반영 신구 대비 ===\n")
  ov_names <- setdiff(out$tab[cost_applied == FALSE & scenario != "bare", scenario], character(0))
  cmp <- rbindlist(lapply(ov_names, function(nm) {
    a <- out$tab[scenario == nm]; b <- out$tab[scenario == paste0(nm, "_cost")]
    data.table(scenario = nm, avg_abs_dexp_m = a$avg_abs_dexp_m, ov_cost_ann_bps = a$ov_cost_ann_bps,
               PORT_t_nocost = a$PORT_t, PORT_t_cost = b$PORT_t, d_PORT_t = b$PORT_t - a$PORT_t,
               calmar_nocost = a$calmar, calmar_cost = b$calmar, d_calmar = b$calmar - a$calmar,
               oos_nocost = a$oos_ret_v2, oos_cost = b$oos_ret_v2, d_oos = b$oos_ret_v2 - a$oos_ret_v2,
               MDD_nocost = a$abs_MDD, MDD_cost = b$abs_MDD, d_MDD = b$abs_MDD - a$abs_MDD)
  }))
  print(cmp, digits = 4)

  dir.create(AB_RESULT_DIR, showWarnings = FALSE, recursive = TRUE)
  result <- list(
    candidate_id = CAND_ID,
    measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    metric_type = "weighted_screen",
    harness = "02_Infrastructure/regime/overlay_candidate_ab_lh.R (auto_regime_overlay_ab 규약 재사용)",
    cost_bps_oneway = 15,
    overlay_cost_model = paste("[A7a 2026-07-04] *_cost 시나리오 = 월별 |Δexposure|×15bps one-way 추가 차감",
                               "(cost_model v2.4 delta-based 정합 — 레그당 과금. PG2 recovery-override 교훈",
                               "'overlay 회전강화는 |Δinv|×15bps 필수' 동일 규약). 첫 월 Δ=0(fill=첫 exposure).",
                               "cost_applied=FALSE 행 = 기존 무비용 수치 보존(비교용, 구본 백업 *_nocost_20260703.json)."),
    note = paste("screen-tier A/B — 자본게이트 아님. cost_applied=FALSE 행은 오버레이 리밸 비용 미반영(구 라벨 유지),",
                 "*_cost 행이 회전비용 반영 재측정. unified_regime_signal walk-forward 미보증 → lag1 스트레스 의무 반영."),
    scenarios = out$tab,
    cost_comparison = cmp,
    crisis_conditional = out$crisis,
    lag1_stress = list(uni_cat = s_uni, voltgt = s_vt,
                       uni_cat_cost = s_uni_c, voltgt_cost = s_vt_c)
  )
  write_json(result, file.path(AB_RESULT_DIR, paste0(CAND_ID, ".json")),
             auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
  fwrite(out$tab, file.path(AB_RESULT_DIR, paste0(CAND_ID, "_scenarios.csv")))
  cat(sprintf("\n[ab] wrote %s/%s.json (+_scenarios.csv) — 큐 갱신은 overlay_candidate_queue.R 재실행\n",
              AB_RESULT_DIR, CAND_ID))
}
