#==============================================================================
# 156_10seed_strict_observable_aggregate.R — Cycle 54E aggregate + observable
#
# Pipeline:
#   Step 1: Per-seed OOS PR-AUC × 2 targets (NEW 5 strict-det + SOURCE 5 reused)
#            against (a) buggy original y (filled NaN to 0) and
#                    (b) observable-only labels (NaN propagated).
#   Step 2: 10-seed mean prediction PR-AUC (observable) + 5-seed comparisons.
#   Step 3: Std reduction quantitative (5-seed → 10-seed).
#   Step 4: Bootstrap CI on 10-seed mean prediction PR-AUC.
#   Step 5: Period-balanced PR-AUC (S2018-19 / S2020-21 / S2022-24).
#   Step 6: Strict determinism cross-check (NEW seed = SOURCE seed if seeds were
#            reused — they aren't here, so check NEW std vs SOURCE std).
#   Step 7: Headline verdict (Q-Lead direct):
#            HEADLINE_STRONG_VALIDATED / MODERATE / INVALIDATED.
#   Step 8: NEW_CYCLE_CHECKLIST status.
#   Step 9: Output JSON + chart.
#
# Reads:
#   outputs/03_models/v5e_q126_10seed/
#     predictions_patchtst_v5e_seed{2048|3000|5000|7777|9999}_y_tail_q126.parquet
#     predictions_patchtst_v5e_seed{2048|3000|5000|7777|9999}_y_tail_q15.parquet
#     predictions_patchtst_v5e_mean5_new_y_{tail_q126|tail_q15}.parquet
#     predictions_patchtst_v5e_mean5_source_y_{tail_q126|tail_q15}.parquet
#     predictions_patchtst_v5e_mean10_y_{tail_q126|tail_q15}.parquet
#     per_fold_diagnostics.json + seed_variance_audit.json + provenance.json
#   outputs/02_targets/targets_long_horizon_observable.parquet
#
# Output:
#   outputs/04_evaluation/cycle54e_10seed_strict_observable.json
#   outputs/06_reports/charts/156_10seed_strict_observable.png
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(ggplot2)
  library(patchwork)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
TS_DIR <- file.path(WS, "outputs/03_models/v5e_q126_10seed")
SRC_54C_DIR <- file.path(WS, "outputs/03_models/v5e_q126_multiseed")
S53H_DIR <- file.path(WS, "outputs/03_models/v5e_patchtst_q126_usmacro")
TGT_DIR <- file.path(WS, "outputs/02_targets")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")
dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(CHART_DIR, recursive = TRUE, showWarnings = FALSE)

OOS_START <- as.Date("2018-01-01")
OOS_END   <- as.Date("2026-04-30")

NEW_SEEDS    <- c(2048L, 3000L, 5000L, 7777L, 9999L)
SOURCE_SEEDS <- c(42L, 123L, 456L, 789L, 1024L)
ALL_SEEDS_10 <- c(SOURCE_SEEDS, NEW_SEEDS)
TARGETS <- c("y_tail_q15", "y_tail_q126")

# Stability thresholds (mirror Cycle 53C/54C convention)
STABILITY_STABLE_STD   <- 0.02
STABILITY_MODERATE_STD <- 0.05

# Baselines for comparison
CYCLE_53H_Q126        <- 0.4012   # seed=42 single (original)
CYCLE_54C_5SEED_Q126  <- 0.5617   # 5-seed mean (original)
CYCLE_54C_5SEED_STD_Q126 <- 0.0787 # 5-seed std (original)
CYCLE_53H_Q15         <- 0.2082
CYCLE_54C_5SEED_Q15   <- 0.2406
V13_FORWARD_BASELINE  <- 0.1450

# Period segments (mirror 54C)
SEGMENTS <- list(
  list(name = "S2018_19_calm",       start = as.Date("2018-01-01"), end = as.Date("2019-12-31")),
  list(name = "S2020_21_covid_lift", start = as.Date("2020-01-01"), end = as.Date("2021-12-31")),
  list(name = "S2022_24_inflation",  start = as.Date("2022-01-01"), end = as.Date("2024-12-31"))
)

BOOTSTRAP_N <- 1000L
BOOTSTRAP_SEED <- 20260521L

# ─── helpers ────────────────────────────────────────────────────────────
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

# ─── Load observable targets (for re-evaluation) ────────────────────────
obs_path <- file.path(TGT_DIR, "targets_long_horizon_observable.parquet")
stopifnot(file.exists(obs_path))
tgt_obs <- as.data.table(read_parquet(obs_path))
tgt_obs[, Date := as.Date(Date)]
setorder(tgt_obs, Date)
cat(sprintf("\n[obs] loaded %s — %d rows\n", basename(obs_path), nrow(tgt_obs)))

# ─── Load Python diagnostics ────────────────────────────────────────────
diag_path  <- file.path(TS_DIR, "per_fold_diagnostics.json")
audit_path <- file.path(TS_DIR, "seed_variance_audit.json")
prov_path  <- file.path(TS_DIR, "provenance.json")
stopifnot(file.exists(diag_path), file.exists(audit_path), file.exists(prov_path))
py_diag  <- fromJSON(diag_path, simplifyVector = FALSE)
py_audit <- fromJSON(audit_path, simplifyVector = FALSE)
py_prov  <- fromJSON(prov_path, simplifyVector = FALSE)

cat(sprintf("\n[Loaded] py_diag cycle=%s\n", py_diag$cycle))
cat(sprintf("[NEW seeds]    %s\n", paste(NEW_SEEDS, collapse = ",")))
cat(sprintf("[SOURCE seeds] %s\n", paste(SOURCE_SEEDS, collapse = ",")))

#==============================================================================
# Helper: load a per-seed prediction (NEW from 54E dir, SOURCE from 54C dir)
#==============================================================================
load_seed_pred <- function(seed, target_col, source = c("new", "source")) {
  source <- match.arg(source)
  if (source == "new") {
    p <- file.path(TS_DIR, sprintf("predictions_patchtst_v5e_seed%d_%s.parquet", seed, target_col))
  } else {
    p <- file.path(SRC_54C_DIR, sprintf("predictions_patchtst_v5e_seed%d_%s.parquet", seed, target_col))
  }
  if (!file.exists(p)) return(NULL)
  dt <- as.data.table(read_parquet(p))
  dt[, Date := as.Date(Date)]
  # OOS window
  dt <- dt[Date >= OOS_START & Date <= OOS_END]
  dt
}

