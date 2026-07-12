#==============================================================================
# N2 / FQ-021 delta_ext — Step 20: Delta m1 (change axis) full measurement
# FROZEN prereg sha256 = 4bdda5f82fcdf70f47eff42dd253033802410f13d2864db7a26abe406cbde926
# chain of Phase A (WT-D20260711_002). selection_type=chain. n_trials cumulative=11.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
set.seed(20260713)
ROOT  <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT   <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
DEXT  <- file.path(OUT, "delta_ext")
CACHE <- file.path(OUT, "text_cache")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

ym_add <- function(ym, k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym%/%100L, ym%%100L))
spear <- function(x,y){ ok<-is.finite(x)&is.finite(y); if(sum(ok)<3) return(NA_real_)
  suppressWarnings(tryCatch(cor(x[ok],y[ok],method="spearman"), error=function(e) NA_real_)) }
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<8) return(NA_real_)
  mu<-mean(x); e<-x-mu; g0<-sum(e^2)/n; v<-g0
  for(L in 1:min(lag,n-1)){ w<-1-L/(lag+1); g<-sum(e[1:(n-L)]*e[(L+1):n])/n; v<-v+2*w*g }
  se<-sqrt(v/n); if(!is.finite(se)||se<=0) return(NA_real_); mu/se }
zc <- function(v){ s<-sd(v,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(0,length(v))); (v-mean(v,na.rm=TRUE))/s }

# ---- 1. corp-year m1 from text_cache -> delta_m1 (consecutive pairs) ----
parts <- list.files(CACHE, pattern="^metrics_part_.*\\.parquet$", full.names=TRUE)
M <- rbindlist(lapply(parts, function(p) as.data.table(read_parquet(p))), fill=TRUE)
M <- unique(M, by="rcept_no")
M <- M[status=="ok" & !is.na(m1_avg_sentence_len_chars)]
M[, rcept_ym := as.integer(substr(rcept_dt,1,4))*100L + as.integer(substr(rcept_dt,5,6))]
setorder(M, Ticker, fy)
M[, `:=`(fy_prev = shift(fy,1L), m1_prev = shift(m1_avg_sentence_len_chars,1L)), by=Ticker]
M[, delta_m1 := fifelse(!is.na(fy_prev) & (fy - fy_prev == 1L),
                        m1_avg_sentence_len_chars - m1_prev, NA_real_)]
D <- M[!is.na(delta_m1), .(Ticker, fy, rcept_ym,
                          m1_level = m1_avg_sentence_len_chars, delta_m1)]
D[, active_from := ym_add(rcept_ym, 1L)]
cat("[20] delta_m1 doc-level obs:", nrow(D), " tickers:", uniqueN(D$Ticker),
    " fy:", min(D$fy),"-",max(D$fy), "\n")

# ---- 2. monthly panel + forward returns (identical to Phase A) ----
mp <- readRDS(file.path(OUT,"monthly_panel.rds")); me<-mp$me; bench<-mp$bench_m
ret_at_t   <- me[, .(Ticker, ym=ym_add(ym,-1L), Ret_1m=mret)]        # ret realized t+1 attributed to t
bench_at_t <- bench[, .(ym=ym_add(ym,-1L), BM_Ret=bench_mret)]
returns_all<- ret_at_t[, .(Date=ym2date(ym), Ticker, Ret_1m)]
bench_all  <- bench_at_t[, .(Date=ym2date(ym), BM_Ret)]
size_all   <- me[, .(Date=ym2date(ym), Ticker, Size)]
liq_all    <- me[, .(Date=ym2date(ym), Ticker, adv=adv20)]
elig <- me[, .(Ticker, ym, Size, adv20, K200, KQ150)]
months <- sort(unique(me$ym)); months <- months[months>=201101 & months<=202506]

# ---- 3. build carried monthly panel for a given carry window ----
build_panel <- function(carry_m){
  setorder(D, Ticker, active_from)
  pl <- list()
  for (t in months) {
    a <- D[active_from<=t]
    if (nrow(a)==0) next
    a <- copy(a)
    a[, age := ((t%/%100L)*12L + t%%100L) - ((active_from%/%100L)*12L + active_from%%100L)]
    a <- a[age<=carry_m]
    if (nrow(a)==0) next
    a <- a[order(Ticker,-active_from)][, .SD[1], by=Ticker]  # latest active
    a[, ym := t]
    pl[[as.character(t)]] <- a[, .(Ticker, ym, m1_level, delta_m1, age)]
  }
  P <- rbindlist(pl)
  P <- merge(P, elig, by=c("Ticker","ym"))
  P <- P[(K200==1|KQ150==1) & !is.na(adv20) & adv20>=2e8 & !is.na(Size) & Size>0]
  P <- merge(P, ret_at_t, by=c("Ticker","ym"), all.x=TRUE)
  P <- merge(P, bench_at_t, by="ym", all.x=TRUE)
  P[, fwd_excess := Ret_1m - BM_Ret]
  P[, logSize := log(Size)]
  # per-month cross-sectional constructs
  P[, z_delta := zc(delta_m1), by=ym]
  # residual: delta_m1 residualized on level m1 (per month OLS); NA-safe
  P[, resid_delta := {
    x <- m1_level; y <- delta_m1; ok <- is.finite(x)&is.finite(y)
    r <- rep(NA_real_, .N)
    if (sum(ok) >= 5) { fit <- lm(y[ok]~x[ok]); r[ok] <- residuals(fit) }
    r
  }, by=ym]
  P[, z_resid := zc(resid_delta), by=ym]
  P
}

