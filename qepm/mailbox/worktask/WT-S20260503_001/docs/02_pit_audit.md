# STR_1715_LRO_v0.1 — PIT Audit Report (risk-research)

**WT_ID**: WT-S20260503_001
**Phase**: Risk Research
**Audit date**: 2026-05-04

---

## 1. PIT C1~C15 적용 결과

| Code | 위반 패턴 | LRO 적용 | 결과 |
|---|---|---|---|
| C1 | full-sample 통계 | rolling residualization 252d window. expanding median/MAD min_obs=24m | PASS — `_logs/01_*.R` + `_logs/02_rolling_268m.R` window strictly < sig_date |
| C2 | same-day circular | factor signal sig_d → return d+1 적용 (forge 단계). risk metrics는 daily (sig_d 이전 252d) | PASS |
| C3 | 같은 기간 집계→적용 | 252d window 종점 < sig_d. monthly factor panel = sig_d 첫 영업일 (panel은 prior month-end 기준) | PASS |
| C4 | 재무제표 lag | factor DB load_month_factors 경유 — quarterly 45d / annual May 자동 적용 | PASS (factor DB infra 책임) |
| C5 | overlay t-1 | LRI(t) close → state(t) → policy(t+1) (forge enforce) | PASS (risk research는 LRI까지만, t+1 실행은 forge) |
| C9 | VT/DD same-day | 본 LRO는 VT/DD 사용 X | N/A |
| C10 | liquidity t-1 | universe = monthly Top500 by Size (각 월 종점 직전 30d 평균 Size) | PASS — 30d window pre-sig_d |
| C11 | FRED 시차 | LRO는 FRED 미사용 (KR-only known factor 6 + sector dummy 11) | N/A |
| C13 | NEGATE_FACTORS | factor DB Z_Score_Aligned only (load_month_factors 경유) | PASS |
| C14 | IC Usable_Date <= sig_date | factor_db_connector v2.0 PIT-safe (Usable_Date <= sig_d enforced) | PASS |
| C15 | Factor DB 직접 load | load_month_factors() 경유 만 | PASS |

---

## 2. Single-rebalance audit (2024-12-31)

**`_debug/pit_audit_2024_12_31.json`**:

```
sig_date                       = 2024-12-31
window_start                   = 2024-03-24
window_end_actual              = ≤ 2024-12-30 (strict < sig_date)
window_endpoint_lt_sig_date    = TRUE
factor_db_pit_compliance       = "C13 / C14 / C15 enforced"
full_sample_grep_hits          = 0
factor_construction_pit        = "monthly factor sigs → daily long-short within month, t < sig_date"
pit_audit_pass                 = TRUE
```

`lookahead_detector.R` 자동 grep 패턴 (`mean(.*all.*)`, `quantile(.*data\\$`) 자체 코드에 사용 X. `pit_zscore_vec` 미사용 — 자체 expanding median/MAD 구현 (`expanding_zscore` in `_logs/02_rolling_268m.R` line ~270, `vals <- x[1:(i-1)]` strictly past).

---

## 3. Rolling 268m PIT 검증

268m × 252d window 모든 sig_date에 대해:
- `compute_one_sigdate(sig_d)` 내 `win_idx <- which(all_dates_a < sig_d & all_dates_a >= sig_d - WIN_DAYS - 30L)` — strictly `<` enforce
- `B_ref` IS endpoint 2024-06-30 1회 추정 후 freeze. 모든 OOS sig_date에 동일 B_ref 적용
- expanding z-score: `vals <- x[1:(i-1)]` past-only, current 제외
- 4-state quantile: IS subset (sig_date <= IS_END = 2024-06-30) 에서 q0.65/0.80/0.90/0.95 산출 후 모든 OOS에 동일 적용

---

## 4. lro_params_frozen SHA-256

```
file: stage_artifacts/WT_WT-S20260503_001/lro_params_frozen.json
SHA: a5c55fc8355b26af... (full SHA in JSON)
```

Forge 단계 verify_hash 의무. 다르면 schedule_fidelity FAIL.

---

## 5. 자기합리화 detect (LRO 특화)

| 패턴 | 자기 검증 결과 |
|---|---|
| (a) PC 경제명 고정 | 회피 — anchor는 label only, anchor R² 매우 낮음 (~10⁻¹⁰) → PC 경제명 고정 불가능. challenge note에 명시 |
| (b) full-sample 통계 단어 | 회피 — `vals[1:(i-1)]` past-only enforced |
| (c) OOS 결과 보고 후 K/threshold 변경 | 회피 — lro_params_frozen.json SHA-256 동결, forge verify |
| (d) defense-like 평가 회피 | judge 단계 의무. risk research는 LRI state 시계열만 제공 |
| (e) M4+LRO cash 충돌 | optimizer 단계 cash_definition_audit.json 5-field 의무. risk research는 LRI 시계열까지만 |
| (f) baseline metric 출처 미flag | 본 risk research는 baseline 사용 X. forge 단계 measurement_basis_audit 책임 |
| (g) latent을 alpha로 재해석 | 회피 — research design §1 명시 "latent을 alpha로 해석하지 않는다" |
| (h) M4 cash source 명시 누락 | optimizer 책임. 본 risk research는 M4 cash 미사용 |
| (i) topN expansion 본 WT 포함 | 본 LRO는 topN 미생성. matrix LRO_mon/cap/cash + M4+LRO_cap/cash만 |
| (j) alpha-research spawn 시도 | Q-Lead 4-파일 stub 사용 (alpha_package.json `inherited_alpha_stub` 6-field) |

---

## 6. 결론

**PIT C1~C15 위반 0건 + 자기합리화 패턴 0건**. risk_package_draft.json 작성 적격.
