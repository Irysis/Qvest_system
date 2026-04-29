#==============================================================================
# Quant Module — Backtest Harness
# Version: 1.0.0
#
# Reusable library extracted from Maxwell Protocol Steps 1-4.
# Provides: load_rawdata(), run_monthly_simulation(), summarise_perf(),
#           generate_charts(), calc_ivol_weights(), get_execution_date()
#
# Usage:
#   source("config.R")
#   source("backtest_harness.R")
#   res <- load_rawdata()          # returns list(RAWDATA, BM_DT, data_list)
#   sim <- run_monthly_simulation(res$RAWDATA, res$BM_DT, FACTORS)
#   perf <- summarise_perf(sim$strategy_xts)
#   generate_charts(sim, output_dir = "output/")
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(sys.frame(1)$ofile %||% "."), "config.R"))
}

# ─── Package Loading ────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(openxlsx)
  library(readxl)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
  library(stringr)
  library(tidyr)
  library(lubridate)
  library(jsonlite)
  library(quadprog)
})

options(scipen = 999)
options(stringsAsFactors = FALSE)
Sys.setenv(TZ = "Asia/Seoul")

# Load QT_to_xts utility
source(file.path(FUNC_PATH, "F1. QT_to_xts.r"))

# ─── Rcpp 가중 엔진 로드 (weight_engine.cpp) ────────────────────────────────
# 컴파일 성공 시 .USE_RCPP_WEIGHT_ENGINE = TRUE → gerber/rmt/hrp/crisis_consec
# 컴파일 실패 시 R fallback 자동 적용
.USE_RCPP_WEIGHT_ENGINE <- tryCatch({
  cpp_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "02_Infrastructure/portfolio/weight_engine.cpp"
  )
  if (file.exists(cpp_path)) {
    Rcpp::sourceCpp(cpp_path)
    cat("[backtest_harness] weight_engine.cpp loaded (Rcpp).\n")
    TRUE
  } else {
    cat("[backtest_harness] weight_engine.cpp not found, using R fallback.\n")
    FALSE
  }
}, error = function(e) {
  cat("[backtest_harness] Rcpp compile failed:", conditionMessage(e), "— R fallback.\n")
  FALSE
})

cat("[backtest_harness] Loaded.\n")

# ─── Rcpp NAV 시뮬레이션 엔진 로드 (sim_engine_nav.cpp) ─────────────────────
# 컴파일 성공 시 .USE_RCPP_NAV_ENGINE = TRUE → cpp_daily_nav() 사용 (4x 속도)
# 컴파일 실패 시 R fallback 자동 적용 (기존 이중 루프)
.USE_RCPP_NAV_ENGINE <- tryCatch({
  nav_cpp_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "02_Infrastructure/portfolio/sim_engine_nav.cpp"
  )
  if (file.exists(nav_cpp_path)) {
    Rcpp::sourceCpp(nav_cpp_path)
    cat("[backtest_harness] sim_engine_nav.cpp loaded (Rcpp NAV 4x speedup).\n")
    TRUE
  } else {
    cat("[backtest_harness] sim_engine_nav.cpp not found, using R NAV fallback.\n")
    FALSE
  }
}, error = function(e) {
  cat("[backtest_harness] Rcpp NAV compile failed:", conditionMessage(e), "— R fallback.\n")
  FALSE
})

# ─── Daily NAV Wrapper (.compute_daily_nav) ───────────────────────────────────
# Rcpp 경로 우선, 실패 시 기존 R 이중 루프로 자동 fallback
# @param RAWDATA          data.table: Date, Ticker, Close (setkey(Date, Ticker) 상태)
# @param holdings         named list: list(ticker = list(shares=, last_price=))
# @param exec_dates_range Date vector: 계산할 날짜 범위
# @param cash             numeric: 현금 잔액
# @return data.table: Date(Date), NAV(numeric)
.compute_daily_nav <- function(RAWDATA, holdings, exec_dates_range, cash) {
  if (.USE_RCPP_NAV_ENGINE && length(holdings) > 0 && length(exec_dates_range) > 0) {
    tickers_vec     <- names(holdings)
    shares_vec      <- sapply(holdings, `[[`, "shares")
    last_prices_vec <- sapply(holdings, `[[`, "last_price")

    # rawdata subset: 관련 종목 + 기간만 (C15 준수 — 이미 RAWDATA에서 추출)
    rd_sub <- RAWDATA[Ticker %in% tickers_vec & Date %in% exec_dates_range,
                      .(Ticker, Date_int = as.integer(Date), Close)]

    result <- cpp_daily_nav(
      rawdata_subset = rd_sub,
      tickers        = tickers_vec,
      shares         = shares_vec,
      last_prices    = last_prices_vec,
      dates          = as.integer(exec_dates_range),
      cash           = cash
    )
    # Date_int → Date 복원
    out <- as.data.table(result)
    out[, Date := as.Date(Date_int, origin = "1970-01-01")]
    out[, Date_int := NULL]
    setcolorder(out, c("Date", "NAV"))
    return(out)
  }

  # ── R fallback (기존 이중 루프, 동작 동일) ──────────────────────────────────
  nav_list <- vector("list", length(exec_dates_range))
  for (i in seq_along(exec_dates_range)) {
    d         <- as.Date(exec_dates_range[i])
    daily_val <- cash
    for (tk in names(holdings)) {
      price_row <- RAWDATA[Ticker == tk & Date == d, Close]
      if (length(price_row) > 0 && !is.na(price_row[1])) {
        daily_val <- daily_val + holdings[[tk]]$shares * price_row[1]
      } else {
        daily_val <- daily_val + holdings[[tk]]$shares * holdings[[tk]]$last_price
      }
    }
    nav_list[[i]] <- data.table(Date = d, NAV = daily_val)
  }
  rbindlist(nav_list)
}

#==============================================================================
# 1. load_rawdata() — Universe + BM + OHLCVS → RAWDATA
#==============================================================================

load_rawdata <- function(use_cache = TRUE) {
  # ── Parquet 캐시 우선 ──
  if (use_cache && file.exists(RAWDATA_CACHE) && file.exists(BM_CACHE)) {
    cache_age <- difftime(Sys.time(), file.mtime(RAWDATA_CACHE), units = "days")
    if (cache_age < 30) {
      cat("[load_rawdata] Loading from Parquet cache...\n")
      RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
      BM_DT   <- as.data.table(read_parquet(BM_CACHE))
      cat(sprintf("[load_rawdata] Cache loaded: %d rows | %s ~ %s\n",
                  nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))
      return(list(RAWDATA = RAWDATA, BM_DT = BM_DT))
    }
  }

  # ── 캐시 없으면 build_cache.R 실행 안내 ──
  stop(paste0(
    "[load_rawdata] Parquet cache not found.\n",
    "  Run first:  Rscript 02_Infrastructure/build_cache.R\n",
    "  This converts OHLCVS.xlsx (890MB) to Parquet (sheet-by-sheet, memory safe).\n",
    "  Cache location: ", CACHE_DIR
  ))
}


#==============================================================================
# 1b. load_fundamentals() — DART 펀더멘털 팩터 로드
#==============================================================================

load_fundamentals <- function() {
  if (!file.exists(DART_FACTOR_CACHE)) {
    cat("[load_fundamentals] DART cache not found. Run data_collector_dart.R pipeline first.\n")
    return(NULL)
  }
  cat("[load_fundamentals] Loading DART fundamental factors...\n")
  dt <- as.data.table(read_parquet(DART_FACTOR_CACHE))
  cat(sprintf("  > %d records | %d tickers | years %d-%d\n",
              nrow(dt), uniqueN(dt$Ticker),
              min(dt$bsns_year), max(dt$bsns_year)))
  dt
}


