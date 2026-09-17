#!/usr/bin/env Rscript
# =============================================================================
# run_paper_replication.R — 1계층 최초 라운드: 논문 충실구현 (v10 2026-08-29 신설)
# =============================================================================
# 도훈 지시: "최초로 진행하는 팩터전략 리서치는 유니버스만 한국시장으로 바꾸고
#   나머지 내용들은 논문의 충실구현을 제1목적으로 함" + "완전 충실구현 —
#   롱숏·종목수·비중 전부 논문 그대로. 고정 축은 강화 프로세스부터".
#
# run_alpha_search.R 과의 관계: 골격(단계·계약·텔레그램·L-code)은 미러하되
#   시뮬레이터는 replication_harness.R(비중 기반·롱숏 허용·종목수 무제한)를 쓴다.
#   실투형 축(LiqPass·weight_method_gate·25캡)은 **여기서 적용하지 않는다** —
#   그건 강화 프로세스(WT-R)의 일이다. PIT(detect_lookahead)는 계층 무관 불변.
#
# 등급: ★비용 이중 측정 — 논문 명시 비용(대개 gross)으로 충실구현 성과를 병기하되,
#   **등급은 15bps 순비용 판으로 산출**한다(essence 문턱이 15bps 기준으로 보정돼
#   있어 gross 등급은 A 인플레). 두 값 모두 manifest·텔레그램에 기록.
#
# Usage:
#   source("02_Infrastructure/alpha_search/run_paper_replication.R")
#   run_paper_replication("전략명", "아이디어", "<engine.R>",
#     portfolio_spec = list(construction="decile_long_short", weighting="ew"),
#     source_paper = list(title="...", url="https://..."))
#
# engine 계약 (확장): 엔진은 둘 중 하나를 산출한다 —
#   FACTORS(Date, Ticker, Score)               → 러너가 portfolio_spec 으로 비중 구성
#   PORTFOLIO(Date, Ticker, Weight[, Leg])     → 논문 비중 그대로 소비 (construction="engine_direct")
#
# L-code 축 (2026-09-02): construction_type 은 러너가 **관측**(diagnostics$has_short)·실행 분기에서
#   파생해 emit_lcode 에 명시 전달한다(.rp_construction_type). emit 측 키워드 추론 폴백은 기본값이
#   'single_factor_long_only' 라 롱숏 5분위 VW 스프레드(RP_20260902_122546_22268, n_max 138·has_short
#   TRUE)를 롱온리로 적었다 — hypothesis_index 태그 오염. 호출자가 더 잘 알면
#   portfolio_spec$construction_type 로 덮어쓴다(LCODE_VALID_CONSTRUCTION_TYPES 어휘).
#   mechanism_hypothesis 인자 미전달 시 = 논문 가설(strategy_idea)을 '검증 전 진술' 로 라벨해 채운다.
# =============================================================================

suppressWarnings(suppressMessages({
  library(data.table)
  library(jsonlite)
}))

.RP_FIND_ROOT <- function() {
  candidates <- unique(c(
    Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
  is_root <- function(p) nzchar(p) && dir.exists(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))
  for (p in candidates) if (is_root(p)) return(normalizePath(p, winslash = "/", mustWork = TRUE))
  cur <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  repeat {
    if (is_root(cur)) return(cur)
    parent <- dirname(cur)
    if (identical(parent, cur)) break
    cur <- parent
  }
  stop("[replication] project root not found. Set CLAUDE_PROJECT_DIR or QM_ROOT.")
}
.RP_ROOT <- .RP_FIND_ROOT()
.RP_INFRA <- file.path(.RP_ROOT, "02_Infrastructure")
source(file.path(.RP_INFRA, "config.R"))
if (!exists("PROJECT_ROOT", inherits = TRUE)) PROJECT_ROOT <- .RP_ROOT
if (!nzchar(Sys.getenv("CLAUDE_PROJECT_DIR", ""))) Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT)
if (!nzchar(Sys.getenv("QM_ROOT", ""))) Sys.setenv(QM_ROOT = PROJECT_ROOT)
source(file.path(.RP_INFRA, "backtest_harness.R"))      # load_rawdata / get_execution_date / generate_charts
source(file.path(.RP_INFRA, "replication", "replication_harness.R"))
source(file.path(TELEGRAM_DIR, "telegram_notify.R"))
source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
source(file.path(.RP_INFRA, "contracts", "backtest_result_contract.R"))
source(file.path(.RP_INFRA, "contracts", "audit_bt_result.R"))
source(file.path(.RP_INFRA, "contracts", "essence_score.R"))
source(file.path(.RP_INFRA, "contracts", "save_bt_result.R"))
source(file.path(.RP_INFRA, "axiom", "lcode_emit.R"))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

