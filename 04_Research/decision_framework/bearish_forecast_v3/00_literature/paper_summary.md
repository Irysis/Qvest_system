# v3 Paper Summary — 14편 Read Notes

**작성**: 2026-05-24 KST (Session 84)
**Owner**: Q-Lead (도훈)
**Source plan**: `04_Research/decision_framework/bearish_forecast_v3/PLAN.md` v0.4
**Read protocol**: Deep 7 (full read with formulas) + Light 7 (skim with key claims)
**Status**: Phase 1 in progress

---

## Status

| ID | Paper | arxiv | Status | Notes |
|----|-------|-------|--------|-------|
| B1 | Michańków 2025 KOSPI DNN | 2508.18921 | ✅ READ_OK | E01-E05 정정 (Neural Portfolio 36.4%/SR 0.91 paper 부재, LSTM 3-layer 128/64/32 / seq=10) |
| B5 | NGBoost Duan et al 2020 ICML | 1910.03225 | ✅ READ_OK | E06-E08 정정 (NLL 0~10% / UCI tabular only, KR 없음 / i.i.d. assumption) |
| C2 | Neural Lévy SDE 2025 | 2509.01041 | ✅ READ_OK | E09-E10 정정 (jump = Merton/Kou/CGMY, Bates X) / S&P 500 only, portfolio Sharpe ≈ 0 |
| A1 | Adrian-Boyarchenko-Giannone "Vulnerable Growth" 2019 AER | (non-arxiv) | ⚠️ READ_PARTIAL | E12 정정 (US만, β coefficients ACCESS_FAIL) |
| E5 | Christoffersen 2009 "Backtesting VaR" RFS | (non-arxiv) | ⚠️ READ_PARTIAL | E13 cite 명확화 (1998 IER vs 2009 RFS) |
| E6 | Gneiting-Raftery 2007 JASA "Strictly Proper Scoring Rules" | (non-arxiv) | ✅ READ_OK | E14 정정 (sea-level pressure case only, KR empirical 부재) |
| F1 | Conformal TS Forecasting 2025 | 2511.13608 | ✅ READ_OK | E11 정정 (simulated AR/ARMA/GARCH only, real stock 부재) |
| B2 | ESRNN-VAE 2025 Frontiers | (search 필요) | pending | Light read |
| B3 | DeepAR Salinas 2020 | (search 필요) | pending | Light read |
| B4 | TFT Lim-Arık-Loeff 2021 | (search 필요) | pending | Light read |
| A5 | Conformal GaR 2024 | 2411.00520 | pending | Light read |
| E1 | RNN VaR/ES 2024 | (ScienceDirect) | pending | Light read |
| E4 | ES backtest 2024 | 2405.02012 | pending | Light read |
| G1 | KR overnight tail risk 2024 | 2402.07134 | pending | Light read |

---

## ★ B1: Michańków 2025 "Forecasting Probability Distributions of Financial Returns with Deep Neural Networks"

**Citation**: Michańków, J. (2025). arxiv preprint 2508.18921. Submitted to Elsevier 2025-09-03.

### Methodology (요약)

DNN을 사용해 6개 글로벌 equity index의 daily log return 분포 parameter를 직접 forecast. 3종 분포 (Normal / Student-t / skewed Student-t) + 2종 architecture (1D CNN / LSTM) = 6 model-distribution 조합 비교.

**핵심 framework**:
```
r_t = μ(x_t) + σ(x_t) · z_t
z_t ~ D(η(x_t))    where D ∈ {N, St, sSt}, η(x_t) = (μ, σ², ν, ξ)
```

**Loss (custom NLL)**:
```
L(ω) = -(1/n) Σ_t log f_D(r_t; ω)
```

skewed-t는 Fernandez-Steel (1998) transformation. 4 parameter (μ, σ², ν, ξ) LSTM/CNN 마지막 layer가 직접 출력.

**Architecture**:
- **LSTM**: 3-layer 128 → 64 → 32 LSTM cells + dense output (param count) ← **★ Plan v0.4 "2-layer hidden=64" 오류**
- **CNN**: 256 filters / kernel size 2 / pool size 2 / flatten + dense

**Training**:
- Walk-forward expanding window (min 1008 train + 504 test)
- **Sequence length: 10 days** ← **★ Plan v0.4 "60-120 거래일 sliding" 오류**
- 300 epochs + Early Stopping + Adam (lr=0.002 KerasTuner)
- L2 = 0.002, Dropout = 0.02

