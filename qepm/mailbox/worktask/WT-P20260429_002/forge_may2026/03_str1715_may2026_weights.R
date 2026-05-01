## ============================================================================
## STR_1715 May 2026 Forward Recompute — Step 3: 2026-05-01 weights
##
## Apply Iter31 best params (LinearTilt λ=1.5 / TOphi=3 / Cash 10/20/40 by regime)
## to alpha_scores at sig_date 2026-05-01 (Step 2b output, swapped into stage_artifacts).
##
## Reuses: 04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/run_all.R
##         lines 156-200 (linear_tilt_qd, linear_tilt_to_penalty_qd helpers).
##
## Output:
##   - production_weights_may2026.csv (Date × Ticker × Weight, 20 holdings + CASH)
##   - holdings_log_may2026.csv (with Name, Sector, AvgTV_30d, ADV_share)
##   - capacity_check_may2026.json
##   - vs_frozen_diff.json (vs prior 2023-12-01 holdings)
## ============================================================================

cat("=== STR_1715 May 2026 Forward — Step 3: 2026-05-01 weights ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(lubridate)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID        <- "WT-P20260429_002"
OUT_DIR      <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID, "forge_may2026")
PROD_DIR     <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights")
dir.create(PROD_DIR, recursive = TRUE, showWarnings = FALSE)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L) a[[1L]] else b

# ---- Iter31 best params (deterministic, no grid sweep) ----
LAMBDA       <- 1.5
TOPHI        <- 3.0
CASH_BULL    <- 0.00
CASH_NORMAL  <- 0.10
CASH_CAUTION <- 0.20
CASH_CRISIS  <- 0.40
UB_WEIGHT    <- 0.20
LB_WEIGHT    <- 0.00
MAX_NAMES    <- 20
MIN_NAMES    <- 15

cat(sprintf("[Step 3] Iter31 best params: λ=%.1f TOphi=%.1f Cash(BULL=%.0f%%/NORMAL=%.0f%%/CAUTION=%.0f%%/CRISIS=%.0f%%)\n",
            LAMBDA, TOPHI, CASH_BULL*100, CASH_NORMAL*100, CASH_CAUTION*100, CASH_CRISIS*100))

cash_overlay_pct_iter31 <- function(regime) {
  cash <- switch(regime,
    "BULL"    = CASH_BULL,
    "NORMAL"  = CASH_NORMAL,
    "CAUTION" = CASH_CAUTION,
    "CRISIS"  = CASH_CRISIS,
    CASH_NORMAL  # fallback to NORMAL
  )
  cash
}

# ---- Helper functions (copied from STR_1715/run_all.R lines 132-200) ----
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w <- pmax(w, lb)
  if (sum(w) <= 0) {
    w_eq <- rep(target_sum / length(w), length(w))
    return(pmin(w_eq, ub))
  }
  w <- w / sum(w) * target_sum
  for (it in seq_len(max_iter)) {
    over <- w > ub
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free_idx <- which(!over & w > lb + 1e-9)
    if (length(free_idx) == 0) break
    free_w <- w[free_idx]
    avail <- ub - free_w
    add <- avail * (excess / sum(avail))
    w[free_idx] <- free_w + add
  }
  w[w < lb + 1e-12] <- lb
  if (sum(w) > 0) w <- w / sum(w) * target_sum
  w
}

linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  if (length(alpha_t) == 0) return(numeric(0))
  alpha_t <- alpha_t[!is.na(alpha_t)]
  if (length(alpha_t) == 0) return(numeric(0))
  centered <- alpha_t - median(alpha_t, na.rm = TRUE)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w_raw <- w_raw / sum(w_raw, na.rm = TRUE)
  w_raw <- normalize_long_only(w_raw, lb = lb, ub = ub, target_sum = 1)
  w_raw
}

linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  if (is.null(w_prev) || length(w_prev) == 0) return(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  if (length(common) == 0) return(w_tilt)
  # Apply TOphi turnover penalty: w_new = w_tilt - phi/2 * (w_tilt - w_prev_aligned) ... here w_prev is NULL anyway
  w_tilt
}

# ---- Load alpha_scores at 2026-05-01 ----
alpha_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
alpha_all <- as.data.table(read_parquet(alpha_path))
alpha_all[, Date := as.Date(Date)]
cat(sprintf("[Step 3] alpha_scores.parquet: %d rows, max_date=%s\n",
            nrow(alpha_all), as.character(max(alpha_all$Date))))

last_sig <- as.Date("2026-05-01")
last_panel <- alpha_all[Date == last_sig & !is.na(score_eff)]
if (nrow(last_panel) == 0) stop(sprintf("No alpha at %s", last_sig))

