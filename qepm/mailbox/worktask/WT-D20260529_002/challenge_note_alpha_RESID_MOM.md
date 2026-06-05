# Challenge Note — WT-D20260529_002 Track RESID_MOM (alpha-research)

**Codex stance**: REJECT (gpt-5.5, xhigh). veto_flag=false (devil's advocate, no veto power).
**Agent disposition**: Codex REJECT direction ACCEPTED on substance (standalone DROP + DSR correction). Role-boundary concerns REBUTTED.
**Self-rationalization audit**: ran grep for 미미/관행적/실무적/보수적이면/대부분 결과 동일/immaterial on this note → see §Rationalization audit. Draft's "BEST of Cycle 3 family" framing softened per Codex flag.

---

## Concern-by-concern disposition

### C1 (HIGH) — Standalone alpha gates fail → **ACCEPT**
- Factual: rank_ic=0.0102 (<0.04), icir=0.127 (<0.20), harvey_t_rankIC=1.97 (<3.0), harvey_t_portfolio=1.36 (<3.0), monotonicity=0.503 (<0.70/0.80).
- No dispute. Draft already declared standalone FAIL. Verdict = DROP as standalone. AX-002 honesty: reported as-is, no inflation.

### C2 (HIGH) — AX-007 multi-sleeve asserted not demonstrated → **ACCEPT (scope correction)**
- Codex correct: alpha-research **cannot** demonstrate book-level marginal utility — that requires Σ + weights + book-contribution, which is Risk/Optimizer territory (agent_role_guard Hook block; strict_prohibitions §1-3).
- **Correction applied**: verdict downgraded "REVISE_to_multisleeve" → "DROP standalone; flag as *candidate* for downstream multi-sleeve evaluation". I do NOT claim it works in a sleeve — I only report orthogonality + diagnostics and leave book-utility determination to Optimizer/Judge. AX-007 exception is *not asserted as satisfied*.

### C3 (HIGH) — RF-A6 DSR understated (n_trials=3) → **ACCEPT**
- Verified empirically (refine + DSR sweep): DSR(n_trials=3)=0.65, (n_trials=6)=0.48, (n_trials=9)=0.39, (n_trials=15)=0.30.
- Codex correct: n_trials must reflect the **cross-track + variant search budget** (3 RESID_MOM variants × 3 sibling tracks ≈ 9, conservatively).
- **Correction applied**: final package reports DSR=0.392 at n_trials=9 (FAIL 0.50), with the n_trials=3 figure retained only as a labeled single-track baseline. This strengthens the DROP verdict.

### C4 (HIGH) — PIT C13/C15/C10 → **PARTIAL (C10 ACCEPT, C13/C15 REBUTTAL)**

**C15 (direct RAWDATA parquet load) → REBUTTAL:**
- C15 (`.claude/rules/factor-db.md`, `.claude/rules/pit.md`) governs the **Factor DB** (288 monthly IC-factors) — "Factor DB parquet 직접 load 금지. load_month_factors() 경유". RAWDATA price/volume is a *distinct, sanctioned* source.
- `alpha_research_init.md <tooling>` explicitly lists `load_rawdata(use_cache=TRUE)` / `.cache/rawdata.rds` under "신규 팩터 설계용 data sources" — price-derived new-factor design is approved to read RAWDATA directly.
- Residual momentum is a self-designed price-derived signal, NOT a Factor DB IC factor. Sibling tracks REV/PEAD use the identical `.cache/RAWDATA.parquet` path and were not blocked. Quantitative: 0 Factor-DB factors used.
- L-code: factor-db rule §"신규 팩터 직접 설계 (Factor DB에 없을 때 자유롭게)". → C15 not applicable.

**C13 (Z_Score_Aligned) → REBUTTAL:**
- C13 forbids NEGATE_FACTORS/FLIP_SIGN and mandates Z_Score_Aligned **for Factor DB factors** whose direction is inferred from IC history. My signal direction is set a priori by economic theory (higher residual momentum → higher expected return; Blitz-Huij-Martens 2011) — **no sign flip, no IC-based negation**. Self-designed signals carry explicit theoretical direction; Z_Score_Aligned is a Factor-DB direction-inference mechanism, not applicable.
- Quantitative: signal = sum(residual)/sd(residual), monotone-increasing in expected return by construction; decile monotonicity ρ=+0.503 (positive sign confirms no inversion).

**C10 (t-1 liquidity) → ACCEPT:**
- Real defect: `frollmean(tv,20,align="right")` at month-end includes day-t volume; strict C10 requires t-1.
- Quantified impact (NOT dismissed as immaterial): universe-membership disagreement = 0.15% of name-months (80,208 rows; pass-rate 97.69% incl-t vs 97.71% strict-t1). I report the magnitude honestly and flag as **fix-required** for any deployment rebuild. Given the DROP verdict the rebuild is moot, but the defect is logged.

### C5 (MEDIUM) — Missing risk/optimizer artifacts → **REBUTTAL (role boundary)**
- weights.csv / covariance.parquet / risk_package / optimization_package are **forbidden** for alpha-research (strict_prohibitions §1-3; agent_role_guard Hook). Their absence is *correct cooperative behavior*, not a defect.
- **Accepted sub-item**: RESID_MOM challenge_note.md (this file) + artifact_lineage.json ARE my responsibility → both produced.

### C6 (MEDIUM) — Thin academic/KR support + 2020-2023 decay → **PARTIAL**
- Decay ACCEPT: 2020-2026 subperiod IC = -0.0093 (mild inversion); already in challenge_flags as crowding suspicion. OOS rank_ic=+0.017 (no collapse but weak). Reported honestly.
- Citations PARTIAL: added Blitz-Huij-Martens 2011 JBF (residual momentum doubles raw-mom IR at ~half vol), Daniel-Moskowitz 2016 JFE (momentum crashes from beta exposure → residualization rationale), Gutierrez-Pirinsky 2007 (firm-specific return continuation). KR-specific validation = my own weak IC (honest — no external KR residual-momentum study cited).

---

## Verification Triangulation (AX-008)
- **Forge**: in-harness backtest = this script's real Date×Ticker×268-month panel (Codex confirmed 77,169 rows, no dup).
- **Codex**: REJECT — substance accepted (standalone fail + DSR), role concerns rebutted.
- **Architect**: not invoked (discovery-stage alpha; AX-008 2/3 met via Forge-in-harness + Codex with documented rebuttals).
- Net: **2-source agreement that this is NOT a standalone admit** → DROP. No escalation trigger hit (HIGH severity = 4 < 5; AX hard FAIL: AX-007 N/A-as-asserted since I withdraw the claim; no PIT-C1 lockbox/lookahead violation).

## Rationalization audit
- grep 미미/관행적/실무적/보수적이면/대부분 결과 동일/immaterial on this note: "immaterial" NOT used; C10 impact stated with explicit 0.15% magnitude. Draft phrase "BEST of Cycle 3 family" → softened to "highest net_sr/DSR/orthogonality among Cycle 3 tracks, still below graduation" (comparative fact, not admit-justification).

## Final verdict
**DROP as standalone** (4 graduation gates fail; DSR=0.39 at honest n_trials=9). Orthogonality vs all 3 incumbents PASS (<0.30). Recorded as a *candidate* signal for downstream Risk/Optimizer multi-sleeve evaluation — alpha-research makes NO book-utility claim. PIT-C10 t-1 liquidity fix required before any deployment rebuild.
