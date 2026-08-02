suppressPackageStartupMessages(library(data.table))
r <- readRDS("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260802_019/wt019_results.rds")
cat("== arms ==\n")
for (k in names(r$bt)) {
  b <- r$bt[[k]]
  cat(sprintf("%-13s PORT_t=%+.2f IR=%+.3f netSR=%+.3f absSR=%+.3f absMDD=%.1f%% TO=%.1f n=%d\n",
      k, b$portfolio_alpha_t_nw_lag3, b$information_ratio, b$net_sr, b$abs_net_sr,
      100*b$abs_mdd, b$turnover_annual, b$n_months))
}
cat("\n== paired ==\n")
for (nm in names(r$paired)) {
  p <- r$paired[[nm]]
  cat(sprintf("%-27s t=%+.2f  %+.2f%%/yr  post17 t=%+.2f  n=%d\n",
      nm, p$t, 100*p$mean_d_ann, p$t_post2017, p$n))
}
cat(sprintf("\ndelta_IR=%+.3f | cost_stress t=%+.2f (%+.2f%%/yr)\n",
    r$delta_ir, r$cost_stress$t, 100*r$cost_stress$mean_d_ann))
cat(sprintf("recovery: ret %.1f%%  mdd %.1f%%\n", 100*r$recovery$ret, 100*r$recovery$mdd))
cat(sprintf("pretest_pass=%s\n", r$pretest_pass))
cat("\n== label quality ==\n"); print(r$label_quality)
cat("\n== label x realized ==\n"); print(r$label_realized)
cat("\n== down axis ==\n"); print(r$down_axis)
cat("\n== AX001 ==\n"); str(r$ax001)
cat("\n== oos_rough ==\n"); print(r$oos_rough)
cat("\n== overlay turnover ==\n"); str(r$overlay_turnover)
cat("\n== gap_days ==\n"); print(r$gap_days)
cat(sprintf("inj_block=%s n_miss_eb=%d\n", r$inj_block, r$n_miss_eb))
cat("\n== seg2026 ==\n"); print(r$seg2026)
cat("\n== n ON months ==\n"); print(r$per[dd_state==TRUE,.N])
cat("expanding months (n_win<252):", r$per[n_win<252,.N], "\n")
cat("\n== sidecar ==\n"); str(r$sidecar)
