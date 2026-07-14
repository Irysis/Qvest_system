## run_r37_insider_megatier_power.R — WT-D20260715_006 / FQ-051 / R37
## insider mega-tier(TOP30) SAFE thinness 진단 — power(검정력) vs genuine mega signal-death 판별.
##   R36 확립: net-buy SAFE 신호는 mid-cap 지배(mid t 5.17~6.13), TOP30 4형태 전부 t 0.93~1.68<2.
##   F2 완화로 TOP30 표본 744→2341(3.1x)에도 미달. ★물음: 표본 부족(power)인가 진짜 mega
##   signal-death(cap-tier localization)인가.
##
## 사전등록 진단 3 (판별 목적 · 자본 재도전 아님 · monitoring 소비면):
##   P1 power vs death: TOP30 관측 효과크기+월별분산으로 (a) 이질성검정 monthly(gap_MID-gap_TOP30) NW-t
##       (b) MDE(80%검정력 최소검출효과) (c) TOP30 표본이 MID/large 효과크기를 검출할 검정력
##       (d) 관측효과에서 t>2 필요 월수. 효과크기 자체가 mid보다 작으면 death / 동등하나 표본부족이면 power.
##   P2 INS01+INS02 복합 SAFE flag: 강도(INS01)+breadth(INS02) 부분독립성으로 TOP30 t>2 도달 가능한지
##       (union/inter/additive-z 3형태) + 부분독립성 실측(corr).
##   P3 pooled cross-form 순열검정: 4형태 TOP30 flag 을 pooled(union) → 월내 순열 null 대비 최대검정력 단일검정.
##
## §7b: base = R36 _r36_objects.rds 의 uni (production clean T-1 파생, production_parity_verified 3.058,
##   PIT C5 검증 완료, size-tier/megatier/INS 부착). 저장 268m same-month vintage 미사용. DART API X.
## PIT: R36 uni 그대로 상속 (clean T-1 홀딩월 + insider signal m→hold m+1, C5 + lag1 통과).
## 규율: 단일스레드 · arrow io(2). book_state/05_Production/outputs/ramp 무변경(stage_artifacts만).
## canonical 진단만 · cov/weights 미산출(역할경계) · 자본 주장 금지(monitoring/진단).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2L),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
set.seed(20260715L)

OUT <- "stage_artifacts/WT_D20260715_006"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
logf <- file.path(OUT, "_r37_run_log.txt"); if(file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc<-file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc)}, silent=TRUE); cat(paste0(...),"\n") }
wf <- function(...) w(sprintf(...))
ymshift <- function(ymv,k){y<-ymv%/%100L;m<-ymv%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
## NW lag-3 t on a monthly series
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_); m<-lm(x~1)
  as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
## NW lag-3 mean + SE + t on a monthly series (SE = mean/t)
nw_fit <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(list(mean=NA,se=NA,t=NA,n=length(x)))
  m<-lm(x~1); ct<-coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))
  list(mean=as.numeric(ct[1,1]), se=as.numeric(ct[1,2]), t=as.numeric(ct[1,3]), n=length(x)) }
## two-sided power at 5% given effect mu and se: ncp = mu/se
pwr2 <- function(mu, se, alpha=0.05){ if(!is.finite(mu)||!is.finite(se)||se<=0) return(NA_real_)
  zc<-qnorm(1-alpha/2); ncp<-mu/se; pnorm(ncp-zc)+pnorm(-ncp-zc) }

w("=== R37 insider mega-tier(TOP30) SAFE thinness — power vs signal-death 판별 — WT-D20260715_006 / FQ-051 ===")

## ── 1. R36 uni 상속 (PIT 검증 완료 base) ────────────────────────────────────────
RDS <- "stage_artifacts/WT_D20260715_005/_r36_objects.rds"
stopifnot(file.exists(RDS))
o36 <- readRDS(RDS); uni <- copy(o36$uni)
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"
PIN_MTIME <- as.character(file.info(RAW_P)$mtime)
BASE_PARITY <- o36$out$base_parity$clean_parity_port_t
wf("[base] R36 uni 상속: rows=%d months=%d | parity_PORT_t=%.3f | pin=%s (mtime=%s)",
   nrow(uni), uniqueN(uni$hold_ym), BASE_PARITY, RAW_P, PIN_MTIME)
