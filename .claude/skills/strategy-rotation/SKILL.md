---
name: strategy-rotation
description: 2계층 — 전략 로테이션 리서치 (v10). 1계층이 생산한 B등급 이상 전략 모듈을 소비해 어느 시장 상황에서나 통하는 한국 특화 전천후(all-weather) 모델을 설계하는 심화 계층. 논문 온디맨드 착수 → 리서치 1단위(국면엔진×배분규칙×WF 실측)마다 essence 등급(A/B/C/F) → 미달 시 강화 무한(국면식별/전략결합, reinforce_ledger_l2) → A 달성 시 Judge(PIT) → BOOK 등록. 모듈 풀 = 계약 floor + essence grade ∈ {A,B} 2단 게이트(RCMA는 그 위 국면조건부 배치 심사). governor 폐지.
---

# 2계층 — 전략 로테이션 리서치 (v10 2026-08-29 재정의)

**정체성**: 1계층(팩터전략 리서치)이 생산한 **B등급 이상 전략**을 국면 조건부로 배합해
**어느 시장 상황에서나 통하는 전략**(한국 특화 전천후 모델 — 최종 목표)을 만드는 심화
계층. 모듈을 생산하지 않고 소비하는 meta-layer. 산출 = `FR_XXXX` 운용체계.
페르소나 = `02_Infrastructure/docs/rules/quant-identity.md`.

## 0. 논문 기반 착수 (v10 — 아이디어는 논문에서 시작한다)

1계층과 마찬가지로 **최초 아이디어 설계는 논문에서 시작**한다. 단 무인 수집기
(paper_recharge)는 1계층 전용 — 2계층은 **세션 온디맨드 검색**:
1. `mcp__jina__search_arxiv` / `mcp__paper-search__search_*` (SSRN 포함)로 국면식별·
   regime-switching allocation·전략결합 방법론 논문 검색 → **원문 링크 확보**.
2. Step 0 지식 대조(아래) 통과 후 착수. **모든 수치 의사결정(국면 정의·λ·배분규칙
   파라미터)에 근거 논문 원문 링크 필수** — 파생 결정은 뿌리 논문 제시. **한 논문
   매몰 금지**(교차 논문 ≥2 대조 권장). 하드코딩 금지 — 동적 리서치.
3. 데이터가 없으면 "구현 불가"가 아니라 `06_Registry/data_pipeline_queue.json` 적재
   → 수집 파이프라인 구축 후 재개 (v10 절대 규칙).

## Step 0 — 지식 대조 (의무)

1. `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <keyword>` (단일어로 넓게 —
   `lookup regime`, `lookup allocation`). 동일 서명 기존 시도 있으면 verdict·grade 인용 +
   **차별점 명시 없인 진행 금지**.
2. 모드 L-code grade F 스캔: `stage_artifacts/l_code/{strategy_rotation,factor_rotation,regime_research,ramp}/`.
3. **원장 교훈 주입**: `rf_lessons_digest(2L, "<FR lineage>")` — 무한 모드의 "교훈 지속 주입"(도훈).
4. 기존 실측 교훈 = 1급 강화 소재 (§7 하단 실증 목록).

## 1. 구조 — 1 모드 2 트랙 (유지)

```
2계층 전략 로테이션 리서치
├── Track 1: 레짐엔진 리서치   = 국면 정의 + 사전 예측 강화 (토대 · 학술 SOT §6)
└── Track 2: 배분 리서치       = 모듈 배합 강화 (Track1 국면 소비)
```
진입 `/strategy-rotation <track∈{regime-engine, allocation}>` · `/qvest` 2계층 선택 시 기본 진입.

## 2. 리서치 1단위 (등급 산출의 단위)

**로테이션 규칙 1개 = {국면엔진 사양 + 배분규칙 사양 + `run_wf_ensemble.R` WF 실측 1회}**
→ 산출 5종: FR_XXXX 등재(grade 포함) + essence 등급 + L-code(mode=`strategy_rotation`) +
텔레그램 `[2계층]` + 원장 엔트리.

등급 경로 (권위 = essence 하나): `run_wf_ensemble` → `build_bt_result`(metric_type=
backtested) → `audit_bt_result` → `essence_score`(A/B/C/F) → `register_fr_result` →
`emit_fr_lcode`(mode=`strategy_rotation` — 구 factor_rotation 은 alias 정규화).

