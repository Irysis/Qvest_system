## run_search2_book.R — 옵션2: Book score를 factor로 흡수해 8-comp grid 재최적화 (25종목 준수 단일 top-25).
## Book score_eff를 *예측월 정렬*(PIT 수정)해 factor BOOK 추가. grid가 regime-조건부로 BOOK↔모멘텀 가중. vs Book 단독.
suppressPackageStartupMessages({library(data.table); library(arrow)}); setDTthreads(1); setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/contracts/canonical_screen_bt.R"); suppressMessages({library(sandwich);library(lmtest)})
C<-readRDS(".cache/_search_cache.rds");FN<-C$FN;dts<-C$dts;ND<-C$ND;ACT<-C$ACT;IC<-C$IC;SIG<-C$SIG;fwd_ret<-C$fwd_ret;bench<-C$bench;liq<-C$liq;UNI<-C$UNI
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)};calf<-function(r){nav<-cumprod(1+r);cagr<-prod(1+r)^(12/length(r))-1;cagr/abs(min(nav/cummax(nav)-1))}
oosr<-function(act){n<-length(act);median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)}
csna<-function(x){x[!is.finite(x)]<-0;cumsum(x)};lagv<-function(x)c(NA,x[-length(x)]);zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
ny<-function(d){m<-as.integer(format(d,"%m"));y<-as.integer(format(d,"%Y"));sprintf("%04d-%02d",ifelse(m==12,y+1,y),ifelse(m==12,1,m+1))}

## Book factor: score_eff를 예측월(ny) 정렬 → book_z per month. book_IC = rank-IC(score, fwd ret)
bk<-as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))[,.(ym=format(as.Date(Date),"%Y-%m"),Ticker,se=score_eff)]
bk<-bk[is.finite(se)]
BOOKz<-vector("list",ND);bookIC<-rep(NA_real_,ND);bookACT<-rep(NA_real_,ND)
for(i in seq_len(ND)){tgt<-ny(dts[i]);b<-bk[ym==tgt,.(Ticker,bz=zc(se))];BOOKz[[i]]<-b
  fr<-fwd_ret[Date==dts[i],.(Ticker,Ret_1m)];mb<-merge(b,fr,by="Ticker");mb<-merge(mb,UNI[Date==dts[i]],by="Ticker")
  if(nrow(mb)>=20&&sd(mb$bz)>0&&sd(mb$Ret_1m)>0)bookIC[i]<-cor(mb$bz,mb$Ret_1m,method="spearman")
  sel<-mb[bz>=quantile(bz,2/3,na.rm=T)]$Ticker;rs<-fwd_ret[Date==dts[i]&Ticker%in%sel,Ret_1m];br<-bench[Date==dts[i],BM_Ret];if(length(rs)>=5)bookACT[i]<-mean(rs)-ifelse(length(br),br,0)}
FN2<-c(FN,"BOOK");IC2<-cbind(IC,BOOK=bookIC);ACT2<-cbind(ACT,BOOK=bookACT)
## ZC 행렬에 BOOK 추가
ZC<-vector("list",ND);for(i in seq_len(ND)){fw<-C$ZL[[as.character(dts[i])]];tk<-fw$Ticker;M<-matrix(0,length(tk),length(FN2),dimnames=list(tk,FN2))
  for(j in seq_along(FN)){id<-C$FAC[FN[j]];if(id%in%names(fw)){z<-zc(fw[[id]]);z[!is.finite(z)]<-0;M[,j]<-z}}
  b<-BOOKz[[i]];if(nrow(b)>0){idx<-match(tk,b$Ticker);bz<-b$bz[idx];bz[!is.finite(bz)]<-0;M[,"BOOK"]<-bz};ZC[[i]]<-M}
UNIVS<-list(book_momcons=c("M05_Trended_Mom","M32_CompMomV2","M09_CompMom","M13_VolAdjMom","M01_Mom121","M08_ResidMom","C04_ESBR","C19_CompEarn","BOOK"),
  book_mom=c("M05_Trended_Mom","M32_CompMomV2","M09_CompMom","M13_VolAdjMom","M01_Mom121","M08_ResidMom","BOOK"),
  book_only=c("BOOK"), book_all=c(FN,"BOOK"))
