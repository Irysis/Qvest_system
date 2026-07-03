# 슈퍼팩터 방법론 문헌 서베이 (2026-07-03, 7계열 학술DB 검색·CrossRef 검증)

# 슈퍼팩터 방법론 서베이 — 7 계열 taxonomy

> 슈퍼팩터 = 다수 팩터/특성 → **단일 종목점수(또는 가중치)** 로 압축해 long-only top-25 포트를 구성하는 방법론 전체. 아래 7 계열은 "무엇을 학습하는가"(SDF loading → 잠재팩터 → 예측수익 → 팩터선별 → z-score 합성 → 가중치 직접 → end-to-end)의 축으로 배열. 모든 논문은 CrossRef/arXiv 메타데이터로 title·author·year·venue·DOI 실측 검증됨(환각 없음).

---

## 계열 1 — SDF / Bayesian shrinkage 추정 (KNS 본가 + 사촌·후속·비판)
**핵심 아이디어**: characteristic-managed 팩터 Fₜ=Z'R의 1·2차 적률(μ̄,Σ)에서 SDF 계수 b̂를 shrinkage/Bayesian prior로 추정해 다수팩터를 단일 SDF loading(=종목점수)으로 압축. **우리 KNS 구현의 본가.**

| 논문 | 저자·연도 | venue | 메커니즘 |
|---|---|---|---|
| **Shrinking the Cross-Section** ★우리 구현 | Kozak-Nagel-Santosh 2020 | JFE (NBER w24070) | b̂=(Σ+γI)⁻¹μ̄ ridge+elastic-net 3-fold CV → SDF loading |
| Interpreting Factor Models | Kozak-Nagel-Santosh 2018 | J. Finance 73(3) | near-arbitrage 부재 → SDF ∝ 소수 dominant PC (KNS 이론 토대) |
| Bayesian Solutions for the Factor Zoo (2 quadrillion models) | Bryzgalova-Huang-Julliard 2023 | J. Finance 78(1) | spike-and-slab prior + BMA → posterior-weighted 단일 SDF, weak-factor 자동 배제 |
| Comparing Asset Pricing Models | Barillas-Shanken 2018 | J. Finance 73(2) | F-통계 closed-form Bayesian model selection → 최고 posterior 팩터 subset |
| Arbitrage Portfolios | Kim-Korajczyk-Neuhierl 2021 | RFS 34(6) | 특성 예측력을 risk-loading에 먼저 귀속 → 잔여 abnormal-return만 포트 신호(위험우선) |
| Complexity in Factor Pricing (Virtue of Complexity) | Didisheim-Ke-Kelly-Malamud 2023 | NBER w31689 | random feature로 P≫T 확장 + 강한 ridge → KNS '축소'의 정반대 극 |

---

## 계열 2 — Latent factor / 차원축소 (IPCA·RP-PCA·three-pass·autoencoder)
**핵심 아이디어**: 팩터를 사전지정하지 않고 자료로부터 잠재팩터를 추정, 종목 기대수익을 loading×premium 하나로 요약. KNS와 형제(SDF-계열)이나 shrinkage 대신 **저차원 잠재구조 강제**로 과적합 억제.

| 논문 | 저자·연도 | venue | 메커니즘 |
|---|---|---|---|
| **Characteristics Are Covariances (IPCA)** ★1순위 대안 | Kelly-Pruitt-Su 2019 | JFE 134(3) | βᵢₜ=Zᵢₜ·Γ, latent fₜ와 Γ를 ALS 동시추정 → 다수특성→저차원 loading |
| Estimating Latent Asset-Pricing Factors (RP-PCA) | Lettau-Pelger 2020 | J. Econometrics 218(1) | PCA + 평균수익 penalty → 약하지만 SR-관련 팩터 복원 |
| Autoencoder Asset Pricing Models | Gu-Kelly-Xiu 2021 | J. Econometrics 222(1) | IPCA의 비선형 일반화 — β(z)=NN, no-arbitrage 제약 |
| Asset Pricing with Omitted Factors (three-pass) | Giglio-Xiu 2021 | J. Political Economy 129(7) | PCA 잠재공간으로 관측팩터 risk premium 편의없이 추정 |
| Three-Pass Regression Filter (many predictors) | Kelly-Pruitt 2015 | J. Econometrics 186(2) | 지도학습형 PLS — 목표(수익)와 공변하는 부분공간만 추출 |
| Forest Through the Trees | Bryzgalova-Pelger-Zhu 2025 | J. Finance 80(5) | decision tree로 종목 endogenous grouping, SDF-spanning split. OOS Sharpe 최대 3배 |
| Projected PCA | Fan-Liao-Wang 2016 | Annals of Statistics 44(1) | 수익을 특성공간에 사영 후 PCA — IPCA 이론 토대 |