### Reported Metrics

**Data**: 6 indices (S&P 500 / BOVESPA / DAX / WIG / Nikkei 225 / **KOSPI**), 2000-01-03 ~ 2021-12-31 (2,487 forecasts).

**Distributional eval (KOSPI)**:
| Model | LPS | CRPS | PIT p-value |
|-------|-----|------|-------------|
| CNN-N | 1.3349 | 0.5285 | 2.41e-07 |
| CNN-STD | 1.3147 | 0.5297 | 2.41e-07 |
| CNN-SSTD | 1.3172 | 0.5302 | 2.41e-07 |
| LSTM-N | 1.3240 | 0.5246 | 2.41e-07 |
| LSTM-STD | 1.2961 | 0.5201 | 4.70e-07 |
| **LSTM-SSTD** | **1.2847** | **0.5165** | 5.08e-06 |

- LSTM-SSTD best LPS/CRPS across 6 indices (S&P/Nikkei/KOSPI 확인)
- PIT p-value 대부분 < 0.05 (calibration imperfect)
- KOSPI: PIT 모든 model rejection (calibration challenge ← 도훈 인지)

**VaR backtest (KOSPI 1%)**:
- LSTM-STD: 0.84% (theoretical 1%) — Christoffersen PASS
- LSTM-SSTD: 0.84%, Christoffersen PASS

**Comparison vs GARCH (Table 5)**:
- KOSPI 5% VaR: LSTM-N 5.42% vs AP(SSTD) GARCH 6.15% — DNN closer to theoretical
- KOSPI 1% VaR: LSTM-STD 0.84% vs AP(N) GARCH 0.80% — comparable

### KR Applicability

- **KOSPI 직접 포함** (6 index 중 하나). 2,487 daily forecast walk-forward.
- LSTM-SSTD가 KOSPI에서도 best (LPS 1.2847 / CRPS 0.5165)
- 분포 적합도: skewed Student-t가 N/STD보다 left tail asymmetry 더 잘 포착
- v3 직접 reproduce 대상 — feature는 paper는 return + volatility만 (alt data 없음)

### Limitations (paper-stated)

- 컴퓨팅 비용 vs GARCH
- 변동성 높은 시장 overfitting risk
- 향후: Transformer / xLSTM / quantile-based / trading strategy 평가

### ★ Plan v0.4 사실 검증

| Plan v0.4 claim | Paper 실제 | 일치? |
|----|----|----|
| "KOSPI 포함 6개 지수" | ✅ S&P/BVP/DAX/WIG/Nikkei/KOSPI | ✓ |
| "CNN/LSTM × {Normal, Student-t, skewed Student-t}" | ✅ 6 조합 | ✓ |
| "CRPS 4-15% 개선 vs GARCH (지수별)" | paper Table 5는 **VaR exceedance만 비교** — CRPS는 DNN 내부 비교만. paper 본문 CRPS GARCH 직접 비교 **표현 없음** | ❌ 추정 |
| "Neural Portfolio annual 36.4%, Sharpe 0.91 (OOS 2020-2024)" | **paper에 portfolio backtest / Sharpe 결과 전무**. paper는 distributional eval + VaR backtest만 | **❌ MISATTRIBUTION** |
| "KOSPI skewed Student-t best fit" | ✅ LPS/CRPS best, 다만 PIT p-value reject | △ partial |
| "LSTM 2-layer hidden=64 → FC(4)" | **paper LSTM 3-layer 128/64/32** | **❌ 사실 오류** |
| "Lookback 60-120 거래일 sliding" | **paper sequence length = 10** | **❌ 사실 오류** |
| "Distribution: skewed Student-t" | ✅ + Normal + Student-t 3종 비교 | ✓ |

**결론**: Plan v0.4 §1.5.2 / §1.5.4의 B1 정량 인용 **2건 완전 오류 + 2건 hyperparameter 오류**. 도훈 confirm 필요 — v0.5 amendment로 정정 권장.

### Phase 5a-1 reproduce 권장 spec (paper 정합)

- LSTM 3-layer 128/64/32
- Sequence length 10
- 300 epochs + ES + Adam lr 0.002
- 6 model 비교 (CNN-N/STD/SSTD + LSTM-N/STD/SSTD)
- Distribution: skewed-t 우선 + Normal/Student-t 비교 base
- Walk-forward expanding window min 1008 train + 504 test

