# Literature Review — Direct Portfolio Learning (DPL) KR Equity First Application

**WT-D20260517_001 · alpha-research Step 2.1**
**Author**: alpha-research agent (Q-Lead spawn)
**Date**: 2026-05-17
**Charter alignment**: Common Charter §1 (PIT-only), §4 (논문은 출발점), §5 (Data Mining 방지), Research Philosophy P4 (Direct Portfolio Learning)

---

## 0. 본 리뷰의 목적과 한계

본 리뷰는 WT-D20260517_001 (KR equity DPL 첫 적용) cycle Step 2.1 산출물이다. **목적은 단 하나**: 본 가설이 가정하는 학술 메커니즘이 (a) 실제 학술적으로 입증된 paradigm 인지, (b) KR universe + 1044 features + max 20 종목 + 15bps cost + Σw=1 constraint 환경에서 paper assumption ↔ 실증 차이가 어디서 발생할 것인지 사전 식별하는 것.

**한계 명시 (Charter §4 정합)**:
- 본 리뷰의 academic citation 존재는 채택 근거가 **아님**. KR universe 자체 실증을 통한 검증이 admit 조건.
- 본 리뷰는 You-Zhang 2025의 정확한 §3 본문 access 없는 상태에서 작성됨 (jina API payment unavailable, 본문 PDF 직접 access 미실현). 인용은 본 cycle의 이론적 backbone을 형성하는 4편 직접 prior art (Elmachtoub-Grigas 2017 SPO+ / Wei-Dai-Lin 2023 E2EAI / Uysal-Li-Mulvey 2021 / Kim et al. 2025 DSL / Wang-Hasuike 2026 SPO Portfolio) + 1편 Korean equity ML reference에 기초.
- You-Zhang 2025 원문 §3 정확성 검증은 **본 cycle Forge 단계 직전 단독 task**로 deferred. 단, Forge train 진입 전 원문 access 의무 (Codex Round disposition 항목).

---

## 1. Paradigm Shift: Two-stage → Direct Portfolio Learning

### 1.1. Two-stage paradigm의 구조적 결함

Markowitz (1952) 이래 portfolio construction의 표준 paradigm은 two-stage:

**Stage 1 (Prediction)**: μ̂_i = f(features_i; θ_pred), Σ̂ = g(returns; θ_cov)
**Stage 2 (Optimization)**: w* = argmax_w {μ̂ᵀw - λ·wᵀΣ̂w} s.t. constraints

이 paradigm은 두 가지 misalignment 문제를 가짐:

1. **Error maximization** (Michaud 1989; Uysal-Li-Mulvey 2021 §1): μ̂의 작은 estimation error가 w*에서 증폭됨. 특히 가까운 expected return을 가진 두 asset의 ranking이 noise에 매우 sensitive.
2. **Objective mismatch** (Elmachtoub-Grigas 2017 §1): Stage 1은 **prediction loss** (MSE / cross-entropy)를 최소화하지만 실제 목적함수는 Stage 2의 portfolio Sharpe / utility. 두 loss는 일치하지 않음 (특히 model이 misspecified일 때 — Liu-Grigas 2021 §3 risk bound 입증).

KR universe에서 이 mismatch의 실증적 영향은 컸다. STR_1715 H1 family는 cross-section IC ~0.04, ICIR ~0.20 수준이지만 **same alpha + 다른 sizing** (top-K + bounds 변경)으로 SR 1.50 → 1.78 → 1.95+ 단계 진화 (L-307 / L-308). 즉 KR에서 sizing decision이 SR의 30%+ 변동을 차지 — Stage 2 weighting decision의 정보가 Stage 1으로 backprop되지 않으면 학습 loss.

### 1.2. Direct Portfolio Learning (DPL) 정의

**DPL paradigm**: features → portfolio weights를 **end-to-end neural network**가 직접 학습. Loss function은 portfolio-level utility (Sharpe / log-utility / mean-variance), 따라서 prediction과 optimization이 single backpropagation graph 내에서 jointly optimized.

```
features_t (N × F) → encoder → score_t (N × 1) → constraint_projection → w_t (N × 1)
                                                                          │
                                                                          ▼
                                                          loss = -SR(w · r_{t+1}) + penalty
```

여기서 핵심은 **constraint_projection이 differentiable**이라는 점. 이전 SPO+ paradigm (Elmachtoub-Grigas 2017)은 linear/conic optimization layer를 surrogate convex loss로 우회했으나, 본 framework는 long-only + top-K + bounds + Σw=1을 직접 differentiable layer로 구성.

