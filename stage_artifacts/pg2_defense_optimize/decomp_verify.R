## Crisis-vs-normal decomposition of the c3 marginal + overlay-saturation check.
suppressWarnings(suppressMessages(library(data.table)))
DIR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_defense_optimize"
c3 <- fread(file.path(DIR,"c3_swap_D45_monthly_ic.csv"))
c3[, d := ret_cand - ret_cur]
c3[, ym := realized_ym]
# crisis episode months (approx from episodes.csv windows)
crisis_ranges <- list(
  c("2008-06","2009-03"), c("2011-08","2011-11"), c("2015-06","2016-02"),
  c("2018-10","2018-12"), c("2020-02","2020-04"), c("2021-06","2022-10"),
  c("2024-08","2024-08"), c("2026-02","2026-02"))
in_crisis <- rep(FALSE, nrow(c3))
for(r in crisis_ranges) in_crisis <- in_crisis | (c3$ym>=r[1] & c3$ym<=r[2])
cat(sprintf("crisis months=%d normal months=%d\n", sum(in_crisis), sum(!in_crisis)))
cat(sprintf("[c3] mean_d CRISIS =%+.6f (t=%+.2f, n=%d)\n",
   mean(c3$d[in_crisis]), mean(c3$d[in_crisis])/(sd(c3$d[in_crisis])/sqrt(sum(in_crisis))), sum(in_crisis)))
cat(sprintf("[c3] mean_d NORMAL =%+.6f (t=%+.2f, n=%d)\n",
   mean(c3$d[!in_crisis]), mean(c3$d[!in_crisis])/(sd(c3$d[!in_crisis])/sqrt(sum(!in_crisis))), sum(!in_crisis)))
cat(sprintf("[c3] share of total cum-d from crisis months = %.1f%%\n",
   100*sum(c3$d[in_crisis])/sum(c3$d)))
# where does the +SR come from: sd reduction vs mean lift?
cat(sprintf("[c3] mean(cand)=%+.6f mean(cur)=%+.6f | sd(cand)=%.6f sd(cur)=%.6f\n",
   mean(c3$ret_cand), mean(c3$ret_cur), sd(c3$ret_cand), sd(c3$ret_cur)))
cat(sprintf("[c3] SR gain source: mean contributes, sd_ratio=%.4f (=<1 means vol-reduction driven)\n",
   sd(c3$ret_cand)/sd(c3$ret_cur)))
