source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id = "R-ICSIGN-20260808",
  verdict_type = "capability_established",

  mechanism_diagnosis = paste0(
    "next_probe ①(IC 부호 직접 검증) 실행 결과 내 1차 가설이 반증됐다. raw R05 z 의 forward-return IC ",
    "271개월 실측: 2004-2015 평균 −0.00153(t=−0.25, 잡음과 구분 불가) / 2016-2026 평균 −0.02113(t=−3.35, 유의). ",
    "부호는 두 구간 다 음수 — **반전이 아니라 크기 변화**다. 따라서 '2016년 IC 부호가 뒤집혀 live 가 따라갔다'는 ",
    "설명은 틀렸고, 실제는 '동결 패널의 고정 방향은 방향을 정할 근거가 없던 시기(t=−0.25)에 박힌 값이며 ",
    "2016년부터 IC 가 유의해지자 live 만 반영했다'이다. live 우위 근거가 SR 간접증거에서 IC 유의성 직접증거로 승격. ",
    "next_probe ②(재도출 영향) 실측: 2016+ 구간에서 live 가 SR +0.093·MDD −2.42%pt·Calmar +0.126 로 3지표 전부 우위이나, ",
    "전기간으로는 MDD +1.23%pt·Calmar −0.138 로 악화 — pre-2016 구간에서 나빠지기 때문이다. ",
    "즉 증거가 있는 구간(2016+)에서만 live 가 낫고, 증거가 없는 구간(pre-2016)에서는 오히려 손해다."),

  next_probes = c(
    "era-aware 재도출(2016+ 만 live-z 로 재산출, pre-2016 은 현행 유지)의 성과를 실측 — 현재 (a)전기간/(b)현행 두 점만 있고 이 중간안은 미측정. 증거가 있는 구간에만 변경을 국한하는 안이라 EV 가 가장 높을 수 있다",
    "pre-2016 에서 live 가 왜 더 나쁜지 기전 규명 — IC 가 잡음이면 방향은 무작위여야 하는데 체계적으로 나쁘다면 정렬 절차의 다른 축(레지스트리 fallback·min_ic_months 창)이 개입한 것",
    "교락 분리: 재계산 vs 계약 rds 불일치 162개월 중 live 전환 전 이미 있던 7개월의 사유(m4 vintage 등)를 특정해 z 귀속분 155개월을 깨끗이 분리",
    "R05 외 팩터로 일반화 검증 — 동결/live 기준 반전이 R05 고유인지, 동결 패널 전체가 같은 시기에 굳은 것인지(같은 패널의 다른 팩터 IC 유의성 전환 시점 대조)"),

  consumer_surfaces = c(
    "계약 rds 앵커(WT-D20260702_002) — 재도출 여부 = 도훈 판단(자본 게이트 baseline 연동)",
    "live_book_series.csv beta_matches_ret_net (기준 이음매 162행 명시)",
    "run_layer5_rerun_extended.R (z 원천 live, A/B 스위치 보유)",
    "align_factor_direction / factor registry (min_ic_months·fallback 규약 — next_probe ② 대상)",
    "essence_score·hurdle_gate (SR/MDD/Calmar 소비 — 재도출 시 재채점 대상)"),

  frontier_update = paste0(
    "z 원천 통일은 완료(live). 계약 rds 재도출은 3안이 열려 있고 그중 era-aware(2016+ 한정)는 미측정 — ",
    "증거 구간에만 변경을 국한하는 안이라 다음 사이클 최우선. 전기간 재도출은 pre-2016 손해가 실측돼 단독 추천 불가."),

  live_trigger = paste0(
    "다음 중 하나가 발화하면 rds 재도출을 재상신한다: ",
    "① era-aware 안 실측이 전기간 Calmar 를 현행(1.899) 이상으로 유지하면서 2016+ 개선을 보존 ",
    "② pre-2016 열위의 기전이 규명돼 제거 가능함이 확인 ",
    "③ 신규 admission·PG2 교체로 어차피 incumbent_book_ir 재산출이 필요해짐 ",
    "④ beta_matches_ret_net 불일치 162행을 소비면이 실제로 잘못 읽고 있음이 확인 ",
    "⑤ 동일 기준 반전이 R05 외 팩터에서도 확인되면(패널 전체 문제) 개별 재도출이 아니라 패널 재빌드로 격상")
)
