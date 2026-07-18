# =============================================================================
# WT-D20260718_001 Crash-aware momentum selection — shared library
#   기전: momentum core 알파에 종목-레벨 ex-ante 하방위험 페널티를 횡단면 합성해
#         crash-prone 종목을 SELECTION 단계에서 감점 → structural DD/calmar 개선 검증.
#   측정: canonical_screen_bt (cap-w PORT_t 1급) + dual-basis(EW-uni/cap-tier) + AX-001 v2.
#   PIT: 신호는 month-end t 데이터만(rows <= idx). holding month t+1(forward Ret).
#   Return.portfolio / build_benchmark_compare 표준함수만 — 자체합성 금지.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
  library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)

ROOT_CA <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT_MF  <- file.path(ROOT_CA, "stage_artifacts/method_frontier")   # fq057 panels 소비
OUT_CA  <- file.path(ROOT_CA, "stage_artifacts/WT_D20260718_001")   # 본 WT 산출
PIN_UPSTREAM_CA <- "fq057_20260718_171024"   # 소비 panel vintage (fq057 pin)

# canonical_screen_bt (1급 측정 helper) + contract
source(file.path(ROOT_CA, "02_Infrastructure/contracts/canonical_screen_bt.R"))
# fq058 lib 재사용 (load_panels/elig/signal(mom)/nw_t/ann_sr/oos_v2/structural_dd)
source(file.path(ROOT_CA, "04_Research/method_frontier/fq058_cdar_construction/fq058_lib.R"))

# ---- ym helpers (fq058_lib에 ym_next_f/ym2date_f 존재) ----------------------

# ---- contemporaneous cap-w benchmark monthly series (by ym) -----------------
#   month ym의 실현 cap-w 수익 = Σ_member (size_i/Σsize) * ret_i (월별 리셋).
#   Return.portfolio(monthly reset) 등가. 하방베타 market series + BM_Ret 원천.
build_bench_m <- function(P) {
  bs <- P$snap[member == 1L & !is.na(size) & size > 0, .(ym, Ticker, size)]
  bs <- merge(bs, P$mr[, .(ym, Ticker, ret_m)], by = c("ym","Ticker"))
  bs <- bs[is.finite(ret_m)]
  bs[, wb := size / sum(size), by = ym]
  bench_m <- bs[, .(bm_ret = sum(wb * ret_m)), by = ym][order(ym)]
  bench_m
}

# ---- crash-penalty signals (PIT, z over elig; HIGHER = more crash-prone) -----
#   반환: named vector (elig) — 값이 클수록 crash-prone(페널티 방향). z-score 반환.
#   market_by_ym: named numeric vector (as.character(ym) -> bm_ret) 하방베타용.
z_of_ca <- function(v) {
  v <- as.numeric(v); s <- sd(v, na.rm = TRUE)
  if (!is.finite(s) || s < 1e-12) return(rep(0, length(v)))
  (v - mean(v, na.rm = TRUE)) / s
}

