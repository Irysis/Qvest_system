cat("=== STR_1631 v5 M22: HRP + C19 5F (Q07_Earnings_Stability 추가) ===\n")
## 핵심 아이디어: C19 4F → 5F (Q07_Earnings_Stability 추가)
## Mutation M_A2: C19_5F = (z_SUE + z_ESBR + z_EPS_CHG_1M + z_TP_Gap + z_Q07) / 5
## C13 준수: Factor DB Z_Score_Aligned 사용 (Q07)
## C15 준수: load_month_factors() 경유
## Orthogonality gate: Q07는 Quality family → C19(Consensus)와 독립적
## 기반: STR_1631 v5 M11 (Gerber + RMT + HRP)

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment Setup
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
CONS_DIR   <- file.path(CACHE_DIR, "consensus")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))  # C15

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(tidyr); library(lubridate); library(jsonlite)
})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul")

LIQ_THRESHOLD <- 2e8; N_HOLD <- 20L; MAX21D_EXCL <- 0.80; HRP_LOOKBACK <- 60L
Q07_FACTOR <- "Q07_Earnings_Stability"
cat(sprintf("[setup] 5F composite: z_SUE + z_ESBR + z_EPS1M + z_TP_Gap + z_%s\n", Q07_FACTOR))

# ═══════════════════════════════════════════════════════════════════
# Gerber + RMT + HRP
# ═══════════════════════════════════════════════════════════════════
gerber_cor <- function(ret_matrix, threshold=0.5) {
  n <- ncol(ret_matrix); mat <- matrix(0, n, n)
  med_abs <- apply(ret_matrix, 2, function(x) median(abs(x), na.rm=TRUE))
  med_abs <- ifelse(med_abs < 1e-12, apply(ret_matrix, 2, sd, na.rm=TRUE), med_abs)
  for (i in seq_len(n)) {
    ti <- threshold*med_abs[i]; hi <- ret_matrix[,i]>ti; li <- ret_matrix[,i]< -ti
    for (j in i:n) {
      if (i==j) { mat[i,j]<-1; next }
      tj <- threshold*med_abs[j]; hj <- ret_matrix[,j]>tj; lj <- ret_matrix[,j]< -tj
      co <- sum((hi&hj)|(li&lj), na.rm=TRUE); di <- sum((hi&lj)|(li&hj), na.rm=TRUE)
      tot <- co+di; val <- if (tot>0L) (co-di)/tot else 0; mat[i,j]<-val; mat[j,i]<-val
    }
  }
  diag(mat)<-1; colnames(mat)<-rownames(mat)<-colnames(ret_matrix); mat
}
rmt_denoise_cov <- function(cov_mat, T_obs, N_assets) {
  if (N_assets<2L || T_obs<N_assets) return(cov_mat)
  vol <- sqrt(pmax(diag(cov_mat),1e-16)); cor_mat <- cov_mat/(vol %o% vol)
  cor_mat <- pmin(pmax(cor_mat,-1),1); diag(cor_mat)<-1
  eig <- tryCatch(eigen(cor_mat, symmetric=TRUE), error=function(e) NULL)
  if (is.null(eig)) return(cov_mat)
  vals<-eig$values; vecs<-eig$vectors; q<-T_obs/N_assets; lp<-(1+1/sqrt(q))^2
  ni<-vals<=lp; if(any(ni)&&!all(ni)) vals[ni]<-mean(vals[ni]); vals<-pmax(vals,1e-8)
  dc <- vecs %*% diag(vals) %*% t(vecs)
  dd <- sqrt(pmax(diag(dc),1e-16)); dc<-dc/(dd %o% dd); diag(dc)<-1
  dcov <- dc*(vol %o% vol); colnames(dcov)<-rownames(dcov)<-colnames(cov_mat); dcov
}
.recursive_bisect <- function(cov_mat, sort_idx) {
  n<-length(sort_idx); nms<-colnames(cov_mat)
  if(n==1L) return(setNames(1.0, nms[sort_idx]))
  mid<-floor(n/2); left<-sort_idx[1:mid]; right<-sort_idx[(mid+1):n]
  wl<-.recursive_bisect(cov_mat,left); wr<-.recursive_bisect(cov_mat,right)
  nl<-names(wl); nr<-names(wr)
  vl<-as.numeric(t(wl)%*%cov_mat[nl,nl,drop=FALSE]%*%wl)
  vr<-as.numeric(t(wr)%*%cov_mat[nr,nr,drop=FALSE]%*%wr)
  tv<-vl+vr; a<-if(is.na(tv)||tv<1e-16) 0.5 else 1-vl/tv
  c(wl*a, wr*(1-a))
}
compute_hrp_weights <- function(ret_matrix, use_gerber=TRUE, use_rmt=TRUE) {
  nc<-ncol(ret_matrix); nr<-nrow(ret_matrix)
  ew<-setNames(rep(1/nc,nc), colnames(ret_matrix))
  if(nc<2L) return(setNames(1.0, colnames(ret_matrix)))
  cm<-cov(ret_matrix, use="pairwise.complete.obs"); if(any(is.na(cm))) return(ew)
  if(use_gerber) {
    cor_mat<-tryCatch(gerber_cor(ret_matrix,0.5),error=function(e) NULL)
    if(is.null(cor_mat)) cor_mat<-cor(ret_matrix, use="pairwise.complete.obs")
  } else cor_mat<-cor(ret_matrix, use="pairwise.complete.obs")
  if(any(is.na(cor_mat))) { cor_mat[is.na(cor_mat)]<-0; diag(cor_mat)<-1 }
  if(use_rmt && nr>nc) cm<-tryCatch(rmt_denoise_cov(cm,nr,nc),error=function(e) cm)
  cc<-pmin(pmax(cor_mat,-1),1); dm<-sqrt(0.5*(1-cc)); dm[is.na(dm)]<-1; diag(dm)<-0
  hc<-tryCatch(hclust(as.dist(dm),method="single"),error=function(e) NULL); if(is.null(hc)) return(ew)
  w<-tryCatch(.recursive_bisect(cm,hc$order),error=function(e) NULL); if(is.null(w)) return(ew)
  ws<-sum(w); if(is.na(ws)||ws<1e-10) return(ew); w/ws
}

