# Challenge Note — WT-D20260630_001 (Alpha: KR buyback event alpha)

Codex stance = **REVISE** (GPT-5.5, xhigh). 7 concerns (2 HIGH, 4 MEDIUM, 1 LOW). veto=null.
Per Charter §8 (No Silent Override) + AX-000 (don't declare dead-end prematurely), each concern classified ACCEPT / PARTIAL / REBUTTAL with evidence. Two HIGH concerns were **ACCEPTED and tested** before finalizing — they materially sharpened (but did not overturn) the verdict.

---

## C1_BENCHMARK_MISMATCH (HIGH) → **ACCEPT + tested**
**Concern**: FAIL is too benchmark-dependent. Basket spans KOSPI200 ∪ KOSDAQ150 but active is measured only vs KOSPI200-TR (a mega-cap-growth-led index, +1.31%/mo).
**Action taken**: Built EW-eligible-universe benchmark and re-measured at all horizons.
**Result (실측)**:
- EW-universe benchmark = **0.71%/mo** vs KOSPI200-TR **1.31%/mo** — confirms K200-TR is a much harder bar.
- 1M active: vs K200-TR −0.0049/mo (NWt −1.00); **vs EW-univ +0.0014/mo (NWt 0.56)** — sign flips positive but insignificant.
**Resolution**: Concern valid. The 1M FAIL vs K200-TR is partly a benchmark/style mismatch. But (a) the constitution mandates `benchmark_definition = KOSPI200_total_return` (request.json) — that is the binding benchmark for admission; (b) even vs the friendlier EW benchmark the 1M signal is insignificant (t=0.56). Verdict downgraded from blanket FAIL to **"FAIL at mandated 1M / KOSPI200-TR spec; effect exists vs EW at longer horizon (see C2)."**

## C2_HORIZON_MISMATCH (HIGH) → **ACCEPT + tested (most important)**
**Concern**: Ikenberry-Lakonishok-Vermaelen is a multi-YEAR post-announcement drift; 1M is the wrong horizon.
**Action taken**: Built 3M/6M/12M forward holding returns (non-overlapping basket, NW HAC lag = horizon+2), vs both benchmarks.
**Result (실측)** top-20 intensity basket active:
| horizon | vs K200-TR (NWt) | vs EW-univ (NWt) |
|---|---|---|
| 1M | −5.88%/yr (−1.00) | +1.66%/yr (0.56) |
| 3M | −5.20%/yr (−0.88) | +1.53%/yr (0.51) |
| 6M | −3.53%/yr (−0.66) | +3.03%/yr (1.37) |
| 12M | −1.37%/yr (−0.39) | **+4.84%/yr (2.17)** |
**Resolution**: Concern VALID and decisive. The Ikenberry drift signature IS present in KR — active return grows monotonically with horizon vs EW benchmark (1.66 → 4.84%/yr, t 0.56 → 2.17). This is real. BUT: (i) vs the **mandated KOSPI200-TR** it stays negative at every horizon; (ii) even the 12M EW result (t=2.17) is **below the HARD portfolio-alpha-t hurdle of 2.95**; (iii) it is recent-regime concentrated (see C6). → Hypothesis family is **screen-tier viable, not capital-graduation viable**.

## C3_DECISION_NOT_EXECUTION (MEDIUM) → **PARTIAL (acknowledged limitation, not testable now)**
**Concern**: Dataset = 취득결정 (decision to buy), not actual execution/completion; partial execution dilutes signal.
**Response**: Correct and noted as a data limitation. DART execution/completion (자기주식취득결과보고서) disclosures are not in the current clean parquet. If anything this biases the result toward UNDERSTATING the effect (decisions that don't execute add noise), so it does not threaten the FAIL verdict — a cleaner execution-confirmed sample could only help. Logged as a follow-up data enhancement, not a verdict-changer. No rationalization: I did not test it, so I claim no execution-confirmed result.

## C4_PIT_DENOMINATOR_SIZE_M (MEDIUM) → **PARTIAL / REBUTTAL**
**Concern**: Using announcement-month-end Size_M as intensity denominator; suggests lagged (M-1) market cap.
**Response**: Size_M is month-END market cap of month M; the announcement occurs DURING month M, so Size_M is known by EOM(M) when the portfolio is formed — no look-ahead (the forward return is M+1). This is PIT-safe (C2 not violated). However the concern that intensity rank carries near-zero signal (rank-IC 0.0076, t=0.37, non-monotonic terciles) is independent of the denominator — a lagged denominator would not rescue a signal whose ranking is noise. So the denominator is not the binding issue. REBUTTAL on PIT-safety; the intensity-noise finding stands regardless.

## C5_TEXT_FILTER_VALIDATION (MEDIUM) → **PARTIAL (audited the logic, sampled)**
**Concern**: Free-text aq_mth filter (retains 857/933) not auditable enough for decisive FAIL.
**Response**: Filter logic is conservative-INCLUSIVE for the FAIL direction: it retains anything containing 매수/취득/장내/직접 (857 events) and only excludes clear non-purchases (공개매수 tender 16, 장외/상환/전환 off-market 51, 무상 free-gift 4, 시간외 block 2). Misclassifying a few off-market as on-market would only ADD noise toward the null — it cannot manufacture a false FAIL. The active-vs-inactive raw spread (+0.30%/mo) shows the included set does carry the right-direction effect, so the filter is not silently dropping the signal. Concern does not threaten the FAIL.

## C6_RECENT_ONLY_SIGNAL (MEDIUM) → **ACCEPT (sharpened, reinforces caution)**
**Concern**: Effect is recent-concentrated; could be regime-alpha (Korean value-up policy) rather than overfit.
**Action taken**: Subperiod split of the 12M EW-active (the one significant cell):
- 2015-2018: −0.4%/yr  | 2019-2022: +4.6%/yr | 2023-2026: **+13.7%/yr**
**Resolution**: Confirms recent concentration. Whether "regime alpha" or "overfit", it fails the stability requirement and the short 2023+ window (n=30) cannot support capital graduation. Reinforces screen-tier classification. Pre-specified forward OOS would be required to claim a value-up regime alpha.

## C7_AX000_METHOD_BREADTH (LOW) → **ACCEPT (verdict wording revised)**
**Concern**: Only 3 forms tested; per AX-000 don't broadly declare dead-end.
**Resolution**: Verdict wording changed from blanket "FAIL" to **"FAIL at mandated 1M / KOSPI200-TR standalone spec; hypothesis family = screen-tier candidate (12M drift exists vs EW, t=2.17 < 2.95)."** This is a precise FAIL of the tested specification, not a claim that the buyback family is structurally impossible. Untested first-order variants (execution-confirmed, calendar-time overlapping with formal HAC, size/value-neutralized 12M, regime dummy) are logged as follow-ups.

---

## Self-rationalization audit
Grep of my rebuttals for prohibited rationalization tokens ("미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 영향 미미"): the only uses are in C4/C5 where I argue a flaw biases TOWARD the null (i.e., cannot create a false FAIL) — this is a directional-bias argument backed by the +0.30%/mo raw spread and the noise-only intensity rank-IC, not a hand-wave. The two HIGH concerns were not rationalized away — they were run as actual canonical-screen / multi-horizon measurements that changed the verdict's precision.

## Net effect on package
- Verdict stays **FAIL** for capital graduation (mandated spec), now with multi-benchmark + multi-horizon evidence.
- Added `benchmark_horizon_matrix` + `recommendation = screen-tier DPL_FEATURE / regime overlay`.
- No silent override: every Codex concern is recorded above with ACCEPT/PARTIAL/REBUTTAL + evidence.

## Codex round infra note
The mandated helper `02_Infrastructure/tools/debate_helpers/run_codex_qepm_critic.sh` and its role prompts are **archived** (`02_Infrastructure/hooks/_archive_codex_round_v8_2/`) and absent from the live path (OneDrive sync surfaced a transient copy at task start that produced a 0-byte output). Codex round was completed by invoking `codex exec --model gpt-5.5 -c reasoning.effort=xhigh` directly in foreground with a self-contained QEPM-alpha-critic prompt; raw response at `codex_critic_response_alpha.json(.raw)`. Flag for Q-Lead: codex-round infrastructure needs repair/restoration on this machine.
