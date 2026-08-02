suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
r <- readRDS("stage_artifacts/WT_D20260802_006/wt006_eval_results.rds")
ct <- r$bt$SIG_LEVY_PV_63$diag_cap_tier
cat("cap_tier available:", ct$available, "\n")
cat("weight_share_avg:", toJSON(ct$weight_share_avg, auto_unbox=TRUE), "\n")
cat("contrib_gross_annualized:", toJSON(ct$contrib_gross_annualized, auto_unbox=TRUE), "\n")
ew <- r$bt$SIG_LEVY_PV_63$diag_ew_universe
cat("EW-uni: t=", ew$portfolio_alpha_t_nw_lag3, " oos_approx=", ew$oos_retention_approx,
    " post17_t=", ew$post2017_t_nw_lag3, " netSR=", ew$net_sr, " IR=", ew$information_ratio, "\n")
b <- r$bt$SIG_LEVY_PV_63
cat("primary: alpha_ann=", b$alpha_annualized, " IR=", b$information_ratio,
    " netSR=", b$net_sr, " TO=", b$turnover_annual, " mean_active=", b$mean_active_net, "\n")
# MEGA/MID 월별 시계열 상위 몇 개
print(head(ct$by_month[tier=="MEGA"][order(-weight_share)], 3))
cat("MEGA 평균 보유월 비율:", ct$by_month[tier=="MEGA", .N] / b$n_months, "\n")
