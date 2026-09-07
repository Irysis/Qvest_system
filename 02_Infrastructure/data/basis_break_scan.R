#==============================================================================
# basis_break_scan.R — **원천 내부** 수정주가 기준 단절 스캐너 (구멍 B)
#
# 2026-09-07 신설. seam_scale_guard.R 의 자매 파일이고 **같은 설정·같은 어휘**를 쓴다
# (seam_guard_config.json 단일 정본).
#
# ─── 왜 (seam_scale_guard.R 가 못 보는 자리) ─────────────────────────────────
# 이음매 가드는 `source` 열이 바뀌는 경계만 본다. 실측(2026-09-07) 전환점은 단 2개다:
#   quantiwise(1990-01-05~2026-03-27) → quantiwise_update(03-30~08-28) → naver(08-31~09-04)
# 그런데 조정기준은 **한 원천 안에서도** 끊긴다 — 같은 벤더의 수출 시점이 다르면 그 사이
# 액면분할이 소급 반영/미반영으로 갈린다. 전기간 후보(|Ret|>SEAM_MAX_RET) 2,342행 중
# 위 두 전환일에 있는 것은 일부뿐이고, 나머지는 아무 가드도 보지 않았다.
#
# ─── 판정축: 크기가 아니라 **발행주식수 불변성** ─────────────────────────────
# ★크기(|Ret|)로 판정하면 안 된다. 2026년 변동성은 실제였고(정리매매·하한가 연속),
#   진짜 급등락을 기준 단절로 오판해 지우면 그게 더 큰 오염이다.
#
# 쓰는 지문은 셋이고, 첫째가 결정적이다.
#
#   ① 발행주식수 = Size / Close   (Size = 시가총액. 실측 커버리지 1990~2026 전 버킷 100%)
#      · 액면분할/병합 = 주식수가 배수로 **변하고** 시가총액은 그대로다.
#      · 진짜 급등락   = 주식수 **그대로**이고 시가총액이 가격만큼 움직인다.
#      실측 분리도(2026-09-07):
#        정상일 n=14,082,618 → |r_shares-1| 중앙값 0 · q99 = 0.00122
#        확정 단절 n=275     → |r_shares-1| **최솟값 0.2498** · 중앙값 0.80
#      두 자릿수 배로 갈라져 **겹치지 않는다**. 전 후보 히스토그램도 이봉이고
#      사이 대역은 16건뿐이다(→ BASIS_SHARES_TOL 는 빈 골짜기에 놓인 값).
#
#   ② 시가총액 연속성 — 기준 단절이면 시총은 그날의 **진짜 하루 등락**만큼만 움직인다.
#      실측: 확정 단절 275건의 |r_size-1| 최댓값이 **정확히 0.30000** = 가격제한폭.
#      ⇒ 그래서 **진짜 수익률 = r_size - 1** 로 직접 회수된다(정수배 스냅이 필요 없다).
#
#   ③ 정수배 지문 (seam_scale_candidates() 재사용) — 독립 계기로서의 교차검증.
#
# ★양성 대조 (두 계기가 같은 답을 내는가): 2026-03-30 확정 단절에서
#     median |ret_snap - ret_size| = 0,  median |k_snap / (1/r_shares) - 1| = 0.
#   정수배 스냅(③)과 시총 불변성(①②)이 **정확히 일치**한다. 서로를 검증한다.
#
# ─── 처분 ────────────────────────────────────────────────────────────────────
# 이 스캐너는 **가격을 고치지 않는다**. 레벨 재척도는 파급이 크고(02_Infrastructure
# 안에서만 Close*Vol 소비가 72파일), 무엇보다 아래 불변성을 **깨뜨린다**:
#
#   거래대금 = Close x Vol 이고, 분할은 Close 를 x k · Vol 을 x 1/k 로 움직인다
#   ⇒ **거래대금은 기준 불변**이다. 가격만 고치면 거래대금이 배수만큼 틀어진다.
#
# 실측이 그 불변성을 확인한다(구멍 A 의 답 — 아래 basis_leg_check 주석 참조).
# 남는 것은 **한쪽 다리만 재척도된** 잔여이고, 그때의 처분은 수정이 아니라 차단이다.
#
# 사용법:
#   source(file.path(DATA_DIR, "basis_break_scan.R"))
#   res <- basis_break_scan(raw)                       # 전기간 스윕
#   res <- basis_leg_check(raw, res)                   # 거래대금 다리 정합
#   basis_break_write_registry(res, path)              # 06_Registry 등재
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# seam_scale_guard.R 를 먼저 싣는다 — 설정 로더(seam_guard_config)와 정수배 후보
# (seam_scale_candidates)를 **재사용**한다. 같은 상수를 두 번 정의하면 한쪽만 고쳐진다.
if (!exists("seam_guard_config", mode = "function")) {
  .bbs_self <- tryCatch({
    a <- commandArgs(trailingOnly = FALSE)
    f <- sub("^--file=", "", a[grepl("^--file=", a)])
    if (length(f)) dirname(normalizePath(f[1], mustWork = FALSE)) else NULL
  }, error = function(e) NULL)
  .bbs_cands <- c(
    if (!is.null(.bbs_self)) file.path(.bbs_self, "seam_scale_guard.R"),
    file.path(gsub("\\\\", "/", Sys.getenv("QM_ROOT", "")),
              "02_Infrastructure/data/seam_scale_guard.R"),
    file.path(gsub("\\\\", "/", Sys.getenv("CLAUDE_PROJECT_DIR", "")),
              "02_Infrastructure/data/seam_scale_guard.R"))
  .bbs_hit <- .bbs_cands[nzchar(.bbs_cands) & file.exists(.bbs_cands)]
  if (!length(.bbs_hit))
    stop("[basis_break] seam_scale_guard.R 미발견 — 설정 로더를 재정의하지 말 것(하드코딩 금지)")
  source(.bbs_hit[1])
}