# ═══════════════════════════════════════════════════════════════════
# 1. Load RAWDATA
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
res<-load_rawdata(use_cache=TRUE); RAWDATA<-res$RAWDATA; BM_DT<-res$BM_DT; rm(res); gc(verbose=FALSE)
RAWDATA[, Date:=as.Date(Date)]; BM_DT[, Date:=as.Date(Date)]
RAWDATA<-RAWDATA[Date>=ANALYSIS_START_DATE]; BM_DT<-BM_DT[Date>=ANALYSIS_START_DATE]
dc<-intersect(c("Open","High","Low","source","Size","Market"), names(RAWDATA))
if(length(dc)>0) RAWDATA[, (dc):=NULL]
if(!"Name"%in%names(RAWDATA)||!"Sector"%in%names(RAWDATA)) {
  ud<-as.data.table(read_parquet(file.path(CACHE_DIR,"universe.parquet"))); ud[,Date:=as.Date(Date)]
  setorder(ud,Ticker,-Date); ti<-ud[,.(Name=Name[1],Sector=Sector[1]),by=Ticker]
  if(!"Name"%in%names(RAWDATA)) RAWDATA<-merge(RAWDATA,ti[,.(Ticker,Name)],by="Ticker",all.x=TRUE)
  if(!"Sector"%in%names(RAWDATA)) RAWDATA<-merge(RAWDATA,ti[,.(Ticker,Sector)],by="Ticker",all.x=TRUE)
  rm(ud,ti)
}
gc(verbose=FALSE)
RAWDATA[, YM:=format(Date,"%Y-%m")]
sd_dt<-RAWDATA[,.(sig_date=max(Date)),by=YM]; setorder(sd_dt,sig_date)
SIG_DATES<-sd_dt[sig_date>=SIGNAL_START_DATE]$sig_date
setorder(RAWDATA,Ticker,Date)
RAWDATA[, TradVal:=Close*Vol]
RAWDATA[, LIQ_20d:=frollmean(TradVal,n=20L,align="right",na.rm=TRUE), by=Ticker]
RAWDATA[, TradVal:=NULL]
RAWDATA[, Ret_abs:=abs(Ret)]
RAWDATA[, MAX21d_raw:={ra<-Ret_abs; n<-length(ra)
  if(n<21L) cummax(fifelse(is.na(ra),-Inf,ra)) else frollapply(ra,n=21L,FUN=max,fill=NA,align="right")
}, by=Ticker]
RAWDATA[, MAX21d:=shift(MAX21d_raw,n=1L,type="lag"), by=Ticker]
RAWDATA[, c("Ret_abs","MAX21d_raw"):=NULL]
SIG_SNAP<-RAWDATA[Date%in%SIG_DATES & !is.na(Close), .(Date,Ticker,Close,LIQ_20d,MAX21d)]
setkey(SIG_SNAP,Date,Ticker); RAWDATA[,c("LIQ_20d","MAX21d","YM"):=NULL]; setkey(RAWDATA,Date,Ticker)
gc(verbose=FALSE)

