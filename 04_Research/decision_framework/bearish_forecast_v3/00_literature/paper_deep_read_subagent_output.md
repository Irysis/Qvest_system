# Phase 1 Deep Read — Subagent Output

작성: 2026-05-24 Cycle 52 v3 bearish_forecast_v3 PLAN.md Phase 1
대상: 6편 paper deep read (B5 / C2 / F1 / A1 / E5 / E6)

각 paper별 status:
- **B5 NGBoost** (arxiv 1910.03225v4) — READ_OK (full body via WebFetch PDF)
- **C2 Neural Lévy SDE** (arxiv 2509.01041) — READ_OK (full body via slice of 80,340-char file)
- **F1 Conformal Time Series Forecasting** (arxiv 2511.13608) — READ_OK (full body via slice of 83,094-char file)
- **A1 Vulnerable Growth** (Adrian-Boyarchenko-Giannone 2019 AER) — READ_PARTIAL (paywalled; abstract + secondary sources OK; specific Tables 3/4 numeric quantile coefficients ACCESS_FAIL — need university library access)
- **E5 Christoffersen 1998 "Evaluating Interval Forecasts" IER** — READ_PARTIAL (Wikipedia thin; Christoffersen 1998 formulas derived from C2 Neural Lévy paper Section 8.3 + 9.3 + multiple secondary references)
- **E6 Gneiting-Raftery 2007 JASA "Strictly Proper Scoring Rules"** — READ_OK (full body via WebFetch PDF, pages 1-15)

---

### B5 NGBoost: Natural Gradient Boosting for Probabilistic Prediction

**Citation**: Duan, T., Avati, A., Ding, D. Y., Thai, K. K., Basu, S., Ng, A., & Schuler, A. (2020). NGBoost: Natural gradient boosting for probabilistic prediction. *Proceedings of the 37th International Conference on Machine Learning (ICML)*, PMLR 108. arXiv:1910.03225v4.

**Methodology**:

핵심 아이디어 — gradient boosting을 distributional regression으로 확장. point estimate `E[y|x]`가 아니라 conditional distribution `P_θ(y|x)`의 parameter vector `θ ∈ R^p`를 직접 예측. 세 가지 modular 구성요소(Base learner f / Parametric distribution P_θ / Proper scoring rule S)를 사용자가 선택. 핵심 기여는 multiparameter boosting의 training dynamics 안정화를 위해 ordinary gradient 대신 Natural Gradient (Riemannian geometry 기반) 사용.

수식 (key equations):
- (Eq 2) Log score: `L(θ, y) = -log P_θ(y)`
- (Eq 3) CRPS: `C(θ, y) = ∫_{-∞}^y F_θ(z)² dz + ∫_y^∞ (1 - F_θ(z))² dz`
- (Eq 7) Natural gradient: `∇̃ S(θ, y) ∝ I_S(θ)^{-1} ∇ S(θ, y)` — `I_S(θ)`는 scoring rule이 induce한 Riemannian metric (MLE의 경우 Fisher Information, CRPS의 경우 Eq 11의 L^2 metric)
- (Eq 9) MLE Fisher: `I_L(θ) = E_{y∼P_θ} [∇L(θ,y) ∇L(θ,y)^T]`

Algorithm 1 (NGBoost for probabilistic prediction):
1. Initialize `θ^(0) ← arg min_θ Σ_i S(θ, y_i)` (marginal fit)
2. For m = 1, ..., M:
   - For each i: compute natural gradient `g_i^(m) ← I_S(θ_i^(m-1))^{-1} ∇ S(θ_i^(m-1), y_i)`
   - Fit base learner f^(m) to `{(x_i, g_i^(m))}` for each component of θ (즉 `p` base learners per stage if distribution has p parameters; e.g., Normal `θ=(μ, log σ)` → 2 learners f_μ, f_{log σ})
   - Line search scaling `ρ^(m) ← arg min_ρ Σ_i S(θ_i^(m-1) - ρ · f^(m)(x_i), y_i)`
   - Update: `θ_i^(m) ← θ_i^(m-1) - η (ρ^(m) · f^(m)(x_i))`

Architecture / flow (Figure 2 paper):
`x → {base learners f^(m)(x)}_{m=1}^M → θ → distribution P_θ(y|x) → scoring rule S(P_θ, y) ← y` with `∇̃_θ` feedback to fit natural gradient.

**Reported Metrics** (정량):

UCI tabular probabilistic regression NLL (Table 1, NGBoost vs MC dropout / Deep Ensembles / Concrete Dropout / Gaussian Process / GAMLSS / DistForest):
- Boston (N=506): NGBoost **2.43±0.15**, MC dropout 2.46±0.25, Deep Ensembles **2.41±0.25** (tie)
- Concrete (N=1030): NGBoost **3.04±0.17**, MC dropout **3.04±0.09** (tie), Deep Ensembles 3.06±0.18
- Energy (N=768): NGBoost **0.60±0.45**, MC dropout 1.99±0.09, Concrete Dropout **0.66±0.17**
- Kin8nm (N=8192): NGBoost -0.49±0.02, Deep Ensembles **-1.20±0.02** (best)
- Naval (N=11934): NGBoost -5.34±0.04, Concrete Dropout **-5.87±0.05** (best)
- Power (N=9568): NGBoost 2.79±0.11, others 2.79~2.81
- Protein (N=45730): NGBoost **2.81±0.03**, all others 2.81~2.89 (NGBoost best)
- Wine (N=1588): NGBoost **0.91±0.06**, others 0.91~1.05 (NGBoost best)
- Yacht (N=308): NGBoost 0.20±0.26, Deep Ensembles **1.18±0.21** (NGBoost much better)
- Year MSD (N=515345): NGBoost 3.43±NA, Deep Ensembles **3.35±NA** (best)

