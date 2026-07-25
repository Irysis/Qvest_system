# debug_two_gate3_cluster.R — fast iterate on similarity+clustering using cached pool matrix
suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/strategy_return_matrix.R")
config <- .ramp_load_config()

cache <- "02_Infrastructure/ramp/debug/_cache_pool.rds"
if (file.exists(cache)) {
  cat("[debug2] loading cached pool matrix\n"); pool <- readRDS(cache)
} else {
  cat("[debug2] building pool matrix (slow, ~160s)...\n")
  pool <- build_pool_return_matrix(config)
  saveRDS(pool, cache); cat("[debug2] cached -> ", cache, "\n")
}

dir.create(".cache/scratch/ramp_debug", recursive = TRUE, showWarnings = FALSE)
sink(".cache/scratch/ramp_debug/debug_gate3_cluster.txt", split = TRUE)
cat(sprintf("pool: %d x %d ; kept=%d\n", nrow(pool$R), ncol(pool$R), pool$n_kept))

sim <- compute_strategy_similarity(pool$R, min_overlap = 252L)
cl <- cluster_strategies(sim, pool$meta, config, n_family_clusters = 12L)

cat("\n=== clustering ===\n")
cat(sprintf("family clusters: %d (%s)\n", cl$n_clusters, cl$family_method))
cat(sprintf("representatives: %d | dedup_dropped(>%.2f): %d | unique_after_dedup: %d\n",
            cl$n_representatives, cl$dedup_thr, cl$n_dedup_dropped, cl$n_unique_after_dedup))
cat("DIAGNOSTIC:", cl$diagnostic_note, "\n")
cat(sprintf("median offdiag return_corr: %.3f\n", cl$median_offdiag_return_corr))
cat("\ncluster sizes:\n")
print(cl$clusters[, .(cluster_size = .N), by = cluster_id][order(-cluster_size)])
cat("\ncluster x source crosstab:\n")
print(dcast(cl$clusters, cluster_id ~ source, fun.aggregate = length, value.var = "strategy_id"))

# SDS proxy: how well does dedup/cluster reduce redundancy?
#   SDS(>=80) = 아키텍처/프로세스 준수 점수. 여기선 측정 가능한 구성요소만 산출.
cat("\n=== SDS components (measured) ===\n")
meta_complete <- mean(!is.na(pool$meta$origin_mode))  # meta>=95%?
overlay_inferred <- mean(grepl("inferred", cl$clusters$overlay_tag))  # overlay>=90%?
cat(sprintf("meta completeness(origin_mode non-NA): %.1f%%\n", 100*meta_complete))
cat(sprintf("overlay tag inferred rate: %.1f%%\n", 100*overlay_inferred))
cat(sprintf("similarity dims live: return,rank,drawdown (3/4) ; turnover=unavailable\n"))
cat(sprintf("dedup reduction: %d -> %d (%.1f%% redundant removed)\n",
            ncol(pool$R), cl$n_unique_after_dedup, 100*cl$n_dedup_dropped/ncol(pool$R)))
sink()
cat("debug_two_gate3_cluster done\n")
