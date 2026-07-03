# outputs — 파이프라인 산출 데이터 존

이 폴더는 RAMP·국면엔진 파이프라인이 자동 생성하는 데이터 산출물(parquet/RData)의 착지점이다. 사람이 읽는 보고서가 아닌 기계 소비용 중간/최종 데이터.

주요 하위 구조:
- `ramp/` — RAMP 모드 산출 parquet (pure_factor_scores 257월 · factor_group_scores · latent_factor_* PCA 산출 · absorption_ratio_signal 등) — RAMP Gate 스크립트(`04_Research/ramp/`)가 생산, graduation 재실행이 소비
- `regime/output/` — MSM 국면엔진 일별 refit 결과 (MSM_updated_YYYYMMDD.RData) — daily_refresh 스케줄러가 매일 append

찾는 것이 있다면: RAMP 순수팩터 점수 → `ramp/*.parquet` · 오늘의 MSM 국면 상태 → `regime/output/` 최신 날짜 파일 · 이 데이터를 만드는 코드 → `02_Infrastructure/ramp/` + `02_Infrastructure/regime/`.
상세 전체 지도는 루트 `ARTIFACTS.md` 참조 (이 존은 INDEX.md 없음).