## 3. ★모듈 풀 = 2단 게이트 (v10 — "B등급 이상" 도훈 지시)

**①자격 = essence grade ∈ {A, B}** (전략 단위, `grade_basis` = essence 계열 또는
dohoon_mandate) — `build_module_performance.R` 전방 필터(env `QVEST_L2_GRADE_FLOOR`,
기본 `B`; `OFF` = 진단 전용). legacy 무등급 모듈은 **권위 재측정 후 grade 기입 시**
재편입. 풀 축소는 결함이 아니라 지시의 귀결 — 첫 실행에서 풀 크기를 보고할 것.
**②배치 = RCMA 6기준** (`regime_module_admission.R` — 유지): B+ 풀 **위에서** 어느
국면에 얼마나 쓸지의 국면조건부 심사. 근거 = v2.1 A/B 실측 교훈 "dispatcher RP-앵커는
IR 무관이라 admission 이 유일한 품질 게이트" — 등급 floor 만으로는 국면별 표본·유의성
검증이 사라진다.
- ★**방어형 경로 (도훈 지시 2026-09-04 — 등급 floor 와 병렬)**: 등급이 B 미만이어도
  **방어형**이면 풀에 편입한다. 방어형 = **벤치마크가 실제로 마이너스를 기록한 국면에서
  아웃퍼폼한 전략**(국면엔진 라벨 기준 아님 — 라벨은 이 시스템의 병목이고, 라벨 품질이
  방어형 판정의 상한을 정하면 전략이 아니라 계기를 재게 된다).
  판정 = `02_Infrastructure/contracts/defensive_score.R::ds_score`(하락월 초과수익 > 0
  ∧ t ≥ 1.5 ∧ 적중률 ≥ 0.5 · 수치 정본 `06_Registry/defensive_score.json`).
  배선 = `build_module_performance.R` (`QVEST_L2_DEFENSIVE_ROUTE=OFF` 로 해제).
  편입 경로는 산출물에 `defensive_specialist` 로 라벨링돼 등급 편입과 구분된다.
  실측 근거(2026-09-04, 380건): 방어형 184건 중 **B 이상 0건** — 전부 C/F.
  하락월 초과 +1.81% vs 비방어형 −0.12%, 벤치 −10% 이하에서 +5.64% vs −0.43%
  (심도에 따라 우위가 커지는 볼록성 = 선형 베타가 아니라 실제 방어 기전).
  ⇒ 아래 "F-overall specialist 풀 부적격"을 **방어형에 한해** 되돌린다.
