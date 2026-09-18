# score.R — 리플레이 점수 V 와 β 스윕 (사전등록 §3)
#
#   V(π,T) = max_{공개·측정} PORT_t − β₁·N + β₂·(N / max(1,k))
#   N = 공개 슬롯 수(예산 단위) · k = 라운드 수
# ★β 는 단일값이 아니라 스윕이고 단위 u 는 데이터에서 재도출한다(하드코딩 금지).
#   u = median_T |최고 − 기저| / 25  — "25칸 예산 전체가 전형적 개선폭 하나" 라는 환산.
# ★N 중립 지표를 함께 낸다 — max 연산자는 N 이 큰 정책에 유리하다(승자의 저주).

source("R/replay_engine.R")

ar_beta_unit <- function(ws) {
  v <- vapply(ws, function(w) {
    ev <- w$nodes[w$nodes$evaluated, , drop = FALSE]
    if (!nrow(ev) || !is.finite(w$baseline)) return(NA_real_)
    abs(max(ev$score, na.rm = TRUE) - w$baseline)
  }, numeric(1))
  u <- stats::median(v, na.rm = TRUE) / 25
  list(u = u, per_tree = v, n = sum(is.finite(v)))
}

#' 트리 1개 위 정책 1개 실행 → 지표
ar_eval_one <- function(world, policy, W = 5L, sizes = NULL) {
  r <- ar_replay(world, policy, W = W, sizes = sizes)
  nd <- world$nodes
  ev <- nd[nd$evaluated, , drop = FALSE]
  tree_best <- if (nrow(ev)) max(ev$score, na.rm = TRUE) else NA_real_
  best_id <- if (nrow(ev)) ev$node_id[which.max(ev$score)] else NA_character_
  # 최고 칸을 몇 번째로 열었나
  fb <- if (!is.na(best_id) && best_id %in% r$revealed) match(best_id, r$revealed) else NA_integer_
  data.frame(base_id = world$base_id, regime = world$regime, kind = world$kind,
             N = r$N, k = r$rounds, minutes = r$minutes,
             best = r$best, tree_best = tree_best,
             regret = tree_best - r$best,
             best_found = !is.na(fb),
             first_best_rank = fb,
             unreachable = r$unreachable,
             stringsAsFactors = FALSE)
}

ar_V <- function(d, b1, b2) d$best - b1 * d$N + b2 * (d$N / pmax(1L, d$k))

#' 정책 여러 개 × 트리 여러 개
ar_eval_all <- function(ws, policies, W = 5L, use_sizes = FALSE, seed = 20260918) {
  set.seed(seed)
  out <- list()
  for (nm in names(policies)) {
    for (w in ws) {
      pol <- policies[[nm]]
      if (is.function(pol) && length(formals(pol)) == 1L && identical(names(formals(pol)), "world")) {
        f <- pol(w)                      # 세계를 받는 생성자(오라클)
      } else f <- pol
      sz <- if (use_sizes) vapply(split(w$nodes, w$nodes$batch), nrow, integer(1)) else NULL
      e <- ar_eval_one(w, f, W = W, sizes = sz)
      e$policy <- nm
      out[[length(out) + 1L]] <- e
    }
  }
  do.call(rbind, out)
}

#' β 스윕 요약 — 정책별 평균 V 와 π₀ 대비 승률
ar_sweep_V <- function(d, u, ref = "pi0", betas1 = c(0, 1, 2, 4, 8), mult2 = c(0, 1, 2)) {
  res <- list()
  for (m1 in betas1) for (m2 in mult2) {
    b1 <- m1 * u; b2 <- m2 * b1
    d$V <- ar_V(d, b1, b2)
    w <- reshape(d[, c("base_id", "policy", "V")], idvar = "base_id",
                 timevar = "policy", direction = "wide")
    refcol <- paste0("V.", ref)
    for (p in setdiff(unique(d$policy), ref)) {
      pc <- paste0("V.", p)
      if (!(pc %in% names(w)) || !(refcol %in% names(w))) next
      dd <- w[[pc]] - w[[refcol]]
      res[[length(res) + 1L]] <- data.frame(
        beta1_mult = m1, beta2_mult = m2, policy = p,
        mean_gain = mean(dd, na.rm = TRUE),
        win_frac = mean(dd > 0, na.rm = TRUE),
        n_trees = sum(is.finite(dd)), stringsAsFactors = FALSE)
    }
  }
  do.call(rbind, res)
}
