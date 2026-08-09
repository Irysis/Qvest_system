suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

OUT  <- "stage_artifacts/pg2_hunt/s2_results.csv"
ERRF <- "stage_artifacts/pg2_hunt/s2_errors.csv"

A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds")
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
bench <- as.data.table(M$bench); liq <- as.data.table(M$liq); sz <- as.data.table(M$size_dt)
inc <- bm_load_incumbent()
Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01"), .(date, regime)]
cat("[input] factor_long rows", nrow(A), "months", uniqueN(A$Date), "factors", uniqueN(A$Factor_Name), "\n")
cat("[input] rule months", nrow(Mru), "ON", sum(Mru$regime), "incumbent months", nrow(inc), "\n")

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 2]
cat("[shard] n =", length(mine), "\n")

done <- character(0)
if (file.exists(OUT)) { d0 <- fread(OUT); done <- unique(d0$factor); cat("[resume] already done", length(done), "\n") }

WTS <- c(0.05, 0.10, 0.15, 0.20, 0.30)

row_from_sweep <- function(sw, prefix) {
  ok <- sw[is.finite(delta_ir)]
  if (nrow(ok) == 0) return(setNames(as.list(rep(NA_real_, 5)),
      paste0(prefix, c("_best_d", "_best_w", "_n", "_cor", "_allw"))))
  i <- which.max(ok$delta_ir)
  list(best_d = ok$delta_ir[i], best_w = ok$weight[i], n = ok$n[i],
       cor = ok$cor_inc[i], allw = as.integer(all(ok$delta_ir >= 0.05)))
}

errs <- list()
for (k in seq_along(mine)) {
  f <- mine[k]
  if (f %in% done) next
  res <- try({
    S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
    n_obs <- nrow(S); n_mo <- uniqueN(S$Date)
    r <- suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = 25L,
          cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8,
          run_id = f, strategy_id = f, diag_dual_basis = FALSE, size_dt = sz))
    PR <- as.data.table(r$period_returns)
    stopifnot(all(c("date","ret_net","benchmark_ret") %in% names(PR)))
    ## arm1 무조건부 — 전 기간
    sw1 <- bm_delta_ir_sweep(PR[, .(date, ret_net)], weights = WTS)
    d1  <- bm_delta_ir(PR[, .(date, ret_net)], weight = 0.20, incumbent = inc)
    ## arm2 파킹 — 국면 라벨 창(73개월)
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru, by = "date")
    n_park_merge <- nrow(X)
    setorder(X, date)
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw * 15/1e4]
    sw2 <- bm_delta_ir_sweep(X[, .(date, ret_net = r2)], weights = WTS)
    d2  <- bm_delta_ir(X[, .(date, ret_net = r2)], weight = 0.20, incumbent = inc)
    a1 <- row_from_sweep(sw1, "u"); a2 <- row_from_sweep(sw2, "p")
    data.table(
      factor = f, n_obs = n_obs, n_months_panel = n_mo,
      n_pr = nrow(PR), pr_start = as.character(min(PR$date)), pr_end = as.character(max(PR$date)),
      n_park_merge = n_park_merge,
      u_status = d1$status, u_n = d1$n_overlap, u_win_start = d1$window[1], u_win_end = d1$window[2],
      u_cor = d1$correlation_with_incumbent, u_sleeve_ir = d1$sleeve_standalone_ir,
      u_dir_w20 = d1$delta_ir, u_best_d = a1$best_d, u_best_w = a1$best_w, u_allw = a1$allw,
      p_status = d2$status, p_n = d2$n_overlap, p_win_start = d2$window[1], p_win_end = d2$window[2],
      p_cor = d2$correlation_with_incumbent, p_sleeve_ir = d2$sleeve_standalone_ir,
      p_dir_w20 = d2$delta_ir, p_best_d = a2$best_d, p_best_w = a2$best_w, p_allw = a2$allw
    )
  }, silent = TRUE)
  if (inherits(res, "try-error")) {
    cat("[ERROR]", f, ":", conditionMessage(attr(res, "condition")), "\n")
    errs[[length(errs)+1]] <- data.table(factor = f, reason = conditionMessage(attr(res, "condition")))
    next
  }
  fwrite(res, OUT, append = file.exists(OUT))
  if (k %% 5 == 0 || k == 1) cat(sprintf("[progress] %d/%d %s u_best=%.4f p_best=%.4f\n",
      k, length(mine), f, res$u_best_d, res$p_best_d))
}
if (length(errs)) fwrite(rbindlist(errs), ERRF)
cat("[done] rows in OUT:", if (file.exists(OUT)) nrow(fread(OUT)) else 0, " errors:", length(errs), "\n")
