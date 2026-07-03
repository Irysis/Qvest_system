# 04_Research — 리서치 산출물 존

이 폴더는 리서치 산출물(실험 결과·보고서·전략 백테스트)의 착지 존이다. 코드는 `02_Infrastructure/`, 등록부는 `06_Registry/`에 있고 여기는 "결과물"만 쌓인다.

구조 (2026-07 재편 — 카테고리 + 유지 토픽):
- `01_reports/` — 감사·검토·설계 보고서 (아키텍처 감사, 가설 스캔, 제안 검토 등 읽는 문서)
- `02_experiments/` — 일회성 실험 산출 (ML 배치, DVAA/DVFS 재검증, factor DB census 등)
- `90_legacy/` — v5x~v6 시대 스크립트·산출 격리 (삭제 아닌 보존)
- `strategies/` — STR_XXX 전략 백테스트 결과 178+ (헌법이 보존 명시하는 결과 아카이브)
- `factor_rotation/` · `ramp/` — ③ FR / ④ RAMP 모드의 활성 산출 존 (fof_first_slice 슈퍼팩터 실측 등)
- `decision_framework/` · `regime_comparison/` — 부팅·모닝브리핑·DPL이 소비하는 활성 파이프라인 데이터

찾는 것이 있다면: 특정 전략 성과 수치 → `strategies/STR_XXX_*/` (권위는 `qepm/registry/backtest_registry.csv`) · 최신 실험 → `factor_rotation/`·`ramp/` 수정일 순 · 실패 교훈 → `strategy_postmortem.md`.
상세 파일별 role은 `INDEX.md`, 전체 지도는 루트 `ARTIFACTS.md`.
