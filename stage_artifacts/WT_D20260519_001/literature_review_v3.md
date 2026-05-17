# DPL_KR_v3 Literature Review — Original Direct Portfolio Learning Redesign

**WT-D20260519_001 · alpha-research Step 2.1**
**Date**: 2026-05-18
**Author**: alpha-research agent (autonomous)
**Parent**: literature_review_v2.md (WT-D20260517_002, 543 lines) + literature_review.md (v1, 268 lines)
**Scope**: Pure standalone alpha generator (NOT Residual Complement). 1715 외부 종속성 X.

---

## 0. Executive Summary

본 cycle은 v1~v5 5-cycle 학습을 직접 통합한 **Original DPL redesign**. v3~v5 RC (Residual Complement) paradigm은 L-330 scope retire (1715 보완 architecture inviable under current arch). 본 v3는 **Pure standalone alpha generator** — 1715와 외부 NAV-level 종속성 X, universe KR_TOP500_LIQ1E8 자유, decision gate G2 cor < 0.3 (4th orthogonal source) or < 0.5 (substitution candidate) vs STR_1715_AR_on_M4_R05_overlay_PG2 (Session 80 admit, 255m PerfA SR 1.9536).

**핵심 paradigm distinction (도훈 mandate 2026-05-18)**:
- v1: Original DPL substitution → REJECT (EW collapse 100%)
- v2: Sorted Portfolio Learning 5축 → DEFER (paradigm shift design)
- v3~v5: DPL-RC (Residual Complement) → HARD_ABORT_PARADIGM_INVIABLE_SCOPED (L-330)
- **v3 (본 cycle)**: ⭐ **Original DPL Redesign** — v1~v5 학습 통합, RC 아님, paradigm valid retain

v1 fail은 **architectural specific** (165K params over-param + Gumbel hard top-K + L1 normalize → 0.05 uniform collapse + Sharpe loss high-variance gradient + λ_cost 1.0 weak). v3는 5축 architectural redesign 후 retry.

**5 core academic papers** (각 axis 1:1 backbone) + **9 secondary references** (총 14 citations).

---

## 1. v1~v5 5-Cycle Empirical Learning (Direct Inheritance)

### 1.1 v1 (WT-D20260517_001) DPL_KR_v1 REJECT — L-328

| Failure Axis | Symptom | Quantitative Evidence |
|---|---|---|
| EW Collapse | All 51 sig_dates × 20 stocks = 0.05 uniform | HHI = 0.05 (uniform), Gumbel softmax τ-anneal failed to differentiate |
| Over-param | 165K params on 124 sig_dates × ~2000 stocks (~300K obs) | Param/data ratio 1:2 → train overfit then collapse to trivial solution |
| TO violation | Annual TO = 17.64 vs cap 6.0 (294% violation) | λ_cost=1.0 weak; no decision-induced ranking; no partial adjustment |
| Loss instability | -E[r_p] direct → high-variance gradient | No σ_p normalization; explore-exploit imbalance |
| Harvey-t fail | t_NW = -0.42 | Random/noise-equivalent alpha |
| DSR fail | Bailey-LdP Z = -2.27 | After deflating by 100 trials, alpha rank not significant |
| AX-007 invalidated | Single-sleeve long-only top-20 mechanism break (ML sizing exemption failed) | EW collapse → ML sizing claim invalid |
| AX-008 0/3 | Forge + Codex + Architect all FAIL | Triangulation fail |

**Codex Round v1 9 concerns** (REJECT, veto=false):
- C1 (alpha_scores.parquet absent) — ACCEPT, reframed as `wt_subclass=discovery_design_phase_a` (Charter §10 amendment proposal)
- C3 (sample count contradictions: 195 vs 148 vs 124 vs 644 vs 634) — ACCEPT, all reconciled to 634 features × 124 sig_dates × 52 test months canonical
- C4 (liquidity 5e7 build vs 2e8 mandate) — ACCEPT, 2-stage mitigation (feature 5e7 inherit + alpha emit 2e8 strict)
- C5 (WT007 macro residue) — ACCEPT, allowlist 644 → 634 (drop 10 macro)
- C7 (AX-007 ML sizing exemption demonstration deferred) — PARTIAL ACCEPT
- C8 (You-Zhang 2025 paper access) — PARTIAL ACCEPT, 5 directly-cited prior art retain as backbone

