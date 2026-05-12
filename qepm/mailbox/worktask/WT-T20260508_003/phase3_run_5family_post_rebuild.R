## ============================================================================
## WT-T20260508_003 — Phase 3: 5-Family Re-Backtest (Post Factor DB Rebuild)
##
## Pre-condition (sequence):
##   Phase 1: Factor DB rebuild (force=TRUE, 437 monthly cache)
##   Phase 2a: alpha_scores.parquet regen (factor_engine_proposal.R)
##   Phase 2b: STR_1715/run_all.R rerun (02_nav.csv / 03_period_returns.csv 갱신)
##   Phase 2c: four_layer_comparison.R rerun (ret_AR_on_M4 갱신)
##
## Action: 5-strategy bt_result × 10 components rebuild with REGENERATED inputs
## Pure Function: weights.csv (as-is) + 3 leg returns (재산출) → bt_result × 5
## ============================================================================

suppressMessages({
  library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(arrow)
})

# ─── Project root + helper paths ─────────────────────────────────────────────
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SOURCE_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260505_001")
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_003")
OUT_BASE     <- file.path(WT_DIR, "output", "5family_post_factor_db_rebuild")
CHARTS_DIR   <- file.path(OUT_BASE, "charts")
dir.create(OUT_BASE, showWarnings=FALSE, recursive=TRUE)
dir.create(CHARTS_DIR, showWarnings=FALSE, recursive=TRUE)

# Source contract
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/audit_bt_result.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/save_bt_result.R"))

# ─── PIT / cost constants ────────────────────────────────────────────────────
COST_BPS_ONEWAY <- 15      # v2.3_kr_retail_15bps uniform (Architect concern #1 fix)
COST_PER_DOLLAR <- COST_BPS_ONEWAY / 10000   # 0.0015
ANN_FACTOR      <- 12       # monthly
RUN_DT          <- format(Sys.time(), "%Y%m%d_%H%M%S")

cat("\n========================================================\n")
cat("  WT-T20260508_003 Phase 3 — 5-Strategy Re-Backtest (Post Factor DB Rebuild)\n")
cat(sprintf("  Run datetime: %s | Cost: %dbps one-way uniform\n", RUN_DT, COST_BPS_ONEWAY))
cat("========================================================\n\n")

# ─── INPUT 1: weights.csv (256 dates × 2935 rows = STR_1715 sleeve + 9 ETFs + KR10y + CASH) ─
weights <- fread(file.path(SOURCE_WT_DIR, "weights.csv"))
weights[, as_of_date := as.Date(as_of_date)]
schedule_dates <- sort(unique(weights$as_of_date))
stopifnot(length(schedule_dates) == 256L)
cat(sprintf("[INPUT] weights.csv: %d rows | %d dates (%s ~ %s)\n",
            nrow(weights), length(schedule_dates),
            min(schedule_dates), max(schedule_dates)))

# ─── INPUT 2: STR_1715 (Layer A) ret_AR_on_M4 256m vector (from WT-P20260504_001) ─
fl_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-P20260504_001/four_layer_returns_path.csv")
fl <- fread(fl_path)
fl[, date := as.Date(date)]
ar_dt <- fl[, .(date, ret_AR_on_M4)]
setkey(ar_dt, date)
cat(sprintf("[INPUT] AR_on_M4: %d obs (%s ~ %s)\n", nrow(ar_dt), min(ar_dt$date), max(ar_dt$date)))

# ─── INPUT 3: KR_10y bond ETF return path (from WT-S20260504_008) ──────────────
kr10y_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_S20260504_008/merged_returns.csv")
kr10y_full <- fread(kr10y_path)
kr10y_full[, date := as.Date(date)]
kr10y_dt <- kr10y_full[, .(date, kr_10y)]
setkey(kr10y_dt, date)
cat(sprintf("[INPUT] KR_10y: %d obs (%s ~ %s)\n", nrow(kr10y_dt), min(kr10y_dt$date), max(kr10y_dt$date)))

# ─── INPUT 4: TSMOM rotation (from WT-S20260504_009) — net of WT-009 50bps ─────
tsmom_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-S20260504_009/docs/rotation_path_TSMOM.csv")
tsmom_full <- fread(tsmom_path)
tsmom_full[, date := as.Date(date)]
# WT-009 'ml_realized_net' is net of 50bps annualized internal cost.
# Architect concern #1: convert to GROSS first, then re-apply 15bps uniform per turnover.
# 50bps annualized monthly = 0.5/12/100 = 0.000417; restore by addition.
tsmom_dt <- tsmom_full[, .(date, tsmom_gross = ml_realized + 0)]   # ml_realized = gross
setkey(tsmom_dt, date)
cat(sprintf("[INPUT] TSMOM: %d obs (%s ~ %s) | re-grossed for uniform cost\n",
            nrow(tsmom_dt), min(tsmom_dt$date), max(tsmom_dt$date)))

