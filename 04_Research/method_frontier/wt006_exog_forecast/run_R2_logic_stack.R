# WT-006 R2 — logic_stack: learned non-negative sum-1 stacking of 6 EN logic sub-predictions.
# Base learners = theta_EN_L1..L6 (each already walk-forward PIT). Meta-weight w_L(t) learned
# rolling IS-ONLY from realized per-learner active Sharpe; annual refit; theta_stack = Σ w_L θ_L.
# PIT: at decision month t, meta-weights use only learner active returns realized for months < t.
#      (no OOS tuning of gamma/rule; single a-priori meta-rule.)
# Also: equal_stack (w=1/6, the true "equal-combine of the 6 logic thetas" baseline the learned
#      stack must beat) + augmented stack incl. momentum/valuation as extra learners (honest test of
#      the ONLY path to beating momentum, reported separately, NOT the spec deliverable).
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
OUT <- "04_Research/method_frontier/wt006_exog_forecast"

learners <- c("L1_crowding","L2_dispersion","L3_funding","L4_crashrisk","L5_crossfactor","L6_macro")
TH <- list()
for(L in learners){
  th <- as.data.table(read_parquet(file.path(OUT, paste0("theta_EN_",L,".parquet"))))
  th[,date:=as.Date(date)]; TH[[L]] <- th
}
# augmented extra learners: factor momentum (WT005 baseline logic) + valuation
mom_th <- .FEAT[is.finite(tr_12m), {z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9); w<-exp(2*z); .(family=family, theta=w/sum(w))}, by=date]
val_th <- .FEAT[is.finite(vs_z),   {z<-(vs_z-mean(vs_z))/(sd(vs_z)+1e-9);     w<-exp(2*z); .(family=family, theta=w/sum(w))}, by=date]
mom_th[,date:=as.Date(date)]; val_th[,date:=as.Date(date)]

dates <- sort(unique(TH[[1]]$date))                    # 163 OOS months
# ---- per-learner realized active series (PIT: active[s] realized at s+1) ----
active_of <- function(th){
  a <- .active_series(.canon(.score_from_theta(th)))   # dt(date, active, ret_net)
  setkey(a,date); a
}
A <- lapply(TH, active_of)
A_mom <- active_of(mom_th); A_val <- active_of(val_th)

# active matrix aligned on `dates` for a given learner set
act_matrix <- function(Aset){
  M <- data.table(date=dates)
  for(nm in names(Aset)) M <- merge(M, Aset[[nm]][,.(date, a=active)][,setnames(.SD,"a",nm)], by="date", all.x=TRUE)
  M
}

# ---- annual-refit expanding IS meta-weights (softmax over trailing active Sharpe, gamma fixed) ----
# w_L held constant within calendar year; recomputed at first month of each year from active[date<anchor].
build_stack_theta <- function(THset, Aset, gamma=2, min_hist=24L, rule=c("softmax","winner")){
  rule <- match.arg(rule)
  M <- act_matrix(Aset); ln <- names(Aset); K <- length(ln)
  yrs <- as.integer(format(dates,"%Y"))
  anchors <- dates[!duplicated(yrs)]                    # first OOS month of each calendar year
  # weight per anchor
  W_anchor <- list()
  for(anc in as.character(anchors)){
    hist <- M[date < as.Date(anc)]
    if(nrow(hist) < min_hist){ W_anchor[[anc]] <- rep(1/K, K); next }
    sr <- sapply(ln, function(nm){ x<-hist[[nm]]; x<-x[is.finite(x)]; s<-sd(x)
      if(length(x)<min_hist || !is.finite(s) || s<=0) return(NA_real_); mean(x)/s*sqrt(12) })
    if(all(!is.finite(sr))){ W_anchor[[anc]] <- rep(1/K, K); next }
    sr[!is.finite(sr)] <- min(sr[is.finite(sr)], na.rm=TRUE)
    if(rule=="winner"){ w <- rep(0,K); w[which.max(sr)] <- 1 }
    else { e <- exp(gamma*(sr-max(sr))); w <- e/sum(e) }
    names(w) <- ln; W_anchor[[anc]] <- w
  }
  # map each month -> most recent anchor's weights, blend thetas
  out <- vector("list", length(dates))
  for(i in seq_along(dates)){
    t <- dates[i]; anc <- max(anchors[anchors<=t]); w <- W_anchor[[as.character(anc)]]
    blend <- NULL
    for(k in seq_along(ln)){
      thk <- THset[[ln[k]]][date==t, .(family, theta)]
      if(nrow(thk)==0) next
      thk[, theta := theta * w[k]]
      blend <- if(is.null(blend)) thk else rbind(blend, thk)
    }
    if(is.null(blend)) next
    b <- blend[, .(theta=sum(theta)), by=family]
    b[, theta := theta/sum(theta)]                      # renormalize (guards tiny numeric drift)
    out[[i]] <- data.table(date=t, family=b$family, theta=b$theta)
  }
  rbindlist(out)
}

