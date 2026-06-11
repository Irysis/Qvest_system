# =============================================================================
# rerun_verify.R - Track W post-measurement adversarial re-verification
#   (a) REPRODUCTION: re-run (1) the best-improvement trial (max d_is_sr vs
#       same-substrate baseline among non-baseline trials) and (2) one random
#       trial (fixed seed 20260612), from prep inputs through the same engine
#       code path, and compare against stored results/series. tol = 1e-6.
#   (b) COST PROPORTIONALITY: across all 77 trials verify the delta-cost
#       identity cost_ann_bps == oneway_to_ann * 2 * 15 (per-name |dW| model,
#       both legs 15bps each => 30 bps per one-way unit), and that the
#       LOW-vs-HIGH turnover cost ratio tracks the turnover ratio (NOT flat).
#   (c) build_bt_result 10-component for IS finalists: NOT executed here -
#       follow-up obligation recorded in finalize/report (screening stage).
# ASCII only.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
options(scipen = 999)

PR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TW <- file.path(PR, "04_Research/composition_search/cycle1b_trackW")
INT <- file.path(TW, "intermediate")
TOL <- 1e-6

fails <- character(0)
chk <- function(name, cond, detail = "") {
  status <- if (isTRUE(cond)) "PASS" else "FAIL"
  if (!isTRUE(cond)) fails <<- c(fails, name)
  cat(sprintf("[%s] %s %s\n", status, name, detail))
}

# engine (same file that produced the results)
Sys.setenv(CLAUDE_PROJECT_DIR = PR)
suppressMessages(source(file.path(TW, "trackw_engine.R")))

res <- fread(file.path(TW, "weighting_results.csv"))

# ---- pick trials -------------------------------------------------------------
nonbl <- res[is_baseline == FALSE]
best <- nonbl[order(-d_is_sr)][1]
set.seed(20260612)
pool <- res[trial_id != best$trial_id]
rnd <- pool[sample(.N, 1)]
cat(sprintf("[pick] best-improvement: %s (%s, d_is_sr=%+.4f)\n",
            best$trial_id, best$method_label, best$d_is_sr))
cat(sprintf("[pick] random (seed 20260612): %s (%s)\n", rnd$trial_id, rnd$method_label))

# ---- rerun machinery ---------------------------------------------------------
load_sub <- function(SUB) {
  sel  <- as.data.table(read_parquet(file.path(INT, sprintf("%s_sel.parquet", tolower(SUB)))))
  grid <- fread(file.path(INT, sprintf("%s_grid.csv", tolower(SUB))))
  grid[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]
  RET  <- as.data.table(read_parquet(file.path(INT,
            if (SUB == "S1") "ret_s1b.parquet" else sprintf("ret_%s.parquet", tolower(SUB)))))
  RET[, Date := as.Date(Date)]; setkey(RET, Ticker, Date)
  bench <- fread(file.path(INT, "bench_monthly.csv"))
  sel[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]
  setorder(grid, w_idx)
  bench_dt <- data.table(r_idx = grid$r_idx, ym = format(grid$r_idx, "%Y-%m"))
  bench_dt <- merge(bench_dt, bench, by = "ym", all.x = TRUE)[, .(r_idx, bm_ret)]
  list(sel = sel, grid = grid, RET = RET, bench_dt = bench_dt)
}

rerun_within <- function(SUB, method_id) {
  d <- load_sub(SUB)
  sp <- Filter(function(s) s$id == method_id, trackw_method_specs())[[1]]
  inv_months <- sort(unique(d$sel$w_idx))
  all_d <- sort(unique(d$RET$Date))
  sel_by_m <- split(d$sel, by = "w_idx", keep.by = TRUE)
  wt_list <- vector("list", length(inv_months))
  for (mi in seq_along(inv_months)) {
    wm <- inv_months[mi]
    ms <- sel_by_m[[as.character(wm)]]
    sl <- if (sp$kind %in% c("equal", "tilt")) NULL else {
      dwin <- all_d[all_d <= wm]
      lo <- dwin[max(1L, length(dwin) - 759L)]
      d$RET[Ticker %in% ms$Ticker & Date >= lo & Date <= wm, .(Date, Ticker, Ret)]
    }
    w <- compute_month_weights(sp, ms$Ticker, ms$Score, sl)
    wt_list[[mi]] <- data.table(w_idx = wm, Ticker = names(w), w = as.numeric(w))
  }
  weights_dt <- rbindlist(wt_list)
  m <- run_trial_portfolio(weights_dt, d$sel[, .(w_idx, Ticker, Ret_1m)], d$grid, d$bench_dt)
  row <- summarise_trial(m, d$grid, sprintf("%s_%s", SUB, sp$id), SUB,
                         weighting_method = sp$label)
  list(m = m, row = row)
}

