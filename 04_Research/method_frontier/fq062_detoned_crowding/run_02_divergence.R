# =============================================================================
# FQ-062 run_02 — detoned residual-crowding: 3-estimator DIVERGENCE (falsification-first)
#
# Hypothesis (반증 우선): lw_nls의 잔차 고유값 dispersion 보존이, RMT-detone(.rmt_denoise)
#   ·sample과 *실제로 다른* detoned 잔차-crowding 시계열을 낳는가.
#   near-identical → lw_nls incidental → KILL. 유의 발산 시에만 다음 단계 자격.
#
# 방법 (딱 이 범위):
#   각 window-end(60m rolling, monthly step)에서 유니버스-규모(p>n) 상관행렬
#     (a) sample cor  (b) .rmt_denoise(q=n/p)  (c) cov2cor(.lw_nls_cov)
#   → detone(PC1 시장모드 제거) → 잔차 concentration 지표 시계열
#   → 3종 시계열 발산량(pairwise Pearson+Spearman·MoM 부호일치·z>2 이벤트 자카드).
#
# ★공정성 수정(run_02 v2): p>n 표본상관은 rank≤n-1 → detone 후 informative 잔차모드는
#   n-2개뿐. lw_nls는 null-space를 양수로 채워(full-rank) 전체-잔차 denom 지표(m_full)를
#   구조적으로 왜곡한다(rank-deficiency 아티팩트, dispersion "정보" 아님). 따라서
#   FAIR 지표 m_fixed = PC2-10 / (공유 informative 잔차 top-(n-2)) 로 두 추정기를 동일
#   부분공간에 정렬 → lw_nls 비선형수축의 순 효과만 격리. 추가로 lw_nls가 고유벡터를
#   *정확히* 보존하는 COVARIANCE 기반(cov2cor 교란 제거)까지 robustness로 측정.
#
# metric_type = spectral_diagnostic. 자본/성과/SR/weight 주장 일절 금지.
#
# Output: stage_artifacts/method_frontier/fq062_divergence.parquet
#         stage_artifacts/method_frontier/fq062/fq062_divergence_stats.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))

OUT_DIR   <- file.path(ROOT, "stage_artifacts/method_frontier/fq062")
STAGE_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

WIN   <- 60L
MIN_P <- 40L
K_RES <- 9L        # PC2..PC10 = first 9 residual eigenvalues

mr  <- as.data.table(read_parquet(file.path(OUT_DIR, "fq062_monthly_returns.parquet")))
sn  <- as.data.table(read_parquet(file.path(OUT_DIR, "fq062_monthly_snapshot.parquet")))
pin_tag <- fromJSON(file.path(OUT_DIR, "fq062_pin_tag.json"))$pin_tag
cat("[load] pin_tag:", pin_tag, " return rows:", nrow(mr), "\n")

yms <- sort(unique(mr$ym))
end_candidates <- yms[seq_len(length(yms)) >= WIN]
cat("[windows] candidate window-ends:", length(end_candidates),
    " range:", min(end_candidates), "..", max(end_candidates), "\n")

# ---- residual-spectrum metrics from a symmetric matrix ----------------------
# k_info = shared non-degenerate residual dimension (n-2 for both estimators)
resid_metrics <- function(M, k_info) {
  eg <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
  eg <- sort(eg, decreasing = TRUE); eg[eg < 0] <- 0
  lam1 <- eg[1]; tot <- sum(eg)
  ar_pc1 <- if (tot > 0) lam1 / tot else NA_real_
  res <- eg[-1]                                  # detone: drop PC1
  kk  <- min(K_RES, length(res))
  ki  <- min(k_info, length(res))
  res_tot   <- sum(res)
  denom_fix <- sum(res[seq_len(ki)])             # FAIR: shared informative residual
  m_full  <- if (res_tot   > 0) sum(res[seq_len(kk)]) / res_tot   else NA_real_
  m_fixed <- if (denom_fix > 0) sum(res[seq_len(min(kk, ki))]) / denom_fix else NA_real_
  resf <- res[seq_len(ki)]                        # residual over shared informative rank
  neff_fix <- if (sum(resf^2) > 0) (sum(resf)^2) / sum(resf^2) else NA_real_
  top_fix  <- if (denom_fix > 0) res[1] / denom_fix else NA_real_
  list(ar_pc1 = ar_pc1, m_full = m_full, m_fixed = m_fixed,
       neff_fix = neff_fix, top_fix = top_fix)
}

