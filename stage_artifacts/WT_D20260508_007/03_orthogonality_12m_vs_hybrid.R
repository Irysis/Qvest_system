#==============================================================================
# WT-D20260508_007 — Step 3: 12M Orthogonality vs Hybrid 70/15/15
#
# Build 12M-holding portfolio returns (overlapping monthly start) and compare
# to Hybrid components (r_AR / r_KR10y / r_TSMOM / r_H_renorm / r_H_naive).
#
# Key construction:
#   - Each month t, alpha-rank universe → form decile portfolios + Top-N=20 LO.
#   - Hold 12 months → return = FwdRet_12M (already inherited).
#   - Compare monthly time-series of these 12M-holding returns.
#
# This IS overlapping (Cooper-Gulen-Schill 2008 standard for long-horizon factor
# tests): each month's portfolio return = 12-month holding from t.
#
# Mandate: max |cor| < 0.25 vs r_H_renorm (production Hybrid).
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_007")

cat("[03] WT-D20260508_007 — 12M orthogonality vs Hybrid\n")

mm <- as.data.table(read_parquet(file.path(OUT, "alpha_panel_12m.parquet")))
PRIMARY_COL <- "alpha_signed_z"  # Step 1 selected raw_signed (12M ICIR best)

# Decile per month
mm[, decile := {
  v <- get(PRIMARY_COL)
  if (sum(!is.na(v)) >= 10) {
    qs <- quantile(v, seq(0, 1, 0.1), na.rm = TRUE)
    qs <- unique(qs)
    if (length(qs) >= 2) as.integer(cut(v, qs, include.lowest = TRUE, labels = FALSE))
    else rep(NA_integer_, length(v))
  } else rep(NA_integer_, length(v))
}, by = ym]

# M1 — D10-D1 12M LS portfolio
m1 <- mm[!is.na(decile) & !is.na(FwdRet_12M) & decile %in% c(1, 10),
         .(ret = mean(FwdRet_12M), n = .N), by = .(ym, decile)]
m1_w <- dcast(m1, ym ~ decile, value.var = "ret")
setnames(m1_w, c("ym", "D1_12m", "D10_12m"))
m1_w[, r_LS_12m := D10_12m - D1_12m]

# M2 — Top-quintile (D9+D10) EW LO 12M
m2 <- mm[!is.na(decile) & !is.na(FwdRet_12M) & decile %in% c(9, 10),
         .(r_LO_top20pct_12m = mean(FwdRet_12M)), by = ym]

# M3 — Top-N=20 EW LO 12M (PG2 breadth)
mm[, alpha_rank_desc := frank(-get(PRIMARY_COL), na.last = "keep"), by = ym]
m3 <- mm[!is.na(alpha_rank_desc) & !is.na(FwdRet_12M) & alpha_rank_desc <= 20,
         .(r_LO_top20_12m = mean(FwdRet_12M), n_used = .N), by = ym]

ports <- merge(m1_w[, .(ym, r_LS_12m)], m2, by = "ym", all = TRUE)
ports <- merge(ports, m3[, .(ym, r_LO_top20_12m)], by = "ym", all = TRUE)
setorder(ports, ym)

# ---- Load Hybrid components ----
hyb_path <- file.path(PROJ, "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv")
if (!file.exists(hyb_path)) {
  stop("Hybrid returns CSV not found: ", hyb_path)
}
hyb <- fread(hyb_path)
hyb[, ym := substr(date, 1, 7)]
hyb_keep <- hyb[, .(ym, r_AR, r_KR10y, r_TSMOM, r_H_renorm, r_H_naive)]