#==============================================================================
# 1c. load_macro_regime() — FRED 매크로 레짐 시그널 로드 (자동 갱신)
#==============================================================================

load_macro_regime <- function(max_age_days = 7) {
  needs_refresh <- FALSE

  if (!file.exists(FRED_REGIME_CACHE)) {
    needs_refresh <- TRUE
  } else {
    age <- as.numeric(difftime(Sys.time(), file.mtime(FRED_REGIME_CACHE), units = "days"))
    if (age > max_age_days) {
      cat(sprintf("[load_macro_regime] Cache is %.0f days old (limit: %d). Auto-refreshing...\n",
                  age, max_age_days))
      needs_refresh <- TRUE
    }
  }

  if (needs_refresh) {
    fred_script <- file.path(DATA_DIR, "data_collector_fred.R")
    if (file.exists(fred_script)) {
      source(fred_script)
      fred_run_pipeline()
    } else {
      cat("[load_macro_regime] data_collector_fred.R not found. Cannot auto-refresh.\n")
      if (!file.exists(FRED_REGIME_CACHE)) return(NULL)
    }
  }

  cat("[load_macro_regime] Loading FRED macro regime...\n")
  dt <- as.data.table(read_parquet(FRED_REGIME_CACHE))
  cat(sprintf("  > %d months | %s ~ %s\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt
}


#==============================================================================
# 1d. load_investor() — 거래주체(투자자별) 순매수 데이터 로드
#==============================================================================

load_investor <- function(
    fmt = c("wide", "long", "foreign", "institutional", "individual"),
    start_date = NULL,
    end_date = NULL
) {
  fmt <- match.arg(fmt)

  pq_file <- switch(fmt,
    wide          = file.path(INVESTOR_CACHE, "investor_wide.parquet"),
    long          = file.path(INVESTOR_CACHE, "investor_all.parquet"),
    foreign       = file.path(INVESTOR_CACHE, "investor_foreign.parquet"),
    institutional = file.path(INVESTOR_CACHE, "investor_institutional.parquet"),
    individual    = file.path(INVESTOR_CACHE, "investor_individual.parquet")
  )

  if (!file.exists(pq_file)) {
    cat("[load_investor] Cache not found. Run parse_investor_act() first.\n")
    cat("  source('02_Infrastructure/parse_investor_quantiwise.R'); parse_investor_act()\n")
    return(NULL)
  }

  cat(sprintf("[load_investor] Loading %s...\n", fmt))
  dt <- as.data.table(read_parquet(pq_file))

  if (!is.null(start_date)) dt <- dt[Date >= as.Date(start_date)]
  if (!is.null(end_date))   dt <- dt[Date <= as.Date(end_date)]

  cat(sprintf("  > %s rows | %d tickers | %s ~ %s\n",
              format(nrow(dt), big.mark = ","), uniqueN(dt$Ticker),
              min(dt$Date), max(dt$Date)))
  dt
}


#==============================================================================
# 1e. load_valuation() — 밸류에이션 팩터 로드 (fPER, fPBR, fDY, tPER, tPBR, PSR, PCR, EV/EBITDA)
#==============================================================================

load_valuation <- function(
    start_date = NULL,
    end_date = NULL,
    cache_path = VALUATION_CACHE
) {
  if (!file.exists(cache_path)) {
    cat("[load_valuation] Cache not found. Run build_valuation() first.\n")
    cat("  source('02_Infrastructure/valuation_calculator.R'); build_valuation()\n")
    return(NULL)
  }

  cat("[load_valuation] Loading valuation factors...\n")
  dt <- as.data.table(read_parquet(cache_path))
  dt[, Date := as.Date(Date)]

  if (!is.null(start_date)) dt <- dt[Date >= as.Date(start_date)]
  if (!is.null(end_date))   dt <- dt[Date <= as.Date(end_date)]

  cat(sprintf("  > %s rows | %d tickers | %s ~ %s\n",
              format(nrow(dt), big.mark = ","), uniqueN(dt$Ticker),
              min(dt$Date), max(dt$Date)))
  dt
}


#==============================================================================
# 2. get_execution_date() — Signal date → next month's first trading day
#==============================================================================

get_execution_date <- function(signal_date, all_dates) {
  ym <- format(signal_date, "%Y-%m")
  yr <- as.integer(substr(ym, 1, 4))
  mo <- as.integer(substr(ym, 6, 7))
  if (mo == 12) { yr <- yr + 1; mo <- 1 } else { mo <- mo + 1 }
  next_start <- as.Date(sprintf("%04d-%02d-01", yr, mo))
  candidates <- all_dates[all_dates >= next_start]
  if (length(candidates) > 0) return(min(candidates)) else return(NA_Date_)
}


#==============================================================================
# 3. calc_ivol_weights() — Inverse-volatility weights
#==============================================================================

calc_ivol_weights <- function(tickers, ret_dt, n_days = 60, max_w = 0.15) {
  vols <- sapply(tickers, function(tk) {
    v <- tail(ret_dt[Ticker == tk]$Ret, n_days)
    if (length(v) < 10) return(NA_real_)
    sd(v, na.rm = TRUE)
  })
  # Floor vols at the 10th percentile to prevent near-zero vol stocks dominating
  vol_floor <- quantile(vols, 0.10, na.rm = TRUE)
  if (is.na(vol_floor) || vol_floor <= 0) vol_floor <- 1e-4
  vols[is.na(vols)] <- median(vols, na.rm = TRUE)
  vols <- pmax(vols, vol_floor)
  vols[vols == 0]   <- 1e-6
  w <- 1 / vols
  w <- w / sum(w)
  # Cap individual weights at max_w and re-normalize
  if (any(w > max_w)) {
    w <- pmin(w, max_w)
    w <- w / sum(w)
  }
  w
}


#==============================================================================
# 3-B-0. Covariance pre-processing: Gerber Statistic + RMT denoising
#==============================================================================

#' Gerber Statistic correlation (Gerber, Hurst, Konev 2022)
#' Noise-robust: only counts co-movements beyond threshold × sd
#' Rcpp 분기: .USE_RCPP_WEIGHT_ENGINE=TRUE → cpp_gerber_cor() 호출 (6~10x speedup)
.gerber_cor <- function(ret_mat, threshold = 0.5) {
  if (isTRUE(.USE_RCPP_WEIGHT_ENGINE) && exists("cpp_gerber_cor")) {
    return(cpp_gerber_cor(ret_mat, threshold))
  }
  p <- ncol(ret_mat)
  sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
  h <- threshold * sds
  cor_mat <- diag(p)
  for (i in 1:(p - 1)) {
    xi <- ret_mat[, i]
    hi <- h[i]
    for (j in (i + 1):p) {
      xj <- ret_mat[, j]
      hj <- h[j]
      up_i <- xi > hi;  dn_i <- xi < -hi
      up_j <- xj > hj;  dn_j <- xj < -hj
      conc <- sum((up_i & up_j) | (dn_i & dn_j), na.rm = TRUE)
      disc <- sum((up_i & dn_j) | (dn_i & up_j), na.rm = TRUE)
      denom <- conc + disc
      cor_mat[i, j] <- cor_mat[j, i] <- if (denom > 0) (conc - disc) / denom else 0
    }
  }
  colnames(cor_mat) <- rownames(cor_mat) <- colnames(ret_mat)
  cor_mat
}

#' RMT denoising (Marchenko-Pastur eigenvalue filtering)
#' Shrinks noise eigenvalues below MP upper bound to average
#' Rcpp 분기: .USE_RCPP_WEIGHT_ENGINE=TRUE → cpp_rmt_denoise() 호출
.rmt_denoise <- function(cor_mat, q_ratio) {
  if (isTRUE(.USE_RCPP_WEIGHT_ENGINE) && exists("cpp_rmt_denoise")) {
    return(cpp_rmt_denoise(cor_mat, q_ratio))
  }
  n <- nrow(cor_mat)
  if (n < 3 || q_ratio < 1) return(cor_mat)  # too few assets, skip
  lambda_plus <- (1 + 1 / sqrt(q_ratio))^2
  eig <- eigen(cor_mat, symmetric = TRUE)
  vals <- eig$values; vecs <- eig$vectors
  noise_idx <- which(vals <= lambda_plus)
  if (length(noise_idx) > 0 && length(noise_idx) < n) {
    vals[noise_idx] <- mean(vals[noise_idx])
  }
  # diag(x) safe: use matrix multiplication with diagonal
  D <- matrix(0, n, n); diag(D) <- vals
  cor_clean <- vecs %*% D %*% t(vecs)
  diag(cor_clean) <- 1.0
  cor_clean <- (cor_clean + t(cor_clean)) / 2
  colnames(cor_clean) <- rownames(cor_clean) <- colnames(cor_mat)
  cor_clean
}

#' Dispatch covariance/correlation pre-processing
#' @param cov_method "sample" | "ledoit_wolf" | "gerber_rmt"
.get_cor_cov <- function(ret_mat, cov_method = "sample") {
  if (cov_method == "gerber_rmt") {
    q_ratio <- nrow(ret_mat) / ncol(ret_mat)
    cor_mat <- .gerber_cor(ret_mat)
    cor_mat <- .rmt_denoise(cor_mat, q_ratio)
    # Gerber-based cov = cor * outer(sd, sd)
    sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
    cov_mat <- cor_mat * outer(sds, sds)
  } else if (cov_method == "ledoit_wolf") {
    cov_mat <- .ledoit_wolf_shrink(ret_mat)
    sds <- sqrt(diag(cov_mat))
    cor_mat <- cov_mat / outer(sds, sds)
    diag(cor_mat) <- 1.0
  } else {
    cor_mat <- cor(ret_mat, use = "pairwise.complete.obs")
    cov_mat <- cov(ret_mat, use = "pairwise.complete.obs")
  }
  cor_mat[is.na(cor_mat)] <- 0
  cov_mat[is.na(cov_mat)] <- 0
  list(cor = cor_mat, cov = cov_mat)
}

#==============================================================================
# 3-B. calc_hrp_weights() — Hierarchical Risk Parity (Lopez de Prado 2016)
#==============================================================================

calc_hrp_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15,
                             cov_method = "sample") {
  # Build return matrix
  ret_mat <- .build_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(ret_mat) || ncol(ret_mat) < 3) {
    return(rep(1 / length(tickers), length(tickers)))  # fallback to EW
  }

  survived <- colnames(ret_mat)
  dropped  <- setdiff(tickers, survived)

  # Correlation & covariance (dispatch by cov_method, fallback to sample)
  cc <- tryCatch(
    .get_cor_cov(ret_mat, cov_method),
    error = function(e) {
      cat(sprintf("[HRP] %s failed (%s), falling back to sample\n", cov_method, e$message))
      .get_cor_cov(ret_mat, "sample")
    }
  )
  cor_mat <- cc$cor
  cov_mat <- cc$cov
  if (!is.matrix(cor_mat) || nrow(cor_mat) != ncol(cor_mat)) {
    cor_mat <- cor(ret_mat, use = "pairwise.complete.obs")
    cor_mat[is.na(cor_mat)] <- 0
    cov_mat <- cov(ret_mat, use = "pairwise.complete.obs")
    cov_mat[is.na(cov_mat)] <- 0
  }
  d <- 0.5 * (1 - cor_mat); d[d < 0] <- 0
  dist_mat <- as.dist(sqrt(d))

  # Hierarchical clustering (ward.D2: balanced clusters, matching F4.HRP.R tuning)
  hc <- hclust(dist_mat, method = "ward.D2")
  order_idx <- hc$order
  w_sub <- tryCatch({
    ws <- .hrp_bisect(cov_mat, order_idx)
    ws / sum(ws)
  }, error = function(e) rep(1 / length(survived), length(survived)))
  names(w_sub) <- survived

  # Map back to full tickers: dropped stocks get equal share of a small allocation
  w_full <- rep(0, length(tickers))
  names(w_full) <- tickers
  if (length(dropped) > 0) {
    # Give dropped stocks EW share, then scale HRP weights for the rest
    drop_share <- length(dropped) / length(tickers)  # proportional share
    for (tk in dropped) w_full[tk] <- 1 / length(tickers)
    hrp_scale <- 1 - sum(w_full)
    for (tk in survived) w_full[tk] <- w_sub[tk] * hrp_scale
  } else {
    w_full[survived] <- w_sub[survived]
  }
  w_full <- w_full / sum(w_full)

  # Cap weights
  if (any(w_full > max_w)) {
    w_full <- pmin(w_full, max_w)
    w_full <- w_full / sum(w_full)
  }
  w_full
}

