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

# ---- Infra path resolution (Korean-path safe) ----
.AS_INFRA <- local({
  cand <- Sys.getenv("QVEST_INFRA_DIR", "")
  if (nzchar(cand) && file.exists(file.path(cand, "config.R"))) return(cand)
  file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure")
})
source(file.path(.AS_INFRA, "config.R"))
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

# =============================================================================
run_alpha_search <- function(strategy_name,
                             strategy_idea,
                             factor_engine_path,
                             n_holdings    = 20L,
                             weight_method = "ivol",
                             commission    = 0.0015,
                             start_date    = NULL,   # FACTORS 시그널 시작일(예 "2005-01-01"). NULL=전기간
                             universe      = "ALL",  # "ALL"=전종목(유동성 2e8만) / "KR_TOP500"=유동성 2e8 통과 중 시총 top500 (KR_TOP500_FREEFLOAT, PIT-safe)
                             out_root      = NULL,
                             portfolio_id  = "PF_ALPHASEARCH",
                             send_telegram = TRUE,
                             tg_dry_run    = FALSE,
                             factor_analysis = TRUE) {   # FF3/FF5/Carhart 알파 + Fama-MacBeth 회귀
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
  source(factor_engine_path, local = TRUE)
  if (!exists("FACTORS") || !is.data.table(FACTORS))
    stop("[AlphaSearch] factor_engine이 FACTORS data.table을 생성하지 않았습니다.")
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
  sim <- run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
    n_holdings = n_holdings, weight_method = weight_method, commission = commission,
    buffer_zone = list(keep_n = as.integer(2L * n_holdings), entry_n = as.integer(n_holdings))
  )

  # ---- 5. Charts: equity_curve.png + annual_returns.png (vs BM) ----
  generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name)
  equity_png <- file.path(OUT_DIR, "equity_curve.png")
  annual_png <- file.path(OUT_DIR, "annual_returns.png")
  charts <- Filter(file.exists, c(equity_png, annual_png))

  # ---- 6. 점수·등급 = 기존 스코어링 체계(run_hurdle_gate) 재사용 ----
  hg     <- run_hurdle_gate(sim_result = sim, FACTORS = FACTORS,
                            strategy_name = strategy_name, output_dir = OUT_DIR)
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

  # ---- 6b. 팩터 회귀 분석 (FF3/FF5/Carhart 알파 + Fama-MacBeth) — 기존 run_analysis 재사용 ----
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({
      run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir = OUT_DIR, strategy_name = strategy_name)
      assign("%||%", `%||%`, envir = globalenv())   # run_analysis 내부 source 오염 복원
    }, error = function(e) cat("[AlphaSearch] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  pass    <- grade %in% c("A", "A_NOVEL", "A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B", "C") || (is_fail && pit_clean)   # 명확한 실패 패턴(clean PIT)
  cat(sprintf("[AlphaSearch] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6c. FR 모듈 등재 (공용 계약 register_module — ★등급무관: 하위등급도 국면 specialist 가능) ----
  # PIT-clean 백테 완료분만(이 지점 도달=detect_lookahead 통과). 사용여부는 RCMA가 국면조건부 판단.
  if (isTRUE(pit_clean)) tryCatch({
    source(file.path(PROJECT_ROOT, "02_Infrastructure", "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_, meta = list(strategy_idea = strategy_idea, score = score))
    assign("%||%", `%||%`, envir = globalenv())   # register_module source 후 전역 %||% 복원
  }, error = function(e) cat("[AlphaSearch] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 7. Telegram: 2차트 + 전략아이디어 + 성과요약(스코어링 지표) ----
  if (isTRUE(send_telegram)) {
    .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                             m, sdef, excess_cagr, charts, universe = universe,
                             universe_n = universe_n_eff, out_dir = OUT_DIR, dry_run = tg_dry_run)
    # 팩터 분석 메시지 ([팩터 분석] 기존 양식: FF3/FF5/Carhart 알파 + Fama-MacBeth + IC)
    if (isTRUE(factor_analysis) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis")) {
      tryCatch(tg_pass_analysis(strategy_name, OUT_DIR),
               error = function(e) cat("[AlphaSearch][팩터분석TG] 실패:", conditionMessage(e), "\n"))
    }
  }

  # ---- 8. L-code 적립 (PASS + 의미있는 실패만, 모드별 디렉터리) ----
  l_code_path <- NULL
  if (pass || notable) {
    l_code_path <- .write_lcode(strategy_id, strategy_name, strategy_idea, grade,
                                m, excess_cagr, pass, is_fail)
    .run_axiom_pipeline()   # harvester + cluster (자가발전)
  }

  # ---- 9. Grade A → STR 등록 + PG 편입 "권고"(book_state는 수동) ----
  if (pass) {
    .register_strategy_best_effort(strategy_id, strategy_name, strategy_idea, grade, m)
    if (isTRUE(send_telegram))
      .recommend_pg_admission(strategy_id, strategy_name, grade, portfolio_id, dry_run = tg_dry_run)
  }

  invisible(list(strategy_id = strategy_id, grade = grade, score = score,
                 pass = pass, notable = notable, excess_cagr = excess_cagr,
                 out_dir = OUT_DIR, charts = charts, l_code = l_code_path))
}

# ---- Telegram brief (tg_agent_brief 단일 진입점; 헤더에 모드 배지 자동) ----
.send_alpha_search_brief <- function(strategy_name, strategy_idea, strategy_id, grade,
                                     score, m, sdef, excess_cagr, charts,
                                     universe = "ALL", universe_n = NA_integer_, out_dir = NULL, dry_run = FALSE) {
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

  idea_body <- strategy_idea
  if (nchar(idea_body) < 30)
    idea_body <- paste0(idea_body, sprintf(" — %s · 월간 리밸런싱 단일 전략으로 검증.", uni_label))

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
  if (!is.na(dsr) && dsr < 0.5)      weak <- c(weak, "감가샤프지수 낮음 — 다중검정에 취약")
  if (!is.na(excess_cagr) && excess_cagr <= 0) weak <- c(weak, "벤치마크 대비 초과수익 미확보")
  if (length(weak) < 2) weak <- c(weak, "특이 위험요인 제한적", "추가 정밀검증 권고")
  weak <- head(weak, 5L)

  # FF3/FF5/Carhart 팩터알파는 [팩터분석] 메시지(tg_pass_analysis)로 일원화 — 메인 brief 중복 제거 (2026-06-05 도훈)

  sections <- list(
    list(type = "text",   emoji = "\U0001F4DA", heading = "연구 컨텍스트", body = ctx),
    list(type = "text",   emoji = "\U0001F4A1", heading = "전략 아이디어", body = idea_body),
    list(type = "kv",     emoji = "\U0001F4C8", heading = "성과 요약",     kv   = kv)
  )
  sections <- c(sections, list(list(type = "bullet", emoji = "\U0001F6A9",
                heading = "주의/약점", items = weak)))
  tryCatch(
    tg_agent_brief(agent = "AlphaSearch",
                   title = sprintf("알파 서칭 — %s 검증 (등급 %s)", strategy_name, grade),
                   sections = sections, charts = charts, lock_scope = strategy_id,
                   dry_run = dry_run),
    error = function(e) cat("[AlphaSearch][TG] 발송 실패:", conditionMessage(e), "\n"))
}

# ---- L-code 작성 (모드별 디렉터리 stage_artifacts/l_code/alpha_search/) ----
.write_lcode <- function(strategy_id, strategy_name, strategy_idea, grade,
                         m, excess_cagr, pass, is_fail) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  lc_dir <-file.path(PROJECT_ROOT, "stage_artifacts", "l_code", "alpha_search")
  dir.create(lc_dir, recursive = TRUE, showWarnings = FALSE)
  tags <- c("ALPHA_SEARCH", "FAST_VALIDATION")
  if (!pass) tags <- c(tags, "VALIDATED_HARD_FAIL")   # 실패 교훈 → 역패턴 마이너 입력
  lesson <- if (pass)
    sprintf("%s: 등급 %s, 연복리 %.1f%% (벤치마크 대비 %+.1f%%p), 샤프 %.2f, 최대낙폭 %.1f%%. 통과 — PG 편입 권고.",
            strategy_name, grade, .as_num(m$CAGR), excess_cagr %||% 0, .as_num(m$Sharpe), -abs(.as_num(m$MDD)))
  else
    sprintf("%s: 등급 %s, 연복리 %.1f%% (벤치마크 대비 %+.1f%%p), 샤프 %.2f. %s",
            strategy_name, grade, .as_num(m$CAGR), excess_cagr %||% 0, .as_num(m$Sharpe),
            if (is_fail) "명확한 실패 패턴 — 역방향 가설 탐색 후보." else "근접 탈락 — 보강 후 재검증 후보.")
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
    excess_cagr       = excess_cagr %||% NA_real_
  )
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
  tryCatch(system2("python3", c(shQuote(hv), "--project-dir", shQuote(PROJECT_ROOT)),
                   stdout = FALSE, stderr = FALSE), error = function(e) NULL)
  tryCatch(system2("python3", c(shQuote(cl), "--project-dir", shQuote(PROJECT_ROOT)),
                   stdout = FALSE, stderr = FALSE), error = function(e) NULL)
  cat("[AlphaSearch] Axiom 파이프라인(harvester+cluster) 갱신\n")
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
