# run5_consolidate.R — assemble master variant table + placebo + attribution into CSVs for report.
suppressMessages({library(data.table); library(jsonlite)})
OUT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/probe_benchmark_relative_construction_20260705"
p1<-readRDS(file.path(OUT,"phase1_base_enh.rds"))
p2<-readRDS(file.path(OUT,"phase2_sh_anchor.rds"))
p3<-readRDS(file.path(OUT,"phase3_attribution.rds"))
p4<-readRDS(file.path(OUT,"phase4_controls.rds"))
PT<-function(r) if(is.null(r)) NA_real_ else r$portfolio_alpha_t_nw_lag3
IRf<-function(r) if(is.null(r)) NA_real_ else r$information_ratio
TOf<-function(r) if(is.null(r)) NA_real_ else r$turnover_annual

# best ENH by full PORT_t
enh<-p1$enh; enh_pt<-sapply(enh,function(x)PT(x$full)); best_te<-names(which.max(enh_pt))
enh_best<-enh[[best_te]]

master<-rbindlist(list(
 data.table(variant="BASE (abs top-25 EW)",              full_PORT_t=PT(p1$res$BASE),        rec2017_PORT_t=PT(p1$res$BASE_rec),  IR=IRf(p1$res$BASE),        TO_yr=TOf(p1$res$BASE),        note="validity anchor (matches 0.9698)"),
 data.table(variant=sprintf("ENH-IDX best (TE=%.0f%%)",as.numeric(best_te)*100), full_PORT_t=PT(enh_best$full), rec2017_PORT_t=PT(enh_best$rec), IR=IRf(enh_best$full), TO_yr=TOf(enh_best$full), note="soft benchmark-relative tilt; cap binds mega-cap"),
 data.table(variant="SHORT-HARVEST best (drop 30%)",     full_PORT_t=PT(p2$res$SH_30),       rec2017_PORT_t=PT(p2$res$SH_30_rec), IR=IRf(p2$res$SH_30),       TO_yr=TOf(p2$res$SH_30),       note="drop worst-signal, redistribute cap-wt"),
 data.table(variant="ANCHOR (top-2@20% + alpha-fill)",   full_PORT_t=PT(p2$res$ANCHOR),      rec2017_PORT_t=PT(p2$res$ANCHOR_rec),IR=IRf(p2$res$ANCHOR),      TO_yr=TOf(p2$res$ANCHOR),      note="mega-cap anchor; WINNER"),
 data.table(variant="ANCHOR bottom-fill (placebo)",      full_PORT_t=PT(p2$res$ANCHOR_bottom),rec2017_PORT_t=NA,                  IR=IRf(p2$res$ANCHOR_bottom),TO_yr=TOf(p2$res$ANCHOR_bottom),note="placebo: worst alpha fill"),
 data.table(variant="ANCHOR random-fill (placebo mean)", full_PORT_t=mean(p2$rand_pt),       rec2017_PORT_t=NA,                  IR=NA,                      TO_yr=NA,                      note=sprintf("20 seeds; sd=%.2f, p(rand>=alpha)=%.3f",sd(p2$rand_pt),p2$p_rand)),
 data.table(variant="ANCHOR lag1 (PIT graceful)",        full_PORT_t=PT(p2$res$ANCHOR_lag1), rec2017_PORT_t=NA,                  IR=IRf(p2$res$ANCHOR_lag1), TO_yr=TOf(p2$res$ANCHOR_lag1), note="t-1 signal+bench; no leak"),
 data.table(variant="CTRL anchor + SIZE-fill (no alpha)",full_PORT_t=p3$ablation[spec=="CTRL_anchor2x20_SIZEfill23"]$full_PORT_t, rec2017_PORT_t=p3$ablation[spec=="CTRL_anchor2x20_SIZEfill23"]$rec2017_PORT_t, IR=NA, TO_yr=NA, note="anchor w/o alpha -> no lift"),
 data.table(variant="ALPHA cap-wt top-25 (no anchor)",   full_PORT_t=PT(p4$alpha_capw[[1]]), rec2017_PORT_t=PT(p4$alpha_capw[[2]]),IR=NA,                     TO_yr=NA,                      note="cap-wt alpha winners, no forced mega-cap"),
 data.table(variant="ALPHA-fill + mega-cap NAT cap-wt",  full_PORT_t=PT(p4$alpha_megacap[[1]]),rec2017_PORT_t=PT(p4$alpha_megacap[[2]]),IR=NA,                 TO_yr=NA,                      note="must-hold mega-cap at natural wt (~A1)")
))
master[, `:=`(full_PORT_t=round(full_PORT_t,3), rec2017_PORT_t=round(rec2017_PORT_t,3), IR=round(IR,3), TO_yr=round(TO_yr,2))]
fwrite(master, file.path(OUT,"master_variant_table.csv"))
cat("=== MASTER VARIANT TABLE ===\n"); print(master)

cat("\n=== ANCHOR active-return attribution (ann %, by role) ===\n")
at<-p3$attribution; at[,ann_pct:=round(ann_contrib*100,2)]; print(at[,.(role,ann_pct)])

cat("\n=== ADVERSARIAL SUMMARY ===\n")
cat(sprintf("(a) placebo: ANCHOR alpha-fill %.2f vs bottom-fill %.2f (edge +%.2f); random-fill mean %.2f sd %.2f; p(rand>=alpha)=%.3f\n",
    PT(p2$res$ANCHOR), PT(p2$res$ANCHOR_bottom), PT(p2$res$ANCHOR)-PT(p2$res$ANCHOR_bottom), mean(p2$rand_pt), sd(p2$rand_pt), p2$p_rand))
cat(sprintf("(b) lag1 PIT: %.2f (vs t0 %.2f) -> graceful, no reversal\n", PT(p2$res$ANCHOR_lag1), PT(p2$res$ANCHOR)))
cat(sprintf("(c) concentration: median top-2 wt %.3f, HHI %.4f (40%% in 2 names = real risk)\n", median(p2$anc_conc$top2), median(p2$anc_conc$hhi)))
cat(sprintf("(d) short-side attribution: underweight bucket = %.2f%%/yr (NEGATIVE -> short-side NOT additive)\n", at[role=="underweight"]$ann_pct))
cat(sprintf("(bench recon) hold b_i -> active PORT_t %.2f (recon drag ~%.4f/mo vs true BM_Ret)\n", PT(p4$bench_hold), p4$bench_hold$mean_active_net))
cat("\nCONSOLIDATED.\n")
