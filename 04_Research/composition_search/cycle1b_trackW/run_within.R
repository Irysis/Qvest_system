# =============================================================================
# run_within.R — Track W within-sleeve trials (22 methods) for one substrate
#   Substrate via env TRACKW_SUB in {S1, S2, S3}. Optional TRACKW_MAXM (smoke).
#   Outputs: intermediate/results_<SUB>.csv + series_<SUB>.rds
# =============================================================================
SUB <- Sys.getenv("TRACKW_SUB", "S1")
MAXM <- as.integer(Sys.getenv("TRACKW_MAXM", "0"))   # 0 = all months

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TRACKW_DIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1b_trackW")
source(file.path(TRACKW_DIR, "trackw_engine.R"))

sel  <- as.data.table(read_parquet(file.path(INT_DIR, sprintf("%s_sel.parquet", tolower(SUB)))))
grid <- fread(file.path(INT_DIR, sprintf("%s_grid.csv", tolower(SUB))))
grid[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]
RET  <- as.data.table(read_parquet(file.path(INT_DIR,
          if (SUB == "S1") "ret_s1b.parquet" else sprintf("ret_%s.parquet", tolower(SUB)))))
RET[, Date := as.Date(Date)]
setkey(RET, Ticker, Date)
bench <- fread(file.path(INT_DIR, "bench_monthly.csv"))

sel[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]
setorder(grid, w_idx)
if (MAXM > 0) {
  grid <- grid[seq_len(min(MAXM, .N))]
  sel <- sel[w_idx %in% grid$w_idx]
}
bench_dt <- data.table(r_idx = grid$r_idx, ym = format(grid$r_idx, "%Y-%m"))
bench_dt <- merge(bench_dt, bench, by = "ym", all.x = TRUE)[, .(r_idx, bm_ret)]
stopifnot(bench_dt[is.na(bm_ret), .N] == 0)

months <- grid$w_idx
inv_months <- sort(unique(sel$w_idx))
cat(sprintf("[run_within %s] grid %d months (%d invested) | %s ~ %s\n",
            SUB, length(months), length(inv_months),
            as.character(min(months)), as.character(max(months))))

# per-month selection + cov slice cache (shared across all 22 methods)
all_d <- sort(unique(RET$Date))
sel_by_m <- split(sel, by = "w_idx", keep.by = TRUE)
slices <- new.env()
get_slice <- function(w_idx, tks) {
  key <- as.character(w_idx)
  if (!is.null(slices[[key]])) return(slices[[key]])
  dwin <- all_d[all_d <= w_idx]
  lo <- dwin[max(1L, length(dwin) - 759L)]
  sl <- RET[Ticker %in% tks & Date >= lo & Date <= w_idx, .(Date, Ticker, Ret)]
  slices[[key]] <- sl
  sl
}

specs <- trackw_method_specs()
rets_dt <- sel[, .(w_idx, Ticker, Ret_1m)]
results <- list(); series <- list()

for (sp in specs) {
  t0 <- Sys.time()
  wt_list <- vector("list", length(inv_months))
  for (mi in seq_along(inv_months)) {
    wm <- inv_months[mi]
    ms <- sel_by_m[[as.character(wm)]]
    sl <- if (sp$kind %in% c("equal", "tilt")) NULL else get_slice(wm, ms$Ticker)
    w <- compute_month_weights(sp, ms$Ticker, ms$Score, sl)
    wt_list[[mi]] <- data.table(w_idx = wm, Ticker = names(w), w = as.numeric(w))
  }
  weights_dt <- rbindlist(wt_list)
  m <- run_trial_portfolio(weights_dt, rets_dt, grid, bench_dt)
  trial_id <- sprintf("%s_%s", SUB, sp$id)
  row <- summarise_trial(m, grid, trial_id, SUB)
  row[, method_id := sp$id]; row[, method_label := sp$label]
  results[[trial_id]] <- row
  series[[trial_id]] <- m
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("  %s | %-44s | full SR %6.3f MDD %5.1f%% PORT_t %5.2f | IS SR %6.3f | OOS SR %6.3f | %.0fs\n",
              sp$id, sp$label, row$full_net_sr, row$full_mdd * 100,
              row$full_port_t_nw3, row$is_net_sr, row$oos_net_sr, el))
}

res <- rbindlist(results, fill = TRUE)
fwrite(res, file.path(INT_DIR, sprintf("results_%s.csv", SUB)))
saveRDS(series, file.path(INT_DIR, sprintf("series_%s.rds", SUB)))
cat(sprintf("RUN_WITHIN_%s_OK trials=%d\n", SUB, nrow(res)))
