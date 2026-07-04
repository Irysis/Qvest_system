---
name: cleaner
description: 주간 Cleaner 증류 절차 (/cleaner) — 토 09:00 무인 기계 스윕(weekly_cleaner_sweep.R)이 남긴 .cache/cleaner_pending.json을 소비해, 주간 리서치 엑기스를 weekly_digest로 증류(실측만), 미적립 학습을 L-code로 발행, 가치없는 잔재를 참조0 검증 후 무아카이브 삭제. bootstrap "[cleaner] 주간 증류 대기" WARN 또는 수동 트리거 시 사용.
---

# Cleaner Skill — 주간 증류 절차 (LLM 세션 파트)

**발효**: 2026-07-04 (도훈 mandate — "가치없는 잔재 무아카이브 삭제 + 지식은 L-code 적립 + 시스템 자체 증류")
**설계**: 스킬+스케줄러 하이브리드. **기계 스윕은 무인**(Task Scheduler `Qvest_WeeklyCleaner`, 매주 토 09:00 + StartWhenAvailable), **증류는 본 스킬**(무인 LLM 호출은 권한/판단 리스크로 배제 — 다음 세션에서 수행).
**규칙 SOT**: `02_Infrastructure/docs/rules/artifact-storage.md` §8 3선.

---

## §0 트리거 조건

다음 중 하나면 본 스킬 실행:
1. **bootstrap WARN**: `[boot] WARN: [cleaner] 주간 증류 대기 — /cleaner 실행` (`.cache/cleaner_pending.json` 존재 + `status:"awaiting_distill"`)
2. **수동**: 도훈이 `/cleaner` 호출

pending 파일이 없으면: "증류 대기 없음" 보고 후 종료 (기계 스윕을 수동으로 돌리려면 `Rscript 02_Infrastructure/ops/weekly_cleaner_sweep.R`).

---

## §1 절차 (① → ⑤ 순서 고정)

### ① pending 인벤토리 로드

```
.cache/cleaner_pending.json
```

- `week_of` / `sweep_deleted_n` / `inventory` (stage_artifacts 신규 엔트리 · hypothesis_index 델타 · 신규 L-code · git log 7일 요약) / `step_status` 확인.
- `step_status`에 FAIL 단계가 있으면 해당 수집이 누락된 것 — 필요 시 직접 보충 수집 (예: `git log --since=7.days --oneline`).

### ② 주간 리서치 요약 (weekly_digest)

- 산출: `04_Research/01_reports/weekly/weekly_digest_YYYYMMDD.md` (YYYYMMDD = 실행일. 디렉토리 최초 사용 시 생성)
- 내용: 지난 7일 **실험별 결론·수치** — inventory의 stage_artifacts 신규 엔트리·신규 L-code·커밋 요약을 실제 산출물(각 run의 verdict/hurdle_result/manifest)로 역추적해 정리.
- **실측만** (measurement-graduation §1): 수치는 해당 런의 실제 기록 파일에서 인용, `metric_type` 라벨 병기. **추정·재구성 금지** ([[feedback-performance-real-code-only]]).
- 각 실험: 가설 1줄 / 결론(PASS·FAIL·screen-tier 등) / 핵심 수치(출처 파일 경로) / 후속 여부.

### ③ 엑기스 적립 (L-code + 메모리)

- digest 작성 중 발견한 **미적립 학습**(L-code 없는 유의미한 교훈)은 `02_Infrastructure/axiom/lcode_emit.R::emit_lcode()`로 발행 (모드별 prefix 자동, `metric_type` 정직 라벨 — proxy 결과에 backtested 금지).
- 새 L-code 발행 시 헌법 Session End 규칙 적용: `methodology_active.md` 등재 + auto-memory `MEMORY.md` 헤더 갱신 안내.
- 이미 L-code가 있는 학습은 재발행 금지 (inventory의 `new_lcodes` 목록과 대조).

### ④ 잔재 삭제 (무아카이브 — 참조0 검증 후)

- 대상 판정: `artifact-storage.md` **§3.1**(리서치 모드 중간 산출 = 재생성 가능 스크래치) + **§4 Retention** 위반 잔재. 지식 기록이 아닌 **죽은 코드·중복·캐시만** 표적.
- **절대 보존** (어떤 삭제도 금지): `05_Production/` · `01_Literature/` · `stage_artifacts/` 내부 · `qepm/{memory,registry,mailbox}` · `qepm/research/results` · `04_Research/strategies` · `04_Research/90_legacy` · `04_Research/01_reports` · `outputs/`(canonical) · `06_Registry/` · bearish_forecast_v3 (morning_briefing 일간 소비 — 활성).
- 삭제 전 **참조 0 검증 의무**: 후보 경로를 프로젝트 전체 grep (실행코드 + config + registry json) — 참조 1건이라도 있으면 보존 + deferred 기록. 판단이 갈리면 보존.
- 통과분만 무아카이브 삭제 후 **distill manifest 기록**: `06_Registry/distill_manifest_YYYYMMDD.json` — `{deleted: [{path, reason, ref_check:"0건"}], preserved_deferred: [...]}`.

### ⑤ 마커 소거 + 완료 보고

- `.cache/cleaner_pending.json`의 `status`를 `"distilled"`로 갱신 + `distilled_at`·`digest_path` 필드 추가 (bootstrap WARN 해제 조건 = `awaiting_distill` 소거).
- 텔레그램 완료 보고: `tg_agent_brief()` (qvest-telegram SOT 준수 — 첫 섹션 한글 연구 컨텍스트. agent는 화이트리스트 내 `"Q-Lead"` 사용 — 전용 "Cleaner" 미등재). 내용: digest 경로 / 신규 L-code n건 / 삭제 n건·manifest 경로 / deferred n건.

---

## §2 금지·주의

- **증류 자동화 금지** — 본 스킬은 항상 대화 세션에서 실행 (④ 삭제 판단은 LLM+도훈 감독 하).
- digest에 proxy/추정 수치를 실측처럼 기재 금지 (answer-principles 회피표현 grep 대상).
- `stage_artifacts/` 내부는 인벤토리 소스일 뿐 — 어떤 파일도 이동·수정·삭제 금지 (§6 불변 런 기록).
- 커밋은 메인 세션 규율에 따름 (본 스킬이 임의 커밋하지 않음).

## 참조

- `02_Infrastructure/ops/weekly_cleaner_sweep.R` (무인 기계 스윕 — pending 생산자)
- `02_Infrastructure/ops/scheduler/Qvest_WeeklyCleaner.bat` + Task Scheduler `Qvest_WeeklyCleaner`
- `02_Infrastructure/docs/rules/artifact-storage.md` §3.1 / §4 / §8
- `02_Infrastructure/axiom/lcode_emit.R` · `.claude/skills/qvest-telegram/SKILL.md`
