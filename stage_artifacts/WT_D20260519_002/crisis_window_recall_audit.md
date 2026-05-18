# Crisis Window Recall Audit — WT-D20260519_002 Bear Prediction Engine v1.0

**Agent**: risk-research (regime_sensor scope)
**As-of**: 2026-05-18
**Scope**: 8 crisis epochs × lead-time prior + true positive prior + false positive cost diagnostic
**Authority**: Risk diagnostic. Threshold τ ∈ {0.3, 0.5, 0.7} sensitivity analysis (alpha admit binding metric, NOT optimizer weight).

---

## 1. Audit Philosophy

Bear regime sensor의 **operational utility**는 단순 G1 5-subgate AUC/Brier/Recall/Precision/sub-window을 넘어:
- **Lead-time** (어떤 backbone가 며칠/몇주/몇달 전에 signal emit?)
- **False positive cost** (실투 시 cash 이동 = 15bps × 2 round-trip = 30bps drag per false alarm)
- **Threshold sensitivity** (τ=0.3 vs τ=0.5 vs τ=0.7 — Recall/Precision/FP rate trade-off)

본 audit은 각 crisis epoch별 **lead-time prior + FP cost expectation + threshold sensitivity prior** 정리. Forge cycle 실측 binding.

---

## 2. Lead-time Priors per Crisis (학술 backbone empirical literature)

각 backbone의 학술 literature reported lead-time:

| Backbone | Reference | Lead-time prior | Notes |
|---|---|---|---|
| **F01~F05 Yield Curve** | Estrella-Hardouvelis 1991 JF | **6~18 months** | "inversion preceded all 7 US recessions 1957-1988" |
| **F06~F10 LEI** | Stock-Watson 2003 JEL | **3~9 months** | PMI / Housing / Consumer Sentiment |
| **F11~F14 VIX/Vol** | Engle-Mistry 2014 JFE | **0~3 months** (coincident) | vol cluster lag 적음 |
| **F17 Asymmetric cor** | Ang-Chen 2002 JFE | **0~1 months** (coincident) | down-market correlation |
| **F20~F22 NFCI/Stress** | Adrian-Brunnermeier 2016 AER | **3~6 months** | CoVaR proxy financial conditions |
| **F23~F25 Credit spread** | Gilchrist-Zakrajsek 2012 AER | **3~9 months** | EBP recession leading |
| **F26~F28 SEFRS** | WT-D20260518_001 Phase A | **5~30 days** (intraday → daily) | ETF flow short-cycle |
| **F29~F30 Foreign flow** | KR empirical | **0~2 weeks** | flow reversal short |
| **MSM Hamilton 1989** | Hamilton 1989 ECTA | **0 months** (state-conditional) | regime probability 추정 |

**Composite lead-time expectation**:
- **Long-lead** (F01~F10, 3~18m): 학술 prior strong → recession 예측에 강함, **but bear month prediction 다를 수 있음** (recession ≠ bear month exact)
- **Mid-lead** (F20~F25, 3~9m): financial conditions deterioration → bear regime onset
- **Short-lead** (F11~F14, F17, F26~F32, 0~3m): vol spike + flow reversal = bear regime concurrent

**Risk diagnosis**: **monthly forecast horizon 1M (alpha spec)** 가 mid-short lead-time backbone에 최적 매칭. **Long-lead yield curve features (F01~F05)** 는 1M horizon에 too-early signal 가능성 — 예측 lead-time이 너무 길면 false alarm 누적.

---

## 3. True Positive / False Positive Cost per Crisis

각 crisis epoch별 expected behavior + downstream cost:

### Crisis 4: 2008 GFC (S2~S3)
- **8 backbones all strong** (feature_stability_audit Section 4)
- **Expected Recall**: 0.80~1.00 per τ=0.5 (5 bad months, model gets 4~5)
- **Expected Precision**: 0.60+ (FP <= 3 in 12-month window)
- **FP cost**: 30bps × ~3 FP / 12m = ~9bps annual drag in this window
- **Risk**: LOW — best-case crisis

### Crisis 2: 1997 IMF (S1)
- **3 features only** (F14 + F31 + F32) — yield curve / VIX / credit ALL missing
- **Expected Recall (Strategy A)**: 0.30~0.50 — model has only volatility + sector rotation to detect
- **Expected Recall (Strategy B 2001+)**: N/A (held out)
- **FP cost**: Strategy A may have many FP in 1991~1996 (5-feature only, noisy)
- **Risk**: **HIGH** — primary mode of Strategy A failure. Codex C5 disposition rationale.

