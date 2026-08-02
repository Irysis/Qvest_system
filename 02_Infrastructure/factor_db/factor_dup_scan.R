#==============================================================================
# factor_dup_scan.R — Factor DB 중복 스캐너 (registry 위생)
#
# 목적: 팩터 DB의 approved 팩터 집합에서 **같은 정보를 두 번 등록한 쌍**을 실측
#   열거한다. 중복 팩터는 (a) Ω(팩터 공분산) rank 결핍을 만들어 위험모델 추정을
#   전소시키고 (b) ICIR/relevance 선별에서 **이중 투표**한다.
#   적발 계기: WT-D20260802_003 risk 라운드 —
#   D01_IdioVol ~ R12_Idiosyncratic_Risk active-cor = 1.0000 (2팩터 drop 후 재추정).
#
# 두 basis 를 모두 측정한다 (같은 질문이 아니다):
#   * signal basis  — 월별 횡단면 Z_Score_Aligned 상관. "신호가 같은가"
#                     = registry de-dup 판단의 근거. C15 준수(load_month_factors 경유).
#   * deploy basis  — 팩터별 배포존 포트의 active 수익 시계열 상관. "배포 결과가
#                     같은가" = WT-003 이 본 면. outputs/ramp 패널을 읽는다.
#
# PIT: load_month_factors() 가 sig_date 별 expanding-window IC 로 방향정렬(C13)한
#   Z_Score_Aligned 만 사용한다. parquet 직접 read 없음(C15).
#
# 주 진입점:
#   scan_signal_dup(months, factor_names, ...)  -> data.table (쌍별 통계)
#   scan_deploy_dup(panel, ...)                 -> data.table (쌍별 통계)
#   classify_dup(pairs, exact_thr, near_thr)    -> verdict 라벨 부착
#
# 테스트: 08_Tests/hooks/test_factor_dup_scan.R (위반 주입 + 음성 대조)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

