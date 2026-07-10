# WT-D20260710_004 B1 PROMOTE-only — event-boundary tie-break substitution A/B
# Spec-frozen: b1_spec.json sha256 fe197763d63cff8bbc1b4bab221a4091f1c1c9453f2a826c8e34fc8eece7904e
# n_trials = 2 (P1 band21-30, P2 band21-40). metric_type=canonical_screen (screen/diag tier).
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); options(scipen=999)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR=ROOT, QM_ROOT=ROOT)
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_004")
source(file.path(ROOT,"02_Infrastructure","config.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","canonical_screen_bt.R"))
source(file.path(ROOT,"02_Infrastructure","validation","overlay_pit_guard.R"))
source(file.path(ROOT,"02_Infrastructure","data","pin_cache.R"))
nwt <- function(x, lag=3L) if(length(x)>=6) .nw_t_mean(x, lag=lag) else NA_real_

SPEC_SHA <- "fe197763d63cff8bbc1b4bab221a4091f1c1c9453f2a826c8e34fc8eece7904e"
OUT <- list(spec_sha256=SPEC_SHA, run_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
            metric_type="canonical_screen", n_trials=2L)

## ---------- vintage pin ----------
PIN_TAG <- format(Sys.time(),"wt004B1_%Y%m%d_%H%M%S")
pin_cache(c(file.path(ROOT,".cache","benchmark.parquet"),
            file.path(ROOT,".cache","dart","buyback_decisions_clean.parquet")), PIN_TAG)
OUT$pin_tag <- PIN_TAG
BM_PIN <- read_pinned(file.path(ROOT,".cache","benchmark.parquet"), PIN_TAG)
BB_PIN <- read_pinned(file.path(ROOT,".cache","dart","buyback_decisions_clean.parquet"), PIN_TAG)

## ---------- inputs (Stage A parity asserts) ----------
PANEL_F <- file.path(ROOT,"stage_artifacts","WT-D20260710_001","panel.rds")
pmd5 <- unname(tools::md5sum(PANEL_F))
stopifnot(pmd5 == "775f40656711b717024b2fe104aaf872")   # Stage A parity
OUT$panel_md5 <- pmd5
panel <- as.data.table(readRDS(PANEL_F))
all_dates <- sort(unique(panel$Date))

