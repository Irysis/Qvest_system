# WT-D20260710_004 Stage A — no-selection diagnostics (0 trial). Spec-frozen: stageA_spec.json
# sha256 bd7ecd9362d6c8fccca869124118d85b85b3405c8c3b7a186ebf51eaa04d38a1
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); options(scipen=999)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR=ROOT, QM_ROOT=ROOT)
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_004")
source(file.path(ROOT,"02_Infrastructure","config.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))  # .nw_t_mean, build_benchmark_compare
source(file.path(ROOT,"02_Infrastructure","factor_db","factor_db_connector.R"))       # load_month_factors
nwt <- function(x, lag=3L) .nw_t_mean(x, lag=lag)

OUT <- list(spec_sha256="bd7ecd9362d6c8fccca869124118d85b85b3405c8c3b7a186ebf51eaa04d38a1",
            run_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"), metric_type="canonical_screen")

## ---------- vintage pin ----------
source(file.path(ROOT,"02_Infrastructure","data","pin_cache.R"))
PIN_TAG <- format(Sys.time(),"wt004A_%Y%m%d_%H%M%S")
pin_cache(c(file.path(ROOT,".cache","benchmark.parquet"),
            file.path(ROOT,".cache","dart","buyback_decisions_clean.parquet")), PIN_TAG)
OUT$pin_tag <- PIN_TAG
BM_PIN <- read_pinned(file.path(ROOT,".cache","benchmark.parquet"), PIN_TAG)
BB_PIN <- read_pinned(file.path(ROOT,".cache","dart","buyback_decisions_clean.parquet"), PIN_TAG)

## ---------- inputs ----------
panel <- as.data.table(readRDS(file.path(ROOT,"stage_artifacts","WT-D20260710_001","panel.rds")))
OUT$panel_md5 <- unname(tools::md5sum(file.path(ROOT,"stage_artifacts","WT-D20260710_001","panel.rds")))
all_dates <- sort(unique(panel$Date)); midx_of <- function(d) match(d, all_dates)

# benchmark: monthly compound -> forward lead1 (canonical WT-001 convention)
bm <- as.data.table(read_parquet(BM_PIN)); bm[, Dt:=as.Date(Date)]; bm[, ym:=format(Dt,"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_m <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
bm_m[, Date:=as.Date(paste0(ym,"-01"))]; bm_m[, bm_fwd:=shift(bm_ret,type="lead",n=1L)]
benchdt <- bm_m[!is.na(bm_fwd), .(Date, BM_Ret=bm_fwd)]
# EW-universe monthly forward return (tradeable in_univ)
ewuni <- panel[!is.na(Ret_1m), .(ew_ret=mean(Ret_1m)), by=Date]

returns_dt <- panel[!is.na(Ret_1m), .(Date,Ticker,Ret_1m)]
# attach fwd benchmark to each panel row for active calc
panel <- merge(panel, benchdt, by="Date", all.x=TRUE)
panel <- merge(panel, ewuni, by="Date", all.x=TRUE)

## ---------- universe alignment precheck ----------
tier_counts <- panel[, .(MEGA=sum(tier=="MEGA"), MID=sum(tier=="MID"), OTHER=sum(tier=="OTHER")), by=Date]
OUT$precheck <- list(
  n_months=length(all_dates), date_min=as.character(min(all_dates)), date_max=as.character(max(all_dates)),
  mega_per_month_med=median(tier_counts$MEGA), mid_per_month_med=median(tier_counts$MID),
  all_in_univ=all(panel$in_univ==TRUE), score_eff_cov=round(mean(!is.na(panel$score_eff)),3),
  note="panel already filtered in_univ K200∪KQ150; MEGA=cap1-10 MID=11-30 OTHER=31+ recomputed within tradeable per Date"
)

## ===================== INTEGRITY (before A1) =====================
spot_dates <- all_dates[round(seq(30, length(all_dates)-5, length.out=4))]
integ <- rbindlist(lapply(spot_dates, function(sd){
  fm <- tryCatch(load_month_factors(sd, factor_names=c("M08_Residual_Mom","V02_EP")), error=function(e) NULL)
  if(is.null(fm)||nrow(fm)==0) return(data.table(Date=sd, cor_M08=NA_real_, cor_V02=NA_real_, n_M08=0L, n_V02=0L))
  fm <- as.data.table(fm)
  ph <- panel[Date==sd]
  mrg <- function(fac, pcol){
    a <- fm[Factor_Name==fac, .(Ticker, Zf=Z_Score_Aligned)]
    b <- ph[, .(Ticker, Zp=get(pcol))]
    m <- merge(a,b,by="Ticker")[!is.na(Zf)&!is.na(Zp)]
    if(nrow(m)<8) return(c(NA_real_, nrow(m)))
    c(cor(m$Zf, m$Zp, method="spearman"), nrow(m))
  }
  r8 <- mrg("M08_Residual_Mom","M08_Residual_Mom"); r2 <- mrg("V02_EP","V02_EP")
  data.table(Date=sd, cor_M08=round(r8[1],4), n_M08=as.integer(r8[2]), cor_V02=round(r2[1],4), n_V02=as.integer(r2[2]))
}))
OUT$integrity <- list(
  restatement_spotcheck=integ,
  interpretation="Spearman rank-cor between FRESH load_month_factors (expanding Usable_Date<=sig_date, built now) and panel.rds signal at spot dates. |cor|~1 => no restatement of cross-sectional ordering across build times.",
  min_abs_cor_M08=round(min(abs(integ$cor_M08),na.rm=TRUE),4),
  min_abs_cor_V02=round(min(abs(integ$cor_V02),na.rm=TRUE),4)
)
cat("[integrity] spot-check done. min|cor| M08=", OUT$integrity$min_abs_cor_M08, " V02=", OUT$integrity$min_abs_cor_V02, "\n")

## ===================== helper: value-innovation age =====================
add_value_age <- function(dt, zcol, tau){
  d <- dt[!is.na(get(zcol)), .(Date, Ticker, z=get(zcol))]
  setorder(d, Ticker, Date)
  d[, midx := midx_of(Date)]
  d[, `:=`(z_prev=shift(z), midx_prev=shift(midx)), by=Ticker]
  d[, refresh := is.na(z_prev) | is.na(midx_prev) | (midx-midx_prev)>1L | abs(z-z_prev)>tau]
  # age = midx - last_refresh_midx  (per ticker running)
  d[, last_ref := { lr <- integer(.N); cur <- NA_integer_
      for(i in seq_len(.N)){ if(refresh[i]) cur <- midx[i]; lr[i] <- cur }; lr }, by=Ticker]
  d[, age := midx - last_ref]
  d[, bucket := fifelse(age==0L,"0-1m", fifelse(age==1L,"1-2m", fifelse(age<=3L,"2-4m","4m+")))]
  d[, .(Date, Ticker, age, bucket)]
}

## ===================== A1 =====================
series_cols <- list(score_eff="score_eff", M08_Residual_Mom="M08_Residual_Mom", V02_EP="V02_EP")
zc_of <- function(nm) if(nm=="score_eff") "score_eff" else paste0("zc_",nm)  # score_eff already ~z; use as ranking

a1_one <- function(sig_name, tau, lag_stress=FALSE){
  rankcol <- zc_of(sig_name)
  base <- panel[!is.na(get(rankcol)) & !is.na(Ret_1m), .(Date, Ticker, z=get(rankcol), Ret_1m, tier)]
  age <- add_value_age(panel, rankcol, tau)
  d <- merge(base, age, by=c("Date","Ticker"))
  if(lag_stress){ # use z_{t-1} to predict Ret_1m_t : shift z forward by 1 month within ticker
    setorder(d, Ticker, Date); d[, z := shift(z), by=Ticker]; d <- d[!is.na(z)]
  }
  # per-month per-bucket IC
  ic_mb <- d[, {if(.N>=8) .(ic=cor(z, Ret_1m, method="spearman"), n=.N) else .(ic=NA_real_, n=.N)}, by=.(Date,bucket)]
  bstat <- ic_mb[!is.na(ic), .(mean_ic=mean(ic), nw_t=nwt(ic), n_months=.N, avg_n=round(mean(n),1)), by=bucket]
  # fresh(age<=1) vs stale(age>=4) monthly pooled IC + contrast
  d[, grp := fifelse(age<=1L,"fresh", fifelse(age>=4L,"stale", "mid"))]
  ic_fs <- d[grp %in% c("fresh","stale"), {if(.N>=8) .(ic=cor(z,Ret_1m,method="spearman"),n=.N) else .(ic=NA_real_,n=.N)}, by=.(Date,grp)]
  wide <- dcast(ic_fs[!is.na(ic)], Date~grp, value.var="ic")
  contrast <- if(all(c("fresh","stale") %in% names(wide))) { wide2 <- wide[!is.na(fresh)&!is.na(stale)]; wide2$fresh-wide2$stale } else numeric(0)
  list(sig=sig_name, tau=tau, lag_stress=lag_stress,
       buckets=bstat[order(match(bucket,c("0-1m","1-2m","2-4m","4m+")))],
       fresh_mean_ic=if(length(contrast)>0) round(mean(wide2$fresh),4) else NA_real_,
       stale_mean_ic=if(length(contrast)>0) round(mean(wide2$stale),4) else NA_real_,
       contrast_mean=if(length(contrast)>0) round(mean(contrast),4) else NA_real_,
       contrast_nw_t=if(length(contrast)>=5) round(nwt(contrast),3) else NA_real_,
       contrast_n_months=length(contrast))
}

A1 <- list()
for(sn in names(series_cols)){
  A1[[sn]] <- a1_one(sn, tau=0.5, lag_stress=FALSE)
  A1[[paste0(sn,"_tau1.0")]] <- a1_one(sn, tau=1.0, lag_stress=FALSE)
  A1[[paste0(sn,"_lag1")]] <- a1_one(sn, tau=0.5, lag_stress=TRUE)
  cat("[A1]", sn, "contrast_nw_t(tau.5)=", A1[[sn]]$contrast_nw_t, " lag1=", A1[[paste0(sn,"_lag1")]]$contrast_nw_t, "\n")
}

## ---- A1 DART event series (event-time forward active by event age) ----
bb <- as.data.table(read_parquet(BB_PIN))
bb[, rcept_dt := as.Date(substr(rcept_no,1,8), format="%Y%m%d")]
bb <- bb[!is.na(rcept_dt) & Ticker %in% unique(panel$Ticker)]
ev <- unique(bb[, .(Ticker, rcept_dt)])[order(Ticker, rcept_dt)]
# for each panel stock-month, most recent prior event -> age months
pm <- panel[!is.na(Ret_1m), .(Date, Ticker, Ret_1m, BM_Ret)]
pm[, active := Ret_1m - BM_Ret]
# correct latest-prior-event via rolling join. carry matched event date as SEPARATE col
# (join-key ev_dt takes query value, so keep matched_ev to recover the real event date).
evj <- ev[, .(Ticker, ev_dt=rcept_dt, matched_ev=rcept_dt)]; setkey(evj, Ticker, ev_dt)
pm[, jdt := Date]; setkey(pm, Ticker, jdt)
rj <- evj[pm, on=.(Ticker, ev_dt=jdt), roll=TRUE]   # pm-ordered; rj$matched_ev = latest ev<=Date (NA if none)
stopifnot(nrow(rj)==nrow(pm))
pm[, matched_ev := rj$matched_ev]
pm[, ev_age_m := ifelse(is.na(matched_ev), NA_real_, as.numeric(Date - matched_ev)/30.44)]
pm[, jdt := NULL]
pm_ev <- pm[!is.na(ev_age_m)]
pm_ev[, ebucket := fifelse(ev_age_m<1,"0-1m", fifelse(ev_age_m<2,"1-2m", fifelse(ev_age_m<4,"2-4m","4m+")))]
# monthly mean active per bucket -> nw_t
dart_mb <- pm_ev[, .(m_active=mean(active), n=.N), by=.(Date,ebucket)]
dart_bstat <- dart_mb[, .(mean_active=round(mean(m_active),5), nw_t=round(nwt(m_active),3), n_months=.N, tot_obs=sum(n)), by=ebucket]
# contrast fresh(0-1m) - stale(2-4m)
dw <- dcast(dart_mb, Date~ebucket, value.var="m_active")
dart_contrast <- if(all(c("0-1m","2-4m") %in% names(dw))){ z<-dw[!is.na(`0-1m`)&!is.na(`2-4m`)]; z$`0-1m`-z$`2-4m` } else numeric(0)
A1_dart <- list(series="DART_buyback", window="2015-01..2026-06 (crawl limit)", n_events=nrow(ev),
                buckets=dart_bstat[order(match(ebucket,c("0-1m","1-2m","2-4m","4m+")))],
                contrast_fresh_minus_stale_mean=if(length(dart_contrast)>0) round(mean(dart_contrast),5) else NA_real_,
                contrast_nw_t=if(length(dart_contrast)>=5) round(nwt(dart_contrast),3) else NA_real_,
                contrast_n_months=length(dart_contrast))
cat("[A1-DART] fresh-stale active nw_t=", A1_dart$contrast_nw_t, "\n")
OUT$A1 <- list(factor_series=A1, dart_series=A1_dart)

## ===================== A2 holding-age realized active decomposition =====================
# canonical top-25 EW book from score_eff + liq filter (2e8)
build_book <- function(top_n=25L, liq_min=2e8){
  S <- panel[!is.na(score_eff), .(Date,Ticker,score=score_eff,adv=tv20,Ret_1m,BM_Ret,ew_ret,tier)]
  S <- S[is.na(adv) | adv>=liq_min]
  setorder(S, Date, -score)
  W <- S[, .SD[seq_len(min(top_n,.N))], by=Date]
  W[, w := 1/.N, by=Date]
  W
}
book <- build_book()
setorder(book, Ticker, Date); book[, midx:=midx_of(Date)]
book[, midx_prev:=shift(midx), by=Ticker]
book[, new_run := is.na(midx_prev) | (midx-midx_prev)>1L]
book[, hold_age := { a<-integer(.N); c<-0L; for(i in seq_len(.N)){ if(new_run[i]) c<-0L else c<-c+1L; a[i]<-c }; a }, by=Ticker]
book[, hgrp := fifelse(hold_age<=2L,"fresh(<=2m)", fifelse(hold_age>4L,"stale(>4m)","mid"))]
# active contribution per name = w*(Ret_1m - bm)
a2_decomp <- function(bmcol){
  b <- copy(book); b[, contrib := w*(Ret_1m - get(bmcol))]
  grpm <- b[hgrp %in% c("fresh(<=2m)","stale(>4m)"), .(contrib=sum(contrib), n=.N, perName=sum(contrib)/.N), by=.(Date,hgrp)]
  fw <- dcast(grpm, Date~hgrp, value.var="contrib")
  pw <- dcast(grpm, Date~hgrp, value.var="perName")
  setnames(fw, c("fresh(<=2m)","stale(>4m)"), c("fresh_c","stale_c"), skip_absent=TRUE)
  setnames(pw, c("fresh(<=2m)","stale(>4m)"), c("fresh_p","stale_p"), skip_absent=TRUE)
  fw[is.na(fresh_c),fresh_c:=0]; fw[is.na(stale_c),stale_c:=0]
  cdiff <- fw$fresh_c - fw$stale_c
  pmg <- pw[!is.na(fresh_p)&!is.na(stale_p)]; pdiff <- pmg$fresh_p - pmg$stale_p
  list(basis=bmcol,
       fresh_contrib_ann=round(mean(fw$fresh_c)*12,4), stale_contrib_ann=round(mean(fw$stale_c)*12,4),
       contrib_diff_nw_t=round(nwt(cdiff),3), contrib_diff_n=length(cdiff),
       perName_fresh_ann=round(mean(pmg$fresh_p)*12,4), perName_stale_ann=round(mean(pmg$stale_p)*12,4),
       perName_diff_nw_t=round(nwt(pdiff),3), perName_diff_n=length(pdiff))
}
A2 <- list(book_n_months=length(unique(book$Date)), avg_names=round(book[,.N,by=Date][,mean(N)],1),
           avg_hold_age=round(mean(book$hold_age),2),
           frac_fresh=round(mean(book$hgrp=="fresh(<=2m)"),3), frac_stale=round(mean(book$hgrp=="stale(>4m)"),3),
           capw=a2_decomp("BM_Ret"), ewuni=a2_decomp("ew_ret"))
cat("[A2] capw perName_diff nw_t=", A2$capw$perName_diff_nw_t, " ewuni=", A2$ewuni$perName_diff_nw_t, "\n")
OUT$A2 <- A2

## ===================== A3 cap-tier x age =====================
a3_one <- function(sig_name, tau=0.5){
  rankcol <- zc_of(sig_name)
  base <- panel[!is.na(get(rankcol)) & !is.na(Ret_1m), .(Date,Ticker,z=get(rankcol),Ret_1m,tier)]
  age <- add_value_age(panel, rankcol, tau)
  d <- merge(base, age, by=c("Date","Ticker"))
  cell <- d[, {if(.N>=8) .(ic=cor(z,Ret_1m,method="spearman"),n=.N) else .(ic=NA_real_,n=.N)}, by=.(Date,tier,bucket)]
  cs <- cell[!is.na(ic), .(mean_ic=round(mean(ic),4), nw_t=round(nwt(ic),2), n_months=.N), by=.(tier,bucket)]
  cs[order(tier, match(bucket,c("0-1m","1-2m","2-4m","4m+")))]
}
OUT$A3 <- list(score_eff=a3_one("score_eff"), M08=a3_one("M08_Residual_Mom"), V02=a3_one("V02_EP"),
               note="fresh-alpha localization: compare fresh(0-1m) mean_ic across MEGA/MID/OTHER. KA3 if fresh-alpha only OTHER(>50).")
cat("[A3] done\n")

## ===================== A4 economics =====================
# fresh per-name active edge (annual) from A2 (cap-w) ; incremental turnover cost
fresh_edge_capw <- A2$capw$perName_fresh_ann - A2$capw$perName_stale_ann
# implied incremental turnover: a fresh-cohort (hold only while age<=2) rotates ~ every 2-3m vs monthly grid baseline.
# baseline book turnover:
setorder(book, Ticker, Date)
dts <- sort(unique(book$Date)); traded <- numeric(length(dts)); prev <- data.table(Ticker=character(0),w=numeric(0))
for(i in seq_along(dts)){ cur<-book[Date==dts[i],.(Ticker,w)]; m<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"))
  m[is.na(w_c),w_c:=0]; m[is.na(w_p),w_p:=0]; traded[i]<-sum(abs(m$w_c-m$w_p)); prev<-cur }
base_to_ann <- mean(traded)*12
# fresh-cohort implied: fresh names replaced when they age past 2m => extra full-turnover ~ (1/3)/mo of the fresh sleeve
# conservative: incremental turnover = base_to (double rotation cap) ; cost 15bps*2
inc_turn_ann <- base_to_ann  # upper-bound proxy: fresh-cohort at most doubles rotation
inc_cost_ann <- inc_turn_ann * 15/1e4 * 2
# Grinold B2 expected IR: IC (fresh bucket rank-IC for best factor) * sqrt(BR)
best_fresh_ic <- max(sapply(names(series_cols), function(sn){ b<-A1[[sn]]$buckets; v<-b[bucket=="0-1m",mean_ic]; if(length(v)) v else NA }), na.rm=TRUE)
# BR estimate: staggered 3-tranche, ~25 names, ~ effective independent bets/yr
N_names <- 25; tranche_rebal <- c(52/8, 52/13, 52/26)  # 8/13/26wk cadences /yr avg
rebal_per_yr <- mean(tranche_rebal)
BR <- N_names * rebal_per_yr
ir_grinold <- best_fresh_ic * sqrt(BR)
A4 <- list(fresh_perName_edge_capw_ann=round(fresh_edge_capw,4),
           base_book_turnover_ann=round(base_to_ann,3),
           incremental_turnover_ann_proxy=round(inc_turn_ann,3),
           incremental_cost_ann=round(inc_cost_ann,5),
           net_fresh_edge_after_cost=round(fresh_edge_capw - inc_cost_ann,4),
           best_fresh_bucket_ic=round(best_fresh_ic,4),
           grinold_BR_estimate=round(BR,1), grinold_expected_IR=round(ir_grinold,3),
           ir_threshold=0.63, ir_meets_threshold=isTRUE(ir_grinold>=0.63),
           note="Grinold IR=IC*sqrt(BR). BR=25 names x mean(8/13/26wk cadence). IC=best fresh(0-1m) rank-IC. Cost = 15bps*2*incr turnover (upper-bound proxy).")
cat("[A4] expected IR=", A4$grinold_expected_IR, " (thr 0.63) net fresh edge=", A4$net_fresh_edge_after_cost, "\n")
OUT$A4 <- A4

## ===================== A5 census =====================
# (a) VETO dilutive events — not crawled
A5a <- list(arm="VETO_dilutive", status="미가용",
            reason="유상증자(piicDecsn)/CB(cvbdIsDecsn) NOT in crawled DART cache (.cache/dart has only 자기주식취득 buyback + insider). No dilutive-event stream => binding stock-months uncomputable.",
            threshold=40, binding_stock_months=NA)
# (b) PROMOTE: rank 21-40 band x fresh buyback (age<=3m), 2015+ window
# per month: rank tradeable liq in_univ by score_eff; band = rank 21-40
Sb <- panel[!is.na(score_eff), .(Date,Ticker,score=score_eff,adv=tv20)]
Sb <- Sb[is.na(adv)|adv>=2e8]; setorder(Sb, Date, -score); Sb[, rk:=seq_len(.N), by=Date]
band <- Sb[rk>=21 & rk<=40]
# fresh buyback age at Date
band <- merge(band, pm[, .(Date,Ticker,ev_age_m)], by=c("Date","Ticker"), all.x=TRUE)
band[, fresh_bb := !is.na(ev_age_m) & ev_age_m<=3]
band_2015 <- band[Date>=as.Date("2015-01-01")]
A5b <- list(arm="PROMOTE_fresh_buyback", window="2015+ (crawl limit)",
            band_stock_months_2015=nrow(band_2015),
            binding_stock_months=sum(band_2015$fresh_bb),
            threshold=60, meets=isTRUE(sum(band_2015$fresh_bb)>=60),
            binding_by_year=band_2015[fresh_bb==TRUE, .N, by=.(yr=format(Date,"%Y"))][order(yr)])
cat("[A5] PROMOTE binding stock-months(2015+)=", A5b$binding_stock_months, " (thr 60)\n")
OUT$A5 <- list(a_veto=A5a, b_promote=A5b)

## ===================== A6 episodes (advisory) =====================
bm_nav <- copy(bm_m)[order(ym)]; bm_nav[, nav:=cumprod(1+bm_ret)]; bm_nav[, peak:=cummax(nav)]; bm_nav[, dd:=nav/peak-1]
bm_nav[, regime := fifelse(dd<=-0.10,"drawdown", fifelse(dd< -0.02,"recovery","normal"))]
bk_active <- book[, .(port=sum(w*Ret_1m), bm=BM_Ret[1]), by=Date]; bk_active[, active:=port-bm]
bk_active[, ym:=format(Date,"%Y-%m")]
bk_active <- merge(bk_active, bm_nav[,.(ym,regime,dd)], by="ym", all.x=TRUE)
A6 <- bk_active[!is.na(regime), .(mean_active_monthly=round(mean(active),5), nw_t=round(nwt(active),2), n_months=.N), by=regime]
OUT$A6 <- list(by_regime=A6[order(match(regime,c("drawdown","recovery","normal")))],
               note="ADVISORY only (not a gate). score_eff top-25 book net active by benchmark drawdown regime (dd<=-10 drawdown / -10..-2 recovery / else normal).")
cat("[A6] done\n")

## ===================== KILL JUDGMENTS =====================
factor_contrasts <- sapply(names(series_cols), function(sn) A1[[sn]]$contrast_nw_t)
a2_contrasts <- c(A2$capw$perName_diff_nw_t, A2$ewuni$perName_diff_nw_t)
all_contrasts <- c(factor_contrasts, dart=A1_dart$contrast_nw_t, a2_capw=A2$capw$perName_diff_nw_t, a2_ew=A2$ewuni$perName_diff_nw_t)
KA1_all_below <- all(all_contrasts < 2.0, na.rm=TRUE)
# KA3 fresh-alpha localization: fresh(0-1m) mean_ic per tier for score_eff
a3se <- OUT$A3$score_eff
fresh_by_tier <- sapply(c("MEGA","MID","OTHER"), function(tt){ v<-a3se[tier==tt & bucket=="0-1m", mean_ic]; if(length(v)) v else NA })
KA3_only_other <- (is.na(fresh_by_tier["MEGA"]) || fresh_by_tier["MEGA"]<=0) &&
                  (is.na(fresh_by_tier["MID"]) || fresh_by_tier["MID"]<=0) &&
                  (!is.na(fresh_by_tier["OTHER"]) && fresh_by_tier["OTHER"]>0)
OUT$kill_judgments <- list(
  all_contrast_nw_t=as.list(round(all_contrasts,3)),
  KA1_met=KA1_all_below,
  KA1_note="KA1 met => 'signal slow enough for monthly grid; no sampling component in wall' DISTILLED_NEG. B1 may still enter via A5 census independently.",
  KA3_fresh_ic_by_tier=as.list(round(fresh_by_tier,4)),
  KA3_met=KA3_only_other,
  KA4_met=!A4$ir_meets_threshold, KA4_note="KA4 met (economics below thr) => B2 blocked",
  KA5_met=!A5b$meets, KA5_note="KA5 met (census below thr) => B1 backtest 0",
  KA5a_veto="미가용 — dilutive event data absent (not a census-starvation kill; data-absence)"
)
cat("\n[KILL] KA1(all<2.0)=", KA1_all_below, " KA3(only OTHER)=", KA3_only_other,
    " KA4(econ fail)=", !A4$ir_meets_threshold, " KA5(census fail)=", !A5b$meets, "\n")

## ---------- write ----------
write_json(OUT, file.path(SA,"alpha_stageA_diagnostics.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("\n[WRITE] alpha_stageA_diagnostics.json\n")
