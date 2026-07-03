# WT-D20260621_009 — Buyback Yield Confirmed Momentum (alpha-only)
# Real-computation via canonical_screen_bt -> build_benchmark_compare. NO proxy hand-calc.
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1)
options(stringsAsFactors=FALSE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- "stage_artifacts/WT-D20260621_009"
dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
log <- function(...) cat(sprintf(...), "\n")

START_DATE <- as.Date("2005-01-01")

# ---------- 1. Buyback panel -> TTM ----------
sb <- as.data.table(read_parquet(".cache/stock_buyback.parquet"))
sb[Value < 0, Value := 0]                       # floor 8 negative disposal rows
setorder(sb, Ticker, Period_Date)
# rolling 4-quarter trailing sum within ticker (TTM); Factor_Date of the latest quarter is the as-of date
sb[, SBB_ttm := frollsum(Value, 4, align="right"), by=Ticker]
sb <- sb[!is.na(SBB_ttm)]                        # need 4 quarters present
sb_pit <- sb[, .(Ticker, Factor_Date, SBB_ttm)]  # as-of-disclosure TTM buyback
log("buyback TTM rows: %d  Factor_Date range %s..%s",
    nrow(sb_pit), as.character(min(sb_pit$Factor_Date)), as.character(max(sb_pit$Factor_Date)))

# also keep 2Q and 8Q variants for lookback grid (ablation)
setorder(sb, Ticker, Period_Date)
sb[, SBB_2q := frollsum(Value, 2, align="right"), by=Ticker]
sb[, SBB_8q := frollsum(Value, 8, align="right"), by=Ticker]

# ---------- 2. RAWDATA -> monthly panel ----------
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
   col_select=c("Date","Ticker","K200","KQ150","Close","Vol","Size","Ret","AdminStock","TradingHalt","UnfaithfulDisc","Sector")))
rd <- rd[Date >= as.Date("2004-01-01")]          # buffer for M03/M12 lookback before 2005
rd[, ym := format(Date, "%Y-%m")]
setorder(rd, Ticker, Date)
# daily adv = 20d mean(Vol*Close), LAGGED to t-1 (C10): the 20d window must END at the
# prior trading day, so the month-end sig_date's own volume is NOT in the filter input.
rd[, dollar_vol := Vol * Close]
rd[, adv20_raw := frollmean(dollar_vol, 20, align="right"), by=Ticker]
rd[, adv20 := shift(adv20_raw, 1L, type="lag"), by=Ticker]   # t-1 ADV (C10)
# month-end snapshot (last trading day of month)
mlast <- rd[, .I[Date == max(Date)], by=.(Ticker, ym)]$V1
mon <- rd[mlast, .(Ticker, ym, Date, Close, Size, K200, KQ150, AdminStock, TradingHalt, UnfaithfulDisc, adv20, Sector)]
setorder(mon, Ticker, Date)
# monthly forward realized return: compound daily Ret within each FORWARD month
mret <- rd[, .(mret = prod(1 + ifelse(is.na(Ret),0,Ret)) - 1), by=.(Ticker, ym)]
mon <- merge(mon, mret, by=c("Ticker","ym"), all.x=TRUE)
setorder(mon, Ticker, Date)
# forward 1M return (next month's monthly return) — PIT: score at t maps to t+1 return
mon[, Ret_1m := shift(mret, type="lead"), by=Ticker]
# momentum: M03/M06/M12 from monthly Close ratio (price up to sig_date only)
mon[, c3 := shift(Close, 3), by=Ticker]
mon[, c6 := shift(Close, 6), by=Ticker]
mon[, c12 := shift(Close, 12), by=Ticker]
mon[, M03 := Close/c3 - 1]
mon[, M06 := Close/c6 - 1]
mon[, M12 := Close/c12 - 1]
mon[, sig_date := Date]
log("monthly panel rows: %d", nrow(mon))

