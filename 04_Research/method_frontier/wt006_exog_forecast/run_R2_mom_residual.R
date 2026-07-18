# WT-006 R2 lane = mom_residual — momentum-anchored residual correction.
# THESIS: factor_momentum (softmax over cross-family z of tr_12m, beta=2) is the winner baseline (port_t~1.277).
#   Do NOT throw it away. Start FROM it, and add a correction only where momentum systematically MISSES.
#   residual(t,f) = fwd_ret(t,f) - [a + b*tr_12m(t,f)]   (pooled OLS on TRAIN ONLY, refit annually)
#   Predict residual with EXOGENOUS, non-momentum features (crowding/dispersion/funding/crashrisk/macro + tr_1m reversal).
#   Combined score = z(tr_12m) + kappa * z(r_hat) ; theta = softmax(2*score).
#   kappa = IS-adaptive: max(0, train inner-CV corr(r_hat,residual)) * K0  -> if residual model has no TRAIN skill, kappa~0
#           => collapses to exact momentum baseline (can't do much worse than the winner). Pure chain, IS-only, no OOS peek.
# PIT: theta(date=t) uses ONLY features observable at t and residuals from months < t. fwd_ret(t) NEVER a feature.
#      Standardization on train only. Expanding window, annual refit. Softmax temperature FIXED=2 (== momentum, no OOS tune).
suppressMessages({library(data.table); library(arrow); library(glmnet)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
W5  <- "04_Research/method_frontier/wt005_factor_timing"
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- c("value","quality","momentum","low_vol","size","dividend")
set.seed(42)

X <- as.data.table(read_parquet(file.path(OUT,"wt006_candidate_features.parquet"))); X[,date:=as.Date(date)]
logic_map <- jsonlite::fromJSON(file.path(OUT,"logic_map.json"))

# --- feature set for the RESIDUAL model: exogenous + short reversal, EXCLUDE momentum family (already in anchor) ---
mom_cols <- c("tr_12m","tr_3m","tr_6m","complex_mom12","rel_rank12")  # captured by momentum anchor -> exclude from residual
exog_all <- setdiff(unlist(logic_map, use.names=FALSE), mom_cols)
exog_all <- union(exog_all, "tr_1m")  # 1m reversal = orthogonal-to-12m-momentum signal
# drop high-NA (same 30% rule as R1)
exog <- exog_all[ sapply(exog_all, function(c) c %in% names(X) && mean(is.na(X[[c]])) <= 0.30) ]
cat("residual features (", length(exog), "):", paste(exog, collapse=" "), "\n")

# family-invariant feats -> interact with family so macro/funding can drive family-specific rotation
is_invariant <- function(f){ v <- X[, .(u=uniqueN(get(f))), by=date]; mean(v$u==1, na.rm=TRUE) > 0.95 }
inv_flag <- sapply(exog, is_invariant)
cat("family-invariant (interacted):", paste(names(inv_flag)[inv_flag], collapse=" "), "\n")

oos_dates <- sort(unique(as.Date(read_parquet(file.path(W5,"theta_transformer_ensemble.parquet"))$date)))
cat("OOS:", as.character(min(oos_dates)),"..",as.character(max(oos_dates))," n=",length(oos_dates),"\n\n")

build_design <- function(df, feats){
  FMAT <- model.matrix(~ family - 1, data=df)
  cols <- list(FMAT); pf <- rep(0, ncol(FMAT))
  for(f in feats){
    x <- df[[f]]
    if(isTRUE(inv_flag[[f]])){
      M <- FMAT * x; colnames(M) <- paste0(f,"_x_",gsub("family","",colnames(FMAT)))
      cols[[length(cols)+1]] <- M; pf <- c(pf, rep(1, ncol(M)))
    } else {
      cols[[length(cols)+1]] <- matrix(x, ncol=1, dimnames=list(NULL,f)); pf <- c(pf,1)
    }
  }
  list(x=do.call(cbind, cols), pf=pf)
}

K0 <- 3.0  # a-priori max residual-tilt gain; actual kappa scaled down by TRAIN skill (IS-only, no OOS tune)
refit_every <- 12L

run_mom_residual <- function(){
  need <- c("date","family","fwd_ret","tr_12m", exog)
  D <- X[, ..need]
  out <- vector("list", length(oos_dates))
  fit <- NULL; anchor <- NULL; sc <- NULL; momfit <- NULL; kappa <- 0; diag <- list()
  nref <- 0L
  for(i in seq_along(oos_dates)){
    t <- oos_dates[i]
    do_refit <- is.null(fit) || is.null(anchor) ||
                (as.integer(round(difftime(t, anchor, units="days")/30.4)) >= refit_every)
    tr <- D[date < t]
    if(do_refit){
      # 1) momentum OLS on train (pooled) -> fitted momentum return + residual target
      trm <- tr[is.finite(fwd_ret) & is.finite(tr_12m)]
      if(nrow(trm) < 60){ next }
      mf <- lm(fwd_ret ~ tr_12m, data=trm); momfit <- coef(mf)
      # residual on train complete-cases over exog
      trr <- tr[complete.cases(tr[, c("fwd_ret","tr_12m", exog), with=FALSE])]
      if(nrow(trr) < 60){ next }
      resid <- trr$fwd_ret - (momfit[1] + momfit[2]*trr$tr_12m)
      des <- build_design(trr, exog); xmat <- des$x
      ctr <- colMeans(xmat); csd <- apply(xmat,2,sd); csd[csd<=0|!is.finite(csd)] <- 1
      pen <- des$pf==1; xs <- xmat; xs[,pen] <- scale(xmat[,pen], center=ctr[pen], scale=csd[pen]); xs[!is.finite(xs)] <- 0
      cvf <- tryCatch(cv.glmnet(xs, resid, alpha=0.5, penalty.factor=des$pf, nfolds=5, standardize=FALSE),
                      error=function(e) NULL)
      if(is.null(cvf)){ next }
      # IS-adaptive kappa = max(0, corr(train r_hat, residual)) * K0  (TRAIN skill only)
      rhat_tr <- as.numeric(predict(cvf, newx=xs, s="lambda.min"))
      rho <- suppressWarnings(cor(rhat_tr, resid)); if(!is.finite(rho)) rho <- 0
      kappa <- max(0, rho) * K0
      fit <- cvf; anchor <- t; sc <- list(ctr=ctr,csd=csd,pen=pen,cols=colnames(xmat)); nref <- nref+1L
      diag[[as.character(t)]] <- list(rho=round(rho,3), kappa=round(kappa,3), n_tr=nrow(trr))
    }
    te <- D[date==t & family %in% fams]; if(nrow(te)==0) next
    if(!all(is.finite(te$tr_12m))) next
    # anchor score
    zmom <- as.numeric(scale(te$tr_12m))
    # residual prediction (exog); if any exog NA at t, that col contributes 0 after scaling->finite
    des_te <- build_design(te, exog); xt <- des_te$x
    miss <- setdiff(sc$cols, colnames(xt)); for(m in miss) xt <- cbind(xt, setNames(matrix(0,nrow(xt),1),m))
    xt <- xt[, sc$cols, drop=FALSE]
    xt[, sc$pen] <- scale(xt[, sc$pen], center=sc$ctr[sc$pen], scale=sc$csd[sc$pen]); xt[!is.finite(xt)] <- 0
    rhat <- as.numeric(predict(fit, newx=xt, s="lambda.min"))
    zres <- if(sd(rhat) > 0) as.numeric(scale(rhat)) else rep(0, length(rhat))
    score <- zmom + kappa * zres
    w <- exp(2 * (score - mean(score))); w <- w/sum(w)
    out[[i]] <- data.table(date=t, family=te$family, theta=w)
  }
  P <- rbindlist(out); attr(P,"nref") <- nref; attr(P,"diag") <- diag; P
}

TH <- run_mom_residual()
stopifnot(nrow(TH) > 0)
# sanity: theta>=0, sum=1 per date
chk <- TH[, .(s=sum(theta), mn=min(theta)), by=date]
cat(sprintf("theta sanity: sum range [%.4f, %.4f], min theta %.4f, n_dates=%d, refits=%d\n",
            min(chk$s), max(chk$s), min(chk$mn), uniqueN(TH$date), attr(TH,"nref")))
write_parquet(TH[, .(date, family, theta)], file.path(OUT,"theta_R2_mom_residual.parquet"))
# kappa path (audit)
dg <- attr(TH,"diag")
kp <- rbindlist(lapply(names(dg), function(d) data.table(date=d, rho=dg[[d]]$rho, kappa=dg[[d]]$kappa, n_tr=dg[[d]]$n_tr)))
fwrite(kp, file.path(OUT,"R2_mom_residual_kappa_path.csv"))
cat("kappa path (refit anchors):\n"); print(kp)
cat("\n[mom_residual] theta written -> theta_R2_mom_residual.parquet\n")
