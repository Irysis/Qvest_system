## probe_a5_mechanism.R — A5(분기 리밸) 우위 기전 규명 (읽기 전용 프로브)
## 과제 5항: ①비용분해 ②신호지속성 ③드리프트 ④월간노이즈 ⑤구조 vs 우연
## 기존 파이프라인 파일 무수정. 산출은 stage_artifacts/probe_a5_20260822/ 만.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich);library(lmtest)})
OUTD<-"stage_artifacts/probe_a5_20260822"
set.seed(20260822)

IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

## ---------- 데이터: R10 와 비트 동일 로딩 ----------
load_mon<-function(path){
  R<-as.data.table(read_parquet(path)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
  fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
  R[,ym:=format(Date,"%Y-%m")]
  mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1),.(medate=max(Date))),by=ym,.SDcols=c("Market",fac)]
  setorder(mon,medate); list(mon=mon,fac=fac) }
BR<-load_mon("outputs/ramp/dfa_index_returns_broad_202608.parquet")
mon<-BR$mon; fac<-BR$fac; NM<-nrow(mon); NAx<-1+length(fac)
cat(sprintf("[data] months=%d  factors=%d  span=%s..%s\n",NM,length(fac),mon$ym[1],mon$ym[NM]))

mk_sig<-function(mon,fac,win=12){
  S<-matrix(NA_real_,nrow(mon),length(fac)); colnames(S)<-fac
  for(fi in seq_along(fac)){ f<-fac[fi]
    for(m in win:nrow(mon)){ w<-(m-win+1):m
      S[m,fi]<-prod(1+mon[[f]][w])/prod(1+mon$Market[w])-1 } }
  S }
S12<-mk_sig(mon,fac,12)

## ---------- 엔진: R10 run_arm 과 동일 규칙 + gross/weight 추적 + 리밸모드 ----------
## rebal_mode = "drift"  : 결정월에만 목표비중 세팅, 사이는 드리프트 (A5/C1 원판)
##            = "reset"  : 결정 주기는 freq 이나 매월 그 분기 목표비중으로 되돌림 (드리프트 제거)
run_arm2<-function(mon,fac,S,mode="cont",bps=15,freq=1,start_m=13,phase=0,rebal_mode="drift"){
  NAx<-1+length(fac); NM<-nrow(mon)
  pr<-rep(NA_real_,NM); gr<-rep(NA_real_,NM); tov<-rep(NA_real_,NM)
  W<-matrix(NA_real_,NM,NAx); Wt<-matrix(NA_real_,NM,NAx)      # 실보유 / 그 분기 목표
  qpos<-rep(NA_integer_,NM); dec_used<-rep(NA_integer_,NM)
  wprev<-rep(1/NAx,NAx); wcur<-NULL; wtar<-NULL; qk<-0L
  for(m in start_m:NM){ d<-m-1
    is_dec <- is.null(wcur) || ((m-start_m-phase) %% freq == 0)
    if(is_dec){
      s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
      if(length(pos)==0){ w[1]<-1 } else if(mode=="cont"){ w[1+pos]<-s[pos]/sum(s[pos])
      } else { rk<-rank(s[pos]); w[1+pos]<-rk/sum(rk) }
      wtar<-w; wcur<-w; qk<-1L; dec_used[m]<-d
    } else { qk<-qk+1L
      if(rebal_mode=="reset") wcur<-wtar }     # drift 모드면 wcur = 직전월 드리프트값 유지
    qpos[m]<-qk
    ri<-unlist(mon[m,c("Market",fac),with=FALSE]); ri[!is.finite(ri)]<-0
    dlt<-sum(abs(wcur-wprev)); tov[m]<-dlt
    gr[m]<-sum(wcur*ri); pr[m]<-gr[m]-(bps/1e4)*dlt
    W[m,]<-wcur; Wt[m,]<-wtar
    wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev }
  list(pr=pr,gross=gr,tov=tov,W=W,Wtar=Wt,qpos=qpos,dec_used=dec_used) }