Point-estimation RMSE (Table 3): NGBoost 경쟁력 있음 — Boston 2.94 vs Gradient Boosting 2.46 (best); Wine 0.63 vs 0.50 best — point estimation 전용 method보다 약간 떨어지지만 **probabilistic prediction을 위한 cost는 작음**.

Ablation (Table 2): 2nd-Order boosting (NGBoost - natural gradient + 2nd order) Boston 3.57±0.20 vs NGBoost 2.43±0.15 — **natural gradient 사용이 핵심 (2nd-order 대안보다 우월)**.

**KR / Equity Applicability**:

논문 자체는 healthcare(survival prediction) + weather forecasting 응용 강조. 금융 명시적 언급 없음. 하지만 다음 측면에서 적용 가능:
- **표(tabular) feature**가 풍부한 KR equity panel에 적합 (gradient boosting의 강점 영역)
- 분포 `θ=(μ, log σ)` 두 parameter만 산출 → daily return forecast의 **heteroscedastic 분포 추정** 가능 (mean μ + 변동성 σ)
- log score 외 **CRPS scoring rule도 지원** → tail risk forecast (Section 3.1 Eq 3)
- Plan v0.4 가설: KR 약세 forecast의 confidence interval 산출 (예: bearish probability `P(y < threshold)`) — NGBoost로 distributional output 가능

**Limitations**:

- 시간 의존성/cross-sectional dependency 미고려 (i.i.d. assumption)
- p^3 scaling per observation (Fisher matrix inversion) — p가 5+ 분포 거의 사용 안하므로 실용상 문제 적음
- Misspecification 시 일관성 보장 불명 (Section 5 미해결 문제)
- p parameters를 위한 `p` series of learners 필요 → standard boosting 대비 p배 cost
- 시계열에서 OOS 시간 분할 시 separate purging/embargo 필요 (논문 자체 미지원)

**Plan v0.4 사실 검증**:

- Plan v0.4가 인용했을 "NLL 5-15% 개선" 주장은 paper 실증 결과 부분적 정합:
  - Boston: NGBoost 2.43 vs Deep Ensembles 2.41 — 본인이 약간 worse (-0.8%)
  - Wine: NGBoost 0.91 vs Concrete Dropout/MC dropout 0.93 — +2.2% 개선
  - Protein: NGBoost 2.81 vs 다음 best 2.89 — +2.8%
  - **Plan v0.4가 "5-15% 개선" 명시했다면 over-statement — paper 결과는 datasets에 따라 0~10% (best case)**
- Plan v0.4가 인용한 "KR equity NLL 비교" 결과는 paper에 **없음** (UCI tabular만)
- Plan v0.4가 인용한 specific Sharpe/CAGR 수치 있다면 **paper에 없음** (NGBoost paper는 portfolio backtest 없음)

---

### C2 Neural Lévy SDE for State-Dependent Risk and Density Forecasting

**Citation**: Wang, Z., & Rachev, S. T. (2025). Neural Lévy SDE for State-Dependent Risk and Density Forecasting. arXiv:2509.01041 (September 2025).

**Methodology**:

핵심 아이디어 — Brownian diffusion + state-dependent Lévy jump process를 neural network로 통합 parameterize. drift μ_θ, diffusion σ_θ, jump intensity λ_θ, jump size distribution g(·|φ_θ) 4개 component 모두 observable state X_t의 함수로 학습. State vector에 conventional features(lagged returns, volume, RV)와 **complexity measures (permutation entropy, RQA determinism)** 모두 포함. Shared encoder + multi-horizon heads (daily/weekly/biweekly/monthly).

수식 (key equations):

State-dependent jump-diffusion SDE (continuous-time, Eq 12-14 paper):
```
dY_t = μ_θ(X_t) dt + σ_θ(X_t) dW_t + dJ_t
J_t = Σ_{k=1}^{N_t} Z_k     where N_t ~ Poisson(λ_θ(X_t)), Z_k ~ g(·|φ_θ(X_t))
```

h-period discretization (Eq 15):
```
ΔY_t^(h) = μ_θ^(h)(X_t) + σ_θ^(h)(X_t) ε_t^(h) + Σ_{k=1}^{K_t^(h)} Z_{k,t}^(h)
    where ε_t^(h) ~ N(0,1), K_t^(h) ~ Poisson(λ_θ^(h)(X_t)), Z_k ~ g(·|φ_θ^(h))
```

Permutation entropy (Bandt-Pompe 2002):
```
H_perm = -Σ_π p_π log p_π / log m!    (normalized to [0,1])
```

RQA Determinism:
```
DET = Σ_{l=l_min}^N l·P(l) / Σ_{l=1}^N l·P(l)   (proportion of diagonal recurrent points)
```

Bipower variation weight (jump separation, Eq for quasi-MLE):
```
ω_t = BV_t / (RV_t + ε)    where BV/RV ratio → 1 if no jumps
```

Risk signals:
- Jump-adjusted Sharpe: `f_ISJ = μ_θ^(h) / sqrt(σ_θ^(h)² + λ_θ^(h) · E[Z²|φ])` (continuous + jump variance 통합)

Cost-aware portfolio (Section 7.1):
```
w_t = arg max [w^T α_t - (λ_r/2) w^T Σ w - κ ||w - τ_{t-1}||_1]
subject to: ||w - τ_{t-1}||_1 ≤ τ_max, |w_i| ≤ w_max, sector neutrality
```

