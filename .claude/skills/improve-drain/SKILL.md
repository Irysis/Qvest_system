---
name: improve-drain
description: 자동 스폰 큐(auto_spawn_queue) 소비 절차 — 미승격 전략의 개선 라운드를 claim하고 kind별로 실측/등재/처분까지 완주. `Rscript 02_Infrastructure/ops/auto_spawn_queue.R --status-line`(수동) 또는 health_full 표면 시 사용 — v10 boot_lean 5줄은 이 큐를 표면하지 않는다. 기계는 적재까지, 개시·판정은 이 스킬(세션)이 담당 — BOOK 등록은 별도 수동(Judge PIT PASS + 도훈 confirm).
---

# /improve-drain — 자동 스폰 큐 소비 (Layer 3, L1 — 도훈 승인 2026-08-16)

SOT: `04_Research/01_reports/auto_spawn_orchestration_design_20260816.md`. 큐 = `06_Registry/auto_spawn_queue.json` (빌더: `02_Infrastructure/ops/auto_spawn_queue.R`). kill switch = `06_Registry/auto_spawn_config.json`.

## 절차

### 0. 큐 현황 + claim

```bash
Rscript 02_Infrastructure/ops/auto_spawn_queue.R --status-line
```

pending이 있으면 큐 JSON에서 entry를 고르고 (우선순위: `improvement_potential.score` 내림차순, NA는 후순위) claim:

```bash
Rscript 02_Infrastructure/ops/auto_spawn_queue.R --claim=<entry_id> --owner=<세션식별>
```

- claim 실패(이미 in_progress, stale 6h 이내) = 병렬 세션 진행 중 — **다른 entry로**. 강제 재점유 금지.
- 신규 라벨이 큐에 안 보이면 먼저 재빌드: `Rscript 02_Infrastructure/ops/auto_spawn_queue.R`

### 1. kind별 분기

**overlay_drain** (기계 실측):
```bash
Rscript 02_Infrastructure/regime/overlay_candidate_drain.R <candidate_id>
```
- 결과 JSON의 `verdict` (dv_v1) 확인: INFERIOR → st_record_disposition 불요(overlay 큐가 measured로 자동 갱신), L-code 적립 판단. SURVIVOR → **정밀 검증 라운드로 승격 제안** (strict-PIT·lag1 통과 확인 후 optimizer/forge 경로 — 등급 HARD 3종은 essence_score 소관). INDETERMINATE → 사유(reason) 판독 후 재측정/보류.

**register_module_induce** (FR_RCMA 재정의 소비 — D2):
- 해당 전략의 `bt_result.rds`/계약 산출물로 `register_module()` input floor(backtested ∧ contract_pass ∧ frozen ∧ 4필드) 충족 여부 확인 → 충족 시 등재(→ module_catalog fr_eligible → RCMA 풀 도달), 미충족 시 부족분을 기록하고 처분:
```bash
Rscript 02_Infrastructure/portfolio/standalone_track_queue.R --dispose=<strategy_id> --verdict=fr_routed --note="등재 완료" 
```
(미충족 시 `--verdict=standalone_reject --note="floor 미달: <사유>"`)

**fr_disposition_suggest**: 라벨 이행 확인 후 위 `--dispose` 1클릭 (`fr_routed`).

**standalone_review**: graduation HARD 3종(PORT_t≥2.95 · oos_retention≥0.7 · calmar≥0.64) 실측치 대조 — **완화 제안 금지**. 판정 후 `--dispose` 기록 (`graduation_candidate` / `standalone_reject` / `overlay_routed` 등). graduation_candidate는 도훈 보고(BOOK 등록은 Judge PIT PASS 후 도훈 confirm 수동).

### 2. 완료 처리 + 루프 닫기

```bash
Rscript 02_Infrastructure/ops/auto_spawn_queue.R --done=<entry_id> --note="<한 줄 결과>"
```

- 의미 있는 결과(양성/정보성 negative)는 L-code emit → harvester + `hypothesis_index.R build` (적립은 corpus+index 둘 다).
- 라운드 마감은 `close_round()` (frontier 언급 시 FQ-id 실기록 후 — 선언↔실기록 대조가 경고함).

## 불변 가드

- BOOK(`06_Registry/book/`)·`05_Production/` 쓰기 금지 — 이 스킬의 어떤 분기도 Judge·BOOK 층을 넘지 않는다.
- 모든 수치 인용은 `metric_type`/`tier` 라벨 동반 (`screen_diagnostic`은 자본 주장 불가).
- `improvement_potential.score`(ip_v1)는 우선순위 근거일 뿐 — 판정에 쓰지 말 것 (판별력 검증 루프 전).
- kill switch OFF면 소비하지 않는다.
