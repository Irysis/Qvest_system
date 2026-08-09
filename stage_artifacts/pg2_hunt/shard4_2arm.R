## Shard 4/8 — 2-arm book-marginal 전수 측정 (uncond + parked)
suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

OUT <- "stage_artifacts/pg2_hunt/shard4_results.csv"
LOG <- "stage_artifacts/pg2_hunt/shard4_log.txt"
lg <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S"), " ", sprintf(...), "\n")
                      cat(m); cat(m, file = LOG, append = TRUE) }

A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds")
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
bench <- as.data.table(M$bench); liq <- as.data.table(M$liq); sz <- as.data.table(M$size_dt)

## ── 입력 실측 (가정 금지) ───────────────────────────────────────────
lg("INPUT A: nrow=%d  factors=%d  months=%d  range=%s..%s",
   nrow(A), uniqueN(A$Factor_Name), uniqueN(A$Date),
   as.character(min(A$Date)), as.character(max(A$Date)))
lg("INPUT ret: nrow=%d months=%d range=%s..%s", nrow(ret), uniqueN(ret$Date),
   as.character(min(ret$Date)), as.character(max(ret$Date)))
lg("INPUT bench: nrow=%d cols=%s", nrow(bench), paste(names(bench), collapse=","))
lg("INPUT liq: nrow=%d | size: nrow=%d", nrow(liq), nrow(sz))

inc <- bm_load_incumbent()
lg("INPUT incumbent: n=%d range=%s..%s  IR=%.4f", nrow(inc),
   as.character(min(inc$date)), as.character(max(inc$date)), bm_ir(inc$active))

Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]
lg("INPUT regime: n=%d range=%s..%s ON=%d cols=%s", nrow(Mru),
   as.character(min(Mru$date)), as.character(max(Mru$date)),
   sum(as.logical(Mru$regime)), paste(names(Mru), collapse=","))

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 4]
lg("SHARD 4/8: %d factors of %d", length(mine), length(FN))

WTS <- c(0.05, 0.10, 0.15, 0.20, 0.30)

one_arm <- function(sl, tag) {
  ## sl: data.table(date, ret_net)
  out <- list(n = NA_integer_, cor = NA_real_, ir = NA_real_, best_d = NA_real_,
              best_w = NA_real_, n_beat = 0L, status = "NA", win = NA_character_)
  d20 <- tryCatch(bm_delta_ir(sl, weight = 0.20, incumbent = inc), error = function(e) e)
  if (inherits(d20, "error")) { out$status <- paste0("ERR:", conditionMessage(d20)); return(out) }
  out$status <- d20$status
  out$n <- d20$n_overlap
  if (d20$status != "MEASURED") return(out)
  out$cor <- d20$correlation_with_incumbent
  out$ir  <- d20$sleeve_standalone_ir
  out$win <- paste(d20$window, collapse = "..")
  sw <- tryCatch(bm_delta_ir_sweep(sl, weights = WTS), error = function(e) NULL)
  if (is.null(sw)) { out$best_d <- d20$delta_ir; out$best_w <- 0.20
                     out$n_beat <- as.integer(d20$delta_ir >= 0.05); return(out) }
  sw <- sw[is.finite(delta_ir)]
  if (!nrow(sw)) return(out)
  i <- which.max(sw$delta_ir)
  out$best_d <- sw$delta_ir[i]; out$best_w <- sw$weight[i]
  out$n_beat <- sum(sw$beats, na.rm = TRUE)
  out$n_w <- nrow(sw)
  out
}

