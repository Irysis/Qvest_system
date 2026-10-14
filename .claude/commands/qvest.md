---
name: qvest
description: "Qvest v10.01 부팅 — 상태 6줄 후 진행 계층 질문(1계층/2계층/BOOK/어드바이저) → 해당 레인 진입"
disable-model-invocation: true
user-invocable: true
---

# /qvest — 부팅 6줄 → 계층 질문 → 레인 진입 (v10.01 2026-10-13 · 6번째 줄 = Programs · 구 Director·Rules 퇴역)

> ★v10.01(2026-10-13): 구 디렉터(rf_director.R)·방향 규칙 채점(run_direction_score.R)·고정 격자 강화 러너는 퇴역(코드 삭제 · 롤백 태그 `pre-v10.01-prescription-20261013`). 1계층 상태는 리서치 프로그램 등록부가 대신한다.

1. `bash 02_Infrastructure/ops/boot_lean.sh` (≈5초 · 테스트 0 · 수리 0 · 백그라운드 0 · Rscript 0). 출력 6줄:
   - `Data:` — 키 캐시 4종 severity + 신선도 감사 나이(>36h면 `★audit stale`) + rawdata/benchmark mtime + K200/KQ150 멤버십 열(schema만). 결손 시에만 `→ daily_refresh` 조치.
   - `Queue:` — 미소비 논문 수(`alpha-pending`. 안 읽히면 `UNREPORTED` — **0으로 접지 않는다**) + frontier `open` 상위 2건 + 2계층 강화 원장 L2 active + data-pipeline open 수 + 충실구현 대기·A 대기.
   - `Last:` — 최신 **리서치 1단위** L-code(`[RP]` 충실구현 / `[RF]` 강화 / `[AS]` 사료 — 세 mode 중 최신) · 등급 · 나이 · `next_probe` 1항.
   - `Book:` — ★v10 BOOK 등록 수·최신 엔트리·트래킹일 (`06_Registry/book/book_registry.json` 정본. **쓰기 = writer 경유 + 도훈 confirm**).
   - `Alerts/Budget:` — 경보 digest + 예산 4종 `값/상한 ✓|✗`.
   - `Programs:` — ★v10.01 1계층 리서치 프로그램 등록부(`06_Registry/research_programs.json`): 측정 계약 완료 n/8(남은 MC id) | P0~P4 상태(재료·라운드 수) + 대기 결정 부기(`대기결정 N · 최고령 · 차단`). 판독 실패 = `?(<원인>)`.
2. 6줄을 **그대로 1회 전재**. 해석·수리·후속 점검 금지. `Data`에 `?`/부재가 있으면 1줄 보고 후 도훈 판단 대기.
3. **★진행 계층을 도훈에게 묻는다** (v10 규칙 "Qvest 실행 시 어떤 계층으로 진행할 것인지 사용자에게 물을 것") — AskUserQuestion. 선택지 순서 = ①②③④ 고정(★2026-09-24 `DIR-PHASE0`: 구 'Director 권고를 첫 선택지로 · human_override 기록' 규칙 삭제 — 권고가 정정 전 수치와 C11 로 막힌 2계층 개설을 가리켰다).
   - **① 1계층 — 목표 역산형 리서치**: `Skill(research-program)` — 등록부 순서(선행 조건 MC → 프로그램 라운드 → 재료 충실구현 `/alpha-search`). 룰 = `.claude/rules/lean-loop.md`.
   - **② 2계층 — 전략 로테이션 리서치**: `Skill(strategy-rotation)` — 논문 온디맨드 착수 → FR 단위 등급 → 강화 무한.
   - **③ BOOK 관리**: `/book` — 등록 목록·온디맨드 트래킹.
   - **④ 어드바이저 — `/advisor`**: 도훈이 가져온 아이디어·논문·질문에 역할별 자문(alpha·risk·optimizer) → Q 종합 메모 → 측정은 도훈 승인 뒤 정본 계약만(`Skill(qvest-advisor)` · 결정 `QEPM-ADVISOR-MODE`). 큐를 소비하지 않는다.
   (도훈이 이미 계층을 지정했으면 질문 생략하고 바로 진입.)

