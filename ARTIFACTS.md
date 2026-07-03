# Qvest 산출물 지도 (ARTIFACTS.md)

> 자동 생성 2026-07-04 03:24:45 — 기계가독 원본: `06_Registry/artifact_index.json` · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동)

**저장 4원칙**: ① `stage_artifacts/<mode>/<run_id>/` 실험 런(불변·이동금지) ② `outputs/<pipeline>/` canonical 데이터(최신본만) ③ `06_Registry/` 기계가독 상태·큐·인덱스 ④ `04_Research/<topic>/` 사람용 보고서

## 존별 현황

| 존 | 무엇 | 규모 | 크기 | 최근 활동 | 대표 진입점 |
|---|---|---|---|---|---|
| `stage_artifacts/` | 실험 런 원본 (WT·legacy S0~S7·L-code·agent 산출) | 754항목 / 22,419파일 | 5.3GB | 2026-07-03 (`pg2_defense_drawdown`) | `reports/` + 최근 WT 디렉토리 |
| `outputs/` | 파이프라인 canonical 데이터 (최신본) | 2항목 / 61파일 | 844.0MB | 2026-07-03 (`regime`) | `outputs/ramp/` (RAMP 순수팩터·팩터군 parquet) |
| `06_Registry/` | 기계가독 상태·큐·인덱스 (JSON) | 22항목 / 53파일 | 4.0MB | 2026-07-03 (`artifact_index.json`) | `module_catalog.json` / `hypothesis_index.json` |
| `04_Research/` | 사람용 리서치 보고서·분석 (토픽별) | 107항목 / 6,833파일 | 2.4GB | 2026-07-03 (`architecture_audit_20260703.md`) | `architecture_audit_*` / `pg2_forensics/` |
| `qepm/mailbox/worktask/` | QEPM WT 핸드오프 mailbox (불변 기록) | 166 WT | - | 2026-07-02 (`WT-D20260702_002`) | 최근 WT의 `output/` |

`stage_artifacts` mode 구성: legacy_stage_S0_S7 439 · worktask_run 116 · other 77 · agent_artifact 61 · l_code 41 · pg2 12 · axiom 3 · report 3 · alpha_search 2

## 자주 찾는 것

- **현 book 성과 (noLayer4 PG2)** → `qepm/mailbox/worktask/WT-D20260702_002/output/`
- **감사 보고서** → `04_Research/architecture_audit_*`
- **가설 이력** → `06_Registry/hypothesis_index.json`
- **모듈 풀** → `06_Registry/module_catalog.json` (격리분 `module_quarantine.json`)
- **RAMP canonical** → `outputs/ramp/`
- **오버레이 후보 큐** → `06_Registry/overlay_candidate_queue.json`
- **라이브 트래킹 (holdout 봉인)** → `06_Registry/live_track/`

## 갱신

```bash
Rscript 02_Infrastructure/tools/build_artifact_index.R   # index JSON + 본 파일 동시 재생성
```

