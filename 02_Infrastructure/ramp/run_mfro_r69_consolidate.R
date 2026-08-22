## run_mfro_r69_consolidate.R — R69: MFRO 아크 통합 판정 (배포 거리 귀속)
##
## ★사전 선언(결과 전 기록): 이 라운드는 새 측정이 아니라 **조립**이다.
##   R58~R68 의 저장 산출물에서 수치를 읽어 4개 취약성 축 + 자본 게이트를 하나의 표로 만든다.
##   ★수치를 손으로 옮기지 않는다 — 재타이핑이 오류의 진입점이기 때문이다.
##   판정 문턱은 아래에 **읽기 전에** 고정한다.
##   ★이 라운드는 '배포 가능한가' 를 새로 묻지 않는다(R61 이 HARD 0/3 으로 이미 답했다).
##     묻는 것은 **어느 축이 얼마나 구속하는가** = 갭 귀속이다.
suppressPackageStartupMessages({library(data.table)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

## ── 문턱 사전 고정 (읽기 전) ──
TH <- list(
  tail_top3_positive = TRUE,    # ①꼬리: 상위 3개월 제거 후 평균이 양수 유지
  config_drop_max    = 0.50,    # ②구성: 인접 구성 대비 낙폭 50% 미만
  power_min          = 0.50,    # ③검정력: 현 창에서 0.50 이상
  cost_drop_max      = 0.30,    # ④비용: 15->30bps 에서 t 감소 30% 미만
  hard_port_t        = 2.95, hard_oos = 0.70, hard_calmar = 0.64)
cat("=== R69 MFRO 통합 판정 — 문턱은 읽기 전 고정 ===\n")
str(TH)

rd<-function(p) if(file.exists(p)) readRDS(p) else NULL
R58<-rd(".cache/_mfro_r58.rds"); R60<-rd(".cache/_mfro_r60.rds")
R61<-rd(".cache/_mfro_r61_contract.rds"); R63<-rd(".cache/_mfro_r63.rds")
R64<-rd(".cache/_mfro_r64.rds"); R65<-rd(".cache/_mfro_r65.rds"); R68<-rd(".cache/_mfro_r68.rds")
have<-c(R58=!is.null(R58),R60=!is.null(R60),R61=!is.null(R61),R63=!is.null(R63),
        R64=!is.null(R64),R65=!is.null(R65),R68=!is.null(R68))
cat("\n[산출물 가용성]\n"); print(have)
stopifnot(all(have))   # ★결측을 조용히 넘기지 않는다

## ── 축① 꼬리 의존 (R60 계열에서 재산출 — 저장된 계열로) ──
suppressMessages({library(sandwich);library(lmtest)})
nwt<-function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1)
  as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=F))[1,3])}
AR<-R60$AR; E<-R60$E; bmf<-R60$bmf
mk<-function(r)E$clean&is.finite(r$pr)&is.finite(bmf)
s<-mk(AR$D1_rotation_top5)&mk(AR$AP_allpos_tilt)
d<-(AR$D1_rotation_top5$pr-AR$AP_allpos_tilt$pr)[s]; o<-order(d,decreasing=TRUE)
ax1<-list(full=mean(d), top1=mean(d[-o[1]]), top3=mean(d[-o[1:3]]), top5=mean(d[-o[1:5]]),
          median=median(d), pos_frac=mean(d>0), n=length(d), t=nwt(d))
ax1$pass <- ax1$top3 > 0

## ── 축② 구성 민감도 (R64 사다리 + R68 공간) ──
lam<-sapply(R64$lambda$out,function(o)o$t); kk<-sapply(R64$k$out,function(o)o$t)
NN<-sapply(R64$N$out,function(o)o$t)
cur_k<-kk[match(5L,R64$k$vals)]; nb_k<-max(kk[R64$k$vals!=5L])
cur_N<-NN[match(25L,R64$N$vals)]; nb_N<-max(NN[R64$N$vals!=25L])
sp<-R68$OUT; cur_sp<-sp$SP_both$mean; nb_sp<-max(sapply(sp[names(sp)!="SP_both"],function(o)o$mean))
ax2<-list(k_cur=cur_k,k_best_other=nb_k,k_drop=1-nb_k/cur_k,
          N_cur=cur_N,N_best_other=nb_N,N_drop=1-nb_N/cur_N,
          sp_cur=cur_sp,sp_best_other=nb_sp,sp_drop=1-nb_sp/cur_sp)
ax2$worst_drop<-max(ax2$k_drop,ax2$N_drop,ax2$sp_drop)
ax2$pass <- ax2$worst_drop < TH$config_drop_max

## ── 축③ 검정력 (R63) ──
ax3<-list(power=R63$p132, n=R63$n0, need_n=R63$need, effect_yr=1200*R63$m0)
ax3$pass <- ax3$power >= TH$power_min

## ── 축④ 비용 견고성 (R65) ──
o15<-R65$OUT[["15"]]; o30<-R65$OUT[["30"]]
ax4<-list(t15=o15$t,t30=o30$t,drop=1-abs(o30$t)/abs(o15$t),p15=o15$p,p30=o30$p)
ax4$pass <- ax4$drop < TH$cost_drop_max && o30$p < 0.05

