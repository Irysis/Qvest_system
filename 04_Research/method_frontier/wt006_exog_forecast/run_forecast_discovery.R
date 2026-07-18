# WT-D20260718_006 — Direct E[r_factor,t+1] forecasting via ML combination discovery.
# 6 economic-logic backbones + combined. Walk-forward expanding refit (12mo), TRAIN-ONLY standardization,
# elastic-net (glmnet, alpha=0.5) sparse combo selection. Family main-effects unpenalized; family-invariant
# exogenous features interacted with family so macro/funding/dispersion can drive ROTATION (family-specific slope).
# IS-only selection (lambda by inner CV on train). beta temperature FIXED=2 (== momentum baseline, no OOS tuning).
# OUTPUT: per-strategy theta parquet (family weights per OOS month) for canonical A/B eval.
suppressMessages({library(data.table); library(arrow); library(glmnet)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=root); setwd(root)
W5  <- "04_Research/method_frontier/wt005_factor_timing"
OUT <- "04_Research/method_frontier/wt006_exog_forecast"
fams <- c("value","quality","momentum","low_vol","size","dividend")
set.seed(42)

X <- as.data.table(read_parquet(file.path(OUT,"wt006_candidate_features.parquet"))); X[,date:=as.Date(date)]
logic_map <- jsonlite::fromJSON(file.path(OUT,"logic_map.json"))
# drop features with high NA (US HY/BBB sparse)
allf0 <- unlist(logic_map, use.names=FALSE)
keep_f <- allf0[ sapply(allf0, function(c) mean(is.na(X[[c]]))) <= 0.30 ]
logic_map <- lapply(logic_map, function(v) intersect(v, keep_f))
logic_map <- logic_map[sapply(logic_map, length) > 0]
cat("logics:", paste(names(logic_map), collapse=", "), "\n")
for(L in names(logic_map)) cat("  ", L, ":", paste(logic_map[[L]], collapse=" "), "\n")

# family-invariant vs family-specific features (invariant get x family interaction)
is_invariant <- function(f){ v <- X[, .(u=uniqueN(get(f))), by=date]; mean(v$u==1, na.rm=TRUE) > 0.95 }
inv_flag <- sapply(unique(keep_f), is_invariant)
cat("\nfamily-invariant features (interacted w/ family):", paste(names(inv_flag)[inv_flag], collapse=" "), "\n")

# OOS window = WT-005 transformer test months (identical, for comparability)
oos_dates <- sort(unique(as.Date(read_parquet(file.path(W5,"theta_transformer_ensemble.parquet"))$date)))
cat("OOS:", as.character(min(oos_dates)),"..",as.character(max(oos_dates))," n=",length(oos_dates),"\n\n")

# ---- design matrix builder: family FE (unpenalized) + feats (family-invariant -> x family) ----
build_design <- function(df, feats){
  fml <- intersect(feats, names(df))
  # family dummies
  FMAT <- model.matrix(~ family - 1, data=df)          # 6 cols, unpenalized
  cols <- list(FMAT); pf <- rep(0, ncol(FMAT))         # penalty.factor 0 for family FE
  for(f in fml){
    x <- df[[f]]
    if(isTRUE(inv_flag[[f]])){                          # invariant -> interact w/ family (family-specific slope)
      M <- FMAT * x                                     # each family col * feature value
      colnames(M) <- paste0(f, "_x_", gsub("family","",colnames(FMAT)))
      cols[[length(cols)+1]] <- M; pf <- c(pf, rep(1, ncol(M)))
    } else {                                            # family-specific feature -> main effect
      cols[[length(cols)+1]] <- matrix(x, ncol=1, dimnames=list(NULL,f)); pf <- c(pf,1)
    }
  }
  Xm <- do.call(cbind, cols)
  list(x=Xm, pf=pf)
}

# ---- walk-forward EN forecasting: returns data.table(date, family, pred) on OOS dates ----
wf_forecast <- function(feats, alpha=0.5, refit_every=12L, label=""){
  fml <- intersect(feats, names(X))
  # complete-case on used feats + target for training
  need <- c("date","family","fwd_ret", fml)
  D <- X[, ..need]
  preds <- vector("list", length(oos_dates))
  last_fit <- NULL; last_anchor <- NULL; last_scale <- NULL; nz_last <- NULL
  refit_count <- 0L; nz_track <- list()
  for(i in seq_along(oos_dates)){
    t <- oos_dates[i]
    do_refit <- is.null(last_fit) || is.null(last_anchor) ||
                (as.integer(round(difftime(t, last_anchor, units="days")/30.4)) >= refit_every)
    tr <- D[date < t]
    tr <- tr[complete.cases(tr[, c("fwd_ret", fml), with=FALSE])]
    if(nrow(tr) < 60){ next }
    if(do_refit){
      des <- build_design(tr, fml)
      xmat <- des$x; y <- tr$fwd_ret
      # train-only standardization of penalized cols (family FE cols left as 0/1)
      ctr <- colMeans(xmat); csd <- apply(xmat,2,sd); csd[csd<=0|!is.finite(csd)] <- 1
      pen <- des$pf==1
      xs <- xmat; xs[,pen] <- scale(xmat[,pen], center=ctr[pen], scale=csd[pen])
      xs[!is.finite(xs)] <- 0
      cvf <- tryCatch(cv.glmnet(xs, y, alpha=alpha, penalty.factor=des$pf, nfolds=5, standardize=FALSE),
                      error=function(e) NULL)
      if(is.null(cvf)){ next }
      last_fit <- cvf; last_anchor <- t
      last_scale <- list(ctr=ctr, csd=csd, pen=pen, cols=colnames(xmat), feats=fml)
      refit_count <- refit_count + 1L
      co <- as.matrix(coef(cvf, s="lambda.min")); nz <- rownames(co)[which(co[,1]!=0)]
      nz_track[[as.character(t)]] <- setdiff(nz, c("(Intercept)", paste0("family",fams)))
    }
    te <- D[date==t]; te <- te[family %in% fams]
    if(nrow(te)==0) next
    des_te <- build_design(te, last_scale$feats)
    xt <- des_te$x
    # align columns to training design
    miss <- setdiff(last_scale$cols, colnames(xt)); for(m in miss) xt <- cbind(xt, setNames(matrix(0,nrow(xt),1),m))
    xt <- xt[, last_scale$cols, drop=FALSE]
    xt[, last_scale$pen] <- scale(xt[, last_scale$pen], center=last_scale$ctr[last_scale$pen], scale=last_scale$csd[last_scale$pen])
    xt[!is.finite(xt)] <- 0
    ph <- as.numeric(predict(last_fit, newx=xt, s="lambda.min"))
    preds[[i]] <- data.table(date=t, family=te$family, pred=ph)
  }
  P <- rbindlist(preds)
  attr(P,"refit_count") <- refit_count; attr(P,"nz_track") <- nz_track
  P
}

# ---- convert per-family predictions -> theta (softmax beta=2 over cross-family z of pred) ----
pred_to_theta <- function(P, beta=2){
  P[is.finite(pred), {z<-(pred-mean(pred))/(sd(pred)+1e-9); w<-exp(beta*z); .(family=family, theta=w/sum(w))}, by=date]
}

configs <- c(list(combined=unlist(logic_map,use.names=FALSE)), logic_map)
summary_nz <- list()
for(cn in names(configs)){
  P <- wf_forecast(configs[[cn]], alpha=0.5, label=cn)
  th <- pred_to_theta(P, beta=2)
  write_parquet(th, file.path(OUT, paste0("theta_EN_", cn, ".parquet")))
  # record discovered combo = union of nonzero features across refits (freq)
  nzt <- attr(P,"nz_track"); allnz <- unlist(nzt); tabnz <- sort(table(allnz), decreasing=TRUE)
  summary_nz[[cn]] <- list(refits=attr(P,"refit_count"), n_oos=uniqueN(th$date),
                           top_selected=head(names(tabnz),12), sel_freq=as.integer(head(tabnz,12)))
  cat(sprintf("[EN %-14s] refits=%d oos_mo=%d  top: %s\n", cn, attr(P,"refit_count"), uniqueN(th$date),
              paste(head(names(tabnz),6), collapse=", ")))
}
jsonlite::write_json(summary_nz, file.path(OUT,"en_selected_combos.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n[done] EN theta written for:", paste(names(configs), collapse=", "), "\n")
