## round_core v3 · pair — 짝 평가(변형 칸 대 같은 배치 기준 칸 RX0) 골격 · P2 · P3 공용 도우미
##   1계층 속도 계획 WP1-b(도훈 10-20 L1-SPEED-PLAN-20261020). 라운드마다 복사 · 확장되던 짝 판정 코드를 한 곳으로 모은다.
##   출처(함수 본문 = 같은 동작 · 이름과 전역 상수만 인자로 바꿨다 — 줄 번호는 각 등록 커밋 판):
##     P2R04 = 04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/evaluate.R  (등록 a32201675 · 파일 9e34f5f05)
##     P2R03 = 04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/evaluate.R (등록 9bb76f972 · 파일 5346d12da)
##     P3R03 = 04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/evaluate.R (등록 c7166d2ca · 파일 53bce362d)
##   수치는 전부 R 계약 산출(dp_build · mc_card · beta_controlled_alpha · behavior_card — 손계산 없음 · AX-008). 계약 파일은 읽기만 한다.
##   ★목록 · 설정 필드는 [[ ]] 로 읽는다(R `$` 부분 일치 — 10-20 실제 결함 · P2R04 `opts$expect_cell` 회귀와 같은 부류).

## ── 짝 판정 공용 상수(P2R04 L52 · L79-82) ───────────────────────────────────────────────
RC_FULL_AUDIENCE <- "사람 쪽 판정 전용(τ_D 2022-12-31 이후 · 전기간 포함) — 보는 창 리뷰어(철학 P1 · P2 · P4 · 판단 Superfan · 처방 레인) 열람 금지(C-031)"
RC_FULL_MARK <- "NO_VISIBLE_REVIEW.txt"
RC_FULL_MARK_PARENT <- "이 폴더의 visible* 하위 폴더(보는 창 패킷)만 보는 창 리뷰어 열람 가능 — artifacts · rx0_artifacts · rx0_beta_scaled = 전기간 사본(열람 금지)"
## 작업 사본(공통 창 · β 짝)의 최소 파일 — 02~05 CSV 밖에서 dp_build(.dp_read · ta_resolve_artifact)가 읽는 파일만(속도 · 결과 동일 실증 = 패킷 바이트 동일)
RC_ARTIFACT_MINIMAL <- c("00_manifest.json", "01_strategy_spec.json", "authoritative_remeasure.json")

## ── 순수 도우미(계약 호출 없음) ───────────────────────────────────────────────────────
## 출처: P2R04 L90-92 = P2R03 L25-27 = P3R03 L21-23(.p2_rows_dt · .p2_key)
.rc_rows_dt <- function(x) if (is.data.frame(x)) as.data.table(x) else if (!length(x)) data.table() else
  rbindlist(lapply(x, function(r) as.data.table(lapply(r, function(v) if (is.null(v) || !length(v)) NA else v[[1]]))), fill = TRUE)
.rc_key <- function(x) paste(as.character(x$peak_date), as.character(x$trough_date))
## 칸 사양 경로 — 사전등록 칸(path) · 코어 사양 칸(spec)
.rc_cell_spec <- function(c) c[["path"]] %||% c[["spec"]]
## 얕은 합치기 — 사양 · 고유 훅이 기본값을 이름 단위로 통째로 덮는다(utils::modifyList 는 이름 없는 목록(단계 목록)을 덮지 못하고 목록 값을 재귀로 섞는다) · NULL 도 값으로 둔다
rc_merge_shallow <- function(x, y) { for (k in names(y)) x[k] <- list(y[[k]]); x }

## 보는 창 밖 작업 사본 표식 — 출처: P2R04 L83-87(.p2_mark_full)
rc_mark_full <- function(dir, note = NULL, audience = RC_FULL_AUDIENCE) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(audience, note), file.path(dir, RC_FULL_MARK), useBytes = TRUE)
  invisible(dir)
}
## 다시 쓰지 않는 파일 복사 — minimal = 최소 파일(RC_ARTIFACT_MINIMAL) + 다시 쓰지 않는 02~05 CSV(β 짝 사본의 05 벤치) · 아니면 구판 그대로(디렉터리 아닌 모든 파일 · 패턴 제외)
.rc_copy_side_files <- function(src_dir, out_dir, skip_rx, minimal) {
  fs <- list.files(src_dir, full.names = TRUE)
  keep <- function(b) !isTRUE(minimal) || b %in% RC_ARTIFACT_MINIMAL || grepl("^0[2-5]_.*[.]csv$", b)
  for (f in fs) if (!dir.exists(f) && !grepl(skip_rx, basename(f)) && keep(basename(f))) file.copy(f, out_dir, overwrite = TRUE)
  invisible(NULL)
}

## 공통 창 사본 — 출처: P2R04 L97-124(p2_trim_artifacts) = P2R03 L29-55 · P3R03 L25-51(두 판은 표식 없음 → mark = FALSE · 오류 머리말 errtag)
##   02 · 03 · 05 는 start 이후 · 04 는 start 이하 마지막 리밸부터 · NAV · 벤치 재기준 · 나머지 복사(minimal = 최소 파일만)
rc_trim_artifacts <- function(src_dir, out_dir, start, mark = TRUE, minimal = FALSE, errtag = "p2_trim") {
  start <- as.Date(start)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  .rc_copy_side_files(src_dir, out_dir, "^0[2-5]_.*[.]csv$", minimal)
  rd <- function(n, tick = FALSE) { p <- file.path(src_dir, n)
                                    x <- if (tick) fread(p, colClasses = list(character = "ticker")) else fread(p)
                                    x[, date := as.Date(date)]; x }
  pr <- rd("03_period_returns.csv")[date >= start]
  br <- rd("05_benchmark_returns.csv")[date >= start]
  nv <- rd("02_nav.csv")[date >= start]
  H  <- rd("04_holdings.csv", tick = TRUE)
  h0 <- suppressWarnings(max(H$date[H$date <= start]))
  H  <- H[date >= (if (is.finite(h0)) h0 else start)]
  if (!nrow(pr) || !nrow(nv) || !nrow(br)) stop("[", errtag, "] start ", format(start), " 이후 행이 없다: ", src_dir)
  setorder(nv, date); setorder(br, date)
  if ("nav_net" %in% names(nv)) {
    g0 <- if ("nav_gross" %in% names(nv)) nv$nav_gross[1] else NA_real_; n0 <- nv$nav_net[1]
    nv[, nav_net := nav_net / n0]
    if ("nav_gross" %in% names(nv)) nv[, nav_gross := nav_gross / g0]
    if ("cum_cost" %in% names(nv) && "nav_gross" %in% names(nv)) nv[, cum_cost := nav_gross - nav_net]
    if ("drawdown_net" %in% names(nv)) nv[, drawdown_net := nav_net / cummax(nav_net) - 1]
  }
  if ("benchmark_nav" %in% names(br) && "benchmark_ret" %in% names(br)) br[, benchmark_nav := cumprod(1 + benchmark_ret)]
  for (z in list(list(pr, "03_period_returns.csv"), list(br, "05_benchmark_returns.csv"), list(nv, "02_nav.csv"), list(H, "04_holdings.csv")))
    fwrite(z[[1]], file.path(out_dir, z[[2]]))
  if (isTRUE(mark)) rc_mark_full(out_dir)
  invisible(list(start = start, holdings_from = if (is.finite(h0)) h0 else start, n_pr = nrow(pr)))
}

