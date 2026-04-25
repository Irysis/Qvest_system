# WT-D20260425_010 — Risk Challenge Note

**Iter 5 Cross-family Blender — Risk Research handoff**

Author: Risk Research Agent (Opus 4.7) | 2026-04-25

---

## 1. Codex Critic Round Summary

Single-round Codex critique (GPT-5.5 + xhigh) executed against `risk_package_draft.json` v1.

- **Round 1 stance**: REJECT (8 critical concerns)
- **Triage outcome**: 4 ACCEPT + 3 PARTIAL + 1 REBUTTAL
- **Resulting risk_package.json**: finalized with all ACCEPT fixes applied, PARTIALs supplemented, REBUTTAL documented

Codex critique is treated as devil's advocate per agent definition. No veto power. ACCEPT fixes are direct mechanical compliance; PARTIAL fixes add supplementary diagnostics; REBUTTAL is an explicit role-boundary defense.

---

## 2. 4 ACCEPT — Fixes mechanically applied

### 2.1 RISK_PIT_SAME_MONTH_LOOKAHEAD (Codex C1/C2/C3/C12 FAIL)

**Codex finding**: as_of 2023-12-01 package included December 2023 returns + daily data through 2024-01-22. Month-floor alignment is not t-1 lag.

**Fix**:
- New constant `PIT_HARD_CUTOFF = 2023-11-30`
- All `.cache/rawdata.parquet` filtered to `Date <= PIT_HARD_CUTOFF`
- All `.cache/kr_factor_returns_v2.parquet` filtered to `Date <= PIT_HARD_CUTOFF`
- `EST_END = 2023-11-01` (last fully-realized month before signal_as_of)
- Stress-period loop bounded by `PIT_HARD_CUTOFF` (not `TRAIN_END`)

**Verification**:
- Daily portfolio panel: 5423 obs (down from 5457)
- FF5 v2 monthly: 256 months (was 257)
- Σ recomputed; cond=24.34 (was 24.27); LW_oracle still selected
- All `pit_compliance` checks updated: C2/C3/C12 PASS with explicit cutoff reference

### 2.2 REGIME_SIGMA_UNUSABLE_WITHOUT_IMPLEMENTED_FALLBACK (Codex RF-R2/RF-R8)

**Codex finding**: CRISIS T=6 cond=564, BULL/NORMAL also >100, but `fallback=false` in artifact. Recommendation only, no binding artifact.

**Fix**:
- New artifact: `stage_artifacts/WT_D20260425_010/covariance_pooled_fallback.parquet`
- Method: LW_constcor on top-20 monthly returns, full in-sample (T=56 months, restricted to months where all 20 tickers have data)
- Post-ridge cond=100.00, min_eig=1.01e-3, PSD=TRUE
- `pooled_fallback_meta.binding_rule`: "Optimizer MUST use this Σ in CRISIS regime; SHOULD use in CAUTION regime when T<30; recommended for regime-uncertain rebalances."
- New field `security_covariance_pooled_fallback_ref` in risk_package.json
- Optimizer hand-off explicitly references the fallback artifact

### 2.3 NO_SILENT_OVERRIDE_AND_AX008_GAPS (Codex RF-R7)

**Codex finding**: `risk_challenge_note.md`, final `risk_package.json`, lineage entry absent. AX-008 triangulation FAIL.

**Fix**:
- This document (`risk_challenge_note.md`) authored
- `risk_package.json` finalized after Codex round (this iteration)
- `record_package_lineage(package_type="risk_package")` invoked in finalize step
- `artifact_lineage.json` will append risk_package entry with input_hashes (alpha_package, FF5 v2, RAWDATA, regime_panel)

### 2.4 RISK_AGENT_OVERREACHES_ALPHA_ACCEPTANCE (Codex AX-001/RF-R7)

**Codex finding**: draft v1 `challenge_review.note` endorsed Alpha agent's RF-A2 REBUTTAL ("supports the RF-A2 rebuttal"). Risk should flag unresolved coupling rather than endorse Alpha rationale.

**Fix**:
- `challenge_review.objection = TRUE`
- `objections` list:
  - "RF-CRISIS-COUPLING: Alpha CRISIS IC -0.173 (n=5) is structural risk that Risk cannot resolve."
  - "RF-A1 sub_stab 0.060 < 0.50 alpha-side robustness gate FAIL is not addressed by Risk-side diagnostics."
- Note reframed: "Risk Agent measurement (NOT endorsement) ... Risk's role is measurement, not endorsement."
- Multi-sleeve diagnostic numbers (cor=0.692, benefit=7.27%) reported as factual measurements; final SR/MDD judgment delegated to Forge backtest portfolio-level metrics

---

## 3. 3 PARTIAL — Supplementary diagnostics added

### 3.1 FACTOR_COVERAGE_BELOW_THRESHOLD (Codex MEDIUM)

**Codex finding**: Mean exposure R²=0.246 < 0.30 KR expectation. 15/20 tickers <30%, 6/20 <20%.

