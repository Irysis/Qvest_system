# Diagnostic: return-stream overlap vs confirmed adoption candidate (SUE+EPS revision, run 20260612_161342_1312338)
suppressMessages({library(xts); library(PerformanceAnalytics); library(data.table)})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/alpha_search"

b1 <- readRDS(file.path(root, "20260612_130540_180351/bt_result.rds"))
p2 <- fread(file.path(root, "20260612_161342_1312338/03_period_returns.csv"))
m2bm <- fread(file.path(root, "20260612_161342_1312338/05_benchmark_returns.csv"))

s1 <- xts(b1$period_returns$ret_net, order.by = b1$period_returns$date)
bm1 <- xts(b1$benchmark_returns$benchmark_ret, order.by = b1$benchmark_returns$date)
s2 <- xts(p2$ret_net, order.by = as.Date(p2$date))
bm2 <- xts(m2bm$benchmark_ret, order.by = as.Date(m2bm$date))

s1m <- apply.monthly(s1, Return.cumulative); bm1m <- apply.monthly(bm1, Return.cumulative)
s2m <- apply.monthly(s2, Return.cumulative); bm2m <- apply.monthly(bm2, Return.cumulative)

x <- na.omit(merge(s1m, s2m, s1m - bm1m, s2m - bm2m))
colnames(x) <- c("s1", "s2", "a1", "a2")
rep_cor <- function(sub, label) {
  cat(sprintf("%-9s n=%3d | raw cor %.3f | active cor %.3f\n",
      label, nrow(sub), cor(sub$s1, sub$s2), cor(sub$a1, sub$a2)))
}
rep_cor(x, "FULL")
rep_cor(x["2017-01/"], "POST-2017")
rep_cor(tail(x, 36), "LAST36")