# ---------- 3. eligibility ----------
mon[, eligible := (K200==1 | KQ150==1) & AdminStock==0 & TradingHalt==0 &
      (is.na(UnfaithfulDisc) | UnfaithfulDisc==0) & !is.na(adv20) & adv20 >= 2e8]

# ---------- 4. PIT asof-join TTM buyback ----------
# for each (Ticker, sig_date) take latest buyback row with Factor_Date <= sig_date
asof_buyback <- function(sb_long, valcol) {
  x <- sb_long[, .(Ticker, Factor_Date, val=get(valcol))]
  x <- x[!is.na(val)]
  setkey(x, Ticker, Factor_Date)
  m <- mon[, .(Ticker, sig_date)]
  setkey(m, Ticker, sig_date)
  j <- x[m, on=.(Ticker, Factor_Date=sig_date), roll=TRUE,
         .(Ticker, sig_date=Factor_Date, val)]
  j
}
b4 <- asof_buyback(sb,"SBB_ttm"); setnames(b4,"val","SBB_ttm")
b2 <- asof_buyback(sb,"SBB_2q");  setnames(b2,"val","SBB_2q")
b8 <- asof_buyback(sb,"SBB_8q");  setnames(b8,"val","SBB_8q")
mon <- merge(mon, b4, by=c("Ticker","sig_date"), all.x=TRUE)
mon <- merge(mon, b2, by=c("Ticker","sig_date"), all.x=TRUE)
mon <- merge(mon, b8, by=c("Ticker","sig_date"), all.x=TRUE)
mon[is.na(SBB_ttm), SBB_ttm := 0]; mon[is.na(SBB_2q), SBB_2q := 0]; mon[is.na(SBB_8q), SBB_8q := 0]

# ---------- 5. signals ----------
mon[, ByYield   := pmin(pmax(SBB_ttm / Size, 0), 0.5)]
mon[, ByYield2q := pmin(pmax(SBB_2q  / Size, 0), 0.5)]
mon[, ByYield8q := pmin(pmax(SBB_8q  / Size, 0), 0.5)]
mon[, ByRaw     := pmax(SBB_ttm, 0)]               # un-normalized (ablation iii)

# confirm gates: M03/M06/M12 > cross-sectional median over ELIGIBLE universe per month
add_confirm <- function(dt, mcol, outcol) {
  dt[eligible==TRUE & !is.na(get(mcol)), med := median(get(mcol), na.rm=TRUE), by=sig_date]
  dt[, med := med[which(!is.na(med))[1]], by=sig_date]
  dt[, (outcol) := as.integer(!is.na(get(mcol)) & get(mcol) > med)]
  dt[, med := NULL]
}
add_confirm(mon,"M03","conf3")
add_confirm(mon,"M06","conf6")
add_confirm(mon,"M12","conf12")

# scores
mon[, score_conf   := ByYield * conf3]             # BASE
mon[, score_nogate := ByYield]                     # ablation i
mon[, score_raw    := ByRaw  * conf3]              # ablation iii (raw KRW * gate)
mon[, score_m06    := ByYield * conf6]             # ablation iv
mon[, score_m12    := ByYield * conf12]
mon[, score_2q     := ByYield2q * conf3]
mon[, score_8q     := ByYield8q * conf3]

# restrict to eligible & period
panel <- mon[eligible==TRUE & sig_date >= START_DATE & !is.na(Ret_1m)]
log("eligible panel rows (>=2005, Ret_1m present): %d  months %d",
    nrow(panel), length(unique(panel$sig_date)))

# ---------- 6. gate fill-frequency & n_active ----------
gate_stats <- panel[, .(
  n_elig = .N,
  n_buyback_pos = sum(ByYield > 0),
  n_active = sum(score_conf > 0)          # buyback>0 AND M03>median
), by=sig_date]
gate_stats[, fill_needed := pmax(0, 25 - n_active)]   # names short of 25 after gate
log("median n_active/mo: %.0f  | months n_active<25: %d / %d  | months n_active<15: %d",
    median(gate_stats$n_active), sum(gate_stats$n_active<25), nrow(gate_stats), sum(gate_stats$n_active<15))
