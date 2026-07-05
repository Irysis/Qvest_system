# =============================================================================
# dividend_analysis.R — WT-D20260706_006 — KR dividend-change SIGNALING drift
#   (Lintner) alpha. Consumes Python-prepped monthly parquets (R arrow segfaults
#   on 419MB rawdata). Canonical top-25 EW long-only measurement + CAP-TIER
#   decomposition (the mega-escape test) + closet-index guard + oos_retention.
# metric_type = canonical_screen (contract-grade; NOT admission-binding — forge is).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
setDTthreads(1L)

PR   <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(PR, "stage_artifacts/dividend_signaling_wt006")
CYC2 <- file.path(PR, "stage_artifacts/flow_microstructure_cycle2")
source(file.path(PR, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PR, "02_Infrastructure/contracts/canonical_screen_bt.R"))

TOP_N <- 25L; COST_BPS <- 15
D2017 <- as.Date("2017-01-01"); D2020 <- as.Date("2020-01-01")

rp <- function(dir, f) as.data.table(read_parquet(file.path(dir, f)))
returns_dt <- rp(CYC2, "returns_dt.parquet"); returns_dt[, Date := as.Date(Date)]
bench_dt   <- rp(CYC2, "bench_dt.parquet");   bench_dt[, Date := as.Date(Date)]
scores     <- rp(OUT,  "div_scores.parquet"); scores[, Date := as.Date(Date)]
liq_dt     <- rp(OUT,  "liq_dt.parquet"); liq_dt[, Date := as.Date(Date)]

# restrict scores to sig-months that have forward returns (drops last month = no forward)
valid_dates <- sort(unique(returns_dt$Date))
scores <- scores[Date %in% valid_dates]
cat(sprintf("[load] scores rows=%d months=%d range=%s..%s\n",
            nrow(scores), uniqueN(scores$Date),
            as.character(min(scores$Date)), as.character(max(scores$Date))))
cat(sprintf("[load] rows with div_yoy=%d  initiations=%d  payers=%d\n",
            sum(is.finite(scores$div_yoy)), sum(scores$div_initiate==1, na.rm=TRUE),
            sum(scores$div_payer==1, na.rm=TRUE)))

# =========================================================================
# Helpers
# =========================================================================
oos_retention_v2 <- function(active, af = 12) {
  a <- active[is.finite(active)]; n <- length(a)
  if (n < 12 || sd(a) == 0) return(list(ret = NA_real_, splits = rep(NA_real_,3)))
  splits <- c(0.55, 0.65, 0.75)
  rets <- vapply(splits, function(fr) {
    k <- floor(n * fr)
    if (k < 6 || (n - k) < 6) return(NA_real_)
    ia <- a[1:k]; oa <- a[(k+1):n]
    is_ir  <- if (sd(ia) > 0) mean(ia)/sd(ia)*sqrt(af) else NA_real_
    oos_ir <- if (sd(oa) > 0) mean(oa)/sd(oa)*sqrt(af) else NA_real_
    if (is.finite(is_ir) && is_ir > 0.05 && is.finite(oos_ir)) oos_ir/is_ir else NA_real_
  }, numeric(1))
  list(ret = if (any(is.finite(rets))) median(rets[is.finite(rets)]) else NA_real_,
       splits = round(rets, 3))
}

rank_ic_series <- function(sc, ret) {
  m <- merge(sc[, .(Date, Ticker, score)], ret[, .(Date, Ticker, Ret_1m)],
             by = c("Date","Ticker"))
  m <- m[is.finite(score) & is.finite(Ret_1m)]
  ics <- m[, .(ic = if (.N >= 10) cor(score, Ret_1m, method="spearman") else NA_real_), by = Date]
  ics[is.finite(ic)]
}

# =========================================================================
# (1) CANONICAL top-25 EW long-only measurement (score = div_yoy, higher=bigger div increase)
#   Universe restricted to payers-with-YoY (dividend-change is only defined for payers).
# =========================================================================
sc_full <- scores[is.finite(div_yoy), .(Date, Ticker, score = div_yoy)]
res_full <- canonical_screen_bt(sc_full, returns_dt, bench_dt,
                                top_n = TOP_N, cost_bps_oneway = COST_BPS,
                                liq_dt = liq_dt[, .(Date, Ticker, adv)], liq_min = 2e8,
                                run_id = "div_full", strategy_id = "div_full")
pr_full <- as.data.table(res_full$period_returns)
pr_full[, active := ret_net - benchmark_ret]

post <- pr_full[date >= D2017]; pre <- pr_full[date < D2017]
post_t <- .nw_t_mean(post$active, lag = 3L)
pre_t  <- .nw_t_mean(pre$active,  lag = 3L)
oosr <- oos_retention_v2(pr_full$active)

