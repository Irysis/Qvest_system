## run_fof_caveat_dsr.R — caveat 4종 정밀 + DSR(sweep) 판정.
## ① 절대 SR 1.18 (standalone) ② MDD 36.6% ③ IC-lookback 12m 의존 ④ DSR(chain vs sweep).
## measurement-graduation §3: sweep = 열거 trial argmax-pick. fof = optimizer 10종 + sensitivity 9격자 argmax → sweep.
suppressPackageStartupMessages({library(data.table)})
setDTthreads(1)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"
con<-file(file.path(OUT,"_fof_caveat_dsr.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
w("============== caveat 4종 정밀 + DSR =============="); w(sprintf("실행 %s",as.character(Sys.time())))

## fof Tilt net 시리즈 (standalone 절대지표 재확인)
ser<-readRDS(file.path(OUT,"_optsweep2_series.rds"))
fof<-as.data.table(ser[["Tilt"]]); fof<-fof[is.finite(net)]; setorder(fof,date)
r<-fof$net
SR<-mean(r)/sd(r)*sqrt(12); nav<-cumprod(1+r); MDD<-max(1-nav/cummax(nav)); CAGR<-prod(1+r)^(12/length(r))-1
w(sprintf("\n[① 절대 standalone] n=%d net SR=%.3f CAGR=%+.1f%% MDD=%.1f%% calmar=%.2f",
          length(r), SR, 100*CAGR, 100*MDD, CAGR/MDD))
w("  → SR 1.18 ≪ 목표 2.5. active-알파 게이트는 통과하나 standalone 시스템 아님(whitepaper §6.1 확인).")

## ── ④ DSR (Bailey-Lopez de Prado Deflated Sharpe Ratio) ──
## DSR = Φ( (SR_obs - SR_benchmark)·sqrt(N-1) / sqrt(1 - skew·SR + (kurt-1)/4·SR^2) )
## SR_benchmark = expected max SR under N independent trials (multiple-testing baseline).
## N = 후보 trial 수. fof sweep: optimizer 10 + sensitivity 9 + rounds(R1~R12 다수 config). 보수적 N 범위 산정.
## 월별 SR (비연율화) 사용.
sr_m<-mean(r)/sd(r); n<-length(r)
sk<-{m<-mean(r);s<-sd(r); mean((r-m)^3)/s^3}; ku<-{m<-mean(r);s<-sd(r); mean((r-m)^4)/s^4}
## E[max SR] over N trials (Bailey approx): sr0 = sqrt(Var(SR_trials)) * ((1-γ)Φ^-1(1-1/N) + γΦ^-1(1-1/(N·e)))
emax_sr<-function(N, var_sr){ g<-0.5772156649; e<-exp(1)
  sqrt(var_sr)*((1-g)*qnorm(1-1/N) + g*qnorm(1-1/(N*e))) }
## Var(SR_trials): 보수적으로 trial 간 SR 분산을 sensitivity grid 9개 monthly-SR로 추정
sens<-fread(file.path(OUT,"sensitivity_results.csv"))
## sensitivity SR은 연율화 → 월별로 환산 (/sqrt(12))
trial_sr_m<-sens$SR/sqrt(12)
var_sr_trials<-var(trial_sr_m)
dsr_for_N<-function(N){
  sr0<-emax_sr(N, var_sr_trials)
  num<-(sr_m - sr0)*sqrt(n-1)
  den<-sqrt(1 - sk*sr_m + ((ku-1)/4)*sr_m^2)
  pnorm(num/den)
}
w("\n[④ DSR — sweep 판정시 게이트 ≥0.5 HARD]")
w(sprintf("  monthly SR=%.4f n=%d skew=%.2f kurt=%.2f  Var(SR_trials)=%.5f (sensitivity 9격자)", sr_m,n,sk,ku,var_sr_trials))
for(N in c(10,19,30,50,100)){
  d<-dsr_for_N(N); w(sprintf("  N=%-3d trials → DSR=%.3f  %s", N, d, ifelse(d>=0.5,"PASS","FAIL"))) }
w("  ※ sweep 분류 근거: optimizer 10종(argmax absSR=Tilt) + sensitivity 9격자(argmax-pass=BASE) = 열거 argmax-pick.")
w("    chain 면제 불가: 변형선택이 OOS(2018+ port_t·oos_retention) 반복조회 기반(§3 chain 요건 ② IS-only 위반).")
w("  → DSR(sweep)는 N≈19+ 에서 게이트 의존적. whitepaper §7 caveat 5(DSR 미판정) = sweep이면 미충족 리스크.")

## ── ③ IC-lookback 12m 의존: look-ahead 아닌 robustness 취약 (whitepaper R11 재인용·해석) ──
w("\n[③ IC-lookback 의존] sensitivity 실측(파일):")
for(i in 1:nrow(sens)) if(sens$tag[i] %in% c("BASE","ic6","ic24"))
  w(sprintf("  %-6s SR=%.2f pt_full=%.2f pt_18p=%.2f oos=%.2f", sens$tag[i],sens$SR[i],sens$pt_full[i],sens$pt_18p[i],sens$oos[i]))
w("  → 12m만 게이트 통과(ic6 oos0.17·ic24 oos-0.52 둘다 FAIL). 12m은 팩터모멘텀 문헌표준이나 단일 lookback 의존 = robustness 취약(과적합 신호 아님이나 fragile).")

## ── ② MDD 36.6% ──
w("\n[② MDD] standalone MDD=36.6% > 25% 제약. structural-drawdown 규약: KR 2005+ BM 자체 MDD 54.5% → hard-fail 아님(tail_review). 단 배포 제약 위반.")

w("\n================ caveat 종합 ================")
w("  ① 절대SR 1.18: active-알파지 standalone 2.5 아님 — 미해소(본질)")
w("  ② MDD 36.6%: tail_review(hard-fail 아님)이나 25% 초과 — 오버레이 무력(R10)")
w("  ③ IC-lookback 12m 의존: PIT청정(STALE 양수)이나 단일 lookback fragile — 미해소")
w("  ④ DSR: sweep 분류 → N≈19+ 게이트 의존. 미산정이었음(이제 산정). chain 면제 불가(OOS-informed 선택)")
saveRDS(list(SR=SR,MDD=MDD,CAGR=CAGR,dsr_N19=dsr_for_N(19),dsr_N50=dsr_for_N(50),
             skew=sk,kurt=ku,var_sr_trials=var_sr_trials), file.path(OUT,"_fof_caveat_dsr.rds"))
cat("CAVEAT|",sprintf("SR=%.2f MDD=%.1f DSR_N19=%.3f DSR_N50=%.3f",SR,100*MDD,dsr_for_N(19),dsr_for_N(50)),"\n")
close(con); cat("FOF_CAVEAT_DSR_DONE\n")
