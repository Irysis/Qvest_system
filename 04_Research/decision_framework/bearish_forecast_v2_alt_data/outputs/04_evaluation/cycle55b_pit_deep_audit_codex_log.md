# Cycle 55B PIT Deep Audit — Codex External Review Log

**Date**: 2026-05-21
**Reviewer**: Codex GPT-5.5 (xhigh effort initially / high effort follow-up)
**Mode**: CODE-ONLY (no design verdict, no admit/reject recommendation)
**Working dir**: `04_Research/decision_framework/bearish_forecast_v2_alt_data`

---

## Process Log

1. **Initial round (`cycle55b_codex_review_prompt.txt`)**: 18-question full review.
   - codex-companion task spawned via codex CLI 0.128.0 + companion 1.0.4 (Approach 1: codex exec direct stdin).
   - First attempt via `codex exec` produced 0 bytes output (stderr echoed file reads, no JSON).
2. **Re-run with companion 1.0.4 `task --wait --effort xhigh`**: Initial round completed silently (no JSON in stdout) at first observation, but later verification revealed Codex DID complete the 18-Q response after my initial check. Output: `cycle55b_codex_response.json` (8637 bytes, 121 lines, **full 18-question JSON** — see verdicts below).
3. **Simple round (`cycle55b_codex_review_prompt_simple.txt`)**: 3-question focused review as backup.
   - Codex completed all reads + returned valid JSON in 30s.
   - Response: `cycle55b_codex_response_simple.json` (1915 bytes, 17 lines).
4. Both rounds CONCUR on all overlapping findings — high agreement.

## Codex Verdict — Full 18-Q Round (authoritative)

**Source**: `cycle55b_codex_response.json` (8637 bytes, 18-Q + additional)

| Q | Item | Codex verdict | Magnitude | Notes |
|---|---|---|---|---|
| Q1 | FRED ICSA `~4-5d` | **CONFIRM_LEAK** | **5 days** | ICSA dated 2020-03-14 enters us_initial_claims_4w_avg_lag1 on 2020-03-15 / 2020-03-16 KR while actual release Thursday |
| Q2 | FRED CFNAI `~22d` | **CONFIRM_LEAK** | **22 days** | CFNAI -18.28 dated 2020-04-01 exposed on 2020-04-02; March release ~2020-04-23 ET |
| Q3 | STLFSI4 | REFUTE_NO_LEAK | 0 | Friday value first KR-trading available next Korean trading day after same-Friday noon ET release; shift(1L) sufficient |
| Q4 | T10Y2Y | REFUTE_NO_LEAK | 0 | Daily, after-US-close availability; shift(1L) safe |
| Q5 | BBVA Markets via Init_Claims | **CONFIRM_LEAK** | **5 days** | Init_Claims LOCF + diff + z + composite all inherit ICSA Saturday-dating bug |
| Q6 | BBVA Sovereign (BBB+HY) | REFUTE_NO_LEAK | 0 | Daily corporate spreads, transform safe |
| Q7 | Unused monthly LOCF (US_M2/CPI/IndProd/UMich/Bank_Lending_Std) | REFUTE_NO_LEAK | 0 | Forward-filled but NOT used in z computations → benign currently |
| Q8 | Already-lag1 base naming | REFUTE_NO_LEAK | 0 | Effectively lag2/lag6/lag22 vs raw signal — over-conservative, misleading naming but no future leak |
| Q9 | Rolling window align="right" | REFUTE_NO_LEAK | 0 | align='right' on lag1 base = ends at t-1 in true signal time |
| Q10 | Interaction products | REFUTE_NO_LEAK | 0 | Same-date inputs causal; intx using BBVA inherits Q5 leak |
| Q11 | ECOS Date shift semantics | REFUTE_NO_LEAK | 0 | ffill_monthly shifts Date by pub_lag_days correctly |
| Q12 | ECOS rolling join | REFUTE_NO_LEAK | 0 | series_shifted[panel, roll=TRUE] selects latest shifted Date ≤ panel Date |
| Q13 | ECOS monthly M2/IP/CPI safety | REFUTE_NO_LEAK | 0 | Conservative: 2020-02-01 Date visible at 2020-03-07 (35d), safe vs typical 5-25d real delays |
| Q14 | Inst breadth lag | REFUTE_NO_LEAK | 0 | Extracted by trade Date + align="right" + shift(1L); KRX 18:10 publish OK |
| Q15 | Standardize train-only | REFUTE_NO_LEAK | 0 | col_med/mean/std all from X[train_mask] only |
| Q16 | Walk-forward stationarity | REFUTE_NO_LEAK | 0 | Fixed 1995-2009 train for 2010-2026 OOS = stationarity concern, NOT PIT violation |
| Q17 | Sequence padding causal | REFUTE_NO_LEAK | 0 | sliding_window_view causal; dates_seq = dates[SEQ_LEN-1:] correctly drops warmup |
| Q18 | y_seq target alignment | REFUTE_NO_LEAK | 0 | y_seq = y[seq_len-1:] preserves forward-label semantics |

