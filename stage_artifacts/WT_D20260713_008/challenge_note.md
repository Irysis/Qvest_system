# Self-Adversarial Challenge — WT-D20260713_008 (R24, FQ-037)

Opus 4.8 native adversarial pass, run pre-finalize (v8.2 — replaces external Codex Round). Prereg SHA `e13d4251f0be30023307d82e91c8e2f0c2752b7f23aeaec2359a2496568d4291`, frozen AFTER the coverage census (a coverage fact, not a treatment-outcome association) and BEFORE any late-filing x severe-event OR/lift was computed.

## Concern 1 (task-mandated) — Does the full-filer expansion just re-discover 'small-cap', not 'late filing'? (answer via Size control + tier decomposition)
**Classification: PARTIAL (real and material; but not a pure size-rediscovery).**
- Direct test: per-fy log_size tercile decomposition of the extreme-tail (wd_strict) episodes. ALL 6 extreme-tail severe events are small-cap; mid+large extreme-late filers (15 episodes) had ZERO severe events. So the signal is unambiguously **small-cap-confined**.
- BUT it is NOT merely 'being small': within the small tier, extreme-late filers have lift **12.2x over the small-cap base rate (0.0351)**, and the controlled OR (6.19) already includes a linear size_z control + year-FE and survives. Being small is necessary but not sufficient — being small AND extreme-late is the joint condition.
- **Honest downgrade this forces**: the mechanism lives entirely in small-caps OUTSIDE the K200uKQ150 deployment universe. This reconciles R23's deployment-universe starvation as STRUCTURAL (large/mid caps that file late do not fail here), not merely low-power. Deployment prospects stay dim even if the extreme tail is later confirmed. Logged in verdict.size_tier_decomposition_DECISIVE.
- **Self-rationalization scan**: I do NOT wave this away as 'small effect' — I promote it to a verdict-shaping structural finding that caps deployment relevance.

## Concern 2 (task-mandated) — Could the episode definition be re-cut favorably knowing the outcome?
**Classification: REBUTTAL on the freeze / ACCEPT the operationalization miss (disclosed against my own result).**
- Freeze integrity: preregistration.json (sha256 above) fixed the treatment (per-fy p90 & delay>0), the episode unit, the outcome, the controls (incl. year-FE), the validity gate, and the verdict rule BEFORE computing any OR/lift. The census measured only coverage/counts (firms, fy spread), never the treatment-outcome link.
- The honest catch: the frozen p90 rule COLLAPSED to 'any late filer' (1105 episodes) because <10% file late in most fiscal years => per-fy p90<=0. This is a pre-registration operationalization MISS (p90 is a looser 'worst decile' than rank-top-decile in a mostly-on-time distribution). I disclose this as a validity note on the FROZEN statistic (analogous to R23 disclosing its nominal PASS rested on invalid few-cluster asymptotics), and the FROZEN primary — not the better-performing diagnostic — governs the verdict = NOT ESTABLISHED. I did not re-cut to rescue significance.

## Concern 3 (task-mandated) — Look-ahead residual in labels beyond the disc_ck 348-stock hardened coverage
**Classification: PARTIAL (bounded, conservative direction).**
- Hardening coverage is 36/2492 matchable (disc_ck survivor-biased to 348 current stocks). R23 established that on the matched subset, flag onset == public 관리종목/불성실 designation month in 89% of cases (median gap 0, only 5.6% flag-leads). Hardened target is numerically identical to pure-flag here => the RAWDATA flag onset is a PIT-clean designation-date proxy on the verifiable subset.
- Residual risk: full-target cleanliness is INFERRED from 36 events; the event-carrying delisted micro-caps are absent from disc_ck and cannot be verified directly. Direction of any residual backdating (flag leading designation) = would INFLATE predictability => the null-actionable frozen verdict is conservative w.r.t. this risk. Coverage expansion to the delisted tail is next_probe P2/P3.
- Delisting last-obs artifact (a distinct PIT-adjacent risk): frozen-primary composition is AdminStock 16 / UnfaithfulDisc 7 / Delisting 2 — the disclosure-dated designation events (immune to last-obs mechanicity) dominate. Artifact cannot manufacture the association.

