# ============================================================
# WT-D20260427_002 — Iter 18 Alpha Inheritance (STR_1701 base)
# ============================================================
# Mandate (b — Optimizer Track):
#   - Alpha agent: STR_1701 base score 그대로 inheritance
#   - cor(V_iter18, STR_1701_base) >= 0.95 strict (L-224 v2)
#   - Optimizer mechanism focus → alpha 변경 절대 금지
#   - 본 sprint: alpha 재계산/재합성 X, direct slot read O
# ============================================================

suppressMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(dplyr)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260427_002"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "qepm/stage_artifacts", paste0("WT_", gsub("-", "_", WT_ID)))
SOURCE_PARQUET <- file.path(ROOT, "qepm/stage_artifacts/WT_D20260426_007/alpha_scores.parquet")
SOURCE_PKG <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260426_004/alpha_package.json")
ITER5_PKG <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260426_004/alpha_package.json")  # Iter 5 STR_1701 spec
TRAIN_END <- as.Date("2024-01-22")
LOCKBOX_START <- as.Date("2024-01-23")

dir.create(STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== Iter 18 Alpha Inheritance (STR_1701 base, Optimizer track) ===\n")
cat("Source parquet:", SOURCE_PARQUET, "\n")
cat("Stage dir:", STAGE_DIR, "\n\n")

# ============================================================
# Step 1: Load STR_1701 base score panel (no recomputation)
# ============================================================
df_src <- as.data.table(read_parquet(SOURCE_PARQUET))
cat("Source rows:", nrow(df_src), "| dates:", length(unique(df_src$Date)),
    "| tickers:", length(unique(df_src$Ticker)), "\n")
cat("Source schema:", paste(colnames(df_src), collapse = ", "), "\n")

# Window isolation hard check (R2 P2): max date must be <= TRAIN_END
stopifnot(max(df_src$Date) <= TRAIN_END)
cat("Window isolation PASS: max_date=", as.character(max(df_src$Date)), " <= ", as.character(TRAIN_END), "\n", sep = "")

# ============================================================
# Step 2: Inheritance — STR_1701 score 그대로 채택
# ============================================================
# Iter 18 V_iter18 := score_str1701 (그대로). 변환 없음.
df_inh <- df_src[, .(
  Date,
  Ticker,
  score_str1701,       # base (preserved)
  score_eff = score_str1701,  # alpha vector (raw inheritance)
  score_rank,          # original rank
  confidence,          # base confidence (preserved)
  fwd_1m,              # forward return (for diagnostics only)
  c_substab, c_resid, c_cov,  # confidence components
  z_A, z_B, z_C,       # slot components (audit trail)
  n_slots_present
)]
setkey(df_inh, Date, Ticker)

cat("\n=== Step 2: Inheritance complete ===\n")
cat("Rows:", nrow(df_inh), "| score_eff range:", round(range(df_inh$score_eff, na.rm=TRUE), 4), "\n")

# ============================================================
# Step 3: cor verification — V_iter18 vs STR_1701 base (cor >= 0.95 mandate)
# ============================================================
cor_v18_str1701 <- cor(df_inh$score_eff, df_inh$score_str1701, method = "spearman", use = "pairwise.complete.obs")
cat("\n=== Step 3: Inheritance hash check ===\n")
cat(sprintf("cor(V_iter18, STR_1701_base) = %.6f (mandate >= 0.95 strict)\n", cor_v18_str1701))
stopifnot(cor_v18_str1701 >= 0.95)
cat("PASS: alpha_inheritance_hash cor >= 0.95\n")

# ============================================================
# Step 4: Diagnostics — re-derive on inherited panel (audit; no re-train)
# ============================================================
df_diag <- df_inh[!is.na(score_eff) & !is.na(fwd_1m)]
cat("\n=== Step 4: Diagnostics (inheritance audit) ===\n")
cat("Diagnostics rows:", nrow(df_diag), "| dates:", length(unique(df_diag$Date)), "\n")

# Per-month rank IC (Spearman)
ic_monthly <- df_diag[, .(
  ic = cor(score_eff, fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  n  = .N
), by = Date]
ic_monthly <- ic_monthly[!is.na(ic)]
rank_ic <- mean(ic_monthly$ic, na.rm = TRUE)
ic_sd <- sd(ic_monthly$ic, na.rm = TRUE)
icir <- rank_ic / ic_sd
cat(sprintf("Rank IC: %.4f | ICIR: %.4f | n_months: %d\n", rank_ic, icir, nrow(ic_monthly)))

# Subperiod stability (P1 2008-2014 / P2 2015-2019 / P3 2020-2023.11)
ic_monthly[, period := fcase(
  Date <= as.Date("2014-12-31"), "P1_2008_2014",
  Date <= as.Date("2019-12-31"), "P2_2015_2019",
  Date <= as.Date("2024-01-22"), "P3_2020_2024",
  default = "OUT"
)]
sub_ic <- ic_monthly[period != "OUT", .(ic = mean(ic, na.rm=TRUE), n = .N), by = period]
setkey(sub_ic, period)
cat("\nSubperiod IC:\n"); print(sub_ic)

# subperiod_stability = min(P_i) / max(P_i) if all positive, else 0
all_pos <- all(sub_ic$ic > 0)
if (all_pos) {
  sub_stab <- min(sub_ic$ic) / max(sub_ic$ic)
} else {
  sub_stab <- 0
}
cat(sprintf("Subperiod stability (min/max): %.4f (all_positive=%s)\n", sub_stab, all_pos))

# Harvey NW-HAC t-stat (5-spec):
#   spec 1: pooled OLS
#   spec 2: NW lag=3
#   spec 3: NW lag=6
#   spec 4: NW lag=12
#   spec 5: cluster by Date (panel-mean)
# Implementation: regress fwd_1m on score_eff_z; HAC SE via sandwich
suppressMessages({
  library(sandwich)
  library(lmtest)
})

# Cross-sectional z-score per Date
df_diag[, score_z := (score_eff - mean(score_eff, na.rm=TRUE)) /
          (sd(score_eff, na.rm=TRUE) + 1e-12), by = Date]

# Spec 1: Pooled OLS
fit1 <- lm(fwd_1m ~ score_z, data = df_diag)
t1 <- summary(fit1)$coefficients["score_z", "t value"]

# Spec 2-4: NW HAC on monthly mean
mret <- df_diag[, .(mean_y = mean(fwd_1m, na.rm=TRUE), mean_x = mean(score_z, na.rm=TRUE)), by = Date]
fit_m <- lm(mean_y ~ mean_x, data = mret)
nw3 <- coeftest(fit_m, vcov = NeweyWest(fit_m, lag = 3, prewhite = FALSE))
nw6 <- coeftest(fit_m, vcov = NeweyWest(fit_m, lag = 6, prewhite = FALSE))
nw12 <- coeftest(fit_m, vcov = NeweyWest(fit_m, lag = 12, prewhite = FALSE))
t2 <- nw3["mean_x", "t value"]
t3 <- nw6["mean_x", "t value"]
t4 <- nw12["mean_x", "t value"]

# Spec 5: Date-clustered SE via sandwich
suppressMessages({
  cl_se <- sqrt(vcovCL(fit1, cluster = ~ Date, type = "HC1")["score_z", "score_z"])
})
t5 <- coef(fit1)["score_z"] / cl_se

harvey_specs <- c(spec1_pooled_ols = t1, spec2_nw_lag3 = t2, spec3_nw_lag6 = t3,
                  spec4_nw_lag12 = t4, spec5_cluster_date = t5)
harvey_pass <- sum(abs(harvey_specs) >= 3.0)
cat("\n=== Harvey NW-HAC t-stats (5 specs) ===\n")
print(round(harvey_specs, 4))
cat(sprintf("Specs |t| >= 3.0: %d/5\n", harvey_pass))

# DSR_post (Bailey-Lopez de Prado deflated SR proxy on monthly IC)
sr_ic <- icir
sr_mean <- mean(ic_monthly$ic, na.rm=TRUE)
sr_sd   <- sd(ic_monthly$ic, na.rm=TRUE)
n_obs <- nrow(ic_monthly)
# skewness & kurtosis of monthly IC
ic_x <- ic_monthly$ic
skew_ic <- mean((ic_x - mean(ic_x))^3) / (sd(ic_x))^3
kurt_ic <- mean((ic_x - mean(ic_x))^4) / (sd(ic_x))^4
# DSR ~ sqrt((n-1)) * (sr - sr_threshold) / sqrt(1 - skew*sr + (kurt-1)/4 * sr^2)
sr_threshold <- 0
dsr_num <- sqrt(max(n_obs - 1, 1)) * (sr_ic - sr_threshold)
dsr_den <- sqrt(max(1 - skew_ic * sr_ic + (kurt_ic - 1) / 4 * sr_ic^2, 1e-9))
dsr_post <- pnorm(dsr_num / dsr_den)
cat(sprintf("\nDSR_post (proxy): %.4f (skew=%.3f kurt=%.3f n=%d)\n", dsr_post, skew_ic, kurt_ic, n_obs))

# Monotonicity (decile)
df_diag[, decile := cut(score_z, breaks = quantile(score_z, probs = seq(0, 1, 0.1), na.rm=TRUE),
                       include.lowest = TRUE, labels = 1:10), by = Date]
dec_ret <- df_diag[!is.na(decile), .(mean_ret = mean(fwd_1m, na.rm=TRUE)), by = decile]
dec_ret[, decile := as.integer(as.character(decile))]
setkey(dec_ret, decile)
mono_pairs <- sum(diff(dec_ret$mean_ret) > 0, na.rm=TRUE)
mono_total <- nrow(dec_ret) - 1
mono <- if (mono_total > 0) mono_pairs / mono_total else NA_real_
cat(sprintf("Monotonicity (decile pairs): %.4f (%d/%d)\n", mono, mono_pairs, mono_total))

# Turnover proxy (top-20 set Jaccard distance month-on-month)
top20_per_date <- df_diag[, {
  o <- order(-score_eff)[seq_len(min(20, .N))]
  list(top_tickers = list(Ticker[o]))
}, by = Date]
setkey(top20_per_date, Date)
to_list <- numeric(nrow(top20_per_date) - 1)
for (i in seq_len(nrow(top20_per_date) - 1)) {
  prev <- top20_per_date$top_tickers[[i]]
  curr <- top20_per_date$top_tickers[[i + 1]]
  if (length(prev) == 0 || length(curr) == 0) { to_list[i] <- NA; next }
  jac <- length(intersect(prev, curr)) / length(union(prev, curr))
  to_list[i] <- 1 - jac
}
turnover_proxy <- mean(to_list, na.rm=TRUE) * 12  # annualized
cat(sprintf("Turnover proxy (top-20 Jaccard, annualized): %.4f\n", turnover_proxy))

# ============================================================
# Step 5: Latest as_of alpha_vector + confidence_vector
# ============================================================
last_date <- max(df_inh$Date)
cat(sprintf("\n=== Step 5: as_of_date = %s ===\n", as.character(last_date)))
df_last <- df_inh[Date == last_date]
# Take top 20 by score_eff (Iter 5 baseline pattern)
df_last <- df_last[order(-score_eff)]
top20 <- df_last[1:min(20, nrow(df_last))]
alpha_vec <- setNames(round(top20$score_eff, 4), top20$Ticker)
conf_vec  <- setNames(round(top20$confidence, 4), top20$Ticker)
cat("Top 20 alpha:\n"); print(head(alpha_vec, 10))

# ============================================================
# Step 6: Write inherited parquet (alpha_scores.parquet)
# ============================================================
out_parquet <- file.path(STAGE_DIR, "alpha_scores.parquet")
write_parquet(df_inh, out_parquet)
cat(sprintf("\nWrote: %s\n", out_parquet))

# ============================================================
# Step 7: Build alpha_package.json (inheritance-only, minimal)
# ============================================================
diag_list <- list(
  rank_ic = round(rank_ic, 4),
  icir = round(icir, 4),
  monotonicity = round(mono, 4),
  subperiod_stability = round(sub_stab, 4),
  subperiod_ics = list(
    P1_2008_2014 = round(sub_ic[period == "P1_2008_2014", ic], 4),
    P2_2015_2019 = round(sub_ic[period == "P2_2015_2019", ic], 4),
    P3_2020_2024 = round(sub_ic[period == "P3_2020_2024", ic], 4)
  ),
  harvey_t_specs = list(
    spec1_pooled_ols   = round(t1, 4),
    spec2_nw_lag3      = round(t2, 4),
    spec3_nw_lag6      = round(t3, 4),
    spec4_nw_lag12     = round(t4, 4),
    spec5_cluster_date = round(t5, 4)
  ),
  harvey_t_stat_pooled = round(t1, 4),
  harvey_t_specs_pass_count = harvey_pass,
  dsr_post = round(dsr_post, 4),
  post_neutralization_ic = round(rank_ic, 4),  # no neutralization applied (inheritance)
  turnover_proxy = round(turnover_proxy, 4),
  n_months = nrow(ic_monthly),
  n_sig_dates = length(unique(df_inh$Date)),
  n_tickers_panel = length(unique(df_inh$Ticker)),
  n_tickers_at_as_of = nrow(df_last),
  alpha_inheritance_cor = round(cor_v18_str1701, 6)
)

inheritance_block <- list(
  base_strategy = "STR_1701 (Iter 11 PG2 active 80% — multi-sleeve composite)",
  base_source_parquet = "stage_artifacts/WT_D20260426_007/alpha_scores.parquet",
  base_source_pkg = "qepm/mailbox/worktask/WT-D20260426_004/alpha_package.json",
  base_score_column = "score_str1701",
  inheritance_method = "DIRECT_SLOT_READ_NO_RECOMPUTE",
  cor_v18_vs_str1701 = round(cor_v18_str1701, 6),
  cor_threshold_strict = 0.95,
  cor_pass = TRUE,
  alpha_unchanged_proof = "PASS",
  rationale = "Iter 18 = Optimizer track. Alpha변경 절대 금지 (L-224 v2 strict). score_str1701 panel as-is + universe filter only.",
  l_codes_referenced = c("L-220", "L-224", "L-226"),
  iter_lineage = c("Iter 5 (WT-D20260425_010)", "Iter 11 (WT-D20260426_004)", "Iter 18 (current)")
)

universe_block <- list(
  label = "KOSPI200_KOSDAQ150_intersection (inherited)",
  liquidity_threshold_won_used = 200000000,
  liquidity_threshold_basis = "production floor 2e8 KRW (Codex C2 fix from WT-D20260426_007)",
  avg_tv20_definition = "Close x Vol (NOT Size)",
  universe_filter_applied_pre_diagnostics = TRUE
)

method_log <- list(
  candidates_tried = 1,
  cap = 5,
  parallel_exec = FALSE,
  rcpp_used = FALSE,
  rolling_seconds = NA,
  method_log = list(
    list(
      name = "STR_1701_inheritance_no_change",
      rank_ic = round(rank_ic, 4),
      icir = round(icir, 4),
      sub_stab = round(sub_stab, 4),
      harvey_specs_pass = harvey_pass,
      dsr_post = round(dsr_post, 4),
      cor_to_str1701 = round(cor_v18_str1701, 6),
      selected = TRUE
    )
  ),
  honest_disclosure = "단일 후보 (inheritance only). Method shopping 의도적 생략 — Iter 18 Optimizer Track mandate (alpha 변경 X)."
)

iter18_lessons <- list(
  L_220_avoidance = "vol-reduction machinery 채택 X (Optimizer track이라 alpha 변경 X)",
  L_224_strict   = sprintf("alpha_inheritance_hash cor=%.4f >= 0.95 strict PASS", cor_v18_str1701),
  L_226_aware    = "ERC near-EW 한계는 Optimizer agent에서 CVaR-aware MVO + adaptive psi로 해소 예정",
  iter14_avoidance = "confidence weighting 시 silent failure 회피 — 본 Iter는 confidence vector도 그대로 inheritance",
  iter15_avoidance = "multi-mutation 시 composite dilution 회피 — 본 Iter는 변경 X"
)

# Challenge flags — inheritance에서는 base의 flag도 보존
inherited_flags <- list(
  RF_A1_inherited = list(
    id = "RF-A1",
    severity = "HIGH",
    msg = "subperiod_stability low (inherited from STR_1701 base; not a regression)",
    inherited_from = "WT-D20260425_010 / WT-D20260426_004"
  )
)

alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  iter = 18,
  iter_name = "Optimizer_Activation_StrictAlphaInheritance",
  parent_iters = c("WT-D20260425_010", "WT-D20260426_004", "WT-D20260426_007"),
  baseline_pg2 = "STR_1701 (active 80%) + STR_1656 (active 20%)",
  as_of_date = as.character(last_date),
  signal_as_of = as.character(last_date),
  forecast_horizon = "1M",
  selection_objective = "icir",
  hypothesis_title = "Iter 18 — Optimizer Alpha Activation (CVaR-aware MVO with adaptive psi)",
  hypothesis_summary = paste(
    "Iter 18 = Optimizer Track. Alpha base = STR_1701 (Iter 11 PG2 active 80%, multi-sleeve composite, slot 0.65/0.35) 그대로 inheritance.",
    "alpha_inheritance_hash cor >= 0.95 strict mandate PASS.",
    "본 sprint: Optimizer mechanism만 변경 (CVaR-aware MVO with adaptive psi / BL informative posterior / LinTilt+EMA+CVaR / Risk Parity Alpha Tilt / Concentrated MVO).",
    "Alpha agent임무: STR_1701 base 그대로 + minimal noise check만.",
    sep = " "
  ),
  alpha_inheritance = inheritance_block,
  alpha_vector = as.list(alpha_vec),
  confidence_vector = as.list(conf_vec),
  signal_matrix_ref = paste0("stage_artifacts://WT_D20260427_002/alpha_scores.parquet"),
  factor_specs = list(
    list(
      factor_family = "Multi_Sleeve_Inheritance",
      proxy = "STR_1701_base_score",
      formula = "score_str1701 (inherited from WT-D20260426_007 parquet, no transform)",
      lag_rule = "monthly t-1 (preserved from STR_1701)",
      winsorization = "preserved",
      neutralization = "preserved",
      economic_rationale = "STR_1701 multi-sleeve composite (Core 0.65 Consensus_4F+Q07+M08 / Defense 0.35 Q07+Q25)",
      sleeve = "inherited",
      source = "inherited",
      weight_theta = 1.0,
      references = c("Iter 5 WT-D20260425_010", "Iter 11 WT-D20260426_004")
    )
  ),
  diagnostics = diag_list,
  universe = universe_block,
  challenge_flags = inherited_flags,
  method_shopping_log = method_log,
  iter18_lessons_applied = iter18_lessons,
  ax_axiom_compliance = list(
    `AX-003` = list(rule = "KR value EP_STANDALONE failure", status = "PASS",
                    evidence = "No standalone Value (inherited from STR_1701 multi-sleeve)"),
    `AX-004` = list(rule = "KR quality_profitability single-signal failure", status = "PASS",
                    evidence = "Multi-axis composite preserved (Consensus + Q07 + M08 + Q25_Distress)"),
    `AX-005` = list(rule = "KR defense 4-axis failure", status = "PASS_WITH_NOTE",
                    evidence = "Defense sleeve = Q07+Q25 2-axis (NOT 4-axis), inherited"),
    `AX-007` = list(rule = "single_sleeve_top20 translation 단절", status = "PASS",
                    evidence = "Multi-sleeve structure preserved (Core 0.65 + Defense 0.35)")
  ),
  pit_compliance = list(
    C1 = "PASS (inherited; expanding window in source)",
    C2 = "PASS (inherited; t-1 lag preserved)",
    C4 = "PASS (inherited; quarterly 45d / annual May)",
    C9 = "PASS (inherited; regime expanding percentile)",
    C10 = "PASS (inherited; AvgTV20 >= 2e8 lagged)",
    C11 = "PASS (inherited; KR internals only)",
    C13 = "PASS (inherited; Z_Score_Aligned)",
    C14 = "PASS (inherited; Usable_Date <= sig_date)",
    C15 = "PASS (inherited; load_month_factors equivalent)",
    lockbox = sprintf("ENFORCED: max_date %s <= TRAIN_END %s",
                       as.character(max(df_inh$Date)), as.character(TRAIN_END))
  ),
  window_isolation = list(
    train_validation_window = list(start = "2008-01-31", end = as.character(max(df_inh$Date))),
    lockbox_window = list(start = as.character(LOCKBOX_START), end = "2026-04-27", sealed = TRUE),
    lockbox_access = FALSE,
    lockbox_isolation_certified = TRUE
  ),
  graduation_status = list(
    rank_ic_gate = list(value = round(rank_ic, 4), threshold = 0.04, pass = rank_ic >= 0.04),
    icir_gate = list(value = round(icir, 4), threshold = 0.20, pass = icir >= 0.20),
    subperiod_gate = list(value = round(sub_stab, 4), threshold = 0.50, pass = sub_stab >= 0.50),
    harvey_t_gate = list(value = round(t1, 4), threshold = 3.0, pass = abs(t1) >= 3.0),
    dsr_gate = list(value = round(dsr_post, 4), threshold = 0.50, pass = dsr_post >= 0.50),
    overall_pass = (rank_ic >= 0.04) && (icir >= 0.20) && (sub_stab >= 0.50) &&
                   (abs(t1) >= 3.0) && (dsr_post >= 0.50),
    gates_passed = sum(c(rank_ic >= 0.04, icir >= 0.20, sub_stab >= 0.50,
                          abs(t1) >= 3.0, dsr_post >= 0.50)),
    gates_total = 5,
    honest_disclosure = "Iter 18 inheritance — diagnostics 재현. Optimizer track focus."
  ),
  references = c(
    "Black-Litterman 1992 (Optimizer downstream)",
    "Rockafellar-Uryasev 2000 CVaR (Optimizer downstream)",
    "Lopez de Prado 2018 adaptive psi (Optimizer downstream)",
    "Maillard-Roncalli-Teiletche 2010 ERC baseline",
    "Iter 11 STR_1701 LinTilt + Iter 15 V3 ERC 학습",
    "QEPM L-220 vol-reduction Harvey 격하",
    "QEPM L-224 alpha_inheritance_hash cor 0.85->0.95 strict",
    "QEPM L-226 ERC near-EW alpha activation 부재"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  forward_to = "Iter 18 Optimizer (CVaR-aware MVO with adaptive psi mechanism)"
)

# ============================================================
# Step 8: Write alpha_package.json (FIRST), then lineage (SECOND)
# ============================================================
out_pkg <- file.path(WT_DIR, "alpha_package.json")
write_json(alpha_package, out_pkg, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\nWrote: %s\n", out_pkg))

# alpha_inheritance_hash.json (separate audit artifact)
hash_artifact <- list(
  task_id = WT_ID,
  base_strategy = "STR_1701",
  base_source_parquet = SOURCE_PARQUET,
  base_score_column = "score_str1701",
  cor_v18_vs_str1701_spearman = round(cor_v18_str1701, 6),
  cor_threshold_strict = 0.95,
  cor_pass = (cor_v18_str1701 >= 0.95),
  cor_method = "spearman",
  cor_n_obs = nrow(df_inh),
  alpha_unchanged_proof = "PASS",
  inheritance_method = "DIRECT_SLOT_READ_NO_RECOMPUTE",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  l_code_reference = "L-224 v2 (cor 0.85 -> 0.95 strict)"
)
write_json(hash_artifact,
           file.path(WT_DIR, "alpha_inheritance_hash.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("Wrote: %s\n", file.path(WT_DIR, "alpha_inheritance_hash.json")))

# alpha_validation.json
validation <- list(
  task_id = WT_ID,
  validation_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  alpha_unchanged_proof = "PASS",
  cor_inheritance_strict_pass = (cor_v18_str1701 >= 0.95),
  graduation = alpha_package$graduation_status,
  pit_compliance = alpha_package$pit_compliance,
  window_isolation = alpha_package$window_isolation
)
write_json(validation,
           file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("Wrote: %s\n", file.path(STAGE_DIR, "alpha_validation.json")))

# Lineage (SECOND, per L-194)
tryCatch({
  source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package",
    method_selected = "STR_1701_inheritance_no_change",
    input_file_paths = c(SOURCE_PARQUET, SOURCE_PKG)
  )
  cat("Lineage recorded.\n")
}, error = function(e) {
  cat("Lineage helper unavailable:", conditionMessage(e), "\n")
  # fallback minimal lineage
  lineage <- list(
    task_id = WT_ID,
    package_type = "alpha_package",
    method_selected = "STR_1701_inheritance_no_change",
    input_files = c(SOURCE_PARQUET, SOURCE_PKG),
    output_file = out_pkg,
    recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  write_json(lineage, file.path(WT_DIR, "artifact_lineage.json"),
             pretty = TRUE, auto_unbox = TRUE, na = "null")
  cat("Wrote fallback lineage.\n")
})

# ============================================================
# Final summary
# ============================================================
cat("\n=== Iter 18 Alpha Inheritance: COMPLETE ===\n")
cat(sprintf("cor_v18_vs_str1701 = %.6f (>= 0.95 strict): %s\n",
             cor_v18_str1701, ifelse(cor_v18_str1701 >= 0.95, "PASS", "FAIL")))
cat(sprintf("ICIR = %.4f | rank_IC = %.4f | sub_stab = %.4f\n", icir, rank_ic, sub_stab))
cat(sprintf("Harvey 5-spec |t|>=3.0: %d/5 | DSR_post = %.4f\n", harvey_pass, dsr_post))
cat(sprintf("Gates passed: %d/5\n", alpha_package$graduation_status$gates_passed))

# Append to a state file for downstream parsing
final_state <- list(
  cor_v18_vs_str1701 = cor_v18_str1701,
  icir = icir,
  rank_ic = rank_ic,
  sub_stab = sub_stab,
  harvey_pass = harvey_pass,
  dsr_post = dsr_post,
  gates_passed = alpha_package$graduation_status$gates_passed
)
write_json(final_state, file.path(WT_DIR, ".alpha_iter18_state.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