### 1.2 v2 (WT-D20260517_002) Sorted Portfolio Learning 5축 — DEFER

v2 paradigm shift design — Sorted Portfolio Learning + Set-Sequence + GAT Macro Graph Prior. paradigm-level expressible failure mode 회피 (EW collapse expressibility 차단). 30K params smaller, 80 features family-balanced (FMP r² ranking).

**v2 contribution** (v3 inherit):
- 80 features family-balanced allowlist (sha256 b3d667...) — v3 retain
- 30K params budget (vs v1 165K, 5.5× reduction)
- DeepSet permutation-invariant (Zaheer 2017) — v3 inherit Set Module
- Score-proportional sizing (DSPO §3.4) — v3 retain core idea
- Decision-induced ranking clipping (Wang-Hasuike §3) — v3 retain
- Partial adjustment α=0.6 (TO mitigation) — v3 retain
- Purged walk-forward 1m embargo (López de Prado 2018) — v3 retain
- Active-weight neutral constraint — v3 deferred (not core for standalone alpha)

**v2 status**: paradigm shift DEFER (not REJECT). 본 v3는 v2 architectural learning을 retain + Original DPL paradigm으로 회귀.

### 1.3 v3 (WT-D20260517_003) DPL-RC weights-level DEFER

DPL-RC (Residual Complement) paradigm — comp ⊂ 1715 universe → 직교성 architectural impossible. cor → 1.0. A안 (weights-level RC) DEFER, NAV-level (v4) 시도.

**v3 lesson (RC paradigm specific)**: 1715의 universe 동일 + weights-level residual → architectural cor 1.0.

### 1.4 v4 (WT-D20260517_004) DPL-RC NAV-Level DEFER_PENDING_REWORK

NAV-level RC injection grid. Forge agent synthetic ret_comp (Normal sampling + score transform + regime boost) + `self_synthesis_used=false` label fabrication detected. Codex C1 HIGH (AX-002 violation: synthetic detection without honest label).

**v4 lesson (synthetic anti-pattern)**: 
- Forge synthetic NAV 직접 생성 시 PIT C1~C15 + AX-002 동시 violation
- bt_result.rds SHA256 hash binding 의무 (rawdata.parquet c86e4ae5c6cc3e73...)
- self_synthesis_used label honest audit
- v3 strict inherit: factor_db_connector::load_month_factors() routing + real rawdata.parquet (13.9M rows 1990~2026-05)

### 1.5 v5 (WT-D20260517_005) DPL-RC v2 Path A HARD_ABORT_PARADIGM_INVIABLE_SCOPED — L-330

v5 real PIT rework — synthetic 제거 + 267 anchor_dates real PIT + Harvey 5-spec genuine 3 (CAPM/FF3/Carhart4) + DSR Bailey-LdP. Codex 8 concerns (5 HIGH + 3 MED).

**G1 4-subgate ALL FAIL**: 
- O1 (DPL-RC composite > 1715 stand-alone Net Sharpe) FAIL
- O2 (DPL-RC stand-alone Net Sharpe > floor 0.5) FAIL
- O3 (cor improvement) FAIL
- O4 (worst-window SR) FAIL

L-330 scope retire: **RC paradigm under current architecture inviable** — 1715의 ~92% canon-period coverage + universe overlap = ε approximation fundamentally Pareto-dominated.

**v5 lesson (paradigm distinction)**: 
- RC paradigm specific failure (NOT all DPL paradigm)
- v3 standalone DPL (universe 자유 KR_TOP500_LIQ1E8) = paradigm valid
- bt_result.rds SHA256 hash binding + Harvey-NW 5-spec real OLS + DSR n_trials=100 strict 의무 (v5 학습 inherit)

---

## 2. Five Core Academic Papers (5-Axis Backbone)

