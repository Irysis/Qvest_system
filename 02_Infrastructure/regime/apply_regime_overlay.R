#==============================================================================
# apply_regime_overlay.R — 3-Layer Regime Overlay (정본 구현)
#
# 20+ 전략에 인라인으로 중복되던 overlay 코드를 단일 함수로 추출.
# STR_1631/run_all.R L527-578 기반.
#
# PIT NOTE:
#   regime_dt (from build_daily_regime()) 의 MRS는 이미 t-1 lagged.
#   regime_engine_daily.R Step 5, line 339:
#     dt[, MRS := shift(MRS_raw, n = 1L, type = "lag")]
#   이 함수에서 추가 shift() 금지 — 이중 lag는 t-2 오류.
#
# Usage:
#   source("02_Infrastructure/regime/apply_regime_overlay.R")
#   overlay <- apply_regime_overlay(sim_result, regime_dt, BM_DT)
#   overlay$strategy_xts   # overlaid daily returns (xts)
#   overlay$DAILY_NAV_DT   # full daily table with Layer, Ret_overlay, NAV
#   overlay$overlay_stats  # Layer 분포 통계
#
# Dependencies: data.table, xts
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
})

#' Apply 3-Layer Regime Overlay to a backtest result
#'
#' @param sim_result  list from run_monthly_simulation()
#'                    Must contain: DAILY_NAV_DT (Date, NAV, Strategy_Ret)
#' @param regime_dt   data.table from build_daily_regime()
#'                    Must contain: Date, MRS, n_axes_firing
#'                    MRS is ALREADY t-1 lagged (no additional shift needed)
#' @param BM_DT       benchmark data.table (Date, BM_Ret)
#' @param inv_dt      (optional) inverse ETF data.table (Date, Ret_Inv)
#'                    If NULL, uses -BM_Ret as proxy
#' @param crisis_threshold  list(mrs, axes, consec) for Layer 3 classification
#' @param caution_threshold numeric MRS threshold for Layer 2
#' @param initial_cap       initial capital for NAV calculation
#'
#' @return list(strategy_xts, bm_xts, DAILY_NAV_DT, overlay_stats)
apply_regime_overlay <- function(
  sim_result,
  regime_dt,
  BM_DT,
  inv_dt             = NULL,
  crisis_threshold   = list(mrs = 60, axes = 5, consec = 3),
  caution_threshold  = 30,
  initial_cap        = 1e8
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

  # ── Merge regime (roll join for date alignment) ────────────────────
  regime_sub <- regime_dt[, .(Date, MRS, n_axes_firing)]
  regime_sub[, Date := as.Date(Date)]
  setkey(regime_sub, Date)
  nav_dt <- regime_sub[nav_dt, roll = TRUE]

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
  # PIT NOTE: MRS is already t-1 lagged in regime_engine_daily.R (Step 5, line 339).
  # MRS[t] = MRS_raw[t-1]. No additional shift() needed — double-lag would create t-2 error.
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
    overlay_stats = overlay_stats
  )
}

cat("[apply_regime_overlay] Loaded. apply_regime_overlay(sim, regime_dt, BM_DT)\n")
