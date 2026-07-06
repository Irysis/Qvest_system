# 03_experiment.R — value/quality spread-reversion conditional activation
# Variants A/B/C/D measured via canonical_screen_bt (top-25 EW long-only, 15bps, NW lag-3).
# + long-side (top-quintile net-active t) vs short-side decomposition (the JUDGMENT lens).
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), ..., "\n"); flush.console() }
t0 <- Sys.time()

pu  <- readRDS(file.path(OUT,"panel_universe_ret.rds"))
me <- pu$me; mret <- pu$mret; bm <- pu$bm
panel <- readRDS(file.path(OUT,"factor_panel_long.rds"))
spr <- readRDS(file.path(OUT,"spread_series.rds"))

# ---- composites per (ym, Ticker): mean Z across value / quality factors ----
val_facs  <- c("V01_BM","V02_EP","V10_FCF_Yield","V14_EBIT_EV","V20_SP")
qual_facs <- c("Q01_GPA","Q02_ROE","Q08_Composite_Quality","Q17_ROIC")
panel[, grp := fifelse(Factor_Name %in% val_facs, "val",
                fifelse(Factor_Name %in% qual_facs, "qual", NA_character_))]
comp <- panel[!is.na(grp), .(z = mean(Z_Score, na.rm=TRUE), nf = .N), by=.(ym, Ticker, grp)]
comp <- dcast(comp, ym + Ticker ~ grp, value.var="z")
# require both value & quality present
comp <- comp[is.finite(val) & is.finite(qual)]
# value+quality composite (equal-weight of the two standardized composites, re-z per month)
zscale <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s==0) x*0 else (x-m)/s }
comp[, val_z  := zscale(val),  by=ym]
comp[, qual_z := zscale(qual), by=ym]
comp[, vq_z   := zscale(val + qual), by=ym]   # value+quality combined cheapness+profitability

# ---- forward return: signal at ym predicts return of ym+1 ----
next_ym <- function(y){ yr<-y%/%100; mo<-y%%100; mo2<-mo+1; yr2<-yr+(mo2>12); mo2<-ifelse(mo2>12,1,mo2); yr2*100+mo2 }
comp[, fwd_ym := next_ym(ym)]
fwd <- merge(comp, mret[, .(Ticker, ym_key=ym, fwd_mret=mret)],
             by.x=c("Ticker","fwd_ym"), by.y=c("Ticker","ym_key"))
fwd <- fwd[is.finite(fwd_mret) & ym>=200501L]
# monthly Date key (use forward month realized) — canonical_screen_bt keys on Date
ym2date <- function(y) as.Date(sprintf("%04d-%02d-01", y%/%100, y%%100))
fwd[, Date := ym2date(fwd_ym)]   # returns realized in fwd month
bm2 <- copy(bm); bm2[, Date := ym2date(ym)]; setnames(bm2, "bm", "BM_Ret")
bm2 <- bm2[, .(Date, BM_Ret)]

# spread condition attached at SIGNAL month ym (expanding pctile known at t)
spr_key <- spr[, .(ym, exp_pctile, exp_z, spread_ratio)]
fwd <- merge(fwd, spr_key, by="ym", all.x=TRUE)
fwd <- fwd[is.finite(exp_pctile)]
log("[panel] fwd rows", nrow(fwd), "months", uniqueN(fwd$ym), "range", min(fwd$ym), max(fwd$ym))

# returns_dt for canonical: Date + Ticker + Ret_1m (forward realized)
returns_dt <- unique(fwd[, .(Date, Ticker, Ret_1m=fwd_mret)])

# ---- helper: run canonical top-25 with a per-row score column, + subperiod PORT_t ----
run_variant <- function(score_col, label, dt=fwd){
  sc <- dt[is.finite(get(score_col)), .(Date, Ticker, score=get(score_col))]
  full <- canonical_screen_bt(sc, returns_dt, bm2, top_n=25L, cost_bps_oneway=15)
  # 2017+ subperiod
  d2017 <- as.Date("2017-01-01")
  sc17 <- sc[Date>=d2017]; r17 <- returns_dt[Date>=d2017]; b17 <- bm2[Date>=d2017]
  rec <- tryCatch(canonical_screen_bt(sc17, r17, b17, top_n=25L, cost_bps_oneway=15),
                  error=function(e) list(portfolio_alpha_t_nw_lag3=NA, net_sr=NA, n_months=0))
  list(label=label, score_col=score_col,
       full_port_t=full$portfolio_alpha_t_nw_lag3, full_ir=full$information_ratio,
       full_sr=full$net_sr, full_alpha_ann=full$alpha_annualized,
       full_turnover=full$turnover_annual, full_n=full$n_months,
       rec2017_port_t=rec$portfolio_alpha_t_nw_lag3, rec2017_sr=rec$net_sr, rec2017_n=rec$n_months,
       period_returns=full$period_returns)
}

