# PIT C11 표식 — 04_Research/strategies/STR_798_adaptive_vt

**상태:** 미검증(macro_regime 소비 — 판정서 1-7 '레거시 24개 폴더' A 조사 단독)  
**위반 근거:** V-14  
**조치:** 표식만(코드·산출 무변경) — 도훈 결정 `PIT-C11-CONVENTIONS ⑦`(등급 체계 밖 소비자)

이 폴더의 코드는 C11 오염이 확정된 파생 패널(macro_regime · regime_daily_v2 · unified_regime_signal)을 읽는다. 결합 방식(같은 달 여부·lag)은 이 표식 단계에서 검증하지 않았다. 따라서 이 폴더의 산출·수치는 C11이 해소되기 전까지 결론의 근거로 인용하지 않는다.

## 검출기 스캔 (2026-09-24, 읽기 전용)

- `run_all.R`: C11_MRS@179, C11_FRED_SAMEDATE@124, C11_FRED_SAMEDATE@179

## 참조

- 판정서: `04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md`
- 레지스트리: `06_Registry/pit_c11_consumer_notices.json` (id `STR_798_adaptive_vt`)
- 격리: `06_Registry/pit_quarantine.json#PITQ-C11-20260924`
- 표식: 2026-09-24T12:20:00+0900 · S6_defense (PIT C11 수리 1단계 · decision_register PIT-C11-CONVENTIONS ⑦ 등급 체계 밖 소비자 = 표식만)