# Aggregate Hybrid to 12M overlapping returns (each month: cumulative 12-month forward)
# Hybrid r_* is monthly. To compare with 12M holding, accumulate next 12 months from each ym.
setorder(hyb_keep, ym)
n_h <- nrow(hyb_keep)
hyb12 <- copy(hyb_keep)
for (col in c("r_AR", "r_KR10y", "r_TSMOM", "r_H_renorm", "r_H_naive")) {
  vals <- hyb_keep[[col]]
  # Compound forward 12 months
  fwd <- rep(NA_real_, n_h)
  for (i in 1:(n_h - 11)) {
    block <- vals[i:(i + 11)]
    if (sum(!is.na(block)) >= 11) fwd[i] <- prod(1 + block, na.rm = TRUE) - 1
  }
  hyb12[, paste0(col, "_12m") := fwd]
}
hyb12_keep <- hyb12[, .(ym, r_AR_12m, r_KR10y_12m, r_TSMOM_12m, r_H_renorm_12m, r_H_naive_12m)]

# Merge
both <- merge(ports, hyb12_keep, by = "ym")
setorder(both, ym)
both <- both[!is.na(r_LS_12m)]
cat("[03] joint ym count:", nrow(both), "range:", min(both$ym), "~", max(both$ym), "\n")

# ---- Correlation table ----
cor_targets <- c("r_AR_12m", "r_KR10y_12m", "r_TSMOM_12m", "r_H_renorm_12m", "r_H_naive_12m")
ports_v <- c("r_LS_12m", "r_LO_top20pct_12m", "r_LO_top20_12m")

cor_table <- list()
for (pv in ports_v) {
  for (tv in cor_targets) {
    sub <- both[!is.na(get(pv)) & !is.na(get(tv))]
    if (nrow(sub) >= 24) {
      pearson <- cor(sub[[pv]], sub[[tv]], method = "pearson")
      spearman <- cor(sub[[pv]], sub[[tv]], method = "spearman")
      cor_table[[length(cor_table) + 1]] <- data.table(
        port = pv, target = tv,
        pearson = pearson, spearman = spearman, n = nrow(sub)
      )
    }
  }
}
cor_table <- rbindlist(cor_table)
fwrite(cor_table, file.path(OUT, "orthogonality_12m_cor_table.csv"))
cat("\n[03] 12M Correlation matrix (port × target):\n"); print(cor_table)

# Max |cor| per port
max_abs_cor <- cor_table[, .(max_abs_pearson = max(abs(pearson), na.rm = TRUE),
                             max_abs_spearman = max(abs(spearman), na.rm = TRUE)),
                         by = port]
cat("\n[03] Max |cor| per port (12M):\n"); print(max_abs_cor)

mandate_threshold <- 0.25
overall_max <- max(abs(cor_table$pearson), na.rm = TRUE)
overall_pass <- overall_max < mandate_threshold

# vs r_H_renorm specifically
hyb_renorm_cors <- cor_table[target == "r_H_renorm_12m"]
cat("\n[03] vs r_H_renorm_12m (production Hybrid 12M):\n"); print(hyb_renorm_cors)

# ---- Save ----
ortho_out <- list(
  forecast_horizon = "12M",
  mandate_threshold = mandate_threshold,
  hybrid_components_12m_overlapping = list(
    note = "Hybrid components are monthly. Aggregated to 12M-overlapping cumulative returns to compare with 12M alpha-portfolio holding."
  ),
  port_constructions_12m = list(
    M1_LS_12m = "D10 - D1 EW long-short with 12M holding",
    M2_LO_top20pct_12m = "Top-quintile (D9+D10) EW long-only 12M holding",
    M3_LO_top20_12m = "Top-N=20 EW long-only 12M holding (PG2 breadth equivalent)"
  ),
  cor_table = cor_table,
  max_abs_cor_per_port = max_abs_cor,
  overall_max_abs_pearson = overall_max,
  overall_pass_threshold_025 = overall_pass,
  joint_n_periods = nrow(both),
  joint_ym_range = c(min(both$ym), max(both$ym)),
  vs_r_H_renorm_12m = hyb_renorm_cors,
  conclusion = if (overall_pass) "ORTHOGONALITY_PASS_12M" else "ORTHOGONALITY_REVIEW_12M"
)
write_json(ortho_out, file.path(OUT, "orthogonality_12m_vs_hybrid.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

write_parquet(both, file.path(OUT, "alpha_port_12m_returns.parquet"))
cat("\n[03] DONE. Conclusion:", ortho_out$conclusion, "\n")
