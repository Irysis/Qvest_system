#!/usr/bin/env Rscript
# =============================================================================
# run_pead_paper.R — Bernard & Thomas (1989) PEAD / SUE 논문 그대로 검증 러너
# =============================================================================
# alpha-search 모드. SUE decile primary = 매월 말 SUE 상위 decile EW long-only.
#   유니버스 = KOSPI200 ∪ KOSDAQ150 (PIT 시변 멤버십, 도훈 mandate 고정).
#   + IC 진단(SUE Spearman, advisory) + IS/OOS 분할 + top-25 비교.
# run_alpha_search.R 내부 헬퍼(.send_alpha_search_brief / .write_lcode /
#   .run_axiom_pipeline / .register_strategy_best_effort / .recommend_pg_admission) 재사용.
# QEPM 이행 없음(Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WT/cert 없음). WT-id 미사용.
# 텔레그램 = tg_agent_brief 단일 진입점.
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.AS_INFRA <- local({
  cand <- Sys.getenv("QVEST_INFRA_DIR", "")
  if (nzchar(cand) && file.exists(file.path(cand, "config.R"))) return(cand)
  file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
            Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
            "02_Infrastructure")
})
source(file.path(.AS_INFRA, "alpha_search", "run_alpha_search.R"))   # 엔진 + 내부 헬퍼

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

