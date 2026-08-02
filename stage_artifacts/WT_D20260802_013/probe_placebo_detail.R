suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260802_013/wt013_eval_results.rds"))
cat("placebo paired detail (vs base):\n")
for (i in seq_along(R$paired_placebo)) {
  p <- R$paired_placebo[[i]]
  cat(sprintf("  seed%d t=%+.3f mean_d=%+.2f%%/yr sub_pre2015=%+.2f sub_2015_19=%+.2f sub_2020p=%+.2f\n",
      i, p$paired_t_nw, 100 * p$mean_d_annualized, p$sub_pre2015, p$sub_2015_19, p$sub_2020p))
}
pt <- vapply(R$paired_placebo, `[[`, numeric(1), "paired_t_nw")
cat(sprintf("placebo t: mean=%.3f sd=%.3f min=%.3f max=%.3f\n", mean(pt), sd(pt), min(pt), max(pt)))
cat(sprintf("RESID primary t=%+.3f mean_d=%+.2f%%/yr\n", R$paired_resid$paired_t_nw, 100 * R$paired_resid$mean_d_annualized))
cat(sprintf("RESID vs PATHQ: t=%+.3f mean_d=%+.3f%%/yr n=%d\n",
    R$paired_resid_vs_pathq$paired_t_nw, 100 * R$paired_resid_vs_pathq$mean_d_annualized,
    R$paired_resid_vs_pathq$n_months))
cat(sprintf("volload pathq_vs_d03: mean=%.4f t=%+.2f | resid_vs_d03: mean=%.4f | resid_vs_base: mean=%.4f\n",
    R$volload$pathq_vs_d03$mean, R$volload$pathq_vs_d03$t_nw,
    R$volload$resid_vs_d03$mean, R$volload$resid_vs_base$mean))
cat(sprintf("RESID arm: oos_retention_approx(EW)=%.3f post2017_ew_t=%+.2f\n",
    R$bt$M01_PATHQ_RESID$diag_ew_universe$oos_retention_approx,
    R$bt$M01_PATHQ_RESID$diag_ew_universe$post2017_t_nw_lag3))
