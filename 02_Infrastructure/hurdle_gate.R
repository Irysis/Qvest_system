#==============================================================================
# Quant Module — QEPM Hurdle Gate
# Version: 2.1.0 (Sharpe-primary scoring)
#
# Automated strategy evaluation based on QEPM Lawbook v1.1 criteria.
# Hard FAIL → immediate rejection (Standalone).
# Soft Score → 0-100 composite quality score.
# 3-Tier Grade: A (Standalone) / B (Component) / C (Ensemble) / F (Fail)
#
# ⚠️ DEMOTED 2026-05-31 (Dual-Mode SOT §3.5, 도훈 mandate): 본 18-component
#    composite score/grade는 prod(1+r)·수동 Sharpe·full-sample β 기반 = proxy.
#    **DIAGNOSTIC ONLY — 권위 등급 아님.** 권위 등급 = essence_score()
#    (02_Infrastructure/contracts/essence_score.R, 계약 bt_result PORT_t/DSR 기반).
#    반환값에 authoritative=FALSE, grade_basis="proxy_diagnostic_18component" 부착.
# 5-Axis Profile: Return, Risk, Robustness, Implementability, Diversification
# Role Label: core / defensive / diversifier
#
# Usage:
#   source("hurdle_gate.R")
#   result <- run_hurdle_gate(sim_result, FACTORS, strategy_name = "STR_001")
#   # result$pass     — TRUE/FALSE
#   # result$score    — 0-100
#   # result$verdict  — JSON-serializable list
#
# Diagnostic Codes:
#   D001-D010: Hard fail diagnostics
#   D011-D030: Performance diagnostics
#   D031-D040: Risk diagnostics
#   D041-D050: Robustness diagnostics
#   D051-D060: Structural diagnostics
#   D061-D070: Temporal diagnostics (alpha trend)
#   D071-D080: Statistical defense diagnostics (DSR, family trials)
#   D081-D083: Diversification diagnostics (correlation, novelty, saturation)
#   D084-D086: Risk engine diagnostics (tail risk, stress severity, coherence)
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(sys.frame(1)$ofile %||% "."), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(PerformanceAnalytics)
  library(xts)
  library(jsonlite)
})

# --- Source statistical defense module ---
stat_defense_path <- file.path(dirname(sys.frame(1)$ofile %||% "."), "validation", "statistical_defense.R")
if (file.exists(stat_defense_path)) source(stat_defense_path)

# --- Source verification pipeline ---
verification_path <- file.path(dirname(sys.frame(1)$ofile %||% "."), "validation", "verification_pipeline.R")
if (file.exists(verification_path)) source(verification_path)

# --- Rcpp 가속: hurdle_gate_perf.cpp (stress 집계 + rolling Sharpe/MDD) ---
# 컴파일 실패 시 자동으로 R fallback 사용 (경고만 발생, 중단 없음)
.hg_rcpp_loaded <- FALSE
tryCatch({
  suppressPackageStartupMessages(library(Rcpp))
  # sys.frame(1)$ofile은 source() 직접 호출 시에만 유효 → PROJECT_ROOT 우선
  .hg_infra_dir <- if (exists("PROJECT_ROOT") && nzchar(PROJECT_ROOT)) {
    file.path(PROJECT_ROOT, "02_Infrastructure")
  } else {
    tryCatch(dirname(sys.frame(1)$ofile),
             error = function(e) file.path(
               Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
               "02_Infrastructure"
             ))
  }
  .hg_cpp_path <- file.path(.hg_infra_dir, "hurdle_gate_perf.cpp")
  if (file.exists(.hg_cpp_path)) {
    Rcpp::sourceCpp(.hg_cpp_path, verbose = FALSE, rebuild = FALSE)
    .hg_rcpp_loaded <- TRUE
    cat("[hurdle_gate] Rcpp 가속 로드 완료 (stress_periods_cpp, rolling_sharpe_cpp, rolling_mdd_cpp)\n")
  }
}, error = function(e) {
  warning("[hurdle_gate] Rcpp 컴파일 실패 — R fallback 사용: ", conditionMessage(e))
})

# --- R fallback 구현 (Rcpp 없을 때 사용) ---
if (!.hg_rcpp_loaded) {
  # stress_periods_cpp R 버전: 루프이지만 xts 슬라이싱 활용 (기존 코드와 동일 로직)
  stress_periods_cpp <- function(dates, strat_ret, bm_ret, starts, ends) {
    k <- length(starts)
    sc <- bm <- al <- mdd_v <- rep(NA_real_, k)
    outperf <- rep(NA, k)
    n_obs_v <- integer(k)
    for (p in seq_len(k)) {
      idx <- which(dates >= starts[p] & dates <= ends[p])
      if (length(idx) < 10) next
      rs <- strat_ret[idx]; rb <- bm_ret[idx]
      rs[is.na(rs)] <- 0; rb[is.na(rb)] <- 0
      sc[p]      <- prod(1 + rs) - 1
      bm[p]      <- prod(1 + rb) - 1
      al[p]      <- sc[p] - bm[p]
      nav_s      <- cumprod(1 + rs)
      pk         <- cummax(nav_s)
      mdd_v[p]   <- max((pk - nav_s) / pk, na.rm = TRUE)
      outperf[p] <- sc[p] > bm[p]
      n_obs_v[p] <- length(idx)
    }
    list(strat_cum=sc, bm_cum=bm, alpha=al, strat_mdd=mdd_v, outperform=outperf, n_obs=n_obs_v)
  }

  # rolling_sharpe_cpp R 버전: data.table frollsum + frollapply 활용
  # frollapply: 'N' 사용 (n은 deprecated in data.table >= 1.15)
  rolling_sharpe_cpp <- function(ret, window, ann_factor = 252) {
    n_obs <- length(ret)
    if (n_obs < window) return(rep(NA_real_, n_obs))
    log1r   <- log1p(pmax(ret, -0.9999))
    sum_log <- data.table::frollsum(log1r, n = window, na.rm = TRUE, align = "right")
    cagr    <- expm1(sum_log * ann_factor / window)
    ann_vol <- tryCatch(
      data.table::frollapply(ret, N = window, align = "right",
                             FUN = function(v) sd(v, na.rm = TRUE)) * sqrt(ann_factor),
      error = function(e)
        data.table::frollapply(ret, n = window, align = "right",
                               FUN = function(v) sd(v, na.rm = TRUE)) * sqrt(ann_factor)
    )
    ifelse(!is.na(ann_vol) & ann_vol > 1e-8, cagr / ann_vol, NA_real_)
  }

  # rolling_mdd_cpp R 버전 (N 우선, n fallback)
  rolling_mdd_cpp <- function(ret, window) {
    mdd_fn <- function(v) {
      nav <- cumprod(1 + v); pk <- cummax(nav)
      max((pk - nav) / pk, na.rm = TRUE)
    }
    tryCatch(
      data.table::frollapply(ret, N = window, align = "right", FUN = mdd_fn),
      error = function(e)
        data.table::frollapply(ret, n = window, align = "right", FUN = mdd_fn)
    )
  }
}

cat("[hurdle_gate] Loaded.\n")

# 한국 long-only alpha-search에서는 overlay 없이 한두 번의 시장 동반 폭락을 맞는 것이
# 흔하다. 따라서 MDD 깊이만으로 즉시 F 처리하지 않고, 심각 drawdown의 빈도/지속성을
# 함께 본다. 구조적으로 반복 붕괴하는 경우만 hard fail로 승격한다.
.drawdown_frequency_profile <- function(ret_xts, bm_xts = NULL,
                                        severe = 0.45, extreme = 0.55,
                                        catastrophic = 0.70,
                                        severe_hard_count = 15L,
                                        extreme_hard_count = 6L,
                                        severe_day_hard_frac = 0.25,
                                        severe_max_hard_days = 252L) {
  r <- as.numeric(ret_xts)
  r <- r[is.finite(r)]
  n <- length(r)
  if (n == 0L) {
    return(list(
      mdd = NA_real_, severe_count = 0L, extreme_count = 0L,
      catastrophic = FALSE, severe_total_days = 0L, severe_max_days = 0L,
      severe_day_frac = NA_real_, underwater20_frac = NA_real_,
      crash_frequency_score = NA_real_, tail_review = FALSE,
      structural_hard_fail = FALSE,
      catastrophic_threshold = catastrophic,
      severe_hard_count = severe_hard_count,
      extreme_hard_count = extreme_hard_count,
      severe_day_hard_frac = severe_day_hard_frac,
      severe_max_hard_days = severe_max_hard_days
    ))
  }
  nav <- cumprod(1 + pmax(r, -0.9999))
  dd <- nav / cummax(nav) - 1
  mdd <- abs(min(dd, na.rm = TRUE))

  .episodes <- function(th) {
    flag <- is.finite(dd) & dd <= -th
    if (!any(flag)) return(list(count = 0L, total_days = 0L, max_days = 0L))
    rr <- rle(flag)
    lens <- rr$lengths[rr$values]
    list(count = length(lens), total_days = sum(lens), max_days = max(lens))
  }
  e35 <- .episodes(0.35)
  e45 <- .episodes(severe)
  e55 <- .episodes(extreme)
  uw20 <- mean(is.finite(dd) & dd <= -0.20)

  # 빈도 점수: 2026-06-12 KR baseline 기준 보정.
  # 2005+ BM 45%+ episodes=8, K200/KQ150 EW=6, strategy-output q75=5/q90=14.
  # 따라서 3회는 시장 평균권도 벌점화해 과징벌이므로, hard fail은 q90 초과권부터 적용한다.
  freq_score <- 10 -
    min(6, e35$count) * 0.35 -
    min(severe_hard_count, e45$count) * 0.30 -
    min(extreme_hard_count, e55$count) * 0.65 -
    min(0.5, uw20) * 4.00
  freq_score <- max(0, min(10, freq_score))

  structural_hard_fail <- isTRUE(
    is.finite(mdd) && (
      mdd >= catastrophic ||
        e45$count >= severe_hard_count ||
        e55$count >= extreme_hard_count ||
        (n > 0L && e45$total_days / n >= severe_day_hard_frac) ||
        e45$max_days >= severe_max_hard_days
    )
  )
  tail_review <- isTRUE(is.finite(mdd) && mdd > severe && !structural_hard_fail)

  list(
    mdd = mdd,
    severe35_count = e35$count,
    severe_count = e45$count,
    extreme_count = e55$count,
    catastrophic = isTRUE(is.finite(mdd) && mdd >= catastrophic),
    severe_total_days = e45$total_days,
    severe_max_days = e45$max_days,
    severe_day_frac = if (n > 0L) e45$total_days / n else NA_real_,
    underwater20_frac = uw20,
    crash_frequency_score = freq_score,
    catastrophic_threshold = catastrophic,
    severe_hard_count = severe_hard_count,
    extreme_hard_count = extreme_hard_count,
    severe_day_hard_frac = severe_day_hard_frac,
    severe_max_hard_days = severe_max_hard_days,
    tail_review = tail_review,
    structural_hard_fail = structural_hard_fail
  )
}

#==============================================================================
# Auto Lesson Generation (memory cycle Phase 1)
#==============================================================================

