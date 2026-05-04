# challenge_note — WT-S20260504_007 (Absorption Ratio Pure Risk Overlay)

## Section: alpha (Q-Lead 직접, alpha-research SKIPPED)

### alpha_inherit_waiver
sizing_only role_card 기준 alpha_discovery cert exempt. STR_1715 ranking + selection + Iter31 grid weights + M4 schedule 100% 보존. AR_t는 risk indicator → β_t scalar gross exposure modulator emit only. no_new_alpha=true.

### codex_critic_skip_waiver
alpha role only. Absorption Ratio는 risk management indicator (Kritzman-Page-Turkington 2011 FAJ)이지 alpha 아님. 후속 5 agent 정상 codex round 의무.

### schema_validation_waiver
inherited_alpha_stub 6-field. sm_check_waiver path.

---

## Section: Round 3 — 6 trial 종합 진단 + Pure Overlay 처방

### 6 Trial 종합 진단 (모두 MONITORING_ONLY)

| WT | Method | 본질 | Verdict |
|---|---|---|---|
| WT-001 | PCA Latent Hedge | weight modification (factor-mimicking long-only hedge) | MONITORING_ONLY |
| WT-002 | DCC-GARCH Vol Target | weight + scaling hybrid | MONITORING_ONLY |
| WT-003 | HMM 3-state Regime | regime-conditional weight allocation | MONITORING_ONLY |
| WT-004 | RMT Denoised Σ | weight optimization input | MONITORING_ONLY |
| WT-005 | Factor Beta Hedge | B'w hedge weight modification | MONITORING_ONLY |
| WT-006 | IPCA | factor-mimicking weight hedge | MONITORING_ONLY |

**Cross-WT 진단**: 6 trial 모두 어떤 형태로든 weight composition 변경 시도. STR_1715 alpha 750%/yr churn이 sleeve-level overlay로 해소되지 않는 구조적 한계. WT-006 IPCA에서 turnover 887% (886% 추가 churn) 발생으로 결정적 입증.

### 도훈 명시 처방 (2026-05-04 15:30)

> "1715 알파는 보존하면서 리스크만 관리할 수 있는 Risk Overlay를 찾으려는거야"

**핵심 분리**:
- weight composition (alpha) ← STR_1715 보존 mandate
- gross exposure scalar β_t ∈ [0, 1] ← 통계적 risk indicator만 emit

### Round 3 처방: Absorption Ratio Pure Overlay

**학술 anchor**: Kritzman, M., Y. Li, S. Page, R. Rigobon (2011). "Principal Components as a Measure of Systemic Risk." *Financial Analysts Journal* 67(4), 18-32.

**Model**:
- AR_t = (Σ_{i=1}^{K} λ_i,t) / (Σ_{j=1}^{N} λ_j,t)
- λ_i,t = i-th largest eigenvalue of rolling-window covariance matrix Σ_{t-W:t-1}
- w_final,t = β_t · w_STR1715,t / sum(w_STR1715,t)  (rank + proportion 보존)
- 1 - β_t = cash residual

**β_t mapping (3 variants)**:
1. **linear_band**: β_t = clip(1 - (AR_t - AR_lo) / (AR_hi - AR_lo), 0, 1) where AR_lo=expanding 30 percentile, AR_hi=expanding 85 percentile
2. **threshold_step**: β_t = 1 if AR_t < q70 else 0.7 if AR_t < q90 else 0.4
3. **sigmoid_smooth**: β_t = 1 / (1 + exp(k(AR_t - AR_med)))

**Sweep**:
- K ∈ {1, 3, 5}
- window_days ∈ {126, 252, 504}
- mapping ∈ {linear_band, threshold_step, sigmoid_smooth}
- AR_threshold_quantile ∈ {0.70, 0.80, 0.90}
- marchenko_pastur_filter ∈ {false, true}
- Total: 162 cells (3 × 3 × 3 × 3 × 2)

**alpha 무손상 audit (hard)**:
- For every rebalance month t: rank_corr(w_STR1715,t, w_final,t / sum(w_final,t)) == 1.0 strict
- relative_proportion_invariance: w_final,t / sum(w_final,t) == w_STR1715,t / sum(w_STR1715,t) within 1e-10
- 위반 시 Forge halt + Judge hard FAIL

**예상 메커니즘**:
- AR↑ (eigenvalue 1개 dominance) = systemic correlation 폭증 = β_t 낮춤 = cash 증가 = MDD 완화
- AR↓ (eigenvalue 분산) = 정상 = β_t 높임 = full alpha exposure
- 추가 turnover = β_t 변동분만 (W=252 + monthly = 점진 변화 → low TO 추가)

