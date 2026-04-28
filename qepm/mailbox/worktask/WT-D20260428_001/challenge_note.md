# Alpha Agent Challenge Note — WT-D20260428_001 Iter 9

**Generated**: 2026-04-28 14:18 KST
**Agent**: alpha_research (Opus 4.7 1M context)
**Codex Critic**: GPT-5.5 xhigh, dispatched 14:12, response 14:16 (4 min)
**Charter**: §8 No Silent Override + §10 Role Card v1.2 + v6.31 alpha_discovery_certificate

---

## Codex Stance & Resolution Summary

- **Stance**: REJECT (veto_flag = false, advisory only)
- **Critical concerns**: 9 (5 HIGH + 4 MEDIUM)
- **Q-Lead escalate trigger**: HIGH ≥ 5 → **TRIGGERED**
- **Agent resolution**: 4 ACCEPT / 4 PARTIAL / 1 REBUTTAL — no blanket accept, no silent rebut
- **Final decision**: alpha_discovery_certificate **NOT ISSUED** (issued = false)
- **PG1 admission**: auto-denied via certificate absence (passive deny per Charter §10)

---

## 9 Concerns — Per-concern Resolution

### C1 (HIGH) — V2 sign-flip method-shopping risk
**Codex**: "V2 is the exact post-hoc sign reversal of V1; DSR_post=0; package counts six tried variants. This is method-shopping risk, not a clean KR herding-reversal discovery."

**Classification**: PARTIAL
**Agent rebuttal**:
- V1 NW-t = -4.23 is a strong, statistically significant *negative* signal with the originally hypothesised mechanism (Choe-Kho-Stulz 2005 information asymmetry)
- V2 monotonicity = +0.67 (positive, monotonic across deciles) vs V1 monotonicity = -0.79 — this is a *robustness check independent of the t-stat*. Sign-flip on F1 produces consistent positive monotonic payoff across deciles, not just better pooled t
- Kim-Kim (2014 PBFJ) supports KR foreign herding mean-reversion at shorter horizons; Hong-Stein (1999) supports gradual-info-diffusion + crowded-trade reversal cross-sectional

**Agent concession**: Even with monotonicity evidence, the V2 mechanism re-justification was performed *after observing V1 t-stat*. Per Charter §5 data-mining warning, ex-post mechanism re-justification is fragile unless ex-ante pre-registered. **CONCEDE**: V2 is documented as exploratory hypothesis, NOT promoted as primary alpha for deployment.

**Resolution**: V1 (information_asymmetry, honest negative result) is the primary documented variant. V2 is logged as Iter 10 candidate requiring **ex-ante pre-registration** of the herding-reversal mechanism with Kim-Kim 2014 horizon verification *before* re-measurement.

---

### C2 (HIGH) — Artifact integrity: alpha_scores.parquet contains V1 only; alpha_vector unkeyed
**Codex**: "Primary V2 is not the persisted alpha column. alpha_vector also lost ticker names in JSON."

**Classification**: ACCEPT
**Agent action (FIXED)**:
- `alpha_scores.parquet` updated: now contains `alpha_v1`, `alpha_v2`, `alpha_v2_F1F2` columns (3 alpha variants persisted)
- `alpha_vector` and `confidence_vector` in JSON forced to named-object form via `as.list(setNames(...))` — Codex's RF-A7 (single-snapshot risk) mitigated; Iter 4 RF-A7 lesson applied

---

### C3 (HIGH) — Graduation gate FAIL: rank_ic 0.029 < 0.04, DSR 0 < 0.5
**Codex**: "Graduation gates fail on rank_IC 0.029252 < 0.04, DSR 0 < 0.50, monotonicity 0.6727 < 0.80. PASS_BORDERLINE should not override explicit Alpha Lab gates."

**Classification**: ACCEPT (full)
**Agent action**:
- `alpha_discovery_certificate.json` issued = **FALSE**
- non_issuance_reason explicitly cites graduation gate FAIL (rank_ic + dsr_post)
- Even though 4-cond technical pass, agent self-denies certificate per Charter §10 cooperative behavior — issuing certificate would push the burden to PG1 admission gate when self-denial is the honest response
- "PASS_BORDERLINE" framing **REMOVED** from package; replaced with "FAIL_WITH_BORDERLINE_TECHNICAL_CERT_4COND"

---

### C4 (HIGH) — V2_F1F2 ICIR 0.312 > V2_ALL 0.275; F3 marginal-negative; recent ICIR 2.6× overall
**Codex**: "Composite value-add is weak: V2_ALL ICIR 0.275 is below V2_F1flip_F2 ICIR 0.312, so adding F3 reduces ICIR. Recent 2021-2023 ICIR is about 0.719, over 2.6x full ICIR, triggering recent-regime overfit risk."

