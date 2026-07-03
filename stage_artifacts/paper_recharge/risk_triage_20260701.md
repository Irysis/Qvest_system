# RISK Paper Queue Triage — 2026-07-01

**Source**: `mode_queue_20260701.json` risk 8편 (arxiv). Triage by Q-Lead risk-triage agent.
**Mandate (도훈)**: 적재 큐 병렬 소진 — 각 논문 verdict 의무, 전부 소진.
**현 시스템 기준**: book=STR_1715 (factor model + M4 BOCPD/AR-absorption/R05 tail overlay), 총SR 1.95. risk-research가 Σ=BΩB'+D+tail+stress+crowding 산출. 데이터: Factor DB 327팩터(`load_month_factors`), `.cache/RAWDATA.parquet`, FRED/ECOS, DART. **불가: 옵션·CDS·HFT·뉴스·cross-market.**
**측정 규율**: 표준 통계함수만(자체합성 금지), metric_type 라벨, PIT C1~C15.
**✅ BM 데이터 valid (2026-07-01 정정)**: 초기 "BM_Ret 손상 ≤2025-09" 전제 **철회** — 외부 yfinance 실제 KOSPI(^KS11)와 BM_Close 소수점까지 일치 검증. 2025-26은 **실제 +250% 멜트업**(KOSPI 2400→8476), 2026-03 −19%·2026-04 +30%는 **실제 조정·반등월**(손상 아님). full 데이터(2026 포함) 전부 valid — 오히려 2026 극단변동이 tempered skew-t 꼬리적합·스트레스에 **최상의 실측 fat-tail 데이터**. #6 테스트 full-period 재실행 완료(아래).

**핵심 신규성 판정 근거 (factor panel 실측 조회)**: 327팩터 패널은 risk 공간 포화 —
- 유동성: `L01/09/10/25_Amihud`, `L08_Roll_Spread`, `L11_Kyle_Lambda`, `L14_Price_Impact`, `L18_Eff_Spread_Proxy` (Roll/Kyle/Amihud 전부 보유)
- 모멘텀/추세: `M01~M32` (12-1,6-1,resid,trend,accel...) + `D55_Vol_Trend`
- 변동성/베타: `D01~D58` (Parkinson/GK/RS/YangZhang/vol-of-vol/EWMA + Dimson/Blume/Frazzini-Pedersen beta)
- 꼬리: `D43_Skewness`,`D44_Kurtosis`,`D16_Coskew`,`D17_Cokurt`,`D25/26_Tail_Beta`,`D47_CVaR`,`D48/49_VaR`,`R01~R06`
- 크라우딩: `CR01~CR11` (sector comovement, vol concentration, momentum crowding...)

---

## 1. 2606.30193 — Hidden Dependence and Aggregate Tail Risk

**Method (1줄)**: 의존-불확실성(marginals 고정, copula만 perturb) 하 worst-case tail-risk 상한 — "hidden dependence" 구성으로 임의 tail event에서 reference 분포를 지배하는 랜덤벡터 존재 증명. 작은 Gaussian-dependence 이탈이 자본요구를 극적으로 키울 수 있음을 신용리스크에 적용.

**신규성·구현성**: 순수 수리금융 정리(distributionally-robust risk aggregation). KR 구현 가능하나 **자본요구/규제 신용리스크 문맥** — 우리는 long-only 25종 equity book이지 credit portfolio 자본규제 대상이 아님. 기여는 alpha도 Σ-추정 개선도 아니고 "Σ의 dependence 불확실성을 인정하면 tail이 과소평가될 수 있다"는 *경계 정리*. 현 risk-research가 DCC/Gerber로 dependence를 점추정하는데, 이 논문은 그 점추정의 robustness 상한을 줌 — 개념적으로는 stress-test severity 정당화에 연료.

