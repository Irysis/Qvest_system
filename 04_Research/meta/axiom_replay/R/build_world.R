# build_world.R — 리플레이 세계 빌더 (사전등록 §3)
#
# 트리 1개 = 원장 entry 1개. 노드 = 시도(칸).
# ★노드 키 = (칸 코드, 바닥 노드). 블록 누적 때문에 같은 코드라도 바닥이 다르면 다른 칸이다.
# ★바닥은 러너 규칙을 그대로 재도출한다 — 전 블록에서 그 시점까지 측정된 최고 PORT_t 칸.
#   (reinforce_auto_parallel.R:434-443 .wbest_spec 과 동형)
# ★스펙 서명 감사: 자기 축을 뺀 나머지 축이 바닥과 같아야 누적 규칙과 정합이다.

source("R/ledger_io.R")

.bw_spec_cache <- new.env(parent = emptyenv())

.bw_load_spec <- function(p) {
  k <- .ar_chr(p); if (is.na(k) || !nzchar(k)) return(NULL)
  if (!is.null(.bw_spec_cache[[k]])) return(.bw_spec_cache[[k]])
  v <- if (file.exists(k)) tryCatch(fromJSON(k, simplifyVector = FALSE), error = function(e) NULL) else NULL
  .bw_spec_cache[[k]] <- if (is.null(v)) list() else v
  .bw_spec_cache[[k]]
}

# 축별 서명 — 블록이 시험하는 자기 축과 승계 축을 가르기 위해
.bw_axis_sig <- function(sp) {
  if (is.null(sp) || !length(sp)) return(c(factors = NA, weighting = NA, universe = NA,
                                           overlay = NA, base_signal = NA))
  j <- function(x) as.character(toJSON(x %||% list(), auto_unbox = TRUE))
  c(factors     = j(sp$factors),
    weighting   = j(sp$weighting),
    universe    = j(sp$universe),
    overlay     = j(sp$overlay),
    base_signal = as.character(sp$base_signal$path %||% sp$base_signal$kind %||% ""))
}

# 블록이 소유한 축 (격자 정본과 같은 대응)
.BW_OWN_AXIS <- c(B1 = "factors", B2 = "weighting", B3 = "universe", B5 = "overlay", B4 = "*")