# ─── Discover probability column in a prediction parquet ─────────────────
prob_col <- function(dt) {
  cand <- intersect(c("p_patchtst_v5e", "p_patchtst", "p_bear", "p"), colnames(dt))[1]
  cand
}

#==============================================================================
# Step 1: Per-seed PR-AUC + IC × 2 targets × {orig, observable}
#==============================================================================
cat("\n========== Step 1: Per-seed PR-AUC × 2 targets × {orig, observable} ==========\n")

eval_seed <- function(seed, target_col, source) {
  dt <- load_seed_pred(seed, target_col, source = source)
  if (is.null(dt) || nrow(dt) == 0) {
    return(data.table(seed = seed, target = target_col, source = source,
                      n_obs = NA_integer_, n_events_orig = NA_integer_, n_events_obs = NA_integer_,
                      n_phantom_excluded = NA_integer_,
                      orig_pr_auc = NA_real_, obs_pr_auc = NA_real_,
                      delta_pr = NA_real_, orig_ic = NA_real_, obs_ic = NA_real_,
                      p_max = NA_real_, p_p99 = NA_real_, p_mean = NA_real_, logit_median = NA_real_,
                      detected_collapse = NA,
                      collapsed = NA, all_collapsed = NA))
  }
  pcol <- prob_col(dt)
  # Merge with observable targets (key Date)
  m <- merge(dt[, .SD, .SDcols = c("Date", pcol, "y",
                                   intersect(c("collapsed", "all_collapsed"), colnames(dt)))],
             tgt_obs[, .(Date, y_obs = get(target_col))], by = "Date", all.x = TRUE)
  setnames(m, pcol, "p_pred")
  pr_o <- pr_auc(m$p_pred, m$y)
  pr_b <- pr_auc(m$p_pred, m$y_obs)
  ic_o <- ic_spearman(m$p_pred, m$y)
  ic_b <- ic_spearman(m$p_pred, m$y_obs)
  n_phantom <- sum(is.na(m$y_obs) & !is.na(m$y))

  # Logit-collapse diagnostic (R-side mirror of Python detect_logit_collapse).
  # Critical for SOURCE seeds (non-strict-det 54C) where collapse was NOT detected
  # nor rescued — we need to surface collapsed source seeds in the audit.
  p_vec <- m$p_pred[!is.na(m$p_pred)]
  if (length(p_vec) > 0) {
    p_max_v <- max(p_vec)
    p_p99_v <- as.numeric(quantile(p_vec, 0.99, na.rm = TRUE))
    p_mean_v <- mean(p_vec)
    eps <- 1e-30
    p_clip <- pmin(pmax(p_vec, eps), 1.0 - eps)
    logit_v <- log(p_clip / (1.0 - p_clip))
    logit_med_v <- median(logit_v)
    detected_collapse_v <- (p_max_v < 1e-4) && (logit_med_v < -15.0)
  } else {
    p_max_v <- NA_real_; p_p99_v <- NA_real_; p_mean_v <- NA_real_
    logit_med_v <- NA_real_; detected_collapse_v <- NA
  }

  data.table(
    seed = seed, target = target_col, source = source,
    n_obs = nrow(m),
    n_events_orig = as.integer(sum(m$y, na.rm = TRUE)),
    n_events_obs = as.integer(sum(m$y_obs, na.rm = TRUE)),
    n_phantom_excluded = as.integer(n_phantom),
    orig_pr_auc = round(pr_o, 4),
    obs_pr_auc = round(pr_b, 4),
    delta_pr = round(pr_b - pr_o, 4),
    orig_ic = round(ic_o, 4),
    obs_ic = round(ic_b, 4),
    p_max = signif(p_max_v, 4),
    p_p99 = signif(p_p99_v, 4),
    p_mean = signif(p_mean_v, 4),
    logit_median = round(logit_med_v, 2),
    detected_collapse = detected_collapse_v,
    collapsed = if ("collapsed" %in% colnames(m)) any(m$collapsed) else NA,
    all_collapsed = if ("all_collapsed" %in% colnames(m)) any(m$all_collapsed) else NA
  )
}

per_seed_rows <- list()
for (s in NEW_SEEDS)    for (tc in TARGETS) per_seed_rows[[length(per_seed_rows) + 1]] <- eval_seed(s, tc, "new")
for (s in SOURCE_SEEDS) for (tc in TARGETS) per_seed_rows[[length(per_seed_rows) + 1]] <- eval_seed(s, tc, "source")
per_seed_dt <- rbindlist(per_seed_rows, fill = TRUE)

cat("\n[Per-seed × source × target]\n")
print(per_seed_dt)

#==============================================================================
# Step 1b: Logit-collapse audit (CRITICAL — surfaces SOURCE seed collapses
#          that 54C never detected because non-strict-det path had no detector)
#==============================================================================
cat("\n========== Step 1b: Logit-collapse audit (R-side, mirrors Python detector) ==========\n")
collapse_audit <- per_seed_dt[, .(seed, target, source, p_max, p_p99, p_mean,
                                  logit_median, detected_collapse,
                                  obs_pr_auc)]
collapsed_seeds <- collapse_audit[detected_collapse == TRUE]
borderline_seeds <- collapse_audit[detected_collapse == FALSE & p_max < 1e-3 & logit_median < -10]

cat(sprintf("\n[Collapse detection summary]\n"))
cat(sprintf("  Total seeds × targets: %d\n", nrow(collapse_audit)))
cat(sprintf("  COLLAPSED (p_max<1e-4 AND logit_median<-15): %d\n", nrow(collapsed_seeds)))
cat(sprintf("  BORDERLINE (p_max<1e-3 AND logit_median<-10, not collapsed): %d\n", nrow(borderline_seeds)))

if (nrow(collapsed_seeds) > 0) {
  cat("\n[COLLAPSED seeds — exclude from ensemble for sound interpretation]\n")
  print(collapsed_seeds)
}
if (nrow(borderline_seeds) > 0) {
  cat("\n[BORDERLINE seeds — predictions saturated, fragile ranking]\n")
  print(borderline_seeds)
}

# Source-seed collapse count for surfacing in headline
n_collapsed_source_q126 <- nrow(collapse_audit[source == "source" & target == "y_tail_q126" & detected_collapse == TRUE])
n_collapsed_new_q126 <- nrow(collapse_audit[source == "new" & target == "y_tail_q126" & detected_collapse == TRUE])
n_borderline_source_q126 <- nrow(collapse_audit[source == "source" & target == "y_tail_q126" &
                                                detected_collapse == FALSE & p_max < 1e-3 & logit_median < -10])