# ═══════════════════════════════════════════════════════════════════
# 2. Load Consensus
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading Consensus...\n")
lc<-function(f){ dt<-as.data.table(read_parquet(file.path(CONS_DIR,f))); dt[,Date:=as.Date(Date)]
  dt<-dt[Date>=ANALYSIS_START_DATE]; setkey(dt,Ticker,Date)
  cat(sprintf("  > %s: %s rows\n",f,format(nrow(dt),big.mark=","))); dt }
SUE_DT<-lc("sue.parquet"); ESBR_DT<-lc("esbr.parquet"); EPS1M_DT<-lc("eps_chg_1m.parquet")
COV_DT<-lc("coverage.parquet"); TP_DT<-lc("target_price.parquet")

# ═══════════════════════════════════════════════════════════════════
# 3. Build C19_5F Signals
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Building C19_5F signals (SUE+ESBR+EPS1M+TP_Gap+Q07)...\n")
z_safe<-function(x){
  nv<-sum(!is.na(x)); if(nv<3L) return(rep(NA_real_,length(x)))
  mu<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE)
  if(is.na(s)||s<1e-10) return(rep(NA_real_,length(x))); (x-mu)/s
}
FACTORS_list<-vector("list", length(SIG_DATES)); fdb_errors<-0L

