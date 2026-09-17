suppressPackageStartupMessages(library(jsonlite))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
led <- fromJSON(file.path(root, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
e1 <- led$entries[[1]]
ap <- file.path(e1$base_artifacts, "authoritative_remeasure.json")
j <- fromJSON(ap, simplifyVector = FALSE)
cat("TOP KEYS:", paste(names(j), collapse = ", "), "\n\n")
str(j$essence, max.level = 1, list.len = 30)
cat("\nessence_grade:", j$essence_grade %||% "NULL", "\n")
