# REGIME 큐 소진 Triage — 2026-07-01

**작업**: `mode_queue_20260701.json` regime 5편 전수 triage + 유망 후보 실측 quick-test.
**규율**: 표준 통계함수만(자체합성 금지) · metric_type 라벨 · PIT(신호 t-1, same-day 금지) · 오버레이 net = |Δexposure|×15bps.
**현 시스템 기준선**: book 오버레이 = M4 BOCPD(change-point) + AR(absorption ratio) + R05(tail-risk) = 작동하는 유일 레버(SR 1.95). 신규 후보는 이를 *보완/초과*해야 가치.
**데이터 주의**: `.cache/benchmark.parquet` BM_Ret 2025-10+ 손상 → 시장-타이밍 테스트는 **자체 구축 KR cap-w 시장프록시**(RAWDATA Size 가중, K200∪KQ150, t-1 weight)로 수행해 손상 회피. 윈도우 = FULL ex-2026(≤2025-12) + BM-safe(≤2025-09) + incl-2026(프록시 자체구축이라 2026 OK).

**산출물**: `WT-D20260701_001/vshape_brake_test.py` (실측 스크립트) + 본 파일.

---

## 5편 verdict 요약

| # | arxiv | 제목(축약) | 신규성 | KR 구현성 | 기-falsify | **Verdict** |
|---|---|---|---|---|---|---|
| 1 | 2606.27932 | GL Fractional Derivative — (In)Efficient market states | 추정량-통계 개선(H>½ 위상전이) | 가능하나 무의미 | **Hurst-state = 기실패 동일 경제객체** | **SKIP** |
| 2 | 2606.23492 | Continuous HMM heavy-tail + regime-VaR | filtered(PIT-clean) 3-state, 저비용 | 가능(가격-only) | — (방법 본질 상이) | **REFERENCE** (오버레이 검증 無·기존 우위 prior) |
| 3 | 2606.22719 | Leakage-aware LLM macro nowcast → factor ranking | PIT-aware 벤치마킹 | **불가**(Cleveland Fed CPI nowcast + 7B LLM infra) | **forward-macro = settled-null** | **SKIP** |
| 4 | 2606.15701 | Robust Transformer 지수 1-step 예측(SDA) | 학습안정 기법(SDA+cosine LR) | DL 학습 시 적용 가능 | predictive 지수타이밍 < coincident | **REFERENCE** (ML 학습 노트, 오버레이 아님) |
| 5 | 2606.09025 | Continuous cash-overlay (slow-tail + V-shape brake + max-cash) | 모듈러 cash overlay | 가능(테스트 완료) | max-cash=FALSIFIED → **V-shape/slow-tail만 평가** | **SKIP** (실측: 기존 오버레이에 dominated) |

