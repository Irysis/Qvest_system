## probe_a5_breakeven.R — 기전 확정: 신선도 감쇠율 · 손익분기 bps · 기전이 예측하는 함의 검정
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
OUTD<-"stage_artifacts/probe_a5_20260822"; set.seed(20260822)
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
load_mon<-function(path){ R<-as.data.table(read_parquet(path)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
  fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market")); R[,ym:=format(Date,"%Y-%m")]
  mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
  setorder(mon,medate); list(mon=mon,fac=fac) }
BR<-load_mon("outputs/ramp/dfa_index_returns_broad_202608.parquet")
mon<-BR$mon; fac<-BR$fac; NM<-nrow(mon); NAx<-1+length(fac)
mk_sig<-function(win=12){ S<-matrix(NA_real_,NM,length(fac)); colnames(S)<-fac
  for(fi in seq_along(fac)){f<-fac[fi]; for(m in win:NM){w<-(m-win+1):m
    S[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1}}; S }
S12<-mk_sig(12)
tgt<-function(d){ s<-S12[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
  if(!length(pos))w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); w }

## lambda: 부분 리밸 (1=완전 복귀, 0=무거래). freq/phase 는 결정 주기.
run4<-function(bps=15,freq=1,phase=0,lambda=1,start_m=13){
  pr<-rep(NA_real_,NM); gr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  wprev<-rep(1/NAx,NAx); wcur<-NULL; wtar<-NULL
  for(m in start_m:NM){ d<-m-1
    if(is.null(wcur)||((m-start_m-phase)%%freq==0)) wtar<-tgt(d)
    wcur<- if(is.null(wcur)) wtar else (1-lambda)*wprev + lambda*wtar
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt; gr[m]<-sum(wcur*ri); pr[m]<-gr[m]-(bps/1e4)*dlt
    wd<-wcur*(1+ri); wprev<-wd/sum(wd) }
  list(pr=pr,gross=gr,tov=tov) }
st<-function(r){ k<-is.finite(r$pr); mk<-mon$Market[k]; na<-r$pr[k]-mk; ga<-r$gross[k]-mk
  list(pt=nwt(na),IR=IRf(na),mean=mean(na)*12,sd=sd(na)*sqrt(12),
       gmean=mean(ga)*12,gsd=sd(ga)*sqrt(12),TO=mean(r$tov[k])*12,
       SR=IRf(r$pr[k]),MDD=min(cumprod(1+r$pr[k])/cummax(cumprod(1+r$pr[k]))-1)) }

cat("=========== (G) 신선도 감쇠율 (위상평균 gross, 0bps) ===========\n")
G<-list()
for(f in c(1,2,3,4,5,6,12)){ gm<-c(); gs<-c(); to<-c()
  for(p in 0:(f-1)){ s<-st(run4(0,f,p,1)); gm<-c(gm,s$gmean); gs<-c(gs,s$gsd); to<-c(to,s$TO) }
  G[[length(G)+1]]<-data.table(freq=f,avg_stale=(f-1)/2,gross_mean=mean(gm),gross_sd=mean(gs),TO=mean(to)) }
G<-rbindlist(G); print(G,digits=4)
fit<-lm(gross_mean~avg_stale,data=G)
cat(sprintf("  회귀 gross_mean ~ 평균신선도지연: 절편 %.4f%%/yr · 기울기 %.4f%%/yr per month (R2=%.3f)\n",
  coef(fit)[1]*100,coef(fit)[2]*100,summary(fit)$r.squared))
fitT<-lm(TO~avg_stale,data=G)
cat(sprintf("  회전율 감소: 기울기 %.4f /yr per month of staleness\n",coef(fitT)[2]))
cat(sprintf("  ★손익분기 비용 = 알파감쇠/회전감소 = %.4f%% / %.4f = %.1f bps (one-way)\n",
  -coef(fit)[2]*100,-coef(fitT)[2],-coef(fit)[2]/-coef(fitT)[2]*1e4))
## freq1 vs freq3 직접 손익분기
g1<-G[freq==1]; g3<-G[freq==3]
cat(sprintf("  freq1 vs freq3 직접: dGross=%.4f%%/yr, dTO=%.4f -> 손익분기 %.1f bps\n",
  (g3$gross_mean-g1$gross_mean)*100,(g1$TO-g3$TO),(g1$gross_mean-g3$gross_mean)/(g1$TO-g3$TO)*1e4))
fwrite(G,file.path(OUTD,"p7_staleness_decay.csv"))

cat("\n=========== (H) 비용 수준별 위상평균 우열 (freq1 vs freq3) ===========\n")
H<-list()
for(b in c(0,5,10,15,20,25,27,30,40)){
  m1<-st(run4(b,1,0,1)); v3<-lapply(0:2,function(p)st(run4(b,3,p,1)))
  H[[length(H)+1]]<-data.table(bps=b,
    f1_mean=m1$mean, f3_mean_phaseavg=mean(sapply(v3,`[[`,"mean")),
    f1_pt=m1$pt, f3_pt_phaseavg=mean(sapply(v3,`[[`,"pt")), f3_pt_phase0=v3[[1]]$pt,
    f1_IR=m1$IR, f3_IR_phaseavg=mean(sapply(v3,`[[`,"IR"))) }
H<-rbindlist(H); H[,`:=`(d_mean=f3_mean_phaseavg-f1_mean, d_pt=f3_pt_phaseavg-f1_pt)]
print(H,digits=4); fwrite(H,file.path(OUTD,"p7_breakeven_bps.csv"))
cx<-H[which.min(abs(d_mean))]$bps
cat(sprintf("  위상평균 net 평균 교차점 ≈ %d bps (그 아래에선 월간이 평균 우위)\n",cx))

cat("\n=========== (I) 기전 함의 검정 — 부분 리밸(lambda) : 신선도 유지 + 회전 절감 ===========\n")
cat("  ※ 미사전등록 진단 — 채택 아님. 기전('감쇠는 신선도, 절감은 회전율')이 맞으면\n")
cat("     매월 결정 + 부분 이동(lambda<1)이 분기(freq3)를 회전율-동률에서 상회해야 함\n")
I<-list()
for(lm_ in c(1,0.8,0.6,0.5,0.4,0.3)){ s<-st(run4(15,1,0,lm_)); s0<-st(run4(0,1,0,lm_))
  I[[length(I)+1]]<-data.table(lambda=lm_,pt15=s$pt,IR15=s$IR,mean15=s$mean,sd15=s$sd,
     TO=s$TO,gross_mean=s0$gmean,gross_sd=s0$gsd,SR=s$SR,MDD=s$MDD) }
I<-rbindlist(I); print(I,digits=4); fwrite(I,file.path(OUTD,"p7_partial_rebal.csv"))
cat(sprintf("\n  대조 freq3 위상평균: pt15=%.3f IR15=%.4f TO=%.3f | freq3 phase0(A5): pt15=3.232 TO=2.352\n",
  mean(sapply(0:2,function(p)st(run4(15,3,p,1))$pt)), mean(sapply(0:2,function(p)st(run4(15,3,p,1))$IR)),
  mean(sapply(0:2,function(p)st(run4(15,3,p,1))$TO))))
## lambda 위상 무관 (매월 결정) -> 로터리 없음
cat("  ※ lambda 팔은 매월 결정이므로 위상 자유도 0 (로터리 없음)\n")
cat("\nPROBE_A5_BREAKEVEN_DONE\n")
