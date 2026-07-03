## pure_factor_extraction.R — RAMP Gate 4 (2차): factor-DB 신호 FWL 직교화 → 순수팩터
## 룰 §4 §3.4 (alpha-research). z_pure = z − X(X'X)^{-1}X'z, X=[sector dummies, log_mktcap, beta, vol, liquidity].
## ★직교성 assert |cor(z_pure, X열)| < 0.05 (FWL 작동 증거). 미달 시 status=fwl_residual_corr_fail.
## PIT: signal은 load_month_factors(sig_date) PIT-safe(C13/14/15). X 컨트롤은 t 시점 rawdata as-of.
##
## 순수팩터 = overlay(국면필터/vol-target/손절/추세/현금/임의리밸/유니버스편향) 제거된 raw cross-sectional signal.

suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/ramp_io.R")
# config.R 먼저 (CACHE_DIR 정의 — 미정의 시 connector가 잘못된 상대경로 'scripts/config.R' 탐색)
if (!exists("CACHE_DIR")) source("02_Infrastructure/config.R")
if (!exists("load_month_factors")) source("02_Infrastructure/factor_db/factor_db_connector.R")

#==============================================================================
# 1. FWL 컨트롤 행렬 X 구성 (월별 cross-section)
#    sector dummies + log_mktcap + beta(252d) + vol(252d) + liquidity(log 20d ADV)
#==============================================================================
#' @param rawdata data.table(Date, Ticker, Sector, Size, Close, Ret, Vol, K200, KQ150, ...)
#' @param sig_date 신호일 (월말)
#' @param beta_window, vol_window 일수
#' @return data.table(Ticker, <X columns>) — sig_date as-of cross-section
build_fwl_controls <- function(rawdata, sig_date, bench_col = "BM_Ret",
                               beta_window = 252L, vol_window = 252L, adv_window = 20L) {
  sig_d <- as.Date(sig_date)
  # universe as-of: KOSPI200 ∪ KOSDAQ150 (sig_date 기준 멤버십)
  asof <- rawdata[Date <= sig_d]
  if (nrow(asof) == 0) return(data.table())
  # 최근 거래일 cross-section
  last_d <- max(asof$Date)
  xs <- asof[Date == last_d & (K200 == TRUE | KQ150 == TRUE),
             .(Ticker, Sector, Size)]
  xs <- xs[!is.na(Size) & Size > 0]
  if (nrow(xs) == 0) return(data.table())

  # log mktcap
  xs[, log_mktcap := log(Size)]

  # rolling window returns for beta / vol / liquidity
  win_start <- last_d - 400  # ~252 trading days buffer
  hist <- asof[Date > win_start & Ticker %in% xs$Ticker,
               .(Date, Ticker, Ret, Vol, Close, BM = get(bench_col))]
  setorder(hist, Ticker, Date)

  # beta & vol (252d)
  bv <- hist[, {
    r <- tail(Ret, beta_window); b <- tail(BM, beta_window)
    ok <- !is.na(r) & !is.na(b)
    beta <- if (sum(ok) > 60 && stats::var(b[ok]) > 0) stats::cov(r[ok], b[ok]) / stats::var(b[ok]) else NA_real_
    vol <- if (sum(!is.na(r)) > 60) stats::sd(r, na.rm = TRUE) else NA_real_
    # liquidity = log mean 20d 거래대금 (Vol * Close 근사; Vol=거래량)
    advv <- tail(Vol * Close, adv_window)
    liq <- if (sum(!is.na(advv)) > 5) log(mean(advv, na.rm = TRUE) + 1) else NA_real_
    .(beta = beta, vol = vol, liquidity = liq)
  }, by = Ticker]

  X <- merge(xs, bv, by = "Ticker", all.x = TRUE)
  X[, sig_date := sig_d]
  X
}

