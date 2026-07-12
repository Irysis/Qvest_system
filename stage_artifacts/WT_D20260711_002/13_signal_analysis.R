#==============================================================================
# WT-D20260711_002 Phase A — Step 13: signal panel + rank-IC + canonical + diags
# FROZEN measurement (preregistration.json sha256 96b7e06d...).
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(stringi) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
CACHE <- file.path(OUT, "text_cache")
source(file.path(OUT, "metrics_lib.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
set.seed(20260711)
ym_add <- function(ym, k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym%/%100L, ym%%100L))
spear <- function(x,y){ ok<-is.finite(x)&is.finite(y); if(sum(ok)<3) return(NA_real_)
  suppressWarnings(tryCatch(cor(x[ok],y[ok],method="spearman"), error=function(e) NA_real_)) }
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<8) return(NA_real_)
  mu<-mean(x); e<-x-mu; g0<-sum(e^2)/n; v<-g0
  for(L in 1:min(lag,n-1)){ w<-1-L/(lag+1); g<-sum(e[1:(n-L)]*e[(L+1):n])/n; v<-v+2*w*g }
  se<-sqrt(v/n); if(!is.finite(se)||se<=0) return(NA_real_); mu/se }

# ---- 1. combine metrics parts ----
parts <- list.files(CACHE, pattern="^metrics_part_.*\\.parquet$", full.names=TRUE)
M <- rbindlist(lapply(parts, function(p) as.data.table(read_parquet(p))), fill=TRUE)
M <- unique(M, by="rcept_no")
cat("[13] metrics rows:", nrow(M), " ok:", sum(M$status=="ok"), " no_section:", sum(M$status=="no_section"), "\n")
M <- M[status=="ok" & !is.na(m1_avg_sentence_len_chars)]
M[, rcept_ym := as.integer(substr(rcept_dt,1,4))*100L + as.integer(substr(rcept_dt,5,6))]

# ---- 2. m6 boilerplate YoY (per ticker consecutive fy on section_head) ----
setorder(M, Ticker, fy)
M[, ng := lapply(section_head, function(s) if(is.na(s)) character(0) else char_ngram_set(s,5L))]
M[, m6_boilerplate_yoy := NA_real_]
for (tk in unique(M$Ticker)) {
  idx <- which(M$Ticker==tk); if (length(idx)<2) next
  sub <- M[idx]; setorder(sub, fy)
  for (j in 2:nrow(sub)) if (sub$fy[j]-sub$fy[j-1]==1L) {
    M[idx[j], m6_boilerplate_yoy := jaccard(sub$ng[[j]], sub$ng[[j-1]])]
  }
}
M[, ng := NULL]
cat("[13] m6 boilerplate computed (non-NA):", sum(!is.na(M$m6_boilerplate_yoy)), "\n")

# ---- 3. convergent validity vs pilot LLM complexity (45 docs, return-blind) ----
conv <- tryCatch({
  pil_meta <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260711_001/excerpts_meta.parquet")))
  pil_sc <- fread(file.path(ROOT,"stage_artifacts/WT_D20260711_001/scores.csv"))
  pil <- merge(pil_meta[,.(doc_id,rcept_no,Ticker,fiscal_year)], pil_sc[,.(doc_id,tone,uncertainty,complexity)], by="doc_id")
  cm <- merge(pil, M[,.(rcept_no,m1_avg_sentence_len_chars,m2_fog_kr,m3_hanja_latin_density,
                        m4_numeric_table_density,m5_section_nchar,m6_boilerplate_yoy)], by="rcept_no")
  cat("[13] convergence sample (pilot∩fullcorpus by rcept_no):", nrow(cm), "\n")
  cm[, logm5 := log(m5_section_nchar)]
  metrics6 <- c("m1_avg_sentence_len_chars","m2_fog_kr","m3_hanja_latin_density",
                "m4_numeric_table_density","logm5","m6_boilerplate_yoy")
  cv <- sapply(metrics6, function(mm) spear(cm[[mm]], cm$complexity))
  # composite (4 clear metrics) z on this small set
  z <- function(v) (v-mean(v,na.rm=TRUE))/sd(v,na.rm=TRUE)
  cm[, comp := rowMeans(cbind(z(m1_avg_sentence_len_chars),z(m2_fog_kr),z(m3_hanja_latin_density),z(logm5)), na.rm=TRUE)]
  cv_comp <- spear(cm$comp, cm$complexity)
  list(n=nrow(cm), per_metric_vs_llm_complexity=as.list(round(cv,3)), composite_vs_llm_complexity=round(cv_comp,3))
}, error=function(e) list(error=conditionMessage(e)))
print(conv)

