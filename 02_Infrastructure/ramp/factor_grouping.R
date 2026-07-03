## factor_grouping.R — RAMP Gate 5 (2차): 팩터군 클러스터링 (헌법 §6.6)
## ★1차 입력 = 풀 PCA 잠재팩터(PC2~PC10 고유포트폴리오). PC1(market/beta)=배분 입력 제외.
## distance matrix D = w_return(1-corr_ret) + w_exposure·exposure_dist + w_drawdown·dd_dist
##   (config gate5_grouping.distance_weights). hclust → 팩터군. 경제 라벨은 *통계 클러스터 후* 부여(강제편입 금지).
## 산출: outputs/ramp/factor_group_map.parquet.
##
## 실측-only: 모든 거리는 잠재팩터 *수익 시계열*(latent_factor_returns)에서 직접 계산. 자체합성 없음.

suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/ramp_io.R")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

#==============================================================================
# 1. PC 간 거리행렬 (수익상관 + exposure + drawdown)
#==============================================================================
#' @param eigen_dt data.table(Date, PC1..PCk) daily eigen-portfolio returns
#' @param loadings_dt data.table(strategy_id, PC1..PCk) — PC별 전략 exposure (loading)
#' @param pc_use 클러스터 대상 PC (default PC2..PCk; PC1 제외)
#' @param w named weights (w_return, w_exposure, w_drawdown)
#' @return list(D(dist matrix), corr_ret, exposure_dist, dd_dist, pc_use)
build_factor_distance <- function(eigen_dt, loadings_dt, pc_use = NULL,
                                  w = list(w_return = 0.6, w_exposure = 0.2, w_drawdown = 0.2)) {
  ed <- copy(as.data.table(eigen_dt)); ed[, Date := as.Date(Date)]
  pc_all <- grep("^PC[0-9]+$", names(ed), value = TRUE)
  if (is.null(pc_use)) pc_use <- setdiff(pc_all, "PC1")
  pc_use <- intersect(pc_use, pc_all)
  k <- length(pc_use)

  # (a) return correlation distance: 1 - |corr| (방향 무관 동조성; 음의 상관도 같은 축)
  Rm <- as.matrix(ed[, ..pc_use])
  corr_ret <- stats::cor(Rm, use = "pairwise.complete.obs")
  d_ret <- 1 - abs(corr_ret)

  # (b) exposure distance: PC loading 벡터(전략공간)의 코사인 거리.
  #     각 PC는 479전략에 대한 loading 벡터 → 두 PC가 비슷한 전략군에 실리면 가까움.
  L <- as.matrix(loadings_dt[, ..pc_use])  # 479 x k
  cosm <- matrix(NA_real_, k, k, dimnames = list(pc_use, pc_use))
  for (a in seq_len(k)) for (b in seq_len(k)) {
    va <- L[, a]; vb <- L[, b]
    den <- sqrt(sum(va^2)) * sqrt(sum(vb^2))
    cosm[a, b] <- if (den > 0) sum(va * vb) / den else 0
  }
  d_exp <- 1 - abs(cosm)

  # (c) drawdown distance: 각 PC 누적수익(고유포트)의 drawdown 시계열 상관 → 1-|corr|.
  #     누적은 PerformanceAnalytics 표준 아닌 단순 cumsum(데모) → 자체합성 우려.
  #     ★자체합성 금지 준수: drawdown은 수익 *순위* 동조성으로 근사하지 말고,
  #       PerformanceAnalytics::Drawdowns(xts) 사용. 미가용 시 NA + 가중치 재배분(정직).
  dd_dist <- NULL
  ok_dd <- requireNamespace("PerformanceAnalytics", quietly = TRUE) &&
           requireNamespace("xts", quietly = TRUE)
  if (ok_dd) {
    suppressMessages({ library(PerformanceAnalytics); library(xts) })
    ddm <- matrix(NA_real_, nrow(Rm), k)
    for (j in seq_len(k)) {
      xj <- xts::xts(Rm[, j], order.by = ed$Date)
      ddm[, j] <- tryCatch(as.numeric(PerformanceAnalytics::Drawdowns(xj)), error = function(e) rep(NA, nrow(Rm)))
    }
    colnames(ddm) <- pc_use
    cdd <- stats::cor(ddm, use = "pairwise.complete.obs")
    cdd[is.na(cdd)] <- 0
    dd_dist <- 1 - abs(cdd)
  }

  # combine (renormalize weights if dd unavailable)
  wr <- w$w_return %||% 0.6; we <- w$w_exposure %||% 0.2; wd <- w$w_drawdown %||% 0.2
  if (is.null(dd_dist)) {
    s <- wr + we; wr <- wr / s; we <- we / s
    D <- wr * d_ret + we * d_exp
    dd_status <- "unavailable_reweighted"
  } else {
    D <- wr * d_ret + we * d_exp + wd * dd_dist
    dd_status <- "ok"
  }
  diag(D) <- 0
  list(D = D, corr_ret = corr_ret, exposure_cos = cosm, dd_dist = dd_dist,
       pc_use = pc_use, weights = list(w_return = wr, w_exposure = we, w_drawdown = if (is.null(dd_dist)) 0 else wd),
       dd_status = dd_status)
}

