source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ099B_20260808_CORRECTED_PANEL_IC_AB_V2",
  verdict_type = "config_scoped_negative",
  layer = "0_데이터",
  mechanism_diagnosis = paste(
    "★v1 무효 → v2 재측정 후 판정. v1 오류: rawdata 를 월간으로 가정했으나 **일간 9,003일**이라 일간 IC·익일수익을 쟀고, 연 4회 이하로 바뀌는 재무신호의 중복관측 위에 NW lag-3 을 얹어 t 가 크게 부풀려졌다(5.38/3.86/5.11 인용 금지). v2 = 계약 함수 build_monthly_forward_returns() 경유(자체합성 금지 정합) + rolling join. 검증: 월별 IC 수준이 상승(Revenue 전기간 raw 0.0118→0.0301)하고 t 는 하락(5.81→2.83) — 중복관측 인플레 제거의 예상 방향과 일치.",
    "**사전등록 판정 = REARRANGEMENT_ONLY**. 주창(DART기 2016+, 127개월) 차이계열 NW(lag3) t: Revenue **+2.02** · OperatingProfit +1.53 · OperatingCF −1.24 · GrossProfit **+1.97**. IMPROVES 조건(Δ>0 3건+ ∧ t≥2.0 2건+)에서 Δ>0 는 3건이나 t≥2.0 는 **1건뿐** ⇒ 미충족. |t|<2.0 이 3건 ⇒ REARRANGEMENT_ONLY 충족.",
    "★문턱 취약성 명시: GrossProfit 1.97 · Revenue 2.02 로 **문턱에 딱 걸렸다**. 문턱이 1.95 였으면 판정이 뒤집힌다. 사후 문턱 변경은 하지 않으나(사전등록 규율), 이 판정은 단일 draw 위에 있으며 [[project-threshold-single-draw-fragility-20260802]] 형태다.",
    "★★시대 분해가 판정보다 큰 정보다 — **TTM 은 무조건 낫지 않고 신선도와 비교가능성을 맞바꾼다**. 전기간에서는 교정이 **해롭다**(OperatingProfit Δ −0.0063 · GrossProfit Δ −0.0031). 2016+ 에서만 이롭다(+0.0052 · +0.0070). 기전: ①2015 이전 = 전 종목 분기값이라 스케일 혼합이 없고, TTM 은 최신 분기를 4분기 평균으로 바꿔 **더 낡은 신호**가 된다 ⇒ 비교가능성 이득 < 신선도 손실. ②2016 이후 = 스케일 혼합이 지배적 왜곡이라 비교가능성이 이긴다.",
    "★이 기전은 **사전등록의 DEGRADES 분기에 미리 적어둔 것**이다('최근 분기 값이 TTM 보다 신선도가 높아 모멘텀 성분을 담는 경우 … 교정을 TTM 대체가 아니라 TTM 을 별도 축으로 추가로 재설계'). 전기간 결과가 그 예측을 확인했다.",
    "⇒ **설계 함의 변경**: 수리는 '전 구간 TTM 교체' 가 아니라 **'기저를 일관되게 만들되 신선도를 버리지 않는 형태'** 여야 한다. 칩 task_4811b0a6 의 스펙을 이에 맞춰 갱신해야 하며, 단순 컬럼 교체는 2015 이전 구간의 신호를 **악화**시킨다.",
    "★수리 정당화는 유지된다(FQ-099d1a/b 정합): 근거는 IC 개선이 아니라 ⓐ현행이 비-TTM 이라는 correctness ⓑFQ-099d2 재심 대상 9건+ 이다. 미탐색 25건 전수평가는 여전히 금지(인용 2/25 = Factor Zoo 확장)."),
  next_probes = c(
    "FQ-099b1 — 교정 형태 재설계 3안 A/B: ①전 구간 TTM ②소스별 기저 일치(DART 연간 ↔ XLSX 는 최근 분기 ×4 연율화, 신선도 보존·계절성 감수) ③이중 축(원시 + TTM 을 별도 신호로 동시 투입). 오늘 실측은 ①이 2015 이전을 악화시킴을 보였으므로 ②③ 가 후보다. 주판정량 동일(차이계열 NW t, 2016+ 와 전기간 병기).",
    "FQ-099b2 — 문턱 취약성 해소: 미소 섭동 5시드 또는 블록 부트스트랩으로 차이계열 t 의 분포를 내고 q05 로 판정. 1.97/2.02 단일 draw 위에서 REARRANGEMENT vs IMPROVES 를 가르는 현 상태는 불안정하다.",
    "칩 task_4811b0a6 스펙 갱신 — '단순 TTM 컬럼 교체' 로 적어둔 부분을 '기저 일관화(형태는 FQ-099b1 결과에 따름)' 로 수정. 현 스펙대로 병합하면 2015 이전 구간 신호가 악화된다."),
  consumer_surfaces = c("팩터랭킹", "선별라벨"),
  frontier_update = "FQ-099b v2 판정 REARRANGEMENT_ONLY(문턱 근접 1.97/2.02) · ★시대 분해로 신선도↔비교가능성 트레이드오프 확립(전기간 교정 해로움) · 수리 스펙을 '전구간 TTM 교체'에서 '기저 일관화'로 변경 · FQ-099b1/b2 신규 · v1 무효 기록",
  live_trigger = "FQ-099b1 이 교정 형태를 확정하면 칩 스펙 갱신 후 수리 착수. 그 전 병합은 2015 이전 악화를 초래",
  evidence_refs = c("stage_artifacts/fq099/np_fq099b_v2.R",
                    "stage_artifacts/fq099/fq099b_v2_ic.rds",
                    "stage_artifacts/fq099/fq099b_prereg.json")
)
cat("[close_fq099b] RC_OK\n")
