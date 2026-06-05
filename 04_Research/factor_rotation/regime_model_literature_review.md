# 국면 결정 모델 (Regime-Determination Models) — 학술 레퍼런스 검토

> 작성: 2026-06-05 · 의뢰: 도훈 ("국면 결정 모델에 대한 학술적 레퍼런스 검토") · Factor Rotation Mode 맥락
> 출처: 레포 문헌(`DERIVATIVES_REGIME_DETECTION_RESEARCH.md` D-01~50, `paper_catalog.md` KR-013/014/023, P189) + arXiv 원문 추출 + 웹 검증
> 목적: FR 모드가 의존하는 "국면 결정"의 학술 SOTA를 정리하고, 시스템 기존 자산(`02_Infrastructure/regime/` 20파일)과 매핑·갭 분석

---

## 0. 개념 프레이밍 — 국면 시스템의 3 레이어

국면 기반 전략은 항상 **3개 분리된 레이어**다. "국면 결정 모델"은 주로 ②를 가리키지만, 셋을 혼동하면 진단이 틀린다.

| 레이어 | 정의 | 학술 분파 | 시스템 자산 |
|---|---|---|---|
| **① State variables (feature)** | 국면을 *나타내는* 관측가능 신호 | VKOSPI/VRP/skew/credit/breadth/macro | `ktri_v3_builder`, `regime_vrp`, `regime_derivatives`, `fred_robust` |
| **② Regime-determination model** | feature → 잠재 국면 상태 *추론* | MS/HMM · Jump Model · GMM · change-point · turbulence | `msm_daily_refit`(2-state HMM), `regime_hmm`, `regime_garch`, `regime_cusum`, `regime_absorption_ratio`, `regime_ensemble` |
| **③ Regime→allocation 매핑** | 국면 상태 → weight | BL views · regime-conditional MVO · 0/1 switch · tree | `module_dispatcher`(rp+IR shrink), `regime_factor_alloc_engine`, `apply_regime_overlay` |

핵심 통찰(본 검토의 결론 선취): **시스템은 ①·②·③ 모두 갖췄으나, ②의 SOTA(Statistical Jump Model)가 없고, ③이 "단일 시장국면 → 모듈선택"이라 학술 SOTA(Shu-Mulvey의 "팩터별 국면 → BL")와 구조가 다르다.**

---

## 1. ②의 모델 계열 분류 (canonical → SOTA)

| 계열 | 대표 문헌 | 핵심 | 시스템 | 평가 |
|---|---|---|---|---|
| **A. Markov-Switching / HMM** | Hamilton (1989, *Econometrica*); Ang-Bekaert (2002); Guidolin (2011, survey) | 잠재 마르코프 체인 + 상태별 Gaussian. MLE/EM. 금융 국면의 표준 | ✅ `msm_daily`(2-state), `regime_hmm` | 성숙·해석가능. 단 Gaussian 가정·과전환·초기값 민감 |
| **B. Change-point / structural break** | Bai-Perron (2003); Page CUSUM (1954) | 분포 변화 시점 탐지. 사전 상태수 불요 | ✅ `regime_cusum` | online 탐지엔 지연. 사후 라벨링은 lookahead 위험 |
| **C. Volatility-state (MS-GARCH)** | Hamilton-Susmel (1994); Haas et al. (2004) | 변동성 레짐. 조건부 분산 전환 | ✅ `regime_garch` | vol 클러스터링 포착. 수익률 레짐과 불일치 가능 |
| **D. Systemic-risk / turbulence** | Kritzman-Li (2010, *FAJ* "turbulence"); Kritzman-Li-Page-Rigobon (2011, "absorption ratio") | Mahalanobis 거리 / PCA 흡수율 → 시스템 취약성 | ✅ `regime_absorption_ratio` | 위기 *조기경보*에 강함. 방향성(상승/하락) 약함 |
| **E. Mixture / clustering** | GMM; k-means | 비시계열 군집. 단순·빠름 | ✅ price-only GMM (L4) | 지속성(persistence) 미강제 → 과전환 |
| **F. ★Statistical / Sparse Jump Model (SJM)** | Bemporad et al. (2018); Nystrup et al. (2020, 2021 sparse); Aydinhan-Kolm-Mulvey-Shu (2024, *Annals of OR*) | HMM의 비모수 대안. **jump penalty λ로 지속성 명시 강제** + ℓ1 feature 선택 | ❌ **없음 (SOTA 갭)** | **현 SOTA.** HMM 대비 정확도·downside·robustness 우위(아래 §3) |
| **G. ML 직접매핑 (regime-free)** | Asset Allocation Forest (Yin-Shi 2024, P189) | state var → weight 직접 (②③ 통합, 명시적 국면 없음) | ❌ 없음 | 추정오차 회피·해석가능. DPL(`research_philosophy ④`)과 동류 |