crash_signal_ca <- function(P, t_ym, elig, axis, market_by_ym,
                            win_beta = 36L, win_semi = 24L, win_skew = 36L,
                            win_crash = 12L) {
  idx <- match(t_ym, P$yms)
  M   <- P$mat  # rows = ym, cols = ticker

  if (axis == "downside_beta") {
    rows <- (idx - win_beta + 1L):idx
    yms_w <- P$yms[rows]
    rm <- as.numeric(market_by_ym[as.character(yms_w)])
    down <- which(is.finite(rm) & rm < 0)          # down-market months only
    if (length(down) < 6L) { val <- rep(NA_real_, length(elig)) }
    else {
      rmd <- rm[down]; vmd <- var(rmd)
      sub <- M[rows[down], elig, drop = FALSE]
      # beta_i = cov(r_i, rm | down) / var(rm | down)  (vectorized)
      rmc <- rmd - mean(rmd)
      cov_i <- apply(sub, 2, function(ri) {
        if (sum(is.finite(ri)) < 6L) return(NA_real_)
        rc <- ri - mean(ri, na.rm = TRUE)
        mean(rc * rmc, na.rm = TRUE)
      })
      val <- cov_i / vmd                            # higher down-beta = crash-prone
    }
  } else if (axis == "downside_semivol") {
    rows <- (idx - win_semi + 1L):idx
    sub <- M[rows, elig, drop = FALSE]
    val <- apply(sub, 2, function(ri) {
      ri <- ri[is.finite(ri)]; if (length(ri) < 6L) return(NA_real_)
      neg <- pmin(ri - mean(ri), 0)
      sqrt(mean(neg^2))                             # downside semi-deviation
    })
  } else if (axis == "crash_exposure") {
    rows <- (idx - win_crash + 1L):idx
    sub <- M[rows, elig, drop = FALSE]
    val <- apply(sub, 2, function(ri) {
      ri <- ri[is.finite(ri)]; if (length(ri) < 6L) return(NA_real_)
      -min(ri)                                      # magnitude of worst month (higher=crash-prone)
    })
  } else if (axis == "ncskew") {
    rows <- (idx - win_skew + 1L):idx
    sub <- M[rows, elig, drop = FALSE]
    val <- apply(sub, 2, function(ri) {
      ri <- ri[is.finite(ri)]; n <- length(ri); if (n < 12L) return(NA_real_)
      rc <- ri - mean(ri); s2 <- sum(rc^2); s3 <- sum(rc^3)
      if (s2 <= 0) return(NA_real_)
      -(n * (n-1)^1.5 * s3) / ((n-1) * (n-2) * s2^1.5)  # Chen-Hong-Stein NCSKEW (higher=left-skew=crash)
    })
  } else stop("unknown crash axis: ", axis)

  z <- z_of_ca(val); z[!is.finite(z)] <- 0
  names(z) <- elig; z
}

# composite crash penalty = mean of z-scored axes (equal weight)
crash_penalty_composite <- function(P, t_ym, elig, market_by_ym, axes) {
  Z <- sapply(axes, function(a) crash_signal_ca(P, t_ym, elig, a, market_by_ym))
  if (is.null(dim(Z))) Z <- matrix(Z, ncol = length(axes))
  pen <- rowMeans(Z, na.rm = TRUE); pen[!is.finite(pen)] <- 0
  names(pen) <- elig; pen
}

# ---- build canonical inputs (forward-aligned) for a scoring function ---------
#   score_fun(P, t_ym, elig, market_by_ym) -> named z-vector(elig) (higher=preferred)
#   반환: scores_dt / returns_dt(forward) / bench_dt(forward) / size_dt / liq_dt
build_canon_inputs <- function(P, reb_yms, score_fun, market_by_ym) {
  sc <- list(); rr <- list(); bd <- list(); sz <- list(); lq <- list()
  bench_by_ym <- setNames(market_by_ym, NULL); names(bench_by_ym) <- names(market_by_ym)
  for (t_ym in reb_yms) {
    idx <- match(t_ym, P$yms)
    nxt <- idx + 1L
    if (is.na(nxt) || nxt > length(P$yms)) next
    elig <- elig_at_f(P, t_ym, win = 60L, liq_min = 2e8)
    if (length(elig) < 30L) next
    z <- score_fun(P, t_ym, elig, market_by_ym)
    z <- z[is.finite(z)]; if (length(z) < 25L) next
    dt_sig <- ym2date_f(t_ym)                  # signal date label (holding = t+1)
    fwd <- P$mat[nxt, names(z)]                # forward realized return (month t+1)
    sc[[length(sc)+1L]] <- data.table(Date = dt_sig, Ticker = names(z), score = as.numeric(z))
    rr[[length(rr)+1L]] <- data.table(Date = dt_sig, Ticker = names(z), Ret_1m = as.numeric(fwd))
    # forward bench = month t+1 cap-w benchmark
    bm_fwd <- as.numeric(market_by_ym[as.character(P$yms[nxt])])
    bd[[length(bd)+1L]] <- data.table(Date = dt_sig, BM_Ret = bm_fwd)
    # size (contemporaneous t) for cap-tier; liq (t)
    ssz <- P$snap[ym == t_ym & Ticker %in% names(z), .(Ticker, size)]
    sz[[length(sz)+1L]] <- data.table(Date = dt_sig, Ticker = ssz$Ticker, Size = ssz$size)
    lqm <- P$liq[ym == t_ym & Ticker %in% names(z), .(Ticker, avgtv20)]
    lq[[length(lq)+1L]] <- data.table(Date = dt_sig, Ticker = lqm$Ticker, adv = lqm$avgtv20)
  }
  list(scores = rbindlist(sc), returns = rbindlist(rr), bench = rbindlist(bd),
       size = rbindlist(sz), liq = rbindlist(lq))
}

