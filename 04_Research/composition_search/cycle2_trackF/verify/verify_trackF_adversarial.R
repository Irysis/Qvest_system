# ============================================================
# Track F ADVERSARIAL VERIFICATION (independent recomputation)
# Verifier: separate agent, Composition Search Cycle 2, 2026-06-12
#
# Independence design:
#  - Recompute O3/INC arms DIRECTLY from the PRODUCTION STORED panel
#    (period_returns_layer5.csv, READ-ONLY) using ONLY the prereg
#    formula text -- does NOT reuse the forge rebuild panel.
#  - Metric formulas replicated from contract source
#    (backtest_result_contract.R lines 378-380, 417-420, 424-427,
#     488-500, 522, 533) + PerformanceAnalytics standard functions.
#  - Then cross-check the saved RDS bt_results + CSV + JSON.
# All file writes confined to 04_Research/.../cycle2_trackF/verify/.
# Production touched read-only (fread). ASCII output only.
# ============================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xts)
  library(PerformanceAnalytics)
  library(jsonlite)
})

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TF   <- file.path(ROOT, "04_Research/composition_search/cycle2_trackF")
PRODCSV <- file.path(ROOT, "05_Production/2.Factor_Model",
  "2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")

CUTOFF <- as.Date("2026-04-30")
fails <- c(); checks <- list()
chk <- function(name, cond, detail = "") {
  status <- if (isTRUE(cond)) "PASS" else "FAIL"
  if (!isTRUE(cond)) fails <<- c(fails, name)
  checks[[length(checks) + 1]] <<- list(name = name, status = status, detail = detail)
  cat(sprintf("[%s] %s %s\n", status, name, detail))
}

# ------------------------------------------------------------
# [V1] Production stored panel (READ-ONLY) vs forge inputs copy
# ------------------------------------------------------------
prod <- fread(PRODCSV)                       # read-only
copyf <- fread(file.path(TF, "inputs/period_returns_layer5_prod_copy.csv"))
prod[, anchor_date := as.Date(anchor_date)]; setorder(prod, anchor_date)
copyf[, anchor_date := as.Date(anchor_date)]; setorder(copyf, anchor_date)
chk("V1a_prod_rows_267", nrow(prod) == 267, sprintf("n=%d", nrow(prod)))
chk("V1b_copy_rows_267", nrow(copyf) == 267, sprintf("n=%d", nrow(copyf)))
common <- intersect(names(prod), names(copyf))
num_cols <- common[sapply(prod[, ..common], is.numeric)]
chr_cols <- setdiff(common, num_cols)
max_num_diff <- max(sapply(num_cols, function(cc) {
  a <- prod[[cc]]; b <- copyf[[cc]]
  m <- max(abs(a - b), na.rm = TRUE); if (!is.finite(m)) 0 else m
}))
chr_eq <- all(sapply(chr_cols, function(cc) identical(as.character(prod[[cc]]),
                                                      as.character(copyf[[cc]]))))
chk("V1c_copy_identical_to_production",
    max_num_diff == 0 && chr_eq,
    sprintf("max_num_diff=%.3e chr_equal=%s ncol_common=%d", max_num_diff, chr_eq, length(common)))
chk("V1d_panel_native_end_le_cutoff",
    max(prod$anchor_date) <= CUTOFF && max(prod$realized_ym) == "2026-04",
    sprintf("max_anchor=%s max_ym=%s", as.character(max(prod$anchor_date)), max(prod$realized_ym)))

# ------------------------------------------------------------
# [V2] Independent arm construction from STORED columns + prereg text
# ------------------------------------------------------------
P <- copy(prod)
P[, g_inc := beta_threshold_lag * m4_weight_lag]
P[, b_inc := g_inc * beta_R05_V2]
deep <- P$b_inc < 0.25
chk("V2a_deep_guard_months_6", sum(deep) == 6, sprintf("n_deep=%d", sum(deep)))

# prereg frozen O3: g = g_inc if g_inc < 0.25 else max(g_inc, 0.5); deep-guard per INV-O1
g_o3 <- ifelse(P$g_inc < 0.25, P$g_inc, pmax(P$g_inc, 0.5))
g_o3[deep] <- P$g_inc[deep]
inv_o1 <- max(abs(g_o3[deep] * P$beta_R05_V2[deep] - P$b_inc[deep]))
chk("V2b_INV_O1_deep_guard_zero", inv_o1 == 0, sprintf("max_abs_beta_diff=%.3e", inv_o1))
lift <- sum(g_o3 > P$g_inc + 1e-12)
chk("V2c_lift_months_33", lift == 33, sprintf("lift=%d", lift))
chk("V2d_no_month_below_incumbent", sum(g_o3 < P$g_inc - 1e-12) == 0,
    sprintf("months_lt_inc=%d", sum(g_o3 < P$g_inc - 1e-12)))

