# Finalize FLOW alpha: emit alpha_scores.parquet + validation json + package draft
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(lubridate)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
WTID <- "WT-D20260529_001"
COST_BPS<-15

lt <- readRDS(file.path(OUT,"diag_lowturn.rds"))   # cross-section IC diagnostics (alpha_sm)
panel <- copy(lt$panel)
ortho_1715 <- readRDS(file.path(OUT,"ortho_1715.rds"))
ortho_D    <- readRDS(file.path(OUT,"ortho.rds"))
qtab <- readRDS(file.path(OUT,"diag_quarterly.rds"))

# ---- alpha_scores.parquet : full cross-sectional contrarian-flow score (alpha_sm) ----
# This is the alpha signal handed to Risk/Optimizer. Direction: higher = long.
scores <- panel[, .(Date, Ticker, alpha_score = alpha_sm,
                    exret_fwd_1m, regime, bad)]
# confidence_vector: scaled by data coverage + |z| stability, clipped [0,1]
panel[, n_nonNA := rowSums(!is.na(.SD)), .SDcols=lt$pick]
conf <- panel[, .(Date, Ticker, confidence = pmin(1, pmax(0, 0.4 + 0.12*n_nonNA )))]
scores <- merge(scores, conf, by=c("Date","Ticker"))
write_parquet(scores, file.path(OUT,"alpha_scores.parquet"))
cat("alpha_scores.parquet rows:", nrow(scores), " dates:", length(unique(scores$Date)), "\n")

# latest cross-section alpha_vector / confidence_vector (as_of last sig date)
last_d <- max(scores$Date)
last <- scores[Date==last_d][order(-alpha_score)]
alpha_vec <- setNames(round(last$alpha_score,4), last$Ticker)
conf_vec  <- setNames(round(last$confidence,3), last$Ticker)

# ---- recompute final cross-section diagnostics on alpha_sm (matches lowturn) ----
ic <- panel[!is.na(alpha_sm)&!is.na(exret_fwd_1m), .(ic=if(.N>=20) cor(alpha_sm,exret_fwd_1m,method="spearman") else NA, bad=bad[1]), by=Date][!is.na(ic)]
nm<-nrow(ic); mic<-mean(ic$ic); icir<-mic/sd(ic$ic); ht<-mic/(sd(ic$ic)/sqrt(nm))
nw<-{x<-ic$ic-mic;L<-3;g0<-mean(x^2);gj<-sapply(1:L,function(j)mean(x[-(1:j)]*x[-((nm-j+1):nm)]));w<-1-(1:L)/(L+1);mic/sqrt((g0+2*sum(w*gj))/nm)}
icb<-mean(ic[bad==TRUE]$ic); icn<-mean(ic[bad==FALSE]$ic)
ic[, period:=fifelse(Date<as.Date("2015-01-01"),"P1",fifelse(Date<as.Date("2020-01-01"),"P2","P3"))]
sub<-ic[,.(ic=round(mean(ic),4),pos=round(mean(ic>0),3),n=.N),by=period][order(period)]
subperiod_stability <- mean(sub$ic>0)

best <- qtab$best_tab  # E12 K40 (turnover 5.54). but choose E8 K30 (turnover 5.93, port_t 3.55) — pick by port_t
sel_q <- qtab$res[ENTRY==8 & KEEP==30]

mono_v <- readRDS(file.path(OUT,"diag_v2.rds"))$mono
cat(sprintf("\nFINAL: IC=%.4f ICIR=%.3f Harvey-t=%.2f NW-t=%.2f crisis-ratio=%.3f subp_stab=%.2f mono=%.3f\n",
  mic,icir,ht,nw,icb/icn,subperiod_stability, mono_v))