n_borderline_new_q126 <- nrow(collapse_audit[source == "new" & target == "y_tail_q126" &
                                             detected_collapse == FALSE & p_max < 1e-3 & logit_median < -10])

cat(sprintf("\n[q126 NEW (strict-det + rescue)] collapsed=%d / borderline=%d / total=5\n",
            n_collapsed_new_q126, n_borderline_new_q126))
cat(sprintf("[q126 SOURCE (54C non-strict)]   collapsed=%d / borderline=%d / total=5\n",
            n_collapsed_source_q126, n_borderline_source_q126))

#==============================================================================
# Step 2: 10-seed mean prediction PR-AUC (observable) + 5-seed comparisons
#==============================================================================
cat("\n========== Step 2: Mean prediction PR-AUC (orig + observable) ==========\n")

eval_mean <- function(label, target_col) {
  p <- file.path(TS_DIR, sprintf("predictions_patchtst_v5e_%s_%s.parquet", label, target_col))
  if (!file.exists(p)) return(NULL)
  dt <- as.data.table(read_parquet(p))
  dt[, Date := as.Date(Date)]
  dt <- dt[Date >= OOS_START & Date <= OOS_END]
  pcol <- intersect(paste0("p_patchtst_v5e_", label), colnames(dt))[1]
  if (is.na(pcol)) {
    # fallback search
    pcol <- grep("^p_", colnames(dt), value = TRUE)[1]
  }
  m <- merge(dt[, .SD, .SDcols = c("Date", pcol, "y",
                                   intersect(c("p_per_seed_std", "n_seeds"), colnames(dt)))],
             tgt_obs[, .(Date, y_obs = get(target_col))], by = "Date", all.x = TRUE)
  setnames(m, pcol, "p_pred")
  pr_o <- pr_auc(m$p_pred, m$y)
  pr_b <- pr_auc(m$p_pred, m$y_obs)
  ic_o <- ic_spearman(m$p_pred, m$y)
  ic_b <- ic_spearman(m$p_pred, m$y_obs)
  ci_b <- bootstrap_ci_pr(m$p_pred, m$y_obs)
  n_phantom <- sum(is.na(m$y_obs) & !is.na(m$y))
  per_date_std_mean <- if ("p_per_seed_std" %in% colnames(m))
    mean(m$p_per_seed_std, na.rm = TRUE) else NA_real_
  per_date_std_med <- if ("p_per_seed_std" %in% colnames(m))
    median(m$p_per_seed_std, na.rm = TRUE) else NA_real_
  per_date_std_max <- if ("p_per_seed_std" %in% colnames(m))
    max(m$p_per_seed_std, na.rm = TRUE) else NA_real_
  data.table(
    label = label, target = target_col,
    n_obs = nrow(m),
    n_events_obs = as.integer(sum(m$y_obs, na.rm = TRUE)),
    n_phantom_excluded = as.integer(n_phantom),
    orig_pr_auc = round(pr_o, 4),
    obs_pr_auc = round(pr_b, 4),
    delta_pr = round(pr_b - pr_o, 4),
    orig_ic = round(ic_o, 4),
    obs_ic = round(ic_b, 4),
    obs_ci_lo = ci_b$lo,
    obs_ci_hi = ci_b$hi,
    per_date_std_mean = round(per_date_std_mean, 4),
    per_date_std_median = round(per_date_std_med, 4),
    per_date_std_max = round(per_date_std_max, 4),
    n_seeds = if ("n_seeds" %in% colnames(m)) m$n_seeds[1] else NA_integer_
  )
}

mean_rows <- list()
for (lab in c("mean5_new", "mean5_source", "mean10")) {
  for (tc in TARGETS) {
    r <- eval_mean(lab, tc)
    if (!is.null(r)) mean_rows[[length(mean_rows) + 1]] <- r
  }
}
mean_dt <- rbindlist(mean_rows, fill = TRUE)

cat("\n[Mean prediction summary (orig vs observable)]\n")
print(mean_dt)

#==============================================================================
# Step 3: Std reduction (5-seed → 10-seed)
#==============================================================================
cat("\n========== Step 3: Std reduction 5-seed vs 10-seed ==========\n")

std_table <- per_seed_dt[!is.na(obs_pr_auc), .(
  n_seeds = .N,
  mean_pr = round(mean(obs_pr_auc, na.rm = TRUE), 4),
  std_pr  = round(sd(obs_pr_auc, na.rm = TRUE), 4),
  min_pr  = round(min(obs_pr_auc, na.rm = TRUE), 4),
  max_pr  = round(max(obs_pr_auc, na.rm = TRUE), 4),
  range_pr = round(max(obs_pr_auc, na.rm = TRUE) - min(obs_pr_auc, na.rm = TRUE), 4)
), by = .(target, source)]
std_table[, stability_verdict := fcase(
  std_pr < STABILITY_STABLE_STD, "STABLE",
  std_pr <= STABILITY_MODERATE_STD, "MODERATE",
  default = "UNSTABLE"
)]

# 10-seed combined
std_10 <- per_seed_dt[!is.na(obs_pr_auc), .(
  source = "merged10",
  n_seeds = .N,
  mean_pr = round(mean(obs_pr_auc, na.rm = TRUE), 4),
  std_pr  = round(sd(obs_pr_auc, na.rm = TRUE), 4),
  min_pr  = round(min(obs_pr_auc, na.rm = TRUE), 4),
  max_pr  = round(max(obs_pr_auc, na.rm = TRUE), 4),
  range_pr = round(max(obs_pr_auc, na.rm = TRUE) - min(obs_pr_auc, na.rm = TRUE), 4)
), by = target]
std_10[, stability_verdict := fcase(
  std_pr < STABILITY_STABLE_STD, "STABLE",
  std_pr <= STABILITY_MODERATE_STD, "MODERATE",
  default = "UNSTABLE"
)]
std_combined <- rbind(std_table, std_10, fill = TRUE)
setorder(std_combined, target, source)

cat("\n[Std reduction table (observable PR-AUC basis)]\n")
print(std_combined)

# Std reduction quantitative
q126_5src <- std_combined[target == "y_tail_q126" & source == "source", std_pr]
q126_5new <- std_combined[target == "y_tail_q126" & source == "new", std_pr]
q126_10   <- std_combined[target == "y_tail_q126" & source == "merged10", std_pr]
q15_5src  <- std_combined[target == "y_tail_q15" & source == "source", std_pr]
q15_5new  <- std_combined[target == "y_tail_q15" & source == "new", std_pr]
q15_10    <- std_combined[target == "y_tail_q15" & source == "merged10", std_pr]

