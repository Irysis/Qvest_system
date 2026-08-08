setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- readRDS("stage_artifacts/WT_D20260808_001/wt122_results.rds")
for (k in names(R$P2)) { p <- R$P2[[k]]
  cat(sprintf("%-14s d_ann=%+7.3f  t=%+6.3f  n=%d  sd_m=%.5f  req_ann=%.3f  verdict=%s  ratio_obs_req=%.3f  |t|/2=%.3f\n",
    k, p$delta_ann_pct, p$t_nw, p$n_months, p$delta_sd_monthly, p$required_ann_pct_at_t2,
    p$power_verdict, abs(p$delta_ann_pct)/p$required_ann_pct_at_t2, abs(p$t_nw)/2))
}
cat("\n-- P1 --\n")
for (k in names(R$P1)) { p <- R$P1[[k]]
  cat(sprintf("%-24s ann=%+7.3f t=%+6.3f n=%d n_avg=%.1f\n", k, p$ann_pct, p$t_nw, p$n_month, p$n_avg)) }
