# ============================================================
# v24_book_remeasure — B0 disposition 4-2 obligation
# Book (STR_1715_AR_on_M4_R05_overlay_PG2) core metrics under
# cost model v2.3 (flat per-rebalance 15bps buy leg) vs
# v2.4 (delta-based: 15bps per leg on |delta holdings notional|)
#
# Method: NOT a production re-run. Uses realized artifacts:
#  - base PR (ret_gross + realized monthly one-way turnover + cost_ret)
#  - layer5 panel (realized beta paths + delta-beta legs)
# Recompose net series under each cost basis, then
# PerformanceAnalytics standard functions only.
# metric_type = estimated (forge-authoritative remeasure is the
# forge stage of WT-D20260611_001, not this script).
# ============================================================
suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(PerformanceAnalytics)
  library(jsonlite)
})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PROD <- file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
BASE_STR <- file.path(ROOT, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd")
OUT <- file.path(ROOT, "04_Research/pg2_forensics/v24_book_remeasure")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------
# [0] Copy source artifacts (production = READ-ONLY source)
# ------------------------------------------------------------
src_files <- c(
  file.path(PROD, "04_backtest_results/period_returns_layer5.csv"),
  file.path(PROD, "04_backtest_results/incremental_turnover.csv"),
  file.path(PROD, "02_holdings_universe/weights_267m_timeseries.csv"),
  file.path(BASE_STR, "output/03_period_returns.csv")
)
for (f in src_files) {
  stopifnot(file.exists(f))
  invisible(file.copy(f, file.path(OUT, basename(f)), overwrite = TRUE))
}
# rename base PR copy to avoid ambiguity
invisible(file.rename(file.path(OUT, "03_period_returns.csv"),
                      file.path(OUT, "base_str1715_03_period_returns.csv")))
cat("[0] source artifacts copied to", OUT, "\n")

# ------------------------------------------------------------
# [1] Load + integrity checks
# ------------------------------------------------------------
pr  <- fread(file.path(OUT, "base_str1715_03_period_returns.csv"))
l5  <- fread(file.path(OUT, "period_returns_layer5.csv"))
pr[, date := as.Date(date)]
pr[, ym := format(date, "%Y-%m")]
setorder(pr, date)
l5[, anchor_date := as.Date(anchor_date)]
setorder(l5, anchor_date)

stopifnot(nrow(pr) == 267, nrow(l5) == 267)

# (1a) verify base cost identity: ret_net = ret_gross - 0.003 * turnover
id_resid <- pr$ret_gross - pr$ret_net - 0.003 * pr$turnover
cat(sprintf("[1a] base cost identity max|resid| = %.3e (n=%d)\n",
            max(abs(id_resid)), length(id_resid)))
cost_identity_holds <- max(abs(id_resid)) < 1e-12

# (1b) verify layer5 ret_orig == base ret_net (merge on realized ym)
mg <- merge(l5[, .(realized_ym, ret_orig)], pr[, .(realized_ym = ym, ret_net)],
            by = "realized_ym")
stopifnot(nrow(mg) == 267)
cat(sprintf("[1b] layer5 ret_orig vs base ret_net max|diff| = %.3e\n",
            max(abs(mg$ret_orig - mg$ret_net))))

# (1c) closure: recompose stored ret_L5_V2 from realized beta columns
l5[, ret_L5_V2_recomp := beta_R05_V2 * beta_threshold_lag * m4_weight_lag * ret_orig -
       db_thr * 0.0015 - db_R05_V2 * 0.0015]
cat(sprintf("[1c] L5_V2 recomposition max|diff| = %.3e\n",
            max(abs(l5$ret_L5_V2_recomp - l5$ret_L5_V2))))

# (1d) realized turnover anchors
to_ann_incl   <- mean(pr$turnover) * 12
to_ann_ex_m1  <- mean(pr$turnover[-1]) * 12
cat(sprintf("[1d] realized one-way TO ann: incl m1 = %.4f | excl m1 = %.4f | governor book_state = 5.5725\n",
            to_ann_incl, to_ann_ex_m1))

# ------------------------------------------------------------
# [2] Cost scenarios on the base (vanilla) layer
#   v2.3 flat  : 15bps per rebalance on full notional (buy leg), every month
#   v2.4 delta : 2 x 15bps x one-way turnover (recorded basis; month1 = 30bps x TO)
#   v2.4 strict: same but month1 buy leg only (engine spec: initial entry single leg)
# ------------------------------------------------------------
pr[, cost_v23_flat  := 0.0015]
pr[, cost_v24_delta := 0.003 * turnover]            # == recorded cost_ret
pr[, cost_v24_strict := cost_v24_delta]
pr[1, cost_v24_strict := 0.0015 * turnover]          # initial entry: buy leg only

pr[, base_v23  := ret_gross - cost_v23_flat]
pr[, base_v24  := ret_gross - cost_v24_delta]        # == recorded ret_net == ret_orig
pr[, base_v24s := ret_gross - cost_v24_strict]

# attach to layer5 panel by realized_ym
l5 <- merge(l5,
            pr[, .(realized_ym = ym, ret_gross, turnover,
                   base_v23, base_v24, base_v24s)],
            by = "realized_ym", all.x = TRUE, sort = FALSE)
setorder(l5, anchor_date)
stopifnot(!anyNA(l5$base_v23))

# overlaid (book variant V2) under each base-cost scenario;
# overlay delta-beta legs identical in both (hand-applied delta-based in production)
l5[, bprod := beta_R05_V2 * beta_threshold_lag * m4_weight_lag]
l5[, ov_legs := db_thr * 0.0015 + db_R05_V2 * 0.0015]
l5[, L5V2_v23  := bprod * base_v23  - ov_legs]
l5[, L5V2_v24  := bprod * base_v24  - ov_legs]       # == stored ret_L5_V2
l5[, L5V2_v24s := bprod * base_v24s - ov_legs]

cat(sprintf("[2] L5V2_v24 vs stored ret_L5_V2 max|diff| = %.3e\n",
            max(abs(l5$L5V2_v24 - l5$ret_L5_V2))))

# embedded annualized cost per scenario (diagnostic, analytic expectation)
ann_cost <- function(x) mean(x) * 12
cost_tab <- data.table(
  series = c("vanilla_v23_flat", "vanilla_v24_delta", "vanilla_v24_strict",
             "L5V2_v23_flat", "L5V2_v24_delta", "L5V2_v24_strict"),
  ann_cost = c(ann_cost(pr$cost_v23_flat),
               ann_cost(pr$cost_v24_delta),
               ann_cost(pr$cost_v24_strict),
               ann_cost(l5$bprod * pr$cost_v23_flat[match(l5$realized_ym, pr$ym)] + l5$ov_legs),
               ann_cost(l5$bprod * pr$cost_v24_delta[match(l5$realized_ym, pr$ym)] + l5$ov_legs),
               ann_cost(l5$bprod * pr$cost_v24_strict[match(l5$realized_ym, pr$ym)] + l5$ov_legs))
)

# ------------------------------------------------------------
# [3] Metrics — PerformanceAnalytics standard functions only
# ------------------------------------------------------------
metr <- function(r, dts) {
  x <- xts(r, order.by = dts)
  ta <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  list(CAGR = as.numeric(ta[1, 1]),
       Vol  = as.numeric(ta[2, 1]),
       SR   = as.numeric(ta[3, 1]),
       MDD  = -abs(as.numeric(maxDrawdown(x))))
}

panels <- list(
  full_267m  = l5,
  admit_255m = l5[realized_ym >= "2005-02"]
)
series_def <- c(vanilla_v23_flat = "base_v23",
                vanilla_v24_delta = "base_v24",
                vanilla_v24_strict = "base_v24s",
                L5V2_v23_flat = "L5V2_v23",
                L5V2_v24_delta = "L5V2_v24",
                L5V2_v24_strict = "L5V2_v24s")

rows <- list()
for (pn in names(panels)) {
  dpan <- panels[[pn]]
  for (sn in names(series_def)) {
    m <- metr(dpan[[series_def[[sn]]]], dpan$anchor_date)
    rows[[length(rows) + 1]] <- data.table(
      panel = pn, series = sn, n_months = nrow(dpan),
      SR = round(m$SR, 4), CAGR = round(m$CAGR, 4),
      Vol = round(m$Vol, 4), MDD = round(m$MDD, 4))
  }
}
res <- rbindlist(rows)
res <- merge(res, cost_tab, by = "series", sort = FALSE)
res[, ann_cost := round(ann_cost, 5)]
setcolorder(res, c("panel", "series", "n_months", "SR", "CAGR", "Vol", "MDD", "ann_cost"))
setorder(res, panel, series)

cat("\n[3] comparison table (metric_type=estimated)\n")
print(res)

fwrite(res, file.path(OUT, "v24_book_remeasure_table.csv"))

out_json <- list(
  task = "v2.4 cost-model book remeasure (B0 disposition 4-2)",
  date = "2026-06-11",
  metric_type = "estimated",
  note_authority = "forge-authoritative remeasure belongs to WT-D20260611_001 forge stage; this is realized-artifact recomposition",
  data_basis = list(
    base_pr = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv (realized ret_gross + one-way turnover + cost_ret, 267m)",
    layer5  = "05_Production/.../04_backtest_results/period_returns_layer5.csv (realized beta paths + delta-beta legs)",
    holdings_stock_level = "NOT retained in production artifacts (bt_result holdings=NULL; base 04_holdings.csv sleeve-level only); realized monthly one-way turnover series used instead (it is the recorded aggregate of |delta weight|)"
  ),
  integrity = list(
    base_cost_identity_max_resid = max(abs(id_resid)),
    cost_identity_holds = cost_identity_holds,
    retorig_eq_retnet_max_diff = max(abs(mg$ret_orig - mg$ret_net)),
    L5V2_recomposition_max_diff = max(abs(l5$ret_L5_V2_recomp - l5$ret_L5_V2)),
    L5V2_v24_eq_stored_max_diff = max(abs(l5$L5V2_v24 - l5$ret_L5_V2))
  ),
  realized_turnover = list(
    one_way_ann_incl_m1 = to_ann_incl,
    one_way_ann_excl_m1 = to_ann_ex_m1,
    governor_book_state_value = 5.5725
  ),
  anchors_b0 = list(flat_annual_cost = 0.018, delta_annual_cost_at_TO_5p57 = 0.0167),
  table = res
)
write_json(out_json, file.path(OUT, "v24_book_remeasure_results.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 10)
cat("\n[done] outputs:", file.path(OUT, "v24_book_remeasure_table.csv"), "\n")
