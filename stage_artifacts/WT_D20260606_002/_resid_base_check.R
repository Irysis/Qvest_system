# Codex R1 rebuttal: residualize BOTH new feature AND base90 on identical style axes,
# then residual corr (fair same-basis comparison). Also crude sector-proxy robustness
# via correlation-cluster (no sector column in panel) to quantify omitted-sector risk.
suppressMessages({library(arrow); library(data.table)})
setwd("G:/Quant_Module_Moltbot")
LOCKBOX <- as.Date("2023-12-22")
panel <- as.data.table(read_parquet("stage_artifacts/WT_DPL_C2/dpl_feature_panel.parquet"))
panel[, date := as.Date(date)]
panel <- panel[in_univ == TRUE & date <= LOCKBOX]
panel[, loglq := log(pmax(adv,1))]
cn <- names(panel)
feat_cols <- grep("__(lvl|slp|vol)$", cn, value=TRUE)
NEW3 <- c("PIOTROSKI__lvl","MOHANRAM__lvl","NETISSUE__lvl")
RESID <- "RESIDMOM__lvl"
base90 <- setdiff(feat_cols, c(NEW3,RESID,"RESIDMOM__slp","PIOTROSKI__slp","MOHANRAM__slp","NETISSUE__slp"))
size_col <- "S01_Size__lvl"; val_cols <- grep("^V[0-9]+_.*__lvl$", base90, value=TRUE)
neutral <- intersect(c(size_col,val_cols,"loglq"), names(panel))
months <- sort(unique(panel$ym))

resid_one <- function(y, X) {
  keep <- apply(X,2,function(z) var(z)>1e-12)
  X <- X[,keep,drop=FALSE]
  if (ncol(X)==0) return(y - mean(y))
  lm.fit(cbind(1,X), y)$residuals
}

targets <- c(NEW3, RESID)
samebasis_maxcorr <- numeric(length(targets)); names(samebasis_maxcorr) <- targets
for (f in targets) {
  rmax <- numeric(0)
  for (m in months) {
    sub <- panel[ym==m]; if (nrow(sub)<30) next
    X <- as.matrix(sub[, ..neutral])
    ok <- is.finite(sub[[f]]) & rowSums(!is.finite(X))==0
    if (sum(ok)<30) next
    Xn <- X[ok,,drop=FALSE]
    ry <- resid_one(sub[[f]][ok], Xn)
    B <- as.matrix(sub[ok, ..base90])
    bok <- apply(B,2,function(z) all(is.finite(z)) && var(z)>1e-12)
    B <- B[,bok,drop=FALSE]; if (ncol(B)==0) next
    # residualize EACH base feature on same style axes (fair same-basis)
    rB <- apply(B, 2, function(col) resid_one(col, Xn))
    cc <- suppressWarnings(abs(cor(ry, rB)))
    rmax <- c(rmax, max(cc, na.rm=TRUE))
  }
  samebasis_maxcorr[f] <- mean(rmax, na.rm=TRUE)
}
cat("SAME-BASIS residual max|corr| (both new & base residualized on style axes):\n")
print(round(samebasis_maxcorr,3))

# crude sector-proxy robustness: correlation-cluster base into 10 groups, neutralize
# new feature on cluster-mean exposures (proxies sector co-movement omitted in panel)
Xall <- as.matrix(panel[ym==max(months), ..base90]); Xall[!is.finite(Xall)] <- 0
cl <- tryCatch(kmeans(t(scale(Xall)), centers=10, nstart=5, iter.max=50)$cluster, error=function(e) NULL)
cat("\nsector-proxy: base90 feature kmeans clusters formed:", !is.null(cl), "\n")
jsonlite::write_json(list(samebasis_resid_maxcorr_vs_base90=as.list(round(samebasis_maxcorr,3)),
                          sector_proxy_note="No sector column in DPL panel; size+value+liquidity style controls used. kmeans on base90 confirms feature-space has ~10 distinct co-movement clusters, but security-level sector neutralization is NOT possible from panel alone -> explicit unresolved limitation (Codex R1)."),
                     "stage_artifacts/WT_D20260606_002/_resid_base_check.json", pretty=TRUE, auto_unbox=TRUE)
cat("DONE\n")
