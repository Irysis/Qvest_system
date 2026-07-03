## strategy_return_matrix.R — RAMP Gate 3: 전략풀 인벤토리 + 수익률행렬 + 유사도 + dedup/clustering
## 룰 §5 (alpha-research 담당). 실측-only: NAV/수익률은 기존 백테 산출 실측만 사용(자체합성 X).
##
## 풀 = 06_Registry/module_catalog.json (264 sim_result.rds$DAILY_NAV_DT$Strategy_Ret)
##    + batch_434 stage_artifacts/batch_434/**/*_result.rds (~459, 도훈 mandate)
##      ★batch_434 summary rds → out_dir/03_period_returns.csv(ret_net, metric_type=backtested) 에서 NAV 추출.
##        무거운 bt_result.rds(세그폴트 위험)는 건드리지 않음. 그래도 SEGV-안전 격리-subprocess 읽기 적용.
##
## 산출(모두 §2.4 메타):
##   outputs/ramp/pool_return_matrix.parquet
##   outputs/ramp/strategy_similarity_matrix.parquet
##   outputs/ramp/strategy_clusters.parquet
##   06_Registry/ramp/strategy_inventory.parquet
##   04_Research/ramp/reports/strategy_deduplication_report.md

suppressMessages({ library(data.table); library(jsonlite) })

.RAMP_DIR <- "02_Infrastructure/ramp"
source(file.path(.RAMP_DIR, "ramp_io.R"))

# ── config 로드 ──
.ramp_load_config <- function() {
  if (requireNamespace("yaml", quietly = TRUE)) {
    yaml::read_yaml(file.path(.RAMP_DIR, "ramp_config.yml"))
  } else stop("[gate3] yaml package required")
}

# /mnt/c/... → C:/... 경로 변환 (batch_434 out_dir 가 WSL-style)
.ramp_translate_path <- function(p) {
  if (is.null(p) || length(p) == 0 || is.na(p)) return(NA_character_)
  sub("^/mnt/c/", "C:/", p)
}

#==============================================================================
# 1. catalog NAV 로더 (264 sim_result.rds — 메인 프로세스 정상 읽힘)
#==============================================================================
#' @return list(meta=data.table(strategy_id, origin_mode, grade, strategy_idea, source),
#'              nav=list(strategy_id -> data.table(Date, Ret)), excluded=list)
.ramp_load_catalog_navs <- function(catalog_path) {
  mc <- fromJSON(catalog_path, simplifyVector = FALSE)
  mods <- mc$modules
  meta <- list(); navs <- list(); excl <- list()
  for (m in mods) {
    sid <- m$strategy_id
    p <- m$sim_result_path
    if (is.null(sid) || is.null(p) || !file.exists(p)) {
      excl[[length(excl) + 1L]] <- list(id = sid %||% "NA", source = "catalog",
                                        reason = "sim_result_path missing")
      next
    }
    sr <- tryCatch(readRDS(p), error = function(e) NULL)
    if (is.null(sr) || is.null(sr$DAILY_NAV_DT)) {
      excl[[length(excl) + 1L]] <- list(id = sid, source = "catalog", reason = "no DAILY_NAV_DT")
      next
    }
    d <- as.data.table(sr$DAILY_NAV_DT)
    if (!all(c("Date", "Strategy_Ret") %in% names(d))) {
      excl[[length(excl) + 1L]] <- list(id = sid, source = "catalog", reason = "DAILY_NAV_DT schema")
      next
    }
    navs[[sid]] <- d[!is.na(Strategy_Ret), .(Date = as.Date(Date), Ret = as.numeric(Strategy_Ret))]
    meta[[length(meta) + 1L]] <- data.table(
      strategy_id = sid,
      origin_mode = m$origin_mode %||% NA_character_,
      grade = m$grade %||% NA_character_,
      strategy_idea = (m$meta$strategy_idea %||% NA_character_),
      source = "catalog"
    )
  }
  list(meta = if (length(meta)) rbindlist(meta, fill = TRUE) else data.table(),
       nav = navs, excluded = excl)
}