# ---- precompute per-month store (momentum + penalty z once) -----------------
#   변형(axis/lambda) 간 재계산 회피. returns/bench/size/liq는 변형 무관 공통.
AXES_CA <- c("downside_beta","downside_semivol","crash_exposure","ncskew")
precompute_store_ca <- function(P, reb_yms, market_by_ym) {
  store <- list()
  for (t_ym in reb_yms) {
    idx <- match(t_ym, P$yms); nxt <- idx + 1L
    if (is.na(nxt) || nxt > length(P$yms)) next
    elig <- elig_at_f(P, t_ym, win = 60L, liq_min = 2e8)
    if (length(elig) < 30L) next
    z_mom <- signal_f58(P, t_ym, elig, "mom_12_1")     # base momentum z (fq058 def)
    z_ax <- lapply(AXES_CA, function(a) crash_signal_ca(P, t_ym, elig, a, market_by_ym))
    names(z_ax) <- AXES_CA
    Zm <- do.call(cbind, z_ax)                          # elig x axes
    z_comp <- rowMeans(Zm, na.rm = TRUE); z_comp[!is.finite(z_comp)] <- 0
    keep <- intersect(elig, colnames(P$mat))
    fwd <- P$mat[nxt, elig]
    dt_sig <- ym2date_f(t_ym)
    ssz <- P$snap[ym == t_ym & Ticker %in% elig, .(Ticker, size)]
    lqm <- P$liq[ym == t_ym & Ticker %in% elig, .(Ticker, avgtv20)]
    store[[as.character(t_ym)]] <- list(
      t_ym = t_ym, date = dt_sig, elig = elig,
      z_mom = z_mom, z_axis = z_ax, z_comp = setNames(z_comp, elig),
      fwd = setNames(as.numeric(fwd), elig),
      bm_fwd = as.numeric(market_by_ym[as.character(P$yms[nxt])]),
      size = ssz, liq = lqm)
  }
  store
}

# assemble canonical inputs for a given penalty definition + lambda
#   penalty_def: "none" | "composite" | one of AXES_CA
assemble_inputs_ca <- function(store, penalty_def = "none", lambda = 0) {
  sc <- list(); rr <- list(); bd <- list(); sz <- list(); lq <- list()
  for (nm in names(store)) {
    s <- store[[nm]]; elig <- s$elig
    zpen <- switch(penalty_def,
      none = rep(0, length(elig)),
      composite = s$z_comp[elig],
      s$z_axis[[penalty_def]][elig])
    zpen[!is.finite(zpen)] <- 0
    score <- s$z_mom[elig] - lambda * as.numeric(zpen)
    ok <- is.finite(score) & is.finite(s$fwd[elig])
    if (sum(ok) < 25L) next
    el <- elig[ok]; d <- s$date
    sc[[length(sc)+1L]] <- data.table(Date = d, Ticker = el, score = as.numeric(score[ok]))
    rr[[length(rr)+1L]] <- data.table(Date = d, Ticker = el, Ret_1m = as.numeric(s$fwd[el]))
    bd[[length(bd)+1L]] <- data.table(Date = d, BM_Ret = s$bm_fwd)
    sz[[length(sz)+1L]] <- data.table(Date = d, Ticker = s$size$Ticker, Size = s$size$size)
    lq[[length(lq)+1L]] <- data.table(Date = d, Ticker = s$liq$Ticker, adv = s$liq$avgtv20)
  }
  list(scores = rbindlist(sc), returns = rbindlist(rr), bench = unique(rbindlist(bd)),
       size = rbindlist(sz), liq = rbindlist(lq))
}

