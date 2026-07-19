# =============================================================================
# FQ-063 run_01: walk-forward weight 생성 — Mode A(비중 방법 스윕) + Mode B(대형-유니버스
#   위험선택+비중, Σ 3-A/B). 알파 base = production STR_1715 score_eff(§7b parity).
#   모든 비중은 .get_cor_cov 3종(sample/ledoit_wolf/lw_nls) Σ 통제 하 self-contained.
#   Hard Constraints: max25 / long-only / [0,0.20] / Σw=1 / LIQ 2e8 t-1. Return.portfolio는 measure에서.
# Output: fq063_weights.parquet + fq063_holdings.parquet + fq063_cell_registry.json + meta
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(quadprog); library(lpSolve)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))               # .get_cor_cov, .hrp_bisect, .cluster_var
source(file.path(ROOT, "02_Infrastructure/portfolio/mean_variance_optimizer.R")) # mvo_weights
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
PIN_TAG <- "fq057_20260718_171024"
stopifnot(exists(".get_cor_cov"), exists("mvo_weights"), exists(".hrp_bisect"))

# ---- 파라미터 (사전등록 고정) ------------------------------------------------
BOUNDS <- c(0, 0.20); UB <- BOUNDS[2]; MAX_NAMES <- 25L; MIN_NAMES <- 15L
LAMBDA_TILT <- 1.5; LAMBDA_MVO <- 2.0; PSI <- 0.3; HHI_CAP <- 0.10; ALPHA_WINSOR <- 2.0
LIQ_MIN <- 2e8; WIN <- 60L; CVAR_BETA <- 0.95
REB_FROM <- 200912L; REB_TO <- 202604L   # score 패널 max 202604 -> 공통 reb 상한
N_PROD_BOOK <- 20L                        # incumbent 참조(top-20 LinearTilt)

# ---- production .tilt/.norm (forward_weights_R05_noLayer4.R verbatim port) ----
.norm <- function(w, lb=0, ub=UB, ts=1, mi=50){
  w[is.na(w)]<-0; w[w<lb]<-lb; w[w>ub]<-ub
  for(i in seq_len(mi)){ s<-sum(w); if(abs(s-ts)<1e-8) break; if(s==0) break
    w<-w*(ts/s); w[w>ub]<-ub; w[w<lb]<-lb }
  w }
.tilt <- function(a, lam=LAMBDA_TILT, lb=0, ub=UB){
  if(!length(a)) return(numeric(0))
  z <- (a-mean(a))/pmax(sd(a),1e-10)
  w <- pmax(0, 1/length(a) + lam*z/length(a))
  if(sum(w)>0) w <- w/sum(w)
  .norm(w, lb, ub) }

# ---- box cap-renorm ----------------------------------------------------------
cap_renorm <- function(w, cap=UB, iter=100){
  w[!is.finite(w)]<-0; w[w<0]<-0; s<-sum(w); if(s<=0) return(w); w<-w/s
  for(i in seq_len(iter)){ over<-w>cap+1e-12; if(!any(over)) break
    excess<-sum(w[over]-cap); w[over]<-cap; under<-(!over)&(w>0)
    if(!any(under)) break; w[under]<-w[under]+excess*w[under]/sum(w[under]) }
  s<-sum(w); if(s>0) w/s else w }

# ---- PD 보정 (solve.QP 요구) -------------------------------------------------
make_pd <- function(S, tol=1e-10){
  S<-(S+t(S))/2
  mn<-min(eigen(S, symmetric=TRUE, only.values=TRUE)$values)
  ridge<-0
  if(mn < tol){ ridge<-(tol-mn)+1e-12; S<-S+diag(ridge, ncol(S)) }
  list(S=S, ridge=ridge, min_ev=mn) }

# ---- 비중 방법 (모두 Σ 또는 scenarios 입력, long-only box Σw=1) --------------
w_ew <- function(nm){ setNames(rep(1/length(nm), length(nm)), nm) }

