#==============================================================================
# distribution_target_screen.R — 분포-표적(distribution-target) 측정 계약 v1.0
#
# 발효: 2026-08-22 (도훈 권한 위임 — .claude/rules/measurement-graduation.md §3
#       `DISTRIBUTION_TARGET` 라우트 신설의 측정 경로 구현).
#
# ── 왜 이 계약이 필요한가 (실측 근거, 2026-08-22 세 라운드 독립 수렴) ─────────
#   FQ-236 Lane D : flow 채널 t +2.98/+3.08 (추세제거 +2.40/+3.27) — 분포 귀결 부재
#   FQ-233/241 A  : cor(왜도기울기, 중앙값−평균 gap) −0.728 · 청정창 −0.546 유지
#   FQ-234 Lane B : 중앙값 스프레드 직교화 후 NW-t 3.551 vs **평균 스프레드 t 0.21**
#   ⇒ 신호가 분포(중앙값·왜도)에 있는데 소비면이 전부 평균을 읽는다.
#      담을 계약이 없어 라우팅 자체가 불가능했다. 이 파일이 그 그릇이다.
#
# ── 설계 (canonical_screen_bt.R 과 **평행**, 표적만 분포) ─────────────────────
#   · canonical_screen_bt : top-N EW 포트 → 성과(PORT_t/IR/SR) — 평균 basis
#   · 본 계약             : 분위 조건부 **분포 형상** → 스프레드/왜도/꼬리확률
#   라벨 규약(metric_type)·NW-t 산출기(.nw_t_mean)·PIT 책임 분담은 기존 계약 승계.
#   **새 규약을 만들지 않는다** — 기존 규약을 따른다.
#
# ── ★자본 우회 물리적 차단 (헌법 §3 "분포 증거는 자본 tier 에 자격을 주지 않는다") ──
#   ① 반환 객체는 `capital_eligible = FALSE` 를 **하드코딩**한다(인자로 못 바꾼다).
#   ② PORT_t / oos_retention / calmar / SR / IR / MDD / CAGR 필드를 **아예 만들지 않는다**.
#   ③ `dt_assert_no_capital_fields()` 가 반환 직전과 게이트 입력에서 **양쪽** 검사한다 —
#      호출자가 손으로 자본 필드를 주입해 게이트를 통과시키려는 시도를 차단.
#      (교훈: 유일한 이음매는 함수 인자다 — env·관례로는 격리가 안 만들어진다.
#       memory project-test-harness-contaminates-production-registry-20260822)
#
# ── PIT (C1 rolling only) ────────────────────────────────────────────────────
#   · 분위 버킷 = 월별 횡단면 `frank(score)` → 시계열 통계 미사용
#   · 초과수익 ex = Ret_1m − mean(Ret_1m) **by Date** (횡단면 demean, 결과량)
#   · 직교화 = **월별 횡단면 OLS** (`by = Date`). pooled/full-sample 회귀는 **거부**한다.
#   · winsorize = 월별 횡단면 분위 (full-sample 분위 아님)
#   · 꼬리 문턱 = `fixed`(사전지정 상수) 또는 `rolling`(직전 N개월 **풀링**, skip 적용).
#     `fullsample` 은 **stop()** — 결과를 보고 문턱을 정하는 경로를 코드가 막는다.
#   · shape_profile(분위별 형상표)만 창-전체 풀링 = **진단 전용·판정 비바인딩**으로 라벨.
#
# 검사기: 08_Tests/contracts/test_distribution_target_screen.R (양방향 위반 주입)
# 소비자: 02_Infrastructure/hurdle_gate.R (라우트 발급) →
#         02_Infrastructure/portfolio/distribution_target_queue.R (라우트 소비 원장)
#==============================================================================

suppressMessages({
  library(data.table)
})

DTS_CONTRACT_VERSION <- "distribution_target_screen_v1.0"

# 자본 tier 필드 금칙 — 이름에 이 패턴이 있으면 분포 계약 객체에 존재해선 안 된다.
#   ★목록이 아니라 **정규식**이다: port_t / portfolio_alpha_t_nw_lag3 / net_sr 등
#   변형을 모두 덮는다. 새 자본 지표가 생기면 여기 한 곳만 추가한다(사본 금지).
DTS_CAPITAL_FIELD_PATTERNS <- c(
  "portfolio_alpha", "port_t", "^alpha_t$", "alpha_annualized",
  "oos_retention", "calmar", "sharpe", "net_sr", "\\bsr\\b",
  "information_ratio", "net_ir", "\\bir\\b",
  "mdd", "max_drawdown", "drawdown",
  "cagr", "ann_ret", "annualized_return",
  "deflated_sharpe", "\\bdsr\\b", "book_marginal", "delta_ir"
)

#------------------------------------------------------------------------------
# 계약 로더 — .nw_t_mean 재사용 (자체합성 금지: NW-t 를 다시 구현하지 않는다)
#   r-portability ④: CLAUDE_PROJECT_DIR 우선 + **정체성 검사**(대상 파일 실재)로 루트 확정.
#   r-portability ③: 선행 "/" 하드코딩 금지 — 상대경로 fallback 만 둔다.
#------------------------------------------------------------------------------
.DTS_DIR <- local({
  ok <- function(d) is.character(d) && length(d) == 1L && !is.na(d) && nzchar(d) &&
    file.exists(file.path(d, "backtest_result_contract.R"))
  cand <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA_character_)
  if (ok(cand)) cand else {
    root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "."))
    d2 <- file.path(root, "02_Infrastructure/contracts")
    if (ok(d2)) d2 else "02_Infrastructure/contracts"
  }
})
local({
  f <- file.path(.DTS_DIR, "backtest_result_contract.R")
  if (file.exists(f) && !exists(".nw_t_mean", mode = "function")) suppressMessages(source(f))
})

# NW lag-3 t — 계약 함수만 쓴다. 미로드면 NA(자체 재구현 금지, canonical_screen_bt 와 동일 규약).
.dts_nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (!exists(".nw_t_mean", mode = "function")) return(NA_real_)
  .nw_t_mean(x, lag = lag)
}

.dts_num <- function(x) if (is.null(x) || length(x) == 0L) NA_real_ else suppressWarnings(as.numeric(x[1]))

