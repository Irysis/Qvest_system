suppressMessages(library(arrow)); suppressMessages(library(data.table))
root <- "G:/Quant_Module_Moltbot"
s <- as.data.table(read_parquet(file.path(root, ".cache/universe_support/us_sector_lv2.parquet")))
cat("=== lv2 ===\n")
cat("cols:", paste(names(s), collapse=", "), "\n")
cat("nrow:", nrow(s), "\n")
print(head(s, 4))
dc <- grep("ate|Date", names(s), value=TRUE)[1]
cat("datecol:", dc, "range:", as.character(range(s[[dc]], na.rm=TRUE)), "\n")
sc <- setdiff(names(s), c(dc, grep("icker|Ticker|ode|Code", names(s), value=TRUE)))
for (c in names(s)) cat("  col", c, "class", class(s[[c]])[1], "uniq", length(unique(s[[c]])), "sample:", paste(head(unique(s[[c]]),6), collapse="|"), "\n")

cat("\n=== lv1 ===\n")
s1 <- as.data.table(read_parquet(file.path(root, ".cache/universe_support/us_sector_lv1.parquet")))
cat("cols:", paste(names(s1), collapse=", "), "\n")
print(head(s1, 3))
for (c in names(s1)) cat("  col", c, "uniq", length(unique(s1[[c]])), "\n")
