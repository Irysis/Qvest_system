setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
suppressMessages(library(arrow)); suppressMessages(library(data.table)); suppressMessages(library(jsonlite))
OUT <- "04_Research/method_frontier/wt006_exog_forecast"

evl <- function(fn, lab){
  th <- as.data.table(read_parquet(file.path(OUT, fn)))
  m <- eval_theta(th, lab)
  cat(sprintf("\n=== %s ===\n", lab))
  for(k in names(m)) cat(sprintf("  %-20s %s\n", k, as.character(m[[k]])))
  m
}
m_reg <- evl("theta_R2_rank_target.parquet", "rank_target(reg)")
m_rk  <- evl("theta_R2_rank_target_ranker.parquet", "rank_target(ranker)")

# pick primary = the one with higher paired_vs_mom_t (IS-agnostic report; both shown)
prim <- if(is.finite(m_rk$paired_vs_mom_t) && m_rk$paired_vs_mom_t > m_reg$paired_vs_mom_t) m_rk else m_reg
cat(sprintf("\n[baseline momentum port_t] %.3f\n", .BASELINE_MOM_PORT_T))
out <- list(reg=m_reg, ranker=m_rk, primary_label=prim$label, baseline_mom_port_t=.BASELINE_MOM_PORT_T)
write_json(out, file.path(OUT,"rank_target_eval.json"), auto_unbox=TRUE, digits=4)
cat("saved rank_target_eval.json\n")