mets<-function(mon,pr,tov){ k<-is.finite(pr); p<-pr[k]; mk<-mon$Market[k]
  act<-p-mk; nav<-cumprod(1+p); mdd<-min(nav/cummax(nav)-1); n<-length(p)
  post17<-format(mon$medate[k],"%Y")>="2017"
  data.table(n_mo=n,pt_vsMkt=nwt(act),IR_vsMkt=IRf(act),SR=IRf(p),
    CAGR=prod(1+p)^(12/n)-1,MDD=mdd,calmar=(prod(1+p)^(12/n)-1)/abs(mdd),
    TO_ann=mean(tov[k],na.rm=TRUE)*12,pt_post17=nwt(act[post17])) }

## ==========================================================================
## [1] 비용 분해 — gross vs net, 0/5/15bps
## ==========================================================================
cat("\n================ [1] 비용 분해 ================\n")
ARMS1<-list(C1_month=list(freq=1,rm="drift"), A5_quart=list(freq=3,rm="drift"))
R1<-list(); SER1<-list()
for(an in names(ARMS1)) for(b in c(0,5,15)){
  a<-ARMS1[[an]]; r<-run_arm2(mon,fac,S12,"cont",b,a$freq,13,0,a$rm)
  k<-is.finite(r$pr); mk<-mon$Market[k]
  g_act<-r$gross[k]-mk; n_act<-r$pr[k]-mk; cost<-(b/1e4)*r$tov[k]
  R1[[length(R1)+1]]<-data.table(arm=an,bps=b,
    gross_act_ann=mean(g_act)*12, net_act_ann=mean(n_act)*12, cost_ann=mean(cost)*12,
    TO_ann=mean(r$tov[k])*12,
    gross_pt=nwt(g_act), net_pt=nwt(n_act),
    gross_IR=IRf(g_act), net_IR=IRf(n_act))
  SER1[[sprintf("%s_%d",an,b)]]<-r }
R1<-rbindlist(R1); print(R1,digits=4)

cat("\n-- A5 − C1 차이 분해 (연율, 산술평균 기준) --\n")
D1<-list()
for(b in c(0,5,15)){
  c1<-SER1[[sprintf("C1_month_%d",b)]]; a5<-SER1[[sprintf("A5_quart_%d",b)]]
  k<-is.finite(c1$pr)&is.finite(a5$pr)
  dg<-(a5$gross-c1$gross)[k]; dc<-((b/1e4)*(a5$tov-c1$tov))[k]; dn<-(a5$pr-c1$pr)[k]
  D1[[length(D1)+1]]<-data.table(bps=b,
    d_gross_ann=mean(dg)*12, d_cost_saved_ann=-mean(dc)*12, d_net_ann=mean(dn)*12,
    paired_nwt_gross=nwt(dg), paired_nwt_net=nwt(dn),
    share_from_cost=ifelse(mean(dn)!=0,(-mean(dc))/mean(dn),NA)) }
D1<-rbindlist(D1); print(D1,digits=4)
cat("\n-- 0bps 판정: 분기가 비용 없이도 이기는가? --\n")
z<-D1[bps==0]
cat(sprintf("   0bps net 차 = %.4f%%/yr (paired NW-t %.3f) -> %s\n",z$d_net_ann*100,z$paired_nwt_net,
    ifelse(z$d_net_ann>0,"YES (gross 자체가 높음)","NO (비용 절감이 전부)")))
fwrite(R1,file.path(OUTD,"p1_cost_decomp.csv")); fwrite(D1,file.path(OUTD,"p1_cost_diff.csv"))

