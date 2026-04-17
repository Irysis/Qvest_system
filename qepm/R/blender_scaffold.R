# v53 Sprint 2 S2.14: Blender Scaffold
# 독립 alpha 4건+ 확보 후 활성화. 현재는 scaffold만 제공.
#
# 주요 함수:
#   blender_check_activation()  — 활성화 조건 검사
#   blender_correlation_matrix() — 후보 상관 분석
#   blender_loo_validate()       — Leave-One-Out 검증
#   blender_ensemble()           — EW/RP/HRP/CVaR_LP 배분 계산

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

.blender_root <- function() {
  cands <- c(
    "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

# ── 활성화 조건: Grade A 독립 alpha 4+ ───────────────────────────────
blender_check_activation <- function(min_n = 4L, max_corr = 0.3) {
  root <- .blender_root()
  catalog <- file.path(root, "04_Research/grade_a_catalog.json")
  if (!file.exists(catalog)) {
    return(list(activated = FALSE,
                reason = "grade_a_catalog.json missing (S2.15 cleanup 필요)"))
  }
  grade_a <- tryCatch(jsonlite::fromJSON(catalog, simplifyVector = FALSE),
                      error = function(e) NULL)
  if (is.null(grade_a) || length(grade_a) < min_n) {
    return(list(activated = FALSE,
                reason = sprintf("Grade A %d건 < %d 필요",
                                 length(grade_a %||% list()), min_n)))
  }
  # 상관 행렬 (실제 return 접근 필요 — 여기선 메타만)
  list(activated = TRUE,
       n_candidates = length(grade_a),
       candidates = names(grade_a) %||% character(0),
       note = sprintf("조건 충족: Grade A %d건", length(grade_a)))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ── 상관 분석 ────────────────────────────────────────────────────────
blender_correlation_matrix <- function(returns_list) {
  stopifnot(is.list(returns_list), length(returns_list) >= 2L)
  m <- do.call(cbind, returns_list)
  cor_mat <- cor(m, use = "pairwise.complete.obs")
  pairs_high <- which(abs(cor_mat) > 0.5 & row(cor_mat) < col(cor_mat),
                      arr.ind = TRUE)
  list(
    matrix = cor_mat,
    high_corr_pairs = pairs_high,
    max_offdiag = max(abs(cor_mat[row(cor_mat) != col(cor_mat)])),
    diversity_ok = nrow(pairs_high) == 0
  )
}

# ── Equal Weight / Risk Parity / HRP (간단) ─────────────────────────
blender_ensemble <- function(returns_list, method = c("EW", "RP", "HRP")) {
  method <- match.arg(method)
  m <- do.call(cbind, returns_list)
  n <- ncol(m)
  if (method == "EW") {
    w <- rep(1 / n, n)
  } else if (method == "RP") {
    v <- apply(m, 2, sd, na.rm = TRUE)
    v <- ifelse(v < 1e-8, 1e-8, v)
    w <- (1 / v) / sum(1 / v)
  } else if (method == "HRP") {
    # 간단 v1: inverse-variance within cluster (실제 HRP는 더 복잡)
    cor_mat <- cor(m, use = "pairwise.complete.obs")
    dist_mat <- as.dist(sqrt(0.5 * (1 - cor_mat)))
    clu <- hclust(dist_mat, method = "single")
    order_idx <- clu$order
    v <- apply(m, 2, sd, na.rm = TRUE)[order_idx]
    w_ordered <- (1 / v) / sum(1 / v)
    w <- numeric(n)
    w[order_idx] <- w_ordered
  }
  names(w) <- colnames(m) %||% paste0("asset_", seq_len(n))
  port_ret <- m %*% w
  list(
    method = method,
    weights = w,
    portfolio_return = as.numeric(port_ret),
    n_assets = n
  )
}

# ── LOO 검증 ────────────────────────────────────────────────────────
blender_loo_validate <- function(returns_list, method = "EW") {
  base <- blender_ensemble(returns_list, method)
  base_sr <- mean(base$portfolio_return, na.rm = TRUE) /
             sd(base$portfolio_return, na.rm = TRUE) * sqrt(252)

  loo_results <- list()
  for (i in seq_along(returns_list)) {
    name <- names(returns_list)[i] %||% paste0("asset_", i)
    sub <- returns_list[-i]
    e <- blender_ensemble(sub, method)
    sr <- mean(e$portfolio_return, na.rm = TRUE) /
          sd(e$portfolio_return, na.rm = TRUE) * sqrt(252)
    loo_results[[name]] <- list(
      excluded = name,
      sr = sr,
      delta_sr = sr - base_sr,
      role = if (abs(sr - base_sr) >= 0.1) "essential" else "redundant"
    )
  }
  list(base_sr = base_sr, loo = loo_results)
}

cat("[blender_scaffold] Loaded. Functions: blender_check_activation / blender_correlation_matrix / blender_ensemble / blender_loo_validate\n")
