## ============================================================================
## score_composite.R — score-level 팩터 컴포짓 계약 (v9.1 §7-S3a, 도훈 지시 E-6)
##
## 지시: "팩터 노출도를 z-score화 → 팩터 컴포짓 스코어 → 상위 25종 편입".
## 저장소 판례가 같은 답을 이미 갖고 있다 — `.claude/skills_retired_v10/ensemble-design.md:50`(v10 퇴역·사료)
##   "score-level blend만 허용(return blend는 L-484 위반)". L-484 = STR_1047/STR_1439 가
##   4-sleeve return-blend 로 **실보유 52~80종**이 되어 Judge 가 A→B 강등한 실사고.
##   weight-level 결합은 union 이 구조적으로 25 를 넘는다(실측: Top25 3건 월평균 union
##   57.5종 / 75 슬롯). 그래서 결합은 **score 층에서** 하고, weight 층 결합은
##   sc_weight_blend_top_n 이 **대조군 측정 전용**으로만 남긴다.
##
## ★설계상 유일한 실질 난점 = 멤버 support 불일치.
##   멤버 엔진의 Score 정의역이 서로 다르다(RevisionAgreement = 3조건 conjunction 집합
##   31~167종 · PFRD = 5팩터 전부 보유 종목 · PTV = 252일 히스토리 보유 전부).
##   규약: **멤버 자기 support 안에서 z → union → 사용가능 멤버만의 가중평균 →
##   n_members < min_members 인 (Date,Ticker) 제외**.
##   ★결측을 0 으로 채워 "신호 없음"으로 위장하지 않는다. z=0 은 "그 멤버가 이 종목을
##   중립으로 봤다"는 진술인데, 실제로는 **보지 않았다**. 전례 = fe_factor_combo.R:47-49
##   의 FACTOR_MIN_COUNT. n_members 는 산출물에 남긴다(멤버 편향 감시 — 위험표 R6).
##
## 자체합성 금지 정합(python-policy §4): 이 파일은 포트폴리오 수익률을 만들지 않는다.
##   점수/비중만 다루고, 성과 축은 저장된 bt_result 계열 + 계약 함수
##   (.nw_t_mean · bm_delta_ir · PerformanceAnalytics)만 재사용한다.
##
## 실행 경로: 신규 백테 러너를 만들지 않는다.
##   fe_score_composite.R(어댑터) → FACTORS(Date,Ticker,Score,N) → 기존
##   run_alpha_search(factor_engine_path=..., n_holdings=25L, deep=FALSE) 한 호출.
## ============================================================================
suppressPackageStartupMessages({ library(data.table) })

## 고정 축 — 배포 현실이 정의한 문제의 정의다(CLAUDE.md Production Constraints, E-5).
SC_HOLDINGS_CAP <- 25L

