# =============================================================================
# trackw_engine.R — Track W (Cycle 1b) weighting-methodology measurement engine
#   Prereg: TRACKW_WEIGHTING_PREREG_v1 (prereg_weighting.json, FROZEN 2026-06-11)
#
# ENGINE PROTOCOL NOTE (honest deviation record, not silently absorbed):
#   Prereg evaluation.engine names run_monthly_simulation as simulation engine.
#   run_monthly_simulation's internal weight dispatch CANNOT express 17/22
#   registered within-sleeve methods without modifying 02_Infrastructure
#   (forbidden by code_change_allowlist):
#     - hardcoded lookback cap .lb_n=150d for hrp < registered 756d anchor window
#     - rank-tilt lambda parametrization (production linear_tilt_qd) absent
#     - W09/HRP-grid/B06-B11 not in dispatch
#   To keep ALL 77 trials on ONE identical engine (prereg comparability rule:
#   "all methods incl. EW evaluated on IDENTICAL rebalance months"), every trial
#   runs on the contract-blessed monthly pattern:
#     PerformanceAnalytics::Return.portfolio (monthly weights @ w_idx,
#     forward returns @ r_idx — b1_step3 precedent, NO hand-rolled NAV)
#     + per-name |dW| delta cost (= v2.4_delta semantics in weight space;
#       same convention as contracts/canonical_screen_bt.R, drift-aware via
#       BOP/EOP weights so netting matches harness v2.4 delta charging)
#     + contracts build_benchmark_compare() for PORT_t NW lag-3 (forge-identical fn)
#   metric_type = "canonical_screen" (enum-compliant; the weighting method is
#   carried in a SEPARATE weighting_method column + metric_type_note — label
#   schema corrected 2026-06-12 per Q-Lead approval, adversarial-verifier
#   finding: 'canonical_screen_weighted' was outside the enum
#   {canonical_screen, backtested, estimated, proxy}. Numbers unchanged.
#   NOT forge build_bt_result "backtested").
#
# Reuse (verbatim, no infra edits):
#   - backtest_harness.R: .build_ret_matrix / .get_cor_cov / .gerber_cor /
#     .rmt_denoise / .ledoit_wolf_shrink / .hrp_bisect / .cluster_var /
#     calc_ivol_weights / calc_minvar_weights / calc_riskparity_weights
#   - contracts/backtest_result_contract.R: build_benchmark_compare / .nw_t_mean
#   - contracts/essence_score.R: .essence_dsr (BLdP 2014)
#   - production linear_tilt_qd / normalize_long_only copied VERBATIM from
#     05_Production/2.Factor_Model/2-1.STR_1715_.../01_reproducible_code/run_all.R
#     lines 137-169 (read-only copy; production file untouched)
# NEW implementations (prereg code_change_allowlist item 2 only):
#   EWMA(0.94) covariance / HERC allocation / cluster-IV allocation /
#   vol-scaled EW / 2-sleeve closed-form allocators (B09-B11, in run_b.R)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TRACKW_DIR   <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1b_trackW")
INT_DIR      <- file.path(TRACKW_DIR, "intermediate")
dir.create(INT_DIR, showWarnings = FALSE, recursive = TRUE)

COMMISSION <- 0.0015   # 15bps one-way per traded leg (v2.4-delta-equivalent)

