# =============================================================================
# FQ-058 run_03: 실측 — Return.portfolio net-active + structural DD + paired NW-t + DSR
#   PRIMARY 판정축: MinCDaR vs MinVar (measure swap). 참조: vs EW, vs MVO.
#   비용 15bps delta 과금 (|BOP - EOP_lag|). 벤치 cap-w member fresh.
# Output: fq058_series.parquet + fq058_metrics.json
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/method_frontier/fq058_cdar_construction/fq058_lib.R")

OUT <- OUT_F58; COST <- 0.0015
ARMS <- c("EW", "MVO", "MinVar", "MinCDaR", "MinCVaR")

P <- load_panels_f58()
W <- as.data.table(read_parquet(file.path(OUT, "fq058_weights.parquet")))
factors <- sort(unique(W$factor))
reb_yms <- sort(unique(W$ym))
span_yms <- P$yms[P$yms >= min(reb_yms)]

Mw <- dcast(P$mr[ym %in% span_yms], ym ~ Ticker, value.var = "ret_m")
Rmat <- as.matrix(Mw[, -1, drop = FALSE]); na_tot <- sum(is.na(Rmat)); Rmat[is.na(Rmat)] <- 0
R_all <- xts(Rmat, order.by = ym2date_f(Mw$ym))

# ---- bench: cap-w member fresh ----------------------------------------------
bsnap <- P$snap[ym %in% reb_yms & member == 1L & !is.na(size) & size > 0]
bsnap <- bsnap[Ticker %in% colnames(R_all)]; bsnap[, wb := size / sum(size), by = ym]
Bw <- dcast(bsnap, ym ~ Ticker, value.var = "wb", fill = 0)
Bx <- xts(as.matrix(Bw[, -1, drop = FALSE]), order.by = ym2date_f(Bw$ym))
bench_pf <- Return.portfolio(R_all[, colnames(Bx), drop = FALSE], weights = Bx, verbose = FALSE)
bench_dt <- data.table(date = index(bench_pf), benchmark_ret = as.numeric(bench_pf))

build_port <- function(f, arm_) {
  wsub <- W[factor == f & arm == arm_]
  tks <- sort(unique(wsub$Ticker))
  Wmw <- dcast(wsub, ym ~ Ticker, value.var = "w", fill = 0)
  Wx <- xts(as.matrix(Wmw[, -1, drop = FALSE])[, tks, drop = FALSE], order.by = ym2date_f(Wmw$ym))
  Rx <- R_all[, tks, drop = FALSE]
  pf <- Return.portfolio(Rx, weights = Wx, verbose = TRUE)
  ret <- pf$returns; bop <- as.matrix(pf$BOP.Weight); eop <- as.matrix(pf$EOP.Weight)
  n <- nrow(bop); eop_lag <- rbind(matrix(0, 1, ncol(eop)), eop[-n, , drop = FALSE])
  to <- rowSums(abs(bop - eop_lag)); cost <- COST * to
  data.table(date = index(ret), ret_net = as.numeric(ret) - cost, to_oneway = to, cost = cost)
}

measure_cell <- function(f, arm) {
  pd <- build_port(f, arm)
  m <- merge(pd, bench_dt, by = "date", all.x = TRUE); stopifnot(!anyNA(m$benchmark_ret))
  m[, active := ret_net - benchmark_ret]
  net_x <- xts(m$ret_net, order.by = m$date)
  pt <- nw_t_f(m$active)
  cagr <- as.numeric(Return.annualized(net_x, scale = 12, geometric = TRUE))
  sdd <- structural_dd_f(net_x)
  m[, yr := year(date)]; yr_to <- m[, .(to = sum(to_oneway), nn = .N), by = yr][nn == 12]
  list(factor = f, arm = arm, n_months = nrow(m),
       port_t_nw_lag3 = round(pt$t, 4), mean_active_m = round(pt$mean_m, 6),
       active_sr = round(ann_sr_f(m$active), 4), net_sr = round(ann_sr_f(m$ret_net), 4),
       cagr = round(cagr, 4), mdd = sdd$mdd, calmar = round(cagr / sdd$mdd, 4),
       structural_dd = sdd,
       oos_retention_v2 = oos_v2_f(m$active),
       turnover_oneway_annual = round(mean(yr_to$to), 3),
       turnover_roundtrip_annual = round(mean(yr_to$to) * 2, 3),
       avg_monthly_cost_bps = round(mean(m$cost) * 1e4, 2),
       active_series = m[, .(date, active)], net_series = m[, .(date, ret_net)])
}

