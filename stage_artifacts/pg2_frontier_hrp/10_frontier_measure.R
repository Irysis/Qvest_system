## ============================================================================
## PG2 Frontier-HRP measurement — Part 1: weight dispatch + canonical measurement
## Reweights the IDENTICAL STR_1715 top-20 sleeve each month by each method,
## applies the SAME m4×β_R05 overlay, measures canonical PORT_t/SR/calmar/MDD/TO
## + book-marginal ΔIR vs incumbent book (1.4055). Real-computation only.
##
## METHOD env selects a single method (parallel workflow); unset = run cheap set.
## Heavy methods (heavytail_dcc, regime) are opt-in via METHOD.
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(quadprog)
  library(sandwich); library(lmtest); library(lubridate)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent = TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCR  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
OUT  <- file.path(ROOT, "stage_artifacts/pg2_frontier_hrp")
FH   <- file.path(ROOT, "02_Infrastructure/portfolio/frontier_hrp")
COST <- 0.0015

## --- estimators / helpers from ramp weight_advanced (cov + classical) --------
## (source in a sandboxed env to grab just the primitives we need)
wa_env <- new.env()
wa_src <- readLines(file.path(ROOT, "02_Infrastructure/ramp/search/weight_advanced.R"))
## keep only lines defining the primitives (avoid the shared-cache readRDS at top)
wa_keep <- grep("^(cap_norm|lw_shrink|denoise_cov|minvar|maxsharpe|erc|maxdiv|hrp|nco)<-function", wa_src)
## the functions span multiple lines; safest is to eval the specific defs by extracting blocks.
## Instead: define them here directly (verbatim from weight_advanced.R) to stay faithful.
suppressPackageStartupMessages(library(quadprog))
cap_norm<-function(w){w<-as.numeric(w);w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w);w[!is.finite(w)]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20;if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix]);w[!is.finite(w)]<-0};w[w>0.20]<-0.20;s<-sum(w);if(!is.finite(s)||s<=0)return(rep(1/length(w),length(w)));w/s}
cap_norm2 <- function(w, cols) { x <- as.numeric(w); x[!is.finite(x)] <- 0; v <- cap_norm(x); setNames(v, cols) }
lw_shrink<-function(R){R<-R[,colSums(is.finite(R))>=nrow(R)*0.6,drop=FALSE];R[!is.finite(R)]<-0;n<-nrow(R);p<-ncol(R);if(p<2)return(list(S=diag(max(p,1)),cols=colnames(R)))
  S<-cov(R);d<-mean(diag(S));T0<-diag(d,p);Xc<-scale(R,center=TRUE,scale=FALSE);phi<-sum((crossprod(Xc^2)/n - S^2))/n; gamma<-sum((S-T0)^2); lam<-max(0,min(1,(phi/gamma)/n*p)); if(!is.finite(lam))lam<-0.3
  list(S=(1-lam)*S+lam*T0,cols=colnames(R),lam=lam)}
denoise_cov<-function(R){R<-R[,colSums(is.finite(R))>=nrow(R)*0.6,drop=FALSE];R[!is.finite(R)]<-0;sdv0<-apply(R,2,sd);R<-R[,sdv0>1e-9,drop=FALSE];n<-nrow(R);p<-ncol(R);if(p<3)return(list(S=cov(R),cols=colnames(R)))
  sdv<-apply(R,2,sd);sdv[sdv<1e-8]<-1e-8;Cr<-cor(R);Cr[!is.finite(Cr)]<-0;diag(Cr)<-1;e<-eigen(Cr,symmetric=TRUE);ev<-pmax(e$values,1e-8);q<-n/p;lmax<-(1+sqrt(1/q))^2
  ev2<-ev;noise<-ev<lmax;if(any(noise))ev2[noise]<-mean(ev[noise]);Cr2<-e$vectors%*%diag(ev2)%*%t(e$vectors);Cr2<-(Cr2+t(Cr2))/2;diag(Cr2)<-1;S<-outer(sdv,sdv)*Cr2;list(S=S,cols=colnames(R))}
