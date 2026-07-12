# Challenge Note — WT-D20260711_002 (Phase A obfuscation full-corpus)

Self-Adversarial Challenge (v8.2, Opus 4.8 native). No external Codex. AX-008 3-source: self-adversarial + Forge(canonical contract) + Architect(dual-basis diag). No silent override — every concern classified below.

## Concerns raised (devil's advocate)

**C1 — The pre-registered PRIMARY (obfuscation_composite) is a null signal; am I fishing by pivoting to m1?**
- Classification: **ACCEPT (disclose), not a violation.** The composite is the pre-committed primary and it FAILS (cap-w PORT_t 1.37, rank-IC placebo p=0.716). m1 is not a post-hoc pivot: it is one of the 6 pre-registered base metrics (n_trials family=7, all reported). m1 is reported as the family's strongest with full n_trials accounting and null-max-t=2.804. The overall verdict is driven by the PRIMARY's failure; m1 is reported honestly as "real but sub-threshold," not promoted to a pass.

**C2 — Is m1 a Size proxy (the WT-005 trap that killed disclosure metadata)?**
- Classification: **REBUTTAL (evidence).** cor(m1, logSize)=0.071 (near-zero); partial rank-IC | logSize = -0.0140 vs raw -0.0155 (barely attenuated), partial Harvey-t -2.52. m1 survives Size control — matches the pilot's central finding (partial -0.313). NOT a size proxy.

**C3 — Is it a small-cap / illiquidity artifact (adv-tercile), or a look-ahead/timing artifact?**
- Classification: **PARTIAL.** (a) adv-tercile Harvey-t LO -1.99 / MID -1.02 / HI -1.48 — negative in ALL liquidity terciles, so not pure micro-liquidity. BUT (b) cap-tier weight shares show ~96% small-cap (OTHER), MEGA ~0.01 — the long-only top-25 CANNOT express the signal in benchmark tiers (cap-w trap). This is the binding structural limit, disclosed in verdict. (c) annual-lag12 stress Harvey-t -3.06 (stronger when stale) rules out timing/look-ahead dependence — the signal is a slow structural firm trait. PIT clean.

**C4 — Boilerplate / YoY-redundancy contaminating the signal?**
- Classification: **REBUTTAL.** m6 (YoY Jaccard) rank-IC Harvey-t -0.70 (weak), excluded from primary composite; leave-one-out shows m1 alone carries the composite (dropping m1 flips to +0.64). Boilerplate is not the driver.

**C5 — Convergence divergence: does Phase A even measure the pilot's signal?**
- Classification: **ACCEPT (disclose).** Objective composite vs LLM complexity = 0.329 (moderate), but the return-carrier (m1) has only 0.147 LLM convergence while the best LLM-matcher (m2 fog 0.275) is return-null. Objective and subjective "complexity" partly measure different things — flagged in validation. Phase B (LLM tone/uncertainty) remains a distinct axis, not settled by Phase A.

**C6 — Horizon confound (pilot 12M vs Phase A 1M)?**
- Classification: **PARTIAL.** Non-replication of the composite may be partly the 1M-monthly vs 12M-subjective design gap, not pure falsification. Disclosed as caveat. But the WT spec mandates 1M/monthly for the canonical gate, so the capital-grade conclusion (FAIL 2.95) stands on its own terms.

## Self-rationalization auto-check
No use of "미미/관행/보수적이면 OK/대부분 동일." Verdict is a hard FAIL on the authoritative canonical PORT_t; the "real but sub-threshold" language for m1 is backed by placebo p=0.008 + Size-control survival + persistence, and explicitly does NOT claim graduation.

## No-Silent-Override — Telegram boundary
The WT request.json and hash-frozen preregistration state `"telegram": "PROHIBITED for this WT"`. Q-Lead relayed a도훈 mandate (chart attachment on final telegram judgment). Reconciliation recorded here: **I generated the chart artifacts** (tg_chart_pack 3종 + sweep) but **did NOT call tg_agent_brief / send telegram** — the send is deferred to Q-Lead's judgment stage, which honors both the chart mandate and the WT's telegram prohibition. An agent message is not user consent to override a hash-frozen prereg constraint.

## Escalation triggers
- HIGH-severity concerns: 0 unresolved (all classified/disclosed).
- No AX axiom hard FAIL, no PIT C1 violation (annual-lag stress confirms PIT clean).
- No Q-Lead auto-escalate trigger fired.

## Verdict
FAIL_CANONICAL_HARD_GATE / SCREEN_TIER. Real Size-independent obfuscation signal in sentence-length, sub-threshold (2.35<2.95) + OOS decay + cap-w trap. Route: TEXT_READABILITY_FEATURE → OVERLAY_CANDIDATE / feature-preservation. Certificate NOT issued.