rows <- list(); rmt_active_any <- FALSE
for (ye in end_candidates) {
  win <- tail(yms[yms <= ye], WIN); if (length(win) < WIN) next
  memb <- sn[ym == ye & member == 1L & !is.na(size), Ticker]      # PIT membership
  if (length(memb) < MIN_P) next
  sub <- mr[ym %in% win & Ticker %in% memb]
  cnt <- sub[, .N, by = Ticker][N == WIN, Ticker]                # complete 60m only
  if (length(cnt) < MIN_P) next
  W <- dcast(sub[Ticker %in% cnt], ym ~ Ticker, value.var = "ret_m")
  R <- as.matrix(W[, -1]); rownames(R) <- W$ym
  p <- ncol(R); n <- nrow(R); q_ratio <- n / p
  k_info <- n - 2L                                               # shared informative residual rank

  # correlation estimators
  C_s <- cor(R, use = "pairwise.complete.obs"); C_s[is.na(C_s)] <- 0
  C_r <- .rmt_denoise(C_s, q_ratio)
  rmt_noop <- isTRUE(all.equal(C_r, C_s, tolerance = 1e-12, check.attributes = FALSE))
  if (!rmt_noop) rmt_active_any <- TRUE
  Sig_nls <- tryCatch(.lw_nls_cov(R), error = function(e) NULL); if (is.null(Sig_nls)) next
  sds <- sqrt(diag(Sig_nls)); C_l <- Sig_nls / outer(sds, sds); diag(C_l) <- 1; C_l[is.na(C_l)] <- 0
  # covariance estimators (robustness: lw_nls preserves cov eigenvectors exactly)
  S_s <- cov(R, use = "pairwise.complete.obs"); S_s[is.na(S_s)] <- 0

  cs <- resid_metrics(C_s, k_info); cr <- resid_metrics(C_r, k_info); cl <- resid_metrics(C_l, k_info)
  vs <- resid_metrics(S_s, k_info); vl <- resid_metrics(Sig_nls, k_info)

  rows[[length(rows) + 1L]] <- data.table(
    ym = ye, p = p, n = n, q_ratio = q_ratio, rmt_noop = rmt_noop, k_info = k_info,
    # correlation
    cor_ar_pc1_sample = cs$ar_pc1, cor_ar_pc1_rmt = cr$ar_pc1, cor_ar_pc1_lwnls = cl$ar_pc1,
    cor_mfix_sample = cs$m_fixed, cor_mfix_rmt = cr$m_fixed, cor_mfix_lwnls = cl$m_fixed,
    cor_mfull_sample = cs$m_full, cor_mfull_rmt = cr$m_full, cor_mfull_lwnls = cl$m_full,
    cor_neff_sample = cs$neff_fix, cor_neff_rmt = cr$neff_fix, cor_neff_lwnls = cl$neff_fix,
    cor_top_sample = cs$top_fix, cor_top_rmt = cr$top_fix, cor_top_lwnls = cl$top_fix,
    # covariance (RMT no-op => cov RMT == cov sample; omit rmt col)
    cov_ar_pc1_sample = vs$ar_pc1, cov_ar_pc1_lwnls = vl$ar_pc1,
    cov_mfix_sample = vs$m_fixed, cov_mfix_lwnls = vl$m_fixed,
    cov_neff_sample = vs$neff_fix, cov_neff_lwnls = vl$neff_fix
  )
}
DT <- rbindlist(rows)
cat("[compute] usable windows:", nrow(DT), " p range:",
    paste(range(DT$p), collapse = ".."), " RMT active any:", rmt_active_any, "\n")
stopifnot(nrow(DT) >= 24)
write_parquet(DT, file.path(STAGE_DIR, "fq062_divergence.parquet"))

# ---- divergence statistics --------------------------------------------------
jacc <- function(a, b, zthr = 2) {
  za <- (a - mean(a, na.rm=TRUE))/sd(a, na.rm=TRUE); zb <- (b - mean(b, na.rm=TRUE))/sd(b, na.rm=TRUE)
  ea <- which(abs(za) > zthr); eb <- which(abs(zb) > zthr); u <- union(ea, eb)
  list(jaccard = if (length(u)==0) NA_real_ else length(intersect(ea,eb))/length(u),
       n_a = length(ea), n_b = length(eb), n_union = length(u))
}
sign_agree <- function(a, b) {
  da <- sign(diff(a)); db <- sign(diff(b)); ok <- is.finite(da)&is.finite(db)&(da!=0|db!=0)
  if (!any(ok)) NA_real_ else mean(da[ok]==db[ok])
}
pair <- function(a, b) {
  e2 <- jacc(a,b,2); e15 <- jacc(a,b,1.5)
  list(pearson = suppressWarnings(cor(a,b,use="complete.obs")),
       spearman = suppressWarnings(cor(a,b,method="spearman",use="complete.obs")),
       sign_agree = sign_agree(a,b),
       event_jaccard_z2 = e2$jaccard, n_events_a_z2 = e2$n_a, n_events_b_z2 = e2$n_b, n_union_z2 = e2$n_union,
       event_jaccard_z15 = e15$jaccard, n_union_z15 = e15$n_union,
       level_ratio_median = median(b,na.rm=TRUE)/median(a,na.rm=TRUE))
}

