# probe_deepdown.R — WT-017 보강: 깊은 하락월(BM<-5%) 라벨 recall + CRISIS 라벨월 연대 분해
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
res <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260802_017/wt017_results.rds"))
per <- res$per
bt_book <- res$bt$BOOK$period_returns
lr <- merge(per[, .(Date = eval_date, Category, g)], bt_book[, .(Date = date, bm = benchmark_ret)], by = "Date")
lr[, lab_risk := Category %in% c("CRISIS", "CAUTION")]
for (thr in c(0, -0.05, -0.08)) {
  dn <- lr[bm < thr]
  cat(sprintf("BM<%.0f%%: n=%d, 라벨발화 recall=%.2f (발화 %d/%d), fisher_p=%.3f\n",
      thr * 100, nrow(dn), dn[, mean(lab_risk)], dn[, sum(lab_risk)], nrow(dn),
      tryCatch(fisher.test(table(lr$lab_risk, lr$bm < thr))$p.value, error = function(e) NA_real_)))
}
cat("\nCRISIS 라벨월(m-1) 연대:\n")
print(lr[Category == "CRISIS", .(Date, bm = round(bm, 3))])
