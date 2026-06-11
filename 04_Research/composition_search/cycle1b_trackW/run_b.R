# =============================================================================
# run_b.R — Track W between-sleeve trials (B01-B11, 11 trials)
#   B01-05: score-level theta blend -> top-20 EW (selection varies with theta)
#   B06-08: portfolio-level fixed theta (core top-13 EW + defense top-12 EW)
#   B09-11: dynamic theta from trailing 36m sleeve GROSS returns (t-1 PIT)
#   Common months (all 11 identical): first w_idx with >= 36 realized sleeve
#   months (longest estimation window of the B grid) — prereg identical-months rule.
#   Baseline for deltas: B03 (production theta=0.65, score level).
# =============================================================================
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TRACKW_DIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1b_trackW")
source(file.path(TRACKW_DIR, "trackw_engine.R"))

b_score  <- as.data.table(read_parquet(file.path(INT_DIR, "b_score_sel.parquet")))
b_sleeve <- as.data.table(read_parquet(file.path(INT_DIR, "b_sleeve_sel.parquet")))
bench <- fread(file.path(INT_DIR, "bench_monthly.csv"))
for (dtb in list(b_score, b_sleeve)) dtb[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]

full_grid <- unique(b_sleeve[, .(w_idx, r_idx)]); setorder(full_grid, w_idx)

# ── sleeve GROSS monthly series (estimation input only, Return.portfolio) ────
bench_full <- data.table(r_idx = full_grid$r_idx, ym = format(full_grid$r_idx, "%Y-%m"))
bench_full <- merge(bench_full, bench, by = "ym", all.x = TRUE)[, .(r_idx, bm_ret)]
sleeve_gross <- list()
for (sv in c("core", "defense")) {
  ss <- b_sleeve[sleeve == sv]
  ss[, w := 1 / .N, by = w_idx]
  m <- run_trial_portfolio(ss[, .(w_idx, Ticker, w)], ss[, .(w_idx, Ticker, Ret_1m)],
                           full_grid, bench_full)
  sleeve_gross[[sv]] <- m[, .(r_idx, ret_gross)]
}
slv <- merge(sleeve_gross$core, sleeve_gross$defense, by = "r_idx", suffixes = c("_c", "_d"))
setorder(slv, r_idx)
cat(sprintf("[run_b] sleeve gross series: %d months %s ~ %s\n", nrow(slv),
            as.character(min(slv$r_idx)), as.character(max(slv$r_idx))))

# ── common months: w_idx with >= 36 realized sleeve months (r_idx <= w_idx) ──
n_hist <- vapply(full_grid$w_idx, function(w) sum(slv$r_idx <= w), integer(1))
grid <- full_grid[n_hist >= 36L]
cat(sprintf("[run_b] common months: %d | start %s\n", nrow(grid), as.character(min(grid$w_idx))))
bench_dt <- bench_full[r_idx %in% grid$r_idx]

theta_hist <- function(w_idx, kind) {
  h <- slv[r_idx <= w_idx]
  h <- tail(h, 36L)
  rc <- h$ret_gross_c; rd <- h$ret_gross_d
  if (kind == "iv") {
    sc <- sd(rc); sdv <- sd(rd)
    (1 / sc) / (1 / sc + 1 / sdv)
  } else if (kind == "idv") {
    sc <- sqrt(mean(pmin(rc, 0)^2)); sdv <- sqrt(mean(pmin(rd, 0)^2))
    if (sc <= 0 || sdv <= 0) return(0.5)
    (1 / sc) / (1 / sc + 1 / sdv)
  } else if (kind == "minvar") {
    vc <- var(rc); vd <- var(rd); cv <- cov(rc, rd)
    den <- vc + vd - 2 * cv
    th <- if (abs(den) < 1e-12) 0.5 else (vd - cv) / den
    min(max(th, 0.2), 0.9)
  } else stop("kind")
}