rerun_b <- function(method_id) {
  b_score  <- as.data.table(read_parquet(file.path(INT, "b_score_sel.parquet")))
  b_sleeve <- as.data.table(read_parquet(file.path(INT, "b_sleeve_sel.parquet")))
  bench <- fread(file.path(INT, "bench_monthly.csv"))
  for (dtb in list(b_score, b_sleeve)) dtb[, `:=`(w_idx = as.Date(w_idx), r_idx = as.Date(r_idx))]
  full_grid <- unique(b_sleeve[, .(w_idx, r_idx)]); setorder(full_grid, w_idx)
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
  n_hist <- vapply(full_grid$w_idx, function(w) sum(slv$r_idx <= w), integer(1))
  grid <- full_grid[n_hist >= 36L]
  bench_dt <- bench_full[r_idx %in% grid$r_idx]
  theta_hist <- function(w_idx, kind) {
    h <- slv[r_idx <= w_idx]; h <- tail(h, 36L)
    rc <- h$ret_gross_c; rd <- h$ret_gross_d
    if (kind == "iv") { sc <- sd(rc); sdv <- sd(rd); (1/sc)/(1/sc + 1/sdv) }
    else if (kind == "idv") {
      sc <- sqrt(mean(pmin(rc, 0)^2)); sdv <- sqrt(mean(pmin(rd, 0)^2))
      if (sc <= 0 || sdv <= 0) return(0.5)
      (1/sc)/(1/sc + 1/sdv)
    } else if (kind == "minvar") {
      vc <- var(rc); vd <- var(rd); cv <- cov(rc, rd)
      den <- vc + vd - 2*cv
      th <- if (abs(den) < 1e-12) 0.5 else (vd - cv)/den
      min(max(th, 0.2), 0.9)
    } else stop("kind")
  }
  plevel_weights <- function(theta_by_m) {
    cs <- b_sleeve[sleeve == "core" & w_idx %in% grid$w_idx]
    ds <- b_sleeve[sleeve == "defense" & w_idx %in% grid$w_idx]
    cs[, w := theta_by_m[as.character(w_idx)] / .N, by = w_idx]
    ds[, w := (1 - theta_by_m[as.character(w_idx)]) / .N, by = w_idx]
    ww <- rbindlist(list(cs[, .(w_idx, Ticker, w)], ds[, .(w_idx, Ticker, w)]))
    ww[, .(w = sum(w)), by = .(w_idx, Ticker)]
  }
  b_rets <- unique(rbindlist(list(
    b_sleeve[w_idx %in% grid$w_idx, .(w_idx, Ticker, Ret_1m)],
    b_score[w_idx %in% grid$w_idx, .(w_idx, Ticker, Ret_1m)])))
  trials <- list(
    B01 = list(kind="score", theta=0.35), B02 = list(kind="score", theta=0.50),
    B03 = list(kind="score", theta=0.65), B04 = list(kind="score", theta=0.80),
    B05 = list(kind="score", theta=1.00),
    B06 = list(kind="pfix", theta=0.50), B07 = list(kind="pfix", theta=0.65),
    B08 = list(kind="pfix", theta=0.80),
    B09 = list(kind="pdyn", est="iv"), B10 = list(kind="pdyn", est="idv"),
    B11 = list(kind="pdyn", est="minvar"))
  tr <- trials[[method_id]]
  if (tr$kind == "score") {
    ss <- b_score[trial == method_id & w_idx %in% grid$w_idx]
    ss[, w := 1 / .N, by = w_idx]
    weights_dt <- ss[, .(w_idx, Ticker, w)]
    rets_dt <- ss[, .(w_idx, Ticker, Ret_1m)]
  } else {
    th <- if (tr$kind == "pfix") setNames(rep(tr$theta, nrow(grid)), as.character(grid$w_idx))
          else setNames(vapply(grid$w_idx, theta_hist, numeric(1), kind = tr$est),
                        as.character(grid$w_idx))
    weights_dt <- plevel_weights(th)
    rets_dt <- b_rets[paste(w_idx, Ticker) %in% weights_dt[, paste(w_idx, Ticker)]]
  }
  m <- run_trial_portfolio(weights_dt, rets_dt, grid, bench_dt)
  row <- summarise_trial(m, grid, sprintf("B_%s", method_id), "B",
                         weighting_method = method_id)
  list(m = m, row = row)
}

