---
name: s0-debate
description: "S0 3-Round Structured Debate. R1 Opening → R2 Rebuttal → R3 Closing. v55 Consensus 기반(stance/veto/unresolved). Hook 상태 머신 강제. 텔레그램 실시간 중계."
---

## S0 3-Round Structured Debate Protocol (v55 Consensus + v6 Compact Mode)

> **v55 변경사항** (2026-04-19): 점수제(20×5=100) → Consensus(stance/veto) 전환.
> **v6 Compact Mode** (2026-04-19 APPROVED): 5인 → 3인 토론 허용 (`QVEST_DEBATE_MODE=compact`). Academic·Quant는 자동 fact-check Hook 대체.
> **필수 읽기**: `00_Lawbook/v55_consensus_addendum.md` §1.6 Compact Mode + `00_Lawbook/v6_amendment_debate_compact.md`
> **핵심**: R1/R2 출력은 `score` 대신 `stance` + `critical_concerns` + `supporting_arguments` + `veto_flag`.

Q-Lead가 이 skill을 호출하면 Scout 가설 설계 → 3인 또는 5인 라운드 토론 → 판정 체인이 실행됩니다.
**모든 라운드 전이는 `s0_debate_enforcer.sh` Hook이 기계적으로 강제합니다.**

## 모드 선택 (Session 68 Day 2~)

| 모드 | Debater | 사용 시점 |
|------|---------|----------|
| **Compact 3인** (기본 — 토큰 절감) | Codex Critic + Risk Manager + (Judge 또는 Governor) | `QVEST_DEBATE_MODE=compact` 또는 default. Shadow mode 5회 통과 후 권장. |
| **Full 5인** (기존) | Codex + Risk + Governor + Quant + Academic | Shadow 기간 + escalate_to_5p fallback 시. `QVEST_DEBATE_MODE=full` 강제 가능 |

**Judge vs Governor 선택 규칙 (Compact Mode 3번째 자리)**:
- **Judge (Opus)**: 가설이 **신규 factor/mutation** 도입 또는 **PIT 경계 판단** 필요
- **Governor (Sonnet)**: 가설이 **기존 family 교체/admission** 중심
- 모호 시 Q-Lead가 S0 스폰 전 선택. `stage_artifacts/s0_judge_or_governor_{H_ID}.md`에 1줄 기록.

**Academic·Quant Fact-Check Hook (Compact Mode 자동 실행)**:
- R1_COMPLETE 시점에 `s0_debate_enforcer.sh`가 자동으로 `academic_factcheck.sh` + `quant_factcheck.sh` nohup 스폰
- 결과: `stage_artifacts/{academic|quant}_factcheck_{H_ID}.json`
- R2 스폰 시 3인 debaters 프롬프트에 fact-check 요약(~200T) 주입
- Hook 2건 이상 실패 → 자동 `escalate_to_5p` (Academic·Quant LLM 1회 스폰 복구)

### Phase 1: Scout 가설 설계

1. `.cache/portfolio_gap_vector.json` 읽기 → sleeve_needs 확인
2. Scout을 **plan mode**로 스폰 (Sonnet 사용 — 토큰 절감):
```
Agent(
  subagent_type: "scout",
  mode: "plan",
  model: "sonnet",
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

### 스폰 모드별

#### Compact 3인 (기본 — v6 Amendment)
```
Claude Agent × 2 (병렬):
1. Risk Manager (subagent_type: "risk-manager", model: "opus"):
   "S0 Debate R1 (Compact Mode). 가설: [...]. 역할: risk_manager. L13 Risk Engine 평가.
    출력: stage_artifacts/s0_debate_r1_risk_manager_{H_ID}.json (v55 스키마)"

2. Judge 또는 Governor (선택 규칙에 따라):
   - Judge (subagent_type: "judge", model: "opus") — PIT 경계 + 신규 factor 판단 중심
   - OR Governor (subagent_type: "governor", model: "sonnet") — admission + gap 중심
   "S0 Debate R1 (Compact Mode). 가설: [...]. 역할: judge|governor.
    출력: stage_artifacts/s0_debate_r1_{judge|governor}_{H_ID}.json"

