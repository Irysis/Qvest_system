# run_02: 방어후보 진단표 persist + alpha_vector + alpha_package.json emit + lineage
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/method_frontier/wt_d20260718_001_crash_aware_mom/ca_lib.R")
WT <- "WT-D20260718_001"
MBOX <- file.path(ROOT_CA, "qepm/mailbox/worktask", WT)

P <- load_panels_f58(); reb_yms <- P$yms[P$yms>=201001L & P$yms<=202605L]
bench_m <- build_bench_m(P); market_by_ym <- setNames(bench_m$bm_ret, as.character(bench_m$ym))
store <- precompute_store_ca(P, reb_yms, market_by_ym)
all_dates <- as.Date(sort(sapply(store,function(s)as.numeric(s$date))),origin="1970-01-01")
is_cut <- all_dates[floor(0.65*length(all_dates))]

# --- defensive candidate diagnostic table (full + IS/OOS MDD + crisis) -------
cand <- expand.grid(pd=c("none","downside_semivol","downside_beta","crash_exposure","ncskew","composite"),
                    lam=c(0.25,0.5,1.0), stringsAsFactors=FALSE)
cand <- cand[!(cand$pd=="none" & cand$lam!=0.25),]  # base once
diag_rows <- list()
for (i in seq_len(nrow(cand))) {
  pd<-cand$pd[i]; lam<-if(pd=="none") 0 else cand$lam[i]
  inp <- assemble_inputs_ca(store, pd, lam)
  res <- run_canon(inp, 25L, size_dt=NULL, run_id=paste0(pd,lam), diag=FALSE)
  pr <- as.data.table(res$period_returns); setorder(pr,date)
  fx<-xts(pr$ret_net,pr$date); isx<-fx[index(fx)<=is_cut]; oox<-fx[index(fx)>is_cut]
  cri<-crisis_conditional(res)
  prO<-pr[date>is_cut]
  cagr<-as.numeric(Return.annualized(fx,scale=12,geometric=TRUE)); mdd<-as.numeric(maxDrawdown(fx))
  diag_rows[[i]]<-data.table(penalty=pd, lambda=lam,
    full_port_t=round(nw_t_f(pr$ret_net-pr$benchmark_ret)$t,3),
    oos_port_t=round(nw_t_f(prO$ret_net-prO$benchmark_ret)$t,3),
    full_calmar=round(cagr/mdd,3), full_mdd=round(mdd,3),
    is_mdd=round(as.numeric(maxDrawdown(isx)),3), oos_mdd=round(as.numeric(maxDrawdown(oox)),3),
    crisis_active_bad=round(cri$active_bad_mean,5), bad_sr=round(cri$bad_sr,2),
    net_sr=round(ann_sr_f(pr$ret_net),3))
  if (pd=="none") base_pt<-diag_rows[[i]]$full_port_t
}
dtab <- rbindlist(diag_rows)
write_parquet(dtab, file.path(OUT_CA,"ca_defensive_diagnostic.parquet"))
cat("=== defensive diagnostic table ===\n"); print(dtab)

# --- alpha_vector: pre-registered selected (composite_l1) latest month --------
sel_pd <- "composite"; sel_lam <- 1.0
last_key <- names(store)[length(store)]
s_last <- store[[last_key]]
zpen <- s_last$z_comp[s_last$elig]; zpen[!is.finite(zpen)]<-0
score_last <- s_last$z_mom[s_last$elig] - sel_lam*as.numeric(zpen)
names(score_last)<-s_last$elig; score_last<-score_last[is.finite(score_last)]
# active alpha proxy (cross-sectional z -> expected active, scaled by realized IR ~ modest)
alpha_vec <- setNames(round(as.numeric(score_last)*0.004,6), names(score_last))  # z*0.4%/z (documented proxy scale)
# confidence: |z| percentile within month (rank-stability proxy)
conf <- rank(abs(score_last))/length(score_last)
conf_vec <- setNames(round(as.numeric(conf),4), names(score_last))
cat("\n[alpha_vector] as_of month:", last_key, " n:", length(alpha_vec),
    " top5:", paste(names(sort(score_last,decreasing=TRUE))[1:5],collapse=","), "\n")

saveRDS(list(dtab=dtab, alpha_vec=alpha_vec, conf_vec=conf_vec, as_of=last_key, is_cut=as.character(is_cut)),
        file.path(OUT_CA,"ca_finalize.rds"))
cat("[run_02] finalize objects saved.\n")
