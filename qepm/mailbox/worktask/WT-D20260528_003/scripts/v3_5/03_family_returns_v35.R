#==============================================================================
# Step 3 — 8-Family Top/Bot Decile Returns v3.5
#
# Purpose:
#   - Per sig_date, per family F_*, compute top-decile vs bot-decile return spread.
#   - Output: per-family monthly long-short return time series (for IC/weight derivation).
#
# v3 v3.5 corrections:
#   - 21d forward log_return (Phase 1 v3 retain), winsorize [-30%, +30%]
#   - Monthly non-overlap (1M horizon, each sig_date 다음 sig_date까지)
#   - K200 universe + liquidity filter (already applied in factor_panel)
#
# Output:
#   - outputs/v3_5/k200_family_lsret_v35.parquet
#     columns: Date, family, ls_simple_ret, top_simple_ret, bot_simple_ret, n_top, n_bot
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_5")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_5")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")
PANEL_PATH <- file.path(OUT_DIR, "k200_factor_panel_v35.parquet")

SIGNAL_CUTOFF <- as.Date("2023-12-22")
FAMILIES <- c("value","quality","momentum","growth","consensus","low_vol","size","dividend")
N_QUANTILE <- 10L
FORWARD_HORIZON <- 21L  # trading days ≈ 1M
WINSORIZE_BOUND <- 0.30  # ±30% Fama-French winsorize

cat("[Family Returns v3.5] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load panel + rawdata ----
panel <- as.data.table(read_parquet(PANEL_PATH))
panel[, Date := as.Date(Date)]
sig_dates <- sort(unique(panel$Date))
cat("[1] panel rows:", nrow(panel), " | sig_dates:", length(sig_dates), "\n")

rd <- as.data.table(read_parquet(RAWDATA, col_select = c("Date","Ticker","Close")))
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)

# Compute 21d forward log_return per Ticker
rd[, fwd_close := shift(Close, n = -FORWARD_HORIZON, type = "lag"), by = Ticker]
rd[!is.na(fwd_close) & !is.na(Close) & Close > 0, fwd_log_ret := log(fwd_close / Close)]
rd[!is.na(fwd_log_ret), fwd_simple_ret := exp(fwd_log_ret) - 1]
# Winsorize ±30%
rd[!is.na(fwd_log_ret), fwd_log_ret := pmin(pmax(fwd_log_ret, log(1 - WINSORIZE_BOUND)),
                                                log(1 + WINSORIZE_BOUND))]
rd[!is.na(fwd_simple_ret), fwd_simple_ret := pmin(pmax(fwd_simple_ret, -WINSORIZE_BOUND),
                                                       WINSORIZE_BOUND)]

# ---- 2. Per family per sig_date: top/bot decile L-S return ----
cat("[2] Per-family top/bot decile L-S return ...\n")
result_list <- list()

for (sig_d in sig_dates) {
  sig_d <- as.Date(sig_d)
  pn <- panel[Date == sig_d]
  rd_d <- rd[Date == sig_d & !is.na(fwd_log_ret), .(Ticker, fwd_log_ret, fwd_simple_ret)]
  pn <- merge(pn, rd_d, by = "Ticker", all.x = FALSE)
  if (nrow(pn) < 100) {
    next
  }

  for (fam in FAMILIES) {
    fc <- paste0("F_", fam)
    if (!fc %in% names(pn)) next
    sub <- pn[!is.na(get(fc))]
    if (nrow(sub) < N_QUANTILE * 5L) next

    # Decile assignment via rank-based ntile (robust to quantile boundary collapse e.g., F_size)
    sub[, rank_pct := frank(get(fc), na.last = "keep", ties.method = "average") / .N]
    sub[, decile := pmax(1L, pmin(N_QUANTILE, ceiling(rank_pct * N_QUANTILE)))]
    sub[, rank_pct := NULL]

    top_ret_log <- mean(sub[decile == N_QUANTILE, fwd_log_ret], na.rm = TRUE)
    bot_ret_log <- mean(sub[decile == 1L, fwd_log_ret], na.rm = TRUE)
    top_ret_simple <- mean(sub[decile == N_QUANTILE, fwd_simple_ret], na.rm = TRUE)
    bot_ret_simple <- mean(sub[decile == 1L, fwd_simple_ret], na.rm = TRUE)

    result_list[[length(result_list) + 1L]] <- data.table(
      Date = sig_d,
      family = fam,
      ls_log_ret = top_ret_log - bot_ret_log,
      ls_simple_ret = top_ret_simple - bot_ret_simple,
      top_log_ret = top_ret_log,
      bot_log_ret = bot_ret_log,
      top_simple_ret = top_ret_simple,
      bot_simple_ret = bot_ret_simple,
      n_top = sum(sub$decile == N_QUANTILE, na.rm = TRUE),
      n_bot = sum(sub$decile == 1L, na.rm = TRUE)
    )
  }
}

family_ret <- rbindlist(result_list, use.names = TRUE)
cat("  rows:", nrow(family_ret), " | sig_dates:", length(unique(family_ret$Date)), " | families:", length(unique(family_ret$family)), "\n")

# ---- 3. Output ----
write_parquet(family_ret, file.path(OUT_DIR, "k200_family_lsret_v35.parquet"))
write_parquet(family_ret, file.path(STAGE_DIR, "k200_family_lsret_v35.parquet"))

# Summary per family
summary_per_fam <- family_ret[, .(
  n_obs = .N,
  mean_ls_simple = round(mean(ls_simple_ret, na.rm = TRUE), 5),
  sd_ls_simple = round(sd(ls_simple_ret, na.rm = TRUE), 5),
  sr_annualized = round(mean(ls_simple_ret, na.rm = TRUE) / sd(ls_simple_ret, na.rm = TRUE) * sqrt(12), 3),
  mean_ls_log = round(mean(ls_log_ret, na.rm = TRUE), 5)
), by = family]
cat("\n--- per-family long-short summary ---\n")
print(summary_per_fam)

meta <- list(
  spec = "v3.5 top/bot decile family L-S return time series",
  forward_horizon_days = FORWARD_HORIZON,
  winsorize_bound = WINSORIZE_BOUND,
  n_quantile = N_QUANTILE,
  families = FAMILIES,
  n_sig_dates = length(unique(family_ret$Date)),
  n_obs = nrow(family_ret),
  per_family_summary = summary_per_fam,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(meta, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "k200_family_lsret_v35.meta.json"))

cat("\n[Family Returns v3.5] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