### Implementation 참고

Github (paper 저자): https://github.com/jmichankow/deep_learning_probability

---

## B5: NGBoost (Duan et al 2020 ICML, arxiv 1910.03225v4)

**Citation**: Duan, T., Avati, A., Ding, D. Y., Thai, K. K., Basu, S., Ng, A., & Schuler, A. (2020). NGBoost: Natural gradient boosting for probabilistic prediction. ICML PMLR 108.

### Methodology

Gradient boosting을 distributional regression으로 확장. point estimate `E[y|x]`가 아니라 conditional distribution `P_θ(y|x)`의 parameter vector `θ ∈ R^p`를 직접 예측. 3 modular 구성요소 (base learner f / parametric distribution P_θ / proper scoring rule S) 사용자 선택. 핵심 기여: multiparameter boosting training dynamics 안정화에 ordinary gradient 대신 **Natural Gradient (Riemannian geometry 기반)** 사용.

**Key equations**:
- Log score: `L(θ, y) = -log P_θ(y)` (Eq 2)
- CRPS: `C(θ, y) = ∫_{-∞}^y F_θ(z)² dz + ∫_y^∞ (1 - F_θ(z))² dz` (Eq 3)
- Natural gradient: `∇̃ S(θ, y) ∝ I_S(θ)^{-1} ∇ S(θ, y)` (Eq 7) — `I_S(θ)` = Fisher Information for MLE, L² metric for CRPS
- MLE Fisher: `I_L(θ) = E_{y∼P_θ} [∇L ∇L^T]` (Eq 9)

**Algorithm**:
```
θ^(0) ← arg min_θ Σ_i S(θ, y_i)   # marginal init
for m = 1 ... M:
  g_i^(m) ← I_S(θ_i^(m-1))^{-1} ∇ S(θ_i^(m-1), y_i)
  fit base learner f^(m) to {(x_i, g_i^(m))} (per component of θ)
  ρ^(m) ← line search
  θ_i^(m) ← θ_i^(m-1) - η (ρ^(m) · f^(m)(x_i))
```

### Reported Metrics (UCI tabular, Table 1)

| Dataset | NGBoost NLL | Best NLL | Δ |
|---|---|---|---|
| Boston (N=506) | 2.43±0.15 | Deep Ensembles 2.41±0.25 | -0.8% (NGBoost slight worse) |
| Concrete (N=1030) | 3.04±0.17 | tie | 0% |
| Energy (N=768) | 0.60±0.45 | Concrete 0.66±0.17 | +9.1% (NGBoost best) |
| Naval (N=11934) | -5.34±0.04 | Concrete -5.87±0.05 | best Concrete |
| Power (N=9568) | 2.79±0.11 | ≈tie all | 0% |
| Protein (N=45730) | 2.81±0.03 | NGBoost best | +0~2.8% |
| Wine (N=1588) | 0.91±0.06 | NGBoost best | +0~13% |
| Yacht (N=308) | 0.20±0.26 | NGBoost best | large gap |
| Year MSD (N=515K) | 3.43 | Deep Ensembles 3.35 | best DE |

**Range 0~10% best case** (Yacht outlier 제외). v0.4 "5-15%" over-statement.

### Ablation (Table 2)

Natural gradient 사용이 핵심 — 2nd-Order alternative 보다 우월 (Boston: NGBoost 2.43 vs 2nd-order 3.57).

### KR / Equity Applicability — v0.5 정정

- ❌ **Paper 자체 금융 dataset 없음** (UCI tabular only)
- ❌ **시계열 적용 시 i.i.d. assumption (paper Section 5 미해결)** — purging/embargo CV 별도 implement 필요
- ✅ 분포 parameter (μ, log σ) 직접 출력 → KR heteroscedastic 분포 추정 가능
- ✅ CRPS scoring rule도 지원 → tail risk 직접
- ✅ Tabular feature 풍부한 KR equity panel에 적합

### Limitations

- i.i.d. assumption
- p² scaling per observation (Fisher inversion)
- Misspecification 일관성 미해결
- p parameters → p base learners per stage cost

---

## C2: Neural Lévy SDE (Wang-Rachev 2025, arxiv 2509.01041)

**Citation**: Wang, Z., & Rachev, S. T. (2025). Neural Lévy SDE for State-Dependent Risk and Density Forecasting. arXiv:2509.01041 (Sept 2025).

### Methodology