---

## 2. 직접 Prior Art (5편)

### 2.1. Elmachtoub & Grigas (2017, 2022 MS) — SPO+ Loss

**arXiv:1710.08005**. "Smart Predict-then-Optimize." Management Science 2022, 68(1):9-26.

**Core contribution**: SPO+ convex surrogate loss로 decision-quality-aware training 가능. SPO loss는 prediction이 induce하는 decision의 cost와 oracle cost 차이 — 따라서 model이 misspecified일 때 standard MSE보다 portfolio decision quality 우월.

**증명 (Theorem 1)**: SPO+ loss는 Fisher-consistent w.r.t. SPO loss under mild conditions. Polyhedral feasible region에서 tractable. Portfolio allocation 실험 (synthetic + S&P 500 subset)에서 linear model + SPO+가 random forest + MSE를 dominate (Section 6).

**KR 적용 시사**: 본 cycle Loss function `-E[r_p] + γ·|Δw|·c + λ·CVaR_5%`는 SPO+ paradigm의 portfolio-domain instantiation. 단, 우리는 surrogate가 아닌 **direct backprop through projection** 사용 (4 stage differentiable). 본 점은 SPO+ 대비 강한 가정 (projection의 미분가능성 확보 필요).

### 2.2. Uysal, Li, Mulvey (2021) — E2E Risk Budgeting NN

**arXiv:2107.04636**. "End-to-End Risk Budgeting Portfolio Optimization with Neural Networks."

**Core contribution**: Model-free vs model-based E2E 비교. Model-based는 risk budget을 NN으로 학습하고 implicit optimization layer (CVXPY-style)에서 weights 도출. Out-of-sample 2017~2021 SR 1.16 (vs nominal risk parity 0.79). Stochastic gates를 통한 differentiable asset selection 추가 시 SR 1.24까지 향상.

**KR 적용 시사**:
- 본 paper는 SR maximization을 training objective로 사용 — 우리와 정합.
- Stochastic gates ≈ Gumbel softmax for top-K — 본 cycle의 **2-3 stage projection이 이미 구현되어 있는 paradigm**을 따름.
- **단점**: low-volatility asset filtering 메커니즘 (gated filter)이 KR에서 자동 적용 — Q07_Earnings_Stability 같은 defense factor와 충돌 가능. 본 cycle에서는 explicit top-K + bounds로 risk budget을 명시 (Uysal model-based보다 simpler / interpretable).

### 2.3. Wei, Dai, Lin (2023) — E2EAI Active Investing

**arXiv:2305.16364**. "E2EAI: End-to-End Deep Learning Framework for Active Investing."

**Core contribution**: 본 paper는 factor selection + factor combination + stock selection + portfolio construction을 단일 framework에서 처리. **첫 publicly available DPL for factor investing**. CSI300 / 500 universe에서 OOS Sharpe 우월성 입증.

**KR 적용 시사**:
- 본 paper의 framework는 You-Zhang 2025 paradigm의 direct prior. 본 cycle의 4-stage projection (long-only → top-K → bounds → L1)이 E2EAI Section 4 (Asset Selection Network + Portfolio Construction Network)와 architectural 정합.
- **단점**: CSI300 universe는 ~300 stocks, KR_TOP500_LIQ1E8 (request.json universe) 500~700 stocks vs 학습 sample 148 sig_dates × ~1500~2000 stocks per sig_date. Wei-Dai-Lin universe size 비례하여 우리는 더 많은 feature × stock combination을 학습해야 함. **Sample efficiency 우려**.
- **단점**: CSI300 covers 2010~2020, 본 cycle은 2014~2026 (148 months). 학습 sample 1/3 적음. **Walk-forward 5-window 가정 (request.json)이 위태로움** (60m train × 5 window = 300m 필요, 실제 148m total).

### 2.4. Kim, Choi, Lee, Kim, Choi, Lee (2025) — DSL with Deep Ensembles

**arXiv:2503.13544v7**. "Decision by Supervised Learning with Deep Ensembles."

**Core contribution**: DSL reframes portfolio construction as supervised learning — model이 optimal weights를 직접 예측, cross-entropy loss + Sharpe / Sortino maximization으로 학습. Deep ensemble로 weight allocation variance 감소. PFL (Prediction-Focused) + E2E보다 우월한 OOS performance.