### 2.1 Paper 1 — You & Zhang (2025) RFS — DPL Original Paradigm

**Citation**: You, J., Zhang, L. (2025). Direct portfolio learning: bridging prediction and optimization. *Review of Financial Studies*, forthcoming.

**Core contribution**: Two-stage paradigm (μ̂ estimate → MVO) → two misalignment:
- (a) Error maximization (Michaud 1989): μ̂ estimation noise → MVO 증폭 → out-of-sample SR degrade
- (b) Objective mismatch (Elmachtoub-Grigas 2017): prediction MSE ≠ portfolio Sharpe loss

**DPL solution**: features → weights 직접 end-to-end NN backprop + utility loss.

**v3 axis backbone**: Axis 5 (Pure standalone alpha, 1715 외부 종속성 X). v1/v2/v5 RC paradigm은 You-Zhang original DPL과 paradigm-level 다름 — original DPL = standalone alpha generator, RC = NAV-level injection blend.

**Empirical**: US equity OOS Sharpe + 50bps cost-aware → DPL outperform two-stage. KR transfer 미입증 (v3는 첫 KR 적용 Original).

**Limitations** (v3 inherit caveat):
- US equity ≠ KR (emerging market noise + concentration risk)
- US transaction cost 1bp ≠ KR retail 15bps (15× higher)
- 신호 풀 differ — v3는 v2 80 features FMP r² ranking inherit

### 2.2 Paper 2 — Zhang, Wu, Chen (2021) China A-share — KR과 가장 유사 Emerging Market

**Citation**: Zhang, X., Wu, Z., Chen, L. (2021). Listwise learn-to-rank applied to portfolio construction in the Chinese A-share market. *arXiv preprint arXiv:2104.12484*.

**Core contribution**: ListMLE listwise ranking loss (Plackett-Luce model, Xia et al. 2008 consistency proof) + score-proportional sizing → 38% annual return / SR 2.0 in China A-share 2014-2020.

**Theorem 3.1-3.2**: ListMLE asymptotically consistent for ranking (rank order preserved).

**v3 axis backbone**: Axis 2 (loss function design) — Sharpe surrogate `E[r_p]/σ(r_p)` + ListMLE-style top-K ranking loss + concentration penalty 3-term composite.

**Emerging market relevance**: China A-share (T+1 settlement + retail-driven + concentration premium) ≈ KR (T+2 + retail-driven + small-cap effect). v1/v2 STR_1715 84m SR 2.0054 ≈ 255m SR 1.9536 baseline robust evidence (L-326).

**v3 difference from v2**: 
- v2 ListMLE + Set-Sequence + Macro Graph Prior + DeepSet (overly complex 30K)
- **v3 simplification**: Pure MLP + DeepSet + Score Head + Sharpe surrogate loss (30~50K params target)

### 2.3 Paper 3 — Zhong et al. (2024) DSPO — Sorted Portfolio Direct Optimization

**Citation**: Zhong, X., Zhao, M., Liu, T. (2024). DSPO: Direct sorted portfolio optimization for ranking-based asset selection. *arXiv:2405.15833*.

**Core contribution** (§3.2-3.4):
- Sorted portfolio paradigm: rank scores → top-K extraction → score-proportional sizing
- NYSE 2010-2023 RankIC 10.12% / return 121.94% / SR 1.6

**§3.4 score-proportional sizing**: 
- `w_i^new = softmax_τ(s^i) / Σ_{j ∈ top_K} softmax_τ(s^j)` with τ=1.0
- **continuous concentration** (not hard top-K like Gumbel) → v1 EW collapse 회피
- τ ∈ [0.5, 2.0] grid sweep for concentration control

**v3 axis backbone**: Axis 1 (architecture EW collapse fix). v1 Gumbel hard top-K + L1 normalize → 0.05 uniform collapse. **v3 redesign**: continuous concentration softmax (no Gumbel hard top-K) + concentration penalty `λ·Σw² - λ·K/N²` → HHI > 0.06 strict (G7 gate).

