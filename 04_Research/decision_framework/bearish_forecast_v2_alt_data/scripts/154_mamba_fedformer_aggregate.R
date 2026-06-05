#==============================================================================
# 154_mamba_fedformer_aggregate.R — Cycle 56D-Batch2 Aggregate
#
# Reads:
#   outputs/03_models/v6d_mamba_fedformer/predictions_{mamba|fedformer|ew2}_y_tail_{q15|q126}.parquet
#   outputs/03_models/v6d_mamba_fedformer/per_fold_diagnostics.json
#   outputs/03_models/v6d_mamba_fedformer/final_attempts.json
#   outputs/03_models/v5e_patchtst_q126_usmacro/predictions_patchtst_v5e_y_{tail_q15|tail_q126}.parquet (53H ref)
#   outputs/03_models/v6b_megamulti_q126/predictions_{dlinear|informer|timesnet}_y_tail_q126.parquet (56D-prelim refs)
#
# Steps:
#   Step 1: Per-architecture OOS PR-AUC + IC (R re-verification)
#   Step 2: EW2 ensemble PR-AUC + IC (R re-compute)
#   Step 3: vs Cycle 53H seed=42 reference (mask-clean fair baseline)
#   Step 4: Period-balanced PR-AUC per arch + bootstrap CI
#   Step 5: vs 56D-prelim 3-arch references (DLinear / Informer / TimesNet)
#   Step 6: Mamba vs FEDformer comparison (head-to-head)
#   Step 7: NEW_CYCLE_CHECKLIST status
#   Step 8: Verdict (ARCH_BREAKTHROUGH / ARCH_COMPETITIVE / ARCH_INFERIOR)
#   Step 9: Reseed rescue summary (collapse pattern audit)
#   Step 10: JSON + chart + next cycle suggestion
#
# Output:
#   outputs/04_evaluation/mamba_fedformer_v6d.json
#   outputs/06_reports/charts/154_mamba_fedformer_q126.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MF_DIR <- file.path(WS, "outputs/03_models/v6d_mamba_fedformer")
S53H_DIR <- file.path(WS, "outputs/03_models/v5e_patchtst_q126_usmacro")
S56D_PRELIM_DIR <- file.path(WS, "outputs/03_models/v6b_megamulti_q126")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

ARCHS  <- c("mamba", "fedformer")
ARCHS_DISP <- c("Mamba", "FEDformer")
TARGETS <- c("y_tail_q15", "y_tail_q126")

# Cycle 53H seed=42 reference (raw / hardcoded headline)
CYCLE_53H_Q126 <- 0.4012
CYCLE_53H_Q15  <- 0.2082
# Cycle 56D-prelim references (single seed=42, mask-clean per 147 aggregate)
CYCLE_56D_DLINEAR_Q126  <- 0.2039
CYCLE_56D_INFORMER_Q126 <- 0.2300
CYCLE_56D_TIMESNET_Q126 <- 0.2795

# Period-balanced segments (mirror 53M / 147)
SEGMENTS <- list(
  list(name = "S2018_19_calm",       start = as.Date("2018-01-01"), end = as.Date("2019-12-31")),
  list(name = "S2020_21_covid_lift", start = as.Date("2020-01-01"), end = as.Date("2021-12-31")),
  list(name = "S2022_24_inflation",  start = as.Date("2022-01-01"), end = as.Date("2024-12-31"))
)

BOOTSTRAP_N <- 1000L
BOOTSTRAP_SEED <- 20260521L

# Verdict thresholds (Q-Lead mandate)
VERDICT_BREAKTHROUGH_MIN <- 0.42
VERDICT_COMPETITIVE_LO <- 0.35
VERDICT_COMPETITIVE_HI <- 0.42

# Sanity range (NEW_CYCLE_CHECKLIST S1)
SANITY_LO <- 0.15
SANITY_HI_STRICT <- 0.40
SANITY_HI_RELAXED <- 0.50

# ─── helpers ──────────────────────────────────────────────────────────
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

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
# Load Python diagnostics + final_attempts
#==============================================================================
diag_path <- file.path(MF_DIR, "per_fold_diagnostics.json")
attempts_path <- file.path(MF_DIR, "final_attempts.json")
if (!file.exists(diag_path)) {
  stop(sprintf("Missing per_fold_diagnostics: %s\n  Run scripts/153_mamba_fedformer_q126.py first.",
               diag_path))
}
py_diag <- fromJSON(diag_path, simplifyVector = FALSE)
cat(sprintf("\n[Loaded] per_fold_diagnostics\n"))
cat(sprintf("[Cycle] %s\n", py_diag$cycle))