# metric families (basis prefix cor_ / cov_)
mk <- function(basis, metric, est) DT[[paste0(basis, "_", metric, "_", est)]]
cor_metrics <- c("ar_pc1","mfix","mfull","neff","top")
cov_metrics <- c("ar_pc1","mfix","neff")
div <- list(correlation = list(), covariance = list())
for (m in cor_metrics) {
  s <- mk("cor",m,"sample"); r <- mk("cor",m,"rmt"); l <- mk("cor",m,"lwnls")
  div$correlation[[m]] <- list(lwnls_vs_sample = pair(s,l),
                               lwnls_vs_rmt = pair(r,l), sample_vs_rmt = pair(s,r))
}
for (m in cov_metrics) {
  s <- mk("cov",m,"sample"); l <- mk("cov",m,"lwnls")
  div$covariance[[m]] <- list(lwnls_vs_sample = pair(s,l))
}

# ---- verdict ----------------------------------------------------------------
# PRIMARY fair metric = correlation m_fixed (monitoring-relevant, shared informative subspace).
# CORROBORATION = covariance m_fixed (lw_nls preserves cov eigenvectors exactly — cleanest).
# KILL_lw_nls_incidental if BOTH near-identical: (|pearson|>0.95 & |spearman|>0.95).
#   (event jaccard reported but not hard-gated: z>2 events are few over ~200m => underpowered.)
pc <- div$correlation$mfix$lwnls_vs_sample
pv <- div$covariance$mfix$lwnls_vs_sample
near_cor <- abs(pc$pearson) > 0.95 && abs(pc$spearman) > 0.95
near_cov <- abs(pv$pearson) > 0.95 && abs(pv$spearman) > 0.95
verdict <- if (near_cor && near_cov) "KILL_lw_nls_incidental" else "DIVERGENT_pursue_conditional"

out <- list(
  fq = "FQ-062", metric_type = "spectral_diagnostic", pin_tag = pin_tag,
  window_rule = "monthly 60m rolling, PC1-detone residual spectrum, universe = PIT index members with complete 60m; k_info = n-2 shared informative residual rank",
  n_windows = nrow(DT), p_range = range(DT$p), n_obs = WIN,
  q_ratio_range = range(DT$q_ratio),
  rmt_active_any_window = rmt_active_any, rmt_noop_all = all(DT$rmt_noop),
  primary_metric = "cor_mfix (correlation, shared informative residual)",
  corroboration_metric = "cov_mfix (covariance, lw_nls eigenvector-exact)",
  divergence = div, verdict = verdict,
  near_identical_cor_mfix = near_cor, near_identical_cov_mfix = near_cov
)
write_json(out, file.path(OUT_DIR, "fq062_divergence_stats.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")

cat("\n==================== FQ-062 DIVERGENCE (v2 fair) ====================\n")
cat("windows:", nrow(DT), " p:", paste(range(DT$p),collapse="-"), " n:", WIN,
    " q:", sprintf("%.3f-%.3f", min(DT$q_ratio), max(DT$q_ratio)), "\n")
cat("RMT no-op all windows:", all(DT$rmt_noop), " (q<1 => .rmt_denoise returns sample)\n\n")
cat("-- CORRELATION basis, lwnls ~ sample --\n")
for (m in cor_metrics) {
  a <- div$correlation[[m]]$lwnls_vs_sample
  cat(sprintf("  [%-7s] pearson=%+.3f spearman=%+.3f sign=%.2f jac_z2=%s(n_u=%d) jac_z1.5=%s levr=%.2f\n",
      m, a$pearson, a$spearman, a$sign_agree,
      ifelse(is.na(a$event_jaccard_z2),"NA",sprintf("%.2f",a$event_jaccard_z2)), a$n_union_z2,
      ifelse(is.na(a$event_jaccard_z15),"NA",sprintf("%.2f",a$event_jaccard_z15)), a$level_ratio_median))
}
cat("-- COVARIANCE basis (lw_nls eigenvector-exact), lwnls ~ sample --\n")
for (m in cov_metrics) {
  a <- div$covariance[[m]]$lwnls_vs_sample
  cat(sprintf("  [%-7s] pearson=%+.3f spearman=%+.3f sign=%.2f jac_z2=%s levr=%.2f\n",
      m, a$pearson, a$spearman, a$sign_agree,
      ifelse(is.na(a$event_jaccard_z2),"NA",sprintf("%.2f",a$event_jaccard_z2)), a$level_ratio_median))
}
cat("\nVERDICT:", verdict, "  (near_cor=", near_cor, " near_cov=", near_cov, ")\n")
cat("====================================================================\n")
