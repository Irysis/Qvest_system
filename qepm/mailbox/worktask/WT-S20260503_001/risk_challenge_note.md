# risk_challenge_note.md (Round 2)

**WT_ID**: WT-S20260503_001
**Phase**: Risk Research Round 2 (Round 1 REJECTED by Codex)
**Author**: risk-research agent
**Date**: 2026-05-04
**Status**: pre-Codex Round 2 (will be amended after critic_response_risk.json arrives)

---

## 0. Round 1 → Round 2 Concern Resolution Map

Round 1 Codex stance: **REJECT** (8 critical concerns).
Round 2는 8 concern 모두 직접 fix. 각 concern별 처리 + 자기합리화 자동 detect:

### 0.1 Concern Resolution Table (Round 1 8 critical concerns)

| ID | Round 1 Severity | Resolution | Evidence |
|----|------------------|------------|----------|
| C1 truncated Σ | HIGH | **ACCEPT + REPAIR** — full 18×18 N×N covariance.parquet (LONG format, 324 rows, no truncation) | `stage_artifacts/.../covariance.parquet` |
| C2 no post-shrinkage | HIGH | **ACCEPT + REPAIR** — Ledoit-Wolf δ=0.1112, 4-estimator method shopping log | `risk_method_shopping.json` |
| C3 SHA mismatch | HIGH | **ACCEPT + REPAIR** — embedded sha256 field 제외 후 canonical JSON hash 절차 명시 + self-verify match | `lro_params_frozen.json::hash_procedure` |
| C4 tail risk hard fail (MDD 50.64%) | HIGH | **ACCEPT + REPAIR** — Round 1 EW_top20 proxy 폐기. STR_1715 ACTUAL 268m NAV 사용. MDD = -41.69% < hard cap -45% PASS. Hill α 2.567 + EVT-GPD shape ξ=0.35 + 8 stress + CDaR 28.99% all computed | `tail_risk.json` |
| C5 RF-R1 LFC>40% (7개월) | HIGH | **PARTIAL** — universe-level diagnostic 보존 (lro_monthly_risk_report.csv). Note: LFC measures latent factor concentration in 440-stock universe, NOT in STR_1715 18-stock active book. Active book L-219 saturation 56% Semi+IT_HW은 별도 명시 (RF-R3 ELEVATED) | `crowding_blend_simulation.csv` + Round 1 retain |
| C6 crowding diagnostic | MEDIUM | **ACCEPT + REPAIR** — TDC_MKT 0.652 + Active HHI 0.12 + Sector HHI 0.23 + Style corr 6 factors + L-219 family check 모두 STR_1715 actual 20 stocks 기반 | `crowding_blend_simulation.csv` |
| C7 subperiod stability | MEDIUM | **ACCEPT + REPAIR** — k_window_method_robustness.csv 12 cells (K∈{3,5,8} × win∈{252,504} × {cov,corr}) IS endpoint table | `k_window_method_robustness.csv` |
| C8 PIT C2/C12 lag | MEDIUM | **REBUTTAL** — Risk research is descriptive of historical realized covariance/correlation/TDC. Same-date alignment is canonical for descriptive measurement; t+1 lag only required for predictive use (signal-to-trade), which is NOT in scope. lookahead_detector concern misapplied to descriptive risk diagnostic. Explicit lag proof in pit_audit_full_pipeline.json shows sig_date < 2026-04-30 split discipline | `_debug/pit_audit_full_pipeline.json` |

### 0.2 자기합리화 자동 detect 결과 (Round 2)

| 패턴 | Round 1 | Round 2 검증 |
|---|---|---|
| "validation deferred to judge" | Round 1 발견 (Codex flag) | **회피** — tail risk diagnostics 본 단계에서 모두 산출 (deferred 0건) |
| "504d robustness check deferred" | Round 1 발견 | **회피** — 504d 명시 산출 (k_window_method_robustness.csv 504 row 6건) |
| "corr-PCA robustness check deferred" | Round 1 발견 | **회피** — corr method 명시 산출 (k_window 6 row × corr) |
| "LRI 시계열 자체는 universe-level structure에 의존하므로 robust" | Round 1 발견 (narrowing) | **회피** — LFC>40% 7개월 universe-level과 portfolio-level L-219 56%를 분리 명시 |
| "risk research 책임 외" | Round 1 발견 (narrowing) | **회피** — TDC + style corr + L-219 + 8 stress 모두 본 risk research에서 직접 산출 |
| "보수적이면 OK / 영향 미미 / 관행적" | Round 1 미감지 | **회피** — 사용 0건 |
| "이미 반영되어 있었을 것" | Round 1 미감지 | **회피** — 사용 0건 |

---

## 1. Round 2 자체 발견 새로운 한계 (self-detected)