# ── contracts (build_benchmark_compare + .nw_t_mean) ─────────────────────────
suppressMessages(source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R")))
suppressMessages(source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/essence_score.R")))

# ── harness cov/weight functions ─────────────────────────────────────────────
# Sourcing the full harness pulls heavy deps + Rcpp compiles; we only need the
# pure weight/cov helpers. They are self-contained — extract by sourcing the
# harness is preferred but harness requires config.R(PROJECT_ROOT)+QT_to_xts.
# config.R is cheap; source both for verbatim reuse.
if (!exists("PROJECT_ROOT_CONFIG_LOADED")) {
  source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
  PROJECT_ROOT_CONFIG_LOADED <- TRUE
}
suppressMessages(source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R")))

`%||%` <- function(a, b) if (is.null(a)) b else a

# ── production tilt functions (VERBATIM copy — STR_1715 run_all.R L137-169) ──
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) {
    n <- length(w)
    return(rep(target_sum / n, n))
  }
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) {
      w <- w * (target_sum / sum(w)); break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}

linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# ── NEW: EWMA(0.94) covariance (RiskMetrics, zero-mean convention) ───────────
.ewma_cov <- function(ret_mat, lambda = 0.94) {
  n <- nrow(ret_mat)
  wts <- lambda^((n - 1):0)
  wts <- wts / sum(wts)
  S <- crossprod(ret_mat * sqrt(wts))   # sum_k w_k r_k r_k'  (no demean — RiskMetrics)
  S <- (S + t(S)) / 2
  colnames(S) <- rownames(S) <- colnames(ret_mat)
  S
}

# ── NEW: HERC-style full-dendrogram allocation (corrects bisection count-split bias)
.herc_weights <- function(cov_mat, hc) {
  n <- ncol(cov_mat)
  w <- rep(NA_real_, n)
  members <- function(node) {
    if (node < 0) return(-node)
    c(members(hc$merge[node, 1]), members(hc$merge[node, 2]))
  }
  rec <- function(node, mult) {
    if (node < 0) { w[-node] <<- mult; return(invisible(NULL)) }
    l <- hc$merge[node, 1]; r <- hc$merge[node, 2]
    ml <- members(l); mr <- members(r)
    vl <- .cluster_var(cov_mat, ml); vr <- .cluster_var(cov_mat, mr)
    a <- if (is.finite(vl) && is.finite(vr) && (vl + vr) > 0) 1 - vl / (vl + vr) else 0.5
    rec(l, mult * a); rec(r, mult * (1 - a))
  }
  rec(nrow(hc$merge), 1.0)
  w[!is.finite(w)] <- 0
  w
}

# ── NEW: cluster-level inverse-variance (k = round(sqrt(N)) heuristic, doc'd) ─
.cluster_iv_weights <- function(cov_mat, hc) {
  n <- ncol(cov_mat)
  k <- max(2L, min(n - 1L, round(sqrt(n))))
  cl <- cutree(hc, k = k)
  w <- numeric(n)
  ucl <- sort(unique(cl))
  cvars <- vapply(ucl, function(c) .cluster_var(cov_mat, which(cl == c)), numeric(1))
  cvars[!is.finite(cvars) | cvars <= 0] <- max(cvars[is.finite(cvars) & cvars > 0], 1e-8)
  Wc <- (1 / cvars) / sum(1 / cvars)
  for (j in seq_along(ucl)) {
    idx <- which(cl == ucl[j])
    dv <- diag(cov_mat)[idx]; dv[!is.finite(dv) | dv <= 0] <- max(dv[is.finite(dv) & dv > 0], 1e-8)
    iv <- (1 / dv) / sum(1 / dv)
    w[idx] <- Wc[j] * iv
  }
  w
}

# ── HRP grid weight fn (anchor + one-axis variants; mirrors calc_hrp_weights
#    structure incl. dropped-ticker EW-share map-back and max_w=0.15 cap) ─────
trackw_hrp_weights <- function(tickers, ret_dt, n_days = 756L,
                               cov_method = "sample", linkage = "single",
                               allocation = "bisection", max_w = 0.15) {
  ew <- setNames(rep(1 / length(tickers), length(tickers)), tickers)
  ret_mat <- .build_ret_matrix(tickers, ret_dt, n_days)
  if (is.null(ret_mat) || ncol(ret_mat) < 3) return(ew)
  survived <- colnames(ret_mat)
  dropped  <- setdiff(tickers, survived)

  cc <- tryCatch({
    if (cov_method %in% c("sample", "ledoit_wolf", "gerber_rmt")) {
      .get_cor_cov(ret_mat, cov_method)
    } else if (cov_method == "gerber") {
      cm <- .gerber_cor(ret_mat)
      sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
      list(cor = cm, cov = cm * outer(sds, sds))
    } else if (cov_method == "rmt") {
      q <- nrow(ret_mat) / ncol(ret_mat)
      cm0 <- cor(ret_mat, use = "pairwise.complete.obs"); cm0[is.na(cm0)] <- 0
      cm <- .rmt_denoise(cm0, q)
      sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
      list(cor = cm, cov = cm * outer(sds, sds))
    } else if (cov_method == "ewma094") {
      cv <- .ewma_cov(ret_mat, 0.94)
      list(cor = suppressWarnings(cov2cor(cv)), cov = cv)
    } else stop(sprintf("unknown cov_method %s", cov_method))
  }, error = function(e) .get_cor_cov(ret_mat, "sample"))

  cor_mat <- cc$cor; cov_mat <- cc$cov
  cor_mat[!is.finite(cor_mat)] <- 0; diag(cor_mat) <- 1
  cov_mat[!is.finite(cov_mat)] <- 0

  d <- 0.5 * (1 - cor_mat); d[d < 0] <- 0
  hcl <- tryCatch(hclust(as.dist(sqrt(d)), method = linkage),
                  error = function(e) NULL)
  if (is.null(hcl)) return(ew)

  w_sub <- tryCatch({
    ws <- switch(allocation,
      bisection  = .hrp_bisect(cov_mat, hcl$order),
      herc       = .herc_weights(cov_mat, hcl),
      cluster_iv = .cluster_iv_weights(cov_mat, hcl),
      stop("unknown allocation"))
    ws / sum(ws)
  }, error = function(e) rep(1 / length(survived), length(survived)))
  names(w_sub) <- survived

  # map back (verbatim calc_hrp_weights convention)
  w_full <- rep(0, length(tickers)); names(w_full) <- tickers
  if (length(dropped) > 0) {
    for (tk in dropped) w_full[tk] <- 1 / length(tickers)
    hrp_scale <- 1 - sum(w_full)
    for (tk in survived) w_full[tk] <- w_sub[tk] * hrp_scale
  } else {
    w_full[survived] <- w_sub[survived]
  }
  w_full <- w_full / sum(w_full)
  if (any(w_full > max_w)) { w_full <- pmin(w_full, max_w); w_full <- w_full / sum(w_full) }
  w_full
}

# ── NEW: vol-scaled EW (W09, prereg definition) ──────────────────────────────
calc_volscaled_ew <- function(tickers, ret_dt, n_days = 252L) {
  sub <- ret_dt[Ticker %in% tickers & !is.na(Ret)]
  sig <- sub[, .(sigma = { v <- tail(Ret, n_days); if (length(v) >= 30) sd(v) else NA_real_ }),
             by = Ticker]
  s <- setNames(sig$sigma, sig$Ticker)[tickers]
  med <- median(s, na.rm = TRUE)
  if (!is.finite(med) || med <= 0) return(setNames(rep(1 / length(tickers), length(tickers)), tickers))
  s[is.na(s) | s <= 0] <- med
  scal <- pmin(pmax(med / s, 0.5), 1.5)
  w <- scal / length(tickers)
  w <- w / sum(w)
  setNames(w, tickers)
}

# ── within-sleeve method dispatch ────────────────────────────────────────────
# spec: list(id, kind, ...params)
trackw_method_specs <- function() {
  list(
    list(id="W01", label="EW (baseline)",            kind="equal"),
    list(id="W02", label="score-tilt lambda=0.5",    kind="tilt", lambda=0.5),
    list(id="W03", label="score-tilt lambda=1.0",    kind="tilt", lambda=1.0),
    list(id="W04", label="score-tilt lambda=1.5 (prod Iter31)", kind="tilt", lambda=1.5),
    list(id="W05", label="score-tilt lambda=2.0",    kind="tilt", lambda=2.0),
    list(id="W06", label="inverse-vol (60d)",        kind="ivol"),
    list(id="W07", label="ERC riskparity (120d LW)", kind="riskparity"),
    list(id="W08", label="min-var (120d LW)",        kind="minvar"),
    list(id="W09", label="vol-scaled EW (252d)",     kind="volscaled"),
    list(id="H00", label="HRP anchor LdP2016 sample/single/bisect/756d", kind="hrp", cov="sample",     linkage="single",  alloc="bisection", n_days=756L),
    list(id="H01", label="HRP LW-shrink cov",        kind="hrp", cov="ledoit_wolf", linkage="single",  alloc="bisection", n_days=756L),
    list(id="H02", label="HRP Gerber cov",           kind="hrp", cov="gerber",      linkage="single",  alloc="bisection", n_days=756L),
    list(id="H03", label="HRP RMT-denoise cov",      kind="hrp", cov="rmt",         linkage="single",  alloc="bisection", n_days=756L),
    list(id="H04", label="HRP Gerber+RMT cov",       kind="hrp", cov="gerber_rmt",  linkage="single",  alloc="bisection", n_days=756L),
    list(id="H05", label="HRP EWMA0.94 cov",         kind="hrp", cov="ewma094",     linkage="single",  alloc="bisection", n_days=756L),
    list(id="H06", label="HRP average linkage",      kind="hrp", cov="sample",      linkage="average", alloc="bisection", n_days=756L),
    list(id="H07", label="HRP ward.D2 linkage",      kind="hrp", cov="sample",      linkage="ward.D2", alloc="bisection", n_days=756L),
    list(id="H08", label="HRP complete linkage",     kind="hrp", cov="sample",      linkage="complete",alloc="bisection", n_days=756L),
    list(id="H09", label="HRP HERC allocation",      kind="hrp", cov="sample",      linkage="single",  alloc="herc",      n_days=756L),
    list(id="H10", label="HRP cluster-IV allocation",kind="hrp", cov="sample",      linkage="single",  alloc="cluster_iv",n_days=756L),
    list(id="H11", label="HRP 12m (252d) window",    kind="hrp", cov="sample",      linkage="single",  alloc="bisection", n_days=252L),
    list(id="H12", label="HRP 24m (504d) window",    kind="hrp", cov="sample",      linkage="single",  alloc="bisection", n_days=504L)
  )
}

compute_month_weights <- function(spec, tickers, scores, ret_slice) {
  n <- length(tickers)
  w <- switch(spec$kind,
    equal     = setNames(rep(1 / n, n), tickers),
    tilt      = { a <- setNames(scores, tickers)
                  wv <- linear_tilt_qd(a, lambda = spec$lambda, lb = 0, ub = 0.20)
                  setNames(wv, tickers) },
    ivol      = setNames(calc_ivol_weights(tickers, ret_slice), tickers),
    # NOTE: calc_riskparity_weights returns weights in .build_ret_matrix dcast
    # column order (sorted tickers), unnamed. Harness dispatch names them by
    # score-order `selected` (latent misalignment). Here: call with SORTED
    # tickers and map back by name — correct alignment, EW fallback on drops
    # (harness-identical fallback behavior).
    riskparity= { tks <- sort(tickers)
                  wv <- calc_riskparity_weights(tks, ret_slice)
                  if (length(wv) == length(tks)) setNames(wv, tks)[tickers]
                  else setNames(rep(1/n, n), tickers) },
    minvar    = setNames(calc_minvar_weights(tickers, ret_slice), tickers),
    volscaled = calc_volscaled_ew(tickers, ret_slice),
    hrp       = setNames(trackw_hrp_weights(tickers, ret_slice, n_days = spec$n_days,
                                            cov_method = spec$cov, linkage = spec$linkage,
                                            allocation = spec$alloc), tickers),
    stop("unknown kind"))
  if (length(w) != n || any(!is.finite(w)) || abs(sum(w) - 1) > 1e-6) {
    w <- setNames(rep(1 / n, n), tickers)   # guard (harness convention)
  }
  w
}

# ── trial runner ─────────────────────────────────────────────────────────────
# weights_dt: data.table(w_idx Date, Ticker, w)  — invested months only
# month_grid: data.table(w_idx, r_idx) FULL grid incl. cash months
# rets_dt:    data.table(w_idx, Ticker, Ret_1m)  forward returns of held names
# bench_dt:   data.table(r_idx, bm_ret) monthly benchmark
run_trial_portfolio <- function(weights_dt, rets_dt, month_grid, bench_dt) {
  stopifnot(all(c("w_idx","Ticker","w") %in% names(weights_dt)))
  # R matrix: rows r_idx, cols tickers (+CASH)
  tickers_all <- sort(unique(weights_dt$Ticker))
  rr <- merge(month_grid, rets_dt, by = "w_idx", all.x = TRUE)
  Rdt <- dcast(rr[!is.na(Ticker)], r_idx ~ Ticker, value.var = "Ret_1m")
  # ensure every grid month present (cash months may have no tickers)
  Rdt <- merge(month_grid[, .(r_idx)], Rdt, by = "r_idx", all.x = TRUE)
  for (cn in setdiff(tickers_all, names(Rdt))) Rdt[, (cn) := NA_real_]
  setcolorder(Rdt, c("r_idx", tickers_all))
  Rmat <- as.matrix(Rdt[, -1, with = FALSE]); Rmat[is.na(Rmat)] <- 0
  Rxts <- xts(cbind(Rmat, CASH = 0), order.by = Rdt$r_idx)

  Wdt <- dcast(weights_dt, w_idx ~ Ticker, value.var = "w", fill = 0)
  Wdt <- merge(month_grid[, .(w_idx)], Wdt, by = "w_idx", all.x = TRUE)
  for (cn in setdiff(tickers_all, names(Wdt))) Wdt[, (cn) := 0]
  setcolorder(Wdt, c("w_idx", tickers_all))
  Wmat <- as.matrix(Wdt[, -1, with = FALSE]); Wmat[is.na(Wmat)] <- 0
  cash_w <- pmax(0, 1 - rowSums(Wmat))
  Wxts <- xts(cbind(Wmat, CASH = cash_w), order.by = Wdt$w_idx)

  pf <- Return.portfolio(Rxts, weights = Wxts, verbose = TRUE)
  ret_gross <- pf$returns
  bop <- pf$BOP.Weight; eop <- pf$EOP.Weight
  stock_cols <- setdiff(colnames(bop), "CASH")
  nT <- nrow(ret_gross)
  traded <- numeric(nT)
  traded[1] <- sum(abs(as.numeric(bop[1, stock_cols])))
  if (nT > 1) for (i in 2:nT) {
    traded[i] <- sum(abs(as.numeric(bop[i, stock_cols]) - as.numeric(eop[i - 1, stock_cols])))
  }
  cost <- traded * COMMISSION
  out <- data.table(r_idx = as.Date(index(ret_gross)),
                    ret_gross = as.numeric(ret_gross),
                    traded = traded, cost = cost)
  out[, ret_net := ret_gross - cost]
  out <- merge(out, bench_dt, by = "r_idx", all.x = TRUE)
  out
}

# ── window metrics ───────────────────────────────────────────────────────────
.win_metrics <- function(m, label) {
  if (nrow(m) < 12 || all(is.na(m$ret_net))) {
    return(list(n = nrow(m), net_sr = NA_real_, cagr = NA_real_, mdd = NA_real_,
                calmar = NA_real_, ir = NA_real_))
  }
  x <- xts(m$ret_net, order.by = m$r_idx)
  sr  <- mean(m$ret_net) / sd(m$ret_net) * sqrt(12)          # house Sharpe0_m convention
  cag <- as.numeric(Return.annualized(x, scale = 12, geometric = TRUE))
  mdd <- as.numeric(maxDrawdown(x))
  act <- m$ret_net - m$bm_ret
  ir  <- if (sd(act, na.rm = TRUE) > 0) mean(act, na.rm = TRUE) / sd(act, na.rm = TRUE) * sqrt(12) else NA_real_
  list(n = nrow(m), net_sr = sr, cagr = cag, mdd = mdd,
       calmar = if (mdd > 0) cag / mdd else NA_real_, ir = ir)
}

.port_t <- function(m, run_id, sid) {
  if (nrow(m) < 12) return(c(t = NA_real_, p = NA_real_))
  prt <- data.table(date = m$r_idx, ret_net = m$ret_net, frequency = "monthly")
  bmt <- data.table(date = m$r_idx, benchmark_ret = m$bm_ret, benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(prt, bmt, run_id = run_id, strategy_id = sid,
                                annualization_factor = 12)
  tv <- bc[metric_name == "Portfolio_Alpha_t_NW_lag3", active_value]
  pv <- bc[metric_name == "Portfolio_Alpha_t_pvalue", active_value]
  c(t = if (length(tv)) as.numeric(tv[1]) else NA_real_,
    p = if (length(pv)) as.numeric(pv[1]) else NA_real_)
}

# windows: signal-month basis (Date label of formation month)
#   IS: formation <= 2018-12 | OOS: formation >= 2019-01 | 2017+: formation >= 2017-01
# m carries r_idx (= month_end(formation+1)); formation month-end = w_idx.
summarise_trial <- function(m, month_grid, trial_id, substrate, n_trials_cum = 86,
                            weighting_method = NA_character_) {
  m <- merge(m, month_grid, by = "r_idx", all.x = TRUE)
  is_m   <- m[w_idx <= as.Date("2018-12-31")]
  oos_m  <- m[w_idx >= as.Date("2019-01-01")]
  p17_m  <- m[w_idx >= as.Date("2017-01-01")]
  f  <- .win_metrics(m, "full"); i <- .win_metrics(is_m, "is")
  o  <- .win_metrics(oos_m, "oos"); p7 <- .win_metrics(p17_m, "2017p")
  ptf <- .port_t(m, trial_id, substrate)
  pti <- .port_t(is_m, paste0(trial_id, "_is"), substrate)
  sk <- tryCatch(as.numeric(PerformanceAnalytics::skewness(m$ret_net)), error = function(e) 0)
  ku <- tryCatch(as.numeric(PerformanceAnalytics::kurtosis(m$ret_net, method = "moment")), error = function(e) 3)
  dsr <- .essence_dsr(f$net_sr, f$n, n_trials_cum, skew = sk, kurt = ku, A = 12)
  data.table(
    trial_id = trial_id, substrate = substrate,
    n_months = f$n, first_r = min(m$r_idx), last_r = max(m$r_idx),
    full_net_sr = f$net_sr, full_cagr = f$cagr, full_mdd = f$mdd, full_calmar = f$calmar,
    full_ir = f$ir, full_port_t_nw3 = ptf["t"], full_port_t_p = ptf["p"],
    oneway_to_ann = mean(m$traded / 2) * 12, cost_ann_bps = mean(m$cost) * 12 * 1e4,
    is_n = i$n, is_net_sr = i$net_sr, is_cagr = i$cagr, is_mdd = i$mdd, is_port_t_nw3 = pti["t"],
    oos_n = o$n, oos_net_sr = o$net_sr, oos_cagr = o$cagr, oos_mdd = o$mdd,
    p2017_net_sr = p7$net_sr, p2017_cagr = p7$cagr, p2017_mdd = p7$mdd,
    dsr_n_trials86 = dsr, skew_m = sk, kurt_m = ku,
    weighting_method = weighting_method,
    metric_type = "canonical_screen",
    metric_type_note = paste(
      "canonical_screen engine generalized to externally supplied weights",
      "(see weighting_method column): Return.portfolio monthly + per-name |dW|",
      "15bps delta cost + build_benchmark_compare PORT_t NW lag-3.",
      "NOT forge build_bt_result 'backtested'.")
  )
}

cat("[trackw_engine] Loaded.\n")
