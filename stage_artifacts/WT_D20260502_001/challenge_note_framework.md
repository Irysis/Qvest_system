# Challenge Note — WT-D20260502_001 Alpha Research

**Generated**: (will be filled by finalize step after Codex critic response)
**Charter §8 No Silent Override compliance: each Codex concern → ACCEPT / PARTIAL / REBUTTAL**

## 0. Pre-Critic Self-Assessment (alpha agent's own audit)

The alpha-research agent identified the following as the **weakest assumptions** in
its own draft (full transparency, before Codex review):

### W1: Hypothesis pivot from pure Quality to dual-axis (Quality + Tail-Skewness)
- **Original**: Quality (Q07/Q25) bad-state activation
- **Empirical 18Y test**: Quality alone has near-zero ic_bad_state (Q07 ic_bad=0.026,
  Q25 ic_bad=0.017, Q08 ic_bad=0.005)
- **True defense factor**: D43_Skewness (ic_bad=0.037, NW_t_bad=4.63)
- **Pivot decision**: Dual-axis composite (Q07+Q25+D43) honors original spirit
  while incorporating empirical evidence
- **Risk**: Risk-research must evaluate AX-001 v2 4-axis on this composite, NOT
  pure Quality

### W2: Bad/Normal IC ratio = 1.28 (not >> 1.5 ideal)
- **Observed**: ic_bad=0.0431, ic_normal=0.0337 → ratio 1.28
- **Interpretation**: Composite is statistically significant in bad-state
  (NW_t_bad=4.99) but NOT regime-conditional in extreme sense
- **Implication**: This is more of a "balanced defense + offense" alpha than
  pure regime-switch defense. AX-001 v2 axis 3 (bad/normal IC ratio) marginal.

### W3: Cert eligibility (harvey_t_count=2 < 3) — performance vs cert tradeoff
- 3-factor composite (best perf): Q07 (4.17) + D43 (4.02) → 2 factors with NW_t≥3
- 4-factor (cert eligible but worse perf): adds R13 (3.32) → all metrics degrade
- **Decision**: Performance-optimal 3-factor over cert artificiality
- **Cert outcome**: alpha_discovery_certificate NOT_ISSUED → PG1 admission blocked
  by passive deny per Charter §10. Q-Lead decision required.

### W4: Q07/Q25 coverage at as_of 2026-05 (19% / 20%)
- **Cause**: Fiscal year end + 5-month financial statement delay (PIT C4)
- **Mitigation**: coverage_min=0.15 used; confidence_vector reduces signal weight
  for low-coverage tickers
- **Risk**: 28 of 348 tickers (8%) have ZERO Quality factor data → confidence reduced

### W5: Definition C (MRS expanding p70) regime gating choice
- **Tested**: 3 definitions (A: Category {CAUTION,CRISIS}, B: Layer1_Alert MSM, C: MRS p70)
- **Selected**: C (only definition with positive ic_bad on primary Quality factors)
- **Risk**: Definition selection is itself a methodological choice. M=3 definitions
  inflates effective trials. Method shopping log records this.

### W6: KR market 18Y window includes structural breaks
- 2008 GFC, 2011 EU debt, 2018 trade war, 2020 COVID, 2022 inflation, 2026 current CAUTION
- All factor coverage stable (Factor DB build PIT-safe)
- Subperiod stability score = 1.0 (all 3 sub-periods positive IC) — robust
- Risk: KR-specific structural changes (2017 short-sell ban, 2020 retail flow surge)
  may have altered factor mechanics. Subperiod analysis confirms stability empirically.

---

## 1. Codex Critic Concerns (will be filled after response received)

[PLACEHOLDER — to be filled with each concern from Codex response]

For each Codex concern:
- **Severity**: HIGH / MED / LOW
- **Reference**: AX-XXX / PIT-CXX / L-XXX / RF-XX
- **Decision**: ACCEPT / PARTIAL / REBUTTAL
- **Rebuttal evidence (if not ACCEPT)**: 학술 paper + L-code + 정량 data 3축

---

## 2. Self-rationalization Auto-detection

The alpha agent ran grep on its own writeup for rationalization phrases:
"미미", "관행적", "보수적이면 OK", "대부분 결과 동일", "실무적", "이미 반영"

(Result will be reported in finalize step — alpha agent's own honest audit)

---

## 3. Decision Summary (pending Codex response)

- ACCEPT count: TBD
- PARTIAL count: TBD
- REBUTTAL count: TBD
- Q-Lead escalate triggers (HIGH ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 violation): TBD
