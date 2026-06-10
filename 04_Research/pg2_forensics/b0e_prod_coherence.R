# b0e_prod_coherence.R — Production coherence: which realized_ym offset matches
# the top-20 EW reconstruction? (diagnostic)
# Established: Ret_1m @ score Date t covers calendar month(t)+1.
#              ret_orig @ realized_ym m covers calendar month m-1.
# If production holds month(t)+1 on score t (panel-consistent): match m = month(t)+2.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")

sc <- as.data.table(read_parquet(file.path(PROD_DIR, "02_holdings_universe/alpha_scores_str1715_268m.parquet")))
sc[, Date := as.Date(Date)]
pr <- fread(file.path(PROD_DIR, "04_backtest_results/period_returns_layer5.csv"))

top20 <- sc[!is.na(score_eff) & !is.na(Ret_1m), .SD[order(-score_eff)][1:20], by = Date]
ew <- top20[, .(ew_ret = mean(Ret_1m)), by = Date][order(Date)]

ym_shift <- function(d, k) format(seq(as.Date(d), by = paste(k, "month"), length.out = 2)[2], "%Y-%m")
for (k in 0:3) {
  ew[, ym_match := sapply(as.character(Date), ym_shift, k = k)]
  mm <- merge(ew[, .(ym = ym_match, ew_ret)], pr[, .(ym = realized_ym, ret_orig)], by = "ym")
  cat(sprintf("match realized_ym = month(t)+%d: pearson=%.4f spearman=%.4f (n=%d)\n", k,
              mm[, cor(ew_ret, ret_orig, use="complete.obs")],
              mm[, cor(ew_ret, ret_orig, method="spearman", use="complete.obs")], nrow(mm)))
}
cat("[b0e] DONE\n")
