# PG2 강화 타겟 논문 수집 보고 (2026-07-02)

**지시**: 도훈 — "자율리서치 진행하려고 하니 현 PG2를 강화할 수 있는 논문 수집" (2026-07-02)
**대상**: PG2 book = `STR_1715_FaithTrend_on_M4_R05_overlay_PG2` (slot 2-2, 2026-07-01 admit)
**방법**: PG2 약점 4개(W1 강세장 참여 부족 / W2 score_eff 1M 신호 감쇠 / W3 단일 sleeve 집중 / W4 25종목 SR 천장 ~1.1)를 8개 검색 각도로 변환 → 56-agent 워크플로우 (8각도 병렬 검색 → dedup → 48편 편별 정밀 평가: 실존 확인 + factor_registry 373팩터 대조 + settled-negative 8종 충돌 검사 + KR/PIT 구현가능성 + priority 채점)

## 집계

- 검색 원본 97편 → 각도간 중복 5 제거 → 신규 후보 92편 (기존 라우팅 142편과 중복 0)
- 평가 48편 (round-robin cap): **collect 43 / uncertain 1 / rejected 4 (전부 redundant)**
- 미평가 44편은 큐 JSON에 `unassessed`로 보존 (후속 라우터 배치에서 소화 가능)
- Route 분포 (collect 43): **alpha 19 / overlay 10 / sleeve 5 / optimizer 5 / regime 4**

## 약점별 Top Picks

### W1 강세장 참여 (overlay) — 즉시 실행 연계됨
| P | 논문 | 핵심 |
|---|---|---|
| 8 | **Breaking Bad Trends** (Goulding-Harvey-Mazzoleni, FAJ 2024) | SLOW(12M)/FAST(1~2M) 부호 조합 4-state(Bull/Correction/Bear/Rebound), Rebound 조기 재진입. **→ 공격형 오버레이 Round 2 배터리로 2026-07-02 당일 실측 착수** |
| 8 | Conditional Volatility Targeting (2020) | 고변동 상태에서만 de-risk, 저변동 상태 노출 유지 — 상태-게이팅으로 상승참여 보존 |
| 7 | Momentum Turning Points (2023) | slow/fast 조합 국면 — BBT 동계열 보완 |
| 7 | Semivolatility-managed portfolios (2024) | 하방 semivol만으로 스케일링 — **Round 1 F5_S_semi(SR 2.224 승자)와 동일 방향의 문헌 근거** |
| 8 | Continuous Statistical Jump Models (2024) | 이산 국면 → soft probability (M4 hard-bin·β 3단 이산화의 연속화 근거, regime route) |

### W2 신호 감쇠 (earnings@3M lead 보강)
| P | 논문 | 핵심 |
|---|---|---|
| 8 | Analyst Forecast Revisions and Market Price Discovery (2003) | 컨센서스 대비 '혁신' 큰 리비전만 — drift 수개월 지속, 저커버리지에서 최강 |
| 8 | Relative Valuation and Analyst Target Price Forecasts (2011) | TP implied return을 **섹터내 상대화** — 내부 TP_gap 팩터 정제 직결 |
| 8 | Fundamentally, Momentum is Fundamental Momentum (2015) | 가격모멘텀 = fundamental momentum의 그림자 — 3M earnings horizon 교체 이론 근거 |
| 7 | Analysts' 3-signal Revisions (2012) | EPS리비전×추천×TP 3-신호 합의 composite |
| 7 | Post-Forecast Revision Drift (2020) | 애널리스트 underreaction 메커니즘 |

### W3 직교 sleeve (비-수익률 신규 정보원)
| P | 논문 | 핵심 |
|---|---|---|
| 8 | **Decoding Inside Information** (Cohen-Malloy-Pomorski, JF 2012) | 내부자 routine vs opportunistic 분리 — opportunistic 매수만 예측력. **DART elestock으로 KR 구현 가능, registry에 insider 계열 0건 (진짜 신규 정보원)** |
| 8 | Beyond Fama-French: Short-Term Signals (Robeco, FAJ 2023) | 단기시그널 composite + **buy/hold 보유밴드 회전억제** (회전 1800%→net alpha +6% 전환) — 구현규칙 레이어가 내부 완전 부재 |
| 7 | The persistence of opportunistic insider trading (2017) | 개인-수준 내부자 정보우위 지속 — 신호 가중 정교화 |
| 7 | Shared Analyst Coverage (2020) | 커버리지 연결 모멘텀 스필오버 — 컨센서스 데이터로 구현 가능한 비가격 링크 |
| 7 | Tug of War: Overnight vs Intraday (2019) | 일별 시가/종가만으로 분해 가능 (tick 불요) |

### W4 SR 천장 (uncertainty-aware 선택 / 비용-aware 구현)
| P | 논문 | 핵심 |
|---|---|---|
| 8 | The Uncertainty of ML Predictions in Asset Pricing (2025) | 예측 신뢰구간 기반 선별 — 레버④ 미탐색 축 직격 |
| 7 | Machine Forecast Disagreement (2023) | 앙상블 불일치 = 횡단면 신호 |
| 7 | To Trade or Not to Trade (2011) / Dynamic Trading (Gârleanu-Pedersen 2013) / Model Comparison with TC (2023) | 단기신호의 저비용 소화 — no-trade region/aim portfolio |

### KR 특화 (감쇠 검증·현지 실증)
- Speculation Before Celebration: Holiday·January·Lottery Korea (2025) / KR MAX effect 2건 (2023·2024) / KR idio vol·turnover (2023) / KR insider clustering (2023) / Anomalies across the globe (2020, post-publication decay)

## Settled-negative 방어
평가 단계에서 8개 기각확정 방향(DPL·forward-macro 예측·인버스ETF·max-cash combine·KR value 단독·FIP/Hurst/PCDM·팩터모멘텀 타이밍·327 재조합)과의 충돌을 편별 검사 — collect 43편은 전부 비충돌 또는 메커니즘 차이 명시분. rejected 4편은 registry 중복(redundant).

## 산출물
- **큐 (자율리서치 소비용)**: `stage_artifacts/paper_recharge/pg2_reinforcement_queue_20260702.json` (collect 43 + unassessed 44, route/priority/구현스케치 포함)
- **원본 평가 전문**: `stage_artifacts/paper_recharge/pg2_reinforcement_raw_20260702.json` (편별 novelty/실현가능성/판정사유 전체)
- 본 보고서: `04_Research/paper_collection/pg2_reinforcement_papers_20260702.md`

## 후속 연결 (2026-07-02 세션에서 즉시 착수분)
1. **Breaking Bad Trends → 공격형 오버레이 Round 2** (`stage_artifacts/pg2_offense_overlay/run_offense_overlay_round2.R`) — 4-state 오버라이드 실측 진행 중
2. Semivolatility-managed → Round 1 F5_S_semi로 이미 실측 (SR 2.224, +0.113 vs incumbent, paired NW-t 2.35)
3. 잔여 41편은 큐에서 라우터 v2 STEP 3 (alpha-search autorun / mode_queue) 규약으로 소비 가능
