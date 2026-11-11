## round_core v3 · p2 — P2(장치 × 엔진) 판정 템플릿 · 도우미 · 라운드 판정
##   출처 = P2R04 evaluate.R(등록 a32201675 · 파일 9e34f5f05 · 1,425줄)의 짝 판정 ①~⑭ · 기록 · 진단 읽기 · R7 판독 · A 거리 · 보는 창 파일.
##   P2R03(5346d12da) 판정은 같은 템플릿에 구판 훅(rejudge/P2R03_ext.R)을 얹어 재현한다. 범용 신규분(시드 띠 · 판정 여유 · Dimson β · 위기 유형 ·
##   유동성 3분위 귀속)은 P2R05 evaluate.R(작업 중 판 · main 미커밋 · 2026-10-18 21:44 · 줄 번호는 그 판)에서 옮겼다.
##   전역 상수(장치 표 · 진단 표 · 판정어)는 템플릿 cfg 로 받는다 — 라운드는 사양 · 표 · 고유 훅만 쓴다. 함수 본문은 같은 동작.

## ── 판정어 · 상수(P2R04 L53-75) ──────────────────────────────────────────────────────
RC_P2_FS_KEYS <- c("calmar_norm", "port_t_norm", "w_calmar", "w_port_t", "tie_eps", "uc_floor", "majority_share", "crisis_improve_min",
                   "alpha_t_floor", "alpha_margin_frac", "single_name_loss_floor", "bull_ratio", "fast_window_days", "fast_drop",
                   "mc8_label_required", "state_unturned_max_drop_crises")
RC_P2_VERDICTS <- c("pass", "not_decisive", "exposure_only", "selection_unmeasured", "size_or_exposure_defense", "fast_unmeasured", "beta_unmeasured",
                    "defense_but_strength_or_path", "untested")
RC_P2_VERDICT_NAMES <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어(β 짝 미통과)",
                         selection_unmeasured = "선택 귀속 미측정 — 방어 이름 보류",
                         size_or_exposure_defense = "크기 · 노출 방어(⑭ 미통과)", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 대조 미측정",
                         defense_but_strength_or_path = "방어만 · 복리 없음", untested = "미시험")
RC_P2_VERDICT_SHORT <- c(pass = "통과", not_decisive = "결정 미달", exposure_only = "노출 방어", selection_unmeasured = "⑭ 미측정",
                         size_or_exposure_defense = "크기 · 노출 방어", fast_unmeasured = "빠른 급락 미측정", beta_unmeasured = "β 짝 미측정",
                         defense_but_strength_or_path = "방어만 · 복리 없음", untested = "미시험")
RC_P2_MC8_LABELS <- c("selection_defense", "size_defense", "exposure_defense", "no_defense")
RC_P2_VISIBLE_DROP <- c("alpha_test_window", "tbl", "cell_log_full_period")

## ── 순수 도우미(계약 호출 없음) ───────────────────────────────────────────────────────
## 크기 × β 짝 계획(C-017) — 출처: P2R04 L159-164 — k = 변형 β / 바스켓 β · k < 1 = 바스켓을 k 배 · k ≥ 1 = 바스켓 그대로(차입 없음)
rc_p2_size_beta_plan <- function(beta_v, beta_b) {
  bv <- suppressWarnings(as.numeric(beta_v)); bb <- suppressWarnings(as.numeric(beta_b))
  k <- if (length(bv) == 1L && length(bb) == 1L && is.finite(bv) && is.finite(bb) && bb > 0) bv / bb else NA_real_
  mode <- if (!is.finite(k) || k <= 0) "unmeasured" else if (k < 1) "scaled" else "basket"
  list(k = k, scale = if (identical(mode, "unmeasured")) NA_real_ else min(k, 1), mode = mode)
}
## 크기 × β 짝 판정 부분 — 출처: P2R04 L179-183 — 깊은 위기에서 변형 dd_capture < 사본 − tol 인 위기 과반(짝 ≥ 2)
rc_p2_size_beta_core <- function(cr_v, cr_c, deep, tol, maj) {
  mj <- rc_crisis_majority(cr_v, cr_c, tol, "dd_capture", subset = deep)
  list(n_pair = mj$n_pair, n_better = mj$n_better, share = mj$share, ok = mj$n_pair >= 2L && rc_maj(mj$share, maj),
       status_pairs = if (mj$n_pair >= 2L) "ok" else "unmeasured(짝 < 2)", per_crisis = mj$per_crisis)
}
## 시장 대비 기준점(C-024) — 출처: P2R04 L185-192 — 위기 dd_capture < 1 − tol 인 위기 비율
rc_p2_vs_market <- function(cr, tol, subset = NULL) {
  D <- .rc_rows_dt(cr)
  if (!nrow(D) || !all(c("peak_date", "trough_date", "dd_capture") %in% names(D))) return(list(n = 0L, n_better = 0L, share = NA_real_))
  D[, k := .rc_key(D)]
  if (!is.null(subset)) D <- D[k %in% subset]
  v <- as.numeric(D$dd_capture); v <- v[is.finite(v)]
  list(n = length(v), n_better = sum(v < 1 - tol), share = if (length(v)) mean(v < 1 - tol) else NA_real_)
}
## 빠른 급락(헌장 빈칸 6 · Mishkin & White 2002 NBER WP 8992 p.7) — 출처: P2R04 L205-224 = P2R03 L103-122
##   위기 [고점, 저점] 안에서 벤치가 win 거래일 창 안에 drop 이상 하락한 구간이 있는 위기의 키 · 날짜 불일치 = 분류 못 함 · 위기 안 월말 0 = 일화 판 제외 목록
rc_p2_fast_crash_keys <- function(br, crises, win = 21L, drop = -0.20) {
  b <- as.data.table(br)[, .(date = as.Date(date), r = as.numeric(benchmark_ret))][order(date)]
  b[!is.finite(r), r := 0]; lvl <- cumprod(1 + b$r)
  me <- b[, .(d = max(date)), by = .(ym = format(date, "%Y-%m"))]$d
  cr <- .rc_rows_dt(crises)
  if (!nrow(cr) || !nrow(b)) return(list(keys = character(0), table = data.table(), unclassified = character(0), no_month_end = character(0)))
  rows <- lapply(seq_len(nrow(cr)), function(i) {
    i0 <- match(as.Date(as.character(cr$peak_date[i])), b$date); i1 <- match(as.Date(as.character(cr$trough_date[i])), b$date)
    k <- .rc_key(cr[i])
    if (is.na(i0) || is.na(i1) || i1 < i0) return(data.table(k = k, max_drop = NA_real_, fast = NA, seg_start = as.Date(NA), seg_end = as.Date(NA), month_ends_inside = NA_integer_))
    best <- 0; sa <- i0; se <- i0
    for (a in i0:i1) { e <- min(i1, a + as.integer(win)); j <- which.min(lvl[a:e]); v <- lvl[a + j - 1L] / lvl[a] - 1
                       if (v < best) { best <- v; sa <- a; se <- a + j - 1L } }
    data.table(k = k, max_drop = best, fast = best <= drop + 1e-12,                  # 1e-12 = 부동소수 여유(결정 수치 아님 — 정확히 −20% 경계)
               seg_start = b$date[sa], seg_end = b$date[se], month_ends_inside = sum(me >= b$date[i0] & me < b$date[i1]))
  })
  T <- rbindlist(rows)
  list(keys = T[fast %in% TRUE, k], table = T, unclassified = T[is.na(fast), k], win = as.integer(win), drop = drop,
       no_month_end = T[fast %in% TRUE & month_ends_inside %in% 0L, k])
}
## 강세 구간별 참여(헌장 빈칸 7) — 출처: P2R04 L228-240 = P2R03 L126-138 — 변형 상승 포착 ≥ 기준 − (1 − ratio) × |기준| 인 구간 비율 · 짝 < min_pairs = NA
rc_p2_bull_segments <- function(bull_m, bull_r, ratio = 0.8, min_pairs = 2L) {
  bm <- .rc_rows_dt(bull_m); br <- .rc_rows_dt(bull_r)
  need <- c("start_ym", "end_ym", "up_capture")
  if (!nrow(bm) || !nrow(br) || !all(need %in% names(bm)) || !all(need %in% names(br)))
    return(list(n_pair = 0L, n_ok = 0L, share = NA_real_, unpaired = nrow(bm) + nrow(br)))
  bm[, k := paste(start_ym, end_ym)]; br[, k := paste(start_ym, end_ym)]
  J <- merge(bm[, .(k, m = as.numeric(up_capture))], br[, .(k, r = as.numeric(up_capture))], by = "k")
  unp <- (nrow(bm) - nrow(J)) + (nrow(br) - nrow(J))
  J <- J[is.finite(m) & is.finite(r)]
  J[, thr := r - (1 - ratio) * abs(r)][, ok := m >= thr]
  list(n_pair = nrow(J), n_ok = sum(J$ok), share = if (nrow(J) >= min_pairs) mean(J$ok) else NA_real_, unpaired = unp,
       ratio = ratio, min_pairs = as.integer(min_pairs), per_phase = J)
}
## β 비대칭(헌장 빈칸 3 · 8) — 출처: P2R04 L242-246 · β 비의 변화량 — 출처: P2R04 L249-254 = P2R03 L140-152
rc_p2_beta_asym <- function(beta_down, beta_up) {
  bd <- suppressWarnings(as.numeric(beta_down)); bu <- suppressWarnings(as.numeric(beta_up))
  if (length(bd) != 1L || length(bu) != 1L || !is.finite(bd) || !is.finite(bu)) return(NA)
  bd < bu
}
rc_p2_beta_ratio_delta <- function(bd_v, bu_v, bd_r, bu_r) {
  x <- suppressWarnings(as.numeric(c(bd_v, bu_v, bd_r, bu_r)))
  if (length(x) != 4L || any(!is.finite(x)) || x[2] <= 0 || x[4] <= 0) return(list(ratio = NA_real_, ratio_rx0 = NA_real_, delta = NA_real_, ok = NA))
  rv <- x[1] / x[2]; rr <- x[3] / x[4]
  list(ratio = rv, ratio_rx0 = rr, delta = rv - rr, ok = rv < rr)
}
## 셀 로그 적재 줄(⑩ 구성 증거) — 출처: P2R04 L322-332 — rf_cell_engine 마지막 요약 줄 '[rf_cell_engine] cell=<code> | univ=<u> | factors=<…|none> | wt=<w> | months=N | rows=M'
rc_p2_parse_cell_log <- function(lines) {
  lines <- sub("\r$", "", as.character(lines))
  rx <- "^\\[rf_cell_engine\\] cell=([^ |]+) \\| univ=([^ |]+) \\| factors=([^ |]+) \\| wt=([^ |]+) \\| months=([0-9]+) \\| rows=([0-9]+)[[:space:]]*$"
  s <- grep(rx, lines, value = TRUE)
  if (!length(s)) return(list(found = FALSE, n_lines = 0L))
  n <- length(s); s <- s[n]
  g <- function(i) sub(rx, paste0("\\", i), s)
  fs <- g(3L)
  list(found = TRUE, n_lines = n, cell = g(1L), univ = g(2L), factors = if (identical(fs, "none")) character(0) else strsplit(fs, "+", fixed = TRUE)[[1]],
       wt = g(4L), months = as.integer(g(5L)), rows = as.integer(g(6L)))
}
## 팩터 방향 경로 줄(기록) — 출처: P2R04 L336-353 · 방향 기록 — 출처: P2R04 L356-371
rc_p2_parse_direction_lines <- function(lines) {
  lines <- sub("\r$", "", as.character(lines))
  rs <- "^\\[align_factor_direction\\] PIT-safe: sig_date=([0-9]{4}-[0-9]{2}-[0-9]{2}).*$"
  rd <- "^\\[align_factor_direction\\] loaded-factor direction: IC-inferred=([0-9]+) / registry-fallback=([0-9]+) / default-fallback=([0-9]+) \\(n_factors=([0-9]+)\\).*$"
  is_s <- grepl(rs, lines); is_d <- grepl(rd, lines)
  emp <- data.table(block = integer(0), sig_date = as.Date(character(0)), ic = integer(0), reg = integer(0), def = integer(0), n = integer(0))
  cur <- NA_character_; prev <- as.Date(NA); blk <- 0L; out <- list()
  for (i in which(is_s | is_d)) {
    if (is_s[i]) { cur <- sub(rs, "\\1", lines[i]); next }
    if (is.na(cur)) next
    d <- as.Date(cur); cur <- NA_character_
    if (is.na(prev) || d <= prev) blk <- blk + 1L
    prev <- d
    v <- as.integer(regmatches(lines[i], regexec(rd, lines[i]))[[1]][2:5])
    out[[length(out) + 1L]] <- data.table(block = blk, sig_date = d, ic = v[1], reg = v[2], def = v[3], n = v[4])
  }
  if (length(out)) rbindlist(out) else emp
}
rc_p2_direction_record <- function(D, block, from, tau) {
  D <- as.data.table(D)
  if (!nrow(D)) return(list(status = "absent"))
  nb <- max(D$block); b0 <- suppressWarnings(as.integer(block))
  if (length(b0) != 1L || is.na(b0) || b0 < 1L || b0 > nb) return(list(status = "block_mismatch", n_blocks = nb, block = b0))
  x <- D[block == b0 & sig_date <= as.Date(tau)]
  if (!is.null(from) && length(from) && !is.na(from)) {
    f0 <- suppressWarnings(max(x$sig_date[x$sig_date <= as.Date(from)]))
    if (is.finite(f0)) x <- x[sig_date >= f0]
  }
  if (!nrow(x)) return(list(status = "empty", n_blocks = nb, block = b0))
  alt <- sum(x$reg > 0L | x$def > 0L)
  list(status = "ok", n_blocks = nb, block = b0, n_sig = nrow(x), ic_inferred = sum(x$ic > 0L), registry_fallback = sum(x$reg > 0L),
       default_fallback = sum(x$def > 0L), no_data = sum(x$n == 0L), first = format(min(x$sig_date)), last = format(max(x$sig_date)),
       tag = if (alt > 0L) sprintf("팩터 방향 대체 경로 %d 신호일(평가 창) — 레지스트리 표기는 원값과 어긋나 공격 쪽일 수 있다(defense_direction_agreement.md)", alt) else NA_character_)
}
## 사양 factors 꼬리 — 출처: P2R04 L374-382(.p2_spec_tail)
.rc_p2_spec_tail <- function(spec_factors) {
  ids <- vapply(spec_factors %||% list(), function(f) as.character(f$id %||% NA_character_), character(1))
  kds <- vapply(spec_factors %||% list(), function(f) as.character(f$kind %||% NA_character_), character(1))
  n <- length(ids)
  if (!n) return(list(ids = ids, kinds = kds, m = 0L, base = character(0), tail_id = NA_character_, tail_kind = NA_character_))
  same <- !is.na(ids) & !is.na(kds) & ids == ids[n] & kds == kds[n]
  r <- rle(rev(same)); m <- if (isTRUE(r$values[1])) r$lengths[1] else 0L
  list(ids = ids, kinds = kds, m = as.integer(m), base = utils::head(ids, n - m), tail_id = ids[n], tail_kind = kds[n])
}
## ⑩ 구성 증거(사양 · 셀 로그 세 대조) — 출처: P2R04 L387-402(p2_construction_check)
rc_p2_construction_check <- function(lv, lr, dev, spec_v, spec_r, expect_cell, expect_cell_rx0) {
  tv <- .rc_p2_spec_tail(spec_v); sid_v <- tv$ids; base_v <- tv$base
  sid_r <- vapply(spec_r %||% list(), function(f) as.character(f$id %||% NA_character_), character(1))
  okS <- tv$m >= 1L && identical(tv$tail_id, dev$id) && identical(tv$tail_kind, dev$kind) && !((dev$id %||% "") %in% base_v) && identical(sid_r, base_v)
  okV <- isTRUE(lv$found) && identical(lv$cell, expect_cell) && identical(lv$factors, sid_v)
  okR <- isTRUE(lr$found) && identical(lr$cell, expect_cell_rx0) && identical(lr$factors, base_v)
  pj <- function(x) if (length(x)) paste(x, collapse = "+") else "none"
  why <- c(if (!okS) sprintf("사양: 변형 factors %s · RX0 factors %s · 장치 %s:%s 꼬리 %d회(변형 = RX0 + 장치 팩터 꼬리여야 함)", pj(sid_v), pj(sid_r),
                             dev$kind %||% "?", dev$id %||% "?", tv$m),
           if (!okV) sprintf("변형 로그: 적재 줄 %s · cell %s(기대 %s) · 적재 %s(기대 %s)", isTRUE(lv$found), lv$cell %||% "-", expect_cell, pj(lv$factors), pj(sid_v)),
           if (!okR) sprintf("RX0 로그: 적재 줄 %s · cell %s(기대 %s) · 적재 %s(기대 %s)", isTRUE(lr$found), lr$cell %||% "-", expect_cell_rx0, pj(lr$factors), pj(base_v)))
  keep <- c("found", "n_lines", "cell", "univ", "factors", "wt")
  list(ok = okS && okV && okR, why = if (length(why)) paste(why, collapse = " / ") else NA_character_,
       checks = list(spec = okS, variant_log = okV, rx0_log = okR), device = dev[c("kind", "id")], device_count = tv$m, spec_factors = sid_v, rx0_spec_factors = sid_r,
       variant_log = lv[intersect(names(lv), keep)], rx0_log = lr[intersect(names(lr), keep)])
}
## 혼합 가중 — 출처: P2R04 L406-415 — rf_cell_engine §4 Score = w0·z_base + (1−w0)·mean(z_factors) → 장치 몫 = (1 − w0) × m / n
rc_p2_blend_weight <- function(base_weight, n_factors, n_device = 1L) {
  w0 <- suppressWarnings(as.numeric(base_weight %||% NA))[1]; n <- as.integer(n_factors); m <- as.integer(n_device)
  bad <- !length(n) || is.na(n) || n < 1L || !length(m) || is.na(m) || m < 1L || m > n
  dw <- if (bad) NA_real_ else if (is.finite(w0)) (1 - w0) * m / n else m / (1 + n)
  ds <- if (bad) NA_real_ else if (is.finite(w0)) w0 else 1 / (1 + n)
  os <- if (bad) NA_real_ else if (is.finite(w0)) (1 - w0) * (n - m) / n else (n - m) / (1 + n)
  list(base_weight = w0, n_factors = n, n_device = m, device_weight = dw, dnn_share = ds, other_share = os,
       rule = "rf_cell_engine.R §4 Score = w0·z_base + (1−w0)·mean(z_factors)")
}
## 두 몫의 비(표시용) — 출처: P2R04 L417-424
rc_p2_ratio_str <- function(a, b) {
  a <- suppressWarnings(as.numeric(a))[1]; b <- suppressWarnings(as.numeric(b))[1]
  if (!length(a) || !length(b) || !is.finite(a) || !is.finite(b)) return(NA_character_)
  if (b <= 0) return("기존 팩터 없음")
  r <- a / b
  for (q in seq_len(20L)) { p <- round(r * q); if (p >= 1 && abs(p / q - r) < 1e-9) return(sprintf("%d:%d", as.integer(p), q)) }
  sprintf("%.3f:1", r)
}
## 진단 칸의 장치 항목 — 출처: P2R04 L426-435(전역 진단 · 장치 표 → 인자)
rc_p2_diag_device <- function(comp, spec_factors, diagnostics, devices) {
  dg <- diagnostics[[comp]]
  if (is.null(dg)) return(NULL)
  if (!is.na(dg[["pair"]] %||% NA_character_)) return(devices[[dg[["pair"]]]])
  f <- utils::tail(spec_factors %||% list(), 1L)
  if (!length(f)) return(NULL)
  f <- f[[1]]; sd0 <- suppressWarnings(as.numeric(f$seed %||% NA))
  if (!identical(f$kind, dg[["kind"]]) || is.null(f$id) || length(sd0) != 1L || !is.finite(sd0)) return(NULL)
  list(kind = dg[["kind"]], id = as.character(f$id), name = "무작위 순열(희석 짝)")
}
## 진단 칸 기대 장치 몫(사양에서 재도출) — 출처: P2R04 L438-453 · ★ [[ ]] 정확 일치(weight · weight_toolbox_on · weight_like 부분 일치 회귀)
rc_p2_diag_expect_weight <- function(comp, cells, root, diagnostics, devices) {
  dg <- diagnostics[[comp]]
  if (is.null(dg)) return(NA_real_)
  if (!is.null(dg[["weight"]])) return(as.numeric(dg[["weight"]]))
  sp_of <- function(eng, cp) { z <- Filter(function(c0) identical(c0$engine, eng) && identical(c0$component, cp) && !isTRUE(c0$diagnostic), cells)
                               if (length(z)) tryCatch(fromJSON(file.path(root, .rc_cell_spec(z[[1]])), simplifyVector = FALSE), error = function(e) NULL) else NULL }
  if (!is.null(dg[["weight_toolbox_on"]])) {
    s <- sp_of(dg[["weight_toolbox_on"]], "RX0"); if (is.null(s)) return(NA_real_)
    return(rc_p2_blend_weight(s$base_weight, length(s$factors %||% list()) + 1L, 1L)$device_weight)
  }
  wl <- dg[["weight_like"]]; s <- sp_of(wl$engine, wl$component); dev <- devices[[wl$component]]
  if (is.null(s) || is.null(dev)) return(NA_real_)
  tv <- .rc_p2_spec_tail(s$factors)
  if (!identical(tv$tail_id, dev$id) || !identical(tv$tail_kind, dev$kind)) return(NA_real_)
  rc_p2_blend_weight(s$base_weight, length(tv$ids), tv$m)$device_weight
}
## ⑭ 선택 귀속(라벨) — 출처: P2R04 L482-487 — 확정 라벨 밖 · 대조 상태 ok 아님 = 미측정 · 규칙 없음 = no_rule
rc_p2_selection_attr <- function(label, required, controls_status = "ok", labels = RC_P2_MC8_LABELS) {
  lb <- as.character(label %||% NA_character_)[1]; rq <- as.character(unlist(required) %||% NA_character_)[1]
  cs <- as.character(controls_status %||% NA_character_)[1]
  st <- if (is.na(rq) || !nzchar(rq)) "no_rule" else if (!identical(cs, "ok")) "unmeasured" else if (is.na(lb) || !(lb %in% labels)) "unmeasured" else "ok"
  list(label = lb, required = rq, controls_status = cs, status = st, ok = identical(st, "ok") && identical(lb, rq))
}
## ⑭ 위기 분해(C-028) — 출처: P2R04 L492-502 — 깊은 위기 selection_sum 변형 − RX0 > 0(엄격 · 문턱 없음 — 수익 단위) 과반 · 짝 ≥ 2
rc_p2_selection_decomp <- function(ex_v, ex_r, deep_peaks, maj) {
  V <- .rc_rows_dt(ex_v); R <- .rc_rows_dt(ex_r); need <- c("peak_date", "selection_sum")
  if (!nrow(V) || !nrow(R) || !all(need %in% names(V)) || !all(need %in% names(R)))
    return(list(status = "unmeasured", tag = "선택 항 분해 미측정(패킷 exposure.crises.selection_sum 없음)", n_pair = 0L, share = NA_real_, ok = FALSE))
  J <- merge(V[, .(peak_date = as.character(peak_date), sv = as.numeric(selection_sum))], R[, .(peak_date = as.character(peak_date), sr = as.numeric(selection_sum))], by = "peak_date")
  J <- J[peak_date %in% as.character(deep_peaks) & is.finite(sv) & is.finite(sr)]
  if (nrow(J) < 2L) return(list(status = "unmeasured", tag = "선택 항 분해 미측정(깊은 위기 짝 < 2)", n_pair = nrow(J), share = NA_real_, ok = FALSE, per_crisis = J))
  J[, better := sv - sr > 0]
  list(status = "ok", tag = NA_character_, n_pair = nrow(J), n_better = sum(J$better), share = mean(J$better), ok = rc_maj(mean(J$better), maj),
       rule = "깊은 위기마다 selection_sum 변형 − RX0 > 0(엄격 · 문턱 없음 — 수익 단위) · 과반 > majority_share · 짝 ≥ 2", per_crisis = J)
}
## ⑭ 통과 = MC8 라벨 일치 ∧ 위기 분해 과반 — 출처: P2R04 L504-509
rc_p2_selection_rule <- function(attr, decomp) {
  st <- if (!identical(attr$status, "ok")) attr$status else if (!identical(decomp$status, "ok")) "unmeasured(선택 항 분해)" else "ok"
  c(attr[c("label", "required")], list(label_status = attr$status, label_ok = isTRUE(attr$ok), controls_status = attr$controls_status %||% NA_character_,
                                       decomposition = decomp, status = st, measured = identical(st, "ok"),
                                       ok = isTRUE(attr$ok) && isTRUE(decomp$ok)))
}
## 기록용 위기(상태 미전환 최대 하락 위기 · C-019) — 출처: P2R04 L512-525
rc_p2_crisis_record <- function(cr_m, cr_r, cr_b, keys, tol, deep = character(0), fast = character(0)) {
  keys <- as.character(unlist(keys))
  if (!length(keys)) return(data.table())
  kv <- function(x) { D <- .rc_rows_dt(x); if (!nrow(D) || !all(c("peak_date", "trough_date", "dd_capture") %in% names(D))) return(setNames(numeric(0), character(0)))
                      setNames(as.numeric(D$dd_capture), .rc_key(D)) }
  M <- kv(cr_m); R <- kv(cr_r); B <- kv(cr_b)
  at <- function(v, k) if (k %in% names(v)) unname(v[[k]]) else NA_real_
  rbindlist(lapply(keys, function(k) {
    m <- at(M, k); r <- at(R, k); b <- at(B, k)
    data.table(crisis = k, in_pairs = is.finite(m) && is.finite(r), deep = k %in% deep, fast = k %in% fast,
               dd_capture = m, dd_capture_rx0 = r, dd_capture_beta_copy = b,
               beats_rx0 = if (is.finite(m) && is.finite(r)) m < r - tol else NA, beats_beta_copy = if (is.finite(m) && is.finite(b)) m < b - tol else NA)
  }))
}
## 위기 중 크기 분위 — 출처: P2R04 L527-541
rc_p2_size_profile <- function(bsd) {
  B <- .rc_rows_dt(bsd)
  if (!nrow(B) || !all(c("size_decile", "n", "peak_date") %in% names(B))) return(data.table())
  B[, `:=`(peak_date = as.character(peak_date), size_decile = suppressWarnings(as.numeric(size_decile)), n = as.numeric(n))]
  B[, .(n_names = sum(n), n_unknown = sum(n[!is.finite(size_decile)]),
        mean_decile = if (any(is.finite(size_decile))) sum((size_decile * n)[is.finite(size_decile)]) / sum(n[is.finite(size_decile)]) else NA_real_), by = peak_date]
}
rc_p2_size_compare <- function(bsd_v, bsd_r, deep_peaks = character(0)) {
  V <- rc_p2_size_profile(bsd_v); R <- rc_p2_size_profile(bsd_r)
  if (!nrow(V)) return(list(status = "absent"))
  J <- if (nrow(R)) merge(V, R, by = "peak_date", all.x = TRUE, suffixes = c("", "_rx0")) else copy(V)[, `:=`(n_names_rx0 = NA_real_, n_unknown_rx0 = NA_real_, mean_decile_rx0 = NA_real_)]
  dm <- function(v) { v <- v[is.finite(v)]; if (length(v)) mean(v) else NA_real_ }
  list(status = "ok", per_crisis = J, deep_mean_decile = dm(J[peak_date %in% as.character(deep_peaks), mean_decile]),
       deep_mean_decile_rx0 = dm(J[peak_date %in% as.character(deep_peaks), mean_decile_rx0]))
}
## 유동성 분위(C-020) — 출처: P2R04 L543-548
rc_p2_liq_deciles <- function(x, univ) {
  u <- suppressWarnings(as.numeric(univ)); u <- u[is.finite(u)]; x <- suppressWarnings(as.numeric(x))
  if (length(u) < 10L) return(rep(NA_integer_, length(x)))
  bp <- stats::quantile(u, probs = seq_len(9) / 10, names = FALSE, type = 7)
  ifelse(is.finite(x), findInterval(x, bp) + 1L, NA_integer_)
}
## 국면별 월 차이 — 출처: P2R04 L550-561
.rc_p2_months <- function(a, b) { a <- suppressWarnings(as.Date(paste0(substr(a, 1, 7), "-01"))); b <- suppressWarnings(as.Date(paste0(substr(b, 1, 7), "-01")))
  if (!length(a) || !length(b) || is.na(a) || is.na(b) || b < a) character(0) else format(seq(a, b, by = "month"), "%Y-%m") }