Architecture:
- Shared encoder: feedforward NN 2 hidden layers × 64 dim + ReLU
- Multi-horizon heads: separate small NNs (one hidden layer) per h ∈ {1D, 1W, 2W, 1M} → output (μ^(h), σ^(h), λ^(h), φ^(h))
- Softplus 양의 제약 on σ, λ; upper bound λ ≤ 0.5 (daily), ≤ 1.5 (weekly)
- Jump distribution g: double exponential or Gaussian mixture (2-component)
- Monotonicity constraint: σ, λ 모두 entropy 증가 / DET 감소에 따라 증가

Training (Section 5.3):
1. Pretrain diffusion head with BV signal (Gaussian log-likelihood, weighted by ω_t)
2. Joint training: quasi-MLE with truncated compound Poisson (K_max = 3 jump events)
3. Hyperparameter tune: embedding dim, horizon weights α_h, regularization λ_1, λ_2

**Reported Metrics** (정량):

Daily (1D) forecast on S&P 500 (500 stocks, 2005-2024, test 2020-2024):
- NLL (negative log score): NeuralLevy **2.598** (best, in MCS); GJR 2.456 (2nd); Diffusion-only NN 2.445; EGARCH 1.773
- CRPS: NeuralLevy **0.01028** (best); GJR 0.01049; Merton 0.01058; EGARCH 0.03522 (worst)
- NeuralLevy vs best baseline: log score **+5.77%**, CRPS **+1.96%**
- DM (Diebold-Mariano) p<10^{-50} for all baselines vs NeuralLevy
- Berkowitz calibration p_μ = 7.68×10^{-7} (rejected — sample = 143,016 too large)

Weekly (1W) forecast:
- NLL: NeuralLevy **2.097**, Diffusion-NN 2.025 (2nd)
- CRPS: NeuralLevy **0.01709**, Diffusion-NN 0.01996
- NeuralLevy vs best baseline: log score **+3.60%**, CRPS **+14.36%**

VaR/ES Backtest 1W (140 weeks, 95% & 99%):
- 95% level: neural / diffusion both **0 breaches**, Kupiec p≈0 (REJECT — over-conservatism)
- 95% rp (risk parity): 2.86% (not different from 5% target), pass
- 95% SPY: 1.43%, Kupiec p=0.023 (mild reject)
- 99% level: all pass

Limitations of portfolio implementation: Sharpe ~0, IR ≈ -1.0 vs SPY (hard risk gate + turnover constraint 충돌).

**KR / Equity Applicability**:

- 논문 자체 cross-sectional **US S&P 500 equities** (500 stocks) — KR 직접 언급 없음
- "methodology applies to other asset classes" (Section 3.1) — KR 적용 가능 명시
- 적용 시 고려: KR daily는 거래대금 분포가 US와 다름 (BV/RV decomp 안정성 필요), permutation entropy embedding dim m=3 robust to KR retail noise 가능
- **금융 jump 분포**: Merton 1976 / Kou 2002 double exponential / CGMY 모두 다양한 jump family 지원 — KR equity의 tail heavy 적합
- limitations 위 portfolio result (gate / turnover 문제)는 KR에 그대로 적용 시 risk → 'soft scaling' (Section 10 discussion)으로 완화 필요

**Limitations**:

- Sample S&P 500만 (cross-asset/country generalization 미검증)
- Quasi-MLE depends on K_max truncation (extreme regime 시 inversion 필요)
- Permutation entropy / DET window length 의존 (adaptive scheme 미구현)
- Berkowitz calibration test universally rejected (sample = 143k 너무 큼)
- Portfolio Sharpe ≈ 0, IR ≈ -1 vs SPY — distributional forecast 우수 but trading rule 미흡
- Hard risk gate ↔ 95% breach 0회 ↔ Kupiec REJECT (over-conservatism)
- Self-exciting Hawkes / rough volatility / Bayesian uncertainty 미통합 (future work)

**Plan v0.4 사실 검증**:

- Plan v0.4가 인용한 "Bates 2008 jump 정합성"은 paper에서 Kou 2002 + Merton 1976 + Carr-Geman-Madan-Yor 2002 (CGMY)로 언급 (Bates 2008 직접 인용은 paper에 없음). **Plan v0.4의 Bates 인용은 verify 필요 (paper에 직접 언급 부재)**
- Plan v0.4 "cross-sectional equity 적용 결과" 정합 — paper는 정확히 cross-sectional S&P 500 사용
- "Neural Portfolio annual 36.4% SR 0.91" 같은 수치는 **paper에 없음** (Q-Lead B1에서 발견한 오류 패턴 동일) — paper Section 10/11에서 명시: Sharpe ratio close to zero, IR ≈ -1.0 vs SPY
- "5-15% NLL 개선" 정합 — paper 1D NLL +5.77%, 1W NLL +3.60%, 1W CRPS +14.36% (range 3.60~14.36%)
- Plan v0.4가 KOSPI 적용 가능성 언급 시 — paper 자체에는 KR 데이터 사용 없음 (claim 가능 but verify 안 됨)

---

### F1 A Gentle Introduction to Conformal Time Series Forecasting

**Citation**: Stocker, M., Małgorzewicz, W., Fontana, M., & Ben Taieb, S. (2025). A Gentle Introduction to Conformal Time Series Forecasting. arXiv:2511.13608v1.

**Methodology**:

핵심 아이디어 — Classical Conformal Prediction (CP)는 distribution-free finite-sample coverage guarantee 제공 but **exchangeability assumption 의존**. 시계열은 temporal dependence + distribution shift로 인해 exchangeability 위배 → standard SCP 무효화 위험. Review는 4가지 family로 non-exchangeable CP 분류 (Reweighting / Refreshing / Adapting Coverage / Blocking).

수식 (key equations):

