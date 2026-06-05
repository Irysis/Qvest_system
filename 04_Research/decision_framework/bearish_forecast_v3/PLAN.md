# bearish_forecast_v3 — Research Plan v0.5

**작성**: 2026-05-24 KST (v0.5 amend 2026-05-24 Session 84)
**Owner**: 도훈 (Quant RA) / Q-Lead orchestration
**계보**: v0.4.2 NULL → v2_alt_data 7 cycle ceiling 0.25 → **v3 paradigm shift (full distributional forecasting + Tier 4 ensemble)**
**Status**: Plan v0.5 — **Paradigm B Primary Lock-in (Phase 1 paper verification + 12건 사실 오류 정정)** + B5 NGBoost + Tier 4 Full Paradigm Mixture ensemble (도훈 mandate 2026-05-24)

**v0.5 amendment**: Phase 1 deep read 7편 verification 결과 v0.4 본문 paper-cite 정량 12건 사실 오류 정정. 상세: `AMENDMENT_v0.5.md` (12건 E01-E14 정정안 + Phase 5 entry criteria CR-V01-V06 신규). 도훈 GO 결정 2026-05-24.

---

## Section 0: 쉽게 설명 — 왜 paradigm shift?

### 0.1 v2가 막힌 이유 (직관)

**v2가 시도한 것**: "다음 한 달 동안 KOSPI가 '평소보다 하위 15%' 사건이 일어날까?" → Y/N 분류

**문제**:
- '평소'의 기준이 시장 변동성에 따라 매번 바뀜
- 변동성 낮은 시기: -3% 손실도 "평소보다 나쁨" 라벨 1
- 변동성 높은 시기: -8% 손실이 "평소" 라벨 0
- 결과: **같은 라벨이라도 실제 손실 크기가 제각각** → 모델이 일관된 패턴 학습 못 함
- risk manager 입장: "사건 확률 20%" 라고 해도 *얼마나 큰 손실*인지 모르니까 hedge 비중 결정 불가

**측정 증거**: 7 cycle (58A~G) 모든 시도가 PR-AUC ceiling 0.25에서 막힘 ([cycle58_FINAL_HONEST_REPORT.md](04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/04_evaluation/cycle58_FINAL_HONEST_REPORT.md)).

### 0.2 v3 paradigm — Full distributional forecasting

**v3가 시도할 것**: "다음 한 달 KOSPI 수익률의 *분포 모양*이 어떻게 생겼을까?" → 평균·분산·꼬리·비대칭 통째로 예측

```
   확률밀도
     │   ╱╲
     │  ╱  ╲
     │ ╱    ╲___
     │╱        ╲___
     └─────────────────→ 수익률 r
     -15% -10% -5%  0%  +5%
              ↑    ↑
          P(r≤-5%) P(r≤0%)
       VaR_95 등 derived
```

**장점 3**:
1. **라벨 의미 일관** — -5% 손실은 언제나 -5% 손실. 시장 regime 무관 (도훈 핵심 통찰).
2. **한 모델로 모든 질문 답** — P(r ≤ -3%), P(r ≤ -5%), P(r ≤ -10%), VaR_95, ES_95 모두 derived.
3. **Risk manager actionable** — hedge 비중 / margin 결정 직결.

