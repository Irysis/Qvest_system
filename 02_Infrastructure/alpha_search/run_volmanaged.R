#!/usr/bin/env Rscript
# =============================================================================
# run_volmanaged.R — Moreira & Muir (2017, JF) 충실 복제 오케스트레이터
# =============================================================================
# alpha-search 모드 변형: run_alpha_search(횡단면 top-N 선택기)는 시계열 scaling
# 전략(MM)을 충실 복제할 수 없으므로 우회. 단 측정·리포팅 백엔드는 재사용:
#   generate_charts / run_hurdle_gate / register_module / run_multifactor_regression
#   / summarise_perf / tg_agent_brief.  (자체합성 금지·measurement 규율 유지)
#
# 기저자산(base)에 vol-management 적용:
#   - "market"        : KR 시장(BM_DT$BM_Ret) — 논문 헤드라인(vol-managed market)
#   - "STR_<id>"      : 04_Research/strategies/<id>/sim_result.rds (예 STR_str1715v2 코어)
#
# 산출: faithful(논문원형·무제약) + implementable(long-only no-leverage cap) 비교
#       + 헤드라인 회귀 α(managed~unmanaged, NW) + FF3/FF5/Carhart α + 2차트 + 텔레그램.
# 기간 2005-01-01~ 고정(도훈 mandate). 유니버스 개념 무관(단일 기저 시계열).
# =============================================================================

suppressWarnings(suppressMessages({ library(data.table); library(xts); library(jsonlite) }))

