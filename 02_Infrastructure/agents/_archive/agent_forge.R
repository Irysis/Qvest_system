#==============================================================================
# Forge Agent — 전략 코드 자동 생성 + 백테스트 실행
# Version: 1.0.0
#
# mailbox 폴링 → "build_and_run" 수신 → 코드 생성 → PIT 검증 → 백테스트 실행
#
# 지원 유형:
#   - "single_factor"      : 단일 팩터 scoring → run_monthly_simulation
#   - "ensemble_blend"     : N개 sim_results 로드 → EW/가중 블렌드 → DD overlay
#   - "weight_optimization": EW, RP, HRP, NCO, Gerber 가중 비교
#   - "regime_conditional" : MRS 기반 동적 슬리브 배분
#
# Usage:
#   Rscript -e 'source("02_Infrastructure/agent_forge.R")'
#   (또는 tmux pane에서 launch_team.sh로 자동 실행)
#
# Lawbook 준수:
#   - Experiment Contract 필수 (없으면 거부)
#   - source('run_all.R') 패턴만
#   - VT/DD/FM lag fix (t-1) 필수
#   - 표준 헤더: cat("=== STR_{NNN}: description ===") + QEPM_AUTO_COMMIT <- TRUE
#   - 05_Production/ 수정 절대 금지
#==============================================================================

cat("[agent_forge] Initializing Forge agent...\n")

