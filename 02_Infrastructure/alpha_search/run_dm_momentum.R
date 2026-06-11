#!/usr/bin/env Rscript
# =============================================================================
# run_dm_momentum.R — Daniel & Moskowitz (2016, JFE) 충실 복제 오케스트레이터
# =============================================================================
# alpha-search 모드. run_alpha_search(횡단면 top-N)는 decile L/S + 시계열 dynamic
# weighting 복제 불가 → 별도 엔진(dm_engine.R). 측정·리포팅 백엔드 재사용:
#   summarise_perf / generate_charts / run_hurdle_gate / run_multifactor_regression
#   / tg_agent_brief.  자체합성 금지·measurement 규율 유지.
#
# 산출:
#   1. 3-way 비교: raw WML(static) / cvol(constant-vol, BSC형) / dyn(dynamic eq.5).
#   2. 헤드라인 = dyn~raw 회귀 α (위험관리+μ타이밍 증분) + dyn~cvol 증분 회귀.
#   3. implementable long-only(Win leg · w_dyn 캡[0,1]) → 2차트 + 허들 + 텔레그램.
# 기간 2005-01-01~ 고정. 유니버스 K200∪KQ150 고정(시변 PIT). target_vol=0.19(DM Fig.5).
# =============================================================================

suppressWarnings(suppressMessages({ library(data.table); library(xts); library(jsonlite) }))

