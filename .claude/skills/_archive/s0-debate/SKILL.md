---
name: s0-debate
description: "S0 3-Round Structured Debate. R1 Opening → R2 Rebuttal → R3 Closing. v55 Consensus 기반(stance/veto/unresolved). Hook 상태 머신 강제. 텔레그램 실시간 중계."
---

## S0 3-Round Debate Protocol (v55 Consensus)

**v55 핵심**: stance(APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT) + veto_flag + critical_concerns/supporting_arguments. 점수제 폐지.
**필수 읽기**: `00_Lawbook/v55_consensus_addendum.md` §1.6.
**상태 머신**: `02_Infrastructure/hooks/s0_enforcer/s0_enforcer.sh`가 모든 라운드 전이를 검증·강제. 위반 = Write block.

### 모드

| 모드 | Debaters | 사용 |
|------|---------|------|
| **Compact 3인** (기본) | Codex Critic + Risk Manager + (Judge 또는 Governor) | 기본값. Academic·Quant는 자동 fact-check Hook로 대체 |
| **Full 5인** | Codex + Risk + Governor + Quant + Academic | `QVEST_DEBATE_MODE=full` 또는 escalate_to_5p fallback |

**Judge vs Governor 선택 (Compact 3번째 자리)**:
- **Judge (Opus)**: 신규 factor/mutation 도입 또는 PIT 경계 판단
- **Governor (Sonnet)**: 기존 family 교체/admission 중심
- 모호 시 Q-Lead가 S0 스폰 전 선택. `stage_artifacts/s0_judge_or_governor_{H_ID}.md` 1줄 기록.

### 에이전트 공통 규칙

- 한글 필수 (arguments, concerns, rebuttals, agreements). 영문 논문명/팩터명/수치만 원문.
- 에이전트 프롬프트: `"모든 arguments, concern, rebuttals, findings는 한글로 작성하세요. 영문 논문명/팩터명/수치는 그대로."`

---

## Phase 1: Scout 가설 설계

1. `.cache/portfolio_gap_vector.json` → sleeve_needs 확인
2. Scout을 plan mode로 스폰 (model=sonnet):
   ```
   Agent(subagent_type: "scout", mode: "plan", model: "sonnet",
         prompt: "S0 가설 설계. gap_vector + conditional_ic_matrix + methodology_active
                  + core_knowledge_base 참조. s0-idea-sourcing skill 준수.
                  가설마다 expected_role, why_now, core_reference, factors, trail 필수.")
   ```
3. Scout ExitPlanMode → plan 파일에 가설.

## Phase 1.5: Scout Plan 브리핑

1. Scout plan 파일 읽기
2. 핵심 요약 (전략명, role, factors, core_reference, 리스크)
3. Telegram `tg_send` "[Scout] S0 가설 브리핑: {전략명}"
4. 사용자 피드백 있으면 반영 → 토론 진입

---

## Round 1: Opening (병렬)

각 debater 독립 초기 평가. 서로 주장 미공개.

### Compact 3인 스폰

```
Claude Agent × 2 (병렬):
  - risk-manager (opus): "S0 Debate R1 Compact. 가설: [...]. 역할: risk_manager.
      L13 Risk Engine 평가. veto 권한: tail_risk.
      출력: stage_artifacts/s0_debate_r1_risk_manager_{H_ID}.json"
  - judge|governor: PIT 경계(judge) 또는 admission(governor) 중심. veto: PIT 또는 admission_rule/gap_misaligned.

Codex × 1 (Bash):
  SCOUT_PLAN="..." L_CODE_FINDINGS="..." FAILED_STRATEGIES="..." \
  bash 02_Infrastructure/tools/debate_helpers/run_codex_critic.sh
  → stage_artifacts/s0_debate_r1_codex_critic_{H_ID}.json
```
(Academic·Quant LLM 스폰 금지 — fact-check Hook 자동 트리거)

### Full 5인 스폰 (필요 시)

**모델 라우팅**: Risk Mgr = Opus / Governor, Quant, Academic = Sonnet.
4인 Claude Agent + Codex 1인 Bash. R1 프롬프트에 veto 권한 도메인 명시.

### R1 출력 스키마 (v55)

