#!/usr/bin/env Rscript
# =============================================================================
# run_qmj_paper.R — Asness-Frazzini-Pedersen (2019) "Quality Minus Junk" 논문 그대로 검증
# =============================================================================
# alpha-search 모드 측정 경로를 그대로 사용(run_hurdle_gate / build_bt_result / register_module /
#   L-code / tg_agent_brief)하되, run_alpha_search 래퍼의 turnover-buffer(hysteresis)와 top20 cap을
#   제거해 **논문 원본의 pure 월간 top-decile equal-weight 리밸런싱**을 충실히 구현(run_residmom_paper와 동일 골격).
#
#   QMJ = z(Profitability)+z(Growth)+z(Safety)+z(Payout) 4축 등가중 composite (fe_qmj.R).
#   KR long-only → high-Quality decile EW. (도훈 mandate: 논문 그대로 decile·비중·종목수.)
#
# ★ 직교성 평가 (도훈 mandate): IS Carhart4 알파 t + **OOS retention(필수)** + STR_1715/풀 상관.
#   - reversal/quality-GP/low-vol/value 단일팩터는 직교 슬리브 실패. QMJ는 4축 composite라
#     STR_1715(풀 내 0.05 무상관) 동류 "멀티팩터 조합" 가설의 직접 검증.
#   - EP가 IS Carhart4 +2.13였으나 OOS -0.257로 기각된 교훈 → 상관↓ + 알파(+) + OOS유지 셋 다여야 슬리브.
#
# QEPM 이행 없음: Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WT/cert 없음.
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics) }))

.AS_INFRA <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"), "02_Infrastructure")
source(file.path(.AS_INFRA, "alpha_search", "run_alpha_search.R"))  # 엔진 + 내부 헬퍼 전부 로드

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.as_num <- function(x) { if (is.null(x) || length(x) == 0L) return(NA_real_); suppressWarnings(as.numeric(x[[1]])) }

run_qmj_paper <- function(strategy_name = "Quality Minus Junk (AFP 2019)",
                          strategy_idea = "Asness-Frazzini-Pedersen(2019) QMJ: profitability+growth+safety+payout 4축 등가중 composite, high-Quality decile 등가중 long-only",
                          start_date    = "2005-01-01",
                          commission    = 0.0015,
                          send_telegram = TRUE,
                          tg_dry_run    = FALSE,
                          factor_analysis = TRUE,
                          oos_split     = "2018-01-01") {  # IS/OOS 분할점 (전반/후반). EP 교훈: OOS retention 필수
  fe <- file.path(.AS_INFRA, "alpha_search", "fe_qmj.R")
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
  # 외부 데이터 의존: load_month_factors(C15 경유)만 사용 → forward-label 캐시 의존 없음.
  cat("[paper][PIT] factor_engine은 load_month_factors(C15) 경유 factor DB만 사용. 외부 forward-label cache 의존 없음.\n")
  cat("  -> Z_Score_Aligned는 Usable_Date<=sig_date IC로 방향정렬(C14), 재무 PIT(5월/45일 lag) factor DB 빌드 반영.\n")
  cat("  -> detect_lookahead 사각(fe_ml류 외부 .py) 해당 없음. NEGATE/FLIP 없음(C13, alignment 자동).\n")

  # ---- 4. Backtest: pure 월간 top-decile EW (buffer 없음, weight=equal) ----
  sim <- run_monthly_simulation(
    RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
    n_holdings = 50L,            # N 컬럼이 매월 override (decile). fallback only.
    weight_method = "equal",     # 논문: equal-weight
    commission = commission,
    buffer_zone = NULL)          # 논문: 순수 월간 리밸런싱 (turnover-buffer 없음)

  # ---- 5. Charts ----
  generate_charts(sim, output_dir = OUT_DIR, strategy_name = strategy_name)
  charts <- Filter(file.exists, file.path(OUT_DIR, c("equity_curve.png","annual_returns.png")))

  # ---- 6. 스코어링 ----
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

  # ---- 6c. ★ 직교성 평가: OOS retention + STR_1715/풀 상관 ----
  ortho <- tryCatch(.qmj_orthogonality(sim, oos_split = oos_split, out_dir = OUT_DIR),
                    error = function(e) { cat("[paper][직교성] 산출 실패:", conditionMessage(e), "\n"); NULL })
  if (!is.null(ortho)) {
    cat(sprintf("[paper][직교성] IS Sharpe=%.3f | OOS Sharpe=%.3f | OOS retention=%.3f | cor(STR_1715)=%.3f\n",
                ortho$is_sharpe %||% NA, ortho$oos_sharpe %||% NA,
                ortho$oos_retention %||% NA, ortho$cor_str1715 %||% NA))
    saveRDS(ortho, file.path(OUT_DIR, "orthogonality.rds"))
    write_json(ortho, file.path(OUT_DIR, "orthogonality.json"), auto_unbox = TRUE, digits = 5)
  }

  pass    <- grade %in% c("A","A_NOVEL","A_DEF")
  is_fail <- grade %in% c("F")
  notable <- grade %in% c("B","C") || (is_fail && isTRUE(pit$clean))
  cat(sprintf("[paper] Grade=%s Score=%.0f Excess=%+.2f%%p | pass=%s notable=%s\n",
              grade, score %||% 0, excess_cagr %||% 0, pass, notable))

  # ---- 6d. FR 모듈 등재 (등급무관) ----
  tryCatch({
    source(file.path(.AS_INFRA, "contracts", "register_module.R"))
    register_module(sim, strategy_id, grade = grade, origin_mode = "alpha_search",
                    role = NA_character_, meta = list(strategy_idea = strategy_idea, score = score))
    assign("%||%", `%||%`, envir = globalenv())
  }, error = function(e) cat("[paper] register_module 생략:", conditionMessage(e), "\n"))

  # ---- 7. Telegram ----
  if (isTRUE(send_telegram)) {
    .send_alpha_search_brief(strategy_name, strategy_idea, strategy_id, grade, score,
                             m, sdef, excess_cagr, charts, universe = "K200_KQ150",
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
                 rank_ic = .as_num(m$IC %||% m$Rank_IC),
                 port_t = .as_num(m$Portfolio_Alpha_t %||% m$Harvey_t),
                 orthogonality = ortho))
}

