## run_mfro_r57_signal_decay.R — R57: 로테이션 신호가 언제 어떻게 죽었나 (진단 라운드)
##
## ★사전 선언 (결과 산출 전 기록, 진단 라운드이므로 경량):
##   질문 = R56 순열 대조가 full p=0.015 / clean p=0.085 로 갈렸다. 신호는 언제 죽었고 그 소멸은
##          (a) 점진적 감쇠인가 (b) 특정 시점 단절인가 (c) 애초에 소수 연도가 전기간 결과를 끌었나?
##   측정 = 신호(팩터별 trailing active)와 결과(팩터별 꼬리25종 익월 active)의 **월별 횡단면 순위상관(IC)**.
##          이것이 로테이션의 원자적 예측력이다 — 포트폴리오 성과보다 앞단이라 구성 잡음이 없다.
##   ★예상(결과 전): 점진 감쇠가 아니라 **2015 전후 단절**일 것으로 본다. 근거 = DFA 아크가 실측한
##          팩터 프리미엄 부호 반전(+3.11 -> -1.04 %/yr)이 같은 시기이고, R56 순열 p 가 창을 바꾸자
##          0.015 -> 0.085 로 뛰었다(연속적 열화라면 중간값이 나와야 한다).
##   ★소비 = 소비면 5(monitoring) — "로테이션 신호가 살아있나" 의 상시 관측 지표.
##   ★이 라운드는 전략 주장을 하지 않는다. graduation 게이트 판정 대상 아님.
suppressPackageStartupMessages({library(data.table);library(arrow)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}

Z<-readRDS(".cache/_mfro_r56.rds")
TA<-Z$TA; TS<-Z$TS; YM<-Z$YM; NM<-length(YM)
FK<-colnames(TA); NF<-length(FK)
## 지수 trailing 신호 재구성 (R56 과 동일 정의)
R<-as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[,Date:=as.Date(Date)];setorder(R,Date);R<-R[is.finite(Market)];R[,ym:=format(Date,"%Y-%m")]
mi<-R[,c(lapply(.SD,function(x)prod(1+ifelse(is.finite(x),x,0))-1)),by=ym,.SDcols=c("Market",FK)]
setorder(mi,ym)
S<-matrix(NA_real_,nrow(mi),NF);dimnames(S)<-list(mi$ym,FK)
for(j in 1:NF)for(m in 12:nrow(mi))S[m,j]<-prod(1+mi[[FK[j]]][(m-11):m])/prod(1+mi$Market[(m-11):m])-1
## 지수 익월 active (결과의 지수 공간 버전)
IA<-matrix(NA_real_,NM,NF);dimnames(IA)<-list(YM,FK)
for(j in 1:NF){r<-match(YM,mi$ym)
  IA[,j]<-ifelse(is.na(r)|r>=nrow(mi),NA_real_,mi[[FK[j]]][pmin(r+1,nrow(mi))]-mi$Market[pmin(r+1,nrow(mi))])}

## ── 월별 횡단면 IC: 결정월 d=m-1 의 신호 vs 월 m 형성 포트의 익월 결과 ──
ic<-function(sig_mat, out_mat, sig_is_S){
  sapply(seq_len(NM),function(m){ d<-m-1L; if(d<1) return(NA_real_)
    s<-if(sig_is_S){r<-match(YM[d],rownames(S)); if(is.na(r)) return(NA_real_); S[r,]} else sig_mat[d,]
    o<-out_mat[m,]; ok<-is.finite(s)&is.finite(o)
    if(sum(ok)<8) return(NA_real_)
    cor(rank(s[ok]),rank(o[ok])) })}
IC <- data.table(ym=YM,
  ic_idx_to_tail = ic(NULL, TA, TRUE),    # 지수 신호 -> 꼬리 결과 (R56 B1 의 원자 예측력)
  ic_tail_to_tail= ic(TS,  TA, FALSE),    # 꼬리 신호 -> 꼬리 결과 (R56 B2)
  ic_idx_to_idx  = ic(NULL, IA, TRUE))    # 지수 신호 -> 지수 결과 (DFA 지수공간 = 원 아크의 F1)
IC[,yr:=as.integer(substr(ym,1,4))]

cat("=== R57: 로테이션 신호 소멸 진단 ===\n")
cat("[정의] 월별 횡단면 순위상관 IC = cor(rank(신호 21개), rank(결과 21개)). 결정월 d=m-1.\n\n")
cat("[전기간 vs clean]\n")
for(w in list(c("full",2005,2026),c("pre2015",2005,2015),c("clean",2015,2026))){
  sub<-IC[yr>=as.integer(w[2]) & yr<as.integer(w[3])+1L]
  if(w[1]=="clean") sub<-IC[ym>="2015-07"]
  if(w[1]=="pre2015") sub<-IC[ym<"2015-07"]
  cat(sprintf("  %-8s n=%3d | 지수->꼬리 %+.4f (t %+.2f) | 꼬리->꼬리 %+.4f (t %+.2f) | 지수->지수 %+.4f (t %+.2f)\n",
    w[1],nrow(sub),
    mean(sub$ic_idx_to_tail,na.rm=TRUE),  nwt(sub$ic_idx_to_tail),
    mean(sub$ic_tail_to_tail,na.rm=TRUE), nwt(sub$ic_tail_to_tail),
    mean(sub$ic_idx_to_idx,na.rm=TRUE),   nwt(sub$ic_idx_to_idx)))}

cat("\n[연도별 IC — 점진 감쇠인가 단절인가]\n")
Y<-IC[,.(n=.N,
         idx2tail=mean(ic_idx_to_tail,na.rm=TRUE),
         tail2tail=mean(ic_tail_to_tail,na.rm=TRUE),
         idx2idx=mean(ic_idx_to_idx,na.rm=TRUE)),by=yr][order(yr)]
for(i in seq_len(nrow(Y))) cat(sprintf("  %d  n=%2d | 지수->꼬리 %+.4f | 꼬리->꼬리 %+.4f | 지수->지수 %+.4f  %s\n",
  Y$yr[i],Y$n[i],Y$idx2tail[i],Y$tail2tail[i],Y$idx2idx[i],
  strrep("#",max(0,round(40*(Y$idx2tail[i]+0.3))))))

cat("\n[★단절 vs 감쇠 판정 — 사전 선언한 대립가설]\n")
v<-Y[is.finite(idx2tail)]
## (1) 선형 추세(감쇠) 대 (2) 2015 더미(단절) 중 어느 쪽이 연도별 IC 를 더 설명하나
m1<-lm(idx2tail~yr,data=v); m2<-lm(idx2tail~I(yr>=2015),data=v)
cat(sprintf("  선형추세 모형 R2=%.3f (기울기 %+.5f/yr, p=%.3f)\n",
  summary(m1)$r.squared, coef(m1)[2], summary(m1)$coefficients[2,4]))
cat(sprintf("  2015단절 모형 R2=%.3f (단차 %+.4f, p=%.3f)\n",
  summary(m2)$r.squared, coef(m2)[2], summary(m2)$coefficients[2,4]))
cat(sprintf("  ⇒ 더 잘 맞는 쪽: %s\n", ifelse(summary(m2)$r.squared>summary(m1)$r.squared,"★단절(2015)","점진 감쇠")))
## 모든 분할점을 훑어 최적 단절 연도 (사후 선택이므로 진단용 라벨)
bs<-sapply(2009:2022,function(y0){mm<-lm(idx2tail~I(yr>=y0),data=v);summary(mm)$r.squared})
cat(sprintf("  [진단·사후선택] 전 분할점 중 최적 = %d년 (R2=%.3f). 사전 지정 2015 의 R2=%.3f\n",
  (2009:2022)[which.max(bs)],max(bs),summary(m2)$r.squared))

cat("\n[소수 연도가 전기간을 끌었나 — 기여 집중도]\n")
for(nm in c("idx2tail","tail2tail","idx2idx")){
  x<-IC[[paste0("ic_",sub("2","_to_",nm))]]
  x<-x[is.finite(x)]
  contrib<-IC[is.finite(get(paste0("ic_",sub("2","_to_",nm)))),
              .(s=sum(get(paste0("ic_",sub("2","_to_",nm))))),by=yr][order(-s)]
  tot<-sum(contrib$s); top3<-sum(head(contrib$s,3))
  cat(sprintf("  %-10s 전기간 합 %+.2f | 상위3개년 합 %+.2f (%.0f%%) = %s\n",
    nm,tot,top3,100*top3/abs(tot),paste(head(contrib$yr,3),collapse=",")))}

cat("\n[★monitoring 지표 제안 — trailing 36M IC 궤적]\n")
roll<-sapply(36:NM,function(m){v<-IC$ic_idx_to_tail[(m-35):m];v<-v[is.finite(v)]
  if(length(v)<24) return(NA_real_); mean(v)})
rym<-YM[36:NM]
cat(sprintf("  trailing36M IC: 최대 %+.4f (%s) · 최소 %+.4f (%s) · 최종 %+.4f (%s)\n",
  max(roll,na.rm=TRUE),rym[which.max(roll)],min(roll,na.rm=TRUE),rym[which.min(roll)],
  tail(roll[is.finite(roll)],1),tail(rym[is.finite(roll)],1)))
neg<-rym[which(roll<0)]
cat(sprintf("  IC<0 최초 진입 %s · 이후 음수 유지 비율 %.0f%%\n",
  ifelse(length(neg)>0,neg[1],"없음"),
  ifelse(length(neg)>0,100*mean(roll[rym>=neg[1]]<0,na.rm=TRUE),0)))
fwrite(data.table(ym=rym,trailing36m_ic=roll),"06_Registry/mfro_rotation_signal_ic_trajectory_20260822.csv")
fwrite(Y,"06_Registry/mfro_rotation_signal_ic_by_year_20260822.csv")
cat("\n산출: 06_Registry/mfro_rotation_signal_ic_trajectory_20260822.csv · ..._by_year_...csv\n")
saveRDS(list(IC=IC,Y=Y,roll=roll,rym=rym),".cache/_mfro_r57.rds")
cat("\nR57_DONE\n")