.DM_INFRA <- local({
  cand <- Sys.getenv("QVEST_INFRA_DIR", "")
  if (nzchar(cand) && file.exists(file.path(cand, "config.R"))) return(cand)
  file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")), "02_Infrastructure")
})
source(file.path(.DM_INFRA, "config.R"))
source(file.path(.DM_INFRA, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
source(file.path(.DM_INFRA, "hurdle_gate.R"))
source(file.path(.DM_INFRA, "factor_portfolios.R"))
source(file.path(.DM_INFRA, "alpha_search", "dm_engine.R"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

# =============================================================================
run_dm_momentum <- function(start_date    = "2005-01-01",
                            target_vol    = 0.19,
                            rv_win        = 126L,
                            commission    = 0.0015,
                            send_telegram = TRUE,
                            tg_dry_run    = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  run_id <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_name <- "DM Dynamic Momentum (KR)"
  strategy_id   <- paste0("STR_AS_DM_", run_id)
  strategy_idea <- paste0(
    "Daniel-Moskowitz(2016) 동적 모멘텀: WML(decile D10-D1 VW 12-2)을 ",
    "예측 평균 μ̂(bear지표×시장분산 회귀)/예측 분산 σ̂²(126일 실현)로 w∝μ̂/σ̂² scaling. ",
    "모멘텀 크래시(bear+고변동 loser leg 옵션성) 회피 + μ타이밍으로 constant-vol 초월 검증.")

  OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

  # ---- 1. RAWDATA + 시그널 월말 ---------------------------------------------
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
  if (!inherits(BM_DT$Date, "Date")) BM_DT[, Date := as.Date(Date)]
  setorder(RAWDATA, Ticker, Date)
  all_dates <- sort(unique(RAWDATA$Date))
  RAWDATA[, .ym := format(Date, "%Y-%m")]
  me_all <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
  RAWDATA[, .ym := NULL]
  sig_dates <- sort(me_all[me_all >= as.Date(start_date)])
  cat(sprintf("\n=== [DM] %s (%s) ===\n  signal months=%d  %s~%s\n",
              strategy_name, strategy_id, length(sig_dates),
              as.character(min(sig_dates)), as.character(max(sig_dates))))

  # ---- 2. WML decile(D10-D1) 일간 시계열 ------------------------------------
  wml <- dm_build_wml_decile(RAWDATA, all_dates, sig_dates,
                             skip_d = 21L, look_d = 252L, liq_thresh = 2e8,
                             liq_win = 20L, n_deciles = 10L)
  daily_wml <- wml$daily
  cat(sprintf("  WML 일간행=%d  %s~%s | 유니버스 중앙값=%d | D10중앙값=%d D1중앙값=%d\n",
              nrow(daily_wml), as.character(min(daily_wml$Date)), as.character(max(daily_wml$Date)),
              as.integer(median(wml$diag$n_uni)), as.integer(median(wml$diag$n_win)),
              as.integer(median(wml$diag$n_los))))

  # ---- 3. bear indicator + 시장 126일 분산 ----------------------------------
  bear_dt <- dm_bear_and_mktvar(BM_DT, month_ends = sig_dates, bear_lookback_m = 24L, var_win = rv_win)
  cat(sprintf("  bear 월비율=%.1f%% (I_B=1) | 시장σ²m 유효=%d/%d\n",
              100 * mean(bear_dt$I_B, na.rm = TRUE), sum(is.finite(bear_dt$sig2_m)), nrow(bear_dt)))

  # ---- 4. WML 월간수익 → μ̂ expanding-window 예측 ----------------------------
  wml_xts_full <- xts(daily_wml$WML, order.by = daily_wml$Date)
  wml_m <- apply.monthly(wml_xts_full, Return.cumulative)
  wml_monthly <- data.table(MEnd = as.Date(index(wml_m)), WML_m = as.numeric(wml_m[, 1]))
  wml_monthly[, ym := format(MEnd, "%Y-%m")]
  # bear_dt MEnd(시그널 월말)와 wml_monthly MEnd(보유기간 종료일) 정렬: ym 기준 join
  bm_for_mu <- merge(wml_monthly[, .(ym, MEnd, WML_m)],
                     bear_dt[, .(ym = format(MEnd, "%Y-%m"), I_B, sig2_m)], by = "ym", all.x = TRUE)
  setorder(bm_for_mu, MEnd)
  mu_dt <- dm_forecast_mu(bm_for_mu[, .(ym, MEnd, WML_m, I_B, sig2_m)], bear_dt = NULL, min_obs = 60L)
  cat(sprintf("  μ̂ 예측 유효구간=%d개월 (expanding min_obs=60) 시작=%s\n",
              sum(is.finite(mu_dt$mu_hat)),
              as.character(min(mu_dt$MEnd[is.finite(mu_dt$mu_hat)]))))

  # ---- 5. dynamic weighting eq(5) + cvol(BSC형) -----------------------------
  vm <- dm_dynamic_series(daily_wml[, .(Date, WML, Win)],
                          mu_dt = mu_dt[, .(MEnd, mu_hat, I_B, sig2_m)],
                          target_vol = target_vol, rv_win = rv_win)
  d <- vm$daily
  cat(sprintf("  dynamic 상수 c=%.4f (target_vol=%.0f%% 매칭) | dyn 정의구간 시작=%s\n",
              vm$c_dyn, target_vol * 100,
              as.character(min(d$Date[is.finite(d$WML_dyn)]))))

  # 공통 정의구간(dyn 유효 = μ̂ + σ̂² 둘 다 정의) 기준 비교 — fair comparison
  d_def <- d[is.finite(WML_dyn) & is.finite(WML_cvol) & is.finite(WML)]
  raw_xts  <- xts(d_def$WML,      order.by = d_def$Date); names(raw_xts)  <- "RawWML"
  cvol_xts <- xts(d_def$WML_cvol, order.by = d_def$Date); names(cvol_xts) <- "CvolWML"
  dyn_xts  <- xts(d_def$WML_dyn,  order.by = d_def$Date); names(dyn_xts)  <- "DynWML"

  # ---- 6. 헤드라인 회귀: dyn~raw, dyn~cvol ----------------------------------
  reg_dyn_raw  <- dm_regression_alpha(dyn_xts, raw_xts)
  reg_dyn_cvol <- dm_regression_alpha(dyn_xts, cvol_xts)
  reg_cvol_raw <- dm_regression_alpha(cvol_xts, raw_xts)
  cat("\n  [헤드라인 회귀 α (월간, NW HAC)]\n")
  pr <- function(lab, r) if (!is.null(r)) cat(sprintf("    %-14s α=%+.2f%%/yr t=%.2f β=%.2f R²=%.2f n=%d\n",
                                                      lab, r$alpha_ann_pct, r$alpha_t, r$beta, r$r2, r$n))
  pr("dyn~raw",  reg_dyn_raw); pr("dyn~cvol", reg_dyn_cvol); pr("cvol~raw", reg_cvol_raw)

  # ---- 7. 성과 비교 ---------------------------------------------------------
  pf_raw  <- summarise_perf(raw_xts,  "raw WML (static L/S)")
  pf_cvol <- summarise_perf(cvol_xts, "cvol (constant-vol)")
  pf_dyn  <- summarise_perf(dyn_xts,  "dyn (dynamic eq.5)")
  perf_tbl <- rbindlist(list(pf_raw, pf_cvol, pf_dyn), fill = TRUE)
  cat("\n  [성과 비교 (공통 dyn-정의구간)]\n")
  print(perf_tbl[, .(Label, CAGR, AnnVol, Sharpe, MDD, Calmar)])

  # ---- 8. 분포 + 크래시 월 --------------------------------------------------
  ds_raw <- dm_dist_stats(raw_xts); ds_dyn <- dm_dist_stats(dyn_xts)
  cat(sprintf("\n  [분포] raw skew=%.2f kurt=%.1f worstM=%.1f%% | dyn skew=%.2f kurt=%.1f worstM=%.1f%%\n",
              ds_raw$skew, ds_raw$kurt, ds_raw$worst_m * 100,
              ds_dyn$skew, ds_dyn$kurt, ds_dyn$worst_m * 100))
  raw_m2 <- apply.monthly(raw_xts, Return.cumulative); dyn_m2 <- apply.monthly(dyn_xts, Return.cumulative)
  raw_mdt <- data.table(ym = format(as.Date(index(raw_m2)), "%Y-%m"), raw = as.numeric(raw_m2[, 1]))
  dyn_mdt <- data.table(ym = format(as.Date(index(dyn_m2)), "%Y-%m"), dyn = as.numeric(dyn_m2[, 1]))
  worst_raw_ym <- raw_mdt[which.min(raw)]
  cat(sprintf("    [raw 최악월] %s raw=%+.1f%% dyn=%+.1f%%\n",
              worst_raw_ym$ym, worst_raw_ym$raw * 100,
              .as_num(dyn_mdt[ym == worst_raw_ym$ym, dyn]) * 100))

  # ---- 9. pre/post-2017 서브피리어드 ----------------------------------------
  cut17 <- as.Date("2017-01-01")
  sr_raw_pre  <- .as_num(summarise_perf(raw_xts[index(raw_xts)  < cut17], "x")$Sharpe)
  sr_cvol_pre <- .as_num(summarise_perf(cvol_xts[index(cvol_xts) < cut17], "x")$Sharpe)
  sr_dyn_pre  <- .as_num(summarise_perf(dyn_xts[index(dyn_xts)  < cut17], "x")$Sharpe)
  sr_raw_post  <- .as_num(summarise_perf(raw_xts[index(raw_xts)  >= cut17], "x")$Sharpe)
  sr_cvol_post <- .as_num(summarise_perf(cvol_xts[index(cvol_xts) >= cut17], "x")$Sharpe)
  sr_dyn_post  <- .as_num(summarise_perf(dyn_xts[index(dyn_xts)  >= cut17], "x")$Sharpe)
  reg_post <- dm_regression_alpha(dyn_xts[index(dyn_xts) >= cut17], cvol_xts[index(cvol_xts) >= cut17])
  cat(sprintf("\n  [서브피리어드 Sharpe raw/cvol/dyn]  pre2017: %.2f/%.2f/%.2f | post2017: %.2f/%.2f/%.2f\n",
              sr_raw_pre, sr_cvol_pre, sr_dyn_pre, sr_raw_post, sr_cvol_post, sr_dyn_post))
  if (!is.null(reg_post)) cat(sprintf("  [post2017 dyn~cvol α] %+.2f%%/yr t=%.2f\n",
                                      reg_post$alpha_ann_pct, reg_post$alpha_t))

  # ---- 10. implementable long-only(Win leg, w_dyn 캡[0,1]) → 백엔드 ---------
  # long-only 구현: long leg(Win=D10 VW)에 dynamic weight 캡[0,1] (무레버리지). 나머지 현금.
  d[, w_dyn_cap := pmin(pmax(w_dyn, 0), 1)]
  d[, Win_dyn := w_dyn_cap * Win]
  impl_daily <- d[is.finite(Win_dyn), .(Date, Ret = Win_dyn)]
  mw <- vm$monthly[, .(MEnd, w = pmin(pmax(w_dyn, 0), 1))]
  sim <- dm_build_sim_result(impl_daily, BM_DT, mw)

  tryCatch(generate_charts(sim, output_dir = OUT_DIR, strategy_name = "DM dynamic long-leg (KR)"),
           error = function(e) cat("[DM] generate_charts 생략:", conditionMessage(e), "\n"))
  charts <- Filter(file.exists, c(file.path(OUT_DIR, "equity_curve.png"),
                                  file.path(OUT_DIR, "annual_returns.png")))

  hg <- tryCatch(run_hurdle_gate(sim_result = sim, FACTORS = NULL,
                                 strategy_name = strategy_name, output_dir = OUT_DIR),
                 error = function(e) { cat("[DM] hurdle 예외:", conditionMessage(e), "\n")
                                       list(grade = "F", score = NA_real_, verdict = list()) })
  assign("%||%", `%||%`, envir = globalenv())
  grade <- hg$grade %||% "uncertain"; score <- .as_num(hg$score)

  # ---- 11. FF3/FF5/Carhart α (raw WML decile L/S) ---------------------------
  mf <- tryCatch({ fdt <- load_kr_factor_returns(); run_multifactor_regression(raw_xts, NULL, fdt) },
                 error = function(e) { cat("[DM] multifactor 생략:", conditionMessage(e), "\n"); NULL })
  if (!is.null(mf)) {
    cat("\n  [FF3/FF5/Carhart α — raw WML decile]\n")
    for (nm in names(mf)) cat(sprintf("    %-10s α=%+.2f%%/yr t=%.2f R²=%.2f\n",
                                      mf[[nm]]$model, mf[[nm]]$alpha * 12 * 100, mf[[nm]]$alpha_tstat, mf[[nm]]$adj_r2))
  }

  # ---- 12. 결과 JSON --------------------------------------------------------
  result <- list(
    strategy_id = strategy_id, strategy_name = strategy_name, run_id = run_id,
    paper = "Daniel & Moskowitz (2016, JFE) Momentum crashes", start_date = start_date,
    target_vol = target_vol, rv_win = rv_win, c_dyn = vm$c_dyn,
    universe = "K200_KQ150 (시변 PIT)", metric_type = "proxy",
    headline_reg = list(dyn_vs_raw = reg_dyn_raw, dyn_vs_cvol = reg_dyn_cvol, cvol_vs_raw = reg_cvol_raw),
    perf = list(
      raw_wml = as.list(pf_raw[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)]),
      cvol    = as.list(pf_cvol[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)]),
      dyn     = as.list(pf_dyn[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)])),
    dist = list(raw = ds_raw, dyn = ds_dyn),
    worst_raw_month = as.list(worst_raw_ym),
    subperiod = list(
      pre2017  = list(sr_raw = sr_raw_pre,  sr_cvol = sr_cvol_pre,  sr_dyn = sr_dyn_pre),
      post2017 = list(sr_raw = sr_raw_post, sr_cvol = sr_cvol_post, sr_dyn = sr_dyn_post,
                      reg_dyn_cvol = reg_post)),
    bear_pct = 100 * mean(bear_dt$I_B, na.rm = TRUE),
    factor_alpha = if (!is.null(mf)) lapply(mf, function(r) list(
      model = r$model, alpha_ann_pct = r$alpha * 12 * 100, t = r$alpha_tstat, adj_r2 = r$adj_r2)) else NULL,
    grade = grade, score = score, out_dir = OUT_DIR, charts = charts)
  writeLines(toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
             file.path(OUT_DIR, "dm_result.json"))
  cat(sprintf("\n  결과 저장: %s\n", file.path(OUT_DIR, "dm_result.json")))

  # ---- 13. 텔레그램 ---------------------------------------------------------
  if (isTRUE(send_telegram)) tryCatch(
    .send_dm_brief(strategy_name, strategy_idea, strategy_id, reg_dyn_raw, reg_dyn_cvol,
                   pf_raw, pf_cvol, pf_dyn, ds_raw, ds_dyn, worst_raw_ym, dyn_mdt,
                   sr_raw_pre, sr_cvol_pre, sr_dyn_pre, sr_raw_post, sr_cvol_post, sr_dyn_post,
                   reg_post, mf, grade, score, vm$bear_pct %||% (100 * mean(bear_dt$I_B, na.rm = TRUE)),
                   charts, dry_run = tg_dry_run),
    error = function(e) cat("[DM][TG] 발송 실패:", conditionMessage(e), "\n"))

  invisible(result)
}

# ---- 텔레그램 brief --------------------------------------------------------
.send_dm_brief <- function(strategy_name, strategy_idea, strategy_id, reg_dyn_raw, reg_dyn_cvol,
                           pf_raw, pf_cvol, pf_dyn, ds_raw, ds_dyn, worst_raw_ym, dyn_mdt,
                           sr_raw_pre, sr_cvol_pre, sr_dyn_pre, sr_raw_post, sr_cvol_post, sr_dyn_post,
                           reg_post, mf, grade, score, bear_pct, charts, dry_run = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  rt <- function(r) if (is.null(r)) "n/a" else sprintf("%+.2f%%/yr (t=%.2f)", .as_num(r$alpha_ann_pct), .as_num(r$alpha_t))
  sr_raw <- .as_num(pf_raw$Sharpe); sr_cvol <- .as_num(pf_cvol$Sharpe); sr_dyn <- .as_num(pf_dyn$Sharpe)
  d_sr_dyn_cvol <- sr_dyn - sr_cvol
  verdict_word <- if (!is.null(reg_dyn_cvol) && .as_num(reg_dyn_cvol$alpha_t) >= 2.0 && d_sr_dyn_cvol > 0)
                    "dynamic이 constant-vol 초월(유의)"
                  else if (d_sr_dyn_cvol > 0) "dynamic 부분 개선(무유의)"
                  else "dynamic이 constant-vol 미달"
  wmym <- as.character(worst_raw_ym$ym)
  wm_dyn <- .as_num(dyn_mdt[ym == wmym, dyn]); wm_raw <- .as_num(worst_raw_ym$raw)
  ctx <- sprintf(paste0("[연구목적] Daniel-Moskowitz(2016) 동적 모멘텀 KR 충실복제.\n",
                        "[방법] WML(decile D10-D1 VW 12-2) · w∝μ̂/σ̂²(μ̂=bear×시장분산 expanding 회귀, σ̂²=126일 WML실현분산) · target vol 19%% · K200∪KQ150 · 2005~.\n",
                        "[결론] 샤프 raw %.2f → cvol %.2f → dyn %.2f · dyn~cvol α %s (%s)."),
                 sr_raw, sr_cvol, sr_dyn, rt(reg_dyn_cvol), verdict_word)
  kv <- list(
    "샤프 raw/cvol/dyn"   = sprintf("%.2f / %.2f / %.2f", sr_raw, sr_cvol, sr_dyn),
    "회귀 α dyn~raw"      = rt(reg_dyn_raw),
    "회귀 α dyn~cvol"     = rt(reg_dyn_cvol),
    "최대낙폭 raw/dyn"    = sprintf("%.1f%% / %.1f%%", -abs(.as_num(pf_raw$MDD)), -abs(.as_num(pf_dyn$MDD))),
    "왜도 raw→dyn"        = sprintf("%.2f → %.2f", .as_num(ds_raw$skew), .as_num(ds_dyn$skew)),
    "최악월(raw)"         = sprintf("%s raw%+.0f%% / dyn%+.0f%%", wmym, wm_raw * 100, wm_dyn * 100),
    "서브 샤프 dyn pre/post" = sprintf("pre %.2f / post %.2f", .as_num(sr_dyn_pre), .as_num(sr_dyn_post)),
    "post2017 dyn~cvol"   = if (!is.null(reg_post)) rt(reg_post) else "n/a",
    "bear 월비율"         = sprintf("%.0f%% (I_B=1, 24m<0)", .as_num(bear_pct)),
    "등급(허들·long-only)" = sprintf("%s · %.0f/100", as.character(grade), .as_num(score) %||% 0))
  if (!is.null(mf)) { best <- mf[[names(mf)[1]]]
    kv[["팩터모델 α(raw WML)"]] <- sprintf("%s %+.2f%%/yr (t=%.2f)", as.character(best$model),
                                          .as_num(best$alpha) * 12 * 100, .as_num(best$alpha_tstat)) }
  notes <- c(
    "3-way: raw(static L/S) / cvol(constant-vol BSC형) / dyn(eq.5 w∝μ̂/σ̂²) 전부 target vol 19% 매칭",
    "헤드라인 = dyn~cvol α (μ타이밍 증분 — DM 핵심 주장: dynamic>constant-vol)",
    "μ̂는 expanding-window OOS(매월 γ 재추정) — DM in-sample 대비 PIT 보강(명시 일탈)",
    if (!is.null(reg_dyn_cvol) && .as_num(reg_dyn_cvol$alpha_t) >= 2.0) "dyn~cvol α 유의(t≥2) — μ타이밍 작동"
      else "dyn~cvol α 무유의(t<2) — KR에서 μ타이밍 약함",
    "decile L/S 논문구조는 production(long-only)과 충돌 — 검증단계 논문 우선(명시 보고)",
    "비용한계: 엔진=flat per-rebalance 15bps. L/S 양다리+레버리지 → 과소계상 가능")
  sections <- list(
    list(type = "text", emoji = "\U0001F4DA", heading = "연구 컨텍스트", body = ctx),
    list(type = "text", emoji = "\U0001F4A1", heading = "전략 아이디어", body = strategy_idea),
    list(type = "kv",   emoji = "\U0001F4C8", heading = "성과 요약(raw/cvol/dyn)", kv = kv),
    list(type = "bullet", emoji = "\U0001F4DD", heading = "해석/주의", items = notes))
  tg_agent_brief(agent = "AlphaSearch",
                 title = sprintf("알파 서칭 — Daniel-Moskowitz 동적 모멘텀 (등급 %s)", grade),
                 sections = sections, charts = charts, lock_scope = strategy_id, dry_run = dry_run)
}

cat("[run_dm_momentum] loaded. usage: run_dm_momentum()\n")