- ★구 "등급무관 specialist 차용"(2026-06-10 mandate) 조항은 **본 v10 지시("B등급
  이상의 전략들을 활용")가 대체** — 폐기. F-overall specialist 는 풀 부적격
  (**단 위 방어형 경로는 예외**). 그 재료가 아깝다면 1계층 강화로 B 이상을 먼저
  만든 뒤 편입하는 것도 경로다.
- 계약 floor 는 불변: `register_module()` — contract_pass ∧ metric_type=backtested ∧
  frozen ∧ provenance 4종. floor 미충족은 quarantine. 신규 등재분은 `essence_grade` +
  `grade_basis` 기록 의무.

## 4. 강화 프로세스 (★무한 — A등급까지)

리서치 1단위가 A 미달(B/C/F)이면 강화 착수. **시도 횟수 제한 없음** — 교훈을 지속
주입받으며 A 달성까지 무한 리서치 모드(도훈). 원장 = `06_Registry/reinforce_ledger_l2.json`
(`reinforce_ledger.R` — layer=2, keyword_axis 2축):
- **`regime_identification`** — 국면 식별 강화: SJM/HMM/BOCPD/forecaster·신규 축·
  label gate 개선. 근거 논문 필수 (Bemporad 2018 / Nystrup 2021 / Shu-Mulvey 2024 계열).
- **`strategy_combination`** — 전략 결합 방법론: dispatcher 개선·Black-Litterman
  (Shu-Mulvey 2024, arXiv 2410.14841)·top-k 제한·regime-conditional shrinkage·HRP.
절차 = `.claude/skills/reinforce/SKILL.md` (rf_append_attempt — root_papers 없으면 거부).
매 시도 = 리서치 1단위 전체(등급·발송·원장·L-code 전부).

**1급 강화 소재 (기존 실측 교훈 — 재발명 금지, 여기서 출발)**:
- softmax 압축 결함: n=21 모듈에서 국면신호 91% 소실(입력 5.2×→출력 1.40×), λ/τ/k0 는
  5-10 모듈 기준 보정(`module_dispatcher.R:47-70`). B+ floor 로 풀이 줄면 이 결함 지형이 바뀐다 — 재측정부터.
- FR_001/FR_002 둘 다 grade C + **OOS retention 음수**(−0.146/−0.702) — OOS 열화가 1차 적수.
- RCMA v2.0/v2.1 기각 교훈: 소표본 위기군 셀 IR 은 대부분 운. rare_mode OFF 유지.
- SJM PoC: churn 33.2%→7.1%·위기 적중 94~100%인데 **앙상블 OOS SR 로버스트 이득 無**
  — 천장은 입력(직교 슬리브)이 결정. B+ 풀 재편 후 재측정 가치.

## 5. A등급 → Judge → BOOK (v10 종착)

essence Grade A 확정 시에만: ① Judge(PIT 전담) 스폰(`.claude/agents/judge.md` —
2계층 추가 축: regime 신호 t-1(C5)·`regime_label_gate` 통과·publisher append-only
무결성) → ② `judge_verdict.json` pit_pass=true → ③ **BOOK 등록**
(`register_book_entry(kind="rotation_rule", fr_id=...)` — 도훈 confirm 수동) →
`rf_record_judge()` 원장 기록. PIT FAIL = 등급 무효 → 수리 후 재측정.
★governor·book_state 는 폐지(v10) — BOOK(`06_Registry/book/book_registry.json`)이 승계.

## 6. Track1 = 학술 기반 (유지 — 국면 정의·예측 강화)

SOT: `04_Research/factor_rotation/regime_model_literature_review.md`. SOTA = Sparse Jump
Model (PoC `02_Infrastructure/regime/regime_jump_model.R` — 실측 §4). 전략 로테이션 정본
= Shu-Mulvey 2024. forecaster 신호: MSM transition + BOCPD + FRED 선행(US-VIX 가 KR 국면
Granger-cause — 1급 feature). **신규 국면축은 문헌 economic-rationale 선존 필수 + 원문 링크.**

## 7. 작동 메커니즘·지표·측정 게이트 (유지)

- Track2 체인: `module_performance.json` → `module_dispatcher.R` → `run_wf_ensemble.R`
  (anchored WF, IS-only 가중, 모듈 frozen, 국면전환 turnover 15bps).
- 합격선: PORT_t 2.95 / DSR 0.5(sweep 만) / OOS_retention 0.7 / Calmar 0.64 HARD ·
  edge_vs_ew > 0 · placebo p<0.05 · TO ≤ 11.0. T1 지표(Kendall τ·Brier·churn) 불변.
- 측정·과적합 게이트: OOS v2 앵커 3분할 · DSR = sweep 만 · placebo · holdout
  falsification (`measurement-graduation.md` §3 정합 — 이건 lockbox 가 아니라 측정 규율).

## 8. 거버넌스·제약

- **모듈 frozen** — 배분만. 모듈 재백테/시그널 수정 금지(1계층 영역).
- **dispatcher = book_optimize 래퍼** — 직접개조 금지(개선은 강화 시도로 — 원장 기록).
- Production Constraints: long-only / Σw=1 / max 25종목 / 15bps / LIQ 2e8 / TO ≤ 11.0
  (★v10: 종목별 비중 상한 폐지).
- WT-id 미사용(2계층은 WorkTask lifecycle 밖 — 원장이 lineage 를 진다).
  텔레그램 `tg_agent_brief()` 단일 진입, 표제 `[2계층] 전략 로테이션 — {FR} (등급 {g})` /
  강화는 `[2계층·강화 n]`(무한 — 분모 없음).
- Q-Lead 오케스트레이션 전용 — 측정은 R 체인(AX-008).

## 9. 참조

`.claude/agents/dispatch-orchestrator.md` · `02_Infrastructure/docs/rules/strategy-rotation.md`(거버넌스 상세) ·
`.claude/skills/reinforce/SKILL.md`(강화 절차) · `02_Infrastructure/book/book_registry.R`(BOOK) ·
연구노트 `04_Research/factor_rotation/output/regime_study*.json`
