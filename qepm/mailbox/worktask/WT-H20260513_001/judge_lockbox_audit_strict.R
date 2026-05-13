# Judge Lockbox Audit Strict — n=27 boundary (decision_date >= 2024-01-23)
# Codex C4 ACCEPT disposition: decision_date strict interpretation

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-H20260513_001")

prl <- fread(file.path(WT_DIR, "output/period_returns_layer5.csv"))
prl[, anchor_date := as.Date(anchor_date)]
setorder(prl, anchor_date)

# Read weights.csv for decision_date alignment
w <- fread(file.path(WT_DIR, "weights.csv"))
w[, decision_date := as.Date(decision_date)]
w[, anchor_date := as.Date(as_of_date)]
setorder(w, anchor_date)

# Strict lockbox boundary: decision_date >= 2024-01-23
seal_date <- as.Date("2024-01-23")
lockbox_rows_strict <- w[decision_date >= seal_date]
cat(sprintf("Strict lockbox rows (decision_date >= %s): n=%d\n",
            seal_date, nrow(lockbox_rows_strict)))
cat(sprintf("First anchor (strict): %s (decision %s)\n",
            min(lockbox_rows_strict$anchor_date), min(lockbox_rows_strict$decision_date)))
cat(sprintf("Last anchor (strict):  %s (decision %s)\n",
            max(lockbox_rows_strict$anchor_date), max(lockbox_rows_strict$decision_date)))

# Get strict OOS period_returns rows
oos_strict <- prl[anchor_date %in% lockbox_rows_strict$anchor_date]
cat(sprintf("OOS_strict period_returns rows: n=%d\n", nrow(oos_strict)))

# IS = remainder
is_strict <- prl[!anchor_date %in% lockbox_rows_strict$anchor_date]
# But we want IS = pre-seal anchor_dates (everything before strict lockbox start)
is_strict <- prl[anchor_date < min(lockbox_rows_strict$anchor_date)]
cat(sprintf("IS_strict rows: n=%d (anchor %s ~ %s)\n",
            nrow(is_strict), min(is_strict$anchor_date), max(is_strict$anchor_date)))

variants <- c("ret_L4_baseline", "ret_L5_V1", "ret_L5_V2", "ret_L5_V3",
              "ret_L5_V4", "ret_L5_V5")

compute_stats <- function(ret_vec, label) {
  ret_vec <- ret_vec[!is.na(ret_vec)]
  n <- length(ret_vec)
  if (n < 2) return(NULL)
  mu <- mean(ret_vec)
  sd <- sd(ret_vec)
  sr_ann <- mu / sd * sqrt(12)
  cagr <- prod(1 + ret_vec)^(12 / n) - 1
  nav <- cumprod(1 + ret_vec)
  mdd <- min(nav / cummax(nav) - 1)
  list(
    period = label,
    n = n,
    SR_ann = round(sr_ann, 4),
    CAGR = round(cagr, 4),
    MDD = round(mdd, 4),
    mu_monthly = round(mu, 6),
    sd_monthly = round(sd, 6)
  )
}

cat("\n----- IS_strict period (anchor < first strict lockbox anchor) -----\n")
is_results_strict <- list()
for (v in variants) {
  r <- compute_stats(is_strict[[v]], "IS_strict")
  is_results_strict[[v]] <- r
  cat(sprintf("%-22s | n=%d | SR_ann=%.4f | CAGR=%.4f | MDD=%.4f\n",
              v, r$n, r$SR_ann, r$CAGR, r$MDD))
}

cat("\n----- OOS_strict period (decision_date >= 2024-01-23) -----\n")
oos_results_strict <- list()
for (v in variants) {
  r <- compute_stats(oos_strict[[v]], "OOS_strict")
  oos_results_strict[[v]] <- r
  cat(sprintf("%-22s | n=%d | SR_ann=%.4f | CAGR=%.4f | MDD=%.4f\n",
              v, r$n, r$SR_ann, r$CAGR, r$MDD))
}

cat("\n----- IS_strict vs OOS_strict SR Ratio -----\n")
for (v in variants) {
  is_sr <- is_results_strict[[v]]$SR_ann
  oos_sr <- oos_results_strict[[v]]$SR_ann
  ratio <- oos_sr / is_sr
  cat(sprintf("%-22s | IS=%.4f | OOS=%.4f | ratio=%.4f %s\n",
              v, is_sr, oos_sr, ratio,
              ifelse(ratio >= 0.7, "PASS", "WARN")))
}

# Save audit
audit_out <- list(
  audit_kind = "judge_lockbox_period_audit_STRICT",
  wt_id = "WT-H20260513_001",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  codex_C4_disposition = "ACCEPT — decision_date strict boundary applied",
  seal_date = as.character(seal_date),
  is_strict_period = list(
    start = as.character(min(is_strict$anchor_date)),
    end = as.character(max(is_strict$anchor_date)),
    n = nrow(is_strict)
  ),
  oos_strict_period = list(
    start_anchor = as.character(min(oos_strict$anchor_date)),
    start_decision = as.character(min(lockbox_rows_strict$decision_date)),
    end_anchor = as.character(max(oos_strict$anchor_date)),
    end_decision = as.character(max(lockbox_rows_strict$decision_date)),
    n = nrow(oos_strict)
  ),
  is_metrics_strict = is_results_strict,
  oos_metrics_strict = oos_results_strict,
  is_oos_sr_ratio_strict = sapply(variants, function(v) {
    a <- is_results_strict[[v]]$SR_ann
    b <- oos_results_strict[[v]]$SR_ann
    if (is.null(a) || is.null(b) || abs(a) < 1e-9) return(NA_real_)
    round(b/a, 4)
  })
)

write_json(audit_out, file.path(WT_DIR, "judge_lockbox_audit_strict.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "null")

cat(sprintf("\nSaved: %s\n", file.path(WT_DIR, "judge_lockbox_audit_strict.json")))
