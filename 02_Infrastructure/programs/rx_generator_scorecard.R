#==============================================================================
# rx_generator_scorecard.R — P4 강화 사슬 생성기(처방 프롬프트) 판별 성적표 (v10.2 · 2026-11-10 감사 레인 E2)
#
# 왜: v10.2 사다리 루프는 "루프가 고쳐 쓰는 것은 생성기뿐"이라고 했다(lean-loop.md · round_core v1/p4.R ⑦ rxg_revise).
#   그런데 생성기 판끼리 견줄 척도가 없으면 개정은 재귀적 자기개선이 아니라 그냥 교체다 — g2 가 g1 보다 나은지 아무도 모른다.
#   rc_p4_generator_review(p4.R)는 블록 유형별 채택 수 · dS_vis 목록을 사람에게 보여 주는 서술 표다(판 사이 척도 · 탐색 · 되풀이 실패 없음).
# 무엇: 걸음 원장(chain_steps.jsonl) 레코드 목록만 입력으로 받는 **순수 함수**(파일 · 네트워크 · 전역 상태 없음)로 판별 성적을 낸다.
#   전부 보는 창 지표(*_vis · τ_D 이전)만 읽는다 — 시험 창 · 전 기간 이름의 열이 레코드에 보이면 멈춘다(fail-closed · R4).
#   척도(판 g 마다 · 사슬을 단위로):
#     n_chains · n_steps(연 걸음) · n_decided(판정) · n_accept · accept_rate = 채택 / 판정
#     dS_mean · dS_median = 판정 걸음의 보는 창 dS_vis(부모 대비) 평균 · 중앙
#     gain_per_step(주 척도) = Σ 채택 걸음 dS_vis / 판정 걸음 수 — 측정 예산 한 걸음이 산 보는 창 S 개선(사슬 머리는 채택 걸음만 옮긴다)
#     cum_dS_mean = 사슬마다 (머리 S_vis − 기준 칸 S_vis) 의 평균 · cum_duc_mean · cum_ddd_mean = 같은 식의 상승 포착 · 위기 하락 포착 중앙값 차
#     new_block_rate = 그 사슬에서 처음 쓰는 블록 유형인 걸음의 비율(탐색) · repeat_fail = 같은 사슬에서 이미 기각된 (블록 유형 · 바뀐 축) 을 또 낸 걸음 수
#     noise_streak_max · noise_streak_mean = 사슬별 최장 연속 '잡음 이내'(r7 = noise) · measure_fail = 측정 실패 기록 수(진단)
#     reasons = 기각 사유(규칙 id) 빈도 · blocks = 블록 유형별 걸음 · 채택 · dS 평균
#   비교 rxg_scorecard_compare(sc, a, b): 판 b − 판 a 의 척도 차 + 주 척도의 사슬 단위 표준오차(사슬 ≥ 2 일 때만 · 아니면 NA).
#     ★판정 문턱은 여기서 만들지 않는다 — 판 승격 규칙은 생성기 개정 사유(rxg_revise reason · 결과 원장 근거)나 별도 사전등록이 정한다.
# 경계: 수치는 원장에 이미 있는 R 계약 산출(step_result.table · base_measured.metrics)을 옮기고 집계할 뿐이다(AX-008 — 새 성과 계산 없음).
#   원장 사슬 무결성(md5 사슬) 검사는 하지 않는다 — 읽기는 round_core v1/p4.R::rc_p4_steps_read(검증 포함)를 쓰고 그 결과를 넘긴다.
# 공개: rxg_scorecard(chains) · rxg_scorecard_compare(sc, a, b) · rxg_scorecard_md(sc) · RXG_SC_FORBIDDEN_RX
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
RXG_SC_SCHEMA <- "rxg_scorecard_v1"
## 시험 창 · 전 기간 지표 이름(round_core v1/p4.R RC_P4_FORBIDDEN_METRIC_RX 와 같은 규칙 — 사본 · 시험이 대조)
RXG_SC_FORBIDDEN_RX <- "(test|_tw$|oos|full|overall|lifetime|_all$)"

.rxgs_num <- function(x) { v <- suppressWarnings(as.numeric(unlist(x))); if (length(v) == 1L) v else NA_real_ }
.rxgs_chr <- function(x) { v <- unlist(x); if (length(v) == 1L && !is.na(v)) as.character(v) else NA_character_ }

