# 08_Tests INDEX

> 자동 생성 2026-08-20 21:15 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

## 계약 (4)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `contract_regression/` | 핵심 계약코드(essence_score·canonical_screen_bt·register_module·hurdle_gate) 회귀 스위트 — 07-04 신설, 실행 실측 PASS | active | 2026-08-20 | 169KB |
| `factor_db/` | factor_db IC month-pair 완결성 가드 위반 주입 테스트(test_ic_completion_guard.R) — .ic_pair_complete() 판정 23케이스(A 위반주입/B 회귀/C 크래시/D 차단실효/E 배선). run_all_hooks.sh SUITES 편입, 총계 래칫 감시 대상 | active | 2026-08-09 | 172KB |
| `portfolio/test_optimizer_breadth.R` | mean_variance_optimizer 종목폭(breadth)+RF-O5 HHI-projection 회귀 — Test1~5(min_names/hhi/winsor/infeasible/compat) + Test6/6b/7/8(p>max_names 누출·Σw보존·min>max precheck). worktree-aware proj_root. v2.4 통합엔진 대상 PASS | active | 2026-08-20 | 20KB |
| `portfolio/test_mvo_turnover_penalty.R` | mvo_weights TC-aware 배선(phi·\|x−x_prev\| L1 확장 QP) 회귀 — 비활성 경로 bit-parity 계약 + 단조성/no-trade region/n=2 해석해 대조 24 asserts. worktree-aware proj_root (FQ-057 NP4 dead-parameter 수리 검증) | active | 2026-08-20 | 15KB |

## 훅 (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hooks/` | hook 배터리 dry-run 스위트(run_all_hooks.sh + role_guard/cert/sequence 테스트) — readiness gate·hook-debug skill이 직접 호출. _archive_codex_round_v8_2는 v8.2 폐지분 격리 | active | 2026-08-20 | 714KB |
| `integration/` | WT lifecycle E2E + execution path + readiness gate 통합테스트 — readiness gate가 test_wt_lifecycle_e2e.R·_e2e_cleanup_guard.sh 직접 참조 | active | 2026-08-20 | 69KB |
| `regime/` | 국면엔진 테스트 5종(ktri_v3·msm_daily_refit·fred_robust·briefing_partial·signal_merge) — 대상 코드 전부 02_Infrastructure/regime/에 현존 | active | 2026-08-20 | 42KB |

## 모드-RAMP (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ramp/` | RAMP Gate3/4(순수팩터 추출·검증) 단위테스트 — .qm_root env 인지, 대상 4모듈 전부 현존 | active | 2026-08-20 | 22KB |

## 보고서 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `baseline/` | v6.4.0 기준선 스냅샷(v6_4_0_baseline.json, Session 76 Sprint 0 preflight) + hook 의존성 감사 기록 — 비교 기준 결과 기록물 | report | 2026-07-03 | 18KB |

## 문서 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `README.md` | 테스트 존 진입 설명 | active | 2026-07-03 | 1KB |

## 미분류 (8) — index_descriptions.json에 추가하세요

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `axiom` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-02 | 18KB |
| `contracts` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-16 | 20KB |
| `data` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-20 | 175KB |
| `lib` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-02 | 6KB |
| `methods` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-13 | 21KB |
| `ops` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-20 | 218KB |
| `validation` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-26 | 20KB |
| `worktask` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 16KB |

## stale 큐레이션 키 (2) — 디스크 부재, index_descriptions.json에서 제거 권장

- `e2e/`
- `benchmark_factor_db_optimizations.R`

