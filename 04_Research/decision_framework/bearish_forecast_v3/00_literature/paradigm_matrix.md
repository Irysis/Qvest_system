# v3 Paradigm Matrix — 7 Paradigm × 6 Dimension Scoring

**작성**: 2026-05-24 KST Session 84 (Phase 3)
**Owner**: Q-Lead / 도훈 mandate
**Source**: `PLAN.md` v0.5 §1.1 + `paper_summary.md` Phase 1 통합
**상태**: Phase 3 산출물 1/2

---

## Scoring 기준 (PLAN.md v0.5 §2.1)

| Dimension | 기준 | Scale |
|---|---|---|
| **D1 학술 정통도** | top-tier journal + 최신 paper count | 1-5 (5=top) |
| **D2 KR data 가용성** | RAWDATA + alt data + FRED + KRX options + overnight 정합성 | 1-5 |
| **D3 Label complexity** | parametric ~ non-parametric tuning surface (낮을수록 단순 → 점수 ↑) | 1-5 |
| **D4 Multi-horizon support** | h=5/21/63 동시 학습 native 지원? | 1-5 |
| **D5 Computational cost** | 학습 + inference time, GPU 요구 (낮을수록 점수 ↑) | 1-5 |
| **D6 Interpretability** | risk manager attribution 가능? | 1-5 |

---

## 7 Paradigm Scoring Matrix

### A. Quantile Regression / Growth-at-Risk

**Component**: A1 Adrian-Boyarchenko-Giannone 2019 AER / A2 Engle-Manganelli CAViaR / A3 Koenker-Bassett 1978 / A4 IMF ML-GaR 2025 / A5 Conformal GaR 2024 / A6 BART quantile 2024

| Dim | Score | 근거 |
|---|---|---|
| D1 | 5 | AER + Econometrica + IMF — top-tier 정통. Foundation paper 1978부터. |
| D2 | 4 | RAWDATA + KOSPI200 + FRED 모두 사용 가능. KR NFCI proxy 구축 가능. |
| D3 | 4 | Quantile loss (Koenker-Bassett) 간단 + interpretable. Tuning surface 작음. |
| D4 | 3 | h-period quantile estimation 표준. Multi-h는 별도 fit 필요 (joint optimization 미흡). |
| D5 | 5 | LASSO/linear quantile regression CPU few seconds. |
| D6 | 5 | Coefficient β_τ(NFCI) 직접 interpretable — risk manager attribution 명확. |
| **합** | **26/30** | **★★★ baseline 강함, Tier 3/4 ensemble component** |

### B. Deep Distributional Forecasting (★ Primary Lock-in)

**Component**: B1 Michańków 2025 (KOSPI direct) / B2 ESRNN-VAE 2025 / B3 DeepAR 2020 / B4 TFT 2021 / **B5 NGBoost 2020 (도훈 ensemble 의도 핵심)**

| Dim | Score | 근거 |
|---|---|---|
| D1 | 5 | arxiv 최신 (B1 2025 KOSPI 직접) + ICML (B5) + Int J Forecast (B3/B4). Multi top-tier. |
| D2 | 5 | KOSPI200 daily return → B1 paper 직접 사용. v3 inherit 가능. |
| D3 | 2 | LSTM × skewed-t hyperparameter surface 큼 (lookback / hidden / num_layers / dropout / lr / wd / batch / dist). |
| D4 | 4 | DeepAR multi-horizon native; B5 NGBoost는 horizon별 separate model이 보통. |
| D5 | 2 | LSTM GPU 200-300h × 100 trial (B1). NGBoost CPU 17-50h (B5). |
| D6 | 3 | LSTM hidden state hard. NGBoost feature importance 직접. Mixed. |
| **합** | **21/30** | **★★★★ KR 직접 검증 + 도훈 mandate Primary Lock-in. compute cost 절감 필요 (Stage 1 → 2)** |

### C. Conditional Density / Neural SDE

**Component**: C1 Cenesizoglu-Timmermann 2008 JF / **C2 Neural Lévy SDE 2025** / C3 CDE NN 2019

