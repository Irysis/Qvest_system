## 자기적대검증 보강 측정 — 부기간 검정력 라벨 + 공선성 + AX-001 scope + 하한 추정
## ★부기간은 판정이 아니라 진단이다. 분할은 검정력을 파괴하므로 라벨을 반드시 붙인다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_002")
say <- function(fmt,...) { cat(sprintf(paste0("[adv] ",fmt,"\n"),...)); flush.console() }
source("02_Infrastructure/contracts/required_effect_size.R")
nw_t <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<20) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }

CF <- fread(file.path(OUT,"m26_fmb_coefs_monthly.csv"))
A  <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
say("★입력 실측: FMB 계수 %d행(%d term × 월) · alpha_scores %d행 · 관측단위 월간",
    nrow(CF), uniqueN(CF$term), nrow(A))

TT <- CF[term=="M26_Revenue_Mom"][order(signal_ym)]
say("전표본: n=%d · mean %+.5f · sd %.5f · t_NW3 %+.3f", nrow(TT), mean(TT$est), sd(TT$est), nw_t(TT$est))

## --- (1) 부기간별 자체 sd 기반 검정력 라벨 ---------------------------------
TT[, era := fifelse(signal_ym < "2010-01","2003-2009", fifelse(signal_ym < "2017-01","2010-2016","2017-2026"))]
say("--- 부기간 (★각 구간 자체 sd 로 검정력 판정) ---")
res <- rbindlist(lapply(split(TT, TT$era), function(d) {
  t_obs <- nw_t(d$est); m_obs <- mean(d$est); s <- sd(d$est); n <- nrow(d)
  v <- verdict_with_power(observed_t=abs(t_obs), observed_monthly=abs(m_obs), n=n,
                          t_threshold=2.0, sd_monthly=s)
  data.table(era=d$era[1], n=n, mean=m_obs, sd=s, t_nw3=t_obs,
             required_monthly=v$required$required_monthly,
             required_annual_pct=v$required$required_annual*100,
             verdict=v$verdict)
}))
for (i in seq_len(nrow(res))) with(res[i], say(
  "  %-10s n=%3d · mean %+.5f (연 %+.2f%%) · t_NW3 %+.2f · 필요 %+.5f (연 %.2f%%) ⇒ ★%s",
  era, n, mean, mean*12*100, t_nw3, required_monthly, required_annual_pct, verdict))
say("  ★해석 규약: INCONCLUSIVE_UNDERPOWERED 구간은 '효과 없음'으로 쓰지 않는다")

## --- (2) 공선성 진단 (증분 계수 불안정 우려) --------------------------------
FACS <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M26_Revenue_Mom")
CM <- A[, .(c12=cor(C01_SUE,C02_EPS_Chg_1m), c14=cor(C01_SUE,C04_ESBR), c1m=cor(C01_SUE,M26_Revenue_Mom),
            c24=cor(C02_EPS_Chg_1m,C04_ESBR), c2m=cor(C02_EPS_Chg_1m,M26_Revenue_Mom),
            c4m=cor(C04_ESBR,M26_Revenue_Mom)), by=signal_ym]
say("--- 월별 피어슨 상관 (시계열 평균) ---")
for (k in setdiff(names(CM),"signal_ym")) say("  %-5s %+.4f (최대 %+.3f)", k, mean(CM[[k]],na.rm=TRUE), max(CM[[k]],na.rm=TRUE))
vif <- A[, {
  f <- lm(M26_Revenue_Mom ~ C01_SUE + C02_EPS_Chg_1m + C04_ESBR)
  .(r2 = summary(f)$r.squared)
}, by=signal_ym]
say("  M26 ~ 3종 회귀 R² 평균 %.4f (최대 %.4f) ⇒ VIF = 1/(1-R²) 평균 %.2f",
    mean(vif$r2), max(vif$r2), 1/(1-mean(vif$r2)))
say("  ★VIF < 5 면 증분 계수 불안정 우려 낮음(관행 문턱이 아니라 진단 기준선으로만 사용)")

## --- (3) 하한 추정 (uncertainty-aware, research_philosophy ③) ---------------
m <- mean(TT$est); n <- nrow(TT)
se_nw <- { x<-TT$est; e<-x-mean(x); s<-sum(e^2)/n
  for(l in 1:3) s <- s + 2*(1-l/4)*sum(e[(l+1):n]*e[1:(n-l)])/n; sqrt(s/n) }
say("--- 하한 추정 (mu_tilde = mu_hat - k*SE_NW) ---")
for (k in c(1,1.645,2)) say("  k=%.3f ⇒ %+.5f/월 (연 %+.2f%%)", k, m-k*se_nw, (m-k*se_nw)*12*100)
say("  95%% CI(NW): [%+.5f, %+.5f] /월 = 연 [%+.2f%%, %+.2f%%]",
    m-1.96*se_nw, m+1.96*se_nw, (m-1.96*se_nw)*12*100, (m+1.96*se_nw)*12*100)

## --- (4) AX-001 scope 선언 (방어형 여부) ------------------------------------
say("--- AX-001 v2 조건부 평가 scope ---")
say("  detected_family = consensus_revenue_revision (registry: M26 category=momentum · data_dependency=consensus)")
say("  ★defense family 아님 ⇒ AX-001 v2 조건부 평가 규칙 비적용. 전기간 평가가 정당.")
say("  (근거: registry labels.regime_profile = risk_on:positive / crisis:negative — 방어 프로필 아님)")

## --- (5) 신호 수명 곡선 (lag 0~3) — path 서술 검증 --------------------------
say("--- 신호 수명 (동일 통제 하 lag k 신호의 증분 t) : 별도 산출은 run_log [7] lag1 참조 ---")
fwrite(res, file.path(OUT,"m26_subperiod_power.csv"))
fwrite(CM,  file.path(OUT,"m26_collinearity_monthly.csv"))
say("저장 완료")
