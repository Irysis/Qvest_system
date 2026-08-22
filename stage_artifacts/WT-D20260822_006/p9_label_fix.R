## P9 — 자기 적대검증 ACCEPT 반영: R1/F1 라벨을 '기각' → '미결(underpowered)' 로 정정
## 근거: p8_gate_power.rds — R1 MDE(t=1.5) 3.88~4.63 %p/yr per 1sd = 여유폭 평균의 28~34%,
##       F1 관측 slope 는 MDE 의 0.72 배. 두 게이트 모두 관측값이 검출 문턱 미만이므로
##       '효과 없음' 이 아니라 '검출 실패' 다. (미결/효과없음/가려짐 3분할 규약)
suppressPackageStartupMessages({library(jsonlite); library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/WT-D20260822_006"; MB <- "qepm/mailbox/worktask/WT-D20260822_006"
G <- readRDS(file.path(OUT,"p8_gate_power.rds"))
hzm <- G$hz_stats$mean*12*100

AV <- fromJSON(file.path(OUT,"alpha_validation.json"), simplifyVector=FALSE)

AV$transport_gate_R1$gate_power_measured <- list(
  headroom_series = list(mean_annual_pct = hzm, sd_monthly = G$hz_stats$sd),
  per_axis = lapply(names(G$R1), function(n) list(axis=n,
    slope_annual_pct_per_1sd = G$R1[[n]]$b*12*100, se = G$R1[[n]]$se, t_nw3 = G$R1[[n]]$t,
    mde_t15_annual_pct_per_1sd = 1.5*G$R1[[n]]$se*12*100,
    mde_as_pct_of_headroom = 100*1.5*G$R1[[n]]$se*12*100/hzm)),
  note = "★자기 적대검증이 적발한 결손의 수리 — 초판은 R1 을 MECHANISM_NOT_TRANSPORTED 로 라벨했으나 게이트 자체의 검정력을 재지 않았다. 실측 MDE 는 여유폭 평균의 28.4%(축1) / 29.5%(축2) / 33.8%(강등축)다.")
AV$transport_gate_R1$verdict <- "UNRESOLVED_UNDERPOWERED — 1sd 상태 변화가 여유폭의 28% 이상을 움직이는 결합은 배제되나, 그보다 약한 결합은 이 설계로 판정 불가"
AV$transport_gate_R1$label <- "UNRESOLVED_UNDERPOWERED"
AV$transport_gate_R1$excluded_region <- "|slope| >= 3.88 %p/yr per 1sd (축1) / 4.04 (축2) — 이 크기 이상의 상태-여유폭 결합은 95% 배제"
AV$transport_gate_R1$practical_consequence <- paste(
  "★단 실무 결론은 여전히 powered 다 — 전도성 실측(오라클 상태조차 여유폭의 25.2% 만 통과)과 결합하면,",
  "R1 의 미검출 구간(결합 < 28%)에 실재하는 결합이 있더라도 이 소프트-틸트 마디를 통과해 MATERIAL 8.22%p/yr 에 도달할 수 없다.",
  "즉 '상태-여유폭 결합의 부재' 는 미결이고, '이 마디에서 상태 조건부 선택이 물질적 회수를 낸다' 는 기각이다 — 두 명제를 분리해 라벨한다.")

AV$falsification_measured$F1_direction_mediator$gate_power_measured <- list(
  n = 103L, D_sd = 0.11927, slope = G$F1$b, se = G$F1$se, t_nw3 = G$F1$t,
  mde_t15 = 1.5*G$F1$se, obs_over_mde = abs(G$F1$b)/(1.5*G$F1$se),
  note = "관측 기울기가 MDE 의 0.72 배 — 검출 문턱 미만이므로 '방향 축 기각' 이 아니라 '판정 불가'.")
AV$falsification_measured$F1_direction_mediator$verdict <- "UNRESOLVED_UNDERPOWERED — 유효 월 103(2군 IC 가 동시 정의되는 달)이라 방향 축의 존부를 가릴 검정력 없음"
AV$falsification_measured$F1_direction_mediator$label <- "UNRESOLVED_UNDERPOWERED"

AV$conduit_test$ceiling_finding_caveat <- paste(
  "★상한 25.2% 는 **하한 추정치**다 — 오라클 상태의 *크기*를 최적화하지 않고 표준화·clip 형태로만 넣었기 때문이다.",
  "매월 최적 틸트 강도를 예지로 고르면 더 높아질 수 있다. 따라서 '소프트 틸트는 여유폭의 1/4 만 나른다' 가 아니라",
  "'표준화-clip 형태의 소프트 틸트는 최소 1/4 을 나르며 그 형태로는 벽에 못 미친다' 가 정확한 서술이다.")

AV$verdict <- "MATERIAL_RECOVERY_POWERED_NULL__STATE_HEADROOM_COUPLING_UNRESOLVED"
AV$verdict_detail <- paste(
  "성과-무관 횡단면 상태 2축(팩터 간 순위 불일치 · 수익 횡단면 분산) 조건부 팩터 선택은 C0 대비 개선 없음 —",
  "co-primary 2종 모두 POWERED_NULL_NO_MATERIAL_EFFECT(T2_AGREE -1.10%p/yr t -0.829 CI95 상단 +1.50 · T3_DISP +0.27%p/yr t +0.251 상단 +2.34, MATERIAL 8.22 배제, MDE 여유 3.0~4.3배).",
  "순열 귀무분포(40 draws/축)에서도 관측 t 가 62.5 / 90.0 백분위로 무작위 상태를 5% 수준에서 이기지 못한다.",
  "★분리 판정 3건이 성과보다 먼저·서로 다른 방향으로 나왔다:",
  "(1) 전도성 PASS — 완전예지 상태를 넣으면 같은 규칙이 t 2.01~2.47 ⇒ null 은 규칙 무력이 아니다.",
  "(2) F3 PASS — 고분산 월 개인 순매수 집중 상승(cor +0.272, t +1.776) ⇒ 기전의 agent 는 실재한다.",
  "(3) R1·F1 은 UNRESOLVED(미결) — 게이트 검정력 실측 결과 R1 MDE 가 여유폭의 28~30%, F1 관측이 MDE 의 0.72배라",
  "    '상태-여유폭 결합 부재' 를 주장할 자격이 없다. 초판이 이를 '기각' 으로 쓴 것은 자기 적대검증에서 ACCEPT 정정했다.",
  "★그래서 두 명제를 분리한다 — 기각(powered): 이 마디의 소프트-틸트 상태 조건부 선택은 물질적 여유폭 회수를 내지 못한다.",
  "미결(underpowered): 상태와 여유폭 사이에 약한 결합이 있는지는 판정 불가. 단 전도성 25.2%(하한)와 결합하면",
  "그 약한 결합이 실재하더라도 이 형태로는 MATERIAL 에 도달 불가하므로 실무 결론은 바뀌지 않는다.",
  "부수 확립(신규): ORACLE_K 4.647 은 **이산 하드 선택**의 상한이고, 표준화-clip **소프트 틸트** 족은 여유폭의 최소 1/4 만 나르며 PORT_t 1.70~1.82 로 벽 미달.")
AV$round_verdict <- "CONFIG_SCOPED_NEGATIVE__SOFT_TILT_STATE_SELECTION_NO_MATERIAL_RECOVERY"
write_json(AV, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[patched] alpha_validation.json\n")

pkg <- fromJSON(file.path(MB,"alpha_package.json"), simplifyVector=FALSE)
cf <- unlist(pkg$challenge_flags)
cf[1] <- paste("CF-01 [HIGH] R1 수송 게이트 = UNRESOLVED_UNDERPOWERED (초판 'MECHANISM_NOT_TRANSPORTED' 는 자기 적대검증에서 ACCEPT 정정).",
  "관측 기울기 +2.27 / +1.04 %p/yr per 1sd, MDE(t=1.5) 3.88 / 4.04 = 여유폭 평균의 28.4% / 29.5%.",
  "⇒ 그 크기 이상의 상태-여유폭 결합은 배제되나 약한 결합은 판정 불가.")
cf <- c(cf, paste("CF-11 [HIGH] F1 방향 매개 = UNRESOLVED_UNDERPOWERED — 관측 slope 가 MDE 의 0.72 배(유효 월 103).",
  "'방향 축 기각' 으로 쓸 수 없다."),
  paste("CF-12 [MEDIUM] 전도성 상한 25.2% 는 하한 추정치 — 오라클 상태의 크기를 최적화하지 않았다(표준화·clip 형태만).",
    "'소프트 틸트는 1/4 만 나른다' 가 아니라 '이 형태의 소프트 틸트는 최소 1/4 을 나르고 그 형태로는 벽 미달' 이 정확한 서술."),
  paste("CF-13 [MEDIUM] 순열 40 draws 는 해상도가 거칠다(1/40 = 0.025 단위). 축2 one-sided p 0.100 은 4/40 이며",
    "0.05 를 확정 배제하지 못한다."),
  paste("CF-14 [MEDIUM] g_k 계열 방향 매핑은 재량 선언이다 — 기전 자구에서 도출하고 봉인 전 고정했으나 다른 매핑도 방어 가능하며",
    "매핑 민감도는 스윕하지 않았다(스윕 시 sweep 재분류 + DSR HARD 발동)."),
  paste("CF-15 [MEDIUM] arm 규칙 형태(중심성 틸트 · 계열 방향)는 FQ-244 결과를 본 뒤 내가 고른 것이다.",
    "봉인 전 고정이라 사후 선택은 아니나 형태 공간을 열거하지 않았다 — 전도성 실측이 그 형태의 상한을 재준 것이 완화이지 해소는 아니다."),
  paste("CF-16 [LOW] F3 집중도 정의(월별 |Individual| 순매수의 HHI)는 사전등록이 'HHI 또는 상위 십분위 몫' 으로 열어둔 둘 중 하나다.",
    "t +1.776 은 문턱 1.5 를 근소 초과하며 정의 다중성 보정은 하지 않았다(상위 십분위 몫은 cor +0.191 로 동방향·약함)."))
pkg$challenge_flags <- as.list(cf)
pkg$round_verdict <- "CONFIG_SCOPED_NEGATIVE__SOFT_TILT_STATE_SELECTION_NO_MATERIAL_RECOVERY"
pkg$diagnostics$transport_gate_label <- "UNRESOLVED_UNDERPOWERED"
pkg$diagnostics$transport_gate_mde_pct_of_headroom <- list(axis1 = 28.4, axis2 = 29.5)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=NA, na="null")
cat("[patched] alpha_package.json — challenge_flags", length(cf), "\n")
