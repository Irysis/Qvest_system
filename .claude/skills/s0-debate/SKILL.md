---
name: s0-debate
description: "S0 3-Round Structured Debate. R1 Opening → R2 Rebuttal → R3 Closing. v55 Consensus 기반(stance/veto/unresolved). Hook 상태 머신 강제. 텔레그램 실시간 중계."
---

## S0 3-Round Structured Debate Protocol (v55 Consensus)

> **v55 변경사항** (2026-04-19): 점수제(20×5=100) → Consensus(stance/veto) 전환.
> **필수 읽기**: `00_Lawbook/v55_consensus_addendum.md`
> **핵심**: R1/R2 출력은 `score` 대신 `stance` + `critical_concerns` + `supporting_arguments` + `veto_flag`. Codex는 `s1_gate_items`로 empirical gate 이동. R3는 router가 자동 집계.

Q-Lead가 이 skill을 호출하면 Scout 가설 설계 → 5인 3라운드 토론 → 판정 체인이 실행됩니다.
**모든 라운드 전이는 `s0_debate_enforcer.sh` Hook이 기계적으로 강제합니다.**

### Phase 1: Scout 가설 설계

1. `.cache/portfolio_gap_vector.json` 읽기 → sleeve_needs 확인
2. Scout을 **plan mode**로 스폰:
```
Agent(
  subagent_type: "scout",
  mode: "plan",
  prompt: "S0 가설 설계. gap_vector 읽고 sleeve_needs에 맞는 가설 N건 설계.
           conditional_ic_matrix + methodology_memory L-code + core_knowledge_base 참조.
           s0-idea-sourcing skill 준수. 가설마다 expected_role, why_now, core_reference, factors 필수."
)
```
3. Scout이 ExitPlanMode → plan 파일에 가설 작성됨

### Phase 1.5: Scout Plan 브리핑 (텔레그램 + 사용자 보고)

Scout plan 완료 후, 토론 스폰 전에 **Q-Lead가 가설 브리핑을 발송**:

1. Scout plan 파일 읽기
2. 가설 핵심 요약 정리 (전략명, expected_role, factors, core_reference, 주요 리스크)
3. **텔레그램 발송**: `tg_send()` — "[Scout] S0 가설 브리핑: {전략명}" 형식
4. **사용자에게 요약 보고** — 토론 시작 전 가설 내용 공유
5. 사용자 피드백이 있으면 반영 후 토론 진입

---

## 에이전트 공통 규칙 (모든 라운드)

- **한글 필수**: arguments, concern, rebuttals, agreements 등 모든 텍스트 필드는 한글로 작성. 영문 논문명/팩터명/수치는 원문 유지.
- 에이전트 프롬프트에 반드시 포함: `"모든 arguments, concern, rebuttals, findings는 한글로 작성하세요. 영문 논문명/팩터명/수치는 그대로."`

## Round 1: Opening (5인 병렬)

5인 병렬 스폰. 서로의 주장은 보이지 않음. 독립 초기 평가.

### 스폰 (4 Claude + 1 Codex, 전부 run_in_background: true)