```json
{
  "role": "risk_manager",
  "stance": "APPROVE_CONDITIONAL",
  "critical_concerns": ["장기 횡보장 기회비용 연 2-3%p"],
  "supporting_arguments": ["D25 tail beta 6대 위기 IC 0.185", "CR05 상관 0.15"],
  "veto_flag": null,
  "s1_gate_items": ["S1에서 beta < 0.85 확인 필수"]
}
```

**필드 규칙**:
- `stance`: APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT
- `critical_concerns` + `supporting_arguments` 합산 ≥ 1건 (Codex 제외)
- `veto_flag`: null 또는 도메인별 (아래 매트릭스)
- `s1_gate_items`: S1에서 실측할 empirical 항목 (Codex는 empirical을 반드시 여기로)

**Veto 매트릭스**:

| Debater | veto_flag |
|---------|-----------|
| Risk Manager | `tail_risk` |
| Academic | `mechanism` |
| Quant | `PIT` / `kr_empirical_hard_fail` |
| Governor | `admission_rule` / `gap_misaligned` |
| Judge (Compact만) | `PIT` |
| Codex | 없음 (flag만 제시, 집계 제외) |

### R1 enforcer 강제

- `stance` ∈ 4개 값 필수
- `critical_concerns` + `supporting_arguments` 합산 ≥ 1
- `veto_flag` 키 존재 (null도 명시)
- 상태: IDLE 또는 R1_IN_PROGRESS만 Write 허용

**R1 Complete (N/N 제출) 자동 동작**:
1. 상태 R1_COMPLETE 전이
2. `/tmp/s0_debate_r1_summary_{H_ID}.md` 요약본 생성 (~500T, Block E)
3. Compact mode: `academic_factcheck.sh` + `quant_factcheck.sh` nohup 스폰
4. Codex R2 Verify background 스폰 → `stage_artifacts/r2_codex_verdict_{H_ID}.json`
5. Q-Lead에게 R2 시작 지시 (hookSpecificOutput)
6. Telegram: 진행률 bar + stance tally + veto count

---

## Transcript 컴파일

Q-Lead가 R1 결과를 `stage_artifacts/s0_debate_transcript_{H_ID}.json`으로 병합. **토큰 절감**: R2 스폰 시 원본 대신 `/tmp/s0_debate_r1_summary_{H_ID}.md` 요약본(~300T) 주입.

```json
{
  "hypothesis_id": "H_1643", "mode": "compact | full",
  "round_1": [
    {"role": "codex_critic", "stance": "...", "critical_concerns": [...], ...},
    ...
  ]
}
```

---

## Round 2: Rebuttal (병렬, R1 요약 주입)

각 debater가 다른 debaters R1 stance/논거 읽고 반응.

### R2 출력 스키마 (v55)

```json
{
  "role": "risk_manager",
  "r1_stance": "APPROVE_CONDITIONAL",
  "r1_veto_flag": null,
  "stance_change": "DOWNGRADED",
  "new_stance": "REVISE",
  "stance_change_reason": "Quant 분석에서 D25 2005년 이전 결측 → PIT 가능 구간 축소...",
  "veto_flag": null,
  "addressed_concerns": [
    {"by": "academic", "concern": "Ang(2006) KR 약세 우려가 Carhart(1997) cross-val로 부분 해소"}
  ],
  "unresolved": [{"with": "quant", "point": "D25 평상시 drag — S1 walk-forward IC 필요"}]
}
```

**필드 규칙**:
- `stance_change` ∈ {UNCHANGED, UPGRADED, DOWNGRADED}
- `new_stance` ∈ 4개 stance (R3 미진행 시 final)
- `stance_change != UNCHANGED` → `stance_change_reason` 50자+ 필수
- `unresolved` ≥ 1건 (없으면 "토론 없는 R2 = 반복" → block)

### R2 Complete 자동 동작

1. **SKIP_R3 조건**: compact mode stance 만장일치 + veto 무변동 + 3인 응답 | full mode 전원 UNCHANGED + veto 변동 0 → VERDICT_READY
2. **R3_NEEDED 조건**: 누구든 stance_change ≠ UNCHANGED 또는 veto 변동 → 해당 role 재소환
3. Telegram: R2 tally + veto 변동 list