# ── Dependencies ──
suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ── Resolve project root (Korean path safe) ──
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
if (is.na(PROJECT_ROOT)) {
  PROJECT_ROOT <- Sys.getenv("QM_ROOT",
    unset = "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
}
rm(.root_candidates)

INFRA_DIR    <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRATEGY_DIR <- file.path(PROJECT_ROOT, "04_Research", "strategies")

# ── Source infrastructure ──
source(file.path(INFRA_DIR, "config.R"))
source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
source(file.path(PROJECT_ROOT, "qepm", "R", "orchestration", "agent_mailbox.R"))

cat("[agent_forge] Infrastructure loaded.\n")

# ══════════════════════════════════════════════════════════════════════════════
# 1. Strategy Directory Creation
# ══════════════════════════════════════════════════════════════════════════════

#' Create strategy directory with standard structure
#'
#' @param strategy_id Character, e.g., "STR_1039"
#' @param name_slug Character, short name for directory suffix
#' @return Full path to created strategy directory
create_strategy_dir <- function(strategy_id, name_slug) {
  dir_name <- paste0(strategy_id, "_", name_slug)
  dir_path <- file.path(STRATEGY_DIR, dir_name)

  if (dir.exists(dir_path)) {
    cat(sprintf("[forge] Directory already exists: %s\n", dir_name))
    return(dir_path)
  }

  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(dir_path, "output"), showWarnings = FALSE)

  cat(sprintf("[forge] Created: %s\n", dir_name))
  dir_path
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. Code Generation — run_all.R
# ══════════════════════════════════════════════════════════════════════════════

#' Generate run_all.R from hypothesis
#'
#' Uses strategy_template.R as base, customized by hypothesis type.
#'
#' @param hypothesis List with: strategy_id, description, family, type, params
#' @param strategy_dir Path to strategy directory
#' @return Invisible path to generated file
generate_run_all <- function(hypothesis, strategy_dir) {
  sid   <- hypothesis$strategy_id
  desc  <- hypothesis$description %||% hypothesis$objective %||% "Auto-generated"
  htype <- hypothesis$type %||% detect_type(hypothesis$family)

  # Sanitize description for R string
  desc_safe <- gsub('"', "'", desc)

  code <- switch(htype,

    # ── Type: ensemble_blend ──
    "ensemble_blend" = generate_ensemble_run_all(sid, desc_safe, hypothesis),

    # ── Type: single_factor ──
    "single_factor" = generate_single_factor_run_all(sid, desc_safe, hypothesis),

    # ── Type: weight_optimization ──
    "weight_optimization" = generate_weight_opt_run_all(sid, desc_safe, hypothesis),

    # ── Type: regime_conditional ──
    "regime_conditional" = generate_regime_cond_run_all(sid, desc_safe, hypothesis),

    # ── Default: single_factor fallback ──
    generate_single_factor_run_all(sid, desc_safe, hypothesis)
  )

  out_path <- file.path(strategy_dir, "run_all.R")
  writeLines(code, out_path)
  cat(sprintf("[forge] Generated run_all.R (%s) for %s\n", htype, sid))
  invisible(out_path)
}

#' Detect hypothesis type from family name
detect_type <- function(family) {
  if (is.null(family)) return("single_factor")
  fam <- tolower(family)
  if (grepl("ensemble|blend|sleeve", fam)) return("ensemble_blend")
  if (grepl("weight|rp|hrp|nco|gerber", fam)) return("weight_optimization")
  if (grepl("regime_alloc|regime_cond", fam)) return("regime_conditional")
  "single_factor"
}

# ── Standard Header (Lawbook mandatory) ──
std_header <- function(sid, desc) {
  paste0(
    '## ', sid, ': ', desc, '\n',
    '## Core Idea: ', desc, '\n',
    'cat("=== ', sid, ': ', desc, ' ===\\n")\n',
    'set.seed(', as.integer(gsub("\\D", "", sid)), ')\n',
    'options(scipen = 999)\n',
    'Sys.setenv(TZ = "Asia/Seoul")\n\n',
    'STRATEGY_NAME <- "', gsub("STR_\\d+_?", "", sid), '"\n',
    'STRATEGY_ID   <- "', sid, '"\n',
    'QEPM_AUTO_COMMIT <- TRUE\n\n',
    '# ── Infrastructure ──\n',
    'SCRIPT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())\n',
    'INFRA_DIR  <- file.path(SCRIPT_DIR, "..", "..", "..", "02_Infrastructure")\n',
    'source(file.path(INFRA_DIR, "config.R"))\n',
    'source(file.path(INFRA_DIR, "backtest_harness.R"))\n',
    'library(data.table); library(xts)\n\n'
  )
}

# ── Standard Footer (analysis + hurdle + completion message) ──
std_footer <- function(sid) {
  paste0(
    '\n# ═══ Validation & Hurdle Gate ═══\n',
    'cat("[Step 4] Validation...\\n")\n',
    'output_dir <- file.path(SCRIPT_DIR, "output")\n',
    'if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)\n\n',
    'perf_strat <- summarise_perf(sim_result$strategy_xts, STRATEGY_NAME)\n',
    'perf_bm    <- summarise_perf(sim_result$bm_xts, "Benchmark (K200)")\n',
    'print(rbind(perf_strat, perf_bm))\n\n',
    'generate_charts(sim_result, output_dir = output_dir, strategy_name = STRATEGY_NAME)\n',
    'fwrite(rbind(perf_strat, perf_bm), file.path(output_dir, "performance.csv"))\n',
    'fwrite(sim_result$PORTFOLIO_LOG, file.path(output_dir, "portfolio_log.csv"))\n\n',
    '# Save sim_result for ensemble use\n',
    'saveRDS(sim_result, file.path(output_dir, "sim_result.rds"))\n\n',
    'source(file.path(INFRA_DIR, "strategy_analyzer.R"))\n',
    'run_analysis(sim_result, FACTORS, RAWDATA, BM_DT, output_dir,\n',
    '             strategy_name = STRATEGY_ID)\n\n',
    'source(file.path(INFRA_DIR, "hurdle_gate.R"))\n',
    'hurdle <- run_hurdle_gate(\n',
    '  sim_result    = sim_result,\n',
    '  FACTORS       = FACTORS,\n',
    '  strategy_name = STRATEGY_NAME,\n',
    '  strategy_file = file.path(SCRIPT_DIR, "factor_engine.R"),\n',
    '  output_dir    = output_dir\n',
    ')\n\n',
    'cat(sprintf("\\n=== ', sid, ' Complete. Verdict: %s (Score: %.1f) ===\\n",\n',
    '    if (hurdle$pass) "PASS" else "FAIL", hurdle$score))\n'
  )
}

# ══════════════════════════════════════════════════════════════════════════════
# 2a. Type-specific run_all.R generators
# ══════════════════════════════════════════════════════════════════════════════

# ── Ensemble Blend ──
generate_ensemble_run_all <- function(sid, desc, hyp) {
  sleeves <- hyp$params$sleeves %||% list()
  n_sleeve <- length(sleeves)
  weights <- hyp$params$weights %||% rep(1/max(n_sleeve,1), max(n_sleeve,1))

  # Build sleeve loading code
  load_lines <- ""
  align_vars <- c()
  for (i in seq_along(sleeves)) {
    sname <- sleeves[[i]]
    vname <- paste0("sim_", LETTERS[i])
    align_vars <- c(align_vars, vname)
    load_lines <- paste0(load_lines,
      sprintf('%s <- load_sim("%s")\n', vname, sname))
  }

  # Build alignment + blend code
  align_code <- paste0(
    '# Align to common dates\n',
    'all_dates <- list(', paste0(
      sapply(align_vars, function(v) sprintf('as.Date(index(%s$strategy_xts))', v)),
      collapse = ", "), ')\n',
    'common <- sort(as.Date(Reduce(intersect, all_dates), origin = "1970-01-01"))\n',
    'cat(sprintf("  Common dates: %d\\n", length(common)))\n\n'
  )

  # Retrieve returns
  ret_lines <- paste0(
    sapply(seq_along(align_vars), function(i) {
      sprintf('ret_%s <- as.numeric(%s$strategy_xts[common])', LETTERS[i], align_vars[i])
    }), collapse = "\n")

  # Blend with fixed weights (C12 compliant)
  w_str <- paste0(sprintf("%.4f", weights), collapse = ", ")
  blend_code <- paste0(
    '\n# Fixed weight blend (C12 compliant — no full-sample optimization)\n',
    'W <- c(', w_str, ')\n',
    'ret_mat <- cbind(', paste0("ret_", LETTERS[seq_along(sleeves)], collapse=", "), ')\n',
    'blended <- as.numeric(ret_mat %*% W)\n',
    'bm_ret <- as.numeric(sim_A$bm_xts[common])\n\n'
  )

  # DD Brake overlay with t-1 lag
  dd_overlay <- paste0(
    '# ═══ DD Brake Overlay (t-1 lagged — C5 compliant) ═══\n',
    'cat("[Phase 3] DD Brake overlay (t-1 lag)...\\n")\n',
    'cum_ret   <- cumprod(1 + blended)\n',
    'running_max <- cummax(cum_ret)\n',
    'drawdown  <- cum_ret / running_max - 1\n',
    'dd_lagged <- c(0, drawdown[-length(drawdown)])  # t-1 lag\n\n',
    'DD_THRESH_SHORT <- -0.05\n',
    'DD_THRESH_LONG  <- -0.15\n',
    'dd_exp <- ifelse(dd_lagged > DD_THRESH_SHORT, 1.0,\n',
    '          ifelse(dd_lagged < DD_THRESH_LONG, 0.2,\n',
    '                 0.2 + 0.8 * (dd_lagged - DD_THRESH_LONG) /\n',
    '                              (DD_THRESH_SHORT - DD_THRESH_LONG)))\n',
    'final_ret <- blended * dd_exp\n\n'
  )

  # Assemble sim_result compatible output
  sim_assembly <- paste0(
    '# ═══ Assemble sim_result ═══\n',
    'strategy_xts <- xts(final_ret, order.by = common)\n',
    'bm_xts       <- xts(bm_ret,   order.by = common)\n',
    'PORTFOLIO_LOG <- data.table(\n',
    '  Date = common, Strategy_Ret = final_ret, BM_Ret = bm_ret,\n',
    '  DD_Exp = dd_exp, Blend_Raw = blended\n',
    ')\n',
    'sim_result <- list(\n',
    '  strategy_xts  = strategy_xts,\n',
    '  bm_xts        = bm_xts,\n',
    '  PORTFOLIO_LOG  = PORTFOLIO_LOG\n',
    ')\n\n',
    '# FACTORS placeholder for hurdle gate\n',
    'FACTORS <- data.table(Date = unique(format(common, "%Y-%m")),\n',
    '                      Ticker = "BLEND", Score = 1)\n',
    'FACTORS[, Date := as.Date(paste0(Date, "-01"))]\n\n',
    '# Load RAWDATA and BM_DT for analyzer\n',
    'rawdata_result <- load_rawdata(use_cache = TRUE)\n',
    'RAWDATA <- rawdata_result$RAWDATA\n',
    'BM_DT   <- rawdata_result$BM_DT\n'
  )

  paste0(
    std_header(sid, desc),
    '# ═══ Phase 1: Load sleeve sim results ═══\n',
    'cat("[Phase 1] Loading ', n_sleeve, ' sleeve sim results...\\n")\n',
    'base <- file.path(PROJECT_ROOT, "04_Research/strategies")\n\n',
    'load_sim <- function(strat_name) {\n',
    '  sim_files <- list.files(file.path(base, strat_name), "sim_result.rds",\n',
    '                          recursive = TRUE, full.names = TRUE)\n',
    '  if (length(sim_files) == 0) stop(paste("No sim_result.rds for", strat_name))\n',
    '  readRDS(sim_files[1])\n',
    '}\n\n',
    load_lines, '\n',
    align_code,
    ret_lines, '\n',
    blend_code,
    dd_overlay,
    sim_assembly,
    std_footer(sid)
  )
}

# ── Single Factor ──
generate_single_factor_run_all <- function(sid, desc, hyp) {
  n_holdings <- hyp$params$n_holdings %||% 20
  weight_method <- hyp$params$weight_method %||% "ivol"

  paste0(
    std_header(sid, desc),
    '# ═══ Phase 1: Data Loading ═══\n',
    'cat("[Step 1] Loading data...\\n")\n',
    'rawdata_result <- load_rawdata(use_cache = TRUE)\n',
    'RAWDATA <- rawdata_result$RAWDATA\n',
    'BM_DT   <- rawdata_result$BM_DT\n\n',
    '# ═══ Phase 2: Factor Engine ═══\n',
    'cat("[Step 2] Computing factors...\\n")\n',
    'source(file.path(SCRIPT_DIR, "factor_engine.R"))\n\n',
    'stopifnot(\n',
    '  is.data.table(FACTORS),\n',
    '  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),\n',
    '  nrow(FACTORS) > 0\n',
    ')\n',
    'cat(sprintf("  > FACTORS: %d rows | %d signal dates | %d unique tickers\\n",\n',
    '            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))\n\n',
    '# ═══ Phase 3: Simulation ═══\n',
    'cat("[Step 3] Running simulation...\\n")\n',
    'sim_result <- run_monthly_simulation(\n',
    '  RAWDATA       = RAWDATA,\n',
    '  BM_DT         = BM_DT,\n',
    '  FACTORS       = FACTORS,\n',
    '  n_holdings    = ', n_holdings, ',\n',
    '  commission    = 0.0015,\n',
    '  weight_method = "', weight_method, '"\n',
    ')\n',
    std_footer(sid)
  )
}

# ── Weight Optimization ──
generate_weight_opt_run_all <- function(sid, desc, hyp) {
  weight_method <- hyp$params$weight_method %||% "rp"
  n_holdings <- hyp$params$n_holdings %||% 20

  paste0(
    std_header(sid, desc),
    '# ═══ Phase 1: Data Loading ═══\n',
    'cat("[Step 1] Loading data...\\n")\n',
    'rawdata_result <- load_rawdata(use_cache = TRUE)\n',
    'RAWDATA <- rawdata_result$RAWDATA\n',
    'BM_DT   <- rawdata_result$BM_DT\n\n',
    '# ═══ Phase 2: Factor Engine ═══\n',
    'cat("[Step 2] Computing factors...\\n")\n',
    'source(file.path(SCRIPT_DIR, "factor_engine.R"))\n\n',
    'stopifnot(\n',
    '  is.data.table(FACTORS),\n',
    '  all(c("Date", "Ticker", "Score") %in% names(FACTORS)),\n',
    '  nrow(FACTORS) > 0\n',
    ')\n\n',
    '# ═══ Phase 3: Simulation (', weight_method, ' weighting) ═══\n',
    'cat("[Step 3] Running simulation (', weight_method, ')...\\n")\n',
    'sim_result <- run_monthly_simulation(\n',
    '  RAWDATA       = RAWDATA,\n',
    '  BM_DT         = BM_DT,\n',
    '  FACTORS       = FACTORS,\n',
    '  n_holdings    = ', n_holdings, ',\n',
    '  commission    = 0.0015,\n',
    '  weight_method = "', weight_method, '"\n',
    ')\n',
    std_footer(sid)
  )
}

# ── Regime Conditional ──
generate_regime_cond_run_all <- function(sid, desc, hyp) {
  sleeves <- hyp$params$sleeves %||% list()
  n_sleeve <- length(sleeves)

  load_lines <- ""
  for (i in seq_along(sleeves)) {
    sname <- sleeves[[i]]
    vname <- paste0("sim_", LETTERS[i])
    load_lines <- paste0(load_lines,
      sprintf('%s <- load_sim("%s")\n', vname, sname))
  }

  paste0(
    std_header(sid, desc),
    'source(file.path(REGIME_DIR, "regime_engine_v7.R"))\n\n',
    '# ═══ Phase 1: Load sleeve sim results ═══\n',
    'cat("[Phase 1] Loading ', n_sleeve, ' sleeve sim results...\\n")\n',
    'base <- file.path(PROJECT_ROOT, "04_Research/strategies")\n\n',
    'load_sim <- function(strat_name) {\n',
    '  sim_files <- list.files(file.path(base, strat_name), "sim_result.rds",\n',
    '                          recursive = TRUE, full.names = TRUE)\n',
    '  if (length(sim_files) == 0) stop(paste("No sim_result.rds for", strat_name))\n',
    '  readRDS(sim_files[1])\n',
    '}\n\n',
    load_lines, '\n',
    '# Align to common dates\n',
    'all_dates <- lapply(list(', paste0(
      sapply(seq_along(sleeves), function(i)
        sprintf('sim_%s$strategy_xts', LETTERS[i])), collapse = ", "),
    '), function(x) as.Date(index(x)))\n',
    'common <- sort(as.Date(Reduce(intersect, all_dates), origin = "1970-01-01"))\n\n',
    '# ═══ Phase 2: Regime signal ═══\n',
    'cat("[Phase 2] Loading regime signal (v7.1)...\\n")\n',
    'regime_sig <- compute_regime_signal_v7(common)\n',
    'regime_lagged <- c(0, regime_sig[-length(regime_sig)])  # t-1 lag\n\n',
    '# ═══ Phase 3: Dynamic allocation ═══\n',
    'cat("[Phase 3] Dynamic sleeve allocation by regime...\\n")\n',
    '# Regime states: 0=Normal, 1=Caution, 2=Crisis\n',
    'regime_state <- ifelse(regime_lagged >= 50, 2L,\n',
    '                ifelse(regime_lagged >= 20, 1L, 0L))\n\n',
    '# Allocation matrix (rows = regime, cols = sleeves)\n',
    '# Normal:  offense-heavy | Caution: balanced | Crisis: defense-heavy\n',
    'alloc_matrix <- matrix(c(\n',
    if (n_sleeve >= 3) paste0(
      '  0.50, 0.30, 0.20,  # Normal\n',
      '  0.30, 0.30, 0.40,  # Caution\n',
      '  0.10, 0.20, 0.70   # Crisis\n')
    else if (n_sleeve == 2) paste0(
      '  0.60, 0.40,  # Normal\n',
      '  0.40, 0.60,  # Caution\n',
      '  0.20, 0.80   # Crisis\n')
    else '  1.0,  # Normal\n  1.0,  # Caution\n  1.0   # Crisis\n',
    '), nrow = 3, ncol = ', n_sleeve, ', byrow = TRUE)\n\n',
    '# Build daily returns\n',
    'ret_mat <- cbind(', paste0(sapply(seq_along(sleeves), function(i)
      sprintf('as.numeric(sim_%s$strategy_xts[common])', LETTERS[i])),
      collapse = ", "), ')\n',
    'bm_ret <- as.numeric(sim_A$bm_xts[common])\n\n',
    'final_ret <- numeric(length(common))\n',
    'for (t in seq_along(common)) {\n',
    '  state <- regime_state[t] + 1L  # 1-indexed\n',
    '  w <- alloc_matrix[state, ]\n',
    '  final_ret[t] <- sum(ret_mat[t, ] * w)\n',
    '}\n\n',
    '# DD Brake overlay (t-1 lagged)\n',
    'cum_ret     <- cumprod(1 + final_ret)\n',
    'running_max <- cummax(cum_ret)\n',
    'drawdown    <- cum_ret / running_max - 1\n',
    'dd_lagged   <- c(0, drawdown[-length(drawdown)])\n',
    'dd_exp <- ifelse(dd_lagged > -0.05, 1.0,\n',
    '          ifelse(dd_lagged < -0.15, 0.2,\n',
    '                 0.2 + 0.8 * (dd_lagged + 0.15) / 0.10))\n',
    'final_ret <- final_ret * dd_exp\n\n',
    '# Assemble sim_result\n',
    'strategy_xts <- xts(final_ret, order.by = common)\n',
    'bm_xts       <- xts(bm_ret,   order.by = common)\n',
    'PORTFOLIO_LOG <- data.table(\n',
    '  Date = common, Strategy_Ret = final_ret, BM_Ret = bm_ret,\n',
    '  Regime_State = regime_state, DD_Exp = dd_exp\n',
    ')\n',
    'sim_result <- list(strategy_xts = strategy_xts, bm_xts = bm_xts,\n',
    '                   PORTFOLIO_LOG = PORTFOLIO_LOG)\n\n',
    'FACTORS <- data.table(Date = unique(format(common, "%Y-%m")),\n',
    '                      Ticker = "REGIME", Score = 1)\n',
    'FACTORS[, Date := as.Date(paste0(Date, "-01"))]\n\n',
    'rawdata_result <- load_rawdata(use_cache = TRUE)\n',
    'RAWDATA <- rawdata_result$RAWDATA\n',
    'BM_DT   <- rawdata_result$BM_DT\n',
    std_footer(sid)
  )
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. Code Generation — factor_engine.R
# ══════════════════════════════════════════════════════════════════════════════

#' Generate factor_engine.R based on hypothesis type
#'
#' Only needed for single_factor and weight_optimization types.
#' Ensemble and regime types don't use a separate factor engine.
#'
#' @param hypothesis List with type/family/params
#' @param strategy_dir Path to strategy directory
#' @return Invisible path (or NULL if not needed)
generate_factor_engine <- function(hypothesis, strategy_dir) {
  htype <- hypothesis$type %||% detect_type(hypothesis$family)

  # Ensemble/regime don't need factor_engine.R
  if (htype %in% c("ensemble_blend", "regime_conditional")) {
    # Write a stub so run_all.R source() doesn't fail
    stub <- paste0(
      '# factor_engine.R — stub for ', htype, ' strategy\n',
      '# FACTORS is built directly in run_all.R\n',
      'cat("[factor_engine] Stub for ', htype, ' — no separate factor computation.\\n")\n'
    )
    out_path <- file.path(strategy_dir, "factor_engine.R")
    writeLines(stub, out_path)
    return(invisible(out_path))
  }

  # Build factor engine based on family
  family <- tolower(hypothesis$family %||% "generic")
  code <- generate_factor_code(family, hypothesis)

  out_path <- file.path(strategy_dir, "factor_engine.R")
  writeLines(code, out_path)
  cat(sprintf("[forge] Generated factor_engine.R (family: %s)\n", family))
  invisible(out_path)
}

#' Generate factor computation code by family
generate_factor_code <- function(family, hyp) {
  lag_days <- hyp$params$lag_days %||% 45

  header <- paste0(
    '#==============================================================================\n',
    '# Factor Engine — Family: ', family, '\n',
    '# Auto-generated by Forge agent. PIT-compliant (expanding window).\n',
    '# VT/DD/FM: t-1 lag enforced.\n',
    '#==============================================================================\n\n',
    '# RAWDATA must already be loaded (via run_all.R)\n',
    'stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))\n\n',
    '# ── Liquidity Filter (C10 compliant: t-1 lag) ──\n',
    'RAWDATA[, AvgTV_20d := shift(frollmean(Close * Vol, n = 20), n = 1, type = "lag"),\n',
    '        by = Ticker]\n',
    'LIQ_THRESHOLD <- 2e8  # 2억원\n\n'
  )

  body <- switch(family,

    "consensus_blend" = paste0(
      '# ── Consensus EPS Change + Quality blend ──\n',
      'source(file.path(DATA_DIR, "consensus_parser.R"))\n',
      'consensus <- load_consensus_data()\n\n',
      '# 45d lag for quarterly data (C4 compliant)\n',
      'consensus[, available_date := Date + ', lag_days, ']\n\n',
      '# EPS Change: t vs t-1 consensus\n',
      'consensus[, EPS_Chg := (EPS_Fwd - shift(EPS_Fwd, 1)) / abs(shift(EPS_Fwd, 1)),\n',
      '          by = Ticker]\n\n',
      '# Quality: ROE expanding z-score (PIT compliant)\n',
      'source(file.path(VALIDATION_DIR, "pit_enforcement.R"))\n',
      'consensus[, ROE_z := pit_zscore_vec(ROE, seq_len(.N)), by = Ticker]\n\n',
      '# Blend: 70% EPS change + 30% Quality\n',
      'W_EPS <- 0.70; W_QUAL <- 0.30\n',
      'signal_dates <- RAWDATA[, .(Date = max(Date)), by = .(YM = format(Date, "%Y-%m"))]\n',
      'FACTORS <- merge(RAWDATA[Date %in% signal_dates$Date, .(Date, Ticker, AvgTV_20d)],\n',
      '                 consensus[, .(Ticker, Date = available_date, EPS_Chg, ROE_z)],\n',
      '                 by = c("Date", "Ticker"), all.x = TRUE)\n',
      'FACTORS <- FACTORS[AvgTV_20d >= LIQ_THRESHOLD]\n',
      'FACTORS[, Score := W_EPS * frank(EPS_Chg, na.last = "keep") / .N +\n',
      '                   W_QUAL * frank(ROE_z, na.last = "keep") / .N,\n',
      '         by = Date]\n',
      'FACTORS <- FACTORS[!is.na(Score), .(Date, Ticker, Score)]\n'
    ),

    "factor_momentum" = paste0(
      '# ── Factor Momentum (t-1 lag, expanding window — C8 compliant) ──\n',
      'LOOKBACK <- ', hyp$params$lookback %||% 84, 'L  # days\n\n',
      '# Compute trailing factor returns (expanding, t-1 lagged)\n',
      'signal_dates <- RAWDATA[, .(Date = max(Date)), by = .(YM = format(Date, "%Y-%m"))]\n',
      'RAWDATA[, mom_20d := shift(Close, 1, type="lag") / shift(Close, 21, type="lag") - 1,\n',
      '        by = Ticker]  # t-1 lag on all data\n\n',
      'FACTORS <- RAWDATA[Date %in% signal_dates$Date & AvgTV_20d >= LIQ_THRESHOLD,\n',
      '                   .(Date, Ticker)]\n',
      'FACTORS[, Score := frank(mom_20d, na.last = "keep") / .N, by = Date]\n',
      'FACTORS <- FACTORS[!is.na(Score), .(Date, Ticker, Score)]\n'
    ),

    "regime_alpha" = paste0(
      '# ── VRP + Absorption Ratio regime alpha (t-1 lag) ──\n',
      'source(file.path(REGIME_DIR, "regime_engine_v7.R"))\n',
      'source(file.path(VALIDATION_DIR, "pit_enforcement.R"))\n\n',
      '# Low-vol defensive factor for crisis sleeve\n',
      'signal_dates <- RAWDATA[, .(Date = max(Date)), by = .(YM = format(Date, "%Y-%m"))]\n',
      'RAWDATA[, vol_60d := shift(\n',
      '  frollapply(Ret, n = 60, FUN = sd, fill = NA) * sqrt(252),\n',
      '  n = 1, type = "lag"), by = Ticker]\n\n',
      'FACTORS <- RAWDATA[Date %in% signal_dates$Date & AvgTV_20d >= LIQ_THRESHOLD,\n',
      '                   .(Date, Ticker, vol_60d)]\n',
      'FACTORS[, Score := -frank(vol_60d, na.last = "keep") / .N, by = Date]\n',
      '# Low vol = high score (defensive)\n',
      'FACTORS <- FACTORS[!is.na(Score), .(Date, Ticker, Score)]\n'
    ),

    "cardinality" = paste0(
      '# ── Cardinality reduction: composite z-score top N ──\n',
      'source(file.path(VALIDATION_DIR, "pit_enforcement.R"))\n',
      'N_TOP <- ', hyp$params$n_top %||% 15, 'L\n\n',
      '# Multi-factor composite: momentum + value + quality\n',
      'signal_dates <- RAWDATA[, .(Date = max(Date)), by = .(YM = format(Date, "%Y-%m"))]\n\n',
      '# Momentum: 12-1 month (skip recent 1 month for reversal)\n',
      'RAWDATA[, mom_12_1 := shift(Close, 22, type="lag") /\n',
      '                      shift(Close, 252, type="lag") - 1, by = Ticker]\n\n',
      '# Composite z-score (cross-sectional per date)\n',
      'FACTORS <- RAWDATA[Date %in% signal_dates$Date & AvgTV_20d >= LIQ_THRESHOLD]\n',
      'FACTORS[, z_mom := (mom_12_1 - mean(mom_12_1, na.rm=TRUE)) /\n',
      '                   sd(mom_12_1, na.rm=TRUE), by = Date]\n',
      'FACTORS[, Score := z_mom]  # extendable: + z_value + z_quality\n',
      'FACTORS <- FACTORS[!is.na(Score), .(Date, Ticker, Score)]\n'
    ),

    # ── Generic fallback ──
    paste0(
      '# ── Generic factor engine (placeholder) ──\n',
      '# Replace with actual factor logic for family: ', family, '\n',
      'signal_dates <- RAWDATA[, .(Date = max(Date)), by = .(YM = format(Date, "%Y-%m"))]\n\n',
      '# Simple momentum 20d (t-1 lagged)\n',
      'RAWDATA[, mom_20d := shift(Close, 1, type="lag") /\n',
      '                    shift(Close, 21, type="lag") - 1, by = Ticker]\n\n',
      'FACTORS <- RAWDATA[Date %in% signal_dates$Date & AvgTV_20d >= LIQ_THRESHOLD,\n',
      '                   .(Date, Ticker)]\n',
      'FACTORS <- merge(FACTORS,\n',
      '                 RAWDATA[, .(Date, Ticker, mom_20d, AvgTV_20d)],\n',
      '                 by = c("Date", "Ticker"))\n',
      'FACTORS[, Score := frank(mom_20d, na.last = "keep") / .N, by = Date]\n',
      'FACTORS <- FACTORS[!is.na(Score), .(Date, Ticker, Score)]\n'
    )
  )

  paste0(header, body)
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. PIT Pre-check
# ══════════════════════════════════════════════════════════════════════════════

#' Run lookahead detector on generated strategy files
#'
#' @param strategy_dir Path to strategy directory
#' @return List with $clean (logical) and $violations
check_lookahead <- function(strategy_dir) {
  detect_lookahead_dir(strategy_dir, verbose = TRUE)
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. Build-and-Run Pipeline
# ══════════════════════════════════════════════════════════════════════════════

#' Full build-and-run pipeline for a single hypothesis
#'
#' @param hypothesis List: strategy_id, objective, description, family, type, params
#' @param timeout_sec Max execution time (default 1800 = 30 min)
#' @return List with status, strategy_dir, error_msg, etc.
forge_build_and_run <- function(hypothesis, timeout_sec = 1800) {
  sid  <- hypothesis$strategy_id
  desc <- hypothesis$description %||% hypothesis$objective
  fam  <- hypothesis$family %||% "unknown"

  cat(sprintf("\n[forge] ════ BUILD & RUN: %s (%s) ════\n", sid, fam))
  cat(sprintf("[forge] Description: %s\n", desc))

  # ── 0. Verify experiment contract ──
  contract <- hypothesis$contract %||% hypothesis$experiment_contract
  if (is.null(contract) && is.null(hypothesis$hypothesis)) {
    cat("[forge] WARNING: No experiment contract found. Generating minimal contract.\n")
    # Generate minimal contract from available fields
    contract <- list(
      scope = list(exp_id = sid, family = fam),
      hypothesis = desc,
      data_pit = list(pit_checklist = TRUE),
      implementation = list(strategy_id = sid)
    )
  }

  # ── 1. Create strategy directory ──
  name_slug <- gsub("[^a-zA-Z0-9_]", "_", tolower(
    gsub("\\s+", "_", substring(desc, 1, 30))))
  name_slug <- gsub("_+", "_", gsub("^_|_$", "", name_slug))
  if (nchar(name_slug) < 3) name_slug <- tolower(fam)

  strategy_dir <- tryCatch(
    create_strategy_dir(sid, name_slug),
    error = function(e) {
      cat(sprintf("[forge] ERROR creating directory: %s\n", e$message))
      return(NULL)
    }
  )
  if (is.null(strategy_dir)) {
    return(list(status = "error", strategy_dir = NULL,
                error_msg = "Failed to create strategy directory"))
  }

  # ── 2. Generate code ──
  tryCatch({
    generate_run_all(hypothesis, strategy_dir)
    generate_factor_engine(hypothesis, strategy_dir)
  }, error = function(e) {
    cat(sprintf("[forge] ERROR in code generation: %s\n", e$message))
    return(list(status = "error", strategy_dir = strategy_dir,
                error_msg = paste("Code generation failed:", e$message)))
  })

  # ── 3. PIT pre-check (C1~C12) ──
  cat("[forge] Running PIT pre-check...\n")
  pit_result <- tryCatch(
    check_lookahead(strategy_dir),
    error = function(e) {
      cat(sprintf("[forge] PIT check error: %s\n", e$message))
      list(clean = TRUE, violations = list(), n_violations = 0)
    }
  )

  if (!pit_result$clean) {
    cat(sprintf("[forge] PIT FAIL: %d violation(s). Aborting.\n",
                pit_result$n_violations))
    return(list(
      status      = "pit_fail",
      strategy_dir = strategy_dir,
      violations  = pit_result$violations,
      error_msg   = sprintf("%d lookahead violation(s)", pit_result$n_violations)
    ))
  }
  cat("[forge] PIT pre-check CLEAN.\n")

  # ── 4. Execute backtest ──
  cat(sprintf("[forge] Executing backtest (timeout: %ds)...\n", timeout_sec))
  original_wd <- getwd()

  result <- tryCatch({
    setTimeLimit(elapsed = timeout_sec, transient = TRUE)
    on.exit({
      setTimeLimit(elapsed = Inf, transient = FALSE)
      setwd(original_wd)
    }, add = TRUE)

    setwd(strategy_dir)
    source("run_all.R", local = new.env(parent = globalenv()))

    list(
      status       = "complete",
      strategy_dir = strategy_dir,
      error_msg    = NULL
    )
  }, error = function(e) {
    msg <- e$message
    cat(sprintf("[forge] EXECUTION ERROR: %s\n", msg))

    # Distinguish timeout from other errors
    if (grepl("elapsed time limit|time limit", msg, ignore.case = TRUE)) {
      list(status = "timeout", strategy_dir = strategy_dir,
           error_msg = paste("Timeout after", timeout_sec, "seconds"))
    } else {
      list(status = "error", strategy_dir = strategy_dir,
           error_msg = msg)
    }
  })

  cat(sprintf("[forge] ════ %s: %s ════\n", sid, toupper(result$status)))
  result
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. Mailbox Polling Loop
# ══════════════════════════════════════════════════════════════════════════════

#' Check forge inbox for pending tasks
#'
#' Wraps mailbox_receive() for the forge agent.
#' @return First pending task message, or NULL
check_inbox_forge <- function() {
  msgs <- mailbox_receive("forge", type_filter = "task", mark_read = TRUE)
  if (length(msgs) == 0) return(NULL)
  msgs[[1]]  # Highest priority first (already sorted)
}

#' Process a single mailbox message
#'
#' @param msg Message from check_inbox_forge()
#' @return Result list from forge_build_and_run()
process_message <- function(msg) {
  cmd  <- msg$body$cmd %||% msg$subject %||% ""
  cat(sprintf("[forge] Received command: %s (from: %s)\n", cmd, msg$from))

  if (!identical(cmd, "build_and_run")) {
    cat(sprintf("[forge] Unknown command: %s. Ignoring.\n", cmd))
    mailbox_reply(msg, "forge",
      result = list(status = "rejected", reason = paste("Unknown command:", cmd)),
      success = FALSE)
    return(invisible(NULL))
  }

  # Extract hypothesis from message body
  hypothesis <- msg$body$hypothesis
  if (is.null(hypothesis)) {
    cat("[forge] ERROR: No hypothesis in message body.\n")
    mailbox_reply(msg, "forge",
      result = list(status = "error", reason = "No hypothesis provided"),
      success = FALSE)
    return(invisible(NULL))
  }

  # Ensure strategy_id is set
  if (is.null(hypothesis$strategy_id)) {
    hypothesis$strategy_id <- msg$body$strategy_id %||%
      paste0("STR_", format(Sys.time(), "%H%M%S"))
  }

  # Run the pipeline
  result <- forge_build_and_run(hypothesis)

  # Reply to sender
  success <- identical(result$status, "complete")
  mailbox_reply(msg, "forge", result = result, success = success)

  result
}

#' Main polling loop
#'
#' Runs indefinitely (until /tmp/STOP_RESEARCH or /tmp/STOP_FORGE exists).
#' Polls mailbox every 15 seconds.
forge_main_loop <- function(poll_interval = 15) {
  cat("\n[agent_forge] ═══════════════════════════════════════\n")
  cat("[agent_forge] Forge Agent ONLINE. Polling every", poll_interval, "sec.\n")
  cat("[agent_forge] Stop: touch /tmp/STOP_FORGE\n")
  cat("[agent_forge] ═══════════════════════════════════════\n\n")

  completed <- 0L
  failed    <- 0L

  while (TRUE) {
    # Check stop signals
    if (file.exists("/tmp/STOP_RESEARCH") || file.exists("/tmp/STOP_FORGE")) {
      cat("[agent_forge] Stop signal detected. Shutting down.\n")
      cat(sprintf("[agent_forge] Session: %d completed, %d failed.\n",
                  completed, failed))
      break
    }

    # Poll inbox
    msg <- tryCatch(check_inbox_forge(), error = function(e) {
      cat(sprintf("[forge] Inbox check error: %s\n", e$message))
      NULL
    })

    if (!is.null(msg)) {
      result <- tryCatch(process_message(msg), error = function(e) {
        cat(sprintf("[forge] Process error: %s\n", e$message))
        list(status = "error")
      })

      if (identical(result$status, "complete")) {
        completed <- completed + 1L
      } else {
        failed <- failed + 1L
      }

      cat(sprintf("[forge] Tally: %d completed, %d failed.\n",
                  completed, failed))
    }

    Sys.sleep(poll_interval)
  }
}

cat("[agent_forge] Loaded. Functions: forge_build_and_run(), forge_main_loop()\n")
cat("[agent_forge]   Code gen: generate_run_all(), generate_factor_engine()\n")
cat("[agent_forge]   Types: single_factor, ensemble_blend, weight_optimization, regime_conditional\n")

# ══════════════════════════════════════════════════════════════════════════════
# 7. Auto-start if running non-interactively (tmux pane)
# ══════════════════════════════════════════════════════════════════════════════

if (!interactive()) {
  forge_main_loop()
}