**Brownian diffusion + state-dependent Lévy jump process**를 neural network로 통합 parameterize. drift μ_θ, diffusion σ_θ, jump intensity λ_θ, jump size dist g(·|φ_θ) 4 component 모두 observable state X_t 함수로 학습. State vector: lagged returns, RV + **complexity measures (permutation entropy, RQA determinism)**. Shared encoder + multi-horizon heads (1D/1W/2W/1M).

**SDE**:
```
dY_t = μ_θ(X_t) dt + σ_θ(X_t) dW_t + dJ_t
J_t = Σ_{k=1}^{N_t} Z_k    where N_t ~ Poisson(λ_θ(X_t)), Z_k ~ g(·|φ_θ(X_t))
```

**v0.5 정정 (E09)**: jump distribution = **Merton 1976 (Gaussian mix) + Kou 2002 (double exponential) + CGMY 2002 (Lévy)** 지원. **Bates 2008 paper 본문 인용 부재**.

**Architecture**: shared encoder feedforward 2 hidden × 64 + ReLU; multi-horizon heads small NN (one hidden layer) per h ∈ {1D, 1W, 2W, 1M} → output (μ, σ, λ, φ). Softplus 양의 제약 on σ/λ. Monotonicity: σ, λ ↑ as entropy ↑ / DET ↓.

**Training**: (1) Pretrain diffusion head with BV signal, (2) Joint quasi-MLE with truncated compound Poisson (K_max=3), (3) Hyperparameter tune.

### Reported Metrics (S&P 500 500 stocks, 2005-2024, test 2020-2024)

**Daily forecast (1D)**:
- NLL: NeuralLevy **2.598 (best, in MCS)** vs GJR 2.456 / Diffusion-only NN 2.445 / EGARCH 1.773
- CRPS: NeuralLevy **0.01028 (best)** vs GJR 0.01049 / Merton 0.01058 / EGARCH 0.03522
- **vs best baseline: log score +5.77%, CRPS +1.96%**
- DM (Diebold-Mariano) p<10^{-50} for all baselines vs NeuralLevy
- Berkowitz p_μ = 7.68×10^{-7} REJECT (sample n=143,016 너무 큼)

**Weekly forecast (1W)**:
- NLL: NeuralLevy 2.097 vs Diffusion-NN 2.025
- CRPS: NeuralLevy 0.01709 vs Diffusion-NN 0.01996
- **vs best baseline: log score +3.60%, CRPS +14.36%**

**VaR/ES 1W (140 weeks, 95%, 99%)**:
- 95% level: neural / diffusion 모두 **0 breaches** (over-conservatism — Kupiec REJECT)
- 95% risk parity: 2.86% (target 5%), pass
- 95% SPY: 1.43% (Kupiec p=0.023 mild reject)
- 99% level: 모두 pass

**Portfolio result (Section 10)**: **Sharpe ≈ 0, IR ≈ -1.0 vs SPY**. paper 명시: hard risk gate ↔ 0 breach ↔ Kupiec REJECT (trading mechanics 한계).

### KR / Equity Applicability — v0.5 정정 (E10)

- ❌ **Paper 자체 KR 데이터 없음** (S&P 500 only)
- "methodology applies to other asset classes" (Section 3.1) — KR 적용 가능 **명시만**, empirical 결과 부재
- KR 적용 시 주의: BV/RV decomp 안정성 / permutation entropy embedding dim
- **Trading rule 단독 위험**: Sharpe ≈ 0, paper의 distributional forecast는 우수하나 portfolio implementation은 미흡 — KR 적용 시 별도 trading rule 설계 필수

### Limitations

- US S&P 500 only
- Quasi-MLE K_max truncation 의존
- Permutation entropy / DET window length 의존 (adaptive 미구현)
- Berkowitz universally REJECT (sample 너무 큼)
- Portfolio Sharpe ≈ 0 vs SPY
- Self-exciting Hawkes / rough volatility / Bayesian 미통합

---

## F1: Conformal TS Forecasting (Stocker et al 2025, arxiv 2511.13608)

**Citation**: Stocker, M., Małgorzewicz, W., Fontana, M., & Ben Taieb, S. (2025). A Gentle Introduction to Conformal Time Series Forecasting. arXiv:2511.13608v1.

### Methodology

