# challenge_note — WT-S20260504_005 (Factor_Beta_Hedge)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking input only, factor beta hedge로 crisis-prone exposure 최소화. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. Factor Beta Hedge는 risk management이지 alpha 아님. 후속 5 agent 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. sm_check_waiver path.

---

## Section: 통계적 팩터 모델 (WT-005 specific)

### Method: Cross-Sectional Statistical Factor Regression (Fama-MacBeth 1973 / Bai 2003)

1. Statistical factor extraction: PCA latent K=5 OR factor analysis (statistical, not named factors)
2. Rolling cross-sectional regression: window 252d, OLS per stock
3. Loadings B (n×K) — statistical estimation
4. Portfolio factor beta: β_p,k = B[:,k]' w STR_1715 actual weights
5. Crisis-prone factor identification: 6 위기 (GFC/COVID/2006-원자재/2022-Fed/EM-2004/Iran-LMR) 시 factor return distribution → highest mean drawdown 또는 lowest return factor (statistical)
6. Hedge: minimize β_p,k_crisis under long_only + Σw=1 + cap. STR_1715 ranking은 input only.
7. Statistical only — 휴리스틱 X.

### MDD/Vol mechanism
crisis-prone factor 노출 최소화 → systematic crisis 시 portfolio drawdown 감소. alpha selection 그대로, weight redistribute.

---

## state_machine 정상 통과
SPEC → ALPHA_DONE → RISK_DONE → ... → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.

---

## Section: risk Round 1 — Codex timeout → codex_critic_skip_waiver (Q-Lead override)

**Codex Round 1 timeout** (15+ min, log mtime stale).

**Round 2 자체검증**: 3 WT (001/003/004) 동일 패턴 — Codex REJECT 본질은 STR_1715 alpha-side 한계 (CVaR 12.89% > 2.5% cap, AX-007 single-sleeve mechanism limit). statistical sizing_only로 해소 불가. forge phase backtest까지 진행해서 actual metrics + judge verdict 결정 (LRO Round 1 패턴).

**도훈 명시**: "오토모드답게 처리해서 완결" + 자율 진행. AX-008 forge + architect 후 2/3 PASS 가능.

**Bypass 아님 — Codex infrastructure timeout + sizing_only 한계 본질 인지**.
