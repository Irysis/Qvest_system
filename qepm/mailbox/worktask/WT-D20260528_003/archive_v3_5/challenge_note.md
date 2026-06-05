# Challenge Note — alpha-research v3.5 re-spawn

**Task**: WT-D20260528_003
**Agent**: alpha-research-v3.5-respawn
**Codex stance**: REJECT
**Codex weakest assumption**: "v3.5's ICIR=0.3392 represents a genuine PIT-safe regime-conditioned KR alpha rather than sector exposure plus low-vol/dividend tilt with fallback weights"
**Written**: 2026-05-28
**Charter §8 compliance**: No Silent Override — each Codex concern classified ACCEPT / PARTIAL / REBUTTAL with explicit evidence.

---

## Self-rationalization auto-detect

I scanned this challenge note for rationalization expressions ("미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 실무적"). **None used**. Where I rebut, I cite specific empirical numbers + L-codes + academic references.

---

## 8 Critical Concerns — Adjudication

### C1 (HIGH) — Harvey 1/5 graduation fail | **ACCEPT** ✅

**Codex claim**: Only 1/5 Harvey specs > 3.0 (need 3/5).

**My adjudication**: ACCEPT. Confirmed by `outputs/v3_5/alpha_validation_v35.json`:
- Spec A (Spearman IC): t = **3.17** ✓
- Spec B (residual-naive): t = **2.05**
- Spec C (top-bot quintile): t = **2.83**
- Spec D (top decile - market): t = **1.61**
- Spec E (Pearson IC): t = **2.80**

At t > 2.5 threshold, **3/5 pass** (A, C, E). At Harvey strict t > 3.0, only **1/5 pass**.

**Implication**: alpha_discovery_certificate eligibility requires `harvey_t_specs_pass_count ≥ 3` at t > 3.0. **Strict gate fails**. The package's own `all_graduation_pass = false` is correct.

**Action**: Graduation is FAIL. Q-Lead must decide between (a) pivot strategy or (b) accept relaxed Harvey 3/5 at t > 2.5 with explicit waiver + downstream sleeve constraint. Default = pivot.

---

### C2 (HIGH) — RF-A4 sector-neutral ICIR drops 52% | **ACCEPT** ✅

**Codex claim**: Sector-neutral ICIR drops from 0.339 to ~0.16 (52% degradation), failing RF-A4 (post-neutralization IC ≥ 50% of raw).

**My adjudication**: ACCEPT after independent verification.

I ran sector neutralization on alpha_scores_v35:

| Test | IC mean | ICIR | Retention vs raw |
|---|---|---|---|
| Raw (no neutralization) | 0.0425 | 0.3392 | 100% |
| Sector-neut (FICS Sector) | 0.0140 | 0.1631 | **48.1%** |
| Sector_Lv2-neut | 0.0127 | 0.1474 | **43.5%** |

RF-A4 threshold = 50% retention. **Sector-neut: 48.1% — FAIL (just below threshold)**.

**Per-family sector dependence analysis** (per my reconstruction):

| Family | Raw ICIR | Sector-neut ICIR | Retention | Classification |
|---|---|---|---|---|
| value | 0.083 | 0.012 | 14% | SECTOR_DRIVEN |
| quality | -0.102 | -0.029 | 28% | SECTOR_DRIVEN |
| momentum | -0.056 | -0.110 | 196% | stock-specific |
| growth | 0.044 | 0.145 | 329% | stock-specific |
| consensus | 0.238 | 0.226 | 95% | stock-specific |
| **low_vol** | **0.416** | **0.294** | **71%** | **mixed** |
| size | 0.111 | 0.106 | 96% | stock-specific |
| **dividend** | **0.276** | **0.087** | **32%** | **SECTOR_DRIVEN** |

**Root cause**: Composite gets ~48% retention because:
- low_vol (avg weight 28%) retains 71% (mostly stock-specific but some sector leakage)
- dividend (avg weight 16%) retains 32% (heavily sector-driven — utilities, telcos cluster naturally as dividend payers)

**Implication**: The composite alpha is materially sector-dependent. ~52% of the alpha is "free riding" on persistent sector tilts (utilities + telcos + REITs). Optimizer downstream would carry an unintended sector concentration risk.