---

## 계열 3 — 머신러닝 자산가격 (ML 기대수익/SDF 예측)
**핵심 아이디어**: 다수 characteristic을 ML 함수 g(z)로 매핑해 종목별 조건부 기대수익 E[r|z] 자체를 예측 → 슈퍼팩터 점수.

| 논문 | 저자·연도 | venue | 메커니즘 |
|---|---|---|---|
| **Empirical Asset Pricing via ML** ★정초 | Gu-Kelly-Xiu 2020 | RFS 33(5) | GBRT/RF/NN으로 94특성×macro→E[r]. 이득=비선형 상호작용 |
| Deep Learning in Asset Pricing | Chen-Pelger-Zhu 2024 | Management Science 70(2) | GAN adversarial no-arbitrage moment로 SDF weight를 딥넷 추정 |
| **ML vs Economic Restrictions** ★KR 경고 | Avramov-Cheng-Metzker 2023 | Management Science 69(5) | ML 초과수익의 상당분이 마이크로캡·고회전. 유동성필터+비용 시 소멸. long-leg·최근연도만 잔존 |
| Dissecting Characteristics Nonparametrically | Freyberger-Neuhierl-Weber 2020 | RFS 33(5) | adaptive group-LASSO로 독립·비선형 특성만 선별 |
| **Autoencoder in Chinese Stock Market** ★KR 최근접 실증 | Shu-Xiong-Zhang 2025 | Applied Economics | 공매도제약 EM(중국)서 **long-only는 선형 IPCA가 autoencoder보다 높은 Sharpe**. 중요팩터=liquidity·fundamentals·valuation |

---

## 계열 4 — Factor Zoo 축소 / 팩터선택 / 다중검정
**핵심 아이디어**: 슈퍼팩터 구성 *이전* 단계 — "373개 중 어느 게 진짜 독립정보인가"를 통계적으로 판정. KNS shrinkage와 상보(FGX 프루닝 후 KNS shrinkage).

| 논문 | 저자·연도 | venue | 메커니즘 |
|---|---|---|---|
| …and the Cross-Section of Expected Returns | Harvey-Liu-Zhu 2016 | RFS 29(1) | 다중검정 haircut → t>3.0 허들 (우리 PORT_t 2.95 원전) |
| Lucky Factors | Harvey-Liu 2021 | JFE 141(2) | orthogonalized bootstrap 순차선택 |
| **Taming the Factor Zoo** ★book-marginal 원전 | Feng-Giglio-Xiu 2020 | J. Finance 75(3) | double-selection LASSO로 신규팩터 marginal 기여 편의없이 검정 |
| Characteristics that Provide Independent Info | Green-Hand-Zhang 2017 | RFS 30(12) | pooled Fama-MacBeth → 독립 유의 ~12특성만 |
| A Transaction-Cost Perspective on Firm Characteristics | DeMiguel-Martín-Utrera-Nogales-Uppal 2020 | RFS 33(5) | 비용 넣으면 유의 특성 6→15개 (트레이드 상쇄로 회전율↓) |
| Replicating Anomalies | Hou-Xue-Zhang 2020 | RFS 33(5) | 452 아노말리 65% 복제실패, 마이크로캡·EW 아티팩트 규명 |
| Is There a Replication Crisis in Finance? | Jensen-Kelly-Pedersen 2023 | J. Finance 78(5) | Bayesian 복제 + **13-theme 클러스터링**(우리 RAMP 11군 정합), 93개국 OOS |
| Open Source Cross-Sectional Asset Pricing | Chen-Zimmermann 2022 | Critical Finance Review 11(2) | 319 예측변수 재현 라이브러리(ground-truth 풀) |