# Helper: build n_assets × n_days return matrix (optimized via dcast)
.build_ret_matrix <- function(tickers, ret_dt, n_days) {
  # Get the last n_days dates available
  sub <- ret_dt[Ticker %in% tickers, .(Date, Ticker, Ret)]
  last_dates <- tail(sort(unique(sub$Date)), n_days)
  sub <- sub[Date %in% last_dates]
  if (nrow(sub) == 0) return(NULL)

  # Pivot to wide: rows=Date, cols=Ticker
  wide <- dcast(sub, Date ~ Ticker, value.var = "Ret")
  mat <- as.matrix(wide[, -1, drop = FALSE])

  # Remove tickers with too few observations
  good_cols <- colSums(!is.na(mat)) >= 30
  if (sum(good_cols) < 3) return(NULL)
  mat <- mat[, good_cols, drop = FALSE]

  # Remove rows with too many NAs
  good_rows <- rowSums(!is.na(mat)) >= ncol(mat) * 0.5
  mat <- mat[good_rows, , drop = FALSE]
  if (nrow(mat) < 30) return(NULL)

  # Fill remaining NAs with 0
  mat[is.na(mat)] <- 0
  mat
}

# Recursive bisection for HRP
# Rcpp 분기: .USE_RCPP_WEIGHT_ENGINE=TRUE → cpp_hrp_weights() 호출 (9x speedup)
.hrp_bisect <- function(cov_mat, order_idx) {
  if (isTRUE(.USE_RCPP_WEIGHT_ENGINE) && exists("cpp_hrp_weights")) {
    return(as.numeric(cpp_hrp_weights(cov_mat, order_idx)))
  }
  n <- length(order_idx)
  w <- rep(1.0, n)
  clusters <- list(order_idx)

  while (length(clusters) > 0) {
    new_clusters <- list()
    for (cl in clusters) {
      if (length(cl) <= 1) next
      mid <- ceiling(length(cl) / 2)
      left  <- cl[1:mid]
      right <- cl[(mid + 1):length(cl)]

      var_left  <- .cluster_var(cov_mat, left)
      var_right <- .cluster_var(cov_mat, right)
      alpha <- 1 - var_left / (var_left + var_right)

      w[left]  <- w[left]  * alpha
      w[right] <- w[right] * (1 - alpha)

      if (length(left) > 1)  new_clusters[[length(new_clusters) + 1]] <- left
      if (length(right) > 1) new_clusters[[length(new_clusters) + 1]] <- right
    }
    clusters <- new_clusters
  }
  w
}

