## R28 screen + paired NW-t + dual-basis + verdict inputs
## Consumes recon_panels.parquet + screen_inputs.rds
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_004")
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}

PAN <- as.data.table(read_parquet(file.path(WT,"recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
SI <- readRDS(file.path(WT,"screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE; bk<-SI$bk
IS_END <- as.Date("2024-06-30")

cap_norm <- function(w){w[!is.finite(w)|w<0]<-0; if(sum(w)<=0) return(rep(1/length(w),length(w))); w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break; w[w>0.20]<-0.20; rem<-1-sum(w); ix<-w<0.20
    if(sum(ix)==0||rem<=0)break; w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])}; w[w>0.20]<-0.20; w/sum(w)}
## cap-w top-25 weights from a score column
mk_capw <- function(scoredt, scorecol){
  S <- merge(scoredt[is.finite(get(scorecol)),.(Date,Ticker,sc=get(scorecol))], SIZE, by=c("Date","Ticker"))
  S <- merge(S, liqf, by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
  W <- list(); for(d in sort(unique(S$Date))){sub<-S[Date==d]; if(nrow(sub)<25) next
    setorder(sub,-sc); hd<-head(sub,25); W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))}
  rbindlist(W)}
## NW lag-3 t of a mean (paired diff series)
nw_t <- function(x){x<-x[is.finite(x)]; if(length(x)<12)return(NA_real_); fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=3,prewhite=FALSE)[1,1]); unname(coef(fit)[1]/se)}
ir_of <- function(active){active<-active[is.finite(active)]; if(length(active)<6)return(NA_real_); mean(active)/sd(active)*sqrt(12)}

## run screen for a score column -> per-month net-active series (contract) + PORT_t
run_col <- function(scorecol, tag){
  if(!(scorecol %in% names(PAN))) return(NULL)
  W <- mk_capw(PAN, scorecol)
  if(nrow(W)==0) return(NULL)
  res <- weighted_screen_bt(W, fwd_ret, bench, cost_bps_oneway=15, run_id=tag, strategy_id=tag)
  pr <- as.data.table(res$period_returns)  # date, ret_net, benchmark_ret
  pr[,active:=ret_net-benchmark_ret]
  list(tag=tag, res=res, pr=pr, W=W)
}

## columns present
cols <- setdiff(names(PAN),c("Date","Ticker"))
cat("panel cols:", paste(cols,collapse=","), "\n")

## Also screen the STORED FROZEN panel directly (reference base = R26's 5.324)
bk_sc <- bk[is.finite(score_eff),.(Date=as.Date(Date),Ticker,score_eff)]
## bk Date = AS_OF (first-of-month label). Map to d0 = fwd sig_date in prior month.
bk_sc[,map_ym:=format(as.Date(paste0(format(Date,"%Y-%m"),"-01"))-1,"%Y-%m")]
d0map <- data.table(d0=sort(unique(fwd_ret$Date))); d0map[,ym:=format(d0,"%Y-%m")]
bk_sc <- merge(bk_sc, d0map, by.x="map_ym", by.y="ym")
bk_sc <- bk_sc[,.(Date=d0,Ticker,score_stored=score_eff)]
PAN2 <- merge(PAN, bk_sc, by=c("Date","Ticker"), all.x=TRUE)

R <- list()
allcols <- c(cols,"score_stored")
for(cc in allcols){
  src <- if(cc=="score_stored") { tmp<-PAN2[is.finite(score_stored),.(Date,Ticker,score_stored)]; tmp } else PAN
  x <- tryCatch(run_col_generic <- {
    W <- mk_capw(if(cc=="score_stored") PAN2 else PAN, cc); if(nrow(W)==0) NULL else {
    res<-weighted_screen_bt(W,fwd_ret,bench,cost_bps_oneway=15,run_id=cc,strategy_id=cc)
    pr<-as.data.table(res$period_returns); pr[,active:=ret_net-benchmark_ret]; list(res=res,pr=pr)}},
    error=function(e){cat("ERR",cc,conditionMessage(e),"\n");NULL})
  if(is.null(x)) next
  R[[cc]] <- x
  cat(sprintf("[%s] PORT_t=%.3f IR=%.3f n=%d TO=%.1f\n", cc, x$res$portfolio_alpha_t_nw_lag3,
              x$res$information_ratio, x$res$n_months, x$res$turnover_annual))
}
save_safe(R, file.path(WT,"screen_results.rds"), saveRDS)

## ---- paired 6F vs 7F within each (off,theta) cell ----
cells <- list(c("0_stored_S7","0_stored_S6"), c("0_ic_S7","0_ic_S6"),
              c("1_stored_S7","1_stored_S6"), c("1_ic_S7","1_ic_S6"))
paired_tbl <- rbindlist(lapply(cells, function(cl){
  a<-R[[cl[1]]]; b<-R[[cl[2]]]; if(is.null(a)||is.null(b)) return(NULL)
  m<-merge(a$pr[,.(date,active7=active)], b$pr[,.(date,active6=active)], by="date")
  m[,diff:=active6-active7]  # 6F minus 7F: positive = removing C06 helps
  is_m<-m[date<=IS_END]; ho_m<-m[date>IS_END]
  data.table(cell=cl[1], base7=cl[1], var6=cl[2],
    n_full=nrow(m), n_is=nrow(is_m), n_ho=nrow(ho_m),
    paired_t_full=nw_t(m$diff), paired_t_is=nw_t(is_m$diff), paired_t_ho=nw_t(ho_m$diff),
    mean_diff_is_bps=mean(is_m$diff)*1e4, mean_diff_ho_bps=mean(ho_m$diff)*1e4,
    port_t7=a$res$portfolio_alpha_t_nw_lag3, port_t6=b$res$portfolio_alpha_t_nw_lag3,
    ir7=a$res$information_ratio, ir6=b$res$information_ratio, dIR=b$res$information_ratio-a$res$information_ratio)
}), fill=TRUE)
cat("\n===== PAIRED 6F(-C06) vs 7F (positive = removing C06 helps) =====\n"); print(paired_tbl)
save_safe(paired_tbl, file.path(WT,"paired_results.parquet"), function(o,p) write_parquet(o,p))

## ---- parity summary: recon 7F vs stored score_eff (per-month cross-sectional cor) ----
parity <- rbindlist(lapply(c("0_stored_S7","1_stored_S7","0_ic_S7","1_ic_S7"), function(cc){
  if(!cc %in% names(PAN)) return(NULL)
  mm <- merge(PAN2[,.(Date,Ticker,rec=get(cc))], PAN2[is.finite(score_stored),.(Date,Ticker,score_stored)], by=c("Date","Ticker"))
  mm <- mm[is.finite(rec)&is.finite(score_stored)]
  per <- mm[,.(cor=if(.N>=10&&sd(rec)>0&&sd(score_stored)>0) cor(rec,score_stored) else NA_real_,
               spr=if(.N>=10&&sd(rec)>0&&sd(score_stored)>0) cor(rec,score_stored,method="spearman") else NA_real_), by=Date]
  data.table(variant=cc, median_cor=median(per$cor,na.rm=TRUE), median_spearman=median(per$spr,na.rm=TRUE),
             q05_cor=quantile(per$cor,0.05,na.rm=TRUE), n_months=sum(!is.na(per$cor)))
}), fill=TRUE)
cat("\n===== PARITY: recon 7F vs stored score_eff =====\n"); print(parity)
save_safe(parity, file.path(WT,"parity_summary.parquet"), function(o,p) write_parquet(o,p))
cat("SCREEN_DONE\n")
