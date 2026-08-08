# =============================================================================
# r9_asym_ax001.R — 필터의 위험-축 비대칭(상승/하락 포착) + AX-001 v2 조건부 축
#   ★alpha 판정 아님. 평균(alpha)은 alpha-research 가 INCONCLUSIVE_UNDERPOWERED 로
#     확정했고 본 스크립트는 2차 적률(변동·하방·β)만 다룬다.
#   국면 '분할 설계' 금지 준수: 주판정은 연속 조건화(상호작용) · 분할표는 descriptive.
#   metric_type = risk_estimate / canonical_screen
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260808_001/risk"
say <- function(fmt,...) cat(sprintf(paste0("[r9] ",fmt,"\n"),...))
R7 <- readRDS(file.path(OUT,"r7_risk.rds")); PB <- as.data.table(R7$PB)
E  <- as.data.table(read_parquet(file.path(OUT,"exposure_panel.parquet"))); E[,Date:=as.Date(Date)]
AS <- as.data.table(read_parquet("stage_artifacts/WT_D20260808_001/alpha_scores.parquet")); AS[,Date:=as.Date(Date)]
say("입력 PB %d월 (%s~%s) 관측단위 월간 | 컬럼 %s", nrow(PB), as.character(min(PB$date)),
    as.character(max(PB$date)), paste(names(PB), collapse=","))

nwt <- function(x, lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<10) return(NA_real_)
  m<-mean(x); e<-x-m; s<-sum(e^2)/n
  for(l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n
  if(s<=0) return(NA_real_); m/sqrt(s/n) }

# ── 1. 필터의 위험-축 효과: 연속 조건화 (분할 아님) ─────────────────────────
PB[, d := ret_filt - ret_base]        # 필터 arm − base arm, 월별 짝지음
say("[필터-base 월별 차이] 평균 연율 %+.4f | t_NW %.2f | 변동(연율) %.4f",
    mean(PB$d)*12, nwt(PB$d), stats::sd(PB$d)*sqrt(12))
fit <- lm(d ~ bm, data=PB)
cf <- summary(fit)$coefficients
say("  연속 조건화 d ~ 벤치수익:  절편 %+.5f (t %.2f)  기울기 %+.4f (t %.2f)",
    cf[1,1], cf[1,3], cf[2,1], cf[2,3])
say("  ⇒ 기울기 %+.4f = 필터가 벤치 1%% 하락 시 base 대비 %+.4f%%p — 부호가 음이면 하방 보호",
    cf[2,1], -cf[2,1])
# 2차 적률의 짝지음 검정: |active| 축소 여부
PB[, absA_base := abs(act_base)][, absA_filt := abs(act_filt)]
say("  |active| 짝지음 차 평균 %+.5f  t_NW %.2f (음수 = 필터가 액티브 변동 축소)",
    mean(PB$absA_filt-PB$absA_base), nwt(PB$absA_filt-PB$absA_base))
# 하락월 부분표본 (descriptive — 검정력 라벨 의무)
dn <- PB[bm < 0]; up <- PB[bm >= 0]
say("[descriptive · 분할 판정 아님] 하락월 n=%d: base %+.4f filt %+.4f 차 %+.4f (t_NW %.2f)",
    nrow(dn), mean(dn$ret_base), mean(dn$ret_filt), mean(dn$d), nwt(dn$d))
say("                              상승월 n=%d: base %+.4f filt %+.4f 차 %+.4f (t_NW %.2f)",
    nrow(up), mean(up$ret_base), mean(up$ret_filt), mean(up$d), nwt(up$d))
say("  ⚠ 하락월 %d개 = 원표본 %.0f%% — 부분표본 검정력은 전표본보다 낮다. 주판정은 위 연속 조건화.",
    nrow(dn), 100*nrow(dn)/nrow(PB))

# ── 2. 하방 위험 지표 (계약 함수) ───────────────────────────────────────────
mk <- function(v) xts(v, order.by=PB$date)
mdd <- function(v) as.numeric(maxDrawdown(mk(v)))
say("[하방 위험] MDD  base %.4f | filt %.4f | 벤치 %.4f",
    mdd(PB$ret_base), mdd(PB$ret_filt), mdd(PB$bm))
say("           하방편차(연율) base %.4f | filt %.4f | 벤치 %.4f",
    as.numeric(DownsideDeviation(mk(PB$ret_base)))*sqrt(12),
    as.numeric(DownsideDeviation(mk(PB$ret_filt)))*sqrt(12),
    as.numeric(DownsideDeviation(mk(PB$bm)))*sqrt(12))
say("           변동(연율)   base %.4f | filt %.4f | 벤치 %.4f",
    stats::sd(PB$ret_base)*sqrt(12), stats::sd(PB$ret_filt)*sqrt(12), stats::sd(PB$bm)*sqrt(12))

