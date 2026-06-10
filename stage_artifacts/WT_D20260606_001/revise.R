## WT-D20260606_001 Optimizer REVISE — address Codex C2..C8 with quantified evidence + fix overlay schedule (C5)
suppressMessages({library(arrow); library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)})
options(warn=1); root <- "G:/Quant_Module_Moltbot"; setwd(root); set.seed(606)
OUT <- "stage_artifacts/WT_D20260606_001"
S <- readRDS(file.path(OUT,"opt_intermediate.rds")); sl <- S$sl; inc <- S$inc; m_r05 <- S$m_r05
FIN <- readRDS(file.path(OUT,"finalize_intermediate.rds")); base_ir <- FIN$base_ir

nw_tstat_mean <- function(x, L=3){ x<-x[is.finite(x)]; n<-length(x); mu<-mean(x); e<-x-mu; g0<-sum(e^2)/n; v<-g0
  if(L>0) for(l in 1:L){ w<-1-l/(L+1); gl<-sum(e[(l+1):n]*e[1:(n-l)])/n; v<-v+2*w*gl }; mu/sqrt(v/n) }

# benchmark forward monthly
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet")); RAW[,Date:=as.Date(Date)]; RAW[,ym:=format(Date,"%Y-%m")]
bm <- unique(RAW[!is.na(BM_Ret), .(Date,ym,BM_Ret)])
bm_m <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]; setorder(bm_m, ym); bm_m[, bm_fwd:=shift(bm_ret,1L,type="lead")]

# ---- C6: book-level net_IR per internal scheme (EW/MVO/HRP/ERC) at a=0.15 ----
cat("=== C6: book-level net_IR per sleeve scheme (a=0.15, net of 15bps already in sleeve_net) ===\n")
inc[, ym:=format(Date,"%Y-%m")]
scheme_book <- list()
for(sc in c("EW","MVO","HRP","ERC")){
  ser <- sl[[sc]]$series[, .(ym, sleeve_net)]
  J <- merge(ser, inc[,.(ym,r05_net=ret_net)], by="ym"); J <- merge(J, bm_m[,.(ym,bm_fwd)], by="ym")
  J <- J[is.finite(sleeve_net)&is.finite(r05_net)&is.finite(bm_fwd)]; setorder(J, ym)
  book <- 0.85*J$r05_net + 0.15*J$sleeve_net
  act <- book - J$bm_fwd
  ir <- mean(act)/sd(act)*sqrt(12); dIR <- ir - base_ir$IR
  to_rt <- mean(sl[[sc]]$series$turnover_oneway, na.rm=TRUE)*12*2
  scheme_book[[sc]] <- list(book_ir=ir, dIR=dIR, to_rt=to_rt)
  cat(sprintf(" %-4s book_IR %.3f  dIR %+.3f  sleeve_TO_rt %.2f\n", sc, ir, dIR, to_rt))
}

# ---- C3/C4: book-level CVaR95 (monthly) + worst-month for a=0.15 vs a=0.20 (EW) ----
cat("\n=== C3/C4: book-level monthly CVaR95 + worst month, a=0.15 vs 0.20 (EW) ===\n")
serEW <- sl[["EW"]]$series[,.(ym,sleeve_net)]
J <- merge(serEW, inc[,.(ym,r05_net=ret_net)], by="ym"); J <- merge(J, bm_m[,.(ym,bm_fwd)], by="ym")
J <- J[is.finite(sleeve_net)&is.finite(r05_net)&is.finite(bm_fwd)]; setorder(J, ym)
cvar95 <- function(x){ q<-quantile(x,0.05); mean(x[x<=q]) }
for(a in c(0.15,0.20)){
  book <- (1-a)*J$r05_net + a*J$sleeve_net
  cat(sprintf(" a=%.2f  bookCVaR95_m %.4f  worst_month %.4f  R05_only_CVaR95 %.4f\n",
      a, cvar95(book), min(book), cvar95(J$r05_net)))
}
cat(sprintf(" book CVaR95 cap reference = 2.5%% monthly (RX-3). a=0.15 book CVaR95 = %.4f\n", cvar95((0.85*J$r05_net+0.15*J$sleeve_net))))

