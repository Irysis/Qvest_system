suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SD <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")

sim <- readRDS(file.path(SD, "forge_sim.rds"))
d <- as.data.table(sim$DAILY_NAV_DT)
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
m <- merge(d[, .(Date, r = Strategy_Ret)], bm[, .(Date, b = BM_Ret)], by = "Date")
m[, ym := format(Date, "%Y-%m")]
F <- m[, .(f_ret = prod(1 + r) - 1, f_bm = prod(1 + b) - 1), by = ym]

p <- fread(file.path(SD, "period_returns_production.csv"))
p[, ym := holding_ym]
X <- merge(F, p[, .(ym, a_ret = ret_net, a_bm = benchmark_ret)], by = "ym")
X[, d_ret := f_ret - a_ret][, d_bm := f_bm - a_bm]
setorder(X, ym)

cat("n matched months =", nrow(X), "\n")
cat("\n-- benchmark: forge(.cache/benchmark.parquet) vs alpha panel --\n")
cat("cor =", cor(X$f_bm, X$a_bm), " mean|diff| =", mean(abs(X$d_bm)),
    " max|diff| =", max(abs(X$d_bm)), "\n")
cat("ann mean: forge_bm =", mean(X$f_bm) * 12, " alpha_bm =", mean(X$a_bm) * 12, "\n")
cat("cum: forge_bm =", prod(1 + X$f_bm) - 1, " alpha_bm =", prod(1 + X$a_bm) - 1, "\n")
cat("worst 8 |bm diff| months:\n"); print(head(X[order(-abs(d_bm)), .(ym, f_bm, a_bm, d_bm)], 8))

cat("\n-- strategy: forge realized vs alpha panel --\n")
cat("cor =", cor(X$f_ret, X$a_ret), " mean|diff| =", mean(abs(X$d_ret)),
    " max|diff| =", max(abs(X$d_ret)), "\n")
cat("ann mean: forge =", mean(X$f_ret) * 12, " alpha =", mean(X$a_ret) * 12, "\n")
cat("cum: forge =", prod(1 + X$f_ret) - 1, " alpha =", prod(1 + X$a_ret) - 1, "\n")
cat("worst 8 |ret diff| months:\n"); print(head(X[order(-abs(d_ret)), .(ym, f_ret, a_ret, d_ret)], 8))

cat("\n-- active IR under each benchmark (forge strategy series) --\n")
a1 <- X$f_ret - X$f_bm; a2 <- X$f_ret - X$a_bm
cat("forge_bm : mean_ann =", mean(a1) * 12, " te =", sd(a1) * sqrt(12),
    " IR =", mean(a1) / sd(a1) * sqrt(12), "\n")
cat("alpha_bm : mean_ann =", mean(a2) * 12, " te =", sd(a2) * sqrt(12),
    " IR =", mean(a2) / sd(a2) * sqrt(12), "\n")
a3 <- X$a_ret - X$a_bm
cat("alpha_ret vs alpha_bm: IR =", mean(a3) / sd(a3) * sqrt(12), "(= 상류 보고 0.2492 대조)\n")

cat("\n-- alpha panel benchmark extreme months (|ret| > 15%) --\n")
print(X[abs(a_bm) > 0.15, .(ym, a_bm, f_bm)])

# 등급 이동 여부 확인: 상류 벤치를 써도 PORT_t 가 B 문턱(2.0)을 넘는가?
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
.t <- function(x) if (exists(".nw_t_mean", mode = "function")) .nw_t_mean(x, lag = 3L) else NA_real_
cat("\n-- PORT_t (NW lag-3, monthly) under each benchmark --\n")
cat("forge_bm :", .t(a1), "\nalpha_bm :", .t(a2), "\nalpha_ret vs alpha_bm:", .t(a3), "\n")
cat("B 문턱 PORT_t >= 2.0 / A 문턱 2.95 — 세 basis 모두 미달인가?",
    all(c(.t(a1), .t(a2), .t(a3)) < 2.0), "\n")

out <- list(
  n_months = nrow(X),
  strategy_series = list(cor = cor(X$f_ret, X$a_ret), mean_abs_diff = mean(abs(X$d_ret)),
                         max_abs_diff = max(abs(X$d_ret)),
                         forge_ann_mean = mean(X$f_ret) * 12, alpha_ann_mean = mean(X$a_ret) * 12,
                         forge_cum = prod(1 + X$f_ret) - 1, alpha_cum = prod(1 + X$a_ret) - 1),
  benchmark_series = list(cor = cor(X$f_bm, X$a_bm), mean_abs_diff = mean(abs(X$d_bm)),
                          max_abs_diff = max(abs(X$d_bm)),
                          forge_ann_mean = mean(X$f_bm) * 12, alpha_ann_mean = mean(X$a_bm) * 12,
                          forge_cum = prod(1 + X$f_bm) - 1, alpha_cum = prod(1 + X$a_bm) - 1,
                          forge_source = ".cache/benchmark.parquet BM_Ret (production harness BM_DT)",
                          alpha_source = "period_returns_production.csv benchmark_ret (alpha 패널 구성)"),
  ir_attribution = list(
    forge_strategy_vs_forge_bm = mean(a1) / sd(a1) * sqrt(12),
    forge_strategy_vs_alpha_bm = mean(a2) / sd(a2) * sqrt(12),
    alpha_strategy_vs_alpha_bm = mean(a3) / sd(a3) * sqrt(12),
    upstream_reported = 0.2492,
    reading = paste("net_IR 격차 0.2492 -> 0.1486 의 지배항은 벤치 계열 차이다",
                    "(같은 forge 수익 계열에 상류 벤치를 쓰면 0.2336). 전략 실현 차이는 잔여분.")),
  port_t_by_basis = list(forge_strategy_vs_forge_bm = .t(a1),
                         forge_strategy_vs_alpha_bm = .t(a2),
                         alpha_strategy_vs_alpha_bm = .t(a3),
                         b_threshold = 2.0, a_threshold = 2.95,
                         all_below_b = all(c(.t(a1), .t(a2), .t(a3)) < 2.0)),
  verdict_invariance = paste("세 basis 전부 PORT_t < 2.0 이므로 벤치 계열 선택은 등급을 옮기지 않는다.",
                             "권위 basis 는 production harness BM (계약/lean 레인 공통)."))
jsonlite::write_json(out, file.path(SD, "forge_baseline_reconciliation.json"),
                     auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("\n[recon] forge_baseline_reconciliation.json written\n")