wf("[base] megatier: TOP30=%d REST=%d | TOP30 INS01 non-NA=%d INS02 non-NA=%d",
   uni[megatier=="TOP30",.N], uni[megatier=="REST",.N],
   uni[megatier=="TOP30"&!is.na(INS01_OffNetBuyIntensity3m),.N], uni[megatier=="TOP30"&!is.na(INS02_OffBuyBreadth6m),.N])

## era 라벨 (challenge #2: mega 표본 시대편중)
uni[, era := fifelse(hold_ym<201500L,"2005-2014", fifelse(hold_ym<202000L,"2015-2019","2020-2026"))]

## ── helper: 특정 tier 내 월별 gap 시계열 (flag vs nonflag) ───────────────────────
##   반환: gap 월별 series + nw_fit + within-month flag/nonflag 표본 요약
tier_gap_series <- function(DT, flagcol, tierval, tiercol="megatier"){
  d <- DT[get(tiercol)==tierval]; d[, f := as.integer(get(flagcol))]; d[is.na(f), f:=0L]
  g <- d[, .(m_f=mean(Ret_1m[f==1L],na.rm=TRUE), m_n=mean(Ret_1m[f==0L],na.rm=TRUE),
             nf=sum(f==1L), nn=sum(f==0L)), by=hold_ym][nf>0 & nn>0]
  gap <- g$m_f - g$m_n
  fit <- nw_fit(gap)
  list(gap=gap, months=g$hold_ym, fit=fit, n_flag=d[f==1L,.N], avg_flag_mo=mean(g$nf), n_months=nrow(g))
}

## ═══════════════════════════════════════════════════════════════════════════════
## P1 — POWER vs DEATH 판별
## ═══════════════════════════════════════════════════════════════════════════════
w("\n────────── P1: power vs signal-death 판별 ──────────")
## 형태별로 TOP30/mid/large-tercile 효과크기·검정력 분해.
##   대표 형태 = F2_relax (표본 최대: TOP30 flag 2341) + F0_base(R33 baseline) + F3_cut(연속 강도).
FORMS_P1 <- c("F2_relax","F0_base","F3_cut")
P1 <- list()
for(fc in FORMS_P1){
  ## TOP30
  gt <- tier_gap_series(uni, fc, "TOP30", "megatier")
  ## mid tercile (효과크기 벤치 — SAFE 신호 중심)
  gm <- tier_gap_series(uni, fc, "mid", "sz_tercile")
  ## large tercile (상위 ~85종 — R33 인용 tier)
  gl <- tier_gap_series(uni, fc, "large", "sz_tercile")
  ## 검정력: TOP30 표본(se) 에 mid/large 효과크기(mean)를 대입
  se_top <- gt$fit$se; mu_top <- gt$fit$mean
  pow_mid   <- pwr2(gm$fit$mean, se_top)   # TOP30 표본이 mid 효과를 검출할 검정력
  pow_large <- pwr2(gl$fit$mean, se_top)   # TOP30 표본이 large-tercile 효과를 검출할 검정력
  pow_own   <- pwr2(mu_top, se_top)        # TOP30 관측 효과의 achieved power
  ## MDE (80% power, 5% two-sided): mu 가 ncp = z_{.975}+z_{.80}=2.802 일 때
  mde_mo <- 2.802 * se_top; mde_ann <- mde_mo*12
  ## t>2 필요 월수 (관측 TOP30 효과 유지 가정): t ∝ sqrt(n), n_need = n*(2/t_obs)^2
  n_need_t2 <- if(is.finite(gt$fit$t)&&gt$fit$t!=0) gt$fit$n*(2/gt$fit$t)^2 else NA_real_
  ## 이질성 검정: 공통 월에서 (gap_mid - gap_top30) NW-t. 양수 유의 → TOP30 효과 진짜 작음(death)
  dm <- merge(data.table(hold_ym=gm$months, g_mid=gm$gap),
              data.table(hold_ym=gt$months, g_top=gt$gap), by="hold_ym")
  het_mid <- nw_fit(dm$g_mid - dm$g_top)
  dl <- merge(data.table(hold_ym=gl$months, g_lar=gl$gap),
              data.table(hold_ym=gt$months, g_top=gt$gap), by="hold_ym")
  het_large <- nw_fit(dl$g_lar - dl$g_top)
  P1[[fc]] <- list(
    top30 = list(gap_ann=mu_top*12, gap_t=gt$fit$t, se_mo=se_top, n_months=gt$fit$n, n_flag=gt$n_flag, avg_flag_mo=gt$avg_flag_mo),
    mid   = list(gap_ann=gm$fit$mean*12, gap_t=gm$fit$t, n_flag=gm$n_flag),
    large = list(gap_ann=gl$fit$mean*12, gap_t=gl$fit$t, n_flag=gl$n_flag),
    power = list(pow_detect_mid=pow_mid, pow_detect_large=pow_large, pow_achieved_own=pow_own,
                 mde_ann=mde_ann, n_need_t2=n_need_t2),
    het   = list(mid_minus_top_ann=het_mid$mean*12, mid_minus_top_t=het_mid$t,
                 large_minus_top_ann=het_large$mean*12, large_minus_top_t=het_large$t, common_months=nrow(dm)),
    gap_series_top=gt$gap)
  wf("\n[%s] TOP30 gap_ann=%+.4f t=%+.2f (se_mo=%.5f n_mo=%d flag=%d) | mid gap_ann=%+.4f t=%+.2f | large gap_ann=%+.4f t=%+.2f",
     fc, mu_top*12, gt$fit$t, se_top, gt$fit$n, gt$n_flag, gm$fit$mean*12, gm$fit$t, gl$fit$mean*12, gl$fit$t)
  wf("   power: TOP30-표본이 mid효과 검출 P=%.3f · large효과 검출 P=%.3f · own achieved P=%.3f | MDE(80%%)=%+.4f/yr | t>2 필요월수=%.0f (실제 %d)",
     pow_mid, pow_large, pow_own, mde_ann, n_need_t2, gt$fit$n)
  wf("   이질성: (mid-TOP30) gap_ann=%+.4f NW-t=%+.2f · (large-TOP30) gap_ann=%+.4f NW-t=%+.2f (공통월=%d)",
     het_mid$mean*12, het_mid$t, het_large$mean*12, het_large$t, nrow(dm))
}

