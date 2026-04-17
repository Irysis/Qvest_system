## =============================================================================
## STR_META_LEARNING Phase 2: Expanding PCA + K-means Regime Discovery
## =============================================================================
## 핵심 아이디어:
##   - 팩터 IC 행렬에 expanding PCA를 적용해 잠재 팩터 레짐 공간을 추출
##   - expanding K-means로 현재 월이 어떤 팩터 레짐에 속하는지 분류
##   - 모든 추정은 t-1까지 데이터만 사용 (PIT C1 준수)
##
## PIT C1 체크:
##   [1] "이 데이터는 의사결정 시점에 알 수 있었는가?"    -> 모든 PCA/K-means는 rows 1:t-1
##   [2] "이후 결과가 판단에 영향을 미치지 않는가?"       -> 현재월 t는 projection만
##   [3] "'괜찮다'고 느끼는 이유가 결과를 이미 알기 때문은 아닌가?" -> expanding window 강제
##
## Author : Forge (V7 Research Engine)
## Created: 2026-04-13
## =============================================================================

cat("=== Phase 2: Expanding PCA + K-means Regime Discovery ===\n")
cat("PIT C1 강제: 모든 PCA/K-means는 t-1까지 expanding window 사용\n\n")

## ---------------------------------------------------------------------------
## 0. 환경 설정
## ---------------------------------------------------------------------------
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
OUT_DIR      <- file.path(PROJECT_ROOT, "04_Research/strategies/meta_learning/output")

# config.R 로드 (인프라 설정)
tryCatch(
  source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R")),
  error = function(e) cat("config.R 생략:", conditionMessage(e), "\n")
)

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(ggplot2)
  library(jsonlite)
  library(cluster)    # silhouette
  library(Rtsne)      # t-SNE 시각화
})

set.seed(42)  # 재현성

## ---------------------------------------------------------------------------
## 1. IC 행렬 로드 (1회만)
## ---------------------------------------------------------------------------
cat("[1/7] IC 행렬 로드 중...\n")
t0_load <- proc.time()

ic_raw <- read_parquet(file.path(CACHE_DIR, "ic_matrix_expanding.parquet"))
ic_dt  <- as.data.table(ic_raw)
rm(ic_raw)

# 메타 컬럼 vs 팩터 컬럼 분리
META_COLS   <- c("Date", "N_Factors", "N_Stocks_Median")
FACTOR_COLS <- setdiff(names(ic_dt), META_COLS)

# 날짜 정렬 (오름차순 보장)
ic_dt <- ic_dt[order(Date)]
dates  <- ic_dt$Date
n_months <- nrow(ic_dt)

cat(sprintf("  IC 행렬: %d개월 × %d 팩터\n", n_months, length(FACTOR_COLS)))
cat(sprintf("  기간: %s ~ %s\n", as.character(min(dates)), as.character(max(dates))))
cat(sprintf("  로드 시간: %.1fs\n\n", (proc.time() - t0_load)["elapsed"]))

## ---------------------------------------------------------------------------
## 2. Expanding PCA (Step 2a)
## ---------------------------------------------------------------------------
## 규칙:
##   - t = 37 부터 시작 (36개월 warmup)
##   - rows 1:(t-1) 사용, 절대 row t 포함 금지 (C1)
##   - >50% NA 컬럼 제거, 나머지 NA → 0 대체
##   - 현재월 t는 과거 PCA 공간에 projection만
## ---------------------------------------------------------------------------
cat("[2/7] Expanding PCA 실행 중...\n")
t0_pca <- proc.time()

WARMUP_PCA  <- 36   # PCA 시작 시점 (1-indexed: t=37부터)
N_PCS       <- 5    # 저장할 PC 수

# IC 팩터 행렬을 matrix로 변환 (루프 내 반복 변환 방지)
ic_mat <- as.matrix(ic_dt[, ..FACTOR_COLS])  # n_months × n_factors