#' 트리 1개 — entry 의 시도들을 바닥 관계로 엮는다
ar_build_tree <- function(base_id, ent, att) {
  E  <- ent[ent$base_id == base_id, ]
  A  <- att[att$base_id == base_id, , drop = FALSE]
  if (!nrow(A)) return(NULL)
  A  <- A[order(A$n), , drop = FALSE]
  # ★블록의 정본은 **격자 코드**다. essence$block 은 B4 결합 칸에서 '빠뜨린 축'의 블록을 적어
  #   B4_24 가 "B5" 로 기록된다(실측 21280_promo1). 그 라벨로 정렬하면 결합 칸이 위험 축으로
  #   앞당겨져 π₀ 재현이 깨진다. essence 라벨은 진단용으로만 보존한다.
  A$block_essence <- A$block
  A$block <- ifelse(!is.na(A$cell_code) & nzchar(A$cell_code),
                    sub("_.*$", "", A$cell_code),
                    ifelse(is.na(A$block), "", A$block))
  base_t <- E$base_port_t %||% NA_real_
  nodes <- vector("list", nrow(A))
  for (i in seq_len(nrow(A))) {
    v <- A[i, ]
    blk <- v$block
    # 바닥 = 이 칸이 열리기 전에 닫힌 측정 칸 중 PORT_t 최대 (러너 규칙)
    prior <- A[is.finite(A$port_t) & !is.na(A$closed_at) & !is.na(v$opened_at) &
                 A$closed_at <= v$opened_at, , drop = FALSE]
    if (identical(blk, "B1") || !nrow(prior)) {
      par <- "base"; par_i <- NA_integer_
    } else {
      par_i <- which.max(prior$port_t); par <- prior$cell_code[par_i]
    }
    # 스펙 서명 감사 — 자기 축 제외 나머지가 바닥과 같은가
    own <- if (!is.na(blk) && blk %in% names(.BW_OWN_AXIS)) .BW_OWN_AXIS[[blk]] else "*"
    aud <- "no_spec"
    if (!is.na(v$spec) && nzchar(v$spec)) {
      s_v <- .bw_axis_sig(.bw_load_spec(v$spec))
      if (identical(par, "base")) {
        aud <- "root_floor"
      } else {
        pj <- match(par, A$cell_code)
        s_p <- if (!is.na(pj) && !is.na(A$spec[pj])) .bw_axis_sig(.bw_load_spec(A$spec[pj])) else NULL
        if (is.null(s_p)) aud <- "parent_no_spec"
        else {
          cmp <- setdiff(names(s_v), if (identical(own, "*")) names(s_v) else own)
          same <- all(mapply(function(a, b) identical(a, b), s_v[cmp], s_p[cmp]))
          aud <- if (identical(own, "*")) "combine_multi_parent"
                 else if (same) "spec_matched"
                 else paste0("unmatched:", paste(cmp[!mapply(function(a,b) identical(a,b),
                                                             s_v[cmp], s_p[cmp])], collapse = "+"))
        }
      }
    }
    fc <- if (v$measured) "none" else {
      f <- v$fail_class
      if (is.na(f) || !nzchar(f)) "other_na"
      else if (grepl("중복", f)) "duplicate_inherited"
      else if (grepl("처치|무처치|측정 무효|구조", f)) "hard_unrecoverable"
      else if (grepl("양립|커버리지", f)) "compat_closed"
      else if (grepl("워커|실행 실패|시간", f)) "worker_fail"
      else "other_na"
    }
    par_t <- if (identical(par, "base")) base_t else A$port_t[match(par, A$cell_code)]
    nodes[[i]] <- data.frame(
      node_id = paste0(v$cell_code, "@", par), cell_code = v$cell_code, n = v$n,
      block = blk, block_essence = v$block_essence, parent = par,
      floor_audit = aud, own_axis = own,
      evaluated = v$measured, grade = v$grade, fail_class = fc,
      score = v$port_t, calmar = v$calmar, oos = v$oos,
      delta_vs_parent = v$port_t - par_t, delta_vs_baseline = v$port_t - base_t,
      cost_min = v$minutes, opened_at = v$opened_at, closed_at = v$closed_at,
      window_shifted = !is.na(v$spec) && nzchar(v$spec) &&
        !identical(.bw_axis_sig(.bw_load_spec(v$spec))[["universe"]], "{\"kind\":\"k200_kq150\"}"),
      stringsAsFactors = FALSE)
  }
  nd <- do.call(rbind, nodes)
  # 배치 재구성 — opened_at 간격 120초 초과에서 절단
  ot <- as.numeric(nd$opened_at); ot[is.na(ot)] <- 0
  nd$batch <- cumsum(c(1L, as.integer(diff(ot) > 120)))
  list(base_id = base_id, kind = E$kind, regime = E$regime, status = E$status,
       baseline = base_t, budget = E$max_attempts,
       block_order = if (!is.na(E$block_order) && nzchar(E$block_order)) strsplit(E$block_order, ">")[[1]] else character(0),
       nodes = nd)
}

#' 전 트리 — 층·감사 요약 포함
ar_build_worlds <- function(ent, att, ids = NULL) {
  cache <- new.env(parent = emptyenv())
  if (is.null(ent$base_port_t))
    ent$base_port_t <- vapply(ent$base_artifacts, function(p) {
      k <- .ar_chr(p); if (is.na(k) || !nzchar(k)) return(NA_real_)
      if (!is.null(cache[[k]])) return(cache[[k]])
      f <- file.path(k, "authoritative_remeasure.json")
      v <- NA_real_
      if (file.exists(f)) { j <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
                            if (!is.null(j)) v <- .ar_num(j$essence$portfolio_alpha_t_nw_lag3) }
      cache[[k]] <- v; v }, numeric(1))
  if (is.null(ids)) ids <- ent$base_id[ent$n_cells > 0]
  ws <- lapply(ids, ar_build_tree, ent = ent, att = att)
  names(ws) <- ids
  Filter(Negate(is.null), ws)
}
