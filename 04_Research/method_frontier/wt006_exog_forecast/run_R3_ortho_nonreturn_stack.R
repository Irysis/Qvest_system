# WT-006 R3 — ortho_nonreturn_stack: break the logic_stack collinearity that collapsed to equal in R2.
# (a) Gram-Schmidt residualize each of the 6 EN logic thetas (theta_EN_L1..L6) against the others in
#     tilt-space (g_L = theta_L - 1/6), IS-ONLY (residualization betas from history<anchor, annual refit),
#     reconstruct each learner's ORTHOGONAL theta = simplex(1/6 + u_k), then non-negative IS-only stack.
# (b) NON-RETURN pure learner: crowding (val_spread, vs_z) + dispersion (disp_ret12, avg_corr24) ONLY,
#     momentum/trailing-return features EXCLUDED. Same walk-forward EN machinery as R1 (family FE +
#     invariant-interacted feats + glmnet alpha=0.5 + softmax beta=2). Fully PIT (expanding, IS-only).
# Deliverable = combined non-negative IS-only stack over {6 ortho EN learners + non-return learner}.
# CORE Q: do orthogonal / non-return base learners escape the common bull-tilt convex hull and beat
#         factor-momentum (baseline cap-w port_t 1.277)? beats_momentum = (paired_vs_mom_t > 1.0).
# PIT: all learners walk-forward IS-only. lag1 self-check reported. metric_type=canonical (backtested).
suppressMessages({library(data.table); library(arrow); library(glmnet)})
setDTthreads(1); set.seed(42)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- .fams
dates <- .oos_dates
yrs <- as.integer(format(dates,"%Y")); anchors <- dates[!duplicated(yrs)]

# =========================================================================================
# PART (b) — NON-RETURN learner (crowding + dispersion only, momentum excluded)
# =========================================================================================
X <- as.data.table(read_parquet(file.path(OUT,"wt006_candidate_features.parquet"))); X[,date:=as.Date(date)]
nonret_feats <- c("val_spread","vs_z","disp_ret12","avg_corr24")   # NO tr_* / complex_mom / rel_rank
stopifnot(all(nonret_feats %in% names(X)))
is_invariant <- function(f){ v <- X[, .(u=uniqueN(get(f))), by=date]; mean(v$u==1, na.rm=TRUE) > 0.95 }
inv_flag <- sapply(nonret_feats, is_invariant)
cat("[nonreturn] family-invariant (interacted w/ family):", paste(names(inv_flag)[inv_flag], collapse=" "),
    "| family-specific:", paste(names(inv_flag)[!inv_flag], collapse=" "), "\n")