### Crisis 8: 2020 COVID (S4)
- **Full 32 features**
- **Expected Recall**: 0.50~0.80 — sudden onset (5 weeks Feb-Mar 2020) challenges monthly granularity
- **Expected Precision**: 0.50~0.70 — 2 bad months in 2020 + ~2 false alarms in recovery 2020-04~12
- **FP cost**: 30bps × ~3 FP / 36m = ~3bps annual drag
- **Risk**: MEDIUM — COVID speed 너무 빨라 monthly aggregate에서 miss 가능

### Crisis 9: 2022 Inflation (S4)
- **Yield curve inversion + credit spread strong**
- **Expected Recall**: 0.70~0.90 — backbone optimal match
- **Expected Precision**: 0.50~0.70
- **FP cost**: 30bps × ~3 FP / 24m = ~4bps annual drag
- **Risk**: LOW — backbone가 가장 잘 작동하는 modern crisis

### Crisis 7: 2018 vol (S3+S4)
- **Single month bear (2018-10)**
- **Expected Recall**: 0.30~0.60 — single-month detection 어려움 (preceding LEI not strongly degraded)
- **Expected Precision**: 0.20~0.40 — VIX spike + foreign flow → many FP signals in 2018-Q4
- **FP cost**: 30bps × ~5 FP / 12m = ~15bps annual drag
- **Risk**: HIGH — generalization weak crisis

### Crisis 5: 2011 EU + Crisis 6: 2015 CN
- **Backbone subset only** (NFCI + credit + 2-month bear)
- **Expected Recall**: 0.40~0.60
- **Expected Precision**: 0.30~0.50
- **Risk**: MEDIUM

### Crisis 10: 2026-03 recent (true OOS)
- **Full features but model trained without it**
- Unknown — pure OOS validation valuable

---

## 4. Threshold Sensitivity Analysis (τ=0.3 vs 0.5 vs 0.7)

Bear sensor p_bad ∈ [0,1] → decision rule `bear_state = (p_bad >= τ)`. Forge Stage 4 binding.

| τ | Expected Recall | Expected Precision | FP rate | Per-year FP count | Downstream β_bear use case |
|---|---|---|---|---|---|
| **0.3 lenient** | 0.75~0.90 | 0.30~0.50 | high | ~6/yr | aggressive defensive scaling, expensive |
| **0.5 medium** | 0.55~0.75 | 0.45~0.65 | medium | ~3/yr | balanced (default per alpha spec) |
| **0.7 conservative** | 0.30~0.55 | 0.65~0.85 | low | ~1/yr | only highest-conviction bear |

**Risk recommendation** (Forge cycle binding, NOT optimizer): 
- τ=0.5 default (alpha spec)
- Per-crisis Recall report at τ=0.3 / 0.5 / 0.7 (Forge Stage 4 mandatory output)
- FP year-by-year cost integration (TO impact estimate per τ)

**Position scaling impact** (Codex C7 disposition Path B β_bear schedule):
- p_bad < 0.3 → β=1.0 (full risk)
- 0.3 ≤ p_bad < 0.5 → β=0.7 (30% defensive)
- 0.5 ≤ p_bad < 0.7 → β=0.5 (50% defensive)
- p_bad ≥ 0.7 → β=0.3 (70% defensive)

**Risk concern**: β_bear schedule는 alpha pre-declared. Optimizer cycle 에서 grid search ban (alpha 영역 침범 방지). 본 risk audit는 schedule sensitivity analysis만 (학술 prior 정합 확인) — Kritzman-Page-Turkington 2011 FAJ AR overlay 정합.

---

## 5. Tail Event Concentration Diagnostic (Risk Specific Audit)

8 crisis ~ 81 bad months / 437m = 18.5% positive class rate.
**Bad months concentration**:

| Period | n_months | n_bad | concentration | bad_share / total |
|---|---|---|---|---|
| **Crisis 8-month windows** (8 × 8 = 64m) | 64 | ~30 | 47% | 37% of all bad |
| **Outside-crisis** (437 - 64 = 373m) | 373 | ~51 | 14% | 63% of all bad |

**Risk diagnosis**: 
- 47% of bad months concentrated in 8 explicit crisis windows (15% of total time)
- **나머지 63% bad months는 sporadic** — "false alarm vs missed individual bad month" trade-off
- Forge cycle bear sensor의 **utility는 crisis-detection vs random-month-bad-detection 분리 평가**

**Risk recommendation**:
- Recall measured separately: **Recall_crisis_period** (8 windows) vs **Recall_outside_crisis** (sporadic)
- 학술 backbone의 진정한 value는 **Crisis Recall**에 집중 (Estrella + Stock-Watson recession-detection 학술 framework)
- Outside-crisis bad month miss는 acceptable trade-off (FP 줄임)

