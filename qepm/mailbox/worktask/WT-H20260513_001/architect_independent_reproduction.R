# ===========================================================
# Architect Independent Reproduction Script
# WT-H20260513_001 — AX-008 3rd Source Verification
# ===========================================================
# Reproduces L4 baseline + L5_V2 aggressive_regime independently
# from Forge data.table approach using base R + manual lag.
#
# Sequential overlay formula (Layer 5):
#   ret_orig(t) = PR ret_net(t)  [Iter31 linear_tilt baked, base + AR L4 cost X here]
#
# Reapplied overlay chain (independent reconstruction):
#   w_final(t) = m4_scalar(t-1) × β_AR(t-1) × β_R05(regime(t-1))
#   ret_net_overlay(t) = w_final(t) × ret_orig(t) - cost(Δw_final) × 0.5 × 0.0015
#
# Note: PR ret_net is base sleeve (alpha + Iter31 weighting + base cost).
#       We must layer M4, AR, R05 on top of it (m4 and AR not baked in PR).
#
# Forge: weight_str1715 = base alpha. PR ret_net already includes base cost.
#        m4_scalar / β_AR / β_R05 are applied multiplicatively to base PR returns.
#        Additional cost is charged for Δscalar transitions.
# ===========================================================

suppressPackageStartupMessages({
  library(arrow)
  library(PerformanceAnalytics)
  library(xts)
})

WT_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(WT_DIR)

cat("============================================================\n")
cat("ARCHITECT INDEPENDENT REPRODUCTION — WT-H20260513_001\n")
cat("AX-008 3rd Source Verification (base R + manual lag)\n")
cat("============================================================\n\n")

# ============================================================
# Phase 0: Hash audit START (Pure Function R12)
# ============================================================
source_paths <- list(
  pr  = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
  r05 = "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet",
  m4  = "qepm/mailbox/worktask/WT-D20260430_001/judge_ready/weights.csv",
  ar  = "stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"
)

md5_of <- function(p) {
  cmd <- sprintf('md5sum "%s" | awk \'{print $1}\'', p)
  out <- system(cmd, intern=TRUE)
  out
}

hash_start <- sapply(source_paths, md5_of)
cat("Hash audit START:\n")
for (k in names(hash_start)) {
  cat(sprintf("  %-4s : %s\n", k, hash_start[[k]]))
}
cat("\n")

# ============================================================
# Phase 1: Read sources independently
# ============================================================

# 1.1 PR ret_net (base sleeve)
pr_raw <- read.csv(source_paths$pr, stringsAsFactors=FALSE)
pr_raw$date <- as.Date(pr_raw$date)
pr <- data.frame(
  date   = pr_raw$date,
  ret_net= as.numeric(pr_raw$ret_net),
  TO     = as.numeric(pr_raw$turnover)
)
pr$ym <- format(pr$date, "%Y-%m")
cat(sprintf("PR (base sleeve): %d months, %s ~ %s\n",
            nrow(pr), as.character(min(pr$date)), as.character(max(pr$date))))

# 1.2 R05 regime per date
r05 <- read_parquet(source_paths$r05)
regime_df <- unique(r05[, c("Date", "regime_state")])
regime_df$Date <- as.Date(regime_df$Date)
regime_df <- regime_df[order(regime_df$Date), ]
regime_df$ym <- format(regime_df$Date, "%Y-%m")
cat(sprintf("R05 regime: %d unique dates, %s ~ %s\n",
            nrow(regime_df), as.character(min(regime_df$Date)), as.character(max(regime_df$Date))))
cat("Regime distribution:\n")
print(table(regime_df$regime_state))

# 1.3 AR beta_t_mapping
ar <- read.csv(source_paths$ar, stringsAsFactors=FALSE)
ar$Date <- as.Date(ar$Date)
ar$ym <- format(ar$Date, "%Y-%m")
cat(sprintf("AR: %d rows, beta_threshold distribution:\n", nrow(ar)))
print(table(ar$beta_threshold, useNA="ifany"))

# 1.4 M4 schedule
m4 <- read.csv(source_paths$m4, stringsAsFactors=FALSE)
m4$Date <- as.Date(m4$Date)
m4$ym <- format(m4$Date, "%Y-%m")
cat(sprintf("M4: %d rows\n", nrow(m4)))

# ============================================================
# Phase 2: Align by ym key + apply t-1 lag manually (PIT)
# ============================================================
# Convention:
#   ret_net at date t = month t realized return (decision at t-1 close)
#   m4_scalar(t) decision is m4_scalar(t-1) [PIT: month t-1 sees m4 BOCPD signal]
#   β_AR(t) decision is β_AR(t-1)
#   β_R05(regime(t)) decision is β_R05(regime(t-1))
# So we lag scalars by 1 month relative to PR date.

