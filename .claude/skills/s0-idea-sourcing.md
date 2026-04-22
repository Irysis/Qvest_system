---
name: s0-idea-sourcing
description: "S0 가설 설계 시 적용 — 논문 기반 가설, gap-directed, Prior Art Gate, axiom signals 체크"
hooks:
  PostToolUse:
    - matcher: "Write"
      hooks:
        - type: "prompt"
          if: "Write(stage_artifacts/s0_record_*)"
          prompt: "s0_record JSON 검증. 필수: hypothesis, expected_role, why_now, core_reference, lesson_check, factors, success_criteria, risk_factors. ML 전략(XGBoost/ML 포함)이면 추가: MI prefilter, purged CV, multi-seed 언급. 누락 시 {\"ok\":false, \"reason\":\"missing: [필드]\"}, 모두 있으면 {\"ok\":true}."
---

## 현재 포트폴리오 Gap (자동 주입)
!`python3 -c "import json; d=json.load(open('.cache/portfolio_gap_vector.json')); print(f'SR gap: {d[\"gap\"][\"sharpe_gap\"]:.3f}, Sleeve: {d.get(\"sleeve_needs\",[])}')"`

## 현재 MRS (자동 주입)
!`python3 -c "import pyarrow.parquet as pq; t=pq.read_table('.cache/regime_daily_v2.parquet').to_pandas(); r=t.iloc[-1]; print(f'Date: {r[\"Date\"]}, MRS: {r[\"MRS\"]:.1f}, Axes: {int(r[\"n_axes_firing\"])}/9')"`

## Conditional IC Top 10 (자동 주입)
!`head -11 .cache/conditional_ic_matrix.csv 2>/dev/null || echo "conditional_ic_matrix.csv not found"`
## S0 가설 설계 절차

### Level 0: S0 debate 필수 경유 (절대 규칙, 3중 Hook 강제)
- **S0 가설은 반드시 `/s0-debate` 스킬을 통해 생성**해야 한다.
- Scout이 직접 S0_VERDICT를 작성하거나 TODO_S1을 Forge에 전달하는 것은 **금지**.
- 정규 프로세스: Scout 설계 → Q-Lead `/s0-debate` 호출 → 5인(또는 compact 3인) v55 consensus 토론 → APPROVE/APPROVE_CONDITIONAL 후에만 S1 진행.
- Scout을 Agent로 스폰할 때 S0 가설 관련이면 **반드시 plan mode** 사용.

**3중 Hook 강제 (우회 불가, v55 strict):**
1. **PreToolUse[Agent] — s0_debate_guard.sh**: 단일 Agent에 2개+ 역할 주입 시 차단
2. **PostToolUse[Write] — s0_debate_enforcer.sh**: R1/R2/R3/VERDICT 상태 머신 + stance/veto/unresolved/final_stances/consensus_tally 스키마 검증 (점수제 폐기)
3. **FileChanged — s0_verdict_router.sh**: stance/veto consensus 집계 + 라우팅 (debaters agent_id 중복/역할 누락 시 차단)

단축 경로(Scout 1인 다역할 시뮬레이션)는 3개 Hook 모두에서 탐지됩니다.

### 필수 읽기 순서 (생략 금지)
1. `methodology_memory.md` — L-code 전수. 실패 팩터 재시도 금지.
2. `core_knowledge_base.md` Part A (학술) + Part B (한국 실증)
3. `.cache/portfolio_gap_vector.json` — 현재 gap 확인
4. `.cache/conditional_ic_matrix.csv` — conditional_value 높은 팩터 우선
5. **Axiom signals**: `sg_read_axiom_signals("reuse_penalty")`, `sg_read_axiom_signals("failure_cluster")` — 최근 실패 패턴 회피

### s0_record 필수 필드
`factor_id`, `hypothesis`(50자+), `economic_rationale`(100자+), `prior_art`, `source_reference`, `expected_role`(core_alpha/diversifier/defense), `why_now`(gap 근거), `core_reference`("Part A 참조번호 + 논문명"), `lesson_check`("L-001~L-XXX 확인 결과"), `overlay`="none"

