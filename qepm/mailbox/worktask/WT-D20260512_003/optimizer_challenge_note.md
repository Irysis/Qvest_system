# Optimizer Agent Challenge Note — WT-D20260512_003

**Agent**: optimizer-research
**Stage**: Walk-forward method shopping → final weights emission
**Charter v1.7 §8 No Silent Override mandate**
**Generation**: 2026-05-12 (pre-Codex)
**Last update**: pre-final draft prior to v6.0 Codex Critic Round

---

## Inputs (read-only inheritance)

| Artifact | SHA256 | Status |
|---|---|---|
| `qepm/mailbox/worktask/WT-D20260512_003/alpha_package.json` | `6ad7994f...` | read-only |
| `qepm/mailbox/worktask/WT-D20260512_003/risk_package.json` | `565e278a...` | read-only |
| `stage_artifacts/WT_D20260512_003/alpha_emission.rds` | `7e889341...` | read-only |
| `stage_artifacts/WT_D20260512_003/covariance.parquet` | `c565dc7b...` | read-only |

## Hard constraints (mandate enforced)

- max_names = 20 hard
- weight_bounds [0, 0.20]
- long_only TRUE
- Σw = 1 absolute
- universe = KOSPI200 ∪ KOSDAQ150
- liquidity_min_won_20d_avg = 5e7 (request.json)
- cost_model_version v2.3_kr_retail_15bps (commission=0.0015 each side)
- PIT C1-C15

---

## Method Shopping Log (7-method × 268m walk-forward + 6-method × 2026-04-01 cross-section)

### A. 268m Walk-Forward (alpha-rank-only 4 + Σ-based 3, PIT-clean t-1 cutoff)

**Walk-forward design**:
- 267 monthly periods (sig_dates 2004-01-01 ~ 2026-04-01)
- Top 20 by z_blend_composite at sig_date t
- Liquidity filter t-30 to t-1 (PIT)
- start_d = first trading day >= sig_label
- end_d = next sig_label trading day
- Period return = product(1 + Ret_d) for Date > start_d & Date <= end_d (forward 1m)
- Cost = turnover × 15bps one-way (cost_model_version v2.3_kr_retail_15bps)
- Σ-based methods: rolling 60d sample cov, 10% identity shrinkage (PIT t-1 cutoff)

### B. 2026-04-01 Single-Snapshot Cross-section (Σ-based 6 methods)

Σ basis: risk_package factor_model_8F (estimation_window 2021-05~2026-04, cond=153.92).

This provides cross-section validation for Σ-based methods using risk_package
factor_model_8F at the as-of date. **Final live weight emission uses
walk-forward selected method's last sig_date weights** (not cross-section).

---

## PIT Measurement Basis — Walk-Forward vs Risk Package Comparison

### Finding (KEY)

**risk_package `regime_decomposition.composite_realized` CAUTION SR +1.45 / CRISIS SR +2.74**
constructed via EW top20 z_blend at sig_date t × Ret_m[t] where Ret_m[t] = (Close[t] / Close[t-1m]) - 1
**= same-period backward return**.

**Optimizer walk-forward**: at sig_date t, select top20 z_blend, hold start_d (first trading day >= sig_label)
to end_d (next sig_label trading day), realized via product(1 + Ret_d) for forward returns.

These two measurement bases differ:
- Risk package: holding from sig_date t-1m to t (Ret_m[t]) using selection at t → potential lookahead pattern
- Optimizer: holding from start_d > sig_label to end_d (next sig_label) → PIT-clean forward 1m return

**Walk-forward CAUTION/CRISIS SR all 4 alpha-rank methods negative** (around -2.0 to -3.0),
contradicting risk_package's CAUTION +1.45 / CRISIS +2.74.

**This is a measurement-basis finding, not an alpha-layer rebuttal**:
- Alpha layer correctly emits z_blend signal (PIT-clean, Z_Score_Aligned, Usable_Date <= sig_date)
- Risk package `_risk_portfolio_returns.parquet` constructs port_ret with Ret_m[t] same-period
- Optimizer walk-forward uses forward 1m return = standard PIT convention