# ==== VARIANTS ====
log("[V] A: unconditional value ...")
A_val  <- run_variant("val_z",  "A_uncond_value")
A_qual <- run_variant("qual_z", "A_uncond_quality")
A_vq   <- run_variant("vq_z",   "A_uncond_valqual")

# B: spread-conditional binary. When spread pctile>=thr -> value tilt (score=val_z); else neutral(score=0 => arbitrary top25, replace with OFF=benchmark).
# Implement OFF as: score set so portfolio = benchmark (active 0). We do this by building period_returns manually:
#   ON months: canonical top25 by val_z; OFF months: active=0 (port ret = benchmark).
build_conditional <- function(score_col, thr, label, cont=FALSE){
  # compute ON/OFF per SIGNAL ym; realized in fwd month (Date)
  cond <- unique(fwd[, .(ym, Date, exp_pctile, exp_z)])
  if(!cont){ cond[, on := exp_pctile >= thr] } else { cond[, on := TRUE] }
  # full ON portfolio period returns (top25 by score)
  sc <- fwd[is.finite(get(score_col)), .(Date, Ticker, score=get(score_col))]
  onbt <- canonical_screen_bt(sc, returns_dt, bm2, top_n=25L, cost_bps_oneway=15)
  pr <- as.data.table(onbt$period_returns)  # date, ret_net, benchmark_ret
  pr <- merge(pr, cond[, .(Date, on, exp_pctile, exp_z)], by.x="date", by.y="Date", all.x=TRUE)
  if(cont){
    # continuous: weight w in [0,1] = clamp((pctile-0.5)/0.5,0,1); port = w*value + (1-w)*bench
    pr[, w := pmin(pmax((exp_pctile-0.5)/0.5, 0), 1)]
  } else {
    pr[, w := as.numeric(on)]
  }
  pr[is.na(w), w := 0]
  pr[, ret_cond := w*ret_net + (1-w)*benchmark_ret]
  pr[, active := ret_cond - benchmark_ret]
  # NW lag3 t of active
  nwt <- function(a){ n<-length(a); if(n<12) return(NA_real_); m<-mean(a); ac<-acf(a,lag.max=3,plot=FALSE)$acf[2:4]; s2<-var(a)/n*(1+2*sum((1-(1:3)/n)*ac)); if(!is.finite(s2)||s2<=0) return(NA_real_); m/sqrt(s2) }
  port_t <- nwt(pr$active)
  sr <- mean(pr$active)/sd(pr$active)*sqrt(12)
  d2017 <- pr[date>=as.Date("2017-01-01")]
  port_t17 <- nwt(d2017$active); sr17 <- mean(d2017$active)/sd(d2017$active)*sqrt(12)
  frac_on <- mean(pr$w>0)
  list(label=label, thr=thr, cont=cont, full_port_t=port_t, full_sr=sr,
       rec2017_port_t=port_t17, rec2017_sr=sr17, full_n=nrow(pr), rec2017_n=nrow(d2017),
       frac_on=frac_on, mean_active=mean(pr$active), pr=pr)
}
log("[V] B: spread-conditional binary (thr=0.80) ...")
B_val80 <- build_conditional("val_z", 0.80, "B_cond_value_p80")
B_vq80  <- build_conditional("vq_z",  0.80, "B_cond_valqual_p80")
B_val90 <- build_conditional("val_z", 0.90, "B_cond_value_p90")
log("[V] C: continuous spread-scaled ...")
C_val <- build_conditional("val_z", 0, "C_scaled_value", cont=TRUE)
C_vq  <- build_conditional("vq_z",  0, "C_scaled_valqual", cont=TRUE)
log("[V] D: quality reversion (conditional Q on spread) ...")
D_qual80 <- build_conditional("qual_z", 0.80, "D_cond_quality_p80")

saveRDS(list(A_val=A_val,A_qual=A_qual,A_vq=A_vq,
             B_val80=B_val80,B_vq80=B_vq80,B_val90=B_val90,
             C_val=C_val,C_vq=C_vq,D_qual80=D_qual80,
             fwd=fwd, returns_dt=returns_dt, bm2=bm2, spr=spr),
        file.path(OUT,"experiment_results.rds"))

# ==== summary table ====
row <- function(x) data.table(label=x$label, full_port_t=round(x$full_port_t,3),
  rec2017_port_t=round(x$rec2017_port_t,3), full_sr=round(x$full_sr,3),
  rec2017_sr=round(x$rec2017_sr,3), n=x$full_n,
  frac_on=round(if(is.null(x$frac_on)) 1 else x$frac_on,2))
tab <- rbindlist(list(row(A_val),row(A_qual),row(A_vq),
                      row(B_val80),row(B_vq80),row(B_val90),
                      row(C_val),row(C_vq),row(D_qual80)), fill=TRUE)
log("\n==== VARIANT SUMMARY (top-25 EW long-only, 15bps, NW lag-3) ====")
print(tab)
fwrite(tab, file.path(OUT,"variant_summary.csv"))
log("[TOTAL]", round(difftime(Sys.time(),t0,units="secs"),1),"s")