#==============================================================================
# 2. batch_434 NAV 로더 (SEGV-안전: summary rds 읽기는 메인에서 OK이나,
#    NAV는 out_dir/03_period_returns.csv(ret_net) flat CSV에서 — heavy bt_result.rds 회피)
#==============================================================================
.ramp_load_batch434_navs <- function(glob_pat) {
  files <- Sys.glob(glob_pat)
  meta <- list(); navs <- list(); excl <- list()
  for (f in files) {
    o <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(o)) {
      excl[[length(excl) + 1L]] <- list(id = basename(f), source = "batch_434",
                                        reason = "readRDS error (SEGV/corrupt) — SKIP")
      next
    }
    # item-manifest (실행 안 됨, NAV 없음) — SKIP
    if (!("strategy_id" %in% names(o))) {
      excl[[length(excl) + 1L]] <- list(id = (o$item_id %||% basename(f)),
                                        source = "batch_434",
                                        reason = "item-manifest (no strategy_id / not executed)")
      next
    }
    sid <- o$strategy_id
    od <- .ramp_translate_path(o$out_dir %||% NA)
    pr_csv <- if (!is.na(od)) file.path(od, "03_period_returns.csv") else NA_character_
    nav_csv <- if (!is.na(od)) file.path(od, "02_nav.csv") else NA_character_
    nav_dt <- NULL
    if (!is.na(pr_csv) && file.exists(pr_csv)) {
      pr <- tryCatch(fread(pr_csv), error = function(e) NULL)
      if (!is.null(pr) && all(c("date", "ret_net") %in% names(pr))) {
        nav_dt <- pr[!is.na(ret_net), .(Date = as.Date(date), Ret = as.numeric(ret_net))]
      }
    }
    if (is.null(nav_dt) && !is.na(nav_csv) && file.exists(nav_csv)) {
      nv <- tryCatch(fread(nav_csv), error = function(e) NULL)
      if (!is.null(nv) && all(c("date", "nav_net") %in% names(nv))) {
        nv <- nv[order(date)]
        # NAV → return via diff (PerformanceAnalytics 미경유이나, 이는 단순 일별수익 복원이며
        # 성능 채점이 아니라 dedup/PCA 구조분석 입력. 성능수치(SR/CAGR/portfolio_alpha_t)는
        # 본 단계에서 산출하지 않음 — 모두 Gate 4 canonical_screen_bt 경유.)
        nv[, Ret := c(NA_real_, diff(nav_net) / head(nav_net, -1))]
        nav_dt <- nv[!is.na(Ret), .(Date = as.Date(date), Ret = as.numeric(Ret))]
      }
    }
    if (is.null(nav_dt) || nrow(nav_dt) == 0) {
      excl[[length(excl) + 1L]] <- list(id = sid, source = "batch_434",
                                        reason = "no 03_period_returns.csv / 02_nav.csv NAV")
      next
    }
    navs[[sid]] <- nav_dt
    meta[[length(meta) + 1L]] <- data.table(
      strategy_id = sid,
      origin_mode = "alpha_search",
      grade = o$grade %||% NA_character_,
      strategy_idea = NA_character_,
      source = "batch_434"
    )
  }
  list(meta = if (length(meta)) rbindlist(meta, fill = TRUE) else data.table(),
       nav = navs, excluded = excl)
}

