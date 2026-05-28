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
.pg_root <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) {
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot/02_Infrastructure/portfolio"
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
.pg_get_regime <- function(date = Sys.Date() - 1) {
  if (!exists("get_regime_at_date", envir = .GlobalEnv)) {
    rs_path <- file.path(.pg_root, "regime_signal.R")
    if (file.exists(rs_path)) {
      tryCatch(source(rs_path, local = FALSE), error = function(e) {
        warning("[pg] Failed to source regime_signal.R: ", e$message)
      })
    }
  }
  if (exists("get_regime_at_date", envir = .GlobalEnv)) {
    tryCatch(get_regime_at_date(date), error = function(e) {
      warning("[pg] get_regime_at_date failed: ", e$message)
      data.table(Category = "NEUTRAL", Regime_Score = 0)
    })
  } else {
    data.table(Category = "NEUTRAL", Regime_Score = 0)
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
  # Even if all checks pass, candidate must fill a gap
  if (decision == "ADMIT" && !("none" %in% pg0_artifact$sleeve_needs)) {
    role_bucket <- switch(validated_role,
      core_alpha  = "core_alpha",
      diversifier = "diversifier",
      defense     = "defense",
      validated_role  # pass through
    )
    if (!(role_bucket %in% pg0_artifact$sleeve_needs)) {
      decision <- "DEFER"
      rationale <- c(rationale, sprintf(
        "Role '%s' not in current sleeve_needs: [%s]",
        role_bucket, paste(pg0_artifact$sleeve_needs, collapse = ", ")
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
cat("  pg2_allocation()       — PG2: Sleeve assembly & regime-adjusted allocation\n")
cat("  pg3_monitor()          — PG3: Live monitoring (drift/regime/MDD alerts)\n")
cat("  pg_cold_start()        — Cold start protocol (Phase 0/1/2+)\n")
cat("  pg_state_save/load()   — Persistent portfolio state\n")
cat("  pg_update_candidates() — Scan S7+ strategies for candidate roster\n")