cat(sprintf("\n[q126] 5-SOURCE std=%.4f / 5-NEW std=%.4f / 10-MERGED std=%.4f / reduction (src→merged) = %+.4f\n",
            q126_5src, q126_5new, q126_10, q126_10 - q126_5src))
cat(sprintf("[q15]  5-SOURCE std=%.4f / 5-NEW std=%.4f / 10-MERGED std=%.4f / reduction (src→merged) = %+.4f\n",
            q15_5src, q15_5new, q15_10, q15_10 - q15_5src))

# Stability verdict transition (UNSTABLE → MODERATE → STABLE)
v_5src_q126   <- std_combined[target == "y_tail_q126" & source == "source", stability_verdict]
v_5new_q126   <- std_combined[target == "y_tail_q126" & source == "new",    stability_verdict]
v_10_q126     <- std_combined[target == "y_tail_q126" & source == "merged10", stability_verdict]
transition_q126 <- sprintf("5-SOURCE=%s, 5-NEW=%s, 10-MERGED=%s", v_5src_q126, v_5new_q126, v_10_q126)
cat(sprintf("\n[Verdict transition q126] %s\n", transition_q126))

#==============================================================================
# Step 4: Bootstrap CI on 10-seed mean prediction (observable)
#==============================================================================
cat("\n========== Step 4: Bootstrap CI on 10-seed mean prediction (observable) ==========\n")
ci_table <- mean_dt[, .(label, target, n_obs, n_events_obs, obs_pr_auc, obs_ci_lo, obs_ci_hi)]
cat("\n[Bootstrap CI table (observable)]\n")
print(ci_table)

#==============================================================================
# Step 5: Period-balanced PR-AUC × 3 segments (observable basis)
#==============================================================================
cat("\n========== Step 5: Period-balanced × 3 segments (observable basis) ==========\n")

eval_segment <- function(label, target_col) {
  p <- file.path(TS_DIR, sprintf("predictions_patchtst_v5e_%s_%s.parquet", label, target_col))
  if (!file.exists(p)) return(NULL)
  dt <- as.data.table(read_parquet(p))
  dt[, Date := as.Date(Date)]
  pcol <- intersect(paste0("p_patchtst_v5e_", label), colnames(dt))[1]
  if (is.na(pcol)) pcol <- grep("^p_", colnames(dt), value = TRUE)[1]
  m <- merge(dt[, .SD, .SDcols = c("Date", pcol, "y")],
             tgt_obs[, .(Date, y_obs = get(target_col))], by = "Date", all.x = TRUE)
  setnames(m, pcol, "p_pred")
  res <- list()
  for (si in seq_along(SEGMENTS)) {
    sg <- SEGMENTS[[si]]
    sub <- m[Date >= sg$start & Date <= sg$end & !is.na(p_pred) & !is.na(y_obs)]
    if (nrow(sub) < 30 || sum(sub$y_obs) < 5) {
      res[[length(res) + 1]] <- data.table(
        label = label, target = target_col, segment = sg$name,
        n_obs = nrow(sub), n_events = as.integer(sum(sub$y_obs)),
        base_rate = NA_real_, pr_auc = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
        lift = NA_real_
      )
      next
    }
    ci <- bootstrap_ci_pr(sub$p_pred, sub$y_obs, seed = BOOTSTRAP_SEED + si)
    br <- sum(sub$y_obs) / nrow(sub)
    res[[length(res) + 1]] <- data.table(
      label = label, target = target_col, segment = sg$name,
      n_obs = nrow(sub), n_events = as.integer(sum(sub$y_obs)),
      base_rate = round(br, 4),
      pr_auc = ci$point, ci_lo = ci$lo, ci_hi = ci$hi,
      lift = round(ci$point / br, 3)
    )
  }
  rbindlist(res, fill = TRUE)
}

seg_rows <- list()
for (lab in c("mean5_new", "mean5_source", "mean10")) {
  for (tc in TARGETS) {
    r <- eval_segment(lab, tc)
    if (!is.null(r)) seg_rows[[length(seg_rows) + 1]] <- r
  }
}
seg_dt <- rbindlist(seg_rows, fill = TRUE)

cat("\n[Period-balanced (observable)]\n")
print(seg_dt)

# 3/3 lift > 1 check for q126 — CODEX FIX (HIGH, G_headline_verdict):
# require FULL segment coverage. A high lift on 1/1 or 2/2 segments (with others
# skipped due to n<30 or n_events<5) MUST NOT count as "period robust".
# Robustness requires: all 3 configured segments produce a usable lift AND every
# one passes lift > 1.
q126_mean10_seg <- seg_dt[label == "mean10" & target == "y_tail_q126" & !is.na(lift)]
n_seg_lift_gt1_q126_mean10 <- sum(q126_mean10_seg$lift > 1)
n_seg_total_q126_mean10 <- nrow(q126_mean10_seg)
n_seg_configured <- length(SEGMENTS)
period_robust_q126_mean10 <- (n_seg_total_q126_mean10 == n_seg_configured) &&
  (n_seg_lift_gt1_q126_mean10 == n_seg_configured)
period_full_coverage_q126_mean10 <- (n_seg_total_q126_mean10 == n_seg_configured)

cat(sprintf("\n[Period-balanced 10-seed mean q126] lift>1: %d/%d (configured=%d) → full_coverage=%s robust=%s\n",
            n_seg_lift_gt1_q126_mean10, n_seg_total_q126_mean10, n_seg_configured,
            period_full_coverage_q126_mean10, period_robust_q126_mean10))

#==============================================================================
# Step 6: Strict determinism cross-check
#==============================================================================
cat("\n========== Step 6: Strict determinism cross-check ==========\n")
# NEW seeds [2048, 3000, 5000, 7777, 9999] are DIFFERENT from SOURCE seeds
# (no overlap). So we cannot test "same seed → same prediction" directly.
# Instead, document:
#  (a) NEW per-seed PR-AUC dispersion (strict-det should give bit-identical
#      output if re-run later — but we cannot verify within this run)
#  (b) SOURCE per-seed PR-AUC dispersion (non-strict-det baseline)
#  (c) Whether NEW std is similar/lower/higher than SOURCE std
#      (strict-det should give LOWER variance for same architecture
#       — but the std here is "across SEEDS" not "across runs of same
#       seed", so strict-det effect is NOT directly measurable here.
#       NEW std reflects ARCHITECTURE × SEED variance only.)

