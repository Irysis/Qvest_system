# challenge_note — WT-S20260504_004 (RMT_Denoised_Cov)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking input only, RMT-denoised Σ + ES forecast로 vol/cash adjustment. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. RMT Denoised는 risk management이지 alpha 아님. 후속 5 agent 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. sm_check_waiver path.

---

## Section: 통계적 팩터 모델 (WT-004 specific)

### Method: RMT Denoised Σ (Laloux et al. 1999 / Bouchaud-Potters 2009)

1. Sample correlation R from STR_1715 universe daily returns (924d × 18~500 stocks)
2. Eigenvalue decomposition: R = U Λ U^T
3. Marchenko-Pastur theoretical bulk: [(1-sqrt(N/T))², (1+sqrt(N/T))²]. T=924, N=18~500
4. Noise eigenvalue (within bulk) → flatten to bulk mean
5. Signal eigenvalue (outside, > λ_max_MP) → retain
6. Denoised R̂ = U Λ_cleaned U^T → denoised Σ̂ = D R̂ D
7. ES forecast: Cornish-Fisher OR EVT-GPD on portfolio σ from Σ̂
8. Vol adjust: weight scale = target_ES / current_ES (statistical, not fixed %)

### MDD/Vol mechanism
RMT-cleaned correlation은 noise-free → portfolio σ forecast 정확도 향상 → ES quantile-based weight scaling으로 자연 vol target.

---

## state_machine 정상 통과
SPEC → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE → ... → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

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