fwrite(gate_stats, file.path(OUT,"gate_fill_frequency.csv"))

# ---------- 7. inputs for canonical_screen_bt ----------
bench <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bench[, Date := as.Date(Date)]
bench <- bench[, .(Date, BM_Ret)]
# align bench to month-end sig_date: compound daily BM_Ret within each FORWARD month?
# canonical contract expects BM_Ret aligned to the same Date key as the forward port return.
# Build monthly forward BM return matching Ret_1m alignment:
bench[, ym := format(Date, "%Y-%m")]
bm_mon <- bench[, .(bm = prod(1 + ifelse(is.na(BM_Ret),0,BM_Ret)) - 1), by=ym]
# map sig_date -> forward month bm
mon_ym_map <- unique(mon[, .(sig_date, ym)])
setorder(mon_ym_map, sig_date)
mon_ym_map[, ym_fwd := shift(ym, type="lead")]      # forward month label per sig_date (global month sequence)
# better: forward month = month after sig_date's month
allmonths <- sort(unique(mon$ym))
ymnext <- data.table(ym=allmonths, ym_fwd=shift(allmonths, type="lead"))
sig_map <- unique(mon[, .(sig_date, ym)])
sig_map <- merge(sig_map, ymnext, by="ym", all.x=TRUE)
sig_map <- merge(sig_map, bm_mon, by.x="ym_fwd", by.y="ym", all.x=TRUE)
bench_dt <- unique(sig_map[, .(Date=sig_date, BM_Ret=bm)])[!is.na(BM_Ret)]

returns_dt <- panel[, .(Date=sig_date, Ticker, Ret_1m)]
liq_dt     <- panel[, .(Date=sig_date, Ticker, adv=adv20)]

run_screen <- function(scorecol, top_n=25L) {
  sc <- panel[get(scorecol) > 0, .(Date=sig_date, Ticker, score=get(scorecol))]
  if (nrow(sc) < 50) return(NULL)
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n=top_n, cost_bps_oneway=15,
                      liq_dt=liq_dt, liq_min=2e8)
}

# ---------- 8. canonical screens (BASE + ablations + concentration) ----------
res <- list()
res$base_top25    <- run_screen("score_conf", 25L)
res$base_top15    <- run_screen("score_conf", 15L)
res$nogate_top25  <- run_screen("score_nogate", 25L)
res$raw_top25     <- run_screen("score_raw", 25L)
res$m06_top25     <- run_screen("score_m06", 25L)
res$m12_top25     <- run_screen("score_m12", 25L)
res$ttm2q_top25   <- run_screen("score_2q", 25L)
res$ttm8q_top25   <- run_screen("score_8q", 25L)

summ <- rbindlist(lapply(names(res), function(nm){
  r <- res[[nm]]; if (is.null(r)) return(data.table(variant=nm, n_months=NA))
  data.table(variant=nm, n_months=r$n_months,
             PORT_t=r$portfolio_alpha_t_nw_lag3, IR=r$information_ratio,
             alpha_ann=r$alpha_annualized, net_sr=r$net_sr,
             turnover_ann=r$turnover_annual, mean_active=r$mean_active_net)
}), fill=TRUE)
print(summ)
fwrite(summ, file.path(OUT,"variant_summary.csv"))

