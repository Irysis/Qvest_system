# Challenge Note — WT-D20260621_011 (Index Inclusion Frontrun Drift)
## Codex Critic Round resolution (Charter §8 No Silent Override)

**Codex stance**: REVISE (veto_flag=FALSE, gpt-5.5 xhigh). weakest_assumption: "effective-date-only membership + A_lag=1 validates only post-effective drift, cannot test the announcement-date frontrun mechanism."

This is correct and is exactly the central honest limitation the package already states. The frontrun window is **unobservable** in the available data; I tested only the PIT-valid post-effective drift and labeled it as such. Resolution per concern below.

### Self-rationalization auto-check
Grepped my rebuttals for ["미미","관행적","실무적","보수적이면 OK","대부분 결과 동일"]: the word "conservative/보수적" appears, but in the *technically correct* sense — argmax over an all-negative grid selects the **least-negative (best-case)** config, so a still-negative verdict is genuinely conservative (not a hand-wave). Not a rationalization; it is a directional property of selecting the max of a negative set.

---

### C1 [HIGH, RF-A7] alpha_scores.parquet single snapshot — **ACCEPT + FIXED**
Valid. Draft exported only the latest month (38 rows). Regenerated as full Date×Ticker×score panel: **254 months, 5,569 rows, 2005-2026** (`revise.R`). Schedule-reuse risk removed.

### C4 / C13 [MEDIUM, PIT-C13] "score>=0 always" inconsistent with negative alpha_vector — **ACCEPT + RETRACTED**
Valid catch. score = exp(−age/τ)·(1+λ·footprint). decay > 0 always, but (1+λ·footprint) goes negative when footprint < −1/λ (= −2 at λ=0.5) → **6.23% of scores are negative**. The "score≥0 always" claim was WRONG and is retracted in the final package. No NEGATE/FLIP operator was applied (C13's actual prohibition); the score remains direction-aligned by construction (higher = fresher/higher-footprint). Note: top-25 selection takes the *highest* scores, so negatives never enter the held book — the held set is unaffected, only the self-certification text was wrong.

### C5 [MEDIUM, RF-A4/A5] missing sector-neutral / liquidity / recent diagnostics — **ACCEPT + COMPUTED (all confirm negative)**
- Sector-neutral score (within-month sector-demean): pt_nw = **−1.079** (still negative → not a sector-composition artifact).
- Held top-25 illiquid(<2e8) fraction = **0.024** (≪0.5 → RF-A5 PASS, not illiquidity-driven).
- Recent-36m pt_nw = **−1.381** (worse than full −0.885 → RF-A3 not triggered; consistent with arbitrage over time).
- Decile monotonicity Spearman = **−0.248** (negative monotonicity → top-concentration inversion).
rank-IC / ICIR genuinely ill-defined for a binary event sleeve whose cross-sectional score is mostly structural-zero; the authoritative diagnostic per measurement-graduation §2 is portfolio-alpha t + decile term-structure, both reported.

### C2 [HIGH, AX-008] no triangulation / lineage artifacts — **PARTIAL (lineage ACCEPT; full-triangulation REBUTTAL)**
- artifact_lineage.json: ACCEPT — added (`finalize.R` → record_package_lineage).
- AX-008 full triangulation (Forge + Codex + Architect, 2/3 PASS): **REBUTTAL**. AX-008 is a *graduation/admission* gate (`.claude/rules/axioms.md`: "process … Verification Triangulation"). This is an **alpha-stage NEGATIVE finding not seeking admission** — risk_package/optimization_package/weights/covariance legitimately do not exist (producing them would violate the agent_role_guard alpha-only mandate). The Codex critic round IS the triangulation source appropriate to this stage and it completed. No graduation is pursued, so Forge/Architect are not invoked. Grounds: axioms.md AX-008 scope + alpha-only role card (alpha_research_init.md <strict_prohibitions>).

### C3 [MEDIUM, RF-A6] selection_objective=subperiod_stability but code argmax(pt) — **REBUTTAL**
The grid argmax(portfolio_alpha_t) was used **only to pick the least-negative PIT-valid config** for the headline verdict. Since **0/72 PIT-valid configs are positive** (max pt −0.282, min −1.089), choosing the maximum makes the negative verdict strictly conservative — the best-case config still fails every gate. DSR/multiple-testing inflation applies to *inflated positive* claims; for a uniformly-negative grid it can only weaken a (non-existent) positive, so it does not threaten a negative verdict. selection_type honestly labeled "sweep" (144 explicit grid). Quantitative grounds: `is_grid.csv` (all A_lag=1 rows negative). Academic grounds: Bailey-López de Prado 2014 DSR is a deflation of *favorable* selection — not relevant to a rejected hypothesis.

### C15 [FAIL→REBUTTAL] direct RAWDATA/universe parquet reads — **REBUTTAL (spec-granted carve-out)**
The C29 spec `pit_notes` explicitly grants this: *"본 알파는 Factor DB 팩터 미사용(RAWDATA 가격 + 멤버십 패널 직접). RAWDATA/membership parquet는 C15 carve-out(가격·멤버십 raw, factor DB 아님) — load_month_factors 불요."* RAWDATA price/Size/Vol and the K200/KQ150 membership panel are raw market data, not Factor DB factors, so `load_month_factors()` does not apply (it would have nothing to serve). Documented in artifact_lineage. L-code reference for raw-price carve-out: pit.md C15 covers *Factor DB parquet* specifically.

### C6 [LOW, AX-007] single long-only top-25 sleeve doesn't satisfy AX-007 exceptions — **ACCEPTED AS LABELED**
Codex itself notes "acceptable for a negative finding, not for a viable alpha claim." Agreed. The package's verdict is NEGATIVE_VALIDATED with screen_route=NONE — no viable-alpha claim is made, so the AX-007 single-sleeve concern is not load-bearing. The buy-side framing was the *rationale* for testing (a legitimate escape attempt), and the test result is that it fails regardless.

---

## Net effect of REVISE
All concerns strengthen or are neutral to the verdict. Sector-neutral, recent-36m, decile monotonicity, and placebo all independently confirm: **KR index-inclusion drift is negative under PIT.** No concern reverses or weakens the NEGATIVE_VALIDATED conclusion. Verdict finalized unchanged; diagnostics, alpha_scores panel, lineage, and C13 text corrected.

## Q-Lead escalation check
HIGH-severity concerns = 2 (C1, C2) < 5 threshold; AX hard-FAIL = 0 (AX-007 N/A to negative); no PIT-C1 lookahead violation found; Codex stance=REVISE (not REJECT). → **No mandatory Q-Lead escalation.** (Informational surface to Q-Lead in completion report.)
