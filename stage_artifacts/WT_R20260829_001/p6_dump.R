suppressPackageStartupMessages({library(data.table); library(jsonlite)})
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
OUT <- "stage_artifacts/WT_R20260829_001"
CS <- readRDS(file.path(OUT,"canonical_arms.rds"))
x <- CS$joint2way
x$period_returns <- NULL; x$benchmark_compare <- NULL
str(x, max.level=2)
cat("\n===== sue_only / mom_only scalar =====\n")
for (nm in c("sue_only","mom_only","zsum_control","joint2way_k200bp")) {
  y <- CS[[nm]]
  cat(sprintf("%s: port_t=%.4f pval=%s IR=%.4f alpha=%.5f TO=%.3f n=%d\n", nm,
      y$portfolio_alpha_t_nw_lag3, as.character(round(y$portfolio_alpha_t_pvalue %||% NA,5)),
      y$information_ratio, y$alpha_annual, y$turnover_annual, y$n_months))
}
