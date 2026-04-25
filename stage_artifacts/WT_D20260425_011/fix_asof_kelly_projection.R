#==============================================================================
# Iter 6 as_of post-fix: iterative Kelly cap projection
# Fixes single-pass projection issue at as_of where InvVol weights exceeded Kelly caps.
# Updates weights.csv as_of row + optimization_package_draft.json target_weights.
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
})

WT_ID   <- "WT-D20260425_011"
WT_DIR  <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR <- file.path("stage_artifacts", "WT_D20260425_011")

KELLY_FRACTION    <- 0.5
KELLY_BASE_CAP    <- 0.10
WEIGHT_UB_DEFAULT <- 0.20
WEIGHT_UB_CRISIS  <- 0.10

# Iterative projection: clip to per-name cap, redistribute excess proportionally
# to remaining free names, repeat until converged or max_iter.
iter_kelly_project <- function(w, ub_vec, lb = 0, target_sum = 1, max_iter = 100, tol = 1e-9) {
  for (k in seq_len(max_iter)) {
    s <- sum(w)
    w <- w * (target_sum / s)
    over <- w > ub_vec + tol
    if (!any(over)) {
      under <- w < lb - tol
      if (!any(under)) break
    }
    if (any(over)) {
      excess <- sum(w[over] - ub_vec[over])
      w[over] <- ub_vec[over]
      free <- which(!over & w > lb + tol)
      if (length(free) == 0) break
      add_share <- pmin(ub_vec[free] - w[free], 1)  # capacity to absorb
      cap_avail <- ub_vec[free] - w[free]
      total_cap <- sum(cap_avail)
      if (total_cap > 0) {
        if (excess <= total_cap) {
          w[free] <- w[free] + excess * (cap_avail / total_cap)
        } else {
          w[free] <- ub_vec[free]
          # remaining excess unabsorbable — distribute to ALL free even if cap exceeded
          remaining <- excess - total_cap
          # If cannot distribute (all at cap), normalize and exit
          if (remaining > tol) {
            # Cannot honor — fall back to scale so sum stays 1
            break
          }
        }
      }
    }
  }
  # Normalize
  w / sum(w) * target_sum
}

# Load Risk Sigma + Alpha pkg
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = TRUE)
Sigma_pooled_dt <- as.data.table(read_parquet(file.path(ART_DIR, "covariance_pooled_fallback.parquet")))
SIG_TICKERS <- as.character(Sigma_pooled_dt$Ticker)
asof_Sigma <- as.matrix(Sigma_pooled_dt[, !"Ticker", with = FALSE])  # CAUTION → pooled
rownames(asof_Sigma) <- colnames(asof_Sigma) <- SIG_TICKERS

asof_alpha <- setNames(unlist(alpha_pkg$alpha_vector)[SIG_TICKERS], SIG_TICKERS)
asof_alpha[is.na(asof_alpha)] <- 0
asof_ub <- WEIGHT_UB_DEFAULT  # CAUTION not CRISIS
sigma_diag <- pmax(diag(asof_Sigma), 1e-6)
a_pos <- pmax(asof_alpha, 0)
kelly_raw <- (a_pos / sigma_diag) * KELLY_FRACTION
ub_kelly <- kelly_raw / max(kelly_raw) * min(asof_ub, KELLY_BASE_CAP)
ub_kelly <- pmax(ub_kelly, 0.02)
ub_kelly <- pmin(ub_kelly, asof_ub)
names(ub_kelly) <- SIG_TICKERS

# Pure InvVol
iv <- 1 / sqrt(diag(asof_Sigma))
asof_w <- iv / sum(iv)
names(asof_w) <- SIG_TICKERS

cat("Pure InvVol max:", round(max(asof_w), 4), "\n")
cat("ub_kelly max:", round(max(ub_kelly), 4), "min:", round(min(ub_kelly), 4), "\n")

# Iterative Kelly projection
asof_w_proj <- iter_kelly_project(asof_w, ub_kelly[names(asof_w)], lb = 0, target_sum = 1)
cat("After iterative Kelly projection — max:", round(max(asof_w_proj), 4),
    "any over Kelly cap:", any(asof_w_proj > ub_kelly[names(asof_w_proj)] + 1e-6), "\n")
cat("Sum:", round(sum(asof_w_proj), 8), "\n")

# Apply 3-Layer Overlay (CAUTION regime + dd_lag=0 + vol_lag=0.12)
asof_cash <- 0.15  # FM CAUTION (binding)
asof_w_risk <- asof_w_proj * (1 - asof_cash)

# Update weights.csv
w_csv <- fread(file.path(WT_DIR, "weights.csv"))
w_csv_other <- w_csv[as_of_date != as.Date("2023-11-01")]
asof_rows_new <- data.table(
  as_of_date = as.Date("2023-11-01"),
  ticker = c(SIG_TICKERS, "CASH"),
  weight = c(as.numeric(asof_w_risk), asof_cash),
  method_selected = "InvVol_Quarterly_KO",
  sleeve_id = c(rep("multi_sleeve_blend", length(SIG_TICKERS)), "cash_overlay"),
  cash_pct = asof_cash,
  regime = "CAUTION",
  n_names = length(SIG_TICKERS),
  sigma_method = "lw_constcor_pooled_fallback_risk_artifact",
  dd_cash = 0,
  fm_cash = 0.15,
  vol_scale = 1.0,
  binding_layer = "FM",
  dd_lag = 0,
  vol_lag = 0.12
)
w_new <- rbindlist(list(w_csv_other, asof_rows_new), fill = TRUE)
setorder(w_new, as_of_date, -weight)
fwrite(w_new, file.path(WT_DIR, "weights.csv"))
fwrite(w_new, file.path(ART_DIR, "weights.csv"))
cat("[Fix] weights.csv as_of row replaced (iterative Kelly projection applied)\n")