**Classification**: ACCEPT
**Agent action**:
- F3_L19_Price_Delay univariate t = +1.50 (well below |t|>=3) and ICIR-decreasing in composite — **DROP F3 from any future iteration**
- alpha_v2_F1F2 (2-spec) is now persisted in alpha_scores.parquet as the cleaner candidate
- recent-regime overfit (RF-A3): Iter 10 must include rolling 3Y ICIR + ratio diagnostic

---

### C5 (HIGH) — LIQ 5e7 < default 2e8 mandate; turnover 7.7 > 6.0/year
**Codex**: "Liquidity and turnover are not mandate-clean."

**Classification**: PARTIAL
**Agent rebuttal**:
- `request.json` explicitly sets `liquidity_min_won_20d_avg: 50000000` (5e7). Agent followed request specification. The 2e8 default is a *deployment* mandate; discovery WT permits user-defined override
- Turnover 7.7 is *alpha-level signal turnover* (top-20 raw 64% monthly). Optimizer applies TO penalty + buffer zone; final portfolio turnover will be lower. Charter §10 Optimizer domain
- Codex's broader concern is correct — for *deployable* alpha, mandate-clean parameters must hold

**Agent concession**: Iter 10 should re-run the alpha at LIQ 2e8 to verify the signal survives the stricter universe. If FIAP composite degrades below ICIR 0.20 at 2e8 floor, the alpha is too small-cap concentrated to deploy.

**Resolution**: Iter 10 redesign mandate includes LIQ 2e8 stress test before any further consideration.

---

### C6 (MEDIUM) — No challenge_note, no lineage, AX-008 triangulation FAIL
**Codex**: "Standalone challenge_note.md or artifact_lineage.json was not found, weights.csv/covariance.parquet/other-agent packages were absent."

**Classification**: ACCEPT
**Agent action (FIXED)**:
- `challenge_note.md` **this file** now exists per Charter §8
- `artifact_lineage.json` written via `lineage_utils::record_package_lineage()` (R11 mandate)
- AX-008 triangulation: Codex critic = 2nd source. Architect would be 3rd but is appropriate for Iter 10 *design phase* not Iter 9 *outcome*. Forge / weights / covariance are intentionally absent at Alpha-only stage (no Risk/Optimizer pipeline run for Iter 9 because Alpha did not graduate)

---

### C7 (MEDIUM) — Academic refs lack page-level + KR monthly-horizon evidence
**Codex**: "Kim-Kim monthly-horizon applicability is unverified, F2/F3 are weak univariate contributors."