```
Claude Agent × 4 (병렬):

1. Risk Manager (subagent_type: "risk-manager"):
   "S0 Debate R1. 가설: [Scout plan 내용].
    역할: risk_manager. L13 Risk Engine 관점 평가.
    출력: stage_artifacts/s0_debate_r1_risk_manager_{H_ID}.json
    스키마: {role, score(0-20), arguments[3건], concern, conditions[]}"

2. Governor (subagent_type: "governor"):
   "S0 Debate R1. 가설: [Scout plan 내용].
    역할: governor. PG0 gap 정합성, family saturation, role admission 평가.
    출력: stage_artifacts/s0_debate_r1_governor_{H_ID}.json"

3. Quant (forge 타입):
   "S0 Debate R1. 가설: [Scout plan 내용].
    역할: quant. ICIR/상관/데이터 가용성 팩트체크. R 코드 실행 가능.
    v54 추가: kr_empirical_check 필수 — methodology_memory.md에서 가설 family의
    VALIDATED_HARD_FAIL L-code 검색 + conditional_ic_matrix.csv에서 KR IC sign/hit rate 확인.
    hard_fail_match 발견 시 kr_empirical_check='hard_fail_match' 태깅 (total -10 penalty 트리거).
    출력: stage_artifacts/s0_debate_r1_quant_{H_ID}.json
    출력 스키마에 kr_empirical_check 필드 추가: 'hard_fail_match'|'partial'|'confirmed'|'no_data'"

4. Academic (scout 타입):
   "S0 Debate R1. 가설: [Scout plan 내용].
    역할: academic. 논문 타당성, 메커니즘, 한국 실증 검증. arXiv/SSRN 검색 가능.
    출력: stage_artifacts/s0_debate_r1_academic_{H_ID}.json"

Codex Critic × 1 (Bash 직접 호출):
  SCOUT_PLAN="가설 요약" L_CODE_FINDINGS="관련 L-code" FAILED_STRATEGIES="실패 목록" \
  bash 02_Infrastructure/hooks/run_codex_critic.sh
  → /tmp/codex_critic_result.json 파싱
  → stage_artifacts/s0_debate_r1_codex_critic_{H_ID}.json으로 저장
```

### R1 출력 스키마 (v55 Consensus)

```json
{
  "role": "risk_manager",
  "stance": "APPROVE_CONDITIONAL",
  "critical_concerns": [
    "장기 횡보장(2014-2016)에서 방어 팩터 기회비용이 연 2-3%p"
  ],
  "supporting_arguments": [
    "D25 tail beta가 6대 위기 구간에서 IC 0.185로 방어력 실증",
    "CR05와 상관 0.15 이하 — 독립 신호원 확보",
    "평상시 IC ≈ 0 → drag 최소화 구조"
  ],
  "veto_flag": null,
  "s1_gate_items": ["S1에서 beta < 0.85 확인 필수"]
}
```

**필드 정의** (v55):
- `stance`: `APPROVE` | `APPROVE_CONDITIONAL` | `REVISE` | `REJECT`
- `critical_concerns`: 재설계 필요한 핵심 문제 (빈 배열 가능)
- `supporting_arguments`: 지지 근거 (빈 배열 가능)
- `veto_flag`: null 또는 도메인별 (아래 매트릭스 참조)
- `s1_gate_items`: S1에서 실측 필요한 empirical 항목 (Codex는 empirical을 **반드시** 여기로)

**Veto 도메인 매트릭스**:
| Debater | veto_flag 가능 값 |
|---------|------------------|
| Risk Manager | `tail_risk` |
| Academic | `mechanism` |
| Quant | `PIT` / `kr_empirical_hard_fail` |
| Governor | `admission_rule` / `gap_misaligned` |
| Codex | **없음** (flag만 제시, veto 집계 제외) |

**하위호환 (일시 허용)**: 구형 `score(0-20)` + `arguments[]` + `concern` 필드도 artifact_validator가 허용하되 v55 경고 로그 발생. 신규 작성은 v55 스키마 필수.

**enforcer 강제 사항:**
- `arguments` 정확히 3건 (!=3 → block)
- `score` 필드 존재 (0-20)
- R1은 IDLE 또는 R1_IN_PROGRESS 상태에서만 Write 허용

**텔레그램 중계:** 각 R1 제출 시 점수 + 주장 요약 + 진행률 발송

### R1 완료 (enforcer 자동 감지)

5/5 제출 시 enforcer가:
1. 상태를 R1_COMPLETE로 전이
2. Q-Lead에 additionalContext 주입: "R1 5/5 완료. Transcript 컴파일 후 R2 시작"
3. 텔레그램 발송: R1 요약
4. **Codex R2 Verify 자동 트리거 (v53 S2.13)** — `run_codex_critic_r2.sh` background 스폰
   - 환경변수: `R1_TRANSCRIPT`(5인 R1 JSON 병합) + `CODEX_R1_RESULT` + `HYP_ID`
   - 출력: `stage_artifacts/r2_codex_verdict_<HYP_ID>.json`
   - VERDICT 작성 시점에 이 파일 존재하지 않으면 **block** (QVEST_SKIP_CODEX_R2=1 로 우회)

