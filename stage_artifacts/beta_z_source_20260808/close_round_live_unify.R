source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id = "R-LIVEZ-20260808",
  verdict_type = "capability_established",

  mechanism_diagnosis = paste0(
    "β_R05 z 원천을 live(factor_db)로 통일했다(도훈 승인). 실측 결과 예측이 빗나갔다: ",
    "원장 ret_net 변경 0/271행, IR 1.6701 무변경 — 계약 rds 앵커가 269/271월을 고정해 z 교체가 ",
    "기록에 닿지 않기 때문(앵커가 역사를 절연). 목표 지표는 달성: 2026-08 북 재계산 vs 배포 실측 ",
    "괴리 −5.47%pt → +0.00%pt. 덤으로 구조 결함 해소 — 배포는 z 를 live 로 재면서 문턱 q20 은 ",
    "동결 기반 북 패널에서 읽어 어긋난 자였다(q20 +0.18 vs −0.35). ",
    "★그리고 더 큰 구조가 드러났다: 동결/live 기준은 2015→2016 에서 갈려 11년 연속 반전 상태이며 ",
    "(rank −0.44~−0.88), 계약 rds 앵커 범위가 두 기준에 걸쳐 있어 앵커된 역사는 단일 기준이 아니다. ",
    "메모리의 '2026-06 부호 반전'은 내 이중정렬 산물이었고 실제로 2026-06 은 +0.974 로 가장 잘 맞는 달이다."),

  next_probes = c(
    "방향 옳음의 직접 검증: post-2016 구간에서 R05 z 의 부호별 forward-return IC 를 실측해 live(IC-추종) 방향이 실제로 옳은지 판정 — 현재 근거는 SR 우열(1.8589 vs 1.8092)뿐이고 이는 간접 증거",
    "계약 rds 재도출 여부 결정에 필요한 수치 선확보: rds 를 live-z 기준으로 재산출했을 때 269개월 ret_net·IR·MDD 변화폭을 읽기전용 산출(book_state 미수정)",
    "2005-06·2007-01 단발 반전 2건의 성격 규명 — 11년 반전과 같은 기전인지 표본 잡음인지(스윕이 연 2점이라 해상도 부족, 월별 조밀 측정 필요)",
    "beta_matches_ret_net 불일치 162행을 소비면이 실제로 존중하는지 감사 — monitor/holdout/recon IR 이 β 열을 읽는다면 어느 기준 값을 쓰는지 확인(새 열이 원장에만 있고 소비자가 없으면 미배선 계통 재현)"),

  consumer_surfaces = c(
    "live_book_series.csv (β·invested_eff·beta_R05_panel·beta_matches_ret_net — 신설 완료)",
    "run_layer5_rerun_extended.R (z 원천 live 기본, QVEST_R05_Z_SOURCE=frozen 로 A/B)",
    "forward_weights_D3_M4gAE.R 배포 문턱 q20 (북 패널 경유 — live 통일로 기준 자동 정합)",
    "extend_nolayer4_series.R 2c (blunt-anchor fail-closed + β 열 정합)",
    "08_Tests/hooks/test_blunt_anchor_failclosed.R (6/6, 정리 원복까지 채점)",
    "monitoring/holdout/recon IR (β 소비 여부 미확인 — next_probe ④)"),

  frontier_update = paste0(
    "z 원천 통일은 실행 완료(live). 남은 미검 축 = 계약 rds 의 기준 이음매 — ",
    "역사(2004~2026-04, 그중 2016+ 는 반전 기준)와 신규월(live)이 다른 기준 위에 있다. ",
    "재도출은 IR 재산출을 동반하므로 도훈 판단 대상이나, 판단에 필요한 수치는 next_probe ②로 선확보 가능."),

  live_trigger = paste0(
    "다음 중 하나가 발화하면 계약 rds 재도출을 상신한다: ",
    "① next_probe ① 의 IC 부호 검증이 live 방향 우위를 확정(그러면 반전 기준 위의 269개월 앵커가 근거를 잃는다) ",
    "② beta_matches_ret_net 불일치 행을 소비면이 실제로 잘못 읽고 있음이 확인 ",
    "③ 신규 admission·PG2 교체 등으로 어차피 incumbent_book_ir 를 재산출해야 하는 사유 발생 ",
    "④ 동결/live 반전 구간이 2026-05 재빌드 이후 다시 벌어짐(재빌드가 일시적 봉합이었다는 신호) ",
    "⑤ manifest 앵커 없는 신규월 발생 — 그 순간 기록이 패널 기준에 직접 의존하므로 기준 문제가 활성화된다")
)