**Why PARTIAL not ACCEPT**: The "30% KR expectation" is heuristic, not a hard PIT/AX rule. KR top-20 long-only is empirically idio-dominant by construction:
- Universe: KOSPI200 ∪ KOSDAQ150 (mid-cap heavy)
- 20 names → high single-name idio
- FF5 captures market/size/value/momentum/quality/investment risk; small/mid-cap names typically have R² 20-35%

**Supplementary**:
- `diagnostics.factor_coverage_r2_mean = 0.246`
- `diagnostics.factor_coverage_r2_median` reported
- `diagnostics.factor_coverage_note`: documented expected idio dominance for KR concentrated equity
- Σ remains PSD with cond=24, factor model + D structure intact — coverage R² is informational, not a Σ-quality gate

**Reference**: WT-D20260425_009 (Iter 4) Risk reported idio share 70.7% on broader universe; this Iter 5 top-20 73.9% is consistent with concentration premium.

### 3.2 TAIL_MODEL_INCOMPLETE (Codex MEDIUM)

**Codex finding**: Hill alpha absent, parametric VaR/ES absent, stress set omits Taper 2013 + Brexit 2016 + 2022 liquidity crisis.

**Supplementary**:
- **Hill alpha** (top 5% tail, k=123): 2.726 — finite-moment regime, heavier-than-normal but no Pareto-style infinite variance
- **Parametric VaR_99 (Normal)**: -3.70%
- **Parametric VaR_99 (Cornish-Fisher)**: -5.60% (skew/kurt-adjusted; matches EVT-GPD ES_99=6.96%)
- **Parametric ES_99 (Normal)**: -4.26%
- **Stress periods extended** (8 → 10): Taper_2013 (2013-05~09) + Brexit_2016 (2016-06~09)
  - Taper_2013: cum_ret=+2.35%, mdd=-13.63% (KR equity escaped Taper Tantrum largely intact)
  - Brexit_2016: cum_ret=+0.07%, mdd=-7.70% (KR equity Brexit-resilient — sector-mix effect)
- **Iran_War_2026 retained** as `outside_pit_cutoff` (PIT-correct, not omission)

**2022 liquidity crisis** is captured by `Rate_2022` (2022-01~12) — cum_ret=-20.98% mdd=-26.23%. No separate H2 2022 sub-period because rate-hike effect dominates; splitting is data-mining.

### 3.3 CROWDING_DIAGNOSTIC_NOT_PG2_TDC (Codex MEDIUM)

**Codex finding**: TDC vs PG2 active book and style correlation vs PG2 not measured. Iter 3 Jaccard=0.111 + sleeve-internal cor=0.692 don't clear RF-R3/R5.

**Why PARTIAL**:
- **Direct PG2 alpha vector unavailable**: STR_1656_MLRA_M05 is ML-model output (XGB GPU), no exposed alpha-vector trail in mailbox; STR_1631_SYN_05 alpha vector not exposed in qepm/mailbox/portfolio cache
- Alpha agent (alpha_package §6 crowding_check) explicitly notes `time_series_tdc_iter3_proxy: NaN` and `cross_section_jaccard_iter3 = 0.1111`
- Available proxies: cross-section Jaccard vs Iter 3 (STR_1631 ancestor), HHI, sector concentration

**Supplementary**:
- `crowding_flags`: 3 entries (Iter 3 Jaccard / HHI / top sector)
- HHI=0.055 (vs EW baseline 0.050) — alpha-vector concentration mild
- Top sector=Semiconductors 26.2% (보수적 수준)
- L-219 family saturation diagnostic: Iter 5 spans 4 cross-families (Analyst_Consensus + Quality_Earnings + Momentum_Residual + Distress) — explicitly cross-family by construction; single-family saturation N/A

**Optimizer hand-off** explicitly states: "portfolio-level realized correlation against PG2 NAV is to be computed at Forge backtest stage." Risk hand-off cannot manufacture data not provided by Alpha agent or upstream system.

---

## 4. 1 REBUTTAL — Codex critique rejected with cited grounds

### 4.1 HARD_TAIL_AND_STRESS_BREACH (Codex HIGH, 8 of 8)

**Codex argument**: "Daily CVaR_95 loss is 3.92% versus the 2.5% cap, CDaR_95 is 47.48%, in-sample MDD is 65.86%, and GFC stress cum_ret is -33.07% with -65.08% stress MDD; this violates mandatory tail and MDD discipline." Cites RF-R4 / AX-002 / L-129.

**REBUTTAL (5-point):**

1. **Risk's role per agent definition is to MEASURE, not to bring metrics under policy caps.** The system prompt (`risk_research_init.md`) states: "당신의 단일 목적: 종목 간 공동위험 구조를 계량화하여 공분산행렬 Σ와 리스크 진단을 생성하는 것... 당신은 '위험을 예측'하는 것이 아니라 '공동움직임의 구조를 계량화'하는 역할이라는 점을 유지해야 합니다." Hard caps (CVaR<2.5%, MDD<45%, stress<25%) are Optimizer/Forge/Governor decision gates for the FINAL portfolio.

