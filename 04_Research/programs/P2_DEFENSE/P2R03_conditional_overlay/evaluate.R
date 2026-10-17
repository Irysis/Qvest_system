## P2R03 평가 — 조건부 · 시변 노출 층 7종 × 엔진 2(E2 DNN 원형 EW · E3 B6_36 엔트로피 비중) vs 같은 배치 엔진 자체 구성 RX0 →
##   사전등록 규칙(stage_artifacts prereg.json rules)을 기계 적용(R2). 수치는 전부 R 계약 산출(dp_build 보는 창 패킷 · mc_card · rk_S ·
##   rk_pair_alpha · beta_controlled_alpha — 손계산 없음 · AX-008). 이 파일이 더하는 것은 규칙 적용 · 공통 창 사본 · β 짝 사본 · 빠른 급락
##   분류(같은 칸 산출물의 벤치 일수익) · 기록 파싱뿐.
##   도우미 = P3R03 evaluate.R(픽스처 22 · 리허설 통과판)을 이어받고, 헌장 빈칸 6~8(β 짝 판정 · 빠른 급락 · 강세 구간별)과
##   lag-1 진단 · 결과 파일 분리(C-031 — 보는 창 / 사람 쪽) · 지문 비교 수리(P3R03 eval_matches_measure 오표시 = 이름 붙은 벡터)를 더했다.
## 실행: Rscript evaluate.R [--cells-only] [--shard=i/K]      (측정 = measure.sh · 리허설 = rehearse.R · 픽스처 = evaluate_fixture.R)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## 장치 → 오버레이 층(카탈로그 arm) — 사양 · 등록 · 판정이 같은 표를 쓴다
P2R03_DEVICES <- list(
  D1 = list(kind = "dbeta_tilt",          arm_id = "dbeta_tilt_rank", name = "낙폭 국면 × 하방베타 순위 축소(횡단면)"),
  D2 = list(kind = "gen_20260903_133452", arm_id = "csd_idio_tilt",   name = "횡단면분산 국면 × 특이변동 순위 축소(횡단면)"),
  D3 = list(kind = "turbulence",          arm_id = "turbulence",      name = "벤치 상태 벡터 거리 게이트(마할라노비스 · 스칼라)"),
  D4 = list(kind = "ml_tail_gate",        arm_id = "ml_tail_gate",    name = "확장창 로지스틱 꼬리 확률 게이트(노출 = 1 − p̂ · 분포 표적)"),
  D5 = list(kind = "ts_mom_gate",         arm_id = "ts_mom_sign",     name = "추세 현금(시장 12개월 수익 < 0 → 현금 · 재시험)"),
  D6 = list(kind = "dd_brake",            arm_id = "dd_brake_q",      name = "낙폭 브레이크(낙폭 중앙~90분위 선형 축소 · 재시험)"),
  D7 = list(kind = "dd_recovery",         arm_id = "dd_recovery",     name = "낙폭 국면 재진입 게이트(직전 1개월 시장 상승이면 노출 유지 · 재시험 · 철학 P1 C-045)"))
P2R03_FULL_AUDIENCE <- "사람 쪽 판정 전용(τ_D 2022-12-31 이후 · 전기간 포함) — 보는 창 리뷰어(철학 P1 · P2 · P4 · 판단 Superfan · 처방 레인) 열람 금지(C-031)"

## ── 순수 도우미(픽스처 검사 대상 · 계약 호출 없음) ─────────────────────────────
.p2_rows_dt <- function(x) if (is.data.frame(x)) as.data.table(x) else if (!length(x)) data.table() else
  rbindlist(lapply(x, function(r) as.data.table(lapply(r, function(v) if (is.null(v) || !length(v)) NA else v[[1]]))), fill = TRUE)
