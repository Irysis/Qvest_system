#==============================================================================
# WT-D20260508_005 — Step 3: Orthogonality vs Hybrid 70/15/15
#
# Compare WT_005 alpha-derived monthly portfolio returns to:
#   - r_AR        : STR_1715_AR_threshold_overlay (PG2 70%)
#   - r_KR10y     : KR_10y bond ETF (15%)
#   - r_TSMOM     : Cross-Asset TSMOM ETF rotation (15%)
#   - r_H_naive   : 70/15/15 naive Hybrid blend
#   - r_H_renorm  : pre-2015 renormalized + post-2015 strict 70/15/15
#
# Mandate: max |cor| < 0.25 across all 5 series → orthogonality PASS
#
# Three portfolio constructions (for robustness):
#   M1: D10-D1 LS (alpha-ranked top decile minus bottom decile, EW)
#   M2: top-quintile EW long-only proxy (D9-D10)
#   M3: top-N=20 EW (PG2-equivalent breadth — long-only mandate)
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_005")

cat("[03] Orthogonality vs Hybrid 70/15/15\n")

mm <- as.data.table(read_parquet(file.path(OUT, "alpha_panel_single.parquet")))
PRIMARY_COL <- "alpha_ema3_z"  # selected in Step 2

# Build per-month decile from alpha
mm[, decile := {
  v <- get(PRIMARY_COL)
  if (sum(!is.na(v)) >= 10) {
    qs <- quantile(v, seq(0, 1, 0.1), na.rm = TRUE)
    qs <- unique(qs)
    if (length(qs) >= 2) as.integer(cut(v, qs, include.lowest = TRUE, labels = FALSE))
    else rep(NA_integer_, length(v))
  } else rep(NA_integer_, length(v))
}, by = ym]

# M1 — D10-D1 LS monthly EW
m1 <- mm[!is.na(decile) & !is.na(FwdRet_1M) & decile %in% c(1, 10),
         .(ret = mean(FwdRet_1M), n = .N),
         by = .(ym, decile)]
m1_w <- dcast(m1, ym ~ decile, value.var = "ret")
setnames(m1_w, c("ym", "D1", "D10"))
m1_w[, r_LS := D10 - D1]

# M2 — top-quintile (D9+D10 average) EW long-only
m2 <- mm[!is.na(decile) & !is.na(FwdRet_1M) & decile %in% c(9, 10),
         .(r_LO_top20pct = mean(FwdRet_1M)),
         by = ym]

# M3 — top-N=20 EW long-only (PG2 breadth)
mm[, alpha_rank_desc := frank(-get(PRIMARY_COL), na.last = "keep"), by = ym]
m3 <- mm[!is.na(alpha_rank_desc) & !is.na(FwdRet_1M) & alpha_rank_desc <= 20,
         .(r_LO_top20 = mean(FwdRet_1M), n_used = .N),
         by = ym]

ports <- merge(m1_w[, .(ym, r_LS)], m2, by = "ym", all = TRUE)
ports <- merge(ports, m3[, .(ym, r_LO_top20)], by = "ym", all = TRUE)
setorder(ports, ym)

# ---- Load Hybrid components ----
hyb <- fread(file.path(PROJ, "qepm/mailbox/worktask/WT-P20260505_001/architect_hybrid_returns_full256m.csv"))
hyb[, ym := substr(date, 1, 7)]
hyb_keep <- hyb[, .(ym, r_AR, r_KR10y, r_TSMOM, r_H_renorm, r_H_naive)]

# Merge port × hybrid
both <- merge(ports, hyb_keep, by = "ym")
setorder(both, ym)
cat("[03] joint ym count:", nrow(both), "range:", min(both$ym), "~", max(both$ym), "\n")

# ---- Correlation matrix ----
cor_targets <- c("r_AR", "r_KR10y", "r_TSMOM", "r_H_renorm", "r_H_naive")
ports_v <- c("r_LS", "r_LO_top20pct", "r_LO_top20")

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
fwrite(cor_table, file.path(OUT, "orthogonality_cor_table.csv"))
cat("\n[03] Correlation matrix (port × target):\n"); print(cor_table)

# ---- Max |cor| per port ----
max_abs_cor <- cor_table[, .(max_abs_pearson = max(abs(pearson), na.rm = TRUE),
                             max_abs_spearman = max(abs(spearman), na.rm = TRUE)),
                         by = port]
cat("\n[03] Max |cor| per port:\n"); print(max_abs_cor)

mandate_threshold <- 0.25
overall_max <- max(cor_table$pearson |> abs(), na.rm = TRUE)
overall_pass <- overall_max < mandate_threshold

# Specifically against r_H_renorm (the production Hybrid)
hyb_renorm_cors <- cor_table[target == "r_H_renorm"]
cat("\n[03] vs r_H_renorm (production Hybrid):\n"); print(hyb_renorm_cors)

# ---- Save Hybrid orthogonality JSON ----
ortho_out <- list(
  mandate_threshold = mandate_threshold,
  hybrid_components = list(
    AR = "STR_1715_AR_threshold_overlay (70%)",
    KR10y = "KODEX 국고채10년 A148070 (15%)",
    TSMOM = "Cross-Asset TSMOM ETF rotation (15%)"
  ),
  port_constructions = list(
    M1_LS = "D10 - D1 EW long-short (alpha-ranked deciles)",
    M2_LO_top20pct = "Top-quintile (D9+D10) EW long-only",
    M3_LO_top20 = "Top-N=20 EW long-only (PG2 breadth equivalent)"
  ),
  cor_table = cor_table,
  max_abs_cor_per_port = max_abs_cor,
  overall_max_abs_pearson = overall_max,
  overall_pass_threshold_025 = overall_pass,
  joint_n_periods = nrow(both),
  joint_ym_range = c(min(both$ym), max(both$ym)),
  vs_r_H_renorm = hyb_renorm_cors,
  conclusion = if (overall_max < 0.25) "ORTHOGONALITY_PASS"
               else "ORTHOGONALITY_FAIL_REVIEW_REQUIRED",
  notes = "Cross-section single-factor alpha is naturally orthogonal to time-series Hybrid (different signal axes). LS construction tests pure cross-section signal; LO_top20 tests the implementable production form."
)
write_json(ortho_out, file.path(OUT, "orthogonality_vs_hybrid.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6)

# Save monthly port returns for Risk/Optimizer downstream
write_parquet(both, file.path(OUT, "alpha_port_monthly_returns.parquet"))
cat("\n[03] DONE. Conclusion:", ortho_out$conclusion, "\n")