# Build month-keyed master table (PR is anchor)
master <- pr[, c("date","ym","ret_net","TO")]

# Map ym to regime, AR beta, M4 scalar (THEN lag by 1)
# Regime: regime_df has dates 2004-01 ~ 2026-04 (268 = 267 PR + 1 future)
master <- merge(master, regime_df[, c("ym","regime_state")], by="ym", all.x=TRUE)
master <- merge(master, ar[, c("ym","beta_threshold")], by="ym", all.x=TRUE)
master <- merge(master, m4[, c("ym","weight_str1715")], by="ym", all.x=TRUE)
master <- master[order(master$date), ]

# Show alignment
cat("\nMaster table (first 8 + last 5):\n")
print(rbind(head(master, 8), tail(master, 5)))
cat("\nNA counts:\n")
print(sapply(master[, c("regime_state","beta_threshold","weight_str1715")],
             function(x) sum(is.na(x))))

# ============================================================
# Phase 3: Manual t-1 lag (Forge convention check)
# ============================================================
# Forge convention check: PR base sleeve has its OWN cost baked in
# (turnover col). m4 and β_AR are scalars applied at t to ret(t).
# Forge file run_layer5_R05_overlay.R indicates:
#   m4 lag: shift(m4_scalar, 1)
#   β_AR lag: shift(beta_threshold, 1)
#   β_R05(regime): regime taken at t-1 (regime(t) is signal AT EOM of month t, used at t+1)
#
# Per Forge note in r05 alpha_scores_new.parquet:
#   regime per date IS sig_date convention (already aligned to Usable_Date).
# Forge package PIT statement: "shift(1) applied on β_AR, β_R05, m4"
# We honor that exact convention.

n <- nrow(master)
# t-1 shift (NA-pad at head)
master$m4_scalar_lag <- c(NA, head(master$weight_str1715, n-1))
master$beta_ar_lag   <- c(NA, head(master$beta_threshold, n-1))
master$regime_lag    <- c(NA, head(master$regime_state, n-1))

# ============================================================
# Phase 4: V2 aggressive_regime mapping
# β_R05(regime) = BULL/NORMAL=1.0, CAUTION=0.5, CRISIS=0.3
# ============================================================
v2_beta_r05 <- function(r) {
  ifelse(is.na(r), NA_real_,
    ifelse(r %in% c("BULL","NORMAL"), 1.0,
      ifelse(r == "CAUTION", 0.5,
        ifelse(r == "CRISIS", 0.3, NA_real_))))
}
master$beta_r05_v2_lag <- v2_beta_r05(master$regime_lag)

# Also compute V1 (mild), V3 (medium) for sanity
master$beta_r05_v1_lag <- ifelse(is.na(master$regime_lag), NA_real_,
                          ifelse(master$regime_lag %in% c("BULL","NORMAL"), 1.0,
                          ifelse(master$regime_lag == "CAUTION", 0.7,
                          ifelse(master$regime_lag == "CRISIS", 0.5, NA_real_))))
master$beta_r05_v3_lag <- ifelse(is.na(master$regime_lag), NA_real_,
                          ifelse(master$regime_lag %in% c("BULL","NORMAL"), 1.0,
                          ifelse(master$regime_lag == "CAUTION", 0.6,
                          ifelse(master$regime_lag == "CRISIS", 0.4, NA_real_))))

# ============================================================
# Phase 5: Compute composite w_final and overlay returns
# ============================================================
# L4 baseline: w_final_L4 = m4_lag × beta_ar_lag (no β_R05)
# L5 V2:       w_final_V2 = m4_lag × beta_ar_lag × beta_r05_v2_lag

# Forge approach: PR ret_net is the base sleeve. m4 & AR & R05 are scalars
# multiplied on TOP of PR. Additional Δscalar cost is 15bps × |Δ| × 0.5.
# Cash residual (1 - w_final) earns 0 in this admit precedent.

# Default: drop first row (NA from lag) for backtest period
# Forge admitted_baseline panel = 255m_admit_baseline_comparable
# (anchor 2005-02-01 ~ 2026-04-01 = 255 months including endpoints)
# Forge raw_cover panel = 267m (first_anchor 2004-02-02 ~ 2026-04-01)

