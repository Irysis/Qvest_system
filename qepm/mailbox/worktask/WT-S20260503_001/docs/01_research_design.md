# STR_1715_LRO_v0.1 — Research Design (risk-research)

**WT_ID**: WT-S20260503_001
**Phase**: Risk Research
**Date**: 2026-05-04
**Author**: risk-research agent

---

## 1. 본질

STR_1715 PG2 100% live (L-274). 268m: CAGR 43.78% / SR 1.7477 / MDD -32.05%. MDD -7.05pp 초과가 진짜 잔여 gap.

**LRO 가설**: STR_1715의 잔여 risk는 known KR factor (MKT/SIZE/VALUE/MOM/QUALITY/LOWVOL) 잔차에 hidden common risk가 있다 — sector / theme crowding (Semi-AI / 신재생 / Bio) + earnings revision crowding + top-name concentration. 이를 **PCA로 측정** + **risk overlay (cap tighten / cash overlay)** 로 보수화하면 MDD 개선.

**중요**: latent factor를 alpha로 해석하지 않는다. LRO는 risk lens. STR_1715 alpha engine + ranking 무손상.

---

## 2. 메서드 선택 + 정당화

| 단계 | 선택 | 근거 |
|---|---|---|
| Residualization | Rolling regression on 6 known KR factor + 11 sector dummies (252d window, t<sig_date) | Sharpe et al. (1992)/Fama-French residual 표준. sector dummy 강제 = sector beta 재발견 차단 |
| PCA | covariance, K=5 | LRS = (x_k² λ_k)/σ_p² 가 portfolio variance와 직접 연결되려면 cov 단위 PCA 필요. cor PCA는 standardize 후 가공 단계 추가 — 본 LRO는 직접 risk decomposition 우선 |
| K freeze | IS endpoint 2024-06-30 | OOS 24m+ 보장. K∈{3,5,8} 비교 후 5 선택 (eigenvalue gap relative ≥ 0.0225 OK, debug PASS) |
| Alignment | Orthogonal Procrustes B_t→B_ref | rolling PCA의 sign-flip + permutation 안정화. Schönemann (1966) 표준 |
| z-score | Expanding median/MAD, min_obs=24m | Hampel (1974) robust. mean/sd는 outlier에 취약. 1.4826 = Gaussian consistency |
| State 4-buckets | IS quantile (q0.80/0.90/0.95) + hysteresis (entry q0.80, exit q0.65) | Threshold 진동 방지 — Hamilton (1989) regime switching의 hysteresis 응용 |
| LRI weights | LFC 0.25 / LHHI 0.20 / D_t 0.20 / ARS_Revision 0.15 / ARS_Momentum 0.10 / Top3MRC 0.10 | request.json 명시. concentration (LFC+LHHI+Top3MRC=55%) + drift (D_t=20%) + crowding theme (ARS=25%) 균형 |

---

## 3. 데이터 + universe

- RAWDATA: 03_Universe → .cache/RAWDATA.parquet (1990-2026.04)
- Factor DB: 02_Infrastructure/factor_db monthly parquets (442 files, 1990-01~2026-05)
- Universe: KOSPI200 ∪ KOSDAQ150 proxy = monthly Top500 by Size (간소화. 실제 universe filter는 forge 단계 STR_1715 universe와 align)
- 268m: 2004-02 ~ 2026-04 (sig_dates first business day of each month)

---

## 4. PIT 검증

| 위반 위험 | 차단 |
|---|---|
| residualization 미래 leak | window=[t-252, t-1] right-closed exclusive. lookahead_detector.R 기준 window endpoint < sig_date 검증 |
| factor DB look-ahead | load_month_factors(sig_d) 경유 (C13~C15). align_factor_direction PIT-safe (Usable_Date <= sig_date) |
| K/threshold OOS 변경 | lro_params_frozen.json SHA-256 동결. forge 동일 SHA verify_hash |
| B_ref OOS 재추정 | IS endpoint 2024-06-30 1회 추정 후 freeze |
| z-score full-sample | expanding median/MAD min_obs=24m. burn-in 이전 NA |
| 4-state quantile ex-post | q0.65/0.80/0.90/0.95 모두 IS-frozen (sig_date <= IS_END subset) |
| anchor regression contamination | 10 anchor IS에서 freeze. R²>0.7 sector면 LFC 재정의 trigger (현재 anchor R² ~10⁻¹⁰ 매우 낮음 → re-define 불필요, 이는 known factor 잔차 latent이 anchor와 직교 = 의도된 결과) |

---

