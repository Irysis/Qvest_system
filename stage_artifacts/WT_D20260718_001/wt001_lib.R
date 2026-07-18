# =============================================================================
# WT-D20260718_001 shared library — Crash-aware momentum selection (alpha stage)
#   FQ-058 P3 승격. pin = fq057_20260718_171024 (RAWDATA/benchmark) + fq057 패널 상속.
#   측정 = canonical_screen_bt() 계약 경유(metric_type="canonical_screen"). proxy 손계산 금지.
#   역할 경계: α̂ 신호/선별만. 공분산·target weights 절대 금지.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
  library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)

ROOT_WT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
MF_DIR  <- file.path(ROOT_WT, "stage_artifacts/method_frontier")
OUT_WT  <- file.path(ROOT_WT, "stage_artifacts/WT_D20260718_001")
PIN_WT  <- "fq057_20260718_171024"
WT_ID   <- "WT-D20260718_001"

dir.create(OUT_WT, showWarnings = FALSE, recursive = TRUE)

# canonical contract (build_benchmark_compare + NW t 포함)
source(file.path(ROOT_WT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

# ---- ym helpers -------------------------------------------------------------
ym_next_w <- function(y) { yy <- y %/% 100L; mm <- y %% 100L; if (mm == 12L) (yy + 1L) * 100L + 1L else y + 1L }
ym_seq_w <- function(from, to) { out <- integer(0); y <- from; while (y <= to) { out <- c(out, y); y <- ym_next_w(y) }; out }
ym2date_w <- function(ym) {
  y <- ym %/% 100L; m <- ym %% 100L
  nx <- ifelse(m == 12L, (y + 1L) * 10000L + 101L, y * 10000L + (m + 1L) * 100L + 1L)
  as.Date(as.character(nx), format = "%Y%m%d") - 1L
}
ym_shift_w <- function(ym, k) {  # k개월 뒤로(-)/앞으로(+)
  y <- ym %/% 100L; m <- ym %% 100L
  tot <- y * 12L + (m - 1L) + k
  (tot %/% 12L) * 100L + (tot %% 12L) + 1L
}

# ---- panel loader (fq057 pinned artifacts 상속) ------------------------------
load_panels_wt <- function() {
  mr   <- as.data.table(read_parquet(file.path(MF_DIR, "fq057_monthly_returns.parquet")))
  snap <- as.data.table(read_parquet(file.path(MF_DIR, "fq057_monthly_snapshot.parquet")))
  liq  <- as.data.table(read_parquet(file.path(MF_DIR, "np4_liq_snapshot.parquet")))
  Mw   <- dcast(mr, ym ~ Ticker, value.var = "ret_m")
  yms  <- Mw$ym
  for (i in seq_len(length(yms) - 1L)) stopifnot(yms[i + 1L] == ym_next_w(yms[i]))
  mat  <- as.matrix(Mw[, -1, drop = FALSE]); rownames(mat) <- as.character(yms)
  list(mr = mr, snap = snap, liq = liq, mat = mat, yms = yms)
}

load_daily_wt <- function() {
  d <- as.data.table(read_parquet(file.path(MF_DIR, "p1_daily_returns.parquet")))
  setkey(d, ym)
  d
}

load_bench_daily_wt <- function() {
  b <- as.data.table(read_parquet(file.path(ROOT_WT, ".cache/pins", PIN_WT, "benchmark.parquet")))
  b[, Date := as.Date(Date)]                      # POSIXct → Date 명시 변환 (dtype 조인 함정 방지)
  b <- b[!is.na(BM_Ret), .(Date, mret = BM_Ret)]
  b[, ym := year(Date) * 100L + month(Date)]
  setkey(b, ym)
  b
}

# ---- NW t helper ------------------------------------------------------------
nw_t_w <- function(x, lag = 3L) {
  x <- as.numeric(x); x <- x[is.finite(x)]
  if (length(x) < 10L) return(list(mean_m = mean(x), t = NA_real_, n = length(x)))
  fit <- lm(x ~ 1)
  ct <- lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))
  list(mean_m = unname(ct[1, 1]), t = unname(ct[1, 3]), n = length(x))
}
ann_sr_w <- function(x) { x <- as.numeric(x); s <- sd(x); if (!is.finite(s) || s < 1e-12) return(NA_real_); mean(x) / s * sqrt(12) }

# ---- z-score (횡단면) -------------------------------------------------------
z_w <- function(v) {
  v <- as.numeric(v)
  s <- sd(v, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(0, length(v)))
  (v - mean(v, na.rm = TRUE)) / s
}
# winsorize 3sd 후 z (사전등록 규격)
zw3_w <- function(v) {
  v <- as.numeric(v)
  m <- mean(v, na.rm = TRUE); s <- sd(v, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(0, length(v)))
  v <- pmin(pmax(v, m - 3 * s), m + 3 * s)
  z_w(v)
}

# ---- structural drawdown (PerformanceAnalytics 표준함수만) -------------------
structural_dd_w <- function(net_xts) {
  mdd <- as.numeric(maxDrawdown(net_xts))
  dd_series <- PerformanceAnalytics::Drawdowns(net_xts)
  fd <- tryCatch(PerformanceAnalytics::findDrawdowns(net_xts), error = function(e) NULL)
  ep_depth <- if (!is.null(fd) && !is.null(fd$return)) abs(fd$return) else numeric(0)
  ep_len   <- if (!is.null(fd) && !is.null(fd$length)) fd$length else numeric(0)
  list(mdd = round(mdd, 4),
       n_episodes_45 = as.integer(sum(ep_depth >= 0.45)),
       n_episodes_30 = as.integer(sum(ep_depth >= 0.30)),
       drawdown_occupancy = round(mean(as.numeric(dd_series) < -1e-8), 4),
       longest_underwater_months = as.integer(if (length(ep_len)) max(ep_len) else 0))
}

# ---- oos retention v2 (anchored 3분할 중앙값 — 진단용, 권위는 essence_score) --
oos_v2_w <- function(x, splits = c(0.55, 0.65, 0.75)) {
  x <- as.numeric(x); N <- length(x)
  rr <- sapply(splits, function(f) {
    n1 <- floor(f * N); if (n1 < 6 || (N - n1) < 6) return(NA_real_)
    s_is <- ann_sr_w(x[1:n1]); s_oos <- ann_sr_w(x[(n1 + 1):N])
    if (!is.finite(s_is) || abs(s_is) < 1e-9) return(NA_real_); s_oos / s_is
  })
  list(splits = as.list(setNames(round(rr, 4), paste0("f", splits * 100))),
       median = round(median(rr, na.rm = TRUE), 4))
}

# ---- PSR (DSR 진단용) --------------------------------------------------------
psr_w <- function(x, sr0 = 0) {
  x <- as.numeric(x); n <- length(x); sr <- mean(x) / sd(x)
  g3 <- PerformanceAnalytics::skewness(x, method = "moment")
  g4 <- PerformanceAnalytics::kurtosis(x, method = "moment")
  pnorm(((sr - sr0) * sqrt(n - 1)) / sqrt(1 - g3 * sr + (g4 - 1) / 4 * sr^2))
}

cat("[wt001_lib] loaded — panels/helpers (pin=", PIN_WT, ")\n", sep = "")
