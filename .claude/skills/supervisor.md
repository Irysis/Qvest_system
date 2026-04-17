---
name: supervisor
description: "Q-Lead Supervisor — S0 토론 자동 체인(합산 점수제), Scout plan 승인, 에이전트 관리"
---
## Q-Lead Supervisor Protocol

### Q-Lead의 역할
Q-Lead(메인 세션)는 에이전트를 감독하고, **S0 토론 자동 체인으로 가설 품질을 검증**한 뒤 PG0 관점으로 승인한다.
직접 전략을 만들거나 백테스트를 돌리지 않는다.

---

### S0 가설 토론: 자동 체인 + 합산 점수제

**Skill**: `/s0-debate` (`.claude/skills/s0-debate/SKILL.md`)
**Hook 체인 (v53)**: PostToolUse[Write s0_debate_*.json] → s0_debate_enforcer.sh (상태머신) → FileChanged[S0_VERDICT_*.json] → s0_verdict_router.sh

```
[Phase 1] Scout 가설 설계
  Q-Lead가 Scout 스폰 (name="scout-s0", mode="plan")
  → gap_vector + conditional_ic + L-code 참조 → 가설 설계
  → ExitPlanMode

[Phase 2] 4인 토론팀 자동 스폰
  Hook(PostToolUse[Write], matcher="s0_debate_r1_*.json")
  → s0_debate_enforcer.sh가 R1 상태 전이 + additionalContext 주입
  → Q-Lead가 4명 병렬 Agent 스폰:

  Critic (judge 타입):    L-code 교훈 반론 + 과거 실패 유사성
  Quant (forge 타입):     conditional_ic_matrix ICIR/상관 수치 팩트체크
  Academic (scout 타입):  core_knowledge_base + arXiv/SSRN 논문 검증
  Gov-proxy (governor 타입): gap_vector 정합성 + 슬리브 + MDD 기여

[Phase 3] 합산 점수 판정
  4명 완료 → Q-Lead가 점수 집계 (각 0~25점, 총 100점):

  | 점수 | 판정 | 조치 |
  |------|------|------|
  | 75~100 | APPROVE | 즉시 S1 진행 |
  | 60~74 | APPROVE_CONDITIONAL | 조건 명시 후 S1 |
  | 40~59 | REVISE | 피드백 → Scout 재설계 (최대 3회) |
  | 0~39 | REJECT | 가설 폐기 |

  특수 규칙:
  - Gov-proxy ≤ 5점 → 무조건 REJECT
  - Quant ≤ 5점 → 무조건 REJECT

  → S0_VERDICT_{factor_id}.json 저장

[Phase 4] 자동 라우팅
  Hook(FileChanged, matcher="S0_VERDICT_*.json")
  → s0_verdict_router.sh → Q-Lead에 다음 단계 주입:
  - APPROVE: allocate_str + s0_record + Forge TODO_S1
  - REVISE: Scout 재스폰(scout-s0) + 피드백 주입 → Phase 1 복귀
  - REJECT: 폐기 로그 + 새 가설 탐색 지시
```

### 채점 Rubric (각 에이전트 25점)

**Critic**: l_code_check(5) + failure_avoidance(5) + banned_factor(5) + lesson_check(5) + structural_risk(5)
**Quant**: icir_pass(5) + internal_corr(5) + c19_corr(5) + defense_ic(5) + data_avail(5)
**Academic**: peer_review(5) + mechanism_align(5) + korea_evidence(5) + substantive_cite(5) + time_decay(5)
**Gov-proxy**: role_match(5) + family_diverse(5) + cond_value(5) + stock_limit(5) + mdd_contrib(5)

### 토론 에이전트 산출물 형식 (JSON 필수)
```json
{
  "role": "critic|quant|academic|govproxy",
  "total": 0-25,
  "breakdown": { "항목1": 0-5, "항목2": 0-5, ... },
  "findings": "핵심 판정 근거 500자 이내",
  "conditions": ["조건1", ...] 또는 []
}
```

---

### Scout Plan 승인 기준 (PG0 Governor 관점)

1. `.cache/portfolio_gap_vector.json` → **sleeve_needs 일치**
2. `methodology_memory.md` → **L-code 위반 없음**
3. **단독 팩터 → REJECT** (멀티팩터 블렌드 필수)
4. core_reference 부재 → REJECT (피어리뷰 학술 근거 필수)
5. 기존 factor_id 중복 → REJECT
6. defense 역할 → **conditional_value > 0 필수** (ic_bad > ic_good)

---

### 에이전트 관리 (v53 TeamCreate 모델)
- **건강 체크**: `Read ~/.claude/teams/<team>/config.json` → members 상태 확인. idle teammate는 SendMessage로 깨움.
- **teammate spawn**: `TeamCreate + Agent(team_name=...)` — 각 teammate는 자율적으로 inbox TODO 수행
- **TeammateIdle Hook**: idle 감지 시 teammate_idle_guard.sh가 작업 재할당 제안
- **Governor 활성화**: PG0 gap이 있거나 Grade A 신규 전략 발생 시 Governor teammate에게 TODO_PG0 전달
- **죽은 teammate 복구**: Agent 도구로 재스폰 (team_name 동일, name 동일)
- v50/v52 tmux 4-pane liveness 체크는 **deprecated** (QVEST_KEEP_LEGACY_TMUX=1 에서만 의미)

### 파이프라인 연결
| 작업 | 방식 |
|------|------|
| **S0 가설** | `/s0-debate` skill → Hook 자동 체인 (Scout→토론→판정→라우팅) |
| S3/S5 후속 | TeammateIdle Hook + `/scout` |
| S1~S7 실행 | Hook + pipeline_trigger.sh |
| S7→PG0 | pipeline_trigger.sh (Grade A/B만) |
| PG0→S0 | gap_vector 갱신 → `/s0-debate` 재호출 |

### 일감 밸런싱
- Forge inbox > 20 → 가설 생성 보류
- RAM > 80% → Forge 병렬 제한
- RAM > 90% → 모든 추가 스폰 중단