build_design <- function(df, feats){
  fml <- intersect(feats, names(df))
  FMAT <- model.matrix(~ family - 1, data=df)
  cols <- list(FMAT); pf <- rep(0, ncol(FMAT))
  for(f in fml){
    x <- df[[f]]
    if(isTRUE(inv_flag[[f]])){
      M <- FMAT * x; colnames(M) <- paste0(f, "_x_", gsub("family","",colnames(FMAT)))
      cols[[length(cols)+1]] <- M; pf <- c(pf, rep(1, ncol(M)))
    } else { cols[[length(cols)+1]] <- matrix(x, ncol=1, dimnames=list(NULL,f)); pf <- c(pf,1) }
  }
  list(x=do.call(cbind, cols), pf=pf)
}
wf_forecast <- function(feats, alpha=0.5, refit_every=12L){
  fml <- intersect(feats, names(X)); need <- c("date","family","fwd_ret", fml); D <- X[, ..need]
  preds <- vector("list", length(dates)); last_fit<-NULL; last_anchor<-NULL; last_scale<-NULL; refit_count<-0L
  for(i in seq_along(dates)){
    t <- dates[i]
    do_refit <- is.null(last_fit) || (as.integer(round(difftime(t,last_anchor,units="days")/30.4)) >= refit_every)
    tr <- D[date < t]; tr <- tr[complete.cases(tr[, c("fwd_ret", fml), with=FALSE])]
    if(nrow(tr) < 60){ next }
    if(do_refit){
      des <- build_design(tr, fml); xmat <- des$x; y <- tr$fwd_ret
      ctr <- colMeans(xmat); csd <- apply(xmat,2,sd); csd[csd<=0|!is.finite(csd)] <- 1; pen <- des$pf==1
      xs <- xmat; xs[,pen] <- scale(xmat[,pen], center=ctr[pen], scale=csd[pen]); xs[!is.finite(xs)] <- 0
      cvf <- tryCatch(cv.glmnet(xs, y, alpha=alpha, penalty.factor=des$pf, nfolds=5, standardize=FALSE), error=function(e) NULL)
      if(is.null(cvf)){ next }
      last_fit<-cvf; last_anchor<-t; last_scale<-list(ctr=ctr,csd=csd,pen=pen,cols=colnames(xmat),feats=fml); refit_count<-refit_count+1L
    }
    te <- D[date==t]; te <- te[family %in% fams]; if(nrow(te)==0) next
    des_te <- build_design(te, last_scale$feats); xt <- des_te$x
    miss <- setdiff(last_scale$cols, colnames(xt)); for(m in miss) xt <- cbind(xt, setNames(matrix(0,nrow(xt),1),m))
    xt <- xt[, last_scale$cols, drop=FALSE]
    xt[, last_scale$pen] <- scale(xt[, last_scale$pen], center=last_scale$ctr[last_scale$pen], scale=last_scale$csd[last_scale$pen])
    xt[!is.finite(xt)] <- 0
    ph <- as.numeric(predict(last_fit, newx=xt, s="lambda.min")); preds[[i]] <- data.table(date=t, family=te$family, pred=ph)
  }
  P <- rbindlist(preds); attr(P,"refit_count")<-refit_count; P
}
pred_to_theta <- function(P, beta=2){ P[is.finite(pred), {z<-(pred-mean(pred))/(sd(pred)+1e-9); w<-exp(beta*z); .(family=family, theta=w/sum(w))}, by=date] }

P_nr <- wf_forecast(nonret_feats)
theta_nonreturn <- pred_to_theta(P_nr, beta=2)
theta_nonreturn[,date:=as.Date(date)]
cat(sprintf("[nonreturn] EN refits=%d oos_mo=%d\n", attr(P_nr,"refit_count"), uniqueN(theta_nonreturn$date)))

# =========================================================================================
# PART (a) — Gram-Schmidt orthogonalized EN theta learners (IS-only) + non-negative stack
# =========================================================================================
learners <- c("L1_crowding","L2_dispersion","L3_funding","L4_crashrisk","L5_crossfactor","L6_macro")
TH <- list(); for(L in learners){ th <- as.data.table(read_parquet(file.path(OUT,paste0("theta_EN_",L,".parquet")))); th[,date:=as.Date(date)]; TH[[L]] <- th }

# wide tilt panel: rows (date,family), cols = per-learner tilt (theta - 1/6)
TL <- NULL
for(nm in learners){ t <- copy(TH[[nm]]); t[,v:=theta-1/6]; t <- t[,.(date,family,v)]; setnames(t,"v",nm)
  TL <- if(is.null(TL)) t else merge(TL,t,by=c("date","family")) }
setorder(TL, date, family)
MIN_HIST <- 60L   # rows (=~10 months x6) before orthogonalizing; else fall back to raw EN tilt