#------------------------------------------------------------------------------
# dt_assert_no_capital_fields — 자본 필드 주입 차단 (재귀 이름 스캔)
#------------------------------------------------------------------------------
#' @param x list/data.frame — 검사 대상
#' @param where 오류 메시지에 찍을 맥락 라벨
#' @param max_depth 재귀 상한 (순환/과대 구조 방어)
#' @return invisible(TRUE) — 위반 시 stop()
#' @details 이름만 본다(값 아님). 분포 계약은 자본 수치를 **산출하지 않으므로**
#'   그런 이름이 존재한다는 사실 자체가 계약 위반이다. 헌법 §1(proxy 손계산 금지)·
#'   §3(분포 통계로 HARD 3종 대체 금지) 정합.
dt_assert_no_capital_fields <- function(x, where = "distribution_screen", max_depth = 8L) {
  hits <- character(0)
  walk <- function(node, path, depth) {
    if (depth > max_depth) return(invisible(NULL))
    nms <- names(node)
    if (!is.null(nms)) {
      for (i in seq_along(nms)) {
        nm <- nms[i]
        if (!nzchar(nm)) next
        lo <- tolower(nm)
        for (p in DTS_CAPITAL_FIELD_PATTERNS) {
          if (grepl(p, lo, perl = TRUE)) {
            hits <<- c(hits, paste0(paste(c(path, nm), collapse = "$"), "  [패턴 ", p, "]"))
            break
          }
        }
      }
    }
    if (is.list(node) && !is.data.frame(node)) {
      for (i in seq_along(node)) {
        nm <- if (!is.null(nms) && nzchar(nms[i])) nms[i] else paste0("[[", i, "]]")
        walk(node[[i]], c(path, nm), depth + 1L)
      }
    }
    invisible(NULL)
  }
  walk(x, character(0), 1L)
  if (length(hits)) {
    stop(sprintf(paste0(
      "[dt_assert_no_capital_fields] %s 에 자본 tier 필드가 존재한다 — 분포-표적 계약은 ",
      "PORT_t/oos_retention/calmar/SR/IR/MDD 를 **설계상 산출하지 않는다**.\n",
      "  위반 필드 %d개:\n    %s\n",
      "  근거: .claude/rules/measurement-graduation.md §3 — 분포 통계량으로 HARD 3종을 ",
      "대체·근사하는 주장은 §1 위반. 자본 판정은 forge-authoritative 포트폴리오 수치로만."),
      where, length(hits), paste(hits, collapse = "\n    ")), call. = FALSE)
  }
  invisible(TRUE)
}

#------------------------------------------------------------------------------
# 월별 횡단면 유틸 (전부 by=Date — 시계열 full-sample 통계 없음)
#------------------------------------------------------------------------------
.dts_wins_by_date <- function(X, col, probs) {
  if (is.null(probs)) return(invisible(NULL))
  stopifnot(length(probs) == 2L, probs[1] < probs[2])
  X[, (col) := {
    q <- stats::quantile(get(col), probs, na.rm = TRUE, names = FALSE)
    pmin(pmax(get(col), q[1]), q[2])
  }, by = Date]
  invisible(NULL)
}

.dts_z_by_date <- function(v) {
  s <- stats::sd(v, na.rm = TRUE)
  if (!is.finite(s) || s <= 0) return(rep(NA_real_, length(v)))
  (v - mean(v, na.rm = TRUE)) / s
}

# 월별 횡단면 OLS 직교화. pooled 회귀는 **호출 자체가 불가**하도록 인자를 두지 않는다.
.dts_orthogonalize_by_date <- function(X, score_col, control_cols, out_col) {
  fml <- stats::as.formula(paste0("`", score_col, "` ~ ",
                                  paste(sprintf("`%s`", control_cols), collapse = " + ")))
  X[, (out_col) := {
    d <- .SD
    fit <- try(stats::lm(fml, data = d), silent = TRUE)
    r <- if (inherits(fit, "try-error")) rep(NA_real_, .N) else as.numeric(stats::residuals(fit))
    # 길이 불일치(NA 제거로 행이 줄어든 경우)는 값을 위장하지 않고 통째로 NA
    if (length(r) != .N) rep(NA_real_, .N) else .dts_z_by_date(r)
  }, by = Date, .SDcols = c(score_col, control_cols)]
  invisible(NULL)
}

#------------------------------------------------------------------------------
# 꼬리 문턱 — fixed / rolling 만. fullsample 은 거부(C1).
#------------------------------------------------------------------------------
#' @return data.table(Date, thr_up, thr_dn) — 문턱을 못 세운 달은 NA (0 으로 위장 금지)
.dts_tail_thresholds <- function(EX, mode, fixed_up, fixed_dn,
                                 window, prob, skip, min_history_months) {
  dts <- sort(unique(EX$Date))
  if (identical(mode, "fixed")) {
    return(data.table(Date = dts, thr_up = fixed_up, thr_dn = fixed_dn))
  }
  if (identical(mode, "fullsample")) {
    stop(paste0("[dt] tail_threshold_mode='fullsample' 은 거부한다 — PIT C1 위반",
                "(전기간 분위로 문턱을 정하면 결과를 보고 문턱을 정하는 것). ",
                "'fixed'(사전지정 상수) 또는 'rolling'(직전 N개월 풀링)만 허용."), call. = FALSE)
  }
  # rolling: t 의 문턱 = 인덱스 [i-skip-window, i-skip-1] 달의 ex 풀링 분위.
  #   skip>=1 이면 풀링 구간의 수익이 Date_i **이전에 이미 실현**된다(경계 안전).
  by_date <- split(EX$ex, EX$Date)
  out <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    hi <- i - skip - 1L
    lo <- max(1L, i - skip - window)
    if (hi < lo || (hi - lo + 1L) < min_history_months) {
      out[[i]] <- data.table(Date = dts[i], thr_up = NA_real_, thr_dn = NA_real_)
      next
    }
    pool <- unlist(by_date[as.character(dts[lo:hi])], use.names = FALSE)
    pool <- pool[is.finite(pool)]
    if (length(pool) < 30L) {
      out[[i]] <- data.table(Date = dts[i], thr_up = NA_real_, thr_dn = NA_real_)
      next
    }
    out[[i]] <- data.table(Date = dts[i],
                           thr_up = stats::quantile(pool, prob, names = FALSE),
                           thr_dn = stats::quantile(pool, 1 - prob, names = FALSE))
  }
  rbindlist(out)
}