# ---- 4. monthly panel + returns ----
mp <- readRDS(file.path(OUT,"monthly_panel.rds")); me<-mp$me; bench<-mp$bench_m
# forward 1M returns keyed at signal month t (Date=firstOfMonth(t)); Ret_1m realized in t+1
me[, sig_date := ym2date(ym)]
returns_dt <- me[, .(Ticker, ym, Ret_1m_next = NA_real_)]  # placeholder
# build ret at t = mret of t+1
me2 <- me[, .(Ticker, ym, mret, Size, adv20, K200, KQ150)]
setkey(me2, Ticker, ym)
nxt <- copy(me2)[, ym_prev := ym_add(ym, -1L)]          # this row's return attributed to previous month t
ret_at_t <- nxt[, .(Ticker, ym=ym_prev, Ret_1m=mret)]
bench_at_t <- bench[, .(ym=ym_add(ym,-1L), BM_Ret=bench_mret)]

# ---- 5. signal cross-section per month with PIT carry (<=12m) ----
# for each month t, each ticker's active metric = latest doc with active_from<=t and t-active_from<=12
D <- M[, .(Ticker, fy, rcept_ym, m1=m1_avg_sentence_len_chars, m2=m2_fog_kr,
           m3=m3_hanja_latin_density, m4=m4_numeric_table_density, m5=log(m5_section_nchar),
           m6=m6_boilerplate_yoy)]
D[, active_from := ym_add(rcept_ym, 1L)]
setorder(D, Ticker, active_from)
months <- sort(unique(me$ym)); months <- months[months>=201101 & months<=202506]
panel_list <- list()
for (t in months) {
  # candidate signals active at t
  a <- D[active_from<=t]
  if (nrow(a)==0) next
  a[, age := ( (t%/%100L)*12L + t%%100L ) - ( (active_from%/%100L)*12L + active_from%%100L )]
  a <- a[age<=12]
  if (nrow(a)==0) next
  a <- a[order(Ticker,-active_from)][, .SD[1], by=Ticker]   # latest active
  a[, ym := t]
  panel_list[[as.character(t)]] <- a[, .(Ticker, ym, m1,m2,m3,m4,m5,m6, age)]
}
P <- rbindlist(panel_list)
# eligibility: in K200|KQ150 at t and adv20>=2e8
elig <- me[, .(Ticker, ym, Size, adv20, K200, KQ150)]
P <- merge(P, elig, by=c("Ticker","ym"))
P <- P[(K200==1|KQ150==1) & !is.na(adv20) & adv20>=2e8 & !is.na(Size) & Size>0]
# cross-sectional z per month, composite (4 clear metrics)
zc <- function(v) { s<-sd(v,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(0,length(v))); (v-mean(v,na.rm=TRUE))/s }
P[, `:=`(z1=zc(m1), z2=zc(m2), z3=zc(m3), z5=zc(m5)), by=ym]
P[, obfuscation_composite := rowMeans(cbind(z1,z2,z3,z5))]
P[, score := -obfuscation_composite]                     # higher = clearer = long
# attach forward return + bench
P <- merge(P, ret_at_t, by=c("Ticker","ym"), all.x=TRUE)
P <- merge(P, bench_at_t, by="ym", all.x=TRUE)
P[, fwd_excess := Ret_1m - BM_Ret]
cat("[13] signal-months:", uniqueN(P$ym), " avg names/mo:", round(nrow(P)/uniqueN(P$ym),1),
    " total obs:", nrow(P), "\n")