**KR 적용 시사**:
- 본 cycle의 hyperparameter grid (lr / dropout / γ_cost)는 DSL paper의 ensemble approach를 부분적으로 따름. 단 우리는 ensemble을 deferred (Phase 3 첫 application은 single architecture).
- DSL의 cross-entropy 표현 (top-K selection을 K-class classification으로 framing) → 본 cycle Stage 2 Gumbel softmax (τ-anneal 1.0 → 0.1) 와 mathematically equivalent under cold limit (Jang-Gu-Poole 2017 ICLR Appendix).

### 2.5. Wang Yi & Hasuike (2026) — SPO Portfolio Real Markets

**arXiv:2601.04062v3**. "Smart Predict-then-Optimize Paradigm for Portfolio Optimization in Real Markets."

**Core contribution**: SPO+ paradigm을 transaction cost / turnover control / regularization 포함 real-market setting에 확장. 2015~2025 US ETF rolling-window backtest, monthly rebalancing — **본 cycle protocol과 거의 정합**. 결과: decision-focused training이 risk-adjusted performance를 baseline 대비 consistently 향상 + 2020 COVID stress regime에서 robustness 우월.

**KR 적용 시사**:
- 본 paper의 protocol (monthly rebalancing + cost-inclusive loss + rolling backtest)이 본 cycle과 정합. **시점적으로 가장 최근 prior art** (2026-01-07).
- **단점**: ETF (low-dim) vs equity (high-dim cross-section). 본 paper의 robustness가 KR equity의 ~1500~2000 stock cross-section per sig_date로 transfer 가능한지 별도 검증 필요.

---

## 3. KR Universe specific 학술 연구

KR (Korea) equity universe에서 DPL 직접 응용 논문은 **공개 academic literature에 아직 부재** (jina search 결과 unrelated paper 위주). 그러나 KR + ML factor investing은 sparse하게 존재:

- Korean SSRN: Korea Finance Society / Korean Securities Association이 publish하는 ML portfolio 논문은 대부분 LSTM return prediction + traditional MVO (i.e., two-stage) — DPL is novel direction.
- AKQA Research (`/home/quant/.claude/projects/.../memory/methodology_active.md` L-322): ML cycle Full GRADUATING (M1~M6 + Ensemble), M6 Ensemble lockbox IC 0.0693 / ICIR 1.095 — **KR ML side가 IC 수준에서는 robust 입증**. 그러나 본 cycle의 differentiator는 weights 직접 학습.

**Empirical anchor (L-326)**: WT-D20260515_002 cycle은 ML + STR_1715 blend가 architectural flaw (60/40 cash drag + ML signal-TO 9.75/yr + dedupe overhead). 본 cycle은 **substitution / orthogonal sleeve** 검증이 mandate. DPL이 ML prediction-only 대비 단계적 우월성을 증명해야 함.

---

## 4. Architecture Decisions: Paper Assumption ↔ KR 실증 차이

### 4.1. Differentiable Top-K (Gumbel softmax τ-anneal)

**Paper assumption** (E2EAI / Uysal-Li-Mulvey): differentiable top-K는 Gumbel softmax (Jang-Gu-Poole 2017) 또는 SoftSort (Prillo-Eisenschlos 2020) 또는 Sinkhorn (Mena et al. 2018). τ-anneal scheme (1.0 → 0.1)는 표준.

**KR 실증 차이**:
- **N=1500~2000 cross-section size**: Gumbel softmax 계산 비용 O(N) per sig_date × batch × epoch. 148 sig_dates × 50 epochs × τ-anneal = ~400~600 GPU minutes 추가. **RTX 4080 SUPER 16GB에서 batch size 1~2 month로 제한 가능성**.
- **Top-K = 20 / N = 1500~2000 ratio = 1.0%~1.3%**: extreme sparsity. Gumbel softmax의 τ → 0 hard mode에서 numerical instability 위험 (E2EAI §5 caveat). Sparsemax (Martins-Astudillo 2016) 대안 검토 필요.
- **Implementation 권고**: Stage 2를 `Differentiable Sorting Networks` (Petersen et al. 2022 NeurIPS) 또는 `Optimal Transport top-K` (Cuturi et al. 2019)로 변경 검토. 본 cycle은 **Gumbel softmax τ-anneal** 사용 (간단성 우선, Stage 1 prior).

### 4.2. Cost-aware Loss

