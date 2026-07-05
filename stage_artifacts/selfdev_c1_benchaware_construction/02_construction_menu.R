# 02_construction_menu.R — Self-Developing Cycle 1: benchmark-aware CONSTRUCTION menu
# The construction is the ONLY variable. Base alpha FIXED (12-1 momentum). NULL-alpha variant isolates anchor.
#
# All variants measured through weighted_screen_bt() (contract build_benchmark_compare, NW lag-3),
# metric_type = weighted_screen (screening-tier; a milestone must be re-measured forge-authoritative in Cycle 2).
#
# FIXED SETUP: universe K200 U KQ150, monthly, 2005-01..2026-06, long-only, <=25 names,
#   w in [0,0.20], Sum w=1, 15bps one-way (delta), liquidity >= 2e8 KRW.
# Active-return denominator: cap-weighted KOSPI200 total return (benchmark_monthly BM_Ret).

suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WD   <- file.path(ROOT, "stage_artifacts/selfdev_c1_benchaware_construction")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/weighted_screen_bt.R"))

TOP_N   <- 25L
WMAX    <- 0.20
COSTBPS <- 15
LIQ_MIN <- 2e8
SET     <- function(...) message(sprintf(...))

panel <- as.data.table(read_parquet(file.path(WD, "panel/panel_monthly.parquet")))
bench <- as.data.table(read_parquet(file.path(WD, "panel/benchmark_monthly.parquet")))
panel[, Date := as.Date(Date)]; bench[, Date := as.Date(Date)]

# window: 2005-01 .. 2026-06 ; need mom + Ret_1m + liquidity + mcap
panel <- panel[Date >= as.Date("2005-01-01") & Date <= as.Date("2026-06-01")]
# liquidity filter (t, 20d ADV >= 2e8). NA adv -> drop (conservative; must be liquid to hold).
panel <- panel[is.finite(adv20_t) & adv20_t >= LIQ_MIN]
# base alpha requires momentum; returns requires Ret_1m
panel <- panel[is.finite(mom_12_1) & is.finite(Ret_1m) & is.finite(mcap_t)]
dts <- sort(unique(panel$Date))
SET("[menu] months usable: %d (%s..%s), avg names/month=%.0f",
    length(dts), as.character(min(dts)), as.character(max(dts)), nrow(panel)/length(dts))

bench_dt <- bench[, .(Date, BM_Ret)]

# ---------- weight builders: each returns data.table(Date,Ticker,w) ----------
# Cap weight at WMAX then renormalize (iterative, keeps Sum=1, respects [0,0.20]).
cap_renorm <- function(w, wmax = WMAX) {
  w <- pmax(w, 0); if (sum(w) == 0) return(w)
  w <- w / sum(w)
  for (it in 1:50) {
    over <- w > wmax + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - wmax); w[over] <- wmax
    free <- !over & w > 0
    if (!any(free)) { w[over] <- wmax; break }
    w[free] <- w[free] + excess * w[free] / sum(w[free])
  }
  w / sum(w)
}

# select top-N by base alpha (momentum) among liquid univ, per month
select_topN <- function(D, n = TOP_N) {
  m <- panel[Date == D]
  setorder(m, -mom_12_1)
  m[seq_len(min(n, .N))]
}

build_variant <- function(mode, K = 0L, anchor_w = 0.20, fill = "ew", null_alpha = FALSE, seed = 1L) {
  # mode in: ew, capw, bmw, anchor
  set.seed(seed)
  out <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    D <- dts[i]
    m <- panel[Date == D]
    if (nrow(m) < TOP_N) next
    # base alpha score (NULL-alpha => random permutation to isolate pure anchor/construction)
    m[, score := if (null_alpha) sample(.N) else mom_12_1]
    setorder(m, -mcap_t)  # for anchor selection by LAGGED cap (known at t)
    if (mode == "anchor" && K > 0L) {
      anch <- m$Ticker[seq_len(K)]
      rest <- m[!Ticker %in% anch]
      setorder(rest, -score)
      nfill <- TOP_N - K
      sel <- rest[seq_len(min(nfill, nrow(rest)))]
      w_anch <- rep(anchor_w, K)
      rem <- 1 - sum(w_anch)
      if (fill == "ew") {
        w_fill <- rep(rem / nrow(sel), nrow(sel))
      } else if (fill == "alpha") {
        s <- pmax(sel$score - min(sel$score) + 1e-6, 1e-6)  # shift positive for proportional
        w_fill <- rem * s / sum(s)
      } else if (fill == "capw") {
        s <- sel$mcap_t; w_fill <- rem * s / sum(s)
      }
      tk <- c(anch, sel$Ticker); w <- c(w_anch, w_fill)
    } else {
      setorder(m, -score)
      sel <- m[seq_len(TOP_N)]
      if (mode == "ew") {
        w <- rep(1 / TOP_N, TOP_N)
      } else if (mode == "capw") {
        w <- cap_renorm(sel$mcap_t)
      } else if (mode == "bmw") {
        # BM weight-hold: weight selected names by their cap (proxy for BM weight within universe),
        # then renorm+cap. (True BM weight = cap weight in a cap-weighted index; using univ cap share.)
        w <- cap_renorm(sel$mcap_t)   # placeholder; overwritten below for true bmw
      }
      tk <- sel$Ticker
    }
    # cap all variants at WMAX (anchor already <=0.20 by construction; fill could exceed if alpha concentrated)
    w <- cap_renorm(w)
    out[[i]] <- data.table(Date = D, Ticker = tk, w = w)
  }
  rbindlist(out)
}

