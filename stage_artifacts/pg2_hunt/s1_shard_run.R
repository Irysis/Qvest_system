## Shard 1/8 — 2-arm book-marginal 전수 측정
suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds")
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
ret  <- as.data.table(M$ret)[!is.na(Ret_1m)]
bench<- as.data.table(M$bench); liq <- as.data.table(M$liq); sz <- as.data.table(M$size_dt)
inc  <- bm_load_incumbent()
Mru  <- fread("stage_artifacts/FQ191/p1_rule.csv")[, date := as.Date(date)][date < as.Date("2026-01-01")]

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 1]
cat("[input] factors_total:", length(FN), " shard:", length(mine),
    " panel_months:", uniqueN(A$Date), " rule_months:", nrow(Mru),
    " rule_ON:", sum(Mru$regime), "\n")

WS <- c(0.05, 0.10, 0.15, 0.20, 0.30)

## 요구조건: sleeve sd 고정, ΔIR>=0.05 달성에 필요한 sleeve mean → 필요 IR (닫힌형 수치해)
req_ir <- function(ai, ss, rho, w, ppy = 12) {
  mi <- mean(ai); si <- stats::sd(ai); iri <- mi/si*sqrt(ppy); tgt <- iri + 0.05
  f <- function(ms) {
    mb <- (1-w)*mi + w*ms
    vb <- (1-w)^2*si^2 + w^2*ss^2 + 2*w*(1-w)*rho*si*ss
    mb/sqrt(vb)*sqrt(ppy) - tgt
  }
  o <- try(stats::uniroot(f, c(-10*si, 10*si))$root, silent = TRUE)
  if (inherits(o, "try-error")) return(NA_real_)
  o/ss*sqrt(ppy)
}

arm_measure <- function(sl, tag) {
  sw <- try(bm_delta_ir_sweep(sl, weights = WS, require_overlap = 60L), silent = TRUE)
  if (inherits(sw, "try-error")) return(list(err = paste("sweep_error:", as.character(sw))))
  if (all(sw$status != "MEASURED")) return(list(err = paste0("status:", sw$status[1], " n=", sw$n[1])))
  o <- bm_delta_ir(sl, weight = 0.20, incumbent = inc, require_overlap = 60L)
  bi <- which.max(sw$delta_ir)
  ## 요구 IR: 각 w 에서 계산 후 최소값 (가장 관대한 w)
  S2 <- as.data.table(sl); setnames(S2, names(S2)[2], "sr")
  S2[, m := .bm_mi(as.Date(S2[[1]])) + o$align_offset]
  B2 <- copy(inc)[, m := .bm_mi(date)]
  X  <- merge(B2, S2[, .(m, sr)], by = "m")
  ss <- stats::sd(X$sr - X$benchmark_ret); rho <- o$correlation_with_incumbent
  rq <- suppressWarnings(min(sapply(WS, function(w) req_ir(X$active, ss, rho, w)), na.rm = TRUE))
  list(err = NA_character_, n = o$n_overlap, cor = rho, ir = o$sleeve_standalone_ir,
       best_dir = sw$delta_ir[bi], best_w = sw$weight[bi], all_beat = all(sw$beats),
       n_beat = sum(sw$beats), inc_ir = o$incumbent_ir_on_overlap, req_ir = rq,
       win = paste(o$window, collapse = "~"), sweep = paste(sprintf("%.4f", sw$delta_ir), collapse="|"))
}