rc_p2_regime_diff <- function(ym, d, crises, bulls) {
  cr <- .rc_rows_dt(crises); bl <- .rc_rows_dt(bulls)
  cm <- if (nrow(cr)) unique(unlist(lapply(seq_len(nrow(cr)), function(i) .rc_p2_months(as.character(cr$peak_date[i]), as.character(cr$trough_date[i]))))) else character(0)
  bm <- if (nrow(bl) && all(c("start_ym", "end_ym") %in% names(bl))) unique(unlist(lapply(seq_len(nrow(bl)), function(i) .rc_p2_months(as.character(bl$start_ym[i]), as.character(bl$end_ym[i]))))) else character(0)
  D <- data.table(ym = as.character(ym), d = suppressWarnings(as.numeric(d)))[is.finite(d)]
  D[, cls := fifelse(ym %in% cm, "crisis", fifelse(ym %in% bm, "bull", "other"))]
  one <- function(c0) { v <- D[cls == c0, d]; list(n = length(v), mean = if (length(v)) mean(v) else NA_real_) }
  list(n_months = nrow(D), crisis = one("crisis"), bull = one("bull"), other = one("other"),
       rule = "월 분류 = 위기(고점 월 ~ 저점 월) 우선 → 강세 구간(start_ym ~ end_ym) → 그 밖 · 차이 = 변형 − RX0 월 수익(계약 bc_monthly)")
}
## RX0 동일성(C-025) — 출처: P2R04 L563-575 · prev = 대조 라운드 이름(필드 접미 — P2R04 판 = 'p2r03')
rc_p2_rx0_identity_core <- function(H4, H3, pr4, pr3, tau, cur = "p2r04", prev = "p2r03") {
  tau <- as.Date(tau)
  ov <- rc_holdings_overlap(H4, H3, tau)
  a <- as.data.table(pr4)[as.Date(date) <= tau, .(date = as.Date(date), r4 = as.numeric(ret_net))]
  b <- as.data.table(pr3)[as.Date(date) <= tau, .(date = as.Date(date), r3 = as.numeric(ret_net))]
  J <- merge(a, b, by = "date")
  M <- if (nrow(J)) J[, .(diff = any(xor(is.na(r4), is.na(r3)) | (!is.na(r4) & !is.na(r3) & r4 != r3))), by = .(ym = format(date, "%Y-%m"))] else data.table(ym = character(0), diff = logical(0))
  hs <- identical(ov$status, "ok") && identical(ov$n_differ, 0L) && identical(as.integer(ov$n_only_variant), 0L) && identical(as.integer(ov$n_only_rx0), 0L)
  only <- (nrow(a) - nrow(J)) + (nrow(b) - nrow(J))
  r <- list(holdings_same = hs, holdings_dates = ov$n_dates, holdings_dates_differ = ov$n_differ)
  r[[paste0("holdings_dates_only_", cur)]] <- ov$n_only_variant %||% NA_integer_
  r[[paste0("holdings_dates_only_", prev)]] <- ov$n_only_rx0 %||% NA_integer_
  c(r, list(returns_same = nrow(M) > 0L && !any(M$diff) && only == 0L, months_compared = nrow(M), months_differ = sum(M$diff), days_only_one_side = only))
}
## 칸 통과(사전 고정) — 출처: P2R04 L577-580 — ① ∧ ② ∧ ③ ∧ ④ ∧ ⑤ ∧ ⑥ ∧ ⑦ ∧ ⑨ ∧ ⑩ ∧ ⑫ ∧ ⑬ ∧ ⑭(⑧ = 제외 판정 · ⑪ = 꼬리표)
rc_p2_cell_pass <- function(f) {
  isTRUE(f$crisis) && isTRUE(f$deep) && isTRUE(f$beta_deep) && isTRUE(f$fast) && isTRUE(f$beta_ratio) && isTRUE(f$bull) &&
    isTRUE(f$alpha) && isTRUE(f$cycle) && isTRUE(f$construction) && isTRUE(f$S) && isTRUE(f$path) && isTRUE(f$selection)
}
## 칸 판정 어휘 — 출처: P2R04 L586-596(위에서 아래로 첫 해당)
rc_p2_cell_verdict <- function(f) {
  r3 <- f$beta_deep %||% NA; r4 <- f$fast %||% NA; s14 <- isTRUE(f$selection); m14 <- isTRUE(f$selection_measured)
  dec <- isTRUE(f$crisis) && isTRUE(f$deep) && isTRUE(r3) && isTRUE(r4)
  if (isTRUE(f$pass)) "pass" else
  if (isTRUE(f$beta_unmeasured) || is.na(r3)) "beta_unmeasured" else
  if (is.na(r4) && isTRUE(r3)) "fast_unmeasured" else
  if (isTRUE(f$crisis) && isTRUE(f$deep) && !isTRUE(r3)) "exposure_only" else
  if (isTRUE(r3) && isTRUE(r4) && !m14) "selection_unmeasured" else
  if (isTRUE(r3) && isTRUE(r4) && !s14) "size_or_exposure_defense" else
  if (dec && s14) "defense_but_strength_or_path" else "not_decisive"
}
## 결론 이름(판정 아님) — 출처: P2R04 L599-609
rc_p2_defense_name <- function(r3, r4, level, s14, sb_ok, sb_status, s14_measured = TRUE) {
  if (is.na(r3 %||% NA) || is.na(r4 %||% NA)) return("방어 이름 보류(③ · ④ β 짝 미측정)")
  if (!isTRUE(r3) || !isTRUE(r4)) return("방어 이름 없음(③ · ④ β 짝 미통과)")
  if (is.na(level %||% NA)) return("방어 이름 보류(⑤ 수준 미측정)")
  if (!isTRUE(level)) return("노출(β) 방어(⑤ 수준 역행 — 하락 β ≥ 상승 β)")
  if (!isTRUE(s14_measured)) return("방어 이름 보류(⑭ 선택 귀속 미측정)")
  if (!isTRUE(s14)) return("크기 방어 또는 노출 방어(⑭ 미통과)")
  if (!identical(sb_status, "ok")) return("방어(크기 × β 짝 미측정 — '선택(특성) 방어' 이름 보류)")
  if (!isTRUE(sb_ok)) return("크기 × β 방어(크기 × β 짝 미통과 — '선택(특성) 방어' 이름 불가)")
  "선택(특성) 방어"
}

## ── 진단 읽기(판정 아님 · 보는 창) — 출처: P2R04 L649-721 ─────────────────────────────────
.rc_p2_wins <- function(D, tol) { D <- as.data.table(D %||% data.table()); if (!nrow(D) || !all(c("k", "m", "r") %in% names(D))) return(NULL)
                                  D[is.finite(m) & is.finite(r) & m < r - tol, k] }
