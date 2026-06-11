#!/usr/bin/env Rscript
# =============================================================================
# run_bsc_momentum.R — Barroso & Santa-Clara (2015, JFE) 충실 복제 오케스트레이터
# =============================================================================
# alpha-search 모드. run_alpha_search(횡단면 top-N 선택기)는 L/S 2x3 VW + 시계열
# scaling 복제 불가 → 별도 엔진(bsc_engine.R) 사용. 측정·리포팅 백엔드 재사용:
#   summarise_perf / generate_charts / run_hurdle_gate / run_multifactor_regression
#   / tg_agent_brief.  자체합성 금지·measurement 규율 유지.
#
# 산출(3종):
#   1. Faithful: raw WML vs risk-managed WML (L/S, 무캡). 헤드라인 = managed~raw 회귀 α.
#   2. Implementable 진단: long leg(High 2포트 VW)에 λ 캡[0,1] long-only 무레버리지.
#   3. 2차트 + 텔레그램 + L-code.
# 기간 2005-01-01~ 고정. 유니버스 K200∪KQ150 고정(시변 PIT 멤버십).
# =============================================================================

suppressWarnings(suppressMessages({ library(data.table); library(xts); library(jsonlite) }))

.BSC_INFRA <- local({
  cand <- Sys.getenv("QVEST_INFRA_DIR", "")
  if (nzchar(cand) && file.exists(file.path(cand, "config.R"))) return(cand)
  file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")), "02_Infrastructure")
})
source(file.path(.BSC_INFRA, "config.R"))
source(file.path(.BSC_INFRA, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
source(file.path(.BSC_INFRA, "hurdle_gate.R"))
source(file.path(.BSC_INFRA, "factor_portfolios.R"))
source(file.path(.BSC_INFRA, "alpha_search", "bsc_engine.R"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

# =============================================================================
run_bsc_momentum <- function(start_date     = "2005-01-01",
                             sigma_target   = 0.12,
                             rv_win         = 126L,
                             commission     = 0.0015,
                             send_telegram  = TRUE,
                             tg_dry_run     = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  run_id <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_name <- "BSC RiskManaged Momentum (KR)"
  strategy_id   <- paste0("STR_AS_BSC_", run_id)
  strategy_idea <- paste0(
    "Barroso-Santa-Clara(2015) 위험관리 모멘텀: WML(2x3 size×prior 12-2 VW L/S)을 ",
    "직전 126일 실현변동성으로 σ_target=12%에 맞춰 scaling(λ=σ_tgt/σ̂). 모멘텀 크래시 제거 검증.")

  OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

  # ---- 1. RAWDATA + 시그널 월말 ---------------------------------------------
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
  if (!inherits(BM_DT$Date, "Date")) BM_DT[, Date := as.Date(Date)]
  setorder(RAWDATA, Ticker, Date)
  all_dates <- sort(unique(RAWDATA$Date))
  # 시그널 월말 = 각 달 마지막 거래일, start_date~
  RAWDATA[, .ym := format(Date, "%Y-%m")]
  me_all <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
  RAWDATA[, .ym := NULL]
  sig_dates <- sort(me_all[me_all >= as.Date(start_date)])
  cat(sprintf("\n=== [BSC] %s (%s) ===\n  signal months=%d  %s~%s\n",
              strategy_name, strategy_id, length(sig_dates),
              as.character(min(sig_dates)), as.character(max(sig_dates))))

  # ---- 2. WML 일간 시계열 구성 (2x3 VW L/S, 12-2) ---------------------------
  wml <- bsc_build_wml(RAWDATA, all_dates, sig_dates,
                       skip_d = 21L, look_d = 252L, liq_thresh = 2e8, liq_win = 20L)
  daily_wml <- wml$daily
  cat(sprintf("  WML 일간행=%d  %s~%s | 유니버스 중앙값=%d\n",
              nrow(daily_wml), as.character(min(daily_wml$Date)), as.character(max(daily_wml$Date)),
              as.integer(median(wml$diag$n_uni))))

  # ---- 3. BSC scaling (faithful 무캡 + implementable long-only 캡) ----------
  vm <- bsc_managed_series(daily_wml[, .(Date, WML, Hi)], sigma_target = sigma_target, rv_win = rv_win)
  d <- vm$daily
  d <- d[is.finite(WML)]              # WML 정의 구간
  # faithful은 λ 정의 구간(초기 126d+1개월 이후)만
  d_mgd <- d[is.finite(WML_mgd)]
  cat(sprintf("  managed 정의구간 시작=%s (σ̂ 126d + 1개월 lag)\n", as.character(min(d_mgd$Date))))

  raw_xts  <- xts(d$WML,      order.by = d$Date);      names(raw_xts) <- "RawWML"
  mgd_xts  <- xts(d_mgd$WML_mgd, order.by = d_mgd$Date); names(mgd_xts) <- "MgdWML"
  hi_xts   <- xts(d$Hi,       order.by = d$Date);      names(hi_xts) <- "LongLeg"
  himgd_xts<- xts(d_mgd$Hi_mgd, order.by = d_mgd$Date); names(himgd_xts) <- "LongLegMgd"

  # ---- 4. 헤드라인 회귀 α: managed ~ raw WML --------------------------------
  reg <- bsc_regression_alpha(mgd_xts, raw_xts)
  cat("\n  [헤드라인 회귀 α: managed WML ~ raw WML]\n")
  if (!is.null(reg)) cat(sprintf("    α=%+.2f%%/yr  t=%.2f  β=%.2f  R²=%.2f  n=%d  (NW lag=%d)\n",
                                 reg$alpha_ann_pct, reg$alpha_t, reg$beta, reg$r2, reg$n, reg$nw_lag))

  # ---- 5. 성과 비교 (PerformanceAnalytics summarise_perf) -------------------
  pf_raw <- summarise_perf(raw_xts, "raw WML (L/S)")
  pf_mgd <- summarise_perf(mgd_xts, "managed WML (L/S, 무캡)")
  pf_hi  <- summarise_perf(hi_xts,  "long leg raw (LO)")
  pf_himgd <- summarise_perf(himgd_xts, "long leg managed (LO cap)")
  perf_tbl <- rbindlist(list(pf_raw, pf_mgd, pf_hi, pf_himgd), fill = TRUE)
  cat("\n  [성과 비교]\n"); print(perf_tbl[, .(Label, CAGR, AnnVol, Sharpe, MDD, Calmar)])

  # ---- 6. 분포(왜도/첨도) + 크래시 월 비교 ----------------------------------
  ds_raw <- bsc_dist_stats(raw_xts); ds_mgd <- bsc_dist_stats(mgd_xts)
  cat(sprintf("\n  [분포] raw skew=%.2f kurt=%.2f worstM=%.1f%% | managed skew=%.2f kurt=%.2f worstM=%.1f%%\n",
              ds_raw$skew, ds_raw$kurt, ds_raw$worst_m * 100,
              ds_mgd$skew, ds_mgd$kurt, ds_mgd$worst_m * 100))
  # KR 모멘텀 크래시 월 (2009 리바운드 등): raw vs managed 월간수익
  raw_m <- apply.monthly(raw_xts, Return.cumulative); mgd_m <- apply.monthly(mgd_xts, Return.cumulative)
  raw_mdt <- data.table(ym = format(as.Date(index(raw_m)), "%Y-%m"), raw = as.numeric(raw_m[, 1]))
  mgd_mdt <- data.table(ym = format(as.Date(index(mgd_m)), "%Y-%m"), mgd = as.numeric(mgd_m[, 1]))
  crash_focus <- c("2009-04", "2009-05", "2009-06", "2009-07", "2020-03", "2020-04")
  crash_tbl <- merge(raw_mdt, mgd_mdt, by = "ym", all = TRUE)[ym %in% crash_focus]
  worst_raw_ym <- raw_mdt[which.min(raw)]
  cat("\n  [크래시 월: raw vs managed]\n")
  if (nrow(crash_tbl)) for (j in seq_len(nrow(crash_tbl)))
    cat(sprintf("    %s  raw=%+.1f%%  managed=%+.1f%%\n", crash_tbl$ym[j],
                crash_tbl$raw[j] * 100, crash_tbl$mgd[j] * 100))
  cat(sprintf("    [전체 raw 최악월] %s raw=%+.1f%% managed=%+.1f%%\n",
              worst_raw_ym$ym, worst_raw_ym$raw * 100,
              mgd_mdt[ym == worst_raw_ym$ym, mgd] %||% NA_real_ * 100))

  # ---- 7. pre/post-2017 서브피리어드 (managed 회귀 α + Sharpe) --------------
  sub_pre  <- bsc_regression_alpha(mgd_xts[index(mgd_xts) < as.Date("2017-01-01")],
                                   raw_xts[index(raw_xts) < as.Date("2017-01-01")])
  sub_post <- bsc_regression_alpha(mgd_xts[index(mgd_xts) >= as.Date("2017-01-01")],
                                   raw_xts[index(raw_xts) >= as.Date("2017-01-01")])
  sr_raw_pre  <- .as_num(summarise_perf(raw_xts[index(raw_xts) < as.Date("2017-01-01")], "x")$Sharpe)
  sr_mgd_pre  <- .as_num(summarise_perf(mgd_xts[index(mgd_xts) < as.Date("2017-01-01")], "x")$Sharpe)
  sr_raw_post <- .as_num(summarise_perf(raw_xts[index(raw_xts) >= as.Date("2017-01-01")], "x")$Sharpe)
  sr_mgd_post <- .as_num(summarise_perf(mgd_xts[index(mgd_xts) >= as.Date("2017-01-01")], "x")$Sharpe)
  cat(sprintf("\n  [서브피리어드 Sharpe raw→managed]  pre2017: %.2f→%.2f | post2017: %.2f→%.2f\n",
              sr_raw_pre, sr_mgd_pre, sr_raw_post, sr_mgd_post))

  # ---- 8. 회전율(one-way TO) + 비용 경고 ------------------------------------
  # WML L/S 양다리. long leg는 매월 High 2포트 재선정. TO proxy: monthly λ_cap 변화 +
  # 종목 회전. 보수적 추정: 모멘텀 월간 리밸 단일팩터 long leg one-way TO ≈ 월 0.3~0.5
  # → 연 4~6x (decile 모멘텀 표준). L/S는 약 2배. 명시 산출:
  mw <- vm$monthly
  setorder(mw, MEnd)
  mw[, dlam := abs(lambda - shift(lambda, 1L))]
  to_lambda_ann <- 12 * mean(mw$dlam[is.finite(mw$dlam)] %||% 0, na.rm = TRUE)
  # 종목 회전은 별도 산출(High leg 멤버십 변화). 근사 상한 보고용.
  cat(sprintf("\n  [회전율] λ 월변화 연환산≈%.2f (스케일 회전만; 종목 회전 별도)\n", to_lambda_ann))

  # ---- 9. implementable sim_result → 백엔드(차트/허들) -----------------------
  impl_daily <- d_mgd[, .(Date, Ret = Hi_mgd)]
  mw_w <- mw[, .(MEnd, w = pmin(pmax(lambda, 0), 1))]
  sim <- bsc_build_sim_result(impl_daily, BM_DT, mw_w)

  tryCatch(generate_charts(sim, output_dir = OUT_DIR, strategy_name = "BSC managed long-leg (KR)"),
           error = function(e) cat("[BSC] generate_charts 생략:", conditionMessage(e), "\n"))
  charts <- Filter(file.exists, c(file.path(OUT_DIR, "equity_curve.png"),
                                  file.path(OUT_DIR, "annual_returns.png")))

  hg <- tryCatch(run_hurdle_gate(sim_result = sim, FACTORS = NULL,
                                 strategy_name = strategy_name, output_dir = OUT_DIR),
                 error = function(e) { cat("[BSC] hurdle 예외:", conditionMessage(e), "\n")
                                       list(grade = "F", score = NA_real_, verdict = list()) })
  assign("%||%", `%||%`, envir = globalenv())
  grade <- hg$grade %||% "uncertain"; score <- .as_num(hg$score)
  m <- hg$verdict$metrics %||% list()

  # ---- 10. FF3/FF5/Carhart α (raw WML L/S vs KR 팩터) -----------------------
  mf <- tryCatch({
    fdt <- load_kr_factor_returns()
    run_multifactor_regression(raw_xts, NULL, fdt)
  }, error = function(e) { cat("[BSC] multifactor 생략:", conditionMessage(e), "\n"); NULL })
  if (!is.null(mf)) {
    cat("\n  [FF3/FF5/Carhart α — raw WML]\n")
    for (nm in names(mf)) cat(sprintf("    %-10s α=%+.2f%%/yr t=%.2f R²=%.2f\n",
                                      mf[[nm]]$model, mf[[nm]]$alpha * 12 * 100, mf[[nm]]$alpha_tstat, mf[[nm]]$adj_r2))
  }

  # ---- 11. 결과 JSON --------------------------------------------------------
  result <- list(
    strategy_id = strategy_id, strategy_name = strategy_name, run_id = run_id,
    paper = "Barroso & Santa-Clara (2015, JFE)", start_date = start_date,
    sigma_target = sigma_target, rv_win = rv_win, universe = "K200_KQ150 (시변 PIT)",
    metric_type = "proxy",
    headline_reg = reg,
    perf = list(
      raw_wml      = as.list(pf_raw[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)]),
      managed_wml  = as.list(pf_mgd[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)]),
      long_raw     = as.list(pf_hi[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)]),
      long_managed = as.list(pf_himgd[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)])),
    dist = list(raw = ds_raw, managed = ds_mgd),
    crash = as.list(crash_tbl), worst_raw_month = as.list(worst_raw_ym),
    subperiod = list(
      pre2017  = list(reg = sub_pre,  sr_raw = sr_raw_pre,  sr_mgd = sr_mgd_pre),
      post2017 = list(reg = sub_post, sr_raw = sr_raw_post, sr_mgd = sr_mgd_post)),
    turnover_lambda_ann = to_lambda_ann,
    factor_alpha = if (!is.null(mf)) lapply(mf, function(r) list(
      model = r$model, alpha_ann_pct = r$alpha * 12 * 100, t = r$alpha_tstat, adj_r2 = r$adj_r2)) else NULL,
    grade = grade, score = score, out_dir = OUT_DIR, charts = charts)
  writeLines(toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
             file.path(OUT_DIR, "bsc_result.json"))
  cat(sprintf("\n  결과 저장: %s\n", file.path(OUT_DIR, "bsc_result.json")))

  # ---- 12. 텔레그램 ---------------------------------------------------------
  if (isTRUE(send_telegram)) tryCatch(
    .send_bsc_brief(strategy_name, strategy_idea, strategy_id, reg,
                    pf_raw, pf_mgd, pf_himgd, ds_raw, ds_mgd, crash_tbl, worst_raw_ym, mgd_mdt,
                    sr_raw_pre, sr_mgd_pre, sr_raw_post, sr_mgd_post, mf, grade, score,
                    to_lambda_ann, charts, dry_run = tg_dry_run),
    error = function(e) cat("[BSC][TG] 발송 실패:", conditionMessage(e), "\n"))

  invisible(result)
}

