# PIT-safe regime correlation (Codex C4/C9 fix): t-1 expanding-window percentile
# cutoffs (NO full-sample quantile). Report switch rate. Include CAUTION band.
suppressMessages({ library(data.table); library(arrow) })
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260614_002"
panel <- as.data.table(read_parquet(file.path(OUT,"_factor_return_panel.parquet"))); setorder(panel, ym)
STYLE <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
           "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date=as.Date(Date), BM_Ret)]
bm[, ym := format(Date,"%Y%m")]
bmm <- bm[, .(bm_ret = prod(1+BM_Ret,na.rm=TRUE)-1), by=ym]
P <- merge(panel, bmm, by="ym"); setorder(P, ym)

# PIT regime label: use EXPANDING window of bm_ret up to t-1 to set quartile cutoffs,
# then classify month t's bm_ret. 4 regimes incl CAUTION.
n <- nrow(P); reg <- rep(NA_character_, n)
MINW <- 36L  # need history to form percentiles
for (t in seq_len(n)) {
  if (t <= MINW) { reg[t] <- "WARMUP"; next }
  hist <- P$bm_ret[1:(t-1)]                       # strictly past (t-1), expanding
  q <- quantile(hist, c(0.20, 0.40, 0.80), na.rm=TRUE)
  x <- P$bm_ret[t]
  reg[t] <- if (x <= q[1]) "CRISIS" else if (x <= q[2]) "CAUTION" else if (x >= q[3]) "BULL" else "NORMAL"
}
P[, regime := reg]
# switch rate (estimated): fraction of months where regime changes from prior
Pv <- P[regime != "WARMUP"]
switch_rate <- mean(Pv$regime[-1] != Pv$regime[-nrow(Pv)])

reg_cor <- rbindlist(lapply(c("CRISIS","CAUTION","NORMAL","BULL","ALL"), function(rg){
  sub <- if(rg=="ALL") Pv else Pv[regime==rg]
  if(nrow(sub) < 6) return(data.table(regime=rg, n_months=nrow(sub), mean_pair_corr=NA,
                                        max_pair_corr=NA, mom_block_corr=NA, small_sample=TRUE))
  M<-as.matrix(sub[,..STYLE]); M<-M[,colSums(is.finite(M))>5,drop=FALSE]
  C<-suppressWarnings(cor(M,use="pairwise.complete.obs")); off<-C[upper.tri(C)]
  momf<-intersect(c("M01_Mom_12_1","M05_Trended_Mom","M07_IndMom"), colnames(C))
  mb<-if(length(momf)>=2) mean(C[momf,momf][upper.tri(diag(length(momf)))],na.rm=TRUE) else NA
  data.table(regime=rg, n_months=nrow(sub), mean_pair_corr=mean(off,na.rm=TRUE),
             max_pair_corr=max(off,na.rm=TRUE), mom_block_corr=mb, small_sample=nrow(sub)<30)
}))
write_parquet(reg_cor, file.path(OUT,"regime_correlation.parquet"))
saveRDS(list(reg_cor=reg_cor, switch_rate=switch_rate,
             regime_n=table(Pv$regime)),
        file.path(OUT,"_risk_regime.rds"))
cat("[regime PIT] switch_rate (estimated):", round(switch_rate,4), "\n")
cat("[regime PIT] regime n:\n"); print(table(Pv$regime))
print(reg_cor)
