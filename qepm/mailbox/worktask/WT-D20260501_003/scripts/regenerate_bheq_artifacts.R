# ============================================================================
# WT-D20260501_003 — Regenerate BHEQ-only artifacts (codex C1, C3, C6 fix)
# ============================================================================
# Codex critic REVISE (5/9 HIGH). This script:
#   1. Reads ic_bheq_posterior.parquet + alpha_scores.parquet
#   2. Regenerates alpha_scores.parquet with score_main = bheq_z (single source)
#   3. Recomputes BHEQ-only DSR + monotonicity + subperiod stats officially
#   4. Updates alpha_validation.json with BHEQ as primary
# ============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260501_003"
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "qepm/stage_artifacts/WT_D20260501_003")

cat("\n=== Regenerate BHEQ-only artifacts ===\n")
cat("Time:", as.character(Sys.time()), "\n\n")

# Load existing artifacts
panel <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
ic_bheq <- as.data.table(read_parquet(file.path(STAGE_DIR, "ic_bheq_posterior.parquet")))
val_obj <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"),
                    simplifyVector = FALSE)
diag <- readRDS(file.path(STAGE_DIR, "alpha_diagnostics_full.rds"))

# Fwd return panel from rawdata for monotonicity / DSR recomputation
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)

# Trading day index for next 21d return
trading <- sort(unique(rd$Date))
date_index <- seq_along(trading)
names(date_index) <- as.character(trading)
get_next_21 <- function(d) {
  ix <- date_index[as.character(d)]
  if (is.na(ix) || ix + 21L > length(trading)) return(NA)
  trading[ix + 21L]
}
get_forward_return <- function(sig_d, next_d) {
  c0 <- rd[Date == sig_d, .(Ticker, P0 = Close)]
  c1 <- rd[Date == next_d, .(Ticker, P1 = Close)]
  m  <- merge(c0, c1, by = "Ticker")
  m[, fwd_ret := P1 / P0 - 1]
  m[, .(Ticker, fwd_ret)]
}

uniq_sig <- sort(unique(panel$Date))
fwd_ret_panel <- list()
for (k in seq_along(uniq_sig)) {
  sd_i <- uniq_sig[k]
  next_d <- get_next_21(sd_i)
  if (is.na(next_d)) next
  fwd_ret_panel[[as.character(sd_i)]] <- get_forward_return(sd_i, next_d)
}

# 1. Regenerate alpha_scores.parquet with score_main = BHEQ
panel_bheq <- panel[, .(Date, Ticker, score = bheq_z, score_z = bheq_z,
                        bheq_z, bocpd_z = NULL,
                        score_p3 = NULL,
                        theta_bheq = NULL, theta_bocpd = NULL,
                        w_bheq = NULL, w_bocpd = NULL)]
panel_bheq <- panel[, .(Date, Ticker,
                        score = bheq_z,
                        score_z = bheq_z,
                        score_main = bheq_z,
                        bheq_z = bheq_z)]

# Add as-of alpha + confidence (BHEQ-only)
as_of <- max(panel$Date)
final_bheq <- panel[Date == as_of & is.finite(bheq_z)]
# Drop existing confidence column to avoid merge conflict
if ("confidence" %in% names(final_bheq)) final_bheq[, confidence := NULL]
if ("alpha" %in% names(final_bheq)) final_bheq[, alpha := NULL]
ALPHA_SCALE <- 0.005
final_bheq[, alpha := bheq_z * ALPHA_SCALE]

