#==============================================================================
# rcpp_helpers.R — Rcpp 컴파일 + R fallback 래퍼
#
# 사용법:
#   source("02_Infrastructure/factor_db/rcpp_helpers.R")
#   .load_rcpp_helpers()   # 세션당 1회 (이후 자동 캐시)
#
# 제공 함수 (Rcpp 우선, 실패 시 R fallback):
#   .roll_mean(x, w)
#   .roll_sd(x, w)
#   .roll_skew(x, w)
#   .roll_kurt(x, w)
#   .roll_beta(stock, mkt, w)
#   .roll_cov(x, y, w)
#   .roll_idiovol(stock, mkt, w)
#   .rank_pct(x)
#
# 설계 원칙:
#   - Rcpp 컴파일 실패 시 R 순수 구현으로 자동 전환 (warn만, 중단 없음)
#   - 세션 내 재컴파일 방지: .rcpp_loaded 플래그 확인
#   - API 시그니처는 기존 코드와 호환
#==============================================================================

.rcpp_env <- new.env(parent = emptyenv())
.rcpp_env$.loaded <- FALSE
.rcpp_env$.use_rcpp <- FALSE

#──────────────────────────────────────────────────────────────────────────────
# 내부: Rcpp 컴파일 시도
#──────────────────────────────────────────────────────────────────────────────
.compile_rcpp <- function() {
  if (isTRUE(.rcpp_env$.loaded)) return(invisible(.rcpp_env$.use_rcpp))

  cpp_path <- tryCatch(
    {
      # Self-locate: try call stack first (works when source()'d directly)
      self_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
      if (is.null(self_dir) || !nzchar(self_dir)) {
        if (exists("FUNC_PATH")) {
          file.path(FUNC_PATH, "factor_db")
        } else {
          # Resolve OneDrive root from current username — avoids hardcoded "User"
          home_win <- Sys.getenv("USERPROFILE", unset = "")  # Windows USERPROFILE
          onedrive  <- if (nzchar(home_win)) {
            file.path(home_win, "OneDrive")
          } else {
            # WSL2: try /mnt/c/Users/<user>/OneDrive
            wsl_user <- Sys.getenv("USER", unset = "")
            if (nzchar(wsl_user)) {
              file.path("/mnt/c/Users", wsl_user, "OneDrive")
            } else {
              # Last-resort: old hardcoded fallback
              file.path("/mnt/c/Users/User/OneDrive")
            }
          }
          # Handle Korean directory name via UTF-8 literal
          proj_root <- file.path(onedrive,
                                 "\ubc14\ud0d5 \ud654\uba74",
                                 "Quant_Module_Moltbot")
          file.path(proj_root, "02_Infrastructure", "factor_db")
        }
      } else {
        self_dir
      }
    },
    error = function(e) NULL
  )

  cpp_file <- if (!is.null(cpp_path)) {
    file.path(cpp_path, "fast_rolling.cpp")
  } else {
    NULL
  }

  compiled <- FALSE
  if (!is.null(cpp_file) && file.exists(cpp_file)) {
    tryCatch({
      suppressPackageStartupMessages(library(Rcpp))
      Rcpp::sourceCpp(cpp_file, verbose = FALSE, rebuild = FALSE)
      compiled <- TRUE
      cat("[rcpp_helpers] Rcpp compiled:", cpp_file, "\n")
    }, error = function(e) {
      warning("[rcpp_helpers] Rcpp compile failed — using R fallback. Reason: ",
              conditionMessage(e))
    })
  } else {
    warning("[rcpp_helpers] fast_rolling.cpp not found at: ", cpp_file,
            " — using R fallback")
  }

  .rcpp_env$.use_rcpp <- compiled
  .rcpp_env$.loaded   <- TRUE
  invisible(compiled)
}

#──────────────────────────────────────────────────────────────────────────────
# R fallback 구현 (Rcpp 실패 시 대체)
#──────────────────────────────────────────────────────────────────────────────

# data.table::frollmean 우선 (훨씬 빠름), 없으면 순수 R
.r_roll_mean <- function(x, w) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::frollmean(x, n = w, na.rm = TRUE, align = "right")
  } else {
    n <- length(x)
    out <- rep(NA_real_, n)
    if (w > n) return(out)
    for (i in w:n) out[i] <- mean(x[(i - w + 1):i], na.rm = TRUE)
    out
  }
}

.r_roll_sd <- function(x, w) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::frollapply(x, n = w, FUN = function(v) sd(v, na.rm = TRUE),
                           align = "right")
  } else {
    n <- length(x)
    out <- rep(NA_real_, n)
    if (w > n) return(out)
    for (i in w:n) out[i] <- sd(x[(i - w + 1):i], na.rm = TRUE)
    out
  }
}

# Skew/Kurt: C++ uses population moment (m3/m2^1.5, m4/m2^2 - 3).
# R fallback matches C++ definition for consistency.
.r_roll_skew <- function(x, w) {
  n <- length(x)
  out <- rep(NA_real_, n)
  if (w > n) return(out)
  for (i in w:n) {
    v <- x[(i - w + 1):i]
    v <- v[!is.na(v)]
    if (length(v) < 3L) next
    mu <- mean(v)
    m2 <- mean((v - mu)^2)
    if (m2 < 1e-14) next
    m3 <- mean((v - mu)^3)
    out[i] <- m3 / (m2^1.5)
  }
  out
}

.r_roll_kurt <- function(x, w) {
  n <- length(x)
  out <- rep(NA_real_, n)
  if (w > n) return(out)
  for (i in w:n) {
    v <- x[(i - w + 1):i]
    v <- v[!is.na(v)]
    if (length(v) < 4L) next
    mu <- mean(v)
    m2 <- mean((v - mu)^2)
    if (m2 < 1e-14) next
    m4 <- mean((v - mu)^4)
    out[i] <- m4 / (m2^2) - 3.0
  }
  out
}