# produce reconstructed ORTHOGONAL theta per learner, PIT (betas from history<anchor of the month)
outrows <- vector("list", length(dates))
for(i in seq_along(dates)){
  t <- dates[i]; anc <- max(anchors[anchors<=t])
  H <- TL[date < anc]; cur <- TL[date==t]; if(nrow(cur)==0) next
  G_c <- as.matrix(cur[, ..learners]); nl <- length(learners)
  U_c <- matrix(0, nrow(G_c), nl); U_c[,1] <- G_c[,1]
  if(nrow(H) >= MIN_HIST){
    G_h <- as.matrix(H[, ..learners]); U_h <- matrix(0, nrow(G_h), nl); U_h[,1] <- G_h[,1]
    for(k in 2:nl){
      Uk <- U_h[,1:(k-1),drop=FALSE]
      b <- tryCatch(solve(crossprod(Uk)+diag(1e-8,k-1), crossprod(Uk, G_h[,k])), error=function(e) rep(0,k-1))
      U_h[,k] <- G_h[,k] - Uk %*% b
      U_c[,k] <- G_c[,k] - U_c[,1:(k-1),drop=FALSE] %*% b
    }
  } else { U_c <- G_c }   # early period: raw EN tilts (no basis yet)
  rec <- data.table(date=t, family=cur$family)
  for(k in seq_along(learners)){ u <- U_c[,k]; th <- 1/6 + u; th[th<0] <- 0; s <- sum(th)
    if(!is.finite(s)||s<=0) th <- rep(1/6, length(th)) else th <- th/s; rec[[learners[k]]] <- th }
  outrows[[i]] <- rec
}
REC <- rbindlist(outrows)
TH_ortho <- lapply(learners, function(nm) REC[,.(date,family,theta=get(nm))]); names(TH_ortho) <- paste0("O_",learners)

# =========================================================================================
# non-negative IS-only stack machinery (softmax over trailing IS active Sharpe, annual refit)
# =========================================================================================
active_of <- function(th){ a <- .active_series(.canon(.score_from_theta(th))); setkey(a,date); a }
build_stack_theta <- function(THset, Aset, gamma=2, min_hist=24L){
  ln <- names(Aset); K <- length(ln)
  M <- data.table(date=dates); for(nm in ln) M <- merge(M, Aset[[nm]][,.(date, a=active)][,setnames(.SD,"a",nm)], by="date", all.x=TRUE)
  W_anchor <- list()
  for(anc in as.character(anchors)){
    hist <- M[date < as.Date(anc)]
    if(nrow(hist) < min_hist){ W_anchor[[anc]] <- setNames(rep(1/K,K),ln); next }
    sr <- sapply(ln, function(nm){ x<-hist[[nm]]; x<-x[is.finite(x)]; s<-sd(x); if(length(x)<min_hist||!is.finite(s)||s<=0) return(NA_real_); mean(x)/s*sqrt(12) })
    if(all(!is.finite(sr))){ W_anchor[[anc]] <- setNames(rep(1/K,K),ln); next }
    sr[!is.finite(sr)] <- min(sr[is.finite(sr)], na.rm=TRUE)
    e <- exp(gamma*(sr-max(sr))); w <- e/sum(e); names(w) <- ln; W_anchor[[anc]] <- w
  }
  out <- vector("list", length(dates))
  for(i in seq_along(dates)){ t <- dates[i]; anc <- max(anchors[anchors<=t]); w <- W_anchor[[as.character(anc)]]
    blend <- NULL
    for(k in seq_along(ln)){ thk <- THset[[ln[k]]][date==t, .(family, theta)]; if(nrow(thk)==0) next
      thk[, theta := theta * w[k]]; blend <- if(is.null(blend)) thk else rbind(blend, thk) }
    if(is.null(blend)) next
    b <- blend[, .(theta=sum(theta)), by=family]; b[, theta := theta/sum(theta)]
    out[[i]] <- data.table(date=t, family=b$family, theta=b$theta) }
  rbindlist(out)
}

cat("[stack] computing per-learner active series (canonical) ...\n")
A_ortho <- lapply(TH_ortho, active_of)
A_nr <- active_of(theta_nonreturn)

# --- variants ---
# ortho_equal: w=1/6 over the 6 ortho learners (true equal-combine baseline the learned stack must beat)
ortho_equal <- rbindlist(lapply(dates, function(t){
  b <- rbindlist(lapply(names(TH_ortho), function(nm) TH_ortho[[nm]][date==t,.(family,theta)]))[, .(theta=sum(theta)/length(TH_ortho)), by=family]
  data.table(date=t, family=b$family, theta=b$theta/sum(b$theta)) }))