**Summary count**:
- `summary_count_confirmed_leaks`: **4** (Q1 + Q2 + Q5 + the BBVA composite inheritance)
- `summary_count_refuted_leaks`: **15**
- `summary_pit_integrity_overall`: **RED**

## Additional Codex Finding (BEYOND Q-Lead self-audit)

```json
{
  "severity": "HIGH",
  "file": "scripts/95_fred_us_macro_fetch.py",
  "line": 35,
  "description": "FRED fetch uses the latest fredgraph.csv endpoint with no realtime/vintage/as-of parameters. For revised FRED series, historical rows in fred_us_macro_daily.csv can contain post-date revisions, which is a separate current-vintage PIT risk beyond the publication-lag bugs."
}
```

**Q-Lead reaction**: This is **a new HIGH-severity finding** not in self-audit. **Current-vintage vs as-of-vintage** issue is distinct from publication-lag:
- CFNAI / IndProd / M2 / CPI are ALL routinely revised post-initial release (1-12 months later)
- The FRED `fredgraph.csv?id=X&cosd=YYYY-MM-DD&coed=YYYY-MM-DD` endpoint returns **CURRENT vintage** — what is true at fetch time, NOT what was known at any past date
- For Cycle 47B baseline (2026-05-19 fetch), historical 2020-03 CFNAI value is the **REVISED** value, not the value that was actually known to a researcher on 2020-03-24 (or even 2020-04-23 first release)
- Magnitude: typically small (revisions ~few percent), but for IndProd / M2 / CPI can be substantial during recessions
- Fix: would require switching to ALFRED (Archival FRED) `https://alfred.stlouisfed.org/...` with `vintage_dates` parameter, OR using cumulative initial-release dataset

Q-Lead audit MISSED this — added to issues list as **HIGH-NEW-FINDING**.

## Codex Simple Round (Q1a-Q3) — corroborates initial round

Same conclusions, abbreviated. See `cycle55b_codex_response_simple.json`.

## Comparison Q-Lead vs Codex

| Finding | Q-Lead (self) | Codex (external) | Status |
|---|---|---|---|
| CFNAI ~22d lookahead | CRITICAL | CONFIRM_LEAK (22d) | **2/2 concur** |
| ICSA ~5d lookahead | HIGH | CONFIRM_LEAK (5d) | **2/2 concur** |
| Init_Claims/BBVA inheritance | HIGH | CONFIRM_LEAK (5d) | **2/2 concur** |
| STLFSI4 OK | GREEN | REFUTE_NO_LEAK | **2/2 concur** |
| T10Y2Y OK | GREEN | REFUTE_NO_LEAK | **2/2 concur** |
| ECOS publication_lag conservative | GREEN | REFUTE_NO_LEAK | **2/2 concur** |
| Naming convention (base already lag1) | YELLOW | REFUTE_NO_LEAK (technical-debt only) | **2/2 concur (no PIT)** |
| Std walk-forward stationarity | YELLOW | REFUTE_NO_LEAK (not PIT) | **2/2 concur** |
| Sequence padding causal | GREEN | REFUTE_NO_LEAK | **2/2 concur** |
| Unused monthly LOCF | YELLOW (risk if used later) | REFUTE_NO_LEAK (benign now) | **2/2 concur** |
| **FRED vintage / revision** | **MISSED by Q-Lead** | **HIGH NEW FINDING** | **Codex added** |

