# Supplement — full-period cap-w for ALL multi-axis candidates + score_eff+MIDemph (honesty)
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_001")
source(file.path(ROOT,"02_Infrastructure","contracts","canonical_screen_bt.R"))
panel <- readRDS(file.path(SA,"panel.rds")); res <- readRDS(file.path(SA,"screen_result.rds"))
selected_axes <- res$selected_axes; isw <- res$isw

bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, Dt := as.Date(Date)]; bm[, ym := format(Dt,"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_m <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
bm_m[, Date := as.Date(paste0(ym,"-01"))]; bm_m[, bm_fwd := shift(bm_ret, type="lead", n=1L)]
benchdt <- bm_m[!is.na(bm_fwd), .(Date, BM_Ret=bm_fwd)]
returns_dt <- panel[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
liq_dt  <- panel[, .(Date, Ticker, adv=tv20)]
nw_t <- function(x,lag=3){ if(exists(".nw_t_mean",mode="function")) .nw_t_mean(x,lag=lag) else mean(x)/sd(x)*sqrt(length(x)) }
tier_mult <- c(MEGA=0.25, MID=1.0, OTHER=0.5)

score_it <- function(dt, mode, midgate){
  d <- copy(dt); if(midgate) d <- d[tier=="MID"]
  zc <- paste0("zc_",selected_axes); zt <- paste0("zt_",selected_axes)
  if(mode=="EW_notier")  s <- rowMeans(as.matrix(d[,..zc]),na.rm=TRUE)
  else if(mode=="EW_midemph") s <- rowMeans(as.matrix(d[,..zt]),na.rm=TRUE)*tier_mult[d$tier]
  else if(mode=="ISw_midemph"){W<-isw/sum(isw); s<-as.numeric(as.matrix(d[,..zt])%*%W)*tier_mult[d$tier]}
  else if(mode=="MIDgate") s <- rowMeans(as.matrix(d[,..zt]),na.rm=TRUE)
  else if(mode=="scoreeff_midemph") s <- d$score_eff * tier_mult[d$tier]  # incumbent + MID emphasis
  d[, score:=s]; d[!is.na(score), .(Date,Ticker,score)]
}
run1 <- function(mode, midgate, top){
  sc <- score_it(panel, mode, midgate)
  r <- canonical_screen_bt(sc, returns_dt, benchdt, top_n=top, cost_bps_oneway=15, liq_dt=liq_dt,
                           liq_min=2e8, run_id=mode, strategy_id=mode, diag_dual_basis=FALSE)
  pr <- as.data.table(r$period_returns); pr17 <- pr[date>=as.Date("2017-01-01")]
  a17 <- pr17$ret_net - pr17$benchmark_ret
  data.table(variant=mode, midgate=midgate, top=top,
             capw_port_t=round(r$portfolio_alpha_t_nw_lag3,3), ir=round(r$information_ratio,3),
             capw_post2017_t=round(nw_t(a17),3), to=round(r$turnover_annual,2), n=r$n_months)
}
cat("\n===== FULL-PERIOD cap-w (all multi-axis variants + incumbent+MIDemph) =====\n")
tab <- rbindlist(list(
  run1("EW_notier",   FALSE, 25L),
  run1("EW_midemph",  FALSE, 25L),
  run1("ISw_midemph", FALSE, 25L),
  run1("MIDgate",     TRUE,  20L),
  run1("scoreeff_midemph", FALSE, 25L)
))
print(tab)
saveRDS(tab, file.path(SA,"supplement_tab.rds"))
