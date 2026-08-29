# 전략 로테이션 — 2계층 리서치 (Level 1)

**발효**: 2026-06-05 (도훈 mandate) · **★v10 전면 개정 2026-08-29** (도훈 지시 — 2계층 재편).
**위반 = AX-002 동급**(실측-only·프로세스 우회 금지).
**SOT**: `.claude/skills/strategy-rotation/SKILL.md` (절차 — v10 재작성판).

## 1. 계층 정의 (v10 — 구 "제3 리서치 모드" 서술 대체)

**2계층 = 1계층(팩터전략 리서치)이 생산한 B등급 이상 전략을 소비해, 어느 시장
상황에서나 통하는 한국 특화 전천후 모델을 설계하는 심화 리서치 계층.**
- 아이디어는 논문에서 시작(세션 온디맨드 검색 — 무인 수집기는 1계층 전용).
  모든 수치 의사결정에 근거 논문 원문 링크 필수(파생 결정은 뿌리 논문 제시). 하드코딩 금지.
- **1 모드 2 트랙**: Track1 레짐엔진 리서치(국면 정의+예측) → Track2 배분 리서치. Track1→Track2 의존.
- **FR_XXXX = 운용체계**(module pool + regime engine ver + 배분정책), STR_XXXX = 개별 모듈(부품).
- **리서치 1단위** = {국면엔진 사양 + 배분규칙 사양 + WF 실측 1회} → essence 등급(A/B/C/F) 산출.
- **강화 프로세스 = 무한** — A등급 달성까지, 교훈 지속 주입(원장 `06_Registry/reinforce_ledger_l2.json`,
  축 = `regime_identification` / `strategy_combination`). 절차 = `.claude/skills/reinforce/SKILL.md`.
- **A 달성 → Judge(PIT 전담) → PASS → BOOK 등록**(`register_book_entry(kind="rotation_rule")`,
  도훈 confirm 수동).

## 2. 모듈 적재 계약 (표준화, 언어무관 — 불변)

- 모든 산출물은 **`register_module()`** 경유 표준화. FR-소비 표준형 = `contract_pass=true` +
  `metric_type=backtested` + `frozen=true` + `source_contract_id/module_hash/build_version/cost_model_version`.
  ★v10: 신규 등재분 `grade_basis` 기록 의무(essence/mandate/proxy 구분).
- floor 통과: `04_Research/strategies/{id}/sim_result.rds` + `module_catalog.json(fr_eligible=true)`.
  미충족: `module_quarantine` 보존, FR 소비 금지.
- **★원장 상호배타 (2026-08-02)**: strategy_id 는 catalog/quarantine 중 최대 한 곳.
  승격 시 격리행은 `superseded{}` tombstone 이동. 역방향은 `mode="shadowed"`.
  스크린 = `reconcile_module_registries.R`. 검사 = `test_module_registry_exclusivity.R`.

## 3. ★모듈 풀 = 2단 게이트 (v10 — 구 "등급무관 RCMA 단독" 대체)

**①자격 = essence grade ∈ {A, B}** — `build_module_performance.R` grade floor
(`QVEST_L2_GRADE_FLOOR`, 기본 B · OFF=진단 전용). 도훈 지시 "1계층에서 생산된 B등급
이상의 전략들을 활용"이 구 2026-06-05 "등급무관 specialist 차용" mandate 를 **대체**한다.
F-overall specialist 는 풀 부적격 — 그 재료는 1계층 강화로 B 이상을 만든 뒤 편입.
산출물에 `grade_floor`·`n_floor_excluded` 메타 기록(검사 재도출 = `test_l2_pool_grade_floor.R`).
**②배치 = RCMA 6기준** (유지): ① regime_IR≥0.5 OR 상위⅓ ② n_months≥12 ③ IS·OOS 부호
지속 ④ |t|≥2 ⑤ 경제논리 1줄 ⑥ ΔIR>0(advisory). admitted=①∧②∧③∧④.
근거 = v2.1 A/B 실측 "dispatcher RP-앵커는 IR 무관 → admission 이 유일 품질 게이트".
- rare_mode 는 2회 A/B 기각으로 영구 OFF (재도전 트리거 = 직교 sleeve/진짜 CRISIS specialist).

## 4. 측정·게이트 (실측-only — 불변)

- 자체합성 금지. `build_bt_result` → `audit_bt_result` → `essence_score`(등급 권위 단일).
- 과적합 게이트: OOS_retention≥0.7 → DSR≥0.5 HARD(sweep 만) → placebo(국면셔플 p<0.05) →
  holdout falsification. 이 분할·게이트는 lockbox(폐지)가 아니라 **측정 규율** — 불변.
- SR 2.5 미달 시 정직 표기. n_trials 누적 상향계상.

## 5. PIT · frozen · 거버넌스

- 국면 t-1 lag(C5) · 가중 IS-only · **모듈 frozen** · classifier/forecaster frozen.
- dispatcher = `book_optimize` 래퍼(직접개조 금지 — 개선은 강화 시도로 원장 기록).
- ★**governor 폐지 (v10)** — 구 "governor 정지·book_state 수동" 조항 대체. 종착 =
  Judge(PIT) PASS 후 BOOK(`06_Registry/book/book_registry.json`) 등록, writer
  (`book_registry.R`) 경유 + 도훈 confirm. book-marginal ΔIR≥0.05 는 진단 도구로 강등.
- Production Constraints: long-only/Σw=1/max25/15bps/LIQ2e8/TO≤11 (★v10: 종목별 비중
  상한 폐지). **WT-id 미사용**(2계층 lineage = 강화 원장). 텔레그램 `tg_agent_brief()`,
  표제 `[2계층] …` / `[2계층·강화 n] …`.

## 6. L-code

`mode=strategy_rotation|regime_research` (`stage_artifacts/l_code/<mode>/`). 구 `factor_rotation`
값은 alias 정규화(역사 보존). 강화 시도는 `mode=reinforcement`(RF) — 원장과 이중 기록.

## 참조
- `.claude/skills/strategy-rotation/SKILL.md` · `.claude/skills/reinforce/SKILL.md` ·
  `.claude/rules/{backtest-contract,measurement-graduation,pit,axioms}.md`
- `02_Infrastructure/{contracts/register_module,regime/build_module_performance,portfolio/{module_dispatcher,regime_module_admission}}.R` ·
  `04_Research/factor_rotation/{run_wf_ensemble.R,regime_model_literature_review.md}` ·
  `02_Infrastructure/book/book_registry.R`

## Change log
- 2026-06-05: 신규 (모드정의·2트랙·적재 계약·RCMA 등급무관·실측 게이트·governor 정지).
- 2026-06-12: FR input floor 실행 보강 (quarantine 분리).
- **2026-08-29 v10**: 2계층 재정의(도훈) — 제목·정체성 개정("Factor Rotation Mode"→"전략
  로테이션 2계층") · 논문 온디맨드 착수 · 리서치 1단위 등급화 · 강화 무한(원장 l2) ·
  풀 2단 게이트(grade B+ floor 신설, 등급무관 차용 폐기) · governor 폐지→Judge+BOOK ·
  비중 상한 폐지 반영.