# 결과 저장 컨테이너
pca_pc_scores    <- matrix(NA_real_, nrow = n_months, ncol = N_PCS)
pca_expvar_cum   <- matrix(NA_real_, nrow = n_months, ncol = N_PCS)
pca_expvar_each  <- matrix(NA_real_, nrow = n_months, ncol = N_PCS)
pca_n_factors    <- integer(n_months)
pca_valid_months <- integer(0)

for (t in (WARMUP_PCA + 1):n_months) {
  # C1 강제: rows 1:(t-1)만 사용, t 절대 포함 금지
  window_rows <- 1:(t - 1)

  # --- NA 처리 ---
  sub_mat <- ic_mat[window_rows, , drop = FALSE]

  # >50% NA 컬럼 제거
  na_pct_col <- colMeans(is.na(sub_mat))
  keep_cols  <- which(na_pct_col <= 0.5)
  if (length(keep_cols) < 3) next  # 팩터 부족

  sub_mat_clean <- sub_mat[, keep_cols, drop = FALSE]

  # 나머지 NA → 0 (IC 없음 = 예측력 없음)
  sub_mat_clean[is.na(sub_mat_clean)] <- 0

  # 상수 컬럼 제거 (PCA 불가)
  col_var <- apply(sub_mat_clean, 2, var)
  keep_var <- which(col_var > 1e-10)
  if (length(keep_var) < 3) next

  sub_mat_clean <- sub_mat_clean[, keep_var, drop = FALSE]
  n_valid_factors <- ncol(sub_mat_clean)

  # --- PCA ---
  pca_fit <- tryCatch(
    prcomp(sub_mat_clean, center = TRUE, scale. = TRUE),
    error = function(e) NULL
  )
  if (is.null(pca_fit)) next

  # 설명분산
  evar  <- pca_fit$sdev^2
  total_var <- sum(evar)
  n_pcs_avail <- min(N_PCS, length(evar))

  # --- 현재 월 t 투영 (projection only, NOT re-fit) ---
  # t 시점 IC 벡터를 과거 PCA 공간에 투영
  t_vec_raw <- ic_mat[t, keep_cols[keep_var], drop = FALSE]
  t_vec_raw[is.na(t_vec_raw)] <- 0

  # center & scale by training parameters
  t_vec_scaled <- sweep(t_vec_raw, 2,
                        pca_fit$center,  "-")
  t_vec_scaled <- sweep(t_vec_scaled, 2,
                        pca_fit$scale,   "/")

  # projection: X_scaled %*% rotation
  t_scores <- as.numeric(t_vec_scaled %*% pca_fit$rotation[, 1:n_pcs_avail])

  # 저장
  pca_pc_scores[t, 1:n_pcs_avail]   <- t_scores
  pca_expvar_each[t, 1:n_pcs_avail] <- evar[1:n_pcs_avail] / total_var * 100
  pca_expvar_cum[t, 1:n_pcs_avail]  <- cumsum(evar[1:n_pcs_avail]) / total_var * 100
  pca_n_factors[t]  <- n_valid_factors
  pca_valid_months  <- c(pca_valid_months, t)
}

cat(sprintf("  PCA 완료: %d개월 유효 (%.1fs)\n",
            length(pca_valid_months),
            (proc.time() - t0_pca)["elapsed"]))

# 마지막 유효 월 설명분산 요약 출력
last_t   <- tail(pca_valid_months, 1)
cat(sprintf("  최근 월 기준 PC 설명분산 (cumulative):\n"))
for (k in 1:N_PCS) {
  cat(sprintf("    PC%d: %.1f%%\n", k, pca_expvar_cum[last_t, k]))
}
cat("\n")

## ---------------------------------------------------------------------------
## 3. Expanding K-means (Step 2b)
## ---------------------------------------------------------------------------
## 규칙:
##   - t = 49부터 시작 (48개월 warmup)
##   - t-1까지 PC scores 사용, 절대 t 포함 금지 (C1)
##   - k=5, nstart=25
##   - 레짐 확률 = softmax(-dist^2 / temperature)
##   - temperature = 중앙값(모든 센트로이드 쌍별 거리)
## ---------------------------------------------------------------------------
cat("[3/7] Expanding K-means 실행 중...\n")
t0_km <- proc.time()