## β 짝 사본(헌장 빈칸 8) — 출처: P2R04 L127-147(p2_beta_scaled_copy) = P2R03 L58-77 · P3R03 L54-73(표식 없음 · 머리말 p3_beta)
##   기준 칸의 기간수익 · NAV 를 k(< 1)배 노출로(잔여 1−k = 현금 · 수익 0) · 보유 비중도 k 배 · 벤치 · 나머지 파일은 그대로
##   minimal = TRUE(속도): 나머지 파일 중 dp_build 가 읽는 것만 복사 — 패킷 바이트 동일 실증(heavy_round_core_v1_p2_rejudge.R)
rc_beta_scaled_copy <- function(src_dir, out_dir, k, mark = TRUE, minimal = FALSE, errtag = "p2_beta") {
  if (!is.finite(k) || k <= 0 || k > 1) stop("[", errtag, "] k 는 (0, 1]: ", k)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  .rc_copy_side_files(src_dir, out_dir, "^0[234]_.*[.]csv$", minimal)
  pr <- fread(file.path(src_dir, "03_period_returns.csv")); pr[, date := as.Date(date)]; setorder(pr, date)
  rc <- intersect(c("ret_net", "ret_gross", "ret"), names(pr))
  for (cn in rc) set(pr, j = cn, value = k * pr[[cn]])
  nv <- fread(file.path(src_dir, "02_nav.csv")); nv[, date := as.Date(date)]; setorder(nv, date)
  if ("nav_net" %in% names(nv) && "ret_net" %in% names(pr)) {
    m <- match(nv$date, pr$date); r <- pr$ret_net[m]; r[!is.finite(r)] <- 0
    nv[, nav_net := nav_net[1] * cumprod(1 + r)]
    if ("nav_gross" %in% names(nv)) { rg <- if ("ret_gross" %in% names(pr)) pr$ret_gross[m] else r; rg[!is.finite(rg)] <- 0; nv[, nav_gross := nav_gross[1] * cumprod(1 + rg)] }
    if ("cum_cost" %in% names(nv) && "nav_gross" %in% names(nv)) nv[, cum_cost := nav_gross - nav_net]
    if ("drawdown_net" %in% names(nv)) nv[, drawdown_net := nav_net / cummax(nav_net) - 1]
  }
  H <- fread(file.path(src_dir, "04_holdings.csv"), colClasses = list(character = "ticker"))
  for (cn in intersect(c("target_weight", "actual_weight"), names(H))) set(H, j = cn, value = k * as.numeric(H[[cn]]))
  fwrite(pr, file.path(out_dir, "03_period_returns.csv")); fwrite(nv, file.path(out_dir, "02_nav.csv")); fwrite(H, file.path(out_dir, "04_holdings.csv"))
  if (isTRUE(mark)) rc_mark_full(dir = out_dir)
  invisible(list(k = k, n_pr = nrow(pr)))
}

## β 짝 계획 — 출처: P2R04 L150-157(p2_beta_plan) · k = 변형 β / RX0 β · 0 < k < 1 = 사본 · k ≥ 1 = RX0 · 비유한 · ≤ 0 = 미측정 · force_k = 리허설 전용
rc_beta_plan <- function(beta_v, beta_r, force_k = NULL) {
  bv <- suppressWarnings(as.numeric(beta_v)); br <- suppressWarnings(as.numeric(beta_r))
  k <- if (!is.null(force_k)) suppressWarnings(as.numeric(force_k))[1] else
    if (length(bv) == 1L && length(br) == 1L && is.finite(bv) && is.finite(br) && br > 0) bv / br else NA_real_
  mode <- if (!is.finite(k) || k <= 0) "unmeasured" else if (k >= 1) "rx0" else "scaled"
  list(k = k, mode = mode, forced = !is.null(force_k),
       comparator = switch(mode, rx0 = "RX0(k ≥ 1)", scaled = "RX0 × k", unmeasured = "미측정"))
}
## β 짝 계획 구판(인라인) — 출처: P2R03 L507-510 · P3R03 L407 — k 비유한만 미측정 · k ≤ 0 은 사본 단계에서 실패(그 오류 문구가 why) ·
##   비교 대상 이름 = k 유한 ∧ k ≥ 1 이면 'RX0(k ≥ 1)' 아니면 'RX0 × k'(구 라운드 결과 동일 재판정용)
rc_beta_plan_v1 <- function(beta_v, beta_r, force_k = NULL) {
  k <- if (!is.null(force_k)) as.numeric(force_k) else if (is.finite(beta_v) && is.finite(beta_r) && beta_r > 0) beta_v / beta_r else NA_real_
  list(k = k, mode = if (!is.finite(k)) "unmeasured" else if (k >= 1) "rx0" else "scaled", forced = !is.null(force_k),
       comparator = if (is.finite(k) && k >= 1) "RX0(k ≥ 1)" else "RX0 × k")
}