## ==========================================================================
## [2] 신호 지속성 — 12M active>0 의 전환 빈도 / 지속기간 분포
## ==========================================================================
cat("\n================ [2] 신호 지속성 ================\n")
dec<-12:(NM-1)                              # 결정월 d (적용월 m=d+1 이 13..NM)
ON<-(is.finite(S12)&S12>0)[dec,,drop=FALSE]; rownames(ON)<-mon$ym[dec]
nd<-nrow(ON)
## (a) 팩터별 전환 횟수 / on-비율
sw<-apply(ON,2,function(v)sum(v[-1]!=v[-length(v)]))
onr<-colMeans(ON)
P2a<-data.table(factor=colnames(ON),on_share=round(onr,3),n_switch=sw,
                switch_rate=round(sw/(nd-1),3), mean_spell_on=NA_real_, mean_spell_off=NA_real_)
## (b) 지속기간(spell) 분포
spell<-function(v,val){ r<-rle(v); r$lengths[r$values==val] }
allon<-c(); alloff<-c()
for(j in seq_len(ncol(ON))){ so<-spell(ON[,j],TRUE); sf<-spell(ON[,j],FALSE)
  P2a[j,mean_spell_on:=ifelse(length(so),mean(so),NA)]; P2a[j,mean_spell_off:=ifelse(length(sf),mean(sf),NA)]
  allon<-c(allon,so); alloff<-c(alloff,sf) }
cat("-- on-spell(신호 켜짐 연속개월) 분포 (전 팩터 pooled) --\n")
cat(sprintf("   n_spell=%d  mean=%.2f  median=%.1f  q25=%.1f q75=%.1f  max=%d  P(<=3mo)=%.3f\n",
    length(allon),mean(allon),median(allon),quantile(allon,.25),quantile(allon,.75),max(allon),mean(allon<=3)))
cat(sprintf("   off-spell: n=%d mean=%.2f median=%.1f\n",length(alloff),mean(alloff),median(alloff)))
print(table(pmin(allon,13)))
## (c) 월간 on-set 변동 + 목표비중 churn
jac<-sapply(2:nd,function(i){a<-ON[i,];b<-ON[i-1,];su<-sum(a|b); if(su==0)NA else sum(a&b)/su})
chg<-sapply(2:nd,function(i)sum(ON[i,]!=ON[i-1,]))
## 목표비중 L1 churn: 매월 재결정 시 목표가 얼마나 바뀌나 (드리프트 무시한 순수 신호 churn)
tgt<-function(d){ s<-S12[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
  if(length(pos)==0)w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); w }
TG<-t(sapply(dec,tgt))
l1_1<-sapply(2:nd,function(i)sum(abs(TG[i,]-TG[i-1,])))
l1_3<-sapply(4:nd,function(i)sum(abs(TG[i,]-TG[i-3,])))
cat(sprintf("\n-- 월간 on-set 안정성: 평균 Jaccard(t,t-1)=%.3f · 평균 멤버십 변화 %.2f개/월 (on 평균 %.1f개)\n",
    mean(jac,na.rm=TRUE),mean(chg),mean(rowSums(ON))))
cat(sprintf("-- 목표비중 L1 거리: lag1 = %.4f · lag3 = %.4f (lag3/lag1 = %.2f배; 무상관이면 ~1.41배 예상)\n",
    mean(l1_1),mean(l1_3),mean(l1_3)/mean(l1_1)))
P2b<-data.table(metric=c("n_dec_months","mean_on_count","mean_jaccard_lag1","mean_membership_change",
                         "pooled_mean_on_spell","pooled_median_on_spell","P_on_spell_le3",
                         "mean_L1_target_lag1","mean_L1_target_lag3","L1_ratio_lag3_lag1"),
                value=c(nd,mean(rowSums(ON)),mean(jac,na.rm=TRUE),mean(chg),
                        mean(allon),median(allon),mean(allon<=3),mean(l1_1),mean(l1_3),mean(l1_3)/mean(l1_1)))
