## 통과 부족분 — 팩터별 실측 sd·rho 고정, mu_s 를 풀어 필요 슬리브 IR 산출
suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds"); setDT(A)
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
bench <- as.data.table(M$bench); liq <- as.data.table(M$liq); sz <- as.data.table(M$size_dt)
inc <- bm_load_incumbent()
Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")[, date := as.Date(date)][date < as.Date("2026-01-01")]
R <- fread("stage_artifacts/pg2_hunt/shard7_results.csv")

## 후보: best_dIR 상위 6건
cand <- R[order(-best_dIR)][1:6]
mi <- function(d) { d <- as.Date(d); 12L*as.integer(format(d,"%Y")) + as.integer(format(d,"%m")) }

req_ir <- function(a_i, a_s, w = 0.20, thr = 0.05, ppy = 12) {
  mu_i <- mean(a_i); s_i <- sd(a_i); s_s <- sd(a_s); rho <- cor(a_i, a_s)
  ir_i <- mu_i/s_i*sqrt(ppy)
  target <- ir_i + thr
  sd_b <- sqrt((1-w)^2*s_i^2 + w^2*s_s^2 + 2*w*(1-w)*rho*s_i*s_s)
  mu_needed_book <- target*sd_b/sqrt(ppy)
  mu_s_needed <- (mu_needed_book - (1-w)*mu_i)/w
  list(rho = rho, ir_i = ir_i, ir_s = mean(a_s)/s_s*sqrt(ppy),
       ir_s_needed = mu_s_needed/s_s*sqrt(ppy), sd_ratio = s_s/s_i)
}

out <- list()
for (i in seq_len(nrow(cand))) {
  f <- cand$factor[i]
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)][is.finite(score)]
  bt <- suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = 25L, cost_bps_oneway = 15,
        liq_dt = liq, liq_min = 2e8, run_id = f, strategy_id = f,
        diag_dual_basis = FALSE, size_dt = sz))
  PR <- as.data.table(bt$period_returns)[is.finite(ret_net)]
  arm <- cand$best_arm[i]
  if (arm == "parked") {
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime = as.logical(regime))], by="date")
    setorder(X, date); X[, sw_ := c(0L, abs(diff(as.integer(regime))))]
    X[, r := ifelse(regime, ret_net, benchmark_ret) - sw_*15/1e4]
    SL <- X[, .(date, ret_net = r, benchmark_ret)]
  } else SL <- PR[, .(date, ret_net, benchmark_ret)]
  SL[, m := mi(date) + 2L]
  B <- copy(inc)[, m := mi(date)]
  Z <- merge(B, SL[, .(m, s_ret = ret_net, s_bm = benchmark_ret)], by = "m")
  ## ★계약(bm_delta_ir) 정합: 슬리브 active 도 **incumbent 의 벤치**로 잰다
  a_s <- Z$s_ret - Z$benchmark_ret
  r1 <- req_ir(Z$active, a_s, w = 0.20)
  out[[i]] <- data.table(factor = f, arm = arm, n = nrow(Z),
    window = paste0(min(Z$date), "..", max(Z$date)),
    rho = r1$rho, sd_ratio = r1$sd_ratio, ir_inc_window = r1$ir_i,
    ir_sleeve = r1$ir_s, ir_needed = r1$ir_s_needed,
    shortfall = r1$ir_s_needed - r1$ir_s, best_dIR = cand$best_dIR[i])
  cat(i, f, "done\n"); flush.console()
}
O <- rbindlist(out)
fwrite(O, "stage_artifacts/pg2_hunt/shard7_shortfall.csv")
print(O)