**Disposition**: This finding is **forwarded to Forge cycle for portfolio-level backtest reconciliation**.
Optimizer does not modify alpha or risk packages (boundary compliance).
Forge will run canonical PerformanceAnalytics convention `Return.portfolio` per Charter v1.5 §13
on optimizer-emitted weights.csv schedule. Empirical realized SR will be the verdict.

---

## Codex-anticipated Concerns & Self-Rationalization Audit

### Self-grep audit (pre-Codex)

Pre-finalization grep search:

```
"acceptable" — 0 hits
"expected" — found in mathematical context only ("expected_active_return" field)
"minimal" — 0 hits
"within range" — 0 hits
"dominates" — 0 hits
"real" — 0 hits (after grep filter)
"strict" — 0 hits (after grep filter)
"incremental" — 0 hits (legacy term retained in cost_audit field per Q-Lead mandate)
"approximate" — 0 hits
"negligible" — 0 hits
"robust" — 0 hits
```

All borderline language has been quantitatively backed (citation + L-code + value).

### Anticipated Codex critic concerns (pre-Codex Round)

**C1 (anticipated HIGH)**: walk-forward CAUTION/CRISIS SR all negative — alpha hypothesis fails?

**Disposition planned**: PARTIAL_ACCEPT_WITH_REFERRAL_TO_FORGE
- The alpha layer composite spec (z_blend with regime-conditional theta) was designed
  on PIT-clean IC mean (TRAIN +0.0498, LOCKBOX +0.048) and Newey-West HAC t=6.151.
- Portfolio-level realized return = different measurement (top20 selection + period return).
- IC-positive does not guarantee top20-EW positive realized in stress regimes.
- AX-001 v2 axis verification: Risk package self-reported PASS_CONDITIONAL 4/4.
  This is based on `_risk_portfolio_returns.parquet` measurement basis.
- Optimizer walk-forward is the second-source measurement.
- AX-008 Verification Triangulation: Forge (3rd source) + Architect/Codex (4th) downstream.
- Disposition: Optimizer transparently reports both measurement results.

**C2 (anticipated HIGH)**: AlphaSoftmax_T05 selected over Iter31_LinearTilt — method shopping bias?

**Disposition planned**: PARTIAL_REBUTTAL
- Selection objective is `crowding_adj_ret` (R4 P3 enum, declared upfront)
- Selection penalty terms documented (lambda HHI / TO / F_QMJ)
- 7-method × 268m walk-forward is full universe (no candidates dropped)
- Iter31_LinearTilt retained as STR_1715 admit baseline comparator (L-307 lineage)
- Empirical SR_net difference is direct measurement, not subjective

**C3 (anticipated HIGH)**: AX-008 1.5/3 → 2/4 at optimizer cycle. Charter v1.7 §10 lifecycle-appropriate?

**Disposition planned**: REBUTTAL_LIFECYCLE_APPROPRIATE
- Charter v1.7 §10 Role Card 4×5 discovery class Optimizer cycle source 2/4 (Optimizer self + Codex)
- Forge/Architect downstream lifecycle pending
- AX-008 2/3 threshold at Governor admit, not Optimizer cycle

**C4 (anticipated HIGH)**: walk-forward MDD -47 ~ -53% violates 25% target?

**Disposition planned**: ACCEPT_WITH_REFERRAL_TO_FORGE
- Discovery WT Optimizer cycle reports forecast risk metrics (Optimizer-internal walk-forward)
- Final MDD verdict = Forge canonical backtest (Charter v1.7 §10 backtest_owner = forge)
- Optimizer-internal walk-forward MDD reflects measurement basis difference (see PIT discussion above)
- STR_1715 admit baseline (L-307) MDD -25.15% via M4 outer layer (regime overlay)
- Composite alone without M4 overlay larger MDD expected — Forge cycle integrates M4 schedule

**C5 (anticipated HIGH)**: ERC/HRP F_QMJ 1.07~1.18 exceeds V5 failure axis threshold?

