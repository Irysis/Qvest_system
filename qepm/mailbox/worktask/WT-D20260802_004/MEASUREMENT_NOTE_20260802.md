# ⚠ 측정 기준 주의 (2026-08-02 부기) — 축③④ 수치는 재산출본을 인용할 것

이 WT 의 factor_db_monthly 리프 패널이 **캘린더 월말 라벨** 결함(ALB-008)으로 94/259 월(36.3%)에서
전월 값을 당겼다(lag 방향, look-ahead 아님 = 측정 감쇠).

- **정성 판정·가설 결론은 유지** (방어 배향 전 구성 PORT_t 음수, 조합 < 단일 최선, C_ORTH 멤버십 동일).
  primary C_ORTH_def PORT_t −0.842 → −0.859.
- **정정 3건**: D55_Vol_Trend_def PORT_t +0.207 → −0.195(부호 반전) · 같은 구성 MDD-complement
  −0.8pp → +0.3pp("전 구성 음수" 전칭 깨짐) · **회전율 전 구성 과소 계상**(포트 레벨 +3~15%).
- 관측 월수 258 → 259(소실 월 복원).

전체 대조: `stage_artifacts/WT_D20260802_004/MEASUREMENT_NOTE_20260802.md`
수치 원본: `04_Research/01_reports/wt004_axis34_sidebyside_20260802.json`
결함/영향: `06_Registry/ast_leaf_table_bugs.jsonl` ALB-008 · `04_Research/01_reports/ast_asof_stale_impact_20260802.md`