saveRDS(P, file.path(OUT,"signal_panel.rds"))

# ---- 6. monthly rank-IC (composite obfuscation vs fwd excess) + family ----
ic_series <- function(scorevar) {
  s <- P[!is.na(fwd_excess) & is.finite(get(scorevar)),
         .(ic=spear(get(scorevar), fwd_excess), n=.N), by=ym][n>=10]
  s[is.finite(ic)]
}
metrics_family <- c("obfuscation_composite","m1","m2","m3","m4","m5","m6")
famtab <- rbindlist(lapply(metrics_family, function(v){
  ics <- ic_series(v)
  data.table(metric=v, mean_ic=mean(ics$ic), icir=mean(ics$ic)/sd(ics$ic),
             harvey_t=nw_t(ics$ic), n_months=nrow(ics))
}))
cat("\n[13] === monthly rank-IC family (metric vs fwd 1M excess) ===\n"); print(famtab)
null_max_t <- max(abs(famtab$harvey_t), na.rm=TRUE)
cat("[13] null max |Harvey-t| across family:", round(null_max_t,3), "\n")

# ---- 7. canonical_screen_bt dual-basis (score=-composite) IS/OOS/full ----
scores_dt <- P[, .(Date=ym2date(ym), Ticker, score)]
returns_all <- ret_at_t[, .(Date=ym2date(ym), Ticker, Ret_1m)]
bench_all <- bench_at_t[, .(Date=ym2date(ym), BM_Ret)]
size_all <- me[, .(Date=ym2date(ym), Ticker, Size)]
liq_all  <- me[, .(Date=ym2date(ym), Ticker, adv=adv20)]
run_canon <- function(dsub, tag){
  sc <- scores_dt[Date %in% dsub]
  canonical_screen_bt(sc, returns_all, bench_all, top_n=25L, cost_bps_oneway=15,
    liq_dt=liq_all, liq_min=2e8, size_dt=size_all, diag_dual_basis=TRUE,
    run_id=paste0("wt002_",tag), strategy_id=paste0("obf_clarity_",tag))
}
alldates <- sort(unique(scores_dt$Date))
is_dates  <- alldates[alldates <  as.Date("2019-01-01")]
oos_dates <- alldates[alldates >= as.Date("2019-01-01")]
canon_full <- run_canon(alldates, "full")
canon_is   <- run_canon(is_dates, "IS")
canon_oos  <- run_canon(oos_dates, "OOS")
pick <- function(c) list(n_months=c$n_months, port_t=c$portfolio_alpha_t_nw_lag3,
  pval=c$portfolio_alpha_t_pvalue, IR=c$information_ratio, net_sr=c$net_sr,
  alpha_ann=c$alpha_annualized, turnover=c$turnover_annual,
  ew_port_t=c$diag_ew_universe$portfolio_alpha_t_nw_lag3,
  ew_post2017_t=c$diag_ew_universe$post2017_t_nw_lag3,
  ew_oos=c$diag_ew_universe$oos_retention_approx,
  capw_mega_wshare=c$diag_cap_tier$weight_share_avg$MEGA,
  capw_mid_wshare=c$diag_cap_tier$weight_share_avg$MID)
cat("\n[13] === canonical (score=-obfuscation_composite, top25 EW, 15bps, liq2e8) ===\n")
cat("FULL:\n"); print(pick(canon_full))
cat("IS(<2019):\n"); print(pick(canon_is))
cat("OOS(>=2019):\n"); print(pick(canon_oos))

saveRDS(list(famtab=famtab, null_max_t=null_max_t, conv=conv,
             canon_full=canon_full, canon_is=canon_is, canon_oos=canon_oos),
        file.path(OUT,"analysis_results.rds"))

# alpha_scores.parquet (latest month cross-section for schema)
last_ym <- max(P$ym)
as_out <- P[ym==last_ym, .(Ticker, obfuscation_composite, score, m1,m2,m3,m5, ym)]
write_parquet(as_out, file.path(OUT,"alpha_scores.parquet"))
cat("\n[13] DONE. alpha_scores latest month:", last_ym, " N:", nrow(as_out), "\n")
