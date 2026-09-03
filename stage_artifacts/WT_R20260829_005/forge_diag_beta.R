suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
sim <- readRDS(file.path(ROOT, "stage_artifacts/WT_R20260829_005/forge_sim.rds"))
d  <- as.data.table(sim$DAILY_NAV_DT)
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
m  <- merge(d[, .(Date, r = Strategy_Ret)], bm[, .(Date, b = BM_Ret)], by = "Date")
cat("n =", nrow(m), " cor_daily =", cor(m$r, m$b), "\n")
cat("sd_r =", sd(m$r), " sd_b =", sd(m$b), "\n")
m[, ym := format(Date, "%Y-%m")]
mm <- m[, .(rs = prod(1 + r) - 1, rb = prod(1 + b) - 1), by = ym]
cat("cor_monthly =", cor(mm$rs, mm$rb), " n_m =", nrow(mm), "\n")
n <- nrow(m)
cat("cor(r_t, b_t-1) =", cor(m$r[-1], m$b[-n]), "  cor(r_t, b_t+1) =", cor(m$r[-n], m$b[-1]), "\n")
cat("\ntop 10 |r| days:\n"); print(head(m[order(-abs(r))], 10))
cat("\nNAV head/tail:\n"); print(head(d, 5)); print(tail(d, 5))
cat("\nreturn quantiles r:\n"); print(quantile(m$r, c(0, .001, .01, .5, .99, .999, 1)))
cat("cor by year:\n")
m[, y := as.integer(format(Date, "%Y"))]
print(m[, .(n = .N, cor = cor(r, b), sd_r = sd(r)), by = y])