# ---- run canonical screen (top-25, 15bps, liq 2e8) --------------------------
run_canon <- function(inp, top_n = 25L, size_dt = NULL, run_id = "ca", diag = TRUE) {
  canonical_screen_bt(
    scores_dt = inp$scores, returns_dt = inp$returns, bench_dt = inp$bench,
    top_n = top_n, cost_bps_oneway = 15, liq_dt = inp$liq, liq_min = 2e8,
    run_id = run_id, strategy_id = run_id, periods_per_year = 12L,
    diag_dual_basis = diag, size_dt = size_dt)
}

# window-sliced metrics from a canonical result's period_returns (no re-run)
window_metrics_ca <- function(res, date_lo = NULL, date_hi = NULL) {
  pr <- as.data.table(res$period_returns)
  if (!is.null(date_lo)) pr <- pr[date >= date_lo]
  if (!is.null(date_hi)) pr <- pr[date <= date_hi]
  if (nrow(pr) < 10L) return(list(n=nrow(pr), port_t=NA, calmar=NA, mdd=NA, net_sr=NA))
  pr[, active := ret_net - benchmark_ret]
  pt <- nw_t_f(pr$active)
  net_x <- xts(pr$ret_net, order.by = pr$date)
  cagr <- as.numeric(Return.annualized(net_x, scale = 12, geometric = TRUE))
  mdd  <- as.numeric(maxDrawdown(net_x))
  list(n = nrow(pr), port_t = round(pt$t,4), mean_active_m = round(pt$mean_m,5),
       calmar = round(cagr/mdd,4), cagr = round(cagr,4), mdd = round(mdd,4),
       net_sr = round(ann_sr_f(pr$ret_net),4),
       active_sr = round(ann_sr_f(pr$active),4))
}

# ---- calmar / structural DD from canonical period_returns (net) -------------
calmar_from_pr <- function(res) {
  pr <- res$period_returns
  if (is.null(pr) || nrow(pr) == 0) return(list(calmar=NA, cagr=NA, mdd=NA, sdd=NULL))
  net_x <- xts(pr$ret_net, order.by = pr$date)
  cagr <- as.numeric(Return.annualized(net_x, scale = 12, geometric = TRUE))
  mdd  <- as.numeric(maxDrawdown(net_x))
  sdd  <- structural_dd_f(net_x)
  list(calmar = round(cagr/mdd, 4), cagr = round(cagr,4), mdd = round(mdd,4), sdd = sdd)
}

# ---- AX-001 v2 crisis-conditional (base vs treatment) -----------------------
#   crisis = benchmark forward return 하위 20% 월. active = ret_net - BM_Ret.
crisis_conditional <- function(res) {
  pr <- res$period_returns
  if (is.null(pr) || nrow(pr) == 0) return(NULL)
  pr <- as.data.table(pr)
  pr[, active := ret_net - benchmark_ret]
  thr <- quantile(pr$benchmark_ret, 0.20, na.rm = TRUE)
  bad <- pr[benchmark_ret <= thr]; norm <- pr[benchmark_ret > thr]
  list(
    crisis_thr = round(as.numeric(thr),4),
    n_bad = nrow(bad), n_norm = nrow(norm),
    active_bad_mean = round(mean(bad$active),5),
    active_norm_mean = round(mean(norm$active),5),
    ret_net_bad_mean = round(mean(bad$ret_net),5),
    bm_bad_mean = round(mean(bad$benchmark_ret),5),
    bad_sr = round(ann_sr_f(bad$ret_net),4))
}

cat("[ca_lib] loaded — crash signals / canon inputs / run_canon / calmar / crisis\n")