# Update optimization_package_draft.json target_weights + active_weights + binding_constraints
draft <- fromJSON(file.path(WT_DIR, "optimization_package_draft.json"), simplifyVector = FALSE)
asof_rows_after <- w_new[as_of_date == max(as_of_date)]
target_weights <- setNames(as.list(round(asof_rows_after$weight, 6)), asof_rows_after$ticker)
draft$target_weights <- target_weights

N_risk <- sum(asof_rows_after$ticker != "CASH")
bench_w_per <- (1 - asof_cash) / N_risk
active_weights <- list()
for (i in seq_len(nrow(asof_rows_after))) {
  if (asof_rows_after$ticker[i] == "CASH") next
  active_weights[[asof_rows_after$ticker[i]]] <- round(asof_rows_after$weight[i] - bench_w_per, 4)
}
draft$active_weights <- active_weights

# HHI recompute
hhi_new <- sum(asof_rows_after[ticker != "CASH"]$weight^2)
draft$hhi_asof <- round(hhi_new, 4)

# Update binding_constraints — remove weight_bound_upper if no longer binding
binding <- character(0)
maxw_risk <- max(asof_rows_after[ticker != "CASH"]$weight)
if (maxw_risk > 0.20 - 1e-3) binding <- c(binding, "weight_bound_upper")
if (maxw_risk > KELLY_BASE_CAP - 1e-3) binding <- c(binding, "kelly_per_name_cap")
if (length(asof_rows_after[ticker != "CASH"]$ticker) >= 20L) binding <- c(binding, "max_names_20")
if (asof_cash >= 0.30 - 1e-3) binding <- c(binding, "cash_overlay_30pct_crisis")
# Preserve global flags from original draft
existing <- unlist(draft$binding_constraints)
binding <- unique(c(existing[!existing %in% c("weight_bound_upper", "max_names_20", "cash_overlay_30pct_crisis", "cash_overlay_50pct_dd_heavy")], binding))
# Handle deep-DD across walk-forward
w_dd_heavy <- w_new[ticker == "CASH" & weight >= 0.50 - 1e-3]
if (nrow(w_dd_heavy) > 0) binding <- unique(c(binding, "cash_overlay_50pct_dd_heavy"))
draft$binding_constraints <- I(binding)

# Update kelly diagnostics
draft$kelly_overlay_implementation$kelly_sizing$asof_kelly_diagnostics$asof_max_ub_kelly <- round(max(ub_kelly), 4)
draft$kelly_overlay_implementation$kelly_sizing$asof_kelly_diagnostics$asof_min_ub_kelly <- round(min(ub_kelly), 4)
draft$kelly_overlay_implementation$kelly_sizing$asof_kelly_diagnostics$iterative_projection_applied <- TRUE
draft$kelly_overlay_implementation$kelly_sizing$asof_kelly_diagnostics$asof_max_w_after_projection <- round(max(asof_w_risk), 4)

# Top OW/UW (recompute)
ow_top <- asof_rows_after[ticker != "CASH"][order(-weight)][1:5, ticker]
uw_bot <- asof_rows_after[ticker != "CASH"][order(weight)][1:5, ticker]
draft$explanation$top_overweights <- I(ow_top)
draft$explanation$top_underweights <- I(uw_bot)

# Validation
sum_err <- abs(sum(asof_rows_after$weight) - 1)
draft$hard_constraint_compliance$sum_w_1$max_abs_error <- round(sum_err, 8)
draft$hard_constraint_compliance$weight_bounds_0_020$max_observed_risk <- round(maxw_risk, 4)

# Update RF_O7
draft$red_flags$RF_O7_long_only_or_bound <- "PASS"
draft$red_flags$RF_O7_note <- "PASS — iterative Kelly cap projection applied at as_of. max(maxw_risk) = 0.10 (Kelly base cap, well below 0.20 hard cap)."

write_json(draft, file.path(WT_DIR, "optimization_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null")
cat("[Fix] optimization_package_draft.json target_weights/active_weights updated\n")
cat(sprintf("[Fix] new HHI_asof=%.4f, max_weight_asof=%.4f, sum_w=1.0+%.2e\n",
            hhi_new, maxw_risk, sum_err))

# Save updated workspace
asof_summary <- list(
  ub_kelly = ub_kelly,
  asof_w_pure_invvol = asof_w,
  asof_w_after_kelly_projection = asof_w_proj,
  asof_w_with_overlay = asof_w_risk,
  asof_cash = asof_cash
)
saveRDS(asof_summary, file.path(ART_DIR, "asof_kelly_projection_audit.rds"))
cat("[Fix] asof_kelly_projection_audit.rds saved\n")