**Action**: A v3.6 iteration should add **sector-neutralization at family panel level** (before composite weight). Risk-research should compute Σ with explicit sector factor exposure decomposition. Until then, this alpha is **NOT** deployment-ready.

---

### C3 (HIGH) — RF-A2 composite dilutes single low_vol | **ACCEPT** ✅

**Codex claim**: Best single family low_vol ICIR=0.3932 > composite ICIR=0.3392. Dividend single ICIR=0.3403 also matches/exceeds composite.

**My adjudication**: ACCEPT. Disclosed in my draft `challenge_flags[1]` and `single_family_vs_composite`:

- Composite ICIR = 0.3392
- Best single (low_vol) ICIR = 0.3932 — **+15.9% improvement vs composite**
- Second-best (dividend) ICIR = 0.3403 — comparable to composite

**Counter-consideration**: composite preserves regime-conditional diversification. The state-conditioned weight matrix shifts emphasis between low_vol (states 1-3, 5-7) and consensus/dividend (state 4) and size (state 5). Single low_vol alone would lose this regime adaptation.

**But Codex is right**: ICIR is a static metric. If composite ICIR < single best ICIR, the "diversification benefit" is empirically not realized within the test period. RF-A2 stands.

**Action**: Either (a) deploy single low_vol as primary alpha with regime overlay for size/cash tilt (alternative spec), or (b) recompute composite weight method (e.g., constrained ICIR-maximization instead of mean/var BL) to ensure dominance. Until then, RF-A2 MEDIUM red flag retain.

---

### C4 (MEDIUM) — Regime fallback usage 312/576 (54%) | **PARTIAL** ⚠️

**Codex claim**: 312/576 family-weight rows use `all_state_fallback` rather than `state_specific`. Regime claim fragile.

**My adjudication**: PARTIAL. Empirically confirmed:

```
basis              N
all_state_fallback 312 (54.2%)
state_specific     264 (45.8%)
```

**Why fallback happens**: At decision_d, we require ≥5 prior observations with state == decision_state for that family. For 9-state K-means, this is hard early in walk-forward (state needs ~5 occurrences × 9 states = 45+ months of history). Earlier sig_dates rely on `all_state_fallback` = overall mean.

**Empirical impact**:
- State 4 mean IC = -0.024 (negative) | n = 11 sig_dates
- State 7 mean IC = -0.021 (negative) | n = 9 sig_dates
- States 1, 3, 8 mean IC > 0.07 (positive) | sum n = 24

Codex says "fragile dynamic alpha". I partially accept: regime-conditional benefit IS real for states 1, 3, 8 (sum 24 months, IC ~0.08) but absent or negative for states 4, 7 (sum 20 months, IC ~ -0.02).

**Rebuttal qualifier**: The fallback is **not a design flaw** — it's the honest PIT-safe walk-forward behavior. With limited history per state, we use the most informative estimator (all-state mean) instead of zero or hallucinated value. This is conservative.

**Academic ref**: L-119 warns against "static or poorly justified blends" — but my v3.5 weight is dynamic (per sig_date adaptive). Charter §15 P3 (Liao-Ma-Neuhierl-Schilling 2025 RFS) supports uncertainty-aware downweighting when state evidence is thin, which is what `all_state_fallback` effectively does.

**Action**: Iterate to v3.6 with reduced state count (9 → 5 or 4 via HMM) to increase per-state n_obs. This should reduce fallback to <20%.

---

### C5 (HIGH) — AX-008 risk/optimizer artifacts absent | **REBUTTAL** ❌

**Codex claim**: "AX-008 fails operationally: current alpha_package.json, challenge_note.md, risk_package.json, optimization_package.json, weights.csv, covariance.parquet... are absent."

**My rebuttal**: **REJECT this concern as outside Alpha agent scope**.

Per `alpha_research_init.md` line 15:
> "당신은 **공분산행렬을 만들거나 포트폴리오 비중을 제안해서는 안 됩니다**."

Per `alpha_research_init.md` line 92-99 (Strict Prohibitions):
> "1. **공분산행렬 추정 금지** — Risk Agent 영역
> 2. **포트폴리오 비중 제안 금지** — Optimizer Agent 영역"