.p2_key <- function(x) paste(as.character(x$peak_date), as.character(x$trough_date))
## 공통 창 사본 — P3R03 p3_trim_artifacts 와 같다(02 · 03 · 05 는 start 이후 · 04 는 start 이하 마지막 리밸부터 · NAV · 벤치 재기준 · 나머지 복사)
p2_trim_artifacts <- function(src_dir, out_dir, start) {
  start <- as.Date(start)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(src_dir, full.names = TRUE)) if (!dir.exists(f) && !grepl("^0[2-5]_.*[.]csv$", basename(f))) file.copy(f, out_dir, overwrite = TRUE)
  rd <- function(n, tick = FALSE) { p <- file.path(src_dir, n)
                                    x <- if (tick) fread(p, colClasses = list(character = "ticker")) else fread(p)
                                    x[, date := as.Date(date)]; x }
  pr <- rd("03_period_returns.csv")[date >= start]
  br <- rd("05_benchmark_returns.csv")[date >= start]
  nv <- rd("02_nav.csv")[date >= start]
  H  <- rd("04_holdings.csv", tick = TRUE)
  h0 <- suppressWarnings(max(H$date[H$date <= start]))
  H  <- H[date >= (if (is.finite(h0)) h0 else start)]
  if (!nrow(pr) || !nrow(nv) || !nrow(br)) stop("[p2_trim] start ", format(start), " 이후 행이 없다: ", src_dir)
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
  invisible(list(start = start, holdings_from = if (is.finite(h0)) h0 else start, n_pr = nrow(pr)))
}
## β 짝 사본(헌장 빈칸 8 · P3R03 p3_beta_scaled_copy 그대로) — 기준 칸의 기간수익 · NAV 를 k(< 1)배 노출로(잔여 1−k = 현금 · 수익 0) ·
##   보유 비중도 k 배 · 벤치 · 나머지 파일은 그대로. 같은 계약(dp_build)으로 패킷을 만들어 'β 만 낮춘 기준'과 비교한다.
p2_beta_scaled_copy <- function(src_dir, out_dir, k) {
  if (!is.finite(k) || k <= 0 || k > 1) stop("[p2_beta] k 는 (0, 1]: ", k)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(src_dir, full.names = TRUE)) if (!dir.exists(f) && !grepl("^0[234]_.*[.]csv$", basename(f))) file.copy(f, out_dir, overwrite = TRUE)
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
  invisible(list(k = k, n_pr = nrow(pr)))
}
## 위기 짝 과반 — metric 이 기준 − tol 보다 낮은 위기의 비율 · subset = 판정에 쓸 위기 키(NULL = 짝 전부) — P3R03 그대로
p2_crisis_majority <- function(cr_m, cr_r, tol, metric = "dd_capture", subset = NULL) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !(metric %in% names(cm)) || !(metric %in% names(cr)))
    return(list(n_pair = 0L, n_better = 0L, share = NA_real_, unpaired = nrow(cm) + nrow(cr)))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  J <- merge(cm[, .(k, m = as.numeric(get(metric)))], cr[, .(k, r = as.numeric(get(metric)))], by = "k")
  unp <- (nrow(cm) - nrow(J)) + (nrow(cr) - nrow(J))
  if (!is.null(subset)) J <- J[k %in% subset]
  J <- J[is.finite(m) & is.finite(r)]
  nb <- sum(J$m < J$r - tol)
  list(n_pair = nrow(J), n_better = nb, share = if (nrow(J)) nb / nrow(J) else NA_real_, unpaired = unp, per_crisis = J)
}
## 깊은 위기 — 두 칸 모두에 있는 위기 중 벤치 낙폭(bm_dd) 크기가 그 집합 중앙값 이상인 위기의 키 — P3R03 그대로
p2_deep_crisis_keys <- function(cr_m, cr_r) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("bm_dd" %in% names(cr))) return(character(0))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  J <- cr[k %in% cm$k, .(k, depth = abs(as.numeric(bm_dd)))][is.finite(depth)]
  if (!nrow(J)) return(character(0))
  J[depth >= stats::median(depth), k]
}
## 빠른 급락(헌장 빈칸 6 · Mishkin & White 2002 NBER WP 8992 p.7) — 위기 [고점, 저점] 안에서 벤치가 win 거래일 창 안에 drop 이상 하락한
##   구간이 있는 위기의 키. br = 같은 칸 산출물의 벤치 일수익(date · benchmark_ret) · 수준 = 누적곱(창 안 비율은 종가 비율과 같다).
##   위기 고점 · 저점이 벤치 날짜에 없으면 그 위기는 분류 못 함(unclassified — 빠름 집합에 넣지 않는다 · 기록).
p2_fast_crash_keys <- function(br, crises, win = 21L, drop = -0.20) {
  b <- as.data.table(br)[, .(date = as.Date(date), r = as.numeric(benchmark_ret))][order(date)]
  b[!is.finite(r), r := 0]; lvl <- cumprod(1 + b$r)
  me <- b[, .(d = max(date)), by = .(ym = format(date, "%Y-%m"))]$d                # 월말 거래일(월간 층의 신호일)
  cr <- .p2_rows_dt(crises)
  if (!nrow(cr) || !nrow(b)) return(list(keys = character(0), table = data.table(), unclassified = character(0), no_month_end = character(0)))
  rows <- lapply(seq_len(nrow(cr)), function(i) {
    i0 <- match(as.Date(as.character(cr$peak_date[i])), b$date); i1 <- match(as.Date(as.character(cr$trough_date[i])), b$date)
    k <- .p2_key(cr[i])
    if (is.na(i0) || is.na(i1) || i1 < i0) return(data.table(k = k, max_drop = NA_real_, fast = NA, seg_start = as.Date(NA), seg_end = as.Date(NA), month_ends_inside = NA_integer_))
    best <- 0; sa <- i0; se <- i0
    for (a in i0:i1) { e <- min(i1, a + as.integer(win)); j <- which.min(lvl[a:e]); v <- lvl[a + j - 1L] / lvl[a] - 1
                       if (v < best) { best <- v; sa <- a; se <- a + j - 1L } }
    data.table(k = k, max_drop = best, fast = best <= drop + 1e-12,                  # 1e-12 = 부동소수 여유(결정 수치 아님 — 정확히 −20% 경계)
               seg_start = b$date[sa], seg_end = b$date[se], month_ends_inside = sum(me >= b$date[i0] & me < b$date[i1]))
  })
  T <- rbindlist(rows)
  list(keys = T[fast %in% TRUE, k], table = T, unclassified = T[is.na(fast), k], win = as.integer(win), drop = drop,
       no_month_end = T[fast %in% TRUE & month_ends_inside %in% 0L, k])               # 위기 안 월말 0 — 월간 층이 위기 안에서 반응할 수 없는 급락(기록 판 · C-047)
}
## 강세 구간별 참여(헌장 빈칸 7) — 두 칸의 강세 국면을 (start_ym, end_ym) 으로 짝짓고, 변형 상승 포착 ≥ 기준 − (1 − ratio) × |기준| 인
##   구간 비율(양수 기준이면 '기준의 ratio 이상' · 음수 기준이면 기준보다 |기준|×(1−ratio) 까지 나빠도 됨 — 기준을 이기라고 요구하지 않는다).
##   짝 < min_pairs 이면 비율 NA(미시험)
p2_bull_segments <- function(bull_m, bull_r, ratio = 0.8, min_pairs = 2L) {
  bm <- .p2_rows_dt(bull_m); br <- .p2_rows_dt(bull_r)
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
## β 비대칭(헌장 빈칸 3 · 8) — 하락장 β < 상승장 β · 비유한 = NA(미시험)
p2_beta_asym <- function(beta_down, beta_up) {
  bd <- suppressWarnings(as.numeric(beta_down)); bu <- suppressWarnings(as.numeric(beta_up))
  if (length(bd) != 1L || length(bu) != 1L || !is.finite(bd) || !is.finite(bu)) return(NA)
  bd < bu
}
## β 비대칭의 변화량(⑤ 장치 검증 · 철학 P1 C-20261017-044) — 하락/상승 β 비가 같은 엔진 RX0 보다 낮아지는가. 비는 정적 축소(β 짝 사본 = k 배)에
##   불변이라 변화량만이 시변 층이 만든 비대칭이다. 상승장 β ≤ 0 · 비유한 = NA(미시험)
p2_beta_ratio_delta <- function(bd_v, bu_v, bd_r, bu_r) {
  x <- suppressWarnings(as.numeric(c(bd_v, bu_v, bd_r, bu_r)))
  if (length(x) != 4L || any(!is.finite(x)) || x[2] <= 0 || x[4] <= 0) return(list(ratio = NA_real_, ratio_rx0 = NA_real_, delta = NA_real_, ok = NA))
  rv <- x[1] / x[2]; rr <- x[3] / x[4]
  list(ratio = rv, ratio_rx0 = rr, delta = rv - rr, ok = rv < rr)
}
## Henriksson & Merton(1981, J. Business 54(4)) 타이밍 회귀(기록 · C-044) — 변형 − RX0 월 수익 = a + b·벤치 + γ·max(0, −벤치) · NW lag 3.
##   γ > 0 = 하락 달에 변형이 RX0 보다 덜 잃는다(볼록성). 회귀는 계약 beta_controlled_alpha.R 의 .nw_fit(같은 NW 규약)
p2_hm_fit <- function(diff, bench, nw_lag = 3L) {
  d <- suppressWarnings(as.numeric(diff)); k <- suppressWarnings(as.numeric(bench)); ok <- is.finite(d) & is.finite(k)
  if (sum(ok) < 24L || !exists(".nw_fit", mode = "function")) return(list(status = if (sum(ok) < 24L) "n<24" else "nw_fit 없음", gamma = NA_real_, t_gamma = NA_real_))
  f <- tryCatch(.nw_fit(d[ok], cbind(k[ok], pmax(0, -k[ok])), lag = nw_lag), error = function(e) NULL)
  if (is.null(f)) return(list(status = "fit 실패", gamma = NA_real_, t_gamma = NA_real_))
  list(status = "ok", n = f$n, alpha_m = f$coef[1], beta = f$coef[2], t_beta = f$t[2], gamma = f$coef[3], t_gamma = f$t[3])
}
## 현금 타이밍(기록 · 철학 P1 C-048 — 설계 §1 '현금을 위기 국면에만'을 기전 수준에서) — 월 노출(보유일 Σw 의 그 달 값) · 벤치 월수익(계약 bc_monthly) ·
##   보는 창 위기 달. 현금 달 = 노출 ≤ cash_thr. 정밀도 = 현금 달 중 위기 달 비율 · 재현율 = 위기 달 중 현금 달 비율 · 반등 노출 = 위기 바닥 달 뒤 3 · 6개월 평균 노출
p2_cash_timing <- function(expo_m, crises, cash_thr = 0.5) {
  E <- as.data.table(expo_m); cr <- .p2_rows_dt(crises)
  if (!nrow(E) || !all(c("ym", "e") %in% names(E))) return(list(status = "unmeasured"))
  E <- E[is.finite(e)][order(ym)]
  cm <- if (nrow(cr)) unique(unlist(lapply(seq_len(nrow(cr)), function(i) {
    s <- as.Date(paste0(substr(as.character(cr$peak_date[i]), 1, 7), "-01")); t <- as.Date(paste0(substr(as.character(cr$trough_date[i]), 1, 7), "-01"))
    format(seq(s, t, by = "month"), "%Y-%m") }))) else character(0)
  E[, crisis := ym %in% cm][, cash := e <= cash_thr]
  reb <- function(h) { v <- unlist(lapply(seq_len(nrow(cr)), function(i) {
    t <- as.Date(paste0(substr(as.character(cr$trough_date[i]), 1, 7), "-01")); w <- format(seq(t, by = "month", length.out = h + 1L)[-1], "%Y-%m")
    E[ym %in% w, e] })); if (length(v)) mean(v) else NA_real_ }
  list(status = "ok", cash_thr = cash_thr, n_months = nrow(E), cash_share = mean(E$cash), expo_mean = mean(E$e),
       precision = if (any(E$cash)) mean(E$crisis[E$cash]) else NA_real_, recall = if (any(E$crisis)) mean(E$cash[E$crisis]) else NA_real_,
       expo_crisis = if (any(E$crisis)) mean(E$e[E$crisis]) else NA_real_, expo_noncrisis = if (any(!E$crisis)) mean(E$e[!E$crisis]) else NA_real_,
       rebound_3m = reb(3L), rebound_6m = reb(6L))
}
## 사이클 짝 · 사이클 복리 — P3R03 그대로(직전 위기 바닥 연월 이후 시작 · 이 위기 고점 연월까지 끝난 강세 중 마지막 · 강세 1회 사용 · 짝 2 미만 NA)
p2_cycle_pairs <- function(bull, crises) {
  b <- .p2_rows_dt(bull); cr <- .p2_rows_dt(crises)
  emp <- data.table(k = character(0), bull = character(0), b_st = numeric(0), c_st = numeric(0))
  if (!nrow(cr)) return(list(pairs = emp, unpaired = character(0)))
  cr[, k := .p2_key(cr)][, pym := substr(as.character(peak_date), 1, 7)][, tym := substr(as.character(trough_date), 1, 7)]
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
p2_cycle_compound <- function(bull_m, cr_m, bull_r, cr_r, min_pairs = 2L) {
  pm <- p2_cycle_pairs(bull_m, cr_m); pr <- p2_cycle_pairs(bull_r, cr_r)
  M <- pm$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  R <- pr$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  K <- merge(M[, .(k, bull)], R[, .(k, bull)], by = c("k", "bull"))
  J <- merge(M, R, by = c("k", "bull"), suffixes = c("_m", "_r"))[is.finite(cyc_m) & is.finite(cyc_r)]
  list(n_pair = nrow(J), n_ge = sum(J$cyc_m >= J$cyc_r), share = if (nrow(J) >= min_pairs) mean(J$cyc_m >= J$cyc_r) else NA_real_,
       min_pairs = as.integer(min_pairs), unpaired_crises = sort(unique(c(pm$unpaired, pr$unpaired))),
       pair_mismatch = (nrow(M) - nrow(K)) + (nrow(R) - nrow(K)), per_cycle = J)
}
## 집중 손실(헌장 빈칸 1) — P3R03 그대로(깊은 위기가 표에 빠지면 partial → 미측정 · 0 으로 접지 않는다)
p2_top_loss <- function(top_losers, deep_peaks, floor) {
  TL <- .p2_rows_dt(top_losers)
  if (!nrow(TL) || !all(c("peak_date", "contrib") %in% names(TL)))
    return(list(status = "unmeasured", n_breach = NA_integer_, missing_deep = as.character(deep_peaks)))
  TL[, contrib := as.numeric(contrib)][, peak_date := as.character(peak_date)]
  per <- TL[is.finite(contrib), .(top1 = min(contrib), top3 = sum(sort(contrib)[seq_len(min(3L, .N))])), by = peak_date]
  deep <- per[peak_date %in% as.character(deep_peaks)]
  miss <- setdiff(as.character(deep_peaks), per$peak_date)
  list(status = if (length(miss)) "partial" else "ok", per_crisis = per, n_breach = sum(deep$top1 < floor), missing_deep = miss,
       deep_top1_min = if (nrow(deep)) min(deep$top1) else NA_real_)
}
p2_conc_status <- function(tl) if (isTRUE(tl$n_breach > 0L)) "breach" else if (identical(tl$status, "ok")) "clear" else "unmeasured"
## 알파 비열등(헌장 빈칸 4C) — t > t_floor ∧ 증분 ≥ −margin_frac × max(엔진 α, 0)(엔진 α ≤ 0 이면 감소 허용 0) · 입력 NA → NA
p2_alpha_ok <- function(pa_vis, t_floor, engine_alpha, margin_frac) {
  t <- suppressWarnings(as.numeric(pa_vis$t)); d <- suppressWarnings(as.numeric(pa_vis$d_alpha)); ea <- suppressWarnings(as.numeric(engine_alpha))
  if (!length(t) || !length(d) || !is.finite(t) || !is.finite(d) || !length(ea) || !is.finite(ea)) return(NA)
  (t > t_floor) && (d >= -margin_frac * max(ea, 0))
}
## 회복 지연 꼬리표(헌장 빈칸 5 · 판정 보조) — 두 칸 모두의 위기에서 변형의 회복 관측(거래일 · 미회복이면 관측 하한)이 RX0 보다 긴 위기 비율 > maj
p2_recovery_tag <- function(cr_m, cr_r, maj) {
  cm <- .p2_rows_dt(cr_m); cr <- .p2_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("st_recovery_obs" %in% names(cm)) || !("st_recovery_obs" %in% names(cr)))
    return(list(status = "unmeasured", tag = FALSE))
  cm[, k := .p2_key(cm)]; cr[, k := .p2_key(cr)]
  if (!"st_recovery_censored" %in% names(cm)) cm[, st_recovery_censored := NA]
  if (!"st_recovery_censored" %in% names(cr)) cr[, st_recovery_censored := NA]
  J <- merge(cm[, .(k, m = as.numeric(st_recovery_obs), mc = as.logical(st_recovery_censored))],
             cr[, .(k, r = as.numeric(st_recovery_obs), rc = as.logical(st_recovery_censored))], by = "k")
  ## 미회복(검열) 위기(격리 교차 점검 권고 1) — 관측이 비었어도 '아직 회복 못 함' = 관측 하한 무한대로 비교한다 · 둘 다 미회복 = 비교 불가(제외)
  J[, `:=`(m = fifelse(!is.finite(m) & mc %in% TRUE, Inf, m), r = fifelse(!is.finite(r) & rc %in% TRUE, Inf, r))]
  J <- J[!is.na(m) & !is.na(r) & !(is.infinite(m) & is.infinite(r))]
  if (!nrow(J)) return(list(status = "unmeasured", tag = FALSE))
  sh <- mean(J$m > J$r)
  list(status = "ok", n_pair = nrow(J), n_longer = sum(J$m > J$r), share = sh, tag = sh > maj, n_censored_variant = sum(is.infinite(J$m)), per_crisis = J)
}
## 오버레이 집행 줄(⑩ 구성 증거) — '[rf_cell_engine] overlay <kind> | 축 <스칼라|종목별> | 평균노출 a · 최소 b · 완전현금 c/N개월[ · 횡단면 sd 최대 s]
##   [ · 현금 집행(표현 하한) k신호일]' 마지막 줄 + lag 판 'overlay_shift=1 적용' 줄. 현금 집행 꼬리는 b234afb11 이후 판에만 있다(없으면 NA)
p2_parse_overlay_log <- function(lines) {
  s <- grep("^\\[rf_cell_engine\\] overlay [^ ]+ \\| 축 ", lines, value = TRUE)
  shift1 <- any(grepl("^\\[rf_cell_engine\\] overlay_shift=1 적용", lines))
  if (!length(s)) return(list(found = FALSE, shift1 = shift1))
  s <- s[length(s)]
  num <- function(p) { v <- suppressWarnings(as.numeric(sub(p, "\\1", s))); if (grepl(p, s)) v else NA_real_ }
  list(found = TRUE, shift1 = shift1, kind = sub("^\\[rf_cell_engine\\] overlay ([^ ]+) \\|.*", "\\1", s),
       axis = sub(".*\\| 축 ([^ ]+) \\|.*", "\\1", s), expo_mean = num(".*평균노출 ([0-9.]+).*"), expo_min = num(".*최소 ([0-9.]+).*"),
       full_cash_months = num(".*완전현금 ([0-9]+)/[0-9]+개월.*"), n_months = num(".*완전현금 [0-9]+/([0-9]+)개월.*"),
       xs_sd_max = num(".*횡단면 sd 최대 ([0-9.]+).*"), cash_exec = num(".*현금 집행\\(표현 하한\\) ([0-9]+)신호일.*"))
}
## 같은 선정 집합(오버레이판) — 보는 창 RX0 보유일마다 변형 보유 종목 ⊆ RX0 보유 종목 · 변형 보유가 없는 RX0 보유일 = 결측(전액 현금 달도
##   b234afb11 뒤로는 표현 하한 보유가 남는다 — 결측은 집행 결함이다)
p2_subset_check <- function(H_var, H_rx0, tau) {
  hv <- H_var[is.finite(w) & w > 0]; hr <- H_rx0[is.finite(w) & w > 0 & date <= as.Date(tau)]
  if (!nrow(hv) || !nrow(hr)) return(list(status = "unmeasured", n_checked = 0L, n_violate = NA_integer_, n_missing = NA_integer_))
  dd <- sort(unique(hr$date)); viol <- character(0); miss <- character(0)
  for (d in as.list(dd)) {
    tv <- unique(hv[date == d, ticker]); tr <- unique(hr[date == d, ticker])
    if (!length(tv)) { miss <- c(miss, format(d)); next }
    if (!all(tv %in% tr)) viol <- c(viol, format(d))
  }
  list(status = "ok", n_checked = length(dd), n_violate = length(viol), n_missing = length(miss),
       violate_dates = utils::head(viol, 10L), missing_dates = utils::head(miss, 10L))
}
## 라운드 판정 — 장치 × 엔진 표(변형 칸만 · tested · pass · excluded = 집중 손실 · 집중 손실 미측정). supported = 두 엔진 통과 ∧ 제외 아님인 장치 ≥ 1 ·
##   label = '판정(판정 칸/전체 칸)'
p2_round_verdict <- function(TB) {
  nt <- nrow(TB); nj <- if (nt) sum(TB$tested) else 0L
  lab <- function(v) sprintf("%s(판정 %d/%d)", v, as.integer(nj), as.integer(nt))
  if (!nt || !any(TB$tested))
    return(list(verdict = "untested", label = lab("untested"), n_judged = nj, n_total = nt, both = character(0), one = character(0), excluded = character(0)))
  if (!"excluded" %in% names(TB)) TB[, excluded := FALSE]
  agg <- TB[, .(n_pass = sum(tested & pass), ex = any(excluded & pass)), by = device]
  both <- agg[n_pass == 2L & !ex, device]; one <- agg[n_pass == 1L, device]; exc <- agg[n_pass == 2L & ex, device]
  v <- if (length(both)) "supported" else if (length(one) || length(exc)) "partial" else "falsified"
  list(verdict = v, label = lab(v), n_judged = nj, n_total = nt, both = both, one = one, excluded = exc)
}
## 최종 선택(rules.selection) — 검증 장치 중 보는 창 S 의 RX0 대비 증분(두 엔진 평균)이 가장 큰 1개 · 동률(차 < tie)이면 ③ · ④ 비율 합(두 엔진 평균)
p2_select <- function(xs_by_device, tie = 1e-12) {
  if (!length(xs_by_device)) return(list())
  sc <- lapply(names(xs_by_device), function(dv) {
    xs <- xs_by_device[[dv]]
    list(device = dv, dS = mean(vapply(xs, function(x) as.numeric(x$non_inferiority$S - x$non_inferiority$S_rx0), numeric(1))),
         r34 = mean(vapply(xs, function(x) as.numeric((x$rules$beta_deep$share %||% NA) + (x$rules$fast$share %||% NA)), numeric(1))))
  })
  ## 동률 = 최대 dS 와의 차가 tie 미만인 장치들(격리 교차 점검 선택 1 — 정확히 같을 때만이 아니라 규칙 문장 '차 < 1e-12') → 그 안에서 r34 큰 순
  dS <- vapply(sc, `[[`, numeric(1), "dS"); r34 <- vapply(sc, `[[`, numeric(1), "r34")
  top <- is.finite(dS) & (max(dS, na.rm = TRUE) - dS) < tie
  o <- order(!top, -ifelse(top, r34, dS), -dS)
  sc <- sc[o]
  if (sum(top) >= 2L) sc[[1]]$tie_break <- "r34"
  sc
}
## lag-1 진단 꼬리표(⑩ — 통과 조건 아님) — 장치 칸이 ③ · ④ 를 넘었을 때 lag-1 판도 넘으면 'lag-1 유지' · 아니면 '지연 민감(…)'
p2_lag_tag <- function(d_out, l_out) {
  if (!isTRUE(d_out$tested)) return("장치 칸 미시험 — lag-1 비교 없음")
  if (!isTRUE(l_out$tested)) return(sprintf("lag-1 판 미시험(%s) — 최종 선택 보류(pit.md C5 의무 2 · 격리 교차 점검 필수 3)", l_out$why %||% "?"))
  d3 <- isTRUE(d_out$rules$beta_deep$ok); d4 <- isTRUE(d_out$rules$fast$ok)
  l3 <- isTRUE(l_out$rules$beta_deep$ok); l4 <- isTRUE(l_out$rules$fast$ok)
  hold <- if (p2_lag_hold(d_out, l_out)) " · 느린 약세 개선이 lag-1 에서 붕괴 — 누출 조사 · 최종 선택 보류(철학 P1 C-052 (b))" else ""
  if (!d3 && !d4) return(sprintf("lag-1 비교 대상 없음(장치 ③ · ④ 미통과 · lag-1 ③ %s · ④ %s)%s", l3, l4, hold))
  lost <- c(if (d3 && !l3) "③", if (d4 && !l4) "④")
  paste0(if (!length(lost)) "lag-1 유지" else sprintf("지연 민감(lag-1 에서 %s 붕괴)", paste(lost, collapse = " · ")), hold)
}
## lag-1 조건 (b)(철학 P1 C-20261017-052) — 장치 칸이 느린 약세(빠름 아닌 위기)에서 β 짝 과반을 넘었는데 lag-1 판이 못 넘으면 누출 조사 대상 →
##   설명될 때까지 최종 선택 보류(빠른 급락의 lag-1 붕괴는 월간 층의 정당한 늦음일 수 있으나, 여러 달 이어지는 느린 약세는 한 달 지연으로 무너질 이유가 없다)
##   + lag-1 판이 미시험이면(측정 실패 · 집행 증거 불일치 · 입력 NA) 장치 칸이 판정됐어도 lag-1 스트레스 없이 고르지 않는다(보류 · 격리 교차 점검 필수 3)
p2_lag_hold <- function(d_out, l_out) {
  if (!isTRUE(d_out$tested)) return(FALSE)
  if (!isTRUE(l_out$tested)) return(TRUE)
  isTRUE(d_out$rules$slow$ok) && identical(l_out$rules$slow$ok, FALSE)
}
## 핀 대조 — precheck.R(측정 직전)과 evaluate.R 시작부(샤드 포함)가 같은 함수를 쓴다. 사양 · 운영 경로 · 비중 카탈로그 엔트리 ·
##   오버레이 카탈로그 arm · 패키지 · R 판 · 평가 경로 · 행동 카드 설정 사본. 반환 = 불일치 설명(없으면 길이 0)
p2_pin_mismatches <- function(pre, root) {
  md5 <- function(f) unname(as.character(tools::md5sum(file.path(root, f))))
  cj <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  bad <- character(0)
  for (c0 in pre$cells) if (!identical(md5(c0$path), c0$md5)) bad <- c(bad, paste("사양 md5:", c0$code))
  op <- pre$operational_pins
  if (is.null(op)) return(c(bad, "운영 핀 없음"))
  for (f in op$files) if (!identical(md5(f$path), f$md5)) bad <- c(bad, paste("운영 경로 md5:", f$path))
  wc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries, error = function(e) list())
  for (pin in op$catalog_entries) {
    ent <- Filter(function(z) identical(z$catalog_id, pin$catalog_id), wc)
    if (!length(ent) || !identical(ent[[1]]$status, pin$status) || !identical(cj(ent[[1]]$resolver), cj(pin$resolver)))
      bad <- c(bad, paste("비중 카탈로그 엔트리:", pin$catalog_id))
  }
  oc <- tryCatch(jsonlite::fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)$arms, error = function(e) list())
  for (pin in op$overlay_arms) {
    ent <- Filter(function(z) identical(z$id, pin$id), oc)
    if (!length(ent) || !identical(cj(ent[[1]]), cj(pin$entry))) bad <- c(bad, paste("오버레이 카탈로그 arm:", pin$id))
  }
  for (pk in names(op$packages)) {
    v <- tryCatch(as.character(utils::packageVersion(pk)), error = function(e) NA_character_)
    if (!identical(v, op$packages[[pk]])) bad <- c(bad, paste(pk, "판"))
  }
  if (!identical(R.version.string, op$r_version)) bad <- c(bad, "R 판")
  for (f in pre$evaluation$files %||% list()) if (!identical(md5(f$path), f$md5)) bad <- c(bad, paste("평가 경로 md5:", f$path))
  if (!is.null(pre$behavior_card_cfg) && !identical(md5(pre$behavior_card_cfg$path), pre$behavior_card_cfg$md5)) bad <- c(bad, "행동 카드 설정 사본 md5")
  bad
}
## 데이터 지문(fingerprint.sh — measure.sh 와 같은 정의) · 줄을 '|' 로 잇는다. 비교는 이름을 지운 문자열로(P3R03 오표시 = 이름 붙은 벡터 · identical 거짓)
p2_fingerprint <- function(rd, mode = "equality") {
  o <- tryCatch(suppressWarnings(system2("bash", c(shQuote(file.path(rd, "fingerprint.sh")), mode), stdout = TRUE, stderr = TRUE)),
                error = function(e) paste("error:", conditionMessage(e)))
  paste(o, collapse = "|")
}
p2_fp_same <- function(a, b) identical(unname(as.character(a)), unname(as.character(b)))

