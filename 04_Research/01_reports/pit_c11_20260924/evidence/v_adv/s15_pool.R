suppressMessages({library(data.table)})
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/rf_factor_arms.R")
P <- rf_factor_pool("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
pool <- P$pool
cat("pool size:", nrow(pool), "\n")
print(pool[id %in% c("D32_Beta_VIX","MA01_GDP_Sensitivity","MA02_CPI_Sensitivity","MA03_Rate_Sensitivity","MA04_YieldCurve_Sensitivity")])
cat("excluded_axis includes RE14/MA07:", c("RE14_Inflation_YoY","MA07_BusinessCycle_Composite") %in% P$excluded_axis, "\n")