.r_roll_beta <- function(s, m, w) {
  n <- length(s)
  out <- rep(NA_real_, n)
  if (w > n) return(out)
  for (i in w:n) {
    sv <- s[(i - w + 1):i]; mv <- m[(i - w + 1):i]
    ok <- !is.na(sv) & !is.na(mv)
    sv <- sv[ok]; mv <- mv[ok]
    if (length(sv) < 5L) next
    vm <- var(mv, na.rm = FALSE)
    if (is.na(vm) || vm < 1e-14) next
    out[i] <- cov(sv, mv, use = "complete.obs") / vm
  }
  out
}

.r_roll_cov <- function(x, y, w) {
  n <- length(x)
  out <- rep(NA_real_, n)
  if (w > n) return(out)
  for (i in w:n) {
    xv <- x[(i - w + 1):i]; yv <- y[(i - w + 1):i]
    out[i] <- cov(xv, yv, use = "complete.obs")
  }
  out
}

# IdioVol: sqrt(RSS / (n-2)) to match textbook df after estimating alpha+beta
.r_roll_idiovol <- function(s, m, w) {
  n <- length(s)
  out <- rep(NA_real_, n)
  if (w > n) return(out)
  for (i in w:n) {
    sv <- s[(i - w + 1):i]; mv <- m[(i - w + 1):i]
    ok <- !is.na(sv) & !is.na(mv)
    sv <- sv[ok]; mv <- mv[ok]
    k <- length(sv)
    if (k < 5L) next
    fit <- tryCatch(lm.fit(cbind(1, mv), sv), error = function(e) NULL)
    if (is.null(fit)) next
    rss <- sum(fit$residuals^2)
    out[i] <- sqrt(rss / (k - 2L))
  }
  out
}

.r_rank_pct <- function(x) {
  r <- rank(x, na.last = "keep", ties.method = "average")
  n_valid <- sum(!is.na(x))
  if (n_valid <= 1L) return(rep(NA_real_, length(x)))
  (r - 1) / (n_valid - 1)
}

#──────────────────────────────────────────────────────────────────────────────
# 공개 래퍼 함수 — Rcpp 있으면 C++ 버전, 없으면 R fallback 호출
#──────────────────────────────────────────────────────────────────────────────

#' 세션당 1회 초기화. compute_*.R 상단에서 호출.
.load_rcpp_helpers <- function() {
  .compile_rcpp()
  invisible(NULL)
}

#' Rolling mean
#' data.table::frollmean은 벤치마크상 Rcpp보다 3배 빠름 → 항상 frollmean 우선.
#' Rcpp 버전은 frollmean 미사용 환경 대비로만 남김.
#' @param x numeric vector
#' @param w integer window size
.roll_mean <- function(x, w) {
  if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::frollmean(x, n = as.integer(w), na.rm = TRUE, align = "right")
  } else if (isTRUE(.rcpp_env$.use_rcpp)) {
    rolling_mean_cpp(x, as.integer(w))
  } else {
    .r_roll_mean(x, w)
  }
}

#' Rolling standard deviation (sample, ddof=1)
#' frollmean 방식으로 var를 구한 뒤 sqrt → data.table에 frollsd가 없으므로
#' Rcpp 버전을 우선 사용. Rcpp 없으면 frollapply.
.roll_sd <- function(x, w) {
  if (isTRUE(.rcpp_env$.use_rcpp)) {
    rolling_sd_cpp(x, as.integer(w))
  } else if (requireNamespace("data.table", quietly = TRUE)) {
    data.table::frollapply(x, n = as.integer(w),
                           FUN = function(v) sd(v, na.rm = TRUE),
                           align = "right")
  } else {
    .r_roll_sd(x, w)
  }
}

#' Rolling standardized skewness
.roll_skew <- function(x, w) {
  if (isTRUE(.rcpp_env$.use_rcpp))
    rolling_skew_cpp(x, as.integer(w))
  else
    .r_roll_skew(x, w)
}

#' Rolling excess kurtosis
.roll_kurt <- function(x, w) {
  if (isTRUE(.rcpp_env$.use_rcpp))
    rolling_kurt_cpp(x, as.integer(w))
  else
    .r_roll_kurt(x, w)
}

#' Rolling OLS beta = cov(stock, mkt) / var(mkt)
.roll_beta <- function(stock_ret, mkt_ret, w) {
  if (isTRUE(.rcpp_env$.use_rcpp))
    rolling_beta_cpp(stock_ret, mkt_ret, as.integer(w))
  else
    .r_roll_beta(stock_ret, mkt_ret, w)
}

#' Rolling covariance
.roll_cov <- function(x, y, w) {
  if (isTRUE(.rcpp_env$.use_rcpp))
    rolling_cov_cpp(x, y, as.integer(w))
  else
    .r_roll_cov(x, y, w)
}

#' Rolling idiosyncratic volatility (CAPM residual std dev)
.roll_idiovol <- function(stock_ret, mkt_ret, w) {
  if (isTRUE(.rcpp_env$.use_rcpp))
    rolling_idiovol_cpp(stock_ret, mkt_ret, as.integer(w))
  else
    .r_roll_idiovol(stock_ret, mkt_ret, w)
}

#' Cross-sectional rank percentile [0, 1]
.rank_pct <- function(x) {
  if (isTRUE(.rcpp_env$.use_rcpp))
    rank_pct_cpp(x)
  else
    .r_rank_pct(x)
}

#──────────────────────────────────────────────────────────────────────────────
# 자동 초기화 (source() 시 한 번 실행)
#──────────────────────────────────────────────────────────────────────────────
.load_rcpp_helpers()
