#==============================================================================
# Step 5 — Alpha Vector Construction (K200 stocks × sig_date)
#
# α̂(i, t) = Σ_f w_f(state(t)) × Z_composite_f(i, t)
#
# Per sig_date t:
#   1. regime_state(t) → factor weight w_f(t)  (from Step 4 walk-forward output)
#   2. Per family f, per K200 ticker i: Z_composite_f(i, t) computed from
#      factor_db using same direction-aligned multi-proxy logic as Phase 1 v3
#   3. α̂(i, t) = Σ_f w_f(t) · Z_composite_f(i, t) (cross-sectional rank 정합)
#
# Output:
#   - stage_artifacts/WT_D20260528_003/alpha_scores.parquet
#         columns: Date (sig_date) × Ticker × alpha_score, regime_state,
#                  factor breakdown (Z_value..Z_dividend, w_value..w_dividend),
#                  rank_within_universe
#   - outputs/alpha_diagnostics.json (per sig_date α̂ summary)
#
# Confidence vector:
#   c(i, t) = clip_01(n_proxies_used / 20)
#     where 20 = total proxies across 6 families (max coverage)
#
# PIT:
#   - factor_db Z_Score = already PIT (C14)
#   - regime_state from walk-forward (C1)
#   - SIGNAL_CUTOFF respected (alpha-research lockbox scope per .claude/rules/lockbox-scope.md)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs")
SHARED_OUT <- file.path(BASE, "04_Research/decision_framework/smart_beta_regime/outputs")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003")
FACTOR_DB <- file.path(BASE, ".cache/factor_db")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")

dir.create(STAGE_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- Lockbox cutoff (정규 리서치 alpha-research scope per .claude/rules/lockbox-scope.md) ----
SIGNAL_CUTOFF <- as.Date("2023-12-22")  # PIT lockbox cutoff. Train + validation only.

FAMILIES <- list(
  value = list(
    proxies = list(
      list(name = "V01_BM",       direction = "higher_better"),
      list(name = "V02_EP",       direction = "higher_better"),
      list(name = "V03_CFP",      direction = "higher_better"),
      list(name = "V20_SP",       direction = "higher_better"),
      list(name = "V14_EBIT_EV",  direction = "higher_better")
    )
  ),
  quality = list(
    proxies = list(
      list(name = "Q02_ROE",          direction = "higher_better"),
      list(name = "Q03_ROA",          direction = "higher_better"),
      list(name = "Q17_ROIC",         direction = "higher_better"),
      list(name = "GR05_ROE_Growth",  direction = "higher_better")
    )
  ),
  momentum = list(
    proxies = list(
      list(name = "M01_Mom_12_1", direction = "higher_better"),
      list(name = "M02_Mom_6_1",  direction = "higher_better"),
      list(name = "M03_Mom_3_1",  direction = "higher_better")
    )
  ),
  low_vol = list(
    proxies = list(
      list(name = "D01_IdioVol",       direction = "lower_better"),
      list(name = "D02_Beta",          direction = "lower_better"),
      list(name = "D03_RealVol",       direction = "lower_better"),
      list(name = "D04_Downside_Beta", direction = "lower_better")
    )
  ),
  size = list(
    proxies = list(list(name = "S01_Size", direction = "lower_better"))
  ),
  dividend = list(
    proxies = list(
      list(name = "V06_fDY",               direction = "higher_better"),
      list(name = "V11_Shareholder_Yield", direction = "higher_better"),
      list(name = "V17_Payout_Ratio",      direction = "higher_better")
    )
  )
)

FAMILIES_LIST <- c("value", "quality", "momentum", "low_vol", "size", "dividend")
TOTAL_PROXIES <- sum(sapply(FAMILIES, function(f) length(f$proxies)))  # = 20
LIQ_FLOOR_KRW <- 2.0e8
LIQ_WINDOW <- 20L

cat("[Step 5 Alpha Compute] === START ===\n")
t0 <- Sys.time()
cat("  SIGNAL_CUTOFF (lockbox):", as.character(SIGNAL_CUTOFF), "\n")

# ---- 1. Load Weight Matrix (walk-forward) ----
cat("[1] Loading walk-forward weight matrix ...\n")
W <- as.data.table(read_parquet(file.path(SHARED_OUT, "regime_factor_weight_matrix_walkforward.parquet")))
W[, sig_date := as.Date(sig_date)]
W <- W[sig_date <= SIGNAL_CUTOFF]  # lockbox
setorder(W, sig_date)
cat("  W rows (after lockbox):", nrow(W), " | range:", as.character(min(W$sig_date)), "~", as.character(max(W$sig_date)), "\n")

# ---- 2. Load rawdata for K200 + liquidity filter ----
cat("[2] Loading rawdata for K200 + liquidity filter ...\n")
rd <- as.data.table(read_parquet(RAWDATA,
                                  col_select = c("Date", "Ticker", "Close", "Vol", "K200")))
rd[, Date := as.Date(Date)]
rd[, tv := Vol * Close]
setorder(rd, Ticker, Date)
rd[, tv_20d_avg := frollmean(tv, n = LIQ_WINDOW, fill = NA, align = "right"), by = Ticker]
rd[, liq_pass := shift(tv_20d_avg, n = 1L, type = "lag", fill = NA) >= LIQ_FLOOR_KRW, by = Ticker]

# ---- 3. Per sig_date, build factor_db Z + K200 universe + α̂ ----
cat("[3] Computing α̂(i, t) per sig_date ...\n")

all_proxy_ids <- unique(unlist(lapply(FAMILIES, function(f) sapply(f$proxies, `[[`, "name"))))

compute_family_z_per_ticker <- function(fdb_at_date, family_spec) {
  # Returns data.table: Ticker × Z_composite_<family> × n_proxies
  proxies <- family_spec$proxies
  proxy_dts <- list()
  for (i in seq_along(proxies)) {
    p <- proxies[[i]]
    sub <- fdb_at_date[Factor_Name == p$name, .(Ticker, Z_Score)]
    if (nrow(sub) == 0) next
    if (p$direction == "lower_better") sub[, Z_aligned := -Z_Score]
    else sub[, Z_aligned := Z_Score]
    sub[, Z_Score := NULL]
    setnames(sub, "Z_aligned", paste0("Z_", p$name))
    proxy_dts[[i]] <- sub
  }
  proxy_dts <- Filter(Negate(is.null), proxy_dts)
  if (length(proxy_dts) == 0) {
    return(data.table(Ticker = character(), Z_composite = numeric(), n_proxies = integer()))
  }
  out <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE), proxy_dts)
  z_cols <- grep("^Z_", names(out), value = TRUE)
  out[, Z_composite := rowMeans(.SD, na.rm = TRUE), .SDcols = z_cols]
  out[, n_proxies := rowSums(!is.na(.SD)), .SDcols = z_cols]
  out[is.nan(Z_composite), Z_composite := NA_real_]
  out[, c("Ticker", "Z_composite", "n_proxies"), with = FALSE]
}

