# 08_Tests INDEX

> 자동 생성 2026-07-04 04:47 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

## 계약 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `contract_regression/` | 핵심 계약코드(essence_score·canonical_screen_bt·register_module·hurdle_gate) 회귀 스위트 — 07-04 신설, 실행 실측 PASS | active | 2026-07-03 | 38KB |

## 훅 (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hooks/` | hook 배터리 dry-run 스위트(run_all_hooks.sh + role_guard/cert/sequence 테스트) — readiness gate·hook-debug skill이 직접 호출. _archive_codex_round_v8_2는 v8.2 폐지분 격리 | active | 2026-06-29 | 17KB |
| `integration/` | WT lifecycle E2E + execution path + readiness gate 통합테스트 — readiness gate가 test_wt_lifecycle_e2e.R·_e2e_cleanup_guard.sh 직접 참조 | active | 2026-06-07 | 48KB |
| `regime/` | 국면엔진 테스트 5종(ktri_v3·msm_daily_refit·fred_robust·briefing_partial·signal_merge) — 대상 코드 전부 02_Infrastructure/regime/에 현존 | active | 2026-06-07 | 30KB |

## 모드-RAMP (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ramp/` | RAMP Gate3/4(순수팩터 추출·검증) 단위테스트 — .qm_root env 인지, 대상 4모듈 전부 현존 | active | 2026-07-03 | 4KB |

## 보고서 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `baseline/` | v6.4.0 기준선 스냅샷(v6_4_0_baseline.json, Session 76 Sprint 0 preflight) + hook 의존성 감사 기록 — 비교 기준 결과 기록물 | report | 2026-07-03 | 18KB |

## 정리 후보 (status=dead) (3)

| 항목 | 정체 | 카테고리 | 최근 | 크기 |
|---|---|---|---|---|
| `e2e/` | Phase 8 QEPM E2E 12시나리오(v53 skills/qepm-* 플러그인 대상) — 대상 skills/ 디렉토리 자체가 소멸해 실행 불가 | 훅 | - | - |
| `portfolio/test_optimizer_breadth.R` | mean_variance_optimizer 종목폭(breadth) 단발 테스트 — 대상 코드는 현존하나 참조 0 + 구 머신 경로 하드코딩 | 훅 | 2026-06-07 | 10KB |
| `benchmark_factor_db_optimizations.R` | Factor DB Rcpp 최적화(43초→5초) 전후 정합성 검증용 일회성 벤치마크 — 최적화 완료로 용도 소멸 | 훅 | - | - |

