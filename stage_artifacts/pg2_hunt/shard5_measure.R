## 샤드 5/8 — 2-arm 전수 측정 (arm1 무조건부 전기간 / arm2 FQ191 파킹 73개월)
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[s5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

inc <- bm_load_incumbent()
A <- readRDS(file.path(OUT, "factor_long.rds"))
M <- readRDS(file.path(OUT, "mkt.rds"))
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
BEN <- as.data.table(M$bench); LIQ <- as.data.table(M$liq); SZ <- as.data.table(M$size_dt)
Mru <- fread(file.path(ROOT, "stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]

## ── 입력 실측 (가정 금지) ────────────────────────────────────────
say("A: %d행 · %d팩터 · Date %s~%s · %d개월",
    nrow(A), uniqueN(A$Factor_Name), min(A$Date), max(A$Date), uniqueN(A$Date))
say("ret: %d행 · %d개월 · %s~%s", nrow(ret), uniqueN(ret$Date), min(ret$Date), max(ret$Date))
say("incumbent: %d행 · %s~%s · IR %.4f",
    nrow(inc), min(inc$date), max(inc$date), bm_ir(inc$active, 12))
say("regime: %d개월 · ON %d · 에피소드 %d · %s~%s",
    nrow(Mru), sum(Mru$regime), sum(diff(c(0L, as.integer(Mru$regime))) == 1L),
    min(Mru$date), max(Mru$date))

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 5]
say("전체 %d팩터 → 샤드5 %d팩터", length(FN), length(mine))

WGRID <- c(0.05, 0.10, 0.15, 0.20, 0.30)
CSV <- file.path(OUT, "shard5_results.csv")

armstat <- function(sl) {
  ## sl: data.table(date, ret_net)
  o <- bm_delta_ir(sl, weight = 0.20, incumbent = inc)
  if (!identical(o$status, "MEASURED"))
    return(list(ok = FALSE, why = o$status, n = o$n_overlap))
  sw <- bm_delta_ir_sweep(sl)
  sw <- sw[is.finite(delta_ir)]
  if (!nrow(sw)) return(list(ok = FALSE, why = "SWEEP_EMPTY", n = o$n_overlap))
  bi <- which.max(sw$delta_ir)
  list(ok = TRUE, n = o$n_overlap, cor = o$correlation_with_incumbent,
       ir = o$sleeve_standalone_ir, ir_inc = o$incumbent_ir_on_overlap,
       d20 = o$delta_ir, best_d = sw$delta_ir[bi], best_w = sw$weight[bi],
       all_beat = all(sw$beats), n_beat = sum(sw$beats),
       win = paste(o$window, collapse = "~"), off = o$align_offset)
}

rows <- list(); fails <- list(); t0 <- Sys.time()
for (j in seq_along(mine)) {
  f <- mine[j]
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  r <- tryCatch(suppressWarnings(canonical_screen_bt(
        S, ret, BEN, top_n = 25L, cost_bps_oneway = 15, liq_dt = LIQ, liq_min = 2e8,
        run_id = f, strategy_id = f, diag_dual_basis = FALSE, size_dt = SZ)),
        error = function(e) conditionMessage(e))
  if (is.character(r)) { fails[[length(fails)+1L]] <- data.table(factor=f, why=paste0("BT_ERROR: ", substr(r,1,120))); next }
  PR <- as.data.table(r$period_returns)
  if (!nrow(PR)) { fails[[length(fails)+1L]] <- data.table(factor=f, why="EMPTY_PERIOD_RETURNS"); next }

  pt <- NA_real_
  bc <- tryCatch(as.data.table(r$benchmark_compare), error = function(e) NULL)
  if (!is.null(bc) && nrow(bc)) {
    nm <- names(bc)[1]
    hit <- grep("Portfolio_Alpha_t_NW_lag3", bc[[nm]], fixed = TRUE)
    if (length(hit)) pt <- suppressWarnings(as.numeric(bc[[2]][hit[1]]))
  }

  a1 <- armstat(PR[, .(date, ret_net)])

  X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by = "date")
  a2 <- if (nrow(X) < 60L) list(ok = FALSE, why = sprintf("REGIME_MERGE_%d", nrow(X)), n = nrow(X)) else {
    X <- X[order(date)]
    X[, sw := c(0L, abs(diff(as.integer(regime))))]
    X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw * 15/1e4]
    armstat(X[, .(date, ret_net = r2)])
  }
  if (!a1$ok && !a2$ok)
    fails[[length(fails)+1L]] <- data.table(factor=f, why=paste0("arm1=",a1$why," arm2=",a2$why))

  g <- function(a, k) if (isTRUE(a$ok)) a[[k]] else NA
  rows[[length(rows)+1L]] <- data.table(
    factor = f, n_bt = nrow(PR), port_t = pt,
    n_u = g(a1,"n"), cor_u = g(a1,"cor"), ir_u = g(a1,"ir"), d20_u = g(a1,"d20"),
    bd_u = g(a1,"best_d"), bw_u = g(a1,"best_w"), nb_u = g(a1,"n_beat"), all_u = g(a1,"all_beat"),
    irinc_u = g(a1,"ir_inc"), win_u = g(a1,"win"), off_u = g(a1,"off"),
    n_p = g(a2,"n"), cor_p = g(a2,"cor"), ir_p = g(a2,"ir"), d20_p = g(a2,"d20"),
    bd_p = g(a2,"best_d"), bw_p = g(a2,"best_w"), nb_p = g(a2,"n_beat"), all_p = g(a2,"all_beat"),
    irinc_p = g(a2,"ir_inc"), win_p = g(a2,"win"), off_p = g(a2,"off"))

  if (j %% 10 == 0) {
    fwrite(rbindlist(rows, fill = TRUE), CSV)
    say("  %d/%d (%.1f분) 저장", j, length(mine), as.numeric(difftime(Sys.time(), t0, units="mins")))
  }
}
R <- rbindlist(rows, fill = TRUE)
fwrite(R, CSV)
F <- if (length(fails)) rbindlist(fails, fill = TRUE) else data.table(factor=character(), why=character())
fwrite(F, file.path(OUT, "shard5_fails.csv"))
saveRDS(list(R = R, F = F), file.path(OUT, "shard5.rds"))
say("완료: 측정 %d · 실패 %d · %.1f분", nrow(R), nrow(F), as.numeric(difftime(Sys.time(), t0, units="mins")))
print(R[, .(factor, cor_u, ir_u, bd_u, cor_p, ir_p, bd_p)])