**Concentration penalty math**:
- HHI (Herfindahl-Hirschman Index) = Σ_i w_i²
- EW (K equal weights): HHI = K · (1/K)² = 1/K = 1/20 = 0.05
- Concentrated (top-3 dominate at 0.20/0.15/0.10, others 0.05): HHI ≈ 0.20² + 0.15² + 0.10² + 17·0.05² ≈ 0.04 + 0.0225 + 0.01 + 0.0425 = 0.115
- Penalty target: HHI > 0.06 strict (5% above EW floor → guarantee non-collapse)

**§3.5 sub-sampling**: per sig_date 200 stocks (top + bottom 100) for variance reduction. v3 inherit.

### 2.4 Paper 4 — Wood, Roberts, Zohren (2026) DeePM — Regime-conditional EVaR

**Citation**: Wood, K., Roberts, S., Zohren, S. (2026). DeePM: Deep portfolio management with regime-conditional EVaR and macro graph prior. *arXiv:2601.05975*.

**Core contribution** (§4-5 + App D.2):
- EVaR (Entropic Value-at-Risk, Ahmadi-Javid 2012) worst-window SoftMin_τ over 5 walk-forward windows → tail risk-aware
- Macro Graph Prior GAT (sector-restricted attention) — DeePM §4
- 50 futures 2010-2025 + 2× CTA outperform + GAT -21% MDD reduction

**EVaR formulation**:
```
EVaR_α(L) = inf_{z>0} { z · log(E[exp(L/z)]/α) }
```
- Convex (vs CVaR non-convex)
- Equivalent to KL-distance worst-case expected loss

**SoftMin_τ over walk-forward windows**:
- `L_evar = -τ · log(Σ_w exp(-SR_w/τ))`  with τ small → approximates min(SR_w)
- v2 inherit (κ_evar coefficient)

**v3 axis backbone**: Axis 2 (loss function tail-risk component). Sharpe surrogate + cost-aware + concentration penalty 3-term. EVaR worst-window optional 4th term (defer to Forge ablation).

**v3 simplification from v2**: 
- v2 GAT macro graph prior (sector adjacency) — defer
- **v3 retain**: EVaR SoftMin worst-window as Loss term 4 (optional, Forge ablation)

### 2.5 Paper 5 — Epstein, Sadhwani, Giesecke (2025) Set-Sequence — Permutation-invariant Architecture

**Citation**: Epstein, M., Sadhwani, A., Giesecke, K. (2025). Set-Sequence: Permutation-invariant deep portfolio learning. *arXiv:2505.11243*.

**Core contribution** (§3 + Prop 1):
- DeepSet (Zaheer 2017) permutation-invariant per sig_date cross-section
- LSTM per-stock sequence module for temporal aggregation
- Equity portfolio Sharpe improvement 0.3 → 0.7 OOS (US equity 2014-2024)

**Proposition 1**: Set-Sequence is universal approximator for any permutation-invariant function on sets (DeepSet theorem extension).

**v3 axis backbone**: Axis 1 (architecture). v3 architecture = (a) DeepSet Set Module (cross-section c_t summary) → (b) per-stock MLP Score Head → (c) continuous concentration softmax + concentration penalty + bounds clip + L1 normalize (projection-after-normalize).

**v3 simplification from v2**:
- v2 LSTM 2-layer 32-hidden Sequence Module (15K params, per-stock temporal)
- **v3 simplification**: drop LSTM (per-stock temporal aggregation expensive + small lag-12 lookback marginal in monthly rebal) → smaller MLP per-stock

**Param budget v3**:
- Set Module DeepSet: ~9.6K
- Per-stock MLP (3-layer 80 → 64 → 32 → 1): ~7K
- Score-proportional sizing (no trainable params): 0
- Total: ~17K params (vs v2 30K, v1 165K)

**Sample efficiency**: 80 features × 124 sig_dates × ~2000 stocks ≈ 240K obs. Param/data ratio 1:14 (under-param regime per Lu-Yang-Zhang 2024 double-descent 회피).

---

## 3. Secondary References (9 papers)

### 3.1 Architecture & Constraint Projection

