## run_fof_bmarg_significance.R — ΔIR=+0.48 vs paired-t=0.71 모순 해소.
## 핵심 질문: ΔIR 증분이 (a) 실제 fof 직교알파 기여인가, (b) 두 양수-IR 무상관 시리즈의 평균화(diversification) 산술 아티팩트인가?
## 규율: paired-NW-t authoritative (SR 비율비교 금지, [[project-pg2-orthogonal-alpha-search]] 교훈).
## 테스트: ① ΔIR block-bootstrap CI ② random-noise sleeve diversification 베이스라인(같은 vol 무상관 노이즈가 같은 ΔIR 내면 = 아티팩트).
suppressPackageStartupMessages({library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); set.seed(42)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"
P<-fread(file.path(OUT,"book_marginal_panel.csv"))   # realized_ym, fof_net, fof_act, book_net, book_act
P<-P[is.finite(fof_act)&is.finite(book_act)]; setorder(P,realized_ym)
con<-file(file.path(OUT,"_fof_bmarg_sig.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
ann<-function(x) mean(x)/sd(x)*sqrt(12)
w("============== ΔIR 유의성 / diversification 아티팩트 판별 =============="); w(sprintf("실행 %s",as.character(Sys.time())))
w(sprintf("n=%d, %s~%s", nrow(P), min(P$realized_ym), max(P$realized_ym)))

ir_book<-ann(P$book_act); ir_fof<-ann(P$fof_act)
combine_ir<-function(lam,bk,ff) { v<-(1-lam)*bk+lam*ff; mean(v)/sd(v)*sqrt(12) }
lam_grid<-seq(0,1,by=0.05)
dIR_at<-function(bk,ff){ irs<-sapply(lam_grid,combine_ir,bk=bk,ff=ff); max(irs)-ann(bk) }
dIR_half<-function(bk,ff) combine_ir(0.5,bk,ff)-ann(bk)
w(sprintf("\nincumbent book IR=%.3f  fof IR=%.3f  cor_active=%.3f", ir_book, ir_fof, cor(P$book_act,P$fof_act)))
w(sprintf("관측 ΔIR: λ-opt=%.3f, λ=0.5=%.3f", dIR_at(P$book_act,P$fof_act), dIR_half(P$book_act,P$fof_act)))

## ── 테스트 ①: ΔIR(λ=0.5) stationary block-bootstrap CI ──
bb<-function(x,bl=6L){ n<-length(x); nb<-ceiling(n/bl); st<-sample.int(n,nb,replace=TRUE)
  idx<-unlist(lapply(st,function(s) ((s-1+0:(bl-1))%%n)+1)); idx[1:n] }
B<-2000
dist_dIR<-numeric(B)
for(b in 1:B){ id<-bb(1:nrow(P),6L); dist_dIR[b]<-dIR_half(P$book_act[id],P$fof_act[id]) }
ci<-quantile(dist_dIR,c(.025,.5,.975))
w(sprintf("\n[①ΔIR(λ=0.5) block-bootstrap B=%d] median=%.3f  95%%CI=[%.3f, %.3f]", B, ci[2],ci[1],ci[3]))
w("  (CI는 ΔIR 추정 불확실성일 뿐 — 아티팩트 여부는 ②로 판별)")

## ── 테스트 ②: random-noise sleeve diversification 베이스라인 ──
## fof_act를 '같은 변동성·book과 무상관인 순수 노이즈'로 대체. 만약 노이즈도 동일 ΔIR을 내면,
## ΔIR은 직교알파가 아니라 두 양수-IR 무상관 시리즈 평균화의 산술효과(= 아티팩트).
## 단 노이즈 IR을 fof와 동일(+1.008)하게 맞춰 공정비교: mean/sd 동일하게 스케일.
sd_f<-sd(P$fof_act); mu_f<-mean(P$fof_act)
Bn<-2000; dist_noise_dIR<-numeric(Bn)
for(b in 1:Bn){ z<-rnorm(nrow(P)); z<-(z-mean(z))/sd(z)*sd_f + mu_f   # 같은 mean/sd → 같은 standalone IR
  dist_noise_dIR[b]<-dIR_half(P$book_act,z) }
nci<-quantile(dist_noise_dIR,c(.025,.5,.975))
w(sprintf("\n[②동일-IR 무상관 노이즈 sleeve, B=%d] ΔIR(λ=0.5) median=%.3f  95%%CI=[%.3f, %.3f]", Bn, nci[2],nci[1],nci[3]))
obs_half<-dIR_half(P$book_act,P$fof_act)
pctl<-mean(dist_noise_dIR < obs_half)
w(sprintf("  관측 fof ΔIR(=%.3f)이 노이즈 분포의 %.1f 백분위. ", obs_half, 100*pctl))
w(sprintf("  → 노이즈 베이스라인이 ΔIR median %.3f을 *그냥* 생성. fof ΔIR이 노이즈 95pctCI와 겹치면 = diversification 아티팩트.", nci[2]))
verdict_artifact <- (obs_half >= nci[1] && obs_half <= nci[3])
w(sprintf("  노이즈 95%%CI [%.3f,%.3f] 안에 fof ΔIR %.3f 포함? %s → %s",
          nci[1],nci[3],obs_half, verdict_artifact,
          ifelse(verdict_artifact,"★아티팩트(diversification 산술) — 직교알파 기여 아님","노이즈 초과 — 실질 기여 가능")))

## ── 테스트 ③: paired-NW-t 재확인 (PIT 점진 λ, authoritative) ──
## (메인 스크립트와 동일하나 여기 재계산 — 결합 active − incumbent active)
minw<-36L; P[,combo_pit:=NA_real_]
for(i in (minw+1):nrow(P)){ tr<-P[1:(i-1)]
  ig<-sapply(lam_grid,function(l){v<-(1-l)*tr$book_act+l*tr$fof_act;mean(v)/sd(v)*sqrt(12)})
  lo<-lam_grid[which.max(ig)]; P[i,combo_pit:=(1-lo)*book_act+lo*fof_act] }
pit<-P[is.finite(combo_pit)]; pr<-pit[,.(d=combo_pit-book_act)]
ft<-lm(d~1,pr); tp<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=FALSE))[1,3])
w(sprintf("\n[③paired-NW-t 결합−incumbent active, lag3] mean=%+.4f%%/월 t=%+.2f  → %s",
          100*mean(pr$d), tp, ifelse(tp>2,"유의","비유의(<2)")))