membership<-function(regime,tau){a3<-c(-1,0,1)/tau;sm<-function(z,a)t(sapply(z,function(zz){e<-exp(a*zz);e/sum(e)}));if(regime=="none")return(matrix(1,ND,1));s<-switch(regime,trend=SIG$trend,cascade=SIG$cascade,vol=SIG$vol,SIG$trend);sm(s,a3)}
build_W<-function(MEM,perf,shrink,fidx){NS<-ncol(MEM);Fn<-length(fidx);W<-matrix(0,ND,Fn);PV<-if(perf=="ic")IC2[,fidx,drop=FALSE] else ACT2[,fidx,drop=FALSE]
  for(s in 1:NS){ms<-MEM[,s];for(jj in seq_len(Fn)){pv<-PV[,jj];fin<-is.finite(pv);ws<-lagv(csna(ms*ifelse(fin,pv,0)));wc<-lagv(csna(ms*fin));fs<-lagv(csna(ifelse(fin,pv,0)));fc<-lagv(csna(fin))
    Cst<-ws/pmax(wc,1e-9);Cfu<-fs/pmax(fc,1e-9);lam<-shrink/(wc+shrink);lam[!is.finite(lam)]<-1;Csh<-(1-lam)*Cst+lam*Cfu;Csh[!is.finite(Csh)]<-0;W[,jj]<-W[,jj]+ms*pmax(Csh,0)}}
  W[1:36,]<-1;W}
eval_cfg<-function(regime,tau,perf,shrink,univ){fidx<-match(UNIVS[[univ]],FN2);fidx<-fidx[!is.na(fidx)];MEM<-membership(regime,tau);W<-build_W(MEM,perf,shrink,fidx)
  rows<-vector("list",ND);for(i in seq_len(ND)){wf<-W[i,];if(sum(wf)<1e-9)wf<-rep(1,length(fidx));wf<-wf/sum(wf);X<-ZC[[i]][,fidx,drop=FALSE];rows[[i]]<-data.table(Date=dts[i],Ticker=rownames(ZC[[i]]),score=as.numeric(X%*%wf))}
  SC<-merge(rbindlist(rows),UNI,by=c("Date","Ticker"));cs<-tryCatch(canonical_screen_bt(SC[,.(Date,Ticker,score)],fwd_ret,bench,top_n=25L,cost_bps_oneway=15,liq_dt=liq,liq_min=2e8,run_id="s2",strategy_id="s2"),error=function(e)NULL)
  if(is.null(cs$period_returns))return(NULL);pr<-as.data.table(cs$period_returns);setorder(pr,date);act<-pr$ret_net-pr$benchmark_ret;n<-nrow(pr);k<-floor(n*0.6)
  data.table(regime=regime,perf=perf,shrink=shrink,univ=univ,n=n,pt=nwt(act),pt_OOS=nwt(act[(k+1):n]),oos_ret=oosr(act),SR=IRf(pr$ret_net),calmar=calf(pr$ret_net),TO=cs$turnover_annual)}
## Book 단독(같은 256mo, gross) 기준
bkret<-merge(data.table(date=dts,book=C$book),data.table(date=dts,bm=merge(data.table(Date=dts),bench,by="Date",all.x=T)$BM_Ret),by="date")[is.finite(book)&is.finite(bm)]
cat(sprintf("=== Book 단독(256mo gross): pt %.2f SR %.2f calmar %.2f ===\n",nwt(bkret$book-bkret$bm),IRf(bkret$book),calf(bkret$book)))
grid<-CJ(regime=c("trend","cascade","none","vol"),perf=c("ic","active"),shrink=c(0,8),univ=c("book_momcons","book_mom","book_only","book_all"),sorted=FALSE)
out<-list();for(gi in seq_len(nrow(grid))){g<-grid[gi];r<-tryCatch(eval_cfg(g$regime,1,g$perf,g$shrink,g$univ),error=function(e)NULL);if(!is.null(r))out[[length(out)+1]]<-r}
R<-rbindlist(out,fill=TRUE);setorder(R,-pt)
cat("=== 옵션2 재최적화 (Book factor 흡수, 단일 top-25 25종목준수) — pt 상위 ===\n")
cat(sprintf("  %-7s %-7s %3s %-13s %4s %6s %7s %7s %5s %6s\n","regime","perf","shr","univ","n","pt","pt_OOS","oos_ret","SR","calmar"))
for(i in seq_len(min(12,nrow(R)))){r<-R[i];cat(sprintf("  %-7s %-7s %3d %-13s %4d %6.2f %7.2f %7.2f %5.2f %6.2f\n",r$regime,r$perf,r$shrink,r$univ,r$n,r$pt,r$pt_OOS,r$oos_ret,r$SR,r$calmar))}
saveRDS(R,".cache/_search2_book.rds");cat("SEARCH2_DONE\n")
