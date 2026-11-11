---
name: qvest
description: "Qvest v10.2 부팅 — 상태 8줄 후 진행 계층 질문(1계층/2계층/BOOK/어드바이저) → 해당 레인 진입"
disable-model-invocation: true
user-invocable: true
---

# /qvest — 부팅 8줄 → 계층 질문 → 레인 진입 (v10.2 2026-11-11 · 6번째 줄 = Programs(+ 사다리 꼬리 11-11) · 7 Resume(10-15) · 8 Infra(11-08) · 구 Director·Rules 퇴역)

> ★v10.01(2026-10-13): 구 디렉터(rf_director.R)·방향 규칙 채점(run_direction_score.R)·고정 격자 강화 러너는 퇴역(코드 삭제 · 롤백 태그 `pre-v10.01-prescription-20261013`). 1계층 상태는 리서치 프로그램 등록부가 대신한다.

1. `bash 02_Infrastructure/ops/boot_lean.sh` (≈5초 · 테스트 0 · 수리 0 · 백그라운드 0 · Rscript 0). 출력 8줄:
   - `Data:` — 키 캐시 4종 severity + 신선도 감사 나이(>36h면 `★audit stale`) + rawdata/benchmark mtime + K200/KQ150 멤버십 열(schema만) + **퀀티 최신성**(벤치 최신일 vs KRX 직전 거래일 · 휴장일 정본 `06_Registry/krx_holidays.json` — `퀀티 MM-DD ✓` / `★퀀티 미최신 a<b` / 미수록 해 `퀀티 ?(…)`). 결손 시에만 `→ daily_refresh` 조치 · 퀀티 미최신이면 `→ 부팅 규칙` 조치.
   - `Queue:` — 미소비 논문 수(`alpha-pending`. 안 읽히면 `UNREPORTED` — **0으로 접지 않는다**) + frontier `open` 상위 2건 + 2계층 강화 원장 L2 active + data-pipeline open 수 + 충실구현 대기·A 대기.
   - `Last:` — 최신 **리서치 1단위** L-code(`[RP]` 충실구현 / `[RF]` 강화 / `[AS]` 사료 — 세 mode 중 최신) · 등급 · 나이 · `next_probe` 1항 + (v10.2) 결과 원장(`06_Registry/round_outcomes.jsonl`)에 닫힌 라운드가 있으면 가장 최근 라운드의 첫 열린 탐침 `· 원장 다음 탐침 "…"`.
   - `Book:` — ★v10 BOOK 등록 수·최신 엔트리·트래킹일 (`06_Registry/book/book_registry.json` 정본. **쓰기 = writer 경유 + 도훈 confirm**).
   - `Alerts/Budget:` — 경보 digest + 예산 4종 `값/상한 ✓|✗`.
   - `Programs:` — ★v10.01 1계층 리서치 프로그램 등록부(`06_Registry/research_programs.json`): 측정 계약 완료 n/8(남은 MC id) | P0~P4 상태(재료·라운드 수) + 대기 결정 부기(`대기결정 N · 최고령 · 차단`) + ★v10.2 사다리 꼬리 `| 사다리: 상설 판 n(<판> 항목·통과·대기·나이 / <판> 미등록) · 사슬 n(<사슬> k<걸음> <마지막 사건> <나이> ·보류) · 닫힘 n · ★생성 차단 n · 틱 켜짐|꺼짐 · 결과 원장 n건 · 열린 탐침 n(없으면 `없음(첫 닫기 전)`) · 팩터DB 수리 MM-DD(· 수리 진행 중 n)` — 판 정의 = `standing_board_run.sh` · 사슬 정의 = `chain_tick.sh` 와 같다. 판독 실패 = `?(<원인>)`(0 으로 접지 않는다).
   - `Resume:` — ★(2026-10-15 도훈 "세션이 예기치않게 종료됐을 때 새로운 세션에서도 이어질 수 있도록") 진행 중 작업(`06_Registry/session_resume.json` · writer `02_Infrastructure/programs/session_resume.py`) 최신 1건의 단계 n/m · 현재 단계 · 다음 할 일 · 갱신 시각 + 등록부의 '등록됐지만 끝나지 않은 라운드'(저널과 별개 자동 신호). 없으면 `진행 중 작업 없음`.
   - `Infra:` — ★(2026-11-08 도훈 "부팅 시에 점검해서 R, 파이썬 버전, 각종 패키지 등 인프라 최신화 시킬 수 있도록") R · Python(QVEST_PY · venv) 판 vs 공식 최신(CRAN · python.org) + 올릴 수 있는 패키지 수(venv · 시스템Py · R패키지 — 의존 상한에 걸린 것은 `(보류 n)`) + 판을 고정한 열린 라운드(`고정 P2R05`) + 점검 시각. 읽기만 — `.cache/machine/infra_currency_<HOST>.json`(점검기 `02_Infrastructure/ops/infra_currency.py` · 표시 규칙 `infra_line` 단일 출처). 뒤처지거나 올릴 것이 있으면 `★최신화 필요`, 기록이 36시간 넘으면 `★오래됨`.