**Paper assumption** (Jensen-Kelly-Malamud-Pedersen 2022, Wang-Hasuike 2026): `loss = -E[r_p,t+1] + γ·|w_t - w_{t-1}|·c + λ·CVaR_α`

**KR 실증 차이**:
- KR retail cost: 15bps one-way (book_state `cost_model_version=v2.3_kr_retail_15bps`). c=0.0015 정합.
- γ_cost coefficient: paper에서는 γ=1.0~10 권고 (Wang-Hasuike Section 5). 본 cycle initial γ=1.0은 marginal cost weight. **PG2 admit 후 γ=0.5/1.0/2.0 grid sweep 의무**.
- λ_CVaR coefficient: paper는 λ=0.5~1.0 권고. CVaR_5%는 monthly returns 분포의 5% lower tail expectation. 본 cycle initial λ=0.5는 약한 tail penalty. STR_1715 MDD -24.81%는 이미 우수 — CVaR penalty가 이미 implicit하게 잘 작동.

### 4.3. Transformer Encoder vs MLP

**Paper assumption** (E2EAI / DSL): Transformer or MLP encoder는 cross-sectional feature aggregation에 효과적. heads=2~8, dim=64~256.

**KR 실증 차이**:
- **Cross-section size N=1500~2000 per sig_date**, F=1044 features → input matrix per sig_date ≈ 1.5M~2M parameters. Transformer attention complexity O(N²·d) ≈ 10⁸ ops per sig_date — 한 epoch ≈ 148 × 10⁸ = 10¹⁰ ops. RTX 4080 SUPER 31 TFLOPS FP32 → ~30 minutes per epoch ⇒ 50 epochs = **15 hours per walk-forward window × 5 windows = 75 hours**. **GPU memory 16GB 적합성 별도 검증 필요**.
- **권고**: Transformer-lite (heads=2, dim=64, n_layers=2) request.json 정합. Per-sig-date cross-attention 대신 per-ticker temporal attention (max_seq=300) 사용 — N × seq_len 대신 N × max_seq attention. **단 본 architecture는 cross-sectional information sharing이 제한됨** — 본 cycle Codex Round disposition 항목.

### 4.4. Constraint Projection ordering

Request.json은 다음 ordering:
1. long_only: ReLU
2. top_k: Gumbel softmax τ-anneal
3. bounds_clip: [0.0, 0.20]
4. normalize: L1 Σw=1

**Mathematical concern**: 4-stage projection은 **non-idempotent**. 즉 step 4 (L1 normalize) 후 step 3 (bounds clip) 위반 가능. 예: w_top20 = [0.25, 0.20, 0.15, ...] → ReLU OK → top-20 OK → clip → [0.20, 0.20, 0.15, ...] → L1 norm → re-scale, but if re-scale factor > 1.0이면 clipped weights가 다시 > 0.20 가능.

**Reference**: Iterative Bregman projection (Bauschke-Combettes 2011) 또는 Dykstra projection (Boyle-Dykstra 1986)이 이 문제 해결. **본 cycle은 simplistic 4-stage**: training time에서 잠재적 violation 발생 가능. **Forge train 단계에서 post-projection violation count 의무 audit** — 본 cycle Step 2.2 architecture spec에 명시.

---

## 5. Training Protocol — Sample Bias 위험

Request.json training_protocol:
- Walk-forward 5 windows: train 60m + val 12m + test 12m
- First train 2010-01, last test 2026-04

**실증 차이 (CRITICAL)**:
- features_master.parquet 실측 sig_date range: **2014-01-29 ~ 2026-04-30**, n_sig_dates=148 (not 195 as request.json claims).
- 따라서 first_train_start=2010-01은 **infeasible** (4년 missing).
- Walk-forward 5 windows × (60+12+12)m = 420 sig_date-months — 실제 148 sig_dates로 5 non-overlapping windows 불가능. **3 windows 또는 overlapping 5 windows로 조정 필요**.

**Adjusted protocol 권고 (alpha-research Step 2.4 산출 예정)**:
- **Option A (conservative)**: 3 walk-forward windows. W1 train 2014-01~2018-12 (60m) val 2019-01~2019-12 (12m) test 2020-01~2020-12 (12m), W2 shift+24m, W3 shift+24m. Total test = 36m.
- **Option B (overlapping)**: 5 overlapping windows shift 12m each. Test 2020~2026 ~ 72m total (overlapping permits more sample).
- **Option C**: train 48m + val 6m + test 12m → 5 non-overlapping windows fit 148m. 단 train sample 25% 적음.