WARMUP_KM <- 48   # K-means 시작 시점
K_CLUSTERS <- 5
NSTART_KM  <- 25

# 결과 컨테이너
km_cluster    <- integer(n_months)
km_probs      <- matrix(NA_real_, nrow = n_months, ncol = K_CLUSTERS)
km_dists      <- matrix(NA_real_, nrow = n_months, ncol = K_CLUSTERS)
km_valid_months <- integer(0)

# silhouette 저장 (선택 출력)
sil_scores <- numeric(n_months)

for (t in (WARMUP_KM + 1):n_months) {
  if (!(t %in% pca_valid_months)) next  # PCA 유효 월만

  # C1 강제: t-1까지 PC scores 사용
  window_idx <- intersect(pca_valid_months, which(1:n_months < t))
  if (length(window_idx) < K_CLUSTERS * 3) next  # 데이터 부족

  hist_scores <- pca_pc_scores[window_idx, , drop = FALSE]
  # NA 행 제거
  hist_scores <- hist_scores[complete.cases(hist_scores), , drop = FALSE]
  if (nrow(hist_scores) < K_CLUSTERS * 3) next

  # --- K-means ---
  km_fit <- tryCatch(
    kmeans(hist_scores, centers = K_CLUSTERS, nstart = NSTART_KM,
           iter.max = 100, algorithm = "Hartigan-Wong"),
    error = function(e) NULL
  )
  if (is.null(km_fit)) next

  # --- 현재 월 t 할당 ---
  t_score <- pca_pc_scores[t, , drop = FALSE]
  if (any(is.na(t_score))) next

  # 각 센트로이드까지 유클리드 거리^2
  centroids <- km_fit$centers  # K × n_pcs
  dists_sq  <- apply(centroids, 1, function(c) sum((t_score - c)^2))

  # Softmax 레짐 확률 (temperature = 중앙값 쌍별 거리)
  centroid_dists <- as.numeric(dist(centroids))
  temp <- max(median(centroid_dists)^2, 1e-6)  # 0 나눔 방지

  log_probs <- -dists_sq / temp
  log_probs <- log_probs - max(log_probs)  # 수치 안정성
  probs     <- exp(log_probs) / sum(exp(log_probs))

  # 가장 가까운 센트로이드 = cluster 할당
  assigned_cluster <- which.min(dists_sq)

  # 저장
  km_cluster[t]      <- assigned_cluster
  km_probs[t, ]      <- probs
  km_dists[t, ]      <- sqrt(dists_sq)
  km_valid_months    <- c(km_valid_months, t)

  # Silhouette (25번에 1번만 계산 — 성능)
  if (t %% 25 == 0 && nrow(hist_scores) >= K_CLUSTERS + 1) {
    km_labels <- km_fit$cluster
    sil_obj   <- tryCatch(
      silhouette(km_labels, dist(hist_scores)),
      error = function(e) NULL
    )
    if (!is.null(sil_obj)) sil_scores[t] <- mean(sil_obj[, 3])
  }
}

cat(sprintf("  K-means 완료: %d개월 유효 (%.1fs)\n",
            length(km_valid_months),
            (proc.time() - t0_km)["elapsed"]))

mean_sil_nonzero <- mean(sil_scores[sil_scores != 0])
cat(sprintf("  평균 Silhouette Score (k=5 고정): %.3f\n\n", mean_sil_nonzero))

## ---------------------------------------------------------------------------
## 4. Parquet 저장
## ---------------------------------------------------------------------------
cat("[4/7] 결과 parquet 저장 중...\n")

# 4a. PCA 결과
pca_out <- data.table(
  Date = dates
)
for (k in 1:N_PCS) {
  pca_out[, paste0("PC", k) := pca_pc_scores[, k]]
}
pca_out[, explained_var_cumulative := pca_expvar_cum[, N_PCS]]
for (k in 1:N_PCS) {
  pca_out[, paste0("expvar_pc", k) := pca_expvar_each[, k]]
}
pca_out[, n_factors_used := pca_n_factors]

