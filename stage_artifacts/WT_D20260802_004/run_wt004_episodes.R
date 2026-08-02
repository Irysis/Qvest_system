# run_wt004_episodes.R — 에피소드 분해 추출 (판정 서사용)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
R <- readRDS(file.path(OUT, "wt004_eval_results.rds"))
for (tag in c("D03_RealVol_def","D55_Vol_Trend_def","D41_Vol_of_Vol_def",
              "C_ORTH_def","C_ALL5_def","CORE_M01","D03_RealVol_can")) {
  ep <- R$cond[[tag]]$crisis_episodes
  cat("==", tag, "\n")
  if (!is.null(ep)) print(ep[, .(ep, months, first, last,
      cum_active = round(100*cum_active,1), cum_net = round(100*cum_net,1),
      cum_bm = round(100*cum_bm,1))])
}
# post-2017 / subperiod 참고 (def combo)
pr <- R$pr[["C_ORTH_def"]]
pr[, active := ret_net - benchmark_ret]
cat("\nC_ORTH_def subperiod mean active (%/월):\n")
print(pr[, .(mean_active = round(100*mean(active),2), n = .N),
        by = .(sub = fifelse(hold_ym < "2012-01", "2005-2011",
                     fifelse(hold_ym < "2019-01", "2012-2018", "2019-2026")))])
