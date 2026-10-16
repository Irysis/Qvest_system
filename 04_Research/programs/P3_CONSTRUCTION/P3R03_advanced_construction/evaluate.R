## P3R03 평가 — 원문 고도화 구성 5종 × 엔진 2(E2 DNN 원형 · E3 B6_36) vs 같은 배치 기준 RX0 → 사전등록 규칙(stage_artifacts prereg.json rules)을 기계 적용(R2)
##   수치는 전부 R 계약 산출(rk_eval_cell · dp_build 보는 창 패킷 · rk_S · rk_pair_alpha · beta_controlled_alpha — 손계산 없음 · AX-008). 이 파일이 더하는 것은
##   규칙 적용 · 공통 창 사본 · β 짝 사본 · 기록 파싱뿐. 도우미는 P3R02 evaluate.R(픽스처 22/0)을 방법 5종으로 일반화하고, 철학 Superfan P1(R-20261016-001 ·
##   C-001~C-005) 수용분 — 깊은 위기 · 복리 경로 · 사이클 복리 · β 짝 대조 · 집중 손실 · 실질 개선 문턱 — 을 더했다.
##   v2(격리 교차 점검 revise 반영 · 2026-10-16): 사이클 짝 = 직전 위기 바닥 이후 · 강세 1회 사용 · 짝 2 미만 미시험 / 미측정은 통과로 접지 않는다(집중 손실 ·
##   β 대조 · 이력 탈락 꼬리표) / 판정 1칸 = p3_eval_pair(본 실행과 등록 전 리허설 rehearse.R 이 같은 함수) · 실패 의미 사전 고정(공통 창 · 패킷 실패 = 미시험) /
##   평가 시점 핀 전체 재대조(샤드 포함) / 칸 평가 캐시 = 현 측정 산출물 단정 / 같은 선정 집합(변형 보유 ⊆ RX0 보유) / 위기 짝 불일치 · 짝 2 미만 = 미시험 /
##   S 입력(Calmar · PORT_t) 유한성 / 알파 SE 병기 / 상승장 β 비 기록 / 평가 시점 데이터 지문 / 판정 칸 수 표기.
## 실행: Rscript evaluate.R [--cells-only] [--shard=i/K]      (측정 = measure.sh · 리허설 = rehearse.R)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

## 방법 → 카탈로그 id · 진단 줄 태그(어댑터가 성공 호출마다 한 줄 · 실패는 래퍼의 '어댑터 실패' 줄)
P3R03_METHODS <- list(HRP = list(catalog = "paper:HRPLdP2016", tag = "hrp"), NCO = list(catalog = "paper:NCOLdP2019", tag = "nco"),
                      MRE = list(catalog = "paper:MichaudResampledMinVar", tag = "michaud"), CVR = list(catalog = "paper:CVaRLPRU2000", tag = "cvar"),
                      ERC = list(catalog = "paper:ERCMRT2010", tag = "erc"))

## ── 순수 도우미(픽스처 검사 대상 · 계약 호출 없음) ─────────────────────────────
.p3_rows_dt <- function(x) if (is.data.frame(x)) as.data.table(x) else if (!length(x)) data.table() else
  rbindlist(lapply(x, function(r) as.data.table(lapply(r, function(v) if (is.null(v) || !length(v)) NA else v[[1]]))), fill = TRUE)