# uniform v2.4-delta cost convention (prereg series_construction)
mk <- function(g) {
  dg   <- abs(diff(c(1, g)))
  cost <- 0.0015 * dg + 0.0015 * P$db_R05_V2
  net  <- P$beta_R05_V2 * g * P$ret_orig - cost
  list(net = net, cost = cost)
}
inc <- mk(P$g_inc); o3 <- mk(g_o3)

# stored-convention incumbent (production cost legs) -- traceability
net_stored <- P$ret_L5_V2

# ------------------------------------------------------------
# [V3] Benchmark monthly (same standard construction, .cache parquet)
# ------------------------------------------------------------
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[Date <= CUTOFF & is.finite(BM_Ret)]
bx <- xts(bm$BM_Ret, order.by = bm$Date)
bm_m <- apply.monthly(bx, Return.cumulative)
bm_dt <- data.table(realized_ym = format(as.Date(index(bm_m)), "%Y-%m"),
                    BM_Ret_m = as.numeric(bm_m))
P <- merge(P, bm_dt, by = "realized_ym", all.x = TRUE)
setorder(P, anchor_date)
chk("V3a_bm_no_NA", !anyNA(P$BM_Ret_m), sprintf("n_NA=%d", sum(is.na(P$BM_Ret_m))))

# ------------------------------------------------------------
# [V4] Metric replication (contract formulas)
# ------------------------------------------------------------
nw_t <- function(x, lag = 3L) {           # replicated from contract .nw_t_mean
  x <- x[!is.na(x)]; n <- length(x)
  if (n < (lag + 2L)) return(NA_real_)
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n; s <- g0
  for (l in 1:lag) {
    w <- 1 - l / (lag + 1)
    g <- sum(e[(l + 1):n] * e[1:(n - l)]) / n
    s <- s + 2 * w * g
  }
  if (s <= 0) return(NA_real_)
  mu / sqrt(s / n)
}
mets <- function(net, dts, bmv, cost) {
  sr_c  <- mean(net) / sd(net) * sqrt(12)                       # contract Sharpe (Rf=0)
  nav   <- cumprod(1 + net)
  cagr_c <- (tail(nav, 1) / head(nav, 1))^(12 / length(nav)) - 1  # contract CAGR
  xx    <- xts(net, order.by = dts)
  mdd   <- as.numeric(maxDrawdown(xx))
  ta    <- table.AnnualizedReturns(xx, scale = 12, Rf = 0)
  act   <- net - bmv
  list(SR_contract = sr_c, CAGR_contract = cagr_c, MDD = -mdd,
       Calmar = cagr_c / mdd,
       SR_ta = as.numeric(ta[3, 1]), CAGR_ta = as.numeric(ta[1, 1]),
       PORT_t = nw_t(act, 3L),
       IR = mean(act) / sd(act) * sqrt(12),
       TE = sd(act) * sqrt(12),
       cost_ann = mean(cost) * 12)
}
wins <- list(FULL_267m   = rep(TRUE, nrow(P)),
             IS_2005_2018  = P$realized_ym >= "2005-01" & P$realized_ym <= "2018-12",
             OOS_2019_2026 = P$realized_ym >= "2019-01",
             SUB2017_2026  = P$realized_ym >= "2017-01")
chk("V4a_window_counts", sum(wins$IS_2005_2018) == 168 && sum(wins$OOS_2019_2026) == 88 &&
      sum(wins$SUB2017_2026) == 112,
    sprintf("IS=%d OOS=%d SUB=%d", sum(wins$IS_2005_2018), sum(wins$OOS_2019_2026), sum(wins$SUB2017_2026)))

