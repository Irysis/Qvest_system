---
name: qvest
description: "Qvest v10.4 부팅 — 상태 7줄 후 진행 계층 질문(1계층/2계층/BOOK/어드바이저) → 해당 레인 진입"
disable-model-invocation: true
user-invocable: true
---

# /qvest — 부팅 7줄 → 계층 질문 → 레인 진입 (v10.4 2026-09-04 · 6·7번째 줄 2026-09-21 · 디렉터 동결 2026-09-24)

> ★2026-09-24 도훈 `DIR-DIRECTION-SCORE` = 폐기: 구 1a 단계(`run_direction_score.R --quiet` 규칙 채점)는 실행하지 않는다. 재설계 조건 = 재측정 뒤 A 근접 후보가 여러 경로에 동시에 생길 때(결정 레지스터 위 리플레이).

1. `bash 02_Infrastructure/ops/boot_lean.sh` (≈5초 · 테스트 0 · 수리 0 · 백그라운드 0 · Rscript 0). 출력 7줄:
   - `Data:` — 키 캐시 4종 severity + 신선도 감사 나이(>36h면 `★audit stale`) + rawdata/benchmark mtime + K200/KQ150 멤버십 열(schema만). 결손 시에만 `→ daily_refresh` 조치.
   - `Queue:` — 미소비 논문 수(`alpha-pending`. 안 읽히면 `UNREPORTED` — **0으로 접지 않는다**) + frontier `open` 상위 2건 + ★v10 강화 원장 active(L1 · L2) + data-pipeline open 수.
   - `Last:` — 최신 **리서치 1단위** L-code(`[RP]` 충실구현 / `[RF]` 강화 / `[AS]` 사료 — 세 mode 중 최신) · 등급 · 나이 · `next_probe` 1항.
   - `Book:` — ★v10 BOOK 등록 수·최신 엔트리·트래킹일 (`06_Registry/book/book_registry.json` 정본. **쓰기 = writer 경유 + 도훈 confirm**).
   - `Alerts/Budget:` — 경보 digest + 예산 4종 `값/상한 ✓|✗`.
   - `Director:` — ★2026-09-24 **동결**(도훈 `DIR-PHASE0`·`DIR-ABSORB`): `director.enabled=false` 인 동안 `Director: 동결(흡수 대기 …)` + 대기 결정 부기(`대기결정 N · 최고령 · 차단`)만 보인다 — 옛 캐시(정정 전 수치·막힌 권고)는 전재하지 않는다. 진단·기록 부품은 P1-01·P3-01·P3-05·P3-07 로 흡수 중. 해제 = 도훈 결정으로 config `director.enabled=true`(그때만 `.cache/rf_director_latest.json` 전재 · 30h 초과면 `★stale`).
   - `Rules:` — ★2026-09-24 **폐기**(도훈 `DIR-DIRECTION-SCORE`): 디렉터 동결 중엔 `Rules: 폐기(…)` 표식만. 줄 삭제는 흡수 Phase 2 에서 부팅 줄 수 계약과 함께.
2. 7줄을 **그대로 1회 전재**. 해석·수리·후속 점검 금지. `Data`에 `?`/부재가 있으면 1줄 보고 후 도훈 판단 대기.
3. **★진행 계층을 도훈에게 묻는다** (v10 규칙 "Qvest 실행 시 어떤 계층으로 진행할 것인지 사용자에게 물을 것") — AskUserQuestion. 선택지 순서 = ①②③④ 고정(★2026-09-24 `DIR-PHASE0`: 구 'Director 권고를 첫 선택지로 · human_override 기록' 규칙 삭제 — 권고가 정정 전 수치와 C11 로 막힌 2계층 개설을 가리켰다).
   - **① 1계층 — 팩터전략 리서치**: 큐 상단 논문의 충실구현(`run_paper_replication`) 또는 진행 중 강화(`Skill(reinforce)`, 원장 L1 active 우선). 룰 = `.claude/rules/lean-loop.md`.
   - **② 2계층 — 전략 로테이션 리서치**: `Skill(strategy-rotation)` — 논문 온디맨드 착수 → FR 단위 등급 → 강화 무한.
   - **③ BOOK 관리**: `/book` — 등록 목록·온디맨드 트래킹.
   - **④ 어드바이저 — `/advisor`**: 도훈이 가져온 아이디어·논문·질문에 역할별 자문(alpha·risk·optimizer) → Q 종합 메모 → 측정은 도훈 승인 뒤 정본 계약만(`Skill(qvest-advisor)` · 결정 `QEPM-ADVISOR-MODE`). 큐를 소비하지 않는다.
   (도훈이 이미 계층을 지정했으면 질문 생략하고 바로 진입.)