#' Wide Z-score matrix for one month, via the C15-safe connector.
#'
#' loader 를 인자로 받는 이유: 위반 주입 테스트가 합성 패널을 밀어넣을 수 있어야
#' 한다. 운영 기본값은 load_month_factors 이므로 C15 경계는 유지된다.
.fds_month_matrix <- function(sig_date, factor_names, loader, coverage_min,
                              rank_transform = FALSE) {
  dt <- loader(sig_date = sig_date, factor_names = factor_names,
               coverage_min = coverage_min)
  if (is.null(dt) || !nrow(dt)) return(NULL)
  dt <- as.data.table(dt)
  req <- c("Ticker", "Factor_Name", "Z_Score_Aligned")
  if (!all(req %in% names(dt))) {
    stop("[dup_scan] loader must return columns: ", paste(req, collapse = ", "))
  }
  W <- dcast(dt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  M <- as.matrix(W[, -1L, with = FALSE])
  rownames(M) <- W$Ticker
  if (rank_transform) {
    # 열별 rank 변환 후 Pearson = 공통 support 위의 Spearman.
    # ★필요한 이유: 서로 역수/단조변환인 쌍(V08_PSR=MC/Rev vs V20_SP=Rev/MC)은
    #   Pearson-on-Z 로는 |cor|<1 이지만 **순위가 동일**해 top-N 선별에서 같은
    #   포트를 만든다. deploy basis 가 이를 cor=1.0000 으로 드러냈다.
    cn <- colnames(M); rn <- rownames(M)
    M <- vapply(seq_len(ncol(M)), function(j) {
      v <- M[, j]; r <- rep(NA_real_, length(v)); k <- !is.na(v)
      if (any(k)) r[k] <- rank(v[k], ties.method = "average")
      r
    }, numeric(nrow(M)))
    # vapply 는 1열이어도 matrix 를 준다 (apply 는 vector 로 붕괴 -> ncol(NULL) 사고)
    M <- matrix(M, ncol = length(cn), dimnames = list(rn, cn))
  }
  M
}

#' Correlation matrix aligned onto a fixed factor universe.
#' 월마다 존재하는 팩터가 다르므로 고정 격자에 올려 누산한다.
.fds_cor_on_grid <- function(M, grid) {
  G <- matrix(NA_real_, nrow = length(grid), ncol = length(grid),
              dimnames = list(grid, grid))
  if (is.null(M) || ncol(M) < 2L) return(G)
  keep <- intersect(colnames(M), grid)
  if (length(keep) < 2L) return(G)
  Mk <- M[, keep, drop = FALSE]
  # 분산 0 / 전부 NA 열은 cor 이 NA 를 뱉는다 — 경고만 억제하고 NA 로 남긴다.
  Ck <- suppressWarnings(stats::cor(Mk, use = "pairwise.complete.obs"))
  G[keep, keep] <- Ck
  G
}

#' Pairwise count of jointly observed rows (min-obs 게이트용).
.fds_pair_nobs <- function(M, grid) {
  G <- matrix(0L, nrow = length(grid), ncol = length(grid),
              dimnames = list(grid, grid))
  if (is.null(M) || ncol(M) < 2L) return(G)
  keep <- intersect(colnames(M), grid)
  if (length(keep) < 2L) return(G)
  A <- !is.na(M[, keep, drop = FALSE])
  storage.mode(A) <- "integer"
  G[keep, keep] <- crossprod(A)
  G
}

#==============================================================================
# scan_signal_dup() — 월별 횡단면 Z_Score_Aligned 상관 (2-pass)
#==============================================================================

#' @param months Date vector. 월별 signal date (월말 권장).
#' @param factor_names character. 스캔 대상 팩터. NULL = 월별 가용 전체.
#'   NULL 이면 grid 를 첫 통과에서 관측된 팩터 합집합으로 잡는다.
#' @param loader function(sig_date, factor_names, coverage_min) -> long dt.
#' @param min_obs integer. 그 달 쌍별 공통 관측 종목 수 하한. 미달 월은 결측 처리.
#' @param screen_thr numeric. 1-pass 후보 선별 문턱 (|cor| 이 어느 달에든 이 값을
#'   넘은 쌍만 2-pass 에서 정확 시계열을 보관). median > near_thr 인 쌍은 반드시
#'   어느 달엔가 near_thr 을 넘으므로, screen_thr <= near_thr 이면 누락이 없다.
#' @return data.table(factor_a, factor_b, n_months, median_cor, mean_cor,
#'   min_cor, max_cor, median_abs, frac_ge_099, frac_ge_095, sign_flips)
scan_signal_dup <- function(months,
                            factor_names = NULL,
                            loader = NULL,
                            coverage_min = 0.05,
                            min_obs = 30L,
                            screen_thr = 0.90,
                            rank_transform = FALSE,
                            verbose = TRUE) {

  if (is.null(loader)) {
    if (!exists("load_month_factors", mode = "function")) {
      stop("[dup_scan] load_month_factors() not loaded — source factor_db_connector.R first")
    }
    loader <- function(sig_date, factor_names, coverage_min) {
      load_month_factors(sig_date = sig_date, coverage_min = coverage_min,
                         factor_names = factor_names)
    }
  }
  months <- sort(as.Date(months))

  # ── grid 확정 ───────────────────────────────────────────────────────────
  grid <- factor_names
  if (is.null(grid)) {
    seen <- character(0)
    for (m in months) {
      Mi <- .fds_month_matrix(as.Date(m, origin = "1970-01-01"), NULL, loader,
                              coverage_min, rank_transform)
      if (!is.null(Mi)) seen <- union(seen, colnames(Mi))
    }
    grid <- seen
  }
  grid <- sort(unique(as.character(grid)))
  if (length(grid) < 2L) stop("[dup_scan] need >= 2 factors in grid, got ", length(grid))
  ng <- length(grid)

  # ── PASS 1: 누산 (평균 + 문턱 초과 카운트) ─────────────────────────────
  sum_c  <- matrix(0,  ng, ng); n_c    <- matrix(0L, ng, ng)
  cnt_hi <- matrix(0L, ng, ng)
  for (i in seq_along(months)) {
    sd_i <- months[i]
    M <- .fds_month_matrix(sd_i, grid, loader, coverage_min, rank_transform)
    C <- .fds_cor_on_grid(M, grid)
    N <- .fds_pair_nobs(M, grid)
    C[N < min_obs] <- NA_real_
    ok <- !is.na(C)
    sum_c[ok] <- sum_c[ok] + C[ok]
    n_c[ok]   <- n_c[ok] + 1L
    cnt_hi[ok & abs(C) >= screen_thr] <- cnt_hi[ok & abs(C) >= screen_thr] + 1L
    if (verbose && (i %% 24L == 0L || i == length(months))) {
      cat(sprintf("[dup_scan] pass1 %d/%d  %s\n", i, length(months), format(sd_i)))
      flush.console()
    }
  }

  ut <- upper.tri(matrix(0, ng, ng))
  cand <- which(ut & cnt_hi > 0L, arr.ind = TRUE)
  if (!nrow(cand)) {
    if (verbose) cat("[dup_scan] no candidate pair exceeded screen_thr\n")
    return(data.table(factor_a = character(0), factor_b = character(0),
                      n_months = integer(0), median_cor = numeric(0),
                      mean_cor = numeric(0), min_cor = numeric(0),
                      max_cor = numeric(0), median_abs = numeric(0),
                      frac_ge_099 = numeric(0), frac_ge_095 = numeric(0),
                      sign_flips = integer(0)))
  }
  if (verbose) cat(sprintf("[dup_scan] pass1 done — %d candidate pairs (|cor|>=%.2f in >=1 month)\n",
                           nrow(cand), screen_thr))

  # ── PASS 2: 후보 쌍만 정확 시계열 보관 ─────────────────────────────────
  np <- nrow(cand)
  series <- matrix(NA_real_, nrow = length(months), ncol = np)
  for (i in seq_along(months)) {
    M <- .fds_month_matrix(months[i], grid, loader, coverage_min, rank_transform)
    C <- .fds_cor_on_grid(M, grid)
    N <- .fds_pair_nobs(M, grid)
    C[N < min_obs] <- NA_real_
    series[i, ] <- C[cand]
    if (verbose && (i %% 24L == 0L || i == length(months))) {
      cat(sprintf("[dup_scan] pass2 %d/%d  %s\n", i, length(months), format(months[i])))
      flush.console()
    }
  }

  out <- data.table(
    factor_a = grid[cand[, 1L]],
    factor_b = grid[cand[, 2L]]
  )
  out[, n_months    := apply(series, 2L, function(v) sum(!is.na(v)))]
  out[, median_cor  := apply(series, 2L, stats::median, na.rm = TRUE)]
  out[, mean_cor    := apply(series, 2L, mean, na.rm = TRUE)]
  out[, min_cor     := apply(series, 2L, function(v) if (all(is.na(v))) NA_real_ else min(v, na.rm = TRUE))]
  out[, max_cor     := apply(series, 2L, function(v) if (all(is.na(v))) NA_real_ else max(v, na.rm = TRUE))]
  out[, median_abs  := apply(series, 2L, function(v) stats::median(abs(v), na.rm = TRUE))]
  out[, frac_ge_099 := apply(series, 2L, function(v) mean(abs(v) >= 0.99, na.rm = TRUE))]
  out[, frac_ge_095 := apply(series, 2L, function(v) mean(abs(v) >= 0.95, na.rm = TRUE))]
  out[, sign_flips  := apply(series, 2L, function(v) {
    v <- v[!is.na(v)]; if (length(v) < 2L) 0L else sum(diff(sign(v)) != 0) })]
  setorder(out, -median_abs)
  out[]
}

#==============================================================================
# scan_deploy_dup() — 배포존 active 수익 시계열 상관
#==============================================================================

#' @param panel data.table(signal_date, factor_id, active_bm) — r6 deployzone 패널.
#' @param min_months integer. 쌍별 공통 관측 월 수 하한.
scan_deploy_dup <- function(panel, factor_names = NULL, min_months = 36L) {
  p <- as.data.table(panel)
  req <- c("signal_date", "factor_id", "active_bm")
  if (!all(req %in% names(p))) stop("[dup_scan] panel needs: ", paste(req, collapse = ", "))
  if (!is.null(factor_names)) p <- p[factor_id %in% factor_names]
  W <- dcast(p, signal_date ~ factor_id, value.var = "active_bm")
  M <- as.matrix(W[, -1L, with = FALSE])
  C <- suppressWarnings(stats::cor(M, use = "pairwise.complete.obs"))
  A <- !is.na(M); storage.mode(A) <- "integer"
  N <- crossprod(A)
  ut <- upper.tri(C)
  idx <- which(ut, arr.ind = TRUE)
  out <- data.table(
    factor_a = colnames(M)[idx[, 1L]],
    factor_b = colnames(M)[idx[, 2L]],
    n_months = N[idx],
    cor      = C[idx]
  )
  out <- out[n_months >= min_months & !is.na(cor)]
  out[, abs_cor := abs(cor)]
  setorder(out, -abs_cor)
  out[]
}

#==============================================================================
# de-dup 소비 API — 라벨이 **행동으로 이어지게** 하는 부분
#
# ★라벨만 붙이고 소비자가 없으면 중복은 그대로 이중 투표한다. registry 의
#   lifecycle.status 는 현재 어떤 코드도 읽지 않는다(2026-08-02 실측) — 그래서
#   de-dup 은 status 문자열이 아니라 아래 두 함수로 소비한다.
#==============================================================================

.fds_load_registry <- function(registry = NULL) {
  if (!is.null(registry)) return(registry)
  if (exists(".load_registry", mode = "function")) return(.load_registry())
  stop("[dup_scan] registry 를 넘기거나 factor_db_connector.R 을 먼저 source 할 것")
}

#' 팩터명을 canonical 코드로 해석한다. alias 는 canonical 로, 그 외는 그대로.
#' 조회 자체는 절대 깨지지 않는다 — 미등록/미라벨 이름은 입력을 그대로 반환.
resolve_factor_canonical <- function(factor_names, registry = NULL) {
  reg <- .fds_load_registry(registry)
  vapply(as.character(factor_names), function(f) {
    d <- reg[[f]]$dedup
    if (is.null(d)) return(f)
    role <- if (is.null(d$role)) "" else as.character(d$role)[1]
    if (!identical(role, "alias")) return(f)
    cn <- if (is.null(d$canonical)) NA_character_ else as.character(d$canonical)[1]
    if (is.na(cn) || is.null(reg[[cn]])) f else cn
  }, character(1), USE.NAMES = FALSE)
}

#' 선별/Ω 추정용 팩터 집합에서 alias 를 제거한다 (canonical 1개만 남김).
#' @param warn TRUE 면 제거된 항목을 알린다 — 조용한 축소 금지.
#' @return canonical 만 남은 character vector (원 순서 보존)
drop_alias_factors <- function(factor_names, registry = NULL, warn = TRUE) {
  fn <- as.character(factor_names)
  canon <- resolve_factor_canonical(fn, registry)
  keep <- !duplicated(canon)
  dropped <- fn[!keep]
  out <- canon[keep]
  if (warn && length(dropped)) {
    cat(sprintf("[dup_scan] alias %d개 제거: %s\n", length(dropped),
                paste(sprintf("%s->%s", dropped, canon[!keep]), collapse = ", ")))
  }
  out
}

#' 주어진 집합 안에 남아 있는 미해결 중복(role=redundant 동일 cluster)을 보고한다.
#' alias 와 달리 자동 제거하지 않는다 — 구성이 다른데 실측만 겹치는 쌍은
#' 리서치 판단 사항이므로 **선언을 강제**하되 대신 결정하지 않는다.
report_redundant_clusters <- function(factor_names, registry = NULL) {
  reg <- .fds_load_registry(registry)
  fn <- as.character(factor_names)
  cl <- vapply(fn, function(f) {
    d <- reg[[f]]$dedup
    if (is.null(d) || is.null(d$cluster)) NA_character_ else as.character(d$cluster)[1]
  }, character(1), USE.NAMES = FALSE)
  tb <- data.table(factor = fn, cluster = cl)[!is.na(cluster)]
  if (!nrow(tb)) return(tb[0])
  tb[, n_in_set := .N, by = cluster]
  tb[n_in_set >= 2L][order(cluster, factor)]
}

#==============================================================================
# classify_dup() — verdict 라벨
#==============================================================================

#' @param pairs data.table with a statistic column named by `stat`.
#' @return same table + `verdict` in {EXACT_DUP, NEAR_DUP, OK}
classify_dup <- function(pairs, stat = "median_abs",
                         exact_thr = 0.99, near_thr = 0.95) {
  p <- copy(as.data.table(pairs))
  if (!stat %in% names(p)) stop("[dup_scan] stat column not found: ", stat)
  v <- p[[stat]]
  p[, verdict := fifelse(is.na(v), NA_character_,
                  fifelse(v >= exact_thr, "EXACT_DUP",
                   fifelse(v >= near_thr, "NEAR_DUP", "OK")))]
  p[]
}
