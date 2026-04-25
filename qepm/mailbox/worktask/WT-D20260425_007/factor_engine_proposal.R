#==============================================================================
# WT-D20260425_007 — factor_engine_proposal.R
#
# Purpose: Iter 2 — MEGA_05 6F factor mix 동일 + regime label injection.
#          Downstream Risk/Optimizer가 호출하여 alpha + regime 신호를 통합 로드.
#
# Boundary: Alpha Research Agent는 factor mix / regime indicator 신호 정의까지만.
#           - Σ 추정 / weight 결정 / MinCVaR 구현 절대 금지 (Risk + Optimizer 영역).
#           - 본 파일은 alpha_scores.parquet + regime_panel.parquet 두 산출물을
#             단순히 join + reproducible 하게 expose.
#
# PIT compliance: regime label은 sig_date 기준 (built at month_end_t, applied t+1).
#                 모든 expanding percentile은 strictly past (C1).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-D20260425_007"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_007")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

#==============================================================================
# Public API — downstream agents call these
#==============================================================================

#' load_alpha_scores_with_regime
#'
#' alpha_scores.parquet (sig_date × Ticker × Score × Ret_1m × regime_state) 로드.
#' Optimizer가 sig_date 별로 regime_state를 조회하여 regime-conditional Σ를 만들 때 사용.
#'
#' @return data.table [sig_date, Ticker, Score, Ret_1m, regime_state, theta_json]
load_alpha_scores_with_regime <- function() {
  fp <- file.path(ART_DIR, "alpha_scores.parquet")
  stopifnot(file.exists(fp))
  dt <- as.data.table(read_parquet(fp))
  setkey(dt, sig_date, Ticker)
  dt
}

#' load_regime_panel
#'
#' regime_panel.parquet (sig_date × regime_state × diagnostics) 로드.
#' Risk Manager가 regime stress test / EVT / DCC 분석 시 사용.
#'
#' @return data.table [sig_date, regime_state, regime_score, rv60, dd_12m, breadth60, ret_1m_bm]
load_regime_panel <- function() {
  fp <- file.path(ART_DIR, "regime_panel.parquet")
  stopifnot(file.exists(fp))
  dt <- as.data.table(read_parquet(fp))
  setkey(dt, sig_date)
  dt
}

#' load_conditional_ic
#'
#' conditional IC matrix — regime × factor.
#'
#' @param wide TRUE면 wide format (regime × factor), FALSE면 long [regime, factor, mean_IC, ICIR, n_months].
#' @return data.table
load_conditional_ic <- function(wide = TRUE) {
  fp <- if (wide)
    file.path(ART_DIR, "conditional_ic_factor_regime_wide.parquet")
  else
    file.path(ART_DIR, "conditional_ic_factor_regime.parquet")
  stopifnot(file.exists(fp))
  as.data.table(read_parquet(fp))
}

#' load_alpha_package
#'
#' alpha_package.json — full schema.
load_alpha_package <- function() {
  fp <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID, "alpha_package.json")
  stopifnot(file.exists(fp))
  fromJSON(fp, simplifyVector = TRUE)
}

#==============================================================================
# Optimizer-facing helpers (decision support — NOT decision-making)
#==============================================================================

#' get_regime_at_signal
#'
#' Optimizer가 특정 sig_date에서 어떤 regime인지 조회.
#' Risk가 regime-conditional Σ를 구성할 때 ticker 그룹화에 사용.
#'
#' @param sig_date Date scalar
#' @return character — one of BULL / NORMAL / CAUTION / CRISIS
get_regime_at_signal <- function(sig_date) {
  panel <- load_regime_panel()
  hit <- panel[sig_date <= as.Date(sig_date), tail(.SD, 1L)]
  if (nrow(hit) == 0L) return("NORMAL")
  hit$regime_state
}

#' alpha_vector_at
#'
#' Optimizer 입력용 — 특정 sig_date의 top-N alpha vector + regime label.
#'
#' @param sig_date Date
#' @param top_n integer (default 20 — hard constraint)
#' @return list(alpha_vector, regime_state, sig_date, n_universe)
alpha_vector_at <- function(sig_date, top_n = 20L) {
  scores <- load_alpha_scores_with_regime()
  sub <- scores[sig_date == as.Date(sig_date) & !is.na(Score) & is.finite(Score)]
  sub <- sub[order(-Score)]
  if (nrow(sub) == 0L) {
    return(list(alpha_vector = list(), regime_state = "NORMAL",
                sig_date = sig_date, n_universe = 0L))
  }
  mu <- mean(sub$Score, na.rm = TRUE)
  sd_s <- sd(sub$Score, na.rm = TRUE)
  sub[, alpha_hat := (Score - mu) / pmax(sd_s, 1e-10)]
  top <- head(sub, top_n)
  list(
    alpha_vector = setNames(round(top$alpha_hat, 5), top$Ticker),
    regime_state = top$regime_state[1],
    sig_date     = as.character(sig_date),
    n_universe   = nrow(sub)
  )
}

#==============================================================================
# Self-verification
#==============================================================================

if (sys.nframe() == 0L) {
  cat("=== factor_engine_proposal.R self-test ===\n")

  scores <- load_alpha_scores_with_regime()
  cat(sprintf("alpha_scores: %d rows | %d months | regimes: %s\n",
              nrow(scores),
              uniqueN(scores$sig_date),
              paste(sort(unique(scores$regime_state)), collapse = ", ")))

  panel  <- load_regime_panel()
  cat(sprintf("regime_panel: %d months | distribution: %s\n",
              nrow(panel),
              paste(sprintf("%s:%d",
                            panel[, .N, by = regime_state]$regime_state,
                            panel[, .N, by = regime_state]$N), collapse = ", ")))

  ic_wide <- load_conditional_ic(wide = TRUE)
  cat(sprintf("conditional_ic_wide: shape (%d, %d)\n",
              nrow(ic_wide), ncol(ic_wide)))
  print(ic_wide)

  pkg <- load_alpha_package()
  cat(sprintf("alpha_package WT_ID: %s | hypothesis: %s\n",
              pkg$task_id, pkg$hypothesis_title))

  last_sig <- max(scores$sig_date)
  av <- alpha_vector_at(last_sig, top_n = 20L)
  cat(sprintf("alpha_vector_at(%s): regime=%s | top20 names=%d | range=[%.3f, %.3f]\n",
              last_sig, av$regime_state,
              length(av$alpha_vector),
              min(unlist(av$alpha_vector)),
              max(unlist(av$alpha_vector))))

  cat("\n=== self-test PASS ===\n")
}
