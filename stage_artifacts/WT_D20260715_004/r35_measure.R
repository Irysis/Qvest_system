## ============================================================================
## R35 (FQ-047 P1, WT-D20260715_004) — SP(sales-yield) consumption-face re-routing
##   Part1: EW-basis deployability (D3 form)  Part2: OVERLAY feature  Part3: 2024+ robustness
##   Reuse R31 harness. base = clean recon_panels (WT_D20260714_004, off0 T-1). READ-ONLY.
##   book_state / 05_Production / outputs/ramp UNCHANGED. DART API not used. factor_db only.
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260715_004")
R31 <- file.path(QM,"stage_artifacts/WT_D20260714_007")
B04 <- file.path(QM,"stage_artifacts/WT_D20260714_004")
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<8)return(NA_real_);fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=lag,prewhite=FALSE)[1,1]);unname(coef(fit)[1]/se)}
IR_ann<-function(v){v<-v[is.finite(v)];if(length(v)<6)return(NA_real_);s<-sd(v);if(!is.finite(s)||s<=0)return(NA_real_);mean(v)/s*sqrt(12)}
sr1<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA_real_);s<-sd(x);if(!is.finite(s)||s<=0)return(NA_real_);mean(x)/s*sqrt(12)}
oos_v2<-function(a){a<-a[is.finite(a)];n<-length(a);if(n<24)return(NA_real_)
  r<-sapply(c(0.55,0.65,0.75),function(f){k<-floor(n*f);if(k<6||(n-k)<6)return(NA_real_)
    is<-sr1(a[1:k]);oo<-sr1(a[(k+1):n]);if(is.na(is)||is.na(oo)||is<=0)return(NA_real_);oo/is});median(r,na.rm=TRUE)}
Y24<-as.Date("2024-01-01")