.VM_FIND_ROOT <- function() {
  candidates <- unique(c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[run_volmanaged] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
.VM_PROJECT_ROOT <- .VM_FIND_ROOT()
.VM_INFRA <- local({
  cand <- Sys.getenv("QVEST_INFRA_DIR", "")
  if (nzchar(cand) && file.exists(file.path(cand, "config.R"))) return(cand)
  file.path(.VM_PROJECT_ROOT, "02_Infrastructure")
})
source(file.path(.VM_INFRA, "config.R"))
if (!exists("PROJECT_ROOT", inherits = TRUE)) PROJECT_ROOT <- .VM_PROJECT_ROOT
if (!nzchar(Sys.getenv("CLAUDE_PROJECT_DIR", ""))) Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT)
if (!nzchar(Sys.getenv("QM_ROOT", ""))) Sys.setenv(QM_ROOT = PROJECT_ROOT)
source(file.path(.VM_INFRA, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
source(file.path(.VM_INFRA, "hurdle_gate.R"))
source(file.path(.VM_INFRA, "factor_portfolios.R"))     # run_multifactor_regression
source(file.path(.VM_INFRA, "alpha_search", "vm_engine.R"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

# =============================================================================
run_volmanaged <- function(base_spec       = "market",
                           base_label       = NULL,
                           strategy_idea    = NULL,
                           start_date       = "2005-01-01",
                           min_hist_months  = 24L,
                           commission       = 0.0015,
                           send_telegram    = TRUE,
                           tg_dry_run       = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  run_id <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())

  # ---- 1. 기저자산 일간수익 + 시장 벤치마크 로드 ----------------------------
  res <- load_rawdata(use_cache = TRUE)
  BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date")) BM_DT[, Date := as.Date(Date)]
  setorder(BM_DT, Date)

  if (identical(base_spec, "market")) {
    base_dt   <- BM_DT[, .(Date, Ret = BM_Ret)]
    base_label <- base_label %||% "KR Market (KOSPI200)"
    is_market  <- TRUE
  } else {
    sp <- file.path(PROJECT_ROOT, "04_Research", "strategies", base_spec, "sim_result.rds")
    stopifnot(file.exists(sp))
    s <- readRDS(sp)
    nav <- as.data.table(s$DAILY_NAV_DT)
    if (!inherits(nav$Date, "Date")) nav[, Date := as.Date(Date)]
    base_dt   <- nav[, .(Date, Ret = Strategy_Ret)]
    base_label <- base_label %||% base_spec
    is_market  <- FALSE
  }
  base_dt <- base_dt[is.finite(Ret) & Date >= as.Date(start_date)]
  setorder(base_dt, Date)

  # ★ 일간 빈도 가드 (도훈 발견 2026-06-07): MM은 월내 일간수익으로 실현분산을
  #   추정한다. 기저가 월간(예 STR_1715 sim_result는 월간 NAV)이면 RV 퇴화 → c=NA →
  #   scaling 미발생 + 연율화 인공물(Sharpe 28·CAGR 2500%) = fabrication. 명시 중단.
  med_gap <- as.numeric(median(diff(as.numeric(base_dt$Date))))
  if (!is.finite(med_gap) || med_gap > 7) {
    stop(sprintf(paste0("[VolManaged] 기저자산이 일간이 아님(median gap %.1f일). ",
      "MM은 월내 일간수익으로 실현분산을 추정하므로 일간 시계열 필수. ",
      "base_spec='%s'는 월간(rows=%d)이라 검증 불가 — 일간 NAV 재백테 필요(forge 영역, 범위 밖)."),
      med_gap, base_spec, nrow(base_dt)))
  }
  strategy_name <- sprintf("VolMgd(%s)", base_label)
  strategy_id   <- paste0("STR_VM_", run_id)
  strategy_idea <- strategy_idea %||% sprintf(
    "Moreira-Muir(2017) 변동성관리: %s 노출을 직전월 실현분산 역수로 scaling(c/σ²). 충실복제.", base_label)
  if (is.null(getOption("vm_out_root"))) options(vm_out_root = file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search"))
  OUT_DIR <- file.path(getOption("vm_out_root"), run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [VolManaged] %s (%s) ===\n  base=%s rows=%d  %s~%s\n",
              strategy_name, strategy_id, base_spec, nrow(base_dt),
              min(base_dt$Date), max(base_dt$Date)))

  # ---- 2. MM 엔진: faithful + implementable 일간 시계열 --------------------
  vm <- vm_managed_series(base_dt, min_hist_months = min_hist_months, cap = 1.0)
  daily <- vm$daily
  cat(sprintf("  c_full=%.4g | months=%d\n", vm$c_full, nrow(vm$monthly)))

  base_xts     <- xts(daily$Ret_base,     order.by = daily$Date); names(base_xts) <- "Base"
  faithful_xts <- xts(daily$Ret_faithful, order.by = daily$Date); names(faithful_xts) <- "Faithful"
  impl_xts     <- xts(daily$Ret_impl,     order.by = daily$Date); names(impl_xts) <- "Impl"

  # ---- 3. 헤드라인 검정: managed ~ unmanaged 회귀 α (논문 정의) -------------
  reg_faithful <- vm_regression_alpha(faithful_xts, base_xts)
  reg_impl     <- vm_regression_alpha(impl_xts,     base_xts)
  cat("\n  [MM 회귀 α: managed ~ unmanaged base]\n")
  for (nm in c("faithful", "impl")) {
    r <- if (nm == "faithful") reg_faithful else reg_impl
    if (!is.null(r)) cat(sprintf("    %-9s α=%+.2f%%/yr  t=%.2f  β=%.2f  R²=%.2f  n=%d\n",
                                 nm, r$alpha_ann_pct, r$alpha_t, r$beta, r$r2, r$n))
  }

  # ---- 4. 성과 비교 (PerformanceAnalytics summarise_perf) -------------------
  pf_base <- summarise_perf(base_xts,     paste0("Base | ", base_label))
  pf_fai  <- summarise_perf(faithful_xts, "Faithful (lev)")
  pf_imp  <- summarise_perf(impl_xts,     "Implementable (LO cap)")
  perf_tbl <- rbindlist(list(pf_base, pf_fai, pf_imp), fill = TRUE)
  cat("\n  [성과 비교]\n"); print(perf_tbl[, .(Label, CAGR, AnnVol, Sharpe, MDD, Calmar)])

  # ---- 5. sim_result(implementable) 구성 → 백엔드 재사용 -------------------
  sim <- build_vm_sim_result(daily[, .(Date, Ret = Ret_impl)], BM_DT, vm$monthly)

  tryCatch({
    source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = NA_character_, origin_mode = "alpha_search",
                    role = "overlay_volmgd", meta = list(strategy_idea = strategy_idea, base = base_spec))
    assign("%||%", `%||%`, envir = globalenv())
  }, error = function(e) cat("[VolManaged] register_module 생략:", conditionMessage(e), "\n"))

  tryCatch(generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name),
           error = function(e) cat("[VolManaged] generate_charts 생략:", conditionMessage(e), "\n"))
  charts <- Filter(file.exists, c(file.path(OUT_DIR, "equity_curve.png"),
                                  file.path(OUT_DIR, "annual_returns.png")))

  hg <- tryCatch(run_hurdle_gate(sim_result = sim, FACTORS = NULL,
                                 strategy_name = strategy_name, output_dir = OUT_DIR),
                 error = function(e) { cat("[VolManaged] hurdle 예외:", conditionMessage(e), "\n")
                                       list(grade = "F", score = NA_real_, verdict = list()) })
  assign("%||%", `%||%`, envir = globalenv())
  grade <- hg$grade %||% "uncertain"; score <- .as_num(hg$score)
  m <- hg$verdict$metrics %||% list(); sdef <- hg$verdict$statistical_defense %||% list()

  # ---- 6. FF3/FF5/Carhart α (managed implementable vs KR 팩터) ------------
  mf <- tryCatch({
    fdt <- load_kr_factor_returns()
    run_multifactor_regression(impl_xts, sim$bm_xts, fdt)
  }, error = function(e) { cat("[VolManaged] multifactor 생략:", conditionMessage(e), "\n"); NULL })
  if (!is.null(mf)) {
    cat("\n  [FF3/FF5/Carhart α — implementable]\n")
    for (nm in names(mf)) cat(sprintf("    %-10s α=%+.2f%%/yr t=%.2f R²=%.2f\n",
                                      mf[[nm]]$model, mf[[nm]]$alpha*12*100, mf[[nm]]$alpha_tstat, mf[[nm]]$adj_r2))
  }

  # ---- 7. 결과 JSON 저장 ---------------------------------------------------
  result <- list(
    strategy_id = strategy_id, strategy_name = strategy_name, base = base_spec,
    base_label = base_label, run_id = run_id, start_date = start_date,
    mm_regression = list(faithful = reg_faithful, implementable = reg_impl),
    perf = list(
      base          = as.list(pf_base[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)]),
      faithful      = as.list(pf_fai[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)]),
      implementable = as.list(pf_imp[, .(CAGR, AnnVol, Sharpe, MDD, Calmar)])),
    factor_alpha = if (!is.null(mf)) lapply(mf, function(r) list(
      model = r$model, alpha_ann_pct = r$alpha*12*100, t = r$alpha_tstat, adj_r2 = r$adj_r2)) else NULL,
    grade = grade, score = score, out_dir = OUT_DIR, charts = charts)
  writeLines(toJSON(result, auto_unbox = TRUE, pretty = TRUE, na = "null"),
             file.path(OUT_DIR, "vm_result.json"))
  cat(sprintf("\n  결과 저장: %s\n", file.path(OUT_DIR, "vm_result.json")))

  # ---- 8. 텔레그램 (tg_agent_brief 단일 진입점) ----------------------------
  if (isTRUE(send_telegram)) tryCatch(
    .send_vm_brief(strategy_name, strategy_idea, strategy_id, base_label,
                   reg_impl, reg_faithful, pf_base, pf_imp, pf_fai, mf, grade, score, m,
                   charts, dry_run = tg_dry_run),
    error = function(e) cat("[VolManaged][TG] 발송 실패:", conditionMessage(e), "\n"))

  invisible(result)
}