Codex Critic × 1 (Bash):
  SCOUT_PLAN="..." L_CODE_FINDINGS="..." FAILED_STRATEGIES="..." \
  bash 02_Infrastructure/hooks/run_codex_critic.sh
  → stage_artifacts/s0_debate_r1_codex_critic_{H_ID}.json

(Academic·Quant LLM 스폰 금지 — fact-check Hook이 자동 대체)
```

#### Full 5인 (기존 + shadow mode 병행 시)
**모델 라우팅**: Risk Manager = Opus (R3 Closing 책임) / Governor, Quant, Academic = Sonnet (토큰 절감). Agent tool `model` parameter로 지정.

```
Claude Agent × 4 (병렬, v55 Consensus 스키마):
공통 출력 스키마: {role, stance, critical_concerns[], supporting_arguments[], veto_flag, s1_gate_items[]}

1. Risk Manager (subagent_type: "risk-manager", model: "opus"):
   "S0 Debate R1 (v55). 가설: [Scout plan 내용].
    역할: risk_manager. L13 Risk Engine 관점 평가. veto 권한: tail_risk.
    출력: stage_artifacts/s0_debate_r1_risk_manager_{H_ID}.json"

2. Governor (subagent_type: "governor", model: "sonnet"):
   "S0 Debate R1 (v55). 가설: [Scout plan 내용].
    역할: governor. PG0 gap 정합성, family saturation, role admission 평가.
    veto 권한: admission_rule, gap_misaligned.
    출력: stage_artifacts/s0_debate_r1_governor_{H_ID}.json"

3. Quant (forge 타입, model: "sonnet"):
   "S0 Debate R1 (v55). 가설: [Scout plan 내용].
    역할: quant. ICIR/상관/데이터 가용성 팩트체크. R 코드 실행 가능.
    veto 권한: PIT, kr_empirical_hard_fail.
    KR empirical check: methodology_memory.md에서 가설 family의 VALIDATED_HARD_FAIL L-code 검색
    + conditional_ic_matrix.csv에서 KR IC sign/hit rate 확인.
    가설 family + 방향이 VALIDATED_HARD_FAIL과 일치하면 veto_flag='kr_empirical_hard_fail' 발동.
    출력: stage_artifacts/s0_debate_r1_quant_{H_ID}.json"

4. Academic (scout 타입, model: "sonnet"):
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

**v55 strict (2026-04-19~)**: `score` 필드는 폐지. 구형 `score(0-20)` 단독 입력은 enforcer가 block. 점진 마이그레이션 시 stance + score 병기는 허용 (score는 무시).

**enforcer 강제 사항 (v55):**
- `stance` 필드 필수 (APPROVE/APPROVE_CONDITIONAL/REVISE/REJECT 중 하나)
- `critical_concerns` + `supporting_arguments` 합산 1건 이상 (Codex 제외)
- `veto_flag` 키 존재 (값은 null 또는 도메인 매트릭스 enum)
- R1은 IDLE 또는 R1_IN_PROGRESS 상태에서만 Write 허용

**텔레그램 중계:** 각 R1 제출 시 stance + veto + 진행률 발송

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

**Block E 자동화 (2026-04-19)**: R1 완료 시 `s0_debate_enforcer.sh`가 `/tmp/s0_debate_r1_summary_{HYP_ID}.md` 요약본(~500T)을 자동 생성. R2 스폰 시 이 요약본 경로를 프롬프트로 주입. 원본 전체 transcript는 `stage_artifacts/s0_debate_transcript_{H_ID}.json`에 별도 저장(아래 구조).

Q-Lead가 R1 결과(3인 또는 5인)를 수집하여 하나의 transcript로 컴파일:

```json
// stage_artifacts/s0_debate_transcript_{H_ID}.json
{
  "hypothesis_id": "H_1643",
  "mode": "compact | full",
  "round_1": [
    {"role": "codex_critic", "stance": "APPROVE_CONDITIONAL", "critical_concerns": [...], "supporting_arguments": [...], "veto_flag": null, "s1_gate_items": [...]},
    {"role": "risk_manager", "stance": "APPROVE", "critical_concerns": [...], "supporting_arguments": [...], "veto_flag": null, "s1_gate_items": [...]},
    {"role": "governor", "stance": "REVISE", "critical_concerns": [...], "supporting_arguments": [...], "veto_flag": "gap_misaligned", "s1_gate_items": []},
    {"role": "quant", "stance": "APPROVE_CONDITIONAL", "critical_concerns": [...], "supporting_arguments": [...], "veto_flag": null, "s1_gate_items": [...]},
    {"role": "academic", "stance": "APPROVE", "critical_concerns": [...], "supporting_arguments": [...], "veto_flag": null, "s1_gate_items": [...]}
  ]
}
```

---

## Round 2: Rebuttal (5인 병렬, R1 transcript 주입)

핵심 라운드. 각 에이전트가 **다른 4인의 R1 주장을 보고** 반응.

### 스폰 (R1 transcript **요약본**을 프롬프트에 주입 — Block E 적용 후)

**토큰 절감 (Block E)**: R1 전체 transcript 대신 Q-Lead가 생성한 **300T 요약본** (`/tmp/s0_debate_r1_summary_{H_ID}.md`)을 주입. 원본 JSON은 `stage_artifacts/s0_debate_transcript_{H_ID}.json`에 보존.

```
Claude Agent × 4 (병렬, 각자 R1과 동일 model):
  - risk_manager: opus / governor: sonnet / quant: sonnet / academic: sonnet

각 에이전트 프롬프트에 포함:
- 가설 내용 (150T)
- R1 요약본 (300T — stance/veto/핵심 논거만. 원본 필요 시 stage_artifacts/ 경로 명시)
- "다른 4인의 stance/논거를 읽고 동의/반박하라"
- R2 출력 스키마

출력: stage_artifacts/s0_debate_r2_{role}_{H_ID}.json

Codex Critic R2:
  R1_TRANSCRIPT="$(cat transcript)" CODEX_R1_RESULT="$(cat r1_result)" HYP_ID="H_1643" \
  bash 02_Infrastructure/hooks/run_codex_critic_r2.sh
  → stage_artifacts/s0_debate_r2_codex_critic_{H_ID}.json으로 저장
```

### R2 출력 스키마 (v55 Consensus, enforcer가 강제)

```json
{
  "role": "risk_manager",
  "r1_stance": "APPROVE_CONDITIONAL",
  "r1_veto_flag": null,
  "stance_change": "DOWNGRADED",
  "new_stance": "REVISE",
  "stance_change_reason": "Quant 데이터 가용성 분석에서 D25 2005년 이전 결측. PIT 가능 구간 축소 → tail_risk 재평가 필요",
  "veto_flag": null,
  "addressed_concerns": [
    {"by": "academic", "concern": "Ang(2006) downside beta premium이 KR에서 약하다는 R1 우려가 Carhart(1997) cross-validation으로 부분 해소"}
  ],
  "unresolved": [
    {"with": "quant", "point": "D25 평상시 drag — S1 walk-forward IC 실측 필요"}
  ]
}
```

**필드 정의** (v55):
- `stance_change`: `UNCHANGED` | `UPGRADED` | `DOWNGRADED`
- `new_stance`: R2 최종 stance (R3 미진행 시 final_stance로 채택)
- `veto_flag`: R2 시점 veto (null 또는 도메인 enum)
- `addressed_concerns`: R1 critical_concerns 중 다른 debater 발언으로 해결된 항목 (빈 배열 가능)
- `unresolved`: 끝까지 풀리지 않는 논점 (1건+ 필수 — VERDICT의 unresolved_disputes로 승계)
- `stance_change_reason`: stance_change != UNCHANGED 시 필수

