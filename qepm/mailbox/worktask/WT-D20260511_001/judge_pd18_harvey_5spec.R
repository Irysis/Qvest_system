# ═══════════════════════════════════════════════════════════════════════════
# judge_pd18_harvey_5spec.R
# Harvey 5-spec composite regression on PD18 cost-embedded returns
#  Specs: CAPM / Carhart-3 / Carhart-4 / FF5 / FF6
#  KR FF factors: .cache/kr_factor_returns_v2.parquet (RMW + CMA + WML + HML + SMB + MKT + RF)
# ═══════════════════════════════════════════════════════════════════════════

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(sandwich)
  library(lmtest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260511_001"
WT_DIR <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
OUT_DIR <- WT_DIR

cat("══════════════════════════════════════════════════════════════════\n")
cat("Judge PD18 Harvey 5-spec Composite Regression\n")
cat("══════════════════════════════════════════════════════════════════\n\n")

# Load KR FF factors v2
ff <- as.data.table(arrow::read_parquet(file.path(PROJECT_ROOT, ".cache", "kr_factor_returns_v2.parquet")))
ff[, Date := as.Date(Date)]
cat("KR FF factors v2 rows:", nrow(ff), " cols:", paste(names(ff), collapse=","), "\n")
cat("Date range:", as.character(min(ff$Date)), "to", as.character(max(ff$Date)), "\n\n")

# Load PD18 cost-embedded composite returns
comp <- fread(file.path(WT_DIR, "composite_cost_embedded_returns_pd18.csv"))
comp[, Date := as.Date(Date)]

# Merge with FF factors by ym (PD18 uses first-of-month rebal date, FF uses end-of-month;
# align by ym)
comp[, ym := format(Date, "%Y-%m")]
ff[, ym := format(Date, "%Y-%m")]

# Use ym-level alignment
merged <- merge(comp[, .(ym, ret_5sleeve_redistribute, ret_5sleeve_redistribute_cost_oneway,
                          ret_5sleeve_redistribute_cost_roundtrip, ret_S4_baseline,
                          ret_S4_baseline_cost_oneway)],
                ff[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)],
                by = "ym", all.x = TRUE)

merged <- merged[!is.na(MKT)]
cat("Merged rows:", nrow(merged), "\n")
cat("Merged ym range:", min(merged$ym), "to", max(merged$ym), "\n\n")

# Excess return: r - RF
merged[, r_excess_pd18 := ret_5sleeve_redistribute_cost_oneway - RF]
merged[, r_excess_pd18_cost_free := ret_5sleeve_redistribute - RF]
merged[, r_excess_pd18_rt := ret_5sleeve_redistribute_cost_roundtrip - RF]
merged[, r_excess_baseline := ret_S4_baseline_cost_oneway - RF]
merged[, MKT_RF := MKT - RF]

# ─────────────────────────────────────────────────────────────────
# Spec 1: CAPM — r_e ~ MKT
# Spec 2: FF3 (Fama-French 1993) — r_e ~ MKT + SMB + HML
# Spec 3: Carhart-4 — r_e ~ MKT + SMB + HML + WML
# Spec 4: FF5 — r_e ~ MKT + SMB + HML + RMW + CMA
# Spec 5: FF6 — r_e ~ MKT + SMB + HML + RMW + CMA + WML
# ─────────────────────────────────────────────────────────────────

run_spec <- function(data, spec_name, formula_str) {
  fm <- as.formula(formula_str)
  lm_fit <- lm(fm, data = data)
  coef_lm <- coef(lm_fit)
  # NW se with lag 6
  nw_se <- tryCatch({
    sqrt(diag(NeweyWest(lm_fit, lag = 6, prewhite = FALSE)))
  }, error = function(e) {
    cat("    NW SE error for", spec_name, ":", e$message, "\n")
    rep(NA, length(coef_lm))
  })

  alpha_monthly <- coef_lm["(Intercept)"]
  se_alpha_NW <- nw_se["(Intercept)"]
  t_NW_alpha <- alpha_monthly / se_alpha_NW
  alpha_ann <- alpha_monthly * 12

  list(
    spec = spec_name,
    formula = formula_str,
    n = nobs(lm_fit),
    alpha_monthly = unname(alpha_monthly),
    alpha_ann = unname(alpha_ann),
    se_NW_alpha = unname(se_alpha_NW),
    t_NW_alpha = unname(t_NW_alpha),
    R2 = summary(lm_fit)$r.squared,
    adj_R2 = summary(lm_fit)$adj.r.squared,
    coefficients = lapply(coef_lm, unname),
    nw_se = lapply(nw_se, unname),
    harvey_pass = abs(unname(t_NW_alpha)) > 3.0
  )
}

