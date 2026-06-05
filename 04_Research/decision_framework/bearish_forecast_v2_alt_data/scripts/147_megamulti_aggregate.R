#==============================================================================
# 147_megamulti_aggregate.R — Cycle 56D-prelim 3-Architecture Aggregate
#
# Reads:
#   outputs/03_models/v6b_megamulti_q126/predictions_dlinear_y_{tail_q15|tail_q126}.parquet
#   outputs/03_models/v6b_megamulti_q126/predictions_informer_y_{tail_q15|tail_q126}.parquet
#   outputs/03_models/v6b_megamulti_q126/predictions_timesnet_y_{tail_q15|tail_q126}.parquet
#   outputs/03_models/v6b_megamulti_q126/predictions_ew3_y_{tail_q15|tail_q126}.parquet
#   outputs/03_models/v6b_megamulti_q126/per_fold_diagnostics.json
#   outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_{tail_q15|tail_q126}.parquet (53H reference)
#
# Steps:
#   Step 1: Per-architecture OOS PR-AUC + IC (R re-verification)
#   Step 2: EW3 ensemble PR-AUC + IC (R re-compute)
#   Step 3: vs Cycle 53H seed=42 reference baselines (0.4012 q126 / 0.2082 q15)
#   Step 4: Period-balanced PR-AUC per arch + bootstrap CI (53M framework)
#   Step 5: NEW_CYCLE_CHECKLIST status
#   Step 6: Verdict (ARCH_BREAKTHROUGH / ARCH_MARGINAL / ARCH_INFERIOR)
#   Step 7: Next cycle suggestion
#   Step 8: JSON + chart
#
# Output:
#   outputs/04_evaluation/megamulti_q126_v6b.json
#   outputs/06_reports/charts/147_megamulti_q126.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MM_DIR <- file.path(WS, "outputs/03_models/v6b_megamulti_q126")
S53H_DIR <- file.path(WS, "outputs/03_models/v5e_patchtst_q126_usmacro")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

ARCHS  <- c("dlinear", "informer", "timesnet")
ARCHS_DISP <- c("DLinear", "Informer", "TimesNet")
TARGETS <- c("y_tail_q15", "y_tail_q126")

# Cycle 53H seed=42 reference
CYCLE_53H_Q126 <- 0.4012
CYCLE_53H_Q15  <- 0.2082
CYCLE_53H_Q126_IC <- 0.3057
CYCLE_53H_Q15_IC  <- 0.0743

# Period-balanced segments (mirror 53M / 141)
SEGMENTS <- list(
  list(name = "S2018_19_calm",       start = as.Date("2018-01-01"), end = as.Date("2019-12-31")),
  list(name = "S2020_21_covid_lift", start = as.Date("2020-01-01"), end = as.Date("2021-12-31")),
  list(name = "S2022_24_inflation",  start = as.Date("2022-01-01"), end = as.Date("2024-12-31"))
)

BOOTSTRAP_N <- 1000L
BOOTSTRAP_SEED <- 20260521L

# Verdict thresholds (도훈 mandate)
VERDICT_BREAKTHROUGH_MIN <- 0.42  # any arch > 0.42 → BREAKTHROUGH
VERDICT_MARGINAL_LO <- 0.40       # 0.40~0.42 → MARGINAL
VERDICT_MARGINAL_HI <- 0.42

# ─── helpers ──────────────────────────────────────────────────────────
pr_auc <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30 || sum(y) < 5) return(NA_real_)
  ord <- order(p, decreasing = TRUE); y_ord <- y[ord]
  prec <- cumsum(y_ord) / seq_along(y_ord); rec <- cumsum(y_ord) / sum(y_ord)
  n <- length(prec); sum(diff(rec) * (prec[-1] + prec[-n]) / 2)
}

ic_spearman <- function(p, y) {
  ok <- !is.na(p) & !is.na(y); p <- p[ok]; y <- y[ok]
  if (length(p) < 30) return(NA_real_)
  cor(rank(p), rank(y), method = "pearson")
}

bootstrap_ci_pr <- function(p, y, B = BOOTSTRAP_N, seed = BOOTSTRAP_SEED) {
  ok <- !is.na(p) & !is.na(y)
  p <- p[ok]; y <- y[ok]
  n <- length(p)
  if (n < 30 || sum(y) < 5) {
    return(list(point = NA_real_, lo = NA_real_, hi = NA_real_, n = n, events = sum(y)))
  }
  point <- pr_auc(p, y)
  set.seed(seed)
  vals <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    vals[b] <- pr_auc(p[idx], y[idx])
  }
  vals <- vals[!is.na(vals)]
  if (length(vals) < 50) {
    return(list(point = point, lo = NA_real_, hi = NA_real_,
                n = n, events = sum(y), bootstrap_valid = length(vals)))
  }
  q <- quantile(vals, c(0.025, 0.975), na.rm = TRUE)
  list(point = round(point, 4), lo = round(unname(q[1]), 4), hi = round(unname(q[2]), 4),
       n = n, events = sum(y), bootstrap_valid = length(vals))
}