strict_det_summary <- list(
  applied_to_new_seeds = TRUE,
  applied_to_source_seeds = FALSE,
  reproducibility_note = paste(
    "Strict-det ensures bit-identical re-runs of the SAME seed.",
    "Since NEW seeds and SOURCE seeds are DIFFERENT, this aggregate cannot",
    "test reproducibility per se. It documents NEW vs SOURCE std dispersion,",
    "which mostly reflects random initialization variance, not strict-det."
  ),
  q126_new_5seed_std = q126_5new,
  q126_source_5seed_std = q126_5src,
  q126_std_diff_new_minus_source = round(q126_5new - q126_5src, 4),
  q15_new_5seed_std = q15_5new,
  q15_source_5seed_std = q15_5src,
  q15_std_diff_new_minus_source = round(q15_5new - q15_5src, 4)
)
cat(sprintf("\n[strict-det q126] NEW std=%.4f / SOURCE std=%.4f / Δ=%+.4f\n",
            q126_5new, q126_5src, q126_5new - q126_5src))
cat(sprintf("[strict-det q15]  NEW std=%.4f / SOURCE std=%.4f / Δ=%+.4f\n",
            q15_5new, q15_5src, q15_5new - q15_5src))

#==============================================================================
# Step 7: Headline verdict (Q-Lead direct)
#==============================================================================
cat("\n========== Step 7: Headline verdict (Q-Lead direct) ==========\n")

# Pull 10-seed mean obs PR-AUC for q126 — CODEX FIX (MINOR): scalar guard.
# data.table subset with no rows returns length-0 vector, which crashes
# `is.na(...)` boolean coercion. Use `length(...) == 1 && !is.na(...)`.
.pull_scalar <- function(x) if (length(x) == 1) x else NA_real_
headline_q126_obs  <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", obs_pr_auc])
headline_q126_orig <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", orig_pr_auc])
headline_q126_ci_lo <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", obs_ci_lo])
headline_q126_ci_hi <- .pull_scalar(mean_dt[label == "mean10" & target == "y_tail_q126", obs_ci_hi])

# Verdict rule:
# HEADLINE_STRONG_VALIDATED: obs PR ≥ 0.50 AND verdict 10-merged in {STABLE, MODERATE}
#                             AND period robust (3/3 lift>1 with FULL coverage — codex HIGH fix)
# HEADLINE_MODERATE: obs PR ∈ [0.40, 0.50)
# HEADLINE_INVALIDATED: obs PR < 0.40
v_q126_10 <- std_combined[target == "y_tail_q126" & source == "merged10", stability_verdict]
if (length(v_q126_10) == 0) v_q126_10 <- NA_character_

if (length(headline_q126_obs) == 1 && !is.na(headline_q126_obs)) {
  if (headline_q126_obs >= 0.50 && v_q126_10 %in% c("STABLE", "MODERATE") && period_robust_q126_mean10) {
    headline_verdict <- "HEADLINE_STRONG_VALIDATED"
    headline_reason <- sprintf(
      "10-seed mean obs PR-AUC=%.4f ≥ 0.50, 10-seed stability=%s, period-robust=%s (%d/%d lift>1)",
      headline_q126_obs, v_q126_10, period_robust_q126_mean10,
      n_seg_lift_gt1_q126_mean10, n_seg_total_q126_mean10
    )
  } else if (headline_q126_obs >= 0.40 && headline_q126_obs < 0.50) {
    headline_verdict <- "HEADLINE_MODERATE"
    headline_reason <- sprintf(
      "10-seed mean obs PR-AUC=%.4f ∈ [0.40, 0.50); 10-seed stability=%s",
      headline_q126_obs, v_q126_10
    )
  } else if (headline_q126_obs < 0.40) {
    headline_verdict <- "HEADLINE_INVALIDATED"
    headline_reason <- sprintf(
      "10-seed mean obs PR-AUC=%.4f < 0.40 (additional cleanup invalidates headline)",
      headline_q126_obs
    )
  } else {
    # Edge case: ≥0.50 but stability=UNSTABLE or period not robust
    headline_verdict <- "HEADLINE_PARTIAL"
    headline_reason <- sprintf(
      "10-seed mean obs PR-AUC=%.4f ≥ 0.50 but stability=%s and period_robust=%s",
      headline_q126_obs, v_q126_10, period_robust_q126_mean10
    )
  }
} else {
  headline_verdict <- "HEADLINE_UNAVAILABLE"
  headline_reason <- "10-seed mean prediction not computed (file missing)"
}

cat(sprintf("\n[HEADLINE VERDICT] %s\n", headline_verdict))
cat(sprintf("[REASON] %s\n", headline_reason))

#==============================================================================
# Step 8: NEW_CYCLE_CHECKLIST
#==============================================================================
cat("\n========== Step 8: NEW_CYCLE_CHECKLIST ==========\n")
checklist <- list(
  M1_bear_date_audit = "PASS (pre-cycle 4/4, qepm/observability/sanity_checks/bear_date_audit_20260521_100612.json)",
  M2_validate_label_direction = "PASS (forward labels via Cycle 50 fix + 53H/54C inherit; targets_long_horizon.parquet)",
  M3_PIT_C1_C15 = "PASS (v5e panel PIT validated Cycle 53H; US macro lag1 PIT verified Cycle 47B)",
  M4_shift_convention = "PASS (forward targets via shift(.,n=H,'lead'); inherited)",
  M4b_observable_labels = "PASS (cycle 54D targets_long_horizon_observable.parquet — NaN tail propagated)",
  M5_AX_008 = "EXEMPT (Forge multi-seed audit + Codex code review only; NOT admit cycle)",
  S1_PRAUC_sanity_q126_obs10 = if (!is.na(headline_q126_obs) && headline_q126_obs <= 0.55) {
    sprintf("PASS (10-seed obs PR-AUC=%.4f within plausible q126 range)", headline_q126_obs)
  } else if (!is.na(headline_q126_obs)) {
    sprintf("WARN_HIGH (obs PR-AUC=%.4f > 0.55, consider repeat sanity)", headline_q126_obs)
  } else {
    "FAIL (10-seed obs PR-AUC unavailable)"
  },
  S2_COVID_spot_check = "PASS (targets_long_horizon_observable 2020-02-19 ret_q126 finite + bear_date_audit 4/4)",
  S3_multiseed_stability_q126_10seed = sprintf("%s (std=%.4f)", v_q126_10, q126_10),
  S3_multiseed_stability_q126_5src   = sprintf("%s (std=%.4f, baseline)", v_5src_q126, q126_5src),
  S3_multiseed_stability_q126_5new   = sprintf("%s (std=%.4f, strict-det)", v_5new_q126, q126_5new),
  S4_period_balanced_q126_10seed = sprintf("%d/%d segments lift>1 (10-seed mean, observable)",
                                            n_seg_lift_gt1_q126_mean10, n_seg_total_q126_mean10),
  A1_cross_cycle_same_forward_labels = "PASS (54E + 54C + 53H + 53B all use targets_long_horizon.parquet)",
  A2_dohun_audit_checkpoint = "AWAITING_REVIEW (Q-Lead self-verdict)",
  A3_codex_critic = "CODE_REVIEW_ONLY (Q-Lead direct mandate 2026-05-21; scope = code correctness)"
)

