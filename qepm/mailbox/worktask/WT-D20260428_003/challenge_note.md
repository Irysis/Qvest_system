# Alpha Agent Challenge Note — WT-D20260428_003 Iter 10 B (MAQGC)

**Generated**: 2026-04-28 KST (post-Codex)
**Agent**: alpha_research v1.2 (Opus 4.7 1M context)
**Codex Critic**: GPT-5.5 xhigh (dispatched 15:23 KST, completion ~10-15 min)
**Charter**: §8 No Silent Override + §10 Role Card v1.2 + v6.31 alpha_discovery_certificate
**Sibling parallel**: WT-D20260428_002 Iter 10 A (FIAPAS V2 sign-flipped, cert NOT ISSUED)

---

## TL;DR

MAQGC (Multi-Axis Growth Quality Composite) Iter 10 B is **HONEST FAIL**:
- 4-axis ex-ante composite per AFP 2019 QMJ KR-adapted — family-orthogonal to FIAPAS as designed
- ICIR 0.656 PASS / Subperiod 1.00 PASS / DSR_post 0.587 PASS / Cert cond1+2+3 PASS
- **rank_ic 0.0188 < 0.04 FAIL**, **Harvey-t 1.78 < 3.0 FAIL** (cond4: 0/3 specs ≥ 3.0)
- **D10-D1 spread NEGATIVE** (-0.00106) — long-only top20 deployment risk HIGH
- **Subperiod decay severe**: p1 ICIR 1.39 → p2 0.07 → p3 0.32

**Result**: alpha_discovery_certificate **NOT ISSUED** (issued = false). PG1 admission auto-denied via passive deny per Charter §10.

**Lesson learned**: AX-004 EXCLUSION (multi-axis composite permitted) confers eligibility, NOT predictive power. AFP 2019 QMJ does not transfer cleanly to KR top342 universe in 2015-2023.

---

## Self-rationalization Audit (per pit-enforcement.md auto-flag list)

Phrases checked: "영향 미미", "관행적 허용", "보수적이면 OK", "대부분 결과 동일", "이미 반영되어 있었을 것", "백테스트 기간이 충분히 길어서 상쇄"

**Result**: 0 hits in alpha_package_draft.json + alpha_validation.json + this challenge_note.

**Verdict explicit**: alpha_package primary_variant labeled "S1_ALL_4axes_HONEST_RESULT_FAIL". Verdict text states "FAIL — rank_ic 0.0188 < 0.04 graduation min, Harvey_t 1.78 < 3.0 graduation min, D10-D1 spread NEGATIVE, subperiod severe decay (p1 1.39 → p2 0.07)".

No PASS_BORDERLINE framing. No "economic re-justification" of negative D10-D1. No "may improve in future regime" speculation.

---

## Pre-registration Audit

- 4 axes (A1=Profitability, A2=Growth, A3=Safety, A4=CashFlowQuality) signs +1 each declared in `evaluate_iter10b.R` script comments BEFORE evaluation
- Composite = mean(A1..A4) equal-weight, no tuning, no weight optimization
- n_candidates_tried = 3 (S1 ALL, S2 Prof+Safe, S3 Prof+Grow as transparent axis-pruning record)
- S2 and S3 selected = FALSE; S1 (the ex-ante full composite) = TRUE
- No sign flips. No method shopping. Pruning increased not decreased Harvey-t — primary spec retained as registered.

---

## Family Orthogonality vs FIAPAS (Iter 10 A)

| Family | FIAPAS V2 (Iter 10 A) | MAQGC (Iter 10 B) |
|---|---|---|
| Primary | investor_flow / liquidity_diffusion | quality_multi_axis × growth |
| Mechanism | foreign+inst herding mean-reversion | quality + safety + growth + CFQ composite |
| Citation core | Choe-Kho-Stulz 2005 + Kim-Kim 2014 | AFP 2019 QMJ + LSV 1994 + Sloan 1996 |
| Family overlap | minimal | minimal |