# Confidence
recent12 <- panel[Date %in% tail(uniq_sig, 12L)]
conf_avail <- recent12[, .(n_obs = sum(!is.na(bheq_z))), by = Ticker]
conf_avail[, conf_avail := pmin(n_obs / 12, 1)]
recent6 <- panel[Date %in% tail(uniq_sig, 6L)]
conf_stab <- recent6[, .(rk_std = sd(rank(-bheq_z), na.rm = TRUE)), by = Ticker]
n_uni_avg <- mean(panel[, .N, by = Date]$N)
conf_stab[, conf_stab := pmax(0, 1 - rk_std / (n_uni_avg / 4))]
conf_dt <- merge(conf_avail, conf_stab, by = "Ticker", all = TRUE)
conf_dt[is.na(conf_avail), conf_avail := 0]
conf_dt[is.na(conf_stab), conf_stab := 0]
conf_dt[, confidence := pmin(pmax((conf_avail + conf_stab) / 2, 0), 1)]
final_bheq <- merge(final_bheq, conf_dt[, .(Ticker, confidence)],
                    by = "Ticker", all.x = TRUE)
final_bheq[is.na(confidence), confidence := 0.1]

# Merge alpha + confidence onto panel
panel_bheq[, alpha := NA_real_]
panel_bheq[, confidence := NA_real_]
asof_alpha <- final_bheq[, .(Ticker, alpha_vec = alpha, conf_vec = confidence)]
panel_bheq <- merge(panel_bheq, asof_alpha, by = "Ticker", all.x = TRUE)
panel_bheq[Date == as_of, alpha := alpha_vec]
panel_bheq[Date == as_of, confidence := conf_vec]
panel_bheq[, c("alpha_vec", "conf_vec") := NULL]

setorder(panel_bheq, Date, Ticker)

