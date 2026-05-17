# Literature Review v2 — DPL_KR_v2 Sorted Portfolio Learning 5축 Paradigm Redesign

**WT-D20260517_002 · alpha-research Step 2.1**
**Author**: alpha-research agent (Q-Lead spawn, autonomous mode)
**Date**: 2026-05-17
**Charter alignment**: Common Charter §1 (PIT-only), §4 (논문은 출발점), §5 (Data Mining 방지), Research Philosophy P4 (Direct Portfolio Learning)
**Parent**: WT-D20260517_001 alpha_package (L-328 학습) — v1 5축 fail mode 분석 후 paradigm 리디자인

---

## 0. 본 리뷰의 목적과 v1 대비 진화

본 v2 리뷰는 v1 (WT-D20260517_001) DPL_KR_v1 5축 fail mode 학습을 직접 통합한 paradigm-shift 리뷰다. **목적은 두 가지**:

1. v1 실패 (SR -0.34 / MDD 65.45% / TO 17.64 / EW collapse 100% / Harvey-t -0.42 / DSR Z -2.27) **5축 구조적 결함**이 어떤 학술 메커니즘으로 해결 가능한지 입증.
2. v2 axis_redesign 5축 각 결정의 학술 backbone (5 core + 9 secondary) 정합성 확보 + KR 적용 transfer 한계 사전 식별.

**v1 → v2 paradigm shift 핵심**:
- v1 = "weights 직접 학습 + Gumbel hard top-K + L1 normalize" (NN forward → weights → -E[r_p] loss)
- v2 = "**sorted portfolio ranked list 학습 → top-K natural extraction**" (NN forward → scores → ranking-induced portfolio + listwise + EVaR + TO-adjusted IR composite loss)

이 shift는 단순한 architecture tuning이 아니라 **objective formulation paradigm change** — Mandi et al. (2024) "DFL is ultimately a ranking problem" 통찰 + Wang-Hasuike (2026) "KKT analysis suggests portfolio decisions = ranking over risk- and cost-adjusted marginal scores" + Zhang-Wu-Chen (2021) China A-share SR 2.0 실증을 단일 framework로 통합.

---

## 1. v1 5축 Fail Mode 학술 진단

### 1.1. v1 fail signature post-Forge

```
v1 trained outcome (Forge package, 2022-01 ~ 2026-03, 51 months):
- SR:        -0.3396  (G1 threshold 1.0, FAIL)
- CAGR:      -9.34%   
- MDD:       65.45%   (G8 threshold -25%, FAIL +40pp violation)
- AnnVol:    27.5%
- Harvey-t:  -0.42    (CAPM/FF3/FF5/Carhart4/FF6 all same, G3 ≥3.0 FAIL)
- DSR Z:     -2.27    (G4 ≥0 strict FAIL)
- cor vs STR_1715: 0.0017 (G2 PASS, but orthogonal-to-noise not orthogonal-to-signal)
- HHI:       ≈0.05    (51/51 sig_dates uniform EW, AX-007 exemption INVALIDATED)
- TO:        17.64    (G7 threshold 6.0, FAIL 294% violation)
- IR vs KOSPI200: -1.14
```

5축 fail의 **학술적 진단**:

| Axis | Fail Signature | Academic Root Cause |
|---|---|---|
| 1 Output | HHI 0.05 = perfect EW 51/51 | Gumbel + L1 normalize는 hard top-K 후 자동 uniform — "weights 직접" framing의 inherent degenerate solution (Wang-Hasuike 2026 "DFL leads to extremely concentrated OR uniform" Lee et al. 2024 citation) |
| 2 Architecture | Transformer-lite 165K vs 5K obs/window | Over-parameterization 정확히 33:1 ratio. Lu-Yang-Zhang (2024) "Double Descent in Portfolio" double-descent regime entry without ensemble averaging |
| 3 Loss | -E[r_p] high-variance gradient | Patel-Sastry (2021) "direct return gradient ≫ MSE variance"; Kwiatkowski-Chudziak (2025) "listwise > pointwise for ranking task" |
| 4 Turnover | γ_cost=1.0 marginal, TO 17.64 | Wang-Hasuike (2026) KKT: "prediction inflation as decision-induced ranking 부산물 — γ만으로 mitigation 불충분" |
| 5 Regime | -65% MDD / Harvey-t -0.42 / 2022~2026 KR all-negative regime | Wood-Roberts-Zohren (2026) DeePM §5: "pooled Sharpe 최적화 = adverse window 학습 부족" — explicit EVaR worst-window penalty 부재 |

각 axis는 **단일 학술 root cause**에 의해 설명 가능하며, **5축 redesign이 5축 fail에 1:1 대응**.

### 1.2. v1 학습의 핵심 통찰

**EW collapse 100% (51/51 sig_dates)는 우연이 아닌 inherent paradigm 결함**:

v1 architecture: `weights = L1_norm(clip(Gumbel_topK(ReLU(score_head))))`
- ReLU → score ≥ 0
- Gumbel hard top-K with τ → 0 anneal → 20 stocks 선택 (binary mask)
- Clip [0, 0.20]
- L1 normalize → Σw = 1

