suppressPackageStartupMessages(library(jsonlite))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
led <- fromJSON(file.path(root, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
ks <- sort(unique(unlist(lapply(led$entries, names))))
cat("ENTRY KEYS:\n"); print(ks)
p <- Filter(function(e) !is.null(e$parent), led$entries)
cat("\nn entries with parent:", length(p), "\n")
cat("parent keys:", paste(sort(unique(unlist(lapply(p, function(e) names(e$parent))))), collapse = ", "), "\n")
for (e in p) cat(sprintf("  %-54s d=%s parent=%-40s pbest=%s\n",
                         e$base_id, e$parent$depth, e$parent$base_id, format(e$parent$best_port_t)))
cat("\ncarry keys:", paste(sort(unique(unlist(lapply(p, function(e) names(e$carry))))), collapse = ", "), "\n")
e1 <- led$entries[[1]]
cat("sample base_grade:", e1$base_grade, "\n  base_artifacts:", e1$base_artifacts, "\n")
ap <- file.path(e1$base_artifacts, "authoritative_remeasure.json")
cat("  artifacts exists:", file.exists(ap), "\n")
