## run_dfa_fr_rule_r54.R — R54: FR Track2 배분 규칙을 DFA 21 팩터지수 풀에 적용
## prereg outputs/ramp/dfa_v26_prereg_20260822.json (결과 산출 전 기록됨)
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/portfolio/module_dispatcher.R")

nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}

R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",fac)]
mon<-mon[ym<="2026-07"]; NM<-nrow(mon); NF<-length(fac); NAx<-1+NF

## ── 국면 라벨: 월 d 의 마지막 관측 (월 d 종료 시점에 알 수 있음) → 월 d+1 적용 ──
RG<-as.data.table(read_parquet(".cache/unified_regime_signal_daily.parquet"))
RG[,Date:=as.Date(Date)];RG[,ym:=format(Date,"%Y-%m")];setorder(RG,Date)
rgm<-RG[,.(regime=Category[.N]),by=ym]
mon<-merge(mon,rgm,by="ym",all.x=TRUE); setorder(mon,ym)
mon[!is.finite(match(regime,unique(regime))),regime:=NA]
stopifnot(sum(is.na(mon$regime))==0)   # 라벨 결측 = 조용한 실패 방지
cat(sprintf("[data] 월 %d · 팩터 %d · 국면 분포: %s\n",NM,NF,
  paste(sprintf("%s=%d",names(table(mon$regime)),as.integer(table(mon$regime))),collapse=" ")))

## 모멘텀 신호 (F1 과 동일)
S<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM) S[m,fi]<-prod(1+mon[[fac[fi]]][(m-11):m])/prod(1+mon$Market[(m-11):m])-1
RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
ACT<-RET[,-1,drop=FALSE]-RET[,1]          # active = factor - market
RGM<-mon$regime

## ── FR 규칙 비중 (IS-only, 결정월 d 까지) ──
fr_weights<-function(d,pos=NULL){
  L<-RGM[d]; idx<-1:d
  inL<-idx[RGM[idx]==L]
  jj<-if(is.null(pos)) 1:NF else pos
  ir<-sapply(jj,function(j){a<-ACT[inL,j];a<-a[is.finite(a)]
    if(length(a)<3||sd(a)==0) 0 else mean(a)/sd(a)*sqrt(12)})
  vo<-sapply(jj,function(j){a<-ACT[idx,j];a<-a[is.finite(a)];if(length(a)<3) NA else sd(a)*sqrt(12)})
  nm<-fac[jj]; names(ir)<-nm; names(vo)<-nm
  nr<-setNames(rep(length(inL),length(jj)),nm)
  compute_regime_module_weights(ir,vo,nr)
}

## ── 공통 앙상블 엔진 (F1 골격 승계, 비중 규칙만 인자화) ──
run_ens<-function(rule,K=5,bps=15,dec_lag=1,freq=3,ncoh=3,start0=13){
  pr_c<-matrix(NA_real_,ncoh,NM); to_c<-matrix(NA_real_,ncoh,NM); ns_c<-matrix(NA_real_,ncoh,NM)
  for(cc in 0:(ncoh-1)){ st<-start0+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL
    for(m in st:NM){ d<-m-dec_lag; if(d<1) next
      if(is.null(wcur)||((m-st)%%freq==0)){
        w<-rep(0,NAx)
        if(rule=="F1"||rule=="A1"){
          s<-S[d,]; pos<-which(is.finite(s)&s>0)
          if(!is.na(K)&&length(pos)>K) pos<-pos[order(s[pos],decreasing=TRUE)][1:K]
          if(length(pos)==0){ w[1]<-1; ns_c[cc+1,m]<-0 }
          else { ns_c[cc+1,m]<-length(pos)
            if(rule=="F1") w[1+pos]<-s[pos]/sum(s[pos])
            else { fw<-fr_weights(d,pos); w[1+pos]<-as.numeric(fw[fac[pos]]) } }
        } else {                                   # A2: 21 전부
          fw<-fr_weights(d,NULL); w[1+(1:NF)]<-as.numeric(fw[fac]); ns_c[cc+1,m]<-NF }
        w[!is.finite(w)]<-0; if(sum(w)<=0){w<-rep(0,NAx);w[1]<-1}; w<-w/sum(w); wcur<-w }
      ri<-RET[m,]; dlt<-sum(abs(wcur-wprev)); to_c[cc+1,m]<-dlt
      pr_c[cc+1,m]<-sum(wcur*ri)-(bps/1e4)*dlt
      wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev } }
  pr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  for(m in (start0+ncoh-1):NM) if(all(is.finite(pr_c[,m]))){ pr[m]<-mean(pr_c[,m]); tov[m]<-mean(to_c[,m]) }
  list(pr=pr,tov=tov,nsel=mean(ns_c,na.rm=TRUE)) }

E<-list(full=rep(TRUE,NM), clean=mon$ym>="2015-07")
rep1<-function(r,lab,win){ s<-E[[win]]&is.finite(r$pr); p<-r$pr[s]; a<-p-mon$Market[s]
  nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); cagr<-prod(1+p)^(12/length(p))-1
  cat(sprintf("  %-14s [%-5s] n=%3d | pt=%+.3f IR=%+.3f | calmar=%.3f MDD=%.3f TO=%.2f | 평균보유지수=%.1f\n",
    lab,win,length(p),nwt(a),IRf(a),cagr/abs(mdd),mdd,mean(r$tov[s],na.rm=TRUE)*12,r$nsel)) }

cat("\n=== R54: FR 배분 규칙 대조 (prereg dfa_v26) ===\n")
cat("[헤드라인 사전지정: A2_FR_full vs F1_base, clean, 15bps, dec_lag=1]\n\n")
ARM<-c(F1_base="F1", A1_FR_top5="A1", A2_FR_full="A2")
res<-list(); for(nm in names(ARM)){ res[[nm]]<-run_ens(ARM[[nm]]); for(w in c("full","clean")) rep1(res[[nm]],nm,w) }

cat("\n[대응표본 — 사전지정 판정]\n")
pair<-function(a,b,w){ s<-E[[w]]&is.finite(res[[a]]$pr)&is.finite(res[[b]]$pr)
  d<-(res[[a]]$pr-res[[b]]$pr)[s]
  cat(sprintf("  %-22s %-5s n=%3d mean=%+.4f%%/월 NW-t=%+.3f\n",paste0(a,"-",b),w,sum(s),100*mean(d),nwt(d))) }
for(w in c("full","clean")){ pair("A2_FR_full","F1_base",w); pair("A1_FR_top5","F1_base",w)
  pair("A2_FR_full","A1_FR_top5",w) }

cat("\n[전 셀 전수 보고 — full/clean 창 IR: arm x cost x dec_lag]\n")
cat(sprintf("  %-12s %-5s %-6s %s\n","arm","win","cost","lag0     lag1     lag2     lag3"))
for(nm in names(ARM)) for(w in c("full","clean")) for(bp in c(5,15,25)){
  v<-sapply(0:3,function(dl){r<-run_ens(ARM[[nm]],bps=bp,dec_lag=dl)
    s<-E[[w]]&is.finite(r$pr); IRf((r$pr-mon$Market)[s])})
  cat(sprintf("  %-12s %-5s %-6s %s\n",nm,w,paste0(bp,"bps"),paste(sprintf("%+8.3f",v),collapse=" "))) }
saveRDS(list(res=res,mon=mon,E=E),".cache/_dfa_r54.rds")
cat("\nR54_DONE\n")