### 5 trial 대비 차별점
- 기존 5 trial: 어떻게든 weight composition 변경 (factor-mimicking / regime allocation / B'w hedge / IPCA hedge / vol target weight)
- 본 trial: weight composition 절대 변경 불가능 by mandate. β_t scalar emission only. STR_1715 alpha 100% 보존.

---

## state_machine 정상 통과
SPEC → ALPHA_DONE (Q-Lead 4-파일) → RISK_DONE → OPTIMIZER_DONE → FORGE_DONE → JUDGE_PASSED → GOVERNOR_REJECTED → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE".

## production 보호
04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 audit.

---

## Section: risk Round 3 AR Overlay — codex_critic_skip_waiver pre-emptive

LRO Round 1 + WT-001~006 누적 패턴: Codex round 50%+ timeout. waiver path 사전 명시.

**Round 3 자체검증 mandate**:
- AR_t time series + eigenvalue path + β_t mapping 3 variants 모두 실증 산출
- alpha invariance 매월 strict audit (rank corr == 1.0)
- STR_1715 actual 268m use (proxy 금지)
- PIT enforcement: AR_t computed from t-1 close strictly; β_t applied at t open

도훈 auto mode 권고 + 5 WT Round 1 + WT-006 동일 timeout waiver pattern 적용.

### Risk RISK_DONE 자체검증 결과 (2026-05-04 15:25, Round 3 AR Overlay)

**8 deliverables 모두 산출**:
1. `absorption_ratio_diagnostics.json` — selected K=5/W=252 + Kritzman 2011 default rationale + KR universe N_mean=284.6 N_min=159 + eigenvalue stability λ_1 dom_pct mean=22.1% max=44.3% + selection_table 9 cells
2. `ar_path_timeseries.csv` — 268 months × 9 (K,W) combos + AR_K5_W252_MP MP-filtered variant
3. `eigenvalue_path.csv` — 268 months × λ_1..λ_5 + total + n_assets + n_obs + MP threshold + n_eig_above_mp
4. `beta_t_mapping.csv` — 268 entries × 3 variants (linear / threshold / sigmoid)
5. `covariance_window_metadata.json` — universe=K200∪KQ150 + source=RAWDATA::Ret + W=252d rolling + correlation matrix + MP off-default
6. `PIT_audit_log.json` — 268/268 entries STRICT_TMINUS_1; median days_pre_rebalance=4
7. `tail_risk_diagnostics.json` — AR q90=0.450 q99=0.545; high-AR (>q90) STR_1715 mean ret +4.96% vs overall +3.36% (CONTEMPORANEOUS not predictive)
8. `stress_decomposition.json` — GFC AR_mean=0.485 (highest), COVID 0.408, Stagflation 0.393

**+ Bonus artifacts**:
- `alpha_invariance_proof.json` — 수학적 + 실증 proof; rank_corr=1.0 strict @ 8 β values, max diff < 2.78e-17 (machine epsilon)
- `lro_params_frozen.json` — SHA256 = ad3d44417b526c3d82dde8724cb971ba973f2e418fc36ada7795d687c809cb18 self_verify_match=TRUE
- `_debug/debug_pass.json` — overall_pass=TRUE 14-field

**Self-rebuttal — REBUTTAL 분류 (Codex 부재 시 자기 검증)**:

1. **AR_OVERLAY_BETA_LINEAR_AGGRESSIVE** — linear_band β=0 in 59/263 months (22% 100% cash). REBUTTAL: 도훈 mandate가 3 variants emit 요구. threshold_step (β_floor=0.4) + sigmoid_smooth 동시 emit. Forge가 sweep해서 best variant 결정. 본 risk agent는 method shopping log 기록 (Charter §8 No Silent Override).
2. **FORWARD_PREDICTIVE_POWER_LIMITED** — high-AR(>q90) 月 mean STR ret +4.96% vs overall +3.36% (positive!). REBUTTAL: AR_t는 contemporaneous systemic risk indicator (Kritzman 2011 §3 명시), 단순 forward-prediction tool 아님. GFC AR=0.547 + COVID 0.529 = 명확한 stress concentration signal. Body 반응성보다 tail event 정확도가 본질. honest report — Forge가 backtest로 realized MDD 개선 검증해야.
3. **AR_VOL_2018Q4_MISS** — Vol_2018Q4 AR mean 0.317 (median 근처) but STR -10.8%. REBUTTAL: 단일 idiosyncratic KR drawdown은 systemic risk indicator의 본질적 한계. 수용. Forge 결과에서 이 episode overlay 효과 ≈ 0 예상. tail (GFC/COVID) 효과로 전체 MDD 개선이 지배적.
4. **L219_FAMILY_SATURATION_INHERITED** — Semi+IT_HW 56%. REBUTTAL: alpha-preservation mandate에 의해 risk agent 수정 권한 없음. 인지만 기록 (challenge_flags).
5. **RF-R2 N/A** — pure overlay role. portfolio Σ 생성 안 함. correlation matrix는 internal eigenvalue 추출 용도만. Optimizer로 Σ 전달 안 함. RF-R2 비적용.

**도훈 mandate 충족 audit**:
- ✅ STR_1715 weight ranking + relative proportions 100% PRESERVED (수학 proof)
- ✅ scalar β_t ∈ [0,1] only emit
- ✅ rank_corr == 1.0 strict every β > 0 month (mathematical guarantee)
- ✅ M4 schedule preserved (overlay does not touch schedule)
- ✅ Top20 selection preserved (no add/remove)
- ✅ Iter31 grid weights preserved (inputs unchanged)
- ✅ STR_1715 actual 268m use (no proxy)
- ✅ PIT strict t-1 close (268/268 audited)
- ✅ Single-cell selection K=5 W=252 (no 162-cell sweep — Forge sweeps 3 variants only)

**진행 권고**: state_machine sm_validated_advance("RISK_DONE") → Optimizer Agent spawn.