**Verdict**: **REFERENCE** — dependence-uncertainty가 tail을 과소평가한다는 정리는 risk-research stress 시나리오 severity 근거로 인용 가능(현 stress가 historical-crisis 기반인데 "Gaussian dependence 가정의 fragility"를 명시 보강). 직접 backtest 부적합(credit/규제자본 문맥, alpha 무관, 25종 equity에 worst-case copula 상한은 over-engineering).

---

## 2. 2606.29018 — Liquidity-Based Audit of Algorithmic Trading

**Method (1줄)**: 전략의 trade+price history만으로 net liquidity demand 식별 — multi-period regret 분해의 부호가 Kyle(1985) informed/market-maker를 분류, AR(1) 비용 하에서 = strategy size × Roll(1984) implied spread². N 상관전략 합산 시 violation이 N² fire-sale externality(closed-form).

**신규성·구현성**: 라우터note "팩터 L08 중복" **확인** — `L08_Roll_Spread` + `L11_Kyle_Lambda` 보유. 핵심 method(Roll spread, Kyle lambda)는 이미 cross-sectional 팩터로 있음. 논문의 *신규분*은 (a) 전략을 net liquidity consumer/provider로 분류하는 audit statistic (b) N² fire-sale welfare loss. 이건 **단일전략 alpha가 아니라 multi-strategy crowding 진단** — 우리 CR-family(`CR07_Momentum_Crowding` 등)와 같은 공간. 게다가 audit은 *우리 자신의 체결 history*가 있어야 의미(live execution log 필요) — 현재 페이퍼 단계라 자기 체결 데이터 없음. 데이터: 우리 RAWDATA로 Roll/Kyle은 이미 산출하나, 논문의 audit은 "전략 trade tape"가 입력이라 부적용.

**Verdict**: **SKIP** — 핵심 추정량(Roll spread² × size) 이미 L08/L11로 보유(중복), 신규분(strategy-level liquidity audit + N² fire-sale)은 자기 체결 tape 필요(페이퍼 단계 부재) + multi-strategy crowding은 CR-family 영역. 자본효과=execution cost 진단이지 alpha 아님.

---

## 3. 2606.26835 — Order-Three Obstruction to Conditional Price-of-Risk Attribution

**Method (1줄)**: 포트의 적분된 조건부 제곱-Sharpe(price-of-risk premium)를 causal driver로 귀속 — benchmark 대비 intervention-stable premium + confounding wedge + information loss로 분해. driver filtration이 price filtration에 immersed일 때만 well-posed. 1·2-driver는 통과하나 3-driver pooled에서 future innovation 노출되는 order-three obstruction(Bernstein 쌍별-독립 유추) + permutation-calibrated screen으로 planted order-3 leakage 탐지.

**신규성·구현성**: 매우 정교한 attribution 이론(judge/governor의 ⑦ Attribution & Feedback Loop 공간). 신규성 高(order-3 immersion obstruction은 문헌에 드묾). 구현: synthetic panel은 가능하나 **실 KR book에 적용하려면 명시적 causal driver DAG + conditional Sharpe functional 추정**이 필요 — 현 attribution은 Brinson + Carhart-4 linear 분해이지 conditional-squared-Sharpe causal이 아님. 자본효과: attribution *진단 정밀화*이지 alpha/Σ 개선 아님. 3개+ driver를 pool할 때만 발현하는 코너케이스 — 현 book은 single sleeve(STR_1715), driver pooling 구조 아직 없음.

**Verdict**: **REFERENCE** — attribution leakage(여러 driver pooling 시 pairwise screen이 못 잡는 anticipative coupling)는 향후 multi-driver/multi-sleeve attribution(judge ⑦) 설계 시 *경고 연료*. 현 단계 직접 테스트 부적합(single-sleeve book, causal DAG 부재, conditional-Sharpe attribution 미구현, alpha 무관). [TESTABLE 잠재: 자가발전이 multi-driver 귀속으로 가면 permutation screen 재방문]

---

## 4. 2606.23596 — Anatomy of the Market: Body-Tail Test of Factor Models