alpha_rows <- list()
diag_rows <- list()

# Per W row (each sig_date with regime + weights)
for (i in seq_len(nrow(W))) {
  sig_d <- W$sig_date[i]
  state <- W$regime_state[i]
  w_fam <- setNames(as.numeric(W[i, ..FAMILIES_LIST]), FAMILIES_LIST)

  # Load factor_db for sig_d (per-month parquet)
  ym_compact <- format(sig_d, "%Y%m")
  fdb_file <- file.path(FACTOR_DB, paste0("factor_db_", ym_compact, ".parquet"))
  if (!file.exists(fdb_file)) next

  fdb <- as.data.table(read_parquet(fdb_file,
                                     col_select = c("Date", "Ticker", "Factor_Name", "Z_Score")))
  fdb[, Date := as.Date(Date)]
  # Match exact Date in factor_db that matches sig_d (factor_db has one Date per month-end)
  fdb_dates <- unique(fdb$Date)
  fdb_d <- fdb_dates[which.min(abs(as.integer(fdb_dates - sig_d)))]
  fdb_t <- fdb[Date == fdb_d & Factor_Name %in% all_proxy_ids]
  if (nrow(fdb_t) == 0) next

  # K200 universe + liquidity at sig_d
  # K200 membership: nearest trading day to sig_d
  univ <- rd[Date >= sig_d - 7L & Date <= sig_d + 7L & K200 == 1.0 & liq_pass == TRUE,
              .SD[.N], by = Ticker][, .(Ticker)]
  if (nrow(univ) < 100) next

  # Per family Z_composite
  per_family_z <- list()
  for (fam in FAMILIES_LIST) {
    z_dt <- compute_family_z_per_ticker(fdb_t, FAMILIES[[fam]])
    if (nrow(z_dt) > 0) {
      setnames(z_dt, c("Z_composite", "n_proxies"),
                c(paste0("Z_", fam), paste0("n_", fam)))
      per_family_z[[fam]] <- z_dt
    }
  }
  if (length(per_family_z) == 0) next

  # Merge all into single panel
  alpha_panel <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE),
                         per_family_z)
  alpha_panel <- merge(alpha_panel, univ, by = "Ticker")
  if (nrow(alpha_panel) < 50) next

  # α̂(i, t) = Σ_f w_f(state(t)) × Z_f(i, t)
  z_fam_cols <- paste0("Z_", FAMILIES_LIST)
  n_fam_cols <- paste0("n_", FAMILIES_LIST)
  alpha_panel[, alpha_score := 0]
  for (fam in FAMILIES_LIST) {
    z_c <- paste0("Z_", fam)
    if (z_c %in% names(alpha_panel)) {
      v <- alpha_panel[[z_c]]
      v[is.na(v)] <- 0
      alpha_panel[, alpha_score := alpha_score + w_fam[[fam]] * v]
    }
  }
  alpha_panel[, sig_date := sig_d]
  alpha_panel[, regime_state := state]
  # weight columns
  for (fam in FAMILIES_LIST) {
    alpha_panel[, (paste0("w_", fam)) := w_fam[[fam]]]
  }
  # confidence vector: n_proxies_used / 20
  alpha_panel[, n_proxies_total := rowSums(.SD, na.rm = TRUE), .SDcols = n_fam_cols]
  alpha_panel[, confidence := pmin(1, pmax(0, n_proxies_total / TOTAL_PROXIES))]
  # cross-sectional rank (1 = highest alpha)
  alpha_panel[, rank_within_universe := rank(-alpha_score, ties.method = "first")]

  alpha_rows[[length(alpha_rows) + 1]] <- alpha_panel

  # diagnostic
  diag_rows[[length(diag_rows) + 1]] <- list(
    sig_date = as.character(sig_d),
    regime_state = state,
    n_universe = nrow(alpha_panel),
    alpha_mean = mean(alpha_panel$alpha_score, na.rm = TRUE),
    alpha_sd = sd(alpha_panel$alpha_score, na.rm = TRUE),
    alpha_p99 = quantile(alpha_panel$alpha_score, 0.99, na.rm = TRUE),
    alpha_p01 = quantile(alpha_panel$alpha_score, 0.01, na.rm = TRUE),
    conf_mean = mean(alpha_panel$confidence, na.rm = TRUE),
    w_value = w_fam[["value"]], w_quality = w_fam[["quality"]],
    w_momentum = w_fam[["momentum"]], w_low_vol = w_fam[["low_vol"]],
    w_size = w_fam[["size"]], w_dividend = w_fam[["dividend"]]
  )
}