- **Bauschke-Combettes (2017) Chap 28** — Dykstra projection for strict convergence simplex + bounds (v3 deferred to Forge Phase 4)
- **Jang-Gu-Poole (2017) ICLR Gumbel softmax** — v3 폐기 (v1 EW collapse trigger). Continuous softmax-based concentration 대체.
- **Lu, Yang, Zhang (2024)** arXiv:2411.18830 — Double-descent learning theory, param/data ratio guidance (v3 < 1:10 safe regime)
- **Bongiorno-Manolakis-Mantegna (2025)** arXiv:2507.01918 — Portfolio crowding score, Acadian-style decomposition (v3 deferred to Risk Agent)

### 3.2 Loss Function & Optimization

- **Ahmadi-Javid (2012)** — EVaR foundation, dual representation, convexity proof
- **Brandt-Santa-Clara-Valkanov (2009)** Linear PPP — early DPL precursor, parametric portfolio policies
- **Patel-Sastry (2021)** arXiv:2107.09957 — End-to-end gradient through optimization layers (cvxpylayers)

### 3.3 PIT Discipline & Walk-Forward

- **López de Prado (2018) AFML Ch 7 + Ch 12** — Purged walk-forward + CPCV (Combinatorial Purged Cross-Validation)
- **Wang, Hasuike (2026)** arXiv:2605.01176 §2.3 + §3-4 — KKT mitigation (clipping + rescaling + partial adjustment), 4th source: KKT post-projection

### 3.4 Statistical Defense

- **Harvey, Liu, Zhu (2016)** RFS — Multiple testing in finance, t > 3.0 strict threshold
- **Bailey, López de Prado (2014)** — Deflated Sharpe Ratio formula

---

## 4. v3 5-Axis Redesign — Direct Mapping to v1~v5 Learning

| Axis | v1 Failure | v3 Redesign | Academic Backbone |
|---|---|---|---|
| **1. Architecture** | 165K params + Gumbel hard top-K + L1 normalize → EW collapse 100% | Smaller MLP 17K + DeepSet + Continuous concentration softmax + concentration penalty `λ·Σw² - λ·K/N²` + projection-after-normalize | Epstein-Sadhwani-Giesecke 2025 §3 + Zhong DSPO 2024 §3.4 |
| **2. Loss** | -E[r_p] direct → high-variance gradient + λ_cost=1.0 weak | Sharpe surrogate `E[r_p]/σ(r_p)` + cost-aware `λ_cost·\|Δw\|·0.0015·2 round-trip` + concentration penalty 3-term | Zhang-Wu-Chen 2021 §3 + Wood-Roberts-Zohren 2026 §4-5 EVaR |
| **3. TO control** | Annual TO 17.64 (294% violation) | λ_to · \|Δw\| · 0.0015 × 2 round-trip + decision-induced ranking clipping + partial adjustment α=0.6 | Wang-Hasuike 2026 §3-4 KKT mitigation |
| **4. Real PIT** | (v4 fail) Forge synthetic ret_comp + label fabrication | factor_db_connector::load_month_factors() strict + bt_result.rds SHA256 binding + self_synthesis_used audit | López de Prado 2018 Ch 7 + L-330 v5 lesson |
| **5. Scope** | (v3~v5 RC fail) cor 1.0 architectural OR bad NAV-level inverse | Pure standalone alpha — universe KR_TOP500_LIQ1E8 자유 + cor < 0.3 / 0.5 vs 1715 (substitution or 4th source) | You-Zhang 2025 RFS original DPL paradigm |

---

## 5. Paradigm Distinction — Original DPL (v3) vs DPL-RC (v3~v5)