# ---------- 9. DECILE TEST (make-or-break) ----------
# per month: drop score==0, rank into deciles over active subset, forward EW net active
decile_panel <- panel[score_conf > 0]
decile_panel[, dec := {
  n <- .N
  if (n < 10) rep(NA_integer_, n) else as.integer(cut(frank(score_conf, ties.method="first"),
        breaks=quantile(frank(score_conf,ties.method="first"), probs=seq(0,1,0.1)),
        include.lowest=TRUE, labels=FALSE))
}, by=sig_date]
decile_panel <- decile_panel[!is.na(dec)]
# EW decile forward net return (15bps on monthly turnover approximated by full rebalance => apply via canonical per decile)
# Build decile-as-portfolio via canonical_screen_bt for D10 PORT_t (contract-grade)
decile_profile <- decile_panel[, .(
  n=.N, mean_fwd=mean(Ret_1m, na.rm=TRUE)
), by=.(sig_date, dec)]
# merge bm
decile_profile <- merge(decile_profile, bench_dt, by.x="sig_date", by.y="Date", all.x=TRUE)
decile_profile[, active := mean_fwd - BM_Ret]
dec_summary <- decile_profile[, .(
  mean_active_monthly = mean(active, na.rm=TRUE),
  ann_active = mean(active, na.rm=TRUE)*12,
  hit_rate = mean(active>0, na.rm=TRUE),
  n_months = .N
), by=dec][order(dec)]
print(dec_summary)
fwrite(dec_summary, file.path(OUT,"decile_profile.csv"))
# monotonicity: Spearman corr of dec vs mean_active
mono <- suppressWarnings(cor(dec_summary$dec, dec_summary$mean_active_monthly, method="spearman"))
log("decile monotonicity (spearman dec vs active): %.3f", mono)

# D10 PORT_t via contract (decile 10 as portfolio of ALL its names EW each month)
d10_scores <- decile_panel[dec==10, .(Date=sig_date, Ticker, score=score_conf)]
d10_screen <- canonical_screen_bt(d10_scores, returns_dt, bench_dt, top_n=999L,
                                  cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8)
log("D10 PORT_t (all D10 names EW): %.3f  IR %.3f  net_sr %.3f",
    d10_screen$portfolio_alpha_t_nw_lag3, d10_screen$information_ratio, d10_screen$net_sr)
d9_scores <- decile_panel[dec==9, .(Date=sig_date, Ticker, score=score_conf)]
d9_screen <- canonical_screen_bt(d9_scores, returns_dt, bench_dt, top_n=999L,
                                  cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8)

# D10-D9 gap series NW t-stat
d10ser <- d10_screen$period_returns[, .(Date=date, r10=ret_net - benchmark_ret)]
d9ser  <- d9_screen$period_returns[, .(Date=date, r9=ret_net - benchmark_ret)]
gap <- merge(d10ser, d9ser, by="Date")
gap[, g := r10 - r9]
nw_t <- function(x) {
  x <- x[!is.na(x)]; n <- length(x); if (n<10) return(NA)
  m <- mean(x); fit <- tryCatch(lm(x ~ 1), error=function(e) NULL); if(is.null(fit)) return(NA)
  # NW lag-3
  cv <- tryCatch(sandwich::NeweyWest(fit, lag=3, prewhite=FALSE), error=function(e) NA)
  if (all(is.na(cv))) return(m/(sd(x)/sqrt(n)))
  m / sqrt(cv[1,1])
}
gap_t <- tryCatch(nw_t(gap$g), error=function(e) NA)
log("D10-D9 gap mean %.5f  NW-t %.3f", mean(gap$g,na.rm=TRUE), gap_t)

# ---------- 10. spike-survival: fresh-disclosure vs carry months ----------
# fresh month = month where sig_date is within ~45-75d after a Factor_Date (first carry)
# determine for D10 names whether their as-of buyback Factor_Date is the latest <= sig_date and "new"
sb_fd <- sb[Value>0 | SBB_ttm>0, .(Ticker, Factor_Date)]
# for each D10 (Ticker, sig_date) find latest Factor_Date <= sig_date and months since
d10n <- decile_panel[dec==10, .(Ticker, sig_date)]
setkey(sb_fd, Ticker, Factor_Date); setkey(d10n, Ticker, sig_date)
d10fd <- sb_fd[d10n, on=.(Ticker, Factor_Date=sig_date), roll=TRUE, .(Ticker, sig_date=Factor_Date, fd=x.Factor_Date)]
# need original fd; redo with mult
d10fd <- d10n[, {
  fds <- sb_fd[Ticker==.BY$Ticker & Factor_Date <= sig_date, Factor_Date]
  .(fd = if(length(fds)) max(fds) else as.Date(NA))
}, by=.(Ticker, sig_date)]
d10fd[, mons_since := as.integer(round(as.numeric(sig_date - fd)/30.44))]
d10fd[, cohort := ifelse(mons_since<=1, "fresh", "carry")]
d10ret <- merge(decile_panel[dec==10, .(Ticker, sig_date, Ret_1m)], d10fd, by=c("Ticker","sig_date"))
d10ret <- merge(d10ret, bench_dt, by.x="sig_date", by.y="Date", all.x=TRUE)
d10ret[, active := Ret_1m - BM_Ret]
spike <- d10ret[!is.na(cohort), .(mean_active=mean(active,na.rm=TRUE), n=.N), by=cohort]
print(spike)
fwrite(spike, file.path(OUT,"spike_survival.csv"))

