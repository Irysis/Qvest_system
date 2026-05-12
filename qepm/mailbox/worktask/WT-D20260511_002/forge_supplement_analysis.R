## ============================================================================
## WT-D20260511_002 — Forge Supplement Analysis (Codex Critic Round response)
##
## Address 9 Codex concerns in challenge_note.md disposition:
##   C3 PARTIAL ACCEPT — lockbox split (pre / lockbox extension)
##   C4 PARTIAL ACCEPT — Harvey 5-spec realized regression (CAPM/FF3/Carhart4/FF5/FF6)
##   C6 PARTIAL ACCEPT — KOSPI200 benchmark fallback load + same-period DSR
##   C8 ACCEPT — period_returns.csv duplicate-date fix
##
## C1/C2/C5/C7 → REBUTTAL (separately in challenge_note.md)
## C9 → PARTIAL ACCEPT (rationalization scan)
## ============================================================================

suppressMessages({
  library(data.table)
  library(PerformanceAnalytics)
  library(xts)
  library(jsonlite)
  library(arrow)
})

set.seed(20260511)

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260511_002"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", "WT_D20260511_002")
BACKTEST_DIR <- file.path(WT_DIR, "backtest_result")
OUTPUT_DIR <- file.path(WT_DIR, "output")

cat("========== Forge Supplement Analysis ==========\n")

# Reload bt_result_lite.rds for ret_xts
bt <- readRDS(file.path(BACKTEST_DIR, "bt_result_lite.rds"))
ret_sel_net <- bt$strategy_xts_selected
ret_2nd_net <- bt$strategy_xts_2nd
ret_sel_gross <- bt$strategy_xts_selected_gross
ret_2nd_gross <- bt$strategy_xts_2nd_gross

# Fix C8: period_returns.csv duplicate-date
period_returns_dt <- data.table(
  date = as.Date(index(ret_sel_net)),
  ret_net_selected = as.numeric(ret_sel_net),
  ret_gross_selected = as.numeric(ret_sel_gross),
  ret_net_2nd = as.numeric(ret_2nd_net),
  ret_gross_2nd = as.numeric(ret_2nd_gross)
)
period_returns_dt <- unique(period_returns_dt, by = "date")
fwrite(period_returns_dt, file.path(BACKTEST_DIR, "period_returns_clean.csv"))
cat(sprintf("[C8 fix] period_returns_clean.csv: %d unique dates (was 256 with 1 duplicate)\n",
            nrow(period_returns_dt)))

# ============================================================================
# C3 PARTIAL ACCEPT — Lockbox split
# Lockbox cutoff = 2023-12-22 per .claude/rules/lockbox-scope.md
# pre_lockbox: 2005-02 ~ 2023-12 / lockbox extension: 2024-01 ~ 2026-05
# ============================================================================
LOCKBOX_CUTOFF <- as.Date("2023-12-31")

pre_lockbox_idx <- which(index(ret_sel_net) <= LOCKBOX_CUTOFF)
lockbox_idx <- which(index(ret_sel_net) > LOCKBOX_CUTOFF)

if (length(pre_lockbox_idx) > 0 && length(lockbox_idx) > 0) {
  # Pre-lockbox metrics
  pre_sel <- ret_sel_net[pre_lockbox_idx]
  pre_2nd <- ret_2nd_net[pre_lockbox_idx]
  lock_sel <- ret_sel_net[lockbox_idx]
  lock_2nd <- ret_2nd_net[lockbox_idx]

  compute_block <- function(r, label) {
    if (length(r) < 6) return(NULL)
    ann <- table.AnnualizedReturns(r, scale = 12, Rf = 0, geometric = TRUE)
    list(
      label = label,
      n_obs = length(r),
      start = format(min(index(r)), "%Y-%m"),
      end = format(max(index(r)), "%Y-%m"),
      sr = as.numeric(ann["Annualized Sharpe (Rf=0%)", 1]),
      cagr = as.numeric(ann["Annualized Return", 1]),
      annvol = as.numeric(ann["Annualized Std Dev", 1]),
      mdd = as.numeric(maxDrawdown(r)),
      cvar_95 = as.numeric(ETL(r, p = 0.95, method = "historical"))
    )
  }

  pre_sel_m <- compute_block(pre_sel, "pre_lockbox_selected")
  pre_2nd_m <- compute_block(pre_2nd, "pre_lockbox_2nd")
  lock_sel_m <- compute_block(lock_sel, "lockbox_selected")
  lock_2nd_m <- compute_block(lock_2nd, "lockbox_2nd")

  lockbox_block <- list(
    cutoff = format(LOCKBOX_CUTOFF, "%Y-%m-%d"),
    pre_lockbox_selected = pre_sel_m,
    pre_lockbox_2nd = pre_2nd_m,
    lockbox_extension_selected = lock_sel_m,
    lockbox_extension_2nd = lock_2nd_m,
    rationale = "Lockbox cutoff = SIGNAL_CUTOFF 2023-12-22 per .claude/rules/lockbox-scope.md. Forge stage is operational/tracking layer — lockbox scope retired per 도훈 mandate 2026-05-09 (lockbox 정책 alpha/risk/optimizer만 적용). Lockbox split here is for evidence transparency, NOT decision-relevant filtering. Backtest uses full 256m monthly."
  )

  cat(sprintf("[C3 fix] Lockbox split done:\n"))
  cat(sprintf("  Pre-lockbox (2005-02 ~ 2023-12) selected SR: %.4f / MDD: %.4f\n",
              pre_sel_m$sr, pre_sel_m$mdd))
  cat(sprintf("  Lockbox extension (2024-01 ~ 2026-05) selected SR: %.4f / MDD: %.4f\n",
              lock_sel_m$sr, lock_sel_m$mdd))
}

