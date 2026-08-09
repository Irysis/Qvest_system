## 샤드5 집계 + 요구조건(필요 슬리브 IR) 해석해 계산
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/pg2_hunt")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")
inc <- bm_load_incumbent()
A <- readRDS(file.path(OUT,"factor_long.rds")); M <- readRDS(file.path(OUT,"mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
BEN <- as.data.table(M$bench); LIQ <- as.data.table(M$liq); SZ <- as.data.table(M$size_dt)
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]
R <- fread(file.path(OUT,"shard5_results.csv"))

## 필요 슬리브 IR (해석해): 관측 σ_s, ρ 고정하고 μ_s 를 풀어 ΔIR=0.05 달성점
req_ir <- function(mu_i, sd_i, mu_s, sd_s, rho, w) {
  ir_i <- sqrt(12)*mu_i/sd_i
  D <- sqrt((1-w)^2*sd_i^2 + w^2*sd_s^2 + 2*w*(1-w)*rho*sd_i*sd_s)
  mu_need <- (((ir_i + 0.05)/sqrt(12))*D - (1-w)*mu_i)/w
  sqrt(12)*mu_need/sd_s
}

## 각 팩터 arm 별 모멘트 재추출
rows <- list()
for (j in seq_len(nrow(R))) {
  f <- R$factor[j]
  S <- A[Factor_Name==f, .(Date,Ticker,score=z)]
  r <- suppressWarnings(canonical_screen_bt(S, ret, BEN, top_n=25L, cost_bps_oneway=15,
        liq_dt=LIQ, liq_min=2e8, run_id=f, strategy_id=f, diag_dual_basis=FALSE, size_dt=SZ))
  PR <- as.data.table(r$period_returns)
  mk <- function(sl, w) {
    S2 <- data.table(date=as.Date(sl$date), s=as.numeric(sl$ret_net))
    S2[, m := .bm_mi(date) + 2L]
    B2 <- copy(inc)[, m := .bm_mi(date)]
    X <- merge(B2, S2[, .(m,s)], by="m")
    if (nrow(X) < 60) return(NULL)
    as_ <- X$s - X$benchmark_ret
    data.table(n=nrow(X), rho=cor(as_, X$active),
      ir_s=sqrt(12)*mean(as_)/sd(as_), ir_i=sqrt(12)*mean(X$active)/sd(X$active),
      req=req_ir(mean(X$active), sd(X$active), mean(as_), sd(as_), cor(as_,X$active), w))
  }
  wu <- if (is.finite(R$bw_u[j])) R$bw_u[j] else 0.20
  wp <- if (is.finite(R$bw_p[j])) R$bw_p[j] else 0.20
  u <- mk(PR[, .(date, ret_net)], wu)
  X <- merge(PR[,.(date,ret_net,benchmark_ret)], Mru[,.(date,regime)], by="date")[order(date)]
  p <- NULL
  if (nrow(X) >= 60) { X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
    p <- mk(X[, .(date, ret_net=r2)], wp) }
  rows[[length(rows)+1L]] <- data.table(factor=f,
    req_u = if(is.null(u)) NA_real_ else u$req, req_p = if(is.null(p)) NA_real_ else p$req)
}
Q <- rbindlist(rows)
R <- merge(R, Q, by="factor", sort=FALSE)
R[, def_u := req_u - ir_u][, def_p := req_p - ir_p]
fwrite(R, file.path(OUT,"shard5_results_full.csv"))

q <- function(x) sprintf("중앙 %.4f [%.4f, %.4f] 최대 %.4f", median(x,na.rm=TRUE),
      quantile(x,.25,na.rm=TRUE), quantile(x,.75,na.rm=TRUE), max(x,na.rm=TRUE))
cat("\n=== ARM1 무조건부 (전기간) ===\n")
cat("n_u:", q(R$n_u), "\ncor:", q(R$cor_u), "\nir :", q(R$ir_u), "\nbest dIR:", q(R$bd_u),
    "\n양수 bestdIR:", sum(R$bd_u>0, na.rm=TRUE), "/", sum(is.finite(R$bd_u)),
    "\n>=0.05:", sum(R$bd_u>=0.05, na.rm=TRUE), "\ncor<0.2:", sum(R$cor_u<0.2,na.rm=TRUE),
    "\nir>0.5:", sum(R$ir_u>0.5,na.rm=TRUE), "\n부족분:", q(R$def_u), "\n")
cat("\n=== ARM2 파킹 (73개월) ===\n")
cat("n_p:", q(R$n_p), "\ncor:", q(R$cor_p), "\nir :", q(R$ir_p), "\nbest dIR:", q(R$bd_p),
    "\n양수 bestdIR:", sum(R$bd_p>0, na.rm=TRUE), "/", sum(is.finite(R$bd_p)),
    "\n>=0.05:", sum(R$bd_p>=0.05, na.rm=TRUE), "\ncor<0.2:", sum(R$cor_p<0.2,na.rm=TRUE),
    "\nir>0.5:", sum(R$ir_p>0.5,na.rm=TRUE), "\n부족분:", q(R$def_p), "\n")
V <- R[is.finite(bd_u) & is.finite(bd_p)]
cat("\npaired(같은팩터, 창 다름 — 참고용) cor 인하:", sprintf("%.4f -> %.4f (t %.3f, %d/%d 감소)",
    median(V$cor_u), median(V$cor_p), t.test(V$cor_p, V$cor_u, paired=TRUE)$statistic,
    sum(V$cor_p<V$cor_u), nrow(V)), "\n")
cat("ΔIR 개선건수:", sum(V$bd_p>V$bd_u), "/", nrow(V), "\n")
cat("\n=== best_arm 별 ===\n")
R[, best_arm := ifelse(!is.finite(bd_p) | (is.finite(bd_u) & bd_u>=bd_p), "uncond","parked")]
R[, best_d := pmax(bd_u, bd_p, na.rm=TRUE)]
R[, best_w := ifelse(best_arm=="uncond", bw_u, bw_p)]
print(R[order(-best_d), .(factor,best_arm,best_d,best_w,cor_u,ir_u,cor_p,ir_p,
   def=pmin(def_u,def_p,na.rm=TRUE))][1:8])
fwrite(R, file.path(OUT,"shard5_results_full.csv"))
cat("\nport_t:", q(R$port_t), "· 유한", sum(is.finite(R$port_t)), "\n")
