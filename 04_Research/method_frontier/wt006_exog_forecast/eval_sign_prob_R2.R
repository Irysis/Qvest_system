setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
library(arrow); library(data.table); library(jsonlite)
th <- as.data.table(read_parquet("04_Research/method_frontier/wt006_exog_forecast/theta_R2_sign_prob.parquet"))
m <- eval_theta(th, "sign_prob")
cat("\n==== sign_prob (direct prob-normalized theta) ====\n")
print(m)
writeLines(toJSON(m, auto_unbox=TRUE, digits=6),
           "04_Research/method_frontier/wt006_exog_forecast/eval_R2_sign_prob.json")