| Dim | Score | 근거 |
|---|---|---|
| D1 | 4 | JF (foundation) + 최신 arxiv 2025 (Neural Lévy). |
| D2 | 3 | C2 paper US S&P 500만 — KR 적용 paper 부재 (extrapolation). v0.5 정정 (E10). |
| D3 | 2 | Drift/diffusion/jump intensity/jump dist 4 component parameterization. RQA + permutation entropy 추가 → tuning surface 큼. |
| D4 | 4 | Multi-horizon heads native (1D/1W/2W/1M) — C2 paper 정합. |
| D5 | 3 | NN 학습 + quasi-MLE. CPU/GPU mid. |
| D6 | 3 | jump intensity / size distribution interpretable; drift NN black-box. |
| **합** | **19/30** | **★★ Tier 4 ensemble component (jump augmentation)**. Portfolio 단독 Sharpe ≈ 0 (E10 정정). |

### D. Generative Diffusion (v3 미적용, v4 후보)

**Component**: D1 Diffolio 2025 / D2 Diffusion charts 2025 / D3 Synthetic TS 2025

| Dim | Score | 근거 |
|---|---|---|
| D1 | 4 | arxiv 2025 최신, multi paper. |
| D2 | 2 | KR 적용 paper 부재. Diffolio multivariate equity (paper에 KR 없음). |
| D3 | 1 | Diffusion model 학습 + sampling cost 큼. Tuning surface 최대. |
| D4 | 3 | Conditional diffusion h 다양. |
| D5 | 1 | DDPM 학습/sampling GPU 매우 큼. |
| D6 | 2 | Generative — interpretability 어려움. |
| **합** | **13/30** | **★ v3 미적용 / v4 후보**. |

### E. VaR/ES Machine Learning (평가 metric foundation)

**Component**: **E5 Christoffersen 1998/2009** / **E6 Gneiting-Raftery 2007** / E1 RNN VaR/ES 2024 / E2 Statistical Learning VaR/ES 2022 / E3 ML tail risk 2024 / E4 ES backtest 2024

| Dim | Score | 근거 |
|---|---|---|
| D1 | 5 | RFS + JASA + IER — top-tier foundation. |
| D2 | 5 | 모든 KR risk model validation 표준 (Kupiec + Christoffersen + CRPS + ES backtest 적용 가능). |
| D3 | 5 | Test statistic LR ~ χ². Foundation simple. |
| D4 | 4 | UC/CC 1-period; ES backtest multi-step (arxiv 2405.02012). |
| D5 | 5 | Backtest CPU msec. |
| D6 | 5 | Coverage + Kupiec/Christoffersen breakdown 명확. |
| **합** | **29/30** | **★★★★★ 평가 metric foundation — ensemble component 아니지만 모든 Phase 평가 의무. v3 사용 표준** |

### F. Conformal Prediction (post-hoc + Tier 3/4 component)

**Component**: **F1 Conformal TS 2025** / F2 Conformal Portfolio 2024 / F3 Online conformal TS 2024

| Dim | Score | 근거 |
|---|---|---|
| D1 | 4 | arxiv 2025 review + arxiv 2024 portfolio 응용. |
| D2 | 3 | F1 paper simulated only (real stock 부재, v0.5 정정 E11). KR 적용은 extrapolation. |
| D3 | 4 | SCP / WCP / ACI / EnbPI / BCP 4 family. Algorithm simple. |
| D4 | 2 | Univariate focus (multivariate future work). multi-step PI는 limitation 명시. |
| D5 | 4 | SCP / WCP CPU 매우 cheap. EnbPI bootstrap M=25 — moderate. |
| D6 | 4 | Prediction interval width + coverage 직접 interpretable. |
| **합** | **21/30** | **★★ Phase 5b post-hoc wrapper (B+F) + Tier 3/4 ensemble component**. ACI / EnbPI는 mean shift 강건. |

### G. KR-specific

**Component**: G1 KR overnight tail 2024 / G2 NYU V-Lab GARCH KOSPI

| Dim | Score | 근거 |
|---|---|---|
| D1 | 3 | arxiv 2024 + V-Lab ongoing. Top-tier 부족. |
| D2 | 5 | KR 직접 검증 paper. |
| D3 | 3 | Semi-parametric + overnight info. Moderate. |
| D4 | 2 | h=daily 위주. |
| D5 | 4 | GARCH CPU few sec. NN moderate. |
| D6 | 4 | Overnight + intraday separation interpretable. |
| **합** | **21/30** | **★ supplementary benchmark + KR check**. |