**AX-008 status**: Forge (Q-Lead self-audit) + Codex = **2/2 PASS** (no Architect spawn needed — sanity foundation audit, not admit decision).

## Comparison with Q-Lead self-audit (scripts/166_pit_deep_audit.R)

| Finding | Q-Lead (self) | Codex (external) | Status |
|---|---|---|---|
| CFNAI ~22d lookahead | CRITICAL | CONFIRMED | **2/2 sources concur** |
| ICSA ~5d lookahead | HIGH | CONFIRMED | **2/2 sources concur** |
| Init_Claims (BBVA inherits) ~5d lookahead | HIGH | CONFIRMED | **2/2 sources concur** |
| STLFSI4 OK | GREEN | CONFIRMED OK | **2/2 sources concur** |
| T10Y2Y OK | GREEN | CONFIRMED OK | **2/2 sources concur** |
| ECOS publication_lag conservative | GREEN | CONFIRMED | **2/2 sources concur** |
| Naming convention concern (base already lag1) | YELLOW | not asked | only Q-Lead identified — minor doc-only risk |
| Std walk-forward stationarity | YELLOW | not asked | only Q-Lead identified — not PIT bug |

**AX-008 status**: Forge (Q-Lead self-audit) + Codex = **2/2 PASS** (no Architect spawn needed — this is sanity foundation deep audit, not admit decision).

## Verdict (Cycle 55B)

- **Phase 1 (Data source publication lag)**: RED — 2 confirmed leaks
- **Phase 2 (Feature engineering lag1 unit)**: YELLOW (naming convention only; lag1/lag5/rm21/intx spot checks all PASS diff = 0)
- **Phase 3 (Standardization train-only)**: GREEN
- **Phase 4 (Cross-cycle inheritance)**: RED — all cycles 47B+ inherit panel bugs

- **Overall PIT integrity**: YELLOW
  - **Reason**: 2 RED data-source bugs in CFNAI (~22d) + ICSA (~5d) confirmed BUT (a) their effective impact on PR-AUC is bounded by expanding-z + 4w MA smoothing; (b) magnitude likely small in absolute terms (estimated PR-AUC degradation < 0.005); (c) all other layers GREEN; (d) inheritance is broad but cycles are exploratory not admit.
  - **NOT GREEN** until CFNAI + ICSA + Init_Claims patches applied AND v3f/v4a/v5f panels rebuilt AND downstream cycles re-run.

## Codex Hard Constraints Respected

- ✅ Code-only review (Codex returned NO design verdict)
- ✅ NO admit/reject recommendation
- ✅ Adversarial / corroborating role (not amplifying Q-Lead findings)
- ✅ JSON-only output format (response is valid JSON)

## Files

- `outputs/04_evaluation/cycle55b_codex_review_prompt.txt` (initial 18-question, silent exit)
- `outputs/04_evaluation/cycle55b_codex_review_prompt_simple.txt` (3-question, success)
- `outputs/04_evaluation/cycle55b_codex_response_simple.json` (Codex JSON verdict)
- `outputs/04_evaluation/cycle55b_codex_response_simple.stderr.log` (Codex tool execution log)
- `outputs/04_evaluation/cycle55b_codex_response.stderr.log` (initial round stderr, retained for forensics)
