#==============================================================================
# Build weights.csv for optimization_package — WT-D20260511_002
#
# selected method: 01_static_baseline_retain (DM test no sig dynamic improvement)
# 2nd candidate:   09_regime_crisis_aggr (CRISIS shift, NOT stat sig but mild improvement)
#
# Output structure: monthly schedule with all sleeves + regime label + weight columns
# Schedule density: 256m sig_dates (Risk Agent 정합) — § 9 Schedule Density Mandate
#==============================================================================

suppressMessages({ library(data.table) })
set.seed(20260511)

returns <- read.csv("stage_artifacts/WT_P20260505_001/merged_returns_3source.csv", stringsAsFactors=FALSE)
returns$date <- as.Date(returns$date)
returns_full <- as.data.table(returns[!is.na(returns$str1715), ])
returns_full[, cash := 0]
assets <- c("str1715", "kr10y", "tsmom", "cash")

# Regime detection
regime_from_str1715 <- function(r) {
  n <- length(r); rs <- rep(NA, n)
  for (i in 12:n) rs[i] <- sum(r[(i-11):i])
  pct <- rep(NA, n)
  for (i in 12:n) { h <- rs[12:i]; h <- h[!is.na(h)]
    if (length(h)>1) pct[i] <- rank(h)[length(h)]/length(h) }
  reg <- rep(NA_character_, n)
  reg[!is.na(pct) & pct > 0.75] <- "BULL"
  reg[!is.na(pct) & pct > 0.50 & pct <= 0.75] <- "NORMAL"
  reg[!is.na(pct) & pct > 0.25 & pct <= 0.50] <- "CAUTION"
  reg[!is.na(pct) & pct <= 0.25] <- "CRISIS"
  c(NA, reg[-n])
}
returns_full[, regime_lag := regime_from_str1715(str1715)]

# Selected method: 01_static_baseline (50/25/20/5 retain)
W_selected <- matrix(c(0.50, 0.20, 0.25, 0.05), nrow=nrow(returns_full), ncol=4, byrow=TRUE, dimnames=list(NULL, assets))

# 2nd candidate: 09_regime_crisis_aggr
n <- nrow(returns_full); base <- c(str1715=0.50, kr10y=0.20, tsmom=0.25, cash=0.05)
shift <- c(str1715=-0.20, kr10y=+0.10, tsmom=+0.05, cash=+0.05)
W_2nd <- matrix(NA, n, 4, dimnames=list(NULL, assets))
for (t in 1:n) {
  reg <- returns_full$regime_lag[t]
  W_2nd[t, ] <- if (!is.na(reg) && reg=="CRISIS") (base+shift)[assets] else base[assets]
  W_2nd[t, ] <- W_2nd[t, ]/sum(W_2nd[t, ])
}

# Build weights.csv
weights_df <- data.frame(
  as_of_date = returns_full$date,
  ym = returns_full$ym,
  regime_lag = returns_full$regime_lag,
  # selected (static)
  w_str1715 = round(W_selected[, "str1715"], 6),
  w_kr10y = round(W_selected[, "kr10y"], 6),
  w_tsmom = round(W_selected[, "tsmom"], 6),
  w_cash = round(W_selected[, "cash"], 6),
  # 2nd candidate
  w_2nd_str1715 = round(W_2nd[, "str1715"], 6),
  w_2nd_kr10y = round(W_2nd[, "kr10y"], 6),
  w_2nd_tsmom = round(W_2nd[, "tsmom"], 6),
  w_2nd_cash = round(W_2nd[, "cash"], 6),
  method_selected = "01_static_baseline_retain",
  method_2nd = "09_regime_crisis_aggr",
  stringsAsFactors = FALSE
)

# Validate hard constraints (Hook strict)
cat("=== weights.csv hard constraint validation ===\n")
sum_check <- abs(rowSums(weights_df[, c("w_str1715", "w_kr10y", "w_tsmom", "w_cash")]) - 1) < 0.001
cat("Σw=1 check (selected):", sum(sum_check), "/", nrow(weights_df), "rows pass\n")
sum_check_2 <- abs(rowSums(weights_df[, c("w_2nd_str1715", "w_2nd_kr10y", "w_2nd_tsmom", "w_2nd_cash")]) - 1) < 0.001
cat("Σw=1 check (2nd):", sum(sum_check_2), "/", nrow(weights_df), "rows pass\n")

bound_check <- all(weights_df$w_str1715 >= 0 & weights_df$w_str1715 <= 0.70) &
               all(weights_df$w_kr10y >= 0 & weights_df$w_kr10y <= 0.40) &
               all(weights_df$w_tsmom >= 0 & weights_df$w_tsmom <= 0.40) &
               all(weights_df$w_cash >= 0 & weights_df$w_cash <= 0.30)
cat("Per-sleeve bounds [0.70/0.40/0.40/0.30]:", bound_check, "\n")

# Long-only
cat("Long-only:", all(weights_df$w_str1715 >= 0) & all(weights_df$w_kr10y >= 0) &
                  all(weights_df$w_tsmom >= 0) & all(weights_df$w_cash >= 0), "\n")

# Schedule density (mandate)
cat("Schedule density check:\n")
cat("  unique_dates:", length(unique(weights_df$as_of_date)), "\n")
cat("  expected sig_dates: 256 (full 256m str1715 backbone)\n")
cat("  ratio:", round(length(unique(weights_df$as_of_date)) / 256, 3), "\n")

# Save (note: single sleeve-aggregate weights, not security-level)
# Security-level decomposition would inherit from STR_1715 H1 internal alpha-research
write.csv(weights_df, "stage_artifacts/WT_D20260511_002/weights.csv", row.names=FALSE)
cat("\nSaved: stage_artifacts/WT_D20260511_002/weights.csv (256 rows, sleeve-level)\n")

# Summary stats
cat("\n=== Sleeve-aggregate weight summary ===\n")
cat("Method selected: 01_static_baseline_retain\n")
print(summary(weights_df[, c("w_str1715", "w_kr10y", "w_tsmom", "w_cash")]))
cat("\nMethod 2nd: 09_regime_crisis_aggr\n")
print(summary(weights_df[, c("w_2nd_str1715", "w_2nd_kr10y", "w_2nd_tsmom", "w_2nd_cash")]))

# CRISIS regime distribution (2nd candidate triggers)
cat("\nCRISIS regime triggers (W_2nd):\n")
cat("  total CRISIS months:", sum(!is.na(returns_full$regime_lag) & returns_full$regime_lag == "CRISIS"), "/256\n")
cat("  CRISIS dates (top 10):\n")
crisis_dates <- returns_full$date[which(!is.na(returns_full$regime_lag) & returns_full$regime_lag == "CRISIS")]
print(head(crisis_dates, 10))