# ---- 1) SPEC deliverable: logic_stack over 6 EN learners, softmax gamma=2, annual refit ----
theta_logic_stack <- build_stack_theta(TH, A, gamma=2, rule="softmax")
write_parquet(theta_logic_stack, file.path(OUT,"theta_R2_logic_stack.parquet"))

# ---- references (not the deliverable; for mechanism attribution) ----
# equal_stack = w=1/6 (the true equal-combine of the 6 logic thetas)
eq_theta <- rbindlist(lapply(dates, function(t){
  b <- rbindlist(lapply(learners, function(L) TH[[L]][date==t,.(family,theta)]))[, .(theta=sum(theta)/length(learners)), by=family]
  data.table(date=t, family=b$family, theta=b$theta/sum(b$theta))
}))
# winner-take-all variant (a-priori alt rule, reported for robustness only)
theta_winner <- build_stack_theta(TH, A, rule="winner")
# augmented: 6 EN + momentum + valuation  (honest test of path to beating momentum)
THa <- c(TH, list(mom=mom_th, val=val_th)); Aa <- c(A, list(mom=A_mom, val=A_val))
theta_aug <- build_stack_theta(THa, Aa, gamma=2, rule="softmax")
write_parquet(theta_aug, file.path(OUT,"theta_R2_logic_stack_aug.parquet"))

# ---- measure everything via canonical harness ----
r_ls  <- eval_theta(theta_logic_stack, "logic_stack")
r_eq  <- eval_theta(eq_theta,          "equal_stack")
r_win <- eval_theta(theta_winner,      "winner_stack")
r_aug <- eval_theta(theta_aug,         "logic_stack_aug")

pr <- function(r) cat(sprintf("%-16s port_t=%6.3f ew_uni_t=%6.3f oos_ret=%7.3f net_sr=%6.3f calmar=%5.3f turn=%6.2f paired_mom=%7.3f lag1_pt=%6.3f n=%d\n",
  r$label, r$port_t, r$ew_uni_t, r$oos_ret, r$net_sr, r$calmar, r$turnover, r$paired_vs_mom_t, r$lag1_port_t, r$n_months))
cat("\n=== R2 logic_stack results (baseline momentum port_t=1.277, paired ref) ===\n")
pr(r_ls); pr(r_eq); pr(r_win); pr(r_aug)

# annual meta-weights snapshot (transparency: what did the meta-learner pick?)
M <- act_matrix(A); yrs <- as.integer(format(dates,"%Y")); anchors <- dates[!duplicated(yrs)]
cat("\nlearner trailing IS active Sharpe at each annual anchor (drives softmax w):\n")
for(anc in as.character(anchors)){
  hist <- M[date < as.Date(anc)]
  sr <- sapply(learners, function(nm){ x<-hist[[nm]]; x<-x[is.finite(x)]; s<-sd(x); if(length(x)<24||!is.finite(s)||s<=0) return(NA); round(mean(x)/s*sqrt(12),2)})
  cat(sprintf("  %s (hist=%3d): %s\n", substr(anc,1,7), nrow(hist), paste(sprintf("%s=%s",substr(learners,1,2),sr), collapse=" ")))
}

saveRDS(list(logic_stack=r_ls, equal_stack=r_eq, winner_stack=r_win, logic_stack_aug=r_aug),
        file.path(OUT,"R2_logic_stack_results.rds"))
cat("\n[done] theta_R2_logic_stack.parquet written.\n")
