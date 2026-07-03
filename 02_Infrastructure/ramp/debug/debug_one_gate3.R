# debug_one_gate3.R — debug-first Gate 3 on the REAL pool (264 + batch_434)
# Run: Rscript --vanilla -e 'source("02_Infrastructure/ramp/debug/debug_one_gate3.R")'
suppressMessages({ library(data.table) })
sink("02_Infrastructure/ramp/debug/_debug_gate3_out.txt", split = TRUE)
t0 <- Sys.time()

source("02_Infrastructure/ramp/strategy_return_matrix.R")
config <- .ramp_load_config()

cat("===== build_pool_return_matrix =====\n")
pool <- build_pool_return_matrix(config)
cat(sprintf("R dim: %d x %d (T days x N strat)\n", nrow(pool$R), ncol(pool$R)))
cat(sprintf("date range: %s .. %s\n", min(pool$dates), max(pool$dates)))
cat(sprintf("n_catalog NAV: %d | n_batch434 NAV: %d | kept(min_obs): %d\n",
            pool$n_catalog, pool$n_batch434, pool$n_kept))
cat(sprintf("excluded rows: %d\n", nrow(pool$excluded)))
if (nrow(pool$excluded)) {
  cat("exclusion reason counts:\n")
  print(pool$excluded[, .N, by = .(source, reason)][order(-N)])
}
cat("source breakdown of kept:\n"); print(pool$meta[, .N, by = source])

# data completeness
na_frac <- mean(is.na(pool$R))
cat(sprintf("matrix NA fraction: %.3f\n", na_frac))

cat("\n===== compute_strategy_similarity =====\n")
sim <- compute_strategy_similarity(pool$R, min_overlap = 252L)
rc <- sim$return_corr
cat("return_corr diag all 1?:", all(abs(diag(rc) - 1) < 1e-9), "\n")
cat("symmetric?:", isTRUE(all.equal(rc, t(rc), check.attributes = FALSE)), "\n")
offdiag <- rc[upper.tri(rc)]
cat(sprintf("offdiag return_corr: median=%.3f  p90=%.3f  max=%.3f  (NA frac=%.3f)\n",
            median(offdiag, na.rm = TRUE), quantile(offdiag, .9, na.rm = TRUE),
            max(offdiag, na.rm = TRUE), mean(is.na(offdiag))))
cat("turnover_similarity status:", sim$turnover_similarity, "\n")

cat("\n===== cluster_strategies =====\n")
cl <- cluster_strategies(sim, pool$meta, config)
cat(sprintf("n_clusters: %d | representatives: %d | dedup_dropped: %d\n",
            cl$n_clusters, cl$n_representatives, cl$n_dedup_dropped))
cat("family_rule:", cl$family_rule, " dedup_thr:", cl$dedup_thr, "\n")
cat("largest clusters:\n")
print(cl$clusters[, .N, by = cluster_id][order(-N)][1:8])

cat(sprintf("\n[gate3 debug] elapsed: %.1f sec\n", as.numeric(Sys.time() - t0, units = "secs")))
sink()
cat("debug_one_gate3 done\n")
