cat("=== Factor DB 268-Factor Deep Analysis ===\n")
cat("Start:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
CACHE <- file.path(PROJ, ".cache/factor_db")
OUT   <- file.path(PROJ, "qepm/mailbox/qlead/inbox")

# ======================================================================
# 0. Load IC history (wide matrix)
# ======================================================================
cat("[0] Loading IC history...\n")
ic_raw <- as.data.table(read_parquet(file.path(CACHE, "factor_ic_monthly.parquet")))
ic_raw[, Date := as.Date(Date)]

cat("  Raw: ", nrow(ic_raw), " rows, ", uniqueN(ic_raw$Factor_Name), " factors, ",
    uniqueN(ic_raw$Date), " months\n")

# Pivot to wide: Date x Factor_Name (IC values)
ic_wide <- dcast(ic_raw, Date ~ Factor_Name, value.var = "IC")
dates <- ic_wide$Date
ic_mat <- as.matrix(ic_wide[, -"Date"])

# Remove factors with >50% missing
miss_pct <- colMeans(is.na(ic_mat))
keep <- miss_pct < 0.5
cat("  Factors with <50% missing:", sum(keep), "/ ", ncol(ic_mat), "\n")
ic_mat <- ic_mat[, keep]

# Impute remaining NA with 0 (no IC = no signal)
ic_mat[is.na(ic_mat)] <- 0
n_factors <- ncol(ic_mat)
n_months  <- nrow(ic_mat)
cat("  Final matrix:", n_months, "months x", n_factors, "factors\n\n")

# ======================================================================
# 1. IC Pairwise Correlation → PCA
# ======================================================================
cat("[1] Computing IC pairwise correlation matrix + PCA...\n")
ic_cor <- cor(ic_mat, use = "pairwise.complete.obs")

# PCA on correlation matrix
pca <- prcomp(ic_mat, center = TRUE, scale. = TRUE)
var_explained <- pca$sdev^2 / sum(pca$sdev^2)
cum_var <- cumsum(var_explained)

# How many PCs for 50/70/80/90/95%?
thresholds <- c(0.50, 0.70, 0.80, 0.90, 0.95)
pcs_needed <- sapply(thresholds, function(th) which(cum_var >= th)[1])
names(pcs_needed) <- paste0(thresholds * 100, "%")

cat("  Variance explained thresholds:\n")
for (i in seq_along(thresholds)) {
  cat(sprintf("    %3.0f%% variance → PC %d (each PC%d explains %.1f%%)\n",
              thresholds[i] * 100, pcs_needed[i], pcs_needed[i],
              var_explained[pcs_needed[i]] * 100))
}

# Top 20 PCs detail
top_pcs <- min(20, length(var_explained))
pca_summary <- data.table(
  PC = 1:top_pcs,
  Var_Explained_Pct = round(var_explained[1:top_pcs] * 100, 2),
  Cumulative_Pct = round(cum_var[1:top_pcs] * 100, 2)
)
cat("\n  Top 20 PCs:\n")
print(pca_summary)

# ======================================================================
# 2. Top Loading Factors per PC → Name the axes
# ======================================================================
cat("\n[2] Top loading factors per PC (naming independent axes)...\n")
loadings <- pca$rotation  # factors x PCs

pc_names <- list()
n_pcs_analyze <- pcs_needed["90%"]
cat("  Analyzing", n_pcs_analyze, "PCs (90% variance)\n\n")

pc_top_loadings <- list()
for (pc_i in 1:min(n_pcs_analyze, 25)) {
  loads <- loadings[, pc_i]
  top_pos <- head(sort(loads, decreasing = TRUE), 5)
  top_neg <- head(sort(loads), 5)

  top_all <- sort(abs(loads), decreasing = TRUE)
  top5 <- names(top_all)[1:5]

  # Extract category prefixes for naming
  prefixes <- gsub("_.*", "", top5)
  prefix_tab <- sort(table(prefixes), decreasing = TRUE)
  dominant <- names(prefix_tab)[1]

  # Auto-name based on dominant category
  name_map <- c(
    D = "Defense/Volatility", V = "Value", M = "Momentum",
    Q = "Quality", C = "Consensus", AC = "Accrual",
    G = "Growth", L = "Liquidity", CR = "Crowding",
    R = "Risk", S = "Size"
  )
  axis_name <- ifelse(dominant %in% names(name_map), name_map[dominant],
                       paste0("Mixed(", dominant, ")"))

  pc_top_loadings[[pc_i]] <- list(
    pc = pc_i,
    var_pct = round(var_explained[pc_i] * 100, 2),
    cum_pct = round(cum_var[pc_i] * 100, 2),
    axis_name = axis_name,
    top5_positive = names(top_pos),
    top5_positive_loading = round(unname(top_pos), 4),
    top5_negative = names(top_neg),
    top5_negative_loading = round(unname(top_neg), 4),
    dominant_prefix = dominant
  )

  cat(sprintf("  PC%02d (%5.2f%%, cum %5.1f%%): [%s]\n",
              pc_i, var_explained[pc_i] * 100, cum_var[pc_i] * 100, axis_name))
  cat(sprintf("    (+) %s\n", paste(sprintf("%s(%.3f)", names(top_pos), top_pos), collapse=", ")))
  cat(sprintf("    (-) %s\n", paste(sprintf("%s(%.3f)", names(top_neg), top_neg), collapse=", ")))
  cat("\n")
}

# ======================================================================
# 3. Sub-cluster decomposition (cor > 0.9)
# ======================================================================
cat("[3] Sub-cluster decomposition (cor > 0.9 threshold)...\n")

# Build adjacency: cor > 0.9
high_cor <- abs(ic_cor) > 0.9
diag(high_cor) <- FALSE

# Connected components via BFS
visited <- rep(FALSE, n_factors)
clusters <- list()
cluster_id <- 0

for (i in 1:n_factors) {
  if (visited[i]) next
  cluster_id <- cluster_id + 1
  queue <- i
  members <- c()
  while (length(queue) > 0) {
    node <- queue[1]
    queue <- queue[-1]
    if (visited[node]) next
    visited[node] <- TRUE
    members <- c(members, node)
    neighbors <- which(high_cor[node, ] & !visited)
    queue <- c(queue, neighbors)
  }
  clusters[[cluster_id]] <- colnames(ic_mat)[members]
}

cluster_sizes <- sapply(clusters, length)
cat("  Total clusters (cor>0.9):", length(clusters), "\n")
cat("  Singletons (unique factors):", sum(cluster_sizes == 1), "\n")
cat("  Multi-member clusters:", sum(cluster_sizes > 1), "\n")
cat("  Largest cluster:", max(cluster_sizes), "factors\n\n")

# Detail multi-member clusters
multi_clusters <- clusters[cluster_sizes > 1]
multi_clusters <- multi_clusters[order(-sapply(multi_clusters, length))]

cat("  Multi-member clusters (sorted by size):\n")
cluster_details <- list()
for (ci in seq_along(multi_clusters)) {
  members <- multi_clusters[[ci]]
  n_mem <- length(members)

  # Compute mean pairwise cor within cluster
  if (n_mem > 1) {
    sub_cor <- ic_cor[members, members]
    mean_cor <- mean(sub_cor[lower.tri(sub_cor)])
  } else {
    mean_cor <- 1.0
  }

  # Dominant category
  prefixes <- gsub("[0-9].*", "", members)
  prefix_tab <- sort(table(prefixes), decreasing = TRUE)

  # Mean IC of cluster members
  member_ic <- colMeans(ic_mat[, members, drop = FALSE], na.rm = TRUE)
  best_member <- names(which.max(abs(member_ic)))

  cluster_details[[ci]] <- list(
    cluster_id = ci,
    size = n_mem,
    mean_intra_cor = round(mean_cor, 3),
    dominant_category = names(prefix_tab)[1],
    members = members,
    best_representative = best_member,
    best_mean_ic = round(member_ic[best_member], 5)
  )

  if (ci <= 20) {
    cat(sprintf("    Cluster %02d (%2d members, mean_cor=%.3f, dom=%s): %s\n",
                ci, n_mem, mean_cor, names(prefix_tab)[1],
                paste(head(members, 8), collapse=", ")))
    if (n_mem > 8) cat(sprintf("      ... +%d more\n", n_mem - 8))
    cat(sprintf("      → Best representative: %s (mean IC=%.5f)\n", best_member, member_ic[best_member]))
  }
}

# Also check cor > 0.7 and cor > 0.8
for (thr in c(0.7, 0.8)) {
  hc <- abs(ic_cor) > thr
  diag(hc) <- FALSE
  vis2 <- rep(FALSE, n_factors)
  cl2 <- 0
  for (i in 1:n_factors) {
    if (vis2[i]) next
    cl2 <- cl2 + 1
    q2 <- i
    while (length(q2) > 0) {
      nd <- q2[1]; q2 <- q2[-1]
      if (vis2[nd]) next
      vis2[nd] <- TRUE
      q2 <- c(q2, which(hc[nd, ] & !vis2))
    }
  }
  cat(sprintf("  [Reference] cor>%.1f threshold → %d clusters\n", thr, cl2))
}

# ======================================================================
# 4. Regime-conditional synergy factor pairs
# ======================================================================
cat("\n[4] Regime-conditional synergy analysis...\n")

# Load regime data
regime_path <- file.path(PROJ, ".cache/regime_v7.parquet")
if (!file.exists(regime_path)) {
  regime_path <- file.path(PROJ, ".cache/macro_regime.parquet")
}

has_regime <- file.exists(regime_path)
if (has_regime) {
  regime_dt <- as.data.table(read_parquet(regime_path))
  regime_dt[, Date := as.Date(Date)]
  cat("  Regime data loaded:", nrow(regime_dt), "rows\n")
  cat("  Columns:", paste(names(regime_dt), collapse=", "), "\n")

  # Map months to regime
  # Find the regime column
  regime_col <- intersect(names(regime_dt), c("Regime", "regime", "regime_label", "State"))
  if (length(regime_col) == 0) {
    # Try to find it
    cat("  Available columns:", paste(names(regime_dt), collapse=", "), "\n")
    # Use the last column as regime signal if numeric
    regime_col <- NULL
    for (cn in rev(names(regime_dt))) {
      if (cn != "Date" && is.numeric(regime_dt[[cn]])) {
        regime_col <- cn
        break
      }
    }
  } else {
    regime_col <- regime_col[1]
  }

  if (!is.null(regime_col)) {
    cat("  Using regime column:", regime_col, "\n")

    # Monthly regime: use end-of-month
    regime_dt[, YM := format(Date, "%Y-%m")]
    regime_monthly <- regime_dt[, .(Regime = tail(get(regime_col), 1)), by = YM]
    regime_monthly[, Date := as.Date(paste0(YM, "-01"))]

    # Classify into 3 regimes (Normal/Elevated/Crisis)
    # Regime engine v7.1: typically numeric 1/2/3 or string labels
    regime_vals <- unique(regime_monthly$Regime)
    cat("  Regime values:", paste(head(regime_vals, 10), collapse=", "), "\n")

    if (is.numeric(regime_monthly$Regime)) {
      # Numeric: use quantile-based classification
      q33 <- quantile(regime_monthly$Regime, 0.33, na.rm = TRUE)
      q67 <- quantile(regime_monthly$Regime, 0.67, na.rm = TRUE)
      regime_monthly[, Label := fifelse(Regime <= q33, "Normal",
                                         fifelse(Regime <= q67, "Elevated", "Crisis"))]
    } else {
      regime_monthly[, Label := as.character(Regime)]
    }

    cat("  Regime distribution:\n")
    print(regime_monthly[, .N, by = Label])

    # For each regime, compute IC correlation and find synergy pairs
    # Synergy = factor pair whose combined IC > sum of individual ICs (diversification benefit)
    # Proxy: pairs with LOW correlation within regime (combine well)
    # AND both have positive mean IC in that regime

    regime_synergy <- list()
    for (reg in unique(regime_monthly$Label)) {
      reg_dates <- regime_monthly[Label == reg, Date]
      # Match to IC dates (same month)
      reg_months <- format(reg_dates, "%Y-%m")
      ic_months  <- format(dates, "%Y-%m")
      idx <- which(ic_months %in% reg_months)

      if (length(idx) < 12) {
        cat(sprintf("  %s: only %d months, skipping\n", reg, length(idx)))
        next
      }

      ic_sub <- ic_mat[idx, ]

      # Mean IC per factor in this regime
      mean_ic_reg <- colMeans(ic_sub, na.rm = TRUE)

      # Factors with positive mean IC
      pos_factors <- names(which(mean_ic_reg > 0.01))
      if (length(pos_factors) < 2) {
        cat(sprintf("  %s: only %d positive IC factors\n", reg, length(pos_factors)))
        next
      }

      # Pairwise correlation among positive IC factors
      cor_sub <- cor(ic_sub[, pos_factors], use = "pairwise.complete.obs")

      # Find pairs with LOWEST correlation (best diversification) among top IC factors
      # Score = mean_ic_A + mean_ic_B - 2*cor(A,B)*sqrt(var_A*var_B) proxy for portfolio Sharpe
      # Simpler: score = (ICIR_A + ICIR_B) * (1 - abs(cor))
      sd_ic_reg <- apply(ic_sub[, pos_factors], 2, sd, na.rm = TRUE)
      icir_reg <- mean_ic_reg[pos_factors] / pmax(sd_ic_reg, 1e-8)

      n_pos <- length(pos_factors)
      pairs <- data.table(
        F1 = character(), F2 = character(),
        IC1 = numeric(), IC2 = numeric(),
        ICIR1 = numeric(), ICIR2 = numeric(),
        Cor = numeric(), Synergy = numeric()
      )

      for (a in 1:(n_pos - 1)) {
        for (b in (a + 1):n_pos) {
          fa <- pos_factors[a]; fb <- pos_factors[b]
          cc <- cor_sub[fa, fb]
          syn <- (icir_reg[fa] + icir_reg[fb]) * (1 - abs(cc))
          pairs <- rbindlist(list(pairs, data.table(
            F1 = fa, F2 = fb,
            IC1 = round(mean_ic_reg[fa], 5),
            IC2 = round(mean_ic_reg[fb], 5),
            ICIR1 = round(icir_reg[fa], 3),
            ICIR2 = round(icir_reg[fb], 3),
            Cor = round(cc, 3),
            Synergy = round(syn, 3)
          )))
        }
      }

      pairs <- pairs[order(-Synergy)]
      top10 <- head(pairs, 10)

      regime_synergy[[reg]] <- list(
        regime = reg,
        n_months = length(idx),
        n_positive_ic_factors = n_pos,
        top10_synergy_pairs = top10
      )

      cat(sprintf("\n  === %s (%d months, %d positive-IC factors) ===\n", reg, length(idx), n_pos))
      cat("  Top 10 synergy pairs (high combined ICIR + low correlation):\n")
      for (r in 1:min(10, nrow(top10))) {
        cat(sprintf("    %2d. %s + %s | IC=%.4f/%.4f | ICIR=%.2f/%.2f | cor=%.2f | syn=%.2f\n",
                    r, top10$F1[r], top10$F2[r],
                    top10$IC1[r], top10$IC2[r],
                    top10$ICIR1[r], top10$ICIR2[r],
                    top10$Cor[r], top10$Synergy[r]))
      }
    }
  }
} else {
  cat("  WARNING: No regime data found. Skipping regime analysis.\n")
  regime_synergy <- list(error = "No regime data found")
}

# ======================================================================
# 5. Factor Lifespan: 3-year rolling ICIR for top 10 factors
# ======================================================================
cat("\n[5] Factor lifespan: 3-year rolling ICIR trends...\n")

# Top 10 by overall ICIR
overall_ic  <- colMeans(ic_mat, na.rm = TRUE)
overall_sd  <- apply(ic_mat, 2, sd, na.rm = TRUE)
overall_icir <- overall_ic / pmax(overall_sd, 1e-8)
top10_factors <- names(sort(abs(overall_icir), decreasing = TRUE))[1:10]

cat("  Top 10 factors by |ICIR|:\n")
for (fi in top10_factors) {
  cat(sprintf("    %s: ICIR=%.3f, Mean_IC=%.4f\n", fi, overall_icir[fi], overall_ic[fi]))
}

# 36-month rolling ICIR
window <- 36  # months
lifespan_results <- list()

for (fi in top10_factors) {
  ic_series <- ic_mat[, fi]
  n <- length(ic_series)
  roll_icir <- rep(NA_real_, n)
  roll_mean_ic <- rep(NA_real_, n)

  for (t in window:n) {
    seg <- ic_series[(t - window + 1):t]
    m <- mean(seg, na.rm = TRUE)
    s <- sd(seg, na.rm = TRUE)
    roll_mean_ic[t] <- m
    roll_icir[t] <- if (s > 1e-8) m / s else NA_real_
  }

  # Trend: linear regression of rolling ICIR on time
  valid_idx <- which(!is.na(roll_icir))
  if (length(valid_idx) > 12) {
    trend_fit <- lm(roll_icir[valid_idx] ~ valid_idx)
    slope <- coef(trend_fit)[2]
    p_val <- summary(trend_fit)$coefficients[2, 4]

    # Classify trend
    if (p_val < 0.05 && slope > 0.001) {
      trend <- "RISING"
    } else if (p_val < 0.05 && slope < -0.001) {
      trend <- "FALLING"
    } else {
      trend <- "STABLE"
    }

    # Recent vs early ICIR
    early_icir <- mean(roll_icir[valid_idx[1:min(24, length(valid_idx))]], na.rm = TRUE)
    recent_icir <- mean(tail(roll_icir[valid_idx], 24), na.rm = TRUE)
  } else {
    slope <- NA; p_val <- NA; trend <- "INSUFFICIENT"
    early_icir <- NA; recent_icir <- NA
  }

  lifespan_results[[fi]] <- list(
    factor = fi,
    overall_icir = round(overall_icir[fi], 3),
    overall_mean_ic = round(overall_ic[fi], 5),
    trend = trend,
    slope = round(slope * 1000, 4),  # per 1000 months for readability
    p_value = round(p_val, 4),
    early_36m_icir = round(early_icir, 3),
    recent_36m_icir = round(recent_icir, 3),
    icir_change = round(recent_icir - early_icir, 3)
  )

  cat(sprintf("  %25s: ICIR=%.3f | Trend=%7s (slope=%.4f, p=%.3f) | Early=%.3f → Recent=%.3f\n",
              fi, overall_icir[fi], trend, slope * 1000, p_val, early_icir, recent_icir))
}

# ======================================================================
# 6. Factors with NEVER positive mean IC → discard candidates
# ======================================================================
cat("\n[6] Factors with never-positive IC (complete discard candidates)...\n")

# Factor mean IC that is always negative across all 36-month windows
# Also check: factors where hit_rate < 40% (less than 40% of months have positive IC)
hit_rate <- colMeans(ic_mat > 0, na.rm = TRUE)
mean_ic_all <- colMeans(ic_mat, na.rm = TRUE)
sd_ic_all <- apply(ic_mat, 2, sd, na.rm = TRUE)
icir_all <- mean_ic_all / pmax(sd_ic_all, 1e-8)

# Never positive: mean IC < 0 AND hit_rate < 0.40
# Strong discard: mean IC < -0.01 AND hit_rate < 0.35
never_pos <- data.table(
  Factor = colnames(ic_mat),
  Mean_IC = round(mean_ic_all, 5),
  Hit_Rate = round(hit_rate, 3),
  ICIR = round(icir_all, 3),
  SD_IC = round(sd_ic_all, 5)
)

# Discard tier 1: consistently negative
discard_t1 <- never_pos[Mean_IC < -0.01 & Hit_Rate < 0.35][order(Mean_IC)]
cat("  Tier 1 discard (Mean_IC < -0.01 AND Hit_Rate < 35%):", nrow(discard_t1), "factors\n")
if (nrow(discard_t1) > 0) {
  print(discard_t1)
}

# Discard tier 2: weakly negative
discard_t2 <- never_pos[Mean_IC < 0 & Hit_Rate < 0.40 & !Factor %in% discard_t1$Factor][order(Mean_IC)]
cat("\n  Tier 2 discard (Mean_IC < 0 AND Hit_Rate < 40%):", nrow(discard_t2), "factors\n")
if (nrow(discard_t2) > 0) {
  print(head(discard_t2, 20))
}

# Also: factors with |ICIR| < 0.05 = essentially noise
noise <- never_pos[abs(ICIR) < 0.05][order(abs(ICIR))]
cat("\n  Noise factors (|ICIR| < 0.05):", nrow(noise), "factors\n")
if (nrow(noise) > 0) {
  print(head(noise, 20))
}

# ======================================================================
# 7. Save comprehensive results to JSON
# ======================================================================
cat("\n[7] Saving results...\n")

results <- list(
  metadata = list(
    analysis_date = as.character(Sys.Date()),
    n_factors = n_factors,
    n_months = n_months,
    date_range = paste(as.character(min(dates)), "~", as.character(max(dates)))
  ),

  pca_analysis = list(
    pcs_for_90pct = unname(pcs_needed["90%"]),
    pcs_for_80pct = unname(pcs_needed["80%"]),
    pcs_for_70pct = unname(pcs_needed["70%"]),
    pcs_for_50pct = unname(pcs_needed["50%"]),
    top20_pcs = pca_summary,
    conclusion = paste0("268 factors collapse to ", pcs_needed["90%"],
                         " independent dimensions (90% variance). True dimensionality is ~",
                         pcs_needed["80%"], " (80%).")
  ),

  independent_axes = pc_top_loadings,

  cluster_analysis = list(
    threshold_09 = list(
      n_clusters = length(clusters),
      n_singletons = sum(cluster_sizes == 1),
      n_multi_clusters = sum(cluster_sizes > 1),
      largest_cluster_size = max(cluster_sizes),
      effective_independent_factors = length(clusters),
      multi_cluster_details = cluster_details[1:min(20, length(cluster_details))]
    )
  ),

  regime_synergy = regime_synergy,

  factor_lifespan = lifespan_results,

  discard_candidates = list(
    tier1_strongly_negative = if (nrow(discard_t1) > 0) as.list(discard_t1) else list(),
    tier1_count = nrow(discard_t1),
    tier2_weakly_negative = if (nrow(discard_t2) > 0) as.list(head(discard_t2, 30)) else list(),
    tier2_count = nrow(discard_t2),
    noise_factors = if (nrow(noise) > 0) as.list(head(noise, 30)) else list(),
    noise_count = nrow(noise)
  ),

  actionable_summary = list(
    true_dimensions = unname(pcs_needed["90%"]),
    independent_clusters_09 = length(clusters),
    discard_tier1 = nrow(discard_t1),
    discard_tier2 = nrow(discard_t2),
    noise_factors = nrow(noise),
    effective_factors = n_factors - nrow(discard_t1) - nrow(noise)
  )
)

# Save JSON
out_path <- file.path(OUT, "factor_db_deep_analysis_268.json")
write_json(results, out_path, pretty = TRUE, auto_unbox = TRUE)
cat("  Saved:", out_path, "\n")

# Also save correlation matrix as compact RDS for future use
cor_path <- file.path(PROJ, ".cache/factor_db/ic_correlation_matrix.rds")
saveRDS(ic_cor, cor_path)
cat("  Saved correlation matrix:", cor_path, "\n")

cat("\n=== Analysis Complete:", as.character(Sys.time()), "===\n")
