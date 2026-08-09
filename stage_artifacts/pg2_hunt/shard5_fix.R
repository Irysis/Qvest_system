## port_t 추출 진단 + w=0.20 고정 요구조건 재계산
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
R <- fread(file.path(OUT,"shard5_results_full.csv"))

r1 <- suppressWarnings(canonical_screen_bt(A[Factor_Name==R$factor[1], .(Date,Ticker,score=z)],
      ret, BEN, top_n=25L, cost_bps_oneway=15, liq_dt=LIQ, liq_min=2e8,
      run_id="d", strategy_id="d", diag_dual_basis=FALSE, size_dt=SZ))
cat("=== benchmark_compare 구조 ===\n"); print(str(r1$benchmark_compare, max.level=1))
bc <- as.data.table(r1$benchmark_compare); print(names(bc)); print(head(bc, 20))

req_ir <- function(mu_i, sd_i, sd_s, rho, w) {
  ir_i <- sqrt(12)*mu_i/sd_i
  D <- sqrt((1-w)^2*sd_i^2 + w^2*sd_s^2 + 2*w*(1-w)*rho*sd_i*sd_s)
  sqrt(12)*((((ir_i+0.05)/sqrt(12))*D - (1-w)*mu_i)/w)/sd_s
}
rows <- list()
for (j in seq_len(nrow(R))) {
  f <- R$factor[j]
  r <- suppressWarnings(canonical_screen_bt(A[Factor_Name==f,.(Date,Ticker,score=z)], ret, BEN,
        top_n=25L, cost_bps_oneway=15, liq_dt=LIQ, liq_min=2e8, run_id=f, strategy_id=f,
        diag_dual_basis=FALSE, size_dt=SZ))
  PR <- as.data.table(r$period_returns)
  pt <- NA_real_
  b <- tryCatch(as.data.table(r$benchmark_compare), error=function(e) NULL)
  if (!is.null(b)) {
    kc <- names(b)[vapply(b, is.character, logical(1))]
    for (k in kc) { h <- grep("Portfolio_Alpha_t_NW", b[[k]])
      if (length(h)) { nc <- names(b)[vapply(b, is.numeric, logical(1))]
        if (length(nc)) pt <- as.numeric(b[[nc[1]]][h[1]]); break } }
  }
  mk <- function(sl) {
    S2 <- data.table(date=as.Date(sl$date), s=as.numeric(sl$ret_net))[, m := .bm_mi(date)+2L]
    X <- merge(copy(inc)[, m := .bm_mi(date)], S2[,.(m,s)], by="m")
    if (nrow(X) < 60) return(NULL)
    a <- X$s - X$benchmark_ret
    list(req20 = req_ir(mean(X$active), sd(X$active), sd(a), cor(a,X$active), 0.20),
         ir = sqrt(12)*mean(a)/sd(a))
  }
  u <- mk(PR[,.(date,ret_net)])
  X <- merge(PR[,.(date,ret_net,benchmark_ret)], Mru[,.(date,regime)], by="date")[order(date)]
  p <- NULL
  if (nrow(X)>=60) { X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]; p <- mk(X[,.(date,ret_net=r2)]) }
  rows[[length(rows)+1L]] <- data.table(factor=f, port_t2=pt,
    req20_u = if(is.null(u)) NA_real_ else u$req20,
    req20_p = if(is.null(p)) NA_real_ else p$req20)
}
Q <- rbindlist(rows)
R[, port_t := NULL]; R <- merge(R, Q, by="factor", sort=FALSE)
setnames(R, "port_t2", "port_t")
R[, def20_u := req20_u - ir_u][, def20_p := req20_p - ir_p]
fwrite(R, file.path(OUT,"shard5_results_full.csv"))
q <- function(x) sprintf("중앙 %.4f [%.4f, %.4f]", median(x,na.rm=TRUE), quantile(x,.25,na.rm=TRUE), quantile(x,.75,na.rm=TRUE))
cat("\nport_t 유한:", sum(is.finite(R$port_t)), "/", nrow(R), "·", q(R$port_t), "· max", max(R$port_t,na.rm=TRUE), "\n")
cat("req20_u:", q(R$req20_u), " def20_u:", q(R$def20_u), "\n")
cat("req20_p:", q(R$req20_p), " def20_p:", q(R$def20_p), "\n")
cat("\n=== top5 closest (def20 최소) ===\n")
R[, def20 := pmin(def20_u, def20_p, na.rm=TRUE)]
print(R[order(def20)][1:6, .(factor, cor_u, ir_u, req20_u, cor_p, ir_p, req20_p, def20, best_arm, best_d)])