---

## 계열 5 — 합성 스코어 / 신호결합 (Composite Scoring)
**핵심 아이디어**: 각 신호를 횡단면 z-score/rank로 표준화 후 **equal-weight 합산** → Σ 역행렬(과적합원) 회피. 저-과적합 경로.

| 논문 | 저자·연도 | venue | 메커니즘 |
|---|---|---|---|
| Quality Minus Junk | Asness-Frazzini-Pedersen 2019 | Review of Accounting Studies 24(1) | profitability/growth/safety z-score 평균 → 단일 quality 점수 |
| Piotroski F-Score | Piotroski 2000 | J. Accounting Research 38(Suppl) | 9개 회계신호 0/1 이진 합산(0~9) — 가장 견고한 composite |
| Value and Momentum Everywhere | Asness-Moskowitz-Pedersen 2013 | J. Finance 68(3) | 음상관 신호쌍 50/50 결합 → 다변화 이득으로 composite Sharpe↑ |
| Parametric Portfolio Policies | Brandt-Santa-Clara-Valkanov 2009 | RFS 22(9) | (계열6과 중첩) w=w̄+θ'x, 점수=가중치 |
| Backtesting Strategies Based on Multiple Signals | Novy-Marx 2015 | NBER w21329 | 신호결합·선택의 t-팽창 정량화 + haircut (우리 DSR 게이트 근거) |

---

## 계열 6 — 직접 포트폴리오 / 파라메트릭 가중 (SDF 우회, 가중치 직접학습)
**핵심 아이디어**: μ̂·Σ 중간추정 없이 특성→가중치를 직접 사상해 효용/Sharpe 최적화. **우리 DPL(§5)의 학술 계보.**

| 논문 | 저자·연도 | venue | 메커니즘 |
|---|---|---|---|
| **Parametric Portfolio Policies** ★DPL 원형 | Brandt-Santa-Clara-Valkanov 2009 | RFS 22(9) | wᵢ=w̄+（1/N)θ'xᵢ, realized CRRA utility 직접 최대화. no-short 변형 제시 |
| Deep Parametric Portfolio Policies | Simon-Weibels-Zimmermann 2026(accepted) | Management Science | w=NN(x), 위험회피 γ가 복잡도 내생 규제. 비용·공매도제약 robust |
| AlphaPortfolio (deep RL) | Cong-Tang-Wang 2026 | NBER w35195 | Transformer+cross-asset attention→승률스코어, RL이 Sharpe 직접 최적화 |
| Bayesian Parametric Portfolio Policies | Herculano 2026 | SSRN 6299340 | θ에 prior — 불확실성 클수록 tilt 자동축소(낮은 turnover) |
| Characteristics and Non-Parametric Optimal Portfolio Policies | Auberson 2023 | SSRN 4570863 | w=g(x) 비모수 추정 — 선형 misspecification 회피 |

---

## 계열 7 — End-to-End / Deep Portfolio Optimization (미분가능 최적화층, 직접 SR) ★내 배정
**핵심 아이디어**: 예측과 최적화를 **하나의 미분가능 그래프**로 합쳐, downstream 의사결정 품질(net Sharpe)로 학습. two-step "error maximization" 회피. 계열 6의 신경망/최적화층 심화판.