# ---------- 11. orthogonality (active basis) ----------
kf <- as.data.table(read_parquet(".cache/kr_factor_returns_v2.parquet"))
kf[, Date := as.Date(Date)]
base_active <- res$base_top25$period_returns[, .(Date=date, a_base=ret_net - benchmark_ret)]
# kr factor dates are month-end; align by year-month
base_active[, ym := format(Date, "%Y-%m")]
kf[, ym := format(Date, "%Y-%m")]
ortho_in <- merge(base_active, kf[, .(ym, MKT, SMB, HML, WML, RMW, CMA)], by="ym")
ortho <- list(
  n = nrow(ortho_in),
  corr_WML_momentum = cor(ortho_in$a_base, ortho_in$WML, use="complete.obs"),
  corr_HML_value    = cor(ortho_in$a_base, ortho_in$HML, use="complete.obs"),
  corr_SMB_size     = cor(ortho_in$a_base, ortho_in$SMB, use="complete.obs"),
  corr_MKT          = cor(ortho_in$a_base, ortho_in$MKT, use="complete.obs"),
  corr_RMW          = cor(ortho_in$a_base, ortho_in$RMW, use="complete.obs"),
  corr_CMA          = cor(ortho_in$a_base, ortho_in$CMA, use="complete.obs")
)
# vs unconfirmed buyback screen (incremental test)
nogate_active <- res$nogate_top25$period_returns[, .(Date=date, a_ng=ret_net - benchmark_ret)]
inc <- merge(base_active, nogate_active, by="Date")
ortho$corr_vs_unconfirmed <- cor(inc$a_base, inc$a_ng, use="complete.obs")
print(ortho)

# ---------- 12. rank-IC / ICIR / Harvey-t ----------
ic_dt <- panel[score_conf > 0, .(Ticker, sig_date, score=score_conf, Ret_1m)]
ic_by_month <- ic_dt[, .(ic = if(.N>=5) cor(score, Ret_1m, method="spearman", use="complete.obs") else NA_real_), by=sig_date]
ic_by_month <- ic_by_month[!is.na(ic)]
rank_ic <- mean(ic_by_month$ic)
icir <- rank_ic / sd(ic_by_month$ic)
harvey_t <- rank_ic / (sd(ic_by_month$ic)/sqrt(nrow(ic_by_month)))
log("rank_IC %.4f  ICIR %.3f  Harvey-t %.3f  (n_months %d)", rank_ic, icir, harvey_t, nrow(ic_by_month))

# sector-neutral rank-IC (RF-A4): demean score & Ret within sector per month, then IC
sn <- panel[score_conf > 0 & !is.na(Sector)]
sn[, score_sn := score_conf - mean(score_conf), by=.(sig_date, Sector)]
sn[, ret_sn   := Ret_1m   - mean(Ret_1m),   by=.(sig_date, Sector)]
ic_sn_m <- sn[, .(ic = if(.N>=5) cor(score_sn, ret_sn, method="spearman", use="complete.obs") else NA_real_), by=sig_date]
ic_sn_m <- ic_sn_m[!is.na(ic)]
rank_ic_sn <- mean(ic_sn_m$ic); icir_sn <- rank_ic_sn / sd(ic_sn_m$ic)
log("sector-neutral rank_IC %.4f  ICIR %.3f  (n %d)", rank_ic_sn, icir_sn, nrow(ic_sn_m))