minvar<-function(S){p<-ncol(S);Dm<-S+diag(1e-5,p);A<-cbind(rep(1,p),diag(p),-diag(p));b<-c(1,rep(0,p),rep(-0.20,p));r<-tryCatch(solve.QP(Dm,rep(0,p),A,b,meq=1),error=function(e)NULL);if(is.null(r))return(rep(1/p,p));cap_norm(pmax(r$solution,0))}
erc<-function(S){p<-ncol(S);w<-1/sqrt(diag(S));w<-w/sum(w);for(it in 1:200){mrc<-as.numeric(S%*%w);rc<-w*mrc;tgt<-mean(rc);w<-w*(tgt/(rc+1e-12))^0.1;w[w<0]<-0;w<-w/sum(w)};cap_norm(w)}
hrp<-function(S){p<-ncol(S);if(p<3)return(rep(1/p,p));sdv<-sqrt(diag(S));Cr<-S/outer(sdv,sdv);Cr[!is.finite(Cr)]<-0;d<-sqrt(pmax(0.5*(1-Cr),0));hc<-tryCatch(hclust(as.dist(d),method="single"),error=function(e)NULL);if(is.null(hc))return(cap_norm(1/sdv))
  ord<-hc$order;w<-rep(1,p);names(w)<-1:p;cl<-list(ord)
  while(length(cl)>0){nc<-list();for(items in cl){if(length(items)<=1)next;half<-floor(length(items)/2);c1<-items[1:half];c2<-items[(half+1):length(items)]
    getIV<-function(idx){sub<-S[idx,idx,drop=FALSE];iv<-1/diag(sub);iv<-iv/sum(iv);as.numeric(t(iv)%*%sub%*%iv)};v1<-getIV(c1);v2<-getIV(c2);a<-1-v1/(v1+v2);w[c1]<-w[c1]*a;w[c2]<-w[c2]*(1-a);nc<-c(nc,list(c1),list(c2))};cl<-nc}
  cap_norm(w)}
nco<-function(S,mu=NULL){p<-ncol(S);if(p<4)return(if(is.null(mu))minvar(S) else minvar(S));sdv<-sqrt(diag(S));Cr<-S/outer(sdv,sdv);Cr[!is.finite(Cr)]<-0;d<-sqrt(pmax(0.5*(1-Cr),0))
  hc<-tryCatch(hclust(as.dist(d),method="ward.D2"),error=function(e)NULL);if(is.null(hc))return(minvar(S));K<-max(2,min(8,round(sqrt(p))));cl<-cutree(hc,k=K)
  wIntra<-rep(0,p);for(k in 1:K){idx<-which(cl==k);if(length(idx)==1){wIntra[idx]<-1}else{sub<-S[idx,idx,drop=FALSE];wi<-minvar(sub);wIntra[idx]<-wi}}
  Sred<-matrix(0,K,K);for(a in 1:K)for(bb in 1:K){ia<-which(cl==a);ib<-which(cl==bb);Sred[a,bb]<-as.numeric(t(wIntra[ia])%*%S[ia,ib,drop=FALSE]%*%wIntra[ib])}
  wInter<-minvar(Sred+diag(1e-8,K));w<-rep(0,p);for(k in 1:K){idx<-which(cl==k);w[idx]<-wIntra[idx]*wInter[k]};cap_norm(w)}

## --- frontier fidelity-PASS modules -----------------------------------------
source(file.path(FH, "cotton_schur.R"))
source(file.path(FH, "lohre_taildep.R"))
source(file.path(FH, "network_rp.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/strategy_tilt_weights.R"))
## heavy modules sourced lazily only when needed
.load_heavy <- function() {
  source(file.path(FH, "paolella_heavytail_dcc.R"))
  source(file.path(FH, "dynamic_regime_rp.R"))
}

