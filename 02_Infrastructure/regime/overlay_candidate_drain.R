#!/usr/bin/env Rscript
# overlay_candidate_drain.R — OVERLAY_CANDIDATE 큐 generic 드레인 러너 (M8 staged, 2026-07-10)
#
# 목적: 06_Registry/overlay_candidate_queue.json 의 엔트리 1건을 인자로 받아, overlay_candidate_ab_lh.R
#   (LH_D2 1회분 하드코딩)의 측정 규약을 *동일하게* 일반화 적용하고 결과 JSON 기록 + 큐 status 갱신.
#
# 측정 규약 (= overlay_candidate_ab_lh.R 재현앵커 — LH_D2 재현 대조로 검증됨):
#   캐리어 = 후보 전략 자체(base). 오버레이 = regime exposure 스케줄 A/B.
#   시나리오: bare / uni_cat(직전월 신호) / uni_cat_lag1(+1 lag 스트레스) / voltgt(trailing 12m) /
#             voltgt_lag1 — 각 오버레이에 *_cost(|Δexposure|×15bps one-way, cost_model v2.4 delta-based) 병행.
#   ※ 임무 명세의 "base=현 PG2 book recon" 표현과 달리, 본 큐의 검증앵커(LH_D2 기존 결과: bare PORT_t 3.70 =
#     D2 자체가 base)와 큐 consumer_ref 규약은 '후보=캐리어' 구조 — 재현 대조가 승인 기준이므로 이 규약을 따름.
#
# v8.x 측정 규율 (proxy 손계산 없음):
#   - 실측 경로: weighted_screen_bt()(adapter A) 또는 build_benchmark_compare()(NW lag-3) 직접 — §1 real-computation.
#   - adapter B의 daily→monthly 집계는 PerformanceAnalytics 표준(xts::apply.monthly + Return.cumulative)만 사용.
#   - abs_SR/CAGR/MDD 표시식은 weighted_screen_bt L82-85 자구동일 미러(측정 일관성 — proxy 신설 아님).
#
# 오버레이 PIT 3종 의무 (BearProb 실사고 재발방지, pit.md C5):
#   ① overlay_pit_guard: assert_overlay_pit() HARD — 신호 컷오프(신호월 말 = 신호월+1개월 첫날)가
#      홀딩월 첫날 이하인지 전 행 검사 (uni0/uni1/voltgt).
#   ② lag1 스트레스: uni_cat_lag1 / voltgt_lag1 — base 대비 개선분 붕괴 시 동월 누출 의심.
#   ③ strict-PIT A/B: uni exposure를 명시적 strict 컷오프(Date < first-day-of-holding-month, 신호월 ≤ 직전월)로
#      독립 재구축해 SR 대조(overlay_lookahead_ab, 인플레>5% → LOOK-AHEAD 의심 flag).
#
# 판정 통계: paired 증분 NW-t(lag-3, .nw_t_mean — contract-grade) on (scenario ret_net − bare ret_net),
#   ΔSR/ΔMDD/ΔPORT_t 병기. SR 비율 비교 아님. 결과 = screen/진단 계층 — capital-grade 주장 금지.
#
# adapters (후보 신호 로드):
#   A "weights_parquet" : 엔트리에 weights/returns/bench parquet 존재(LH_D2) → weighted_screen_bt 경로
#                          (overlay_candidate_ab_lh.R 자구동일).
#   B "bt_result_rds"   : source=alpha_search_manifest → bt_result.rds(10-component)의 period_returns(daily)
#                          + benchmark_returns를 monthly 집계 후 동일 계약경로 측정. exposure는 ret_net×e
#                          (weighted_screen_bt L65 규약 동일 — cash@0 곱셈 노출).
#
# 실행: Rscript 02_Infrastructure/regime/overlay_candidate_drain.R <candidate_id> \
#         [--suffix=_xxx] [--no-queue-update] [--queue=path] [--result-dir=path] [--cost-bps=15]
#   소싱 전용(테스트): Sys.setenv(QVEST_DRAIN_NORUN="1") 후 source().
suppressMessages({ library(data.table); library(arrow); library(jsonlite)
                   library(xts); library(PerformanceAnalytics) })
setDTthreads(1)
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)

Sys.setenv(QVEST_REGIME_AB_NORUN = "1")   # 하네스 함수/상수만 재사용 (book 캐리어 자동실행 차단)
source("02_Infrastructure/ops/auto_regime_overlay_ab.R")  # CAT_EXPOSURE / VT_* / .prev_month_ym / build_voltarget_exposure / weighted_screen_bt / build_benchmark_compare / .nw_t_mean
source("02_Infrastructure/validation/overlay_pit_guard.R") # assert_overlay_pit / overlay_lookahead_ab

