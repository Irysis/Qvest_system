source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "OVERLAY-I1-J1-20260808",
  verdict_type = "incumbent_confirmed",
  mechanism_diagnosis = "J1 에서 재구성을 포기하고 원장 저장값(beta_R05·m4)을 직접 대조하자 캐리어 invested 가 100% 일치하고 regime×beta 교차표가 문서화된 2×2 표와 정확히 맞아떨어졌다 — 누락 성분은 없었고 내 재현 갭은 factor DB 재계산 z 가 production 저장 R05_z_avg 와 cor 0.712 로 갈린 것 단독이었다(§7b 실증). 그 충실한 base 위에서 I1(β 매핑 연속화)을 완주한 결과 연속 f(z) 3종이 전부 현행 이산 2×2 표보다 열위(Calmar 1.793 이하 vs 현행 1.953)였고, flag 심화는 SR 이 1.908→1.905 로 불변이라 효율 개선이 아니라 위험-수익 선 위의 다이얼 이동임이 드러났다(−0.20 심화 = CAGR −2.09%pt 지불하고 MDD −1.97%pt 획득). 즉 현행 매핑이 이 축에서 이미 효율적이며, MDD 를 더 낮추는 공짜 경로는 이 축에 없다. 부수 확인: z-flag 발화 72개월 중 65개월이 BULL/NORMAL 로, 그 실체는 위기 대응이 아니라 평시 국면의 0.85 감축이다.",
  next_probes = c(
    "K1: MDD 여유를 CAGR 로 되사는 방향의 역질문 — 현행 MDD 23.27% 는 목표(25%) 대비 1.73%pt 여유가 있다. flag 심화의 역방향(완화)으로 여유를 CAGR 로 전환할 수 있는지 같은 곡선 위에서 측정(B arm 이 MDD 24.81%·CAGR +1.29%pt 를 보여줌 — 목표 안에서 더 벌 여지). 목표가 MDD 하한이 아니라 상한이라는 점이 이 방향을 정당화한다.",
    "K2: 타이밍 83% 의 성분별 ablation — base 가 100% 재현되므로 이제 의미를 갖는다. m4 단독 / β_R05 단독 / 둘 다 제거 arm 을 만들어 MDD 기여를 분해. D3 는 '타이밍 전체'만 쟀고 누가 얼마인지는 미분해. m4(BOCPD)가 15.9% 달에서만 작동하는데 기여가 크면 그 축이 다음 레버.",
    "K3: 문턱 vintage 기록 부재 — production 저장 z + 정적 q20 으로도 flag 일치가 87.6% 뿐이라 backtest 는 시점별 확장 문턱을 썼는데 그 정의가 산출물에 없다. §7 pin 대상으로 등재하고, I1 계열 후속 측정은 문턱 정의를 명시 고정한 뒤 수행."
  ),
  consumer_surfaces = c(
    "위험모델/베타예산: MDD-CAGR 다이얼 위치가 선호 선택임을 명시 — 현행 23.27% / −0.10 심화 22.28% / −0.20 심화 21.30%, 각각 CAGR 1.0~2.1%pt 지불",
    "monitoring 신호: z-flag 발화가 평시(BULL/NORMAL) 중심 26.8% 라는 사실을 관측면에 노출 — '위기 대응 장치'로 오해되고 있음",
    "선별 라벨: 연속 매핑 열위는 이 측정틀 결과이므로 다른 base(다른 전략/유니버스)에서는 재측정 대상",
    "타 모드 이식: FR/RAMP 의 regime-조건부 배분도 이산 표 대 연속 함수 비교를 같은 방식으로 수행 가능"
  ),
  frontier_update = "FQ 등재 예정: K1(MDD 여유의 CAGR 전환 — 목표 상한 해석) · K2(타이밍 성분 ablation) · K3(문턱 vintage pin). K2 가 레버 소재지 특정이라 최우선.",
  live_trigger = "β 매핑 연속화 재도전 조건 (config-scoped negative, 경로-scoped): ① 다른 base 전략/유니버스에서 이산 대 연속 비교 시 재측정(본 결과는 STR_1715×D3 오버레이 한정) ② z 원천이 production 저장값이 아닌 재계산 패널로 교체되고 parity 가 검증되면 z 분해능이 달라져 재계산 ③ 문턱 정의가 pin 으로 고정되면 연속 매핑의 설계공간이 달라져 재시험.",
  layer = "오버레이 β 매핑 — 방어 계층 (현행 효율 확인, 다이얼 위치는 선호)",
  evidence_refs = c("stage_artifacts/tilt_realign_20260808/p17_i1_beta_redesign.csv",
                    "stage_artifacts/tilt_realign_20260808/p16_j1_close.csv",
                    "memory: project-regime-label-response-depth-20260808")
)
