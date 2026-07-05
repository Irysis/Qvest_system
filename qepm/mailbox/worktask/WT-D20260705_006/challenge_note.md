# Self-Adversarial Challenge — WT-D20260705_006

**Agent**: Alpha Research (Opus 4.8 native adversarial, v8.2 — Codex Round 대체)
**Subject**: KR Conservative-Investment (FF5 CMA) multi-signal composite
**Verdict under challenge**: VALIDATED_NEGATIVE (holds — strengthened, not overturned)
**AX-008**: this is 1 of 3 sources (Forge + Self-Adversarial + Architect).

## Self-raised weaknesses (devil's advocate) + resolution

### W1 [ACCEPT-as-context] "rank-IC misread as realized alpha?"
- **Concern**: Could a positive rank-IC be dressed up as portfolio alpha (Cycle-2 trap)?
- **Resolution**: No such dressing here. Full-period core6 rank-IC ≈ 0 (mean_ic −0.0002, Harvey-t_NW −0.03) AND canonical top-25 PORT_t_NW = −0.445. Both agree negative. The rank-IC and PORT_t are reported separately (measurement-graduation §2). The authoritative metric (PORT_t) is the binding one. No misread.

### W2 [REBUTTAL] "composite is just a repackaged dead single-signal (IN04)?"
- **Concern**: DIST-QPM-003 warns multi-axis ≠ single-signal; is the reverse true — is this secretly single-signal?
- **Evidence (adversarial C1)**: composite rank-rho to components: AC24 0.77, AC09 0.77, IN06 0.66, GR03 0.60, AC05 0.52, **IN04 −0.04**. The composite loads on the accrual/asset-growth axes and is near-orthogonal to IN04. It is a genuine 6-axis conservative signal.
- **Evidence (adversarial C3)**: dropping IN04 (the only positive component) gives core5 PORT_t −0.274 — composite stays net negative either way. Verdict robust to component set. **REBUTTAL grounded**: not a repackaged single-signal; the negative verdict is a property of the *family composite*, not an artifact of one bad component.

### W3 [REBUTTAL] "lookahead present (C4 fundamental lag / C14 IC alignment)?"
- **Concern**: Fundamental factors are lookahead-prone if the 45d/May lag or IC-direction alignment leaks future info.
- **Evidence**: (a) All 12 factors loaded via `load_month_factors()` (C15) with IC-inferred direction 12/12, Usable_Date ≤ sig_date (C14) — no registry/default fallback. (b) Adversarial C4: recomputing pre-2017 with strictly-STALE (1-month-lagged) scores gives PORT_t +1.05 vs live +1.72 — a modest drop, NOT a collapse. If the signal were lookahead-inflated, stale scores would destroy it. It survives with worse info. **No lookahead.**

### W4 [ACCEPT] "top-25 illiquid — alpha is a micro-cap artifact (RF-A5)?"
- **Concern**: KR anomalies often live in micro-caps that evaporate under the 2e8 liq floor / top-25.
- **Evidence (adversarial C2)**: median selected-name 20d ADV = 7.71B KRW; only 3.9% of selections below 5e8. Selections are large, liquid K200/KQ150 names. **Not a liquidity artifact** — which makes the negative verdict *more* credible (no hidden micro-cap alpha being masked).

### W5 [ACCEPT — core finding] "is the negative just post-2017 cohort decay, not a real family death?"
- **Concern**: Should I attribute failure to KR post-2017 decay (out of scope) rather than the family?
- **Evidence (subperiod + C5)**: pre-2017 PORT_t **+1.72** (real premium existed) → post-2017 **−1.52** (flipped). Within pre-2017: 2005-2011 +2.19 → 2012-2016 +0.47 → post-2017 −1.52 = **monotone decay across the full sample**, not a cliff at 2017 and not a single 2008 window. oos_retention median −1.37 (all anchored splits negative). This is the documented KR IC→PORT_t transition wall + cohort decay operating on yet another distinct family. I report it honestly as VALIDATED_NEGATIVE; I do NOT attribute it to the constraint envelope (AX-000 corollary / INV-7 firewall).

### W6 [PARTIAL] "why_now = distinct family — but is the orthogonality actually useful?"
- **Concern**: The thesis leans on diversifying-sleeve value (SR-2.5 lever 2).
- **Evidence**: composite rank-rho to incumbent momentum M04 = +0.041 pooled / −0.013 mean-monthly (vs M01 12-1 = +0.019) — genuinely orthogonal. BUT per measurement-graduation §6 "직교 ≠ 수익": orthogonality without positive realized PORT_t contributes nothing to book-marginal ΔIR. A diversifying sleeve with negative standalone alpha degrades the book. **PARTIAL**: orthogonality confirmed (reportable fact), but it does not rescue the sleeve. ΔIR is the governor's call, not mine — I report the raw orthogonality only.

## Self-rationalization auto-detection
Scanned my own reasoning for banned phrases ("미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일"). None used to excuse a gate failure. The verdict is a clean fail on the authoritative metric, not a rationalized pass.

## Escalation triggers (checked)
- HIGH severity ≥5: NO (verdict is a clean negative, not a governance breach).
- AX axiom hard FAIL ≥3: NO.
- PIT C1 (lockbox/lookahead): NO — C4 (stale-score test) confirms no lookahead.
→ **No Q-Lead auto-escalation required.** Report as VALIDATED_NEGATIVE.