# ---- 4. canonical runner (dual-basis) ----
run_canon <- function(scores_dt, dsub, tag){
  sc <- scores_dt[Date %in% dsub]
  canonical_screen_bt(sc, returns_all, bench_all, top_n=25L, cost_bps_oneway=15,
    liq_dt=liq_all, liq_min=2e8, size_dt=size_all, diag_dual_basis=TRUE,
    run_id=paste0("wt002dx_",tag), strategy_id=paste0("delta_m1_",tag))
}
pick <- function(c) list(n_months=c$n_months, port_t=round(c$portfolio_alpha_t_nw_lag3,3),
  pval=round(c$portfolio_alpha_t_pvalue,4), IR=round(c$information_ratio,3),
  net_sr=round(c$net_sr,3), alpha_ann=round(c$alpha_annualized,4),
  turnover=round(c$turnover_annual,3),
  ew_port_t=round(c$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),
  ew_post2017_t=round(c$diag_ew_universe$post2017_t_nw_lag3,3),
  ew_oos=round(c$diag_ew_universe$oos_retention_approx,3),
  mega_w=round(c$diag_cap_tier$weight_share_avg$MEGA,3),
  mid_w=round(c$diag_cap_tier$weight_share_avg$MID,3),
  other_w=round(c$diag_cap_tier$weight_share_avg$OTHER,3))

# ---- 5. run all 4 configs ----
cfgs <- list(
  c1=list(form="raw_delta_z",   carry=12L, scorevar="z_delta"),
  c2=list(form="residual_delta",carry=12L, scorevar="z_resid"),
  c3=list(form="raw_delta_z",   carry=6L,  scorevar="z_delta"),
  c4=list(form="residual_delta",carry=6L,  scorevar="z_resid"))
results <- list(); panels <- list()
for (cn in names(cfgs)) {
  cf <- cfgs[[cn]]
  P <- build_panel(cf$carry); panels[[cn]] <- P
  sv <- cf$scorevar
  # score_for_long = -z(signal) : worsening (higher delta) -> lower long score
  scores_dt <- P[is.finite(get(sv)), .(Date=ym2date(ym), Ticker, score = -get(sv))]
  alldates <- sort(unique(scores_dt$Date))
  is_d  <- alldates[alldates <  as.Date("2019-01-01")]
  oos_d <- alldates[alldates >= as.Date("2019-01-01")]
  cf_full <- run_canon(scores_dt, alldates, paste0(cn,"_full"))
  cf_is   <- run_canon(scores_dt, is_d,     paste0(cn,"_IS"))
  cf_oos  <- run_canon(scores_dt, oos_d,    paste0(cn,"_OOS"))
  # rank-IC of the RAW signal (delta_m1 for raw; resid_delta for residual) vs fwd excess
  icvar <- if (cf$form=="raw_delta_z") "delta_m1" else "resid_delta"
  ics <- P[!is.na(fwd_excess) & is.finite(get(icvar)),
           .(ic=spear(get(icvar), fwd_excess), n=.N), by=ym][n>=10 & is.finite(ic)]
  results[[cn]] <- list(cfg=cf,
    avg_names_mo = round(nrow(P)/uniqueN(P$ym),1), signal_months=uniqueN(P$ym), n_obs=nrow(P),
    rank_ic_mean=round(mean(ics$ic),4), icir=round(mean(ics$ic)/sd(ics$ic),3),
    rank_ic_harvey_t=round(nw_t(ics$ic),3), rank_ic_nmonths=nrow(ics),
    canon_full=cf_full, canon_is=cf_is, canon_oos=cf_oos,
    full=pick(cf_full), IS=pick(cf_is), OOS=pick(cf_oos))
  cat(sprintf("\n[20] === %s (%s, carry=%dm) === names/mo=%.1f  rank-IC=%.4f Ht=%.2f (nmo=%d)\n",
    cn, cf$form, cf$carry, results[[cn]]$avg_names_mo, results[[cn]]$rank_ic_mean,
    results[[cn]]$rank_ic_harvey_t, results[[cn]]$rank_ic_nmonths))
  cat("  FULL:"); print(results[[cn]]$full)
  cat("  IS  :"); print(results[[cn]]$IS)
  cat("  OOS :"); print(results[[cn]]$OOS)
}