---

## Round 3: Closing (조건부)

R2에서 `stance_change != UNCHANGED` 또는 veto 변동인 debater만 재소환. 없으면 생략.

```json
{"role": "risk_manager",
 "final_stance": "APPROVE_CONDITIONAL", "final_veto_flag": null,
 "closing_statement": "Quant R2 지적 수용. S1 walk-forward gate 조건 공유..."}
```
`closing_statement` ≥ 150자. 전원 R3 완료 시 VERDICT_READY.

---

## Verdict (Q-Lead)

Q-Lead가 stance 합의 집계. **점수 합산 폐지**.

### 사전 체크

- `stage_artifacts/r2_codex_verdict_{H_ID}.json` 존재 필수 (enforcer가 block)
- 긴급 시 `QVEST_SKIP_CODEX_R2=1` 우회 (감사 로그)
- Codex R2 요약을 `codex_cross_check` 필드로 기입

### Verdict 결정 규칙 (`s0_verdict_router.sh` 기준)

**Full 5인**:
- veto ≥ 2 동의 (Codex 제외) → REVISE (도메인 충돌 시 REJECT)
- APPROVE ≥ 4 && veto 0 → APPROVE
- REJECT ≥ 3 → REJECT
- (APPROVE + APPROVE_CONDITIONAL) ≥ 3 && REJECT ≤ 1 → APPROVE_CONDITIONAL
- 그 외 → REVISE

**Compact 3인**:
- veto ≥ 1 (Risk or Judge/Governor) → REVISE (즉시 block)
- 3/3 APPROVE → APPROVE (tier=strong)
- REJECT ≥ 2 → REJECT
- (APPROVE + APPROVE_CONDITIONAL) ≥ 2 && REJECT 0 → APPROVE_CONDITIONAL
- 그 외 → REVISE

**Consensus tier**:
- `UNANIMOUS` — 전원 동일 stance + veto 변동 0
- `MAJORITY` — APPROVE/COND ≥ 과반
- `MINORITY` — REVISE 우세
- `DEADLOCK` — 동수 또는 veto 충돌

**KR-Inverse**: Quant `veto_flag = "kr_empirical_hard_fail"` = veto 1건 집계. Compact mode에서 즉시 REVISE.

### S0_VERDICT 스키마 (v55)

```json
{
  "hypothesis_id": "H_1643", "mode": "compact",
  "verdict": "APPROVE_CONDITIONAL", "consensus_tier": "MAJORITY",
  "consensus_tally": {"approve": 1, "approve_conditional": 2, "revise": 0, "reject": 0,
                       "veto_count": 0, "veto_flags": []},
  "transcript": {"rounds": [{"round": 1, ...}, {"round": 2, ...}]},
  "final_stances": {
    "codex_critic": {"r1": "APPROVE_CONDITIONAL", "final": "APPROVE_CONDITIONAL",
                      "stance_change": "UNCHANGED", "veto_flag": null},
    "risk_manager": {"r1": "APPROVE", "final": "APPROVE",
                      "stance_change": "UNCHANGED", "veto_flag": null},
    "judge":        {"r1": "APPROVE_CONDITIONAL", "final": "APPROVE_CONDITIONAL",
                      "stance_change": "UNCHANGED", "veto_flag": null}
  },
  "consensus_points": ["defense family 필요성 전원 동의", "C11 데이터 시간축 검증 필수"],
  "unresolved_disputes": ["D25 평상시 drag — S1 walk-forward에서 실측"],
  "codex_cross_check": "Codex R2: PIT 설계 검증 PASS. kill scenario #2는 S1 gate item 이관.",
  "debaters": [
    {"agent_id": "codex_critic_...", "role": "codex_critic", "stance": "...", "veto_flag": null, "findings": "..."},
    {"agent_id": "risk_manager_...", "role": "risk_manager", "stance": "...", "veto_flag": null, "findings": "..."},
    {"agent_id": "judge_...",        "role": "judge",        "stance": "...", "veto_flag": null, "findings": "..."}
  ]
}
```