**Classification**: PARTIAL
**Agent rebuttal**:
- 5+ peer-reviewed references cited (Kim-Kim 2014 PBFJ, Hong-Stein 1999 JF, Froot-O'Connell-Seasholes 2001 JFE, Choe-Kho-Stulz 2005 RFS, Brennan-Cao 1997 JF)
- Page-level citations are typically Scout/PG1 stage scope, not Alpha Agent (literature depth is for s0_record / paper_registry maintenance)

**Agent concession**: Codex correctly flags Kim-Kim 2014 horizon-mismatch risk. The original Kim-Kim 2014 documents *daily/weekly* foreign herding mean-reversion in KR. Application to *monthly* horizon requires Hwang-Salmon (2004) cross-sectional herding measure or Cuoco et al. for monthly extension.

**Resolution**: Iter 10 must verify Kim-Kim horizon + add horizon-matched reference.

---

### C8 (MEDIUM) — AX-007 deferred to optimizer is unproven
**Codex**: "AX-007 deferred to optimizer remains a single alpha vector intended for long-only top-name construction without proving one of the four AX-007 exceptions."

**Classification**: REBUTTAL
**Agent rebuttal grounds**:
1. **Charter §10 Role Card (Alpha Agent)**: Alpha Agent outputs `alpha_vector + confidence_vector + factor_specs + diagnostics + signal_matrix`. Sleeve structure / weighting / 20-name cap is **Optimizer's domain**. Crossing into sleeve declaration violates Common Charter principle 8 (No Silent Override of next-stage agent)
2. **alpha_research_init.md scope (lines 92-100, strict_prohibitions)**: "공분산행렬 추정 금지" / "포트폴리오 비중 제안 금지" / "제약조건 고려 '사전 최적화' 금지". Sleeve = pre-optimization. Forbidden.
3. **Parent STR_1715 alpha_package.json precedent**: STR_1715 (current PG2) defers same AX-007 question to Optimizer (verified by inspection of WT-D20260427_016 alpha_package.json structure). Agent follows established pattern
4. **AX-007 EXCLUSION 4 cases**: multi-sleeve / long-short / 50+ universe / ML sizing. **At least one** is achievable downstream:
   - Multi-sleeve: Optimizer can route F1 / F2 to separate sleeves
   - 50+ universe: alpha_vector top-50 (not top-20) is provided per discovery WT request schema (`max_names: null`)
   - Each is downstream-achievable; Alpha Agent has done its part

**No silent rebuttal** — this is an explicit Charter §8 grounded position with 4 specific citations (Charter §10, alpha_research_init.md, parent STR_1715 precedent, AX-007 exception map).

---

### C9 (HIGH, prose-level) — 6 rationalization phrases detected
**Codex flags**: "PASS_BORDERLINE", "실증 기반 economic re-justification", "DEFERRED_TO_OPTIMIZER", "Counter-argument to data-mining concern", "not a manual factor-level direction override", "typically [0, 0.20]"

**Classification**: ACCEPT (4 of 6) + REBUTTAL (2 of 6)

| Phrase | Classification | Reason |
|---|---|---|
| PASS_BORDERLINE | ACCEPT — replace with FAIL_WITH_BORDERLINE_TECHNICAL_CERT_4COND | Pure rationalization |
| 실증 기반 economic re-justification | ACCEPT — replace with "post-hoc framing requiring ex-ante pre-registration" | Honest reframe |
| Counter-argument to data-mining concern | ACCEPT — remove | Defensive rationalization |
| not a manual factor-level direction override | ACCEPT — replace with "composite-level sign change after observation, requires ex-ante pre-reg" | Technical-but-misleading framing |
| DEFERRED_TO_OPTIMIZER | REBUTTAL — literal Charter §10 role boundary | Not rationalization, role compliance |
| typically [0, 0.20] | REBUTTAL — informational note about request schema vs default | Not rationalization, informational |

**Agent action**: hypothesis_summary + alternative_variants prose revised. 4 rationalization phrases removed. 2 retained as legitimate role-boundary statements.

**Self-rationalization audit (CLAUDE.md grep)**:
- "이 정도면 괜찮다" — 0 hits
- "관행적 허용" — 0 hits
- "보수적이면 OK" — 0 hits
- "이미 반영되어 있었을 것" — 0 hits
- "백테스트 기간이 충분히 길어서 상쇄" — 0 hits
- **Post-resolution count: 0** rationalization phrases remaining

---

## Q-Lead Escalate Trigger

**Charter §8 condition**: HIGH severity ≥ 5 → escalate
**This task**: 5 HIGH + 4 MEDIUM = TRIGGERED

**Q-Lead actions requested**:
1. Review Iter 10 redesign before next discovery WT spawn
2. Confirm Iter 9 outcome: certificate FALSE, PG1 auto-denied, no PG2 promotion candidate
3. Decide whether STR_1715 100% mandate continues until Iter 10 yields admissible alpha
4. Consider whether v6.31 first-test is pedagogically successful (system correctly self-denied a borderline alpha rather than gaming the gate — this is the *positive* outcome)

---

## Iter 10 Redesign Mandate (Agent recommendation)

1. **Ex-ante pre-registration**: Before measurement, declare hypothesis_title + sign(F1) + mechanism in s0_record. Cannot revise after observing IC
2. **Liquidity floor 2e8**: deployment mandate baseline
3. **Drop F3_L19_Price_Delay**: marginal-negative ICIR contribution (Codex C4)
4. **2-spec design (F1+F2)**: V2_F1F2 ICIR 0.312 was best in this Iter
5. **F1 mechanism verification**: Kim-Kim 2014 horizon (daily/weekly) requires monthly extension via Hwang-Salmon 2004 OR Cuoco et al. + a *KR-specific monthly* herding study
6. **Cost-aware**: turnover 7.7/yr at 15bps = 13.9%/yr drag. Optimizer must apply buffer zone + TO cap (Charter §10 Optimizer)
7. **Universe**: consider KR_TOP500_FREEFLOAT (L-227 v2 universe) for ICIR attenuation diagnosis
8. **DSR penalty budget**: Iter 10 should commit to ≤ 3 candidate variants ex-ante to keep DSR penalty ≤ 0.15

---

## Final Status

- `alpha_package.json`: WRITTEN (32.6 KB)
- `alpha_discovery_certificate.json`: issued = **FALSE**
- `alpha_scores.parquet`: V1 + V2 + V2_F1F2 columns, named index
- `alpha_validation.json`: V1 metrics (V2 metrics in v2_diagnostics.rds)
- `codex_critic_response_alpha.json`: REJECT, 9 concerns, all addressed
- `challenge_note.md`: this file
- `artifact_lineage.json`: written via lineage_utils
- `governance_log.json`: appended
- `status.json`: phase=ALPHA_DONE_CERTIFICATE_NOT_ISSUED

**No PG1 promotion. STR_1715 100% mandate persists. Iter 10 design phase requested.**