#==============================================================================
# 2. FWL 직교화: z_pure = z − X(X'X)^{-1}X'z
#==============================================================================
#' @param z named numeric vector (signal, Ticker-indexed)
#' @param Xdf data.table(Ticker, Sector, log_mktcap, beta, vol, liquidity)
#' @return list(z_pure(named vec), orth_cor(named: max|cor| with each X col), ok)
fwl_orthogonalize <- function(z, Xdf) {
  common <- intersect(names(z), Xdf$Ticker)
  if (length(common) < 30) return(list(status = "too_few_common", n = length(common)))
  zc <- z[common]
  X <- Xdf[match(common, Ticker)]
  # design matrix: sector dummies + numeric controls
  X[, Sector := ifelse(is.na(Sector), "UNK", Sector)]
  num_ctrl <- c("log_mktcap", "beta", "vol", "liquidity")
  # 결측 컨트롤은 컬럼 중앙값 대치 (직교화 안정)
  for (cc in num_ctrl) { v <- X[[cc]]; X[[cc]] <- ifelse(is.na(v), median(v, na.rm = TRUE), v) }
  # 신호도 결측 제거
  keep <- !is.na(zc) & is.finite(zc)
  zc <- zc[keep]; X <- X[keep]
  if (length(zc) < 30) return(list(status = "too_few_after_na", n = length(zc)))

  # [2026-06-18 robust] degenerate cross-section 대응 (희소 팩터: 1-sector / 상수 control →
  #   model.matrix contrasts 에러 방지). 유효 term만 동적 formula 구성.
  terms <- character(0)
  if (length(unique(X$Sector)) >= 2L) terms <- c(terms, "Sector")
  for (cc in num_ctrl) if (!is.na(stats::sd(X[[cc]])) && stats::sd(X[[cc]]) > 1e-12) terms <- c(terms, cc)
  if (length(terms) == 0L) return(list(status = "degenerate_controls", n = length(zc)))
  fml <- stats::as.formula(paste("~", paste(terms, collapse = " + ")))
  mm <- tryCatch(model.matrix(fml, data = X), error = function(e) NULL)
  if (is.null(mm)) return(list(status = "model_matrix_fail", n = length(zc)))
  # FWL residual via lm.fit (X(X'X)^{-1}X'z)
  fit <- tryCatch(stats::lm.fit(mm, zc), error = function(e) NULL)
  if (is.null(fit)) return(list(status = "lm_fail"))
  z_pure <- fit$residuals
  names(z_pure) <- X$Ticker

  # 직교성: |cor(z_pure, 각 numeric X열)| < 0.05
  orth_cor <- sapply(num_ctrl, function(cc) {
    v <- X[[cc]]; sv <- stats::sd(v); sz <- stats::sd(z_pure)
    if (is.na(sv) || is.na(sz) || sv < 1e-12 || sz < 1e-12) return(NA_real_)  # [2026-06-18] 전체-NA control NA-가드
    abs(stats::cor(z_pure, v))
  })
  # sector(범주형) 직교성: residual ~ sector ANOVA R^2
  sec_r2 <- tryCatch({
    af <- stats::lm(z_pure ~ X$Sector)
    summary(af)$r.squared
  }, error = function(e) NA_real_)

  list(
    status = "ok",
    z_pure = z_pure,
    n = length(z_pure),
    orth_cor = orth_cor,
    max_orth_cor = max(orth_cor, na.rm = TRUE),
    sector_residual_r2 = sec_r2,
    orthogonality_pass = (max(orth_cor, na.rm = TRUE) < 0.05) && (is.na(sec_r2) || sec_r2 < 0.05)
  )
}

#==============================================================================
# 3. 월별 순수팩터 점수 산출 (factor_id × Date × Ticker → neutralized_z)
#==============================================================================
#' @param factor_names character — load_month_factors 로 부를 신호명
#' @param sig_dates Date vector (월말)
#' @param rawdata data.table
#' @return list(scores=data.table(§5.7 schema), orth_summary=data.table per factor×date)
extract_pure_factor <- function(factor_names, sig_dates, rawdata, verbose = TRUE) {
  scores <- list(); orth <- list()
  for (sd in as.character(sig_dates)) {
    sig_d <- as.Date(sd)
    Xdf <- tryCatch(build_fwl_controls(rawdata, sig_d), error = function(e) data.table())  # [2026-06-18] 방어
    if (nrow(Xdf) == 0) next
    fdb <- tryCatch(load_month_factors(sig_d, factor_names = factor_names),
                    error = function(e) NULL)
    if (is.null(fdb) || nrow(fdb) == 0) next
    for (fn in unique(fdb$Factor_Name)) {
      sub <- fdb[Factor_Name == fn]
      z <- setNames(sub$Z_Score_Aligned, sub$Ticker)
      res <- tryCatch(fwl_orthogonalize(z, Xdf),  # [2026-06-18] 단일 팩터-월 실패가 전체 sweep 죽이지 않게
                      error = function(e) list(status = paste0("error:", substr(conditionMessage(e), 1, 40))))
      if (!identical(res$status, "ok")) {
        orth[[length(orth) + 1L]] <- data.table(factor_id = fn, sig_date = sig_d,
                                                 status = res$status, max_orth_cor = NA_real_,
                                                 orthogonality_pass = NA)
        next
      }
      # §5.7 schema
      tk <- names(res$z_pure)
      raw_z <- z[tk]
      scores[[length(scores) + 1L]] <- data.table(
        signal_date = sig_d,
        data_available_date = sig_d,    # load_month_factors는 PIT-safe(available<=sig)
        rebalance_date = sig_d,
        security_id = tk,               # = Ticker
        factor_id = fn,
        raw = as.numeric(raw_z),
        winsorized = as.numeric(pmax(pmin(raw_z, 3), -3)),
        z = as.numeric(raw_z),          # 이미 Z_Score_Aligned
        neutralized_z = as.numeric(res$z_pure),
        rank = frank(res$z_pure, ties.method = "average"),
        source_strategy_id = paste0("factor_db:", fn)
      )
      orth[[length(orth) + 1L]] <- data.table(
        factor_id = fn, sig_date = sig_d, status = "ok",
        n = res$n, max_orth_cor = res$max_orth_cor,
        sector_residual_r2 = res$sector_residual_r2,
        orthogonality_pass = res$orthogonality_pass
      )
    }
    if (verbose) cat(sprintf("[pure_factor] %s: %d factors orthogonalized\n", sd,
                             length(unique(fdb$Factor_Name))))
  }
  list(
    scores = if (length(scores)) rbindlist(scores, fill = TRUE) else data.table(),
    orth_summary = if (length(orth)) rbindlist(orth, fill = TRUE) else data.table()
  )
}

cat("[pure_factor_extraction.R] Loaded — build_fwl_controls / fwl_orthogonalize / extract_pure_factor (FWL z_pure)\n")
