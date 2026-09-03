suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SD <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
b <- bm[Date >= as.Date("2005-02-03") & Date <= as.Date("2026-08-28")]
n <- nrow(b)
cat("harness BM (.cache/benchmark.parquet):\n")
cat("  n =", n, " cum =", prod(1 + b$BM_Ret) - 1,
    " CAGR =", prod(1 + b$BM_Ret)^(252 / n) - 1, "\n")
cat("  BM_Close first/last:", b$BM_Close[1], b$BM_Close[n],
    " price CAGR =", (b$BM_Close[n] / b$BM_Close[1])^(252 / n) - 1, "\n")

p <- fread(file.path(SD, "period_returns_production.csv"))
cat("\nperiod_returns_production.csv cols:", paste(names(p), collapse = ","), " rows =", nrow(p), "\n")
print(head(p, 3)); print(tail(p, 3))