## 레코드 안 지표 이름 검사(보는 창만) — step_result.table · step_result.metrics · base_measured.metrics 의 키
.rxgs_guard <- function(rec, where) {
  ks <- c(names(rec$table), names(rec$metrics))
  bad <- ks[grepl(RXG_SC_FORBIDDEN_RX, ks, perl = TRUE)]
  if (length(bad)) stop(sprintf("[rxg_scorecard] %s 에 시험 창 · 전 기간 지표가 있다(보는 창만 — R4): %s", where, paste(unique(bad), collapse = ",")), call. = FALSE)
  invisible(TRUE)
}

## 사슬 한 개 → 걸음 표(data.table) + 사슬 요약
.rxgs_chain <- function(recs, cid) {
  recs <- Filter(Negate(is.null), recs)
  ev <- vapply(recs, function(r) .rxgs_chr(r$event) %||% NA_character_, "")
  reg <- recs[ev %in% "chain_registered"]
  if (!is.na(cid) && length(reg) && !is.na(.rxgs_chr(reg[[1]]$chain_id)) && !identical(.rxgs_chr(reg[[1]]$chain_id), cid))
    stop(sprintf("[rxg_scorecard] 사슬 이름(%s) ≠ 등록 기록 chain_id(%s)", cid, .rxgs_chr(reg[[1]]$chain_id)), call. = FALSE)
  if (is.na(cid)) cid <- if (length(reg)) .rxgs_chr(reg[[1]]$chain_id) else NA_character_
  if (is.na(cid)) stop("[rxg_scorecard] 사슬 이름 없음(이름 있는 목록으로 넘기거나 chain_registered 기록이 있어야 한다)", call. = FALSE)
  gen_reg <- if (length(reg)) .rxgs_chr(reg[[1]]$generator$id) else NA_character_
  bm <- recs[ev %in% "base_measured"]; bm <- if (length(bm)) bm[[length(bm)]] else NULL
  if (!is.null(bm)) .rxgs_guard(bm, sprintf("%s base_measured", cid))
  opens <- recs[ev %in% "step_open"]; res <- recs[ev %in% "step_result"]
  for (r in res) .rxgs_guard(r, sprintf("%s step_result k=%s", cid, .rxgs_chr(r$k)))
  rk <- vapply(res, function(r) as.integer(.rxgs_num(r$k)), 1L)
  seen_blocks <- character(0); rejected_sig <- character(0); rows <- list()
  for (o in opens) {
    k <- as.integer(.rxgs_num(o$k)); bt <- .rxgs_chr(o$block_type)
    ax <- paste(sort(as.character(unlist(o$changed_axes))), collapse = "+")
    sig <- paste(bt, ax, sep = "|")
    r <- res[rk %in% k]; r <- if (length(r)) r[[1]] else NULL
    dec <- if (is.null(r)) "pending" else .rxgs_chr(r$decision)
    rows[[length(rows) + 1L]] <- data.table(
      chain = cid, generator = { gv <- .rxgs_chr(o$generator_version); if (is.na(gv)) gen_reg else gv }, k = k, block = bt, axes = ax,
      decision = dec, dS = if (is.null(r)) NA_real_ else .rxgs_num(r$table$dS_vis),
      S = if (is.null(r)) NA_real_ else .rxgs_num(r$table$S_vis),
      uc = if (is.null(r)) NA_real_ else .rxgs_num(r$table$uc_vis), ddc = if (is.null(r)) NA_real_ else .rxgs_num(r$table$dd_capture_median_vis),
      r7 = if (is.null(r)) NA_character_ else .rxgs_chr(r$r7),
      reasons = if (is.null(r) || !length(r$reasons)) "" else paste(sub(":.*$", "", unlist(r$reasons)), collapse = ";"),
      new_block = !(bt %in% seen_blocks), repeat_fail = sig %in% rejected_sig)
    seen_blocks <- c(seen_blocks, bt)
    if (identical(dec, "reject")) rejected_sig <- c(rejected_sig, sig)
  }
  D <- if (length(rows)) rbindlist(rows) else NULL
  ## 사슬 머리 = 마지막 채택 걸음(없으면 기준 칸) — p4.R .rcp4_state 와 같은 정의
  acc <- if (is.null(D)) NULL else D[decision == "accept"][order(k)]
  base_S <- if (is.null(bm)) NA_real_ else .rxgs_num(bm$metrics$S_vis)
  base_uc <- if (is.null(bm)) NA_real_ else .rxgs_num(bm$metrics$uc_vis)
  base_dd <- if (is.null(bm)) NA_real_ else .rxgs_num(bm$metrics$dd_capture_median_vis)
  head <- if (!is.null(acc) && nrow(acc)) acc[nrow(acc)] else NULL
  streak_max <- 0L; cur <- 0L
  if (!is.null(D)) for (v in D[decision != "pending"][order(k)]$r7) { if (identical(v, "noise")) { cur <- cur + 1L; streak_max <- max(streak_max, cur) } else if (!is.na(v)) cur <- 0L }
  S <- list(chain = cid, generator = if (!is.null(D) && nrow(D)) D$generator[1] else gen_reg, base_measured = !is.null(bm),
            cum_dS = if (is.null(head)) (if (is.finite(base_S)) 0 else NA_real_) else head$S - base_S,
            cum_duc = if (is.null(head)) (if (is.finite(base_uc)) 0 else NA_real_) else head$uc - base_uc,
            cum_ddd = if (is.null(head)) (if (is.finite(base_dd)) 0 else NA_real_) else head$ddc - base_dd,
            noise_streak_max = streak_max, measure_fail = sum(ev %in% c("step_measure_failed", "base_measure_failed")),
            closed = any(ev %in% "chain_closed"))
  list(steps = D, summary = S)
}

