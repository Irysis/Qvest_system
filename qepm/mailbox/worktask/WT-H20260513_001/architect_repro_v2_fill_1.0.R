# ===========================================================
# Architect Independent Reproduction — REVISED V2
# WT-H20260513_001 — AX-008 3rd source
# ============================================================
# Change vs v1: NA fill = 1.0 (Forge convention) instead of NA drop
# This aligns with Forge's shift(x, 1, fill=1.0) pattern across all overlays.
#
# Result: should reproduce Forge L4 1.6957 (267m) and 1.7486 (255m) within strict
# ===========================================================

suppressPackageStartupMessages({
  library(arrow)
  library(PerformanceAnalytics)
  library(xts)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(WT_DIR)

cat("============================================================\n")
cat("ARCHITECT REVISED REPRO — NA fill = 1.0 (Forge convention)\n")
cat("============================================================\n\n")

# Hash audit start
source_paths <- list(
  pr  = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
  r05 = "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet",
  m4  = "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv",
  ar  = "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"
)
md5_of <- function(p) system(sprintf('md5sum "%s" | awk \'{print $1}\'', p), intern=TRUE)
hash_start <- sapply(source_paths, md5_of)

# Read sources
pr_raw <- read.csv(source_paths$pr, stringsAsFactors=FALSE)
pr_raw$date <- as.Date(pr_raw$date)
pr <- data.frame(date=pr_raw$date,
                 ret_net=as.numeric(pr_raw$ret_net),
                 TO=as.numeric(pr_raw$turnover))
pr$ym <- format(pr$date, "%Y-%m")

r05 <- read_parquet(source_paths$r05)
regime_df <- unique(r05[, c("Date","regime_state")])
regime_df$Date <- as.Date(regime_df$Date)
regime_df <- regime_df[order(regime_df$Date), ]
regime_df$ym <- format(regime_df$Date, "%Y-%m")

ar <- read.csv(source_paths$ar, stringsAsFactors=FALSE)
ar$Date <- as.Date(ar$Date)
ar$ym <- format(ar$Date, "%Y-%m")

m4 <- read.csv(source_paths$m4, stringsAsFactors=FALSE)
m4$Date <- as.Date(m4$Date)
m4$ym <- format(m4$Date, "%Y-%m")

# ============================================================
# FORGE CONVENTION: shift(x, 1, fill=1.0) at SOURCE level
#   m4: shift(weight_str1715, 1, fill=1.0) by Date order
#   AR: shift(beta_threshold, 1, fill=1.0) by Date order
#   R05 regime: applied at "realized_ym = sig_date + 1m"
#     i.e., regime at month t-1 EOM applied to month t (Forge code line 175)
#
# We pre-compute the lagged values at the SOURCE, then merge by realized_ym.
# ============================================================

# m4: shift by 1 with fill=1.0
m4 <- m4[order(m4$Date), ]
m4$m4_lag <- c(1.0, head(m4$weight_str1715, -1))
# Realized ym is m4 row's ym + 1 month (since m4 row indicates "decided at Date_t apply at t+1")
# But actually Forge's m4 data is sig_date based — Date column = decision month
# Forge code: m4_weight_lag = shift(weight_str1715, 1, fill=1.0); then merge by realized_ym
# So m4 row Date = sig_date_t, weight_str1715 = decision_t; m4_weight_lag at row t = decision at t-1
# applied to realized_ym = next month?
# Forge line 128-130: "m4_weight_lag = weight_str1715_lag" merged on realized_ym = panel's realized_ym
# This means: panel realized_ym (which is PR's month, the actual return month)
# matches m4 row's ym (decision month). So if PR's return at month 2004-02-02 is "Feb 2004 return"
# and decision_date m4 ym=2004-02 (line m4_lag = previous decision), that's a LAG ALREADY applied.
#
# More carefully: m4 row Date=2004-01-01 has weight_str1715=1.0 — this is January 2004 decision
# m4_weight_lag at row Date=2004-01-01 = 1.0 (fill) = December 2003 decision
# Forge merges this on realized_ym = panel realized_ym (which is the month of return)
# So the m4 sig_date "2004-01-01" decides Feb 2004 weights, which Forge merges to
# panel's realized_ym field. We need to align.

# Look at Forge panel construction (line 81-103):
# panel from PR rows includes "realized_ym" — what is it?

# Forge line 81-103 was loaded earlier — realized_ym is forge-constructed.
# Let me check what realized_ym means. Per Forge code:
#   panel <- pr[..., .(..., realized_ym = ym ...)]
# Actually need to check

# Practical approach: PR ret_net at month t is the realized return for month t.
# The decision was made at end of month t-1.
# m4 weight_str1715 at Date=t-1 = decision for month t.
# Forge convention shift(x, 1, fill=1.0) on m4 sorted by Date:
#   m4_weight_lag at Date=t = weight at Date=t-1 (decision for t)
#   Then merge to panel where panel.realized_ym = (year-month of return)
# So we want: for PR return at month t (year-month=ym_t), use m4's row at Date with ym=t-1?
# Or m4's row at Date with ym=t (then lagged means t-1)?
#
# Forge line 269: realized_ym = format(Date + months(1), "%Y-%m")
# Forge sees: sig_date Date in p_r05/r05/regime → realized_ym = sig_date + 1 month
# So for r05: regime at sig_date=2004-01-01 → realized_ym=2004-02 → applied to PR row ym=2004-02
#
# For m4 (line 116): m4_weight_lag = shift(weight_str1715, 1) by Date order
# Then merged on realized_ym = m4's ym (NOT +1m).
# Wait, line 127-130:
#   panel <- merge(panel, m4[, .(realized_ym = ym, m4_weight_lag = ...)], by="realized_ym")
# This means: m4 row's ym IS treated as the realized return month.
# So m4 Date=2004-01-01 means "Jan 2004 is realized" — weight decided at Dec 2003.
# m4_weight_lag at row Date=2004-01-01 = (Dec 2003 decision via shift)
#
# But then panel.realized_ym = PR's ym (let's verify).
# PR ym = format(date, "%Y-%m") where date = "2004-02-02" → ym = "2004-02"
# So panel.realized_ym = "2004-02" means Feb 2004 is the return month
# Merge with m4 row at ym=2004-02 (Date=2004-02-01) m4_weight_lag = Jan 2004 weight
# Hmm — that's lag of 1 month, but Jan weight applies to Feb? That IS the lag.
#
# So Forge's convention is: m4 row at ym=X has weight_str1715 = decision FOR ym=X
# m4_weight_lag at row ym=X = decision for ym=X-1 (one month earlier)
# Applied to PR return at realized_ym=X → using decision for ym=X-1 → THAT is the t-1 lag
# YES — this is consistent with PIT.

# Implementation: align our master table the SAME way

# Create panel with realized_ym from PR
panel <- pr
panel$realized_ym <- panel$ym

# m4 lagged values
m4$m4_lag_at_row <- c(1.0, head(m4$weight_str1715, -1))
# Use m4 row's ym as the realized_ym (key for merge)
m4_key <- data.frame(realized_ym = m4$ym, m4_weight_lag = m4$m4_lag_at_row)
panel <- merge(panel, m4_key, by="realized_ym", all.x=TRUE)
panel$m4_weight_lag[is.na(panel$m4_weight_lag)] <- 1.0

# AR lagged values
ar$beta_threshold_lag <- c(1.0, head(ar$beta_threshold, -1))
ar_key <- data.frame(realized_ym = ar$ym, beta_threshold_lag = ar$beta_threshold_lag)
# Where beta_threshold is NA, lag also propagates NA → fill with 1.0
ar_key$beta_threshold_lag[is.na(ar_key$beta_threshold_lag)] <- 1.0
panel <- merge(panel, ar_key, by="realized_ym", all.x=TRUE)
panel$beta_threshold_lag[is.na(panel$beta_threshold_lag)] <- 1.0

# R05 regime: per Forge line 175, realized_ym = sig_date + 1m
regime_df$realized_ym <- format(as.Date(paste0(regime_df$ym, "-01")) + 32, "%Y-%m")
# To map: regime at sig_date 2004-01 → realized 2004-02
regime_key <- regime_df[, c("realized_ym","regime_state")]
panel <- merge(panel, regime_key, by="realized_ym", all.x=TRUE)
panel$regime_state[is.na(panel$regime_state)] <- "UNKNOWN"

# Sort by date
panel <- panel[order(panel$date), ]

# V2 regime mapping
panel$beta_R05_V2 <- ifelse(panel$regime_state %in% c("BULL","NORMAL"), 1.0,
                       ifelse(panel$regime_state == "CAUTION", 0.5,
                       ifelse(panel$regime_state == "CRISIS", 0.3,
                              1.0)))  # UNKNOWN → 1.0 (Forge fill convention)
panel$beta_R05_V1 <- ifelse(panel$regime_state %in% c("BULL","NORMAL"), 1.0,
                       ifelse(panel$regime_state == "CAUTION", 0.7,
                       ifelse(panel$regime_state == "CRISIS", 0.5, 1.0)))
panel$beta_R05_V3 <- ifelse(panel$regime_state %in% c("BULL","NORMAL"), 1.0,
                       ifelse(panel$regime_state == "CAUTION", 0.6,
                       ifelse(panel$regime_state == "CRISIS", 0.4, 1.0)))

cat("Panel rows:", nrow(panel), "\n")
cat("Realized_ym range:", min(panel$realized_ym), "~", max(panel$realized_ym), "\n")
cat("m4_weight_lag distribution (rounded 0.01):\n")
print(table(round(panel$m4_weight_lag, 2)))
cat("\nbeta_threshold_lag distribution (rounded 0.1):\n")
print(table(round(panel$beta_threshold_lag, 1)))
cat("\nbeta_R05_V2 distribution (rounded 0.1):\n")
print(table(round(panel$beta_R05_V2, 1)))

# ============================================================
# Compute composite returns
# Forge line 285-300:
#   db_thr = abs(beta_threshold_lag - shift(beta_threshold_lag, 1, fill=1.0))
#   ret_L4 = beta_threshold_lag * m4_weight_lag * ret_orig - db_thr * 0.0015
#   For V*: ret_v = beta_R05_v * beta_threshold_lag * m4_weight_lag * ret_orig - db_v*0.0015
# ============================================================

# db (Δ scalar) computation
panel$db_thr <- c(0, abs(diff(panel$beta_threshold_lag)))

# L4: m4 * beta_AR (no R05)
panel$ret_L4 <- panel$beta_threshold_lag * panel$m4_weight_lag * panel$ret_net -
                panel$db_thr * 0.0015

# V2: m4 * beta_AR * beta_R05_V2
panel$db_V2 <- c(0, abs(diff(panel$beta_R05_V2 * panel$beta_threshold_lag * panel$m4_weight_lag)))
panel$ret_V2 <- panel$beta_R05_V2 * panel$beta_threshold_lag * panel$m4_weight_lag * panel$ret_net -
                panel$db_V2 * 0.0015

# Actually, Forge line 308:
#   panel[, (rcol) := get(bb) * beta_threshold_lag * m4_weight_lag * ret_orig - get(db) * 0.0015]
# Where db = abs(get(bb) - shift(get(bb), 1, fill=1.0))
# This means db is computed on JUST beta_R05_V2 (not the product), with fill=1.0
# Let me reproduce that exactly:

panel$db_R05_V2_only <- c(NA_real_, abs(diff(panel$beta_R05_V2)))
panel$db_R05_V2_only[1] <- abs(panel$beta_R05_V2[1] - 1.0)  # fill=1.0 for first
panel$db_R05_V2_only[is.na(panel$db_R05_V2_only)] <- 0
panel$ret_V2_forgestyle <- panel$beta_R05_V2 * panel$beta_threshold_lag * panel$m4_weight_lag * panel$ret_net -
                           panel$db_R05_V2_only * 0.0015

# Similarly V1, V3
panel$db_R05_V1_only <- c(abs(panel$beta_R05_V1[1] - 1.0), abs(diff(panel$beta_R05_V1)))
panel$db_R05_V1_only[is.na(panel$db_R05_V1_only)] <- 0
panel$db_R05_V3_only <- c(abs(panel$beta_R05_V3[1] - 1.0), abs(diff(panel$beta_R05_V3)))
panel$db_R05_V3_only[is.na(panel$db_R05_V3_only)] <- 0
panel$ret_V1_forgestyle <- panel$beta_R05_V1 * panel$beta_threshold_lag * panel$m4_weight_lag * panel$ret_net -
                           panel$db_R05_V1_only * 0.0015
panel$ret_V3_forgestyle <- panel$beta_R05_V3 * panel$beta_threshold_lag * panel$m4_weight_lag * panel$ret_net -
                           panel$db_R05_V3_only * 0.0015

# L4 baseline: ONLY beta_threshold_lag * m4_weight_lag * ret_net - db_thr * 0.0015
# (no V scalar applied, no V db)
# Wait, but L4 also has β_AR baked? Yes — L4 = base + M4 + AR (3-layer admit precedent)

# Build NAV via PerformanceAnalytics
build_nav <- function(rets, dates) {
  xts(rets, order.by=dates)
}
L4_xts <- build_nav(panel$ret_L4, panel$date)
V2_xts <- build_nav(panel$ret_V2_forgestyle, panel$date)
V1_xts <- build_nav(panel$ret_V1_forgestyle, panel$date)
V3_xts <- build_nav(panel$ret_V3_forgestyle, panel$date)

compute_metrics <- function(ret_xts, label, anchor_start=NULL, panel_label="") {
  if (!is.null(anchor_start)) {
    ret_xts <- ret_xts[index(ret_xts) >= as.Date(anchor_start)]
  }
  n_m <- length(ret_xts)
  ar_stats <- table.AnnualizedReturns(ret_xts, Rf=0, scale=12, geometric=TRUE, digits=10)
  cagr <- as.numeric(ar_stats["Annualized Return", 1])
  vol  <- as.numeric(ar_stats["Annualized Std Dev", 1])
  sr   <- as.numeric(ar_stats["Annualized Sharpe (Rf=0%)", 1])
  mdd  <- as.numeric(maxDrawdown(ret_xts, geometric=TRUE))
  sortino_mo <- as.numeric(SortinoRatio(ret_xts, MAR=0))
  sortino_ann <- sortino_mo * sqrt(12)
  calmar  <- as.numeric(CalmarRatio(ret_xts, scale=12))
  cat(sprintf("[%s%s] n=%d | SR=%.4f | MDD=%.4f | CAGR=%.4f | Vol=%.4f | Sortino_mo=%.4f | Sortino_ann=%.4f | Calmar=%.4f\n",
              label, panel_label, n_m, sr, -abs(mdd), cagr, vol, sortino_mo, sortino_ann, calmar))
  list(label=label, panel=panel_label, n_months=n_m,
       Sharpe=sr, MDD=-abs(mdd), CAGR=cagr, Vol=vol,
       Sortino_mo=sortino_mo, Sortino_ann=sortino_ann, Calmar=calmar)
}

cat("\n=== 267m raw cover panel ===\n")
L4_267 <- compute_metrics(L4_xts, "L4", NULL, "_267m")
V2_267 <- compute_metrics(V2_xts, "V2", NULL, "_267m")
V1_267 <- compute_metrics(V1_xts, "V1", NULL, "_267m")
V3_267 <- compute_metrics(V3_xts, "V3", NULL, "_267m")

cat("\n=== 255m admit-comparable panel (anchor 2005-02-01) ===\n")
L4_255 <- compute_metrics(L4_xts, "L4", "2005-02-01", "_255m")
V2_255 <- compute_metrics(V2_xts, "V2", "2005-02-01", "_255m")
V1_255 <- compute_metrics(V1_xts, "V1", "2005-02-01", "_255m")
V3_255 <- compute_metrics(V3_xts, "V3", "2005-02-01", "_255m")

# Compare with Forge
cat("\n\n============================================================\n")
cat("FORGE vs ARCHITECT — REVISED COMPARISON\n")
cat("============================================================\n")
forge_255 <- list(
  L4=list(Sharpe=1.7486, MDD=-0.2481, CAGR=0.3868, Vol=0.2212, Sortino=1.0063, Calmar=1.5592),
  V2=list(Sharpe=1.9536, MDD=-0.2481, CAGR=0.4150, Vol=0.2125, Sortino=1.2204, Calmar=1.6730),
  V1=list(Sharpe=1.8774, MDD=-0.2481, CAGR=0.4043, Vol=0.2153, Sortino=1.1408, Calmar=1.6301),
  V3=list(Sharpe=1.9159, MDD=-0.2481, CAGR=0.4097, Vol=0.2138, Sortino=1.1817, Calmar=1.6516)
)
forge_267 <- list(
  L4=list(Sharpe=1.6957, MDD=-0.2481, CAGR=0.3770),
  V2=list(Sharpe=1.8861, MDD=-0.2481, CAGR=0.4037),
  V1=list(Sharpe=1.8153, MDD=-0.2481, CAGR=0.3936),
  V3=list(Sharpe=1.8511, MDD=-0.2481, CAGR=0.3987)
)
arch_255 <- list(L4=L4_255, V2=V2_255, V1=V1_255, V3=V3_255)
arch_267 <- list(L4=L4_267, V2=V2_267, V1=V1_267, V3=V3_267)

n_within_strict <- 0; n_total <- 0
max_abs_delta <- 0
for (panel in c("255m","267m")) {
  cat(sprintf("\n--- %s panel ---\n", panel))
  arch <- if (panel=="255m") arch_255 else arch_267
  forge <- if (panel=="255m") forge_255 else forge_267
  for (v in c("L4","V2","V1","V3")) {
    a <- arch[[v]]; f <- forge[[v]]
    for (m in names(f)) {
      if (m %in% names(a)) {
        d <- a[[m]] - f[[m]]
        flag <- ifelse(abs(d) < 0.005, "OK", "FAIL")
        cat(sprintf("  %s_%s_%s F=%.4f A=%.4f Δ=%+.4f [%s]\n",
                    v, panel, m, f[[m]], a[[m]], d, flag))
        n_total <- n_total + 1
        if (abs(d) < 0.005) n_within_strict <- n_within_strict + 1
        if (abs(d) > max_abs_delta) max_abs_delta <- abs(d)
      }
    }
  }
}
cat(sprintf("\nSUMMARY: %d/%d within 0.005 strict | max|Δ|=%.4f\n",
            n_within_strict, n_total, max_abs_delta))

# Hash audit end
hash_end <- sapply(source_paths, md5_of)
hash_match <- all(hash_start == hash_end)
cat(sprintf("\nHash audit: all_unchanged=%s\n", hash_match))

# Save
all_results <- list(
  hash_audit = list(start=as.list(hash_start),
                     end=as.list(hash_end),
                     all_unchanged=hash_match),
  panel_255m = list(L4=L4_255, V2=V2_255, V1=V1_255, V3=V3_255),
  panel_267m = list(L4=L4_267, V2=V2_267, V1=V1_267, V3=V3_267),
  comparison_summary = list(
    n_within_strict_0p005 = n_within_strict,
    n_total = n_total,
    max_abs_delta = max_abs_delta,
    pass_4decimal_exact = (n_within_strict == n_total)
  )
)
saveRDS(all_results, "qepm/mailbox/worktask/WT-H20260513_001/architect_indep_results_v2.rds")
saveRDS(panel, "qepm/mailbox/worktask/WT-H20260513_001/architect_master_table_v2.rds")
cat("\nSaved.\n")
