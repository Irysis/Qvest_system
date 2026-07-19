# =============================================================================
# FQ-062 run_02 — detoned residual-crowding: 3-estimator DIVERGENCE (falsification-first)
#
# Hypothesis (반증 우선): lw_nls의 잔차 고유값 dispersion 보존이, RMT-detone(.rmt_denoise)
#   ·sample과 *실제로 다른* detoned 잔차-crowding 시계열을 낳는가.
#   near-identical → lw_nls incidental → KILL. 유의 발산 시에만 다음 단계 자격.
#
# 방법 (딱 이 범위):
#   각 window-end(60m rolling, monthly step)에서 유니버스-규모(p>n) 3종 상관행렬
#     (a) sample cor  (b) .rmt_denoise(q=n/p)  (c) cov2cor(.lw_nls_cov)
#   → detone(PC1 시장모드 제거) → 잔차 concentration 지표 시계열 산출
#   → 3종 시계열 발산량(pairwise Pearson+Spearman·MoM 부호일치·z>2 이벤트 자카드).
#
# metric_type = spectral_diagnostic. 자본/성과/SR/weight 주장 일절 금지.
#
# Output: stage_artifacts/method_frontier/fq062_divergence.parquet  (3종 잔차 시계열)
#         stage_artifacts/method_frontier/fq062/fq062_divergence_stats.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
# hrp_core defines .get_cor_cov / .lw_nls_cov / .rmt_denoise (standalone mode)
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))

OUT_DIR   <- file.path(ROOT, "stage_artifacts/method_frontier/fq062")
STAGE_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

WIN <- 60L        # rolling window length in months
MIN_P <- 40L      # minimum tickers to attempt spectral estimation
K_RES <- 9L       # PC2..PC10 = first 9 residual eigenvalues (detone removes PC1)
TOL_REL <- 1e-6   # relative eigenvalue tolerance for effective residual rank

mr  <- as.data.table(read_parquet(file.path(OUT_DIR, "fq062_monthly_returns.parquet")))
sn  <- as.data.table(read_parquet(file.path(OUT_DIR, "fq062_monthly_snapshot.parquet")))
pin_tag <- fromJSON(file.path(OUT_DIR, "fq062_pin_tag.json"))$pin_tag
cat("[load] pin_tag:", pin_tag, " return rows:", nrow(mr), "\n")

yms <- sort(unique(mr$ym))
# window-end must have >=WIN months of history in the sample
end_candidates <- yms[seq_len(length(yms)) >= WIN]
cat("[windows] candidate window-ends:", length(end_candidates),
    " range:", min(end_candidates), "..", max(end_candidates), "\n")

# ---- residual-spectrum metrics from a correlation matrix --------------------
resid_metrics <- function(C) {
  eg <- eigen(C, symmetric = TRUE, only.values = TRUE)$values
  eg <- sort(eg, decreasing = TRUE)
  eg[eg < 0] <- 0                      # numerical floor (PSD)
  lam1  <- eg[1]
  tot   <- sum(eg)
  ar_pc1 <- if (tot > 0) lam1 / tot else NA_real_   # classic Absorption Ratio (context)
  res   <- eg[-1]                      # detone: drop PC1
  res_tot <- sum(res)
  # effective residual rank (# residual eigenvalues above rel tol of lam1)
  r_eff <- sum(res > TOL_REL * lam1)
  kk    <- min(K_RES, length(res))
  m_a   <- if (res_tot > 0) sum(res[seq_len(kk)]) / res_tot else NA_real_        # PC2-10 / all-residual
  denom_b <- if (r_eff >= 1) sum(res[seq_len(r_eff)]) else res_tot
  m_b   <- if (denom_b > 0) sum(res[seq_len(min(kk, r_eff))]) / denom_b else NA_real_ # PC2-10 / non-degenerate residual
  neff_res <- if (sum(res^2) > 0) (res_tot^2) / sum(res^2) else NA_real_          # participation ratio
  top_res_share <- if (res_tot > 0) res[1] / res_tot else NA_real_                # PC2 share of residual
  list(ar_pc1 = ar_pc1, m_a = m_a, m_b = m_b, neff_res = neff_res,
       top_res_share = top_res_share, r_eff = r_eff)
}