**Verified orthogonal at family level**. Cross-correlation in factor space:
- A4 (CashFlowQuality) uses `Q05_Accrual` (fundamental quality, not flow-based) — orthogonal to FIAPAS V2_F3 retail-accrual MTC.
- Other 3 axes (Profitability/Growth/Safety) are pure fundamental — no overlap with FIAPAS investor-flow signals.

**However vs Q08_Composite_Quality (FactorDB existing parent proxy)**:
- mean spearman cor = **0.7155** — high overlap with incumbent quality signal
- This is a separate orthogonality concern: MAQGC is family-orthogonal to FIAPAS but nearly co-linear with existing FactorDB Q08

---

## Codex Stance & Resolution

**Codex stance**: [PENDING — to be filled after Codex completion ~ 10-15 min from 15:23 KST]
**Codex critical concerns**: [PENDING]

[Will be updated below post-Codex]

---

## Per-Concern Resolution Plan (template — populate after Codex response)

### C1 — [Codex concern title]
**Codex position**: [quote]
**Classification**: [ACCEPT / PARTIAL / REBUTTAL]
**Agent grounds**: [academic citation + L-code + quantitative data per pit-enforcement.md 3-axis rule]
**Action**: [spec change / package field update / Iter 11 mandate]

### C2 — ...

---

## Q-Lead Auto-Escalate Trigger Check

Triggers per CLAUDE.md alpha-research init:
- HIGH severity concerns ≥ 5 → Q-Lead escalate
- AX axiom hard FAIL ≥ 3 → Q-Lead escalate
- PIT C1 (lockbox / lookahead) violation found → immediate escalate
- Codex stance=REJECT + agent rebuttal ALL → auto Q-Lead

[Counts to be populated after Codex response]

---

## Lesson Pending (post-Codex registration)

**L-code proposed**: L-223_MAQGC_KR_AFP2019_does_not_transfer

**Lesson text**:
"AX-004 EXCLUSION (multi-axis quality composite permitted) confers eligibility, not predictive power. KR top342 universe 2008-2023, MAQGC 4-axis composite (AFP 2019 QMJ) yields rank_ic 0.019 / Harvey-t 1.78 / D10-D1 NEGATIVE spread. Strong p1 (2008-14 ICIR 1.39) but post-2015 decay severe (p2 0.07, p3 0.32). Cor 0.716 vs Q08_Composite_Quality (FactorDB existing composite) suggests no orthogonal contribution beyond incumbent quality factor. Eligibility ≠ profitability. AFP 2019 RAS US-validated QMJ does not transfer cleanly to KR top342 universe."

**Tags**: AX-004, AFP2019, KR_factor_decay, multi_axis_quality, long_only_top20_negative_d10_d1, family_orthogonality_vs_inheritance

**Core reference**: AFP 2019 RAS QMJ; Sloan 1996 AR; LSV 1994 JF; FactorDB Q08_Composite_Quality

**Register after**: Codex round complete + Q-Lead approval (this challenge_note + alpha_validation finalized)

---

## Iter 11 Recommendations (if Q-Lead chooses to continue B-track)

If MAQGC family is to be retained, alternative architectures:

1. **Regime-conditional MAQGC**: deploy only in MRS regimes resembling p1 (2008-14 high crisis-frequency) where ICIR 1.39. Drop in normal/bull regimes.
2. **Residualized MAQGC vs Q08**: take MAQGC composite, residualize against Q08_Composite_Quality (orthogonalize against incumbent), evaluate residual alpha.
3. **Drop MAQGC, pivot to Skewness × CFO accrual residual**: original 3rd candidate (Boyer-Mitton-Vorkink 2010 + Sloan 1996) deferred. Behavioral × fundamental cross-family — potentially genuinely orthogonal to both FIAPAS and quality_multi_axis.
4. **Structural mutation: long-short MAQGC**: AX-004 EXCLUSION clause includes long-short variant. KR has no legal long-short retail, but institutional sleeve permitted.

Recommendation: **Option 3 (Skewness × CFO accrual residual)** for highest novelty + family-orthogonal contribution, after Iter 10 A & B both fail.

---
