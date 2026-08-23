---
name: qvest
description: "Qvest v9.0 부팅(lean) — 상태 5줄 후 즉시 알파 서칭 루프 진입"
disable-model-invocation: true
user-invocable: true
---

# /qvest — 부팅 5줄 → lean-loop 1단계

1. `bash 02_Infrastructure/ops/boot_lean.sh` (≈5초 · 테스트 0 · 수리 0 · 백그라운드 0 · Rscript 0). 출력 5줄:
   - `Data:` — 키 캐시 4종 severity + 신선도 감사 자신의 나이(>36h면 `★audit stale`) + rawdata/benchmark mtime + K200/KQ150 멤버십 열 존재(schema만 읽음). 결손이 있을 때만 `→ daily_refresh` 조치가 붙는다.
   - `Queue:` — 미소비 논문 수(`alpha-pending`. 원장이 안 읽히면 `UNREPORTED` — **0으로 접지 않는다**) + frontier `open` 상위 2건(id · 제목).
   - `Last:` — 최신 alpha-search L-code의 id · 등급 · `next_probe` 1항(다음 라운드의 출발점).
   - `Book:` — 자본 층 현재 편입(`admitted_ids[0]` · 비중 · 갱신일). **쓰기는 도훈 수동.**
   - `Alerts/Budget:` — 경보 digest(미해소 N · 생성 나이) + v9 예산 4종(CLAUDE.md · autoload 룰 합 · 등록 훅 수 · 직전 세션 첫 턴 컨텍스트) `값/상한 ✓|✗`.
2. 5줄을 **그대로 1회 전재**한다. 해석·수리·후속 점검 금지. `Data`에 `?`/부재가 있으면 "데이터 없음 — daily_refresh 필요" 1줄만 보고하고 도훈 판단을 기다린다.
3. 그 외에는 `Queue`의 다음 항목으로 `.claude/rules/lean-loop.md` 1단계를 바로 시작한다 (`Skill(alpha-search)`). 큐가 비면 도훈에게 논문/가설 1건을 요청한다.

> 예산 `✗`는 그 자체로 작업 지시가 아니다 — 감산 여지를 보여줄 뿐이고, 손대는 것은 도훈 지시 시.

## 풀 점검 (주간/수동)

`bash 02_Infrastructure/ops/health_full.sh [--with-tests]` = 구 `bootstrap.sh` 전문 + `alerts_digest_build.sh`(+`--with-tests`면 `08_Tests/hooks/run_all_hooks.sh`).
**세션에서 자동 호출 금지** — 부팅은 위 5줄이 전부다. Digest의 WARN은 **도훈이 지시할 때만** 수리 대상(그 외에는 태스크 분리).

## 진입점

| Command | 용도 |
|---|---|
| `/qvest` | 부팅 5줄 → lean-loop 진입 (본 문서) |
| `/alpha-search` | 논문/가설 1건 경량 백테 검증 — 루프의 기본 단위 |
| `/worktask` | QEPM 6-agent 풀파이프라인 = **자본 층 입구** (Grade A 또는 도훈 지명 시) |
| `/factor-rotation <track>` | 기존 모듈을 국면 조건부로 배합 (모듈 소비) |
| `/ramp <stage>` | K-RAMP 팩터배분 운용체계 (풀 소비 · governor 정지) |

## 정본 위임 (사본은 낙후한다 — 여기에 목록을 다시 적지 않는다)

- agents / skills = `ls .claude/agents .claude/skills`
- hooks = `.claude/settings.json` (예산 ≤12)
- book = `qepm/mailbox/governor/book_state.json` (**도훈만 씀**)
- alerts = `.cache/alerts_digest.md` (생성 = `ops/alerts_digest_build.sh`)
- 헌법 = `CLAUDE.md` (예산 ≤8KB)
- 구 v8.4 본문(체크리스트 28항·5-Tier·Charter·Red Flag) 전문 = `02_Infrastructure/docs/CHANGELOG_qvest_command.md` 최상단 절
