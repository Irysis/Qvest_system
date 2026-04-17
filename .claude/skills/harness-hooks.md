---
name: harness-hooks
description: "Hook 17종 operator guide — Tier별 분류, 각 hook 강제 규칙 + 우회 env 변수 + 로그 위치. 디버깅/신규 hook 추가 시 참조."
---
## Harness Engineering v53 (Hook 17종 4-Tier)

모든 프로세스 규칙은 프롬프트가 아닌 Hook으로 강제한다. **"엄밀함은 사라지지 않고 이동한다."**
v53에서는 Q-Lead 단일 세션 내 자동 발동 (tmux pane 모델 폐기).

### Tier 분류

- **L1 Bootstrap**: 세션 시작 시 1회 실행
- **L2 Soft Gate**: 검증 실패 시 경고 + 로그
- **L3 Hard Block**: 위반 시 도구 실행 자체를 물리적 차단
- **L4 구조 강제**: JSON 스키마 + agent_id 추적 + LLM 판정

### Hook 목록

| # | Hook | 이벤트 | 강제 대상 | Tier | 우회 env |
|---|------|--------|-----------|------|----------|
| 1 | `axiom_enforcement_hook.sh` | PreToolUse[W/E] | AX-001 Defense F + AX-002 사후수정 + 동적 AX.enforcement regex | L3 | — |
| 2 | `safety_guard.sh` | PreToolUse[W/E/B] | 05_Production / 01_Literature (Korea_Research 제외) / normalizePath | L3 | — |
| 3 | `forge_code_guard.sh` | PreToolUse[W/E/B] | OPT-1~12 (loop parquet / cache / Daily NAV / mclapply / stress / VaR / S1 overlay / 20종목 / 유동성 / lag / L-code reuse) + PIT v3 blocking_gate + FDB 신선도 + Codex PIT flag | L3 | `QVEST_SKIP_PIT_V3=1`, `QVEST_ALLOW_STALE_DB=1` |
| 4 | `unified_agent_guard.sh` | PreToolUse[Agent] | Stage 순서 (S1/S2/S3/S4/S5/S6 + PG0~PG3) + S5 Fast-Track (mutation_tracker) + active AX 전 에이전트 주입 | L3 | — |
| 5 | `s0_debate_guard.sh` | PreToolUse[Agent] | 1인 다역할 시뮬레이션 차단 (3+ 역할 + 채점 지시 감지) | L4 | — |
| 6 | `artifact_validator.sh` | PostToolUse[Write] | stage_artifacts 스키마 + PIT 표현 격리(P2-B .p2b_violation) + L-code harvester 트리거 + s6_judge → role_honesty_runner 자동 + grade_a_catalog 갱신 + s0_record → backlog bucket | L2+L3 | — |
| 7 | `pipeline_trigger.sh` | PostToolUse[W/B] | DONE→TODO 자동 라우팅 + mutation_tracker 갱신 + 처리완료 archive (flock 직렬화) | L3 | — |
| 8 | `circuit_breaker.sh` | PostToolUse[Bash] | 동일 STR 3회 연속 Rscript 실패 → 차단 + 30분 초과 경고 | L3 | — |
| 9 | `risk_gate.sh` | PostToolUse[Bash] | 백테스트 후 tail_risk_result.json 존재 확인 + additionalContext 경고 | L2 | — |
| 10 | `s0_debate_enforcer.sh` | PostToolUse[Write] | R1/R2/R3/VERDICT 상태 머신 + Codex R2 auto-trigger (S2.13) + transcript/final_scores/debaters 스키마 검증 + 텔레그램 중계 | L4 | `QVEST_SKIP_CODEX_R2=1` (VERDICT만) |
| 11 | `s0_verdict_router.sh` | FileChanged[S0_VERDICT_*] | debaters agent_id 중복/역할 누락 검증 + APPROVE/REVISE/REJECT 라우팅 | L3 | — |
| 12 | `judge_autospawn.sh` | PostToolUse[Write(hurdle_result)] | 60s grace 후 s6_validation 미존재 시 Judge inbox TODO_S6_REVIEW 생성 | L2 | — |
| 13 | `teammate_idle_guard.sh` | TeammateIdle[*] | idle teammate 감지 → 작업 재할당 제안 | L3 | — |
| 14 | `task_complete_guard.sh` | TaskCompleted[*] | 태스크 완료 시 파이프라인 다음 단계 트리거 | L3 | — |
| 15 | `harness_health.sh` | 부트스트랩 | 전체 Hook 파일 존재/실행권한/ERR trap 체크 (14/14) | L1 | — |
| 16 | `resolve_project.sh` | 공용 | 프로젝트 경로 해석 (WSL 한글 경로 대응) | — | — |
| 17 | `run_codex_critic*.sh` / `run_pit_intent_scan.sh` | on-demand | Codex companion 래퍼 (R2 R1 transcript 주입 등) | L4 | — |

### Hook 실행 순서 (도구 호출 시)