ic_full <- rank_ic_series(sc_full, returns_dt)
ic_post <- ic_full[Date >= D2017]
rank_ic_mean <- mean(ic_full$ic); icir <- rank_ic_mean / sd(ic_full$ic)
harvey_t <- rank_ic_mean / (sd(ic_full$ic)/sqrt(nrow(ic_full)))

cat("\n===== (1) CANONICAL top-25 EW long-only (div_yoy, payers) =====\n")
cat(sprintf("  n_months=%d  PORT_t_NW(full)=%.3f  IR=%.3f  net_SR=%.3f  turnover_ann=%.2f\n",
            res_full$n_months, res_full$portfolio_alpha_t_nw_lag3,
            res_full$information_ratio, res_full$net_sr, res_full$turnover_annual))
cat(sprintf("  alpha_ann=%.4f  mean_active_net(mo)=%.5f\n",
            res_full$alpha_annualized, res_full$mean_active_net))
cat(sprintf("  PORT_t pre2017=%.3f  post2017=%.3f  (n_post=%d)\n", pre_t, post_t, nrow(post)))
cat(sprintf("  oos_retention=%.3f  splits=%s\n", oosr$ret, paste(oosr$splits, collapse="/")))
cat(sprintf("  rank_IC=%.4f  ICIR=%.3f  harvey_t(rankIC)=%.3f  n_ic=%d\n",
            rank_ic_mean, icir, harvey_t, nrow(ic_full)))
cat(sprintf("  rank_IC post2017=%.4f (n=%d)\n", mean(ic_post$ic), nrow(ic_post)))

# --- (1b) DIVIDEND INITIATION long-only book (initiators EW, top-25) ---
# score = div_initiate (1 for initiators). Only months with >=1 initiator per book.
sc_init <- scores[div_initiate == 1, .(Date, Ticker, score = 1.0)]
n_init_months <- uniqueN(sc_init$Date)
if (nrow(sc_init) > 30 && n_init_months >= 12) {
  res_init <- canonical_screen_bt(sc_init, returns_dt, bench_dt,
                                  top_n = TOP_N, cost_bps_oneway = COST_BPS,
                                  liq_dt = liq_dt[, .(Date, Ticker, adv)], liq_min = 2e8,
                                  run_id="div_init", strategy_id="div_init")
  pri <- as.data.table(res_init$period_returns); pri[, active := ret_net - benchmark_ret]
  init_t_full <- res_init$port_t <- res_init$portfolio_alpha_t_nw_lag3
  init_t_post <- .nw_t_mean(pri[date>=D2017]$active, lag=3L)
  cat(sprintf("\n  [initiation book EW top-25] n_months=%d PORT_t_full=%.3f post2017=%.3f IR=%.3f (avg names/mo=%.1f)\n",
              res_init$n_months, init_t_full, init_t_post, res_init$information_ratio,
              nrow(sc_init)/n_init_months))
} else {
  res_init <- list(n_months=0L, portfolio_alpha_t_nw_lag3=NA_real_, information_ratio=NA_real_)
  init_t_full <- NA_real_; init_t_post <- NA_real_
  cat(sprintf("\n  [initiation book] too few initiators (rows=%d months=%d) — skip book, report count only\n",
              nrow(sc_init), n_init_months))
}