**학술 정통**: Adrian-Boyarchenko-Giannone 2019 AER + KOSPI 직접 검증 ([arxiv 2508.18921](https://arxiv.org/abs/2508.18921), 2025).

### 0.3 방법론 비유

| 방법 | 비유 | 직관 |
|------|------|------|
| **Quantile Regression** | "분포 위의 점 1개 직접 찍기" | 하위 5% 지점 features에서 직접 학습. 분포 5-6개 quantile 점 동시 학습 |
| **GBM quantile loss** | "tree 모델로 점 찍기" | XGBoost/LightGBM objective를 quantile loss로 |
| **NGBoost** | "tree로 분포 parameter 예측" | 평균만이 아니라 (평균, 분산, 비대칭, 첨도) 묶음을 tree boosting으로 학습. **★ 도훈 ensemble 의도 부합** |
| **Mixture Density Network** | "여러 분포 섞어서 예측" | 신경망 출력이 multi-modal mixture |
| **Neural Lévy SDE** | "점프 + 변동성 명시 모델" | 갑작스러운 점프 (COVID -34%) 명시 모델링 ([arxiv 2509.01041](https://arxiv.org/abs/2509.01041), 2025) |
| **Diffusion model** | "노이즈에서 시계열 복원" | 학습 데이터에 노이즈 단계 추가, 역으로 복원 학습 ([Diffolio, arxiv 2511.07014](https://arxiv.org/abs/2511.07014), 2025) |
| **Conformal Prediction** | "어떤 모델 위에 씌우는 '90% 보장' 도장" | base model 무관, distribution-free coverage 보장 ([arxiv 2411.00520](https://arxiv.org/abs/2411.00520), 2024) |

---

## Section 1: Survey Scope (방법론 보강 — 27편 후보)

### 1.1 Paradigm × Paper 매트릭스

#### Paradigm A: Quantile Regression / Growth-at-Risk (★★★ 학술 정통, Tier 3/4 ensemble component)

| # | Paper | 년도 | Key | KR 적용 |
|---|-------|------|-----|---------|
| A1 | **Adrian-Boyarchenko-Giannone "Vulnerable Growth"** AER | 2019 | US GDP GaR 정통 — 5%/25%/50%/75% quantile penalized regression | KIF 2022 차용 |
| A2 | **Engle-Manganelli "CAViaR"** JBES | 2004 | quantile autoregressive | 학술 다수 |
| A3 | **Koenker-Bassett "Regression Quantiles"** Econometrica | 1978 | quantile regression 원조 | foundation |
| A4 | **Machine-learning Growth at Risk** IMF arxiv 2506.00572 | 2025 | quantile partial correlation regression + ML selection | EU/EM |
| A5 | **Calibrated quantile prediction for GaR** arxiv 2411.00520 | 2024 | Conformal + quantile combined | US GDP |
| A6 | **Multicountry Nonparametric Quantile Factor Model** T&F | 2024 | BART quantile factor | multi-country |

#### Paradigm B: Deep Distributional Forecasting (★★★ ★ **PRIMARY LOCK-IN** + B5 NGBoost 신규)

| # | Paper | 년도 | Key | KR 적용 |
|---|-------|------|-----|---------|
| B1 | **Forecasting Probability Distributions with DNN** arxiv 2508.18921 | 2025 | CNN/LSTM × {Normal, Student-t, skewed Student-t} | ★★★ **KOSPI 포함 6개 지수** + Neural Portfolio (annual 36.4%, SR 0.91) |
| B2 | **ESRNN-VAE downside risk** Frontiers Appl Math Stat | 2025 | ES-RNN + Variational Autoencoder combined | equity index |
| B3 | **DeepAR (probabilistic autoregressive)** Salinas et al Int. J. Forecast | 2020 | LSTM × Gaussian likelihood | retail/energy + 금융 |
| B4 | **Temporal Fusion Transformer** Lim-Arık-Loeff Int. J. Forecast | 2021 | Transformer × quantile loss multi-horizon | finance 다수 |
| **B5** | **NGBoost: Natural Gradient Boosting** Duan et al ICML | 2020 | ★ **Boosting + 분포 parameter 학습** — 도훈 ensemble 의도 정확 부합 | ML benchmark, KR 직접 검증 없음 (v3가 첫 KR 적용) |

#### Paradigm C: Conditional Density / Neural SDE (★★ Tier 4 ensemble component active)

| # | Paper | 년도 | Key | KR 적용 |
|---|-------|------|-----|---------|
| C1 | **Cenesizoglu-Timmermann "Density Forecast"** JF | 2008 | conditional density forecast classic | foundation |
| C2 | **Neural Lévy SDE for State-Dependent Risk** arxiv 2509.01041 | 2025 | jumps + heavy tails 명시 — Bates 2008 jump 정합 | cross-sectional equity |
| C3 | **CDE with Neural Networks: Best Practices** arxiv 1903.00954 | 2019 | KDE/MDN/normalizing flow benchmark | benchmark |

#### Paradigm D: Generative Diffusion (★★ — v3 미적용, v4 후보)

| # | Paper | 년도 | Key | KR 적용 |
|---|-------|------|-----|---------|
| D1 | **Diffolio** arxiv 2511.07014 | 2025 | DDPM portfolio, 9-47% baseline 개선 | multivariate equity |
| D2 | **Diffusion Financial Charts** arxiv 2509.02308 | 2025 | conditional diffusion (vol/trend) | finance generative |
| D3 | **Synthetic financial TS by diffusion** Quantitative Finance | 2025 | GBM-aligned SDE | heteroskedasticity |

#### Paradigm E: VaR/ES Machine Learning (★★ — 평가 metric foundation)

| # | Paper | 년도 | Key | KR 적용 |
|---|-------|------|-----|---------|
| E1 | **VaR/ES via stateful RNN** ScienceDirect S1057521924000346 | 2024 | joint VaR + ES, no distributional assumption | multi-index |
| E2 | **Statistical Learning of VaR/ES** arxiv 2209.06476 | 2022 | non-asymptotic convergence + NN | theoretical |
| E3 | **ML for Financial Tail Risk Forecasting** SSRN 5334625 | 2024 | comprehensive ML tail risk survey | survey |
| E4 | **Backtesting ES: duration & severity** arxiv 2405.02012 | 2024 | ES backtest beyond Christoffersen | backtest |
| E5 | **Christoffersen "VaR backtesting"** RFS | 2009 | unconditional + conditional coverage | foundation |
| E6 | **Gneiting-Raftery "Strictly Proper Scoring Rules"** JASA | 2007 | CRPS / log score | foundation |

#### Paradigm F: Conformal Prediction (★★ — Phase 5b 후처리 + Tier 3/4 component)

| # | Paper | 년도 | Key | KR 적용 |
|---|-------|------|-----|---------|
| F1 | **Conformal Time Series Forecasting** arxiv 2511.13608 | 2025 | non-exchangeable time series | time series |
| F2 | **Conformal Predictive Portfolio Selection** arxiv 2410.16333 | 2024 | conformal + portfolio | equity |
| F3 | **Online conformal inference multi-step TS** Monash WP 20-2024 | 2024 | adaptive online conformal | TS |

#### Paradigm G: KR-specific (★)

| # | Paper | 년도 | Key | KR 적용 |
|---|-------|------|-----|---------|
| G1 | **Tail risk forecasting with overnight info** arxiv 2402.07134 | 2024 | semi-parametric + overnight | tail risk |
| G2 | NYU V-Lab GARCH/AMEM KOSPI 분석 | ongoing | KOSPI volatility benchmark | KR direct |

#### 별도: Ensemble 학술 base (Section 5.4 참조)

| # | Paper | 년도 | Key |
|---|-------|------|-----|
| ENS1 | **Schapire "Strength of Weak Learnability"** | 1990 | Boosting 원조 — 도훈 의도 정통 |
| ENS2 | **Freund-Schapire "AdaBoost"** JCSS | 1997 | sequential weak → strong |
| ENS3 | **Friedman "Gradient Boosting Machine"** Ann Stat | 2001 | GBM lineage |
| ENS4 | **Breiman "Random Forest"** Mach Learn | 2001 | Bagging |
| ENS5 | **Lakshminarayanan "Deep Ensembles"** NIPS | 2017 | seed ensemble |
| ENS6 | **Gneiting "Combining probability forecasts"** | 2008 | Linear Pool 분포 ensemble |
| ENS7 | **Geweke-Amisano "Optimal pooling"** | 2011 | validation-based weight |
| ENS8 | **Jacobs et al "Mixture of Experts"** Neural Comput | 1991 | regime-specific expert |

### 1.2 Read priority (★ Tier 4 정합 14편)

**Deep read 7편 (Primary B + Tier 4 ensemble component + 평가 foundation)**:
- **B1 KOSPI deep distributional 2025** ★★★ (reproduce 대상)
- **B5 NGBoost Duan 2020 ICML** ★★★ (★ 신규 — 도훈 ensemble 의도 핵심)
- **C2 Neural Lévy SDE 2025** (Phase 5d active, Tier 4 component)
- **A1 Adrian 2019 AER** (Phase 5c baseline, Tier 3/4 component)
- **E5 Christoffersen 2009** (VaR backtest foundation)
- **E6 Gneiting-Raftery 2007** (CRPS foundation)
- **F1 Conformal TS 2025** (Phase 5b 후처리, Tier 3/4 component)

**Light read 7편 (비교 / 보조)**:
- **B2 ESRNN-VAE 2025** (B 보강)
- **B3 DeepAR** / **B4 TFT** (B foundation 2편)
- **A5 Conformal GaR 2024** (A + F 결합 참고)
- **E1 RNN VaR/ES 2024** (B 비교 reference)
- **E4 ES backtest 2024** (평가 metric 강화)
- **G1 KR overnight 2024** (KR 보강)

---

## Section 1.5: ★ v3 Methodology Lock-in — Paradigm B (Deep Distributional Forecasting + NGBoost)

**Lock-in 시점**: 2026-05-24 도훈 mandate (Plan v0.3 / v0.4 누적)
**근거**: paper B1 (arxiv 2508.18921) KOSPI 직접 검증 + B5 NGBoost (도훈 ensemble 의도)

### 1.5.1 무엇을 하는가 — B1 (LSTM) + B5 (NGBoost) 병행

**B1 (LSTM 정통)**: 신경망이 분포 parameter 직접 출력
```
F̂(r|x_t) = skewed_t( r ; μ̂(x_t), σ̂(x_t), ν̂(x_t), λ̂(x_t) )
[μ̂, σ̂, ν̂, λ̂] = LSTM(x_t) → FC head 4-output
Loss = -(1/T) Σ_t log f̂(r_{t+21} | x_t)   (NLL)
```

**B5 (NGBoost 신규)**: tree boosting이 분포 parameter 학습
```
F̂(r|x_t) = D( r ; [μ̂, σ̂, ν̂, λ̂](x_t) )
   where D ∈ {Normal, LogNormal, Laplace, Exponential, skewed-t (custom)}

학습:
  init: F̂_0 = 평균 분포 (모든 t에 같은 parameter)
  for m = 1 ... M (e.g., M=500):
    g_m = ∇_θ NLL(F̂_{m-1}; r_t)   -- Natural Gradient (Fisher 정합)
    Tree_m fit to g_m
    F̂_m = F̂_{m-1} + η · Tree_m(x_t)
  최종: F̂_M = 분포 forecaster
```

**비유**: 100명 학생이 차례로 답안 보완 — 1번이 평균만 맞추고, 2번이 1번 오류 보완, ..., 100번까지 누적 = 정확한 분포 답안.

### 1.5.2 KOSPI 적용 명세 (B1 vs B5 비교)

**v0.5 정정** (AMENDMENT E02/E03/E07/E08): paper-direct verified architecture spec.

| 항목 | B1 (LSTM × skewed-t) | B5 (NGBoost) |
|------|---------------------|--------------|
| Universe | KOSPI200 index level | 동일 |
| Horizon | h=21일 (월간) primary | 동일 |
| Features | v2_alt_data inherit (audit 후) | 동일 |
| Architecture | **LSTM 3-layer 128/64/32 → dense output (p params)** (paper actual) | **Tree depth ∈ {3,4,5,6}, M ∈ {500, 1000, 2000} (paper Section 4 sweep), η ∈ {0.001, 0.01, 0.1}** |
| Distribution | skewed Student-t (Fernandez-Steel 1998 transform) | **Normal / Lognormal / Laplace / Exponential (paper built-in) + skewed-t custom (v3 신규 implement)** |
| Lookback | **Sequence length 10 (paper Table 1 baseline)**, v3 expansion {10, 20, 30, 60, 90, 120} | feature engineering 별도 (lagged returns + rolling vol) |
| Output | **distribution param count p ∈ {2, 3, 4}** (N/STD/SSTD) | parameter set per distribution choice |
| Cost | GPU 학습 (~2-3h per config × 100 trial = 200-300h GPU) | CPU 학습 (~10-30min per config × 100 trial = 17-50h CPU) |
| Interpretability | LSTM hidden state hard | tree feature importance 직접 |
| KR 검증 | **paper B1 직접 (Table 2 KOSPI LSTM-SSTD LPS=1.2847, CRPS=0.5165 best 6 model)** | **없음 (paper UCI tabular only; v3가 첫 KR equity 적용)** |
| **시계열 처리** | walk-forward expanding window min 1008 train + 504 test (paper) | **★ i.i.d. assumption (paper Section 5 미해결) — v3에서 purging/embargo 5-fold CV 별도 implement (Lopez de Prado 2018)** |

### 1.5.3 평가 + Derived metric (B1/B5 공통)

- 학습 평가: NLL, CRPS, LPS
- 분포 형태 검증: PIT histogram, reliability diagram
- Risk metric derived:
  - `P(r ≤ -5%)`, `P(r ≤ -7%)`, `P(r ≤ -10%)` — 약세 확률 (도훈 mandate)
  - `VaR_95 = F̂^{-1}(0.05 | x_t)`, `ES_95 = E[r | r ≤ VaR_95]`
- VaR backtest: Christoffersen 2009 UC + CC, Kupiec POF, ES dual (arxiv 2405.02012)

### 1.5.4 학술 reported 정량

**v0.5 정정** (AMENDMENT E01/E04/E05/E06): paper-direct verified numbers.

**B1 paper (arxiv 2508.18921, 2025) — Michańków**:
- **Data**: 6 indices (S&P/BVP/DAX/WIG/Nikkei/**KOSPI**), daily 2000-01-03 ~ 2021-12-31, n=2,487 walk-forward forecasts (Table 1).
- **KOSPI distributional eval (Table 2 paper)**: LSTM-SSTD **LPS=1.2847 / CRPS=0.5165 (best)** vs CNN-N 1.3349/0.5285. LSTM 일관 best 6 indices.
- **KOSPI VaR backtest (Table 3 paper)**: LSTM-STD 1% VaR exceedance 0.84% (Christoffersen PASS), LSTM-SSTD 0.84% PASS. 5% level LSTM-N 5.42% (Kupiec + Christoffersen PASS).
- **GARCH 비교 (Table 5)**: paper는 **VaR exceedance % only** vs GARCH. CRPS direct GARCH 비교는 paper 본문에 없음 (DNN 내부 비교만, Tab 2).
- **PIT calibration**: KOSPI 모든 model PIT p < 0.05 reject (sample n=2,487 너무 큼). DAX는 LSTM-SSTD PIT uniform 가장 가까움.
- ❌ **삭제 (v0.4 hallucination)**: "Neural Portfolio annual 36.4%, Sharpe 0.91" — **paper에 portfolio backtest / Sharpe 결과 자체 없음**. LPS/CRPS/PIT + VaR backtest만.
- ❌ **삭제 (v0.4 hallucination)**: "CRPS 4-15% 개선 vs GARCH" — paper Table 5는 VaR exceedance만, CRPS GARCH 직접 비교 부재.

**B5 paper (Duan et al 2020 ICML, arxiv 1910.03225v4)**:
- **Data**: UCI tabular regression 9 datasets (Boston/Concrete/Energy/Kin8nm/Naval/Power/Protein/Wine/Yacht/Year MSD). **금융 dataset 자체 없음**.
- **NLL 개선 (Table 1)**: NGBoost vs Deep Ensembles / MC dropout / Concrete Dropout / GP / GAMLSS:
  - Boston: NGBoost 2.43 vs Deep Ensembles 2.41 (-0.8%, NGBoost slight worse)
  - Energy: NGBoost 0.60 vs Concrete 0.66 (+9.1%, NGBoost best)
  - Protein: NGBoost 2.81 vs all others 2.81~2.89 (+0~2.8%)
  - Wine: NGBoost 0.91 vs others 0.91~1.05 (+0~13.3%)
  - Yacht: NGBoost 0.20 vs Deep Ensembles 1.18 (outlier 큰 격차)
  - **Range 0~10% (Yacht outlier 제외), Plan v0.4 "5-15%" over-statement**.
- Tabular data fast training (GBM 수준)
- **KR / 금융 직접 검증 paper 전무 — v3가 first KR equity application (paper Section 5 misspecification 일관성 미해결 점에 주의)**
- ❌ **v0.5 추가 명시**: paper i.i.d. assumption — 시계열 적용 시 별도 purging/embargo CV 필요.

### 1.5.5 v3 진행 순서 (★ Tier 4 정합 갱신)

| Phase | 작업 | Paradigm component | 산출 |
|-------|------|-------------------|------|
| **5a-1** | **B1 prototype** (LSTM × skewed-t) | B1 | paper B1 reproduce + KR feature panel fit |
| **5a-2** | **B5 NGBoost prototype** | B5 | tree boosting × distribution 학습, CPU fast |
| **5a-3** | **B1 vs B5 비교** + Linear Pool ensemble | B1+B5 | within-Paradigm B ensemble |
| **5b** | **Conformal post-hoc** | B(1+5) + F | Distribution-free coverage 보장 |
| **5c** | **LASSO Quantile baseline** + Tier 3 Linear Pool | A + (B1+B5+F) | paradigm shift 정량 측정 + 3-way ensemble |
| **5d** | **Neural Lévy SDE** + **Tier 4 Full Mixture** | C + (B1+B5+A+F) | jump 보강 + 5-way ensemble |

### 1.5.6 장단점 (B1+B5 combined)

| 장점 | 단점 |
|------|------|
| ✅ KR 시장 직접 검증 (B1) + ensemble diversity (B5) | ❌ Tuning surface 2배 (LSTM + NGBoost 둘 다 tuning) |
| ✅ Multi-distribution 비교 (4종) | ❌ B5 KR 검증 없음 (v3가 first) |
| ✅ Boosting paradigm 도훈 의도 정합 | ❌ Compute: LSTM GPU 200-300h + NGBoost CPU 17-50h |
| ✅ Linear Pool ensemble 자연 | ❌ B5 sequential LSTM 패턴 capture 약함 |
| ✅ Interpretability 보강 (NGBoost feature importance) | |

---

## Section 2: Paradigm 선택 기준

### 2.1 정량 scoring (6 dimension)

| Dimension | 기준 |
|-----------|------|
| D1 학술 정통도 | top-tier + 최신 paper count |
| D2 KR data 가용성 | RAWDATA + alt data + FRED + KRX options + overnight |
| D3 Label complexity | parametric ~ non-parametric tuning surface |
| D4 Multi-horizon support | h=5/21/63 동시 학습? |
| D5 Computational cost | 학습 + inference time, GPU 요구 |
| D6 Interpretability | risk manager attribution 가능? |

### 2.2 Short-list 결정 (★ Lock-in confirmed + Tier 4 ensemble)

- **★ Primary: Paradigm B (B1 LSTM + B5 NGBoost 병행)** — 2026-05-24 도훈 mandate
- **Tier 4 Ensemble: Full Paradigm Mixture (B1 + B5 + A + F + C)** Linear Pool — 2026-05-24 도훈 mandate
- Lock-in 변경 trigger: Phase 5a B1 reproduce 실패 (KR feature 적용 시 CRPS 개선 < 0) 시 도훈 mandate 재검토

---

## Section 3: v3 Entry Trigger

### 3.1 폴더 init

```
04_Research/decision_framework/bearish_forecast_v3/
├── PLAN.md
├── 00_literature/                   # Phase 1-3 산출
│   ├── paradigm_matrix.md
│   ├── paper_summary.md
│   └── v3_algorithm_shortlist.md
├── 01_data/                         # Phase 5+
├── 02_targets/
├── 03_models/                       # 5a B1/B5, 5b F, 5c A, 5d C
├── 04_evaluation/                   # CRPS + Christoffersen + ensemble diag
├── 05_orthogonality/
├── 06_reports/
├── scripts/                         # Phase 5+ R/Python
├── config/                          # hyperparameter + ensemble weight
└── tests/                           # PIT loader + bear date audit
```

### 3.2 Cycle 51 lesson checklist 의무 (v3 진입 전 ALL PASS)

- [ ] `02_Infrastructure/sanity_checks/bear_date_audit.R` 4/4 PASS
- [ ] `02_Infrastructure/validation/pit_enforcement.R::validate_label_direction()` ≥ 95% PASS
- [ ] `.claude/rules/data_table_shift_convention.md` 정합 (shift `n=H, type="lead"` only)
- [ ] AX-008 Verification Triangulation (Forge + Codex + Architect 2/3 PASS)

### 3.3 평가 metric 변경 (PR-AUC 폐기 → distributional metrics)

| Metric | 출처 | 용도 |
|--------|------|------|
| **NLL** | parametric distribution | primary training loss |
| **Pinball loss** (τ ∈ {0.05, 0.10, 0.15, 0.20, 0.25, 0.50}) | Koenker-Bassett 1978 | quantile eval |
| **CRPS** | Gneiting-Raftery 2007 JASA | full distribution proper score |
| **LPS** | classical | distribution likelihood |
| **PIT** | Rosenblatt 1952 | calibration histogram |
| **Christoffersen UC + CC** | Christoffersen 2009 RFS | VaR backtest |
| **Kupiec POF** | Kupiec 1995 | unconditional coverage |
| **ES dual (duration + severity)** | arxiv 2405.02012 (2024) | ES backtest |
| **DM test (HAC lag ≥ 21)** | Diebold-Mariano 1995 | sig comparison |
| **Reliability diagram + ECE** | Gneiting-Balabdaoui-Raftery 2007 | calibration visual |
| **Spearman ρ (cross-model)** | classical | ensemble diversity check ★ |

### 3.4 WT 생성 시점

- Survey + Paradigm B prototype 검증까지 **WT 외부**
- Phase 5a-2 (B1+B5 prototype) 결과 도훈 mandate 시 정식 WT 생성

---

## Section 4: Risks & Tradeoffs

| Risk | 영향 | Mitigation |
|------|------|-----------|
| R1: full distributional 학습 복잡 + tuning surface 큼 | 구현 + 시간 비용 ↑ | Phase 5a-1 (LSTM × skewed-t) paper B1 reproduce부터 시작, hyperparameter는 paper 값 inherit |
| R2: Distributional metric (CRPS/pinball)은 PR-AUC와 다름 | 학술 base 약하면 ceiling 판단 모호 | paper B1 KOSPI 결과 (CRPS 4-15%) 정량 benchmark |
| R3: KR multi-horizon distributional 학술 사례 적음 | KR fit 불확실 | B1 (KOSPI 직접) + G1 (KR overnight) + V-Lab KOSPI |
| R4: v2 features 그대로 사용 시 paradigm shift 효과 약화 | label 변경만으로 ceiling 못 깰 가능 | feature 재선정 + paradigm shift 둘 다 평가 |
| R5: 5-seed inflation 함정 재발 (v2 Cycle 58 lesson) | seed-noise를 신호로 오해 | 15-seed strict + paired bootstrap CI + Spearman ρ cross-cycle |
| R6: Paradigm B Christoffersen CC 부분 PASS (paper B1) | tail coverage 불충분 가능 | Phase 5b Conformal post-hoc로 distribution-free 보장 |
| R7: skewed-t 가정이 KOSPI 실제 분포와 다를 경우 | parametric mis-specification | NLL + PIT에서 감지 → MDN / B5 (다른 distribution) 보강 |
| R8: B Lock-in으로 다른 paradigm 발견 시 변경 옵션 포기 | survey가 A/C 더 promising | Lock-in 변경 trigger 명시 |
| **R9** | **Hyperparameter tuning val set overfit (data snooping)** | 보고 CRPS와 OOS gap | Nested CV (outer test set strict separation) + Stage 3 Test set 1회 strict |
| **R10** | **15-seed × Optuna trial 폭증 compute cost** | GPU 자원 한계 | Two-stage: Stage 1 = 1-seed 100 trials, Stage 2 = top 5 × 15-seed |
| **R11** | **AutoML (autogluon/FLAML) 미적합 (custom NLL skewed-t)** | manual tuning 부담 | Optuna + PyTorch Lightning combo 표준화 |
| **R12 (★ 신규)** | **Ensemble diversity 부족 시 SIG_WORSE 재발 (v2 58C/58D lesson)** | mean/stacking → noise 추가 | Spearman ρ < 0.8 mandate (per-pair) + stacking 배제 retain + Linear Pool only |
| **R13 (★★ v0.5 신규)** | **Paper hallucination — v0.4 본문에 인용된 정량이 paper 자체에 없는 경우 (E01-E14 12건 검출)** | Phase 5 reproduce 무효 위험 | AMENDMENT_v0.5.md CR-V06 의무: paper-cite 정량 보고 시 paper-direct verification 또는 ACCESS_FAIL 명시. 모든 figure/table reference 필수 |
| **R14 (★★ v0.5 신규)** | **Architecture / hyperparameter mismatch — v0.4 가 paper actual과 다른 spec 인용 (E02 LSTM 3-layer / E03 seq=10)** | reproduce 무효 + Phase 5 결과 무의미 | CR-V02 의무: Phase 5a-1 prototype은 paper actual spec (3-layer 128/64/32, seq=10) baseline reproduce 우선. Stage 2부터 expansion |

---

## Section 5: 산출물 + Timeline

### 5.1 산출물 4 file (survey phase)

1. `PLAN.md` (본 문서) — paradigm lock-in + Tier 4 ensemble + entry trigger + B deep dive
2. `00_literature/paper_summary.md` — 14편 read summary (Deep 7 + Light 7) + 핵심 수식 + KR 적용
3. `00_literature/paradigm_matrix.md` — 7 paradigm × 6 dimension scoring + Tier 4 ensemble 정합
4. `00_literature/v3_algorithm_shortlist.md` — B1+B5 Lock-in + Tier 4 Full Mixture 확정 + Phase 5a-d algorithm

### 5.2 Timeline (Q autonomous)

| Phase | 작업 | 시간 | 도구 |
|-------|------|------|------|
| 1 | Deep read 7편 (B1/B5/C2/A1 + E5/E6/F1) PDF download + 정독 | **2-2.5h** | WebFetch arxiv PDF / Read |
| 1' | Light read 7편 (B2/B3/B4/A5/E1/E4/G1) skim | **1-1.5h** | WebFetch / skim |
| 2 | Paper summary 작성 | **1.5-2h** | Write summary.md |
| 3 | Paradigm matrix + shortlist 확정 | **30min-1h** | Write matrix.md + shortlist.md |
| 4 | 도훈 confirm checkpoint | **30min** | 보고 + redirect |
| **Total survey** | | **5.5-7.5h** | |

→ Phase 5 (구현)은 별도 cycle. Phase 5a-d 누적 예상 14-23h GPU + 17-50h CPU (Tier 4 정합).

### 5.3 Tuning Protocol 명세 (Stage 1-4)

#### 5.3.1 Why multi-seed (Section 6 추가 reference)

신경망 학습은 무작위 과정 → 단일 seed = noise + signal. **15-seed 평균이 진짜 실력**. v2 Cycle 58 cherry-pick 사고 (v5h 5-seed best 0.295 → 15-seed 0.226) 재발 방지.

#### 5.3.2 Seed vs Hyperparameter 함정 구분

- **Hyperparameter** = 모델 *구조적 가설* (lookback / hidden) — 다른 데이터에서 재현 → tuning OK (단 nested CV)
- **Seed** = *우연한 시작점* — 재현 X → best 1개 선택 금지

#### 5.3.3 4-Stage 정합

| Stage | 방법 | Seed | 의미 |
|-------|------|------|------|
| **Stage 1 탐색** | Optuna TPE 100 trial | 1-seed=0 고정 | 후보 좁히기, 빠름 |
| **Stage 2 재검증** | Top 3-5 config × 15-seed × 5-fold CV | 15-seed | 통계적 confirm |
| **Stage 3 Final test** | best 1 config × 15-seed × Test set 1회 | 15-seed | 도훈 보고용 (cherry-pick 불가) |
| **Stage 4 Production** | 학습 weight 1 set fix | 1 weight | deploy, 보고 성능 = Stage 3 mean ± CI |

#### 5.3.4 Hyperparameter Search Space (B1 + B5)

**B1 (LSTM × skewed-t)** — v0.5 정정 (AMENDMENT E03 paper baseline=10이라 lookback 확장 범위에 10 포함):
- **lookback ∈ {10, 20, 30, 60, 90, 120}** (paper baseline=10 포함)
- **hidden_size 구조 ∈ {(128,64,32) paper-default, (64,32,16), (256,128,64), (128,64), single 64}** (paper 3-layer 정합)
- **num_layers ∈ {2, 3, 4}** (paper actual=3, ablation symmetric)
- dropout ∈ [0.0, 0.5] uniform (paper 0.02 baseline)
- lr ∈ [1e-5, 1e-2] log-uniform (paper Adam lr=0.002 baseline)
- weight_decay ∈ [1e-6, 1e-2] log-uniform (paper L2=0.002 baseline)
- batch_size ∈ {32, 64, 128} (paper 128 baseline)
- epochs 300 + early stopping (paper)
- **Stage 1 baseline = paper exact spec (3-layer 128/64/32, seq=10, dropout=0.02, L2=0.002, lr=0.002, batch=128, epochs=300+ES) reproduce 의무 (AMENDMENT CR-V02)**

**B5 (NGBoost)**:
- distribution ∈ {Normal, LogNormal, Laplace, skewed-t-custom}
- n_estimators ∈ {100, 300, 500, 1000}
- learning_rate ∈ {0.001, 0.01, 0.1}
- tree_depth ∈ {3, 4, 5, 6}
- minibatch_frac ∈ [0.5, 1.0]
- natural_gradient (True/False)

#### 5.3.5 Optuna TPE 설정

- Sampler: TPESampler(seed=42)  -- 재현 가능
- Pruner: MedianPruner (별로인 trial 중단, 시간 30-50% 절약)
- Direction: minimize val CRPS (primary), val NLL (secondary)
- Multi-objective 옵션: CRPS + Christoffersen UC + ECE 동시 (Pareto)
- CV: walk-forward purged 5-fold + embargo 21d (Lopez de Prado 2018)

### 5.4 ★ Ensemble Strategy — Tier 4 Full Paradigm Mixture (도훈 mandate 2026-05-24)

#### 5.4.1 도훈 mandate

> "약한 학습모델 결합으로 더 강한 학습모델 구축" = Schapire 1990 "Strength of Weak Learnability" 본질 정의.

#### 5.4.2 4-Tier 구조 (도훈 Tier 4 선택)

| Tier | 내용 | Component | Phase |
|------|------|-----------|-------|
| Tier 1 | **NGBoost 도입** — Boosting + distributional | B5 | 5a-2 |
| Tier 2 | Architecture diversity (LSTM + CNN + Transformer) within B | B1 variants | 5a sub (조건부) |
| Tier 3 | Paradigm diversity (B + A + F) Linear Pool | (B1+B5) + A + F | 5c |
| **Tier 4 ★** | **Full Paradigm Mixture (B + A + F + C + NGBoost)** | **(B1+B5) + A + F + C** | **5d** |

#### 5.4.3 Linear Pool 수식 (Gneiting 2008 표준)

```
F̂_ensemble(r | x_t) = Σ_i w_i · F̂_i(r | x_t)

where:
  F̂_i ∈ {F̂_B1, F̂_B5, F̂_A, F̂_F, F̂_C}  (5 component)
  w_i ≥ 0,  Σ w_i = 1
  
Weight 결정 (Geweke-Amisano 2011):
  w_i ∝ 1 / val_CRPS_i   -- inverse CRPS weighting
  또는
  w_i = optimal pool via convex optimization (val NLL 최소화)
```

#### 5.4.4 Diversity Mandate (Spearman ρ < 0.8)

v2 lesson (cycle 58 Spearman ρ 0.977 사고) 재발 방지:

```
모든 component pair (i, j)에 대해:
  Spearman_ρ(F̂_i(VaR_95), F̂_j(VaR_95)) < 0.80  ← strict
  
Spearman ρ ≥ 0.80 인 pair는:
  - 한 component 제외 OR
  - 다른 distribution / horizon으로 재학습 후 재측정
```

#### 5.4.5 ❌ Stacking 배제 (v2 58D lesson)

- v2 Cycle 58D: Ridge / XGB meta-learner stacking → SIG_WORSE (-0.06)
- 원인: meta-learner가 val set overfit
- v3 mandate: **Linear Pool only**, Stacking 배제

#### 5.4.6 Ensemble Diagnosis (Phase 5c/d 산출물)

각 ensemble 단계에 mandatory diagnosis:
- per-component CRPS (B1 / B5 / A / F / C)
- per-pair Spearman ρ matrix (5×5 = 10 pair)
- ensemble Linear Pool weight (Geweke-Amisano)
- ensemble vs best single component CRPS sig test (DM test HAC)
- ensemble vs simple mean baseline (validation)

#### 5.4.7 학술 base (Section 1.1 ENS1-ENS8 참조)

| 학자 | 연도 | 핵심 |
|------|------|------|
| Schapire | 1990 | Strength of Weak Learnability (도훈 의도 원조) |
| Freund-Schapire | 1997 | AdaBoost |
| Friedman | 2001 | GBM |
| Duan et al | 2020 ICML | NGBoost (B5) |
| Gneiting | 2008 | Linear Pool 분포 ensemble |
| Geweke-Amisano | 2011 | Optimal pool weight |
| Lakshminarayanan | 2017 NIPS | Deep Ensembles (seed) |
| Jacobs et al | 1991 | Mixture of Experts (regime) |

---

## 참조

### 학술 (paradigm + ensemble)

- **A (Quantile/GaR)**: Adrian 2019 AER / Koenker-Bassett 1978 / Engle-Manganelli 2004 / IMF 2025 / Conformal GaR 2024 / BART quantile 2024
- **B (Deep Distributional) ★ PRIMARY**: KOSPI DNN 2025 / ESRNN-VAE 2025 / DeepAR 2020 / TFT 2021 / **NGBoost Duan 2020**
- **C (Density / Neural SDE)**: Cenesizoglu-Timmermann 2008 / Neural Lévy SDE 2025 / CDE NN 2019
- **D (Diffusion)**: Diffolio 2025 / Diffusion charts 2025 / Synthetic TS 2025 (v3 미적용, v4 후보)
- **E (VaR/ES ML)**: Christoffersen 2009 / Gneiting-Raftery 2007 / RNN VaR/ES 2024 / ES backtest 2024 / ML tail risk 2024
- **F (Conformal)**: Conformal TS 2025 / Conformal portfolio 2024 / Online conformal 2024
- **G (KR)**: KR overnight 2024 / NYU V-Lab KOSPI
- **★ ENS (Ensemble)**: Schapire 1990 / Freund-Schapire 1997 / Friedman 2001 / Breiman 2001 / Lakshminarayanan 2017 / Gneiting 2008 / Geweke-Amisano 2011 / Jacobs 1991

### v2 inherit (학습)

- `04_Research/decision_framework/bearish_forecast_v2_alt_data/STATUS_BUGGY_ERA.md`
- `04_Research/decision_framework/bearish_forecast_v2_alt_data/RESEARCH_CHARTER_v2_forward.md`
- `04_Research/decision_framework/bearish_forecast_v2_alt_data/outputs/04_evaluation/cycle58_FINAL_HONEST_REPORT.md`

### Cycle 51 lesson

- `.claude/rules/data_table_shift_convention.md`
- `02_Infrastructure/sanity_checks/bear_date_audit.R`
- `02_Infrastructure/validation/pit_enforcement.R`

### Qvest 헌법

- `.claude/rules/pit.md` (C1~C15)
- `.claude/rules/axioms.md` (AX-000~008)
- `.claude/rules/research_philosophy.md` (7 QEPM Modern Trends)

---

## Change log

- **v0.1** (2026-05-24): 도훈 mandate full distributional + plan 반영 초안. 12-15편 후보.
- **v0.2** (2026-05-24): 도훈 mandate 쉽게 설명 + 최신 방법론 보강. Section 0 신규 / paradigm 7개 26편 확장 (B Deep Distributional + D Diffusion + F Conformal 신규) / R6-R7 추가 / timeline 6-8h.
- **v0.3** (2026-05-24): 도훈 mandate ★ Paradigm B Primary Lock-in. Section 1.5 신규 (B 수식/KOSPI 적용/Phase 5a-d ordering) / Read priority B-focused 재배치 / timeline 4.5-6h.
- **v0.4** (2026-05-24): 도훈 mandate ★ **B5 NGBoost 추가 + Tier 4 Full Paradigm Mixture ensemble + Stacking 배제 retain + Multi-seed/Hyperparameter 함정 명문화**. Section 1.1 B5 신규 (NGBoost Duan 2020) + ENS1-ENS8 ensemble base 신규 / Section 1.5 B1+B5 병행 명세 / Section 5.3 Tuning Protocol 4-Stage 명문화 (Optuna TPE + Search Space + Why multi-seed) / Section 5.4 신규 Ensemble Strategy (4-Tier + Linear Pool + Spearman ρ < 0.8 + Stacking 배제 + Geweke-Amisano weight) / R9-R12 추가 / Read priority 재배치 (Deep 7: B1+B5+C2+A1+E5+E6+F1) / timeline 5.5-7.5h.
- **★ v0.5** (2026-05-24 Session 84) — **Phase 1 deep read 7편 verification 결과 v0.4 본문 12건 사실 오류 정정 + Phase 5 entry criteria 강화**. Q-Lead B1 paper direct read + subagent 6편 verification (paper_deep_read_subagent_output.md 596줄) → 정정안 AMENDMENT_v0.5.md (E01-E14 12건 + CR-V01-V06 entry criteria 6건) + R13/R14 risk 신규 + §1.5.2 (LSTM 3-layer 128/64/32, seq=10) + §1.5.4 (Neural Portfolio Sharpe 0.91 hallucination 제거, NLL 5-15% → 0~10% 정정) + §5.3.4 (B1 hyperparameter search paper baseline 정합) + memory `feedback_paper_cite_verification.md` recurring lesson 적립. 도훈 GO 결정 2026-05-24.
