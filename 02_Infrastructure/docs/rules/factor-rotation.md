# Factor Rotation Mode (Level 1)

**발효**: 2026-06-05 (도훈 mandate). **위반 = AX-002 동급**(실측-only·프로세스 우회 금지).
**SOT**: `.claude/skills/factor-rotation/SKILL.md` (절차). 원본 설계 plan(curious-sauteeing-hippo)은 구 머신 경로라 도달불가 — 설계 내용은 본 rule + SKILL.md에 흡수됨 (2026-06-10).

## 1. 모드 정의 (제3 리서치 모드, Lane3)

신규 알파를 생산하지 않고 **이미 생산된 전략 모듈을 국면조건부로 배합**해 합성 운용체계(`FR_XXXX`)를 만드는 meta-layer. Lane1(QEPM)·Lane2(alpha-search)는 모듈 *생산*, 본 모드는 *소비*.
- **1 모드 2 트랙**: Track1 레짐엔진 리서치(국면 정의+예측) → Track2 배분 리서치(모듈 배합). Track1→Track2 의존.
- **FR_XXXX = 운용체계**(module pool + regime engine ver + 배분정책), STR_XXXX = 개별 모듈(부품). 2계층: book sleeve=STR or FR / FR 내부=국면→모듈.

## 2. 모듈 적재 계약 (표준화, 언어무관)

- 모든 모드 산출물은 **`register_module()`**(`02_Infrastructure/contracts/register_module.R`) 경유 FR-소비 표준형: `04_Research/strategies/{id}/sim_result.rds`(`$DAILY_NAV_DT[Date,Strategy_Ret]`+`$bm_xts`) + `06_Registry/module_catalog.json`. **등급무관 등재**.
- `build_module_performance.R` = grade_a_catalog ∪ module_catalog ∪ 04_Research/strategies/* 전수, **validity 필터(MDD≤90%·|일간ret|≤50%)**. QEPM=native, alpha-search=register_module 경유.

## 3. ★ 모듈 풀 admission = RCMA (overall 등급 아님, 양방향 대칭)

**Grade-A만 쓰지 않는다.** 어느 국면이든 그 국면에서 압도적이면 차용 — F-overall이어도.
- 방어형(CRISIS specialist) + **공격형(RISK_ON/확장 specialist)** 양방향. dispatcher가 강점 국면만 쓰고 약점은 ~0 → overall 등급=잡음, 게이트 부적합. **AX-001**(방어형 조건부 평가) 양방향 일반화.
- **RCMA 6기준** (`regime_module_admission.R` → `module_regime_admission.json`): ① regime_IR≥0.5 OR regime-L 상위⅓ ② n_months≥12(36=high_conf) ③ IS·OOS regime IR 둘 다 양수 ④ |t|=|IR·√(n_m/12)|≥2 ⑤ 경제논리 1줄 ⑥ ΔIR>0(advisory). admitted=①∧②∧③∧④.
- **C2 소표본 셀 완화경로 = 2회 A/B 실측 기각 (2026-06-10, `rare_mode` 영구 OFF)**: 위기군 소표본(n<12) 셀 완화(v2.1 순수완화)도 OOS active SR −0.084→−0.178 악화 — 소표본 셀 측정 IR≈운 + dispatcher RP-앵커가 IR무관 배분(admission=유일 품질게이트). 재도전 트리거 = 직교 sleeve/진짜 CRISIS specialist 등재 시. 상세 = FR SKILL §5.

## 4. 측정·게이트 (실측-only)

- 자체합성 금지. `build_bt_result`(PerformanceAnalytics 표준함수, metric_type=backtested) → `audit_bt_result` → `essence_score`. proxy 손계산·`prod(1+r)`·`cumprod` 금지(`backtest-contract.md`/`answer-principles.md`).
- 과적합 게이트(SR2.5보다 먼저): **OOS_retention≥0.7 → DSR≥0.5 HARD(sweep형 selection만 — 2026-06-10 개정) → placebo(국면셔플 p<0.05) → holdout**. SR2.5 미달 시 정직 표기.
- **n_trials**: 앙상블 grid/축탐색/레짐grid/forecaster/hyper sweep = 다중검정(누적 상향계상, DSR HARD 유지). **단일 가설 A/B·가설주도 순차개선 chain은 DSR 게이트 면제**(`selection_type="chain"`, 자격요건·재분류 = `measurement-graduation §3` 2026-06-10).

## 5. PIT · frozen · 거버넌스

- 국면 t-1 lag, 가중 IS-only, **모듈 frozen**(재백테/시그널 수정 금지), forward 적용. **classifier/forecaster frozen**(국면정의 후행 재튜닝 금지).
- dispatcher = `book_optimize` 정적 QP의 regime-conditional 래퍼(직접개조 금지). 스타일태깅 없음(모듈=STR 직접).
- **governor 정지** — FR_XXXX 게이트 통과해도 `book_state.json` 자동 쓰기 금지. book-marginal ΔIR≥0.05 진단까지만, 실편입=Q-Lead+도훈 수동 confirm(`measurement-graduation §4`).
- Production Constraints: long-only/Σw=1/w∈[0,0.20]/max25/15bps/LIQ2e8/TO≤11. **WT-id 미사용**(WorkTask lifecycle 밖). 텔레그램 `tg_agent_brief()`.

## 6. L-code

`mode=factor_rotation|regime_research` 태깅(`stage_artifacts/l_code/<mode>/`). 다른 모드와 enum 공유 {qepm, alpha_searching, factor_rotation, regime_research}.

## 참조
- `.claude/skills/factor-rotation/SKILL.md` · `.claude/rules/{backtest-contract,measurement-graduation,pit,axioms,research_philosophy}.md`
- `02_Infrastructure/{contracts/register_module,regime/{build_module_performance,regime_engine_research,regime_forecaster},portfolio/{module_dispatcher,regime_module_admission}}.R` · `04_Research/factor_rotation/{run_wf_ensemble,regime_model_literature_review.md}`

## Change log
- 2026-06-05: 신규. 모드정의·2트랙·모듈 적재 계약·RCMA(등급무관 양방향)·실측 게이트·governor 정지. 도훈 mandate 4건.