cat("\n[NEW_CYCLE_CHECKLIST]\n")
for (k in names(checklist)) cat(sprintf("  %s: %s\n", k, checklist[[k]]))

#==============================================================================
# Step 9: Output JSON + chart
#==============================================================================
cat("\n========== Step 9: Output JSON + chart ==========\n")

# Next cycle suggestion (Q-Lead direct)
if (headline_verdict == "HEADLINE_STRONG_VALIDATED") {
  next_cycle_suggestion <- paste(
    "STRONG_VALIDATED_PATH: (1) Architect 3rd-source verification (AX-008 P1 admit pathway):",
    "exact reproduction of 10-seed mean PR-AUC via independent re-implementation.",
    "(2) Calibration analysis (Brier + reliability curves) on 10-seed mean for actionability.",
    "(3) Cross-architecture diversity (TimeMixer / iTransformer / N-BEATS-X 5-seed × 3-arch)",
    "to confirm robustness beyond PatchTST."
  )
} else if (headline_verdict == "HEADLINE_MODERATE") {
  next_cycle_suggestion <- paste(
    "MODERATE_PATH: (1) Calibration analysis on 10-seed mean to identify saturation/collapse zones.",
    "(2) Period-balanced robustness check (S2018-19 / S2020-21 / S2022-24 + S2025-26 holdout).",
    "(3) Cross-architecture seed × arch 3x3 mini-grid (PatchTST / iTransformer / TimeMixer)",
    "to disentangle architecture effect from random initialization."
  )
} else if (headline_verdict == "HEADLINE_INVALIDATED") {
  next_cycle_suggestion <- paste(
    "INVALIDATED_PATH: (1) Root-cause analysis on 53H 0.4012 vs 10-seed obs ΔPR-AUC source.",
    "(2) Feature panel inspection — which subset is seed-sensitive (74 features)?",
    "(3) Regularization tuning (dropout 0.30 → 0.40 + weight_decay 5e-3 → 1e-2) to reduce variance.",
    "(4) Cycle 53B baseline (v4a 70 features w/o US macro) 10-seed re-audit for control."
  )
} else {
  next_cycle_suggestion <- "Cycle 54E unable to produce verdict — re-run Python script and re-aggregate."
}