# subperiod stability (3 windows)
ic_by_month[, era := fifelse(sig_date < as.Date("2013-01-01"),"P1",
                      fifelse(sig_date < as.Date("2020-01-01"),"P2","P3"))]
sub <- ic_by_month[, .(ic=mean(ic), n=.N), by=era][order(era)]
print(sub)
sub_stab <- mean(sub$ic > 0)

# ---------- 13. oos_retention (anchored 55/65/75 median) ----------
base_ser <- res$base_top25$period_returns[, .(Date=date, active=ret_net - benchmark_ret)]
setorder(base_ser, Date)
n <- nrow(base_ser)
oos_ret_split <- function(frac){
  k <- floor(n*frac)
  is_sr <- mean(base_ser$active[1:k])/sd(base_ser$active[1:k])*sqrt(12)
  oos_sr <- mean(base_ser$active[(k+1):n])/sd(base_ser$active[(k+1):n])*sqrt(12)
  if (is_sr <= 0) return(NA)
  oos_sr / is_sr
}
oos_vals <- sapply(c(0.55,0.65,0.75), oos_ret_split)
oos_retention <- median(oos_vals, na.rm=TRUE)
log("oos_retention (median 55/65/75): %.3f  [%s]", oos_retention, paste(round(oos_vals,3),collapse=","))

# calmar from base series
cum <- cumprod(1 + base_ser$active)
dd <- 1 - cum/cummax(cum)
mdd <- max(dd)
cagr_active <- prod(1+base_ser$active)^(12/n) - 1
calmar <- cagr_active / mdd

# ---------- save scores parquet + validation json ----------
# RF-A5: top-decile (D10) liquidity distribution — is the top a micro-cap basket?
d10liq <- merge(decile_panel[dec==10, .(Ticker, sig_date)], panel[, .(Ticker, sig_date, adv20, Size)],
                by=c("Ticker","sig_date"))
liq_q <- quantile(d10liq$adv20, c(0.1,0.5,0.9), na.rm=TRUE)
size_q <- quantile(d10liq$Size, c(0.1,0.5,0.9), na.rm=TRUE)
log("D10 adv20 p10/p50/p90: %.2e / %.2e / %.2e  | frac adv<5e8: %.2f",
    liq_q[1], liq_q[2], liq_q[3], mean(d10liq$adv20<5e8, na.rm=TRUE))
log("D10 Size  p10/p50/p90: %.2e / %.2e / %.2e", size_q[1], size_q[2], size_q[3])

scores_out <- panel[, .(Date=sig_date, Ticker, score_conf, ByYield, conf3, M03, SBB_ttm, Size, Ret_1m)]
write_parquet(scores_out, file.path(OUT,"alpha_scores.parquet"))

saveRDS(list(summ=summ, dec_summary=dec_summary, d10_PORT_t=d10_screen$portfolio_alpha_t_nw_lag3,
  d10_IR=d10_screen$information_ratio, d10_netsr=d10_screen$net_sr,
  gap_mean=mean(gap$g,na.rm=TRUE), gap_t=gap_t, mono=mono, spike=spike, ortho=ortho,
  rank_ic=rank_ic, icir=icir, harvey_t=harvey_t, rank_ic_sn=rank_ic_sn, icir_sn=icir_sn, sub=sub, sub_stab=sub_stab,
  oos_retention=oos_retention, oos_vals=oos_vals, calmar=calmar, mdd=mdd, cagr_active=cagr_active,
  gate_stats=gate_stats, base=res$base_top25, base15=res$base_top15,
  d10_liq_q=liq_q, d10_size_q=size_q, d10_frac_illiq=mean(d10liq$adv20<5e8,na.rm=TRUE)),
  file.path(OUT,"results.rds"))

log("=== DONE ===")
