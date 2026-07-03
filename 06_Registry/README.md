# 06_Registry — 레지스트리(등록부) 존

이 폴더는 시스템의 "무엇이 등록되어 있나"를 담는 JSON 레지스트리 모음이다 — 모듈·가설·논문·라이브트래킹의 단일 등록부.

주요 파일/하위 구조:
- `module_catalog.json` — register_module 공용계약의 모듈 카탈로그 SOT (계약 floor 통과분만) · 미충족분은 `module_quarantine.json` 격리 보존
- `hypothesis_index.json` — alpha-search 가설/검증 이력 인덱스 (중복 가설 방지 — stage_artifacts 탐색 전 여기부터)
- `module_performance.json` + `module_regime_admission.json` — FR 모드가 소비하는 국면조건부 성과/RCMA 판정
- `live_track/` — 라이브 페이퍼트래킹 (현행 PG2 book = STR_1715_on_M4_R05_noLayer4_PG2, holdout 봉인 구간 포함)
- `book_carrier/` — PG2 book 수익 캐리어 + 오버레이 A/B 실측
- `ramp/` — RAMP 승인팩터 라이브러리(parquet)·CCS 스코어·Gate summary
- `paper_registry.json` · `strategy_registry.json` — 논문 파이프라인 / 전략 마스터(178+ STR) 등록부

찾는 것이 있다면: 모듈이 등록됐나 → `module_catalog.json` · 이 가설 이미 해봤나 → `hypothesis_index.json` · 라이브 성과 → `live_track/`.
파일별 role 큐레이션 DB는 `index_descriptions.json`, 상세는 `INDEX.md` (루트 지도 `ARTIFACTS.md`).
