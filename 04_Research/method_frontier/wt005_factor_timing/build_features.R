# WT-D20260718_005 — Family valuation/momentum feature panel (PIT).
# Per (Date t, family k):  trailing own-portfolio returns (realized < t, lagged),
#   valuation_spread (cheapness of family's favored basket at t, from factor_db@t),
#   trailing vol.  Target = forward family return (realized t..t+1) for transformer.
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(root)
OUT <- "04_Research/method_frontier/wt005_factor_timing"
fams <- c("value","quality","momentum","low_vol","size","dividend")

FAM <- as.data.table(read_parquet(file.path(OUT,"family_z_panel.parquet"))); FAM[, Date:=as.Date(Date)]
so  <- readRDS(file.path(OUT,"static_oracle.rds"))
per_fam_pr <- so$per_fam_pr   # list fk -> data.table(date, ret_net) forward-realized labeled at sig_date

# ---- factor forward returns matrix (labeled at sig_date = realized over (t, t+1]) ----
# per_fam_pr[[fk]] columns already (date, <fk>) — see static_oracle.rds
FR <- Reduce(function(a,b) merge(a,b,by="date",all=TRUE), lapply(fams, function(fk){
  x <- copy(per_fam_pr[[fk]]); setnames(x, setdiff(names(x),"date"), fk); x }))
setorder(FR, date)
dts <- FR$date

# ---- trailing (lagged) return features: known at t = returns labeled < t ----
lagsum <- function(v, k){ # sum of previous k labeled returns (shift by 1 so t uses <t)
  out <- rep(NA_real_, length(v))
  for(i in seq_along(v)){ lo <- i-k; hi <- i-1; if(lo>=1 && hi>=1) out[i] <- sum(v[lo:hi], na.rm=FALSE) }
  out
}
lagsd <- function(v,k){ out<-rep(NA_real_,length(v)); for(i in seq_along(v)){ lo<-i-k; hi<-i-1; if(lo>=1&&hi>=1) out[i]<-sd(v[lo:hi]) }; out }

feat_list <- list()
for(fk in fams){
  v <- FR[[fk]]
  feat_list[[fk]] <- data.table(date=dts, family=fk,
    fwd_ret = v,                      # TARGET (realized t..t+1) — never an input
    tr_1m = shift(v,1), tr_3m = lagsum(v,3), tr_6m = lagsum(v,6), tr_12m = lagsum(v,12),
    tr_vol12 = lagsd(v,12))
}
FEAT <- rbindlist(feat_list)

# ---- valuation spread: cheapness of family k's favored basket at t (PIT: factor_db@t) ----
# for each Date, family k: top vs bottom tercile by z_k, mean z_value gap (higher=family favors cheap stocks)
vs_list <- list()
for(d in as.character(unique(FAM$Date))){
  sub <- FAM[Date==as.Date(d)]
  if(nrow(sub)<30) next
  zval <- sub[["value"]]
  for(fk in fams){
    zk <- sub[[fk]]; ok <- is.finite(zk) & is.finite(zval)
    if(sum(ok)<30){ vs_list[[paste(d,fk)]] <- data.table(date=as.Date(d),family=fk,val_spread=NA_real_); next }
    zk2<-zk[ok]; zv2<-zval[ok]
    qs <- quantile(zk2, c(1/3,2/3), na.rm=TRUE)
    top <- zv2[zk2>=qs[2]]; bot <- zv2[zk2<=qs[1]]
    vs_list[[paste(d,fk)]] <- data.table(date=as.Date(d),family=fk,val_spread=mean(top)-mean(bot))
  }
}
VS <- rbindlist(vs_list)
FEAT <- merge(FEAT, VS, by=c("date","family"), all.x=TRUE)
# valuation momentum: change in val_spread vs its trailing mean (mean-reversion signal, Arnott)
setorder(FEAT, family, date)
FEAT[, vs_z := (val_spread - frollmean(val_spread, 36, align="right", na.rm=TRUE)) /
                frollapply(val_spread, 36, sd, align="right"), by=family]

write_parquet(FEAT, file.path(OUT,"family_feature_panel.parquet"))
cat("FEAT rows",nrow(FEAT)," dates",uniqueN(FEAT$date)," families",uniqueN(FEAT$family),"\n")
cat("val_spread NA rate", round(mean(is.na(FEAT$val_spread)),3),
    " tr_12m NA", round(mean(is.na(FEAT$tr_12m)),3), " vs_z NA", round(mean(is.na(FEAT$vs_z)),3), "\n")
print(FEAT[family=="value"][sample(.N,4)])
