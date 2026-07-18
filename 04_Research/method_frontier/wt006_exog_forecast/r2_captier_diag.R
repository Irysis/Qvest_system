# r2_captier_diag.R — captier_translate lane: locate the transition wall per family.
# Step 1 diagnostic: for each family, one-hot static theta (theta_f=1 over all OOS dates)
#   -> eval_theta gives cap-w port_t AND ew_uni_t. The gap = tier localization of that family's alpha.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")

fams <- c("value","quality","momentum","low_vol","size","dividend")
oos  <- get(".oos_dates", envir=globalenv())

# one-hot static per family
diag <- rbindlist(lapply(fams, function(f){
  th <- data.table(date=rep(oos, 1), family=f, theta=1.0)
  m  <- eval_theta(th, paste0("onehot_",f))
  data.table(family=f, port_t=m$port_t, ew_uni_t=m$ew_uni_t, net_sr=m$net_sr,
             oos_ret=m$oos_ret, turnover=m$turnover, lag1_port_t=m$lag1_port_t,
             paired_vs_mom_t=m$paired_vs_mom_t)
}))
diag[, gap_ew_minus_capw := ew_uni_t - port_t]
diag[, translatable := port_t]  # higher cap-w port_t = more translatable
setorder(diag, -port_t)
cat("\n===== PER-FAMILY ONE-HOT STATIC (OOS 163m) =====\n")
print(diag)

# momentum baseline theta average weights (which families momentum overweights)
mom <- get(".mom_theta", envir=globalenv())
mw  <- mom[date %in% oos, .(mean_theta=mean(theta)), by=family]
setorder(mw, -mean_theta)
cat("\n===== FACTOR-MOMENTUM baseline avg family weight =====\n")
print(mw)

# equal-weight static reference
ewq <- data.table(date=rep(oos, each=6), family=rep(fams, length(oos)), theta=1/6)
mew <- eval_theta(ewq, "static_EW")
cat(sprintf("\nstatic_EW: port_t=%.3f ew_uni_t=%.3f paired_vs_mom_t=%.3f net_sr=%.3f\n",
            mew$port_t, mew$ew_uni_t, mew$paired_vs_mom_t, mew$net_sr))

saveRDS(diag, "04_Research/method_frontier/wt006_exog_forecast/r2_captier_family_diag.rds")
fwrite(diag, "04_Research/method_frontier/wt006_exog_forecast/r2_captier_family_diag.csv")
cat("\n[diag] saved.\n")
