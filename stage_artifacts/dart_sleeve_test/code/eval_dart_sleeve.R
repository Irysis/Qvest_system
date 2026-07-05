#!/usr/bin/env Rscript
# eval_dart_sleeve.R — DART insider sleeve book-marginal harness (isolated).
# ============================================================================
# Reuse of stage_artifacts/beat_pg2_lag1_scan_20260705/eval_lag1.R logic:
#   - BASE = STR_1715 score_eff + PG2 overlay (m4*beta_R05), canonical LinTilt top-20 recon.
#   - blend(sleeve, w): merge sleeve z into BASE z by ym+Ticker, forward-shift LAG (PIT-safe).
#   - metrics: book_ir, dIR vs PG2 (1.4238 baseline), paired NW t, book_port_t, oos_v2, calmar, mdd.
# Adaptation:
#   - sleeves read from stage_artifacts/dart_sleeve_test/data/cache_<CODE>.parquet
#   - WINDOW restriction: DART coverage months only, PG2 restricted to SAME months (apples-to-apples).
#   - LAG default 1: sleeve sig_month=m -> decision month m+1 (== panel usable_month; single PIT lag).
# NO self-synthesis: portfolio return via recon() GRID forward windows (Return.portfolio-equivalent),
#   identical to the PIT-verified base harness. oos_v2 = anchored 3-split {55/65/75} median (§3 C1).
# ============================================================================
suppressMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) })
setDTthreads(1); arrow::set_io_thread_count(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SC     <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
SLDIR  <- "stage_artifacts/dart_sleeve_test/data"
OUTDIR <- "stage_artifacts/dart_sleeve_test/reports"
dir.create(OUTDIR, showWarnings=FALSE, recursive=TRUE)
LAG <- as.integer(Sys.getenv("LAG", "1"))
TAG <- Sys.getenv("RUNTAG", paste0("dart_lag",LAG))
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
LOG <- file(file.path(OUTDIR, paste0("eval_",TAG,".log")), open="wt")
lg  <- function(...){ cat(...,file=LOG); flush(LOG); cat(...) }

GRID <- readRDS(file.path(SC,"grid.rds"))
OV  <- fread("05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv")
OV[, ov_mult := m4*beta_R05]; OVm <- OV[,.(ym=return_ym, ov_mult)]
BASE <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); BASE[,ym:=format(Date,"%Y-%m")]
BASE_YMS <- sort(unique(BASE$ym))
YM_NEXT  <- setNames(c(BASE_YMS[-1], NA_character_), BASE_YMS)
bl <- readRDS("stage_artifacts/beat_pg2_ortho_sleeve_20260705/pg2_baseline.rds"); PG2_IR_FULL <- bl$book_ir
pg2_m <- as.data.table(bl$monthly)[,.(ym, pg2_active=active, pg2_net=ret_net, bm=bm_ret)]

ir_active <- function(rn,bm){ a<-rn-bm; mean(a)/sd(a)*sqrt(12) }
sr_a      <- function(r) mean(r)/sd(r)*sqrt(12)
recon <- function(A){ A<-as.data.table(A); setkey(A,Date); w_prev<-NULL; out<-vector("list",length(GRID))
  for(i in seq_along(GRID)){ g<-GRID[[i]]; p<-A[.(g$sig)][!is.na(score)]; if(nrow(p)==0) next
    reg<-p$regime_state[1]; setorder(p,-score); Ne<-nrow(p); Nt<-min(20L,Ne); if(Nt<15L&&Ne>=15L)Nt<-15L; if(Nt<5L) next
    pk<-p[seq_len(Nt)]; al<-setNames(pk$score,pk$Ticker); tk<-intersect(names(al),g$liq_tickers); if(length(tk)<5L)tk<-names(al); al<-al[tk]; if(length(al)<5L) next
    ub<-if(identical(reg,"CRISIS"))0.10 else 0.20
    wr<-tryCatch(linear_tilt_to_penalty_qd(al,lambda=1.5,w_prev=w_prev,phi=3.0,lb=0,ub=ub),error=function(e)linear_tilt_qd(al,lambda=1.5,lb=0,ub=ub)); names(wr)<-names(al)
    w<-normalize_long_only(wr,lb=0,ub=ub,target_sum=1); fr<-g$fwd[match(names(w),Ticker),ret_fwd]; fr[is.na(fr)]<-0
    out[[i]]<-data.table(ym=g$ym, gross=sum(as.numeric(w)*fr), bm=g$bm); w_prev<-setNames(as.numeric(w),names(w)) }
  M<-rbindlist(out,use.names=TRUE); M<-merge(M,OVm,by="ym",all.x=TRUE); M[is.na(ov_mult),ov_mult:=1]
  M[,ret_net:=gross*ov_mult]; M[,active:=ret_net-bm]; M[order(ym)] }
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s==0) rep(0,length(x)) else (x-m)/s }
blend <- function(sl, bws, lag=LAG){ B<-copy(BASE)[,.(Date,Ticker,ym,bscore=score_eff,regime_state)]; B[,bz:=zc(bscore),by=Date]
  S<-as.data.table(sl)[,.(Ticker, sscore=score, ym=format(Date,"%Y-%m"))]
  if(lag>=1L){ for(k in seq_len(lag)) S[, ym := YM_NEXT[ym]]; S<-S[!is.na(ym)] }
  J<-merge(B,S,by=c("ym","Ticker"),all.x=TRUE)
  J[,sz:=zc(sscore),by=Date]; J[is.na(sz),sz:=0]; J[,score:=(1-bws)*bz+bws*sz]; J[,.(Date,Ticker,score,regime_state)] }