---

## 2. 시장국면이 *왜* 팩터/모듈에 작동하(거나 안 하)는가 — 이론

- **Ang-Bekaert (2002)**: 국면 전환은 상관·변동성을 비대칭으로 바꿔, 정적 배분이 놓치는 시점 분산효과를 만든다 → 국면 배분의 이론적 근거.
- **Guidolin (2011)**: MS 모형이 in-sample 적합은 압도적이나 **OOS 경제적 가치는 거래비용·추정오차에 매우 민감** — 본 검토 §5의 핵심 경고.
- **KR 특수성** (레포 D-doc): Kang-Yoon (2015, *FRL*) VKOSPI **3-regime MS**(저/중/고변동), **US VIX가 KR 국면전환을 Granger-cause**; Kim et al. (2016) Hamilton **2-regime** — 저변동 국면에선 환율·금리가 KOSPI에 영향, 고변동 국면에선 무반응. → **KR 국면모델은 US 신호를 1급 feature로 써야 한다**(D-doc Key Takeaway #1·#4).

---

## 3. ★ FR 모드 직결 SOTA: Shu & Mulvey (2024) — "Dynamic Factor Allocation Leveraging Regime-Switching Signals"

> arXiv [2410.14841](https://arxiv.org/abs/2410.14841) (레포 카탈로그 KR-013). **이것이 곧 "팩터 로테이션"의 학술 정본.**

**② 국면 모델**: Sparse Jump Model, **K=2**, jump penalty λ + ℓ1 feature 선택.
**① feature (~20, 팩터별 active-return에서)**: EWMA active return, RSI, stochastic %K, MACD(8/21/63d), downside deviation, active beta + 시장환경(market EWMA, log-VIX, 2Y, 10Y-2Y slope).
**핵심 구조차이**: **단일 시장국면이 아니라 *팩터마다* 별도 국면을 추론**(각 팩터 초과수익에 SJM 적용).
**③ 매핑**: 국면조건부 평균 active return → **Black-Litterman views** → MVO(long-only, fully-invested, δ=2.5, EW cov hl 126d, TE 1~4% 타깃).
**universe**: MSCI USA + 6 스타일(Value/Size/Momentum/Quality/LowVol/Growth), 전부 저비용 ETF.

**OOS 결과 (2007–2024, 5bps, expanding window, 월 refit)**:
| 지표 | vs Market | vs EW(TE3%) |
|---|---|---|
| Information Ratio | 0.44 | **0.49** |
| Active Return p.a. | 1.55% | 1.46% |
| Sharpe(절대) | 0.63 | 0.63 |
| Turnover | — | **522%/yr** |

**저자 명시 caveat (FR 모드에 直관련)**:
1. **online 국면전환이 in-sample 대비 ~2배 빈번** — 경계에서 추정오차.
2. **feature는 후행** — 국면을 *예측*이 아니라 *사후식별*. "1-day delay" 명시.
3. **Quality 팩터 국면식별 최약**(방어적·저변동이라).
4. 100% leverage 유지 → downside 보호 없음(절대 시장국면 추가 시 개선 여지).
5. active return은 trend 약해 국면분석 난도↑(1~3% p.a. vs 시장 8~10%).

→ **시사**: 학술 SOTA조차 팩터 로테이션의 순효익은 **IR ~0.5, active ~1.5%, turnover 522%**로 *겸손*하다. 우리 FR_001이 EW를 못 이긴 것은 이 문헌 맥락에서 이례가 아니라 **정상 범위의 어려움**이다. 단 그들은 **팩터별 국면 + BL**, 우리는 **단일국면 + 모듈 dispatch** — 구조가 다르다(§6).

---

## 4. SJM 방법 박스 (Shu-Mulvey et al. 2024, arXiv [2402.05272](https://arxiv.org/abs/2402.05272))

**목적함수**:  min_{θ,s} Σ_t ½‖x_t − θ_{s_t}‖² + **λ Σ_t 𝟙{s_{t-1}≠s_t}**
- λ=0 → k-means(과전환). λ=50~100 → 연 <1회 전환(경기순환 정렬). **λ가 지속성을 명시 제어** — HMM이 전이행렬로 *암묵* 제어하는 것과 대비.
- vs HMM: 비모수·data-driven·robust(오설정/초기값), 수렴 빠름.
- **feature(parsimonious 3종)**: EWM downside deviation(hl10), EWM Sortino(hl20), EWM Sortino(hl60) — excess return 기반.

**OOS (1990–2023, 0/1 bull→100%자산 / bear→100%무위험)**:
| 시장 | JM Sharpe | HMM | B&H | JM MDD | B&H MDD |
|---|---|---|---|---|---|
| S&P500 | **0.68** | 0.54 | 0.48 | **−26.6%** | −55.2% |
| DAX | 0.44 | 0.35 | 0.30 | −39.4% | −72.7% |
| Nikkei | 0.31 | 0.19 | 0.12 | −45.3% | −79.1% |

→ **JM이 HMM을 모든 시장서 Sharpe·MDD 동시 우위.** Expected shortfall ~1%p 개선.
**lookahead 차단**: online DP를 lookback window(l=3000)에서 *t까지 데이터만으로* 상태 추론, 파라미터는 6개월마다 refit, **+1일 지연(t 신호→t+2 적용)**, COVID 전환 탐지 지연 ~보름.

---

## 5. 비판적 평가 — OOS 취약성 · PIT (이 검토의 핵심 가치)

국면모델 문헌의 *불편한 합의*:
1. **In-sample 적합 ≫ OOS 가치**(Guidolin 2011). 화려한 likelihood가 거래비용·추정오차에 녹는다.
2. **Regime-labeling lookahead** — 가장 흔한 함정. 전체표본 Viterbi/smoothing으로 라벨 매기면 미래정보 누설. **online filtering(t까지)만 PIT 유효.** Shu-Mulvey가 +1일 지연·6개월 refit·DP online inference로 방어하는 이유. ⇒ 우리 PIT C1/C5(t-1 lag, expanding) 정합 필수.
3. **새 국면 일반화 실패** — "시장은 결국 본 적 없는 국면을 준다." 2-state가 K↑보다 안정·해석가능해 선호되는 이유.
4. **Data-snooping** — 국면정의·feature·λ를 여러 개 시도 후 best만 보고 = p-hacking. 완화: **CSCV/PBO**(López de Prado), **Deflated Sharpe**, walk-forward only.

**시스템 연결**: 우리는 이미 `essence_score.R`의 **DSR(Deflated Sharpe) 게이트** + `measurement-graduation §3`의 oos_retention·n_trials 다중검정 보정을 갖고 있다 — 이는 위 4번에 대한 *정답 방향*. 그리고 본 세션 실증(국면 분석 스터디)은 §1~5를 KR 모듈풀에서 재확인: 시스템 `Category`가 **월 25% 전환**(SJM이 λ로 막는 바로 그 과전환), FR_001 **OOS_retention 0.022** = "in-sample 국면엣지가 OOS에 안 남음"의 교과서 사례.

---

## 6. 시스템 갭 분석 + FR 모드 함의

**갭 1 — 모델(②)**: SJM 부재. 시스템은 HMM(2-state)·GARCH·CUSUM·absorption·GMM·ensemble까지 있으나 **현 SOTA인 jump model이 없다.** SJM은 우리의 과전환 문제(Category 25%/월)를 **정확히 겨냥**(λ penalty)하고, KR 단일지수 시계열에 K=2로 바로 적용 가능(`msm_daily_refit` 대체/병렬). 도입난도 낮음(목적함수 단순, DP).

**갭 2 — 구조(③)**: 더 근본적. 학술 SOTA(Shu-Mulvey)는 **팩터별 국면 → BL views**. 우리 FR는 **단일 시장국면(Category) → 12모듈 dispatch**. 본 세션 실증이 보인 한계(모듈 0.70 상관 → 로테이션 무가치)는 **③ 구조의 문제이기도 하다**: 단일 시장국면은 상관 높은 모듈들을 *같은 방향*으로만 흔든다. Shu-Mulvey식 *팩터/슬리브별* 국면은 직교 슬리브가 있을 때만 의미.

**함의 (본 세션 실증 + 문헌 종합)**:
- 국면 모델 고도화(SJM 도입)는 **②의 신호 질**을 올리지만, **③ 입력(모듈풀)이 0.70 상관이면 천장은 그대로**다. 문헌도 active return 1.5%/IR 0.5의 겸손한 효익 + Quality(방어적) 팩터 국면 무력을 인정 — 우리의 *이미 방어적인* 모듈풀과 동형.
- **순서**: (a) 직교 슬리브 확보(③ 입력) → (b) 그 위에 SJM(②) + 팩터별 국면 BL(③) = Shu-Mulvey 아키텍처 이식. 입력 직교화 없이 SJM만 얹는 건 문헌이 경고한 "겸손한 효익"에 거래비용만 추가.

---

## 7. 권고 (우선순위)

1. **[입력 우선]** 직교 슬리브 확보가 ②③ 어떤 고도화보다 선행(본 세션 실증 = 천장은 입력이 결정).
2. **[②, 저난도·고가치]** **SJM(jump penalty λ) PoC** — 현 `Category`/MSM 2-state를 SJM로 대체 비교(λ로 과전환 25%→<5% 목표). KR 단일지수 + US-VIX feature(D-doc #1). known-case parity는 `msm_daily` 대비.
3. **[③, SOTA 이식]** 직교 슬리브 ≥4건 확보 후 **Shu-Mulvey 팩터별-국면 → BL → long-only MVO** 이식(우리 제약 15bps/[0,0.20]/Σw=1/max25 native). turnover 522%는 우리 11.0/yr 한도와 충돌하므로 **TE 타깃 하향 + λ 상향**으로 회전 억제 필수.
4. **[방법론 위생]** 국면라벨 online-only(PIT C5) + DSR/CSCV 다중검정 보정(이미 보유) 유지.

---

## 부록 — 주요 레퍼런스

**모델(②)**: Hamilton (1989) *Econometrica* 57:357 · Ang-Bekaert (2002) *RFS* · Guidolin (2011) MS survey · Kritzman-Li (2010) *FAJ* turbulence · Kritzman-Li-Page-Rigobon (2011) absorption ratio · Bemporad et al. (2018) jump models · Nystrup et al. (2020, 2021) (sparse) JM · Aydinhan-Kolm-Mulvey-Shu (2024) *Annals of OR* [10.1007/s10479-024-06035-z](https://link.springer.com/article/10.1007/s10479-024-06035-z).
**팩터 로테이션 SOTA**: Shu-Mulvey (2024) [arXiv:2410.14841](https://arxiv.org/abs/2410.14841) · Shu et al. (2024) [arXiv:2402.05272](https://arxiv.org/abs/2402.05272) (SJM downside) · Li et al. (2025) MPC+JM [Mathematics 13:2837](https://www.mdpi.com/2227-7390/13/17/2837).
**HMM 팩터투자**: Wang-Lin (2020) [*JRFM* 13:311](https://www.mdpi.com/1911-8074/13/12/311) · Yale (2022, KR-023).
**ML 직접매핑**: Yin-Shi (2024) Asset Allocation Forest (P189).
**KR 국면/신호(레포 D-doc 50편)**: Kang-Yoon (2015) *FRL* VKOSPI 3-regime MS · Kim et al. (2016) Hamilton 2-regime · Bollerslev-Tauchen-Zhou (2009) VRP · Xing-Zhang-Zhao (2010) skew crash · Lee-Mykland (2013) US-KR VRP leading.
**방법론 위생**: López de Prado — CSCV/PBO, Deflated Sharpe(시스템 `essence_score` 정합).

> 검증 라벨: arXiv 2편(2410.14841/2402.05272)은 원문 추출(수치 검증). canonical 문헌은 표준 인용 레벨(세부수치 미주장). KR D-papers는 레포 `DERIVATIVES_REGIME_DETECTION_RESEARCH.md` 재인용.
