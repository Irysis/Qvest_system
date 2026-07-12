suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260711_002/delta_ext")
r <- readRDS("delta_results.rds")
cat("delta docs:", r$D_docs, " tickers:", r$D_tickers, "\n\n")
for(cn in names(r$results)){
  x <- r$results[[cn]]
  cat(sprintf("=== %s : %s carry=%dm | names/mo=%.1f sigmo=%d | rank-IC=%.4f ICIR=%.3f Harvey-t=%.3f (nmo=%d)\n",
    cn, x$cfg$form, x$cfg$carry, x$avg_names_mo, x$signal_months, x$rank_ic_mean, x$icir, x$rank_ic_harvey_t, x$rank_ic_nmonths))
  cat(sprintf("   FULL: capw_PORT_t=%.3f pval=%.3f IR=%.3f netSR=%.3f turn=%.2f | EW_t=%.3f EWpost17=%.3f | mega=%.3f mid=%.3f other=%.3f\n",
    x$full$port_t, x$full$pval, x$full$IR, x$full$net_sr, x$full$turnover, x$full$ew_port_t, x$full$ew_post2017_t, x$full$mega_w, x$full$mid_w, x$full$other_w))
  cat(sprintf("   IS  : capw_PORT_t=%.3f netSR=%.3f | OOS: capw_PORT_t=%.3f netSR=%.3f\n\n",
    x$IS$port_t, x$IS$net_sr, x$OOS$port_t, x$OOS$net_sr))
}
cat("Size control (c1):\n"); print(r$size_ctrl)
cat("Market split (c1):\n"); print(r$mkt_split)
cat("Placebo (c1):\n"); print(r$placebo_c1)
cat("null_max_t_delta:", r$null_max_t_delta, "\n")
