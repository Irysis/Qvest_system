# challenge_note — WT-S20260504_003 (HMM_Regime)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking input only, HMM 3-state latent posterior로 weight scale 결정. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. HMM Regime은 risk management이지 alpha 아님. 후속 5 agent는 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. sm_check_waiver path.

---

## Section: 통계적 팩터 모델 (WT-003 specific)

### Method: HMM 3-state Latent Regime (Hamilton 1989 / Ang-Bekaert 2002)

1. Features: KOSPI200 monthly return + realized vol 60d + market breadth correlation + STR_1715 NAV return
2. HMM spec: 3-state {Normal, Caution, Crisis}, multivariate Gaussian emissions
3. Estimation: Baum-Welch EM algorithm, k-means seed init, max_iter 200, tol 1e-6
4. Posterior: γ_t(k) = P(state=k | observations 1..t) via forward-backward
5. Regime-conditional weight: w_t = w_alpha × Σ_k γ_t(k) × scale_k (Normal=1.0 / Caution=0.7 / Crisis=0.4)
6. Statistical only — fixed % cash rule X. scale factors는 historical regime risk premium-based.

### MDD/Vol mechanism
HMM posterior에 따른 continuous weight scaling. crisis state probability 높을 때 자동 보수화 (alpha 무손상 selection 그대로).

---

## state_machine 정상 통과
SPEC → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE → ... → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.
