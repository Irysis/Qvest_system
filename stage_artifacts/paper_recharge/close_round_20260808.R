source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/close_round.R")

close_round(
  round_id  = "paper_recharge_20260808_SpectralPersistence",
  verdict_type = "config_scoped_negative",

  mechanism_diagnosis = paste(
    "rolling-252일 R/S Hurst 지수(H>0.5 long)는 전 기간 cap-w long-only 25종목 프레임에서",
    "PORT_t=0.978(FAIL vs 2.95), OOS=0.369(FAIL vs 0.70) — 신호 자체가 추세 지속성을 포착하나",
    "cap-w 상위종목이 추세 효과를 희석(post-2017 MEGA 포화 가능성).",
    "단, Rate_2022 위기 알파 +17.4%pp는 금리 상승 국면 조건부 유효성을 시사."
  ),

  next_probes = c(
    "FQ-158: 금리 상승 국면(기준금리 인상 사이클) 조건부 Hurst 팩터 — 전 기간 약하나 Rate_2022 +17.4%pp 위기 알파가 국면 조건부 배분에서 살아날 가능성. canonical_screen_bt로 금리 국면 서브샘플 PORT_t 실측 필수",
    "FQ-159: Hurst 팩터 cap-tier 분해 (MEGA vs MID 별도 스코어링) — post-2017 MEGA cap 벤치 아티팩트 여부 확인. EW-유니버스 대비 및 cap-tier별 IC·PORT_t 실측 (measurement-graduation §1 dual-basis 의무)"
  ),

  consumer_surfaces = c(
    "AX-001 defense 조건부 평가: crisis_alpha Rate_2022 +17.4%pp·EuDebt_2011 +39.7%pp로 위기 보험 후보 — bad/normal IC ratio 실측 후 레짐 오버레이 입력 검토",
    "OVERLAY_CANDIDATE feature 보존: standalone QUARANTINE이나 신호 자체는 폐기 아닌 피처로 보존 (§5 DPL 원칙 — 구현 lane 아님, 피처로만)",
    "regime route 소비: mode_queue_20260808 regime 항목으로 이미 등재 — TF Systems Science(2607.19497) 소비자가 Hurst 추정 파이프라인 참고"
  ),

  frontier_update = paste(
    "FQ-158(금리국면 Hurst) · FQ-159(cap-tier Hurst) →",
    "alpha_frontier_queue.json 등재 대상 (dohoon_decision 항목 아님, Q-Lead 착수 가능).",
    "FQ-092(vol rank 역방향)·FQ-149(FX_Intensity) 소비 대기 중 — 우선순위 큐 대비 중하위"
  ),

  live_trigger = c(
    "금리 상승 사이클 재진입 신호: 한국은행 기준금리 연속 인상 ≥2회 OR FRED KRBASE 12m 변화 >+50bps → FQ-158 착수 자동 트리거",
    "cap-tier 분해 측정 가용 시점: 현 factor_db에 MEGA/MID 분류 파티셔닝 배선 완료 후 FQ-159 즉시 착수"
  ),

  layer = "①재료 (비-return 스펙트럼 통계 — 신규 원천)",

  evidence_refs = c(
    "stage_artifacts/paper_recharge/paper_recharge_20260808.done",
    "stage_artifacts/paper_recharge/alpha_search_route_20260808.json",
    "06_Registry/alpha_frontier_queue.json"
  )
)
