#==============================================================================
# CRISIS held-month cap fix (Codex Concern #6 ACCEPT)
# Enforce pre-cash 0.10 cap on all CRISIS dates including held months.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

WT_ID   <- "WT-D20260425_011"
WT_DIR  <- file.path("qepm/mailbox/worktask", WT_ID)
ART_DIR <- file.path("stage_artifacts", "WT_D20260425_011")
WEIGHT_UB_CRISIS <- 0.10

# Iterative cap projection (re-used)
iter_cap_project <- function(w, ub, lb = 0, target_sum = 1, max_iter = 100, tol = 1e-9) {
  for (k in seq_len(max_iter)) {
    s <- sum(w)
    if (s <= 1e-12) return(rep(target_sum / length(w), length(w)))
    w <- w * (target_sum / s)
    over <- w > ub + tol
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + tol)
    if (length(free) == 0) break
    cap_avail <- ub - w[free]
    total_cap <- sum(cap_avail)
    if (total_cap <= 0) break
    if (excess <= total_cap) {
      w[free] <- w[free] + excess * (cap_avail / total_cap)
    } else {
      w[free] <- w[free] + cap_avail  # absorb to cap
      # Remaining excess unabsorbable — break
      break
    }
  }
  w / sum(w) * target_sum
}

w <- fread(file.path(WT_DIR, "weights.csv"))

# CRISIS dates that need fix
crisis_dates <- unique(w[regime == "CRISIS"]$as_of_date)
n_fixed <- 0L
for (d in crisis_dates) {
  rows_d <- w[as_of_date == d]
  risk_rows <- rows_d[ticker != "CASH"]
  cash_rows <- rows_d[ticker == "CASH"]
  cash_pct <- if (nrow(cash_rows) > 0) cash_rows$weight[1] else 0
  # Pre-cash weight: w / (1 - cash_pct)
  pre_cash <- risk_rows$weight / (1 - cash_pct)
  if (max(pre_cash) > WEIGHT_UB_CRISIS + 1e-6) {
    n_fixed <- n_fixed + 1L
    # Apply iterative 0.10 cap on pre-cash, then re-multiply by (1 - cash_pct)
    pre_cash_proj <- iter_cap_project(pre_cash, ub = WEIGHT_UB_CRISIS, lb = 0, target_sum = 1)
    risk_rows$weight <- pre_cash_proj * (1 - cash_pct)
    # Replace
    w[as_of_date == d & ticker != "CASH", weight := risk_rows$weight]
    cat(sprintf("  Fixed CRISIS date %s: max pre-cash %.4f → %.4f\n",
                as.character(d), max(pre_cash), max(pre_cash_proj)))
  }
}

cat(sprintf("[CRISIS Fix] %d / %d CRISIS dates required cap projection\n",
            n_fixed, length(crisis_dates)))

# Verify
crisis_check <- w[regime == "CRISIS" & ticker != "CASH"]
crisis_check[, pre_cash := weight / (1 - cash_pct)]
cat(sprintf("[CRISIS Fix] Post-fix max pre-cash on CRISIS rows: %.4f (target ≤ 0.10+1e-6)\n",
            max(crisis_check$pre_cash)))

# Verify Σw = 1 still
val <- w[, .(sumw = sum(weight)), by = as_of_date]
cat(sprintf("[CRISIS Fix] Post-fix Σw range: [%.10f, %.10f]\n",
            min(val$sumw), max(val$sumw)))

# Write back
fwrite(w, file.path(WT_DIR, "weights.csv"))
fwrite(w, file.path(ART_DIR, "weights.csv"))
cat("[CRISIS Fix] weights.csv updated (mailbox + stage)\n")