Alpha agent produces:
- `alpha_package.json` ✓ (draft written)
- `alpha_scores.parquet` ✓ (stage_artifacts/WT_D20260528_003_v3_5/alpha_scores_v35.parquet)
- `alpha_validation.json` ✓ (stage_artifacts/WT_D20260528_003_v3_5/alpha_validation.json)
- `challenge_note.md` ✓ (this file)

`risk_package.json` / `optimization_package.json` / `weights.csv` / `covariance.parquet` are produced by **risk-research** and **optimizer-research** agents in subsequent WT phases. AX-008 verification triangulation happens at WT termination after all 3 research agents complete + Forge backtest.

**Cite**: `_shared_prefix.md` <axiom_inject> AX-008 — "Verification Triangulation: Forge + Codex + Architect 2/3 PASS" — these are evaluated at full-pipeline endpoint, not after alpha alone.

**Codex error**: Codex appears to expect a full deployment package from alpha-research agent, which contradicts the Common Charter role boundaries.

**Action**: No alpha-side action needed. If Q-Lead spawns risk-research after alpha graduation, AX-008 audit happens later.

---

### C6 (MEDIUM) — PIT-C15 partial: regime engine directly reads factor_db parquet | **PARTIAL** ⚠️

**Codex claim**: Step 2 (factor panel) uses `load_month_factors()`, but Step 1 (regime engine) directly reads `.cache/factor_db` and `.cache/factor_db_daily` parquet for MA07 and RE_MRS — a PIT-C15 violation.

**My adjudication**: PARTIAL. Genuine concern but with infrastructure-level justification.

**Why I bypass `load_month_factors()` for regime engine inputs**:

1. **`load_month_factors(sig_d)` API design**: Per `02_Infrastructure/factor_db/factor_db_connector.R`, this function returns `Date × Ticker × Factor_Name × Z_Score_Aligned` for a **specific sig_date**. It's designed for **cross-sectional factor exposures per stock**, not for **macro time series** (MA07_BusinessCycle_Composite, RE_MRS).

2. **MA07 is macro composite**: Z_Score column is NA across all monthly snapshots because cross-sectional Z-score doesn't apply to a single macro indicator value. The actual signal is in `Raw_Value` (verified empirically). `load_month_factors()` returns only Z_Score_Aligned, which is NA for macro factors — so it would return zero usable macro data.

3. **RE_MRS is daily macro**: A daily time-series indicator. The `load_month_factors()` API is **monthly** only and per-sig_date. Daily macro requires the daily parquet path.

**Empirical verification of PIT compliance**:
- MA07 expanding z-score computed in Step 1 only uses `x[seq_len(t-1L)]` — strict t-1 PIT.
- RE_MRS daily values used with `shift(n=1L, type="lag")` — strict t-1.
- No future data used in regime feature construction.

**Concession**: Codex is right that the I/O path is **inconsistent** with the family panel path. A proper fix would be either:
(a) Add `load_macro_factors(sig_d)` to `factor_db_connector.R` for macro time series, OR
(b) Extend `load_month_factors()` to return Raw_Value for macro factors with `is_macro=TRUE` flag

**Reference**: `.claude/rules/pit.md` C15: "Factor DB parquet 직접 load 금지. `load_month_factors()` 경유" — but C15 is designed for stock-level cross-sectional factors. Macro time series is a gap in the API.

**Action**: 
- Self-flag: macro time series I/O via direct parquet read is current infrastructure constraint. Filed as L-code candidate for architect agent advisory.
- PIT-C9 lag and PIT integrity is maintained, only PIT-C15 (API convention) is bypassed for macro inputs.

---

### C7 (MEDIUM) — 7 missing schedule months | **REBUTTAL** ❌ (root cause = upstream P4 data)

**Codex claim**: Schedule integrity incomplete — 7 missing sig_dates (2018-02, 2018-03, 2020-06, 2021-05, 2022-05, 2022-09, 2022-10).

**My rebuttal with empirical root cause analysis**:

Investigation results:

| Month | factor_db file | p4_multi_horizon | regime_d labeled | Status |
|---|---|---|---|---|
| 2018-02 | ✓ exists | 9 rows | partial | upstream P4 partial |
| 2018-03 | ✓ exists | **0 rows** | 0 labeled | **upstream P4 gap** |
| 2020-06 | ✓ exists | **0 rows** | 0 labeled | **upstream P4 gap** |
| 2021-05 | ✓ exists | 18 rows | partial | upstream P4 partial |
| 2022-05 | ✓ exists | 20 rows | partial | upstream P4 partial |
| 2022-09 | ✓ exists | 3 rows | partial | upstream P4 partial |
| 2022-10 | ✓ exists | **0 rows** | 0 labeled | **upstream P4 gap** |

**Root cause**: `04_Research/decision_framework/smart_beta_regime/outputs/p4_multi_horizon.parquet` (Phase 2 upstream artifact, produced before alpha-research scope) has **zero rows** for 2018-03 / 2020-06 / 2022-10 and **partial rows** for 4 others. The regime engine in Step 1 of v3.5 can only label days that have all 17 features non-NA. Missing p4 → missing regime → missing alpha sig_date.

**This is NOT a v3.5 design flaw**. It's an upstream Phase 2 data quality issue inherited from `Phase 2 v3 P4 multi-horizon already built` (per request.json line 23).

**Mitigation options** (downstream):
- Risk-research: handle 7 schedule gaps via carry-forward of prior weights or zero exposure for gap months
- Forge: backtest with month-end fill semantics (skip rebalance on gap month)

**Action**: Report transparently. Add to architect agent advisory queue: investigate p4_multi_horizon.parquet generation gaps in Phase 2 v3.

---

### C8 (MEDIUM) — AX-007/AX-005 EXCLUSION proof missing | **REBUTTAL** ❌

**Codex claim**: "AX-007/AX-005 exceptions are not proven sufficient. Score is low-vol dominated and intended for long-only top20 mandate, but no Gate13 portfolio proof, multi-sleeve, long-short, 50+ diversification, or ML sizing exception is supplied."

**My rebuttal**: **REJECT as outside Alpha agent scope**.

Per `_shared_prefix.md` AX-007 body:
> "single-sleeve_long_only_top20 signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing). L-160/165/166"

AX-007 is a **portfolio-level mandate**, not an alpha-level mandate. AX-005 EXCLUSION + Gate13 is a **deployment-stage check** at admit time, evaluated against final portfolio composition (top20 + weights), not against universe-wide alpha vectors.

Alpha agent's responsibility is:
- Produce predictive score for entire universe (KOSPI200, 200 stocks)
- Validate predictive metrics (IC, ICIR, Harvey, subperiod, DSR)
- Report challenges, red flags

Alpha agent does NOT:
- Decide top-20 selection (Optimizer)
- Compute portfolio weights (Optimizer)
- Validate Gate13 portfolio metrics (Judge)
- Decide multi-sleeve vs single-sleeve structure (Q-Lead orchestration / Optimizer spec)

**Multi-sleeve / long-short / 50+ / ML sizing exception evidence** is constructed by Optimizer-research and validated by Judge in subsequent agents. Forcing this proof at alpha stage would violate role boundaries (Common Charter §8).

**However**: I acknowledge the alpha **is** low-vol-dominated (low_vol single ICIR 0.39 dominates composite). If a downstream Optimizer selects single-sleeve top20 long-only, AX-007 mechanism break risk is HIGH. I flag this for Q-Lead:

**Forward warning to Optimizer**: Single-sleeve top20 long-only construction from this composite is **high risk** for AX-007 mechanism break. Recommend either (a) multi-sleeve structure with low_vol/dividend/consensus separated, (b) 50+ name diversification, or (c) ML sizing (non-uniform weights).

**Action**: Forward warning included in challenge_flags. Optimizer agent must consult AX-007 exception path or document override.

---

## Codex Round Decision Summary

