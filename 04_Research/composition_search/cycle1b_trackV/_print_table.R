# _print_table.R - compact verdict table for the final report (read-only)
suppressMessages(library(data.table))
TV <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1b_trackV"
A <- fread(file.path(TV, "variation_results.csv"))
cols <- c("run_id","axis","full_sr_net","full_mdd_pct","full_to_oneway","full_cost_pct",
          "full_port_t","is_sr_net","oos_sr_net","r2017_sr_net","d_is_sr","d_oos_sr",
          "d_full_cost_pct","verdict","dsr_full_active_n38")
for (b in unique(A$base_id)) {
  cat("\n====", b, "====\n")
  print(A[base_id == b, ..cols], digits = 4, nrows = 30)
}
imp <- A[verdict == "IMPROVED"]
cat("\n==== IMPROVED runs ====\n")
print(imp[, .(base_id, run_id, axis, d_is_sr, d_oos_sr, d_full_sr, d_full_cost_pct,
              full_sr_net, full_mdd_pct, full_port_t, dsr_full_active_n38)])
