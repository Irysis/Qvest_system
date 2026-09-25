# PIT C11 표식 — 02_Infrastructure/ramp

**상태:** 위반(상속) — r15/r23 = apply_regime_overlay(V-06) · r24/r37/r38 = regime_daily_v2 VIX_z·주간 축(V-10·V-11) · r8/r9/v5_daily = Bear_Prob lag 처리 미확인(판정서 1-7) · ramp_shumulvey_features = FRED KRW_USD(=DEXKOUS, 금지 → ECOS_KRW_USD)  
**위반 근거:** V-06, V-10, V-11, CONVENTIONS ①  
**조치:** 표식만(코드·산출 무변경) — 도훈 결정 `PIT-C11-CONVENTIONS ⑦`(등급 체계 밖 소비자)

이 폴더의 코드는 해외(FRED) 시계열 또는 그 파생 패널(macro_regime · regime_daily_v2 · unified_regime_signal · apply_regime_overlay)을 가용 시점이 아니라 관측일·같은 달로 읽는다. 따라서 이 폴더의 산출·수치는 C11이 해소되기 전까지 결론의 근거로 인용하지 않는다. 다시 쓰려면 `02_Infrastructure/data/fred_availability.R`의 `fred_asof_join()`으로 결합을 고친 뒤 다시 측정해야 한다.

## 검출기 스캔 (2026-09-24, 읽기 전용)

- `ramp_shumulvey_features.R`: C11_PROHIBITED_SERIES@33

## 해당 파일

- `run_dfa_pg2overlay_r15.R`
- `run_dfa_pg2overlay_r23.R`
- `run_ramp_r15_emit.R`
- `run_ramp_r15_fill.R`
- `run_dfa_signal_align_r24.R`
- `run_dfa_persistent_signal_r37.R`
- `run_dfa_exposure_power_r38.R`
- `run_dfa_fm_exposure_r8.R`
- `run_ramp_r8_band_escalation.R`
- `run_dfa_exposure_r9.R`
- `run_ramp_shumulvey_v5_daily.R`
- `ramp_shumulvey_features.R`

## 참조

- 판정서: `04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md`
- 레지스트리: `06_Registry/pit_c11_consumer_notices.json` (id `ramp`)
- 격리: `06_Registry/pit_quarantine.json#PITQ-C11-20260924`
- 표식: 2026-09-24T12:20:00+0900 · S6_defense (PIT C11 수리 1단계 · decision_register PIT-C11-CONVENTIONS ⑦ 등급 체계 밖 소비자 = 표식만)
