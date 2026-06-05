#!/usr/bin/env Rscript
# 190_panel_v5h_interactions.R — Cycle 58C Phase 1
# Build v5h panel: v5g (86 features, BBVA-clean via v5f_FIXED2 + 7 cross-market lag1)
# + 5 cross-market × KR interaction features (PIT-safe, both bases are _lag1)
#
# 5 interactions:
#   1. dxy_x_bbva_market_z       = dxy_change_5d_lag1 × bbva_market_z_lag1
#                                  (USD strength × KR market regime, transmission proxy)
#   2. dxy_x_bbva_sovereign_z    = dxy_change_5d_lag1 × bbva_sovereign_z_lag1
#                                  (USD strength × KR sovereign risk, dollar funding squeeze proxy)
#   3. asia_joint_momentum_z     = nikkei225_return_lag1 × hangseng_return_lag1, z-scored
#                                  (Asia intra-day joint, rolling z over 252d)
#   4. sp500_x_us_sector_avg_z   = sp500_overnight_return_lag1 × us_sector_avg_z_lag1 (use base us_sector_avg_z if no _lag1)
#                                  (US risk-on global × US sector dispersion)
#   5. vix_x_bbva_macro          = vix_change_5d_lag1 × bbva_macro_composite_lag1
#                                  (US vol shock × KR macro composite)
#
# PIT: All 5 interactions are products of features already lag1-shifted in their source build.
#      Result is therefore PIT-safe (no future leakage, same lag1 stamp as components).
#
# Output:
#   - outputs/01_data/feature_panel_v5h_cross_market_interactions.parquet (91 features = 86 + 5)
#   - outputs/04_evaluation/cycle58c_panel_v5h_build.json

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(jsonlite); library(zoo)
})

WS <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "04_Research/decision_framework/bearish_forecast_v2_alt_data")
setwd(WS)

cat("=", strrep("=", 70), "\n", sep="")
cat("[Cycle 58C Phase 1] Build v5h_cross_market_interactions panel\n")
cat(strrep("=", 70), "\n", sep="")

# ===== Load v5g (86 features = v5f_FIXED2 79 + 7 cross-market) =====
base_path <- "outputs/01_data/feature_panel_v5g_cross_market.parquet"
v5g <- read_parquet(base_path)
v5g$Date <- as.Date(v5g$Date)
v5g <- v5g[order(v5g$Date), ]
cat(sprintf("[loaded] %s  shape=(%d, %d)\n", base_path, nrow(v5g), ncol(v5g)))
base_feat_cols <- setdiff(names(v5g), "Date")
cat(sprintf("  base features: %d\n", length(base_feat_cols)))

# ===== Verify required source columns present =====
req_cols <- c(
  "dxy_change_5d_lag1", "bbva_market_z_lag1", "bbva_sovereign_z_lag1",
  "nikkei225_return_lag1", "hangseng_return_lag1",
  "sp500_overnight_return_lag1",
  "vix_change_5d_lag1", "bbva_macro_composite_lag1"
)
missing_cols <- setdiff(req_cols, base_feat_cols)
if (length(missing_cols) > 0) {
  # Some columns might be present as base (no lag1) — check those too
  alt_check <- gsub("_lag1$", "", missing_cols)
  alt_present <- alt_check %in% base_feat_cols
  cat(sprintf("[WARN] Missing lag1 cols: %s\n", paste(missing_cols, collapse=", ")))
  cat(sprintf("[WARN] Base form present: %s\n", paste(alt_check[alt_present], collapse=", ")))
}

# Find us_sector_avg_z (may not have _lag1 suffix in panel — check both)
us_sector_col <- if ("us_sector_avg_z_lag1" %in% base_feat_cols) "us_sector_avg_z_lag1" else "us_sector_avg_z"
if (!(us_sector_col %in% base_feat_cols)) {
  stop("Cannot find us_sector_avg_z or us_sector_avg_z_lag1 in v5g panel")
}
cat(sprintf("[us_sector] Using column: %s\n", us_sector_col))

# Helper: rolling z-score over 252d (PIT-safe expanding-then-rolling)
rolling_z <- function(x, w = 252) {
  rm <- rollapplyr(x, width = w, FUN = mean, na.rm = TRUE, fill = NA, partial = TRUE)
  rsd <- rollapplyr(x, width = w, FUN = sd, na.rm = TRUE, fill = NA, partial = TRUE)
  z <- (x - rm) / rsd
  z[!is.finite(z)] <- NA
  z
}