**Method (1줄)**: 투자가능 시장포트를 시가총액 누적비중 내림차순으로 body(상위 p 캡)/tail(나머지)로 분할 — 두 leg는 직전일 가중으로 market을 정확히 재구성(R_M=w_B·R_B+w_T·R_T). 각 leg 초과수익을 6개 팩터모형(CAPM/FF3/Carhart/FF5/FF6/q5)에 회귀해 leg-alpha 산출, 공동귀무 H0:α_B=α_T=0 Wald(NW lag-21). **q5(=Hou-Mo-Xue-Zhang: MKT+ME+IA+ROE+EG)만** 9/9 비율서 reject(body α −56bp/tail α +181bp, 상쇄) — 다른 모형은 0/9~4/9. 패턴은 **EG(expected growth) 블록에 거주**(EG 제거 시 9/9→2/9 붕괴). 500-random-split placebo는 4.1%(≈nominal). CRSP 1967-2024.

**신규성·구현성**: 신규성 高(spanning 강한 모형이 분해서는 체계적 잔차-α를 남긴다 — "aggregate fit·spanning·leg-alpha는 별개 객체"). **순수 sorting+회귀라 KR 구현 가능**(cap 누적분할 + cross-sectional LS 팩터 + NW-OLS). **치명적 caveat**: 판별력이 **q5(Global-q daily ROE/IA/EG)에 특정** — KR엔 Global-q 동치 일별시리즈 없음. KR 팩터패널로 q5-ANALOGUE(Q02_ROE, IN01_CapEx/Assets=IA, GR02_Earnings_Growth=EG proxy) 구성 가능하나 EG는 realized-growth proxy(forward expected-growth 아님), KR ROE 팩터는 사실상 死(ann +0.11%, t=0.04). 자본효과: 팩터모형 *진단*(어느 모형이 시장 횡단을 못 가격하나)이지 alpha 아님. 우리 score_eff는 composite이지 q-factor 구조 아님.

**Verdict**: **TESTABLE** (실측 완료 — 구조적-spirit 복제. q5-faithful 불가하나 진단 가치로 실행)

**테스트결과** (`bodytail_23596_results.json`, monthly 2005-01~2026-04, 256m, KR q5-analogue, NW lag-3, metric_type=empirical_factor_regression): **패턴 KR 미복제.** ① CAPM-analogue: 전 비율서 offsetting(neg body/pos tail) 나타나나 **전부 비유의**(|t|max 1.30) — 논문이 경고한 small-cap-tail 기계적 효과. ② FF-analogue·q5-analogue: 패턴 흡수(α→0, 대부분 비유의). ③ q5-analogue **1/7 reject**(p=0.95 극단 small-cap tail에서만), 게다가 **부호 역전**(body +0.1%/tail −2.0%, t −2.35 — 논문의 neg-body/pos-tail과 반대). ④ placebo random-split 3.5~7.0%(≈nominal 5%, 테스트 기계 정상 보정). **결론**: 논문의 body-tail leg-α 시그니처는 **US-q5(특히 EG factor) 고유 현상** — KR 팩터 analogue(EG=realized-growth proxy, ROE 死)로는 재현 안 됨. 추가 진단가치 없음(우리 모형은 q-factor 구조도 아님). screen-tier 아님(tradeable 신호 아닌 모형진단), 자본 무관.

---

## 5. 2606.20145 — Trends, Volatility, Correlations, Critical Phenomena

**Method (1줄)**: 현재 추세 강도(trend strength)로 미래 vol·상관 예측 — vol/corr이 강한 상승·하락 추세 중 매일 증가(특히 하락추세서 현저), 오늘 추세강도의 2차 다항식으로 정량화. 기존 mean-reversion vol 모델 보강. lattice-gas-near-critical 시장모델 지지.

