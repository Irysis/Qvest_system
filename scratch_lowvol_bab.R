suppressMessages({library(data.table);library(arrow)})
setDTthreads(1)
root<-Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(root)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

zscore<-function(x){s<-sd(x,na.rm=TRUE);if(!is.finite(s)||s<=0)return(rep(0,length(x)));(x-mean(x,na.rm=TRUE))/s}

# universe per date from FAM panel (K200|KQ150 already embedded as FAM rows)
FAMpanel <- .FAM  # has Date,Ticker,low_vol,...
univ_by_date <- FAMpanel[,.(Date,Ticker)]

# build a family score panel from a set of proxies (mirror build_panel.R: aligned-z EW rowMeans -> cross-sectional z)
build_family_score <- function(proxies, dates){
  out <- vector("list", length(dates))
  for(i in seq_along(dates)){
    sd_i <- dates[i]
    mf <- tryCatch(load_month_factors(sd_i, factor_names=proxies), error=function(e) NULL)
    if(is.null(mf)||nrow(mf)==0) next
    u <- univ_by_date[Date==sd_i, Ticker]
    if(length(u)==0) next
    mf <- mf[Ticker %in% u]
    if(nrow(mf)==0) next
    W <- dcast(mf, Ticker ~ Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x) mean(x,na.rm=TRUE))
    px <- intersect(proxies, names(W))
    if(length(px)==0) next
    m <- as.matrix(W[,..px]); comp <- rowMeans(m, na.rm=TRUE)
    dt <- data.table(Date=sd_i, Ticker=W$Ticker, score=zscore(comp))
    out[[i]] <- dt[is.finite(score)]
  }
  rbindlist(out)
}

# lag1: assign each date the previous sig_date's (Ticker,score)
lag1_score <- function(sc){
  dts <- sort(unique(sc$Date)); lm<-data.table(Date=dts, prevdate=shift(dts,1))[!is.na(prevdate)]
  merge(lm, sc[,.(prevdate=Date,Ticker,score)], by="prevdate", allow.cartesian=TRUE)[,.(Date,Ticker,score)]
}

metrics_of <- function(sc, label){
  res <- .canon(sc); pr<-res$period_returns
  lg <- tryCatch(.canon(lag1_score(sc))$portfolio_alpha_t_nw_lag3, error=function(e) NA_real_)
  list(label=label, n_months=res$n_months,
       port_t=round(res$portfolio_alpha_t_nw_lag3,3),
       ew_uni_t=round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),
       oos_ret=round(.oos_ret_of(pr),3),
       net_sr=round(res$net_sr,3),
       calmar=round(.calmar_of(pr),3),
       turnover=round(res$turnover_annual,2),
       lag1_port_t=round(lg,3))
}

dts <- .oos_dates

# ---------- BASELINE: current low_vol construction (FAM low_vol column) ----------
base_sc <- FAMpanel[is.finite(low_vol), .(Date,Ticker,score=low_vol)]
m_base <- metrics_of(base_sc, "baseline_current_lowvol")

# ---------- REDESIGN lowvol_BAB (economic composite, a priori) ----------
# axes: BAB(D18,D02) + lottery(D05_MaxRet) + downside(D04,D45)
redesign_prox <- c("D18_BAB_Rank","D02_Beta","D05_MaxRet","D04_Downside_Beta","D45_Downside_Dev")
sc_re <- build_family_score(redesign_prox, dts)
m_re <- metrics_of(sc_re, "redesign_lowvol_BAB")

# ---------- diagnostics (NOT selection) : single-axis to understand mechanism ----------
sc_bab <- build_family_score(c("D18_BAB_Rank","D02_Beta"), dts); m_bab<-metrics_of(sc_bab,"diag_BAB_only")
sc_max <- build_family_score(c("D05_MaxRet"), dts); m_max<-metrics_of(sc_max,"diag_MAX_only")
sc_dn  <- build_family_score(c("D04_Downside_Beta","D45_Downside_Dev"), dts); m_dn<-metrics_of(sc_dn,"diag_downside_only")

pr<-function(m) cat(sprintf("%-26s n=%d port_t=%s ew_uni=%s oos=%s net_sr=%s calmar=%s TO=%s lag1=%s\n",
  m$label,m$n_months,m$port_t,m$ew_uni_t,m$oos_ret,m$net_sr,m$calmar,m$turnover,m$lag1_port_t))
cat("\n===== RESULTS =====\n")
pr(m_base); pr(m_re); pr(m_bab); pr(m_max); pr(m_dn)
saveRDS(list(base=m_base,redesign=m_re,bab=m_bab,max=m_max,dn=m_dn),
        file.path(Sys.getenv("TEMP"),"lowvol_bab_res.rds"))