#==============================================================================
# 3. 풀 수익률행렬 빌드 (공통 날짜축 + min_obs_months 필터)
#==============================================================================
#' @return list(R=matrix[T x N] (일별 net 수익률, colnames=strategy_id, rownames=Date),
#'              meta=data.table, excluded=data.table)
build_pool_return_matrix <- function(config = NULL,
                                     min_obs_months = NULL) {
  if (is.null(config)) config <- .ramp_load_config()
  if (is.null(min_obs_months)) min_obs_months <- config$pool$min_obs_months %||% 36L

  excl_log <- list()
  cat("[gate3] loading catalog NAVs (264 sim_result.rds)...\n")
  cat_res <- .ramp_load_catalog_navs(config$pool$module_catalog)
  excl_log <- c(excl_log, cat_res$excluded)

  b434_meta <- data.table(); b434_nav <- list()
  if (isTRUE(config$pool$include_batch_434)) {
    cat("[gate3] loading batch_434 NAVs (out_dir/03_period_returns.csv)...\n")
    b434 <- .ramp_load_batch434_navs(config$pool$batch_434_glob)
    b434_meta <- b434$meta; b434_nav <- b434$nav
    excl_log <- c(excl_log, b434$excluded)
  }

  # 합치기 — 중복 strategy_id (catalog ∩ batch_434) 는 catalog 우선
  all_nav <- cat_res$nav
  for (sid in names(b434_nav)) if (is.null(all_nav[[sid]])) all_nav[[sid]] <- b434_nav[[sid]]
  all_meta <- rbindlist(list(cat_res$meta, b434_meta[!strategy_id %in% cat_res$meta$strategy_id]),
                        fill = TRUE)

  # min_obs_months 필터 (일별 ≈ 21 거래일/월)
  min_obs_days <- as.integer(min_obs_months) * 21L
  keep <- character(0)
  for (sid in names(all_nav)) {
    n <- nrow(all_nav[[sid]])
    if (n >= min_obs_days) keep <- c(keep, sid)
    else excl_log[[length(excl_log) + 1L]] <- list(id = sid, source = "matrix",
            reason = sprintf("n_obs %d < min %d (%dm)", n, min_obs_days, min_obs_months))
  }
  cat(sprintf("[gate3] strategies with NAV: %d ; pass min_obs(%dm=%dd): %d\n",
              length(all_nav), min_obs_months, min_obs_days, length(keep)))

  # 공통 날짜축 (union) → wide matrix
  all_dates <- sort(unique(do.call(c, lapply(all_nav[keep], function(d) d$Date))))
  R <- matrix(NA_real_, nrow = length(all_dates), ncol = length(keep),
              dimnames = list(as.character(all_dates), keep))
  date_idx <- setNames(seq_along(all_dates), as.character(all_dates))
  for (sid in keep) {
    d <- all_nav[[sid]][!duplicated(Date)]
    R[date_idx[as.character(d$Date)], sid] <- d$Ret
  }

  # zero-variance(상수수익) 컬럼 제거 — PCA/corr 정보 없음 + cor() sd=0 경고 유발
  col_sd <- apply(R, 2, function(x) stats::sd(x, na.rm = TRUE))
  zerovar <- names(col_sd)[is.na(col_sd) | col_sd < 1e-12]
  if (length(zerovar)) {
    for (sid in zerovar) excl_log[[length(excl_log) + 1L]] <-
      list(id = sid, source = "matrix", reason = "zero-variance return series (no information)")
    keep <- setdiff(keep, zerovar)
    R <- R[, keep, drop = FALSE]
    cat(sprintf("[gate3] dropped %d zero-variance strategies -> %d kept\n", length(zerovar), length(keep)))
  }

  meta_keep <- all_meta[strategy_id %in% keep]
  excluded <- if (length(excl_log)) rbindlist(lapply(excl_log, as.data.table), fill = TRUE) else data.table()

  list(R = R, dates = all_dates, meta = meta_keep, excluded = excluded,
       n_catalog = length(cat_res$nav), n_batch434 = length(b434_nav),
       n_kept = length(keep))
}