Classical Conformal Prediction (CP)은 distribution-free finite-sample coverage 보장 but **exchangeability assumption 의존**. 시계열은 temporal dependence + distribution shift → exchangeability 위배. Review는 4 family로 non-exchangeable CP 분류 (Reweighting / Refreshing / Adapting Coverage / Blocking).

**Standard Split CP** (Section 1):
- Non-conformity score: `s(X_i, Y_i) = |Y_i - μ̂(X_i)|`
- Empirical quantile: `q̂_{1-α} = quantile_α of S_cal`
- Prediction set: `Ĉ_{1-α}(X_{T+1}) = [μ̂(X_{T+1}) ± q̂_{1-α}]`

**4 family algorithms**:
- **WCP (Weighted CP)**: `q̂^{(w)} = inf {t : Σ w̃_i 𝟙{s_i ≤ t} ≥ 1-α}`, weights w_i ∝ ρ^{t_m - t_i} (exponential decay) or sliding window or learned (Hop-CPT)
- **EnbPI (Ensemble Batch PI)**: M=25 bootstrap ensemble + OOB residuals + sliding refresh δ
- **ACI (Adaptive Conformal Inference)**: `α_{t+1} = α_t + γ(α - e_t)` (Gibbs-Candes 2021), variants AgACI / Conformal PID
- **Block CP**: permutation on blocks (size B), Split-BCP trains μ̂ once

**Coverage theorem (A.3.1, A.4.1)**:
```
P(Y_i ∈ C_{1-α}(X_i)) ≥ 1 - α - ε_cal - ε_train - δ_cal
```
β-mixing slack: ε_train = β(i - n_train), ε_cal via β(a) + n_cal.

### Reported Metrics (4 simulated DGPs × R=50 runs, n=900 split 300/300/300, target 1-α=0.9)

**v0.5 정정 (E11)**: paper actual은 **simulated DGP만** — real-world stock data 결과 부재.

1. **AR(1) / ARMA(1,1) / GARCH(1,1)** — stationary β-mixing:
   - SCP / WCP / ACI / EnbPI: coverage ≈ 0.9 (valid)
   - EnbPI: wider intervals (bootstrap cost)

2. **Mean shift (t*=601 abrupt break)** — non-exchangeable:
   - **SCP drop to ~0.84** (target miss ~6%)
   - WCP-window (last 50) ~0.81 (fail)
   - **ACI / EnbPI / WCP-exp/linear maintain ~0.9 (적응 성공)**

### KR / Equity Applicability

- ❌ Paper real-world stock 결과 없음 (simulation only)
- ✅ GARCH(1,1) DGP 결과 → KR equity volatility clustering에 적용 가능
- ⚠️ KR regime switching (bull→bear) ↔ SCP 실패 가능 → **ACI 또는 EnbPI 권장 (Cycle 50 bear date audit 부합)**
- Conformal Risk Control (CRC, Angelopoulos et al 2023) — KR downside CVaR loss에 직접 적용 가능

### Limitations

- Univariate focus (multivariate future work)
- Simple AR-LS base forecaster
- Coarse hyperparameter sweep (γ, s, ρ, B 민감도 미검증)
- Locally / strongly non-stationary process simulation 미포함
- Hop-CPT / AgACI / Conformal PID advanced variants 미실험

---

## A1: Vulnerable Growth (Adrian-Boyarchenko-Giannone 2019 AER)

**Citation**: Adrian, T., Boyarchenko, N., & Giannone, D. (2019). Vulnerable growth. AER 109(4), 1263-1289. DOI: 10.1257/aer.20161923. (Earlier: FRBNY Staff Report 794, Oct 2016.)

**v0.5 정정 (E12)**: paper PDF paywalled (AER 본문 + sr794 둘 다 access fail). Framework은 secondary sources로 확보, specific Tables 3-4 β coefficients **ACCESS_FAIL**.

### Methodology (secondary sources)

GDP growth conditional distribution을 financial conditions 함수로 **quantile regression** 추정. Mean growth 단일 점이 아닌 full distribution (특히 lower tail). Financial stress 증가 시 **conditional volatility 증가 + conditional mean 감소** 동시 발생 → downside risk asymmetric amplification.

**Specification (Eq 1, secondary)**:
```
Q_{y_{t+h}}(τ | x_t) = β_0(τ) + β_1(τ) y_t + β_2(τ) NFCI_t
```
- y_{t+h}: GDP growth h quarters ahead (h ∈ {1, 4})
- NFCI_t: National Financial Conditions Index (Chicago Fed)
- τ ∈ {0.05, 0.25, 0.50, 0.75, 0.95}