fwrite(P2a,file.path(OUTD,"p2_signal_persistence_byfactor.csv"))
fwrite(P2b,file.path(OUTD,"p2_signal_persistence_summary.csv"))
fwrite(data.table(spell_len=allon),file.path(OUTD,"p2_on_spells.csv"))

## ==========================================================================
## [3] 드리프트 효과 — HHI 비교 + 드리프트 수익 귀속 (Q-reset 대조군)
## ==========================================================================
cat("\n================ [3] 드리프트 효과 ================\n")
QR<-run_arm2(mon,fac,S12,"cont",15,3,13,0,"reset")   # 분기 결정 + 매월 목표 복귀 (드리프트 제거)
C1<-SER1[["C1_month_15"]]; A5<-SER1[["A5_quart_15"]]
hhi<-function(W){ k<-which(is.finite(W[,1])); apply(W[k,,drop=FALSE],1,function(w)sum(w^2)) }
h_c1<-hhi(C1$W); h_a5<-hhi(A5$W); h_qr<-hhi(QR$W)
cat(sprintf("-- 평균 HHI: C1(월간 리셋)=%.4f (유효N %.2f) · A5(분기 드리프트)=%.4f (유효N %.2f) · QR(분기 리셋)=%.4f (유효N %.2f)\n",
    mean(h_c1),1/mean(h_c1),mean(h_a5),1/mean(h_a5),mean(h_qr),1/mean(h_qr)))
qk<-A5$qpos[is.finite(A5$pr)]
cat("-- A5 분기내 위치별 평균 HHI (1=결정직후, 3=드리프트 최대):\n")
for(q in 1:3) cat(sprintf("     q%d: HHI=%.4f  유효N=%.2f  (n=%d)\n",q,mean(h_a5[qk==q]),1/mean(h_a5[qk==q]),sum(qk==q)))
## 드리프트가 밀어낸 비중 L1 (실보유 vs 그 분기 목표)
dl1<-sapply(which(is.finite(A5$pr)),function(m)sum(abs(A5$W[m,]-A5$Wtar[m,])))
cat(sprintf("-- A5 |실보유-분기목표| L1: q1=%.4f q2=%.4f q3=%.4f\n",
    mean(dl1[qk==1]),mean(dl1[qk==2]),mean(dl1[qk==3])))
## 드리프트 수익 귀속: gross(A5) - gross(QR)  (동일 신호·동일 결정월, 리밸모드만 다름)
kk<-is.finite(A5$pr)&is.finite(QR$pr)
drift_ret<-(A5$gross-QR$gross)[kk]
cat(sprintf("-- 드리프트 순수 기여(gross A5−QR): 연율 %.4f%%  NW-t=%.3f  (양수=모멘텀 노출 강화가 수익)\n",
    mean(drift_ret)*12*100,nwt(drift_ret)))
M3<-rbind(cbind(data.table(arm="C1_month_drift"),mets(mon,C1$pr,C1$tov)),
          cbind(data.table(arm="QR_quart_reset"),mets(mon,QR$pr,QR$tov)),
          cbind(data.table(arm="A5_quart_drift"),mets(mon,A5$pr,A5$tov)))
cat("\n-- 2-way 분해 (15bps): C1 -> QR = '신호 신선도' 효과 / QR -> A5 = '드리프트' 효과 --\n"); print(M3,digits=4)
d_stale<-(QR$pr-C1$pr)[is.finite(QR$pr)&is.finite(C1$pr)]
d_drift<-(A5$pr-QR$pr)[kk]
cat(sprintf("   net paired NW-t: C1->QR(신호 stale화) = %.3f (연율 %.4f%%) | QR->A5(드리프트) = %.3f (연율 %.4f%%)\n",
    nwt(d_stale),mean(d_stale)*12*100,nwt(d_drift),mean(d_drift)*12*100))