**신규성·구현성**: 라우터note "추세=모멘텀 중복" 부분확인이나 **정확히는 다름** — 논문은 trend로 *수익*이 아니라 *vol/corr*를 예측(risk-model refinement). 우리는 `M01~M32` 모멘텀 + `D34~D42` realized vol + `D55_Vol_Trend`를 *별개 cross-sectional 팩터*로 보유하나, "trend strength → conditional Σ(vol·corr)" 매핑은 risk-research가 명시적으로 안 함(현 DCC/Ledoit-Wolf는 trend-conditional 아님). KR 구현 가능(RAWDATA로 trend·vol 산출). BUT: 자본효과 = Σ 예측 정밀화이지 alpha 아니고, M4 overlay(BOCPD regime)가 이미 vol-state 조건부 — trend→vol 2차 다항식은 M4의 단순화 버전일 소지(중복). down-trend서 vol↑는 우리 R05 tail overlay가 이미 포착.

**Verdict**: **REFERENCE** — "trend strength의 2차식으로 forward vol/corr" 매핑은 risk-research가 conditional-Σ 보강 시 인용 가능(현 DCC는 trend-conditional 아님). 직접 테스트 부적합: alpha 아님 + M4 regime overlay/R05 tail이 이미 vol-state 조건부(개념 중복) + lattice-gas critical는 우리 인프라 밖. cross-sectional 팩터(M*/D*) 중복은 라우터note대로.

---

## 6. 2606.19318 — Fitting Accumulated Returns with Tempered Skew-t

**Method (1줄)**: 누적(multi-day, τ=20~120일) 지수수익 분포 적합 — capped-Inverse-Gamma 확률변동성 SDE(변동성 κ₁⁻¹서 상한) → tempered Student-t → Jones-Faddy 비대칭깨짐 → tempered modified-JF Skew-t(좌/우 꼬리 지수 β_l<β_g, 손실 꼬리가 더 두꺼움). PDF는 confluent hypergeometric ₁F₁ 포함 closed-form. **핵심 발견**: τ 증가 시 멱법칙 꼬리가 유한값으로 tempering + **분산 m₂=θτ 선형(보존법칙)** + 양의 평균·음의 왜도. **VaR closed-form 없음**(PDF+수치적분 CCDF만). 적합 알고리즘 미명시(MLE/소프트웨어 불기재 — 복제 gap). S&P500 1980-2025, Gaussian/stable 비교 없음(자기 이전 비-tempered 모형과만 비교).

**신규성·구현성**: **신규** — 우리 D-family(D43_Skewness·D44_Kurtosis·D47_CVaR·D48/49_VaR)는 *횡단면 종목 팩터*이지 *지수 누적수익 시계열 분포모형*이 아님(중복 아님). KR 구현 가능(benchmark 일별→누적). 자본효과: tail/VaR/SES 모형 정밀화(risk-research tail 진단) — alpha 아님. 우리 R05 tail overlay는 drawdown-state 기반이지 모수적 꼬리분포 아님. **gap**: 완전 tempered-mJF PDF는 ₁F₁ + 음수인자 Γ + 미명시 적합법 → 실용적으로 Jones-Faddy skew-t(scipy `jf_skew_t`, 동일 비대칭 메커니즘) + Student-t로 proxy 적합이 합리적.

**Verdict**: **TESTABLE** (실측 완료 — 핵심 testable 예측 3종 검증; 완전 PDF 대신 scipy jf_skew_t/Student-t proxy)