# combined stock weights for portfolio-level trials
plevel_weights <- function(theta_by_m) {
  cs <- b_sleeve[sleeve == "core" & w_idx %in% grid$w_idx]
  ds <- b_sleeve[sleeve == "defense" & w_idx %in% grid$w_idx]
  cs[, w := theta_by_m[as.character(w_idx)] / .N, by = w_idx]
  ds[, w := (1 - theta_by_m[as.character(w_idx)]) / .N, by = w_idx]
  ww <- rbindlist(list(cs[, .(w_idx, Ticker, w)], ds[, .(w_idx, Ticker, w)]))
  ww[, .(w = sum(w)), by = .(w_idx, Ticker)]   # overlap names summed
}
b_rets <- unique(rbindlist(list(
  b_sleeve[w_idx %in% grid$w_idx, .(w_idx, Ticker, Ret_1m)],
  b_score[w_idx %in% grid$w_idx, .(w_idx, Ticker, Ret_1m)])))
# guard: a (w_idx,Ticker) must have one Ret_1m
stopifnot(b_rets[, .N, by = .(w_idx, Ticker)][N > 1, .N] == 0)

trials <- list(
  list(id = "B01", label = "score theta=0.35", kind = "score", theta = 0.35),
  list(id = "B02", label = "score theta=0.50", kind = "score", theta = 0.50),
  list(id = "B03", label = "score theta=0.65 (PRODUCTION BASELINE)", kind = "score", theta = 0.65),
  list(id = "B04", label = "score theta=0.80", kind = "score", theta = 0.80),
  list(id = "B05", label = "score theta=1.00 (core only)", kind = "score", theta = 1.00),
  list(id = "B06", label = "plevel fixed theta=0.50", kind = "pfix", theta = 0.50),
  list(id = "B07", label = "plevel fixed theta=0.65", kind = "pfix", theta = 0.65),
  list(id = "B08", label = "plevel fixed theta=0.80", kind = "pfix", theta = 0.80),
  list(id = "B09", label = "plevel inverse-vol 36m", kind = "pdyn", est = "iv"),
  list(id = "B10", label = "plevel inverse-downside-vol 36m", kind = "pdyn", est = "idv"),
  list(id = "B11", label = "plevel min-var 36m theta[0.2,0.9]", kind = "pdyn", est = "minvar")
)

results <- list(); series <- list(); theta_log <- list()
for (tr in trials) {
  t0 <- Sys.time()
  if (tr$kind == "score") {
    ss <- b_score[trial == tr$id & w_idx %in% grid$w_idx]
    ss[, w := 1 / .N, by = w_idx]
    weights_dt <- ss[, .(w_idx, Ticker, w)]
    rets_dt <- ss[, .(w_idx, Ticker, Ret_1m)]
  } else {
    th <- if (tr$kind == "pfix") {
      setNames(rep(tr$theta, nrow(grid)), as.character(grid$w_idx))
    } else {
      setNames(vapply(grid$w_idx, theta_hist, numeric(1), kind = tr$est),
               as.character(grid$w_idx))
    }
    theta_log[[tr$id]] <- data.table(w_idx = grid$w_idx, theta = as.numeric(th))
    weights_dt <- plevel_weights(th)
    rets_dt <- b_rets[paste(w_idx, Ticker) %in% weights_dt[, paste(w_idx, Ticker)]]
  }
  m <- run_trial_portfolio(weights_dt, rets_dt, grid, bench_dt)
  trial_id <- sprintf("B_%s", tr$id)
  row <- summarise_trial(m, grid, trial_id, "B", weighting_method = tr$label)
  row[, method_id := tr$id]; row[, method_label := tr$label]
  results[[trial_id]] <- row
  series[[trial_id]] <- m
  cat(sprintf("  %s | %-40s | full SR %6.3f MDD %5.1f%% PORT_t %5.2f | IS %6.3f | OOS %6.3f | %.0fs\n",
              tr$id, tr$label, row$full_net_sr, row$full_mdd * 100, row$full_port_t_nw3,
              row$is_net_sr, row$oos_net_sr,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

res <- rbindlist(results, fill = TRUE)
fwrite(res, file.path(INT_DIR, "results_B.csv"))
saveRDS(series, file.path(INT_DIR, "series_B.rds"))
saveRDS(theta_log, file.path(INT_DIR, "theta_log_B.rds"))
cat(sprintf("RUN_B_OK trials=%d\n", nrow(res)))
