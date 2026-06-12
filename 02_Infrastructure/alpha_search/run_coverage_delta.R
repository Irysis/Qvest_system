#!/usr/bin/env Rscript
# =============================================================================
# run_coverage_delta.R — 애널리스트 커버리지 head-count 변화 알파(KR-native) 검증 러너
# =============================================================================
# alpha-search 모드. 가설 P1(Δcoverage_3m initiation burst) primary = 상위 decile EW
#   long-only 월간 + top-25 EW 비교 + P2(철수 회피)/P3(저커버리지 조건) 진단 IC + IS/OOS.
# 측정·리포팅 백엔드 재사용(run_alpha_search 내부 헬퍼) → 모드 일관성.
# QEPM 이행 없음(Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WT/cert 없음). WT-id 미사용.
# 골격 = run_disclosure_meta.R(직전 성공 경로) 충실 복제, 커버리지 가설로 교체.
# 롱숏 불허(도훈 06-11): 전면 long-only. L/S 미산출.
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

# ---- 진단: 1개월 forward 종목수익 vs 시그널 Spearman IC (IC 정의상 t+1 평가 — 미래참조 아님) ----
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

# ---- IS/OOS 분할 성과 (PerformanceAnalytics 표준함수만) ----
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

run_coverage_delta <- function(
    strategy_name = "Coverage Head-Count Change (KR-native)",
    strategy_idea = paste0(
      "애널리스트 커버리지 head-count 3개월 변화(initiation burst) 횡단면 랭크 상위 decile ",
      "EW long-only — 커버리지 개시 급증=정보환경 개선·기관수요 선행 long, 철수=음의 신호. ",
      "커버리지 수준 아닌 변화 그 자체가 신호."),
    signal_var    = "dcov_abs",     # P1 변형: dcov_abs(절대증분, 기본) / dcov_rel(증가율). IS 분포 보고 선택
    invert        = FALSE,          # ★ 역신호 프로브(abandonment long): TRUE면 Score=frank(-signal) — 철수 종목 상위 decile long
    start_date    = "2005-01-01",   # coverage floor 2001-06 — 2005 mandate 충족
    oos_split     = "2022-01-01",
    commission    = 0.0015,
    track         = NULL,           # 산출 메타 라벨(NULL이면 기본 COVD). 역프로브는 "COVD_abandonment_inverse"
    send_telegram = TRUE,
    tg_dry_run    = FALSE,
    factor_analysis = TRUE) {

  # ★ 함수-로컬 length-safe %||% shadow (run_hurdle_gate/loop_integrator가 global %||% clobber)
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

  fe <- file.path(.AS_INFRA, "alpha_search", "fe_coverage_delta.R")
  stopifnot(file.exists(fe))
  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  .id_tag     <- if (isTRUE(invert)) "COVDINV" else "COVD"
  strategy_id <- paste0("STR_AS_", .id_tag, "_", run_id)
  track       <- track %||% (if (isTRUE(invert)) "COVD_abandonment_inverse" else "COVD_coverage_delta")
  OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [AlphaSearch · KR-native] %s (%s) ===\n", strategy_name, strategy_id))
  cat(sprintf("    idea: %s\n    signal_var=%s\n", strategy_idea, signal_var))

  # ---- 1. Data ----
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
  RAWDATA[, TradingValue := Close * Vol]
  RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
  RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

  # ---- 2. Factor engine -> FACTORS(Date,Ticker,Score,N,dcov_abs,dcov_rel,cov_now,aband,neglect) ----
  source(fe, local = TRUE)
  stopifnot(exists("FACTORS"), is.data.table(FACTORS),
            all(c("Date","Ticker","Score","N","dcov_abs","dcov_rel") %in% names(FACTORS)))

  # ---- 2a. P1 변형 선택 (IS-only): 기본 dcov_abs. signal_var=dcov_rel 지정 시 Score swap ----
  #   ★ invert=TRUE(abandonment 역프로브): Score=frank(-signal) — 커버리지 철수(Δ 하위=감소 큰) 종목을
  #     상위 decile로 long. 원 검증 P2 진단(aband IC +0.0220, t=3.39, 가설과 역부호)의 portfolio 집행.
  #     aband 정의(dcov_abs<0)는 fe 원정의 그대로 보존 — 새 정의 발명 없음. invert는 랭크 방향만 뒤집음.
  if (identical(signal_var, "dcov_rel")) {
    FACTORS[, Score := frank(dcov_rel, ties.method = "average") / .N, by = Date]
    cat("[covd] P1 변형 = dcov_rel(증가율) 선택 — Score 재산출 (변경사유: IS 분포 보고 러너 지정)\n")
  } else {
    cat("[covd] P1 변형 = dcov_abs(절대증분, 기본)\n")
  }
  if (isTRUE(invert)) {
    .sigc <- if (identical(signal_var, "dcov_rel")) "dcov_rel" else "dcov_abs"
    FACTORS[, Score := frank(-get(.sigc), ties.method = "average") / .N, by = Date]
    cat(sprintf("[covd][INVERT] 역신호 프로브: Score=frank(-%s) — 철수(Δ 하위) 종목 상위 decile long\n", .sigc))
  }
  setorder(FACTORS, Date, -Score)

  if (!is.null(start_date)) FACTORS <- FACTORS[Date >= as.Date(start_date)]

  # ---- 2b. 유니버스는 fe가 이미 K200∪KQ150 그리드로 구성. decile N 재산출(filter 후 후보 기준) ----
  FACTORS[, N := NULL]
  .NDT <- FACTORS[, .(N = as.integer(pmax(1L, round(.N / 10)))), by = Date]
  FACTORS <- merge(FACTORS, .NDT, by = "Date")
  setorder(FACTORS, Date, -Score)
  universe_n_eff <- as.integer(round(nrow(unique(FACTORS[, .(Date, Ticker)])) /
                                       max(uniqueN(FACTORS$Date), 1L)))
  cat(sprintf("[covd] universe=K200_KQ150 (fe 그리드, NA->0): cand/mo=%d | dates=%d (%s~%s) | tickers=%d\n",
              universe_n_eff, uniqueN(FACTORS$Date),
              as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date)),
              uniqueN(FACTORS$Ticker)))

  # ---- 2c. ★ 잔존 폭 진단(역프로브 필수): top-decile N + 그 중 실제 철수(aband=1) 종목수 ----
  #   철수 종목은 저유동 쏠림 가능 — 유동성 필터(2e8, fe LiqPass) 통과 후 잔존. decile N<15면 명시.
  .topdec <- FACTORS[, head(.SD[order(-Score)], N[1L]), by = Date]
  decile_n_med   <- as.integer(median(FACTORS[, .(N = N[1L]), by = Date]$N))
  aband_in_dec   <- .topdec[, .(n_ab = sum(aband == 1L), n = .N), by = Date]
  aband_n_med    <- as.integer(median(aband_in_dec$n_ab))
  aband_frac_med <- round(median(aband_in_dec$n_ab / pmax(aband_in_dec$n, 1L)), 3)
  decile_thin    <- decile_n_med < 15L
  cat(sprintf("[covd][잔존폭] top-decile N med=%d | 그 중 실제철수(aband=1) med=%d (비율 med=%.1f%%) | %s\n",
              decile_n_med, aband_n_med, 100 * aband_frac_med,
              if (decile_thin) "★decile N<15 과소 — 분산 부족·일물쏠림 위험 명시"
              else "decile N>=15 충분"))

  # ---- 3. PIT 검증 (정적분석 + fe 내장 self-assert는 source 시점에 이미 실행됨) ----
  pit <- detect_lookahead(fe)
  if (!isTRUE(pit$clean)) {
    for (v in (pit$violations %||% list()))
      cat(sprintf("  [PIT] line %s [%s]: %s\n", v$line %||% "?", v$check %||% "?", v$msg %||% ""))
    stop("[covd] PIT 위반 — 중단")
  }
  cat("[covd] PIT check (static): CLEAN\n")
  cat("[covd][PIT-WARN] fe가 외부 parquet(.cache/consensus/coverage.parquet)에 의존.\n")
  cat("  -> 원천 컨센서스 캐시(factor DB 아님, C15 load_month_factors 대상 아님).\n")
  cat("  -> fe 내장 self-assert: Usable_Date=관측일+1거래일, 시그널일별 max(Usable_Date)<=시그널일 통과.\n")
  cat("  -> Δcoverage_3m = cov_now - cov_3m_ago, 둘 다 과거/현재 관측(forward-label 아님). Cycle50류 해당없음.\n")

  # ---- 4. Backtest: P1 primary = 월간 top-decile EW (buffer 없음) ----
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
  }, error = function(e) { cat("[covd] top25 비교 생략:", conditionMessage(e), "\n"); NULL })

  # ---- 5. Charts ----
  tryCatch(generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name),
           error = function(e) cat("[covd] generate_charts 생략:", conditionMessage(e), "\n"))
  charts <- Filter(file.exists, file.path(OUT_DIR, c("equity_curve.png","annual_returns.png")))

  # ---- 6. 스코어링 (run_hurdle_gate 재사용) ----
  hg <- tryCatch(run_hurdle_gate(sim_result = sim, FACTORS = FACTORS[, .(Date, Ticker, Score)],
                                 strategy_name = strategy_name, output_dir = OUT_DIR),
                 error = function(e) { cat("[covd] hurdle 예외 — grade=F:", conditionMessage(e), "\n");
                                       list(grade = "F", score = NA_real_, verdict = list()) })
  assign("%||%", `%||%`, envir = globalenv())
  grade <- hg$grade %||% "uncertain"
  score <- .as_num(hg$score)
  m     <- hg$verdict$metrics %||% list()
  sdef  <- hg$verdict$statistical_defense %||% list()
  perf_bm <- tryCatch(summarise_perf(sim$bm_xts, "KOSPI200"), error = function(e) NULL)
  bm_cagr_pct <- if (!is.null(perf_bm)) .as_num(perf_bm$CAGR) else NA_real_
  excess_cagr <- round(.as_num(m$CAGR) - bm_cagr_pct, 2)

  # ---- 6a. 진단 IC (P1/P2/P3) + IS/OOS (advisory — 게이트 미사용) ----
  #   P1 = dcov_abs(또는 선택 신호). P2 = -aband 회피(철수=음의 신호이면 aband와 수익 음상관 기대).
  #   P3 = neglect 구간 내 dcov_abs (조건부). aband는 binary라 IC = 점이연 상관 진단.
  #   ★ invert: P1 IC는 실제 랭킹신호(-signal)로 측정 (IC(-x) = -IC(x); 부호 정합 확인용).
  if (isTRUE(invert)) {
    .sigc <- if (identical(signal_var, "dcov_rel")) "dcov_rel" else "dcov_abs"
    FACTORS[, aband_score := -get(.sigc)]
    p1_col <- "aband_score"
  } else p1_col <- signal_var
  ic_p1 <- tryCatch(.compute_ic(FACTORS, RAWDATA, p1_col),          error = function(e) NULL)
  ic_p2 <- tryCatch(.compute_ic(FACTORS, RAWDATA, "aband"),         error = function(e) NULL)
  ic_p3 <- tryCatch(.compute_ic(FACTORS[neglect == 1L], RAWDATA, signal_var), error = function(e) NULL)
  isoos <- tryCatch(.is_oos(sim, oos_split), error = function(e) NULL)
  fmt_diag <- function(x) if (is.null(x)) "산출불가"
    else sprintf("mean IC %.4f (t=%.2f, hit=%.0f%%, n=%d)", x$mean_ic, x$t_ic %||% NA, 100*(x$hit %||% NA), x$n)
  cat("\n[covd][진단 IC — advisory, 판정권위 아님]\n")
  cat(sprintf("  P1 %-9s: %s\n", p1_col, fmt_diag(ic_p1)))
  cat(sprintf("  P2 철수(aband): %s [음의 IC = 철수가 음의 신호 = 가설 정합]\n", fmt_diag(ic_p2)))
  cat(sprintf("  P3 저커버리지내 %-6s: %s\n", signal_var, fmt_diag(ic_p3)))
  if (!is.null(isoos))
    cat(sprintf("  IS/OOS(%s 분할): IS SR %.2f (n=%d) | OOS SR %.2f (n=%d) | retention %.2f\n",
                oos_split, isoos$is_sr %||% NA, isoos$is_n, isoos$oos_sr %||% NA, isoos$oos_n, isoos$retention %||% NA))
  to_ann <- .as_num(m$Turnover_Ann)
  to_oneway_x <- if (is.finite(to_ann)) to_ann / 100 else NA_real_
  cost_warn <- is.finite(to_oneway_x) && to_oneway_x > 10
  cat(sprintf("[covd][비용] one-way 회전율 연 %.1fx — %s\n", to_oneway_x %||% NA,
              if (cost_warn) "★TO>10x: flat 비용모델 거래비용 과소계상(B0 진단). 게이트 해석 주의"
              else "TO<=10x: flat 비용모델 정확 범위"))

  diag_path <- file.path(OUT_DIR, "coverage_delta_diagnostics.json")
  tryCatch(write_json(list(
    strategy_id = strategy_id, track = track, invert = invert,
    data_floor = as.character(min(FACTORS$Date)),
    signal_var = signal_var, p1_signal = p1_col,
    universe = "K200_KQ150", cand_per_month = universe_n_eff,
    decile_n_med = decile_n_med, aband_in_decile_med = aband_n_med,
    aband_frac_in_decile_med = aband_frac_med, decile_thin = decile_thin,
    P1_ic = ic_p1, P2_aband_ic = ic_p2, P3_neglect_ic = ic_p3,
    is_oos = isoos, oos_split = oos_split,
    top25_compare = top25, turnover_oneway_x = to_oneway_x, cost_underreport_warn = cost_warn,
    note = paste0(if (isTRUE(invert)) "INVERSE(abandonment long): Score=frank(-signal), 철수 decile long. "
                  else "P1 primary(Δcoverage_3m initiation). ",
                  "원검증 P2 aband IC +0.0220(t=3.39) 집행. P2/P3 IC=진단(게이트 미사용). ",
                  "NA->0(미커버=0) 가정. aband 정의 fe 원정의 보존. IC advisory.")),
    diag_path, auto_unbox = TRUE, pretty = TRUE, digits = 6),
    error = function(e) cat("[covd] 진단 JSON 저장 실패:", conditionMessage(e), "\n"))

  pass    <- grade %in% c("A","A_NOVEL","A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B","C") || (is_fail && isTRUE(pit$clean))
  cat(sprintf("\n[covd] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6c. FR 모듈 등재 (등급무관) ----
  tryCatch({
    source(file.path(.AS_INFRA, "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_, meta = list(strategy_idea = strategy_idea, score = score))
    assign("%||%", `%||%`, envir = globalenv())
  }, error = function(e) cat("[covd] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 6d. 팩터 회귀 (FF3/FF5/Carhart + Fama-MacBeth) ----
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({ run_analysis(sim, FACTORS[, .(Date, Ticker, Score)], RAWDATA, BM_DT,
                            output_dir = OUT_DIR, strategy_name = strategy_name)
               assign("%||%", `%||%`, envir = globalenv()) },
             error = function(e) cat("[covd] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  # ---- 7. Telegram (헬퍼 재사용) ----
  if (isTRUE(send_telegram)) {
    .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                             m, sdef, excess_cagr, charts, universe = "K200_KQ150",
                             universe_n = universe_n_eff, out_dir = OUT_DIR, dry_run = tg_dry_run)
    if (isTRUE(factor_analysis) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis"))
      tryCatch(tg_pass_analysis(strategy_name, OUT_DIR),
               error = function(e) cat("[covd][팩터분석TG] 실패:", conditionMessage(e), "\n"))
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

  cat(sprintf("\n[covd] DONE. id=%s grade=%s score=%.0f excess=%+.2f out=%s\n",
              strategy_id, grade, score %||% 0, excess_cagr %||% 0, OUT_DIR))
  invisible(list(strategy_id = strategy_id, grade = grade, score = score, pass = pass,
                 notable = notable, excess_cagr = excess_cagr, out_dir = OUT_DIR,
                 charts = charts, l_code = l_code_path, signal_var = signal_var,
                 ic_p1 = ic_p1, ic_p2 = ic_p2, ic_p3 = ic_p3, isoos = isoos,
                 top25 = top25, diag_path = diag_path,
                 metrics = m, cost_warn = cost_warn))
}

cat("[run_coverage_delta] loaded. usage: run_coverage_delta(send_telegram=TRUE, tg_dry_run=TRUE)\n")