## era별 TOP30 flag 분포 (challenge #2: 시대편중)
era_dist <- uni[megatier=="TOP30", .(
  n_names=.N,
  F2_flag=sum(F2_relax==1L,na.rm=TRUE),
  F0_flag=sum(F0_base==1L,na.rm=TRUE),
  F3_flag=sum(F3_cut==1L,na.rm=TRUE)), by=era][order(era)]
w("\n[era] TOP30 flag 시대 분포 (challenge #2):")
for(i in seq_len(nrow(era_dist))){ r<-era_dist[i]
  wf("   %-10s names=%d F2_flag=%d F0_flag=%d F3_flag=%d", r$era, r$n_names, r$F2_flag, r$F0_flag, r$F3_flag) }
## era별 TOP30 F2 gap (편중 검정)
era_gap <- uni[megatier=="TOP30", {
  d<-copy(.SD); d[,f:=as.integer(F2_relax)]; d[is.na(f),f:=0L]
  g<-d[,.(gp=mean(Ret_1m[f==1L],na.rm=TRUE)-mean(Ret_1m[f==0L],na.rm=TRUE), nf=sum(f==1L)),by=hold_ym][nf>0]
  .(gap_ann=mean(g$gp,na.rm=TRUE)*12, gap_t=nwt(g$gp), months=nrow(g))
}, by=era][order(era)]
for(i in seq_len(nrow(era_gap))){ r<-era_gap[i]; wf("   [era-gap] %-10s F2 TOP30 gap_ann=%+.4f t=%+.2f months=%d", r$era, r$gap_ann, r$gap_t, r$months) }

## ── bootstrap CI on TOP30 F2 효과크기 (challenge #1: 효과크기 추정 불확실) ────────
gt_f2 <- P1$F2_relax$gap_series_top
B <- 2000L; bs <- numeric(B)
for(b in seq_len(B)){ idx<-sample.int(length(gt_f2), replace=TRUE); bs[b]<-mean(gt_f2[idx],na.rm=TRUE)*12 }
ci_top <- quantile(bs, c(0.025,0.5,0.975), na.rm=TRUE)
wf("\n[bootstrap] TOP30 F2 효과크기 95%% CI = [%+.4f, %+.4f]/yr (median %+.4f, B=%d) — MID 효과 0.191/yr 포함 여부: %s",
   ci_top[1], ci_top[3], ci_top[2], B, ifelse(ci_top[3]>=P1$F2_relax$mid$gap_ann,"CI 상단이 MID까지 도달","MID 효과 CI 밖(=효과 진짜 작음)"))

