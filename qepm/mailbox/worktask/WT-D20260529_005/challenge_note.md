# Challenge Note — WT-D20260529_005 Track CAP_TIER (alpha-research)

Codex Critic Round (gpt-5.5, xhigh) — stance **REJECT**, veto_flag false (devil's advocate, no veto).
Resolution: 6 concerns classified per Charter §8 No Silent Override. **Core concern ACCEPTED and fixed (not rebutted).**

## Decision summary
Codex C1 (full-sample ICIR weight lookahead) was a legitimate hard PIT-C1/C3 violation. I **rebuilt the entire construction with expanding-window walk-forward ICIR weights** (`run_captier_pit.R`, no full-sample fitting). The honest result: the construction's apparent strength was largely the lookahead. Under PIT the construction is **below baselines** — reported as a scoped finding, not a verdict.

| Concern | Severity | Class | Action |
|---|---|---|---|
| C1 full-sample ICIR weights → score same dates (PIT-C1/C3/AX-002/RF-A6) | HIGH | **ACCEPT** | Rebuilt expanding-window (warmup 36m, IC Date<t only). Re-ran all diagnostics + canonical. |
| C2 alpha_scores.parquet carries exret/ret forward cols (PIT-C2/RF-A7) | HIGH | **ACCEPT** | Clean artifact = Date,Ticker,tier,score,confidence only. Audit-with-label copy separated. |
| C4 RF-A2 composite < best single factor | MEDIUM | **ACCEPT** | Added V02_EP-only + POOLED342 baselines under same PIT harness. Composite LOSES. |
| C3 AX-007 single-sleeve top-25 | HIGH | **PARTIAL** | Acknowledged: this is an alpha-stage signal, not a deployable sleeve. Finding routes to DPL-feature / multi-sleeve, not standalone (measurement-graduation §5). Not alpha-stage's role to build sleeves. |
| C5 missing risk/opt/weights/cov artifacts, no challenge_note | HIGH | **PARTIAL/REBUTTAL** | alpha-research scope = α̂ only (agent_role_guard Hook forbids Σ/weights). challenge_note.md now written. risk/opt artifacts are downstream stages, intentionally absent at alpha stage — not a silent omission. |
| C6 references author-year only | MEDIUM | **PARTIAL** | Mechanisms cite Basu 1977 / Fama-French 1993 / Novy-Marx 2013 / Bali 2011 / Boyer-Mitton 2010. KR-specific lottery reversal from memory [[kr_lottery_anomaly_reversal]]. Moot given the construction fails PIT anyway. |

## C1 fix detail (the decisive one)
- **Before (in-sample, draft)**: tier weights = full-sample ICIR over 2005-2023, applied to score 2005-2023. Combined portfolio-alpha t = **3.367**, netSR 0.832. This is look-ahead.
- **After (PIT walk-forward)**: at each sig_date t, tier weights = expanding ICIR using only IC realized strictly before t (warmup ≥36m → scores start 2008-01). Combined portfolio-alpha t = **1.622** (p=0.105), netSR 0.428, n=190. **Below 2.95 hurdle.**
- The ~1.7 t-stat drop is the lookahead premium Codex identified. Honest reporting per AX-000: this is an *empirically established limit of this construction*, not a method failure to hide.

## C4 fix detail — baselines under identical PIT harness (top-25, 15bps, 2e8)
| Construction | PIT port-alpha t | netSR | IR |
|---|---|---|---|
| **CAP_TIER (separated + expanding-ICIR multi-factor)** | **1.622** | 0.428 | 0.428 |
| POOLED342 (no tier split, same 8 factors, expanding-ICIR) | 2.253 | 0.635 | 0.635 |
| V02_EP-only (within-tier z, single factor) | **3.556** | 0.878 | 0.878 |

**Finding**: cap-tier separation + multi-factor ICIR-weighting *underperforms* both pooling and a single value factor under PIT. The tier split narrows breadth (25 names split across 2 tiers) and the 8-weight × 2-tier ICIR estimation adds noise that overwhelms the cap-conditional signal once lookahead is removed. The per-tier SMALL signal is real (PIT rank-ICIR 0.431, Harvey 4.92) but does not survive translation into a combined top-25 long-only portfolio better than simpler constructions.

## Self-rationalization check (Charter §8)
grep for {미미, 관행적, 실무적, 보수적이면 OK, 대부분 결과 동일}: **none used**. The result is reported as-is: the construction is below baselines under PIT. No softening language.

## Escalate check
- HIGH severity ≥5? Codex marked C1/C2/C3/C5 HIGH (4) — below 5 escalate trigger.
- AX hard FAIL ≥3? AX-007 FAIL only (1).
- PIT C1 violation found? Yes (C1) — but ACCEPTED + fully fixed before finalize, not deployed. No escalate needed (the system worked: Codex caught it, agent fixed it).
- Codex REJECT + agent rebuttal ALL? No — agent ACCEPTED the core (3 of 6), did not blanket-rebut. Q-Lead escalate not triggered.

## Net outcome
PIT-honest finding logged. The construction does NOT graduate (port-alpha t 1.622 < 2.95 HARD, DSR N=22 = 0.404 < 0.5 HARD). Scoped: *in THIS construction (cap-tier separation + expanding-ICIR multi-factor combine), N=190 months, portfolio-alpha t = 1.622, below pooled (2.253) and EP-only (3.556).* Source space remains open (per도훈 mandate — no "impossible" verdict).