#------------------------------------------------------------------------------
# 한 축(raw 또는 직교화)의 월별 분포 통계 시계열 → NW-t 집계
#------------------------------------------------------------------------------
.dts_axis_stats <- function(X, key, THR, n_quantiles, q_hi, q_lo,
                            quantile_probs, min_obs_per_date, nw_lag) {
  S <- X[is.finite(get(key)) & is.finite(Ret_1m)]
  S <- S[, if (.N >= min_obs_per_date) .SD, by = Date]
  if (nrow(S) == 0L) {
    return(list(available = FALSE, n_months = 0L, n_obs = 0L,
                note = "유효 관측 0 — 축 산출 불가"))
  }
  S <- copy(S)
  S[, .g  := cut(frank(get(key)), breaks = n_quantiles, labels = FALSE), by = Date]
  S[, .ex := Ret_1m - mean(Ret_1m), by = Date]
  S <- merge(S, THR, by = "Date", all.x = TRUE)

  skew1 <- function(v) {
    v <- v[is.finite(v)]
    s <- stats::sd(v)
    if (length(v) < 3L || !is.finite(s) || s <= 0) return(NA_real_)
    mean((v - mean(v))^3) / s^3
  }

  M <- S[, {
    hi <- .ex[.g == q_hi]; lo <- .ex[.g == q_lo]
    tu <- thr_up[1]; td <- thr_dn[1]
    # 분위별 왜도 → 분위 인덱스에 대한 기울기(조건부 왜도 프로파일의 1차 요약)
    sk <- vapply(seq_len(n_quantiles), function(k) skew1(.ex[.g == k]), numeric(1))
    gi <- seq_len(n_quantiles)
    okk <- is.finite(sk)
    sl <- if (sum(okk) >= 3L) {
      gg <- gi[okk]; ss <- sk[okk]
      stats::cov(gg, ss) / stats::var(gg)
    } else NA_real_
    qs <- vapply(quantile_probs, function(p)
      stats::quantile(hi, p, names = FALSE) - stats::quantile(lo, p, names = FALSE), numeric(1))
    c(list(n_hi = length(hi), n_lo = length(lo),
           median_spread = stats::median(hi) - stats::median(lo),
           mean_spread   = mean(hi) - mean(lo),
           skew_hi = skew1(hi), skew_lo = skew1(lo),
           skew_spread = skew1(hi) - skew1(lo),
           skew_slope = sl,
           tail_up_prob_diff = if (is.finite(tu)) mean(hi > tu) - mean(lo > tu) else NA_real_,
           tail_dn_prob_diff = if (is.finite(td)) mean(hi < td) - mean(lo < td) else NA_real_),
      stats::setNames(as.list(qs), paste0("qspread_p", sprintf("%02d", round(quantile_probs * 100)))))
  }, by = Date]

  axis_names <- c("median_spread", "mean_spread", "skew_spread", "skew_slope",
                  "tail_up_prob_diff", "tail_dn_prob_diff",
                  paste0("qspread_p", sprintf("%02d", round(quantile_probs * 100))))
  axes <- lapply(axis_names, function(a) {
    v <- M[[a]]
    v <- v[is.finite(v)]
    list(mean = if (length(v)) mean(v) else NA_real_,
         nw_t = .dts_nw_t(v, lag = nw_lag),
         n_months = length(v))
  })
  names(axes) <- axis_names

  # 분위별 형상표 — **창 전체 풀링**이므로 진단 전용(판정 비바인딩)으로 라벨한다.
  prof <- S[, .(n = .N,
                mean   = mean(.ex),
                median = stats::median(.ex),
                p10 = stats::quantile(.ex, 0.10, names = FALSE),
                p90 = stats::quantile(.ex, 0.90, names = FALSE),
                sd = stats::sd(.ex),
                skew = skew1(.ex)), by = .g][order(.g)]
  setnames(prof, ".g", "quantile")

  list(available = TRUE,
       n_months = nrow(M), n_obs = nrow(S),
       axes = axes,
       monthly_series = M[, c("Date", axis_names), with = FALSE],
       shape_profile = list(
         metric_type = "distribution_screen_diag",
         decision_binding = FALSE,
         full_window_pooled = TRUE,
         note = "창 전체 풀링 서술표 — 판정 비바인딩. 판정 통계는 axes(월별 시계열 NW-t)만.",
         table = as.data.frame(prof)))
}