## ── 칸 평가(보는 창 / 사람 쪽 파일 분리 · C-031) — round_kit rk_eval_cell 과 같은 계약 호출 · 저장만 둘로 나눈다 ─────────
##   results/<code>/visible/{diagnosis_packet.json, eval_visible.json}(보는 창 리뷰어 열람 가능) ·
##   results/<code>/full/{behavior_card.json, eval_full.json}(사람 쪽 · 열람 금지 표식). 반환 = 둘을 합친 목록(메모리에서만)
p2_cell_join <- function(v, f) c(v, list(test = f$test, full = f$full))
## 칸 평가 안전 호출(격리 교차 점검 필수 2) — 진단 패킷 · 행동 카드 · 축 감사의 stop 이 30칸 판정 전체를 멈추지 않게 그 칸만 status = eval_error 로 접는다
##   (짝 판정은 평가 상태 단정에서 미시험 · 보는 창 파일은 끝에 쓰므로 부분 저장은 캐시가 되지 않는다)
p2_eval_cell <- function(root, res_dir, cell, env, tau)
  tryCatch(.p2_eval_cell_core(root, res_dir, cell, env, tau),
           error = function(e) { cat(sprintf("[평가] %s — 칸 평가 오류: %s\n", cell$code, conditionMessage(e))); list(code = cell$code, status = "eval_error", err = conditionMessage(e)) })