## ── 결론 ──
w("\n================ 결론 ================")
w(sprintf("  active 상관 %.3f (직교) · ΔIR(λ.5) %.3f · ΔIR 노이즈-베이스라인 median %.3f", cor(P$book_act,P$fof_act), obs_half, nci[2]))
w(sprintf("  paired-NW-t %.2f (%s) · 노이즈구별 %s",
          tp, ifelse(tp>2,"유의","비유의"), ifelse(verdict_artifact,"불가(아티팩트)","가능")))
final <- if(tp>2 && !verdict_artifact) "기여 유의 — 등록 검토" else
         if(verdict_artifact) "ΔIR=diversification 아티팩트 + paired-t 비유의 → 직교하나 *기여 미입증*. screen-tier" else
         "paired-t 비유의 → 기여 미입증. screen-tier"
w(sprintf("  ★최종: %s", final))
saveRDS(list(ci=ci,nci=nci,obs_half=obs_half,verdict_artifact=verdict_artifact,t_pair=tp,
             ir_book=ir_book,ir_fof=ir_fof,cor_active=cor(P$book_act,P$fof_act),final=final),
        file.path(OUT,"_fof_bmarg_sig.rds"))
cat("SIG|",sprintf("noise_dIR_med=%.3f obs=%.3f artifact=%s t_pair=%.2f",nci[2],obs_half,verdict_artifact,tp),"\n")
close(con); cat("FOF_BMARG_SIG_DONE\n")
