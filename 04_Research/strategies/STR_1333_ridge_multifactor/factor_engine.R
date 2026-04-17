#==============================================================================
# STR_1333 — Ridge Regularized Multi-Factor (FC_1c_Ridge, 20 factors)
#
# 핵심아이디어: 327개 팩터 중 소수 Grade A만 사용하는 기존 접근 대신,
#   20개 후보 팩터를 glmnet(alpha=0) expanding window Ridge로 결합.
#   약한 signal까지 앙상블로 흡수하여 소수 강팩터 의존도를 낮춤.
#   Kozak, Nagel & Santosh (2020): Ridge가 OOS에서 LASSO/OLS 지배.
#
# Method: FC_1c_Ridge (method_registry.json)
# Input:  20 candidate factors from Factor DB (Z_Score_Aligned only, C13)
# Target: Forward 1-month cross-sectional returns
# Window: Expanding (min 36 months, C1/C12)
# Lambda: cv.glmnet lambda.1se (conservative)
# PIT:    Usable_Date IC (C14), load_month_factors() only (C15)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

cat("[factor_engine] STR_1333: Ridge Regularized Multi-Factor (20 factors)...\n")

# ---- Constants ----
# 20 candidate factors from contract (6 families)
CANDIDATE_FACTORS <- c(
  # Defense
  "D01_IdioVol", "D02_Beta", "D04_Downside_Beta", "D05_MaxRet",
  # Value
  "V01_BM", "V02_EP", "V03_CFP",
  # Quality
  "Q04_Piotroski_F", "Q07_Earnings_Stability", "Q09_CFOA", "Q17_ROIC",
  # Consensus
  "C01_SUE", "C04_ESBR", "C06_TP_Gap",
  # Accrual
  "AC01_Total_Accruals_CF", "AC07_Operating_Accruals", "AC05_NOA",
  # Momentum
  "M07_IndMom", "M02_Mom_6_1", "M08_Residual_Mom"
)

LIQ_THRESHOLD   <- 2e8
MIN_FACTOR_COUNT <- 12L   # require at least 12 of 20 factors available

# ---- S1: IC Screening (per-month, expanding window, PIT) ----
#' Screen factors by IC > 0.02 at signal date using expanding window IC history.
#' Returns subset of CANDIDATE_FACTORS that pass threshold.
#' PIT: Only uses IC data with Usable_Date <= sig_date (C14).
screen_factors_by_ic <- function(sig_d, ic_hist, ic_threshold = 0.02) {
  if (is.null(ic_hist) || nrow(ic_hist) == 0) return(CANDIDATE_FACTORS)

  # PIT: only IC data usable at sig_d
  if ("Usable_Date" %in% names(ic_hist)) {
    ic_avail <- ic_hist[Usable_Date <= sig_d & Factor_Name %in% CANDIDATE_FACTORS]
  } else {
    ic_avail <- ic_hist[Date < sig_d & Factor_Name %in% CANDIDATE_FACTORS]
  }

  if (nrow(ic_avail) == 0) return(CANDIDATE_FACTORS)

  # Expanding window mean IC per factor
  ic_summary <- ic_avail[, .(Mean_IC = mean(abs(IC), na.rm = TRUE), N = .N),
                          by = Factor_Name]
  passed <- ic_summary[Mean_IC >= ic_threshold & N >= 12, Factor_Name]

  # Ensure minimum factor count
  if (length(passed) < MIN_FACTOR_COUNT) {
    # Fall back to top MIN_FACTOR_COUNT by |IC|
    setorder(ic_summary, -Mean_IC)
    passed <- head(ic_summary$Factor_Name, MIN_FACTOR_COUNT)
  }

  intersect(passed, CANDIDATE_FACTORS)
}


# ---- S2: Ridge Score Computation ----
#' Compute Ridge-weighted composite score for a single month.
#' Uses accumulated training data (expanding window).
#'
#' @param panel_cur data.table: Ticker x Factor Z_Score_Aligned (current month)
#' @param train_pool list of past monthly data.tables (Ticker x Factors x Fwd_Ret)
#' @param factor_cols character vector of factor column names
#' @param min_train integer: minimum training observations
#' @return data.table(Ticker, Ridge_Score) or NULL
compute_ridge_scores <- function(panel_cur, train_dt_cached, factor_cols, min_train = 300L) {
  # train_dt_cached: pre-stacked data.table (avoid rbindlist every call)
  if (is.null(train_dt_cached) || nrow(train_dt_cached) == 0) return(NULL)

  common_cols <- intersect(factor_cols, names(train_dt_cached))
  common_cols <- intersect(common_cols, names(panel_cur))
  if (length(common_cols) < 5L) return(NULL)

  # Training X, y
  X_train <- as.matrix(train_dt_cached[, ..common_cols])
  y_train <- train_dt_cached$Fwd_Ret
  valid <- complete.cases(X_train) & !is.na(y_train)
  X_train <- X_train[valid, , drop = FALSE]
  y_train <- y_train[valid]

  if (nrow(X_train) < min_train || ncol(X_train) < 5L) return(NULL)

  # Winsorize returns (1%, 99%) for stability
  q_lo <- quantile(y_train, 0.01, na.rm = TRUE)
  q_hi <- quantile(y_train, 0.99, na.rm = TRUE)
  y_train <- pmin(pmax(y_train, q_lo), q_hi)

  # Ridge: alpha=0, CV for lambda
  ridge_fit <- tryCatch({
    glmnet::cv.glmnet(
      x = X_train,
      y = y_train,
      alpha = 0,                  # Ridge (L2 penalty)
      nfolds = 5L,
      type.measure = "mse",
      standardize = FALSE         # already Z_Score_Aligned
    )
  }, error = function(e) NULL)

  if (is.null(ridge_fit)) return(NULL)

  # Predict on current month
  X_cur <- as.matrix(panel_cur[, ..common_cols])
  valid_cur <- complete.cases(X_cur)
  if (sum(valid_cur) < 30L) return(NULL)

  pred <- as.numeric(predict(ridge_fit, newx = X_cur[valid_cur, , drop = FALSE],
                              s = "lambda.1se"))

  list(
    scores = data.table(
      Ticker      = panel_cur$Ticker[valid_cur],
      Ridge_Score = pred
    ),
    ridge_fit   = ridge_fit,
    lambda_1se  = ridge_fit$lambda.1se,
    n_factors   = length(common_cols),
    n_train_obs = nrow(X_train)
  )
}


# ---- S3: EW Baseline Score ----
#' Simple equal-weight average of Z_Score_Aligned (FC_1a baseline).
compute_ew_scores <- function(panel_cur, factor_cols) {
  common_cols <- intersect(factor_cols, names(panel_cur))
  if (length(common_cols) < 5L) return(NULL)

  X <- as.matrix(panel_cur[, ..common_cols])
  valid <- rowSums(!is.na(X)) >= length(common_cols) * 0.5
  if (sum(valid) < 30L) return(NULL)

  data.table(
    Ticker   = panel_cur$Ticker[valid],
    EW_Score = rowMeans(X[valid, , drop = FALSE], na.rm = TRUE)
  )
}


cat(sprintf("[factor_engine] %d candidate factors loaded.\n", length(CANDIDATE_FACTORS)))
cat("  Functions: screen_factors_by_ic(), compute_ridge_scores(), compute_ew_scores()\n")
