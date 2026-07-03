## ============================================================================
## Iter5 alpha 재산출 — PG2_AS_OF 파라미터화 (임의 월, 새 코드 0)
## sig_date = AS_OF(=T-01). factor_db = 전월말(T-1). regime = cls_thr_q 임베드.
## 팩터 결측 시 hard-stop(fallback 폐기 — stale 대체 금지, 도훈 2026-06-17). 기존행 보존 + AS_OF행 교체.
## 사용: PG2_AS_OF=2026-07-01 Rscript _recompute_alpha_asof.R   (기본 2026-06-01)
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(lubridate)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
ROOT<-Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT,"02_Infrastructure/config.R")); source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(ROOT,"02_Infrastructure/backtest_harness.R"))
AS_OF<-as.Date(Sys.getenv("PG2_AS_OF","2026-06-01"))
SLEEVE_CORE<-c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
SLEEVE_DEF<-c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"); W_CORE<-0.65; W_DEF<-0.35
winsor_z<-function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
cat(sprintf("=== alpha recompute AS_OF=%s ===\n",AS_OF))

## --- regime (cls_thr_q, AS_OF 시점, BM vol/ret/dd/breadth) ---
res<-load_rawdata(use_cache=TRUE);RAW<-res$RAWDATA;BM<-res$BM_DT;rm(res);gc(verbose=F)
BM[,Date:=as.Date(Date)];RAW[,Date:=as.Date(Date)]
brc<-if("BM_Ret"%in%names(BM))"BM_Ret" else "Ret"
brd<-RAW[!is.na(Ret),.(b=mean(Ret>0,na.rm=T)),by=Date];setkey(brd,Date)
CUT<-AS_OF-1L  # 전월말 데이터까지
me<-BM[Date<=CUT,.(me=max(Date)),by=.(YM=format(Date,"%Y-%m"))]$me; me<-sort(unique(me))
bf<-function(m){w<-BM[Date<=m & Date>m-90];if(nrow(w)<30)return(NULL);rv<-sd(w[[brc]],na.rm=T)*sqrt(252)
  mc<-BM[Date==m,BM_Close][1];pm<-BM[format(Date,"%Y-%m")!=format(m,"%Y-%m") & Date<m,max(Date)];pc<-BM[Date==pm,BM_Close][1]
  r1<-if(!is.na(mc)&&!is.na(pc)&&pc>0)mc/pc-1 else NA_real_
  w2<-BM[Date<=m & Date>m-380];dd<-if(nrow(w2)<20)NA_real_ else{px<-cumprod(1+w2[[brc]]);min(px/cummax(px)-1,na.rm=T)}
  b6<-brd[Date<=m & Date>m-90,mean(b,na.rm=T)];data.table(me=m,rv=rv,r1=r1,dd=dd,b6=b6)}
rf<-rbindlist(lapply(me,bf),fill=T);rf<-rf[!is.na(rv)&!is.na(dd)];setorder(rf,me)
ep<-function(x){n<-length(x);o<-rep(NA_real_,n);for(i in seq_len(n)){if(i==1){o[i]<-.5;next};p<-x[seq_len(i-1)];p<-p[is.finite(p)];o[i]<-if(length(p)<6).5 else mean(p<=x[i],na.rm=T)};o}
rf[,sc:=.35*ep(rv)+.25*ep(-r1)+.25*ep(-dd)+.15*ep(-b6)]
cl<-function(s,q=c(.30,.65,.85)){n<-length(s);o<-character(n);for(i in seq_len(n)){if(i<12){o[i]<-"NORMAL";next};p<-s[seq_len(i-1)];p<-p[is.finite(p)];if(length(p)<12){o[i]<-"NORMAL";next};t<-quantile(p,q,na.rm=T);o[i]<-if(s[i]<=t[1])"BULL" else if(s[i]<=t[2])"NORMAL" else if(s[i]<=t[3])"CAUTION" else "CRISIS"};o}
rf[,rs:=cl(sc)];rf[,sig:=as.Date(paste0(format(me,"%Y-%m"),"-01"))%m+%months(1)]
setorder(rf,sig,-me);rf<-rf[,.SD[1],by=sig]
REGIME<-rf[sig==AS_OF,rs]; if(!length(REGIME))REGIME<-"NORMAL"
cat(sprintf("[regime] AS_OF=%s → %s\n",AS_OF,REGIME))

