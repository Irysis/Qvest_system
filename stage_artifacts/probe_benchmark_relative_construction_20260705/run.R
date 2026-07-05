# run.R — DISCOVERY PROBE: benchmark-relative construction (enhanced indexing, active weights)
# Question: does benchmark-relative construction harvest short-side alpha to lift realized PORT_t
#           above the absolute top-25 selection (~0.97) in the KR long-only envelope?
#
# NOT a WT. screening-tier. canonical measurement only (weighted_screen_bt / build_benchmark_compare).
# Fixed axes: 25 names, long-only w>=0, [0,0.20], Sw=1, K200uKQ150, 15bps, PIT C1-C15.
#
# Inputs (read-only reuse):
#   - mu_hat (alpha composite) + sigma_hat + F1 (forward 1M ret): alpha_scores.parquet (WT-004)
#   - benchmark cap-weights b_i: benchmark_weights.rds (built PIT t-1 from RAWDATA Size x membership)
#   - realized benchmark BM_Ret: .cache/benchmark.parquet (KOSPI200 total return, forward-aligned)

suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); arrow::set_cpu_count(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA   <- file.path(ROOT,"stage_artifacts","WT-D20260705_004")
OUT  <- file.path(ROOT,"stage_artifacts","probe_benchmark_relative_construction_20260705")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))

set.seed(20260705L)
ym2date <- function(y) as.Date(paste0(y,"-01"))

# ---- Load inputs ----
pan <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))   # ym, Ticker, mu_hat, sigma_hat, F1, ...
yms <- sort(unique(pan$ym))
bw  <- readRDS(file.path(OUT,"benchmark_weights.rds"))                       # ym, Ticker, Size, b (cap-weight, alpha universe)

# forward-aligned benchmark (same recipe as repro_baseline_check.R)
bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, ym := format(as.Date(Date),"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_lr <- bm[, .(lr=sum(log1p(BM_Ret))), by=ym][order(ym)]
bm_lr[, bm_fwd := expm1(shift(lr, type="lead", n=1L))]
benchdt <- bm_lr[!is.na(bm_fwd), .(Date=ym2date(ym), BM_Ret=bm_fwd)]

# returns table (F1 = forward 1M realized, PIT-aligned)
rets <- pan[, .(Date=ym2date(ym), Ticker, Ret_1m=F1)]

CAP <- 0.20; NMAX <- 25L; BPS <- 15

# ---- Helper: cap-project weights to [0,CAP] with Sw=1 (long-only), iterative water-filling ----
cap_project <- function(w, cap=CAP) {
  w[w<0] <- 0
  if (sum(w)<=0) return(w)
  w <- w/sum(w)
  for (it in 1:100) {
    over <- w > cap + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - cap)
    w[over] <- cap
    under <- !over & w > 0
    if (!any(under)) { w[which.max(w)] <- w[which.max(w)]; break }
    w[under] <- w[under] + excess * w[under]/sum(w[under])
  }
  w/sum(w)
}

run_bt <- function(wd, tag, subset_from=NULL) {
  d <- copy(wd)
  if (!is.null(subset_from)) d <- d[Date >= as.Date(subset_from)]
  weighted_screen_bt(d, rets, benchdt, cost_bps_oneway=BPS, run_id=tag, strategy_id=tag)
}

# active-weight tracking-error attribution: realize weights vs b_i
# TE (ex-post active vol) computed later from realized series; here store per-month active exposure stats.
active_stats <- function(wd) {
  m <- merge(wd, bw[, .(ym, Ticker, b)], by=c("ym","Ticker"), all.x=TRUE)
  m[is.na(b), b := 0]
  m[, act := w - b]
  # per-month: sum |active|, n names, max weight, HHI
  m[, .(sum_abs_active=sum(abs(act)), n_names=.N, max_w=max(w), hhi=sum(w^2),
        held_bench_wt=sum(pmin(w,b))), by=ym]
}

# ================================================================================
# VARIANT 1: BASE — absolute top-25 by mu_hat, EW  (validity anchor, must ~0.97)
# ================================================================================
setorder(pan, ym, -mu_hat)
top25 <- pan[, head(.SD, NMAX), by=ym]
base_wd <- top25[, .(ym, Date=ym2date(ym), Ticker, w=1/NMAX)]
res <- list()
res$BASE <- run_bt(base_wd[, .(Date,Ticker,w)], "BASE")
res$BASE_rec <- run_bt(base_wd[, .(Date,Ticker,w)], "BASE_rec", subset_from="2017-01-01")
cat(sprintf("[BASE] full PORT_t=%.4f n=%d | recent2017=%.4f  (anchor 0.9698/-0.7248)\n",
            res$BASE$portfolio_alpha_t_nw_lag3, res$BASE$n_months, res$BASE_rec$portfolio_alpha_t_nw_lag3))

