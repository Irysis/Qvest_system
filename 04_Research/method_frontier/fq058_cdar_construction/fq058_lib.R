# =============================================================================
# FQ-058 shared library — drawdown-aware construction A/B
#   metric_type = canonical_screen (screen_diagnostic). Return.portfolio only.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
  library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)
ROOT_F58 <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT_F58  <- file.path(ROOT_F58, "stage_artifacts/method_frontier")
PIN_F58  <- "fq057_20260718_171024"
ROUND_TAG_F58 <- "fq058_20260718_191740"

# ---- ym helpers -------------------------------------------------------------
ym_next_f <- function(y) { yy <- y %/% 100L; mm <- y %% 100L; if (mm == 12L) (yy + 1L) * 100L + 1L else y + 1L }
ym2date_f <- function(ym) {
  y <- ym %/% 100L; m <- ym %% 100L
  nx <- ifelse(m == 12L, (y + 1L) * 10000L + 101L, y * 10000L + (m + 1L) * 100L + 1L)
  as.Date(as.character(nx), format = "%Y%m%d") - 1L
}

# ---- panel loader -----------------------------------------------------------
load_panels_f58 <- function() {
  mr   <- as.data.table(read_parquet(file.path(OUT_F58, "fq057_monthly_returns.parquet")))
  snap <- as.data.table(read_parquet(file.path(OUT_F58, "fq057_monthly_snapshot.parquet")))
  liq  <- as.data.table(read_parquet(file.path(OUT_F58, "np4_liq_snapshot.parquet")))
  Mw   <- dcast(mr, ym ~ Ticker, value.var = "ret_m")
  yms  <- Mw$ym
  mat  <- as.matrix(Mw[, -1, drop = FALSE]); rownames(mat) <- as.character(yms)
  # ym 연속성 검증
  for (i in seq_len(length(yms) - 1L)) stopifnot(yms[i + 1L] == ym_next_f(yms[i]))
  list(mr = mr, snap = snap, liq = liq, mat = mat, yms = yms)
}

# ---- eligible universe at month t (PIT) -------------------------------------
elig_at_f <- function(P, t_ym, win = 60L, liq_min = 2e8) {
  idx <- match(t_ym, P$yms); if (is.na(idx) || idx < win) return(character(0))
  members <- P$snap[ym == t_ym & member == 1L, Ticker]
  liq_ok  <- P$liq[ym == t_ym & !is.na(avgtv20) & avgtv20 >= liq_min, Ticker]
  cand <- intersect(intersect(members, liq_ok), colnames(P$mat))
  if (length(cand) < 30L) return(character(0))
  sub <- P$mat[(idx - win + 1L):idx, cand, drop = FALSE]
  cand[colSums(!is.na(sub)) == win]
}

# ---- candidate factor signals (PIT, z-score over elig) ----------------------
#   신호는 month-end t 시점 정보만. holding month t+1.
signal_f58 <- function(P, t_ym, elig, factor) {
  idx <- match(t_ym, P$yms)
  z_of <- function(v) { v <- as.numeric(v); s <- sd(v, na.rm = TRUE); if (!is.finite(s) || s < 1e-12) return(rep(0, length(v))); (v - mean(v, na.rm = TRUE)) / s }
  if (factor == "mom_12_1") {
    rows <- (idx - 11L):(idx - 1L)                       # t-11..t-1 skip t
    val <- expm1(colSums(log1p(P$mat[rows, elig, drop = FALSE])))
  } else if (factor == "mom_6_1") {
    rows <- (idx - 6L):(idx - 1L)
    val <- expm1(colSums(log1p(P$mat[rows, elig, drop = FALSE])))
  } else if (factor == "low_vol") {
    rows <- (idx - 11L):idx                              # 12m incl t (known @ end t)
    val <- -apply(P$mat[rows, elig, drop = FALSE], 2, sd)  # 저변동성 = 高 신호
  } else if (factor == "reversal_1m") {
    val <- -P$mat[idx, elig]                              # -ret_t (단기 반전)
  } else if (factor == "small_size") {
    sz <- P$snap[ym == t_ym & Ticker %in% elig, .(Ticker, size)]
    v <- setNames(sz$size, sz$Ticker)[elig]
    val <- -log(pmax(as.numeric(v), 1))                  # 소형주 = 高 신호
  } else stop("unknown factor")
  z <- z_of(val); names(z) <- elig; z
}

# ---- metric helpers ---------------------------------------------------------
nw_t_f <- function(x, lag = 3L) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (length(x) < 10L) return(list(mean_m = mean(x), t = NA_real_, n = length(x)))
  fit <- lm(x ~ 1)
  ct <- lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))
  list(mean_m = unname(ct[1, 1]), t = unname(ct[1, 3]), n = length(x))
}
ann_sr_f  <- function(x) { x <- as.numeric(x); m <- mean(x); s <- sd(x); if (!is.finite(s) || s < 1e-12) return(NA_real_); m / s * sqrt(12) }
oos_v2_f  <- function(x, splits = c(0.55, 0.65, 0.75)) {
  x <- as.numeric(x); N <- length(x)
  rr <- sapply(splits, function(f) {
    n1 <- floor(f * N); if (n1 < 6 || (N - n1) < 6) return(NA_real_)
    s_is <- ann_sr_f(x[1:n1]); s_oos <- ann_sr_f(x[(n1 + 1):N])
    if (!is.finite(s_is) || abs(s_is) < 1e-9) return(NA_real_); s_oos / s_is
  })
  list(splits = as.list(setNames(round(rr, 4), paste0("f", splits * 100))), median = median(rr, na.rm = TRUE))
}
psr_f <- function(x, sr0 = 0) {
  x <- as.numeric(x); n <- length(x); sr <- mean(x) / sd(x)
  g3 <- PerformanceAnalytics::skewness(x, method = "moment")
  g4 <- PerformanceAnalytics::kurtosis(x, method = "moment")
  pnorm(((sr - sr0) * sqrt(n - 1)) / sqrt(1 - g3 * sr + (g4 - 1) / 4 * sr^2))
}

# ---- structural drawdown 지표 (PerformanceAnalytics 표준함수만) --------------
#   net 수익 시계열(xts, month-end)로 계산. 게이트 06-13 정의 정합.
structural_dd_f <- function(net_xts) {
  mdd <- as.numeric(maxDrawdown(net_xts))
  # findDrawdowns: 각 drawdown 에피소드 (from,to,depth,length,recovery)
  dd_series <- PerformanceAnalytics::Drawdowns(net_xts)
  fd <- tryCatch(PerformanceAnalytics::findDrawdowns(net_xts), error = function(e) NULL)
  ep_depth <- if (!is.null(fd) && !is.null(fd$return)) abs(fd$return) else numeric(0)
  ep_len   <- if (!is.null(fd) && !is.null(fd$length)) fd$length else numeric(0)
  n_ep_45 <- sum(ep_depth >= 0.45)
  n_ep_30 <- sum(ep_depth >= 0.30)
  occ_underwater <- mean(as.numeric(dd_series) < -1e-8)          # drawdown 점유율(수중 비율)
  longest_underwater_m <- if (length(ep_len)) max(ep_len) else 0 # 최장 수중(월 단위)
  list(mdd = round(mdd, 4),
       n_episodes_45 = as.integer(n_ep_45),
       n_episodes_30 = as.integer(n_ep_30),
       drawdown_occupancy = round(occ_underwater, 4),
       longest_underwater_months = as.integer(longest_underwater_m),
       n_episodes_total = length(ep_depth))
}

cat("[fq058_lib] loaded — panels/elig/signal/metrics/structural_dd\n")