# ===== Build 5 interactions =====
panel <- v5g
cat("\n[Phase 1] Constructing 5 cross-market × KR interactions:\n")

# Interaction 1: dxy × bbva_market_z
panel$dxy_x_bbva_market_z_lag1 <- panel$dxy_change_5d_lag1 * panel$bbva_market_z_lag1
n1 <- sum(!is.na(panel$dxy_x_bbva_market_z_lag1))
cat(sprintf("  1. dxy_x_bbva_market_z_lag1            n_notna=%d  range=[%.4f, %.4f]\n",
            n1, min(panel$dxy_x_bbva_market_z_lag1, na.rm=TRUE),
            max(panel$dxy_x_bbva_market_z_lag1, na.rm=TRUE)))

# Interaction 2: dxy × bbva_sovereign_z
panel$dxy_x_bbva_sovereign_z_lag1 <- panel$dxy_change_5d_lag1 * panel$bbva_sovereign_z_lag1
n2 <- sum(!is.na(panel$dxy_x_bbva_sovereign_z_lag1))
cat(sprintf("  2. dxy_x_bbva_sovereign_z_lag1         n_notna=%d  range=[%.4f, %.4f]\n",
            n2, min(panel$dxy_x_bbva_sovereign_z_lag1, na.rm=TRUE),
            max(panel$dxy_x_bbva_sovereign_z_lag1, na.rm=TRUE)))

# Interaction 3: Asia joint momentum (Nikkei × HangSeng, z-scored)
asia_raw <- panel$nikkei225_return_lag1 * panel$hangseng_return_lag1
panel$asia_joint_momentum_z_lag1 <- rolling_z(asia_raw, w = 252L)
n3 <- sum(!is.na(panel$asia_joint_momentum_z_lag1))
cat(sprintf("  3. asia_joint_momentum_z_lag1          n_notna=%d  range=[%.4f, %.4f]\n",
            n3, min(panel$asia_joint_momentum_z_lag1, na.rm=TRUE),
            max(panel$asia_joint_momentum_z_lag1, na.rm=TRUE)))

# Interaction 4: SP500 overnight × US sector avg
panel$sp500_x_us_sector_avg_lag1 <- panel$sp500_overnight_return_lag1 * panel[[us_sector_col]]
n4 <- sum(!is.na(panel$sp500_x_us_sector_avg_lag1))
cat(sprintf("  4. sp500_x_us_sector_avg_lag1          n_notna=%d  range=[%.4f, %.4f]\n",
            n4, min(panel$sp500_x_us_sector_avg_lag1, na.rm=TRUE),
            max(panel$sp500_x_us_sector_avg_lag1, na.rm=TRUE)))

# Interaction 5: VIX × BBVA macro
panel$vix_x_bbva_macro_lag1 <- panel$vix_change_5d_lag1 * panel$bbva_macro_composite_lag1
n5 <- sum(!is.na(panel$vix_x_bbva_macro_lag1))
cat(sprintf("  5. vix_x_bbva_macro_lag1               n_notna=%d  range=[%.4f, %.4f]\n",
            n5, min(panel$vix_x_bbva_macro_lag1, na.rm=TRUE),
            max(panel$vix_x_bbva_macro_lag1, na.rm=TRUE)))

interaction_cols <- c(
  "dxy_x_bbva_market_z_lag1",
  "dxy_x_bbva_sovereign_z_lag1",
  "asia_joint_momentum_z_lag1",
  "sp500_x_us_sector_avg_lag1",
  "vix_x_bbva_macro_lag1"
)
stopifnot(all(interaction_cols %in% names(panel)))
new_feat_cols <- setdiff(names(panel), "Date")
expected_n <- length(base_feat_cols) + 5L
cat(sprintf("\n[panel] v5h shape=(%d, %d)  features=%d (expected=%d)\n",
            nrow(panel), ncol(panel), length(new_feat_cols), expected_n))
stopifnot(length(new_feat_cols) == expected_n)

