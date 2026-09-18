# replay_engine.R — 기록 트리 위 off-policy 리플레이 (사전등록 §3)
#
# ★정책은 **공개된 접두**만 본다. 미공개 점수·스펙은 뷰에 들어가지 않는다.
# ★합법 = 러너가 그 상태에서 정확히 그 기록 스펙을 만들었을 칸만.
#     B1  : 바닥이 기저라 항상 합법
#     B2/B3/B5 : 현재 바닥(공개·측정 칸 중 PORT_t argmax)이 그 칸의 기록 바닥과 같을 때만
#     B4  : 네 블록의 전역 승자가 모두 공개됐을 때만 (결합은 승자 조립이다)
# ★기록에 없는 칸 요청은 버리고 unreachable 로 센다 (논문 미해결 지점의 Qvest 답).

source("R/build_world.R")

.RE_BLOCKS <- c("B1", "B2", "B3", "B5")

# 현재 바닥 — 공개·측정 칸 중 최고 (동률은 먼저 등록된 칸)
.re_floor <- function(nd, revealed) {
  r <- nd[nd$node_id %in% revealed & nd$evaluated, , drop = FALSE]
  if (!nrow(r)) return("base")
  r$cell_code[order(-r$score, r$n)][1]
}

# 전역 블록 승자(기록 전체 기준) — B4 합법성 판정용
.re_block_winners <- function(nd) {
  out <- character(0)
  for (b in .RE_BLOCKS) {
    s <- nd[nd$block == b & nd$evaluated, , drop = FALSE]
    if (nrow(s)) out[b] <- s$node_id[order(-s$score, s$n)][1]
  }
  out
}

ar_legal <- function(nd, revealed, winners) {
  fl <- .re_floor(nd, revealed)
  ok <- vapply(seq_len(nrow(nd)), function(i) {
    if (nd$node_id[i] %in% revealed) return(FALSE)
    b <- nd$block[i]
    if (identical(b, "B1")) return(TRUE)
    if (identical(b, "B4")) return(length(winners) > 0 && all(winners %in% revealed))
    identical(nd$parent[i], fl)
  }, logical(1))
  nd$node_id[ok]
}

# 정책이 받는 유일한 객체 — 공개분 복사본만 캡처한다
ar_view <- function(nd, revealed, legal, meta) {
  r <- nd[nd$node_id %in% revealed,
          c("node_id", "cell_code", "block", "parent", "evaluated", "grade", "fail_class",
            "score", "calmar", "oos", "delta_vs_parent", "delta_vs_baseline",
            "cost_min", "batch"), drop = FALSE]
  rownames(r) <- NULL
  lg <- nd[nd$node_id %in% legal, c("node_id", "cell_code", "block"), drop = FALSE]
  rownames(lg) <- NULL
  force(r); force(lg); force(meta)
  list(
    revealed = function() r,
    legal    = function() lg,
    meta     = meta,
    block_summary = function() {
      if (!nrow(r)) return(data.frame())
      do.call(rbind, lapply(split(r, r$block), function(s) data.frame(
        block = s$block[1], n = nrow(s), n_eval = sum(s$evaluated),
        best = suppressWarnings(max(s$score[s$evaluated], na.rm = TRUE)),
        mean_delta = suppressWarnings(mean(s$delta_vs_parent[s$evaluated], na.rm = TRUE)),
        stringsAsFactors = FALSE)))
    })
}

#' 리플레이 1회
#' @param policy function(view) -> list(batch = <node_id 벡터>, stop = <logical>)
ar_replay <- function(world, policy, W = 5L, budget = NULL, max_rounds = 60L,
                      sizes = NULL) {
  # sizes: 환경이 부과한 라운드별 배치 상한(일 상한 room 절단·재개). 정책 밖 변수다.
  nd <- world$nodes
  winners <- .re_block_winners(nd)
  budget <- budget %||% (world$budget %||% 25L)
  revealed <- character(0); trace <- list(); unreachable <- 0L; k <- 0L
  repeat {
    if (k >= max_rounds) break
    if (length(revealed) >= budget) break
    legal <- ar_legal(nd, revealed, winners)
    if (!length(legal)) break
    meta <- list(W = W, budget_left = budget - length(revealed), round = k + 1L,
                 blocks = unique(nd$block), block_order = world$block_order,
                 baseline = world$baseline, n_total = nrow(nd))
    v <- ar_view(nd, revealed, legal, meta)
    res <- tryCatch(policy(v),
                    error = function(e) list(batch = character(0), stop = TRUE,
                                             err = conditionMessage(e)))
    b <- as.character(res$batch %||% character(0))
    bad <- setdiff(b, legal)
    unreachable <- unreachable + length(bad)
    b <- unique(intersect(b, legal))
    cap <- if (!is.null(sizes) && k + 1L <= length(sizes)) min(W, sizes[k + 1L]) else W
    if (length(b) > cap) b <- b[seq_len(cap)]
    room <- budget - length(revealed)
    if (length(b) > room) b <- b[seq_len(room)]
    if (isTRUE(res$stop) || !length(b)) break
    k <- k + 1L
    revealed <- c(revealed, b)
    trace[[k]] <- data.frame(
      round = k,
      batch = paste(nd$cell_code[match(b, nd$node_id)], collapse = ","),
      n = length(b),
      block = paste(unique(nd$block[match(b, nd$node_id)]), collapse = "/"),
      stringsAsFactors = FALSE)
  }
  ev <- nd[nd$node_id %in% revealed & nd$evaluated, , drop = FALSE]
  cm <- nd$cost_min[nd$node_id %in% revealed]
  list(revealed = revealed, rounds = k, unreachable = unreachable,
       trace = if (length(trace)) do.call(rbind, trace) else data.frame(),
       N = length(revealed),
       N_costly = sum(is.finite(cm) & cm >= 1, na.rm = TRUE),
       best = if (nrow(ev)) max(ev$score, na.rm = TRUE) else NA_real_,
       best_cell = if (nrow(ev)) ev$cell_code[which.max(ev$score)] else NA_character_,
       minutes = sum(cm[is.finite(cm) & cm < 720], na.rm = TRUE))
}