## --- metrics helpers (NW lag-3 t on active) ---------------------------------
nwt <- function(x, lag = 3L) {
  x <- as.numeric(x); x <- x[is.finite(x)]; n <- length(x); if (n < 10) return(NA_real_)
  as.numeric(coeftest(lm(x ~ 1), vcov = sandwich::NeweyWest(lm(x ~ 1), lag = lag, prewhite = FALSE))[1, 3])
}
IRf   <- function(x){ x <- x[is.finite(x)]; if (length(x) < 6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
calf  <- function(r){ nav <- cumprod(1+r); cagr <- prod(1+r)^(12/length(r))-1; cagr/abs(min(nav/cummax(nav)-1)) }
mddf  <- function(r){ nav <- cumprod(1+r); min(nav/cummax(nav)-1) }
oosr  <- function(act){ n<-length(act); median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE) }

## --- shared cache ------------------------------------------------------------
C   <- readRDS(file.path(SCR, "frontier_sleeve_cache.rds"))
SEL <- C$SEL; RMm <- C$RMm; p5 <- C$p5; bm_m <- C$bm_m; inc <- C$inc
dts <- sort(unique(SEL$Date))
## index return series (pinned KOSPI200 monthly, realized-month keyed) for regime/DCC
## Build a monthly KOSPI200 return vector aligned to realized months up to each t.
idx_ret_by_rym <- setNames(bm_m$bm_ret, bm_m$realized_ym)

## trailing 36m return matrix for held tickers, using months realized THROUGH t
## panel signal month t -> trailing returns are realized months <= t (rownames of RMm are ym).
trail_cov_input <- function(ymt, tk, k = 36) {
  ri <- which(rownames(RMm) == ymt)
  if (length(ri) == 0) return(NULL)
  tk <- tk[tk %in% colnames(RMm)]
  if (length(tk) < 3) return(NULL)
  M <- RMm[max(1, ri - k + 1):ri, tk, drop = FALSE]   # inclusive of month t (realized <= t)
  M
}

## ============================================================================
## WEIGHT DISPATCH — returns named weight vector for the sleeve at month i
## alpha tilt variant handled by caller (multiply pure-risk weights by score tilt)
## ============================================================================
schur_gamma_grid <- c(0, 0.1, 0.25, 0.5, 0.75, 1.0)

compute_weights <- function(method, sel, M, mu_score) {
  tk <- sel$Ticker; p <- length(tk)
  ## M = trailing return matrix (rows=months, cols=tickers present); may drop names
  present <- if (!is.null(M)) colnames(M) else character(0)
  ord_tk  <- tk
  ## default EW fallback
  ewv <- setNames(rep(1/p, p), tk)

  ## covariance (lw-shrink default; denoise for denoise_* methods)
  Scov <- NULL
  if (!is.null(M) && length(present) >= 3 && nrow(M) >= 6) {
    est <- if (grepl("denoise", method)) denoise_cov(M) else lw_shrink(M)
    Scov <- est$S; colnames(Scov) <- rownames(Scov) <- est$cols
  }

  ## map a weight vector defined on `present` back to full tk (missing -> 0 then EW-fill)
  expand <- function(wp, cols) {
    wp[!is.finite(wp)] <- 0
    w <- setNames(rep(0, p), tk); w[cols] <- wp[cols]
    if (!is.finite(sum(w)) || sum(w) <= 0) return(ewv)
    ## names absent from cov get residual EW share of the gap
    miss <- setdiff(tk, cols)
    if (length(miss) > 0) { w[miss] <- mean(w[cols], na.rm = TRUE) }
    w[!is.finite(w)] <- 0
    if (sum(w) <= 0) return(ewv)
    w / sum(w)
  }

  base <- switch(method,
    "ew"        = ewv,
    "lineartilt" = {  # handled specially by caller (needs w_prev); placeholder EW
      ewv
    },
    "hrp_legacy" = if (!is.null(Scov)) expand(setNames(hrp(Scov), colnames(Scov)), colnames(Scov)) else ewv,
    "minvar"     = if (!is.null(Scov)) expand(setNames(minvar(Scov), colnames(Scov)), colnames(Scov)) else ewv,
    "nco"        = if (!is.null(Scov)) expand(setNames(nco(Scov), colnames(Scov)), colnames(Scov)) else ewv,
    "erc"        = if (!is.null(Scov)) expand(setNames(erc(Scov), colnames(Scov)), colnames(Scov)) else ewv,
    "network"    = {  # network_rp softmax default (paper). also proportional diag.
      if (!is.null(Scov)) {
        nr <- tryCatch(network_rp_weights(Scov, dist_method="paper", norm="softmax"), error=function(e) NULL)
        if (is.null(nr)) ewv else expand(cap_norm2(nr$weights, colnames(Scov)), colnames(Scov))
      } else ewv
    },
    "network_prop" = {
      if (!is.null(Scov)) {
        nr <- tryCatch(network_rp_weights(Scov, dist_method="paper", norm="proportional"), error=function(e) NULL)
        if (is.null(nr)) ewv else expand(cap_norm2(nr$weights, colnames(Scov)), colnames(Scov))
      } else ewv
    },
    "taildep"    = {  # Lohre lower-tail-dependence HRP
      if (!is.null(M) && ncol(M) >= 3 && nrow(M) >= 12) {
        lr <- tryCatch(lohre_hrp(M, measure="tail_lower", long_only=TRUE, ub=0.20), error=function(e) NULL)
        if (is.null(lr)) ewv else expand(setNames(lr$weights, colnames(M)), colnames(M))
      } else ewv
    },
    ## schur handled outside (gamma sweep)
    ewv
  )
  base
}

## ============================================================================
## RUN ONE METHOD across all months -> net-active series + metrics
## alpha_tilt: if TRUE, multiply pure-risk weights by score-rank tilt then renorm
## schur_gamma: if not NA, use cotton_schur at that gamma (pure-risk covariance)
## ============================================================================
run_method <- function(method, alpha_tilt = FALSE, schur_gamma = NA_real_,
                        heavy = NULL, verbose = FALSE) {
  prev_w <- NULL
  rows <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    d <- dts[i]; sel <- SEL[Date == d]; if (nrow(sel) < C$TOP_N) next
    ymt <- sel$ym[1]; rym <- sel$realized_ym[1]
    tk <- sel$Ticker; p <- length(tk)
    mu_score <- setNames(sel$score_eff, tk)
    M <- trail_cov_input(ymt, tk, 36)

    ## ---- weight vector ----
    if (method == "lineartilt") {
      w <- linear_tilt_to_penalty_qd(mu_score, lambda = 1.5, w_prev = prev_w, phi = 3.0, lb = 0, ub = 0.20)
      w <- w[tk]; names(w) <- tk
    } else if (!is.na(schur_gamma)) {
      ## Schur (Cotton) on trailing lw-shrink covariance of present names
      if (!is.null(M) && ncol(M) >= 3 && nrow(M) >= 6) {
        est <- lw_shrink(M); S <- est$S; colnames(S) <- rownames(S) <- est$cols
        wp <- cotton_schur(S, gamma = schur_gamma, term = 5, shrink = TRUE,
                           adaptive = TRUE, long_only = TRUE, ub = 0.20)
        names(wp) <- colnames(S)
        w <- setNames(rep(0, p), tk); w[names(wp)] <- wp
        miss <- setdiff(tk, names(wp)); if (length(miss)) w[miss] <- mean(wp)
        if (sum(w) <= 0) w <- setNames(rep(1/p, p), tk) else w <- w / sum(w)
      } else w <- setNames(rep(1/p, p), tk)
    } else if (!is.null(heavy)) {
      w <- heavy(sel, M, mu_score, rym, i)
    } else {
      w <- compute_weights(method, sel, M, mu_score)
    }
    ## optional alpha tilt overlay on pure-risk weights: w_i *= (1 + lam*rankcentered)
    if (alpha_tilt && !(method %in% c("lineartilt"))) {
      r <- rank(mu_score[names(w)], ties.method = "average"); N <- length(r)
      centered <- (r - mean(r)) / max(N - 1, 1)
      tiltf <- pmax(1 + 1.5 * 2 * centered, 1e-6)   # same lambda=1.5 tilt strength
      w <- w * tiltf; w <- cap_norm(as.numeric(w)); names(w) <- tk
    }
    w <- w[tk]; w[!is.finite(w)] <- 0; if (sum(w) <= 0) w <- setNames(rep(1/p,p),tk) else w <- w/sum(w)

    ## ---- gross return ----
    rr <- merge(data.table(Ticker = names(w), w = as.numeric(w)),
                sel[, .(Ticker, Ret_1m)], by = "Ticker", all.x = TRUE)
    rr[is.na(Ret_1m), Ret_1m := 0]
    gross <- sum(rr$w * rr$Ret_1m)
    ## ---- turnover ----
    if (is.null(prev_w)) traded <- 1 else {
      alln <- union(names(w), names(prev_w))
      wc <- setNames(rep(0, length(alln)), alln); wc[names(w)] <- w
      wp <- setNames(rep(0, length(alln)), alln); wp[names(prev_w)] <- prev_w
      traded <- sum(abs(wc - wp))
    }
    rows[[i]] <- data.table(realized_ym = rym, ret_net_bare = gross - traded * COST, traded = traded)
    prev_w <- w
  }
  sl <- rbindlist(rows)
  ## apply overlay + benchmark by realized month
  mg <- merge(sl, p5[, .(realized_ym, beta_R05, m4, dR05)], by = "realized_ym")
  mg <- merge(mg, bm_m, by = "realized_ym"); setorder(mg, realized_ym)
  mg[, ret_ov := beta_R05 * m4 * ret_net_bare - dR05 * COST]
  mg[, active := ret_ov - bm_ret]
  mg
}

