# 06_alpha_scores.R — current-month alpha vector + alpha_scores.parquet + rank-IC diagnostics
suppressMessages({library(data.table); library(arrow)})
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260706_007")
log <- function(...) { cat(format(Sys.time(),"%H:%M:%S"), ..., "\n"); flush.console() }
E <- readRDS(file.path(OUT,"experiment_results.rds"))
fwd <- E$fwd; spr <- E$spr

# rank-IC diagnostics (per-month spearman) for the primary signal (val_z) + composite
rank_ic <- function(sc){
  d <- fwd[is.finite(get(sc))]
  ics <- d[, .(ic = if(.N>=10) suppressWarnings(cor(get(sc), fwd_mret, method="spearman")) else NA_real_), by=ym][is.finite(ic)]
  n<-nrow(ics); mu<-mean(ics$ic); s<-sd(ics$ic)
  list(mean_ic=mu, icir=mu/s, t=mu/(s/sqrt(n)), n=n, ics=ics)
}
ic_val <- rank_ic("val_z"); ic_vq <- rank_ic("vq_z"); ic_qual <- rank_ic("qual_z")
# Harvey t (rank-IC t already NW-naive; report plain t + subperiod)
sub_stab <- function(ics){
  ics[, per := fifelse(ym<201500,"p1_0514", fifelse(ym<202000,"p2_1519","p3_2026"))]
  s <- ics[, .(mean_ic=mean(ic), t=mean(ic)/(sd(ic)/sqrt(.N)), n=.N), by=per][order(per)]
  s
}
log("[rank-IC] val_z: mean_ic=%.4f icir=%.3f t=%.2f n=%d", ic_val$mean_ic, ic_val$icir, ic_val$t, ic_val$n)
cat(sprintf("[rank-IC] val_z: mean_ic=%.4f icir=%.3f t=%.2f n=%d\n", ic_val$mean_ic, ic_val$icir, ic_val$t, ic_val$n))
cat(sprintf("[rank-IC] vq_z : mean_ic=%.4f icir=%.3f t=%.2f n=%d\n", ic_vq$mean_ic, ic_vq$icir, ic_vq$t, ic_vq$n))
cat(sprintf("[rank-IC] qual : mean_ic=%.4f icir=%.3f t=%.2f n=%d\n", ic_qual$mean_ic, ic_qual$icir, ic_qual$t, ic_qual$n))
cat("[subperiod val_z]\n"); print(sub_stab(copy(ic_val$ics)))

# ---- current month (latest sig ym) alpha vector: composite value score, top-universe ----
last_ym <- max(fwd$ym)   # latest month with forward return available (signal month)
# but for FORECAST we want latest SIGNAL month even if no fwd return yet:
comp_latest_ym <- max(E$fwd$ym)  # signal months that have forward
# use the most recent AVAILABLE signal (202607 factor month) directly from factor panel
panel <- readRDS(file.path(OUT,"factor_panel_long.rds"))
val_facs  <- c("V01_BM","V02_EP","V10_FCF_Yield","V14_EBIT_EV","V20_SP")
qual_facs <- c("Q01_GPA","Q02_ROE","Q08_Composite_Quality","Q17_ROIC")
cur_ym <- max(panel$ym)
cur <- panel[ym==cur_ym & Factor_Name %in% c(val_facs,qual_facs)]
cur[, grp := fifelse(Factor_Name %in% val_facs,"val","qual")]
cc <- cur[, .(z=mean(Z_Score,na.rm=TRUE)), by=.(Ticker,grp)]
cc <- dcast(cc, Ticker~grp, value.var="z")
cc <- cc[is.finite(val)&is.finite(qual)]
zc <- function(x){m<-mean(x);s<-sd(x); (x-m)/s}
cc[, val_z := zc(val)]; cc[, vq_z := zc(val+qual)]
# alpha_hat = val_z scaled to expected active return via realized IC*ret_sd (modest). Confidence from |z| coverage.
# expected active per unit z ~ mean_ic * cross-sec return sd (approx). keep small (honest: signal weak).
ret_sd <- 0.09  # approx monthly cross-sec sd
cc[, alpha_hat := ic_val$mean_ic * val_z * ret_sd]   # expected 1M active
cc[, confidence := pmin(pmax(0.3 + 0.15*(abs(val_z)) , 0.3), 0.9)]
setorder(cc, -val_z)
cur_spread_pctile <- spr$exp_pctile[spr$ym==cur_ym]
cur_spread_ratio  <- spr$spread_ratio[spr$ym==cur_ym]
log(sprintf("[current %d] n=%d  spread_ratio=%.1f pctile=%.3f  top5 by value:", cur_ym, nrow(cc), cur_spread_ratio, cur_spread_pctile))
print(head(cc[, .(Ticker, val_z=round(val_z,2), alpha_hat=round(alpha_hat,4), confidence=round(confidence,2))],5))

# ---- alpha_scores.parquet: full history panel of scores (for downstream) ----
scores_out <- fwd[, .(Date, Ticker, ym, val_z, qual_z, vq_z, exp_pctile, spread_ratio, fwd_mret)]
write_parquet(scores_out, file.path(OUT,"alpha_scores.parquet"))
log("[saved] alpha_scores.parquet rows %d", nrow(scores_out))

saveRDS(list(ic_val=ic_val, ic_vq=ic_vq, ic_qual=ic_qual,
             sub_val=sub_stab(copy(ic_val$ics)),
             cur=cc, cur_ym=cur_ym, cur_spread_pctile=cur_spread_pctile, cur_spread_ratio=cur_spread_ratio),
        file.path(OUT,"alpha_diag.rds"))
cat("[done]\n")