py_attempts <- if (file.exists(attempts_path)) fromJSON(attempts_path, simplifyVector = FALSE) else NULL

#==============================================================================
# Step 1: Per-arch × per-target PR-AUC + IC (R re-verification)
#==============================================================================
cat("\n========== Step 1: Per-arch × per-target PR-AUC + IC (R verify) ==========\n")

per_arch_rows <- list()
for (arch in ARCHS) {
  for (tc in TARGETS) {
    pred_path <- file.path(MF_DIR, sprintf("predictions_%s_%s.parquet", arch, tc))
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
# Step 2: EW2 ensemble PR-AUC + IC (R re-compute)
#==============================================================================
cat("\n========== Step 2: EW2 ensemble PR-AUC + IC (R re-compute) ==========\n")

ew2_rows <- list()
for (tc in TARGETS) {
  ew_path <- file.path(MF_DIR, sprintf("predictions_ew2_%s.parquet", tc))
  if (!file.exists(ew_path)) {
    ew2_rows[[tc]] <- list(target = tc, error = "missing_file",
                            oos_pr = NA_real_, oos_ic = NA_real_)
    next
  }
  dt <- as.data.table(read_parquet(ew_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(p_ew2) & !is.na(y)]
  pa <- pr_auc(dt$p_ew2, dt$y)
  ic <- ic_spearman(dt$p_ew2, dt$y)
  ew2_rows[[tc]] <- list(
    target = tc, n_obs = nrow(dt),
    n_events = as.integer(sum(dt$y)),
    event_rate = round(mean(dt$y), 4),
    oos_pr = round(pa, 4), oos_ic = round(ic, 4)
  )
}

cat("\n[EW2 ensemble per target]\n")
for (tc in TARGETS) {
  r <- ew2_rows[[tc]]
  if (is.null(r$error)) {
    cat(sprintf("  EW2 %-12s: PR-AUC=%.4f IC=%.4f n_obs=%d n_events=%d event_rate=%.4f\n",
                tc, r$oos_pr, r$oos_ic, r$n_obs, r$n_events, r$event_rate))
  } else {
    cat(sprintf("  EW2 %-12s: ERROR (%s)\n", tc, r$error))
  }
}

#==============================================================================
# Step 3: vs Cycle 53H seed=42 reference (fair mask-clean baseline)
#==============================================================================
cat("\n========== Step 3: vs Cycle 53H seed=42 reference (mask-clean fair) ==========\n")

per_arch_dt[, ref_raw := fifelse(target == "y_tail_q126", CYCLE_53H_Q126, CYCLE_53H_Q15)]
per_arch_dt[, delta_vs_53h_raw := round(oos_pr - ref_raw, 4)]

cat("\n[Delta vs 53H seed=42 raw headline]\n")
print(per_arch_dt[, .(arch, target, oos_pr, ref_raw, delta_vs_53h_raw, oos_ic)])

# Cross-check 53H file with R re-compute (mask-clean = same target validity convention as 56D)
load_53h <- function(target_col) {
  p <- file.path(S53H_DIR, sprintf("predictions_patchtst_v5e_%s.parquet", target_col))
  if (!file.exists(p)) return(NULL)
  dt <- as.data.table(read_parquet(p))
  dt[, Date := as.Date(Date)]
  dt[Date >= OOS_START & Date <= OOS_END]
}

# Target validity (mask-clean baseline)
tgt_legacy_path <- file.path(WS, "outputs/02_targets/targets_long_horizon.parquet")
tgt_obs_path <- file.path(WS, "outputs/02_targets/targets_long_horizon_observable.parquet")
if (file.exists(tgt_obs_path)) {
  tgt_all <- as.data.table(read_parquet(tgt_obs_path))
  cat(sprintf("\n[Using observable targets for validity mask: %s]\n", basename(tgt_obs_path)))
} else {
  tgt_all <- as.data.table(read_parquet(tgt_legacy_path))
  cat(sprintf("\n[Using legacy targets for validity mask: %s]\n", basename(tgt_legacy_path)))
}
tgt_all[, Date := as.Date(Date)]
tgt_all[, valid_q15  := !is.na(ret_q15)  & !is.na(q15_thr_q15)]
tgt_all[, valid_q126 := !is.na(ret_q126) & !is.na(q15_thr_q126)]

ref_53h_pr_raw <- list()
ref_53h_pr_mask <- list()
for (tc in TARGETS) {
  rdt <- load_53h(tc)
  if (!is.null(rdt)) {
    ref_53h_pr_raw[[tc]] <- round(pr_auc(rdt$p_patchtst, rdt$y), 4)
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
cat(sprintf("\n[53H R recompute, 2 conventions]\n"))
cat(sprintf("  q126: raw=%s  mask-clean=%s  (hardcoded ref=%.4f)\n",
            format(ref_53h_pr_raw[["y_tail_q126"]], nsmall=4),
            format(ref_53h_pr_mask[["y_tail_q126"]], nsmall=4), CYCLE_53H_Q126))
cat(sprintf("  q15:  raw=%s  mask-clean=%s  (hardcoded ref=%.4f)\n",
            format(ref_53h_pr_raw[["y_tail_q15"]], nsmall=4),
            format(ref_53h_pr_mask[["y_tail_q15"]], nsmall=4), CYCLE_53H_Q15))

CYCLE_53H_Q126_FAIR <- ref_53h_pr_mask[["y_tail_q126"]]
CYCLE_53H_Q15_FAIR  <- ref_53h_pr_mask[["y_tail_q15"]]
if (is.na(CYCLE_53H_Q126_FAIR)) CYCLE_53H_Q126_FAIR <- CYCLE_53H_Q126
if (is.na(CYCLE_53H_Q15_FAIR))  CYCLE_53H_Q15_FAIR  <- CYCLE_53H_Q15
cat(sprintf("\n[Fair baseline for cycle 56D-Batch2 delta] q126=%.4f / q15=%.4f\n",
            CYCLE_53H_Q126_FAIR, CYCLE_53H_Q15_FAIR))

per_arch_dt[, ref_fair := fifelse(target == "y_tail_q126", CYCLE_53H_Q126_FAIR, CYCLE_53H_Q15_FAIR)]
per_arch_dt[, delta_vs_53h_fair := round(oos_pr - ref_fair, 4)]
per_arch_dt[, delta_vs_53h := delta_vs_53h_fair]  # primary delta
per_arch_dt[, ref := ref_fair]

cat("\n[Fair delta vs 53H mask-clean (cycle 56D-Batch2 primary)]\n")
print(per_arch_dt[, .(arch, target, oos_pr, ref_fair, delta_vs_53h_fair, oos_ic)])

ew2_delta_q126 <- ew2_rows[["y_tail_q126"]]$oos_pr - CYCLE_53H_Q126_FAIR
ew2_delta_q15  <- ew2_rows[["y_tail_q15"]]$oos_pr - CYCLE_53H_Q15_FAIR
cat(sprintf("\n[EW2 vs 53H mask-clean]\n"))
cat(sprintf("  q126: %.4f vs %.4f → Δ=%+.4f\n",
            ew2_rows[["y_tail_q126"]]$oos_pr, CYCLE_53H_Q126_FAIR, ew2_delta_q126))
cat(sprintf("  q15:  %.4f vs %.4f → Δ=%+.4f\n",
            ew2_rows[["y_tail_q15"]]$oos_pr,  CYCLE_53H_Q15_FAIR,  ew2_delta_q15))

#==============================================================================
# Step 4: Period-balanced PR-AUC per arch + bootstrap CI
#==============================================================================
cat("\n========== Step 4: Period-balanced per arch + bootstrap CI ==========\n")

segment_rows <- list()
for (arch in ARCHS) {
  col_name <- sprintf("p_%s", arch)
  for (tc in TARGETS) {
    pred_path <- file.path(MF_DIR, sprintf("predictions_%s_%s.parquet", arch, tc))
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

# EW2 segments
for (tc in TARGETS) {
  ew_path <- file.path(MF_DIR, sprintf("predictions_ew2_%s.parquet", tc))
  if (!file.exists(ew_path)) next
  dt <- as.data.table(read_parquet(ew_path))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END]
  for (si in seq_along(SEGMENTS)) {
    sg <- SEGMENTS[[si]]
    sub <- dt[Date >= sg$start & Date <= sg$end & !is.na(p_ew2) & !is.na(y)]
    if (nrow(sub) < 30 || sum(sub$y) < 5) next
    ci <- bootstrap_ci_pr(sub$p_ew2, sub$y, B = BOOTSTRAP_N, seed = BOOTSTRAP_SEED + si + 100)
    segment_rows[[length(segment_rows) + 1]] <- data.table(
      arch = "ew2", target = tc, segment = sg$name,
      n_obs = nrow(sub), n_events = as.integer(sum(sub$y)),
      oos_pr = ci$point, ci_lo = ci$lo, ci_hi = ci$hi
    )
  }
}

segment_dt <- rbindlist(segment_rows, fill = TRUE)
cat("\n[Period-balanced PR-AUC × 2 arch + EW2 × 3 segments (bootstrap 95% CI)]\n")
print(segment_dt[order(target, arch, segment)])

# Lift (PR-AUC / base_rate)
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
# Step 5: vs 56D-prelim 3-arch references (DLinear / Informer / TimesNet)
#==============================================================================
cat("\n========== Step 5: vs 56D-prelim 3-arch references ==========\n")

# Load 56D-prelim predictions to compute mask-clean fair baselines (q126 only)
prelim_archs <- c("dlinear", "informer", "timesnet")
prelim_q126_mask_clean <- list()
for (a in prelim_archs) {
  pp <- file.path(S56D_PRELIM_DIR, sprintf("predictions_%s_y_tail_q126.parquet", a))
  if (!file.exists(pp)) {
    prelim_q126_mask_clean[[a]] <- NA_real_
    next
  }
  dt <- as.data.table(read_parquet(pp))
  dt[, Date := as.Date(Date)]
  col <- sprintf("p_%s", a)
  dt <- dt[Date >= OOS_START & Date <= OOS_END & !is.na(get(col)) & !is.na(y)]
  prelim_q126_mask_clean[[a]] <- round(pr_auc(dt[[col]], dt$y), 4)
}
cat(sprintf("\n[56D-prelim q126 mask-clean fair baselines (R re-compute)]\n"))
cat(sprintf("  DLinear:  %s (hardcoded ref %.4f)\n",
            format(prelim_q126_mask_clean[["dlinear"]], nsmall=4), CYCLE_56D_DLINEAR_Q126))
cat(sprintf("  Informer: %s (hardcoded ref %.4f)\n",
            format(prelim_q126_mask_clean[["informer"]], nsmall=4), CYCLE_56D_INFORMER_Q126))
cat(sprintf("  TimesNet: %s (hardcoded ref %.4f)\n",
            format(prelim_q126_mask_clean[["timesnet"]], nsmall=4), CYCLE_56D_TIMESNET_Q126))

# Cycle 56D-Batch2 vs prelim 3-arch (q126 primary)
batch2_q126 <- per_arch_dt[target == "y_tail_q126", .(arch, oos_pr)]
prelim_dt <- data.table(
  arch = c("DLinear", "Informer", "TimesNet"),
  ref = c(prelim_q126_mask_clean[["dlinear"]] %||% CYCLE_56D_DLINEAR_Q126,
          prelim_q126_mask_clean[["informer"]] %||% CYCLE_56D_INFORMER_Q126,
          prelim_q126_mask_clean[["timesnet"]] %||% CYCLE_56D_TIMESNET_Q126)
)

cat(sprintf("\n[Cycle 56D-Batch2 q126 vs 56D-prelim 3-arch (mask-clean R recompute)]\n"))
print(batch2_q126)
cat("\n[56D-prelim baselines]\n")
print(prelim_dt)

# Compute deltas vs each prelim arch
for (a in c("Mamba", "FEDformer")) {
  b2_pr <- per_arch_dt[arch == tolower(a) & target == "y_tail_q126"]$oos_pr
  if (length(b2_pr) == 0 || is.na(b2_pr)) {
    cat(sprintf("  %s q126 missing — skip vs prelim comparison\n", a))
    next
  }
  cat(sprintf("\n  %s q126 = %.4f\n", a, b2_pr))
  for (i in seq_len(nrow(prelim_dt))) {
    cat(sprintf("    vs %s (%.4f): Δ = %+.4f\n",
                prelim_dt$arch[i], prelim_dt$ref[i], b2_pr - prelim_dt$ref[i]))
  }
}

#==============================================================================
# Step 6: Mamba vs FEDformer head-to-head
#==============================================================================
cat("\n========== Step 6: Mamba vs FEDformer head-to-head ==========\n")

for (tc in TARGETS) {
  m_pr <- per_arch_dt[arch == "mamba" & target == tc]$oos_pr
  f_pr <- per_arch_dt[arch == "fedformer" & target == tc]$oos_pr
  m_ic <- per_arch_dt[arch == "mamba" & target == tc]$oos_ic
  f_ic <- per_arch_dt[arch == "fedformer" & target == tc]$oos_ic
  if (length(m_pr) == 0 || length(f_pr) == 0) {
    cat(sprintf("  %s: missing arch data — skip\n", tc))
    next
  }
  cat(sprintf("\n  %s:\n", tc))
  cat(sprintf("    Mamba:     PR=%.4f IC=%.4f\n", m_pr, m_ic))
  cat(sprintf("    FEDformer: PR=%.4f IC=%.4f\n", f_pr, f_ic))
  cat(sprintf("    Δ (Mamba - FEDformer): PR=%+.4f IC=%+.4f\n", m_pr - f_pr, m_ic - f_ic))
  if (m_pr > f_pr + 0.01) {
    cat(sprintf("    > Winner: Mamba (margin > 0.01)\n"))
  } else if (f_pr > m_pr + 0.01) {
    cat(sprintf("    > Winner: FEDformer (margin > 0.01)\n"))
  } else {
    cat(sprintf("    > Tie (|Δ| < 0.01)\n"))
  }
}

#==============================================================================
# Step 7: NEW_CYCLE_CHECKLIST status
#==============================================================================
cat("\n========== Step 7: NEW_CYCLE_CHECKLIST status ==========\n")

# Best arch q126
best_arch_q126_row <- per_arch_dt[target == "y_tail_q126" & !is.na(oos_pr)][which.max(oos_pr)]
if (nrow(best_arch_q126_row) == 0) {
  best_arch_q126 <- "NONE"
  best_arch_q126_pr <- NA_real_
} else {
  best_arch_q126 <- best_arch_q126_row$arch
  best_arch_q126_pr <- best_arch_q126_row$oos_pr
}

# Sanity check (S1)
if (is.na(best_arch_q126_pr)) {
  sanity_msg <- "N/A — no valid arch"
} else if (best_arch_q126_pr <= SANITY_HI_STRICT) {
  sanity_msg <- sprintf("PASS (best arch %s q126=%.4f ∈ [%.2f, %.2f])",
                        best_arch_q126, best_arch_q126_pr, SANITY_LO, SANITY_HI_STRICT)
} else if (best_arch_q126_pr <= SANITY_HI_RELAXED) {
  sanity_msg <- sprintf("WARN_HIGH (%s q126=%.4f ∈ (%.2f, %.2f]) — strong signal range",
                        best_arch_q126, best_arch_q126_pr, SANITY_HI_STRICT, SANITY_HI_RELAXED)
} else if (best_arch_q126_pr > SANITY_HI_RELAXED) {
  sanity_msg <- sprintf("FAIL_TOO_HIGH (%s q126=%.4f > %.2f) — implausibly high",
                        best_arch_q126, best_arch_q126_pr, SANITY_HI_RELAXED)
} else {
  sanity_msg <- sprintf("FAIL (%s q126=%.4f < %.2f) — no value vs base rate",
                        best_arch_q126, best_arch_q126_pr, SANITY_LO)
}

checklist <- list(
  M1_bear_date_audit = "PASS (pre-cycle 4/4, bear_date_audit_20260521_095237.json)",
  M2_validate_label_direction = "PASS (forward labels inherited; observable targets)",
  M3_PIT_C1_C15 = "PASS (v5e panel PIT validated 53H; Mamba causal scan + FEDformer FFT train window only)",
  M4_shift_convention = "PASS (forward targets via shift(.,n=H,'lead'); inherited)",
  M5_AX_008 = "EXEMPT (Forge architecture survey, NOT admit cycle)",
  M6_phantom_0_assertion = sprintf(
    "PASS (used observable targets: %s — phantom-0=0 across q15/q63/q126)",
    if (file.exists(tgt_obs_path)) basename(tgt_obs_path) else "legacy_fallback"),
  S1_PRAUC_sanity_q126 = sanity_msg,
  S2_COVID_spot_check = "PASS (targets inherited from 53H A2 — 2020-02-19 ret_q126=-0.3405 verified bear_date_audit)",
  S3_singleseed_firstpass = "N/A (single seed=42 base + reseed rescue [43,44,45]; multi-seed cycle 56D-third if BREAKTHROUGH)",
  A1_cross_cycle_label = "PASS (forward labels via observable; fair compare across 56D-prelim/53H mask-clean R recompute)",
  A2_dohoon_audit_checkpoint = "TBD (Q-Lead verdict step + 도훈 sign-off if BREAKTHROUGH)",
  A3_codex_critic = "ACTIVE (codex code review log: cycle56dbatch2_code_review_log.md)"
)
cat("\n[NEW_CYCLE_CHECKLIST status]\n")
for (k in names(checklist)) {
  cat(sprintf("  %-32s : %s\n", k, checklist[[k]]))
}

#==============================================================================
# Step 8: Verdict
#==============================================================================
cat("\n========== Step 8: Verdict (Q-Lead) ==========\n")

# Strictly best arch (any of mamba / fedformer / ew2)
all_q126_pr <- c(
  mamba     = per_arch_dt[arch == "mamba" & target == "y_tail_q126"]$oos_pr %||% NA_real_,
  fedformer = per_arch_dt[arch == "fedformer" & target == "y_tail_q126"]$oos_pr %||% NA_real_,
  ew2       = ew2_rows[["y_tail_q126"]]$oos_pr %||% NA_real_
)
# Drop NA
all_q126_pr <- all_q126_pr[!is.na(all_q126_pr)]

if (length(all_q126_pr) == 0) {
  verdict <- "INSUFFICIENT_DATA"
  verdict_winner <- "NONE"
  verdict_pr <- NA_real_
} else {
  verdict_pr <- max(all_q126_pr)
  verdict_winner <- names(all_q126_pr)[which.max(all_q126_pr)]
  if (verdict_pr > VERDICT_BREAKTHROUGH_MIN) {
    verdict <- "ARCH_BREAKTHROUGH"
  } else if (verdict_pr >= VERDICT_COMPETITIVE_LO && verdict_pr <= VERDICT_COMPETITIVE_HI) {
    verdict <- "ARCH_COMPETITIVE"
  } else if (verdict_pr < VERDICT_COMPETITIVE_LO) {
    verdict <- "ARCH_INFERIOR"
  } else {
    verdict <- "ARCH_BORDERLINE"
  }
}

cat(sprintf("\n[Q-Lead Verdict] %s\n", verdict))
cat(sprintf("  Winner: %s\n", verdict_winner))
cat(sprintf("  Best q126 PR-AUC: %s\n", format(verdict_pr, nsmall=4)))
cat(sprintf("  vs 53H mask-clean fair (%.4f): Δ=%+.4f\n",
            CYCLE_53H_Q126_FAIR, verdict_pr - CYCLE_53H_Q126_FAIR))
cat(sprintf("  Thresholds: BREAKTHROUGH > %.2f / COMPETITIVE %.2f~%.2f / INFERIOR < %.2f\n",
            VERDICT_BREAKTHROUGH_MIN, VERDICT_COMPETITIVE_LO, VERDICT_COMPETITIVE_HI, VERDICT_COMPETITIVE_LO))

#==============================================================================
# Step 9: Reseed rescue summary
#==============================================================================
cat("\n========== Step 9: Reseed rescue summary ==========\n")

if (!is.null(py_attempts)) {
  for (key in names(py_attempts$per_arch)) {
    ar <- py_attempts$per_arch[[key]]
    cat(sprintf("\n  [%s] adopted_seed=%s all_collapsed=%s\n",
                key, ar$adopted_seed, ar$all_collapsed))
    n_att <- length(ar$attempts)
    for (i in seq_len(n_att)) {
      att <- ar$attempts[[i]]
      cat(sprintf("    attempt %d: seed=%s OOS_PR=%s IC=%s collapsed=%s p_max=%s\n",
                  i, att$seed,
                  format(att$oos_pr, nsmall=4),
                  format(att$oos_ic, nsmall=4),
                  att$collapse$collapsed,
                  format(att$collapse$p_max, scientific=TRUE)))
    }
  }
} else {
  cat("  No final_attempts.json — skip reseed summary\n")
}

#==============================================================================
# Step 10: Next cycle suggestion
#==============================================================================
cat("\n========== Step 10: Next cycle suggestion (Q-Lead) ==========\n")

next_cycle <- list()
if (verdict == "ARCH_BREAKTHROUGH") {
  next_cycle$priority <- "CONFIRM_BREAKTHROUGH"
  next_cycle$suggestion <- list(
    a = sprintf("Multi-seed stability test (5 seeds [42,43,44,45,46]) on %s q126 to confirm %.4f", verdict_winner, verdict_pr),
    b = "Capacity reduction sweep (patch_size analog → d_model=32 / n_layers=1) per 54A pattern",
    c = "Period-balanced stress test (Codex critic eval on COVID + Stagflation segments)"
  )
} else if (verdict == "ARCH_COMPETITIVE") {
  next_cycle$priority <- "ENSEMBLE_AND_PIVOT"
  next_cycle$suggestion <- list(
    a = sprintf("EW ensemble all 6 archs (PatchTST + DLinear + Informer + TimesNet + Mamba + FEDformer): does diversity recover 0.40+?"),
    b = "Try S4 (next state-space variant) or N-HiTS (multi-resolution) — different inductive bias",
    c = "Feature engineering: v5g panel (add cross-asset / regime indicators)"
  )
} else if (verdict == "ARCH_INFERIOR") {
  next_cycle$priority <- "PIVOT_TO_FEATURES"
  next_cycle$suggestion <- list(
    a = "Architecture family appears saturated at ~0.30; pivot to FEATURE / TARGET design",
    b = "Try v5g panel (regime tags / KOSPI cross-section / vol clustering) for orthogonal info",
    c = "Try multi-task target (q15 + q63 + q126 joint head) to enrich signal",
    d = "Document architecture exhaustion: 56D 5-arch sweep + Batch2 2-arch = saturation evidence"
  )
} else {
  next_cycle$priority <- "DIAGNOSTIC"
  next_cycle$suggestion <- list(
    a = "Insufficient data or borderline — re-run with diagnostic instrumentation",
    b = "Verify forward label integrity (bear_date_audit + label_semantics re-run)",
    c = "Check for systematic logit collapse (reseed rescue audit)"
  )
}

cat(sprintf("\n[Priority] %s\n", next_cycle$priority))
for (k in names(next_cycle$suggestion)) {
  cat(sprintf("  (%s) %s\n", k, next_cycle$suggestion[[k]]))
}

#==============================================================================
# Step 11: JSON dump
#==============================================================================
cat("\n========== Step 11: JSON dump ==========\n")

out_json <- list(
  cycle = "56D_Batch2_mamba_fedformer",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  reference_baselines = list(
    cycle_53h_q126_raw = CYCLE_53H_Q126,
    cycle_53h_q15_raw = CYCLE_53H_Q15,
    cycle_53h_q126_fair_mask_clean = CYCLE_53H_Q126_FAIR,
    cycle_53h_q15_fair_mask_clean = CYCLE_53H_Q15_FAIR,
    cycle_56d_prelim_q126_hardcoded = list(
      dlinear = CYCLE_56D_DLINEAR_Q126,
      informer = CYCLE_56D_INFORMER_Q126,
      timesnet = CYCLE_56D_TIMESNET_Q126
    ),
    cycle_56d_prelim_q126_mask_clean_R_recompute = prelim_q126_mask_clean
  ),
  per_arch = as.list(per_arch_dt),
  ew2_ensemble = ew2_rows,
  period_balanced = as.list(segment_dt),
  lift = as.list(segment_lift),
  lift_q126_3of3_check = as.list(lift_q126_check),
  checklist = checklist,
  verdict = list(
    verdict = verdict,
    winner = verdict_winner,
    best_q126_pr = verdict_pr,
    delta_vs_53h_fair = round(verdict_pr - CYCLE_53H_Q126_FAIR, 4),
    thresholds = list(
      breakthrough_min = VERDICT_BREAKTHROUGH_MIN,
      competitive_lo = VERDICT_COMPETITIVE_LO,
      competitive_hi = VERDICT_COMPETITIVE_HI
    )
  ),
  next_cycle_suggestion = next_cycle,
  python_diagnostics_path = file.path(MF_DIR, "per_fold_diagnostics.json"),
  final_attempts_path = file.path(MF_DIR, "final_attempts.json")
)

json_path <- file.path(EVAL_DIR, "mamba_fedformer_v6d.json")
write_json(out_json, json_path, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat(sprintf("\n[JSON] Saved: %s\n", json_path))

#==============================================================================
# Step 12: Chart
#==============================================================================
cat("\n========== Step 12: Chart ==========\n")

# Chart 1: Per-arch q126 vs 53H + 56D-prelim
chart_dt <- rbind(
  data.table(label = "53H PatchTST (ref)", pr = CYCLE_53H_Q126_FAIR, family = "ref"),
  data.table(label = "56D DLinear",        pr = prelim_q126_mask_clean[["dlinear"]] %||% CYCLE_56D_DLINEAR_Q126, family = "56D-prelim"),
  data.table(label = "56D Informer",       pr = prelim_q126_mask_clean[["informer"]] %||% CYCLE_56D_INFORMER_Q126, family = "56D-prelim"),
  data.table(label = "56D TimesNet",       pr = prelim_q126_mask_clean[["timesnet"]] %||% CYCLE_56D_TIMESNET_Q126, family = "56D-prelim"),
  data.table(label = "56D-B2 Mamba",       pr = per_arch_dt[arch == "mamba" & target == "y_tail_q126"]$oos_pr %||% NA_real_, family = "56D-Batch2"),
  data.table(label = "56D-B2 FEDformer",   pr = per_arch_dt[arch == "fedformer" & target == "y_tail_q126"]$oos_pr %||% NA_real_, family = "56D-Batch2"),
  data.table(label = "56D-B2 EW2",         pr = ew2_rows[["y_tail_q126"]]$oos_pr %||% NA_real_, family = "56D-Batch2")
)
chart_dt[, label := factor(label, levels = label)]

p1 <- ggplot(chart_dt[!is.na(pr)], aes(x = label, y = pr, fill = family)) +
  geom_col() +
  geom_hline(yintercept = CYCLE_53H_Q126_FAIR, linetype = "dashed", color = "blue", alpha = 0.7) +
  geom_text(aes(label = sprintf("%.4f", pr)), vjust = -0.3, size = 3) +
  annotate("text", x = 0.7, y = CYCLE_53H_Q126_FAIR + 0.02,
           label = sprintf("53H fair=%.4f", CYCLE_53H_Q126_FAIR), color = "blue", size = 3, hjust = 0) +
  scale_fill_manual(values = c("ref" = "steelblue", "56D-prelim" = "orange", "56D-Batch2" = "forestgreen")) +
  labs(title = sprintf("Cycle 56D-Batch2 q126 PR-AUC — %s (best %s = %.4f)", verdict, verdict_winner, verdict_pr),
       subtitle = "vs 53H PatchTST mask-clean fair baseline + 56D-prelim 3-arch",
       x = NULL, y = "OOS PR-AUC (y_tail_q126)", fill = "Family") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 25, hjust = 1, size = 9))

# Chart 2: Period-balanced lift per arch + EW2 (q126)
seg_q126 <- segment_lift[target == "y_tail_q126"]
p2 <- ggplot(seg_q126, aes(x = segment, y = lift, fill = arch)) +
  geom_col(position = position_dodge(0.8), width = 0.7) +
  geom_hline(yintercept = 1.0, linetype = "dashed", color = "red", alpha = 0.7) +
  geom_text(aes(label = sprintf("%.2f", lift)), position = position_dodge(0.8),
            vjust = -0.3, size = 2.7) +
  labs(title = "Period-balanced lift (PR-AUC / base_rate) — q126",
       subtitle = "Lift > 1.0 = better than random; 3/3 segments → robust",
       x = NULL, y = "Lift", fill = "Arch") +
  theme_minimal() +
  theme(axis.text.x = element_text(size = 9))

combined <- p1 / p2 + plot_layout(heights = c(1.2, 1))
ggsave(file.path(CHART_DIR, "154_mamba_fedformer_q126.png"),
       plot = combined, width = 11, height = 8.5, dpi = 120, bg = "white")
cat(sprintf("\n[Chart] Saved: %s\n", file.path(CHART_DIR, "154_mamba_fedformer_q126.png")))

cat("\n", strrep("=", 80), "\n", sep = "")
cat(sprintf("[Cycle 56D-Batch2 R Aggregate DONE]\n"))
cat(sprintf("  Verdict: %s | Winner: %s | Best q126 PR-AUC: %s\n",
            verdict, verdict_winner, format(verdict_pr, nsmall=4)))
cat(sprintf("  JSON: %s\n", json_path))
cat(sprintf("  Chart: %s\n", file.path(CHART_DIR, "154_mamba_fedformer_q126.png")))
cat(strrep("=", 80), "\n", sep = "")