# ortho_stack: learned non-negative stack over 6 ortho learners only
theta_ortho_stack <- build_stack_theta(TH_ortho, A_ortho, gamma=2)
# combined DELIVERABLE: 6 ortho + non-return learner, learned non-negative stack
THc <- c(TH_ortho, list(nonreturn=theta_nonreturn)); Ac <- c(A_ortho, list(nonreturn=A_nr))
theta_combined <- build_stack_theta(THc, Ac, gamma=2)
write_parquet(theta_combined, file.path(OUT,"theta_R3_ortho_nonreturn_stack.parquet"))
write_parquet(theta_nonreturn, file.path(OUT,"theta_R3_nonreturn.parquet"))
write_parquet(theta_ortho_stack, file.path(OUT,"theta_R3_ortho_stack.parquet"))

# =========================================================================================
# canonical measurement
# =========================================================================================
r_comb  <- eval_theta(theta_combined,   "ortho_nonreturn_stack")   # DELIVERABLE
r_nr    <- eval_theta(theta_nonreturn,  "nonreturn_only")
r_os    <- eval_theta(theta_ortho_stack,"ortho_stack")
r_oe    <- eval_theta(ortho_equal,      "ortho_equal")

pr <- function(r) cat(sprintf("%-22s port_t=%6.3f ew_uni_t=%6.3f oos_ret=%7.3f net_sr=%6.3f calmar=%5.3f turn=%6.2f paired_mom=%7.3f paired_static=%7.3f lag1_pt=%6.3f n=%d\n",
  r$label, r$port_t, r$ew_uni_t, r$oos_ret, r$net_sr, r$calmar, r$turnover, r$paired_vs_mom_t, r$paired_vs_static_t, r$lag1_port_t, r$n_months))
cat(sprintf("\n=== R3 ortho_nonreturn_stack (baseline momentum port_t=%.3f, HARD gate 2.95) ===\n", .BASELINE_MOM_PORT_T))
pr(r_comb); pr(r_nr); pr(r_os); pr(r_oe)

# stack weight transparency: what did combined stack pick at each anchor?
Mc <- data.table(date=dates); for(nm in names(Ac)) Mc <- merge(Mc, Ac[[nm]][,.(date,a=active)][,setnames(.SD,"a",nm)], by="date", all.x=TRUE)
cat("\ncombined-stack trailing IS active Sharpe at anchors (drives softmax w):\n")
for(anc in as.character(anchors)){ hist <- Mc[date<as.Date(anc)]
  sr <- sapply(names(Ac), function(nm){ x<-hist[[nm]]; x<-x[is.finite(x)]; s<-sd(x); if(length(x)<24||!is.finite(s)||s<=0) return(NA); round(mean(x)/s*sqrt(12),2)})
  cat(sprintf("  %s (h=%3d): %s\n", substr(anc,1,7), nrow(hist), paste(sprintf("%s=%s",c(paste0("O",1:6),"NR"),sr), collapse=" "))) }

best <- list(r_comb=r_comb, r_nr=r_nr, r_os=r_os)[[ which.max(c(r_comb$paired_vs_mom_t, r_nr$paired_vs_mom_t, r_os$paired_vs_mom_t)) ]]
res_out <- list(
  baseline_mom_port_t=.BASELINE_MOM_PORT_T, hard_gate=2.95,
  deliverable=r_comb, nonreturn_only=r_nr, ortho_stack=r_os, ortho_equal=r_oe,
  best_by_paired_mom=best$label,
  beats_momentum=isTRUE(r_comb$paired_vs_mom_t > 1.0),
  best_beats_momentum=isTRUE(best$paired_vs_mom_t > 1.0),
  wall_moved=isTRUE(r_comb$port_t >= 2.95)
)
jsonlite::write_json(res_out, file.path(OUT,"R3_ortho_nonreturn_results.json"), pretty=TRUE, auto_unbox=TRUE, digits=4)
saveRDS(res_out, file.path(OUT,"R3_ortho_nonreturn_results.rds"))
cat(sprintf("\n[done] deliverable theta_R3_ortho_nonreturn_stack.parquet written. beats_momentum=%s (paired=%.3f). best=%s\n",
    isTRUE(r_comb$paired_vs_mom_t>1.0), r_comb$paired_vs_mom_t, best$label))