DRAIN_QUEUE_PATH_DEFAULT <- "06_Registry/overlay_candidate_queue.json"
DRAIN_RESULT_DIR_DEFAULT <- "06_Registry/overlay_ab_results"
DRAIN_HARNESS_ID <- "02_Infrastructure/regime/overlay_candidate_drain.R (overlay_candidate_ab_lh 규약 generic화)"

# adapter A 데이터 경로 오버라이드 (weights parquet 계열 — 엔트리에 명시 필드 없을 때)
DRAIN_ADAPTER_OVERRIDES <- list(
  LH_D2_loser_augment = list(
    adapter = "weights_parquet",
    weights_path = "04_Research/factor_rotation/smartbeta_allstock/D2_winner_weights.parquet",
    returns_path = "04_Research/factor_rotation/smartbeta_allstock/D2_returns.parquet",
    bench_path   = "04_Research/factor_rotation/smartbeta_allstock/D2_bench.parquet")
)

# ---------------------------------------------------------------------------
# 공용 통계 (overlay_candidate_ab_lh.R 자구동일)
# ---------------------------------------------------------------------------
drain_oos_v2 <- function(pr) {   # anchored 3분할 {55/65/75} 중앙값 (essence_score v2 규약, active 기준)
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

# 오버레이 회전비용: |Δexposure|×bps one-way (cost_model v2.4 delta-based). 첫 월 Δ=0(fill=첫 exposure).
drain_overlay_cost_dt <- function(exp_dt, bps) {
  e <- as.data.table(exp_dt)[, .(Date, exposure)]; setorder(e, Date)
  e[, d_exp := abs(exposure - shift(exposure, 1L, fill = exposure[1]))]
  e[, ov_cost := d_exp * bps / 1e4]
  e[, .(Date, d_exp, ov_cost)]
}

# 시나리오 행 빌드 — build_benchmark_compare(NW lag-3) 계약경로. abs 표시식 = weighted_screen_bt L82-85 미러.
drain_measure_pr <- function(pr, rid, scen_name, avg_exposure = 1.0,
                             cost_applied = FALSE, avg_abs_dexp_m = 0, ov_cost_ann_bps = 0) {
  pr <- as.data.table(pr)[, .(date, ret_net, benchmark_ret)]; setorder(pr, date)
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
  list(row = data.table(
         scenario = scen_name, n_months = nrow(pr),
         abs_SR = abs_sr, abs_CAGR = cagr, abs_MDD = mdd,
         IR = getbc("Information_Ratio"), PORT_t = getbc("Portfolio_Alpha_t_NW_lag3"),
         active_SR = mean(active) / stats::sd(active) * sqrt(12),
         oos_ret_v2 = drain_oos_v2(pr),
         calmar = { m <- abs(mdd); if (m > 0) cagr / m else NA_real_ },
         avg_exposure = avg_exposure,
         cost_applied = cost_applied, avg_abs_dexp_m = avg_abs_dexp_m, ov_cost_ann_bps = ov_cost_ann_bps),
       pr = pr)
}

# 비용 차감 후 동일 계약경로 재측정 (overlay_candidate_ab_lh.R remeasure_with_overlay_cost 자구동일 로직)
drain_remeasure_with_cost <- function(pr_scen, exp_dt, bps, rid_prefix, nm) {
  oc <- drain_overlay_cost_dt(exp_dt, bps)
  pr <- as.data.table(copy(pr_scen))
  pr[oc, on = c(date = "Date"), `:=`(d_exp = i.d_exp, ov_cost = i.ov_cost)]
  pr[is.na(ov_cost), `:=`(d_exp = 0, ov_cost = 0)]
  pr[, ret_net := ret_net - ov_cost]
  m <- drain_measure_pr(pr, paste0(rid_prefix, nm, "_cost"), paste0(nm, "_cost"),
                        avg_exposure = mean(as.data.table(exp_dt)$exposure, na.rm = TRUE),
                        cost_applied = TRUE,
                        avg_abs_dexp_m = mean(pr$d_exp), ov_cost_ann_bps = mean(pr$ov_cost) * 12 * 1e4)
  m
}

# ---------------------------------------------------------------------------
# regime 신호 (overlay_candidate_ab_lh.R 자구동일: 신호 = 직전월(m-1), lag1 = 전전월(m-2))
# ---------------------------------------------------------------------------
.month_add <- function(d, k = 1L) {
  fm <- as.Date(format(as.Date(d), "%Y-%m-01"))
  y <- as.integer(format(fm, "%Y")); m <- as.integer(format(fm, "%m"))
  m2 <- m + k; y2 <- y + (m2 - 1L) %/% 12L; m2 <- ((m2 - 1L) %% 12L) + 1L
  as.Date(sprintf("%04d-%02d-01", y2, m2))
}

drain_load_uni <- function() {
  as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[
    , .(ym_sig = as.character(YM), Category = as.character(Category))]
}

drain_build_uni <- function(u, dates, extra_lag = 0L) {
  dd <- data.table(Date = sort(unique(dates)))
  dd[, ym_sig := .prev_month_ym(Date)]
  if (extra_lag > 0L) for (k in seq_len(extra_lag)) dd[, ym_sig := .prev_month_ym(as.Date(paste0(ym_sig, "-01")))]
  dd[u, on = "ym_sig", Category := i.Category]
  dd[, exposure := as.numeric(CAT_EXPOSURE[Category])]
  dd[is.na(exposure), exposure := 1.0]
  dd
}

# ---------------------------------------------------------------------------
# adapters — 후보 데이터 로드
# ---------------------------------------------------------------------------
drain_resolve_adapter <- function(entry) {
  ov <- DRAIN_ADAPTER_OVERRIDES[[entry$id]]
  wp <- entry$weights_path %||% ov$weights_path
  if (!is.null(wp)) {
    return(list(adapter = "weights_parquet",
                weights_path = wp,
                returns_path = entry$returns_path %||% ov$returns_path,
                bench_path   = entry$bench_path %||% ov$bench_path))
  }
  if (identical(entry$source, "alpha_search_manifest")) {
    bt <- entry$bt_result_path
    if (is.null(bt) || is.na(bt) || !nzchar(bt) || !file.exists(bt)) {
      cand <- file.path(dirname(entry$source_path), "bt_result.rds")
      bt <- if (file.exists(cand)) cand else NA_character_
    }
    return(list(adapter = "bt_result_rds", bt_result_path = bt))
  }
  list(adapter = "unknown")
}

# adapter A: weights parquet → weighted_screen_bt 입력 (LH_D2 자구동일 전처리)
drain_load_weights_parquet <- function(ad) {
  W <- as.data.table(read_parquet(ad$weights_path))
  R <- as.data.table(read_parquet(ad$returns_path))
  B <- as.data.table(read_parquet(ad$bench_path))
  setnames(W, "ym", "Date"); setnames(R, "ym", "Date"); setnames(B, "ym", "Date")
  W[, Date := as.Date(paste0(Date, "-01"))]
  R[, Date := as.Date(paste0(Date, "-01"))]
  B[, Date := as.Date(paste0(Date, "-01"))]
  R <- R[, .(Date, Ticker, Ret_1m)]
  WR <- merge(W, R, by = c("Date", "Ticker"), all.x = TRUE); WR[is.na(Ret_1m), Ret_1m := 0]
  bare_gross <- WR[, .(r = sum(w / sum(w) * Ret_1m)), by = Date]; setorder(bare_gross, Date)
  list(mode = "A", W = W, R = R, B = B, bare_gross = bare_gross, dates = sort(unique(W$Date)))
}

# adapter B: bt_result.rds → monthly pr (PerformanceAnalytics 표준 집계만 — 자체합성 없음)
drain_load_bt_result <- function(ad) {
  if (is.na(ad$bt_result_path)) stop("[drain] bt_result.rds not found for adapter bt_result_rds")
  bt <- readRDS(ad$bt_result_path)
  pr <- as.data.table(bt$period_returns); bm <- as.data.table(bt$benchmark_returns)
  pr[, date := as.Date(date)]; bm[, date := as.Date(date)]
  agg <- function(dt, col) {
    x <- xts::xts(dt[[col]], order.by = dt$date)
    m <- xts::apply.monthly(x, PerformanceAnalytics::Return.cumulative)
    data.table(Date = as.Date(format(zoo::index(m), "%Y-%m-01")), v = as.numeric(m))
  }
  freq <- tolower(as.character(pr$frequency[1] %||% "monthly"))
  if (freq == "daily") {
    net <- agg(pr, "ret_net"); gro <- agg(pr, "ret_gross"); ben <- agg(bm, "benchmark_ret")
  } else {
    net <- data.table(Date = as.Date(format(pr$date, "%Y-%m-01")), v = pr$ret_net)
    gro <- data.table(Date = as.Date(format(pr$date, "%Y-%m-01")), v = pr$ret_gross)
    ben <- data.table(Date = as.Date(format(bm$date, "%Y-%m-01")), v = bm$benchmark_ret)
  }
  mm <- merge(merge(net, gro, by = "Date", suffixes = c("_net", "_gross")),
              ben, by = "Date")
  setnames(mm, c("v_net", "v_gross", "v"), c("ret_net", "ret_gross", "benchmark_ret"))
  setorder(mm, Date)
  bare_gross <- mm[, .(Date, r = ret_gross)]
  list(mode = "B", pr_monthly = mm[, .(date = Date, ret_net, benchmark_ret)],
       bare_gross = bare_gross, dates = mm$Date)
}

# ---------------------------------------------------------------------------
# 드레인 본체
# ---------------------------------------------------------------------------
drain_run_candidate <- function(entry, cost_bps = 15) {
  ad <- drain_resolve_adapter(entry)
  if (ad$adapter == "unknown") stop(sprintf("[drain] adapter 불명 — entry %s (source=%s)", entry$id, entry$source))
  dat <- if (ad$adapter == "weights_parquet") drain_load_weights_parquet(ad) else drain_load_bt_result(ad)
  rid_prefix <- paste0("drain_", entry$id, "_")

  # --- 신호 exposure 스케줄 ---
  u <- drain_load_uni()
  uni0 <- drain_build_uni(u, dat$dates, extra_lag = 0L)   # 직전월 신호 (하네스 기본)
  uni1 <- drain_build_uni(u, dat$dates, extra_lag = 1L)   # +1 lag 스트레스 (전전월)
  vt0 <- as.data.table(build_voltarget_exposure(copy(dat$bare_gross)))
  vt1 <- copy(vt0); vt1[, exposure := shift(exposure, 1L, fill = 1.0)]

  # --- ① overlay_pit_guard HARD (C5): 신호 컷오프(신호월+1개월 첫날 = 신호월 말까지 known) ≤ 홀딩월 첫날 ---
  holding_start <- as.Date(format(uni0$Date, "%Y-%m-01"))
  assert_overlay_pit(.month_add(as.Date(paste0(uni0$ym_sig, "-01")), 1L), holding_start, label = paste0(entry$id, "/uni_cat"))
  assert_overlay_pit(.month_add(as.Date(paste0(uni1$ym_sig, "-01")), 1L), holding_start, label = paste0(entry$id, "/uni_cat_lag1"))
  # voltgt: row i는 trailing (i-12..i-1)월 수익만 사용(strictly before) → 컷오프 = 홀딩월 첫날
  assert_overlay_pit(as.Date(format(vt0$Date, "%Y-%m-01")), as.Date(format(vt0$Date, "%Y-%m-01")), label = paste0(entry$id, "/voltgt"))
  pit_assert_pass <- TRUE

  scen <- list(bare = NULL,
               uni_cat = uni0[, .(Date, exposure)], uni_cat_lag1 = uni1[, .(Date, exposure)],
               voltgt = vt0[, .(Date, exposure)], voltgt_lag1 = vt1[, .(Date, exposure)])

  # --- 시나리오 측정 ---
  res <- list(); prs <- list()
  for (nm in names(scen)) {
    if (dat$mode == "A") {
      r <- weighted_screen_bt(dat$W, dat$R, dat$B, cost_bps_oneway = cost_bps,
                              run_id = paste0(rid_prefix, nm), strategy_id = paste0(rid_prefix, nm),
                              exposure_dt = scen[[nm]])
      avg_exp <- if (is.null(scen[[nm]])) 1.0 else mean(scen[[nm]]$exposure, na.rm = TRUE)
      res[[nm]] <- data.table(
        scenario = nm, n_months = r$n_months,
        abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr, abs_MDD = r$abs_mdd,
        IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3,
        active_SR = r$net_sr, oos_ret_v2 = drain_oos_v2(r$period_returns),
        calmar = { cagr <- r$abs_cagr; mdd <- abs(r$abs_mdd); if (mdd > 0) cagr / mdd else NA_real_ },
        avg_exposure = avg_exp,
        cost_applied = FALSE, avg_abs_dexp_m = 0, ov_cost_ann_bps = 0)
      prs[[nm]] <- as.data.table(r$period_returns)
    } else {
      pr <- copy(dat$pr_monthly)
      if (!is.null(scen[[nm]])) {   # exposure 적용 = ret_net×e (weighted_screen_bt L65 규약 동일)
        ed <- as.data.table(scen[[nm]])
        pr[ed, on = c(date = "Date"), exposure := i.exposure]
        pr[is.na(exposure), exposure := 1]
        pr[, ret_net := ret_net * exposure][, exposure := NULL]
      }
      avg_exp <- if (is.null(scen[[nm]])) 1.0 else mean(scen[[nm]]$exposure, na.rm = TRUE)
      m <- drain_measure_pr(pr, paste0(rid_prefix, nm), nm, avg_exposure = avg_exp)
      res[[nm]] <- m$row; prs[[nm]] <- m$pr
    }
    if (!is.null(scen[[nm]])) {   # 오버레이 시나리오만 회전비용 변형 병행 (bare Δ≡0)
      rc <- drain_remeasure_with_cost(prs[[nm]], scen[[nm]], cost_bps, rid_prefix, nm)
      res[[paste0(nm, "_cost")]] <- rc$row
      prs[[paste0(nm, "_cost")]] <- rc$pr
      res[[nm]][, avg_abs_dexp_m := rc$row$avg_abs_dexp_m]
      res[[nm]][, ov_cost_ann_bps := rc$row$ov_cost_ann_bps]
      res[[nm]][, cost_applied := FALSE]
    }
  }
  tab <- rbindlist(res, fill = TRUE)

  # --- ③ strict-PIT A/B: uni exposure를 명시적 strict 규칙(신호월 말 < 홀딩월 첫날)으로 독립 재구축 ---
  u_strict <- copy(u)[, sig_month_start := as.Date(paste0(ym_sig, "-01"))]
  dd_strict <- data.table(Date = sort(unique(dat$dates)))
  dd_strict[, holding_start := as.Date(format(Date, "%Y-%m-01"))]
  pick_strict <- function(hs) {   # 신호월 말(=신호월+1M 첫날) ≤ 홀딩월 첫날 인 가장 최근 신호월
    ok <- u_strict[.month_add(sig_month_start, 1L) <= hs]
    if (nrow(ok) == 0) NA_character_ else ok[which.max(sig_month_start), Category]
  }
  dd_strict[, Category := sapply(holding_start, pick_strict)]
  dd_strict[, exposure := as.numeric(CAT_EXPOSURE[Category])]
  dd_strict[is.na(exposure), exposure := 1.0]
  strict_same <- isTRUE(all.equal(dd_strict$exposure, uni0$exposure, tolerance = 1e-12))
  pr_strict <- if (dat$mode == "A") {
    weighted_screen_bt(dat$W, dat$R, dat$B, cost_bps_oneway = cost_bps,
                       run_id = paste0(rid_prefix, "uni_strict"), strategy_id = paste0(rid_prefix, "uni_strict"),
                       exposure_dt = dd_strict[, .(Date, exposure)])$period_returns
  } else {
    pr <- copy(dat$pr_monthly)
    pr[dd_strict, on = c(date = "Date"), exposure := i.exposure]
    pr[is.na(exposure), exposure := 1]
    pr[, ret_net := ret_net * exposure][, exposure := NULL]
    pr
  }
  sr_of <- function(pr) mean(pr$ret_net) / stats::sd(pr$ret_net) * sqrt(12)
  strict_ab <- overlay_lookahead_ab(sr_of(prs[["uni_cat"]]), sr_of(as.data.table(pr_strict)),
                                    metric_name = "uni_cat abs_SR (current vs strict-PIT)")

  # --- paired 증분 NW-t (lag-3, contract .nw_t_mean) — 비율 비교 금지 규약 ---
  bare_pr <- prs[["bare"]]
  paired <- rbindlist(lapply(setdiff(names(prs), "bare"), function(nm) {
    p <- merge(bare_pr[, .(date, bare = ret_net)], prs[[nm]][, .(date, scen = ret_net)], by = "date")
    d <- p$scen - p$bare
    b <- tab[scenario == "bare"]; s <- tab[scenario == nm]
    data.table(scenario = nm, n = nrow(p),
               paired_nw_t_lag3 = .nw_t_mean(d, lag = 3L),
               mean_d_monthly = mean(d),
               dSR = s$abs_SR - b$abs_SR, dMDD = s$abs_MDD - b$abs_MDD,
               d_PORT_t = s$PORT_t - b$PORT_t)
  }))

  # --- ② lag1 스트레스 요약 (LH 규약: bare 대비 MDD 완화/ΔSR 부호 유지 여부) ---
  bare_row <- tab[scenario == "bare"]
  lag_survive <- function(base_nm, lag_nm) {
    b <- tab[scenario == base_nm]; l <- tab[scenario == lag_nm]
    list(mdd_improve_base = bare_row$abs_MDD - b$abs_MDD, mdd_improve_lag1 = bare_row$abs_MDD - l$abs_MDD,
         dSR_base = b$abs_SR - bare_row$abs_SR, dSR_lag1 = l$abs_SR - bare_row$abs_SR)
  }
  lag1_stress <- list(uni_cat = lag_survive("uni_cat", "uni_cat_lag1"),
                      voltgt = lag_survive("voltgt", "voltgt_lag1"),
                      uni_cat_cost = lag_survive("uni_cat_cost", "uni_cat_lag1_cost"),
                      voltgt_cost = lag_survive("voltgt_cost", "voltgt_lag1_cost"))

  # --- AX-001 v2 crisis-conditional (LH 자구동일: gross × uni0 노출) ---
  cr <- merge(dat$bare_gross, uni0[, .(Date, Category, uni_e = exposure)], by = "Date", all.x = TRUE)
  cr[is.na(uni_e), uni_e := 1.0]
  cr[, crisis := Category %in% c("CRISIS", "CAUTION")]
  crisis_tab <- cr[, .(n = .N, bare_mean = mean(r), uni_mean = mean(r * uni_e)), by = crisis]

  list(tab = tab, paired = paired, lag1_stress = lag1_stress, crisis = crisis_tab,
       adapter = ad$adapter, pit = list(assert_pass = pit_assert_pass,
                                        strict_exposure_identical = strict_same,
                                        strict_ab = strict_ab))
}

# ---------------------------------------------------------------------------
# 결과 기록 + 큐 갱신 (원자적 temp-rename)
# ---------------------------------------------------------------------------
.atomic_write_json <- function(obj, path, ...) {
  tmp <- paste0(path, ".tmp", Sys.getpid())
  write_json(obj, tmp, ...)
  if (file.exists(path)) {
    bak <- paste0(path, ".bak")
    file.copy(path, bak, overwrite = TRUE)
    file.remove(path)
  }
  ok <- file.rename(tmp, path)
  if (!ok) stop(sprintf("[drain] atomic rename 실패: %s", path))
  invisible(TRUE)
}

# jsonlite 라운드트립 보존: JSON null(read→R NULL)은 write_json에서 {}로 깨짐 → NA로 치환(na="null"로 null 복원)
.null_to_na <- function(x) {
  if (is.null(x)) return(NA)
  if (is.list(x)) return(lapply(x, .null_to_na))
  x
}

drain_update_queue <- function(queue_path, candidate_id, result_path, measured_at) {
  q <- .null_to_na(read_json(queue_path, simplifyVector = FALSE))
  idx <- which(vapply(q$candidates, function(x) identical(x$id, candidate_id), logical(1)))
  if (length(idx) != 1) stop(sprintf("[drain] 큐에서 id=%s 를 찾지 못함(%d건)", candidate_id, length(idx)))
  q$candidates[[idx]]$status <- "measured"
  q$candidates[[idx]]$ab_result_ref <- list(
    result_path = result_path, measured_at = measured_at, harness = DRAIN_HARNESS_ID)
  .atomic_write_json(q, queue_path, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# 판정 계층 dv_v1 (2026-08-16 P0#2 — L1 자동 스폰 설계, 도훈 승인)
#   왜: 07-10 드레인 16건의 SURVIVOR/INFERIOR 판정이 결과 JSON에 없고 세션 수기
#   (L-OVL-20260710_153559)에만 있었다 — 재현 불가 판정. 규약을 코드로 이관:
#   ① best_t = paired 증분 NW-t(lag-3, scenario − bare)의 최대
#   ② null_max_t = sqrt(2·ln(n_selection)) — n개 비교의 우연 최대 t 근사
#      (07-10 세션 판정 "null max-t(N16~2.35)" 규약의 일반화. n_selection 기본 =
#       이 후보의 유한 비교 수, 배치 재판정 시 배치 전체 비교 수를 전달 — 보수적)
#   ③ verdict: best_t ≤ 0 → INFERIOR (bare 대비 개선 없음 — 우연 문턱 불요)
#              best_t ≥ null_max_t ∧ lag1 게이트 통과 → SURVIVOR
#              그 외 → INDETERMINATE
#   ④ lag1 게이트(SURVIVOR 전제): best 시나리오의 lag1 짝 paired t > 0 — 동월 누출
#      방어(note의 "lag1 스트레스 의무"를 판정에 바인딩). lag1 짝 부재 시 SURVIVOR
#      불가(INDETERMINATE cap) — 억지 승격 금지.
#   tier=screen_diagnostic 불변 — 이 판정은 자본게이트가 아니다 (HARD 3종/governor 별도).
# ---------------------------------------------------------------------------
drain_verdict <- function(paired, n_selection = NULL) {
  base <- list(rule_version = "dv_v1",
               basis = "screen_diagnostic — 자본게이트 판정 아님 (HARD 3종/governor 불변)",
               verdict = "INDETERMINATE", best_scenario = NA_character_,
               best_paired_nw_t_lag3 = NA_real_, lag1_scenario = NA_character_,
               lag1_paired_t = NA_real_, n_selection = NA_integer_, null_max_t = NA_real_,
               reason = "")
  P <- tryCatch(as.data.table(paired), error = function(e) NULL)
  if (is.null(P) || !nrow(P) || !all(c("scenario", "paired_nw_t_lag3") %in% names(P))) {
    base$reason <- "paired_nw 비어있음/스키마 불일치 — 판정 불가"
    return(base)
  }
  P[, paired_nw_t_lag3 := suppressWarnings(as.numeric(paired_nw_t_lag3))]
  P <- P[is.finite(paired_nw_t_lag3)]
  if (!nrow(P)) { base$reason <- "유한한 paired t 없음 — 판정 불가"; return(base) }
  n_sel <- max(as.integer(if (is.null(n_selection)) nrow(P) else n_selection), 2L)
  nmt <- sqrt(2 * log(n_sel))
  bi <- which.max(P$paired_nw_t_lag3)
  bs <- as.character(P$scenario[bi]); bt <- P$paired_nw_t_lag3[bi]
  lag_nm <- if (grepl("lag1", bs, fixed = TRUE)) bs
            else if (grepl("_cost$", bs)) sub("_cost$", "_lag1_cost", bs)
            else paste0(bs, "_lag1")
  lr <- P[scenario == lag_nm]
  lt <- if (nrow(lr)) lr$paired_nw_t_lag3[1] else NA_real_
  verdict <- if (bt <= 0) "INFERIOR"
             else if (bt >= nmt && is.finite(lt) && lt > 0) "SURVIVOR"
             else "INDETERMINATE"
  reason <- if (bt <= 0) sprintf("best paired NW-t %.3f <= 0 — bare 대비 개선 없음", bt)
            else if (identical(verdict, "SURVIVOR"))
              sprintf("best %.3f >= null_max_t %.3f (n_sel %d) AND lag1 %.3f > 0", bt, nmt, n_sel, lt)
            else if (bt < nmt)
              sprintf("best %.3f in (0, null_max_t %.3f) — 선택공간 n=%d 의 우연과 미구분", bt, nmt, n_sel)
            else sprintf("best %.3f >= null_max_t %.3f 이나 lag1 게이트 미통과(lag1 t=%s) — 동월 누출 방어",
                         bt, nmt, if (is.finite(lt)) sprintf("%.3f", lt) else "짝 부재")
  modifyList(base, list(verdict = verdict, best_scenario = bs, best_paired_nw_t_lag3 = bt,
                        lag1_scenario = lag_nm, lag1_paired_t = lt,
                        n_selection = n_sel, null_max_t = round(nmt, 4), reason = reason))
}

# JSON 재판독용: paired_nw(리스트-of-리스트) → data.table (스칼라만 추출, 결측 NA)
.dv_paired_dt <- function(pn) {
  if (is.null(pn) || !length(pn)) return(data.table(scenario = character(0), paired_nw_t_lag3 = numeric(0)))
  data.table(
    scenario = vapply(pn, function(r) as.character((r$scenario %||% NA_character_)[1]), character(1)),
    paired_nw_t_lag3 = vapply(pn, function(r)
      suppressWarnings(as.numeric((r$paired_nw_t_lag3 %||% NA_real_)[1])), numeric(1))
  )
}

# 배치 재판정 — 기존 결과 전수에 dv_v1 적용. n_selection = 배치 전체 유한 비교 수(보수적).
#   write=TRUE 면 각 결과 JSON에 verdict 블록 append (원자적, judged_at/judged_by 기록).
#   ★"빈 결과 = 합격" 금지 — 결과 0건이면 stop.
drain_verdict_batch <- function(result_dir = DRAIN_RESULT_DIR_DEFAULT, write = FALSE) {
  fs <- Sys.glob(file.path(result_dir, "*.json"))
  if (!length(fs)) stop("[drain] verdict-batch: 결과 파일 0건 — ", result_dir, " (빈 결과 = 합격 아님)")
  parsed <- lapply(fs, function(p) tryCatch(.null_to_na(read_json(p, simplifyVector = FALSE)),
                                            error = function(e) NULL))
  keep <- !vapply(parsed, is.null, logical(1))
  if (any(!keep)) message("[drain] verdict-batch: parse 실패 skip — ",
                          paste(basename(fs[!keep]), collapse = ", "))
  fs <- fs[keep]; parsed <- parsed[keep]
  pdts <- lapply(parsed, function(d) .dv_paired_dt(d$paired_nw))
  n_total <- sum(vapply(pdts, function(P) sum(is.finite(P$paired_nw_t_lag3)), numeric(1)))
  rows <- vector("list", length(fs))
  for (i in seq_along(fs)) {
    v <- drain_verdict(pdts[[i]], n_selection = n_total)
    d <- parsed[[i]]
    if (isTRUE(write)) {
      d$verdict <- c(v, list(judged_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                             judged_by = "drain_verdict_batch"))
      .atomic_write_json(d, fs[i], auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
    }
    rows[[i]] <- data.table(
      candidate_id = as.character(d$candidate_id %||% basename(fs[i])),
      verdict = v$verdict,
      best_t = v$best_paired_nw_t_lag3, best_scenario = v$best_scenario,
      null_max_t = v$null_max_t, n_selection = v$n_selection)
  }
  out <- rbindlist(rows, fill = TRUE)
  tb <- table(out$verdict)
  cat(sprintf("[drain] verdict-batch: %d건 판정 (n_selection=%d, write=%s) — %s\n",
              nrow(out), as.integer(n_total), write,
              paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse = " ")))
  out
}

drain_main <- function(candidate_id, suffix = "", queue_path = DRAIN_QUEUE_PATH_DEFAULT,
                       result_dir = DRAIN_RESULT_DIR_DEFAULT, cost_bps = 15, update_queue = TRUE) {
  q <- read_json(queue_path, simplifyVector = FALSE)
  idx <- which(vapply(q$candidates, function(x) identical(x$id, candidate_id), logical(1)))
  if (length(idx) != 1) stop(sprintf("[drain] 큐에서 id=%s 를 찾지 못함", candidate_id))
  entry <- q$candidates[[idx]]

  cat(sprintf("\n##### overlay drain — %s (%s) #####\n", entry$id, entry$strategy_name %||% ""))
  out <- drain_run_candidate(entry, cost_bps = cost_bps)
  cat(sprintf("\n=== 시나리오 비교 (adapter=%s, build_benchmark_compare NW lag-3) ===\n", out$adapter))
  print(out$tab, digits = 4)
  cat("\n=== paired 증분 NW-t (scenario − bare, lag-3) ===\n")
  print(out$paired, digits = 4)
  cat("\n=== AX-001 crisis-conditional ===\n"); print(out$crisis, digits = 4)
  cat(sprintf("\n[PIT] assert_overlay_pit HARD: PASS | strict exposure 동일: %s\n%s\n",
              out$pit$strict_exposure_identical, out$pit$strict_ab$message))

  measured_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  dir.create(result_dir, showWarnings = FALSE, recursive = TRUE)
  result_path <- file.path(result_dir, paste0(candidate_id, suffix, ".json"))
  result <- list(
    candidate_id = candidate_id,
    measured_at = measured_at,
    metric_type = if (out$adapter == "weights_parquet") "weighted_screen" else "backtested_monthly_agg",
    tier = "screen_diagnostic",   # capital-grade 아님 — HARD 3종/governor 별도
    harness = DRAIN_HARNESS_ID,
    adapter = out$adapter,
    cost_bps_oneway = cost_bps,
    overlay_cost_model = paste("*_cost = 월별 |Δexposure|×15bps one-way 추가 차감 (cost_model v2.4 delta-based,",
                               "PG2 recovery-override 규약). 첫 월 Δ=0(fill=첫 exposure)."),
    pit_guard = list(assert_overlay_pit = "PASS(HARD)",
                     strict_exposure_identical = out$pit$strict_exposure_identical,
                     strict_ab_inflation = out$pit$strict_ab$inflation,
                     strict_ab_lookahead_suspected = out$pit$strict_ab$lookahead_suspected,
                     strict_ab_message = out$pit$strict_ab$message),
    note = paste("screen-tier A/B — 자본게이트 아님. 판정은 paired 증분 NW-t(비율 비교 금지).",
                 "unified_regime_signal walk-forward 미보증 → lag1 스트레스 의무."),
    scenarios = out$tab,
    paired_nw = out$paired,
    crisis_conditional = out$crisis,
    lag1_stress = out$lag1_stress,
    # P0#2 (2026-08-16): 판정 계층 dv_v1 — 수기 판정의 재현 불가능성 제거.
    verdict = c(drain_verdict(out$paired),
                list(judged_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                     judged_by = "drain_main"))
  )
  cat(sprintf("\n[verdict dv_v1] %s — %s\n", result$verdict$verdict, result$verdict$reason))
  .atomic_write_json(result, result_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
  fwrite(out$tab, sub("\\.json$", "_scenarios.csv", result_path))
  cat(sprintf("\n[drain] wrote %s\n", result_path))

  if (update_queue) {
    drain_update_queue(queue_path, candidate_id, result_path, measured_at)
    cat(sprintf("[drain] queue 갱신: %s → status=measured (원자적 temp-rename)\n", candidate_id))
  } else cat("[drain] --no-queue-update: 큐 미갱신\n")
  invisible(result)
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
if (sys.nframe() == 0L && Sys.getenv("QVEST_DRAIN_NORUN") != "1") {
  args <- commandArgs(trailingOnly = TRUE)
  pos <- args[!grepl("^--", args)]
  if (length(pos) < 1) stop("usage: Rscript overlay_candidate_drain.R <candidate_id> [--suffix=] [--no-queue-update] [--queue=] [--result-dir=] [--cost-bps=]")
  getopt <- function(key, default) {
    hit <- grep(paste0("^--", key, "="), args, value = TRUE)
    if (length(hit) == 0) default else sub(paste0("^--", key, "="), "", hit[1])
  }
  drain_main(candidate_id = pos[1],
             suffix = getopt("suffix", ""),
             queue_path = getopt("queue", DRAIN_QUEUE_PATH_DEFAULT),
             result_dir = getopt("result-dir", DRAIN_RESULT_DIR_DEFAULT),
             cost_bps = as.numeric(getopt("cost-bps", "15")),
             update_queue = !("--no-queue-update" %in% args))
}