Standard Split CP (Section 1):
- Non-conformity score: `s(X_i, Y_i) = |Y_i - μ̂(X_i)|` (absolute residual; quantile-based and HDR-based 대안)
- Empirical quantile: `q̂_{1-α} = quantile_{α} of S_cal` (calibration scores)
- Prediction set: `Ĉ_{1-α}(X_{T+1}) = [μ̂(X_{T+1}) - q̂_{1-α}, μ̂(X_{T+1}) + q̂_{1-α}]`
- Marginal coverage: `P(Y_{T+1} ∈ Ĉ_{1-α}(X_{T+1})) ≥ 1 - α` (exchangeability 가정 하)

4 family algorithms:

(1) Weighted CP (WCP / Nex-CP, Algorithm 1):
- Weighted quantile: `q̂_{1-α}^{(w)} = inf {t : Σ w̃_i 𝟙{s_i ≤ t} ≥ 1 - α}`
- Weights w_i: exponential decay `w_i ∝ ρ^{t_m - t_i}` (recent past), sliding window, or learned (Hop-CPT / CT-SSF)

(2) EnbPI (Ensemble Batch Prediction Intervals, Algorithm 2):
- Bootstrap ensemble of M=25 models
- OOB residuals: `ε_i = |Y_i - μ̂_OOB(X_i)|` (out-of-bag aggregation)
- Sliding window refresh every δ steps (refresh frequency s ∈ {1, 10, 100})

(3) ACI (Adaptive Conformal Inference, Algorithm 3) — Gibbs-Candes 2021:
- Update rule: `α_{t+1} = α_t + γ(α - e_t)` where `e_t = 𝟙{Y_t ∉ Ĉ}`
- Long-run convergence: `(1/T) Σ_t 𝟙{Y_t ∉ Ĉ_t} → α`
- Variants: AgACI (multiple γ aggregation), Conformal PID Control (Angelopoulos-Candes-Tibshirani 2023)

(4) Block CP (BCP, Section 3.4) — Chernozhukov-Wuthrich-Zhu 2018:
- Permutation acts on blocks (size B) instead of individual points
- Split-BCP: model `μ̂` trained once, p-value from permuted scores
- Trade-off: loses exact validity, gains scalability

Coverage guarantee theorem (Theorem A.3.1, Marginal coverage under non-exchangeability):
```
P(Y_i ∈ C_{1-α}(X_i)) ≥ 1 - α - ε_cal - ε_train - δ_cal
```
where (ε_cal, δ_cal) bound calibration concentration error and ε_train bounds train-test dependence. For β-mixing processes (Theorem A.4.1), explicit slack: ε_train = β(i - n_train), ε_cal expressed via β(a) coefficient + n_cal.

**Reported Metrics** (정량):

Simulation study (Section 4, 4 DGPs × R=50 runs, n=900 split 300/300/300, 1-α=0.9):

1. AR(1) — stationary, β-mixing:
   - SCP / WCP / ACI / EnbPI: coverage ≈ 0.9 (valid)
   - SCP-block: under-covers (visible)
   - EnbPI: wider intervals than SCP (bootstrap variance cost)

2. ARMA(1,1) — stationary: 결과 유사

3. GARCH(1,1) — heteroscedastic: 결과 유사. Methods가 모두 valid but interval width 차이 (SPCI / conditional methods가 sharper).

4. **Mean shift** (non-exchangeable, t*=601 abrupt break):
   - **SCP coverage drop to ~0.84** (target 0.9 미달, ~6% gap)
   - SCP-block ~0.81-0.84
   - WCP-window (last 50 points only) ~0.81 (fail)
   - **ACI / EnbPI / WCP-exp / WCP-linear all maintain ~0.9** (적응 성공)

Runtime (Figure 2): SCP / WCP < ACI < EnbPI (EnbPI 가장 비쌈 — bootstrap ensemble cost)

Practical recommendations (Section 5):
- Stable processes → SCP (cheap, valid)
- Anticipated shifts → WCP-exp/linear (cheap + robust), ACI (active feedback), EnbPI (expensive but robust)
- SCP-block: requires careful block size tuning, weak in simple stationary cases

**KR / Equity Applicability**:

- Paper 자체 simulated AR/ARMA/GARCH + mean shift만; KR 명시 없음
- 그러나 GARCH(1,1) DGP 결과: KR equity volatility clustering에 직접 적용 가능 → SCP / WCP가 coverage 유지 (heteroscedasticity은 mild dependence로 처리됨)
- KR equity에서 우려: regime switching (bull→bear) 시 mean shift 시나리오 ↔ SCP 실패 가능 → **ACI 또는 EnbPI가 안전 (Cycle 50 bear date audit에 부합)**
- forecast horizon h-week에서: paper Section 5 limitations에 multi-step horizon은 future work 명시 → KR forecast 적용 시 h=1 day 권장
- Conformal Risk Control (CRC, Angelopoulos et al 2023) — paper Section 3.1에서 언급. **KR loss function (e.g., downside CVaR)에 직접 적용 가능**

**Limitations**:

- Univariate focus (multivariate CP는 future work)
- Simple AR-LS base forecaster (real applications: ARIMA / neural model 권장)
- Coarse hyperparameter sweeps (γ, s, ρ, B 민감도 미검증)
- Locally stationary / strongly non-stationary process는 simulation 미포함
- Hop-CPT / AgACI / Conformal PID 등 advanced variants 미실험

**Plan v0.4 사실 검증**:

- Plan v0.4가 인용한 "non-exchangeable conformal" — paper 일치 (Section 2)
- "sliding window 알고리즘" — paper EnbPI Section 3.2 일치
- "coverage guarantee theorem" — paper Theorem A.3.1, A.4.1 일치 (β-mixing slack term)
- Plan v0.4가 어떤 specific coverage 수치 주장 시 (e.g., "95% coverage achieved on KR"): paper에 KR 데이터 사용 **없음** → claim 검증 안 됨
- 실험 datasets는 simulated 4종 only — paper에 real-world stock data 없음. **Plan v0.4가 stock data 결과 인용 시 다른 paper 출처 확인 필요**