## 0bps 에서도 같은 분해
QR0<-run_arm2(mon,fac,S12,"cont",0,3,13,0,"reset"); C10<-SER1[["C1_month_0"]]; A50<-SER1[["A5_quart_0"]]
k0<-is.finite(A50$pr)&is.finite(QR0$pr)
cat(sprintf("   [0bps] C1->QR = %.4f%%/yr (t %.3f) | QR->A5 = %.4f%%/yr (t %.3f)\n",
    mean((QR0$pr-C10$pr)[k0])*12*100,nwt((QR0$pr-C10$pr)[k0]),
    mean((A50$pr-QR0$pr)[k0])*12*100,nwt((A50$pr-QR0$pr)[k0])))
fwrite(M3,file.path(OUTD,"p3_drift_arms.csv"))
fwrite(data.table(qpos=qk,hhi_a5=h_a5[seq_along(qk)],l1_vs_target=dl1),file.path(OUTD,"p3_hhi_by_qpos.csv"))

## ==========================================================================
## [4] 월간 노이즈 — 신규진입 팩터 vs 장기유지 팩터의 익월 active
## ==========================================================================
cat("\n================ [4] 월간 노이즈(단기 역전) ================\n")
FA<-matrix(NA_real_,NM,length(fac)); colnames(FA)<-fac
for(j in seq_along(fac)) FA[,j]<-mon[[fac[j]]]-mon$Market      # 팩터 active return (월)
## tenure: 결정월 d 기준 연속 on 개월수
TEN<-matrix(0L,nd,ncol(ON))
for(j in seq_len(ncol(ON))){ t<-0L; for(i in seq_len(nd)){ t<-if(ON[i,j]) t+1L else 0L; TEN[i,j]<-t } }
rec<-list()
for(i in seq_len(nd)){ d<-dec[i]; m<-d+1; if(m>NM) next
  s<-S12[d,]; pos<-which(is.finite(s)&s>0); if(!length(pos)) next
  w<-s[pos]/sum(s[pos])
  rec[[length(rec)+1]]<-data.table(ym=mon$ym[m],i=i,fj=pos,ten=TEN[i,pos],w=w,fwd_act=FA[m,pos]) }
RC<-rbindlist(rec)
RC[,grp:=ifelse(ten<=3,"신규(<=3mo)","유지(>=4mo)")]
cat(sprintf("-- 관측 (팩터-월) = %d 쌍, 결정월 %d개\n",nrow(RC),length(unique(RC$i))))
g<-RC[,.(n=.N,share=.N/nrow(RC),mean_fwd_act=mean(fwd_act),sd=sd(fwd_act),
         wmean_fwd_act=sum(w*fwd_act)/sum(w), mean_w=mean(w)),by=grp][order(grp)]
print(g,digits=4)
tb<-RC[,.(n=.N,mean_fwd_act_pct=mean(fwd_act)*100,mean_w=mean(w)),
       by=.(ten_bucket=cut(ten,c(0,1,2,3,6,12,999),labels=c("1","2","3","4-6","7-12","13+")))][order(ten_bucket)]
cat("\n-- tenure 버킷별 익월 active (월%) --\n"); print(tb,digits=4)
## 월별 (신규평균 − 유지평균) 시계열로 NW-t (횡단면 상관 통제)
ms<-RC[,{a<-mean(fwd_act[ten<=3]);b<-mean(fwd_act[ten>=4]);.(d=a-b,na=sum(ten<=3),nb=sum(ten>=4))},by=i]
ms<-ms[na>0&nb>0]
cat(sprintf("\n-- 월별 (신규−유지) 차: n=%d개월  평균 %.4f%%/월 (연율 %.3f%%)  NW-t=%.3f\n",
    nrow(ms),mean(ms$d)*100,mean(ms$d)*12*100,nwt(ms$d)))