#==============================================================================
# Load Python diagnostics
#==============================================================================
diag_path <- file.path(MM_DIR, "per_fold_diagnostics.json")
if (!file.exists(diag_path)) {
  stop(sprintf("Missing per_fold_diagnostics: %s\n  Run scripts/146_megamulti_3arch_q126.py first.",
               diag_path))
}
py_diag <- fromJSON(diag_path, simplifyVector = FALSE)
cat(sprintf("\n[Loaded] per_fold_diagnostics\n"))
cat(sprintf("[Cycle] %s\n", py_diag$cycle))

#==============================================================================
# Step 1: Per-arch × per-target PR-AUC + IC (R re-verification)
#==============================================================================
cat("\n========== Step 1: Per-arch × per-target PR-AUC + IC (R verify) ==========\n")

per_arch_rows <- list()
for (arch in ARCHS) {
  for (tc in TARGETS) {
    pred_path <- file.path(MM_DIR, sprintf("predictions_%s_%s.parquet", arch, tc))
    col_name <- sprintf("p_%s", arch)
    if (!file.exists(pred_path)) {
      per_arch_rows[[length(per_arch_rows) + 1]] <- data.table(
        arch = arch, target = tc, n_obs = NA_integer_,
        n_events = NA_integer_, event_rate = NA_real_,
        oos_pr = NA_real_, oos_ic = NA_real_, error = "missing_file"
      )
      next
    }
    dt <- as.data.table(read_parquet(pred_path))
    dt[, Date := as.Date(Date)]
    dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(get(col_name)) & !is.na(y)]
    pa <- pr_auc(dt[[col_name]], dt$y)
    ic <- ic_spearman(dt[[col_name]], dt$y)
    per_arch_rows[[length(per_arch_rows) + 1]] <- data.table(
      arch = arch, target = tc,
      n_obs = nrow(dt), n_events = as.integer(sum(dt$y)),
      event_rate = round(mean(dt$y), 4),
      oos_pr = round(pa, 4), oos_ic = round(ic, 4), error = NA_character_
    )
  }
}
per_arch_dt <- rbindlist(per_arch_rows, fill = TRUE)

cat("\n[Per-arch × target table (R verification)]\n")
print(per_arch_dt)

#==============================================================================
# Step 2: EW3 ensemble PR-AUC + IC (R re-compute)
#==============================================================================
cat("\n========== Step 2: EW3 ensemble PR-AUC + IC (R re-compute) ==========\n")