w_gmv <- function(S, ub=UB){                      # min w'Σw
  p<-ncol(S); pd<-make_pd(S); Dmat<-2*pd$S; dvec<-rep(0,p)
  Amat<-cbind(rep(1,p), diag(p), -diag(p)); bvec<-c(1, rep(0,p), rep(-ub,p))
  sol<-tryCatch(solve.QP(Dmat,dvec,Amat,bvec,meq=1L), error=function(e) NULL)
  if(is.null(sol)) return(NULL)
  w<-sol$solution; w[w<0]<-0; s<-sum(w); if(s<=0) return(NULL)
  w<-setNames(w/s, colnames(S)); attr(w,"ridge")<-pd$ridge; w }

w_maxdiv <- function(S, ub=UB){                   # max diversification ratio
  p<-ncol(S); sig<-sqrt(diag(S)); pd<-make_pd(S); Dmat<-2*pd$S; dvec<-rep(0,p)
  Amat<-cbind(sig, diag(p)); bvec<-c(1, rep(0,p))
  sol<-tryCatch(solve.QP(Dmat,dvec,Amat,bvec,meq=1L), error=function(e) NULL)
  if(is.null(sol)) return(NULL)
  w<-sol$solution; w[w<0]<-0; s<-sum(w); if(s<=0) return(NULL)
  w<-setNames(w/s, colnames(S)); cap_renorm(w, ub) }

w_erc <- function(S, ub=UB, iter=2000, tol=1e-9){ # equal risk contribution
  p<-ncol(S); dg<-diag(S); dg[dg<=0]<-min(dg[dg>0], na.rm=TRUE)
  w<-1/sqrt(dg); w<-w/sum(w)
  for(k in seq_len(iter)){
    mrc<-as.numeric(S%*%w); rc<-w*mrc; tgt<-mean(rc)
    wn<-w*(tgt/pmax(rc,1e-16))^0.5; wn<-wn/sum(wn)
    if(max(abs(wn-w))<tol){ w<-wn; break }; w<-wn }
  w<-setNames(w, colnames(S)); cap_renorm(w, ub) }

w_hrp_cov <- function(S, ub=UB){                  # HRP from cov
  sds<-sqrt(diag(S)); cor_mat<-S/outer(sds,sds); diag(cor_mat)<-1; cor_mat[!is.finite(cor_mat)]<-0
  d<-0.5*(1-cor_mat); d[d<0]<-0
  hc<-tryCatch(hclust(as.dist(sqrt(d)), method="ward.D2"), error=function(e) NULL)
  if(is.null(hc)) return(NULL)
  w<-tryCatch(.hrp_bisect(S, hc$order), error=function(e) NULL); if(is.null(w)) return(NULL)
  w<-setNames(w/sum(w), colnames(S)); cap_renorm(w, ub) }

w_mvo <- function(alpha, S){
  res<-tryCatch(mvo_weights(alpha=alpha, cov_matrix=S, confidence=NULL,
      lambda=LAMBDA_MVO, psi=PSI, bounds=BOUNDS, max_names=MAX_NAMES, min_names=MIN_NAMES,
      hhi_cap=HHI_CAP, alpha_winsor=ALPHA_WINSOR, turnover_penalty=0.0, active=FALSE),
      error=function(e) NULL)
  if(is.null(res)||is.null(res$weights)) return(NULL)
  w<-res$weights; setNames(as.numeric(w), names(w)) }

