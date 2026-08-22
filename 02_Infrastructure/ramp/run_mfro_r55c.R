## run_mfro_r55c.R — R55c: **진짜 상한** + 전이 손실 분해
## ★R55b 가 드러낸 설계 오류: '지수 active 의 완전예지' 는 이 구성의 상한이 아니다.
##   최적화 대상은 **종목 꼬리 25종의 active** 인데 oracle 은 **지수 active** 를 예지했다(rho 0.34 = 부분 매핑).
##   부분 상관 표적을 완전예지해도 상한이 아니며, 회전만 늘어 오히려 나빠진다.
##   ⇒ 상한은 **결과 자체**(꼬리 active)를 예지해야 한다.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}
UB<-0.20;LAMBDA<-1.5;N_TARGET<-25L;LIQ<-2e8
.norm<-function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub
  for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt<-function(a,lam=LAMBDA,lb=0,ub=UB){if(!length(a))return(numeric(0))
  z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}
P<-as.data.table(read_parquet("outputs/ramp/mfro_panel.parquet"))
FK<-c("Value","Issuance","Size","Momentum","ResidMom","Reversal","Quality","GPA","EarnStab",
      "Growth","Investment","LowVol","LowBeta","TailRisk","Liquidity","Accrual","Consensus",
      "SUE","Crowding","ForeignFlow","SmartMoney");NF<-length(FK)
P<-P[is.finite(adv20)&adv20>=LIQ];setorder(P,ym);YM<-sort(unique(P$ym));NM<-length(YM)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
mi<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",FK)]
setorder(mi,ym)
bm<-mi$Market[match(YM,mi$ym)];bmf<-c(bm[-1],NA_real_)
E<-list(full=rep(TRUE,NM),clean=YM>="2015-07")

## ── 팩터별 '꼬리 25종' 익월 active 를 전 월 산출 (상한·전이의 공통 재료) ──
TA<-matrix(NA_real_,NM,NF);dimnames(TA)<-list(YM,FK)
for(m in seq_len(NM)){ D<-P[ym==YM[m]]; if(nrow(D)<N_TARGET)next
  fr0<-D$fwd_ret; fr0[!is.finite(fr0)]<-0
  for(j in 1:NF){ z<-D[[FK[j]]]; if(sum(is.finite(z))<N_TARGET)next
    o<-order(-z);idx<-o[seq_len(N_TARGET)];w<-.tilt(z[idx])
    TA[m,j]<-sum(w*fr0[idx])-bmf[m] } }
S<-matrix(NA_real_,nrow(mi),NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF) for(m in 12:nrow(mi)) S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1

zmean<-function(D,cols){if(!length(cols))return(rep(NA_real_,nrow(D)));rowMeans(as.matrix(D[,cols,with=FALSE]),na.rm=TRUE)}
## sel: "trailing"(실현) / "idx_oracle"(지수 예지) / "tail_oracle"(★결과 예지 = 진짜 상한)
pick<-function(m,k,sel){
  if(sel=="trailing"){r<-match(YM[m-1],rownames(S));if(is.na(r))return(character(0));s<-S[r,]}
  else if(sel=="idx_oracle"){r<-match(YM[m],rownames(S));if(is.na(r)||r>=nrow(S))return(character(0))
    s<-sapply(1:NF,function(j)mi[[FK[j]]][r+1]-mi$Market[r+1]);names(s)<-FK}
  else {s<-TA[m,]}
  pos<-which(is.finite(s)&s>0);if(!length(pos))return(character(0))
  FK[pos[order(s[pos],decreasing=TRUE)][seq_len(min(k,length(pos)))]] }
run<-function(mode,sel,k=5L,bps=15){
  pr<-rep(NA_real_,NM);tov<-rep(NA_real_,NM);wprev<-NULL
  for(m in 2:NM){ D<-P[ym==YM[m]];if(nrow(D)<N_TARGET)next
    wk<-pick(m,k,sel);if(!length(wk))wk<-FK
    bs<-zmean(D,FK)
    if(mode=="weight_only"){o<-order(-bs);idx<-o[seq_len(N_TARGET)];w<-.tilt(zmean(D,wk)[idx])}
    else{rs<-zmean(D,wk);o<-order(-rs);idx<-o[seq_len(N_TARGET)];w<-.tilt(rs[idx])}
    tk<-D$Ticker[idx];names(w)<-tk
    at<-union(names(wprev),tk);a<-setNames(rep(0,length(at)),at);b<-a
    if(!is.null(wprev))a[names(wprev)]<-wprev;b[tk]<-w
    dl<-sum(abs(b-a));tov[m]<-dl
    fr<-D$fwd_ret[idx];fr[!is.finite(fr)]<-0
    pr[m]<-sum(w*fr)-(bps/1e4)*dl
    wd<-w*(1+fr);wprev<-wd/sum(wd)}
  list(pr=pr,tov=tov)}