# ================================================================================
# VARIANT 2: ENH-IDX — maximize S (w_i - b_i) mu_hat  s.t. TE<=budget, w in [0,CAP], Sw=1, nonzero<=25
# Grinold-Kahn characteristic portfolio approach with active-risk (Sigma) budget via lambda sweep,
# then cap-project + top-25 truncation of the ACTIVE-tilted portfolio.
# We use a simple, robust construction: active tilt a_i proportional to mu_hat (demeaned),
# scaled to hit TE budget using per-name sigma_hat as risk proxy (diagonal risk).
# ================================================================================
sig <- pan[, .(ym, Ticker, mu_hat, sigma_hat)]
enh_build <- function(te_budget) {
  # per month: start from benchmark b, add active tilt a_i = k * (mu_hat - mean_bench(mu_hat)) / var-normalize
  out <- vector("list", length(yms))
  for (i in seq_along(yms)) {
    y <- yms[i]
    bb <- bw[ym==y, .(Ticker, b, Size)]
    mm <- sig[ym==y, .(Ticker, mu_hat, sigma_hat)]
    dd <- merge(bb, mm, by="Ticker", all=TRUE)
    dd[is.na(b), b:=0]; dd[is.na(mu_hat), mu_hat:=NA]
    dd <- dd[!is.na(mu_hat)]
    if (nrow(dd) < 5) next
    # demean mu_hat over benchmark-weighted mean (active signal has zero benchmark-weighted mean)
    mu_bar <- sum(dd$b * dd$mu_hat)/sum(dd$b)
    dd[, sig_a := mu_hat - mu_bar]
    # raw active direction: tilt toward high sig_a, scaled inversely by risk (diagonal): a ~ sig_a / sigma_hat^2
    dd[, sd2 := pmax(sigma_hat^2, 1e-6)]
    dd[, a_raw := sig_a / sd2]
    dd[, a_raw := a_raw - sum(b*a_raw)/sum(b)]  # enforce benchmark-neutral active (Sum b*a ~ 0 -> Sum a small); keep Sum a = 0
    dd[, a_raw := a_raw - mean(a_raw)]           # Sum a_i = 0 so Sum w = Sum b = 1
    # scale to TE budget: ex-ante active vol (diagonal) = sqrt(Sum a_i^2 sigma_hat^2) annualized (monthly sigma_hat)
    te_month <- sqrt(sum(dd$a_raw^2 * dd$sd2))
    te_ann <- te_month * sqrt(12)
    if (te_ann <= 0) next
    k <- te_budget / te_ann
    dd[, a := a_raw * k]
    dd[, w := b + a]
    dd[w<0, w:=0]
    # truncate to top-25 by w, then cap-project
    setorder(dd, -w)
    dd25 <- head(dd, NMAX)
    dd25[, w := cap_project(w)]
    out[[i]] <- dd25[w>0, .(ym=y, Date=ym2date(y), Ticker, w)]
  }
  rbindlist(out)
}
# TE budget sweep (annualized active vol target)
te_grid <- c(0.03, 0.05, 0.08, 0.12, 0.20)
enh_results <- list()
for (te in te_grid) {
  wd <- enh_build(te)
  r  <- run_bt(wd[, .(Date,Ticker,w)], sprintf("ENH_te%02d", round(te*100)))
  rr <- run_bt(wd[, .(Date,Ticker,w)], sprintf("ENH_te%02d_rec", round(te*100)), subset_from="2017-01-01")
  ast <- active_stats(wd)
  enh_results[[as.character(te)]] <- list(wd=wd, full=r, rec=rr, active=ast,
    realized_te = sd((r$period_returns$ret_net - r$period_returns$benchmark_ret))*sqrt(12))
  cat(sprintf("[ENH te=%.2f] full PORT_t=%.4f n=%d | rec2017=%.4f | realTE=%.3f | med max_w=%.3f\n",
              te, r$portfolio_alpha_t_nw_lag3, r$n_months, rr$portfolio_alpha_t_nw_lag3,
              sd(r$period_returns$ret_net - r$period_returns$benchmark_ret)*sqrt(12), median(ast$max_w)))
}

saveRDS(list(res=res, enh=enh_results, benchdt=benchdt, bw=bw), file.path(OUT,"phase1_base_enh.rds"))
cat("SAVED phase1_base_enh.rds\n")