w_cvar_lp <- function(retmat, ub=UB, beta=CVAR_BETA){  # Rockafellar-Uryasev min-CVaR (lpSolve)
  p<-ncol(retmat); S<-nrow(retmat); nm<-colnames(retmat)
  nv<-p+2L+S                                    # [w(p), zp, zn, u(S)]
  K<-1/((1-beta)*S)
  obj<-c(rep(0,p), 1, -1, rep(K, S))
  cons<-list(); dir<-c(); rhs<-c()
  cons[[1]]<-c(rep(1,p),0,0,rep(0,S)); dir<-c(dir,"="); rhs<-c(rhs,1)           # Σw=1
  for(j in 1:p){ r<-rep(0,nv); r[j]<-1; cons[[length(cons)+1]]<-r; dir<-c(dir,"<="); rhs<-c(rhs,ub) }  # w_j<=ub
  for(s in 1:S){ r<-rep(0,nv); r[1:p]<-retmat[s,]; r[p+1]<-1; r[p+2]<--1; r[p+2+s]<-1
    cons[[length(cons)+1]]<-r; dir<-c(dir,">="); rhs<-c(rhs,0) }                # u_s+w'r_s+zeta>=0
  Amat<-do.call(rbind, cons)
  sol<-tryCatch(lp("min", obj, Amat, dir, rhs), error=function(e) NULL)
  if(is.null(sol)||sol$status!=0) return(NULL)
  w<-sol$solution[1:p]; w[w<0]<-0; s<-sum(w); if(s<=0) return(NULL)
  w<-setNames(w/s, nm); cap_renorm(w, ub) }

# 대형-유니버스 위험선택 -> top-25 -> 재해/재정규화(카디널리티)
risk_select25 <- function(method, S_full, retmat_full){
  wf <- switch(method,
    GMV    = w_gmv(S_full),
    MaxDiv = w_maxdiv(S_full),
    HRP    = w_hrp_cov(S_full))
  if(is.null(wf)) return(NULL)
  sel <- names(sort(wf[wf>1e-9], decreasing=TRUE))
  sel <- sel[seq_len(min(MAX_NAMES, length(sel)))]
  if(length(sel) < 5L) return(NULL)
  S25 <- S_full[sel, sel, drop=FALSE]
  w25 <- switch(method,
    GMV    = w_gmv(S25),
    MaxDiv = w_maxdiv(S25),
    HRP    = { setNames(cap_renorm(wf[sel], UB), sel) })
  if(is.null(w25)) return(NULL)
  w25 }

# ---- 입력 로드 (pinned 재사용) ----------------------------------------------
mr   <- as.data.table(read_parquet(file.path(OUT_DIR,"fq057_monthly_returns.parquet")))
snap <- as.data.table(read_parquet(file.path(OUT_DIR,"fq057_monthly_snapshot.parquet")))
liq  <- as.data.table(read_parquet(file.path(OUT_DIR,"np4_liq_snapshot.parquet")))
CP <- file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet")
sc <- as.data.table(read_parquet(CP, col_select=c("Date","Ticker","score_eff")))
sc[, Date:=as.Date(Date)]; sc[, ym:=as.integer(format(Date,"%Y"))*100L+as.integer(format(Date,"%m"))]
setkey(sc, ym, Ticker)
cat("[score] cleanT1 rows:", nrow(sc)," ym:", min(sc$ym),"..",max(sc$ym),"\n")

Mw<-dcast(mr, ym~Ticker, value.var="ret_m"); yms<-Mw$ym
mat<-as.matrix(Mw[,-1,drop=FALSE]); rownames(mat)<-as.character(yms)
ym_next<-function(y){yy<-y%/%100L;mm<-y%%100L;if(mm==12L)(yy+1L)*100L+1L else y+1L}
for(i in seq_len(length(yms)-1L)) stopifnot(yms[i+1L]==ym_next(yms[i]))
reb_months<-yms[yms>=REB_FROM & yms<=REB_TO]
cat("[panel] months:",length(yms)," rebalances:",length(reb_months),"\n")

# ---- cell registry -----------------------------------------------------------
mA_methods <- c("EW","LinearTilt","MVO","GMV","HRP","ERC","MaxDiv","CVaR")
mB_methods <- c("GMV","MaxDiv","HRP"); mB_sig<-c("sample","lwlin","lwnls"); mB_var<-c("pure","alpha")
sig_map <- c(sample="sample", lwlin="ledoit_wolf", lwnls="lw_nls")

rows<-list(); hold<-list(); cell_reg<-list(); skipped<-list(); regularized_count<-0L
lw_degen<-0L; t0<-Sys.time()

emit <- function(cell, ym, w){
  rows[[length(rows)+1L]] <<- data.table(cell=cell, ym=ym, Ticker=names(w), w=as.numeric(w))
}