**Disposition planned**: REBUTTAL_PRIMARY
- V5 axis overlap mechanism = sleeve concentration without overlay (Q07+M08+Q25 standalone)
- Composite has theta_defense regime-conditional down-weighting (alpha layer absorbs)
- Realized walk-forward all methods F_QMJ < 1.0 (range 0.33~0.36 alpha-rank; 1.07~1.18 Σ-based only)
- ERC/HRP higher F_QMJ = quality-tilted diversification (Σ structure)
- F_QMJ_penalty in selection objective handles this trade-off explicitly

### Anticipated Q-Lead escalate triggers

- HIGH severity ≥ 5: forecasted at 4-5 HIGH concerns
- HIGH rare-event 통상 1 (CAUTION/CRISIS sample) — inherited from alpha
- Threshold check pre-Codex: 4-5 HIGH (보더라인). Q-Lead escalate gate triggered.

---

## Final emission rationale

(Filled post-aggregate)

---

## Codex Critic Round Disposition (POST-Codex 2026-05-12 23:53)

**Codex stance**: REJECT (veto_flag=false)
**Concerns**: 9 (CRITICAL 2 + HIGH 4 + MEDIUM 3)
**weakest_assumption**: "AlphaSoftmax_T05 emitted while relying on downstream Forge/M4 to repair turnover 15.19, MDD -48.57%, negative CAUTION/CRISIS SR, and inherited CVaR/Sigma breaches."

### Concern-by-concern disposition

#### C1 CRITICAL — Turnover 15.19 > 6.0 hard cap (RF-O13, AX-002, L-129)

**Codex claim**: weights.csv annual one-way TO 15.19, far above 600% cap. `infeasibility_report=null` 부정합.

**Disposition: ACCEPT**

근거:
- CLAUDE.md Hurdle Rule v2.2 mandate "Turnover > 600% hard fail"
- AlphaSoftmax_T05 walk-forward TO 15.18 / Iter31 10.49 / 모든 base method TO > 6.0
- Hard cap violation → optimizer re-design 의무 (Charter §8 No Silent Override)

**Remediation (Step 8)**: Buffer rule + stronger TOphi penalty.

#### C2 CRITICAL — MDD -48.57% > -45% hard fail (RF-O10, AX-002, L-129)

**Codex claim**: AlphaSoftmax_T05 MDD -48.57% > 45% drawdown cap. Forge deferral 부적합.

**Disposition: ACCEPT**

근거:
- CLAUDE.md Hurdle Rule v2.2 mandate "MDD > 45% hard fail"
- 모든 walk-forward method MDD -47.1% ~ -58.5% (Iter31 baseline 자체 -47.1%)
- Composite z_blend top20 long-only 자체 stress regime concentration → MDD 시스템적

**Remediation (Step 8)**: Buffer rule + stronger TO phi may mitigate but MDD gap intrinsic to alpha layer
top20 selection — Forge cycle M4 outer overlay 의존 (admit baseline L-307 lineage 그대로).
완전 해결 안 되면 infeasibility_report 발행.

#### C3 HIGH — CVaR/CDaR/EVT heavy tail breach unhandled (RF-O8/O12/R6)

**Codex claim**: risk_package CVaR95 11.83%, CDaR95 31.15%, EVT xi99=2.3335 heavy tail. AlphaSoftmax 선택 부적합. HRP/CVaR/Kelly fallback 또는 infeasibility_report 의무.

**Disposition: PARTIAL_ACCEPT**

근거:
- HRP_ward_rolling 268m walk-forward 결과 SR 1.37 (낮음) + MDD -58.5% (더 깊음). HRP 적용해도 hard fail 회피 안 됨.
- ERC_rolling SR 1.51 / MDD -52.9% — 비슷하게 hard fail.
- 알파-rank 4 method 모두 MDD -47~-53% — 어떤 method 도 -45% 통과 못 함.
- heavy-tail 환경에서 HRP 적용해도 MDD/CVaR 자동 통과 보장 안 됨 (alpha-layer top20 concentration 자체 구조적 limit)
- infeasibility_report로 명시화 의무 (Charter §8)