#' 원천 내부 스캐너 설정 — seam_guard_config.json 을 그대로 쓰고 추가 키만 검증한다.
basis_break_config <- function(...) {
  cfg <- seam_guard_config(...)
  req <- c("BASIS_SHARES_TOL", "BASIS_LEG_WINDOW_SESSIONS", "BASIS_LEG_MAX_LOG2")
  miss <- setdiff(req, names(cfg))
  if (length(miss))
    stop("[basis_break] 설정 키 결손: ", paste(miss, collapse = ", "),
         " — 문턱을 코드에 되살리지 말 것(하드코딩 금지)")
  cfg
}

#' 판정 — 벡터화. **크기가 아니라 발행주식수 불변성**이 축이다.
#'
#' @param r_close  Close_t / Close_{t-1}   (직전 **유효** 종가 대비)
#' @param r_size   Size_t  / Size_{t-1}    (시가총액 비율)
#' @return character vector of verdicts
basis_break_classify <- function(r_close, r_size, cfg = basis_break_config()) {
  n <- length(r_close)
  r_size <- rep_len(r_size, n)
  tol_sh  <- as.numeric(cfg$BASIS_SHARES_TOL)
  max_ret <- as.numeric(cfg$SEAM_MAX_RET)

  r_shares <- r_size / r_close                    # 발행주식수 비율
  bad <- !is.finite(r_close) | r_close <= 0 | !is.finite(r_size) | r_size <= 0

  shares_changed <- is.finite(r_shares) & abs(r_shares - 1) > tol_sh
  cap_continuous <- is.finite(r_size) & abs(r_size - 1) <= max_ret

  out <- rep(NA_character_, n)
  out[!bad & !shares_changed] <- "real_market_event"
  out[!bad &  shares_changed &  cap_continuous] <- "adjustment_basis_break"
  out[!bad &  shares_changed & !cap_continuous] <- "undecidable"
  out[bad] <- "no_measure"
  out
}

