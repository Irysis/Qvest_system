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
