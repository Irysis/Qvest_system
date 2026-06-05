# =============================================================
# WT-D20260529_001 FLOW — Stage 3: emit weights.csv (walk-forward schedule)
# FLOW sleeve weights at EVERY sig_date (monthly) for selected method.
# Schedule density mandate: unique_dates >= sig_dates_count * 0.95
# Note: weights held quarterly (rebal), but emitted MONTHLY (carry-forward held weights
#       + monthly drift renormalization) so density >= 0.95 and Forge has holdings each month.
# =============================================================
suppressMessages({library(data.table); library(arrow)})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260529_001_FLOW")
LOCKBOX <- as.Date("2023-12-22"); W_CAP <- 0.20; MAX_NAMES <- 20L; LIQ_FLOOR <- 2e8
COST_OW <- 0.0015; N_DAYS_COV <- 252L

source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/portfolio/advanced_weights.R")
source("02_Infrastructure/portfolio/mean_variance_optimizer.R")
`%||%` <- function(a,b) if (is.null(a)) b else a

st  <- readRDS(file.path(OUT,"opt_stage2.rds"))
bl  <- readRDS(file.path(OUT,"opt_blend.rds"))
sel_method <- st$sel_method
flow_w_book <- bl$best$flow_w     # book allocation to FLOW sleeve
cat(sprintf("[emit] sel_method=%s | book FLOW alloc=%.0f%%\n", sel_method, flow_w_book*100))

alpha <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
alpha <- alpha[Date <= LOCKBOX]
sig_dates <- sort(unique(alpha$Date))

rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd <- rd[Date <= LOCKBOX, .(Date,Ticker,Ret,Close,Vol,AdminStock,TradingHalt)]
rd[, TV := Close*Vol]; setkey(rd, Date, Ticker)

erc_w <- function(Sig, tk){n<-ncol(Sig);x<-rep(1/n,n);for(i in 1:300){mrc<-as.numeric(Sig%*%x);rc<-x*mrc;tgt<-mean(rc);x<-x*(tgt/(rc+1e-12))^0.5;x<-pmax(x,1e-8);x<-x/sum(x)};setNames(x,tk)}
minvar_w <- function(Sig,tk){library(quadprog);n<-ncol(Sig);Dmat<-Sig+diag(1e-8,n);dvec<-rep(0,n);Amat<-cbind(rep(1,n),diag(n),-diag(n));bvec<-c(1,rep(0,n),rep(-W_CAP,n));sol<-tryCatch(solve.QP(Dmat,dvec,Amat,bvec,meq=1)$solution,error=function(e)rep(1/n,n));sol<-pmax(sol,0);sol<-sol/sum(sol);setNames(sol,tk)}

build_ret_dt <- function(tickers,d,n_days=N_DAYS_COV){sub<-rd[Ticker%in%tickers & Date<d];sub<-sub[order(Date)];kd<-tail(sort(unique(sub$Date)),n_days);sub<-sub[Date%in%kd,.(Date,Ticker,Ret)];sub[!is.na(Ret)]}
select_names <- function(d){a<-alpha[Date==d,.(Ticker,alpha_score,confidence)];if(nrow(a)==0)return(NULL);liq<-rd[Date<d & Ticker%in%a$Ticker];liq<-liq[order(Ticker,Date)];liq20<-liq[,.(avgTV=mean(tail(TV,20),na.rm=TRUE),admin=max(tail(AdminStock,1),0,na.rm=TRUE),halt=max(tail(TradingHalt,1),0,na.rm=TRUE)),by=Ticker];ok<-liq20[avgTV>=LIQ_FLOOR & (is.na(admin)|admin==0)&(is.na(halt)|halt==0),Ticker];a<-a[Ticker%in%ok];if(nrow(a)<10)return(NULL);setorder(a,-alpha_score);head(a,MAX_NAMES)}