2. 8줄을 **그대로 1회 전재**. 해석·수리·후속 점검 금지. `Data`에 `?`/부재가 있으면 1줄 보고 후 도훈 판단 대기.
   - ★**인프라 부팅 규칙**(도훈 2026-11-08): `Infra`가 `?(점검 기록 없음 …)`이거나 `★오래됨`이면 `python -X utf8 02_Infrastructure/ops/infra_currency.py` 를 **백그라운드로 1회** 띄운다(읽기만 · 1~2분 · 네트워크) — 다음 부팅부터 새 줄이 보인다. `★최신화 필요`면 1줄 보고(무엇이 얼마나 뒤처졌나 · 보류 · 고정)만 하고 **도훈이 승인할 때** 최신화한다: 패키지 = `python 02_Infrastructure/ops/infra_update.py`(계획) → `--apply`(venv 는 세션에서 · 시스템 Python · R 사용자 라이브러리는 `%LOCALAPPDATA%` 가상화 때문에 일회용 예약 작업이나 보통 PowerShell 에서 · 라운드 고정 · 메이저는 기본 제외) / R · Python **판 자체** = `04_Research/01_reports/env_upgrade_20261109/PLAN.md` 절차(관리자 설치 UAC · 경로 전환 · venv 재생성 · 회귀 시험 · 라운드 재고정). 고정된 패키지를 바꾸면 그 라운드 사전 점검이 '판 불일치'로 막힌다 — 재고정까지 한 묶음.
   - ★**부팅 규칙**(도훈 2026-10-17 "부팅시점에 최신화 안되어있으면 퀀티로그인해서 최신화시킨다" · 결정 BOOT-QW-LOGIN-REFRESH-20261017): `Data`에 `★퀀티 미최신`이 있으면 `bash 02_Infrastructure/ops/ensure_data_current.sh` 를 **백그라운드로 1회** 띄운다(리프레시의 퀀티 수급이 단말을 띄우고 로그인 · 최신화 · 결과 = `.cache/data_currency_stamp.json`). 기다리지 않고 1줄 보고 후 3으로 진행. PC 부팅(로그온 3분 뒤 `morning_run.sh reboot` · 주말 포함)과 아침 브리핑 [0/5] 는 같은 진입점을 스스로 부른다.
3. **★진행 계층을 도훈에게 묻는다** (v10 규칙 "Qvest 실행 시 어떤 계층으로 진행할 것인지 사용자에게 물을 것") — AskUserQuestion. 선택지 순서 = ①②③④ 고정(★2026-09-24 `DIR-PHASE0`: 구 'Director 권고를 첫 선택지로 · human_override 기록' 규칙 삭제 — 권고가 정정 전 수치와 C11 로 막힌 2계층 개설을 가리켰다).
   - **⓪ 이전 세션 리서치 재개**(★2026-10-15 · `Resume:` 줄에 진행 중 작업이 있을 때만 맨 앞에 둔다): `python -X utf8 02_Infrastructure/programs/session_resume.py show` 로 재개 브리핑(목표 · 단계 · 다음 할 일 · 먼저 읽을 것 · 백그라운드 · 결정 대기)을 읽고, '먼저 읽을 것'을 읽은 뒤 **다음 할 일**부터 이어 간다. 백그라운드 항목은 로그 · 센티널로 살아 있는지 먼저 확인한다(죽었으면 그 단계를 다시 띄운다).
   - **① 1계층 — 목표 역산형 리서치**: `Skill(research-program)` — 등록부 순서(선행 조건 MC → 프로그램 라운드 → 재료 충실구현 `/alpha-search`). 룰 = `.claude/rules/lean-loop.md`.
     v10.2 사다리 루프 순서 = 충실구현 레인(엔진) → 상설 판(P1 자격) → 기저 풀 → 강화 사슬(P4 · 한 걸음 = 가설 하나 · 무인 틱이 잇는다) · 절차 = research-program SKILL §0-1 · 상태 = `Programs:` 줄 사다리 꼬리.
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
| `/qvest` | 부팅 8줄 → 계층 질문 (본 문서) |
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
- hooks = `.claude/settings.json` (현행 10 · 예산 ≤13 — 2026-11-10 동결 QEPM WT 가드 3개 등록 해제. 세는 건 distinct .sh)
- **BOOK = `06_Registry/book/book_registry.json`** (writer = `02_Infrastructure/book/book_registry.R` 경유만 · 도훈 confirm)
- 리서치 프로그램 = `06_Registry/research_programs.json`(writer `programs/program_registry.R`) · 원장 L2 = `06_Registry/reinforce_ledger_l2.json` · L1 = 충실구현 소비 기록
- alerts = `.cache/alerts_digest.md` · 헌법 = `CLAUDE.md` (예산 ≤8KB)
- 페르소나 = `02_Infrastructure/docs/rules/quant-identity.md`
- 구 v8.4 본문 전문 = `02_Infrastructure/docs/CHANGELOG_qvest_command.md(10-14 정리로 보관소행 · 99_Archive/reorg_20261014 · 태그 pre-reorg-20261014)` 최상단 절