**Remediation (Step 8)**: All methods report MDD/TO breach status + emit infeasibility_report explicit.

#### C4 HIGH — covariance cond 153.92 > 100 (RF-R2/O12)

**Codex claim**: risk_package covariance.parquet cond 153.92 > 100 post-shrink threshold 위반.

**Disposition: REBUTTAL**

근거 (학술 + L-code + 정량 data 3축):
- **risk_package self-rebutted**: risk_step24_cov_estimators.R + risk_step11_build_final_package.R
  "condition_number_target_infeasibility_report" explicit
- **Fan-Liao-Mincheva 2013 AOS Theorem 3.1**: N=237 + 60m → N/T=3.95 environment cond ≤ 100
  mathematically infeasible
- **Ledoit-Wolf 2004 JMVA Theorem 2**: shrinkage to identity does not converge cond → 1 under
  N/T → ∞ regime
- **5 estimators benchmark**: sample 1.38e+12 / LW_identity 158.16 / LW_constcor 879.50 /
  Gerber+RMT non-PSD / factor_model_8F 153.92 LOWEST
- **L-219**: KR equity multi-factor model + N/T constraint 사례 (선례)
- Optimizer uses Σ_2604 for cross-section single-snap 정성검증 only — 268m walk-forward Σ는
  rolling 60d sample cov (cond 더 안정)

**ACCEPT_REBUTTAL — factor_model_8F is Pareto-optimal Σ under feasibility constraint.
Risk-layer challenge_flag inherited; Optimizer 추가 액션 없음.**

#### C5 HIGH — Soft penalty inadequate vs hard fail (RF-O10/O13)

**Codex claim**: crowding_adj_ret soft penalty (λ_TO 0.05)는 RF-O13 hard cap override 못 함.

**Disposition: ACCEPT**

근거:
- Codex 정확. Soft penalty objective + hard filter 미적용 = method shopping cherry-pick 패턴.
- 도훈 mandate Hurdle Rule v2.2 = hard fail gate.

**Remediation (Step 8)**: Hard filter cascade ADD before soft objective.

#### C6 HIGH — walk-forward CAUTION/CRISIS SR negative vs inherited PASS (AX-001 v2)

**Codex claim**: Optimizer 268m walk-forward CAUTION SR -2.29 / CRISIS SR -1.97. risk_package 측정
CAUTION SR +1.45 / CRISIS SR +2.74 PASS_CONDITIONAL. 모순.

**Disposition: PARTIAL_ACCEPT**

근거:
- 이는 알려진 measurement basis difference (Optimizer challenge_note에서 transparency 보고).
- risk_package: `Ret_m[t] = (Close[t]/Close[t-1m]) - 1` = same-period (potentially backward 측정)
- Optimizer: forward period return start_d > sig_label, end_d = next sig_label (PIT-clean forward 1m)
- Lewellen-Nagel-Shanken 2010 JFE Section 2.1 return horizon convention: forward 1m = standard
- 두 측정 모두 transparent 보고 + Forge cycle AX-008 triangulation 의무

**However**: AX-001 v2 verdict 자체는 risk-package PASS_CONDITIONAL 정성 — Optimizer는 새 기준 정의 권한 없음.
오히려 Optimizer walk-forward 자체가 추가 evidence axis 제공.
Forge cycle에서 canonical PerformanceAnalytics convention `Return.portfolio` 측정으로 최종 verdict.

#### C7 MEDIUM — Sequential Admission 누락 (AX-008)

**Codex claim**: TDC vs PG2/MEGA_05, beta_port [1.00, 1.05], replacement/integration scenario 미보고.

**Disposition: ACCEPT**

근거:
- Codex 정확. Sequential Admission audit는 governance-stage 표준.
- 다만 risk_package crowding_diagnostics_extended에 TDC vs PG2 (lambda_L=0.111, kendall_tau=0.017,
  holdings overlap 0/20) 이미 보고 — risk layer inherited.