**enforcer 강제 사항 (v55):**
- `stance_change` ∈ {UNCHANGED, UPGRADED, DOWNGRADED} (누락/오타 → block)
- `new_stance` ∈ {APPROVE, APPROVE_CONDITIONAL, REVISE, REJECT} (누락 → block)
- `unresolved` 1건+ 필수 (없으면 block — "토론 없는 R2 = 반복")
- `stance_change != UNCHANGED` → `stance_change_reason` 50자+ 필수
- R2는 R1_COMPLETE 또는 R2_IN_PROGRESS 상태에서만 Write 허용

**점진 호환 (deprecated, 곧 제거)**: `r1_score`/`r2_score`/`agreements`/`rebuttals` 추가 필드는 무시되며 v55 경고. 신규 작성은 v55 스키마 필수.

**텔레그램 중계:** 각 R2 제출 시 stance_change 화살표 + new_stance + veto + 진행률 발송

### R2 완료 (enforcer 자동 감지)

N/N 제출 시 enforcer가:
1. R1 stance vs R2 new_stance 비교 + veto_flag 변동 확인
2. **VERDICT_READY 조건**: 전원 stance_change == UNCHANGED && veto 변동 0 (compact: stance 만장일치 시 자동)
3. **R3_NEEDED 조건**: 누구든 stance_change != UNCHANGED OR veto_flag 신규 발현/변경
4. additionalContext 주입 + 텔레그램 발송

---

## Round 3: Closing (조건부, v55)

R2에서 **stance_change != UNCHANGED** 이거나 **veto_flag 신규 발현/변경** 한 에이전트만 재소환. 없으면 생략(VERDICT_READY 직진).

재소환 프롬프트:
```
"R1에서 stance={r1_stance}, R2에서 stance={r2_stance} ({stance_change}).
 R1/R2 전체 transcript를 다시 확인하고 최종 stance + veto_flag를 확정하세요.
 출력: stage_artifacts/s0_debate_r3_{role}_{H_ID}.json
 스키마: {role, final_stance, final_veto_flag, closing_statement(150자+)}"
```

R3 완료 → VERDICT_READY 전이

---

## Verdict (Q-Lead, v55 Consensus)

Q-Lead가 stance 합의 집계 + 토론 기록 보존. **점수 합산 폐지.**

### 사전 체크: Codex R2 Verdict 필수 (v53 S2.13)
`stage_artifacts/r2_codex_verdict_<HYP_ID>.json` 파일 존재 확인.
- enforcer의 VERDICT hook이 해당 파일 미존재 시 Write **block**
- 우회: `QVEST_SKIP_CODEX_R2=1` (긴급 시만)
- Codex R2 결과 참조 → VERDICT의 `codex_cross_check` 필드에 요약 기입
- 타임아웃 실패 시 `/tmp/codex_critic_r2_stderr.log` 확인

### Verdict 결정 규칙 (router 자동 집계 = 작성 기준)

`s0_verdict_router.sh`가 v55_consensus_addendum §1 + §1.6 규칙대로 집계합니다. Q-Lead는 router가 적용할 규칙대로 verdict를 작성:

**Full 5인:**
```
veto 2+ 동의 (Codex 제외)              → REVISE   (도메인 필요 시 REJECT)
4+ APPROVE && veto 0                  → APPROVE
3+ REJECT                             → REJECT
3+ (APPROVE | APPROVE_CONDITIONAL) && REJECT≤1 → APPROVE_CONDITIONAL
그 외                                  → REVISE
```

**Compact 3인:**
```
veto 1+ (Risk or Judge/Governor)       → REVISE  (즉시 block)
3/3 APPROVE                            → APPROVE   (consensus_tier: strong)
2+ REJECT                              → REJECT
2+ (APPROVE | APPROVE_CONDITIONAL) && 0 REJECT → APPROVE_CONDITIONAL
그 외                                   → REVISE
```

