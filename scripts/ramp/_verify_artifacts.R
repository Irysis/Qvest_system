suppressMessages({library(data.table);library(arrow)})
sink("scripts/ramp/_verify_out.txt")
# approved factor library
av <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
cat("=== approved_factor_library (20 factors) ===\n")
print(av[order(-rank_ic_ir), .(factor_id, status, rank_ic_ir=round(rank_ic_ir,3),
   spread=round(net_quintile_spread_oos,4), cost_drag=round(cost_drag,3),
   net_sr=round(net_sr,3), port_t=round(portfolio_alpha_t_nw,2), metric_type)])
cat("\napproved:", sum(av$status=="approved"), "/", nrow(av), "\n")

# §2.4 meta check
cat("\n=== §2.4 meta + security_id field check (all artifacts) ===\n")
chk <- function(f) {
  d <- as.data.table(read_parquet(f))
  meta_ok <- all(c("as_of_date","generated_at","source_version","security_id_field") %in% names(d))
  cat(sprintf("  %-55s meta=%s id_field=%s\n", basename(f), meta_ok,
              if("security_id_field" %in% names(d)) d$security_id_field[1] else "MISSING"))
}
for (f in list.files("outputs/ramp", pattern="parquet$", full.names=TRUE)) chk(f)
for (f in c("06_Registry/ramp/approved_factor_library.parquet","06_Registry/ramp/strategy_inventory.parquet")) chk(f)

# clusters/dedup summary
cl <- as.data.table(read_parquet("outputs/ramp/strategy_clusters.parquet"))
cat("\n=== dedup ===\n")
cat("n_strategies:", nrow(cl), " dedup_dropped:", sum(cl$dedup_dropped),
    " unique:", sum(!cl$dedup_dropped), " clusters:", uniqueN(cl$cluster_id), "\n")

# residual candidates
rc <- as.data.table(read_parquet("outputs/ramp/residual_alpha_candidates.parquet"))
rc2 <- rc[is_dedup_unique==TRUE & unexplained_var_frac>0.5][order(-unexplained_var_frac)]
cat("\n=== residual-alpha candidates (top 8) ===\n")
print(head(rc2[, .(strategy_id, unexplained=round(unexplained_var_frac,3), source, grade)], 8))
sink(); cat("verify done\n")
