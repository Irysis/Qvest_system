#==============================================================================
# G12 Batch Runner: Run STR_354~372 sequentially
# Collects results into a summary table
#==============================================================================
cat("[G12 Runner] Starting batch execution...\n")
t0 <- Sys.time()

PROJECT_ROOT <- tryCatch({
  d <- dirname(sys.frame(1)$ofile)
  dirname(dirname(d))
}, error = function(e) getwd())

strat_dir <- file.path(PROJECT_ROOT, "research_output", "strategies")

# List of strategies to run (353 already done)
str_ids <- 354:372
results <- list()

for (sid in str_ids) {
  str_name <- list.files(strat_dir, pattern = sprintf("^STR_%03d_", sid), full.names = FALSE)
  if (length(str_name) == 0) { cat(sprintf("  Skip: STR_%03d not found\n", sid)); next }

  str_path <- file.path(strat_dir, str_name)
  run_file <- file.path(str_path, "run_all.R")
  if (!file.exists(run_file)) { cat(sprintf("  Skip: %s/run_all.R not found\n", str_name)); next }

  cat(sprintf("\n========== STR_%03d (%s) ==========\n", sid, str_name))
  t1 <- Sys.time()

  tryCatch({
    # Clean up from previous strategy
    rm(FACTORS, sim, perf, hurdle, envir = .GlobalEnv)
  }, error = function(e) {})

  result <- tryCatch({
    old_wd <- getwd()
    setwd(str_path)
    source("run_all.R", local = FALSE)
    setwd(old_wd)

    # Read hurdle result
    hurdle_file <- file.path(str_path, "output", "hurdle_result.json")
    if (file.exists(hurdle_file)) {
      h <- jsonlite::fromJSON(hurdle_file)
      data.frame(
        STR = sprintf("STR_%03d", sid),
        Name = str_name,
        Grade = h$grade,
        Score = h$total_score,
        CAGR = round(h$metrics$ann_ret * 100, 1),
        Sharpe = round(h$metrics$sharpe, 3),
        MDD = round(h$metrics$mdd * 100, 1),
        IR = round(h$metrics$ir, 3),
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(STR = sprintf("STR_%03d", sid), Name = str_name,
                 Grade = "ERR", Score = NA, CAGR = NA, Sharpe = NA, MDD = NA, IR = NA,
                 stringsAsFactors = FALSE)
    }
  }, error = function(e) {
    cat(sprintf("  ERROR: %s\n", e$message))
    setwd(old_wd)
    data.frame(STR = sprintf("STR_%03d", sid), Name = str_name,
               Grade = "ERR", Score = NA, CAGR = NA, Sharpe = NA, MDD = NA, IR = NA,
               stringsAsFactors = FALSE)
  })

  elapsed <- round(as.numeric(difftime(Sys.time(), t1, units = "secs")), 0)
  cat(sprintf("  Elapsed: %ds\n", elapsed))
  results[[length(results) + 1]] <- result
}

# Summary
summary_dt <- do.call(rbind, results)
cat("\n\n========== G12 BATCH SUMMARY ==========\n")
print(summary_dt[order(-summary_dt$Score), ])

# Save
out_path <- file.path(PROJECT_ROOT, "research_output", "regime_comparison", "output", "g12_batch_summary.csv")
write.csv(summary_dt, out_path, row.names = FALSE)
cat(sprintf("\nSaved: %s\n", out_path))

total_elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
cat(sprintf("[G12 Runner] Complete. Total: %.1f minutes\n", total_elapsed))
