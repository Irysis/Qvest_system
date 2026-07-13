# Self-Adversarial Challenge — WT-D20260713_007 (R23, FQ-036)

Opus 4.8 native adversarial pass, run pre-finalize. Prereg SHA `4b880cfb48e83f6f59161cb2ce21bf61ee1ff7d4a9896ba439164408a3a6f12d` (frozen BEFORE any severity-target feature->event association was computed; event counts by type were known from R22 but no severity-union lift/OR existed before freeze).

## Concern 1 (task-mandated) — Is the signal still significant AFTER label hardening? (hardening is authoritative)
**Classification: REBUTTAL on the PIT question / ACCEPT on the deeper fragility.**
- Hardening executed: cross-matched RAWDATA AdminStock/UnfaithfulDisc flag onsets to the actual 관리종목지정 / 불성실공시법인지정 disclosure dates in the disc_ck archive (506,874 rows, 348 stocks). Result: **flag onset == public designation month in 89% of matchable cases, median gap 0, only 5.6% flag-leads (look-ahead risk)**. No systematic backdating -> the RAWDATA flag onset is a PIT-clean designation-date proxy. This directly answers R22 next_probe P3.
- BUT coverage is only 36/2492 matchable (disc_ck is survivor-biased to 348 current stocks; delisted micro-caps absent). Because matched hardening months equal flag months in ~89% of cases, the **hardened target is numerically identical to the pure-flag target** (base rate 0.01444, 793 events, 47 worst-decile hits both). So hardening confirms cleanliness but does not move the verdict.
- The honest deeper problem is NOT the labels but the *count of independent events*: the "significant" result rests on 6 firms (below), which hardening cannot fix.
- **Self-rationalization check**: I do NOT claim "coverage low but 결과 동일 so OK". The 89% same-month is a genuine directional-cleanliness finding on a *small* matched sample; I flag that full-target cleanliness is *inferred* from 36 events and log coverage expansion as next_probe P3.

## Concern 2 (task-mandated) — Delisting last-obs mechanicity: do late-filing firms just lose data coverage faster (data artifact, reverse causation)?
**Classification: PARTIAL (real risk, bounded, and partially defused).**
- The worry: Delisting is DERIVED from last-observation (C6). A firm that files its annual report late may also be a firm whose price series terminates early in rawdata for administrative reasons -> the "delay -> delisting" link could be a data-plumbing artifact, not economics.
- Defusing evidence: (a) The signal is NOT delisting-only. Worst-decile forward-hits split AdminStock 23 / UnfaithfulDisc 21 / Delisting 18 - **the two designation events (which are disclosure-dated, NOT last-obs-derived) carry more of the signal than delisting**. AdminStock/UnfaithfulDisc lift (4.24 / 3.82) is measured against actual designation disclosures, immune to the last-obs artifact. (b) The delay feature is measured at decision-month t from the 사업보고서 filing date vs the 90-day legal deadline - it is a *filing-timeliness* measurement, not a proxy for imminent data truncation.
- Residual risk retained: the delisting component (18 hits, lift 6.38) could still be partly mechanical. I did NOT fully isolate this (would require the actual 상장폐지 decision date vs last-trade date). Logged: the aux continuous-hazard on delisting-only is flat (OR 1.18, p=0.62), so even if mechanical, delisting is not what drives the (fragile) significance - the designation events do. Net: the artifact cannot manufacture the AdminStock/UnfaithfulDisc lift, so it is not the primary explanation.

## Concern 3 (task-mandated) — Era variation in event base rates
**Classification: ACCEPT (drives a headline caveat).**
- Base rate of severe events is not stationary: the delay feature's coverage is post-2016-heavy, and **all estimable signal is post-2016** (post-2016 OR 4.16 p=0.005; pre-2016 non-estimable, <5 worst-decile events). This sits entirely inside the R-cohort documented alpha-decay / regime window. Temporal robustness is UNESTABLISHED (not disproven - the pre-2016 delay panel simply has too few late-filer episodes to estimate).
- Combined with the era-varying severe-event base rate (managed/unfaithful designation regimes changed with KRX rule tightening ~2009+ and delisting-review reforms), the single-regime estimate cannot be extrapolated. This is why the prereg stability clause (pre AND post) was pre-registered - and it is structurally unmeetable here, so I do NOT upgrade the verdict on the strength of the post-2016-only fit.

