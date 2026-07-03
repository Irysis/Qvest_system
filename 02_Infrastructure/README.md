# 02_Infrastructure — 코드 전용 존

이 폴더는 Qvest의 실행 코드 전체(백테스트 엔진·계약·훅·데이터 빌더)를 담는다. **코드 전용 존 — 산출물(결과 CSV·보고서) 저장 금지** (`docs/rules/artifact-storage.md`). 서브디렉토리명은 하드코딩 참조 때문에 리네임 금지.

주요 하위 구조:
- `contracts/` — 측정·계약 코어 (build_bt_result / canonical_screen_bt / essence_score / register_module 등 실측-only 거버넌스 구현체)
- `hooks/` — 하네스 강제 계층 (qvest_hook_router.py + 47 훅: axiom 강제·graduation gate·backtest audit)
- `data/` + `factor_db/` — 데이터 인제스트/캐시(RAWDATA·benchmark parquet) + 월간 373팩터 DB (`load_month_factors` = C15 유일 진입점)
- `docs/` — 설계 SOT(`docs/qvest_v8_1_sot.md`) + 확장 룰(`docs/rules/`) + CHANGELOG
- `alpha_search/` · `ramp/` — ② alpha-search / ④ RAMP 모드 실행 계층
- `regime/` · `portfolio/` — 국면엔진(RCMA) + 거버넌스(portfolio_governor, book-marginal admission)
- `ops/` · `validation/` — 부팅(bootstrap.sh)·스케줄러·헬스체크 + PIT 강제(pit_enforcement / lookahead_detector)

찾는 것이 있다면: 백테스트 엔진 → `backtest_harness.R` · 게이트 기준 → `hurdle_gate.R` + `worktask/constraint_defaults.json` · 룰 원문 → `docs/rules/`.
상세 파일별 role은 `INDEX.md` 참조 (전체 지도는 루트 `ARTIFACTS.md`).