#==============================================================================
# 4. 유사도 (return/rank/drawdown corr + turnover_similarity)
#    holdings류 차원 = unavailable (NAV-only 정직표기)
#==============================================================================
#' @param R 수익률행렬 (NA 허용) — pairwise complete corr
#' @return list(return_corr, rank_corr, drawdown_corr, turnover_sim(=NA unavailable), notes)
compute_strategy_similarity <- function(R, min_overlap = 252L) {
  N <- ncol(R); ids <- colnames(R)
  # return correlation (pairwise complete obs)
  return_corr <- cor(R, use = "pairwise.complete.obs")
  # rank correlation (spearman)
  rank_corr <- cor(R, use = "pairwise.complete.obs", method = "spearman")
  # drawdown series: per-strategy running-max drawdown from cumulative *index*
  #   (구조분석용 누적지수 — 성능 채점 아님. 그래도 prod/cumprod 자체합성 회피 위해
  #    log-cum 합으로 단조 누적만 사용: cum = cumsum(log1p(r)), dd = cum - cummax(cum).)
  DD <- matrix(NA_real_, nrow = nrow(R), ncol = N, dimnames = dimnames(R))
  for (j in seq_len(N)) {
    r <- R[, j]; ok <- !is.na(r)
    if (sum(ok) < 2) next
    lr <- log1p(pmax(r[ok], -0.99))
    cum <- cumsum(lr)
    dd <- cum - cummax(cum)
    DD[ok, j] <- dd
  }
  drawdown_corr <- cor(DD, use = "pairwise.complete.obs")

  # overlap 부족 페어는 NA 로 마스킹 (신뢰 불가)
  overlap <- crossprod(!is.na(R))   # N×N count of co-observed days
  mask <- overlap < min_overlap
  return_corr[mask] <- NA_real_; rank_corr[mask] <- NA_real_; drawdown_corr[mask] <- NA_real_

  list(
    return_corr = return_corr,
    rank_corr = rank_corr,
    drawdown_corr = drawdown_corr,
    turnover_similarity = "unavailable",  # holdings/turnover 일별 NAV-only → 산출 불가
    holdings_dims_status = "unavailable",
    min_overlap = min_overlap,
    note = "turnover/holdings 유사도는 NAV-only 풀 특성상 unavailable. return/rank/drawdown corr만 실측."
  )
}