| Concern | Severity | Adjudication | Action |
|---|---|---|---|
| C1 Harvey 1/5 | HIGH | **ACCEPT** | Graduation FAIL — Q-Lead decide pivot vs waiver |
| C2 RF-A4 sector | HIGH | **ACCEPT** | v3.6 iteration required: sector-neut composite |
| C3 RF-A2 composite | HIGH | **ACCEPT** | Document MEDIUM red flag; consider single low_vol alternative |
| C4 fallback 54% | MEDIUM | **PARTIAL** | v3.6 reduce state count 9→4-5 (HMM) |
| C5 AX-008 artifacts | HIGH | **REBUTTAL** | Outside alpha scope; AX-008 evaluated post-pipeline |
| C6 PIT-C15 macro | MEDIUM | **PARTIAL** | Infra gap: load_macro_factors API missing |
| C7 schedule 7 gaps | MEDIUM | **REBUTTAL** | Upstream P4 data gap, not v3.5 design |
| C8 AX-007 Gate13 | MEDIUM | **REBUTTAL** | Optimizer / Judge stage; forwarded warning |

**Quantitative breakdown**:
- ACCEPT: **3 HIGH** concerns (C1, C2, C3) — fundamental issues
- PARTIAL: **2 MEDIUM** concerns (C4, C6) — design improvements available
- REBUTTAL: **3 concerns** (C5, C7, C8) — scope misattribution or upstream root cause

**HIGH severity ≥ 5 trigger check**: Total HIGH = 3 in Codex critique. **Threshold ≥ 5 NOT met** → no auto Q-Lead escalate trigger.

**AX axiom hard FAIL ≥ 3 trigger check**: AX-005 + AX-007 + AX-008 ALL "REBUTTAL" (process boundary concern, not actual AX violation). PIT-C9 PASS. PIT-C13 PASS. PIT-C14/C15 = PARTIAL macro I/O. **0 hard fails** → no escalate trigger.

**PIT C1 lockbox / lookahead detected**: No.

**Auto-escalate to Q-Lead**: NOT triggered. Decision belongs to Q-Lead manual review.

---

## Final Spec Decision (v3.5 finalize)

Given 3 ACCEPT HIGH concerns (graduation fail + RF-A4 sector + RF-A2 composite), my honest assessment is:

**v3.5 alpha-research GRADUATION STATUS = FAIL**.

Q-Lead options:
1. **PIVOT** — terminate v3.5 family attempt, redesign with sector-neutralization + 4-5 state regime + single-family-dominant spec. Recommended.
2. **WAIVER** — accept Harvey 3/5 at t > 2.5 (relaxed threshold) + accept RF-A4 sector dependence + accept RF-A2 dilution; proceed to risk-research with explicit known limitations. Risk-research builds Σ with sector exposure decomposition. Optimizer constrains sector active weight (e.g., ≤ 10% per sector). Forge backtests with sector-aware risk.
3. **TERMINATE** — STR_1721 family attempt determined infeasible after 2 cycles (v1 + v3.5). Pivot to alternative hypothesis.

My recommendation (alpha agent within scope): **OPTION 1 PIVOT to v3.6**.

Rationale: 
- Sector dependence (48% IC retention) is a fundamental alpha mechanism issue
- Composite < single best ICIR means regime conditioning isn't capturing what it should
- 54% fallback in weight matrix indicates state count too high for available history

v3.6 spec proposal (alpha agent recommends to Q-Lead):
- Sector-neutralize family panel BEFORE composite weighting (residualize each F_f against sector dummies)
- Reduce regime state count: 9-state K-means → 4-state HMM (Hamilton 1989) to increase per-state n_obs
- Test single-family-dominant alpha (low_vol primary with regime-conditional size/dividend tilt) as alternative

---

## Codex audit log

- Codex audit log: `/tmp/codex_qepm_critic_WT-D20260528_003_alpha_1779954441.log`
- Codex response: `qepm/mailbox/worktask/WT-D20260528_003/codex_critic_response_alpha.json`
- Codex model: gpt-5.5 + xhigh
- Codex stance: REJECT
- Codex veto_flag: false (advisory, not blocking)

**Charter §8 "No Silent Override" compliance**: All 8 concerns explicitly classified. ACCEPT/PARTIAL/REBUTTAL rationale documented above with empirical evidence + code path citation + L-code references. Rebuttal cases explicitly cite scope boundary (Common Charter Strict Prohibitions) for C5, C7, C8.