## tenure==1 (막 진입) 단독
ms1<-RC[,{a<-mean(fwd_act[ten==1]);b<-mean(fwd_act[ten>=4]);.(d=a-b,na=sum(ten==1),nb=sum(ten>=4))},by=i][na>0&nb>0]
cat(sprintf("-- 월별 (tenure1−유지) 차: n=%d  평균 %.4f%%/월  NW-t=%.3f\n",nrow(ms1),mean(ms1$d)*100,nwt(ms1$d)))
fwrite(g,file.path(OUTD,"p4_tenure_groups.csv")); fwrite(tb,file.path(OUTD,"p4_tenure_buckets.csv"))
fwrite(RC,file.path(OUTD,"p4_factor_month_panel.csv"))

## ==========================================================================
## [5] 구조 vs 우연 — 위상(phase) 3종 · 주기 사다리 · 부분표본 · 블록부트스트랩
## ==========================================================================
cat("\n================ [5] 구조 vs 표본우연 ================\n")
cat("-- (a) 분기 위상 3종 (phase 0/1/2, 15bps) : 우연이면 특정 위상만 이김 --\n")
PH<-list()
for(p in 0:2){ r<-run_arm2(mon,fac,S12,"cont",15,3,13,p,"drift")
  k<-is.finite(r$pr)&is.finite(C1$pr)
  PH[[length(PH)+1]]<-cbind(data.table(phase=p),mets(mon,r$pr,r$tov),
      data.table(paired_nwt_vs_C1=nwt((r$pr-C1$pr)[k]), d_net_ann=mean((r$pr-C1$pr)[k])*12)) }
PH<-rbindlist(PH); print(PH,digits=4)
cat("-- (a') 0bps 위상 3종 --\n")
PH0<-list()
for(p in 0:2){ r<-run_arm2(mon,fac,S12,"cont",0,3,13,p,"drift")
  k<-is.finite(r$pr)&is.finite(C10$pr)
  PH0[[length(PH0)+1]]<-data.table(phase=p,pt=mets(mon,r$pr,r$tov)$pt_vsMkt,
      paired_nwt_vs_C1=nwt((r$pr-C10$pr)[k]), d_net_ann=mean((r$pr-C10$pr)[k])*12) }
PH0<-rbindlist(PH0); print(PH0,digits=4)

cat("\n-- (b) 리밸 주기 사다리 freq=1..6,12 (15bps, phase0) --\n")
LD<-list()
for(f in c(1,2,3,4,5,6,12)){ r<-run_arm2(mon,fac,S12,"cont",15,f,13,0,"drift")
  r0<-run_arm2(mon,fac,S12,"cont",0,f,13,0,"drift")
  k<-is.finite(r$pr)&is.finite(C1$pr)
  LD[[length(LD)+1]]<-cbind(data.table(freq=f),mets(mon,r$pr,r$tov)[,.(pt_vsMkt,IR_vsMkt,SR,CAGR,MDD,calmar,TO_ann)],
     data.table(pt_0bps=mets(mon,r0$pr,r0$tov)$pt_vsMkt, paired_nwt_vs_C1=nwt((r$pr-C1$pr)[k]))) }
LD<-rbindlist(LD); print(LD,digits=4)

cat("\n-- (c) 부분표본 3분할 (paired net 차, A5−C1) --\n")
k<-which(is.finite(A5$pr)&is.finite(C1$pr)); dn<-(A5$pr-C1$pr)[k]; ymk<-mon$ym[k]; n<-length(dn)
cut3<-cut(seq_len(n),3,labels=c("T1","T2","T3"))
SS<-data.table(seg=levels(cut3))[,`:=`(
  span=sapply(levels(cut3),function(s)paste(range(ymk[cut3==s]),collapse="~")),
  n=sapply(levels(cut3),function(s)sum(cut3==s)),
  d_net_ann=sapply(levels(cut3),function(s)mean(dn[cut3==s])*12),
  nwt=sapply(levels(cut3),function(s)nwt(dn[cut3==s])),
  win_rate=sapply(levels(cut3),function(s)mean(dn[cut3==s]>0)))]