## ── 자본 게이트 (R61) ──
e<-R61[["D1_rotation_top5_clean"]]$essence$essence
gt<-list(port_t=as.numeric(e$portfolio_alpha_t_nw_lag3), calmar=as.numeric(e$calmar),
         oos=as.numeric(e$oos_retention), sharpe=as.numeric(e$net_sharpe), ir=as.numeric(e$net_ir))

cat("\n=== 취약성 4축 ===\n")
cat(sprintf("  ①꼬리 의존   전체 %+.4f -> 상위1제 %+.4f · 상위3제 %+.4f · 상위5제 %+.4f (%%/월)\n",
  100*ax1$full,100*ax1$top1,100*ax1$top3,100*ax1$top5))
cat(sprintf("               중앙 %+.4f · 양수월 %.1f%% · n=%d · NW-t %+.3f  ⇒ %s\n",
  100*ax1$median,100*ax1$pos_frac,ax1$n,ax1$t,ifelse(ax1$pass,"PASS(상위3제 양수)","FAIL")))
cat(sprintf("  ②구성 민감도 k %+.3f->%+.3f(낙폭 %.0f%%) · N %+.3f->%+.3f(%.0f%%) · 공간 %+.4f->%+.4f(%.0f%%)\n",
  ax2$k_cur,ax2$k_best_other,100*ax2$k_drop,ax2$N_cur,ax2$N_best_other,100*ax2$N_drop,
  100*ax2$sp_cur,100*ax2$sp_best_other,100*ax2$sp_drop))
cat(sprintf("               최악 낙폭 %.0f%% (문턱 %.0f%%) ⇒ %s\n",
  100*ax2$worst_drop,100*TH$config_drop_max,ifelse(ax2$pass,"PASS","FAIL")))
cat(sprintf("  ③검정력     현 창 %.3f (n=%d) · 효과 연 %.2f%% · 필요 n %d ⇒ %s\n",
  ax3$power,ax3$n,ax3$effect_yr,ax3$need_n,ifelse(ax3$pass,"PASS","FAIL")))
cat(sprintf("  ④비용 견고성 15bps t %+.3f (p %.3f) -> 30bps t %+.3f (p %.3f) · 감소 %.1f%% ⇒ %s\n",
  ax4$t15,ax4$p15,ax4$t30,ax4$p30,100*ax4$drop,ifelse(ax4$pass,"PASS","FAIL")))

cat("\n=== 자본 게이트 (R61, 계약 경유) ===\n")
cat(sprintf("  PORT_t %+.3f / %.2f = %.0f%% %s | calmar %.3f / %.2f = %.0f%% %s | oos %.3f %s\n",
  gt$port_t,TH$hard_port_t,100*gt$port_t/TH$hard_port_t,ifelse(gt$port_t>=TH$hard_port_t,"PASS","FAIL"),
  gt$calmar,TH$hard_calmar,100*gt$calmar/TH$hard_calmar,ifelse(gt$calmar>=TH$hard_calmar,"PASS","FAIL"),
  gt$oos,"(분모 붕괴 — 통과로 쓰지 않음)"))

cat("\n=== ★갭 귀속 — 어느 축이 얼마나 구속하나 ===\n")
gaps<-data.table(
  축=c("꼬리 의존","구성 민감도","검정력","비용 견고성","PORT_t","calmar"),
  현재=c(sprintf("상위3제 %+.4f",100*ax1$top3), sprintf("낙폭 %.0f%%",100*ax2$worst_drop),
        sprintf("%.3f",ax3$power), sprintf("감소 %.1f%%",100*ax4$drop),
        sprintf("%+.3f",gt$port_t), sprintf("%.3f",gt$calmar)),
  문턱=c(">0","<50%",">=0.50","<30%",">=2.95",">=0.64"),
  판정=c(ifelse(ax1$pass,"PASS","FAIL"),ifelse(ax2$pass,"PASS","FAIL"),
        ifelse(ax3$pass,"PASS","FAIL"),ifelse(ax4$pass,"PASS","FAIL"),
        ifelse(gt$port_t>=TH$hard_port_t,"PASS","FAIL"),ifelse(gt$calmar>=TH$hard_calmar,"PASS","FAIL")),
  달성률=c(NA_real_,NA_real_,ax3$power/TH$power_min,NA_real_,
          gt$port_t/TH$hard_port_t,gt$calmar/TH$hard_calmar))
print(gaps)
np<-sum(gaps$판정=="PASS")
cat(sprintf("\n  통과 %d/6\n",np))
cat(sprintf("  ★가장 구속하는 축 = %s (달성률 %.0f%%)\n",
  gaps$축[which.min(gaps$달성률)],100*min(gaps$달성률,na.rm=TRUE)))
fwrite(gaps,"06_Registry/mfro_consolidated_verdict_20260822.csv")
saveRDS(list(ax1=ax1,ax2=ax2,ax3=ax3,ax4=ax4,gt=gt,gaps=gaps,TH=TH),".cache/_mfro_r69.rds")
cat("\n산출: 06_Registry/mfro_consolidated_verdict_20260822.csv\nR69_DONE\n")