for(i in seq_along(SIG_DATES)){
  sd<-SIG_DATES[i]
  univ<-SIG_SNAP[Date==sd & !is.na(LIQ_20d)][LIQ_20d>=LIQ_THRESHOLD]
  if(nrow(univ)<30L) next
  mq<-quantile(univ$MAX21d,MAX21D_EXCL,na.rm=TRUE)
  univ<-univ[is.na(MAX21d)|MAX21d<=mq]; if(nrow(univ)<30L) next
  probe<-data.table(Ticker=univ$Ticker, Date=sd); setkey(probe,Ticker,Date)
  sue_j<-SUE_DT[probe,roll=7L,nomatch=NA][,.(Ticker,sue)]
  esbr_j<-ESBR_DT[probe,roll=7L,nomatch=NA][,.(Ticker,esbr)]
  eps1m_j<-EPS1M_DT[probe,roll=7L,nomatch=NA][,.(Ticker,eps_chg_1m)]
  cov_j<-COV_DT[probe,roll=7L,nomatch=NA][,.(Ticker,coverage)]
  tp_j<-TP_DT[probe,roll=7L,nomatch=NA][,.(Ticker,target_price)]

  # C15: load_month_factors() 경유, C13: Z_Score_Aligned 직접 사용
  fdb_dt<-tryCatch(load_month_factors(sd, coverage_min=0.05), error=function(e){ fdb_errors<<-fdb_errors+1L; NULL })
  if(is.null(fdb_dt)||!Q07_FACTOR%in%fdb_dt$Factor_Name) next
  q07_j<-fdb_dt[Factor_Name==Q07_FACTOR, .(Ticker, z_q07=Z_Score_Aligned)]

  sig<-Reduce(function(a,b) merge(a,b,by="Ticker",all=FALSE),
    list(univ[,.(Ticker,Close)], sue_j, esbr_j, eps1m_j, cov_j, tp_j, q07_j))
  sig<-sig[!is.na(coverage) & coverage>=3L]; if(nrow(sig)<20L) next

  sig[, TP_Gap:=(target_price-Close)/Close]
  sig[, z_sue:=z_safe(sue)]; sig[, z_esbr:=z_safe(esbr)]
  sig[, z_eps1m:=z_safe(eps_chg_1m)]; sig[, z_tpgap:=z_safe(TP_Gap)]
  # z_q07: Z_Score_Aligned (C13 준수), cross-section 재표준화
  sig[, z_q07_cs:=z_safe(z_q07)]
  sig<-sig[!is.na(z_sue)&!is.na(z_esbr)&!is.na(z_eps1m)&!is.na(z_tpgap)&!is.na(z_q07_cs)]
  if(nrow(sig)<20L) next

  sig[, C19_5F:=(z_sue+z_esbr+z_eps1m+z_tpgap+z_q07_cs)/5]
  setorder(sig,-C19_5F); top<-head(sig,N_HOLD)
  FACTORS_list[[i]]<-data.table(Date=sd, Ticker=top$Ticker, Score=top$C19_5F)
}
FACTORS<-rbindlist(FACTORS_list[!sapply(FACTORS_list,is.null)])
cat(sprintf("[Step 3] FACTORS: %d rows | %d months | FDB errors: %d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), fdb_errors))
rm(SUE_DT,ESBR_DT,EPS1M_DT,COV_DT,TP_DT,FACTORS_list,SIG_SNAP); gc(verbose=FALSE)
if(nrow(FACTORS)<50L) stop("[M22] Insufficient FACTORS. Q07 coverage may be too low.")

# ═══════════════════════════════════════════════════════════════════
# 4. HRP Weights (60d, t-1 lag)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Computing HRP weights...\n")
FACTORS_hrp<-copy(FACTORS); FACTORS_hrp[, Weight_hrp:=NA_real_]
hrp_success<-0L; hrp_fallback<-0L
for(sd in unique(FACTORS_hrp$Date)){
  tickers<-FACTORS_hrp[Date==sd, Ticker]
  ad<-sort(unique(RAWDATA[Date<sd, Date])); if(length(ad)<HRP_LOOKBACK){ FACTORS_hrp[Date==sd,Weight_hrp:=1/length(tickers)]; hrp_fallback<-hrp_fallback+1L; next }
  ld<-tail(ad,HRP_LOOKBACK); rs<-RAWDATA[Date%in%ld & Ticker%in%tickers, .(Date,Ticker,Ret)]
  rw<-dcast(rs,Date~Ticker,value.var="Ret"); rm_<-as.matrix(rw[,-1,with=FALSE]); colnames(rm_)<-names(rw)[-1]
  vc<-colSums(!is.na(rm_))>=30L
  if(sum(vc)<2L){ FACTORS_hrp[Date==sd,Weight_hrp:=1/length(tickers)]; hrp_fallback<-hrp_fallback+1L; next }
  rc<-rm_[,vc,drop=FALSE]; rc[is.na(rc)]<-0
  hw<-tryCatch(compute_hrp_weights(rc),error=function(e) NULL)
  if(is.null(hw)){ FACTORS_hrp[Date==sd,Weight_hrp:=1/length(tickers)]; hrp_fallback<-hrp_fallback+1L; next }
  wv<-rep(0,length(tickers)); names(wv)<-tickers; mt<-intersect(names(hw),tickers); wv[mt]<-hw[mt]
  um<-setdiff(tickers,mt); if(length(um)>0) wv[um]<-0.01/length(um); wv<-wv/sum(wv)
  for(tk in tickers) FACTORS_hrp[Date==sd & Ticker==tk, Weight_hrp:=wv[tk]]
  hrp_success<-hrp_success+1L
}
cat(sprintf("[Step 4] HRP: %d success, %d fallback\n", hrp_success, hrp_fallback))
hwl<-list()
for(d in unique(FACTORS_hrp$Date)){ mf<-FACTORS_hrp[Date==d]; w<-mf$Weight_hrp
  if(all(is.na(w))) w<-rep(1/nrow(mf),nrow(mf)); hwl[[as.character(d)]]<-setNames(w,mf$Ticker) }
oi<-calc_ivol_weights
calc_ivol_weights<<-function(tickers,ret_dt,n_days=60,max_w=0.15){
  for(d in names(hwl)){ hw<-hwl[[d]]; if(all(tickers%in%names(hw))){ w<-hw[tickers]; return(as.numeric(w/sum(w))) } }
  rep(1/length(tickers),length(tickers)) }
sim_base<-run_monthly_simulation(RAWDATA,BM_DT,FACTORS,n_holdings=N_HOLD,
  weight_method="ivol",commission=0.0015,buffer_zone=list(keep_n=35L,entry_n=20L))
calc_ivol_weights<<-oi
perf_base<-summarise_perf(sim_base$strategy_xts,"M22_5F_Base")
to_base<-calc_turnover(sim_base$PORTFOLIO_LOG, sim_base$DAILY_NAV_DT)

# ═══════════════════════════════════════════════════════════════════
# 5. Regime Overlay
# ═══════════════════════════════════════════════════════════════════
source(file.path(FUNC_PATH,"regime_engine_daily.R")); REGIME<-build_daily_regime(use_cache=TRUE); setkey(REGIME,Date)
ip<-file.path(CACHE_DIR,"kodex_inverse_114800.csv")
ID<-if(file.exists(ip)){ dt<-fread(ip); dt[,Date:=as.Date(Date)]; setkey(dt,Date); dt } else NULL
nd<-copy(sim_base$DAILY_NAV_DT); setkey(nd,Date)
nd<-REGIME[,.(Date,MRS,n_axes_firing)][nd,roll=TRUE]
nd<-merge(nd,BM_DT[,.(Date,BM_Ret)],by="Date",all.x=TRUE)
if(!is.null(ID)){ nd<-merge(nd,ID[,.(Date,Ret_Inv)],by="Date",all.x=TRUE); nd[is.na(Ret_Inv),Ret_Inv:=-BM_Ret] } else nd[,Ret_Inv:=-BM_Ret]
nd[is.na(Ret_Inv),Ret_Inv:=0]; nd[is.na(MRS),MRS:=0]; nd[is.na(n_axes_firing),n_axes_firing:=0L]
nd[,crisis_flag:=fifelse(MRS>=60&n_axes_firing>=5,1L,0L)]
nd[,crisis_consec:={out<-integer(.N);cnt<-0L; for(j in seq_len(.N)){if(nd$crisis_flag[j]==1L) cnt<-cnt+1L else cnt<-0L; out[j]<-cnt}; out}]
nd[,Layer:=fifelse(crisis_consec>=3L,3L,fifelse(MRS>=30,2L,1L))]
nd[,Ret_overlay:=fcase(Layer==1L,Strategy_Ret,
  Layer==2L,{fw<-pmax(0.5,1.0-(MRS-30)/60); fw*Strategy_Ret+(1-fw)*0},
  Layer==3L,0.50*Strategy_Ret+0.20*Ret_Inv+0.30*0)]
nd[,NAV_overlay:=DEFAULT_INITIAL_CAPITAL*cumprod(1+Ret_overlay)]
ov_xts<-xts(nd$Ret_overlay,order.by=nd$Date); names(ov_xts)<-"Strategy"

# ═══════════════════════════════════════════════════════════════════
# 6. Summary
# ═══════════════════════════════════════════════════════════════════
po<-summarise_perf(ov_xts,"M22_5F_Overlay"); pb<-summarise_perf(sim_base$bm_xts,"KOSPI200")
cat("\n================================================================\n")
cat("   STR_1631 v5 M22: 5F composite (+ Q07 Earnings Stability)\n")
cat("================================================================\n")
cat("--- Base ---\n"); print(perf_base); cat("--- Overlay ---\n"); print(po); cat("--- BM ---\n"); print(pb)
cat(sprintf("Turnover: %.1f%%\n", to_base))
source(file.path(FUNC_PATH,"hurdle_gate.R"))
sim_ov_h<-list(strategy_xts=ov_xts, bm_xts=sim_base$bm_xts,
  DAILY_NAV_DT=nd[,.(Date,NAV=NAV_overlay,Strategy_Ret=Ret_overlay)], PORTFOLIO_LOG=sim_base$PORTFOLIO_LOG)
hr<-run_hurdle_gate(sim_ov_h, FACTORS, strategy_name="STR_1631_v5_M22_5factor_q07", output_dir=OUT_DIR)
cat("--- Hurdle ---\n"); print(hr[c("pass","score")])
generate_charts(list(strategy_xts=ov_xts,bm_xts=sim_base$bm_xts,
  DAILY_NAV_DT=nd[,.(Date,NAV=NAV_overlay,Strategy_Ret=Ret_overlay)]),
  output_dir=OUT_DIR, strategy_name="STR_1631 v5 M22 - 5F Q07")
write_json(list(strategy="STR_1631_v5_M22_5factor_q07",
  mutation="M_A2: 4F->5F, add Q07_Earnings_Stability via load_month_factors()",
  pit_notes=list(C13="Z_Score_Aligned",C15="load_month_factors()"),
  fdb_errors=fdb_errors, base=as.list(perf_base), overlay=as.list(po), benchmark=as.list(pb),
  turnover=to_base, hurdle_pass=hr$pass, hurdle_score=hr$score, run_time=as.numeric(difftime(Sys.time(),t0,units="secs"))
), file.path(OUT_DIR,"performance.json"), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n[DONE] M22 complete in %.1f sec\n", difftime(Sys.time(),t0,units="secs")))