rc_p2_read_overlap_wins <- function(a_pc, b_pc, tol) {
  wa <- .rc_p2_wins(a_pc, tol)
  if (is.null(wa)) return(list(status = "unmeasured", n_a = NA_integer_, both = character(0), a_only = character(0), unknown = character(0)))
  wb <- .rc_p2_wins(b_pc, tol); kb <- if (is.null(wb)) character(0) else as.character(as.data.table(b_pc)$k)
  list(status = if (is.null(wb)) "b_unmeasured" else "ok", n_a = length(wa), both = intersect(wa, wb %||% character(0)),
       a_only = setdiff(intersect(wa, kb), wb %||% character(0)), unknown = setdiff(wa, kb))
}
rc_p2_read_missing <- function(h, c0, tol) {
  if (!isTRUE(h$tested)) return(list(status = "unmeasured", why = "장치 칸 미시험"))
  if (!isTRUE(c0$tested)) return(list(status = "unmeasured", why = paste("결측 짝 미시험:", c0$why %||% "칸 없음")))
  ov <- rc_p2_read_overlap_wins(h$rules$beta_deep$per_crisis, c0$rules$beta_deep$per_crisis, tol)
  list(status = ov$status, device = h$device, diag_cell = c0$cell %||% NA_character_, n_win = ov$n_a, missing_pattern = ov$both, n_missing_pattern = length(ov$both),
       not_missing = ov$a_only, n_not_missing = length(ov$a_only), unknown = ov$unknown,
       tag = if (length(ov$both)) sprintf("결측 패턴 방어 %d/%s 위기(β 짝 승리 중 결측 짝도 이김)", length(ov$both), format(ov$n_a)) else NA_character_)
}
rc_p2_capacity_label <- function(e2_50, e3_50, e2_12, e3_12, table) {
  x <- c(e2_50 = e2_50, e3_50 = e3_50, e2_12 = e2_12, e3_12 = e3_12)
  if (length(x) != 4L || anyNA(x)) return(NA_character_)
  for (i in seq_len(nrow(table))) {
    pat <- unlist(table[i, .(e2_50, e3_50, e2_12, e3_12)])
    if (all(is.na(pat) | pat == x)) return(table$label[i])
  }
  NA_character_
}
rc_p2_read_capacity <- function(e2h, e3h, e2w, e3w, table) {
  f <- function(x) if (isTRUE(x$tested)) isTRUE(x$pass) else NA
  w <- function(x) suppressWarnings(as.numeric(x$construction$blend$device_weight %||% NA))[1]
  W <- c(e2_50 = w(e2h), e3_50 = w(e3h), e2_12 = w(e2w), e3_12 = w(e3w))
  wok <- all(is.finite(W)) && abs(W[["e2_50"]] - W[["e3_50"]]) < 1e-9 && abs(W[["e2_12"]] - W[["e3_12"]]) < 1e-9 && W[["e2_12"]] < W[["e2_50"]]   # 1e-9 = 부동소수 여유
  P <- c(e2_50 = f(e2h), e3_50 = f(e3h), e2_12 = f(e2w), e3_12 = f(e3w))
  lab <- if (anyNA(P)) "미측정(네 칸 중 미시험)" else if (!wok) "미측정(가중 불일치 — 같은 처치 50% · 12.5% 구성 아님)" else
         rc_p2_capacity_label(P[["e2_50"]], P[["e3_50"]], P[["e2_12"]], P[["e3_12"]], table) %||% "미측정(표 밖)"
  cmp <- function(x) { b <- x$construction$blend; if (is.null(b)) NA_character_ else rc_p2_ratio_str(b$dnn_share, b$other_share) }
  r50 <- cmp(e3h); r12 <- cmp(e3w)
  note <- if (!is.na(r50) && !is.na(r12) && !identical(r50, r12))
    sprintf("E3 용량 짝 W 는 방어 몫 외에 DNN : 기존 팩터 비율도 %s → %s 로 바뀐다(구성 차이 혼재 — 용량 읽기는 이 차이를 함께 읽는다)", r50, r12) else NA_character_
  list(passes = as.list(P), weights = as.list(W), weights_ok = wok, label = lab, e3_composition = c(e3_50 = r50, e3_12 = r12), composition_note = note,
       verdicts = c(e2_50 = e2h$verdict %||% NA_character_, e3_50 = e3h$verdict %||% NA_character_, e2_12 = e2w$verdict %||% NA_character_, e3_12 = e3w$verdict %||% NA_character_))
}
rc_p2_read_dilution <- function(h, n0, tol) {
  if (!isTRUE(h$tested)) return(list(status = "unmeasured", why = "장치 칸 미시험"))
  if (!isTRUE(n0$tested)) return(list(status = "unmeasured", why = paste("희석 짝 미시험:", n0$why %||% "칸 없음")))
  ov <- rc_p2_read_overlap_wins(h$rules$crisis$per_crisis, n0$rules$crisis$per_crisis, tol)
  list(status = ov$status, device = h$device, n_improve = ov$n_a, dilution_share = ov$both, n_dilution = length(ov$both),
       not_dilution = ov$a_only, n_not_dilution = length(ov$a_only), unknown = ov$unknown,
       tag = if (length(ov$both)) sprintf("희석 몫 %d/%s 위기(① 개선 중 무작위 순열 팩터도 개선)", length(ov$both), format(ov$n_a)) else NA_character_)
}
rc_p2_diag_summary <- function(x) if (!isTRUE(x$tested)) list(tested = FALSE, why = x$why %||% NA_character_) else
  list(tested = TRUE, verdict = x$verdict, treatment_delivered = x$treatment_delivered %||% NA,
       crisis = list(share = x$rules$crisis$share, ok = x$rules$crisis$ok), deep = list(share = x$rules$deep$share, ok = x$rules$deep$ok),
       beta_deep = list(status = x$rules$beta_deep$status, share = x$rules$beta_deep$share, ok = x$rules$beta_deep$ok))
## 진단 읽기 묶음(결측 · 용량 · 희석) — 출처: P2R04 L708-721(진단 표 · 장치 표 · 진단 엔진 · 용량 표 = 인자)
rc_p2_readings <- function(OUT, DOUT, tol, devices, diagnostics, diag_engine, capacity_table) {
  fnd <- function(L, eng, comp) { z <- Filter(function(x) identical(x$engine, eng) && identical(x$device, comp), L); if (length(z)) z[[1]] else list(tested = FALSE, why = "칸 없음") }
  cof <- function(rd, h) { z <- names(Filter(function(d) identical(d[["reading"]], rd) && identical(d[["pair"]], h), diagnostics)); if (length(z)) z[1] else NA_character_ }
  engs <- unique(vapply(OUT, function(x) as.character(x$engine %||% NA_character_), character(1)))
  other <- setdiff(engs[!is.na(engs)], diag_engine)[1]
  oe <- if (length(other) && !is.na(other)) other else ""
  n0c <- names(Filter(function(d) identical(d[["reading"]], "dilution"), diagnostics))[1]
  n0 <- fnd(DOUT, diag_engine, n0c)
  list(diag_engine = diag_engine, other_engine = if (nzchar(oe)) oe else NA_character_,
       missing = setNames(lapply(devices, function(h) rc_p2_read_missing(fnd(OUT, diag_engine, h), fnd(DOUT, diag_engine, cof("missing", h)), tol)), devices),
       capacity = setNames(lapply(devices, function(h) rc_p2_read_capacity(fnd(OUT, diag_engine, h), fnd(OUT, oe, h),
                                                                         fnd(DOUT, diag_engine, cof("capacity", h)), fnd(DOUT, oe, cof("capacity", h)), capacity_table)), devices),
       dilution = list(n0 = rc_p2_diag_summary(n0), by_device = setNames(lapply(devices, function(h) rc_p2_read_dilution(fnd(OUT, diag_engine, h), n0, tol)), devices)))
}
## A 거리(C-031 기록) — 출처: P2R04 L724-730
rc_p2_a_distance <- function(perf, bench_calmar, th, S = NA_real_, a_boundary = NA_real_) {
  v <- function(k) suppressWarnings(as.numeric(perf[[k]] %||% NA))[1]
  one <- function(x, t) { x <- suppressWarnings(as.numeric(x))[1]; t <- suppressWarnings(as.numeric(t))[1]
                          list(value = x, threshold = t, distance = x - t, meets = is.finite(x) && is.finite(t) && x >= t) }
  list(cagr = one(v("cagr"), th$cagr_min), sharpe = one(v("sharpe"), th$sharpe_min), calmar = one(v("calmar"), bench_calmar),
       port_t = one(v("port_t"), th$port_t_b), S = one(S, a_boundary))
}
## R7 판독(C-029 · lean-loop 예산) — 출처: P2R04 L737-766 · 판정된 장치(두 구성 tested ∧ ③ 측정 ∧ S 증분 유한) < 2 = 판독 불가(NA)
rc_p2_noise_reading <- function(OUT, validated, tie_eps, maj, devices) {
  per <- lapply(devices, function(dv) {
    xs <- Filter(function(x) identical(x$device, dv), OUT)
    tst <- vapply(xs, function(x) isTRUE(x$tested), logical(1))
    st3 <- vapply(xs, function(x) as.character(x$rules$beta_deep$status %||% NA_character_)[1], character(1))
    np3 <- vapply(xs, function(x) suppressWarnings(as.integer(x$rules$beta_deep$n_pair %||% NA))[1], integer(1))
    sh3 <- vapply(xs, function(x) suppressWarnings(as.numeric(x$rules$beta_deep$share %||% NA))[1], numeric(1))
    dS <- vapply(xs, function(x) if (isTRUE(x$tested)) suppressWarnings(as.numeric(x$non_inferiority$S - x$non_inferiority$S_rx0))[1] else NA_real_, numeric(1))
    r3m <- tst & st3 %in% "ok" & !is.na(np3) & np3 >= 2L & is.finite(sh3)
    judged <- length(xs) == 2L && all(r3m) && all(is.finite(dS))
    why <- if (length(xs) != 2L) sprintf("구성 칸 %d개(2개여야 함)", length(xs)) else if (!all(tst)) "미시험 구성 있음" else
           if (!all(r3m)) sprintf("③ 미측정 구성 있음(%s)", paste(ifelse(is.na(st3), "NA", st3), collapse = " / ")) else if (!all(is.finite(dS))) "S 증분 비유한" else NA_character_
    list(device = dv, n_cells = length(xs), r3_status = unname(st3), r3_share = unname(sh3), r3_measured = unname(r3m), judged = judged, dropped_why = why,
         r3_both = judged && all(vapply(sh3, rc_maj, logical(1), maj = maj)), dS_mean = if (judged) mean(dS) else NA_real_)
  })
  jd <- vapply(per, function(p) isTRUE(p$judged), logical(1)); nb <- sum(jd)
  dmv <- vapply(per, function(p) p$dS_mean, numeric(1))[jd]; n3 <- sum(vapply(per, function(p) isTRUE(p$r3_both), logical(1))[jd])
  dmax <- if (any(is.finite(dmv))) max(dmv[is.finite(dmv)]) else NA_real_
  c1 <- !length(validated); c2 <- n3 == 0L; c3 <- is.finite(dmax) && dmax < as.numeric(tie_eps)
  readable <- nb >= 2L
  res <- if (!readable) NA else c1 && c2 && c3
  dropped <- lapply(per[!jd], function(p) list(device = p$device, why = p$dropped_why))
  list(result = res, label = if (!readable) sprintf("판독 불가(판정된 장치 %d/%d < 2 — 두 구성 tested ∧ ③ 측정)", nb, length(devices)) else if (isTRUE(res)) "잡음 이내" else "잡음 밖",
       judged_devices = sprintf("%d/%d", nb, length(devices)), n_devices_judged_both = nb, n_devices = length(devices),
       judged = vapply(per[jd], function(p) p$device, character(1)), dropped = dropped,
       components = list(no_validated = c1, no_device_r3_both = c2, max_dS_below_tie = c3),
       n_validated = length(validated), n_device_r3_both = n3, max_dS = dmax, tie_eps = as.numeric(tie_eps), per_device = per,
       rule = paste0("R7 판독(C-029) — 판정된 장치(두 구성 tested ∧ ③ 측정 · 짝 ≥ 2 ∧ S 증분 유한) < 2 = 판독 불가 · 아니면 검증 0 ∧ 판정된 장치 중 두 구성 ",
                     "③ 비율 > majority_share 인 장치 0 ∧ 판정된 장치 S 증분(두 구성 평균) 최대 < tie_eps = 잡음 이내"))
}
## final_selection_rule 키 결손 — 출처: P2R04 L768
rc_p2_fs_missing <- function(FS, keys = RC_P2_FS_KEYS) setdiff(keys, names(FS %||% list()))
## 사전등록 칸 목록 검사 — 출처: P2R04 L772-800 · code = <prefix>_<engine>_<component> · 판정 엔진 2 · 엔진마다 RX0 1 · 진단 칸 규칙
rc_p2_cells_check <- function(cells, devices, diags, diag_engine, prefix) {
  if (!length(cells)) return("칸 없음")
  f <- function(k) vapply(cells, function(z) as.character(z[[k]] %||% NA_character_), character(1))
  cd <- f("code"); en <- f("engine"); cp <- f("component")
  rf <- vapply(cells, function(z) isTRUE(z[["reference"]]), logical(1)); dg <- vapply(cells, function(z) isTRUE(z[["diagnostic"]]), logical(1))
  bad <- character(0)
  if (anyNA(cd) || anyNA(en) || anyNA(cp)) bad <- c(bad, "code · engine · component 결측")
  if (anyDuplicated(cd)) bad <- c(bad, "code 중복")
  wrong <- !is.na(cd) & cd != paste0(prefix, "_", en, "_", cp)
  if (any(wrong)) bad <- c(bad, sprintf("code ≠ %s_<engine>_<component>: %s", prefix, paste(cd[wrong], collapse = ",")))
  if (any(rf != (cp %in% "RX0"))) bad <- c(bad, "reference ≠ (component == RX0)")
  if (any(dg != (cp %in% names(diags)))) bad <- c(bad, "diagnostic ≠ (component ∈ 진단 표)")
  unk <- setdiff(unique(cp[!is.na(cp)]), c("RX0", names(devices), names(diags))); if (length(unk)) bad <- c(bad, paste("장치 · 진단 표에 없는 부품:", paste(unk, collapse = ",")))
  out_eng <- dg & !is.na(cp) & !mapply(function(e, k) isTRUE(e %in% (diags[[k]][["engines"]] %||% character(0))), en, cp)
  if (any(out_eng)) bad <- c(bad, paste("진단 칸이 진단 표 engines 밖:", paste(cd[out_eng], collapse = ",")))
  ue <- unique(en[!is.na(en) & !dg])
  if (length(ue) != 2L) bad <- c(bad, sprintf("판정 엔진 %d개(2개여야 함 — 장치 검증 = 두 엔진 통과)", length(ue)))
  for (e in ue) { ce <- cp[en %in% e & !dg]; if (sum(ce %in% "RX0") != 1L) bad <- c(bad, sprintf("%s RX0 %d칸(1칸이어야 함)", e, sum(ce %in% "RX0")))
                  if (anyDuplicated(ce)) bad <- c(bad, sprintf("%s 부품 중복", e)) }
  ds <- unique(lapply(ue, function(e) sort(setdiff(cp[en %in% e & !dg], "RX0"))))
  if (length(ds) > 1L) bad <- c(bad, "엔진마다 장치 집합이 다르다")
  dset <- if (length(ds)) ds[[1]] else character(0)
  pr <- unique(unlist(lapply(cp[dg & !is.na(cp)], function(k) diags[[k]][["pair"]] %||% NA_character_)))
  pr <- pr[!is.na(pr)]
  if (length(setdiff(pr, dset))) bad <- c(bad, paste("진단 짝 장치가 판정 장치 집합 밖:", paste(setdiff(pr, dset), collapse = ",")))
  de <- unique(en[dg & !is.na(en)])
  if (length(setdiff(de, en[!dg & cp %in% "RX0"]))) bad <- c(bad, paste("진단 칸 엔진에 RX0 칸 없음:", paste(setdiff(de, en[!dg & cp %in% "RX0"]), collapse = ",")))
  bad
}
## 보는 창 판정 칸 — 출처: P2R04 L823-827(사람 쪽 항목 제거 · 공통 창 사본 행 수 제거 · τ_D 이후 날짜 가림)
rc_p2_visible_only <- function(x, tau, drop = RC_P2_VISIBLE_DROP) {
  for (k in drop) x[[k]] <- NULL
  if (is.list(x$trim)) for (s in names(x$trim)) if (is.list(x$trim[[s]])) x$trim[[s]]$n_pr <- NULL
  rc_redact_after_tau(x, tau)
}