## ---- inputs (reuse R31/R28 clean harness) ----
SP7 <- as.data.table(read_parquet(file.path(R31,"subaxis_panels.parquet"))); SP7[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(B04,"screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE; BK<-as.data.table(SI$bk)
PAN <- as.data.table(read_parquet(file.path(B04,"recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
FR <- fwd_ret[,.(Date,Ticker,Ret_1m)]

## SP score panel (single factor, aligned z within base membership)
SPDT <- SP7[is.finite(SP),.(Date,Ticker,score=SP)]
cat(sprintf("SP panel: %d rows, %d months (%s..%s)\n", nrow(SPDT), uniqueN(SPDT$Date),
    as.character(min(SPDT$Date)), as.character(max(SPDT$Date))))

## ============================================================================
## PART 1 — EW-basis deployability (D3 form)
## ============================================================================
cat("\n===== PART 1: EW-basis deployability =====\n")
sp_ew <- canonical_screen_bt(SPDT, FR, bench, top_n=25L, cost_bps_oneway=15,
          liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id="R35_SP_ew",
          strategy_id="R35_SP_ew", size_dt=SIZE, diag_dual_basis=TRUE)
capw_pt <- sp_ew$portfolio_alpha_t_nw_lag3
ewuni <- sp_ew$diag_ew_universe
cat(sprintf("[SP EW top-25]  cap-w PORT_t=%.3f IR=%.3f net_SR=%.3f TO=%.1f n=%d\n",
    capw_pt, sp_ew$information_ratio, sp_ew$net_sr, sp_ew$turnover_annual, sp_ew$n_months))
cat(sprintf("  diag_EW-universe: PORT_t=%.3f post2017_t=%.3f oos_approx=%.3f net_SR=%.3f IR=%.3f n=%d\n",
    ewuni$portfolio_alpha_t_nw_lag3, ewuni$post2017_t_nw_lag3, ewuni$oos_retention_approx,
    ewuni$net_sr, ewuni$information_ratio, ewuni$n_months))

## EW-active series (from diag) for oos v2 + TE + corr
ewpr <- as.data.table(ewuni$period_returns)  # date, ret_net, ew_bench_ret, active_ew
setorder(ewpr, date)
oos_ew <- oos_v2(ewpr$active_ew)
TE_ew  <- sd(ewpr$active_ew, na.rm=TRUE)*sqrt(12)
## cap-w active (vs KOSPI200) from main pr
capwpr <- as.data.table(sp_ew$period_returns) # date, ret_net, benchmark_ret
capwpr[, active_capw := ret_net - benchmark_ret]
oos_capw <- oos_v2(capwpr$active_capw)
TE_capw  <- sd(capwpr$active_capw,na.rm=TRUE)*sqrt(12)
cat(sprintf("  oos_v2  EW=%.3f  capw=%.3f  |  TE_ann  EW=%.1f%%  capw=%.1f%%\n",
    oos_ew, oos_capw, TE_ew*100, TE_capw*100))

## band 2/3 supporting evidence for EW-active (if in [0.5,0.7))
## (a) trailing 24m PORT_t > 0  (b) placebo p<0.05 [from R31: 0.025]  (c) book-marginal [Part2]
trail24_pt <- nw_t(tail(ewpr$active_ew,24))
cat(sprintf("  band-evidence: trailing24m EW PORT_t=%.3f (>0?) ; placebo p=0.025 (R31) ; book-marginal->Part2\n", trail24_pt))

## capacity: holdings ADV. get SP top-25 weights per month, min ADV
setorder(SPDT, Date, -score)
Wsp <- merge(SPDT, liqf[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
Wsp <- Wsp[is.na(adv)|adv>=2e8]
Wsp <- Wsp[, {n<-min(25L,.N); .(Ticker=Ticker[1:n], adv=adv[1:n], w=1/n)}, by=Date]
## AUM cap at 5% ADV participation for smallest holding: AUM*w <= 0.05*adv -> AUM <= 0.05*adv/w
Wsp[, aum_cap := 0.05*adv/w]
cap_by_month <- Wsp[, .(min_adv=min(adv,na.rm=TRUE), aum_cap_krw=min(aum_cap,na.rm=TRUE)), by=Date]
cap_med <- median(cap_by_month$aum_cap_krw, na.rm=TRUE)
cat(sprintf("  capacity: median monthly AUM cap (5%% ADV, binding smallest holding) = %.1f bil KRW\n", cap_med/1e9))

## active corr vs P-pure base + D-2 paper-tracks (act_ew)
pp_base <- fread(file.path(QM,"06_Registry/live_track/PPURE_BASE_W36K20/sealed_source_series.csv"))
pp_d2   <- fread(file.path(QM,"06_Registry/live_track/PPURE_D2_DECAYEXIT/sealed_source_series.csv"))
pp_base[,date:=as.Date(signal_date)]; pp_d2[,date:=as.Date(signal_date)]
cmp_b <- merge(ewpr[,.(date,sp=active_ew)], pp_base[,.(date,pb=act_ew)], by="date")
cmp_d <- merge(ewpr[,.(date,sp=active_ew)], pp_d2[,.(date,pd=act_ew)], by="date")
corr_ppbase <- suppressWarnings(cor(cmp_b$sp, cmp_b$pb, use="complete.obs"))
corr_ppd2   <- suppressWarnings(cor(cmp_d$sp, cmp_d$pd, use="complete.obs"))
cat(sprintf("  active-corr(EW) vs P-pure base=%.3f (n=%d) / D-2=%.3f (n=%d)\n",
    corr_ppbase, nrow(cmp_b), corr_ppd2, nrow(cmp_d)))

## holding overlap Jaccard vs P-pure base holdings
ppb_h <- fread(file.path(QM,"06_Registry/live_track/PPURE_BASE_W36K20/sealed_holdings_ref.csv"))
ppb_h[,date:=as.Date(signal_date)]
jac <- Wsp[, .(sp_tk=list(Ticker)), by=Date]
jm <- merge(jac, ppb_h[, .(pp_tk=list(Ticker)), by=date], by.x="Date", by.y="date")
jm[, jac := mapply(function(a,b){u<-length(union(a,b));if(u==0)NA_real_ else length(intersect(a,b))/u}, sp_tk, pp_tk)]
jac_med <- median(jm$jac, na.rm=TRUE); overlap_med <- median(mapply(function(a,b)length(intersect(a,b)), jm$sp_tk, jm$pp_tk),na.rm=TRUE)
cat(sprintf("  holding overlap vs P-pure base: median Jaccard=%.3f, median #shared=%.1f / 25\n", jac_med, overlap_med))

## ============================================================================
## PART 2 — OVERLAY feature qualification (EW-basis marginal, m1-drain format)
## ============================================================================
cat("\n===== PART 2: OVERLAY feature qualification =====\n")
## base EW (clean 0_stored_S7) top-25
BASEDT <- PAN[is.finite(`0_stored_S7`),.(Date,Ticker,score=`0_stored_S7`)]
base_ew <- canonical_screen_bt(BASEDT, FR, bench, top_n=25L, cost_bps_oneway=15,
          liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id="R35_base_ew",
          strategy_id="R35_base_ew", size_dt=SIZE, diag_dual_basis=TRUE)
base_ewpr <- as.data.table(base_ew$diag_ew_universe$period_returns)[,.(date,ba=active_ew)]

## overlay: 0.7 base_z + 0.3 SP_z, EW top-25 (tilt overlay)
mk_blend <- function(basecol_dt, valcol_dt, w=0.3){
  d <- merge(basecol_dt[,.(Date,Ticker,b=score)], valcol_dt[,.(Date,Ticker,v=score)], by=c("Date","Ticker"), all.x=TRUE)
  d[, b_z:=zc(b), by=Date]; d[, v_z:=zc(v), by=Date]; d[is.na(v_z), v_z:=0]
  d[, score:=(1-w)*b_z + w*v_z]; d[,.(Date,Ticker,score)]
}
ovl_base <- mk_blend(BASEDT, SPDT, 0.3)
ovl_base_res <- canonical_screen_bt(ovl_base, FR, bench, top_n=25L, cost_bps_oneway=15,
          liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id="R35_ovl_base",
          strategy_id="R35_ovl_base", size_dt=SIZE, diag_dual_basis=TRUE)
ovl_base_pr <- as.data.table(ovl_base_res$diag_ew_universe$period_returns)[,.(date,va=active_ew)]
mB <- merge(ovl_base_pr, base_ewpr, by="date"); mB[,dd:=va-ba]
ovl_base_paired <- nw_t(mB$dd); ovl_base_dIR <- IR_ann(mB$va)-IR_ann(mB$ba)
preB<-mB[date<Y24]; postB<-mB[date>=Y24]
cat(sprintf("[OVERLAY on base clean, EW] paired NW-t=%.3f dIR=%.3f | pre24 paired=%.3f post24 paired=%.3f | base_EW_pt=%.2f ovl_EW_pt=%.2f\n",
    ovl_base_paired, ovl_base_dIR, nw_t(preB$dd), nw_t(postB$dd),
    base_ew$diag_ew_universe$portfolio_alpha_t_nw_lag3, ovl_base_res$diag_ew_universe$portfolio_alpha_t_nw_lag3))

## overlay on incumbent book (bk score_eff), EW top-25
## BK Date = first-of-month AS_OF (rebalance); FR/recon Date = prior month-end d0 (realized_ym -1mo offset,
## reference-book-benchmark-alignment-realized-ym). Remap BK AS_OF -> matching month-end d0 = max(FR date < AS_OF).
frd <- sort(unique(FR$Date))
BK2 <- BK[is.finite(score_eff),.(Date,Ticker,score=score_eff)]
BK2[, d0 := frd[findInterval(Date-1L, frd)]]   # largest FR date <= AS_OF-1 = prior month-end
BK2 <- BK2[!is.na(d0) & d0 < Date]
BKDT <- BK2[,.(Date=d0,Ticker,score)]
stopifnot(length(intersect(as.character(BKDT$Date),as.character(FR$Date)))>0)
bk_ew <- canonical_screen_bt(BKDT, FR, bench, top_n=25L, cost_bps_oneway=15,
          liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id="R35_bk_ew",
          strategy_id="R35_bk_ew", size_dt=SIZE, diag_dual_basis=TRUE)
bk_ewpr <- as.data.table(bk_ew$diag_ew_universe$period_returns)[,.(date,ba=active_ew)]
ovl_bk <- mk_blend(BKDT, SPDT, 0.3)
ovl_bk_res <- canonical_screen_bt(ovl_bk, FR, bench, top_n=25L, cost_bps_oneway=15,
          liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id="R35_ovl_bk",
          strategy_id="R35_ovl_bk", size_dt=SIZE, diag_dual_basis=TRUE)
ovl_bk_pr <- as.data.table(ovl_bk_res$diag_ew_universe$period_returns)[,.(date,va=active_ew)]
mK <- merge(ovl_bk_pr, bk_ewpr, by="date"); mK[,dd:=va-ba]
ovl_bk_paired <- nw_t(mK$dd); ovl_bk_dIR <- IR_ann(mK$va)-IR_ann(mK$ba)
preK<-mK[date<Y24]; postK<-mK[date>=Y24]
cat(sprintf("[OVERLAY on incumbent bk, EW] paired NW-t=%.3f dIR=%.3f | pre24=%.3f post24=%.3f | bk_EW_pt=%.2f ovl_EW_pt=%.2f\n",
    ovl_bk_paired, ovl_bk_dIR, nw_t(preK$dd), nw_t(postK$dd),
    bk_ew$diag_ew_universe$portfolio_alpha_t_nw_lag3, ovl_bk_res$diag_ew_universe$portfolio_alpha_t_nw_lag3))

## ============================================================================
## PART 3 — 2024+ robustness
## ============================================================================
cat("\n===== PART 3: 2024+ robustness =====\n")
## pre/post + subperiod on SP EW-active
ea <- ewpr[,.(date, a=active_ew)]
subs <- list(P0814=c("2008-01-01","2014-12-31"),P1519=c("2015-01-01","2019-12-31"),
             P2023=c("2020-01-01","2023-12-31"),P2426=c("2024-01-01","2026-12-31"))
cat("  SP EW-active subperiod NW-t / meanAnnBp / SR:\n")
sub_rows <- list()
for(nm in names(subs)){s<-ea[date>=as.Date(subs[[nm]][1])&date<=as.Date(subs[[nm]][2])]
  sub_rows[[nm]]<-data.table(period=nm,n=nrow(s),nwt=nw_t(s$a),meanbp=mean(s$a,na.rm=TRUE)*1200,sr=sr1(s$a))
  cat(sprintf("    %-6s n=%2d  NW-t=%6.2f  meanAnn=%6.0fbp  SR=%5.2f\n", nm, nrow(s), nw_t(s$a), mean(s$a,na.rm=TRUE)*1200, sr1(s$a)))}
SUBP <- rbindlist(sub_rows)
pre24_nwt<-nw_t(ea[date<Y24]$a); post24_nwt<-nw_t(ea[date>=Y24]$a)
cat(sprintf("  pre-2024 NW-t=%.3f (n=%d) / 2024+ NW-t=%.3f (n=%d)\n",
    pre24_nwt, ea[date<Y24,.N], post24_nwt, ea[date>=Y24,.N]))

## rolling 24m PORT_t
setorder(ea,date); ea[, roll_pt := {v<-a; sapply(seq_len(.N),function(i){if(i<24)NA_real_ else nw_t(v[(i-23):i])})}]
cat(sprintf("  rolling-24m EW PORT_t: last=%.2f, max=%.2f, min=%.2f, #months>0(last12)=%d/12\n",
    tail(ea$roll_pt,1), max(ea$roll_pt,na.rm=TRUE), min(ea$roll_pt,na.rm=TRUE), sum(tail(ea$roll_pt,12)>0,na.rm=TRUE)))

## sector concentration of SP top-25 holdings, pre vs post 2024
RAW <- as.data.table(read_parquet(file.path(QM,".cache/RAWDATA.parquet"),
        col_select=c("Date","Ticker","Sector")))
RAW[,Date:=as.Date(Date)]
RAW <- unique(RAW[!is.na(Sector),.(Ticker,Sector)], by="Ticker")  # latest sector per ticker (approx, static)
Hsp <- Wsp[,.(Date,Ticker)]; Hsp <- merge(Hsp, RAW, by="Ticker", all.x=TRUE)
Hsp[is.na(Sector),Sector:="UNK"]
Hsp[, era := fifelse(Date>=Y24,"post24","pre24")]
sec_pre <- Hsp[era=="pre24", .N, by=Sector][order(-N)][, share:=N/sum(N)]
sec_post<- Hsp[era=="post24",.N, by=Sector][order(-N)][, share:=N/sum(N)]
cat("  SP top-25 sector share (pre24 top5):\n"); print(head(sec_pre,5))
cat("  SP top-25 sector share (post24 top5):\n"); print(head(sec_post,5))
## concentration HHI
hhi_pre <- sum(sec_pre$share^2); hhi_post <- sum(sec_post$share^2)
cat(sprintf("  sector HHI: pre24=%.3f post24=%.3f (higher=more concentrated)\n", hhi_pre, hhi_post))

## low-quality trap check (C3): SP top-decile — do they skew to negative-earnings? proxy via EP sign
## use EP aligned-z from panel: SP-top holdings' median EP z (if EP very negative -> low earnings)
EPP <- SP7[,.(Date,Ticker,EP)]
Hsp_ep <- merge(Wsp[,.(Date,Ticker)], EPP, by=c("Date","Ticker"), all.x=TRUE)
ep_med_sp <- median(Hsp_ep$EP, na.rm=TRUE)
## reference: full-universe median EP z ~ 0 (it's a z). so negative => SP-holdings tilt low-earnings-yield
cat(sprintf("  C3 low-quality proxy: SP top-25 holdings median EP(aligned-z)=%.3f (neg => low earnings-yield tilt)\n", ep_med_sp))

## ---- save ----
save_safe(ewpr, file.path(WT,"sp_ew_series.parquet"), function(o,p)write_parquet(o,p))
save_safe(SUBP, file.path(WT,"sp_subperiod.parquet"), function(o,p)write_parquet(o,p))
save_safe(ea[,.(date,a,roll_pt)], file.path(WT,"sp_rolling.parquet"), function(o,p)write_parquet(o,p))
save_safe(rbind(sec_pre[,era:="pre24"],sec_post[,era:="post24"]), file.path(WT,"sp_sector.parquet"), function(o,p)write_parquet(o,p))
RES <- list(
  part1=list(capw_pt=capw_pt, ewuni_pt=ewuni$portfolio_alpha_t_nw_lag3, ewuni_post17=ewuni$post2017_t_nw_lag3,
    oos_ew=oos_ew, oos_capw=oos_capw, oos_ewuni_approx=ewuni$oos_retention_approx,
    TE_ew=TE_ew, TE_capw=TE_capw, net_sr_ew=ewuni$net_sr, net_sr_capw=sp_ew$net_sr,
    turnover=sp_ew$turnover_annual, capacity_bil=cap_med/1e9, trail24_pt=trail24_pt,
    corr_ppbase=corr_ppbase, corr_ppd2=corr_ppd2, jaccard_ppbase=jac_med, overlap_ppbase=overlap_med),
  part2=list(ovl_base_paired=ovl_base_paired, ovl_base_dIR=ovl_base_dIR,
    ovl_base_pre=nw_t(preB$dd), ovl_base_post=nw_t(postB$dd),
    base_ew_pt=base_ew$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    ovl_base_ew_pt=ovl_base_res$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    ovl_bk_paired=ovl_bk_paired, ovl_bk_dIR=ovl_bk_dIR,
    ovl_bk_pre=nw_t(preK$dd), ovl_bk_post=nw_t(postK$dd),
    bk_ew_pt=bk_ew$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    ovl_bk_ew_pt=ovl_bk_res$diag_ew_universe$portfolio_alpha_t_nw_lag3),
  part3=list(pre24_nwt=pre24_nwt, post24_nwt=post24_nwt, subperiod=SUBP,
    roll_last=tail(ea$roll_pt,1), roll_max=max(ea$roll_pt,na.rm=TRUE), roll_min=min(ea$roll_pt,na.rm=TRUE),
    hhi_pre=hhi_pre, hhi_post=hhi_post, ep_med_sp=ep_med_sp)
)
saveRDS(RES, file.path(WT,"r35_results.rds"))
cat("\nR35_MEASURE_DONE\n")