for(t_ym in reb_months){
  idx<-match(t_ym,yms); if(is.na(idx)||idx<WIN){ skipped[[length(skipped)+1L]]<-list(ym=t_ym,reason="win"); next }
  w_idx<-(idx-WIN+1L):idx
  members<-snap[ym==t_ym & member==1L, Ticker]
  liq_ok <-liq[ym==t_ym & !is.na(avgtv20) & avgtv20>=LIQ_MIN, Ticker]
  cand<-intersect(intersect(members, liq_ok), colnames(mat))
  if(length(cand)<40L){ skipped[[length(skipped)+1L]]<-list(ym=t_ym,reason="few_cand"); next }
  sub60<-mat[w_idx, cand, drop=FALSE]; elig<-cand[colSums(!is.na(sub60))==WIN]
  if(length(elig)<40L){ skipped[[length(skipped)+1L]]<-list(ym=t_ym,reason="few_complete60"); next }
  ret60<-sub60[, elig, drop=FALSE]

  # score for elig
  sc_t<-sc[ym==t_ym]; s_all<-setNames(sc_t$score_eff, sc_t$Ticker)
  s_elig<-s_all[names(s_all)%in%elig]; s_elig<-s_elig[!is.na(s_elig)]
  if(length(s_elig)<MAX_NAMES){ skipped[[length(skipped)+1L]]<-list(ym=t_ym,reason="few_score"); next }

  # ===================== MODE A: 고정 top-25 선택, 비중 스윕 =====================
  sel25<-names(sort(s_elig, decreasing=TRUE))[seq_len(MAX_NAMES)]
  r25<-ret60[, sel25, drop=FALSE]
  S25 <- .get_cor_cov(r25, "lw_nls")$cov            # p(25)<n(60)
  a25 <- s_elig[sel25]                              # score alpha on 25
  # MVO alpha scale: score_eff z (mvo_weights winsorizes internally)
  alpha25 <- setNames(as.numeric(a25), sel25)

  wA <- list(
    EW         = w_ew(sel25),
    LinearTilt = setNames(.tilt(a25), sel25),
    MVO        = w_mvo(alpha25, S25),
    GMV        = w_gmv(S25),
    HRP        = w_hrp_cov(S25),
    ERC        = w_erc(S25),
    MaxDiv     = w_maxdiv(S25),
    CVaR       = w_cvar_lp(r25))
  # incumbent 참조: prod top-20 LinearTilt
  sel20<-names(sort(s_elig, decreasing=TRUE))[seq_len(N_PROD_BOOK)]
  wA[["prodLT20"]] <- setNames(.tilt(s_elig[sel20]), sel20)

  A_ok <- all(sapply(wA, function(w) !is.null(w) && length(w)>=1 && abs(sum(w)-1)<1e-6))
  if(!A_ok){ skipped[[length(skipped)+1L]]<-list(ym=t_ym,reason="modeA_null",
             which=paste(names(which(sapply(wA,is.null))),collapse=",")); next }

  # ===================== MODE B: 대형-유니버스 위험선택+비중 (Σ 3-A/B) ==========
  Sig_full<-list()
  ccS<-.get_cor_cov(ret60,"sample");  Sig_full[["sample"]]<-ccS$cov
  ccL<-withCallingHandlers(.get_cor_cov(ret60,"ledoit_wolf"),
        warning=function(w){ lw_degen<<-lw_degen+1L; invokeRestart("muffleWarning") })
  Sig_full[["lwlin"]]<-ccL$cov
  Sig_full[["lwnls"]]<-.get_cor_cov(ret60,"lw_nls")$cov

  wB<-list(); B_ok<-TRUE
  for(sg in mB_sig) for(mth in mB_methods){
    w25<-tryCatch(risk_select25(mth, Sig_full[[sg]], ret60), error=function(e) NULL)
    if(is.null(w25)){ B_ok<-FALSE; next }
    if(!is.null(attr(Sig_full[[sg]],"x"))) NULL
    # pure_risk
    wB[[paste0("B_",mth,"_",sg,"_pure")]] <- w25
    # alpha_combined: 위험선택 25종 × LinearTilt(score)
    sel<-names(w25); asel<-s_elig[sel]; asel<-asel[!is.na(asel)]
    if(length(asel)>=5L){
      wa<-setNames(.tilt(asel), names(asel))
      wB[[paste0("B_",mth,"_",sg,"_alpha")]]<-wa
    } else B_ok<-FALSE
  }
  # sample p>n regularization flag
  if(any(sapply(Sig_full,function(S) min(eigen(S,symmetric=TRUE,only.values=TRUE)$values)< -1e-10))) NULL

  if(!B_ok || length(wB)!=length(mB_sig)*length(mB_methods)*length(mB_var)){
    skipped[[length(skipped)+1L]]<-list(ym=t_ym,reason="modeB_incomplete",n=length(wB)); next }

  # ---- 이 월은 전 셀 feasible -> emit (paired 무결) --------------------------
  for(nmk in names(wA)) emit(paste0("A_",nmk), t_ym, wA[[nmk]])
  for(nmk in names(wB)) emit(nmk, t_ym, wB[[nmk]])

  # holdings meta (cap-tier용): size at t_ym for elig
  sz_t<-snap[ym==t_ym & Ticker%in%elig, .(Ticker, size)]
  hold[[length(hold)+1L]]<-data.table(ym=t_ym, n_elig=length(elig))

  # hard constraint audit (전 셀)
  for(w in c(wA,wB)) stopifnot(length(w)<=MAX_NAMES, all(w>=-1e-9), max(w)<=UB+1e-6, abs(sum(w)-1)<1e-6)

  if(match(t_ym,reb_months)%%36==0)
    cat(sprintf("[wf] %d done (%.1f min)\n", t_ym, as.numeric(difftime(Sys.time(),t0,units="mins"))))
}