## ── 계약 호출 기록 도우미(보는 창 · 판정 아님 · 실패 = 그 기록만 미측정 꼬리표) — 출처: P2R04 L884-973 ─────────────
## 크기 × β 짝(C-017) — 출처: P2R04 L884-911
rc_p2_size_beta_record <- function(X, dir, PM, cr_v, deep, tol, maj) {
  E <- X$env$E; TAU <- X$tau
  rd <- .dp_read(E, dir)
  prv <- rd$pr[date <= TAU][order(date)]; brv <- rd$br[date <= TAU][order(date)]; Hv <- rd$H[date <= TAU]
  uni <- as.character(rd$spec$universe %||% rd$man$universe_id %||% NA_character_)[1]
  if (is.na(uni) || !nzchar(uni)) stop("유니버스 미상")
  raw <- rc_raw_get(X)
  cfg <- E$mc_cfg(X$root)
  win <- E$.mc_windows(prv$date, Hv$date, rd$src$exec_price)
  sb <- E$mc_size_basket(Hv, raw, cfg, uni)
  if (!nrow(sb$members)) stop("크기 바스켓을 못 만들었다(모든 리밸)")
  bk <- E$.mc_basket_returns(sb$members, win, raw)
  if (!nrow(bk) || max(bk$date) > TAU) stop("바스켓 수익이 비었거나 τ_D 를 넘는다")
  M <- merge(E$bc_monthly(bk[, .(date, r = ret)], "r")[, .(ym, s = r)], E$bc_monthly(brv[, .(date, r = benchmark_ret)], "r")[, .(ym, k = r)], by = "ym")
  bb <- E$.bc_beta(M$s, M$k); bv <- rc_getf(PM, "behavior.stats.beta")
  plan <- rc_p2_size_beta_plan(bv, bb)
  base <- list(beta_variant = bv, beta_basket = bb, basket_rebalances_ok = sum(sb$diag$status == "ok"), basket_rebalances = nrow(sb$diag))
  if (identical(plan$mode, "unmeasured")) return(c(list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = "β 비 비유한 또는 ≤ 0"), base, plan))
  CR <- .rc_rows_dt(PM$behavior$crises)
  if (!nrow(CR)) return(c(list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = "위기 없음"), base, plan))
  CR[, `:=`(peak_date = as.Date(as.character(peak_date)), trough_date = as.Date(as.character(trough_date)))]
  att <- E$bc_attach_controls(list(crises = CR, cfg = list(majority_share = maj)), list(size_beta = bk[, .(date, ret = plan$scale * ret)]),
                              brv[, .(date, benchmark_ret)], tol = 0)$controls$size_beta
  if (!identical(att$status, "ok")) return(c(list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = paste("대조 위기 포착:", att$status %||% "?")), base, plan))
  pc <- as.data.table(att$per_crisis)
  CRc <- copy(CR)[, dd_capture := pc$control_dd_capture[match(peak_date, as.Date(pc$peak_date))]]
  c(list(status = "ok", tag = NA_character_), base, plan, rc_p2_size_beta_core(cr_v, CRc, deep, tol, maj))
}
## 유동성 패널(C-020) — 출처: P2R04 L913-922 · 프로세스당 1회(X$env$liq) — 같은 RAWDATA 지문이면 디스크 메모(비압축 RDS)를 쓸 수 있다
rc_p2_liq_panel <- function(root, tau, disk = FALSE) {
  rp <- file.path(root, ".cache/RAWDATA.parquet")
  f <- file.path(rc_cache_dir(root, "liq"), paste0("liq_", .rc_digest(list(.rc_file_fp(rp), format(as.Date(tau)), "p2_liq_panel_v1")), ".rds"))
  if (isTRUE(disk) && file.exists(f)) { L <- readRDS(f); data.table::setalloccol(L); setkey(L, Date, Ticker); return(L) }
  L <- as.data.table(arrow::read_parquet(rp, col_select = c("Date", "Ticker", "Close", "Vol")))
  if (!inherits(L$Date, "Date")) L[, Date := as.Date(Date)]
  L <- L[Date <= as.Date(tau)]
  setorder(L, Ticker, Date)
  L[, adv20_l1 := shift(frollmean(as.numeric(Close) * as.numeric(Vol), 20L, align = "right"), 1L), by = Ticker]
  L <- L[, .(Date, Ticker = as.character(Ticker), Vol = as.numeric(Vol), adv20_l1)]
  setkey(L, Date, Ticker)
  if (isTRUE(disk)) { tmp <- paste0(f, ".tmp", Sys.getpid()); saveRDS(L, tmp, compress = FALSE); if (!file.rename(tmp, f)) unlink(tmp) }
  L
}
## 유동성 귀속(C-020 기록) — 출처: P2R04 L924-958
rc_p2_liquidity_record <- function(X, dir, crises, deep_peaks) {
  E <- X$env$E; TAU <- X$tau
  raw <- rc_raw_get(X)
  if (!"HYG" %in% names(raw)) stop("위생 멤버십(HYG) 없음 — 측정 유니버스 분위를 정할 수 없다")
  if (is.null(X$env$liq)) X$env$liq <- rc_p2_liq_panel(X$root, TAU, disk = isTRUE(X[["raw_disk_cache"]]))
  L <- X$env$liq; RW <- raw
  rd <- .dp_read(E, dir)
  prv <- rd$pr[date <= TAU]
  Hv <- rd$H[date <= TAU & is.finite(target_weight) & target_weight > 0, .(exec_date = date, Ticker = as.character(ticker))]
  win <- E$.mc_windows(prv$date, unique(Hv$exec_date), rd$src$exec_price)
  CR <- .rc_rows_dt(crises)
  if (!nrow(CR)) stop("위기 없음")
  rows <- lapply(seq_len(nrow(CR)), function(i) {
    p0 <- as.Date(as.character(CR$peak_date[i])); t0 <- as.Date(as.character(CR$trough_date[i]))
    D <- win[date > p0 & date <= t0]
    if (!nrow(D)) return(NULL)
    PR <- merge(D, Hv, by = "exec_date", allow.cartesian = TRUE)
    if (!nrow(PR)) return(NULL)
    d0 <- min(D$date); tk <- unique(PR$Ticker)
    hyg <- RW$Ticker[as.integer(RW$Date) == as.integer(d0) & RW$HYG %in% TRUE]
    U <- L[.(d0)][Ticker %in% hyg & is.finite(adv20_l1) & adv20_l1 > 0]
    dec <- rc_p2_liq_deciles(U$adv20_l1[match(tk, U$Ticker)], U$adv20_l1)
    Z <- L[.(PR$date, PR$Ticker), nomatch = NA]
    v <- Z$Vol[is.finite(Z$Vol)]
    data.table(peak_date = format(p0), asof = format(d0), n_names = length(tk), n_unknown = sum(is.na(dec)),
               mean_decile = if (any(!is.na(dec))) mean(dec, na.rm = TRUE) else NA_real_,
               n_holding_days = nrow(PR), n_vol_known = length(v), zero_vol_share = if (length(v)) mean(v <= 0) else NA_real_)
  })
  T <- rbindlist(rows)
  if (!nrow(T)) stop("위기 보유창 없음")
  dm <- function(v) { v <- v[is.finite(v)]; if (length(v)) mean(v) else NA_real_ }
  list(status = "ok", per_crisis = T, deep_mean_decile = dm(T[peak_date %in% as.character(deep_peaks), mean_decile]),
       deep_zero_vol_share = dm(T[peak_date %in% as.character(deep_peaks), zero_vol_share]),
       rule = "유동성 = 20일 평균 거래대금(Close × Vol) t−1 · 위기 첫 보유일 as-of 위생 멤버 10분위 · 무거래일 = 보유 종목 × 위기 거래일 중 Vol ≤ 0")
}
## 국면별 월 차이 입출력 — 출처: P2R04 L960-964
rc_p2_regime_months <- function(X, am, ar, PM) {
  E <- X$env$E; mon <- function(d) { rd <- .dp_read(E, d); E$bc_monthly(rd$pr[date <= X$tau, .(date, r = ret_net)], "r") }
  D <- merge(mon(am)[, .(ym, s = r)], mon(ar)[, .(ym, b = r)], by = "ym")[order(ym)]
  rc_p2_regime_diff(D$ym, D$s - D$b, PM$behavior$crises %||% list(), PM$behavior$bull_phases %||% list())
}
## RX0 동일성 입출력(C-025) — 출처: P2R04 L966-973 · json3 = 대조 라운드 같은 엔진 RX0 측정 결과(json 의 ok · artifacts 만)
rc_p2_rx0_identity <- function(X, art4, json3, cur = "p2r04", prev = "p2r03") {
  st <- function(s) { r <- list(status = s); r[[prev]] <- json3; r }
  if (!file.exists(json3)) return(st("absent"))
  j <- fromJSON(json3, simplifyVector = FALSE)
  if (!isTRUE(j$ok) || is.null(j$artifacts)) return(st(paste0(prev, "_not_ok")))
  E <- X$env$E; d4 <- E$ta_resolve_artifact(art4)$dir; d3 <- E$ta_resolve_artifact(j$artifacts)$dir
  rp <- function(d) { x <- fread(file.path(d, "03_period_returns.csv")); x[, date := as.Date(date)]; x }
  r <- list(status = "ok"); r[[prev]] <- sub(paste0("^", X$root, "/"), "", json3)
  c(r, rc_p2_rx0_identity_core(rc_read_holdings(d4), rc_read_holdings(d3), rp(d4), rp(d3), X$tau, cur = cur, prev = prev))
}

## ── P2R05 범용 신규분(기록 · 판정 아님) ──────────────────────────────────────────────────
RC_P2_LIQ_TERCILES <- c("low", "mid", "high")
RC_P2_LIQ_RECON_TOL <- 1e-10   # 재구성 대조 여유 = 진단 패킷 벤치 항등식 문턱 재사용(diagnosis_packet.R .dp_exposure 'gap > 1e-10' · 결정 수치 아님)
RC_P2_BOUNDARY_EPS <- 1e-9     # 위기 유형 '경계' = |rho_W − 문턱| < eps(부동소수 여유 · 결정 수치 아님)
rc_md5_or_na <- function(f) if (length(f) == 1L && !is.na(f) && file.exists(f)) unname(as.character(tools::md5sum(f))) else NA_character_   # 출처: P2R05 L775(p5_md5)
## 설계 입력 핀(design_inputs 아래 어디든 {path|file, md5}) — 출처: P2R05 L809-820(p5_find_pin)
rc_find_pin <- function(x, rel) {
  hits <- character(0)
  walk <- function(v) {
    if (!is.list(v)) return(invisible())
    p <- v[["path"]] %||% v[["file"]]; m <- v[["md5"]]
    if (is.character(p) && length(p) == 1L && is.character(m) && length(m) == 1L && endsWith(tolower(gsub("\\\\", "/", p)), tolower(rel))) hits <<- c(hits, m)
    for (z in v) walk(z)
    invisible()
  }
  walk(x); unique(hits)
}
## 판정 계산이 된 칸(시드 띠 · 진단 읽기 입력) — P2R05 .p5_readable(rules_computed) + P2R04 판 칸(tested ∧ rules)
.rc_p2_readable <- function(x) isTRUE(x[["rules_computed"]]) || (isTRUE(x[["tested"]]) && !is.null(x[["rules"]]))
## Dimson β(Dimson 1979 JFE 7(2)) — 출처: P2R05 L1488-1501(p5_dimson_beta · p5_dimson_from)
rc_p2_dimson_beta <- function(r, m) {
  r <- suppressWarnings(as.numeric(r)); m <- suppressWarnings(as.numeric(m)); n <- length(r)
  if (n != length(m) || n < 10L) return(list(beta = NA_real_, n = n))
  X <- cbind(1, c(NA, m[-n]), m, c(m[-1L], NA))
  ok <- stats::complete.cases(X) & is.finite(r)
  if (sum(ok) < 10L) return(list(beta = NA_real_, n = sum(ok)))
  b <- stats::coef(stats::lm.fit(X[ok, , drop = FALSE], r[ok]))
  list(beta = unname(sum(b[2:4])), coef = list(lag = unname(b[2]), same = unname(b[3]), lead = unname(b[4])), n = sum(ok))
}
rc_p2_dimson_from <- function(E, dir, tau) {
  rd <- .dp_read(E, dir)
  D <- merge(rd$pr[date <= as.Date(tau), .(date, r = as.numeric(ret_net))], rd$br[date <= as.Date(tau), .(date, m = as.numeric(benchmark_ret))], by = "date")[order(date)]
  rc_p2_dimson_beta(D$r, D$m)
}
## 판정 여유(새 문턱 없음 · 양수 = 충족) — 출처: P2R05 L1503-1516(p5_margins)
rc_p2_margins <- function(RL, tail, maj, tol) {
  pc <- function(J) { J <- as.data.table(J %||% data.table()); if (!nrow(J) || !all(c("k", "m", "r") %in% names(J))) return(data.table()) else J[, .(crisis = k, margin = (r - tol) - m)] }
  sh <- function(x) suppressWarnings(as.numeric(x %||% NA))[1] - as.numeric(maj)
  dc <- RL$selection$decomposition$per_crisis
  list(rule = "여유 = 값 − 문턱(양수 = 충족 · 새 문턱 없음 · 코드는 '경계'를 판정하지 않는다)",
       beta_deep = list(per_crisis = pc(RL$beta_deep$per_crisis), share_minus_majority = sh(RL$beta_deep$share)),
       fast = list(per_crisis = pc(RL$fast$per_crisis), share_minus_majority = sh(RL$fast$share)),
       selection_decomp = list(per_crisis = if (length(dc) && nrow(as.data.table(dc))) as.data.table(dc)[, .(crisis = peak_date, margin = sv - sr)] else data.table(),
                               share_minus_majority = sh(RL$selection$decomposition$share)),
       beta_ratio = list(margin = -suppressWarnings(as.numeric(RL$beta_asym$delta %||% NA))[1], delta = RL$beta_asym$delta %||% NA_real_),
       tail = list(margin = tail$margin %||% NA_real_, t = tail$t %||% NA_real_, t_min = tail$t_min %||% NA_real_))
}
## 위기 유형 분류 — 출처: P2R05 L1552-1574(p5_load_crisis_types) · rel = 분류 파일(저장소 상대) · 문턱 = rule 의 'peak >= <날짜>' 위기 rho_W 중앙값(파일 값으로 재계산)
rc_p2_load_crisis_types <- function(root, pre, rel, eps = RC_P2_BOUNDARY_EPS) {
  p <- file.path(root, rel); pin <- rc_find_pin(pre[["design_inputs"]], rel)
  if (!file.exists(p)) return(list(status = "unclassified", why = "분류 파일 없음 — 미분류(실패 아님)", path = rel, pins = pin))
  md5 <- rc_md5_or_na(p)
  tag <- if (!length(pin)) "분류 핀 없음(사전등록 design_inputs)" else if (length(pin) > 1L) "분류 핀 여럿(사전등록 design_inputs)" else if (!identical(pin, md5)) "분류 판본 다름" else NA_character_
  J <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(J) || !length(J$crises)) return(list(status = "unclassified", why = "분류 파일 판독 실패 — 미분류", path = rel, md5 = md5, pin_tag = tag))
  C <- rbindlist(lapply(J$crises, function(z) data.table(k = as.character(z$crisis %||% NA), type = as.character(z$type %||% NA), rho_W = suppressWarnings(as.numeric(z$rho_W %||% NA)),
                                                         window = as.character(z$window %||% NA))), fill = TRUE)
  C[!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{4}-[0-9]{2}-[0-9]{2}$", k) | !(type %in% c("systemic", "dispersed")), type := "unclassified"]
  rule <- as.character(J$rule %||% "")
  fm <- regmatches(rule, regexpr("peak >= [0-9]{4}-[0-9]{2}-[0-9]{2}", rule)); from <- if (length(fm)) as.Date(sub("peak >= ", "", fm)) else as.Date(NA)
  sv <- regmatches(rule, regexpr("= [0-9]+\\.[0-9]+", rule)); stated <- if (length(sv)) as.numeric(sub("= ", "", sv)) else NA_real_
  C[, peak := suppressWarnings(as.Date(substr(k, 1, 10), format = "%Y-%m-%d"))]
  th <- if (!is.na(from)) stats::median(C[!is.na(peak) & peak >= from & is.finite(rho_W), rho_W]) else NA_real_
  C[, boundary := is.finite(th) & is.finite(rho_W) & abs(rho_W - th) < eps]
  dig <- if (length(sv)) nchar(sub("^= [0-9]+\\.", "", sv)) else NA_integer_
  list(status = "ok", path = rel, md5 = md5, pins = pin, pin_tag = tag, rule = rule, threshold = th, threshold_from = if (is.na(from)) NA_character_ else format(from),
       threshold_stated = stated, threshold_stated_matches = if (is.finite(stated) && is.finite(th) && !is.na(dig)) isTRUE(round(th, dig) == stated) else NA,
       boundary_status = if (is.finite(th)) "ok" else "unmeasured(문턱 재계산 불가 — rule 에 'peak >= <날짜>' 없음)", boundary_eps = eps,
       falsification = J$falsification %||% NULL, classes = C[, .(k, type, boundary, rho_W)])
}
## 시작 시점 분류 기록 — 출처: P2R05 L1575-1590(p5_load_onset)
rc_p2_load_onset <- function(root, pre, rel) {
  p <- file.path(root, rel); pin <- rc_find_pin(pre[["design_inputs"]], rel)
  if (!file.exists(p)) return(list(status = "unclassified", why = "시작 시점 분류 파일 없음", path = rel, pins = pin))
  J <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(J) || !length(J$table)) return(list(status = "unclassified", why = "시작 시점 분류 판독 실패", path = rel))
  C <- rbindlist(lapply(J$table, function(z) data.table(k = sub(" → ", " ", as.character(z$crisis %||% NA), fixed = TRUE),
                                                       from_top = if (is.null(z$from_top)) NA else as.logical(z$from_top), window = as.character(z$window %||% NA))), fill = TRUE)
  C <- C[window %in% "판정 창" & !is.na(from_top)]
  vft <- sub(" → ", " ", as.character(unlist(J$visible_from_top %||% list())), fixed = TRUE)
  md5 <- rc_md5_or_na(p)
  list(status = "ok", path = rel, md5 = md5, pins = pin, pin_tag = if (!length(pin)) "분류 핀 없음(사전등록 design_inputs)" else if (!identical(pin[1], md5) || length(pin) > 1L) "분류 판본 다름" else NA_character_,
       visible_from_top_matches_table = setequal(vft, C[from_top == TRUE, k]),
       classes = C[, .(k, type = ifelse(from_top, "from_top", "not_from_top"), boundary = FALSE)])
}
## 칸 1개의 위기 유형별 β 짝 승패 — 출처: P2R05 L1591-1613(p5_crisis_type_record)
rc_p2_crisis_type_record <- function(pc, CL, deep_keys = character(0), tol = 0, decomp = NULL, beta_delta = NA_real_) {
  if (is.null(CL) || !identical(CL$status, "ok")) return(list(status = "unclassified", why = CL$why %||% "미분류", beta_ratio_delta = beta_delta))
  P <- as.data.table(pc %||% data.table())
  if (!nrow(P) || !all(c("k", "m", "r") %in% names(P))) return(list(status = "unmeasured", why = "β 짝 위기 표 없음(β 사본 미측정)", beta_ratio_delta = beta_delta))
  P <- P[is.finite(m) & is.finite(r)][, win := m < r - tol]
  X <- merge(P, CL$classes, by = "k", all.x = TRUE)
  X[is.na(type), type := "unclassified"][is.na(boundary), boundary := FALSE]
  X[, is_deep := k %in% deep_keys]
  DC <- as.data.table(decomp %||% data.table())
  X[, selection_better := if (nrow(DC) && all(c("peak_date", "sv", "sr") %in% names(DC))) { mi <- match(substr(k, 1, 10), as.character(DC$peak_date)); ifelse(is.na(mi), NA, DC$sv[mi] - DC$sr[mi] > 0) } else NA]
  agg <- function(D) if (!nrow(D)) data.table(type = character(0), n = integer(0), n_win = integer(0), wins = character(0), n_selection_better = integer(0)) else
    D[, .(n = .N, n_win = sum(win), wins = paste(k[win], collapse = " | "), n_selection_better = sum(selection_better %in% TRUE)), by = type][order(type)]
  S <- copy(X)[boundary %in% TRUE, type := "boundary"]
  list(status = "ok", tag = CL$pin_tag %||% NA_character_, tol = tol, beta_ratio_delta = beta_delta,
       as_written = agg(X), boundary_separate = agg(S), deep_as_written = agg(X[is_deep == TRUE]), deep_boundary_separate = agg(S[is_deep == TRUE]),
       per_crisis = X[, .(crisis = k, type, boundary, deep = is_deep, dd_capture = m, dd_capture_beta_copy = r, beats_beta_copy = win, selection_better)])
}
## 유동성 3분위 위기 손익 귀속 — 출처: P2R05 L1366-1380(.p5_bins · p5_liq_from) · L1666-1785(p5_ret_state · p5_liq_tercile_core/cell · p5_liq_improvement ·
##   p5_liq_table · p5_liq_attr_round · p5_liq_attr_for) · 칸 목록 · 3분위 이름 · 재구성 여유 = 인자
.rc_p2_bins <- function(x, univ, k) {
  u <- suppressWarnings(as.numeric(univ)); u <- u[is.finite(u)]; x <- suppressWarnings(as.numeric(x)); k <- as.integer(k)
  if (is.na(k) || k < 2L || length(u) < k) return(rep(NA_integer_, length(x)))
  bp <- stats::quantile(u, probs = seq_len(k - 1L) / k, names = FALSE, type = 7)
  ifelse(is.finite(x), findInterval(x, bp) + 1L, NA_integer_)
}
rc_p2_liq_from <- function(RAW) {
  L <- RAW[, .(Date, Ticker = as.character(Ticker), Close = as.numeric(Close), Vol = as.numeric(Vol))]
  setorder(L, Ticker, Date)
  L[, adv20_l1 := shift(frollmean(Close * Vol, 20L, align = "right"), 1L), by = Ticker]
  L <- L[, .(Date, Ticker, Vol, adv20_l1)]
  setkey(L, Date, Ticker)
  L
}
rc_p2_ret_state <- function(RAW, tickers, from, cal = NULL) {
  if (is.null(cal)) cal <- sort(unique(as.Date(RAW$Date)))
  cal <- cal[cal >= as.Date(from)]
  tk <- sort(unique(as.character(tickers)))
  P <- RAW[Date >= as.Date(from) & Ticker %in% tk, .(Date, Ticker, Ret)]
  R <- matrix(NA_real_, length(cal), length(tk))
  pos <- cbind(match(P$Date, cal), match(P$Ticker, tk)); okp <- !is.na(pos[, 1]) & !is.na(pos[, 2])
  R[pos[okp, , drop = FALSE]] <- as.numeric(P$Ret[okp]); R[!is.finite(R)] <- NA_real_
  R0 <- R; R0[is.na(R0)] <- 0
  list(cal = cal, tickers = tk, R = R, R0 = R0)
}
rc_p2_liq_tercile_core <- function(C, retg, adv_held, adv_univ, tol = RC_P2_LIQ_RECON_TOL, terciles = RC_P2_LIQ_TERCILES) {
  C <- as.data.table(C); retg <- as.data.table(retg)
  if (!nrow(C)) return(list(status = "unmeasured", why = "구간 보유 기여 없음"))
  k <- length(terciles); u <- suppressWarnings(as.numeric(adv_univ)); u <- u[is.finite(u)]
  TT <- C[, .(contrib = sum(contrib), days_held = .N), by = Ticker]
  TT[, adv20_l1 := unname(adv_held[Ticker])]
  b <- .rc_p2_bins(TT$adv20_l1, u, k)
  TT[, tercile := terciles[b]][is.na(tercile), tercile := "unknown"]
  BYT <- TT[, .(contrib = sum(contrib), n_names = .N), by = tercile][order(match(tercile, c(terciles, "unknown")))]
  total <- sum(C$contrib); hr <- nrow(retg) > 0L && "ret_gross" %in% names(retg)
  cs <- if (hr) sum(retg$ret_gross) else NA_real_; gap <- cs - total
  list(status = "ok", total = total, sum_terciles = sum(BYT$contrib), by_tercile = BYT, names = TT[order(tercile, Ticker)],
       contract_sum = cs, recon_gap = gap, recon_ok = is.finite(gap) && abs(gap) < tol, recon_tol = tol,
       contract_cum = if (hr) prod(1 + retg$ret_gross) - 1 else NA_real_, n_days = uniqueN(C$date), n_contract_days = nrow(retg), n_names = nrow(TT),
       n_universe = length(u), breaks = if (length(u) >= k) stats::quantile(u, probs = seq_len(k - 1L) / k, names = FALSE, type = 7) else NA_real_)
}
rc_p2_liq_tercile_cell <- function(E, dir, CRK, RAW, liq, hyg_of, tau, cal = NULL) {
  src <- E$ta_resolve_artifact(dir)
  H <- E$ta_read_holdings(src$dir)[Exec <= as.Date(tau) & is.finite(Weight) & Weight != 0]
  if (!nrow(H)) return(list(status = "unmeasured", why = "보는 창 보유 없음"))
  st <- rc_p2_ret_state(RAW, H$Ticker, min(H$Exec), cal)
  WL <- E$.ta_daily_weights(H, st, src$exec_price)
  WL[, `:=`(date = st$cal[di], Ticker = st$tickers[ti], r = st$R0[cbind(di, ti)])][, contrib := w * r]
  PR <- fread(file.path(src$dir, "03_period_returns.csv")); PR[, date := as.Date(date)]
  per <- setNames(lapply(seq_len(nrow(CRK)), function(i) tryCatch({
    p0 <- as.Date(CRK$peak[i]); t0 <- as.Date(CRK$trough[i])
    C <- WL[date > p0 & date <= t0, .(date, Ticker, contrib)]
    rg <- if ("ret_gross" %in% names(PR)) PR[date > p0 & date <= t0 & date <= as.Date(tau), .(date, ret_gross)] else data.table()
    L0 <- liq[Date == p0]; hy <- hyg_of(p0)
    c(list(peak = format(p0), trough = format(t0), asof = format(p0), deep = isTRUE(CRK$deep[i]), fast = isTRUE(CRK$fast[i])),
      rc_p2_liq_tercile_core(C, rg, setNames(L0$adv20_l1, as.character(L0$Ticker)), L0[Ticker %in% hy & is.finite(adv20_l1) & adv20_l1 > 0]$adv20_l1))
  }, error = function(e) list(status = "unmeasured", why = conditionMessage(e)))), CRK$k)
  list(status = "ok", exec_price = src$exec_price, basis = src$basis, per_crisis = per)
}
rc_p2_liq_improvement <- function(rv, rr, maj) {
  ks <- intersect(names(rv %||% list()), names(rr %||% list()))
  lo <- function(x) { z <- as.data.table(x$by_tercile %||% data.table()); z <- if (nrow(z)) z[tercile == "low"]$contrib else numeric(0); if (length(z)) z[1] else 0 }
  P <- rbindlist(lapply(ks, function(k) { a <- rv[[k]]; b <- rr[[k]]
    fl <- list(deep = isTRUE(a$deep %||% b$deep), fast = isTRUE(a$fast %||% b$fast))
    if (!identical(a$status, "ok") || !identical(b$status, "ok"))
      return(data.table(crisis = k, deep = fl$deep, fast = fl$fast, total = NA_real_, total_rx0 = NA_real_, improvement = NA_real_, low_improvement = NA_real_,
                        low_share = NA_real_, low_attributed = NA, status = "unmeasured", why = paste(c(a$why, b$why), collapse = " · ")))
    rec <- isTRUE(a$recon_ok) && isTRUE(b$recon_ok)
    imp <- a$total - b$total; li <- lo(a) - lo(b); sh <- if (rec && is.finite(imp) && imp > 0) li / imp else NA_real_
    data.table(crisis = k, deep = fl$deep, fast = fl$fast, total = a$total, total_rx0 = b$total, improvement = imp, low_improvement = li, low_share = sh,
               low_attributed = if (is.finite(sh)) sh > as.numeric(maj) else NA, status = if (rec) "ok" else "recon_mismatch", why = NA_character_) }), fill = TRUE)
  if (!nrow(P)) return(list(status = "unmeasured", tags = "유동성 귀속 미측정", per_crisis = data.table(), why = "짝 위기 없음(칸 또는 RX0 귀속 없음)"))
  ni <- sum(P$status == "ok" & is.finite(P$improvement) & P$improvement > 0); nl <- sum(P$low_attributed %in% TRUE)
  list(status = "ok", per_crisis = P, n_crisis = nrow(P), n_measured = sum(P$status == "ok"), n_improvement = ni, n_low_attributed = nl, majority_share = as.numeric(maj),
       tags = c(if (any(P$status != "ok")) sprintf("유동성 귀속 미측정(일부 위기 %d/%d — 재구성 대조 불일치 · 결손)", sum(P$status != "ok"), nrow(P)),
                if (nl > 0L) sprintf("저유동 귀속(위기 개선의 과반이 저유동 3분위 기여 — %d/%d 개선 위기)", nl, ni)))
}
rc_p2_liq_table <- function(per, eng) rbindlist(lapply(names(per), function(cp) { z <- per[[cp]]
  if (!identical(z$status, "ok")) return(data.table(engine = eng, device = cp, cell = z$cell %||% NA_character_, crisis = NA_character_, status = z$status %||% "unmeasured", why = z$why %||% NA_character_))
  rbindlist(lapply(names(z$per_crisis), function(k) { a <- z$per_crisis[[k]]
    if (!identical(a$status, "ok")) return(data.table(engine = eng, device = cp, cell = z$cell %||% NA_character_, crisis = k, status = a$status %||% "unmeasured", why = a$why %||% NA_character_))
    B <- as.data.table(a$by_tercile)
    g <- function(t) { v <- B[tercile == t]$contrib; if (length(v)) v[1] else 0 }; n <- function(t) { v <- B[tercile == t]$n_names; if (length(v)) as.integer(v[1]) else 0L }
    data.table(engine = eng, device = cp, cell = z$cell %||% NA_character_, crisis = k, deep = a$deep, fast = a$fast, status = "ok", total = a$total,
               low = g("low"), mid = g("mid"), high = g("high"), unknown = g("unknown"), n_low = n("low"), n_mid = n("mid"), n_high = n("high"), n_unknown = n("unknown"),
               contract_sum = a$contract_sum, recon_gap = a$recon_gap, recon_ok = a$recon_ok, contract_cum = a$contract_cum)
  }), fill = TRUE) }), fill = TRUE)
