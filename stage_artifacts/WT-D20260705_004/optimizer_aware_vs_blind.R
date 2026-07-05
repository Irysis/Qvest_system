# optimizer_aware_vs_blind.R — WT-D20260705_004 Optimizer Research (v2, validated pipeline)
# DECISIVE TEST: does uncertainty-AWARE robust portfolio optimization beat
#                uncertainty-BLIND optimization on realized PORT_t?
#
# VALIDITY ANCHOR: EW-of-top25 reproduces alpha baseline A exactly (full 0.9698 / recent -0.7248).
#
# Clean paired A/B (isolates SIZING; name set identical to baseline):
#   NAME SET each month t = top-25 by mu_hat (== baseline A names, all 196 months present).
#   All methods re-weight THOSE SAME 25 names.
#     BLIND (ignore sigma_hat): EW(=baseline A), MVO, HRP, ERC, MINVAR.
#     AWARE (consume per-name sigma_hat): ROBUST_BOX, EST_PENALTY, BL_SHRINK, RESAMPLED.
#   Sigma_25 = trailing-window (<=120m, PIT months<t) Ledoit-Wolf constant-corr shrink of F1.
#   HARD: 25 names, long-only, [0,0.20], sum w=1, liquidity in-panel, 15bps v2.4 delta.
#   Perf: contract-grade weighted_screen_bt (NW lag-3). metric_type="weighted_screen" (estimated).
#
# SECONDARY (selection+sizing): pool top-40 by mu_hat, optimizer picks/sizes 25 (reported separately).

suppressMessages({
  library(arrow); library(data.table); library(jsonlite); library(quadprog)
})
setDTthreads(1); set.seed(20260705L)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA   <- file.path(ROOT,"stage_artifacts","WT-D20260705_004")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))

MAX_W <- 0.20; N_SELECT <- 25L; COST_BPS <- 15
COV_MIN_MONTHS <- 24L; COV_WINDOW <- 120L; LW_DELTA <- 0.3
LAMBDA <- 5.0

