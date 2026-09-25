# PIT C11 표식 — 04_Research/strategies/STR_943_oc_eps_chg

**상태:** 위반(동월 조회)  
**위반 근거:** V-14  
**조치:** 표식만(코드·산출 무변경) — 도훈 결정 `PIT-C11-CONVENTIONS ⑦`(등급 체계 밖 소비자)

이 폴더의 코드는 해외(FRED) 시계열 또는 그 파생 패널(macro_regime · regime_daily_v2 · unified_regime_signal · apply_regime_overlay)을 가용 시점이 아니라 관측일·같은 달로 읽는다. 따라서 이 폴더의 산출·수치는 C11이 해소되기 전까지 결론의 근거로 인용하지 않는다. 다시 쓰려면 `02_Infrastructure/data/fred_availability.R`의 `fred_asof_join()`으로 결합을 고친 뒤 다시 측정해야 한다.

## 검출기 스캔 (2026-09-24, 읽기 전용)

- `run_all.R`: C11_MRS@108, C11_FRED_SAMEDATE@46

## 참조

- 판정서: `04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md`
- 레지스트리: `06_Registry/pit_c11_consumer_notices.json` (id `STR_943_oc_eps_chg`)
- 격리: `06_Registry/pit_quarantine.json#PITQ-C11-20260924`
- 표식: 2026-09-24T12:20:00+0900 · S6_defense (PIT C11 수리 1단계 · decision_register PIT-C11-CONVENTIONS ⑦ 등급 체계 밖 소비자 = 표식만)