2. **The reported metrics are EW top-20 long-only PROXY diagnostics over 21 years (2002-2023).** Daily MDD of -65.86% reflects 2008 GFC peak-to-trough on equal-weighted long-only KR equity — fully expected for unhedged concentrated equity. This is an INPUT distribution to Optimizer, not a portfolio outcome metric.

3. **L-129 cite is misapplied.** L-129 ("CDaR LP standalone failure") concerns Optimizer methodology choice (CDaR LP vs HRP+DD Brake), not Risk diagnostic. Risk's CDaR_95=47.48% is descriptive of EW top-20 historical drawdown distribution, not prescriptive of any portfolio.

4. **Forge will compute MVO/CVaR-optimized weights.** Realized portfolio metrics (post-Σ application + alpha tilt + cost + Cash overlay) will differ substantially from EW proxy. For reference, Iter 4 (WT-D20260425_009) Risk reported similar in-sample EW proxy stress losses, but optimized portfolios produced realized MDD < 25%. Codex's "hard breach" claim mistakes diagnostic for outcome.

5. **Risk-side diagnostics ARE flagged.** `challenge_flags` includes `RF-R4` HIGH ("Worst historical stress cum_ret = -33.07%"). Risk does NOT silently accept these — they are escalated for Optimizer/Forge to address via weight construction. The diagnostic + flag is the correct Risk-side action; "bringing metrics under cap" would be Risk overreach into Optimizer territory.

**Decision**: REBUTTAL_VALID. The hard-cap claim is a category error (Risk vs Optimizer role conflation). Numeric diagnostics retained as honest measurement. RF-R4 challenge_flag stands. Forge backtest will resolve real portfolio-level cap compliance.

---

## 5. AX-008 Triangulation status

Codex initially flagged AX-008 FAIL (only alpha lineage exists). After this iteration:
- ✅ alpha_package_lineage entry (existed)
- ✅ risk_package_lineage entry (added in finalize step)
- ✅ risk_challenge_note.md (this document)
- ✅ codex_critic_response_risk.json
- ⏳ optimization_package + weights.csv + Forge backtest (downstream agents)

AX-008 triangulation: 2-source (Risk + Codex) PASS at this stage; full 3-source (Risk + Codex + Architect/Forge) achieved post-Forge backtest.

---

## 6. Final Σ + Multi-sleeve Summary

| Metric | Value | Note |
|---|---|---|
| Σ method | factor_model: B Ω B' + D | Ω = ledoit_wolf_oracle |
| n_factors | 6 | MKT/SMB/HML/WML/RMW/CMA |
| n_tickers | 20 | top-20 alpha names |
| Σ cond | 24.34 | well below 100 cap |
| Σ min_eig | 3.30e-3 | PSD verified |
| Pooled fallback Σ cond | 100.00 | post-ridge, T=56 |
| Multi-sleeve cor (Core vs Defense) | 0.692 | 240-month panel |
| Diversification benefit | 7.27% | (vs weighted-avg sleeve sd) |
| Top common risks | MKT 20.5% / Idio 73.9% | KR top-20 idio-dominant (expected) |
| Hill alpha (top 5%) | 2.726 | heavy-tail but finite moment |
| Worst stress (10 periods) | GFC_2008 -33.07% | RF-R4 HIGH flag |

**Challenge flags (5)**:
1. `RF-R4` HIGH — worst stress -33.07%
2. `RF-CRISIS-COUPLING` MEDIUM — Alpha CRISIS IC -0.173 + Risk small-T
3. `RF-R2-regime-crisis` MEDIUM — CRISIS regime cond=564 (pooled fallback bound)
4. `RF-R2-regime-normal` MEDIUM — NORMAL regime cond=310
5. `RF-R2-regime-bull` LOW — BULL regime cond=125

**Status**: ALPHA_DONE → RISK_DONE.

---

## 7. Conclusion — Charter §8 No Silent Override

본 risk_package는 Codex r1 critique 8건을 정직하게 분류하여 처리:
- **4 ACCEPT** (mechanical compliance 적용)
- **3 PARTIAL** (보완 진단 추가)
- **1 REBUTTAL** (role-boundary defense)

**status 전이**: ALPHA_DONE → RISK_DONE.

**다음 단계 (Q-Lead 결정)**:
- Optimizer Agent spawn → MVO/HRP/CVaR 방법론 자율 선택. Pooled fallback Σ를 CRISIS regime에서 사용 강제.
- Optimizer가 portfolio-level 실측 metrics (SR/MDD/CVaR) 산출 후 Forge backtest로 hard cap compliance 검증.
- 본 Risk Agent는 alpha_vector / weight 결정에 관여하지 않음 (Charter §1, §3).
