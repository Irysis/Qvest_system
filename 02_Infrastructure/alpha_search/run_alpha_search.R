#!/usr/bin/env Rscript
# =============================================================================
# run_alpha_search.R — "알파 서칭" 엔진 (Qvest 초기 모델 스타일)
# =============================================================================
# 논문/가설을 빠르게 백테스트 검증하고 전략별로:
#   (1) 전기간 Equity Curve(vs BM) + (2) 연간 수익률 막대그래프(vs BM) 2차트
#   (3) 전략명+아이디어 요약 + (4) 성과요약(스코어링 지표) 텔레그램 발송
#   → PASS/의미있는 실패만 L-code(모드별) 적립 → harvester/cluster 자가발전
#   → Grade A는 PG 편입 "권고"만 (book_state.json 편입은 도훈 수동 승인)
#
# QEPM 이행 없음: Risk/Optimizer/Forge/Judge/Governor 미호출, Codex Round 없음,
#   WorkTask status 전이 없음, certificate 의존 없음. WT-id 사용 금지.
#
# 스코어링: 기존 run_hurdle_gate() 재사용(grade/score/지표). 별도 임계값 신설 없음.
# Usage:
#   source("02_Infrastructure/alpha_search/run_alpha_search.R")
#   run_alpha_search("STR명", "전략 아이디어", "<factor_engine.R 경로>")
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(jsonlite)
}))

