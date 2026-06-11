#!/usr/bin/env Rscript
# =============================================================================
# run_hzz_inverse.R — HZZ(2016) Trend Factor 역방향 프로브 (anti-trend Q1 long)
# =============================================================================
# kr-inverse-pattern-miner 패턴 (Direction Flip): 원 HZZ 검증(STR_AS_HZZ_*)이
#   풀런 F + 스모크에서 *팩터 알파 유의 음수*(FF3 −7.7%/yr t=−1.91, Carhart4 −8.3%/yr
#   t=−2.19, FF5 −7.5%/yr t=−1.94, 2015~)를 관찰 → KR에서 HZZ E[r] 예측의 부호가 역전됐다는
#   문서화된 next_probe 가설. E[r] *최하위* quintile(Q1) long(anti-trend)이 실재 신호일 가능성.
#   메커니즘 후보: KR 개인투자자 추세추종 과잉 → 트렌드 신호 과대반영 → 반전.
#
# ★ chain probe (데이터 스누핑 아님): selection_type="chain", 동일 데이터 가족 2번째 trial.
#   변경사유 = "원방향에서 유의 음수 알파 관찰"(mechanism 진단). n_trials_cumulative=2 (HZZ Q5 → HZZ Q1).
#   chain 자격 ①진단사유 기록(본 헤더) ②변형선택 IS-only(부호 1회 flip, OOS 반복조회 없음)
#   ③holdout 최종 1회. DSR 게이트 부적용(chain), PORT_t 2.95가 문헌-레벨 다중검정 기보정.
#
# 구현 = 엔진 invert 인자 재사용 (신규 구현 최소):
#   .HZZ_INVERT <- TRUE 를 환경에 설정 후 fe_hzz_trend.R source → Score = −E[r] →
#   엔진 descending-Score 선택이 E[r] bottom quintile(Q1)을 long으로 선택. 원본 동작은 invert=FALSE로 무변.
#   ★ C13(NEGATE_FACTORS/FLIP_SIGN) 무관 — factor DB 부호 조작이 아니라 동일 E[r] 예측의 하위분위
#     long 포트 구성(anti-trend 가설의 정의). E[r]은 식(1)~(5) 그대로(forward 없음). 상세 fe_hzz_trend.R §7b.
#
# 측정 경로 = run_hzz_trend.R 미러 (run_monthly_simulation / generate_charts / run_hurdle_gate /
#   run_analysis / register_module / L-code / tg_agent_brief). track="HZZ_inverse".
# QEPM 이행 없음: Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WT/cert 없음.
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.AS_INFRA <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                    Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
                    "02_Infrastructure")
source(file.path(.AS_INFRA, "alpha_search", "run_alpha_search.R"))  # 엔진 + 내부 헬퍼 전부 로드

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