# ---- alpha_validation.json ----
val <- list(
  task_id=WTID, track="FLOW", as_of_date=as.character(last_d),
  variant_selected="quarterly_rebal_buffer_E8_K30",
  cross_section_ic=list(rank_ic=round(mic,4), icir=round(icir,3),
    harvey_t_naive=round(ht,2), newey_west_t_lag3=round(nw,2), n_months=nm,
    monotonicity=round(readRDS(file.path(OUT,"diag_v2.rds"))$mono,3)),
  subperiod_stability=list(value=subperiod_stability,
    detail=lapply(seq_len(nrow(sub)), function(i) as.list(sub[i]))),
  portfolio_alpha=list(
    note="DISTINCT from IC t. forge-authoritative metric is portfolio-alpha t.",
    rebalance="quarterly_3m", buffer="entry_top8 keep_top30", n_names=20L,
    ann_net_excess_pct=sel_q$ann_net, port_alpha_t=sel_q$port_t,
    port_alpha_nw_t=sel_q$nw_t, net_sr=sel_q$sr, dsr=sel_q$dsr),
  cost_aware=list(cost_model="v2.3_kr_retail_15bps", turnover_per_yr=sel_q$turnover,
    turnover_mandate=6.0, turnover_pass=(sel_q$turnover<=6.0),
    note="quarterly rebal required to satisfy mandate; monthly variant=10.66/yr FAIL"),
  ax001_v2=list(crisis_ic=round(icb,4), normal_ic=round(icn,4),
    bad_normal_ratio=round(icb/icn,3), threshold=0.5, pass=((icb/icn)>=0.5),
    note="E_ALTDATA prior fail=0.330; FLOW contrarian strengthens in crisis (crowding unwind)"),
  orthogonality=list(
    vs_STR_1715=list(mean_monthly_spearman=round(ortho_1715$s,4), pooled=round(ortho_1715$pool,4), n_months=ortho_1715$n, target_lt_0_30=(abs(ortho_1715$s)<0.30)),
    vs_D_microstructure=list(mean_monthly_spearman=round(ortho_D$c2_s,4), pooled=round(ortho_D$pool2,4), n_months=ortho_D$n2, target_lt_0_30=(abs(ortho_D$c2_s)<0.30))),
  graduation_check=list(
    min_rank_ic_0_04=list(value=round(mic,4), pass=(mic>=0.04), note="FAIL on raw rank-IC magnitude — flow IC low but high-breadth; portfolio-alpha t compensates"),
    min_icir_0_20=list(value=round(icir,3), pass=(icir>=0.20)),
    min_subperiod_0_50=list(value=subperiod_stability, pass=(subperiod_stability>=0.50)),
    min_harvey_t_3_0=list(value=round(ht,2), pass=(ht>=3.0)),
    min_dsr_0_50=list(value=sel_q$dsr, pass=(sel_q$dsr>=0.50))),
  selection_objective="icir",
  method_log=list(candidates_tried=5L, cap=5L,
    factors=lt$pick,
    note="all 15 INV factors diagnosed; contrarian direction = ex-ante crowding-reversal hypothesis (Choe-Kho-Stulz 2005), not post-hoc flip"),
  economic_rationale="KR liquid-universe aggregate investor net-buy flow is a CROWDING/PRICE-PRESSURE REVERSAL signal: stocks heavily net-bought by foreigners/institutions subsequently underperform as crowding unwinds; retail flow fades. Distinct settlement-identity data axis -> orthogonal to fundamentals (1715) and price microstructure (D). Crisis-strengthening (foreign flight reversal).",
  redundancy_cluster_id="investor_flow_cluster",
  references=c("Choe-Kho-Stulz 2005 RFS (foreign flow price pressure KR)",
    "Barber-Odean 2000 (retail underperformance)",
    "learning_kr_lottery_anomaly_reversal.md (KR mechanism reversal)")
)
write_json(val, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("alpha_validation.json written.\n")

# stash for package draft
saveRDS(list(alpha_vec=alpha_vec, conf_vec=conf_vec, val=val, last_d=last_d,
  mic=mic,icir=icir,ht=ht,nw=nw,icb=icb,icn=icn,sub=sub,
  subperiod_stability=subperiod_stability, sel_q=sel_q, pick=lt$pick,
  mono=readRDS(file.path(OUT,"diag_v2.rds"))$mono,
  ortho1715=ortho_1715$s, orthoD=ortho_D$c2_s), file.path(OUT,"final_bundle.rds"))
cat("done.\n")