# ---- 텔레그램 brief --------------------------------------------------------
.send_vm_brief <- function(strategy_name, strategy_idea, strategy_id, base_label,
                           reg_impl, reg_faithful, pf_base, pf_imp, pf_fai, mf, grade, score, m,
                           charts, dry_run = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  rt <- function(r) if (is.null(r)) "n/a" else sprintf("%+.2f%%/yr (t=%.2f)", r$alpha_ann_pct, r$alpha_t)
  d_sr  <- .as_num(pf_imp$Sharpe) - .as_num(pf_base$Sharpe)
  verdict_word <- if (!is.null(reg_impl) && reg_impl$alpha_t >= 2.0 && d_sr > 0) "MM 효과 확인"
                  else if (!is.null(reg_impl) && d_sr > 0) "부분 개선"
                  else "효과 미확인"
  ctx <- sprintf(paste0("[연구목적] Moreira-Muir(2017) 변동성관리 KR 충실복제.\n",
                        "[기저] %s · 2005~ · 직전월 실현분산 역수 노출 c/σ².\n",
                        "[결론] MM 회귀 α(implementable, managed~unmanaged) %s · ΔSharpe %+.2f vs 기저 (%s)."),
                 base_label, rt(reg_impl), d_sr, verdict_word)
  kv <- list(
    "기저자산"             = base_label,
    "MM α(impl, vs기저)"  = rt(reg_impl),
    "MM α(faithful 원형)" = rt(reg_faithful),
    "샤프 기저→관리"       = sprintf("%.2f → %.2f (Δ%+.2f)", .as_num(pf_base$Sharpe), .as_num(pf_imp$Sharpe), d_sr),
    "CAGR 기저→관리"       = sprintf("%.1f%% → %.1f%%", .as_num(pf_base$CAGR), .as_num(pf_imp$CAGR)),
    "MDD 기저→관리"        = sprintf("%.1f%% → %.1f%%", -abs(.as_num(pf_base$MDD)), -abs(.as_num(pf_imp$MDD))),
    "칼마 기저→관리"       = sprintf("%.2f → %.2f", .as_num(pf_base$Calmar), .as_num(pf_imp$Calmar)),
    "등급(허들)"           = sprintf("%s · %.0f/100", as.character(grade), score %||% 0))
  if (!is.null(mf)) { best <- mf[[names(mf)[1]]]
    kv[["팩터모델 α"]] <- sprintf("%s %+.2f%%/yr (t=%.2f)", best$model, best$alpha*12*100, best$alpha_tstat) }
  notes <- c(
    sprintf("faithful=레버리지 허용(논문원형) / implementable=long-only no-leverage cap(w≤1)"),
    "헤드라인 검정 = managed를 unmanaged 기저에 회귀한 α (논문 정의)",
    if (!is.null(reg_impl) && reg_impl$alpha_t < 2.0) "회귀 α 무유의(t<2) — KR에서 MM 약함" else "회귀 α 유의 — 변동성 타이밍 작동",
    if (d_sr <= 0) "long-only 캡 적용 시 Sharpe 개선 없음" else "long-only 캡에도 Sharpe 개선")
  sections <- list(
    list(type="text", emoji="\U0001F4DA", heading="연구 컨텍스트", body=ctx),
    list(type="text", emoji="\U0001F4A1", heading="전략 아이디어", body=strategy_idea),
    list(type="kv",   emoji="\U0001F4C8", heading="성과 요약(기저 vs 변동성관리)", kv=kv),
    list(type="bullet", emoji="\U0001F4DD", heading="해석/주의", items=notes))
  tg_agent_brief(agent="AlphaSearch",
                 title=sprintf("알파 서칭 — Moreira-Muir 변동성관리 [%s] (등급 %s)", base_label, grade),
                 sections=sections, charts=charts, lock_scope=strategy_id, dry_run=dry_run)
}

cat("[run_volmanaged] loaded. usage: run_volmanaged(base_spec='market' | 'STR_str1715v2')\n")
