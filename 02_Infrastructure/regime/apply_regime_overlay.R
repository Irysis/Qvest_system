#==============================================================================
# apply_regime_overlay.R — 3-Layer Regime Overlay (정본 구현)
#
# 20+ 전략에 인라인으로 중복되던 overlay 코드를 단일 함수로 추출.
# STR_1631/run_all.R L527-578 기반.
#
# PIT NOTE (★2026-09-24 C11 정정 — 판정서 V-06 · ② 규약 (b)):
#   구 서술 "regime_dt 의 MRS 는 이미 t-1 lagged 라 추가 shift 금지"는 **C11 위반을 만든 전제**였다.
#   build_daily_regime() 의 MRS[t] = MRS_raw[직전 FRED 행] 은 미국 t-1 세션(한국 t-1 종가 뒤 약 14시간)을
#   담는데, 이 오버레이는 그 값을 한국 종가→종가 수익 r_t(창 시작 = 한국 t-1 15:30)에 곱했다.
#   '국면 패널 1행 lag' 는 규약 (b)를 대신하지 못한다(미국 날짜 ≤ t-2 여야 한다).
#   현행: 노출을 곱하는 수익 행마다 결정일 = 그 수익 창의 시작(= NAV 의 직전 행 날짜)을 두고,
#   가용일(avail_date / MRS_avail_date)이 결정일 이하인 최신 국면 값만 쓴다
#   (02_Infrastructure/validation/overlay_pit_guard.R — c11_window_start · c11_asof_align ·
#    assert_overlay_pit_avail). 가용일 열이 없는 legacy 패널은 기본 중단(fail-closed).
#
# Usage:
#   source("02_Infrastructure/regime/apply_regime_overlay.R")
#   overlay <- apply_regime_overlay(sim_result, regime_dt, BM_DT)
#   overlay$strategy_xts   # overlaid daily returns (xts)
#   overlay$DAILY_NAV_DT   # full daily table with Layer, Ret_overlay, NAV
#   overlay$overlay_stats  # Layer 분포 통계
#   overlay$pit_c11        # 국면 값 정렬 방식 기록(legacy 면 미해소 표식)
#   # C5 lag1 스트레스: apply_regime_overlay(..., extra_lag = 1L)
#
# Dependencies: data.table, xts, 02_Infrastructure/validation/overlay_pit_guard.R
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
})

# ── C11 가용시점 가드 적재 (격리 env — 호출자 전역을 건드리지 않는다) ─────────────
#   가드 부재 = 규약 (b) 없이 오버레이를 돌릴 수 없으므로 적재 시점에 중단한다.
.ARO_C11 <- local({
  self <- tryCatch({
    f <- NULL
    for (i in rev(seq_len(sys.nframe()))) {
      o <- tryCatch(sys.frame(i)$ofile, error = function(e) NULL)
      if (!is.null(o) && nzchar(o)) { f <- o; break }
    }
    f
  }, error = function(e) NULL)
  cands <- c(if (!is.null(self)) file.path(dirname(self), "..", "validation", "overlay_pit_guard.R"),
             "02_Infrastructure/validation/overlay_pit_guard.R",
             file.path(Sys.getenv("CLAUDE_PROJECT_DIR", ""), "02_Infrastructure/validation/overlay_pit_guard.R"),
             file.path(Sys.getenv("QM_ROOT", ""), "02_Infrastructure/validation/overlay_pit_guard.R"))
  hit <- cands[nzchar(cands) & file.exists(cands)]
  if (!length(hit))
    stop("[apply_regime_overlay] C11 가용시점 가드(overlay_pit_guard.R) 부재 — 규약 (b) 없이 오버레이를 돌릴 수 없다: ",
         paste(cands, collapse = " | "))
  e <- new.env(parent = globalenv())
  sys.source(hit[1], envir = e)
  if (!exists("c11_asof_align", envir = e, inherits = FALSE))
    stop("[apply_regime_overlay] overlay_pit_guard.R 에 C11 층(c11_asof_align) 없음 — 구판 가드: ", hit[1])
  e
})

