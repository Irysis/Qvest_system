## 샤드 7/8 — 2-arm book-marginal 전수 측정
suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

OUT <- "stage_artifacts/pg2_hunt/shard7_results.csv"
ERR <- "stage_artifacts/pg2_hunt/shard7_errors.csv"

A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds")
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
setDT(A)
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
bench <- as.data.table(M$bench); liq <- as.data.table(M$liq); sz <- as.data.table(M$size_dt)
inc <- bm_load_incumbent()
Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]

## ---- 입력 실측 (가정 금지) ----
cat("=== INPUT AUDIT ===\n")
cat(sprintf("factor_long: rows=%d  factors=%d  months=%d  range=%s..%s\n",
  nrow(A), uniqueN(A$Factor_Name), uniqueN(A$Date), as.character(min(A$Date)), as.character(max(A$Date))))
cat(sprintf("ret: rows=%d months=%d range=%s..%s\n", nrow(ret), uniqueN(ret$Date),
  as.character(min(ret$Date)), as.character(max(ret$Date))))
cat(sprintf("bench: rows=%d cols=%s\n", nrow(bench), paste(names(bench), collapse=",")))
cat(sprintf("incumbent: rows=%d cols=%s range=%s..%s\n", nrow(inc), paste(names(inc), collapse=","),
  as.character(min(inc$date)), as.character(max(inc$date))))
cat(sprintf("regime: rows=%d ON=%d range=%s..%s\n", nrow(Mru), sum(as.logical(Mru$regime)),
  as.character(min(Mru$date)), as.character(max(Mru$date))))

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 7]
cat(sprintf("TOTAL factors=%d  MY SHARD (idx%%8==7)=%d\n", length(FN), length(mine)))
cat("=== END AUDIT ===\n"); flush.console()

res <- list(); errs <- list(); k <- 0L
t0 <- Sys.time()