.cluster_var <- function(cov_mat, idx) {
  if (length(idx) == 1) return(cov_mat[idx, idx])
  sub_cov <- cov_mat[idx, idx, drop = FALSE]
  ivp <- 1 / diag(sub_cov)
  ivp <- ivp / sum(ivp)
  as.numeric(t(ivp) %*% sub_cov %*% ivp)
}


#==============================================================================
# 3-C. calc_minvar_weights() — Minimum Variance (Ledoit-Wolf shrinkage)
#==============================================================================

calc_minvar_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15) {
  ret_mat <- .build_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(ret_mat) || ncol(ret_mat) < 3) {
    return(rep(1 / length(tickers), length(tickers)))
  }

  survived <- colnames(ret_mat)
  dropped  <- setdiff(tickers, survived)
  n <- ncol(ret_mat)
  cov_mat <- .ledoit_wolf_shrink(ret_mat)

  # Solve: min w'Σw  s.t. sum(w)=1, w>=0, w<=max_w
  Dmat <- 2 * cov_mat
  # Make positive definite
  eig <- eigen(Dmat, symmetric = TRUE)
  eig$values <- pmax(eig$values, 1e-8)
  Dmat <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)

  dvec <- rep(0, n)

  # Constraints: sum(w)=1, w>=0, w<=max_w
  # Amat columns: [equality(sum=1), identity(w>=0), -identity(w<=max_w)]
  Amat <- cbind(
    rep(1, n),          # sum = 1
    diag(n),            # w_i >= 0
    -diag(n)            # -w_i >= -max_w
  )
  bvec <- c(1, rep(0, n), rep(-max_w, n))
  meq  <- 1  # first constraint is equality

  res <- tryCatch(
    quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq = meq),
    error = function(e) NULL
  )

  if (is.null(res)) {
    w_sub <- rep(1 / n, n)
  } else {
    w_sub <- pmax(res$solution, 0)
    w_sub <- w_sub / sum(w_sub)
  }
  names(w_sub) <- survived

  # Map back to full tickers: dropped stocks get equal share
  w_full <- rep(0, length(tickers))
  names(w_full) <- tickers
  if (length(dropped) > 0) {
    for (tk in dropped) w_full[tk] <- 1 / length(tickers)
    mv_scale <- 1 - sum(w_full)
    for (tk in survived) w_full[tk] <- w_sub[tk] * mv_scale
  } else {
    w_full[survived] <- w_sub[survived]
  }
  w_full <- w_full / sum(w_full)

  # Cap weights
  if (any(w_full > max_w)) {
    w_full <- pmin(w_full, max_w)
    w_full <- w_full / sum(w_full)
  }
  w_full
}

# Ledoit-Wolf linear shrinkage toward scaled identity
.ledoit_wolf_shrink <- function(X) {
  n <- nrow(X)
  p <- ncol(X)
  S <- cov(X, use = "pairwise.complete.obs")
  S[is.na(S)] <- 0

  mu <- sum(diag(S)) / p
  delta <- S - mu * diag(p)

  # Shrinkage intensity
  sum_sq <- sum(delta^2) / p
  X_centered <- scale(X, center = TRUE, scale = FALSE)
  X_centered[is.na(X_centered)] <- 0

  b_bar <- 0
  for (i in 1:n) {
    xi <- matrix(X_centered[i, ], ncol = 1)
    b_bar <- b_bar + sum((xi %*% t(xi) - S)^2)
  }
  b_bar <- b_bar / (n^2 * p)

  alpha <- min(b_bar / sum_sq, 1)
  alpha * mu * diag(p) + (1 - alpha) * S
}


#==============================================================================
# 3-D. calc_riskparity_weights() — Risk Parity (Equal Risk Contribution)
#==============================================================================

calc_riskparity_weights <- function(tickers, ret_dt, n_days = 120,
                                     max_w = 0.15, max_iter = 100) {
  ret_mat <- .build_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(ret_mat) || ncol(ret_mat) < 3) {
    return(rep(1 / length(tickers), length(tickers)))
  }

  n <- ncol(ret_mat)
  cov_mat <- .ledoit_wolf_shrink(ret_mat)

  # Iterative Cyclical Coordinate Descent for ERC
  w <- rep(1 / n, n)
  for (iter in 1:max_iter) {
    sigma_w <- as.numeric(cov_mat %*% w)
    port_vol <- sqrt(as.numeric(t(w) %*% cov_mat %*% w))
    if (port_vol < 1e-10) break

    # Risk contribution
    rc <- w * sigma_w / port_vol
    target_rc <- port_vol / n

    # Update
    w_new <- w * (target_rc / rc)
    w_new[is.na(w_new) | w_new < 1e-6] <- 1e-6
    w_new <- w_new / sum(w_new)

    if (max(abs(w_new - w)) < 1e-8) break
    w <- w_new
  }

  # Cap weights
  if (any(w > max_w)) {
    w <- pmin(w, max_w)
    w <- w / sum(w)
  }
  w
}


# ─── calc_score_tilt_weights ─────────────────────────────────────────────────
#' HRP-Score Tilt Hybrid Weights
#'
#' Blends HRP weights with score-proportional weights.
#' w = (1-alpha) * hrp_w + alpha * score_proportional
#'
#' @param tickers character vector of selected stock tickers
#' @param scores  named numeric vector (names = tickers, values = factor scores)
#' @param ret_dt  data.table with Date, Ticker, Ret (for HRP computation)
#' @param n_days  lookback for HRP covariance (default 60)
#' @param max_w   maximum single-stock weight (default 0.15)
#' @param alpha   score tilt proportion: 0 = pure HRP, 1 = pure score (default 0.4)
#' @param cov_method  covariance method for HRP ("sample", "ledoit_wolf", "gerber_rmt")
#' @return numeric vector of weights (length = length(tickers), sums to 1)
calc_score_tilt_weights <- function(tickers, scores, ret_dt,
                                     n_days = 60, max_w = 0.15,
                                     alpha = 0.4, cov_method = "gerber_rmt") {
  n <- length(tickers)
  ew_fallback <- rep(1 / n, n)
  if (n < 2L) return(ew_fallback)

  # HRP weights
  hrp_w <- tryCatch(
    calc_hrp_weights(tickers, ret_dt, n_days = n_days, max_w = 1.0,
                     cov_method = cov_method),
    error = function(e) ew_fallback
  )
  if (length(hrp_w) != n) hrp_w <- ew_fallback

  # Score-proportional weights (shift to positive)
  sc <- if (is.null(names(scores))) {
    scores[seq_len(min(n, length(scores)))]
  } else {
    scores[tickers]
  }
  sc[is.na(sc)] <- 0
  sc <- sc - min(sc) + 0.01
  sc_w <- as.numeric(sc / sum(sc))

  # Blend
  w <- (1 - alpha) * as.numeric(hrp_w) + alpha * sc_w

  # Cap and normalize
  w <- pmin(w, max_w)
  w <- w / sum(w)
  w
}