rep_csv <- fread(file.path(TF, "trackF_forge_comparison.csv"))
tol4 <- 5.1e-5; tol3 <- 5.1e-4
res_rows <- list()
for (wn in names(wins)) {
  m <- wins[[wn]]
  for (al in c("INC", "O3")) {
    arm <- if (al == "INC") inc else o3
    mm <- mets(arm$net[m], P$anchor_date[m], P$BM_Ret_m[m], arm$cost[m])
    r <- rep_csv[window == wn & arm == al]
    ok <- abs(mm$SR_contract - r$SR) <= tol4 &&
          abs(mm$CAGR_contract - r$CAGR) <= tol4 &&
          abs(mm$MDD - r$MDD) <= tol4 &&
          abs(mm$Calmar - r$Calmar) <= tol4 &&
          abs(mm$PORT_t - r$PORT_t_NW3) <= tol3 &&
          abs(mm$IR - r$IR) <= tol4 &&
          abs(mm$SR_ta - r$SR_ta_likeforlike) <= tol4 &&
          abs(mm$CAGR_ta - r$CAGR_ta_likeforlike) <= tol4 &&
          abs(mm$cost_ann - r$ann_overlay_cost) <= 5.1e-6
    chk(sprintf("V4b_%s_%s_all9_metrics_match", wn, al), ok,
        sprintf("SRc %.4f/%.4f SRta %.4f/%.4f CAGRc %.4f/%.4f MDD %.4f/%.4f Cal %.4f/%.4f PORTt %.3f/%.3f IR %.4f/%.4f cost %.5f/%.5f",
                mm$SR_contract, r$SR, mm$SR_ta, r$SR_ta_likeforlike,
                mm$CAGR_contract, r$CAGR, mm$MDD, r$MDD, mm$Calmar, r$Calmar,
                mm$PORT_t, r$PORT_t_NW3, mm$IR, r$IR, mm$cost_ann, r$ann_overlay_cost))
    res_rows[[paste(wn, al)]] <- data.table(window = wn, arm = al,
      SR_contract = mm$SR_contract, SR_ta = mm$SR_ta, CAGR_contract = mm$CAGR_contract,
      MDD = mm$MDD, Calmar = mm$Calmar, PORT_t = mm$PORT_t, IR = mm$IR, cost_ann = mm$cost_ann)
  }
}
indep <- rbindlist(res_rows)

# headline checks (mission item 4): O3 FULL SR + OOS SR, both conventions
o3_full <- indep[window == "FULL_267m" & arm == "O3"]
o3_oos  <- indep[window == "OOS_2019_2026" & arm == "O3"]
chk("V4c_O3_FULL_SR_repro",
    abs(o3_full$SR_contract - 1.7372) <= tol4 && abs(o3_full$SR_ta - 1.9271) <= tol4,
    sprintf("contract=%.6f (rep 1.7372) ta=%.6f (rep 1.9271)", o3_full$SR_contract, o3_full$SR_ta))
chk("V4d_O3_OOS_SR_repro",
    abs(o3_oos$SR_contract - 1.8626) <= tol4 && abs(o3_oos$SR_ta - 2.0971) <= tol4,
    sprintf("contract=%.6f (rep 1.8626) ta=%.6f (rep 2.0971)", o3_oos$SR_contract, o3_oos$SR_ta))

# stored-convention incumbent traceability vs authoritative 267m 1.8861
x_st <- xts(net_stored, order.by = P$anchor_date)
ta_st <- table.AnnualizedReturns(x_st, scale = 12, Rf = 0)
sr_stored <- as.numeric(ta_st[3, 1])
chk("V4e_incumbent_stored_SR_1.8861", abs(sr_stored - 1.8861) <= tol4,
    sprintf("recomputed=%.6f vs authoritative 1.8861 (v24/judge/governor 267m)", sr_stored))

