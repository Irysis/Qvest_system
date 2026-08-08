source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "LABEL-LANE-R1R2-20260808",
  verdict_type = "config_scoped_negative",
  mechanism_diagnosis = "위기월(expanding-q10) 사전식별 시도 9종 전건 FAIL — 벤치 시계열 파생 4종(낙폭·변동성·3m수익·변동성비)과 종목간 구조 파생 5종(횡단면분산·상승종목비율·동조화·거래대금z·분산급확대) 모두 precision 이 기저(0.077) 근방이고 p>0.29. 자격 관문을 통과하는 유일한 신호는 기존 라벨(BOCPD/AE 계열, precision 6.22× · p<0.0001 · recall 0.556). 기전 진단: 단일 지표에 expanding 문턱을 씌우는 형태가 문제 — 위기는 여러 축이 동시에 어긋나는 사건인데 단일 문턱은 그 결합을 표현 못 하고, 결합해도(동조화∧약세확산) 발화가 희소해져 유의성을 잃는다. 한편 대응 깊이 축은 SR 만 회수하고(ΔSR +0.072 = 오라클의 18%) MDD 는 0% 회수 — MDD 를 만든 월이 NORMAL 라벨 밖에 있기 때문.",
  next_probes = c(
    "L1: 비-return 원천으로 사각지대 공략 — 옵션 IV 표면(스큐 급변)·대차잔고/공매도 잔량·DART 이벤트 밀도. 9종 실패는 전부 가격/거래량 파생이었고, 제약 조건-안 프론티어 ①(비-return 원천)이 미시도 상태. 데이터 가용성 census 선행(FQ 등재 시 즉시 측정 가능 여부부터).",
    "L2: 단일 문턱이 아닌 결합 학습형 — 9개 feature 를 입력으로 하는 walk-forward 분류기(로지스틱/GBM)로 위기월 확률 추정. 단 selection_type=sweep 이므로 DSR + 사전등록 필수, 그리고 P6/P7 의 개별 실패가 '정보 없음'이 아니라 '단일 문턱으로 표현 불가'였는지를 먼저 판별(다변량 AUC 가 개별 최대치를 넘는지).",
    "L3: 사각지대 8개월의 사후 해부 — NORMAL/BULL 라벨을 달고 최악 10분위에 들어간 월들이 서로 공통 구조를 갖는지(급락 유형·섹터 집중·유동성). 공통 구조가 없으면 예측 자체가 무의미하고, 있으면 그 구조가 곧 feature 설계도. 예측 시도 전에 표적의 성질부터 재는 순서.",
    "L4: 대응 깊이 축의 잔여 — CAUTION β 심화가 SR +0.072(p=0.030)로 유효하나 sweep 3값 단일표본. 정식 심사(DSR·holdout 사전등록·book-marginal ΔIR)로 채택 자격을 판정. MDD 목표와는 무관하고 SR 목표에만 기여함을 명시."
  ),
  consumer_surfaces = c(
    "위험모델/베타예산: 라벨 자격 관문을 recall 축까지 확장 — 현 관문(precision·p)은 CRISIS 단독(recall 0.111)도 PASS 시키는데 상금 회수엔 recall 이 결정적",
    "monitoring 신호: 9종 실패 신호를 감시 대시보드에서 제외(발화하되 무의미한 경보 = 침묵보다 해로움)",
    "선별 라벨: 기존 라벨(BOCPD/AE)의 precision 6.22× 는 재확인된 자산 — 라벨 교체가 아니라 대응 매핑 재설계가 레버",
    "타 모드 이식: FR/RAMP 의 regime 입력도 같은 라벨을 쓰므로 이 판정이 그대로 적용"
  ),
  frontier_update = "FQ 등재 예정: L1(비-return 위기 예보 원천 census) · L3(사각지대 8개월 해부). L2 는 L3 결과에 조건부.",
  live_trigger = "가격/거래량 파생 위기예보 재도전 조건 (9-hits negative, 경로-scoped): ① 다변량 AUC 가 개별 최대(0.14 precision 급)를 유의하게 넘는 것이 L2 에서 확인되면 단일문턱 실패는 표현력 문제로 재분류 ② 옵션/대차 등 비-return 원천이 붙어 결합 feature 가 되면 재측정 ③ 사각지대 8개월이 L3 에서 공통 구조를 보이면 그 구조 전용 신호로 재설계.",
  layer = "국면 라벨/오버레이 — 방어 계층",
  evidence_refs = c("stage_artifacts/tilt_realign_20260808/p7_crosssectional.csv",
                    "stage_artifacts/tilt_realign_20260808/p6_label_recall.csv",
                    "stage_artifacts/tilt_realign_20260808/p6b_deepen_caution.csv",
                    "memory: project-regime-label-response-depth-20260808")
)