#==============================================================================
# 4. run_monthly_simulation() — Signal → Execution → NAV
#==============================================================================
#
# Arguments:
#   RAWDATA     — data.table from load_rawdata()
#   BM_DT       — benchmark data.table from load_rawdata()
#   FACTORS     — data.table with columns: Date, Ticker, Score
#                 (monthly signal dates, higher Score = better)
#   n_holdings  — max number of holdings (default 20)
#   commission  — round-trip commission rate (default 0.0015)
#   initial_cap — initial capital (default 1e8)
#   weight_method — "equal", "ivol", "hrp", "minvar", "riskparity"
#   buffer_zone — list(keep_n, entry_n) for hysteresis band turnover control
#                 keep_n: retain if rank <= keep_n (default NULL = no buffer)
#                 entry_n: new entry if rank <= entry_n
#                 Ref: Garleanu & Pedersen (2013) JF
#
# NOTE: Rebalancing frequency is determined by FACTORS$Date, NOT by this function.
#   Monthly rebal: FACTORS has month-end dates
#   Weekly rebal: FACTORS has week-end dates
#   Dynamic N: if FACTORS has an 'N' column, n_holdings is overridden per signal date
#
# Returns: list(DAILY_NAV_DT, PORTFOLIO_LOG, HOLDINGS_LOG, strategy_xts, bm_xts)
#==============================================================================