---

## 종합 Ranking (D1-D6 합산)

| Rank | Paradigm | 합 | Tier 4 정합 |
|---|---|---|---|
| 1 | **E. VaR/ES ML (foundation)** | 29/30 | 평가 표준 (component 아님) |
| 2 | **A. Quantile / GaR** | 26/30 | Tier 3/4 component (Phase 5c) |
| 3 (tie) | **B. Deep Distributional** | 21/30 | **★ Primary Lock-in** |
| 3 (tie) | **F. Conformal** | 21/30 | Phase 5b post-hoc + Tier 3/4 |
| 3 (tie) | **G. KR-specific** | 21/30 | supplementary benchmark |
| 6 | **C. Neural SDE** | 19/30 | Tier 4 component (jump) |
| 7 | **D. Diffusion** | 13/30 | v4 후보 (v3 미적용) |

---

## Tier 4 Full Paradigm Mixture 정합 (PLAN.md v0.5 §5.4)

```
Linear Pool F̂_ensemble(r|x_t) = Σ_i w_i · F̂_i(r|x_t)

Components (5):
  F̂_B1: Paradigm B (LSTM × skewed-t)         — Phase 5a-1
  F̂_B5: Paradigm B (NGBoost custom skewed-t)  — Phase 5a-2
  F̂_A:  Paradigm A (LASSO Quantile / GaR)     — Phase 5c
  F̂_F:  Paradigm F (Conformal post-hoc)       — Phase 5b
  F̂_C:  Paradigm C (Neural Lévy SDE)          — Phase 5d

Weight: w_i ∝ 1 / val_CRPS_i (Geweke-Amisano 2011)
Diversity: Spearman ρ(F̂_i VaR_95, F̂_j VaR_95) < 0.80 strict
Stacking: 배제 (v2 58D lesson)
```

**Phase 5d Tier 4 활성화 조건**:
- 5 components 모두 individual val CRPS > simple baseline (ensemble 의미)
- pair Spearman ρ < 0.80 strict (diversity confirmed)
- Linear Pool ensemble vs best single DM test sig (p < 0.05)

---

## Paradigm 선택 justification

**Primary Lock-in: Paradigm B (B1 + B5)** — 도훈 mandate 2026-05-24:
- D2 KR data: B1 paper KOSPI 직접 사용 (paper에 portfolio 결과는 없으나 distributional forecast 정량 정합)
- D1 학술 정통도: arxiv 2025 KOSPI + ICML 2020 NGBoost
- 위험: D3 (tuning surface 큼) + D5 (compute cost) — Stage 1-2-3 Tuning Protocol로 완화
- **★ AX-007 lesson 정합**: single-paradigm Lock-in이 risk → 5 components Tier 4 ensemble로 분산

**평가 metric Foundation: Paradigm E** — 모든 phase에서 사용:
- Log score (NLL) — training loss
- CRPS — primary forecast eval
- Kupiec + Christoffersen — VaR backtest
- ES dual — Expected Shortfall backtest

**Post-hoc wrapper: Paradigm F (Conformal)** — Phase 5b:
- B distribution-free coverage 보강
- ACI / EnbPI는 mean shift 강건 (KR regime switching 대응)

**Ensemble component: Paradigm A (GaR) + C (Neural Lévy)** — Phase 5c/d:
- A: paradigm shift 정량 측정 baseline
- C: jump distribution 추가 diversity

---

## v3 미적용 paradigm

- **D Diffusion** — v4 후보 (compute cost / interpretability 부적합)
- **G KR-specific** — supplementary benchmark (Section 5d 비교에서만)

---

## 참조

- `PLAN.md` v0.5 §1.1 / §2.1 / §2.2
- `paper_summary.md` Phase 1 Deep 7편 통합
- `AMENDMENT_v0.5.md` E01-E14 정정안

---

## Change log

- 2026-05-24 Session 84 — Phase 3 paradigm_matrix 작성 (PLAN.md v0.5 + paper_summary 정합).
