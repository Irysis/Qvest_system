# R15 — Cycle 2 교훈 이행: vol-centric alpha 의 idio-vol tilt 실측 + Forge AX-001 v2 crisis IC 재검 권고
#   본 라운드 패닉 분기 = 126d 실현변동성 신호(factor_specs[[2]]) → 스킬이 지정한 점검 대상.
suppressWarnings(suppressMessages({library(data.table); library(jsonlite); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004"); MB <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
S1<-readRDS(file.path(OUT,"risk_calc_stage1.rds")); S2<-readRDS(file.path(OUT,"risk_calc_stage2.rds"))
EXP<-S1$EXP; HOLDH<-S1$HOLDH; PAN<-S1$PANIC_YM; RVM<-S1$RVM; yms<-S1$yms

## (1) 보유 슬리브의 vol tilt — 홀딩월별 평균 x_vol(횡단면 z) · 패닉 vs 비패닉
TILT <- rbindlist(lapply(sort(unique(HOLDH$hold_ym)), function(hm){
  E <- EXP[hold_ym==hm & Ticker %chin% HOLDH[hold_ym==hm]$Ticker]
  if(nrow(E)<10L) return(NULL)
  data.table(hold_ym=hm, x_vol=mean(E$x_vol), x_size=mean(E$x_size), x_mom=mean(E$x_mom),
             raw_vol=mean(E$vol126_ann, na.rm=TRUE), n=nrow(E)) }))
TILT[, panic := as.integer(hold_ym %in% PAN)]
UNI <- EXP[, .(uni_raw_vol=median(vol126_ann,na.rm=TRUE)), by=hold_ym]
TILT <- merge(TILT, UNI, by="hold_ym")
TILT[, vol_ratio_vs_universe := raw_vol/uni_raw_vol]
agg <- TILT[, .(n_months=.N, x_vol_mean=mean(x_vol), raw_vol=mean(raw_vol),
                uni_vol=mean(uni_raw_vol), ratio=mean(vol_ratio_vs_universe)), by=panic][order(panic)]
cat("[R15] 슬리브 vol tilt (패닉 vs 비패닉):\n"); print(agg)
tt <- t.test(TILT[panic==1]$x_vol, TILT[panic==0]$x_vol)
cat(sprintf("[R15] x_vol tilt 차 %.3f (t %.2f, p %.4f)\n",
            diff(rev(c(mean(TILT[panic==1]$x_vol), mean(TILT[panic==0]$x_vol)))), tt$statistic, tt$p.value))
cur <- EXP[Date==as.Date("2026-08-28") & Ticker %chin% S1$HOLD_CUR]
cat(sprintf("[R15] as-of x_vol tilt %.3f · 원시 vol126 중앙 %.3f vs 유니버스 %.3f (배율 %.2f)\n",
  mean(cur$x_vol), median(cur$vol126_ann), median(EXP[Date==as.Date("2026-08-28")]$vol126_ann),
  median(cur$vol126_ann)/median(EXP[Date==as.Date("2026-08-28")]$vol126_ann)))

## (2) 특이변동성(idio-vol) tilt — 모형 잔차 기준. 신호가 총변동성인데 위험은 특이분산으로 온다.
IDIO <- rbindlist(lapply(sort(unique(HOLDH$hold_ym)), function(hm){
  tk <- HOLDH[hold_ym==hm]$Ticker; pv <- yms[which(yms==hm)-1L]
  if(!length(pv)||is.na(pv)) return(NULL)
  Z <- RVM[ym==pv]; if(nrow(Z)<50L) return(NULL)
  data.table(hold_ym=hm, hold_idio=median(Z[Ticker %chin% tk]$sv_d, na.rm=TRUE),
             uni_idio=median(Z$sv_d, na.rm=TRUE)) }))
IDIO[, ratio := hold_idio/uni_idio][, panic := as.integer(hold_ym %in% PAN)]
ai <- IDIO[, .(n=.N, idio_ratio=mean(ratio,na.rm=TRUE)), by=panic][order(panic)]
cat("[R15] idio-vol tilt (보유/유니버스 특이분산 중앙비):\n"); print(ai)

## (3) crisis 구간 vol tilt (AX-001 v2 crisis IC 재검 근거)
crisis <- list(GFC=c("2007-10","2009-03"), COVID=c("2020-01","2020-06"),
               RateHike=c("2022-01","2022-12"), KR2026H2=c("2026-05","2026-08"))
cr <- rbindlist(lapply(names(crisis), function(nm){ w <- crisis[[nm]]
  Z <- TILT[hold_ym>=w[1] & hold_ym<=w[2]]
  if(nrow(Z)==0) return(NULL)
  data.table(period=nm, n=nrow(Z), x_vol=mean(Z$x_vol), vol_ratio=mean(Z$vol_ratio_vs_universe),
             n_panic=sum(Z$panic)) }))
cat("[R15] crisis 구간 vol tilt:\n"); print(cr)

dtl <- function(D) lapply(seq_len(nrow(D)), function(i) as.list(D[i]))
p <- fromJSON(file.path(MB,"risk_package.json"), simplifyVector=FALSE)
p$risk_summary$vol_centric_alpha_check <- list(
  trigger="risk-style Cycle 2 교훈 — 본 라운드 factor_specs[[2]] 가 126d 실현변동성 신호(vol-centric)이므로 crowding/idio-vol tilt 점검 의무 발동",
  crowding_of_vol_factor=list(factor="LowVol_realized126d", crowding_score=0.2687, hhi_top=0.0625,
    alert="none", reading="4요인 중 최저 crowding. 저변동 축은 이 유니버스에서 붐비지 않는다 — 패닉 분기의 실행가능성은 crowding 쪽에서 막히지 않는다."),
  total_vol_tilt=list(by_regime=dtl(agg), t_stat=unname(tt$statistic), p_value=tt$p.value,
    asof_x_vol=mean(cur$x_vol),
    asof_raw_vol_median=median(cur$vol126_ann),
    asof_universe_vol_median=median(EXP[Date==as.Date("2026-08-28")]$vol126_ann),
    asof_ratio=median(cur$vol126_ann)/median(EXP[Date==as.Date("2026-08-28")]$vol126_ann)),
  idio_vol_tilt=list(by_regime=dtl(ai),
    note="신호는 총변동성(vol126)인데 Sigma 의 특이분산은 잔차 기준이다. 두 tilt 가 갈리면 '저변동 선택'이 실제로는 저-베타 선택이라는 뜻."),
  crisis_periods=dtl(cr),
  forge_recommendation=list(
    id="RISK->FORGE AX-001 v2",
    action="crisis IC 재검 권고",
    reason="vol-centric 신호는 crisis 구간에서 IC 부호가 뒤집히는 계열(Cycle 2 실측 교훈). 본 라운드의 패닉 분기는 26개월(에피소드 4)에서만 발화하므로 전기간 IC 로는 그 구간 거동이 희석된다. forge 는 GFC/COVID/RateHike/2026H2 각 구간에서 vol126 축의 IC 를 **구간별로** 재산출해 부호 안정성을 확인할 것.",
    scope_note="risk 는 권고만 한다 — IC 재산출은 forge/alpha 영역이며 본 에이전트는 alpha 신호를 재해석하지 않는다."))
p$challenge_flags[[length(p$challenge_flags)+1L]] <- list(
  id="RISK-CH7", severity="MEDIUM", to="forge",
  message="vol-centric alpha 점검(risk-style Cycle 2): 패닉 분기가 126d 실현변동성 신호다. crowding 은 최저(0.269)로 무해하나, crisis 구간별 IC 부호 안정성은 미검증이다. AX-001 v2 crisis IC 를 GFC/COVID/RateHike2022/2026H2 구간별로 재산출할 것. 상세 = risk_summary.vol_centric_alpha_check.")
write_json(p, file.path(MB,"risk_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, null="null", na="null")
cat("[R15] risk_package 등재 완료 · challenge_flags:", length(p$challenge_flags), "\n")
saveRDS(list(TILT=TILT, IDIO=IDIO, cr=cr, agg=agg, ai=ai), file.path(OUT,"risk_calc_stage6.rds"))
