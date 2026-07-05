# Self-Adversarial Challenge — DART document.xml 원문파서 빌드

**날짜**: 2026-07-05 | **검증자**: 메인 Opus 4.8 자체 적대검증 (v8.2, Charter §8 No Silent Override)

## Concern 1 (MEDIUM) — 파리티가 단일 월(2024-12, form v4.1)에만 수행
- **분류**: PARTIAL
- **근거**: net_change 추출은 별도로 5개 form-version(v2.8/3.1/3.8/4.0/4.1) 원문 테이블과 대조 검증됨.
  ACODE `MDF_STK_SUM` 셀은 전 버전 일관 존재·정확. 파리티 월은 fetch+parse+aggregate 체인을,
  5-버전 테스트는 form robustness 를 커버 — 둘 다 PASS.
- **잔여 한계**: 교차-버전 파리티는 elestock 커버리지(2024-03+)가 v4.x 만 담아 불가능(데이터 한계).
  → 더 강한 검증 불가는 코드 결함 아닌 baseline 데이터 제약.

## Concern 2 (LOW) — late-filing PIT 취약
- **분류**: ACCEPT (이미 올바르게 처리)
- **근거**: 2010 접수·2009 거래 사례 실측. 신호는 rcept_dt(공시 접수일) 기준 — 시장 인지 시점.
  MDF_DM(변동일자)은 정보용만. PIT 안전.

## Concern 3 (MEDIUM) — pre-2007 reporter-type 분류 감쇠
- **분류**: ACCEPT (문서화된 한계)
- **근거**: v2.8(2005~06) 은 STF_RYN/MAIN_SH sparse → 40/70 이 `other`. net-buy 주 신호는 전기간
  무결. officer-only 필터(연기금 기계적 매도 격리)는 2010+(v3.1+) 신뢰. 레코드 플래그 마킹 +
  PARITY_VERDICT.md 명시. 결함 아닌 form-version 데이터 한계.

## 합리화 자기검증
"미미/관행적/보수적이면 OK" 류 사용 없음. 모든 한계는 정량 근거(버전별 실측·필드 존재 여부) 기반.

## Escalate 판정
HIGH severity 0건 / AX axiom hard FAIL 0 / PIT C1 위반 0 → **escalate 불필요**.