| 논문 | 저자·연도 | venue | 메커니즘 |
|---|---|---|---|
| **OptNet: Differentiable Optimization as a Layer** ★기반 | Amos-Kolter 2017 | ICML (arXiv 1703.00443) | QP를 NN 층으로 임베드, 암묵적 미분으로 backprop → 제약 최적화층의 토대 |
| **Task-based End-to-end Model Learning in Stochastic Optimization** ★DFL 정초 | Donti-Amos-Kolter 2017 | NeurIPS (arXiv 1703.04529) | 예측모델을 최종 task objective로 직접 학습(decision-focused learning) |
| Differentiable Convex Optimization Layers (cvxpylayers) | Agrawal-Amos-Barratt-Boyd-Diamond-Kolter 2019 | NeurIPS (arXiv 1910.12430) | DPP를 미분 가능화, PyTorch/TF 층 제공 — 우리 DPL convex-layer 구현 도구 |
| **Deep Learning for Portfolio Optimization** ★대표 | Zhang-Zohren-Roberts 2020 | J. Financial Data Science 2(4), 114 cites | 특성→가중치 end-to-end, **Sharpe ratio를 손실함수로 직접 최적화** |
| **Integrating Prediction in Mean-Variance Optimization** ★MVO 통합 | Butler-Kwon 2021/22 | arXiv 2102.09287 (q-fin.PM) | 회귀예측을 MVO에 통합, batch-QP 미분. unconstrained/equality closed-form + inequality NN-QP |
| **End-to-End Risk Budgeting Portfolio Optimization with NN** ★게이팅 | Uysal-Li-Mulvey 2021 | arXiv 2107.04636 (q-fin.PM) | model-based 암묵적 최적화층 + **stochastic-gate 자산선택**으로 저수익·저변동 자산 제거. Sharpe 목적 시 OOS 1.16~1.24 (risk-parity 0.79 대비) |
| Smart "Predict, then Optimize" (SPO/SPO+) | Elmachtoub-Grigas 2022 | Management Science 68(1), 569 cites | decision-error를 반영한 SPO+ surrogate loss, 통계적 일관성 증명 |
| Enhancing Time Series Momentum Strategies Using DNNs | Lim-Zohren-Roberts 2019 | J. Financial Data Science 1(4) | 신호→position sizing을 Sharpe로 직접 학습(시계열 momentum) |
| E2EAI: End-to-End DL Framework for Active Investing | Wei-Dai-Lin 2023 | ACM ICAIF (arXiv 2305.16364) | factor selection→combination→stock selection→construction 전 파이프 end-to-end |
---
## 우리 시스템 이미 탐색(settled)

**우리 시스템이 이미 구현·검증한 것 (메모리 근거):**