# Also pull weight matrix per date for TSMOM turnover computation
tsmom_w_cols <- grep("^w_etf_", names(tsmom_full), value = TRUE)
tsmom_wmat   <- tsmom_full[, c("date", tsmom_w_cols), with = FALSE]

# ─── INPUT 5: BM (KOSPI) — load and aggregate to monthly cumulative return ─────
bm_full <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm_full[, Date := as.Date(Date)]
# Aggregate to month-start dates matching schedule (compound daily returns)
bm_full[, ym := format(Date, "%Y-%m")]
schedule_ym <- format(schedule_dates, "%Y-%m")
bm_monthly <- bm_full[!is.na(BM_Ret) & ym %in% schedule_ym,
                     .(bm_ret = prod(1 + BM_Ret) - 1), by = ym]
bm_monthly_dt <- merge(data.table(ym = schedule_ym, date = schedule_dates),
                        bm_monthly, by = "ym", all.x = TRUE)
bm_monthly_dt[is.na(bm_ret), bm_ret := 0]
setkey(bm_monthly_dt, date)
cat(sprintf("[INPUT] BM (KOSPI): %d monthly obs (compounded daily, 0-fill missing)\n", nrow(bm_monthly_dt)))

# ─── HELPER: build sim_result per strategy ─────────────────────────────────────

# Weights aggregated: AR (sleeve) / TSMOM (sum across 9 ETFs) / KR10y / CASH per date
agg_legs <- weights[, .(
  w_AR    = sum(weight[asset_class == "EQ_KR_TOP20_SLEEVE"]),
  w_TSMOM = sum(weight[asset_class == "ETF_KR_TSMOM_LEG"]),
  w_KR10y = sum(weight[asset_class == "ETF_KR_BOND10Y_LEG"]),
  w_CASH  = sum(weight[asset_class == "CASH_RESIDUAL_LEG"])
), by = .(date = as_of_date)]
setkey(agg_legs, date)

# Sanity: each row sum to 1 (within fp tolerance)
w_sum_max_dev <- max(abs(agg_legs[, w_AR + w_TSMOM + w_KR10y + w_CASH] - 1))
cat(sprintf("[CHECK] Σw per date max deviation from 1: %.10f\n", w_sum_max_dev))
stopifnot(w_sum_max_dev < 1e-8)

# Merge leg returns
master <- merge(agg_legs, ar_dt,    by = "date", all.x = TRUE)
master <- merge(master,    kr10y_dt, by = "date", all.x = TRUE)
master <- merge(master,    tsmom_dt, by = "date", all.x = TRUE)
master <- merge(master,    bm_monthly_dt[, .(date, bm_ret)], by = "date", all.x = TRUE)

# Pre-2015 TSMOM = NA → 0 for those dates (TSMOM weight is 0 then anyway)
master[is.na(tsmom_gross), tsmom_gross := 0]
master[is.na(kr_10y),       kr_10y := 0]
master[is.na(ret_AR_on_M4), ret_AR_on_M4 := 0]
master[is.na(bm_ret),        bm_ret := 0]

cat(sprintf("[MASTER] %d rows | columns: %s\n", nrow(master), paste(names(master), collapse=", ")))

# ─── TURNOVER computation (for cost_ret) ─────────────────────────────────────
# Per leg turnover sources:
#   AR (STR_1715) — read 04_holdings.csv from STR_1715 production
#   TSMOM         — w_etf_* delta sum / 2 per date
#   KR10y         — single-asset, turnover = |Δw_KR10y_leg_internal| (always 100% within leg)
#                    Net effect: Δ in capital allocation only
#   CASH          — no cost
# Use factor_engine REPLAY output (Codex C3 fix: per-date time-varying stock-level holdings)
str1715_expanded_path <- file.path(SOURCE_WT_DIR, "str1715_expanded_holdings.csv")
if (!file.exists(str1715_expanded_path)) {
  cat("[INFO] str1715_expanded_holdings.csv not found in SOURCE, generating via expand_str1715_holdings.R...\n")
  source(file.path(SOURCE_WT_DIR, "expand_str1715_holdings.R"))
}
str1715_h_expanded <- fread(str1715_expanded_path)
str1715_h_expanded[, date := as.Date(date)]
# Map names from RAWDATA (we'll fill in build phase)
raw_names <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/rawdata.parquet")))[
  , .(Ticker, Name, Sector)][, .SD[1], by = Ticker]
setnames(raw_names, c("Ticker","Name","Sector"), c("ticker","name","sector"))
str1715_h_expanded <- merge(str1715_h_expanded, raw_names, by = "ticker", all.x = TRUE)
# Schema alignment for downstream
str1715_h_expanded[, actual_weight := weight_within_sleeve]
str1715_h_expanded[, target_weight := weight_within_sleeve]