---

## 6. Downstream β_bear Stress Translation

p_bad → β_bear → portfolio impact 정량 (alpha C7 disposition Path B 정합).

Assume STR_1715 PG2 base (sleeve return SR 1.95 / vol 21%):

| Regime case | p_bad | β_bear | Effective sleeve weight | Vol impact | Expected SR impact |
|---|---|---|---|---|---|
| Bull continuation | <0.3 | 1.0 | 70% (m4=1.0 × β_AR=0.7) | base 14.7% | base 1.37 |
| Caution | 0.3~0.5 | 0.7 | 49% | -30% vol = 10.3% | -0.5 if FP, +0.3 if TP |
| Bear onset | 0.5~0.7 | 0.5 | 35% | -50% vol = 7.4% | -1.0 if FP, +1.5 if TP |
| Bear severe | ≥0.7 | 0.3 | 21% | -70% vol = 4.4% | -1.5 if FP, +3.0 if TP |

**Expected value calculation** (per regime):
- Bull case (60% of months): SR contribution = 1.37 × 60% = 0.82
- Caution (15% of months): SR contribution_TP = (0.3 - 0.5) × 15% × 0.6 + ((-0.5) × 0.4) = noisy
- Bear (10% of months): SR contribution depends heavily on Precision

**Risk Net Verdict**: β_bear schedule **only adds positive expected value when Precision @ τ=0.5 ≥ 0.50** (break-even). Forge cycle G1 Precision ≥ 0.40 (alpha admission threshold) **는 break-even에 못 미침** → alpha spec G1 Precision ≥ 0.40을 risk advisory로 **flag** but no veto (alpha 영역).

**Risk Conditional Concern**: Alpha G1 Precision threshold ≥ 0.40 binding은 sensor admit 후 standalone deployment 시 단기 SR drag 가능. Codex round에서 alpha challenge_flags 명시 — risk re-flag.

---

## 7. Stress Set Pre-declaration (Forge cycle binding)

본 risk audit가 권고하는 Forge Stage 4 stress test set:

### Stress Set A: All-crisis Recall
- Each of 8 crisis epoch별 Recall + Precision report at τ ∈ {0.3, 0.5, 0.7}

### Stress Set B: Held-out crisis fold
- alpha crisis_sample_inclusion.md Section 3 Alternative ✅ accept
- Fold-1 IMF held / Fold-2 Dotcom / Fold-3 GFC / Fold-4 COVID / Fold-5 Inflation
- per-fold OOS Recall ≥ 0.50 expected

### Stress Set C: Lead-time decomposition
- Per backbone (8 backbones) signal correlation with forward 1M bear label
- Test: yield curve (F01~F05) 6m lead signal vs 1m forward bear — lead-time mismatch flag

### Stress Set D: False-positive run-length
- Consecutive bear signal streak distribution (max streak, mean streak when wrong)
- Goal: τ=0.5 false-positive streaks < 3 consecutive months (anti-flicker)

---

## 8. Summary

**Risk Sensor Audit Verdict** (regime_sensor scope, NOT alpha approval):
- ✅ Lead-time priors satisfactory for 1M monthly horizon (mid-short lead backbones dominant)
- ⚠️ S1 era (1990~2000) only 3 features → Strategy A admit 시 1997 IMF Recall HIGH RISK
- ⚠️ 2018 vol crisis weakest backbone coverage → generalization stress
- ✅ 2008 GFC + 2022 inflation backbone optimal match → easy cases
- ⚠️ Crisis-concentration 47% in 15% of time → Recall_crisis vs Recall_outside 분리 평가 권고
- ⚠️ Precision break-even @ τ=0.5 ≥ 0.50 — alpha G1 ≥ 0.40 below break-even (advisory flag, NOT veto)

**Forge cycle binding**: Stress Set A + B + D mandatory. Set C optional.

---

## References

- Estrella, A., & Hardouvelis, G. A. (1991). The term structure as a predictor of real economic activity. JF 46(2), 555-576.
- Stock, J. H., & Watson, M. W. (2003). Forecasting output and inflation. JEL 41(3), 788-829.
- Kritzman, M., Page, S., & Turkington, D. (2011). Regime Shifts: Implications for Dynamic Strategies. FAJ 67(3), 22-39. (AR overlay precedent)
- Gilchrist, S., & Zakrajsek, E. (2012). Credit spreads and business cycle fluctuations. AER 102(4), 1692-1720.
- Codex C7 disposition (alpha challenge_note_alpha-research.md) — Path B β_bear schedule pre-declared
