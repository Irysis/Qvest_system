## probe_unit.R — SJM 단위 프로브 (감사 audit_dfa_20260821)
## 엔진 함수 = snip_*.R (sed 추출, extraction_evidence.txt에 원본과 md5 일치 증거).
## 검사: P1(λ=0=k-means), P2(λ→∞ 붕괴), P3(손계산+DP 정확해), P4(시간정보), P7(λ/κ 결합),
##       P9(CV 비용 반응 — 복사 CV 루프), P10(롱온리), O6(온라인>인샘플), CLAIM(last-state≡filter), S2(시장환경 동일).
suppressPackageStartupMessages({library(Rcpp); library(data.table); library(quadprog)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(file.path(QM,"stage_artifacts/audit_dfa_20260821"))
PER<-252
source("snip_sjm.R")   # jumpDP / jumpDPlast / sparse_jm  (엔진 L30-61)
source("snip_ls.R")    # GRID9 + ls_sh_t1                 (엔진 L99-106)
sink("probe_unit_output.txt", split=TRUE)
cat("== probe_unit.R 실행:", format(Sys.time()), "==\n\n")

nsw<-function(s) sum(diff(s)!=0)
relabel_match<-function(a,b){ m1<-mean(a==b); m2<-mean(a==(3L-b)); max(m1,m2) }

## ---------- M5 사전검증: jumpDP = 경로 전수탐색 정확해 (고정 C) ----------
cat("---- [M5] jumpDP 정확해 검증: 무작위 C 20건 × 전수탐색 대조 ----\n")
set.seed(1); ok_m5<-0
for(r in 1:20){
  n<-8; C<-matrix(runif(2*n,0,10),n,2); lam<-runif(1,0,15)
  best<-Inf; bests<-NULL
  for(msk in 0:(2^n-1)){ s<-as.integer(intToBits(msk))[1:n]+1L
    v<-sum(C[cbind(1:n,s)])+lam*nsw(s); if(v<best-1e-12){best<-v;bests<-s} }
  sdp<-jumpDP(C,lam); vdp<-sum(C[cbind(1:n,sdp)])+lam*nsw(sdp)
  if(abs(vdp-best)<1e-9) ok_m5<-ok_m5+1
}
cat(sprintf("  jumpDP 목적값 = 전수탐색 최적값 일치: %d/20\n\n", ok_m5))

## ---------- P3: 손계산 대조 x=[5,4,-1,5,4], D=1, w=1 ----------
cat("---- [P3] 손계산 대조 ----\n")
x<-c(5,4,-1,5,4); X<-matrix(x,ncol=1)
obj_impl<-function(s,lam){ th<-sapply(1:2,function(k){i<-which(s==k); if(length(i))mean(x[i]) else mean(x)})
  sum((x-th[s])^2)+lam*nsw(s) }
brute<-function(lam){ best<-Inf; bests<-NULL
  for(msk in 0:31){ s<-as.integer(intToBits(msk))[1:5]+1L; v<-obj_impl(s,lam)
    if(v<best-1e-12){best<-v;bests<-s} }; list(s=bests,v=best) }
for(lam in c(6.0,6.1,12.0,12.2)){
  fit<-sparse_jm(X,lam=lam,kappa=sqrt(9.5))
  bf<-brute(lam)
  cat(sprintf("  lam=%.1f: sparse_jm 라벨=%s (전환%d, obj_impl=%.2f, obj_paper(=cost/2+lam·sw)=%.2f) | 전수최적 라벨=%s (obj=%.2f)\n",
    lam, paste(fit$s,collapse=""), nsw(fit$s), obj_impl(fit$s,lam),
    (obj_impl(fit$s,lam)-lam*nsw(fit$s))/2+lam*nsw(fit$s),
    paste(bf$s,collapse=""), bf$v))
}
## 분기점 이분탐색: (a) 전수최적 기준 (구현 규약: ½ 없음) (b) sparse_jm 자체 기준
bisect_flip<-function(f, lo, hi){ for(b in 1:40){ mid<-(lo+hi)/2; if(f(mid)>0) lo<-mid else hi<-mid }; (lo+hi)/2 }
fl_bf<-bisect_flip(function(l) nsw(brute(l)$s), 5, 20)
fl_sp<-bisect_flip(function(l) nsw(sparse_jm(X,lam=l,kappa=sqrt(9.5))$s), 3, 20)
cat(sprintf("  분기점(전수최적, 구현규약 no-½): %.4f (기대 = 2×6.05 = 12.10 — ½ 부재로 2배)\n", fl_bf))
cat(sprintf("  분기점(sparse_jm 단일 init):    %.4f (전수최적과 다르면 단일-초기값 국소최적 = M6 증거)\n\n", fl_sp))

## ---------- P2: λ→∞ 붕괴 ----------
cat("---- [P2] λ→∞ 전환 0 ----\n")
set.seed(2); Tn<-400; D<-6
st<-integer(Tn); st[1]<-1; for(t in 2:Tn) st[t]<-if(runif(1)<0.98) st[t-1] else 3L-st[t-1]
Xp<-sapply(1:D,function(j) c(-0.8,0.8)[st]*runif(1,0.5,1)+rnorm(Tn)); Xp<-scale(Xp)
fit0<-sparse_jm(Xp,lam=0,kappa=sqrt(9.5))
C0<-matrix(0,Tn,2); for(k in 1:2){d2<-sweep(Xp,2,fit0$th[k,],"-")^2; C0[,k]<-as.numeric(d2%*%fit0$w)}
lam_huge<-10*sum(apply(C0,1,max))
s_dp<-jumpDP(C0,lam_huge); fit_h<-sparse_jm(Xp,lam=lam_huge,kappa=sqrt(9.5))
cat(sprintf("  lam_huge=%.1f (=10×Σ_t max_k C): jumpDP 전환=%d | sparse_jm 전체 전환=%d  [0이어야 통과, >0 = BLOCK③]\n\n",
  lam_huge, nsw(s_dp), nsw(fit_h$s)))

## ---------- P1: λ=0 = k-means (D=1 정확 등가) ----------
cat("---- [P1] λ=0 k-means 환원 (D=1: w=1 강제 → 정확 등가 기대) ----\n")
set.seed(3); x1<-c(rnorm(150,-2),rnorm(150,2))[sample(300)]; X1<-matrix(x1,ncol=1)
f1<-sparse_jm(X1,lam=0,kappa=1)
th0<-c(mean(x1[x1<=median(x1)]),mean(x1[x1>median(x1)]))  # sparse_jm 초기 s와 동일한 분할의 중심
km<-kmeans(X1,centers=matrix(th0,2,1),algorithm="Lloyd",iter.max=100)
cat(sprintf("  라벨 일치율(상태명 스왑 허용): %.4f  [1.0 = 통과]\n", relabel_match(f1$s,km$cluster)))
cat("  (D>1은 κ 슬랙이어도 w∝between-SS 적응 가중 = 설계상 plain k-means와 다름 — 구현 노트에 명시)\n\n")

## ---------- P4: 시간정보 사용 ----------
cat("---- [P4] 시간축 셔플 ----\n")
set.seed(4); perm<-sample(Tn)
f_o<-sparse_jm(Xp,lam=30,kappa=sqrt(9.5)); f_s<-sparse_jm(Xp[perm,],lam=30,kappa=sqrt(9.5))
f0o<-sparse_jm(Xp,lam=0,kappa=sqrt(9.5)); f0s<-sparse_jm(Xp[perm,],lam=0,kappa=sqrt(9.5))
unshuf<-function(s) s[match(seq_len(Tn),perm)]   # s_shuf[i]는 원 시점 perm[i]의 라벨 → 역정렬
cat(sprintf("  lam=30: 원 전환=%d vs 셔플 전환=%d | 라벨 일치율(셔플→역정렬)=%.3f  [전환수·라벨 달라야 통과]\n",
  nsw(f_o$s), nsw(f_s$s), relabel_match(f_o$s, unshuf(f_s$s))))
cat(sprintf("  lam=0 : 원 vs 셔플(역정렬) 라벨 일치율=%.4f  [1.0 근접 = 순열 등변성 확인]\n\n",
  relabel_match(f0o$s, unshuf(f0s$s))))

## ---------- P7: λ/κ 결합 (D=50 전 차원 정보성 — κ 양쪽 구속) ----------
cat("---- [P7] κ 2배 → 전환 증가, λ 2배 → 복원 ----\n")
res7<-matrix(0,5,3); colnames(res7)<-c("l50k9.5","l50k38","l100k38")
w_l1<-numeric(3)
for(sd_ in 1:5){ set.seed(100+sd_)
  Tn7<-800; D7<-50
  st7<-integer(Tn7); st7[1]<-1; for(t in 2:Tn7) st7[t]<-if(runif(1)<0.985) st7[t-1] else 3L-st7[t-1]
  amp<-runif(D7,0.1,0.6)
  X7<-sapply(1:D7,function(j) c(-1,1)[st7]*amp[j]+rnorm(Tn7)); X7<-scale(X7)
  cfg<-list(c(50,9.5),c(50,38),c(100,38))
  for(ci in 1:3){ f<-sparse_jm(X7,lam=cfg[[ci]][1],kappa=sqrt(cfg[[ci]][2])); res7[sd_,ci]<-nsw(f$s)
    if(sd_==1) w_l1[ci]<-sum(abs(f$w)) }
}
cat(sprintf("  전환수 평균(5시드): (λ50,κ²9.5)=%.1f → (λ50,κ²38)=%.1f → (λ100,κ²38)=%.1f\n",
  mean(res7[,1]),mean(res7[,2]),mean(res7[,3])))
cat(sprintf("  ‖w‖₁ (시드1): %.2f → %.2f → %.2f  [κ 구속 실효 확인 — 불변이면 M3 위반]\n\n", w_l1[1],w_l1[2],w_l1[3]))

## ---------- P9: CV 비용 반응 (복사 CV 루프, 5bps→50bps) ----------
cat("---- [P9] CV 내부 비용 5→50bps 재튜닝 ----\n")
## ls_sh_t1 사본에서 비용 상수만 치환 (치환 diff 명시)
src<-readLines("snip_ls.R"); i<-grep("5e-4",src)
cat("  원문 :",trimws(src[i]),"\n")
src2<-sub("5e-4","COSTBP",src); cat("  치환 :",trimws(src2[i]),"\n")
src2<-sub("^ls_sh_t1<-","ls_sh_cost<-",src2)
eval(parse(text=paste(src2[grep("ls_sh_cost<-",src2):length(src2)],collapse="\n")))
source("../../02_Infrastructure/ramp/ramp_shumulvey_features.R")  # build_feat_v2 (모듈 read-only 사용)
sel9<-list()
for(sd_ in 1:3){ set.seed(200+sd_)
  Tn9<-1764
  st9<-integer(Tn9); st9[1]<-1; for(t in 2:Tn9) st9[t]<-if(runif(1)<0.985) st9[t-1] else 3L-st9[t-1]
  a9<-c(-8e-4,8e-4)[st9]+rnorm(Tn9,0,0.004); m9<-rnorm(Tn9,2e-4,0.01)
  Fe<-as.matrix(build_feat_v2(a9,m9,"f15"))
  okr<-which(apply(Fe,1,function(r)all(is.finite(r))))
  Fe<-Fe[okr,]; a9k<-a9[okr]
  Xs9<-scale(Fe)
  pick<-function(costbp){ best<-list(sh=-Inf,lam=NA,k2=NA)
    for(g in 1:nrow(GRID9)){ f<-tryCatch(sparse_jm(Xs9,lam=GRID9$lam[g],kappa=sqrt(GRID9$k2[g])),error=function(e)NULL)
      if(is.null(f))next; COSTBP<<-costbp; sh<-ls_sh_cost(f$s,a9k)
      if(is.finite(sh)&&sh>best$sh)best<-list(sh=sh,lam=GRID9$lam[g],k2=GRID9$k2[g],nsw=nsw(f$s)) }
    best }
  b5<-pick(5e-4); b50<-pick(50e-4)
  sel9[[sd_]]<-c(lam5=b5$lam,k5=b5$k2,sw5=b5$nsw,lam50=b50$lam,k50=b50$k2,sw50=b50$nsw)
  cat(sprintf("  시드%d: 5bps → (λ=%g,κ²=%g, 전환%d) | 50bps → (λ=%g,κ²=%g, 전환%d)\n",
    sd_, b5$lam,b5$k2,b5$nsw, b50$lam,b50$k2,b50$nsw))
}
cat("  [판정 기준: 50bps에서 λ 증가 또는 전환수 감소 — 불변이면 C6 위반]\n\n")

## ---------- O6 micro + CLAIM(last-state ≡ filter) ----------
cat("---- [O6-micro] 온라인 전환 vs 인샘플(스무더) 전환 ----\n")
set.seed(5); Tn6<-1500
st6<-integer(Tn6); st6[1]<-1; for(t in 2:Tn6) st6[t]<-if(runif(1)<0.985) st6[t-1] else 3L-st6[t-1]
X6<-sapply(1:6,function(j) c(-0.6,0.6)[st6]*runif(1,0.5,1)+rnorm(Tn6)); X6<-scale(X6)
f6<-sparse_jm(X6,lam=50,kappa=sqrt(9.5))
C6<-matrix(0,Tn6,2); for(k in 1:2){d2<-sweep(X6,2,f6$th[k,],"-")^2; C6[,k]<-as.numeric(d2%*%f6$w)}
onl<-integer(500); for(q in 1:500){ tau<-1000+q; onl[q]<-jumpDPlast(C6[1:tau,,drop=FALSE],50) }
cat(sprintf("  같은 구간(1001..1500) 전환수: 스무더 경로=%d | 온라인(prefix-DP last)=%d  [온라인 >= 스무더 기대]\n\n",
  nsw(f6$s[1001:1500]), nsw(onl)))

cat("---- [CLAIM] refit일 last-state(cur) ≡ 온라인 필터(jumpDPlast) — 구현측 '월간 케이던스 동일' 주장 ----\n")
idr<-0; fpr<-0
for(r in 1:50){ set.seed(300+r)
  Tt<-600; stt<-integer(Tt); stt[1]<-1; for(t in 2:Tt) stt[t]<-if(runif(1)<0.985) stt[t-1] else 3L-stt[t-1]
  Xt<-sapply(1:6,function(j) c(-0.5,0.5)[stt]*runif(1,0.4,1)+rnorm(Tt)); Xt<-scale(Xt)
  ft<-sparse_jm(Xt,lam=50,kappa=sqrt(9.5))
  Ct<-matrix(0,Tt,2); for(k in 1:2){d2<-sweep(Xt,2,ft$th[k,],"-")^2; Ct[,k]<-as.numeric(d2%*%ft$w)}
  if(ft$s[Tt]==jumpDPlast(Ct,50)) idr<-idr+1
  if(all(jumpDP(Ct,50)==ft$s)) fpr<-fpr+1
}
cat(sprintf("  s[T]==jumpDPlast(C_frozen): %d/50 | 수렴 고정점(jumpDP(C)==s): %d/50\n\n", idr, fpr))

## ---------- P10: 롱온리 (BL 층 — snip_bl.R 사본) ----------
cat("---- [P10] 전 팩터 음수 뷰 강제 → 음수 0 · Σw=1 · 시장 비중 증가 ----\n")
NF<-6; NA_<-7; delta<-2.5; w_ew<-rep(1/NA_,NA_)
P<-matrix(0,NF,NA_); for(j in 1:NF)P[j,1+j]<-1; P[,1]<- -1   # 엔진 L190 재현
source("snip_bl.R")    # solveMVO / bl_w / te_ex (엔진 L191-197)
suppressPackageStartupMessages(library(arrow))
sa<-as.data.table(read_parquet("synth_A.parquet"))
Rm<-as.matrix(sa[,c("Market","Value","Size","Momentum","Quality","LowVol","Growth"),with=FALSE])
a126<-1-exp(log(0.5)/126); Sacc<-matrix(0,7,7)
for(t in 1:nrow(Rm)){ xx<-Rm[t,]; Sacc<-a126*tcrossprod(xx)+(1-a126)*Sacc }
Sig<-Sacc*PER
for(vv_ in list(rep(-0.50,6), rep(-0.05,6))){
  for(cc in c(0.01,0.1,1)){
    w<-bl_w(Sig,vv_,cc)
    cat(sprintf("  view=%+.2f c=%.2f: min(w)=%.2e | Σw=%.8f | w_Market=%.3f (EW 1/7=%.3f) %s\n",
      vv_[1], cc, min(w), sum(w), w[1], 1/7,
      ifelse(min(w)>=-1e-10 && abs(sum(w)-1)<1e-8 && w[1]>1/7, "[PASS]", "[FAIL]")))
  }
}

## ---------- S2: 시장환경 피처 6모델 동일값 ----------
cat("\n---- [S2] 시장환경 피처(mkt21/vix21) 팩터 간 동일 ----\n")
set.seed(6); m_<-rnorm(700,2e-4,0.01); aA<-rnorm(700,0,0.004); aB<-rnorm(700,5e-4,0.005)
FA<-build_feat_v2(aA,m_,"f15"); FB<-build_feat_v2(aB,m_,"f15")
cat(sprintf("  max|Δmkt21|=%.3e | max|Δvix21|=%.3e  [0 = 동일값 통과]\n",
  max(abs(FA$mkt21-FB$mkt21),na.rm=TRUE), max(abs(FA$vix21-FB$vix21),na.rm=TRUE)))

cat("\nPROBE_UNIT_DONE\n"); sink()
