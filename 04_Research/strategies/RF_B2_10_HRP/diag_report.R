suppressPackageStartupMessages(library(data.table))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
d <- readRDS("04_Research/strategies/RF_B2_10_HRP/hrp_diag.rds")
cat(sprintf("months=%d\n", nrow(d)))
cat(sprintf("n_cluster: mean %.2f | median %d | range %d-%d\n",
            mean(d$n_cluster), as.integer(median(d$n_cluster)),
            min(d$n_cluster), max(d$n_cluster)))
cat(sprintf("max_cluster: mean %.2f | median %d | max %d\n",
            mean(d$max_cluster), as.integer(median(d$max_cluster)), max(d$max_cluster)))
cat(sprintf("eff_n(1/sum w^2): mean %.2f | median %.2f | min %.2f | max %.2f  (EW=25)\n",
            mean(d$eff_n), median(d$eff_n), min(d$eff_n), max(d$eff_n)))
cat(sprintf("w_max: mean %.4f | median %.4f | max %.4f   (EW=0.04)\n",
            mean(d$w_max), median(d$w_max), max(d$w_max)))
cat(sprintf("w_min: mean %.5f | median %.5f | min %.5f\n",
            mean(d$w_min), median(d$w_min), min(d$w_min)))
cat(sprintf("top5 share: mean %.3f | median %.3f   (EW=0.20)\n",
            mean(d$w_top5), median(d$w_top5)))
cat(sprintf("n_sel: median %d | min %d | months<25 = %d\n",
            as.integer(median(d$n_sel)), min(d$n_sel), sum(d$n_sel < 25)))
cat(sprintf("hist_drop(<24M obs excluded from candidate pool): mean %.2f | median %.1f | max %d\n",
            mean(d$n_hist_drop), median(d$n_hist_drop), max(d$n_hist_drop)))
cat(sprintf("window obs per name: median %.0f | min %.0f\n",
            median(d$obs_med), min(d$obs_med)))

# turnover 비교 (B2-10 vs B1-5) — 계약 산출 CSV 만 인용
for (p in c("04_Research/strategies/RF_B2_10_HRP/stage/20260829_233456_7952",
            "04_Research/strategies/RF_B1_5_MomIlliq/stage/20260829_230711_27764")) {
  m <- fread(file.path(p, "06_metrics.csv"))
  cat("\n==", p, "==\n")
  print(m[grepl("turnover|Turnover|sharpe|Sharpe|cagr|CAGR|mdd|MDD|calmar|Calmar|ir|IR|alpha|beta",
                m[[1]]), ][1:40])
}