alpha_dt <- rbindlist(alpha_rows, fill = TRUE)
setorder(alpha_dt, sig_date, rank_within_universe)
cat("  Total alpha rows:", nrow(alpha_dt), " | distinct sig_dates:", uniqueN(alpha_dt$sig_date), "\n")
cat("  α̂ summary:\n")
print(summary(alpha_dt$alpha_score))
cat("  confidence summary:\n")
print(summary(alpha_dt$confidence))

# ---- 4. Save outputs ----
cat("[4] Saving outputs ...\n")
# rename sig_date → Date for stage_artifacts convention
alpha_dt[, Date := sig_date]
keep_cols <- c("Date", "Ticker", "alpha_score", "regime_state",
                paste0("Z_", FAMILIES_LIST),
                paste0("w_", FAMILIES_LIST),
                "n_proxies_total", "confidence", "rank_within_universe")
keep_cols <- intersect(keep_cols, names(alpha_dt))
alpha_out <- alpha_dt[, ..keep_cols]
write_parquet(alpha_out, file.path(STAGE_DIR, "alpha_scores.parquet"))
write_parquet(alpha_out, file.path(OUT_DIR, "alpha_scores.parquet"))

diag_dt <- rbindlist(diag_rows, fill = TRUE)
writeLines(toJSON(diag_dt, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "alpha_diagnostics_per_sigdate.json"))

cat("[Step 5] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
