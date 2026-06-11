#!/usr/bin/env Rscript
# =============================================================================
# run_hzz_trend.R — Han, Zhou & Zhu (2016, JFE) Trend Factor 논문 그대로 검증
# =============================================================================
# alpha-search 모드 측정 경로를 그대로 사용(run_monthly_simulation / generate_charts /
#   run_hurdle_gate / run_analysis / register_module / L-code / tg_agent_brief).
#   run_residmom_paper.R 골격 미러 — 팩터 엔진만 fe_hzz_trend.R로 교체.
#   buffer_zone=NULL(순수 월간 리밸), weight_method="equal"(논문 equal-weight),
#   N 컬럼=top quintile decile-size override(종목수 임의제한 금지).
#
# ★ 논문 완전복제 (제1원칙):
#   - 신호: 정규화 MA price ratio 11종(L=3..1000일) → 월간 횡단면 OLS β → 직전12m β평균 →
#     E[r] 예측(식1~5). 포트=E[r] top quintile EW 월간리밸 (식 portfolio).
#   - ★ 롱숏 불허(도훈 mandate 2026-06-11): 논문 L/S(Q5−Q1) → Q5 long-only 사상. 엔진이 Q5만 산출.
#   - 유니버스 K200∪KQ150 고정(시변 PIT). 기간 2005-01-01~ 고정. burn-in: 1000d MA + 12m β평균.
#   - KR 보충(명시): $5 가격필터→유동성 2e8 대체 / WLS→OLS(baseline) / 사이즈필터→유니버스 내재.
#
# QEPM 이행 없음: Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WT/cert 없음.
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.AS_INFRA <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                    Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
                    "02_Infrastructure")
source(file.path(.AS_INFRA, "alpha_search", "run_alpha_search.R"))  # 엔진 + 내부 헬퍼 전부 로드

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