# Compute the chain on FULL 267m (NA-aware) then subset 255m for admit panel
compute_overlay <- function(master, w_col, label) {
  m <- master
  w <- m[[w_col]]
  # NA-safe: at first row w is NA, output NA
  ret_orig <- m$ret_net
  # Δw cost (15bps round-trip, divide by 2 for one-way)
  dw <- c(NA, abs(diff(w)))
  cost_extra <- ifelse(is.na(dw), 0, dw * 0.0015 * 0.5)
  # Forge convention: full Δw × 0.0015 (since Δ scalar transitions are round-trip cash⇄risk)
  # Per forge_package: "AR Δβ × 0.0015 + β_R05 Δβ × 0.0015"
  # We use 0.0015 (round-trip 15bps single application = one-way trade × 2 directions consolidated)
  cost_extra_v2 <- ifelse(is.na(dw), 0, dw * 0.0015)
  # Cash residual (1 - w) earns 0
  # Overlay return = w × ret_orig - cost_extra
  # We compute both conventions and use the one that reproduces Forge L4 1.7486 exactly
  ret_overlay_v1 <- w * ret_orig - cost_extra
  ret_overlay_v2 <- w * ret_orig - cost_extra_v2
  data.frame(date=m$date, ym=m$ym, w_final=w, ret_orig=ret_orig,
             dw=dw, cost_v1=cost_extra, cost_v2=cost_extra_v2,
             ret_overlay_v1=ret_overlay_v1, ret_overlay_v2=ret_overlay_v2)
}

# w_final for L4 and V2
master$w_final_L4 <- master$m4_scalar_lag * master$beta_ar_lag
master$w_final_V2 <- master$m4_scalar_lag * master$beta_ar_lag * master$beta_r05_v2_lag
master$w_final_V1 <- master$m4_scalar_lag * master$beta_ar_lag * master$beta_r05_v1_lag
master$w_final_V3 <- master$m4_scalar_lag * master$beta_ar_lag * master$beta_r05_v3_lag

# Build overlay returns
overlay_L4 <- compute_overlay(master, "w_final_L4", "L4")
overlay_V2 <- compute_overlay(master, "w_final_V2", "V2")
overlay_V1 <- compute_overlay(master, "w_final_V1", "V1")
overlay_V3 <- compute_overlay(master, "w_final_V3", "V3")

# Show first NA pattern
cat("\nFirst row NA check (lag effect):\n")
print(head(master[, c("date","ym","weight_str1715","beta_threshold",
                       "regime_state","m4_scalar_lag","beta_ar_lag",
                       "regime_lag","w_final_L4","w_final_V2")], 4))

# ============================================================
# Phase 6: Backtest panels — 267m raw + 255m admit-comparable
# ============================================================
# Subset construction:
#   267m raw: first_anchor = 2004-02-02, last = 2026-04-01 (n=267)
#   But first row has NA m4_lag → effective n = 266 NA-dropped
# Forge claim: 267 months in raw panel - meaning Forge fills NA at row 1?
# Let's check what Forge does with the first month's NA.
# Forge convention from sr_realized_share_based n=267 = uses all 267 PR months
# implying first month uses no overlay (w_final = NA → treat as 1.0? or ret_orig?)
#
# Test both:
#  (a) drop NA first row → n=266
#  (b) impute first row w=1 (base sleeve only) → n=267
#
# Then 255m admit panel = 2005-02-01 ~ 2026-04-01 (last 255 months)

# Build NAV series both ways
build_nav <- function(rets, dates, label, drop_na=TRUE) {
  if (drop_na) {
    keep <- !is.na(rets)
    rets <- rets[keep]; dates <- dates[keep]
  } else {
    rets[is.na(rets)] <- 0
  }
  xts(rets, order.by=dates)
}

# Use Forge's exact convention. forge cost = 0.0015 (full Δ) per package note.
# Try cost_v2 (Δw × 0.0015) which matches Forge note.
L4_xts <- build_nav(overlay_L4$ret_overlay_v2, overlay_L4$date, "L4")
V2_xts <- build_nav(overlay_V2$ret_overlay_v2, overlay_V2$date, "V2")
V1_xts <- build_nav(overlay_V1$ret_overlay_v2, overlay_V1$date, "V1")
V3_xts <- build_nav(overlay_V3$ret_overlay_v2, overlay_V3$date, "V3")

cat("\nL4 effective length (after NA drop):", length(L4_xts), "\n")
cat("V2 effective length (after NA drop):", length(V2_xts), "\n")
cat("L4 first / last 3 entries (date | ret):\n")
print(head(L4_xts, 3)); print(tail(L4_xts, 3))