## ---- metric summary for a method series (overlay applied) -------------------
summarize_method <- function(mg, label) {
  a <- mg$active; r <- mg$ret_ov
  data.table(
    method       = label,
    n_months     = nrow(mg),
    PORT_t       = round(nwt(a), 4),
    IR_active    = round(IRf(a), 4),
    SR           = round(mean(r)/sd(r)*sqrt(12), 4),
    CAGR         = round(prod(1+r)^(12/length(r))-1, 4),
    MDD          = round(mddf(r), 4),
    Calmar       = round(calf(r), 4),
    TO_annual    = round(mean(mg$traded, na.rm=TRUE)*12, 3),
    mean_active_ann = round(mean(a)*12, 4)
  )
}

## ---- book-marginal ΔIR vs incumbent (blend candidate active w/ inc active) --
bookmarginal <- function(mg, label) {
  J <- merge(inc[, .(realized_ym, inc_active)], mg[, .(realized_ym, cand_active = active)],
             by = "realized_ym"); setorder(J, realized_ym)
  inc_ir_ov <- IRf(J$inc_active)
  ## active-basis correlation (orthogonality)
  cor_act <- cor(J$inc_active, J$cand_active)
  ## 50/50 blend
  J[, blend50 := 0.5*inc_active + 0.5*cand_active]
  ir50 <- IRf(J$blend50)
  ## IR-max blend, candidate weight capped at 0.5 (sleeve is auxiliary)
  grid <- seq(0, 0.5, by = 0.01)
  irs  <- sapply(grid, function(w) IRf((1-w)*J$inc_active + w*J$cand_active))
  w_opt <- grid[which.max(irs)]; ir_opt <- max(irs)
  ## 2021+ survival of best blend
  J21 <- J[realized_ym >= "2021-01"]
  t21_blend <- nwt((1-w_opt)*J21$inc_active + w_opt*J21$cand_active)
  data.table(
    method = label, overlap_m = nrow(J),
    inc_IR_overlap = round(inc_ir_ov, 4),
    cand_IR = round(IRf(J$cand_active), 4),
    active_cor = round(cor_act, 4),
    blend50_IR = round(ir50, 4), dIR_blend50 = round(ir50 - inc_ir_ov, 4),
    IRmax_w = w_opt, IRmax_IR = round(ir_opt, 4), dIR_IRmax = round(ir_opt - inc_ir_ov, 4),
    t21_blend_opt = round(t21_blend, 3)
  )
}

cat("[10_frontier_measure] primitives + modules + drivers loaded\n")