---

## Transcript 컴파일 (Q-Lead)

Q-Lead가 5개 R1 결과를 수집하여 하나의 transcript로 컴파일:

```json
// stage_artifacts/s0_debate_transcript_{H_ID}.json
{
  "hypothesis_id": "H_1643",
  "round_1": [
    {"role": "codex_critic", "score": 15, "arguments": [...], "concern": "..."},
    {"role": "risk_manager", "score": 14, "arguments": [...], "concern": "..."},
    {"role": "governor", "score": 16, "arguments": [...], "concern": "..."},
    {"role": "quant", "score": 13, "arguments": [...], "concern": "..."},
    {"role": "academic", "score": 15, "arguments": [...], "concern": "..."}
  ]
}
```

---

## Round 2: Rebuttal (5인 병렬, R1 transcript 주입)

핵심 라운드. 각 에이전트가 **다른 4인의 R1 주장을 보고** 반응.

### 스폰 (R1 transcript 전문을 프롬프트에 주입)

```
Claude Agent × 4 (병렬):

각 에이전트 프롬프트에 포함:
- 가설 내용
- R1 Transcript 전문 (5인 주장 전부)
- "다른 4인의 주장을 읽고 동의/반박하라"
- R2 출력 스키마

출력: stage_artifacts/s0_debate_r2_{role}_{H_ID}.json

Codex Critic R2:
  R1_TRANSCRIPT="$(cat transcript)" CODEX_R1_RESULT="$(cat r1_result)" HYP_ID="H_1643" \
  bash 02_Infrastructure/hooks/run_codex_critic_r2.sh
  → stage_artifacts/s0_debate_r2_codex_critic_{H_ID}.json으로 저장
```

### R2 출력 스키마 (enforcer가 강제)

```json
{
  "role": "risk_manager",
  "r1_score": 14,
  "r2_score": 12,
  "score_changed": true,
  "score_change_reason": "Quant의 데이터 가용성 분석에서 D25가 2005년 이후만 존재",
  "agreements": [
    {"with": "academic", "point": "Ang(2006) downside beta premium이 한국에서 약하다는 지적 유효"}
  ],
  "rebuttals": [
    {"against": "quant", "point": "IC -0.02는 t-stat 0.3으로 0과 구분 불가. drag 아닌 noise", "severity": "major"}
  ],
  "strongest_opposing_argument": "Codex Critic의 kill scenario #2 — 장기 횡보장에서 방어 팩터 기회비용"
}
```

**enforcer 강제 사항:**
- `rebuttals` 1건+ 필수 (없으면 block — "반박 없는 R2")
- `agreements` 1건+ 필수 (없으면 block)
- `score_changed == true`이면 `score_change_reason` 필수 (없으면 block)
- R2는 R1_COMPLETE 또는 R2_IN_PROGRESS 상태에서만 Write 허용

**텔레그램 중계:** 각 R2 제출 시 점수 변동 + 반박 대상 + 핵심 논점 발송

### R2 완료 (enforcer 자동 감지)

5/5 제출 시 enforcer가:
1. R1→R2 점수 변동 확인
2. 전원 |delta| ≤ 4 → VERDICT_READY
3. 누구든 |delta| > 4 → R3_NEEDED
4. additionalContext 주입 + 텔레그램 발송

---

## Round 3: Closing (조건부)

R2에서 점수 변동 > 4점인 에이전트만 재소환. 없으면 생략.

