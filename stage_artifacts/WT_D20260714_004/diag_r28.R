## R28 dual-basis + oos_retention + lookahead confirmation diagnostics
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_004")
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
PAN <- as.data.table(read_parquet(file.path(WT,"recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
SI <- readRDS(file.path(WT,"screen_inputs.rds")); fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
R <- readRDS(file.path(WT,"screen_results.rds"))
IS_END <- as.Date("2024-06-30")
nw_t <- function(x){x<-x[is.finite(x)]; if(length(x)<12)return(NA_real_); fit<-lm(x~1); se<-sqrt(NeweyWest(fit,lag=3,prewhite=FALSE)[1,1]); unname(coef(fit)[1]/se)}
oos_ret_v2 <- function(active, frac=c(.55,.65,.75)){active<-active[is.finite(active)];n<-length(active)
  sr<-function(x){if(length(x)<6)return(NA);s<-sd(x);if(!is.finite(s)||s<=0)return(NA);mean(x)/s*sqrt(12)}
  r<-sapply(frac,function(f){k<-floor(n*f);if(k<6||n-k<6)return(NA);is_<-sr(active[1:k]);oo<-sr(active[(k+1):n]);if(is.na(is_)||is_<=0)return(NA);oo/is_});median(r,na.rm=TRUE)}
## EW-universe bench (mean of universe returns per month)
UNIret <- merge(unique(SIZE[,.(Date,Ticker)]), fwd_ret, by=c("Date","Ticker"))
ewb <- UNIret[,.(ew_bench=mean(Ret_1m,na.rm=TRUE)),by=Date]

diag_one <- function(cc){
  x <- R[[cc]]; if(is.null(x)) return(NULL)
  pr <- copy(x$pr)  # date, ret_net, benchmark_ret(cap-w), active
  pr <- merge(pr, ewb, by.x="date", by.y="Date", all.x=TRUE)
  pr[,active_ew:=ret_net-ew_bench]
  p17 <- pr$date>=as.Date("2017-01-01")
  data.table(panel=cc,
    port_t_capw=x$res$portfolio_alpha_t_nw_lag3, ir_capw=x$res$information_ratio,
    net_sr_capw=x$res$net_sr, oos_ret_capw=oos_ret_v2(pr$active),
    post2017_t_capw=nw_t(pr$active[p17]),
    port_t_ewuni=nw_t(pr$active_ew), post2017_t_ewuni=nw_t(pr$active_ew[p17]),
    oos_ret_ewuni=oos_ret_v2(pr$active_ew), n=nrow(pr))
}
key <- c("score_stored","1_stored_S7","1_stored_S6","0_stored_S7","0_stored_S6","0_ic_S7","0_ic_S6","1_ic_S7")
D <- rbindlist(lapply(key, diag_one), fill=TRUE)
cat("===== DUAL-BASIS + OOS (cap-w authoritative; EW-uni diagnostic) =====\n"); print(D)
save_safe(D, file.path(WT,"dualbasis_oos.parquet"), function(o,p) write_parquet(o,p))

## cap-tier weight share for base (off=0 stored 7F vs 6F) via SIZE ranking
tier_share <- function(cc){
  W <- R[[cc]]$W; if(is.null(W)) return(NULL)
  Z <- copy(SIZE); setorder(Z,Date,-Size); Z[,rank:=seq_len(.N),by=Date]
  Z[,tier:=fifelse(rank<=10,"MEGA",fifelse(rank<=30,"MID","OTHER"))]
  HT <- merge(W, Z[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE); HT[is.na(tier),tier:="UNRANKED"]
  sh <- HT[,.(w=sum(w)),by=.(Date,tier)][,.(share=mean(w)),by=tier]
  sh[,panel:=cc]; sh}
TS <- rbindlist(lapply(c("0_stored_S7","0_stored_S6","1_stored_S7"), tier_share), fill=TRUE)
cat("\n===== CAP-TIER weight share (base panels) =====\n")
tryCatch(print(dcast(TS[,.(panel,tier,share)], panel~tier, value.var="share")), error=function(e) print(TS))
save_safe(TS, file.path(WT,"cap_tier_share.parquet"), function(o,p) write_parquet(o,p))

## lookahead confirmation table: PORT_t off=0 vs off=+1, same theta+sleeve (only factor_db month differs)
la <- data.table(
  cell=c("stored_S7","stored_S6","ic_S7","ic_S6"),
  port_t_off0_PITclean=c(R[["0_stored_S7"]]$res$portfolio_alpha_t_nw_lag3, R[["0_stored_S6"]]$res$portfolio_alpha_t_nw_lag3,
                         R[["0_ic_S7"]]$res$portfolio_alpha_t_nw_lag3, R[["0_ic_S6"]]$res$portfolio_alpha_t_nw_lag3),
  port_t_off1_samemonth_lookahead=c(R[["1_stored_S7"]]$res$portfolio_alpha_t_nw_lag3, R[["1_stored_S6"]]$res$portfolio_alpha_t_nw_lag3,
                         R[["1_ic_S7"]]$res$portfolio_alpha_t_nw_lag3, R[["1_ic_S6"]]$res$portfolio_alpha_t_nw_lag3))
la[,inflation_ratio:=port_t_off1_samemonth_lookahead/port_t_off0_PITclean]
cat("\n===== LOOK-AHEAD CONFIRMATION (only factor_db month differs) =====\n"); print(la)
cat(sprintf("stored panel (direct screen) PORT_t = %.3f (sits between clean %.2f and lookahead %.2f)\n",
    R[["score_stored"]]$res$portfolio_alpha_t_nw_lag3, R[["0_stored_S7"]]$res$portfolio_alpha_t_nw_lag3, R[["1_stored_S7"]]$res$portfolio_alpha_t_nw_lag3))
save_safe(la, file.path(WT,"lookahead_confirm.parquet"), function(o,p) write_parquet(o,p))
cat("DIAG_DONE\n")