rows <- list()
rmt_active_any <- FALSE
for (ye in end_candidates) {
  win <- yms[yms <= ye]; win <- tail(win, WIN)
  if (length(win) < WIN) next
  memb <- sn[ym == ye & member == 1L & !is.na(size), Ticker]     # PIT membership at window end
  if (length(memb) < MIN_P) next
  sub <- mr[ym %in% win & Ticker %in% memb]
  cnt <- sub[, .N, by = Ticker][N == WIN, Ticker]               # complete 60m only
  if (length(cnt) < MIN_P) next
  W <- dcast(sub[Ticker %in% cnt], ym ~ Ticker, value.var = "ret_m")
  R <- as.matrix(W[, -1]); rownames(R) <- W$ym
  p <- ncol(R); n <- nrow(R)
  q_ratio <- n / p

  # (a) sample correlation
  C_s <- cor(R, use = "pairwise.complete.obs"); C_s[is.na(C_s)] <- 0
  # (b) RMT-detone via .rmt_denoise (as-is; q<1 => no-op by design)
  C_r <- .rmt_denoise(C_s, q_ratio)
  rmt_noop <- isTRUE(all.equal(C_r, C_s, tolerance = 1e-12,
                               check.attributes = FALSE))
  if (!rmt_noop) rmt_active_any <- TRUE
  # (c) lw_nls covariance -> correlation
  Sig_nls <- tryCatch(.lw_nls_cov(R), error = function(e) NULL)
  if (is.null(Sig_nls)) next
  sds <- sqrt(diag(Sig_nls)); C_l <- Sig_nls / outer(sds, sds); diag(C_l) <- 1
  C_l[is.na(C_l)] <- 0

  ms <- resid_metrics(C_s); mr_ <- resid_metrics(C_r); ml <- resid_metrics(C_l)
  rows[[length(rows) + 1L]] <- data.table(
    ym = ye, p = p, n = n, q_ratio = q_ratio, rmt_noop = rmt_noop, r_eff = ms$r_eff,
    ar_pc1_sample = ms$ar_pc1, ar_pc1_rmt = mr_$ar_pc1, ar_pc1_lwnls = ml$ar_pc1,
    m_a_sample = ms$m_a,   m_a_rmt = mr_$m_a,   m_a_lwnls = ml$m_a,
    m_b_sample = ms$m_b,   m_b_rmt = mr_$m_b,   m_b_lwnls = ml$m_b,
    neff_res_sample = ms$neff_res, neff_res_rmt = mr_$neff_res, neff_res_lwnls = ml$neff_res,
    top_res_sample = ms$top_res_share, top_res_rmt = mr_$top_res_share, top_res_lwnls = ml$top_res_share
  )
}
DT <- rbindlist(rows)
cat("[compute] usable windows:", nrow(DT), " p range:",
    if (nrow(DT)) paste(range(DT$p), collapse = "..") else "NA",
    " RMT active any window:", rmt_active_any, "\n")
stopifnot(nrow(DT) >= 24)

write_parquet(DT, file.path(STAGE_DIR, "fq062_divergence.parquet"))

# ---- divergence statistics per metric --------------------------------------
jaccard_events <- function(a, b, zthr = 2) {
  za <- (a - mean(a, na.rm = TRUE)) / sd(a, na.rm = TRUE)
  zb <- (b - mean(b, na.rm = TRUE)) / sd(b, na.rm = TRUE)
  ea <- which(abs(za) > zthr); eb <- which(abs(zb) > zthr)
  u <- union(ea, eb)
  if (length(u) == 0) return(list(jaccard = NA_real_, n_events_a = 0L,
                                  n_events_b = 0L, n_union = 0L))
  list(jaccard = length(intersect(ea, eb)) / length(u),
       n_events_a = length(ea), n_events_b = length(eb), n_union = length(u))
}
sign_agree <- function(a, b) {
  da <- sign(diff(a)); db <- sign(diff(b))
  ok <- is.finite(da) & is.finite(db) & (da != 0 | db != 0)
  if (!any(ok)) return(NA_real_)
  mean(da[ok] == db[ok])
}
pair_stats <- function(a, b) {
  ev <- jaccard_events(a, b)
  list(pearson  = suppressWarnings(cor(a, b, use = "complete.obs")),
       spearman = suppressWarnings(cor(a, b, method = "spearman", use = "complete.obs")),
       sign_agree = sign_agree(a, b),
       event_jaccard = ev$jaccard, n_events_a = ev$n_events_a,
       n_events_b = ev$n_events_b, n_union = ev$n_union,
       level_ratio_median = median(b, na.rm = TRUE) / median(a, na.rm = TRUE))
}