# ---- 직교성 산출 헬퍼: PerformanceAnalytics 표준함수만 (자체합성 금지) ----
.qmj_orthogonality <- function(sim, oos_split = "2018-01-01", out_dir = NULL) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
  stopifnot(!is.null(sim$strategy_xts))
  # 일간 → 월간 (PerformanceAnalytics apply.monthly + Return.cumulative — 자체합성 아님)
  d_xts  <- sim$strategy_xts
  m_xts  <- apply.monthly(d_xts, function(x) Return.cumulative(x))
  m_xts  <- m_xts[is.finite(coredata(m_xts))]
  storage.mode(oos_split) <- "character"
  split_d <- as.Date(oos_split)
  is_x  <- m_xts[index(m_xts) <  split_d]
  oos_x <- m_xts[index(m_xts) >= split_d]
  # 월간 Sharpe annualized (PerformanceAnalytics SharpeRatio.annualized)
  is_sr  <- if (length(is_x)  >= 6) as.numeric(SharpeRatio.annualized(is_x,  scale = 12)) else NA_real_
  oos_sr <- if (length(oos_x) >= 6) as.numeric(SharpeRatio.annualized(oos_x, scale = 12)) else NA_real_
  oos_ret <- if (is.finite(is_sr) && abs(is_sr) > 1e-6) oos_sr / is_sr else NA_real_

  # STR_1715 월간 ret_net 상관
  cor_1715 <- NA_real_; n_overlap_1715 <- 0L
  bt1715 <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                      "04_Research", "strategies", "STR_1715_WT016_Iter31_GridBestProd",
                      "output", "bt_result.rds")
  if (file.exists(bt1715)) {
    pr <- as.data.table(readRDS(bt1715)$period_returns)
    if (all(c("date","ret_net") %in% names(pr))) {
      pr[, ym := format(as.Date(date), "%Y-%m")]
      qm <- data.table(date = index(m_xts), r = as.numeric(coredata(m_xts)))
      qm[, ym := format(date, "%Y-%m")]
      mg <- merge(qm[, .(ym, r_qmj = r)], pr[, .(ym, r_1715 = ret_net)], by = "ym")
      n_overlap_1715 <- nrow(mg)
      if (n_overlap_1715 >= 12) cor_1715 <- cor(mg$r_qmj, mg$r_1715, use = "complete.obs")
    }
  }

  # 풀 상관: module_performance 등 별도 raw 월간 시계열이 통일 안 돼 STR_1715 단일대표로 보고(풀 proxy).
  list(is_sharpe = round(is_sr, 4), oos_sharpe = round(oos_sr, 4),
       oos_retention = round(oos_ret, 4), oos_split = as.character(split_d),
       n_is_months = length(is_x), n_oos_months = length(oos_x),
       cor_str1715 = round(cor_1715, 4), n_overlap_1715 = n_overlap_1715)
}
