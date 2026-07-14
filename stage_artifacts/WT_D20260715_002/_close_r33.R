source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "R33 / FQ-049 / WT-D20260715_002 (insider 소비면 전환)",
  verdict_type = "capability_established",
  mechanism_diagnosis = "insider net-buy breadth 클러스터가 monitoring 소비면에서 종목단 forward 안전신호로 유효(gap t=+3.36, size-neutral +5.22, large-cap tier t=+2.57, 하방/vol/tail 감소) — 선별-면 cap-tier 벽(R9)이 monitoring-면엔 안 걸림. 단 net-seller exclusion 필터(paired t=-0.09)·net-sell tripwire(t=-0.01)는 config-scoped negative(수익-파생 선별/필터 벽 잔존).",
  next_probes = c(
    "net-buy 클러스터를 incumbent PG2 book overlay/de-risk 예외 신호로 배선 측정 — 북 보유 종목 net-buy flag 시 실현 drawdown 개선 여부(tripwire 실효, 자본 아님)",
    "net-buy 클러스터 coverage 확장(126m→, INS02+INS03 결합/임계 완화)로 large-cap tier(t=2.57) 안정성 재검정",
    "net-buy forward-gap sector-neutral 검정 — size 통제는 통과, 섹터/지배구조 잔여 confound 격리"
  ),
  consumer_surfaces = c(
    "⑤monitoring: net-buy breadth 클러스터 → forward 안전 tripwire (배선 후보)",
    "⑥선별라벨: net-sell exclusion 무효 (배선 금지)",
    "①유니버스 필터: net-sell 필터 무효 (배선 금지)"
  ),
  frontier_update = "FQ-049 insider 소비면: monitoring-면(net-buy) capability_established → tripwire 배선 후보로 전개. 선별/필터-면(net-sell) config-scoped negative.",
  live_trigger = c("net-sell 방향 부활 = 임원 순매도 정보성 회복 레짐(공시제도 강화/숏 규제 변화) 또는 비-장내 순매도 magnitude 데이터원 등재 시"),
  layer = "⑤monitoring (net-buy 열림) / 선별·필터-면 ①재료 수익-파생 벽 잔존",
  evidence_refs = c(
    "stage_artifacts/WT_D20260715_002/verdict_r33_insider_consumption.json",
    "stage_artifacts/WT_D20260715_002/r33_results.json",
    "stage_artifacts/WT_D20260715_002/r33_sizeneutral.json",
    "stage_artifacts/WT_D20260715_002/challenge_note_r33_20260715.md"
  )
)