> 예산 `✗`는 그 자체로 작업 지시가 아니다. WARN 은 보고 대상이지 그 세션의 과제가 아니다.

## 풀 점검 (주간/수동)

`bash 02_Infrastructure/ops/health_full.sh [--with-tests]`. **세션 자동 호출 금지.**

## 진입점 (v10)

| Command | 용도 |
|---|---|
| `/qvest` | 부팅 7줄 → 계층 질문 (본 문서) |
| `/alpha-search` | 1계층 — 논문 1건 충실구현 검증 (기본 단위) |
| `/reinforce` (Skill) | 강화 프로세스 — 셀 엔진 + `run_paper_replication` · L1 상한 = 원장 `max_attempts` / L2 무한 |
| `/worktask` | QEPM WT 체인 — **동결**(도훈 `QEPM-R0-FREEZE` 2026-09-25 · 해제 = decision_register 재상정) |
| `/advisor <아이디어·논문·질문> [--measure]` | 어드바이저 — 역할별 자문 → 종합 메모 → 정본 측정(도훈 승인 뒤 · `QEPM-ADVISOR-MODE`) |
| `/strategy-rotation <track>` | 2계층 — B+ 모듈 국면 배합 → 전천후 모델 |
| `/book` | BOOK 등록 목록·트래킹 (governor 승계) |

★**무인 파이프라인 = 수집 + 강화**(2026-08-30 도훈 "모든 작업을 무인화"). 아침 체인 = 논문 수집·트리아지, 그리고 `02_Infrastructure/ops/reinforce_auto_parallel.R`(1 tick = 1블록 · 워커 `rf_cell_worker.R`)이 강화를 사람 없이 돌린다(상한 = 원장 `max_attempts` 소진 → 다음 논문). ★**규칙 개시**다 — 격자 `06_Registry/reinforce_program.json` · 엔진 `rf_cell_engine.R` 하나 · 러너는 코드 생성 없음. kill switch `06_Registry/reinforce_auto_config.json`. **충실구현·Judge 는 여전히 세션**(논문 판독·PIT 판단).
★**Judge(PIT 전담)는 어느 계층이든 essence Grade A 확정 후에만 스폰** → PASS 시 BOOK 등록 후보(도훈 confirm).
★`/ramp` 퇴임(v9.21) · 기계 사다리(reinforce_ladder)·governor·execution 퇴역(v10) — 파일 사료 존치.

## 정본 위임 (사본은 낙후한다 — 여기에 목록을 다시 적지 않는다)

- agents / skills = `ls .claude/agents .claude/skills` (퇴역분 = `.claude/agents_retired_v10/`)
- hooks = `.claude/settings.json` (예산 ≤13 — v10.2 arm_gen_read_guard 신설분 포함. 세는 건 distinct .sh)
- **BOOK = `06_Registry/book/book_registry.json`** (writer = `02_Infrastructure/book/book_registry.R` 경유만 · 도훈 confirm)
- 강화 원장 = `06_Registry/reinforce_ledger_l1.json`(상한 = 파일 `max_attempts`) · `_l2.json`(무한)
- alerts = `.cache/alerts_digest.md` · 헌법 = `CLAUDE.md` (예산 ≤8KB)
- 페르소나 = `02_Infrastructure/docs/rules/quant-identity.md`
- 구 v8.4 본문 전문 = `02_Infrastructure/docs/CHANGELOG_qvest_command.md` 최상단 절
