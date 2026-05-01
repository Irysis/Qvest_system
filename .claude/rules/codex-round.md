# Codex Critic Round + Positive Hook 패러다임 (Level 0)

**Charter v1.7 §10 + L-269 + Session 75 v6.4 rule 분리**

## Positive Hook 원칙

LLM은 자기합리화 엔진이라 negative hook ("block on violation")은 defensive rationalization 발동 + bypass 시도. Positive hook ("certify on compliance")은 cooperative goal frame 획득.

**5 Certificate**:
- `alpha_discovery_certificate` (cor<0.95 + mech≥50자 + factor_specs≥1 + harvey_t_count≥3)
- `sr_provenance_certificate` (forge_package 4-field)
- `schedule_fidelity_certificate` (density≥0.95 OR infeasibility_report)
- `forge_package_validated_certificate` (forge_package 8-field)
- `governor_concord_certificate` (book_state ↔ admission match, or `_with_waiver`)

**1 Health Score**: `measurement_coherence_health_score` (0-100, Healthy/Warning/Drifted) — bootstrap 자동 산출.

**4 Role Cards (wt_type)**: discovery / deployment / sizing_only / hyperparameter_sweep.

## Hard Block 2건 (system integrity 위협만)

1. `ProductionSchedule[N]m` fabrication label (sr_provenance_check / schedule_fidelity_check)
2. `governor_admission.json` 전무한 STR을 `book_state.json`에 admit (governor_concord_certifier)

## v6.0 Codex Critic Round 의무 (모든 agent spawn)

**5단계 흐름** (skip 금지, PreToolUse Hook block):

1. **Draft 작성**: `qepm/mailbox/worktask/{WT_id}/{role}_package_draft.json` (Write tool, `_draft` suffix 필수)
2. **PostToolUse codex auto-spawn 대기** (~9-15분 background, `codex_round_auto_trigger.sh`)
3. **Codex response 검토**: `codex_critic_response_{role}.json` 도착 후 stance / critical_concerns / weakest_assumption 분석
4. **challenge_note.md 의무 기록** (Charter §8 No Silent Override):
   - 각 concern: ACCEPT / PARTIAL / REBUTTAL 분류
   - REBUTTAL은 학술 1+ 인용 + L-code 1+ + 정량 data 3축
   - 자기 합리화 자동 detect ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적")
   - HIGH severity ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 위반 → Q-Lead escalate
5. **Final 작성**: `{role}_package.json` (no _draft) — PreToolUse `codex_round_pre_enforcer.sh` 통과 의무 (draft + critic_response 둘 다 존재 검증)

**우회 시 PreToolUse Hook BLOCK** (single-instance 위반 차단).

## Cert Auto-Issuance Paths (v6.3.2 cert_issuance_paths.md 흡수)

| 작성 경로 | Hook 발동 | Cert 자동 발급 |
|---|---|---|
| **Q-Lead Write/Edit tool** | ✅ | ✅ (eligibility 충족 시) |
| Agent (any) → Write tool | ✅ | ✅ |
| Bash → Rscript → file.write | ❌ | ❌ → Layer 2 sweep 보완 |
| 외부 editor (vim/RStudio) | ❌ | ❌ → Layer 2 보완 |
| Cron daemon | ❌ | ❌ → Layer 2 보완 |

**Layer 2 sweep**: `Rscript 02_Infrastructure/ops/cert_backfill_audit.R --auto` (bootstrap 자동) 또는 `--target=WT-XXX --manual`.

## 4-Layer 강제 매트릭스 (L-269)

| Layer | 책임자 | 수단 |
|---|---|---|
| L1 인지 | Q-Lead | CLAUDE.md autoload 명문화 |
| L2 spawn prompt | Q-Lead | `qlead_spawn_template.md` |
| L3 자율 의무 | agent | `.claude/agents/*.md` line 22+ |
| L4 Hook 강제 | 시스템 | `codex_round_auto_trigger.sh` (Post) + `codex_round_pre_enforcer.sh` (Pre) |

**3개 미만 작동 시 우회 가능** — Session 75 사례 (L1+L2+L4 모두 부재) 재발 방지.

## 6 role 적용

alpha-research / risk-research / optimizer-research / forge / judge / governor.

## 예외 (waiver)

도훈 명시 override 또는 Q-Lead urgent waiver 시 `challenge_note.md` 에 `codex_critic_skip_waiver` 명시 + 사유 + 인용. 사후 Layer 2 sweep 의무.

## 참조

- `02_Infrastructure/hooks/codex_round_auto_trigger.sh`
- `02_Infrastructure/hooks/codex_round_pre_enforcer.sh`
- `02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh`
- `02_Infrastructure/prompts/qlead_spawn_template.md` (Phase 9에서 skill로 이동 예정)
- `02_Infrastructure/docs/qvest_v6_4_sot.md`
- L-269 (v6.0 우회 사례 + 3중 장치) / L-270 (v6.3.3 검증 + Bayesian)