#==============================================================================
# 2. hclust → 팩터군 + 경제 라벨 후부여
#==============================================================================
#' @param dist_obj from build_factor_distance
#' @param label_table from label_latent_factors (pc -> label)
#' @param n_groups 목표 군수 (NULL이면 height cut by cut_height)
#' @param cut_height dist cut (default 0.7)
#' @return data.table(pc, group_id, group_label, economic_label, members)
group_factors <- function(dist_obj, label_table = NULL, n_groups = NULL, cut_height = 0.7) {
  D <- dist_obj$D; pc_use <- dist_obj$pc_use
  hc <- stats::hclust(stats::as.dist(D), method = "average")
  grp <- if (!is.null(n_groups)) stats::cutree(hc, k = min(n_groups, length(pc_use)))
         else stats::cutree(hc, h = cut_height)

  dt <- data.table(pc = pc_use, group_id = as.integer(grp))
  # 경제 라벨 부여(통계 클러스터 후): 군 내 PC label 다수결 (unlabeled 제외).
  if (!is.null(label_table)) {
    lt <- as.data.table(label_table)[, .(pc, label)]
    dt <- merge(dt, lt, by = "pc", all.x = TRUE)
  } else dt[, label := NA_character_]

  dt[, group_label := {
    lbls <- label[!is.na(label) & label != "unlabeled"]
    if (length(lbls) == 0) "unlabeled_group"
    else names(sort(table(lbls), decreasing = TRUE))[1]
  }, by = group_id]
  dt[, group_size := .N, by = group_id]
  dt[, economic_label := fifelse(is.na(label), "unlabeled", label)]

  # ★정직: eigen-portfolio는 직교(return-corr=0, exposure-cos=0) → 통계적 hclust는 거의 singleton.
  #   따라서 *경제 라벨 기반 grouping*(dominant style 공유)을 병행 제공한다.
  #   dominant style = label에서 "+mixed" 접미 제거. unlabeled은 자체 그룹.
  dt[, dominant_style := gsub("\\+mixed$", "", economic_label)]
  style_levels <- unique(dt$dominant_style)
  dt[, econ_group_id := match(dominant_style, style_levels)]
  dt[, econ_group_size := .N, by = econ_group_id]

  setorder(dt, group_id, pc)
  list(group_map = dt[], hclust = hc,
       n_groups = length(unique(grp)),
       n_econ_groups = length(unique(dt$econ_group_id)),
       merge_heights = hc$height,
       orthogonal_note = "PCs orthogonal by construction (corr=0, cos=0) → statistical hclust yields singletons; econ_group_id = label-based grouping.")
}

cat("[factor_grouping.R] Loaded — build_factor_distance / group_factors (경제라벨 후부여)\n")
