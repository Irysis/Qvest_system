# challenge_note — WT-S20260504_001 (PCA_Latent_Hedge)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking input only, statistical PCA model로 weight 결정. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. PCA Latent Hedge는 risk management model이지 alpha 아님. 후속 risk/optimizer/forge/judge/governor 5 agent는 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. cert_rules.role_card_4x5 sizing_only alpha_discovery exempt와 동일 logic.

---

## Section: 통계적 팩터 모델 (WT-001 specific)

### Method: PCA Latent Hedge (Connor-Korajczyk 1986 / Bai-Ng 2002)

1. Residualization: STR_1715 universe stock returns from known factors (MKT/SIZE/VALUE/MOM/QUALITY/LOWVOL) + 11 sector dummy. Window 252/504 (IS-fixed).
2. Rolling PCA: K∈{3,5,8} IS-frozen. cov vs corr 비교.
3. Factor extraction: B matrix (n×K) latent factor loadings.
4. Portfolio exposure: x_t = B'w_t latent factor exposure.
5. Hedge objective: minimize dominant latent factor exposure (max |x_k|) under long_only + Σw=1 + cap [0,0.20] + max_names ≤20. STR_1715 alpha ranking은 weight bound 또는 score input.
6. Statistical only — 휴리스틱 rule X (DD brake / topN / fixed cash %). PCA params SHA-frozen.

### MDD/Vol mechanism
Dominant latent factor 노출 최소화로 hidden common risk 회피. STR_1715 alpha selection 그대로, weight redistribution만.

---

## state_machine 정상 통과
SPEC_APPROVED → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE (risk-research) → OPT → FORGE → JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.
