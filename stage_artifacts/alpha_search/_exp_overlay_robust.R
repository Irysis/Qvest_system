## ============================================================
## EXPERIMENT 2 ROBUSTNESS: regime overlay PIT-lag + placebo + dependence
## Tests whether the regime de-risk SR gain is (a) PIT-real, (b) not over-fit
## to a handful of crisis months, (c) survives strict t-1 lag.
## ============================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(PerformanceAnalytics); library(xts)
})
options(warn=1)
BASE <- "G:/Quant_Module_Moltbot"
PROD <- file.path(BASE,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe")
OUT  <- file.path(BASE,"stage_artifacts/alpha_search")
BPS <- 15
set.seed(20260607)

b <- readRDS(file.path(OUT,"_exp_baseline.rds"))
core <- copy(b$dt); setorder(core, period_end); NP <- nrow(core)
r05 <- as.data.table(read_parquet(file.path(PROD,"alpha_scores_r05_panel.parquet")))
reg <- unique(r05[,.(sig_date=Date, regime_state)], by="sig_date"); setorder(reg, sig_date)
core[, regime_state := reg$regime_state[seq_len(NP)]]

metr <- function(ret, bm, end){
  rx<-xts(ret,order.by=as.Date(end)); bx<-xts(bm,order.by=as.Date(end)); ax<-rx-bx
  list(sr_total=as.numeric(SharpeRatio.annualized(rx,Rf=0,scale=12)),
       sr_active=as.numeric(SharpeRatio.annualized(ax,Rf=0,scale=12)),
       cagr=as.numeric(Return.annualized(rx,scale=12)),
       mdd=as.numeric(maxDrawdown(rx)))
}
apply_e <- function(e){
  e[!is.finite(e)]<-1; e<-pmin(pmax(e,0),1)
  ep <- c(1, head(e,-1))
  to_eff <- ep*core$turnover + abs(e-ep)
  ret <- e*core$port_gross - (BPS/1e4)*to_eff*2
  ret
}
full_metr <- function(e, name){
  ret <- apply_e(e)
  f <- metr(ret, core$bm_ret, core$period_end)
  oos<- core$period_end>=as.Date("2010-01-01") & core$period_end<=as.Date("2023-12-31")
  o <- metr(ret[oos], core$bm_ret[oos], core$period_end[oos])
  ## early/late retention (total)
  mid<-ceiling(NP/2); el<-1:mid; ll<-(mid+1):NP
  me<-metr(ret[el],core$bm_ret[el],core$period_end[el]); ml<-metr(ret[ll],core$bm_ret[ll],core$period_end[ll])
  retn <- ml$sr_total/me$sr_total
  cat(sprintf("  %-22s FULL SR_tot=%.4f act=%.4f CAGR=%.4f MDD=%.4f | OOS SR_tot=%.4f | oos_ret_tot=%.4f\n",
      name,f$sr_total,f$sr_active,f$cagr,f$mdd,o$sr_total,retn))
  list(full=f, oos=o, oos_ret_tot=retn, ret=ret)
}

cat("=== regime label distribution (per period) ===\n")
print(table(core$regime_state))
def_idx <- which(core$regime_state %in% c("CRISIS","CAUTION"))
cat(sprintf("defensive periods: %d / %d (%.1f%%)  dates: %s\n",
    length(def_idx), NP, 100*length(def_idx)/NP,
    paste(as.character(core$period_end[def_idx]), collapse=", ")))

cat("\n=== BASELINE ===\n")
base <- full_metr(rep(1,NP),"baseline")

cat("\n=== CONFIG 3 contemporaneous (keep=0) [as run before] ===\n")
e0 <- ifelse(core$regime_state %in% c("CRISIS","CAUTION"), 0, 1)
c0 <- full_metr(e0,"regime_keep0_contemp")
e5 <- ifelse(core$regime_state %in% c("CRISIS","CAUTION"), 0.5, 1)
c5 <- full_metr(e5,"regime_keep5_contemp")

cat("\n=== STRICT t-1 LAG: use regime decided at PREVIOUS rebal (shift +1) ===\n")
## e for period i depends on regime_state[i-1] (one rebal earlier)
reg_lag <- c("NORMAL", head(core$regime_state,-1))
e0L <- ifelse(reg_lag %in% c("CRISIS","CAUTION"), 0, 1)
c0L <- full_metr(e0L,"regime_keep0_LAG1")
e5L <- ifelse(reg_lag %in% c("CRISIS","CAUTION"), 0.5, 1)
c5L <- full_metr(e5L,"regime_keep5_LAG1")

cat("\n=== DEPENDENCE: how much of the gain is a FEW months? ===\n")
## contribution of defensive periods to total return diff
ret_base <- base$ret; ret_ov <- c0$ret
diff <- ret_ov - ret_base
ord <- order(diff, decreasing=TRUE)
cat("top 5 period contributions to (overlay - baseline) return:\n")
for(j in ord[1:5]) cat(sprintf("   %s  regime=%-7s  base=%+.4f overlay=%+.4f diff=%+.4f\n",
    as.character(core$period_end[j]), core$regime_state[j], ret_base[j], ret_ov[j], diff[j]))
cat(sprintf("sum diff over ALL: %+.4f ; sum over top-3 months: %+.4f (%.0f%%)\n",
    sum(diff), sum(diff[ord[1:3]]), 100*sum(diff[ord[1:3]])/sum(diff)))

cat("\n=== PLACEBO: shuffle which periods are 'defensive' (same count), 500x ===\n")
ndef <- length(def_idx)
B <- 500
sr_perm <- numeric(B)
for(bb in 1:B){
  idx <- sample.int(NP, ndef)
  e <- rep(1,NP); e[idx] <- 0
  r <- apply_e(e)
  sr_perm[bb] <- metr(r, core$bm_ret, core$period_end)$sr_total
}
real_sr <- c0$full$sr_total
pval <- mean(sr_perm >= real_sr)
cat(sprintf("real regime_keep0 FULL SR_tot=%.4f ; placebo mean=%.4f sd=%.4f ; p(placebo>=real)=%.3f\n",
    real_sr, mean(sr_perm), sd(sr_perm), pval))
cat(sprintf("placebo quantiles: 50%%=%.3f 90%%=%.3f 95%%=%.3f 99%%=%.3f max=%.3f\n",
    quantile(sr_perm,.5),quantile(sr_perm,.9),quantile(sr_perm,.95),quantile(sr_perm,.99),max(sr_perm)))

saveRDS(list(base=base, c0=c0,c5=c5,c0L=c0L,c5L=c5L,
             def_idx=def_idx, sr_perm=sr_perm, real_sr=real_sr, pval=pval),
        file.path(OUT,"_exp_overlay_robust.rds"))
cat("\n[DONE] saved _exp_overlay_robust.rds\n")