> 예산 `✗`는 그 자체로 작업 지시가 아니다. WARN 은 보고 대상이지 그 세션의 과제가 아니다.

## 풀 점검 (주간/수동)

`bash 02_Infrastructure/ops/health_full.sh [--with-tests]`. **세션 자동 호출 금지.**

## 진입점 (v10.01)

| Command | 용도 |
|---|---|
| `/qvest` | 부팅 6줄 → 계층 질문 (본 문서) |
| `research-program` (Skill) | 1계층 — 프로그램 라운드(사전등록 → 측정 → 행동 카드 → 판정 → 보고) · 측정 계약 MC 진척 |
| `/alpha-search` | 1계층 재료 — 논문 1건 충실구현 검증 |
| `/reinforce` (Skill) | 2계층 강화(원장 L2 · 무한) + 처방 도구 상자(셀 엔진 · 블록 어휘) |
| `/worktask` | QEPM WT 체인 — **동결**(도훈 `QEPM-R0-FREEZE` 2026-09-25 · 해제 = decision_register 재상정) |
| `/advisor <아이디어·논문·질문> [--measure]` | 어드바이저 — 역할별 자문 → 종합 메모 → 정본 측정(도훈 승인 뒤 · `QEPM-ADVISOR-MODE`) |
| `/strategy-rotation <track>` | 2계층 — B+ 모듈 국면 배합 → 전천후 모델 |
| `/book` | BOOK 등록 목록·트래킹 (governor 승계) |

★**무인 파이프라인(v10.01)** = 수집(라우터 v5 → 프로그램 재료 큐 · 논문 지도) + 충실구현 레인(`rf_replication_auto.sh` → 검증 → 행동 카드 · 재료 큐 · 다음 논문 `programs/next_replication.R`) + 2계층 레인. 스케줄 진입점 `reinforce_auto_tick.sh`. 스위치 = config `replication_lane.enabled` · `l2_auto.enabled`(전역 `enabled` = 퇴역 러너). 스케줄 재가동 = 도훈 설정.
★**Judge(PIT 전담)는 어느 계층이든 essence Grade A 확정 후에만 스폰** → PASS 시 BOOK 등록 후보(도훈 confirm).
★`/ramp` 퇴임(v9.21) · governor·execution 퇴역(v10) · 고정 격자 러너·디렉터·기계 사다리 코드 삭제(v10.01).

## 정본 위임 (사본은 낙후한다 — 여기에 목록을 다시 적지 않는다)

- agents / skills = `ls .claude/agents .claude/skills` (퇴역분 = `.claude/agents_retired_v10/`)
- hooks = `.claude/settings.json` (예산 ≤13 — v10.2 arm_gen_read_guard 신설분 포함. 세는 건 distinct .sh)
- **BOOK = `06_Registry/book/book_registry.json`** (writer = `02_Infrastructure/book/book_registry.R` 경유만 · 도훈 confirm)
- 리서치 프로그램 = `06_Registry/research_programs.json`(writer `programs/program_registry.R`) · 원장 L2 = `06_Registry/reinforce_ledger_l2.json` · L1 = 충실구현 소비 기록
- alerts = `.cache/alerts_digest.md` · 헌법 = `CLAUDE.md` (예산 ≤8KB)
- 페르소나 = `02_Infrastructure/docs/rules/quant-identity.md`
- 구 v8.4 본문 전문 = `02_Infrastructure/docs/CHANGELOG_qvest_command.md(10-14 정리로 보관소행 · C:/qm_archive/reorg_20261014 · 태그 pre-reorg-20261014)` 최상단 절