verdict_json <- list(
  cycle = "54E_10seed_strict_observable",
  approach = "5_NEW_strict_det_plus_5_SOURCE_54C_reused_observable_aggregate",
  hypothesis = paste(
    "54C UNSTABLE std=0.0787 (5-seed) on q126 → expected MODERATE/STABLE transition",
    "at 10-seed merged. Observable-only labels (54D) preserve headline."
  ),
  panel = "feature_panel_v5e_q126_usmacro.parquet",
  targets_source = "targets_long_horizon.parquet",
  targets_observable = "targets_long_horizon_observable.parquet (54D)",
  n_features = 74,
  new_seeds = NEW_SEEDS,
  source_54c_seeds = SOURCE_SEEDS,
  all_seeds_10 = ALL_SEEDS_10,
  forward_labels = TRUE,
  validation_strategy = "walk_forward_expanding_5_fold_CV",
  oos_window = list(start = as.character(OOS_START), end = as.character(OOS_END)),
  baselines = list(
    cycle_53H_seed42_y_tail_q126_orig = CYCLE_53H_Q126,
    cycle_54C_5seed_y_tail_q126_orig = CYCLE_54C_5SEED_Q126,
    cycle_54C_5seed_std_q126_orig = CYCLE_54C_5SEED_STD_Q126,
    cycle_53H_seed42_y_tail_q15_orig = CYCLE_53H_Q15,
    cycle_54C_5seed_y_tail_q15_orig = CYCLE_54C_5SEED_Q15,
    v13_forward_baseline = V13_FORWARD_BASELINE
  ),
  per_seed_table = lapply(seq_len(nrow(per_seed_dt)), function(i) {
    r <- per_seed_dt[i]
    list(
      seed = r$seed, target = r$target, source = r$source,
      n_obs = r$n_obs, n_events_orig = r$n_events_orig, n_events_obs = r$n_events_obs,
      n_phantom_excluded = r$n_phantom_excluded,
      orig_pr_auc = r$orig_pr_auc, obs_pr_auc = r$obs_pr_auc,
      delta_pr = r$delta_pr, orig_ic = r$orig_ic, obs_ic = r$obs_ic,
      p_max = r$p_max, p_p99 = r$p_p99, p_mean = r$p_mean,
      logit_median = r$logit_median, detected_collapse = r$detected_collapse,
      collapsed = r$collapsed, all_collapsed = r$all_collapsed
    )
  }),
  collapse_audit_summary = list(
    detector_criteria = "p_max < 1e-4 AND logit_median < -15",
    q126_new_collapsed = n_collapsed_new_q126,
    q126_new_borderline = n_borderline_new_q126,
    q126_source_collapsed = n_collapsed_source_q126,
    q126_source_borderline = n_borderline_source_q126,
    collapsed_seeds_q126_source = lapply(seq_len(nrow(collapsed_seeds[target == "y_tail_q126" & source == "source"])),
      function(i) {
        r <- collapsed_seeds[target == "y_tail_q126" & source == "source"][i]
        list(seed = r$seed, p_max = r$p_max, logit_median = r$logit_median, obs_pr_auc = r$obs_pr_auc)
      }),
    collapsed_seeds_q126_new = lapply(seq_len(nrow(collapsed_seeds[target == "y_tail_q126" & source == "new"])),
      function(i) {
        r <- collapsed_seeds[target == "y_tail_q126" & source == "new"][i]
        list(seed = r$seed, p_max = r$p_max, logit_median = r$logit_median, obs_pr_auc = r$obs_pr_auc)
      }),
    borderline_seeds_q126_source = lapply(seq_len(nrow(borderline_seeds[target == "y_tail_q126" & source == "source"])),
      function(i) {
        r <- borderline_seeds[target == "y_tail_q126" & source == "source"][i]
        list(seed = r$seed, p_max = r$p_max, logit_median = r$logit_median, obs_pr_auc = r$obs_pr_auc)
      }),
    interpretation = paste(
      "Cycle 54C SOURCE seeds were NOT run with collapse detector — collapsed seeds entered",
      "the 5-seed mean without rescue. Cycle 54E NEW seeds DO use collapse detector + reseed",
      "rescue (139 FIXED inherit). The 10-seed mean PR-AUC is reported as-is but PR-AUC is a",
      "ranking-only metric — collapsed seeds contribute ~0 to the mean and shrink it uniformly",
      "without breaking ranking. For sound interpretation, also consider the 'clean 10-seed mean'",
      "computed downstream (collapsed-excluded subset, if applicable)."
    )
  ),
  mean_prediction_table = lapply(seq_len(nrow(mean_dt)), function(i) {
    r <- mean_dt[i]
    list(
      label = r$label, target = r$target,
      n_obs = r$n_obs, n_events_obs = r$n_events_obs, n_phantom_excluded = r$n_phantom_excluded,
      orig_pr_auc = r$orig_pr_auc, obs_pr_auc = r$obs_pr_auc,
      delta_pr = r$delta_pr, orig_ic = r$orig_ic, obs_ic = r$obs_ic,
      obs_ci_lo = r$obs_ci_lo, obs_ci_hi = r$obs_ci_hi,
      per_date_std_mean = r$per_date_std_mean,
      per_date_std_median = r$per_date_std_median,
      per_date_std_max = r$per_date_std_max,
      n_seeds = r$n_seeds
    )
  }),
  std_reduction = list(
    q126_5_source = q126_5src,
    q126_5_new_strict = q126_5new,
    q126_10_merged = q126_10,
    q126_reduction_src_to_merged = round(q126_10 - q126_5src, 4),
    q126_verdict_5src = v_5src_q126,
    q126_verdict_5new = v_5new_q126,
    q126_verdict_10 = v_q126_10,
    q15_5_source = q15_5src,
    q15_5_new_strict = q15_5new,
    q15_10_merged = q15_10,
    q15_reduction_src_to_merged = round(q15_10 - q15_5src, 4)
  ),
  period_balanced = list(
    segments = lapply(SEGMENTS, function(sg) list(name = sg$name,
                                                  start = as.character(sg$start),
                                                  end = as.character(sg$end))),
    bootstrap_n = BOOTSTRAP_N,
    table = lapply(seq_len(nrow(seg_dt)), function(i) {
      r <- seg_dt[i]
      list(label = r$label, target = r$target, segment = r$segment,
           n_obs = r$n_obs, n_events = r$n_events,
           base_rate = r$base_rate, pr_auc = r$pr_auc,
           ci_lo = r$ci_lo, ci_hi = r$ci_hi, lift = r$lift)
    }),
    period_robust_q126_mean10 = period_robust_q126_mean10,
    period_full_coverage_q126_mean10 = period_full_coverage_q126_mean10,
    n_seg_lift_gt1_q126_mean10 = n_seg_lift_gt1_q126_mean10,
    n_seg_total_q126_mean10 = n_seg_total_q126_mean10,
    n_seg_configured = n_seg_configured,
    codex_fix_note = "Robustness predicate strengthened (codex HIGH 2026-05-21): now requires full segment coverage (3/3 configured) AND 3/3 lift>1."
  ),
  strict_determinism = strict_det_summary,
  observable_labels_impact = list(
    n_phantom_excluded_per_seed = mean(per_seed_dt$n_phantom_excluded, na.rm = TRUE),
    median_delta_pr = round(median(per_seed_dt$delta_pr, na.rm = TRUE), 4),
    cycle_53h_orig_to_obs_seed42_q126 = round(
      per_seed_dt[seed == 42L & target == "y_tail_q126" & source == "source", delta_pr], 4)
  ),
  headline = list(
    verdict = headline_verdict,
    reason = headline_reason,
    q126_obs_pr_auc_10seed_mean = headline_q126_obs,
    q126_orig_pr_auc_10seed_mean = headline_q126_orig,
    q126_obs_ci_lo = headline_q126_ci_lo,
    q126_obs_ci_hi = headline_q126_ci_hi
  ),
  next_cycle_suggestion = next_cycle_suggestion,
  new_cycle_checklist = checklist,
  python_provenance = py_prov,
  python_seed_variance_audit_summary = list(
    new_seeds_per_seed_pr_q126 = py_audit$audit_per_target$y_tail_q126$mean5_new$per_seed_pr_auc,
    new_seeds_per_seed_pr_q15  = py_audit$audit_per_target$y_tail_q15$mean5_new$per_seed_pr_auc,
    source_seeds_per_seed_pr_q126 = py_audit$audit_per_target$y_tail_q126$mean5_source$per_seed_pr_auc,
    source_seeds_per_seed_pr_q15  = py_audit$audit_per_target$y_tail_q15$mean5_source$per_seed_pr_auc,
    mean10_pr_q126_orig_python = py_audit$audit_per_target$y_tail_q126$mean10$mean_prediction_pr_auc,
    mean10_pr_q15_orig_python  = py_audit$audit_per_target$y_tail_q15$mean10$mean_prediction_pr_auc
  ),
  outputs = list(
    multiseed_dir = TS_DIR,
    final_json = file.path(EVAL_DIR, "cycle54e_10seed_strict_observable.json"),
    chart = file.path(CHART_DIR, "156_10seed_strict_observable.png")
  )
)

out_json <- file.path(EVAL_DIR, "cycle54e_10seed_strict_observable.json")
write_json(verdict_json, out_json, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("\n[Final JSON] Saved: %s\n", out_json))

#==============================================================================
# Chart (4 panels)
#==============================================================================

# Panel A: Per-seed observable PR-AUC by source (NEW vs SOURCE)
chartA_data <- per_seed_dt[!is.na(obs_pr_auc)]
chartA_data[, seed_label := factor(seed)]
chartA_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15 (sec)", "y_tail_q126 (primary)"))]
chartA_data[, source_label := factor(source, levels = c("source", "new"),
                                     labels = c("54C SOURCE 5 (non-strict-det)",
                                                "54E NEW 5 (strict-det)"))]