get_weights <- function(method, names_dt, d){
  tk<-names_dt$Ticker; ret_dt<-build_ret_dt(tk,d); have<-intersect(tk,unique(ret_dt$Ticker)); tk2<-have; n<-length(tk2)
  if(n<5) return(NULL); a_sub<-names_dt[Ticker%in%tk2]
  w<-switch(method,
    "EW"={setNames(rep(1/n,n),tk2)},
    "MVO"={rm<-dcast(ret_dt[Ticker%in%tk2],Date~Ticker,value.var="Ret");rmat<-as.matrix(rm[,-1]);rmat[is.na(rmat)]<-0;Sig<-tryCatch(corpcor::cov.shrink(rmat,verbose=FALSE),error=function(e)cov(rmat))*252;al<-setNames(a_sub$alpha_score,a_sub$Ticker)[colnames(rmat)];cf<-setNames(a_sub$confidence,a_sub$Ticker)[colnames(rmat)];ww<-tryCatch(mvo_weights(alpha=al,cov_matrix=Sig,confidence=cf,lambda=2.0,psi=0.3,bounds=c(0,W_CAP),max_names=MAX_NAMES,min_names=15L,hhi_cap=0.15,alpha_winsor=2.0),error=function(e)NULL);if(is.null(ww))return(NULL);wv<-ww$weights%||%ww$target_weights%||%ww;if(is.list(wv))wv<-unlist(wv);wv},
    "HRP"={tryCatch(calc_hrp_weights(tk2,ret_dt,n_days=N_DAYS_COV,max_w=W_CAP),error=function(e)NULL)},
    "ERC"={rm<-dcast(ret_dt[Ticker%in%tk2],Date~Ticker,value.var="Ret");rmat<-as.matrix(rm[,-1]);rmat[is.na(rmat)]<-0;Sig<-tryCatch(corpcor::cov.shrink(rmat,verbose=FALSE),error=function(e)cov(rmat));erc_w(Sig,colnames(rmat))},
    "CVaR"={tryCatch(calc_cvar_weights(tk2,ret_dt,n_days=N_DAYS_COV,max_w=W_CAP),error=function(e)NULL)},
    "MinVar"={rm<-dcast(ret_dt[Ticker%in%tk2],Date~Ticker,value.var="Ret");rmat<-as.matrix(rm[,-1]);rmat[is.na(rmat)]<-0;Sig<-tryCatch(corpcor::cov.shrink(rmat,verbose=FALSE),error=function(e)cov(rmat));minvar_w(Sig,colnames(rmat))},
    NULL)
  if(is.null(w)||length(w)==0)return(NULL); w<-w[!is.na(w)]; if(length(w)==0)return(NULL)
  w<-pmax(pmin(w,W_CAP),0); if(sum(w)<=0)return(NULL); w<-w/sum(w)
  it<-0; while(any(w>W_CAP+1e-9)&&it<200){over<-w>W_CAP;ex<-sum(w[over]-W_CAP);w[over]<-W_CAP;und<-!over&w>0;if(!any(und))break;w[und]<-w[und]+ex*w[und]/sum(w[und]);w<-w/sum(w);it<-it+1}
  w/sum(w)
}

# quarterly rebal dates
q_dates <- sig_dates[as.integer(format(sig_dates,"%m")) %in% c(1,4,7,10)]
q_dates <- q_dates[q_dates >= (min(rd$Date)+400)]

# compute weights at each rebal date (sleeve-level)
wlist <- list()
for(d in as.character(q_dates)){dd<-as.Date(d);nm<-select_names(dd);if(is.null(nm)){next};w<-get_weights(sel_method,nm,dd);if(is.null(w)){next};wlist[[d]]<-w}
cat(sprintf("[emit] rebal weight sets computed: %d / %d quarterly dates\n", length(wlist), length(q_dates)))

# monthly carry-forward held weights (drift renormalization between rebals)
rd[, ym := format(Date,"%Y-%m")]
mret <- rd[!is.na(Ret), .(mret=prod(1+Ret)-1), by=.(Ticker,ym)]; setkey(mret, Ticker, ym)
month_to_rebal <- function(m){md<-as.Date(paste0(m,"-01"));cand<-q_dates[q_dates<=(md+31)];if(length(cand)==0)return(NA);max(cand)}

emit <- list()
for(d in sig_dates){
  m <- format(d,"%Y-%m"); rb <- month_to_rebal(m); if(is.na(rb)) next
  w0 <- wlist[[as.character(rb)]]; if(is.null(w0)) next
  # drift from rebal month to current month
  rbm <- format(rb,"%Y-%m")
  months_seq <- format(seq(as.Date(paste0(rbm,"-01")), as.Date(paste0(m,"-01")), by="month"),"%Y-%m")
  w <- w0
  if(length(months_seq) > 1){
    for(mm in months_seq[-1]){
      gr <- mret[ym==mm & Ticker %in% names(w)]
      if(nrow(gr)>0){ g<-setNames(gr$mret,gr$Ticker)[names(w)]; g[is.na(g)]<-0; w<-w*(1+g); w<-w/sum(w) }
    }
  }
  emit[[as.character(d)]] <- data.table(as_of_date=as.character(d),
                                        Ticker=names(w), weight=as.numeric(w),
                                        sleeve="FLOW", rebal_date=as.character(rb),
                                        book_sleeve_alloc=flow_w_book)
}
W <- rbindlist(emit)
# sanity: per-date sum to 1, bounds
chk <- W[, .(s=sum(weight), mx=max(weight), n=.N), by=as_of_date]
cat(sprintf("[emit] dates emitted: %d | Σw range [%.4f, %.4f] | maxw range [%.4f, %.4f] | n range [%d, %d]\n",
            nrow(chk), min(chk$s), max(chk$s), min(chk$mx), max(chk$mx), min(chk$n), max(chk$n)))

# schedule density
sig_count <- length(sig_dates); emit_count <- length(unique(W$as_of_date))
density <- emit_count / sig_count
cat(sprintf("[emit] schedule density = %d/%d = %.4f (mandate >= 0.95: %s)\n",
            emit_count, sig_count, density, density>=0.95))

fwrite(W, file.path(OUT,"weights.csv"))
saveRDS(list(W=W, density=density, sig_count=sig_count, emit_count=emit_count,
             wlist=wlist, sel_method=sel_method, flow_w_book=flow_w_book),
        file.path(OUT,"opt_weights.rds"))
cat("\n[done stage 3 emit]\n")