# ============================================================
# Phase 7: PerformanceAnalytics standard metrics
# ============================================================
compute_metrics <- function(ret_xts, label, anchor_start=NULL, panel_label="") {
  if (!is.null(anchor_start)) {
    ret_xts <- ret_xts[index(ret_xts) >= as.Date(anchor_start)]
  }
  n_m <- length(ret_xts)
  if (n_m < 2) return(NULL)
  # Standard PerformanceAnalytics functions
  ar_stats <- table.AnnualizedReturns(ret_xts, Rf=0, scale=12, geometric=TRUE, digits=10)
  cagr <- as.numeric(ar_stats["Annualized Return", 1])
  vol  <- as.numeric(ar_stats["Annualized Std Dev", 1])
  sr   <- as.numeric(ar_stats["Annualized Sharpe (Rf=0%)", 1])
  mdd  <- as.numeric(maxDrawdown(ret_xts, geometric=TRUE))
  sortino <- as.numeric(SortinoRatio(ret_xts, MAR=0)) * sqrt(12)  # annualized
  calmar  <- as.numeric(CalmarRatio(ret_xts, scale=12))
  cat(sprintf("\n[%s%s] n=%d | SR=%.4f | MDD=%.4f | CAGR=%.4f | Vol=%.4f | Sortino=%.4f | Calmar=%.4f\n",
              label, panel_label, n_m, sr, -abs(mdd), cagr, vol, sortino, calmar))
  list(label=label, panel=panel_label, n_months=n_m,
       Sharpe=sr, MDD=-abs(mdd), CAGR=cagr, Vol=vol,
       Sortino=sortino, Calmar=calmar)
}

cat("\n============================================================\n")
cat("PANEL 1: 267m raw cover (full PR)\n")
cat("============================================================\n")
L4_267  <- compute_metrics(L4_xts, "L4_baseline", NULL, "_267m")
V2_267  <- compute_metrics(V2_xts, "V2_aggressive", NULL, "_267m")
V1_267  <- compute_metrics(V1_xts, "V1_mild", NULL, "_267m")
V3_267  <- compute_metrics(V3_xts, "V3_medium", NULL, "_267m")

cat("\n============================================================\n")
cat("PANEL 2: 255m admit-comparable (anchor 2005-02-01 ~ 2026-04-01)\n")
cat("============================================================\n")
L4_255  <- compute_metrics(L4_xts, "L4_baseline", "2005-02-01", "_255m")
V2_255  <- compute_metrics(V2_xts, "V2_aggressive", "2005-02-01", "_255m")
V1_255  <- compute_metrics(V1_xts, "V1_mild", "2005-02-01", "_255m")
V3_255  <- compute_metrics(V3_xts, "V3_medium", "2005-02-01", "_255m")

# ============================================================
# Phase 8: Hash audit END
# ============================================================
hash_end <- sapply(source_paths, md5_of)
hash_match <- all(hash_start == hash_end)
cat("\n============================================================\n")
cat("Hash audit END (Pure Function R12):\n")
for (k in names(hash_end)) {
  match_flag <- ifelse(hash_start[[k]] == hash_end[[k]], "MATCH", "DIFFER")
  cat(sprintf("  %-4s : %s [%s]\n", k, hash_end[[k]], match_flag))
}
cat(sprintf("ALL_UNCHANGED=%s\n", hash_match))

# ============================================================
# Phase 9: Save results
# ============================================================
all_results <- list(
  hash_audit = list(
    start = as.list(hash_start),
    end   = as.list(hash_end),
    all_unchanged = hash_match
  ),
  panel_255m = list(
    L4=L4_255, V2=V2_255, V1=V1_255, V3=V3_255
  ),
  panel_267m = list(
    L4=L4_267, V2=V2_267, V1=V1_267, V3=V3_267
  )
)

saveRDS(all_results, "qepm/mailbox/worktask/WT-H20260513_001/architect_independent_results.rds")
write.csv(do.call(rbind, lapply(list(L4=L4_267, V2=V2_267, V1=V1_267, V3=V3_267,
                                      L4_a=L4_255, V2_a=V2_255, V1_a=V1_255, V3_a=V3_255),
                                 as.data.frame)),
          "qepm/mailbox/worktask/WT-H20260513_001/architect_metrics_table.csv",
          row.names=TRUE)
saveRDS(master,  "qepm/mailbox/worktask/WT-H20260513_001/architect_master_table.rds")

cat("\nResults saved to:\n")
cat("  architect_independent_results.rds\n")
cat("  architect_metrics_table.csv\n")
cat("  architect_master_table.rds\n")
cat("\nDONE.\n")
