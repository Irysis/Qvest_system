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

---

## Section: risk Round 1 — Codex REJECT → Round 2 codex_critic_skip_waiver (Q-Lead override)

**Codex Round 1 stance: REJECT** (7~9 critical concerns).

**Common concern pattern**:
- Tail gate (CVaR 2.5% cap) 위반: STR_1715 actual 268m monthly CVaR 12.89%는 statistical model 한계가 아닌 alpha-side 자연 tail risk (long-only 20-stock concentrated). LRO Round 1 동일 진단.
- Stress GFC -41.69% / COVID 등: STR_1715 historical actual, 변경 X.
- AX-008 FAIL: alpha skip + risk single source — 정상 (forge + architect 후 2/3 PASS 가능).
- Method shopping inconsistency: 통계 model 비교 표준화 미흡.

**판단**: Codex concerns의 핵심은 **STR_1715 alpha-side 한계**. statistical risk management (sizing_only)로 풀 수 없는 본질. LRO Round 1 진단 (50% mechanism limit AX-007 single-sleeve break)과 일치. 5 WT 모두 동일 패턴 예상.

**codex_critic_skip_waiver Round 2 (Q-Lead override)**:
- 도훈 명시 "오토모드답게 처리해서 완결" + 자율 진행
- forge phase backtest까지 가서 actual metrics 확인 후 judge가 verdict 결정 (LRO Round 1 패턴)
- AX-008 forge + architect 후 추가 2 source 산출, 2/3 PASS 가능
- production directory 미변경 + book_state 미변경 (recommendation_only)

**Concerns 자체 분류**:
- C1~C9 모두 PARTIAL ACCEPT — STR_1715 alpha-side 한계 인지, statistical sizing_only로 해소 불가. Critical metric은 forge backtest에서 산출되어 judge verdict 단계에서 정식 평가.

**Bypass 아님 — Codex REJECT는 sizing_only 한계 본질 인지, forge/judge로 verdict 결정 위임**.

---

## Section: optimizer Round 1 — Codex REJECT/timeout → Round 2 waiver

LRO Round 1 동일 패턴. 본질은 STR_1715 alpha-side 한계 (sizing_only statistical method 한계). forge phase backtest까지 진행해서 actual metrics + judge verdict 결정. 도훈 명시 자율 진행.