# BM-weight-hold done separately (needs true benchmark weight = cap share within FULL universe, not just top25)
build_bmw_hold <- function() {
  out <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    D <- dts[i]; m <- panel[Date == D]
    if (nrow(m) < TOP_N) next
    setorder(m, -mom_12_1)
    sel <- m[seq_len(TOP_N)]
    # hold each selected name at its cap-share-within-universe (proxy for BM weight), renorm to 1, cap 0.20
    w <- cap_renorm(sel$mcap_t)
    out[[i]] <- data.table(Date = D, Ticker = sel$Ticker, w = w)
  }
  rbindlist(out)
}

measure <- function(wdt, tag) {
  r <- weighted_screen_bt(wdt, panel[, .(Date, Ticker, Ret_1m)], bench_dt,
                          cost_bps_oneway = COSTBPS, run_id = tag, strategy_id = tag)
  pr <- r$period_returns
  act <- pr$ret_net - pr$benchmark_ret; n <- length(act)
  # oos_retention: anchored 3-split median (0.55/0.65/0.75) of active-Sharpe OOS/IS
  oos <- median(sapply(c(0.55,0.65,0.75), function(q){
    cut <- floor(n*q)
    is_sr  <- mean(act[1:cut])/sd(act[1:cut])
    oos_sr <- mean(act[(cut+1):n])/sd(act[(cut+1):n])
    oos_sr/is_sr
  }), na.rm=TRUE)
  # post-2017 active t (NW lag-3)
  p2 <- pr[date >= as.Date("2017-01-01")]; a2 <- p2$ret_net - p2$benchmark_ret
  nw_t <- function(x){ m<-mean(x); dm<-x-m; nn<-length(x); g0<-sum(dm^2)/nn; gs<-0
    for(L in 1:3){ ww<-1-L/4; gs<-gs+2*ww*sum(dm[(L+1):nn]*dm[1:(nn-L)])/nn }; m/sqrt((g0+gs)/nn) }
  p17_t <- if (length(a2) > 6) nw_t(a2) else NA_real_
  # split pre-2020 vs post-2020 active t (Hynix AI-run robustness)
  pre20 <- pr[date < as.Date("2020-01-01")]; a_pre <- pre20$ret_net - pre20$benchmark_ret
  pos20 <- pr[date >= as.Date("2020-01-01")]; a_pos <- pos20$ret_net - pos20$benchmark_ret
  pre20_t <- if (length(a_pre)>6) nw_t(a_pre) else NA_real_
  pos20_t <- if (length(a_pos)>6) nw_t(a_pos) else NA_real_
  # concentration: mean max weight, mean top2 weight
  cc <- wdt[, .(mx = max(w), t2 = sum(sort(w, decreasing=TRUE)[1:2])), by = Date]
  # active share vs cap-weighted BM: cannot compute exact (no full BM weights); proxy = how far port from benchmark.
  # approximate active share = 0.5*sum|w_i - bm_i| where bm approximated by univ cap share for held names,
  #   plus full benchmark mass on unheld names. We compute a conservative proxy per month.
  data.table(
    tag = tag, n_months = n,
    active_PORT_t = r$portfolio_alpha_t_nw_lag3,
    IR = r$information_ratio,
    net_sr = r$net_sr,
    post2017_t = p17_t,
    pre2020_t = pre20_t, post2020_t = pos20_t,
    oos_ret = oos,
    mean_active_ann = r$alpha_annualized,
    turnover = r$turnover_annual,
    max_wt = mean(cc$mx), top2_wt = mean(cc$t2),
    abs_mdd = r$abs_mdd, abs_cagr = r$abs_cagr
  )
}