# =========================================================================
# (2) CAP-TIER DECOMPOSITION — the key mega-escape test.
#   Within each tier (mega top-10 / mid 11-30 / small 31+), among PAYERS-with-YoY:
#   top-half (high div_yoy) EW minus bottom-half EW, forward Ret_1m. NW lag-3 t.
# =========================================================================
tier_ls <- function(tier_name) {
  sc <- scores[tier == tier_name & is.finite(div_yoy), .(Date, Ticker, score = div_yoy)]
  m <- merge(sc, returns_dt[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  m <- m[is.finite(score) & is.finite(Ret_1m)]
  spread <- m[, {
    if (.N >= 4) {
      thr <- median(score)
      hi <- Ret_1m[score >= thr]; lo <- Ret_1m[score < thr]
      if (length(hi) >= 1 && length(lo) >= 1) .(ls = mean(hi) - mean(lo), n = .N) else .(ls = NA_real_, n = .N)
    } else .(ls = NA_real_, n = .N)
  }, by = Date]
  spread <- spread[is.finite(ls)]; setorder(spread, Date)
  list(
    tier = tier_name, n_months = nrow(spread),
    avg_names = round(mean(spread$n),1),
    ls_mean_mo = mean(spread$ls),
    ls_t_full  = .nw_t_mean(spread$ls, lag = 3L),
    ls_t_post2017 = .nw_t_mean(spread[Date >= D2017]$ls, lag = 3L),
    ls_t_pre2020  = .nw_t_mean(spread[Date <  D2020]$ls, lag = 3L),
    ls_t_post2020 = .nw_t_mean(spread[Date >= D2020]$ls, lag = 3L),
    n_post2017 = nrow(spread[Date >= D2017])
  )
}
cat("\n===== (2) CAP-TIER long-short spread (div_yoy high-half minus low-half, payers) =====\n")
tiers <- c("mega","mid","small")
tier_res <- lapply(tiers, tier_ls); names(tier_res) <- tiers
for (tr in tier_res) {
  cat(sprintf("  [%5s] n=%d avgN=%.1f  LS_mean=%.5f  t_full=%.3f  t_pre2020=%.3f  t_post2017=%.3f  t_post2020=%.3f\n",
              tr$tier, tr$n_months, tr$avg_names, tr$ls_mean_mo, tr$ls_t_full, tr$ls_t_pre2020,
              tr$ls_t_post2017, tr$ls_t_post2020))
}

# MEGA-only long-only: within mega payers, top-half (~3-4 names) by div_yoy EW vs BM.
mega_scores <- scores[tier == "mega" & is.finite(div_yoy), .(Date, Ticker, score = div_yoy)]
res_mega <- canonical_screen_bt(mega_scores, returns_dt, bench_dt,
                                top_n = 4L, cost_bps_oneway = COST_BPS,
                                run_id = "div_mega4", strategy_id = "div_mega4")
prm <- as.data.table(res_mega$period_returns); prm[, active := ret_net - benchmark_ret]
cat(sprintf("  [mega top-4 by div_yoy EW long-only vs BM] PORT_t_full=%.3f  post2017=%.3f  IR=%.3f  (n_months=%d)\n",
            res_mega$portfolio_alpha_t_nw_lag3,
            .nw_t_mean(prm[date>=D2017]$active, lag=3L), res_mega$information_ratio, res_mega$n_months))

# =========================================================================
# (3) CLOSET-INDEX GUARD — active-share, top-2 mega weight, ex-mega re-test
# =========================================================================
uni_size <- scores[, .(Date, Ticker, Size, mcap_rank, tier)]
setorder(sc_full, Date, -score)
book <- merge(sc_full, liq_dt[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
book <- book[is.na(adv) | adv >= 2e8]
setorder(book, Date, -score)
book25 <- book[, .(Ticker = Ticker[seq_len(min(TOP_N,.N))], w = rep(1/min(TOP_N,.N), min(TOP_N,.N))), by=Date]
book25 <- merge(book25, unique(uni_size[, .(Date, Ticker, mcap_rank, tier)]), by=c("Date","Ticker"), all.x=TRUE)
top2_w <- book25[mcap_rank <= 2, .(w_top2 = sum(w)), by=Date]
mega_w <- book25[tier == "mega", .(w_mega = sum(w)), by=Date]
avg_top2 <- mean(merge(unique(book25[,.(Date)]), top2_w, by="Date", all.x=TRUE)[is.na(w_top2), w_top2:=0]$w_top2)
avg_mega <- mean(merge(unique(book25[,.(Date)]), mega_w, by="Date", all.x=TRUE)[is.na(w_mega), w_mega:=0]$w_mega)

# active-share vs cap-weighted benchmark (Size-share approx over eligible universe)
bm_w <- unique(uni_size)[, .(Ticker, bm_w = Size/sum(Size)), by=Date]
as_dt <- merge(book25[, .(Date, Ticker, w)], bm_w, by=c("Date","Ticker"), all.x=TRUE)
as_dt[is.na(bm_w), bm_w := 0]
act_share <- as_dt[, .(as = 0.5 * (sum(abs(w - bm_w)) + (1 - sum(bm_w)))), by=Date]
avg_as <- mean(act_share$as)

# ex-mega re-test: exclude top-10 mega, canonical top-25 from remaining payers
sc_exmega <- scores[tier != "mega" & is.finite(div_yoy), .(Date, Ticker, score = div_yoy)]
res_exmega <- canonical_screen_bt(sc_exmega, returns_dt, bench_dt,
                                  top_n = TOP_N, cost_bps_oneway = COST_BPS,
                                  liq_dt = liq_dt[, .(Date, Ticker, adv)], liq_min = 2e8,
                                  run_id="div_exmega", strategy_id="div_exmega")
pre_ex <- as.data.table(res_exmega$period_returns); pre_ex[, active := ret_net - benchmark_ret]

cat("\n===== (3) CLOSET-INDEX GUARD =====\n")
cat(sprintf("  avg active-share=%.3f  avg top-2 mega weight in book=%.3f  avg total-mega weight=%.3f\n",
            avg_as, avg_top2, avg_mega))
cat(sprintf("  EX-MEGA canonical top-25: PORT_t_full=%.3f  post2017=%.3f  IR=%.3f  net_SR=%.3f\n",
            res_exmega$portfolio_alpha_t_nw_lag3,
            .nw_t_mean(pre_ex[date>=D2017]$active, lag=3L),
            res_exmega$information_ratio, res_exmega$net_sr))

# =========================================================================
# (4) Self-adversarial: is div_yoy just a quality/value proxy?
#   cross-sectional rank corr of div_yoy with (a) payout_yield_proxy (level, value-ish)
#   and (b) dividend LEVEL. Low corr => change channel distinct from level.
# =========================================================================
lvl <- scores[is.finite(div_yoy) & is.finite(payout_yield_proxy),
              .(Date, Ticker, div_yoy, payout = payout_yield_proxy, dlevel = div_paid)]
corr_yoy_payout <- lvl[, .(c = if (.N>=10) cor(div_yoy, payout, method="spearman") else NA_real_), by=Date]
corr_yoy_level  <- lvl[, .(c = if (.N>=10) cor(div_yoy, dlevel, method="spearman") else NA_real_), by=Date]
cat("\n===== (4) div_yoy vs level proxies (distinctness) =====\n")
cat(sprintf("  mean xsec Spearman(div_yoy, payout_yield_proxy)=%.3f\n", mean(corr_yoy_payout$c, na.rm=TRUE)))
cat(sprintf("  mean xsec Spearman(div_yoy, div_level)=%.3f\n", mean(corr_yoy_level$c, na.rm=TRUE)))

# =========================================================================
# SAVE results JSON
# =========================================================================
out <- list(
  task_id = "WT-D20260706_006",
  as_of = "2026-07-06",
  signal = "div_yoy = YoY growth of annual cash dividends paid (CF DividendsPaid), Lintner signaling change channel. PIT annual->May lag.",
  metric_type = "canonical_screen",
  n_months = res_full$n_months,
  signal_window = paste(as.character(min(sc_full$Date)), "..", as.character(max(sc_full$Date))),
  canonical_top25_div_yoy = list(
    port_t_nw_full = round(res_full$portfolio_alpha_t_nw_lag3,3),
    port_t_pre2017 = round(pre_t,3),
    port_t_post2017 = round(post_t,3),
    n_post2017 = nrow(post),
    information_ratio = round(res_full$information_ratio,3),
    net_sr = round(res_full$net_sr,3),
    alpha_annualized = round(res_full$alpha_annualized,4),
    turnover_annual = round(res_full$turnover_annual,2),
    oos_retention = round(oosr$ret,3),
    oos_splits = oosr$splits,
    rank_ic = round(rank_ic_mean,4),
    icir = round(icir,3),
    harvey_t_rankic = round(harvey_t,3),
    rank_ic_post2017 = round(mean(ic_post$ic),4)
  ),
  dividend_initiation_book = list(
    n_months = res_init$n_months,
    port_t_full = round(init_t_full,3),
    port_t_post2017 = round(init_t_post,3),
    ir = round(res_init$information_ratio,3)
  ),
  cap_tier_longshort = lapply(tier_res, function(tr) lapply(tr, function(x) if(is.numeric(x)) round(x,4) else x)),
  mega_top4_longonly = list(
    port_t_full = round(res_mega$portfolio_alpha_t_nw_lag3,3),
    port_t_post2017 = round(.nw_t_mean(prm[date>=D2017]$active, lag=3L),3),
    ir = round(res_mega$information_ratio,3),
    n_months = res_mega$n_months
  ),
  closet_guard = list(
    avg_active_share = round(avg_as,3),
    avg_top2_mega_weight = round(avg_top2,3),
    avg_total_mega_weight = round(avg_mega,3),
    exmega_port_t_full = round(res_exmega$portfolio_alpha_t_nw_lag3,3),
    exmega_port_t_post2017 = round(.nw_t_mean(pre_ex[date>=D2017]$active, lag=3L),3),
    exmega_ir = round(res_exmega$information_ratio,3),
    exmega_net_sr = round(res_exmega$net_sr,3)
  ),
  distinctness = list(
    corr_yoy_payout = round(mean(corr_yoy_payout$c, na.rm=TRUE),3),
    corr_yoy_level = round(mean(corr_yoy_level$c, na.rm=TRUE),3)
  ),
  graduation_gates = list(
    port_t_hard_2p95 = round(res_full$portfolio_alpha_t_nw_lag3,3),
    oos_retention_hard_0p7 = round(oosr$ret,3),
    calmar_note = "computed at forge; canonical net_sr/IR reported here"
  )
)
write_json(out, file.path(OUT, "dividend_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=5)
write_parquet(pr_full, file.path(OUT, "dividend_period_returns.parquet"))
cat("\n[DONE] wrote dividend_result.json\n")