# ── 3. AX-001 v2 조건부 축 (D03 = defense family 접촉) ──────────────────────
# ① crisis_alpha ② Core(=base arm) 대비 MDD ③ bad/normal IC 비 — ③은 연속 조건화 병기
say("[AX-001 v2 조건부 축]")
say("  ① crisis_alpha(스트레스 구간 active, r7 표): GFC base %+.4f filt %+.4f | China base %+.4f filt %+.4f | Rate22 base %+.4f filt %+.4f",
    R7$stress[period=="GFC"]$act_base, R7$stress[period=="GFC"]$act_filt,
    R7$stress[period=="China_Shock"]$act_base, R7$stress[period=="China_Shock"]$act_filt,
    R7$stress[period=="Rate_Hike_2022"]$act_base, R7$stress[period=="Rate_Hike_2022"]$act_filt)
say("  ② Core(base arm) 대비 MDD 완화 = %+.4f%%p (filt %.4f − base %.4f)",
    100*(mdd(PB$ret_filt)-mdd(PB$ret_base)), mdd(PB$ret_filt), mdd(PB$ret_base))
IC <- merge(E[, .(Date,Ticker,Ret_1m)], AS[, .(Date,Ticker,D03_EWMA,Q01_EB)], by=c("Date","Ticker"))
icm <- IC[is.finite(Ret_1m), .(ic_d03 = if(sum(is.finite(D03_EWMA))>=30) cor(D03_EWMA,Ret_1m,method="spearman",use="complete.obs") else NA_real_,
                               ic_q01 = if(sum(is.finite(Q01_EB))>=30) cor(Q01_EB,Ret_1m,method="spearman",use="complete.obs") else NA_real_), by=Date]
icm <- merge(icm, PB[, .(Date=date, bm)], by="Date")
f3 <- lm(ic_d03 ~ bm, data=icm); f4 <- lm(ic_q01 ~ bm, data=icm)
say("  ③ 연속 조건화 IC ~ 벤치수익: D03 기울기 %+.4f (t %.2f) | Q01 기울기 %+.4f (t %.2f)",
    coef(f3)[2], summary(f3)$coefficients[2,3], coef(f4)[2], summary(f4)$coefficients[2,3])
say("     descriptive 분할: D03 IC 하락월 %+.4f / 상승월 %+.4f (비 %.2f) | Q01 %+.4f / %+.4f (비 %.2f)",
    mean(icm[bm<0]$ic_d03,na.rm=TRUE), mean(icm[bm>=0]$ic_d03,na.rm=TRUE),
    mean(icm[bm<0]$ic_d03,na.rm=TRUE)/mean(icm[bm>=0]$ic_d03,na.rm=TRUE),
    mean(icm[bm<0]$ic_q01,na.rm=TRUE), mean(icm[bm>=0]$ic_q01,na.rm=TRUE),
    mean(icm[bm<0]$ic_q01,na.rm=TRUE)/mean(icm[bm>=0]$ic_q01,na.rm=TRUE))
say("     ⚠ ③ 분할값은 descriptive. AX-001 은 '방어형 standalone 자본자격' 평가 규칙이며 본 라운드 대상(선별필터의 위험축 기여)과 범위가 다르다 — 조건부 축은 기록하되 자격 판정에 쓰지 않는다.")

# ── 4. 예측 TE vs 실현 TE (모델 검증) ───────────────────────────────────────
TB <- as.data.table(read_parquet(file.path(OUT,"te_budget_panel.parquet")))
pt <- median(TB[arm=="score"]$te_ann); ptf <- median(TB[arm=="score_q01filtered"]$te_ann)
sub <- PB[date >= as.Date("2009-01-01")]
rt <- stats::sd(sub$act_base)*sqrt(12); rtf <- stats::sd(sub$act_filt)*sqrt(12)
say("[TE 검증 2009+ n=%d] base 예측 %.4f / 실현 %.4f (비 %.2f) | filt 예측 %.4f / 실현 %.4f (비 %.2f)",
    nrow(sub), pt, rt, pt/rt, ptf, rtf, ptf/rtf)

saveRDS(list(fit=cf, dn=nrow(dn), up=nrow(up), d_mean_ann=mean(PB$d)*12, d_t=nwt(PB$d),
             absA_t=nwt(PB$absA_filt-PB$absA_base),
             mdd=c(base=mdd(PB$ret_base), filt=mdd(PB$ret_filt), bm=mdd(PB$bm)),
             dd=c(base=as.numeric(DownsideDeviation(mk(PB$ret_base)))*sqrt(12),
                  filt=as.numeric(DownsideDeviation(mk(PB$ret_filt)))*sqrt(12)),
             vol=c(base=stats::sd(PB$ret_base)*sqrt(12), filt=stats::sd(PB$ret_filt)*sqrt(12),
                   bm=stats::sd(PB$bm)*sqrt(12)),
             ic_slope=c(d03=coef(f3)[2], q01=coef(f4)[2]),
             te_pred=c(base=pt, filt=ptf), te_real=c(base=rt, filt=rtf)),
        file.path(OUT,"r9_asym.rds"))
say("저장 완료")