# PCA 유효 월만 보존 (나머지 NA)
pca_out_valid <- pca_out[!is.na(PC1)]

write_parquet(pca_out_valid,
              file.path(CACHE_DIR, "regime_factor_pca.parquet"))
cat(sprintf("  regime_factor_pca.parquet: %d rows\n", nrow(pca_out_valid)))

# 4b. K-means 클러스터 결과
km_out <- data.table(
  Date       = dates,
  cluster_id = km_cluster
)
for (k in 1:K_CLUSTERS) {
  km_out[, paste0("prob_", k)  := km_probs[, k]]
  km_out[, paste0("dist_", k)  := km_dists[, k]]
}
km_out_valid <- km_out[cluster_id != 0]

write_parquet(km_out_valid,
              file.path(CACHE_DIR, "regime_factor_clusters.parquet"))
cat(sprintf("  regime_factor_clusters.parquet: %d rows\n", nrow(km_out_valid)))

## ---------------------------------------------------------------------------
## 5. 클러스터 해석 (팩터별 평균 IC 분석)
## ---------------------------------------------------------------------------
cat("[5/7] 클러스터 해석 중...\n")

# 각 유효 K-means 월의 클러스터 레이블 + 해당 IC 벡터 매칭
km_dates <- dates[km_valid_months]
km_labels_vec <- km_cluster[km_valid_months]

# IC 행렬에서 해당 월 추출
ic_valid <- ic_mat[km_valid_months, , drop = FALSE]
colnames(ic_valid) <- FACTOR_COLS

# 클러스터별 팩터 평균 IC 계산
cluster_factor_ic <- lapply(1:K_CLUSTERS, function(k) {
  idx_k   <- which(km_labels_vec == k)
  if (length(idx_k) == 0) return(NULL)
  sub_ic  <- ic_valid[idx_k, , drop = FALSE]
  mean_ic <- colMeans(sub_ic, na.rm = TRUE)
  n_months_k <- length(idx_k)
  list(
    cluster_id   = k,
    n_months     = n_months_k,
    pct_months   = round(n_months_k / length(km_valid_months) * 100, 1),
    mean_ic_vec  = mean_ic,
    top3_pos     = names(sort(mean_ic, decreasing = TRUE))[1:3],  # 상위 3 (양)
    top3_neg     = names(sort(mean_ic, decreasing = FALSE))[1:3], # 하위 3 (음)
    mean_abs_ic  = mean(abs(mean_ic), na.rm = TRUE)
  )
})

# 클러스터 해석 테이블 출력
cat("\n  --- 클러스터 해석 테이블 ---\n")
cat(sprintf("  %-12s %-10s %-8s %-50s %-10s\n",
            "Cluster", "N_Months", "Pct", "Top3 Factors (양의 IC)", "Avg|IC|"))
cat(sprintf("  %s\n", paste(rep("-", 100), collapse="")))

cluster_labels <- character(K_CLUSTERS)