pnw <- function(d){ d<-d[is.finite(d)]; if(length(d)<12) return(NA_real_); f<-lm(d~1); coef(f)[1]/sqrt(NeweyWest(f,lag=3,prewhite=FALSE)[1,1]) }
oos_v2 <- function(a){ n<-length(a); if(n<40) return(NA_real_); s<-function(x) if(length(x)<6||sd(x)==0) NA_real_ else mean(x)/sd(x)*sqrt(12)
  rr<-sapply(c(0.55,0.65,0.75),function(f){k<-floor(n*f); i<-s(a[1:k]); o<-s(a[(k+1):n]); if(is.na(i)||is.na(o)||i<=0) NA_real_ else o/i}); median(rr,na.rm=TRUE) }
mdd  <- function(r){ nav<-cumprod(1+r); -min(nav/cummax(nav)-1) }
calm <- function(r){ n<-length(r); c<-prod(1+r)^(12/n)-1; m<-mdd(r); if(m<=0) NA_real_ else c/m }

# sleeve coverage window: months where sleeve has ANY nonzero signal (after lag)
sleeve_window <- function(sl){
  S<-as.data.table(sl)[score!=0]; S[,ym:=format(Date,"%Y-%m")]
  if(nrow(S)==0) return(character(0))
  ym0<-sort(unique(S$ym))
  if(LAG>=1L){ ym0<-unname(YM_NEXT[ym0]); ym0<-ym0[!is.na(ym0)] }  # shift to decision months
  ym0
}

args <- commandArgs(trailingOnly=TRUE)
RES <- list()
for(cn in args){
  cf<-file.path(SLDIR,paste0("cache_",cn,".parquet")); if(!file.exists(cf)){ lg(sprintf("[%s] no cache\n",cn)); next }
  sl<-as.data.table(read_parquet(cf))
  win <- sleeve_window(sl)
  if(length(win)<24){ lg(sprintf("[%s] window too short (%d decision-months w/ signal) — SKIP eval, coverage insufficient\n",cn,length(win))); next }
  # standalone sleeve-only book (w=1) active-cor vs PG2 (informational)
  Ms<-recon(blend(sl,1.0)); Ms<-Ms[ym %in% win]
  Js<-merge(Ms[,.(ym,sa=active)],pg2_m[,.(ym,pg2_active)],by="ym"); acor<-if(nrow(Js)>3) cor(Js$sa,Js$pg2_active) else NA_real_
  sir<-if(nrow(Ms)>3) ir_active(Ms$ret_net,Ms$bm) else NA_real_
  for(bw in c(0.90,0.80,0.70)){   # sleeve weight small (insider = sparse tilt); base weight bw
    M<-recon(blend(sl,1-bw)); M<-M[ym %in% win]
    J<-merge(M[,.(ym,book_net=ret_net,book_active=active)],pg2_m,by="ym")
    if(nrow(J)<24){ next }
    # window-restricted PG2 IR for apples-to-apples dIR
    pg2_ir_win <- ir_active(J$pg2_net, J$bm)
    bir<-ir_active(M$ret_net,M$bm); dIR_win<-bir-pg2_ir_win
    tt<-pnw(J$book_active-J$pg2_active); oo<-oos_v2(J$book_active)
    f0<-lm(J$book_active~1); pt<-coef(f0)[1]/sqrt(NeweyWest(f0,lag=3,prewhite=FALSE)[1,1])
    RES[[paste0(cn,"_",bw)]]<-data.table(lag=LAG, code=cn, base_w=bw, sleeve_w=round(1-bw,2),
      book_ir=round(bir,4), pg2_ir_win=round(pg2_ir_win,4), dIR_win=round(dIR_win,4),
      paired_nw_t=round(as.numeric(tt),3), book_port_t=round(as.numeric(pt),3),
      standalone_sleeve_ir=round(sir,3), standalone_active_cor_pg2=round(acor,3),
      book_net_sr=round(sr_a(M$ret_net),3), mdd=round(mdd(M$ret_net),4),
      calmar=round(as.numeric(calm(M$ret_net)),3), oos_v2=round(as.numeric(oo),3), n_months=nrow(J))
    outf0<-file.path(OUTDIR,paste0("results_",TAG,".csv")); fwrite(RES[[paste0(cn,"_",bw)]],outf0,append=file.exists(outf0))
    lg(sprintf("[%s] bw=%.2f n=%d IR=%.4f (PG2win=%.4f) dIR=%+.4f pNWt=%+.2f portT=%+.2f oos=%.2f calmar=%.2f mdd=%.3f | sIR=%.2f acor=%.2f\n",
        cn,bw,nrow(J),bir,pg2_ir_win,dIR_win,as.numeric(tt),as.numeric(pt),as.numeric(oo),as.numeric(calm(M$ret_net)),mdd(M$ret_net),sir,acor))
  }
}
lg(sprintf("[DONE] %d codes, LAG=%d, PG2_full_IR=%.4f\n",length(args),LAG,PG2_IR_FULL)); close(LOG)
