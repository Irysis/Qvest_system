## anchors.R — §4 수치 앵커 대조 (로직 판정 완료 후 실행 — Phase 0-4 해제 시점).
## 대상: 실측 헤드라인 런 (KEY=f15_roll, M0/D1, TUNE=roll) — .cache/_smv_v5_f15_roll.rds + 상태/refit 캐시.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
AD<-"stage_artifacts/audit_dfa_20260821"
sink(file.path(AD,"anchors_output.txt"), split=TRUE)
cat("== anchors.R:", format(Sys.time()), "==\n\n")
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

Z<-readRDS(".cache/_smv_v5_f15_roll.rds"); RES<-Z$RES
R<-as.data.table(read_parquet(Z$idxfile)); R[,Date:=as.Date(Date)]; setorder(R,Date); R<-R[is.finite(Market)]
FACN<-c("Value","Size","Momentum","Quality","LowVol","Growth")
ACT<-copy(R[,.(Date)]); for(f in FACN) ACT[[f]]<-R[[f]]-R$Market
NS<-nrow(R); me<-Z$medates; meix<-Z$meix
gmi<-findInterval(seq_len(NS), meix)
S<-readRDS(".cache/_smv_v5_states_f15_roll_lm1.rds")
if(is.list(S)&&!is.null(S$S)) S<-S$S
REF<-readRDS(".cache/_dfa_v5_refit_f15_roll_shumulvey_index_returns_202608_parquet_n6_ValSizMomQua.rds")$REF

## ---- §4.1 온라인 연 전환수 순서 ----
cat("---- §4.1 온라인 연 전환수 (논문 순서: Qua .64 < Gro 1.31 < LowVol 1.78 < Siz 2.57 < Val 3.16 < Mom 3.66) ----\n")
paper_rate<-c(Value=3.16,Size=2.57,Momentum=3.66,Quality=0.64,LowVol=1.78,Growth=1.31)
sw<-sapply(FACN,function(f){ s<-S[,f]; ok<-which(!is.na(s)); if(length(ok)<252)return(NA)
  yrs<-as.numeric(diff(range(R$Date[ok])))/365.25; sum(diff(s[ok])!=0)/yrs })
kr_r<-rank(sw); pp_r<-rank(paper_rate[FACN])
tau<-cor(kr_r,pp_r,method="kendall")
for(f in FACN) cat(sprintf("  %-9s KR %.2f/yr (논문 %.2f)\n",f,sw[f],paper_rate[f]))
cat(sprintf("  Kendall tau(KR vs 논문) = %.3f [>=0.6 통과] | quality 최소? %s | momentum 최대? %s\n\n",
  tau, names(which.min(sw))=="Quality", names(which.max(sw))=="Momentum"))

## ---- §4.1 단일팩터 L/S (상태→±5% 선형 포지션, T+2, 5bps) ----
cat("---- §4.1 단일팩터 L/S Sharpe (전부 양수 앵커; T+2·5bps 자기사양 회계) ----\n")
LS<-matrix(NA_real_,NS,6); colnames(LS)<-FACN
for(fi in seq_along(FACN)){ f<-FACN[fi]; rl<-REF[[f]]
  pos<-rep(NA_real_,NS)
  for(t in seq_len(NS)){ mi<-gmi[t]; if(mi<1)next; rf<-rl[[mi]]; if(is.null(rf)||is.na(S[t,fi]))next
    pos[t]<-max(min(rf$m_ann[S[t,fi]]/0.05,1),-1) }
  pa<-shift(pos,2); dpa<-abs(pa-shift(pa,1))
  LS[,fi]<-pa*ACT[[f]]-5e-4*ifelse(is.finite(dpa),dpa,0)
}
shv<-apply(LS,2,function(x){x<-x[is.finite(x)]; mean(x)/sd(x)*sqrt(252)})
paper_sh<-c(Value=.39,Size=.20,Momentum=.16,Quality=.21,LowVol=.30,Growth=.37)
for(f in FACN) cat(sprintf("  %-9s KR LS_SR=%+.2f (논문 %+.2f)\n",f,shv[f],paper_sh[f]))
CC<-cor(LS,use="pairwise.complete.obs"); diag(CC)<-NA
cat(sprintf("  전부 양수? %s | L/S 최대 쌍상관=%.3f [<0.5 앵커; 논문 최대 0.48]\n\n", all(shv>0,na.rm=TRUE), max(abs(CC),na.rm=TRUE)))

