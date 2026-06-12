# Advisory: C19 "방어 프로파일(MDD 21%)" = 1개월-stale 신호 아티팩트 (FR/RCMA 소비자 고지)

- 발행: 2026-06-12 (Composition Search Cycle 2, Track C)
- 근거: Cycle 1b Track V 확정 발견 — `04_Research/composition_search/cycle1b_trackV/variation_results.json`
- metric_type: canonical_screen (Track V 측정), 데이터 2026-04-30 절단 규율 하 측정

## 1. 발견 요지

registry에 등재된 `STR_C19_Composite_Earnings_LO_top25`의 "방어 프로파일"(MDD 20.97%, Sharpe 0.865, CAGR 12.28%)은
**신호를 1개월 stale하게 적용하는 측정 경로의 아티팩트**다.

- 원인: `stage_artifacts/alpha_search/driver_lo_screen.R`의 same-grid 구성 — weights와 forward return을 동일 날짜(ret_date)로 dcast 후 `Return.portfolio` 투입 → 신호 weight가 1개월 늦게 적용됨 (`probe_env.R` Case B로 기전 입증).
- 입증 (Track V, `variation_results.json`):
  - **B4 driver 재현** (stale 동일그리드 verbatim 복제): MDD **20.968%** — registry 20.97%와 정확 일치 → registry 수치 = stale 경로 산출 확정.
  - **B4_BASE 보정 타이밍 재측정** (신호→익월 정상 정렬): **MDD 43.349% / CAGR 18.899% / SR_net 0.759** (full 2005~, n=257).
- 해석: C19의 저MDD는 알파/방어 특성이 아니라 측정 결함. 보정 타이밍에서는 고MDD 고CAGR 일반 core 프로파일.

## 2. 조치 완료 (registry caveat 전파)

기존 수치 삭제/덮어쓰기 없이 `measurement_caveat` 필드만 append:

- `06_Registry/module_performance.json` → `modules.STR_C19_Composite_Earnings_LO_top25.measurement_caveat`
- `06_Registry/module_catalog.json` → `modules.STR_C19_Composite_Earnings_LO_top25.measurement_caveat`

주의: 두 파일은 빌더 스크립트(build_module_performance.R / register_module)가 재생성·재등재할 수 있음 — 재생성 시 caveat 유실 가능. 빌더에 caveat 보존 로직 또는 stale-driver 재측정이 후속 과제.

## 3. RCMA / FR 채택 여부 (영향 범위)

**결론: RCMA는 C19를 채택하지 않았다. 소비 영향 없음 (2026-06-12 기준).**

- `06_Registry/module_regime_admission.json` (RCMA): `STR_C19_Composite_Earnings_LO_top25`는 **5개 국면(RISK_ON/NEUTRAL/CAUTION/CRISIS/RISK_OFF) 전부 `admitted: false`** (rationale: review_pending). 방어(CRISIS) specialist 채택 없음.
- `06_Registry/factor_rotation_registry.json` (FR_001, 유일 FR): module_pool 92종에 C19 LO 모듈 **불포함**. allocation_policy = "rp+IR shrink + RCMA admitted"이므로 미admit 모듈은 어차피 배분 제외.
- 혼동 주의: RCMA admitted 목록의 `STR_1566_c19_l22_blend` / `STR_1567_c19_l22_*` / `STR_1570/1571/1572_c19_*` 등은 **C19 팩터를 쓰는 legacy(v55-era) 전략**으로, 측정 경로가 lo_screen driver가 아닌 자체 sim_result — 본 아티팩트 의심군 아님 (단, C19 팩터 자체의 방어성 주장 인용 시 본 advisory 참조 권장).
- 함의: 향후 RCMA review_pending 해소/재심사 시 C19의 per_regime mdd(RISK_ON 0.128 등 registry 수치)도 동일 stale 경로 파생이므로 **보정 타이밍 재측정 전 채택 금지** 권고.

## 4. 동일 아티팩트 의심군 (1차 스캔 — 목록만, 재측정은 후속)

같은 same-grid driver family로 측정·등재된 모듈. registry(module_performance.json / module_catalog.json) headline 수치(특히 MDD·Sharpe)가 1개월-stale 적용일 개연성:

**(a) driver_lo_screen.R 경유 23종** (stage_artifacts/alpha_search/lo_screen/*.json → STR_*_LO_top25):
STR_AC09_NNI / STR_AC13_Abnormal_Accruals / STR_AC24_NOA_Growth / STR_C16_EPS_Acceleration / **STR_C19_Composite_Earnings(본건)** / STR_CR01_Sector_Comovement / STR_CR02_Volume_Concentration / STR_CR04_Ownership_Concentration / STR_CR05_Short_Pressure_Proxy / STR_CR06_DTC_Proxy / STR_CR07_Momentum_Crowding / STR_CR08_Volume_Price_Divergence / STR_CR09_Money_Flow_Ratio / STR_CR10_Convergence_Premium / STR_CR11_Idiosyncratic_Return / STR_IN01_CapEx_to_Assets / STR_IN02_CapEx_to_Revenue / STR_IN05_Net_Debt_Issuance / STR_V10_FCF_Yield / STR_V15_NetDebt_Adj_EP / STR_V17_Payout_Ratio / STR_V19_Debt_to_Market / STR_V21_Composite_Equity_Issuance (전부 `_LO_top25`)

**(b) 동일 구성 개별 driver 4종** (코드 검사로 same-grid dcast 확인):
- `STR_str1715v2` (driver_str1715v2_lo.R — Track V B2 repro로 stale 입증, 보정 base: SR 0.809/MDD 47.3 vs registry 0.911/39.2)
- `STR_str1715v3` (driver_str1715v3_lo.R — 헤더에 "driver_str1715v2_lo.R 복제" 명시)
- `STR_valearn_70_top25` (driver_valearn_lo.R)
- `STR_IN04_top25` (driver_in04_lo.R)

총 **27종**. RCMA 채택 현황: **27종 전부 미admit** (admitted=false 또는 RCMA 미등재) — FR_001 pool에는 STR_str1715v2 / STR_valearn_70_top25가 후보로 포함돼 있으나 RCMA 미admit이므로 현 배분 영향 없음. 단, 향후 재심사·pool 갱신 전 보정 타이밍 재측정 필수.

**의심군 제외**: forge/build_bt_result 경유 모듈(STR_1715 본체 등), run_monthly_simulation daily NAV 경유(B3 VALMOM 등), legacy v55 sim_result — 측정 경로 상이.