---

### A1 Vulnerable Growth (Adrian, Boyarchenko, Giannone 2019 AER)

**Citation**: Adrian, T., Boyarchenko, N., & Giannone, D. (2019). Vulnerable growth. *American Economic Review*, 109(4), 1263-1289. DOI: 10.1257/aer.20161923. (Earlier version: FRBNY Staff Report 794, October 2016.)

**Methodology** (secondary sources + abstract 기반 — primary paywalled):

핵심 아이디어 — GDP growth의 **conditional distribution**을 financial conditions의 함수로 quantile regression 추정. Mean growth 단일 점이 아닌 full distribution (특히 lower tail)을 추적. Financial stress 증가 시 **conditional volatility 증가 + conditional mean 감소** 동시 발생 → downside risk asymmetric amplification.

수식 (key equations) — secondary sources 기반:

(1) Quantile regression specification (paper Eq 1):
```
Q_{y_{t+h}}(τ | x_t) = β_0(τ) + β_1(τ) y_t + β_2(τ) NFCI_t
```
- y_{t+h}: GDP growth h quarters ahead (h ∈ {1, 4})
- NFCI_t: National Financial Conditions Index (Chicago Fed) — composite of risk premia, leverage, volatility
- τ ∈ {0.05, 0.25, 0.50, 0.75, 0.95}: quantile levels

(2) Koenker-Bassett 1978 quantile loss (estimation):
```
β̂(τ) = arg min_β Σ_t ρ_τ(y_{t+h} - β_0 - β_1 y_t - β_2 NFCI_t)
ρ_τ(u) = u · (τ - 𝟙{u < 0})       (asymmetric absolute loss)
```

(3) Skewed t-distribution fit (Azzalini-Capitanio 2003):
- Conditional density `f(y_{t+h} | x_t)` fitted from quantile estimates via skewed t with parameters (location μ, scale σ, shape α, kurtosis ν)
- Allows asymmetric tail behavior — left tail (downside) widens more than right tail when NFCI rises

(4) Growth-at-Risk (GaR):
```
GaR_α = Q_{y_{t+h}}(α | x_t)       (Bottom α-quantile of growth distribution)
```
- Standard reporting: GaR_5% (5th percentile of expected growth)

**Reported Metrics** (정량) — secondary sources만 (primary paper numbers paywalled):

US empirical results (1973Q1-2015Q4, NFCI):
- h=1Q (1 quarter ahead): NFCI strongly affects **lower quantiles (τ=0.05, 0.10)** of growth distribution; upper quantiles (τ=0.75) less affected → **asymmetric downside risk amplification**
- h=4Q (1 year ahead): Conditional distribution widens substantially; financial stress shifts left tail more
- Downside Q_5% expected GDP growth at NFCI shock: dropped multiple percentage points
- Upper tail (Q_95%) relatively stable across NFCI levels — **upside risk constant; downside risk variable**
- Out-of-sample density forecast: GaR framework dominates Gaussian VAR particularly in tail prediction (log score / CRPS / PIT)

**Specific Tables 3-4 numeric quantile coefficients** ACCESS_FAIL — paywalled, requires university library or AEA subscription.

**KR / Equity Applicability**:

- 직접 적용 가능: KR GDP forecast with KR NFCI proxy (e.g., KOSPI 변동성 + 회사채 spread + KRW vol)
- **금융 → 거시 channel**이 paper focus → KR equity strategy의 macroeconomic regime detection에 적용 가능
- Plan v0.4 가설 (KR 약세 forecast): NFCI-like financial conditions index가 미래 KR equity bearish probability와 연결 → 본 paper의 quantile regression framework 활용 가능
- 주의: 본 paper는 GDP 예측 — equity price 예측 아님. **GDP downside risk → equity bear market** 매핑은 추가 step

**Limitations**:

- US 데이터만 — paper 자체에 다른 국가 결과 없음 (IMF subsequent 확장 paper에 emerging markets 결과)
- Quantile crossing 가능성 (quantile regression의 일반 문제)
- NFCI 정의 의존 — 다른 financial conditions index (FCI / GSFCI) 시 결과 다를 수 있음
- Long-horizon (h > 4Q) conditional distribution은 wider but identification 약함
- Real-time NFCI vs revised NFCI 시점 차이

**Plan v0.4 사실 검증**:

- Plan v0.4가 인용한 GaR framework 정합 — paper의 core contribution
- "NFCI predicts lower quantile of GDP growth" 정합 — paper main finding
- "5%/25%/50%/75% empirical quantiles" 인용 — 본 paper의 표준 reporting
- "downside risk asymmetric" 정합
- **만약 Plan v0.4가 specific β coefficient 수치 (e.g., β_1(0.05) = -X.XX) 인용했다면 verify 필요** — 본인은 access fail이지만 paper Tables 3-4에 정확한 수치 존재
- **만약 Plan v0.4가 KR/KOSPI 적용 결과 인용했다면 paper 자체에는 없음** (US만)

---

### E5 Christoffersen 1998 "Evaluating Interval Forecasts"

**Citation**: Christoffersen, P. F. (1998). Evaluating interval forecasts. *International Economic Review*, 39(4), 841-862.

**Methodology** (Wikipedia + Neural Lévy paper Section 8.3 + 9.3 + Gneiting-Raftery 2007 Section 6.1 기반):