## Concern 4 (self-generated, DECISIVE) — The "47 events" are ~6 company-episodes.
**Classification: ACCEPT - this is the binding reason the prediction is not robustly established.**
- Worst-decile 47 hits are carried by **6 distinct tickers** (12/11/11/7/5/1). The 12-month hold means one late annual-report filing keeps a firm in the worst decile (and pointing at the same forward event) for up to 12 months -> the 47 monthly "events" collapse to ~6 independent company-episodes.
- Pre-registered test (d) ticker-bootstrap lift CI **[0.95, 7.25] includes 1**. Leave-one-ticker-out: removing ANY of {A001570, A016790, A290510} pushes controlled OR p>=0.05. Cluster-robust logistic SE (which gives the nominal p=0.011) needs many clusters; **6 event-clusters make that p anti-conservative and untrustworthy**.
- Therefore, although the pre-registered PRIMARY *literally* passes (OR 3.43, cluster-robust p=0.011), its inferential validity is void. I classify the round as **config-scoped negative (not robustly established) + frontier open**, NOT "prediction holds". I explicitly flag that this is a validity disclosure of the primary statistic, not a post-hoc goalpost move (the bootstrap and LOO were the pre-registered / standing robustness checks).

## Concern 5 (self-generated) — Am I moving the goalpost to REJECT after a nominal pass?
**Classification: REBUTTAL (guarded).**
- The symmetric danger to R22's "don't post-hoc to accept" is R23 "don't post-hoc to reject". Guard: the primary literal outcome (PASS, p=0.011) is reported verbatim and prominently in verdict.json (`prereg_primary_literal.literal_outcome = PASS`). I am not hiding it. The downgrade to non-actionable rests only on (a) the pre-registered ticker-bootstrap CI (test d) and (b) a validity precondition of the primary statistic itself (cluster count), both legitimate. If a future full-universe replication (P1) delivers dozens of independent episodes with p<0.05 AND a bootstrap CI excluding 1, that WOULD be a robust positive. The mechanism is directionally confirmed; only the power/independence is missing.

## Concern 6 (self-generated) — Placebo optimism.
**Classification: PARTIAL.**
- The month-permuted placebo (obs OR 3.43 vs null q99 1.365, p=0) looks decisive but is anti-conservative here: permuting `pred` within month breaks the ticker-persistence that makes the 47 hits autocorrelated. It confirms the association is not a within-month cross-sectional artifact, but it does not test the few-cluster problem. I therefore do NOT cite the placebo as evidence for robustness - only as a ruling-out of one specific artifact.

## Self-rationalization auto-scan
Grepped my own reasoning for "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일". Two flagged uses, both legitimate directional-bound arguments, not hand-waves: (1) survivorship "conservative" (fewer delisting events -> harder detection); (2) hardened==pure-flag "결과 동일" - used to say hardening does NOT rescue the verdict (i.e., against my own positive result), not to excuse a gap. No banned rationalization used to UPGRADE the verdict.

## Escalation check
HIGH-severity concerns: {C4 fragility}. Count of HIGH < 5; no AX axiom hard-FAIL; no PIT C1 lockbox/lookahead violation (C1 hardening AFFIRMS PIT-cleanliness, median gap 0). -> No Q-Lead auto-escalate. Verdict stays in alpha lane: config-scoped negative + frontier open.

## Net effect on verdict
The severity-restriction hypothesis (R22 P1) is **directionally CONFIRMED**: dropping transient LongHalt lifted the union from 2.07 to 3.74 exactly as the D1 decomposition predicted, and controls barely attenuate (not size-disguise). Label hardening (P3) **confirms PIT-cleanliness** (89% same-month, no backdating). BUT the binding wall moved from *dilution* to *too few independent late-filer episodes*: 47 monthly hits = ~6 firms, bootstrap CI includes 1, LOO 3/6 decisive, cluster-robust p invalid at 6 clusters. => **config-scoped negative + frontier open**; no Stage-2 filter round; next_probe P1 (full DART filer universe) is the direct, addressable path to the missing power.
