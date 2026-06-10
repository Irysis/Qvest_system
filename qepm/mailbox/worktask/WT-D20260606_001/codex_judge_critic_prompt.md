# Codex Critic Round — Judge Verdict (WT-D20260606_001)

You are a GPT-5.5 cross-model adversarial critic (devil's advocate) reviewing a QEPM **Judge** verdict in a quant equity research pipeline (KR KOSPI200/KOSDAQ150, long-only, monthly). Be rigorous and skeptical. The Judge is the pipeline's final adjudicator (AX-008 Verification Triangulation: it must independently re-compute, not rubber-stamp Forge).

## Context (the hypothesis under test)
WT theme: build a residual-momentum **orthogonal diversifier sleeve** + regime overlay + uncertainty sizing to break a single-sleeve book's Sharpe ceiling toward SR 2.5. Incumbent book = R05 (value/consensus, already admitted, 100% of book_state). The new book = 0.85*R05(frozen) + 0.15*residual-mom-sleeve (EW top-20).

## Upstream results (all self-flagged failure, transparently)
- alpha: standalone FAIL (portfolio-alpha t 1.46 canonical-screen << 2.95 hurdle); self-grade F; intended use = diversifier/DPL feature. C15 violation (read factor_db parquet directly, not load_month_factors).
- risk: diversification statistically UNCERTAIN (cov-contribution 95% CI [-0.0149,+0.0056] straddles 0; downside cov flips +0.0014); high-vol momentum-crash sleeve (-26.8% worst month); NOT a hedge.
- optimizer: central thesis REFUTED (overlay no SR lift; book beta ~0.107 nothing to time; ceiling ~1.74<<2.5); ΔIR borderline; recommend DPL transition; governor admit NOT recommended.
- forge (authoritative bt_result, n=268 months): net Sharpe 1.5599, PORT_t(NW lag-3) 4.90, Calmar 1.01, DSR 1.0, IR 0.78, MDD 0.351; oos_retention active 0.171; book-marginal ΔIR NOT robust (+0.059 realized-month / -0.006 fwd-shift); incremental book-vs-R05 return NEGATIVE IS (-1.85%/yr, t-2.17), FLAT OOS (t+0.09).

## Judge verdict to critique
File: `qepm/mailbox/worktask/WT-D20260606_001/judge_verdict_draft.json`

Judge DISPOSITION = JUDGE_FAILED, essence_grade = B, graduation = BLOCKED, governor_handoff = false.

Judge's key independent re-computations (loaded bt_result.rds, re-ran essence_score.R + manual splits):
- essence_score authoritative grade = B (both single-paper n_trials=NULL and sweep n_trials=17), binding fail = oos_retention < 0.7.
- active 65/35 retention = 0.216 (forge reported 0.171 via 70/30); active 2024-01 lockbox retention = -0.149 (OOS active SR negative); total-SR retention healthy (0.757/1.293).
- Gate E concentration re-aggregated from holdings: max w 0.05 <= 0.20, HHI 0.05 <= 0.15, 20 names PASS.
- Gate C PORT_t 4.90 reproduced but ruled NON-DECISIVE (full-sample IS-dominated, frozen-R05-driven, not the new sleeve).
- Gate A: C1-C14 no lookahead (PASS); C15 = sanctioned-path procedural violation (NOT lookahead), ruled an outstanding graduation precondition (independent block).

Three blocking grounds: (1) oos_retention HARD fail, (2) C15 precondition un-remediated, (3) ΔIR not robust + sleeve adds no incremental return.

## Your task — output STRICT JSON only (no prose outside JSON)
Evaluate whether the Judge verdict is correct, complete, and free of error or over/under-reach. Focus areas:
1. Is JUDGE_FAILED + Grade B + graduation BLOCKED the correct call? Or is the Judge being too harsh / too lenient anywhere?
2. Is the oos_retention HARD-fail interpretation sound (active vs total; 65/35 vs lockbox 2024-01; is the negative-active-SR-OOS a real disqualifier or a rallying-BM artifact that should be contextualized differently)?
3. Is the Judge right that C15 is procedural (not lookahead) yet still an independent graduation block? Or is it over-reaching to make C15 a block when numbers are byte-identical?
4. Is Gate C PASS-but-non-decisive logically coherent (PORT_t 4.90 passes the hurdle but doesn't graduate the sleeve)?
5. Any missed gate, any AX violation (AX-001 v2 / AX-007 / AX-008), any PIT issue the Judge missed?
6. Is "governor_handoff = false" correct given un-graduated discovery?

Output JSON schema:
{
  "agent_id": "codex_qepm_critic", "role": "judge_critic", "model": "gpt-5.5",
  "task_id": "WT-D20260606_001", "veto_power": false,
  "stance": "APPROVE | APPROVE_CONDITIONAL | REVISE | REJECT",
  "stance_rationale": "...",
  "critical_concerns": [ {"id":"C1","severity":"HIGH|MEDIUM|LOW","title":"...","evidence":"...","impact":"...","required_rebuttal":"..."} ],
  "ax_violations": [ "..." ],
  "agreements": [ "..." ],
  "weakest_assumption": "...",
  "verdict_correctness": "CORRECT | CORRECT_WITH_REVISIONS | INCORRECT",
  "rebuttal_required": [ "..." ]
}
