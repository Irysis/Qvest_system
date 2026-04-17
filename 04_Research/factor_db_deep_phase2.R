cat("=== Factor DB Deep Analysis Phase 2 (Regime Synergy + Lifespan + Discard) ===\n")
cat("Start:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
CACHE <- file.path(PROJ, ".cache/factor_db")
OUT   <- file.path(PROJ, "qepm/mailbox/qlead/inbox")

# Load IC data
ic_raw <- as.data.table(read_parquet(file.path(CACHE, "factor_ic_monthly.parquet")))
ic_raw[, Date := as.Date(Date)]
ic_wide <- dcast(ic_raw, Date ~ Factor_Name, value.var = "IC")
dates <- ic_wide$Date
ic_mat <- as.matrix(ic_wide[, -"Date"])
miss_pct <- colMeans(is.na(ic_mat))
keep <- miss_pct < 0.5
ic_mat <- ic_mat[, keep]
ic_mat[is.na(ic_mat)] <- 0
n_factors <- ncol(ic_mat)

# ======================================================================
# 4. Regime-conditional synergy factor pairs
# ======================================================================
cat("[4] Regime-conditional synergy analysis...\n")

regime_dt <- as.data.table(read_parquet(file.path(PROJ, ".cache/regime_v7.parquet")))
# regime_v7: apply_month = "YYYY-MM", regime_state = "Normal"/"Elevated"/"Crisis"
regime_dt[, ym := apply_month]

# Map IC dates to regime
ic_ym <- data.table(idx = 1:length(dates), ym = format(dates, "%Y-%m"))
ic_ym <- merge(ic_ym, regime_dt[, .(ym, regime_state)], by = "ym", all.x = TRUE)
ic_ym <- ic_ym[!is.na(regime_state)]

cat("  Regime distribution in IC data:\n")
print(ic_ym[, .N, by = regime_state])

regime_synergy <- list()

for (reg in c("Normal", "Elevated", "Crisis")) {
  idx <- ic_ym[regime_state == reg, idx]
  if (length(idx) < 12) {
    cat(sprintf("  %s: only %d months, skipping\n", reg, length(idx)))
    next
  }

  ic_sub <- ic_mat[idx, , drop = FALSE]
  mean_ic_reg <- colMeans(ic_sub, na.rm = TRUE)
  sd_ic_reg <- apply(ic_sub, 2, sd, na.rm = TRUE)
  icir_reg <- mean_ic_reg / pmax(sd_ic_reg, 1e-8)

  # Positive IC factors with |ICIR| > 0.15
  pos_factors <- names(which(mean_ic_reg > 0.005 & abs(icir_reg) > 0.10))
  if (length(pos_factors) < 2) {
    cat(sprintf("  %s: only %d eligible factors\n", reg, length(pos_factors)))
    next
  }

  # Pairwise correlation among eligible factors
  cor_sub <- cor(ic_sub[, pos_factors], use = "pairwise.complete.obs")

  # Build synergy score table
  n_pos <- length(pos_factors)
  pairs_list <- vector("list", n_pos * (n_pos - 1) / 2)
  k <- 0
  for (a in 1:(n_pos - 1)) {
    for (b in (a + 1):n_pos) {
      k <- k + 1
      fa <- pos_factors[a]; fb <- pos_factors[b]
      cc <- cor_sub[fa, fb]
      # Synergy = combined ICIR potential with low correlation
      syn <- (abs(icir_reg[fa]) + abs(icir_reg[fb])) * (1 - abs(cc))
      pairs_list[[k]] <- data.table(
        F1 = fa, F2 = fb,
        IC1 = round(mean_ic_reg[fa], 5),
        IC2 = round(mean_ic_reg[fb], 5),
        ICIR1 = round(icir_reg[fa], 3),
        ICIR2 = round(icir_reg[fb], 3),
        Cor = round(cc, 3),
        Synergy = round(syn, 3)
      )
    }
  }
  pairs <- rbindlist(pairs_list)
  pairs <- pairs[order(-Synergy)]
  top15 <- head(pairs, 15)

  regime_synergy[[reg]] <- list(
    regime = reg,
    n_months = length(idx),
    n_eligible_factors = n_pos,
    top_factors_icir = head(sort(icir_reg[pos_factors], decreasing = TRUE), 10),
    top15_synergy_pairs = top15
  )

  cat(sprintf("\n  === %s (%d months, %d eligible factors) ===\n", reg, length(idx), n_pos))
  cat("  Top 10 ICIR factors in this regime:\n")
  top_icir <- sort(icir_reg[pos_factors], decreasing = TRUE)
  for (j in 1:min(10, length(top_icir))) {
    cat(sprintf("    %s: ICIR=%.3f, IC=%.4f\n",
                names(top_icir)[j], top_icir[j], mean_ic_reg[names(top_icir)[j]]))
  }
  cat("\n  Top 15 synergy pairs (high combined ICIR + low correlation):\n")
  for (r in 1:nrow(top15)) {
    cat(sprintf("    %2d. %-25s + %-25s | cor=%5.2f | ICIR=%.2f/%.2f | syn=%.2f\n",
                r, top15$F1[r], top15$F2[r], top15$Cor[r],
                top15$ICIR1[r], top15$ICIR2[r], top15$Synergy[r]))
  }
}

# ======================================================================
# 5. Factor Lifespan: 3-year rolling ICIR for top 10 factors
# ======================================================================
cat("\n\n[5] Factor lifespan: 3-year rolling ICIR trends...\n")

overall_ic  <- colMeans(ic_mat, na.rm = TRUE)
overall_sd  <- apply(ic_mat, 2, sd, na.rm = TRUE)
overall_icir <- overall_ic / pmax(overall_sd, 1e-8)
top10_factors <- names(sort(abs(overall_icir), decreasing = TRUE))[1:10]

window <- 36
lifespan_results <- list()

for (fi in top10_factors) {
  ic_series <- ic_mat[, fi]
  n <- length(ic_series)
  roll_icir <- rep(NA_real_, n)

  for (t in window:n) {
    seg <- ic_series[(t - window + 1):t]
    m <- mean(seg, na.rm = TRUE)
    s <- sd(seg, na.rm = TRUE)
    roll_icir[t] <- if (s > 1e-8) m / s else NA_real_
  }

  valid_idx <- which(!is.na(roll_icir))
  if (length(valid_idx) > 12) {
    trend_fit <- lm(roll_icir[valid_idx] ~ valid_idx)
    slope <- coef(trend_fit)[2]
    p_val <- summary(trend_fit)$coefficients[2, 4]

    if (p_val < 0.10 && slope > 0.0005) {
      trend <- "RISING"
    } else if (p_val < 0.10 && slope < -0.0005) {
      trend <- "FALLING"
    } else {
      trend <- "STABLE"
    }

    n_valid <- length(valid_idx)
    q1 <- valid_idx[1:min(36, n_valid)]
    q4 <- tail(valid_idx, 36)
    early_icir <- mean(roll_icir[q1], na.rm = TRUE)
    recent_icir <- mean(roll_icir[q4], na.rm = TRUE)

    # Also compute 5 period breakdown
    chunk_size <- ceiling(n_valid / 5)
    period_icir <- numeric(5)
    for (pp in 1:5) {
      start_i <- (pp - 1) * chunk_size + 1
      end_i <- min(pp * chunk_size, n_valid)
      period_icir[pp] <- mean(roll_icir[valid_idx[start_i:end_i]], na.rm = TRUE)
    }
  } else {
    slope <- NA; p_val <- NA; trend <- "INSUFFICIENT"
    early_icir <- NA; recent_icir <- NA; period_icir <- rep(NA, 5)
  }

  lifespan_results[[fi]] <- list(
    factor = fi,
    overall_icir = round(overall_icir[fi], 3),
    trend = trend,
    slope_per_year = round(slope * 12, 5),
    p_value = round(p_val, 4),
    early_36m = round(early_icir, 3),
    recent_36m = round(recent_icir, 3),
    delta = round(recent_icir - early_icir, 3),
    period_5split = round(period_icir, 3)
  )

  cat(sprintf("  %-25s: ICIR=%6.3f | %7s (p=%.3f) | Early=%.3f → Recent=%.3f (Δ=%+.3f) | [%.2f %.2f %.2f %.2f %.2f]\n",
              fi, overall_icir[fi], trend, p_val, early_icir, recent_icir,
              recent_icir - early_icir, period_icir[1], period_icir[2],
              period_icir[3], period_icir[4], period_icir[5]))
}

# ======================================================================
# 6. Discard candidates: never positive / noise
# ======================================================================
cat("\n[6] Discard candidates...\n")

hit_rate <- colMeans(ic_mat > 0, na.rm = TRUE)
mean_ic_all <- colMeans(ic_mat, na.rm = TRUE)
sd_ic_all <- apply(ic_mat, 2, sd, na.rm = TRUE)
icir_all <- mean_ic_all / pmax(sd_ic_all, 1e-8)

all_factors <- data.table(
  Factor = colnames(ic_mat),
  Mean_IC = round(mean_ic_all, 5),
  Hit_Rate = round(hit_rate, 3),
  ICIR = round(icir_all, 3),
  SD_IC = round(sd_ic_all, 5)
)

# Tier 1: consistently negative (strong discard)
discard_t1 <- all_factors[Mean_IC < -0.01 & Hit_Rate < 0.38][order(Mean_IC)]
cat("\n  === Tier 1: Strong discard (Mean_IC < -0.01 AND Hit_Rate < 38%) ===\n")
cat("  Count:", nrow(discard_t1), "\n")
if (nrow(discard_t1) > 0) print(discard_t1)

# Tier 2: weakly negative
discard_t2 <- all_factors[Mean_IC < 0 & Hit_Rate < 0.42 & !Factor %in% discard_t1$Factor][order(Mean_IC)]
cat("\n  === Tier 2: Weak discard (Mean_IC < 0 AND Hit_Rate < 42%) ===\n")
cat("  Count:", nrow(discard_t2), "\n")
if (nrow(discard_t2) > 0) print(discard_t2)

# Tier 3: Noise (|ICIR| < 0.05)
noise <- all_factors[abs(ICIR) < 0.05][order(abs(ICIR))]
cat("\n  === Tier 3: Noise (|ICIR| < 0.05) ===\n")
cat("  Count:", nrow(noise), "\n")
if (nrow(noise) > 0) print(noise)

# Factors that are ALWAYS negative (no single positive mean IC in any 36-month window)
cat("\n  === Factors with negative mean IC in ALL 36-month windows ===\n")
always_neg <- character()
for (fi in colnames(ic_mat)) {
  ic_s <- ic_mat[, fi]
  any_pos_window <- FALSE
  for (t in 36:length(ic_s)) {
    if (mean(ic_s[(t-35):t]) > 0) {
      any_pos_window <- TRUE
      break
    }
  }
  if (!any_pos_window) always_neg <- c(always_neg, fi)
}
cat("  Count:", length(always_neg), "\n")
if (length(always_neg) > 0) {
  for (fi in always_neg) {
    cat(sprintf("    %s: Mean_IC=%.5f, ICIR=%.3f, Hit=%.1f%%\n",
                fi, mean_ic_all[fi], icir_all[fi], hit_rate[fi] * 100))
  }
}

# ======================================================================
# 7. Factor quality tiers (actionable summary)
# ======================================================================
cat("\n[7] Factor quality tier classification...\n")

all_factors[, Tier := "C_Marginal"]
all_factors[abs(ICIR) >= 0.30, Tier := "A_Core"]
all_factors[abs(ICIR) >= 0.15 & abs(ICIR) < 0.30, Tier := "B_Useful"]
all_factors[abs(ICIR) < 0.05, Tier := "D_Noise"]
all_factors[Mean_IC < -0.01 & Hit_Rate < 0.38, Tier := "F_Discard"]

cat("\n  Tier distribution:\n")
print(all_factors[, .N, by = Tier][order(Tier)])

cat("\n  === A_Core factors (|ICIR| >= 0.30) ===\n")
a_core <- all_factors[Tier == "A_Core"][order(-abs(ICIR))]
print(a_core)

cat("\n  === B_Useful factors (0.15 <= |ICIR| < 0.30) ===\n")
b_useful <- all_factors[Tier == "B_Useful"][order(-abs(ICIR))]
print(b_useful)

# ======================================================================
# 8. Save Phase 2 results
# ======================================================================
cat("\n[8] Saving Phase 2 results...\n")

results2 <- list(
  regime_synergy = regime_synergy,
  factor_lifespan = lifespan_results,
  discard_candidates = list(
    tier1_strong = if (nrow(discard_t1) > 0) discard_t1 else list(),
    tier1_count = nrow(discard_t1),
    tier2_weak = if (nrow(discard_t2) > 0) discard_t2 else list(),
    tier2_count = nrow(discard_t2),
    noise = if (nrow(noise) > 0) noise else list(),
    noise_count = nrow(noise),
    always_negative_36m = always_neg
  ),
  factor_tiers = list(
    A_Core = a_core,
    B_Useful = b_useful,
    tier_counts = all_factors[, .N, by = Tier][order(Tier)]
  ),
  actionable = list(
    core_factors = nrow(a_core),
    useful_factors = nrow(b_useful),
    discard_total = nrow(discard_t1) + length(always_neg),
    noise_total = nrow(noise),
    effective_universe = n_factors - nrow(discard_t1) - nrow(noise)
  )
)

out_path <- file.path(OUT, "factor_db_deep_analysis_phase2.json")
write_json(results2, out_path, pretty = TRUE, auto_unbox = TRUE)
cat("  Saved:", out_path, "\n")

cat("\n=== Phase 2 Complete:", as.character(Sys.time()), "===\n")
