# risk_challenge_note — WT-S20260504_001 (PCA_Latent_Hedge)

## Section: Method overview

**Method**: PCA Latent Hedge (Connor-Korajczyk 1986 + Bai-Ng 2002 statistical factor model).

**Pipeline executed**:
1. Residualization of stock returns from 6 known KR factors (MKT/SIZE/VALUE/MOM/QUALITY/LOWVOL) + 11 sector dummies (window 252d, IS-frozen at 2024-06-30) — **inherited from WT-S20260503_001 Round 1** (B_ref.parquet 440 × 5).
2. PCA K=5 covariance (IS-frozen).
3. Σ on STR_1715 18-active universe via Ledoit-Wolf shrinkage to constant correlation target. δ=0.0491, rbar=0.269, cond=40.95, PSD verified.
4. Tail risk on STR_1715 ACTUAL 268m monthly returns: VaR/ES + Hill α + EVT-GPD MLE + 8 stress periods + CDaR + state-conditional. MDD = -41.69% < hard cap -45% (PASS, margin 3.31pp).
5. Latent factor exposures: universe-level 268m diagnostic (Round 1 inherited) + portfolio-level 2026-05-01 point exposure (STR_1715 actual production weights × B_ref). Portfolio LFC = 0.036 (low), dominant PC3.
6. SHA-frozen lro_params (sha excluded from canonical JSON, recomputed and self-verify match=TRUE).
7. PIT C1/C2/C12/C14/C15 audit PASS + production directory write count = 0.

**debug_pass.json overall_pass = TRUE** (11-field gate including hard cap check).

---

## Section: Codex Critic Round (Round 1)

### Pending — codex_critic_response_risk.json arrival or timeout

**자율 분류 framework** per Codex Round Decision Protocol:

#### ACCEPT criteria (명백한 위반 → spec 수정 의무)
- PIT C1/C9/C11/C12 hard violation
- Σ PD violation (양정치성 깨짐) — N/A here (PSD verified, min_eig > 0)
- CVaR hard breach (MDD > -45%) — N/A here (margin 3.31pp)
- Hard Constraint 위반 — N/A here (sizing_only no weights produced)
- SHA self-verify mismatch — N/A here (verified TRUE)

#### PARTIAL criteria (부분 인정 + 보완)
- Universe-level LFC>40% epoch count interpretation (7/267 from Round 1 inherited)
- Anchor R² ~10⁻⁴ — orthogonality strong but anchor naming labels only (Round 1 inherited)
- VALUE/QUALITY style proxy (RAWDATA-derived, not factor_db composite)

#### REBUTTAL criteria (학술 + L-code + 정량 data 3축 근거)
- Σ method Ledoit-Wolf vs Gerber-RMT (Round 1 selection coherence justification)
- Tail risk EVT shape_xi negative (-0.85) — finite tail per Hosking-Wallis (1987) parameterization
- 268m latent diagnostic = universe proxy (not stock-level historical reconstruction) — out of risk research scope
- Portfolio 2026-05-01 LFC interpretation (low because well-diversified across frozen B_ref space, not because portfolio is risk-free)

### Auto-escalate triggers (Q-Lead notification)
- HIGH severity ≥ 5
- AX axiom hard FAIL ≥ 3
- PIT hard violation
- Σ PD violation
- SHA mismatch

### Self-detected limitations (defensive disclosure)
- L1: VALUE/QUALITY style factors are inverse-of-MOM/LOWVOL proxies on RAWDATA (not Factor DB composites). Style correlation directional indicator only.
- L2: STR_1715 universe is 20 nominal but 2 stocks have weight=0 → Σ on 18 active.
- L3: 5y daily window for Σ stability, 268m monthly for tail/MDD. Trade-off acknowledged.
- L4: 268m universe-level LFC is size-proxy diagnostic (Round 1 inheritance); stock-level historical reconstruction is out of risk research scope (would require alpha pipeline rerun).
- L5: B_ref was frozen at 2024-06-30 IS endpoint. OOS K modification count = 0. AX-002 enforced.
- L6: EVT-GPD shape_xi = -0.85 is unusually negative (suggests bounded tail). MLE may be sensitive to threshold choice (q90 used). Hill α = 2.25 (moderate) is the more interpretable tail metric.

---

## Section: AX-008 stance entry (Source 1 of 3, Round 1)

```json
{
  "source": "risk-research",
  "round": 1,
  "stance": "PASS_CONDITIONAL",
  "rationale": "Σ Ledoit-Wolf PSD verified cond 40.95, hard cap MDD -41.69% < -45%, SHA self-verify match, PIT all PASS, debug_pass overall=TRUE",
  "concerns_resolved": "self-disclosed limitations L1-L6",
  "final_after_codex": "pending_codex_response_or_waiver"
}
```

---

## Section: Waiver path (Codex timeout)

If `codex_critic_response_risk.json` does not arrive within timeout window (~20m / 1200s codex CLI ceiling), Round 1 invokes **waiver path** (LRO Round 1 검증된 패턴):

- `codex_critic_skip_waiver` for Codex Round (consistent with alpha section already declared in challenge_note.md)
- Risk-side **자체검증 quantitative proof**:
  - 11-field debug_pass.overall_pass = TRUE
  - Σ PSD verified min_eig > 0
  - SHA self-verify match
  - Hard cap MDD margin 3.31pp PASS
  - PIT C1/C2/C12/C14/C15 PASS
- Round 1 risk_package.json finalize as `codex_round_status = "round1_timeout_waiver_applied"`
- Q-Lead optimizer-research handoff with sigma_method, B_ref freeze, lro_params SHA, tail_risk hard cap PASS evidence

---

## Section: state_machine 정상 통과 plan

```
SPEC_APPROVED (done by Q-Lead)
  → ALPHA_DONE (done by Q-Lead waiver path)
  → RISK_DONE (this agent — sm_validated_advance call)
  → OPTIMIZER_DONE (next agent)
  → FORGE_DONE
  → JUDGE_PASSED
  → GOVERNOR_REJECTED
  → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE"
```

## Section: Production protection
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit
(production_directory_audit.json PASS).

---

# Pending — Codex Round response classification

(Will be appended on arrival of codex_critic_response_risk.json)