## ═══════════════════════════════════════════════════════════════════════════════
## P2 — INS01+INS02 복합 SAFE flag (TOP30 t>2 도달 가능한가)
## ═══════════════════════════════════════════════════════════════════════════════
w("\n────────── P2: INS01+INS02 복합 SAFE flag ──────────")
## 부분독립성 실측: TOP30 및 전체에서 corr(INS01_z, INS02_z)
both <- uni[!is.na(INS01_OffNetBuyIntensity3m) & !is.na(INS02_OffBuyBreadth6m)]
cor_all  <- cor(both$INS01_OffNetBuyIntensity3m, both$INS02_OffBuyBreadth6m, use="complete.obs")
cor_top  <- both[megatier=="TOP30", cor(INS01_OffNetBuyIntensity3m, INS02_OffBuyBreadth6m)]
wf("[indep] corr(INS01,INS02): 전체=%.3f (n=%d) · TOP30=%.3f (n=%d) — 부분독립성 %s",
   cor_all, nrow(both), cor_top, both[megatier=="TOP30",.N], ifelse(abs(cor_all)<0.6,"있음(복합 잠재효익)","약함(중복)"))

## 복합 3형태
uni[, C_union := as.integer((!is.na(INS01_OffNetBuyIntensity3m)&INS01_OffNetBuyIntensity3m>=0.5) |
                            (!is.na(INS02_OffBuyBreadth6m)&INS02_OffBuyBreadth6m>=0.5))]         # OR
uni[, C_inter := as.integer((!is.na(INS01_OffNetBuyIntensity3m)&INS01_OffNetBuyIntensity3m>=0.5) &
                            (!is.na(INS02_OffBuyBreadth6m)&INS02_OffBuyBreadth6m>=0.5))]         # AND
uni[, ins_addz := rowMeans(cbind(INS01_OffNetBuyIntensity3m, INS02_OffBuyBreadth6m), na.rm=TRUE)]
uni[is.nan(ins_addz), ins_addz := NA_real_]
uni[, C_addz := as.integer(!is.na(ins_addz) & ins_addz>=0.5)]                                     # additive-z >= 0.5

P2 <- list()
for(cc in c("C_union","C_inter","C_addz")){
  gt <- tier_gap_series(uni, cc, "TOP30", "megatier")
  gm <- tier_gap_series(uni, cc, "mid", "sz_tercile")
  ## universe-wide SAFE (참고)
  d <- copy(uni); d[,f:=as.integer(get(cc))]; d[is.na(f),f:=0L]
  guni <- d[, .(gp=mean(Ret_1m[f==1L],na.rm=TRUE)-mean(Ret_1m[f==0L],na.rm=TRUE), nf=sum(f==1L),nn=sum(f==0L)),by=hold_ym][nf>0&nn>0]
  uni_t <- nwt(guni$gp); uni_ann <- mean(guni$gp,na.rm=TRUE)*12
  P2[[cc]] <- list(top30=list(gap_ann=gt$fit$mean*12, gap_t=gt$fit$t, n_flag=gt$n_flag, n_months=gt$fit$n, avg_flag_mo=gt$avg_flag_mo),
                   mid=list(gap_ann=gm$fit$mean*12, gap_t=gm$fit$t, n_flag=gm$n_flag),
                   uni=list(gap_ann=uni_ann, gap_t=uni_t, n_flag=d[f==1L,.N]))
  wf("[%s] uni gap_ann=%+.4f t=%+.2f (flag=%d) | TOP30 gap_ann=%+.4f t=%+.2f (flag=%d mo=%d) | mid gap_ann=%+.4f t=%+.2f",
     cc, uni_ann, uni_t, d[f==1L,.N], gt$fit$mean*12, gt$fit$t, gt$n_flag, gt$fit$n, gm$fit$mean*12, gm$fit$t)
}

## ═══════════════════════════════════════════════════════════════════════════════
## P3 — pooled cross-form TOP30 순열검정 (최대검정력 단일검정)
## ═══════════════════════════════════════════════════════════════════════════════
w("\n────────── P3: pooled cross-form TOP30 순열검정 ──────────")
## pooled flag = F0 ∪ F2 ∪ F3cut (F1 KILL 제외, robustness 로 별도) — 최대 표본으로 "TOP30 에 within-month SAFE 신호가 있는가"
uni[, P_pool := as.integer((F0_base==1L)|(F2_relax==1L)|(F3_cut==1L))]; uni[is.na(P_pool),P_pool:=0L]
gt_pool <- tier_gap_series(uni, "P_pool", "TOP30", "megatier")
wf("[pool] TOP30 pooled(F0∪F2∪F3) gap_ann=%+.4f NW-t=%+.2f (flag=%d months=%d avg/mo=%.1f)",
   gt_pool$fit$mean*12, gt_pool$fit$t, gt_pool$n_flag, gt_pool$fit$n, gt_pool$avg_flag_mo)