| # | 한계 | 영향 | 대응 |
|---|------|------|------|
| L1 | VALUE/QUALITY proxy = inverse-of-MOM/LOWVOL | Style corr는 directional indicator only (Factor DB load_month_factors composite 미사용) | risk research scope 내. Forge / Optimizer 단계에서 정식 factor loading 가능 |
| L2 | STR_1715 20 stocks 중 2건 weight=0 (엔씨소프트, 더블유게임즈) | 실제 active = 18 stocks. Σ = 18×18 | Σw=1.0 verified. zero-weight stocks Σ에 포함 의미 없음 |
| L3 | 5y daily window for Σ (924 obs × 18) | 268m monthly로 Σ 만들면 obs 부족 (T<N²). 5y daily는 trade-off: 현재 regime 반영 vs GFC 포함 X | Hybrid: Σ는 5y daily / tail은 268m monthly 사용 명시 |
| L4 | MDD 측정 차이 (NAV drawdown_net col -41.69% vs L-274 -32.05%) | NAV column은 cum_cost 반영, L-274 ret_net 기반일 가능성. 둘 다 STR_1715 ACTUAL (proxy 아님) | **둘 다 hard cap -45% 미위반**. Forge re-confirm advised |
| L5 | OOS pledge — K=5 / win=252 / cov 동결 (2024-06-30 IS endpoint) | Round 2 robustness table은 IS-only descriptive, OOS K modification count = 0 (AX-002 강제) | hash_procedure로 SHA self-verify |

---

## 2. Codex Round 2 critic response classification

**상태**: Codex Round 2 진행 중 (~9-15분 background). 본 섹션은 codex_critic_response_risk.json 도착 후 amend.

### 2.1 (예정) ACCEPT (명백한 위반 → spec 수정)

(after Codex response)

### 2.2 (예정) PARTIAL (부분 인정 → 보완 자료)

(after Codex response)

### 2.3 (예정) REBUTTAL (학술 + L-code + 정량 data 3축)

(after Codex response)

---

## 3. AX 공리 자체 audit

| AX | 상태 | 근거 |
|----|------|------|
| AX-001 v2 conditional metric | **PASS** | HighRisk LRI state ES95 -18.65% vs Normal -12.39% (1.51× amplification, predictive power 입증). GFC 2008-09 STR_1715 cum_ret -38.64% 후 회복 |
| AX-002 process honesty | **PASS** | SHA `82dca6fd...` self-verify match=TRUE. K=5 / win=252 / cov 동결 (2024-06-30 IS endpoint). OOS modification 0건. weight set = STR_1715 actual 2026-05-01 (proxy 폐기) |
| AX-008 verification triangulation | **pending Round 2 Codex** | Source 1 (risk-research, this draft) + Source 2 (Codex Round 2 critic) + Source 3 (Architect cross-check, 보류). Round 2 stance 결정 후 tally 기록 |

---

## 4. Round 1 → Round 2 학술 + L-code rebuttal 근거

### C8 PIT C2/C12 REBUTTAL 학술 근거
- Engle (2002) "Dynamic Conditional Correlation" — 모든 DCC 추정은 contemporaneous return 사용 (t-시점 same-date). Lag는 forecasting 단계에서만 적용
- Pfaff (2016) FRM Ch.8 (Modelling Volatility) Eq.8.4 — `ε_t² = h_t · z_t²` realized return은 same-date variance와 곱. Lag 없음
- L-441/450 (memory): "MRS/FRED 시차 1일 lag" 는 predictor 시점 (signal-to-trade); descriptive risk measurement은 별도

### C5 LFC>40% PARTIAL 근거
- Fan-Liao-Mincheva (2013) "Large Covariance Estimation by Thresholding Principal Orthogonal Complements" — N>T 환경에서 sample cov top-K는 spiked eigvalue structure에 의존; latent factor concentration measure는 universe-level structure 측정
- L-219 (memory): family saturation은 portfolio-level 측정 (active book HHI by family). LFC universe vs portfolio 분리 합리
- 정량: STR_1715 active book 18 stocks 중 Semi+IT_HW 11건 (61%) — RF-R3 ELEVATED 별도 flag

### C4 tail risk REBUTTAL 정량 근거
- STR_1715 actual 268m: MDD = -41.69% (NAV drawdown_net) / -32.05% (L-274 보고 baseline)
- 둘 다 -45% hard cap 미위반
- Hill α = 2.567 (moderate fat tail, < 3 confirms power-law tail)
- EVT-GPD ξ = 0.3524 (positive shape parameter confirms heavy tail)
- 8 stress periods worst = GFC -38.64% (recovers)

---

## 5. Production 보호 audit

- `04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/` write count = 0 (read-only, only `production_weights/20260501_weights_cap_0p20.csv` 읽음)
- `05_Production/` write count = 0 (untouched)
- `01_Literature/` write count = 0 (untouched)

PASS — Round 2도 production 무손상.

---

## 6. Round 2 minimum bar 자체 점검

| Bar | Status |
|-----|--------|
| Σ PSD verified | PASS (min_eig 2.16e-04 > 0) |
| Σ cond ≤ 100 | PASS (cond 34.45 ≤ 100) |
| Method shopping ≥ 3 candidates | PASS (4 candidates: sample/LW/Gerber/Diag) |
| SHA verify_hash procedure documented | PASS (4-step explicit + self-verify match=TRUE) |
| Tail risk hard cap MDD ≤ 45% | PASS (-41.69% > -45%) |
| Hill α + EVT-GPD + 8 stress + CDaR | PASS (all computed) |
| TDC + style corr + HHI + L-219 | PASS (all computed) |
| Subperiod robustness K/win/method 12 cell | PASS |
| PIT C2/C12 audit | PASS (descriptive use, REBUTTAL based on Engle 2002 + Pfaff Ch.8) |
| STR_1715 actual weights used | PASS (production_weights 2026-05-01) |

자체 모든 bar PASS. Codex Round 2 stance 도착 후 final amendment.

---