#------------------------------------------------------------------------------
# canonical_distribution_screen — 메인 계약
#------------------------------------------------------------------------------
#' 분포-표적 스크리닝 실측 (canonical_screen_bt 의 분포 평행 계약)
#'
#' @param scores_dt data.table(Date, Ticker, score) — sig_date 기준(t 에 알 수 있는 값)
#' @param returns_dt data.table(Date, Ticker, Ret_1m) — forward 실현수익
#' @param control_dt data.table(Date, Ticker, <control_cols>) — vol/size 등 통제 패널.
#'   NULL 이면 직교화 **미실행** → survival$verdict = "NOT_TESTED" 이고 라우트 발급 불가.
#' @param control_cols 통제 축 이름. 헌법 요건② = **최소 2축**(vol·size).
#' @param n_quantiles 분위 수(기본 5)
#' @param q_hi,q_lo **사전지정** 분위(기본 n_quantiles, 1)
#' @param quantile_probs 조건부 분위 스프레드 확률(기본 c(0.10,0.50,0.90))
#' @param tail_threshold_mode "fixed" | "rolling" ("fullsample" = stop, C1)
#' @param tail_fixed_up,tail_fixed_dn fixed 모드 상수 문턱(사전지정)
#' @param tail_rolling_window 직전 N개월 풀링 창(기본 36)
#' @param tail_rolling_prob rolling 상방 문턱 분위(기본 0.90; 하방은 1-p)
#' @param tail_rolling_skip 최근 skip 개월 제외(기본 1 — 풀링분 수익이 t 이전 실현 보장)
#' @param winsorize_probs 월별 횡단면 winsorize 분위. NULL = 미적용
#' @param liq_dt data.table(Date,Ticker,adv) 유동성 패널. NULL = 미적용(호출자 책임)
#' @param windows named list — 각 원소 c(start,end) Date. 요건③ = **서로 겹치지 않는 2창 이상**
#' @param t_min_survive 직교화 후 생존 |NW-t| 하한(기본 2.0, screening tier 기준)
#' @param prereg_ref 사전등록 문서 경로/식별자 — 기록용(분위 사전지정 감사 흔적)
#' @return list — `capital_eligible = FALSE` 하드코딩. 자본 필드는 **존재하지 않는다**.
canonical_distribution_screen <- function(scores_dt, returns_dt,
                                          control_dt = NULL,
                                          control_cols = c("win_vol", "log_size"),
                                          control_transform = c("raw", "rank"),
                                          n_quantiles = 5L,
                                          q_hi = NULL, q_lo = NULL,
                                          quantile_probs = c(0.10, 0.90),
                                          tail_threshold_mode = c("fixed", "rolling"),
                                          tail_fixed_up = 0.20, tail_fixed_dn = -0.20,
                                          tail_rolling_window = 36L,
                                          tail_rolling_prob = 0.90,
                                          tail_rolling_skip = 1L,
                                          tail_min_history_months = 12L,
                                          winsorize_probs = NULL,
                                          liq_dt = NULL, liq_min = 2e8,
                                          windows = NULL,
                                          min_obs_per_date = NULL,
                                          nw_lag = 3L,
                                          t_min_survive = 2.0,
                                          run_id = "distribution_screen",
                                          spec_id = "distribution_screen",
                                          prereg_ref = NULL) {

  stopifnot(all(c("Date", "Ticker", "score") %in% names(scores_dt)))
  stopifnot(all(c("Date", "Ticker", "Ret_1m") %in% names(returns_dt)))
  n_quantiles <- as.integer(n_quantiles)
  if (n_quantiles < 3L) stop("[dt] n_quantiles >= 3 필요", call. = FALSE)
  if (is.null(q_hi)) q_hi <- n_quantiles
  if (is.null(q_lo)) q_lo <- 1L
  q_hi <- as.integer(q_hi); q_lo <- as.integer(q_lo)
  if (q_hi == q_lo || q_hi > n_quantiles || q_lo < 1L)
    stop("[dt] q_hi/q_lo 사전지정이 유효하지 않다", call. = FALSE)
  if (is.null(min_obs_per_date)) min_obs_per_date <- n_quantiles * 5L
  # ★p=0.50 은 median_spread 와 **같은 통계량**이다(type-7 quantile at 0.5 == median).
  #   기본값에서 뺀 이유: 넣어두면 생존 축 집계가 같은 증거를 두 번 센다(실측 확인 —
  #   FQ-234 재현에서 survived_axes 에 median_spread 와 qspread_p50 가 동시 등장).
  #   호출자가 명시하면 막지 않되, 중복임을 경고한다(조용히 세지 않는다).
  if (any(abs(quantile_probs - 0.5) < 1e-9))
    warning(paste0("[dt] quantile_probs 에 0.50 포함 — qspread_p50 은 median_spread 와 동일 통계량이다. ",
                   "생존 축 집계에서 같은 증거가 두 번 세어진다."), call. = FALSE)

  # ★ mode 검증은 match.arg 앞에서 직접 — "fullsample" 이 조용히 fixed 로 떨어지면
  #   C1 차단이 무력화된다(결손을 정상값으로 내려앉히는 계통).
  if (length(tail_threshold_mode) == 1L && identical(tail_threshold_mode, "fullsample")) {
    stop(paste0("[dt] tail_threshold_mode='fullsample' 거부 — PIT C1. ",
                "문턱은 사전지정 상수(fixed) 또는 직전 N개월 풀링(rolling)에서만."), call. = FALSE)
  }
  tail_threshold_mode <- match.arg(tail_threshold_mode)
  control_transform <- match.arg(control_transform)

  S <- as.data.table(scores_dt)[!is.na(score)][, .(Date = as.Date(Date), Ticker, score)]
  R <- as.data.table(returns_dt)[!is.na(Ret_1m)][, .(Date = as.Date(Date), Ticker, Ret_1m)]

  # canonical_screen_bt 와 동일한 Ret_1m sanity 방화벽 (규약 승계)
  bad <- is.finite(R$Ret_1m) & (R$Ret_1m > 5.0 | R$Ret_1m < -1.0)
  n_bad <- sum(bad)
  if (n_bad > 0L) {
    warning(sprintf("[dt] Ret_1m sanity: %d 물리불가 월수익 격리 — rawdata_sanitize 미적용 vintage 의심.", n_bad))
    R <- R[!bad]
  }

  liq_applied <- FALSE; n_liq_dropped <- 0L
  liq_ruler <- attr(liq_dt, "liq_ruler", exact = TRUE)
  if (!is.null(liq_dt)) {
    L <- as.data.table(liq_dt)[, .(Date = as.Date(Date), Ticker, adv)]
    n0 <- nrow(S)
    S <- merge(S, L, by = c("Date", "Ticker"), all.x = TRUE)
    S <- S[is.na(adv) | adv >= liq_min][, adv := NULL]
    liq_applied <- TRUE; n_liq_dropped <- n0 - nrow(S)
    if (is.null(liq_ruler)) liq_ruler <- "unlabeled"
  }

  # ── winsorize 의 **적용 범위** 규약 (실측으로 확정, 2026-08-22) ────────────
  #   winsorize 는 **직교화 회귀의 좌변에만** 적용하고, 분위 버킷팅에는 적용하지 않는다.
  #   근거 두 가지:
  #     ① 버킷팅은 `frank` 기반 = 단조변환 불변이다. 극단치를 자르면 순위가 좋아지는 게
  #        아니라 **인위적 동점**이 생겨 경계 종목이 옆 버킷으로 넘어간다 —
  #        효익 없이 잡음만 넣는다.
  #     ② 회귀는 다르다. 극단치가 통제 기울기를 끌면 잔차가 통제를 덜 빼앗기므로
  #        winsorize→직교화 가 더 보수적이다.
  #   ★이 범위 구분이 값을 바꾼다(FQ-234 재현 실측):
  #     버킷에도 winsorize 적용 시 raw median_spread NW-t 3.9870 · 미적용 시 3.9928
  #     (Lane B 기록 3.992838 과 일치). 직교화 축은 두 경우 모두 3.551258 로 동일.
  #   순서·범위는 규약이며 control_spec 에 기록한다.

  # ── 통제 패널 병합 + 월별 횡단면 직교화 ────────────────────────────────────
  control_applied <- FALSE
  n_ctl_before <- nrow(S); n_ctl_after <- nrow(S)
  ctl_note <- "control_dt=NULL — 직교화 미실행"
  if (!is.null(control_dt)) {
    C <- as.data.table(control_dt)
    miss <- setdiff(control_cols, names(C))
    if (length(miss)) stop(sprintf("[dt] control_dt 에 통제 축 결측: %s", paste(miss, collapse = ", ")), call. = FALSE)
    C <- C[, c("Date", "Ticker", control_cols), with = FALSE]
    C[, Date := as.Date(Date)]
    S <- merge(S, C, by = c("Date", "Ticker"), all.x = TRUE)
    n_ctl_before <- nrow(S)
    keep <- Reduce(`&`, lapply(control_cols, function(cc) is.finite(S[[cc]])))
    S_ctl <- S[keep]
    n_ctl_after <- nrow(S_ctl)
    if (n_ctl_after > 0L) {
      # ── 통제 변수 변환 규약 (2026-08-22 실측으로 추가) ──────────────────────
      #  "raw"  : 통제 변수를 그대로 월별 z — FQ-234 Lane B 재현 규약(기본).
      #  "rank" : 월별 횡단면 **순위**로 바꾼 뒤 z — 단조 종속을 전부 제거.
      #  ★왜 선택지가 필요한가 (검사가 잡은 실제 한계):
      #    선형 직교화는 통제 변수에 대한 **비선형** 종속을 못 걷어낸다.
      #    합성 픽스처 score = −log(vol) 로 실측: raw 변환에선 통제 후에도 분포 축이
      #    살아남아 verdict=SURVIVES(=오통과)가 나온다. 같은 픽스처가 rank 변환에선
      #    DIES_UNDER_CONTROL 로 정확히 죽는다.
      #    즉 "vol 로 통제했다"는 진술은 **변환 규약을 밝히지 않으면 강도가 미정**이다.
      #    그래서 선택을 인자로 노출하고 산출물에 기록한다(숨은 기본값 금지).
      if (identical(control_transform, "rank")) {
        for (cc in control_cols) S_ctl[, (cc) := (frank(get(cc)) / .N) - 0.5, by = Date]
      }
      # 통제 축도 월별 z (Lane B 규약 승계: lm(raw ~ zc(vol) + zc(size)))
      for (cc in control_cols) S_ctl[, (cc) := .dts_z_by_date(get(cc)), by = Date]
      # 회귀 좌변만 winsorize — 원본 score(버킷팅용)는 건드리지 않는다(위 범위 규약)
      S_ctl[, score_reg := score]
      .dts_wins_by_date(S_ctl, "score_reg", winsorize_probs)
      .dts_orthogonalize_by_date(S_ctl, "score_reg", control_cols, "score_orth")
      S <- merge(S, S_ctl[, .(Date, Ticker, score_orth)], by = c("Date", "Ticker"), all.x = TRUE)
      control_applied <- TRUE
      ctl_note <- sprintf(paste0("월별 횡단면 OLS 직교화(%d축) — pooled 회귀 경로 없음(C1). ",
                                 "winsorize=%s (회귀 좌변 전용, 버킷팅 미적용)"),
                          length(control_cols),
                          if (is.null(winsorize_probs)) "none" else
                            paste0("[", paste(winsorize_probs, collapse = ","), "]"))
    } else {
      ctl_note <- "통제 축 유효행 0 — 직교화 불가"
    }
  }

  # score_orth 는 winsorize 하지 않는다 — 이미 잔차의 월별 z 이고, 여기서 다시 자르면
  #   통제가 걷어낸 분산을 되돌려 넣는 꼴이 된다(Lane B 규약과 동일).

  X0 <- merge(S, R, by = c("Date", "Ticker"))
  if (nrow(X0) == 0L) {
    out <- list(metric_type = "distribution_screen", capital_eligible = FALSE,
                n_months = 0L, note = "scores/returns 겹침 0")
    dt_assert_no_capital_fields(out, "canonical_distribution_screen(empty)")
    return(out)
  }

  if (is.null(windows)) {
    windows <- list(full = c(min(X0$Date), max(X0$Date) + 1L))
  }
  windows <- lapply(windows, function(w) as.Date(w))

  # ── 창별 산출 ──────────────────────────────────────────────────────────────
  win_out <- list()
  for (wn in names(windows)) {
    w <- windows[[wn]]
    Xw <- X0[Date >= w[1] & Date < w[2]]
    if (nrow(Xw) == 0L) {
      win_out[[wn]] <- list(window = as.character(w), available = FALSE,
                            note = "창 내 관측 0")
      next
    }
    # 꼬리 문턱은 **창 내부**에서 rolling — 창 밖 미래를 안 본다
    EXw <- copy(Xw)[, .(ex = Ret_1m - mean(Ret_1m)), by = Date]
    THR <- .dts_tail_thresholds(EXw, tail_threshold_mode,
                                tail_fixed_up, tail_fixed_dn,
                                as.integer(tail_rolling_window), tail_rolling_prob,
                                as.integer(tail_rolling_skip), as.integer(tail_min_history_months))
    raw <- .dts_axis_stats(Xw, "score", THR, n_quantiles, q_hi, q_lo,
                           quantile_probs, min_obs_per_date, nw_lag)
    orth <- if (control_applied && "score_orth" %in% names(Xw))
      .dts_axis_stats(Xw, "score_orth", THR, n_quantiles, q_hi, q_lo,
                      quantile_probs, min_obs_per_date, nw_lag)
    else list(available = FALSE, note = ctl_note)

    win_out[[wn]] <- list(
      window = as.character(w),
      n_months_raw = raw$n_months %|d|% 0L,
      tail_threshold_na_months = sum(!is.finite(THR$thr_up)),
      raw = raw,
      orthogonalized = orth
    )
  }

  # ── 요건② 생존 판정 (계약이 **강제**한다 — raw 만 반환하고 끝나지 않는다) ──
  dist_axes <- c("median_spread", "skew_spread", "skew_slope",
                 "tail_up_prob_diff", "tail_dn_prob_diff",
                 paste0("qspread_p", sprintf("%02d", round(quantile_probs * 100))))
  # mean_spread 는 **분포 축이 아니다** — 평균 공간 대조축(요건① 의 그림자). 생존 집계에서 제외.
  per_window_surv <- list()
  for (wn in names(win_out)) {
    W <- win_out[[wn]]
    if (!isTRUE(W$raw$available) || !isTRUE(W$orthogonalized$available)) {
      per_window_surv[[wn]] <- list(tested = FALSE,
                                    note = if (!isTRUE(W$orthogonalized$available)) ctl_note else "raw 미산출")
      next
    }
    ax <- lapply(dist_axes, function(a) {
      tr <- .dts_num(W$raw$axes[[a]]$nw_t)
      to <- .dts_num(W$orthogonalized$axes[[a]]$nw_t)
      surv <- is.finite(tr) && is.finite(to) && sign(tr) == sign(to) && abs(to) >= t_min_survive
      list(raw_nw_t = tr, orth_nw_t = to,
           sign_kept = is.finite(tr) && is.finite(to) && sign(tr) == sign(to),
           magnitude_ok = is.finite(to) && abs(to) >= t_min_survive,
           survives = surv,
           attenuation = if (is.finite(tr) && is.finite(to) && abs(tr) > 1e-12) to / tr else NA_real_)
    })
    names(ax) <- dist_axes
    surv_names <- dist_axes[vapply(ax, function(z) isTRUE(z$survives), logical(1))]
    per_window_surv[[wn]] <- list(tested = TRUE, axes = ax, survived_axes = surv_names,
                                  n_survived = length(surv_names))
  }
  tested_wins <- names(per_window_surv)[vapply(per_window_surv, function(z) isTRUE(z$tested), logical(1))]
  survived_any <- unique(unlist(lapply(per_window_surv[tested_wins], function(z) z$survived_axes)))
  # ★"어느 한 창에서 생존"은 창을 늘릴수록 우연히 충족된다. 더 엄한 관점(전 창 생존)을
  #   **함께 기록**해 소비자가 둘을 구분할 수 있게 한다(헌법 요건을 임의로 강화하지 않되,
  #   증거의 강도를 숨기지도 않는다).
  survived_all <- if (length(tested_wins) == 0L) character(0) else
    Reduce(intersect, lapply(per_window_surv[tested_wins], function(z) z$survived_axes))
  survival <- list(
    metric_type = "distribution_screen",
    t_min_survive = t_min_survive,
    control_cols = control_cols,
    control_axes_n = if (control_applied) length(control_cols) else 0L,
    control_axes_min_required = 2L,
    control_applied = control_applied,
    control_note = ctl_note,
    per_window = per_window_surv,
    n_windows_tested = length(tested_wins),
    survived_axes_any_window = survived_any,
    survived_axes_all_windows = if (is.null(survived_all)) character(0) else survived_all,
    survived_scope_note = paste0(
      "verdict 는 **any-window** 기준(헌법 요건② 원문). all-windows 는 더 엄한 관점으로 병기 — ",
      "창을 늘릴수록 any 는 우연히 충족되므로 소비자는 둘을 함께 읽을 것."),
    verdict = if (!control_applied) "NOT_TESTED"
              else if (length(control_cols) < 2L) "INSUFFICIENT_CONTROL_AXES"
              else if (length(survived_any) > 0L) "SURVIVES"
              else "DIES_UNDER_CONTROL"
  )

  # ── 요건③ 독립 창 부호 일치 (창 겹침 = 독립 아님 → 실패) ──────────────────
  wn_all <- names(windows)
  pairs <- list(); disjoint_any <- FALSE
  if (length(wn_all) >= 2L) {
    for (i in 1:(length(wn_all) - 1L)) for (j in (i + 1L):length(wn_all)) {
      a <- windows[[wn_all[i]]]; b <- windows[[wn_all[j]]]
      dj <- (a[2] <= b[1]) || (b[2] <= a[1])
      if (dj) disjoint_any <- TRUE
      pairs[[length(pairs) + 1L]] <- list(a = wn_all[i], b = wn_all[j], disjoint = dj)
    }
  }
  window_independence <- list(
    n_windows = length(wn_all), pairs = pairs, has_disjoint_pair = disjoint_any,
    verdict = if (length(wn_all) < 2L) "SINGLE_WINDOW"
              else if (disjoint_any) "DISJOINT_PAIR_PRESENT"
              else "OVERLAPPING_ONLY",
    note = paste0("'독립 창 2개'의 최소 기계 조건 = **서로 겹치지 않음**. ",
                  "포함관계(예: 전체창 ⊃ 청정창)는 독립이 아니다 — 같은 표본을 두 번 세는 것.")
  )

  sign_agreement <- list(verdict = "NOT_EVALUATED", per_axis = list())
  if (disjoint_any) {
    dj <- Filter(function(p) isTRUE(p$disjoint), pairs)
    pa <- list()
    for (p in dj) {
      A <- win_out[[p$a]]$orthogonalized; B <- win_out[[p$b]]$orthogonalized
      if (!isTRUE(A$available) || !isTRUE(B$available)) next
      for (a in dist_axes) {
        ta <- .dts_num(A$axes[[a]]$nw_t); tb <- .dts_num(B$axes[[a]]$nw_t)
        key <- paste0(p$a, "|", p$b, "::", a)
        pa[[key]] <- list(axis = a, t_a = ta, t_b = tb,
                          agree = is.finite(ta) && is.finite(tb) && sign(ta) == sign(tb))
      }
    }
    agreed <- unique(vapply(Filter(function(z) isTRUE(z$agree), pa),
                            function(z) z$axis, character(1)))
    sign_agreement <- list(
      verdict = if (length(agreed)) "AGREES" else if (length(pa)) "DISAGREES" else "NOT_EVALUATED",
      agreed_axes = agreed, per_axis = pa,
      note = "직교화 축 기준(raw 아님) — 요건②를 통과한 신호가 요건③도 만족하는지 물어야 한다.")
  }

  out <- list(
    metric_type = "distribution_screen",
    metric_type_note = paste0(
      "분위 조건부 **분포 형상** 실측(월별 횡단면 → NW lag-", nw_lag, " t). ",
      "성과 수치 아님 — 이 계약은 PORT_t/SR/IR/calmar/MDD 를 산출하지 않는다."),
    contract_version = DTS_CONTRACT_VERSION,

    # ★자본 우회 물리적 차단 (인자로 바꿀 수 없다 — 하드코딩)
    capital_eligible = FALSE,
    capital_note = paste0(
      "분포-공간 증거는 자본 tier 에 어떤 자격도 주지 않는다 ",
      "(.claude/rules/measurement-graduation.md §3, 2026-08-22). ",
      "graduation HARD 3종은 forge-authoritative 포트폴리오 수치로만 판정한다. ",
      "본 객체에는 해당 필드가 **존재하지 않으며**, 주입 시 dt_assert_no_capital_fields() 가 stop 한다."),

    run_id = run_id, spec_id = spec_id, prereg_ref = prereg_ref,
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),

    quantile_spec = list(n_quantiles = n_quantiles, q_hi = q_hi, q_lo = q_lo,
                         quantile_probs = quantile_probs,
                         min_obs_per_date = min_obs_per_date,
                         prespecified = TRUE,
                         note = "분위는 사전지정 인자다 — 결과를 보고 고르는 경로가 없다."),
    tail_spec = list(mode = tail_threshold_mode,
                     fixed_up = if (identical(tail_threshold_mode, "fixed")) tail_fixed_up else NA_real_,
                     fixed_dn = if (identical(tail_threshold_mode, "fixed")) tail_fixed_dn else NA_real_,
                     rolling_window = tail_rolling_window, rolling_prob = tail_rolling_prob,
                     rolling_skip = tail_rolling_skip,
                     min_history_months = tail_min_history_months,
                     fullsample_rejected = TRUE),
    control_spec = list(cols = control_cols, method = "per_date_cross_section_ols",
                        transform = control_transform,
                        transform_note = paste0(
                          "raw = 통제 변수 원값의 월별 z (Lane B 재현 규약, 기본) / ",
                          "rank = 월별 횡단면 순위 z (단조 종속 전부 제거). ",
                          "★선형 직교화는 **비선형** 종속을 못 걷어낸다 — 합성 픽스처 score=-log(vol) 는 ",
                          "raw 에서 SURVIVES(오통과)이고 rank 에서 DIES_UNDER_CONTROL 이다(실측). ",
                          "'vol 로 통제했다'는 진술은 이 필드 없이는 강도가 미정이다."),
                        applied = control_applied, n_axes = length(control_cols),
                        n_rows_before = n_ctl_before, n_rows_after = n_ctl_after,
                        winsorize_probs = winsorize_probs, winsorize_scope = "regression_lhs_only", note = ctl_note),
    liquidity = list(applied = liq_applied, liq_min = liq_min,
                     n_dropped = n_liq_dropped,
                     liq_ruler = if (is.null(liq_ruler)) NA_character_ else liq_ruler),
    sanity = list(ret1m_excluded = n_bad),

    pit = list(
      c1_rolling_only = TRUE,
      quantile_bucketing = "per_date_cross_section_rank",
      excess_return = "per_date_cross_section_demean",
      orthogonalization_scope = "per_date_cross_section",
      winsorize_scope = "per_date_cross_section (직교화 회귀 좌변 전용 — 버킷팅 미적용)",
      tail_threshold_scope = if (identical(tail_threshold_mode, "fixed"))
        "prespecified_constant" else sprintf("trailing_%dm_pooled_skip%d",
                                             tail_rolling_window, tail_rolling_skip),
      fullsample_statistic_used = FALSE,
      diag_pooled_fields = "windows$*$*$shape_profile (decision_binding=FALSE)",
      note = "판정 통계는 전부 월별 횡단면 시계열의 NW-t 집계 — full-sample 추정 없음."),

    windows = win_out,
    survival = survival,
    window_independence = window_independence,
    sign_agreement = sign_agreement,
    distribution_axes = dist_axes,
    mean_space_control_axis = "mean_spread"
  )

  # 반환 직전 자기검사 — 계약이 스스로 자본 필드를 새로 만드는 회귀를 차단
  dt_assert_no_capital_fields(out, "canonical_distribution_screen(return)")
  out
}