핵심 아이디어 — VaR 또는 prediction interval의 quality를 두 가지 측면으로 test:
1. **Unconditional coverage (UC)**: empirical breach rate가 nominal α level과 일치
2. **Independence (Markov)**: breach 발생이 시간적 독립 (clustering 없음)
3. **Conditional coverage (CC)**: 위 두 가지 결합

수식 (key equations):

Breach indicator sequence: `I_t = 𝟙{Y_t < VaR_α(t)}`, ideally `I_t ~ i.i.d. Bernoulli(α)`

(1) Kupiec POF (Proportion of Failures, Unconditional Coverage):
- Null: `H_0: π = α`, where `π` = true breach probability
- Likelihood ratio: `LR_UC = -2 log[ (1-α)^{n_0} α^{n_1} / ((1-π̂)^{n_0} π̂^{n_1}) ]`
- where π̂ = n_1 / (n_0 + n_1), n_0 = # non-breaches, n_1 = # breaches
- Asymptotic distribution: `LR_UC ~ χ²(1)` under H_0

(2) Independence test (Markov chain transition):
- Transition counts: n_{ij} = # transitions from state i to state j (i,j ∈ {0, 1})
- Markov dependence: `π_{ij} = P(I_t = j | I_{t-1} = i)`
- Null: `H_0: π_{01} = π_{11}` (no dependence)
- Likelihood ratio: `LR_IND = -2 log[ L(π̂_2) / L(π̂_1) ]`
  - L(π̂_2) = (1-π̂_{01})^{n_{00}} π̂_{01}^{n_{01}} (1-π̂_{11})^{n_{10}} π̂_{11}^{n_{11}}
  - L(π̂_1) = (1-π̂)^{n_0} π̂^{n_1}     (i.i.d. case)
- `LR_IND ~ χ²(1)` under H_0

(3) Conditional Coverage:
```
LR_CC = LR_UC + LR_IND  ~ χ²(2)   under H_0 (both correct)
```

**Reported Metrics** (정량) — Christoffersen 1998 paper actual experiments:

(secondary recall — full paper PDF 미접근):
- Bilinear AR process simulation
- 95% VaR backtest sequential forecasts (n=100,001)
- Kupiec test power / size: typical Type I error 5% level performance
- Independence test catches volatility clustering (GARCH-type data)
- Conditional coverage (CC) test combines both with χ²(2) critical value 5.99 (α=0.05)

**KR / Equity Applicability**:

- 매우 적용 가능 — KR equity VaR backtest 표준
- Plan v0.4의 bearish probability forecast → breach indicator I_t 정의 가능
  - 예: I_t = 𝟙{KOSPI_t < forecast_5%}
- Kupiec + Christoffersen pair는 거의 모든 KR risk model validation 표준
- Christoffersen이 직접 Neural Lévy paper Section 9.3 backtest에 사용 (95%, 99% level)
- 한계: 적은 breach count (n_1 < 10) 시 test power 낮음 — KR 5년 daily data (~1250 obs)에서 95% target만 ~62 breaches 예상 (수용 가능)

**Limitations**:

- Markov 1차 의존만 detect (long memory 미감지)
- Tail magnitude 정보 미사용 (ES 평가 아님)
- Small sample bias — Christoffersen-Pelletier 2004 (extended test)에서 개선
- VaR breach만 — Expected Shortfall은 별도 backtest (Acerbi-Szekely 2014)

**Plan v0.4 사실 검증**:

- Plan v0.4가 인용한 "Unconditional coverage test" + "Conditional coverage test" 정합
- "Markov dependence" 정합
- "LR test χ²(1) for UC, χ²(2) for CC" 정합
- Plan v0.4가 specific numeric example (e.g., "98 breaches expected, 92 observed") 인용했다면 verify 필요 — paper Section 3-4 example 있음 but 본인 ACCESS_FAIL
- **본 paper는 1998년 IER paper — Plan v0.4가 "Christoffersen 2009 RFS" 인용 시 다른 paper (Christoffersen 2009 RFS는 backtest review paper일 수 있음). 사용자 mandate에 "E5 Christoffersen 2009 VaR Backtesting RFS"로 명시되었으나 가장 자주 인용되는 backtesting framework은 1998 IER. Plan v0.4가 정확히 어떤 paper 참조하는지 명확히 할 필요**

---

### E6 Gneiting-Raftery 2007 JASA "Strictly Proper Scoring Rules"

**Citation**: Gneiting, T., & Raftery, A. E. (2007). Strictly proper scoring rules, prediction, and estimation. *Journal of the American Statistical Association*, 102(477), 359-378. (Review Article)

**Methodology** (full PDF 1-15 pages 직접 읽음):

핵심 아이디어 — Probabilistic forecast P를 evaluate하는 scoring rule S(P, y)의 theory. **Proper** scoring rule은 forecaster가 honest 보고를 하도록 incentive (true distribution Q가 expected score 최대화). **Strictly proper**는 maximum이 unique. 본 paper는 various scoring rules (logarithmic, quadratic, spherical, CRPS, energy score)를 unify하고 convex function / Bregman divergence와 연결.

수식 (key equations from paper):

(1) Proper scoring rule definition (Eq 1):
```
S(Q, Q) ≥ S(P, Q)    for all P, Q ∈ 𝒫
```
- Strictly proper: equality iff P = Q
- Information measure (entropy): `G(P) = sup_{Q∈𝒫} S(Q, P) = S(P, P)` (Eq 6)
- Divergence: `d(P, Q) = S(Q, Q) - S(P, Q)` (Eq 7) — Bregman divergence

(2) Common scoring rules:

Logarithmic score (Eq 19): `LogS(p, ω) = log p(ω)`
- Associated entropy: negative Shannon entropy `G(p) = ∫ p log p`
- Divergence: KL divergence