재소환 프롬프트:
```
"R1에서 {r1_score}점, R2에서 {r2_score}점으로 {delta}점 변동.
 R1/R2 전체 transcript를 다시 확인하고 최종 입장을 확정하세요.
 출력: stage_artifacts/s0_debate_r3_{role}_{H_ID}.json"
```

R3 완료 → VERDICT_READY 전이

---

## Verdict (Q-Lead)

Q-Lead가 최종 합산 + 토론 기록 보존.

### 사전 체크: Codex R2 Verdict 필수 (v53 S2.13)
`stage_artifacts/r2_codex_verdict_<HYP_ID>.json` 파일 존재 확인.
- enforcer의 VERDICT hook이 해당 파일 미존재 시 Write **block**
- 우회: `QVEST_SKIP_CODEX_R2=1` (긴급 시만)
- Codex R2 결과 참조 → VERDICT의 `codex_cross_check` 필드에 요약 기입
- 타임아웃 실패 시 `/tmp/codex_critic_r2_stderr.log` 확인


```
total = sum of final scores (5×20 = 100)

# ─── v54 KR-Inverse Penalty (S0 칼리브레이션) ───
# 가설 family가 VALIDATED_HARD_FAIL L-code(L-160/L-161/L-154 등)와
# 동일 family + 동일 방향이면 total -= 10 (절대 적용, 점수 보정 후 판정)
# 예: momentum family 가설인데 L-161 KR momentum inverse VALIDATED_HARD_FAIL → -10
# 적용 조건: debaters 중 quant role의 kr_empirical_check == "hard_fail_match"

if (risk_manager.final <= 4 || quant.final <= 4) → REJECT (특수 규칙)
else if (total >= 75) → APPROVE
else if (total >= 70) → APPROVE_CONDITIONAL (조건 명시)  # v54: 60→70 상향
else if (total >= 60) → BORDERLINE_REVISE (v54 신설: 60-69 borderline, 재설계 + 보강 요구)
else if (total >= 40) → REVISE (Scout에 피드백 → Phase 1 복귀)
else → REJECT (가설 폐기)
```

**v54 BORDERLINE_REVISE (60-69점):**
- APPROVE_CONDITIONAL과 REVISE 사이 신설 구간
- Scout에게 구체적 피드백 전달: 어떤 role이 감점했고 무엇을 보강해야 하는지
- 동일 가설 BORDERLINE 2회 연속 시 REJECT 전환 권고
- `s0_verdict_router.sh`가 이 범위를 탐지하여 라우팅

### S0_VERDICT 스키마 (enforcer가 강제)

```json
{
  "hypothesis_id": "H_1643",
  "verdict": "APPROVE_CONDITIONAL",
  "total_score": 71,
  "transcript": {
    "rounds": [
      {"round": 1, "entries": [...]},
      {"round": 2, "entries": [...]}
    ]
  },
  "final_scores": {
    "codex_critic": {"r1": 15, "final": 14, "delta": -1},
    "risk_manager": {"r1": 14, "final": 12, "delta": -2},
    "governor": {"r1": 16, "final": 17, "delta": 1},
    "quant": {"r1": 13, "final": 13, "delta": 0},
    "academic": {"r1": 15, "final": 15, "delta": 0}
  },
  "consensus_points": ["defense family 필요성 전원 동의", "C11 데이터 시간축 검증 필수"],
  "unresolved_disputes": ["D25 평상시 drag 여부 — S1에서 실증 필요"],
  "debaters": [
    {"agent_id": "codex_critic_...", "role": "codex_critic", "score": 14, "findings": "..."},
    {"agent_id": "risk_manager_...", "role": "risk_manager", "score": 12, "findings": "..."},
    {"agent_id": "governor_...", "role": "governor", "score": 17, "findings": "..."},
    {"agent_id": "quant_...", "role": "quant", "score": 13, "findings": "..."},
    {"agent_id": "academic_...", "role": "academic", "score": 15, "findings": "..."}
  ]
}
```

