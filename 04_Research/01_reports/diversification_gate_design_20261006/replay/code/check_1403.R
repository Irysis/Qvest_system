suppressMessages({ library(data.table); library(jsonlite) })
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(RF_DIV_CFG = "C:/tmp/qvest_staging_1006_divgate/rf_diversification_gate.json")
source("C:/tmp/qvest_staging_1006_divgate/rf_diversification_gate.R")
cfg <- rfd_cfg(root)
bm <- rfd_bench_daily(root, cfg); fac <- rfd_factor_monthly(root, cfg)
a_path <- list.files(file.path(root, "stage_artifacts/replication/20260904_163647_18444"), pattern = "^remeasure_close_t1_", full.names = TRUE)[1]
A <- rfd_monthly(rfd_read_series(file.path(a_path, "03_period_returns.csv")), bm, fac)
B <- rfd_monthly(rfd_read_series(file.path(root, "04_Research/strategies/STR_AS_20260612_154914_1055315/sim_result.rds")), bm, fac)
M <- merge(A[, .(ym, e2a = e2, ea = e)], B[, .(ym, e2b = e2, eb = e)], by = "ym")
M <- M[is.finite(e2a) & is.finite(e2b)]
cat(sprintf("n=%d · Pearson resid2 %.3f · Spearman resid2 %.3f · Pearson resid %.3f\n", nrow(M),
            cor(M$e2a, M$e2b), cor(M$e2a, M$e2b, method = "spearman"), cor(M$ea, M$eb)))
pr <- abs(scale(M$e2a) * scale(M$e2b)); o <- order(-pr)
for (k in c(5, 10)) cat(sprintf("상위 %d개월(|곱|) 제외 Pearson %.3f\n", k, cor(M$e2a[-o[1:k]], M$e2b[-o[1:k]])))
cat("상위 기여 월:", paste(M$ym[o[1:6]], collapse = " "), "\n")
M[, yr := substr(ym, 1, 4)]
print(M[, .(n = .N, rho = round(cor(e2a, e2b), 3)), by = .(period = fifelse(yr < "2016", "2010-15", fifelse(yr < "2021", "2016-20", "2021-26")))])
C <- fromJSON(file.path(root, "06_Registry/module_catalog.json"), simplifyVector = FALSE)$modules[["STR_AS_20260612_154914_1055315"]]
cat("이웃 모듈:", C$meta$strategy_idea, "\n")