bm <- as.data.table(read_parquet(BM_PIN)); bm[, Dt:=as.Date(Date)]; bm[, ym:=format(Dt,"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_m <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
bm_m[, Date:=as.Date(paste0(ym,"-01"))]; bm_m[, bm_fwd:=shift(bm_ret,type="lead",n=1L)]
benchdt <- bm_m[!is.na(bm_fwd), .(Date, BM_Ret=bm_fwd)]

returns_dt <- panel[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]

## ---------- beta-scan alignment sanity (holding month = month(Date)+1 convention) ----------
ewm <- returns_dt[, .(mret=mean(Ret_1m)), by=Date][order(Date)]
scan <- sapply(-1:2, function(off){
  b <- copy(bm_m)[, DateX := as.Date(paste0(ym,"-01"))]
  b[, key := { y<-as.integer(format(DateX,"%Y")); m<-as.integer(format(DateX,"%m")) - off
               y2<-y+(m-1)%/%12; m2<-((m-1)%%12)+1; sprintf("%04d-%02d", y2, m2) }]
  m <- merge(ewm[,.(key=format(Date,"%Y-%m"), mret)], b[,.(key,bm_ret)], by="key")
  cor(m$mret, m$bm_ret)
})
names(scan) <- paste0("offset", -1:2)
OUT$alignment_beta_scan <- as.list(round(scan,4))
stopifnot(which.max(scan) == which(names(scan)=="offset1"))  # Ret_1m at Date = month(Date)+1 return
cat("[align] beta-scan cor:", paste(names(scan), round(scan,3), collapse=" "), "-> offset+1 max OK\n")

## ---------- ranks / band / events ----------
S <- panel[!is.na(score_eff), .(Date,Ticker,score=score_eff,adv=tv20)]
S <- S[is.na(adv) | adv>=2e8]
setorder(S, Date, -score); S[, rk:=seq_len(.N), by=Date]

bb <- as.data.table(read_parquet(BB_PIN))
bb[, rcept_dt := as.Date(substr(rcept_no,1,8), format="%Y%m%d")]
bb <- bb[!is.na(rcept_dt) & Ticker %in% unique(panel$Ticker)]
ev <- unique(bb[, .(Ticker, rcept_dt)])[order(Ticker, rcept_dt)]

# roll-join latest prior event at arbitrary cutoff column (Stage A corrected pattern)
attach_ev <- function(dt, cutoff_col){
  evj <- ev[, .(Ticker, ev_dt=rcept_dt, matched_ev=rcept_dt)]; setkey(evj, Ticker, ev_dt)
  x <- copy(dt); x[, jdt := get(cutoff_col)]; setkey(x, Ticker, jdt)
  rj <- evj[x, on=.(Ticker, ev_dt=jdt), roll=TRUE]
  stopifnot(nrow(rj)==nrow(x))
  x[, matched_ev := rj$matched_ev]; x[, jdt:=NULL]; x
}
add_month <- function(d, k=1L){ y<-as.integer(format(d,"%Y")); m<-as.integer(format(d,"%m"))+k
  y2<-y+(m-1L)%/%12L; m2<-((m-1L)%%12L)+1L; as.Date(sprintf("%04d-%02d-01",y2,m2)) }

B <- S[, .(Date,Ticker,rk)]
B[, cut_primary := Date]
B[, cut_ext := add_month(Date,1L) - 1L]          # end of month(Date)  (< holding start, PIT-legal)
B <- attach_ev(B, "cut_primary"); setnames(B, "matched_ev", "ev_primary")
B <- attach_ev(B, "cut_ext");     setnames(B, "matched_ev", "ev_ext")
B[, fresh_primary := !is.na(ev_primary) & as.numeric(Date - ev_primary)/30.44 <= 3]
B[, fresh_ext     := !is.na(ev_ext)     & as.numeric(cut_ext - ev_ext)/30.44 <= 3]
# lag1 stress: fresh flag computed at Date_{t-1} applied at t (shift within ticker over month grid)
FL <- B[, .(Date, Ticker, fresh_primary, ev_primary)]
FL[, Date_next := add_month(Date,1L)]
B <- merge(B, FL[, .(Date=Date_next, Ticker, fresh_lag1=fresh_primary, ev_lag1=ev_primary)],
           by=c("Date","Ticker"), all.x=TRUE)
B[is.na(fresh_lag1), fresh_lag1 := FALSE]

## ---------- membership builders ----------
IS_LO <- as.Date("2015-01-01"); IS_HI <- as.Date("2018-12-01")
K_MAX <- 3L

base_mem <- S[rk<=20, .(Date,Ticker,rk)]

# promotion schedule for a config: per Date, candidates in band with fresh flag, best-rank first, max K
promo_schedule <- function(band_hi, fresh_col, dates_range){
  cand <- B[rk>=21 & rk<=band_hi & get(fresh_col)==TRUE & Date>=dates_range[1] & Date<=dates_range[2]]
  setorder(cand, Date, rk)
  cand[, pos:=seq_len(.N), by=Date]
  cand[pos<=K_MAX, .(Date, Ticker, rk, matched_ev=get(if(fresh_col=="fresh_primary") "ev_primary"
                                                      else if(fresh_col=="fresh_ext") "ev_ext" else "ev_lag1"))]
}

# substituted membership: replace K lowest-ranked incumbents with promoted set
subst_mem <- function(promos, dates_range){
  bm0 <- base_mem[Date>=dates_range[1] & Date<=dates_range[2]]
  if(nrow(promos)==0) return(bm0)
  pk <- promos[, .N, by=Date]
  out <- rbindlist(lapply(split(bm0, by="Date"), function(g){
    d <- g$Date[1]; k <- pk[Date==d, N]
    if(length(k)==0 || k==0) return(g)
    p <- promos[Date==d]
    p <- p[!Ticker %in% g$Ticker]              # already in top-20: skip swap
    k <- nrow(p); if(k==0) return(g)
    setorder(g, rk)
    keep <- g[seq_len(20-k)]
    rbind(keep, p[, .(Date, Ticker, rk)])
  }))
  out
}

# canonical run from explicit membership (score = indicator ordering; exactly 20/Date)
run_mem <- function(mem, label, diag=FALSE){
  sc <- mem[, .(Date, Ticker, score = 100 - pmin(rk, 99))]
  canonical_screen_bt(scores_dt=sc, returns_dt=returns_dt, bench_dt=benchdt,
                      top_n=20L, cost_bps_oneway=15, liq_dt=NULL,
                      run_id=paste0("wt004B1_",label), strategy_id=paste0("wt004B1_",label),
                      periods_per_year=12L, diag_dual_basis=diag)
}

paired_stats <- function(prA, prB){   # A = substituted, B = base
  m <- merge(prA[, .(date, retA=ret_net)], prB[, .(date, retB=ret_net, benchmark_ret)], by="date")
  d <- m$retA - m$retB
  actA <- m$retA - m$benchmark_ret; actB <- m$retB - m$benchmark_ret
  sr <- function(x) if(sd(x)>0) mean(x)/sd(x)*sqrt(12) else NA_real_
  list(n_months=nrow(m), mean_diff_monthly=mean(d), mean_diff_ann=mean(d)*12,
       paired_nw_t_lag3=round(nwt(d),3), n_active_diff_months=sum(abs(d)>1e-12),
       mean_diff_active_only=if(any(abs(d)>1e-12)) mean(d[abs(d)>1e-12]) else NA_real_,
       ir_A=sr(actA), ir_B=sr(actB), d_ir_frame=sr(actA)-sr(actB),
       tot_sr_A=if(sd(m$retA)>0) mean(m$retA)/sd(m$retA)*sqrt(12) else NA_real_,
       tot_sr_B=if(sd(m$retB)>0) mean(m$retB)/sd(m$retB)*sqrt(12) else NA_real_,
       mde_t2_monthly=2*sd(d)/sqrt(nrow(m)), mde_t2_ann=2*sd(d)/sqrt(nrow(m))*12,
       diff_series=data.table(date=m$date, d=d))
}

## ---------- PIT HARD assert ----------
check_pit <- function(promos, label){
  if(nrow(promos)==0){ cat("[PIT]",label,"no promotions — vacuous pass\n"); return(invisible(TRUE)) }
  pm <- promos[!is.na(matched_ev), .(used=max(matched_ev)), by=Date]
  pm[, holding_start := holdings_signal_cutoff(Date)]
  assert_overlay_pit(pm$used, pm$holding_start, label=label)
  cat("[PIT]",label,"assert_overlay_pit PASS on", nrow(pm),"promotion months\n")
  invisible(TRUE)
}

## ---------- IS measurement ----------
ISR <- c(IS_LO, IS_HI)
base_IS <- run_mem(base_mem[Date>=IS_LO & Date<=IS_HI], "base_IS", diag=TRUE)
prB_IS <- as.data.table(base_IS$period_returns)

cfg_defs <- list(P1=list(band_hi=30L), P2=list(band_hi=40L))
res <- list()
for(cn in names(cfg_defs)){
  bh <- cfg_defs[[cn]]$band_hi
  pro <- promo_schedule(bh, "fresh_primary", ISR)
  check_pit(pro, paste0(cn,"_primary_IS"))
  memS <- subst_mem(pro, ISR)
  scr <- run_mem(memS, paste0(cn,"_sub_IS"), diag=TRUE)
  ps <- paired_stats(as.data.table(scr$period_returns), prB_IS)
  # lag1 stress
  pro_l1 <- promo_schedule(bh, "fresh_lag1", ISR)
  ps_l1 <- paired_stats(as.data.table(run_mem(subst_mem(pro_l1, ISR), paste0(cn,"_lag1_IS"))$period_returns), prB_IS)
  # strict-PIT A/B (ext = end-of-month cutoff, still PIT-legal; primary is stricter)
  pro_ext <- promo_schedule(bh, "fresh_ext", ISR)
  check_pit(pro_ext, paste0(cn,"_ext_IS"))
  ps_ext <- paired_stats(as.data.table(run_mem(subst_mem(pro_ext, ISR), paste0(cn,"_ext_IS"))$period_returns), prB_IS)
  ab <- overlay_lookahead_ab(ps_ext$mean_diff_ann, ps$mean_diff_ann, metric_name=paste0(cn,"_mean_diff_ann"))
  res[[cn]] <- list(band=paste0("21-",bh),
                    binding_stock_months_IS=nrow(pro),
                    binding_months_IS=length(unique(pro$Date)),
                    promoted_tickers=length(unique(pro$Ticker)),
                    primary=ps[names(ps)!="diff_series"],
                    lag1=ps_l1[c("paired_nw_t_lag3","mean_diff_ann","n_active_diff_months")],
                    ext_ab=list(ext_paired_nw_t=ps_ext$paired_nw_t_lag3, ext_mean_diff_ann=ps_ext$mean_diff_ann,
                                inflation=ab$inflation, lookahead_suspected=ab$lookahead_suspected, message=ab$message),
                    diff_series=ps$diff_series, promos=pro)
  cat(sprintf("[IS %s] binding=%d sm / paired NW-t=%+.3f / mean_diff_ann=%+.4f / dIR_frame=%+.3f / lag1 t=%+.3f / ext t=%+.3f\n",
              cn, nrow(pro), ps$paired_nw_t_lag3, ps$mean_diff_ann, ps$d_ir_frame,
              ps_l1$paired_nw_t_lag3, ps_ext$paired_nw_t_lag3))
}

## ---------- size-matched control (200 draws, episode-matched) ----------
set.seed(20260710)
control_one_cfg <- function(cn, n_draws=200L){
  bh <- cfg_defs[[cn]]$band_hi
  pro <- res[[cn]]$promos
  if(nrow(pro)==0) return(list(available=FALSE, note="no promotions"))
  # episodes: ticker x consecutive months
  p <- copy(pro); p[, midx := match(Date, all_dates)]; setorder(p, Ticker, midx)
  p[, epi := cumsum(c(1L, diff(midx)>1L)), by=Ticker]
  p[, epi_id := paste(Ticker, epi, sep="_")]
  epis <- split(p, p$epi_id)
  base20 <- base_mem[Date>=IS_LO & Date<=IS_HI]
  band_pool <- B[rk>=21 & rk<=bh & Date>=IS_LO & Date<=IS_HI]
  draws_mean <- numeric(n_draws); draws_t <- numeric(n_draws)
  for(dr in seq_len(n_draws)){
    used <- character(0)
    ctrl_rows <- rbindlist(lapply(epis, function(e){
      d0 <- min(e$Date)
      pool <- band_pool[Date==d0 & fresh_primary==FALSE &
                        !Ticker %in% pro[Date==d0, Ticker] & !Ticker %in% used]
      if(nrow(pool)==0) return(NULL)
      pick <- pool[sample(.N,1L), Ticker]
      used <<- c(used, pick)
      rbindlist(lapply(e$Date, function(dd){
        r <- B[Date==dd & Ticker==pick, rk]
        data.table(Date=dd, Ticker=pick, rk=if(length(r)) r else 999L, matched_ev=as.Date(NA))
      }))
    }))
    if(is.null(ctrl_rows)||nrow(ctrl_rows)==0){ draws_mean[dr]<-NA; draws_t[dr]<-NA; next }
    # skip months where control already in base top-20 that month
    ctrl_rows <- ctrl_rows[!paste(Date,Ticker) %in% base20[, paste(Date,Ticker)]]
    if(nrow(ctrl_rows)==0){ draws_mean[dr]<-NA; draws_t[dr]<-NA; next }
    scrC <- run_mem(subst_mem(ctrl_rows, ISR), paste0(cn,"_ctrl",dr))
    psC <- paired_stats(as.data.table(scrC$period_returns), prB_IS)
    draws_mean[dr] <- psC$mean_diff_ann; draws_t[dr] <- psC$paired_nw_t_lag3
    if(dr %% 50 == 0) cat("[ctrl",cn,"] draw",dr,"done\n")
  }
  actual_mean <- res[[cn]]$primary$mean_diff_ann; actual_t <- res[[cn]]$primary$paired_nw_t_lag3
  ok <- is.finite(draws_mean)
  list(available=TRUE, n_valid_draws=sum(ok),
       ctrl_mean_diff_ann=list(mean=mean(draws_mean[ok]), sd=sd(draws_mean[ok]),
                               q05=unname(quantile(draws_mean[ok],.05)), q50=unname(quantile(draws_mean[ok],.5)),
                               q95=unname(quantile(draws_mean[ok],.95))),
       ctrl_nw_t=list(mean=mean(draws_t[ok]), q05=unname(quantile(draws_t[ok],.05)),
                      q95=unname(quantile(draws_t[ok],.95))),
       actual_mean_diff_ann=actual_mean, actual_nw_t=actual_t,
       actual_pctile_mean=mean(draws_mean[ok] < actual_mean),
       actual_pctile_t=mean(draws_t[ok] < actual_t))
}
CTRL <- list(P1=control_one_cfg("P1"), P2=control_one_cfg("P2"))
for(cn in names(CTRL)) if(isTRUE(CTRL[[cn]]$available))
  cat(sprintf("[CTRL %s] actual pctile(mean)=%.3f pctile(t)=%.3f | ctrl mean q05/q50/q95 = %+.4f/%+.4f/%+.4f\n",
      cn, CTRL[[cn]]$actual_pctile_mean, CTRL[[cn]]$actual_pctile_t,
      CTRL[[cn]]$ctrl_mean_diff_ann$q05, CTRL[[cn]]$ctrl_mean_diff_ann$q50, CTRL[[cn]]$ctrl_mean_diff_ann$q95))

## ---------- selection + (conditional) OOS ----------
is_ts <- sapply(res, function(r) r$primary$paired_nw_t_lag3)
sel <- names(which.max(is_ts)); sel_t <- max(is_ts, na.rm=TRUE)
OOS_RUN <- NULL
if(is.finite(sel_t) && sel_t >= 2.5){
  OOR <- c(as.Date("2019-01-01"), max(returns_dt$Date))
  bh <- cfg_defs[[sel]]$band_hi
  base_OOS <- run_mem(base_mem[Date>=OOR[1] & Date<=OOR[2]], "base_OOS")
  proO <- promo_schedule(bh, "fresh_primary", OOR)
  check_pit(proO, paste0(sel,"_primary_OOS"))
  scrO <- run_mem(subst_mem(proO, OOR), paste0(sel,"_sub_OOS"))
  psO <- paired_stats(as.data.table(scrO$period_returns), as.data.table(base_OOS$period_returns))
  OOS_RUN <- c(list(config=sel, binding_stock_months_OOS=nrow(proO)), psO[names(psO)!="diff_series"])
  cat(sprintf("[OOS %s] paired NW-t=%+.3f\n", sel, psO$paired_nw_t_lag3))
} else cat(sprintf("[SELECT] max IS t=%+.3f < 2.5 -> OOS NOT consulted (KB1)\n", sel_t))

## ---------- verdict (pre-registered rules) ----------
verd <- lapply(names(res), function(cn){
  r <- res[[cn]]; t_ <- r$primary$paired_nw_t_lag3
  pw_ok <- r$binding_stock_months_IS >= 30
  v <- if(is.finite(t_) && t_ <= -2.0) "KILL_NEGATIVE"
       else if(is.finite(t_) && t_ >= 2.5) "SELECTED_PENDING_OOS"
       else if(!pw_ok) "power-insufficient"
       else "KILL"
  list(config=cn, is_t=t_, binding=r$binding_stock_months_IS, power_adequate=pw_ok, verdict=v)
})
names(verd) <- names(res)
# final overall
overall <- if(!is.null(OOS_RUN)){
  ok <- OOS_RUN$paired_nw_t_lag3 >= 2.0 &&
        res[[sel]]$primary$d_ir_frame >= 0.05 &&
        res[[sel]]$primary$tot_sr_A >= res[[sel]]$primary$tot_sr_B - 0.02 &&
        abs(res[[sel]]$lag1$paired_nw_t_lag3) >= 0.5*abs(res[[sel]]$primary$paired_nw_t_lag3) &&
        isTRUE(CTRL[[sel]]$actual_pctile_mean >= 0.95)
  if(ok) "SURVIVOR_CANDIDATE" else "KILL"
} else {
  vs <- sapply(verd, `[[`, "verdict")
  if(any(vs=="KILL_NEGATIVE")) "KILL_NEGATIVE"
  else if(all(vs=="KILL")) "KILL"
  else "power-insufficient"
}
cat("\n[VERDICT] overall =", overall, "\n")

## ---------- write ----------
strip_ds <- function(r){ r$diff_series <- NULL; r$promos <- NULL; r }
OUT$window <- list(IS="2015-01..2018-12 (Dates; DART crawl 2015+ — mission 2005-2018 window truncated by data availability, pre-declared in spec)",
                   OOS=if(!is.null(OOS_RUN)) "2019-01..panel end (consulted once)" else "NOT consulted (selection threshold unmet)")
OUT$configs <- lapply(res, strip_ds)
OUT$size_matched_control <- CTRL
OUT$selection <- list(rule="max IS paired NW-t >= +2.5 -> OOS once; all < +2.0 -> terminate; [2.0,2.5) near-null terminate",
                      max_is_t=sel_t, selected=if(!is.null(OOS_RUN)) sel else NA)
OUT$oos <- OOS_RUN
OUT$verdicts_per_config <- verd
OUT$overall_verdict <- overall
OUT$honest_notes <- c(
  "screen/diagnostic tier only — capital-grade claim forbidden (HARD 3종 + forge + governor 별도).",
  "IR figures are FRAME-LEVEL net-active (canonical top-20 EW, unoverlaid, cap-w BM) — NOT production net_active_recon_v1 NAV recon. Overlay M4xR05 identical in both arms and holdings-independent => monthly diff sign preserved under overlay (magnitude scaled by exposure).",
  "thin census: 33 firms / ~81 binding stock-months 2015+, of which ~28 in IS 2015-2018 — power cap pre-registered.",
  "incremental turnover cost is delta-based 15bps/leg inside canonical ret_net for both arms (no proxy).",
  "Stage A prior: A1-DART event drift 2015+ all buckets mildly negative/insignificant; favorable edge NOT expected — this run completes the measurement honestly (도훈 '컴퓨팅 한계까지')."
)
write_json(OUT, file.path(ROOT,"qepm","mailbox","worktask","WT-D20260710_004","alpha_b1_promote_results.json"),
           pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
saveRDS(list(res=res, CTRL=CTRL, OOS=OOS_RUN), file.path(SA,"b1_runtime_objects.rds"))
cat("[WRITE] alpha_b1_promote_results.json\n")