.generate_auto_lessons <- function(verdict, strategy_name) {
  lessons <- character(0)
  m <- verdict$metrics
  grade <- verdict$grade
  score <- verdict$total_score

  # Grade A achievement
  if (identical(grade, "A")) {
    lessons <- c(lessons, sprintf(
      "%s Grade A(%.1f): SR %.3f, CAGR %.1f%%, MDD %.1f%%",
      strategy_name, score,
      as.numeric(m$Sharpe %||% 0),
      as.numeric(m$CAGR %||% 0),
      as.numeric(m$MDD %||% 0)
    ))
  }

  # Hard FAIL reason
  if (isTRUE(verdict$hard_fail)) {
    reasons <- paste(verdict$fail_reasons, collapse = "; ")
    lessons <- c(lessons, sprintf("%s HARD FAIL: %s", strategy_name, reasons))
  }

  # OOS degradation
  oos_val <- tryCatch(
    as.numeric(verdict$score_breakdown$oos$value),
    error = function(e) NA_real_
  )
  if (!is.na(oos_val) && oos_val < 0.4) {
    lessons <- c(lessons, sprintf(
      "%s OOS retention %.2f = overfitting suspected",
      strategy_name, oos_val
    ))
  }

  # Alpha trend decay
  at_val <- tryCatch(
    as.numeric(verdict$score_breakdown$alpha_trend$value),
    error = function(e) NA_real_
  )
  if (!is.na(at_val) && at_val < 0.5) {
    lessons <- c(lessons, sprintf(
      "%s alpha decay: trend ratio %.2f",
      strategy_name, at_val
    ))
  }

  lessons
}

#==============================================================================
# run_hurdle_gate() — Main evaluation function
#==============================================================================