## Concern 4 (self-generated, DECISIVE for framing) — Am I over-selling the extreme-tail diagnostic (goalpost-move to a positive)?
**Classification: REBUTTAL (guarded) — the symmetric danger to R23.**
- R22 refused to post-hoc RESTRICT its target to reach significance. The strict-tail here is MORE restrictive than my frozen primary; declaring the round 'established' on it would be the identical sin. Guard: verdict.verdict = CONFIG_SCOPED_NEGATIVE, driven ONLY by the frozen primary (lift boot CI [0.86,1.62] includes 1; year-FE p=0.051). The extreme-tail block is explicitly labeled `_DIAGNOSTIC_nonauthoritative` and `goalpost_discipline_statement` is recorded verbatim in verdict.json.
- What the diagnostic legitimately buys: it RESOLVES R23's power/inference wall (6 fragile firms -> 27 LOO-robust firms, boot CI now excludes 1) and it routes to a clean pre-registered extreme-tail round (next_probe P1). That is a genuine knowledge advance, reported without upgrading this round's verdict.

## Concern 5 (self-generated) — 6 events is thin; is the extreme-tail OR / boot-CI trustworthy?
**Classification: ACCEPT (bounds the claim).**
- The extreme-tail rests on 6 severe events across 6 firms (27 total extreme-tail firms). LOO shows no single firm is decisive (drop any -> min OR 5.38, max p 0.004) — a real improvement over R23 (3/6 decisive) — and the firm bootstrap (1000 reps) CI [3.5,17.3] excludes 1. But 6 events is still modest for a logistic with year-FE (separation risk on the FE terms). I therefore label the extreme tail 'robustly suggestive, event-count-modest', NOT 'established', and make raising the event count (coverage expansion, next_probe P2) an explicit precondition for a confirmatory positive.

## Concern 6 (self-generated) — Did year-FE get added post-census to help the primary?
**Classification: REBUTTAL.**
- year-FE was pre-registered in the PRIMARY spec (disclosed as an a-priori guard against the era base-rate non-stationarity R23 already documented as Concern 3). Empirically it made the frozen primary MORE favorable (OR 1.33 no-FE -> 2.34 with FE) yet it STILL failed (p=0.051, boot CI includes 1). So year-FE did not rescue the result and was not result-tuning; the no-FE spec is reported alongside for transparency.

## Self-rationalization auto-scan
Grepped my reasoning for '미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일'. Flagged uses, all legitimate directional-bound arguments, none used to UPGRADE the verdict: (1) survivorship + residual-backdating 'conservative' (both push AGAINST a positive); (2) hardened==pure-flag 'identical' (used to say hardening does not change the null, not to excuse a gap). No banned rationalization used to move the verdict toward success.

## Escalation check
HIGH-severity concerns: {C1 small-cap-confinement caps deployment; C4 goalpost risk (mitigated)}. Count HIGH < 5; no AX axiom hard-FAIL; no PIT C1 lockbox/lookahead violation (hardening AFFIRMS PIT-cleanliness; census used only local archives, DART API=0). => No Q-Lead auto-escalate. Verdict stays in alpha lane: config-scoped negative + frontier open.

## Net effect on verdict
The FROZEN pre-registered primary does NOT establish the prediction (config-scoped negative) — its p90 operationalization diluted to 'any late filer'. R23's binding power wall IS resolved at the design level: episode-level + universe expansion delivered 27 independent, LOO-robust extreme-tail firms (vs 6 fragile in R23) with a firm-bootstrap CI excluding 1 and controlled OR ~6 (p<0.001). But the signal is entirely small-cap-confined (all 6 events small-cap; 0 in mid/large), making the deployment-universe starvation STRUCTURAL and capping capital relevance. Knowledge gained: 'extreme-late annual filing predicts severe events, but only among small-caps outside the deployment universe.' next_probe: pre-register the extreme-tail definition (P1) + expand coverage to the delisted micro-cap tail for more events (P2) + isolate the disclosure-dated designation channel (P3).