# ---- 6. Size control + market split + adv tercile on PRIMARY (c1 raw delta 12m) ----
Pc1 <- panels[["c1"]]
sc_ctrl <- Pc1[!is.na(fwd_excess) & is.finite(delta_m1) & is.finite(logSize)]
ic_raw   <- sc_ctrl[, .(ic=spear(delta_m1, fwd_excess), n=.N), by=ym][n>=10 & is.finite(ic)]
# partial rank-IC given logSize: residualize both ranks then correlate
partial_ic <- sc_ctrl[, {
  if(.N>=10){
    rx<-rank(delta_m1); ry<-rank(fwd_excess); rz<-rank(logSize)
    ex<-residuals(lm(rx~rz)); ey<-residuals(lm(ry~rz))
    .(pic=suppressWarnings(cor(ex,ey)), n=.N)
  } else .(pic=NA_real_, n=.N)
}, by=ym][n>=10 & is.finite(pic)]
cor_delta_size <- sc_ctrl[, .(c=spear(delta_m1, logSize)), by=ym][is.finite(c), mean(c)]
size_ctrl <- list(
  raw_ic=round(mean(ic_raw$ic),4), raw_harvey_t=round(nw_t(ic_raw$ic),3),
  partial_ic_given_logSize=round(mean(partial_ic$pic),4),
  partial_harvey_t=round(nw_t(partial_ic$pic),3),
  cor_delta_logSize=round(cor_delta_size,3))
cat("\n[20] === Size control (PRIMARY c1) ===\n"); print(size_ctrl)

mkt_split <- list(
  K200_Ht = round(nw_t(sc_ctrl[K200==1, .(ic=spear(delta_m1,fwd_excess),n=.N), by=ym][n>=10&is.finite(ic)]$ic),3),
  KQ150_Ht= round(nw_t(sc_ctrl[KQ150==1,.(ic=spear(delta_m1,fwd_excess),n=.N), by=ym][n>=10&is.finite(ic)]$ic),3))
cat("[20] === market split (PRIMARY c1) ===\n"); print(mkt_split)

# ---- 7. placebo: month-shuffle signal labels within cross-section (200 draws) on PRIMARY c1 ----
placebo <- function(Ptab, sigvar, ndraw=200){
  base <- Ptab[!is.na(fwd_excess) & is.finite(get(sigvar))]
  obs  <- mean(base[, .(ic=spear(get(sigvar), fwd_excess), n=.N), by=ym][n>=10&is.finite(ic)]$ic)
  null <- numeric(ndraw)
  for(d in 1:ndraw){
    B <- copy(base)
    B[, sperm := sample(get(sigvar)), by=ym]   # shuffle signal within month (breaks signal-return link)
    null[d] <- mean(B[, .(ic=spear(sperm, fwd_excess), n=.N), by=ym][n>=10&is.finite(ic)]$ic)
  }
  list(obs_mean_ic=round(obs,4), null_sd=round(sd(null),4),
       p_two_sided=round(mean(abs(null)>=abs(obs)),4))
}
plc_c1 <- placebo(Pc1, "delta_m1", 200)
cat("\n[20] === placebo (PRIMARY c1 raw delta, 200 draws) ===\n"); print(plc_c1)

# ---- 8. delta-vs-level independence test (does residual retain PORT_t?) ----
indep <- list(
  raw_delta_12m_full_port_t   = results$c1$full$port_t,
  resid_delta_12m_full_port_t = results$c2$full$port_t,
  raw_delta_12m_rankic_Ht     = results$c1$rank_ic_harvey_t,
  resid_delta_12m_rankic_Ht   = results$c2$rank_ic_harvey_t,
  interpretation = "if residual (c2) collapses vs raw (c1) -> change signal = level in disguise (not independent). if residual survives -> change adds orthogonal info.")
cat("\n[20] === delta-vs-level independence ===\n"); print(indep)

# ---- 9. null max-t across delta family (4 configs rank-IC) + phase-A context ----
delta_family_Ht <- sapply(names(results), function(cn) abs(results[[cn]]$rank_ic_harvey_t))
null_max_t_delta <- max(delta_family_Ht, na.rm=TRUE)
cat("\n[20] delta family null max |Harvey-t|:", round(null_max_t_delta,3),
    " (Phase A family max was 2.804 on level m1)\n")

# ---- 10. save ----
saveRDS(list(results=results, size_ctrl=size_ctrl, mkt_split=mkt_split,
             placebo_c1=plc_c1, independence=indep, null_max_t_delta=null_max_t_delta,
             D_docs=nrow(D), D_tickers=uniqueN(D$Ticker)),
        file.path(DEXT,"delta_results.rds"))
# alpha_scores latest cross-section (primary c1)
last_ym <- max(Pc1$ym)
as_out <- Pc1[ym==last_ym, .(Ticker, m1_level, delta_m1, z_delta, score=-z_delta, ym)]
write_parquet(as_out, file.path(DEXT,"alpha_scores_delta.parquet"))
cat("\n[20] DONE. delta docs:", nrow(D), " alpha_scores latest ym:", last_ym, " N:", nrow(as_out), "\n")