**enforcer 강제 사항:**
- VERDICT_READY 상태에서만 Write 허용 (R2 미완료 시 block)
- `transcript.rounds` 2개+ (R1+R2 최소)
- `final_scores`에 5인 전원 r1/final/delta 존재
- `debaters` 5건 + 5역할 전부 포함
- `consensus_points` + `unresolved_disputes` 존재

### 라우팅 (s0_verdict_router.sh — 유지)

APPROVE → STR 번호 할당 → Forge inbox TODO_S1
REVISE → Scout 재스폰 + 피드백 (최대 3회)
REJECT → 폐기 로그 + 새 가설 탐색

---

## 채점 Rubric (각 에이전트 0-20점, 5항목×4점)

**Risk Manager:** tail_risk(4) + kill_scenario(4) + beta_orthogonality(4) + mdd_contribution(4) + regime_vulnerability(4)
**Governor:** gap_alignment(4) + role_match(4) + family_saturation(4) + marginal_contribution(4) + implementation_feasibility(4)
**Codex Critic:** l_code_check(4) + failure_avoidance(4) + banned_factor(4) + lesson_check(4) + structural_risk(4)
**Quant (v54 확장):** icir_pass(3) + internal_corr(3) + c19_corr(3) + defense_ic(3) + data_avail(4) + **kr_empirical_check(4)** = ceiling 20
**Academic:** peer_review(4) + mechanism_align(4) + korea_evidence(4) + substantive_cite(4) + time_decay(4)

### v54 Quant kr_empirical_check 채점 기준 (4점 만점)

| 점수 | 조건 |
|------|------|
| **-10 (penalty)** | 가설 메커니즘이 VALIDATED_HARD_FAIL L-code(L-160/L-161/L-154 등)와 **동일 family + 동일 방향**으로 직접 상충. KR-Inverse Penalty Rule 적용. `kr_empirical_check: "hard_fail_match"` 태깅 → total에서 -10 절대 차감 |
| **0** | 가설 family가 VALIDATED_HARD_FAIL과 동일하나 방향은 다름 (예: momentum inverse L-code가 있는데 reversal 가설). 충돌 가능성 있으나 penalty 미적용 |
| **+2** | KR 10년+ IC sign이 가설 방향과 일치하나 Hit Rate < 55%. 또는 부분적 실증만 존재 |
| **+4** | KR 10년+ IC sign 일치 + Hit Rate >= 55%. 한국시장 실증 완전 확인 |

**채점 절차:**
1. `methodology_memory.md`에서 가설 family 관련 VALIDATED_HARD_FAIL L-code 검색
2. 해당 L-code의 tags에 family명 포함 여부 확인
3. `.cache/conditional_ic_matrix.csv`에서 가설 factor의 KR IC sign + hit rate 조회
4. **hard_fail_match 판정 시**: Quant score에 4점 정상 채점 후, **total 합산 단계에서 -10 별도 차감** (Quant 개인 score는 0-20 범위 유지)

**VALIDATED_HARD_FAIL L-code 참조 목록 (v54 기준):**
- L-160: Defense IC-Return decoupling (family: defense)
- L-161: KR momentum inverse (family: momentum)
- L-154: Low-beta BAB standalone fail (family: defense)
- L-132/L-135: Value EP standalone fail (family: value, AX-003)
- L-133/L-134/L-139: Quality profitability standalone fail (family: quality_profitability, AX-004)
- L-136/L-140: Defense low-beta/Q07+D25 fail (family: defense, AX-005)

---

## Hook 아키텍처

| Hook | 이벤트 | 역할 |
|------|--------|------|
| `s0_debate_enforcer.sh` | PostToolUse[Write] | **상태 머신** — R1/R2/R3/VERDICT 전이 강제 + 텔레그램 중계 |
| `s0_debate_guard.sh` | PreToolUse[Agent] | 단일 에이전트 다역할 시뮬레이션 차단 (intent 이중 조건) |
| `s0_verdict_router.sh` | FileChanged[S0_VERDICT_*] | APPROVE/REVISE/REJECT 라우팅 |