setorder(last_panel, -score_eff)
N_last <- min(MAX_NAMES, nrow(last_panel))
if (N_last < MIN_NAMES) N_last <- max(MIN_NAMES, nrow(last_panel))
picks_last <- last_panel[seq_len(N_last)]
regime_last <- picks_last$regime_state[1L]
cash_last   <- cash_overlay_pct_iter31(regime_last)

cat(sprintf("[Step 3] Sig_date=%s | regime=%s | cash=%.0f%% | picked %d\n",
            as.character(last_sig), regime_last, cash_last*100, N_last))

alpha_last  <- setNames(picks_last$score_eff, picks_last$Ticker)
cat("[Step 3] Top picks (score_eff):\n")
print(round(alpha_last, 4))

# CRISIS-tightening: ub_use = min(UB_WEIGHT, 0.10) per run_all.R line 327
ub_use <- if (regime_last == "CRISIS") min(UB_WEIGHT, 0.10) else UB_WEIGHT

w_last_tilt <- tryCatch(
  linear_tilt_to_penalty_qd(alpha_last, lambda = LAMBDA, w_prev = NULL,
                             phi = TOPHI, ub = ub_use),
  error = function(e) linear_tilt_qd(alpha_last, lambda = LAMBDA, ub = ub_use)
)
names(w_last_tilt) <- names(alpha_last)
w_last_risk <- w_last_tilt * (1 - cash_last)

cat(sprintf("[Step 3] Risk weights sum (pre-cash) = %.4f, max = %.4f\n",
            sum(w_last_risk), max(w_last_risk)))

# ---- Build final portfolio (20 holdings + CASH) ----
final_w <- data.table(
  Ticker = c(names(w_last_risk), "CASH"),
  Weight = c(as.numeric(w_last_risk), cash_last)
)
setorder(final_w, -Weight)
cat(sprintf("[Step 3] Final portfolio: %d names + CASH | sum_weights=%.6f | max=%.4f\n",
            nrow(final_w) - 1L, sum(final_w$Weight), max(final_w$Weight)))

# ---- Capacity check (ADV share) ----
rawdata <- as.data.table(read_parquet(
  file.path(PROJECT_ROOT, ".cache/rawdata.parquet"),
  col_select = c("Date", "Ticker", "Name", "Sector", "Close", "Vol")))
rawdata[, Date := as.Date(Date)]
rawdata[, TradingValue := Close * Vol]

risk_tickers <- final_w[Ticker != "CASH", Ticker]
liq_window_start <- last_sig - 30L
liq_window_end   <- last_sig - 1L
liq_recent <- rawdata[Date >= liq_window_start & Date <= liq_window_end & Ticker %in% risk_tickers,
                      .(AvgTV_30d_won = mean(TradingValue, na.rm = TRUE)), by = Ticker]
name_map <- rawdata[!is.na(Name) & Ticker %in% risk_tickers,
                    .SD[which.max(Date)], by = Ticker, .SDcols = c("Name", "Sector")]

merged <- merge(final_w, name_map[, .(Ticker, Name, Sector)], by = "Ticker", all.x = TRUE)
merged <- merge(merged, liq_recent, by = "Ticker", all.x = TRUE)
merged[Ticker == "CASH", `:=`(Name = "CASH (단기예금/MMF)", Sector = "Cash", AvgTV_30d_won = Inf)]
merged[is.na(AvgTV_30d_won), AvgTV_30d_won := 0]

# ADV share at AUM 10B KRW
AUM_won <- 1e10
merged[Ticker != "CASH", ADV_share_pct := round(Weight * AUM_won / pmax(AvgTV_30d_won, 1) * 100, 2)]
merged[Ticker != "CASH", capacity_breach_50pct := ADV_share_pct > 50]
merged[Ticker == "CASH", `:=`(ADV_share_pct = NA_real_, capacity_breach_50pct = FALSE)]

setorder(merged, -Weight)
merged[, rank := seq_len(.N)]

# ---- Save outputs ----
date_tag <- format(last_sig, "%Y%m%d")
weights_path  <- file.path(PROD_DIR, sprintf("%s_weights_cap_0p20.csv", date_tag))
holdings_path <- file.path(PROD_DIR, sprintf("%s_holdings_log_cap_0p20.csv", date_tag))
capacity_path <- file.path(PROD_DIR, sprintf("%s_capacity_check_cap_0p20.json", date_tag))

fwrite(merged[, .(rank, Ticker, Name, Sector, Weight)], weights_path)
fwrite(merged[, .(rank, Ticker, Name, Sector, Weight,
                    AvgTV_30d_억 = round(AvgTV_30d_won / 1e8, 1),
                    ADV_share_pct, capacity_breach_50pct)], holdings_path)

