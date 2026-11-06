# m4 발행 원장 — C11 epoch 기준선

**발효**: 2026-09-25 11:36 · **규칙 epoch**: `c11_avail:2026-09-24.b4:631e4f98` · **AS_OF**: 2026-09-01 · **행**: 272 (2004-02-02 ~ 2026-09-01)
**사유**: PIT-C11-P2-AUX ② — m4 발행 원장 구판 보관 후 C11 epoch 재초기화(런북 S7 · run 20260925_113012 · 확인: 도훈 2026-09-24 22시 채팅 · decision_register PIT-C11-M4-S7-APPLY)
**구판 보관**: `06_Registry/m4_published/_epoch_archive/20260925_113619_to_2026-09-24.b4_631e4f98` (원장·사이드카·드리프트 로그·PROVENANCE 복사 + md5 대조 · 이관본 *.live_at_reinit)

이 원장의 전 행은 C11 가용시점 결합 상류(unified 월간 avail 표식) 위에서 현행 factor_engine.R 로 재생성된 값이다.
구판 원장(수리 전 상류 · 2026-08-30 BOCPD 가드 결함 구간 라벨 포함)의 수치는 보관본에서만 인용한다.
재초기화 드리프트: 공통 271행 중 결정값 변경 20행 — 귀속 logic(입력 배경 수준)=4, regime=15, regime+bocpd+decay+base=1 (상세 `reinit_drift_report.json`).

이후 규칙 epoch 가 바뀌면 소비자(pg2 arm)가 epoch 불일치로 거부한다 — 상류 재빌드 뒤 이 스크립트로 다시 재초기화한다.
