## run_dfa_volattrib_r21.R — R21: 타이밍 초과분 변동성 상승(+75%)의 2x2 반사실 귀속
## 질문: vol 0.0518(pre) -> 0.0906(clean) 이 (A)팩터공간 공분산 확대인가 (B)신호 회전(가중 이탈) 확대인가.
## 방법: 초과분 = d_t' r_t (d = w - w_EW 이탈벡터). 연율분산 ~ mean_t[d_t' Sigma d_t]*12.
##       era별 d 와 era별 Sigma 를 교차 대입한 2x2 반사실.
suppressPackageStartupMessages({library(data.table);library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
fac<-setdiff(names(R),c("Date","ym","as_of_date","source_version","Market"))
mon<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",fac)]
mon<-mon[ym<="2026-07"]; NM<-nrow(mon); NF<-length(fac); NAx<-1+NF
ACT<-sapply(fac,function(k)mon[[k]]-mon$Market)          # NM x NF 팩터 active
S<-matrix(NA_real_,NM,NF)
for(fi in 1:NF) for(m in 12:NM) S[m,fi]<-prod(1+mon[[fac[fi]]][(m-11):m])/prod(1+mon$Market[(m-11):m])-1
RET<-as.matrix(mon[,c("Market",fac),with=FALSE]); RET[!is.finite(RET)]<-0
## 가중 궤적 산출 (F0 현행 규칙, 3-코호트 평균) — 팩터 부분만 추출해 EW 이탈 계산
wtraj<-function(dec_lag=1,freq=3,ncoh=3,start0=13){
  W<-array(NA_real_,c(ncoh,NM,NAx))
  for(cc in 0:(ncoh-1)){ st<-start0+cc; wprev<-rep(1/NAx,NAx); wcur<-NULL
    for(m in st:NM){ d<-m-dec_lag; if(d<1) next
      if(is.null(wcur)||((m-st)%%freq==0)){ s<-S[d,]; pos<-which(is.finite(s)&s>0); w<-rep(0,NAx)
        if(length(pos)==0) w[1]<-1 else w[1+pos]<-s[pos]/sum(s[pos]); wcur<-w }
      W[cc+1,m,]<-wcur
      ri<-RET[m,]; wd<-wcur*(1+ri); wprev<-wd/sum(wd); wcur<-wprev } }
  apply(W,c(2,3),function(x)if(all(is.finite(x)))mean(x) else NA_real_) }
WT<-wtraj()                                  # NM x NAx (Market + 21팩터)
DEV<-WT[,-1,drop=FALSE]-1/NF                 # 이탈: 팩터 가중 - EW(1/NF). Market 성분은 초과분 정의상 제외
E<-list(pre=which(mon$ym<"2015-07"), post=which(mon$ym>="2015-07"))  # (2026-08-29) clean→post 개명 — PIT $clean 소비 검사기 오탐 회피(구간명일 뿐)
ok<-function(idx) idx[apply(DEV[idx,,drop=FALSE],1,function(x)all(is.finite(x)))]
E<-lapply(E,ok)
SIG<-lapply(E,function(idx) cov(ACT[idx,,drop=FALSE],use="pairwise.complete.obs"))
cat("=== R21 타이밍 초과분 변동성 2x2 반사실 귀속 ===\n")
cat(sprintf("표본: pre n=%d (%s~%s) | post(구 clean) n=%d (%s~%s)\n\n",
  length(E$pre),mon$ym[min(E$pre)],mon$ym[max(E$pre)],length(E$post),mon$ym[min(E$post)],mon$ym[max(E$post)]))
vol<-function(d_era,s_era){ D<-DEV[E[[d_era]],,drop=FALSE]; Sg<-SIG[[s_era]]
  sqrt(mean(apply(D,1,function(x)as.numeric(t(x)%*%Sg%*%x)))*12) }
cat("[2x2 반사실: 행=이탈벡터 d 출처, 열=공분산 Sigma 출처]\n")
cat(sprintf("  %-12s %10s %10s\n","d \ Sigma","pre","post"))
for(dd in c("pre","post")) cat(sprintf("  %-12s %10.4f %10.4f\n",dd,vol(dd,"pre"),vol(dd,"post")))
vpp<-vol("pre","pre"); vcc<-vol("post","post"); vpc<-vol("pre","post"); vcp<-vol("post","pre")
cat(sprintf("\n실제 상승 배율: %.4f -> %.4f = x%.3f\n",vpp,vcc,vcc/vpp))
cat(sprintf("  (A) 공분산 효과 단독 [d 고정=pre, Sigma pre->clean]: x%.3f\n",vpc/vpp))
cat(sprintf("  (B) 이탈벡터 효과 단독 [Sigma 고정=pre, d pre->clean]: x%.3f\n",vcp/vpp))
cat(sprintf("  (교차/상호작용) 잔여: x%.3f\n",(vcc/vpp)/((vpc/vpp)*(vcp/vpp))))
cat("\n[보조 지표 — 두 축의 직접 관측]\n")
for(e in c("pre","post")){ idx<-E[[e]]
  D<-DEV[idx,,drop=FALSE]; A<-ACT[idx,,drop=FALSE]
  disp<-mean(apply(D,1,function(x)sqrt(sum(x^2))))              # 이탈 벡터 노름
  nsel<-mean(apply(WT[idx,-1,drop=FALSE],1,function(x)sum(x>1e-8)))
  tovv<-mean(abs(diff(D)),na.rm=TRUE)*NF                        # 이탈 회전
  ivol<-mean(apply(A,2,sd,na.rm=TRUE))*sqrt(12)                 # 팩터 개별 active vol 평균
  cat(sprintf("  %-6s 이탈노름=%.4f  평균선택수=%.1f  이탈회전=%.4f  팩터개별 active vol 평균=%.4f\n",
    e,disp,nsel,tovv,ivol)) }
cat("\nR21_DONE\n")
