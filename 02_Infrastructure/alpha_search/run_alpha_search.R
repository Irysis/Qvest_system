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
                             factor_analysis = deep,   # FF3/FF5/Carhart 알파 + Fama-MacBeth 회귀 (기본 = deep)
                             vol_target = NULL,
                             vol_lookback = 60L,
                             dd_brake = NULL,
                             buffer_zone = NULL,
                             use_default_buffer = TRUE,
                             cov_method = "sample",
                             # ── v9 Lean Loop (2026-08-23) ─────────────────────────────────────────
                             #   deep=FALSE(기본) = lean 라운드: 측정·판정·교훈만 돈다.
                             #   deep=TRUE 는 "지명된 후보"에만 — register_module(3회)·FF3/FF5/FM
                             #   회귀·권위 재측정·improvement_potential 을 추가로 돈다.
                             #   ★신규 인자는 전부 시그니처 **끝**에 붙인다 — 기존 위치인자 호출
                             #   (strategy_name, strategy_idea, factor_engine_path, n_holdings, ...)
                             #   순서를 건드리지 않기 위함.
                             deep = FALSE,
                             source_paper = NULL,              # L-code source_paper 축 (원 논문 식별자/URL)
                             paper_assumption_broken = NULL) { # 논문의 어느 가정이 KR에서 깨졌나(1줄)
  # 로컬 안전 %||% — 외부 source가 전역을 취약버전으로 덮어도 영향 없게 함수 스코프에 고정
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

  # ── (2026-08-22) 단계별 소요 계측 — 도훈 지시 "문제 없이 완성".
  #   왜: 무인 alpha 레인이 timeout 3000s 를 만성 초과하는데(42일 중 7일 exit=124),
  #   단계별 소요가 로그에 없어 **상한을 올릴지 작업량을 쪼갤지** 근거로 못 갈랐다.
  #   ★상한 상향은 증상 은폐다 — 어디서 먹는지 먼저 안다.
  #   에이전트 사고시간과 R 실측시간을 가르는 것이 1차 목적이므로 총소요도 함께 남긴다.
  .AS_T0 <- Sys.time(); .AS_TPREV <- .AS_T0; .AS_STAGES <- list()
  .as_stage <- function(nm) {
    now <- Sys.time()
    dt <- as.numeric(difftime(now, .AS_TPREV, units = "secs"))
    .AS_STAGES[[nm]] <<- round(dt, 2); .AS_TPREV <<- now
    cat(sprintf("[as-timing] %-28s %7.2fs (누적 %7.2fs)
", nm, dt,
                as.numeric(difftime(now, .AS_T0, units = "secs"))))
    invisible(NULL)
  }
  .as_timing_flush <- function(status = "ok") {
    tot <- as.numeric(difftime(Sys.time(), .AS_T0, units = "secs"))
    rec <- list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                strategy = strategy_name, status = status,
                total_secs = round(tot, 2), stages = .AS_STAGES)
    out <- file.path(PROJECT_ROOT, ".cache", "alpha_search_timing.jsonl")
    tryCatch({
      dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
      cat(jsonlite::toJSON(rec, auto_unbox = TRUE), "
", file = out, append = TRUE, sep = "")
    }, error = function(e) NULL)
    cat(sprintf("[as-timing] TOTAL %.2fs (status=%s) -> %s
", tot, status, out))
    invisible(tot)
  }
  on.exit(.as_timing_flush("exit"), add = TRUE)   # 함수 프레임이므로 발화한다(r-portability 금칙② 해당 없음)

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

  .as_stage("00_setup")
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

  .as_stage("sec1_done")
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

  # ---- 2b. 선례 조회 (advisory 1줄 — 차단 아님, v9 Lean Loop) ----
  #   Step 0 lookup 을 "세션이 손으로 돌리는 사전 의무"에서 러너 안 1줄 advisory 로 옮긴다.
  #   ★차단하지 않는다: 조회 실패/인덱스 부재/stale 전부 무시하고 라운드는 계속 간다
  #   (게이트로 만들면 그 순간 라운드가 인프라 수리로 흘러가는 게 이 저장소의 반복 패턴).
  #   auto_rebuild=FALSE — 조회 때문에 인덱스를 재빌드하지 않는다(라운드 예산 보호).
  tryCatch({
    .hi_kw <- tolower(unlist(strsplit(gsub("[^A-Za-z0-9가-힣]+", " ", strategy_name %||% ""), "\\s+")))
    .hi_kw <- .hi_kw[nchar(.hi_kw) >= 3L & !grepl("^(str|as|v[0-9]+|[0-9]+)$", .hi_kw)]
    if (!length(.hi_kw)) {
      .hi_kw <- tolower(unlist(strsplit(gsub("[^A-Za-z0-9가-힣]+", " ", strategy_idea %||% ""), "\\s+")))
      .hi_kw <- .hi_kw[nchar(.hi_kw) >= 3L]
    }
    .hi_kw <- head(unique(.hi_kw), 3L)   # ≤3 토큰 (AND 매칭이라 많이 넣을수록 좁아진다)
    if (length(.hi_kw)) {
      source(file.path(PROJECT_ROOT, "02_Infrastructure", "tools", "hypothesis_index.R"), local = TRUE)
      .hi_hits <- suppressMessages(lookup_hypothesis(.hi_kw, auto_rebuild = FALSE))
      if (is.data.frame(.hi_hits) && nrow(.hi_hits)) {
        .hi_g <- .hi_hits$grade[!is.na(.hi_hits$grade) & nzchar(as.character(.hi_hits$grade))]
        .hi_best <- if (length(.hi_g)) sort(as.character(.hi_g))[1] else "NA"
        cat(sprintf("[hypothesis_index] 선례 %d건 — 최고 %s · 최근 %s · 예) %s (advisory)\n",
                    nrow(.hi_hits), .hi_best,
                    as.character(.hi_hits$date[1] %||% "?"),
                    .clip_msg(.hi_hits$title[1] %||% "?", 60L)))
      } else {
        cat(sprintf("[hypothesis_index] 선례 0건 (키워드: %s) — 신규 축 (advisory)\n",
                    paste(.hi_kw, collapse = " ")))
      }
    }
  }, error = function(e)
    cat("[hypothesis_index] 조회 생략(비치명):", conditionMessage(e), "\n"))

  .as_stage("sec2_done")
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

  .as_stage("sec3_done")
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

  .as_stage("sec4_done")
  if (!isTRUE(deep))
    cat("[AlphaSearch] lean 모드(deep=FALSE): 팩터회귀(FF3/FF5/FM)·권위재측정·improvement_potential 생략 | 6c proxy 등재는 수행(module_quarantine, v9.1 S2c)\n")

  # ---- 4b. 후보 보존(register_module) — 계약 미충족분은 quarantine ---- [deep 전용]
  #   v8.1 hardening: PIT-clean 백테는 연구 후보로 보존하되, FR canonical pool은
  #   authoritative 재측정(contract_pass+backtested+frozen+hash) 성공분만 허용한다.
  #   따라서 이 early call은 통상 module_quarantine에 저장된다.
  #   ★v9.1(2026-08-23): lean 라운드의 등재는 **6c 한 곳으로 모은다.** 여기(4b, 등급 이전)와
  #   6e(권위 재측정)는 deep 전용 그대로다 — 등급 없는 조기 등재는 소비자가 쓸 수 없고
  #   (screen_route 도 grade 도 아직 없다) 같은 id 를 한 라운드에 두 번 쓰는 낭비다.
  if (isTRUE(deep) && isTRUE(pit_clean)) tryCatch({
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

  .as_stage("sec4b_done")
  # ---- 5. Charts: equity_curve.png + annual_returns.png (vs BM) ----
  #   차트 생성이 실패(예 그래픽 디바이스 이슈)해도 register/측정/등재는 이미 완료 — 전체 run 중단 방지.
  tryCatch(
    generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name),
    error = function(e) cat("[AlphaSearch] generate_charts 생략:", conditionMessage(e), "\n"))
  equity_png <- file.path(OUT_DIR, "equity_curve.png")
  annual_png <- file.path(OUT_DIR, "annual_returns.png")
  charts <- Filter(file.exists, c(equity_png, annual_png))

  .as_stage("sec5_done")
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
  # ★[2026-08-23 v9.1 / S2c] screening 을 여기로 끌어올린다(구 위치 = 6d, 6c 뒤).
  #   6c 의 lean register_module 이 `screen_route`·`screen_pass`·`structural_dd` 를 meta 에
  #   실어야 하는데, 구 배치에서는 그 시점에 아직 정의되지 않은 이름이었다.
  screening <- hg$verdict$screening %||% list()
  m      <- hg$verdict$metrics %||% list()
  sdef   <- hg$verdict$statistical_defense %||% list()
  perf_bm <- tryCatch(summarise_perf(sim$bm_xts, "KOSPI200"), error = function(e) NULL)
  bm_cagr_pct <- if (!is.null(perf_bm)) .as_num(perf_bm$CAGR) else NA_real_  # summarise_perf CAGR은 이미 percent(round(ann*100,2))
  excess_cagr <- round(.as_num(m$CAGR) - bm_cagr_pct, 2)

  pass    <- grade %in% c("A", "A_NOVEL", "A_DEF")
  is_fail <- grade %in% c("F")
  # notable 조임 (v9 Lean Loop): "clean PIT F등급" 전량이 아니라 **탈락축이 실제로 잡힌** F만
  #   교훈으로 적립한다. FMT 판정도 fail_reasons 도 없는 F 는 "왜 안 됐나"를 못 쓰므로
  #   L-code 로 남겨봐야 숫자만 남는다(형해화). fmt_hits 는 이 줄 아래에서 산출되므로
  #   판정 후 재계산한다 — 아래 6a-2 참조.
  notable <- grade %in% c("B", "C")

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

  # notable 최종 판정 — 탈락축이 실제로 잡힌 clean-PIT 실패만 "의미있는 실패"
  .fail_reasons_now <- tryCatch(unlist(hg$verdict$fail_reasons), error = function(e) character(0))
  notable <- notable ||
    (is_fail && pit_clean && (length(fmt_hits) > 0L || length(.fail_reasons_now) > 0L))
  cat(sprintf("[AlphaSearch] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s deep=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable, isTRUE(deep)))

  .as_stage("sec6_done")
  # ---- 6c. 후보 등재(quarantine) — ★lean 라운드도 등재한다 (2026-08-23 v9.1 / S2c, E-4) ----
  #   왜 열었나(실측): v9 lean 첫날 13라운드의 module_catalog 등재가 **0건**이었다
  #   (register_module 3곳이 전부 `deep` 뒤). 그래서 리서치 층이 만든 재료가 결합 층
  #   (오버레이·팩터 로테이션)에 **도달하지 못했다** — 만들고 안 부르는 계통 그대로.
  #   ★그런데 FR 입력면은 오염시키지 않는다: `metric_type="proxy"` 를 **명시**하면
  #   register_module.R:133-142 의 계약 floor(`metric_type=="backtested"` 요구)가 걸려
  #   `fr_eligible=FALSE` → **module_quarantine.json** 으로 간다. module_catalog 에는
  #   들어가지 않고, build_module_performance.R:63-67 필터는 한 줄도 건드리지 않는다.
  #   무오염이 규칙이 아니라 **계약**으로 보장된다는 뜻이다.
  #   소비자는 이미 있다 — overlay_candidate_queue.R:65-87 이 quarantine 을 스캔해
  #   `mod$meta$screen_route` 를 읽는다("현재 0건, 배관 선설치" 주석).
  #   kill switch: QVEST_LEAN_REGISTER=0.
  if (isTRUE(pit_clean) && !identical(Sys.getenv("QVEST_LEAN_REGISTER", "1"), "0")) tryCatch({
    if (!exists("register_module", mode = "function"))
      source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_,
                    metric_type = "proxy",   # ★기본값 의존 금지 — grep 가능해야 한다
                    meta = list(strategy_idea = strategy_idea,
                                strategy_name = strategy_name,   # ★backfill_lean_modules.R::bl_meta 와 키 동형
                                score = score,
                                lean = !isTRUE(deep),
                                grade_basis = "proxy_diagnostic",
                                screen_route = screening$screen_route %||% "NONE",
                                screen_pass = isTRUE(screening$screen_pass),
                                structural_dd = isTRUE(screening$structural_dd),
                                f_grade_reasons = f_grade_reasons,
                                fmt_codes = vapply(fmt_hits, function(x) x$code, ""),
                                bt_result_path = .rel_project_path(bt_contract$bt_result_path %||% file.path(OUT_DIR, "bt_result.rds")),
                                bt_contract_status = bt_contract$status %||% "UNKNOWN"))
    assign("%||%", `%||%`, envir = globalenv())   # register_module source 후 전역 %||% 복원
  }, error = function(e) cat("[AlphaSearch] register_module(grade 갱신) 생략:", conditionMessage(e), "\n"))

  .as_stage("sec6c_done")
  # ---- 6b. 팩터 회귀 분석 (FF3/FF5/Carhart 알파 + Fama-MacBeth) ---- [deep 전용]
  #   ★게이트는 factor_analysis 이고 그 **기본값이 deep** 이다(시그니처 lazy default).
  #   ⇒ lean 라운드는 자동으로 생략(R 시간의 ~25% 회수), 기존 호출자가 명시한
  #   factor_analysis=TRUE 는 deep 과 무관하게 그대로 존중된다(back-compat).
  analysis_ran <- FALSE
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({
      run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir = OUT_DIR, strategy_name = strategy_name)
      assign("%||%", `%||%`, envir = globalenv())   # run_analysis 내부 source 오염 복원
      analysis_ran <- TRUE   # tryCatch expr 는 호출자 프레임에서 평가되므로 `<-` 가 지역 갱신
    }, error = function(e) cat("[AlphaSearch] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  # ---- 6b-2. analysis_report.md FMT 체크리스트 자동 체크 ([x] + 사유) ----
  #   run_analysis가 생성한 보고서의 "Failure Mode Diagnosis" 빈 체크박스를 6a-2 판정으로 채움.
  #   분석이 안 돌았으면 보고서 자체가 없다 — 없는 파일에 "부재 WARN"을 찍지 않는다(거짓 경보 방지).
  if (isTRUE(analysis_ran)) .patch_fmt_checklist(OUT_DIR, fmt_hits)

  .as_stage("sec6b_done")
  # ---- 6d. ★ 권위측정 사다리: hurdle B 이상 또는 screening_pass → 계약 실측 재측정 ---- [deep 전용]
  #   v8.1 트랙C(measurement-graduation §1~§3): proxy(run_hurdle_gate) 등급이 B 이상이거나,
  #   MDD/turnover 같은 구조 사유로 C/F가 됐어도 screen_pass면 authoritative 재측정.
  #   → OUT_DIR/bt_result.rds + authoritative_remeasure.json (essence grade / PORT_t NW lag-3 / metric_type=backtested).
  #   ★v9: 권위 재측정은 **자본 층 입구**의 일이다 — lean 라운드는 proxy 허들 등급까지만 낸다.
  #   (lean 에서도 bt_result 계약은 4장에서 이미 저장되므로 지명 시 그 산출물로 재측정 가능)
  auth <- NULL
  # (screening 은 6장 앞머리에서 이미 산출 — 6c 의 lean register_module 이 소비한다)
  screen_remeasure <- isTRUE(screening$screen_pass) &&
    grepl("OVERLAY_CANDIDATE|FR_RCMA|DPL_FEATURE|TURNOVER_REVIEW", screening$screen_route %||% "")
  # v8.3(2026-07-10): DPL_FEATURE 발급 중단(hurdle_gate) — 고회전 케이스는 TURNOVER_REVIEW로 대체.
  #   DPL_FEATURE 패턴은 기존 manifest 호환 위해 잔존. FR_RCMA는 이제 조건부(회전율 hard-fail 이내)만.
  if (isTRUE(deep)) {
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

  .as_stage("sec6d_done")
  # ---- 6d+. Layer 1 개선-여지 평가 자동 첨부 (2026-08-16 L1 자동 스폰 — 도훈 승인) ----
  #   ★v9.2 §8-S2 [7] 진입 재료 개방 (2026-08-24): 구 조건 `isTRUE(deep) && screen_pass` 는
  #   **평가기가 요구하지 않는 입력**을 관문으로 삼고 있었다. improvement_potential_entry()
  #   (regime/improvement_potential.R:113-118)가 실제로 요구하는 것은 `bt_result.rds` 하나뿐이고
  #   deep·screen_pass 는 그 입력과 무관한 **하류 라벨**이다. 그 결과 2026-08-23 lean 17런에서
  #   ip 산출이 0건이었고, 강화 사다리(reinforce_ladder.R)의 진입 재료가 통째로 비어 있었다.
  #   ⇒ 조건을 "평가기의 실입력이 존재하는가"로 교체한다.
  #   ★deep 조건은 6d(권위 재측정)·6e(register_module)에서는 그대로 둔다 — 그 둘은 실제로
  #     deep 라운드의 비용/의미에 묶여 있다(여기만 입력-기준으로 되돌린다).
  #   비치명: 평가 실패는 정직 WARN — 본 러너 산출물은 불변.
  if (identical(bt_contract$status %||% "", "OK")) tryCatch({
    if (!exists("improvement_potential_for_run", mode = "function")) {
      Sys.setenv(QVEST_IP_NORUN = "1")
      source(file.path(PROJECT_ROOT, "02_Infrastructure", "regime", "improvement_potential.R"))
    }
    improvement_potential_for_run(OUT_DIR)
  }, error = function(e)
    cat(sprintf("[AlphaSearch][WARN] improvement_potential 평가 실패 (비치명): %s\n",
                conditionMessage(e))))

  .as_stage("sec6d_done_2")
  # ---- 6e. FR-eligible 승격: 권위측정 OK일 때만 canonical module_catalog로 등록 ---- [deep 전용]
  #   ★L434 수정 (v9, 플랜 §1.1): catalog grade 는 **리서치 허들 등급**이다.
  #   구 `grade = auth$essence_grade %||% grade` 는 자본-보정 essence 등급으로 허들 A를
  #   덮어써서 "역대 A등급 모듈 0"을 만들었다(meta.proxy_grade 에는 A 6·A_DEF 5건 잔존).
  #   두 등급은 서로 다른 층의 판정이므로 각각의 필드에 각각 기록한다 —
  #   grade=허들(리서치 층) / meta$essence_grade=자본 층 / meta$proxy_grade=허들(호환 유지).
  if (isTRUE(deep) && !is.null(auth) && identical(auth$status, "OK")) tryCatch({
    if (!exists("register_module", mode = "function"))
      source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "register_module.R"))
    register_module(
      sim, strategy_id,
      grade = grade,
      origin_mode = "alpha_search",
      role = NA_character_,
      meta = list(strategy_idea = strategy_idea, score = score,
                  selection_type = "chain",
                  chain_qualification = .chain_qualification_record(),  # §3 chain 자격요건 기록 (추가 필드)
                  proxy_grade = grade,
                  essence_grade = auth$essence_grade %||% NA_character_,  # 자본 층 등급(별도 필드 — grade 를 덮지 않는다)
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

  .as_stage("sec6e_done")
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
        #   ★분석이 실제로 돈 경우에만 — lean 라운드는 산출물이 없으므로 발송 자체가 없다(텔레그램 1회).
        if (isTRUE(analysis_ran) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis")) {
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

  .as_stage("sec7_done")
  # ---- 8. L-code 적립 (PASS + 의미있는 실패만, 모드별 디렉터리) ----
  l_code_path <- NULL
  if (pass || notable) {
    l_code_path <- .write_lcode(strategy_id, strategy_name, strategy_idea, grade,
                                m, excess_cagr, pass, is_fail,
                                hg = hg, fmt = fmt_hits, auth = auth,
                                source_paper = source_paper,
                                paper_assumption_broken = paper_assumption_broken)
    .run_axiom_pipeline()   # harvester + cluster (자가발전, 비동기 spawn)
  }

  .as_stage("sec8_done")
  # ---- 9. Grade A → STR 등록 + PG 편입 "권고"(book_state는 수동) ----
  if (pass) {
    .register_strategy_best_effort(strategy_id, strategy_name, strategy_idea, grade, m)
    if (isTRUE(send_telegram))
      .with_alpha_search_tg_lock(strategy_id, {
        .recommend_pg_admission(strategy_id, strategy_name, grade, portfolio_id, dry_run = tg_dry_run)
      })
  }

  # ---- 10. 스크리닝 큐 리프레시 (동기 · 실패해도 라운드에 영향 없음) ----
  #   6c 가 방금 quarantine 에 넣은 재료를 overlay/standalone/auto_spawn 큐가 집어가게 한다.
  #   ★2026-08-23 실측 수리: 구판은 `wait=FALSE` 였는데 **한 번도 실행되지 않았다**.
  #     이 블록은 `invisible(list(...))` 직전이라 부모 R 이 곧바로 종료하고, Windows 에서는
  #     그 순간 자식이 시작도 못 하고 죽는다(로그 파일이 0바이트로 생성된 것이 그 증거 —
  #     리다이렉트는 걸렸는데 출력이 0). 검증 실런에서 큐 나이가 1687분 그대로였다.
  #     ⇒ 동기 호출 + timeout. 실측 소요 21초로 라운드 예산(<=40분)의 0.9% 라 무해하고,
  #       무엇보다 **실패가 로그에 보인다** — 조용한 미실행이 이 저장소의 반복 결함이다.
  #   스크립트 부재 시에는 조용히 넘어간다(tryCatch NULL). 중단 = QVEST_SCREEN_QUEUE_NORUN=1.
  tryCatch({
    .qsc <- file.path(PROJECT_ROOT, "02_Infrastructure/ops/refresh_screen_queues.R")
    if (file.exists(.qsc)) {
      qlog <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", "refresh_screen_queues.log")
      .qrc <- system2(Sys.which("Rscript"), c("--no-save", shQuote(.qsc), "--if-stale", "10"),
                      stdout = qlog, stderr = qlog, wait = TRUE, timeout = 180)
      cat(sprintf("[AlphaSearch] 스크리닝 큐 리프레시 rc=%s (로그: %s)\n",
                  as.character(.qrc), .rel_project_path(qlog)))
    }
  }, error = function(e) cat("[AlphaSearch] 큐 리프레시 생략:", conditionMessage(e), "\n"))

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
    # ★[2026-08-23 v9.1] `hard_fail=FALSE` 인데 `fail_reasons` 가 남는 **새 상태**.
    #   MDD 가 탈락 권한을 잃었으므로(E-2) 같은 문자열이 "게이트가 막았다"일 수도,
    #   "구조 진단만 남았다"일 수도 있다. 라벨을 조건화하지 않으면 읽는 사람이
    #   탈락 사유와 진단을 구분하지 못한다.
    items <- c(items, sprintf("%s: %s",
                              if (isTRUE(v$hard_fail)) "게이트 사유" else "구조 진단(탈락 아님)",
                              .clip_msg(paste(fr, collapse = " | "), 165L)))
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
    # "탈락"이 아니라 "부담"이다 — 리서치 층에서 MDD 는 결합 층으로 보내는 주소지 판정이 아니다.
    items <- c(items, sprintf("낙폭 부담(오버레이 대상): 최대낙폭 %.1f%%", mdd))
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

# ---- chain 자격요건 기록 (measurement-graduation §3 — selection_type="chain" 하드코딩 근거) ----
#   run_alpha_search 1회 호출 = 1가설 1전략 단일 실행 (열거집합 argmax/threshold-pick 없음 = sweep 아님).
#   §3 chain 요건 ①(iteration별 변경사유 1줄) ②(IS-only 변형선택) ③(holdout 최종 1회)은
#   반복 체인(호출 반복) 레벨 규약 — 단일 실행 스크립트는 ②③을 스스로 검증할 수 없으므로
#   구조적 사실만 정직 기록하고 cross-run 준수 책임을 호출자(리서치 세션)로 명시한다.
#   기존 출력 스키마를 깨뜨리지 않는 추가 필드 (MC-04 수리 2026-07-03).
.chain_qualification_record <- function() {
  list(
    selection_operator      = "none_single_run",            # 단일 실행 — sweep 선택 연산자 부재
    iteration_reason_logged = TRUE,                          # L-code mechanism_hypothesis/next_probe에 변경사유 기록
    is_only_selection       = "not_applicable_single_run",   # 실행 내 변형선택 없음 — cross-run IS-only 규약은 호출자 책임
    holdout_single_view     = "not_queried_by_this_script",  # 본 스크립트는 holdout 미조회
    note = paste0("run_alpha_search 1회=1가설 1전략 단일 실행(sweep 아님). ",
                  "반복 개선 체인의 IS-only 변형선택·holdout 1회 규약 준수는 호출자 책임 ",
                  "(measurement-graduation §3 chain 자격요건 — 미충족 시 sweep 재분류 대상).")
  )
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
      chain_qualification = .chain_qualification_record(),  # §3 chain 자격요건 기록 (추가 필드)
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
                         hg = NULL, fmt = NULL, auth = NULL,
                         source_paper = NULL,
                         paper_assumption_broken = NULL) {
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
  # ── [2026-08-23 v9.1 / S2b] 논문 가정 충돌을 **1급 축**으로 승격하기 위한 선행 판정.
  #   fmt_axis(아래)·lesson_reason·mechanism_hypothesis 세 곳이 같은 값을 봐야 하므로
  #   여기서 한 번만 계산한다.
  paper_gap_txt <- trimws(as.character(paper_assumption_broken %||% ""))
  has_paper_gap <- nzchar(paper_gap_txt) && !identical(paper_gap_txt, "미기재")
  # FMT-01/04(MDD 축)는 KR 롱온리에서 상수라 **선두에서 내린다** — 14/14 발화한 축이
  #   교훈 문장의 첫머리를 차지하면 모든 라운드의 교훈이 같은 문장이 된다.
  .fmt_lead <- Filter(function(x) !((x$code %||% "") %in% c("FMT-01", "FMT-04")), fmt)
  .fmt_tail <- Filter(function(x)  ((x$code %||% "") %in% c("FMT-01", "FMT-04")), fmt)
  .fmt_ord  <- c(.fmt_lead, .fmt_tail)

  # ---- lesson_text 꼬리 = 숫자 나열이 아니라 **사유 + 논문 가정 대비** (v9 Lean Loop) ----
  #   구판 꼬리("통과 — PG 편입 권고." / "명확한 실패 패턴 — 역방향 가설 탐색 후보.")는
  #   등급에서 기계적으로 파생되는 상수라 교훈이 없다. 축(FMT/fail_reasons)과 논문 가정을 적는다.
  lesson_reason <- if (has_paper_gap) {
    # 논문 가정 충돌이 있으면 그것이 **지배 사유**다 — 그 뒤에 측정된 축을 잇는다.
    .rest <- if (length(.fmt_ord)) {
      paste(vapply(.fmt_ord, function(x) sprintf("%s %s", x$code %||% "FMT", x$reason %||% ""), ""), collapse = "; ")
    } else if (length(fail_reasons)) {
      paste(fail_reasons, collapse = "; ")
    } else ""
    sprintf("논문 가정 충돌: %s%s", paper_gap_txt,
            if (nzchar(.rest)) sprintf(" | 측정된 축: %s", .rest) else "")
  } else if (length(.fmt_ord)) {
    paste(vapply(.fmt_ord, function(x) sprintf("%s %s", x$code %||% "FMT", x$reason %||% ""), ""), collapse = "; ")
  } else if (length(fail_reasons)) {
    paste(fail_reasons, collapse = "; ")
  } else if (pass) {
    sprintf("허들 통과 (종합 %.0f점, 초과CAGR %+.1f%%p)", .as_num(hg$score), excess_cagr %||% 0)
  } else {
    sprintf("탈락축 미기록 — 종합 %.0f점 미달(신호 약함)", .as_num(hg$score))
  }
  paper_gap <- if (has_paper_gap) paper_gap_txt else "미기재"
  lesson <- sprintf("%s: 등급 %s, 연복리 %.1f%% (벤치마크 대비 %+.1f%%p), 샤프 %.2f, 최대낙폭 %.1f%%. 사유: %s; 논문 가정 대비: %s",
                    strategy_name, grade, .as_num(m$CAGR), excess_cagr %||% 0, .as_num(m$Sharpe),
                    -abs(.as_num(m$MDD)), .clip_msg(lesson_reason, 220L), .clip_msg(paper_gap, 120L))
  if (auth_ok)
    lesson <- sprintf("%s [실측재측정: essence %s, PORT_t(NW) %s, metric_type=backtested]",
                      lesson, auth$essence_grade %||% "?",
                      ifelse(is.na(.as_num(auth$essence$portfolio_alpha_t_nw_lag3)), "NA",
                             sprintf("%.2f", .as_num(auth$essence$portfolio_alpha_t_nw_lag3))))

  # ---- 학습 3필드 (의무, v8.1 트랙D — 형해화 해소: 탈락축/실측수치 기반 구체 문장) ----
  # mechanism_hypothesis: 전략 아이디어 + 판정된 실패축(FMT/fail_reasons)에서 구성. 보일러플레이트 금지.
  axis_txt <- if (has_paper_gap) {
    # 논문 가정이 깨진 지점이 **기전 가설의 출발점**이다 — "KR 에서 이 가정이 성립하지
    #   않는다"는 것이 검증이 실제로 알아낸 것이고, MDD 상수는 그 뒤에 온다.
    .rest2 <- if (length(.fmt_ord)) {
      paste(vapply(.fmt_ord, function(x) sprintf("%s(%s)", x$code, x$reason), ""), collapse = "; ")
    } else if (length(fail_reasons)) {
      paste(fail_reasons, collapse = "; ")
    } else ""
    sprintf("논문 가정 충돌(%s)%s", paper_gap_txt,
            if (nzchar(.rest2)) sprintf(" + %s", .rest2) else "")
  } else if (length(.fmt_ord)) {
    paste(vapply(.fmt_ord, function(x) sprintf("%s(%s)", x$code, x$reason), ""), collapse = "; ")
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
  # ---- 연속성 계약의 유일한 집 (v9 Lean Loop, 2026-08-23) ----------------------
  #   구판: 단일 문자열 next_probe 1개. → Stop 훅이 매 턴 "계속 산출물"을 강요하던 구조를
  #   **L-code 발행 시점 1곳**으로 옮긴다. 여기가 계약이 걸리는 유일한 지점이다.
  #   계약 = ①next_probes 2건 이상(축별 표에서 자동 생성) ②live_trigger(부활 조건, C/F만).
  #   ★차단하지 않는다 — 미충족이면 WARN 후 그대로 발행한다(정직 원장 우선).
  #   표 = {분기 조건 → probe① 기존 분기문 / probe② 축별 대안 / live_trigger 부활조건}.
  # ── [2026-08-23 v9.1 / S2b] probe 축 재설계: PAPER_GAP 1급 · FMT-01/04 최하위 ───
  #   실측 사유: v9 lean 첫날 L-code 14건 중 **FMT-01 이 14/14 발화**했다(FMT-04 는 9/14).
  #   구 우선순위는 FMT-01/04 를 2순위에 뒀으므로 14건 **전부** 같은 축으로 판정됐고,
  #   next_probes 가 "MDD 축 탈락 → 오버레이" 한 문장으로 붕괴했다(Grade B 라운드 포함).
  #   상수는 축이 아니다 — 전부에 발화하는 판정은 아무것도 구분하지 못한다.
  #   ⇒ ①MDD 축은 최하위로 내리고 ②그 자리에 **논문 가정 충돌(PAPER_GAP)** 을 놓는다.
  #     PAPER_GAP 은 라운드마다 다르고(종목수 절단·유니버스 치환·비중방법 대체),
  #     KR 데이터에서 직접 재볼 수 있는 **구성 변경**으로 곧장 번역되는 축이다.
  #   예상 분포(오늘 14건 기준): PAPER_GAP 10 · FMT-07 2 · FMT-02 1 · FMT-01/04 1.
  #   (`paper_gap_txt`·`has_paper_gap` 은 위 lesson_reason 블록에서 이미 산출됐다)
  fmt_axis <- if (pass) "PASS"
              else if (has_paper_gap) "PAPER_GAP"
              else if ("FMT-05" %in% fmt_codes) "FMT-05"
              else if ("FMT-02" %in% fmt_codes) "FMT-02"
              else if ("FMT-07" %in% fmt_codes) "FMT-07"
              else if ("FMT-08" %in% fmt_codes) "FMT-08"
              else if ("FMT-03" %in% fmt_codes) "FMT-03"
              else if (any(c("FMT-01", "FMT-04") %in% fmt_codes)) "FMT-01/04"
              else if (is_fail) "FAIL_DEFAULT"
              else "NEAR_MISS"

  probe1 <- switch(fmt_axis,
    "PASS"        = "QEPM 정밀검증(WorkTask) 이행 + Grade-A 풀 직교성(GradeA_Corr)·book-marginal ΔIR>=0.05 확인.",
    # ★1급 축. 파라미터 튜닝이 아니라 **구성 변경 1건**을 지시한다 — 논문이 가정한 것과
    #   KR 배포 형태가 갈린 그 지점을 데이터에서 직접 재는 것이 이 라운드의 다음 수다.
    "PAPER_GAP"   = sprintf(paste0("논문 가정 충돌 '%s' 을 KR 데이터에서 직접 측정 — ",
                                   "충돌 축을 되돌린 **구성 변경 1건**(파라미터 조정 아님: 종목수 절단 전 N 복원 / ",
                                   "논문 유니버스 근사 / 논문 비중방법 복원 중 해당 1건)으로 재검증하고 ",
                                   "기여를 분리한다."),
                            .clip_msg(paper_gap_txt, 120L)),
    "FMT-05"      = sprintf("회전율 축 탈락(연 %.0f%%) — 리밸 주기 연장(월->분기)·buffer_zone 확대·신호 지속성 측정 후 재검증.", .as_num(m$Turnover_Ann)),
    "FMT-01/04"   = sprintf(paste0("MDD 축 진단(%.1f%%) — **리서치 층 탈락 아님**(도훈 결정 E-2). ",
                                   "OVERLAY_CANDIDATE 라우트로 오버레이/국면 결합에서 소비하고, ",
                                   "그 결합에서 실제로 낙폭이 내려가는지를 잰다."), abs(.as_num(m$MDD))),
    "FMT-02"      = "방향 역작동 의심 — kr-inverse-pattern-miner로 역방향 가설 생성 + long-short/multi-sleeve 구성 변경 탐색.",
    "FMT-07"      = "후반부 알파 붕괴 — 2017 전후 서브기간 분해 + 최근 5Y 한정 재검증으로 소멸 여부 확정.",
    "FMT-08"      = "게이팅 과적합 의심 — 게이트 임계 완화/제거 대조 실험으로 회복랠리 기여 분리.",
    "FMT-03"      = "앙상블 희석 의심 — 구성 팩터 단독 성과 분해 후 강한 축 단독/가중 재설계.",
    "FAIL_DEFAULT"= sprintf("탈락 사유(%s) 직접 해소 변형 1건 검증.",
                            if (length(fail_reasons)) .clip_msg(paste(fail_reasons, collapse = "; "), 150L) else "점수 미달"),
    "NEAR_MISS"   = sprintf("근접 탈락(종합 %.0f점) — 최약 축 보강(파라미터 아닌 구성 변경) 후 1회 재검증. 반복 sweep 시 n_trials 누적 신고.", .as_num(hg$score)))

  probe2 <- switch(fmt_axis,
    "PASS"        = "지명 후 deep=TRUE 재실행으로 권위 재측정(PORT_t·oos_retention·calmar) 산출.",
    # 대조군: 논문 **원 사양** 복제팔. 충돌 축을 되돌린 팔과 나란히 재야 "고정 축이 죽인 것"과
    #   "KR 에서 원래 안 되는 것"이 구분된다 — 한 팔만 돌리면 둘이 같은 결과로 보인다.
    "PAPER_GAP"   = "논문 원 사양 복제팔(고정 축 충돌분만 되돌린 대조군) 1건을 나란히 측정해 격차를 귀속.",
    "FMT-05"      = "신호 지속성 측정 후 보유기간 재설계.",
    "FMT-01/04"   = "오버레이/국면 결합 후 dMDD 측정(단독 재설계 아님 — MDD 는 결합 층에서 푼다).",
    "FMT-02"      = "multi-sleeve 구성 변경.",
    "FMT-07"      = "최근 5Y 한정 재검증.",
    "FMT-08"      = "게이트 제거 대조.",
    "FMT-03"      = "강한 축 단독 재설계.",
    "FAIL_DEFAULT"= "역방향 가설(kr-inverse-pattern-miner) 1건.",
    "NEAR_MISS"   = "논문 원 유니버스 대비 KR 치환 축 점검.")

  live_trigger <- switch(fmt_axis,
    "PASS"        = NA_character_,   # 통과 라운드는 부활 조건이 없다(이미 살아 있음)
    # ★PAPER_GAP arm 누락 금지 — 빠지면 무명 default 로 떨어져 상수 문장이 나온다.
    "PAPER_GAP"   = "논문 가정 축을 복원한 구성에서 IR>0 ∧ score>=25 회복 시",
    "FMT-05"      = "회전율<600% 변형이 SR 유지 시",
    "FMT-01/04"   = "오버레이/국면 결합에서 dMDD<=-3pp ∧ IR 비열위 시",  # MDD 축 공통(FMT-01·04 동일 분기)
    "hard_fail 축 해소 후 score>=25 회복 시")

  next_probes <- unique(c(probe1, probe2))
  next_probes <- next_probes[nzchar(next_probes)]
  # ★[2026-08-23 v9.1] `paper_assumption_broken` 미기재 = PAPER_GAP 축이 발화하지 않는다는 뜻이고,
  #   그러면 probe 축이 FMT 상수(KR 롱온리에서 MDD>45%는 14/14 발화)로 떨어진다.
  #   차단하지 않는다 — 기존 WARN 규약(정직 원장 우선) 전례를 따른다.
  if (!pass && !has_paper_gap)
    cat(sprintf("[L-CODE WARN] %s: paper_assumption_broken 미기재 — probe 축이 진단 상수로 떨어진다 (axis=%s)\n",
                strategy_id, fmt_axis))
  if (!pass && (length(next_probes) < 2L || is.na(live_trigger)))
    cat(sprintf("[L-CODE WARN] continuity contract 미충족 (%s: next_probes=%d, live_trigger=%s) — 그대로 발행\n",
                strategy_id, length(next_probes),
                if (is.na(live_trigger)) "NA" else "ok"))
  next_probe <- paste(next_probes, collapse = " | ")   # 구 소비자(단일 문자열) 호환

  # ---- falsification_attempts (r7 Falsification 축 — AXM-01 공급측 배선, 2026-07-03) ----
  #   이미 산출된 반증형 검증 결과의 전달만 (신규 계산 금지). placebo/lag-stress는 현
  #   alpha_search 파이프라인 미산출 — 미산출 값은 기재하지 않는다 (가짜 데이터 생성 금지,
  #   cluster_extractor._draft_falsification이 실기록만 집계). 형식: 문자열 list.
  sdef_lc <- tryCatch(hg$verdict$statistical_defense, error = function(e) NULL) %||% list()
  # [2026-07-04 G-mode-wiring] 구조체 형식 전환: character 벡터 → [{test, result, effect_retained}].
  #   promote.R .axis_falsification 소비 규약 정합 (2026-07-17 A2 정정): result = SOT
  #   axiom-engine.md §3d 정규 토큰 {survived, falsified, weakened} — promote는
  #   .fals_norm_result 정규화 소비(미상 토큰 = falsified 취급 보수, INV-4).
  #   'diagnostic'은 게이트-비적용 진단 산출(DSR 등)로 정규화에서 중립 처리 — 서술은
  #   detail 필드에 분리. survived는 effect_retained 수치 필수(비수치 = retained-pass
  #   불인정 보수 FALSE), effect_retained = 효과 잔존 비율 실값(결측 시 NA — 수치 창작
  #   금지). 그 외 기배선 유지.
  .fals_entry <- function(test, result, effect_retained = NA_real_, detail = "")
    list(test = test, result = result, effect_retained = effect_retained, detail = detail)
  fals <- list()
  # ★삭제 (v9, 2026-08-23): "PIT 정적스캔 survived 1.0" 항목 제거.
  #   detect_lookahead 위반 시 run 자체가 중단되므로 이 항목은 **모든 L-code에 100% 등장하는
  #   상수**였다 — 판별력 0인데 Falsification 축 카운트만 1 올려 "반증을 시도했다"로 읽혔다
  #   (효과 잔존 1.0 은 성과 수치도 아니다). PIT 통과 사실은 manifest.pit 에 이미 있다.
  dsr_lc <- .as_num(sdef_lc$dsr)
  if (is.finite(dsr_lc))
    fals[[length(fals) + 1L]] <- .fals_entry(
      "DSR(다중검정 반증)", "diagnostic", NA_real_,
      sprintf("DSR %.3f, significant=%s, n_trials=%s — chain은 게이트 부적용(진단 산출)",
              dsr_lc, isTRUE(sdef_lc$dsr_significant), as.character(sdef_lc$n_trials %||% NA)))
  if (is.finite(oos_retention))
    fals[[length(fals) + 1L]] <- .fals_entry(
      "IS65/OOS35 활성SR retention (hurdle D062, proxy) — 과적합 반증 시도",
      # §3 하한 0.5(<0.5 무조건 FAIL) 기준 판정 — promote.R fals_min_retained 0.5와 동일 규약 (창작 아님)
      if (oos_retention >= 0.5) "survived" else "falsified",
      round(oos_retention, 3),
      sprintf("retention %.2f (measurement-graduation §3 하한 0.5 기준)", oos_retention))
  f7 <- Filter(function(x) identical(x$code %||% "", "FMT-07"), fmt)
  if (length(f7))
    fals[[length(fals) + 1L]] <- .fals_entry(
      "서브기간 분해(pre/post-2017)", "falsified", NA_real_,
      sprintf("후반부 알파 붕괴: %s", .clip_msg(f7[[1]]$reason %||% "", 150L)))
  if (auth_ok) {
    a_oos <- .as_num(auth$essence$oos_retention)
    a_dsr <- .as_num(auth$essence$dsr)
    a_hf  <- isTRUE(any(as.logical(unlist(auth$hard_fail %||% list())), na.rm = TRUE))
    fals[[length(fals) + 1L]] <- .fals_entry(
      "계약 실측 재검(essence v2, backtested)",
      if (a_hf) "falsified" else if (is.finite(a_oos)) "survived" else "diagnostic",
      if (is.finite(a_oos)) round(a_oos, 3) else NA_real_,
      sprintf("oos_retention %s / DSR %s / hard_fail=%s",
              ifelse(is.finite(a_oos), sprintf("%.2f", a_oos), "NA"),
              ifelse(is.finite(a_dsr), sprintf("%.2f", a_dsr), "NA"),
              paste(as.character(auth$hard_fail %||% "NA"), collapse = ",")))
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
    lcode_schema_version = if (exists("LCODE_SCHEMA_VERSION")) LCODE_SCHEMA_VERSION else 2L,  # [2026-07-17 A3] v2 태깅 (07-09 배치 5건 sv 결측 봉합)
    cagr_pct          = .as_num(m$CAGR),
    sharpe            = .as_num(m$Sharpe),
    mdd_pct           = abs(.as_num(m$MDD)),
    excess_cagr       = excess_cagr %||% NA_real_,
    # ---- 학습 3필드 (v8.1 트랙D 의무) + FMT + OOS ----
    mechanism_hypothesis      = mechanism_hypothesis,   # r7 Mechanism 축 입력
    data_supported_conclusion = data_supported_conclusion,
    # ---- 연속성 계약 (v9): 리스트가 정본, 문자열은 구 소비자 호환 사본 ----
    next_probes               = as.list(next_probes),   # ≥2 (C/F 기준) — 다음 라운드의 생성기
    live_trigger              = live_trigger,           # 부활 조건 (PASS면 NA)
    next_probe                = next_probe,             # " | " join — 구 스키마/소비자 호환
    fmt_codes                 = as.list(fmt_codes),     # 빈 list = 판정 없음 (정직)
    oos_retention             = oos_retention,          # IS65/OOS35 SR retention (hurdle D062, proxy)
    falsification_attempts    = fals                    # r7 Falsification 축 — 구조체 [{test,result,effect_retained}] (2026-07-04)
  )
  # ---- 논문 축 (v9): 전달된 값만 기록 — 없는 값을 "미기재" 문자열로 채우지 않는다 ----
  if (nzchar(trimws(as.character(source_paper %||% ""))))
    lcode$source_paper <- as.character(source_paper)
  if (nzchar(trimws(as.character(paper_assumption_broken %||% ""))))
    lcode$paper_assumption_broken <- as.character(paper_assumption_broken)

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
    # [2026-07-17 A3] portfolio_alpha_t 1급 병기 — nested(authoritative.*)에만 두면
    # promote.R .lc_get(top-level 조회) Rigor 축에서 NA 유실 (실측 48건 갭 봉합)
    if (is.finite(.as_num(auth$essence$portfolio_alpha_t_nw_lag3)))
      lcode$portfolio_alpha_t <- .as_num(auth$essence$portfolio_alpha_t_nw_lag3)
    lcode$authoritative <- list(
      essence_grade             = auth$essence_grade,
      portfolio_alpha_t_nw_lag3 = .as_num(auth$essence$portfolio_alpha_t_nw_lag3),
      oos_retention             = .as_num(auth$essence$oos_retention),
      dsr                       = .as_num(auth$essence$dsr),
      audit_integrity           = auth$contract$integrity_status,
      selection_type            = "chain",
      chain_qualification       = .chain_qualification_record(),  # §3 chain 자격요건 기록 (추가 필드)
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
#   v9 Lean Loop (2026-08-23): **비동기 spawn**(wait = FALSE)으로 전환한다.
#   왜: 이 두 파이썬은 L-code corpus/cluster 를 갱신하는 *후처리*이고, 그 결과를 이 런이
#   소비하지 않는다(반환값 미사용). 동기로 기다리면 라운드 예산만 먹는다.
#   ★대가를 정직하게 적는다 — wait=FALSE 이므로 **종료코드 검사가 불가능**하다(구판의
#   rc 검사 기능은 여기서 사라진다). 대신 stdout/stderr 를 로그 파일로 남겨 사후 확인이
#   가능하게 하고, spawn 사실 1줄을 콘솔에 찍는다(침묵 금지).
.run_axiom_pipeline <- function() {
  hv <- file.path(.AS_INFRA, "axiom", "lcode_harvester.py")
  cl <- file.path(.AS_INFRA, "axiom", "cluster_extractor.py")
  # QVEST_PY 우선 → PATH python3.
  py <- Sys.getenv("QVEST_PY", unset = Sys.which("python3"))
  if (!nzchar(py)) {
    cat("[AlphaSearch] WARN: python 부재 — Axiom 파이프라인 SKIP (QVEST_PY 환경변수 설정 필요)\n")
    return(invisible(FALSE))
  }
  log_path <- file.path(PROJECT_ROOT, ".cache", "axiom_pipeline_spawn.log")
  tryCatch(dir.create(dirname(log_path), showWarnings = FALSE, recursive = TRUE),
           error = function(e) NULL)
  ok <- tryCatch({
    system2(py, c(shQuote(hv), "--project-dir", shQuote(PROJECT_ROOT)),
            stdout = log_path, stderr = log_path, wait = FALSE)
    system2(py, c(shQuote(cl), "--project-dir", shQuote(PROJECT_ROOT)),
            stdout = log_path, stderr = log_path, wait = FALSE)
    TRUE
  }, error = function(e) { cat("[AlphaSearch] WARN: Axiom 파이프라인 spawn 실패 —",
                               conditionMessage(e), "\n"); FALSE })
  if (isTRUE(ok))
    cat(sprintf("[AlphaSearch] Axiom 파이프라인 비동기 spawn (harvester+cluster, wait=FALSE) — 종료코드 미검사, 로그: %s\n",
                .rel_project_path(log_path)))
  invisible(ok)
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
    # book_state.json 정본 소재 = qepm/mailbox/governor/ (CAP-P0-2 수리 2026-07-03:
    #   기존 PROJECT_ROOT 직하 참조는 항상 부재 → incumbent_book_ir 공백 → ΔIR 기준선 소실).
    bs  <- file.path(PROJECT_ROOT, "qepm", "mailbox", "governor", "book_state.json")
    if (!file.exists(bs))
      cat(sprintf("[AlphaSearch][PG] WARN: book_state.json 부재 (%s) — incumbent 빈 book으로 대체 (ΔIR 기준선 없음, 침묵 금지 고지)\n", bs))
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