out <- list(); errs <- list(); t0 <- Sys.time()
for (i in seq_along(mine)) {
  f <- mine[i]
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- try(suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8, run_id = f, strategy_id = f,
        diag_dual_basis = FALSE, size_dt = sz)), silent = TRUE)
  if (inherits(r, "try-error")) {
    errs[[length(errs)+1]] <- data.table(factor = f, stage = "canonical_screen_bt", msg = as.character(r)); next
  }
  PR <- as.data.table(r$period_returns)
  a1 <- arm_measure(PR[, .(date, ret_net)], "uncond")
  X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by = "date")
  if (nrow(X) < 60L) {
    errs[[length(errs)+1]] <- data.table(factor=f, stage="park_merge", msg=paste0("rows=",nrow(X)))
    a2 <- list(err = paste0("park_merge_rows_", nrow(X)))
  } else {
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
    a2 <- arm_measure(X[, .(date, ret_net = r2)], "parked")
  }
  if (!is.na(a1$err)) errs[[length(errs)+1]] <- data.table(factor=f, stage="arm1", msg=a1$err)
  if (!is.null(a2$err) && !is.na(a2$err)) errs[[length(errs)+1]] <- data.table(factor=f, stage="arm2", msg=a2$err)
  g <- function(a, k) if (is.null(a[[k]])) NA else a[[k]]
  out[[length(out)+1]] <- data.table(
    factor = f, port_t = r$portfolio_alpha_t_nw_lag3, screen_ir = r$information_ratio,
    n_u = g(a1,"n"), cor_u = g(a1,"cor"), ir_u = g(a1,"ir"), dir_u = g(a1,"best_dir"),
    w_u = g(a1,"best_w"), nbeat_u = g(a1,"n_beat"), req_u = g(a1,"req_ir"),
    win_u = g(a1,"win"), sweep_u = g(a1,"sweep"),
    n_p = g(a2,"n"), cor_p = g(a2,"cor"), ir_p = g(a2,"ir"), dir_p = g(a2,"best_dir"),
    w_p = g(a2,"best_w"), nbeat_p = g(a2,"n_beat"), req_p = g(a2,"req_ir"),
    win_p = g(a2,"win"), sweep_p = g(a2,"sweep"))
  if (i %% 5 == 0 || i == length(mine)) {
    fwrite(rbindlist(out, fill=TRUE), "stage_artifacts/pg2_hunt/s1_results.csv")
    cat(sprintf("[%d/%d] %s  elapsed %.1f min\n", i, length(mine), f,
        as.numeric(difftime(Sys.time(), t0, units="mins"))))
  }
}
R <- rbindlist(out, fill = TRUE)
fwrite(R, "stage_artifacts/pg2_hunt/s1_results.csv")
E <- if (length(errs)) rbindlist(errs, fill=TRUE) else data.table(factor=character())
fwrite(E, "stage_artifacts/pg2_hunt/s1_errors.csv")
cat("\n=== DONE measured:", nrow(R), " errors:", nrow(E), "\n")
q <- function(x) sprintf("med %.4f [%.4f, %.4f] min %.4f max %.4f",
     median(x,na.rm=T), quantile(x,.25,na.rm=T), quantile(x,.75,na.rm=T), min(x,na.rm=T), max(x,na.rm=T))
cat("cor_u  :", q(R$cor_u), "\n"); cat("ir_u   :", q(R$ir_u), "\n"); cat("dir_u  :", q(R$dir_u), "\n")
cat("cor_p  :", q(R$cor_p), "\n"); cat("ir_p   :", q(R$ir_p), "\n"); cat("dir_p  :", q(R$dir_p), "\n")
cat("pos dir_u:", sum(R$dir_u>0,na.rm=T), "/", sum(is.finite(R$dir_u)),
    "  pos dir_p:", sum(R$dir_p>0,na.rm=T), "/", sum(is.finite(R$dir_p)), "\n")
cat("cor_u<0.2:", sum(R$cor_u<0.2,na.rm=T), "  cor_p<0.2:", sum(R$cor_p<0.2,na.rm=T), "\n")
cat("survivors u:", sum(R$dir_u>=0.05,na.rm=T), "  p:", sum(R$dir_p>=0.05,na.rm=T), "\n")
R[, `:=`(short_u = req_u - ir_u, short_p = req_p - ir_p)]
R[, short_best := pmin(short_u, short_p, na.rm=TRUE)]
print(R[order(short_best)][1:5, .(factor, cor_u, ir_u, req_u, short_u, cor_p, ir_p, req_p, short_p, dir_u, dir_p)])
cat("\n--- paired parking effect (같은 팩터 내, 창 다름 주의) ---\n")
cat("cor: paired t =", tryCatch(t.test(R$cor_p, R$cor_u, paired=TRUE)$statistic, error=function(e) NA), "\n")
saveRDS(R, "stage_artifacts/pg2_hunt/s1_results.rds")