.p2_eval_cell_core <- function(root, res_dir, cell, env, tau) {
  out_dir <- file.path(res_dir, cell$code)
  fv <- file.path(out_dir, "visible", "eval_visible.json"); ff <- file.path(out_dir, "full", "eval_full.json")
  if (file.exists(fv) && file.exists(ff)) return(p2_cell_join(fromJSON(fv, simplifyVector = FALSE), fromJSON(ff, simplifyVector = FALSE)))
  rj <- file.path(res_dir, paste0(cell$code, ".json"))
  if (!file.exists(rj)) return(list(code = cell$code, status = "not_measured"))
  r <- fromJSON(rj, simplifyVector = FALSE)
  if (!isTRUE(r$ok)) return(list(code = cell$code, status = "measure_failed", err = r$err %||% NA))
  dir.create(file.path(out_dir, "visible"), recursive = TRUE, showWarnings = FALSE); dir.create(file.path(out_dir, "full"), recursive = TRUE, showWarnings = FALSE)
  if (is.null(env$raw)) env$raw <- mc_load_raw(root, from = "1999-11-01", hygiene = TRUE)
  t0 <- Sys.time()
  ax <- rk_axis_audit(root, r$artifacts)
  vis <- dp_build(r$artifacts, root = root, cell_spec = file.path(root, cell$path), raw = env$raw, bcfg = env$BCFG_L)
  dp_write(vis, file.path(out_dir, "visible"))
  card <- mc_card(r$artifacts, root = root, raw = env$raw, bcfg = env$BCFG_L)
  mc_write(card, file.path(out_dir, "full"), root = root)
  tp <- tryCatch(rk_test_perf(env$E, root, r$artifacts, tau), error = function(e) list(status = paste("error:", conditionMessage(e))))
  ar <- fromJSON(file.path(r$artifacts, "authoritative_remeasure.json"), simplifyVector = FALSE)
  g <- function(p) rk_getf(vis, p)
  v <- list(code = cell$code, engine = cell$engine %||% NA, component = cell$component %||% NA,
            status = if (isTRUE(ax$ok)) "evaluated" else "axis_violation", artifacts = r$artifacts, axis = ax,
            effective_start = ar$measurement_axis$effective_start[c("status", "date")],
            visible = list(window = vis$window, uc = g("behavior.summary.bull_up_capture_median"), dc = g("behavior.summary.crisis_cum_capture_median"),
                           dc_strong = g("behavior.dc_strong_max"), cagr = g("performance.strategy.cagr"), calmar = g("performance.strategy.calmar"),
                           port_t = g("performance.strategy.port_t"), mdd = g("performance.strategy.mdd"), sharpe = g("performance.strategy.sharpe"),
                           cdar = g("behavior.stats.cdar"), beta = g("behavior.stats.beta"), beta_down = g("behavior.stats.beta_down"), beta_up = g("behavior.stats.beta_up"),
                           dd_capture_median = g("behavior.summary.crisis_dd_capture_median"), dd_capture_worst = g("behavior.summary.crisis_dd_capture_worst"),
                           n_crisis = g("behavior.summary.n_crisis"), n_bull = g("behavior.summary.n_bull"), verdict = vis$behavior$verdict,
                           attribution = vis$controls$attribution$label %||% NA, exposure_mean = g("controls.exposure_profile.mean"),
                           turnover_annual = g("profile.turnover_annual"), cost_drag_annual = g("profile.cost_drag_annual")),
            eval_seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")))
  f <- list(code = cell$code, audience = P2R03_FULL_AUDIENCE,
            test = list(uc = card$test$bull_up_capture_median %||% NA, dc = card$test$crisis_cum_capture_median %||% NA,
                        n_bull = card$test$n_bull %||% NA, n_crisis = card$test$n_crisis %||% NA, verdict = card$test$verdict %||% NA,
                        dc_strong = card$dc_strong_max %||% NA, perf = tp),
            full = list(grade = ar$essence_grade, S = ar$grade_v3$S %||% NA, cr = card$overall$verdict, attribution = card$controls$attribution$overall$label %||% NA,
                        cdar = card$stats$cdar %||% NA, effective_start = ar$measurement_axis$effective_start$date %||% NA))
  writeLines(toJSON(f, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), ff, useBytes = TRUE)
  writeLines(toJSON(v, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), fv, useBytes = TRUE)   # 보는 창 파일을 마지막에(캐시 = 둘 다 있을 때)
  writeLines(P2R03_FULL_AUDIENCE, file.path(out_dir, "full", "NO_VISIBLE_REVIEW.txt"), useBytes = TRUE)
  cat(sprintf("[평가] %s — UC %.3f · DC %.3f · CAGR %.3f · CDaR %.3f · 축 %s · %.0f초\n", cell$code, v$visible$uc, v$visible$dc,
              v$visible$cagr, v$visible$cdar, ax$ok, v$eval_seconds))
  p2_cell_join(v, f)
}

## ── 판정 1칸(장치 · lag 판 × 엔진 vs RX0) — 본 실행과 등록 전 리허설(rehearse.R)이 같은 함수를 쓴다 ─────────────────
##   X = list(root · res(읽기 — 칸 평가 패킷 · 셀 로그) · out(쓰기 — 공통 창 · β 짝 사본과 그 패킷) · env(E · BCFG_L · raw) · fs · tau · ea(엔진 알파 캐시 환경))
##   opts(리허설 전용 — 본 실행은 비운다): force_start · force_k · expect_shift · log
##   실패 의미(사전 고정): 평가 상태 · 오버레이 집행 증거 · 실효 시작 · 같은 선정 집합 · 공통 창 · 패킷 · 위기 짝 · 판정 입력(①②⑤⑥⑦⑨⑫⑬) = 미시험 /
##   β 사본 실패 · ③ 짝 < 2 = 'β 대조 미측정'(통과 불가) / 빠른 급락 짝 < 2 = '빠른 급락 미측정'(통과 불가) / 집중 손실 표 결손 = '집중 손실 미측정'(제외)
.p2_untested <- function(out, why) {
  out$tested <- FALSE; out$verdict <- "untested"; out$why <- why
  out$tbl <- data.table(engine = out$engine, device = out$device, lag = isTRUE(out$lag), tested = FALSE, pass = FALSE, excluded = FALSE)
  out
}
.p2_read_holdings <- function(dir) {
  x <- fread(file.path(dir, "04_holdings.csv"), colClasses = list(character = "ticker"))
  x[, date := as.Date(date)]; x[, w := as.numeric(get(intersect(c("target_weight", "actual_weight"), names(x))[1]))]; x
}
p2_pk_read <- function(X, code, sub = "visible") {
  p <- file.path(X$res, code, sub, "diagnosis_packet.json"); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL
}
p2_pk_build <- function(X, spec_path, art, od) {
  if (is.null(X$env$raw)) X$env$raw <- mc_load_raw(X$root, from = "1999-11-01", hygiene = TRUE)
  v <- dp_build(art, root = X$root, cell_spec = file.path(X$root, spec_path), raw = X$env$raw, bcfg = X$env$BCFG_L)
  dp_write(v, od); fromJSON(file.path(od, "diagnosis_packet.json"), simplifyVector = FALSE)
}
## 엔진 자체 β-통제 알파(보는 창 · RX0 월 수익 대 벤치 · 계약 beta_controlled_alpha) — 알파 비열등 여유의 기준 · 엔진 자격 기록
p2_eng_alpha <- function(X, dir) {
  E <- X$env$E; rd <- .dp_read(E, dir); mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
  D <- merge(mon(rd$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(rd$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")
  D <- D[ym <= format(X$tau, "%Y-%m")]
  a <- tryCatch(beta_controlled_alpha(D$s, D$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
  list(alpha_ann = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, n = a$n %||% NA_integer_)
}
p2_eval_pair <- function(X, eng, dev, cm, cr, em, er, opts = list()) {
  FS <- X$fs; TAU <- X$tau; g <- rk_getf
  MAJ <- as.numeric(FS$majority_share); tol <- as.numeric(FS$crisis_improve_min)
  lag <- isTRUE(cm$lag)
  out <- list(engine = eng, device = dev, cell = cm$code, rx0 = cr$code, lag = lag, status = em$status %||% NA, status_rx0 = er$status %||% NA)
  if (!identical(em$status, "evaluated") || !identical(er$status, "evaluated"))
    return(.p2_untested(out, sprintf("평가 상태 %s · %s", em$status %||% "NA", er$status %||% "NA")))
  ## ⑩ 구성 증거 — 오버레이 집행 줄(층 · 축 · 노출 · 현금 집행 수) · lag 판은 'overlay_shift=1 적용' 줄 · 장치 칸은 그 줄이 없어야 한다
  lg <- opts$log %||% file.path(X$res, paste0(cm$code, ".log"))
  L <- if (file.exists(lg)) readLines(lg, warn = FALSE, encoding = "UTF-8") else character(0)
  ol <- p2_parse_overlay_log(L)
  ol$kind_expected <- opts$expect_kind %||% (P2R03_DEVICES[[dev]]$kind %||% NA_character_)   # 집행 줄의 층 = 장치의 kind(격리 교차 점검 권고 3)
  ol$kind_ok <- isTRUE(ol$found) && (is.na(ol$kind_expected) || identical(ol$kind, ol$kind_expected))
  out$overlay <- ol
  want_shift <- if (!is.null(opts$expect_shift)) isTRUE(opts$expect_shift) else lag
  if (!isTRUE(ol$found) || !identical(isTRUE(ol$shift1), want_shift) || !isTRUE(ol$kind_ok))
    return(.p2_untested(out, sprintf("오버레이 집행 증거 불일치(집행 줄 %s · shift=1 줄 %s · 기대 %s · 층 %s/%s)", isTRUE(ol$found), isTRUE(ol$shift1), want_shift,
                                     ol$kind %||% "-", ol$kind_expected %||% "-")))
  ## 실효 시작
  dm <- X$env$E$ta_resolve_artifact(em$artifacts)$dir; dr <- X$env$E$ta_resolve_artifact(er$artifacts)$dir
  esm <- em$effective_start; esr <- er$effective_start
  out$effective_start <- list(variant = esm, rx0 = esr)
  if (!identical(esm$status, "ok") || !identical(esr$status, "ok"))
    return(.p2_untested(out, sprintf("실효 시작 상태 %s · %s", esm$status %||% "NA", esr$status %||% "NA")))
  ## 같은 선정 집합(보는 창 RX0 보유일마다 변형 보유 ⊆ RX0 보유 · 결측 0)
  Hm <- tryCatch(.p2_read_holdings(dm), error = function(e) data.table()); Hr <- tryCatch(.p2_read_holdings(dr), error = function(e) data.table())
  ss <- p2_subset_check(Hm, Hr, TAU); out$same_selection <- ss
  if (!identical(ss$status, "ok") || !identical(ss$n_violate, 0L) || !identical(ss$n_missing, 0L))
    return(.p2_untested(out, sprintf("선정 집합 %s — 변형 보유 ⊄ RX0 보유 %s · 변형 보유 결측 %s / %s 보유일", ss$status, format(ss$n_violate),
                                     format(ss$n_missing), format(ss$n_checked))))
  ## 창 — 실효 시작이 같으면 원 산출 · 다르면(또는 리허설 강제) 공통 창 사본(실패 = 미시험)
  common <- !is.null(opts$force_start) || !identical(esm$date, esr$date)
  W <- tryCatch({
    if (!common) list(sub = "original", window = "original", am = dm, ar = dr, PM = p2_pk_read(X, cm$code), PRX = p2_pk_read(X, cr$code))
    else {
      cs <- if (!is.null(opts$force_start)) as.Date(opts$force_start) else {
        late <- if (as.Date(esm$date) > as.Date(esr$date)) dm else dr
        min(as.Date(fread(file.path(late, "03_period_returns.csv"))$date)) }
      sub <- paste0("common_", format(cs, "%Y%m%d")); base <- file.path(X$out, cm$code, sub)
      am <- file.path(base, "artifacts"); ar <- file.path(base, "rx0_artifacts")
      tr <- list(variant = p2_trim_artifacts(dm, am, cs), rx0 = p2_trim_artifacts(dr, ar, cs))
      list(sub = sub, window = paste0("common_from_", format(cs)), am = am, ar = ar, trim = tr,
           PM = p2_pk_build(X, cm$path, am, file.path(base, "visible")), PRX = p2_pk_build(X, cr$path, ar, file.path(base, "visible_rx0")))
    }
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(W$error)) return(.p2_untested(out, paste("공통 창 · 패킷 실패:", W$error)))
  out$window <- W$window; out$trim <- W$trim
  PM <- W$PM; PRX <- W$PRX; am <- W$am; ar <- W$ar
  if (is.null(PM) || is.null(PRX)) return(.p2_untested(out, "보는 창 패킷 없음"))
  ek <- paste(eng, W$sub)
  if (is.null(X$ea[[ek]])) assign(ek, tryCatch(p2_eng_alpha(X, ar), error = function(e) list(alpha_ann = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e))), envir = X$ea)
  ea <- X$ea[[ek]]
  ## ① · ② 위기 짝 · 깊은 위기(RX0 대비)
  crm <- PM$behavior$crises %||% list(); crr <- PRX$behavior$crises %||% list()
  maj <- p2_crisis_majority(crm, crr, tol, "dd_capture")
  deep <- p2_deep_crisis_keys(crm, crr)
  dmj <- p2_crisis_majority(crm, crr, tol, "dd_capture", subset = deep)
  out$crisis_pairs <- list(n_pair = maj$n_pair, unpaired = maj$unpaired, n_deep = dmj$n_pair, deep_keys = deep)
  if (!identical(as.integer(maj$unpaired), 0L)) return(.p2_untested(out, sprintf("위기 짝 불일치 %s(같은 창이면 0)", format(maj$unpaired))))
  if (maj$n_pair < 2L || dmj$n_pair < 2L) return(.p2_untested(out, sprintf("판정 위기 짝 < 2(전체 %d · 깊은 %d)", maj$n_pair, dmj$n_pair)))
  ## 빠른 급락 분류(같은 칸 RX0 산출물의 벤치 일수익 · 사전등록 창 · 문턱)
  fk <- tryCatch(p2_fast_crash_keys(fread(file.path(ar, "05_benchmark_returns.csv")), crr, as.integer(FS$fast_window_days), as.numeric(FS$fast_drop)),
                 error = function(e) list(keys = character(0), table = data.table(), unclassified = NA_character_, err = conditionMessage(e)))
  ## β 짝 사본 — k = 변형 β / RX0 β(보는 창) · k < 1 이면 RX0 를 k 배 노출로 낮춘 사본 · k ≥ 1 이면 사본 = RX0
  bm <- g(PM, "behavior.stats.beta"); br0 <- g(PRX, "behavior.stats.beta")
  k <- if (!is.null(opts$force_k)) as.numeric(opts$force_k) else if (is.finite(bm) && is.finite(br0) && br0 > 0) bm / br0 else NA_real_
  PB <- NULL; berr <- NULL
  if (!is.finite(k)) berr <- "k 비유한"
  else if (k >= 1) PB <- PRX
  else PB <- tryCatch({
    base <- file.path(X$out, cm$code, W$sub); bdir <- file.path(base, "rx0_beta_scaled")
    p2_beta_scaled_copy(ar, bdir, k)
    p2_pk_build(X, cr$path, bdir, file.path(base, "visible_rx0_beta"))
  }, error = function(e) { berr <<- conditionMessage(e); NULL })
  cbp <- if (!is.null(PB)) PB$behavior$crises %||% list() else list()
  emp <- list(n_pair = 0L, share = NA_real_)
  b3 <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = deep) else emp
  b4 <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = fk$keys) else emp
  r3 <- if (!is.null(PB) && b3$n_pair >= 2L) b3$share > MAJ else NA
  r4 <- if (!is.null(PB) && b4$n_pair >= 2L) b4$share > MAJ else NA
  ## 기록 판(판정 아님): ④ 에서 위기 안 월말 0 인 급락을 뺀 판(C-047) · 느린 약세(분류된 위기 중 빠름 아님)의 β 짝 비율(lag-1 조건 (b) · C-052)
  b4x <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = setdiff(fk$keys, fk$no_month_end)) else emp
  slow_keys <- if (nrow(fk$table)) fk$table[fast %in% FALSE, k] else character(0)
  bsl <- if (!is.null(PB)) p2_crisis_majority(crm, cbp, tol, "dd_capture", subset = slow_keys) else emp
  ## ⑤ β 비대칭(장치 검증 = 하락/상승 β 비의 변화량 · 방어 주장 = 수준) · ⑥ 강세 구간별 · ⑦ 알파 · ⑨ 사이클 · ⑫ S · ⑬ 경로
  bdu <- c(down = g(PM, "behavior.stats.beta_down"), up = g(PM, "behavior.stats.beta_up"))
  bdr <- c(down = g(PRX, "behavior.stats.beta_down"), up = g(PRX, "behavior.stats.beta_up"))
  r5d <- p2_beta_ratio_delta(bdu[["down"]], bdu[["up"]], bdr[["down"]], bdr[["up"]])
  r5 <- r5d$ok
  r5_level <- p2_beta_asym(bdu[["down"]], bdu[["up"]])
  bs <- p2_bull_segments(PM$behavior$bull_phases %||% list(), PRX$behavior$bull_phases %||% list(), as.numeric(FS$bull_ratio), 2L)
  ucm <- g(PM, "behavior.summary.bull_up_capture_median"); ucr <- g(PRX, "behavior.summary.bull_up_capture_median")
  pa <- tryCatch(rk_pair_alpha(X$env$E, am, ar, TAU),
                 error = function(e) list(visible = list(d_alpha = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e)), test = NULL))
  aok <- p2_alpha_ok(pa$visible, as.numeric(FS$alpha_t_floor), ea$alpha_ann, as.numeric(FS$alpha_margin_frac))
  cyc <- p2_cycle_compound(PM$behavior$bull_phases %||% list(), crm, PRX$behavior$bull_phases %||% list(), crr)
  cmv <- g(PM, "performance.strategy.calmar"); crv <- g(PRX, "performance.strategy.calmar")
  ptm <- g(PM, "performance.strategy.port_t"); ptr <- g(PRX, "performance.strategy.port_t")
  mvb <- c(g(PM, "behavior.summary.mdd_vs_bench"), g(PRX, "behavior.summary.mdd_vs_bench"))
  cdr <- c(g(PM, "behavior.stats.cdar"), g(PRX, "behavior.stats.cdar"))
  inp <- c(b = maj$share, d = dmj$share, beta_ratio = r5d$ratio, beta_ratio_rx0 = r5d$ratio_rx0, bull_share = bs$share, uc = ucm, cycle = cyc$share,
           calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr, mdd_vs_bench = mvb, cdar = cdr)
  if (any(!is.finite(inp)) || is.na(aok)) {
    out$inputs <- c(as.list(inp), list(alpha_t = pa$visible$t, engine_alpha = ea$alpha_ann, cycle_pairs = cyc$n_pair, bull_pairs = bs$n_pair))
    return(.p2_untested(out, sprintf("판정 입력 NA(%s)", paste(c(names(inp)[!is.finite(inp)], if (is.na(aok)) "alpha"), collapse = ","))))
  }
  Sm <- rk_S(cmv, ptm, FS); Sr <- rk_S(crv, ptr, FS)
  r12 <- if (Sr > 0) Sm >= Sr - as.numeric(FS$tie_eps) else cmv >= crv
  r13 <- mvb[1] <= mvb[2] && cdr[1] <= cdr[2]
  RL <- list(
    crisis    = c(maj[setdiff(names(maj), "per_crisis")], list(ok = maj$share > MAJ)),
    deep      = c(dmj[setdiff(names(dmj), "per_crisis")], list(deep_keys = deep, ok = dmj$share > MAJ)),
    beta_deep = list(k = k, k_forced = !is.null(opts$force_k), comparator = if (is.finite(k) && k >= 1) "RX0(k ≥ 1)" else "RX0 × k",
                     n_pair = b3$n_pair, share = b3$share, status = if (!is.null(berr)) "unmeasured" else if (is.na(r3)) "unmeasured(짝 < 2)" else "ok",
                     why = berr, ok = isTRUE(r3), per_crisis = b3$per_crisis),
    fast      = list(keys = fk$keys, table = fk$table, unclassified = fk$unclassified, n_pair = b4$n_pair, share = b4$share, classify_error = fk$err %||% NA_character_,
                     status = if (!is.null(berr)) "unmeasured" else if (is.na(r4)) "unmeasured(짝 < 2)" else "ok", ok = isTRUE(r4), per_crisis = b4$per_crisis,
                     record_excluding_no_month_end = list(excluded = fk$no_month_end, n_pair = b4x$n_pair, share = b4x$share)),
    slow      = list(keys = slow_keys, n_pair = bsl$n_pair, share = bsl$share, ok = if (bsl$n_pair >= 2L) isTRUE(bsl$share > MAJ) else NA, per_crisis = bsl$per_crisis,
                     note = "기록 · lag-1 조건 (b)(느린 약세 개선이 lag-1 에서 무너지면 누출 조사 · 최종 선택 보류)"),
    beta_asym = list(beta = c(variant = bm, rx0 = br0), down = bdu[["down"]], up = bdu[["up"]], rx0_down = bdr[["down"]], rx0_up = bdr[["up"]],
                     ratio = r5d$ratio, ratio_rx0 = r5d$ratio_rx0, delta = r5d$delta, ok = isTRUE(r5),
                     level_ok = r5_level, claim_tag = if (isTRUE(r5_level)) NA_character_ else "노출(β) 방어 — 비대칭 역행(하락 β ≥ 상승 β) · 방어 주장 불가(헌장 빈칸 3 · 8)"),
    bull      = c(bs[setdiff(names(bs), "per_phase")], list(uc_median = ucm, uc_median_rx0 = ucr, uc_floor = FS$uc_floor, per_phase = bs$per_phase,
                                                            ok = isTRUE(bs$share > MAJ) && ucm >= as.numeric(FS$uc_floor))),
    cycle     = c(cyc[setdiff(names(cyc), "per_cycle")], list(per_cycle = cyc$per_cycle, ok = cyc$share > MAJ)),
    path      = list(mdd_vs_bench = mvb, cdar = cdr, ok = r13),
    construction = list(overlay = ol, ok = TRUE))
  out$rules <- RL
  se <- if (is.finite(pa$visible$t) && pa$visible$t != 0) pa$visible$d_alpha / pa$visible$t else NA_real_
  mg <- as.numeric(FS$alpha_margin_frac) * max(ea$alpha_ann, 0)
  out$alpha_non_loss <- list(d_alpha = pa$visible$d_alpha, t = pa$visible$t, se = se, n = pa$visible$n, window = pa$visible$window, engine_alpha = ea,
                             t_floor = FS$alpha_t_floor, margin_frac = FS$alpha_margin_frac, margin = mg,
                             margin_over_se = if (is.finite(se) && se > 0) mg / se else NA_real_, ok = isTRUE(aok))
  out$alpha_test_window <- pa$test                                              # 사람 쪽 파일로만 나간다(본 실행이 분리)
  out$non_inferiority <- list(S = Sm, S_rx0 = Sr, calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr,
                              basis = if (Sr > 0) "S_vis − tie_eps" else "Calmar(S_rx0 = 0)", ok = isTRUE(r12))
  ## ⑧ 집중(깊은 위기 한 종목 기여) — 제외 판정 · ⑪ 회복 꼬리표 · 귀속(기록)
  deep_peaks <- vapply(strsplit(deep, " "), `[`, "", 1)
  tl <- p2_top_loss(PM$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  tl0 <- p2_top_loss(PRX$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  conc <- tryCatch(rk_concentration(am, TAU), error = function(e) list(visible = list(error = conditionMessage(e))))
  cst <- p2_conc_status(tl)
  out$concentration <- list(status = cst, visible = conc$visible, eff_n_mean = c(g(PM, "profile.eff_n_mean"), g(PRX, "profile.eff_n_mean")),
                            top_loss = tl[setdiff(names(tl), "per_crisis")], top_loss_rx0 = tl0[setdiff(names(tl0), "per_crisis")], per_crisis = tl$per_crisis,
                            concentration_loss_tag = identical(cst, "breach"), unmeasured_tag = identical(cst, "unmeasured"))
  out$recovery <- p2_recovery_tag(crm, crr, MAJ)
  ## 귀속(기록 · 철학 P1 C-046 ⑤) — MC8 'selection_defense' 는 정의상 '종목 선택 또는 노출 타이밍'이라 시변 층에선 β 짝 결과 · 시변 노출 경로 짝(size_exposure_path)과 병기
  out$attribution <- list(label = as.character(PM$controls$attribution$label %||% NA)[1], label_rx0 = as.character(PRX$controls$attribution$label %||% NA)[1],
                          share_beats_size_exposure = g(PM, "controls.attribution.share_beats_size_exposure"),
                          share_beats_size_exposure_path = g(PM, "controls.attribution.share_beats_size_exposure_path"),
                          beta_copy_deep = RL$beta_deep$share, timing_vs_selection = if (isTRUE(RL$beta_deep$ok)) "시변 노출(타이밍) 방어 후보 — β 짝 통과" else "β 짝 미통과 — 노출(β) 방어 또는 방어 없음")
  hm <- tryCatch({                                                               # HM 타이밍(기록) — rk_pair_alpha 와 같은 월 수익(계약 bc_monthly) · 보는 창
    E <- X$env$E; v <- .dp_read(E, am); b <- .dp_read(E, ar); mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
    S2 <- merge(mon(v$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(b$pr[, .(date, ret_net)], "ret_net")[, .(ym, b = r)], by = "ym")
    D2 <- merge(S2, mon(b$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")[ym <= format(TAU, "%Y-%m")][order(ym)]
    p2_hm_fit(D2$s - D2$b, D2$k)
  }, error = function(e) list(status = paste("오류:", conditionMessage(e))))
  ct <- tryCatch({                                                               # 현금 타이밍(기록) — 보는 창 월 노출 = 그 달 집행일 Σw
    Hv <- Hm[date <= TAU & is.finite(w) & w > 0, .(e = sum(w)), by = date][order(date)][, .(ym = format(date, "%Y-%m"), e)][, .(e = e[.N]), by = ym]
    list(expo_m = Hv, timing = p2_cash_timing(Hv, crm))
  }, error = function(e) list(expo_m = NULL, timing = list(status = paste("오류:", conditionMessage(e)))))
  out$record <- list(hm_timing = hm, cash_timing = ct$timing, expo_m = ct$expo_m,
                     rolling = PM$behavior$rolling, turnover_annual = c(variant = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")),
                     cost_drag_annual = c(variant = g(PM, "profile.cost_drag_annual"), rx0 = g(PRX, "profile.cost_drag_annual")),
                     exposure_mean = c(variant = g(PM, "controls.exposure_profile.mean"), rx0 = g(PRX, "controls.exposure_profile.mean")),
                     crisis_dd_capture_median = c(variant = g(PM, "behavior.summary.crisis_dd_capture_median"), rx0 = g(PRX, "behavior.summary.crisis_dd_capture_median")),
                     size_decile = "exposure.by_size_decile(패킷) — 유동성 3분위는 미측정")
  decisive <- RL$crisis$ok && RL$deep$ok && isTRUE(r3) && isTRUE(r4)
  strength <- isTRUE(r5) && RL$bull$ok && isTRUE(aok) && RL$cycle$ok
  out$pass <- decisive && strength && isTRUE(r12) && isTRUE(r13) && RL$construction$ok
  out$verdict <- if (out$pass) "pass" else if (!is.null(berr) || is.na(r3)) "beta_unmeasured" else if (is.na(r4) && isTRUE(r3)) "fast_unmeasured" else
                 if (RL$crisis$ok && RL$deep$ok && !isTRUE(r3)) "exposure_only" else if (isTRUE(r3) && !isTRUE(r4)) "slow_only" else
                 if (decisive) "defense_but_strength_or_path" else "not_decisive"
  out$tested <- TRUE
  out$tbl <- data.table(engine = eng, device = dev, lag = lag, tested = TRUE, pass = out$pass, excluded = !identical(cst, "clear"))
  out
}
## 판정 1칸 안전 호출 — 이름 붙은 분기 밖의 예기치 않은 오류도 그 칸만 미시험으로 접는다(오류 문구 기록 · 라운드 평가는 계속)
p2_eval_pair_safe <- function(X, eng, dev, cm, cr, em, er, opts = list())
  tryCatch(p2_eval_pair(X, eng, dev, cm, cr, em, er, opts),
           error = function(e) .p2_untested(list(engine = eng, device = dev, cell = cm$code, rx0 = cr$code, lag = isTRUE(cm$lag),
                                                 status = em$status %||% NA, status_rx0 = er$status %||% NA), paste("평가 오류:", conditionMessage(e))))
## 보는 창 판정 칸에서 사람 쪽 항목(시험 창 증분 알파)을 뺀다 — evaluation_visible.json 은 이것만 싣는다
##   셀 로그 집행 줄의 노출 수치(평균 · 최소 · 완전현금 · 현금 집행 수 · 횡단면 sd)는 전 구간(시험 창 포함)에서 센 값이라 보는 창 파일에는
##   집행 증거(found · shift1 · kind · axis)만 남기고 수치는 사람 쪽 파일로 보낸다(격리 교차 점검 필수 1 · C-031) — 보는 창 노출 = record$cash_timing
P2R03_OVERLAY_VISIBLE_KEYS <- c("found", "shift1", "kind", "axis", "kind_expected", "kind_ok")
p2_visible_only <- function(x) {
  x$alpha_test_window <- NULL; x$tbl <- NULL
  if (!is.null(x$overlay)) x$overlay <- x$overlay[intersect(names(x$overlay), P2R03_OVERLAY_VISIBLE_KEYS)]
  if (!is.null(x$rules$construction$overlay)) x$rules$construction$overlay <- x$rules$construction$overlay[intersect(names(x$rules$construction$overlay), P2R03_OVERLAY_VISIBLE_KEYS)]
  x
}

if (sys.nframe() == 0L) {   # ── 본 실행(스크립트로 불렸을 때만 — 픽스처 · 리허설은 위 함수만 적재) ──
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
CELLS_ONLY <- "--cells-only" %in% commandArgs(trailingOnly = TRUE)
RD <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay")
PR <- file.path(ROOT, "stage_artifacts/programs/P2_DEFENSE/P2R03_conditional_overlay/prereg.json")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, "P2R03_conditional_overlay"), pr_get(reg, "P2_DEFENSE")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, rk_md5(PR))) stop("[P2R03 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
BCFG <- file.path(ROOT, pre$behavior_card_cfg$path)
if (!identical(rk_md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P2R03 평가] 행동 카드 설정 사본 변경")
pin <- p2_pin_mismatches(pre, ROOT)                                            # 평가 시점 핀 전체 재대조(샤드 포함)
if (length(pin)) stop("[P2R03 평가] 핀 불일치 — 평가하지 않는다:\n", paste0("  · ", pin, collapse = "\n"))
pc <- file.path(RD, "results", "precheck.json")
if (!file.exists(pc) || !isTRUE(fromJSON(pc)$ok)) stop("[P2R03 평가] precheck 통과 기록이 없다 — 측정 조건 미확인")
TAU <- as.Date(pre$tau_d); FS <- pre$final_selection_rule
RES <- file.path(RD, "results")
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCFG); env$raw <- NULL
CELLS <- if (CELLS_ONLY) rk_shard(pre$cells) else pre$cells
EVS <- lapply(CELLS, function(cl) p2_eval_cell(ROOT, RES, cl, env, TAU)); names(EVS) <- vapply(CELLS, function(z) z$code, character(1))
for (cd in names(EVS)) if (!is.null(EVS[[cd]]$artifacts)) {                    # 칸 평가 캐시 = 현 측정 산출물(재측정 뒤 옛 캐시 혼입 차단)
  rj <- file.path(RES, paste0(cd, ".json"))
  a0 <- if (file.exists(rj)) fromJSON(rj, simplifyVector = FALSE)$artifacts else NULL
  if (!identical(EVS[[cd]]$artifacts, a0)) stop(sprintf("[P2R03 평가] %s 칸 평가 캐시의 산출물 ≠ 현 측정 산출물 — results/%s/ 를 지우고 다시 평가", cd, cd))
}
cat(sprintf("[P2R03 평가] 칸 평가 %d/%d\n", sum(vapply(EVS, function(e) e$status %in% c("evaluated", "axis_violation"), logical(1))), length(EVS)))
if (CELLS_ONLY) quit(status = 0)

cell_of <- function(eng, comp) Filter(function(z) identical(z$engine, eng) && identical(z$component, comp), pre$cells)[[1]]
dfr <- Filter(function(cl) { j <- file.path(RES, paste0(cl$code, ".json")); if (!file.exists(j)) return(FALSE)
                             r <- fromJSON(j, simplifyVector = FALSE); !isTRUE(r$ok) && !is.null(r$deferred) }, pre$cells)
if (length(dfr)) stop("[P2R03 평가] 측정 연기 칸 — 재측정(measure.sh) 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
fp_of <- function(code, tag) { f <- file.path(RES, sprintf("%s.fp_%s", code, tag)); if (file.exists(f)) paste(readLines(f, warn = FALSE), collapse = "|") else NA_character_ }
FP_EVAL <- p2_fingerprint(RD, "equality")
X <- list(root = ROOT, res = RES, out = RES, env = env, fs = FS, tau = TAU, ea = new.env())
ENGINES <- unique(vapply(pre$cells, function(z) z$engine, character(1)))
DEVS <- names(pre$variants)
OUT <- list(); TBL <- list(); FPG <- list(); LAGT <- list()
for (eng in ENGINES) {
  cr <- cell_of(eng, "RX0")
  codes <- unname(c(vapply(DEVS, function(dv) cell_of(eng, dv)$code, character(1)), vapply(DEVS, function(dv) cell_of(eng, paste0("L_", dv))$code, character(1)), cr$code))
  fps <- unname(unlist(lapply(codes, function(cd) c(fp_of(cd, "start"), fp_of(cd, "end")))))
  if (anyNA(fps) || length(unique(fps)) != 1L) stop(sprintf("[P2R03 평가] %s 묶음 데이터 지문 불일치 또는 부재 — 그 묶음을 재측정한 뒤 평가(rules.vintage_group)", eng))
  FPG[[eng]] <- list(measure = fps[1], eval_matches_measure = p2_fp_same(fps[1], FP_EVAL))
  for (dv in DEVS) {
    cm <- cell_of(eng, dv); cl <- cell_of(eng, paste0("L_", dv)); cl$lag <- TRUE
    od <- p2_eval_pair_safe(X, eng, dv, cm, cr, EVS[[cm$code]], EVS[[cr$code]])
    ol <- p2_eval_pair_safe(X, eng, dv, cl, cr, EVS[[cl$code]], EVS[[cr$code]])
    od$lag_tag <- p2_lag_tag(od, ol); od$lag_hold <- p2_lag_hold(od, ol); LAGT[[cm$code]] <- od$lag_tag
    TBL[[cm$code]] <- od$tbl; OUT[[cm$code]] <- od; OUT[[cl$code]] <- ol
  }
}
TB <- rbindlist(TBL)                                                             # 판정 표 = 장치 칸만(lag 판은 진단)
rv <- p2_round_verdict(TB)
held <- unique(vapply(Filter(function(x) isTRUE(x$lag_hold), OUT), function(x) x$device, character(1)))   # lag-1 조건 (b) — 최종 선택 보류
validated <- setdiff(rv$both, held)
xs_by <- setNames(lapply(validated, function(dv) Filter(function(x) identical(x$device, dv) && !isTRUE(x$lag), OUT)), validated)
sel <- p2_select(xs_by)
## 대조 읽기(철학 P1 C-20261017-049 · 판정 아님) — 엔진별 장치 간 월 노출 경로 상관 · 깊은 위기 β 짝 승패 겹침
TOLC <- as.numeric(FS$crisis_improve_min)
CONTRAST <- lapply(setNames(ENGINES, ENGINES), function(eng) {
  xs <- Filter(function(x) identical(x$engine, eng) && !isTRUE(x$lag) && isTRUE(x$tested), OUT)
  em <- Filter(function(z) !is.null(z) && nrow(as.data.table(z)), setNames(lapply(xs, function(x) x$record$expo_m), vapply(xs, function(x) x$device, "")))
  M <- if (length(em) >= 2L) Reduce(function(a, b) merge(a, b, by = "ym"), lapply(names(em), function(dv) setnames(copy(as.data.table(em[[dv]])), "e", dv))) else NULL
  wins <- rbindlist(lapply(xs, function(x) { pc <- as.data.table(x$rules$beta_deep$per_crisis %||% data.table())
    if (!nrow(pc)) NULL else data.table(device = x$device, crisis = pc$k, beats_beta_copy = pc$m < pc$r - TOLC) }), fill = TRUE)
  list(exposure_cor = if (!is.null(M) && ncol(M) >= 3L) round(stats::cor(as.matrix(M[, -1, with = FALSE]), use = "pairwise.complete.obs"), 3) else NULL,
       deep_wins = wins, readings = c("D3 vs D6 = 일정을 고정한 상태 대조(다변량 거리 vs 낙폭)", "D1 vs D6 = 같은 상태 변수의 처치 대조(순위형 축소 vs 스칼라 현금)",
                                       "D5 vs D6 = 추세 부호 vs 깊이", "D4 vs D3 = 학습된 꼬리 확률 vs 거리", "D7 vs D6 = 재진입 규칙 vs 깊이 비례 축소"))
})
excl <- lapply(rv$excluded, function(dv) list(device = dv, concentration = unique(vapply(Filter(function(x) identical(x$device, dv) && !isTRUE(x$lag), OUT),
                                                                                         function(x) as.character(x$concentration$status %||% "NA"), character(1)))))
VIS <- list(schema = "p2r03_evaluation_visible_v1", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rk_md5(PR),
            evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")), tau_d = pre$tau_d, cells = lapply(OUT, p2_visible_only), table = TB,
            verdict = rv$verdict, verdict_label = rv$label, n_judged = rv$n_judged, n_total = rv$n_total, pass_both = rv$both, pass_one = rv$one,
            excluded = excl, held_lag1_slow = held, validated = validated, selected = sel, lag_tags = LAGT, contrast = CONTRAST, engine_alpha = as.list(X$ea),
            fingerprint = list(eval = FP_EVAL, eval_record = p2_fingerprint(RD, "record"), groups = FPG),
            precheck = list(ok = isTRUE(fromJSON(pc)$ok), at = fromJSON(pc)$at, prereg_md5 = fromJSON(pc)$prereg_md5))
FULL <- list(schema = "p2r03_evaluation_full_v1", audience = P2R03_FULL_AUDIENCE, evaluated_at = VIS$evaluated_at, prereg_md5 = VIS$prereg_md5,
             cells = lapply(names(EVS), function(cd) list(code = cd, test = EVS[[cd]]$test, full = EVS[[cd]]$full,
                                                          alpha_test_window = OUT[[cd]]$alpha_test_window %||% NULL,
                                                          overlay_log_full_period = OUT[[cd]]$overlay %||% NULL)))   # 집행 줄 수치 = 전 구간(필수 1)
writeLines(toJSON(FULL, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation_full.json"), useBytes = TRUE)
writeLines(toJSON(VIS, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation_visible.json"), useBytes = TRUE)
for (x in OUT) cat(sprintf("[P2R03 평가] %s %s%s — %s%s · 창 %s · ① %s ② %s ③ %s ④ %s ⑤ %s ⑥ %s ⑦ %s ⑨ %s ⑫ %s ⑬ %s · 집중 %s%s\n", x$engine, x$device,
                           if (isTRUE(x$lag)) "(lag-1)" else "", x$verdict, if (!isTRUE(x$tested)) paste0("(", x$why, ")") else "", x$window %||% "-",
                           isTRUE(x$rules$crisis$ok), isTRUE(x$rules$deep$ok), x$rules$beta_deep$status %||% "-", x$rules$fast$status %||% "-",
                           isTRUE(x$rules$beta_asym$ok), isTRUE(x$rules$bull$ok), isTRUE(x$alpha_non_loss$ok), isTRUE(x$rules$cycle$ok),
                           isTRUE(x$non_inferiority$ok), isTRUE(x$rules$path$ok), x$concentration$status %||% "-",
                           if (!is.null(x$lag_tag)) paste0(" · ", x$lag_tag) else ""))
pj <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
cat(sprintf("[P2R03 평가] 판정 %s · 두 엔진 통과 %s · 한 엔진 %s · 집중 제외 %s · 선택 %s · 평가 지문 = 측정 지문 %s\n", rv$label, pj(rv$both), pj(rv$one),
            pj(rv$excluded), if (length(sel)) sel[[1]]$device else "-",
            paste(vapply(names(FPG), function(e) sprintf("%s:%s", e, FPG[[e]]$eval_matches_measure), ""), collapse = " ")))
}
