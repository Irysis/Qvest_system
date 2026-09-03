setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages(library(data.table))
d <- "04_Research/strategies/RF_B2_8_InvVol"
tr <- readRDS(Sys.glob(file.path(d,"stage","*","bt_result.rds")))
ct <- readRDS(Sys.glob(file.path(d,"stage_ctrl","*","bt_result.rds")))
for (nm in c("TREAT","CTRL")) {
  b <- if (nm=="TREAT") tr else ct
  a <- as.data.table(b$audit)
  cat("==",nm,"| audit:", paste(sprintf("%s=%s", a$check_name, a$status)[a$status!="PASS"], collapse=" | "), "\n")
  m <- b$metrics
  cat("   turnover_annual =", m$turnover_annual %||% m$turnover %||% NA,
      "| n_max =", b$strategy_spec$n_max, "| has_short =", b$strategy_spec$has_short, "\n")
}
wd <- readRDS(file.path(d,"invvol_diag.rds"))
cat("\n-- weight dist quantiles (across 262 rebalances) --\n")
print(round(quantile(wd$w_max, c(0,.5,.9,1)),4))
print(round(quantile(wd$eff_n, c(0,.5,1)),2))
cat("w_max/w_min ratio median:", round(median(wd$w_max/wd$w_min),2), "\n")
cat("sigma NA total:", sum(wd$n_sigma_na), "| sigma==0 total:", sum(wd$n_sigma_zero), "| held always 25:", all(wd$n_held==25), "\n")