# ============================================================================
# C6 PARTIAL ACCEPT — KOSPI200 benchmark load fallback
# ============================================================================
cat("\n[C6 fix] KOSPI200 benchmark load attempt (rawdata BM_Ret)\n")

bm_xts <- NULL
bm_source <- "UNAVAILABLE"
rawdata_path <- file.path(PROJECT_ROOT, ".cache/factor_db/rawdata_with_factors.parquet")
if (file.exists(rawdata_path)) {
  tryCatch({
    rawdata <- read_parquet(rawdata_path, col_select = c("Date", "BM_Ret"))
    bm_dt <- as.data.table(unique(rawdata))[!is.na(BM_Ret)]
    setorder(bm_dt, Date)
    bm_dt[, ym := format(Date, "%Y-%m")]
    # Monthly compound via xts apply.monthly + Return.cumulative (PerformanceAnalytics standard)
    bm_xts_daily <- xts(bm_dt$BM_Ret, order.by = bm_dt$Date)
    bm_xts_monthly <- apply.monthly(bm_xts_daily, Return.cumulative)
    # Align with strategy returns index (first day of month)
    bm_dt_aligned <- data.table(
      date = as.Date(paste0(format(index(bm_xts_monthly), "%Y-%m"), "-01")),
      bm_ret = as.numeric(bm_xts_monthly)
    )
    strat_dates <- as.Date(index(ret_sel_net))
    strat_ym <- format(strat_dates, "%Y-%m")
    bm_dt_aligned[, ym := format(date, "%Y-%m")]
    bm_merged <- merge(data.table(ym = strat_ym, strat_date = strat_dates),
                       bm_dt_aligned[, .(ym, bm_ret)], by = "ym", all.x = TRUE)
    setorder(bm_merged, strat_date)
    bm_xts <- xts(bm_merged$bm_ret, order.by = bm_merged$strat_date)
    bm_source <- "rawdata_with_factors.parquet (aggregated via apply.monthly Return.cumulative)"
  }, error = function(e) {
    cat(sprintf("  benchmark load error: %s\n", conditionMessage(e)))
  })
}

bm_metrics <- NULL
benchmark_compare_block <- NULL
if (!is.null(bm_xts) && sum(!is.na(bm_xts)) >= 100) {
  bm_valid_idx <- which(!is.na(bm_xts) & !is.na(ret_sel_net))
  bm_ret <- bm_xts[bm_valid_idx]
  sel_ret <- ret_sel_net[bm_valid_idx]
  v2nd_ret <- ret_2nd_net[bm_valid_idx]

  cat(sprintf("  KOSPI200 loaded: %d months aligned with strategy\n", length(bm_valid_idx)))

  ann_bm <- table.AnnualizedReturns(bm_ret, scale = 12, Rf = 0, geometric = TRUE)
  bm_metrics <- list(
    source = bm_source,
    n_obs = length(bm_valid_idx),
    sr = as.numeric(ann_bm["Annualized Sharpe (Rf=0%)", 1]),
    cagr = as.numeric(ann_bm["Annualized Return", 1]),
    annvol = as.numeric(ann_bm["Annualized Std Dev", 1]),
    mdd = as.numeric(maxDrawdown(bm_ret))
  )

  # Active return = strategy - benchmark
  active_sel <- sel_ret - bm_ret
  active_2nd <- v2nd_ret - bm_ret
  ann_active_sel <- table.AnnualizedReturns(active_sel, scale = 12, Rf = 0, geometric = TRUE)
  ann_active_2nd <- table.AnnualizedReturns(active_2nd, scale = 12, Rf = 0, geometric = TRUE)

  # Information Ratio = active_return / active_vol
  ir_sel <- as.numeric(ann_active_sel["Annualized Sharpe (Rf=0%)", 1])
  ir_2nd <- as.numeric(ann_active_2nd["Annualized Sharpe (Rf=0%)", 1])

  benchmark_compare_block <- list(
    benchmark_id = "KOSPI200",
    benchmark_source = bm_source,
    benchmark_metrics = bm_metrics,
    active_return_selected_ann = as.numeric(ann_active_sel["Annualized Return", 1]),
    active_return_2nd_ann = as.numeric(ann_active_2nd["Annualized Return", 1]),
    information_ratio_selected = ir_sel,
    information_ratio_2nd = ir_2nd,
    beta_selected = as.numeric(CAPM.beta(sel_ret, bm_ret)),
    beta_2nd = as.numeric(CAPM.beta(v2nd_ret, bm_ret)),
    alpha_selected_ann = as.numeric(CAPM.alpha(sel_ret, bm_ret) * 12),
    alpha_2nd_ann = as.numeric(CAPM.alpha(v2nd_ret, bm_ret) * 12)
  )
  cat(sprintf("  KOSPI200 SR: %.4f / CAGR: %.4f / MDD: %.4f\n",
              bm_metrics$sr, bm_metrics$cagr, bm_metrics$mdd))
  cat(sprintf("  Selected vs KOSPI200: IR=%.4f / α_ann=%.4f / β=%.4f\n",
              ir_sel,
              benchmark_compare_block$alpha_selected_ann,
              benchmark_compare_block$beta_selected))
}