# ---- per factor: 5 arms + paired + DSR --------------------------------------
per_factor <- list(); series_out <- list()
for (f in factors) {
  cells <- lapply(ARMS, function(a) measure_cell(f, a)); names(cells) <- ARMS
  # 공통 date 정합
  dates <- cells[["MinVar"]]$active_series$date
  for (a in ARMS) stopifnot(identical(cells[[a]]$active_series$date, dates))
  act <- sapply(ARMS, function(a) cells[[a]]$active_series$active)  # T x 5
  # paired NW-t: treatment - MinVar (measure swap 격리), + vs EW, vs MVO
  paired <- list()
  pair_def <- list(
    MinCDaR_vs_MinVar = c("MinCDaR", "MinVar"),
    MinCVaR_vs_MinVar = c("MinCVaR", "MinVar"),
    MinCDaR_vs_EW     = c("MinCDaR", "EW"),
    MinCDaR_vs_MVO    = c("MinCDaR", "MVO"),
    MinCVaR_vs_EW     = c("MinCVaR", "EW"))
  for (nm in names(pair_def)) {
    a <- pair_def[[nm]][1]; b <- pair_def[[nm]][2]
    d <- act[, a] - act[, b]; tt <- nw_t_f(d)
    paired[[nm]] <- list(diff_def = paste0("active_", a, " - active_", b),
                         mean_diff_m = round(tt$mean_m, 6), nw_t_lag3 = round(tt$t, 4),
                         ann_diff = round(tt$mean_m * 12, 4), n = tt$n)
  }
  # DSR (sweep형: n_trials = 5 arms). Bailey-LdP sr0, best arm 활성수익.
  srs <- sapply(ARMS, function(a) { x <- act[, a]; mean(x) / sd(x) })
  gamma_e <- 0.5772156649; Ntr <- length(ARMS)
  sr_star <- sd(srs) * ((1 - gamma_e) * qnorm(1 - 1 / Ntr) + gamma_e * qnorm(1 - 1 / (Ntr * exp(1))))
  best_arm <- ARMS[which.max(srs)]
  dsr_best <- psr_f(act[, best_arm], sr0 = sr_star)
  # treatment DSR (MinCDaR) 별도
  dsr_cdar <- psr_f(act[, "MinCDaR"], sr0 = sr_star)

  arms_summary <- lapply(ARMS, function(a) cells[[a]][setdiff(names(cells[[a]]), c("active_series", "net_series"))])
  names(arms_summary) <- ARMS
  per_factor[[f]] <- list(arms = arms_summary, paired = paired,
    dsr = list(note = "sweep형 5-arm — DSR HARD>=0.5 게이트 대상", n_trials = Ntr,
               sr_star_monthly = round(sr_star, 4), best_arm = best_arm,
               dsr_best_arm = round(dsr_best, 4), dsr_MinCDaR = round(dsr_cdar, 4)))
  for (a in ARMS) {
    s <- copy(cells[[a]]$net_series)[, `:=`(factor = f, arm = a)]
    s2 <- merge(s, cells[[a]]$active_series, by = "date")
    series_out[[length(series_out) + 1L]] <- s2
  }
}

SER <- rbindlist(series_out)
write_parquet(SER, file.path(OUT, "fq058_series.parquet"))
metrics <- list(round_tag = ROUND_TAG_F58, pin_consumed = PIN_F58,
                measured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                metric_type = "canonical_screen (construction_ab_diagnostic)",
                na_to_zero_cells = na_tot,
                bench = "cap-w K200|KQ150 fresh (Size, Return.portfolio monthly)",
                primary_axis = "MinCDaR vs MinVar (risk measure swap; alpha 미사용 동일 basket)",
                materials = factors, per_factor = per_factor)
write_json(metrics, file.path(OUT, "fq058_metrics.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("[done] run_03 — materials:", paste(factors, collapse = ","), "\n")
for (f in factors) {
  cat(sprintf("\n== %s ==\n", f))
  for (a in ARMS) { x <- per_factor[[f]]$arms[[a]]
    cat(sprintf("  %-8s port_t %6.2f  calmar %6.3f  mdd %5.3f  ep45 %d  underwater_occ %.2f  net_sr %5.2f  TO %.1f\n",
      a, x$port_t_nw_lag3, x$calmar, x$mdd, x$structural_dd$n_episodes_45,
      x$structural_dd$drawdown_occupancy, x$net_sr, x$turnover_oneway_annual)) }
  pp <- per_factor[[f]]$paired$MinCDaR_vs_MinVar
  cat(sprintf("  PRIMARY MinCDaR-MinVar: ann_diff %+.4f  NW-t %+.2f\n", pp$ann_diff, pp$nw_t_lag3))
}
