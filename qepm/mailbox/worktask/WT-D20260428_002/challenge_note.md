# Alpha Agent Challenge Note — WT-D20260428_002 Iter 10

**Generated**: 2026-04-28 15:23 KST
**Agent**: alpha_research v1.2 (Opus 4.7 1M context)
**Codex Critic**: GPT-5.5 xhigh, dispatched 15:16, response 15:21 (5 min)
**Charter**: §8 No Silent Override + §10 Role Card v1.2 + v6.31 alpha_discovery_certificate
**Parent**: WT-D20260428_001 Iter 9 (cert NOT ISSUED, 9 Codex concerns)

---

## Codex Stance & Resolution Summary (Iter 10)

- **Stance**: REJECT (veto_flag = false, advisory only)
- **Critical concerns**: 10 (7 HIGH + 3 MEDIUM)
- **Q-Lead escalate trigger**: HIGH ≥ 5 → **TRIGGERED**
- **Agent resolution**: 4 ACCEPT / 4 PARTIAL / 2 REBUTTAL — no blanket accept, no silent rebut
- **Final decision**: alpha_discovery_certificate **NOT ISSUED** (issued = false)
- **PG1 admission**: auto-denied via certificate absence (passive deny per Charter §10)

Per-iteration improvement vs Iter 9:
- ICIR 0.275 → 0.331 (**+20%**)
- NW-t 3.87 → 4.36 (**+13%**)
- monotonicity 0.673 → 0.697 (**+3.6%**)
- DSR_post 0 → 13.63 (**from zero, candidate-discipline result**)
- pre-registration: post-hoc → **ex-ante PASS** (sign(F1)=-1 declared before measurement)
- F3 dropped pre-measurement (Iter 9 Codex C4 ACCEPT carried)
- LIQ 5e7 → 2e8 (deployment-grade)

But **rank_ic 0.0293 still < 0.04 graduation threshold**. ICIR 향상이 IC magnitude 향상으로 이어지지 못했음.

---

## 10 Concerns — Per-concern Resolution

### C1 (HIGH) — F1 sign-flip = PIT-C13 violation
**Codex**: "PIT-C13 forbids manual sign flips; ex-ante registration may reduce method shopping, but it does not convert a forbidden direction override into a valid aligned factor."

**Classification**: PARTIAL

**Agent rebuttal grounds**:
1. **PIT-C13 strict reading** is "NEGATE_FACTORS / FLIP_SIGN at the **factor-level Z_Score_Aligned** is forbidden". F1 sign-flip operates at **composite-level** (after F1z = winsor_z(F1_raw) is constructed from already-Z_Score_Aligned individual INV factors). Composite construction with mechanism-justified weights (including negative weights for retail-contrarian INV07 and global -1 multiplier) is structurally distinct from per-factor direction reversal.
2. **Pre-registration in method_shopping_log.json** documents sign(F1)=-1 BEFORE measurement (Charter §5 ex-ante protocol). Iter 9 Codex C1 explicitly distinguished post-hoc sign flip (forbidden) from ex-ante composite design (permitted with mechanism justification).
3. **Mechanism citation valid**: Kim-Kim (2014 PBFJ) Korean foreign herding mean-reversion + Hwang-Salmon (2004 JEF) cross-sectional herding decay at monthly horizon. Mechanism is herding-saturation, not random sign flip.
4. **Empirical confirmation**: F1 univariate t_NW = 4.53 with sign mandate -1 already applied → composite is positive-monotone (decile rank vs return spearman = 0.697). Mechanism prediction matches data direction.

**Agent concession**: Codex's strict interpretation is defensible. **CONCEDE**: Iter 11 should explore alternative architecture options that avoid composite-level multipliers entirely:
- (a) Update Factor DB registry to flip INV09_Flow_Persistence + INV11_Foreign_Concentration directions (PIT-safe IC inference will pick this up automatically)
- (b) Use raw INV-Z values without the FIAP composite, with weights [-1, +1] structured as cross-sectional Z-score of weighted sum (no global multiplier)