## --- alpha: factor_db_{T-1} + M08 fallback ---
ym<-format(AS_OF-1,"%Y%m")
fdp<-file.path(ROOT,sprintf(".cache/factor_db/factor_db_%s.parquet",ym))
ic<-as.data.table(read_parquet(file.path(ROOT,".cache/factor_db/factor_ic_monthly.parquet")));ic[,Date:=as.Date(Date)];ic[,Usable_Date:=as.Date(Usable_Date)]
icm<-ic[Usable_Date<AS_OF & !is.na(IC) & Factor_Name %in% SLEEVE_CORE,.(m=mean(IC,na.rm=T)),by=Factor_Name]
tc<-setNames(rep(0,4),SLEEVE_CORE);for(f in icm$Factor_Name)tc[f]<-max(icm[Factor_Name==f,m],0);tc<-tc/sum(abs(tc))
td<-setNames(rep(1/3,3),SLEEVE_DEF)
rdf<-function(p,fac){f<-as.data.table(read_parquet(p,col_select=c("Ticker","Factor_Name","Z_Score","Coverage")));f[Factor_Name%in%fac & Coverage==TRUE & !is.na(Z_Score),.(Ticker,Factor_Name,Z_Score)]}
base<-rdf(fdp,c(SLEEVE_CORE,"Q07_Earnings_Stability","Q25_Ohlson_O"))
m08<-rdf(fdp,"M08_Residual_Mom")
fdb<-rbind(base,m08);fdb[,sig_date:=AS_OF]
# [2026-06-17 도훈] fallback 폐기 — stale(직전월) 데이터 조용히 쓰던 로직 삭제.
# 결정월(T)엔 전월말(T-1) factor_db만 사용. 결측 시 명시 중단 → 데이터 먼저 수리(PIT 준수).
.missing<-setdiff(c(SLEEVE_CORE,SLEEVE_DEF), unique(fdb$Factor_Name))
if(length(.missing)) stop(sprintf("[FATAL] factor_db_%s 결측 팩터: %s — fallback 없음(폐기). 먼저 factor_db_%s 완성 필요(M08은 benchmark BM_Ret join → compute_momentum). stale 대체 금지 = PIT.", ym, paste(.missing,collapse=","), ym))
cat(sprintf("[factor_db_%s] %d rows | %s\n",ym,nrow(fdb),paste(sort(unique(fdb$Factor_Name)),collapse=",")))
fa<-align_factor_direction(fdb,.load_registry(),sig_date=AS_OF,min_ic_months=12L)
if("Z_Score_Aligned"%in%names(fa))fa[,Z_Score:=Z_Score_Aligned]
fw<-dcast(fa,sig_date+Ticker~Factor_Name,value.var="Z_Score",fill=NA_real_)
RAW[,TV:=Close*Vol];RAW[order(Date),A:=frollmean(TV,20L,align="right"),by=Ticker];RAW[order(Date),AvgTV20:=shift(A,1L),by=Ticker]
pc<-RAW[Date<=CUT,max(Date)];liq<-RAW[Date==pc & !is.na(AvgTV20) & AvgTV20>=2e8,.(Ticker)];fw<-merge(fw,liq,by="Ticker")
k2<-as.data.table(read_parquet(file.path(ROOT,".cache/universe_support/us_k200.parquet")));k2[,Date:=as.Date(Date)]
kq<-as.data.table(read_parquet(file.path(ROOT,".cache/universe_support/us_kq150.parquet")));kq[,Date:=as.Date(Date)]
uni<-unique(c(k2[Date==k2[Date<=CUT,max(Date)]&K200==1,Ticker],kq[Date==kq[Date<=CUT,max(Date)]&KQ150==1,Ticker]));fw<-fw[Ticker%in%uni]
agg<-function(df,fc,w){fc<-intersect(intersect(names(w),fc),names(df));W<-as.numeric(w[fc]);W<-W/sum(W);X<-as.matrix(df[,..fc]);X<-apply(X,2,winsor_z);X[is.na(X)]<-0;as.numeric(X%*%W)}
fw[,Sc:=agg(.SD,SLEEVE_CORE,tc)];fw[,Sd:=agg(.SD,SLEEVE_DEF,td)]
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
fw[,Scz:=zc(Sc)];fw[,Sdz:=zc(Sd)];fw[,score_eff:=W_CORE*Scz+W_DEF*Sdz]
na<-fw[,.(Date=sig_date,Ticker,score_eff,score_core_z=Scz,score_defense_z=Sdz,Ret_1m=NA_real_,regime_state=REGIME,
  theta_core=toJSON(as.list(round(tc,4)),auto_unbox=T),theta_defense=toJSON(as.list(round(td,4)),auto_unbox=T))]
ap<-file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet");ex<-as.data.table(read_parquet(ap));ex[,Date:=as.Date(Date)]
ex[,theta_core:=as.character(theta_core)];ex[,theta_defense:=as.character(theta_defense)];na[,theta_core:=as.character(theta_core)];na[,theta_defense:=as.character(theta_defense)]
mg<-rbind(ex[Date!=AS_OF],na,use.names=T,fill=T);setkey(mg,Date,Ticker)
.t<-paste0(ap,".tmp");write_parquet(mg,.t);if(file.exists(ap))file.remove(ap);file.rename(.t,ap)
cat(sprintf("[write] alpha %s 행 교체(%d종목, regime=%s). %s~%s sig_dates=%d\n",AS_OF,nrow(na),REGIME,min(mg$Date),max(mg$Date),uniqueN(mg$Date)))