# ── portfolio_spec → WEIGHTS 구성 (논문 그대로 — 하드코딩 금지: 값은 논문에서) ──
.rp_build_weights <- function(FACTORS, RAWDATA, spec) {
  cons  <- spec$construction %||% "top_n_long"
  wgt   <- spec$weighting %||% "ew"
  lfrac <- spec$long_frac %||% 0.10
  sfrac <- spec$short_frac %||% lfrac
  nl    <- spec$n_long %||% NA
  ns    <- spec$n_short %||% NA
  nmax  <- as.integer(spec$n_max %||% .RP_NMAX_DEFAULT)

  size_at <- NULL
  if (wgt == "vw") {
    if (!"Size" %in% names(RAWDATA)) stop("[replication] weighting=vw 는 RAWDATA$Size 필요")
    size_at <- RAWDATA[is.finite(Size), .(Date, Ticker, Size)]
  }
  .leg_w <- function(md, side) {
    if (nrow(md) == 0L) return(NULL)
    w <- switch(wgt,
      ew    = rep(1 / nrow(md), nrow(md)),
      vw    = { s <- md$Size; s[!is.finite(s) | s <= 0] <- NA
                if (all(is.na(s))) rep(1 / nrow(md), nrow(md)) else { s[is.na(s)] <- min(s, na.rm = TRUE); s / sum(s) } },
      score = { s <- md$Score - min(md$Score) + 1e-9; s / sum(s) },
      stop(sprintf("[replication] 미지원 weighting: %s (ew/vw/score/paper)", wgt)))
    data.table(Date = md$Date, Ticker = md$Ticker,
               Weight = if (side == "long") w else -w)
  }
  out <- vector("list", 2L)
  by_date <- split(FACTORS[is.finite(Score)], by = "Date")
  rows <- lapply(by_date, function(md) {
    md <- as.data.table(md)
    if (!is.null(size_at) && wgt == "vw")
      md <- merge(md, size_at[Date == md$Date[1]], by = c("Date", "Ticker"), all.x = TRUE)
    setorder(md, -Score)
    n <- nrow(md)
    if (cons == "top_n_long") {
      k <- if (is.finite(nl)) as.integer(nl) else max(2L, as.integer(ceiling(n * lfrac)))
      k <- min(k, nmax)                                   # ★고정 축 상한
      # ★"상위 k" 는 "있는 만큼 최대 k" 다 (2026-09-01). n_long 을 명시하면 후보가 얇은 달이
      #   통째로 버려졌다. lfrac 경로는 k <= n 이 자명하므로 이 두 줄은 그쪽 거동을 바꾸지 않는다.
      k <- min(k, n)
      if (n < 2L) return(NULL)
      .leg_w(head(md, k), "long")
    } else if (cons %in% c("decile_long_short", "quantile_long_short")) {
      kl <- if (is.finite(nl)) as.integer(nl) else max(2L, as.integer(ceiling(n * lfrac)))
      ks <- if (is.finite(ns)) as.integer(ns) else max(2L, as.integer(ceiling(n * sfrac)))
      # ★양 다리 **합계**가 상한이다(슬리브 조합에서도 최종 보유가 축을 넘지 않게).
      if (kl + ks > nmax) { .sc <- nmax / (kl + ks)
        kl <- max(1L, as.integer(floor(kl * .sc))); ks <- max(1L, as.integer(floor(ks * .sc))) }
      if (n < kl + ks) return(NULL)
      rbind(.leg_w(head(md, kl), "long"), .leg_w(tail(md, ks), "short"))
    } else stop(sprintf("[replication] 미지원 construction: %s", cons))
  })
  W <- rbindlist(Filter(Negate(is.null), rows), use.names = TRUE)
  if (nrow(W) == 0L) stop("[replication] WEIGHTS 구성 실패 — FACTORS/spec 확인")
  W
}

# ── L-code construction_type 파생 (Independence 축 — 관측 우선 · 선언 폴백 · 미상은 NULL) ──
#   선언(spec$construction)은 원천을 말하지 산출 축을 말하지 않는다 — 시뮬레이터가 실제로 기록한
#   레그(diagnostics$has_short)가 1순위, 선언은 미관측일 때의 폴백. engine_direct = 러너가 엔진
#   PORTFOLIO 를 그대로 썼는가(선언과 무관한 실제 실행 분기). 반환값은 전부
#   lcode_schema.R::LCODE_VALID_CONSTRUCTION_TYPES 안의 라벨이고, 판별 불가면 NULL 이다 —
#   라벨을 지어내지 않는다(emit 측이 키워드 추론 WARN 으로 정직 결측 처리).
.rp_construction_type <- function(spec, diag, engine_direct = FALSE) {
  explicit <- as.character(spec$construction_type %||% "")[1]
  if (nzchar(explicit)) return(explicit)                              # 호출자 명시 > 파생
  cons <- if (isTRUE(engine_direct)) "engine_direct" else as.character(spec$construction %||% "top_n_long")[1]
  has_short <- diag$has_short %||% NA
  if (isTRUE(has_short))  return("long_short")                        # 관측: 숏 레그 존재 (선언 무관)
  if (isFALSE(has_short)) {                                           # 관측: 롱온리
    if (identical(cons, "top_n_long")) return("single_sleeve_long_only_topN")
    return("single_factor_long_only")                                 # engine_direct 논문 비중 그대로(롱온리)
  }
  # 미관측(diagnostics 부재) → 선언 폴백
  if (cons %in% c("decile_long_short", "quantile_long_short")) return("long_short")
  if (identical(cons, "top_n_long")) return("single_sleeve_long_only_topN")
  NULL                                                                # engine_direct + 미관측 = 미상
}

