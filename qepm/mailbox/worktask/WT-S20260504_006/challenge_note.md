# challenge_note — WT-S20260504_006 (IPCA Instrumented PCA)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking input only, IPCA로 weight 결정. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. IPCA는 risk management이지 alpha 아님. 후속 5 agent 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. sm_check_waiver path.

---

## Section: Round 2 — WT-001 PCA 한계 진단 + IPCA 처방

WT-001 PCA Latent Hedge **MONITORING_ONLY 진단**:
- LFC reduction 42% (mean) achieved 단 MDD -42.67% 악화 (S1+M4 baseline -36.44% 대비)
- 시간 불변 B_ref + linear factor + no firm characteristics → alpha 손상 큼

**IPCA (Kelly-Pruitt-Su 2020 JFE) 처방**:
1. **time-varying loadings**: β_i,t = Γ_β z_i,t. characteristics가 instrument로 작용하여 시간 변동 자동 반영. 2020+ semi/AI 비중 변화 capture.
2. **firm characteristics 풍부 활용**: L=6/12/20 후보 (market cap / B/M / E/P / momentum / ROE / earnings / low vol / sector). KR Factor DB 288+ factor 풍부.
3. **PCA 일반화**: K latent factor + L instrument → ALS로 결합 추정. nonparametric.
4. **alpha misspecification test**: restricted (α=0) vs unrestricted. Kelly-Pruitt-Su §3.4 test statistic.

### IPCA Pipeline (정교화 핵심)
1. **Characteristics matrix Z_t** (N × L): t 시점 KR universe firm characteristics. PIT 의무 (Usable_Date ≤ sig_date).
2. **Returns matrix R_t** (N × T): rolling daily/monthly returns.
3. **ALS estimation**: 
   - Step A (fix Γ_β, solve f_t): f_t = (Z_t Γ_β)' R_t / N
   - Step B (fix f_t, solve Γ_β): vec(Γ_β) = (X'X)^{-1} X'r where X = stacked Z_t
   - 반복 until convergence (∇|loss| < 1e-6)
4. **K selection**: explained variance + alpha test.
5. **Factor mimicking long-only hedge**: minimize dominant latent factor exposure under STR_1715 alpha ranking score input.

---

## state_machine 정상 통과
SPEC → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE → ... → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.
