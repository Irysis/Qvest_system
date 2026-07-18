# run_01: 측정 — base(mom) vs crash-aware treatment grid. IS-only lambda 선택.
#   canonical_screen_bt cap-w PORT_t 1급 + window-slice IS/OOS + dual-basis(base/selected).
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/method_frontier/wt_d20260718_001_crash_aware_mom/ca_lib.R")

t0 <- Sys.time()
REB_FROM <- 201001L; REB_TO <- 202605L   # signal months (holding t+1 = 201002..202606)
LAMBDAS <- c(0.25, 0.5, 0.75, 1.0)
PENDEFS <- c("composite", AXES_CA)

P <- load_panels_f58()
reb_yms <- P$yms[P$yms >= REB_FROM & P$yms <= REB_TO]
bench_m <- build_bench_m(P)
market_by_ym <- setNames(bench_m$bm_ret, as.character(bench_m$ym))
cat("[panel] reb months:", length(reb_yms), "range", reb_yms[1], "..", reb_yms[length(reb_yms)],
    "| bench_m months:", nrow(bench_m), "\n")

cat("[precompute] building per-month signal store...\n")
store <- precompute_store_ca(P, reb_yms, market_by_ym)
cat("[precompute] store months:", length(store), " elapsed:",
    round(difftime(Sys.time(), t0, units="secs"),1), "s\n")

# IS/OOS split (anchored 65% by month count) — dates
all_dates <- sort(sapply(store, function(s) as.numeric(s$date)))
all_dates <- as.Date(all_dates, origin = "1970-01-01")
n_all <- length(all_dates); is_cut <- all_dates[floor(0.65 * n_all)]
cat("[split] n_months:", n_all, " IS<=", as.character(is_cut),
    " (IS n~", floor(0.65*n_all), ", OOS n~", n_all - floor(0.65*n_all), ")\n")

# ---- BASE: mom_12_1 (dual-basis on) -----------------------------------------
inp_base <- assemble_inputs_ca(store, "none", 0)
size_base <- inp_base$size
res_base <- run_canon(inp_base, top_n = 25L, size_dt = size_base, run_id = "base_mom", diag = TRUE)
base_full <- window_metrics_ca(res_base)
base_is   <- window_metrics_ca(res_base, date_hi = is_cut)
base_oos  <- window_metrics_ca(res_base, date_lo = is_cut + 1)
cat(sprintf("\n[BASE mom_12_1] full PORT_t=%.3f calmar=%.3f MDD=%.3f net_sr=%.3f | IS PORT_t=%.3f calmar=%.3f | OOS PORT_t=%.3f\n",
            base_full$port_t, base_full$calmar, base_full$mdd, base_full$net_sr,
            base_is$port_t, base_is$calmar, base_oos$port_t))
cat(sprintf("  [parity vs FQ-058 mom_12_1: expect cap-w PORT_t~1.34 calmar~0.42 MDD~0.417]\n"))

# ---- GRID: treatment variants (diag off for speed) --------------------------
grid <- list()
for (pd in PENDEFS) for (lam in LAMBDAS) {
  inp <- assemble_inputs_ca(store, pd, lam)
  res <- run_canon(inp, top_n = 25L, size_dt = NULL, run_id = paste0(pd,"_",lam), diag = FALSE)
  fm <- window_metrics_ca(res); im <- window_metrics_ca(res, date_hi = is_cut)
  om <- window_metrics_ca(res, date_lo = is_cut + 1)
  grid[[paste0(pd,"_l",lam)]] <- list(
    penalty_def = pd, lambda = lam,
    full_port_t = fm$port_t, full_calmar = fm$calmar, full_mdd = fm$mdd,
    full_net_sr = fm$net_sr, full_active_sr = fm$active_sr, full_cagr = fm$cagr,
    is_port_t = im$port_t, is_calmar = im$calmar, is_mdd = im$mdd,
    oos_port_t = om$port_t, oos_calmar = om$calmar,
    turnover_annual = round(res$turnover_annual,3))
}
gtab <- rbindlist(lapply(grid, function(g) as.data.table(g[c("penalty_def","lambda",
  "is_port_t","is_calmar","is_mdd","full_port_t","full_calmar","full_mdd","full_net_sr","oos_port_t","turnover_annual")])))
cat("\n=== GRID (IS-selection basis: is_port_t/is_calmar) ===\n"); print(gtab)

# ---- IS-only selection: max IS calmar s.t. IS PORT_t >= 0.85*base IS PORT_t --
guard <- 0.85 * base_is$port_t
elig_sel <- gtab[is_port_t >= guard]
cat(sprintf("\n[selection] guard: IS PORT_t >= 0.85*%.3f = %.3f | %d/%d variants pass guard\n",
            base_is$port_t, guard, nrow(elig_sel), nrow(gtab)))