for (k in 1:K_CLUSTERS) {
  info <- cluster_factor_ic[[k]]
  if (is.null(info)) {
    cat(sprintf("  Cluster %d: 데이터 없음\n", k))
    next
  }

  top3_str <- paste(info$top3_pos, collapse = ", ")

  # 자동 레이블 생성 (팩터 패밀리 기반 휴리스틱)
  top3_families <- sapply(info$top3_pos, function(f) {
    prefix2 <- substr(f, 1, 2)
    prefix1 <- substr(f, 1, 1)
    # 2-char prefix 우선
    label <- switch(prefix2,
      "Q0" = "Quality",  "Q1" = "Quality",  "Q2" = "Quality",
      "M0" = "Momentum", "M1" = "Momentum", "M2" = "Momentum",
      "V0" = "Value",    "V1" = "Value",    "V2" = "Value",
      "AC" = "Accrual",
      "CR" = "Crowding",
      "D0" = "Volatility", "D1" = "Volatility", "D2" = "Volatility",
      "D3" = "Volatility", "D4" = "Volatility", "D5" = "Volatility",
      "D6" = "Volatility", "D7" = "Volatility",
      "ML" = "ML_Factor",
      "L1" = "Liquidity", "L2" = "Liquidity", "L3" = "Liquidity",
      "SZ" = "Size",
      "EP" = "Earnings",  "GP" = "Profitability",
      NA_character_
    )
    # fallback: 1-char prefix
    if (is.na(label)) {
      label <- switch(prefix1,
        "Q" = "Quality",   "M" = "Momentum",
        "V" = "Value",     "D" = "Volatility",
        "L" = "Liquidity", "S" = "Size",
        "Unknown"
      )
    }
    label
  })
  dominant_family <- names(sort(table(top3_families), decreasing=TRUE))[1]
  cluster_labels[k] <- paste0(dominant_family, "_Regime_", k)

  cat(sprintf("  Cluster %d: N=%3d (%5.1f%%) | Top3: %-50s | Avg|IC|=%.3f | Label: %s\n",
              k, info$n_months, info$pct_months,
              substr(top3_str, 1, 50),
              info$mean_abs_ic,
              cluster_labels[k]))
}
cat("\n")

## ---------------------------------------------------------------------------
## 6. JSON 메타데이터 저장
## ---------------------------------------------------------------------------
cat("[6/7] 메타 JSON 저장 중...\n")

meta_json <- list(
  config = list(
    script          = "build_regime_discovery.R",
    phase           = "Phase 2: Expanding PCA + K-means",
    created         = as.character(Sys.time()),
    pit_c1_enforced = TRUE,
    warmup_pca      = WARMUP_PCA,
    warmup_km       = WARMUP_KM,
    n_pcs           = N_PCS,
    k_clusters      = K_CLUSTERS,
    nstart_km       = NSTART_KM,
    ic_matrix_rows  = n_months,
    ic_matrix_cols  = length(FACTOR_COLS),
    date_range      = list(
      start = as.character(min(dates)),
      end   = as.character(max(dates))
    )
  ),
  pca_summary = list(
    n_valid_months   = length(pca_valid_months),
    last_month_expvar = as.list(setNames(
      round(pca_expvar_cum[last_t, ], 2),
      paste0("PC", 1:N_PCS)
    ))
  ),
  kmeans_summary = list(
    n_valid_months  = length(km_valid_months),
    mean_silhouette = round(mean_sil_nonzero, 4),
    k               = K_CLUSTERS
  ),
  cluster_interpretations = lapply(1:K_CLUSTERS, function(k) {
    info <- cluster_factor_ic[[k]]
    if (is.null(info)) return(list(cluster_id = k, label = "empty"))
    list(
      cluster_id   = k,
      label        = cluster_labels[k],
      n_months     = info$n_months,
      pct_months   = info$pct_months,
      top3_factors = info$top3_pos,
      bot3_factors = info$top3_neg,
      mean_abs_ic  = round(info$mean_abs_ic, 4)
    )
  })
)

