ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
say <- function(...) cat(sprintf(...), "\n")
r <- readRDS(file.path(OUT, "wt122_results.rds"))
say("results names: %s", paste(names(r), collapse=", "))
say("=== F3 ===")
for (n in names(r$F3)) { say("-- %s --", n); print(unlist(r$F3[[n]])) }
say("=== F2 ===")
for (n in names(r$F2)) { say("-- %s --", n); print(unlist(r$F2[[n]])) }
a <- readRDS(file.path(OUT, "wt122_addendum.rds"))
say("=== addendum ===")
for (n in names(a)) { say("-- %s --", n); print(unlist(a[[n]])) }
