#==============================================================================
# Diagnose Regime Correlation Bug
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
base_dir <- file.path(PROJ, "qepm/mailbox/worktask/WT-T20260508_004/output/5family_post_incremental")

s0 <- fread(file.path(base_dir, "S0_baseline/03_period_returns.csv"))[, .(date, ret_net)]
setnames(s0, "ret_net", "str1715")

s1 <- fread(file.path(base_dir, "S1_KR10y_only/03_period_returns.csv"))[, .(date, ret_net)]
setnames(s1, "ret_net", "kr10y")

s2 <- fread(file.path(base_dir, "S2_TSMOM_only/03_period_returns.csv"))[, .(date, ret_net)]
setnames(s2, "ret_net", "tsmom")

dt <- merge(s0, s1, by = "date", all = TRUE)
dt <- merge(dt, s2, by = "date", all = TRUE)
dt[, date := as.Date(date)]
setkey(dt, date)

cat("=== Full period correlation ===\n")
print(cor(dt[, .(str1715, kr10y, tsmom)], use = "complete.obs"))

cat("\n=== Sample rows ===\n")
print(head(dt, 10))

cat("\n=== Vol (annualized) ===\n")
cat(sprintf("str1715: %.4f%%\n", sd(dt$str1715, na.rm=TRUE)*sqrt(12)*100))
cat(sprintf("kr10y: %.4f%%\n", sd(dt$kr10y, na.rm=TRUE)*sqrt(12)*100))
cat(sprintf("tsmom: %.4f%%\n", sd(dt$tsmom, na.rm=TRUE)*sqrt(12)*100))

cat("\n=== Mean ===\n")
cat(sprintf("str1715: %.4f\n", mean(dt$str1715, na.rm=TRUE)))
cat(sprintf("kr10y: %.4f\n", mean(dt$kr10y, na.rm=TRUE)))
cat(sprintf("tsmom: %.4f\n", mean(dt$tsmom, na.rm=TRUE)))

# Check if kr10y_only / tsmom_only is really independent or just str1715 differently weighted
cat("\n=== Row 1-10 comparison ===\n")
print(dt[1:10, .(date, str1715, kr10y, tsmom)])