### Prior Art Gate
**Fallback 우선순위 (Gap-3, Session 68 Day 2)** — `06_Registry/factor_registry.json`이 실제로 존재하지 않는다:

1. **Primary**: `06_Registry/factor_registry.json` (존재 시 사용)
2. **Fallback 1**: `06_Registry/strategy_registry.json` (strategy 단위, 222KB, 기존 STR 전수)
3. **Fallback 2**: `06_Registry/idea_registry.json` (idea 단위, 40KB)
4. **Fallback 3**: `04_Research/strategies/STR_*/stage_artifacts/s1_construction_*.json`의 `factor_list` 필드

Scout이 Prior Art Gate 검증 시 1~4 순서로 조회. 1번 부재 시 반드시 2~4 중 1개 이상으로 중복 확인. 검증 방식(strategy_registry의 factor_list 필드 vs 별도 factor_registry 생성)은 Q-Lead 결정에 따름. **현재 정책: strategy_registry fallback 사용**. 추후 factor_registry.json을 build script로 자동 생성할 수 있다(미구현).

### 금지
- ICIR 랭킹 조합, 파라미터 변형, core_knowledge 미참조
- 경로 B(직관→논문) 예산: Explore 버킷 내 30% 이하

### Track 1/2 라우팅
- Track 1 (논문→가설): Part A 참조 필수
- Track 2 (직관→논문): 논문 근거 사후 확보 필수

### Plan Mode 가설 설계 (Q-Lead가 name="scout-s0"로 스폰 시)
1. **read-only 탐색만**: gap_vector, conditional_ic_matrix, methodology_memory, core_knowledge
2. plan 파일에 가설 설계 작성 (코드 실행/파일 수정 금지):
   - factor_id, hypothesis, economic_rationale
   - expected_role (sleeve_needs 일치 필수)
   - why_now (gap 수치 근거)
   - core_reference (피어리뷰 학술 논문 1편+)
   - factors (2~3 팩터 블렌드 권장, **단독 팩터 금지**)
   - **defense 역할 시**: conditional_value > 0 팩터만 (ic_bad > ic_good)
3. ExitPlanMode → **R1 5인 Write로 시작** (s0_debate_enforcer.sh가 상태 머신 구동 + R2 Codex 자동 트리거)

### 토론 자동 체인 (Scout은 대기, v55 Consensus)
- Scout ExitPlanMode 후 Hook이 Q-Lead에 토론팀 스폰을 지시
- Q-Lead가 5인(Codex/Risk/Governor/Quant/Academic) 또는 compact 3인(Codex/Risk/(Judge or Governor)) 병렬 스폰
- 각자 stance(APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT) + veto_flag + critical_concerns + supporting_arguments + s1_gate_items 출력
- s0_verdict_router가 consensus 집계(approve/approve_conditional/revise/reject + veto_count)로 verdict 결정
- **Scout의 가설이 APPROVE를 받으려면 (도메인별 무결점)**:
  - L-code 교훈 전수 확인 + 과거 실패 팩터 미사용 (Codex critical_concerns 0건)
  - ICIR ≥ 0.20 + 내부상관 < 0.5 + C19 상관 < 0.3 (Quant veto: PIT / kr_empirical_hard_fail 없음)
  - tail_risk + kill_scenario + EVT 정합 (Risk veto: tail_risk 없음)
  - 피어리뷰 논문 실질 인용 + 한국시장 적용 근거 (Academic veto: mechanism 없음)
  - gap 정합 + family 비포화 + role admission (Governor veto: admission_rule / gap_misaligned 없음)

### 토론 결과 피드백 (REVISE 시)
- Q-Lead가 S0_VERDICT의 critical_concerns + unresolved_disputes + veto_flags를 피드백으로 전달
- veto/critical_concerns를 모두 addressing하는 revised hypothesis로 재설계 → plan 재제출
- 동일 가설 REVISE 2회 연속 → REJECT 전환 권고

### 등록 (APPROVE 후)
`allocate_str(name_slug)` → `sg_init(factor_id, strategy_id)` → s0_record → Forge TODO_S1
