<!-- ★RETIRED (v10 2026-09-02): 호출자 0 · v8.2 DEPRECATED 스텁 — spawn orchestration = .claude/skills/qvest-worktask/SKILL.md. 재열람 = git pre-v10-2layer -->
# Q-Lead Agent Spawn Prompt Template

> **⚠️ DEPRECATED (v8.2, 2026-07-03 스탬프)** — 본 template의 "v6.0 Codex Critic Round 5단계" 흐름은 v8.2에서 폐지됨 (도훈 mandate 2026-06-30: 외부 Codex Round 제거 → 각 agent의 Self-Adversarial Challenge로 대체, 훅 `codex_round_pre_enforcer`/`codex_round_auto_trigger` 등록 해제·archive).
> **현행 절차**: `.claude/skills/qvest-worktask/SKILL.md` (spawn orchestration) + `02_Infrastructure/docs/rules/codex-round.md` (DEPRECATED 스텁 = Self-Adversarial 대체 규약) + `.claude/agents/*.md` 각 role의 "Self-Adversarial Challenge" 절.
> 아래 본문은 이력 보존용 (L-269/L-270 감사추적) — 신규 spawn에 사용 금지.

**버전**: v1.0 (2026-05-01 Session 75 발행, L-269 책임)
**목적**: Q-Lead가 alpha-research / risk-research / optimizer-research / forge / judge / governor agent spawn 시 의무 흐름 명시. **v6.0 Codex Critic Round 의무 누락 방지**.

**Reference**: Session 75 본 cycle WT-D20260501_001 alpha + risk codex round 누락 사례. 4-Layer 진단 (Q-Lead 책임 70% + 시스템 결함 30%). L-269.

---

## 의무 흐름 (모든 agent spawn 공통)

agent prompt에 **다음 5단계 명시 의무**:

```
{role}_package_draft.json 작성 (Write tool, _draft suffix 필수)
↓ PostToolUse codex_round_auto_trigger.sh background spawn (~9-15분)
codex_critic_response_{role}.json 도착 대기
↓ stance/concerns 검토
challenge_note.md 기록 (Charter §8 No Silent Override)
↓ ACCEPT/PARTIAL/REBUTTAL 분류 + spec 수정 (필요시)
{role}_package.json finalize (Write tool, no _draft suffix)
↓ PreToolUse codex_round_pre_enforcer.sh 통과 검증
```

PreToolUse hook이 `_draft` + `codex_critic_response` 둘 다 부재 시 **block** — 우회 불가.

---

## Spawn Prompt 표준 Section (모든 agent prompt에 포함)

```markdown
## v6.0 Codex Critic Round (의무 단계, Charter §8 No Silent Override + L-269 영구)

**5단계 흐름 (절대 skip 금지)**:

1. **Draft 작성**: `qepm/mailbox/worktask/{WT_id}/{role}_package_draft.json` Write tool로 작성
   - `_draft` suffix 필수 — final 직접 작성 시 PreToolUse Hook block

2. **Codex auto-spawn 대기**: PostToolUse `codex_round_auto_trigger.sh`가 background로 spawn (~9-15분)
   - 본 단계는 자동. Agent는 대기.

3. **Codex response 검토**: `qepm/mailbox/worktask/{WT_id}/codex_critic_response_{role}.json` 도착 후
   - `verdict.stance` ∈ {APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT}
   - `critical_concerns` (HIGH/MEDIUM/LOW) 별 분류
   - `weakest_assumption` 명시
   - `ax_violations` (AX-000~005 hard FAIL) 우선

4. **challenge_note.md 기록 의무** (Charter §8):
   - 각 concern: ACCEPT / PARTIAL / REBUTTAL 분류
   - REBUTTAL은 학술 1+ 인용 + L-code 1+ + 정량 data 3축
   - 자기 합리화 자동 detect (미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적)
   - HIGH severity ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 위반 → Q-Lead escalate

5. **Final 작성**: `{role}_package.json` (no _draft) Write tool로 finalize
   - PreToolUse `codex_round_pre_enforcer.sh` 통과 의무
   - draft + critic_response 둘 다 존재 → PASS / 부재 → BLOCK

**우회 시 처리**:
- 정당 사유 (도훈 명시 override / urgent waiver) → `challenge_note.md` 에 `codex_critic_skip_waiver` 명시 + 사유 + 인용
- waiver 없이 final 직접 작성 시 PreToolUse Hook block 발동
```

---

## Q-Lead Self-Check (spawn 전 의무)

매 spawn 직전 다음 체크:

- [ ] agent definition (`.claude/agents/{role}.md`) 매 cycle 확인 (의무 단계 갱신 가능성)
- [ ] spawn prompt에 위 "v6.0 Codex Critic Round 의무 단계" section 포함
- [ ] `_draft` suffix 흐름 명시
- [ ] `challenge_note.md` 기록 의무 명시
- [ ] PreToolUse Hook block 가능성 인지 (waiver 절차 포함)

---

## L-269 Lesson 핵심

**4-Layer 강제 (전부 갖춰야 진짜 의무)**:

| Layer | 책임자 | 수단 |
|---|---|---|
| L1 Q-Lead 인지 | Q-Lead | CLAUDE.md autoload 명문화 (Session 75 v6.3.3 적용) |
| L2 Q-Lead spawn prompt | Q-Lead | 본 template 사용 |
| L3 Agent 자율 의무 | agent | `.claude/agents/*.md` line 22+ 명시 |
| L4 Hook 강제 | 시스템 | `codex_round_auto_trigger.sh` (Post) + `codex_round_pre_enforcer.sh` (Pre, v6.3.3 신규) |

3개 미만 작동 시 우회 가능 — Session 75 사례 (L1+L2+L4 모두 부재) 재발 방지.

---

## 적용 대상 agent (6종)

- `alpha-research` — alpha_package_draft.json
- `risk-research` — risk_package_draft.json
- `optimizer-research` — optimization_package_draft.json
- `forge` — forge_package_draft.json
- `judge` — judge_verdict_draft.json
- `governor` — governor_admission_draft.json

---

## 변경 이력

- **v1.0** — 2026-05-01 Session 75 — 신규 발행. L-269 (Codex Critic Round 우회 사례) 사후 보강.

## 참조

- `CLAUDE.md` ## v6.0 Codex Critic Round 의무 (Level 0)
- `02_Infrastructure/hooks/codex_round_auto_trigger.sh` (PostToolUse, _draft trigger)
- `02_Infrastructure/hooks/codex_round_pre_enforcer.sh` (PreToolUse, final block)
- `02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh` (codex CLI helper)
- `.claude/agents/{alpha,risk,optimizer,forge,judge,governor}-research.md` line 22+ (의무 단계)
- L-269 (methodology_active.md)