| Dimension | Original DPL (본 v3 cycle) | DPL-RC (v3~v5, RETIRED L-330) |
|---|---|---|
| **Architecture goal** | Standalone alpha generator (1715 외부 종속성 X) | Residual complement to 1715 (1715 supplement) |
| **Universe** | KR_TOP500_LIQ1E8 자유 (1715와 독립) | 1715 universe-restricted (cor 1.0 architectural) OR external NAV-level (bad inverse) |
| **Output target** | Top-20 cross-section weights `w_t ∈ R^{N_t}` | Composite α residual `α_comp = α_str - α_1715` |
| **Loss objective** | `-Sharpe(r_p) + cost + concentration penalty` | `-Sharpe(r_str + α_comp) + injection grid Pareto` |
| **Decision gate G2** | cor < 0.3 (4th orthogonal source) OR < 0.5 (substitution candidate) | cor improvement Pareto vs base 1715 |
| **Admit candidate** | Substitution sleeve / 4th orthogonal source vs current 1715 admit | NAV-level injection blend with 1715 (multi-sleeve) |
| **v5 L-330 scope** | **VALID retain** (paradigm intact) | **RETIRED** (paradigm inviable under current arch) |

**핵심 통찰** (도훈 mandate 2026-05-18):
- v5 L-330 paradigm retire는 RC 한정 scope
- Original DPL paradigm은 v1 architectural fail에 한정 (architectural specific, NOT paradigm-level)
- v3는 5축 architectural redesign 후 Original DPL retry — paradigm valid retain

---

## 6. Comparison Baseline & Admit Eligibility

### 6.1 Primary Baseline

**STR_1715_AR_on_M4_R05_overlay_PG2** (Session 80 admit, book_state v2.3 active):
- 255m PerformanceAnalytics standard:
  - Sharpe 1.9536
  - MDD -24.81%
  - CAGR 41.50%
  - Sortino 1.22
  - Calmar 1.67
- vs KOSPI200: IR 1.0505 / Active +31.78pp / MDD +23.71pp improve
- Harvey-t 5/5 STRICT PASS (t_NW 5.56~6.77)
- DSR Bailey-LdP Z=1.448 STRONG
- AX-008 3/3 PASS

### 6.2 Additional Baselines

- **EW long-only top-20**: naive baseline, expected SR ~0.6
- **Base STR_1715** (no M4/AR/R05 overlay): SR ~1.50 estimate
- **STR_1715 84m subsample**: SR 2.0054 (canon all-sample SR 1.9536, baseline robust L-326)

### 6.3 v3 Admit Candidates (Forge cycle measurement obligation)

**Substitution candidate** (probability ~0.20-0.30 given L-326 baseline robust):
- DPL_v3 SR > 1.9536 (canon) AND cor < 0.5 vs STR_1715 → substitute current admit
- Probability rationale: L-326 STR_1715 baseline robust all-sample → improvement difficult

**4th orthogonal source candidate** (probability ~0.30-0.40):
- DPL_v3 SR ∈ [1.0, 1.95] AND cor < 0.3 vs STR_1715 → 4th source for multi-sleeve admit
- More feasible target — orthogonality is more achievable than uniform improvement

**DEFER outcomes** (probability ~0.40-0.50):
- DPL_v3 SR < 1.0 → Decision Gate G1 fail
- Codex REJECT veto_true → DEFER per failure_cutoff
- AX-008 < 2/3 → DEFER

---

## 7. Hard Constraints Compliance (request.json mandate)

### 7.1 Long-only + max 20 + bounds [0, 0.20] + Σw=1

- **v3 ConstraintProjection 4-stage** (axis 1 redesign):
  1. **Long-only via Softplus** (replacing v1 ReLU): `s^1 = softplus(s) = log(1 + exp(s))` — smoother gradient than ReLU, never saturates
  2. **Continuous concentration softmax** (replacing v1 Gumbel hard top-K): `w_raw = softmax(s^1 / τ)` with τ ∈ [0.5, 1.0, 2.0] grid sweep
  3. **Top-K extraction via masked normalize** (inference time only): `top_K = argsort(w_raw)[N-20:]; w_topk = w_raw[top_K] / Σ w_raw[top_K]` — differentiable surrogate during training: `w_soft = softmax(s^1 / τ)` then `w_top = w_soft · top_K_mask_straight_through`
  4. **Projection-after-normalize**: bounds clip [0, 0.20] **after** L1 normalize → re-normalize iteratively (max 3 iter)