.p3_key <- function(x) paste(as.character(x$peak_date), as.character(x$trough_date))
## 공통 창 사본 — P3R02 와 같다(02 · 03 · 05 는 start 이후 · 04 는 start 이하 마지막 리밸부터 · NAV · 벤치 재기준 · 나머지 복사)
p3_trim_artifacts <- function(src_dir, out_dir, start) {
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
  if (!nrow(pr) || !nrow(nv) || !nrow(br)) stop("[p3_trim] start ", format(start), " 이후 행이 없다: ", src_dir)
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
## β 짝 사본(rules.beta_matched · 철학 C-003) — 기준 칸의 기간수익 · NAV 를 k(= 칸 β / 기준 β < 1)배 노출로(잔여 1−k = 현금 · 수익 0) ·
##   보유 비중도 k 배(Σw = k) · 벤치 · 나머지 파일은 그대로. 같은 계약(dp_build)으로 패킷을 만들어 'β 만 낮춘 기준'과 비교한다.
p3_beta_scaled_copy <- function(src_dir, out_dir, k) {
  if (!is.finite(k) || k <= 0 || k > 1) stop("[p3_beta] k 는 (0, 1]: ", k)
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
## 위기 짝 과반 — metric(cum_capture 또는 dd_capture)이 기준 − tol 보다 낮은 위기의 비율 · subset = 판정에 쓸 위기 키(NULL = 짝 전부)
p3_crisis_majority <- function(cr_m, cr_r, tol, metric = "cum_capture", subset = NULL) {
  cm <- .p3_rows_dt(cr_m); cr <- .p3_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !(metric %in% names(cm)) || !(metric %in% names(cr)))
    return(list(n_pair = 0L, n_better = 0L, share = NA_real_, unpaired = nrow(cm) + nrow(cr)))
  cm[, k := .p3_key(cm)]; cr[, k := .p3_key(cr)]
  J <- merge(cm[, .(k, m = as.numeric(get(metric)))], cr[, .(k, r = as.numeric(get(metric)))], by = "k")
  unp <- (nrow(cm) - nrow(J)) + (nrow(cr) - nrow(J))
  if (!is.null(subset)) J <- J[k %in% subset]
  J <- J[is.finite(m) & is.finite(r)]
  nb <- sum(J$m < J$r - tol)
  list(n_pair = nrow(J), n_better = nb, share = if (nrow(J)) nb / nrow(J) else NA_real_, unpaired = unp, per_crisis = J)
}
## 깊은 위기(rules.decisive (d) · 철학 C-001) — 두 칸 모두에 있는 위기 중 벤치 낙폭(bm_dd · 음수)의 크기가 그 집합 중앙값 이상인 위기의 키
p3_deep_crisis_keys <- function(cr_m, cr_r) {
  cm <- .p3_rows_dt(cr_m); cr <- .p3_rows_dt(cr_r)
  if (!nrow(cm) || !nrow(cr) || !("bm_dd" %in% names(cr))) return(character(0))
  cm[, k := .p3_key(cm)]; cr[, k := .p3_key(cr)]
  J <- cr[k %in% cm$k, .(k, depth = abs(as.numeric(bm_dd)))][is.finite(depth)]
  if (!nrow(J)) return(character(0))
  J[depth >= stats::median(depth), k]
}
## 사이클 짝(rules.decisive (c) · 교차 점검 필수 1) — 위기를 고점 순으로 놓고, 위기마다 '직전 위기 바닥 연월 이후(같은 달 포함) 시작해 이 위기 고점
##   연월까지(같은 달 포함) 끝난 강세 국면 중 마지막'과 짝짓는다 · 강세 1개는 1번만 쓴다 · 짝 없는 위기는 목록으로 남긴다(벤치 연대기 — 성과 무관)
p3_cycle_pairs <- function(bull, crises) {
  b <- .p3_rows_dt(bull); cr <- .p3_rows_dt(crises)
  emp <- data.table(k = character(0), bull = character(0), b_st = numeric(0), c_st = numeric(0))
  if (!nrow(cr)) return(list(pairs = emp, unpaired = character(0)))
  cr[, k := .p3_key(cr)][, pym := substr(as.character(peak_date), 1, 7)][, tym := substr(as.character(trough_date), 1, 7)]
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
## 사이클 복리 — 사이클 수익 = (1 + 강세 st_cum)(1 + 위기 st_cum) − 1(계약 산출 두 값의 정의식 결합 — 사전등록 공식) · 칸 ≥ 기준인 사이클 비율 ·
##   두 칸의 같은 (위기, 강세) 짝만 비교 · 짝이 min_pairs 미만이면 비율 NA(미시험)
p3_cycle_compound <- function(bull_m, cr_m, bull_r, cr_r, min_pairs = 2L) {
  pm <- p3_cycle_pairs(bull_m, cr_m); pr <- p3_cycle_pairs(bull_r, cr_r)
  M <- pm$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  R <- pr$pairs[, .(k, bull, cyc = (1 + b_st) * (1 + c_st) - 1)]
  K <- merge(M[, .(k, bull)], R[, .(k, bull)], by = c("k", "bull"))
  J <- merge(M, R, by = c("k", "bull"), suffixes = c("_m", "_r"))[is.finite(cyc_m) & is.finite(cyc_r)]
  list(n_pair = nrow(J), n_ge = sum(J$cyc_m >= J$cyc_r), share = if (nrow(J) >= min_pairs) mean(J$cyc_m >= J$cyc_r) else NA_real_,
       min_pairs = as.integer(min_pairs), unpaired_crises = sort(unique(c(pm$unpaired, pr$unpaired))),
       pair_mismatch = (nrow(M) - nrow(K)) + (nrow(R) - nrow(K)), per_cycle = J)
}
## 집중 손실(rules.concentration · 철학 C-002) — 깊은 위기 중 한 종목 최악 기여(exposure.top_losers contrib 최솟값)가 floor 보다 나쁜 위기 수 · 위기별 1위 · 상위 3 합 ·
##   깊은 위기가 표에 빠지면 status = partial(교차 점검 필수 5 — 0 으로 접지 않는다)
p3_top_loss <- function(top_losers, deep_peaks, floor) {
  TL <- .p3_rows_dt(top_losers)
  if (!nrow(TL) || !all(c("peak_date", "contrib") %in% names(TL)))
    return(list(status = "unmeasured", n_breach = NA_integer_, missing_deep = as.character(deep_peaks)))
  TL[, contrib := as.numeric(contrib)][, peak_date := as.character(peak_date)]
  per <- TL[is.finite(contrib), .(top1 = min(contrib), top3 = sum(sort(contrib)[seq_len(min(3L, .N))])), by = peak_date]
  deep <- per[peak_date %in% as.character(deep_peaks)]
  miss <- setdiff(as.character(deep_peaks), per$peak_date)
  list(status = if (length(miss)) "partial" else "ok", per_crisis = per, n_breach = sum(deep$top1 < floor), missing_deep = miss,
       deep_top1_min = if (nrow(deep)) min(deep$top1) else NA_real_)
}
## 집중 상태 — breach(깊은 위기 한 종목 손실 < floor · 꼬리표 '집중 손실') · unmeasured(표 없음 · 깊은 위기 누락 — 꼬리표 '집중 손실 미측정') · clear.
##   breach · unmeasured 둘 다 P4 구성 부품 후보에서 제외(미측정을 통과로 접지 않는다)
p3_conc_status <- function(tl) if (isTRUE(tl$n_breach > 0L)) "breach" else if (identical(tl$status, "ok")) "clear" else "unmeasured"
## β 짝 판정(교차 점검 필수 4 · 5 — 실패 의미 사전 고정) — k 비유한 · 사본 · 패킷 실패 · 사본 판정 입력 NA = unmeasured('β 대조 미측정' · 통과 아님) ·
##   k ≥ 1 = not_needed(변형 β 가 기준 이상이면 β 로 산 방어가 아니다) · 그 밖 = ok(beats = 중앙값이 사본보다 낮고 깊은 위기 과반)
p3_beta_verdict <- function(k, dcm, dcb, deep_share, maj, err = NULL) {
  if (!length(k) || !is.finite(k)) return(list(status = "unmeasured", beats = NA, why = "k 비유한"))
  if (k >= 1) return(list(status = "not_needed", beats = TRUE))
  if (!is.null(err)) return(list(status = "unmeasured", beats = NA, why = paste("β 사본 · 패킷 실패:", err)))
  if (!length(dcb) || !is.finite(dcb) || !length(deep_share) || !is.finite(deep_share)) return(list(status = "unmeasured", beats = NA, why = "β 사본 판정 입력 NA"))
  list(status = "ok", beats = (dcm < dcb) && (deep_share > maj))
}
## 셀 로그 — 엔진 커버리지 줄 · 방법 진단 줄('[<tag>] d=… n=… maxw=… effn=…' — key=value · 키 앞 공백 필수) · 래퍼 폴백 줄
p3_parse_cell_log <- function(lines, tag) {
  cov <- grep("^\\[rf_cell_engine\\] catalog ", lines, value = TRUE)
  cv <- if (length(cov)) {
    s <- cov[length(cov)]
    num <- function(p) suppressWarnings(as.numeric(sub(p, "\\1", s)))
    list(diff = num(".*차별화 ([0-9]+).*"), ew_fallback = num(".*EW폴백 ([0-9]+).*"),
         n_hit = num(".*선정일 ([0-9]+)/[0-9]+.*"), n_try = num(".*선정일 [0-9]+/([0-9]+).*"))
  } else NULL
  if (!is.null(cv)) cv$carry_days <- cv$n_try - cv$n_hit
  dl <- grep(sprintf("^\\[%s\\] d=", tag), lines, value = TRUE)
  D <- if (length(dl)) rbindlist(lapply(dl, function(s) {
    s2 <- sub(sprintf("^\\[%s\\]", tag), "", s)
    g <- function(k) if (grepl(paste0(" ", k, "="), s2, fixed = TRUE)) sub(paste0(".* ", k, "=([^ ]+).*"), "\\1", s2) else NA_character_
    data.table(d = as.Date(g("d")), n = suppressWarnings(as.integer(g("n"))), maxw = suppressWarnings(as.numeric(g("maxw"))),
               effn = suppressWarnings(as.numeric(g("effn"))))
  })) else data.table(d = as.Date(character(0)), n = integer(0), maxw = numeric(0), effn = numeric(0))
  fb <- grep("어댑터 실패", lines, fixed = TRUE, value = TRUE)
  list(coverage = cv, diag = D, n_method_fallback = length(fb),
       fallback_by_reason = list(under_3_assets = sum(grepl("자산 3종 미만", fb, fixed = TRUE)), other = sum(!grepl("자산 3종 미만", fb, fixed = TRUE))))
}
## 처치 전달률 = 방법 해를 낸 고유 신호일(진단 줄) / 선정 신호일(n_try) — 커버리지 줄이 없으면 NA(미시험)
p3_delivery <- function(pl) {
  if (is.null(pl$coverage) || !is.finite(pl$coverage$n_try) || pl$coverage$n_try <= 0) return(NA_real_)
  length(unique(pl$diag$d[!is.na(pl$diag$d)])) / pl$coverage$n_try
}
p3_crisis_execs <- function(exec_dates, crises) {
  ex <- sort(unique(as.Date(exec_dates))); cr <- .p3_rows_dt(crises)
  if (!length(ex) || !nrow(cr)) return(as.Date(character(0)))
  out <- unlist(lapply(seq_len(nrow(cr)), function(i) {
    p0 <- as.Date(as.character(cr$peak_date[i])); t0 <- as.Date(as.character(cr$trough_date[i]))
    c(suppressWarnings(max(ex[ex <= p0])), ex[ex > p0 & ex <= t0])
  }))
  out <- as.Date(out, origin = "1970-01-01"); sort(unique(out[is.finite(out)]))
}
p3_selection_vs_ref <- function(ex_m, ex_r) {
  m <- .p3_rows_dt(ex_m); r <- .p3_rows_dt(ex_r)
  need <- c("peak_date", "trough_date", "selection_sum")
  if (!nrow(m) || !nrow(r) || !all(need %in% names(m)) || !all(need %in% names(r))) return(list(n_pair = 0L, share = NA_real_))
  m[, k := .p3_key(m)]; r[, k := .p3_key(r)]
  J <- merge(m[, .(k, sm = as.numeric(selection_sum))], r[, .(k, sr = as.numeric(selection_sum))], by = "k")[is.finite(sm) & is.finite(sr)]
  list(n_pair = nrow(J), n_better = sum(J$sm - J$sr > 0), share = if (nrow(J)) mean(J$sm - J$sr > 0) else NA_real_, per_crisis = J)
}
p3_history_drops <- function(D, H_rx0) {
  if (!nrow(D) || !nrow(H_rx0)) return(data.table())
  sel <- H_rx0[is.finite(w) & w > 0, .(n_sel = uniqueN(ticker)), by = date][order(date)]
  out <- D[, { ex <- sel[date > d][1]; list(exec = ex$date, n_sel = ex$n_sel, n = n) }, by = d]
  out[, drops := pmax(n_sel - n, 0L)][, drop_share := drops / n_sel]
  out[]
}
## 같은 선정 집합(교차 점검 권고 4) — 방법 해를 낸 신호일(진단 줄 d)마다 그 뒤 첫 RX0 집행일에서 변형 보유 종목 ⊆ RX0 보유 종목.
##   방법 해가 없던 신호일(EW 폴백 · 이월)은 보지 않는다(이월 보유는 앞 선정을 들고 있어 정의상 집합이 다르다 — 전달률 규칙이 따로 센다)
p3_subset_check <- function(D, H_var, H_rx0) {
  dd <- sort(unique(as.Date(D$d[!is.na(D$d)])))
  hv <- H_var[is.finite(w) & w > 0]; hr <- H_rx0[is.finite(w) & w > 0]
  if (!length(dd) || !nrow(hv) || !nrow(hr)) return(list(status = "unmeasured", n_checked = 0L, n_violate = NA_integer_, n_missing = NA_integer_))
  ex <- sort(unique(hr$date)); idx <- findInterval(as.numeric(dd), as.numeric(ex)) + 1L
  xe <- ex[idx[idx <= length(ex)]]
  viol <- character(0); miss <- character(0)
  for (i in seq_along(xe)) {
    tv <- unique(hv[date == xe[i], ticker]); tr <- unique(hr[date == xe[i], ticker])
    if (!length(tv)) { miss <- c(miss, format(xe[i])); next }
    if (!all(tv %in% tr)) viol <- c(viol, format(xe[i]))
  }
  list(status = "ok", n_checked = length(xe), n_violate = length(viol), n_missing = length(miss), violate_dates = utils::head(viol, 10L),
       missing_dates = utils::head(miss, 10L))
}
## 알파 비열등(rules.non_inferiority 알파 항 · 철학 C-004 ③) — t > t_floor ∧ 증분 ≥ −margin_frac × max(엔진 자체 β-통제 알파, 0) · 입력 NA → NA(미시험)
p3_alpha_ok <- function(pa_vis, t_floor, engine_alpha, margin_frac) {
  t <- suppressWarnings(as.numeric(pa_vis$t)); d <- suppressWarnings(as.numeric(pa_vis$d_alpha)); ea <- suppressWarnings(as.numeric(engine_alpha))
  if (!length(t) || !length(d) || !is.finite(t) || !is.finite(d) || !length(ea) || !is.finite(ea)) return(NA)
  (t > t_floor) && (d >= -margin_frac * max(ea, 0))
}
## 라운드 판정 — 방법 × 엔진 표(tested · pass · excluded = 집중 손실 · 집중 손실 미측정으로 P4 후보 제외). supported = 두 엔진 통과 ∧ 제외 아님인 방법이 1개 이상 ·
##   label = '판정(판정 칸/전체 칸)'(교차 점검 권고 12)
p3_round_verdict <- function(TB) {
  nt <- nrow(TB); nj <- if (nt) sum(TB$tested) else 0L
  lab <- function(v) sprintf("%s(판정 %d/%d)", v, as.integer(nj), as.integer(nt))
  if (!nt || !any(TB$tested))
    return(list(verdict = "untested", label = lab("untested"), n_judged = nj, n_total = nt, both = character(0), one = character(0), excluded = character(0)))
  if (!"excluded" %in% names(TB)) TB[, excluded := FALSE]
  agg <- TB[, .(n_pass = sum(tested & pass), ex = any(excluded & pass)), by = method]
  both <- agg[n_pass == 2L & !ex, method]; one <- agg[n_pass == 1L, method]; exc <- agg[n_pass == 2L & ex, method]
  v <- if (length(both)) "supported" else if (length(one) || length(exc)) "partial" else "falsified"
  list(verdict = v, label = lab(v), n_judged = nj, n_total = nt, both = both, one = one, excluded = exc)
}
## 후보 꼬리표(rules.selection) — 두 엔진 판정 기록(xs)에서. 미측정은 따로 적는다(통과로 접지 않는다)
p3_candidate_tags <- function(xs) {
  stt <- function(f) vapply(xs, function(x) as.character(f(x) %||% "unmeasured")[1], character(1))
  c(if (any(stt(function(x) x$beta_matched$status) == "unmeasured")) "β 대조 미측정",
    if (any(vapply(xs, function(x) identical(x$beta_matched$beats, FALSE), logical(1)))) "노출(β) 방어",
    if (!all(vapply(xs, function(x) isTRUE(x$attribution$mechanism), logical(1)))) "기전(선택) 방어 미확인",
    if (any(vapply(xs, function(x) isTRUE(x$history_drop_tag), logical(1)))) "선택 교락(이력 탈락)",
    if (any(stt(function(x) x$history_drop_status) == "unmeasured")) "선택 교락 미측정")
}
## 핀 대조(교차 점검 필수 3) — precheck.R(측정 직전)과 evaluate.R 시작부(샤드 포함)가 같은 함수를 쓴다. 사양 · 운영 경로 · 카탈로그 엔트리 ·
##   패키지 · R 판 · 평가 경로. 반환 = 불일치 설명(없으면 길이 0)
p3_pin_mismatches <- function(pre, root) {
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
      bad <- c(bad, paste("카탈로그 엔트리:", pin$catalog_id))
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
## 이력 탈락 꼬리표(선택 교락) — 판독할 위기 집행 행이 없거나 탈락 몫이 전부 비유한이면 미측정(통과로 접지 않는다 · v2 점검 권고 3)
p3_history_drop_eval <- function(hd_cr, drop_tag_share, has_holdings = TRUE) {
  if (!isTRUE(has_holdings) || is.null(hd_cr) || !nrow(hd_cr) || !any(is.finite(hd_cr$drop_share))) return(list(status = "unmeasured", tag = FALSE))
  list(status = "ok", tag = mean(hd_cr$drop_share, na.rm = TRUE) > drop_tag_share)
}
## 데이터 지문(fingerprint.sh — measure.sh 와 같은 정의) · 줄을 '|' 로 잇는다
p3_fingerprint <- function(rd, mode = "equality") {
  o <- tryCatch(suppressWarnings(system2("bash", c(shQuote(file.path(rd, "fingerprint.sh")), mode), stdout = TRUE, stderr = TRUE)),
                error = function(e) paste("error:", conditionMessage(e)))
  paste(o, collapse = "|")
}

## ── 판정 1칸(방법 × 엔진) — 본 실행과 등록 전 리허설(rehearse.R)이 같은 함수를 쓴다(교차 점검 필수 4) ─────────────────
##   X = list(root · res(읽기 — 칸 평가 패킷 · 셀 로그) · out(쓰기 — 공통 창 · β 짝 사본과 그 패킷) · env(E · BCFG_L · raw) · fs · tau · ea(엔진 알파 캐시 환경))
##   opts(리허설 전용 — 본 실행은 비운다): force_start(공통 창 시작 강제) · force_k(β 짝 k 강제) · tag · log(다른 라운드 산출로 리허설할 때)
##   실패 의미(사전 고정): 평가 상태 · 전달률 · 실효 시작 · 선정 집합 · 공통 창 · 패킷 · 위기 짝 · 판정 입력 = 미시험 / β 사본 = 'β 대조 미측정' /
##   집중 손실 표 = '집중 손실 미측정'(후보 제외) / 보유 판독 = '선택 교락 미측정'
.p3_untested <- function(out, why) {
  out$tested <- FALSE; out$verdict <- "untested"; out$why <- why
  out$tbl <- data.table(engine = out$engine, method = out$method, tested = FALSE, pass = FALSE, excluded = FALSE)
  out
}
.p3_read_holdings <- function(dir) {
  x <- fread(file.path(dir, "04_holdings.csv"), colClasses = list(character = "ticker"))
  x[, date := as.Date(date)]; x[, w := as.numeric(get(intersect(c("target_weight", "actual_weight"), names(x))[1]))]; x
}
p3_pk_read <- function(X, code, sub = "visible") {
  p <- file.path(X$res, code, sub, "diagnosis_packet.json"); if (file.exists(p)) fromJSON(p, simplifyVector = FALSE) else NULL
}
p3_pk_build <- function(X, spec_path, art, od) {
  if (is.null(X$env$raw)) X$env$raw <- mc_load_raw(X$root, from = "1999-11-01", hygiene = TRUE)
  v <- dp_build(art, root = X$root, cell_spec = file.path(X$root, spec_path), raw = X$env$raw, bcfg = X$env$BCFG_L)
  dp_write(v, od); fromJSON(file.path(od, "diagnosis_packet.json"), simplifyVector = FALSE)
}
## 엔진 자체 β-통제 알파(보는 창 · RX0 월 수익 대 벤치 · 계약 beta_controlled_alpha) — 알파 비열등 여유의 기준
p3_eng_alpha <- function(X, dir) {
  E <- X$env$E; rd <- .dp_read(E, dir); mon <- function(d, col) E$bc_monthly(d[, .(date, r = get(col))], "r")
  D <- merge(mon(rd$pr[, .(date, ret_net)], "ret_net")[, .(ym, s = r)], mon(rd$br[, .(date, benchmark_ret)], "benchmark_ret")[, .(ym, k = r)], by = "ym")
  D <- D[ym <= format(X$tau, "%Y-%m")]
  a <- tryCatch(beta_controlled_alpha(D$s, D$k, periods_per_year = 12, nw_lag = 3L), error = function(e) NULL)
  list(alpha_ann = a$alpha_ann %||% NA_real_, t = a$t_alpha %||% NA_real_, n = a$n %||% NA_integer_)
}
p3_eval_pair <- function(X, eng, mth, cm, cr, em, er, opts = list()) {
  FS <- X$fs; TAU <- X$tau; g <- rk_getf
  MAJ <- as.numeric(FS$majority_share); tol <- as.numeric(FS$crisis_improve_min)
  out <- list(engine = eng, method = mth, cell = cm$code, rx0 = cr$code, status = em$status %||% NA, status_rx0 = er$status %||% NA)
  ## ① 평가 상태
  if (!identical(em$status, "evaluated") || !identical(er$status, "evaluated"))
    return(.p3_untested(out, sprintf("평가 상태 %s · %s", em$status %||% "NA", er$status %||% "NA")))
  ## ③ 처치 전달률
  lg <- opts$log %||% file.path(X$res, paste0(cm$code, ".log"))
  L <- if (file.exists(lg)) readLines(lg, warn = FALSE, encoding = "UTF-8") else character(0)
  pl <- p3_parse_cell_log(L, opts$tag %||% P3R03_METHODS[[mth]]$tag); dlv <- p3_delivery(pl); out$delivery <- dlv
  if (!is.finite(dlv) || dlv < as.numeric(FS$delivery_min)) return(.p3_untested(out, sprintf("처치 전달률 %s < %s", format(dlv), FS$delivery_min)))
  ## ② 실효 시작
  dm <- X$env$E$ta_resolve_artifact(em$artifacts)$dir; dr <- X$env$E$ta_resolve_artifact(er$artifacts)$dir
  es <- function(d) tryCatch(fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE)$measurement_axis$effective_start, error = function(e) NULL)
  esm <- es(dm); esr <- es(dr)
  out$effective_start <- list(variant = esm[c("status", "date")], rx0 = esr[c("status", "date")])
  if (!identical(esm$status, "ok") || !identical(esr$status, "ok"))
    return(.p3_untested(out, sprintf("실효 시작 상태 %s · %s", esm$status %||% "NA", esr$status %||% "NA")))
  ## 같은 선정 집합(방법 해를 낸 보는 창 신호일)
  Hm <- tryCatch(.p3_read_holdings(dm), error = function(e) data.table()); Hr <- tryCatch(.p3_read_holdings(dr), error = function(e) data.table())
  ss <- p3_subset_check(pl$diag[!is.na(d) & d <= TAU], Hm, Hr); out$same_selection <- ss
  if (!identical(ss$status, "ok") || !identical(ss$n_violate, 0L) || ss$n_missing > (1 - as.numeric(FS$delivery_min)) * ss$n_checked)
    return(.p3_untested(out, sprintf("선정 집합 %s — 변형 보유 ⊄ RX0 보유 %s · 변형 집행 결측 %s / %s 집행일", ss$status, format(ss$n_violate),
                                     format(ss$n_missing), format(ss$n_checked))))
  ## 창 — 실효 시작이 같으면 원 산출 · 다르면(또는 리허설 강제) 공통 창 사본(실패 = 미시험)
  common <- !is.null(opts$force_start) || !identical(esm$date, esr$date)
  W <- tryCatch({
    if (!common) list(sub = "original", window = "original", am = dm, ar = dr, PM = p3_pk_read(X, cm$code), PRX = p3_pk_read(X, cr$code))
    else {
      cs <- if (!is.null(opts$force_start)) as.Date(opts$force_start) else {
        late <- if (as.Date(esm$date) > as.Date(esr$date)) dm else dr
        min(as.Date(fread(file.path(late, "03_period_returns.csv"))$date)) }
      sub <- paste0("common_", format(cs, "%Y%m%d")); base <- file.path(X$out, cm$code, sub)
      am <- file.path(base, "artifacts"); ar <- file.path(base, "rx0_artifacts")
      tr <- list(variant = p3_trim_artifacts(dm, am, cs), rx0 = p3_trim_artifacts(dr, ar, cs))
      list(sub = sub, window = paste0("common_from_", format(cs)), am = am, ar = ar, trim = tr,
           PM = p3_pk_build(X, cm$path, am, file.path(base, "visible")), PRX = p3_pk_build(X, cr$path, ar, file.path(base, "visible_rx0")))
    }
  }, error = function(e) list(error = conditionMessage(e)))
  if (!is.null(W$error)) return(.p3_untested(out, paste("공통 창 · 패킷 실패:", W$error)))
  out$window <- W$window; out$trim <- W$trim
  PM <- W$PM; PRX <- W$PRX; am <- W$am; ar <- W$ar
  if (is.null(PM) || is.null(PRX)) return(.p3_untested(out, "보는 창 패킷 없음"))
  ek <- paste(eng, W$sub)
  if (is.null(X$ea[[ek]])) assign(ek, tryCatch(p3_eng_alpha(X, ar), error = function(e) list(alpha_ann = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e))), envir = X$ea)
  ea <- X$ea[[ek]]
  ## 위기 짝 · 깊은 위기 · 사이클
  crm <- PM$behavior$crises %||% list(); crr <- PRX$behavior$crises %||% list()
  dcm <- g(PM, "behavior.summary.crisis_cum_capture_median"); dcr <- g(PRX, "behavior.summary.crisis_cum_capture_median")
  ucm <- g(PM, "behavior.summary.bull_up_capture_median"); ucr <- g(PRX, "behavior.summary.bull_up_capture_median")
  maj <- p3_crisis_majority(crm, crr, tol, metric = "dd_capture")
  deep <- p3_deep_crisis_keys(crm, crr)
  dmj <- p3_crisis_majority(crm, crr, tol, metric = "dd_capture", subset = deep)
  out$crisis_pairs <- list(n_pair = maj$n_pair, unpaired = maj$unpaired, n_deep = dmj$n_pair, deep_keys = deep)
  if (!identical(as.integer(maj$unpaired), 0L)) return(.p3_untested(out, sprintf("위기 짝 불일치 %s(같은 창이면 0)", format(maj$unpaired))))
  if (maj$n_pair < 2L || dmj$n_pair < 2L) return(.p3_untested(out, sprintf("판정 위기 짝 < 2(전체 %d · 깊은 %d)", maj$n_pair, dmj$n_pair)))
  cyc <- p3_cycle_compound(PM$behavior$bull_phases %||% list(), crm, PRX$behavior$bull_phases %||% list(), crr)
  mvb <- c(g(PM, "behavior.summary.mdd_vs_bench"), g(PRX, "behavior.summary.mdd_vs_bench"))
  cdr <- c(g(PM, "behavior.stats.cdar"), g(PRX, "behavior.stats.cdar"))
  cmv <- g(PM, "performance.strategy.calmar"); crv <- g(PRX, "performance.strategy.calmar")
  ptm <- g(PM, "performance.strategy.port_t"); ptr <- g(PRX, "performance.strategy.port_t")
  pa <- tryCatch(rk_pair_alpha(X$env$E, am, ar, TAU),
                 error = function(e) list(visible = list(d_alpha = NA_real_, t = NA_real_, n = NA_integer_, err = conditionMessage(e)), test = NULL))
  aok <- p3_alpha_ok(pa$visible, as.numeric(FS$alpha_t_floor), ea$alpha_ann, as.numeric(FS$alpha_margin_frac))
  inp <- c(dc = dcm, dc_rx0 = dcr, uc = ucm, b = maj$share, d = dmj$share, cycle = cyc$share, mdd_vs_bench = mvb, cdar = cdr,
           calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr)
  if (any(!is.finite(inp)) || is.na(aok)) {
    out$inputs <- c(as.list(inp), list(alpha_t = pa$visible$t, engine_alpha = ea$alpha_ann, cycle_pairs = cyc$n_pair, cycle_unpaired = cyc$unpaired_crises))
    return(.p3_untested(out, sprintf("판정 입력 NA(%s)", paste(c(names(inp)[!is.finite(inp)], if (is.na(aok)) "alpha"), collapse = ","))))
  }
  a <- dcm < dcr
  b <- maj$share > MAJ
  cc <- ucm >= as.numeric(FS$uc_floor) && cyc$share > MAJ
  d <- dmj$share > MAJ
  e <- mvb[1] <= mvb[2] && cdr[1] <= cdr[2]
  Sm <- rk_S(cmv, ptm, FS); Sr <- rk_S(crv, ptr, FS)
  ni <- if (Sr > 0) Sm >= Sr - as.numeric(FS$tie_eps) else cmv >= crv
  out$decisive <- list(a_median = list(variant = dcm, rx0 = dcr, ok = a), b_majority = c(maj[setdiff(names(maj), "per_crisis")], list(ok = b)),
                       c_participation = list(variant = ucm, rx0 = ucr, ratio = ucm / ucr, floor = FS$uc_floor, cycle = cyc[setdiff(names(cyc), "per_cycle")], ok = cc),
                       d_deep = c(dmj[setdiff(names(dmj), "per_crisis")], list(deep_keys = deep, ok = d)),
                       e_path = list(mdd_vs_bench = mvb, cdar = cdr, ok = e), ok = a && b && cc && d && e)
  out$mild_only <- a && b && !(d && e)                                        # 중앙값 · 과반만 — '완만한 약세 · 여진 방어'(통과 아님)
  out$non_inferiority <- list(S = Sm, S_rx0 = Sr, calmar = cmv, calmar_rx0 = crv, port_t = ptm, port_t_rx0 = ptr,
                              basis = if (Sr > 0) "S_vis − tie_eps" else "Calmar(S_rx0 = 0)", ok = isTRUE(ni))
  se <- if (is.finite(pa$visible$t) && pa$visible$t != 0) pa$visible$d_alpha / pa$visible$t else NA_real_
  mg <- as.numeric(FS$alpha_margin_frac) * max(ea$alpha_ann, 0)
  out$alpha_non_loss <- list(d_alpha = pa$visible$d_alpha, t = pa$visible$t, se = se, n = pa$visible$n, engine_alpha = ea, t_floor = FS$alpha_t_floor,
                             margin_frac = FS$alpha_margin_frac, margin = mg, margin_over_se = if (is.finite(se) && se > 0) mg / se else NA_real_, ok = isTRUE(aok))
  ## β 짝 대조(철학 C-003) — k = 변형 β / RX0 β · 상승장 β 비 기록(교차 점검 권고 6)
  bm <- g(PM, "behavior.stats.beta"); br0 <- g(PRX, "behavior.stats.beta")
  bu <- c(g(PM, "behavior.stats.beta_up"), g(PRX, "behavior.stats.beta_up")); bd <- c(g(PM, "behavior.stats.beta_down"), g(PRX, "behavior.stats.beta_down"))
  k <- if (!is.null(opts$force_k)) as.numeric(opts$force_k) else if (is.finite(bm) && is.finite(br0) && br0 > 0) bm / br0 else NA_real_
  bmc <- list(k = k, k_forced = !is.null(opts$force_k), k_up = if (all(is.finite(bu)) && bu[2] > 0) bu[1] / bu[2] else NA_real_,
              beta = list(variant = bm, rx0 = br0, down = bd, up = bu))
  dcb <- NA_real_; dsh <- NA_real_; berr <- NULL
  if (is.finite(k) && k < 1) {
    rb <- tryCatch({
      base <- file.path(X$out, cm$code, W$sub); bdir <- file.path(base, "rx0_beta_scaled")
      p3_beta_scaled_copy(ar, bdir, k)
      PB <- p3_pk_build(X, cr$path, bdir, file.path(base, "visible_rx0_beta"))
      list(dcb = g(PB, "behavior.summary.crisis_cum_capture_median"), dmb = p3_crisis_majority(crm, PB$behavior$crises %||% list(), tol, metric = "dd_capture", subset = deep))
    }, error = function(e) list(err = conditionMessage(e)))
    if (!is.null(rb$err)) berr <- rb$err else {
      dcb <- rb$dcb; dsh <- if (rb$dmb$n_pair >= 2L) rb$dmb$share else NA_real_
      bmc$scaled <- list(dc_median = dcb, deep = rb$dmb[setdiff(names(rb$dmb), "per_crisis")])
    }
  }
  out$beta_matched <- c(bmc, p3_beta_verdict(k, dcm, dcb, dsh, MAJ, berr))
  ## 기전(선택) 방어 — MC8 라벨 + 노출 분해 selection_sum 짝 과반
  sv <- p3_selection_vs_ref(PM$exposure$crises %||% list(), PRX$exposure$crises %||% list())
  out$attribution <- list(label = as.character(PM$controls$attribution$label %||% NA)[1], selection_vs_rx0 = sv[setdiff(names(sv), "per_crisis")])
  out$attribution$mechanism <- identical(out$attribution$label, "selection_defense") && is.finite(sv$share) && sv$share > MAJ
  ## 집중 손실(철학 C-002) — 깊은 위기가 손실 표에 하나라도 없거나 표가 없으면 '집중 손실 미측정'(후보 제외)
  deep_peaks <- vapply(strsplit(deep, " "), `[`, "", 1)
  tl <- p3_top_loss(PM$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  tl0 <- p3_top_loss(PRX$exposure$top_losers %||% list(), deep_peaks, as.numeric(FS$single_name_loss_floor))
  conc <- tryCatch(rk_concentration(am, TAU), error = function(e) list(visible = list(error = conditionMessage(e))))
  cst <- p3_conc_status(tl)
  out$concentration <- list(status = cst, visible = conc$visible, eff_n_mean = c(g(PM, "profile.eff_n_mean"), g(PRX, "profile.eff_n_mean")),
                            top_loss = tl[setdiff(names(tl), "per_crisis")], top_loss_rx0 = tl0[setdiff(names(tl0), "per_crisis")], per_crisis = tl$per_crisis,
                            concentration_loss_tag = identical(cst, "breach"), unmeasured_tag = identical(cst, "unmeasured"))
  ## 이력 탈락(선택 교락) — E2 기준(EW)은 선정 전부 보유 · E3 기준(lean:entropy)은 변형과 같은 이력 필터를 거친다(rf_cell_engine 카탈로그 경로)
  hd <- if (nrow(Hr)) p3_history_drops(pl$diag, Hr) else data.table()
  cx <- if (nrow(hd)) p3_crisis_execs(hd$exec, crr) else as.Date(character(0))
  hd_cr <- if (nrow(hd)) hd[exec %in% cx] else hd
  hde <- p3_history_drop_eval(hd_cr, as.numeric(FS$drop_tag_share), has_holdings = nrow(Hr) > 0L)
  out$history_drop_status <- hde$status; out$history_drop_tag <- hde$tag
  ann <- .p3_rows_dt(PM$performance$annual %||% list())
  rec <- tryCatch({ R0 <- .p3_rows_dt(crm); as.list(R0[, intersect(c("peak_date", "st_recovery_obs", "st_recovery_censored"), names(R0)), with = FALSE]) },
                  error = function(e) NULL)
  out$record <- list(coverage = pl$coverage, method_fallback_lines = pl$n_method_fallback, fallback_by_reason = pl$fallback_by_reason,
                     diag = list(n_days = nrow(pl$diag), effn_median = stats::median(pl$diag$effn, na.rm = TRUE), maxw_max = suppressWarnings(max(pl$diag$maxw, na.rm = TRUE)),
                                 n_le4 = sum(pl$diag$effn <= 4, na.rm = TRUE)),
                     history_drops = if (nrow(hd)) list(mean = mean(hd$drops), max = max(hd$drops), crisis_mean_share = if (nrow(hd_cr)) mean(hd_cr$drop_share, na.rm = TRUE) else NA_real_) else NULL,
                     recovery = rec, rolling = PM$behavior$rolling,
                     negative_years = if (nrow(ann) && "strategy" %in% names(ann)) sum(as.numeric(ann$strategy) < 0, na.rm = TRUE) else NA_integer_,
                     size_decile = "exposure.by_size_decile(패킷) — 유동성 3분위는 미측정", turnover_annual = list(variant = g(PM, "profile.turnover_annual"), rx0 = g(PRX, "profile.turnover_annual")),
                     per_crisis = maj$per_crisis, per_cycle = cyc$per_cycle, alpha_test_window = pa$test)
  out$pass <- isTRUE(out$decisive$ok) && isTRUE(out$non_inferiority$ok) && isTRUE(out$alpha_non_loss$ok)
  out$verdict <- if (out$pass) "pass" else if (isTRUE(out$mild_only)) "mild_only" else if (isTRUE(out$decisive$ok)) "decisive_but_inferior" else "not_decisive"
  out$tested <- TRUE
  out$tbl <- data.table(engine = eng, method = mth, tested = TRUE, pass = out$pass, excluded = !identical(cst, "clear"))
  out
}
## 판정 1칸 안전 호출(v2 점검 권고 1) — 이름 붙은 분기 밖의 예기치 않은 오류도 그 칸만 미시험으로 접는다(오류 문구 기록 · 라운드 평가는 계속).
##   평가 전체가 멈추면 '결과를 본 뒤 고정된 evaluate.R 을 고치거나(R2 위반) 라운드가 멈추는' 경로가 남는다
p3_eval_pair_safe <- function(X, eng, mth, cm, cr, em, er, opts = list())
  tryCatch(p3_eval_pair(X, eng, mth, cm, cr, em, er, opts),
           error = function(e) .p3_untested(list(engine = eng, method = mth, cell = cm$code, rx0 = cr$code, status = em$status %||% NA, status_rx0 = er$status %||% NA),
                                            paste("평가 오류:", conditionMessage(e))))

if (sys.nframe() == 0L) {   # ── 본 실행(스크립트로 불렸을 때만 — 픽스처 · 리허설은 위 함수만 적재) ──
source("02_Infrastructure/contracts/diagnosis_packet.R")
source("02_Infrastructure/contracts/matched_controls.R")
source("02_Infrastructure/contracts/beta_controlled_alpha.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
CELLS_ONLY <- "--cells-only" %in% commandArgs(trailingOnly = TRUE)
RD <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction")
PR <- file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json")
reg <- pr_load(ROOT); rr <- Filter(function(r) identical(r$round_id, "P3R03_advanced_construction"), pr_get(reg, "P3_CONSTRUCTION")$rounds)
if (!length(rr) || !identical(rr[[1]]$prereg_md5, rk_md5(PR))) stop("[P3R03 평가] 사전등록 md5 불일치(R2)")
pre <- fromJSON(PR, simplifyVector = FALSE)
BCFG <- file.path(ROOT, pre$behavior_card_cfg$path)
if (!identical(rk_md5(BCFG), pre$behavior_card_cfg$md5)) stop("[P3R03 평가] 행동 카드 설정 사본 변경")
pin <- p3_pin_mismatches(pre, ROOT)                                            # 평가 시점 핀 전체 재대조(샤드 포함)
if (length(pin)) stop("[P3R03 평가] 핀 불일치 — 평가하지 않는다:\n", paste0("  · ", pin, collapse = "\n"))
pc <- file.path(RD, "results", "precheck.json")
if (!file.exists(pc) || !isTRUE(fromJSON(pc)$ok)) stop("[P3R03 평가] precheck 통과 기록이 없다 — 측정 조건 미확인")
TAU <- as.Date(pre$tau_d); FS <- pre$final_selection_rule
env <- new.env(); env$E <- .dp_deps(ROOT); env$BCFG_L <- env$E$bc_cfg(ROOT, path = BCFG); env$raw <- NULL
CELLS <- if (CELLS_ONLY) rk_shard(pre$cells) else pre$cells
EVS <- lapply(CELLS, function(cl) rk_eval_cell(ROOT, RD, cl, env, TAU)); names(EVS) <- vapply(CELLS, function(z) z$code, character(1))
for (cd in names(EVS)) if (!is.null(EVS[[cd]]$artifacts)) {                    # 칸 평가 캐시 = 현 측정 산출물(재측정 뒤 옛 캐시 혼입 차단)
  rj <- file.path(RD, "results", paste0(cd, ".json"))
  a0 <- if (file.exists(rj)) fromJSON(rj, simplifyVector = FALSE)$artifacts else NULL
  if (!identical(EVS[[cd]]$artifacts, a0)) stop(sprintf("[P3R03 평가] %s 칸 평가 캐시의 산출물 ≠ 현 측정 산출물 — results/%s/ 를 지우고 다시 평가", cd, cd))
}
cat(sprintf("[P3R03 평가] 칸 평가 %d/%d\n", sum(vapply(EVS, function(e) e$status %in% c("evaluated", "axis_violation"), logical(1))), length(EVS)))
if (CELLS_ONLY) quit(status = 0)

RES <- file.path(RD, "results")
cell_of <- function(eng, comp) Filter(function(z) identical(z$engine, eng) && identical(z$component, comp), pre$cells)[[1]]
dfr <- Filter(function(cl) { j <- file.path(RES, paste0(cl$code, ".json")); if (!file.exists(j)) return(FALSE)
                             r <- fromJSON(j, simplifyVector = FALSE); !isTRUE(r$ok) && !is.null(r$deferred) }, pre$cells)
if (length(dfr)) stop("[P3R03 평가] 측정 연기 칸 — 재측정(measure.sh) 뒤 평가: ", paste(vapply(dfr, function(z) z$code, ""), collapse = ","))
fp_of <- function(code, tag) { f <- file.path(RES, sprintf("%s.fp_%s", code, tag)); if (file.exists(f)) paste(readLines(f, warn = FALSE), collapse = "|") else NA_character_ }
FP_EVAL <- p3_fingerprint(RD, "equality")
X <- list(root = ROOT, res = RES, out = RES, env = env, fs = FS, tau = TAU, ea = new.env())
ENGINES <- unique(vapply(pre$cells, function(z) z$engine, character(1)))
METHODS <- names(pre$variants)
OUT <- list(); TBL <- list(); FPG <- list()
for (eng in ENGINES) {
  cr <- cell_of(eng, "RX0")
  codes <- c(vapply(METHODS, function(m) cell_of(eng, m)$code, character(1)), cr$code)
  fps <- unlist(lapply(codes, function(cd) c(fp_of(cd, "start"), fp_of(cd, "end"))))
  if (anyNA(fps) || length(unique(fps)) != 1L) stop(sprintf("[P3R03 평가] %s 묶음 데이터 지문 불일치 또는 부재 — 그 묶음을 재측정한 뒤 평가(rules.vintage_group)", eng))
  FPG[[eng]] <- list(measure = fps[1], eval_matches_measure = identical(fps[1], FP_EVAL))
  for (mth in METHODS) {
    cm <- cell_of(eng, mth)
    out <- p3_eval_pair_safe(X, eng, mth, cm, cr, EVS[[cm$code]], EVS[[cr$code]])
    TBL[[cm$code]] <- out$tbl; out$tbl <- NULL; OUT[[cm$code]] <- out
  }
}
TB <- rbindlist(TBL)
rv <- p3_round_verdict(TB)
sel <- lapply(rv$both, function(m) {
  xs <- Filter(function(x) identical(x$method, m), OUT); tags <- p3_candidate_tags(xs)
  list(method = m, catalog_id = P3R03_METHODS[[m]]$catalog, tag = if (length(tags)) paste0("구성 부품 후보(", paste(tags, collapse = " · "), ")") else "구성 부품 후보",
       dc_gain_mean = mean(vapply(xs, function(x) x$decisive$a_median$rx0 - x$decisive$a_median$variant, numeric(1))))
})
if (length(sel)) sel <- sel[order(-vapply(sel, `[[`, numeric(1), "dc_gain_mean"))]
excl <- lapply(rv$excluded, function(m) list(method = m, concentration = unique(vapply(Filter(function(x) identical(x$method, m), OUT),
                                                                                         function(x) as.character(x$concentration$status %||% "NA"), character(1)))))
res <- list(schema = "p3r03_evaluation_v2", evaluated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), prereg_md5 = rk_md5(PR),
            evaluate_md5 = rk_md5(file.path(RD, "evaluate.R")), cells = OUT, table = TB, verdict = rv$verdict, verdict_label = rv$label,
            n_judged = rv$n_judged, n_total = rv$n_total, pass_both = rv$both, pass_one = rv$one, excluded = excl, selected = sel,
            engine_alpha = as.list(X$ea), fingerprint = list(eval = FP_EVAL, eval_record = p3_fingerprint(RD, "record"), groups = FPG),
            precheck = fromJSON(pc, simplifyVector = FALSE))
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(RES, "evaluation.json"), useBytes = TRUE)
for (x in OUT) cat(sprintf("[P3R03 평가] %s %s — %s%s · 창 %s · a %s b %s c %s d %s e %s · S비열등 %s · 알파 %s · β짝 %s · 집중 %s\n", x$engine, x$method, x$verdict,
                           if (!isTRUE(x$tested)) paste0("(", x$why, ")") else "", x$window %||% "-", isTRUE(x$decisive$a_median$ok), isTRUE(x$decisive$b_majority$ok),
                           isTRUE(x$decisive$c_participation$ok), isTRUE(x$decisive$d_deep$ok), isTRUE(x$decisive$e_path$ok), isTRUE(x$non_inferiority$ok),
                           isTRUE(x$alpha_non_loss$ok), x$beta_matched$status %||% "-", x$concentration$status %||% "-"))
pj <- function(x) if (length(x)) paste(x, collapse = ",") else "-"
cat(sprintf("[P3R03 평가] 판정 %s · 두 엔진 통과 %s · 한 엔진 %s · 집중 제외 %s · 평가 지문 = 측정 지문 %s\n", rv$label, pj(rv$both), pj(rv$one), pj(rv$excluded),
            paste(vapply(names(FPG), function(e) sprintf("%s:%s", e, FPG[[e]]$eval_matches_measure), ""), collapse = " ")))
}
