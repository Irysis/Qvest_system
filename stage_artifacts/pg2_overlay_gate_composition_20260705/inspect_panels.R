suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
opts <- options(width=200)
cat("================ 1. WT-H20260513_001 extended panel (Track A) ================\n")
p1 <- fread("qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv")
cat("dims:", dim(p1)[1], "x", dim(p1)[2], "\n")
cat("cols:", paste(names(p1), collapse=" | "), "\n\n")
print(head(p1, 3)); cat("...\n"); print(tail(p1, 2))

cat("\n================ 2. no_faith source: period_returns_layer5_faith.csv ================\n")
f1 <- "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"
if (file.exists(f1)) {
  p2 <- fread(f1)
  cat("dims:", dim(p2)[1], "x", dim(p2)[2], "\n")
  cat("cols:", paste(names(p2), collapse=" | "), "\n\n")
  print(head(p2, 3)); cat("...\n"); print(tail(p2, 2))
} else cat("NOT FOUND:", f1, "\n")

cat("\n================ 3. alpha_scores_str1715_268m.parquet (Track B) ================\n")
a1 <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
if (file.exists(a1)) {
  s1 <- as.data.table(read_parquet(a1))
  cat("dims:", dim(s1)[1], "x", dim(s1)[2], "\n")
  cat("cols:", paste(names(s1), collapse=" | "), "\n")
  cat("n months:", length(unique(s1$Date)), " date range:", as.character(min(s1$Date)), "->", as.character(max(s1$Date)), "\n")
  cat("regime_state values:", paste(unique(s1$regime_state), collapse=", "), "\n\n")
  print(head(s1[!is.na(score_eff)], 4))
} else cat("NOT FOUND:", a1, "\n")

cat("\n================ 4. alpha_scores_r05_panel.parquet ================\n")
a2 <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet"
if (file.exists(a2)) {
  s2 <- as.data.table(read_parquet(a2))
  cat("cols:", paste(names(s2), collapse=" | "), "\n")
} else cat("NOT FOUND:", a2, "\n")

cat("\n================ 5. audit_layer_timing_book_comparison.csv ================\n")
ac <- "stage_artifacts/pg2_offense_overlay/audit_layer_timing_book_comparison.csv"
if (file.exists(ac)) { print(fread(ac)) } else cat("NOT FOUND\n")

cat("\n================ 6. benchmark_pinned_20260702.parquet ================\n")
bp <- "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet"
if (file.exists(bp)) {
  b <- as.data.table(read_parquet(bp)); cat("cols:", paste(names(b), collapse=" | "), " rows:", nrow(b), "\n"); print(head(b,3))
} else cat("NOT FOUND\n")

cat("\n================ 7. contract functions present? ================\n")
for (f in c("02_Infrastructure/contracts/backtest_result_contract.R",
            "02_Infrastructure/contracts/canonical_screen_bt.R")) {
  cat(f, ":", ifelse(file.exists(f), "OK", "MISSING"), "\n")
}
