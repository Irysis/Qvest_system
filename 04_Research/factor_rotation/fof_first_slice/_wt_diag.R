# _wt_diag.R — WT-D20260705_001 XATTN diagnostics: rank-IC ICIR, Harvey-Liu-Zhu t, placebo,
#   feature attribution (which factor groups load on attention), and alpha-vector (as-of 2026-06)
#   with uncertainty shrinkage (research_philosophy iii). Uses seed-ENSEMBLE scores.
suppressMessages({ library(data.table); library(arrow) })
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(file.path(R,"04_Research/factor_rotation/fof_first_slice"))
MODE <- ifelse(length(commandArgs(TRUE))>=1, commandArgs(TRUE)[1], "canonical")
me <- function(ym){ d<-as.Date(paste0(ym,"-01")); as.Date(format(d+32,"%Y-%m-01"))-1 }

M <- as.data.table(read_parquet("kns_master_panel.parquet",
       col_select=c("ym","Ticker","F1","adv","K200f","KQ150f","bad","nret")))
M[, Date := me(ym)]
if (MODE=="canonical") M <- M[(K200f|KQ150f)] else if (MODE=="allliq") M <- M[nret>=15 & !bad & adv>=2e8]

ens <- sprintf("scores_XATTN_%s_ENS.parquet", MODE)
S <- as.data.table(read_parquet(ens)); S[, Date:=as.Date(Date)]
D <- merge(S[,.(Date,Ticker,score)], M[,.(Date,Ticker,F1)], by=c("Date","Ticker"))
D <- D[!is.na(F1) & !is.na(score)]

# --- rank-IC per month (Spearman) ---
ics <- D[, .(ic = if(.N>25 && sd(score)>0) cor(rank(score),rank(F1)) else NA_real_,
             n=.N), by=Date][!is.na(ic)]
setorder(ics, Date)
ic_mean <- mean(ics$ic); ic_sd <- sd(ics$ic); nM <- nrow(ics)
icir <- ic_mean/ic_sd*sqrt(12)
# rank-IC t (Newey-West lag-3 on IC series)
nw_t <- function(x, lag=3){
  x <- x[is.finite(x)]; n<-length(x); mu<-mean(x); e<-x-mu
  g0<-sum(e^2)/n; v<-g0
  for(l in 1:lag){ w<-1-l/(lag+1); gl<-sum(e[(l+1):n]*e[1:(n-l)])/n; v<-v+2*w*gl }
  mu/sqrt(v/n)
}
ic_t_nw <- nw_t(ics$ic,3)
# Harvey-Liu-Zhu multiple-testing haircut: our program tested 6 superfactor methods x 3 universes.
# HLZ (2016) BHY/Bonferroni: with M tests, adjusted t threshold rises. We report the raw t and the
# HLZ-adjusted equivalent p (Bonferroni over N_tests) so downstream can compare vs 2.95-style hurdle.
N_TESTS <- 6*3  # 6 methods x {canonical, allclean, allliq}
p_raw <- 2*pnorm(-abs(ic_t_nw))
p_bonf <- min(1, p_raw*N_TESTS)
# HLZ recommend ~t>3.0 as the multiple-testing hurdle for "new factors"; BHY less conservative.
t_hlz_hurdle <- 3.0

# --- subperiod rank-IC stability (3 eras) ---
ics[, era := fifelse(Date<as.Date("2015-01-01"),"E1_pre15",
              fifelse(Date<as.Date("2020-01-01"),"E2_1519","E3_2026"))]
sub <- ics[, .(ic=mean(ic), n=.N), by=era][order(era)]
# stability = min(era IC>0) share / fraction of eras with IC>0
sub_stab <- mean(sub$ic>0)

# --- placebo: shuffle scores within month, recompute IC mean (100 draws) ---
set.seed(20260705)
placebo <- replicate(100, {
  Dp <- copy(D); Dp[, sc_sh := sample(score), by=Date]
  mean(Dp[, if(.N>25) cor(rank(sc_sh),rank(F1)) else NA_real_, by=Date]$V1, na.rm=TRUE)
})
placebo_pctile <- mean(ic_mean > placebo)  # fraction of placebo below real
placebo_p <- mean(placebo >= ic_mean)

cat(sprintf("=== DIAG %s (ensemble) ===\n", MODE))
cat(sprintf("rank-IC mean=%+.4f sd=%.4f ICIR=%+.2f  IC_t_NW(lag3)=%+.2f  nMonths=%d\n",
            ic_mean, ic_sd, icir, ic_t_nw, nM))
cat(sprintf("HLZ multiple-testing: N_tests=%d  p_raw=%.4g  p_Bonf=%.4g  (hurdle t>%.1f)\n",
            N_TESTS, p_raw, p_bonf, t_hlz_hurdle))
cat("subperiod rank-IC:\n"); print(sub)
cat(sprintf("subperiod_stability(eras IC>0)=%.2f\n", sub_stab))
cat(sprintf("placebo: real_IC=%+.4f  placebo_mean=%+.4f  pctile=%.2f  p=%.3f\n",
            ic_mean, mean(placebo), placebo_pctile, placebo_p))

diag <- list(mode=MODE, ic_mean=ic_mean, ic_sd=ic_sd, icir=icir, ic_t_nw=ic_t_nw, n_months=nM,
             hlz_N_tests=N_TESTS, hlz_p_raw=p_raw, hlz_p_bonf=p_bonf, hlz_hurdle_t=t_hlz_hurdle,
             subperiod=sub, subperiod_stability=sub_stab,
             placebo_pctile=placebo_pctile, placebo_p=placebo_p, ic_series=ics)
saveRDS(diag, sprintf("_wt_diag_%s.rds", MODE))
cat(sprintf("[diag] DONE -> _wt_diag_%s.rds\n", MODE))