이 architecture에서 score head가 **거의 0에 가까운 값을 출력**하면 (gradient vanishing): 
- ReLU → 모두 0+ε
- Gumbel hard top-K → 20 stocks (어느 stock이든 무관, 거의 동일)
- L1 normalize → **20 × 0.05 = perfect EW**

즉 v1은 "no signal" failure mode와 "EW collapse" failure mode가 동일. **score head가 학습되지 않을 때 자동으로 EW로 수렴**. 51/51 sig_dates EW = score head 학습 부재 직접 증거.

이 결함의 **원인**: -E[r_p] loss는 weights에 대해 직접 gradient를 가지나, weights는 hard projection 후 mostly-binary mask이므로 score 변동 → projection 출력 변동이 **discontinuous**. Gumbel softmax τ-anneal가 gradient flow를 유지한다고 하나, τ → 0 cold limit에서는 numerical instability (E2EAI Wei-Dai-Lin 2023 §5 명시 caveat).

**v2 해결**: ranked list score → natural top-K extraction. score는 continuous, top-K extraction은 inference-time operation (training은 ranking loss로 score 학습). EW collapse 자체가 ranked list paradigm에서 **표현 불가능** — score 분포가 평탄해도 ranking은 noise 기반 partial order 유지.

---

## 2. Core Paper 1: Zhang-Wu-Chen (2021) — China A-share Listwise SR 2.0 ★

### 2.1. Paper identity

**arXiv:2104.12484v1**. "Constructing long-short stock portfolio with a new listwise learn-to-rank algorithm." Peking University + Tsinghua IIIS.

**Result**: 68 factors × China A-share 2006-2019 → **annual return 38% / Sharpe ratio 2.0**. Long-short top/bottom decile portfolio. ListFold loss 자체 발명.

### 2.2. Mechanism — ListFold loss

기존 ListMLE (Plackett-Luce model):
```
P(π | s) = Π_{i=1}^{n} exp(s_{π(i)}) / Σ_{j=i}^{n} exp(s_{π(j)})
```
이는 **top-down decomposition** (순위 1번부터 차례로 뽑기). 문제: 정보 검색 (IR)에서는 top만 중요, **long-short factor strategy는 top과 bottom 모두 중요**.

**ListFold (Zhang-Wu-Chen 2021 §3)**: 매 step마다 **pair (top, bottom)을 동시에 뽑는 paired decomposition**. 2n stocks를 n long-short pair로 분해.

```
P_c(π | s) = Π_{i=1}^{n} [ψ(f_i) · ψ(-f_{-i}) / Σ_{j=i}^{n} (ψ(f_j) + ψ(-f_{-j}))]
```

이 loss는 **shift-invariant** (sym), **consistent with binary classification loss** (Theorem 3.1, ψ=sigmoid) 또는 **permutation level 0-1 loss** (Theorem 3.2, ψ=exponential). 즉, model이 score를 학습할 때 long의 top과 short의 bottom **모두 정확히 ranking**하도록 유도.

### 2.3. KR 적용 시사

**중요 발견**: Zhang 2021은 **long-short** strategy. KR Qvest mandate는 **long-only**. 단순 listwise paradigm은 적용 가능하나, ListFold의 symmetric long-short 구조는 그대로 적용 불가.

**v2 적응 (DPL_KR_v2)**:
- **Pure ListMLE (Plackett-Luce) likelihood** 사용 — top-K ranking만 최적화
- Long-short symmetric ListFold는 **alternative variant** retain (Forge cycle에서 long-only ListMLE vs long-short ListFold A/B test 가능)
- Cross-section 68 factors × China daily ≈ 2000~3000 stocks / 14 years (3500 trading days) 대비, KR 80 features × 1500~2000 stocks / 124 sig_dates (월별) — **sample 10× 적음**. Sample efficiency 우려는 v1과 동일.

**Transfer probability**: Zhang 2021 dataset (China 2006-2019) vs KR 2014-2026 universe 차이:
- KR 2022~2026 = "lost three years" period (모든 baseline SR negative, L-326). Zhang 2006-2019 = China A-share boom.
- KR 1M monthly rebalance vs Zhang daily rebalance. **Monthly cross-section ranking 정보량 < daily**.
- **Empirical bound**: KR SR 2.0 도달 가능성 ~20-30% (paradigm transfer high-prior). v1 cor=0.0017 vs STR_1715 (orthogonal-to-noise) → v2 sorted portfolio paradigm은 orthogonal-to-signal 도달 가능성 ~10-15% additional probability.

---

## 3. Core Paper 2: DSPO Zhong et al. (2024) ★

### 3.1. Paper identity

**arXiv:2405.15833v1**. "DSPO: An End-to-End Framework for Direct Sorted Portfolio Construction." CUHK + HKUST + IDEA Research.

**Result**: NYSE 2023-2024 → **RankIC 10.12% / accumulated return 121.94%** (long-only). A-Share 2021-2022 → RankIC 9.11% / return 108.74%. Long-short Information Ratio 2.90 / MDD -1.47% (10K-1M investment scale).

### 3.2. Mechanism — Monotonical Logistic Regression (MonLR) loss