#' 판정 → 처분. ★진짜 시장 사건은 **무처치**다 — 지우는 것이 더 큰 오염이다.
basis_action_for <- function(verdict) {
  fifelse(verdict == "real_market_event", "none",
    fifelse(verdict == "no_measure", "no_measure", "block_liquidity_window"))
}

#' 후보 생성 — 종목별 직전 **유효** 종가 대비 비율이 하루 상한을 넘는 자리.
#'
#' ★`source` 전환을 보지 않는다. 전환점은 이미 seam_scale_guard 가 본다 — 여기서는
#'   원천 내부까지 포함해 **전기간 전종목**을 훑는다(그것이 구멍 B 다).
basis_break_candidates <- function(dt, cfg = basis_break_config()) {
  stopifnot(is.data.table(dt))
  need <- c("Date", "Ticker", "Close", "Size")
  miss <- setdiff(need, names(dt))
  if (length(miss)) stop("[basis_break] 열 결손: ", paste(miss, collapse = ", "))

  v <- dt[is.finite(Close) & Close > 0]
  if (!nrow(v)) return(v[0][, .(Date, Ticker)])
  setorder(v, Ticker, Date)
  sess <- sort(unique(v$Date))
  v[, .si := match(Date, sess)]
  v[, `:=`(.pc = shift(Close), .ps = shift(Size),
           .pd = shift(Date),  .psi = shift(.si)), by = Ticker]
  v <- v[is.finite(.pc) & .pc > 0]
  v[, r_close := Close / .pc]
  v[, r_size := fifelse(is.finite(Size) & Size > 0 & is.finite(.ps) & .ps > 0,
                        Size / .ps, NA_real_)]
  v[abs(r_close - 1) > as.numeric(cfg$SEAM_MAX_RET)]
}

#' 전기간 스윕 — 후보 생성 + 판정 + 정수배 교차검증.
#'
#' @return data.table(Date, Ticker, prev_date, prev_close, Close, prev_size, Size,
#'                    r_close, r_size, r_shares, verdict, action,
#'                    implied_scale, implied_ret, snap_scale, snap_agrees, gap_sessions)
basis_break_scan <- function(dt, cfg = basis_break_config()) {
  cd <- basis_break_candidates(dt, cfg)
  if (!nrow(cd))
    return(data.table(Date = as.Date(character(0)), Ticker = character(0),
                      verdict = character(0), action = character(0)))

  cd[, r_shares := r_size / r_close]
  cd[, verdict := basis_break_classify(r_close, r_size, cfg)]
  cd[, action := basis_action_for(verdict)]

  # 기준 단절이면: 배율 = 1/r_shares, **진짜 수익률 = r_size - 1** (시총이 곧 값이다)
  cd[, implied_scale := fifelse(verdict == "adjustment_basis_break", 1 / r_shares, NA_real_)]
  cd[, implied_ret   := fifelse(verdict == "adjustment_basis_break", r_size - 1, NA_real_)]

  # ── 교차검증(독립 계기): 정수배 스냅이 같은 배율을 주는가 ──────────────────
  cand <- seam_scale_candidates(cfg)
  snap_tol <- as.numeric(cfg$SCALE_SNAP_TOL)
  cd[, snap_scale := vapply(r_close, function(r) {
        if (!is.finite(r) || r <= 0) return(NA_real_)
        h <- cand[abs(r / cand - 1) <= snap_tol]
        if (length(h) == 1L) h else NA_real_
      }, numeric(1))]
  cd[, snap_agrees := is.finite(snap_scale) & is.finite(implied_scale) &
                      abs(snap_scale / implied_scale - 1) <= snap_tol]

  cd[, gap_sessions := as.integer(.si - .psi)]
  setnames(cd, c(".pd", ".pc", ".ps"), c("prev_date", "prev_close", "prev_size"))
  keep <- c("Date", "Ticker", "prev_date", "prev_close", "Close", "prev_size", "Size",
            "r_close", "r_size", "r_shares", "verdict", "action",
            "implied_scale", "implied_ret", "snap_scale", "snap_agrees", "gap_sessions")
  extra <- intersect(c("source", "AdminStock", "TradingHalt"), names(cd))
  out <- cd[, c(keep, extra), with = FALSE]
  setorder(out, Date, Ticker)
  out[]
}