# ── 논문 기준(충실구현) 성과 요약 — PerformanceAnalytics 표준 함수만 ──
.rp_paper_summary <- function(sim) {
  x <- sim$strategy_xts
  m <- apply.monthly(x, Return.cumulative)
  list(
    cagr   = as.numeric(Return.annualized(x, scale = 252, geometric = TRUE)),
    sharpe = as.numeric(SharpeRatio.annualized(m, scale = 12)),
    mdd    = as.numeric(maxDrawdown(x)),
    n_months = nrow(m)
  )
}

# ★"호출자가 고르지 않았다" 는 **부재(NULL)** 로 표현한다 — 특정 값을 표식으로 삼으면
#   그 값을 진짜로 고른 호출자와 구분되지 않는다(2026-08-31 실사고).
# ★종목수 상한 (도훈 지시 2026-08-31). 정본 = constraint_defaults.json::max_names 25
#   = CLAUDE.md/pit.md 고정 축. 구판은 러너 구성 경로에 상한이 없어 long_frac 폴백 10%%가
#   후보 수에 따라 27~36 종을 냈다(논문 값이 아니라 후보 수가 정한 숫자였다).
#   spec$n_max 로 덮을 수 있게 두되 기본은 축을 따른다.
.RP_NMAX_DEFAULT <- 25L
run_paper_replication <- function(strategy_name, strategy_idea, factor_engine_path,
                                  # ★NULL = "호출자가 고르지 않았다". 구판은 기본값이
                                  #   "top_n_long" 이라 **명시적 top_n_long 과 구분되지 않았고**,
                                  #   자동 판정이 그 명시를 덮었다(2026-08-31: 롱온리 판을 요청했는데
                                  #   engine_direct 로 측정돼 롱숏 결과가 나왔다). 부재는 값이 아니다.
                                  portfolio_spec = NULL,
                                  universe = "K200_KQ150",
                                  source_paper = NULL,
                                  require_source_paper = TRUE,   # ★강화 레인만 FALSE (2026-09-03 해제)
                                  commission_paper = NULL,   # NULL = 논문 무명시 → gross(0)
                                  start_date = "2005-01-01",
                                  out_root = NULL,
                                  send_telegram = TRUE, tg_dry_run = FALSE,
                                  factor_analysis = TRUE,
                                  mechanism_hypothesis = NULL) {   # L-code 기전 가설 — NULL 이면 논문 가설(strategy_idea)을 '검증 전 진술' 로 라벨
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  stopifnot(file.exists(factor_engine_path))
  # 근거 논문 — 충실구현은 필수(논문을 재현하는 단계에서 논문을 뺄 수 없다),
  #   강화 레인은 2026-09-03 해제(도훈 지시). 호출자가 require_source_paper=FALSE 로 가른다.
  if (isTRUE(require_source_paper) &&
      (is.null(source_paper) || !nzchar(as.character(source_paper$url %||% ""))))
    stop("[replication] source_paper$url 필수 — 근거 논문 원문 링크 없이 착수 금지 (v10)")
  # ★아래 서식·기록에서 NULL 이 sprintf 를 영길이로 붕괴시키지 않게 한 번만 정규화한다.
  .sp_url <- as.character(source_paper$url %||% NA_character_)[1]
  if (is.na(.sp_url) || !nzchar(.sp_url)) .sp_url <- "(근거 논문 없음 — 강화 레인)"

  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_id <- paste0("RP_", run_id)
  if (is.null(out_root)) out_root <- file.path(PROJECT_ROOT, "stage_artifacts", "replication")
  OUT_DIR <- file.path(out_root, run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [Replication] %s (%s) ===\n    paper: %s\n    idea: %s\n",
              strategy_name, strategy_id, .sp_url, strategy_idea))

  # ---- 1. Data (LiqPass 미적용 — 논문 유니버스 필터 우선. paper_faithful 라벨) ----
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]

  # ---- 2. Engine → FACTORS 또는 PORTFOLIO ----
  fe_env <- new.env(parent = environment())
  fe_env$RAWDATA <- RAWDATA; fe_env$BM_DT <- BM_DT
  source(factor_engine_path, local = fe_env)
  has_pf <- exists("PORTFOLIO", envir = fe_env, inherits = FALSE) && is.data.table(fe_env$PORTFOLIO)
  has_fx <- exists("FACTORS", envir = fe_env, inherits = FALSE) && is.data.table(fe_env$FACTORS)
  if (!has_pf && !has_fx)
    stop("[replication] engine 이 FACTORS 도 PORTFOLIO 도 생성하지 않았습니다.")
  FACTORS <- if (has_fx) fe_env$FACTORS else NULL
  PORTFOLIO <- if (has_pf) fe_env$PORTFOLIO else NULL
  rm(fe_env); gc(verbose = FALSE)

  # ---- 3. 유니버스 치환 (유일한 변경 — K200∪KQ150 PIT 시변 멤버십) ----
  .apply_universe <- function(dt) {
    if (is.null(universe) || !universe %in% c("K200_KQ150", "INDEX")) return(dt)
    if (!all(c("K200", "KQ150") %in% names(RAWDATA)))
      stop("[replication] universe=K200_KQ150 requires RAWDATA K200/KQ150 membership")
    .mem <- unique(RAWDATA[Date %in% unique(dt$Date) & (K200 == TRUE | KQ150 == TRUE),
                           .(Date, Ticker)])
    n0 <- uniqueN(dt$Ticker)
    out <- merge(dt, .mem, by = c("Date", "Ticker"))
    cat(sprintf("[replication] universe=K200_KQ150 (PIT 시변): tickers %d->%d\n",
                n0, uniqueN(out$Ticker)))
    out
  }
  if (!is.null(FACTORS))   { stopifnot(all(c("Date","Ticker","Score") %in% names(FACTORS)))
                             if (!inherits(FACTORS$Date, "Date")) FACTORS[, Date := as.Date(Date)]
                             FACTORS <- .apply_universe(FACTORS[Date >= as.Date(start_date)])
    # ★스코어 패널을 산출물로 남긴다 (2026-09-01) — B+ 논문 신호를 팩터 DB 에 무인 등록하는
    #   경로가 이 패널을 **동결 사본**으로 쓴다. 등록 시점에 엔진을 다시 돌리면 443개월 백필이
    #   수시간이고, 그 사이 엔진 파일이 바뀌면 값이 달라져 재현이 깨진다.
    #   ★여기서 저장하는 것은 **실제로 측정에 들어간 바로 그 패널**이다(유니버스 적용 후).
    tryCatch({
      suppressMessages(library(arrow))
      arrow::write_parquet(FACTORS, file.path(OUT_DIR, "factors_panel.parquet"))
    }, error = function(e) cat(sprintf("[replication] factors_panel 저장 실패(측정에는 영향 없음): %s
",
                                       conditionMessage(e))))
  }
  if (!is.null(PORTFOLIO)) { stopifnot(all(c("Date","Ticker","Weight") %in% names(PORTFOLIO)))
                             if (!inherits(PORTFOLIO$Date, "Date")) PORTFOLIO[, Date := as.Date(Date)]
                             PORTFOLIO <- .apply_universe(PORTFOLIO[Date >= as.Date(start_date)]) }

  # ---- 4. PIT (계층 무관 불변) ----
  pit <- detect_lookahead(factor_engine_path)
  if (!isTRUE(pit$clean)) {
    for (v in (pit$violations %||% list()))
      cat(sprintf("  [PIT] line %s [%s]: %s\n", v$line %||% "?", v$check %||% "?", v$msg %||% ""))
    stop("[replication] PIT 위반 감지 — 중단. engine 을 t-1 기준으로 수정하세요.")
  }
  cat("[replication] PIT check: CLEAN\n")

  # ---- 5. WEIGHTS ----
  # ★엔진이 PORTFOLIO 를 냈다면 그것이 **논문 비중**이다 — 엔진이 비중을 만들 이유가 그것뿐이다.
  #   구판은 construction 기본값이 "top_n_long" 이라, 호출자가 engine_direct 를 **명시하지
  #   않으면** PORTFOLIO 를 조용히 버리고 FACTORS 로 top-N 롱온리를 다시 구성했다.
  #   실사고 2026-08-31: 무인 충실구현 3편 전부(2608.24703 · 27156 · 27076) 가 이 경로로
  #   측정됐다. 2608.27076 은 논문이 top-6 롱 + top-6 숏(베타≈0)인데 롱온리 36종으로 나가
  #   설계의 핵심인 시장중립이 사라졌다 — 논문 성과와 비교 자체가 성립하지 않는다.
  #   무인 검증기가 portfolio_spec 을 넘기지 않는 것이 방아쇠였지만, 기본값이 엔진 산출을
  #   덮는 구조가 근인이다. 명시가 없으면 **산출물이 결정한다**(명시가 있으면 그것이 우선).
  if (is.null(portfolio_spec)) portfolio_spec <- list()
  .cons <- portfolio_spec$construction %||% ""
  if (!nzchar(.cons)) {
    .auto <- if (!is.null(PORTFOLIO)) "engine_direct" else "top_n_long"
    if (!identical(.auto, .cons)) {
      cat(sprintf("[replication] construction 자동 판정: %s (엔진 산출 = %s)
",
                  .auto, if (!is.null(PORTFOLIO)) "PORTFOLIO" else "FACTORS"))
      portfolio_spec$construction <- .auto; .cons <- .auto
    }
  }
  WEIGHTS <- if (!is.null(PORTFOLIO) && identical(.cons, "engine_direct")) {
    # ★engine_direct 는 **논문 비중 그대로**가 존재 이유라 자르지 않는다. 자르면 그 순간
    #   충실구현이 아니게 된다. 대신 축 초과를 조용히 넘기지 않는다 — 계약 감사(E-5)가
    #   판정하고 여기서는 사실을 드러낸다.
    .nd <- PORTFOLIO[, .N, by = Date]
    if (nrow(.nd) && max(.nd$N) > .RP_NMAX_DEFAULT)
      cat(sprintf("[replication] ★engine_direct 보유 최대 %d종 > 고정 축 %d — 논문 비중 그대로 유지, 축 초과는 감사에 남는다
",
                  max(.nd$N), .RP_NMAX_DEFAULT))
    PORTFOLIO
  } else if (!is.null(FACTORS)) {
    .rp_build_weights(FACTORS, RAWDATA, portfolio_spec)
  } else PORTFOLIO
  # 러너가 실제로 탄 분기 — 선언(construction)이 아니라 이것이 L-code construction_type 의 근거 (제어흐름 불변)
  weights_engine_direct <- !is.null(PORTFOLIO) &&
    (identical(portfolio_spec$construction %||% "", "engine_direct") || is.null(FACTORS))
  # Weight 패널 날짜 정합 sanity: 시그널일이 미래로 튀면 중단
  if (max(WEIGHTS$Date) > max(RAWDATA$Date))
    stop("[replication] WEIGHTS 시그널일이 RAWDATA 범위 밖 (미래 날짜) — PIT 의심")

  # ---- 6. 이중 시뮬레이션 (논문 기준 + 15bps 등급 기준) ----
  comm_paper <- commission_paper %||% 0
  sim_paper <- run_replication_simulation(RAWDATA, BM_DT, WEIGHTS,
                                          commission = comm_paper, start_date = start_date)
  sim_grade <- if (identical(comm_paper, 0.0015)) sim_paper else
    run_replication_simulation(RAWDATA, BM_DT, WEIGHTS,
                               commission = 0.0015, start_date = start_date)
  paper_sum <- .rp_paper_summary(sim_paper)
  cat(sprintf("[replication] 논문 기준(비용 %.0fbps): CAGR %.1f%% · SR %.2f · MDD %.1f%% · %d개월\n",
              comm_paper * 1e4, paper_sum$cagr * 100, paper_sum$sharpe,
              paper_sum$mdd * 100, paper_sum$n_months))

  # ---- 7. 계약 경유 등급 (15bps 판) ----
  strategy_spec <- list(
    strategy_name = strategy_name, strategy_idea = strategy_idea,
    constraint_profile = "replication",          # audit holdings_cap INFO 강등 스위치
    lookahead_prevention = "detect_lookahead(engine) CLEAN + t+1 실행(get_execution_date 익월 첫 거래일) + 시그널일>RAWDATA 범위 검사",
    construction = portfolio_spec$construction %||% "top_n_long",
    weight_method = portfolio_spec$weighting %||% "paper",
    rebalance = portfolio_spec$rebalance %||% "monthly",
    universe = universe, liquidity_filter = "paper_faithful",
    n_max = sim_grade$diagnostics$n_max, has_short = sim_grade$diagnostics$has_short,
    source_paper_url = .sp_url,
    benchmark_note = if (isTRUE(sim_grade$diagnostics$has_short)) "long_short_vs_long_bm" else "long_vs_long_bm"
  )
  bt <- build_bt_result(sim_grade, strategy_spec,
                        run_id = run_id, strategy_id = strategy_id,
                        benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
                        transaction_cost_bps = 15, slippage_bps = 0,
                        frequency = "daily", annualization_factor = 252,
                        universe_id = universe, code_version = "run_paper_replication_v10",
                        created_by_agent = "Replication")
  bt <- audit_bt_result(bt)
  saved <- tryCatch(save_bt_result(bt, OUT_DIR, save_xlsx = FALSE), error = function(e) {
    cat("[replication] save_bt_result 실패(비치명):", conditionMessage(e), "\n"); NULL })
  es <- essence_score(bt, n_trials_cumulative = 1L, selection_type = "chain")

  # ---- 7-b. 팩터 회귀 분석 (FF3/FF5/Carhart 4F 알파 + Fama-MacBeth) ----
  #   ★도훈 지시 2026-08-30 — 예전 알파 서칭의 [팩터 분석] 메시지를 무인 경로에도.
  #   생산자는 `strategy_analyzer.R::run_analysis` 하나다 — 새로 구현하지 않는다.
  #   산출: analysis_multifactor.csv(FF3/FF5/Carhart) · analysis_fmb_summary.csv(FMB) ·
  #        analysis_ic.csv · analysis_stress.csv · analysis_report.md → tg_pass_analysis 가 소비.
  #   ★FACTORS 가 NULL 이면(PORTFOLIO 형 엔진) IC·FMB 가 서지 않는다 — 조용히 건너뛰지 말고
  #     사유를 남긴다(침묵 누락이 이 저장소의 반복 결함).
  analysis_ran <- FALSE
  if (isTRUE(factor_analysis) && !identical(Sys.getenv("QVEST_RP_NO_FACTOR_ANALYSIS", "0"), "1")) {
    if (is.null(FACTORS) || !nrow(FACTORS)) {
      cat("[replication] 팩터분석 생략 — FACTORS 부재(PORTFOLIO 형 엔진). FF/FMB 미산출
")
    } else if (!exists("run_analysis")) {
      suppressWarnings(tryCatch(source(file.path(.RP_INFRA, "strategy_analyzer.R")),
                                error = function(e) NULL))
    }
    if (exists("run_analysis") && !is.null(FACTORS) && nrow(FACTORS)) {
      .t0 <- Sys.time()
      # ★경계 어댑터 2개 — 분석기(strategy_analyzer.R)는 알파 서칭 하네스를 전제한다.
      #   공유 분석기를 고치지 않고 호출자 쪽에서 맞춰준다(알파 서칭 경로 무영향).
      #
      #   ① HOLDINGS_LOG 열 이름: 복제 하네스는 Date(=exec_date) 로 찍고 분석기는
      #      Signal_Date 를 찾는다 → 5절(회전율)에서 죽고 6절(FF3/FF5/Carhart)에
      #      도달못한다. 실측 2026-08-30: "Object 'Signal_Date' not found amongst
      #      [Date, Ticker, Weight, Leg]". ★기간 라벨로만 쓰이므로(연속 리밸런싱
      #      간 종목 집합 차집합) exec_date 를 그대로 써도 의미가 보존된다 — 조회가
      #      아니라 그룹핑 키라 PIT 함의 없음.
      #   ② FUNC_PATH: 없으면 분석기가 dirname(dirname(output_dir))/02_Infrastructure 로
      #      폴백하는데 그게 stage_artifacts/02_Infrastructure 로 풀려 **존재하지 않는다**.
      #      file.exists 가드라 에러 없이 조용히 건너뛴다 — FF3/FF5/Carhart 가 침묵 누락된다.
      .fp_had <- exists("FUNC_PATH", envir = globalenv())
      .fp_old <- if (.fp_had) get("FUNC_PATH", envir = globalenv()) else NULL
      assign("FUNC_PATH", .RP_INFRA, envir = globalenv())
      on.exit({ if (.fp_had) assign("FUNC_PATH", .fp_old, envir = globalenv())
                else suppressWarnings(rm("FUNC_PATH", envir = globalenv())) }, add = TRUE)
      .sim_fa <- sim_grade
      if (!is.null(.sim_fa$HOLDINGS_LOG) && nrow(.sim_fa$HOLDINGS_LOG) &&
          !("Signal_Date" %in% names(.sim_fa$HOLDINGS_LOG))) {
        .hl <- data.table::copy(.sim_fa$HOLDINGS_LOG)
        .hl[, Signal_Date := Date]
        .sim_fa$HOLDINGS_LOG <- .hl
      }
      tryCatch({
        run_analysis(.sim_fa, FACTORS, RAWDATA, BM_DT,
                     output_dir = OUT_DIR, strategy_name = strategy_name)
        assign("%||%", `%||%`, envir = globalenv())   # run_analysis 내부 source 오염 복원
        analysis_ran <- TRUE
        if (!file.exists(file.path(OUT_DIR, "analysis_multifactor.csv")))
          cat("[replication][WARN] analysis_multifactor.csv 미생성 — FF3/FF5/Carhart 누락",
              "(factor_portfolios.R 경로 또는 KR 팩터 캐시 확인)
")
        cat(sprintf("[replication] 팩터분석 완료 — %.1f분 (FF3/FF5/Carhart + FMB)
",
                    as.numeric(difftime(Sys.time(), .t0, units = "mins"))))
      }, error = function(e)
        cat("[replication] 팩터분석 실패(비치명):", conditionMessage(e), "
"))
    }
  }
  grade <- as.character(es$grade %||% NA)
  audit_tbl <- bt$audit
  integrity <- tryCatch(if (nrow(audit_tbl[severity == "critical" & status == "FAIL"])) "FAIL" else "OK",
                        error = function(e) "UNKNOWN")

  auth <- list(
    status = if (identical(es$metric_type, "backtested") && !identical(integrity, "FAIL")) "OK" else "FAIL",
    strategy_id = strategy_id, strategy_name = strategy_name,
    remeasured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    run_id = run_id, bt_result_path = file.path(OUT_DIR, "bt_result.rds"),
    metric_type = es$metric_type, essence_grade = grade,
    grade_basis = "replication_chain",
    essence = es$essence, hard_fail = es$hard_fail,
    structural_drawdown = es$structural_drawdown,
    selection_type = es$selection_type, dsr_gate_applied = es$dsr_gate_applied,
    ## ★essence_score 가 산출한 겼을 **떨어뜨리지 않는다** (도훈 2026-09-04).
    ##   이 쓰기는 반환 list 를 통째로 실지 않고 필드를 골라 쓴다. 그래서 새로
    ##   붙인 rolling_grade / defensive_score / grade_base 가 산출물에서 사라졌다 —
    ##   소급은 380건에 기입됐는데 **새 측정은 빈 채** 나갔다(2511.12490 실측).
    ##   생산자만 있고 소비자가 없는 형태의 거울상 — 산출하는데 실리지 않았다.
    grade_base = es$grade_base, recent_regime_rescued = es$recent_regime_rescued,
    recent_regime_label = es$recent_regime_label,
    rolling_grade = es$rolling_grade, defensive_score = es$defensive_score,
    reasons = es$reasons,
    replication = list(
      source_paper = source_paper,
      commission_paper_bps = comm_paper * 1e4,
      paper_basis = paper_sum,
      grade_basis_note = "등급은 15bps 순비용 판 (essence 문턱 15bps 보정 — gross 등급은 인플레)",
      fidelity = "universe 치환(K200∪KQ150)만 — 그 외 논문 그대로 (v10 완전 충실구현)",
      benchmark_note = strategy_spec$benchmark_note,
      n_max = sim_grade$diagnostics$n_max, has_short = sim_grade$diagnostics$has_short
    ),
    contract = list(integrity_status = integrity,
                    cagr = es$essence$cagr, sharpe = es$essence$net_sharpe,
                    mdd = es$essence$mdd, calmar = es$essence$calmar)
  )
  saveRDS(bt, file.path(OUT_DIR, "bt_result.rds"))
  write_json(auth, file.path(OUT_DIR, "authoritative_remeasure.json"),
             auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
  cat(sprintf("[replication] 권위 등급 = %s (15bps 판 · %s)\n", grade, integrity))

  # ---- 7-c. 2계층 모듈 풀 등재 (2026-09-07 신설 이음매) ----------------------
  #   ★없던 것: 이 러너는 bt_result.rds + authoritative_remeasure.json 만 남기고
  #     `register_module()` 을 **한 번도 부르지 않았다**. 그래서 v10 생산 631 런
  #     (essence B 54 · defensive TRUE 407)이 module_catalog 에 들어갈 경로가 없었고
  #     카탈로그는 2026-08-24 이후 정지했다. "1계층이 B 이상을 못 만든다" 가 아니라
  #     **만든 것이 풀로 못 갔다**. 이 한 줄이 충실구현·결합·강화 셀 세 레인을 동시에
  #     잇는다 — 셋 다 이 함수를 경유하기 때문이다(rf_cell_worker.R:32 · rf_replication_verify.R:369).
  #   ★재측정 없음 — 방금 쓴 산출물을 읽어 옮길 뿐이고, 등재 자격은 소비자의 계약
  #     술어(ds_pool_eligible → essence ∈ {A,B} ∨ 방어형)가 낸다. 자격 미달은 등재하지
  #     않는다(카탈로그 폭주 방지). 실패는 저널에 사유가 남는다 — 조용한 실패 없음.
  #   kill switch: QVEST_RP_REGISTER=0
  if (!identical(Sys.getenv("QVEST_RP_REGISTER", "1"), "0")) tryCatch({
    .rmm_env <- new.env(parent = globalenv())     # 전역 %||% 오염 방지 — 격리 적재
    sys.source(file.path(.RP_INFRA, "contracts", "register_measured_module.R"), envir = .rmm_env)
    .reg <- .rmm_env$rmm_register_measured(
      OUT_DIR, sim_result = sim_grade, origin_mode = "replication",
      meta = list(strategy_idea = strategy_idea, strategy_name = strategy_name,
                  source_paper_url = .sp_url,
                  paper_key = as.character(source_paper$paper_key %||% NA_character_),
                  fidelity_lane = if (isTRUE(weights_engine_direct)) "engine_direct" else
                                  (portfolio_spec$construction %||% "top_n_long")))
    cat(sprintf("[replication] 모듈 등재: %s (%s)\n",
                if (isTRUE(.reg$registered)) "OK" else "미등재", .reg$code))
  }, error = function(e)
    cat("[replication] 모듈 등재 실패(비치명 — 저널에 사유):", conditionMessage(e), "\n"))

  # ---- 8. Charts (2차트 — 알파서칭 양식) ----
  tryCatch(generate_charts(sim_grade, OUT_DIR, strategy_name),
           error = function(e) cat("[replication] 차트 실패(비치명):", conditionMessage(e), "\n"))

  # ---- 9. Telegram ([1계층] 표제 — qvest-telegram SKILL 계층 표제 정본) ----
  if (isTRUE(send_telegram)) tryCatch({
    kv <- list(
      "계층" = "1계층 — 충실구현",
      "유니버스" = paste0(universe, " (논문 대비 유일한 변경)"),
      "등급" = sprintf("%s (15bps 순비용 판)", grade %||% "NA"),
      "논문 기준 성과" = sprintf("CAGR %.1f%% · SR %.2f · MDD %.1f%% (비용 %.0fbps)",
                            paper_sum$cagr * 100, paper_sum$sharpe, paper_sum$mdd * 100, comm_paper * 1e4),
      "15bps 순 성과" = sprintf("CAGR %.1f%% · SR %.2f · MDD %.1f%%",
                            (es$essence$cagr %||% NA) * 100, es$essence$net_sharpe %||% NA,
                            (es$essence$mdd %||% NA) * 100),
      "구성" = sprintf("%s · %s · 종목 max %s%s",
                     strategy_spec$construction, strategy_spec$weight_method,
                     sim_grade$diagnostics$n_max %||% "?",
                     if (isTRUE(sim_grade$diagnostics$has_short)) " · 롱숏" else ""),
      "근거 논문" = .sp_url
    )
    charts <- Filter(file.exists, file.path(OUT_DIR, c("equity_curve.png", "annual_returns.png")))
    tg_agent_brief(
      agent = "AlphaSearch",
      title = sprintf("[1계층] 알파 서칭 — %s 충실구현 (등급 %s)", strategy_name, grade %||% "NA"),
      sections = list(
        list(type = "bullet", emoji = "📌", heading = "현재 리서치 상황",
             items = c(sprintf("단계: 1계층 팩터전략 리서치 — 충실구현"),
                       sprintf("대상: %s", strategy_name),
                       sprintf("위치: %s", .rel_path <- sub(paste0(PROJECT_ROOT, "/?"), "", OUT_DIR)),
                       sprintf("직전 판정: 등급 %s", grade %||% "NA"))),
        list(type = "text", emoji = "💡", heading = "전략 아이디어", body = strategy_idea),
        list(type = "kv", emoji = "📈", heading = "성과 요약", kv = kv)
      ),
      charts = charts, dry_run = tg_dry_run, lock_scope = strategy_id
    )
  }, error = function(e) cat("[replication] 텔레그램 실패(비치명):", conditionMessage(e), "\n"))

  # ---- 10. L-code (research_mode = paper_replication) ----
  #   construction_type = 관측(has_short)·실행 분기 파생 — emit 키워드 추론에 맡기지 않는다.
  #   mechanism_hypothesis = 호출자 전달 > 논문 가설(strategy_idea, '검증 전 진술' 라벨). 아이디어가
  #   비어 있으면 NULL(정직 결측 — 접두어만으로 보일러플레이트 검사를 통과시키지 않는다).
  lc_construction <- .rp_construction_type(portfolio_spec, sim_grade$diagnostics, weights_engine_direct)
  lc_mechanism <- {
    mh <- trimws(as.character(mechanism_hypothesis %||% "")[1])
    if (nzchar(mh)) mh else {
      si <- trimws(as.character(strategy_idea %||% "")[1])
      if (nzchar(si)) sprintf("논문 가설(충실구현 대상 — 검증 전 진술): %s", si) else NULL
    }
  }
  # ★L-code 억제 스위치 (2026-09-17 · G2 적대 재실행): rf_overlay_adversary 의 T1/T2 재실행은 측정 산출물만 필요하다 —
  #   같은 칸의 교훈이 두 번 적립되면 hypothesis_index 가 오염된다. QVEST_RP_NO_LCODE=1 은 그 재실행 경로만 켠다
  #   (기본 0 = 구판 거동 그대로). 스위치를 읽는다는 사실 자체를 적대검증 모듈이 소스에서 재도출해 재실행 허용 조건으로 쓴다.
  lc <- if (identical(Sys.getenv("QVEST_RP_NO_LCODE", "0"), "1")) {
    cat("[replication] L-code 발행 억제 (QVEST_RP_NO_LCODE=1 — 적대 재실행 · 교훈 이중 적립 방지)\n"); NULL
  } else tryCatch({
    emit_lcode(mode = "paper_replication", strategy_id = strategy_id, grade = grade,
               lesson_text = sprintf("%s 충실구현: 등급 %s. 논문기준 SR %.2f vs 15bps SR %.2f. %s",
                                     strategy_name, grade %||% "NA", paper_sum$sharpe,
                                     es$essence$net_sharpe %||% NA_real_,
                                     strategy_idea),
               metric_type = es$metric_type %||% "uncertain",
               construction_type = lc_construction,     # Independence 축 — 관측·실행 분기 파생
               mechanism_hypothesis = lc_mechanism,     # Mechanism 축 — 논문 가설(검증 전) / 호출자
               oos_retention = es$essence$oos_retention,
               portfolio_alpha_t = es$essence$portfolio_alpha_t_nw_lag3,
               selection_type = "chain",
               source_paper = .sp_url,
               next_probe = list("강화 프로세스 축 1 (멀티팩터/비중방법론/리스크오버레이 중 논문 후속연구가 가리키는 축)",
                                 "실투형 변환(long-only·≤25종·15bps) 시 신호 보존율 측정"))
  }, error = function(e) { cat("[replication] L-code 실패(비치명):", conditionMessage(e), "\n"); NULL })

  # ---- 11. 라우팅: A → Judge / 미달 → 강화 원장 ----
  if (identical(grade, "A")) {
    write_json(list(strategy_id = strategy_id, layer = 1L, grade = grade,
                    artifacts = OUT_DIR, engine_path = factor_engine_path,
                    requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                    note = "v10: Grade A → Judge(PIT 전담) 스폰 요청 — 세션(Q-Lead)이 Agent 스폰"),
               file.path(OUT_DIR, "judge_request.json"), auto_unbox = TRUE, pretty = TRUE)
    cat("[replication] ★Grade A — judge_request.json 발행 (Judge 스폰은 세션 소관)\n")
  } else if (identical(Sys.getenv("QVEST_NO_LEDGER_OPEN", "0"), "1")) {
    # ★강화 셀 실행 중에는 새 강화 entry 를 열지 않는다 (강화 대상을 강화 중에 또 만드는 자기증식).
    #   2026-08-30 실사고: 무인 병렬 러너가 셀 5개를 돌리자 원장에 active 0/20 쓰레기 entry 5개가 생겼고,
    #   다음 논문 이월이 그 쓰레기를 붙잡을 뻔했다. 충실구현(신규 논문)에는 자동 open 이 옳으므로 조건부다.
    cat("[replication] 강화 원장 auto-open 억제 (QVEST_NO_LEDGER_OPEN=1)
")
  } else {
    tryCatch({
      source(file.path(.RP_INFRA, "reinforcement", "reinforce_ledger.R"))
      rf_open_entry(layer = 1L,
                    paper_key = as.character(source_paper$paper_key %||% ""),
                    paper_id = as.character(source_paper$paper_id %||% ""),
                    base_id = strategy_id, base_grade = grade %||% "NA",
                    base_artifacts = OUT_DIR, engine_path = factor_engine_path)
      cat("[replication] 강화 원장 open — reinforce_ledger_l1.json (≤20회)\n")
    }, error = function(e)
      cat("[replication] 강화 원장 등록 실패(비치명 — 세션이 수동 등록):", conditionMessage(e), "\n"))
  }

  invisible(list(strategy_id = strategy_id, grade = grade, out_dir = OUT_DIR,
                 paper_basis = paper_sum, essence = es$essence,
                 diagnostics = sim_grade$diagnostics, l_code = lc,
                 analysis_ran = analysis_ran,
                 construction_type = lc_construction))
}

cat("[run_paper_replication.R] Loaded (v10) — run_paper_replication(name, idea, engine, portfolio_spec, source_paper=...)\n")
