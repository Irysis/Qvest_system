suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds")
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
cat("== factor_long ==\n"); cat("rows:", nrow(A), "\n"); print(names(A))
cat("n_factors:", uniqueN(A$Factor_Name), " n_months:", uniqueN(A$Date), "\n")
cat("date range:", as.character(min(A$Date)), as.character(max(A$Date)), "\n")
cat("day-of-month median:", median(as.integer(format(A$Date,"%d"))), "\n")
cat("== mkt ==\n"); print(names(M))
for (nm in names(M)) { x <- as.data.table(M[[nm]]); cat(nm, "rows:", nrow(x), " cols:", paste(names(x),collapse=","), "\n") }
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
cat("ret rows(non-NA):", nrow(ret), " months:", uniqueN(ret$Date), " range:", as.character(min(ret$Date)), as.character(max(ret$Date)), "\n")
Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")
cat("== FQ191 rule ==\n"); print(names(Mru)); print(head(Mru,3)); cat("rows:", nrow(Mru), "\n")
Mru[, date := as.Date(date)]
cat("rule range:", as.character(min(Mru$date)), as.character(max(Mru$date)), " dom median:", median(as.integer(format(Mru$date,"%d"))), "\n")
cat("regime class:", class(Mru$regime), " table:\n"); print(table(Mru$regime))
Mru2 <- Mru[date < as.Date("2026-01-01")]
cat("rule<2026 rows:", nrow(Mru2), " ON:", sum(as.integer(Mru2$regime)), "\n")
FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 1]
cat("shard size:", length(mine), "of", length(FN), "\n")
writeLines(mine, "stage_artifacts/pg2_hunt/s1_shard.txt")
print(mine)