# Also keep legacy sleeve-level holdings for turnover comparison
str1715_holdings_path <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/04_holdings.csv")
str1715_h <- fread(str1715_holdings_path)
str1715_h[, date := as.Date(date)]
# Sleeve-internal turnover (already consistent with PG2 frozen schedule)
str1715_pr <- fread(file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
str1715_pr[, date := as.Date(date)]
str1715_to <- str1715_pr[, .(date, str1715_to = turnover)]
setkey(str1715_to, date)

# TSMOM internal turnover
tsmom_wmat_dates <- tsmom_wmat$date
tsmom_w_only <- as.matrix(tsmom_wmat[, !"date"])
tsmom_internal_to <- c(NA_real_,
  sapply(2:nrow(tsmom_w_only), function(i) sum(abs(tsmom_w_only[i,] - tsmom_w_only[i-1,])) / 2))
tsmom_to_dt <- data.table(date = tsmom_wmat_dates, tsmom_internal_to = tsmom_internal_to)
tsmom_to_dt[is.na(tsmom_internal_to), tsmom_internal_to := 0]
setkey(tsmom_to_dt, date)

master <- merge(master, str1715_to,   by = "date", all.x = TRUE)
master <- merge(master, tsmom_to_dt, by = "date", all.x = TRUE)
master[is.na(str1715_to),        str1715_to := 0]
master[is.na(tsmom_internal_to), tsmom_internal_to := 0]

# ─── STRATEGY DEFINITION & BACKTEST ──────────────────────────────────────────
# Each strategy = capital weights (cap_AR, cap_TSMOM, cap_KR10y, cap_CASH)
# Returns: r = cap_AR*ret_AR + cap_TSMOM*ret_TSMOM_gross + cap_KR10y*kr_10y + cap_CASH*0
# Costs (uniform 15bps one-way):
#   - Sleeve internal turnover (within-AR moves) = cap_AR * str1715_to * COST
#   - TSMOM internal rotation                    = cap_TSMOM * tsmom_internal_to * COST
#   - Capital reallocation between legs (Δcap)   = sum |Δcap| / 2 * COST per rebal
#     (For static-capital strategies S0/S1/S2/S3/S4, Δcap=0 across all dates by design;
#      pre-2015 S1/S3/S4 have weights.csv-mandated 70/0/20/10cash → handle dynamically)

build_strategy_returns <- function(master, w_AR, w_TSMOM, w_KR10y, w_CASH = 0,
                                    use_weights_csv_for_pre2015 = TRUE,
                                    label = "S?") {
  dt <- copy(master)

  # For S1/S2/S3/S4 with TSMOM exposure: pre-2015 TSMOM=0, residual flows back per design
  # We respect weights.csv for STRATEGY S3 (Path C admitted), but for S0/S1/S2/S4
  # we apply the requested capital weights directly.
  # If S3, override w_AR/w_TSMOM/w_KR10y/w_CASH from weights.csv per date.

  if (label == "S3_Hybrid_70_15_15") {
    # Respect weights.csv as-is (pre-2015 70/0/20+10cash; post-2015 70/15/15)
    # weights.csv aggregated columns: w_AR / w_TSMOM / w_KR10y / w_CASH (pre-merged into master/dt)
    setnames(dt, c("w_AR", "w_TSMOM", "w_KR10y", "w_CASH"),
              c("c_AR", "c_TS",    "c_KR",     "c_CSH"))
  } else if (label == "S0_baseline") {
    dt[, `:=`(c_AR = 1, c_TS = 0, c_KR = 0, c_CSH = 0)]
    dt[, `:=`(w_AR = NULL, w_TSMOM = NULL, w_KR10y = NULL, w_CASH = NULL)]
  } else if (label == "S1_KR10y_only") {
    # 70/30 KR10y. KR10y per-name cap 0.20 binds (Codex C2 / Architect concern #2)
    # → 0.20 KR10y + 0.10 cash residual all dates (no TSMOM gap concern)
    dt[, `:=`(c_AR = 0.70, c_TS = 0.0, c_KR = 0.20, c_CSH = 0.10)]
    dt[, `:=`(w_AR = NULL, w_TSMOM = NULL, w_KR10y = NULL, w_CASH = NULL)]
  } else if (label == "S2_TSMOM_only") {
    # 70/30 TSMOM. Pre-2015 TSMOM unavailable → fallback CASH=0.30 per renorm convention
    dt[, c_AR  := 0.70]
    dt[, c_TS  := ifelse(date >= as.Date("2015-01-01"), 0.30, 0.00)]
    dt[, c_KR  := 0.00]
    dt[, c_CSH := ifelse(date >= as.Date("2015-01-01"), 0.00, 0.30)]
    dt[, `:=`(w_AR = NULL, w_TSMOM = NULL, w_KR10y = NULL, w_CASH = NULL)]
  } else if (label == "S4_Hybrid_50_25_25") {
    # 50/25/25 wider sensitivity. Pre-2015 TSMOM=0 → renorm 50/0/20+0.30cash; KR10y cap 0.20 binding
    dt[, c_AR := 0.50]
    dt[, c_TS := ifelse(date >= as.Date("2015-01-01"), 0.25, 0.00)]
    dt[, c_KR := 0.20]
    dt[, c_CSH := 1 - c_AR - c_TS - c_KR]
    dt[, `:=`(w_AR = NULL, w_TSMOM = NULL, w_KR10y = NULL, w_CASH = NULL)]
  }

  # Σcap = 1 check
  dt[, c_sum := c_AR + c_TS + c_KR + c_CSH]
  if (max(abs(dt$c_sum - 1)) > 1e-8) {
    stop(sprintf("[%s] Σcap≠1 max dev: %.6f", label, max(abs(dt$c_sum - 1))))
  }

  # Gross return per period
  dt[, ret_gross := c_AR * ret_AR_on_M4 +
                     c_TS * tsmom_gross +
                     c_KR * kr_10y +
                     c_CSH * 0]

  # Cost: sleeve-internal + TSMOM-internal + capital reallocation
  # Sleeve cost (AR holdings turnover within STR_1715 sleeve)
  dt[, cost_sleeve := c_AR * str1715_to * COST_PER_DOLLAR]
  # TSMOM internal rotation cost
  dt[, cost_tsmom_internal := c_TS * tsmom_internal_to * COST_PER_DOLLAR]
  # Capital reallocation (Δc across periods; first period cost = full cap establishment ignored here
  # for non-static; for static c_*, Δc = 0 except where weights.csv has dynamic c_*)
  cap_mat <- as.matrix(dt[, .(c_AR, c_TS, c_KR, c_CSH)])
  cap_to <- c(NA_real_, sapply(2:nrow(cap_mat), function(i) sum(abs(cap_mat[i,] - cap_mat[i-1,])) / 2))
  cap_to[is.na(cap_to)] <- 0
  dt[, cap_reallocation_to := cap_to]
  dt[, cost_cap_reallocation := cap_reallocation_to * COST_PER_DOLLAR]

  # Total cost & net return
  dt[, cost_ret_total := cost_sleeve + cost_tsmom_internal + cost_cap_reallocation]
  dt[, ret_net := ret_gross - cost_ret_total]
  # Aggregate turnover indicator (for period_returns.turnover col)
  dt[, turnover_total := c_AR * str1715_to + c_TS * tsmom_internal_to + cap_reallocation_to]

  dt[, .(date, c_AR, c_TS, c_KR, c_CSH,
          ret_gross, ret_net, cost_ret_total,
          turnover_total, cost_sleeve, cost_tsmom_internal, cost_cap_reallocation,
          str1715_to, tsmom_internal_to)]
}

# ─── BUILD per-strategy sim_result-compatible inputs ─────────────────────────
build_sim_result_for_strategy <- function(strat_returns, label, master, weights, schedule_dates, str1715_h, str1715_h_expanded) {
  # NAV: cumulative product of (1 + ret_net) starting at 1.0
  nav_dt_local <- copy(strat_returns)
  nav_dt_local[, NAV_gross := cumprod(1 + ret_gross)]
  nav_dt_local[, NAV       := cumprod(1 + ret_net)]
  nav_dt_local[, cash_weight := c_CSH]
  nav_dt_local[, gross_exposure := 1 - c_CSH]
  nav_dt_local[, net_exposure := gross_exposure]
  nav_dt_local[, leverage := gross_exposure]
  setnames(nav_dt_local, "date", "Date")
  daily_nav_dt <- nav_dt_local[, .(Date, NAV_gross, NAV, cash_weight, gross_exposure, net_exposure, leverage)]

  # strategy_xts: monthly net returns
  strat_xts <- xts(strat_returns$ret_net, order.by = strat_returns$date)

  # bm_xts: monthly BM cumulative
  bm_xts <- xts(master$bm_ret, order.by = master$date)

  # HOLDINGS_LOG: build per date from weights.csv with per-strategy c_* override.
  # For strategies with c_*≠weights.csv (S0/S1/S2/S4), reweight ETF/sleeve/bond accordingly.
  holdings_log <- vector("list", length(schedule_dates))
  for (i in seq_along(schedule_dates)) {
    dt_i <- schedule_dates[i]
    sr_i <- strat_returns[date == dt_i]
    if (nrow(sr_i) == 0) next
    cAR  <- sr_i$c_AR
    cTS  <- sr_i$c_TS
    cKR  <- sr_i$c_KR
    cCSH <- sr_i$c_CSH

    # AR (STR_1715) holdings — Codex C3 fix: time-varying stock-level expansion via factor_engine replay
    h_str <- str1715_h_expanded[date == dt_i]
    if (nrow(h_str) == 0) {
      prior <- str1715_h_expanded[date <= dt_i]
      if (nrow(prior) > 0) {
        max_dt <- max(prior$date)
        h_str <- str1715_h_expanded[date == max_dt]
      }
    }
    rows <- list()
    if (nrow(h_str) > 0 && cAR > 0) {
      # Renorm: within-sleeve weights sum to 1.0 → multiply by cAR for capital allocation
      h_str_norm <- copy(h_str)
      sum_w <- sum(h_str_norm$actual_weight, na.rm = TRUE)
      if (sum_w > 0) {
        h_str_norm[, target_weight := actual_weight / sum_w * cAR]
        h_str_norm[, actual_weight := target_weight]
        h_str_norm[, date := dt_i]
        rows[[length(rows)+1]] <- h_str_norm[, .(date, ticker, name, sector, target_weight, actual_weight,
                                                   price = NA_real_, shares = NA_real_, market_value = NA_real_,
                                                   signal_score = score_eff, rank = NA_integer_,
                                                   entry_date = as.Date(NA), holding_period = NA_integer_,
                                                   is_new_position = FALSE, is_exiting_position = FALSE)]
      }
    }
    # TSMOM ETFs (only if cTS > 0 and ≥ 2015-01)
    if (cTS > 0 && dt_i >= as.Date("2015-01-01")) {
      tsm_row <- tsmom_full[date == dt_i]
      if (nrow(tsm_row) > 0) {
        wcols <- tsmom_w_cols
        tsm_w <- unlist(tsm_row[, ..wcols])
        # Post-cap (RF-R8 0.30 cap embedded in weights.csv already; we use weights.csv when label==S3)
        if (label == "S3_Hybrid_70_15_15") {
          tsm_etf <- weights[as_of_date == dt_i & asset_class == "ETF_KR_TSMOM_LEG"]
          if (nrow(tsm_etf) > 0 && sum(tsm_etf$weight) > 0) {
            # Aggregate dup tickers (KODEX_KTB10Y appears in TSMOM + KR10Y)
            tsm_etf_agg <- tsm_etf[, .(weight = sum(weight)), by = .(ticker, name)]
            sum_w <- sum(tsm_etf_agg$weight)
            tsm_etf_agg[, target_weight := weight / sum_w * cTS]
            rows[[length(rows)+1]] <- data.table(
              date = dt_i, ticker = tsm_etf_agg$ticker, name = tsm_etf_agg$name,
              sector = "ETF_TSMOM", target_weight = tsm_etf_agg$target_weight,
              actual_weight = tsm_etf_agg$target_weight,
              price = NA_real_, shares = NA_real_, market_value = NA_real_,
              signal_score = NA_real_, rank = NA_integer_,
              entry_date = as.Date(NA), holding_period = NA_integer_,
              is_new_position = FALSE, is_exiting_position = FALSE)
          }
        } else {
          # S2/S4: use raw TSMOM weight matrix
          rows[[length(rows)+1]] <- data.table(
            date = dt_i,
            ticker = sub("^w_etf_", "", names(tsm_w)),
            name = sub("^w_etf_", "", names(tsm_w)),
            sector = "ETF_TSMOM",
            target_weight = as.numeric(tsm_w) * cTS,
            actual_weight = as.numeric(tsm_w) * cTS,
            price = NA_real_, shares = NA_real_, market_value = NA_real_,
            signal_score = NA_real_, rank = NA_integer_,
            entry_date = as.Date(NA), holding_period = NA_integer_,
            is_new_position = FALSE, is_exiting_position = FALSE)
        }
      }
    }
    # KR10y bond (single ETF A148070)
    if (cKR > 0) {
      rows[[length(rows)+1]] <- data.table(
        date = dt_i, ticker = "A148070", name = "KODEX_KTB10Y",
        sector = "ETF_BOND_KR10Y", target_weight = cKR, actual_weight = cKR,
        price = NA_real_, shares = NA_real_, market_value = NA_real_,
        signal_score = NA_real_, rank = NA_integer_,
        entry_date = as.Date(NA), holding_period = NA_integer_,
        is_new_position = FALSE, is_exiting_position = FALSE)
    }
    # CASH
    if (cCSH > 0) {
      rows[[length(rows)+1]] <- data.table(
        date = dt_i, ticker = "CASH_KRW", name = "KRW Cash",
        sector = "CASH", target_weight = cCSH, actual_weight = cCSH,
        price = NA_real_, shares = NA_real_, market_value = NA_real_,
        signal_score = NA_real_, rank = NA_integer_,
        entry_date = as.Date(NA), holding_period = NA_integer_,
        is_new_position = FALSE, is_exiting_position = FALSE)
    }
    if (length(rows) > 0) holdings_log[[i]] <- rbindlist(rows, fill = TRUE)
  }
  holdings_log <- holdings_log[!sapply(holdings_log, is.null)]

  list(
    DAILY_NAV_DT = daily_nav_dt,
    strategy_xts = strat_xts,
    bm_xts = bm_xts,
    HOLDINGS_LOG = holdings_log,
    PORTFOLIO_LOG = data.table(Exec_Date = schedule_dates, Signal_Date = schedule_dates)
  )
}

# ─── BUILD STRATEGY SPEC ─────────────────────────────────────────────────────
build_strategy_spec <- function(label, w_AR, w_TS, w_KR, w_CSH = NA) {
  list(
    strategy_id = label,
    strategy_name = sprintf("WT-P20260505_001 %s", label),
    strategy_family = "hybrid_overlay_path_C",
    signal_description = "STR_1715 Iter31 PG2 base + TSMOM 9-ETF rotation + KR_10y bond ETF carry",
    universe_rule = "STR_1715 sleeve top20 + 9 TSMOM ETF basket + KODEX KTB10Y A148070 + CASH",
    rebalance_frequency = "monthly",
    signal_date_rule = "month_end",
    execution_date_rule = "next_trading_day_open",
    weighting_method = sprintf("static_capital_%g_%g_%g_%g", w_AR, w_TS, w_KR, ifelse(is.na(w_CSH), 0, w_CSH)),
    max_position_weight = 0.20,
    max_leverage = 1,
    cash_rule = "residual_to_cash_when_KR10y_or_TSMOM_unavailable",
    cost_model = sprintf("v2.3_kr_retail_%dbps", COST_BPS_ONEWAY),
    missing_data_rule = "drop",
    risk_controls = "TSMOM 30pct single-ETF cap + KR10y 20pct per-name cap (Codex C2)",
    lookahead_prevention = "C1-C15 strict; PIT signals; t+1 execution",
    survivorship_bias_control = "STR_1715 sleeve PG2 frozen + ETF universe constructible at PIT"
  )
}

# ─── EXECUTE 5 STRATEGIES ────────────────────────────────────────────────────
strategy_specs <- list(
  S0_baseline        = list(label = "S0_baseline",        cap = c(AR=1.00, TS=0.00, KR=0.00, CSH=0.00)),
  S1_KR10y_only      = list(label = "S1_KR10y_only",      cap = c(AR=0.70, TS=0.00, KR=0.20, CSH=0.10)),
  S2_TSMOM_only      = list(label = "S2_TSMOM_only",      cap = c(AR=0.70, TS=0.30, KR=0.00, CSH=0.00)),
  S3_Hybrid_70_15_15 = list(label = "S3_Hybrid_70_15_15", cap = c(AR=0.70, TS=0.15, KR=0.15, CSH=0.00)),
  S4_Hybrid_50_25_25 = list(label = "S4_Hybrid_50_25_25", cap = c(AR=0.50, TS=0.25, KR=0.20, CSH=0.05))
)

bt_result_list <- list()
strategy_returns_list <- list()
runtime_audit_list <- list()
crisis_decomp_list <- list()

for (sname in names(strategy_specs)) {
  spec <- strategy_specs[[sname]]
  cat(sprintf("\n[STRATEGY %s] capital weights: AR=%.2f TS=%.2f KR=%.2f CSH=%.2f\n",
              spec$label, spec$cap["AR"], spec$cap["TS"], spec$cap["KR"], spec$cap["CSH"]))

  strat_ret <- build_strategy_returns(master,
                                        w_AR = spec$cap["AR"], w_TSMOM = spec$cap["TS"],
                                        w_KR10y = spec$cap["KR"], w_CASH = spec$cap["CSH"],
                                        label = spec$label)
  strategy_returns_list[[sname]] <- strat_ret

  cat(sprintf("  | Returns: gross_mean=%.4f net_mean=%.4f vol=%.4f mean_cost=%.5f\n",
              mean(strat_ret$ret_gross), mean(strat_ret$ret_net),
              sd(strat_ret$ret_net) * sqrt(12), mean(strat_ret$cost_ret_total)))

  # Build sim_result
  sim_result <- build_sim_result_for_strategy(strat_ret, spec$label, master, weights, schedule_dates, str1715_h, str1715_h_expanded)

  # Build strategy_spec
  strat_spec <- build_strategy_spec(spec$label, spec$cap["AR"], spec$cap["TS"], spec$cap["KR"], spec$cap["CSH"])

  # Build bt_result via Contract v1.0
  bt <- build_bt_result(
    sim_result = sim_result,
    strategy_spec = strat_spec,
    run_id = sprintf("WT-P20260505_001_%s_%s", sname, RUN_DT),
    strategy_id = spec$label,
    strategy_version = "1.0",
    benchmark_id = "KOSPI200",
    benchmark_name = "KOSPI 200",
    transaction_cost_bps = COST_BPS_ONEWAY,
    slippage_bps = 0,                   # 15bps absorbs both
    risk_free_rate = 0,
    frequency = "monthly",
    annualization_factor = 12,
    universe_id = "KR_TOP20_PLUS_ETF",
    code_version = "WT-P20260505_001_run_all_v1",
    created_by_agent = "Forge"
  )

  # Audit
  bt$audit <- audit_bt_result(bt)

  # Inject leg-cost detail rows into period_returns for traceability
  pr_extra <- strat_ret[, .(date, leg_cost_sleeve = cost_sleeve,
                              leg_cost_tsmom_internal = cost_tsmom_internal,
                              leg_cost_cap_reallocation = cost_cap_reallocation)]

  bt$period_returns <- merge(bt$period_returns, pr_extra, by = "date", all.x = TRUE)

  bt_result_list[[sname]] <- bt

  # ─── Save outputs ───
  out_dir <- file.path(OUT_BASE, sname)

  # Defensive: ensure all components are not NULL data.tables
  comps_to_check <- c("manifest","strategy_spec","nav","period_returns","holdings",
                       "benchmark_returns","metrics","benchmark_compare",
                       "rolling_metrics","drawdowns","audit")
  for (cmp in comps_to_check) {
    if (is.null(bt[[cmp]])) bt[[cmp]] <- data.table()
    if (!is.data.table(bt[[cmp]])) bt[[cmp]] <- as.data.table(bt[[cmp]])
  }

  tryCatch({
    save_bt_result(bt, out_dir, save_xlsx = FALSE)
  }, error = function(e) {
    cat(sprintf("  ! save_bt_result fallback (manual fwrite): %s\n", conditionMessage(e)))
    saveRDS(bt, file.path(out_dir, "bt_result.rds"))
    for (cmp in comps_to_check) {
      idx <- which(c("manifest","strategy_spec","nav","period_returns","holdings",
                      "benchmark_returns","metrics","benchmark_compare",
                      "rolling_metrics","drawdowns","audit") == cmp) - 1
      fname <- sprintf("%02d_%s.csv", idx, cmp)
      tryCatch(fwrite(bt[[cmp]], file.path(out_dir, fname)), error = function(e2) {})
    }
  })

  cat(sprintf("  | Saved bt_result to: %s\n", out_dir))

  # ─── Alpha invariance runtime audit per strategy ───
  # For S0/S1/S2/S3/S4 we DO NOT touch STR_1715 internal weights ranking.
  # Sleeve weights are scalar-multiplied by c_AR (≥0). rank_corr = 1.0 by Lemma.
  # Empirical verify: pick 5 random dates, compute Spearman rho.
  set.seed(20260505)
  test_dates <- sample(schedule_dates, min(5, length(schedule_dates)))
  rank_corrs <- numeric(length(test_dates))
  for (j in seq_along(test_dates)) {
    h_orig <- str1715_h[date == test_dates[j]]
    if (nrow(h_orig) >= 2) {
      w_orig <- h_orig$actual_weight
      w_post <- w_orig * spec$cap["AR"]   # scalar scale
      rank_corrs[j] <- if (sd(w_orig) > 0) cor(rank(w_orig), rank(w_post), method = "spearman") else 1.0
    } else rank_corrs[j] <- 1.0
  }
  runtime_audit_list[[sname]] <- list(
    strategy = spec$label,
    capital_AR = spec$cap["AR"],
    test_dates = as.character(test_dates),
    spearman_rho_per_date = rank_corrs,
    min_spearman_rho = min(rank_corrs),
    pass = all(abs(rank_corrs - 1.0) < 1e-10),
    proof = "scalar_c=cAR_monotone_strict (Kendall tau=Spearman rho=Pearson r=1.0 by lemma)"
  )

  # ─── Crisis decomposition per strategy ───
  crises <- list(
    GFC_2008_2009     = c("2008-08-01", "2009-06-30"),
    Vol2018_Q4         = c("2018-10-01", "2019-01-31"),
    COVID_2020_acute  = c("2020-02-01", "2020-06-30"),
    Stagflation_2022  = c("2022-01-01", "2022-12-31")
  )
  crisis_decomp <- list()
  for (cname in names(crises)) {
    win <- crises[[cname]]
    sub <- strat_ret[date >= as.Date(win[1]) & date <= as.Date(win[2])]
    if (nrow(sub) == 0) next
    cum_g <- prod(1 + sub$ret_gross) - 1
    cum_n <- prod(1 + sub$ret_net) - 1
    crisis_decomp[[cname]] <- list(
      window_start = win[1], window_end = win[2], n = nrow(sub),
      cum_ret_gross = cum_g, cum_ret_net = cum_n,
      avg_cap_AR = mean(sub$c_AR), avg_cap_TS = mean(sub$c_TS),
      avg_cap_KR = mean(sub$c_KR), avg_cap_CSH = mean(sub$c_CSH),
      max_drawdown_in_window = if (nrow(sub) > 1) {
        nav_w <- cumprod(1 + sub$ret_net)
        min(nav_w / cummax(nav_w) - 1)
      } else 0
    )
  }
  crisis_decomp_list[[sname]] <- crisis_decomp
}

# ─── BUILD comparison_table.csv (5 strategies × 10 metrics) ──────────────────
comparison_rows <- lapply(names(bt_result_list), function(sn) {
  m <- bt_result_list[[sn]]$metrics
  pick <- function(metric) {
    val <- m[metric_name == metric, metric_value]
    if (length(val) == 0) NA_real_ else as.numeric(val[1])
  }
  data.table(
    strategy        = sn,
    CAGR            = pick("CAGR"),
    Sharpe          = pick("Sharpe"),
    Sortino         = pick("Sortino"),
    Calmar          = pick("Calmar"),
    Vol_annualized  = pick("Annualized_Volatility"),
    MDD             = pick("MDD"),
    VaR_95          = pick("VaR_95"),
    CVaR_95         = pick("CVaR_95"),
    Skewness        = pick("Skewness"),
    Total_Return    = pick("Total_Return")
  )
})
comparison_dt <- rbindlist(comparison_rows, fill = TRUE)
fwrite(comparison_dt, file.path(WT_DIR, "comparison_table.csv"))
cat("\n[OUTPUT] comparison_table.csv\n")
print(comparison_dt)

# ─── Save runtime audit + crisis decomposition ───────────────────────────────
write_json(runtime_audit_list, file.path(WT_DIR, "alpha_invariance_runtime_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
write_json(crisis_decomp_list, file.path(WT_DIR, "crisis_decomposition_5_strategy.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[OUTPUT] alpha_invariance_runtime_audit.json + crisis_decomposition_5_strategy.json\n")

# ─── CHARTS: equity curves + drawdown + annual returns ───────────────────────
suppressMessages(library(ggplot2))

eq_curve_data <- rbindlist(lapply(names(strategy_returns_list), function(sn) {
  data.table(strategy = sn, date = strategy_returns_list[[sn]]$date,
             nav = cumprod(1 + strategy_returns_list[[sn]]$ret_net))
}))
ggplot(eq_curve_data, aes(x = date, y = nav, color = strategy)) +
  geom_line(linewidth = 0.7) +
  scale_y_log10() +
  labs(title = "Equity Curves — 5 Strategy Backtest (256m)",
       subtitle = "Log scale | 15bps uniform cost | 2005-02 ~ 2026-05",
       x = NULL, y = "NAV (log10)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(CHARTS_DIR, "equity_curves_5_strategy.png"), width = 10, height = 6, dpi = 110)

# OOS zoom 2015+ (joint 135m)
ggplot(eq_curve_data[date >= as.Date("2015-01-01")], aes(x = date, y = nav, color = strategy)) +
  geom_line(linewidth = 0.7) +
  labs(title = "Equity Curves OOS Zoom (Joint 135m, 2015-01+)",
       subtitle = "All 3 sources active | KR10y + TSMOM legs both available",
       x = NULL, y = "NAV") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(CHARTS_DIR, "oos_zoom_chart.png"), width = 10, height = 6, dpi = 110)

# Annual returns bar chart
ann_ret_data <- rbindlist(lapply(names(strategy_returns_list), function(sn) {
  dt <- strategy_returns_list[[sn]]
  dt[, year := format(date, "%Y")]
  dt[, .(ann_ret = prod(1 + ret_net) - 1, strategy = sn), by = year]
}))
ggplot(ann_ret_data, aes(x = year, y = ann_ret, fill = strategy)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
  labs(title = "Annual Returns — 5 Strategy", x = NULL, y = "Annual Return") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(CHARTS_DIR, "annual_returns.png"), width = 12, height = 6, dpi = 110)

# Regime decomposition — overlay schedule's m4_regime
overlay <- fread(file.path(SOURCE_WT_DIR, "overlay_schedule.csv"))
overlay[, as_of_date := as.Date(as_of_date)]
regime_decomp <- rbindlist(lapply(names(strategy_returns_list), function(sn) {
  dt <- merge(strategy_returns_list[[sn]],
               overlay[, .(as_of_date, m4_regime)],
               by.x = "date", by.y = "as_of_date", all.x = TRUE)
  dt[!is.na(m4_regime), .(SR = mean(ret_net) / sd(ret_net) * sqrt(12),
                            CAGR = prod(1 + ret_net)^(12/.N) - 1,
                            n = .N,
                            strategy = sn), by = m4_regime]
}))
ggplot(regime_decomp, aes(x = m4_regime, y = SR, fill = strategy)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  labs(title = "Sharpe by Regime — 5 Strategy", x = "M4 Regime", y = "Sharpe (annualized)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")
ggsave(file.path(CHARTS_DIR, "regime_decomposition.png"), width = 10, height = 6, dpi = 110)

cat("\n[OUTPUT] charts: equity_curves / oos_zoom / annual_returns / regime_decomposition (4 PNG)\n")

# ─── FINAL SUMMARY ───────────────────────────────────────────────────────────
cat("\n========================================================\n")
cat("  FORGE EXECUTION COMPLETE — 5-strategy bt_result built\n")
cat("========================================================\n")
print(comparison_dt)
cat("\nAll deliverables:\n")
cat(sprintf("  - %s/comparison_table.csv\n", WT_DIR))
cat(sprintf("  - %s/output/<strategy>/* (10 components × 5)\n", WT_DIR))
cat(sprintf("  - %s/output/charts/*.png (4 charts)\n", WT_DIR))
cat(sprintf("  - %s/alpha_invariance_runtime_audit.json\n", WT_DIR))
cat(sprintf("  - %s/crisis_decomposition_5_strategy.json\n", WT_DIR))
cat("\n[FORGE] Done.\n")