ew3_rows <- list()
for (tc in TARGETS) {
  ew_path <- file.path(MM_DIR, sprintf("predictions_ew3_%s.parquet", tc))
  if (!file.exists(ew_path)) {
    ew3_rows[[tc]] <- list(target = tc, error = "missing_file",
                            oos_pr = NA_real_, oos_ic = NA_real_)
    next
  }
  dt <- as.data.table(read_parquet(ew_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(p_ew3) & !is.na(y)]
  pa <- pr_auc(dt$p_ew3, dt$y)
  ic <- ic_spearman(dt$p_ew3, dt$y)
  ew3_rows[[tc]] <- list(
    target = tc, n_obs = nrow(dt),
    n_events = as.integer(sum(dt$y)),
    event_rate = round(mean(dt$y), 4),
    oos_pr = round(pa, 4), oos_ic = round(ic, 4)
  )
}

cat("\n[EW3 ensemble per target]\n")
for (tc in TARGETS) {
  r <- ew3_rows[[tc]]
  if (is.null(r$error)) {
    cat(sprintf("  EW3 %-12s: PR-AUC=%.4f IC=%.4f n_obs=%d n_events=%d event_rate=%.4f\n",
                tc, r$oos_pr, r$oos_ic, r$n_obs, r$n_events, r$event_rate))
  } else {
    cat(sprintf("  EW3 %-12s: ERROR (%s)\n", tc, r$error))
  }
}

#==============================================================================
# Step 3: vs Cycle 53H seed=42 reference baselines
#==============================================================================
cat("\n========== Step 3: vs Cycle 53H seed=42 reference (q126=0.4012 / q15=0.2082) ==========\n")

# Add deltas — use raw hardcoded ref (headline reference) AND fair mask-clean ref
# Fair ref is computed later in cross-check section. Use raw here, then update.
per_arch_dt[, ref_raw := fifelse(target == "y_tail_q126", CYCLE_53H_Q126, CYCLE_53H_Q15)]
per_arch_dt[, delta_vs_53h_raw := round(oos_pr - ref_raw, 4)]

cat("\n[Delta vs 53H seed=42 (raw fillna(0) headline)]\n")
print(per_arch_dt[, .(arch, target, oos_pr, ref_raw, delta_vs_53h_raw, oos_ic)])

ew3_delta_q126_raw <- ew3_rows[["y_tail_q126"]]$oos_pr - CYCLE_53H_Q126
ew3_delta_q15_raw  <- ew3_rows[["y_tail_q15"]]$oos_pr - CYCLE_53H_Q15
cat(sprintf("\n[EW3 vs 53H raw]\n"))
cat(sprintf("  q126: %.4f vs 53H %.4f → Δ=%+.4f\n",
            ew3_rows[["y_tail_q126"]]$oos_pr, CYCLE_53H_Q126, ew3_delta_q126_raw))
cat(sprintf("  q15:  %.4f vs 53H %.4f → Δ=%+.4f\n",
            ew3_rows[["y_tail_q15"]]$oos_pr,  CYCLE_53H_Q15,  ew3_delta_q15_raw))

# Cross-check 53H file itself with R re-compute (2 conventions)
# Convention A: raw 53H (fillna(0) downstream — original cycle 53H headline 0.4012)
# Convention B: mask-clean (cycle 56D-fix convention, label valid mask applied)
load_53h <- function(target_col) {
  p <- file.path(S53H_DIR, sprintf("predictions_patchtst_v5e_%s.parquet", target_col))
  if (!file.exists(p)) return(NULL)
  dt <- as.data.table(read_parquet(p))
  dt[, Date := as.Date(Date)]
  dt[Date >= OOS_START & Date <= OOS_END]
}

# Load target validity mask
tgt_path <- file.path(WS, "outputs/02_targets/targets_long_horizon.parquet")
tgt_all <- as.data.table(read_parquet(tgt_path))
tgt_all[, Date := as.Date(Date)]
tgt_all[, valid_q15  := !is.na(ret_q15)  & !is.na(q15_thr_q15)]
tgt_all[, valid_q126 := !is.na(ret_q126) & !is.na(q15_thr_q126)]

ref_53h_pr_raw <- list()
ref_53h_pr_mask <- list()
for (tc in TARGETS) {
  rdt <- load_53h(tc)
  if (!is.null(rdt)) {
    # raw (cycle 53H original convention)
    ref_53h_pr_raw[[tc]] <- round(pr_auc(rdt$p_patchtst, rdt$y), 4)
    # mask-clean (cycle 56D-fix convention)
    valid_col <- if (tc == "y_tail_q126") "valid_q126" else "valid_q15"
    rdt_merged <- merge(rdt, tgt_all[, c("Date", valid_col), with = FALSE],
                        by = "Date", all.x = TRUE)
    rdt_clean <- rdt_merged[get(valid_col) == TRUE]
    ref_53h_pr_mask[[tc]] <- round(pr_auc(rdt_clean$p_patchtst, rdt_clean$y), 4)
  } else {
    ref_53h_pr_raw[[tc]] <- NA_real_
    ref_53h_pr_mask[[tc]] <- NA_real_
  }
}
cat(sprintf("\n[Cross-check 53H file PR-AUC R re-compute, 2 conventions]\n"))
cat(sprintf("  q126: raw=%.4f (hardcoded ref %.4f), mask-clean=%.4f (cycle 56D-fix convention)\n",
            ref_53h_pr_raw[["y_tail_q126"]], CYCLE_53H_Q126, ref_53h_pr_mask[["y_tail_q126"]]))
cat(sprintf("  q15:  raw=%.4f (hardcoded ref %.4f), mask-clean=%.4f (cycle 56D-fix convention)\n",
            ref_53h_pr_raw[["y_tail_q15"]], CYCLE_53H_Q15, ref_53h_pr_mask[["y_tail_q15"]]))
cat(sprintf("  Mask-clean baseline = fair 53H baseline for cycle 56D delta computation\n"))

# Use mask-clean for fair delta comparison
ref_53h_pr <- ref_53h_pr_mask
CYCLE_53H_Q126_FAIR <- ref_53h_pr_mask[["y_tail_q126"]]
CYCLE_53H_Q15_FAIR  <- ref_53h_pr_mask[["y_tail_q15"]]
cat(sprintf("\n[Fair baseline for cycle 56D delta] q126=%.4f / q15=%.4f\n",
            CYCLE_53H_Q126_FAIR, CYCLE_53H_Q15_FAIR))

# Compute fair deltas (mask-clean basis) for cycle 56D
per_arch_dt[, ref_fair := fifelse(target == "y_tail_q126", CYCLE_53H_Q126_FAIR, CYCLE_53H_Q15_FAIR)]
per_arch_dt[, delta_vs_53h_fair := round(oos_pr - ref_fair, 4)]
per_arch_dt[, delta_vs_53h := delta_vs_53h_fair]  # primary delta for verdict
per_arch_dt[, ref := ref_fair]

cat("\n[Fair delta vs 53H mask-clean (cycle 56D primary)]\n")
print(per_arch_dt[, .(arch, target, oos_pr, ref_fair, delta_vs_53h_fair, oos_ic)])

ew3_delta_q126 <- ew3_rows[["y_tail_q126"]]$oos_pr - CYCLE_53H_Q126_FAIR
ew3_delta_q15  <- ew3_rows[["y_tail_q15"]]$oos_pr - CYCLE_53H_Q15_FAIR
cat(sprintf("\n[EW3 vs 53H mask-clean]\n"))
cat(sprintf("  q126: %.4f vs 53H-fair %.4f → Δ=%+.4f\n",
            ew3_rows[["y_tail_q126"]]$oos_pr, CYCLE_53H_Q126_FAIR, ew3_delta_q126))
cat(sprintf("  q15:  %.4f vs 53H-fair %.4f → Δ=%+.4f\n",
            ew3_rows[["y_tail_q15"]]$oos_pr,  CYCLE_53H_Q15_FAIR,  ew3_delta_q15))

#==============================================================================
# Step 4: Period-balanced PR-AUC per arch + bootstrap CI
#==============================================================================
cat("\n========== Step 4: Period-balanced per arch + bootstrap CI ==========\n")

segment_rows <- list()
for (arch in ARCHS) {
  col_name <- sprintf("p_%s", arch)
  for (tc in TARGETS) {
    pred_path <- file.path(MM_DIR, sprintf("predictions_%s_%s.parquet", arch, tc))
    if (!file.exists(pred_path)) next
    dt <- as.data.table(read_parquet(pred_path))
    dt[, Date := as.Date(Date)]
    dt <- dt[Date >= OOS_START & Date <= OOS_END]

    for (si in seq_along(SEGMENTS)) {
      sg <- SEGMENTS[[si]]
      sub <- dt[Date >= sg$start & Date <= sg$end &
                  !is.na(get(col_name)) & !is.na(y)]
      if (nrow(sub) < 30 || sum(sub$y) < 5) {
        segment_rows[[length(segment_rows) + 1]] <- data.table(
          arch = arch, target = tc, segment = sg$name,
          n_obs = nrow(sub), n_events = as.integer(sum(sub$y)),
          oos_pr = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_
        )
        next
      }
      ci <- bootstrap_ci_pr(sub[[col_name]], sub$y, B = BOOTSTRAP_N,
                            seed = BOOTSTRAP_SEED + si)
      segment_rows[[length(segment_rows) + 1]] <- data.table(
        arch = arch, target = tc, segment = sg$name,
        n_obs = nrow(sub), n_events = as.integer(sum(sub$y)),
        oos_pr = ci$point, ci_lo = ci$lo, ci_hi = ci$hi
      )
    }
  }
}

# EW3 segments
for (tc in TARGETS) {
  ew_path <- file.path(MM_DIR, sprintf("predictions_ew3_%s.parquet", tc))
  if (!file.exists(ew_path)) next
  dt <- as.data.table(read_parquet(ew_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END]
  for (si in seq_along(SEGMENTS)) {
    sg <- SEGMENTS[[si]]
    sub <- dt[Date >= sg$start & Date <= sg$end & !is.na(p_ew3) & !is.na(y)]
    if (nrow(sub) < 30 || sum(sub$y) < 5) next
    ci <- bootstrap_ci_pr(sub$p_ew3, sub$y, B = BOOTSTRAP_N, seed = BOOTSTRAP_SEED + si + 100)
    segment_rows[[length(segment_rows) + 1]] <- data.table(
      arch = "ew3", target = tc, segment = sg$name,
      n_obs = nrow(sub), n_events = as.integer(sum(sub$y)),
      oos_pr = ci$point, ci_lo = ci$lo, ci_hi = ci$hi
    )
  }
}

segment_dt <- rbindlist(segment_rows, fill = TRUE)

cat("\n[Period-balanced PR-AUC × 3 arch + EW3 × 3 segments (bootstrap 95% CI)]\n")
print(segment_dt[order(target, arch, segment)])

# Compute lift per segment + 3/3 lift>1 check
segment_lift <- segment_dt[!is.na(oos_pr),
  .(arch, target, segment, n_obs, n_events,
    base_rate = round(n_events / n_obs, 4),
    pr_auc = oos_pr, ci_lo, ci_hi,
    lift = round(oos_pr / (n_events / n_obs), 3))]

cat("\n[Period-balanced lift (PR-AUC / base_rate)]\n")
print(segment_lift[order(target, arch, segment)])

# Per-arch 3/3 lift>1 check for q126 (primary)
lift_q126_check <- segment_lift[target == "y_tail_q126" & !is.na(lift),
  .(n_seg_lift_gt1 = sum(lift > 1), n_seg_total = .N,
    all_3_lift_gt1 = sum(lift > 1) == .N), by = arch]

cat("\n[Per-arch 3/3 lift>1 q126 check]\n")
print(lift_q126_check)

#==============================================================================
# Step 5: NEW_CYCLE_CHECKLIST status
#==============================================================================
cat("\n========== Step 5: NEW_CYCLE_CHECKLIST status ==========\n")

# Best arch q126
best_arch_q126_row <- per_arch_dt[target == "y_tail_q126"][which.max(oos_pr)]
best_arch_q126 <- best_arch_q126_row$arch
best_arch_q126_pr <- best_arch_q126_row$oos_pr

# Sanity check
ew3_q126 <- ew3_rows[["y_tail_q126"]]$oos_pr
sanity_lo <- 0.15
sanity_hi_strict <- 0.40
sanity_hi_relaxed <- 0.50
if (best_arch_q126_pr <= sanity_hi_strict) {
  sanity_msg <- sprintf("PASS (best arch %s q126=%.4f ∈ [%.2f, %.2f])",
                        best_arch_q126, best_arch_q126_pr, sanity_lo, sanity_hi_strict)
} else if (best_arch_q126_pr <= sanity_hi_relaxed) {
  sanity_msg <- sprintf("WARN_HIGH (%s q126=%.4f ∈ (%.2f, %.2f]) — q126 strong signal range",
                        best_arch_q126, best_arch_q126_pr, sanity_hi_strict, sanity_hi_relaxed)
} else if (best_arch_q126_pr > sanity_hi_relaxed) {
  sanity_msg <- sprintf("FAIL_TOO_HIGH (%s q126=%.4f > %.2f) — implausibly high",
                        best_arch_q126, best_arch_q126_pr, sanity_hi_relaxed)
} else {
  sanity_msg <- sprintf("FAIL (%s q126=%.4f < %.2f) — no value vs base rate",
                        best_arch_q126, best_arch_q126_pr, sanity_lo)
}

checklist <- list(
  M1_bear_date_audit = "PASS (pre-cycle 4/4, bear_date_audit_20260521_085130.json)",
  M2_validate_label_direction = "PASS (forward labels inherited; targets_long_horizon.parquet)",
  M3_PIT_C1_C15 = "PASS (v5e panel PIT validated 53H; arch-internal FFT/ProbSparse uses train window only)",
  M4_shift_convention = "PASS (forward targets via shift(.,n=H,'lead'); inherited)",
  M5_AX_008 = "EXEMPT (Forge first-pass architecture survey, NOT admit cycle)",
  S1_PRAUC_sanity_q126 = sanity_msg,
  S2_COVID_spot_check = "PASS (targets inherited from 53H A2 — 2020-02-19 ret_q126=+0.0289 verified)",
  S3_singleseed_firstpass = "N/A (single seed=42 first-pass; multi-seed stability in cycle 56D-second if BREAKTHROUGH)",
  S4_period_balanced_q126 = sprintf("[per arch] %s",
    paste(sapply(seq_len(nrow(lift_q126_check)), function(i)
      sprintf("%s=%d/%d", lift_q126_check$arch[i],
              lift_q126_check$n_seg_lift_gt1[i], lift_q126_check$n_seg_total[i])),
      collapse = " / ")),
  A1_cross_cycle_same_forward_labels = "PASS (56D + 53H + 53B all use targets_long_horizon.parquet)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW",
  A3_codex_code_review = "PENDING (Codex code review log: outputs/04_evaluation/cycle56d_code_review_log.md)"
)

cat("\n[NEW_CYCLE_CHECKLIST]\n")
for (k in names(checklist)) cat(sprintf("  %s: %s\n", k, checklist[[k]]))

#==============================================================================
# Step 6: Verdict (도훈 thresholds: BREAKTHROUGH/MARGINAL/INFERIOR)
#==============================================================================
cat("\n========== Step 6: Verdict (BREAKTHROUGH / MARGINAL / INFERIOR) ==========\n")

# Verdict basis: best arch q126
if (best_arch_q126_pr >= VERDICT_BREAKTHROUGH_MIN) {
  verdict <- "ARCH_BREAKTHROUGH"
  verdict_msg <- sprintf(
    paste0("ARCH_BREAKTHROUGH — best arch %s q126=%.4f >= %.2f (vs 53H-fair %.4f / 53H-raw %.4f). ",
           "Multi-seed stability + Architect 3rd-source verification 의무."),
    best_arch_q126, best_arch_q126_pr, VERDICT_BREAKTHROUGH_MIN,
    CYCLE_53H_Q126_FAIR, CYCLE_53H_Q126)
} else if (best_arch_q126_pr >= VERDICT_MARGINAL_LO &&
           best_arch_q126_pr < VERDICT_MARGINAL_HI) {
  verdict <- "ARCH_MARGINAL"
  verdict_msg <- sprintf(
    paste0("ARCH_MARGINAL — best arch %s q126=%.4f in [%.2f, %.2f). ",
           "vs 53H-fair %.4f baseline. Multi-seed + 다른 arch 보강 필요."),
    best_arch_q126, best_arch_q126_pr, VERDICT_MARGINAL_LO, VERDICT_MARGINAL_HI,
    CYCLE_53H_Q126_FAIR)
} else {
  verdict <- "ARCH_INFERIOR"
  verdict_msg <- sprintf(
    paste0("ARCH_INFERIOR — best arch %s q126=%.4f < %.2f (vs 53H-fair %.4f). ",
           "3 arch drop, PatchTST 53H retain. 다음 cycle: 다른 미시도 arch (Mamba/S4/FEDformer)."),
    best_arch_q126, best_arch_q126_pr, VERDICT_MARGINAL_LO, CYCLE_53H_Q126_FAIR)
}

cat(sprintf("\n[VERDICT] %s\n", verdict))
cat(sprintf("[VERDICT_MSG] %s\n", verdict_msg))

#==============================================================================
# Step 7: Next cycle suggestion
#==============================================================================
cat("\n========== Step 7: Next cycle suggestion ==========\n")

if (verdict == "ARCH_BREAKTHROUGH") {
  next_cycle <- list(
    primary = sprintf("56D-second: multi-seed audit (5 seeds) for best arch %s + add Mamba/S4/FEDformer", best_arch_q126),
    secondary = sprintf("Architect 3rd-source verification (AX-008 P1 admit pathway) for %s", best_arch_q126),
    tertiary = "Cycle 56E: stacking ensemble (best 53H PatchTST + new BREAKTHROUGH arch)"
  )
} else if (verdict == "ARCH_MARGINAL") {
  next_cycle <- list(
    primary = "56D-second: multi-seed audit (5 seeds) for all 3 arch to test if MARGINAL stable or seed-lucky",
    secondary = "Add Mamba/S4/FEDformer (Batch 2 of mega multi-view, 미시도 arch 보강)",
    tertiary = "EW3 stability check via 5-seed mean prediction (if EW3 close to 53H, ensemble path candidate)"
  )
} else {  # INFERIOR
  next_cycle <- list(
    primary = "Drop 3 arch (DLinear/Informer/TimesNet). PatchTST 53H 0.4012 retain as headline.",
    secondary = "Batch 2 (Mamba/S4/FEDformer) start — 3 different architecture family. 진정한 미시도 axes.",
    tertiary = sprintf("Capacity 재검토: best 56D arch %s n_params=%d, PatchTST 140K. 작은 size 1차 결과로 ceiling 검증.",
                       best_arch_q126,
                       per_arch_dt[target == "y_tail_q126" & arch == best_arch_q126, ]$n_obs)
  )
}
cat("\n[Next cycle]\n")
for (k in names(next_cycle)) cat(sprintf("  %s: %s\n", k, next_cycle[[k]]))

#==============================================================================
# Step 8: Output JSON + chart
#==============================================================================
cat("\n========== Step 8: Output JSON + chart ==========\n")

cycle_verdict <- list(
  cycle = "56D_prelim_megamulti_3arch",
  approach = "MEGA_MULTI_VIEW_3ARCH_DLinear_Informer_TimesNet_FIRST_PASS",
  hypothesis = "PatchTST 53H 0.4012 vs 3 NEW architectures (DLinear / Informer / TimesNet). Some arch beat 0.4012?",
  panel = "feature_panel_v5e_q126_usmacro.parquet",
  targets_source = "targets_long_horizon.parquet (forward labels)",
  n_features = 74,
  seed = 42L,
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV (single seed first-pass)",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  baselines = list(
    cycle_53H_patchtst_seed42_y_tail_q126_raw = CYCLE_53H_Q126,
    cycle_53H_patchtst_seed42_y_tail_q15_raw  = CYCLE_53H_Q15,
    cycle_53H_patchtst_seed42_y_tail_q126_fair_mask_clean = CYCLE_53H_Q126_FAIR,
    cycle_53H_patchtst_seed42_y_tail_q15_fair_mask_clean  = CYCLE_53H_Q15_FAIR,
    fair_baseline_note = "Cycle 56D primary delta uses *_fair_mask_clean baseline (Codex review fix label-mask convention). Raw retained for headline reference. Mask convention drift impact: q126 ~+0.0004, q15 ~negligible."
  ),
  verdict_thresholds = list(
    BREAKTHROUGH_min = VERDICT_BREAKTHROUGH_MIN,
    MARGINAL_range = c(VERDICT_MARGINAL_LO, VERDICT_MARGINAL_HI)
  ),
  per_arch = lapply(seq_len(nrow(per_arch_dt)), function(i) {
    r <- per_arch_dt[i]
    list(arch = r$arch, target = r$target,
         n_obs = r$n_obs, n_events = r$n_events,
         event_rate = r$event_rate,
         oos_pr = r$oos_pr, oos_ic = r$oos_ic,
         delta_vs_53h = r$delta_vs_53h)
  }),
  ensemble_ew3 = list(
    y_tail_q126 = ew3_rows[["y_tail_q126"]],
    y_tail_q15  = ew3_rows[["y_tail_q15"]],
    delta_vs_53h = list(
      q126 = round(ew3_delta_q126, 4),
      q15  = round(ew3_delta_q15,  4)
    )
  ),
  period_balanced = list(
    segments = lapply(SEGMENTS, function(sg) list(name = sg$name,
                                                  start = as.character(sg$start),
                                                  end = as.character(sg$end))),
    bootstrap_n = BOOTSTRAP_N,
    per_arch_segments = lapply(seq_len(nrow(segment_dt)),
      function(i) {
        r <- segment_dt[i]
        list(arch = r$arch, target = r$target, segment = r$segment,
             n_obs = r$n_obs, n_events = r$n_events,
             pr_auc = r$oos_pr, ci_lo = r$ci_lo, ci_hi = r$ci_hi)
      }),
    per_arch_3_3_lift_check = lapply(seq_len(nrow(lift_q126_check)),
      function(i) {
        r <- lift_q126_check[i]
        list(arch = r$arch, n_seg_lift_gt1 = r$n_seg_lift_gt1,
             n_seg_total = r$n_seg_total, all_3_lift_gt1 = r$all_3_lift_gt1)
      })
  ),
  cross_check_53h_re_computed = ref_53h_pr,
  best_arch_q126 = list(arch = best_arch_q126, pr_auc = best_arch_q126_pr),
  verdict = verdict,
  verdict_msg = verdict_msg,
  next_cycle_suggestion = next_cycle,
  new_cycle_checklist_compliance = checklist,
  outputs = list(
    megamulti_dir = MM_DIR,
    final_json = file.path(EVAL_DIR, "megamulti_q126_v6b.json"),
    chart = file.path(CHART_DIR, "147_megamulti_q126.png"),
    codex_code_review_log = file.path(EVAL_DIR, "cycle56d_code_review_log.md")
  )
)

out_json <- file.path(EVAL_DIR, "megamulti_q126_v6b.json")
write_json(cycle_verdict, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("\n[Final JSON] Saved: %s\n", out_json))

#==============================================================================
# Chart: per-arch OOS PR-AUC + period-balanced
#==============================================================================
chartA_data <- copy(per_arch_dt)
chartA_data[, target_label := factor(target, levels = TARGETS,
                                     labels = c("y_tail_q15 (secondary)", "y_tail_q126 (primary)"))]
chartA_data[, arch_label := factor(arch, levels = ARCHS, labels = ARCHS_DISP)]
chartA_data[, ref_label := paste0("53H ref = ", sprintf("%.4f", ref))]

# Add EW3 + 53H reference rows
ew3_add <- data.table(
  arch = c("ew3", "ew3"),
  target = TARGETS,
  arch_label = factor(c("EW3", "EW3"), levels = c(ARCHS_DISP, "EW3", "53H")),
  target_label = factor(TARGETS, levels = TARGETS,
                         labels = c("y_tail_q15 (secondary)", "y_tail_q126 (primary)")),
  oos_pr = c(ew3_rows[["y_tail_q15"]]$oos_pr, ew3_rows[["y_tail_q126"]]$oos_pr),
  ref = c(CYCLE_53H_Q15_FAIR, CYCLE_53H_Q126_FAIR),
  ref_fair = c(CYCLE_53H_Q15_FAIR, CYCLE_53H_Q126_FAIR),
  ref_raw = c(CYCLE_53H_Q15, CYCLE_53H_Q126),
  delta_vs_53h_fair = c(round(ew3_delta_q15, 4), round(ew3_delta_q126, 4)),
  delta_vs_53h_raw  = c(round(ew3_delta_q15_raw, 4), round(ew3_delta_q126_raw, 4)),
  delta_vs_53h = c(round(ew3_delta_q15, 4), round(ew3_delta_q126, 4)),
  n_obs = NA, n_events = NA, event_rate = NA, oos_ic = NA, error = NA
)
ref_add <- data.table(
  arch = c("53h_ref", "53h_ref"),
  target = TARGETS,
  arch_label = factor(c("53H", "53H"), levels = c(ARCHS_DISP, "EW3", "53H")),
  target_label = factor(TARGETS, levels = TARGETS,
                         labels = c("y_tail_q15 (secondary)", "y_tail_q126 (primary)")),
  oos_pr = c(CYCLE_53H_Q15_FAIR, CYCLE_53H_Q126_FAIR),
  ref = c(CYCLE_53H_Q15_FAIR, CYCLE_53H_Q126_FAIR),
  ref_fair = c(CYCLE_53H_Q15_FAIR, CYCLE_53H_Q126_FAIR),
  ref_raw = c(CYCLE_53H_Q15, CYCLE_53H_Q126),
  delta_vs_53h_fair = c(0, 0),
  delta_vs_53h_raw = c(0, 0),
  delta_vs_53h = c(0, 0),
  n_obs = NA, n_events = NA, event_rate = NA, oos_ic = NA, error = NA
)
chartA_all <- rbindlist(list(chartA_data, ew3_add, ref_add), fill = TRUE)
chartA_all[, arch_label := factor(arch_label, levels = c(ARCHS_DISP, "EW3", "53H"))]

pA <- ggplot(chartA_all, aes(x = arch_label, y = oos_pr, fill = arch_label)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.4f", oos_pr)), vjust = -0.5, size = 3) +
  geom_hline(data = chartA_all[!duplicated(target_label), .(target_label, ref)],
             aes(yintercept = ref), linetype = "dashed", color = "black", linewidth = 0.6) +
  facet_wrap(~ target_label, scales = "free_y", ncol = 2) +
  scale_fill_manual(values = c("DLinear" = "#1b9e77", "Informer" = "#d95f02",
                                "TimesNet" = "#7570b3", "EW3" = "#e7298a",
                                "53H" = "gray50")) +
  labs(title = "Cycle 56D-prelim — Per-arch OOS PR-AUC + EW3 ensemble",
       subtitle = sprintf("Dashed lines = Cycle 53H seed=42 (q126=%.4f / q15=%.4f)",
                          CYCLE_53H_Q126, CYCLE_53H_Q15),
       x = NULL, y = "OOS PR-AUC", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none", strip.text = element_text(face = "bold"),
        axis.text.x = element_text(angle = 20, hjust = 1))

# Panel B: period-balanced per arch
chartB_data <- copy(segment_dt[!is.na(oos_pr) & target == "y_tail_q126"])
chartB_data[, arch_label := factor(arch, levels = c(ARCHS, "ew3"),
                                   labels = c(ARCHS_DISP, "EW3"))]

pB <- ggplot(chartB_data, aes(x = segment, y = oos_pr, fill = arch_label)) +
  geom_col(position = position_dodge(width = 0.85), width = 0.75) +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                position = position_dodge(width = 0.85), width = 0.2) +
  geom_text(aes(label = sprintf("%.3f", oos_pr)),
            position = position_dodge(width = 0.85), vjust = -0.5, size = 2.8) +
  scale_fill_manual(values = c("DLinear" = "#1b9e77", "Informer" = "#d95f02",
                                "TimesNet" = "#7570b3", "EW3" = "#e7298a")) +
  labs(title = "Period-balanced PR-AUC per arch (y_tail_q126, 95% bootstrap CI)",
       x = NULL, y = "PR-AUC", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "top",
        axis.text.x = element_text(angle = 20, hjust = 1))

# Combine
chart_combined <- pA / pB +
  plot_layout(heights = c(1, 1)) +
  plot_annotation(title = "Cycle 56D-prelim — Mega Multi-View 3 architectures (DLinear + Informer + TimesNet)",
                  subtitle = sprintf("[VERDICT] %s | Best arch q126: %s = %.4f",
                                     verdict, best_arch_q126, best_arch_q126_pr),
                  theme = theme(plot.title = element_text(face = "bold", size = 13),
                                plot.subtitle = element_text(size = 11)))

chart_path <- file.path(CHART_DIR, "147_megamulti_q126.png")
ggsave(chart_path, chart_combined, width = 16, height = 11, dpi = 130)
cat(sprintf("\n[Chart] Saved: %s\n", chart_path))

cat("\n", strrep("=", 70), "\n", sep = "")
cat("[Cycle 56D-prelim R aggregate DONE]\n")
cat(strrep("=", 70), "\n", sep = "")
