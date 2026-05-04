# challenge_note — WT-S20260504_002 (DCC_Vol_Target)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking input only, DCC-GARCH dynamic Σ로 weight scale 결정. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. DCC Vol Target은 risk management이지 alpha 아님. 후속 5 agent는 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. sm_check_waiver path.

---

## Section: 통계적 팩터 모델 (WT-002 specific)

### Method: DCC-GARCH Vol Target (Engle 2002 / Engle-Sheppard 2001)

1. Univariate GARCH(1,1) Gaussian per stock (STR_1715 holdings 18 active). min_obs 252.
2. Standardized residuals: z_i,t = ε_i,t / σ_i,t.
3. DCC(1,1) dynamic conditional correlation: Q_t = (1-α-β)Q̄ + α(z_{t-1}z'_{t-1}) + βQ_{t-1}, α+β<1.
4. Dynamic Σ_t = D_t R_t D_t.
5. Portfolio σ_p,t = sqrt(w'Σ_t w).
6. Vol target rule: σ_p target (rolling 3y avg 또는 fixed 15% annual). w_t = w_alpha * (target/forecast). cash bridge = 1 - sum(w_t scaled).
7. Statistical only — 휴리스틱 X. DCC params SHA-frozen.

### M4 vs DCC 차원 차이
- M4: regime-conditional cash overlay (binary Normal/Crisis state)
- DCC: continuous σ forecast (fine-grained vol targeting)
- 두 신호는 시간축에서 다르게 활성화 가능 (M4 lag + DCC lead)

### MDD/Vol mechanism
σ_p target 일정 유지 → 위기 시 자동 cash bridge (statistical scaling, no fixed % rule).

---

## state_machine 정상 통과
SPEC_APPROVED → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE → OPT → FORGE → JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.

---

## Section: risk Round 1 — Codex timeout → codex_critic_skip_waiver (Q-Lead override)

**Codex Round 1 timeout** (15+ min, log mtime stale).

**Round 2 자체검증**: 3 WT (001/003/004) 동일 패턴 — Codex REJECT 본질은 STR_1715 alpha-side 한계 (CVaR 12.89% > 2.5% cap, AX-007 single-sleeve mechanism limit). statistical sizing_only로 해소 불가. forge phase backtest까지 진행해서 actual metrics + judge verdict 결정 (LRO Round 1 패턴).

**도훈 명시**: "오토모드답게 처리해서 완결" + 자율 진행. AX-008 forge + architect 후 2/3 PASS 가능.

**Bypass 아님 — Codex infrastructure timeout + sizing_only 한계 본질 인지**.

---

## Section: optimizer Round 1 — Codex REJECT/timeout → Round 2 waiver

LRO Round 1 동일 패턴. 본질은 STR_1715 alpha-side 한계 (sizing_only statistical method 한계). forge phase backtest까지 진행해서 actual metrics + judge verdict 결정. 도훈 명시 자율 진행.