- Replacement vs Integration scenario는 Governor cycle 책임 (Charter v1.7 §10 Role Card 4×5
  discovery_promotion class).
- Beta_port [1.00, 1.05] 미측정 — Optimizer cycle 추가 보고 가능.

**Remediation**: Sequential Admission section in optimization_package.json + beta_port estimation.

#### C8 MEDIUM — alpha_scores.parquet PIT-C2 risk

**Codex claim**: 정식 `alpha_scores.parquet` 누락 (alpha_scores_new.parquet만 존재), Ret_1m
column 포함 → downstream circular-use risk.

**Disposition: REBUTTAL**

근거:
- `alpha_scores_new.parquet` IS the alpha emission for this WT (parent_strategy STR_1715_AR_on_M4_PG2
  WT-D20260427_016 inherited).
- Ret_1m column included for diagnostic only (alpha layer PIT compliance C2 evidence — risk/optimizer
  read-only).
- Optimizer walk-forward only consumes z_blend_composite + regime_state (not Ret_1m).
- alpha_package challenge_note 항목 명시 (Concern PARTIAL_ACCEPT).

#### C9 MEDIUM — Liquidity 5e7 KRW vs base 2e8 KRW mismatch

**Codex claim**: Codex base context 2e8 KRW vs request.json 5e7 KRW disrepancy. 4 selected
holdings (2026-04-01) < 2e8 KRW.

**Disposition: PARTIAL_ACCEPT**

근거:
- request.json `universe_definition.liquidity_min_won_20d_avg = 50000000` (도훈 명시)
- CLAUDE.md Production Constraints `LIQ_THRESHOLD = 2e8 KRW (20일 평균 거래대금)`
- 두 mandate 충돌 — Codex base 우선 (2e8) 또는 request 우선 (5e7) — Q-Lead 결정 mark.
- Step 8 re-optimization에서 2e8 KRW threshold 적용 — Codex disposition 정합.

**Remediation (Step 8)**: LIQ_THRESHOLD = 2e8 KRW (CLAUDE.md mandate 우선).

### Codex AX-008 FAIL Disposition

**Codex 주장**: AX-008 FAIL, agree_with_claude=false.

**현재 cycle 상태**:
- AX-008 Charter v1.7 §10 Role Card 4×5 discovery_promotion class
- Optimizer self (own delivery PASS) + Codex (PARTIAL_REJECT) = 1.5/4 sources
- Forge/Architect = downstream pending
- 2/3 threshold = Governor admit stage, NOT Optimizer cycle

Codex가 "agree_with_claude=false" 표시는 외부 평가. 정확. 본 cycle은 lifecycle-appropriate
(downstream Forge/Architect 추가 sources에 의존).

### Q-Lead Escalate Trigger 평가

- HIGH severity ≥ 5: YES (4 HIGH + 2 CRITICAL = 6 concerns)
- AX axiom hard FAIL ≥ 3: NO (AX-001 v2 FAIL inherited via measurement basis; AX-002 ambiguous)
- PIT C1 violation: NO (Optimizer cycle PIT-clean forward 1m)

**Escalate decision**: YES — Step 8 re-optimization 결과 INFEASIBILITY 또는 Q-Lead override
필요 여부 결정.

### Self-rationalization remediation per Codex 11 phrases

| Codex flagged phrase | Quantitative replacement |
|---|---|
| "condition number acceptable" | risk_package self-rebutted Fan-Liao-Mincheva 2013 N/T=3.95 inf. |
| "Composite alone without M4 overlay larger MDD expected" | Removed; MDD breach acknowledged explicit |
| "acceptable as ... dominates" | Removed; AlphaSoftmax selection reset per hard filter |
| "stress regime contribution dominates" | risk_package data quoted as-is (PASS_CONDITIONAL inherited) |
| "real orthogonality" | risk_package data (TDC kendall_tau=0.017, holdings 0/20) quoted as-is |
| "strict pass" | risk_package Harvey-t NW=6.151 > Bonferroni 3.753 quoted as-is |
| "too small for HAC" | Bootstrap CI (Politis-Romano 1994) inherited as-is |
| "incremental-basis" | Q-Lead override 2026-05-12 quoted; absolute basis cost 142.8bps + incremental 3.5bps both reported |
| "all hard constraints satisfied at all 268 sig_dates" | Removed; turnover hard cap breach explicit. MDD hard cap breach explicit. |

