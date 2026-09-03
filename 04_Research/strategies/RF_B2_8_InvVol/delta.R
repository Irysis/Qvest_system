setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages(library(jsonlite))
d <- "04_Research/strategies/RF_B2_8_InvVol"
t <- fromJSON(Sys.glob(file.path(d,"stage","*","authoritative_remeasure.json")))
c <- fromJSON(Sys.glob(file.path(d,"stage_ctrl","*","authoritative_remeasure.json")))
f <- function(x) c(grade=x$essence_grade, PORT_t=x$essence$portfolio_alpha_t_nw_lag3,
  SR=x$essence$net_sharpe, IR=x$essence$net_ir, CAGR=x$essence$cagr, MDD=x$essence$mdd,
  Calmar=x$essence$calmar, OOS=x$essence$oos_retention,
  struct_dd=x$structural_drawdown, sev55=x$essence$drawdown_profile$severe55_count,
  sev45=x$essence$drawdown_profile$severe45_count)
print(data.frame(CTRL_EW=f(c), TREAT_InvVol=f(t)))
