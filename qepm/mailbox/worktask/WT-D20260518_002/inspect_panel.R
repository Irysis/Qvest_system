suppressPackageStartupMessages({ library(data.table); library(arrow) })
p <- as.data.table(arrow::read_parquet("stage_artifacts/WT_D20260518_002/alpha_scores.parquet"))
cat("Columns:", paste(names(p), collapse=", "), "\n")
cat("Total rows:", nrow(p), "\n")
cat("Sleeve summary:\n")
print(p[, .(n = .N, n_dates = uniqueN(Date), n_tick = uniqueN(Ticker)), by = sleeve])

cat("\n--- S3 sample ---\n")
s3 <- p[sleeve == "Sleeve_3_KR_10y_bond"]
print(head(s3))
cat("S3 Ret_1m_PIT summary:\n"); print(summary(s3$Ret_1m_PIT))
cat("S3 score summary:\n"); print(summary(s3$score))
cat("S3 weight_target_in_sleeve summary:\n"); print(summary(s3$weight_target_in_sleeve))

cat("\n--- S2 sample ---\n")
s2 <- p[sleeve == "Sleeve_2_TSMOM_ETF_rotation_8_assets"]
print(head(s2, 3))
cat("S2 unique tickers:", paste(unique(s2$Ticker), collapse=", "), "\n")
cat("S2 Ret_1m_PIT summary:\n"); print(summary(s2$Ret_1m_PIT))
cat("S2 weight per Date sum (head):\n")
ws <- s2[, .(sum_w = sum(weight_target_in_sleeve, na.rm=TRUE)), by = Date]
print(head(ws, 5))

cat("\n--- S1 sample ---\n")
s1 <- p[sleeve == "Sleeve_1_STR_1715_AR_on_M4_R05_overlay_PG2"]
print(head(s1, 3))
cat("S1 Ret_1m_PIT summary:\n"); print(summary(s1$Ret_1m_PIT))
