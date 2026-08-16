# Qvest 산출물 지도 (ARTIFACTS.md)

> 자동 생성 2026-08-16 17:00:00 — 기계가독 원본: `06_Registry/artifact_index.json` · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동)

**저장 4원칙**: ① `stage_artifacts/<mode>/<run_id>/` 실험 런(불변·이동금지) ② `outputs/<pipeline>/` canonical 데이터(최신본만) ③ `06_Registry/` 기계가독 상태·큐·인덱스 ④ `04_Research/<topic>/` 사람용 보고서

## 존별 현황

| 존 | 무엇 | 규모 | 크기 | 최근 활동 | 대표 진입점 |
|---|---|---|---|---|---|
| `stage_artifacts/` | 실험 런 원본 (WT·legacy S0~S7·L-code·agent 산출) | 1022항목 / 32,133파일 | 8.1GB | 2026-08-16 (`paper_recharge`) | `reports/` + 최근 WT 디렉토리 |
| `outputs/` | 파이프라인 canonical 데이터 (최신본) | 5항목 / 239파일 | 1.6GB | 2026-08-16 (`regime`) | `outputs/ramp/` (RAMP 순수팩터·팩터군 parquet) |
| `06_Registry/` | 기계가독 상태·큐·인덱스 (JSON) | 112항목 / 262파일 | 34.7MB | 2026-08-16 (`artifact_index.json`) | `module_catalog.json` / `hypothesis_index.json` |
| `04_Research/` | 사람용 리서치 보고서·분석 (토픽별) | 34항목 / 6,658파일 | 2.3GB | 2026-08-16 (`01_reports`) | `01_reports/` / `pg2_forensics/` |
| `qepm/mailbox/worktask/` | QEPM WT 핸드오프 mailbox (불변 기록) | 269 WT | - | 2026-08-13 (`WT-D20260813_006`) | 최근 WT의 `output/` |

`stage_artifacts` mode 구성: legacy_stage_S0_S7 439 · worktask_run 259 · other 188 · agent_artifact 61 · l_code 39 · pg2 17 · ramp 7 · alpha_search 5 · report 4 · axiom 3

## 존별 상세 INDEX (큐레이션 병합 — 자동 생성)

- [`02_Infrastructure/INDEX.md`](02_Infrastructure/INDEX.md) — 인프라 코드 존: 카테고리별 정체·status·정리 후보
- [`04_Research/INDEX.md`](04_Research/INDEX.md) — 리서치 산출 존: 카테고리 접기(active-pipeline/report/experiment/…)
- [`06_Registry/INDEX.md`](06_Registry/INDEX.md) — 레지스트리 존: 파일별 정체·계약/모드 라벨
- [`08_Tests/INDEX.md`](08_Tests/INDEX.md) — 테스트 존: 스위트별 정체·실행 가능성
- 큐레이션 DB: `06_Registry/index_descriptions.json` — 신규 항목이 '(미분류)'로 뜨면 여기에 추가 후 재생성

## 자주 찾는 것

- **현 book 성과 (noLayer4 PG2)** → `qepm/mailbox/worktask/WT-D20260702_002/output/`
- **감사 보고서** → `04_Research/01_reports/architecture_audit_*`
- **가설 이력** → `06_Registry/hypothesis_index.json`
- **모듈 풀** → `06_Registry/module_catalog.json` (격리분 `module_quarantine.json`)
- **RAMP canonical** → `outputs/ramp/`
- **오버레이 후보 큐** → `06_Registry/overlay_candidate_queue.json`
- **라이브 트래킹 (holdout 봉인)** → `06_Registry/live_track/`

## 갱신

```bash
Rscript 02_Infrastructure/tools/build_artifact_index.R   # index JSON + 본 파일 동시 재생성
```