# ---- 진단: 1개월 forward 종목수익 vs SUE Spearman IC (advisory — 판정권위 아님) ----
.compute_ic <- function(FAC, RAWDATA, signal_col) {
  RD <- RAWDATA[is.finite(Ret), .(Date, Ticker, Ret)]
  RD[, ym := format(Date, "%Y-%m")]
  MR <- RD[, .(MRet = prod(1 + Ret) - 1), by = .(Ticker, ym)]
  cal <- RAWDATA[, .(MEnd = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
  setorder(cal, MEnd); cal[, nxt_ym := shift(ym, 1L, type = "lead")]   # 시그널월 t -> 평가월 t+1
  fac <- FAC[is.finite(get(signal_col)), .(Date, Ticker, sig = get(signal_col))]
  fac <- merge(fac, cal[, .(MEnd, nxt_ym)], by.x = "Date", by.y = "MEnd")
  fac <- merge(fac, MR, by.x = c("Ticker","nxt_ym"), by.y = c("Ticker","ym"))
  ics <- fac[, .(ic = if (.N >= 10L)
                   suppressWarnings(cor(sig, MRet, method = "spearman", use = "complete.obs"))
                 else NA_real_), by = Date]
  ics <- ics[is.finite(ic)]
  list(mean_ic = mean(ics$ic), n = nrow(ics),
       t_ic = if (nrow(ics) > 2L) mean(ics$ic) / (sd(ics$ic) / sqrt(nrow(ics))) else NA_real_,
       hit = mean(ics$ic > 0))
}

.is_oos <- function(sim, split = "2022-01-01") {
  mg <- merge(sim$strategy_xts, sim$bm_xts, join = "inner")
  act <- mg[, 1] - mg[, 2]
  sd_dt <- as.Date(split)
  is_r  <- act[zoo::index(act) <  sd_dt]
  oos_r <- act[zoo::index(act) >= sd_dt]
  sr <- function(r) if (nrow(r) > 20L)
    as.numeric(PerformanceAnalytics::SharpeRatio.annualized(r, Rf = 0)) else NA_real_
  list(is_sr = sr(is_r), oos_sr = sr(oos_r),
       is_n = nrow(is_r), oos_n = nrow(oos_r),
       retention = if (is.finite(sr(is_r)) && abs(sr(is_r)) > 1e-9) sr(oos_r) / sr(is_r) else NA_real_)
}

run_pead_paper <- function(
    strategy_name = "PEAD / SUE (Bernard-Thomas 1989)",
    strategy_idea = "Bernard-Thomas(1989) 실적발표후표류: 분기순이익 계절차분 표준화 어닝서프라이즈(SUE) 상위 decile EW long-only — 최근 6개월 내 공시 최신 SUE 월간 리밸",
    start_date    = "2015-01-01",   # 시그널 floor(접수일 2015-06~ + σ창)는 fe가 결정 — 실효 ~2018~
    oos_split     = "2022-01-01",
    commission    = 0.0015,
    send_telegram = TRUE,
    tg_dry_run    = TRUE,           # 스모크 기본 dry-run. 풀런 wrapper만 FALSE.
    factor_analysis = TRUE) {

  # ★ 함수-로컬 length-safe %||% shadow (run_hurdle_gate/loop_integrator가 global %||%를
  #   vector에 깨지는 `&&` 버전으로 clobber — run_disclosure_meta.R 동일 수리. 2026-06-12,
  #   실측: 풀런이 hurdle 직후 'length = 18 in coercion to logical(1)'로 사망)
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

  fe <- file.path(.AS_INFRA, "alpha_search", "fe_sue_pead.R")
  stopifnot(file.exists(fe))
  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_id <- paste0("STR_AS_", run_id)
  OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [AlphaSearch · 논문스펙] %s (%s) ===\n", strategy_name, strategy_id))
  cat(sprintf("    idea: %s\n", strategy_idea))

  # ---- 1. Data ----
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
  RAWDATA[, TradingValue := Close * Vol]
  RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
  RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

  # ---- 2. Factor engine -> FACTORS(Date, Ticker, Score, SUE, N) ----
  source(fe, local = TRUE)
  stopifnot(exists("FACTORS"), is.data.table(FACTORS),
            all(c("Date","Ticker","Score","N") %in% names(FACTORS)))
  if (!is.null(start_date)) FACTORS <- FACTORS[Date >= as.Date(start_date)]
  stopifnot(nrow(FACTORS) > 0L)

  # ---- 2b. 유니버스 = KOSPI200 ∪ KOSDAQ150 (PIT 시변 멤버십) ----
  stopifnot(all(c("K200","KQ150") %in% names(RAWDATA)))
  .me  <- unique(FACTORS$Date)
  .mem <- unique(RAWDATA[Date %in% .me & (K200 == 1 | KQ150 == 1), .(Date, Ticker)])
  .n0  <- uniqueN(FACTORS$Ticker)
  FACTORS <- merge(FACTORS, .mem, by = c("Date","Ticker"))
  stopifnot(nrow(FACTORS) > 0L)
  # decile N 재산출 (유니버스 필터 후 후보 기준)
  FACTORS[, N := NULL]
  .NDT <- FACTORS[, .(N = as.integer(pmax(1L, round(.N / 10)))), by = Date]
  FACTORS <- merge(FACTORS, .NDT, by = "Date")
  setorder(FACTORS, Date, -Score)
  universe_n_eff <- as.integer(round(nrow(unique(FACTORS[, .(Date, Ticker)])) /
                                       max(uniqueN(FACTORS$Date), 1L)))
  cat(sprintf("[pead] universe=K200_KQ150 (PIT 시변): tickers %d->%d | cand/mo=%d | dates=%d (%s~%s)\n",
              .n0, uniqueN(FACTORS$Ticker), universe_n_eff, uniqueN(FACTORS$Date),
              as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date))))

  # ---- 3. PIT 검증 (정적분석 + fe 내장 self-assert는 source 시점 실행됨) ----
  pit <- detect_lookahead(fe)
  if (!isTRUE(pit$clean)) {
    for (v in (pit$violations %||% list()))
      cat(sprintf("  [PIT] line %s [%s]: %s\n", v$line %||% "?", v$check %||% "?", v$msg %||% ""))
    stop("[pead] PIT 위반 — 중단")
  }
  cat("[pead] PIT check (static): CLEAN\n")
  cat("[pead][PIT-WARN] fe가 외부 parquet(.cache/dart/dart_raw_quarterly.parquet)에 의존.\n")
  cat("  -> 원천 분기 재무 캐시(factor DB 아님, C15 load_month_factors 대상 아님).\n")
  cat("  -> fe 내장 self-assert: Usable_Date=접수일+1거래일, 시그널일별 max(Usable_Date)<=시그널일, ticker내 단일 회계기준.\n")
  cat("  -> SUE/UE/δ/σ = 전부 과거·현재 보고이익(접수완료분). 계절차분 shift(1..8)=과거분기. forward-label 아님 — Cycle50류 해당 없음.\n")

  # ---- 4. Backtest: SUE 상위 decile EW (buffer 없음) ----
  sim <- run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS[, .(Date, Ticker, Score, N)],
    n_holdings = 50L, weight_method = "equal", commission = commission, buffer_zone = NULL)

  # ---- 4b. top-25 EW 비교 (production 정합 진단) ----
  top25 <- tryCatch({
    sim25 <- run_monthly_simulation(
      RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS[, .(Date, Ticker, Score)],
      n_holdings = 25L, weight_method = "equal", commission = commission, buffer_zone = NULL)
    p25 <- summarise_perf(sim25$strategy_xts, "top25")
    list(cagr = .as_num(p25$CAGR), sharpe = .as_num(p25$Sharpe), mdd = .as_num(p25$MDD))
  }, error = function(e) { cat("[pead] top25 비교 생략:", conditionMessage(e), "\n"); NULL })

  # ---- 5. Charts ----
  tryCatch(generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name),
           error = function(e) cat("[pead] generate_charts 생략:", conditionMessage(e), "\n"))
  charts <- Filter(file.exists, file.path(OUT_DIR, c("equity_curve.png","annual_returns.png")))

  # ---- 6. 스코어링 (run_hurdle_gate 재사용) ----
  hg <- tryCatch(run_hurdle_gate(sim_result = sim, FACTORS = FACTORS[, .(Date, Ticker, Score)],
                                 strategy_name = strategy_name, output_dir = OUT_DIR),
                 error = function(e) { cat("[pead] hurdle 예외 — grade=F:", conditionMessage(e), "\n");
                                       list(grade = "F", score = NA_real_, verdict = list()) })
  assign("%||%", `%||%`, envir = globalenv())
  grade <- hg$grade %||% "uncertain"
  score <- .as_num(hg$score)
  m     <- hg$verdict$metrics %||% list()
  sdef  <- hg$verdict$statistical_defense %||% list()
  perf_bm <- tryCatch(summarise_perf(sim$bm_xts, "KOSPI200"), error = function(e) NULL)
  bm_cagr_pct <- if (!is.null(perf_bm)) .as_num(perf_bm$CAGR) else NA_real_
  excess_cagr <- round(.as_num(m$CAGR) - bm_cagr_pct, 2)

  # ---- 6a. 진단 IC + IS/OOS (advisory — 게이트 미사용) ----
  ic_sue <- tryCatch(.compute_ic(FACTORS, RAWDATA, "SUE"), error = function(e) NULL)
  isoos  <- tryCatch(.is_oos(sim, oos_split), error = function(e) NULL)
  fmt_diag <- function(x) if (is.null(x)) "산출불가"
    else sprintf("mean IC %.4f (t=%.2f, hit=%.0f%%, n=%d)", x$mean_ic, x$t_ic %||% NA, 100*(x$hit %||% NA), x$n)
  cat("\n[pead][진단 IC — advisory, 판정권위 아님]\n")
  cat(sprintf("  SUE Spearman IC : %s\n", fmt_diag(ic_sue)))
  if (!is.null(isoos))
    cat(sprintf("  IS/OOS(%s 분할): IS SR %.2f (n=%d) | OOS SR %.2f (n=%d) | retention %.2f [짧은 표본 — OOS 저정보]\n",
                oos_split, isoos$is_sr %||% NA, isoos$is_n, isoos$oos_sr %||% NA, isoos$oos_n, isoos$retention %||% NA))
  to_ann <- .as_num(m$Turnover_Ann)
  to_oneway_x <- if (is.finite(to_ann)) to_ann / 100 else NA_real_
  cost_warn <- is.finite(to_oneway_x) && to_oneway_x > 10
  cat(sprintf("[pead][비용] one-way 회전율 연 %.1fx — %s\n", to_oneway_x %||% NA,
              if (cost_warn) "★TO>10x: flat per-rebalance 비용모델이 거래비용 과소계상(B0 진단). 게이트 해석 주의"
              else "TO<=10x: flat 비용모델 정확 범위"))

  diag_path <- file.path(OUT_DIR, "pead_sue_diagnostics.json")
  tryCatch(write_json(list(
    strategy_id = strategy_id, paper = "Bernard-Thomas 1989 PEAD/SUE",
    data_floor = as.character(min(FACTORS$Date)),
    universe = "K200_KQ150", cand_per_month = universe_n_eff,
    sue_ic = ic_sue, is_oos = isoos, oos_split = oos_split,
    top25_compare = top25, turnover_oneway_x = to_oneway_x, cost_underreport_warn = cost_warn,
    note = "SUE decile primary. IC advisory(판정권위=portfolio 성과). 데이터 floor ~2018(σ창 충족) — 2005 mandate 미충족."),
    diag_path, auto_unbox = TRUE, pretty = TRUE, digits = 6),
    error = function(e) cat("[pead] 진단 JSON 저장 실패:", conditionMessage(e), "\n"))

  pass    <- grade %in% c("A","A_NOVEL","A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B","C") || (is_fail && isTRUE(pit$clean))
  cat(sprintf("\n[pead] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6c. FR 모듈 등재 (등급무관) ----
  tryCatch({
    source(file.path(.AS_INFRA, "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_, meta = list(strategy_idea = strategy_idea, score = score))
    assign("%||%", `%||%`, envir = globalenv())
  }, error = function(e) cat("[pead] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 6d. 팩터 회귀 (FF3/FF5/Carhart + Fama-MacBeth) ----
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({ run_analysis(sim, FACTORS[, .(Date, Ticker, Score)], RAWDATA, BM_DT,
                            output_dir = OUT_DIR, strategy_name = strategy_name)
               assign("%||%", `%||%`, envir = globalenv()) },
             error = function(e) cat("[pead] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  # ---- 7. Telegram (헬퍼 재사용) ----
  if (isTRUE(send_telegram)) {
    .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                             m, sdef, excess_cagr, charts, universe = "K200_KQ150",
                             universe_n = universe_n_eff, out_dir = OUT_DIR, dry_run = tg_dry_run)
    if (isTRUE(factor_analysis) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis"))
      tryCatch(tg_pass_analysis(strategy_name, OUT_DIR),
               error = function(e) cat("[pead][팩터분석TG] 실패:", conditionMessage(e), "\n"))
  }

  # ---- 8. L-code (PASS + 의미있는 실패만) ----
  l_code_path <- NULL
  if (pass || notable) {
    l_code_path <- .write_lcode(strategy_id, strategy_name, strategy_idea, grade,
                                m, excess_cagr, pass, is_fail, hg = hg)
    .run_axiom_pipeline()
  }

  # ---- 9. Grade A → 등록 + PG 권고 ----
  if (pass) {
    .register_strategy_best_effort(strategy_id, strategy_name, strategy_idea, grade, m)
    if (isTRUE(send_telegram))
      .recommend_pg_admission(strategy_id, strategy_name, grade, "PF_ALPHASEARCH", dry_run = tg_dry_run)
  }

  cat(sprintf("\n[pead] DONE. id=%s grade=%s score=%.0f excess=%+.2f out=%s\n",
              strategy_id, grade, score %||% 0, excess_cagr %||% 0, OUT_DIR))
  invisible(list(strategy_id = strategy_id, grade = grade, score = score, pass = pass,
                 notable = notable, excess_cagr = excess_cagr, out_dir = OUT_DIR,
                 charts = charts, l_code = l_code_path,
                 ic_sue = ic_sue, isoos = isoos, top25 = top25, diag_path = diag_path,
                 metrics = m, cost_warn = cost_warn))
}