metrics <- c("ar_pc1", "m_a", "m_b", "neff_res", "top_res")
col <- function(metric, est) {
  base <- if (metric == "top_res") "top_res" else metric
  DT[[paste0(base, "_", est)]]
}
div <- list()
for (mt in metrics) {
  s <- col(mt, "sample"); r <- col(mt, "rmt"); l <- col(mt, "lwnls")
  div[[mt]] <- list(
    lwnls_vs_sample = pair_stats(s, l),
    lwnls_vs_rmt    = pair_stats(r, l),
    sample_vs_rmt   = pair_stats(s, r)
  )
}

# ---- verdict logic ----------------------------------------------------------
# Primary fair metric = m_b (residual restricted to non-degenerate modes; isolates
# lw_nls nonlinear-shrink effect free of null-space inflation). Secondary = neff_res.
# KILL_lw_nls_incidental if lw_nls vs sample near-identical on the FAIR metric:
#   (|pearson|>0.95 OR |spearman|>0.95) AND event_jaccard>0.8.
primary <- "m_b"
ps <- div[[primary]]$lwnls_vs_sample
near_identical <- ((abs(ps$pearson) > 0.95) || (abs(ps$spearman) > 0.95)) &&
                  (is.na(ps$event_jaccard) || ps$event_jaccard > 0.8)
# also require neff_res corroboration
ps2 <- div[["neff_res"]]$lwnls_vs_sample
corrob <- (abs(ps2$spearman) > 0.90)

verdict <- if (near_identical && corrob) "KILL_lw_nls_incidental" else "DIVERGENT_pursue_conditional"

out <- list(
  fq = "FQ-062",
  metric_type = "spectral_diagnostic",
  pin_tag = pin_tag,
  window_rule = "monthly 60m rolling, PC1-detone residual spectrum, universe = PIT index members with complete 60m",
  n_windows = nrow(DT),
  p_range = range(DT$p), n_obs = WIN, q_ratio_range = range(DT$q_ratio),
  rmt_active_any_window = rmt_active_any,
  rmt_noop_all = all(DT$rmt_noop),
  primary_metric = primary,
  divergence = div,
  verdict = verdict,
  near_identical_primary = near_identical,
  neff_res_corroborated = corrob
)
write_json(out, file.path(OUT_DIR, "fq062_divergence_stats.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")

cat("\n==================== FQ-062 DIVERGENCE ====================\n")
cat("windows:", nrow(DT), " p:", paste(range(DT$p), collapse="-"),
    " n:", WIN, " q_ratio:", sprintf("%.3f-%.3f", min(DT$q_ratio), max(DT$q_ratio)), "\n")
cat("RMT no-op all windows:", all(DT$rmt_noop), " (q<1 => .rmt_denoise returns sample)\n\n")
for (mt in metrics) {
  a <- div[[mt]]$lwnls_vs_sample
  cat(sprintf("[%-9s] lwnls~sample  pearson=%+.3f spearman=%+.3f sign=%.2f jaccard=%s levratio=%.2f\n",
      mt, a$pearson, a$spearman, a$sign_agree,
      ifelse(is.na(a$event_jaccard), "NA", sprintf("%.2f", a$event_jaccard)),
      a$level_ratio_median))
}
cat("\nVERDICT:", verdict, "\n")
cat("==========================================================\n")
