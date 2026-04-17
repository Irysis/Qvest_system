## STR_1340 Phase 1-2 Cache Builder
## Saves intermediate combined_ret (before overlays) for S5 variants
## Run once, then STR_1343/1344/1345 load this cache

CACHE_FILE <- file.path(SCRIPT_DIR, "phase2_cache.rds")

if (file.exists(CACHE_FILE)) {
  cat("[Cache] Loading Phase 1-2 cache...\n")
  .cache <- readRDS(CACHE_FILE)
  combined_ret <- .cache$combined_ret
  common_idx   <- .cache$common_idx
  sim_def      <- .cache$sim_def
  RAWDATA_ORIG <- .cache$RAWDATA_ORIG
  BM_DT_ORIG   <- .cache$BM_DT_ORIG
  n <- length(common_idx)
  cat(sprintf("[Cache] Loaded: %d days (%s ~ %s)\n", n, min(common_idx), max(common_idx)))
} else {
  stop("[Cache] phase2_cache.rds not found. Run STR_1340 first or build cache.")
}
