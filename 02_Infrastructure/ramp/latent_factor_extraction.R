## latent_factor_extraction.R — RAMP Gate 4 (1차): 통계적 잠재팩터 추출
## 룰 §4/§5 (alpha-research). 풀 수익률행렬(T×N) → PCA(prcomp) + factanal(가능시) + hclust 고유포트.
## ★PC1 분산설명률 보고(KR 베타지배 예상 — 부풀림 금지).
## 실측-only: 본 모듈은 *구조분석*(분산설명/loading)만 산출. 성능수치(SR/alpha_t)는 산출 안 함
##            (그건 factor_validation.R 의 canonical_screen_bt 경유).

suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/ramp_io.R")

#' 풀 수익률행렬에서 통계적 잠재팩터 추출.
#' @param R matrix[T x N] 일별 net 수익률 (NA 허용)
#' @param n_pc 보고할 주성분 수 (default 10)
#' @param do_factanal factanal 시도 여부 (수렴 실패 가능 — 정직 보고)
#' @return list(pca, variance_explained, loadings(dt), eigen_returns(dt), factanal, scree(dt))
extract_latent_factors <- function(R, n_pc = 10L, do_factanal = TRUE, factanal_factors = 5L) {
  ids <- colnames(R); Tn <- nrow(R); N <- ncol(R)

  # ── 결측 처리: PCA 위해 완전관측 구간 또는 평균대치 필요.
  #    전략별 시작일이 달라 NA 다수 → 공통-관측 구간(모든 전략 관측된 날)이 너무 짧을 수 있음.
  #    방침: 각 전략 NA는 0(평균수익 근처)으로 대치 + 관측 마스크 보고. 데이터 한계 정직표기.
  na_frac_col <- colMeans(is.na(R))
  R0 <- R
  R0[is.na(R0)] <- 0   # 결측=0 대치 (해당일 미존재 전략은 PC 기여 0)
  # demean (PCA는 중심화 필수)
  R0c <- scale(R0, center = TRUE, scale = FALSE)

  # ── PCA ──
  pca <- prcomp(R0c, center = FALSE, scale. = FALSE)
  sdev <- pca$sdev
  var_exp <- sdev^2 / sum(sdev^2)
  n_rep <- min(n_pc, length(var_exp))

  scree <- data.table(
    pc = seq_len(n_rep),
    sdev = sdev[seq_len(n_rep)],
    variance_explained = var_exp[seq_len(n_rep)],
    cumulative_variance = cumsum(var_exp)[seq_len(n_rep)]
  )

  # loadings: rotation matrix (N x n_rep) — 각 전략의 PC 적재
  loadings <- as.data.table(pca$rotation[, seq_len(n_rep), drop = FALSE], keep.rownames = "strategy_id")
  setnames(loadings, old = paste0("PC", seq_len(n_rep)), new = paste0("PC", seq_len(n_rep)),
           skip_absent = TRUE)

  # eigen-portfolio returns: pca$x (T x n_rep) — 잠재팩터의 시계열 수익(고유포트폴리오)
  eigen_returns <- as.data.table(pca$x[, seq_len(n_rep), drop = FALSE])
  eigen_returns[, Date := as.Date(rownames(R))]
  setcolorder(eigen_returns, c("Date", paste0("PC", seq_len(n_rep))))

  # ── factanal (선택, 수렴 실패 정직보고) ──
  fa_res <- NULL
  if (isTRUE(do_factanal)) {
    fa_res <- tryCatch({
      # factanal은 상관행렬 기반 — 완전관측 corr 사용
      cmat <- cor(R, use = "pairwise.complete.obs")
      cmat[is.na(cmat)] <- 0; diag(cmat) <- 1
      # PD 보정
      ev <- eigen(cmat, symmetric = TRUE)$values
      if (min(ev) < 1e-6) cmat <- cmat + diag(1e-3, N)
      fa <- factanal(covmat = cmat, factors = factanal_factors, rotation = "varimax")
      list(status = "ok", factors = factanal_factors,
           uniquenesses_mean = mean(fa$uniquenesses),
           pval = fa$PVAL %||% NA_real_,
           loadings = as.data.table(unclass(fa$loadings), keep.rownames = "strategy_id"))
    }, error = function(e) list(status = "failed", error = conditionMessage(e)))
  }

  list(
    pca = pca,
    n_strategies = N, n_days = Tn,
    pc1_variance_explained = var_exp[1],
    top10_cumulative_variance = sum(var_exp[seq_len(min(10, length(var_exp)))]),
    variance_explained = var_exp,
    scree = scree,
    loadings = loadings,
    eigen_returns = eigen_returns,
    factanal = fa_res,
    na_frac_col = na_frac_col,
    note = sprintf("PCA on demeaned daily returns (NA->0 imputation). PC1 var=%.1f%% (KR 베타지배 진단).",
                   100 * var_exp[1])
  )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[latent_factor_extraction.R] Loaded — extract_latent_factors() (PCA/factanal, PC1 var 보고)\n")