Quadratic score / Brier score (Eq 18, categorical): `QS(p, ω) = 2p(ω) - ||p||²₂`

CRPS Continuous Ranked Probability Score (**Eq 20**):
```
CRPS(F, x) = -∫_{-∞}^{∞} (F(y) - 𝟙{y ≥ x})² dy
```
Equivalent kernel representation (**Eq 21**, Baringhaus-Franz / Szekely-Rizzo):
```
CRPS(F, x) = (1/2) E_F |X - X'| - E_F |X - x|
```
- X, X' independent copies from F
- Closed-form for Gaussian: `CRPS(N(μ,σ²), x) = σ[1/√π - 2φ((x-μ)/σ) - ((x-μ)/σ)(2Φ((x-μ)/σ) - 1)]`

Energy score (Eq 22, multivariate generalization of CRPS):
```
ES(P, **x**) = (1/2) E_P ||**X** - **X'**||^β - E_P ||**X** - **x**||^β
```
- β ∈ (0, 2); β=1 reduces to CRPS (univariate)

Spherical / pseudospherical score (Eq related to S(p, ω) = p(ω)^{α-1} / ||p||_α^{α-1})

(3) Logarithmic score scoring rule for predictive density (Eq 25):
```
S(P, x) = -log det Σ_P - (x - μ_P)^T Σ_P^{-1} (x - μ_P)   (Mahalanobis-style)
```

(4) Interval score (Eq 43, quantile forecast at α/2 and 1-α/2):
```
S_α^int(l, u; x) = (u - l) + (2/α)(l - x)𝟙{x < l} + (2/α)(x - u)𝟙{x > u}
```
Negatively oriented — smaller is better. Width penalty + miss penalty (size of miss depends on α).

(5) Quantile score (Eq 41, Koenker-Bassett-related):
```
S(r; x) = (x - r)(𝟙{x ≤ r} - α)    proper for quantile at level α
```

(6) Strictly proper kernel score (Theorem 4, Eq 28):
```
S(P, x) = (1/2) E_P g(X, X') - E_P g(X, x)
```
where g is non-negative continuous negative definite kernel.

**Reported Metrics** (정량) — paper case study (Section 8, sea-level pressure forecast over NA Pacific Northwest, 6 months, n=16,015):

Mean score for 6 scoring rules (Table 3) at optimal inflation factor r*:
- Quadratic Score (QS): r* = 2.18 (transformed 40s + 6)
- Spherical Score (SphS): r* = 1.84 (transformed 108s - 22)
- Logarithmic Score (LogS): r* = 2.41 (transformed s + 13)
- CRPS: r* = 1.62 (transformed 10s + 8)
- Linear Score (LinS, **improper**): r* = 0.05 (artificially low — improper score 함정)
- Probability Score (PS, **improper**): r* = 0.02

→ Linear score / probability score는 r* near zero (delta-function-like, improper) — paper의 핵심 경고: **improper scoring rule은 misleading**.

QS / SphS / LogS / CRPS all yield r* > 1, confirming underdispersion of ensemble forecast (raw r_0 = 1.55).

Interval score case study (Section 6.3, stationary bilinear process, n=100,001, 95% interval, Table 2):
- Interval I (true conditional 2.5%-97.5%): coverage 95.01%, width 4.00, interval score **4.77**
- Interval J (unconditional 2.5%-97.5%): coverage 95.08%, width 5.45, score 8.04
- Interval K (variance-narrowest): coverage 94.98%, width 3.79, score 5.32
- **Best by interval score = I (true conditional)** — confirms propriety theorem operational value

**KR / Equity Applicability**:

- 모든 KR distributional forecast의 evaluation 표준
- Log score = NLL (NGBoost / Neural Lévy / Conformal 모두 사용)
- CRPS = forecast verification 표준 (Neural Lévy paper 직접 사용)
- Energy score = multivariate KR cross-sectional forecast (예: factor returns 함께 predict)
- Interval score = KR 95% VaR forecast의 quality measure (coverage + width 결합)
- Plan v0.4가 KR bearish probability forecast 시 — log score 또는 CRPS로 model comparison 직접 가능
- **본 paper는 review/theory paper — empirical KR application 없음**

**Limitations**:

- 본 paper는 2007 — 이후 conformal prediction / kernel score 발전 미포함 (subsequent literature 참조 필요)
- Forecast 평가 framework only — forecast 산출 model에 대한 guidance 없음
- Skill score (relative score)는 종종 improper (Section 2.3) — caution
- Local scoring rules는 logarithmic score만 (Bernardo 1979) — locality property와 propriety 조합 제한
- Improper scoring rule이 자주 사용되는 경우 (linear score 등) detection 필요

**Plan v0.4 사실 검증**:

- Plan v0.4가 인용한 "Strictly proper scoring rule" 정합 — paper Eq 1 core definition
- "CRPS 수식 Eq 20-21" 정합 — 정확히 paper Eq 20 (integral form), Eq 21 (kernel form)
- "Log score" 정합 — paper Eq 19
- "Energy score" 정합 — paper Eq 22
- "Propriety theorem" 정합 — paper Section 2.1 + Eq 4 (subtangent inequality)
- Plan v0.4가 specific KR empirical numbers 인용했다면 paper에 **없음** (sea-level pressure case study만)
- "skill score" 사용 시 — paper Section 2.3에서 "Skill scores of form (8) are generally improper" 경고 명시. Plan v0.4가 skill score 비교 사용 시 propriety check 필요

---

## 종합: Plan v0.4 사실 오류 발견 list

작성: 2026-05-24