run_hurdle_gate <- function(sim_result,
                             FACTORS = NULL,
                             strategy_name = "Unknown",
                             catalog_strategy_id = NULL,
                             strategy_file = NULL,
                             output_dir = NULL,
                             ff5_result = NULL,
                             strict_mode = as.logical(Sys.getenv("QVEST_STRICT_MODE", "TRUE"))) {

  turnover_hard_fail_pct <- 1100
  strat_xts <- sim_result$strategy_xts
  bm_xts    <- sim_result$bm_xts
  NAV_DT    <- sim_result$DAILY_NAV_DT
  PLOG      <- sim_result$PORTFOLIO_LOG

  merged <- merge(strat_xts, bm_xts, join = "inner")
  if (nrow(merged) < 60) {
    return(list(
      pass = FALSE, score = 0,
      verdict = list(
        strategy = strategy_name,
        hard_fail = TRUE,
        fail_reason = "Insufficient data (< 60 trading days)",
        diagnostics = list(list(code = "D001", msg = "Insufficient backtest length"))
      )
    ))
  }

  diagnostics <- list()
  hard_fail   <- FALSE
  fail_reasons <- character(0)

  # ==========================================================================
  # GATE 0: VALIDITY (auto PIT/survivorship/data quality)
  # ==========================================================================

  # --- D000: PIT Enforcement — factor signals must precede execution ---
  if (!is.null(FACTORS) && nrow(PLOG) > 0) {
    # (v8.2.1 2026-07-04 수리) 구 로직은 exec_dates[exec_dates > fd] 필터 후 min(.) < fd
    # 비교여서 위반 카운트가 구조적으로 0 (회귀 스위트 H6가 노출한 결함 — look-ahead가
    # 스크리닝을 통과). PLOG 행 단위 Signal_Date/Exec_Date 직접 대조로 교체:
    # 집행일이 신호일과 같거나 앞서면 위반 (C2 same-day / C5 t-1 lag 규약).
    if (all(c("Signal_Date", "Exec_Date") %in% names(PLOG))) {
      # (1) 행 단위: 집행이 신호와 같은 날이거나 앞서면 위반 (C2 same-day / C5 t-1)
      n_pit_violations <- sum(as.Date(PLOG$Exec_Date) <= as.Date(PLOG$Signal_Date),
                              na.rm = TRUE)
      # (2) 팩터 시점축: k번째 팩터 스냅샷 날짜가 k번째 집행일과 같거나 이후면
      #     집행에 미래 데이터 사용 (월간 리밸 순서 정렬 대응 — H6 픽스처 계열)
      fdx   <- sort(unique(as.Date(FACTORS$Date)))
      exe_v <- sort(as.Date(PLOG$Exec_Date))
      m <- min(length(fdx), length(exe_v))
      if (m > 0) {
        n_pit_violations <- n_pit_violations +
          sum(fdx[seq_len(m)] >= exe_v[seq_len(m)], na.rm = TRUE)
      }
    } else {
      n_pit_violations <- 0L
      diagnostics <- c(diagnostics, list(list(
        code = "D000a",
        msg  = "PIT check SKIP — PLOG lacks Signal_Date/Exec_Date columns (판정 불가)"
      )))
    }
    if (n_pit_violations > 0) {
      hard_fail <- TRUE
      fail_reasons <- c(fail_reasons,
                         sprintf("PIT violation: %d signals with future data", n_pit_violations))
      diagnostics <- c(diagnostics, list(list(
        code = "D000", msg = sprintf("PIT violation: %d signals", n_pit_violations)
      )))
    } else {
      diagnostics <- c(diagnostics, list(list(
        code = "D000", msg = "PIT check PASS — all signals precede execution"
      )))
    }
  }

  # --- D001a: Data Coverage — strategy must span ≥ 5 years ---
  backtest_years <- as.numeric(difftime(max(NAV_DT$Date), min(NAV_DT$Date),
                                         units = "days")) / 365.25
  if (backtest_years < 5) {
    diagnostics <- c(diagnostics, list(list(
      code = "D001a",
      msg = sprintf("Short backtest: %.1f years (5Y+ recommended)", backtest_years)
    )))
  }

  # ==========================================================================
  # HARD FAIL CHECKS
  # ==========================================================================

  # --- D002: Annualized turnover > 1,100% ---
  n_rebal <- nrow(PLOG)
  n_years <- as.numeric(difftime(max(NAV_DT$Date), min(NAV_DT$Date),
                                  units = "days")) / 365.25
  # Use actual tracked turnover if available (buffer_zone aware)
  if ("Turnover_Pct" %in% names(PLOG) && n_years > 0) {
    ann_turnover <- sum(PLOG$Turnover_Pct, na.rm = TRUE) / n_years
  } else {
    ann_turnover <- if (n_years > 0) (n_rebal / n_years) * 100 else 0
  }

  if (ann_turnover > turnover_hard_fail_pct) {
    hard_fail <- TRUE
    fail_reasons <- c(fail_reasons,
                       sprintf("Turnover %.0f%% > %.0f%%", ann_turnover, turnover_hard_fail_pct))
    diagnostics <- c(diagnostics, list(list(
      code = "D002",
      msg = sprintf("Excessive turnover: %.0f%% > %.0f%%",
                    ann_turnover, turnover_hard_fail_pct)
    )))
  }

  # --- D003: Top 10 concentration > 70% ---
  # Check the last rebalance weights
  top10_conc <- NA_real_
  if (!is.null(FACTORS) && nrow(PLOG) > 0) {
    last_sig <- max(PLOG$Signal_Date)
    last_factors <- FACTORS[Date == last_sig & !is.na(Score)]
    if (nrow(last_factors) > 0) {
      setorder(last_factors, -Score)
      n_selected <- min(nrow(last_factors), 20)
      # Equal weight approximation for concentration check
      top10_conc <- min(10, n_selected) / n_selected * 100
    }
  }
  if (!is.na(top10_conc) && top10_conc > 70) {
    hard_fail <- TRUE
    fail_reasons <- c(fail_reasons,
                       sprintf("Top 10 concentration %.1f%% > 70%%", top10_conc))
    diagnostics <- c(diagnostics, list(list(
      code = "D003", msg = sprintf("Top 10 concentration: %.1f%%", top10_conc)
    )))
  }

  # --- D004: Drawdown structure ---
  dd_profile <- .drawdown_frequency_profile(strat_xts, bm_xts)
  mdd <- as.numeric(dd_profile$mdd)
  if (is.finite(mdd) && mdd > 0.45 && isTRUE(dd_profile$structural_hard_fail)) {
    dd_hard_causes <- character(0)
    if (isTRUE(dd_profile$catastrophic)) {
      dd_hard_causes <- c(dd_hard_causes,
                          sprintf("MDD>=%.0f%%", dd_profile$catastrophic_threshold * 100))
    }
    if (dd_profile$severe_count >= dd_profile$severe_hard_count) {
      dd_hard_causes <- c(dd_hard_causes,
                          sprintf("45%%+ episodes>=%d", dd_profile$severe_hard_count))
    }
    if (dd_profile$extreme_count >= dd_profile$extreme_hard_count) {
      dd_hard_causes <- c(dd_hard_causes,
                          sprintf("55%%+ episodes>=%d", dd_profile$extreme_hard_count))
    }
    if (is.finite(dd_profile$severe_day_frac) &&
        dd_profile$severe_day_frac >= dd_profile$severe_day_hard_frac) {
      dd_hard_causes <- c(dd_hard_causes,
                          sprintf("45%%+ days>=%.0f%%", dd_profile$severe_day_hard_frac * 100))
    }
    if (dd_profile$severe_max_days >= dd_profile$severe_max_hard_days) {
      dd_hard_causes <- c(dd_hard_causes,
                          sprintf("max_underwater>=%dd", dd_profile$severe_max_hard_days))
    }
    if (!length(dd_hard_causes)) dd_hard_causes <- "threshold exceeded"
    hard_fail <- TRUE
    fail_reasons <- c(fail_reasons,
                       sprintf("Structural drawdown (%s): MDD %.1f%%, 45%%+ episodes=%d/%d, max_underwater=%d/%d",
                               paste(dd_hard_causes, collapse = ", "),
                               mdd * 100, dd_profile$severe_count, dd_profile$severe_hard_count,
                               dd_profile$severe_max_days, dd_profile$severe_max_hard_days))
    diagnostics <- c(diagnostics, list(list(
      code = "D004",
      msg = sprintf("Structural drawdown hard fail: MDD %.1f%%, 45%%+ episodes=%d/%d, 55%%+ episodes=%d/%d, 45%%+ days=%d",
                    mdd * 100, dd_profile$severe_count, dd_profile$severe_hard_count,
                    dd_profile$extreme_count, dd_profile$extreme_hard_count,
                    dd_profile$severe_total_days)
    )))
  } else if (is.finite(mdd) && mdd > 0.45) {
    diagnostics <- c(diagnostics, list(list(
      code = "D004",
      msg = sprintf("Tail-review drawdown: MDD %.1f%% but not structural hard fail (45%%+ episodes=%d/%d, max_underwater=%dd)",
                    mdd * 100, dd_profile$severe_count, dd_profile$severe_hard_count,
                    dd_profile$severe_max_days)
    )))
  }

  # --- D005: Reproducibility (set.seed check) ---
  has_seed <- TRUE
  if (!is.null(strategy_file) && file.exists(strategy_file)) {
    code_text <- readLines(strategy_file, warn = FALSE)
    has_seed  <- any(grepl("set\\.seed", code_text))
    if (!has_seed) {
      hard_fail <- TRUE
      fail_reasons <- c(fail_reasons, "No set.seed() found")
      diagnostics <- c(diagnostics, list(list(
        code = "D005", msg = "Missing set.seed() — reproducibility not guaranteed"
      )))
    }
  }

  # ==========================================================================
  # SOFT SCORE (0-100)
  # ==========================================================================

  score_components <- list()

  # --- Performance metrics ---
  r <- strat_xts[!is.na(strat_xts)]
  n <- length(r)
  ann_ret  <- as.numeric((prod(1 + r))^(252 / n) - 1)
  ann_vol  <- as.numeric(sd(r) * sqrt(252))
  sharpe   <- ann_ret / ann_vol
  calmar   <- if (mdd > 0) ann_ret / mdd else 0

  # Excess return vs benchmark
  bm_r    <- bm_xts[!is.na(bm_xts)]
  bm_ann  <- as.numeric((prod(1 + bm_r))^(252 / length(bm_r)) - 1)
  excess  <- ann_ret - bm_ann

  # Tracking error & IR
  active_ret <- merged[, 1] - merged[, 2]
  te <- as.numeric(sd(active_ret) * sqrt(252))
  ir <- if (te > 0) excess / te else 0

  # --- D011: Net Sharpe (0-15 pts) — balanced, not dominant ---
  # Reduced from 25 to 15 to allow high-CAGR/high-Vol strategies a fair chance
  sharpe_score <- min(15, max(0, (sharpe - 0.3) / (1.5 - 0.3) * 15))
  score_components$sharpe <- list(
    score = round(sharpe_score, 1),
    max = 15,
    value = round(sharpe, 3),
    code = "D011"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D011", msg = sprintf("Net Sharpe: %.3f (%.1f/15 pts)", sharpe, sharpe_score)
  )))

  # --- D012: Net IR (0-10 pts) ---
  ir_score <- min(10, max(0, (ir - 0.2) / (1.2 - 0.2) * 10))
  score_components$ir <- list(
    score = round(ir_score, 1), max = 10,
    value = round(ir, 3), code = "D012"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D012", msg = sprintf("Net IR: %.3f (%.1f/10 pts)", ir, ir_score)
  )))

  # --- D013: Net CAGR (0-15 pts, target 16%) — increased to reward high-return strategies ---
  cagr_score <- min(15, max(0, (ann_ret - 0.05) / (0.30 - 0.05) * 15))
  score_components$cagr <- list(
    score = round(cagr_score, 1), max = 15,
    value = round(ann_ret * 100, 2), code = "D013"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D013",
    msg = sprintf("Net CAGR: %.2f%% (%.1f/15 pts, target 16%%)",
                  ann_ret * 100, cagr_score)
  )))

  # --- D014: Calmar ratio (0-10 pts) ---
  calmar_score <- min(10, max(0, (calmar - 0.3) / (1.5 - 0.3) * 10))
  score_components$calmar <- list(
    score = round(calmar_score, 1), max = 10,
    value = round(calmar, 3), code = "D014"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D014", msg = sprintf("Calmar: %.3f (%.1f/10 pts)", calmar, calmar_score)
  )))

  # --- D031: Drawdown depth/frequency score (0-10 pts, higher is better) ---
  # MDD depth still matters, but repeated/severe underwater episodes carry more information
  # than a single Korea-market crash with no overlay.
  mdd_depth_score <- min(10, max(0, (0.65 - mdd) / 0.55 * 10))
  mdd_freq_score  <- dd_profile$crash_frequency_score
  mdd_score <- 0.45 * mdd_depth_score + 0.55 * mdd_freq_score
  score_components$mdd <- list(
    score = round(mdd_score, 1), max = 10,
    value = round(mdd * 100, 2), code = "D031",
    depth_score = round(mdd_depth_score, 1),
    frequency_score = round(mdd_freq_score, 1),
    severe45_count = dd_profile$severe_count,
    severe55_count = dd_profile$extreme_count,
    severe45_max_days = dd_profile$severe_max_days,
    tail_review = isTRUE(dd_profile$tail_review)
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D031",
    msg = sprintf("Drawdown: MDD %.2f%%, 45%%+ episodes=%d, freq_score=%.1f, blended=%.1f/10",
                  mdd * 100, dd_profile$severe_count, mdd_freq_score, mdd_score)
  )))

  # --- D041: 3-year rolling Sharpe > 0 ratio (0-10 pts) — reduced from 15 ---
  rolling_sharpe_ratio <- NA_real_
  rolling_score <- 0
  if (n >= 252 * 3) {
    rolling_ann <- rollapply(strat_xts, 252 * 3, function(x) {
      ar <- (prod(1 + x))^(252 / length(x)) - 1
      av <- sd(x) * sqrt(252)
      ar / av
    }, by = 63, align = "right")
    rolling_sharpe_ratio <- mean(rolling_ann > 0, na.rm = TRUE)
    rolling_score <- min(10, rolling_sharpe_ratio * 10)
  }
  score_components$rolling <- list(
    score = round(rolling_score, 1), max = 10,
    value = round(rolling_sharpe_ratio, 3), code = "D041"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D041",
    msg = sprintf("3Y rolling Sharpe > 0 ratio: %.1f%% (%.1f/10 pts)",
                  rolling_sharpe_ratio * 100, rolling_score)
  )))

  # --- D043: 6M Rolling Return Hit Rate (diagnostic + axis) ---
  rolling_6m_hit <- NA_real_
  worst_6m_ret   <- NA_real_
  if (n >= 126) {
    rolling_6m <- rollapply(strat_xts, 126, function(x) as.numeric(prod(1 + x) - 1),
                            by = 21, align = "right")
    rolling_6m_hit <- mean(rolling_6m > 0, na.rm = TRUE)
    worst_6m_ret   <- as.numeric(min(rolling_6m, na.rm = TRUE))
  }
  diagnostics <- c(diagnostics, list(list(
    code = "D043",
    msg = sprintf("6M Rolling Hit Rate: %.1f%% | Worst 6M Return: %.2f%%",
                  ifelse(is.na(rolling_6m_hit), 0, rolling_6m_hit * 100),
                  ifelse(is.na(worst_6m_ret), 0, worst_6m_ret * 100))
  )))

  # --- D045: Max Consecutive Negative Alpha Months ---
  max_consec_neg_alpha <- 0L
  if (nrow(merged) >= 60) {
    monthly_alpha <- tryCatch({
      as.numeric(apply.monthly(merged[, 1] - merged[, 2], Return.cumulative))
    }, error = function(e) numeric(0))
    if (length(monthly_alpha) > 0) {
      neg_run <- 0L; max_run <- 0L
      for (val in monthly_alpha) {
        if (!is.na(val) && val < 0) {
          neg_run <- neg_run + 1L
          max_run <- max(max_run, neg_run)
        } else {
          neg_run <- 0L
        }
      }
      max_consec_neg_alpha <- max_run
    }
  }
  diagnostics <- c(diagnostics, list(list(
    code = "D045",
    msg = sprintf("Max Consecutive Negative Alpha Months: %d", max_consec_neg_alpha)
  )))

  # --- D046: 12M Rolling Hit Rate ---
  rolling_12m_hit <- NA_real_
  if (n >= 252) {
    rolling_12m <- rollapply(strat_xts, 252, function(x) as.numeric(prod(1 + x) - 1),
                             by = 21, align = "right")
    rolling_12m_hit <- mean(rolling_12m > 0, na.rm = TRUE)
  }
  diagnostics <- c(diagnostics, list(list(
    code = "D046",
    msg = sprintf("12M Rolling Hit Rate: %.1f%%",
                  ifelse(is.na(rolling_12m_hit), 0, rolling_12m_hit * 100))
  )))

  # --- D051: Parameter penalty (0-5 pts, fewer is better) ---
  # Estimated from the number of holdings as proxy
  avg_holdings <- if (nrow(PLOG) > 0) mean(PLOG$N_stocks) else 20
  param_score  <- 5  # default full score; deducted if complex
  score_components$params <- list(
    score = round(param_score, 1), max = 5,
    value = avg_holdings, code = "D051"
  )

  # --- D042: Stress period performance (0-10 pts) ---
  # 벡터화: stress_periods_cpp()로 루프 제거 (Rcpp 또는 R fallback 자동 선택)
  stress_score <- 0
  .d42_starts <- as.numeric(as.Date(c("2007-10-01", "2020-01-01", "2022-01-01")))
  .d42_ends   <- as.numeric(as.Date(c("2009-03-31", "2020-06-30", "2022-12-31")))
  .d42_dates  <- as.numeric(as.Date(index(merged)))
  .d42_sr     <- as.numeric(merged[, 1])
  .d42_br     <- as.numeric(merged[, 2])
  .d42_res    <- stress_periods_cpp(.d42_dates, .d42_sr, .d42_br, .d42_starts, .d42_ends)
  n_stress    <- sum(!is.na(.d42_res$strat_cum) & .d42_res$n_obs >= 10L)
  # stress_periods_cpp는 LogicalVector 반환 → as.logical() 후 NA 제거 후 합산
  n_outperform <- sum(as.logical(.d42_res$outperform), na.rm = TRUE)
  if (n_stress > 0) {
    stress_score <- (n_outperform / n_stress) * 10
  }
  score_components$stress <- list(
    score = round(stress_score, 1), max = 10,
    value = sprintf("%d/%d outperform", n_outperform, n_stress),
    code = "D042"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D042",
    msg = sprintf("Stress outperformance: %d/%d (%.1f/10 pts)",
                  n_outperform, n_stress, stress_score)
  )))

  # --- D061: Alpha Trend — 최근 3Y Sharpe vs 전체기간 Sharpe (-10 ~ +10 pts) ----
  # ratio ≥ 1.5 → +10 (알파 부활), ratio = 1.0 → 0 (안정), ratio ≤ 0.5 → -10 (소멸)
  # 최소 5Y 데이터 필요. 전체기간 Sharpe ≤ 0.1 이면 비교 불가 → neutral
  alpha_trend_adj   <- 0
  alpha_trend_ratio <- NA_real_
  recent_sharpe_val <- NA_real_
  alpha_trend_note  <- "Insufficient history (< 5Y required)"

  if (n >= 252 * 5) {
    r_recent          <- tail(r, 252 * 3)
    rc_ann            <- as.numeric((prod(1 + r_recent))^(252 / length(r_recent)) - 1)
    rc_vol            <- as.numeric(sd(r_recent) * sqrt(252))
    recent_sharpe_val <- if (rc_vol > 0) rc_ann / rc_vol else 0

    if (!is.na(sharpe) && sharpe > 0.1) {
      alpha_trend_ratio <- recent_sharpe_val / sharpe
      # Linear: ratio 1.5 → +10, ratio 1.0 → 0, ratio 0.5 → -10
      alpha_trend_adj <- max(-10, min(10, round((alpha_trend_ratio - 1.0) * 20, 1)))
      direction <- if (alpha_trend_adj > 1) "improving ↑" else
                   if (alpha_trend_adj < -1) "decaying ↓"  else "stable →"
      alpha_trend_note <- sprintf(
        "recent 3Y SR %.3f / full SR %.3f = ratio %.2f → %s",
        recent_sharpe_val, sharpe, alpha_trend_ratio, direction
      )
    } else {
      alpha_trend_note <- sprintf(
        "Full-period Sharpe %.3f ≤ 0.1 — trend comparison skipped", sharpe
      )
    }
  }

  score_components$alpha_trend <- list(
    score = alpha_trend_adj,   # range [-10, +10]; negative = penalty
    max   = 10,
    value = round(alpha_trend_ratio, 3),
    code  = "D061"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D061",
    msg  = sprintf("Alpha Trend: %s (adj %.1f pts)", alpha_trend_note, alpha_trend_adj)
  )))

  # --- D062: Out-of-Sample Validation (IS 65% / OOS 35% split) (-8 ~ +8 pts) ---
  # retention = OOS_Sharpe / IS_Sharpe
  # ≥ 0.7 → +8 (견고), 0.5 → 0 (중립), ≤ 0.3 → -8 (오버핏 의심)
  oos_adj  <- 0
  oos_note <- "Insufficient data (< 5Y)"
  oos_retention <- NA_real_

  if (n >= 252 * 5) {
    split_idx <- floor(n * 0.65)
    r_is  <- r[1:split_idx]
    r_oos <- r[(split_idx + 1):n]

    is_ann  <- as.numeric((prod(1 + r_is))^(252 / length(r_is)) - 1)
    is_vol  <- as.numeric(sd(r_is) * sqrt(252))
    is_sr   <- if (is_vol > 0) is_ann / is_vol else 0

    oos_ann <- as.numeric((prod(1 + r_oos))^(252 / length(r_oos)) - 1)
    oos_vol <- as.numeric(sd(r_oos) * sqrt(252))
    oos_sr  <- if (oos_vol > 0) oos_ann / oos_vol else 0

    if (!is.na(is_sr) && abs(is_sr) > 0.05) {
      oos_retention <- oos_sr / is_sr
      # clamp((retention - 0.5) * 40, -8, +8)
      oos_adj  <- max(-8, min(8, round((oos_retention - 0.5) * 40, 1)))
      direction <- if (oos_adj >= 3) "robust ↑" else
                   if (oos_adj <= -3) "degraded ↓" else "acceptable →"
      oos_note <- sprintf(
        "IS SR %.3f / OOS SR %.3f = retention %.2f → %s",
        is_sr, oos_sr, oos_retention, direction
      )
    } else {
      oos_note <- sprintf("IS Sharpe %.3f too low for meaningful split", is_sr)
    }
  }

  score_components$oos <- list(
    score = oos_adj,   # range [-8, +8]
    max   = 8,
    value = round(oos_retention, 3),
    code  = "D062"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D062",
    msg  = sprintf("OOS Validation: %s (adj %.1f pts)", oos_note, oos_adj)
  )))

  # --- D063: IC Stability — recent 3Y IC vs full IC (-6 ~ +6 pts) -----------
  # Reads analysis_ic.csv produced by strategy_analyzer.R (must run before hurdle_gate)
  # Requires ≥ 12 IC observations total. Annual strategies (< 12) → neutral.
  ic_adj  <- 0
  ic_note <- "analysis_ic.csv not found (run strategy_analyzer first)"

  if (!is.null(output_dir)) {
    ic_csv_path <- file.path(output_dir, "analysis_ic.csv")
    if (file.exists(ic_csv_path)) {
      ic_dt <- tryCatch(
        read.csv(ic_csv_path, stringsAsFactors = FALSE),
        error = function(e) NULL
      )
      if (!is.null(ic_dt) && nrow(ic_dt) >= 12 && "IC" %in% names(ic_dt)) {
        ic_dt$Signal_Date <- as.Date(ic_dt$Signal_Date)
        full_ic_mean   <- mean(ic_dt$IC, na.rm = TRUE)
        cutoff_3y      <- max(ic_dt$Signal_Date) - 365.25 * 3
        recent_ic_mean <- mean(ic_dt$IC[ic_dt$Signal_Date >= cutoff_3y], na.rm = TRUE)

        if (!is.na(full_ic_mean) && abs(full_ic_mean) > 0.005) {
          ic_ratio <- recent_ic_mean / full_ic_mean
          # clamp((ratio - 1.0) * 12, -6, +6)
          ic_adj <- max(-6, min(6, round((ic_ratio - 1.0) * 12, 1)))
          direction <- if (ic_adj >= 2) "IC improving ↑" else
                       if (ic_adj <= -2) "IC decaying ↓"  else "IC stable →"
          ic_note <- sprintf(
            "full IC %.4f / recent 3Y IC %.4f = ratio %.2f → %s",
            full_ic_mean, recent_ic_mean, ic_ratio, direction
          )
        } else {
          ic_note <- sprintf("Full-period IC %.4f near zero — comparison skipped", full_ic_mean)
        }
      } else if (!is.null(ic_dt)) {
        ic_note <- sprintf("Too few IC obs (%d) — need ≥ 12 (annual strategy)", nrow(ic_dt))
      }
    }
  }

  score_components$ic_stability <- list(
    score = ic_adj,   # range [-6, +6]
    max   = 6,
    value = ic_adj,
    code  = "D063"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D063",
    msg  = sprintf("IC Stability: %s (adj %.1f pts)", ic_note, ic_adj)
  )))

  # --- D071: Deflated Sharpe Ratio (score impact: 0 to -8 pts) ---
  dsr_value   <- NA_real_
  dsr_sig     <- FALSE
  dsr_note    <- "DSR module not available"
  sr_max_exp  <- NA_real_
  n_family_trials <- NA_integer_

  if (exists("compute_dsr") && is.function(compute_dsr)) {
    dsr_n_obs <- length(r)
    dsr_skew  <- tryCatch(as.numeric(skewness(r)), error = function(e) 0)
    dsr_ekurt <- tryCatch(as.numeric(kurtosis(r, method = "excess")), error = function(e) 0)
    if (is.na(dsr_skew)) dsr_skew <- 0
    if (is.na(dsr_ekurt)) dsr_ekurt <- 0

    n_family_trials <- 465L
    if (exists("load_family_trials") && is.function(load_family_trials)) {
      fam_data <- tryCatch(load_family_trials(), error = function(e) list())
      total_all_trials <- tryCatch(
        sum(vapply(fam_data, function(f) as.integer(f$total_trials %||% 0L), integer(1))),
        error = function(e) 0L
      )
      if (total_all_trials > 0) n_family_trials <- total_all_trials
    }

    dsr_result  <- compute_dsr(sharpe, dsr_n_obs, n_family_trials, dsr_skew, dsr_ekurt)
    dsr_value   <- dsr_result$dsr
    dsr_sig     <- dsr_result$significant
    sr_max_exp  <- dsr_result$sr_max_expected
    dsr_note    <- dsr_result$note
  }

  # Gate 4: DSR score impact (v1.4.2 — statistical defense affects score)
  dsr_score_adj <- 0
  if (!is.na(dsr_value)) {
    if (dsr_sig) {
      dsr_score_adj <- 0
    } else if (dsr_value >= 0.80) {
      dsr_score_adj <- -2
    } else if (dsr_value >= 0.50) {
      dsr_score_adj <- -5
    } else {
      dsr_score_adj <- -8
    }
  }
  score_components$dsr <- list(
    score = dsr_score_adj, max = 0,
    value = round(dsr_value, 4), code = "D071"
  )

  diagnostics <- c(diagnostics, list(list(
    code = "D071",
    msg  = sprintf("DSR: %s (score adj: %+d pts)", dsr_note, dsr_score_adj)
  )))

  # --- D081: Gate 5 — Diversification vs Existing Grade A (0 to -6 pts) ---
  # Check correlation with existing Grade A composite returns (if cached)
  div_gate_adj  <- 0
  div_gate_note <- "No Grade A composite cache"
  max_corr_with_a <- NA_real_
  grade_a_composite_path <- file.path(
    ifelse(exists("CACHE_DIR"), CACHE_DIR, ".cache"),
    "grade_a_composite_returns.parquet"
  )
  if (file.exists(grade_a_composite_path)) {
    tryCatch({
      ga_dt <- as.data.table(arrow::read_parquet(grade_a_composite_path))
      ga_xts <- xts(ga_dt$Ret, order.by = as.Date(ga_dt$Date))
      overlap <- merge(strat_xts, ga_xts, join = "inner")
      if (nrow(overlap) >= 252) {
        max_corr_with_a <- as.numeric(cor(
          as.numeric(overlap[, 1]), as.numeric(overlap[, 2]),
          use = "complete.obs"
        ))
        if (!is.na(max_corr_with_a)) {
          if (max_corr_with_a > 0.95) {
            div_gate_adj <- -6
            div_gate_note <- sprintf("Very high corr with Grade A composite: %.3f → redundant",
                                      max_corr_with_a)
          } else if (max_corr_with_a > 0.85) {
            div_gate_adj <- -3
            div_gate_note <- sprintf("High corr with Grade A composite: %.3f", max_corr_with_a)
          } else {
            div_gate_note <- sprintf("Acceptable diversification vs Grade A: corr %.3f",
                                      max_corr_with_a)
          }
        }
      }
    }, error = function(e) NULL)
  }

  score_components$div_gate <- list(
    score = div_gate_adj, max = 0,
    value = round(max_corr_with_a, 3), code = "D081"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D081",
    msg  = sprintf("Gate 5 (Diversification): %s (adj %+d pts)", div_gate_note, div_gate_adj)
  )))

  # --- D082: Novelty Bonus (v2.2 — new alpha source reward) ---
  novelty_bonus <- 0L
  novelty_detail <- list(max_corr = NA_real_, independence = "unknown",
                         family_grade_a = NA_integer_, fmb_t = NA_real_,
                         bonus_base = 0L, fmb_multiplier = 1.0)

  # Read s3 orthogonality artifact if available
  s3_art_dir <- file.path(dirname(output_dir), "stage_artifacts")
  s3_files <- list.files(s3_art_dir, pattern = "^s3_orthogonality.*\\.json$", full.names = TRUE)
  if (length(s3_files) > 0) {
    s3_data <- tryCatch(fromJSON(s3_files[1], simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(s3_data)) {
      s3_corr <- s3_data$max_abs_corr_db %||% 1.0
      s3_class <- s3_data$independence_class %||% "redundant"
      novelty_detail$max_corr <- s3_corr
      novelty_detail$independence <- s3_class
    }
  } else {
    # Fallback: use Grade A composite correlation as proxy
    if (!is.na(max_corr_with_a)) {
      novelty_detail$max_corr <- max_corr_with_a
      novelty_detail$independence <- if (max_corr_with_a < 0.3) "independent"
                                     else if (max_corr_with_a < 0.5) "partial"
                                     else "redundant"
    }
  }

  # Determine family + Grade A count by scanning factor_engine.R content
  family_ga_count <- 0L
  detected_family <- "unknown"

  .classify_alpha_family <- function(strategy_dir, strategy_name) {
    fe_path <- file.path(strategy_dir, "factor_engine.R")
    ra_path <- file.path(strategy_dir, "run_all.R")
    fe <- ""
    if (file.exists(fe_path)) fe <- tolower(paste(readLines(fe_path, warn = FALSE), collapse = " "))
    else if (file.exists(ra_path)) fe <- tolower(paste(readLines(ra_path, warn = FALSE), collapse = " "))
    sn <- tolower(strategy_name)

    if (grepl("d01_idiovol|d02_beta|idio.*vol|beta.*persist|ivol.*beta", fe) ||
        grepl("defense|brk0|dd[0-9]pct|noshortdd", sn)) return("defense")
    if (grepl("sleeve|regime.*alloc|ensemble|gerber|nco|bayesian.*bl|oas_minvar|hrp|daily.*regime", fe) ||
        grepl("sleeve|ensemble|gerber|nco|bl_hybrid|regime|oas|hrp", sn)) return("defense_ensemble")
    if (grepl("m07_indmom|industry.*mom", fe) || grepl("indmom", sn)) return("indmom")
    if (grepl("c19_composite|c13_.*revision|c10_sue|c07_esbr|c11_earning", fe) ||
        grepl("consensus|cons_", sn)) return("consensus")
    if (grepl("foreign.*flow|inv.*foreign|flow.*alpha", fe) || grepl("flow", sn)) return("flow")
    if (grepl("v14_ebit|v15_netdebt|pbr|per_|ep_", fe) || grepl("value|pbr|ep_", sn)) return("value")
    if (grepl("q04_piotroski|q07_earn|q11_net_margin|ac21_cf", fe) ||
        grepl("quality|piotroski|accrual", sn)) return("quality")
    if (grepl("d43_skew|r01_var|cvar|r03_cvar", fe) || grepl("risk|var95|cvar", sn)) return("risk")
    if (grepl("l31_vol_conc|l15_turnover", fe) || grepl("liquidity|turnover", sn)) return("liquidity")
    if (grepl("m25_earning|m10_intermediate|m21_season", fe) || grepl("momentum|streak", sn)) return("momentum")
    return("other")
  }

  .count_family_grade_a <- function(family, strat_root) {
    if (!dir.exists(strat_root)) return(0L)
    all_dirs <- list.dirs(strat_root, recursive = FALSE, full.names = TRUE)
    count <- 0L
    for (d in all_dirs) {
      hr <- file.path(d, "output", "hurdle_result.json")
      if (!file.exists(hr)) next
      j <- tryCatch(fromJSON(hr, simplifyVector = FALSE), error = function(e) NULL)
      if (is.null(j)) next
      g <- j$grade %||% j$verdict$grade %||% "?"
      if (g != "A") next
      fam <- .classify_alpha_family(d, basename(d))
      if (fam == family) count <- count + 1L
    }
    count
  }

  strat_dir <- dirname(output_dir)  # strategy root dir
  strat_root <- dirname(strat_dir)  # all strategies root
  detected_family <- .classify_alpha_family(strat_dir, strategy_name)

  # Cache family counts to avoid rescanning on every call
  if (!exists(".family_ga_cache", envir = .GlobalEnv)) {
    assign(".family_ga_cache", list(), envir = .GlobalEnv)
  }
  fga_cache <- get(".family_ga_cache", envir = .GlobalEnv)
  if (is.null(fga_cache[[detected_family]])) {
    fga_cache[[detected_family]] <- .count_family_grade_a(detected_family, strat_root)
    assign(".family_ga_cache", fga_cache, envir = .GlobalEnv)
  }
  family_ga_count <- fga_cache[[detected_family]]

  novelty_detail$family_grade_a <- family_ga_count
  novelty_detail$detected_family <- detected_family

  eff_corr <- novelty_detail$max_corr
  if (!is.na(eff_corr)) {
    if (eff_corr < 0.3 && family_ga_count == 0) {
      novelty_bonus <- 15L  # independent + new family
    } else if (eff_corr < 0.3) {
      novelty_bonus <- 10L  # independent + existing family
    } else if (eff_corr < 0.5 && family_ga_count == 0) {
      novelty_bonus <- 8L   # partial + new family
    } else if (eff_corr < 0.5) {
      novelty_bonus <- 5L   # partial + existing family
    } else {
      novelty_bonus <- 0L   # redundant
    }
  }
  novelty_detail$bonus_base <- novelty_bonus

  # FMB t-stat multiplier: if cross-sectional pricing power confirmed, 1.5x
  fmb_path <- file.path(output_dir, "analysis_fmb_summary.csv")
  if (file.exists(fmb_path)) {
    fmb_dt <- tryCatch(fread(fmb_path), error = function(e) NULL)
    if (!is.null(fmb_dt) && "NW_t" %in% names(fmb_dt)) {
      fmb_t_val <- max(fmb_dt$NW_t, na.rm = TRUE)
      novelty_detail$fmb_t <- fmb_t_val
      if (!is.na(fmb_t_val) && fmb_t_val > 3.0) {
        novelty_detail$fmb_multiplier <- 1.5
        novelty_bonus <- round(novelty_bonus * 1.5)
      }
    }
  }

  score_components$novelty_bonus <- list(
    score = novelty_bonus, max = 15,
    value = novelty_detail$max_corr, code = "D082"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D082",
    msg  = sprintf("Novelty Bonus: +%d pts (corr=%.3f, class=%s, family=%s, family_A=%d, fmb_mult=%.1f)",
                   novelty_bonus, novelty_detail$max_corr %||% NA,
                   novelty_detail$independence, detected_family, family_ga_count,
                   novelty_detail$fmb_multiplier)
  )))

  # --- D083: Family Saturation Penalty (v2.2 — diminishing returns) ---
  saturation_penalty <- 0L
  if (family_ga_count == 0) {
    saturation_penalty <- 0L
  } else if (family_ga_count <= 5) {
    saturation_penalty <- -3L
  } else if (family_ga_count <= 20) {
    saturation_penalty <- -8L
  } else if (family_ga_count <= 50) {
    saturation_penalty <- -12L
  } else {
    saturation_penalty <- -20L  # 51+ Grade A in same family (e.g. Defense 202)
  }

  # Additional: if Grade A composite corr > 0.85, extra -5 (replaces old D081 logic)
  if (!is.na(max_corr_with_a) && max_corr_with_a > 0.85) {
    saturation_penalty <- saturation_penalty - 5L
  }

  score_components$saturation_penalty <- list(
    score = saturation_penalty, max = 0,
    value = family_ga_count, code = "D083"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D083",
    msg  = sprintf("Saturation Penalty: %d pts (family_A=%d, ga_corr=%.3f)",
                   saturation_penalty, family_ga_count, max_corr_with_a %||% NA)
  )))

  # --- D084: Tail Risk Gate (Pfaff 2016, Session 56) ---
  # tail_risk_result.json이 있으면 CDaR/GPD/CF-VaR 검증
  tail_risk_penalty <- 0L
  tr_path <- NULL
  if (!is.null(output_dir) && dir.exists(output_dir)) {
    tr_path <- file.path(output_dir, "tail_risk_result.json")
  }
  if (!is.null(strategy_file) && is.null(tr_path)) {
    tr_path <- file.path(dirname(strategy_file), "tail_risk_result.json")
  }

  if (!is.null(tr_path) && file.exists(tr_path)) {
    tr_data <- tryCatch(fromJSON(tr_path), error = function(e) NULL)
    if (!is.null(tr_data)) {
      # CDaR check (35% threshold)
      cdar_val <- tr_data$summary$cdar_95 %||% tr_data$cdar$cdar
      if (!is.null(cdar_val) && !is.na(cdar_val) && cdar_val > 0.35) {
        tail_risk_penalty <- tail_risk_penalty - 3L
      }
      # GPD shape xi heavy tail (>= 0.5)
      xi_val <- tr_data$summary$tail_shape_xi %||% tr_data$evt_var$shape_xi
      if (!is.null(xi_val) && !is.na(xi_val) && xi_val >= 0.5) {
        tail_risk_penalty <- tail_risk_penalty - 2L
      }
      diagnostics <- c(diagnostics, list(list(
        code = "D084",
        msg  = sprintf("Tail Risk: CDaR=%.3f(lim 0.35), xi=%.3f, penalty=%d",
                       cdar_val %||% NA, xi_val %||% NA, tail_risk_penalty)
      )))
    }
  } else {
    diagnostics <- c(diagnostics, list(list(
      code = "D084",
      msg  = "Tail Risk: tail_risk_result.json 미발견 (compute_tail_risk_suite 미실행). 경고만."
    )))
  }
  score_components$tail_risk <- list(
    score = tail_risk_penalty, max = 0,
    value = tail_risk_penalty, code = "D084"
  )

  # --- D085: Stress Period Severity (8대 구간 MDD 기준) ---
  # 스트레스 기간 정보가 이미 계산되었으면 worst stress MDD 기반 패널티
  stress_penalty <- 0L
  if (exists("stress_periods") && is.data.table(stress_periods) && nrow(stress_periods) > 0) {
    worst_stress <- min(stress_periods$Strategy_MDD, na.rm = TRUE)
    if (!is.na(worst_stress) && worst_stress < -0.50) {
      stress_penalty <- -3L  # worst stress MDD > 50%
    } else if (!is.na(worst_stress) && worst_stress < -0.40) {
      stress_penalty <- -2L  # worst stress MDD 40~50%
    } else if (!is.na(worst_stress) && worst_stress < -0.30) {
      stress_penalty <- -1L  # worst stress MDD 30~40%
    }
    diagnostics <- c(diagnostics, list(list(
      code = "D085",
      msg  = sprintf("Stress Severity: worst_MDD=%.2f%%, penalty=%d",
                     worst_stress * 100, stress_penalty)
    )))
  } else {
    diagnostics <- c(diagnostics, list(list(
      code = "D085",
      msg  = "Stress Severity: 스트레스 기간 데이터 미계산. 패널티 없음."
    )))
  }
  score_components$stress_severity <- list(
    score = stress_penalty, max = 0,
    value = stress_penalty, code = "D085"
  )

  # --- D086: Risk Measure Coherence (CF-VaR vs EVT-VaR) ---
  # tail_risk_result.json의 CF-VaR/Normal-VaR 비율 경고
  coherence_note <- "N/A"
  if (!is.null(tr_path) && file.exists(tr_path)) {
    tr_data2 <- tryCatch(fromJSON(tr_path), error = function(e) NULL)
    if (!is.null(tr_data2)) {
      cf_ratio <- tr_data2$summary$cf_vs_normal %||%
                  tr_data2$cf_var$cf_vs_normal_ratio
      if (!is.null(cf_ratio) && !is.na(cf_ratio)) {
        if (cf_ratio > 1.5) {
          coherence_note <- sprintf("CF/Normal=%.2f: 꼬리 비대칭 높음. 정규VaR 과소추정 주의.", cf_ratio)
        } else {
          coherence_note <- sprintf("CF/Normal=%.2f: 정상 범위.", cf_ratio)
        }
      }
    }
  }
  diagnostics <- c(diagnostics, list(list(
    code = "D086",
    msg  = paste("Risk Coherence:", coherence_note)
  )))

  # --- Total score ---
  total_score <- sum(sapply(score_components, function(x) {
    s <- x[["score"]]
    if (is.null(s) || is.list(s)) 0 else as.numeric(s)
  }))
  total_score <- round(min(100, max(0, total_score)), 1)

  # Preserve v2.1 score (before novelty/saturation)
  total_score_v21 <- round(min(100, max(0, total_score - novelty_bonus - saturation_penalty)), 1)

  # --- D072: Confidence Auto-Enforcement (v1.4.2 Lawbook) ---
  confidence_mult <- 1.0
  confidence_note <- "No family data"

  if (exists("load_family_trials") && is.function(load_family_trials)) {
    fam_data <- tryCatch(load_family_trials(), error = function(e) list())
    for (fn in names(fam_data)) {
      if (strategy_name %in% names(fam_data[[fn]]$strategies %||% list())) {
        n_fam <- fam_data[[fn]]$total_trials %||% 1L
        n_pass <- fam_data[[fn]]$grade_a_count %||% 0L
        if (n_fam < 3) {
          confidence_mult <- 0.80
          confidence_note <- sprintf("Low evidence ('%s': %d trials) -> 0.80x", fn, n_fam)
        } else if (n_fam <= 5) {
          confidence_mult <- 0.90
          confidence_note <- sprintf("Moderate evidence ('%s': %d trials) -> 0.90x", fn, n_fam)
        } else if (n_fam >= 10 && n_pass / n_fam < 0.3) {
          confidence_mult <- 0.85
          confidence_note <- sprintf("High-trial low-success ('%s': %d/%d) -> 0.85x", fn, n_pass, n_fam)
        } else {
          confidence_mult <- 1.0
          confidence_note <- sprintf("Full confidence ('%s': %d trials)", fn, n_fam)
        }
        break
      }
    }
  }
  total_score_raw <- total_score
  total_score <- round(total_score * confidence_mult, 1)
  diagnostics <- c(diagnostics, list(list(
    code = "D072",
    msg  = sprintf("Confidence: %s (%.1f -> %.1f)", confidence_note, total_score_raw, total_score)
  )))

  # --- D073: Combinatorial Penalty (v53 S2.9) ---
  # grid_runs iteration >= 50 → -10 pts (조합 폭발 패널티, qepm §1 프로세스 위배 방지)
  combinat_adj <- 0L
  grid_iter_count <- 0L
  grid_cache_dir <- file.path(
    ifelse(exists("CACHE_DIR"), CACHE_DIR, ".cache"),
    "grid_runs"
  )
  if (dir.exists(grid_cache_dir)) {
    .gf <- list.files(
      grid_cache_dir,
      pattern = paste0("^", strategy_name, ".*\\.(parquet|csv)$"),
      full.names = TRUE
    )
    for (fp in .gf) {
      n_rows <- tryCatch({
        if (grepl("\\.parquet$", fp) && requireNamespace("arrow", quietly = TRUE)) {
          nrow(arrow::read_parquet(fp))
        } else {
          nrow(fread(fp))
        }
      }, error = function(e) 0L)
      grid_iter_count <- grid_iter_count + as.integer(n_rows)
    }
  }
  if (grid_iter_count >= 50L) {
    combinat_adj <- -10L
    total_score <- total_score + combinat_adj
  }
  score_components$combinat <- list(
    score = combinat_adj, max = 0,
    value = grid_iter_count, code = "D073"
  )
  diagnostics <- c(diagnostics, list(list(
    code = "D073",
    msg  = sprintf("Combinatorial: grid_iter=%d (%+d pts)%s",
                    grid_iter_count, combinat_adj,
                    if (grid_iter_count >= 50L) " [explosion penalty]" else "")
  )))

  # ==========================================================================
  # 5-AXIS SCORING (v1.1 Lawbook)
  # Each axis 0-100. Presented as radar chart + table, not single number.
  # ==========================================================================

  # Axis 1: Return (0-100)
  axis_return <- min(100, round(
    (sharpe_score / 20) * 40 +
    (ir_score / 15) * 30 +
    (cagr_score / 15) * 30
  ))

  # Axis 2: Risk (0-100) — higher = safer
  vol_pts <- max(0, min(20, (0.30 - ann_vol) / 0.25 * 20))
  axis_risk <- min(100, round(
    (mdd_score / 10) * 50 +
    (calmar_score / 10) * 30 +
    vol_pts
  ))

  # Axis 3: Robustness (0-100)
  axis_robustness <- min(100, max(0, round(
    (rolling_score / 15) * 35 +
    ((oos_adj + 8) / 16) * 30 +
    ((ic_adj + 6) / 12) * 20 +
    ((alpha_trend_adj + 10) / 20) * 15
  )))

  # Axis 4: Implementability (0-100) — turnover/concentration penalty
  to_pts   <- max(0, min(50, (800 - ann_turnover) / 800 * 50))
  conc_pts <- if (!is.na(top10_conc)) max(0, min(30, (70 - top10_conc) / 40 * 30)) else 20
  axis_implement <- min(100, round(to_pts + conc_pts + (param_score / 5) * 20))

  # Axis 5: Diversification (0-100) — stress alpha, BM decorrelation, skew
  bm_corr <- tryCatch(
    as.numeric(cor(as.numeric(merged[,1]), as.numeric(merged[,2]), use = "complete.obs")),
    error = function(e) 0.5
  )
  if (is.na(bm_corr)) bm_corr <- 0.5
  bm_corr_pts <- max(0, min(30, (1 - abs(bm_corr)) * 30))
  act_skew <- tryCatch(as.numeric(skewness(active_ret)), error = function(e) 0)
  if (is.na(act_skew)) act_skew <- 0
  skew_pts <- max(0, min(20, 10 + act_skew * 5))
  axis_divers <- min(100, round(
    (stress_score / 10) * 50 + bm_corr_pts + skew_pts
  ))

  axes <- list(
    Return          = axis_return,
    Risk            = axis_risk,
    Robustness      = axis_robustness,
    Implementability = axis_implement,
    Diversification = axis_divers
  )

  # ==========================================================================
  # GRADE DETERMINATION (v1.1 — 06_Hurdle)
  # A (Standalone)  : Solo-운용 가능. CAGR >= 16%, Sharpe >= 0.8, no hard fail, score >= 40
  # B (Component)   : 포트폴리오 기여 가능. 완화된 MDD/TO 기준
  # C (Ensemble)    : 앙상블에서만 가치
  # F (Fail)        : 부적합
  # ==========================================================================
  max_axis <- max(unlist(axes))
  mdd_b_ok <- isTRUE(is.finite(mdd) && mdd <= 0.50) || isTRUE(dd_profile$tail_review)
  mdd_c_ok <- isTRUE(is.finite(mdd) && mdd <= 0.60) || isTRUE(dd_profile$tail_review)

  # v2.1 grade (preserved for backward compat)
  grade_v21 <- if (!hard_fail && total_score_v21 >= 40 && ann_ret >= 0.16 && sharpe >= 0.8) {
    "A"
  } else if (!hard_fail && total_score_v21 >= 40) {
    "B"
  } else if (!hard_fail && mdd_b_ok && sharpe >= 0.3 && total_score_v21 >= 25 && max_axis >= 50) {
    "B"
  } else if (!hard_fail && mdd_c_ok && total_score_v21 >= 15 && max_axis >= 30) {
    "C"
  } else {
    "F"
  }

  # ==========================================================================
  # DEFENSE GRADE — role_label == "defense" 전용 평가 체계
  # 8대 스트레스 구간 alpha outperform 비율 기반 추가 판정
  # A_DEF: 강한 방어 능력 (구간 5/8+ 아웃퍼폼 + MDD <= 35% + SR >= 0.5)
  # B_DEF: 보통 방어 능력 (구간 3/8+ 아웃퍼폼 + MDD <= 45%)
  # 기존 A/B/C/F는 defense 아닌 전략에 그대로 적용 (하위 호환 보장)
  # ==========================================================================
  .defense_stress_periods_8 <- list(
    list(name = "Terror_9_11",     start = "2001-09-01", end = "2001-12-31"),
    list(name = "GFC",             start = "2007-10-01", end = "2009-03-31"),
    list(name = "Euro_Debt",       start = "2011-07-01", end = "2011-12-31"),
    list(name = "China_Shock",     start = "2015-06-01", end = "2016-02-29"),
    list(name = "US_China_Trade",  start = "2018-03-01", end = "2018-12-31"),
    list(name = "COVID",           start = "2020-01-01", end = "2020-06-30"),
    list(name = "Rate_Hike",       start = "2022-01-01", end = "2022-12-31"),
    list(name = "Iran_War",        start = "2026-02-01", end = "2026-04-30")
  )

  # 벡터화: stress_periods_cpp()로 8구간 일괄 처리 (for-loop 제거)
  .def_starts <- as.numeric(as.Date(vapply(.defense_stress_periods_8,
                                            `[[`, character(1), "start")))
  .def_ends   <- as.numeric(as.Date(vapply(.defense_stress_periods_8,
                                            `[[`, character(1), "end")))
  .def_names  <- vapply(.defense_stress_periods_8, `[[`, character(1), "name")
  .def_dates  <- as.numeric(as.Date(index(merged)))
  .def_sr     <- as.numeric(merged[, 1])
  .def_br     <- as.numeric(merged[, 2])

  .def_res    <- stress_periods_cpp(.def_dates, .def_sr, .def_br, .def_starts, .def_ends)

  .valid_idx  <- which(!is.na(.def_res$strat_cum) & .def_res$n_obs >= 10L)
  .def_n_stress  <- length(.valid_idx)
  .def_n_outperf <- sum(as.logical(.def_res$outperform[.valid_idx]), na.rm = TRUE)

  # 상세 리스트 생성 (벡터 인덱싱, 루프 없음)
  .def_stress_alpha_rows <- lapply(seq_along(.def_names), function(i) {
    sc_i  <- .def_res$strat_cum[i]
    bc_i  <- .def_res$bm_cum[i]
    al_i  <- .def_res$alpha[i]
    op_i  <- as.logical(.def_res$outperform[i])
    list(
      period     = .def_names[i],
      strat_ret  = if (!is.na(sc_i)) round(sc_i * 100, 2) else NA_real_,
      bm_ret     = if (!is.na(bc_i)) round(bc_i * 100, 2) else NA_real_,
      alpha      = if (!is.na(al_i)) round(al_i * 100, 2) else NA_real_,
      outperform = if (!is.na(op_i)) op_i else NA
    )
  })

  .def_outperf_rate <- if (.def_n_stress > 0L) .def_n_outperf / .def_n_stress else 0

  # CAPM beta (full-sample proxy — 방어성 측정용, grade 판정에만 사용)
  .def_beta <- tryCatch({
    .m <- merge(strat_xts, bm_xts)
    .m <- .m[complete.cases(as.data.frame(.m)), ]
    if (nrow(.m) >= 60) coef(lm(as.numeric(.m[, 1]) ~ as.numeric(.m[, 2])))[2] else NA_real_
  }, error = function(e) NA_real_)

  # role_label: 외부에서 주입 가능 (sg_determine_role 결과). 없으면 내부 role로 추론
  .effective_role <- if (exists("role_label") && !is.null(role_label) && nchar(role_label) > 0) {
    role_label
  } else {
    # 내부 axis 기반 추론 (defense 판단: axis_risk 우위)
    if (axis_risk >= axis_return && axis_risk >= axis_divers) "defense" else "other"
  }

  grade <- if (.effective_role == "defense") {
    # ── Defense 전용 분기 ──────────────────────────────────────────────────
    if (hard_fail) {
      "F"       # Hard fail은 defense도 예외 없음
    } else if (.def_outperf_rate >= (5/8) && mdd <= 0.35 && sharpe >= 0.5) {
      "A_DEF"   # 강한 방어 — 5/8+ 아웃퍼폼, MDD <= 35%, SR >= 0.5
    } else if (.def_outperf_rate >= (3/8) && mdd <= 0.45) {
      "B_DEF"   # 보통 방어 — 3/8+ 아웃퍼폼, MDD <= 45%
    } else if (mdd <= 0.55 && total_score >= 15 && max_axis >= 30) {
      "C"       # Ensemble-only (방어 미달이지만 일부 가치)
    } else {
      "F"
    }
  } else {
    # ── 기존 Core/Diversifier 분기 (하위 호환 유지) ────────────────────────
    if (!hard_fail && total_score >= 40 && ann_ret >= 0.16 && sharpe >= 0.8) {
      "A"
    } else if (!hard_fail && total_score >= 40 && ann_ret >= 0.12 && sharpe >= 0.6
               && novelty_bonus >= 10) {
      "A_NOVEL"  # v2.2: independent alpha with portfolio diversification value
    } else if (!hard_fail && total_score >= 40) {
      "B"  # PASS but below 16% CAGR target — strong Component
    } else if (!hard_fail && mdd_b_ok && sharpe >= 0.3 && total_score >= 25 && max_axis >= 50) {
      "B"  # Near-PASS with clear axis strength (relaxed MDD/TO)
    } else if (!hard_fail && mdd_c_ok && total_score >= 15 && max_axis >= 30) {
      "C"  # Ensemble-only: some merit but not standalone/component
    } else {
      "F"
    }
  }

  # ==========================================================================
  # v53 S2.9: DSR + FF5 Hard Gate (strict_mode)
  # Grade A 경로는 통계적 방어선 통과를 강제. 미통과 시 B로 강등.
  # ==========================================================================
  strict_downgrade_reasons <- character(0)
  if (isTRUE(strict_mode) && grade %in% c("A", "A_NOVEL", "A_DEF")) {
    # DSR hard gate: dsr_sig==FALSE 이면 downgrade
    if (!is.na(dsr_value) && !isTRUE(dsr_sig)) {
      strict_downgrade_reasons <- c(strict_downgrade_reasons,
        sprintf("DSR insignificant (%.3f < 0.95 threshold)", dsr_value))
    }
    # FF5 hard gate: ff5_result 주입된 경우만. |t_alpha| < 3.0 → downgrade
    if (!is.null(ff5_result) && isTRUE(ff5_result$converged)) {
      t_alpha_abs <- abs(ff5_result$alpha_t %||% 0)
      if (t_alpha_abs < 3.0) {
        strict_downgrade_reasons <- c(strict_downgrade_reasons,
          sprintf("FF5 alpha t=%.2f < 3.0 (Harvey 2016)", t_alpha_abs))
      }
    }
    if (length(strict_downgrade_reasons) > 0) {
      original_grade <- grade
      grade <- if (grade == "A_DEF") "B_DEF" else "B"
      diagnostics <- c(diagnostics, list(list(
        code = "D074",
        msg  = sprintf("[STRICT_MODE] %s → %s downgrade: %s",
                        original_grade, grade,
                        paste(strict_downgrade_reasons, collapse = "; "))
      )))
    }
  }
  score_components$strict_gate <- list(
    score = 0, max = 0,
    value = length(strict_downgrade_reasons),
    code = "D074",
    reasons = strict_downgrade_reasons,
    strict_mode = isTRUE(strict_mode)
  )

  # ==========================================================================
  # v53 Sprint 4 AX-P2: D075 AX Violation Suspicion
  # 전략이 active AX 범위와 매치되는데 AX 주장과 반대 결과면 의심
  # "결과가 아닌 실험을 의심" 원칙
  # ==========================================================================
  d075_flag <- FALSE
  d075_reasons <- character(0)
  d075_penalty <- 0

  .axiom_root <- function() {
    c1 <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
    c2 <- Sys.getenv("PROJECT_ROOT", "")
    if (dir.exists(c1)) c1 else if (nzchar(c2) && dir.exists(c2)) c2 else getwd()
  }
  .ax_dir <- file.path(.axiom_root(), "qepm", "memory", "axioms", "active")
  if (dir.exists(.ax_dir)) {
    .ax_files <- list.files(.ax_dir, pattern = "^AX-.*\\.json$", full.names = TRUE)
    # Extract strategy family hint from name
    .strat_lower <- tolower(strategy_name)
    for (axf in .ax_files) {
      ax <- tryCatch(jsonlite::fromJSON(axf, simplifyVector = FALSE),
                     error = function(e) NULL)
      if (is.null(ax)) next
      ax_id <- ax$axiom_id %||% ax$id %||% basename(axf)
      # IMMUTABLE (AX-000/001/002) 는 D075 대상에서 제외
      if (identical(ax$grade, "IMMUTABLE")) next
      pol <- ax$polarity %||% "unknown"
      scope <- ax$scope %||% list()
      ax_family <- tolower(scope$factor_family %||% "")

      # scope family 매치 여부 (간이 keyword match)
      matched <- nzchar(ax_family) && grepl(ax_family, .strat_lower, fixed = TRUE)
      if (!matched) next

      # polarity vs observed grade 충돌 감지
      is_grade_a <- grade %in% c("A", "A_NOVEL", "A_DEF")
      if (pol == "negative" && is_grade_a) {
        d075_flag <- TRUE
        d075_reasons <- c(d075_reasons,
          sprintf("%s (negative) 범위 내 Grade A 관찰", ax_id))
      } else if (pol %in% c("positive", "conditional") && grade == "F" && !hard_fail) {
        d075_flag <- TRUE
        d075_reasons <- c(d075_reasons,
          sprintf("%s (%s) 범위 내 Grade F 관찰 — 실험 오류 의심", ax_id, pol))
      }
    }
  }

  if (d075_flag) {
    d075_penalty <- -5
    total_score <- total_score + d075_penalty
    diagnostics <- c(diagnostics, list(list(
      code = "D075",
      msg = sprintf("[AX Violation Suspicion] %s (실험/데이터 오류 먼저 의심). penalty=%+d",
                    paste(d075_reasons, collapse = "; "), d075_penalty)
    )))
    # strict_mode 에서는 Grade A 경로도 강등
    if (isTRUE(strict_mode) && grade %in% c("A", "A_NOVEL", "A_DEF")) {
      original_grade_d075 <- grade
      grade <- if (grade == "A_DEF") "B_DEF" else "B"
      diagnostics <- c(diagnostics, list(list(
        code = "D075",
        msg = sprintf("[STRICT_MODE] %s → %s (D075 axiom violation)",
                      original_grade_d075, grade)
      )))
    }
  }
  score_components$axiom_suspicion <- list(
    score = d075_penalty, max = 0,
    value = length(d075_reasons),
    code = "D075", reasons = d075_reasons, flag = d075_flag
  )

  # Role assignment based on axis profile
  role <- if (grade == "F") {
    "none"
  } else if (.effective_role == "defense" || grade %in% c("A_DEF", "B_DEF")) {
    "defense"
  } else if (axis_risk >= axis_return && axis_risk >= axis_divers) {
    "defensive"
  } else if (axis_divers >= axis_return) {
    "diversifier"
  } else {
    "core"
  }

  # Defense metrics (항상 기록, defense 아닌 전략은 빈 리스트)
  defense_metrics <- if (.effective_role == "defense" || grade %in% c("A_DEF", "B_DEF")) {
    list(
      stress_8_outperf_rate = round(.def_outperf_rate, 3),
      stress_8_n_outperf    = .def_n_outperf,
      stress_8_n_total      = .def_n_stress,
      stress_8_detail       = .def_stress_alpha_rows,
      capm_beta             = if (!is.na(.def_beta)) round(.def_beta, 4) else NA
    )
  } else {
    list()
  }

  # ==========================================================================
  # SCREENING TIER (v8.1.1 2026-06-10, 도훈 mandate P2 게이트 계층화)
  # 배경: alpha-search 탈락 66/66건이 MDD>45% 단일 사유 (long-only β≈0.8 구조 —
  #   overlay 없는 맨몸 채점이라 구조적 전멸. near-miss: SR 0.825·CAGR 20.8%가 MDD로 F).
  # 설계: 졸업/자본 게이트(grade·HARD)는 불변. screening은 "알파 신호력" 별도 축 —
  #   MDD·turnover 등 구조 사유를 제외하고 신호가 실재하는 후보를
  #   overlay 결합 / FR RCMA 국면소비 / DPL 피처 경로로 라우팅하는 라벨.
  # PIT 위반(D000)만은 계층 무관 절대 기각 (AX-002).
  # ==========================================================================
  .pit_violated <- any(grepl("^PIT violation", fail_reasons))
  screen_pass <- !.pit_violated && (
    (sharpe >= 0.7 && ann_ret >= 0.12) ||
    (total_score >= 40 && sharpe >= 0.5)
  )
  screen_route <- if (!screen_pass) {
    "NONE"
  } else if (grade %in% c("A", "A_NOVEL", "A_DEF", "B", "B_DEF")) {
    "STANDALONE_TRACK"  # 기존 등급 경로가 이미 소화
  } else {
    .routes <- character(0)
    if (mdd > 0.45 || isTRUE(dd_profile$tail_review)) .routes <- c(.routes, "OVERLAY_CANDIDATE")  # MDD가 죽인 신호 — overlay/regime 결합 후보
    if (ann_turnover > turnover_hard_fail_pct) .routes <- c(.routes, "DPL_FEATURE")  # 고회전 신호 — 직접운용 불가, 피처로
    .routes <- c(.routes, "FR_RCMA")                                    # 국면조건부 소비는 항상 후보 (등급무관 등재)
    paste(unique(.routes), collapse = "|")
  }
  if (screen_pass && grade %in% c("C", "F")) {
    diagnostics <- c(diagnostics, list(list(
      code = "D090",
      msg  = sprintf("[SCREENING] 신호력 PASS (SR %.2f, CAGR %.1f%%) — grade %s는 구조 사유. 라우팅: %s",
                     sharpe, ann_ret * 100, grade, screen_route)
    )))
  }

  # ==========================================================================
  # VERDICT
  # ==========================================================================

  pass <- !hard_fail && total_score >= 40

  verdict <- list(
    screening   = list(
      screen_pass  = screen_pass,
      screen_route = screen_route,
      drawdown_tail_review = isTRUE(dd_profile$tail_review),
      note = "탐색 게이트 — 자본/졸업 게이트 아님 (graduation HARD 불변). PIT만 절대."
    ),
    strategy    = strategy_name,
    timestamp   = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    pass        = pass,
    hard_fail   = hard_fail,
    fail_reasons = fail_reasons,
    total_score = total_score,
    total_score_v21 = total_score_v21,
    grade       = grade,
    grade_v21   = grade_v21,
    novelty_bonus = novelty_bonus,
    saturation_penalty = saturation_penalty,
    novelty_detail = novelty_detail,
    role        = role,
    axes        = axes,
    score_breakdown = score_components,
    metrics = list(
      CAGR          = round(ann_ret * 100, 2),
      AnnVol        = round(ann_vol * 100, 2),
      Sharpe        = round(sharpe, 3),
      Sharpe_m      = tryCatch({
        mr <- as.numeric(apply.monthly(strat_xts[!is.na(strat_xts)], Return.cumulative))
        if (length(mr) >= 12) round(mean(mr) / sd(mr) * sqrt(12), 3) else NA
      }, error = function(e) NA),
      IR            = round(ir, 3),
      MDD           = round(mdd * 100, 2),
      Calmar        = round(calmar, 3),
      Turnover_Ann  = round(ann_turnover, 1),
      Top10_Conc    = round(top10_conc, 1),
      Rolling3Y_Pos = round(rolling_sharpe_ratio * 100, 1),
      BM_Corr       = round(bm_corr, 3),
      ES99_d        = tryCatch({
        r_num <- as.numeric(r)
        cutoff <- quantile(r_num, 0.01, na.rm = TRUE)
        tail_r <- r_num[r_num <= cutoff]
        if (length(tail_r) > 0) round(-mean(tail_r) * 100, 2) else NA
      }, error = function(e) NA),
      ES99_m        = tryCatch({
        mr <- as.numeric(apply.monthly(strat_xts[!is.na(strat_xts)], Return.cumulative))
        if (length(mr) >= 24) {
          cutoff <- quantile(mr, 0.01, na.rm = TRUE)
          tail_r <- mr[mr <= cutoff]
          if (length(tail_r) > 0) round(-mean(tail_r) * 100, 2) else NA
        } else NA
      }, error = function(e) NA),
      GradeA_Corr   = round(max_corr_with_a, 3),
      Rolling6M_Hit = round(rolling_6m_hit * 100, 1),
      Worst6M_Ret   = round(worst_6m_ret * 100, 2),
      MaxConsecNegAlpha = max_consec_neg_alpha,
      Rolling12M_Hit = round(rolling_12m_hit * 100, 1)
    ),
    drawdown_profile = list(
      severe35_count = dd_profile$severe35_count,
      severe45_count = dd_profile$severe_count,
      severe55_count = dd_profile$extreme_count,
      severe45_total_days = dd_profile$severe_total_days,
      severe45_max_days = dd_profile$severe_max_days,
      severe45_day_frac = round(dd_profile$severe_day_frac, 4),
      severe45_hard_count = dd_profile$severe_hard_count,
      severe55_hard_count = dd_profile$extreme_hard_count,
      severe45_day_hard_frac = dd_profile$severe_day_hard_frac,
      severe45_max_hard_days = dd_profile$severe_max_hard_days,
      underwater20_frac = round(dd_profile$underwater20_frac, 4),
      crash_frequency_score = round(dd_profile$crash_frequency_score, 2),
      tail_review = isTRUE(dd_profile$tail_review),
      structural_hard_fail = isTRUE(dd_profile$structural_hard_fail)
    ),
    statistical_defense = list(
      dsr             = dsr_value,
      dsr_significant = dsr_sig,
      sr_max_expected = sr_max_exp,
      n_trials        = n_family_trials
    ),
    diagnostics      = diagnostics,
    defense_metrics  = defense_metrics
  )

  # --- Save if output_dir provided ---
  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
    write_json(verdict, file.path(output_dir, "hurdle_result.json"),
               auto_unbox = TRUE, pretty = TRUE)
    cat(sprintf("[hurdle_gate] Result saved to %s\n",
                file.path(output_dir, "hurdle_result.json")))

    # --- Save FULL portfolio holdings for Grade A strategies ---
    if (grade == "A") {
      holdings_saved <- FALSE

      # Method 1: Check for multi-sleeve sim results in strategy directory
      strat_dir <- dirname(output_dir)
      sleeve_files <- list.files(strat_dir, pattern = "^sim_sleeve_.*\\.rds$", full.names = TRUE)

      if (length(sleeve_files) > 0) {
        # Multi-sleeve: combine all sleeve HOLDINGS_LOGs
        all_holdings <- list()
        for (sf in sleeve_files) {
          sleeve_name <- gsub("sim_sleeve_|\\.rds$", "", basename(sf))
          sleeve_sim <- tryCatch(readRDS(sf), error = function(e) NULL)
          if (!is.null(sleeve_sim) && !is.null(sleeve_sim$HOLDINGS_LOG) &&
              nrow(sleeve_sim$HOLDINGS_LOG) > 0) {
            hl <- as.data.table(sleeve_sim$HOLDINGS_LOG)
            hl[, Sleeve := sleeve_name]
            all_holdings[[length(all_holdings) + 1]] <- hl
          }
        }
        if (length(all_holdings) > 0) {
          combined <- rbindlist(all_holdings, fill = TRUE)
          fwrite(combined, file.path(output_dir, "holdings_all_sleeves.csv"))
          cat(sprintf("[hurdle_gate] Multi-sleeve holdings saved (%d rows, %d sleeves, Grade A)\n",
                      nrow(combined), length(all_holdings)))
          holdings_saved <- TRUE
        }
      }

      # Method 2: Single sleeve / standard strategy — save HOLDINGS_LOG directly
      if (!holdings_saved && !is.null(sim_result$HOLDINGS_LOG) &&
          nrow(sim_result$HOLDINGS_LOG) > 0) {
        hl <- as.data.table(sim_result$HOLDINGS_LOG)
        hl[, Sleeve := "single"]
        fwrite(hl, file.path(output_dir, "holdings_detail.csv"))
        cat(sprintf("[hurdle_gate] Holdings detail saved (%d rows, Grade A)\n",
                    nrow(hl)))
        holdings_saved <- TRUE
      }

      # Method 3: Check parent environment for FACTORS (factor-level holdings)
      if (!holdings_saved && exists("FACTORS", envir = parent.frame())) {
        factors_dt <- as.data.table(get("FACTORS", envir = parent.frame()))
        if (nrow(factors_dt) > 0 && all(c("Date", "Ticker", "Score") %in% names(factors_dt))) {
          fwrite(factors_dt, file.path(output_dir, "factors_detail.csv"))
          cat(sprintf("[hurdle_gate] FACTORS saved (%d rows, Grade A fallback)\n",
                      nrow(factors_dt)))
        }
      }
    }
  }

  # --- Console summary ---
  cat("\n")
  cat("=== HURDLE GATE RESULT ===\n")
  cat(sprintf("Strategy : %s\n", strategy_name))
  cat(sprintf("Verdict  : %s\n", if (pass) "PASS" else "FAIL"))
  if (hard_fail) {
    cat(sprintf("Hard FAIL: %s\n", paste(fail_reasons, collapse = "; ")))
  }
  cat(sprintf("Score    : %.1f / 100  |  Grade: %s (%s)\n", total_score, grade, role))
  cat(sprintf("5-Axis   : Ret=%d | Risk=%d | Rob=%d | Impl=%d | Div=%d\n",
              axis_return, axis_risk, axis_robustness, axis_implement, axis_divers))
  cat(sprintf("CAGR=%.1f%% | Sharpe=%.3f | Sharpe_m=%s | MDD=%.1f%% | IR=%.3f | Calmar=%.3f\n",
              ann_ret * 100, sharpe,
              ifelse(is.na(verdict$metrics$Sharpe_m), "N/A", sprintf("%.3f", verdict$metrics$Sharpe_m)),
              mdd * 100, ir, calmar))
  cat(sprintf("ES99_d=%s%% | ES99_m=%s%% | GradeA_Corr=%s\n",
              ifelse(is.na(verdict$metrics$ES99_d), "N/A", sprintf("%.2f", verdict$metrics$ES99_d)),
              ifelse(is.na(verdict$metrics$ES99_m), "N/A", sprintf("%.2f", verdict$metrics$ES99_m)),
              ifelse(is.na(max_corr_with_a), "N/A", sprintf("%.3f", max_corr_with_a))))
  cat(sprintf("6M_Hit=%.1f%% | Worst6M=%.2f%% | MaxConsecNeg=%dM | 12M_Hit=%.1f%%\n",
              ifelse(is.na(rolling_6m_hit), 0, rolling_6m_hit * 100),
              ifelse(is.na(worst_6m_ret), 0, worst_6m_ret * 100),
              max_consec_neg_alpha,
              ifelse(is.na(rolling_12m_hit), 0, rolling_12m_hit * 100)))
  cat(sprintf("AlphaTrend: %s (adj %.1f pts)\n",
              alpha_trend_note, alpha_trend_adj))
  cat(sprintf("OOS Valid : %s (adj %.1f pts)\n", oos_note, oos_adj))
  cat(sprintf("IC Stab   : %s (adj %.1f pts)\n", ic_note, ic_adj))
  cat(sprintf("DSR       : %s\n", dsr_note))
  cat(sprintf("Gate5 Div : %s\n", div_gate_note))

  # --- Auto 3-Axis Verification ---
  verification <- NULL
  if (exists("verify_strategy") && is.function(verify_strategy)) {
    verification <- tryCatch(
      verify_strategy(strat_xts, bm_xts, strategy_name, output_dir = output_dir),
      error = function(e) {
        cat(sprintf("  [Verification] Skipped: %s\n", conditionMessage(e)))
        NULL
      }
    )
  }
  cat("==========================\n\n")

  # --- Grade A Catalog (persistent, zero external dependencies) ---
  if (grade == "A" && !is.null(output_dir)) {
    tryCatch({
      catalog_path <- file.path(PROJECT_ROOT, "04_Research", "grade_a_catalog.json")
      catalog_id <- catalog_strategy_id %||% strategy_name
      raw_catalog <- if (file.exists(catalog_path)) {
        jsonlite::fromJSON(catalog_path, simplifyVector = FALSE)
      } else list()

      if (!is.null(raw_catalog$strategies)) {
        catalog <- raw_catalog
        strategies <- catalog$strategies %||% list()
      } else {
        # Legacy compatibility: older catalog files were a plain list of entries.
        catalog <- list(
          schema_version = "legacy_wrapped_by_hurdle_gate",
          last_updated = NULL,
          n_strategies = 0L,
          grade_counts = list(A = 0L),
          strategies = if (length(raw_catalog)) raw_catalog else list()
        )
        strategies <- catalog$strategies
      }

      existing_ids <- vapply(strategies, function(x) {
        if (is.list(x)) x$strategy_id %||% "" else ""
      }, character(1))
      if (!catalog_id %in% existing_ids) {
        m <- verdict$metrics %||% list()
        entry <- list(
          strategy_id = catalog_id,
          strategy_name = strategy_name,
          grade = grade,
          grade_v21 = grade,
          score = round(total_score, 1),
          cagr = round(as.numeric(m$CAGR %||% 0), 2),
          sharpe = round(as.numeric(m$Sharpe %||% 0), 3),
          mdd = round(as.numeric(m$MDD %||% 0), 2),
          calmar = round(as.numeric(m$Calmar %||% 0), 3),
          role = role,
          family = detected_family %||% NULL,
          novelty_bonus = novelty_bonus %||% 0,
          source = if (file.exists(file.path(output_dir, "hurdle_result.json"))) {
            sub(paste0("^", gsub("([][{}()+*^$.|?\\\\-])", "\\\\\\1", PROJECT_ROOT), "/?"),
                "", normalizePath(file.path(output_dir, "hurdle_result.json"), winslash = "/", mustWork = FALSE))
          } else NULL,
          source_mtime = if (file.exists(file.path(output_dir, "hurdle_result.json"))) {
            format(file.info(file.path(output_dir, "hurdle_result.json"))$mtime, "%Y-%m-%dT%H:%M:%S%z")
          } else NULL,
          timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
          output_dir = output_dir
        )
        strategies <- c(strategies, list(entry))
        catalog$strategies <- strategies
        catalog$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
        catalog$n_strategies <- length(strategies)
        catalog$grade_counts <- as.list(table(vapply(strategies, function(x) {
          if (is.list(x)) x$grade %||% "A" else "A"
        }, character(1))))
        jsonlite::write_json(catalog, catalog_path, auto_unbox = TRUE, pretty = TRUE)
        cat(sprintf("[hurdle_gate] Grade A catalog: %d entries (+1 %s)\n",
                    length(strategies), catalog_id))
      }
    }, error = function(e) cat(sprintf("[grade_a_catalog] %s\n", conditionMessage(e))))
  }

  # --- Auto Lesson Generation ---
  auto_lessons <- .generate_auto_lessons(verdict, strategy_name)
  if (length(auto_lessons) > 0) {
    cat(sprintf("[hurdle_gate] Auto-lessons generated: %d\n", length(auto_lessons)))
  }

  # --- QEPM Auto-Commit Hook (opt-in via QEPM_AUTO_COMMIT flag) ---
  if (exists("QEPM_AUTO_COMMIT") && isTRUE(QEPM_AUTO_COMMIT) && !is.null(output_dir)) {
    tryCatch({
      hybrid_mode_path <- file.path(PROJECT_ROOT, "qepm", "scripts", "hybrid_mode.R")
      if (!exists("hybrid_commit") && file.exists(hybrid_mode_path)) {
        old_wd <- getwd()
        setwd(file.path(PROJECT_ROOT, "qepm"))
        tryCatch(source(hybrid_mode_path), error = function(e) {
          cat("[hurdle_gate] hybrid_mode.R load failed:", conditionMessage(e), "\n")
        })
        setwd(old_wd)
      }
      if (exists("hybrid_commit")) {
        # Infer family from strategy directory name pattern
        # Walk up from output_dir until we find a STR_XXX_name directory
        strat_dir <- ""
        check_dir <- output_dir
        for (.i in 1:5) {
          check_dir <- dirname(check_dir)
          bn <- basename(check_dir)
          if (grepl("^STR_\\d+", bn)) { strat_dir <- bn; break }
        }
        if (nchar(strat_dir) == 0) strat_dir <- basename(dirname(output_dir))
        family_guess <- gsub("^STR_\\d+_?", "", strat_dir)
        if (nchar(family_guess) == 0) family_guess <- "general"

        # Set family for telegram message (tg_strategy_result reads this)
        .qepm_last_family <<- family_guess

        # Build named artifact list from output_dir files (H3 fix)
        art_files <- list.files(output_dir, pattern = "\\.(json|csv|png|md)$", full.names = TRUE)
        art_named <- if (length(art_files) > 0) {
          setNames(as.list(art_files), basename(art_files))
        } else {
          list(output_dir = output_dir)  # fallback: pass dir itself
        }

        # Dynamic construction extraction from run_all.R
        run_all_path <- file.path(dirname(output_dir), "run_all.R")
        if (!file.exists(run_all_path)) run_all_path <- file.path(dirname(dirname(output_dir)), "run_all.R")
        construction_auto <- if (file.exists(run_all_path)) {
          bf_path <- file.path(INFRA_DIR, "backfill_construction.R")
          if (!exists("classify_construction") && file.exists(bf_path)) source(bf_path)
          if (exists("classify_construction")) {
            classify_construction(run_all_path)
          } else {
            list(construction_type = "unknown", rebalance = "monthly", weighting = "equal")
          }
        } else {
          list(construction_type = "unknown", rebalance = "monthly", weighting = "equal")
        }

        hybrid_commit(strategy_name = strategy_name,
                      family = family_guess,
                      hurdle_result = verdict,
                      artifact_paths = art_named,
                      construction = construction_auto,
                      role = role,
                      lessons = auto_lessons)
        cat("[hurdle_gate] QEPM auto-commit completed\n")
      } else {
        # hybrid_commit 로드 실패 → pending 마커 저장 (batch recovery 대상)
        pending <- list(
          strategy_name = strategy_name, output_dir = output_dir,
          grade = grade, score = total_score, role = role,
          timestamp = format(Sys.time())
        )
        jsonlite::write_json(pending, file.path(output_dir, "qepm_pending.json"),
                             auto_unbox = TRUE, pretty = TRUE)
        cat("[hurdle_gate] QEPM commit PENDING — saved for batch recovery\n")
      }
    }, error = function(e) {
      cat(sprintf("[hurdle_gate] QEPM auto-commit failed: %s\n", conditionMessage(e)))
    })
  }

  # --- (제거됨 2026-06-10 도훈 mandate) Loop Integrator FreshIdea hostile review ---
  # 사유: _deleted_FreshIdea 폴더 완전 삭제 결정. generic Mutation Seed 생성이
  # 신규 체계(L-code 학습 3필드 next_probe + FMT 자동판정 + screening tier 라우팅
  # + kr-inverse-pattern-miner)와 역할 중복이고 질이 낮았으며, 소비자(loop_integrator
  # 정기 실행처)가 0건인 반쪽 루프였음. loop_integrator.R 파일은 FS retain.

  list(pass = pass, score = total_score, grade = grade, role = role,
       axes = axes, verdict = verdict, verification = verification,
       # ⚠️ 강등 (Dual-Mode SOT §3.5): 본 grade/score는 proxy 진단용. 권위 등급은 essence_score().
       authoritative = FALSE, grade_basis = "proxy_diagnostic_18component")
}
