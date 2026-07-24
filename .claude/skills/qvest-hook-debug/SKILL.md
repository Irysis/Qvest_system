---
name: qvest-hook-debug
description: Qvest v8.x Hook 디버깅 + dry-run test 실행. router selftest / E2E 배터리 / cert eligibility 검증 / state machine transition 검증.
---

# Qvest Hook Debug Skill

**router + state machine + cert rules + E2E 배터리 디버깅 도구.** (2026-07-24 현행화 — Codex Round 절 제거(v8.2 폐지), bare python3 금지)

⚠ **python 해석기**: bare `python3` = Windows Store 스텁(fail-open 사고 이력). 반드시 venv 사용:
```bash
PY="${QVEST_PY:-/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe}"
```

## 1. Hook Router Selftest

```bash
"$PY" 02_Infrastructure/hooks/qvest_hook_router.py selftest
```

→ policy 로드 + classify case 검증.

## 2. Hook Router CLI

```bash
ROUTER="02_Infrastructure/hooks/qvest_hook_router.py"

# 1. classify file_path → role + stage
"$PY" "$ROUTER" classify --file-path "qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json"
# → {"role":"alpha","stage":"final","is_final":true}

# 2. cert eligibility 검증
"$PY" "$ROUTER" check-cert \
  --cert "alpha_discovery" \
  --package-path "qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json"

# 3. WT phase 전이 검증
"$PY" "$ROUTER" check-transition --wt-id "WT-D20260601_001" --from "ALPHA_DONE" --to "RISK_DONE"

# 4. Role permission
"$PY" "$ROUTER" check-permission --role "alpha-research" --file-path "qepm/mailbox/worktask/WT-D20260601_001/alpha_package.json"
```

(구 `check-codex-round-complete`는 v8.2 Codex Round 폐지로 미사용 — Self-Adversarial은 `challenge_note.md` 존재로 확인.)

## 3. State Machine Selftest

```bash
Rscript -e 'source("02_Infrastructure/worktask/state_machine.R"); qvest_state_machine_selftest()'
```

## 4. Cert Rules Selftest

```bash
Rscript -e 'source("02_Infrastructure/worktask/cert_rules.R"); qvest_cert_rules_selftest()'
```

## 5. Hook E2E 배터리 (정본 회귀 테스트)

```bash
"$PY" 02_Infrastructure/ops/hook_e2e_battery.py
```

→ 11 케이스 (역할가드 / 제약 / 주입-페이로드 / 텔레그램 가드 / axiom inject / milestone). 2026-07-24 기준 11/11 PASS. 결과 영속: `.cache/hook_e2e_battery_latest.json`.

보조: `bash 08_Tests/hooks/run_all_hooks.sh` (dry-run suite, codex_round_gate 케이스는 legacy).

## 6. Hook 활성 상태 점검

```bash
bash 02_Infrastructure/hooks/harness_health.sh
```

## 7. PostToolUse / PreToolUse 호출 기록 확인

```bash
ls -la /tmp/sr_provenance.log /tmp/schedule_fidelity*.log /tmp/alpha_discovery_certifier.log \
       /tmp/answer_principles.log /tmp/pipeline_trigger.log /tmp/qvest_hook_router_dispatch.stderr.log
tail -20 /tmp/qvest_hook_router_dispatch.log 2>/dev/null || tail -20 /c/tmp/qvest_hook_router_dispatch.log
```

## 8. Layer 2 Cert Backfill

```bash
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --auto           # bootstrap 자동 호출 모드
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-D20260501_003 --manual
Rscript 02_Infrastructure/ops/cert_backfill_audit.R --target=WT-D20260501_003 --dry-run
```

## 9. Coherence Health Score

```bash
Rscript 02_Infrastructure/portfolio/measurement_basis_audit.R \
  qepm/mailbox/governor/book_state.json \
  qepm/mailbox/worktask
```

## 10. Hook 신규 등록 패턴

- **PreToolUse[Write|Edit] 게이트**: settings.json 직접 등록 금지 — `02_Infrastructure/hooks/policies/router_dispatch.json`에 엔트리 추가 (라우터 dispatch 단일 등록점).
- **기타 이벤트**(Read/Bash/PostToolUse/Stop/SubagentStop): settings.json 개별 등록.
- **의무 패턴**: ① content를 python 소스에 보간 금지 — env 경유 + quoted heredoc(`<<'PYEOF'`) ② 경로 필터는 python 파싱 **앞**에 raw-INPUT superset grep 조기-exit ③ advisory는 `{}`가 아니라 additionalContext 채널로 실전달 (라우터 훅 = `{"additionalContext": ...}` 단일키 / 직접 등록 PostToolUse = `hookSpecificOutput.additionalContext`).

```bash
ROLE_INFO=$("$PY" "$ROUTER" classify --file-path "$FILE_PATH")   # 정규식 중복 금지, policy JSON 단일 source
```

## 11. 강제 매트릭스 디버깅 (일반형)

문제 발생 시 어느 Layer가 부재인지 확인:

| Layer | 검증 명령 |
|---|---|
| L1 Q-Lead 인지 | CLAUDE.md 해당 규칙 절 grep |
| L2 spawn prompt | agent 스폰 프롬프트에 의무 명시 여부 |
| L3 agent definition | `.claude/agents/{role}.md` 해당 의무 grep |
| L4 Hook | settings.json / router_dispatch.json 등록 + 실발화 로그 |

3개 미만 작동 시 우회 가능 (L-269 사례 — 당시 대상은 Codex Round, 패턴은 일반).

## 참조

- `02_Infrastructure/docs/qvest_v8_1_sot.md` + `02_Infrastructure/docs/qvest_modes_sot.md` (Active SOT)
- `02_Infrastructure/hooks/qvest_hook_router.py` + `policies/router_dispatch.json`
- `02_Infrastructure/worktask/state_machine.R` · `cert_rules.R`
- `02_Infrastructure/ops/hook_e2e_battery.py` (정본 배터리)
- `02_Infrastructure/docs/rules/harness.md` (2026-07-24 정합 절 포함)
