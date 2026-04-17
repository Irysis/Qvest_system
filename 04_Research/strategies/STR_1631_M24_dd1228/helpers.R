# helpers.R — STR_1631_M24_dd1228
# Gerber Statistic + RMT Denoise + HRP 알고리즘 함수 모음
# run_all.R에서 source("helpers.R")로 로드

# --- Gerber Statistic: robust correlation for fat-tailed returns ---
gerber_cor <- function(ret_matrix, threshold = 0.5) {
  n <- ncol(ret_matrix)
  mat <- matrix(0, n, n)
  med_abs <- apply(ret_matrix, 2, function(x) median(abs(x), na.rm = TRUE))
  med_abs <- ifelse(med_abs < 1e-12, apply(ret_matrix, 2, sd, na.rm = TRUE), med_abs)

  for (i in seq_len(n)) {
    thresh_i <- threshold * med_abs[i]
    hi <- ret_matrix[, i] > thresh_i
    li <- ret_matrix[, i] < -thresh_i
    for (j in i:n) {
      if (i == j) { mat[i, j] <- 1; next }
      thresh_j <- threshold * med_abs[j]
      hj <- ret_matrix[, j] > thresh_j
      lj <- ret_matrix[, j] < -thresh_j
      concordant <- sum((hi & hj) | (li & lj), na.rm = TRUE)
      discordant <- sum((hi & lj) | (li & hj), na.rm = TRUE)
      total <- concordant + discordant
      val <- if (total > 0L) (concordant - discordant) / total else 0
      mat[i, j] <- val
      mat[j, i] <- val
    }
  }
  diag(mat) <- 1
  colnames(mat) <- rownames(mat) <- colnames(ret_matrix)
  mat
}

# --- RMT (Random Matrix Theory) Denoising ---
rmt_denoise_cov <- function(cov_mat, T_obs, N_assets) {
  if (N_assets < 2L || T_obs < N_assets) return(cov_mat)
  vol <- sqrt(pmax(diag(cov_mat), 1e-16))
  cor_mat <- cov_mat / (vol %o% vol)
  cor_mat <- pmin(pmax(cor_mat, -1), 1)
  diag(cor_mat) <- 1

  eig <- tryCatch(eigen(cor_mat, symmetric = TRUE), error = function(e) NULL)
  if (is.null(eig)) return(cov_mat)

  vals <- eig$values
  vecs <- eig$vectors
  q <- T_obs / N_assets
  lambda_plus <- (1 + 1 / sqrt(q))^2

  noise_idx <- vals <= lambda_plus
  if (any(noise_idx) && !all(noise_idx)) {
    vals[noise_idx] <- mean(vals[noise_idx])
  }
  vals <- pmax(vals, 1e-8)

  denoised_cor <- vecs %*% diag(vals) %*% t(vecs)
  d_diag <- sqrt(pmax(diag(denoised_cor), 1e-16))
  denoised_cor <- denoised_cor / (d_diag %o% d_diag)
  diag(denoised_cor) <- 1

  denoised_cov <- denoised_cor * (vol %o% vol)
  colnames(denoised_cov) <- rownames(denoised_cov) <- colnames(cov_mat)
  denoised_cov
}

# --- HRP Recursive Bisection ---
.recursive_bisect <- function(cov_mat, sort_idx) {
  n <- length(sort_idx)
  nms <- colnames(cov_mat)
  if (n == 1L) return(setNames(1.0, nms[sort_idx]))

  mid <- floor(n / 2)
  left  <- sort_idx[1:mid]
  right <- sort_idx[(mid + 1):n]

  w_left  <- .recursive_bisect(cov_mat, left)
  w_right <- .recursive_bisect(cov_mat, right)

  nl <- names(w_left)
  nr <- names(w_right)
  var_left  <- as.numeric(t(w_left) %*% cov_mat[nl, nl, drop = FALSE] %*% w_left)
  var_right <- as.numeric(t(w_right) %*% cov_mat[nr, nr, drop = FALSE] %*% w_right)

  total_var <- var_left + var_right
  alpha <- if (is.na(total_var) || total_var < 1e-16) 0.5 else 1 - var_left / total_var
  c(w_left * alpha, w_right * (1 - alpha))
}

# --- Full Pipeline: Gerber -> RMT Denoise -> HRP ---
compute_hrp_weights <- function(ret_matrix, use_gerber = TRUE, use_rmt = TRUE) {
  n_col <- ncol(ret_matrix)
  n_row <- nrow(ret_matrix)
  ew_fallback <- setNames(rep(1 / n_col, n_col), colnames(ret_matrix))
  if (n_col < 2L) return(setNames(1.0, colnames(ret_matrix)))

  cov_mat <- cov(ret_matrix, use = "pairwise.complete.obs")
  if (any(is.na(cov_mat))) return(ew_fallback)

  cor_mat <- if (use_gerber) {
    tryCatch(gerber_cor(ret_matrix, threshold = 0.5),
             error = function(e) cor(ret_matrix, use = "pairwise.complete.obs"))
  } else {
    cor(ret_matrix, use = "pairwise.complete.obs")
  }
  if (any(is.na(cor_mat))) { cor_mat[is.na(cor_mat)] <- 0; diag(cor_mat) <- 1 }

  if (use_rmt && n_row > n_col) {
    cov_mat <- tryCatch(rmt_denoise_cov(cov_mat, T_obs = n_row, N_assets = n_col),
                        error = function(e) cov_mat)
  }

  cor_clamped <- pmin(pmax(cor_mat, -1), 1)
  dist_mat <- sqrt(0.5 * (1 - cor_clamped))
  dist_mat[is.na(dist_mat)] <- 1
  diag(dist_mat) <- 0

  hc <- tryCatch(hclust(as.dist(dist_mat), method = "single"),
                 error = function(e) NULL)
  if (is.null(hc)) return(ew_fallback)

  weights <- tryCatch(.recursive_bisect(cov_mat, hc$order),
                      error = function(e) NULL)
  if (is.null(weights)) return(ew_fallback)

  w_sum <- sum(weights)
  if (is.na(w_sum) || w_sum < 1e-10) return(ew_fallback)
  weights / w_sum
}

# --- Bulk parquet loader (OPT-1 준수: 루프 밖에서만 호출) ---
pq_load <- function(path) {
  as.data.table(arrow::read_parquet(path))
}

cat("[helpers] Gerber + RMT + HRP functions loaded.\n")
