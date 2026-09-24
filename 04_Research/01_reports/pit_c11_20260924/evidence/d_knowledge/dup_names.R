suppressPackageStartupMessages(library(data.table))
dt <- data.table(Date=1:4, VIX_z_smooth=c(10,20,30,40), HY_Spread_z_smooth=c(1,2,3,4))
dt[, VIX_z_smooth_lag := shift(VIX_z_smooth, 1L)]
dt[, HY_Spread_z_smooth_lag := shift(HY_Spread_z_smooth, 1L)]
setnames(dt, c("VIX_z_smooth_lag","HY_Spread_z_smooth_lag"), c("VIX_z_smooth","HY_z_smooth"), skip_absent=TRUE)
print(names(dt))
out <- c("Date","VIX_z_smooth","HY_z_smooth")
r <- dt[, ..out]
print(r)
cat("data.table", as.character(packageVersion("data.table")), "\n")
