## run_mfro_r63_power.R — R63: 검정력 역산 ('미결(검정력)' vs '효과 크기 부족' 구분)
##
## ★사전 선언(결과 전): R62 가 랭킹 고유 기여를 +0.2103%/월(t +1.671, n=132) · 우측 꼬리 의존으로 특성화했다.
##   질문 = 이 크기를 t>=1.96 으로 확립하려면 몇 개월이 필요한가? 132 가 원리적으로 부족한가?
##   ★계약 경고 준수: verdict_with_power 에 **arm 자신의 sd** 를 넘기면 바가 t 검정의 재진술로 퇴화한다
##     (implied_t_threshold 로 그 여부를 항상 신고받는다).
##   ★분포 형태 존중: 효과가 우측 꼬리 의존이므로 정규 근사 t-검정력은 낙관적이다.
##     블록 부트스트랩으로 **실제 분포에서** P(t>=1.96) 을 n 별로 재는 것을 1급 지표로 둔다.
##   ★예상: 부트스트랩 검정력이 정규 근사보다 낮게 나올 것(꼬리 의존 -> t 통계량 불안정).
suppressPackageStartupMessages({library(data.table)});suppressMessages({library(sandwich);library(lmtest)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
## ★nw_inflation_measured 는 .nw_t_mean 이 없으면 조용히 NA 를 반환한다(함수 주석 명시).
##   canonical_screen_bt.R 를 먼저 로드해야 실측이 가정을 이긴다.
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
stopifnot(exists(".nw_t_mean"))   # 조용한 NA 낙하 차단
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1)
  as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
Z<-readRDS(".cache/_mfro_r60.rds"); AR<-Z$AR; E<-Z$E; bmf<-Z$bmf
mk<-function(r)E$clean&is.finite(r$pr)&is.finite(bmf)
s<-mk(AR$D1_rotation_top5)&mk(AR$AP_allpos_tilt)
d<-(AR$D1_rotation_top5$pr-AR$AP_allpos_tilt$pr)[s]
n0<-length(d); m0<-mean(d); t0<-nwt(d); sd0<-sd(d)
cat(sprintf("=== R63 검정력 (랭킹 고유 기여 D1-AP) ===\n"))
cat(sprintf("  실측: n=%d · 평균 %+.4f%%/월 · sd %.4f%% · NW-t %+.3f · 왜도 %.3f\n",
  n0,100*m0,100*sd0,t0,{x<-(d-mean(d))/sd(d);mean(x^3)}))

cat("\n[① 계약 verdict_with_power — 바가 무엇을 재는지 신고받는다]\n")
v<-verdict_with_power(observed_t=t0, observed_monthly=m0, n=n0, t_threshold=1.96, series=d)
cat(sprintf("  verdict = %s\n",v$verdict))
cat(sprintf("  required %+.4f%%/월 (연 %+.2f%%) | nw_inflation %.3f (%s)\n",
  100*v$required$required_monthly,100*v$required$required_annual,
  v$required$nw_inflation,v$required$nw_inflation_source))
cat(sprintf("  se_arm %.4f%% | implied_t_threshold %.3f | NEGATIVE_POWERED 도달가능 %s | 바가 t 재진술 %s\n",
  100*v$se_arm,v$implied_t_threshold,v$negative_powered_reachable,v$bar_restates_t))
if(!is.null(v$note)) cat("  note:",v$note,"\n")

cat("\n[② 직접 역산 — 관측 효과를 t>=1.96 으로 확립하는 데 필요한 n (정규 근사)]\n")
nw_i<-nw_inflation_measured(d)
stopifnot(is.finite(nw_i))   # 실측 실패 시 중단(가정값으로 조용히 진행 금지)
need<-ceiling((1.96*sd0*nw_i/abs(m0))^2)
cat(sprintf("  측정 nw_inflation %.3f | 필요 n = %d 개월 (%.1f년) | 현재 %d ⇒ 배수 %.2f\n",
  nw_i,need,need/12,n0,need/n0))

cat("\n[★③ 블록 부트스트랩 검정력 — 실제 분포에서 P(NW-t >= 1.96)]\n")
set.seed(20260822); B<-12L
pw<-function(nn,R=400){cnt<-0L
  for(i in 1:R){st<-sample(1:(n0-B+1),ceiling(nn/B),replace=TRUE)
    x<-unlist(lapply(st,function(j)d[j:(j+B-1)]))[1:nn]
    tt<-nwt(x); if(is.finite(tt)&&tt>=1.96) cnt<-cnt+1L}
  cnt/R}
for(nn in c(132L,200L,264L,396L,528L)){
  cat(sprintf("  n=%3d (%.0f년): 검정력 %.3f\n",nn,nn/12,pw(nn)))}

cat("\n[④ 대조 — 정규 근사가 낙관적인가]\n")
zpw<-function(nn){se<-sd0/sqrt(nn)*nw_i; 1-pnorm(1.96-abs(m0)/se)}
for(nn in c(132L,264L,528L)) cat(sprintf("  n=%3d 정규근사 %.3f\n",nn,zpw(nn)))

cat("\n[⑤ 판정]\n")
p132<-pw(132L)
cat(sprintf("  현 창(132) 검정력 = %.3f\n",p132))
lab<-if(p132<0.5) "★미결(검정력 부족) — 이 창에서는 이 크기를 확립할 수 없다" else
     if(p132<0.8) "경계 — 검정력 %.0f%%, 관측 미달이 효과 부재를 뜻하지 않는다" else
     "★효과 크기 부족 — 검정력이 충분한데 미달"
cat(sprintf("  ⇒ %s\n",sprintf(lab,100*p132)))
cat(sprintf("  검정력 0.80 도달 n ≈ "))
nn<-132L; while(nn<1200L && pw(nn,200)<0.80) nn<-nn+60L
cat(sprintf("%d 개월 (%.1f년)\n",nn,nn/12))
saveRDS(list(n0=n0,m0=m0,t0=t0,sd0=sd0,need=need,p132=p132),".cache/_mfro_r63.rds")
cat("\nR63_DONE\n")