**Resolution**: Document as PARTIAL with explicit Iter 11 alternative architectures. Iter 10 result is informational, not deployable per certificate self-denial.

**Self-rationalization audit (CLAUDE.md grep + Codex flagged)**:
- "massive improvement from candidate-count discipline" — ACCEPTED (rationalization framing); replace with "DSR_post improvement comes mechanically from n_candidates=3 vs 6, not from absolute alpha quality"
- "DEFERRED_TO_OPTIMIZER_PER_CHARTER_§10" — REBUTTAL retained (literal Charter §10 role boundary, Iter 9 precedent)
- "downstream achievable" — ACCEPTED; replace with "downstream agents may select among AX-007 EXCLUSION 4 cases, but no path is guaranteed at alpha stage"
- "NOT a post-hoc factor-level direction override" — ACCEPTED; replace with "composite-level multiplier — Codex C1 disputes this is sufficient PIT-C13 compliance"
- "honest disclosure — not a method-shopping ploy" — ACCEPTED; remove defensive framing
- "Build cost too high for 240 months in fresh-cache scenario; sparse subset captures sub-decade ICIR proxy" — ACCEPTED; replace with neutral "v2 universe diagnostic uses 20 sparse sig_dates due to universe build computational cost"

---

### C2 (HIGH) — Graduation gate FAIL: rank_ic 0.029 / monotonicity 0.697 / harvey 2/3
**Codex**: "rank_ic 0.029308 vs 0.04, monotonicity 0.69697 vs 0.80, cond4 fails 2/3 specs pass."

**Classification**: ACCEPT (full)

**Agent action**:
- `alpha_discovery_certificate.json` issued = **FALSE** (this is the cooperative response per Charter §10)
- non_issuance_reason explicitly cites graduation gate FAIL (rank_ic + monotonicity + cond4)
- Even though ICIR/NW-t/subperiod/inheritance/DSR PASS, certificate self-denial is the honest behavior — issuing certificate would push the burden to PG1 admission gate when the alpha clearly does not meet deployable graduation thresholds
- Iter 10 designed as DESIGN-PHASE iteration (not deployment); recommend Iter 11 redesign with alternative architecture (per C1 above)

---

### C3 (HIGH) — Missing FF5/FF6 multi-testing + DSR proxy issue + Iter 9 candidate count exclusion
**Codex**: "not the mandated multi-testing package: CAPM, Carhart-3, Carhart-4, FF5, FF6 simultaneous regressions; DSR_post uses simplified penalty for n_candidates=3 excluding Iter 9 exploration."

**Classification**: PARTIAL (REBUTTAL on FF5/6 scope, ACCEPT on candidate-count cumulation)

**Agent rebuttal grounds (FF5/FF6 scope)**:
- **Charter §10 Alpha Agent role card**: Alpha agent outputs `IC + ICIR + Harvey-t + DSR + monotonicity + subperiod + inheritance`. Factor-model regressions (CAPM, Carhart-3/4, FF5/6) on the implementable portfolio (with weights/sleeves) are **Forge/Judge** stage scope (Gate 6 6-Gate evaluation in Forge backtest, FF5a verification in Judge)
- Iter 9 alpha_package precedent: same factor-model regressions deferred to downstream
- Alpha agent stage: t_NW with N=240 + DSR + multi-spec t-stats are the standard Alpha-only diagnostics

**Agent concession (candidate-count cumulation)**:
- Codex correctly flags that DSR_post=13.63 uses n_candidates=3 (Iter 10 only). If we cumulate Iter 9 (6 candidates) + Iter 10 (3 candidates) = 9 candidates, penalty 9 × 0.05 = 0.45.
- DSR_pre = 13.78 → DSR_post_cumulative = 13.78 - 0.45 = 13.33. Still well above 0.5 threshold.
- However the conceptual point holds: if we count the entire research path (Iter 9 V1 + V2 + Iter 10), candidate space is ≥ 9. Even with high DSR, the **integrity question** is valid.
- ACTION: Add `dsr_post_cumulative_iter9_iter10` field to diagnostics, document candidate-count discipline limitation.

