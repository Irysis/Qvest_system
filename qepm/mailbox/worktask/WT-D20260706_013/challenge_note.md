# Self-Adversarial Challenge — WT-D20260706_013 (Intangible-adjusted value)

Agent: alpha-research (Opus 4.8 native adversarial reasoning, v8.2 — no external Codex).
Verdict emitted: **CLEAN_NEGATIVE** (wall-escape thesis falsified). This note records the
devil's-advocate concerns raised against my own CLEAN_NEGATIVE and their resolution.
No self-rationalization terms ("미미/관행적/실무적/보수적이면 OK") used as evidence.

All numbers are canonical_screen_bt (metric_type=canonical_screen, NW lag-3, 15bps, top-25,
liq 2e8, cap-w float universe benchmark). 2005-01..2026-07, K200∪KQ150.

---

## Concern 1 — "Intangible capitalization δ/θ is overfit; a different δ would flip the negative."
**Classification: REBUTTAL (with evidence).**
- Params are Peters-Taylor (2017) canonical defaults, NOT fit to KR returns: δ_RD=0.15, δ_SGA=0.20,
  θ_SGA=0.30, steady-state g=0.10. No return-based tuning at any step.
- The live overfit risk was the *opposite* (under-adjusting → hiding a real mega-cap effect). I ran a
  full adjustment-strength sweep (sensitivity.R). Result is monotone in the WRONG direction for the
  thesis: as I push the portfolio toward intangibles/mega-caps, POST2017 cap-w PORT_t gets WORSE:
    tilt λ=0.5 → −0.951 ;  λ=1.0 → −1.019 ;  λ=2.0 → −1.158 ;  pure intangible-intensity → −1.415.
  (mega-cap share rises 15.5%→52.3% size-pctile in lockstep with the deterioration.)
- Conclusion: the negative is NOT a weak-adjustment artifact. Stronger intangible adjustment produces
  MORE negative post-2017 alpha. Rebuttal grounded in: Peters-Taylor 2017 (literature), sensitivity
  sweep (quant, 4 strengths × 2 benchmarks), and consistency with de-rated AX-003.

## Concern 2 — "Large-cap reclassification is just growth/quality relabeled, not value."
**Classification: ACCEPT (framing correct; strengthens the negative).**
- Ortho check: mean monthly Spearman iBM_orgc~ROE = −0.239 (identical to stdBM~ROE = −0.243) → the
  intangible-adjusted signal is NOT quality-in-disguise; it is mildly anti-quality like real value.
- iBM_orgc~stdBM = 0.983 → it IS standard value (reclassification is minimal, see Concern-adjacent
  reclass diag: cross-rank Spearman 0.987, LARGE-cap mean rank-shift −0.001). So the object under test
  is genuine value, and genuine value dies post-2017. Accepting this framing makes the CLEAN_NEGATIVE
  cleaner: not confounded by quality.

## Concern 3 — "Excluding no-intangible sectors (financials/utilities) = survivorship / cherry-pick."
**Classification: ACCEPT as construction disclosure (no survivorship present).**
- No sector was excluded. Firms without R&D/SG&A get KC=OC=0 by construction → iBM collapses to stdBM
  (no spurious reclassification). Universe = full K200∪KQ150, liq 2e8 only.
- Genuine DATA CAVEAT (disclosed, not hidden): the DART/XLSX `RandD` line item collapses post-2016
  (has_rd frac = 0.17 post-2017), so post-2017 V-full ≈ V-orgc (knowledge-capital term ~0). The
  post-2017 test therefore leans on SG&A-based organizational capital + on-balance IntangibleAssets.
  This is a real coverage limit of KR IFRS separate-line R&D reporting, not a selection choice. It does
  NOT rescue the thesis: even the pre-2016 window where R&D is dense (R&D-firms-only iBM_full PRE2016
  PORT_t=3.08) is a SMALL-cap premium (top-25 med size-pctile 9.5%, frac size-top40 0.001), and it dies
  post-2017 (−0.714) like everything else.

## Concern 4 — "EW-survival = the escape exists, you just measured on the wrong benchmark."
**Classification: ACCEPT — but the EW-survival IS the wall, not an escape.**
- iBM_orgc POST2017: EW PORT_t = 0.656 (weakly +) vs cap-w = −0.768. The EW-vs-capw gap is the
  mega-cap artifact the collective flagged. BUT the signal is structurally small-cap: iBM_orgc~size_pctile
  Spearman = −0.705, top-25 median size-pctile 9.1%, frac size-top40 0.026. The EW "survival" is exactly
  the small-cap tilt paying off vs an EW (small-friendly) bar. Under the deployable cap-w bar (mega-cap
  anchored, no-short), it fails. This is the net-issuance wall reproduced, not escaped.

---

## Escalation check (Q-Lead auto-triggers)
- HIGH-severity concerns ≥5? NO (4 raised, all resolved; no unresolved HIGH).
- AX axiom hard FAIL ≥3? NO.
- PIT C1 (lockbox/lookahead) violation? NO — as-of Factor_Date roll, forward Ret_1m, no full-sample stat.
→ No escalation. Standard CLEAN_NEGATIVE emission.

## Net resolution
CLEAN_NEGATIVE stands and is reinforced by adversarial testing. Mechanism: intangible adjustment
barely re-ranks KR value (0.98 cross-rank corr), does NOT tilt value large-cap (signal~size −0.71),
and forcing a large-cap/intangible tilt makes post-2017 cap-w alpha strictly worse. KR value death is
NOT primarily an intangible-mismeasurement artifact — it is real death that intangible adjustment does
not repair. Value-family (standalone long-only) research direction: CLOSE.
