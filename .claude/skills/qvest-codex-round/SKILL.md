---
name: qvest-codex-round
description: QEPM v6.0 Codex Critic Round 5단계 흐름. 모든 6 agent (alpha/risk/optimizer/forge/judge/governor) spawn 시 의무.
---

# Qvest Codex Critic Round Skill

**Charter v1.7 §10 + L-269 + v6.4 SOT**

## 5단계 흐름 (skip 금지)

### Step 1 — Draft 작성

`qepm/mailbox/worktask/{WT_id}/{role}_package_draft.json`
- Write tool 사용 (외부 R script file.write 시 hook 시야 밖)
- **`_draft` suffix 필수**

### Step 2 — PostToolUse codex auto-spawn 대기

`02_Infrastructure/hooks/codex_round_auto_trigger.sh`:
- matcher: `_draft.json` suffix
- Bash GPT-5.5 cross-model `run_codex_qepm_critic.sh` 자동 호출
- ~9-15분 background

### Step 3 — Codex response 검토

`qepm/mailbox/worktask/{WT_id}/codex_critic_response_{role}.json`:
- `verdict.stance` ∈ {APPROVE / APPROVE_CONDITIONAL / REVISE / REJECT}
- `critical_concerns` (HIGH / MEDIUM / LOW) 분류
- `weakest_assumption` 명시
- `ax_violations` (AX-000~005 hard FAIL) 우선

### Step 4 — challenge_note.md 의무 (Charter §8 No Silent Override)

각 concern: ACCEPT / PARTIAL / REBUTTAL 분류:
- **ACCEPT**: 명백한 위반 (PIT C1-15 hard / Hard Constraint / AX axiom hard FAIL) → spec 수정
- **PARTIAL**: 부분 인정 → 보완 자료 + 일부 변경
- **REBUTTAL**: 명시적 근거 필요 (학술 1+ 인용 + L-code 1+ + 정량 data 3축)

자기 합리화 자동 detect:
- "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일"
- REBUTTAL 작성 후 grep 검사 → hit 시 근거 강화

Q-Lead 자동 escalate trigger:
- HIGH severity ≥ 5
- AX axiom hard FAIL ≥ 3
- PIT C1 (lockbox / lookahead) 위반 발견 → 즉시 escalate
- Codex stance=REJECT + agent rebuttal ALL → 자동 Q-Lead 검토 요청

### Step 5 — Final 작성

`qepm/mailbox/worktask/{WT_id}/{role}_package.json` (no `_draft`):
- PreToolUse `codex_round_pre_enforcer.sh` 통과 의무
- 검증: 동일 디렉토리 `_draft.json` + `codex_critic_response_{role}.json` 둘 다 존재
- 부재 시 `{"decision": "block"}` 발동

## 우회 시 처리

PreToolUse Hook BLOCK 발동:
```
CODEX_CRITIC_ROUND_REQUIRED (v6.0 의무 단계, L-269):
role={role} | draft={present|missing} | critic_response={present|missing}
절차: (1) {role}_package_draft.json Write
   → (2) PostToolUse codex auto-spawn 대기
   → (3) codex_critic_response_{role}.json 도착 후 challenge_note.md 기록
   → (4) {role}_package.json finalize
```

## Waiver

도훈 명시 override 또는 Q-Lead urgent waiver 시:
- `challenge_note.md` 에 `codex_critic_skip_waiver` 명시
- 사유 + 도훈 override 인용
- 사후 Layer 2 sweep 의무 (`Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-XXX --manual`)

## 6 role 적용

alpha-research / risk-research / optimizer-research / forge / judge / governor.

## 4-Layer 강제

| Layer | 책임자 | 수단 |
|---|---|---|
| L1 인지 | Q-Lead | CLAUDE.md autoload 명문화 |
| L2 spawn prompt | Q-Lead | `qlead_spawn_template.md` |
| L3 자율 의무 | agent | `.claude/agents/*.md` line 22+ |
| L4 Hook 강제 | 시스템 | auto_trigger (Post) + pre_enforcer (Pre) |

3개 미만 작동 시 우회 가능 — Session 75 사례 (L1+L2+L4 부재) 재발 방지.

## 참조

- `02_Infrastructure/hooks/codex_round_auto_trigger.sh`
- `02_Infrastructure/hooks/codex_round_pre_enforcer.sh`
- `02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh`
- `02_Infrastructure/prompts/qlead_spawn_template.md`
- `02_Infrastructure/docs/qvest_v6_4_sot.md`
- `02_Infrastructure/docs/rules/codex-round.md` (rule SOT)
- L-269 (우회 사례) / L-270 (Bayesian 검증)
