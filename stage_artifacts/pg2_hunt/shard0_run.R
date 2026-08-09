suppressPackageStartupMessages({ library(data.table) })
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/book_marginal.R")

OUT <- "stage_artifacts/pg2_hunt/shard0_results.csv"
ERR <- "stage_artifacts/pg2_hunt/shard0_errors.csv"
SWP <- "stage_artifacts/pg2_hunt/shard0_sweeps.csv"

A <- as.data.table(readRDS("stage_artifacts/pg2_hunt/factor_long.rds"))
M <- readRDS("stage_artifacts/pg2_hunt/mkt.rds")
ret  <- as.data.table(M$ret)[!is.na(Ret_1m)]
bench<- as.data.table(M$bench)
liq  <- as.data.table(M$liq)
szd  <- as.data.table(M$size_dt)
inc  <- bm_load_incumbent()
cat("[input] incumbent rows:", nrow(inc), "range", as.character(min(inc$date)), as.character(max(inc$date)), "\n")

Mru <- fread("stage_artifacts/FQ191/p1_rule.csv")[, date := as.Date(date)]
Mru <- Mru[date < as.Date("2026-01-01"), .(date, regime)]
cat("[input] regime rows:", nrow(Mru), "ON:", sum(Mru$regime),
    "range", as.character(min(Mru$date)), as.character(max(Mru$date)), "\n")

FN <- sort(unique(A$Factor_Name))
mine <- FN[seq_along(FN) %% 8 == 0]
cat("[input] shard factors:", length(mine), "\n")

WTS <- c(0.05, 0.10, 0.15, 0.20, 0.30)

res <- list(); errs <- list()
SW <- new.env(parent = emptyenv()); SW$sweeps <- list()   # <<- 는 globalenv 에서 globalenv 를 건너뛴다(실측 41/41 실패) — env 로 대체
done <- character(0)
if (file.exists(OUT)) { prev <- fread(OUT); done <- prev$factor; res[["prev"]] <- prev }

flush_all <- function() {
  if (length(res)) fwrite(rbindlist(res, fill=TRUE), OUT)
  if (length(SW$sweeps)) fwrite(rbindlist(SW$sweeps, fill=TRUE), SWP)
  if (length(errs)) fwrite(rbindlist(errs, fill=TRUE), ERR)
}

