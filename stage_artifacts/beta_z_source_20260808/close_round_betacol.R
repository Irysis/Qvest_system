source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id = "R-BETACOL-20260808",
  verdict_type = "infra_repair_measured",

  mechanism_diagnosis = paste0(
    "β_R05 z 원천이 북(동결 패널, 종점 2026-06-01)과 배포(factor_db live)로 갈렸으나, ",
    "extend_nolayer4_series.R 2c 의 manifest 앵커가 신규월 ret_net 을 배포 실측(invested)으로 ",
    "덮어쓰고 있어 원장 기록은 오염되지 않았다(2026-08 재현 오차 1.4e-17; 동결 β=0.50 산식 ",
    "−13.7429% 는 미채택, 원장 −8.2757%). 따라서 이 건은 활성 오염이 아니라 잠재 결함이다. ",
    "실결함은 둘: ① beta_R05 열이 앵커 적용 후에도 패널값(0.5)으로 남아 소비자가 배포되지 않은 ",
    "값을 읽고, 나아가 prev_inv = beta_R05×m4 경유로 다음 달 회전비용 기준을 오염시킨다 ",
    "② 앵커 부재 시 무뎌진 재계산치가 경고만 남기고 기록된다(규모 5.47%pt). ",
    "차단은 결함이 보이는 상류가 아니라 피해가 발생하는 2c 폴백으로 이설했다."),

  next_probes = c(
    "원천 통일 (a)live 안의 소급 규모를 실측 산출: flag 불일치 72.2% 를 북 시리즈에 실제 반영해 incumbent_book_ir 1.416 재산출 전후 대조(읽기전용, book_state 미수정) — 도훈 결정에 필요한 수치를 선제 확보",
    "2026-05 패널 규약 전환(n 343→2526, sd_z=1.0) 직후 2026-06 만 동결 쪽 rank 부호 반전(−0.689)하는 원인 규명 — era 경계 왜곡인지 단일월 이상인지 분리",
    "manifest 앵커 의존도 감사: 271행 중 앵커 269 rds / 1 manifest / 1 panel_recompute — panel_recompute 로 남은 월(2026-07)이 배포 실측과 일치하는지 대조(앵커 없는 달의 무검증 구간)",
    "invested_eff 를 monitor/holdout/recon IR 소비면이 실제로 읽는지 배선 확인 — 새 열이 원장에만 있고 소비자가 없으면 '표준↔소비자 미배선' 계통 재현"),

  consumer_surfaces = c(
    "live_book_series.csv (원장 β 열 — 정합 완료, invested_eff/beta_R05_panel 신설)",
    "extend_nolayer4_series.R 2c (회전비용 prev_inv 기준 — invested_eff 경유로 정정)",
    "run_nolayer4_monthly.sh 월간 체인 (차단 이설로 정상 통과 복귀, rc=0 확인)",
    "monitoring/holdout/recon IR (β 소비 — 미배선 확인 필요, next_probe ④)",
    "08_Tests/hooks/test_blunt_anchor_failclosed.R (차단 실효 상시 검증, 배터리 편입 대상)"),

  frontier_update = paste0(
    "원천 통일 3안(a live / b 동결연장 / c era-aware)은 도훈 판단 대기이나 긴급도 하향 ",
    "— 기록 오염 부재가 실측 확인됐으므로 자본 게이트 압박 없음. §7b 정합상 (a) 권고 유지."),

  live_trigger = paste0(
    "다음 중 하나가 발화하면 원천 통일을 즉시 재상신한다: ",
    "① manifest 앵커가 없는 신규월이 발생(= test_blunt_anchor_failclosed 계약이 실차단) — ",
    "   앵커 보호가 벗겨지는 순간 잠재 결함이 활성 오염으로 전환된다 ",
    "② 동결 패널 종점(2026-06-01) 이후 신호일이 3개월 이상 누적 ",
    "③ beta_R05_panel 과 invested_eff 괴리가 2개월 연속 발생(현재 1건: 2026-08) ",
    "④ incumbent_book_ir 재산출이 필요한 다른 사유(신규 admission·PG2 교체)가 생겨 어차피 재계산할 때 ",
    "⑤ 2026-06 부호 반전이 era 경계 왜곡으로 판명되면 (c) era-aware 안이 우선순위 상승")
)