rc_p2_liq_attr_round <- function(X, EVS, cells, engines, RAW, FS, tau, liq_cells) {
  E <- X$env$E
  if (!"Ret" %in% names(RAW)) stop("RAWDATA Ret 열 없음 — 일수익 재구성 불가")
  if (is.null(X$env$liq)) stop("유동성 패널 없음(보는 창 RAWDATA 미적재)")
  RW <- rc_raw_get(X)
  if (!"HYG" %in% names(RW)) stop("위생 멤버십(HYG) 없음 — 유니버스 3분위를 정할 수 없다")
  hc <- new.env(); di <- as.integer(RW$Date)
  hyg_of <- function(d) { k <- as.character(as.integer(as.Date(d))); if (is.null(hc[[k]])) hc[[k]] <- RW$Ticker[di == as.integer(k) & RW$HYG %in% TRUE]; hc[[k]] }
  cal <- sort(unique(as.Date(RAW$Date)))
  cof <- function(eng, comp) { z <- Filter(function(c0) identical(c0$engine, eng) && identical(c0$component, comp), cells); if (length(z)) z[[1]] else NULL }
  setNames(lapply(engines, function(eng) tryCatch({
    cr <- cof(eng, "RX0"); if (is.null(cr)) stop("RX0 칸 없음")
    ev0 <- EVS[[cr$code]]; if (!identical(ev0$status, "evaluated")) stop(sprintf("RX0 칸 평가 상태 %s", ev0$status %||% "NA"))
    pk <- rc_pk_read(X, cr$code); if (is.null(pk)) stop("RX0 보는 창 패킷 없음")
    crr <- pk$behavior$crises %||% list(); CR <- .rc_rows_dt(crr); if (!nrow(CR)) stop("위기 없음")
    CR[, k := .rc_key(CR)]
    deep <- rc_deep_crisis_keys(crr, crr)
    fk <- rc_p2_fast_crash_keys(fread(file.path(E$ta_resolve_artifact(ev0$artifacts)$dir, "05_benchmark_returns.csv")), crr, as.integer(FS[["fast_window_days"]]), as.numeric(FS[["fast_drop"]]))
    CRK <- CR[k %in% union(deep, fk$keys), .(k, peak = as.Date(as.character(peak_date)), trough = as.Date(as.character(trough_date)), deep = k %in% deep, fast = k %in% fk$keys)]
    CRK <- CRK[!is.na(peak) & !is.na(trough) & trough <= as.Date(tau)]
    if (!nrow(CRK)) stop("보는 창 깊은 위기 · 빠른 급락 없음")
    comps <- intersect(liq_cells, vapply(Filter(function(c0) identical(c0$engine, eng), cells), function(c0) as.character(c0$component), character(1)))
    per <- setNames(lapply(comps, function(cp) { cc <- cof(eng, cp); tryCatch({
      ev <- EVS[[cc$code]]
      if (!identical(ev$status, "evaluated")) stop(sprintf("칸 평가 상태 %s", ev$status %||% "NA"))
      c(list(cell = cc$code), rc_p2_liq_tercile_cell(E, ev$artifacts, CRK, RAW, X$env$liq, hyg_of, tau, cal))
    }, error = function(e) list(status = "unmeasured", cell = cc$code, why = conditionMessage(e))) }), comps)
    rest <- setdiff(comps, "RX0")
    imp <- setNames(lapply(rest, function(cp) rc_p2_liq_improvement(per[[cp]]$per_crisis, per[["RX0"]]$per_crisis, FS[["majority_share"]])), rest)
    list(status = "ok", crises = CRK[, .(crisis = k, peak = format(peak), trough = format(trough), deep, fast)], per_cell = per, improvement = imp, table = rc_p2_liq_table(per, eng),
         rule = "유동성 구간별 위기 손익 귀속 — 고점일 t−1 20일 평균 거래대금 유니버스 3분위 · 구간 손익 = 계약 일별 시작 비중 × 일수익의 (고점, 저점] 산술합 · 03 ret_gross 구간 합과 대조 단정 · 기록(판정 아님)")
  }, error = function(e) list(status = "unmeasured", why = conditionMessage(e), tags = "유동성 귀속 미측정"))), engines)
}
rc_p2_liq_attr_for <- function(LQA, eng, dev) {
  L <- LQA[[eng]]
  if (!is.list(L) || !identical(L$status, "ok")) return(list(status = "unmeasured", tags = "유동성 귀속 미측정", why = L$why %||% "구성 귀속 없음"))
  L$improvement[[dev]] %||% list(status = "unmeasured", tags = "유동성 귀속 미측정", why = "칸 귀속 없음(나란히 칸 밖 또는 RX0)")
}
## 시드 띠(재시드 칸 RX0S 대 RX0) · 시드 미결 꼬리표 · R7 시드 꼬리표 수 — 출처: P2R05 L1894-1930(p5_seed_band · p5_seed_tags · p5_seed_tag_counts)
rc_p2_seed_band <- function(rs) {
  if (!.rc_p2_readable(rs)) return(list(status = "unmeasured", tag = "시드 띠 미측정", why = rs$why %||% "재시드 칸 없음"))
  P <- as.data.table(rs$rules$crisis$per_crisis %||% data.table())
  if (!nrow(P) || !all(c("k", "m", "r") %in% names(P))) return(list(status = "unmeasured", tag = "시드 띠 미측정", why = "재시드 위기 표 없음"))
  P <- P[is.finite(m) & is.finite(r), .(k, band = abs(m - r))]
  sb <- abs(suppressWarnings(as.numeric(rs$non_inferiority$S %||% NA) - as.numeric(rs$non_inferiority$S_rx0 %||% NA))[1])
  list(status = "ok", tag = NA_character_, cell = rs$cell %||% NA_character_, per_crisis = P, S_band = sb,
       note = "시드 띠 = 같은 구성 재시드 1쌍(RX0S 대 RX0) — 모델 시드 잡음의 대리")
}
rc_p2_seed_tags <- function(v, band) {
  if (!.rc_p2_readable(v)) return(list(status = "unmeasured", why = "변형 칸 판정 계산 없음", tags = character(0)))
  if (!identical(band$status, "ok")) return(list(status = "unmeasured", why = band$why %||% NA_character_, tags = "시드 띠 미측정"))
  one <- function(J) { J <- as.data.table(J %||% data.table())
    if (!nrow(J) || !all(c("k", "m", "r") %in% names(J))) return(data.table(crisis = character(0), gap = numeric(0), band = numeric(0), undetermined = logical(0)))
    X <- merge(J[, .(k, gap = abs(m - r))], band$per_crisis, by = "k", all.x = TRUE)
    X[, .(crisis = k, gap, band, undetermined = ifelse(is.finite(band), gap < band, NA))] }
  D <- one(v$rules$beta_deep$per_crisis); F <- one(v$rules$fast$per_crisis)
  dS <- suppressWarnings(as.numeric(v$non_inferiority$S %||% NA) - as.numeric(v$non_inferiority$S_rx0 %||% NA))[1]
  sU <- if (is.finite(dS) && is.finite(band$S_band)) abs(dS) < band$S_band else NA
  nd <- sum(D$undetermined %in% TRUE); nf <- sum(F$undetermined %in% TRUE)
  list(status = "ok", deep = D, fast = F, n_deep = nrow(D), n_deep_undetermined = nd, n_fast = nrow(F), n_fast_undetermined = nf,
       n_band_missing = sum(is.na(D$undetermined)) + sum(is.na(F$undetermined)), S = list(dS = dS, band = band$S_band, undetermined = sU),
       tags = c(if (nd) sprintf("시드 미결 %d/%d 깊은 위기(③)", nd, nrow(D)), if (nf) sprintf("시드 미결 %d/%d 빠른 급락(④)", nf, nrow(F)), if (isTRUE(sU)) "S 시드 미결",
                if (anyNA(c(D$undetermined, F$undetermined)) || is.na(sU)) "시드 띠 미측정(일부 위기 · S)"))
}
rc_p2_seed_tag_counts <- function(OUT, devs) {
  xs <- Filter(function(x) isTRUE(x$device %in% devs), OUT)
  st <- lapply(xs, function(x) x$seed_tags %||% list(status = "unmeasured"))
  ok <- vapply(st, function(s) identical(s$status, "ok"), logical(1))
  list(n_cells = length(xs), n_cells_with_band = sum(ok), n_deep_undetermined = sum(vapply(st[ok], function(s) as.integer(s$n_deep_undetermined %||% 0L), integer(1))),
       n_fast_undetermined = sum(vapply(st[ok], function(s) as.integer(s$n_fast_undetermined %||% 0L), integer(1))),
       n_S_undetermined = sum(vapply(st[ok], function(s) isTRUE(s$S$undetermined), logical(1))),
       tag = if (length(xs) && !all(ok)) "시드 띠 미측정(일부 칸)" else NA_character_)
}

## ── P2 판정 1칸 단계(출처: P2R04 p2_eval_pair L1064-1278 — 같은 순서 · 같은 필드) ─────────────────────────
## 초기 필드 · 미시험(P2R04 L1038-1042 · L1068)
rc_p2_init <- function(ctx, opts) list(engine = ctx$engine, device = ctx$unit, role = opts[["role"]] %||% "judge", cell = ctx$cm$code, rx0 = ctx$cr$code,
                                       status = ctx$em$status %||% NA, status_rx0 = ctx$er$status %||% NA)