**소진 완료: 5/5.** TESTABLE로 실측한 1건(#5)은 기존 오버레이에 열위 확인 → 전편 비-편입(SKIP 3 + REFERENCE 2). capital-grade 후보 0.

---

## #1 — 2606.27932 (In)Efficient Market States & Rough Volatility via Grünwald-Letnikov

**Method**: fBm 단일 궤적에서 자기상사 H 추정 시 H>½ 영역의 KS 통계 위상전이(비함수적 절대-가우시안 극한 붕괴) 문제를 GL(Grünwald-Letnikov) 분수도함수 필터로 해결하는 **regime-adaptive KS/GL-KS Hurst 추정기**. 금융 적용 = realized vol의 rough(H<½) 검정 + 로그가격 궤적의 persistent/anti-persistent/efficient **시장상태 분류(= sign(H−½))**.
- 키워드 그대로: "Hurst exponent; Fractional processes; Kolmogorov–Smirnov test; Grünwald-Letnikov derivative".
- 전문 grep: trading/portfolio/backtest/sharpe/strategy/signal→position 매핑 **전무**("trade" 매치는 전부 trade-off/tradependence). GL 보정은 H>½에서만 활성(Remark 3.14), short/anti-persistent에선 α=0로 무필터 KS와 동일.

**신규성·구현성·기-falsify**: 신규성은 **순수 추정량-통계적**(H 추정의 유한표본 편의 축소) — 경제 신호가 아니라 추정 정밀도 개선. 산출 경제객체는 Hurst-state 분류로 **기실패한 KR Hurst/rough-vol 모멘텀 패밀리와 동일**([[project-kr-momentum-novel-hunt]]: FIP·Hurst·PCDM 3종 FALSIFIED). 라우터 note "Hurst 팩터 기실패" 직접 적용. method가 본질적으로 달라 재평가할 여지를 검토했으나 → **다른 것은 추정기일 뿐 경제객체(H state)는 동일**하므로 재실행 시 falsified 메커니즘 재검정.

**Verdict**: **SKIP** — Hurst-state 분류기, 기실패 경제객체와 동일. 개선은 추정-통계적이지 신규 경제신호 아님. (재실행 금지 정합)

---

## #2 — 2606.23492 Continuous HMM heavy-tail + Regime-Conditional VaR

**Method** (전문 추출): K*=3 연속 HMM(per-state Gaussian/Student-t/Laplace/GED emission), EM(forward-backward, 가우시안/라플라스 M-step 폐형). 핵심 기여 = **합성 수익률 생성기** + regime-조건부 VaR(joint conditional-coverage test 통과). 멀티자산 copula로 상관 재현.
- **PIT 관점(load-bearing)**: 다운스트림 VaR은 **filtered(causal) forward filter** 사용 — IS-고정 파라미터로 `P(s_{t+1}|history_t)`만 OoS 업데이트(Table 3). smoothed γ_t는 **EM 학습에만**("both past and future observations"). Viterbi는 별도 HSMM 벤치에만. → **regime 신호 자체는 PIT-admissible**(smoothed/Viterbi 라벨과 달리 look-ahead 없음).
- **상태**: K*=3(held-out CV+BIC, K=3~6 구분불가 → 작은 것). 명시적 risk-on/off 라벨 없음, σ_k로 사실상 vol-정렬(heavy-tail 클러스터 = high-vol rank).
- **데이터**: 가격-only(SPY/CRSP daily, 옵션·VIX·매크로 불요) → **KR 일별 지수수익만으로 적합 가능**. 비용 저렴(K=3 → 12 파라미터, 초~분, GPU 불요).

**신규성·구현성·기-falsify**: regime-탐지 코어는 BOCPD/AR 대안으로 **이론상 적합**(causal·가격-only·저비용·연속 조건부-risk 신호 산출). 기-falsify 직접 해당 없음(BOCPD와 본질 상이한 generative HMM). **그러나 결정적 갭**: 논문은 이를 **포트폴리오 de-risking 오버레이로 전혀 검증 안 함** — Sharpe/drawdown/exposure-rule 결과 0건. VaR 벤치도 다른 *VaR* 모델(filtered bootstrap/CAViaR) 상대지 vol-target/change-point 상대 아님. 즉 "KR에서 AR/BOCPD보다 낫다"는 근거를 논문이 **제공하지 않음**.

**Verdict**: **REFERENCE** — PIT-clean regime 탐지기로 잠재 가치 있으나, **오버레이 우위 근거 부재 + 기존 M4+AR+R05가 동일 역할 수행 중(SR 1.95)**. #5 실측이 "coincident 오버레이는 이미 포화"를 재확인한 마당에, generative-HMM regime을 신규 sleeve로 검증하려면 별도 풀 harness 필요(현 시점 EV 낮음). regime-VaR 산식은 risk-research VaR 고도화 *참고자료*로 보존. (재시도 트리거: 기존 오버레이 4-지표 천장 돌파가 별도로 요구될 때 BOCPD A/B 대상 후보.)

---

## #3 — 2606.22719 Leakage-Aware LLM Forecasting → Macro Factor Ranking

**Method**: leakage-통제 하 retrieval-augmented 7B LLM이 월말 의사결정시점 정보만(lag-shifted FRED + 매크로이벤트 요약 + **Cleveland Fed archived daily CPI nowcast**) 관측 → macro-analog retrieval + critic LLM(전술규칙 1개 압축) + actor LLM이 7개 US style 팩터 스코어 산출. 2023-04~2026-03.

**신규성·구현성·기-falsify** — 3중 kill:
1. **NULL prior**: forward-macro → 팩터-랭킹 = 예측-매크로 패밀리. [[project-predictive-crisis-timer-forward-macro-null]](forward-macro settled-null) + [[project-predictive-vs-coincident-overlay]](coincident > predictive) 직접 해당.
2. **논문 자체 underpowered**: median 월 Spearman IC +0.154이나 **mean IC bootstrap 95% CI가 0 포함**(통계적 underpowered, 저자 자인). 게다가 평범한 kNN macro-analog가 comparable median 복원 → "신호 대부분이 실시간 인플레+매크로유사 retrieval로 설명". LLM 한계효익은 extreme ranking(long-short)에만 집중 — 우린 long-only.
3. **구현 불가**: Cleveland Fed CPI nowcast archive = US 전용(KR 등가 부재) + 7B LLM nowcast infra 필요. underpowered 신호 위해 LLM-nowcast 파이프라인 구축 정당화 안 됨.

**Verdict**: **SKIP** — forward-macro NULL prior + 논문 자인 underpowered(CI∋0) + KR 데이터/infra 불가. 3중 사유.

---

## #4 — 2606.15701 Robust Transformer One-Step Index Forecasting (Shifted Data Augmentation)

**Method**: 수정 Transformer + cosine-annealing-warmup LR schedule + **Shifted Data Augmentation(SDA)**로 1-step 지수 예측. VN30/S&P500. 결과 = **예측정확도(RMSE)/run-to-run 분산 감소** — cosine annealing > inverse-power scheduler, SDA가 모델복잡도 증가보다 robustness에 중요.

**신규성·구현성·기-falsify**:
- 산출이 **예측오차(RMSE)이지 전략 아님** — 포트폴리오/Sharpe/오버레이/신호→포지션 매핑 전무. 기여(SDA + LR schedule)는 **DL 학습-안정화 기법**, 신규 경제신호 아님.
- predictive 지수-레벨 타이밍은 [[project-predictive-vs-coincident-overlay]]에서 *좋은* 예측조차 배포 coincident 오버레이(1.95)에 열위 입증. 지수예측 정확도 개선이 오버레이 우위로 직결 안 됨.
- SDA는 generic DL 트릭 → ML 파이프라인이 transformer 학습 시 *참고*. regime/오버레이 테스트 후보 아님.

**Verdict**: **REFERENCE** — ML 학습 robustness 기법(SDA/cosine-warmup) 메서드 노트로 보존. 오버레이/regime 신호 아님 → 실측 불요.

---

## #5 — 2606.09025 Continuous Cash-Overlay Filters (★실측 수행)

**Method** (전문 추출): 고정 growth-defensive 위험 sleeve R(50/50 EW 성장/방어 ETF) vs 현금 C 배분. 2 모듈:
- **slow-tail filter**: compensation/rate-headwind/risk-premium-compression/rate-path-stress 연속상태 → cash weight(30% material-trade gate). 직접 compensation-score(historical analogue 아님).
- **V-shape filter(fast crash brake)**: `BrakeScore_t = VIXCore + λ_r·RatePanic + λ_c·CreditPanic` (+drawdown/10d-crash-loss interaction), VIXCore = α·VIXLevel_z + (1−α)·VIXSpike_z. re-entry η_exit=0.25 평활. → 빠른 drawdown 대응.
- **max-cash combine**: w_cash = max(slow, vshape) [**FALSIFIED 2026-06-26, min-combine 우위 → 평가 제외**].
- 논문 결과(2017-2026): max-cash combo 18.83% CAGR(vs 16.62% R), MDD −33.6%→−18.1%. **단 V-shape standalone OOS는 buy-hold보다 낮음**(expanding 15.59% vs 16.09%; rolling 14.88% vs 16.09%) — 저자 명시 "drawdown lens로 읽어라, alpha table 아님" + "post-2022 V-shape 의도적으로 약함".

**평가 대상**: max-cash 제외, **V-shape crash brake**(+slow-tail 핵심) 신규성만. = VIX/credit/drawdown coincident de-risker → **R05(tail-risk)가 이미 채우는 역할**.

**실측 quick-test** (`vshape_brake_test.py` + tuned variants, metric_type=**proxy_overlay**, KR cap-w 프록시 13.18% ann/21.6% vol):

FULL ex-2026(≤2025-12):
| 전략 | Sharpe | CAGR | MDD | Calmar | avgCash |
|---|---|---|---|---|---|
| Buy&Hold R | 0.487 | 8.04% | −53.7% | 0.150 | — |
| **Existing exposure (M4+AR+R05)** | **0.505** | 6.72% | −35.2% | **0.191** | 0.136 |
| V-shape brake (faithful) | 0.449 | 7.11% | −53.7% | 0.132 | 0.025 |
| VIXz>1.5 brake (tuned) | 0.517 | 7.66% | −40.8% | 0.188 | 0.055 |
| VIXz\|dd>8% brake | 0.251 | 2.11% | −48.3% | 0.044 | 0.445 |
| 5d-crashloss brake | 0.491 | 7.69% | −48.9% | 0.157 | 0.011 |
| aggressive-combo brake | 0.250 | 2.10% | −47.7% | 0.044 | 0.446 |
| min(brake,exposure) | 0.467 | 5.95% | −35.2% | 0.169 | 0.158 |

위기 sub-window MDD: 2008 BH −48.8% / aggrBrake −6.4% / exposure −15.2% · 2020 BH −35.1% / aggrBrake −9.0% / exposure −18.4%.

**해석**:
1. **Faithful V-shape는 buy-hold보다 strictly 열위**(Sharpe 0.449<0.487, Calmar 0.132<0.150, **MDD 동일 −53.7%**) — brake가 거의 발화 안 함(평균 cash 3%) + **2008 GFC·2020 COVID에서 발화 실패**(brake MDD = buy-hold MDD). US-파생 VIX/credit가 KR-고유 crash onset에 lag. 논문 standalone 결과(15.59<16.09) 재현.
2. **기존 exposure 오버레이가 V-shape를 모든 윈도우·모든 지표에서 dominate**(Sharpe 0.505>0.449, Calmar 0.191>0.132, MDD −35.2%<−53.7%). M4+AR+R05가 V-shape 주장을 이미 더 잘 수행(2008/2020 발화 차이가 결정적 — combo의 MDD 개선은 전부 exposure leg에서 나옴).
3. **유일하게 경쟁하는 tuned VIXz>1.5는 V-shape 메커니즘 아님**(순수 VIX-level) + (a) VIX_z는 이미 exposure 9축 중 1개 → 중복, (b) Calmar 0.188<0.191로 **여전히 기존 미달**, Sharpe 우위(0.517)는 덜-방어적(cash 5.5% vs 13.6%)에서만 발생 = 더 나은 게 아니라 덜 보호.
4. **drawdown/crash-loss 트리거(논문 실질 신규)는 KR에서 whipsaw 참사**(Sharpe 0.25, CAGR 2.1%) — 바닥 매도 + 늦은 재진입. crash 보호(2008 −6.4%)와 수익 drag(2.1%)가 불가분 = no free lunch, "over-allocate to cash" 실패 재현.

**Verdict**: **SKIP** — V-shape crash-brake는 faithful·관대-tuned 전 형태에서 **기존 M4+AR+R05 오버레이에 risk-adjusted(Calmar) frontier상 dominated**. 경쟁하는 유일 변형(순수 VIX)은 기존이 이미 쓰는 축과 중복이며 여전히 미달. drawdown/crash-loss 코어(논문 신규성)는 KR whipsaw. 논문 자인(standalone < buy-hold) + 메모리([[reference-kr-sr-ceiling-overlay]] coincident 오버레이 포화) 정합. capital-grade 아님, 비-편입.

---

## 메모리 적립 후보 (1줄)
- **regime 큐 5편 전수 SKIP/REFERENCE — capital-grade 0**: #1 Hurst-state(기실패 동일객체) · #3 forward-macro+LLM(NULL+underpowered+infra불가) = SKIP / #2 generative-HMM regime(PIT-clean이나 오버레이 검증無·기존 우위) · #4 transformer SDA(학습기법, 신호아님) = REFERENCE / **#5 V-shape brake 실측 = 기존 M4+AR+R05에 dominated**(faithful Sharpe 0.449<exposure 0.505, Calmar 0.132<0.191; drawdown-trigger whipsaw Sharpe 0.25). coincident 크래시-브레이크 공간 = R05가 포화. [[reference-kr-sr-ceiling-overlay]] 정합.
