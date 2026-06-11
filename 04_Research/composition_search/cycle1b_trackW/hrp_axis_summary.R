# =============================================================================
# hrp_axis_summary.R - Track W HRP 13-variant axis-effect decomposition
#   One-axis-at-a-time grid around anchor H00 (sample/single/bisection/756d):
#     axis A cov estimator : H01 LW / H02 Gerber / H03 RMT / H04 Gerber+RMT / H05 EWMA094
#     axis B linkage       : H06 average / H07 ward.D2 / H08 complete
#     axis C allocation    : H09 HERC / H10 cluster-IV
#     axis D window        : H11 252d / H12 504d
#   Question (Dohoon): WHICH axis moves performance relative to the anchor?
#   Output: hrp_axis_summary.csv + console table. Deltas vs H00 (same substrate,
#   identical months) and vs W01 EW baseline for reference. ASCII only.
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
PR <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TW <- file.path(PR, "04_Research/composition_search/cycle1b_trackW")

res <- fread(file.path(TW, "weighting_results.csv"))
axis_map <- c(H00 = "anchor", H01 = "A_cov", H02 = "A_cov", H03 = "A_cov",
              H04 = "A_cov", H05 = "A_cov", H06 = "B_linkage", H07 = "B_linkage",
              H08 = "B_linkage", H09 = "C_allocation", H10 = "C_allocation",
              H11 = "D_window", H12 = "D_window")
h <- res[method_id %in% names(axis_map)]
h[, axis := axis_map[method_id]]

anc <- h[method_id == "H00", .(substrate, anc_full_sr = full_net_sr, anc_is_sr = is_net_sr,
                               anc_oos_sr = oos_net_sr, anc_mdd = full_mdd,
                               anc_to = oneway_to_ann)]
h <- merge(h, anc, by = "substrate")
h[, dH_full_sr := full_net_sr - anc_full_sr]
h[, dH_is_sr   := is_net_sr  - anc_is_sr]
h[, dH_oos_sr  := oos_net_sr - anc_oos_sr]
h[, dH_mdd_pp  := (full_mdd - anc_mdd) * 100]
h[, dH_to      := oneway_to_ann - anc_to]

out <- h[, .(substrate, method_id, method_label, axis,
             full_net_sr, is_net_sr, oos_net_sr, full_mdd, oneway_to_ann,
             dH_full_sr, dH_is_sr, dH_oos_sr, dH_mdd_pp, dH_to,
             d_is_sr_vs_EW = d_is_sr, d_oos_sr_vs_EW = d_oos_sr)]
setorder(out, substrate, method_id)
fwrite(out, file.path(TW, "hrp_axis_summary.csv"))

cat("=== HRP variants: per-substrate deltas vs H00 anchor ===\n")
print(out[, .(substrate, method_id, axis, full_net_sr,
              dH_full_sr = round(dH_full_sr, 3), dH_is_sr = round(dH_is_sr, 3),
              dH_oos_sr = round(dH_oos_sr, 3), dH_mdd_pp = round(dH_mdd_pp, 1))],
      nrows = 100)

cat("\n=== Axis-level effect summary (variants pooled across S1/S2/S3) ===\n")
ax <- h[axis != "anchor",
        .(n_variants = .N,
          mean_dH_full_sr = mean(dH_full_sr), max_abs_dH_full_sr = max(abs(dH_full_sr)),
          mean_dH_is_sr = mean(dH_is_sr), max_abs_dH_is_sr = max(abs(dH_is_sr)),
          mean_dH_oos_sr = mean(dH_oos_sr),
          mean_dH_mdd_pp = mean(dH_mdd_pp), max_abs_dH_mdd_pp = max(abs(dH_mdd_pp))),
        by = axis]
setorder(ax, -max_abs_dH_full_sr)
print(ax)

cat("\n=== Per-axis per-substrate spread (max - min full SR within axis variants) ===\n")
sp <- h[axis != "anchor",
        .(spread_full_sr = max(full_net_sr) - min(full_net_sr),
          best_variant = method_id[which.max(full_net_sr)],
          worst_variant = method_id[which.min(full_net_sr)]),
        by = .(substrate, axis)]
setorder(sp, substrate, -spread_full_sr)
print(sp)
fwrite(sp, file.path(TW, "hrp_axis_spread.csv"))
cat("HRP_AXIS_SUMMARY_OK\n")
