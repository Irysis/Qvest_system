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
      if (n < max(2L, k)) return(NULL)
      .leg_w(head(md, k), "long")
    } else if (cons %in% c("decile_long_short", "quantile_long_short")) {
      kl <- if (is.finite(nl)) as.integer(nl) else max(2L, as.integer(ceiling(n * lfrac)))
      ks <- if (is.finite(ns)) as.integer(ns) else max(2L, as.integer(ceiling(n * sfrac)))
      if (n < kl + ks) return(NULL)
      rbind(.leg_w(head(md, kl), "long"), .leg_w(tail(md, ks), "short"))
    } else stop(sprintf("[replication] 미지원 construction: %s", cons))
  })
  W <- rbindlist(Filter(Negate(is.null), rows), use.names = TRUE)
  if (nrow(W) == 0L) stop("[replication] WEIGHTS 구성 실패 — FACTORS/spec 확인")
  W
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

run_paper_replication <- function(strategy_name, strategy_idea, factor_engine_path,
                                  portfolio_spec = list(construction = "top_n_long",
                                                        weighting = "ew",
                                                        rebalance = "monthly"),
                                  universe = "K200_KQ150",
                                  source_paper = NULL,
                                  commission_paper = NULL,   # NULL = 논문 무명시 → gross(0)
                                  start_date = "2005-01-01",
                                  out_root = NULL,
                                  send_telegram = TRUE, tg_dry_run = FALSE) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  stopifnot(file.exists(factor_engine_path))
  # 근거 논문 필수 (v10 절대 규칙: 모든 수치 결정에 뿌리 논문 — 원문 링크)
  if (is.null(source_paper) || !nzchar(as.character(source_paper$url %||% "")))
    stop("[replication] source_paper$url 필수 — 근거 논문 원문 링크 없이 착수 금지 (v10)")

  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_id <- paste0("RP_", run_id)
  if (is.null(out_root)) out_root <- file.path(PROJECT_ROOT, "stage_artifacts", "replication")
  OUT_DIR <- file.path(out_root, run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [Replication] %s (%s) ===\n    paper: %s\n    idea: %s\n",
              strategy_name, strategy_id, source_paper$url, strategy_idea))

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
                             FACTORS <- .apply_universe(FACTORS[Date >= as.Date(start_date)]) }
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
  WEIGHTS <- if (!is.null(PORTFOLIO) && identical(portfolio_spec$construction %||% "", "engine_direct")) {
    PORTFOLIO
  } else if (!is.null(FACTORS)) {
    .rp_build_weights(FACTORS, RAWDATA, portfolio_spec)
  } else PORTFOLIO
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
    source_paper_url = as.character(source_paper$url),
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
      "근거 논문" = as.character(source_paper$url)
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
  lc <- tryCatch({
    emit_lcode(mode = "paper_replication", strategy_id = strategy_id, grade = grade,
               lesson_text = sprintf("%s 충실구현: 등급 %s. 논문기준 SR %.2f vs 15bps SR %.2f. %s",
                                     strategy_name, grade %||% "NA", paper_sum$sharpe,
                                     es$essence$net_sharpe %||% NA_real_,
                                     strategy_idea),
               metric_type = es$metric_type %||% "uncertain",
               oos_retention = es$essence$oos_retention,
               portfolio_alpha_t = es$essence$portfolio_alpha_t_nw_lag3,
               selection_type = "chain",
               source_paper = as.character(source_paper$url),
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
                 diagnostics = sim_grade$diagnostics, l_code = lc))
}

cat("[run_paper_replication.R] Loaded (v10) — run_paper_replication(name, idea, engine, portfolio_spec, source_paper=...)\n")
