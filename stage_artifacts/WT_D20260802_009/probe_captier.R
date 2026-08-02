R <- readRDS("stage_artifacts/WT_D20260802_009/wt009_eval_results.rds")
for (a in names(R$bt)) {
  ct <- R$bt[[a]]$diag_cap_tier
  if (is.null(ct) || is.null(ct$weight_share_avg)) next
  cat(sprintf("%-12s ws=%s contrib=%s\n", a,
      paste(sprintf("%.2f", unlist(ct$weight_share_avg)), collapse = "/"),
      paste(sprintf("%+.3f", unlist(ct$contrib_gross_annualized)), collapse = "/")))
}
