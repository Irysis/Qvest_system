# Artifact Naming Policy (Level 1)

**발효**: 2026-05-29 (v8.0 B1). **위반 = 파이프라인 handoff 단절 risk.**
**근거**: Cycle 2(WT-D20260528_003)에서 `_PROD` suffix variant가 canonical 검사(sequence_enforcer / forge_integration_audit / qvest_hook_router.classify)에 안 걸려 copy로 우회한 사건. 핸드오프 네이밍 규약 부재가 근본.

## 1. 핸드오프 파일 = canonical 단일 이름 (HARD)

WT 파이프라인 단계 간 인계 파일은 **반드시 canonical 이름**:
- `alpha_package.json` / `risk_package.json` / `optimization_package.json` / `forge_package.json` / `judge_verdict.json` / `governor_admission.json`
- draft: `{role}_package_draft.json` (Self-Adversarial Challenge 입력 — 메인 에이전트 자체 적대검증)
- self-adversarial record: `challenge_note.md` (자체 적대검증 기록)

> **v8.2 변경 (2026-06-30, 도훈 mandate)**: QEPM Codex Critic Round 제거 → 외부 codex artifact `codex_critic_response_{role}.json` 명세 **폐기**. 메인 에이전트(Opus 4.8)가 자체 적대검증을 수행하며 기록은 `challenge_note.md`로 남긴다. (S0 Debate codex / RAMP "Codex"는 별개 시스템 — 본 정책 영향 없음.)

이 이름들만 hook(sequence_enforcer L70/77, forge_integration_audit, qvest_hook_router.classify)이 인식한다. (구 `codex_round_pre_enforcer`는 v8.2에서 등록 해제 — `_archive_codex_round_v8_2/`.)

## 2. 탐색 variant = 별도 네임스페이스 (handoff와 분리)

여러 가설/스펙 비교 시(예 D vs D_REFINE vs D_ENSEMBLE, 30f vs 162f) variant는:
- **stage_artifacts 하위 디렉토리** 또는 `_variant_<tag>` suffix로 보관 (handoff 검사 경로 밖).
- **최종 채택분만 canonical 이름으로 복사/승격** → 그 시점부터 파이프라인 진입.
- ❌ `alpha_package_PROD.json` 같은 suffix를 **handoff 자리에** 두지 말 것 (Cycle 2 우회 재발). 채택 시 `cp variant → alpha_package.json`.

## 3. WT 디렉토리 = single prefix

- `WT-{YYYYMMDD}_{NNN}` (mailbox) / `WT_{ID}` (stage_artifacts). 
- **`WT_WT-...` double-prefix 금지** (생성 버그). 발견 시 cleanup 대상 — 단 동일 WT의 정상 dir 존재 확인 후 삭제.

## 4. role 명칭 일관 (optimization ↔ optimizer)

- package 파일: `optimization_package.json` (역사적).
- role/policy 키: **`optimizer`** (role_permissions.json / state_transitions.json 등 정책 키).
- 코드에서 둘 alias 처리 의무 (예 harness_perf_eval.R `if role=="optimization": "optimizer"`).

## 5. 향후 hook 강화 (v8.x 후보)
sequence_enforcer / forge_integration_audit가 canonical 이름만 검사하되, variant가 handoff 자리에 잘못 놓이면 명시 WARN. (현재는 본 정책 + Q-Lead 규율로 보강.)

## 참조
- `02_Infrastructure/docs/rules/harness.md` (hook matrix) · `02_Infrastructure/hooks/worktask_sequence_enforcer.sh` · `qvest_hook_router.py` classify
- Cycle 2 사건: WT-D20260528_003 (`_PROD` copy 우회) — `project_cycle2_overnight_active` 메모리

## Change log
- 2026-06-30 v8.2 (도훈 mandate): QEPM Codex Critic Round 제거 반영 — §1 `codex_critic_response_{role}.json` 명세 폐기 → `challenge_note.md`(self-adversarial record). §1 hook 목록서 `codex_round_pre_enforcer` 제거(등록 해제 · `_archive_codex_round_v8_2/`). §4 optimizer alias 예시를 policy 키 기준으로 재anchor. S0 Debate codex / RAMP "Codex"는 별개 — 불변.
- 2026-05-29 v8.0 B1: 신규. 핸드오프 canonical 단일화 + 탐색 variant 분리 + WT_WT- 금지 + optimizer alias.