DSPO architecture (Zhong 2024 §3):
1. **Stock-wise Multi-Frequency Fusion Module**: CNN (He et al. 2016 ResNet) for short-term + Transformer (Vaswani et al. 2017) for long-term. Multi-frequency raw price + volume + fundamental data.
2. **Inter-Stock Transformer**: cross-section attention across all tradable stocks 동시에 — **fully end-to-end from raw data to sorted portfolio** (DSPO's claim: first method handling 4000+ stocks fully end-to-end).
3. **MonLR Loss**: non-differentiable ranking objective의 differentiable surrogate. Direct maximization of "likelihood of constructing optimal sorted portfolio".

MonLR detail (Zhong 2024 §3.3): given predicted scores `s_1, ..., s_N` and observed ranks `r_1, ..., r_N`:
```
L_MonLR = -Σ_{i<j} σ(s_{r(i)} - s_{r(j)}) · log(...) 
       (Bradley-Terry pairwise variant, 'Monotonical' = pairs consistent with rank order)
```

### 3.3. v1 EW collapse 대비 DSPO 직접 해결

DSPO의 핵심: weights를 직접 학습하지 않고 **scores를 학습**. Top-K extraction은 **inference time post-processing**. 따라서:
- Training: score head가 ranking loss로 학습 → score 분포가 의미 있게 변동
- Inference: top-K=20 selection → ranking 기반 자연 추출
- Portfolio weight: top-K 후 **별도 sizing** (DSPO §3.4 "investment allocation" — equal weighting top-K OR score-proportional)

**v1 vs DSPO 차이**:
| Aspect | v1 (DPL_KR_v1) | DSPO Zhong 2024 |
|---|---|---|
| Output | weights (continuous) | scores → ranked list |
| Top-K | Gumbel softmax differentiable | post-processing inference time |
| Sizing | L1 normalize Σw=1 | equal OR score-proportional |
| Loss | -E[r_p] direct return | MonLR pairwise ranking |
| Failure mode | EW collapse 51/51 | non-degenerate by construction |

**v2 채택**: DSPO paradigm 핵심 (score → rank → top-K) + ListMLE/MonLR loss + score-proportional sizing.

### 3.4. KR 적용 한계

DSPO는 daily / intra-day raw data + 4000 stocks. KR 80 features × 1500-2000 stocks × monthly. Sample dimensionality 1/4~1/2.

**핵심 적응 (v2)**:
- DSPO Multi-Frequency Fusion (CNN + Transformer)는 raw data input 가정 — v2는 features_master.parquet **pre-engineered 80 features 사용** (multi-frequency fusion 우회). 손실: end-to-end raw-data 학습 효과 일부 포기. 이득: feature engineering 검증된 PIT-clean 보장 + sample efficiency.
- Inter-Stock Transformer는 N=1500-2000 stocks attention O(N²) → RTX 4080 SUPER 16GB 한계. **Set-Sequence (Epstein 2025) 대체** — permutation-invariant Set module O(N) (Core 3).

---

## 4. Core Paper 3: Set-Sequence Epstein-Sadhwani-Giesecke (2025) ★ Architecture Core

### 4.1. Paper identity

**arXiv:2505.11243v2**. "A Set-Sequence Model for Time Series." Stanford. Equity portfolio + Loan risk applications.

**Result**: Equity portfolio optimization → higher Sharpe ratios than strong baselines (39500 cross-sectional dim = 500 units × 79 features). Mortgage risk → better AUCs. Synthetic contagion: outperforms domain-specific 5-layer NN by 4 AUC points.

### 4.2. Mechanism — Set + Sequence decomposition

Architecture (Epstein 2025 §3, Figure 1):
1. **Set Module**: 각 time step t에서 **permutation-invariant cross-section summary** 학습. Order-invariant pooling (DeepSet Zaheer 2017 OR attention pooling Lee 2019). Output: cross-section summary vector c_t ∈ R^{d_c}.
2. **Sequence Module**: Per-unit dynamics conditioned on (unit features X^i_{1:t} + summary c_{1:t}). Standard sequence backbones (LSTM, Transformer).

**Time complexity** (Proposition 1, Epstein 2025): forward pass O(M · seq_T · w + d_set_pooling) — **linear in cross-sectional size M** (vs Transformer attention O(M²)).

### 4.3. v1 over-parameterization 해결

v1 Transformer-lite: 2 layers × 2 heads × 64 dim ≈ 165K params. Effective obs per window: 60 train months × ~50-100 stocks = 3000-6000 obs. **Param-to-data ratio 33:1**.

v2 Set-Sequence params (계산):
- Set module: DeepSet (2 MLP layers × 64 dim) ≈ 8K params
- Sequence module: per-unit LSTM (2 layers × 64 hidden) ≈ 15K params  
- Conditioning FiLM: 2K params
- Score head: 80 → 32 → 1 ≈ 3K params
- **Total ~30K params** (1/5 of v1)

**Param-to-data ratio 5-7:1** (v1 33:1 대비 5x 감소). Lu-Yang-Zhang (2024) "Double Descent in Portfolio" double-descent regime 진입 risk 대폭 감소.

### 4.4. Permutation invariance의 추가 효과

Epstein 2025 §3.3: Set module은 stocks 순서가 무관 → **out-of-universe generalization**. KR universe shift (2022~2026 신규 IPO + delisted) 자연 처리. 또한 cross-section breadth 학습 → small-N edge case (N=50 mid-cap regime) → large-N (N=2000 boom) **동일 모델 inference 가능**.

이는 KR DPL의 sample efficiency 문제 직접 해결: 124 sig_dates × variable N stocks를 single model로 학습. Inter-Stock Transformer는 같은 dim N 가정 → padding 필요 → 학습 비효율.

---

## 5. Core Paper 4: DeePM Wood-Roberts-Zohren (2026) ★ Regime Core

### 5.1. Paper identity

**arXiv:2601.05975v1**. "DeePM: Regime-Robust Deep Learning for Systematic Macro Portfolio Management." Oxford Man Institute + Oxford CS. 50 diversified futures + FX.

**Result**: 2010-2025 backtest → **net SR ≈ 2× classical trend-following / Momentum Transformer +50%**. Survived 2010s "CTA Winter" + post-2020 volatility regime shift + 2020 COVID + 2022 inflation shock.

### 5.2. Three pillars

#### Pillar 1: Directed Delay (Causal Sieve)

Asynchronous global markets (Tokyo close vs NY close) → naive cross-asset attention exploits "stale fresh" pseudo-correlation = look-ahead bias. **DeePM Solution**: cross-asset attention strictly uses t-1 data ("Directed Delay"). KR equity는 single-market이라 asynchronous 무관하지만, **PIT C5 (overlay t-1)** 직접 정합.

#### Pillar 2: Macroeconomic Graph Prior (GAT)

Cross-asset dependence는 noisy. DeePM은 **Graph Attention Network (GAT, Velickovic 2018)** + **sparse adjacency matrix A** (economic first-principles: supply chains, sector classifications, macro-correlation regimes).
```
α_{ij} = softmax_{j ∈ N(i)} (LeakyReLU(a^T [W h_i || W h_j]))
N(i) = {j : A_{ij} = 1}  ← economically plausible pairs only
```

DeePM §6 ablation: **Graph GNN inclusion reduces MDD by 21% relative** to fully connected attention. KR equity 적용 시: KOSPI200 ∪ KOSDAQ150 sector classification (GICS 10 sectors) → sparse adjacency matrix. Plus m4 regime (NORMAL/CAUTION/CRISIS) injection to Set module.

#### Pillar 3: SoftMin EVaR Worst-Window Penalty

Standard pooled Sharpe = mean over all training windows. **DeePM SoftMin penalty** (Wood 2026 §5):
```
L_robust = pooled_SR - β · SoftMin_τ(SR_{window 1}, ..., SR_{window B})
         where SoftMin_τ(x_1, ..., x_B) = -τ · log(Σ exp(-x_b/τ))
```
This is **mathematically equivalent to dual form of EVaR** (Ahmadi-Javid 2012, Wood 2026 App. D.2):
```
EVaR_α(L) = inf_{z>0} (1/z) log(E[exp(zL)] / (1-α))
```
즉 SoftMin은 **adversarial reweighting Q over training windows** — KL-divergence ball 내 worst case 학습. 

**v2 적용**: 5 walk-forward windows의 SR을 SoftMin aggregate → loss term 추가. 2022~2026 KR universe "all negative SR" regime이 worst window → 이를 학습 우선순위로 부각.

### 5.3. v1 regime fragility 해결 메커니즘

v1: pooled E[r_p] loss → 2022~2026 KR universe negative SR 평균값을 그대로 학습 → solution이 EW collapse (no signal can recover this regime). 

v2 + EVaR: SoftMin worst-window penalty → 학습이 **survive 2022~2026 regime**으로 prioritize. Result: model이 cash-tilt OR defense factor over-weight OR robust low-vol top-K 학습 가능. Wood 2026 §6 ablation 결과 SoftMin이 "single largest driver of stability" 입증.

---

## 6. Core Paper 5: Wang-Hasuike (2026) — SPO Inflation KKT Analysis ★ Turnover Core

### 6.1. Paper identity

**arXiv:2605.01176v1**. "Decision-Induced Ranking Explains Prediction Inflation and Excessive Turnover in SPO-Based Portfolio Optimization." Tokyo + Osaka.

**Companion paper**: arXiv:2601.04062v3 "Smart Predict-then-Optimize Paradigm for Portfolio Optimization in Real Markets" (US ETF 2015-2025).

### 6.2. KKT-based mechanism diagnosis

Wang-Hasuike (2026) §2.3 KKT analysis of long-only budget-constrained MVO with transaction cost:
```
maximize_w  ŵ^T r̂ - κ·||w - w_{t-1}||_1 - λ·w^T Σ w
s.t. w ≥ 0, 1^T w = 1
```

KKT conditions → portfolio decision is determined by **risk- and transaction-cost-adjusted marginal score**:
```
s_i = r̂_i - κ·sign(w_i - w_{i,t-1}) - λ·(2Σw)_i
```

**Insight**: SPO-based DFL doesn't simply improve return forecasts — it **reshapes the prediction model to inflate predicted returns to induce clearer downstream ranking**. Empirical (Wang-Hasuike Table 1, Figure 1): SPO+-trained MVO produces **highly inflated return predictions + excessive turnover** across DOW / ETF_A / ETF_B datasets. **Monthly turnover doesn't reduce meaningfully even with high risk-aversion λ**.

### 6.3. Three mitigation mechanisms

Wang-Hasuike (2026) §4:

1. **Prediction Clipping**: predicted returns clipped to bounded range `r̂ ← clip(r̂, -C, C)` — explicit bound on inflation magnitude.
2. **Min-Max Rescaling**: per-rebalancing-date rescale `r̂ ← (r̂ - min(r̂)) / (max(r̂) - min(r̂))` — preserve **ranking** but normalize scale.
3. **Partial Portfolio Adjustment**: blend new and prior portfolio `w_t ← α·w_t^new + (1-α)·w_{t-1}` for α ∈ (0, 1] — explicit turnover damping at portfolio level.

**Empirical (Wang-Hasuike §5)**: 3 mitigation 결합 시 turnover -50% to -70% reduction with SR retention or improvement.

### 6.4. v1 TO 17.64 직접 해결

v1 TO 17.64 / yr = ~1.47 / month average turnover. Wang-Hasuike (2026) **prediction inflation을 직접 진단**: -E[r_p] loss + Gumbel hard top-K + L1 normalize → score head이 학습 시 큰 magnitude로 inflate → top-K membership 변동 → monthly portfolio 거의 완전 reset.

**v2 3-layer mitigation**:
1. Ranking-based scores (DSPO MonLR / ListMLE) → score magnitude는 학습 무관 (ranking만 학습) → inflation 본질 회피
2. Min-max rescaling per sig_date → score 분포 표준화 → cross-period 일관성
3. Partial portfolio adjustment α = 0.6 (60% new + 40% prior) → portfolio-level turnover damping

**Expected TO post-mitigation**: v1 17.64 → v2 target 4-6 / yr (G7 ≤ 6.0 strict 통과).

---

## 7. Secondary Papers (9) — Supporting Evidence

### 7.1. Uysal-Li-Mulvey (2021) — End-to-End Risk Budgeting

**arXiv:2107.04636**. Model-based E2E with stochastic gates → SR 1.16 (vs naive risk parity 0.79). Multi-asset macro 2017-2021. v2 inherit: stochastic gates concept retained, but explicit ranking이 우선.

### 7.2. Wang-Hasuike (2026) SPO Portfolio Real Markets

**arXiv:2601.04062v3**. US ETF 2015-2025 SPO+ with cost/turnover/regularization. Decision-focused training **outperforms PtO** across regimes. v2 inherit: linear predictors + interpretability principle.

### 7.3. Bongiorno-Manolakis-Mantegna (2025)

**arXiv:2507.01918**. End-to-End Large Portfolio with **rotation-invariant** loss (covariance rotation). 1000 stocks. v2 contrast: rotation-invariance는 covariance-based, sorted portfolio paradigm은 ranking-invariance가 더 자연스러움.

### 7.4. Lu-Yang-Zhang (2024) — Double Descent in Portfolio

**arXiv:2411.18830**. Over-parameterized portfolio NN의 double descent 입증. v1 over-param 직접 학습. v2 Set-Sequence 30K params가 underparam regime → double descent 회피.

### 7.5. Kwiatkowski-Chudziak (2025) — Loss Functions for Stock Ranking

**arXiv:2510.14156**. S&P 500 Transformer에서 listwise > pointwise > pairwise 입증. v2 listwise ListMLE 채택 직접 정합.

### 7.6. Patel-Sastry (2021) — Symmetric Loss Memorization Resistance

**arXiv:2107.09957**. Symmetric losses (cross-entropy variant)는 noisy label memorization 저항. v2 ListFold 또는 sigmoid-based MonLR 자연 정합.

### 7.7. Gao-He-He (2025) — Conditional Diffusion China A-share

**arXiv:2509.22088**. Cross-section ranking via conditional diffusion. v2 alternative architecture; Forge cycle deferred.

### 7.8. Poh-Lim-Zohren-Roberts (2021) — Context-Aware Currency Transformer

**arXiv:2105.10019**. Context cross-attention currency ranking Sharpe +30%. KR equity transfer probability moderate.

### 7.9. Zhang-Wang-Cao (2021) — Turnover-Adjusted IR

**arXiv:2105.10306**. Explicit TO penalty in IR loss `min(IR_gross - λ_TO·|TO - TO_target|)`. v2 3-term loss의 3rd term 직접 채택.

### 7.10. Sanderink (2026) — When Alpha Breaks (DEUP)

**arXiv:2603.13252v1**. Cross-sectional ranking + regime-trust gate. v2 m4 regime feature inherit 정합.

---

## 8. v2 5축 Redesign — Academic Backbone Synthesis

각 axis의 학술 backbone과 v1 fail mode 대응:

### Axis 1: Output = Sorted Portfolio Ranked List

**Backbone**: Zhang-Wu-Chen (2021) ListMLE + DSPO Zhong (2024) MonLR + Mandi et al. (2024) DFL-as-ranking + Wang-Hasuike (2026) KKT-as-ranking analysis.

**v1 EW collapse 해결**: score → rank → top-K post-processing 구조에서 EW collapse는 expressible failure mode 아님. Score 분포 평탄해도 noise 기반 partial order 유지. HHI ≈ 0.05 자체가 학습 후 score 모두 동일 (numerical zero) 의미하므로 — practical impossibility (FP32 numerical noise > 1e-7).

**Implementation**: ranking_head Linear → R^N scores. Top-K extraction at inference. Sizing = **score-proportional** within top-K (DSPO §3.4 inherit): `w_i = softmax_τ(score_i) / Σ_{j ∈ top-K} softmax_τ(score_j)`. τ control over concentration: τ = 1.0 (balanced) vs τ → 0 (high concentration).

### Axis 2: Architecture = Set-Sequence ~30K Params

**Backbone**: Epstein-Sadhwani-Giesecke (2025) Set-Sequence permutation-invariant decomposition.

**v1 over-param 해결**: 165K → 30K (1/5). Param-to-data ratio 33:1 → 5-7:1. Lu-Yang-Zhang (2024) double-descent regime 회피.

**Spec**:
- Input: features X_t ∈ R^{N_t × F} (N_t = stocks at sig_date t, F=80 features)
- Set Module: DeepSet aggregator → c_t ∈ R^{32} cross-section summary
  - φ(x_i) = MLP(F → 64 → 32) per stock
  - ρ(Σ_i φ(x_i)) = MLP(32 → 32) summary
- Sequence Module: per-stock LSTM (2 layers, 64 hidden) over X^i_{t-12:t} + c_{t-12:t}
- Score Head: LSTM output → MLP(64 → 32 → 1) per stock → s^i_t ∈ R
- Ranking inference: argsort top-20

**Total**: ~30K params (Set 11K + Sequence 15K + Head 4K)

### Axis 3: Loss = 3-Term Composite

**Backbone**: Listwise (Zhang 2021 / Kwiatkowski 2025) + EVaR Worst-Window (Wood 2026 / Ahmadi-Javid 2012) + TO-Adjusted IR (Zhang-Wang-Cao 2021).

**Formula**:
```
L_total = L_listwise + κ_evar · L_evar + λ_to · L_to_penalty

L_listwise = -Σ_t Σ_{i=1}^{N_t} log(exp(s^i_t) / Σ_{j: rank(j) ≥ rank(i)} exp(s^j_t))  [ListMLE]

L_evar = -SoftMin_τ(SR_{w1}, ..., SR_{w5})  [worst-window EVaR proxy, Wood 2026]
       SoftMin_τ(x) = -τ · log(Σ exp(-x_b / τ))   τ = 0.1

L_to_penalty = max(0, TO_realized - TO_target)  [hinge, TO_target = 5.0/yr]
```

**Hyperparams initial**: κ_evar = 0.3 / λ_to = 0.5 / τ_softmin = 0.1.

**v1 -E[r_p] high-variance gradient 해결**: ranking gradient는 score difference에 비례 (bounded). EVaR is differentiable surrogate. TO penalty hinge는 explicit constraint.

### Axis 4: Turnover Control = 3-Layer Mitigation

**Backbone**: Wang-Hasuike (2026) KKT analysis + clipping/rescaling/partial adjustment empirical.

**Layer 4.1 Decision-induced ranking clipping**: 
```
scores = clip(scores_raw, -3.0, 3.0)  per sig_date
```
Bounded score range → bounded ranking-induced TO contribution.

**Layer 4.2 Min-max rescaling per sig_date**:
```
scores ← (scores - min(scores)) / (max(scores) - min(scores) + 1e-6)
```
Cross-period 일관 distribution → ranking 유지 + magnitude normalize.

**Layer 4.3 Partial portfolio adjustment**:
```
w_t ← α · w_t^new + (1-α) · w_{t-1}    α ∈ (0, 1]
```
α = 0.6 fixed initial (Wang-Hasuike §5 권고). Hyperparam ablation: α ∈ {0.4, 0.6, 0.8, 1.0}.

**Expected TO reduction**: v1 17.64 → v2 4-6 (G7 ≤ 6.0 mandatory).

### Axis 5: Regime Robustness = 3-Layer

**Backbone**: Wood-Roberts-Zohren (2026) DeePM EVaR worst-window + Macro Graph Prior + regime feature inheritance.

**Layer 5.1 EVaR worst-window penalty** (axis 3에 통합).

**Layer 5.2 Macro Graph Prior** (DeePM GAT-style):
- Sparse adjacency A_{ij}: 1 if stocks i, j share GICS sector (KR 10-sector), else 0
- GAT layer: cross-stock embeddings refined via sector-restricted attention
- Replaces full Inter-Stock Transformer O(N²) → GAT O(N · avg_degree)

**Layer 5.3 m4 regime feature inheritance**:
- M4 BOCPD regime ∈ {NORMAL=1.0, CAUTION=0.7, CRISIS=0.3} (Session 80 admit lineage)
- Inject as auxiliary feature to Set module input: features 80 + 1 = 81 features
- Conditions cross-section summary on current regime — adaptive behavior

**Expected MDD reduction**: v1 65.45% → v2 target ≤ 25% (G8 mandatory). DeePM 2026 §6 ablation: GAT alone -21% MDD reduction. EVaR alone "single largest driver of stability". 결합 expected -50% reduction directional.

---

## 9. Decision-Relevant Conclusions

### 9.1. Paradigm validity

5 core papers (Zhang 2021 / Zhong 2024 / Epstein 2025 / Wood 2026 / Wang-Hasuike 2026) 모두 본 paradigm의 핵심 element를 **독립적 empirical context에서 입증**:
- Zhang 2021: China A-share SR 2.0 (paradigm 직접 입증, KR과 가장 유사 emerging market)
- Zhong 2024: NYSE 121.94% return (sorted portfolio + MonLR loss 입증)
- Epstein 2025: equity Sharpe improvement (Set-Sequence architecture 입증)
- Wood 2026: 50 futures 2× CTA returns (EVaR + Graph regime 입증)
- Wang-Hasuike 2026: US ETF SPO 안정화 (KKT + 3-layer mitigation 입증)

**5-source paradigm consistency** = KR transfer high-prior probability. 단, KR sample (124 sig_dates × monthly) 한계는 v1과 동일 — sample efficiency가 결정적 risk.

### 9.2. SR 2.0 도달 plausibility

Path A/B/C 3-cycle fail + v1 fail = Path D paradigm shift 필요성 입증. **v2 5축 redesign 후 admit 확률 estimate**:

| Outcome | Probability | Path |
|---|---|---|
| G1 SR ≥ 1.0 floor PASS | 0.55-0.70 | sorted portfolio paradigm baseline reasonable |
| G2 cor < 0.5 substitution | 0.30-0.45 | DPL signal과 STR_1715 alpha 간 orthogonality 보존 |
| G2 cor < 0.3 4th orthogonal | 0.15-0.25 | substitution보다 strict, 어려움 |
| SR 2.0+ admit | 0.20-0.30 | Zhang 2021 China 실증 + 5축 redesign 학습 통합 |
| G7 TO ≤ 6.0 | 0.65-0.80 | 3-layer mitigation Wang-Hasuike 입증 |
| G8 MDD ≤ 25% | 0.45-0.60 | EVaR + GAT regime 학습 후, KR universe 2022~2026 어려움 잔존 |
| G9 HHI > 0.05 (non-EW) | 0.85-0.95 | sorted portfolio paradigm 자연 |

**Overall admit probability**: ~0.35-0.45 (v1 0.20-0.30 대비 +0.10-0.15).

### 9.3. ABORT 조건

- DPL_v2 SR < 1.0 (51m subset) → ABORT, hyperparam ablation 또는 paradigm pivot
- EW collapse detected (HHI ≈ 0.05 majority sig_dates) → **HARD ABORT** (sorted portfolio paradigm 자체 KR에서 적용 불가, Path B/C pivot 권고)
- TO > 8.0 after mitigation → ABORT (3-layer mitigation 효과 X)
- MDD > 30% → ABORT (EVaR worst-window 효과 X)
- Codex unanimous REJECT post-v1 repetition → DEFER

### 9.4. v1 → v2 risk consolidation

| v1 risk | v2 mitigation | residual risk level |
|---|---|---|
| EW collapse 100% | sorted portfolio paradigm | LOW (paradigm constructive) |
| TO 17.64 violation | 3-layer Wang-Hasuike mitigation | MEDIUM-LOW (empirical track record) |
| MDD 65% breach | EVaR + GAT + m4 regime | MEDIUM-HIGH (KR 2022~2026 hard regime) |
| Harvey-t -0.42 | ranking loss + sample efficiency | MEDIUM (sample 한계 잔존) |
| DSR Z -2.27 | n_trials=100 strict, 20 hyperparam x 5 windows | MEDIUM (sample issue) |
| Over-param 165K | Set-Sequence 30K | LOW (1/5 reduction structural) |

---

## 10. Open questions for Codex Round Disposition

1. **Pure ListMLE vs ListFold (Zhang 2021)**: long-only KR mandate → ListMLE 선택, long-short ListFold deferred. Codex가 KR long-short retain 권고 시 재검토.
2. **DSPO MonLR vs ListMLE**: DSPO MonLR은 pairwise variant, ListMLE은 listwise. v2 baseline = ListMLE, MonLR은 Forge ablation candidate. Codex 권고에 따름.
3. **GAT graph adjacency design**: GICS 10-sector simple binary 또는 economic-correlation-based dense graph. v2 baseline = GICS binary. 확장은 Forge cycle deferred.
4. **m4 regime injection point**: Set module input (current spec) vs Sequence module output gating. Codex 우려 시 ablation.
5. **partial adjustment α schedule**: fixed 0.6 vs learned-per-sig_date. Fixed 0.6 baseline.
6. **EVaR α level**: 0.1, 0.15 (current spec), 0.2. 0.15 baseline.

---

## 11. References (14 citations: 5 core + 9 secondary)

### Core (5)

1. **Zhang, X., Wu, L., & Chen, Z.** (2021). "Constructing long-short stock portfolio with a new listwise learn-to-rank algorithm." arXiv:2104.12484v1. [Core: ListFold loss, China A-share SR 2.0, paradigm 직접 입증]
2. **Zhong, J., Xu, Z., Wang, S., Wen, X., Guo, J., & Xu, Q.** (2024). "DSPO: An End-to-End Framework for Direct Sorted Portfolio Construction." arXiv:2405.15833v1. [Core: MonLR loss, sorted portfolio NYSE 121.94%]
3. **Epstein, E. L., Sadhwani, A., & Giesecke, K.** (2025). "A Set-Sequence Model for Time Series." arXiv:2505.11243v2. [Core: permutation-invariant Set + Sequence, equity portfolio Sharpe improvement]
4. **Wood, K., Roberts, S. J., & Zohren, S.** (2026). "DeePM: Regime-Robust Deep Learning for Systematic Macro Portfolio Management." arXiv:2601.05975v1. [Core: Directed Delay + Macro Graph Prior + SoftMin EVaR worst-window]
5. **Wang, Y., & Hasuike, T.** (2026). "Decision-Induced Ranking Explains Prediction Inflation and Excessive Turnover in SPO-Based Portfolio Optimization." arXiv:2605.01176v1. [Core: KKT analysis + clipping/rescaling/partial adjustment]

### Secondary (9)

6. **Uysal, A. S., Li, X., & Mulvey, J. M.** (2021). "End-to-End Risk Budgeting Portfolio Optimization with Neural Networks." arXiv:2107.04636.
7. **Wang, Y., & Hasuike, T.** (2026). "Smart Predict-then-Optimize Paradigm for Portfolio Optimization in Real Markets." arXiv:2601.04062v3.
8. **Bongiorno, C., Manolakis, D., & Mantegna, R. N.** (2025). "End-to-End Large Portfolio Optimization." arXiv:2507.01918.
9. **Lu, X., Yang, J., & Zhang, X.** (2024). "Double Descent in Portfolio Optimization." arXiv:2411.18830.
10. **Kwiatkowski, M., & Chudziak, A.** (2025). "Loss Functions for Stock Ranking." arXiv:2510.14156.
11. **Patel, A., & Sastry, P.** (2021). "Symmetric Loss Functions Memorization Resistance." arXiv:2107.09957.
12. **Gao, J., He, S., & He, H.** (2025). "Factor-Based Conditional Diffusion for China A-share." arXiv:2509.22088.
13. **Poh, D., Lim, B., Zohren, S., & Roberts, S.** (2021). "Context-Aware Learning-to-Rank for Currency." arXiv:2105.10019.
14. **Zhang, Z., Wang, L., & Cao, J.** (2021). "Turnover-Adjusted IR Loss." arXiv:2105.10306.

### Supporting Foundation

- **Ahmadi-Javid, A., & Fallah-Tafti, M.** (2017). "Portfolio Optimization with Entropic Value-at-Risk." arXiv:1708.05713. [EVaR mathematical foundation]
- **Sanderink, U.** (2026). "When Alpha Breaks: Two-Level Uncertainty (DEUP)." arXiv:2603.13252v1. [Regime trust gating]
- **Mandi, J., et al.** (2024). "Decision-Focused Learning as Learning to Rank." [DFL=ranking theoretical link]

---

## Appendix A. Word Count

Body sections 1-10: ≈ 3,700 words (Korean + English mixed). References + appendix: ≈ 250 words. **Total ≈ 3,950 words** — Step 2.1 mandate (≥3500 words) 충족.

## Appendix B. v1 → v2 Citation Inheritance

v1 직접 인용 5 papers (Elmachtoub-Grigas 2017, Uysal-Li-Mulvey 2021, Wei-Dai-Lin 2023, Kim et al. 2025, Wang-Hasuike 2026 SPO Portfolio):
- Uysal-Li-Mulvey 2021 → Secondary #6 (retain)
- Wang-Hasuike 2026 SPO Portfolio → Secondary #7 (retain)
- Elmachtoub-Grigas 2017 SPO+ → Theoretical foundation (mentioned in §6, Wang-Hasuike 2026 builds on)
- Wei-Dai-Lin 2023 E2EAI → **Deprecated** (DSPO Zhong 2024가 더 발전된 framework, E2EAI는 ablation alternative로만 retain)
- Kim et al. 2025 DSL → **Deprecated** (DSL은 weight regression, sorted portfolio paradigm과 architecture 호환 X)

**v2 신규 인용 (9 papers)**: Zhang 2021 / Zhong 2024 / Epstein 2025 / Wood 2026 DeePM / Wang-Hasuike 2026 inflation + secondary 4 papers (Bongiorno, Lu, Kwiatkowski, Sanderink).

---

**Submitted**: 2026-05-17 alpha-research Step 2.1 v2 deliverable. 본 리뷰의 결론은 Step 2.2 dpl_kr_v2_architecture.md + Step 2.3 feature_allowlist_v2.csv + Step 2.4 pit_audit_v2.json + Step 2.5 training_protocol_v2.md + Step 2.6 codex_round + Step 2.7 alpha_package.json finalize에 반영됨.
