# finalize_alpha.R — WT-D20260710_002
# Advisory rank-IC for finalists + latest-month alpha_vector for strongest EW-survivor (V02_EP).
# Writes alpha_scores.parquet + rank-IC advisory JSON. (validation/package JSON assembled after.)

suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
P   <- file.path(ROOT, "stage_artifacts/WT-D20260710_002/panel")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260710_002")

feat <- as.data.table(read_parquet(file.path(P,"features_monthly.parquet"))); feat[, Date:=as.Date(Date)]
ret  <- as.data.table(read_parquet(file.path(P,"returns_monthly.parquet")))[, .(Date=as.Date(Date), Ticker, Ret_1m)]
feat <- merge(feat, ret[, .(Date,Ticker)], by=c("Date","Ticker"))   # universe restriction (same as measure)

FEATURES <- c("V02_EP","V12_Composite_Value","V10_FCF_Yield","Q01_GPA","Q08_Composite_Quality",
              "M08_Residual_Mom","M09_Composite_Mom","R12_Idiosyncratic_Risk")

nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  f<-lm(x~1); as.numeric(lmtest::coeftest(f, vcov=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]) }

# advisory rank-IC (Spearman score vs forward Ret_1m), per month
adv <- list()
for (fac in FEATURES) {
  m <- merge(feat[!is.na(get(fac)), .(Date,Ticker, score=get(fac))], ret, by=c("Date","Ticker"))
  ic <- m[, .(ic = if(.N>=10) cor(score, Ret_1m, method="spearman") else NA_real_), by=Date][!is.na(ic)]
  adv[[fac]] <- list(
    factor=fac, rank_ic=mean(ic$ic), icir=mean(ic$ic)/sd(ic$ic),
    ic_t_nw_lag3=nw_t(ic$ic), n_months_ic=nrow(ic),
    hit_rate=mean(ic$ic>0)
  )
  cat(sprintf("%-24s rank_IC=%+.4f ICIR=%+.3f IC_t=%+.2f hit=%.2f\n",
      fac, adv[[fac]]$rank_ic, adv[[fac]]$icir, adv[[fac]]$ic_t_nw_lag3, adv[[fac]]$hit_rate))
}
write_json(adv, file.path(OUT,"advisory_rankic.json"), pretty=TRUE, auto_unbox=TRUE, na="null")

# ---- latest-month alpha_vector for V02_EP (strongest EW-survivor) ----
last_m <- max(feat$Date)
cat("\n[finalize] latest signal month:", as.character(last_m), "\n")
# IS pooled slope: Ret_1m ~ z (calibration scale, IS-only). cap-w is authority; magnitude non-load-bearing.
mm <- merge(feat[!is.na(V02_EP), .(Date,Ticker,z=V02_EP)], ret, by=c("Date","Ticker"))
slope <- as.numeric(coef(lm(Ret_1m ~ z, data=mm))["z"])
cat("[finalize] IS pooled slope (Ret_1m ~ V02_EP z) =", round(slope,5), "\n")

lastf <- feat[Date==last_m & !is.na(V02_EP), .(Ticker, z_V02_EP=V02_EP,
                                               z_V10_FCF=V10_FCF_Yield)]
lastf[, expected_active_1m := slope * z_V02_EP]
# confidence: rank-stability proxy in [0,1] from |z| percentile (higher |z| = more confident direction)
lastf[, confidence := pmin(1, pmax(0, 0.4 + 0.5*(frank(abs(z_V02_EP))/.N)))]
setorder(lastf, -z_V02_EP)
write_parquet(lastf, file.path(OUT,"alpha_scores.parquet"))
cat(sprintf("[finalize] alpha_scores.parquet: %d names (latest month), top z: %s\n",
    nrow(lastf), paste(head(lastf$Ticker,5), collapse=",")))
cat("FINALIZE_DONE\n")