# Alias for backward compatibility
run_monthly_simulation <- function(RAWDATA,
                                    BM_DT,
                                    FACTORS,
                                    n_holdings    = DEFAULT_MAX_HOLDINGS,
                                    commission    = DEFAULT_COMMISSION,
                                    initial_cap   = DEFAULT_INITIAL_CAPITAL,
                                    weight_method = "ivol",
                                    vol_target    = NULL,    # annualized vol target e.g. 0.15
                                    vol_lookback  = 60L,     # days for realized vol est.
                                    dd_brake      = NULL,    # list(entry_pct, exit_pct) e.g. list(0.05, 0.15)
                                    buffer_zone   = NULL,    # list(keep_n, entry_n) for TO control
                                    cov_method    = "sample",  # "sample" | "ledoit_wolf" | "gerber_rmt"
                                    regime_dt     = NULL,    # data.table(Date, MRS, ...) from build_daily_regime()
                                    ic_history    = NULL) {  # numeric vector of past IC values (for V2 ic_tilt)

  cat("[simulation] Starting monthly simulation...\n")

  all_dates    <- sort(unique(RAWDATA$Date))
  signal_dates <- sort(unique(FACTORS$Date))

  # Remove signals with no next month data
  signal_dates <- signal_dates[
    !is.na(sapply(signal_dates, get_execution_date, all_dates))
  ]

  cat(sprintf("  > %d signal dates | %d trading days\n",
              length(signal_dates), length(all_dates)))

  # Storage
  portfolio_log <- list()
  holdings_log  <- list()
  daily_nav     <- list()

  # Initial state
  cash     <- initial_cap
  holdings <- list()
  prev_holdings_set <- list()
  prev_date <- min(all_dates)

  sig_counter <- 0L
  for (sig_date in signal_dates) {
    sig_counter <- sig_counter + 1L
    if (sig_counter %% 5 == 0) gc(verbose = FALSE)
    sig_date  <- as.Date(sig_date)
    exec_date <- get_execution_date(sig_date, all_dates)
    if (is.na(exec_date)) next

    # --- Stock selection by Score (descending) ---
    month_factors <- FACTORS[Date == sig_date & !is.na(Score)]
    setorder(month_factors, -Score)
    month_factors[, rank := .I]

    # Dynamic N: if FACTORS has 'N' column, override n_holdings for this signal
    n_hold_eff <- n_holdings
    if ("N" %in% names(month_factors) && nrow(month_factors) > 0) {
      n_val <- month_factors$N[1]
      if (!is.na(n_val) && n_val > 0) n_hold_eff <- as.integer(n_val)
    }

    if (nrow(month_factors) == 0) {
      # No signal → hold cash
      selected <- character(0)
    } else if (!is.null(buffer_zone)) {
      # === Buffer Zone: Hysteresis band for turnover control ===
      keep_n  <- buffer_zone$keep_n  %||% (n_hold_eff * 2L)
      entry_n <- buffer_zone$entry_n %||% round(n_hold_eff * 0.8)
      current_tickers <- names(holdings)

      if (length(current_tickers) > 0) {
        kept <- month_factors[Ticker %in% current_tickers & rank <= keep_n]$Ticker
      } else {
        kept <- character(0)
      }

      new_candidates <- month_factors[!(Ticker %in% kept) & rank <= entry_n]$Ticker
      n_slots_for_new <- max(0L, n_hold_eff - length(kept))
      selected <- c(kept, head(new_candidates, n_slots_for_new))

      if (length(selected) < n_hold_eff) {
        fill <- month_factors[!(Ticker %in% selected)]$Ticker
        n_fill <- n_hold_eff - length(selected)
        selected <- c(selected, head(fill, n_fill))
      }

      selected <- head(selected, n_hold_eff)
    } else {
      n_hold   <- min(n_hold_eff, nrow(month_factors))
      selected <- month_factors[1:n_hold]$Ticker
    }

    # --- Daily NAV between prev execution and this execution ---
    # .compute_daily_nav(): Rcpp cpp_daily_nav() 우선, R fallback 자동 적용
    exec_dates_range <- all_dates[all_dates > prev_date & all_dates <= exec_date]
    if (length(exec_dates_range) > 0 && length(holdings) > 0) {
      nav_chunk <- .compute_daily_nav(RAWDATA, holdings, exec_dates_range, cash)
      for (ri in seq_len(nrow(nav_chunk))) {
        daily_nav[[length(daily_nav) + 1]] <- nav_chunk[ri]
      }
    }

    # --- Liquidate if no stocks selected ---
    if (length(selected) == 0) {
      for (tk in names(holdings)) {
        price_row <- RAWDATA[Ticker == tk & Date == exec_date, Close]
        if (length(price_row) > 0 && !is.na(price_row[1])) {
          proceeds <- holdings[[tk]]$shares * price_row[1]
          cash     <- cash + proceeds * (1 - commission)
        }
      }
      holdings  <- list()
      prev_date <- exec_date
      portfolio_log[[length(portfolio_log) + 1]] <- data.table(
        Signal_Date = sig_date, Exec_Date = exec_date,
        N_stocks = 0L, NAV = cash
      )
      next
    }

    # --- Get execution prices ---
    exec_prices <- RAWDATA[Ticker %in% selected & Date == exec_date,
                           .(Ticker, Close)]
    exec_prices <- exec_prices[!is.na(Close)]
    if (nrow(exec_prices) == 0) { prev_date <- exec_date; next }

    selected <- exec_prices$Ticker

    # --- Portfolio value before rebalance ---
    total_val <- cash
    for (tk in names(holdings)) {
      price_row <- RAWDATA[Ticker == tk & Date == exec_date, Close]
      if (length(price_row) > 0 && !is.na(price_row[1])) {
        total_val <- total_val + holdings[[tk]]$shares * price_row[1]
      }
    }

    # --- DD Brake: reduce exposure when drawdown exceeds threshold (C9: t-1 lag) ---
    invest_val <- total_val
    if (!is.null(dd_brake) && length(daily_nav) >= 2) {
      peak_nav <- max(sapply(daily_nav, function(x) x$NAV))
      current_nav <- tail(daily_nav, 1)[[1]]$NAV
      dd_pct <- 1 - current_nav / peak_nav  # drawdown as positive fraction
      dd_entry <- dd_brake$entry_pct  # e.g. 0.05
      dd_exit  <- dd_brake$exit_pct   # e.g. 0.15

      if (dd_pct >= dd_exit) {
        invest_val <- 0  # full cash
      } else if (dd_pct >= dd_entry) {
        # Linear scale: entry→exit maps to 1.0→0.0
        exposure <- 1 - (dd_pct - dd_entry) / (dd_exit - dd_entry)
        invest_val <- total_val * max(0, min(1, exposure))
      }
    }

    # --- Vol Targeting: scale equity exposure ---
    if (!is.null(vol_target) && length(daily_nav) >= vol_lookback) {
      recent_nav_dt <- rbindlist(tail(daily_nav, vol_lookback + 1))
      recent_rets   <- diff(log(recent_nav_dt$NAV))
      if (length(recent_rets) >= 10) {
        port_vol_ann <- sd(recent_rets, na.rm = TRUE) * sqrt(252)
        if (!is.na(port_vol_ann) && port_vol_ann > 0.001) {
          exposure   <- min(1.0, vol_target / port_vol_ann)
          invest_val <- total_val * exposure
        }
      }
    }

    # --- Weights ---
    # For advanced methods, only pass recent 150 days of selected tickers
    if (weight_method %in% c("hrp", "minvar", "riskparity")) {
      lookback_dates <- tail(all_dates[all_dates <= exec_date], 150)
      ret_sub <- RAWDATA[Ticker %in% selected & Date %in% lookback_dates,
                         .(Date, Ticker, Ret)]
    } else {
      ret_sub <- RAWDATA[Date <= exec_date]
    }
    if (weight_method == "ivol") {
      w <- calc_ivol_weights(selected, ret_sub)
    } else if (weight_method == "hrp") {
      w <- calc_hrp_weights(selected, ret_sub, cov_method = cov_method)
    } else if (weight_method == "minvar") {
      w <- calc_minvar_weights(selected, ret_sub)
    } else if (weight_method == "riskparity") {
      w <- calc_riskparity_weights(selected, ret_sub)
    } else if (weight_method == "score_tilt") {
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      w <- calc_score_tilt_weights(selected, sc, ret_sub,
                                    cov_method = cov_method)
    } else if (weight_method == "regime_tilt") {
      # V1: Regime-Conditional Alpha — alpha varies by MRS layer (t-1 lagged)
      # PIT: regime_dt[Date == exec_date, MRS] is already t-1 lagged from build_daily_regime()
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      mrs_val <- if (!is.null(regime_dt)) {
        v <- regime_dt[Date == exec_date, MRS]
        if (length(v) > 0 && !is.na(v[1])) v[1] else 0
      } else 0
      w <- calc_regime_tilt_weights(selected, sc, ret_sub,
                                     regime_mrs = mrs_val,
                                     cov_method = cov_method)
    } else if (weight_method == "ic_tilt") {
      # V2: Expanding IC Confidence Alpha — alpha scales with historical IC quality
      # ic_history must be pre-computed before calling run_monthly_simulation
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      # Subset ic_history to signals before current sig_date
      ic_hist_sub <- if (!is.null(ic_history) && !is.null(names(ic_history))) {
        ih_dates <- as.Date(names(ic_history))
        ic_history[ih_dates < sig_date]
      } else ic_history
      w <- calc_ic_tilt_weights(selected, sc, ret_sub,
                                 ic_history = ic_hist_sub,
                                 cov_method = cov_method)
    } else if (weight_method == "rank_tilt") {
      # V3: Rank Percentile Score — uniform spacing, outlier-robust
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      w <- calc_rank_tilt_weights(selected, sc, ret_sub,
                                   cov_method = cov_method)
    } else if (weight_method == "softmax_tilt") {
      # V4: Softmax Temperature Score — tau=1.0 (natural z-score scale)
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      w <- calc_softmax_tilt_weights(selected, sc, ret_sub,
                                      tau = 1.0,
                                      cov_method = cov_method)
    } else if (weight_method == "winsor_tilt") {
      # V9: Winsorized Z-Score — ±2 sigma clipping, gentler than rank
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      w <- calc_winsor_tilt_weights(selected, sc, ret_sub,
                                     winsor_sd = 2.0,
                                     cov_method = cov_method)
    } else if (weight_method == "regime_softmax") {
      # V10: Regime Alpha + Softmax Synthesis — alpha AND tau vary by regime layer
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      mrs_val <- if (!is.null(regime_dt)) {
        v <- regime_dt[Date == exec_date, MRS]
        if (length(v) > 0 && !is.na(v[1])) v[1] else 0
      } else 0
      w <- calc_regime_softmax_weights(selected, sc, ret_sub,
                                        regime_mrs = mrs_val,
                                        cov_method = cov_method)
    } else if (weight_method == "nco_score_tilt") {
      # V8: NCO base + Score Tilt (Lopez de Prado 2020)
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      w <- calc_nco_score_tilt_weights(selected, sc, ret_sub)
    } else if (weight_method == "cvar") {
      w <- calc_cvar_weights(selected, ret_sub)
    } else if (weight_method == "maxdiv") {
      w <- calc_maxdiv_weights(selected, ret_sub)
    } else if (weight_method == "nco") {
      w <- calc_nco_weights(selected, ret_sub)
    } else if (weight_method == "resampled") {
      w <- calc_resampled_weights(selected, ret_sub)
    } else if (weight_method == "robust_mv") {
      w <- calc_robust_mv_weights(selected, ret_sub)
    } else if (weight_method == "factor_rp") {
      w <- calc_factor_rp_weights(selected, ret_sub)
    } else if (weight_method == "entropy") {
      sc <- month_factors[Ticker %in% selected, setNames(Score, Ticker)]
      w <- calc_entropy_weights(selected, sc, ret_sub)
    } else if (weight_method == "kelly") {
      w <- calc_kelly_weights(selected, ret_sub)
    } else if (weight_method == "higher_moment") {
      w <- calc_higher_moment_weights(selected, ret_sub)
    } else if (weight_method == "omega") {
      w <- calc_omega_weights(selected, ret_sub)
    } else {
      w <- rep(1 / length(selected), length(selected))
    }
    # Guard: if advanced weighting returned wrong length, fallback to EW
    if (length(w) != length(selected)) {
      w <- rep(1 / length(selected), length(selected))
    }
    names(w) <- selected

    # --- Allocate ---
    new_holdings <- list()
    total_cost   <- 0
    for (tk in selected) {
      alloc     <- invest_val * w[tk]
      price_now <- exec_prices[Ticker == tk, Close]
      shares    <- floor(alloc / price_now)
      cost      <- shares * price_now * (1 + commission)
      total_cost <- total_cost + cost
      new_holdings[[tk]] <- list(
        shares     = shares,
        last_price = price_now,
        weight     = w[tk]
      )
    }

    cash      <- total_val - total_cost
    holdings  <- new_holdings
    prev_date <- exec_date

    # --- Holdings detail log ---
    holding_rows <- lapply(selected, function(tk) {
      name_val <- RAWDATA[Ticker == tk & Date == exec_date, Name]
      sect_val <- RAWDATA[Ticker == tk & Date == exec_date, Sector]
      score_val <- month_factors[Ticker == tk, Score]
      data.table(
        Signal_Date = sig_date,
        Exec_Date   = exec_date,
        Ticker      = tk,
        Name        = if (length(name_val) > 0) name_val[1] else NA_character_,
        Sector      = if (length(sect_val) > 0) sect_val[1] else NA_character_,
        Weight      = round(w[tk], 4),
        Score       = if (length(score_val) > 0) round(score_val[1], 4) else NA_real_,
        Price       = exec_prices[Ticker == tk, Close]
      )
    })
    holdings_log[[length(holdings_log) + 1]] <- rbindlist(holding_rows)

    # --- Track actual turnover (stocks changed) ---
    prev_tickers <- names(if (exists("prev_holdings_set")) prev_holdings_set else list())
    if (length(prev_tickers) == 0) prev_tickers <- character(0)
    n_sells <- length(setdiff(prev_tickers, selected))
    n_buys  <- length(setdiff(selected, prev_tickers))
    actual_to_pct <- if (length(prev_tickers) > 0) {
      (n_sells + n_buys) / (length(prev_tickers) + length(selected)) * 100
    } else 100

    portfolio_log[[length(portfolio_log) + 1]] <- data.table(
      Signal_Date = sig_date, Exec_Date = exec_date,
      N_stocks = length(selected), NAV = total_val,
      N_sells = n_sells, N_buys = n_buys, Turnover_Pct = round(actual_to_pct, 1)
    )
    prev_holdings_set <- new_holdings
  }

  # --- Final daily NAV after last signal ---
  remaining_dates <- all_dates[all_dates > prev_date]
  if (length(remaining_dates) > 0 && length(holdings) > 0) {
    for (d in remaining_dates) {
      d <- as.Date(d)
      daily_val <- cash
      for (tk in names(holdings)) {
        price_row <- RAWDATA[Ticker == tk & Date == d, Close]
        if (length(price_row) > 0 && !is.na(price_row[1])) {
          daily_val <- daily_val + holdings[[tk]]$shares * price_row[1]
        } else {
          daily_val <- daily_val + holdings[[tk]]$shares * holdings[[tk]]$last_price
        }
      }
      daily_nav[[length(daily_nav) + 1]] <- data.table(Date = d, NAV = daily_val)
    }
  }

  # --- Assemble results ---
  PORTFOLIO_LOG <- rbindlist(portfolio_log)
  HOLDINGS_LOG  <- if (length(holdings_log) > 0) rbindlist(holdings_log, fill = TRUE) else data.table()
  DAILY_NAV_DT  <- rbindlist(daily_nav)
  setorder(DAILY_NAV_DT, Date)

  # Daily returns
  DAILY_NAV_DT[, Strategy_Ret := NAV / shift(NAV) - 1]
  DAILY_NAV_DT <- DAILY_NAV_DT[!is.na(Strategy_Ret)]

  # xts
  strategy_xts <- xts(DAILY_NAV_DT$Strategy_Ret, order.by = DAILY_NAV_DT$Date)
  names(strategy_xts) <- "Strategy"

  # BM returns aligned
  bm_aligned <- BM_DT[Date %in% DAILY_NAV_DT$Date]
  bm_xts <- xts(bm_aligned$BM_Ret, order.by = bm_aligned$Date)
  names(bm_xts) <- "Benchmark"

  cat(sprintf("[simulation] Complete. Period: %s ~ %s | %d rebalances\n",
              min(DAILY_NAV_DT$Date), max(DAILY_NAV_DT$Date),
              nrow(PORTFOLIO_LOG)))

  list(
    DAILY_NAV_DT  = DAILY_NAV_DT,
    PORTFOLIO_LOG = PORTFOLIO_LOG,
    HOLDINGS_LOG  = HOLDINGS_LOG,
    strategy_xts  = strategy_xts,
    bm_xts        = bm_xts
  )
}