# ---- C7: book beta vs BM (overlay OFF, a=0.15) ----
cat("\n=== C7: book beta vs KOSPI200 (overlay OFF, a=0.15) ===\n")
book015 <- 0.85*J$r05_net + 0.15*J$sleeve_net
beta_book <- cov(book015, J$bm_fwd)/var(J$bm_fwd)
beta_r05  <- { Jr <- merge(inc[,.(ym,r05_net=ret_net)], bm_m[,.(ym,bm_fwd)], by="ym"); Jr<-Jr[is.finite(r05_net)&is.finite(bm_fwd)]; cov(Jr$r05_net,Jr$bm_fwd)/var(Jr$bm_fwd) }
cat(sprintf(" beta_book(a0.15) %.3f | beta_R05 %.3f | sleeve beta_BM (risk) 1.018\n", beta_book, beta_r05))

# ---- C2/C8: book-level turnover + cost reconciliation ----
cat("\n=== C2/C8: turnover + cost units ===\n")
ew_ow_m <- mean(sl[["EW"]]$series$turnover_oneway, na.rm=TRUE)   # one-way monthly L1
sleeve_to_rt_ann <- ew_ow_m*12*2
book_to_rt_ann <- 0.15*sleeve_to_rt_ann   # sleeve is 15% of book; R05 turnover handled by incumbent (frozen, already costed in ret_net)
cost_sleeve_ann <- sleeve_to_rt_ann*0.0015   # annual round-trip * 15bps... NOTE round-trip already x2, so cost = oneway_ann*2*15bps = rt_ann*15bps
cost_book_ann <- book_to_rt_ann*0.0015
cat(sprintf(" sleeve one-way monthly L1 %.3f\n", ew_ow_m))
cat(sprintf(" sleeve annual round-trip turnover %.2f (=ow_m*12*2)\n", sleeve_to_rt_ann))
cat(sprintf(" sleeve annual cost %.4f (=rt_ann*15bps) [already deducted in sleeve_net]\n", cost_sleeve_ann))
cat(sprintf(" BOOK annual round-trip turnover %.2f (sleeve leg only; R05 frozen)\n", book_to_rt_ann))
cat(sprintf(" BOOK annual incremental cost %.4f\n", cost_book_ann))
cat(sprintf(" RF-O13 check: book RT turnover %.2fx vs 6.0x cap -> %s ; sleeve-leg %.2fx > 6.0x -> BREACH at sleeve level\n",
    book_to_rt_ann, ifelse(book_to_rt_ann<=6.0,"PASS","BREACH"), sleeve_to_rt_ann))

# ---- C5 FIX: rebuild overlay_exposure schedule joining by YM (not Date) ----
cat("\n=== C5 FIX: overlay schedule via ym join ===\n")
W <- copy(sl[["EW"]]$weights)   # Date,Ticker,w
W[, ym := format(Date,"%Y-%m")]
ovm <- inc[, .(ym, sig=pmax(MSM_Crisis_Prob_lag, combined_regime, na.rm=TRUE))]
ovm[is.na(sig), sig:=0]; ovm[, exposure := ifelse(sig>=0.6, 0.3, 1.0)]
W <- merge(W, ovm[,.(ym,exposure)], by="ym", all.x=TRUE); W[is.na(exposure), exposure:=1.0]
A_BOOK <- 0.15
W[, book_weight := w*A_BOOK][, effective_book_weight := book_weight*exposure]
setorder(W, Date, -w)
fwrite(W[, .(as_of_date=Date, Date, Ticker, method_selected="STATIC_MULTISLEEVE_EW_a0.15",
             sleeve_weight=w, book_allocation=A_BOOK, book_weight,
             overlay_exposure=exposure, effective_book_weight)],
       file.path(OUT,"weights.csv"))
cat("overlay_exposure table after fix:\n"); print(table(W$exposure))
cat("unique dates:", length(unique(W$Date)), "\n")

saveRDS(list(scheme_book=scheme_book, beta_book=beta_book, beta_r05=beta_r05,
             cvar_a15=cvar95(0.85*J$r05_net+0.15*J$sleeve_net),
             cvar_a20=cvar95(0.80*J$r05_net+0.20*J$sleeve_net),
             worst_a15=min(0.85*J$r05_net+0.15*J$sleeve_net),
             worst_a20=min(0.80*J$r05_net+0.20*J$sleeve_net),
             sleeve_to_rt_ann=sleeve_to_rt_ann, book_to_rt_ann=book_to_rt_ann,
             cost_book_ann=cost_book_ann), file.path(OUT,"revise_intermediate.rds"))
cat("\n[done revise]\n")