#' Apply 3-Layer Regime Overlay to a backtest result
#'
#' @param sim_result  list from run_monthly_simulation()
#'                    Must contain: DAILY_NAV_DT (Date, NAV, Strategy_Ret)
#' @param regime_dt   data.table from build_daily_regime()
#'                    Must contain: Date, MRS, n_axes_firing
#'                    ★C11: 가용일 열(MRS_avail_date / avail_date — 한국 d 종가 결정에 처음 쓸 수 있는 날)이
#'                    있어야 한다. 없으면 legacy 패널 → c11_legacy 정책(기본 stop).
#' @param BM_DT       benchmark data.table (Date, BM_Ret)
#' @param inv_dt      (optional) inverse ETF data.table (Date, Ret_Inv)
#'                    If NULL, uses -BM_Ret as proxy
#' @param crisis_threshold  list(mrs, axes, consec) for Layer 3 classification
#' @param caution_threshold numeric MRS threshold for Layer 2
#' @param initial_cap       initial capital for NAV calculation
#' @param extra_lag   C5 lag 스트레스용 추가 지연(수익 행 수). 0 = 규약 (b) 기본.
#' @param c11_legacy  가용일 열 없는 legacy 패널 정책: NULL(→ QVEST_C11_LEGACY_REGIME → "stop") | "stop" | "label".
#'                    "label" = 구 정렬(Date roll join)로 진행 + pit_c11 미해소 표식 — 진단 재현 전용.
#'
#' @return list(strategy_xts, bm_xts, DAILY_NAV_DT, overlay_stats, pit_c11)
apply_regime_overlay <- function(
  sim_result,
  regime_dt,
  BM_DT,
  inv_dt             = NULL,
  crisis_threshold   = list(mrs = 60, axes = 5, consec = 3),
  caution_threshold  = 30,
  initial_cap        = 1e8,
  extra_lag          = 0L,
  c11_legacy         = NULL
) {

  # ── Validate inputs ───────────────────────────────────────────────
  stopifnot(
    is.list(sim_result),
    "DAILY_NAV_DT" %in% names(sim_result),
    is.data.table(regime_dt),
    all(c("Date", "MRS", "n_axes_firing") %in% names(regime_dt)),
    is.data.table(BM_DT),
    "BM_Ret" %in% names(BM_DT)
  )

  nav_dt <- copy(sim_result$DAILY_NAV_DT)
  nav_dt[, Date := as.Date(Date)]
  setkey(nav_dt, Date)

  # ── Merge regime — ★C11 규약 (b) (2026-09-24) ─────────────────────
  #   수익 r_t(한국 종가→종가, 창 시작 = NAV 직전 행 날짜 15:30)에 곱하는 노출은 그 창 시작까지
  #   가용한 국면 값만 쓴다. 날짜 라벨 roll join(구판)은 미국 t-1 세션을 들였다(V-06).
  .g <- .ARO_C11$c11_legacy_gate(regime_dt, "MRS", site = "apply_regime_overlay",
                                 source_desc = "regime_dt(build_daily_regime)", policy = c11_legacy)
  .g2 <- .ARO_C11$c11_legacy_gate(regime_dt, "n_axes_firing", site = "apply_regime_overlay",
                                  source_desc = "regime_dt(build_daily_regime)", policy = c11_legacy)
  if (!identical(isTRUE(.g$legacy), isTRUE(.g2$legacy)))
    stop("[apply_regime_overlay] MRS 와 n_axes_firing 의 가용일 상태가 다르다 — 한쪽만 가용일 결합할 수 없다")
  .n_aligned <- NA_integer_
  if (!isTRUE(.g$legacy)) {
    .dec <- .ARO_C11$c11_window_start(nav_dt$Date, extra_lag = extra_lag)
    .a1 <- .ARO_C11$c11_asof_align(.dec, regime_dt, "MRS")
    .a2 <- .ARO_C11$c11_asof_align(.dec, regime_dt, "n_axes_firing")
    .ARO_C11$assert_overlay_pit_avail(.a1$avail_date, .dec, "apply_regime_overlay MRS")
    .ARO_C11$assert_overlay_pit_avail(.a2$avail_date, .dec, "apply_regime_overlay n_axes_firing")
    nav_dt[, MRS := as.numeric(.a1$value)]
    nav_dt[, n_axes_firing := as.integer(.a2$value)]
    nav_dt[, regime_decision_date := .dec]
    nav_dt[, regime_avail_date := .a1$avail_date]
    .n_aligned <- sum(!is.na(.a1$value))
  } else {
    # legacy 재현(label 정책) — 구판 정렬 그대로. 결과는 C11 미해소(pit_c11 표식).
    regime_sub <- regime_dt[, .(Date, MRS, n_axes_firing)]
    regime_sub[, Date := as.Date(Date)]
    setkey(regime_sub, Date)
    nav_dt <- regime_sub[nav_dt, roll = TRUE]
    .k <- suppressWarnings(as.integer(extra_lag))
    if (length(.k) != 1L || is.na(.k) || .k < 0L) stop("[apply_regime_overlay] extra_lag 는 0 이상 정수")
    if (.k > 0L) {
      nav_dt[, MRS := shift(MRS, .k)]
      nav_dt[, n_axes_firing := shift(n_axes_firing, .k)]
    }
  }

  # ── Merge benchmark ───────────────────────────────────────────────
  bm_merge <- BM_DT[, .(Date = as.Date(Date), BM_Ret)]
  setkey(bm_merge, Date)
  nav_dt <- merge(nav_dt, bm_merge, by = "Date", all.x = TRUE)

  # ── Merge inverse ETF (or use -BM_Ret proxy) ─────────────────────
  if (!is.null(inv_dt)) {
    inv_merge <- inv_dt[, .(Date = as.Date(Date), Ret_Inv)]
    setkey(inv_merge, Date)
    nav_dt <- merge(nav_dt, inv_merge, by = "Date", all.x = TRUE)
    nav_dt[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
  } else {
    nav_dt[, Ret_Inv := -BM_Ret]
  }

  # ── Fill NAs ──────────────────────────────────────────────────────
  nav_dt[is.na(Ret_Inv), Ret_Inv := 0]
  nav_dt[is.na(MRS), MRS := 0]
  nav_dt[is.na(n_axes_firing), n_axes_firing := 0L]

  # ── Crisis detection ──────────────────────────────────────────────
  # PIT NOTE (C11): MRS 는 위 '가용일 결합'에서 이미 수익 창 시작까지 가용한 값이다. 여기서 추가 shift 하지 않는다
  #   (추가 지연은 extra_lag 인자 — C5 lag1 스트레스 전용).
  nav_dt[, crisis_flag := fifelse(
    MRS >= crisis_threshold$mrs & n_axes_firing >= crisis_threshold$axes, 1L, 0L
  )]

  nav_dt[, crisis_consec := {
    # Rcpp 분기: cpp_crisis_consec() 사용 시 ~2x speedup
    # weight_engine.cpp가 sourceCpp된 세션에서만 활성화
    if (exists("cpp_crisis_consec")) {
      cpp_crisis_consec(crisis_flag)
    } else {
      out <- integer(.N)
      cnt <- 0L
      for (j in seq_len(.N)) {
        if (crisis_flag[j] == 1L) { cnt <- cnt + 1L } else { cnt <- 0L }
        out[j] <- cnt
      }
      out
    }
  }]

  # ── Layer classification ──────────────────────────────────────────
  nav_dt[, Layer := fifelse(
    crisis_consec >= crisis_threshold$consec, 3L,
    fifelse(MRS >= caution_threshold, 2L, 1L)
  )]

  # ── Overlay return calculation ────────────────────────────────────
  nav_dt[, Ret_overlay := {
    r <- Strategy_Ret
    fcase(
      Layer == 1L, r,                                          # NORMAL: full exposure
      Layer == 2L, {
        f_w <- pmax(0.5, 1.0 - (MRS - caution_threshold) / 60)  # linear ramp
        f_w * r + (1 - f_w) * 0                                  # rest to cash
      },
      Layer == 3L, 0.50 * r + 0.20 * Ret_Inv + 0.30 * 0        # crisis hedge
    )
  }]

  # ── NAV calculation ───────────────────────────────────────────────
  nav_dt[, NAV_overlay := initial_cap * cumprod(1 + Ret_overlay)]

  # ── Build xts output ──────────────────────────────────────────────
  overlay_xts <- xts(nav_dt$Ret_overlay, order.by = nav_dt$Date)
  names(overlay_xts) <- "Strategy"

  # ── Layer distribution stats ──────────────────────────────────────
  layer_dist <- nav_dt[, .N, by = Layer]
  layer_dist[, Pct := round(N / sum(N) * 100, 1)]
  overlay_stats <- list(
    layer_distribution = layer_dist,
    crisis_days = sum(nav_dt$Layer == 3L),
    caution_days = sum(nav_dt$Layer == 2L),
    normal_days = sum(nav_dt$Layer == 1L)
  )

  cat(sprintf("[overlay] Applied. Normal: %d (%.0f%%) | Caution: %d (%.0f%%) | Crisis: %d (%.0f%%)\n",
              overlay_stats$normal_days,
              overlay_stats$normal_days / nrow(nav_dt) * 100,
              overlay_stats$caution_days,
              overlay_stats$caution_days / nrow(nav_dt) * 100,
              overlay_stats$crisis_days,
              overlay_stats$crisis_days / nrow(nav_dt) * 100))

  # ── Return ────────────────────────────────────────────────────────
  list(
    strategy_xts  = overlay_xts,
    bm_xts        = sim_result$bm_xts,
    DAILY_NAV_DT  = nav_dt,
    PORTFOLIO_LOG = sim_result$PORTFOLIO_LOG,
    HOLDINGS_LOG  = if ("HOLDINGS_LOG" %in% names(sim_result)) sim_result$HOLDINGS_LOG else NULL,
    overlay_stats = overlay_stats,
    pit_c11       = .ARO_C11$c11_consumption_record(.g, site = "apply_regime_overlay",
                                                    mode = "window_start(b): NAV 직전 행 = 수익 창 시작",
                                                    extra_lag = extra_lag, n_rows = nrow(nav_dt),
                                                    n_aligned = .n_aligned)
  )
}

cat("[apply_regime_overlay] Loaded. apply_regime_overlay(sim, regime_dt, BM_DT) — C11 규약 (b) 가용일 결합\n")
