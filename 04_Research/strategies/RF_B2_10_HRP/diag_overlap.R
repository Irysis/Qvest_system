suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
a <- fread("04_Research/strategies/RF_B2_10_HRP/stage/20260829_233456_7952/04_holdings.csv")
b <- fread("04_Research/strategies/RF_B1_5_MomIlliq/stage/20260829_230711_27764/04_holdings.csv")
cat("cols A:", paste(names(a), collapse = ","), "\n")
dc <- intersect(names(a), c("Date", "date", "Signal_Date", "rebalance_date"))[1]
tc <- intersect(names(a), c("Ticker", "ticker"))[1]
cat("date col:", dc, "| ticker col:", tc, "\n")
A <- unique(a[, .(d = get(dc), t = get(tc))])
B <- unique(b[, .(d = get(dc), t = get(tc))])
ov <- merge(A[, .N, by = d], merge(A, B, by = c("d", "t"))[, .N, by = d],
            by = "d", suffixes = c("_a", "_ov"))
cat(sprintf("공통 리밸일 %d | 종목 겹침 median %.1f/%.1f (%.1f%%) | min %.0f\n",
            nrow(ov), median(ov$N_ov), median(ov$N_a),
            100 * median(ov$N_ov / ov$N_a), min(ov$N_ov)))