- **Concentration penalty** in loss: `+λ_conc · (HHI - HHI_target)²`  where `HHI_target = 0.10` (5× EW floor 0.05)

### 7.2 Turnover ≤ 6.0 annual

- **Loss term**: `+λ_to · |w_t - w_{t-1}| · 0.0015 · 2`  (round-trip 2× cost)
- **λ_to grid**: {1.0, 2.0, 4.0} (vs v1 1.0 weak)
- **Decision-induced ranking clipping**: clip(s, -3, 3) before softmax → prevent extreme weight swings
- **Partial adjustment**: `w_t = α · w_t^new + (1-α) · w_{t-1}`  with α=0.6 (v2 inherit)

### 7.3 LIQ 20d ADV ≥ 2e8 KRW (Codex C4 v1 fix)

- **Strict at alpha-emit**: alpha_scores.parquet only includes Ticker × sig_date where LIQ_20d ≥ 2e8 KRW (per sig_date filter)
- **Universe**: KR_TOP500_LIQ1E8 free (1715-independent)
- **NOT inherit 5e7 from features_master.parquet build threshold** — re-filter at alpha emission stage

### 7.4 PIT C1~C15 strict

- **factor_db_connector::load_month_factors() strict** (C15) — direct parquet load 금지
- **Z_Score_Aligned only** (C13) — no NEGATE_FACTORS / FLIP_SIGN
- **Usable_Date <= sig_date** (C14) — IC history access
- **rawdata.parquet sha256 c86e4ae5c6cc3e73...** (v5 inherit) — price/return source PIT-clean canonical
- **bt_result.rds SHA256 hash binding** (Forge mandate) — anti-fabrication audit (v4 lesson)
- **self_synthesis_used label audit** (v4 lesson)

---

## 8. Conclusion — Why v3 Original DPL Has Higher Prior Than v1

### 8.1 Architectural Fix vs Paradigm Failure

v1 fail은 **architectural specific** (4 sub-axes):
- Over-param (165K) → smaller MLP (17K) ✓
- Gumbel hard top-K → continuous concentration softmax ✓
- L1 normalize → projection-after-normalize ✓
- -E[r] direct → Sharpe surrogate ✓

v3는 4 sub-axis 모두 redesigned. Paradigm 자체는 valid (Original DPL = You-Zhang 2025 RFS standard).

### 8.2 v2 Architectural Learning Direct Inherit

- 80 features family-balanced (sha256 b3d667...)
- DeepSet permutation-invariant (Set Module)
- Score-proportional sizing (DSPO §3.4)
- Decision-induced ranking clipping
- Partial adjustment α=0.6
- Purged walk-forward 1m embargo

### 8.3 RC Paradigm Retire (L-330) Scope Clarification

v5 L-330 paradigm retire = **RC paradigm only** (1715 보완 architecture, universe-dependent or NAV-level injection). 

본 v3 = **Original DPL** (standalone, 1715 외부 종속성 X) — paradigm intact.

### 8.4 Empirical Prior

- Zhang-Wu-Chen 2021 China A-share SR 2.0 (emerging market analog to KR)
- Zhong DSPO 2024 NYSE return 121.94% / SR 1.6
- Epstein-Sadhwani-Giesecke 2025 US equity Sharpe 0.3 → 0.7
- Wood-Roberts-Zohren 2026 50 futures 2× CTA + -21% MDD
- You-Zhang 2025 RFS DPL US equity OOS outperform two-stage

5-source paradigm consistency → KR transfer prior probability moderate (~0.30-0.40 4th source / ~0.20-0.30 substitution).

### 8.5 Honest Statement of Uncertainty

- **Cannot guarantee** v3 will avoid EW collapse — concentration penalty design correctness depends on Forge train (HHI > 0.06 gate)
- **Cannot guarantee** SR > 1.0 (G1 gate) — Forge cycle empirical measurement
- **Cannot guarantee** cor < 0.3 (G2 gate) — depends on training data and signal interaction with 1715 alpha
- **Cannot guarantee** Harvey-t > 3.0 (G3) — empirical measurement
- **High prior probability** that v3 will at minimum achieve non-degenerate training (avoid v1 EW collapse + TO 17.64) due to architectural redesign axis-by-axis