## ---- §4.2 TE 단조성 (M0-roll, 5bps 논문대조 셀) ----
cat("---- §4.2 TE 1→4%% 단조성 (M0-roll 5bps) ----\n")
m5<-RES[arm=="M0"&cost_bps==5][order(te)]
print(m5[,.(te,TO_ann,abs_SR,IR_vsMkt,IR_vsEW,abs_MDD,pt_capwt,n_mo)],digits=3)
mono<-function(x) all(diff(x)>0)
cat(sprintf("  회전율 단조증가? %s | absSR 단조증가? %s | IR_vsMkt 증가후포화? Δ=%s | IR_vsEW 중간최대? argmax te=%g\n\n",
  mono(m5$TO_ann), mono(m5$abs_SR), paste(sprintf("%+.3f",diff(m5$IR_vsMkt)),collapse=","), m5$te[which.max(m5$IR_vsEW)]))
cat("---- (참고) D1-roll 5bps 동일 표 ----\n")
d5<-RES[arm=="D1"&cost_bps==5&lam_mult==1][order(te)]
print(d5[,.(te,TO_ann,abs_SR,IR_vsMkt,IR_vsEW,abs_MDD,pt_capwt,n_mo)],digits=3)

## ---- §4.3 과적합 신호 ----
cat("\n---- §4.3 과적합 탐지 문턱 ----\n")
mon_mkt<-R[,.(mk=prod(1+Market)-1),by=format(Date,"%Y-%m")]$mk
h<-RES[arm=="M0"&te==3&cost_bps==5]
mdd_of<-function(r){nav<-cumprod(1+r); min(nav/cummax(nav)-1)}
s0<-h$series[[1]]
mm_mkt<-s0$pr-s0$actM; mdd_mkt<-mdd_of(mm_mkt); mm_ew<-s0$pr-s0$actE; mdd_ew<-mdd_of(mm_ew)
cat(sprintf("  헤드라인 M0-roll TE3 5bps: abs_SR=%.3f [>0.80 의심] | IR_vsMkt=%.3f [>0.70 의심] | pt=%.3f\n", h$abs_SR, h$IR_vsMkt, h$pt_capwt))
cat(sprintf("  abs_MDD=%.3f vs 시장(동일창)=%.3f vs EW=%.3f → 개선 %.1f%%p(시장) %.1f%%p(EW) [>10%%p 의심]\n",
  h$abs_MDD, mdd_mkt, mdd_ew, 100*(h$abs_MDD-mdd_mkt), 100*(h$abs_MDD-mdd_ew)))
cat("  단일팩터 L/S>0.60 의심축: ", paste(sprintf("%s=%.2f",FACN[shv>0.60&is.finite(shv)],shv[shv>0.60&is.finite(shv)]),collapse=" "),
    ifelse(any(shv>0.60,na.rm=TRUE),""," (없음)"),"\n")
cat("  온라인 vs 인샘플 전환수: 인샘플 경로 미보존 → 실런 대조 불가 (O6-micro 방향성 검증으로 대체)\n\n")

## ---- B6 실현 TE vs 목표 ±30% ----
cat("---- B6 실현 TE (M0-roll 5bps, 월간 actE/actM sd×√12) ----\n")
for(k in 1:nrow(m5)){ s<-m5$series[[k]]
  cat(sprintf("  목표 TE%g%%: 실현 TE_vsEW=%.2f%% | TE_vsMkt=%.2f%% [목표 ±30%% = %.1f~%.1f%%]\n",
    m5$te[k], 100*sd(s$actE,na.rm=TRUE)*sqrt(12), 100*sd(s$actM,na.rm=TRUE)*sqrt(12), m5$te[k]*0.7, m5$te[k]*1.3)) }

## ---- 계보 교차확인: v6 prereg 기재 baseline (pt_5bps 1.033) 재계산 ----
cat("\n---- 계보 교차확인: M0-roll TE3 5bps pt_capwt 재계산 vs prereg 기재 1.033 ----\n")
cat(sprintf("  CSV pt_capwt=%.3f | series 재계산 nwt(actM)=%.3f\n", h$pt_capwt, nwt(h$series[[1]]$actM)))
cat("\nANCHORS_DONE\n"); sink()