## 월내 순열: TOP30 내에서 flag 라벨 셔플(월별 count 보존) → pooled gap ann 귀무분포
perm_top30 <- function(flagcol, obs_gap_ann, nperm=2000L){
  d <- uni[megatier=="TOP30"]; d[,f:=as.integer(get(flagcol))]; d[is.na(f),f:=0L]
  mo <- d[, .(nf=sum(f), n=.N), by=hold_ym][nf>0 & nf<n]
  dm <- d[hold_ym %in% mo$hold_ym]
  ret_by <- split(dm$Ret_1m, dm$hold_ym); nf_by <- setNames(mo$nf, as.character(mo$hold_ym))
  perm_ann <- numeric(nperm)
  for(p in seq_len(nperm)){
    gaps <- vapply(names(ret_by), function(k){ r<-ret_by[[k]]; n<-length(r); kf<-nf_by[[k]]
      idx<-sample.int(n,kf); mean(r[idx],na.rm=TRUE)-mean(r[-idx],na.rm=TRUE) }, numeric(1))
    perm_ann[p] <- mean(gaps,na.rm=TRUE)*12
  }
  list(p_value=mean(perm_ann>=obs_gap_ann), perm_mean=mean(perm_ann,na.rm=TRUE), perm_sd=sd(perm_ann,na.rm=TRUE),
       nperm=nperm, perm_ann=perm_ann, q=quantile(perm_ann,c(0.95,0.99),na.rm=TRUE))
}
obs_pool_ann <- gt_pool$fit$mean*12
PB_pool <- perm_top30("P_pool", obs_pool_ann, 2000L)
wf("[pool-perm] obs gap_ann=%+.4f · perm null mean=%+.4f sd=%.4f q95=%+.4f q99=%+.4f · p_value=%.4f (nperm=%d)",
   obs_pool_ann, PB_pool$perm_mean, PB_pool$perm_sd, PB_pool$q[1], PB_pool$q[2], PB_pool$p_value, PB_pool$nperm)
## robustness: F2 단독 TOP30 순열 (비교)
gt_f2t <- tier_gap_series(uni, "F2_relax", "TOP30","megatier")
PB_f2  <- perm_top30("F2_relax", gt_f2t$fit$mean*12, 2000L)
wf("[pool-perm][robust] F2 단독 TOP30 obs=%+.4f p_value=%.4f", gt_f2t$fit$mean*12, PB_f2$p_value)

## ═══════════════════════════════════════════════════════════════════════════════
## 판정 로직 (구조화)
## ═══════════════════════════════════════════════════════════════════════════════
w("\n────────── 판정 로직 ──────────")
## power vs death: 대표형태 F2 기준
pw_mid_f2 <- P1$F2_relax$power$pow_detect_mid
het_t_f2  <- P1$F2_relax$het$mid_minus_top_t
verdict_power_vs_death <- if(is.finite(pw_mid_f2) && pw_mid_f2>=0.8 && is.finite(het_t_f2) && het_t_f2>=2){
  "signal_attenuation_dominant"   # TOP30 표본이 mid효과 검출력 충분(P>=0.8)한데도 이질성 유의 → 효과 진짜 작음(death 우세)
} else if(is.finite(pw_mid_f2) && pw_mid_f2<0.5){
  "power_limited"                 # mid효과조차 검출 못함 → underpowered
} else { "mixed" }
wf("[verdict] power_vs_death=%s (P(mid효과 검출|TOP30표본)=%.3f · 이질성 mid-TOP30 NW-t=%+.2f)",
   verdict_power_vs_death, pw_mid_f2, het_t_f2)
## 복합이 TOP30 를 t>2 로 올렸나
best_comp_t <- max(sapply(P2, function(x) x$top30$gap_t), na.rm=TRUE)
wf("[verdict] 복합 최고 TOP30 t=%+.2f (%s>2 도달)", best_comp_t, ifelse(best_comp_t>=2,"","미"))
wf("[verdict] pooled 순열 p=%.4f (%sTOP30 within-month SAFE 신호 유의)", PB_pool$p_value, ifelse(PB_pool$p_value<0.05,"","不"))