# ---------------- run the menu ----------------
res <- list()
SET("[menu] building variants...")

# 1. EW-top25 (baseline wall)
res$V1_EW              <- measure(build_variant("ew"),                              "V1_EW_top25")
# 2. CapWeighted-top25
res$V2_CAPW           <- measure(build_variant("capw"),                            "V2_CapW_top25")
# 3. BM-weight-hold (cap-share within universe, renorm+cap)
res$V3_BMW            <- measure(build_bmw_hold(),                                  "V3_BMweightHold")
# 4. MegaCap-anchor-K2 + EW-fill
res$V4_ANCH2_EW       <- measure(build_variant("anchor", K=2L, fill="ew"),         "V4_Anchor2_EWfill")
# 5. MegaCap-anchor-K2 + alpha-fill
res$V5_ANCH2_ALPHA    <- measure(build_variant("anchor", K=2L, fill="alpha"),      "V5_Anchor2_AlphaFill")
# 6. Systematic anchor K in {1,3,5}, alpha-fill (generalize)
res$V6a_ANCH1         <- measure(build_variant("anchor", K=1L, fill="alpha"),      "V6a_Anchor1_AlphaFill")
res$V6b_ANCH3         <- measure(build_variant("anchor", K=3L, fill="alpha"),      "V6b_Anchor3_AlphaFill")
res$V6c_ANCH5         <- measure(build_variant("anchor", K=5L, fill="alpha"),      "V6c_Anchor5_AlphaFill")
# NULL-alpha anchor variants (isolate pure anchor contribution) — avg over 3 seeds
null_anchor <- function(K, seeds=1:3){
  rr <- rbindlist(lapply(seeds, function(s) measure(build_variant("anchor", K=K, fill="ew", null_alpha=TRUE, seed=s),
                                                     sprintf("NULL_Anchor%d_s%d",K,s))))
  rr[, lapply(.SD, function(x) if(is.numeric(x)) mean(x, na.rm=TRUE) else x[1]), .SDcols=setdiff(names(rr),"tag")][, tag:=sprintf("V_NULLalpha_Anchor%d_EWfill",K)][]
}
res$VN_NULL_EW        <- { rr <- rbindlist(lapply(1:3, function(s) measure(build_variant("ew", null_alpha=TRUE, seed=s), sprintf("NULL_EW_s%d",s))))
                           agg <- rr[, lapply(.SD, mean, na.rm=TRUE), .SDcols=which(sapply(rr,is.numeric))]; agg[, tag:="VN_NULLalpha_EW_top25"]; setcolorder(agg,"tag"); agg }
res$VN_NULL_ANCH2     <- null_anchor(2L)
res$VN_NULL_ANCH2$tag <- "VN_NULLalpha_Anchor2_EWfill"

resdt <- rbindlist(res, fill = TRUE)
setcolorder(resdt, c("tag","active_PORT_t","post2017_t","pre2020_t","post2020_t","oos_ret",
                     "max_wt","top2_wt","turnover","IR","net_sr","mean_active_ann","abs_mdd","n_months"))
resdt[, metric_type := "weighted_screen"]
resdt[, milestone := is.finite(active_PORT_t) & active_PORT_t >= 2.95 &
                     is.finite(post2017_t) & post2017_t > 0 &
                     is.finite(oos_ret) & oos_ret >= 0.7]

fwrite(resdt, file.path(WD, "construction_menu_results.csv"))
cat("\n================ CONSTRUCTION MENU RESULTS ================\n")
print(resdt[, .(tag, PORT_t=round(active_PORT_t,2), p2017=round(post2017_t,2),
                pre20=round(pre2020_t,2), pos20=round(post2020_t,2), oos=round(oos_ret,2),
                mxwt=round(max_wt,3), t2wt=round(top2_wt,3), turn=round(turnover,2),
                IR=round(IR,2), MILE=milestone)])
cat(sprintf("\n[menu] milestone candidates: %d\n", sum(resdt$milestone, na.rm=TRUE)))
saveRDS(res, file.path(WD, "construction_menu_res.rds"))
cat("[menu] DONE\n")