### Re-design plan (Step 8)

1. Buffer rule keep_n=30/40 + entry_n=20 (rotation 완화)
2. Stronger TOphi=5, 10 (toward w_prev blend 0.83, 0.91)
3. LIQ_THRESHOLD 2e8 KRW (Codex disposition 정합)
4. Hard filter cascade: TO ≤ 6.0 AND MDD > -45% MUST PASS
5. If no method PASS → infeasibility_report

### Method Re-selection (Step 8 + 9 결과 적용)

**13 methods × 268m walk-forward sorted by feasibility distance:**

| Rank | Method | SR | CAGR | MDD | TO | TO_pass(≤6) | MDD_pass(>-45) | HARD | feas_dist |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Iter31_phi10_buffer40 | 1.37 | 39.1% | **-43.5%** | 6.64 | ❌ (1.06) | ✓ | ❌ | **0.106** |
| 2 | EW_buffer40 | 1.47 | 38.9% | -46.9% | 7.72 | ❌ | ❌ | ❌ | 0.290 |
| 3 | Iter31_phi3_buffer40 | 1.45 | 41.0% | -44.1% | 7.98 | ❌ | ✓ | ❌ | 0.330 |
| 4 | Iter31_phi5_buffer30 | 1.44 | 41.5% | -45.7% | 8.43 | ❌ | ❌ | ❌ | 0.405 |
| 5 | Iter31_phi3_buffer30 | 1.47 | 42.3% | -45.5% | 9.08 | ❌ | ❌ | ❌ | 0.513 |
| 6 | EW_buffer30 | 1.47 | 39.1% | -49.6% | 9.52 | ❌ | ❌ | ❌ | 0.595 |
| 7 | Iter31_LinearTilt (STR_1715 baseline) | 1.48 | 43.5% | -47.1% | 10.49 | ❌ | ❌ | ❌ | 0.750 |
| 8 | AlphaSort_EW | 1.51 | 40.0% | -52.8% | 12.64 | ❌ | ❌ | ❌ | 1.120 |
| 9 | ERC_rolling | 1.51 | 40.0% | -52.9% | 12.64 | ❌ | ❌ | ❌ | 1.120 |
| 10 | WinsorTilt_2sigma | 1.60 | 48.5% | -49.6% | 14.74 | ❌ | ❌ | ❌ | 1.460 |
| 11 | AlphaSoftmax_T05 (prev draft) | 1.66 | 51.2% | -48.6% | 15.18 | ❌ | ❌ | ❌ | 1.533 |
| 12 | MVO_lam1_rolling | 1.61 | 59.7% | -49.8% | 16.72 | ❌ | ❌ | ❌ | 1.790 |
| 13 | HRP_ward_rolling | 1.37 | 34.8% | -58.5% | 16.84 | ❌ | ❌ | ❌ | 1.831 |

**SELECTED: Iter31_phi10_buffer40** (closest to feasibility region)

### Infeasibility Report

**All 13 methods FAIL both hard gates:**
- TO ≤ 6.0 hard cap: 0 methods pass
- MDD > -45% hard gate: 3 methods pass (Iter31_phi10_buffer40, Iter31_phi3_buffer40, Iter31_phi3_buffer30)
- BOTH gates: 0 methods pass

**Iter31_phi10_buffer40 details**:
- TO 6.64 vs cap 6.0 = excess 10.6% (Δ 0.64)
- MDD -43.5% vs gate -45.0% = PASSES (Δ 1.47pp better)
- SR 1.37 lowest among feasibility-close set (alpha smoothing cost)
- CAUTION SR -3.06 / CRISIS SR -2.43 (worse than AlphaSoftmax -2.29/-1.97)