#' 거래대금 **다리 정합** 검사 (구멍 A 의 측정 지점).
#'
#' ─── 왜 이 검사이고 왜 레벨 재척도가 아닌가 (2026-09-07 실측) ────────────────
#' 액면분할은 Close 를 x k, Vol 을 x 1/k 로 움직인다 ⇒ 거래대금(Close*Vol)은 **원리적으로
#' 기준 불변**이다. 실측이 그대로 확인한다 — 2026-03-30 확정 단절 275건의 하루 거래대금
#' 비율 분포(q25 0.573 · q50 0.858 · q75 1.537)가 같은 날 정상 종목 2,200건
#' (q25 0.632 · q50 0.857 · q75 1.247)과 사실상 같다. 창(10세션 중앙값)으로 넓혀도
#' 기준단절 343건(q25 0.610 · q50 0.867 · q75 1.377) vs 무작위 대조 1,437건
#' (q25 0.644 · q50 0.916 · q75 1.378) — 중앙 |log2| 0.616 vs 0.557.
#'
#' ⇒ **adv20 이 기준 단절을 가로질러도 이미 한 기준 위에 있다.** 두 배수가 상쇄되기 때문이다.
#'    가격 레벨만 한 기준으로 재척도하면 이 상쇄가 깨져 거래대금이 배수만큼 틀어진다
#'    (그리고 Close*Vol 소비자가 02_Infrastructure 안에만 72파일이다).
#'
#' 남는 위험은 **한쪽 다리만 재척도된** 경우뿐이다. 그것을 이 함수가 잰다:
#'   |log2(창 거래대금 비율)| > BASIS_LEG_MAX_LOG2 → 다리 불일치 의심 → 그 창 차단.
#' ★대조가 이미 6.1% 이므로 이 검사는 **선별기**다 — 그래서 처분이 수정이 아니라 차단이다.
#'
#' @param dt   Date/Ticker/Close/Vol 을 가진 data.table
#' @param brk  basis_break_scan() 결과
#' @return brk + (tv_before, tv_after, tv_ratio, leg_consistent)
basis_leg_check <- function(dt, brk, cfg = basis_break_config()) {
  stopifnot(is.data.table(dt), is.data.table(brk))
  if (!nrow(brk)) return(brk)
  if (!all(c("Vol", "Close") %in% names(dt))) stop("[basis_break] Vol/Close 필요")
  W <- as.integer(cfg$BASIS_LEG_WINDOW_SESSIONS)
  maxl2 <- as.numeric(cfg$BASIS_LEG_MAX_LOG2)

  x <- dt[is.finite(Close) & Close > 0 & is.finite(Vol) & Vol > 0,
          .(Date, Ticker, .tv = Close * Vol)]
  sess <- sort(unique(dt$Date))
  x[, .si := match(Date, sess)]
  setkey(x, Ticker)

  si_brk <- match(brk$Date, sess)
  tvb <- rep(NA_real_, nrow(brk)); tva <- rep(NA_real_, nrow(brk))
  for (i in seq_len(nrow(brk))) {
    s <- si_brk[i]
    if (is.na(s)) next
    y <- x[.(brk$Ticker[i]), .(.si, .tv), nomatch = NULL]
    if (!nrow(y)) next
    b <- y[.si < s & .si >= s - W]$.tv
    a <- y[.si >= s & .si < s + W]$.tv
    # 표본이 셋 미만이면 중앙값이 잡음이다 — 재지 않고 NA(미측정)로 남긴다
    if (length(b) >= 3L) tvb[i] <- median(b)
    if (length(a) >= 3L) tva[i] <- median(a)
  }
  brk[, `:=`(tv_before = tvb, tv_after = tva)]
  brk[, tv_ratio := tv_after / tv_before]
  brk[, leg_consistent := fifelse(is.finite(tv_ratio) & tv_ratio > 0,
                                  abs(log2(tv_ratio)) <= maxl2, NA)]
  # 기준 단절인데 다리가 어긋나면 유동성 창을 차단한다. 정합이면 거래대금은 불변이므로
  # 무처치가 옳다 — 상쇄되는 것을 '고치면' 그때 오염이 생긴다.
  brk[verdict == "adjustment_basis_break",
      action := fifelse(is.na(leg_consistent), "no_measure",
                 fifelse(leg_consistent, "none", "block_liquidity_window"))]
  brk[]
}

