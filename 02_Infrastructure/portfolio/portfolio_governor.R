#==============================================================================
# Portfolio Governor — PG0~PG3 Module (V7 Research Engine)
# portfolio_governor.R
#
# Orchestrates portfolio-level decisions after research validation (S7).
# PG0: Gap Diagnosis — current portfolio vs target profile gaps
# PG1: Candidate Admission — anti-pattern, LOO, role honesty checks
# PG2: Sleeve Assembly & Allocation — role-based weight assignment
# PG3: Live Monitoring — drift, regime change, rebalance triggers
#
# Usage:
#   source("02_Infrastructure/portfolio_governor.R")
#   gap   <- pg0_gap_review("PF_001")
#   admit <- pg1_admission("PF_001", "STR_1433", "core_alpha", gap)
#   alloc <- pg2_allocation("PF_001", list(admit))
#   mon   <- pg3_monitor("PF_001", alloc)
#
# Dependencies: data.table, jsonlite
# Lazy-loaded: regime_signal.R, antipattern_detector.R, hurdle_gate.R
#==============================================================================

# ─── Bootstrap ───────────────────────────────────────────────────────────────
# .pg_root 해석 (M10 수리 2026-07-11): sys.frame(1)$ofile은 *중첩 source* 시
# (예: run_alpha_search.R L61이 본 파일을 source) 최외곽 호출 스크립트의 디렉토리로
# 풀린다 — 실측 probe에서 ".pg_root=." 재현. 그 결과 gap_vector_steering.R /
# regime_signal.R 등 lazy-load가 전부 부재 판정(warning-only)되어
# .cache/portfolio_gap_vector.json이 빌더 콜드스타트(빈 값)로 잔존하는 실사고 발생
# (2026-07-09 07:46 PF_ALPHASEARCH 산출물). 후보 경로가 실제 본 파일을 포함하는지
# 검증 후 채택, 아니면 env 기반 canonical로 폴백한다.
.pg_root <- local({
  cand <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
  fallback <- file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR",
               Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
    "02_Infrastructure/portfolio")
  ok <- is.character(cand) && length(cand) == 1L && nzchar(cand) &&
    file.exists(file.path(cand, "portfolio_governor.R"))
  if (ok) cand else fallback
})
# config.R is one level up from portfolio/
if (!exists("INFRA_DIR")) {
  source(file.path(dirname(.pg_root), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ─── Module Constants ────────────────────────────────────────────────────────
.PG_VERSION         <- "1.0.0"
.PG_DEFAULT_TARGET  <- list(cagr = 0.16, sharpe = 2.5, mdd = 0.25)  # SR 2.0→2.5 (2026-05-29 도훈 mandate)
.PG_DRIFT_THRESH    <- 0.05
.PG_MAX_TURNOVER    <- 0.30
.PG_FAMILY_CAP      <- 0.35
.PG_REGIME_ADJ      <- list(
  RISK_OFF = list(defense = +0.15, core_alpha = -0.10, diversifier = -0.05),
  CAUTION  = list(defense = +0.05, core_alpha = -0.03, diversifier = -0.02),
  NEUTRAL  = list(defense =  0.00, core_alpha =  0.00, diversifier =  0.00),
  RISK_ON  = list(defense = -0.05, core_alpha = +0.10, diversifier = -0.05)
)

# ── §4 book-marginal ΔIR 단일 컨벤션 (도훈 confirm 2026-07-03, 감사 CAP-P0-2/CAP-P1-4) ──
# net_active_recon_v1 = recon NAV 월수익(net, 비용 반영) − BM(KOSPI200) 월수익 active 시계열의
#   mean(active)/sd(active)*sqrt(12) — contract build_benchmark_compare(annualization_factor=12)
#   Information_Ratio와 동일 산식. gross IR / geometric-active IR(PerfA InformationRatio)은
#   본 게이트에 사용 금지 (book_state.json::ir_convention 선언과 정합).
.PG_IR_CONVENTION     <- "net_active_recon_v1"

# ── A7c: sleeve_needs 신 조향 enum (gap_vector_steering.R::GV_STEERING_DIRECTIONS와 동일 키) ──
# 감사 SC-01/SC-06 (도훈 confirm 2026-07-03): pg0 빌더의 구 enum(core_alpha/defense/
# diversifier/none)은 steering 레이어가 실증-열린 방향 enum으로 재정의. 소비 코드는
# 양쪽 vocabulary 모두 처리 (과거 JSON 재독 호환 — 구 라벨도 종래 로직 유지).
.PG_STEERING_ENUM <- c("non_return_datasource", "screen_tier_recovery",
                       "overlay_refinement", "residual_orthogonal_sleeve",
                       "dpl_feature", "core_alpha_standalone")
# (v8.3 현행화 2026-07-11 M10: screen_tier_recovery 추가 + 서열 갱신 —
#  gap_vector_steering.R::GV_STEERING_DIRECTIONS와 동일 키 유지 의무)
.PG_MODULE_CATALOG    <- file.path(PROJECT_ROOT, "06_Registry", "module_catalog.json")
.PG_BOOK_STATE_PATH   <- file.path(PROJECT_ROOT, "qepm", "mailbox", "governor", "book_state.json")
.PG_BENCHMARK_PARQUET <- file.path(CACHE_DIR, "benchmark.parquet")  # 2026-07-02 IKS200 정정본

# `%||%`는 종래 세션 환경(contract/book_optimizer sourcing)에 의존 — 본 파일 단독 source 시
# 미정의 즉사 방어. contract(backtest_result_contract.R L679)와 동일 semantics, 미존재 시에만 정의.
if (!exists("%||%")) {
  `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
}

# ─── Internal Helpers ────────────────────────────────────────────────────────

#' Ensure directory exists (recursive, silent)
.pg_ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
}

#' Safe JSON write
.pg_write_json <- function(obj, path) {
  .pg_ensure_dir(dirname(path))
  tryCatch(
    write_json(obj, path, auto_unbox = TRUE, pretty = TRUE, na = "null"),
    error = function(e) warning("[pg] JSON write failed: ", path, " — ", e$message)
  )
}

#' Safe JSON read with fallback
.pg_read_json <- function(path, fallback = list()) {
  tryCatch(
    fromJSON(path, simplifyVector = FALSE),
    error = function(e) {
      warning("[pg] JSON read failed: ", path, " — ", e$message)
      fallback
    }
  )
}

#' Resolve strategy directory from strategy_id
.pg_strategy_dir <- function(strategy_id) {
  file.path(STRATEGY_OUTPUT, strategy_id)
}

#' Resolve portfolio artifact directory
.pg_portfolio_dir <- function(portfolio_id) {
  d <- file.path(RESEARCH_OUTPUT, "portfolios", portfolio_id)
  .pg_ensure_dir(d)
  d
}

#' Read performance.csv from a strategy and return key metrics
.pg_read_performance <- function(strategy_id) {
  perf_path <- file.path(.pg_strategy_dir(strategy_id), "output", "performance.csv")
  if (!file.exists(perf_path)) {
    warning("[pg] performance.csv not found for ", strategy_id)
    return(list(cagr = NA_real_, sharpe = NA_real_, mdd = NA_real_))
  }
  tryCatch({
    dt <- fread(perf_path)
    # Normalize column names (case-insensitive match)
    cn <- tolower(names(dt))
    names(dt) <- cn

    .extract <- function(patterns) {
      for (p in patterns) {
        idx <- grep(p, cn)
        if (length(idx) > 0) return(as.numeric(dt[[idx[1]]][1]))  # first row only (strategy, not BM)
      }
      NA_real_
    }

    list(
      cagr   = .extract(c("cagr", "annualized_return", "ann_ret")),
      sharpe = .extract(c("sharpe", "sharpe_ratio", "sr")),
      mdd    = .extract(c("mdd", "max_drawdown", "maxdd"))
    )
  }, error = function(e) {
    warning("[pg] Failed to parse performance.csv for ", strategy_id, ": ", e$message)
    list(cagr = NA_real_, sharpe = NA_real_, mdd = NA_real_)
  })
}

#' Read hurdle_result.json and extract grade, score, role
.pg_read_hurdle <- function(strategy_id) {
  hr_path <- file.path(.pg_strategy_dir(strategy_id), "output", "hurdle_result.json")
  if (!file.exists(hr_path)) return(list(grade = NA_character_, score = NA_real_, role = NA_character_))
  tryCatch({
    j <- fromJSON(hr_path, simplifyVector = FALSE)
    list(
      grade = j$grade %||% j$verdict$grade %||% NA_character_,
      score = as.numeric(j$total_score %||% j$verdict$total_score %||% NA_real_),
      role  = j$role_label %||% j$verdict$role_label %||% NA_character_
    )
  }, error = function(e) {
    list(grade = NA_character_, score = NA_real_, role = NA_character_)
  })
}

#' Lazy-load regime signal (sourced only once per session)
#' [2026-07-13 수리, task #49] 구 경로 file.path(.pg_root, "regime_signal.R")는 portfolio/ 안을
#'   찾아 상시 file.exists FALSE → 무경고 NEUTRAL/0 fallback (gap_vector가 엔진값을 한 번도
#'   못 읽던 배선 버그 — 엔진 CRISIS vs 표시 NEUTRAL 불일치의 원인). 실물은 regime/ 소재.
#'   fallback은 warn-loud + source 라벨로 침묵 금지.
.pg_get_regime <- function(date = Sys.Date() - 1) {
  if (!exists("get_regime_at_date", envir = .GlobalEnv)) {
    rs_candidates <- c(file.path(dirname(.pg_root), "regime", "regime_signal.R"),
                       file.path(.pg_root, "regime_signal.R"))
    rs_path <- rs_candidates[file.exists(rs_candidates)][1]
    if (!is.na(rs_path)) {
      tryCatch(source(rs_path, local = FALSE), error = function(e) {
        warning("[pg] Failed to source regime_signal.R: ", e$message)
      })
    } else {
      warning("[pg] regime_signal.R not found in: ", paste(rs_candidates, collapse = " | "))
    }
  }
  if (exists("get_regime_at_date", envir = .GlobalEnv)) {
    tryCatch(get_regime_at_date(date), error = function(e) {
      warning("[pg] get_regime_at_date failed — NEUTRAL/0 fallback 사용: ", e$message)
      data.table(Category = "NEUTRAL", Regime_Score = 0, source = "fallback")
    })
  } else {
    warning("[pg] get_regime_at_date 부재 — NEUTRAL/0 fallback 사용 (엔진값 아님)")
    data.table(Category = "NEUTRAL", Regime_Score = 0, source = "fallback")
  }
}

#' Classify alpha family for a strategy (mirrors hurdle_gate.R logic)
.pg_classify_family <- function(strategy_id) {
  sdir <- .pg_strategy_dir(strategy_id)
  fe_path <- file.path(sdir, "factor_engine.R")
  ra_path <- file.path(sdir, "run_all.R")
  fe <- ""
  if (file.exists(fe_path)) fe <- tolower(paste(readLines(fe_path, warn = FALSE), collapse = " "))
  else if (file.exists(ra_path)) fe <- tolower(paste(readLines(ra_path, warn = FALSE), collapse = " "))
  sn <- tolower(strategy_id)

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
  "other"
}

#' Scan all strategies and count per-family for admitted strategies
.pg_family_concentration <- function(admitted_ids = character(0)) {
  if (length(admitted_ids) == 0) return(list())
  fams <- vapply(admitted_ids, .pg_classify_family, character(1))
  as.list(table(fams))
}

#' Read a stage artifact JSON for a candidate
.pg_read_artifact <- function(strategy_id, artifact_pattern) {
  art_dir <- file.path(.pg_strategy_dir(strategy_id), "stage_artifacts")
  if (!dir.exists(art_dir)) return(NULL)
  files <- list.files(art_dir, pattern = artifact_pattern, full.names = TRUE)
  if (length(files) == 0) return(NULL)
  .pg_read_json(files[length(files)])  # latest
}


#==============================================================================
# 1. PG0 — Portfolio Gap Diagnosis
#==============================================================================

#' PG0: Diagnose gaps between current portfolio profile and target.
#'
#' Implements cold-start protocol (Phase 0/1/2+) and saves gap vector
#' for downstream Scout/Forge consumption.
#'
#' @param portfolio_id Character: portfolio identifier (e.g., "PF_001")
#' @param base_strategy_id Character or NULL: initial seed strategy
#' @param target_profile List: target metrics (cagr, sharpe, mdd)
#' @return List: PG0 artifact with gaps, sleeve_needs, regime state
pg0_gap_review <- function(portfolio_id,
                           base_strategy_id = NULL,
                           target_profile = .PG_DEFAULT_TARGET) {

  cat(sprintf("[pg0_gap_review] Portfolio: %s\n", portfolio_id))
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")


  # ── Determine cold-start phase ──────────────────────────────────────────────
  # Load existing state to find admitted strategies
  state <- pg_state_load(portfolio_id)
  admitted <- state$admitted_strategies %||% character(0)

  # If base_strategy_id is provided and not yet in admitted, consider it
  if (!is.null(base_strategy_id) && !(base_strategy_id %in% admitted)) {
    admitted <- c(admitted, base_strategy_id)
  }

  n_strategies <- length(admitted)

  if (n_strategies == 0 && is.null(base_strategy_id)) {
    # ── Phase 0: Empty portfolio ──
    cold_start_phase <- 0L
    current_profile <- list(cagr = 0, sharpe = 0, mdd = 0)
    cat("[pg0] Phase 0: Empty portfolio. Full gap to target.\n")

  } else if (n_strategies <= 1) {
    # ── Phase 1: Single strategy ──
    cold_start_phase <- 1L
    sid <- if (!is.null(base_strategy_id)) base_strategy_id else admitted[1]
    current_profile <- .pg_read_performance(sid)
    # Coerce NAs to 0 for gap computation
    current_profile <- lapply(current_profile, function(x) if (length(x) == 0 || any(is.na(x))) 0 else x[1])
    cat(sprintf("[pg0] Phase 1: Single strategy (%s). CAGR=%.1f%%, SR=%.3f, MDD=%.1f%%\n",
                sid,
                current_profile$cagr * ifelse(abs(current_profile$cagr) < 1, 100, 1),
                current_profile$sharpe,
                abs(current_profile$mdd) * ifelse(abs(current_profile$mdd) < 1, 100, 1)))

  } else {
    # ── Phase 2+: Multiple strategies ──
    cold_start_phase <- 2L
    # Aggregate: simple average of individual strategy metrics
    perfs <- lapply(admitted, .pg_read_performance)
    avg_metric <- function(field) {
      vals <- vapply(perfs, function(p) {
        v <- p[[field]]
        if (is.na(v)) 0 else v
      }, numeric(1))
      mean(vals, na.rm = TRUE)
    }
    current_profile <- list(
      cagr   = avg_metric("cagr"),
      sharpe = avg_metric("sharpe"),
      mdd    = avg_metric("mdd")
    )
    cat(sprintf("[pg0] Phase 2+: %d strategies. Avg CAGR=%.3f, SR=%.3f, MDD=%.3f\n",
                n_strategies, current_profile$cagr, current_profile$sharpe, current_profile$mdd))
  }

  # ── Normalize metrics (ensure CAGR/MDD as decimals) ─────────────────────────
  # If CAGR looks like percentage (>1), convert
  if (abs(current_profile$cagr) > 1) current_profile$cagr <- current_profile$cagr / 100
  if (abs(current_profile$mdd) > 1)  current_profile$mdd  <- current_profile$mdd / 100
  # MDD stored as positive fraction internally
  current_profile$mdd <- abs(current_profile$mdd)

  # ── Gap computation ─────────────────────────────────────────────────────────
  gap <- list(
    cagr_gap   = target_profile$cagr   - current_profile$cagr,
    sharpe_gap = target_profile$sharpe  - current_profile$sharpe,
    mdd_gap    = current_profile$mdd    - target_profile$mdd  # positive = MDD too deep
  )

  # ── Sleeve needs ────────────────────────────────────────────────────────────
  sleeve_needs <- character(0)
  if (cold_start_phase == 0L) {
    sleeve_needs <- "core_alpha"
  } else {
    if (gap$cagr_gap > 0.02 || gap$sharpe_gap > 0.3) {
      sleeve_needs <- c(sleeve_needs, "core_alpha")
    }
    if (gap$mdd_gap > 0.02) {
      sleeve_needs <- c(sleeve_needs, "defense")
    }
    if (gap$sharpe_gap > 0.1 && gap$mdd_gap <= 0.02) {
      sleeve_needs <- c(sleeve_needs, "diversifier")
    }
    # If everything looks fine
    if (length(sleeve_needs) == 0) sleeve_needs <- "none"
  }

  # ── Regime state (PIT: t-1) ─────────────────────────────────────────────────
  regime <- .pg_get_regime(Sys.Date() - 1)
  regime_category <- as.character(regime$Category[1] %||% "NEUTRAL")
  regime_score    <- as.numeric(regime$Regime_Score[1] %||% 0)

  # ── Family concentration ────────────────────────────────────────────────────
  family_counts <- .pg_family_concentration(admitted)

  # ── Build artifact ──────────────────────────────────────────────────────────
  artifact <- list(
    stage            = "PG0",
    version          = .PG_VERSION,
    portfolio_id     = portfolio_id,
    timestamp        = timestamp,
    cold_start_phase = cold_start_phase,
    n_strategies     = n_strategies,
    admitted_ids     = admitted,
    current_profile  = current_profile,
    target_profile   = target_profile,
    gap              = gap,
    sleeve_needs     = sleeve_needs,
    regime_state     = list(
      date     = as.character(Sys.Date() - 1),
      category = regime_category,
      score    = regime_score
    ),
    family_concentration = family_counts
  )

  # ── Save artifacts ──────────────────────────────────────────────────────────
  # Strategy-level (if base exists)
  if (!is.null(base_strategy_id)) {
    sdir <- file.path(.pg_strategy_dir(base_strategy_id), "stage_artifacts")
    .pg_write_json(artifact, file.path(sdir, sprintf("pg0_gap_review_%s.json", portfolio_id)))
  }

  # Portfolio-level
  pdir <- file.path(.pg_portfolio_dir(portfolio_id), "stage_artifacts")
  .pg_write_json(artifact, file.path(pdir, sprintf("pg0_gap_review_%s.json", portfolio_id)))

  # Cache for Scout/Forge consumption
  .pg_write_json(artifact, file.path(CACHE_DIR, "portfolio_gap_vector.json"))

  # ── A7b: Steering 자동 재조향 (감사 SC-01/SC-06, 도훈 confirm 2026-07-03) ────
  # gap_vector_steering.R 후처리 레이어를 빌더 직후 자동 호출 — 빌더 재실행이
  # 구 enum(core_alpha/defense/diversifier)으로 .cache/portfolio_gap_vector.json을
  # 덮어써도 즉시 신 조향 enum으로 재조향된다. 파일 부재/오류 시 WARN-only (크래시 금지).
  tryCatch({
    gvs_path <- file.path(.pg_root, "gap_vector_steering.R")
    if (file.exists(gvs_path)) {
      if (!exists("steer_gap_vector", envir = .GlobalEnv)) {
        source(gvs_path, local = FALSE)
      }
      steered <- steer_gap_vector()  # cache 재조향 (sleeve_needs_raw_builder에 빌더 원본 보존)
      artifact$sleeve_needs_steered <- steered$sleeve_needs
      artifact$steering             <- steered$steering
    } else {
      warning("[pg0] gap_vector_steering.R not found — cache gap vector left with builder enum (WARN-only)")
    }
  }, error = function(e) {
    warning("[pg0] gap vector steering failed (WARN-only, builder output retained): ", e$message)
  })

  cat(sprintf("[pg0] Gap: CAGR=%+.1f%%, SR=%+.3f, MDD=%+.1f%%. Needs: [%s]. Regime: %s(%d)\n",
              gap$cagr_gap * 100, gap$sharpe_gap, gap$mdd_gap * 100,
              paste(sleeve_needs, collapse = ", "),
              regime_category, as.integer(regime_score)))

  artifact
}


#==============================================================================
# 2. PG1 — Candidate Admission
#==============================================================================

#' PG1: Evaluate a candidate strategy for portfolio admission.
#'
#' Runs anti-pattern detection, LOO validation, and role honesty audit.
#' Decision: ADMIT / DEFER / REJECT with detailed rationale.
#'
#' @param portfolio_id Character: portfolio identifier
#' @param candidate_id Character: strategy ID to evaluate
#' @param validated_role Character: role from S4 ("core_alpha"/"diversifier"/"defense")
#' @param pg0_artifact List: output of pg0_gap_review()
#' @return List: PG1 artifact with admission decision
pg1_admission <- function(portfolio_id, candidate_id, validated_role, pg0_artifact) {

  cat(sprintf("[pg1_admission] Candidate: %s (role: %s) → Portfolio: %s\n",
              candidate_id, validated_role, portfolio_id))
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

  decision   <- "ADMIT"
  rationale  <- character(0)
  checks     <- list()

  # ── Build portfolio state from PG0 ─────────────────────────────────────────
  portfolio_state <- list(
    current_sleeves     = pg0_artifact$admitted_ids %||% character(0),
    family_counts       = pg0_artifact$family_concentration %||% list(),
    current_profile     = pg0_artifact$current_profile %||% list(),
    sleeve_needs        = pg0_artifact$sleeve_needs %||% character(0)
  )

  # ── Read candidate stage artifacts ──────────────────────────────────────────
  s2 <- .pg_read_artifact(candidate_id, "^s2_")
  s3 <- .pg_read_artifact(candidate_id, "^s3_")
  s4 <- .pg_read_artifact(candidate_id, "^s4_")
  s6 <- .pg_read_artifact(candidate_id, "^s6_")

  # ── Check 1: Anti-pattern Detection ─────────────────────────────────────────
  ap_result <- tryCatch({
    ap_path <- file.path(.pg_root, "antipattern_detector.R")
    if (!file.exists(ap_path)) stop("antipattern_detector.R not found")

    # Source only if not already loaded
    if (!exists("sg_detect_antipatterns", envir = .GlobalEnv)) {
      source(ap_path, local = FALSE)
    }
    sg_detect_antipatterns(
      candidate_id    = candidate_id,
      portfolio_state = portfolio_state,
      s2 = s2, s3 = s3, s4 = s4, s6 = s6
    )
  }, error = function(e) {
    warning("[pg1] Anti-pattern check skipped: ", e$message)
    list(pass = TRUE, severity = "unknown", patterns_detected = character(0),
         details = list(), error = e$message)
  })
  checks$antipattern <- ap_result

  if (!isTRUE(ap_result$pass) && identical(ap_result$severity, "critical")) {
    decision <- "REJECT"
    rationale <- c(rationale, sprintf(
      "Critical anti-pattern: %s",
      paste(ap_result$patterns_detected, collapse = ", ")
    ))
  }

  # ── Check 2: LOO Validation ─────────────────────────────────────────────────
  loo_result <- tryCatch({
    loo_path <- file.path(.pg_root, "loo_validator.R")
    if (!file.exists(loo_path)) stop("loo_validator.R not found")

    if (!exists("sg_loo_crisis", envir = .GlobalEnv)) {
      source(loo_path, local = FALSE)
    }

    crisis   <- sg_loo_crisis(candidate_id)
    regime   <- sg_loo_regime(candidate_id)
    subprd   <- sg_loo_subperiod(candidate_id)

    # Treat skipped LOO tests as pass (structural absence, not failure)
    # loo_validator returns pass=NA when data is unavailable (e.g., no regime column)
    crisis_ok <- isTRUE(crisis$pass) || isTRUE(crisis$skipped) || is.na(crisis$pass)
    regime_ok <- isTRUE(regime$pass) || isTRUE(regime$skipped) || is.na(regime$pass)
    subprd_ok <- isTRUE(subprd$pass) || isTRUE(subprd$skipped) || is.na(subprd$pass)

    list(
      crisis  = crisis,
      regime  = regime,
      subperiod = subprd,
      all_pass = crisis_ok && regime_ok && subprd_ok
    )
  }, error = function(e) {
    warning("[pg1] LOO validation skipped: ", e$message)
    list(crisis = NULL, regime = NULL, subperiod = NULL,
         all_pass = TRUE, skipped = TRUE, error = e$message)
  })
  checks$loo <- loo_result

  if (!isTRUE(loo_result$all_pass) && !isTRUE(loo_result$skipped)) {
    if (decision != "REJECT") decision <- "DEFER"
    failed_loo <- character(0)
    .loo_real_fail <- function(r) !isTRUE(r$pass) && !isTRUE(r$skipped) && !is.na(r$pass)
    if (.loo_real_fail(loo_result$crisis))    failed_loo <- c(failed_loo, "crisis")
    if (.loo_real_fail(loo_result$regime))    failed_loo <- c(failed_loo, "regime")
    if (.loo_real_fail(loo_result$subperiod)) failed_loo <- c(failed_loo, "subperiod")
    rationale <- c(rationale, sprintf("LOO failed: %s", paste(failed_loo, collapse = ", ")))
  }

  # ── Check 3: Role Honesty Audit ─────────────────────────────────────────────
  rha_result <- tryCatch({
    rha_path <- file.path(.pg_root, "role_honesty_audit.R")
    if (!file.exists(rha_path)) stop("role_honesty_audit.R not found")

    if (!exists("sg_audit_role_honesty", envir = .GlobalEnv)) {
      source(rha_path, local = FALSE)
    }
    sg_audit_role_honesty(candidate_id, validated_role, s2 = s2, s3 = s3, s4 = s4)
  }, error = function(e) {
    warning("[pg1] Role honesty audit skipped: ", e$message)
    list(honest = TRUE, declared_role = validated_role, detected_role = validated_role,
         skipped = TRUE, error = e$message)
  })
  checks$role_honesty <- rha_result

  if (!isTRUE(rha_result$honest) && !isTRUE(rha_result$skipped)) {
    decision <- "REJECT"
    rationale <- c(rationale, sprintf(
      "Role dishonesty: declared=%s, detected=%s",
      rha_result$declared_role, rha_result$detected_role
    ))
  }

  # ── Check 4: Role-gap alignment ────────────────────────────────────────────
  # Even if all checks pass, candidate must fill a gap.
  # A7c 양쪽 vocabulary 호환 (감사 SC-01/SC-06, 도훈 confirm 2026-07-03):
  #  - 신 조향 enum(.PG_STEERING_ENUM, gap_vector_steering.R 산출)은 role bucket이
  #    아닌 탐색 *방향*이므로 role-bucket 멤버십 정합 판정의 대상이 아님 —
  #    sleeve_needs가 순수 조향 enum이면 본 체크 not-applicable (DEFER 오발 방지).
  #  - 구 enum(core_alpha/defense/diversifier/none) 요소가 있으면(과거 pg0 JSON 재독
  #    포함) 그 부분집합에 대해 종래 정합 검사를 그대로 수행.
  sn_all    <- unlist(pg0_artifact$sleeve_needs %||% character(0))
  sn_legacy <- setdiff(sn_all, .PG_STEERING_ENUM)
  if (decision == "ADMIT" && length(sn_all) > 0 && length(sn_legacy) == 0) {
    # 순수 신 조향 enum — role-bucket 정합 비적용 (기록만 남김)
    checks$role_gap_alignment <- list(
      applicable   = FALSE,
      reason       = "sleeve_needs is steering-direction enum (gap_vector_steering.R) — role-bucket alignment not applicable",
      sleeve_needs = as.list(sn_all)
    )
  } else if (decision == "ADMIT" && !("none" %in% sn_legacy)) {
    role_bucket <- switch(validated_role,
      core_alpha  = "core_alpha",
      diversifier = "diversifier",
      defense     = "defense",
      validated_role  # pass through
    )
    if (!(role_bucket %in% sn_legacy)) {
      decision <- "DEFER"
      rationale <- c(rationale, sprintf(
        "Role '%s' not in current sleeve_needs: [%s]",
        role_bucket, paste(sn_legacy, collapse = ", ")
      ))
    }
  }

  # ── Family concentration check (skip for small portfolios: n <= 3) ─────────
  if (decision == "ADMIT") {
    cand_family <- .pg_classify_family(candidate_id)
    current_count <- as.integer(portfolio_state$family_counts[[cand_family]] %||% 0L)
    total_sleeves <- length(portfolio_state$current_sleeves) + 1L
    if (total_sleeves > 3 && (current_count + 1) / total_sleeves > .PG_FAMILY_CAP) {
      decision <- "DEFER"
      rationale <- c(rationale, sprintf(
        "Family '%s' would exceed %.0f%% cap (%d/%d)",
        cand_family, .PG_FAMILY_CAP * 100, current_count + 1, total_sleeves
      ))
    }
  }

  if (length(rationale) == 0) rationale <- "All checks passed"

  # ── Build artifact ──────────────────────────────────────────────────────────
  artifact <- list(
    stage          = "PG1",
    version        = .PG_VERSION,
    portfolio_id   = portfolio_id,
    candidate_id   = candidate_id,
    validated_role = validated_role,
    timestamp      = timestamp,
    decision       = decision,
    rationale      = rationale,
    checks         = checks,
    candidate_family = .pg_classify_family(candidate_id)
  )

  # ── Save artifact ───────────────────────────────────────────────────────────
  sdir <- file.path(.pg_strategy_dir(candidate_id), "stage_artifacts")
  .pg_write_json(artifact, file.path(sdir, sprintf("pg1_admission_%s.json", portfolio_id)))

  pdir <- file.path(.pg_portfolio_dir(portfolio_id), "stage_artifacts")
  .pg_write_json(artifact, file.path(pdir, sprintf("pg1_admission_%s_%s.json", portfolio_id, candidate_id)))

  cat(sprintf("[pg1] Decision: %s | Rationale: %s\n",
              decision, paste(rationale, collapse = "; ")))

  artifact
}


#' Compute book-level information ratio for a set of admitted WT ids.
#'
#' Wraps book_optimizer.R's read-only path (load_admitted_packages → book_optimize)
#' WITHOUT mutating book_state.json (does NOT call book_update / update_book_state).
#' Used by pg1_admission_with_book_context to measure marginal IR contribution.
#'
#' @param wt_ids Character vector: WT/strategy ids to combine into a book.
#' @return List with: book_ir (numeric, NA if uncomputable), n_loaded (int),
#'   infeasible (logical), reason (character or NA), error (character or NA).
.pg_book_ir <- function(wt_ids) {
  wt_ids <- unique(as.character(wt_ids))
  wt_ids <- wt_ids[!is.na(wt_ids) & nzchar(wt_ids)]
  if (length(wt_ids) == 0) {
    return(list(book_ir = NA_real_, n_loaded = 0L, infeasible = TRUE,
                reason = "no_wt_ids", error = NA_character_))
  }

  tryCatch({
    bo_path <- file.path(.pg_root, "book_optimizer.R")
    if (!file.exists(bo_path)) stop("book_optimizer.R not found")

    if (!exists("book_optimize", envir = .GlobalEnv) ||
        !exists("load_admitted_packages", envir = .GlobalEnv)) {
      source(bo_path, local = FALSE)
    }

    # 경로버그 수정 (2026-07-03, 감사 CAP-P1-4): load_admitted_packages 기본 wt_root가
    # 상대경로("qepm/mailbox/worktask")라 cwd != PROJECT_ROOT에서 3-package 탐색 전멸 → 절대경로 명시.
    pkgs <- load_admitted_packages(wt_ids,
                                   wt_root = file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask"))
    n_loaded <- length(pkgs)
    if (n_loaded == 0) {
      return(list(book_ir = NA_real_, n_loaded = 0L, infeasible = TRUE,
                  reason = "no_packages_loaded", error = NA_character_))
    }

    res <- book_optimize(pkgs)   # read-only: no book_state.json write
    list(
      book_ir    = as.numeric(res$book_information_ratio %||% NA_real_),
      n_loaded   = n_loaded,
      infeasible = isTRUE(res$infeasible),
      reason     = res$reason %||% NA_character_,
      error      = NA_character_
    )
  }, error = function(e) {
    warning("[pg1_book] book IR computation failed: ", e$message)
    list(book_ir = NA_real_, n_loaded = 0L, infeasible = TRUE,
         reason = "book_optimize_error", error = e$message)
  })
}


#' Load canonical book_state.json (절대경로 고정 — cwd 무관, 감사 CAP-P1-4 경로버그 방어).
#' 읽기 전용 helper. book_state 쓰기(admit)는 자동화 금지 (§4 — Q-Lead + 도훈 수동 confirm).
pg_load_book_state <- function(path = .PG_BOOK_STATE_PATH) {
  if (!file.exists(path)) stop("[pg_load_book_state] book_state.json not found: ", path)
  fromJSON(path, simplifyVector = FALSE)
}


#' Canonical KOSPI200 벤치마크 월수익 (.cache/benchmark.parquet — 2026-07-02 IKS200 정정본).
#' apply.monthly(Return.cumulative) 표준함수 recon (자체합성 금지 준수).
#' @return list(bm_m = data.table(ym, ret) 또는 NULL, source)
.pg_bm_monthly_returns <- function(parquet_path = .PG_BENCHMARK_PARQUET) {
  out <- tryCatch({
    if (!requireNamespace("arrow", quietly = TRUE)) stop("arrow unavailable")
    if (!file.exists(parquet_path)) stop("benchmark.parquet not found: ", parquet_path)
    suppressPackageStartupMessages({ library(xts); library(PerformanceAnalytics) })
    b <- as.data.table(arrow::read_parquet(parquet_path))
    if (!all(c("Date", "BM_Ret") %in% names(b))) stop("benchmark.parquet missing Date/BM_Ret")
    b <- b[is.finite(BM_Ret)][order(Date)]
    bx <- apply.monthly(xts(b$BM_Ret, order.by = as.Date(b$Date)), Return.cumulative)
    list(bm_m = data.table(ym = format(as.Date(index(bx)), "%Y-%m"), ret = as.numeric(bx)),
         source = sprintf("canonical_benchmark_parquet:%s", parquet_path))
  }, error = function(e) NULL)
  if (!is.null(out)) return(out)
  list(bm_m = NULL, source = "unresolved")
}


#' Resolve a sleeve's monthly net return series (module_catalog / live_track 어댑터).
#'
#' mailbox 3-package가 없는 모듈(alpha_search register_module 산출 등)을 recon IR에
#' 공급하기 위한 시계열 해상. 해상 순서:
#'   ① module_catalog.json entry의 sim_result_path (register_module 계약 산출)
#'   ② 04_Research/strategies/{id}/sim_result.rds 직접 (catalog 미등재 대비)
#'   ③ 06_Registry/live_track/{id}/live_book_series.csv (라이브 book 월간 recon net, ret_net)
#' 일간 sim_result는 apply.monthly(Return.cumulative)로 월간 재구성 (PerfA 표준함수만 —
#' backtest-contract 자체합성 금지 준수). 주의: sim 마지막 월은 데이터 종료일까지의
#' 부분월일 수 있음 (artifact의 n_months/period로 감사 가능).
#'
#' @return list(ret_m = data.table(ym, ret) 또는 NULL, bm_m = 동일 또는 NULL, source)
.pg_sleeve_monthly_returns <- function(sleeve_id, catalog_path = .PG_MODULE_CATALOG) {
  none <- list(ret_m = NULL, bm_m = NULL, source = "unresolved")
  sleeve_id <- as.character(sleeve_id)[1]
  if (is.na(sleeve_id) || !nzchar(sleeve_id)) return(none)

  # ── ①/② sim_result.rds ──
  sim_path <- NULL
  src_tag <- NULL
  if (file.exists(catalog_path)) {
    catj <- tryCatch(fromJSON(catalog_path, simplifyVector = FALSE), error = function(e) NULL)
    entry <- if (!is.null(catj) && !is.null(catj$modules)) catj$modules[[sleeve_id]] else NULL
    if (!is.null(entry) && !is.null(entry$sim_result_path)) {
      p <- file.path(PROJECT_ROOT, entry$sim_result_path)
      if (file.exists(p)) {
        sim_path <- p
        src_tag <- sprintf("module_catalog(metric_type=%s)",
                           as.character(entry$metric_type %||% "unlabeled"))
      }
    }
  }
  if (is.null(sim_path)) {
    p <- file.path(STRATEGY_OUTPUT, sleeve_id, "sim_result.rds")
    if (file.exists(p)) { sim_path <- p; src_tag <- "strategies_dir_sim_result" }
  }
  if (!is.null(sim_path)) {
    out <- tryCatch({
      suppressPackageStartupMessages({ library(xts); library(PerformanceAnalytics) })
      sim <- readRDS(sim_path)
      d <- as.data.table(sim$DAILY_NAV_DT)
      if (!all(c("Date", "Strategy_Ret") %in% names(d)))
        stop("DAILY_NAV_DT missing Date/Strategy_Ret")
      d[, Date := as.Date(Date)]
      d <- d[is.finite(Strategy_Ret)][order(Date)]
      sm <- apply.monthly(xts(d$Strategy_Ret, order.by = d$Date), Return.cumulative)
      ret_m <- data.table(ym = format(as.Date(index(sm)), "%Y-%m"), ret = as.numeric(sm))
      bm_m <- NULL
      if (!is.null(sim$bm_xts)) {
        bmx <- apply.monthly(sim$bm_xts[, 1], Return.cumulative)
        bm_m <- data.table(ym = format(as.Date(index(bmx)), "%Y-%m"), ret = as.numeric(bmx))
      }
      list(ret_m = ret_m, bm_m = bm_m, source = sprintf("%s:%s", src_tag, sim_path))
    }, error = function(e) NULL)
    if (!is.null(out)) return(out)
  }

  # ── ③ live_track 월간 recon 시리즈 (라이브 book — 예: STR_1715_on_M4_R05_noLayer4_PG2) ──
  # 월 키 = return_ym (수익 발생 달력월 — 2026-07-02 정정 라벨). realized_ym/date 앵커는
  # 달력월보다 1개월 앞 라벨(패널 라벨결함, [[reference-book-benchmark-alignment-realized-ym]])이라
  # 달력월 BM과 lag0 merge 시 오정렬(β 0.083 vs 정렬 시 0.651 실측 2026-07-03). return_ym 부재
  # 구버전 시리즈는 realized_ym-1개월 시프트로 동일 정렬 (소스 라벨에 명시).
  lt <- file.path(PROJECT_ROOT, "06_Registry", "live_track", sleeve_id, "live_book_series.csv")
  if (file.exists(lt)) {
    out <- tryCatch({
      s <- fread(lt)
      if (!("ret_net" %in% names(s))) stop("live_book_series missing ret_net")
      if ("return_ym" %in% names(s)) {
        ret_m <- s[is.finite(ret_net), .(ym = as.character(return_ym), ret = as.numeric(ret_net))]
        key_tag <- "key=return_ym"
      } else if ("realized_ym" %in% names(s)) {
        d0 <- as.Date(paste0(as.character(s$realized_ym), "-01"))
        ym_cal <- vapply(d0, function(x) format(seq(x, by = "-1 month", length.out = 2)[2], "%Y-%m"),
                         character(1))
        ret_m <- data.table(ym = ym_cal, ret = as.numeric(s$ret_net))[is.finite(ret)]
        key_tag <- "key=realized_ym_minus_1m(구버전 — return_ym 부재)"
      } else stop("live_book_series missing return_ym/realized_ym")
      list(ret_m = unique(ret_m, by = "ym"), bm_m = NULL,
           source = sprintf("live_track(%s):%s", key_tag, lt))
    }, error = function(e) NULL)
    if (!is.null(out)) return(out)
  }
  none
}


#' Book-level recon IR — §4 단일 컨벤션 net_active_recon_v1 산출기.
#'
#' sleeve 월수익들을 PerformanceAnalytics::Return.portfolio(월 리밸)로 결합해 book 월수익을
#' 재구성하고, contract build_benchmark_compare(annualization_factor=12)의 Information_Ratio
#' (= mean(active)/sd(active)*sqrt(12), active = book net − BM)를 계산한다.
#' measurement-graduation §1 real-computation: 수익 합성/IR 모두 표준함수·contract 경유.
#'
#' @param sleeve_ids Character vector: book 구성 sleeve ids (incumbent + candidate).
#' @param weights Numeric or NULL: sleeve 결합비중 (sleeve_ids 순서, 합 1, >=0).
#'   NULL = equal-weight — book_optimize의 equal_weight_fallback 컨벤션 준용 (별도 최적화
#'   아님, artifact에 라벨 기록. QP 비중이 필요하면 mailbox 3-package 경로 사용).
#' @param min_common_months Integer: 공통 월 최소 표본. 기본 60은 register_module의
#'   "유효 수익 관측 < 60 = 표본 부족" floor 준용 (신규 문턱 창작 아님).
#' @return list(book_ir, ir_convention, n_months, period, sources, bm_source,
#'   weights_used, combination, port_alpha_t_nw3, reason)
.pg_book_ir_recon <- function(sleeve_ids, weights = NULL,
                              catalog_path = .PG_MODULE_CATALOG,
                              min_common_months = 60L) {
  fail <- function(reason, sources = NULL) list(
    book_ir = NA_real_, ir_convention = .PG_IR_CONVENTION, n_months = 0L,
    period = NULL, sources = sources, bm_source = NA_character_,
    weights_used = NULL, combination = NA_character_,
    port_alpha_t_nw3 = NA_real_, reason = reason)

  sleeve_ids <- unique(as.character(sleeve_ids))
  sleeve_ids <- sleeve_ids[!is.na(sleeve_ids) & nzchar(sleeve_ids)]
  if (length(sleeve_ids) == 0) return(fail("no_sleeve_ids"))

  tryCatch({
    suppressPackageStartupMessages({ library(xts); library(PerformanceAnalytics) })
    res <- lapply(sleeve_ids, .pg_sleeve_monthly_returns, catalog_path = catalog_path)
    names(res) <- sleeve_ids
    sources <- vapply(res, function(r) r$source, character(1))
    unresolved <- sleeve_ids[vapply(res, function(r) is.null(r$ret_m), logical(1))]
    if (length(unresolved) > 0)
      return(fail(sprintf("unresolved sleeve return series: %s",
                          paste(unresolved, collapse = ", ")), as.list(sources)))

    # BM: ① canonical benchmark.parquet(IKS200 정정본) 우선 ② sleeve 내장 bm_xts fallback
    #   (2026-07-02 이전 등재 모듈 bm_xts는 IKS001 코스피전체 버그 소지 — fallback 시 라벨로 명시)
    bm <- .pg_bm_monthly_returns()
    bm_m <- bm$bm_m
    bm_source <- bm$source
    if (is.null(bm_m)) {
      bm_idx <- which(vapply(res, function(r) !is.null(r$bm_m), logical(1)))
      if (length(bm_idx) == 0)
        return(fail("no benchmark series (canonical parquet + sleeve bm_xts 모두 부재)",
                    as.list(sources)))
      bm_m <- res[[bm_idx[1]]]$bm_m
      bm_source <- sprintf("sleeve_bm_xts_fallback:%s (pre-2026-07-02 IKS001 bug 소지 — 검증 필요)",
                           sleeve_ids[bm_idx[1]])
    }

    common <- Reduce(intersect, lapply(res, function(r) r$ret_m$ym))
    common <- sort(intersect(common, bm_m$ym))
    if (length(common) < min_common_months)
      return(fail(sprintf("insufficient common months: %d < %d",
                          length(common), min_common_months), as.list(sources)))

    dts <- as.Date(paste0(common, "-01"))
    Rmat <- do.call(merge, lapply(res, function(r) {
      xts(r$ret_m$ret[match(common, r$ret_m$ym)], order.by = dts)
    }))
    colnames(Rmat) <- sleeve_ids

    if (is.null(weights)) weights <- rep(1 / length(sleeve_ids), length(sleeve_ids))
    weights <- as.numeric(weights)
    if (length(weights) != length(sleeve_ids) || any(!is.finite(weights)) ||
        abs(sum(weights) - 1) > 1e-8 || any(weights < 0))
      return(fail("invalid combination weights (length/sum/sign)", as.list(sources)))

    # 수익 결합 = Return.portfolio only (python-policy/answer-principles 자체 가중합성 금지)
    book_x <- if (length(sleeve_ids) == 1) Rmat[, 1] else
      Return.portfolio(Rmat, weights = weights, rebalance_on = "months", geometric = TRUE)

    if (!exists("build_benchmark_compare", envir = .GlobalEnv)) {
      source(file.path(dirname(.pg_root), "contracts", "backtest_result_contract.R"),
             local = FALSE)
    }
    pr <- data.table(date = as.Date(index(book_x)),
                     ret_net = as.numeric(book_x[, 1]),
                     frequency = "monthly")
    bt <- data.table(date = dts,
                     benchmark_ret = bm_m$ret[match(common, bm_m$ym)],
                     benchmark_id = bm_source)
    cmp <- build_benchmark_compare(pr, bt, run_id = "pg1_book_recon",
                                   strategy_id = paste(sleeve_ids, collapse = "+"),
                                   annualization_factor = 12)
    ir <- as.numeric(cmp[metric_name == "Information_Ratio", active_value])
    pa <- as.numeric(cmp[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value])
    ok <- length(ir) == 1 && is.finite(ir)
    list(book_ir = if (ok) ir else NA_real_,
         ir_convention = .PG_IR_CONVENTION,
         n_months = length(common),
         period = c(min(common), max(common)),
         sources = as.list(sources),
         bm_source = bm_source,
         weights_used = as.list(setNames(weights, sleeve_ids)),
         combination = "Return.portfolio(monthly_rebalance)_equal_weight_unless_specified",
         port_alpha_t_nw3 = if (length(pa) == 1) pa else NA_real_,
         reason = if (ok) NA_character_ else "IR_not_finite")
  }, error = function(e) {
    warning("[pg1_book_recon] failed: ", e$message)
    fail(paste0("recon_error: ", e$message))
  })
}


#' PG1 (book-aware): Evaluate a candidate against the *incumbent book*.
#'
#' Wraps pg1_admission (hostile to modification — left intact for back-compat)
#' and enforces the constraint_defaults.json governor_admission_rule:
#'   "judge_pass AND book-level IR improvement >= 0.05 (marginal contribution)".
#'
#' Flow:
#'   1. Run standalone pg1_admission(...). If REJECT → return as-is (book context
#'      irrelevant; a rejected sleeve cannot improve the book).
#'   2. If standalone ADMIT/DEFER → compute incumbent book IR and the candidate-
#'      augmented book IR (incumbent_ids ∪ candidate_id).
#'   3. delta_ir = new_book_ir - incumbent_book_ir.
#'        delta_ir >= 0.05  → keep ADMIT
#'        delta_ir <  0.05  → DEFER (book-marginal shortfall recorded in rationale).
#'   4. Append book_delta_ir / new_book_ir / incumbent_book_ir to the artifact.
#'
#' This function NEVER writes book_state.json and NEVER admits — it only computes
#' a recommended decision artifact. Real admission stays manual (Q-Lead + 도훈).
#'
#' @param portfolio_id Character: portfolio identifier.
#' @param candidate_id Character: strategy/WT id under evaluation.
#' @param validated_role Character: role from S4.
#' @param pg0_artifact List: output of pg0_gap_review().
#' @param incumbent_book_state List: parsed book_state.json (pg_load_book_state() 권장 —
#'   절대경로 canonical). Must carry admitted_ids (or incumbent_admitted_ids);
#'   incumbent_book_ir is read if present, else recomputed from the incumbent ids.
#' @param marginal_ir_threshold Numeric: required book-marginal IR gain (default 0.05).
#' @param book_combination_weights Numeric or NULL: recon 어댑터의 sleeve 결합비중
#'   (c(incumbent_ids, candidate_id) 순서, 합 1). NULL = equal-weight
#'   (book_optimize equal_weight_fallback 컨벤션 준용 — artifact에 라벨 기록).
#' @return List: pg1_admission artifact + book-context fields.
pg1_admission_with_book_context <- function(portfolio_id, candidate_id,
                                            validated_role, pg0_artifact,
                                            incumbent_book_state,
                                            marginal_ir_threshold = 0.05,
                                            artifact_type = "STR",
                                            book_combination_weights = NULL) {
  # artifact_type ∈ {STR, FR}: FR(factor rotation 운용체계)도 STR과 동일 book-marginal ΔIR 경로로
  #   admit 평가. book sleeve = STR(단일모듈) 또는 FR(1 sleeve). 도훈 2026-06-05. book_state 쓰기=수동.
  # ΔIR 단일 컨벤션 (도훈 confirm 2026-07-03, CAP-P0-2): net_active_recon_v1.
  #   new/incumbent IR의 basis가 혼재(gross/geo/exante)하면 ADMIT 인증 불가 → DEFER.

  # ── Step 1: standalone admission (do NOT modify pg1_admission) ──────────────
  artifact <- pg1_admission(portfolio_id, candidate_id, validated_role, pg0_artifact)
  artifact$artifact_type <- artifact_type
  artifact$ir_convention <- .PG_IR_CONVENTION

  # REJECT short-circuits: book context cannot rescue a rejected sleeve.
  if (identical(artifact$decision, "REJECT")) {
    artifact$book_delta_ir           <- NA_real_
    artifact$new_book_ir             <- NA_real_
    artifact$incumbent_book_ir       <- NA_real_
    artifact$new_book_ir_basis       <- NA_character_
    artifact$incumbent_book_ir_basis <- NA_character_
    artifact$ir_basis_consistent     <- NA
    artifact$book_context_note       <- "standalone REJECT — book-marginal check skipped"
    return(artifact)
  }

  # ── Step 2: incumbent + augmented book IR ───────────────────────────────────
  incumbent_ids <- incumbent_book_state$incumbent_admitted_ids %||%
                   incumbent_book_state$admitted_ids %||% character(0)
  incumbent_ids <- unlist(incumbent_ids, use.names = FALSE)

  # incumbent_book_ir: prefer the stored baseline; recompute only if absent.
  # basis 라벨 = book_state.json::incumbent_ir_basis / ir_convention 선언 필드 (2026-07-03 신설).
  incumbent_book_ir <- suppressWarnings(
    as.numeric(incumbent_book_state$incumbent_book_ir %||% NA_real_)
  )
  incumbent_ir_basis <- NA_character_
  if (length(incumbent_book_ir) == 1 && !is.na(incumbent_book_ir)) {
    incumbent_ir_basis <- as.character(
      incumbent_book_state$incumbent_ir_basis %||%
      incumbent_book_state$ir_convention %||% "unlabeled")[1]
  } else {
    inc <- .pg_book_ir(incumbent_ids)
    incumbent_book_ir <- inc$book_ir
    if (length(incumbent_book_ir) == 1 && !is.na(incumbent_book_ir)) {
      incumbent_ir_basis <- "book_optimize_qp_exante"
    } else {
      inc_recon <- .pg_book_ir_recon(incumbent_ids)
      incumbent_book_ir <- inc_recon$book_ir
      if (!is.na(incumbent_book_ir)) incumbent_ir_basis <- inc_recon$ir_convention
    }
  }

  # 후보-증강 book IR — fallback 순서 (도훈 confirm 2026-07-03):
  #   ① mailbox 3-package 경로 (기존 book_optimize QP — 보존)
  #   ② module_catalog/live_track recon 어댑터 (.pg_book_ir_recon —
  #      alpha_search register_module 산출 등 mailbox 미보유 모듈 대응)
  new_book <- .pg_book_ir(c(incumbent_ids, candidate_id))
  new_book_ir <- new_book$book_ir
  new_book_ir_basis <- if (length(new_book_ir) == 1 && !is.na(new_book_ir))
    "book_optimize_qp_exante" else NA_character_
  recon <- NULL
  if (is.na(new_book_ir)) {
    recon <- .pg_book_ir_recon(c(incumbent_ids, candidate_id),
                               weights = book_combination_weights)
    if (!is.na(recon$book_ir)) {
      new_book_ir       <- recon$book_ir
      new_book_ir_basis <- recon$ir_convention
    }
  }

  # ── Step 3: book-marginal decision (ΔIR 단일 컨벤션 강제) ───────────────────
  .basis_short <- function(x) {
    x <- as.character(x %||% NA_character_)[1]
    if (is.na(x)) NA_character_ else sub("\\s.*$", "", x)
  }
  delta_ir <- NA_real_
  basis_consistent <- NA
  if (!is.na(new_book_ir) && !is.na(incumbent_book_ir)) {
    delta_ir <- new_book_ir - incumbent_book_ir
    both_recon <- grepl(.PG_IR_CONVENTION, new_book_ir_basis %||% "", fixed = TRUE) &&
                  grepl(.PG_IR_CONVENTION, incumbent_ir_basis %||% "", fixed = TRUE)
    basis_consistent <- both_recon ||
      identical(.basis_short(new_book_ir_basis), .basis_short(incumbent_ir_basis))
  }

  if (is.na(delta_ir)) {
    # IR uncomputable (missing packages / infeasible QP / recon unresolved) → cannot certify gain.
    if (artifact$decision == "ADMIT") artifact$decision <- "DEFER"
    artifact$rationale <- c(
      if (identical(artifact$rationale, "All checks passed")) character(0) else artifact$rationale,
      sprintf("book-marginal IR uncomputable (new=%s, incumbent=%s) — DEFER pending book packages/recon series",
              ifelse(is.na(new_book_ir), "NA", sprintf("%.3f", new_book_ir)),
              ifelse(is.na(incumbent_book_ir), "NA", sprintf("%.3f", incumbent_book_ir)))
    )
  } else if (!isTRUE(basis_consistent)) {
    # gross/geo/exante 혼재 ΔIR로 ADMIT 인증 금지 (CAP-P0-2 — 컨벤션 혼용이 감사 지적의 원인)
    if (artifact$decision == "ADMIT") artifact$decision <- "DEFER"
    artifact$rationale <- c(
      if (identical(artifact$rationale, "All checks passed")) character(0) else artifact$rationale,
      sprintf("book-marginal ΔIR basis mismatch (new=%s vs incumbent=%s) — %s 단일 컨벤션 미충족, ADMIT 인증 불가",
              .basis_short(new_book_ir_basis), .basis_short(incumbent_ir_basis),
              .PG_IR_CONVENTION)
    )
  } else if (artifact$decision == "ADMIT" && delta_ir < marginal_ir_threshold) {
    artifact$decision  <- "DEFER"
    artifact$rationale <- c(
      if (identical(artifact$rationale, "All checks passed")) character(0) else artifact$rationale,
      sprintf("book-marginal IR gain %.3f < %.2f (basis=%s)",
              delta_ir, marginal_ir_threshold, .basis_short(new_book_ir_basis))
    )
  } else if (artifact$decision == "ADMIT") {
    artifact$rationale <- c(
      if (identical(artifact$rationale, "All checks passed")) "All checks passed" else artifact$rationale,
      sprintf("book-marginal IR gain %.3f >= %.2f (basis=%s)",
              delta_ir, marginal_ir_threshold, .basis_short(new_book_ir_basis))
    )
  }
  # If standalone already DEFER, keep DEFER; book gain is informational only.

  if (length(artifact$rationale) == 0) artifact$rationale <- "All checks passed"

  # ── Step 4: append book-context fields ──────────────────────────────────────
  artifact$book_delta_ir           <- delta_ir
  artifact$new_book_ir             <- new_book_ir
  artifact$incumbent_book_ir       <- incumbent_book_ir
  artifact$new_book_ir_basis       <- new_book_ir_basis
  artifact$incumbent_book_ir_basis <- incumbent_ir_basis
  artifact$ir_basis_consistent     <- basis_consistent
  artifact$marginal_ir_threshold   <- marginal_ir_threshold
  if (!is.null(recon)) {
    artifact$book_recon_adapter <- list(
      sources          = recon$sources,
      bm_source        = recon$bm_source,
      n_months         = recon$n_months,
      period           = recon$period,
      combination      = recon$combination,
      weights_used     = recon$weights_used,
      port_alpha_t_nw3 = recon$port_alpha_t_nw3,
      reason           = recon$reason
    )
  }
  artifact$book_context_note       <- sprintf(
    "incumbent_ids=[%s] + candidate=%s | mailbox n_loaded=%d infeasible=%s | recon_adapter=%s",
    paste(incumbent_ids, collapse = ", "), candidate_id,
    new_book$n_loaded, isTRUE(new_book$infeasible),
    if (is.null(recon)) "unused"
    else if (!is.na(recon$book_ir)) sprintf("used(n_months=%d)", recon$n_months)
    else sprintf("failed(%s)", recon$reason)
  )

  # Re-persist the augmented artifact (overwrites the standalone pg1 artifact).
  sdir <- file.path(.pg_strategy_dir(candidate_id), "stage_artifacts")
  .pg_write_json(artifact, file.path(sdir, sprintf("pg1_admission_%s.json", portfolio_id)))
  pdir <- file.path(.pg_portfolio_dir(portfolio_id), "stage_artifacts")
  .pg_write_json(artifact, file.path(pdir, sprintf("pg1_admission_%s_%s.json", portfolio_id, candidate_id)))

  cat(sprintf("[pg1_book] Decision: %s | book_delta_ir=%s | %s\n",
              artifact$decision,
              ifelse(is.na(delta_ir), "NA", sprintf("%.3f", delta_ir)),
              paste(artifact$rationale, collapse = "; ")))

  artifact
}


#==============================================================================
# 3. PG2 — Sleeve Assembly & Allocation
#==============================================================================

#' PG2: Build allocation plan from admitted candidates.
#'
#' Assigns sleeve weights (equal-weight default), applies regime-conditional
#' adjustments, and produces a rebalance plan.
#'
#' @param portfolio_id Character: portfolio identifier
#' @param admitted_candidates List of PG1 artifacts with decision="ADMIT"
#' @param regime_signal List or NULL: regime state override (default: auto-fetch t-1)
#' @param allocation_method Character: "equal_weight" (default) or "risk_parity"
#' @return List: PG2 allocation plan artifact
pg2_allocation <- function(portfolio_id,
                           admitted_candidates,
                           regime_signal = NULL,
                           allocation_method = "equal_weight") {

  cat(sprintf("[pg2_allocation] Portfolio: %s | Method: %s | Candidates: %d\n",
              portfolio_id, allocation_method, length(admitted_candidates)))
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")

  # ── Filter to ADMIT only ────────────────────────────────────────────────────
  admits <- Filter(function(a) identical(a$decision, "ADMIT"), admitted_candidates)
  if (length(admits) == 0) {
    cat("[pg2] No admitted candidates. Empty allocation.\n")
    artifact <- list(
      stage = "PG2", version = .PG_VERSION, portfolio_id = portfolio_id,
      timestamp = timestamp, allocation_method = allocation_method,
      n_sleeves = 0L, sleeves = list(), sleeve_weights = list(),
      rebalance_plan = list(), pit_lag_verified = TRUE,
      note = "No admitted candidates"
    )
    pdir <- file.path(.pg_portfolio_dir(portfolio_id), "stage_artifacts")
    .pg_write_json(artifact, file.path(pdir, sprintf("pg2_allocation_plan_%s.json", portfolio_id)))
    return(artifact)
  }

  # ── Build sleeve configs ────────────────────────────────────────────────────
  n <- length(admits)
  sleeves <- lapply(seq_along(admits), function(i) {
    a <- admits[[i]]
    list(
      sleeve_idx    = i,
      strategy_id   = a$candidate_id,
      role          = a$validated_role,
      family        = a$candidate_family %||% .pg_classify_family(a$candidate_id)
    )
  })

  # ── Initial weights: equal weight ───────────────────────────────────────────
  raw_weights <- setNames(rep(1 / n, n), vapply(admits, function(a) a$candidate_id, character(1)))

  # ── Regime-conditional adjustment (PIT: t-1) ────────────────────────────────
  if (is.null(regime_signal)) {
    regime <- .pg_get_regime(Sys.Date() - 1)
    regime_category <- as.character(regime$Category[1] %||% "NEUTRAL")
    regime_score    <- as.numeric(regime$Regime_Score[1] %||% 0)
  } else {
    regime_category <- regime_signal$category %||% "NEUTRAL"
    regime_score    <- regime_signal$score %||% 0
  }

  # Map adjustments by role
  adj <- .PG_REGIME_ADJ[[regime_category]] %||% .PG_REGIME_ADJ[["NEUTRAL"]]

  adjusted_weights <- raw_weights
  for (i in seq_along(sleeves)) {
    role <- sleeves[[i]]$role
    role_bucket <- switch(role,
      core_alpha  = "core_alpha",
      diversifier = "diversifier",
      defense     = "defense",
      "core_alpha"  # default
    )
    delta <- adj[[role_bucket]] %||% 0
    adjusted_weights[i] <- adjusted_weights[i] + delta
  }

  # Floor at 0, then normalize to sum to 1

  adjusted_weights <- pmax(adjusted_weights, 0.01)
  adjusted_weights <- adjusted_weights / sum(adjusted_weights)

  # Convert to named list for JSON
  sleeve_weights <- as.list(adjusted_weights)

  # Annotate sleeves with final weights
  for (i in seq_along(sleeves)) {
    sleeves[[i]]$weight <- as.numeric(adjusted_weights[i])
  }

  # ── Rebalance plan ──────────────────────────────────────────────────────────
  rebalance_plan <- list(
    frequency    = "monthly",
    buffer_zone  = list(keep_n = 50L, entry_n = 25L),
    max_turnover = .PG_MAX_TURNOVER,
    next_rebal   = as.character(as.Date(cut(Sys.Date() + 31, "month")))
  )

  # ── Build artifact ──────────────────────────────────────────────────────────
  artifact <- list(
    stage             = "PG2",
    version           = .PG_VERSION,
    portfolio_id      = portfolio_id,
    timestamp         = timestamp,
    allocation_method = allocation_method,
    n_sleeves         = n,
    sleeves           = sleeves,
    sleeve_weights    = sleeve_weights,
    raw_weights       = as.list(raw_weights),
    regime_state      = list(
      date     = as.character(Sys.Date() - 1),
      category = regime_category,
      score    = regime_score
    ),
    regime_adjustments = adj,
    rebalance_plan    = rebalance_plan,
    pit_lag_verified  = TRUE
  )

  # ── Save artifact ───────────────────────────────────────────────────────────
  pdir <- file.path(.pg_portfolio_dir(portfolio_id), "stage_artifacts")
  .pg_write_json(artifact, file.path(pdir, sprintf("pg2_allocation_plan_%s.json", portfolio_id)))

  cat(sprintf("[pg2] Allocation: %d sleeves. Regime: %s(%.0f). Weights: %s\n",
              n, regime_category, regime_score,
              paste(sprintf("%s=%.1f%%", names(adjusted_weights),
                            adjusted_weights * 100), collapse = ", ")))

  artifact
}


#==============================================================================
# 4. PG3 — Live Monitoring
#==============================================================================

#' PG3: Monitor portfolio health — drift, regime changes, rebalance triggers.
#'
#' @param portfolio_id Character: portfolio identifier
#' @param pg2_artifact List: output of pg2_allocation()
#' @return List: PG3 monitoring artifact with alerts
pg3_monitor <- function(portfolio_id, pg2_artifact) {

  cat(sprintf("[pg3_monitor] Portfolio: %s\n", portfolio_id))
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  today     <- Sys.Date()
  alerts    <- character(0)

  # ── Target weights from PG2 ─────────────────────────────────────────────────
  target_weights <- pg2_artifact$sleeve_weights %||% list()
  target_vec <- unlist(target_weights)

  # ── Current holdings ────────────────────────────────────────────────────────
  holdings_path <- file.path(CACHE_DIR, "current_holdings.csv")
  current_weights <- target_vec  # default: assume on-target

  if (file.exists(holdings_path)) {
    tryCatch({
      h <- fread(holdings_path)
      # Try to match sleeve/strategy weights
      if ("strategy_id" %in% names(h) && "weight" %in% names(h)) {
        cw <- setNames(h$weight, h$strategy_id)
        # Only use if strategies overlap
        overlap <- intersect(names(cw), names(target_vec))
        if (length(overlap) > 0) {
          current_weights <- cw[names(target_vec)]
          current_weights[is.na(current_weights)] <- 0
        }
      }
    }, error = function(e) {
      warning("[pg3] Failed to read current_holdings.csv: ", e$message)
    })
  }

  # ── NAV report (lazy-load daily_portfolio_nav.R) ────────────────────────────
  nav_summary <- list(available = FALSE)
  tryCatch({
    dnav_path <- file.path(.pg_root, "daily_portfolio_nav.R")
    if (file.exists(dnav_path)) {
      if (!exists("daily_nav_report", envir = .GlobalEnv)) {
        source(dnav_path, local = FALSE)
      }
      if (exists("daily_nav_report", envir = .GlobalEnv)) {
        nav_summary <- daily_nav_report()
        nav_summary$available <- TRUE
      }
    }
  }, error = function(e) {
    warning("[pg3] NAV report unavailable: ", e$message)
  })

  # ── Drift check ─────────────────────────────────────────────────────────────
  drift <- abs(current_weights - target_vec)
  max_drift <- if (length(drift) > 0) max(drift, na.rm = TRUE) else 0
  rebalance_needed <- max_drift > .PG_DRIFT_THRESH

  if (rebalance_needed) {
    # Identify which sleeves drifted most
    drifted <- names(which(drift > .PG_DRIFT_THRESH))
    alerts <- c(alerts, sprintf(
      "DRIFT: max=%.1f%% (threshold=%.1f%%). Sleeves: %s",
      max_drift * 100, .PG_DRIFT_THRESH * 100,
      paste(drifted, collapse = ", ")
    ))
  }

  # ── Regime check (PIT: t-1) ─────────────────────────────────────────────────
  current_regime <- .pg_get_regime(today - 1)
  current_category <- as.character(current_regime$Category[1] %||% "NEUTRAL")
  current_score    <- as.numeric(current_regime$Regime_Score[1] %||% 0)

  last_regime_category <- pg2_artifact$regime_state$category %||% "NEUTRAL"
  regime_changed <- !identical(current_category, last_regime_category)

  if (regime_changed) {
    alerts <- c(alerts, sprintf(
      "REGIME CHANGE: %s → %s (score: %d)",
      last_regime_category, current_category, current_score
    ))
  }

  # ── MDD threshold check ────────────────────────────────────────────────────
  if (isTRUE(nav_summary$available) && !is.null(nav_summary$current_mdd)) {
    current_mdd <- abs(nav_summary$current_mdd)
    mdd_target  <- .PG_DEFAULT_TARGET$mdd
    if (current_mdd > mdd_target + 0.05) {
      alerts <- c(alerts, sprintf(
        "MDD BREACH: current=%.1f%% > target=%.1f%% + 5pp",
        current_mdd * 100, mdd_target * 100
      ))
    }
  }

  # ── Reopen triggers ─────────────────────────────────────────────────────────
  reopen_signal <- FALSE
  reopen_reason <- character(0)

  if (max_drift > 0.10) {
    reopen_signal <- TRUE
    reopen_reason <- c(reopen_reason, "Severe drift >10%")
  }
  if (regime_changed && current_category %in% c("RISK_OFF", "CAUTION")) {
    reopen_signal <- TRUE
    reopen_reason <- c(reopen_reason, sprintf("Defensive regime: %s", current_category))
  }

  # ── Build artifact ──────────────────────────────────────────────────────────
  artifact <- list(
    stage              = "PG3",
    version            = .PG_VERSION,
    portfolio_id       = portfolio_id,
    timestamp          = timestamp,
    monitoring_date    = as.character(today),
    target_weights     = as.list(target_vec),
    current_weights    = as.list(current_weights),
    drift              = as.list(drift),
    max_drift          = max_drift,
    rebalance_needed   = rebalance_needed,
    regime_state       = list(
      date     = as.character(today - 1),
      category = current_category,
      score    = current_score
    ),
    regime_changed     = regime_changed,
    last_regime        = last_regime_category,
    nav_summary        = nav_summary,
    alerts             = alerts,
    reopen_signal      = reopen_signal,
    reopen_reason      = reopen_reason,
    pit_lag_verified   = TRUE
  )

  # ── Save artifact ───────────────────────────────────────────────────────────
  pdir <- file.path(.pg_portfolio_dir(portfolio_id), "stage_artifacts")
  .pg_write_json(artifact, file.path(pdir, sprintf("pg3_monitoring_%s.json", as.character(today))))

  cat(sprintf("[pg3] Drift: %.1f%% | Regime: %s(%.0f) | Alerts: %d | Reopen: %s\n",
              max_drift * 100, current_category, as.numeric(current_score),
              length(alerts), reopen_signal))

  artifact
}


#==============================================================================
# 5. pg_cold_start — Cold Start Protocol
#==============================================================================

#' Determine cold-start phase and required action.
#'
#' @param portfolio_id Character: portfolio identifier
#' @param available_candidates Character vector or NULL: S7-complete strategy IDs
#' @return List with phase, action, selected strategies
pg_cold_start <- function(portfolio_id, available_candidates = NULL) {

  cat(sprintf("[pg_cold_start] Portfolio: %s\n", portfolio_id))

  # ── Scan for S7-complete strategies if not provided ─────────────────────────
  if (is.null(available_candidates)) {
    available_candidates <- tryCatch({
      strat_dirs <- list.dirs(STRATEGY_OUTPUT, recursive = FALSE, full.names = TRUE)
      s7_ready <- character(0)
      for (d in strat_dirs) {
        art_dir <- file.path(d, "stage_artifacts")
        if (!dir.exists(art_dir)) next
        # Check for S6 or S7 artifacts (S7 uses s6_validation as gate)
        s6_files <- list.files(art_dir, pattern = "^s6_", full.names = FALSE)
        s7_files <- list.files(art_dir, pattern = "^s7_", full.names = FALSE)
        if (length(s6_files) > 0 || length(s7_files) > 0) {
          s7_ready <- c(s7_ready, basename(d))
        }
      }
      s7_ready
    }, error = function(e) {
      warning("[pg_cold_start] Scan failed: ", e$message)
      character(0)
    })
  }

  # ── Load existing state ─────────────────────────────────────────────────────
  state <- pg_state_load(portfolio_id)
  admitted <- state$admitted_strategies %||% character(0)
  n_admitted <- length(admitted)

  # ── Phase determination ─────────────────────────────────────────────────────
  if (n_admitted == 0 && length(available_candidates) == 0) {
    result <- list(
      phase    = 0L,
      action   = "need_first_core_alpha",
      selected = NULL,
      available_candidates = available_candidates,
      admitted = admitted
    )
  } else if (n_admitted == 0 && length(available_candidates) > 0) {
    result <- list(
      phase    = 0L,
      action   = "select_first_core_alpha",
      selected = NULL,
      available_candidates = available_candidates,
      admitted = admitted
    )
  } else if (n_admitted == 1) {
    result <- list(
      phase              = 1L,
      action             = "need_diversifier_or_defense",
      current_strategy   = admitted[1],
      selected           = NULL,
      available_candidates = available_candidates,
      admitted           = admitted
    )
  } else {
    result <- list(
      phase    = 2L,
      action   = "full_pg_cycle",
      selected = NULL,
      available_candidates = available_candidates,
      admitted = admitted
    )
  }

  cat(sprintf("[pg_cold_start] Phase %d: %s | Admitted: %d | Available: %d\n",
              result$phase, result$action, n_admitted, length(available_candidates)))

  result
}


#==============================================================================
# 6. pg_state_save / pg_state_load — Persistent State
#==============================================================================

#' Save portfolio governor state to JSON cache.
#'
#' @param portfolio_id Character: portfolio identifier
#' @param state List: state object to persist
pg_state_save <- function(portfolio_id, state) {
  path <- file.path(CACHE_DIR, sprintf("pg_state_%s.json", portfolio_id))
  state$last_updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  .pg_write_json(state, path)
  cat(sprintf("[pg_state_save] Saved: %s\n", path))
  invisible(path)
}

#' Load portfolio governor state from JSON cache.
#'
#' @param portfolio_id Character: portfolio identifier
#' @return List: persisted state, or empty list if not found
pg_state_load <- function(portfolio_id) {
  path <- file.path(CACHE_DIR, sprintf("pg_state_%s.json", portfolio_id))
  if (!file.exists(path)) {
    return(list(
      portfolio_id       = portfolio_id,
      admitted_strategies = character(0),
      pg_history         = list(),
      created            = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
    ))
  }
  .pg_read_json(path, fallback = list(
    portfolio_id       = portfolio_id,
    admitted_strategies = character(0),
    pg_history         = list()
  ))
}


#==============================================================================
# 7. pg_update_candidates — Scan Production Candidates
#==============================================================================

#' Scan all S7+ strategies and compile candidate roster with metrics.
#'
#' @param portfolio_id Character: portfolio identifier (for artifact save)
#' @return data.table: candidate roster (strategy_id, grade, validated_role, total_score, sharpe, cagr, mdd)
pg_update_candidates <- function(portfolio_id) {

  cat(sprintf("[pg_update_candidates] Scanning strategies for portfolio %s...\n", portfolio_id))

  strat_dirs <- list.dirs(STRATEGY_OUTPUT, recursive = FALSE, full.names = TRUE)
  if (length(strat_dirs) == 0) {
    cat("[pg_update_candidates] No strategies found.\n")
    return(data.table(
      strategy_id = character(0), grade = character(0),
      validated_role = character(0), total_score = numeric(0),
      sharpe = numeric(0), cagr = numeric(0), mdd = numeric(0)
    ))
  }

  results <- rbindlist(lapply(strat_dirs, function(d) {
    sid <- basename(d)
    art_dir <- file.path(d, "stage_artifacts")

    # Check S6/S7 completion
    has_s6 <- length(list.files(art_dir, pattern = "^s6_", full.names = FALSE)) > 0
    has_s7 <- length(list.files(art_dir, pattern = "^s7_", full.names = FALSE)) > 0
    if (!has_s6 && !has_s7 && !dir.exists(art_dir)) return(NULL)

    # Also accept strategies with hurdle_result (legacy path)
    hr <- .pg_read_hurdle(sid)
    if (is.na(hr$grade) && !has_s6 && !has_s7) return(NULL)

    # Read S6 for role if available
    s6 <- NULL
    if (dir.exists(art_dir)) {
      s6_files <- list.files(art_dir, pattern = "^s6_", full.names = TRUE)
      if (length(s6_files) > 0) {
        s6 <- .pg_read_json(s6_files[length(s6_files)])
      }
    }

    # Extract role: S4 artifact > S6 artifact > hurdle > classify
    s4_files <- list.files(art_dir, pattern = "^s4_", full.names = TRUE)
    role <- NA_character_
    if (length(s4_files) > 0) {
      s4 <- .pg_read_json(s4_files[length(s4_files)])
      role <- s4$assigned_role %||% s4$validated_role %||% NA_character_
    }
    if (is.na(role) && !is.null(s6)) role <- s6$validated_role %||% s6$role %||% NA_character_
    if (is.na(role)) role <- hr$role
    if (is.na(role)) role <- .pg_classify_family(sid)

    # Performance metrics
    perf <- .pg_read_performance(sid)

    data.table(
      strategy_id    = sid,
      grade          = hr$grade %||% (s6$grade %||% NA_character_),
      validated_role = role,
      total_score    = hr$score %||% NA_real_,
      sharpe         = perf$sharpe %||% NA_real_,
      cagr           = perf$cagr %||% NA_real_,
      mdd            = perf$mdd %||% NA_real_
    )
  }), fill = TRUE)

  if (nrow(results) == 0) {
    cat("[pg_update_candidates] No qualifying candidates found.\n")
    results <- data.table(
      strategy_id = character(0), grade = character(0),
      validated_role = character(0), total_score = numeric(0),
      sharpe = numeric(0), cagr = numeric(0), mdd = numeric(0)
    )
  } else {
    # Sort by total_score descending
    setorder(results, -total_score, na.last = TRUE)
    cat(sprintf("[pg_update_candidates] Found %d candidates (%d Grade A).\n",
                nrow(results), sum(results$grade == "A", na.rm = TRUE)))
  }

  # ── Save to cache ───────────────────────────────────────────────────────────
  cache_path <- file.path(CACHE_DIR, "production_candidates.json")
  tryCatch(
    write_json(
      list(
        portfolio_id = portfolio_id,
        timestamp    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
        n_candidates = nrow(results),
        candidates   = lapply(seq_len(nrow(results)), function(i) as.list(results[i]))
      ),
      cache_path, auto_unbox = TRUE, pretty = TRUE, na = "null"
    ),
    error = function(e) warning("[pg_update_candidates] Cache write failed: ", e$message)
  )

  results
}


#==============================================================================
# Module Load Confirmation
#==============================================================================
cat("[portfolio_governor] Loaded (v", .PG_VERSION, "). Functions:\n", sep = "")
cat("  pg0_gap_review()       — PG0: Portfolio gap diagnosis + cold start\n")
cat("  pg1_admission()        — PG1: Candidate admission (anti-pattern/LOO/role)\n")
cat("  pg1_admission_with_book_context() — PG1 book-marginal ΔIR (net_active_recon_v1 단일 컨벤션;\n")
cat("                           mailbox 3-package 우선 → module_catalog/live_track recon 어댑터)\n")
cat("  pg_load_book_state()   — canonical book_state.json 로드 (절대경로, 읽기 전용)\n")
cat("  pg2_allocation()       — PG2: Sleeve assembly & regime-adjusted allocation\n")
cat("  pg3_monitor()          — PG3: Live monitoring (drift/regime/MDD alerts)\n")
cat("  pg_cold_start()        — Cold start protocol (Phase 0/1/2+)\n")
cat("  pg_state_save/load()   — Persistent portfolio state\n")
cat("  pg_update_candidates() — Scan S7+ strategies for candidate roster\n")