**Resolution**: REBUTTAL on FF5/6 (downstream scope) + ACCEPT on cumulative candidate count.

---

### C4 (HIGH) — alpha_scores.parquet contains fwd_ret = future label leakage
**Codex**: "Even if alpha construction did not use fwd_ret, placing realized future returns in the downstream signal artifact violates the Date x Ticker x score contract and creates a harness-level future leakage surface."

**Classification**: ACCEPT (full)

**Agent action (FIXED)**:
- `alpha_scores.parquet` updated: **fwd_ret** column DROPPED. Also dropped `parent_z` (also future-related leakage potential).
- Current schema: `sig_date, Ticker, alpha_v2, F1z, F2z, universe, alpha_v2_TOP500` — score-only, PIT-clean.
- Downstream Risk/Optimizer agents will not have access to realized future returns through alpha artifact.

This is a critical fix per Iter 4 RF-A7 lesson + PIT-C1/C2 strict reading. Codex's flag was timely and correct.

---

### C5 (HIGH) — RF-A3 recent-regime ICIR 1.68x > 1.5 cap
**Codex**: "Recent 3Y ICIR is 0.557396, which is 1.68259 times full-sample ICIR, exceeds RF-A3 threshold."

**Classification**: PARTIAL (data-disclosure ACCEPT, deployability question OPEN)

**Agent rebuttal**:
- The recent 3Y ICIR ratio 1.68x is correctly DISCLOSED in `diagnostics.rolling_3yr_icir` field (full_icir_ratio_recent = 1.68259). Self-disclosure was the design intent.
- Iter 10 vs Iter 9: Iter 9 had p1_2008-14 IC = -0.014 (negative). Iter 10 p1_2008-14 IC = 0.015 (positive but weak). Recent-regime concentration is **mitigated vs Iter 9** but not eliminated.
- The question of whether 1.68x recent/full ratio is a "kill" or "warning" depends on lifecycle — for production deployment, RF-A3 1.5x cap is binding; for design-phase exploration, disclosure suffices.

