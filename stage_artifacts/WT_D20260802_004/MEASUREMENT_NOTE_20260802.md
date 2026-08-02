# ⚠ 측정 기준 주의 — 이 디렉터리의 수치는 **구판 라벨** 기준 (2026-08-02 부기)

이 WT 의 6개 팩터 패널은 `ast_compile.R` 의 factor_db_monthly provider 로 컴파일됐는데,
당시 provider 가 월별 팩터 행을 **캘린더 월말**로 라벨했다. eval 그리드(`compile_meta.rds::SIG`)는
**거래일 월말**이므로, 거래말 < 캘린더말인 달에는 AS_OF 조인이 그 달 값을 못 보고 **전월 값을
당겼다** — 실측 **94/259 월(36.3%)**, 첫 월(2004-12-30)은 매칭 0 으로 **통째 소실**(패널 258월).
lag 방향이라 look-ahead 는 아니고 **측정 감쇠**다. 결함 등재 = `06_Registry/ast_leaf_table_bugs.jsonl` **ALB-008**.

## 재산출 결과 — 정성 판정은 유지, 개별 수치 3건 정정

수리판 패널로 축③④ 를 동일 정의(run_wt004_eval.R §4~6)로 재산출했다.
**원 산출물은 무변경(읽기 전용)** — 이 노트가 유일한 연결 고리다.

- **유지**: 방어 배향 전 구성 PORT_t 음수 · 조합이 단일 최선에 crisis_alpha·하락에피 양쪽 미달 ·
  C_ORTH 멤버십 {D03, D41, D55} 동일 · primary C_ORTH_def PORT_t −0.842 → **−0.859**
- **정정 ①** `D55_Vol_Trend_def` PORT_t **+0.207 → −0.195** (부호 반전)
- **정정 ②** 같은 구성 MDD-complement **−0.8pp → +0.3pp** → L-code ③ 의
  "MDD-complement **전 구성** 음수"는 전칭이 아님(6/7 음수, D55 ≈ 0)
- **정정 ③** **회전율 전 구성 과소 계상**(포트 레벨 +3~15%, CORE_M01 628→720%/yr).
  스테일 월엔 패널이 안 움직여 회전이 1/3 로 억제되고 다음 달로 이연된다 → 15bps/leg 비용이
  덜 잡혀 net 이 비용축에서 **유리하게** 나왔다. 신호 감쇠(불리)와 **반대 방향** 편향 공존.
- 관측 월수 258 → **259**(소실 월 복원), Core MDD 59.5% → 59.7%

## 수치를 인용할 때

| 용도 | 인용처 |
|---|---|
| 정성 결론·가설 판정 | 이 디렉터리 + L-code `L-AR-20260802_124500` (유효) |
| **축③④ 수치**(crisis_alpha·하락에피·MDD-compl·turnover) | **`04_Research/01_reports/wt004_axis34_sidebyside_20260802.json`** |
| 결함 규모·기전 전체 | `04_Research/01_reports/ast_asof_stale_impact_20260802.md` |

L-code 에는 `measurement_caveat.status = RECOMPUTED_CONCLUSIONS_HOLD` 로 동일 내용이 부기돼 있다.
provider 수리는 브랜치 `claude/confident-pasteur-53fafb`(075a613c/04b526af/8ef012fc) — 이 노트 작성
시점에 **main 미반영**이므로, 이 디렉터리를 재컴파일하려면 병합 후에 해야 같은 결함이 재발하지 않는다.