**enforcer 강제 (v55)**:
- VERDICT_READY 상태만 Write (R2 미완료 시 block)
- `transcript.rounds` ≥ 2 (R1+R2 최소)
- `final_stances`에 N인 전원 r1/final/stance_change/veto_flag
- `consensus_tally` 필드 전수 + 합 = N (compact 3 / full 5)
- `consensus_tier` ∈ 4개 값
- `debaters` 배열 = N (필수 역할 전원)
- `consensus_points` ≥ 1 + `unresolved_disputes` 키 존재
- 점수(total_score/final_scores) 폐기 (있어도 통과)

### 라우팅 (`s0_verdict_router.sh`)

- APPROVE → STR 번호 할당 → Forge inbox TODO_S1
- APPROVE_CONDITIONAL → 동일 + s1_gate_items 전달
- REVISE → Scout 재스폰 + critical_concerns 전달 (최대 3회)
- REJECT → 폐기 로그 + 새 가설 탐색

---

## Stance 결정 기준 (도메인별)

### Risk Manager — stance + (veto: tail_risk)
체크: tail_risk / kill_scenario / beta_orthogonality / mdd_contribution / regime_vulnerability
- 5 OK → APPROVE / 1~2 S1 실측 가능 → APPROVE_CONDITIONAL / 3+ 우려 or EVT 위반 → REVISE / tail 구조적 해소 불가 → veto=tail_risk + REJECT

### Academic — stance + (veto: mechanism)
체크: peer_review / mechanism_align / korea_evidence / substantive_cite / time_decay
- 1편+ 피어리뷰 + 메커니즘 + KR 실증 → APPROVE / 메커니즘 약하나 ML/통계 trail 보강 → APPROVE_CONDITIONAL / 메커니즘 논리 결함 → veto=mechanism + REVISE/REJECT
- ML/KR-original trail은 "논문 없음"만으로 REJECT 금지

### Quant — stance + (veto: PIT | kr_empirical_hard_fail)
체크: icir_check / internal_corr / c19_corr / defense_ic / data_avail / kr_empirical_check
- 전수 PASS → APPROVE / 1건 borderline → APPROVE_CONDITIONAL / C1~C15 위반 → veto=PIT + REVISE/REJECT
- VALIDATED_HARD_FAIL L-code 일치 → veto=kr_empirical_hard_fail + REVISE (L-132/133/134/136/139/140/154/160/161/165/166)

### Governor — stance + (veto: admission_rule | gap_misaligned)
체크: gap_alignment / role_match / family_saturation / marginal_contribution / implementation_feasibility
- 정합 + 비포화 → APPROVE / 한계기여 borderline → APPROVE_CONDITIONAL / admission v3.5.x 위반 → veto=admission_rule / gap 어긋남 → veto=gap_misaligned

### Judge (Compact 3인 한정) — stance + (veto: PIT)
체크: PIT 경계 / 신규 factor 적격 / lesson_check / hurdle 적용
- PIT 깨끗 → APPROVE / 경계 사례 → APPROVE_CONDITIONAL / PIT 위반 → veto=PIT + REVISE

### Codex Critic — stance만 (veto 없음)
체크: l_code_check / failure_avoidance / cross_model_diversity / structural_risk / kill_scenario
- 회피 + cross-model 동의 → APPROVE / S1 measurable → APPROVE_CONDITIONAL + s1_gate_items / 구조 결함 → REVISE
- empirical은 반드시 `s1_gate_items`로 (stance 결정 근거 금지)
- "논문 없음"만으로 REJECT 금지 (ML/KR-original 허용)

---

## Hook 아키텍처

| Hook | 이벤트 | 역할 |
|------|--------|------|
| `s0_enforcer/s0_enforcer.sh` (via shim `s0_debate_enforcer.sh`) | PostToolUse[Write] | 상태 머신 dispatcher — R1/R2/R3/VERDICT 전이 강제 + 텔레그램 중계 + codex r2 spawn |
| `s0_enforcer/state_machine.py` | (called by dispatcher) | 스키마 validation + 상태 전이 + R1 summary 빌드 (단일 python, 22+ heredoc 통합) |
| `s0_debate_guard.sh` | PreToolUse[Agent] | 단일 에이전트 다역할 시뮬레이션 차단 |
| `s0_verdict_router.sh` | FileChanged[S0_VERDICT_*] | APPROVE/REVISE/REJECT 라우팅 |
