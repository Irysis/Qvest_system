# debug_one_catalog.R — inspect pool sources (module_catalog + sim_result.rds + batch_434 rds)
# Run: Rscript -e 'source("02_Infrastructure/ramp/debug/debug_one_catalog.R")'  (from QM_ROOT)
suppressMessages({ library(jsonlite); library(data.table) })

dir.create(".cache/scratch/ramp_debug", recursive = TRUE, showWarnings = FALSE)
sink(".cache/scratch/ramp_debug/debug_catalog_out.txt")

cat("===== module_catalog.json =====\n")
mc <- fromJSON("06_Registry/module_catalog.json", simplifyVector = FALSE)
cat("class:", class(mc), " len:", length(mc), "\n")
cat("top names:", paste(head(names(mc), 15), collapse=" | "), "\n\n")

# locate the module array
mod_list <- NULL; mod_key <- NULL
if (is.null(names(mc))) { mod_list <- mc; mod_key <- "<root unnamed list>" } else {
  for (nm in names(mc)) {
    x <- mc[[nm]]
    if (is.list(x) && length(x) > 10 && is.null(names(x[[1]])) == FALSE) { mod_list <- x; mod_key <- nm; break }
    if (is.list(x) && length(x) > 10 && is.list(x[[1]])) { mod_list <- x; mod_key <- nm; break }
  }
}
cat("module list key:", mod_key, " n_modules:", length(mod_list), "\n")
if (!is.null(mod_list) && length(mod_list) > 0) {
  e1 <- mod_list[[1]]
  cat("first module keys:", paste(names(e1), collapse=", "), "\n\n")
  cat("first module dump:\n"); str(e1, max.level = 2, list.len = 30)
  # look for sim_result_path-like field
  cat("\nsearching for path-like fields across first 3 modules:\n")
  for (i in 1:min(3, length(mod_list))) {
    m <- mod_list[[i]]
    pk <- names(m)[grepl("path|rds|sim|nav|result", names(m), ignore.case = TRUE)]
    cat(sprintf("  [%d] id-ish=%s ; path-fields: %s\n",
        i, paste(unlist(m[intersect(c("module_id","id","name","strategy_id"), names(m))]), collapse="/"),
        paste(pk, collapse=", ")))
    for (k in pk) cat(sprintf("       %s = %s\n", k, as.character(m[[k]])[1]))
  }
}

cat("\n===== sample sim_result.rds (main process) =====\n")
# find one sim_result_path that exists
sim_path <- NULL
if (!is.null(mod_list)) {
  for (m in mod_list) {
    for (k in names(m)) {
      v <- m[[k]]
      if (is.character(v) && length(v)==1 && grepl("sim_result.*\\.rds$", v, ignore.case=TRUE)) {
        if (file.exists(v)) { sim_path <- v; break }
      }
    }
    if (!is.null(sim_path)) break
  }
}
cat("sim_path found:", if (is.null(sim_path)) "<none in catalog>" else sim_path, "\n")
if (!is.null(sim_path)) {
  sr <- readRDS(sim_path)
  cat("sim_result class:", class(sr), " names:", paste(names(sr), collapse=", "), "\n")
  if (!is.null(sr$DAILY_NAV_DT)) {
    d <- sr$DAILY_NAV_DT
    cat("DAILY_NAV_DT class:", class(d)[1], " cols:", paste(names(d), collapse=", "), " nrow:", nrow(d), "\n")
    print(head(d, 3))
  }
}

cat("\n===== batch_434 sample _result.rds (ISOLATED read test) =====\n")
b <- list.files("stage_artifacts/batch_434", pattern="_result\\.rds$", recursive=TRUE, full.names=TRUE)
cat("n batch_434 rds:", length(b), "\n")
cat("first 3:\n"); cat(paste(head(b,3), collapse="\n"), "\n")

sink()
cat("debug_one_catalog done -> .cache/scratch/ramp_debug/debug_catalog_out.txt\n")