#==============================================================================
# 5. summarise_perf() — Performance metrics
#==============================================================================

summarise_perf <- function(ret_xts, label = "Strategy",
                            rf_daily = 0, rf_monthly = 0) {
  r   <- ret_xts[!is.na(ret_xts)]
  n   <- length(r)
  if (n < 10) {
    return(data.table(
      Label = label, CAGR = NA, AnnVol = NA,
      Sharpe = NA, Sharpe_m = NA, Sortino = NA, MDD = NA, Calmar = NA,
      WinRate = NA, WorstMonth = NA, Worst3M = NA,
      ES99_d = NA, ES99_m = NA
    ))
  }
  # CAGR (compound annual growth rate) — 별도 metric, Sharpe 분자 아님
  ann <- (prod(1 + r))^(252 / n) - 1
  # Annualized vol (daily sd × √252)
  vol <- sd(r) * sqrt(252)
  mdd <- maxDrawdown(r)
  cal <- if (mdd > 0) ann / mdd else NA_real_

  # Sharpe (daily, 학술 표준 — Lo 2002 / Bailey-LdP 2014 / 도훈 reference 2026-04-29):
  #   ER_t = R_t - Rf_t
  #   Sharpe = mean(ER) / sd(ER) × sqrt(252)
  # ※ 비표준 hybrid (CAGR / vol) 사용 금지 (도훈 reference 4번 흔한 실수).
  rf_d_vec <- if (length(rf_daily) == 1) rep(rf_daily, n) else rf_daily
  if (length(rf_d_vec) != n) rf_d_vec <- rep(0, n)
  er_d <- as.numeric(r) - rf_d_vec
  sd_er_d <- sd(er_d, na.rm = TRUE)
  sr  <- if (!is.na(sd_er_d) && sd_er_d > 1e-12) {
    mean(er_d, na.rm = TRUE) / sd_er_d * sqrt(252)
  } else NA_real_

  # Sharpe_m: monthly-basis annualized Sharpe (Lawbook v1.4.2 Sharpe0_m_ann)
  monthly_ret <- tryCatch({
    as.numeric(apply.monthly(ret_xts[!is.na(ret_xts)], Return.cumulative))
  }, error = function(e) NULL)

  sharpe_m <- if (!is.null(monthly_ret) && length(monthly_ret) >= 12) {
    rf_m_vec <- if (length(rf_monthly) == 1) rep(rf_monthly, length(monthly_ret)) else rf_monthly
    if (length(rf_m_vec) != length(monthly_ret)) rf_m_vec <- rep(0, length(monthly_ret))
    er_m <- monthly_ret - rf_m_vec
    sd_er_m <- sd(er_m, na.rm = TRUE)
    if (!is.na(sd_er_m) && sd_er_m > 1e-12) {
      mean(er_m, na.rm = TRUE) / sd_er_m * sqrt(12)
    } else NA_real_
  } else {
    NA_real_
  }

  # ES99: Expected Shortfall at 99% confidence (CVaR)
  # Lawbook v1.4.2: ES99 = -E[r | r <= q_0.01] (positive loss magnitude, smaller=better)
  r_num <- as.numeric(r)
  cutoff_d <- quantile(r_num, 0.01, na.rm = TRUE)
  tail_d   <- r_num[r_num <= cutoff_d]
  es99_d   <- if (length(tail_d) > 0) -mean(tail_d) else NA_real_

  es99_m <- if (!is.null(monthly_ret) && length(monthly_ret) >= 24) {
    cutoff_m <- quantile(monthly_ret, 0.01, na.rm = TRUE)
    tail_m   <- monthly_ret[monthly_ret <= cutoff_m]
    if (length(tail_m) > 0) -mean(tail_m) else NA_real_
  } else {
    NA_real_
  }

  # Sortino: annualized return / downside deviation (MAR=0)
  # Lawbook v1.4.2 Ch.05: Sortino = CAGR / DD, DD = sqrt(mean(min(r,0)^2)) * sqrt(252)
  downside_dev <- sqrt(mean(pmin(r_num, 0)^2)) * sqrt(252)
  sortino <- if (downside_dev > 1e-8) as.numeric(ann) / downside_dev else NA_real_

  # WinRate: percentage of positive months
  win_rate <- if (!is.null(monthly_ret) && length(monthly_ret) >= 6) {
    mean(monthly_ret > 0) * 100
  } else { NA_real_ }

  # WorstMonth / Worst3M: tail risk measures
  worst_month <- if (!is.null(monthly_ret) && length(monthly_ret) >= 6) {
    min(monthly_ret) * 100
  } else { NA_real_ }

  worst_3m <- if (!is.null(monthly_ret) && length(monthly_ret) >= 6) {
    roll3 <- zoo::rollapply(monthly_ret, width = 3, FUN = function(x) prod(1+x)-1,
                            fill = NA, align = "right")
    min(roll3, na.rm = TRUE) * 100
  } else { NA_real_ }

  data.table(
    Label    = label,
    CAGR     = round(as.numeric(ann) * 100, 2),
    AnnVol   = round(as.numeric(vol) * 100, 2),
    Sharpe   = round(as.numeric(sr), 3),
    Sharpe_m = round(as.numeric(sharpe_m), 3),
    Sortino  = round(as.numeric(sortino), 3),
    MDD      = round(as.numeric(mdd) * 100, 2),
    Calmar   = round(as.numeric(cal), 3),
    WinRate  = round(as.numeric(win_rate), 1),
    WorstMonth = round(as.numeric(worst_month), 2),
    Worst3M  = round(as.numeric(worst_3m), 2),
    ES99_d   = round(as.numeric(es99_d) * 100, 2),
    ES99_m   = round(as.numeric(es99_m) * 100, 2)
  )
}