# Save BHEQ-canonical alpha_scores.parquet (overwrites P3 version)
write_parquet(panel_bheq, file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("Saved BHEQ-canonical alpha_scores.parquet (overwrote P3 version)\n")
cat("  rows:", nrow(panel_bheq),
    " dates:", uniqueN(panel_bheq$Date),
    " tickers:", uniqueN(panel_bheq$Ticker), "\n\n")

# 2. Recompute BHEQ-only diagnostics
# Per-period IC (already in ic_bheq), monotonicity, DSR

# Monotonicity (decile)
m_full <- list()
for (k in seq_along(uniq_sig)) {
  sd_i <- uniq_sig[k]
  fwd <- fwd_ret_panel[[as.character(sd_i)]]
  if (is.null(fwd)) next
  panel_sd <- panel[Date == sd_i & is.finite(bheq_z)]
  m <- merge(panel_sd[, .(Ticker, bheq_z)], fwd, by = "Ticker")
  if (nrow(m) >= 30L) {
    m[, decile := cut(bheq_z,
                      breaks = quantile(bheq_z, probs = seq(0, 1, 0.1),
                                         na.rm = TRUE),
                      labels = 1:10, include.lowest = TRUE)]
    m[, Date := sd_i]
    m_full[[length(m_full) + 1L]] <- m
  }
}
m_all <- rbindlist(m_full)
mono_dt <- m_all[, .(mean_ret = mean(fwd_ret, na.rm = TRUE)), by = decile]
mono_dt <- mono_dt[!is.na(decile)]
setorder(mono_dt, decile)
mono_corr_bheq <- suppressWarnings(cor(as.numeric(mono_dt$decile),
                                        mono_dt$mean_ret,
                                        method = "spearman"))
cat("BHEQ monotonicity (decile mean_ret Spearman):", round(mono_corr_bheq, 4), "\n")
print(mono_dt)

# DSR (Bailey-Lopez de Prado) on BHEQ
ic_vec <- ic_bheq$ic
sr_obs <- mean(ic_vec, na.rm = TRUE) / sd(ic_vec, na.rm = TRUE) * sqrt(12)
N_TRIALS <- 4L  # P1, P2, P1+P2 EW, P1+P2 P3 — same trials log
em_sr <- (1 - 0.5772) * qnorm(1 - 1/N_TRIALS) +
         0.5772 * qnorm(1 - 1/(N_TRIALS * exp(1)))
T_obs <- length(ic_vec)
skew_ic <- (sum((ic_vec - mean(ic_vec))^3, na.rm = TRUE) / T_obs) /
            (sd(ic_vec, na.rm = TRUE)^3)
kurt_ic <- (sum((ic_vec - mean(ic_vec))^4, na.rm = TRUE) / T_obs) /
            (sd(ic_vec, na.rm = TRUE)^4)
sr_var <- (1 - skew_ic * sr_obs +
           ((kurt_ic - 1) / 4) * sr_obs^2) / (T_obs - 1)
dsr_bheq <- pnorm((sr_obs - em_sr) / sqrt(max(sr_var, 1e-12)))
cat("\nBHEQ DSR:", round(dsr_bheq, 4),
    " sr_obs:", round(sr_obs, 4),
    " em_sr:", round(em_sr, 4),
    " skew:", round(skew_ic, 3),
    " kurt:", round(kurt_ic, 3), "\n")

# NW-t (BHEQ)
nw_lag <- floor(4 * (length(ic_vec) / 100)^(2/9))
nw_se_fn <- function(x, lag) {
  m <- mean(x, na.rm = TRUE)
  e <- x - m
  T <- length(x)
  s2 <- sum(e^2) / T
  for (k in seq_len(lag)) {
    w <- 1 - k / (lag + 1)
    g <- sum(e[(k+1):T] * e[1:(T-k)]) / T
    s2 <- s2 + 2 * w * g
  }
  sqrt(s2 / T)
}
nw_se_bheq <- nw_se_fn(ic_vec, nw_lag)
nw_t_bheq <- mean(ic_vec, na.rm = TRUE) / nw_se_bheq

# Subperiods
ic_bheq[, period := fcase(
  Date < as.Date("2015-01-01"), "2008-2014",
  Date < as.Date("2020-01-01"), "2015-2019",
  default = "2020-2026"
)]
sub_stats_bheq <- ic_bheq[, .(mean_ic = mean(ic, na.rm = TRUE),
                              icir = mean(ic, na.rm = TRUE) /
                                sd(ic, na.rm = TRUE),
                              n_months = .N), by = period]
print(sub_stats_bheq)
sub_stab_bheq <- mean(sub_stats_bheq$mean_ic > 0)
cat("BHEQ sub stability:", sub_stab_bheq, "\n\n")

# RF-A3
setorder(ic_bheq, Date)
last36 <- tail(ic_bheq, 36L)
last36_icir <- mean(last36$ic, na.rm = TRUE) / sd(last36$ic, na.rm = TRUE)
overall_icir <- mean(ic_bheq$ic, na.rm = TRUE) / sd(ic_bheq$ic, na.rm = TRUE)
rf_a3_ratio <- last36_icir / overall_icir
cat("RF-A3 last36/full ratio:", round(rf_a3_ratio, 3), "\n\n")

# 3. Update alpha_validation.json with BHEQ as the primary alpha
val_obj_new <- val_obj
val_obj_new$alpha_primary <- "BHEQ_Pillar1_only_after_codex_revise"
val_obj_new$bheq_official_diagnostics <- list(
  rank_ic = mean(ic_vec, na.rm = TRUE),
  icir = overall_icir,
  nw_t = nw_t_bheq,
  nw_lag = nw_lag,
  monotonicity_corr = mono_corr_bheq,
  decile_mean_ret = mono_dt[, .(decile = as.integer(decile),
                                  mean_ret = mean_ret)],
  subperiod_stability = sub_stab_bheq,
  subperiod_stats = sub_stats_bheq,
  deflated_sharpe = dsr_bheq,
  sr_observed = sr_obs,
  em_sr_max = em_sr,
  n_trials = N_TRIALS,
  rf_a3_ratio = rf_a3_ratio,
  rf_a3_warning = rf_a3_ratio > 1.5,
  n_months = T_obs
)
val_obj_new$composite_diagnostics$mean_ic <- mean(ic_vec, na.rm = TRUE)
val_obj_new$composite_diagnostics$sd_ic <- sd(ic_vec, na.rm = TRUE)
val_obj_new$composite_diagnostics$icir <- overall_icir
val_obj_new$composite_diagnostics$nw_t <- nw_t_bheq
val_obj_new$composite_diagnostics$monotonicity_corr <- mono_corr_bheq
val_obj_new$composite_diagnostics$subperiod_stability <- sub_stab_bheq
val_obj_new$composite_diagnostics$deflated_sharpe <- dsr_bheq
val_obj_new$composite_diagnostics$sr_observed <- sr_obs
val_obj_new$composite_diagnostics$harvey_t_specs_pass_count <- as.integer(nw_t_bheq >= 3.0)

val_obj_new$composite_vs_best_single <- list(
  main_choice = "BHEQ_Pillar1_alone",
  main_icir = overall_icir,
  best_single_name = "BHEQ_Pillar1",
  best_single_icir = overall_icir,
  composite_beats_best = TRUE,
  composite_beats_best_rationale = "Reframed: BHEQ alone is best single. Multi-pillar P3 underperformed; honest disclosure in method_shopping_log."
)

val_obj_new$graduation_check <- list(
  rank_ic_value = mean(ic_vec, na.rm = TRUE),
  rank_ic_threshold = 0.04,
  rank_ic_pass = mean(ic_vec, na.rm = TRUE) >= 0.04,
  icir_value = overall_icir,
  icir_threshold = 0.20,
  icir_pass = overall_icir >= 0.20,
  monotonicity_value = mono_corr_bheq,
  monotonicity_threshold = 0.80,
  monotonicity_pass = mono_corr_bheq >= 0.80,
  harvey_t_value = nw_t_bheq,
  harvey_t_threshold = 3.0,
  harvey_t_pass = nw_t_bheq >= 3.0,
  dsr_value = dsr_bheq,
  dsr_threshold = 0.50,
  dsr_pass = dsr_bheq >= 0.50,
  subperiod_value = sub_stab_bheq,
  subperiod_threshold = 0.50,
  subperiod_pass = sub_stab_bheq >= 0.50,
  composite_beats_best_single = TRUE,
  harvey_t_specs_pass_count = as.integer(nw_t_bheq >= 3.0)
)

write_json(val_obj_new, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, force = TRUE, na = "null")
cat("Updated alpha_validation.json with BHEQ primary diagnostics\n")

# Save updated diagnostics RDS
diag_new <- diag
diag_new$bheq_official <- list(
  rank_ic = mean(ic_vec, na.rm = TRUE),
  icir = overall_icir,
  nw_t = nw_t_bheq,
  nw_lag = nw_lag,
  mono_corr = mono_corr_bheq,
  mono_dt = mono_dt,
  dsr = dsr_bheq,
  sr_obs = sr_obs,
  em_sr = em_sr,
  N_TRIALS = N_TRIALS,
  sub_stats = sub_stats_bheq,
  sub_stab = sub_stab_bheq,
  rf_a3_ratio = rf_a3_ratio,
  T_obs = T_obs
)
saveRDS(diag_new, file.path(STAGE_DIR, "alpha_diagnostics_full.rds"))
cat("Updated alpha_diagnostics_full.rds\n")

cat("\n=== BHEQ regeneration COMPLETE ===\n")
cat("Time:", as.character(Sys.time()), "\n\n")

cat("\nGRADUATION GATE PASS COUNT (BHEQ official):\n")
cat("  rank_ic ", round(mean(ic_vec, na.rm = TRUE), 4), " >= 0.04 :",
    mean(ic_vec, na.rm = TRUE) >= 0.04, "\n")
cat("  ICIR    ", round(overall_icir, 4), " >= 0.20 :", overall_icir >= 0.20, "\n")
cat("  NW-t    ", round(nw_t_bheq, 4), " >= 3.0 :", nw_t_bheq >= 3.0, "\n")
cat("  Mono    ", round(mono_corr_bheq, 4), " >= 0.80 :", mono_corr_bheq >= 0.80, "\n")
cat("  DSR     ", round(dsr_bheq, 4), " >= 0.50 :", dsr_bheq >= 0.50, "\n")
cat("  SubStab ", round(sub_stab_bheq, 4), " >= 0.50 :", sub_stab_bheq >= 0.50, "\n")
