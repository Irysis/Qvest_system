setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages(library(data.table))

pan <- readRDS("stage_artifacts/WT_D20260809_001/p0_panels.rds")
cat("== panels names ==\n"); print(names(pan))
ret <- as.data.table(pan$ret)
cat("== ret dims ==\n"); print(dim(ret))
cat("== ret cols ==\n"); print(names(ret))
cat("== ret Date class ==\n"); print(class(ret$Date))
cat("== ret Date range ==\n"); print(range(ret$Date))
ud <- sort(unique(ret$Date))
cat("n unique Date (all):", length(ud), "\n")
cat("first 6:\n"); print(head(ud))
cat("last 6:\n"); print(tail(ud))
# day-of-month distribution to confirm month-end
cat("== day-of-month table (all unique dates) ==\n")
print(table(as.integer(format(as.Date(ud), "%d"))))

sel <- ud[ud >= as.Date("2003-01-01") & ud <= as.Date("2026-06-30")]
cat("n unique Date in [2003-01-01, 2026-06-30]:", length(sel), "\n")
cat("head:\n"); print(head(sel, 3)); cat("tail:\n"); print(tail(sel, 3))
cat("n unique ym:", length(unique(format(as.Date(sel), "%Y-%m"))), "\n")

idx <- seq(4L, length(sel), by = 4L)
cat("slice_3 idx n:", length(idx), " first:", idx[1], " last:", idx[length(idx)], "\n")
cat("slice_3 first date:", format(as.Date(sel[idx[1]])), " last date:", format(as.Date(sel[idx[length(idx)]])), "\n")

FN <- readLines("stage_artifacts/FQ176/factor_set.txt")
FN <- trimws(FN); FN <- FN[nzchar(FN)]
cat("n factors:", length(FN), "\n")

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
d <- as.Date(sel[idx[1]])
cat("== test load month:", format(d), "==\n")
t0 <- Sys.time()
Fx <- as.data.table(load_month_factors(d, factor_names = FN))
cat("elapsed sec:", round(as.numeric(difftime(Sys.time(), t0, units="secs")),2), "\n")
cat("dim:\n"); print(dim(Fx))
cat("cols:\n"); print(names(Fx))
cat("n factors returned:", length(unique(Fx$Factor_Name)), "\n")
cat("missing factors:\n"); print(setdiff(FN, unique(Fx$Factor_Name)))
cat("str head:\n"); print(head(Fx, 3))
