suppressWarnings(suppressMessages({library(data.table); library(arrow); library(quadprog); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o1 <- readRDS(file.path(OUT,"op1_objects.rds")); A<-o1$A; BM<-o1$BM; DTS<-o1$DTS
source(file.path(OUT,"op3_sigma_mod.R"))
CVEC <- { cj <- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"))$confidence_vector
          setNames(as.numeric(unlist(cj)), names(cj)) }
COST_BPS<-0.0015; LAM<-2.0; PSI<-0.3; PHI<-0.00405
source(file.path(OUT,"op4_core.R")); FLR<-new.env(); FLR$n<-c(); FLR$rat<-c()

emit_run <- function(selfun){
  prev<-setNames(numeric(0),character(0)); wl<-list(); rows<-list(); k<-0L
  for(i in seq_along(DTS)){
    dd<-DTS[i]; x<-A[Date==dd]
    tk<-selfun(x,prev); w<-setNames(rep(1/length(tk),length(tk)),tk)
    xo <- x[order(-fh_lag1d,Ticker)]
    wl[[i]]<-data.table(as_of_date=dd,Ticker=names(w),weight=as.numeric(w),
                        rank_proximity=match(names(w),xo$Ticker))
    r<-x$Ret_1m[match(names(w),x$Ticker)]; if(!all(is.finite(r))) next
    pg<-sum(w*r); k<-k+1L
    allt<-union(names(prev),names(w)); a<-setNames(numeric(length(allt)),allt); a[names(prev)]<-prev
    b<-setNames(numeric(length(allt)),allt); b[names(w)]<-w; dw<-b-a
    adv<-x$adv[match(allt,x$Ticker)]; trd<-abs(dw)>1e-8
    rows[[k]]<-data.table(signal_date=dd,n=length(w),ret_gross=pg,traded=sum(abs(dw)),
      cost=COST_BPS*sum(abs(dw)),ret_net=pg-COST_BPS*sum(abs(dw)),bm=BM$BM_Ret[match(dd,BM$Date)],
      hhi=sum(w^2),cap_aum=min(0.10*adv[trd]/abs(dw)[trd],na.rm=TRUE),n_new=sum(!names(w)%in%names(prev)))
    prev<-setNames(w*(1+r)/(1+pg),names(w))
  }
  list(perf=rbindlist(rows), weights=rbindlist(wl))
}
SEL_B <- 50L
SEL <- emit_run(mk_selbuf(SEL_B)); BASE <- emit_run(sel_top)
SELP<-SEL$perf; SELW<-SEL$weights; m1<-BASE$perf
cat("weights dates:",length(unique(SELW$as_of_date))," backtest months:",nrow(SELP),
    " last:",as.character(max(SELW$as_of_date)),"\n")
fs <- function(p,lab){ act<-p$ret_net-p$bm
  data.table(method=lab,months=nrow(p),to_2way=mean(p$traded)*12,
    net_ir=mean(act)*12/(sd(act)*sqrt(12)),active_ann=mean(act)*12,
    gross_active_ann=mean(p$ret_gross-p$bm)*12,
    net_cagr=prod(1+p$ret_net)^(12/nrow(p))-1,net_sr=mean(p$ret_net)*12/(sd(p$ret_net)*sqrt(12)),
    cost_ann=mean(p$cost)*12,cap_med=median(p$cap_aum,na.rm=TRUE)/1e8,
    cap_p10=quantile(p$cap_aum,.10,na.rm=TRUE)/1e8, cap_12m=median(tail(p$cap_aum,12),na.rm=TRUE)/1e8,
    beta=as.numeric(coef(lm(p$ret_net~p$bm))[2])) }
FS <- rbind(fs(m1,"M1_EW25_base"), fs(SELP,"M2_EW25_buffer50"))
print(FS)
csens <- rbindlist(lapply(c(15,40.5,50,60)/10000,function(cb){
  a1<-(m1$ret_gross-cb*m1$traded)-m1$bm; a2<-(SELP$ret_gross-cb*SELP$traded)-SELP$bm
  data.table(bps=cb*10000,M1_active=mean(a1)*12,M1_netir=mean(a1)*12/(sd(a1)*sqrt(12)),
             SEL_active=mean(a2)*12,SEL_netir=mean(a2)*12/(sd(a2)*sqrt(12)))}))
print(csens)
saveRDS(list(SELP=SELP,SELW=SELW,FS=FS,csens=csens,m1=m1,BASEW=BASE$weights),file.path(OUT,"op6_objects.rds"))
