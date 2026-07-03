# Codex Critic Round (DEPRECATED v8.2 — 2026-06-30)

**상태**: 제거됨 (도훈 mandate 2026-06-30). QEPM 외부 Codex Critic Round 폐지.
**사유**: 메인 에이전트가 Opus 4.8로 자체 적대검증(self-adversarial challenge)을 수행 → 외부 GPT-5.5 Codex 라운드가 중복.
**대체**: 각 agent(`.claude/agents/*.md`)가 finalize 직전 self-adversarial challenge 수행(약점 ≥3건 자가 제기 → ACCEPT/PARTIAL/REBUTTAL 분류 → `challenge_note.md` 기록). No Silent Override(Charter §8)·self-rationalization auto-detect는 유지.

## AX-008 정합
AX-008 Verification Triangulation의 Codex source는 self-adversarial로 치환: **Forge + Self-Adversarial(메인 Opus 4.8) + Architect 3-source 중 2 PASS**(구조·임계값 불변). 동기화 4곳: `qepm/memory/axioms/active/AX-008.json` · `.claude/rules/axioms.md` · `02_Infrastructure/prompts/_shared_prefix.md` · `02_Infrastructure/hooks/policies/state_transitions.json::ax_008_sources`.

## 제거 범위 (v8.2)
- `.claude/settings.json` 훅 3개 등록 해제: `codex_round_pre_enforcer` / `codex_round_auto_trigger` / `codex_round_subagent_stop`.
- `state_transitions.json`: 6 phase `codex_critic_response_{role}.json` required 제거 + `ax_008_sources` codex→self_adversarial.
- `qvest_hook_router.py`: selftest policy list에서 `codex_round_contract` 제거 + `check_codex_round_complete()` passthrough.
- archive: `02_Infrastructure/hooks/_archive_codex_round_v8_2/` (`run_codex_qepm_critic.sh` + `codex_round_*.sh` 3 + `policies/codex_round_contract.json`) + `02_Infrastructure/prompts/_archive_codex_round_v8_2/` (`qepm_codex_base_context.md` + `codex_{role}_critic_prompt.md` 6).
- skill `qvest-codex-round` 삭제.

## Historical (보존 — read-only retain)
- **L-269** (v6.0 우회 사례 + 3중 장치) / **L-270** (v6.3.3 검증 + Bayesian) — Codex Round 도입·검증 이력.
- 과거 WT 산출물(`qepm/mailbox/worktask/**/challenge_note.md`, `codex_critic_response_*.json` 수백 건)은 감사추적·재현성 보존.

## 별개 시스템 (본 제거와 무관 — 절대 건드리지 말 것)
- **S0 Debate codex_critic** (`02_Infrastructure/hooks/s0_enforcer/`, `stage_artifacts/r2_codex_verdict_*`): 가설토론 검증 — 별개 서브시스템.
- **RAMP "Codex"** (`.claude/agents/ramp-orchestrator.md`, `00_Lawbook/K_RAMP/K_RAMP_Codex_*`): Q-Lead+에이전트 오케스트레이터 역할명(외부 critic 아님).

## 참조
- `02_Infrastructure/hooks/_archive_codex_round_v8_2/` (archived 구현)
- `02_Infrastructure/docs/CHANGELOG_constitution.md` (v8.2 entry) · `00_Lawbook/DEPRECATION.md`