rc_p2_untested_fn <- function(verdict_names) function(out, why) {
  out$tested <- FALSE; out$pass <- FALSE; out$verdict <- "untested"; out$verdict_name <- verdict_names[["untested"]]; out$why <- why
  out$tbl <- data.table(engine = out$engine, device = out$device, tested = FALSE, pass = FALSE, excluded = FALSE, verdict = "untested")
  out
}
## 사양 읽기(P2R04 L1071-1073)
rc_p2_st_spec <- function(S) {
  sp <- tryCatch(list(v = fromJSON(file.path(S$X$root, .rc_cell_spec(S$ctx$cm)), simplifyVector = FALSE), r = fromJSON(file.path(S$X$root, .rc_cell_spec(S$ctx$cr)), simplifyVector = FALSE)),
                 error = function(e) list(error = conditionMessage(e)))
  if (!is.null(sp$error)) return(paste("사양 읽기 실패:", sp$error))
  S$sp <- sp
  NULL
}
## 장치(진단) 항목(P2R04 L1074-1076)
rc_p2_st_device <- function(S) {
  cfg <- S$T$cfg; dev <- S$ctx$unit
  dvt <- if (S$diag) rc_p2_diag_device(dev, S$sp$v[["factors"]], cfg[["diagnostics"]], cfg[["devices"]]) else cfg[["devices"]][[dev]]
  if (is.null(dvt)) return(if (S$diag) paste("진단 칸 장치 해석 실패(진단 표 · 사양 끝 항목):", dev) else paste("장치 표에 없는 부품:", dev))
  S$dvt <- dvt
  S$out$device_factor <- dvt[intersect(names(dvt), c("kind", "id", "name"))]
  NULL
}
## ⑩ 구성 증거(팩터 틸트 장치 — 사양 꼬리 · 셀 로그 · 혼합 가중) — P2R04 L1077-1089 · ★ opts 는 [[ ]](log ↔ log_rx0 · expect_cell ↔ expect_cell_rx0 부분 일치)
rc_p2_st_construction_factor <- function(S) {
  X <- S$X; cm <- S$ctx$cm; cr <- S$ctx$cr; opts <- S$opts
  S$Lv <- rc_read_lines(opts[["log"]] %||% file.path(X$res, paste0(cm$code, ".log"))); S$Lr <- rc_read_lines(opts[["log_rx0"]] %||% file.path(X$res, paste0(cr$code, ".log")))
  lv <- rc_p2_parse_cell_log(S$Lv); lr <- rc_p2_parse_cell_log(S$Lr); S$lv <- lv
  cs <- rc_p2_construction_check(lv, lr, S$dvt, S$sp$v[["factors"]], S$sp$r[["factors"]], opts[["expect_cell"]] %||% cm$code, opts[["expect_cell_rx0"]] %||% cr$code)
  cs$blend <- rc_p2_blend_weight(S$sp$v[["base_weight"]], length(cs$spec_factors), cs$device_count)
  if (S$diag) { ew <- suppressWarnings(as.numeric(opts[["expect_weight"]] %||% NA))[1]; dw <- cs$blend$device_weight
                cs$blend$expected <- ew; cs$blend$ok <- is.finite(ew) && is.finite(dw) && abs(dw - ew) < 1e-9 }   # 1e-9 = 부동소수 여유(결정 수치 아님)
  S$cs <- cs
  S$out$construction <- cs
  S$out$cell_log_full_period <- list(variant = lv[intersect(names(lv), c("months", "rows"))], rx0 = lr[intersect(names(lr), c("months", "rows"))])
  if (!isTRUE(cs$ok)) return(paste("구성 증거 불일치(⑩) —", cs$why))
  if (S$diag && !isTRUE(cs$blend$ok))
    return(sprintf("진단 칸 혼합 가중 불일치 — 장치 가중 %s(기대 %s · 진단 표 %s)", format(cs$blend$device_weight), format(cs$blend$expected), S$ctx$unit))
  NULL
}
## ⑩ 처치 전달(보유 대조) — P2R04 L1114-1120(판정 칸: 무처치 = 미시험 · 진단 칸: 같음도 그 진단의 답)
rc_p2_st_treatment <- function(S) {
  ov <- tryCatch(rc_holdings_overlap(rc_read_holdings(S$am), rc_read_holdings(S$ar), S$X$tau), error = function(e) list(status = paste("오류:", conditionMessage(e))))
  S$ov <- ov
  S$out$holdings_overlap <- ov[setdiff(names(ov), "per_date")]
  S$out$holdings_overlap_per_date <- ov$per_date
  S$out$treatment_delivered <- rc_treatment_delivered(ov)
  if (!S$out$treatment_delivered && (!S$diag || !identical(ov$status, "ok")))
    return(sprintf("무처치(⑩) — 보는 창 보유가 RX0 와 다른 보유일 %s/%s(보유 대조 %s)", format(ov$n_differ %||% NA), format(ov$n_dates %||% NA), ov$status %||% "NA"))
  NULL
}
## 팩터 방향 경로 기록 — P2R04 L1129-1131
rc_p2_st_direction <- function(S) {
  S$out$construction$factor_direction <- tryCatch(rc_p2_direction_record(rc_p2_parse_direction_lines(S$Lv), length(S$lv$factors), S$PM$window[[1]] %||% NA, S$X$tau),
                                                  error = function(e) list(status = paste("오류:", conditionMessage(e))))
  NULL
}
## ③ · ④ β 짝 · 빠른 급락 · 느린 약세 — P2R04 L1143-1167
rc_p2_st_beta <- function(S) {
  X <- S$X; FS <- X$fs; cfg <- S$T$cfg; g <- rc_getf; tol <- S$tol; MAJ <- S$MAJ; cm <- S$ctx$cm; cr <- S$ctx$cr
  fk <- tryCatch(rc_p2_fast_crash_keys(fread(file.path(S$ar, "05_benchmark_returns.csv")), S$crr, as.integer(FS[["fast_window_days"]]), as.numeric(FS[["fast_drop"]])),
                 error = function(e) if (isTRUE(cfg[["fast_err_no_month_end"]])) list(keys = character(0), table = data.table(), unclassified = NA_character_, no_month_end = character(0), err = conditionMessage(e))
                                     else list(keys = character(0), table = data.table(), unclassified = NA_character_, err = conditionMessage(e)))
  bm <- g(S$PM, "behavior.stats.beta"); br0 <- g(S$PRX, "behavior.stats.beta")
  bp <- cfg[["beta_plan"]](bm, br0, S$opts[["force_k"]]); k <- bp$k
  PB <- NULL; berr <- NULL
  if (identical(bp$mode, "unmeasured")) berr <- cfg[["beta_unmeasured_why"]](k)
  else if (identical(bp$mode, "rx0")) PB <- S$PRX
  else PB <- tryCatch({
    base <- file.path(X$out, cm$code, S$W$sub); bdir <- file.path(base, "rx0_beta_scaled")
    if (isTRUE(cfg[["mark_full"]])) rc_mark_full(base, RC_FULL_MARK_PARENT)
    rc_beta_scaled_copy(S$ar, bdir, k, mark = isTRUE(cfg[["mark_full"]]), minimal = isTRUE(X[["minimal_copy"]]), errtag = cfg[["beta_errtag"]] %||% "p2_beta")
    rc_pk_build(X, .rc_cell_spec(cr), bdir, file.path(base, "visible_rx0_beta"))
  }, error = function(e) { berr <<- conditionMessage(e); NULL })
  cbp <- if (!is.null(PB)) PB$behavior$crises %||% list() else list()
  emp <- list(n_pair = 0L, share = NA_real_)
  b3 <- if (!is.null(PB)) rc_crisis_majority(S$crm, cbp, tol, "dd_capture", subset = S$deep) else emp
  b4 <- if (!is.null(PB)) rc_crisis_majority(S$crm, cbp, tol, "dd_capture", subset = fk$keys) else emp
  r3 <- if (!is.null(PB) && b3$n_pair >= 2L) rc_maj(b3$share, MAJ) else NA
  r4 <- if (!is.null(PB) && b4$n_pair >= 2L) rc_maj(b4$share, MAJ) else NA
  b4x <- if (!is.null(PB)) rc_crisis_majority(S$crm, cbp, tol, "dd_capture", subset = setdiff(fk$keys, fk$no_month_end)) else emp
  slow_keys <- if (nrow(fk$table)) fk$table[fast %in% FALSE, k] else character(0)
  bsl <- if (!is.null(PB)) rc_crisis_majority(S$crm, cbp, tol, "dd_capture", subset = slow_keys) else emp
  S$fk <- fk; S$bm <- bm; S$br0 <- br0; S$bp <- bp; S$k <- k; S$PB <- PB; S$berr <- berr; S$cbp <- cbp
  S$b3 <- b3; S$b4 <- b4; S$r3 <- r3; S$r4 <- r4; S$b4x <- b4x; S$slow_keys <- slow_keys; S$bsl <- bsl
  NULL
}
## ⑤ β 비대칭 · ⑥ 강세 · ⑦ 알파 · ⑨ 사이클 · ⑫ · ⑬ 입력 — P2R04 L1168-1192(판정 입력 NA = 미시험 · 진단 칸 무처치의 알파 0/0 은 접지 않음)
rc_p2_st_inputs <- function(S) {
  X <- S$X; FS <- X$fs; cfg <- S$T$cfg; g <- rc_getf; PM <- S$PM; PRX <- S$PRX
  bdu <- c(down = g(PM, "behavior.stats.beta_down"), up = g(PM, "behavior.stats.beta_up"))
  bdr <- c(down = g(PRX, "behavior.stats.beta_down"), up = g(PRX, "behavior.stats.beta_up"))
  r5d <- rc_p2_beta_ratio_delta(bdu[["down"]], bdu[["up"]], bdr[["down"]], bdr[["up"]])
  bs <- rc_p2_bull_segments(PM$behavior$bull_phases %||% list(), PRX$behavior$bull_phases %||% list(), as.numeric(FS[["bull_ratio"]]), 2L)
  ucm <- g(PM, "behavior.summary.bull_up_capture_median"); ucr <- g(PRX, "behavior.summary.bull_up_capture_median")
  pa <- tryCatch(rc_pair_alpha(X$env$E, S$am, S$ar, X$tau),
                 error = function(e) list(visible = list(d_alpha = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e)), test = NULL))
  aok <- rc_alpha_ok(pa$visible, as.numeric(FS[["alpha_t_floor"]]), S$ea$alpha_ann, as.numeric(FS[["alpha_margin_frac"]]))
  cyc <- rc_cycle_compound(PM$behavior$bull_phases %||% list(), S$crm, PRX$behavior$bull_phases %||% list(), S$crr)
  cmv <- g(PM, "performance.strategy.calmar"); crv <- g(PRX, "performance.strategy.calmar")
  ptm <- g(PM, "performance.strategy.port_t"); ptr <- g(PRX, "performance.strategy.port_t")
  mvb <- c(g(PM, "behavior.summary.mdd_vs_bench"), g(PRX, "behavior.summary.mdd_vs_bench"))
  cdr <- c(g(PM, "behavior.stats.cdar"), g(PRX, "behavior.stats.cdar"))
  inp <- c(b = S$maj$share, d = S$dmj$share, beta_ratio = r5d$ratio, beta_ratio_rx0 = r5d$ratio_rx0, bull_share = bs$share, uc = ucm, cycle = cyc$share,
           calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr, mdd_vs_bench = mvb, cdar = cdr)
  S$bdu <- bdu; S$bdr <- bdr; S$r5d <- r5d; S$r5 <- r5d$ok; S$r5_level <- rc_p2_beta_asym(bdu[["down"]], bdu[["up"]])
  S$bs <- bs; S$ucm <- ucm; S$ucr <- ucr; S$pa <- pa; S$aok <- aok; S$cyc <- cyc; S$cmv <- cmv; S$crv <- crv; S$ptm <- ptm; S$ptr <- ptr; S$mvb <- mvb; S$cdr <- cdr
  alpha_degenerate <- isTRUE(cfg[["alpha_degenerate"]]) && S$diag && !isTRUE(S$out$treatment_delivered) && is.na(aok)
  if (isTRUE(cfg[["alpha_degenerate"]])) S$out$alpha_degenerate <- alpha_degenerate
  if (any(!is.finite(inp)) || (is.na(aok) && !alpha_degenerate)) {
    S$out$inputs <- c(as.list(inp), list(alpha_t = pa$visible$t, engine_alpha = S$ea$alpha_ann, cycle_pairs = cyc$n_pair, bull_pairs = bs$n_pair))
    return(sprintf("판정 입력 NA(%s)", paste(c(names(inp)[!is.finite(inp)], if (is.na(aok)) "alpha"), collapse = ",")))
  }
  NULL
}
## 판정 규칙 표(RL) · ⑫ S · ⑬ 경로 · ⑭ 선택 · 알파 비열등 — P2R04 L1193-1230
rc_p2_st_judge <- function(S) {
  X <- S$X; FS <- X$fs; cfg <- S$T$cfg; g <- rc_getf; MAJ <- S$MAJ; PM <- S$PM; PRX <- S$PRX
  Sm <- rc_S(S$cmv, S$ptm, FS); Sr <- rc_S(S$crv, S$ptr, FS)
  r12 <- if (Sr > 0) Sm >= Sr - as.numeric(FS[["tie_eps"]]) else S$cmv >= S$crv
  r13 <- S$mvb[1] <= S$mvb[2] && S$cdr[1] <= S$cdr[2]
  S$deep_peaks <- vapply(strsplit(S$deep, " "), `[`, "", 1)
  s14 <- if (isTRUE(cfg[["selection"]])) rc_p2_selection_rule(rc_p2_selection_attr(PM$controls$attribution$label, FS[["mc8_label_required"]], PM$controls$status %||% NA_character_, cfg[["mc8_labels"]] %||% RC_P2_MC8_LABELS),
                                                         rc_p2_selection_decomp(PM$exposure$crises %||% list(), PRX$exposure$crises %||% list(), S$deep_peaks, MAJ)) else NULL
  maj <- S$maj; dmj <- S$dmj; kp <- isTRUE(cfg[["rl_keep_per_crisis"]])
  RL <- list(
    crisis    = c(if (kp) maj else maj[setdiff(names(maj), "per_crisis")], list(ok = rc_maj(maj$share, MAJ))),
    deep      = c(if (kp) dmj else dmj[setdiff(names(dmj), "per_crisis")], list(deep_keys = S$deep, ok = rc_maj(dmj$share, MAJ))),
    beta_deep = list(k = S$k, k_forced = S$bp$forced, comparator = S$bp$comparator, n_pair = S$b3$n_pair, share = S$b3$share,
                     status = if (!is.null(S$berr)) "unmeasured" else if (is.na(S$r3)) "unmeasured(짝 < 2)" else "ok", why = S$berr, ok = isTRUE(S$r3), per_crisis = S$b3$per_crisis),
    fast      = list(keys = S$fk$keys, table = S$fk$table, unclassified = S$fk$unclassified, n_pair = S$b4$n_pair, share = S$b4$share, classify_error = S$fk$err %||% NA_character_,
                     status = if (!is.null(S$berr)) "unmeasured" else if (is.na(S$r4)) "unmeasured(짝 < 2)" else "ok", ok = isTRUE(S$r4), per_crisis = S$b4$per_crisis,
                     record_excluding_no_month_end = list(excluded = S$fk$no_month_end, n_pair = S$b4x$n_pair, share = S$b4x$share)),
    slow      = list(keys = S$slow_keys, n_pair = S$bsl$n_pair, share = S$bsl$share, ok = if (S$bsl$n_pair >= 2L) rc_maj(S$bsl$share, MAJ) else NA, per_crisis = S$bsl$per_crisis,
                     note = cfg[["slow_note"]]),
    beta_asym = list(beta = c(variant = S$bm, rx0 = S$br0), down = S$bdu[["down"]], up = S$bdu[["up"]], rx0_down = S$bdr[["down"]], rx0_up = S$bdr[["up"]],
                     ratio = S$r5d$ratio, ratio_rx0 = S$r5d$ratio_rx0, delta = S$r5d$delta, ok = isTRUE(S$r5),
                     level_ok = S$r5_level, claim_tag = if (isTRUE(S$r5_level)) NA_character_ else "노출(β) 방어 — 비대칭 역행(하락 β ≥ 상승 β) · 방어 주장 불가(헌장 빈칸 3 · 8)"),
    bull      = c(S$bs[setdiff(names(S$bs), "per_phase")], list(uc_median = S$ucm, uc_median_rx0 = S$ucr, uc_floor = FS[["uc_floor"]], per_phase = S$bs$per_phase,
                                                                ok = rc_maj(S$bs$share, MAJ) && S$ucm >= as.numeric(FS[["uc_floor"]]))),
    cycle     = c(S$cyc[setdiff(names(S$cyc), "per_cycle")], list(per_cycle = S$cyc$per_cycle, ok = rc_maj(S$cyc$share, MAJ))),
    path      = list(mdd_vs_bench = S$mvb, cdar = S$cdr, ok = r13),
    construction = S$T$hooks[["construction_rule"]](S))
  if (!is.null(s14)) RL$selection <- c(s14, list(share_beats_size_exposure = g(PM, "controls.attribution.share_beats_size_exposure"),
                                                 share_beats_exposure = g(PM, "controls.attribution.share_beats_exposure"),
                                                 n_crisis = g(PM, "controls.attribution.n_crisis")))
  S$out$rules <- RL
  pa <- S$pa
  se <- if (is.finite(pa$visible$t) && pa$visible$t != 0) pa$visible$d_alpha / pa$visible$t else NA_real_
  mg <- as.numeric(FS[["alpha_margin_frac"]]) * max(S$ea$alpha_ann, 0)
  S$out$alpha_non_loss <- list(d_alpha = pa$visible$d_alpha, t = pa$visible$t, se = se, n = pa$visible$n, window = pa$visible$window, engine_alpha = S$ea,
                               t_floor = FS[["alpha_t_floor"]], margin_frac = FS[["alpha_margin_frac"]], margin = mg,
                               margin_over_se = if (is.finite(se) && se > 0) mg / se else NA_real_, ok = isTRUE(S$aok))
  S$out$alpha_test_window <- pa$test
  S$out$non_inferiority <- list(S = Sm, S_rx0 = Sr, calmar = S$cmv, calmar_rx0 = S$crv, port_t = S$ptm, port_t_rx0 = S$ptr,
                                basis = if (Sr > 0) "S_vis − tie_eps" else "Calmar(S_rx0 = 0)", ok = isTRUE(r12))
  S$RL <- RL; S$s14 <- s14; S$Sm <- Sm; S$Sr <- Sr; S$r12 <- r12; S$r13 <- r13
  NULL
}
## ⑧ 집중 · ⑪ 회복(공용 기록) — P2R04 L1231-1239 = P2R03 L579-588
rc_p2_st_concentration <- function(S) {
  X <- S$X; FS <- X$fs; g <- rc_getf; PM <- S$PM; PRX <- S$PRX
  tl <- rc_top_loss(PM$exposure$top_losers %||% list(), S$deep_peaks, as.numeric(FS[["single_name_loss_floor"]]))
  tl0 <- rc_top_loss(PRX$exposure$top_losers %||% list(), S$deep_peaks, as.numeric(FS[["single_name_loss_floor"]]))
  conc <- tryCatch(rc_concentration(S$am, X$tau), error = function(e) list(visible = list(error = conditionMessage(e))))
  cst <- rc_conc_status(tl)
  S$out$concentration <- list(status = cst, visible = conc$visible, eff_n_mean = c(g(PM, "profile.eff_n_mean"), g(PRX, "profile.eff_n_mean")),
                              top_loss = tl[setdiff(names(tl), "per_crisis")], top_loss_rx0 = tl0[setdiff(names(tl0), "per_crisis")], per_crisis = tl$per_crisis,
                              concentration_loss_tag = identical(cst, "breach"), unmeasured_tag = identical(cst, "unmeasured"))
  S$out$recovery <- rc_recovery_tag(S$crm, S$crr, S$MAJ)
  S$cst <- cst
  NULL
}
## 기준점 · 귀속 · 기록 · 크기 × β · 유동성 · 국면 월 — P2R04 L1240-1267(판정 칸만 크기 × β · 유동성 · 국면 월 · 실패 = 그 기록만 미측정)
rc_p2_st_records <- function(S) {
  X <- S$X; FS <- X$fs; g <- rc_getf; PM <- S$PM; PRX <- S$PRX; tol <- S$tol; RL <- S$RL; s14 <- S$s14; MAJ <- S$MAJ
  S$out$reference_points <- list(engine = list(all = S$maj$share, deep = S$dmj$share),
                                 market = list(all = rc_p2_vs_market(S$crm, tol), deep = rc_p2_vs_market(S$crm, tol, S$deep)),
                                 market_rx0 = list(all = rc_p2_vs_market(S$crr, tol), deep = rc_p2_vs_market(S$crr, tol, S$deep)))
  r3 <- S$r3
  S$out$attribution <- list(label = s14$label, label_rx0 = as.character(PRX$controls$attribution$label %||% NA)[1],
                            share_beats_size_exposure = RL$selection$share_beats_size_exposure, share_beats_exposure = RL$selection$share_beats_exposure,
                            share_beats_bench = g(PM, "controls.attribution.share_beats_bench"), median_placebo_p = g(PM, "controls.attribution.median_placebo_p"),
                            beta_copy_deep = RL$beta_deep$share,
                            reading = if (is.na(r3)) "β 짝 미측정 — 방어 이름 보류" else
                                      if (isTRUE(s14$ok) && isTRUE(r3)) "선택 방어 후보 — MC8 선택 귀속 ∧ 위기 분해 선택 항 ∧ β 짝 통과" else
                                      if (isTRUE(r3) && !isTRUE(s14$measured)) sprintf("β 짝 통과 · ⑭ 미측정(%s) — 방어 이름 보류", s14$status) else
                                      if (isTRUE(r3)) sprintf("β 짝 통과 · ⑭ 미통과(MC8 %s · 분해 %s) — 크기 방어 또는 노출 방어", s14$label, format(s14$decomposition$ok)) else
                                      "β 짝 미통과 — 노출(β) 방어 또는 방어 없음")
  S$out$record <- list(state_unturned_max_drop = rc_p2_crisis_record(S$crm, S$crr, S$cbp, FS[["state_unturned_max_drop_crises"]], tol, S$deep, S$fk$keys),
                       size_decile = rc_p2_size_compare(PM$exposure$by_size_decile %||% list(), PRX$exposure$by_size_decile %||% list(), S$deep_peaks),
                       rolling = PM$behavior$rolling, turnover_annual = c(variant = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")),
                       cost_drag_annual = c(variant = g(PM, "profile.cost_drag_annual"), rx0 = g(PRX, "profile.cost_drag_annual")),
                       exposure_mean = c(variant = g(PM, "controls.exposure_profile.mean"), rx0 = g(PRX, "controls.exposure_profile.mean")),
                       crisis_dd_capture_median = c(variant = g(PM, "behavior.summary.crisis_dd_capture_median"), rx0 = g(PRX, "behavior.summary.crisis_dd_capture_median")))
  if (!S$diag) {
    t0 <- Sys.time()
    S$out$size_beta <- tryCatch(rc_p2_size_beta_record(X, S$am, PM, S$crm, S$deep, tol, MAJ),
                                error = function(e) list(status = "unmeasured", tag = "크기 × β 짝 미측정", why = conditionMessage(e)))
    .rc_perf_note(X, "size_beta", t0); t0 <- Sys.time()
    S$out$liquidity <- tryCatch(list(variant = rc_p2_liquidity_record(X, S$am, S$crm, S$deep_peaks), rx0 = rc_p2_liquidity_record(X, S$ar, S$crr, S$deep_peaks)),
                                error = function(e) list(status = "unmeasured", tag = "유동성 귀속 미측정", why = conditionMessage(e)))
    .rc_perf_note(X, "liquidity", t0)
    S$out$regime_months <- tryCatch(rc_p2_regime_months(X, S$am, S$ar, PM), error = function(e) list(status = "unmeasured", why = conditionMessage(e)))
  }
  NULL
}
## 결론 이름 · 칸 통과 · 판정어 — P2R04 L1268-1277
rc_p2_st_verdict <- function(S) {
  cfg <- S$T$cfg; RL <- S$RL; s14 <- S$s14
  S$out$conclusion_name <- rc_p2_defense_name(S$r3, S$r4, S$r5_level, s14$ok, S$out$size_beta$ok %||% NA, S$out$size_beta$status %||% (if (S$diag) "skipped_diagnostic" else "unmeasured"),
                                              s14_measured = isTRUE(s14$measured))
  S$out$pass <- rc_p2_cell_pass(list(crisis = RL$crisis$ok, deep = RL$deep$ok, beta_deep = S$r3, fast = S$r4, beta_ratio = S$r5, bull = RL$bull$ok, alpha = S$aok,
                                     cycle = RL$cycle$ok, construction = RL$construction$ok, S = S$r12, path = S$r13, selection = s14$ok))
  S$out$verdict <- rc_p2_cell_verdict(list(pass = S$out$pass, beta_unmeasured = !is.null(S$berr), beta_deep = S$r3, fast = S$r4, crisis = RL$crisis$ok, deep = RL$deep$ok,
                                           selection = s14$ok, selection_measured = isTRUE(s14$measured)))
  S$out$verdict_name <- cfg[["verdict_names"]][[S$out$verdict]]
  S$out$tested <- TRUE
  S$out$tbl <- data.table(engine = S$ctx$engine, device = S$ctx$unit, tested = TRUE, pass = S$out$pass, excluded = !identical(S$cst, "clear"), verdict = S$out$verdict)
  NULL
}
## ⑩ 규칙 항목(팩터 틸트 장치) — P2R04 L1218
rc_p2_construction_rule_factor <- function(S) list(checks = S$cs$checks, device = S$cs$device, holdings_differ = S$ov$n_differ, holdings_dates = S$ov$n_dates, ok = TRUE)

## 템플릿 — P2R04 판 기본값(장치 표 · 진단 표 · 판정어 · 훅은 사양 · 라운드 고유 훅이 덮는다)
##   cfg: devices · diagnostics · diag_engine · capacity_table · verdict_names · verdict_short · verdicts · mc8_labels · mark_full · trim_errtag · beta_errtag ·
##        rl_keep_per_crisis · slow_note · beta_plan · beta_unmeasured_why · alpha_degenerate · fast_err_no_month_end · selection
##   hooks: construction(단계 목록 — 사양 · 장치 · 구성 증거) · treatment · post_packets · construction_rule · records · verdict · init · untested · stages(전체 순서 덮기)
rc_p2_template <- function(cfg = list(), hooks = list()) {
  dc <- list(devices = list(), diagnostics = list(), diag_engine = NA_character_, capacity_table = NULL,
             verdicts = RC_P2_VERDICTS, verdict_names = RC_P2_VERDICT_NAMES, verdict_short = RC_P2_VERDICT_SHORT, mc8_labels = RC_P2_MC8_LABELS,
             mark_full = TRUE, trim_errtag = "p2_trim", beta_errtag = "p2_beta", rl_keep_per_crisis = TRUE,
             slow_note = "기록 — 느린 약세(빠름으로 분류되지 않은 위기)의 β 짝 비율(판정 아님)",
             beta_plan = rc_beta_plan, beta_unmeasured_why = function(k) sprintf("k 비유한 또는 ≤ 0(%s)", format(k)),
             alpha_degenerate = TRUE, fast_err_no_month_end = TRUE, selection = TRUE, unit = "device")
  cfg <- rc_merge_shallow(dc, cfg)
  dh <- list(init = rc_p2_init, untested = rc_p2_untested_fn(cfg[["verdict_names"]]),
             construction = list(rc_p2_st_spec, rc_p2_st_device, rc_p2_st_construction_factor),
             treatment = list(rc_p2_st_treatment), post_packets = list(rc_p2_st_direction),
             construction_rule = rc_p2_construction_rule_factor, records = list(rc_p2_st_records), verdict = list(rc_p2_st_verdict))
  h <- rc_merge_shallow(dh, hooks)
  stages <- h[["stages"]] %||% c(list(rc_st_consts, rc_st_status), h[["construction"]], list(rc_st_effective_start, rc_st_window), h[["treatment"]],
                            list(rc_st_packets), h[["post_packets"]], list(rc_st_engine_alpha, rc_st_crisis_pairs, rc_p2_st_beta, rc_p2_st_inputs, rc_p2_st_judge,
                                                                       rc_p2_st_concentration), h[["records"]], h[["verdict"]])
  list(name = "p2_device", cfg = cfg, hooks = h, init = h[["init"]], untested = h[["untested"]], stages = stages)
}

## ── P2 라운드 판정(출처: P2R04 본 실행 L1285-1424 — 같은 순서 · 같은 파일 필드) ─────────────────────────────
##   R = list(round_id · pre(사전등록 목록: cells · final_selection_rule · tau_d · behavior_card_cfg) · prereg_path · root(계약 · .cache) ·
##            res(읽기 — 칸 평가 · 셀 로그 · 측정 json · 지문) · out(쓰기 — 공통 창 · β 짝 사본 · 평가 파일) · precheck(경로) · fingerprint(스크립트 · 인자) ·
##            evaluate_md5(문자) · rx0_identity(경로 형식 sprintf — 엔진) · rx0_identity_names(cur · prev) · schema_visible · schema_full · prefix · tag ·
##            cell_cache("legacy" | "key") · readings(function(OUT, DOUT, tol, DEVS, T) — 진단 읽기) · log(console 출력 여부))
##   T = rc_p2_template(...) · shard = "i/K"(짝 평가만 · RDS 저장) · merge = TRUE(샤드 결과 병합 → 종합 판정)
rc_p2_round_setup <- function(R, T) {
  pre <- R$pre; root <- R$root
  E <- rc_deps(root)
  if (isTRUE(R$memo)) { rc_memo_install(E); if (isTRUE(R$mc8_memo)) rc_mc_memo_install(E, root) }
  ## R2 — 사전등록 md5 = 등록부 · 핀(판정에 닿는 전체) 재대조 · precheck 통과 기록(출처: P2R04 L1294-1304)
  if (!is.null(R$program)) {
    reg <- pr_load(root); rr <- Filter(function(r) identical(r$round_id, R$round_id), pr_get(reg, R$program)$rounds)
    if (!length(rr) || !identical(rr[[1]]$prereg_md5, rc_md5(R$prereg_path))) stop("[", R$tag, "] 사전등록 md5 불일치(R2)")
  }
  if (isTRUE(R$check_pins)) { pin <- rc_legacy_pin_mismatches(pre, root)
    if (length(pin)) stop("[", R$tag, "] 핀 불일치 — 평가하지 않는다:\n", paste0("  · ", pin, collapse = "\n")) }
  if (!is.null(R$precheck) && (!file.exists(R$precheck) || !isTRUE(fromJSON(R$precheck)$ok))) stop("[", R$tag, "] precheck 통과 기록이 없다 — 측정 조건 미확인")
  BCFG <- file.path(root, pre[["behavior_card_cfg"]][["path"]])
  if (!identical(rc_md5(BCFG), pre[["behavior_card_cfg"]][["md5"]])) stop("[", R$tag, "] 행동 카드 설정 사본 변경")
  FS <- pre[["final_selection_rule"]]
  fsm <- rc_p2_fs_missing(FS, R$fs_keys %||% RC_P2_FS_KEYS); if (length(fsm)) stop("[", R$tag, "] final_selection_rule 키 결손 — 평가하지 않는다: ", paste(fsm, collapse = ","))
  if (!is.null(R$prefix)) {
    cbad <- rc_p2_cells_check(pre[["cells"]], T$cfg[["devices"]], T$cfg[["diagnostics"]], T$cfg[["diag_engine"]], R$prefix)
    if (length(cbad)) stop("[", R$tag, "] 사전등록 칸 목록 불일치:\n", paste0("  · ", cbad, collapse = "\n"))
  }
  env <- new.env(); env$E <- E; env$BCFG_L <- E$bc_cfg(root, path = BCFG); env$raw <- NULL; env$liq <- NULL
  env$raw_disk_cache <- isTRUE(R$raw_disk_cache); env$mc8_cache <- isTRUE(R$mc8_cache)
  list(env = env, FS = FS, TAU = as.Date(pre[["tau_d"]]), BCFG = BCFG)
}
rc_p2_round <- function(R, T, shard = NULL, merge = FALSE, cells_only = FALSE) {
  pre <- R$pre; root <- R$root; RES <- R$res; OUT_DIR <- R$out; tag <- R$tag %||% "P2"
  st <- rc_p2_round_setup(R, T); env <- st$env; FS <- st$FS; TAU <- st$TAU
  pdir <- file.path(OUT_DIR, ".pairs")
  ## 칸 평가(캐시) — 구 라운드 재판정 = legacy(저장분 그대로) · 새 라운드 = key(내용 주소)
  CELLS <- pre[["cells"]]
  t0 <- Sys.time()
  EVS <- lapply(CELLS, function(cl) rc_eval_cell_split_safe(root, RES, cl, env, TAU, cache = R$cell_cache %||% "key", diagnostic_field = TRUE, tag = paste(tag, "평가"),
                                                            write = !isFALSE(R$cell_write)))
  names(EVS) <- vapply(CELLS, function(z) z$code, character(1))
  bad <- names(EVS)[vapply(EVS, function(e) identical(e$status, "eval_error"), logical(1))]
  if (isFALSE(R$cell_write) && length(bad)) stop("[", tag, "] 저장된 칸 평가 없음(재판정은 칸 평가를 새로 쓰지 않는다): ", paste(bad, collapse = ","))
  rc_assert_eval_artifacts(EVS, RES, paste(tag, "평가"))
  .rc_perf_round(R, "cells", t0)
  if (isTRUE(cells_only)) return(invisible(EVS))
  JCELLS <- Filter(function(z) !isTRUE(z$diagnostic), CELLS); DCELLS <- Filter(function(z) isTRUE(z$diagnostic), CELLS)
  cell_of <- function(eng, comp) Filter(function(z) identical(z$engine, eng) && identical(z$component, comp), CELLS)[[1]]
  dfr <- rc_deferred_cells(JCELLS, RES)
  if (length(dfr)) stop("[", tag, "] 측정 연기 칸 — 재측정 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
  X <- list(root = root, res = RES, out = OUT_DIR, env = env, fs = FS, tau = TAU, ea = new.env(), meta = new.env(),
            minimal_copy = isTRUE(R$minimal_copy), raw_disk_cache = isTRUE(R$raw_disk_cache), perf = R$perf_env)
  ENGINES <- unique(vapply(JCELLS, function(z) z$engine, character(1)))
  DEVS <- sort(unique(setdiff(vapply(JCELLS, function(z) z$component, character(1)), "RX0")))
  ## 짝 목록(전체 순서 고정 — 판정 칸 엔진 × 장치 → 진단 칸) · 엔진 묶음 측정 지문(rules.vintage_group)
  FPG <- list(); jobs <- list()
  worker <- !is.null(shard) && !isTRUE(merge)
  FP_EVAL <- if (worker) NA_character_ else rc_fingerprint(R$fingerprint$script, "equality", R$fingerprint$args %||% character(0))
  for (eng in ENGINES) {
    cr <- cell_of(eng, "RX0")
    codes <- unname(c(vapply(DEVS, function(dv) cell_of(eng, dv)$code, character(1)), cr$code))
    fps <- unname(unlist(lapply(codes, function(cd) c(rc_fp_of(RES, cd, "start"), rc_fp_of(RES, cd, "end")))))
    if (anyNA(fps) || length(unique(fps)) != 1L) stop(sprintf("[%s] %s 묶음 데이터 지문 불일치 또는 부재 — 그 묶음을 재측정한 뒤 평가(rules.vintage_group)", tag, eng))
    FPG[[eng]] <- list(measure = fps[1], eval_matches_measure = rc_fp_same(fps[1], FP_EVAL))
    for (dv in DEVS) jobs[[length(jobs) + 1L]] <- list(kind = "judge", eng = eng, dev = dv, cm = cell_of(eng, dv), cr = cr)
  }
  for (cl in DCELLS) jobs[[length(jobs) + 1L]] <- list(kind = "diag", eng = cl$engine, dev = cl$component, cm = cl, cr = cell_of(cl$engine, "RX0"))
  run_job <- function(j) {
    if (identical(j$kind, "judge")) return(rc_pair_run_safe(X, T, list(engine = j$eng, unit = j$dev, cm = j$cm, cr = j$cr, em = EVS[[j$cm$code]], er = EVS[[j$cr$code]])))
    fpd <- c(rc_fp_of(RES, j$cm$code, "start"), rc_fp_of(RES, j$cm$code, "end"))
    if (anyNA(fpd) || is.null(FPG[[j$eng]]) || !all(fpd == FPG[[j$eng]]$measure))
      return(T$untested(list(engine = j$eng, device = j$dev, role = "diagnostic", cell = j$cm$code, rx0 = j$cr$code), "진단 칸 데이터 지문 ≠ 엔진 묶음 지문(또는 부재)"))
    rc_pair_run_safe(X, T, list(engine = j$eng, unit = j$dev, cm = j$cm, cr = j$cr, em = EVS[[j$cm$code]], er = EVS[[j$cr$code]]),
                     opts = list(role = "diagnostic", expect_weight = rc_p2_diag_expect_weight(j$cm$component, CELLS, root, T$cfg[["diagnostics"]], T$cfg[["devices"]])))
  }
  jcode <- vapply(jobs, function(j) j$cm$code, character(1))
  t0 <- Sys.time()
  if (worker) {                                                                   # 샤드 워커 — 맡은 짝만 평가해 RDS 로 남긴다
    for (i in rc_shard_index(length(jobs), shard)) {
      tj <- Sys.time(); od <- run_job(jobs[[i]])
      ek <- X$meta[[jcode[i]]]
      rc_pair_save(pdir, jcode[i], list(out = od, ek = ek, ea = if (!is.null(ek)) X$ea[[ek]] else NULL, seconds = as.numeric(difftime(Sys.time(), tj, units = "secs"))))
      cat(sprintf("[%s 짝] %s — %s · %.0f초\n", tag, jcode[i], od$verdict %||% "-", as.numeric(difftime(Sys.time(), tj, units = "secs"))))
    }
    .rc_perf_round(R, paste0("pairs_shard_", shard), t0)
    return(invisible(TRUE))
  }
  if (isTRUE(merge)) {                                                            # 병합 — 전체 순서로 읽고 엔진 알파 삽입 순서를 재현
    PR <- lapply(jcode, function(cd) rc_pair_load(pdir, cd))
    miss <- jcode[vapply(PR, is.null, logical(1))]
    if (length(miss)) stop("[", tag, "] 샤드 결과 없음: ", paste(miss, collapse = ","))
    res_l <- lapply(PR, `[[`, "out")
    vals <- list(); for (p in PR) if (!is.null(p$ek) && is.null(vals[[p$ek]])) vals[[p$ek]] <- p$ea
    X$ea <- rc_ea_replay(jcode, setNames(lapply(PR, `[[`, "ek"), jcode), vals)
  } else res_l <- lapply(jobs, run_job)
  .rc_perf_round(R, "pairs", t0)
  names(res_l) <- jcode
  OUT <- res_l[vapply(jobs, function(j) identical(j$kind, "judge"), logical(1))]
  DOUT <- res_l[vapply(jobs, function(j) identical(j$kind, "diag"), logical(1))]
  TBL <- lapply(OUT, `[[`, "tbl")
  rc_p2_round_finish(R, T, list(EVS = EVS, OUT = OUT, DOUT = DOUT, TBL = TBL, X = X, FPG = FPG, FP_EVAL = FP_EVAL, ENGINES = ENGINES, DEVS = DEVS,
                                cell_of = cell_of, FS = FS, TAU = TAU, env = env))
}
.rc_perf_round <- function(R, stage, t0) {
  pe <- R$perf_env
  if (is.environment(pe)) pe[[paste0("round_", stage)]] <- (pe[[paste0("round_", stage)]] %||% 0) + as.numeric(difftime(Sys.time(), t0, units = "secs"))
  invisible(NULL)
}
## 종합 — 진단 읽기 · A 거리 · RX0 동일성 · 라운드 판정 · 선택 · R7 · 칸 요약 · 보는 창 / 사람 쪽 파일(τ_D 전수 검사 뒤 쓰기) — 출처: P2R04 L1352-1424
rc_p2_round_finish <- function(R, T, Z) {
  EVS <- Z$EVS; OUT <- Z$OUT; DOUT <- Z$DOUT; X <- Z$X; FS <- Z$FS; TAU <- Z$TAU; env <- Z$env; root <- R$root; tag <- R$tag %||% "P2"
  pre <- R$pre; RES <- R$res; DEVS <- Z$DEVS; ENGINES <- Z$ENGINES; cfg <- T$cfg
  .safe_rec <- function(expr) tryCatch(expr, error = function(e) list(status = "error", why = conditionMessage(e)))
  READ <- .safe_rec(if (is.function(R$readings)) R$readings(OUT, DOUT, as.numeric(FS[["crisis_improve_min"]]), DEVS, T) else list(status = "none"))
  GV3 <- .safe_rec(list(th = env$E$gv3_thresholds(root), cfg = env$E$gv3_cfg(root)))
  ADIST <- setNames(lapply(names(EVS), function(cd) .safe_rec({
    pk <- rc_pk_read(X, cd)
    if (is.null(pk)) list(status = "no_packet") else if (identical(GV3$status, "error")) list(status = "unmeasured", why = GV3$why) else {
      S <- env$E$gv3_S(rc_getf(pk, "performance.strategy.calmar"), rc_getf(pk, "performance.strategy.port_t"), GV3$th, GV3$cfg[["weights"]])
      c(list(status = "ok", window = unlist(pk$window)), rc_p2_a_distance(pk$performance$strategy, rc_getf(pk, "performance.benchmark.calmar"), GV3$th, S, GV3$cfg[["a_boundary"]])) }
  })), names(EVS))
  RXI <- if (!is.null(R$rx0_identity)) setNames(lapply(ENGINES, function(eng) tryCatch(rc_p2_rx0_identity(X, EVS[[Z$cell_of(eng, "RX0")$code]]$artifacts, file.path(root, sprintf(R$rx0_identity, eng)),
                                                                                                            cur = R$rx0_identity_names[1] %||% "p2r04", prev = R$rx0_identity_names[2] %||% "p2r03"),
                                                                                         error = function(e) list(status = paste("오류:", conditionMessage(e))))), ENGINES) else list()
  TB <- rbindlist(Z$TBL)
  rv <- rc_round_verdict(TB, "device", cfg[["verdicts"]], cfg[["verdict_short"]])
  validated <- rv$both
  xs_by <- setNames(lapply(validated, function(dv) Filter(function(x) identical(x$device, dv), OUT)), validated)
  sel <- rc_select(xs_by)
  NOISE <- .safe_rec(rc_p2_noise_reading(OUT, validated, FS[["tie_eps"]], FS[["majority_share"]], DEVS))
  excl <- lapply(rv$excluded, function(dv) list(device = dv, concentration = unique(vapply(Filter(function(x) identical(x$device, dv), OUT),
                                                                                           function(x) as.character(x$concentration$status %||% "NA"), character(1)))))
  SUMMARY <- rbindlist(lapply(c(OUT, DOUT), function(x) {
    su <- as.data.table(x$record$state_unturned_max_drop %||% data.table())
    data.table(role = x$role %||% "judge", engine = x$engine, device = x$device, factor = x$device_factor$id %||% NA_character_, cell = x$cell, tested = isTRUE(x$tested),
               verdict = x$verdict %||% NA_character_, verdict_name = x$verdict_name %||% NA_character_, pass = isTRUE(x$pass),
               conclusion_name = x$conclusion_name %||% NA_character_, attribution = x$attribution$label %||% NA_character_,
               selection_status = x$rules$selection$status %||% NA_character_, selection_decomp_ok = x$rules$selection$decomposition$ok %||% NA,
               beta_deep = x$rules$beta_deep$status %||% NA_character_, fast = x$rules$fast$status %||% NA_character_,
               size_beta = x$size_beta$status %||% NA_character_, size_beta_ok = x$size_beta$ok %||% NA,
               holdings_differ = x$holdings_overlap$n_differ %||% NA_integer_, holdings_dates = x$holdings_overlap$n_dates %||% NA_integer_,
               name_overlap_mean = x$holdings_overlap$name_overlap_mean %||% NA_real_, name_overlap_min = x$holdings_overlap$name_overlap_min %||% NA_real_,
               state_unturned_beats_beta = if (nrow(su) && "beats_beta_copy" %in% names(su)) paste(ifelse(is.na(su$beats_beta_copy), "NA", su$beats_beta_copy), collapse = ",") else NA_character_,
               concentration = x$concentration$status %||% NA_character_)
  }), fill = TRUE)
  pc <- if (!is.null(R$precheck)) fromJSON(R$precheck) else list(ok = NA, at = NA, prereg_md5 = NA)   # 코어 흐름 = driver precheck 단계(파일 없음)
  VIS <- list(schema = R$schema_visible %||% "round_core_p2_evaluation_visible_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rc_md5(R$prereg_path),
              evaluate_md5 = R$evaluate_md5 %||% NA_character_, tau_d = pre[["tau_d"]], devices = cfg[["devices"]], diagnostics_def = cfg[["diagnostics"]],
              verdict_names = as.list(cfg[["verdict_names"]]), cells = lapply(OUT, rc_p2_visible_only, tau = TAU), diagnostics = lapply(DOUT, rc_p2_visible_only, tau = TAU),
              readings = rc_p2_visible_only(READ, TAU), rx0_identity = RXI, a_distance = ADIST, noise_reading = NOISE, capacity_table = cfg[["capacity_table"]],
              table = TB, summary = SUMMARY,
              verdict = rv$verdict, verdict_label = rv$label, n_judged = rv$n_judged, n_total = rv$n_total, pass_both = rv$both, pass_one = rv$one,
              excluded = excl, validated = validated, selected = sel, engine_alpha = as.list(X$ea),
              fingerprint = list(eval = Z$FP_EVAL, eval_record = rc_fingerprint(R$fingerprint$script, "record", R$fingerprint$record_args %||% character(0)), groups = Z$FPG),
              precheck = list(ok = if (is.na(pc$ok %||% NA)) NA else isTRUE(pc$ok), at = pc$at, prereg_md5 = pc$prereg_md5))
  ## 보는 창 파일 전수 검사(C-031) — 메타(평가 · precheck 시각 · 지문) 밖에서 τ_D 이후 날짜가 하나라도 남으면 쓰지 않는다(계약 dp_scan_dates + 코어 누출 검사 둘 다)
  chk <- VIS[setdiff(names(VIS), c("evaluated_at", "precheck", "fingerprint"))]
  bad_dates <- unique(c(dp_scan_dates(chk, TAU), rc_after_tau_leaks(chk, TAU)))
  if (length(bad_dates)) stop(sprintf("[%s] 보는 창 파일에 τ_D 이후 날짜 %d개 — 쓰지 않는다(C-031 · 가림 결함)", tag, length(bad_dates)))
  FULL <- list(schema = R$schema_full %||% "round_core_p2_evaluation_full_v1", audience = RC_FULL_AUDIENCE, evaluated_at = VIS$evaluated_at, prereg_md5 = VIS$prereg_md5,
               cells = lapply(names(EVS), function(cd) { x <- c(OUT, DOUT)[[cd]]
                                                          list(code = cd, test = EVS[[cd]]$test, full = EVS[[cd]]$full, alpha_test_window = x$alpha_test_window %||% NULL,
                                                               cell_log_full_period = x$cell_log_full_period %||% NULL, why = x$why %||% NULL) }))
  dir.create(R$out, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(FULL, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(R$out, "evaluation_full.json"), useBytes = TRUE)
  writeLines(toJSON(VIS, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(R$out, "evaluation_visible.json"), useBytes = TRUE)
  if (!isFALSE(R$log)) {
    pj <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
    for (x in c(OUT, DOUT)) cat(sprintf("[%s 평가] %s%s %s — %s%s · ③ %s ④ %s ⑭ %s · 집중 %s\n", tag, if (identical(x$role, "diagnostic")) "[진단] " else "", x$engine, x$device,
                                        x$verdict, if (!isTRUE(x$tested)) paste0("(", .rc_redact_chr(x$why %||% "-", TAU), ")") else "",
                                        x$rules$beta_deep$status %||% "-", x$rules$fast$status %||% "-", x$rules$selection$status %||% "-", x$concentration$status %||% "-"))
    cat(sprintf("[%s 평가] 판정 %s · 두 엔진 통과 %s · 한 엔진 %s · 선택 %s · R7 %s\n", tag, rv$label, pj(rv$both), pj(rv$one), if (length(sel)) sel[[1]]$device else "-", NOISE$label %||% "-"))
  }
  invisible(list(VIS = VIS, FULL = FULL, OUT = OUT, DOUT = DOUT, EVS = EVS, rv = rv))
}

## ── 코어 사양 라운드(round_spec.json · template = p2_device) — driver evaluate 가 부른다 ─────────────────────────────
##   사양이 쓰는 것: cells(code · engine · role · component · spec) · params(판정 상수 — 값 + 근거 또는 정본 참조) · devices · diagnostics · diag_engine ·
##   capacity_table · rules(선언 — rules.R + rules_p2.R 종류) · behavior_card_cfg · ext(고유 훅 파일 — RC_EXT_CFG · RC_EXT_HOOKS · RC_EXT_READINGS ·
##   RC_EXT_RULES_MAP). 판정 단계 · 기록 · 라운드 판정은 템플릿(P2R04 판)이 한다 — 라운드는 판정 코드를 새로 쓰지 않는다.
rc_spec_params <- function(spec, root) {
  ps <- spec[["params"]] %||% list(); FS <- list()
  for (k in names(ps)) { p <- ps[[k]]
    if (!is.null(p[["value_ref"]])) FS[[k]] <- rc_ref_value(p[["value_ref"]], root)
    else if (!is.null(p[["value"]])) { if (is.null(p[["basis"]]) || !nzchar(p[["basis"]])) stop("[round_core] params.", k, " 근거(basis) 없음 — 하드코딩 금지"); FS[[k]] <- p[["value"]] }
    else stop("[round_core] params.", k, " 에 value 또는 value_ref 가 없다") }
  FS
}
rc_spec_cells_legacy <- function(spec, root) lapply(spec[["cells"]], function(c) {
  if (is.null(c[["component"]])) stop("[round_core] P2 · P3 칸에는 component 가 필요하다: ", c[["code"]])
  list(code = c[["code"]], engine = c[["engine"]], component = c[["component"]], path = c[["spec"]], md5 = rc_md5(rc_abs(c[["spec"]], root)),
       reference = identical(c[["role"]], "reference"), diagnostic = identical(c[["role"]], "diagnostic"))
})
rc_spec_ext <- function(spec, root) {
  e <- new.env(parent = globalenv())
  if (!is.null(spec[["ext"]])) sys.source(rc_abs(spec[["ext"]], root), envir = e)
  list(cfg = e$RC_EXT_CFG %||% list(), hooks = e$RC_EXT_HOOKS %||% list(), readings = e$RC_EXT_READINGS, rules_map = e$RC_EXT_RULES_MAP)
}
## 템플릿 기본 칸 기록 대응(선언 규칙 id → 칸 기록) — 선언 판정 = 단계 판정 대조(rc_p2_rules_crosscheck)
RC_P2_RULES_MAP <- list(crisis = function(x) x$rules$crisis$ok, deep = function(x) x$rules$deep$ok,
                        beta_deep = function(x) if (identical(x$rules$beta_deep$status, "ok")) x$rules$beta_deep$ok else NA,
                        fast = function(x) if (identical(x$rules$fast$status, "ok")) x$rules$fast$ok else NA,
                        bull = function(x) x$rules$bull$ok, alpha = function(x) x$alpha_non_loss$ok)
rc_p2_evaluate <- function(spec, pre, root, round_dir, P, shard = NULL, merge = FALSE) {
  ext <- rc_spec_ext(spec, root)
  cfg <- rc_merge_shallow(list(devices = spec[["devices"]] %||% list(), diagnostics = spec[["diagnostics"]] %||% list(),
                                diag_engine = spec[["diag_engine"]] %||% NA_character_,
                                capacity_table = if (!is.null(spec[["capacity_table"]])) rbindlist(spec[["capacity_table"]], fill = TRUE) else NULL),
                           ext[["cfg"]])
  T <- rc_p2_template(cfg = cfg, hooks = ext[["hooks"]])
  FS <- rc_spec_params(spec, root)
  pl <- list(cells = rc_spec_cells_legacy(spec, root), final_selection_rule = FS, tau_d = spec[["tau_d"]], behavior_card_cfg = pre[["behavior_card_cfg"]])
  tag <- rc_round_tag(spec[["round_id"]])
  R <- list(round_id = spec[["round_id"]], tag = tag, prefix = tag, pre = pl, prereg_path = P$prereg, root = root, res = P$results, out = P$results, precheck = NULL,
            fingerprint = list(script = file.path(RC_DIR, "fingerprint.sh"), args = character(0), record_args = character(0)), evaluate_md5 = rc_core_manifest()$manifest_md5,
            fs_keys = names(FS), cell_cache = "key", readings = ext[["readings"]], memo = TRUE, mc8_memo = TRUE, mc8_cache = TRUE, minimal_copy = TRUE,
            schema_visible = "round_core_p2_evaluation_visible_v1", schema_full = "round_core_p2_evaluation_full_v1", perf_env = new.env())
  r <- rc_p2_round(R, T, shard = shard, merge = merge)
  if (!is.null(shard) && !isTRUE(merge)) return(invisible(list(worker = TRUE)))
  rules <- pre[["rules_resolved"]]
  rc_p2_rules_tau_check(rules)
  map <- c(RC_P2_RULES_MAP, ext[["rules_map"]] %||% list())
  map <- map[intersect(names(map), vapply(rules, function(z) z[["id"]], character(1)))]
  cc <- rc_p2_rules_crosscheck(rules, r$OUT, r$EVS, map)
  if (!isTRUE(cc$ok)) stop("[round_core p2] 규칙 선언 판정 ≠ 템플릿 단계 판정(문구 표류 — 판정하지 않는다):\n", paste(cc$mismatches, collapse = "\n"))
  for (st in names(R$perf_env)) rc_perf_log(spec[["round_id"]], st, R$perf_env[[st]], root = root)
  list(schema = "round_core_p2_verdict_v1", core = RC_VERSION, round_id = spec[["round_id"]], evaluated_at = rc_now(), rules = rules, sentences = pre[["sentences"]],
       table = r$VIS$table, verdict = r$rv$verdict, verdict_label = r$rv$label, n_judged = r$rv$n_judged, n_total = r$rv$n_total,
       validated = r$VIS$validated, selected = r$VIS$selected, noise_reading = r$VIS$noise_reading, rules_crosscheck = cc[c("ok", "mismatches")],
       declared = cc$table, writes_visible = TRUE)
}
