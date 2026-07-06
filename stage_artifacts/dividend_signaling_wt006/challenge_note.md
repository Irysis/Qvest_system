# Self-Adversarial Challenge — WT-D20260706_006 (dividend-signaling Lintner, mega-escape)

**Agent**: Alpha Research. **Method**: Opus 4.8 native adversarial (v8.2, no external Codex).
**Finalize verdict**: VALIDATED_NEGATIVE — dividend-signaling has zero/negative cross-sectional
picking edge in KR top-342, and does NOT escape the mega-cap trap. Clean closure of the
"information-signal escapes mega where price signals die" thesis for the dividend channel.

## Concerns raised (≥3, devil's advocate)

### C1 [ACCEPT→resolved] "div_yoy is really a value/quality proxy that is already dead in KR"
- Devil: KR value (dividend-yield LEVEL) and quality (profitability LEVEL) are proven dead
  (AX-003 distilled, KR value decay ref). If div_yoy is just correlated with those, the
  negative result is uninformative — it's the family, not the signaling channel.
- Test: cross-sectional Spearman(div_yoy, payout_yield_proxy)=0.215 and
  Spearman(div_yoy, div_level)=0.206. **Low correlation → div_yoy IS a distinct signal**,
  not a repackaged level/value proxy. So the negative is a genuine test of the CHANGE/signaling
  channel, not a re-run of a dead family.
- Resolution: distinctness confirmed. The signaling channel is genuinely tested and genuinely
  dead — a stronger (more informative) negative than "it's just value again."

### C2 [ACCEPT→resolved] "Extreme div_yoy outliers (max 8583x) drive an illiquid/unstable top-25"
- Devil: div_yoy std=147, max 8583x. A firm going from tiny→large dividend produces a huge
  ratio → the top-25 by raw div_yoy could be dominated by erratic tiny payers, making the
  negative an artifact of a garbage portfolio rather than a signal test.
- Test: re-ran with (a) winsorized div_yoy clip[-0.9, 3.0] and (b) BINARY "dividend increased
  >5%" (the cleanest Lintner signal, immune to outliers). Results: raw −1.904, winsorized
  −1.904 (identical — top firms all ≥3x so clip doesn't reorder), **binary −1.215 (still
  negative)**. Liquidity floor 2e8 already applied. TO annual ≈1.4-2.0 (low, annual signal).
- Resolution: verdict robust to construction. Outliers are NOT the story; the binary signal
  which has zero outlier exposure is also negative. Illiquidity ruled out by 2e8 filter.

### C3 [ACCEPT→resolved] "The annual→May lag is wrong; a lookahead is inflating (or here, an
  incorrect lag is suppressing) the result"
- Devil: DART annual reports filed ~March fy+1. If I stamped the signal usable too early, that
  is lookahead; if too late, I'm suppressing a real effect.
- Test: usable_ym = (fy+1)-05 (May of the year after fiscal-year-end), derived purely from the
  filing calendar, never from returns. This is the STANDARD KR annual lag (C4). Samsung series
  is economically sensible (2017/2018 increases, 2021 special dividend). The verdict is negative
  under this lag — if anything a lookahead would have HELPED the signal, so the conservative lag
  is not manufacturing a false negative. Signal window is 2016-05..2026-05 (108 forward months),
  entirely post-2017 — which is exactly the regime the escape question targets.
- Resolution: PIT-clean; the negative is not a lag artifact.

### C4 [ACCEPT→resolved] "A post-2017 mega edge could be a specific-firm artifact (1-2 names)"
- Devil: mega tier has only ~6.8 payers-with-YoY/month; a positive or negative t could be one
  firm (e.g. Samsung/SK Hynix dividend events coinciding with semi rallies).
- Test: The mega result is NEGATIVE (t_full −1.508, post2020 −1.775) under raw, winsorized
  (−1.508) AND binary (−1.413). A single-firm fluke would not survive three independent signal
  encodings with consistent sign and magnitude. mega top-4 long-only vs BM = −0.874. There is
  no positive mega edge to attribute to any firm — the escape simply does not exist.
- Resolution: no positive artifact to explain away; negative is stable across encodings.

### C5 [PARTIAL] "Low mega breadth (~7/10) means the mega test is underpowered — absence of
  evidence, not evidence of absence"
- Devil: With ~7 mega payers/month, the within-mega long-short splits 3-4 vs 3-4. Power is low;
  a true small edge could be undetected.
- Assessment: PARTIAL accept. Mega breadth IS thin — this is inherent to KR (most mega-caps pay
  regular dividends, so cross-sectional div-CHANGE dispersion within mega is small). I report
  this honestly as a caveat. BUT: (i) the point estimate is negative, not near-zero-positive;
  (ii) the FULL top-25 (207 payers, well-powered) is also negative (−1.90); (iii) ex-mega
  (mid+small, well-powered) is negative (−1.83). So even if mega alone is underpowered, the
  signal is dead in the powered tiers too. The escape thesis required a POSITIVE mega edge to
  offset the known price-signal death; we find no positive edge anywhere. Underpower cannot
  rescue a thesis that needed a positive and got a negative.
- Rebuttal basis: L (this WT) + high52 parallel (mega LS ≈0.68 dead) + insider ICIR 1.31
  (the ONE information signal that DID show large-cap lead) → dividend ≠ insider. The
  information-escape thesis holds only for insider, not for the dividend channel. Clean
  differentiation, not a blanket "information signals escape."

## Self-rationalization auto-check
No "미미/관행적/보수적이면 OK/대부분 동일" used to wave away a violation. The one hedge
(C5 mega underpower) is explicitly labeled PARTIAL with quantified compensating evidence
(powered tiers negative), not dismissed.

## Escalation check
- HIGH severity ≥5? No (0 — this is a clean negative, no PIT/constraint violation).
- AX axiom hard FAIL ≥3? No.
- PIT C1 lockbox/lookahead? No (annual May lag, filing-calendar-derived usable date).
- → No Q-Lead auto-escalate. Standard ALPHA_DONE with VALIDATED_NEGATIVE verdict.

## AX-008 triangulation note
Self-adversarial = 1 of 3 sources. This is a canonical_screen (contract-grade) negative;
forge is not required to CONFIRM a negative for closure (a negative alpha does not proceed to
book). The verdict is honest closure, not an admission claim — no forge/architect gate needed.