**Estimation**: Koenker-Bassett 1978 quantile loss `ρ_τ(u) = u(τ - 𝟙{u<0})`.

**Skewed t fit (Azzalini-Capitanio 2003)**: conditional density `f(y_{t+h}|x_t)` from quantile estimates (location μ, scale σ, shape α, kurtosis ν). 좌측 tail이 NFCI ↑ 시 widen.

**GaR**: `GaR_α = Q_{y_{t+h}}(α | x_t)`.

### Reported Metrics — secondary recall only

- US 1973Q1-2015Q4
- NFCI는 lower quantile (τ ∈ {0.05, 0.10})에 강한 영향, upper quantile (τ=0.75) 약함 → asymmetric downside amplification
- Out-of-sample density forecast: GaR > Gaussian VAR 특히 tail prediction에서 (log score / CRPS / PIT)
- **Specific β_1(τ), β_2(τ) coefficients ACCESS_FAIL — paywalled**

### KR Applicability

- 직접 KR 적용 가능: KR NFCI proxy 구축 (KOSPI vol + 회사채 spread + KRW vol 등)
- **Paper 자체 US만 — KR/cross-country 결과 부재** (IMF subsequent paper 별도 cite 필요)
- GDP downside risk → equity bear market 매핑은 추가 step

### Limitations

- US only
- Quantile crossing 가능성
- NFCI 정의 의존
- h>4Q wider but identification 약함
- Real-time NFCI 시점 차이

---

## E5: Christoffersen 1998/2009 — cite 명확화 필요

**v0.5 정정 (E13)**: PLAN.md "Christoffersen 2009 RFS" 인용은 다음 둘 중 하나일 가능성:
- (a) **Christoffersen 1998 IER "Evaluating Interval Forecasts"** — 가장 널리 인용되는 VaR backtest framework (UC/Independence/CC test)
- (b) Christoffersen 2009 RFS review/extension paper (검증 안 됨)

**v3 진행 시 (a) 1998 IER로 인용 권장 (UC/CC test framework standard)**.

### Methodology (1998 IER, secondary sources)

VaR / prediction interval quality 두 측면 test:
1. **Unconditional coverage (UC)**: empirical breach rate = nominal α
2. **Independence (Markov)**: breach 시간 독립 (no clustering)
3. **Conditional coverage (CC)**: 1+2 결합

Breach indicator: `I_t = 𝟙{Y_t < VaR_α(t)}`, ideally i.i.d. Bernoulli(α).

**Kupiec POF (UC test)**:
```
LR_UC = -2 log[ (1-α)^{n_0} α^{n_1} / ((1-π̂)^{n_0} π̂^{n_1}) ] ~ χ²(1)
π̂ = n_1 / (n_0 + n_1)
```

**Independence test (Markov)**:
```
LR_IND = -2 log[ L(π̂_2) / L(π̂_1) ] ~ χ²(1)
H_0: π_{01} = π_{11}
```

**Conditional Coverage**: `LR_CC = LR_UC + LR_IND ~ χ²(2)`

### KR Applicability

- KR equity VaR backtest 표준 (거의 모든 risk model validation)
- v3 bearish probability forecast → breach indicator 정의 가능
- 한계: 적은 breach count (n_1 < 10) test power 낮음 — KR 5년 daily (~1250 obs) 95% target ~62 breaches (수용 가능)

### Limitations

- Markov 1차 의존만 detect
- Tail magnitude 정보 미사용 (ES backtest 별도)
- Small sample bias (Christoffersen-Pelletier 2004 개선)

---

## E6: Gneiting-Raftery 2007 JASA "Strictly Proper Scoring Rules"

**Citation**: Gneiting, T., & Raftery, A. E. (2007). Strictly proper scoring rules, prediction, and estimation. JASA 102(477), 359-378. (Review)

### Methodology (full read OK)

Probabilistic forecast P evaluation scoring rule S(P, y) theory. **Proper** scoring rule: forecaster가 honest 보고 incentive (true Q가 expected score 최대화). **Strictly proper**: maximum unique. Various scoring rules (logarithmic, quadratic, spherical, CRPS, energy score) unify with convex function / Bregman divergence.

**Proper definition (Eq 1)**: `S(Q, Q) ≥ S(P, Q)` for all P, Q ∈ 𝒫.