compare_trial <- function(tag, stored_row, rr, stored_series) {
  num_cols <- c("full_net_sr","full_cagr","full_mdd","full_calmar","full_ir",
                "full_port_t_nw3","oneway_to_ann","cost_ann_bps",
                "is_net_sr","is_cagr","is_mdd","is_port_t_nw3",
                "oos_net_sr","oos_cagr","oos_mdd","p2017_net_sr")
  diffs <- vapply(num_cols, function(cn) {
    a <- as.numeric(stored_row[[cn]]); b <- as.numeric(rr$row[[cn]])
    if (is.na(a) && is.na(b)) 0 else abs(a - b)
  }, numeric(1))
  mx <- max(diffs)
  chk(sprintf("REPRO_%s_summary_cols", tag), mx < TOL,
      sprintf("(max|diff| over %d metric cols = %.3e, tol %.0e)", length(num_cols), mx, TOL))
  sm <- max(abs(stored_series$ret_net - rr$m$ret_net))
  chk(sprintf("REPRO_%s_ret_net_series", tag), sm < TOL,
      sprintf("(n=%d months, max|diff|=%.3e)", nrow(stored_series), sm))
  cm <- max(abs(stored_series$cost - rr$m$cost))
  chk(sprintf("REPRO_%s_cost_series", tag), cm < TOL, sprintf("(max|diff|=%.3e)", cm))
}

do_one <- function(trow, tag) {
  sub <- trow$substrate; mid <- trow$method_id
  ser <- readRDS(file.path(INT, sprintf("series_%s.rds", sub)))
  stored_m <- ser[[trow$trial_id]]
  rr <- if (sub == "B") rerun_b(mid) else rerun_within(sub, mid)
  compare_trial(tag, trow, rr, stored_m)
}

do_one(best, sprintf("best_%s", best$trial_id))
do_one(rnd,  sprintf("random_%s", rnd$trial_id))

# ---- (b) cost proportionality across actual trials --------------------------
# engine identity: cost_ann_bps = mean(traded)*0.0015*12*1e4 and
# oneway_to_ann = mean(traded/2)*12  =>  cost_ann_bps = oneway_to_ann * 30
imp <- res[, max(abs(cost_ann_bps - oneway_to_ann * 2 * 15))]
chk("COST_identity_all_trials", imp < 1e-6,
    sprintf("(all %d trials: max|cost_ann_bps - oneway_to_ann*30| = %.3e bps)", nrow(res), imp))
# discriminator: lowest-TO vs highest-TO within each substrate, ratio match
for (s in unique(res$substrate)) {
  rs <- res[substrate == s][order(oneway_to_ann)]
  lo <- rs[1]; hi <- rs[.N]
  r_to <- hi$oneway_to_ann / lo$oneway_to_ann
  r_c  <- hi$cost_ann_bps / lo$cost_ann_bps
  chk(sprintf("COST_ratio_tracks_turnover_%s", s),
      isTRUE(all.equal(r_to, r_c, tolerance = 1e-9)),
      sprintf("(TO %s=%.2fx vs %s=%.2fx; turnover ratio %.4f vs cost ratio %.4f; flat model => 1.0)",
              lo$method_id, lo$oneway_to_ann, hi$method_id, hi$oneway_to_ann, r_to, r_c))
}

cat("\n[(c) build_bt_result obligation] NOT executed at this stage (screening tier).\n")
cat("    Follow-up obligation: full build_bt_result 10-component for IS-selected\n")
cat("    finalists (max 3) REQUIRED before any graduation claim (prereg evaluation.engine.stats).\n")

cat("\n=== RERUN VERIFY SUMMARY ===\n")
if (length(fails) == 0) cat("ALL CHECKS PASS\n") else
  cat(sprintf("FAILURES (%d): %s\n", length(fails), paste(fails, collapse = ", ")))