res <- list(); errs <- list(); k <- 0L
for (f in mine) {
  k <- k + 1L
  row <- list(factor = f, n_obs = NA_integer_, n_months = NA_integer_,
              n_uncond = NA_integer_, cor_uncond = NA_real_, ir_uncond = NA_real_,
              dIR_uncond = NA_real_, w_uncond = NA_real_, nbeat_uncond = 0L, win_uncond = NA_character_,
              n_park = NA_integer_, cor_park = NA_real_, ir_park = NA_real_,
              dIR_park = NA_real_, w_park = NA_real_, nbeat_park = 0L, win_park = NA_character_,
              err = NA_character_)
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  S <- S[is.finite(score)]
  row$n_obs <- nrow(S); row$n_months <- uniqueN(S$Date)
  r <- tryCatch(suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8,
        run_id = f, strategy_id = f, diag_dual_basis = FALSE, size_dt = sz)),
        error = function(e) e)
  if (inherits(r, "error")) {
    row$err <- paste0("BT_ERR:", conditionMessage(r))
    errs[[length(errs)+1L]] <- row$err
  } else {
    PR <- as.data.table(r$period_returns)
    if (!all(c("date","ret_net","benchmark_ret") %in% names(PR))) {
      row$err <- paste0("PR_COLS:", paste(names(PR), collapse=","))
    } else {
      a1 <- one_arm(PR[, .(date, ret_net)], "uncond")
      row$n_uncond <- a1$n; row$cor_uncond <- a1$cor; row$ir_uncond <- a1$ir
      row$dIR_uncond <- a1$best_d; row$w_uncond <- a1$best_w
      row$nbeat_uncond <- a1$n_beat; row$win_uncond <- a1$win
      if (a1$status != "MEASURED") row$err <- paste0("UNCOND:", a1$status)

      X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by = "date")
      if (nrow(X) < 60L) {
        row$err <- paste0(if (is.na(row$err)) "" else paste0(row$err,";"),
                          "PARK_MERGE_N=", nrow(X))
      } else {
        X[, regime := as.logical(regime)]
        setorder(X, date)
        X[, sw := c(0L, abs(diff(as.integer(regime))))]
        X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
        a2 <- one_arm(X[, .(date, ret_net = r2)], "parked")
        row$n_park <- a2$n; row$cor_park <- a2$cor; row$ir_park <- a2$ir
        row$dIR_park <- a2$best_d; row$w_park <- a2$best_w
        row$nbeat_park <- a2$n_beat; row$win_park <- a2$win
        if (a2$status != "MEASURED")
          row$err <- paste0(if (is.na(row$err)) "" else paste0(row$err,";"), "PARK:", a2$status)
      }
    }
  }
  res[[length(res)+1L]] <- as.data.table(row)
  if (k %% 5L == 0L || k == length(mine)) {
    fwrite(rbindlist(res, fill = TRUE), OUT)
    lg("progress %d/%d  last=%s dU=%s dP=%s", k, length(mine), f,
       format(row$dIR_uncond, digits=4), format(row$dIR_park, digits=4))
  }
}
R <- rbindlist(res, fill = TRUE)
fwrite(R, OUT)
lg("DONE n=%d  err=%d", nrow(R), sum(!is.na(R$err)))
print(R[, .(factor, cor_uncond, ir_uncond, dIR_uncond, cor_park, ir_park, dIR_park, err)])
cat("\n--- SUMMARY ---\n")
q <- function(x) paste(sprintf("%.4f", quantile(x, c(0,.25,.5,.75,1), na.rm=TRUE)), collapse=" / ")
cat("cor_uncond min/q1/med/q3/max:", q(R$cor_uncond), "\n")
cat("ir_uncond  :", q(R$ir_uncond), "\n")
cat("dIR_uncond :", q(R$dIR_uncond), " pos=", sum(R$dIR_uncond>0, na.rm=TRUE), "\n")
cat("cor_park   :", q(R$cor_park), "\n")
cat("ir_park    :", q(R$ir_park), "\n")
cat("dIR_park   :", q(R$dIR_park), " pos=", sum(R$dIR_park>0, na.rm=TRUE), "\n")
cat("beats(any arm >=0.05):", sum(R$dIR_uncond>=0.05, na.rm=TRUE), "/", sum(R$dIR_park>=0.05, na.rm=TRUE), "\n")
