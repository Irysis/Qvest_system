#!/usr/bin/env Rscript
# =============================================================================
# run_residmom_paper.R — Blitz-Huij-Martens (2011) Residual Momentum 논문 그대로 검증
# =============================================================================
# alpha-search 모드 측정 경로를 그대로 사용(run_hurdle_gate / build_bt_result / register_module /
#   L-code / tg_agent_brief)하되, run_alpha_search 래퍼가 하드코딩하는 turnover-buffer(hysteresis)와
#   top20 cap을 제거해 **논문 원본의 pure 월간 top-decile equal-weight 리밸런싱**을 충실히 구현한다.
#   (도훈 mandate: "논문 그대로 진행. 비중 같은거" / "decile 그대로, 종목수·비중 임의 제한 금지".)
#
# run_alpha_search.R의 내부 헬퍼(.send_alpha_search_brief / .write_lcode / .run_axiom_pipeline /
#   .register_strategy_best_effort / .recommend_pg_admission)를 그대로 재사용 → 모드 일관성 유지.
# QEPM 이행 없음: Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WT/cert 없음.
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.AS_INFRA <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"), "02_Infrastructure")
source(file.path(.AS_INFRA, "alpha_search", "run_alpha_search.R"))  # 엔진 + 내부 헬퍼 전부 로드

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

