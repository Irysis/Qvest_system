# F6 출력별 신선도 감사 — 설치 보류 후보(2026-11-06)

- `freshness_audit.R` = 운영본(02_Infrastructure/ops/morning_steps/freshness_audit.R · MSM as-of 변경 포함) 사본에 F6(출력별 신선도 · 최신일 채움 · 최근 L 거래일 구멍)을 넣은 판. `freshness_audit.R.diff` = 운영본 대비.
- `test_freshness_audit_outputs.R` = 그 시험(`--audit <사본 경로>` 로 이 후보를 잰다 · 기본값은 운영본).
- 보류 사유: 2차 독립 검증의 낮은 등급 결함 — 창 밖 유지 토큰 뒤 E 첫날 새 구멍 침묵(cont 인접성) · 지평선 앞당김(after_horizon) 시험 공백 · 본문 사유 줄 생략 단정 공백 · 측정 불가 시 BEHIND 토큰 접힘(통지 2회) · 상태 교체 반환값 미확인. 원장 = 워크플로 wf_42ba394f-f68 journal(F6b).
- 설치 = 위 결함 수리 · 재검증 뒤 운영본 교체(리프레시 비실행 시) + 시험 08_Tests/data 이동 · SUITES 편입.