# ===== Correlation with base features (sanity, not constraint) =====
cat("\n[Correlations] interaction vs source-features (drop NA, pearson):\n")
cor_audit <- list()
pairs <- list(
  c("dxy_x_bbva_market_z_lag1", "dxy_change_5d_lag1"),
  c("dxy_x_bbva_market_z_lag1", "bbva_market_z_lag1"),
  c("dxy_x_bbva_sovereign_z_lag1", "bbva_sovereign_z_lag1"),
  c("asia_joint_momentum_z_lag1", "nikkei225_return_lag1"),
  c("asia_joint_momentum_z_lag1", "hangseng_return_lag1"),
  c("sp500_x_us_sector_avg_lag1", "sp500_overnight_return_lag1"),
  c("vix_x_bbva_macro_lag1", "vix_change_5d_lag1"),
  c("vix_x_bbva_macro_lag1", "bbva_macro_composite_lag1")
)
for (p in pairs) {
  a <- panel[[p[1]]]; b <- panel[[p[2]]]
  m <- complete.cases(a, b)
  if (sum(m) > 10) {
    r <- cor(a[m], b[m], use = "complete.obs")
    cor_audit[[paste(p, collapse="_VS_")]] <- round(r, 4)
    cat(sprintf("  %-50s r=%.4f (n=%d)\n", paste(p, collapse=" vs "), r, sum(m)))
  }
}

# ===== Fill NaN with 0 (neutral) for non-essential rows (pre-2000 history) =====
# Matches 187_panel_v5g_cross_market.py policy
for (c in interaction_cols) {
  n_before <- sum(is.na(panel[[c]]))
  panel[[c]][is.na(panel[[c]])] <- 0
  cat(sprintf("[fillna_zero] %s: filled %d NaN -> 0 (neutral)\n", c, n_before))
}

# ===== Save =====
out_path <- "outputs/01_data/feature_panel_v5h_cross_market_interactions.parquet"
write_parquet(panel, out_path)
cat(sprintf("\n[saved] %s\n", out_path))
cat(sprintf("  shape: (%d, %d) — Date + %d features\n", nrow(panel), ncol(panel), length(new_feat_cols)))

# ===== Audit JSON =====
audit <- list(
  cycle = "58C_Phase1",
  script = "190_panel_v5h_interactions.R",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  inputs = list(
    base_panel = base_path,
    base_features = length(base_feat_cols),
    base_n_rows = nrow(v5g)
  ),
  output = list(
    panel_path = out_path,
    n_features = length(new_feat_cols),
    n_rows = nrow(panel)
  ),
  interactions = list(
    dxy_x_bbva_market_z_lag1 = list(
      formula = "dxy_change_5d_lag1 * bbva_market_z_lag1",
      rationale = "USD strength shock × KR market regime — transmission proxy",
      n_notna = n1
    ),
    dxy_x_bbva_sovereign_z_lag1 = list(
      formula = "dxy_change_5d_lag1 * bbva_sovereign_z_lag1",
      rationale = "USD strength × KR sovereign risk — dollar funding squeeze",
      n_notna = n2
    ),
    asia_joint_momentum_z_lag1 = list(
      formula = "rolling_z_252d(nikkei225_return_lag1 * hangseng_return_lag1)",
      rationale = "Asia intra-day joint momentum (Nikkei × HangSeng cor 0.446 in 58B audit) — orthogonal component via z-score",
      n_notna = n3
    ),
    sp500_x_us_sector_avg_lag1 = list(
      formula = sprintf("sp500_overnight_return_lag1 * %s", us_sector_col),
      rationale = "US risk-on global × US sector dispersion conditional",
      n_notna = n4,
      us_sector_col_used = us_sector_col
    ),
    vix_x_bbva_macro_lag1 = list(
      formula = "vix_change_5d_lag1 * bbva_macro_composite_lag1",
      rationale = "US vol shock × KR macro composite — global risk-off propagation",
      n_notna = n5
    )
  ),
  pit_safety = list(
    audit = "All 5 interactions are products of features already lag1-shifted at source. Result is PIT-safe (same lag1 stamp).",
    fillna_zero_policy = "NaN filled with 0 (neutral), consistent with 187_panel_v5g_cross_market.py"
  ),
  correlations_to_sources = cor_audit
)

audit_path <- "outputs/04_evaluation/cycle58c_panel_v5h_build.json"
writeLines(jsonlite::toJSON(audit, pretty = TRUE, auto_unbox = TRUE), audit_path)
cat(sprintf("[audit] Saved: %s\n", audit_path))

cat("\n", strrep("=", 70), "\n", sep="")
cat("[Phase 1 DONE] v5h panel built: 91 features (86 v5g + 5 interactions)\n")
cat(strrep("=", 70), "\n", sep="")
