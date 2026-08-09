suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

OUT <- "stage_artifacts/pg2_hunt/shard6_results.csv"
LOG <- "stage_artifacts/pg2_hunt/shard6_log.txt"
cat("", file = LOG)
lg <- function(...) { m <- paste0(...); cat(m, "\n"); cat(m, "\n", file = LOG, append = TRUE) }

A <- readRDS("stage_artifacts/pg2_hunt/factor_long.rds")
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
A <- as.data.table(A)
ret <- as.data.table(M$ret)[!is.na(Ret_1m)]
bench <- as.data.table(M$bench)
liq <- as.data.table(M$liq)
size_dt <- as.data.table(M$size_dt)
inc <- bm_load_incumbent()
Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")
Mru[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01")]

## --- 입력 실측 (가정 금지) ---
lg("[INPUT] factor_long rows=", nrow(A), " factors=", uniqueN(A$Factor_Name),
   " months=", uniqueN(A$Date), " range=", as.character(min(A$Date)), "..", as.character(max(A$Date)))
lg("[INPUT] ret rows=", nrow(ret), " months=", uniqueN(ret$Date))
lg("[INPUT] bench rows=", nrow(bench), " cols=", paste(names(bench), collapse=","))
lg("[INPUT] regime rows=", nrow(Mru), " ON=", sum(as.integer(Mru$regime)),
   " range=", as.character(min(Mru$date)), "..", as.character(max(Mru$date)))
lg("[INPUT] incumbent rows=", nrow(inc), " range=", as.character(min(inc$date)), "..", as.character(max(inc$date)))

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 6]
lg("[SHARD] 6/8  n=", length(mine))

WTS <- c(0.05, 0.10, 0.15, 0.20, 0.30)

run_arm <- function(sl) {
  rs <- lapply(WTS, function(w) {
    o <- try(bm_delta_ir(sl, weight = w, incumbent = inc), silent = TRUE)
    if (inherits(o, "try-error")) return(data.table(weight=w, status="ERROR", n=NA_integer_,
        delta_ir=NA_real_, cor_inc=NA_real_, sleeve_ir=NA_real_))
    data.table(weight = w, status = o$status, n = as.integer(o$n_overlap %||% NA),
      delta_ir = as.numeric(o$delta_ir %||% NA),
      cor_inc = as.numeric(o$correlation_with_incumbent %||% NA),
      sleeve_ir = as.numeric(o$sleeve_standalone_ir %||% NA))
  })
  rbindlist(rs, fill = TRUE)
}

res <- list(); errs <- list(); i <- 0L
for (f in mine) {
  i <- i + 1L
  S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
  S <- S[is.finite(score)]
  r <- try(suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8,
        run_id = f, strategy_id = f, diag_dual_basis = FALSE,
        size_dt = size_dt)), silent = TRUE)
  if (inherits(r, "try-error")) {
    errs[[length(errs)+1]] <- data.table(factor = f, stage = "screen_bt",
       msg = substr(as.character(r), 1, 200)); lg("[ERR] ", f, " screen_bt"); next
  }
  PR <- as.data.table(r$period_returns)
  if (!nrow(PR)) { errs[[length(errs)+1]] <- data.table(factor=f, stage="empty_pr", msg="0 rows")
    lg("[ERR] ", f, " empty period_returns"); next }

  a1 <- run_arm(PR[, .(date, ret_net)])

  X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru[, .(date, regime)], by = "date")
  a2 <- if (nrow(X) < 60L) {
    data.table(weight=WTS, status="PARK_MERGE_SHORT", n=nrow(X), delta_ir=NA_real_,
               cor_inc=NA_real_, sleeve_ir=NA_real_)
  } else {
    Xc <- copy(X)
    Xc[, reg := as.integer(regime)]
    setorder(Xc, date)
    Xc[, sw := c(0L, abs(diff(reg)))]
    Xc[, r2 := ifelse(reg == 1L, ret_net, benchmark_ret) - sw * 15/1e4]
    run_arm(Xc[, .(date, ret_net = r2)])
  }

  b1 <- a1[is.finite(delta_ir)]; b2 <- a2[is.finite(delta_ir)]
  g1 <- if (nrow(b1)) b1[which.max(delta_ir)] else NULL
  g2 <- if (nrow(b2)) b2[which.max(delta_ir)] else NULL

  row <- data.table(
    factor = f,
    n_uncond = if (nrow(b1)) b1$n[1] else NA_integer_,
    n_park   = if (nrow(b2)) b2$n[1] else NA_integer_,
    cor_uncond = if (!is.null(g1)) a1[weight==0.20]$cor_inc else NA_real_,
    ir_uncond  = if (!is.null(g1)) a1[weight==0.20]$sleeve_ir else NA_real_,
    dIR_uncond = if (!is.null(g1)) a1[weight==0.20]$delta_ir else NA_real_,
    best_dIR_uncond = if (!is.null(g1)) g1$delta_ir else NA_real_,
    best_w_uncond   = if (!is.null(g1)) g1$weight else NA_real_,
    n_beats_uncond  = if (nrow(b1)) sum(b1$delta_ir >= 0.05) else 0L,
    cor_park = if (!is.null(g2)) a2[weight==0.20]$cor_inc else NA_real_,
    ir_park  = if (!is.null(g2)) a2[weight==0.20]$sleeve_ir else NA_real_,
    dIR_park = if (!is.null(g2)) a2[weight==0.20]$delta_ir else NA_real_,
    best_dIR_park = if (!is.null(g2)) g2$delta_ir else NA_real_,
    best_w_park   = if (!is.null(g2)) g2$weight else NA_real_,
    n_beats_park  = if (nrow(b2)) sum(b2$delta_ir >= 0.05) else 0L,
    status_uncond = a1$status[1], status_park = a2$status[1]
  )
  res[[length(res)+1]] <- row
  if (i %% 10 == 0 || i == length(mine)) {
    fwrite(rbindlist(res, fill=TRUE), OUT)
    lg("[PROGRESS] ", i, "/", length(mine), " last=", f)
  }
}

R <- rbindlist(res, fill = TRUE)
fwrite(R, OUT)
E <- if (length(errs)) rbindlist(errs, fill=TRUE) else data.table(factor=character(), stage=character(), msg=character())
fwrite(E, "stage_artifacts/pg2_hunt/shard6_errors.csv")
lg("[DONE] measured=", nrow(R), " failed=", nrow(E))
q1 <- function(x) sprintf("med %.4f [%.4f, %.4f] max %.4f", median(x,na.rm=TRUE),
    quantile(x,0.25,na.rm=TRUE), quantile(x,0.75,na.rm=TRUE), max(x,na.rm=TRUE))
lg("[UNCOND] cor: ", q1(R$cor_uncond), " | ir: ", q1(R$ir_uncond), " | dIR@0.20: ", q1(R$dIR_uncond),
   " | best_dIR: ", q1(R$best_dIR_uncond), " | pos best: ", sum(R$best_dIR_uncond>0,na.rm=TRUE))
lg("[PARK] cor: ", q1(R$cor_park), " | ir: ", q1(R$ir_park), " | dIR@0.20: ", q1(R$dIR_park),
   " | best_dIR: ", q1(R$best_dIR_park), " | pos best: ", sum(R$best_dIR_park>0,na.rm=TRUE))
lg("[SURVIVORS] uncond=", sum(R$n_beats_uncond>0,na.rm=TRUE), " park=", sum(R$n_beats_park>0,na.rm=TRUE))
lg("[WINDOW] n_uncond med=", median(R$n_uncond,na.rm=TRUE), " n_park med=", median(R$n_park,na.rm=TRUE))
