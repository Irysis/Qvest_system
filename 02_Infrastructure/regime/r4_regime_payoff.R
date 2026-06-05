#==============================================================================
# R4 Regime Payoff — 국면별 전략 성과 자동 계산 + 저장
#
# Forge가 매 백테스트 완료 후 호출하여 R4 레이어에 국면별 성과를 축적한다.
# Axiom 스캔(R7)이 R4 데이터를 참조하여 "어떤 국면에서 통하는가" 판단.
#
# Usage:
#   source("02_Infrastructure/r4_regime_payoff.R")
#   compute_and_store_r4(sim, strategy_id, family)
#==============================================================================

cat("[r4_regime_payoff] Loading...\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}

#' Compute regime payoff and store to R4
#'
#' @param sim list with strategy_xts, bm_xts, DAILY_NAV_DT
#' @param strategy_id character e.g. "STR_1039"
#' @param family character e.g. "regime_alloc"
#' @param regime_dt optional pre-built regime data.table. If NULL, builds from option2.
#' @return data.table with regime-conditional performance
compute_and_store_r4 <- function(sim, strategy_id, family, regime_dt = NULL) {

  cat(sprintf("[R4] Computing regime payoff for %s (family=%s)...\n", strategy_id, family))

  # 1. Get daily returns
  if (!is.null(sim$DAILY_NAV_DT)) {
    daily <- copy(sim$DAILY_NAV_DT)
    if (!"Strategy_Ret" %in% names(daily)) {
      daily[, Strategy_Ret := c(NA, diff(NAV)/head(NAV, -1))]
    }
  } else if (!is.null(sim$strategy_xts)) {
    daily <- data.table(
      Date = as.Date(index(sim$strategy_xts)),
      Strategy_Ret = as.numeric(sim$strategy_xts)
    )
  } else {
    cat("[R4] No return data found. Skipping.\n")
    return(NULL)
  }

  daily[, YM := substr(as.character(Date), 1, 7)]

  # 2. Build or use regime
  if (is.null(regime_dt)) {
    tryCatch({
      source(file.path(PROJECT_ROOT, "02_Infrastructure", "regime", "regime_engine_option2.R"))
      regime_dt <- build_regime_option2()
    }, error = function(e) {
      cat("[R4] Cannot build regime:", e$message, "\n")
      return(NULL)
    })
  }

  # 3. Merge regime with daily returns
  regime_monthly <- regime_dt[, .(apply_month, MRS, exposure)]
  merged <- merge(daily, regime_monthly, by.x = "YM", by.y = "apply_month", all.x = TRUE)

  # Fill missing MRS with 0 (normal)
  merged[is.na(MRS), MRS := 0]

  # 4. Classify regime states
  merged[, regime_state := fifelse(MRS >= 25, "crisis",
                             fifelse(MRS >= 12, "elevated", "risk_on"))]

  # 5. Compute per-regime metrics
  payoff <- merged[!is.na(Strategy_Ret), .(
    mean_ret_ann = mean(Strategy_Ret, na.rm = TRUE) * 252,
    vol_ann = sd(Strategy_Ret, na.rm = TRUE) * sqrt(252),
    sharpe = fifelse(sd(Strategy_Ret, na.rm = TRUE) > 0,
                     mean(Strategy_Ret, na.rm = TRUE) / sd(Strategy_Ret, na.rm = TRUE) * sqrt(252),
                     0),
    mdd = {
      nav <- cumprod(1 + Strategy_Ret)
      dd <- 1 - nav / cummax(nav)
      -max(dd, na.rm = TRUE)
    },
    n_days = .N,
    n_months = uniqueN(YM)
  ), by = regime_state]

  # 6. Also compute full-sample
  full_sample <- merged[!is.na(Strategy_Ret), .(
    regime_state = "full_sample",
    mean_ret_ann = mean(Strategy_Ret, na.rm = TRUE) * 252,
    vol_ann = sd(Strategy_Ret, na.rm = TRUE) * sqrt(252),
    sharpe = mean(Strategy_Ret, na.rm = TRUE) / sd(Strategy_Ret, na.rm = TRUE) * sqrt(252),
    mdd = {
      nav <- cumprod(1 + Strategy_Ret)
      dd <- 1 - nav / cummax(nav)
      -max(dd, na.rm = TRUE)
    },
    n_days = .N,
    n_months = uniqueN(YM)
  )]

  payoff <- rbind(payoff, full_sample)

  cat(sprintf("[R4] Regime payoff computed:\n"))
  print(payoff)

  # 7. Store via hybrid_store_regime_payoff (if available)
  if (exists("hybrid_store_regime_payoff")) {
    for (i in 1:nrow(payoff)) {
      tryCatch({
        hybrid_store_regime_payoff(
          fam = family,
          regime = payoff$regime_state[i],
          const = strategy_id,
          m = as.list(payoff[i, .(mean_ret_ann, vol_ann, sharpe, mdd)]),
          n = payoff$n_months[i]
        )
      }, error = function(e) {
        cat(sprintf("[R4] hybrid_store error for %s: %s\n", payoff$regime_state[i], e$message))
      })
    }
    cat(sprintf("[R4] Stored %d regime payoffs for %s\n", nrow(payoff), strategy_id))
  } else {
    # Fallback: save as JSON
    r4_dir <- file.path(PROJECT_ROOT, "qepm", "memory", "regime_payoff")
    dir.create(r4_dir, recursive = TRUE, showWarnings = FALSE)
    r4_path <- file.path(r4_dir, sprintf("%s_%s.json", family, strategy_id))

    jsonlite::write_json(
      list(strategy_id = strategy_id, family = family,
           computed_at = as.character(Sys.time()),
           payoff = payoff),
      r4_path, pretty = TRUE, auto_unbox = TRUE
    )
    cat(sprintf("[R4] Saved to %s\n", r4_path))
  }

  payoff
}

cat("[r4_regime_payoff] Loaded. Function: compute_and_store_r4(sim, strategy_id, family)\n")
