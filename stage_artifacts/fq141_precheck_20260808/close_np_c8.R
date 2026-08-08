source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "NPC8_20260808_REVERSAL_IS_GIVEBACK",
  verdict_type = "capability_established",
  layer = "4_construction",
  mechanism_diagnosis = paste(
    "2026-06/07 의 음수 d 반전은 승자 교체가 아니라 되돌림(giveback)이다.",
    "정점 구간(2026 1~5월, 월평균 d +0.11980) 주도 상위-2 = A000660 +0.24359 / A005930 +0.21535.",
    "반전 2개월 구간 음수기여 순위 = A000660 1위/347(-0.13697) · A005930 2위/347(-0.09528).",
    "★정점 주도 상위-2 와 반전 주도 상위-2 가 정확히 동일(교집합 = 둘 다). 되돌림 비율 하이닉스 56.2% · 삼성 44.2% — 5개월에 쌓은 기여를 2개월에 절반 가까이 반납했다.",
    "함의: 새 승자 출현이 아니라 같은 이름의 되돌림이므로 경로가 상대적으로 예측 가능하고 평균회귀 서사와 정합한다.",
    "★단 전환 선언은 여전히 보류 — 2개월 표본이고 2026 안에서 월별 d 가 -0.14~+0.34 로 요동한다. NP-c5 사전등록 문턱(6m 롤링 d_ann 이 역사 75 백분위 +0.0314 아래로 3개월 연속)이 그대로 유효하며 단일 월 반등으로 번복 금지.",
    "NP-c8 이 물은 질문(되돌림인가 교체인가)에는 답했으나, 되돌림이 어디까지 진행될지는 미측정이다."),
  next_probes = c(
    "NP-c9 되돌림 완료 지점 추정 — 과거 유사 구간(메가캡 승자가 대규모 기여 후 반납)에서 되돌림이 정점 기여의 몇 % 에서 멈췄는지 분포. 현재 44~56% 가 그 분포의 어디인지가 남은 경로의 추정치",
    "NP-c7 반전 감시 배선(이월) — 6m 롤링 d_ann 월간 산출 + 사전등록 문턱 통과 기록. 되돌림이 확인됐으므로 감시 EV 가 올라갔다",
    "NP-157c2a1b 이월 — 과거 90+ 백분위 구간의 지속 기간 분포. 정점을 이미 지났다면 질문이 '얼마나 더'에서 '회귀 경로의 모양'으로 바뀐다"),
  consumer_surfaces = c("monitoring", "위험모델", "선별라벨"),
  frontier_update = "반전의 정체 = 되돌림 확정(정점/반전 주도 종목 동일) · 되돌림 비율 44~56% · 전환 선언은 사전등록 문턱 유지 · NP-c9 신규",
  live_trigger = "NP-c5 사전등록 문턱 불변 — 6m 롤링 d_ann 이 +0.0314 아래로 3개월 연속 유지 시 정상화 판정. 되돌림 확인은 그 문턱을 앞당기는 근거가 아니다(기전 확인일 뿐)",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_c8_reversal_attrib.R",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1_d_extended.csv",
                    "stage_artifacts/fq141_precheck_20260808/np157c2a1c_findings.md")
)
cat("[close_np_c8] RC_OK\n")