#' 레지스트리 등재 — 06_Registry. 결정이 아니라 **측정 결과**이지만, 소비자
#' (liquidity_basis.R)가 조인하는 계약면이라 원장 층에 둔다.
basis_break_write_registry <- function(brk, path, cfg = basis_break_config(),
                                       scope = list()) {
  stopifnot(is.data.table(brk))
  b <- copy(brk)
  for (cl in intersect(c("Date", "prev_date"), names(b)))
    b[, (cl) := as.character(get(cl))]
  cnt <- if (nrow(b)) as.list(table(b$verdict)) else list()
  act <- if (nrow(b)) as.list(table(b$action)) else list()

  payload <- list(
    schema = "basis_break_registry_v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    purpose = paste0(
      "원천 **내부** 수정주가 기준 단절의 전기간 실측. seam_scale_guard.R 가 보는 ",
      "`source` 전환 경계 **밖**까지 훑는다. 판정축 = 발행주식수(Size/Close) 불변성 — ",
      "크기(|Ret|)가 아니다. 진짜 급등락(정리매매·하한가 연속)을 기준 단절로 오판해 ",
      "지우면 그것이 더 큰 오염이므로, real_market_event 는 **무처치**다."),
    axis = list(
      primary = "shares_outstanding = Size / Close — 분할은 주식수를 바꾸고 시총을 남긴다; 진짜 사건은 주식수를 남기고 시총을 바꾼다",
      secondary = "market_cap continuity — 기준 단절이면 |r_size-1| 은 하루 등락 안(실측 확정단절 최댓값 = 정확히 0.30 = 가격제한폭)",
      cross_check = "정수배 스냅(seam_scale_candidates) — 독립 계기. 2026-03-30 확정단절에서 두 계기의 배율이 정확히 일치(median 편차 0)"),
    scope = scope,
    config = cfg[c("SEAM_MAX_RET", "SCALE_SNAP_TOL", "BASIS_SHARES_TOL",
                   "BASIS_LEG_WINDOW_SESSIONS", "BASIS_LEG_MAX_LOG2", "config_path")],
    counts = list(rows = nrow(b), tickers = length(unique(b$Ticker)),
                  by_verdict = cnt, by_action = act),
    entries = b)

  js <- jsonlite::toJSON(payload, auto_unbox = TRUE, digits = 10, na = "null", pretty = TRUE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp", Sys.getpid())
  writeLines(js, tmp, useBytes = TRUE)
  if (file.exists(path)) file.remove(path)
  file.rename(tmp, path)
  path
}

#' 요약 1줄 — 침묵 통과 금지.
basis_break_print <- function(brk) {
  cat(sprintf("[basis_break] 후보 %d행 / %d종목\n", nrow(brk), length(unique(brk$Ticker))))
  if (!nrow(brk)) return(invisible(brk))
  tv <- sort(table(brk$verdict), decreasing = TRUE)
  for (i in seq_along(tv)) cat(sprintf("    %-26s %5d\n", names(tv)[i], tv[i]))
  cat("    -- 처분 --\n")
  ta <- sort(table(brk$action), decreasing = TRUE)
  for (i in seq_along(ta)) cat(sprintf("    %-26s %5d\n", names(ta)[i], ta[i]))
  invisible(brk)
}

cat("[basis_break_scan] Loaded. basis_break_scan() / basis_leg_check() / basis_break_write_registry()\n")
