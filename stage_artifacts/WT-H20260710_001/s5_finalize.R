# WT-H20260710_001 Stage 5 — alpha_scores.parquet + advisory diagnostics for winner & incumbent.
suppressMessages({library(arrow); library(data.table)})
options(scipen=999); setDTthreads(1L); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-H20260710_001")
inp<-readRDS(file.path(SA,"inputs.rds")); swp<-readRDS(file.path(SA,"sweep_is.rds"))
m08v<-readRDS(file.path(SA,"m08_variants.rds")); cv<-readRDS(file.path(SA,"c_variants.rds")); ap<-inp$ap
.winsor_z <- function(x, sigma=2.5){ if(!is.finite(sigma)) return(x); m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}
.zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
mp <- merge(inp$core_panel, inp$def_panel, by=c("Date","Ticker"), all=TRUE)
mp <- merge(mp, cv[, .(Date,Ticker, z_esbr_3, z_tpgap_5)], by=c("Date","Ticker"), all.x=TRUE)
build_sleeve<-function(P,cols){ wl<-list(); for(fn in cols) wl[[fn]]<-P[, .winsor_z(get(fn),2.5), by=Date]$V1
  M<-do.call(cbind,wl); s<-rowSums(M); P2<-data.table(Date=P$Date,Ticker=P$Ticker,sraw=s); P2[,sz:=.zc(sraw),by=Date]; P2[,.(Date,Ticker,sz)] }
# winner C5: core={C01,C02,z_esbr_3,z_tpgap_5}, def={Q07,M08,Q25}
cz<-build_sleeve(mp,c("C01_SUE","C02_EPS_Chg_1m","z_esbr_3","z_tpgap_5")); setnames(cz,"sz","cz")
dz<-build_sleeve(mp,c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")); setnames(dz,"sz","dz")
w<-merge(cz,dz,by=c("Date","Ticker")); w[,score_winner:=0.65*cz+0.35*dz]
out<-merge(ap[,.(Date,Ticker,score_eff_incumbent=score_eff,Ret_1m)], w[,.(Date,Ticker,score_winner)], by=c("Date","Ticker"), all.x=TRUE)
write_parquet(out, file.path(SA,"alpha_scores.parquet"))

# advisory rank-IC / ICIR / harvey-t + redundancy cor (winner vs incumbent), full period
ric<-function(scol){ d<-out[!is.na(get(scol))&!is.na(Ret_1m)]
  icv<-d[,{if(.N>=8) .(ic=cor(get(scol),Ret_1m,method="spearman")) else .(ic=NA_real_)},by=Date]$ic; icv<-icv[!is.na(icv)]
  list(rank_ic=mean(icv), icir=mean(icv)/sd(icv), harvey_t=mean(icv)/sd(icv)*sqrt(length(icv)), n=length(icv)) }
rw<-ric("score_winner"); ri<-ric("score_eff_incumbent")
red<-out[!is.na(score_winner)&!is.na(score_eff_incumbent), .(c=cor(score_winner,score_eff_incumbent)), by=Date][,mean(c,na.rm=TRUE)]
# subperiod stability (winner): rank-IC sign consistency across 3 blocks
out[, blk := fifelse(Date<as.Date("2014-01-01"),"p1",fifelse(Date<as.Date("2019-01-01"),"p2","p3"))]
sub<-out[!is.na(score_winner)&!is.na(Ret_1m), {icv<-.SD[,{if(.N>=8) .(ic=cor(score_winner,Ret_1m,method="spearman")) else .(ic=NA_real_)},by=Date]$ic; .(mic=mean(icv,na.rm=TRUE))}, by=blk]
cat("=== ADVISORY (full period) ===\n")
cat(sprintf("winner   rank_ic=%.4f icir=%.3f harvey_t=%.3f (n=%d)\n", rw$rank_ic,rw$icir,rw$harvey_t,rw$n))
cat(sprintf("incumbent rank_ic=%.4f icir=%.3f harvey_t=%.3f (n=%d)\n", ri$rank_ic,ri$icir,ri$harvey_t,ri$n))
cat(sprintf("winner subperiod rank-IC: p1=%.4f p2=%.4f p3=%.4f\n",
    sub[blk=="p1",mic],sub[blk=="p2",mic],sub[blk=="p3",mic]))
cat(sprintf("redundancy: winner vs incumbent cross-sec cor = %.3f\n", red))
saveRDS(list(winner_adv=rw, inc_adv=ri, redundancy_cor=red,
             subperiod=list(p1=sub[blk=="p1",mic],p2=sub[blk=="p2",mic],p3=sub[blk=="p3",mic])),
        file.path(SA,"advisory.rds"))
cat("[saved] alpha_scores.parquet + advisory.rds\n")
