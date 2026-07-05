# Self-Adversarial Challenge — WT-D20260705_009 Alpha Research (v8.2)

**Agent**: alpha-research (Opus 4.8 native adversarial). No external Codex round (v8.2).
**Package under challenge**: `alpha_package_draft.json` → finalize `alpha_package.json`
**Finding under challenge**: Uncertainty-conditioned selection (α̂/σ̂) does NOT improve IC→PORT_t transfer; the wall is real top-region decay, not selection-into-noise. Honest NEGATIVE.

Charter §8 No Silent Override: every concern classified ACCEPT / PARTIAL / REBUTTAL with 3-axis evidence (academic + L-code/measurement-rule + quantitative).

---

## Concern 1 [HIGH] — "NGBoost crippled the known-good base; the null is an ML-attenuation artifact, not a real wall"
The selection score is NGBoost `mu_hat` (in-univ rank-IC t=3.38), which is **half** the raw EW composite's rank-IC (t=6.30). If the strong base was throttled by NGBoost regularization, the A/B under-tests the true known-good signal and the transfer-wall conclusion is invalid.

**Classification: REBUTTAL (with direct empirical test)**
- **Quantitative (3-axis #1)**: I re-ran the entire A/B with the **raw EW composite** (rank-IC t=6.30 — the strongest base) directly as Arm A (`adv_rawbase.R`). Result: ArmA_full PORT_t = **−0.866**, ArmA_post2017 PORT_t = **−1.833** — the raw known-good composite hits the SAME (worse) wall. Transfer failure is robust to base choice; NGBoost `mu_hat` actually realized *slightly better* long-only PORT_t (+0.20/−1.38) than the raw composite despite lower IC — a clean IC≠PORT_t illustration, not attenuation harming the verdict.
- **Measurement-rule (#2)**: measurement-graduation §2 — "rank-IC t and portfolio-alpha t are distinct; long-only top-N realized alpha is authoritative". The base having t=6.3 rank-IC is exactly the setup where §2 warns PORT_t can still be null/negative. Confirmed empirically both bases.
- **Academic (#3)**: Harvey-Liu-Zhu 2016 — cross-sectional IC significance does not survive as tradable long-only alpha after implementation. Both bases consistent.
- **Verdict**: The wall is NOT an NGBoost artifact. Rebuttal holds on real data (not rationalization).

## Concern 2 [HIGH] — "The design forces NGBoost because only it produces σ̂; the null may reflect a weak-base confound different from the mandate's intent"
Arm B needs a per-stock σ̂. The raw composite has none natively; NGBoost was necessary. Is the null due to uncertainty being useless, or to the base+σ̂ pairing being mis-specified?

**Classification: REBUTTAL**
- **Quantitative (#1)**: In the raw-base robustness test I formed Arm B = `raw_base / sigma_hat` (borrowing NGBoost σ̂ onto the raw known-good composite). Arm B still did NOT beat Arm A (full −1.55 vs −0.87; post-2017 −1.72 vs −1.83, marginal). Two independent bases (NGBoost mu_hat AND raw composite), same σ̂, same null. The uncertainty lever fails regardless of which base it protects.
- **Measurement-rule (#2)**: The mechanism check confirms σ̂ conditioning *worked* — Arm B mean σ̂ 0.109 vs Arm A 0.127 vs universe 0.118 (`diag3`). It genuinely down-weighted high-uncertainty names; the effect is real, its return impact is null.
- **Academic (#3)**: Liao-Ma-Neuhierl-Schilling 2025 RFS motivates uncertainty-aware selection but does not guarantee it in every market/universe; KR long-only top-25 is outside its demonstrated regime.
- **Verdict**: Not a weak-base confound — the σ̂ lever is genuinely inert here across two bases.

## Concern 3 [MEDIUM] — "Post-2017 Arm B is right-signed (dSR +0.029); the study is under-powered to detect a small real bite"
Post-2017 Arm B beats Arm A (dSR +0.029, mean-diff +1.3%/yr) in the *hypothesized* direction. With 114 months and small effect, a Type-II error is possible — I may be dismissing a real (if small) bite.

**Classification: PARTIAL (accept the caveat; reject that it changes the verdict)**
- **Quantitative (#1)**: The paired NW-t(lag3) on the monthly active-diff = **+0.45** (p≈0.65). Even taking the point estimate at face value, +1.3%/yr on a base that is itself PORT_t −1.2 to −1.4 cannot rescue a capital-grade strategy (post-2017 Arm B PORT_t still −1.155, far below the 2.95 HARD gate). Full-period the sign flips negative (dSR −0.048, t=−0.42) — no stable directional effect.
- **Measurement-rule (#2)**: measurement-graduation §3 — sub-t=2 differences are advisory noise, not admissible improvement; and oos_retention/PORT_t gates bind on the *level*, which fails regardless of the tiny B-vs-A tilt.
- **Academic (#3)**: Newey-West 1987 — the lag-3 HAC SE already accounts for the monthly autocorrelation; t=0.45 is genuinely indistinguishable from zero.
- **Verdict**: I RECORD the under-power caveat honestly (added to package), but it does not change "no bite / real decay". Requiring a t≥2 bite that also lifts the level is the correct bar; neither is met.

## Concern 4 [MEDIUM] — "σ̂ is just an illiquidity/size proxy; Arm B is a liquidity tilt in disguise, not a forecast-confidence tilt"
If NGBoost σ̂ mainly tracks illiquidity/microcap (§6 microcap structure), then Arm B ≈ a liquid-name tilt and the test does not isolate "forecast uncertainty".

**Classification: REBUTTAL**
- **Quantitative (#1)**: cor(σ̂, log ADV) = **+0.082** (near zero, `adv_rawbase.R`). σ̂ does NOT proxy liquidity — Arm B is a genuine forecast-confidence tilt, not a liq/size tilt. (cor(σ̂, base_score) = −0.497 — higher-scored names have modestly lower forecast uncertainty, which is the mild source of the 55% A/B holdings overlap.)
- **Measurement-rule (#2)**: The A/B already applies the same 5e7 liquidity floor to BOTH arms, so any residual liquidity difference is neutralized by construction.
- **Academic (#3)**: NGBoost predictive scale is a function of local feature-space model disagreement (Duan et al. 2020), not a single input — consistent with the near-zero liquidity correlation.
- **Verdict**: The mechanism is a true uncertainty tilt; the null is about uncertainty, not liquidity.

## Concern 5 [MEDIUM] — "Measurement integrity: is the corrected pipeline actually clean, given the 87.7% zeroing bug that was initially present?"
The first-pass A/B silently zeroed 87.7% of selected returns (forecast universe 3345 ⊄ returns universe 1024). If a residual leak remains, all numbers are suspect.

**Classification: ACCEPT (bug was real) → fixed and verified**
- **Quantitative (#1)**: Root-caused (`reconcile2.R`): NGBoost forecast all 3345 factor-DB tickers, but the mandate universe (returns_monthly, in_univ) = K200∪KQ150 only. Fix = inner-join forecast scores to the in-universe (Date,Ticker) panel BEFORE selection (`measure_ab.R` universe-restriction block). Post-fix: 777 in-univ tickers, 68,227 rows, 0% return-zeroing (selected names all have returns). Corrected PORT_t (+0.20/−1.38) reconciles with independent diag2 gross (+3%/yr active t=0.66).
- **Measurement-rule (#2)**: measurement-graduation §1 — real-computation via `canonical_screen_bt` (contract build_benchmark_compare), no proxy hand-calc. All numbers metric_type=canonical_screen (NOT forge-authoritative — screening/mechanism-location grade, correctly labeled, not claimed as capital-binding).
- **Academic (#3)**: n/a (pure data-integrity).
- **Verdict**: ACCEPT — genuine bug, transparently caught in reconciliation, fixed, re-measured, cross-validated. This is why the honest verdict rests on the corrected universe. Recorded in alpha_validation.json + package.

---

## Self-rationalization auto-detection (measurement-graduation / pit.md forbidden-phrase scan)
Scanned my own reasoning for: "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 영향 미미". 
- **None used as a gate-passing crutch.** The one place I say Arm B and Arm A are "roughly flat" (Concern 3) is backed by an explicit NW-t=0.45 (quantitative), not asserted. The negative verdict is *strengthened* by adversarial tests (raw-base robustness, σ̂-vs-liq), not excused by hand-waving. No RE-VIEW trigger fired.

## Q-Lead escalation trigger check
- HIGH severity concerns ≥5? No (2 HIGH, both REBUTTED with data). 
- AX axiom hard FAIL ≥3? No.
- PIT C1 (lockbox/lookahead) violation? No — expanding-window strict (month≤t−2 train), asof-safe, C15 connector, no lockbox access.
- **No auto-escalation.** This is a clean, well-diagnosed honest negative (AX-000 valuable knowledge).

## Net effect on package
- No spec change to the alpha (it is a negative result; the "alpha" delivered is the forecast-IR score for completeness + full diagnostic record).
- ADD to package: Concern-3 under-power caveat + Concern-1/2 raw-base robustness result + Concern-4 σ̂-liq decoupling + Concern-5 bug-and-fix provenance → challenge_flags populated.
- Verdict unchanged and reinforced: **mechanism has no bite; wall = real top-region decay + short-side-carried IC; uncertainty-conditioning is not a KR long-only transfer-wall lever.**