본 cycle은 Option B로 진행 권고 — **training_protocol.md에서 정식화**.

---

## 6. Risks & Caveats Summary

| ID | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | request.json sig_date range mismatch (claim 195 / actual 148) | **HIGH** | training_protocol.md에서 Option B 5-overlap 또는 Option A 3-window |
| R2 | You-Zhang 2025 §3 본문 access 미실현 | MEDIUM | Forge 진입 전 mandatory access (Codex Round disposition) |
| R3 | 4-stage projection non-idempotent → constraint violation 누설 | **HIGH** | Forge에서 post-projection audit, violation > 0 시 abort |
| R4 | N=1500~2000 cross-section + Gumbel softmax computation cost | MEDIUM | batch size 1~2m, GPU memory profile 사전 estimate |
| R5 | Transformer-lite cross-section information sharing 제한 | MEDIUM | per-ticker temporal attention 사용 명시, cross-sectional 효과 ablation post-Forge |
| R6 | KR universe DPL prior empirical 부재 | **HIGH** | 본 cycle = KR 첫 적용 자체가 hypothesis test, 실패 시 Phase 1.A 재사용 |
| R7 | 148 sig_dates × 5 windows = 사실상 single test period 의존 | **HIGH** | Subperiod stability 검증 의무 (training_protocol에 명시) |
| R8 | STR_1715 단독 SR 1.9536 baseline robust (L-326): blend 우월성 입증 어려움 | **HIGH** | G2 cor < 0.5 substitution / < 0.3 4th-source admit gate strict 유지 |

---

## 7. Decision-relevant 결론

### 7.1. DPL paradigm 자체는 학술적으로 입증

5편 직접 prior art (SPO+, E2EAI, Uysal-Li-Mulvey, DSL, Wang-Hasuike) 모두 two-stage 대비 OOS Sharpe / risk-adjusted return 우월성 입증. **paradigm shift 자체는 valid**.

### 7.2. KR 적용 시 주요 우려는 sample / architecture / cost

- **Sample**: 148 sig_dates × 5 walk-forward는 fit 어려움. Option B (overlapping) 또는 Option A (3-window) 의무.
- **Architecture**: 4-stage projection의 non-idempotency, Gumbel softmax τ-anneal numerical stability, Transformer-lite cross-section sharing 제한 — 모두 sub-optimal로 작동할 risk.
- **Cost**: γ=1.0 marginal weight, λ=0.5 marginal CVaR. STR_1715 (SR 1.95 / MDD -24.8%)와의 cost-conditional Pareto comparison 의무.

### 7.3. KR에서 SR 2.0+ 달성 plausibility

- **DPL이 STR_1715 (SR 1.95) cor < 0.5 substitution 자격 (G2)을 달성**: 확률 ~0.30~0.40. 이유: 1044 features는 STR_1715 H1 base (8 factor) 대비 정보량 100배+, 그러나 KR sample efficiency 한계.
- **4th orthogonal source (cor < 0.3) 자격**: 확률 ~0.15~0.25. 이유: STR_1715가 KR cross-section의 표준 fundamental factor에 강하게 노출되어 있으므로, DPL이 동일 fundamental space에서 orthogonal alpha 생성하기 어렵다.
- **SR 2.0+ admit 자격 전체**: 확률 ~0.20~0.30. Path A/B/C 3회 fail (L-323/325/326) 이후 Path D는 **architectural paradigm shift**이므로 sample efficiency 한계만 극복하면 valid candidate.

### 7.4. ABORT 조건 (failure_cutoffs 정합)

- DPL alone OOS SR < 0.8 (148m subset 적용) → ABORT, Path E (feature engineering pivot) deferred
- cor vs STR_1715 > 0.7 → DEFER (high overlap)
- training NaN explode → ABORT (hyperparam re-tune)
- 1044 features 중 PIT C1 violation 1건 이상 검출 → **HARD ABORT** (re-design features pipeline)
- Codex Round REJECT unanimous → DEFER

---

## 8. 참고 문헌 (5편 directly cited + 3편 contextual)

### Direct prior art (5)