```
User → Claude가 도구 호출 시도
   ↓
PreToolUse hooks (matcher 일치하면 순서대로)
   - axiom_enforcement (W/E) → block?
   - safety_guard (W/E/B)    → block?
   - forge_code_guard (W/E/B)→ block?
   - unified_agent_guard (Agent) → block?
   - s0_debate_guard (Agent) → block?
   ↓ (모두 통과)
도구 실행
   ↓
PostToolUse hooks (matcher 일치하면)
   - artifact_validator (W)   → block+격리?
   - pipeline_trigger (W/B)   → 라우팅
   - circuit_breaker (B)      → 연속 실패 차단
   - risk_gate (B)            → 경고
   - s0_debate_enforcer (W)   → 상태전이 + Codex R2
   - judge_autospawn (W)      → TODO 생성
   ↓
FileChanged hooks (매칭)
   - s0_verdict_router (S0_VERDICT_*)
   ↓
Teammate events
   - teammate_idle_guard
   - task_complete_guard
```

### 주요 로그 위치

| 로그 | 내용 |
|------|------|
| `/tmp/forge_code_guard.log` | OPT-1~12 + PIT v3 + FDB 신선도 violation |
| `/tmp/axiom_enforcement.log` | AX-001/002 block + 동적 enforcement |
| `/tmp/artifact_validation.log` | 스키마 경고 + 합리화 표현 탐지 |
| `/tmp/pipeline_trigger.log` | DONE→TODO 전이 |
| `/tmp/risk_gate.log` | tail_risk 확인 결과 |
| `/tmp/s0_debate_enforcer.log` | R1/R2/R3/VERDICT 상태 전이 |
| `/tmp/s0_verdict.log` | 라우팅 |
| `/tmp/judge_autospawn.log` | Judge TODO 생성 |
| `/tmp/hook_errors.log` | enforcer/validator stderr |
| `/tmp/axiom_weekly.log` | 주간 axiom 갱신 |
| `/tmp/axiom_quarterly.log` | 분기 review |

### Env 변수 (운영 조정)

| 변수 | 기본값 | 효과 |
|------|-------|------|
| `QVEST_STRICT_MODE` | `TRUE` | hurdle_gate D074 DSR/FF5 Grade A 강등 활성 |
| `QVEST_SKIP_PIT_V3` | `0` | forge_code_guard PIT Engine v3 block 우회 |
| `QVEST_ALLOW_STALE_DB` | `0` | Factor DB 30일 초과 block 우회 (P3-A) |
| `QVEST_SKIP_CODEX_R2` | `0` | S0 Debate VERDICT 작성 시 Codex R2 필수 우회 |
| `QVEST_AXIOM_AUTO_INJECT` | `0` | inject.R 실제 쓰기 (CLAUDE.md + prompts) |
| `QVEST_KEEP_LEGACY_TMUX` | `0` | bootstrap이 legacy tmux research/supervisor 종료 억제 |
| `QVEST_PROJECT_DIR` | 자동탐지 | axiom py 스크립트 경로 지정 |

### harness_health 실행

```bash
bash 02_Infrastructure/hooks/harness_health.sh
# === Result: 14/14 passed, 0 failed ===
# [HARNESS] All hooks healthy.
```

부트스트랩(`bash 02_Infrastructure/ops/bootstrap.sh`)이 자동 호출.

### Hook 추가 시 체크리스트

1. **파일 위치**: `02_Infrastructure/hooks/<name>.sh` (표준 경로)
2. **Shebang + ERR trap**: `trap 'echo "{}"; exit 0' ERR` 필수 (stdout 스키마 유효 유지)
3. **출력 JSON 스키마**:
   - 통과: `echo '{}'`
   - block: `printf '{"decision":"block","reason":"..."}'` (PreToolUse 기준)
   - additionalContext 주입: `{"hookSpecificOutput":{"hookEventName":"<Event>","additionalContext":"..."}}`
   - `decision:allow` 금지 (스키마 위반)
4. **settings.json 등록**: `.claude/settings.json` hooks 섹션 추가
5. **harness_health 파일 목록 갱신**: `02_Infrastructure/hooks/harness_health.sh`의 REQUIRED_HOOKS 배열
6. **로그**: `/tmp/<name>.log`에 타임스탬프 + 판정 기록
7. **테스트**: 샘플 payload를 echo + bash로 invoke, 예상 출력 확인

### 흔한 오류

- **"Hook JSON output validation failed — (root): Invalid input"**
  → `decision:allow` 사용 중. `{}` 또는 `{"continue":true}`로 변경.
- **Hook이 발동되지 않음**
  → `.claude/settings.json` matcher 패턴 확인 (예: `Write|Edit|Bash` 대소문자 정확).
- **Hook이 너무 느림 (Agent spawn 지연)**
  → python3 호출 최소화, 캐시 활용 (PIT v3의 md5 flag 참조).

### v53 핵심 변화 요약

- Q-Lead 단일 세션 → 모든 Hook이 이 세션 내 발동 (중복 위험 없음)
- mutation_tracker + grade_a_catalog + backlog_buckets + lcode_corpus: Hook이 자동 갱신
- AX active 전체 주입: unified_agent_guard가 전 에이전트 스폰 시 additionalContext
- Codex R2 / role_honesty_runner / axiom_harvester: 백그라운드 자동 트리거
- 레거시 tmux supervisor: agents/_archive로 이동, bootstrap 자동 종료