## ── 저장 ────────────────────────────────────────────────────────────────────────
PREREG <- list(mode="RAMP-adjacent monitoring 진단 (mega-tier thinness power vs death)", round="R37", fq="FQ-051", wt="WT-D20260715_006",
  parent="R36 next_probe P1/P2 (TOP30 thinness 진단 + INS 복합)",
  base_source="R36 _r36_objects.rds uni (production clean T-1 파생, production_parity_verified, PIT C5 검증 상속)",
  diagnostics=list(
    P1="power vs death: 이질성 monthly(gap_MID-gap_TOP30) NW-t + MDE + TOP30표본 검정력(mid/large 효과) + t>2 필요월수 + bootstrap CI + era 편중",
    P2="INS01+INS02 복합 SAFE (union/inter/additive-z) TOP30 t>2 도달 + 부분독립성 corr",
    P3="pooled cross-form(F0∪F2∪F3) TOP30 월내 순열검정 (최대검정력 단일검정)"),
  decision_axis="TOP30 SAFE thinness 원인 = power(표본부족) vs genuine signal-death(cap-tier localization) 판별. 자본 아님(monitoring 진단).",
  honest_prior="cap-tier localization prior 상 death 우세 예상. 복합이 TOP30 를 t>2 로 못 올릴 가능성 高.",
  selection_type="chain (가설주도 고정 config · sweep 아님)", n_trials=1L,
  vintage_pin=RAW_P, pin_mtime=PIN_MTIME, as_of="2026-07-15")
PREREG$config_hash <- substr(digest::digest(PREREG, algo="sha256"),1,16)
write_json(PREREG, file.path(OUT,"prereg_r37.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("\n[prereg] config_hash=%s selection_type=chain n_trials=1", PREREG$config_hash)

out <- list(prereg=PREREG, vintage_pin=RAW_P, pin_mtime=PIN_MTIME,
  base_parity=list(clean_parity_port_t=BASE_PARITY, note="§7b R36 uni 상속 production_parity_verified"),
  universe_coverage=list(rows=nrow(uni), months=uniqueN(uni$hold_ym),
    top30_names=uni[megatier=="TOP30",.N], top30_ins01=uni[megatier=="TOP30"&!is.na(INS01_OffNetBuyIntensity3m),.N],
    top30_ins02=uni[megatier=="TOP30"&!is.na(INS02_OffBuyBreadth6m),.N]),
  P1_power_vs_death=list(
    forms=lapply(P1, function(x) list(top30=x$top30, mid=x$mid, large=x$large, power=x$power, het=x$het)),
    bootstrap_top30_f2_ci=list(lo=as.numeric(ci_top[1]), median=as.numeric(ci_top[2]), hi=as.numeric(ci_top[3]), B=B),
    era_dist=era_dist, era_gap=era_gap),
  P2_composite=list(cor_ins01_ins02_all=cor_all, cor_ins01_ins02_top30=cor_top, forms=P2),
  P3_pooled_perm=list(top30_pooled=list(gap_ann=obs_pool_ann, gap_t=gt_pool$fit$t, n_flag=gt_pool$n_flag, n_months=gt_pool$fit$n),
    perm=list(p_value=PB_pool$p_value, perm_mean=PB_pool$perm_mean, perm_sd=PB_pool$perm_sd, q95=as.numeric(PB_pool$q[1]), q99=as.numeric(PB_pool$q[2]), nperm=PB_pool$nperm),
    robust_f2=list(gap_ann=gt_f2t$fit$mean*12, p_value=PB_f2$p_value)),
  verdict=list(power_vs_death=verdict_power_vs_death, pow_detect_mid_f2=pw_mid_f2, het_mid_top_t_f2=het_t_f2,
    best_composite_top30_t=best_comp_t, pooled_perm_p=PB_pool$p_value),
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))
write_json(out, file.path(OUT,"r37_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)
saveRDS(list(uni=uni, P1=P1, P2=P2, PB_pool=PB_pool, gt_pool=gt_pool, out=out), file.path(OUT,"_r37_objects.rds"))

wf("\nR37_DONE | power_vs_death=%s | P(mid|TOP30표본)=%.3f het_t=%+.2f | best_comp_TOP30_t=%+.2f | pool_perm_p=%.4f",
   verdict_power_vs_death, pw_mid_f2, het_t_f2, best_comp_t, PB_pool$p_value)
cat("[SAVED]", file.path(OUT,"r37_results.json"), "\n")