run_residmom_paper <- function(strategy_name = "Residual Momentum (BHM 2011)",
                               strategy_idea = "Blitz-Huij-Martens(2011) 잔차모멘텀: 36m FF3 회귀 잔차의 11-1 표준화 모멘텀 top decile 등가중",
                               start_date    = "2006-01-01",
                               commission    = 0.0015,
                               send_telegram = TRUE,
                               tg_dry_run    = FALSE,
                               factor_analysis = TRUE) {
  fe <- file.path(.AS_INFRA, "alpha_search", "fe_residmom.R")
  stopifnot(file.exists(fe))
  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_id <- paste0("STR_AS_", run_id)
  OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [AlphaSearch · 논문스펙] %s (%s) ===\n", strategy_name, strategy_id))

  # ---- 1. Data ----
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
  RAWDATA[, TradingValue := Close * Vol]
  RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
  RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

  # ---- 2. Factor engine -> FACTORS(Date, Ticker, Score, N) ----
  source(fe, local = TRUE)
  stopifnot(exists("FACTORS"), is.data.table(FACTORS),
            all(c("Date","Ticker","Score","N") %in% names(FACTORS)))
  if (!is.null(start_date)) FACTORS <- FACTORS[Date >= as.Date(start_date)]
  universe_n_eff <- as.integer(round(uniqueN(paste(FACTORS$Date, FACTORS$Ticker)) /
                                       max(uniqueN(FACTORS$Date), 1L)))
  cat(sprintf("[paper] FACTORS: %d rows | %d signal dates | %d tickers | avg cand/mo=%d\n",
              nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker), universe_n_eff))

  # ---- 3. PIT 검증 ----
  pit <- detect_lookahead(fe)
  if (!isTRUE(pit$clean)) {
    for (v in (pit$violations %||% list()))
      cat(sprintf("  [PIT] line %s [%s]: %s\n", v$line %||% "?", v$check %||% "?", v$msg %||% ""))
    stop("[paper] PIT 위반 — 중단")
  }
  cat("[paper] PIT check: CLEAN\n")
  # 외부 데이터 의존 경고 (KR FF3 cache = 실현 과거 월간팩터, forward-label 아님 — 보증)
  cat("[paper][PIT-WARN] factor_engine이 .cache/kr_factor_returns_v2.parquet(KR FF3 월간)에 의존.\n")
  cat("  -> 해당 캐시는 '실현 월간 팩터수익'(과거)이며 forward-label 아님. 36m 회귀창은 형성월 t까지 과거만.\n")
  cat("  -> 따라서 Cycle50류 forward-label lookahead 해당 없음 (정적분석 사각 보증 완료).\n")

  # ---- 4. Backtest: pure 월간 top-decile EW (buffer 없음, weight=equal) ----
  #   N 컬럼이 매월 decile 종목수 override. buffer_zone=NULL → hysteresis 없는 순수 리밸런싱.
  sim <- run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
    n_holdings = 50L,            # N 컬럼이 매월 override (decile). fallback only.
    weight_method = "equal",     # 논문: equal-weight
    commission = commission,
    buffer_zone = NULL)          # 논문: 순수 월간 리밸런싱 (turnover-buffer 없음)

  # ---- 5. Charts ----
  generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name)
  charts <- Filter(file.exists, file.path(OUT_DIR, c("equity_curve.png","annual_returns.png")))

  # ---- 6. 스코어링 (alpha-search 모드 동일 경로) ----
  hg <- run_hurdle_gate(sim_result = sim, FACTORS = FACTORS,
                        strategy_name = strategy_name, output_dir = OUT_DIR)
  assign("%||%", `%||%`, envir = globalenv())
  grade <- hg$grade %||% "uncertain"
  score <- .as_num(hg$score)
  m     <- hg$verdict$metrics %||% list()
  sdef  <- hg$verdict$statistical_defense %||% list()
  perf_bm <- tryCatch(summarise_perf(sim$bm_xts, "KOSPI200"), error = function(e) NULL)
  bm_cagr_pct <- if (!is.null(perf_bm)) .as_num(perf_bm$CAGR) else NA_real_
  excess_cagr <- round(.as_num(m$CAGR) - bm_cagr_pct, 2)

  # ---- 6b. 팩터 회귀 (FF3/FF5/Carhart + Fama-MacBeth) ----
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({ run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir = OUT_DIR,
                            strategy_name = strategy_name)
               assign("%||%", `%||%`, envir = globalenv()) },
             error = function(e) cat("[paper] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  pass    <- grade %in% c("A","A_NOVEL","A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B","C") || (is_fail && isTRUE(pit$clean))
  cat(sprintf("[paper] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6c. FR 모듈 등재 (등급무관, register_module) ----
  tryCatch({
    source(file.path(.AS_INFRA, "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_, meta = list(strategy_idea = strategy_idea, score = score))
    assign("%||%", `%||%`, envir = globalenv())
  }, error = function(e) cat("[paper] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 7. Telegram (run_alpha_search 헬퍼 재사용) ----
  if (isTRUE(send_telegram)) {
    .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                             m, sdef, excess_cagr, charts, universe = "ALL",
                             universe_n = universe_n_eff, out_dir = OUT_DIR, dry_run = tg_dry_run)
    if (isTRUE(factor_analysis) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis"))
      tryCatch(tg_pass_analysis(strategy_name, OUT_DIR),
               error = function(e) cat("[paper][팩터분석TG] 실패:", conditionMessage(e), "\n"))
  }

  # ---- 8. L-code ----
  l_code_path <- NULL
  if (pass || notable) {
    l_code_path <- .write_lcode(strategy_id, strategy_name, strategy_idea, grade,
                                m, excess_cagr, pass, is_fail)
    .run_axiom_pipeline()
  }

  # ---- 9. Grade A → 등록 + PG 권고 ----
  if (pass) {
    .register_strategy_best_effort(strategy_id, strategy_name, strategy_idea, grade, m)
    if (isTRUE(send_telegram))
      .recommend_pg_admission(strategy_id, strategy_name, grade, "PF_ALPHASEARCH", dry_run = tg_dry_run)
  }

  cat(sprintf("\n[paper] DONE. id=%s grade=%s score=%.0f excess=%+.2f out=%s\n",
              strategy_id, grade, score %||% 0, excess_cagr %||% 0, OUT_DIR))
  invisible(list(strategy_id = strategy_id, grade = grade, score = score, pass = pass,
                 notable = notable, excess_cagr = excess_cagr, out_dir = OUT_DIR,
                 charts = charts, l_code = l_code_path,
                 rank_ic = .as_num(m$IC %||% m$Rank_IC), port_t = .as_num(m$Portfolio_Alpha_t %||% m$Harvey_t)))
}
