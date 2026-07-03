# 08_Tests — 테스트 존

이 폴더는 계약·훅·통합 테스트 스위트를 담는다. readiness gate와 hook-debug skill이 직접 호출하는 실행 대상 존.

주요 하위 구조:
- `contract_regression/` — 핵심 계약코드(essence_score·canonical_screen_bt·register_module·hurdle_gate) 회귀 스위트 (2026-07-04 신설)
- `hooks/` — hook 배터리 dry-run 스위트 (run_all_hooks.sh + role_guard/cert/sequence 테스트)
- `integration/` — WT lifecycle E2E + readiness gate 통합테스트 (test_wt_lifecycle_e2e.R)
- `ramp/` — RAMP Gate3/4 (순수팩터 추출·검증) 단위테스트
- `regime/` — 국면엔진 테스트 5종 (ktri_v3·msm_daily_refit 등, 대상 코드는 02_Infrastructure/regime/)
- `baseline/` — v6.4.0 기준선 스냅샷 + hook 의존성 감사 기록 (비교 기준 기록물)
- `portfolio/` — optimizer breadth 단발 테스트 (구 머신 경로 하드코딩, 사실상 dead)

찾는 것이 있다면: 훅이 살아있나 → `hooks/run_all_hooks.sh` · 계약코드 수정 후 회귀 → `contract_regression/`.
파일별 상세는 `INDEX.md` 참조 (루트 지도 `ARTIFACTS.md`).
