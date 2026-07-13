# Self-Adversarial Challenge — WT-D20260713_006 (R22, FQ-035)

Opus 4.8 native adversarial pass, run pre-finalize. Prereg SHA `3455656218d17d2af7333a40d0ba1abda74c242fa891013f0100a9eae49e0659` (frozen before any feature→event association was inspected).

## Concern 1 (task-mandated) — Is the lift a Size disguise? Controlled residual is authoritative.
**Classification: REBUTTAL (empirically resolved).**
- F3 delay: raw OR 2.18 → controlled OR 2.06 (add log(Size)+liq_z+K200+KQ150, ticker-cluster-robust). The Size/tier/liq controls barely attenuate the delay→event odds → the delay signal is **NOT** a small-cap base-rate artifact. This is the strongest possible answer to the concern: the confound was tested and the signal survives it in point estimate.
- F1 Benford / F2 m1 / stack: there is no lift to disguise (controlled OR ≈ 1, p>0.6). Concern moot for these.
- Caveat retained: F3 fails the *significance* bar (p=0.075) on power, not on the size control. Size-disguise is ruled out; power is the binding issue.

## Concern 2 (task-mandated) — Event-label PIT: designation date vs cause-occurrence date.
**Classification: PARTIAL (limitation surfaced, direction bounded).**
- Flag onset = the date the designation/halt appears in rawdata (treated as the public designation date, forward-looking → PIT-clean). Risk: if rawdata **backdates** the AdminStock/UnfaithfulDisc flag to the underlying cause date (which precedes public designation), a mild look-ahead would make the feature→event link *easier* to detect.
- Direction: such backdating would **inflate** predictability. Since F1/F2/stack are flat nulls and F3 is only sub-threshold, any inflation makes the null verdict *more* robust and the F3 sub-threshold slightly optimistic — it does not manufacture the negative verdict.
- Cannot fully verify without raw designation-announcement timestamps → logged as next_probe P3 (mandatory before any capital use of delay).

## Concern 3 (task-mandated) — Survivorship of the flag/event data itself.
**Classification: PARTIAL (bounded, conservative direction).**
- Delisting is DERIVED from last-observation; rawdata is the K200/KQ150 support universe and may under-retain fully-delisted micro-caps. Direction: fewer delisting events observed → **harder** to detect prediction → conservative for a positive verdict. 1105 delisting events are present (non-trivial), so coverage is partial not absent.
- For the NULL features (F1/F2) this means the null could be mildly under-powered on the most extreme names; for F3 it means the true delisting lift (already 6.4x in-sample) is if anything understated.

## Concern 4 (self-generated) — Composite-target dilution.
**Classification: ACCEPT (drives the primary next_probe).**
- The union target mixes severity classes. D1 decomposition: F3 delay worst-decile lift = Delisting **6.4x**, AdminStock **4.2x**, UnfaithfulDisc **3.8x**, but transient LongHalt only **1.8x** — and LongHalt is the largest-base component, so it *dominates and dilutes* the union lift down to 2.07.
- This is a real construct-measurement flaw in the frozen prereg: a coherent late-filing→severe-outcome signal is masked by lumping in transient halts. I did **not** re-run with a severity-restricted target this round (that would be post-hoc goalpost-moving on a frozen prereg). It becomes pre-registered next_probe P1.

## Concern 5 (self-generated) — Worst-decile power throttle / non-monotonicity.
**Classification: ACCEPT.**
- Worst decile of delay = 871 obs / 57 events, clustered in few tickers → ticker-bootstrap lift CI [0.71, 3.65] includes 1 even though Wilson [1.61, 2.65] excludes it. Clustering, not the point estimate, kills significance.
- D2: continuous days-late OR 1.07/sd (p=0.40); top-quintile OR 1.36 (p=0.34). The signal is **tail-concentrated, not monotonic** — widening the threshold DILUTES it. So the naive "widen for power" fix is wrong; power must come from severity-restricted target / longer window / larger filer universe (next_probe P1/P2). Recorded to prevent a mis-specified follow-up.

## Concern 6 (self-generated) — Delay is a post-2016-only feature.
**Classification: PARTIAL.**
- F3 delay pre-2016 worst-decile events <10 → pre-2016 controlled OR not estimable → prereg stability clause (pre AND post both >1) structurally unmeetable. Its post-2016 significance (OR 2.58, p=0.022) therefore sits entirely inside the post-2016 regime where the R-cohort documents alpha decay. Temporal robustness is unestablished, not disproven.

## Self-rationalization auto-scan
Grepped my own reasoning for "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일". One legitimate use: survivorship bias direction is called "conservative" — this is a *directional bound argument* (fewer events → harder detection), not a hand-wave to excuse a gap. No banned rationalization used to upgrade the verdict.

## Escalation check
HIGH-severity count < 5; no AX axiom hard-FAIL; no PIT C1 lockbox/lookahead violation (the C5 concern is a bounded caveat, direction conservative). → No Q-Lead auto-escalate. Verdict = config-scoped negative, stays within alpha lane.

## Net effect on verdict
Concerns 1-3 do not overturn the negative. Concerns 4-6 explain *why* the frozen config under-detects a genuinely coherent delay signal and convert a flat "terminate the stack" into a differentiated disposition: F1/F2/stack terminate as event predictors; F3 delay = config-scoped negative with a specific, pre-registerable frontier (severity-restricted target, tail-preserving, coverage-based power). Prereg bar respected; no post-hoc.