# Run all 5 specs on PD18 cost-embedded 15bps
cat("─────────────────────────────────────────────────────────────────\n")
cat("PD18 cost-embedded 15bps Harvey 5-spec:\n")
cat("─────────────────────────────────────────────────────────────────\n")

specs <- list(
  CAPM = run_spec(merged, "CAPM", "r_excess_pd18 ~ MKT_RF"),
  FF3 = run_spec(merged, "FF3 (Fama-French 1993)", "r_excess_pd18 ~ MKT_RF + SMB + HML"),
  Carhart4 = run_spec(merged, "Carhart-4 (Carhart 1997)", "r_excess_pd18 ~ MKT_RF + SMB + HML + WML"),
  FF5 = run_spec(merged, "FF5 (Fama-French 2015)", "r_excess_pd18 ~ MKT_RF + SMB + HML + RMW + CMA"),
  FF6 = run_spec(merged, "FF6 (FF5 + WML)", "r_excess_pd18 ~ MKT_RF + SMB + HML + RMW + CMA + WML")
)

# Same for baseline cost-15bps
specs_baseline <- list(
  CAPM = run_spec(merged, "CAPM (baseline S4v2)", "r_excess_baseline ~ MKT_RF"),
  FF3 = run_spec(merged, "FF3 (baseline S4v2)", "r_excess_baseline ~ MKT_RF + SMB + HML"),
  Carhart4 = run_spec(merged, "Carhart-4 (baseline S4v2)", "r_excess_baseline ~ MKT_RF + SMB + HML + WML"),
  FF5 = run_spec(merged, "FF5 (baseline S4v2)", "r_excess_baseline ~ MKT_RF + SMB + HML + RMW + CMA"),
  FF6 = run_spec(merged, "FF6 (baseline S4v2)", "r_excess_baseline ~ MKT_RF + SMB + HML + RMW + CMA + WML")
)

# Print summary tables
print_spec <- function(specs, label) {
  cat("\n", label, ":\n", sep = "")
  cat(sprintf("%-30s %10s %10s %10s %10s %10s %s\n",
              "Spec", "α (ann)", "t_NW(α)", "R²", "adj R²", "n", "Harvey >3?"))
  for (s in specs) {
    cat(sprintf("%-30s %10.4f %10.4f %10.4f %10.4f %10d %s\n",
                s$spec, s$alpha_ann, s$t_NW_alpha, s$R2, s$adj_R2, s$n,
                ifelse(s$harvey_pass, "PASS", "FAIL")))
  }
}

print_spec(specs, "PD18 cost-15bps Composite (5-sleeve) Harvey 5-spec")
print_spec(specs_baseline, "S4v2 baseline cost-15bps (4-sleeve) Harvey 5-spec")

# Harvey pass count
harvey_pass_count_pd18 <- sum(sapply(specs, function(x) x$harvey_pass), na.rm = TRUE)
harvey_pass_count_baseline <- sum(sapply(specs_baseline, function(x) x$harvey_pass), na.rm = TRUE)

cat("\nPD18 Harvey pass count (t_NW>3):", harvey_pass_count_pd18, "/ 5\n")
cat("S4v2 baseline Harvey pass count:", harvey_pass_count_baseline, "/ 5\n")

# Save results
output <- list(
  task_id = WT_ID,
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  description = "Harvey 5-spec composite regression on PD18 cost-embedded 15bps + S4v2 baseline",
  factor_data_source = ".cache/kr_factor_returns_v2.parquet (FF5 v2 backfill 2002-07 ~ 2026-03)",
  alignment = "ym-level (PD18 1st-of-month + FF end-of-month)",
  n_months_overlap = nrow(merged),
  pd18_5spec = specs,
  baseline_S4v2_5spec = specs_baseline,
  harvey_pass_count_pd18 = harvey_pass_count_pd18,
  harvey_pass_count_baseline = harvey_pass_count_baseline,
  harvey_threshold = 3.0,
  harvey_verdict = list(
    pd18_5_specs_pass_count = harvey_pass_count_pd18,
    pd18_strict_5_of_5 = harvey_pass_count_pd18 == 5,
    pd18_majority_3_of_5 = harvey_pass_count_pd18 >= 3,
    baseline_5_specs_pass_count = harvey_pass_count_baseline,
    baseline_strict_5_of_5 = harvey_pass_count_baseline == 5
  )
)

jsonlite::write_json(output, file.path(OUT_DIR, "judge_pd18_harvey_5spec_results.json"),
                     auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("\nSaved: judge_pd18_harvey_5spec_results.json\n")
cat("══════════════════════════════════════════════════════════════════\n")