run_hzz_trend <- function(strategy_name = "Trend Factor (HZZ 2016)",
                          strategy_idea = paste0(
                            "Han-Zhou-Zhu(2016) 트렌드 팩터: 정규화 MA price ratio 11종(3~1000일)을 ",
                            "월간 횡단면 회귀 → 직전 12개월 계수평균으로 E[r] 예측 → top quintile 등가중 월간리밸 (long-only 사상)"),
                          start_date    = "2005-01-01",
                          commission    = 0.0015,
                          send_telegram = TRUE,
                          tg_dry_run    = FALSE,
                          factor_analysis = TRUE) {
  # ★ 함수-로컬 robust %||% (lexical scope 우선). run_hurdle_gate가 source하는
  #   qepm/scripts/hybrid_mode.R가 global %||%를 buggy form(!is.na(a) — length>1 list서 crash)으로
  #   덮어쓰므로, 함수 내부 모든 %||%가 이 로컬을 쓰도록 고정. assign 복원도 이 로컬을 글로벌에 재주입.
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  .restore_or <- function() assign("%||%",
    function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a,
    envir = globalenv())
  fe <- file.path(.AS_INFRA, "alpha_search", "fe_hzz_trend.R")
  stopifnot(file.exists(fe))
  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_id <- paste0("STR_AS_HZZ_", run_id)
  OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [AlphaSearch · 논문스펙] %s (%s) ===\n  start=%s\n",
              strategy_name, strategy_id, start_date))

  # ---- 1. Data ----
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
  RAWDATA[, TradingValue := Close * Vol]
  RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
  RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

  # ---- 2. Factor engine -> FACTORS(Date, Ticker, Score=E[r], N=quintile) ----
  #   ★ start_date filter는 엔진 *후*에 적용 — 1000d MA + 36... 아닌 12m β평균 burn-in이
  #     데이터 시작(~1990)부터 필요. start_date는 시그널(FACTORS$Date)만 제한(RAWDATA는 전체).
  source(fe, local = TRUE)
  stopifnot(exists("FACTORS"), is.data.table(FACTORS),
            all(c("Date","Ticker","Score","N") %in% names(FACTORS)))
  if (!is.null(start_date)) FACTORS <- FACTORS[Date >= as.Date(start_date)]
  universe_n_eff <- as.integer(round(uniqueN(paste(FACTORS$Date, FACTORS$Ticker)) /
                                       max(uniqueN(FACTORS$Date), 1L)))
  cat(sprintf("[hzz] FACTORS: %d rows | %d signal dates | %d tickers | avg cand/mo=%d | %s~%s\n",
              nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker), universe_n_eff,
              as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date))))

  # ---- 3. PIT 검증 ----
  pit <- detect_lookahead(fe)
  if (!isTRUE(pit$clean)) {
    for (v in (pit$violations %||% list()))
      cat(sprintf("  [PIT] line %s [%s]: %s\n", v$line %||% "?", v$check %||% "?", v$msg %||% ""))
    stop("[hzz] PIT 위반 — 중단")
  }
  cat("[hzz] PIT check: CLEAN\n")
  # 외부 데이터 의존: 없음 — 신호는 RAWDATA 일간 종가만(forward-label 무관, 정적분석 사각 해당 없음).
  cat("[hzz][PIT-NOTE] 외부 parquet/cache 의존 없음 (MA는 RAWDATA 일간 종가만). forward-label lookahead 비해당.\n")
  cat("  -> 식(3) r_t~Ã_{t-1}: 신호 t-1 정보. 식(5) E[β]: t까지 β만. 식(4) Ã_t로 t+1 예측. 미래참조 없음.\n")

  # ---- 4. Backtest: pure 월간 top-quintile EW (buffer 없음, weight=equal) ----
  sim <- run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
    n_holdings = 50L,            # N 컬럼이 매월 override (quintile). fallback only.
    weight_method = "equal",     # 논문: equal-weight
    commission = commission,
    buffer_zone = NULL)          # 논문: 순수 월간 리밸런싱

  # ---- 5. Charts ----
  generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name)
  charts <- Filter(file.exists, file.path(OUT_DIR, c("equity_curve.png","annual_returns.png")))

  # ---- 6. 스코어링 (alpha-search 모드 동일 경로) ----
  hg <- run_hurdle_gate(sim_result = sim, FACTORS = FACTORS,
                        strategy_name = strategy_name, output_dir = OUT_DIR)
  .restore_or()
  grade <- hg$grade %||% "uncertain"
  score <- .as_num(hg$score)
  m     <- hg$verdict$metrics %||% list()
  sdef  <- hg$verdict$statistical_defense %||% list()
  perf_bm <- tryCatch(summarise_perf(sim$bm_xts, "KOSPI200"), error = function(e) NULL)
  bm_cagr_pct <- if (!is.null(perf_bm)) .as_num(perf_bm$CAGR) else NA_real_
  excess_cagr <- round(.as_num(m$CAGR) - bm_cagr_pct, 2)

  # ---- 6b. 팩터 회귀 (FF3/FF5/Carhart + Fama-MacBeth) — long-only Q5 ----
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({ run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir = OUT_DIR,
                            strategy_name = strategy_name)
               .restore_or() },
             error = function(e) cat("[hzz] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  pass    <- grade %in% c("A","A_NOVEL","A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B","C") || (is_fail && isTRUE(pit$clean))
  cat(sprintf("[hzz] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6c. FR 모듈 등재 (등급무관, register_module) ----
  tryCatch({
    source(file.path(.AS_INFRA, "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_, meta = list(strategy_idea = strategy_idea, score = score))
    .restore_or()
  }, error = function(e) cat("[hzz] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 7. Telegram (run_alpha_search 헬퍼 재사용) ----
  if (isTRUE(send_telegram)) {
    .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                             m, sdef, excess_cagr, charts, universe = "ALL",
                             universe_n = universe_n_eff, out_dir = OUT_DIR, dry_run = tg_dry_run)
    if (isTRUE(factor_analysis) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis"))
      tryCatch(tg_pass_analysis(strategy_name, OUT_DIR),
               error = function(e) cat("[hzz][팩터분석TG] 실패:", conditionMessage(e), "\n"))
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

  cat(sprintf("\n[hzz] DONE. id=%s grade=%s score=%.0f excess=%+.2f out=%s\n",
              strategy_id, grade, score %||% 0, excess_cagr %||% 0, OUT_DIR))
  invisible(list(strategy_id = strategy_id, grade = grade, score = score, pass = pass,
                 notable = notable, excess_cagr = excess_cagr, out_dir = OUT_DIR,
                 charts = charts, l_code = l_code_path,
                 rank_ic = .as_num(m$IC %||% m$Rank_IC),
                 port_t = .as_num(m$Portfolio_Alpha_t %||% m$Harvey_t)))
}

cat("[run_hzz_trend] loaded. usage: run_hzz_trend(start_date=\"2005-01-01\")\n")
