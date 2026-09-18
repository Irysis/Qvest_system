# candidates.R — 손으로 쓴 후보 정책들
#
# ★모든 상수는 **사전 고정**이다. 리플레이 결과를 보고 조정하지 않는다.
#   그래서 이 정책들에는 LOEO 가 필요 없다(고를 자유도가 없으므로 선택편의가 없다).
#   문턱은 계약에서 읽는다 — Calmar 0.64 = constraint_defaults.json::tier_graduation.
# ★정책은 순서·배치·정지만 정한다. 칸 내용은 정하지 않는다(설계 레인 소관).
# ★칸 코드 리터럴 금지(부록 B.2) — 블록 축 이름으로만 지목한다.

.CAL_MIN <- 0.64   # 계약 문턱(Grade A Calmar). 데이터에서 온 값이 아니다.
.GRID_ORDER <- c("B1", "B2", "B3", "B5", "B4")

.pol_order_legal <- function(lg, ord) {
  rk <- match(lg$block, ord); rk[is.na(rk)] <- 99L
  num <- suppressWarnings(as.integer(sub("^B[0-9]+_", "", lg$cell_code)))
  lg[order(rk, num, lg$cell_code), , drop = FALSE]
}

.pol_take_first_block <- function(lg, W) {
  b <- lg$block[1]
  head(lg$node_id[lg$block == b], W)
}

# ── π_B : 구속 축 우선 ───────────────────────────────────────────────────
# B1 이 끝난 뒤, 공개된 최고 칸의 Calmar 가 계약 문턱 미만이면 위험 축(B5)을 2번째로.
# 현행 rf_block_order_decide 와 다른 점: CAGR 조건을 걸지 않는다(수익 축 충족 여부와 무관하게
# 위험 축이 막고 있으면 먼저 친다). 결합(B4)은 언제나 마지막.
pol_calmar_first <- function(view) {
  lg <- view$legal(); if (!nrow(lg)) return(list(batch = character(0), stop = TRUE))
  r <- view$revealed(); ev <- r[r$evaluated, , drop = FALSE]
  ord <- .GRID_ORDER
  if (nrow(ev)) {
    best <- ev[which.max(ev$score), ]
    if (is.finite(best$calmar) && best$calmar < .CAL_MIN)
      ord <- c("B1", "B5", "B2", "B3", "B4")
  }
  lg <- .pol_order_legal(lg, ord)
  list(batch = .pol_take_first_block(lg, view$meta$W), stop = FALSE)
}

# ── π_A : 앞 두 블록만 ───────────────────────────────────────────────────
# 기록된 블록 순서의 앞 두 블록을 소진하면 정지. (격자 부분집합 — 헌법 라벨 grid_subset)
pol_first_two <- function(view) {
  lg <- view$legal(); if (!nrow(lg)) return(list(batch = character(0), stop = TRUE))
  ord <- view$meta$block_order; if (!length(ord)) ord <- .GRID_ORDER
  keep <- lg[lg$block %in% ord[1:2], , drop = FALSE]
  if (!nrow(keep)) return(list(batch = character(0), stop = TRUE))
  keep <- .pol_order_legal(keep, ord)
  list(batch = .pol_take_first_block(keep, view$meta$W), stop = FALSE)
}

# ── π_C : 블록 예산 재배분 ───────────────────────────────────────────────
# 각 비-B1 블록에 먼저 2칸씩 탐침한 뒤, 남은 예산은 running delta_vs_parent 가 가장 좋은
# 블록에 몰아준다. 탐침 수 2 는 사전 고정(최소 2점이 있어야 블록 간 비교가 성립).
.PROBE_N <- 2L
pol_reallocate <- function(view) {
  lg <- view$legal(); if (!nrow(lg)) return(list(batch = character(0), stop = TRUE))
  ord <- view$meta$block_order; if (!length(ord)) ord <- .GRID_ORDER
  r <- view$revealed()
  cnt <- table(factor(r$block, levels = ord))
  # 1단계: B1 먼저, 그다음 각 블록 2칸씩
  if (as.integer(cnt[["B1"]] %||% 0L) == 0L && any(lg$block == "B1")) {
    l2 <- .pol_order_legal(lg[lg$block == "B1", , drop = FALSE], ord)
    return(list(batch = head(l2$node_id, view$meta$W), stop = FALSE))
  }
  under <- ord[vapply(ord, function(b) as.integer(cnt[[b]] %||% 0L) < .PROBE_N &&
                                       any(lg$block == b) && !identical(b, "B4"), logical(1))]
  if (length(under)) {
    l2 <- .pol_order_legal(lg[lg$block %in% under, , drop = FALSE], ord)
    b <- l2$block[1]
    need <- .PROBE_N - as.integer(cnt[[b]] %||% 0L)
    return(list(batch = head(l2$node_id[l2$block == b], min(need, view$meta$W)), stop = FALSE))
  }
  # 2단계: delta_vs_parent 평균이 최고인 블록으로
  bs <- view$block_summary()
  cand <- unique(lg$block[lg$block != "B4"])
  if (length(cand) && nrow(bs)) {
    sc <- vapply(cand, function(b) { s <- bs$mean_delta[bs$block == b]
                                     if (!length(s) || !is.finite(s)) -Inf else s }, numeric(1))
    if (any(is.finite(sc))) {
      b <- cand[which.max(sc)]
      l2 <- .pol_order_legal(lg[lg$block == b, , drop = FALSE], ord)
      return(list(batch = head(l2$node_id, view$meta$W), stop = FALSE))
    }
  }
  l2 <- .pol_order_legal(lg, ord)
  list(batch = .pol_take_first_block(l2, view$meta$W), stop = FALSE)
}

# ── π_D : 정체 시 정지 ───────────────────────────────────────────────────
# 최근 두 배치가 공개 최고를 못 올렸으면 정지. 2 는 사전 고정.
.PLATEAU_K <- 2L
pol_stop_plateau <- function(view) {
  lg <- view$legal(); if (!nrow(lg)) return(list(batch = character(0), stop = TRUE))
  r <- view$revealed(); ev <- r[r$evaluated, , drop = FALSE]
  if (nrow(ev)) {
    bs <- split(ev$score, ev$batch)
    if (length(bs) > .PLATEAU_K) {
      run <- vapply(seq_along(bs), function(i) suppressWarnings(max(unlist(bs[seq_len(i)]), na.rm = TRUE)), numeric(1))
      tail_run <- tail(run, .PLATEAU_K + 1L)
      if (all(abs(diff(tail_run)) < 1e-9)) return(list(batch = character(0), stop = TRUE))
    }
  }
  ord <- view$meta$block_order; if (!length(ord)) ord <- .GRID_ORDER
  lg <- .pol_order_legal(lg, ord)
  list(batch = .pol_take_first_block(lg, view$meta$W), stop = FALSE)
}

# ── 무작위 (귀무) ────────────────────────────────────────────────────────
pol_random <- function(view) {
  lg <- view$legal(); if (!nrow(lg)) return(list(batch = character(0), stop = TRUE))
  b <- lg$block[sample.int(nrow(lg), 1L)]
  ids <- lg$node_id[lg$block == b]
  list(batch = sample(ids, min(length(ids), view$meta$W)), stop = FALSE)
}