# ---- 텔레그램 brief --------------------------------------------------------
.send_bsc_brief <- function(strategy_name, strategy_idea, strategy_id, reg,
                            pf_raw, pf_mgd, pf_himgd, ds_raw, ds_mgd, crash_tbl, worst_raw_ym, mgd_mdt,
                            sr_raw_pre, sr_mgd_pre, sr_raw_post, sr_mgd_post, mf, grade, score,
                            to_lambda_ann, charts, dry_run = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  rt <- function(r) if (is.null(r)) "n/a" else sprintf("%+.2f%%/yr (t=%.2f)", .as_num(r$alpha_ann_pct), .as_num(r$alpha_t))
  score <- .as_num(score)
  d_sr <- .as_num(pf_mgd$Sharpe) - .as_num(pf_raw$Sharpe)
  verdict_word <- if (!is.null(reg) && reg$alpha_t >= 2.0 && d_sr > 0) "위험관리 효과 확인"
                  else if (d_sr > 0) "부분 개선" else "효과 미확인"
  wmym <- as.character(worst_raw_ym$ym)
  wm_mgd <- .as_num(mgd_mdt[ym == wmym, mgd]); wm_raw <- .as_num(worst_raw_ym$raw)
  sr_raw_pre <- .as_num(sr_raw_pre); sr_mgd_pre <- .as_num(sr_mgd_pre)
  sr_raw_post <- .as_num(sr_raw_post); sr_mgd_post <- .as_num(sr_mgd_post)
  ctx <- sprintf(paste0("[연구목적] Barroso-Santa-Clara(2015) 위험관리 모멘텀 KR 충실복제.\n",
                        "[방법] WML(2x3 size×prior 12-2 VW L/S) · 직전 126일 실현변동성으로 σ목표 12%% scaling · K200∪KQ150 · 2005~.\n",
                        "[결론] 헤드라인 회귀 α(managed~raw) %s · 샤프 %.2f→%.2f (%s)."),
                 rt(reg), .as_num(pf_raw$Sharpe), .as_num(pf_mgd$Sharpe), verdict_word)
  kv <- list(
    "회귀 α(managed~raw)" = rt(reg),
    "샤프 raw→관리"       = sprintf("%.2f → %.2f (Δ%+.2f)", .as_num(pf_raw$Sharpe), .as_num(pf_mgd$Sharpe), d_sr),
    "최대낙폭 raw→관리"   = sprintf("%.1f%% → %.1f%%", -abs(.as_num(pf_raw$MDD)), -abs(.as_num(pf_mgd$MDD))),
    "왜도 raw→관리"       = sprintf("%.2f → %.2f", .as_num(ds_raw$skew), .as_num(ds_mgd$skew)),
    "첨도 raw→관리"       = sprintf("%.1f → %.1f", .as_num(ds_raw$kurt), .as_num(ds_mgd$kurt)),
    "최악월(raw)"         = sprintf("%s raw%+.0f%% / 관리%+.0f%%", wmym, wm_raw * 100, wm_mgd * 100),
    "서브 샤프 pre/post"  = sprintf("pre %.2f→%.2f / post %.2f→%.2f", sr_raw_pre, sr_mgd_pre, sr_raw_post, sr_mgd_post),
    "long-only 관리 샤프" = sprintf("%.2f (캡[0,1])", .as_num(pf_himgd$Sharpe)),
    "등급(허들)"          = sprintf("%s · %.0f/100", as.character(grade), .as_num(score) %||% 0))
  if (!is.null(mf)) { best <- mf[[names(mf)[1]]]
    kv[["팩터모델 α(raw WML)"]] <- sprintf("%s %+.2f%%/yr (t=%.2f)", as.character(best$model), .as_num(best$alpha) * 12 * 100, .as_num(best$alpha_tstat)) }
  notes <- c(
    "faithful=L/S 무캡(논문 원형, 레버리지 허용) / implementable=long leg λ캡[0,1] long-only",
    "헤드라인 검정 = managed를 raw WML에 회귀한 α (논문 정의)",
    if (!is.null(reg) && .as_num(reg$alpha_t) >= 2.0) "회귀 α 유의(t≥2) — 변동성 타이밍 작동" else "회귀 α 무유의(t<2) — KR에서 BSC 약함",
    "L/S 논문구조는 production(long-only)과 충돌 — 검증단계 논문 우선(명시 보고)",
    sprintf("비용한계: 엔진=flat per-rebalance 15bps. L/S 양다리 회전 → 과소계상 가능"))
  sections <- list(
    list(type = "text", emoji = "\U0001F4DA", heading = "연구 컨텍스트", body = ctx),
    list(type = "text", emoji = "\U0001F4A1", heading = "전략 아이디어", body = strategy_idea),
    list(type = "kv",   emoji = "\U0001F4C8", heading = "성과 요약(raw vs 위험관리)", kv = kv),
    list(type = "bullet", emoji = "\U0001F4DD", heading = "해석/주의", items = notes))
  tg_agent_brief(agent = "AlphaSearch",
                 title = sprintf("알파 서칭 — Barroso-Santa-Clara 위험관리 모멘텀 (등급 %s)", grade),
                 sections = sections, charts = charts, lock_scope = strategy_id, dry_run = dry_run)
}

cat("[run_bsc_momentum] loaded. usage: run_bsc_momentum()\n")