## 판 하나의 척도(사슬 표 · 걸음 표에서)
.rxgs_one <- function(D, C) {
  dd <- D[decision %in% c("accept", "reject")]
  nd <- nrow(dd); na <- sum(dd$decision == "accept")
  rs <- unlist(strsplit(dd[decision == "reject"]$reasons, ";", fixed = TRUE)); rs <- rs[nzchar(rs)]
  per_chain_gain <- vapply(unique(C$chain), function(ch) { x <- dd[chain == ch]
    if (!nrow(x)) NA_real_ else sum(x[decision == "accept"]$dS, na.rm = TRUE) / nrow(x) }, numeric(1))
  B <- if (nrow(D)) D[, .(steps = .N, decided = sum(decision %in% c("accept", "reject")), accept = sum(decision == "accept"),
                          dS_mean = if (any(is.finite(dS))) mean(dS, na.rm = TRUE) else NA_real_), by = block][order(block)] else NULL
  list(n_chains = nrow(C), n_steps = nrow(D), n_decided = nd, n_accept = na,
       accept_rate = if (nd) na / nd else NA_real_,
       dS_mean = if (nd && any(is.finite(dd$dS))) mean(dd$dS, na.rm = TRUE) else NA_real_,
       dS_median = if (nd && any(is.finite(dd$dS))) stats::median(dd$dS, na.rm = TRUE) else NA_real_,
       gain_per_step = if (nd) sum(dd[decision == "accept"]$dS, na.rm = TRUE) / nd else NA_real_,
       gain_per_step_chain_se = { g <- per_chain_gain[is.finite(per_chain_gain)]; if (length(g) >= 2L) stats::sd(g) / sqrt(length(g)) else NA_real_ },
       cum_dS_mean = if (any(is.finite(C$cum_dS))) mean(C$cum_dS, na.rm = TRUE) else NA_real_,
       cum_duc_mean = if (any(is.finite(C$cum_duc))) mean(C$cum_duc, na.rm = TRUE) else NA_real_,
       cum_ddd_mean = if (any(is.finite(C$cum_ddd))) mean(C$cum_ddd, na.rm = TRUE) else NA_real_,
       new_block_rate = if (nrow(D)) mean(D$new_block) else NA_real_,
       repeat_fail = sum(D$repeat_fail),
       noise_streak_max = if (nrow(C)) max(C$noise_streak_max) else NA_integer_,
       noise_streak_mean = if (nrow(C)) mean(C$noise_streak_max) else NA_real_,
       measure_fail = sum(C$measure_fail),
       chains_without_base = sum(!C$base_measured),
       reasons = if (length(rs)) as.list(sort(table(rs), decreasing = TRUE)) else list(),
       blocks = B)
}

