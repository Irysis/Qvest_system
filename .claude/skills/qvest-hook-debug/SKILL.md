---
name: qvest-hook-debug
description: Qvest v8.1 Hook 디버깅 + dry-run test 실행. router selftest / cert eligibility 검증 / state machine transition 검증.
---

# Qvest Hook Debug Skill

**Phase 4 router + Phase 5 state machine + Phase 7 cert rules 디버깅 도구.**

## 1. Hook Router Selftest

```bash
python3 02_Infrastructure/hooks/qvest_hook_router.py selftest
```

→ 4 policy 로드 + classify 3 case 검증.

## 2. Hook Router CLI

```bash
ROUTER="02_Infrastructure/hooks/qvest_hook_router.py"

# 1. classify file_path → role + stage
python3 "$ROUTER" classify --file-path "qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json"
# → {"role":"alpha","stage":"final","is_final":true}

# 2. cert eligibility 검증
python3 "$ROUTER" check-cert \
  --cert "alpha_discovery" \
  --package-path "qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json"

# 3. WT phase 전이 검증
python3 "$ROUTER" check-transition --wt-id "WT-D20260601_001" --from "ALPHA_DONE" --to "RISK_DONE"

# 4. Codex Round 5단계 완료 여부
python3 "$ROUTER" check-codex-round-complete --wt-id "WT-D20260601_001" --role "alpha"

# 5. Role permission
python3 "$ROUTER" check-permission --role "alpha-research" --file-path "qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json"
```

## 3. State Machine Selftest

```bash
Rscript -e 'source("02_Infrastructure/worktask/state_machine.R"); qvest_state_machine_selftest()'
```

→ 11 phases / 11 transitions / 10 valid + 3 invalid case + artifact + waiver detection.

## 4. Cert Rules Selftest

```bash
Rscript -e 'source("02_Infrastructure/worktask/cert_rules.R"); qvest_cert_rules_selftest()'
```

→ 5 cert eligibility 함수 + 4 role card + active book 검증.

## 5. All Hook Dry-run Tests

```bash
bash 08_Tests/hooks/run_all_hooks.sh
```

→ 4 test suite (codex_round_gate / worktask_sequence_gate / agent_role_guard / cert_rules) — total 30 cases.

결과: `08_Tests/hooks/results.json`

## 6. Hook 활성 상태 점검

```bash
bash 02_Infrastructure/hooks/harness_health.sh
```

→ 모든 등록 hook 30/30 PASS 확인.

## 7. PostToolUse / PreToolUse 호출 기록 확인

```bash
ls -la /tmp/codex_round*.log /tmp/sr_provenance.log /tmp/schedule_fidelity*.log /tmp/alpha_discovery_certifier.log
tail -20 /tmp/codex_round_pre_enforcer.log
```

## 8. Codex Critic Round Round Trip 검증

```bash
# Specific WT의 codex round 완성 여부
python3 02_Infrastructure/hooks/qvest_hook_router.py \
  check-codex-round-complete \
  --wt-id "WT-D20260501_003" \
  --role "alpha"
# → {"complete":true,"reason":"complete: draft + critic_response present"}
```

## 9. Layer 2 Cert Backfill

```bash
# Auto mode (DRIFTED/WARNING tier 시 bootstrap에서 자동 호출)
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --auto

# Manual (Q-Lead 직접)
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-D20260501_003 --manual

# Dry-run (실 발급 없이 audit만)
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-D20260501_003 --dry-run
```

## 10. Coherence Health Score

```bash
Rscript 02_Infrastructure/portfolio/measurement_basis_audit.R \
  qepm/mailbox/governor/book_state.json \
  qepm/mailbox/worktask
# → Book score: 100 / 100 / Tier: HEALTHY
```

## 11. Hook 신규 등록 패턴 (Phase 4 router 경유)

```bash
# 새 hook 작성 시 router import 권장:
PROJ_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROUTER="$PROJ_DIR/02_Infrastructure/hooks/qvest_hook_router.py"

# Hook 본문에서:
ROLE_INFO=$(python3 "$ROUTER" classify --file-path "$FILE_PATH")
# → Hook이 정규식 중복 보유 안 함, policy JSON 단일 source 사용
```

## 12. 4-Layer 강제 매트릭스 디버깅

문제 발생 시 어느 Layer가 부재인지 확인:

| Layer | 검증 명령 |
|---|---|
| L1 Q-Lead 인지 | `grep "v6.0 Codex Critic Round" CLAUDE.md` |
| L2 spawn prompt | agent prompt에 5단계 흐름 명시 여부 |
| L3 agent definition | `grep "Codex Critic Round" .claude/agents/{role}-research.md` |
| L4 Hook | `ls -la 02_Infrastructure/hooks/codex_round_*.sh` |

3개 미만 작동 시 우회 가능 (L-269 사례).

## 참조

- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (Active SOT)
- `02_Infrastructure/docs/qvest_v6_4_sot.md` (historical SOT, read-only retain)
- `02_Infrastructure/hooks/qvest_hook_router.py` (Phase 4 router)
- `02_Infrastructure/worktask/state_machine.R` (Phase 5)
- `02_Infrastructure/worktask/cert_rules.R` (Phase 7)
- `08_Tests/hooks/run_all_hooks.sh` (Phase 8 dry-run)
- `02_Infrastructure/docs/rules/harness.md`
- `02_Infrastructure/docs/rules/codex-round.md`