W<-rbindlist(rows)
cat("[wf] weight rows:", nrow(W)," cells:", length(unique(W$cell)),
    " months:", length(unique(W$ym))," skipped:", length(skipped)," lw_degen:", lw_degen,"\n")

# cell registry (descriptor)
cells<-sort(unique(W$cell))
for(c_ in cells){
  d<-if(startsWith(c_,"A_")){
    list(mode="A", method=sub("A_","",c_), selection="score_eff top-25 (top-20 for prodLT20)",
         sigma=if(sub("A_","",c_)%in%c("MVO","GMV","HRP","ERC","MaxDiv"))"lw_nls_25x25" else "none", variant="fixed_alpha_selection")
  } else {
    parts<-strsplit(c_,"_")[[1]]  # B, method, sig, var
    list(mode="B", method=parts[2], sigma=sig_map[[parts[3]]], variant=parts[4],
         selection="large-universe risk method -> top-25")
  }
  cell_reg[[c_]]<-d
}

write_parquet(W, file.path(OUT_DIR,"fq063_weights.parquet"))
write_parquet(rbindlist(hold), file.path(OUT_DIR,"fq063_holdings.parquet"))
write_json(cell_reg, file.path(OUT_DIR,"fq063_cell_registry.json"), auto_unbox=TRUE, pretty=TRUE)
meta<-list(pin_tag=PIN_TAG, built_at=format(Sys.time(),"%Y-%m-%d %H:%M:%S"),
  n_rebalances=length(reb_months), n_months_emitted=length(unique(W$ym)),
  n_cells=length(cells), cells=cells, lw_degenerate_warnings=lw_degen,
  n_skipped=length(skipped), skipped=skipped,
  params=list(bounds=BOUNDS, max_names=MAX_NAMES, min_names=MIN_NAMES, lambda_tilt=LAMBDA_TILT,
              lambda_mvo=LAMBDA_MVO, psi=PSI, liq_min=LIQ_MIN, win=WIN, cvar_beta=CVAR_BETA,
              reb_from=REB_FROM, reb_to=REB_TO))
write_json(meta, file.path(OUT_DIR,"fq063_run01_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat("[done] run_01 —", round(as.numeric(difftime(Sys.time(),t0,units="mins")),1),"min\n")