#==============================================================================
# 6. calc_turnover() — Annualized turnover from portfolio log
#==============================================================================

calc_turnover <- function(PORTFOLIO_LOG, DAILY_NAV_DT) {
  if (nrow(PORTFOLIO_LOG) < 2) return(0)
  n_years <- as.numeric(difftime(
    max(DAILY_NAV_DT$Date), min(DAILY_NAV_DT$Date), units = "days"
  )) / 365.25
  if (n_years <= 0) return(0)

  # Use actual turnover if tracked, else fall back to rebalance count
  if ("Turnover_Pct" %in% names(PORTFOLIO_LOG)) {
    # Sum actual turnover percentages, annualize
    total_to <- sum(PORTFOLIO_LOG$Turnover_Pct, na.rm = TRUE)
    ann_turnover <- total_to / n_years
  } else {
    n_rebal <- nrow(PORTFOLIO_LOG)
    ann_turnover <- (n_rebal / n_years) * 100
  }
  round(ann_turnover, 1)
}


#==============================================================================
# 7. generate_charts() — Equity curve + Annual bar chart
#==============================================================================

generate_charts <- function(sim_result, output_dir = NULL, strategy_name = "Strategy") {

  merged <- merge(sim_result$strategy_xts, sim_result$bm_xts, join = "inner")

  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  }

  # --- 7a. Performance Summary (PerformanceAnalytics) ---
  if (!is.null(output_dir)) {
    png(file.path(output_dir, "equity_curve.png"),
        width = 1200, height = 800, res = 120)
  }
  # 색상 팔레트 — 전략: 강한 파란/보라, 벤치마크: 투명한 회색
  .COL_STRAT <- "#1A6FE3"   # 쨍한 코발트 블루
  .COL_BM    <- "#B0B8C1"   # 옅은 슬레이트 그레이
  .COL_DD    <- "#E84545"   # 드로우다운: 강한 레드

  charts.PerformanceSummary(
    merged,
    main     = paste(strategy_name, "vs KOSPI200"),
    colorset = c(.COL_STRAT, .COL_BM),
    lwd      = c(2.5, 1.2),
    legend.loc = "topleft"
  )
  if (!is.null(output_dir)) dev.off()

  # --- 7b. Annual bar chart ---
  ann_strat <- apply.yearly(merged[, 1], Return.cumulative)
  ann_bm    <- apply.yearly(merged[, 2], Return.cumulative)
  ann_merged <- merge(ann_strat, ann_bm, join = "inner")

  df_ann <- data.frame(
    Year      = format(index(ann_merged), "%Y"),
    Strategy  = as.numeric(coredata(ann_merged[, 1])) * 100,
    Benchmark = as.numeric(coredata(ann_merged[, 2])) * 100
  )
  df_long <- pivot_longer(df_ann, -Year, names_to = "Label", values_to = "Return")

  p <- ggplot(df_long, aes(x = Year, y = Return, fill = Label)) +
    geom_col(position = "dodge", width = 0.7) +
    scale_fill_manual(values = c("Strategy" = .COL_STRAT, "Benchmark" = .COL_BM)) +
    scale_y_continuous(labels = function(x) paste0(x, "%")) +
    geom_hline(yintercept = 0, linewidth = 0.4, colour = "grey40") +
    geom_text(aes(label = paste0(round(Return, 1), "%"),
                  vjust = ifelse(Return >= 0, -0.35, 1.25)),
              position = position_dodge(0.7), size = 2.8, fontface = "bold",
              colour = "grey20") +
    labs(title  = paste(strategy_name, "— Annual Returns"),
         x = NULL, y = "Return (%)") +
    theme_minimal(base_size = 12) +
    theme(
      plot.title       = element_text(face = "bold", size = 13, hjust = 0),
      axis.text.x      = element_text(angle = 45, hjust = 1, size = 9),
      panel.grid.major = element_line(colour = "grey90"),
      panel.grid.minor = element_blank(),
      legend.position  = "top",
      legend.title     = element_blank()
    )

  if (!is.null(output_dir)) {
    ggsave(file.path(output_dir, "annual_returns.png"), p,
           width = 11, height = 6, dpi = 150)
  }
  print(p)

  # --- 7c. Drawdown chart ---
  if (!is.null(output_dir)) {
    png(file.path(output_dir, "drawdown.png"),
        width = 1200, height = 400, res = 120)
  }
  chart.Drawdown(merged,
                 main = paste(strategy_name, "- Drawdown"),
                 colorset = c(.COL_DD, .COL_BM),
                 lwd = c(2, 1),
                 legend.loc = "bottomright")
  if (!is.null(output_dir)) dev.off()

  cat("[charts] Generated.\n")
  invisible(NULL)
}


#==============================================================================
# 8. stress_test() — Stress period analysis
#==============================================================================

stress_test <- function(strategy_xts, bm_xts) {
  merged <- merge(strategy_xts, bm_xts, join = "inner")

  stress_periods <- list(
    list(label = "2008 GFC",      start = "2007-10-01", end = "2009-03-31"),
    list(label = "2020 COVID",    start = "2020-01-01", end = "2020-06-30"),
    list(label = "2022 Rate Hike", start = "2022-01-01", end = "2022-12-31")
  )

  rbindlist(lapply(stress_periods, function(sp) {
    sub <- merged[paste0(sp$start, "/", sp$end)]
    if (nrow(sub) < 5) return(NULL)
    rbind(
      summarise_perf(sub[, 1], paste0("Strategy | ", sp$label)),
      summarise_perf(sub[, 2], paste0("BM       | ", sp$label))
    )
  }))
}