## 5. Single-rebalance debug 결과 (2024-12-31)

**debug_pass.json overall_pass=true** (9 field 모두 PASS):

| Field | Value |
|---|---|
| pit_audit_pass | TRUE |
| lri_value_sane | TRUE (0.0642) |
| mrc_sum_close_to_sigma2 | TRUE (residual 1.36e-20) |
| anchor_R2_all_present | TRUE (10 anchor × K=5 = 50 R² values) |
| eigenvalue_gap_above_1e_3 | TRUE (relative gap cov 0.0225 / cor 0.0426) |
| procrustes_alignment_quality | TRUE (frobenius 0 — single-point B_ref==B_t) |
| residual_no_lookahead_grep | TRUE (window strictly < sig_date) |

**핵심 발견** (single point):
- IdioShare = 0.9759 → STR_1715의 risk는 latent common이 아닌 **idiosyncratic dominant**
- Top3MRC = 0.6122 → portfolio risk의 61%가 top 3 stock 기여. **top-name concentration이 risk의 진짜 source**
- LFC = 0.0118 (1.2%) → 어떤 단일 latent factor도 risk explanatory power ≤ 1.2%
- anchor R² ~10⁻¹⁰ → known factor 잔차 latent은 sector/theme anchor와 직교 (sector beta 재발견 차단 성공)

**해석**: LRO의 risk overlay 효과는 latent common (LFC 작음) 보다 **stock concentration (Top3MRC 큼)**에 더 민감. 이는 cap tightening (0.20→0.15) 이 cash overlay보다 효과적일 가능성 시사 → optimizer/forge 단계 검증 대상.

---

## 6. 268m rolling 산출물

- `lro_monthly_risk_report.csv`: 월별 LFC/LHHI/IdioShare/Top3MRC/D_t/ARS_*/Z_*/LRI/state
- `lro_policy_state.csv`: 월별 4-state + transition flag
- `lro_factor_mapping.csv`: 월별 PC ↔ top-anchor R²
- `anchor_map.json`: IS freeze + OOS 비교
- `B_ref.parquet`: IS endpoint 잠재요인 loadings (frozen)
- `covariance.parquet`: 마지막 sig_date Σ = B Λ B' + D (latent + idio)
- `residuals.parquet`: 마지막 window U_t panel (illustrative)
- `tail_risk.json`: state-conditional VaR/ES/CDaR
- `lro_params_frozen.json`: AX-002 동결 SHA

---

## 7. AX 공리 적용

| AX | 적용 |
|---|---|
| AX-002 | lro_params_frozen.json SHA-256 동결. forge 동일 SHA verify_hash 의무 |
| AX-008 | 본 risk research = Source 1 (Forge bt_result 기반). Codex critic = Source 2. Architect cross-check = Source 3 (judge 단계). 3-source tally PASS≥2 필요 (PASS verdict 시) |

---

## 8. Limitations / Self-detected

(challenge note에 정식 기록)

a) Universe proxy = monthly Top500 by Size — 실제 KOSPI200∪KOSDAQ150 정확하지 않음. forge에서 실 universe로 align 필요.
b) Daily factor return 합성 = top30%/bottom30% spread 단순 long-short. KR-specific FF-style portfolio 구축 (size+BM 2x3 sort)이 더 정확하나 본 LRO 범위 밖.
c) STR_1715 weight proxy = EW_top20 by Size at each month — 실제 STR_1715 grid Best (linear tilt + TOphi penalty + cash overlay) 와 다름. portfolio decomposition (LFC/Top3MRC/ARS)는 forge 단계 실 weight로 재산출 필요. risk research는 latent risk **infra** + **methodology**를 제공.
d) Sector dummy 11 → 실제 KOSPI 33-sector 일부 통합 (top11 + Other). semi-AI / 신재생 / Bio 등 theme이 sector level에서 분산 → ARS 계산 시 sector aggregation 부정확.
e) Anchor "Revision" proxy = QUALITY_KR — proper revision factor (analyst EPS revision)이 factor DB에 없어 placeholder. label only로 사용.
f) corr-PCA 비교 미실행 — debug에서 cov 채택. corr 비교는 robustness check로 충분 가치 있으나 본 LRO는 cov 직접 risk decomposition 우선. 추후 robust check 가능.

---

## 9. Decision

**risk_package_draft.json 작성 → Codex Round → final risk_package.json**.

본 risk research는 LRO infra + lro_params_frozen + monthly LRI/state 시계열을 **확정**. portfolio-level decomposition은 forge에서 실 STR_1715 weight 적용 시 정확.