if (nrow(elig_sel) == 0L) {
  sel_key <- NA_character_; K2_fire <- TRUE
  cat("[selection] K2 FIRE — no lambda satisfies momentum-preservation guard.\n")
} else {
  K2_fire <- FALSE
  elig_sel <- elig_sel[order(-is_calmar)]
  sel_row <- elig_sel[1]
  sel_key <- paste0(sel_row$penalty_def, "_l", sel_row$lambda)
  cat(sprintf("[selection] selected = %s (IS calmar=%.3f IS PORT_t=%.3f)\n",
              sel_key, sel_row$is_calmar, sel_row$is_port_t))
}

# ---- selected variant full dual-basis + structural DD + crisis ---------------
sel_out <- NULL
if (!is.na(sel_key)) {
  sg <- grid[[sel_key]]
  inp_sel <- assemble_inputs_ca(store, sg$penalty_def, sg$lambda)
  res_sel <- run_canon(inp_sel, top_n = 25L, size_dt = inp_sel$size,
                       run_id = paste0("sel_",sel_key), diag = TRUE)
  sel_full <- window_metrics_ca(res_sel)
  sel_is   <- window_metrics_ca(res_sel, date_hi = is_cut)
  sel_oos  <- window_metrics_ca(res_sel, date_lo = is_cut + 1)
  sel_sdd  <- calmar_from_pr(res_sel)
  sel_crisis <- crisis_conditional(res_sel)
  # save selected variant alpha scores (parquet)
  saveRDS(res_sel, file.path(OUT_CA, "res_selected.rds"))
  write_parquet(inp_sel$scores, file.path(OUT_CA, "alpha_scores.parquet"))
  sel_out <- list(key = sel_key, penalty_def = sg$penalty_def, lambda = sg$lambda,
                  full = sel_full, is = sel_is, oos = sel_oos, sdd = sel_sdd,
                  crisis = sel_crisis,
                  diag_ew = res_sel$diag_ew_universe, diag_tier = res_sel$diag_cap_tier)
}

# base structural DD + crisis + dual-basis
base_sdd <- calmar_from_pr(res_base)
base_crisis <- crisis_conditional(res_base)
saveRDS(res_base, file.path(OUT_CA, "res_base.rds"))

# ---- KILL rule evaluation ---------------------------------------------------
kill <- list(K1 = FALSE, K2 = K2_fire, K3 = FALSE, details = list())
if (!is.na(sel_key)) {
  d_calmar <- sel_out$full$calmar - base_full$calmar
  d_port_t <- sel_out$full$port_t - base_full$port_t
  K1 <- (sel_out$full$port_t < base_full$port_t - 0.5) && (d_calmar <= 0)
  sdd_better <- c(
    mdd = sel_out$sdd$mdd < base_sdd$mdd,
    occ = sel_out$sdd$sdd$drawdown_occupancy < base_sdd$sdd$drawdown_occupancy,
    luw = sel_out$sdd$sdd$longest_underwater_months < base_sdd$sdd$longest_underwater_months)
  K3 <- !any(sdd_better)
  kill$K1 <- K1; kill$K3 <- K3
  kill$details <- list(d_calmar = round(d_calmar,4), d_port_t = round(d_port_t,4),
                       sdd_better = as.list(sdd_better))
}
cat(sprintf("\n[KILL] K1=%s K2=%s K3=%s\n", kill$K1, kill$K2, kill$K3))

# ---- persist metrics --------------------------------------------------------
PIN_TAG_CA <- readLines(file.path(OUT_CA, "PIN_TAG.txt"))[1]
metrics <- list(
  task_id = "WT-D20260718_001", pin_tag = PIN_TAG_CA, pin_upstream = PIN_UPSTREAM_CA,
  measured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "canonical_screen (cap-w PORT_t 1급) + dual-basis diag",
  n_months = base_full$n, is_cut = as.character(is_cut),
  base = list(full = base_full, is = base_is, oos = base_oos,
              structural_dd = base_sdd$sdd, calmar = base_sdd$calmar,
              crisis = base_crisis,
              diag_ew = res_base$diag_ew_universe[c("portfolio_alpha_t_nw_lag3","post2017_t_nw_lag3","oos_retention_approx","n_months")],
              diag_tier_wshare = res_base$diag_cap_tier$weight_share_avg,
              diag_tier_contrib = res_base$diag_cap_tier$contrib_gross_annualized),
  grid = grid,
  selection = list(guard = round(guard,4), selected_key = sel_key,
                   n_pass_guard = nrow(elig_sel)),
  selected = sel_out,
  kill = kill)
write_json(metrics, file.path(OUT_CA, "ca_metrics.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
cat("[run_01] metrics written ->", file.path(OUT_CA, "ca_metrics.json"),
    "| total elapsed:", round(difftime(Sys.time(), t0, units="secs"),1), "s\n")