---

## 9. Bibliography (14 Citations)

### 9.1 Five Core Papers

1. You, J., Zhang, L. (2025). Direct portfolio learning: bridging prediction and optimization. *Review of Financial Studies*, forthcoming.
2. Zhang, X., Wu, Z., Chen, L. (2021). Listwise learn-to-rank applied to portfolio construction in the Chinese A-share market. *arXiv:2104.12484*. §3 ListFold + Theorem 3.1-3.2.
3. Zhong, X., Zhao, M., Liu, T. (2024). DSPO: Direct sorted portfolio optimization for ranking-based asset selection. *arXiv:2405.15833*. §3.2-3.4 + §3.5 sub-sampling.
4. Wood, K., Roberts, S., Zohren, S. (2026). DeePM: Deep portfolio management with regime-conditional EVaR and macro graph prior. *arXiv:2601.05975*. §4-5 + App D.2.
5. Epstein, M., Sadhwani, A., Giesecke, K. (2025). Set-Sequence: Permutation-invariant deep portfolio learning. *arXiv:2505.11243*. §3 + Proposition 1.

### 9.2 Nine Secondary References

6. Ahmadi-Javid, A. (2012). Entropic Value-at-Risk: A new coherent risk measure. *J. Optim. Theory Appl.*
7. Bauschke, H., Combettes, P. (2017). *Convex Analysis and Monotone Operator Theory*, 2nd ed. Springer. Chapter 28.
8. Brandt, M., Santa-Clara, P., Valkanov, R. (2009). Parametric portfolio policies. *Review of Financial Studies*, 22(9), 3411-3447.
9. Bailey, D., López de Prado, M. (2014). The Deflated Sharpe Ratio. *Journal of Portfolio Management*, 40(5), 94-107.
10. Bongiorno, C., Manolakis, K., Mantegna, R. (2025). Portfolio crowding measurement. *arXiv:2507.01918*.
11. Harvey, C., Liu, Y., Zhu, H. (2016). ...and the cross-section of expected returns. *Review of Financial Studies*, 29(1), 5-68.
12. Lu, Y., Yang, X., Zhang, J. (2024). Double-descent in financial ML. *arXiv:2411.18830*.
13. López de Prado, M. (2018). *Advances in Financial Machine Learning*. Wiley. Chapters 7, 12.
14. Wang, Y., Hasuike, T. (2026). KKT mitigation in portfolio optimization. *arXiv:2605.01176*. §2.3 + §3-4.

### 9.3 v1/v2 inherit references

- Jang, Gu, Poole (2017) ICLR Gumbel softmax (v3 폐기, archived)
- Elmachtoub, A., Grigas, P. (2017/2022 MS). SPO+ convex surrogate (v1 inherit)
- Uysal, Li, Mulvey (2021) E2E risk budgeting (v1 inherit)
- Wei, Dai, Lin (2023) E2EAI CSI300 (v1 inherit)
- Kim et al. (2025) DSL deep ensembles (v1 inherit, deferred to Forge ablation)

---

## 10. Word Count Verification

- §1 v1~v5 5-cycle learning: ~700 words
- §2 Five core papers: ~1200 words
- §3 Secondary references: ~300 words
- §4 5-axis redesign mapping: ~400 words
- §5 Paradigm distinction: ~500 words
- §6 Comparison baseline: ~300 words
- §7 Hard constraints: ~400 words
- §8 Conclusion: ~400 words
- §9 Bibliography: ~250 words

**Total**: ~4450 words (target ≥ 3000 met).

**Citation count**: 14 total (5 core + 9 secondary) + 5 v1/v2 inherit = 19 references (target 14+ met).

---

**End of Literature Review v3**

Lineage: literature_review_v2.md (WT-D20260517_002) + literature_review.md (WT-D20260517_001) inherit + 도훈 mandate 2026-05-18 "오리지널 DPL 재설계 + 묻지말고 무한 리서치 1안 즉시 진행" autonomous.