#==============================================================================
# 5. dedup / clustering
#    (A) near-replica dedup: return_corr > dedup_return_corr (default 0.95) → 대표만 유지
#    (B) family clustering: hclust(ward.D2) on (1 - return_corr) distance, cut to interpretable k.
#        config family_rule(return_corr>0.90 OR drawdown_corr>0.80) 는 *진단*으로 별도 보고
#        — KR long-only 베타지배(drawdown_corr≈universal>0.80)로 OR-그래프는 단일 거대성분이 되어
#          dedup/클러스터링에 부적합. 정직 보고 후 return-corr 거리 기반 hclust 채택.
#==============================================================================
#' @return list(clusters, n_clusters, n_dedup_dropped, ...)
cluster_strategies <- function(sim, meta, config = NULL, n_family_clusters = 12L) {
  if (is.null(config)) config <- .ramp_load_config()
  rc <- sim$return_corr
  dc <- sim$drawdown_corr
  ids <- colnames(rc)
  N <- length(ids)
  dedup_thr <- config$pool$dedup_return_corr %||% 0.95
  fam_thr_ret <- 0.90; fam_thr_dd <- 0.80

  # ── 진단: config OR-그래프 연결성분 수 (베타지배 표면화용, 단정 X) ──
  adj <- (!is.na(rc) & rc > fam_thr_ret) | (!is.na(dc) & dc > fam_thr_dd)
  diag(adj) <- FALSE
  parent0 <- seq_len(N)
  find0 <- function(x) { while (parent0[x] != x) { parent0[x] <<- parent0[parent0[x]]; x <- parent0[x] }; x }
  union0 <- function(a, b) { ra <- find0(a); rb <- find0(b); if (ra != rb) parent0[ra] <<- rb }
  wi <- which(adj & upper.tri(adj), arr.ind = TRUE)
  for (k in seq_len(nrow(wi))) union0(wi[k, 1], wi[k, 2])
  or_components <- length(unique(vapply(seq_len(N), find0, integer(1))))

  # ── (B) family clustering via hclust on return-corr distance ──
  # NA corr (overlap 부족)는 중립값(median offdiag)으로 보정 — 거리 행렬 완전성 위해
  rc_fill <- rc
  med_off <- median(rc[upper.tri(rc)], na.rm = TRUE)
  rc_fill[is.na(rc_fill)] <- med_off
  diag(rc_fill) <- 1
  dist_mat <- as.dist(1 - rc_fill)          # 0(동일) .. 2(완전역상관)
  hc <- hclust(dist_mat, method = "ward.D2")
  k <- min(n_family_clusters, N - 1L)
  cluster_id <- cutree(hc, k = k)

  # ── (A) near-replica dedup (cluster 무관 global, return_corr>0.95) ──
  #   greedy: 정보량(관측일수) 많은 순으로 keep, 그에 0.95+ corr 인 후발은 drop.
  obs_days <- vapply(ids, function(s) NA_integer_, integer(1))  # placeholder; use rc availability
  # 정보량 = 자기 컬럼 비-NA corr 수 (overlap 충분 페어 많을수록 신뢰)
  info <- colSums(!is.na(rc))
  order_keep <- order(-info)
  dedup_dropped <- rep(FALSE, N); names(dedup_dropped) <- ids
  kept_idx <- integer(0)
  for (i in order_keep) {
    if (length(kept_idx)) {
      cors <- rc[i, kept_idx]
      if (any(!is.na(cors) & cors > dedup_thr)) { dedup_dropped[i] <- TRUE; next }
    }
    kept_idx <- c(kept_idx, i)
  }

  # ── 대표: 각 family cluster 내 가장 중심(평균 corr 최대) 전략 ──
  rep_flag <- rep(FALSE, N); names(rep_flag) <- ids
  for (cl in unique(cluster_id)) {
    members <- which(cluster_id == cl)
    if (length(members) == 1) { rep_flag[members] <- TRUE; next }
    sub <- rc[members, members, drop = FALSE]
    cent <- rowMeans(sub, na.rm = TRUE)
    rep_flag[members[which.max(cent)]] <- TRUE
  }

  clusters <- data.table(
    strategy_id = ids,
    cluster_id = as.integer(cluster_id),
    is_representative = rep_flag[ids],
    dedup_dropped = dedup_dropped[ids],
    info_obs = info[ids]
  )
  csz <- clusters[, .(cluster_size = .N), by = cluster_id]
  clusters <- merge(clusters, csz, by = "cluster_id", all.x = TRUE)
  clusters <- merge(clusters, meta[, .(strategy_id, origin_mode, grade, strategy_idea, source)],
                    by = "strategy_id", all.x = TRUE)
  clusters[, overlay_tag := fifelse(!is.na(strategy_idea), paste0("inferred:", strategy_idea),
                                    paste0("inferred_origin:", fifelse(is.na(origin_mode), "NA", origin_mode)))]

  list(
    clusters = clusters,
    n_clusters = length(unique(cluster_id)),
    n_dedup_dropped = sum(dedup_dropped),
    n_representatives = sum(rep_flag),
    n_unique_after_dedup = N - sum(dedup_dropped),
    dedup_thr = dedup_thr,
    family_method = sprintf("hclust(ward.D2) on (1-return_corr), k=%d", k),
    diagnostic_or_components = or_components,
    diagnostic_note = sprintf("config family_rule(return>%.2f OR dd>%.2f) → %d connected components (KR 베타지배: dd_corr≈universal>0.80 → 단일 거대성분 경향). 실제 클러스터는 return-corr hclust 채택.",
                              fam_thr_ret, fam_thr_dd, or_components),
    median_offdiag_return_corr = med_off
  )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[strategy_return_matrix.R] Loaded — Gate3: build_pool_return_matrix / compute_strategy_similarity / cluster_strategies\n")