cat("=== R55c: 진짜 상한 (결과-예지) vs 신호-예지 vs 실현 ===\n")
AR<-list()
for(md in c("weight_only","sel_weight")) for(sl in c("trailing","idx_oracle","tail_oracle"))
  AR[[paste0(substr(md,1,1),"_",sl)]]<-run(md,sl)
for(n in names(AR)) for(w in c("full","clean")){r<-AR[[n]];s<-E[[w]]&is.finite(r$pr)&is.finite(bmf)
  cat(sprintf("  %-20s [%-5s] IR=%+.3f pt=%+.3f TO=%.1f\n",n,w,IRf((r$pr-bmf)[s]),nwt((r$pr-bmf)[s]),mean(r$tov[s],na.rm=TRUE)*12))}
cat("\n[★상한 대비 — 실현이 상한의 몇 %를 회수하나]\n")
for(md in c("w","s")) for(w in c("full","clean")){
  tr<-AR[[paste0(md,"_trailing")]]$pr; io<-AR[[paste0(md,"_idx_oracle")]]$pr; to<-AR[[paste0(md,"_tail_oracle")]]$pr
  s<-E[[w]]&is.finite(tr)&is.finite(to)&is.finite(io)&is.finite(bmf)
  a_tr<-mean((tr-bmf)[s]);a_io<-mean((io-bmf)[s]);a_to<-mean((to-bmf)[s])
  cat(sprintf("  %s %-5s | 실현 %+.4f · 지수예지 %+.4f · ★결과예지 %+.4f (%%/월)  ⇒ 회수율 %.1f%% | 결과예지-실현 NW-t=%+.3f\n",
    ifelse(md=="w","비중만  ","선택+비중"),w,100*a_tr,100*a_io,100*a_to,
    ifelse(a_to>0,100*a_tr/a_to,NA_real_),nwt((to-tr)[s])))}

cat("\n=== 전이 손실 분해: 지수 active vs 꼬리 active ===\n")
IA<-matrix(NA_real_,NM,NF);dimnames(IA)<-list(YM,FK)
for(j in 1:NF){r<-match(YM,mi$ym);IA[,j]<-ifelse(is.na(r)|r>=nrow(mi),NA_real_,mi[[FK[j]]][pmin(r+1,nrow(mi))]-mi$Market[pmin(r+1,nrow(mi))])}
for(w in c("full","clean")){ sel<-E[[w]]
  ta<-as.vector(TA[sel,]);ia<-as.vector(IA[sel,]);ok<-is.finite(ta)&is.finite(ia)
  cat(sprintf("  [%-5s] n=%d | 꼬리 평균 %+.4f%%/월 · 지수 평균 %+.4f%%/월 · **수준 갭 %+.4f%%/월 (%+.1f%%/yr)**\n",
    w,sum(ok),100*mean(ta[ok]),100*mean(ia[ok]),100*(mean(ta[ok])-mean(ia[ok])),1200*(mean(ta[ok])-mean(ia[ok]))))
  ## 월내 횡단면: 지수 active 순위가 꼬리 active 순위를 맞히나
  rs<-sapply(which(sel),function(m){x<-IA[m,];y<-TA[m,];o<-is.finite(x)&is.finite(y)
    if(sum(o)<5)return(NA_real_);cor(rank(x[o]),rank(y[o]))})
  rs<-rs[is.finite(rs)]
  cat(sprintf("           월내 횡단면 순위상관: 평균 %+.4f · NW-t %+.3f · 양수월 %.1f%%\n",mean(rs),nwt(rs),100*mean(rs>0)))}
saveRDS(list(AR=AR,TA=TA,IA=IA,YM=YM,E=E,bmf=bmf),".cache/_mfro_r55c.rds")
cat("\nR55C_DONE\n")