print(SS,digits=4)
cat(sprintf("   전체: 월별 승률 %.3f (n=%d)  평균차 %.4f%%/yr\n",mean(dn>0),n,mean(dn)*12*100))
## 위기월 대 정상월
crisis<-mon$Market[k]< -0.05
cat(sprintf("   시장 −5%% 이하 월(n=%d): 평균차 %.4f%%/월 | 그 외(n=%d): %.4f%%/월\n",
    sum(crisis),mean(dn[crisis])*100,sum(!crisis),mean(dn[!crisis])*100))

cat("\n-- (d) 이동블록 부트스트랩 (block=12, B=3000) on paired net diff --\n")
mbb<-function(x,B=3000,bl=12){ n<-length(x); nb<-ceiling(n/bl)
  replicate(B,{st<-sample(1:(n-bl+1),nb,replace=TRUE)
    mean(unlist(lapply(st,function(s)x[s:(s+bl-1)]))[1:n])}) }
bs<-mbb(dn); ci<-quantile(bs,c(.025,.5,.975))
cat(sprintf("   mean=%.5f  95%%CI=[%.5f, %.5f] (월)  P(mean>0)=%.3f\n",mean(dn),ci[1],ci[3],mean(bs>0)))
bsg<-mbb((A50$pr-C10$pr)[is.finite(A50$pr)&is.finite(C10$pr)]); cig<-quantile(bsg,c(.025,.975))
cat(sprintf("   [0bps] mean=%.5f 95%%CI=[%.5f, %.5f]  P(>0)=%.3f\n",
    mean((A50$pr-C10$pr)[is.finite(A50$pr)]),cig[1],cig[2],mean(bsg>0)))
fwrite(PH,file.path(OUTD,"p5_phase.csv")); fwrite(PH0,file.path(OUTD,"p5_phase_0bps.csv"))
fwrite(LD,file.path(OUTD,"p5_freq_ladder.csv")); fwrite(SS,file.path(OUTD,"p5_subsample.csv"))

## ==========================================================================
## 계약 채점 (essence_score) — C1 / QR / A5 15bps
## ==========================================================================
cat("\n================ 계약 채점 (essence_score, 15bps) ================\n")
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
score<-function(r,nm,reb){ k<-is.finite(r$pr); d<-mon$medate[k]; p<-r$pr[k]; mk<-mon$Market[k]
  sim<-list(DAILY_NAV_DT=data.table(Date=d,Strategy_Ret=p,NAV=cumprod(1+p)),
            strategy_xts=xts(p,order.by=d),bm_xts=xts(mk,order.by=d),cost_model_version="probe_a5_15bps")
  spec<-list(strategy_name=nm,description="A5 기전 프로브",universe="KR broad-21",rebalance=reb,signal="factor momentum")
  bt<-build_bt_result(sim,spec,run_id=paste0("probe_a5_",tolower(nm)),strategy_id=toupper(nm),
      benchmark_id="CAPW_PARENT",benchmark_name="cap-w parent",transaction_cost_bps=15,slippage_bps=0,
      frequency="monthly",universe_id="K200_KQ150",code_version="probe_a5_mechanism.R",created_by_agent="Q-Lead")
  es<-essence_score(bt,n_trials_cumulative=56,selection_type="chain"); e<-es$essence
  data.table(arm=nm,grade=es$grade,pt=e$portfolio_alpha_t_nw_lag3,oos=e$oos_retention,
             calmar=e$calmar,SR=e$net_sharpe,MDD=e$mdd) }
SC<-rbind(score(C1,"PROBE_C1_MONTH","monthly"),score(QR,"PROBE_QR_QUART_RESET","quarterly"),
          score(A5,"PROBE_A5_QUART_DRIFT","quarterly"))
print(SC,digits=4); fwrite(SC,file.path(OUTD,"p0_contract_scores.csv"))
cat("\nPROBE_A5_DONE\n")
