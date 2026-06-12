# report_extract.R - key numbers for the Track W completion report (ASCII)
suppressPackageStartupMessages({ library(data.table) })
PR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TW <- file.path(PR, "04_Research/composition_search/cycle1b_trackW")
res <- fread(file.path(TW, "weighting_results.csv"))

cat("=== EW / B03 baselines (full | IS | OOS net SR, full MDD, TO, PORT_t) ===\n")
print(res[is_baseline == TRUE, .(substrate, method_id, n_months,
      full_net_sr = round(full_net_sr,3), is_net_sr = round(is_net_sr,3),
      oos_net_sr = round(oos_net_sr,3), full_mdd = round(full_mdd,3),
      to = round(oneway_to_ann,2), port_t = round(full_port_t_nw3,2),
      dsr = round(dsr_n_trials86,3))])

cat("\n=== S3 ALIVE survivors (all 3 criteria) ===\n")
print(res[substrate == "S3" & alive_all == TRUE,
      .(method_id, method_label, full_net_sr = round(full_net_sr,3),
        d_is_sr = round(d_is_sr,3), d_oos_sr = round(d_oos_sr,3),
        d_full_mdd_pp = round(d_full_mdd_pp,1), full_mdd = round(full_mdd,3),
        port_t = round(full_port_t_nw3,2), dsr = round(dsr_n_trials86,3))])

cat("\n=== best-IS per substrate (selection) ===\n")
print(res[, .SD[order(-is_net_sr, -is_port_t_nw3)][1], by = substrate][,
      .(substrate, method_id, method_label, is_net_sr = round(is_net_sr,3),
        d_is_sr = round(d_is_sr,3), d_oos_sr = round(d_oos_sr,3),
        d_full_mdd_pp = round(d_full_mdd_pp,1))])

cat("\n=== counts ===\n")
cat(sprintf("n trials total: %d | non-baseline: %d\n", nrow(res), res[is_baseline==FALSE,.N]))
cat(sprintf("d_is_sr >= +0.10: %d | d_oos_sr >= 0: %d | both + dMDD<=2pp (alive): %d\n",
    res[is_baseline==FALSE & d_is_sr >= 0.10, .N],
    res[is_baseline==FALSE & d_oos_sr >= 0, .N],
    res[alive_all == TRUE, .N]))
cat(sprintf("S1 challengers with d_oos_sr >= 0: %d / 21\n", res[substrate=="S1" & is_baseline==FALSE & d_oos_sr>=0, .N]))
cat(sprintf("S2 challengers with d_oos_sr >= 0: %d / 21\n", res[substrate=="S2" & is_baseline==FALSE & d_oos_sr>=0, .N]))
cat(sprintf("S3 challengers with d_oos_sr >= 0: %d / 21\n", res[substrate=="S3" & is_baseline==FALSE & d_oos_sr>=0, .N]))
cat(sprintf("B  challengers with d_oos_sr >= 0: %d / 10\n", res[substrate=="B" & is_baseline==FALSE & d_oos_sr>=0, .N]))

cat("\n=== DSR (n_trials=86) range ===\n")
cat(sprintf("min %.3f / median %.3f / max %.3f | trials with DSR >= 0.5: %d/77\n",
    min(res$dsr_n_trials86, na.rm=TRUE), median(res$dsr_n_trials86, na.rm=TRUE),
    max(res$dsr_n_trials86, na.rm=TRUE), res[dsr_n_trials86 >= 0.5, .N]))

cat("\n=== metric_type labels ===\n")
print(res[, .N, by = metric_type])
cat("weighting_method column present:", "weighting_method" %in% names(res), "\n")