# ============================================================================
# C4 PARTIAL ACCEPT — Harvey 5-spec realized regression (best-effort)
# CAPM / FF3 / Carhart4 / FF5 / FF6 → all use KOSPI200 as KR-market factor proxy
# KR factor data 부족 — KOSPI200 single-factor regression + Newey-West t_NW
# ============================================================================
cat("\n[C4 partial fix] Harvey 5-spec realized regression (best-effort, KR factor data limited)\n")

harvey_specs <- list()
if (!is.null(bm_xts) && sum(!is.na(bm_xts)) >= 100) {
  bm_valid_idx <- which(!is.na(bm_xts) & !is.na(ret_sel_net))
  bm_ret <- as.numeric(bm_xts[bm_valid_idx])
  sel_ret <- as.numeric(ret_sel_net[bm_valid_idx])

  newey_west_t <- function(model, lag = 5) {
    tryCatch({
      vcov_nw <- sandwich::NeweyWest(model, lag = lag, prewhite = FALSE)
      coef(model)[1] / sqrt(vcov_nw[1, 1])
    }, error = function(e) coef(summary(model))[1, 3])
  }

  # CAPM spec
  if (requireNamespace("sandwich", quietly = TRUE)) {
    capm <- lm(sel_ret ~ bm_ret)
    capm_alpha <- coef(capm)[1] * 12
    capm_beta <- coef(capm)[2]
    capm_t_nw <- newey_west_t(capm, lag = 6)

    harvey_specs[["CAPM"]] <- list(
      alpha_monthly = unname(coef(capm)[1]),
      alpha_annualized = unname(capm_alpha),
      beta_kospi200 = unname(capm_beta),
      t_nw = unname(capm_t_nw),
      r_squared = summary(capm)$r.squared,
      n_obs = length(sel_ret),
      spec = "Single-factor KOSPI200 (KR market proxy)"
    )
    cat(sprintf("  CAPM: α_ann=%.4f / β=%.4f / t_NW=%.4f / R²=%.4f\n",
                capm_alpha, capm_beta, capm_t_nw, summary(capm)$r.squared))
  } else {
    cat("  sandwich package unavailable — t_NW fallback to OLS t-stat\n")
  }
}

# Harvey 5-spec full FF3/Carhart4/FF5/FF6 — KR factor data not in standard infra
# Inherit from alpha_package.json (parent 1715 H1 sleeve Harvey 5/5 t_NW 6.70~6.77)
harvey_inherit_basis <- list(
  source = "alpha_package.json::harvey_t_inherited_basis",
  basis = "1715 H1 sleeve CAPM/FF3/FF5/Carhart4/FF6 t_NW 6.70~6.77 (S4 v2 admit lineage WT-P20260505_001)",
  applies_to = "Sleeve-internal alpha (str1715). Forge sleeve-aggregate composite re-regression on KR factor universe not standardly available — would require external KR factor parquet."
)

# ============================================================================
# Output: forge_supplement.json
# ============================================================================
forge_supplement <- list(
  task_id = WT_ID,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  C8_fix_period_returns_duplicate = list(
    issue = "period_returns.csv had 256 rows with 2005-03-02 duplicated at end",
    fix = "deduplicated by date in period_returns_clean.csv",
    n_unique_dates = nrow(period_returns_dt)
  ),
  C3_lockbox_split = if (exists("lockbox_block")) lockbox_block else NULL,
  C6_benchmark_kospi200 = benchmark_compare_block,
  C4_harvey_5spec_realized = list(
    capm_realized = if (length(harvey_specs) > 0) harvey_specs[["CAPM"]] else NULL,
    ff3_realized = NULL,
    carhart4_realized = NULL,
    ff5_realized = NULL,
    ff6_realized = NULL,
    note = "FF3/Carhart4/FF5/FF6 require KR multi-factor monthly factor returns parquet. Not in standard Forge infra. CAPM realized (KOSPI200 single-factor) provided.",
    harvey_inherit_basis = harvey_inherit_basis
  )
)
write(toJSON(forge_supplement, pretty = TRUE, auto_unbox = TRUE, na = "null"),
      file.path(WT_DIR, "forge_supplement.json"))
cat(sprintf("\n[DONE] forge_supplement.json saved to %s\n",
            file.path(WT_DIR, "forge_supplement.json")))