**테스트결과** (`skewt_19318_results.json`, **full-period 재실행** KR benchmark 일별 2000~2026-06 6,529일 — BM valid 정정 반영, 2026 실제 극단변동 포함, 비중첩 누적블록 τ∈{20,40,60,90,120}, scipy MLE + KS/AIC, metric_type=empirical_distribution_fit. 절대 분포적합이라 BM-relative 아님): ① **논문 핵심 보존법칙 KR 복제 — 2026 극단데이터로 더 강화**: 누적분산 ~ τ **선형 R²=0.992**(slope 2.21e-4, intcpt≈5e-5 ≈원점통과 — 논문 m₂=θτ 형태 정확 일치), 평균~τ 선형 **R²=0.996**(≤2025-09 0.986/0.945 → full 0.992/0.996로 상승). 실제 멜트업 데이터가 linear-variance 보존법칙을 거의 완벽하게 만듦. ② **tempering 가시화**: 초과첨도 τ 증가에도 유한범위(0.8~1.8) 유지(daily 초과첨도 2026 포함 7.4 — 실제 fat-tail), Gaussian 0으로 안 붕괴 — "유한값으로 tempering" 정성 일치. ③ **비대칭**: 음의 왜도(daily −0.36) — 논문 β_l<β_g(손실꼬리 우세) 정합. 단 누적 τ서 멜트업 양의 드리프트로 부호 불안정(+0.04~+0.18). ④ **fat-tail 모형 압도**: Student-t가 **전 5개 τ서 Gaussian·JF-skew-t 모두 AIC 우승**(KS h=20: 0.068→0.033 반감) — full-period선 skew 4번째 파라미터 미정당화(왜도 부호 불안정), Student-t로 충분. ⑤ **꼬리정확도(자본관련) — 개선**: 1% VaR서 Gaussian 손실 +3.7pp 과소(−14.8% vs 실측 −18.5%), Student-t는 오차 **+1.3pp로 축소**(≤2025-09 +2.0pp보다 개선). **결론**: 논문의 분포물리(linear-variance 보존·tempering·음왜도)는 KR서 robust 복제(2026 극단포함으로 더 견고), fat-tail 모수모형이 Gaussian 대비 KR 꼬리 VaR 실질 개선. 단 완전 tempered-mJF의 skew 증분은 미입증 — Student-t가 전 τ 우승. **REFERENCE-grade 실용가치**: risk-research가 tail/SVaR 모형화 시 "Gaussian 금지, fat-tail 모수(Student-t 충분, df≈4.2~4.5, skew 불요) + variance=θτ 스케일링" 채택 근거. 신규 alpha/모듈 아님(분포모형 진단).

---

## 7. 2606.08141 — Structural Matrix AR (SMAR): Volume-Volatility-Returns

**Method (1줄)**: 수익·realized vol·거래량의 결합동학을 Structural Matrix Autoregressive로 대형차원 모델링 — VAR 대비 parsimonious, MDH(Mixture of Distributions Hypothesis)+효율시장 제약으로 구조식별. DJIA 2021-25 일별: vol이 거래활동의 주동인, cross-asset spillover가 장기 volume 변동의 50%+.

**신규성·구현성**: 라우터note "파생팩터 중복" **확인** — volume·vol·return 결합은 `L03_Volume_Mom`,`L13_Vol_Variance_Ratio`,`L05_Dollar_Volume` + D-family vol에 분산 존재. 핵심 발견(vol→volume 인과, MDH)은 cross-sectional alpha가 아니라 *시계열 spillover 구조*. SMAR은 매트릭스-AR 추정 — KR 구현 가능하나 (a) DJIA 30종 대상 모델을 KR 350종에 확장은 추정부담 (b) 산출이 FEVD/spillover이지 종목별 α̂ 아님 (c) volume-vol-return 동학은 우리가 alpha source로 안 씀(M4 regime은 price/vol 기반). 자본효과: 거래량 spillover 진단 — execution/impact 모델링에 가까움.

**Verdict**: **SKIP** — volume·vol·return 파생팩터 이미 L*/D* 보유(중복, 라우터note 확인), SMAR 산출은 spillover/FEVD 진단이지 alpha 아님. MDH 구조식별은 KR equity book 의사결정에 비-actionable(거래량 인과는 우리 신호공간 밖). 대형차원 matrix-AR 추정부담 대비 자본효과 불명.

---

## 8. 2606.07575 — Forward-Looking Stress Testing GPR-HS SVaR (SACS)

**Method (1줄)**: 규제 스트레스테스트(CCAR/ICAAP)용 Stressed-VaR을 forward macro 시나리오 하 안정 추정 — Hybrid GPR-HS(Gaussian Process Regression + Historical Simulation) + SACS(Scenario-Averaged Covariance Stabilization, 과거 위기국면 가중합으로 stress 공분산 구성). 3시나리오(서아시아전쟁/기후/AI버블) 252일 경로, SVaR −2.10~−2.22%.