run_hzz_inverse <- function(strategy_name = "Trend Factor INVERSE (HZZ 2016 anti-trend)",
                            strategy_idea = paste0(
                              "Han-Zhou-Zhu(2016) 트렌드 팩터 역방향 프로브: 동일 E[r] 예측의 ",
                              "최하위 분위(anti-trend Q1) 등가중 월간리밸 long-only. ",
                              "원방향 KR 검증서 팩터알파 유의 음수 → 부호역전 가설(개인 추세추종 과잉 반전)"),
                            start_date    = "2005-01-01",
                            commission    = 0.0015,
                            send_telegram = TRUE,
                            tg_dry_run    = FALSE,
                            factor_analysis = TRUE) {
  # ★ 함수-로컬 robust %||% (hybrid_mode.R global %||% clobber 방어 — run_hzz_trend.R 동일 패턴)
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  .restore_or <- function() assign("%||%",
    function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a,
    envir = globalenv())
  fe <- file.path(.AS_INFRA, "alpha_search", "fe_hzz_trend.R")
  stopifnot(file.exists(fe))
  run_id      <- paste0(format(Sys.time(), "%Y%m%d_%H%M%S"), "_", Sys.getpid())
  strategy_id <- paste0("STR_AS_HZZINV_", run_id)
  OUT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "alpha_search", run_id)
  dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
  cat(sprintf("\n=== [AlphaSearch · HZZ_inverse(anti-trend Q1)] %s (%s) ===\n  start=%s\n",
              strategy_name, strategy_id, start_date))

  # ---- 1. Data ----
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
  if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date, tz = "Asia/Seoul")]
  if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date, tz = "Asia/Seoul")]
  RAWDATA[, TradingValue := Close * Vol]
  RAWDATA[, AvgTV20 := frollmean(TradingValue, 20L, align = "right"), by = Ticker]
  RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

  # ---- 2. Factor engine -> FACTORS(Date, Ticker, Score=-E[r], N=quintile) ----
  #   ★ INVERT 스위치 ON: 엔진이 Score=-E[r] → bottom quintile(Q1) long 선택.
  .HZZ_INVERT <- TRUE
  source(fe, local = TRUE)
  stopifnot(exists("FACTORS"), is.data.table(FACTORS),
            all(c("Date","Ticker","Score","N") %in% names(FACTORS)))
  if (!is.null(start_date)) FACTORS <- FACTORS[Date >= as.Date(start_date)]
  universe_n_eff <- as.integer(round(uniqueN(paste(FACTORS$Date, FACTORS$Ticker)) /
                                       max(uniqueN(FACTORS$Date), 1L)))
  cat(sprintf("[hzzinv] FACTORS: %d rows | %d signal dates | %d tickers | avg cand/mo=%d | %s~%s\n",
              nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker), universe_n_eff,
              as.character(min(FACTORS$Date)), as.character(max(FACTORS$Date))))

  # ---- 3. PIT 검증 ----
  pit <- detect_lookahead(fe)
  if (!isTRUE(pit$clean)) {
    for (v in (pit$violations %||% list()))
      cat(sprintf("  [PIT] line %s [%s]: %s\n", v$line %||% "?", v$check %||% "?", v$msg %||% ""))
    stop("[hzzinv] PIT 위반 — 중단")
  }
  cat("[hzzinv] PIT check: CLEAN\n")
  cat("[hzzinv][PIT-NOTE] 외부 parquet/cache 의존 없음 (MA는 RAWDATA 일간 종가만). forward-label 비해당.\n")
  cat("  -> invert는 선택부호만 flip(Q5→Q1). E[r] 식(1)~(5) 불변, 미래참조 없음. C13 무관(§7b).\n")

  # ---- 4. Backtest: pure 월간 quintile EW (buffer 없음, weight=equal) ----
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

  # ---- 6b. 팩터 회귀 (FF3/FF5/Carhart + Fama-MacBeth) — long-only Q1 ----
  if (isTRUE(factor_analysis) && exists("run_analysis")) {
    tryCatch({ run_analysis(sim, FACTORS, RAWDATA, BM_DT, output_dir = OUT_DIR,
                            strategy_name = strategy_name)
               .restore_or() },
             error = function(e) cat("[hzzinv] 팩터분석 생략:", conditionMessage(e), "\n"))
  }

  pass    <- grade %in% c("A","A_NOVEL","A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B","C") || (is_fail && isTRUE(pit$clean))
  cat(sprintf("[hzzinv] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6c. FR 모듈 등재 (등급무관, register_module) ----
  tryCatch({
    source(file.path(.AS_INFRA, "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_, meta = list(strategy_idea = strategy_idea, score = score,
                                                      track = "HZZ_inverse", selection_type = "chain",
                                                      n_trials_cumulative = 2L))
    .restore_or()
  }, error = function(e) cat("[hzzinv] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 7. Telegram (run_alpha_search 헬퍼 재사용) ----
  if (isTRUE(send_telegram)) {
    .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                             m, sdef, excess_cagr, charts, universe = "ALL",
                             universe_n = universe_n_eff, out_dir = OUT_DIR, dry_run = tg_dry_run)
    if (isTRUE(factor_analysis) && !isTRUE(tg_dry_run) && exists("tg_pass_analysis"))
      tryCatch(tg_pass_analysis(strategy_name, OUT_DIR),
               error = function(e) cat("[hzzinv][팩터분석TG] 실패:", conditionMessage(e), "\n"))
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

  cat(sprintf("\n[hzzinv] DONE. id=%s grade=%s score=%.0f excess=%+.2f out=%s\n",
              strategy_id, grade, score %||% 0, excess_cagr %||% 0, OUT_DIR))
  invisible(list(strategy_id = strategy_id, grade = grade, score = score, pass = pass,
                 notable = notable, excess_cagr = excess_cagr, out_dir = OUT_DIR,
                 charts = charts, l_code = l_code_path, track = "HZZ_inverse",
                 rank_ic = .as_num(m$IC %||% m$Rank_IC),
                 port_t = .as_num(m$Portfolio_Alpha_t %||% m$Harvey_t)))
}

cat("[run_hzz_inverse] loaded. usage: run_hzz_inverse(start_date=\"2005-01-01\")\n")