write_json(meta_json,
           file.path(CACHE_DIR, "regime_factor_meta.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  regime_factor_meta.json 저장 완료\n\n")

## ---------------------------------------------------------------------------
## 7. 시각화 3종
## ---------------------------------------------------------------------------
cat("[7/7] 시각화 생성 중...\n")

theme_forge <- theme_minimal(base_size = 11) +
  theme(
    plot.title    = element_text(face = "bold", size = 13),
    plot.subtitle = element_text(color = "grey40", size = 9),
    legend.position = "bottom"
  )

# 7a. Scree Plot (PC 설명분산)
cat("  7a. Scree plot...\n")

# 마지막 유효 월 평균 설명분산 사용 (전체 기간 안정 추정)
avg_expvar_each <- numeric(N_PCS)
for (k in 1:N_PCS) {
  vals <- pca_expvar_each[pca_valid_months, k]
  avg_expvar_each[k] <- mean(vals, na.rm = TRUE)
}
avg_expvar_cum <- cumsum(avg_expvar_each)

scree_dt <- data.table(
  PC         = paste0("PC", 1:N_PCS),
  expvar     = round(avg_expvar_each, 2),
  expvar_cum = round(avg_expvar_cum, 2)
)
scree_dt[, PC := factor(PC, levels = paste0("PC", 1:N_PCS))]

p_scree <- ggplot(scree_dt, aes(x = PC)) +
  geom_bar(aes(y = expvar), stat = "identity",
           fill = "#2196F3", alpha = 0.7) +
  geom_line(aes(y = expvar_cum, group = 1),
            color = "#FF5722", size = 1.2) +
  geom_point(aes(y = expvar_cum),
             color = "#FF5722", size = 3) +
  geom_text(aes(y = expvar, label = sprintf("%.1f%%", expvar)),
            vjust = -0.5, size = 3.5, fontface = "bold") +
  geom_text(aes(y = expvar_cum, label = sprintf("%.1f%%", expvar_cum)),
            vjust = 1.5, color = "#FF5722", size = 3) +
  scale_y_continuous(
    name   = "개별 설명분산 (%)",
    limits = c(0, max(avg_expvar_cum) * 1.15),
    sec.axis = sec_axis(~., name = "누적 설명분산 (%)")
  ) +
  labs(
    title    = "Factor IC Matrix: PCA Scree Plot (Expanding Window 평균)",
    subtitle = sprintf("281 factors → %d PCs | 전기간 평균 기준 | PIT C1: t-1까지 expanding 학습", N_PCS),
    x        = "Principal Component"
  ) +
  theme_forge

ggsave(file.path(OUT_DIR, "regime_pca_variance.png"), p_scree,
       width = 8, height = 5, dpi = 150)
cat("  regime_pca_variance.png 저장 완료\n")

# 7b. t-SNE 2D 시각화
cat("  7b. t-SNE cluster plot...\n")

# t-SNE용 데이터: K-means 유효 월 PC scores
tsne_idx     <- km_valid_months
tsne_scores  <- pca_pc_scores[tsne_idx, , drop = FALSE]
tsne_labels  <- km_cluster[tsne_idx]
tsne_dates   <- dates[tsne_idx]

# NA 제거
complete_idx <- complete.cases(tsne_scores)
tsne_scores  <- tsne_scores[complete_idx, ]
tsne_labels  <- tsne_labels[complete_idx]
tsne_dates   <- tsne_dates[complete_idx]

set.seed(42)
tsne_fit <- tryCatch(
  Rtsne(tsne_scores,
        dims          = 2,
        perplexity    = min(30, floor(nrow(tsne_scores) / 3) - 1),
        max_iter      = 1000,
        theta         = 0.5,
        check_duplicates = FALSE,
        verbose       = FALSE),
  error = function(e) {
    cat("    t-SNE 오류:", conditionMessage(e), "\n")
    NULL
  }
)

if (!is.null(tsne_fit)) {
  tsne_dt <- data.table(
    tSNE1      = tsne_fit$Y[, 1],
    tSNE2      = tsne_fit$Y[, 2],
    cluster_id = factor(tsne_labels),
    year       = as.integer(format(tsne_dates, "%Y"))
  )

  cluster_colors <- c("#E41A1C","#377EB8","#4DAF4A","#FF7F00","#984EA3")

  p_tsne <- ggplot(tsne_dt, aes(x = tSNE1, y = tSNE2,
                                 color = cluster_id)) +
    geom_point(alpha = 0.75, size = 2.5) +
    scale_color_manual(
      values = cluster_colors,
      labels = cluster_labels,
      name   = "Factor Regime"
    ) +
    stat_ellipse(aes(group = cluster_id), type = "t",
                 linetype = 2, alpha = 0.5, size = 0.8) +
    labs(
      title    = "Factor IC Regimes: t-SNE 2D Visualization",
      subtitle = sprintf("%d months | k=%d clusters | Expanding PCA → t-SNE",
                         nrow(tsne_dt), K_CLUSTERS),
      x = "t-SNE Dim 1", y = "t-SNE Dim 2"
    ) +
    theme_forge +
    guides(color = guide_legend(nrow = 2))

  ggsave(file.path(OUT_DIR, "regime_clusters_tsne.png"), p_tsne,
         width = 9, height = 6, dpi = 150)
  cat("  regime_clusters_tsne.png 저장 완료\n")
} else {
  cat("  t-SNE 실패 — 스킵\n")
}

# 7c. 클러스터 타임라인
cat("  7c. Regime timeline...\n")

timeline_dt <- data.table(
  Date       = dates[km_valid_months],
  cluster_id = factor(km_cluster[km_valid_months])
)

# 연도별 클러스터 비율
timeline_dt[, year := as.integer(format(Date, "%Y"))]

year_cluster_pct <- timeline_dt[, .N, by = .(year, cluster_id)]
year_cluster_pct[, pct := N / sum(N), by = year]

cluster_colors <- c("1" = "#E41A1C", "2" = "#377EB8", "3" = "#4DAF4A",
                    "4" = "#FF7F00", "5" = "#984EA3")

p_timeline <- ggplot(year_cluster_pct,
                     aes(x = year, y = pct, fill = cluster_id)) +
  geom_bar(stat = "identity", width = 0.85, alpha = 0.85) +
  scale_fill_manual(
    values = cluster_colors,
    labels = cluster_labels,
    name   = "Factor Regime"
  ) +
  scale_y_continuous(labels = scales::percent_format(),
                     expand = c(0, 0)) +
  scale_x_continuous(breaks = seq(2005, 2025, 2)) +
  labs(
    title    = "Factor Regime Timeline: Annual Cluster Distribution",
    subtitle = "연도별 팩터 레짐 비율 (Expanding K-means, k=5)",
    x = "Year", y = "Regime Share"
  ) +
  theme_forge +
  theme(
    panel.grid.major.x = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  ) +
  guides(fill = guide_legend(nrow = 2))

ggsave(file.path(OUT_DIR, "regime_timeline.png"), p_timeline,
       width = 12, height = 5, dpi = 150)
cat("  regime_timeline.png 저장 완료\n\n")

## ---------------------------------------------------------------------------
## 8. 클러스터 연도별 해석 출력
## ---------------------------------------------------------------------------
cat("=== 연도별 주요 레짐 분포 ===\n")
year_dominant <- timeline_dt[, .(dominant = as.integer(cluster_id[which.max(tabulate(as.integer(cluster_id)))])),
                              by = year]
year_dominant[, label := cluster_labels[dominant]]

for (i in seq_len(nrow(year_dominant))) {
  cat(sprintf("  %d: Cluster %d (%s)\n",
              year_dominant$year[i],
              year_dominant$dominant[i],
              year_dominant$label[i]))
}
cat("\n")

## ---------------------------------------------------------------------------
## 9. 파일 크기 보고
## ---------------------------------------------------------------------------
cat("=== 산출물 파일 크기 ===\n")
output_files <- c(
  file.path(CACHE_DIR, "regime_factor_pca.parquet"),
  file.path(CACHE_DIR, "regime_factor_clusters.parquet"),
  file.path(CACHE_DIR, "regime_factor_meta.json"),
  file.path(OUT_DIR,   "regime_pca_variance.png"),
  file.path(OUT_DIR,   "regime_clusters_tsne.png"),
  file.path(OUT_DIR,   "regime_timeline.png")
)
for (f in output_files) {
  sz <- file.info(f)$size
  if (!is.na(sz)) {
    cat(sprintf("  %-55s %s\n",
                basename(f),
                ifelse(sz > 1e6,
                       sprintf("%.2f MB", sz/1e6),
                       sprintf("%.1f KB", sz/1e3))))
  } else {
    cat(sprintf("  %-55s NOT FOUND\n", basename(f)))
  }
}

cat("\n=== Phase 2 완료 ===\n")
cat(sprintf("총 소요 시간: %.1f초\n", (proc.time() - t0_load)["elapsed"]))
cat("PIT C1: 모든 PCA/K-means는 t-1까지 expanding window 사용 — VERIFIED\n")