**신규성·구현성**: forward-looking macro stress는 risk-research stress 진단 공간. **단, 이미 falsify된 영역과 인접** — 메모리 [[project-predictive-crisis-timer-forward-macro-null]] (2026-06-26): forward-macro 예측 위기 ONSET = settled-null, 외생충격 미가격(정보론적 한계). 본 논문은 ONSET *예측*이 아니라 시나리오-조건부 SVaR *추정 안정화*(다른 목적)이나, "서아시아전쟁/AI버블" 같은 내러티브 시나리오는 우리가 정량 macro factor(FRED/ECOS)로 매핑 불가. SACS(과거위기 가중 Σ)는 우리 historical-crisis stress와 동형. GPR vol 모델은 구현 가능하나 자본효과=SVaR 안정성(규제보고용)이지 alpha/book 개선 아님. 우리는 규제 SVaR 보고 의무 없음.

**Verdict**: **SKIP** — (a) SACS(과거위기 가중 stress-Σ)는 현 historical-crisis stress와 동형(증분 없음) (b) 내러티브 macro 시나리오(전쟁/AI버블)는 정량 FRED/ECOS 매핑 불가 (c) forward-macro 인접영역 이미 settled-null([[project-predictive-crisis-timer-forward-macro-null]]) (d) 규제 SVaR(CCAR/ICAAP)는 우리 의무 아님, alpha 무관. GPR-HS vol은 우리 DCC/EWMA로 대체.

---

## 종합 (8편 verdict)

| # | Paper | 신규성 | KR구현 | verdict |
|---|---|---|---|---|
| 1 | 2606.30193 Hidden Dependence Tail Risk | 高(정리) | 가능(credit문맥) | **REFERENCE** |
| 2 | 2606.29018 Liquidity Audit Algo | 중(L08중복) | 부분(체결tape필요) | **SKIP** |
| 3 | 2606.26835 Order-3 Attribution Obstruction | 高 | synthetic만 | **REFERENCE** |
| 4 | 2606.23596 Body-Tail Factor Test | 高(q5특정) | 가능(degraded) | **TESTABLE→미복제** |
| 5 | 2606.20145 Trends→Vol/Corr Critical | 중(M*/D*중복) | 가능 | **REFERENCE** |
| 6 | 2606.19318 Tempered Skew-t | 신규(분포) | 가능(proxy) | **TESTABLE→부분PASS** |
| 7 | 2606.08141 SMAR Volume-Vol-Return | 중(L*/D*중복) | 가능(부담) | **SKIP** |
| 8 | 2606.07575 GPR-HS SVaR SACS | 중 | 부분 | **SKIP** |

**소진 완료**: 8/8 verdict. REFERENCE 3 (#1,3,5) · SKIP 3 (#2,7,8) · TESTABLE-실측 2 (#4 미복제, #6 부분PASS). **신규 alpha/모듈 0** — risk 논문 전부 간접 자본효과(Σ/stress/attribution/tail 모형). 

**유일한 actionable take-away** (#6 tempered skew-t 실측, full-period 2000~2026-06): risk-research tail/SVaR 모형화 시 Gaussian 대신 **fat-tail 모수(Student-t df≈4.2~4.5로 충분, 1% VaR 오차 Gaussian +3.7pp → Student-t +1.3pp 개선) + 누적분산=θτ 선형 스케일링(R²=0.992, 원점통과)** 채택 권고. full-period선 skew 불요(Student-t 전 τ 우승). alpha 무관·book 무관이므로 capital-grade 아님 — risk-research 단계 모형선택 reference로만. (BM 데이터 valid 정정 반영 — 2026 실제 극단변동이 최상의 fat-tail 검증 데이터)

**기록 산출물**: `test_skewt_19318.py`+`skewt_19318_results.json` / `test_bodytail_23596.py`+`bodytail_23596_results.json` (모두 `stage_artifacts/paper_recharge/`).