## 위기 짝 비율 — 출처: P2R04 L166-177(p2_crisis_majority) = P2R03 L79-90 = P3R03 L75-86(기본 metric 만 cum_capture — 호출은 모두 명시)
##   metric 이 기준 − tol 보다 낮은 위기의 비율 · subset = 판정에 쓸 위기 키(NULL = 짝 전부)
rc_crisis_majority <- function(cr_m, cr_r, tol, metric = "dd_capture", subset = NULL) {
  cm <- .rc_rows_dt(cr_m); cr <- .rc_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !(metric %in% names(cm)) || !(metric %in% names(cr)))
    return(list(n_pair = 0L, n_better = 0L, share = NA_real_, unpaired = nrow(cm) + nrow(cr)))
  cm[, k := .rc_key(cm)]; cr[, k := .rc_key(cr)]
  J <- merge(cm[, .(k, m = as.numeric(get(metric)))], cr[, .(k, r = as.numeric(get(metric)))], by = "k")
  unp <- (nrow(cm) - nrow(J)) + (nrow(cr) - nrow(J))
  if (!is.null(subset)) J <- J[k %in% subset]
  J <- J[is.finite(m) & is.finite(r)]
  nb <- sum(J$m < J$r - tol)
  list(n_pair = nrow(J), n_better = nb, share = if (nrow(J)) nb / nrow(J) else NA_real_, unpaired = unp, per_crisis = J)
}
## 깊은 위기 — 출처: P2R04 L194-201 = P2R03 L92-99 = P3R03 L88-95 — 두 칸 모두에 있는 위기 중 벤치 낙폭(bm_dd) 크기 ≥ 그 집합 중앙값
rc_deep_crisis_keys <- function(cr_m, cr_r) {
  cm <- .rc_rows_dt(cr_m); cr <- .rc_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("bm_dd" %in% names(cr))) return(character(0))
  cm[, k := .rc_key(cm)]; cr[, k := .rc_key(cr)]
  J <- cr[k %in% cm$k, .(k, depth = abs(as.numeric(bm_dd)))][is.finite(depth)]
  if (!nrow(J)) return(character(0))
  J[depth >= stats::median(depth), k]
}
## 사이클 짝 · 사이클 복리 — 출처: P2R04 L256-283 = P2R03 L181-208 = P3R03 L98-127
##   직전 위기 바닥 연월 이후 시작 · 이 위기 고점 연월까지 끝난 강세 중 마지막 · 강세 1회 사용 · 짝 2 미만 NA
rc_cycle_pairs <- function(bull, crises) {
  b <- .rc_rows_dt(bull); cr <- .rc_rows_dt(crises)
  emp <- data.table(k = character(0), bull = character(0), b_st = numeric(0), c_st = numeric(0))
  if (!nrow(cr)) return(list(pairs = emp, unpaired = character(0)))
  cr[, k := .rc_key(cr)][, pym := substr(as.character(peak_date), 1, 7)][, tym := substr(as.character(trough_date), 1, 7)]
  cr <- cr[order(as.character(peak_date))]
  if (nrow(b)) b[, bid := paste(start_ym, end_ym)][, s := as.character(start_ym)][, e := as.character(end_ym)]
  used <- character(0); rows <- list(); unp <- character(0)
  for (i in seq_len(nrow(cr))) {
    lo <- if (i > 1L) cr$tym[i - 1L] else ""
    cand <- if (nrow(b)) b[s >= lo & e <= cr$pym[i] & !(bid %in% used)] else b
    if (!nrow(cand)) { unp <- c(unp, cr$k[i]); next }
    p <- cand[order(e, s)][.N]
    used <- c(used, p$bid)
    rows[[length(rows) + 1L]] <- data.table(k = cr$k[i], bull = p$bid, b_st = as.numeric(p$st_cum), c_st = as.numeric(cr$st_cum[i]))
  }
  list(pairs = if (length(rows)) rbindlist(rows) else emp, unpaired = unp)
}
rc_cycle_compound <- function(bull_m, cr_m, bull_r, cr_r, min_pairs = 2L) {
  pm <- rc_cycle_pairs(bull_m, cr_m); pr <- rc_cycle_pairs(bull_r, cr_r)
  M <- pm$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  R <- pr$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  K <- merge(M[, .(k, bull)], R[, .(k, bull)], by = c("k", "bull"))
  J <- merge(M, R, by = c("k", "bull"), suffixes = c("_m", "_r"))[is.finite(cyc_m) & is.finite(cyc_r)]
  list(n_pair = nrow(J), n_ge = sum(J$cyc_m >= J$cyc_r), share = if (nrow(J) >= min_pairs) mean(J$cyc_m >= J$cyc_r) else NA_real_,
       min_pairs = as.integer(min_pairs), unpaired_crises = sort(unique(c(pm$unpaired, pr$unpaired))),
       pair_mismatch = (nrow(M) - nrow(K)) + (nrow(R) - nrow(K)), per_cycle = J)
}
## 집중 손실(헌장 빈칸 1) — 출처: P2R04 L285-296 = P2R03 L210-221 = P3R03 L130-143 — 깊은 위기가 표에 빠지면 partial → 미측정(0 으로 접지 않는다)
rc_top_loss <- function(top_losers, deep_peaks, floor) {
  TL <- .rc_rows_dt(top_losers)
  if (!nrow(TL) || !all(c("peak_date", "contrib") %in% names(TL)))
    return(list(status = "unmeasured", n_breach = NA_integer_, missing_deep = as.character(deep_peaks)))
  TL[, contrib := as.numeric(contrib)][, peak_date := as.character(peak_date)]
  per <- TL[is.finite(contrib), .(top1 = min(contrib), top3 = sum(sort(contrib)[seq_len(min(3L, .N))])), by = peak_date]
  deep <- per[peak_date %in% as.character(deep_peaks)]
  miss <- setdiff(as.character(deep_peaks), per$peak_date)
  list(status = if (length(miss)) "partial" else "ok", per_crisis = per, n_breach = sum(deep$top1 < floor), missing_deep = miss,
       deep_top1_min = if (nrow(deep)) min(deep$top1) else NA_real_)
}
rc_conc_status <- function(tl) if (isTRUE(tl$n_breach > 0L)) "breach" else if (identical(tl$status, "ok")) "clear" else "unmeasured"
## 알파 비열등(헌장 빈칸 4C) — 출처: P2R04 L298-302 = P2R03 L223-227 = P3R03 L221-225 — t > t_floor ∧ 증분 ≥ −margin_frac × max(엔진 α, 0) · 입력 NA → NA
rc_alpha_ok <- function(pa_vis, t_floor, engine_alpha, margin_frac) {
  t <- suppressWarnings(as.numeric(pa_vis$t)); d <- suppressWarnings(as.numeric(pa_vis$d_alpha)); ea <- suppressWarnings(as.numeric(engine_alpha))
  if (!length(t) || !length(d) || !is.finite(t) || !is.finite(d) || !length(ea) || !is.finite(ea)) return(NA)
  (t > t_floor) && (d >= -margin_frac * max(ea, 0))
}
## 회복 지연 꼬리표(헌장 빈칸 5) — 출처: P2R04 L304-319 = P2R03 L229-244(과반 = 비율 > maj · 비율은 유한 — rc_maj 와 같은 값)
rc_recovery_tag <- function(cr_m, cr_r, maj) {
  cm <- .rc_rows_dt(cr_m); cr <- .rc_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("st_recovery_obs" %in% names(cm)) || !("st_recovery_obs" %in% names(cr)))
    return(list(status = "unmeasured", tag = FALSE))
  cm[, k := .rc_key(cm)]; cr[, k := .rc_key(cr)]
  if (!"st_recovery_censored" %in% names(cm)) cm[, st_recovery_censored := NA]
  if (!"st_recovery_censored" %in% names(cr)) cr[, st_recovery_censored := NA]
  J <- merge(cm[, .(k, m = as.numeric(st_recovery_obs), mc = as.logical(st_recovery_censored))],
             cr[, .(k, r = as.numeric(st_recovery_obs), rc = as.logical(st_recovery_censored))], by = "k")
  J[, `:=`(m = fifelse(!is.finite(m) & mc %in% TRUE, Inf, m), r = fifelse(!is.finite(r) & rc %in% TRUE, Inf, r))]
  J <- J[!is.na(m) & !is.na(r) & !(is.infinite(m) & is.infinite(r))]
  if (!nrow(J)) return(list(status = "unmeasured", tag = FALSE))
  sh <- mean(J$m > J$r)
  list(status = "ok", n_pair = nrow(J), n_longer = sum(J$m > J$r), share = sh, tag = rc_maj(sh, maj), n_censored_variant = sum(is.infinite(J$m)), per_crisis = J)
}
## 보유 대조 — 출처: P2R04 L457-476(p2_holdings_overlap) — 보는 창 보유일마다 이름 겹침 · 비중 겹침 · 다름(종목 집합 또는 비중) · 한쪽에만 있는 보유일은 따로 센다
rc_holdings_overlap <- function(H_var, H_rx0, tau) {
  tau <- as.Date(tau)
  pick <- function(H) { H <- as.data.table(H); if (!nrow(H) || !all(c("date", "ticker", "w") %in% names(H))) return(data.table(date = as.Date(character(0)), ticker = character(0), w = numeric(0)))
                        H[is.finite(w) & w > 0 & as.Date(date) <= tau, .(w = sum(w)), by = .(date = as.Date(date), ticker = as.character(ticker))] }
  hv <- pick(H_var); hr <- pick(H_rx0)
  if (!nrow(hv) || !nrow(hr)) return(list(status = "unmeasured", n_dates = 0L, n_differ = NA_integer_))
  dv <- sort(unique(hv$date)); dr <- sort(unique(hr$date)); dd <- dv[dv %in% dr]
  if (!length(dd)) return(list(status = "unmeasured", n_dates = 0L, n_differ = NA_integer_, n_only_variant = length(dv), n_only_rx0 = length(dr)))
  P <- rbindlist(lapply(as.list(dd), function(d) {
    a <- hv[date == d]; b <- hr[date == d]; u <- union(a$ticker, b$ticker)
    wa <- setNames(a$w, a$ticker)[u]; wa[is.na(wa)] <- 0; wb <- setNames(b$w, b$ticker)[u]; wb[is.na(wb)] <- 0
    data.table(date = d, n_var = nrow(a), n_rx0 = nrow(b), name_overlap = length(intersect(a$ticker, b$ticker)) / max(nrow(a), nrow(b)),
               weight_overlap = sum(pmin(wa / sum(wa), wb / sum(wb))), differ = !setequal(a$ticker, b$ticker) || any(wa != wb))
  }))
  list(status = "ok", n_dates = nrow(P), n_differ = sum(P$differ), share_differ = mean(P$differ),
       n_only_variant = sum(!(dv %in% dr)), n_only_rx0 = sum(!(dr %in% dv)),
       name_overlap_mean = mean(P$name_overlap), name_overlap_median = stats::median(P$name_overlap), name_overlap_min = min(P$name_overlap),
       weight_overlap_mean = mean(P$weight_overlap), weight_overlap_median = stats::median(P$weight_overlap), weight_overlap_min = min(P$weight_overlap),
       window = c(format(min(P$date)), format(max(P$date))), per_date = P)
}
## 처치 전달 — 출처: P2R04 L478 — 보는 창 보유가 RX0 와 다른 보유일 ≥ 1(무처치 = 미시험)
rc_treatment_delivered <- function(ov) identical(ov$status, "ok") && isTRUE(ov$n_differ > 0L)
## 산출물 읽기 — 출처: P2R04 L1043-1050 = P2R03 L422-428 = P3R03 L295-301
rc_read_holdings <- function(dir) {
  x <- fread(file.path(dir, "04_holdings.csv"), colClasses = list(character = "ticker"))
  x[, date := as.Date(date)]; x[, w := as.numeric(get(intersect(c("target_weight", "actual_weight"), names(x))[1]))]; x
}
rc_read_lines <- function(p) if (length(p) == 1L && !is.na(p) && file.exists(p)) readLines(p, warn = FALSE, encoding = "UTF-8") else character(0)
rc_pk_read <- function(X, code, sub = "visible") {
  p <- file.path(X$res, code, sub, "diagnosis_packet.json"); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL
}
## 보는 창 패킷 만들기 — 출처: P2R04 L1051-1055(p2_pk_build) = P2R03 L429-433 = P3R03 L302-306 · 원자료는 처음 필요할 때 한 번(rc_raw_get)
##   MC8 메모가 켜져 있으면 원자료 판(attr rc_raw_key)을 이 호출 동안만 알린다(판을 모르는 원자료 = 메모 안 함)
rc_pk_build <- function(X, spec_path, art, od) {
  raw <- rc_raw_get(X)
  t0 <- Sys.time()
  .RCM$cur_raw_key <- attr(raw, "rc_raw_key"); on.exit(.RCM$cur_raw_key <- NULL, add = TRUE)
  v <- dp_build(art, root = X$root, cell_spec = file.path(X$root, spec_path), raw = raw, bcfg = X$env$BCFG_L)
  dp_write(v, od)
  .rc_perf_note(X, "packet_build", t0)
  fromJSON(file.path(od, "diagnosis_packet.json"), simplifyVector = FALSE)
}
## 엔진 자체 β-통제 알파(보는 창) — 출처: P2R04 L1057-1063 = P2R03 L435-441 = P3R03 L308-314
rc_eng_alpha <- function(X, dir) {
  E <- X$env$E; rd <- .dp_read(E, dir); mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
  D <- merge(mon(rd$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(rd$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")
  D <- D[ym <= format(X$tau, "%Y-%m")]
  a <- tryCatch(beta_controlled_alpha(D$s, D$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
  list(alpha_ann = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, n = a$n %||% NA_integer_)
}
## 데이터 지문 — 출처: P2R04 L873-878(p2_fingerprint · p2_fp_same) · script = 지문 스크립트 경로(라운드 fingerprint.sh 또는 코어 v1/fingerprint.sh)
rc_fingerprint <- function(script, mode = "equality", args = character(0)) {
  o <- tryCatch(suppressWarnings(system2(qv_bash(), c(shQuote(script), mode, args), stdout = TRUE, stderr = TRUE)),
                error = function(e) paste("error:", conditionMessage(e)))
  paste(o, collapse = "|")
}
rc_fp_same <- function(a, b) identical(unname(as.character(a)), unname(as.character(b)))
## 사전등록 핀 재대조(구 라운드 형식 operational_pins) — 출처: P2R04 L831-871(p2_pin_mismatches · 대조 함수 없는 핀 종류 = 불일치) ·
##   P2R03 L322-349 · P3R03 L250-272 는 그 부분집합(종류 검사 · 팩터 레지스트리 없음 — 같은 사전등록에서 같은 판정)
RC_LEGACY_PIN_KINDS <- c("files", "catalog_entries", "overlay_arms", "factor_registry_entries", "packages", "r_version")
rc_legacy_pin_mismatches <- function(pre, root, kinds = RC_LEGACY_PIN_KINDS, catalog_label = "비중 카탈로그 엔트리") {
  md5 <- function(f) unname(as.character(tools::md5sum(file.path(root, f))))
  cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  bad <- character(0)
  for (c0 in pre[["cells"]]) if (!identical(md5(c0[["path"]]), c0[["md5"]])) bad <- c(bad, paste("사양 md5:", c0[["code"]]))
  op <- pre[["operational_pins"]]
  if (is.null(op)) return(c(bad, "운영 핀 없음"))
  unk <- if (is.null(kinds)) character(0) else setdiff(names(op), kinds)   # kinds = NULL — 종류 검사 없음(P2R03 · P3R03 판)
  if (length(unk)) bad <- c(bad, paste("대조 함수 없는 운영 핀 종류(침묵 통과 금지):", paste(unk, collapse = ",")))
  for (f in op[["files"]]) if (!identical(md5(f[["path"]]), f[["md5"]])) bad <- c(bad, paste("운영 경로 md5:", f[["path"]]))
  if (length(op[["catalog_entries"]])) {
    wc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries, error = function(e) list())
    for (pin in op[["catalog_entries"]]) {
      ent <- Filter(function(z) identical(z$catalog_id, pin[["catalog_id"]]), wc)
      if (!length(ent) || !identical(ent[[1]]$status, pin[["status"]]) || !identical(cj(ent[[1]]$resolver), cj(pin[["resolver"]])))
        bad <- c(bad, paste0(catalog_label, ": ", pin[["catalog_id"]]))
    }
  }
  if (length(op[["overlay_arms"]])) {
    oc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)$arms, error = function(e) list())
    for (pin in op[["overlay_arms"]]) {
      ent <- Filter(function(z) identical(z$id, pin[["id"]]), oc)
      if (!length(ent) || !identical(cj(ent[[1]]), cj(pin[["entry"]]))) bad <- c(bad, paste("오버레이 카탈로그 arm:", pin[["id"]]))
    }
  }
  FRC <- list()
  for (pin in op[["factor_registry_entries"]]) {
    fp <- pin[["path"]] %||% ".cache/factor_db/factor_registry.json"
    if (is.null(FRC[[fp]])) FRC[[fp]] <- tryCatch(jsonlite::fromJSON(file.path(root, fp), simplifyVector = FALSE), error = function(e) list())
    ent <- FRC[[fp]][[pin[["id"]] %||% ""]]
    if (is.null(ent) || !identical(cj(ent), cj(pin[["entry"]]))) bad <- c(bad, paste("팩터 레지스트리 엔트리:", pin[["id"]] %||% "?"))
  }
  for (pk in names(op[["packages"]])) {
    v <- tryCatch(as.character(utils::packageVersion(pk)), error = function(e) NA_character_)
    if (!identical(v, op[["packages"]][[pk]])) bad <- c(bad, paste(pk, "판"))
  }
  if (!identical(R.version.string, op[["r_version"]])) bad <- c(bad, "R 판")
  for (f in pre[["evaluation"]][["files"]] %||% list()) if (!identical(md5(f[["path"]]), f[["md5"]])) bad <- c(bad, paste("평가 경로 md5:", f[["path"]]))
  if (!is.null(pre[["behavior_card_cfg"]]) && !identical(md5(pre[["behavior_card_cfg"]][["path"]]), pre[["behavior_card_cfg"]][["md5"]])) bad <- c(bad, "행동 카드 설정 사본 md5")
  bad
}

## ── 라운드 판정 집계(판정 칸 수 표기) ─────────────────────────────────────────────────────
## 판정어별 칸 수 — 출처: P2R04 L613-618(p2_verdict_counts) · vocab = 사전 고정 판정어 순서 · short = 짧은 이름
rc_verdict_counts <- function(v, vocab, short) {
  v <- as.character(v[!is.na(v)])
  if (!length(v)) return("")
  k <- c(intersect(vocab, unique(v)), setdiff(unique(v), vocab))
  paste(vapply(k, function(z) sprintf("%s %d", if (z %in% names(short)) short[[z]] else z, sum(v == z)), character(1)), collapse = " · ")
}
## 라운드 판정 — 출처: P2R04 L619-631(p2_round_verdict · 판정어별 칸 수 라벨) = P2R03 L274-284 · P3R03 L228-238(verdict 열 없음 → 칸 수만 · unit = method)
##   단위(장치 · 방법) × 엔진 표(tested · pass · excluded) · supported = 두 엔진 통과 ∧ 제외 아님 ≥ 1 · label = '판정(판정 칸/전체 칸[ · 판정어별 칸 수])'
rc_round_verdict <- function(TB, unit = "device", vocab = NULL, short = NULL, counts_field = !is.null(vocab)) {
  nt <- nrow(TB); nj <- if (nt) sum(TB$tested) else 0L
  vc <- if (nt && "verdict" %in% names(TB) && !is.null(vocab)) rc_verdict_counts(TB$verdict, vocab, short) else ""
  lab <- function(v) if (nzchar(vc)) sprintf("%s(판정 %d/%d · %s)", v, as.integer(nj), as.integer(nt), vc) else sprintf("%s(판정 %d/%d)", v, as.integer(nj), as.integer(nt))
  base <- function(v, both, one, exc) {
    r <- list(verdict = v, label = lab(v), n_judged = nj, n_total = nt, both = both, one = one, excluded = exc)
    if (isTRUE(counts_field)) r$verdict_counts <- vc
    r
  }
  if (!nt || !any(TB$tested)) return(base("untested", character(0), character(0), character(0)))
  if (!"excluded" %in% names(TB)) TB[, excluded := FALSE]
  agg <- TB[, .(n_pass = sum(tested & pass), ex = any(excluded & pass)), by = c(unit)]
  both <- agg[n_pass == 2L & !ex][[unit]]; one <- agg[n_pass == 1L][[unit]]; exc <- agg[n_pass == 2L & ex][[unit]]
  v <- if (length(both)) "supported" else if (length(one) || length(exc)) "partial" else "falsified"
  base(v, both, one, exc)
}
## 최종 선택 — 출처: P2R04 L633-646(p2_select) = P2R03 L286-300 — 검증 단위 중 보는 창 S 의 RX0 대비 증분(두 엔진 평균) 최대 1개 ·
##   동률(최대와의 차 < tie)이면 ③ · ④ 비율 합(두 엔진 평균) · tie = 부동소수 여유(결정 수치 아님)
rc_select <- function(xs_by_device, tie = 1e-12) {
  if (!length(xs_by_device)) return(list())
  sc <- lapply(names(xs_by_device), function(dv) {
    xs <- xs_by_device[[dv]]
    list(device = dv, dS = mean(vapply(xs, function(x) as.numeric(x$non_inferiority$S - x$non_inferiority$S_rx0), numeric(1))),
         r34 = mean(vapply(xs, function(x) as.numeric((x$rules$beta_deep$share %||% NA) + (x$rules$fast$share %||% NA)), numeric(1))))
  })
  dS <- vapply(sc, `[[`, numeric(1), "dS"); r34 <- vapply(sc, `[[`, numeric(1), "r34")
  top <- is.finite(dS) & (max(dS, na.rm = TRUE) - dS) < tie
  o <- order(!top, -ifelse(top, r34, dS), -dS)
  sc <- sc[o]
  if (sum(top) >= 2L) sc[[1]]$tie_break <- "r34"
  sc
}

## ── 짝 평가 골격(라운드 훅) ───────────────────────────────────────────────────────────
##   T(템플릿) = list(name, unit_field("device"|"method"), init(ctx, opts) → out, untested(out, why) → out, stages = list(function(S) …), cfg, hooks)
##   단계 함수는 S(환경 — X · T · ctx · opts · out · 중간값)를 받아 계속이면 NULL, 미시험이면 사유 문자열을 돌려준다(실패 의미 사전 고정 — 그 칸만 미시험).
##   ctx = list(engine, unit, cm(변형 칸), cr(RX0 칸), em(변형 칸 평가), er(RX0 칸 평가)) · X = list(root · res(읽기) · out(쓰기) · env(E · BCFG_L · raw · liq) · fs · tau · ea)
##   단계 밖 예기치 않은 오류 = rc_pair_run_safe 가 그 칸만 '평가 오류'로 접는다(라운드 판정은 계속 — 출처 P2R04 L1280-1283 · P3R03 L462-465)
rc_pair_run <- function(X, T, ctx, opts = list()) {
  S <- new.env(parent = emptyenv())
  S$X <- X; S$T <- T; S$ctx <- ctx; S$opts <- opts
  S$out <- T$init(ctx, opts)
  for (st in T$stages) {
    why <- st(S)
    if (!is.null(why)) return(T$untested(S$out, why))
  }
  S$out
}
rc_pair_run_safe <- function(X, T, ctx, opts = list())
  tryCatch(rc_pair_run(X, T, ctx, opts),
           error = function(e) T$untested(T$init(ctx, opts), paste("평가 오류:", conditionMessage(e))))

## 실행 시간 메모(라운드 실행기가 X$perf 환경을 주면 단계별 누적 · 없으면 아무것도 안 한다)
.rc_perf_note <- function(X, what, t0) {
  pf <- X[["perf"]]
  if (is.environment(pf)) pf[[what]] <- (pf[[what]] %||% 0) + as.numeric(difftime(Sys.time(), t0, units = "secs"))
  invisible(NULL)
}

## ── 공용 단계 ──────────────────────────────────────────────────────────────────────
## 평가 상태 — 출처: P2R04 L1069-1070 = P2R03 L447-448 = P3R03 L320-321
rc_st_status <- function(S) {
  em <- S$ctx$em; er <- S$ctx$er
  if (!identical(em$status, "evaluated") || !identical(er$status, "evaluated"))
    return(sprintf("평가 상태 %s · %s", em$status %||% "NA", er$status %||% "NA"))
  NULL
}
## 실효 시작(칸 평가 기록) — 출처: P2R04 L1091-1095 = P2R03 L461-465
rc_st_effective_start <- function(S) {
  E <- S$X$env$E
  S$dm <- E$ta_resolve_artifact(S$ctx$em$artifacts)$dir; S$dr <- E$ta_resolve_artifact(S$ctx$er$artifacts)$dir
  S$esm <- S$ctx$em$effective_start; S$esr <- S$ctx$er$effective_start
  S$out$effective_start <- list(variant = S$esm, rx0 = S$esr)
  if (!identical(S$esm$status, "ok") || !identical(S$esr$status, "ok"))
    return(sprintf("실효 시작 상태 %s · %s", S$esm$status %||% "NA", S$esr$status %||% "NA"))
  NULL
}
## 실효 시작(산출물 authoritative_remeasure.json) — 출처: P3R03 L328-333
rc_st_effective_start_auth <- function(S) {
  E <- S$X$env$E
  S$dm <- E$ta_resolve_artifact(S$ctx$em$artifacts)$dir; S$dr <- E$ta_resolve_artifact(S$ctx$er$artifacts)$dir
  es <- function(d) tryCatch(fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE)$measurement_axis$effective_start, error = function(e) NULL)
  S$esm <- es(S$dm); S$esr <- es(S$dr)
  S$out$effective_start <- list(variant = S$esm[c("status", "date")], rx0 = S$esr[c("status", "date")])
  if (!identical(S$esm$status, "ok") || !identical(S$esr$status, "ok"))
    return(sprintf("실효 시작 상태 %s · %s", S$esm$status %||% "NA", S$esr$status %||% "NA"))
  NULL
}
## 공통 창 시작 — 실효 시작이 같으면 원 산출 · 다르면 늦게 시작한 칸의 첫 기간수익일(리허설 force_start)
.rc_common_start <- function(S) {
  if (!is.null(S$opts[["force_start"]])) return(as.Date(S$opts[["force_start"]]))
  late <- if (as.Date(S$esm$date) > as.Date(S$esr$date)) S$dm else S$dr
  min(as.Date(fread(file.path(late, "03_period_returns.csv"))$date))
}
## 창(사본만 · 패킷은 다음 단계) — 출처: P2R04 L1096-1113(공통 창 사본 · 상위 폴더 표식 · 실패 = '공통 창 실패')
rc_st_window <- function(S) {
  X <- S$X; cm <- S$ctx$cm; cfg <- S$T$cfg
  S$common <- !is.null(S$opts[["force_start"]]) || !identical(S$esm$date, S$esr$date)
  W <- tryCatch({
    if (!S$common) list(sub = "original", window = "original", am = S$dm, ar = S$dr)
    else {
      cs0 <- .rc_common_start(S)
      sub <- paste0("common_", format(cs0, "%Y%m%d")); base <- file.path(X$out, cm$code, sub)
      am <- file.path(base, "artifacts"); ar <- file.path(base, "rx0_artifacts")
      mk <- isTRUE(cfg[["mark_full"]]); mn <- isTRUE(X[["minimal_copy"]])
      tr <- list(variant = rc_trim_artifacts(S$dm, am, cs0, mark = mk, minimal = mn, errtag = cfg[["trim_errtag"]] %||% "p2_trim"),
                 rx0 = rc_trim_artifacts(S$dr, ar, cs0, mark = mk, minimal = mn, errtag = cfg[["trim_errtag"]] %||% "p2_trim"))
      if (mk) rc_mark_full(base, RC_FULL_MARK_PARENT)
      list(sub = sub, window = paste0("common_from_", format(cs0)), am = am, ar = ar, base = base, trim = tr)
    }
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(W$error)) return(paste("공통 창 실패:", W$error))
  S$W <- W; S$out$window <- W$window; S$out$trim <- W$trim
  S$am <- W$am; S$ar <- W$ar
  NULL
}
## 보는 창 패킷(원 창 = 칸 평가 패킷 · 공통 창 = 사본에 같은 계약) — 출처: P2R04 L1121-1128
rc_st_packets <- function(S) {
  X <- S$X; cm <- S$ctx$cm; cr <- S$ctx$cr
  P <- tryCatch({
    if (!S$common) list(PM = rc_pk_read(X, cm$code), PRX = rc_pk_read(X, cr$code))
    else list(PM = rc_pk_build(X, .rc_cell_spec(cm), S$am, file.path(S$W$base, "visible")), PRX = rc_pk_build(X, .rc_cell_spec(cr), S$ar, file.path(S$W$base, "visible_rx0")))
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(P$error)) return(paste("보는 창 패킷 실패:", P$error))
  S$PM <- P$PM; S$PRX <- P$PRX
  if (is.null(S$PM) || is.null(S$PRX)) return("보는 창 패킷 없음")
  NULL
}
## 창 + 패킷 한 번에(실패 = '공통 창 · 패킷 실패') — 출처: P2R03 L472-490 = P3R03 L341-358(표식 없음)
rc_st_window_packets <- function(S) {
  X <- S$X; cm <- S$ctx$cm; cr <- S$ctx$cr; cfg <- S$T$cfg
  S$common <- !is.null(S$opts[["force_start"]]) || !identical(S$esm$date, S$esr$date)
  W <- tryCatch({
    if (!S$common) list(sub = "original", window = "original", am = S$dm, ar = S$dr, PM = rc_pk_read(X, cm$code), PRX = rc_pk_read(X, cr$code))
    else {
      cs <- .rc_common_start(S)
      sub <- paste0("common_", format(cs, "%Y%m%d")); base <- file.path(X$out, cm$code, sub)
      am <- file.path(base, "artifacts"); ar <- file.path(base, "rx0_artifacts")
      mn <- isTRUE(X[["minimal_copy"]]); et <- cfg[["trim_errtag"]] %||% "p2_trim"
      tr <- list(variant = rc_trim_artifacts(S$dm, am, cs, mark = FALSE, minimal = mn, errtag = et), rx0 = rc_trim_artifacts(S$dr, ar, cs, mark = FALSE, minimal = mn, errtag = et))
      list(sub = sub, window = paste0("common_from_", format(cs)), am = am, ar = ar, trim = tr,
           PM = rc_pk_build(X, .rc_cell_spec(cm), am, file.path(base, "visible")), PRX = rc_pk_build(X, .rc_cell_spec(cr), ar, file.path(base, "visible_rx0")))
    }
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(W$error)) return(paste("공통 창 · 패킷 실패:", W$error))
  S$W <- W; S$out$window <- W$window; S$out$trim <- W$trim
  S$PM <- W$PM; S$PRX <- W$PRX; S$am <- W$am; S$ar <- W$ar
  if (is.null(S$PM) || is.null(S$PRX)) return("보는 창 패킷 없음")
  NULL
}
## 엔진 알파(엔진 × 창 메모) — 출처: P2R04 L1132-1134 = P2R03 L491-493 = P3R03 L359-361 · X$meta 가 있으면 칸이 쓴 키를 남긴다(샤드 병합의 삽입 순서 재현)
rc_st_engine_alpha <- function(S) {
  X <- S$X; ek <- paste(S$ctx$engine, S$W$sub)
  if (is.null(X$ea[[ek]])) assign(ek, tryCatch(rc_eng_alpha(X, S$ar), error = function(e) list(alpha_ann = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e))), envir = X$ea)
  S$ea <- X$ea[[ek]]
  if (is.environment(X[["meta"]])) X$meta[[S$ctx$cm$code]] <- ek
  NULL
}
## 위기 짝 · 깊은 위기 — 출처: P2R04 L1135-1142 = P2R03 L494-501 = P3R03 L363-371(위기 짝 불일치 · 짝 < 2 = 미시험)
rc_st_crisis_pairs <- function(S) {
  tol <- S$tol
  S$crm <- S$PM$behavior$crises %||% list(); S$crr <- S$PRX$behavior$crises %||% list()
  S$maj <- rc_crisis_majority(S$crm, S$crr, tol, "dd_capture")
  S$deep <- rc_deep_crisis_keys(S$crm, S$crr)
  S$dmj <- rc_crisis_majority(S$crm, S$crr, tol, "dd_capture", subset = S$deep)
  S$out$crisis_pairs <- list(n_pair = S$maj$n_pair, unpaired = S$maj$unpaired, n_deep = S$dmj$n_pair, deep_keys = S$deep)
  if (!identical(as.integer(S$maj$unpaired), 0L)) return(sprintf("위기 짝 불일치 %s(같은 창이면 0)", format(S$maj$unpaired)))
  if (S$maj$n_pair < 2L || S$dmj$n_pair < 2L) return(sprintf("판정 위기 짝 < 2(전체 %d · 깊은 %d)", S$maj$n_pair, S$dmj$n_pair))
  NULL
}
## 판정 상수 — 과반 · tol(사전등록 final_selection_rule) · 역할(판정 · 진단)
rc_st_consts <- function(S) {
  FS <- S$X$fs
  S$MAJ <- as.numeric(FS[["majority_share"]]); S$tol <- as.numeric(FS[["crisis_improve_min"]])
  S$role <- S$opts[["role"]] %||% "judge"; S$diag <- identical(S$role, "diagnostic")
  NULL
}

## ── 원자료 · 시장 패널 메모(계약 파일 무수정 래퍼 · 결과 동일 = 같은 함수 · 같은 입력) ───────────────────
.RCM <- new.env(parent = emptyenv())
## 파일 지문(크기 · 수정 시각) — 캐시 키 입력(재측정 · 갱신 뒤 옛 결과를 쓰지 않게)
.rc_file_fp <- function(p) { fi <- file.info(p); paste(gsub("\\\\", "/", p), fi$size, format(fi$mtime, "%Y-%m-%dT%H:%M:%OS3")) }
rc_cache_dir <- function(root, kind) { d <- file.path(root, ".cache", "round_core", kind); dir.create(d, recursive = TRUE, showWarnings = FALSE); d }
.rc_digest <- function(x) digest::digest(x, algo = "xxhash64", serialize = TRUE)

## 원자료(위생 raw) — mc_load_raw(root, from = "1999-11-01", hygiene = TRUE) 와 같은 결과 · 판 키(attr rc_raw_key)를 붙인다 ·
##   disk = TRUE 면 비압축 RDS 디스크 메모(프로세스 간 재사용 · 샤드 워커가 각자 읽는다).
##   키 = RAWDATA 지문 + 인자 + 위생 판정 계약(measurement_axis.R · constraint_defaults.json · factor_z_standard.R · matched_controls.R) md5.
rc_raw_key <- function(root, from = "1999-11-01", hygiene = TRUE) {
  rp <- file.path(root, ".cache/RAWDATA.parquet")
  deps <- file.path(root, c("02_Infrastructure/contracts/measurement_axis.R", "02_Infrastructure/worktask/constraint_defaults.json",
                            "02_Infrastructure/factor_db/factor_z_standard.R", "02_Infrastructure/contracts/matched_controls.R"))
  .rc_digest(list(raw = .rc_file_fp(rp), from = from, hygiene = hygiene, deps = unname(vapply(deps, function(f) if (file.exists(f)) rc_md5(f) else "absent", ""))))
}
rc_raw_load <- function(root, from = "1999-11-01", hygiene = TRUE, disk = FALSE) {
  key <- rc_raw_key(root, from, hygiene)
  if (!is.null(.RCM$raw_key) && identical(.RCM$raw_key, key)) return(.RCM$raw)
  f <- file.path(rc_cache_dir(root, "raw"), paste0("raw_", key, ".rds"))
  R <- if (isTRUE(disk) && file.exists(f)) { x <- readRDS(f); data.table::setalloccol(x); x } else {
    x <- mc_load_raw(root, from = from, hygiene = hygiene)
    if (isTRUE(disk)) { tmp <- paste0(f, ".tmp", Sys.getpid()); saveRDS(x, tmp, compress = FALSE); if (!file.rename(tmp, f)) unlink(tmp) }
    x
  }
  setattr(R, "rc_raw_key", key)
  .RCM$raw <- R; .RCM$raw_key <- key
  R
}
## X 의 원자료 — 처음 필요할 때 한 번(env 가 환경이면 거기 둔다 · 구판 p2_pk_build 와 같은 시점 · 같은 인자 · 같은 함수 산출)
rc_raw_get <- function(X) {
  if (!is.null(X$env$raw)) return(X$env$raw)
  R <- rc_raw_load(X$root, disk = isTRUE(X[["raw_disk_cache"]]))
  if (is.environment(X$env)) X$env$raw <- R
  R
}

## ta_load_market 메모 — 진단 패킷(.dp_exposure)이 패킷마다 RAWDATA 를 다시 읽는다. 같은 인자(정렬된 보유 종목 · 기간 · 설정) · 같은 파일 지문이면
##   같은 결과다(계약 함수 그대로 호출 · 소비자 ta_build_state 는 사본을 만든다 — 입력을 바꾸지 않는다). 계약 환경(.DP$e)의 바인딩만 감싼다(파일 무수정).
rc_memo_install <- function(E, n_keep = 1L) {   # n_keep = 1 — 연속한 같은 RX0 β 짝 사본이 적중(메모리 · 워커당 시장 패널 1개)
  if (isTRUE(attr(E$ta_load_market, "rc_memo"))) return(invisible(E))
  orig <- E$ta_load_market
  memo <- new.env(parent = emptyenv()); memo$keys <- character(0)
  f <- function(root = NULL, cfg, from, to = NULL, raw_path = NULL, bm_path = NULL, extra_tickers = character(0)) {
    r0 <- E$ta_root(root)
    rp <- raw_path %||% file.path(r0, ".cache/RAWDATA.parquet"); bp <- bm_path %||% file.path(r0, ".cache/benchmark.parquet")
    key <- .rc_digest(list(r0, cfg, as.character(as.Date(from)), if (is.null(to)) NULL else as.character(as.Date(to)), .rc_file_fp(rp), .rc_file_fp(bp),
                           sort(unique(as.character(extra_tickers)))))
    if (!is.null(memo[[key]])) { .RCM$ta_hits <- (.RCM$ta_hits %||% 0L) + 1L; return(memo[[key]]) }
    v <- orig(root = root, cfg = cfg, from = from, to = to, raw_path = raw_path, bm_path = bm_path, extra_tickers = extra_tickers)
    .RCM$ta_miss <- (.RCM$ta_miss %||% 0L) + 1L
    memo[[key]] <- v; memo$keys <- c(memo$keys, key)
    while (length(memo$keys) > n_keep) { rm(list = memo$keys[1], envir = memo); memo$keys <- memo$keys[-1] }
    v
  }
  attr(f, "rc_memo") <- TRUE
  assign("ta_load_market", f, envir = E)
  invisible(E)
}

## 계약 · 설정 판(MC8 메모 키) — 대조 · 행동 카드 · 등급 · 롤링 계약과 그 설정의 md5(하나라도 바뀌면 다시 잰다)
.rc_mc8_deps <- function(root) {
  fs <- c(file.path("02_Infrastructure/contracts", c("matched_controls.R", "behavior_card.R", "grade_v3.R", "rolling_grade.R", "measurement_axis.R")),
          file.path("06_Registry", c("matched_controls.json", "behavior_card.json", "grade_v3.json", "rolling_grade.json")))
  vapply(file.path(root, fs), function(f) if (file.exists(f)) rc_md5(f) else "absent", "", USE.NAMES = FALSE)
}
## MC8 대조 메모(진단 패킷 안의 mc_controls) — 입력 내용 해시(보유 · 수익일 · 벤치 · 설정 · 집행 규약 · 유니버스 · 원자료 판 · 계약 md5) · 경로 · run_id 없음 ·
##   placebo_seed 결정론이라 같은 입력 = 같은 결과. 원자료 판 = rc_pk_build 가 이 호출 동안만 알리는 키(.RCM$cur_raw_key) + 잘린 범위 — 판을 모르면 그대로 호출.
rc_mc_memo_install <- function(E, root) {
  if (isTRUE(attr(E$mc_controls, "rc_memo"))) return(invisible(E))
  orig <- E$mc_controls
  dir <- rc_cache_dir(root, "mc8"); deps <- .rc_mc8_deps(root)
  f <- function(H, pr, br, R, cfg, exec_price, universe) {
    rk <- .RCM$cur_raw_key
    if (is.null(rk)) return(orig(H, pr, br, R, cfg, exec_price, universe))
    key <- .rc_digest(list(v = "mc_controls_v1", H = as.data.frame(H), pr = as.data.frame(pr)[, intersect(names(pr), "date"), drop = FALSE],
                           br = as.data.frame(br)[, intersect(names(br), c("date", "benchmark_ret")), drop = FALSE], cfg = cfg, ep = exec_price, u = universe,
                           raw = rk, rn = nrow(R), rd = range(R$Date), deps = deps))
    p <- file.path(dir, paste0(key, ".rds"))
    if (file.exists(p)) { .RCM$mc_hits <- (.RCM$mc_hits %||% 0L) + 1L; return(readRDS(p)) }
    v <- orig(H, pr, br, R, cfg, exec_price, universe)
    tmp <- paste0(p, ".tmp", Sys.getpid()); saveRDS(v, tmp, compress = FALSE); if (!file.rename(tmp, p)) unlink(tmp)
    .RCM$mc_miss <- (.RCM$mc_miss %||% 0L) + 1L
    v
  }
  attr(f, "rc_memo") <- TRUE
  assign("mc_controls", f, envir = E)
  invisible(E)
}

## MC8 카드(전기간 행동 카드 + 크기 · 노출 짝 대조) 입력 해시 캐시 — mc_card(dir, root, raw, bcfg) 와 같은 결과(strategy_id · source_dir · 시각만 그 칸 것으로).
##   키 = mc_card 가 읽는 판정 입력(03 date · ret_net / 05 date · benchmark_ret / 04 date · ticker · target_weight · 명세 universe · exec_price · 매니페스트 universe_id)
##   + 원자료 판(attr rc_raw_key · 행 수) + 행동 카드 설정 + 벤치 이력 지문 + 계약 · 설정 md5 — run_id · 경로 · 전략 이름 제외(같은 RX0 가 라운드를 건너 재사용된다)
rc_mc_card_cached <- function(dir, root, raw, bcfg = NULL) {
  raw_key <- attr(raw, "rc_raw_key")
  if (is.null(raw_key)) return(mc_card(dir, root = root, raw = raw, bcfg = bcfg))
  rd <- function(n) { p <- file.path(dir, n); if (file.exists(p)) fread(p) else NULL }
  pr <- rd("03_period_returns.csv"); br <- rd("05_benchmark_returns.csv"); H <- rd("04_holdings.csv")
  if (is.null(pr) || is.null(br) || is.null(H)) return(mc_card(dir, root = root, raw = raw, bcfg = bcfg))   # 결손 = 계약이 그대로 멈추게
  rj <- function(n) { p <- file.path(dir, n); if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) list()) else list() }
  spec <- rj("01_strategy_spec.json"); man <- rj("00_manifest.json")
  sel <- function(d, cols) as.data.frame(d)[, intersect(names(d), cols), drop = FALSE]
  key <- .rc_digest(list(v = "mc_card_v1", pr = sel(pr, c("date", "ret_net")), br = sel(br, c("date", "benchmark_ret")),
                         H = sel(H, c("date", "ticker", "target_weight")), uni = spec[["universe"]], uid = man[["universe_id"]], ep = spec[["exec_price"]],
                         raw = raw_key, rn = nrow(raw), bcfg = bcfg, bm = .rc_file_fp(file.path(root, ".cache/benchmark.parquet")), deps = .rc_mc8_deps(root)))
  p <- file.path(rc_cache_dir(root, "mc8_card"), paste0(key, ".rds"))
  sid <- tryCatch(as.character(pr$strategy_id[1]), error = function(e) NA_character_)
  if (file.exists(p)) {
    card <- readRDS(p)
    card$strategy_id <- sid; card$created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    if (!is.null(card$controls$spec)) card$controls$spec$source_dir <- dir
    .RCM$card_hits <- (.RCM$card_hits %||% 0L) + 1L
    return(card)
  }
  card <- mc_card(dir, root = root, raw = raw, bcfg = bcfg)
  tmp <- paste0(p, ".tmp", Sys.getpid()); saveRDS(card, tmp, compress = FALSE); if (!file.rename(tmp, p)) unlink(tmp)
  .RCM$card_miss <- (.RCM$card_miss %||% 0L) + 1L
  card
}

## ── 칸 평가(보는 창 / 사람 쪽 파일 분리 · C-031) — 출처: P2R04 L978-1028(.p2_eval_cell_core · p2_eval_cell) = P2R03 L361-410 ─────────
##   results/<code>/visible/{diagnosis_packet.json, eval_visible.json} · results/<code>/full/{behavior_card.json, eval_full.json, NO_VISIBLE_REVIEW.txt}
##   cache = "legacy"(두 파일이 있으면 그대로 — 구 라운드 저장분 재판정) | "key"(내용 주소 키 eval.key — 산출물 · 칸 사양 · 코어 매니페스트 · 행동 카드 설정 · τ_D)
##   diagnostic_field = TRUE(P2R04 — 칸 기록에 diagnostic 필드) | FALSE(P2R03 판)
rc_cell_join <- function(v, f) c(v, list(test = f$test, full = f$full))
##   write = FALSE(구 라운드 재판정) — 저장분이 없으면 계산해 쓰지 않고 멈춘다(라운드 결과 폴더 무수정)
rc_eval_cell_split <- function(root, res_dir, cell, env, tau, cache = c("key", "legacy"), diagnostic_field = TRUE, audience = RC_FULL_AUDIENCE, tag = "평가", out_dir = NULL,
                               write = TRUE) {
  cache <- match.arg(cache)
  od <- out_dir %||% file.path(res_dir, cell[["code"]])
  fv <- file.path(od, "visible", "eval_visible.json"); ff <- file.path(od, "full", "eval_full.json"); fk <- file.path(od, "eval.key")
  rj <- file.path(res_dir, paste0(cell[["code"]], ".json"))
  if (identical(cache, "legacy") && file.exists(fv) && file.exists(ff)) return(rc_cell_join(fromJSON(fv, simplifyVector = FALSE), fromJSON(ff, simplifyVector = FALSE)))
  if (!file.exists(rj)) return(list(code = cell[["code"]], status = "not_measured"))
  r <- fromJSON(rj, simplifyVector = FALSE)
  if (!isTRUE(r$ok)) return(list(code = cell[["code"]], status = "measure_failed", err = r$err %||% NA))
  sp <- .rc_cell_spec(cell)
  key <- if (identical(cache, "key")) rc_eval_key(r$artifacts, if (!is.null(sp)) file.path(root, sp) else NULL, env$bcfg_md5, tau) else NULL
  if (!is.null(key) && file.exists(fv) && file.exists(ff) && file.exists(fk) && identical(readLines(fk, warn = FALSE)[1], key))
    return(rc_cell_join(fromJSON(fv, simplifyVector = FALSE), fromJSON(ff, simplifyVector = FALSE)))
  if (!isTRUE(write)) stop("저장된 칸 평가가 없다(쓰기 금지 모드 — 재판정은 칸 평가를 새로 쓰지 않는다): ", cell[["code"]])
  dir.create(file.path(od, "visible"), recursive = TRUE, showWarnings = FALSE); dir.create(file.path(od, "full"), recursive = TRUE, showWarnings = FALSE)
  raw <- rc_raw_get(list(root = root, env = env, raw_disk_cache = isTRUE(env$raw_disk_cache)))
  t0 <- Sys.time()
  ax <- rc_axis_audit(root, r$artifacts)
  .RCM$cur_raw_key <- attr(raw, "rc_raw_key"); on.exit(.RCM$cur_raw_key <- NULL, add = TRUE)
  vis <- dp_build(r$artifacts, root = root, cell_spec = file.path(root, sp), raw = raw, bcfg = env$BCFG_L)
  dp_write(vis, file.path(od, "visible"))
  card <- if (isTRUE(env$mc8_cache)) rc_mc_card_cached(r$artifacts, root, raw, env$BCFG_L) else mc_card(r$artifacts, root = root, raw = raw, bcfg = env$BCFG_L)
  mc_write(card, file.path(od, "full"), root = root)
  tp <- tryCatch(rc_test_perf(env$E, root, r$artifacts, tau), error = function(e) list(status = paste("error:", conditionMessage(e))))
  ar <- fromJSON(file.path(r$artifacts, "authoritative_remeasure.json"), simplifyVector = FALSE)
  g <- function(p) rc_getf(vis, p)
  vw <- list(window = vis$window, uc = g("behavior.summary.bull_up_capture_median"), dc = g("behavior.summary.crisis_cum_capture_median"),
             dc_strong = g("behavior.dc_strong_max"), cagr = g("performance.strategy.cagr"), calmar = g("performance.strategy.calmar"),
             port_t = g("performance.strategy.port_t"), mdd = g("performance.strategy.mdd"), sharpe = g("performance.strategy.sharpe"),
             cdar = g("behavior.stats.cdar"), beta = g("behavior.stats.beta"), beta_down = g("behavior.stats.beta_down"), beta_up = g("behavior.stats.beta_up"),
             dd_capture_median = g("behavior.summary.crisis_dd_capture_median"), dd_capture_worst = g("behavior.summary.crisis_dd_capture_worst"),
             n_crisis = g("behavior.summary.n_crisis"), n_bull = g("behavior.summary.n_bull"), verdict = vis$behavior$verdict,
             attribution = vis$controls$attribution$label %||% NA, exposure_mean = g("controls.exposure_profile.mean"),
             turnover_annual = g("profile.turnover_annual"), cost_drag_annual = g("profile.cost_drag_annual"))
  head <- list(code = cell[["code"]], engine = cell[["engine"]] %||% NA, component = cell[["component"]] %||% NA)
  if (isTRUE(diagnostic_field)) head$diagnostic <- isTRUE(cell[["diagnostic"]])
  v <- c(head, list(status = if (isTRUE(ax$ok)) "evaluated" else "axis_violation", artifacts = r$artifacts, axis = ax,
                    effective_start = ar$measurement_axis$effective_start[c("status", "date")], visible = vw,
                    eval_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  f <- list(code = cell[["code"]], audience = audience,
            test = list(uc = card$test$bull_up_capture_median %||% NA, dc = card$test$crisis_cum_capture_median %||% NA,
                        n_bull = card$test$n_bull %||% NA, n_crisis = card$test$n_crisis %||% NA, verdict = card$test$verdict %||% NA,
                        dc_strong = card$dc_strong_max %||% NA, perf = tp),
            full = list(grade = ar$essence_grade, S = ar$grade_v3$S %||% NA, cr = card$overall$verdict, attribution = card$controls$attribution$overall$label %||% NA,
                        cdar = card$stats$cdar %||% NA, effective_start = ar$measurement_axis$effective_start$date %||% NA))
  writeLines(toJSON(f, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ff, useBytes = TRUE)
  writeLines(toJSON(v, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), fv, useBytes = TRUE)
  writeLines(audience, file.path(od, "full", RC_FULL_MARK), useBytes = TRUE)
  if (!is.null(key)) writeLines(key, fk, useBytes = TRUE)
  cat(sprintf("[%s] %s — 보는 창 UC %.3f · DC %.3f · CAGR %.3f · CDaR %.3f · 귀속 %s · 축 %s · %.0f초\n", tag, cell[["code"]], vw$uc, vw$dc,
              vw$cagr, vw$cdar, vw$attribution, ax$ok, v$eval_seconds))
  rc_cell_join(v, f)
}
## 칸 평가 안전 호출 — 출처: P2R04 L981-984 — 그 칸만 eval_error(오류 문구의 τ_D 이후 날짜는 가린다)
rc_eval_cell_split_safe <- function(root, res_dir, cell, env, tau, ...)
  tryCatch(rc_eval_cell_split(root, res_dir, cell, env, tau, ...),
           error = function(e) { cat(sprintf("[평가] %s — 칸 평가 오류: %s\n", cell[["code"]], .rc_redact_chr(conditionMessage(e), as.Date(tau))))
                                 list(code = cell[["code"]], status = "eval_error", err = conditionMessage(e)) })

## 칸 평가 캐시 = 현 측정 산출물 단정 — 출처: P2R04 L1312-1316 = P2R03 L659-663 = P3R03 L489-493
rc_assert_eval_artifacts <- function(EVS, res_dir, tag) {
  for (cd in names(EVS)) if (!is.null(EVS[[cd]]$artifacts)) {
    rj <- file.path(res_dir, paste0(cd, ".json"))
    a0 <- if (file.exists(rj)) fromJSON(rj, simplifyVector = FALSE)$artifacts else NULL
    if (!identical(EVS[[cd]]$artifacts, a0)) stop(sprintf("[%s] %s 칸 평가 캐시의 산출물 ≠ 현 측정 산출물 — results/%s/ 를 지우고 다시 평가", tag, cd, cd))
  }
  invisible(TRUE)
}
## 측정 연기 칸 — 출처: P2R04 L1322-1324
rc_deferred_cells <- function(cells, res_dir) Filter(function(cl) { j <- file.path(res_dir, paste0(cl[["code"]], ".json")); if (!file.exists(j)) return(FALSE)
                                                                    r <- fromJSON(j, simplifyVector = FALSE); !isTRUE(r$ok) && !is.null(r$deferred) }, cells)
## 측정 지문 — 출처: P2R04 L1325(fp_of)
rc_fp_of <- function(res_dir, code, tag) { f <- file.path(res_dir, sprintf("%s.fp_%s", code, tag)); if (file.exists(f)) paste(readLines(f, warn = FALSE), collapse = "|") else NA_character_ }

## ── 샤딩(최종 판정의 짝 평가) — 칸 목록을 교차 배정(round_kit rk_shard 와 같은 규칙) · 병합 순서 고정 ───────────────────
rc_shard_index <- function(n, shard) {
  if (is.null(shard)) return(seq_len(n))
  v <- suppressWarnings(as.integer(strsplit(shard, "/", fixed = TRUE)[[1]]))
  if (length(v) != 2L || anyNA(v) || v[2] < 1L || v[1] < 1L || v[1] > v[2]) stop("[round_core] shard=i/K 형식 오류: ", shard)
  which((seq_len(n) - 1L) %% v[2] == (v[1] - 1L))
}
## 짝 결과 저장 · 읽기(샤드 워커 → 병합) — RDS(비압축 · 같은 R 객체 그대로 · JSON 왕복 없음)
rc_pair_save <- function(dir, code, x) { dir.create(dir, recursive = TRUE, showWarnings = FALSE); p <- file.path(dir, paste0(code, ".rds"))
                                         tmp <- paste0(p, ".tmp"); saveRDS(x, tmp, compress = FALSE); file.rename(tmp, p); invisible(p) }
rc_pair_load <- function(dir, code) { p <- file.path(dir, paste0(code, ".rds")); if (file.exists(p)) readRDS(p) else NULL }
## 엔진 알파 메모 병합 — 샤드마다 다른 칸이 먼저 계산했어도, 전체 칸 순서로 '없으면 넣기'를 다시 하면 단일 프로세스와 같은 삽입 순서 · 같은 값이다
rc_ea_replay <- function(order_codes, metas, values) {
  ea <- new.env()
  for (cd in order_codes) { ek <- metas[[cd]]; if (!is.null(ek) && is.null(ea[[ek]]) && !is.null(values[[ek]])) assign(ek, values[[ek]], envir = ea) }
  ea
}
