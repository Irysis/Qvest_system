# WT-006 R2 lane: interaction_en — conditional-momentum Elastic Net.
# Hypothesis: single-logic EN failed because momentum's PREDICTIVE SLOPE on fwd_ret is
# regime-conditional. Keep momentum main effects as backbone, add explicit interactions of the
# family's OWN momentum signal with (a) its own valuation z / vol, (b) market-wide dispersion /
# credit / stress. EN (past-only) selects which conditioners actually modulate momentum.
# PIT: theta(t) uses features observable at t; trained on rows date<t (fwd_ret realized by t);
#      expanding window, annual refit; IS-only lambda (inner CV on train); train-only standardization.
suppressMessages({library(data.table); library(arrow); library(glmnet)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
W5  <- "04_Research/method_frontier/wt005_factor_timing"
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- c("value","quality","momentum","low_vol","size","dividend")
set.seed(42)

X <- as.data.table(read_parquet(file.path(OUT,"wt006_candidate_features.parquet"))); X[,date:=as.Date(date)]
oos_dates <- sort(unique(as.Date(read_parquet(file.path(W5,"theta_transformer_ensemble.parquet"))$date)))
cat("OOS:", as.character(min(oos_dates)),"..",as.character(max(oos_dates))," n=",length(oos_dates),"\n")

# ---- feature roster (all low-NA; exclude US HY/BBB @86% NA) ----
mom_main  <- c("tr_1m","tr_3m","tr_6m","tr_12m","complex_mom12","rel_rank12")     # momentum backbone
val_main  <- c("vs_z","val_spread")                                              # valuation
risk_main <- c("tr_vol12","tr_downdev12")                                        # own risk
main_feats <- c(mom_main, val_main, risk_main)

# interaction pairs: (momentum-signal) x (conditioner). own = family-specific, mkt = invariant.
inter_pairs <- list(
  # momentum conditioned on own valuation (mom works less when family already expensive/cheap)
  c("tr_12m","vs_z"), c("tr_6m","vs_z"), c("complex_mom12","vs_z"),
  # momentum conditioned on own risk
  c("tr_12m","tr_vol12"), c("tr_12m","tr_downdev12"),
  # momentum conditioned on market dispersion / co-movement (momentum crash regime)
  c("tr_12m","disp_ret12"), c("tr_6m","disp_ret12"), c("tr_12m","avg_corr24"),
  # momentum conditioned on credit / financial stress
  c("tr_12m","cs_bbb"), c("tr_12m","StL_Fin_Stress"), c("tr_12m","VIX"), c("tr_12m","term"),
  # valuation conditioned on dispersion / credit
  c("vs_z","disp_ret12"), c("vs_z","cs_bbb"), c("val_spread","disp_ret12")
)
base_used <- unique(c(main_feats, unlist(inter_pairs)))
cat("main:", length(main_feats), " interactions:", length(inter_pairs),
    " base feats:", length(base_used), "\n")

# ---- design builder: family FE (unpenalized) + main (penalized) + interactions (penalized) ----
build_design <- function(df){
  FMAT <- model.matrix(~ family - 1, data=df)              # 6 family dummies (intercept surrogate)
  cols <- list(FMAT); pf <- rep(0, ncol(FMAT))             # penalty.factor 0 = unpenalized FE
  nm   <- colnames(FMAT)
  for(f in main_feats){ cols[[length(cols)+1]] <- matrix(df[[f]],ncol=1); pf<-c(pf,1); nm<-c(nm,f) }
  for(pr in inter_pairs){
    v <- df[[pr[1]]]*df[[pr[2]]]
    cols[[length(cols)+1]] <- matrix(v,ncol=1); pf<-c(pf,1); nm<-c(nm, paste0(pr[1],"_x_",pr[2]))
  }
  Xm <- do.call(cbind, cols); colnames(Xm) <- nm
  list(x=Xm, pf=pf)
}

# ---- walk-forward EN: returns data.table(date, family, pred) ----
need <- c("date","family","fwd_ret", base_used)
D <- X[, ..need]
wf_forecast <- function(alpha=0.5, refit_every=12L){
  preds <- vector("list", length(oos_dates))
  fit <- NULL; anchor <- NULL; sc <- NULL; refit_count <- 0L; nz_track <- list()
  for(i in seq_along(oos_dates)){
    t <- oos_dates[i]
    do_refit <- is.null(fit) || (as.integer(round(difftime(t, anchor, units="days")/30.4)) >= refit_every)
    tr <- D[date < t]; tr <- tr[complete.cases(tr[, c("fwd_ret", base_used), with=FALSE])]
    if(nrow(tr) < 120) next
    if(do_refit){
      des <- build_design(tr); xmat <- des$x; y <- tr$fwd_ret
      pen <- des$pf==1
      ctr <- colMeans(xmat); csd <- apply(xmat,2,sd); csd[csd<=0|!is.finite(csd)] <- 1
      xs <- xmat; xs[,pen] <- scale(xmat[,pen], center=ctr[pen], scale=csd[pen]); xs[!is.finite(xs)] <- 0
      cvf <- tryCatch(cv.glmnet(xs, y, alpha=alpha, penalty.factor=des$pf, nfolds=5, standardize=FALSE),
                      error=function(e) NULL)
      if(is.null(cvf)) next
      fit <- cvf; anchor <- t; sc <- list(ctr=ctr, csd=csd, pen=pen, cols=colnames(xmat))
      refit_count <- refit_count + 1L
      co <- as.matrix(coef(cvf, s="lambda.min")); nz <- rownames(co)[which(co[,1]!=0)]
      nz_track[[as.character(t)]] <- setdiff(nz, c("(Intercept)", paste0("family",fams)))
    }
    te <- D[date==t & family %in% fams]
    te <- te[complete.cases(te[, base_used, with=FALSE])]
    if(nrow(te)==0) next
    xt <- build_design(te)$x
    miss <- setdiff(sc$cols, colnames(xt)); for(m in miss) xt <- cbind(xt, setNames(matrix(0,nrow(xt),1),m))
    xt <- xt[, sc$cols, drop=FALSE]
    xt[, sc$pen] <- scale(xt[, sc$pen], center=sc$ctr[sc$pen], scale=sc$csd[sc$pen]); xt[!is.finite(xt)] <- 0
    ph <- as.numeric(predict(fit, newx=xt, s="lambda.min"))
    preds[[i]] <- data.table(date=t, family=te$family, pred=ph)
  }
  P <- rbindlist(preds); attr(P,"refit_count") <- refit_count; attr(P,"nz_track") <- nz_track; P
}

pred_to_theta <- function(P, beta=2){                      # softmax beta=2 (== momentum baseline, no OOS tune)
  P[is.finite(pred), {z<-(pred-mean(pred))/(sd(pred)+1e-9); w<-exp(beta*z); .(family=family, theta=w/sum(w))}, by=date]
}

P  <- wf_forecast(alpha=0.5, refit_every=12L)
th <- pred_to_theta(P, beta=2)
write_parquet(th, file.path(OUT,"theta_R2_interaction_en.parquet"))
nzt <- attr(P,"nz_track"); tabnz <- sort(table(unlist(nzt)), decreasing=TRUE)
cat(sprintf("[interaction_en] refits=%d oos_mo=%d\n", attr(P,"refit_count"), uniqueN(th$date)))
cat("top selected features (freq across refits):\n")
print(head(tabnz, 15))
saveRDS(list(refits=attr(P,"refit_count"), top=head(as.data.frame(tabnz),15)),
        file.path(OUT,"R2_interaction_en_selected.rds"))
cat("[done] theta_R2_interaction_en.parquet written\n")
