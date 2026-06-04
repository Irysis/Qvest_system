#==============================================================================
# factor_portfolios.R — KR FF3 / FF5 / Carhart-4F 팩터 회귀 (재작성 2026-06-04)
#
# 배경: 본 파일이 git/OneDrive/WSL 어디에도 없어(미백업 소실) strategy_analyzer.R의
#   Multi-Factor Regression이 "N/A"로 죽어 있었음. KR 팩터 수익률 캐시
#   (.cache/kr_factor_returns_v2.parquet: MKT/SMB/HML/WML/RMW/CMA/RF, 월간)는 존재하므로
#   load + regression 함수만 재작성. 캐시 재빌드는 외부 스크립트 영역(여기선 stub).
#
# strategy_analyzer.R 인터페이스 (source(.., local=TRUE)):
#   KR_FACTOR_CACHE / load_kr_factor_returns()
#   run_multifactor_regression(strat_xts, bm_xts, factor_dt)
#     → named list(FF3, Carhart4, FF5), 각 list(model, alpha, alpha_tstat,
#       alpha_pval, adj_r2, n_obs). names()[1]=FF3 = report Best.
# PIT: 캐시는 월간 실현 팩터(과거). alpha=월간 절편. 자체합성 금지 → apply.monthly + Return.cumulative.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo); library(PerformanceAnalytics)
})

KR_FACTOR_CACHE <- local({
  .cd <- if (exists("CACHE_DIR")) CACHE_DIR else file.path(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), ".cache")
  .v2 <- file.path(.cd, "kr_factor_returns_v2.parquet")  # MKT/SMB/HML/WML/RMW/CMA/RF (FF5+Carhart 완비)
  if (file.exists(.v2)) .v2 else file.path(.cd, "kr_factor_returns.parquet")
})

#' KR FF/Carhart 팩터 월간 수익률 로드 (캐시).
load_kr_factor_returns <- function() {
  dt <- as.data.table(read_parquet(KR_FACTOR_CACHE))
  dt[, Date := as.Date(Date)]
  setorder(dt, Date)
  dt[]
}

#' 전략 초과수익(strat-RF)을 FF3 / Carhart4 / FF5에 회귀 → 모델별 alpha + t-stat.
#' @param strat_xts 전략 수익률 xts (일간 또는 월간). @param bm_xts (미사용, 호환).
#' @param factor_dt load_kr_factor_returns() 결과 (NULL이면 자동 로드).
# Newey-West HAC 공분산 (Bartlett kernel, lag = floor(T^(1/3)) — strategy_analyzer FMB와 일관).
# MF 알파 t를 OLS→NW로 통일: 시계열 회귀 잔차의 자기상관/이분산 보정. 2026-06-05 도훈.
.nw_hac_vcov <- function(fit, L = NULL) {
  X <- stats::model.matrix(fit)
  u <- as.numeric(stats::residuals(fit))
  n <- nrow(X)
  if (is.null(L)) L <- max(1L, floor(n^(1/3)))
  bread <- solve(crossprod(X))                 # (X'X)^-1
  Xu    <- X * u
  meat  <- crossprod(Xu)                        # gamma_0 = sum u_t^2 x_t x_t'
  for (l in seq_len(L)) {
    w <- 1 - l / (L + 1)                         # Bartlett weight
    G <- crossprod(Xu[(l + 1):n, , drop = FALSE], Xu[1:(n - l), , drop = FALSE])
    meat <- meat + w * (G + t(G))
  }
  bread %*% meat %*% bread
}

run_multifactor_regression <- function(strat_xts, bm_xts = NULL, factor_dt = NULL) {
  if (is.null(strat_xts)) return(NULL)
  if (is.null(factor_dt)) factor_dt <- tryCatch(load_kr_factor_returns(), error = function(e) NULL)
  if (is.null(factor_dt) || nrow(factor_dt) == 0L) return(NULL)

  # 1) 전략 월간 수익률 (PerformanceAnalytics 표준 — prod/cumprod 자체합성 금지)
  x  <- tryCatch(strat_xts[, 1], error = function(e) strat_xts)
  sm <- tryCatch(apply.monthly(x, Return.cumulative), error = function(e) NULL)
  if (is.null(sm) || nrow(sm) == 0L) return(NULL)
  sdt <- data.table(Date = as.Date(zoo::index(sm)), StratRet = as.numeric(sm[, 1]))
  sdt[, ym := format(Date, "%Y-%m")]

  # 2) 팩터와 year-month 키로 정렬 (월말 일자 차이 흡수)
  fdt <- copy(factor_dt); fdt[, ym := format(Date, "%Y-%m")]
  reg <- merge(sdt[, .(ym, StratRet)], fdt, by = "ym")
  reg <- reg[is.finite(StratRet) & is.finite(MKT) & is.finite(RF)]
  if (nrow(reg) < 24L) return(NULL)              # 최소 24개월
  reg[, Excess := StratRet - RF]

  models <- list(
    FF3      = "MKT + SMB + HML",
    Carhart4 = "MKT + SMB + HML + WML",          # WML = 모멘텀(UMD)
    FF5      = "MKT + SMB + HML + RMW + CMA"
  )
  out <- list()
  for (nm in names(models)) {
    vars <- strsplit(gsub(" ", "", models[[nm]]), "\\+", perl = TRUE)[[1]]
    sub  <- reg[stats::complete.cases(reg[, c("Excess", vars), with = FALSE])]
    if (nrow(sub) < 24L) next
    fit <- tryCatch(lm(as.formula(paste("Excess ~", models[[nm]])), data = sub),
                    error = function(e) NULL)
    if (is.null(fit)) next
    cs <- summary(fit)$coefficients
    if (!"(Intercept)" %in% rownames(cs)) next
    a <- cs["(Intercept)", ]
    # 알파 t: OLS → Newey-West HAC (시계열 잔차 자기상관/이분산 보정; FMB NW와 일관). 실패 시 OLS fallback.
    nw_t <- tryCatch({
      V <- .nw_hac_vcov(fit)
      unname(a[1]) / sqrt(V["(Intercept)", "(Intercept)"])
    }, error = function(e) unname(a[3]))
    df_resid <- max(1L, nobs(fit) - length(stats::coef(fit)))
    out[[nm]] <- list(
      model           = nm,
      alpha           = unname(a[1]),            # 월간 alpha
      alpha_tstat     = nw_t,                    # Newey-West HAC (was OLS a[3])
      alpha_tstat_ols = unname(a[3]),            # 참고용 OLS 보존
      alpha_pval      = 2 * stats::pt(-abs(nw_t), df = df_resid),  # NW t 기반 양측 p
      adj_r2          = summary(fit)$adj.r.squared,
      n_obs           = nobs(fit)
    )
  }
  if (length(out) == 0L) return(NULL)
  out
}

#' KR 팩터 캐시 재빌드 — 캐시가 이미 존재하므로 stub (재빌드는 외부 스크립트).
build_kr_factor_returns <- function(...) {
  cat("[factor_portfolios] KR factor 캐시 존재(재빌드 불요):", KR_FACTOR_CACHE, "\n")
  invisible(KR_FACTOR_CACHE)
}

cat(sprintf("[factor_portfolios] Loaded (재작성 2026-06-04). 캐시: %s\n", basename(KR_FACTOR_CACHE)))
cat("[factor_portfolios] Functions: load_kr_factor_returns() / run_multifactor_regression() [FF3/Carhart4/FF5]\n")