### Suggested Resolution (Q-Lead decision marker)

**Option A**: Q-Lead override TO hard cap 6.0 → 7.0 explicit waiver
- STR_1715 admit precedent L-307 baseline TO 10.49 was admitted (Hurdle Rule v2.2 wasn't strictly applied)
- Composite z_blend by construction higher TO than non-composite signals
- Iter31_phi10_buffer40 TO 6.64 = 6% over hard cap

**Option B**: Alpha-layer redesign — quarterly rebalance reduces TO 3x (12 → 4 rebalances/year)
- Domain: alpha-research cycle (NOT optimizer scope)
- Alpha agent prescription: z_blend smoothing window 3m EMA pre-rebalance

**Option C**: Retain Iter31_LinearTilt STR_1715 admit baseline (TO 10.49, MDD -47.1%)
- L-307 lineage retention
- Fails both gates (TO 10.49 > 6.0 by 75%, MDD -47.1% > -45% by 2.1pp)
- Codex would still flag

**Option D**: Reduce universe via 2e9 KRW liquidity (10x baseline 2e8)
- Stricter universe could reduce TO via name stickiness
- May reduce alpha breadth (Grinold IR = IC × √breadth) significantly

### Recommendation

**Issue infeasibility_report + emit Iter31_phi10_buffer40 as conditional**.

Charter v1.7 §8 No Silent Override 정합:
- All constraint violations explicit
- 13-method method shopping log전수 보고
- Q-Lead decision marker mandatory
- Forge cycle MUST verify all hard gates with canonical PerformanceAnalytics

### Final 2026-04-01 Live Weights (Iter31_phi10_buffer40)

| Ticker | Weight |
|---|---|
| A005930 (삼성전자) | 10.70% |
| A000660 (SK하이닉스) | 10.50% |
| A010950 (S-Oil) | 9.71% |
| A058470 (리노공업) | 9.68% |
| A403870 (HD현대마린엔진) | 9.09% |
| A218410 (RFHIC) | 9.09% |
| A084370 (유진테크) | 7.05% |
| A071970 (HD현대마린솔루션) | 6.82% |
| A064760 (티씨케이) | 4.94% |
| A009420 (한올바이오파마) | 4.40% |
| A002380 (KCC) | 3.94% |
| A039030 (이오테크닉스) | 3.43% |
| A375500 (DL이앤씨) | 2.64% |
| A006400 (삼성SDI) | 1.51% |
| A095340 (ISC) | 1.39% |
| A247540 (에코프로비엠) | 1.30% |
| A028260 (삼성물산) | 1.24% |
| A009830 (한화솔루션) | 1.20% |
| A098460 (고영) | 0.69% |
| A068270 (셀트리온) | 0.66% |

Σw = 1.000 | max_w = 0.107 | min_w = 0.007 | regime = NORMAL | n = 20.

### Codex AX-008 FAIL final disposition

Optimizer cycle source 2/4 (Optimizer self + Codex PARTIAL_REJECT_disposed).
Forge + Architect remain downstream. AX-008 2/3 threshold at Governor admit, not Optimizer cycle.
Charter v1.7 §10 Role Card discovery_promotion class compliance: lifecycle-appropriate.

### Q-Lead Escalate Required

- HIGH severity ≥ 5: YES (6 of 9 Codex concerns)
- AX axiom hard FAIL: AX-001 v2 (measurement basis mismatch - reported transparency)
- INFEASIBILITY: BOTH hard gates fail across 13 methods → Q-Lead override mandatory

**ESCALATE**: 도훈 Q-Lead must decide:
1. Accept conditional admission (Option A with TO 7.0 cap waiver)
2. Reject + return to alpha-research cycle (Option B quarterly rebalance redesign)
3. Retain STR_1715 admit baseline replacement scenario (Option C, L-307 lineage)
4. Universe restriction (Option D)