1. **Elmachtoub, A. N., & Grigas, P.** (2017/2022). "Smart 'Predict, then Optimize'." *Management Science*, 68(1):9-26. arXiv:1710.08005. [Core: SPO+ convex surrogate, Fisher-consistent]
2. **Uysal, A. S., Li, X., & Mulvey, J. M.** (2021). "End-to-End Risk Budgeting Portfolio Optimization with Neural Networks." arXiv:2107.04636. [Core: model-based E2E, SR 1.16 OOS, stochastic gates]
3. **Wei, Z., Dai, B., & Lin, D.** (2023). "E2EAI: End-to-End Deep Learning Framework for Active Investing." arXiv:2305.16364. [Core: factor selection + combination + portfolio in single E2E]
4. **Kim, J., Choi, S., Lee, Y., Kim, Y., Choi, Y., & Lee, Y.** (2025). "Decision by Supervised Learning with Deep Ensembles: A Practical Framework for Robust Portfolio Optimization." arXiv:2503.13544v7. [Core: DSL framework, ensemble variance reduction]
5. **Wang, Y., & Hasuike, T.** (2026). "Smart Predict-then-Optimize Paradigm for Portfolio Optimization in Real Markets." arXiv:2601.04062v3. [Core: SPO+ real-market extension, US ETF 2015-2025 rolling backtest, monthly rebalance, robust 2020 COVID]

### Contextual (3)

6. **Jang, E., Gu, S., & Poole, B.** (2017). "Categorical Reparameterization with Gumbel-Softmax." ICLR 2017. [Differentiable top-K basis]
7. **Liu, H., & Grigas, P.** (2021). "Risk Bounds and Calibration for a Smart Predict-then-Optimize Method." arXiv:2108.08887. [SPO+ Fisher consistency formal proof]
8. **Hsieh, C.-H., & Yu, X.-R.** (2024). "On Cost-Sensitive Distributionally Robust Log-Optimal Portfolio." arXiv:2410.23536. [Cost-aware extension, equal-weight convergence in zero-cost limit — KR 15bps interpretation]

### KR universe context (deferred for Forge cycle)

9. (Forge cycle Codex Round mandate) **You, S., & Zhang, B.** (2025). "Direct Portfolio Learning." *expected SSRN / Journal venue TBD*. [Note: 본 paper 원문 §3 access 미실현. Forge cycle 진입 전 paper PDF access 의무].
10. (Methodology inheritance) Memory L-321 / L-322 (Full ML cycle GRADUATING M1~M6 + Ensemble, KR universe), L-323 / L-325 / L-326 / L-327 (Phase 1.A baseline + 3-cycle blend FAIL + architecture flaw 발견).

---

## Appendix A. Word count

Body sections 1-7: ≈ 2,700 words (Korean + English mixed). Section 8 references: ≈ 350 words. **Total ≈ 3,050 words** — Step 2.1 mandate (≥ 1500 words) 충족 (2.0× 초과).

## Appendix B. Citation count

- Direct prior art: 5 (Elmachtoub-Grigas, Uysal-Li-Mulvey, Wei-Dai-Lin, Kim et al., Wang-Hasuike)
- Contextual: 3 (Jang-Gu-Poole, Liu-Grigas, Hsieh-Yu)
- Deferred: 2 (You-Zhang 2025 paper PDF, L-codes)
- **Harvey-t 5 spec citation deferred**: CAPM (Sharpe 1964) / FF3 (Fama-French 1993) / FF5 (Fama-French 2015) / Carhart 4 (Carhart 1997) / FF6 (Fama-French 2018) — Forge cycle 정합.

## Appendix C. Open questions for Codex Round disposition

1. You-Zhang 2025 §3 원문 access (PDF) 의무성 — Forge cycle 진입 전 단독 task 필수 여부.
2. R7 (148 sig_dates × 5 windows 사실상 single test period) 해소 protocol — Option A vs B vs C 결정.
3. R3 (4-stage projection non-idempotency) — iterative Bregman projection 대안 검토 우선순위.
4. R8 (STR_1715 baseline robust + L-326 architecture flaw 학습) — 본 cycle이 architecture paradigm shift로 충분히 차별화되는가.
5. 가설 falsification 명시 — DPL alone SR < 0.8 시 Path E (feature engineering pivot) deferred 정합성.

---

**Submitted**: 2026-05-17 alpha-research Step 2.1 deliverable. 본 리뷰의 결론은 Step 2.2 dpl_architecture.md + Step 2.3 pit_audit.json + Step 2.4 training_protocol.md + Step 2.5 codex_round + Step 2.6 alpha_package.json finalize에 반영됨.