#' 성적표 — chains = 사슬별 걸음 원장 레코드 목록의 목록(이름 = chain_id 권장 · 이름 없으면 chain_registered 의 chain_id)
#'   레코드 = rc_p4_steps_read(chain_dir) 가 돌려주는 목록 그대로(event · k · block_type · generator_version · decision · table · metrics · r7 …)
#' @return list(schema, by_generator = 판별 척도 목록, chains = 사슬 요약 표, steps = 걸음 표)
rxg_scorecard <- function(chains) {
  if (!is.list(chains)) stop("[rxg_scorecard] 입력은 사슬별 레코드 목록의 목록", call. = FALSE)
  nm <- names(chains) %||% rep(NA_character_, length(chains)); nm[!nzchar(nm %||% "")] <- NA_character_
  parts <- lapply(seq_along(chains), function(i) .rxgs_chain(chains[[i]], nm[i]))
  if (anyDuplicated(vapply(parts, function(p) p$summary$chain, ""))) stop("[rxg_scorecard] 같은 사슬이 두 번 들어왔다", call. = FALSE)
  D <- rbindlist(lapply(parts, `[[`, "steps"), fill = TRUE)
  if (!nrow(D)) D <- data.table(chain = character(0), generator = character(0), k = integer(0), block = character(0), axes = character(0),
                                decision = character(0), dS = numeric(0), S = numeric(0), uc = numeric(0), ddc = numeric(0), r7 = character(0),
                                reasons = character(0), new_block = logical(0), repeat_fail = logical(0))
  C <- rbindlist(lapply(parts, function(p) as.data.table(p$summary)), fill = TRUE)
  if (!nrow(C)) C <- data.table(chain = character(0), generator = character(0), base_measured = logical(0), cum_dS = numeric(0), cum_duc = numeric(0),
                                cum_ddd = numeric(0), noise_streak_max = integer(0), measure_fail = integer(0), closed = logical(0))
  if (anyNA(C$generator)) stop(sprintf("[rxg_scorecard] 생성기 판을 모르는 사슬: %s", paste(C[is.na(generator)]$chain, collapse = ",")), call. = FALSE)
  gens <- sort(unique(C$generator))
  by <- stats::setNames(lapply(gens, function(g) .rxgs_one(D[generator == g], C[generator == g])), gens)
  list(schema = RXG_SC_SCHEMA, audience = "보는 창(τ_D 이전) 걸음 원장 집계 — 처방 · 리뷰 레인 열람 가능", by_generator = by, chains = C, steps = D)
}

#' 판 비교 — b − a(척도 차) · 주 척도(gain_per_step) 차의 사슬 단위 표준오차(두 판 모두 사슬 ≥ 2 일 때만) · 판정 문턱 없음
rxg_scorecard_compare <- function(sc, a, b) {
  for (g in c(a, b)) if (is.null(sc$by_generator[[g]])) stop("[rxg_scorecard] 성적표에 없는 생성기 판: ", g, call. = FALSE)
  A <- sc$by_generator[[a]]; B <- sc$by_generator[[b]]
  ks <- c("accept_rate", "dS_mean", "dS_median", "gain_per_step", "cum_dS_mean", "cum_duc_mean", "cum_ddd_mean", "new_block_rate",
          "repeat_fail", "noise_streak_mean", "measure_fail")
  d <- stats::setNames(lapply(ks, function(k) .rxgs_num(B[[k]]) - .rxgs_num(A[[k]])), ks)
  se <- if (is.finite(A$gain_per_step_chain_se) && is.finite(B$gain_per_step_chain_se)) sqrt(A$gain_per_step_chain_se^2 + B$gain_per_step_chain_se^2) else NA_real_
  list(a = a, b = b, n_chains = c(a = A$n_chains, b = B$n_chains), n_decided = c(a = A$n_decided, b = B$n_decided), delta = d,
       gain_per_step_se = se, gain_per_step_z = if (is.finite(se) && se > 0) d$gain_per_step / se else NA_real_,
       note = "판정 문턱 없음 — 판 승격은 개정 사유 · 결과 원장 근거 · 사전등록 규칙이 정한다(이 함수는 척도만)")
}

#' 사람용 md(보는 창 정보만)
rxg_scorecard_md <- function(sc) {
  f3 <- function(x) { x <- .rxgs_num(x); if (is.finite(x)) formatC(x, format = "f", digits = 3) else "—" }
  L <- c("# P4 생성기 성적표(보는 창 · 걸음 원장 집계)", "",
         "| 판 | 사슬 | 걸음 | 판정 | 채택률 | 걸음당 개선(주) | dS 평균 | 누적 dS | 누적 상승 포착 차 | 누적 위기 포착 차 | 새 블록 비율 | 되풀이 기각 | 최장 잡음 |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|---|")
  for (g in names(sc$by_generator)) { s <- sc$by_generator[[g]]
    L <- c(L, paste0("| ", g, " | ", s$n_chains, " | ", s$n_steps, " | ", s$n_decided, " | ", f3(s$accept_rate), " | ", f3(s$gain_per_step), " | ", f3(s$dS_mean),
                     " | ", f3(s$cum_dS_mean), " | ", f3(s$cum_duc_mean), " | ", f3(s$cum_ddd_mean), " | ", f3(s$new_block_rate), " | ", s$repeat_fail, " | ",
                     s$noise_streak_max, " |")) }
  paste(L, collapse = "\n")
}