1. **계열 1 KNS 본가 (SDF eigenvalue-shrinkage) = settled-negative.** [[project-kns-shrinking-cross-section]] (07-03): w24070 방법론을 한 치 변형 없이 구현(managed portfolio Fₜ=Z'R 327특성→b̂=(Σ+γI)⁻¹μ̄ η=2 + elastic-net eq.28 + 3-fold CV). canonical KOSPI200∪KQ150 2005-2026 long-only top-25 = **port_t +1.28 ≪ 2.95, calmar 0.40, oos_reten −1.01 (HARD 3종 전부 FAIL)**. pre-2018 t+2.57→2018+ −0.74 감쇠 재현. 명시 결론: "정본 SDF-shrinkage도 §6 직교≠수익 + KR SR 천장 초과불가, **shrinkage/SDF 방향 재시도 금지**."

2. **계열 6 직접 포트폴리오(DPL) = settled-negative.** [[project-dpl-vs-pg2-settled]] (06-26): 8config+GPU 동원해도 0.75~0.89 ≪ PG2 1.52. "재제안 금지." measurement-graduation §5에 DPL이 "구성 레이어"로 잔존하나 standalone은 죽음. → 계열 6/7의 순수 features→weights 학습은 이미 한 번 패배.

3. **계열 3 ML 자산가격 = discovery에서 다수 시도, screen-tier 강등.** [[project-discovery-substrate-phase0]] (06-30): 373 raw를 비선형 HGB로 재조합(계열3 GKX류) → 헤드라인 PORT_t 2.96(seed42)이나 6종 검증서 deflate(seed취약·book-marginal +0.047<0.05·2021+ 死). [[project-paper-pool-qepm-exhaustion]]: 논문풀 ~95% 소진.

4. **계열 4 Factor Zoo 축소 = 다중검정 게이트로 이미 내재화.** Harvey-Liu-Zhu t>3.0 → 우리 PORT_t 2.95 HARD, Feng-Giglio-Xiu double-selection → book-marginal ΔIR≥0.05, Jensen-KP 13-theme → RAMP Gate4 11 직교군. 즉 이 계열의 **판정 프레임은 이미 헌법에 흡수**됨(신규 백테 대상 아니라 게이트로 작동 중).

5. **계열 5 composite / KR value·momentum 감쇠 = 실증됨.** [[reference-kr-value-factor-decay]] V01~24 전수 post-2015 감쇠. [[project-kr-momentum-novel-hunt]] return-derived 모멘텀 3종 실패. → Value&Momentum·QMJ류 신호쌍 결합의 KR 원료가 약함이 확인됨.

6. **RAMP M-code (계열1·2 혼합) = graduation FAIL.** [[project-ramp-fullcycle-graduation]] (06-18): 102 승인팩터 264월 실측, 11 직교 경제군 결합 cap-w PORT_t 2.37 < 2.95, oos 0.15, calmar 0.37. "직교≠수익" M-code 레벨 확증.
---
## 유망 미탐색

**KR long-only에 아직 안 해본·EV 있어 보이는 방법론 (우선순위순):**

1. **계열 2 IPCA (Kelly-Pruitt-Su 2019) — 최우선.** 우리가 죽인 것은 KNS(SDF의 *mean* 경로 shrinkage)이지 IPCA(covariance/loading 경로 latent factor)가 아니다. 결정적 근거: **Shu-Xiong-Zhang 2025(중국 A주, 공매도제약·소형주 다수 = KR 최근접 시장)에서 long-only는 비선형 autoencoder보다 선형 IPCA가 높은 Sharpe.** 우리는 이미 KNS managed-portfolio(327특성) 인프라 보유 → 이식비용 최소. 시변 loading βᵢₜ=Zᵢₜ·Γ가 KR 국면전환(RAMP regime)을 자연 흡수. R `ipca` 패키지 존재.

2. **계열 1 Bayesian shrinkage 변형 (BMA-SDF / Bayesian PPP) — 미탐색 하위영역.** 우리 KNS는 **point-estimate(CV 불안정·PIT 배포서 −0.71 과적합)**였다. Bryzgalova-Huang-Julliard의 spike-and-slab BMA-SDF나 Herculano의 Bayesian PPP(θ에 prior, 불확실성 클수록 tilt 축소 → 낮은 turnover)는 감쇠 국면 계수 안정성을 명시적으로 개선. "shrinkage→Bayesian averaging"은 우리가 안 밟은 축. R `BayesianFactorZoo` 존재. 단 sweep형이라 DSR 게이트 적용.

3. **계열 7 End-to-End risk-budgeting + stochastic-gate 자산선택 (Uysal-Li-Mulvey 2021) — DPL 재도전의 정확한 각도.** 우리 DPL pilot이 죽은 이유는 순수 black-box features→weights였을 가능성. 이 논문의 **model-based 암묵적 최적화층 + 확률적 게이트로 "저수익·저변동 자산 제거"**는 우리 KNS 실패 패턴(마이크로캡·저품질주 오염, Avramov-Cheng-Metzker가 경고한 바로 그것)을 objective 안에서 직접 겨냥. cvxpylayers로 long-only/Σw=1/[0,0.20]/15bps native 삽입 가능.

4. **계열 7 SPO+ decision-focused loss (Elmachtoub-Grigas 2022) — 게이트 철학과 정합한 미탐색 학습목표.** 예측정확도가 아니라 **decision quality를 직접 최소화**하는 surrogate. 우리가 계속 관찰한 "rank-IC 강해도 PORT_t 약함"(measurement §2) 문제를 학습단계에서 구조적으로 해소. 선형 predictor + SPO+로도 random-forest 지배(원논문). KR ETF/top-25 rolling backtest로 저비용 검증 가능.

**공통 caveat**: 1·2는 latent/Bayesian이라 KNS와 다른 경로지만 §6 "직교≠수익"·KR SR 천장(~1.1)을 벗어난다는 보장 없음. 3·4는 DPL 재도전이라 [[project-dpl-vs-pg2-settled]]의 "재제안 금지"와 충돌 — 반드시 *새 구조적 차별점*(게이트/decision-loss)을 사전 명시하고 도훈 confirm 후 진행.
---
## 읽기 순서

**KNS 다음 읽을 순서 (우선순위 5-7편):**

1. **Kelly-Pruitt-Su 2019, "Characteristics Are Covariances (IPCA)", JFE 134(3)** — KNS의 covariance-경로 자매. 우리 managed-portfolio 인프라 직접 재사용. 1순위 실측 후보.

2. **Shu-Xiong-Zhang 2025, "Autoencoder Asset Pricing in Chinese Stock Market", Applied Economics** — KR 최근접 시장의 직접 실증. "long-only는 IPCA>autoencoder" + "중요팩터=liquidity·fundamentals·valuation" = KR 우선탐색군 힌트. IPCA 실측 전 필독.

3. **Avramov-Cheng-Metzker 2023, "ML vs Economic Restrictions", Management Science 69(5)** — 우리 KNS 실패(마이크로캡·감쇠)의 문헌적 진단. long-leg·최근연도 잔존이라는 유일한 희망 메시지가 재도전 조건 설정.

4. **Uysal-Li-Mulvey 2021, "End-to-End Risk Budgeting with NN", arXiv 2107.04636** — DPL 재도전의 정확한 각도(stochastic-gate 자산선택으로 저품질 제거). cvxpylayers 실장 청사진.

5. **Bryzgalova-Huang-Julliard 2023, "Bayesian Solutions for the Factor Zoo", J. Finance 78(1)** — point-estimate KNS의 Bayesian 대안. weak-factor posterior 배제.

6. **Elmachtoub-Grigas 2022, "Smart Predict, then Optimize", Management Science 68(1)** — decision-focused loss. "IC≠PORT_t" 문제의 학습단계 해법.

7. **Bryzgalova-Pelger-Zhu 2025, "Forest Through the Trees", J. Finance 80(5)** — 저차원·해석가능 SDF-spanning, 25종 집중 포트와 궁합. KNS 직접 대체 후보로 자주 인용.
---
## 정직한 유보

**정직한 유보 (AX-000 정직보고):**

1. **대부분이 KNS와 같은 감쇠벽에 부딪힐 개연이 높다.** IPCA·RP-PCA·BMA-SDF·autoencoder·arbitrage-portfolio 모두 본질적으로 long-short tangency/아비트라지 지향이다. KR no-short로 loading·잔차-α 상위분위만 절삭하면, 우리가 KNS/RAMP에서 실측한 두 벽 — ① §6 "직교≠수익"(잔차 직교라도 PORT_t 별개 게이트) ② **KR 횡단면 post-2017 cohort decay**(방법론 아닌 구조) — 을 그대로 만날 공산이 크다. 감쇠는 [[project-kns-shrinking-cross-section]]이 명시했듯 "방법론이 아니라 KR 횡단면 구조"이므로, 추정기를 바꾼다고 사라진다는 보장이 없다.

2. **계열 6/7(DPL·end-to-end)은 [[project-dpl-vs-pg2-settled]]에서 이미 settled-negative("재제안 금지").** 위 promising 3·4번을 진행하려면 "순수 black-box가 아니라 stochastic-gate/decision-loss라는 구조적 차별점"을 사전 등록하고 도훈 confirm이 반드시 필요하다. 그 차별점이 KR 258월 소표본 과적합을 실제로 이긴다는 증거는 아직 없다(원논문 전부 대형 US/글로벌 패널 전제).

3. **KR SR 천장 ~1.1**([[reference-kr-sr-ceiling-overlay]])은 25종 팩터선택의 실증적 상한이다. 계열 1~7 전부가 "팩터선택/결합"의 변주이므로, 이 천장을 넘는 유일하게 입증된 레버는 **overlay(β/regime timing)**뿐이라는 우리 실측과 상충한다. 슈퍼팩터 계열 자체가 SR 2.5의 주역이 되기 어렵다는 것이 가장 정직한 유보.

4. **검색 한계 (환각 방지 명시)**: 모든 논문의 title·author·year·venue·DOI는 CrossRef/arXiv 실측 검증. 그러나 (a) 각 논문의 **KR 특정 실증결과는 우리 시스템 미실행**(전망은 방법론+메모리 실증 기반 추론), (b) 일부 abstract는 CrossRef 미제공이라 메커니즘 설명이 표준 학술지식 조합, (c) AlphaPortfolio(NBER w35195)·Simon-Weibels-Zimmermann(MS accepted)·Herculano(SSRN)·Auberson(SSRN)은 미출판/워킹페이퍼 상태로 재현 리스크 큼(citations 0~소수), (d) Semantic Scholar/Google Scholar/jina SSRN은 세션 중 무응답/Payment Required로 CrossRef 단일 교차검증에 의존(CrossRef 인용수는 실제보다 과소집계 경향).