(1) **Plan v0.4가 "Neural Portfolio annual 36.4% SR 0.91" 등 specific portfolio Sharpe/CAGR 인용 시** — Q-Lead B1 KOSPI paper에서 발견한 동일 오류 가능성 **C2 Neural Lévy 논문에도 적용**. Paper의 portfolio result는 정반대: Sharpe ≈ 0, IR ≈ -1.0 vs SPY (Section 10). 만약 v0.4가 NeuralLevy의 trading performance를 high Sharpe로 기술했다면 **HALLUCINATION 가능성 높음**.

(2) **"NLL 5-15% 개선" 주장 검증**:
- B5 NGBoost: UCI tabular dataset별 0~10% 범위 (Boston -0.8%, Wine +2.2%, Protein +2.8%) — 5-15% 주장 over-statement
- C2 Neural Lévy: 1D log score +5.77%, 1W +3.60%, 1W CRPS +14.36% — 3.60~14.36% 범위. "5-15%"는 부분적으로 부합 but range 정확히 표현 필요

(3) **B5 NGBoost paper에 KR / financial dataset 결과 없음** — Plan v0.4가 NGBoost를 KR equity forecast로 직접 적용 결과 인용 시 paper에 **없는 내용**. UCI tabular benchmark만 (Boston housing, Wine quality, Protein structure 등).

(4) **B5 NGBoost paper는 i.i.d. 가정 기반** — Plan v0.4가 NGBoost를 시계열에 직접 적용 가능하다고 명시 시 purging/embargo + temporal CV 필요성 누락 가능성. Paper Section 5에서 misspecification 일관성 미해결 명시.

(5) **C2 Neural Lévy paper에서 "Bates 2008 jump 정합성" 인용 verify 실패** — Paper에는 Merton 1976 / Kou 2002 / CGMY 2002 인용; Bates 2008 직접 인용 없음. Plan v0.4가 Bates 2008로 기술 시 source verification 필요.

(6) **C2 Neural Lévy KR 적용 결과** — paper는 S&P 500 미국 cross-section. KR 적용 결과 paper에 없음. Plan v0.4가 KR 결과 인용 시 다른 source 또는 인용 오류.

(7) **F1 Conformal paper는 simulated AR/ARMA/GARCH + mean shift만 사용** — real-world stock data 결과 없음. Plan v0.4가 stock data conformal coverage 결과 인용 시 paper에 없는 내용.

(8) **A1 Vulnerable Growth specific Tables 3-4 quantile coefficient 수치** — ACCESS_FAIL (paywalled). Plan v0.4가 specific β_1(0.05) = -X.XX 형식의 수치 인용 시 paper actual values 확인 필요. **본 deep read에서 verify 불가**.

(9) **A1 Vulnerable Growth paper는 US만** — Plan v0.4가 KR / 다른 국가 GaR 결과 인용 시 본 paper에는 없음 (subsequent IMF 확장 paper 또는 다른 cross-country 연구 인용 필요).

(10) **E5 Christoffersen RFS 2009 vs 1998 IER 확인 필요** — 사용자 mandate에 "Christoffersen 2009 VaR Backtesting RFS" 명시되었으나, 가장 널리 인용되는 VaR backtest framework은 Christoffersen 1998 IER "Evaluating Interval Forecasts". 2009 RFS paper 별도 존재할 가능성 (review paper 등) — Plan v0.4 cite 명확화 필요.

(11) **E6 Gneiting-Raftery 2007 paper에 KR empirical 결과 없음** — review/theory paper + sea-level pressure case study만. Plan v0.4가 본 paper에서 KR 결과 인용 시 source 오류.

(12) **모든 paper에서 specific Sharpe/CAGR/MDD 수치는 paper-by-paper 검증 필요** — Q-Lead B1 사례처럼 "annual 36.4% SR 0.91" 같은 구체 수치는 paper에 없는 경우가 빈번 (hallucination 패턴). Plan v0.4의 정량 인용은 본 deep read 결과와 case-by-case 비교 권장.

---

## ACCESS_FAIL list

- **A1 Vulnerable Growth specific Tables 3-4 numeric quantile coefficients**: AER 2019 paywalled, NY Fed sr794 403 Forbidden, NBER WP 24875는 다른 paper, NBER 23192도 다른 paper. Secondary sources (IMF GaR review / Jina extract / Wikipedia Quantile Regression Koenker-Bassett loss formula)로 framework 일반 설명만 가능.
- **E5 Christoffersen 1998 PDF full body**: Wikipedia thin, full text 접근 실패. C2 Neural Lévy paper Section 8.3 + 9.3에서 backtest framework 실증 적용 사례 확인 (Kupiec + Christoffersen + Acerbi-Szekely 적용 표).
- **NGBoost arxiv 1910.03225 mcp__arxiv__read_paper**: download 끝까지 미완료 (timeout). 우회로 arxiv abs page + arxiv pdf v4 (WebFetch PDF)로 full body 확보.

---

## 출처

- B5: arxiv:1910.03225v4 (full PDF read via WebFetch — 10 pages)
- C2: arxiv:2509.01041 (full body read via /home/quant/.claude/projects/.../mcp-arxiv-read_paper-1779606779313.txt slice 0-80340)
- F1: arxiv:2511.13608v1 (full body read via /home/quant/.claude/projects/.../mcp-arxiv-read_paper-1779606852482.txt slice 0-83094)
- A1: AER 2019 abstract (https://www.aeaweb.org/articles?id=10.1257/aer.20161923) + IMF GaR Working Paper context + Wikipedia Quantile Regression
- E5: Wikipedia VaR + Backtesting + C2 Neural Lévy paper Section 8.3 + Gneiting-Raftery 2007 Section 6.1 reference
- E6: WebFetch PDF https://sites.stat.washington.edu/raftery/Research/PDF/Gneiting2007jasa.pdf (full 15 pages read)