# ------------------------------------------------------------
# [V5] RDS bt_result inspection (audit + labels + series identity)
# ------------------------------------------------------------
for (al in c("incumbent", "O3")) {
  btr <- readRDS(file.path(TF, sprintf("bt_result_%s_FULL.rds", al)))
  comp_names <- names(btr)
  cat(sprintf("\n[V5] %s components: %s\n", al, paste(comp_names, collapse = ", ")))
  need <- c("manifest", "strategy_spec", "nav", "period_returns", "holdings",
            "benchmark_returns", "metrics", "benchmark_compare", "rolling_metrics",
            "drawdowns", "audit")
  chk(sprintf("V5a_%s_10component_complete", al), all(need %in% comp_names),
      sprintf("missing=%s", paste(setdiff(need, comp_names), collapse = ",")))
  mt_manifest <- btr$manifest$metric_type[1]
  integ <- btr$manifest$integrity_status[1]
  ad <- as.data.table(btr$audit)
  n_crit_fail <- nrow(ad[severity == "critical" & status == "FAIL"])
  n_fail <- nrow(ad[status == "FAIL"])
  warn_names <- ad[status %in% c("WARN", "WARNING"), check_name]
  chk(sprintf("V5b_%s_metric_type_backtested", al), identical(mt_manifest, "backtested"),
      sprintf("manifest$metric_type=%s", mt_manifest))
  chk(sprintf("V5c_%s_no_critical_FAIL", al), n_crit_fail == 0 && n_fail == 0,
      sprintf("critical_FAIL=%d any_FAIL=%d integrity=%s n_checks=%d WARNs=[%s]",
              n_crit_fail, n_fail, integ, nrow(ad), paste(warn_names, collapse = ";")))
  # net series identity vs my independent reconstruction
  mynet <- if (al == "incumbent") inc$net else o3$net
  prn <- as.data.table(btr$period_returns)
  dseries <- max(abs(prn$ret_net - mynet))
  chk(sprintf("V5d_%s_period_returns_match_indep", al), dseries < 1e-12,
      sprintf("max_abs_diff=%.3e n=%d", dseries, nrow(prn)))
  # metrics in RDS vs my replication
  M <- as.data.table(btr$metrics)
  B <- as.data.table(btr$benchmark_compare)
  g1 <- as.numeric(M[metric_name == "Sharpe", metric_value][1])
  g2 <- as.numeric(B[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value][1])
  myrow <- indep[window == "FULL_267m" & arm == (if (al == "incumbent") "INC" else "O3")]
  chk(sprintf("V5e_%s_rds_metrics_match_indep", al),
      abs(g1 - myrow$SR_contract) < 1e-9 && abs(g2 - myrow$PORT_t) < 1e-9,
      sprintf("rds_SR=%.6f my_SR=%.6f rds_PORTt=%.4f my_PORTt=%.4f", g1, myrow$SR_contract, g2, myrow$PORT_t))
  mt_metrics_all <- unique(M$metric_type)
  cat(sprintf("    metrics metric_type values: %s | audit statuses: %s\n",
              paste(mt_metrics_all, collapse = ","), paste(unique(ad$status), collapse = ",")))
}

# ------------------------------------------------------------
# [V6] estimated (cycle1) vs backtested like-for-like discrepancy
# ------------------------------------------------------------
c1 <- fromJSON(file.path(ROOT, "04_Research/composition_search/cycle1_trackO/combine_ab_results.json"))
c1t <- as.data.table(c1$table)
pairs <- list(c("O3_MIDBAND_FLOOR", "O3"), c("INCUMBENT_REPRICED", "INC"))
max_disc <- 0
for (pp in pairs) {
  for (wn in names(wins)) {
    est <- c1t[arm == pp[1] & window == wn]
    my  <- indep[window == wn & arm == pp[2]]
    d_sr <- abs(my$SR_ta - est$SR); d_mdd <- abs(my$MDD - est$MDD)
    max_disc <- max(max_disc, d_sr, d_mdd)
  }
}
chk("V6a_est_vs_bt_likeforlike_zero", max_disc <= tol4,
    sprintf("max |SR_ta/MDD discrepancy| vs cycle1 = %.2e (threshold 0.05 -- far below)", max_disc))

# JSON cross-doc: comparison json vs csv
tj <- fromJSON(file.path(TF, "trackF_comparison.json"))
tjt <- as.data.table(tj$forge_table)
mism <- merge(tjt[, .(window, arm, SR_j = SR, PORT_j = PORT_t_NW3)],
              rep_csv[, .(window, arm, SR_c = SR, PORT_c = PORT_t_NW3)],
              by = c("window", "arm"))
chk("V6b_json_csv_consistent",
    all(abs(mism$SR_j - mism$SR_c) < 1e-12) && all(abs(mism$PORT_j - mism$PORT_c) < 1e-12),
    sprintf("rows=%d", nrow(mism)))
chk("V6c_book_state_flag_false", identical(tj$book_state_written, FALSE),
    sprintf("book_state_written=%s", tj$book_state_written))

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
cat(sprintf("\n==== VERIFICATION SUMMARY: %d checks, %d FAIL ====\n",
            length(checks), length(fails)))
if (length(fails)) cat("FAILED:", paste(fails, collapse = ", "), "\n")
fwrite(indep, file.path(TF, "verify/indep_recompute_metrics.csv"))
write_json(list(checks = checks, n_fail = length(fails),
                indep_metrics = indep,
                incumbent_stored_sr_ta = sr_stored,
                note = "independent recomputation from production stored panel + prereg frozen formula; production read-only"),
           file.path(TF, "verify/verify_results.json"), pretty = TRUE, auto_unbox = TRUE, digits = 10)
cat("[done] verify outputs written to cycle2_trackF/verify/\n")