# ---- Infra path resolution (Korean-path safe, stale drive fallback free) ----
.AS_FIND_ROOT <- function() {
  script_file <- tryCatch(sys.frame(1)$ofile, error = function(e) "")
  script_dir <- if (is.character(script_file) && nzchar(script_file)) dirname(script_file) else "."
  candidates <- unique(c(
    Sys.getenv("CLAUDE_PROJECT_DIR", ""),
    Sys.getenv("QM_ROOT", ""),
    getwd(),
    normalizePath(file.path(script_dir, "../.."), winslash = "/", mustWork = FALSE)
  ))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[AlphaSearch] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
.AS_PROJECT_ROOT <- .AS_FIND_ROOT()
.AS_INFRA <- local({
  cand <- Sys.getenv("QVEST_INFRA_DIR", "")
  if (nzchar(cand) && file.exists(file.path(cand, "config.R"))) return(cand)
  file.path(.AS_PROJECT_ROOT, "02_Infrastructure")
})
source(file.path(.AS_INFRA, "config.R"))
if (!exists("PROJECT_ROOT", inherits = TRUE)) PROJECT_ROOT <- .AS_PROJECT_ROOT
if (!nzchar(Sys.getenv("CLAUDE_PROJECT_DIR", ""))) Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT)
if (!nzchar(Sys.getenv("QM_ROOT", ""))) Sys.setenv(QM_ROOT = PROJECT_ROOT)
source(file.path(.AS_INFRA, "backtest_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
source(file.path(.AS_INFRA, "hurdle_gate.R"))
source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
suppressWarnings(tryCatch(source(file.path(.AS_INFRA, "strategy_registry.R")), error = function(e) NULL))
suppressWarnings(tryCatch(source(file.path(.AS_INFRA, "portfolio", "portfolio_governor.R")), error = function(e) NULL))
suppressWarnings(tryCatch(source(file.path(.AS_INFRA, "strategy_analyzer.R")), error = function(e) NULL))  # run_analysis: FF3/FF5/Carhart 알파 + Fama-MacBeth

# 견고한 %||% / .as_num 는 모든 source 이후 최종 선언 — 외부 파일의 취약한 %||%
# (`!is.null(a) && !is.na(a)`: 빈/길이>1 벡터에서 크래시)에 덮이지 않도록 마지막에 정의.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }
.rel_project_path <- function(path) {
  p <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- normalizePath(PROJECT_ROOT, winslash = "/", mustWork = FALSE)
  pref <- paste0(root, "/")
  if (startsWith(p, pref)) substring(p, nchar(pref) + 1L) else p
}

# =============================================================================
run_alpha_search <- function(strategy_name,
                             strategy_idea,
                             factor_engine_path,
                             n_holdings    = 20L,
                             weight_method = "ivol",
                             commission    = 0.0015,
                             start_date    = "2005-01-01",  # 표준 백테 시작(도훈 mandate 2026-06-05): KR value/재무 한계(BM 2002-08~)+FF3 36m → 2005 공통 고정. NULL=전기간
                             universe      = "K200_KQ150",  # 표준 고정(도훈 2026-06-05): KOSPI200/KOSDAQ150 멤버십(실투). "ALL"=전종목 / "KR_TOP500"=시총top500 / "K200_KQ150"=인덱스멤버십(PIT 시변)
                             out_root      = NULL,
                             portfolio_id  = "PF_ALPHASEARCH",
                             send_telegram = TRUE,
                             tg_dry_run    = FALSE,
                             factor_analysis = TRUE,   # FF3/FF5/Carhart 알파 + Fama-MacBeth 회귀
                             vol_target = NULL,
                             vol_lookback = 60L,
                             dd_brake = NULL,
                             buffer_zone = NULL,
                             use_default_buffer = TRUE,
                             cov_method = "sample") {
  # 로컬 안전 %||% — 외부 source가 전역을 취약버전으로 덮어도 영향 없게 함수 스코프에 고정
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

  stopifnot(file.exists(factor_engine_path))
  # run_id: 초단위 타임스탬프 + PID로 고유화. 병렬 실행 시 같은 초 충돌 방지
  #   (충돌 시 OUT_DIR 덮어쓰기 + tg lock scope 충돌로 메인 brief BLOCKED — 2026-06-05 도훈 발견).
  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_id <- paste0("STR_AS_", run_id)          # QEPM(STR_XXXX)과 구분되는 접두사
  if (is.null(out_root)) out_root <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search")
  OUT_DIR <- file.path(out_root, run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [AlphaSearch] %s (%s) ===\n", strategy_name, strategy_id))
  cat(sprintf("    idea: %s\n", strategy_idea))

  # ---- 1. Data ----
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  # Date 타입 정합: BM_DT$Date가 POSIXct로 오는 경우 Date로 정규화
  #   (run_monthly_simulation의 BM_DT[Date %in% DAILY_NAV_DT$Date] 매칭이 타입 불일치로 깨지는 것 방지)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
  LIQ <- 2e8
  RAWDATA[, TradingValue := Close * Vol]
  RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
  RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ]

  # ---- 2. Factor engine -> FACTORS (Date, Ticker, Score) ----
  # Run the factor engine in a child environment. Some memory-hardened engines
  # intentionally rm(RAWDATA) from their local env after deriving FACTORS; the
  # simulation still needs the canonical RAWDATA object below.
  fe_env <- new.env(parent = environment())
  fe_env$RAWDATA <- RAWDATA
  fe_env$BM_DT <- BM_DT
  source(factor_engine_path, local = fe_env)
  if (!exists("FACTORS", envir = fe_env, inherits = FALSE) || !is.data.table(fe_env$FACTORS))
    stop("[AlphaSearch] factor_engine이 FACTORS data.table을 생성하지 않았습니다.")
  FACTORS <- fe_env$FACTORS
  rm(fe_env)
  gc(verbose = FALSE)
  stopifnot(all(c("Date", "Ticker", "Score") %in% names(FACTORS)))
  if (!is.null(start_date)) FACTORS <- FACTORS[Date >= as.Date(start_date)]  # 시그널 시작일 제한(RAWDATA는 전체 유지)
  # universe 멤버십 필터 (PIT-safe: sig_date 시점 시총 ranking. KR_TOP500 = 유동성 2e8 통과 종목 중 시총 top500 = KR_TOP500_FREEFLOAT 등가)
  universe_n_eff <- NA_integer_
  if (!is.null(universe) && universe == "KR_TOP500") {
    if (!"Size" %in% names(RAWDATA)) stop("[AlphaSearch] universe=KR_TOP500 requires RAWDATA$Size (시가총액)")
    .me_uni <- unique(FACTORS$Date)
    .urank  <- RAWDATA[Date %in% .me_uni & LiqPass == TRUE & is.finite(Size),
                       .(Ticker, .UR = frank(-Size, ties.method = "first")), by = Date]
    .keep   <- .urank[.UR <= 500L, .(Date, Ticker)]
    .n0 <- uniqueN(FACTORS$Ticker)
    FACTORS <- merge(FACTORS, .keep, by = c("Date", "Ticker"))
    universe_n_eff <- as.integer(round(nrow(.keep) / max(uniqueN(.keep$Date), 1L)))
    cat(sprintf("[AlphaSearch] universe=KR_TOP500 (시총 top500, PIT): tickers %d->%d | avg/month %d | rows->%d\n",
                .n0, uniqueN(FACTORS$Ticker), universe_n_eff, nrow(FACTORS)))
  } else if (!is.null(universe) && universe %in% c("K200_KQ150", "INDEX")) {
    # KOSPI200 ∪ KOSDAQ150 인덱스 멤버십 (PIT 시변: sig_date 시점 멤버만). 실투 표준 유니버스.
    if (!all(c("K200", "KQ150") %in% names(RAWDATA)))
      stop("[AlphaSearch] universe=K200_KQ150 requires RAWDATA K200/KQ150 membership columns")
    .me_uni <- unique(FACTORS$Date)
    .mem <- unique(RAWDATA[Date %in% .me_uni & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
    .n0  <- uniqueN(FACTORS$Ticker)
    FACTORS <- merge(FACTORS, .mem, by = c("Date", "Ticker"))
    universe_n_eff <- as.integer(round(nrow(.mem) / max(uniqueN(.mem$Date), 1L)))
    cat(sprintf("[AlphaSearch] universe=K200_KQ150 (KOSPI200/KOSDAQ150 membership, PIT time-varying): tickers %d->%d | avg/month %d\n",
                .n0, uniqueN(FACTORS$Ticker), universe_n_eff))
  } else {
    universe_n_eff <- as.integer(round(uniqueN(paste(FACTORS$Date, FACTORS$Ticker)) / max(uniqueN(FACTORS$Date), 1L)))
  }
  cat(sprintf("[AlphaSearch] FACTORS: %d rows | %d signal dates | %d tickers\n",
              nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

  # ---- 3. PIT 준수 검증 (필수) ----
  pit <- detect_lookahead(factor_engine_path)
  pit_clean <- isTRUE(pit$clean)
  if (!pit_clean) {
    for (v in (pit$violations %||% list()))
      cat(sprintf("  [PIT] line %s [%s]: %s\n", v$line %||% "?", v$check %||% "?", v$msg %||% ""))
    stop("[AlphaSearch] PIT 위반 감지 — 백테스트 중단. factor_engine을 t-1 기준으로 수정하세요.")
  }
  cat("[AlphaSearch] PIT check: CLEAN\n")

  # ---- 3b. 외부 데이터 의존 팩터 경고 (detect_lookahead 정적분석 사각) ----
  #   fe_ml처럼 factor_engine이 외부 parquet/cache(예 ML 예측 pred)를 읽어 Score를 만들면,
  #   detect_lookahead는 factor_engine.R 텍스트만 보므로 생성 파이프라인(.py)의 forward-label
  #   lookahead를 검사하지 못한다(13줄 fe_ml.R은 무조건 CLEAN). 명시 경고로 PIT 책임 고지.
  fe_src_txt <- tryCatch(readLines(factor_engine_path, warn = FALSE), error = function(e) character(0))
  if (any(grepl("read_parquet|read_feather|arrow::|read_csv|\\.cache|fromJSON|_pred|pred\\b",
                fe_src_txt, ignore.case = TRUE))) {
    cat("[AlphaSearch][PIT-WARN] factor_engine이 외부 데이터(parquet/cache/pred)에 의존합니다.\n")
    cat("  -> detect_lookahead 정적분석은 생성 파이프라인(.py 등)의 forward-label PIT를 검사하지 못합니다.\n")
    cat("  -> 생성 코드가 forward-label sanity(bear_date_audit / validate_label_direction 또는 동등 self-assert)를\n")
    cat("     통과했는지 별도 보증하세요 (python-policy.md 언어무관 의무, Cycle 50 교훈).\n")
  }

  # ---- 4. Backtest (기존 풀백테스트 재사용) ----
  sim_buffer_zone <- buffer_zone
  if (is.null(sim_buffer_zone) && isTRUE(use_default_buffer)) {
    sim_buffer_zone <- list(keep_n = as.integer(2L * n_holdings),
                            entry_n = as.integer(n_holdings))
  }
  risk_controls <- list(
    vol_target = vol_target,
    vol_lookback = as.integer(vol_lookback %||% 60L),
    dd_brake = dd_brake,
    buffer_zone = sim_buffer_zone,
    use_default_buffer = isTRUE(use_default_buffer),
    cov_method = cov_method %||% "sample"
  )
  sim <- run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
    n_holdings = n_holdings, weight_method = weight_method, commission = commission,
    vol_target = vol_target,
    vol_lookback = as.integer(vol_lookback %||% 60L),
    dd_brake = dd_brake,
    buffer_zone = sim_buffer_zone,
    cov_method = cov_method %||% "sample"
  )
  bt_contract <- .standardize_alpha_search_bt_result(
    sim = sim,
    strategy_id = strategy_id,
    strategy_name = strategy_name,
    strategy_idea = strategy_idea,
    factor_engine_path = factor_engine_path,
    out_dir = OUT_DIR,
    universe = universe,
    weight_method = weight_method,
    commission = commission,
    risk_controls = risk_controls
  )

  # ---- 4b. 후보 보존(register_module) — 계약 미충족분은 quarantine ----
  #   v8.1 hardening: PIT-clean 백테는 연구 후보로 보존하되, FR canonical pool은
  #   authoritative 재측정(contract_pass+backtested+frozen+hash) 성공분만 허용한다.
  #   따라서 이 early call은 통상 module_quarantine에 저장된다.
  if (isTRUE(pit_clean)) tryCatch({
    source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = NA_character_, origin_mode = "alpha_search",
                    role = NA_character_,
                    meta = list(
                      strategy_idea = strategy_idea,
                      bt_result_path = .rel_project_path(bt_contract$bt_result_path %||% file.path(OUT_DIR, "bt_result.rds")),
                      bt_contract_status = bt_contract$status %||% "UNKNOWN"
                    ))
    assign("%||%", `%||%`, envir = globalenv())   # register_module source 후 전역 %||% 복원
  }, error = function(e) cat("[AlphaSearch] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 5. Charts: equity_curve.png + annual_returns.png (vs BM) ----
  #   차트 생성이 실패(예 그래픽 디바이스 이슈)해도 register/측정/등재는 이미 완료 — 전체 run 중단 방지.
  tryCatch(
    generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name),
    error = function(e) cat("[AlphaSearch] generate_charts 생략:", conditionMessage(e), "\n"))
  equity_png <- file.path(OUT_DIR, "equity_curve.png")
  annual_png <- file.path(OUT_DIR, "annual_returns.png")
  charts <- Filter(file.exists, c(equity_png, annual_png))

  # ---- 6. 점수·등급 = 기존 스코어링 체계(run_hurdle_gate) 재사용 ----
  #   허들 게이트는 PG 편입 *권고*에만 영향 — 측정·등재·직교성 분석은 등급무관 진행(v8.1 헌법).
  #   허들 예외 시에도 grade="F"로 안전 강등하고 진행(register/factor_analysis 보존).
  hg     <- tryCatch(
    run_hurdle_gate(sim_result = sim, FACTORS = FACTORS,
                    strategy_name = strategy_name,
                    catalog_strategy_id = strategy_id,
                    output_dir = OUT_DIR),
    error = function(e) { cat("[AlphaSearch] run_hurdle_gate 예외 — grade=F 강등 후 진행:",
                              conditionMessage(e), "\n"); list(grade = "F", score = NA_real_, verdict = list()) })
  # run_hurdle_gate가 내부 source(weight_method_registry 등)로 전역 %||%를 취약버전
  # (`!is.null(a) && !is.na(a)`: 벡터에서 크래시)으로 덮어쓴다. tg_agent_brief 등 전역
  # %||%를 쓰는 함수가 오작동하지 않도록 견고버전(로컬)을 전역에 복원.
  assign("%||%", `%||%`, envir = globalenv())
  grade  <- hg$grade %||% "uncertain"
  score  <- .as_num(hg$score)
  m      <- hg$verdict$metrics %||% list()
  sdef   <- hg$verdict$statistical_defense %||% list()
  perf_bm <- tryCatch(summarise_perf(sim$bm_xts, "KOSPI200"), error = function(e) NULL)
  bm_cagr_pct <- if (!is.null(perf_bm)) .as_num(perf_bm$CAGR) else NA_real_  # summarise_perf CAGR은 이미 percent(round(ann*100,2))
  excess_cagr <- round(.as_num(m$CAGR) - bm_cagr_pct, 2)

  pass    <- grade %in% c("A", "A_NOVEL", "A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B", "C") || (is_fail && pit_clean)   # 명확한 실패 패턴(clean PIT)
  cat(sprintf("[AlphaSearch] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6a-2. FMT-01~08 실패모드 자동판정 (proxy 진단 라벨 — 게이트 아님) ----
  #   strategy_postmortem.md FMT taxonomy를 hurdle metrics rule로 매핑(.judge_fmt 주석 참조).
  #   판정 실패 시에도 run은 계속 (진단 누락은 콘솔 WARN으로 정직 고지).
  fmt_hits <- tryCatch(.judge_fmt(m, hg, sim, strategy_name, strategy_idea, excess_cagr, grade),
                       error = function(e) { cat("[AlphaSearch][FMT] WARN: 자동판정 실패 —",
                                                 conditionMessage(e), "\n"); list() })
  if (length(fmt_hits)) {
    cat(sprintf("[AlphaSearch] FMT 자동판정: %s\n",
                paste(vapply(fmt_hits, function(x) x$code, ""), collapse = ", ")))
  } else {
    cat("[AlphaSearch] FMT 자동판정: 해당 없음 (rule 기준 미충족 — FMT-06은 수동 진단 전용)\n")
  }
  f_grade_reasons <- .alpha_failure_reasons(grade, hg, fmt_hits, m, excess_cagr, auth = NULL)

  # ---- 6c. 후보 quarantine grade 갱신 ----
  #   허들 등급 산출 후에도 계약 실측 전이면 FR pool이 아니라 quarantine만 갱신된다.
  if (isTRUE(pit_clean)) tryCatch({
    if (!exists("register_module", mode = "function"))
      source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_,
                    meta = list(strategy_idea = strategy_idea, score = score,
                                f_grade_reasons = f_grade_reasons,
                                fmt_codes = vapply(fmt_hits, function(x) x$code, ""),
                                bt_result_path = .rel_project_path(bt_contract$bt_result_path %||% file.path(OUT_DIR, "bt_result.rds")),
                                bt_contract_status = bt_contract$status %||% "UNKNOWN"))
    assign("%||%", `%||%`, envir = globalenv())   # register_module source 후 전역 %||% 복원
  }, error = function(e) cat("[AlphaSearch] register_module(grade 갱신) 생략:", conditionMessage(e), "\n"))

  # ---- 6b. 팩터 회귀 분석 (FF3/FF5/Carhart 알파 + Fama-MacBeth) — 등급무관 진행(직교성 핵심 지표) ----
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({
      run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir = OUT_DIR, strategy_name = strategy_name)
      assign("%||%", `%||%`, envir = globalenv())   # run_analysis 내부 source 오염 복원
    }, error = function(e) cat("[AlphaSearch] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  # ---- 6b-2. analysis_report.md FMT 체크리스트 자동 체크 ([x] + 사유) ----
  #   run_analysis가 생성한 보고서의 "Failure Mode Diagnosis" 빈 체크박스를 6a-2 판정으로 채움.
  .patch_fmt_checklist(OUT_DIR, fmt_hits)

  # ---- 6d. ★ 권위측정 사다리: hurdle B 이상 또는 screening_pass → 계약 실측 재측정 (자동) ----
  #   v8.1 트랙C(measurement-graduation §1~§3): proxy(run_hurdle_gate) 등급이 B 이상이거나,
  #   MDD/turnover 같은 구조 사유로 C/F가 됐어도 screen_pass면 authoritative 재측정.
  #   → OUT_DIR/bt_result.rds + authoritative_remeasure.json (essence grade / PORT_t NW lag-3 / metric_type=backtested).
  #   PIT 위반/신호력 부재 C/F는 기존 proxy 흐름 유지(비용 절약). 실패 시 정직 WARN — 침묵 금지.
  auth <- NULL
  screening <- hg$verdict$screening %||% list()
  screen_remeasure <- isTRUE(screening$screen_pass) &&
    grepl("OVERLAY_CANDIDATE|FR_RCMA|DPL_FEATURE", screening$screen_route %||% "")
  if (grade %in% c("A", "A_NOVEL", "A_DEF", "B", "B_DEF") || screen_remeasure) {
    if (screen_remeasure && !(grade %in% c("A", "A_NOVEL", "A_DEF", "B", "B_DEF"))) {
      cat(sprintf("[AlphaSearch] 권위측정 사다리: grade=%s but screening_pass route=%s — 실측 재측정 진행\n",
                  grade, screening$screen_route %||% ""))
    }
    auth <- .authoritative_remeasure(sim, strategy_id, strategy_name, strategy_idea,
                                     factor_engine_path, OUT_DIR, grade,
                                     universe = universe, weight_method = weight_method,
                                     commission = commission,
                                     risk_controls = risk_controls,
                                     bt_contract = bt_contract)
    assign("%||%", `%||%`, envir = globalenv())   # contract source 후 전역 %||% 복원
  } else {
    cat(sprintf("[AlphaSearch] 권위측정 사다리: grade=%s, screen_pass=%s — proxy 유지, 실측 재측정 생략\n",
                grade, isTRUE(screening$screen_pass)))
  }
  f_grade_reasons <- .alpha_failure_reasons(grade, hg, fmt_hits, m, excess_cagr, auth = auth)
  strategy_manifest_path <- .write_alpha_search_strategy_manifest(
    out_dir = OUT_DIR,
    strategy_id = strategy_id,
    strategy_name = strategy_name,
    strategy_idea = strategy_idea,
    factor_engine_path = factor_engine_path,
    grade = grade,
    score = score,
    hg = hg,
    fmt = fmt_hits,
    f_grade_reasons = f_grade_reasons,
    auth = auth,
    metrics = m,
    excess_cagr = excess_cagr,
    universe = universe,
    universe_n = universe_n_eff,
    n_holdings = n_holdings,
    weight_method = weight_method,
    commission = commission,
    risk_controls = risk_controls,
    bt_contract = bt_contract
  )

  # ---- 6e. FR-eligible 승격: 권위측정 OK일 때만 canonical module_catalog로 등록 ----
  if (!is.null(auth) && identical(auth$status, "OK")) tryCatch({
    if (!exists("register_module", mode = "function"))
      source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "register_module.R"))
    register_module(
      sim, strategy_id,
      grade = auth$essence_grade %||% grade,
      origin_mode = "alpha_search",
      role = NA_character_,
      meta = list(strategy_idea = strategy_idea, score = score,
                  selection_type = "chain",
                  proxy_grade = grade,
                  f_grade_reasons = f_grade_reasons,
                  fmt_codes = vapply(fmt_hits, function(x) x$code, ""),
                  strategy_manifest_path = .rel_project_path(strategy_manifest_path),
                  authoritative_essence = auth$essence),
      metric_type = "backtested",
      contract_pass = TRUE,
      frozen = TRUE,
      source_contract_id = auth$run_id,
      build_version = "run_alpha_search_v8.1_ladder",
      cost_model_version = "v2.4_delta_15bps",
      bt_result_path = .rel_project_path(auth$bt_result_path %||% file.path(OUT_DIR, "bt_result.rds"))
    )
    assign("%||%", `%||%`, envir = globalenv())
  }, error = function(e) cat("[AlphaSearch] FR-eligible register_module 생략:", conditionMessage(e), "\n"))

  # ---- 7. Telegram: 2차트 + 전략아이디어 + 성과요약(스코어링 지표) ----
  if (isTRUE(send_telegram)) {
    .with_alpha_search_tg_lock(strategy_id, {
      send_set <- function() {
        main_tg <- .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                                            m, sdef, excess_cagr, charts, universe = universe,
                                            universe_n = universe_n_eff, out_dir = OUT_DIR,
                                            hg = hg, fmt = fmt_hits, auth = auth,
                                            f_reasons = f_grade_reasons, dry_run = tg_dry_run)
        # 팩터 분석 메시지 ([팩터 분석] 기존 양식: FF3/FF5/Carhart 알파 + Fama-MacBeth + IC)
        if (isTRUE(factor_analysis) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis")) {
          if (isTRUE(main_tg$ok)) {
            tryCatch(tg_pass_analysis(strategy_name, OUT_DIR),
                     error = function(e) cat("[AlphaSearch][팩터분석TG] 실패:", conditionMessage(e), "\n"))
          } else {
            cat("[AlphaSearch][팩터분석TG] 메인 브리프 실패로 발송 생략\n")
          }
        }
        invisible(main_tg)
      }
      if (!isTRUE(tg_dry_run) && exists("tg_with_serial_lock", mode = "function")) {
        tg_with_serial_lock(
          scope = paste0("alpha_search_set_", strategy_id),
          owner = sprintf("AlphaSearch set · %s", strategy_id),
          send_set()
        )
      } else {
        send_set()
      }
    })
  }

  # ---- 8. L-code 적립 (PASS + 의미있는 실패만, 모드별 디렉터리) ----
  l_code_path <- NULL
  if (pass || notable) {
    l_code_path <- .write_lcode(strategy_id, strategy_name, strategy_idea, grade,
                                m, excess_cagr, pass, is_fail,
                                hg = hg, fmt = fmt_hits, auth = auth)
    .run_axiom_pipeline()   # harvester + cluster (자가발전)
  }

  # ---- 9. Grade A → STR 등록 + PG 편입 "권고"(book_state는 수동) ----
  if (pass) {
    .register_strategy_best_effort(strategy_id, strategy_name, strategy_idea, grade, m)
    if (isTRUE(send_telegram))
      .with_alpha_search_tg_lock(strategy_id, {
        .recommend_pg_admission(strategy_id, strategy_name, grade, portfolio_id, dry_run = tg_dry_run)
      })
  }

  invisible(list(strategy_id = strategy_id, grade = grade, score = score,
                 pass = pass, notable = notable, excess_cagr = excess_cagr,
                 out_dir = OUT_DIR, charts = charts, l_code = l_code_path,
                 fmt_codes = vapply(fmt_hits, function(x) x$code, ""),
                 f_grade_reasons = f_grade_reasons,
                 strategy_manifest = strategy_manifest_path,
                 bt_contract = bt_contract,
                 authoritative = auth))
}

# ---- Telegram brief (tg_agent_brief 단일 진입점; 헤더에 모드 배지 자동) ----
.with_alpha_search_tg_lock <- function(strategy_id, expr,
                                       timeout_sec = 900,
                                       stale_sec = 1800) {
  expr <- substitute(expr)
  env <- parent.frame()
  if (isFALSE(tolower(Sys.getenv("QVEST_TG_SERIAL_LOCK", "true")) %in% c("1", "true", "yes"))) {
    return(eval(expr, env))
  }

  lock_root <- file.path(PROJECT_ROOT, "stage_artifacts", "telegram_locks")
  lock_dir <- file.path(lock_root, "alpha_search_send.lock")
  dir.create(lock_root, recursive = TRUE, showWarnings = FALSE)
  started <- Sys.time()
  acquired <- FALSE
  repeat {
    acquired <- dir.create(lock_dir, showWarnings = FALSE)
    if (isTRUE(acquired)) {
      owner <- c(
        sprintf("strategy_id=%s", strategy_id %||% "unknown"),
        sprintf("pid=%s", Sys.getpid()),
        sprintf("started=%s", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
      )
      try(writeLines(owner, file.path(lock_dir, "owner.txt")), silent = TRUE)
      break
    }

    info <- suppressWarnings(file.info(lock_dir))
    if (nrow(info) == 1L && !is.na(info$mtime)) {
      age <- as.numeric(difftime(Sys.time(), info$mtime, units = "secs"))
      if (is.finite(age) && age > stale_sec) {
        cat(sprintf("[AlphaSearch][TG] stale telegram lock removed (age %.0fs)\n", age))
        unlink(lock_dir, recursive = TRUE, force = TRUE)
        next
      }
    }

    waited <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    if (is.finite(waited) && waited > timeout_sec) {
      cat(sprintf("[AlphaSearch][TG] telegram lock timeout after %.0fs — sending without lock\n", waited))
      return(eval(expr, env))
    }
    Sys.sleep(runif(1L, 0.5, 1.5))
  }

  on.exit({
    if (isTRUE(acquired)) unlink(lock_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  eval(expr, env)
}

.clip_msg <- function(x, n = 150L) {
  x <- paste(as.character(x %||% ""), collapse = " ")
  x <- gsub("\\s+", " ", x)
  if (nchar(x, type = "chars") > n) paste0(substr(x, 1L, n - 1L), "...") else x
}

.alpha_tg_bullets <- function(items, fallback = "후속: 전략 명세와 분석 리포트에서 상세 실패축 확인") {
  items <- as.character(items %||% character(0))
  items <- items[nzchar(items)]
  items <- vapply(items, function(x) {
    x <- gsub("FMT-[0-9]+\\s+[^:]+:", "진단:", x, perl = TRUE)
    x <- gsub("\\bMDD\\b", "최대낙폭", x, perl = TRUE)
    x <- gsub("\\bIR\\b", "정보비율", x, perl = TRUE)
    x <- gsub("\\bCAGR\\b", "연복리수익률", x, perl = TRUE)
    x <- gsub("\\bOOS\\b", "표본외", x, perl = TRUE)
    x <- gsub("\\bDSR\\b", "감가샤프", x, perl = TRUE)
    x <- gsub("\\bRCMA\\b", "국면조건부 평가", x, perl = TRUE)
    x <- gsub("\\bPORT_t\\b", "포트폴리오 검정", x, perl = TRUE)
    x <- gsub("\\bNW\\b", "뉴이웨스트", x, perl = TRUE)
    x <- gsub("\\bhard_fail\\b", "하드 실패", x, perl = TRUE)
    x <- gsub("\\bgrade\\b", "등급", x, ignore.case = TRUE, perl = TRUE)
    x <- gsub("[_]+", " ", x, perl = TRUE)
    .clip_msg(x, 70L)
  }, character(1))
  items <- unique(items[nzchar(items)])
  if (!length(items)) items <- fallback
  if (length(items) == 1L && !identical(items[1], fallback)) items <- c(items, fallback)
  head(items, 5L)
}

.send_alpha_search_plain_brief <- function(strategy_name, strategy_idea, strategy_id,
                                          grade, score, m, excess_cagr,
                                          f_reasons = character(0),
                                          dry_run = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  idea <- .clip_msg(strategy_idea %||% "", 180L)
  reasons <- .alpha_tg_bullets(f_reasons %||% character(0),
                               fallback = "상세 실패축은 전략 명세와 분석 리포트에 기록됨")
  msg <- paste(c(
    sprintf("🔭 [AlphaSearch] %s", strategy_name),
    sprintf("전략ID: %s", strategy_id),
    sprintf("등급: %s | 점수: %.0f/100 | 초과수익: %+.1f%%p",
            grade, score %||% 0, excess_cagr %||% 0),
    sprintf("성과: CAGR %.1f%% | Sharpe %.2f | MDD %.1f%% | IR %.2f | Turnover %.0f%%",
            .as_num(m$CAGR), .as_num(m$Sharpe), -abs(.as_num(m$MDD)),
            .as_num(m$IR), .as_num(m$Turnover_Ann)),
    sprintf("아이디어: %s", idea),
    "F등급/주의 사유:",
    paste0("- ", reasons)
  ), collapse = "\n")

  if (isTRUE(dry_run)) {
    cat("=== alpha_search plain fallback dry_run ===\n")
    cat(msg, "\n")
    return(invisible(list(ok = TRUE, fallback = "plain_dry_run", bytes = nchar(msg, type = "bytes"))))
  }
  if (!exists("tg_send", mode = "function")) {
    stop("tg_send() not available for mandatory alpha brief fallback")
  }
  tg_send(msg, parse_mode = "", validate_emoji = TRUE, emoji_min = 1L)
  invisible(list(ok = TRUE, fallback = "plain", bytes = nchar(msg, type = "bytes")))
}

.alpha_failure_reasons <- function(grade, hg, fmt = list(), m = list(),
                                   excess_cagr = NA_real_, auth = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  if (!identical(as.character(grade), "F")) return(character(0))

  v <- hg$verdict %||% list()
  items <- character(0)

  fr <- v$fail_reasons %||% character(0)
  if (is.list(fr)) fr <- unlist(fr, use.names = FALSE)
  fr <- fr[nzchar(fr)]
  if (length(fr)) {
    items <- c(items, sprintf("게이트 사유: %s", .clip_msg(paste(fr, collapse = " | "), 165L)))
  } else if (isTRUE(v$hard_fail)) {
    items <- c(items, "게이트 사유: hard_fail=TRUE이나 상세 사유가 비어 있음")
  }

  if (length(fmt)) {
    fmt_lines <- vapply(head(fmt, 3L), function(x) {
      sprintf("%s %s: %s", x$code %||% "FMT", x$label %||% "진단", .clip_msg(x$reason %||% "", 130L))
    }, character(1))
    items <- c(items, fmt_lines)
  }

  ir <- .as_num(m$IR)
  exc <- .as_num(excess_cagr)
  mdd <- abs(.as_num(m$MDD))
  to <- .as_num(m$Turnover_Ann)
  if (!is.na(ir) && ir <= 0) {
    items <- c(items, sprintf("알파 부재: 정보비율 %.2f로 벤치 대비 기여가 음수/미약", ir))
  }
  if (!is.na(exc) && exc <= 0) {
    items <- c(items, sprintf("초과수익 부족: 벤치 대비 %+.1f%%p", exc))
  }
  if (!is.na(mdd) && mdd > 45 && !any(grepl("최대낙폭|MDD|Structural|drawdown", items, ignore.case = TRUE))) {
    items <- c(items, sprintf("낙폭 부담: 최대낙폭 %.1f%%", mdd))
  }
  if (!is.na(to) && to > 1100) {
    items <- c(items, sprintf("구현 부담: 연환산 회전율 %.0f%%로 1,100%% 초과", to))
  }

  if (!is.null(auth) && identical(auth$essence_grade %||% NA_character_, "F")) {
    ar <- auth$reasons %||% ""
    if (nzchar(ar)) items <- c(items, sprintf("권위측정: %s", .clip_msg(ar, 150L)))
  }

  items <- unique(items[nzchar(items)])
  if (!length(items)) {
    items <- c("종합점수/F 판정이나 상세 실패축이 부족함", "후속: analysis_report.md에서 IC·국면·보유종목 진단 확인")
  } else if (length(items) == 1L) {
    items <- c(items, "후속: 단독 운용 탈락과 별개로 국면조건부 차용은 RCMA에서 별도 평가")
  }
  head(items, 5L)
}

.alpha_search_strategy_spec <- function(strategy_id, strategy_name, strategy_idea,
                                        factor_engine_path, universe, weight_method,
                                        risk_controls = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  rc <- risk_controls %||% list()
  rc_bits <- character(0)
  if (!is.null(rc$vol_target)) {
    rc_bits <- c(rc_bits, sprintf("vol_target=%.4f, lookback=%sd",
                                  as.numeric(rc$vol_target), as.integer(rc$vol_lookback %||% 60L)))
  }
  if (!is.null(rc$dd_brake)) {
    rc_bits <- c(rc_bits, sprintf("dd_brake(entry=%.4f, exit=%.4f)",
                                  as.numeric(rc$dd_brake$entry_pct %||% NA_real_),
                                  as.numeric(rc$dd_brake$exit_pct %||% NA_real_)))
  }
  if (!is.null(rc$buffer_zone)) {
    rc_bits <- c(rc_bits, sprintf("buffer_zone(keep_n=%s, entry_n=%s)",
                                  as.integer(rc$buffer_zone$keep_n %||% NA_integer_),
                                  as.integer(rc$buffer_zone$entry_n %||% NA_integer_)))
  }
  if (!is.null(rc$cov_method) && !identical(rc$cov_method, "sample")) {
    rc_bits <- c(rc_bits, sprintf("cov_method=%s", rc$cov_method))
  }
  rc_text <- if (length(rc_bits)) paste(rc_bits, collapse = "; ") else "none"
  list(
    strategy_id = strategy_id,
    strategy_name = strategy_name,
    strategy_family = "alpha_search",
    signal_description = substr(strategy_idea %||% "", 1, 300),
    universe_rule = sprintf("%s + 20d avg trading value >= 2e8 KRW (t-1 PIT)", universe %||% "ALL"),
    rebalance_frequency = "monthly",
    signal_date_rule = "month_end_signal",
    execution_date_rule = "t_plus_1_first_trading_day",
    weighting_method = weight_method,
    max_position_weight = 0.20,
    max_leverage = 1.0,
    cash_rule = "fully_invested_after_floor_shares",
    cost_model = "v2.4_delta_15bps",
    missing_data_rule = "exclude_na_scores",
    risk_controls = rc_text,
    lookahead_prevention = "detect_lookahead static scan CLEAN (PIT C1-C15)",
    survivorship_bias_control = "RAWDATA PIT membership / time-varying universe filters",
    factor_engine_path = .rel_project_path(factor_engine_path)
  )
}

.standardize_alpha_search_bt_result <- function(sim, strategy_id, strategy_name, strategy_idea,
                                                factor_engine_path, out_dir,
                                                universe = "K200_KQ150",
                                                weight_method = "ivol",
                                                commission = 0.0015,
                                                risk_controls = NULL,
                                                run_prefix = "ASBT") {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  out_path <- file.path(out_dir, "bt_contract_status.json")
  bt_path <- file.path(out_dir, "bt_result.rds")
  status <- tryCatch({
    cdir <- file.path(PROJECT_ROOT, "02_Infrastructure", "contracts")
    source(file.path(cdir, "backtest_result_contract.R"))
    source(file.path(cdir, "audit_bt_result.R"))
    source(file.path(cdir, "save_bt_result.R"))

    spec <- .alpha_search_strategy_spec(strategy_id, strategy_name, strategy_idea,
                                        factor_engine_path, universe, weight_method,
                                        risk_controls = risk_controls)
    run_id <- sprintf("%s_%s", run_prefix, basename(out_dir))
    bt <- build_bt_result(
      sim, spec, run_id = run_id, strategy_id = strategy_id,
      strategy_version = "alpha_search_v1",
      benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
      transaction_cost_bps = round(commission * 1e4, 1),
      slippage_bps = 0,
      risk_free_rate = 0, frequency = "daily", annualization_factor = 252,
      universe_id = universe %||% "ALL",
      code_version = "run_alpha_search_v8.2_contract_always",
      created_by_agent = "AlphaSearch"
    )
    bt <- audit_bt_result(bt)
    validation <- validate_bt_result(bt)
    save_bt_result(bt, out_dir, save_xlsx = FALSE)
    AU <- as.data.table(bt$audit)
    pr <- tryCatch(as.data.table(bt$period_returns), error = function(e) data.table())
    if (nrow(pr) && "date" %in% names(pr)) pr[, date := as.Date(date)]
    return_series <- if (nrow(pr) && "date" %in% names(pr) && "ret_net" %in% names(pr)) {
      list(
        status = "OK",
        source = "bt_result.period_returns",
        csv_path = .rel_project_path(file.path(out_dir, "03_period_returns.csv")),
        date_col = "date",
        ret_col = "ret_net",
        n_obs = nrow(pr),
        start_date = as.character(min(pr$date, na.rm = TRUE)),
        end_date = as.character(max(pr$date, na.rm = TRUE)),
        post2008_obs = sum(pr$date >= as.Date("2008-01-01"), na.rm = TRUE),
        frequency = as.character(pr$frequency[1] %||% "daily")
      )
    } else {
      list(
        status = "MISSING",
        source = "bt_result.period_returns",
        csv_path = .rel_project_path(file.path(out_dir, "03_period_returns.csv")),
        date_col = "date",
        ret_col = "ret_net",
        n_obs = 0L,
        note = "period_returns$date/ret_net not available in bt_result"
      )
    }
    list(
      status = if (isTRUE(validation$valid)) "OK" else "INVALID",
      strategy_id = strategy_id,
      strategy_name = strategy_name,
      run_id = run_id,
      bt_result_path = bt_path,
      output_dir = out_dir,
      metric_type = "backtested",
      integrity_status = bt$manifest$integrity_status[1] %||% "UNKNOWN",
      audit_pass = nrow(AU[status == "PASS"]),
      audit_fail = nrow(AU[status == "FAIL"]),
      audit_warn = nrow(AU[status == "WARN"]),
      validation_errors = validation$errors %||% character(0),
      return_series = return_series,
      note = "standard Backtest Result Contract saved for every AlphaSearch run; grade/admission remains separate"
    )
  }, error = function(e) {
    list(
      status = "FAIL",
      strategy_id = strategy_id,
      strategy_name = strategy_name,
      run_id = sprintf("%s_%s", run_prefix, basename(out_dir)),
      bt_result_path = bt_path,
      output_dir = out_dir,
      metric_type = "unavailable",
      integrity_status = "FAIL",
      audit_pass = NA_integer_,
      audit_fail = NA_integer_,
      audit_warn = NA_integer_,
      validation_errors = character(0),
      return_series = list(
        status = "UNAVAILABLE",
        source = "bt_result.period_returns",
        n_obs = 0L,
        note = "standard bt_result contract generation failed"
      ),
      error = conditionMessage(e),
      note = "standard Backtest Result Contract generation failed; sim_result quarantine remains available"
    )
  })
  tryCatch(
    jsonlite::write_json(status, out_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null"),
    error = function(e) cat("[AlphaSearch][BT-CONTRACT] WARN: status JSON 저장 실패 —", conditionMessage(e), "\n")
  )
  if (identical(status$status, "OK")) {
    cat(sprintf("[AlphaSearch] 표준 bt_result contract 저장: %s | integrity=%s\n",
                status$bt_result_path, status$integrity_status %||% "UNKNOWN"))
  } else {
    cat(sprintf("[AlphaSearch] WARN: 표준 bt_result contract 저장 실패/불완전 (%s) — %s\n",
                status$status %||% "UNKNOWN", status$error %||% status$note %||% "unknown"))
  }
  status
}

.write_alpha_search_strategy_manifest <- function(out_dir, strategy_id, strategy_name,
                                                  strategy_idea, factor_engine_path,
                                                  grade, score, hg, fmt, f_grade_reasons,
                                                  auth, metrics, excess_cagr,
                                                  universe, universe_n, n_holdings,
                                                  weight_method, commission,
                                                  risk_controls = NULL,
                                                  bt_contract = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  v <- hg$verdict %||% list()
  fr <- v$fail_reasons %||% character(0)
  if (is.list(fr)) fr <- unlist(fr, use.names = FALSE)
  fr <- fr[nzchar(fr)]
  fmt_rows <- lapply(fmt, function(x) {
    list(code = x$code %||% NA_character_,
         label = x$label %||% NA_character_,
         reason = x$reason %||% NA_character_)
  })
  auth_summary <- if (is.null(auth)) {
    NULL
  } else {
    list(status = auth$status %||% NA_character_,
         essence_grade = auth$essence_grade %||% NA_character_,
         reasons = auth$reasons %||% NA_character_,
         metric_type = auth$metric_type %||% NA_character_,
         run_id = auth$run_id %||% NA_character_,
         bt_result_path = auth$bt_result_path %||% NA_character_)
  }
  bt_summary <- if (is.null(bt_contract)) {
    list(status = "MISSING",
         bt_result_path = .rel_project_path(file.path(out_dir, "bt_result.rds")),
         note = "standard backtest contract was not generated")
  } else {
    list(
      status = bt_contract$status %||% NA_character_,
      run_id = bt_contract$run_id %||% NA_character_,
      metric_type = bt_contract$metric_type %||% NA_character_,
      bt_result_path = .rel_project_path(bt_contract$bt_result_path %||% file.path(out_dir, "bt_result.rds")),
      output_dir = .rel_project_path(bt_contract$output_dir %||% out_dir),
      integrity_status = bt_contract$integrity_status %||% NA_character_,
      audit_pass = bt_contract$audit_pass %||% NA_integer_,
      audit_fail = bt_contract$audit_fail %||% NA_integer_,
      audit_warn = bt_contract$audit_warn %||% NA_integer_,
      validation_errors = as.list(bt_contract$validation_errors %||% character(0)),
      return_series = bt_contract$return_series %||% list(status = "UNKNOWN"),
      note = bt_contract$note %||% NA_character_
    )
  }
  manifest <- list(
    schema_version = "alpha_search_strategy_manifest_v1",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    mode = "alpha_search",
    strategy_id = strategy_id,
    strategy_name = strategy_name,
    strategy_idea = strategy_idea,
    factor_engine_path = .rel_project_path(factor_engine_path),
    execution = list(
      universe = universe,
      universe_n = universe_n,
      n_holdings = n_holdings,
      weight_method = weight_method,
      commission = commission,
      risk_controls = risk_controls %||% list(),
      bt_result_path = bt_summary$bt_result_path
    ),
    pit = list(
      code_scan = "detect_lookahead",
      status = "CLEAN",
      factor_engine_path = .rel_project_path(factor_engine_path),
      note = "AlphaSearch stops before backtest when detect_lookahead reports violations."
    ),
    backtest_contract = bt_summary,
    verdict = list(
      grade = grade,
      score = score,
      hurdle_pass = isTRUE(v$pass),
      hard_fail = isTRUE(v$hard_fail),
      fail_reasons = as.list(fr),
      f_grade_reasons = as.list(f_grade_reasons),
      screening = v$screening %||% list()
    ),
    metrics = metrics %||% list(),
    excess_cagr_pct = excess_cagr,
    fmt = fmt_rows,
    authoritative = auth_summary
  )
  path <- file.path(out_dir, "strategy_manifest.json")
  tryCatch({
    jsonlite::write_json(manifest, path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    cat(sprintf("[AlphaSearch] 전략 명세 저장: %s\n", path))
  }, error = function(e) {
    cat("[AlphaSearch] 전략 명세 저장 실패:", conditionMessage(e), "\n")
  })
  path
}

.send_alpha_search_brief <- function(strategy_name, strategy_idea, strategy_id, grade,
                                     score, m, sdef, excess_cagr, charts,
                                     universe = "ALL", universe_n = NA_integer_,
                                     out_dir = NULL, hg = list(), fmt = list(),
                                     auth = NULL, f_reasons = NULL, dry_run = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  verdict_word <-if (grade %in% c("A", "A_NOVEL", "A_DEF")) "통과"
                  else if (grade %in% c("B", "C")) "근접"
                  else "미달"
  uni_label <- if (identical(universe, "KR_TOP500")) "시총상위500(거래대금2억+)"
               else "전종목(거래대금2억+)"
  uni_desc  <- if (!is.na(universe_n)) sprintf("%s·%d종목/월", uni_label, universe_n) else uni_label
  ctx <- sprintf(
    paste0("[연구목적] %s 가설 백테스트 검증.\n",
           "[검토] 유니버스 %s · 전기간 · 15bps · PIT.\n",
           "[결론] 등급 %s · 종합 %.0f점 · 벤치(KOSPI200) 대비 %+.2f%%p (%s)."),
    strategy_name, uni_desc, grade, score %||% 0, excess_cagr %||% 0, verdict_word)
  ctx_body <- .clip_msg(ctx, 210L)

  idea_body <- strategy_idea %||% ""
  if (nchar(idea_body, type = "chars") < 30L) {
    idea_body <- paste0(idea_body, sprintf(" — %s · 월간 리밸런싱 단일 전략으로 검증.", uni_label))
  }
  idea_body <- .clip_msg(idea_body, 210L)

  kv <- list(
    "유니버스"      = uni_desc,
    "등급"          = as.character(grade),
    "종합점수"      = sprintf("%.0f/100", score %||% 0),
    "샤프지수"      = sprintf("%.2f", .as_num(m$Sharpe)),
    "연복리수익률"  = sprintf("%.1f%%", .as_num(m$CAGR)),
    "최대낙폭"      = sprintf("%.1f%%", -abs(.as_num(m$MDD))),
    "칼마지수"      = sprintf("%.2f", .as_num(m$Calmar)),
    "정보비율"      = sprintf("%.2f", .as_num(m$IR)),
    "회전율"        = sprintf("%.0f%%", .as_num(m$Turnover_Ann)),
    "벤치마크상관"  = sprintf("%.2f", .as_num(m$BM_Corr)),
    "초과수익"      = sprintf("%+.1f%%p", excess_cagr %||% 0)
  )
  dsr <- .as_num(sdef$dsr)
  if (!is.na(dsr)) kv[["감가샤프지수"]] <- sprintf("%.2f", dsr)

  weak <- character(0)
  if (.as_num(m$Turnover_Ann) > 300) weak <- c(weak, sprintf("회전율 높음 (연 %.0f%%) — 거래비용 민감", .as_num(m$Turnover_Ann)))
  if (abs(.as_num(m$MDD)) > 30)      weak <- c(weak, sprintf("최대낙폭 큼 (%.1f%%)", -abs(.as_num(m$MDD))))
  # DSR weak-flag = 게이트 적용분(sweep)만. chain/단일은 진단수치라 비표기 (도훈 mandate 2026-06-10).
  dsr_gated <- is.null(sdef$dsr_gate_applied) || isTRUE(sdef$dsr_gate_applied)  # 필드 없으면 legacy(=sweep만 산출되던 시절) 표기 유지
  if (!is.na(dsr) && dsr < 0.5 && dsr_gated) weak <- c(weak, "감가샤프지수 낮음 — 다중검정(sweep)에 취약")
  if (!is.na(excess_cagr) && excess_cagr <= 0) weak <- c(weak, "벤치마크 대비 초과수익 미확보")
  if (length(weak) < 2) weak <- c(weak, "특이 위험요인 제한적", "추가 정밀검증 권고")
  weak <- head(weak, 5L)

  # FF3/FF5/Carhart 팩터알파는 [팩터분석] 메시지(tg_pass_analysis)로 일원화 — 메인 brief 중복 제거 (2026-06-05 도훈)

  sections <- list(
    list(type = "text",   emoji = "\U0001F4DA", heading = "연구 컨텍스트", body = ctx_body),
    list(type = "text",   emoji = "\U0001F4A1", heading = "전략 아이디어", body = idea_body),
    list(type = "kv",     emoji = "\U0001F4C8", heading = "성과 요약",     kv   = kv)
  )
  f_reason <- f_reasons %||% .alpha_failure_reasons(grade, hg, fmt, m, excess_cagr, auth)
  if (length(f_reason)) {
    f_reason <- .alpha_tg_bullets(f_reason)
    sections <- c(sections, list(list(type = "bullet", emoji = "\U0001F50E",
                                      heading = "F등급 사유", items = f_reason)))
  }
  sections <- c(sections, list(list(type = "bullet", emoji = "\U0001F6A9",
                heading = "주의/약점", items = weak)))
  title <- sprintf("알파 서칭 — %s 검증 (등급 %s)", strategy_name, grade)
  result <- tryCatch(
    tg_agent_brief(agent = "AlphaSearch",
                   title = title,
                   sections = sections, charts = charts, lock_scope = strategy_id,
                   dry_run = dry_run),
    error = function(e) {
      cat("[AlphaSearch][TG] 발송 실패:", conditionMessage(e), "\n")
      list(ok = FALSE, error = conditionMessage(e))
    })

  if (!isTRUE(result$ok)) {
    fallback_items <- .alpha_tg_bullets(c(
      if (length(f_reason)) f_reason else "메인 브리프 검증 규칙으로 원문 발송 실패",
      sprintf("등급 %s · 점수 %.0f · 초과수익 %+.1f%%p", grade, score %||% 0, excess_cagr %||% 0)
    ))
    result <- tryCatch(
      tg_agent_brief(agent = "AlphaSearch",
                     title = sprintf("알파 서칭 요약 — %s (등급 %s)", strategy_name, grade),
                     sections = list(
                       list(type = "text", emoji = "\U0001F4DA", heading = "연구 컨텍스트", body = ctx_body),
                       list(type = "kv", emoji = "\U0001F4C8", heading = "성과 요약", kv = kv),
                       list(type = "bullet", emoji = "\U0001F50E", heading = "핵심 판단", items = fallback_items),
                       list(type = "bullet", emoji = "\U0001F6A9", heading = "주의/약점", items = .alpha_tg_bullets(weak))
                     ),
                     charts = charts, lock_scope = paste0(strategy_id, "_fallback"),
                     dry_run = dry_run, force = TRUE),
      error = function(e) {
        cat("[AlphaSearch][TG] fallback 발송 실패:", conditionMessage(e), "\n")
        list(ok = FALSE, error = conditionMessage(e))
      })
  }
  if (!isTRUE(result$ok)) {
    result <- tryCatch(
      .send_alpha_search_plain_brief(strategy_name, strategy_idea, strategy_id,
                                     grade, score, m, excess_cagr,
                                     f_reasons = f_reason %||% weak,
                                     dry_run = dry_run),
      error = function(e) {
        cat("[AlphaSearch][TG] mandatory plain fallback 실패:", conditionMessage(e), "\n")
        list(ok = FALSE, error = conditionMessage(e))
      })
  }
  invisible(result)
}

# =============================================================================
# FMT-01~08 실패모드 자동판정 (strategy_postmortem.md taxonomy → hurdle metrics rule)
# 임계값 도훈 승인 2026-06-10: FMT-02 IR<-0.1 / FMT-04 corr≥0.7 / FMT-07 post-SR≤0.1 (FMT-06 수동 전용)
# =============================================================================
# 정의 SOT: 04_Research/strategy_postmortem.md "Failure Mode Taxonomy (FMT)".
# 모든 rule은 proxy 진단(라벨)이며 게이트가 아님. 측정 가능한 지표 rule만 자동판정:
#   FMT-01 Structural/Tail MDD   : MDD > 45% (게이트 아님; 권위측정은 drawdown 빈도/지속성으로 판정)
#   FMT-02 Factor Degeneration   : IR < -0.1 AND 초과CAGR < 0 (KR에서 부호 역작동 의심)
#   FMT-03 Ensemble Dilution     : 앙상블/블렌드 구성(키워드) AND grade C/F
#   FMT-04 Regime Blindness      : MDD > 35% AND BM_Corr >= 0.7 (위기 동조 낙폭 + 국면필터 부재)
#   FMT-05 Turnover Toxicity     : 연환산 회전율 > 1,100% (postmortem 정의 임계)
#   FMT-06 Korea-Specific Signal Inversion : ★자동판정 제외 — SG사태/작전주 등 사건 식별은
#          메트릭만으로 불가(수동 진단 전용). 거짓 양성 방지를 위해 rule 미구현 (정직성).
#   FMT-07 Publication Decay     : pre-2017 활성SR >= 0.5 AND post-2017 활성SR <= 0.1
#          (각 2년+ 데이터 필요) OR alpha_trend ratio(최근3Y/전체) <= 0.3 (전체 SR >= 0.3 전제)
#   FMT-08 Regime Overfit        : regime/국면/게이팅 키워드 구성 AND 초과CAGR < 0 (회복랠리 상실)
.judge_fmt <- function(m, hg, sim, strategy_name, strategy_idea, excess_cagr, grade) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  hits <- list()
  add <- function(code, label, reason)
    hits[[length(hits) + 1L]] <<- list(code = code, label = label, reason = reason)

  mdd  <- abs(.as_num(m$MDD))          # percent
  to   <- .as_num(m$Turnover_Ann)      # percent
  ir   <- .as_num(m$IR)
  bmc  <- .as_num(m$BM_Corr)
  shp  <- .as_num(m$Sharpe)
  exc  <- .as_num(excess_cagr)
  txt  <- tolower(paste(strategy_name %||% "", strategy_idea %||% ""))

  # FMT-01
  if (!is.na(mdd) && mdd > 45)
    add("FMT-01", "Structural MDD",
        sprintf("MDD %.1f%% > 45%% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)", mdd))
  # FMT-02
  if (!is.na(ir) && ir < -0.1 && !is.na(exc) && exc < 0)
    add("FMT-02", "Factor Degeneration",
        sprintf("IR %.2f < -0.1 & 초과CAGR %+.1f%%p < 0 — KR에서 팩터 방향 역작동 의심", ir, exc))
  # FMT-03 (키워드 + 등급)
  if (grepl("ensemble|앙상블|blend|블렌드|배합|composite|합성|결합", txt) && grade %in% c("C", "F"))
    add("FMT-03", "Ensemble Dilution",
        sprintf("앙상블/블렌드 구성 + grade %s — 결합 시 강점 희석 의심 (키워드 기반 heuristic)", grade))
  # FMT-04
  if (!is.na(mdd) && mdd > 35 && !is.na(bmc) && bmc >= 0.7)
    add("FMT-04", "Regime Blindness",
        sprintf("MDD %.1f%% > 35%% & BM상관 %.2f >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)", mdd, bmc))
  # FMT-05
  if (!is.na(to) && to > 1100)
    add("FMT-05", "Turnover Toxicity",
        sprintf("연환산 회전율 %.0f%% > 1,100%% — 15bps 비용이 알파 소진", to))
  # FMT-07 (2017 전후 활성수익 SR 분해 — PerformanceAnalytics 표준함수만)
  fmt07 <- tryCatch({
    mg <- merge(sim$strategy_xts, sim$bm_xts, join = "inner")
    act <- mg[, 1] - mg[, 2]
    pre  <- act[zoo::index(act) <  as.Date("2017-01-01")]
    post <- act[zoo::index(act) >= as.Date("2017-01-01")]
    if (nrow(pre) >= 252 * 2 && nrow(post) >= 252 * 2) {
      sr_pre  <- as.numeric(PerformanceAnalytics::SharpeRatio.annualized(pre,  Rf = 0))
      sr_post <- as.numeric(PerformanceAnalytics::SharpeRatio.annualized(post, Rf = 0))
      if (is.finite(sr_pre) && is.finite(sr_post) && sr_pre >= 0.5 && sr_post <= 0.1)
        sprintf("활성SR pre-2017 %.2f -> post-2017 %.2f — 논문발표 후 알파 소진 패턴", sr_pre, sr_post)
      else NULL
    } else NULL
  }, error = function(e) NULL)
  if (is.null(fmt07)) {
    at_ratio <- .as_num(tryCatch(hg$verdict$score_breakdown$alpha_trend$value, error = function(e) NA))
    if (!is.na(at_ratio) && at_ratio <= 0.3 && !is.na(shp) && shp >= 0.3)
      fmt07 <- sprintf("alpha_trend ratio(최근3Y/전체 SR) %.2f <= 0.3 — 후반부 알파 붕괴", at_ratio)
  }
  if (!is.null(fmt07)) add("FMT-07", "Publication Decay", fmt07)
  # FMT-08
  if (grepl("regime|국면|게이팅|gating|타이밍|timing", txt) && !is.na(exc) && exc < 0)
    add("FMT-08", "Regime Overfit",
        sprintf("국면 게이팅 구성 + 초과CAGR %+.1f%%p < 0 — 회복랠리 상실로 CAGR 훼손 의심", exc))

  hits
}

# ---- analysis_report.md FMT 체크리스트 자동 체크 ([ ] -> [x] + 사유) ----
.patch_fmt_checklist <- function(out_dir, fmt_hits) {
  rp <- file.path(out_dir, "analysis_report.md")
  if (!file.exists(rp)) {
    if (length(fmt_hits))
      cat("[AlphaSearch][FMT] WARN: analysis_report.md 부재 — 체크리스트 자동 체크 생략 (판정값은 L-code에 보존)\n")
    return(invisible(FALSE))
  }
  if (!length(fmt_hits)) return(invisible(TRUE))   # 빈 판정 = 체크 없음 (원본 유지)
  tryCatch({
    lines <- readLines(rp, warn = FALSE, encoding = "UTF-8")
    for (h in fmt_hits) {
      pat <- sprintf("- [ ] %s:", h$code)
      idx <- which(startsWith(lines, pat))
      if (length(idx) == 1L)
        lines[idx] <- sprintf("%s — AUTO: %s",
                              sub("- [ ] ", "- [x] ", lines[idx], fixed = TRUE), h$reason)
    }
    # 자동판정 명시 (rule 출처 + heuristic 고지 — 수동 진단 FMT-06 제외)
    tail_note <- "(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)"
    if (!any(grepl("FMT 자동판정", lines, fixed = TRUE))) lines <- c(lines, "", tail_note)
    writeLines(lines, rp, useBytes = FALSE)
    cat(sprintf("[AlphaSearch] analysis_report.md FMT %d건 자동 체크 완료\n", length(fmt_hits)))
    invisible(TRUE)
  }, error = function(e) {
    cat("[AlphaSearch][FMT] WARN: 체크리스트 패치 실패 —", conditionMessage(e), "\n")
    invisible(FALSE)
  })
}

# =============================================================================
# 권위측정 사다리: proxy(hurdle B 이상 또는 screening_pass) → 계약 실측 재측정 (build_bt_result + essence_score)
# =============================================================================
# measurement-graduation §1(real-computation) §2(PORT_t forge-authoritative) §3(severity).
# alpha-search = 1논문/1알파 가설주도 검증 → selection_type="chain" (DSR 게이트 부적용,
# essence_score 주석 + 도훈 mandate 2026-05-31/2026-06-10). 결과는 OUT_DIR/
# bt_result.rds + authoritative_remeasure.json + 호출부 L-code 라벨. 실패 시 정직 WARN + status="FAIL" 기록.
.authoritative_remeasure <- function(sim, strategy_id, strategy_name, strategy_idea,
                                     factor_engine_path, out_dir, hurdle_grade,
                                     universe = "K200_KQ150", weight_method = "ivol",
                                     commission = 0.0015, n_trials_cumulative = NULL,
                                     risk_controls = NULL,
                                     bt_contract = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  out_path <- file.path(out_dir, "authoritative_remeasure.json")
  bt_path  <- file.path(out_dir, "bt_result.rds")
  res <- tryCatch({
    cdir <- file.path(PROJECT_ROOT, "02_Infrastructure", "contracts")
    source(file.path(cdir, "backtest_result_contract.R"))   # build_bt_result()
    source(file.path(cdir, "audit_bt_result.R"))            # audit_bt_result()
    source(file.path(cdir, "essence_score.R"))              # essence_score()
    source(file.path(cdir, "save_bt_result.R"))              # save_bt_result()

    reuse_existing <- !is.null(bt_contract) &&
      identical(bt_contract$status %||% NA_character_, "OK") &&
      file.exists(bt_contract$bt_result_path %||% bt_path)
    if (reuse_existing) {
      bt <- readRDS(bt_contract$bt_result_path %||% bt_path)
      run_id <- bt$manifest$run_id[1] %||% sprintf("ASBT_%s", basename(out_dir))
    } else {
      spec <- .alpha_search_strategy_spec(strategy_id, strategy_name, strategy_idea,
                                          factor_engine_path, universe, weight_method,
                                          risk_controls = risk_controls)
      run_id <- sprintf("ASRM_%s", basename(out_dir))
      bt <- build_bt_result(
        sim, spec, run_id = run_id, strategy_id = strategy_id,
        strategy_version = "alpha_search_v1",
        benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
        transaction_cost_bps = round(commission * 1e4, 1),
        slippage_bps = 0,                       # 별도 슬리피지 미부과 (commission에 일원화) — 정직 기록
        risk_free_rate = 0, frequency = "daily", annualization_factor = 252,
        universe_id = universe %||% "ALL",
        code_version = "run_alpha_search_v8.2_contract_always",
        created_by_agent = "AlphaSearch")
      bt <- audit_bt_result(bt)
      save_bt_result(bt, out_dir, save_xlsx = FALSE)
    }
    es <- essence_score(bt, n_trials_cumulative = n_trials_cumulative,
                        selection_type = "chain")

    AU <- as.data.table(bt$audit)
    getm <- function(nm) { v <- bt$metrics[metric_name == nm, metric_value]
                           if (length(v)) as.numeric(v[1]) else NA_real_ }
    integrity <- bt$manifest$integrity_status[1] %||% "UNKNOWN"
    ok <- identical(es$metric_type, "backtested") && !identical(integrity, "FAIL")
    list(
      status        = if (ok) "OK" else "FAIL",
      strategy_id   = strategy_id,
      strategy_name = strategy_name,
      trigger_grade = hurdle_grade,                    # proxy hurdle 등급 (사다리 트리거)
      remeasured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      run_id        = run_id,
      bt_result_path = bt_path,
      metric_type   = es$metric_type,                  # "backtested" = 계약 경유 실측
      essence_grade = es$grade,
      essence       = es$essence,                      # PORT_t NW lag-3 / OOS retention / DSR 등
      dsr_gate_applied = es$dsr_gate_applied,
      selection_type   = "chain",
      hard_fail        = es$hard_fail,
      reasons          = es$reasons,
      contract = list(
        integrity_status = integrity,
        audit_pass = nrow(AU[status == "PASS"]), audit_fail = nrow(AU[status == "FAIL"]),
        audit_warn = nrow(AU[status == "WARN"]),
        cagr = getm("CAGR"), sharpe = getm("Sharpe"), mdd = getm("MDD"), calmar = getm("Calmar")
      ),
      note = if (ok) "build_bt_result+audit_bt_result+essence_score 계약 경유 실측 (proxy hurdle와 별도 권위값)"
             else sprintf("재측정 비권위 (metric_type=%s, integrity=%s) — proxy 유지", es$metric_type, integrity)
    )
  }, error = function(e) {
    list(status = "FAIL", strategy_id = strategy_id, strategy_name = strategy_name,
         trigger_grade = hurdle_grade, remeasured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
         bt_result_path = bt_path, metric_type = "proxy", error = conditionMessage(e),
         note = "authoritative 재측정 실패 — proxy(run_hurdle_gate) 수치만 유효. 침묵 금지 정책에 따라 기록.")
  })
  tryCatch(jsonlite::write_json(res, out_path, auto_unbox = TRUE, pretty = TRUE, digits = 6),
           error = function(e) cat("[AlphaSearch][권위측정] WARN: JSON 저장 실패 —", conditionMessage(e), "\n"))
  if (identical(res$status, "OK")) {
    cat(sprintf("[AlphaSearch] ★ 권위측정 사다리: essence %s | PORT_t(NW lag-3) %s | OOS_ret %s | metric_type=backtested -> %s\n",
                res$essence_grade,
                ifelse(is.na(res$essence$portfolio_alpha_t_nw_lag3 %||% NA), "NA",
                       sprintf("%.2f", res$essence$portfolio_alpha_t_nw_lag3)),
                ifelse(is.na(res$essence$oos_retention %||% NA), "NA",
                       sprintf("%.2f", res$essence$oos_retention)),
                basename(out_path)))
  } else {
    cat(sprintf("[AlphaSearch] WARN: 권위측정 재측정 실패/비권위 (%s) — proxy 수치만 유효. 상세: %s\n",
                res$error %||% res$note %||% "unknown", basename(out_path)))
  }
  res
}

# ---- L-code 작성 (모드별 디렉터리 stage_artifacts/l_code/alpha_search/) ----
.write_lcode <- function(strategy_id, strategy_name, strategy_idea, grade,
                         m, excess_cagr, pass, is_fail,
                         hg = NULL, fmt = NULL, auth = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  lc_dir <-file.path(PROJECT_ROOT, "stage_artifacts", "l_code", "alpha_search")
  dir.create(lc_dir, recursive = TRUE, showWarnings = FALSE)
  tags <- c("ALPHA_SEARCH", "FAST_VALIDATION")
  if (!pass) tags <- c(tags, "VALIDATED_HARD_FAIL")   # 실패 교훈 → 역패턴 마이너 입력

  fmt <- fmt %||% list()
  fmt_codes <- vapply(fmt, function(x) x$code, "")
  oos_retention <- .as_num(tryCatch(hg$verdict$score_breakdown$oos$value, error = function(e) NA))
  fail_reasons  <- tryCatch(unlist(hg$verdict$fail_reasons), error = function(e) character(0))
  auth_ok <- !is.null(auth) && identical(auth$status, "OK")

  lesson <- if (pass)
    sprintf("%s: 등급 %s, 연복리 %.1f%% (벤치마크 대비 %+.1f%%p), 샤프 %.2f, 최대낙폭 %.1f%%. 통과 — PG 편입 권고.",
            strategy_name, grade, .as_num(m$CAGR), excess_cagr %||% 0, .as_num(m$Sharpe), -abs(.as_num(m$MDD)))
  else
    sprintf("%s: 등급 %s, 연복리 %.1f%% (벤치마크 대비 %+.1f%%p), 샤프 %.2f. %s",
            strategy_name, grade, .as_num(m$CAGR), excess_cagr %||% 0, .as_num(m$Sharpe),
            if (is_fail) "명확한 실패 패턴 — 역방향 가설 탐색 후보." else "근접 탈락 — 보강 후 재검증 후보.")
  if (auth_ok)
    lesson <- sprintf("%s [실측재측정: essence %s, PORT_t(NW) %s, metric_type=backtested]",
                      lesson, auth$essence_grade %||% "?",
                      ifelse(is.na(.as_num(auth$essence$portfolio_alpha_t_nw_lag3)), "NA",
                             sprintf("%.2f", .as_num(auth$essence$portfolio_alpha_t_nw_lag3))))

  # ---- 학습 3필드 (의무, v8.1 트랙D — 형해화 해소: 탈락축/실측수치 기반 구체 문장) ----
  # mechanism_hypothesis: 전략 아이디어 + 판정된 실패축(FMT/fail_reasons)에서 구성. 보일러플레이트 금지.
  axis_txt <- if (length(fmt)) {
    paste(vapply(fmt, function(x) sprintf("%s(%s)", x$code, x$reason), ""), collapse = "; ")
  } else if (length(fail_reasons)) {
    paste(fail_reasons, collapse = "; ")
  } else if (pass) {
    sprintf("주요 허들 통과 (초과CAGR %+.1f%%p, 샤프 %.2f) — 아이디어의 메커니즘이 KR %s 유니버스에서 유효",
            excess_cagr %||% 0, .as_num(m$Sharpe), "K200/KQ150")
  } else {
    sprintf("hard_fail 없이 점수 미달 (종합 %.0f점) — 신호 자체가 약함(IR %.2f)",
            .as_num(hg$score), .as_num(m$IR))
  }
  mechanism_hypothesis <- sprintf("가설 '%s' — 검증 결과 지배 요인: %s",
                                  strtrim(strategy_idea %||% "", 140), axis_txt)
  # data_supported_conclusion: 실측 수치 인용 (proxy/backtested 라벨 명시)
  data_supported_conclusion <- sprintf(
    "측정치(%s): CAGR %.1f%% (BM 대비 %+.1f%%p), 샤프 %.2f, MDD %.1f%%, IR %.2f, 회전율 연 %.0f%%, OOS retention %s%s.",
    if (auth_ok) "proxy hurdle + 계약 실측 병기" else "proxy — run_hurdle_gate",
    .as_num(m$CAGR), excess_cagr %||% 0, .as_num(m$Sharpe), -abs(.as_num(m$MDD)),
    .as_num(m$IR), .as_num(m$Turnover_Ann),
    ifelse(is.na(oos_retention), "NA", sprintf("%.2f", oos_retention)),
    if (auth_ok) sprintf(" | 실측(backtested): essence %s, PORT_t(NW lag-3) %s, OOS_ret %s",
                         auth$essence_grade %||% "?",
                         ifelse(is.na(.as_num(auth$essence$portfolio_alpha_t_nw_lag3)), "NA",
                                sprintf("%.2f", .as_num(auth$essence$portfolio_alpha_t_nw_lag3))),
                         ifelse(is.na(.as_num(auth$essence$oos_retention)), "NA",
                                sprintf("%.2f", .as_num(auth$essence$oos_retention)))) else "")
  # next_probe: 탈락축 기반 다음 탐색 제안 (축별 분기 — 빈 제안 금지)
  next_probe <- if (pass) {
    "QEPM 정밀검증(WorkTask) 이행 + Grade-A 풀 직교성(GradeA_Corr)·book-marginal ΔIR>=0.05 확인."
  } else if ("FMT-05" %in% fmt_codes) {
    sprintf("회전율 축 탈락(연 %.0f%%) — 리밸 주기 연장(월->분기)·buffer_zone 확대·신호 지속성 측정 후 재검증.", .as_num(m$Turnover_Ann))
  } else if (any(c("FMT-01", "FMT-04") %in% fmt_codes)) {
    sprintf("MDD 축 탈락(%.1f%%) — 신호력 보존 시 OVERLAY_CANDIDATE 라우트(국면/DD overlay는 S5/QEPM 단계) 또는 저변동 결합 재검증.", abs(.as_num(m$MDD)))
  } else if ("FMT-02" %in% fmt_codes) {
    "방향 역작동 의심 — kr-inverse-pattern-miner로 역방향 가설 생성 + long-short/multi-sleeve 구성 변경 탐색."
  } else if ("FMT-07" %in% fmt_codes) {
    "후반부 알파 붕괴 — 2017 전후 서브기간 분해 + 최근 5Y 한정 재검증으로 소멸 여부 확정."
  } else if ("FMT-08" %in% fmt_codes) {
    "게이팅 과적합 의심 — 게이트 임계 완화/제거 대조 실험으로 회복랠리 기여 분리."
  } else if ("FMT-03" %in% fmt_codes) {
    "앙상블 희석 의심 — 구성 팩터 단독 성과 분해 후 강한 축 단독/가중 재설계."
  } else if (is_fail) {
    sprintf("탈락 사유(%s) 직접 해소 변형 1건 + 역방향 가설(kr-inverse-pattern-miner) 1건 검증.",
            if (length(fail_reasons)) paste(fail_reasons, collapse = "; ") else "점수 미달")
  } else {
    sprintf("근접 탈락(종합 %.0f점) — 최약 축 보강(파라미터 아닌 구성 변경) 후 1회 재검증. 반복 sweep 시 n_trials 누적 신고.", .as_num(hg$score))
  }

  # v8.0 입력 품질 게이트 (lcode_schema.R) — garbage corpus 진입 차단 (안전핀 #1)
  schema_src <- file.path(.AS_INFRA, "axiom", "lcode_schema.R")
  if (file.exists(schema_src)) source(schema_src, local = TRUE)
  construction_type <- if (exists("infer_construction_type", mode = "function"))
    infer_construction_type(strategy_name, strategy_idea) else "single_factor_long_only"
  lcode <- list(
    l_code         = paste0("L-AS-", sub("^STR_AS_", "", strategy_id)),
    strategy_id    = strategy_id,
    grade          = grade,
    core_reference = strategy_idea,
    lesson_text    = lesson,
    tags           = tags,
    created_at     = format(Sys.Date()),
    research_mode  = "alpha_search",
    created_by     = "AlphaSearch",
    metric_type       = "proxy",              # alpha_search = run_hurdle_gate proxy → INV-1: mode-local 한정
    construction_type = construction_type,    # r7 Independence 축
    cagr_pct          = .as_num(m$CAGR),
    sharpe            = .as_num(m$Sharpe),
    mdd_pct           = abs(.as_num(m$MDD)),
    excess_cagr       = excess_cagr %||% NA_real_,
    # ---- 학습 3필드 (v8.1 트랙D 의무) + FMT + OOS ----
    mechanism_hypothesis      = mechanism_hypothesis,   # r7 Mechanism 축 입력
    data_supported_conclusion = data_supported_conclusion,
    next_probe                = next_probe,
    fmt_codes                 = as.list(fmt_codes),     # 빈 list = 판정 없음 (정직)
    oos_retention             = oos_retention           # IS65/OOS35 SR retention (hurdle D062, proxy)
  )
  # ---- 권위측정 사다리 결과 라벨 (트랙C): 계약 실측 성공 시 backtested로 승격 ----
  #   INV-1: proxy는 mode-local 한정 — 실측(backtested) 라벨은 build_bt_result+essence_score
  #   계약 경유 성공분에만 부여. 수치도 계약값으로 교체하고 proxy 원값은 proxy_metrics에 보존.
  if (auth_ok) {
    lcode$metric_type   <- "backtested"
    lcode$proxy_metrics <- list(cagr_pct = .as_num(m$CAGR), sharpe = .as_num(m$Sharpe),
                                mdd_pct = abs(.as_num(m$MDD)), excess_cagr = excess_cagr %||% NA_real_,
                                source = "run_hurdle_gate (proxy). excess_cagr는 계약 미산출 — 상단 excess_cagr도 proxy값 유지")
    if (is.finite(.as_num(auth$contract$cagr)))   lcode$cagr_pct <- round(.as_num(auth$contract$cagr) * 100, 2)
    if (is.finite(.as_num(auth$contract$sharpe))) lcode$sharpe   <- round(.as_num(auth$contract$sharpe), 3)
    if (is.finite(.as_num(auth$contract$mdd)))    lcode$mdd_pct  <- round(abs(.as_num(auth$contract$mdd)) * 100, 2)
    if (is.finite(.as_num(auth$essence$oos_retention))) lcode$oos_retention <- .as_num(auth$essence$oos_retention)
    lcode$authoritative <- list(
      essence_grade             = auth$essence_grade,
      portfolio_alpha_t_nw_lag3 = .as_num(auth$essence$portfolio_alpha_t_nw_lag3),
      oos_retention             = .as_num(auth$essence$oos_retention),
      dsr                       = .as_num(auth$essence$dsr),
      audit_integrity           = auth$contract$integrity_status,
      selection_type            = "chain",
      source                    = "authoritative_remeasure.json"
    )
  }
  if (exists("validate_lcode", mode = "function")) {
    v <- validate_lcode(lcode)
    if (!isTRUE(v$valid)) {
      cat(sprintf("[AlphaSearch][L-CODE BLOCKED] %s: %s\n", strategy_id, paste(v$errors, collapse = "; ")))
      return(invisible(NULL))
    }
    if (length(v$warnings))
      cat(sprintf("[AlphaSearch][L-CODE WARN] %s: %s\n", strategy_id, paste(v$warnings, collapse = "; ")))
  }
  path <- file.path(lc_dir, sprintf("l_code_%s.json", strategy_id))
  write_json(lcode, path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("[AlphaSearch] L-code 적립: %s [validated]\n", path))
  path
}

# ---- Axiom 파이프라인(harvester + cluster) 명시 호출 — 자동 트리거 없으므로 ----
.run_axiom_pipeline <- function() {
  hv <- file.path(.AS_INFRA, "axiom", "lcode_harvester.py")
  cl <- file.path(.AS_INFRA, "axiom", "cluster_extractor.py")
  # QVEST_PY 우선 → PATH python3. 침묵 실패 금지 — 종료코드 검사 + 정직한 메시지 (2026-06-10 fix:
  # 기존엔 python3 스텁 실패에도 무조건 "갱신" 출력하는 거짓 성공 로그였음)
  py <- Sys.getenv("QVEST_PY", unset = Sys.which("python3"))
  if (!nzchar(py)) {
    cat("[AlphaSearch] WARN: python 부재 — Axiom 파이프라인 SKIP (QVEST_PY 환경변수 설정 필요)\n")
    return(invisible(FALSE))
  }
  rc1 <- tryCatch(system2(py, c(shQuote(hv), "--project-dir", shQuote(PROJECT_ROOT)),
                          stdout = FALSE, stderr = FALSE), error = function(e) 1L)
  rc2 <- tryCatch(system2(py, c(shQuote(cl), "--project-dir", shQuote(PROJECT_ROOT)),
                          stdout = FALSE, stderr = FALSE), error = function(e) 1L)
  if (identical(rc1, 0L) && identical(rc2, 0L)) {
    cat("[AlphaSearch] Axiom 파이프라인(harvester+cluster) 갱신 완료\n")
  } else {
    cat(sprintf("[AlphaSearch] WARN: Axiom 파이프라인 실패 (harvester rc=%s / cluster rc=%s) — corpus 갱신 안 됨\n",
                as.character(rc1), as.character(rc2)))
  }
}

# ---- STR 등록 (best-effort, origin=alpha_search) ----
.register_strategy_best_effort <- function(strategy_id, strategy_name, strategy_idea, grade, m) {
  tryCatch({
    reg <- load_registry()
    cfg <- list(family = "alpha_search", origin = "alpha_search",
                idea = strategy_idea, grade = grade,
                cagr = .as_num(m$CAGR), sharpe = .as_num(m$Sharpe))
    reg <- register_strategy(reg, strategy_id, cfg)
    save_registry(reg)
    cat(sprintf("[AlphaSearch] STR 등록: %s (origin=alpha_search)\n", strategy_id))
  }, error = function(e) cat("[AlphaSearch] STR 등록 생략:", conditionMessage(e), "\n"))
}

# ---- PG 편입 "권고"만 (book_state.json은 코드가 쓰지 않음 — 도훈 수동 승인) ----
.recommend_pg_admission <- function(strategy_id, strategy_name, grade, portfolio_id, dry_run = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  rec <- tryCatch({
    pg0 <- pg0_gap_review(portfolio_id)
    bs  <- file.path(PROJECT_ROOT, "book_state.json")
    incumbent <- if (file.exists(bs)) fromJSON(bs, simplifyVector = FALSE) else list(admitted_ids = list())
    pg1_admission_with_book_context(portfolio_id, strategy_id, "core_alpha", pg0, incumbent)
  }, error = function(e) { cat("[AlphaSearch][PG] 권고 산출 실패:", conditionMessage(e), "\n"); NULL })

  decision <- rec$decision %||% "검토필요"
  ddir     <- .as_num(rec$book_delta_ir)
  body <- sprintf("등급 %s 전략의 운용 북 편입 판정: %s. 자동 편입은 하지 않으며, book_state.json 편입은 도훈 수동 승인으로 진행합니다.",
                  grade, decision)
  sections <- list(
    list(type = "summary", emoji = "\U0001F451", body = body),
    list(type = "kv", emoji = "\U2696\UFE0F", heading = "편입 판정",
         kv = list("판정"        = as.character(decision),
                   "북한계기여"  = if (!is.na(ddir)) sprintf("%+.3f", ddir) else "산출불가",
                   "전략식별자"  = strategy_id)),
    list(type = "text", emoji = "\U0001F4CC", heading = "안내",
         body = paste0("본 판정은 권고이며 자동 편입하지 않습니다. ",
                       "운용 북(book_state) 편입은 도훈 수동 승인으로만 진행합니다. ",
                       "백테스트는 PIT(미래참조 금지) 준수로 검증되었습니다."))
  )
  tryCatch(
    tg_agent_brief(agent = "AlphaSearch",
                   title = sprintf("PG 편입 권고 — %s", strategy_name),
                   sections = sections, lock_scope = paste0("pg_", strategy_id),
                   dry_run = dry_run),
    error = function(e) cat("[AlphaSearch][PG-TG] 발송 실패:", conditionMessage(e), "\n"))
}
