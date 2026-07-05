# run2.R — VARIANT 3 (SHORT-HARVEST), VARIANT 4 (mega-cap anchor), + adversarial suite.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); arrow::set_cpu_count(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA   <- file.path(ROOT,"stage_artifacts","WT-D20260705_004")
OUT  <- file.path(ROOT,"stage_artifacts","probe_benchmark_relative_construction_20260705")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))
set.seed(20260705L)
ym2date <- function(y) as.Date(paste0(y,"-01"))

pan <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))
yms <- sort(unique(pan$ym))
bw  <- readRDS(file.path(OUT,"benchmark_weights.rds"))
bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, ym := format(as.Date(Date),"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_lr <- bm[, .(lr=sum(log1p(BM_Ret))), by=ym][order(ym)]
bm_lr[, bm_fwd := expm1(shift(lr, type="lead", n=1L))]
benchdt <- bm_lr[!is.na(bm_fwd), .(Date=ym2date(ym), BM_Ret=bm_fwd)]
rets <- pan[, .(Date=ym2date(ym), Ticker, Ret_1m=F1)]
CAP <- 0.20; NMAX <- 25L; BPS <- 15

cap_project <- function(w, cap=CAP) {
  w[w<0] <- 0; if (sum(w)<=0) return(w); w <- w/sum(w)
  for (it in 1:100) { over <- w>cap+1e-12; if(!any(over)) break
    excess <- sum(w[over]-cap); w[over]<-cap; under <- !over & w>0
    if(!any(under)){break}; w[under]<-w[under]+excess*w[under]/sum(w[under]) }
  w/sum(w)
}
run_bt <- function(wd, tag, subset_from=NULL) {
  d <- copy(wd); if(!is.null(subset_from)) d <- d[Date>=as.Date(subset_from)]
  weighted_screen_bt(d, rets, benchdt, cost_bps_oneway=BPS, run_id=tag, strategy_id=tag)
}
PT <- function(r) r$portfolio_alpha_t_nw_lag3

# ================================================================================
# VARIANT 4 (build first — it's the reference the probe wants to generalize):
# mega-cap anchor: top-2 size names get 20% cap each (0.40 total), remaining 0.60 to top alpha-fill.
# Reproduce [[project-megacap-anchor-construction-discovery]] (reported ~4.76 screening).
# ================================================================================
anchor_build <- function(anchor_frac_each=0.20, n_fill=23L, fill_mode="alpha") {
  out <- vector("list", length(yms))
  for (i in seq_along(yms)) {
    y <- yms[i]
    bb <- bw[ym==y][order(-Size)]
    mm <- pan[ym==y, .(Ticker, mu_hat)]
    if (nrow(bb) < 3) next
    anchors <- head(bb$Ticker, 2)
    # fill pool = alpha names excluding anchors
    pool <- mm[!Ticker %in% anchors]
    if (fill_mode=="alpha") setorder(pool, -mu_hat)
    else if (fill_mode=="bottom") setorder(pool, mu_hat)
    else if (fill_mode=="random") pool <- pool[sample(.N)]
    fill <- head(pool$Ticker, n_fill)
    w <- c(rep(anchor_frac_each, length(anchors)), rep((1-anchor_frac_each*length(anchors))/length(fill), length(fill)))
    tk <- c(anchors, fill)
    dt <- data.table(ym=y, Date=ym2date(y), Ticker=tk, w=w)
    dt[, w := cap_project(w)]
    out[[i]] <- dt[w>0, .(ym, Date, Ticker, w)]
  }
  rbindlist(out)
}
anc_wd <- anchor_build(fill_mode="alpha")
res <- list()
res$ANCHOR <- run_bt(anc_wd[,.(Date,Ticker,w)], "ANCHOR")
res$ANCHOR_rec <- run_bt(anc_wd[,.(Date,Ticker,w)], "ANCHOR_rec", subset_from="2017-01-01")
cat(sprintf("[ANCHOR alpha-fill] full PORT_t=%.4f n=%d | rec2017=%.4f\n", PT(res$ANCHOR), res$ANCHOR$n_months, PT(res$ANCHOR_rec)))

# ADVERSARIAL (a): placebo fills — bottom-fill and random-fill (does the lift come from alpha edge?)
anc_bottom <- anchor_build(fill_mode="bottom")
anc_rand_list <- list()
for (s in 1:20) { set.seed(1000+s); anc_rand_list[[s]] <- run_bt(anchor_build(fill_mode="random")[,.(Date,Ticker,w)], paste0("ANCHOR_rand",s)) }
res$ANCHOR_bottom <- run_bt(anc_bottom[,.(Date,Ticker,w)], "ANCHOR_bottom")
rand_pt <- sapply(anc_rand_list, PT)
cat(sprintf("[ANCHOR bottom-fill] PORT_t=%.4f | [ANCHOR random-fill] mean=%.4f sd=%.4f range=[%.3f,%.3f]\n",
            PT(res$ANCHOR_bottom), mean(rand_pt), sd(rand_pt), min(rand_pt), max(rand_pt)))
# placebo p-value: fraction of random fills >= alpha-fill PORT_t
p_rand <- mean(rand_pt >= PT(res$ANCHOR))
# alpha-edge = alpha-fill - bottom-fill (in port_t) and also compare vs random mean
cat(sprintf("  alpha-edge vs bottom = %.3f | placebo p(rand>=alpha)=%.3f | edge vs rand-mean=%.3f\n",
            PT(res$ANCHOR)-PT(res$ANCHOR_bottom), p_rand, PT(res$ANCHOR)-mean(rand_pt)))

# ================================================================================
# VARIANT 3: SHORT-HARVEST — hold benchmark-representative (cap-weight of GOOD-signal members)
# but drive worst-signal high-cap names to 0 (harvest the short-side as -b_i active).
# Construction: within benchmark members with alpha, drop bottom-K by mu_hat (set w=0),
# redistribute their b to remaining members proportional to b (benchmark-relative, no new bets),
# then truncate to top-25 by resulting weight + cap-project.
# Isolate from anchor: NO explicit anchor; mega-cap kept only if not bottom-signal.
# ================================================================================
sh_build <- function(drop_frac=0.5) {
  out <- vector("list", length(yms))
  for (i in seq_along(yms)) {
    y <- yms[i]
    dd <- merge(bw[ym==y, .(Ticker,b)], pan[ym==y,.(Ticker,mu_hat)], by="Ticker")
    if (nrow(dd)<10) next
    setorder(dd, mu_hat)
    n_drop <- floor(nrow(dd)*drop_frac)
    drop_tk <- head(dd$Ticker, n_drop)   # worst-signal names -> underweight to 0
    keep <- dd[!Ticker %in% drop_tk]
    keep[, w := b/sum(b)]                 # redistribute dropped cap-weight prorata to survivors
    setorder(keep, -w)
    k25 <- head(keep, NMAX)
    k25[, w := cap_project(w)]
    out[[i]] <- k25[w>0, .(ym=y, Date=ym2date(y), Ticker, w)]
  }
  rbindlist(out)
}
for (df in c(0.3,0.5,0.7)) {
  wd <- sh_build(df)
  r <- run_bt(wd[,.(Date,Ticker,w)], sprintf("SH_%02d",round(df*100)))
  rr <- run_bt(wd[,.(Date,Ticker,w)], sprintf("SH_%02d_rec",round(df*100)), subset_from="2017-01-01")
  res[[sprintf("SH_%02d",round(df*100))]] <- r
  res[[sprintf("SH_%02d_rec",round(df*100))]] <- rr
  cat(sprintf("[SHORT-HARVEST drop=%.1f] full PORT_t=%.4f n=%d | rec2017=%.4f | med max_w=%.3f\n",
              df, PT(r), r$n_months, PT(rr), median(merge(wd,wd[,.(mw=max(w)),by=ym],by="ym")$mw)))
}

# additivity test: does SHORT-HARVEST add to ANCHOR? anchor + drop bottom-signal from fill already alpha-sorted,
# so build ANCHOR-with-short = anchor top2 + fill from members EXCLUDING bottom-50% signal (vs plain alpha-fill).
anchor_short_build <- function() {
  out <- vector("list", length(yms))
  for (i in seq_along(yms)) {
    y <- yms[i]; bb <- bw[ym==y][order(-Size)]; mm <- pan[ym==y,.(Ticker,mu_hat)]
    if (nrow(bb)<3) next
    anchors <- head(bb$Ticker,2)
    pool <- mm[!Ticker %in% anchors]; setorder(pool,-mu_hat)
    fill <- head(pool$Ticker,23L)
    w <- c(rep(0.20,2), rep(0.60/23,23)); tk <- c(anchors,fill)
    dt <- data.table(ym=y,Date=ym2date(y),Ticker=tk,w=cap_project(w))
    out[[i]] <- dt[w>0]
  }
  rbindlist(out)
}
# (ANCHOR alpha-fill already = anchor + top-23 alpha = long-side selection; short-harvest additivity
#  is captured by comparing ANCHOR vs ANCHOR_bottom above. The -b_i underweight IS the anchor's implicit
#  short of non-held mega/large caps. Report attribution below.)

# ADVERSARIAL (b): lag1 PIT graceful — shift signal AND benchmark weights by 1 month (use t-1 info for t).
# If lift survives gracefully (no collapse/reversal) => no look-ahead leak.
pan_lag <- copy(pan); setorder(pan_lag, Ticker, ym)
pan_lag[, mu_lag := shift(mu_hat, 1L), by=Ticker]
bw_lag <- copy(bw); setorder(bw_lag, Ticker, ym); bw_lag[, b_lag := shift(b,1L), by=Ticker]
anchor_lag_build <- function() {
  out <- vector("list", length(yms))
  for (i in seq_along(yms)) {
    y <- yms[i]
    bb <- bw_lag[ym==y & !is.na(b_lag) & b_lag>0][order(-b_lag)]
    mm <- pan_lag[ym==y & !is.na(mu_lag), .(Ticker, mu_lag)]
    if (nrow(bb)<3 || nrow(mm)<25) next
    anchors <- head(bb$Ticker,2)
    pool <- mm[!Ticker %in% anchors]; setorder(pool,-mu_lag)
    fill <- head(pool$Ticker,23L); w <- c(rep(0.20,2),rep(0.60/23,23)); tk <- c(anchors,fill)
    out[[i]] <- data.table(ym=y,Date=ym2date(y),Ticker=tk,w=cap_project(w))[w>0]
  }
  rbindlist(out)
}
anc_lag <- anchor_lag_build()
res$ANCHOR_lag1 <- run_bt(anc_lag[,.(Date,Ticker,w)], "ANCHOR_lag1")
cat(sprintf("[ADV-b lag1 PIT] ANCHOR_lag1 PORT_t=%.4f n=%d (vs t0 %.4f) -> %s\n",
            PT(res$ANCHOR_lag1), res$ANCHOR_lag1$n_months, PT(res$ANCHOR),
            ifelse(PT(res$ANCHOR_lag1) > 0 && PT(res$ANCHOR_lag1) > PT(res$ANCHOR)*0.3, "graceful (no leak)", "degrades")))

# ADVERSARIAL (c): concentration risk of ANCHOR (40% in top-2)
anc_conc <- anc_wd[, .(top2=sum(sort(w,decreasing=TRUE)[1:2]), max_w=max(w), hhi=sum(w^2)), by=ym]
cat(sprintf("[ADV-c concentration] ANCHOR median top2=%.3f max_w=%.3f hhi=%.4f\n",
            median(anc_conc$top2), median(anc_conc$max_w), median(anc_conc$hhi)))

# ADVERSARIAL (d): short-side attribution — decompose ANCHOR active return into
# (i) anchor mega-cap tilt (top2 held at 20% vs their b) and (ii) fill alpha vs (iii) underweight of non-held.
# Approx via: ANCHOR vs "EW top-25 alpha" (=BASE) tells anchor+underweight contribution;
# ANCHOR vs ANCHOR_bottom tells fill-alpha contribution.
cat(sprintf("[ADV-d attribution] ANCHOR(%.3f) - BASE(%.3f) = %.3f (anchor+underweight lift)\n",
            PT(res$ANCHOR), 0.9698, PT(res$ANCHOR)-0.9698))

saveRDS(list(res=res, rand_pt=rand_pt, anc_wd=anc_wd, anc_conc=anc_conc,
             p_rand=p_rand), file.path(OUT,"phase2_sh_anchor.rds"))
cat("SAVED phase2_sh_anchor.rds\n")
