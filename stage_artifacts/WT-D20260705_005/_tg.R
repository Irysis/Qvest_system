source("02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent="Alpha",
  title="WT-D20260705_005 ALPHA_DONE — RAMP 잔차-직교 sleeve 개별 배포 스크리닝 = 0/11 통과",
  sections=list(
    list(type="kv", title="판정 요약", data=list(
      "개별 sleeve"="11개 직교 경제군 (Consensus/Value/Momentum/…)",
      "유니버스"="K200∪KQ150 top-25 EW long-only, 15bps",
      "HARD 통과(PORT_t≥2.95)"="0/11",
      "screen-tier(≥1.5)"="2/11 (Consensus 2.16 · Value 1.57)",
      "verdict"="FAIL_NO_SURVIVOR"
    )),
    list(type="kv", title="핵심 지표 (cap-w authoritative)", data=list(
      "max PORT_t (NW lag-3)"="+2.16 (Consensus)",
      "rank-IC 최강"="Momentum 0.040 / Harvey-t 8.09 → but PORT_t 0.51 (전이 벽)",
      "oos_retention"="11/11 음수 (전원)",
      "post-2017 t"="11/11 음수 → cohort decay 벽",
      "DSR(진단, best)"="0.77 (신호 실재 ≠ 배포 alpha)"
    )),
    list(type="bullet", title="Challenge Flags", items=c(
      "HIGH: request '18후보' 모델 ≠ 실제 아티팩트 → 실제 11 직교 sleeve로 정정 수행 (AX-000 정직)",
      "HIGH: 전 11 sleeve oos+post2017 음수 = cohort-wide decay(overfit 아님)",
      "PIT: look-ahead 부재(FWL per-date), C14/C15/C10 PASS"
    )),
    list(type="bullet", title="다음 단계 / 결론", items=c(
      "measurement-graduation §6 미해결('RAMP 잔차 sleeve 개별 PORT_t 검증') = CLOSED-negative",
      "survivors 0 → Risk/Optimizer로 넘길 α̂ 없음, multi-sleeve 스택·ΔIR moot",
      "개별 배포 스크리닝도 IC→PORT_t 전이 벽 (결합 M-code 2.37·composite falsification과 동일 posterior)"
    ))
  )
)