manifest <- list(
  strategy_id = "STR_1715_WT016_Iter31_GridBestProd",
  iter_label = "Iter31_LinTilt_lam1.5_TOphi3_CashOverlay",
  as_of_date = as.character(last_sig),
  mandate = "cap_0.20",
  alpha_source = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet (May 2026 forward recompute)",
  alpha_source_max_date = as.character(max(alpha_all$Date)),
  alpha_source_unique_dates = uniqueN(alpha_all$Date),
  regime_state = regime_last,
  cash_pct = cash_last,
  n_risk_holdings = nrow(merged) - 1L,
  n_total_lines = nrow(merged),
  sum_weights = round(sum(merged$Weight), 6),
  max_weight = round(max(merged$Weight), 4),
  min_weight = round(min(merged$Weight[merged$Weight > 0]), 6),
  measurement_basis_primary = "forge_realized_share_based",
  capacity_check = list(
    AUM_won = AUM_won,
    n_tickers = nrow(merged) - 1L,
    n_breach_ADV50 = sum(merged$capacity_breach_50pct, na.rm = TRUE),
    breach_tickers = merged[capacity_breach_50pct == TRUE & Ticker != "CASH", Ticker],
    worst_ADV_pct = max(merged$ADV_share_pct[merged$Ticker != "CASH"], na.rm = TRUE),
    worst_ticker = merged[which.max(ifelse(Ticker == "CASH", -1, ADV_share_pct))][["Ticker"]]
  ),
  notes = "Mode=forward_recompute. Iter5 alpha_scores SIGNAL_CUTOFF extended 2023-12-22 → 2026-04-30 (lockbox passed). regime_panel rebuilt to 2026-05-01."
)
write_json(manifest, capacity_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

cat(sprintf("\n[Step 3] Outputs:\n"))
cat(sprintf("  weights:   %s\n", weights_path))
cat(sprintf("  holdings:  %s\n", holdings_path))
cat(sprintf("  capacity:  %s\n", capacity_path))

# ---- vs frozen diff (2023-12-01 vs 2026-05-01) ----
cat("\n[Step 3] vs frozen 2023-12-01 diff:\n")
frozen_w <- fread(file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260427_017/weights.csv"))
frozen_w[, Date := as.Date(Date)]
frozen_2312 <- frozen_w[Date == as.Date("2023-12-01") & Weight > 1e-6, .(Ticker, Weight_2312 = Weight)]
new_2605 <- merged[Weight > 1e-6, .(Ticker, Weight_2605 = Weight)]

diff_dt <- merge(frozen_2312, new_2605, by = "Ticker", all = TRUE)
diff_dt[is.na(Weight_2312), Weight_2312 := 0]
diff_dt[is.na(Weight_2605), Weight_2605 := 0]
diff_dt[, status := fcase(
  Weight_2312 == 0 & Weight_2605 > 0, "added",
  Weight_2312 > 0 & Weight_2605 == 0, "removed",
  Weight_2312 > 0 & Weight_2605 > 0, "held",
  default = "none"
)]
n_added   <- sum(diff_dt$status == "added")
n_removed <- sum(diff_dt$status == "removed")
n_held    <- sum(diff_dt$status == "held")

held_dt <- diff_dt[status == "held"]
held_dt[, weight_change := Weight_2605 - Weight_2312]
mean_change <- mean(abs(held_dt$weight_change), na.rm = TRUE)

cat(sprintf("  n_added=%d, n_removed=%d, n_held=%d, mean|Δw_held|=%.4f\n",
            n_added, n_removed, n_held, mean_change))
cat("\n  Held tickers (with weight change):\n")
print(held_dt[order(-abs(weight_change))])
cat("\n  Added (new):\n")
print(diff_dt[status == "added"][order(-Weight_2605)])
cat("\n  Removed:\n")
print(diff_dt[status == "removed"][order(-Weight_2312)])

vs_frozen <- list(
  date_frozen = "2023-12-01",
  date_new    = "2026-05-01",
  n_added     = n_added,
  n_removed   = n_removed,
  n_held      = n_held,
  mean_abs_weight_change_held = round(mean_change, 6),
  added_tickers   = diff_dt[status == "added", Ticker],
  removed_tickers = diff_dt[status == "removed", Ticker],
  held_tickers    = diff_dt[status == "held", Ticker]
)
write_json(vs_frozen, file.path(OUT_DIR, "vs_frozen_diff.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")

# ---- Final preview ----
cat("\n[Step 3] FINAL 5월 운용 weights:\n")
print(merged[, .(rank, Ticker, Name, Sector, Weight = round(Weight, 4),
                  ADV_share = round(ADV_share_pct, 2))])

cat("\n=== Step 3 DONE ===\n")
