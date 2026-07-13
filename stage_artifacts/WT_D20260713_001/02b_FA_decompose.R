#==============================================================================
# WT-D20260713_001 R17 — Step 02b: F-A single-metric decomposition (cos-only / jac-only)
# 단일지표 분해 원칙 (Phase A 교훈: 합성이 유일 신호를 은폐/역전하는지 확인)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(stringi) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT<-file.path(ROOT,"stage_artifacts/WT_D20260711_002"); OUT<-file.path(ROOT,"stage_artifacts/WT_D20260713_001")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
ym2date<-function(ym) as.Date(sprintf("%d-%02d-01",ym%/%100L,ym%%100L))
ym_add<-function(ym,k){y<-ym%/%100L;m<-ym%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
dt2ym<-function(d){d<-as.Date(d);as.integer(format(d,"%Y"))*100L+as.integer(format(d,"%m"))}
mp<-readRDS(file.path(WT,"monthly_panel.rds"));me<-mp$me;memb<-me[K200==TRUE|KQ150==TRUE,.(Ticker,ym)];setkey(memb,ym,Ticker)
pan<-readRDS(file.path(OUT,"panels.rds"))
expand_hold<-function(sig,H){sig<-sig[is.finite(raw)];sig[,us:=ym_add(rcept_ym,1L)]
  rows<-sig[,{dm<-vapply(0:(H-1L),function(k)ym_add(us,k),integer(1));.(decision_ym=dm,raw=raw,rcept_ym=rcept_ym)},by=.(Ticker,seq_len(nrow(sig)))]
  rows[,seq_len:=NULL];setorder(rows,Ticker,decision_ym,-rcept_ym);rows<-rows[,.SD[1L],by=.(Ticker,decision_ym)];rows[,.(Ticker,ym=decision_ym,raw)]}
make_scores<-function(sm,sign){x<-merge(sm,memb,by=c("Ticker","ym"));zc<-function(v){s<-sd(v,na.rm=TRUE);if(!is.finite(s)||s<=0)return(rep(NA_real_,length(v)));(v-mean(v,na.rm=TRUE))/s}
  x[,z:=zc(raw),by=ym];x<-x[is.finite(z)];x[,.(Date=ym2date(ym),Ticker,score=sign*z)]}
run_canon<-function(sc,tag)canonical_screen_bt(sc,pan$returns_all,pan$bench_all,top_n=25L,cost_bps_oneway=15,
  liq_dt=pan$liq_all,liq_min=2e8,size_dt=pan$size_all,diag_dual_basis=TRUE,run_id=tag,strategy_id=tag)

tc<-readRDS(file.path(WT,"text_cache_all.rds"));tc<-tc[!is.na(section_head)&nchar(section_head)>=300&status%in%c("ok","OK")];setorder(tc,Ticker,fy)
tc[,ng:=lapply(section_head,function(s){s2<-gsub("\\s+","",s);n<-nchar(s2);if(n<5L)return(character(0));stri_sub(s2,1:(n-4L),length=5L)})]
cos_ng<-function(a,b){if(length(a)==0||length(b)==0)return(NA_real_);ta<-table(a);tb<-table(b);k<-union(names(ta),names(tb))
  va<-as.numeric(ta[k]);va[is.na(va)]<-0;vb<-as.numeric(tb[k]);vb[is.na(vb)]<-0;d<-sqrt(sum(va^2))*sqrt(sum(vb^2));if(d<=0)return(NA_real_);sum(va*vb)/d}
fa<-tc[,{o<-NULL;if(.N>=2)for(i in 2:.N)if(fy[i]-fy[i-1]==1L){a<-ng[[i]];b<-ng[[i-1]]
    jac<-length(intersect(a,b))/length(union(a,b));cos<-cos_ng(a,b);rc<-as.Date(as.character(rcept_dt[i]),"%Y%m%d")
    o<-rbind(o,data.table(cos=cos,jac=jac,rcept_ym=dt2ym(rc)))};if(is.null(o))o<-data.table(cos=numeric(0),jac=numeric(0),rcept_ym=integer(0));o},by=Ticker]
cat("[02b] cos-jac cor:",round(cor(fa$cos,fa$jac,use="complete.obs"),3),
    " cos q:",paste(round(quantile(fa$cos,c(0,.5,1),na.rm=TRUE),3),collapse=","),
    " jac q:",paste(round(quantile(fa$jac,c(0,.5,1),na.rm=TRUE),3),collapse=","),"\n")
sc_cos<-make_scores(expand_hold(fa[,.(Ticker,rcept_ym,raw=cos)],12L),+1)
sc_jac<-make_scores(expand_hold(fa[,.(Ticker,rcept_ym,raw=jac)],12L),+1)
cc<-run_canon(sc_cos,"FA_cosonly");cj<-run_canon(sc_jac,"FA_jaconly")
cat(sprintf("[02b] F-A cos-only : cap-w PORT_t %.2f  EW-uni t %.2f  EWpost2017 %.2f\n",cc$portfolio_alpha_t_nw_lag3,cc$diag_ew_universe$portfolio_alpha_t_nw_lag3,cc$diag_ew_universe$post2017_t_nw_lag3))
cat(sprintf("[02b] F-A jac-only : cap-w PORT_t %.2f  EW-uni t %.2f  EWpost2017 %.2f\n",cj$portfolio_alpha_t_nw_lag3,cj$diag_ew_universe$portfolio_alpha_t_nw_lag3,cj$diag_ew_universe$post2017_t_nw_lag3))
# also test INVERTED sign (changers-short = high-sim-long is CMN; check if KR sign flips)
sc_inv<-make_scores(expand_hold(fa[,.(Ticker,rcept_ym,raw=0.5*cos+0.5*jac)],12L),-1)
ci<-run_canon(sc_inv,"FA_inverted")
cat(sprintf("[02b] F-A INVERTED (low-sim long): cap-w PORT_t %.2f  EW-uni t %.2f\n",ci$portfolio_alpha_t_nw_lag3,ci$diag_ew_universe$portfolio_alpha_t_nw_lag3))
cat("[02b] DONE\n")