**Consensus tier 라벨**:
- `UNANIMOUS` — 전원 동일 stance + veto 변동 0
- `MAJORITY` — APPROVE/COND 합산 ≥ 과반
- `MINORITY` — REVISE 우세
- `DEADLOCK` — 동수 또는 veto 충돌

**KR-Inverse는 score penalty가 아니라 quant veto**: Quant가 `veto_flag = "kr_empirical_hard_fail"` 발동 시 veto 1건으로 집계. Compact mode에서는 즉시 REVISE.

### S0_VERDICT 스키마 (v55, enforcer가 강제)

```json
{
  "hypothesis_id": "H_1643",
  "mode": "compact",
  "verdict": "APPROVE_CONDITIONAL",
  "consensus_tier": "MAJORITY",
  "consensus_tally": {
    "approve": 1,
    "approve_conditional": 2,
    "revise": 0,
    "reject": 0,
    "veto_count": 0,
    "veto_flags": []
  },
  "transcript": {
    "rounds": [
      {"round": 1, "entries": [...]},
      {"round": 2, "entries": [...]}
    ]
  },
  "final_stances": {
    "codex_critic": {"r1": "APPROVE_CONDITIONAL", "final": "APPROVE_CONDITIONAL", "stance_change": "UNCHANGED", "veto_flag": null},
    "risk_manager": {"r1": "APPROVE", "final": "APPROVE", "stance_change": "UNCHANGED", "veto_flag": null},
    "judge":        {"r1": "APPROVE_CONDITIONAL", "final": "APPROVE_CONDITIONAL", "stance_change": "UNCHANGED", "veto_flag": null}
  },
  "consensus_points": ["defense family 필요성 전원 동의", "C11 데이터 시간축 검증 필수"],
  "unresolved_disputes": ["D25 평상시 drag — S1 walk-forward에서 실측"],
  "codex_cross_check": "Codex R2: PIT 설계 검증 PASS. kill scenario #2는 S1 gate item으로 이관.",
  "debaters": [
    {"agent_id": "codex_critic_...", "role": "codex_critic", "stance": "APPROVE_CONDITIONAL", "veto_flag": null, "findings": "..."},
    {"agent_id": "risk_manager_...", "role": "risk_manager", "stance": "APPROVE", "veto_flag": null, "findings": "..."},
    {"agent_id": "judge_...", "role": "judge", "stance": "APPROVE_CONDITIONAL", "veto_flag": null, "findings": "..."}
  ]
}
```

**enforcer 강제 사항 (v55):**
- VERDICT_READY 상태에서만 Write 허용 (R2 미완료 시 block)
- `transcript.rounds` 2개+ (R1+R2 최소)
- `final_stances`에 N인(compact 3 / full 5) 전원 r1/final/stance_change/veto_flag 존재
- `consensus_tally`에 approve/approve_conditional/revise/reject/veto_count 필드 존재 + 합계 = N
- `consensus_tier` ∈ {UNANIMOUS, MAJORITY, MINORITY, DEADLOCK}
- `debaters` N건 (compact 3 / full 5) + 필수 역할 전부 포함
- `consensus_points` 1건+ + `unresolved_disputes` 키 존재
- **`total_score` / `final_scores` 필드는 무시** (있어도 통과, 없어도 통과 — score legacy 잔존)

### 라우팅 (s0_verdict_router.sh — 유지)

APPROVE → STR 번호 할당 → Forge inbox TODO_S1
REVISE → Scout 재스폰 + 피드백 (최대 3회)
REJECT → 폐기 로그 + 새 가설 탐색

---

## Stance 결정 기준 (각 에이전트, v55 — 점수제 폐기)

각 debater는 자기 도메인 체크리스트로 stance 1개 + (필요 시) veto_flag 1개를 선택합니다. 항목 합산이 아니라 **약점 1개라도 치명적이면 REVISE/REJECT, veto는 도메인 권한 내에서만**.