for (f in mine) {
  k <- k + 1L
  row <- data.table(factor = f, n = NA_integer_,
    cor_uncond = NA_real_, ir_uncond = NA_real_, dIR_uncond = NA_real_,
    n_park = NA_integer_, cor_park = NA_real_, ir_park = NA_real_, dIR_park = NA_real_,
    best_arm = NA_character_, best_dIR = NA_real_, best_w = NA_real_,
    beats_all_w = NA, win_uncond = NA_character_, win_park = NA_character_,
    status_uncond = NA_character_, status_park = NA_character_)
  ok <- TRUE
  bt <- tryCatch({
    S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
    S <- S[is.finite(score)]
    if (nrow(S) < 100L) stop("EMPTY_PANEL: rows=", nrow(S))
    suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = 25L,
      cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8,
      run_id = f, strategy_id = f, diag_dual_basis = FALSE, size_dt = sz))
  }, error = function(e) e)
  if (inherits(bt, "error")) {
    errs[[length(errs)+1L]] <- data.table(factor = f, stage = "canonical_screen_bt", msg = conditionMessage(bt))
    res[[length(res)+1L]] <- row; ok <- FALSE
  }
  if (ok) {
    PR <- as.data.table(bt$period_returns)
    if (!all(c("date","ret_net","benchmark_ret") %in% names(PR))) {
      errs[[length(errs)+1L]] <- data.table(factor=f, stage="period_returns_cols",
        msg=paste(names(PR), collapse=","))
      res[[length(res)+1L]] <- row; ok <- FALSE
    }
  }
  if (ok) {
    PR <- PR[is.finite(ret_net)]
    row$n <- nrow(PR)
    ## arm1 무조건부 (전기간)
    a1 <- tryCatch({
      sw <- bm_delta_ir_sweep(PR[, .(date, ret_net)])
      d1 <- bm_delta_ir(PR[, .(date, ret_net)], weight = 0.20, incumbent = inc)
      list(sw = sw, d = d1)
    }, error = function(e) e)
    if (inherits(a1, "error")) {
      errs[[length(errs)+1L]] <- data.table(factor=f, stage="arm1", msg=conditionMessage(a1))
    } else {
      sw <- a1$sw
      row$status_uncond <- sw$status[1]
      if (any(is.finite(sw$delta_ir))) {
        i <- which.max(ifelse(is.finite(sw$delta_ir), sw$delta_ir, -Inf))
        row$dIR_uncond <- sw$delta_ir[i]
        row$cor_uncond <- sw$cor_inc[i]
        row$win_uncond <- paste0(as.character(min(PR$date)), "..", as.character(max(PR$date)),
                                 "|n=", sw$n[i])
        row$ir_uncond <- if (is.list(a1$d)) a1$d$sleeve_standalone_ir else NA_real_
        row$beats_all_w <- all(sw$beats)
        attr(row, "sw1") <- sw
      }
    }
    ## arm2 파킹 (73개월 창)
    a2 <- tryCatch({
      X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime = as.logical(regime))], by = "date")
      if (nrow(X) < 60L) stop("PARK_OVERLAP: n=", nrow(X))
      setorder(X, date)
      X[, sw_ := c(0L, abs(diff(as.integer(regime))))]
      X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw_*15/1e4]
      swp <- bm_delta_ir_sweep(X[, .(date, ret_net = r2)])
      dp <- bm_delta_ir(X[, .(date, ret_net = r2)], weight = 0.20, incumbent = inc)
      list(sw = swp, d = dp, X = X)
    }, error = function(e) e)
    if (inherits(a2, "error")) {
      errs[[length(errs)+1L]] <- data.table(factor=f, stage="arm2", msg=conditionMessage(a2))
    } else {
      swp <- a2$sw
      row$status_park <- swp$status[1]
      row$n_park <- nrow(a2$X)
      if (any(is.finite(swp$delta_ir))) {
        j <- which.max(ifelse(is.finite(swp$delta_ir), swp$delta_ir, -Inf))
        row$dIR_park <- swp$delta_ir[j]
        row$cor_park <- swp$cor_inc[j]
        row$win_park <- paste0(as.character(min(a2$X$date)), "..", as.character(max(a2$X$date)),
                               "|n=", swp$n[j])
        row$ir_park <- if (is.list(a2$d)) a2$d$sleeve_standalone_ir else NA_real_
        attr(row, "sw2") <- swp
      }
    }
    ## best arm
    c1 <- row$dIR_uncond; c2 <- row$dIR_park
    if (is.finite(c1) || is.finite(c2)) {
      if (!is.finite(c2) || (is.finite(c1) && c1 >= c2)) {
        row$best_arm <- "uncond"; row$best_dIR <- c1
        sw <- attr(row, "sw1"); row$best_w <- sw$weight[which.max(ifelse(is.finite(sw$delta_ir), sw$delta_ir, -Inf))]
        row$beats_all_w <- all(sw$beats)
      } else {
        row$best_arm <- "parked"; row$best_dIR <- c2
        sw <- attr(row, "sw2"); row$best_w <- sw$weight[which.max(ifelse(is.finite(sw$delta_ir), sw$delta_ir, -Inf))]
        row$beats_all_w <- all(sw$beats)
      }
    }
  }
  res[[length(res)+1L]] <- row
  if (k %% 5L == 0L || k == length(mine)) {
    cat(sprintf("[%d/%d] %s  elapsed=%.1fmin\n", k, length(mine), f,
      as.numeric(difftime(Sys.time(), t0, units="mins")))); flush.console()
    fwrite(rbindlist(res, fill=TRUE), OUT)
  }
}

R <- rbindlist(res, fill = TRUE)
fwrite(R, OUT)
if (length(errs)) fwrite(rbindlist(errs, fill=TRUE), ERR) else fwrite(data.table(factor=character()), ERR)

cat("\n=== SUMMARY ===\n")
cat(sprintf("measured=%d  failed=%d\n", sum(!is.na(R$best_dIR)), sum(is.na(R$best_dIR))))
q <- function(x) { x <- x[is.finite(x)]; if(!length(x)) return("n/a")
  sprintf("n=%d med=%.4f q25=%.4f q75=%.4f max=%.4f pos=%d(%.1f%%)", length(x), median(x),
    quantile(x,.25), quantile(x,.75), max(x), sum(x>0), 100*mean(x>0)) }
cat("dIR_uncond: ", q(R$dIR_uncond), "\n")
cat("dIR_park  : ", q(R$dIR_park), "\n")
cat("cor_uncond: ", q(R$cor_uncond), "\n")
cat("cor_park  : ", q(R$cor_park), "\n")
cat("ir_uncond : ", q(R$ir_uncond), "\n")
cat("ir_park   : ", q(R$ir_park), "\n")
cat("survivors(best_dIR>=0.05): ", sum(R$best_dIR >= 0.05, na.rm=TRUE), "\n")
print(R[order(-best_dIR)][1:8, .(factor, n, cor_uncond, ir_uncond, dIR_uncond, cor_park, ir_park, dIR_park, best_arm, best_dIR, best_w)])
if (length(errs)) { cat("\n--- ERRORS ---\n"); print(rbindlist(errs, fill=TRUE)[, .N, by=.(stage)]) ; print(rbindlist(errs, fill=TRUE)[1:min(10,.N)]) }
cat("=== DONE ===\n")
