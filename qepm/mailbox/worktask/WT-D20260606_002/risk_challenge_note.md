# Risk Challenge Note — WT-D20260606_002 (DPL cycle 2)

**Codex Risk Critic stance: APPROVE_CONDITIONAL** (GPT-5.5, AX-008 PASS, agree_with_claude=true)
4 concerns: R1 HIGH, R2 MEDIUM, R3 MEDIUM, R4 LOW. No escalation trigger (HIGH<5, no Σ PD violation [PSD=true], no PIT hard violation).

Codex is devil's advocate (no veto). Each concern classified ACCEPT / PARTIAL / REBUTTAL with 3-axis basis (academic + L-code/code + quantitative).

---

## R1 [HIGH] — Residual orthogonality "over-framed as closing the alpha-Codex gap" (missing sector neutralization + raw-base comparator)

**Disposition: PARTIAL (rebuttal on comparator basis, ACCEPT on sector limitation).**

- **REBUTTAL on the raw-base comparator concern (the quantitative core of R1):** Codex worried that residual corr was measured vs *raw* base90, not *residualized* base90, which "can misstate incremental orthogonality." I ran the fair same-basis test: residualize BOTH the new feature AND every base90 feature on identical style axes [Size, 5 value, log-liquidity] per month, then take residual max|corr|. Result (`_resid_base_check.json`):
  - PIOTROSKI 0.242, MOHANRAM 0.257, NETISSUE 0.302 — essentially unchanged from raw-base (0.21/0.20/0.26), still low.
  - RESIDMOM 0.865 — *higher* than raw (0.78), confirming redundancy even more strongly.
  - **The same-basis comparison STRENGTHENS the conclusion**: the 3 new features are independent of style-residualized base, RESIDMOM is collinear. The orthogonality verdict survives the fairer test. (Academic: Fama-MacBeth cross-sectional residualization standard; quantitative: 3-era + same-basis triangulation.)
- **ACCEPT on sector neutralization:** The DPL panel has NO sector column (only ym/Ticker/Ret_1m/adv/in_univ/date + 98 features). Security-level sector neutralization is genuinely impossible from the sanctioned panel input. I downgrade language from "genuinely/strongly orthogonal" to "orthogonal to available style axes (size/value/liquidity); sector neutralization is an unresolved limitation — sector co-movement could inflate true panel correlation." A base90-feature kmeans cluster proxy was attempted but is not a security-level sector control. This is now an explicit limitation in the final package, not a closed claim. (Honest reporting per AX-000.)

## R2 [MEDIUM] — Sigma cond# 480 may create false precision (95% shrink + ridge ≈ constant-corr prior)

**Disposition: ACCEPT (already self-flagged; reinforce).** Draft already states delta=0.95 + ridge → "interpret as risk-budget tool, not fine covariance." Codex is right that cond#<500 must not be read as a quality *certificate* — it was reached by extreme structure imposition on a singular (N≈T) sample. Final package adds explicit `cond_number_is_not_a_quality_certificate: true` and reiterates DPL does not consume Σ as a hard input. Academic: Ledoit-Wolf 2004 (shrinkage trades bias for conditioning — by design loses cross-name detail). No rebuttal needed; this is the honest reading.

## R3 [MEDIUM] — Crowding flags (0.749/0.785) are admitted artifacts → risk misleading downstream gates

**Disposition: ACCEPT.** Codex correctly notes that simultaneously flagging LEVEL_HIGH and calling it an artifact invites cherry-picking. Fix applied: passive_overlap_proxy is a CONSTANT 1.0 (all candidates in_univ) → absolute scores are invalid for any threshold gate. Final package marks crowding `valid_for_threshold: false` and `usable_signal: rank_only`. The risk_crowding_score_check hook field is preserved (compliance) but flags are demoted to `RANK_ONLY_ADVISORY`. The genuinely tradable-crowding signal is the RANK: momentum M05 (vol_concentration 0.220, highest) > new features. (Acadian 2026 crowding is rank/relative by construction; absolute calibration needs RAWDATA inst-flow which the panel lacks.)

## R4 [LOW] — Tail ES on EW basket ≠ DPL portfolio tail

**Disposition: ACCEPT.** Correct. EW candidate-basket ES95 -13.3% is a candidate-POOL regime warning, NOT a bound on optimized DPL weights (which can reduce OR amplify tail). Final package: tail recommendation reworded to "require DPL-WEIGHTED portfolio ES/CVaR reporting at optimizer/forge stage before tail metrics enter any graduation decision." Not a bound claim. Already labelled metric_type=proxy.

---

## Rationalization self-check (Codex flagged 4 red-flag phrases)
- "genuinely/strongly orthogonal" → softened to "orthogonal to available style axes" (R1 accept). ✓
- "cond#<500 as certificate" → explicitly negated (R2 accept). ✓
- "crowding LEVEL_HIGH" → demoted to RANK_ONLY_ADVISORY, valid_for_threshold=false (R3 accept). ✓
- "candidate tail as DPL bound" → reworded to require DPL-weighted ES (R4 accept). ✓
No "미미/관행적/보수적이면 OK/대부분 동일/실무적" rationalizations used.

## Ceiling view — Codex AGREES (ceiling_view_agreement)
Both Codex and risk concur: orthogonality is NECESSARY but NOT SUFFICIENT for SR 2.5; the 3 new features add real independent information (refuting "no new info"), but weak long-side transfer + fat tail (ES95 -13%) + KR crisis correlation spike + avg-pairwise-corr 0.156 common-mode floor bound the extractable Sharpe. 1.74 breakout remains UNPROVEN. Definitive judgment = optimizer full DPL sweep (forge-authoritative), outside risk scope. Independent triangulation: alpha + alpha-Codex + risk + risk-Codex all converge on cautious-ceiling.

## Net change: draft → final
1. Same-basis residual evidence added (rebuttal of R1 comparator concern). 2. Sector limitation made explicit (R1 accept). 3. Orthogonality language softened (R1). 4. cond# certificate negation (R2). 5. Crowding flags → valid_for_threshold=false, rank-only advisory (R3). 6. Tail → DPL-weighted ES required (R4). No alpha edit, no weights, scope preserved (Codex scope_audit PASS).