### Risk Manager → stance + (veto: tail_risk)
체크: tail_risk / kill_scenario / beta_orthogonality / mdd_contribution / regime_vulnerability
- 5건 모두 OK → APPROVE
- 1~2건 S1에서 실측 가능 → APPROVE_CONDITIONAL (s1_gate_items 명시)
- 3건+ 우려 OR EVT/GPD 위반 명백 → REVISE
- tail_risk가 구조적으로 해소 불가 → `veto_flag: "tail_risk"` + REJECT

### Academic → stance + (veto: mechanism)
체크: peer_review / mechanism_align / korea_evidence / substantive_cite / time_decay
- 1편+ 피어리뷰 + 메커니즘 일치 + KR 실증 → APPROVE
- 메커니즘은 약하나 ML/통계 trail로 보강 가능 → APPROVE_CONDITIONAL
- 메커니즘 논리 결함 → `veto_flag: "mechanism"` + REVISE/REJECT
- ML/KR-original trail은 "논문 없음"만으로 REJECT 금지 (v55 §1.6 Codex 재정의 일관)

### Quant → stance + (veto: PIT | kr_empirical_hard_fail)
체크: icir_check / internal_corr / c19_corr / defense_ic / data_avail / kr_empirical_check
- 모두 PASS → APPROVE
- ICIR 또는 corr 1건만 borderline → APPROVE_CONDITIONAL (S1 measurement gate)
- PIT 설계 결함 (C1~C15 위반 가능성) → `veto_flag: "PIT"` + REVISE/REJECT
- 가설 family + 방향이 VALIDATED_HARD_FAIL L-code와 일치 → `veto_flag: "kr_empirical_hard_fail"` + REVISE
  - L-160 Defense IC-Return decoupling / L-161 KR momentum inverse / L-154 BAB standalone fail
  - L-132/L-135 Value EP (AX-003) / L-133/L-134/L-139 Quality profitability (AX-004) / L-136/L-140 Defense low-beta (AX-005)

### Governor → stance + (veto: admission_rule | gap_misaligned)
체크: gap_alignment / role_match / family_saturation / marginal_contribution / implementation_feasibility
- gap_targeting_axes와 정합 + family 비포화 → APPROVE
- 한계기여 borderline → APPROVE_CONDITIONAL
- admission_rule v3.5.x 위반 → `veto_flag: "admission_rule"` + REVISE
- 현재 GAP과 어긋남 (예: Core 포화 상태에서 Core 가설) → `veto_flag: "gap_misaligned"` + REVISE

### Codex Critic → stance만 (veto 권한 없음, flag만 제시)
체크: l_code_check / failure_avoidance / cross_model_diversity / structural_risk / kill_scenario
- 명백 실패 패턴 회피 + cross-model 동의 → APPROVE
- 약점 있지만 S1 measurable → APPROVE_CONDITIONAL (s1_gate_items 필수)
- 구조적 결함 OR 직접 충돌하는 L-code → REVISE
- empirical 항목(walk-forward IC, beta stability 등)은 stance 결정 근거 금지 → `s1_gate_items`로 이동
- "논문 없음"만으로 REJECT 금지 (ML/KR-original 허용)

### Judge (Compact 3인 모드 한정) → stance + (veto: PIT)
체크: PIT 경계 / 신규 factor 적격 / lesson_check 일관성 / hurdle gate 적용 가능성
- PIT 깨끗 + factor 적격 → APPROVE
- 경계 사례 — S1에서 검증 가능 → APPROVE_CONDITIONAL
- PIT 위반 가능성 → `veto_flag: "PIT"` + REVISE

---

## Hook 아키텍처

| Hook | 이벤트 | 역할 |
|------|--------|------|
| `s0_debate_enforcer.sh` | PostToolUse[Write] | **상태 머신** — R1/R2/R3/VERDICT 전이 강제 + 텔레그램 중계 |
| `s0_debate_guard.sh` | PreToolUse[Agent] | 단일 에이전트 다역할 시뮬레이션 차단 (intent 이중 조건) |
| `s0_verdict_router.sh` | FileChanged[S0_VERDICT_*] | APPROVE/REVISE/REJECT 라우팅 |
