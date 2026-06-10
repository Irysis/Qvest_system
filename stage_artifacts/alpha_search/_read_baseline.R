b <- readRDS("G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/_exp_baseline.rds")
cat("top names:", paste(names(b), collapse=","), "\n")
cat("nrow(dt):", nrow(b$dt), " range:", as.character(min(b$dt$period_end)), "~", as.character(max(b$dt$period_end)), "\n")
r <- b$rep
cat("rep names:", paste(names(r), collapse=","), "\n")
pr <- function(m){
  if(is.null(m)){ cat("  (insufficient)\n"); return(invisible()) }
  lab <- as.character(m$label)[1]
  cat(sprintf("  %-26s n=%3d SR_tot=%.4f SR_act=%.4f CAGR=%.4f MDD=%.4f Calmar=%.3f TO=%.2f\n",
      lab, m$n, m$sr_total, m$sr_active, m$cagr, m$mdd,
      ifelse(is.na(m$calmar), -99, m$calmar), m$ann_to))
}
cat("--- BASELINE ---\n")
pr(r$full); pr(r$is); pr(r$oos); pr(r$early); pr(r$late)
cat(sprintf("  oos_retention(active)=%.4f total=%.4f\n", r$oos_retention_active, r$oos_retention_total))