**Common scoring rules**:
- Logarithmic (Eq 19): `LogS(p, ω) = log p(ω)` — KL divergence associate
- Quadratic / Brier (Eq 18): `QS(p, ω) = 2p(ω) - ||p||²₂`
- **CRPS (Eq 20)**: `CRPS(F, x) = -∫_{-∞}^∞ (F(y) - 𝟙{y≥x})² dy`
- **CRPS kernel form (Eq 21, Baringhaus-Franz)**: `CRPS(F, x) = (1/2) E_F|X-X'| - E_F|X-x|`
- Closed-form Gaussian: `CRPS(N(μ,σ²), x) = σ[1/√π - 2φ((x-μ)/σ) - ((x-μ)/σ)(2Φ((x-μ)/σ)-1)]`
- **Energy score (Eq 22)**: `ES(P,**x**) = (1/2)E||X-X'||^β - E||X-x||^β`, β ∈ (0,2)
- Interval score (Eq 43): width + miss penalty
- Quantile score (Eq 41): `S(r;x) = (x-r)(𝟙{x≤r} - α)`

### Reported Metrics — sea-level pressure NA Pacific Northwest case study (n=16,015)

**v0.5 정정 (E14)**: paper는 review/theory + sea-level pressure 6 month case study만. **KR empirical 부재**.

Inflation factor r* by scoring rule (Table 3):
- Quadratic (QS): r* = 2.18
- Spherical (SphS): r* = 1.84
- Logarithmic (LogS): r* = 2.41
- CRPS: r* = 1.62
- **Linear (LinS, improper)**: r* = 0.05 (artificially low — improper trap)
- **Probability (PS, improper)**: r* = 0.02

→ Proper scoring rules (QS/SphS/LogS/CRPS) yield r* > 1 (raw ensemble underdispersion 1.55). Improper (LinS/PS) near zero (delta-function-like). **핵심 경고: improper scoring rule은 misleading**.

### KR Applicability

- 모든 KR distributional forecast eval 표준
- Log score = NLL (NGBoost / Neural Lévy / Conformal 모두 사용)
- CRPS = forecast verification 표준
- Energy score = multivariate KR cross-section
- Interval score = KR 95% VaR quality (coverage + width)

### Limitations

- 2007 — 이후 conformal / kernel score 발전 미포함
- Forecast evaluation framework only — forecast 산출 model 가이드 없음
- Skill score (relative) 자주 improper (Section 2.3) — caution
- Local scoring rule = logarithmic only (locality + propriety 조합 제한)

---

## 종합 — Plan v0.5 Phase 1 verification 결과

**12건 사실 오류 정정**: AMENDMENT_v0.5.md Section B (E01-E14 정정안 + B1 §1.5.2 / §1.5.4 / §5.3.4 PLAN.md 본문 반영 완료).

**recurring lesson** (memory `feedback_paper_cite_verification.md`): paper-cite 정량은 paper-direct verification 의무. Chain of cites / AI-generated summary 단독 사용 금지.

**ACCESS_FAIL** (subsequent verification 필요):
- A1 specific Tables 3-4 β coefficients (paywalled — university library access)
- E5 Christoffersen 2009 RFS vs 1998 IER cite 명확화 (v0.5 권장: 1998 IER)

---

## Light read 7편 (Phase 1' pending)

도훈 confirm 후 Phase 1' Light read 진행 권장. Hallucination 패턴 검증 동일 protocol 적용 (paper-direct + Section/Table 명시 의무).

대상:
- B2 ESRNN-VAE 2025 Frontiers
- B3 DeepAR Salinas 2020
- B4 TFT Lim-Arık-Loeff 2021
- A5 Conformal GaR 2024 arxiv 2411.00520
- E1 RNN VaR/ES 2024 ScienceDirect
- E4 ES backtest 2024 arxiv 2405.02012
- G1 KR overnight tail risk 2024 arxiv 2402.07134

---

## Change log

- 2026-05-24 Session 84 v0.1 — Q-Lead read B1 완료 + 사실 검증 4건 오류 발견 + skeleton 작성.
- **2026-05-24 Session 84 v0.2** — Phase 1 Deep 7편 통합 완료 (B1 Q-Lead direct + B5/C2/F1/A1/E5/E6 subagent). PLAN.md v0.5 amendment 적용 + E01-E14 12건 정정 반영. ACCESS_FAIL 2건 명시 (A1 β coefficients / E5 cite).