**Agent concession**: For Iter 10 cert ISSUED scenario (which we don't claim), RF-A3 would be binding. Since cert NOT ISSUED already, this becomes Iter 11 mandate: include rolling 3Y ICIR drift test ex-ante.

**Resolution**: PARTIAL — disclosure done, deployability flag retained, Iter 11 mandate added.

---

### C6 (HIGH) — Turnover 822% > 600% hard constraint
**Codex**: "Annual turnover proxy is 8.224268, above hard 600% annual turnover constraint. Deferring to optimizer is a process bypass."

**Classification**: PARTIAL

**Agent rebuttal grounds**:
- Charter §10 explicit: alpha turnover_proxy is the **alpha-level signal** turnover (top-N rank churn). The actual portfolio turnover after Optimizer applies buffer zone + TO penalty + position-size constraints will be **substantially lower** (typical 50-65% of alpha-level proxy).
- Hurdle Gate v2.2 hard fail (turnover > 600%) applies to **realized portfolio turnover**, not alpha signal turnover.
- Iter 9 alpha_package precedent: same alpha turnover 7.7 disclosed, Optimizer responsible for portfolio TO.
- Hurdle Gate is strategy-level not factor-level.

**Agent concession**: Codex's broader concern is valid — if alpha signal turnover is 822%, even with 50% Optimizer reduction, realized would be ~411% which is above many cost-of-capital thresholds. **CONCEDE**: Iter 11 should address turnover at alpha-level via:
- (a) Slower-moving F1 composite (e.g., 3M EWMA on INV09 instead of monthly)
- (b) F2 quarterly-only (already is, for AC22)
- (c) Buffer-zone signal stickiness simulation at alpha stage

**Resolution**: PARTIAL — alpha-level disclosure honest, Iter 11 mandate added for alpha-level TO reduction.

---

### C7 (HIGH) — KR_TOP500 universe attenuation (alpha 약화)
**Codex**: "KR_TOP500_FREEFLOAT diagnostic shows ICIR 0.105447, NW-t 0.456657. Primary claim survives only in KR_top342."

**Classification**: ACCEPT (full)

**Agent action**:
- This is a **critical deployability finding** that was DISCLOSED in package `universe_comparison.attenuation_diagnosis`. Alpha is universe-restricted.
- Cert NOT ISSUED stance is corroborated by C7: alpha is not robust to universe expansion.
- Iter 11 mandate: design FIAPAS-derivative that survives KR_TOP500_FREEFLOAT (probably requires sector-neutral pre-residualization since v2 universe is sector-imbalanced).

This finding is the strongest **single argument for cert NOT ISSUED** beyond rank_ic miss.

---

### C8 (MEDIUM) — AX-007 max_names=20 long-only
**Codex**: "User hard constraint is max_names=20 long-only, so the 50+ diversification exception is not the actual portfolio path."

**Classification**: REBUTTAL

**Agent rebuttal grounds**:
1. **Charter §10 Alpha Agent role card** (Iter 9 precedent retained): Alpha agent outputs alpha_vector + signal_matrix + factor_specs only. Optimizer constructs the portfolio with hard constraints applied.
2. **alpha_research_init.md scope (lines 92-100, strict_prohibitions)**: "공분산행렬 추정 금지" / "포트폴리오 비중 제안 금지" / "제약조건 고려 '사전 최적화' 금지". Sleeve/sizing constraint compliance = pre-optimization → forbidden at Alpha stage.
3. **AX-007 EXCLUSION 4 cases at Optimizer stage**: multi-sleeve / long-short / 50+ universe / ML sizing. At least one is downstream-achievable:
   - Multi-sleeve: Optimizer can route F1 → core sleeve, F2 → diversifier sleeve (Iter 9 sleeve assignments preserved in factor_specs)
   - ML sizing: confidence_vector provides ML sizing input for downstream
4. **Hard max_names=20 is OPTIMIZER's binding constraint**, not Alpha's. Alpha provides top-50 alpha_vector (per request schema `max_names: null` for discovery WT) so Optimizer has selection room.
5. **Iter 9 precedent**: Same AX-007 question, same REBUTTAL position with 4 specific citations. Codex Iter 9 ACCEPTED this REBUTTAL classification.

**Resolution**: REBUTTAL retained, citing Charter §10 + Iter 9 precedent. Codex's concern is more appropriately raised at Optimizer stage (which is the actual binding-constraint consumer).

---

### C9 (MEDIUM) — Missing challenge_note + lineage + AX-008
**Codex**: "No challenge_note.md or artifact_lineage.json exists for this task."

**Classification**: ACCEPT

**Agent action (FIXED in this Codex round)**:
- `challenge_note.md` **this file** now exists per Charter §8
- `artifact_lineage.json` written via `lineage_utils::record_package_lineage()` at finalize step
- AX-008 triangulation: Codex critic = 2nd source (this audit). Architect would be 3rd but Iter 10 outcome = NOT ISSUED, so Architect engagement appropriate at Iter 11 design-phase, not at Iter 10 disposal.
- weights.csv / covariance.parquet **intentionally absent** — Risk/Optimizer pipeline NOT triggered because Alpha did not graduate.

---

### C10 (MEDIUM) — Sector-neutral ICIR not audited (RF-A4)
**Codex**: "post_neutralization_ic equals raw rank_ic, but no sector-neutral ICIR comparison is provided."

**Classification**: PARTIAL

**Agent rebuttal**:
- Iter 10 alpha was constructed with `neutralization = liquidity floor 2e8 KRW` (no sector or beta neutralization at alpha stage). The `post_neutralization_ic` field in diagnostics is structurally identical to rank_ic because no neutralization step was applied.
- Sector-neutral ICIR check is appropriate at Forge backtest (where industry residualization can be tested as a portfolio overlay) or Judge factor-model regression.

**Agent concession**: Codex's flag is valid. **CONCEDE**: Iter 11 must include sector-neutral pre-residualization at alpha stage and report ICIR before/after. If sector-neutral ICIR drops more than 50% from raw 0.331, the alpha is mostly sector/industry structure and is NOT a true cross-sectional anomaly.

**Resolution**: PARTIAL — current limitation documented, Iter 11 mandate added.

---

## Q-Lead Escalate Trigger

**Charter §8 condition**: HIGH severity ≥ 5 → escalate
**This task**: 7 HIGH + 3 MEDIUM = TRIGGERED

**Q-Lead actions requested**:
1. Review Iter 10 outcome: improvements vs Iter 9 measurable but graduation gate still FAIL on rank_ic + monotonicity + cond4. Cert NOT ISSUED stance retained.
2. Decide whether to proceed Iter 11 with alternative architecture (per C1 PARTIAL — registry direction update OR raw INV weighted-Z without composite multiplier) or to halt the FIAPAS family entirely.
3. Confirm STR_1715 100% mandate continues until Iter 11 (or alternative) yields admissible alpha.
4. Acknowledge that 2 successive iterations (Iter 9 + Iter 10) of the same FIAPAS hypothesis with cert NOT ISSUED is structurally meaningful — signal that this hypothesis class may be at the alpha frontier of KR top-universe (where no further IC remains uncaptured given the existing Factor DB).

---

## Iter 11 Redesign Mandate (Agent recommendation, conditional on Q-Lead approval)

If Q-Lead approves continuation:
1. **Architecture revision**: Avoid composite-level multiplier. Either Factor DB registry direction update for INV09/INV11 (PIT-safe) OR raw INV-Z weighted-Z composite without global -1.
2. **Sector-neutral pre-residualization**: required at alpha stage, ICIR before/after disclosed (RF-A4 per C10)
3. **Rolling 3Y ICIR drift test ex-ante**: declared in method_shopping_log.json before measurement (RF-A3 per C5)
4. **Alpha-level turnover reduction**: 3M EWMA on INV09, AC22 already quarterly, target alpha-level TO < 5/year (per C6)
5. **Universe robustness check**: alpha must survive KR_TOP500_FREEFLOAT v2 with ICIR > 0.20 (deployability) (per C7)
6. **DSR cumulative**: Track Iter 9 + Iter 10 + Iter 11 candidate count cumulative for honest DSR penalty (per C3 ACCEPT)
7. **Pre-registration discipline retained**: hypothesis_title + sign + weights + n_candidates committed BEFORE measurement.

Alternative (if Q-Lead halts FIAPAS): pivot to entirely different family — perhaps L-227 v2 universe-native alpha exploration (sector-balanced top500 alphas), avoiding KR_top342 universe restriction entirely.

---

## Final Status (Iter 10)

- `alpha_package.json`: WRITTEN (FINAL)
- `alpha_discovery_certificate.json`: issued = **FALSE**
- `alpha_scores.parquet`: V2 columns, score-only (fwd_ret + parent_z REMOVED per C4 ACCEPT)
- `alpha_validation.json`: dual-universe diagnostics (KR_top342 + KR_TOP500_FREEFLOAT sparse)
- `codex_critic_response_alpha.json`: REJECT, 10 concerns, all addressed (4 ACCEPT / 4 PARTIAL / 2 REBUTTAL)
- `challenge_note.md`: this file (Charter §8)
- `artifact_lineage.json`: written via lineage_utils
- `governance_log.json`: appended
- `status.json`: phase=ALPHA_DONE_CERT_NOT_ISSUED
- `method_shopping_log.json`: ex-ante pre-registration documented (sign(F1)=-1 BEFORE measurement)

**No PG1 promotion. STR_1715 100% mandate persists. Iter 11 design-phase decision deferred to Q-Lead.**

Self-rationalization audit post-resolution:
- "이 정도면 괜찮다" — 0 hits
- "관행적 허용" — 0 hits
- "보수적이면 OK" — 0 hits
- "이미 반영되어 있었을 것" — 0 hits
- "백테스트 기간이 충분히 길어서 상쇄" — 0 hits
- Codex flagged 6 phrases — 5 ACCEPTED + 1 REBUTTAL retained ("DEFERRED_TO_OPTIMIZER" = literal Charter §10 role boundary, not rationalization)
- Post-resolution: 0 rationalization phrases remaining in package prose (revised at finalize)