i <- 0L
for (f in setdiff(mine, done)) {
  i <- i + 1L
  ok <- TRUE
  out <- tryCatch({
    S <- A[Factor_Name == f, .(Date, Ticker, score = z)]
    S <- S[is.finite(score)]
    if (nrow(S) == 0L) stop("empty_score_panel")
    r <- suppressWarnings(canonical_screen_bt(S, ret, bench, top_n = 25L,
          cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8,
          run_id = f, strategy_id = f, diag_dual_basis = FALSE, size_dt = szd))
    PR <- as.data.table(r$period_returns)
    if (!"date" %in% names(PR)) {
      dc <- names(PR)[which(tolower(names(PR)) %in% c("date","period","ym"))[1]]
      setnames(PR, dc, "date")
    }
    PR[, date := as.Date(date)]

    ## arm1 무조건부 (전 기간)
    sw1 <- bm_delta_ir_sweep(PR[, .(date, ret_net)], weights = WTS)
    sw1[, `:=`(factor = f, arm = "uncond")]

    ## arm2 파킹 (FQ-191 국면 라벨 창)
    X <- merge(PR[, .(date, ret_net, benchmark_ret)], Mru, by = "date")
    n2 <- nrow(X)
    if (n2 > 0L) {
      setorder(X, date)
      X[, sw := c(0L, abs(diff(as.integer(regime))))]
      X[, r2 := ifelse(regime, ret_net, benchmark_ret) - sw*15/1e4]
      sw2 <- bm_delta_ir_sweep(X[, .(date, ret_net = r2)], weights = WTS)
    } else {
      sw2 <- data.table(weight=WTS, status="NO_REGIME_OVERLAP", n=0L, delta_ir=NA_real_,
                        verdict=NA_character_, book_ir=NA_real_, cor_inc=NA_real_, beats=FALSE)
    }
    sw2[, `:=`(factor = f, arm = "parked")]
    SW$sweeps[[f]] <- rbindlist(list(sw1, sw2), fill=TRUE)

    ## 대표 w=0.20 값 + sleeve IR
    g <- function(sw, w) sw[weight == w]
    a1 <- g(sw1, 0.20); a2 <- g(sw2, 0.20)
    d1 <- bm_delta_ir(PR[, .(date, ret_net)], weight = 0.20, incumbent = inc)
    d2 <- if (n2 > 0L) bm_delta_ir(X[, .(date, ret_net = r2)], weight = 0.20, incumbent = inc,
                                   require_overlap = 60L) else list(status="NO_REGIME_OVERLAP")
    b1 <- if (any(is.finite(sw1$delta_ir))) sw1[which.max(delta_ir)] else sw1[1]
    b2 <- if (any(is.finite(sw2$delta_ir))) sw2[which.max(delta_ir)] else sw2[1]
    bestarm <- if (!is.finite(b1$delta_ir[1]) && !is.finite(b2$delta_ir[1])) NA_character_
               else if (!is.finite(b2$delta_ir[1])) "uncond"
               else if (!is.finite(b1$delta_ir[1])) "parked"
               else if (b1$delta_ir[1] >= b2$delta_ir[1]) "uncond" else "parked"
    bd <- switch(if (is.na(bestarm)) "na" else bestarm, uncond = b1, parked = b2, na = NULL)

    data.table(
      factor = f,
      n = if (is.null(d1$n_overlap)) NA_integer_ else d1$n_overlap,
      n_parked = if (is.null(d2$n_overlap)) NA_integer_ else d2$n_overlap,
      status_uncond = d1$status, status_park = d2$status,
      cor_uncond = if (is.null(d1$correlation_with_incumbent)) NA_real_ else d1$correlation_with_incumbent,
      ir_uncond  = if (is.null(d1$sleeve_standalone_ir)) NA_real_ else d1$sleeve_standalone_ir,
      dIR_uncond = if (is.null(d1$delta_ir)) NA_real_ else d1$delta_ir,
      cor_park = if (is.null(d2$correlation_with_incumbent)) NA_real_ else d2$correlation_with_incumbent,
      ir_park  = if (is.null(d2$sleeve_standalone_ir)) NA_real_ else d2$sleeve_standalone_ir,
      dIR_park = if (is.null(d2$delta_ir)) NA_real_ else d2$delta_ir,
      ir_inc_overlap_uncond = if (is.null(d1$incumbent_ir_on_overlap)) NA_real_ else d1$incumbent_ir_on_overlap,
      ir_inc_overlap_park = if (is.null(d2$incumbent_ir_on_overlap)) NA_real_ else d2$incumbent_ir_on_overlap,
      best_arm = bestarm,
      best_dIR = if (is.null(bd)) NA_real_ else bd$delta_ir[1],
      best_w   = if (is.null(bd)) NA_real_ else bd$weight[1],
      n_beat_weights_uncond = sum(sw1$beats, na.rm=TRUE),
      n_beat_weights_park   = sum(sw2$beats, na.rm=TRUE),
      align_offset = if (is.null(d1$align_offset)) NA_integer_ else d1$align_offset
    )
  }, error = function(e) { ok <<- FALSE
    errs[[f]] <<- data.table(factor = f, reason = conditionMessage(e)); NULL })
  if (!is.null(out)) res[[f]] <- out
  if (i %% 5L == 0L) { cat("[progress]", i, "/", length(setdiff(mine, done)), " last:", f, "\n"); flush.console(); flush_all() }
}
flush_all()
cat("[done] measured:", length(res) - as.integer("prev" %in% names(res)), " errors:", length(errs), "\n")
R <- rbindlist(res, fill=TRUE)
print(R[order(-best_dIR)][1:15, .(factor, n, n_parked, cor_uncond, ir_uncond, dIR_uncond, cor_park, ir_park, dIR_park, best_arm, best_dIR, best_w)])