`%|d|%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#------------------------------------------------------------------------------
# dt_route_eligible — DISTRIBUTION_TARGET 발급 요건 3종 게이트
#------------------------------------------------------------------------------
#' @param dist_result canonical_distribution_screen() 반환 객체
#' @param mean_space_evidence list(
#'     label = "NEGATIVE_POWERED" | "INCONCLUSIVE_UNDERPOWERED" | ...,
#'     positive_control = list(design=, detected=, statistic=, null_band_q05=, null_band_q95=),
#'     observed = list(statistic=, inside_null_band=))
#'   ★선언을 믿지 않는다 — detected/inside 플래그를 **수치로 재검증**한다.
#' @return list(eligible, route, requirements, reasons)
dt_route_eligible <- function(dist_result, mean_space_evidence = NULL, t_min_survive = NULL) {
  # ★게이트 입력에도 자본 필드 검사 — 손으로 PORT_t 를 붙여 통과시키려는 경로 차단
  dt_assert_no_capital_fields(dist_result, "dt_route_eligible(input)")
  if (!is.null(mean_space_evidence))
    dt_assert_no_capital_fields(mean_space_evidence, "dt_route_eligible(mean_space_evidence)")

  reasons <- character(0)

  # ── 요건① 평균 공간이 '미결'이 아니라 '효과없음' — 양성 대조로 실증 ────────
  ev <- mean_space_evidence
  r1_detail <- list()
  r1 <- FALSE
  if (is.null(ev)) {
    reasons <- c(reasons, "R1: mean_space_evidence 부재 — 평균 공간 판정 없이 분포 라우트 발급 불가")
    r1_detail <- list(supplied = FALSE)
  } else {
    lab <- as.character(ev$label %|d|% "")
    pc <- ev$positive_control %|d|% list()
    ob <- ev$observed %|d|% list()
    pc_stat <- .dts_num(pc$statistic); pc_q95 <- .dts_num(pc$null_band_q95); pc_q05 <- .dts_num(pc$null_band_q05)
    ob_stat <- .dts_num(ob$statistic)
    # 플래그가 아니라 수치로 재검증
    pc_detected_measured <- is.finite(pc_stat) && is.finite(pc_q95) && is.finite(pc_q05) &&
      (pc_stat > pc_q95 || pc_stat < pc_q05)
    ob_inside_measured <- is.finite(ob_stat) && is.finite(pc_q95) && is.finite(pc_q05) &&
      ob_stat >= pc_q05 && ob_stat <= pc_q95
    label_ok <- identical(lab, "NEGATIVE_POWERED")
    r1 <- label_ok && pc_detected_measured && ob_inside_measured
    r1_detail <- list(supplied = TRUE, label = lab, label_ok = label_ok,
                      positive_control_statistic = pc_stat,
                      null_band = c(pc_q05, pc_q95),
                      positive_control_detected_measured = pc_detected_measured,
                      positive_control_detected_declared = isTRUE(pc$detected),
                      declaration_matches_measurement =
                        identical(isTRUE(pc$detected), pc_detected_measured),
                      observed_statistic = ob_stat,
                      observed_inside_null_band_measured = ob_inside_measured,
                      design = as.character(pc$design %|d|% NA_character_))
    if (!label_ok) reasons <- c(reasons, sprintf(
      "R1: label='%s' — 'NEGATIVE_POWERED'(효과없음) 만 자격. 'INCONCLUSIVE_UNDERPOWERED'(미결)는 처분이 다르다.", lab))
    if (!pc_detected_measured) reasons <- c(reasons,
      "R1: 양성 대조가 귀무 밴드를 넘지 못했다(수치 재검증) — '조작이 먹는다'가 실증되지 않았다")
    if (!ob_inside_measured) reasons <- c(reasons,
      "R1: 관측 평균-공간 통계가 귀무 밴드 밖 — 평균 공간이 null 이 아니다(분포 라우트가 아니라 평균 레인 후보)")
    if (!identical(isTRUE(pc$detected), pc_detected_measured)) reasons <- c(reasons,
      "R1: 양성 대조 **선언과 실측이 불일치** — 선언 필드를 신뢰하지 않는다")
  }

  # ── 요건② vol·size 최소 2축 직교화 후 생존 ────────────────────────────────
  sv <- dist_result$survival %|d|% list()
  tmin <- t_min_survive %|d|% .dts_num(sv$t_min_survive)
  r2 <- identical(as.character(sv$verdict %|d|% ""), "SURVIVES") &&
    isTRUE(sv$control_applied) && (length(sv$control_cols %|d|% character(0)) >= 2L)
  r2_detail <- list(verdict = as.character(sv$verdict %|d|% NA_character_),
                    control_cols = sv$control_cols,
                    control_axes_n = sv$control_axes_n,
                    t_min_survive = tmin,
                    survived_axes = sv$survived_axes_any_window)
  if (!isTRUE(sv$control_applied)) reasons <- c(reasons,
    "R2: 직교화 미실행 — raw 값만으로는 발급 불가(가장 화려한 열이 통제 후 먼저 죽는다: Lane B 상방꼬리 t −6.67→−0.92)")
  else if (length(sv$control_cols %|d|% character(0)) < 2L) reasons <- c(reasons,
    sprintf("R2: 통제 축 %d개 — 헌법 요건 최소 2축(vol·size)", length(sv$control_cols %|d|% character(0))))
  else if (!r2) reasons <- c(reasons,
    sprintf("R2: 직교화 후 생존 축 0 (verdict=%s, |NW-t| >= %.2f 미달 또는 부호 반전)",
            as.character(sv$verdict %|d|% "NA"), tmin))

  # ── 요건③ 독립 창 2개 부호 일치 ────────────────────────────────────────────
  wi <- dist_result$window_independence %|d|% list()
  sa <- dist_result$sign_agreement %|d|% list()
  surv_ax <- sv$survived_axes_any_window %|d|% character(0)
  agreed_ax <- sa$agreed_axes %|d|% character(0)
  both <- intersect(surv_ax, agreed_ax)
  r3 <- isTRUE(wi$has_disjoint_pair) && identical(as.character(sa$verdict %|d|% ""), "AGREES") &&
    length(both) > 0L
  r3_detail <- list(window_verdict = as.character(wi$verdict %|d|% NA_character_),
                    has_disjoint_pair = isTRUE(wi$has_disjoint_pair),
                    sign_verdict = as.character(sa$verdict %|d|% NA_character_),
                    agreed_axes = agreed_ax,
                    axes_surviving_and_agreeing = both)
  if (!isTRUE(wi$has_disjoint_pair)) reasons <- c(reasons, sprintf(
    "R3: 겹치지 않는 창 쌍 없음 (verdict=%s) — 포함관계 창(전체창 ⊃ 부분창)은 독립 창 2개가 아니다",
    as.character(wi$verdict %|d|% "NA")))
  else if (!length(both)) reasons <- c(reasons,
    "R3: 요건② 생존 축과 부호 일치 축의 교집합 0 — 살아남은 축이 두 창에서 같은 부호를 내야 한다")

  eligible <- r1 && r2 && r3
  list(
    eligible = eligible,
    route = if (eligible) "DISTRIBUTION_TARGET" else "NONE",
    gate_version = DTS_CONTRACT_VERSION,
    spec_id = dist_result$spec_id %|d|% NA_character_,
    capital_eligible = FALSE,
    capital_note = "라우트 발급은 screening tier 라벨일 뿐 — 자본 자격이 아니다.",
    requirements = list(
      r1_mean_space_powered_null = list(pass = r1, detail = r1_detail),
      r2_orthogonal_survival     = list(pass = r2, detail = r2_detail),
      r3_two_window_sign_agree   = list(pass = r3, detail = r3_detail)),
    reasons = reasons,
    evaluated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )
}

#------------------------------------------------------------------------------
# dt_emit_screen_result — 산출물 발행 (소비 배관이 읽는 **정본 형태**)
#------------------------------------------------------------------------------
#' @param dist_result canonical_distribution_screen() 반환
#' @param gate_result dt_route_eligible() 반환 (NULL 이면 여기서 계산 안 함 — 기록만)
#' @param out_path 저장 경로. 파일명은 `distribution_screen_*.json` 규약
#'   (소비자 02_Infrastructure/portfolio/distribution_target_queue.R 가 이 패턴으로 찾는다)
#' @param drop_monthly_series TRUE(기본) — 월별 원계열은 JSON 에서 제외(용량).
#'   ★제외 사실을 `monthly_series_dropped` 로 **기록**한다. 조용히 빠지면 소비자가
#'   "산출 안 됨"과 "발행에서 뺐음"을 구분 못 한다.
dt_emit_screen_result <- function(dist_result, gate_result = NULL, out_path,
                                  drop_monthly_series = TRUE) {
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("[dt_emit_screen_result] jsonlite 필요", call. = FALSE)
  dt_assert_no_capital_fields(dist_result, "dt_emit_screen_result(dist_result)")
  bn <- basename(out_path)
  if (!grepl("^distribution_screen_.*\\.json$", bn))
    stop(sprintf(paste0("[dt_emit_screen_result] 파일명 규약 위반: '%s'. ",
                        "소비 배관이 'distribution_screen_*.json' 으로 찾는다 — ",
                        "다른 이름으로 쓰면 발행은 되고 **아무도 읽지 않는다**."), bn), call. = FALSE)
  obj <- dist_result
  if (isTRUE(drop_monthly_series)) {
    for (wn in names(obj$windows)) for (bs in c("raw", "orthogonalized")) {
      if (is.list(obj$windows[[wn]][[bs]])) obj$windows[[wn]][[bs]]$monthly_series <- NULL
    }
  }
  obj$monthly_series_dropped <- isTRUE(drop_monthly_series)
  obj$route_gate <- gate_result
  obj$emitted_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(obj, out_path, auto_unbox = TRUE, pretty = TRUE,
                       digits = NA, null = "null", na = "null")
  invisible(out_path)
}

cat("[distribution_target_screen.R] Loaded — canonical_distribution_screen() / dt_route_eligible() / dt_emit_screen_result() / dt_assert_no_capital_fields() (v1.0)\n")