pA <- ggplot(chartA_data, aes(x = seed_label, y = obs_pr_auc, fill = source_label)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.3f", obs_pr_auc)), vjust = -0.5, size = 2.8) +
  facet_grid(target_label ~ source_label, scales = "free", space = "free_x") +
  geom_hline(data = data.table(target_label = factor(c("y_tail_q15 (sec)", "y_tail_q126 (primary)")),
                               ref = c(CYCLE_53H_Q15, CYCLE_53H_Q126)),
             aes(yintercept = ref), linetype = "dashed", color = "red", linewidth = 0.5) +
  scale_fill_brewer(palette = "Set2") +
  labs(title = "Cycle 54E — Per-seed Observable PR-AUC (NEW strict-det vs SOURCE 54C reused)",
       subtitle = sprintf("Red dashed = 53H seed=42 reference (q126=%.4f / q15=%.4f)",
                          CYCLE_53H_Q126, CYCLE_53H_Q15),
       x = "Seed", y = "Observable OOS PR-AUC", fill = NULL) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom",
        strip.text = element_text(face = "bold", size = 9),
        axis.text.x = element_text(angle = 35, hjust = 1, size = 9))

# Panel B: Std reduction bar (5-NEW / 5-SOURCE / 10-MERGED) for q126 + q15
chartB_data <- std_combined[order(target, source)]
chartB_data[, source_label := factor(source,
                                     levels = c("source", "new", "merged10"),
                                     labels = c("5 SOURCE", "5 NEW", "10 MERGED"))]
chartB_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15", "y_tail_q126"))]

pB <- ggplot(chartB_data, aes(x = source_label, y = std_pr, fill = stability_verdict)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = sprintf("%.4f", std_pr)), vjust = -0.5, size = 3) +
  facet_wrap(~ target_label, ncol = 2) +
  scale_fill_manual(values = c("STABLE" = "#1b7837", "MODERATE" = "#fdae61", "UNSTABLE" = "#d73027")) +
  geom_hline(yintercept = STABILITY_STABLE_STD, linetype = "dotted", color = "#1b7837", linewidth = 0.4) +
  geom_hline(yintercept = STABILITY_MODERATE_STD, linetype = "dotted", color = "#fdae61", linewidth = 0.4) +
  labs(title = "Std Reduction Audit (UNSTABLE → MODERATE transition test)",
       subtitle = sprintf("Dotted: STABLE %.2f / MODERATE %.2f thresholds",
                          STABILITY_STABLE_STD, STABILITY_MODERATE_STD),
       x = NULL, y = "OOS PR-AUC std across seeds", fill = "Stability") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        strip.text = element_text(face = "bold"))

# Panel C: Mean prediction PR-AUC obs/orig (3 labels × 2 targets)
chartC_data <- copy(mean_dt[, .(label, target, orig_pr_auc, obs_pr_auc, obs_ci_lo, obs_ci_hi)])
chartC_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15", "y_tail_q126"))]
chartC_data[, label_label := factor(label, levels = c("mean5_new", "mean5_source", "mean10"),
                                    labels = c("5-NEW (strict)", "5-SOURCE (54C)", "10-MERGED"))]

pC <- ggplot(chartC_data, aes(x = label_label)) +
  geom_col(aes(y = obs_pr_auc, fill = "Observable"), width = 0.5,
           position = position_nudge(x = -0.15)) +
  geom_col(aes(y = orig_pr_auc, fill = "Original"), width = 0.5,
           position = position_nudge(x = 0.15)) +
  geom_errorbar(aes(ymin = obs_ci_lo, ymax = obs_ci_hi), width = 0.15,
                position = position_nudge(x = -0.15), linewidth = 0.4) +
  geom_text(aes(y = obs_pr_auc, label = sprintf("%.3f", obs_pr_auc)),
            position = position_nudge(x = -0.15), vjust = -0.4, size = 2.7) +
  geom_text(aes(y = orig_pr_auc, label = sprintf("%.3f", orig_pr_auc)),
            position = position_nudge(x = 0.15), vjust = -0.4, size = 2.7) +
  facet_wrap(~ target_label, ncol = 2, scales = "free_y") +
  scale_fill_manual(values = c("Observable" = "#2166ac", "Original" = "#bababa")) +
  labs(title = "Mean Prediction PR-AUC (Observable + 95% CI vs Original)",
       subtitle = "Observable = NaN-tail propagated (54D); Original = NaN→0",
       x = NULL, y = "OOS PR-AUC", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        strip.text = element_text(face = "bold"),
        axis.text.x = element_text(angle = 20, hjust = 1))

# Panel D: Period-balanced 10-seed mean lift (q126 + q15)
chartD_data <- seg_dt[label == "mean10" & !is.na(lift)]
chartD_data[, target_label := factor(target,
                                     levels = TARGETS,
                                     labels = c("y_tail_q15", "y_tail_q126"))]

pD <- ggplot(chartD_data, aes(x = segment, y = lift, fill = target_label)) +
  geom_col(width = 0.6, position = position_dodge(width = 0.7)) +
  geom_text(aes(label = sprintf("%.2fx", lift)),
            position = position_dodge(width = 0.7), vjust = -0.5, size = 3) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "red", linewidth = 0.5) +
  facet_wrap(~ target_label, ncol = 2, scales = "free_y") +
  scale_fill_brewer(palette = "Set1") +
  labs(title = "Period-balanced lift of 10-seed mean prediction (vs base rate)",
       subtitle = "Red dashed = lift=1 (chance); higher = better than chance",
       x = NULL, y = "Lift (PR-AUC / base_rate)", fill = NULL) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold"),
        axis.text.x = element_text(angle = 25, hjust = 1))

# Combine
chart_combined <- (pA / pB) | (pC / pD) +
  plot_layout(widths = c(1.2, 1)) +
  plot_annotation(
    title = sprintf("Cycle 54E — PatchTST v5e q126 10-seed strict-det merge (5 NEW + 5 SOURCE)"),
    subtitle = sprintf("HEADLINE: %s | 10-seed obs PR-AUC=%.4f | stability=%s | period-robust=%s",
                       headline_verdict, headline_q126_obs, v_q126_10, period_robust_q126_mean10),
    theme = theme(plot.title = element_text(face = "bold", size = 14),
                  plot.subtitle = element_text(size = 11))
  )

chart_path <- file.path(CHART_DIR, "156_10seed_strict_observable.png")
ggsave(chart_path, chart_combined, width = 18, height = 12, dpi = 130)
cat(sprintf("\n[Chart] Saved: %s\n", chart_path))

cat("\n", strrep("=", 70), "\n", sep = "")
cat("[Cycle 54E R aggregate DONE]\n")