# ---- load panel + forward benchmark (validated alignment) ----
pan <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))
yms <- sort(unique(pan$ym))
bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, ym := format(as.Date(Date),"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_lr <- bm[, .(lr=sum(log1p(BM_Ret))), by=ym][order(ym)]
bm_lr[, bm_fwd := expm1(shift(lr, type="lead", n=1L))]
ym2date <- function(y) as.Date(paste0(y,"-01"))
benchdt <- bm_lr[!is.na(bm_fwd), .(Date=ym2date(ym), BM_Ret=bm_fwd)]
rets <- pan[, .(Date=ym2date(ym), Ticker, Ret_1m=F1)]

# ---- QP + weight helpers ----
qp_mvo <- function(m, Q, lam, ub=MAX_W) {
  p <- length(m); Q <- (Q+t(Q))/2
  emin <- min(eigen(Q, symmetric=TRUE, only.values=TRUE)$values)
  if (emin <= 1e-10) Q <- Q + (1e-8 - min(emin,0))*diag(p)
  sol <- tryCatch(solve.QP(lam*Q, as.numeric(m),
                           cbind(rep(1,p), diag(p), -diag(p)),
                           c(1, rep(0,p), rep(-ub,p)), meq=1), error=function(e) NULL)
  if (is.null(sol)) return(NULL)
  w <- pmin(pmax(sol$solution,0), ub); if (sum(w)<1e-10) return(NULL); w/sum(w)
}
qp_minvar <- function(Q, ub=MAX_W) qp_mvo(rep(0,ncol(Q)), Q, 1, ub)
cap_redistribute <- function(w, ub) {
  for (it in 1:1000){ over <- w>ub+1e-12; if(!any(over)) break
    ex<-sum(w[over]-ub); w[over]<-ub; un<-!over&w>0
    if(!any(un)){w<-w/sum(w);break}; w[un]<-w[un]+ex*w[un]/sum(w[un]) }
  w/sum(w)
}
hrp_weights <- function(Q){
  p<-ncol(Q); if(p<2) return(rep(1/p,p))
  sd<-sqrt(pmax(diag(Q),1e-12)); corr<-Q/(sd%o%sd); corr[!is.finite(corr)]<-0; diag(corr)<-1
  d<-sqrt(pmax(0.5*(1-corr),0)); hc<-tryCatch(hclust(as.dist(d),"single"),error=function(e)NULL)
  if(is.null(hc)) return(rep(1/p,p)); oi<-hc$order
  gIVP<-function(c){iv<-1/pmax(diag(c),1e-12);iv/sum(iv)}
  gCV<-function(c,it){cc<-c[it,it,drop=FALSE];w<-gIVP(cc);as.numeric(t(w)%*%cc%*%w)}
  w<-rep(1,p); ci<-list(oi)
  while(length(ci)>0){
    ci<-unlist(lapply(ci,function(i){if(length(i)>1){h<-floor(length(i)/2);list(i[1:h],i[(h+1):length(i)])}else NULL}),recursive=FALSE)
    if(is.null(ci)) break
    for(k in seq(1,length(ci),by=2)){ if(k+1>length(ci)) break
      c0<-ci[[k]];c1<-ci[[k+1]];v0<-gCV(Q,c0);v1<-gCV(Q,c1);a<-1-v0/(v0+v1)
      w[c0]<-w[c0]*a; w[c1]<-w[c1]*(1-a) } }
  cap_redistribute(w/sum(w), MAX_W)
}
erc_weights <- function(Q){
  p<-ncol(Q); if(p<2) return(rep(1/p,p))
  w<-1/sqrt(pmax(diag(Q),1e-12)); w<-w/sum(w)
  for(it in 1:300){ Sw<-as.numeric(Q%*%w); rc<-w*Sw; tg<-mean(rc)
    wn<-w*(tg/pmax(rc,1e-12))^0.5; wn<-pmax(wn,0); wn<-wn/sum(wn)
    if(max(abs(wn-w))<1e-9){w<-wn;break}; w<-wn }
  cap_redistribute(w, MAX_W)
}
# AWARE (consume sigma_hat)
qp_robust_box <- function(m,sig,Q,lam,kappa,ub=MAX_W) qp_mvo(m-kappa*sig, Q, lam, ub)
qp_est_penalty<- function(m,sig,Q,lam,gamma,ub=MAX_W) qp_mvo(m, Q+(gamma/lam)*diag(sig^2), lam, ub)
qp_bl_shrink  <- function(m,sig,Q,lam,ub=MAX_W){
  sn<-(sig-min(sig))/(max(sig)-min(sig)+1e-12); mb<-mean(m)
  qp_mvo((1-sn)*m+sn*mb, Q, lam, ub)
}
qp_resampled  <- function(m,sig,Q,lam,ub=MAX_W,B=40L){
  p<-length(m); acc<-rep(0,p); nok<-0
  for(b in 1:B){ wb<-qp_mvo(m+rnorm(p,0,sig),Q,lam,ub); if(!is.null(wb)){acc<-acc+wb;nok<-nok+1} }
  if(nok==0) return(NULL); (acc/nok)/sum(acc/nok)
}

# trailing LW covariance for a fixed ticker set at month ym_t (PIT months<t)
trailing_cov <- function(tks, ym_t){
  hist <- yms[yms<ym_t]; if(length(hist)>COV_WINDOW) hist<-tail(hist,COV_WINDOW)
  if(length(hist)<COV_MIN_MONTHS) return(NULL)
  hp <- pan[ym %in% hist & Ticker %in% tks, .(ym,Ticker,F1)]
  if(nrow(hp)==0) return(NULL)
  hw <- dcast(hp, ym~Ticker, value.var="F1")
  mat<- as.matrix(hw[,-1,with=FALSE])
  ok <- colSums(!is.na(mat))>=COV_MIN_MONTHS
  if(sum(ok)<2) return(NULL)
  matk<-mat[,ok,drop=FALSE]; S<-cov(matk,use="pairwise.complete.obs"); S[!is.finite(S)]<-0
  sd_<-sqrt(pmax(diag(S),1e-10)); cc<-S/(sd_%o%sd_); cc[!is.finite(cc)]<-0; diag(cc)<-1
  rbar<-mean(cc[upper.tri(cc)],na.rm=TRUE); Ftar<-rbar*(sd_%o%sd_); diag(Ftar)<-diag(S)
  Sshr<-(1-LW_DELTA)*S+LW_DELTA*Ftar
  emin<-min(eigen((Sshr+t(Sshr))/2,symmetric=TRUE,only.values=TRUE)$values)
  if(emin<=1e-8) Sshr<-Sshr+(1e-6-min(emin,0))*diag(ncol(Sshr))
  dimnames(Sshr)<-list(colnames(matk),colnames(matk))
  Sshr
}

methods_blind <- c("EW","MVO","HRP","ERC","MINVAR")
methods_aware <- c("ROBUST_BOX","EST_PENALTY","BL_SHRINK","RESAMPLED")
all_methods   <- c(methods_blind, methods_aware)

run_design <- function(pool_k, label){
  wl <- setNames(lapply(all_methods, function(x) vector("list", length(yms))), all_methods)
  pan_by <- split(pan[order(ym,-mu_hat)], by="ym")
  for(ti in seq_along(yms)){
    ym_t<-yms[ti]; cur<-pan_by[[ym_t]]
    if(is.null(cur)||nrow(cur)<N_SELECT) next
    pool <- head(cur, pool_k)
    Q <- trailing_cov(pool$Ticker, ym_t)
    dte<-ym2date(ym_t)
    put<-function(mm,w,tkv){ if(is.null(w)||any(!is.finite(w)))return(invisible())
      if(length(w)>N_SELECT){ ord<-order(w,decreasing=TRUE)[1:N_SELECT]; w<-w[ord]; tkv<-tkv[ord]; w<-cap_redistribute(w/sum(w),MAX_W)}
      wl[[mm]][[ti]]<<-data.table(Date=dte,Ticker=tkv,w=w/sum(w)) }
    if(pool_k==N_SELECT){
      # fixed name set = top25; EW must == baseline A
      tks<-pool$Ticker; m<-pool$mu_hat; sig<-pool$sigma_hat; p<-length(tks)
      put("EW", rep(1/p,p), tks)
      if(!is.null(Q)){
        cm<-match(colnames(Q),tks); mQ<-m[cm]; sigQ<-sig[cm]; tkQ<-tks[cm]
        # for names lacking cov, MVO/etc only over covered set then EW-fill? keep full-25 for EW,
        # risk methods only defined on covered set -> use covered set (report unique_dates)
        put("MVO", qp_mvo(mQ,Q,LAMBDA), tkQ)
        put("HRP", hrp_weights(Q), tkQ)
        put("ERC", erc_weights(Q), tkQ)
        put("MINVAR", qp_minvar(Q), tkQ)
        put("ROBUST_BOX", qp_robust_box(mQ,sigQ,Q,LAMBDA,1.0), tkQ)
        put("EST_PENALTY",qp_est_penalty(mQ,sigQ,Q,LAMBDA,LAMBDA), tkQ)
        put("BL_SHRINK",  qp_bl_shrink(mQ,sigQ,Q,LAMBDA), tkQ)
        put("RESAMPLED",  qp_resampled(mQ,sigQ,Q,LAMBDA), tkQ)
      }
    } else {
      # selection+sizing: need Q; skip months without cov
      if(is.null(Q)) next
      cm<-match(colnames(Q), pool$Ticker); mQ<-pool$mu_hat[cm]; sigQ<-pool$sigma_hat[cm]; tkQ<-pool$Ticker[cm]
      if(length(tkQ)<N_SELECT) next
      # EW here = top-25 by mu within covered pool
      ord<-order(mQ,decreasing=TRUE)[1:N_SELECT]
      put("EW", rep(1/N_SELECT,N_SELECT), tkQ[ord])
      put("MVO", qp_mvo(mQ,Q,LAMBDA), tkQ)
      put("HRP", hrp_weights(Q), tkQ)
      put("ERC", erc_weights(Q), tkQ)
      put("MINVAR", qp_minvar(Q), tkQ)
      put("ROBUST_BOX", qp_robust_box(mQ,sigQ,Q,LAMBDA,1.0), tkQ)
      put("EST_PENALTY",qp_est_penalty(mQ,sigQ,Q,LAMBDA,LAMBDA), tkQ)
      put("BL_SHRINK",  qp_bl_shrink(mQ,sigQ,Q,LAMBDA), tkQ)
      put("RESAMPLED",  qp_resampled(mQ,sigQ,Q,LAMBDA), tkQ)
    }
  }
  RECENT_LO<-as.Date("2017-01-01")
  ev<-function(mm){ wd<-rbindlist(wl[[mm]]); if(nrow(wd)==0)return(NULL)
    f<-weighted_screen_bt(wd,rets,benchdt,cost_bps_oneway=COST_BPS,run_id=paste0(label,mm),strategy_id=paste0(label,mm))
    r<-weighted_screen_bt(wd[Date>=RECENT_LO],rets,benchdt,cost_bps_oneway=COST_BPS,run_id=paste0(label,mm,"r"),strategy_id=paste0(label,mm,"r"))
    data.table(method=mm, full_port_t=f$portfolio_alpha_t_nw_lag3, full_IR=f$information_ratio,
               full_net_sr=f$net_sr, full_turnover=f$turnover_annual, full_n=f$n_months,
               recent_port_t=r$portfolio_alpha_t_nw_lag3, recent_n=r$n_months,
               unique_dates=length(unique(wd$Date))) }
  res<-rbindlist(lapply(all_methods,ev),fill=TRUE)
  res[, group:=ifelse(method%in%methods_blind,"BLIND","AWARE")]
  res[, design:=label]
  list(res=res, wl=wl)
}

cat("========== DESIGN 1: fixed name set = top-25 (SIZING isolation) ==========\n")
d1 <- run_design(N_SELECT, "d1_")
setorder(d1$res, -full_port_t)
print(d1$res[, .(method,group,full_port_t=round(full_port_t,4),full_net_sr=round(full_net_sr,4),
                 full_turnover=round(full_turnover,2),recent_port_t=round(recent_port_t,4),full_n,unique_dates)])

cat("\n========== DESIGN 2: pool top-40 (SELECTION + SIZING) ==========\n")
d2 <- run_design(40L, "d2_")
setorder(d2$res, -full_port_t)
print(d2$res[, .(method,group,full_port_t=round(full_port_t,4),full_net_sr=round(full_net_sr,4),
                 full_turnover=round(full_turnover,2),recent_port_t=round(recent_port_t,4),full_n,unique_dates)])

summ <- function(res, tag){
  bb<-res[group=="BLIND"][which.max(full_port_t)]; ab<-res[group=="AWARE"][which.max(full_port_t)]
  df<-ab$full_port_t-bb$full_port_t; dr<-ab$recent_port_t-bb$recent_port_t
  cat(sprintf("\n[%s] BLIND best=%s(%.4f)  AWARE best=%s(%.4f)  dPORT_t full=%.4f recent=%.4f => %s\n",
      tag, bb$method,bb$full_port_t, ab$method,ab$full_port_t, df,dr,
      ifelse(df>0,"AWARE wins","AWARE does NOT win")))
  list(blind_best=as.list(bb), aware_best=as.list(ab), delta_full=df, delta_recent=dr)
}
s1<-summ(d1$res,"D1 sizing"); s2<-summ(d2$res,"D2 select+size")

allres<-rbind(d1$res,d2$res)
fwrite(allres, file.path(SA,"aware_vs_blind_results.csv"))
saveRDS(list(d1=d1$wl,d2=d2$wl), file.path(SA,"weights_lists.rds"))
write_json(list(design1_sizing=s1, design2_select_size=s2, lambda=LAMBDA,
                cov_window=COV_WINDOW, lw_delta=LW_DELTA, n_select=N_SELECT, cost_bps=COST_BPS,
                baseline_A_full=0.9698, baseline_A_recent=-0.7248),
           file.path(SA,"aware_vs_blind_summary.json"), auto_unbox=TRUE, na="null")
cat("\n[saved] aware_vs_blind_results.csv + summary.json + weights_lists.rds\n")
