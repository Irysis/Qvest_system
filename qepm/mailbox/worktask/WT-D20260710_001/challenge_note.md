# Self-Adversarial Challenge — WT-D20260710_001 Alpha (v8.2, Opus 4.8 native)

**Alpha**: MID-tier(11-30) concentrated MULTI-AXIS composite (6 families: value/revision/momentum/reversal/quality/liquidity).
**Selected**: C3_multiISw_midemph. **Canonical cap-w PORT_t = 2.08** (screening, NW lag-3, metric_type=canonical_screen, p=0.038).
**Finding**: multi-axis breadth does NOT exceed the ~2.4 mid-cap ceiling; it is slightly WORSE than the incumbent single composite (score_eff 2.75) and the prior single-axis tier-emphasis (2.40-2.52). All variants < HARD 2.95. Decisive structural negative.

Harness calibration: reproduced prior base_score_eff canonical PORT_t **2.7488** (prior 2.749) exactly — alignment/anchor confirmed before any new measurement.

---

## Devil's-advocate concerns (≥3) — classification + resolution

### C-1 [PARTIAL/REBUTTAL] "Composite construction is suboptimal — you didn't give multi-axis a fair chance"
- Concern: tier_mult (0.25/1.0/0.5) borrowed from prior, not optimized; ISw weights leaked value's IS strength; maybe a value-excluded or differently-weighted composite clears 2.95.
- Resolution: **PARTIAL acknowledgment, REBUTTAL on the ceiling claim.** I tested **5 constructions** (EW-no-tier 1.79, EW-mid-emph 1.76, ISw-mid-emph 2.08, MID-gate −1.23, score_eff+mid-emph 2.52) plus the incumbent score_eff (2.75). Every one is < 2.95. The ceiling conclusion is robust across the construction space, not a single-config artifact. I concede I did not grid-optimize tier_mult or run a value-excluded variant — but a well-tuned incumbent composite (score_eff, 2.75) ALREADY fails 2.95, and adding MID emphasis to it makes it worse (2.52). No reasonable construction in this family clears the gate. Quantified, not hand-waved.
- Evidence: `screen_result.rds` cand_IS table + `supplement_tab.rds`.

### C-2 [ACCEPT — strengthens negative] "IS-selection leaked value (which decayed); true OOS is worse than 2.08"
- Concern: C3 was IS(<=2018-12)-selected where V02_EP was strongest (IS port_t 4.24); value decayed post-2015 → full-period 2.08 flatters the true OOS.
- Resolution: **ACCEPT.** This makes the FAIL MORE decisive: cap-w **post-2017 active t = −0.885 (negative)** and subperiod IC decays 0.071(04-15)→0.024(15-20) (stability 0.33<0.5). The honest post-decay reality is worse than the full-period 2.08. Documented in CF-2/CF-4. No graduation claim made. Not a process violation — an honest disclosure that reinforces the negative.

### C-3 [REBUTTAL] "You conflated cross-sectional rank-IC with realized portfolio-alpha (Cycle 2 error)"
- Concern (mandatory C2 self-check): rank-IC 0.0526 is strong (> incumbent 0.044); did I read that as success?
- Resolution: **REBUTTAL — explicitly separated.** rank-IC 0.0526 and cap-w PORT_t 2.08 are reported as DISTINCT; CF-3 + diagnostics.self_adversarial.ic_vs_portt_distinct name the IC→PORT_t transfer wall directly. EW-universe port_t (4.10) shows the selection signal is real among peers but does not transfer to the cap-w mandate benchmark. selection_objective = canonical_port_t (not rank_ic).

### C-4 [REBUTTAL] "Benchmark alignment inflates/deflates the result"
- Concern: forward-shifted cap-w KOSPI200 could misalign.
- Resolution: **REBUTTAL.** Calibration reproduced the prior anchor (base_score_eff 2.7488 vs prior 2.749) exactly with identical bench construction (run_forge_midcap.R lines 32-37). lag1(t-1) rank-IC 0.028 < real 0.053 → PIT graceful, no same-month look-ahead. placebo (within-date shuffle) rank-IC 0.0044 ~ 0 → no spurious structure.

### C-5 [REBUTTAL — immaterial, verified] "Liquidity floor 2e8 (vs request 5e7) biases selection"
- Resolution: score_eff canonical PORT_t identical with liq_min=0 vs 2e8 (**2.7488 both**) — top-25 names are all large-cap, floor non-binding at the portfolio level. Using 2e8 = constitution deployment floor (WT brief), more realistic. Verified immaterial by direct A/B, not assumed.

### C-6 [PARTIAL — disclosed] "alpha_vector cross-section is 2026-04-01, not as_of 2026-07-10"
- Resolution: **PARTIAL/disclosed.** Panel inherits tier_panel's range (max 2026-04-01). The DISCOVERY VERDICT uses the full 268-month history and is unaffected. The 3-month-stale current cross-section only affects the (moot, since FAIL) alpha_vector for deployment. Flagged via `signal_as_of_date` field.

---

## Self-rationalization auto-scan
Scanned for: "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일". Instances of "immaterial"/"slightly worse"/"does not change" are each backed by explicit numbers (2.7488=2.7488; 2.08 vs 2.75; 5-variant table) — quantified, not rationalization. No auto-RE-VIEW triggered.

## AX-008 triangulation
Self-adversarial (this note) is 1 of 3 sources (Forge + Architect pending, 2/3 required). Forge is authoritative for admission — alpha stage does NOT declare graduation.

## Escalation check
HIGH severity flags = 2 (CF-1, CF-2) < 5 threshold. No AX axiom hard FAIL. PIT graceful (lag1<real). **No auto-escalate** beyond normal Q-Lead reporting.

## Net verdict
Alpha package stands as a **decisive, honest structural negative**: the mid-cap ceiling (~2.4-2.75 cap-w PORT_t) is NOT liftable by multi-axis breadth; genuinely orthogonal (cor 0.567) 6-family MID composite achieves only 2.08, post-2017 cap-w negative. No spec change required — measurement is the finding.
