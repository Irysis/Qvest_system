# Challenge Note — WT-D20260529_002 Track BAC (alpha-research)

**Codex Critic Round** (gpt-5.5 xhigh, 2026-05-29T14:56): stance = **REJECT** (veto_flag=false).
**Agreement**: Codex agrees BAC must NOT advance (`agree_with_claude` on DROP direction). REJECT is about
audit-cleanliness of the *negative finding*, not the verdict. Disposition per Charter §8 No Silent Override.

## Self-rationalization auto-detection (mandatory)
Codex flagged 3 rationalization phrases in my draft:
1. "BAC US/intl premium does NOT transfer to KR" — **ACCEPTED as overgeneralization** (C6). Softened below.
2. "AX-000 honest limit reported" — retained but **scoped to the tested proxy**, not a universal KR-BAC law.
3. "orthogonality is good but moot" — factually correct (signal cor 0.079 / return cor -0.042 measured; alpha negative) but rephrased to avoid dismissive tone.
grep of {미미/관행적/실무적/보수적이면/대부분 결과 동일} on my rebuttals: **0 hits**.

## Concern disposition

| ID | Sev | Codex concern | Class | Disposition |
|----|-----|---------------|-------|-------------|
| C1 | HIGH | All graduation gates fail (rank_IC -0.0156, ICIR -0.153, Harvey t -2.31, DSR 0.0075, sub-stab 0, mono -0.358) | **ACCEPT** | Confirms DROP. No rebuttal — this IS the finding. |
| C2 | HIGH | Low-risk thesis fails: AX001_v2=-0.831, realized_beta=0.821 (not low-beta), cor_vs_lowbeta_BAB=0.624 → AX-005 failed family | **ACCEPT** | Already my central finding; matches `learning_kr_lottery_anomaly_reversal.md` + AX-005. |
| C3 | HIGH | PIT not audit-clean: C13 manual sign, C15 direct parquet, C10 same-day liquidity | **PARTIAL** | C10 **fixed** (strict t-1 addendum) — rank_IC -0.0157 unchanged, DROP robust. C13 attested below. C15 = documented daily-RAWDATA carve-out (same as REV/RESID_MOM tracks, signal-engineering not factor-DB IC). |
| C4 | MED | DSR n_trials=4 understates cross-track budget | **ACCEPT** | Recomputed full budget n_trials=32 (8 Cycle-3 tracks × 4 internal): DSR = **0.00044** (worsens — more conservative, DROP firmer). |
| C5 | MED | No BAC challenge_note / lineage / canonical artifacts | **ACCEPT** | This note + `record_package_lineage()` for `alpha_package_BAC.json`. Risk/opt/weights/cov correctly ABSENT (alpha role boundary; DROP needs no downstream). |
| C6 | MED | "does NOT transfer to KR" overgeneralizes one proxy | **PARTIAL ACCEPT** | Scoped: the **tested SMAX-cleaned market-correlation BAC proxy** fails in KR; this is strong evidence (264 mo, all subperiods neg, robust to strict-PIT) but NOT a universal proof that no correlation-based construction can ever work. AX-000 framing narrowed accordingly. |

### RF-A audit (Codex requested challenge_note coverage A1–A7)
- **RF-A1** (sub-stability<0.5, all neg): TRUE — core DROP evidence.
- **RF-A2** (SMAX-clean -0.0156 worse than raw -0.0149): TRUE — control adds no alpha; reported in method_log.
- **RF-A3** (recent-period rescue): FALSE — 2021-23 ICIR -0.026, OOS rank_IC 0.0009, no rescue.
- **RF-A4** (post-neutral collapse): FALSE — raw/sector/clean all negative, nothing to collapse.
- **RF-A5** (top-decile illiquid): TRUE under same-day filter (3 <1e8, 19 <2e8) → **resolved** by strict t-1 liquidity addendum (rank_IC unchanged -0.0157).
- **RF-A6** (multi-testing budget): TRUE → resolved (full-budget DSR 0.00044).
- **RF-A7** (single-snapshot): FALSE — 264 sig_dates true panel, Codex confirms clean.

## C13 direction attestation (Codex C3 rebuttal-required item)
BAC's sign is **a-priori from theory**, not a data-driven flip: AFGP-2020 defines the low-risk premium as
LONG low-correlation. `bac_raw := -corr_part` encodes "low correlation → high alpha" by definition of the
published thesis — this is the Z_Score_Aligned-equivalent canonical direction, NOT a NEGATE_FACTORS/FLIP_SIGN
on an observed result (which C13 prohibits). I explicitly **do NOT** sign-reverse to long-high-correlation:
that would be high-beta pro-cyclical (realized_beta 0.82 confirms), economically void as a "low-risk premium",
and a C13-violating data-mined flip. Per Codex rebuttal item: a sign-reversed BAC is only admissible if a NEW
C13-compliant economic thesis independently passes all gates — not pursued (no such thesis).

## Scoped verdict (post-disposition)
**DROP** — the tested SMAX-cleaned market-correlation BAC proxy does not produce alpha in KR over 2004–2023
(264 mo): negative rank-IC robust to strict t-1 PIT, fails all graduation gates, 62% redundant with the
already-failed KR low-risk/low-beta family (AX-005), and refutes its own low-beta thesis (realized_beta 0.82).
Mechanism consistent with KR lottery/skewness anomaly reversal (retail lottery preference). This is a durable
**negative result for this proxy**, not a universal KR-correlation impossibility claim.

## Escalation check
HIGH concerns = 3 (< 5 threshold). AX hard FAIL: AX-005 FAIL + AX-007 FAIL = 2 (< 3). No PIT C1/lookahead
violation (C10 resolved, C14 PASS, RF-A7 clean). Codex stance REJECT but I do NOT rebut-ALL (4 ACCEPT + 2
PARTIAL). → **No automatic Q-Lead escalate triggered.** Verdict DROP stands with full audit trail.