## 계약 함수 견고 소싱 (weighted_screen_bt.R:12-22 전례 — 호출 컨텍스트 무관, idempotent)
.sc_source <- function(rel, probe) {
  if (exists(probe, mode = "function")) return(invisible(TRUE))
  here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA_character_)
  # ★resolver 우선순위 = CLAUDE_PROJECT_DIR 먼저 (r-portability.md 금칙 ④ 표준 계열).
  #   ~/.Renviron 이 QM_ROOT 를 고정해 쉘 export 로 안 덮이므로, worktree 실행에서
  #   호출자와 계열이 갈리면 존재하는 파일이 "package not found" 로 기각된다.
  cands <- c(if (!is.na(here)) file.path(here, basename(rel)) else NULL,
             file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "."), rel),
             file.path(Sys.getenv("QM_ROOT", "."), rel),
             rel)
  for (f in cands) if (!is.null(f) && file.exists(f)) { suppressMessages(source(f)); return(invisible(TRUE)) }
  invisible(FALSE)
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. 멤버 수확 — 엔진 1개를 격리 실행해 (Date,Ticker,Score) 만 받는다
# ─────────────────────────────────────────────────────────────────────────────
#' @param engine_path   멤버 factor engine 경로 (FACTORS 를 만드는 파일)
#' @param rawdata       RAWDATA data.table. ★멤버마다 copy 를 준다 — 엔진들이 `[ , := ]`
#'                      로 RAWDATA 를 참조 수정하기 때문에 공유하면 뒤 멤버가 앞 멤버의
#'                      파생컬럼 위에서 돈다(조용한 교차오염).
#' @param extra_globals 엔진이 요구하는 추가 전역(보통 list(BM_DT = BM_DT))
#' @return data.table(Date, Ticker, Score) — ★멤버의 N 컬럼은 폐기한다.
#'         종목수 결정은 composite 층의 권한이고, 멤버가 25를 들고 오면 결합 전에
#'         이미 절단된 신호를 결합하게 된다.
sc_harvest_member <- function(engine_path, rawdata, extra_globals = list()) {
  if (!file.exists(engine_path)) stop("[score_composite] 멤버 엔진 부재: ", engine_path)
  env <- new.env(parent = globalenv())
  env$RAWDATA <- data.table::copy(as.data.table(rawdata))
  for (nm in names(extra_globals)) assign(nm, extra_globals[[nm]], envir = env)
  source(engine_path, local = env)
  if (!exists("FACTORS", envir = env, inherits = FALSE))
    stop("[score_composite] 멤버가 FACTORS 를 만들지 않았다: ", engine_path)
  F <- as.data.table(env$FACTORS)
  if (!all(c("Date", "Ticker", "Score") %in% names(F)))
    stop("[score_composite] 멤버 FACTORS 에 Date/Ticker/Score 필요: ", engine_path)
  out <- F[is.finite(Score), .(Date = as.Date(Date), Ticker = as.character(Ticker),
                               Score = as.numeric(Score))]
  rm(env); gc(verbose = FALSE)
  if (!nrow(out)) stop("[score_composite] 멤버 산출 0행: ", engine_path)
  out[]
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. 시점별 cross-sectional z
# ─────────────────────────────────────────────────────────────────────────────
## ★규약 자구동일 — factor_engine_composite_mom.R:57 의 .zsc.
##   sd 가 0 이거나 비유한이면 0 벡터(전원 동점 = 정보 없음). 구현이 갈리면 같은 신호를
##   두 파일이 다르게 표준화한다.
.sc_zsc <- function(x) { s <- sd(x, na.rm = TRUE); if (!is.finite(s) || s == 0) return(rep(0, length(x))); (x - mean(x, na.rm = TRUE)) / s }

#' 시점별 cross-sectional z-score. 입력의 support 를 넓히거나 좁히지 않는다.
#' @return data.table(Date, Ticker, <score_col>, z)
sc_zscore_by_date <- function(dt, score_col = "Score") {
  D <- data.table::copy(as.data.table(dt))   # 호출자 테이블에 z 를 참조로 심지 않는다
  if (!all(c("Date", "Ticker", score_col) %in% names(D)))
    stop("[score_composite] sc_zscore_by_date: Date/Ticker/", score_col, " 필요")
  D <- D[is.finite(get(score_col))]
  D[, z := .sc_zsc(get(score_col)), by = Date]
  D[]
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. 멤버 z 가중결합 (support 불일치 규약의 집)
# ─────────────────────────────────────────────────────────────────────────────
#' @param members     named list of data.table(Date,Ticker,Score)
#' @param weights     멤버 가중(non-negative, 길이 동일). NULL = 등가중
#' @param min_members (Date,Ticker) 가 살아남기 위한 최소 관측 멤버 수
#' @return data.table(Date, Ticker, Score, n_members)
#'         attr "n_members_by_date" = 월별 n_members 분포 · attr "member_support" = 멤버별 커버리지
sc_combine_scores <- function(members, weights = NULL, min_members = 2L) {
  if (!is.list(members) || !length(members)) stop("[score_composite] members 가 비었다")
  nms <- names(members)
  if (is.null(nms) || any(!nzchar(nms))) nms <- paste0("m", seq_along(members))
  names(members) <- nms
  w <- if (is.null(weights)) rep(1, length(members)) else as.numeric(weights)
  if (length(w) != length(members) || any(!is.finite(w)) || any(w < 0) || !any(w > 0))
    stop("[score_composite] weights 는 members 와 같은 길이의 non-negative 벡터여야 한다")
  names(w) <- nms
  min_members <- as.integer(min_members)

  Z <- rbindlist(lapply(nms, function(n) {
    d <- sc_zscore_by_date(members[[n]])          # ★멤버 자기 support 안에서 z
    d[, .(Date, Ticker, member = n, z)]
  }), use.names = TRUE)
  Z <- Z[is.finite(z)]
  Z[, wgt := w[member]]
  Z <- Z[wgt > 0]
  if (!nrow(Z)) stop("[score_composite] 결합 가능한 멤버 관측이 0")

  ## union 위에서 **사용가능 멤버만의** 가중평균. 결측 멤버는 분모에서도 빠진다
  ## (0 으로 채우면 "중립 신호"라는 없는 진술을 만든다).
  out <- Z[, .(Score = sum(wgt * z) / sum(wgt), n_members = .N), by = .(Date, Ticker)]
  n_pre <- nrow(out)
  out <- out[n_members >= min_members]
  if (!nrow(out))
    stop(sprintf("[score_composite] min_members=%d 를 만족하는 (Date,Ticker) 가 0 — 멤버 support 가 겹치지 않는다",
                 min_members))
  setorder(out, Date, -Score)

  nmb <- out[, .(n_names = .N, n_members_mean = mean(n_members),
                 n_members_min = min(n_members), n_members_max = max(n_members)), by = Date]
  sup <- Z[, .(n_obs = .N, n_dates = uniqueN(Date), n_tickers = uniqueN(Ticker)), by = member]
  setattr(out, "n_members_by_date", nmb[])
  setattr(out, "member_support", sup[])
  setattr(out, "dropped_below_min_members", as.integer(n_pre - nrow(out)))
  out[]
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. 종목수 상한을 FACTORS$N 에 박는다
# ─────────────────────────────────────────────────────────────────────────────
#' 행은 자르지 않고 N 컬럼만 시점별로 박는다(_top25 엔진 3종의 실증 경로 —
#' fe_revision_agreement_top25.R:60 `out[, N := min(.N, 25L)]`). 소비 지점은
#' backtest_harness.R:933-937 이 N 을 읽어 n_hold_eff 로 쓰고 :965 가 잘라내는 곳이다.
#' 행을 자르면 buffer_zone(keep_n = 2*n) 이 볼 순위표가 사라져 회전율 규약이 달라진다.
#' ★top_n 은 SC_HOLDINGS_CAP(25) 로 강제 클램프된다 — E-5(고정 축 우선).
sc_cap_top_n <- function(scores_dt, top_n = SC_HOLDINGS_CAP) {
  D <- as.data.table(scores_dt)
  if (!all(c("Date", "Ticker", "Score") %in% names(D)))
    stop("[score_composite] sc_cap_top_n: Date/Ticker/Score 필요")
  tn <- as.integer(min(SC_HOLDINGS_CAP, max(1L, as.integer(top_n))))
  D <- D[is.finite(Score)]
  setorder(D, Date, -Score)
  D[, N := as.integer(min(.N, tn)), by = Date]
  D[]
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. 대조군 — weight-level 결합 후 절단 (채택 경로 아님)
# ─────────────────────────────────────────────────────────────────────────────
#' 왜 있나: "score 결합이 옳다"는 주장은 **weight 결합의 손실을 수치로 보여야** 성립한다.
#' L-484 의 재현이 목적이지 채택 후보가 아니다.
#' @param weights_list named list of data.table(Date, Ticker, w)
#' @return list(weights=절단·재정규화 결과, n_union_pre_trunc(mean/by_date),
#'              weight_retained_mean(절단 전 대비 잔존 비중 평균 ∈ [0,1]), n_trunc_months, ...)
sc_weight_blend_top_n <- function(weights_list, weights = NULL, top_n = SC_HOLDINGS_CAP) {
  if (!is.list(weights_list) || !length(weights_list)) stop("[score_composite] weights_list 가 비었다")
  nms <- names(weights_list)
  if (is.null(nms) || any(!nzchar(nms))) nms <- paste0("m", seq_along(weights_list))
  names(weights_list) <- nms
  lam <- if (is.null(weights)) rep(1, length(weights_list)) else as.numeric(weights)
  if (length(lam) != length(weights_list) || any(!is.finite(lam)) || any(lam < 0) || !any(lam > 0))
    stop("[score_composite] weights 는 weights_list 와 같은 길이의 non-negative 벡터여야 한다")
  lam <- lam / sum(lam); names(lam) <- nms
  tn <- as.integer(min(SC_HOLDINGS_CAP, max(1L, as.integer(top_n))))

  W <- rbindlist(lapply(nms, function(n) {
    d <- as.data.table(weights_list[[n]])
    if (!all(c("Date", "Ticker", "w") %in% names(d)))
      stop("[score_composite] weights_list[[", n, "]] 에 Date/Ticker/w 필요")
    d <- d[is.finite(w) & w > 0]
    d[, Date := as.Date(Date)]; d[, Ticker := as.character(Ticker)]; d[, w := as.numeric(w)]
    d[, w := w / sum(w), by = Date]              # Date별 합 1 정규화(안전)
    d[, .(Date, Ticker, w, member = n)]
  }), use.names = TRUE)
  ## ★여기서의 0 은 "신호 없음"이 아니라 "그 슬리브가 이 종목을 보유하지 않음"이다 —
  ##   sc_combine_scores 의 결측 규약과 구분된다(비중은 실제로 0, 점수는 미관측).
  W[, lw := lam[member] * w]
  B <- W[, .(w_blend = sum(lw)), by = .(Date, Ticker)]
  B <- B[w_blend > 0]
  setorder(B, Date, -w_blend)

  uni <- B[, .(n_union_pre_trunc = .N, w_total = sum(w_blend)), by = Date]
  B[, .rk := seq_len(.N), by = Date]
  K <- B[.rk <= tn]
  kept <- K[, .(w_kept = sum(w_blend)), by = Date]
  d <- merge(uni, kept, by = "Date")
  d[, retained := w_kept / w_total]
  K[, w := w_blend / sum(w_blend), by = Date]

  list(
    weights              = K[, .(Date, Ticker, w)],
    top_n                = tn,
    by_date              = d[, .(Date, n_union_pre_trunc, weight_retained = retained)],
    n_union_pre_trunc    = mean(d$n_union_pre_trunc),
    weight_retained_mean = mean(d$retained),
    n_trunc_months       = as.integer(sum(d$n_union_pre_trunc > tn)),
    n_months             = nrow(d),
    metric_type          = "control_arm_weight_blend",
    note = paste0("대조군 전용 — 채택 경로 아님(ensemble-design.md:50 'score-level blend만 허용', ",
                  "L-484). weight_retained_mean 이 절단 손실이다.")
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. ★증분 — composite 가 최고 구성원을 실제로 이겼는가
# ─────────────────────────────────────────────────────────────────────────────
.sc_bt <- function(x) {
  if (is.character(x) && length(x) == 1L) {
    if (!file.exists(x)) stop("[score_composite] bt_result 부재: ", x)
    return(readRDS(x))
  }
  if (is.list(x) && !is.null(x$period_returns)) return(x)
  stop("[score_composite] bt_result 또는 그 경로가 필요하다")
}

## 일간 → 월간: PerformanceAnalytics 표준 집계만(자체합성 없음).
## overlay_candidate_drain.R:190-195 와 동일 idiom.
.sc_monthly <- function(dt, col) {
  x <- xts::xts(as.numeric(dt[[col]]), order.by = as.Date(dt$date))
  m <- xts::apply.monthly(x, PerformanceAnalytics::Return.cumulative)
  data.table(date = as.Date(zoo::index(m)), v = as.numeric(m))
}

.sc_metric <- function(bt, nm) {
  M <- as.data.table(bt$metrics)
  v <- M[metric_name == nm, metric_value]
  if (!length(v)) return(NA_real_)
  as.numeric(v[1])
}
.sc_bcmp <- function(bt, nm, field = "active_value") {
  B <- as.data.table(bt$benchmark_compare)
  v <- B[metric_name == nm][[field]]
  if (!length(v)) return(NA_real_)
  suppressWarnings(as.numeric(v[1]))
}

#' 축 6종을 한 bt_result 에서 뽑는다.
sc_axes <- function(bt, book_weight = 0.20, with_book = TRUE) {
  bt <- .sc_bt(bt)
  pr <- as.data.table(bt$period_returns)[, .(date = as.Date(date), ret_net = as.numeric(ret_net))]
  br <- as.data.table(bt$benchmark_returns)[, .(date = as.Date(date), benchmark_ret = as.numeric(benchmark_ret))]
  freq <- tolower(as.character((as.data.table(bt$period_returns)$frequency)[1]))
  if (identical(freq, "daily")) {
    pm <- .sc_monthly(pr, "ret_net"); bm <- .sc_monthly(br, "benchmark_ret")
  } else {
    pm <- pr[, .(date, v = ret_net)];  bm <- br[, .(date, v = benchmark_ret)]
  }
  X <- merge(pm, bm, by = "date", suffixes = c("_s", "_b"))
  X[, active := v_s - v_b]

  .sc_source("02_Infrastructure/contracts/backtest_result_contract.R", ".nw_t_mean")
  port_t <- if (exists(".nw_t_mean", mode = "function")) .nw_t_mean(X$active, lag = 3L) else NA_real_

  dir <- NA_real_
  if (isTRUE(with_book)) {
    .sc_source("02_Infrastructure/contracts/book_marginal.R", "bm_delta_ir")
    dir <- tryCatch({
      ## ★반드시 bm_delta_ir 을 경유한다 — .bm_align_offset 이 candidate month_index +2 =
      ##   PG2 month_index 로 정렬한다. 손으로 merge 하면 겹침 0 이 되어 전 후보가
      ##   조용히 INSUFFICIENT_OVERLAP 으로 탈락한다(2026-08-09 실측 확정).
      r <- bm_delta_ir(X[, .(date, ret_net = v_s)], weight = book_weight, bootstrap = FALSE)
      if (identical(r$status, "INSUFFICIENT_OVERLAP")) NA_real_ else as.numeric(r$delta_ir)
    }, error = function(e) NA_real_)
  }

  list(SR = .sc_metric(bt, "Sharpe"), MDD = .sc_metric(bt, "MDD"),
       Calmar = .sc_metric(bt, "Calmar"), IR = .sc_bcmp(bt, "Information_Ratio"),
       PORT_t_NW3 = port_t, book_dIR = dir, n_months = nrow(X))
}

## 축 방향 — TRUE 면 클수록 좋다
SC_AXIS_HIGHER_BETTER <- c(SR = TRUE, MDD = FALSE, Calmar = TRUE, IR = TRUE,
                           PORT_t_NW3 = TRUE, book_dIR = TRUE)

#' ★증분 보고 — composite vs **최고 구성원**(축별로 각각 최고인 멤버)
#' HARD 판정(v9.1 §S3a): ΔSR ≥ +0.05 ∨ ΔMDD ≤ −0.03 ∨ ΔIR ≥ +0.05 중 하나도 못 내면
#' 결합 이득 없음 — blender 문서 갱신 착수하지 않고 L-code 적립 후 종료.
#' @param composite bt_result 또는 그 경로
#' @param members   named list of bt_result/경로
sc_incremental_report <- function(composite, members, book_weight = 0.20) {
  ca <- sc_axes(composite, book_weight = book_weight)
  ma <- lapply(members, sc_axes, book_weight = book_weight)
  nms <- names(members); if (is.null(nms)) nms <- paste0("m", seq_along(members))

  rows <- rbindlist(lapply(names(SC_AXIS_HIGHER_BETTER), function(ax) {
    hb <- SC_AXIS_HIGHER_BETTER[[ax]]
    vals <- vapply(ma, function(m) { v <- m[[ax]]
      if (is.null(v) || !length(v)) NA_real_ else as.numeric(v[1]) }, numeric(1))
    if (all(!is.finite(vals)))
      return(data.table(axis = ax, composite = as.numeric(ca[[ax]]), best_member = NA_real_,
                        best_member_name = NA_character_, delta = NA_real_))
    i <- if (hb) which.max(replace(vals, !is.finite(vals), -Inf))
         else     which.min(replace(vals, !is.finite(vals),  Inf))
    data.table(axis = ax, composite = as.numeric(ca[[ax]]), best_member = vals[i],
               best_member_name = nms[i], delta = as.numeric(ca[[ax]]) - vals[i])
  }), use.names = TRUE)
  rows[, direction := ifelse(SC_AXIS_HIGHER_BETTER[axis], "higher_better", "lower_better")]

  g <- function(ax) rows[axis == ax, delta][1]
  gains <- c(dSR = isTRUE(g("SR") >= 0.05),
             dMDD = isTRUE(g("MDD") <= -0.03),
             dIR = isTRUE(g("IR") >= 0.05))
  verdict <- if (any(gains)) "INCREMENTAL_GAIN" else "NO_INCREMENTAL_GAIN"
  rows[, verdict := verdict]

  list(axes = rows[], verdict = verdict, gates_passed = gains,
       composite_axes = ca, member_axes = ma, book_weight = book_weight,
       metric_type = "proxy_incremental_vs_best_member",
       note = paste0("HARD: ΔSR≥+0.05 ∨ ΔMDD≤−3pp ∨ ΔIR≥+0.05 중 1개 이상. ",
                     "book_dIR 은 bm_delta_ir(PG2 incumbent, w=", book_weight,
                     ") 경유 — 손 merge 금지(.bm_align_offset +2)."))
}

## ★이 파일은 전역 `%||%` 를 정의하지 않는다 — register_module.R 소싱 뒤 run_alpha_search 가
##   매번 `%||%` 를 복원해야 했던 계통의 오염을 만들지 않기 위해서다(계약은 조용해야 한다).
