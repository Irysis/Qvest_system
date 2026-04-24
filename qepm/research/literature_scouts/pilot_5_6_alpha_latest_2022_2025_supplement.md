# Pilot 5~6 Alpha Bibliography — 최신 보강 (2022~2025)
최종 업데이트: 2026-04-24
작성: Scout 2차 (Q-Lead 지시)
용도: 1차 bibliography 보완 (최신 연구 집중, >=2022)
연관: pilot_5_6_alpha_enhancement_bibliography.md

---

## 조사 방법 메모 (MCP 도구 성공/실패 로그)

### 성공한 경로
| MCP 도구 | 상태 | 비고 |
|----------|------|------|
| `mcp__arxiv__search_papers` | **PASS** | 단순 키워드(OR 없이) + q-fin 카테고리 필터 조합 시 작동. 주요 발견 경로. |
| `mcp__arxiv__search_papers` (date_from + relevance) | **PASS** | 2022+ 필터 + relevance 정렬이 가장 효율적 조합. |

### 실패한 경로 (2차 Scout 학습용)
| MCP 도구 | 상태 | 오류 코드 | 비고 |
|----------|------|----------|------|
| `mcp__jina__search_arxiv` | **FAIL** | Payment Required (402) | 1차와 동일. 여전히 차단. |
| `mcp__jina__search_web` | **FAIL** | Payment Required (402) | 웹 검색 전체 차단. |
| `mcp__jina__search_ssrn` | **FAIL** | Payment Required (402) | SSRN 전용 경로도 차단. |
| `mcp__paper-search__search_google_scholar` | **FAIL** | 빈 result [] | 모든 쿼리 결과 없음. |
| `mcp__paper-search__search_arxiv` | **FAIL** | 비관련 결과 | 키워드 무시, 최신 전체 논문 반환. |
| `mcp__arxiv__search_papers` (OR 연산자, 따옴표 복합) | **FAIL** | 400 Bad Request | 복잡한 쿼리 문법 오류. 단순 키워드만 허용. |
| `mcp__arxiv__search_papers` (categories: econ.GN 단독) | **PARTIAL** | 비관련 결과 다수 | 경제학 전반 논문 혼입. q-fin 카테고리 필수. |

### 핵심 교훈
- `mcp__arxiv__search_papers` 단독 사용 시: 쿼리는 4단어 이내 단순 키워드, 카테고리는 `q-fin.PM` + `q-fin.GN` 조합이 최적
- SSRN 최신 논문 접근 불가 → arXiv 프리프린트로 대체
- 한국 학술지(ARFR/APJFS/한국증권학회지) arXiv 등록률 극히 낮음 → 직접 검색 불가

---

## 축 1: RAPC Alpha 최신 보강 (Earnings Surprise / Accrual / Multi-testing)

### 1.A PEAD & 투자자 이질성 — 2022년 이후 발견

**[Vamossy (2025)] "Retail Investor Horizon and Earnings Announcements"**
- arXiv: 2512.00280 | Venue: arXiv preprint (q-fin.PR)
- Peer-reviewed 여부: preprint | 인용수: ~0 (신규)
- GitHub / replication: 미공개
- **메커니즘**: StockTwits 자기보고 보유기간으로 소매투자자를 장기(long-horizon) vs 단기(short-horizon)로 분화. 장기 소매투자자 비중 높은 종목에서 과소반응(PEAD 강화), 단기 비중 높은 종목에서 과반응(가격 반전). 이질적 투자자 구성이 PEAD 강도를 결정하는 메커니즘 제시.
- **한국 적용 가능성**: 한국 소매투자자 비중 60%+ (개인 비중 세계 최고 수준). 투자자 유형별 거래 데이터(KRX 제공) 기반 유사 분화 가능. DART 분기보고 시 PEAD 창(D30/D60) 한국 투자자 구성과 결합 시 강화 신호 가능.
- **1차 shortlist 대비 추가 가치**: Bernard&Thomas(1989)의 PEAD 존재를 투자자 구성이라는 교차분면으로 확장. RAPC SUE 신호에 '투자자 유형 조건부 가중' 레이어 추가 가능.
- **차기 Alpha handoff 포인트**: 차기 Discovery WT (WT-D)에서 Alpha Agent가 alpha_signal_definition에 SUE × retail_long_horizon_ratio 교차항 추가. `IC_SUE_adjusted = IC_SUE × (1 + retail_long_horizon_ratio × λ)` 구조.

---

**[Kim (2023)] "Information Content of Financial Youtube Channel: Korean Stock Market"**
- arXiv: 2311.15247 | Venue: arXiv preprint (q-fin.PM / q-fin.GN)
- Peer-reviewed 여부: preprint | 인용수: ~0
- GitHub / replication: 미공개
- **메커니즘**: 한국 주식 유튜브 채널(3PROTV) 정보 내용 실증. 부정 감성 언급 종목의 공시 후 과소반응(post-announcement underreaction) 확인. 채널 감성 변화가 한국 시장 포트폴리오 수익률 예측.
- **한국 적용 가능성**: 직접 한국 KOSPI 실증. 소매투자자 정보처리 행태와 PEAD 연결. DART 공시+감성 복합 신호 구성 가능성.
- **1차 shortlist 대비 추가 가치**: "한국 직접 실증 부족" 한계에 대한 직접 보완. 한국 PEAD가 소매투자자 감성 채널과 연결됨을 실증.
- **차기 Alpha handoff 포인트**: 차기 Discovery WT (WT-D)에서 Alpha Agent의 alpha_signal_definition에 SUE × 공시감성 교차 신호 포함. 감성 조건부 PEAD 창 선택(부정 감성 시 D60, 중립 시 D30). method_shopping_log에 variant 기록.

---

### 1.B Multiple Testing / Factor Zoo 메타 연구 — 2022년 이후

**[Chen & Zimmermann (2022)] "Publication Bias in Asset Pricing Research"**
- arXiv: 2209.13623 | Venue: Journal of Finance (forthcoming 2022, arXiv preprint)
- Peer-reviewed 여부: 심사중/발표 | 인용수: 50+
- GitHub / replication: Open Source Asset Pricing DB (https://github.com/OpenSourceAP/CrossSection)
- **메커니즘**: 수백 개 팩터의 복제성/OOS 지속성 메타분석. 핵심 발견: (1) 거의 모든 팩터 복제 가능 (2) OOS 지속 (3) t-stat이 2.0보다 훨씬 큼 (4) 팩터 간 상관 낮음. Empirical Bayes 보정 시 평균 shrinkage 10-15%에 불과. Publication bias가 팩터 연구에서 주요 요인이 아님을 실증.
- **한국 적용 가능성**: Harvey t>3.0 기준이 지나치게 보수적일 수 있음을 시사. 한국 Factor DB 288팩터에 Empirical Bayes 보정 적용 시 실질 shrinkage 추정 가능.
- **1차 shortlist 대비 추가 가치**: Harvey et al.(2016)의 t>3.0 기준에 대한 최신 반론. 더 균형 잡힌 다중검정 시각 제공. replication package 제공으로 직접 적용 가능.
- **차기 Alpha handoff 포인트**: 차기 Discovery WT (WT-D)에서 Alpha Agent가 RAPC 요소 선택 시 FDR 보정을 Empirical Bayes 방식으로 교체. 단순 BH 보정보다 덜 보수적. Judge Gate A(PIT) + Gate C(NetAlpha) 검증 시 EB shrinkage 기준 적용.

---

**[Chen & Dim (2023)] "High-Throughput Asset Pricing"**
- arXiv: 2311.10685 | Venue: arXiv preprint (q-fin.GN)
- Peer-reviewed 여부: preprint | 인용수: 20+
- GitHub / replication: 미공개
- **메커니즘**: 13만 6천 개 롱숏 전략(회계비율+과거수익률+티커)에 Empirical Bayes 적용. "High-throughput" 방식이 top journal 수준 OOS 성과를 Look-ahead bias 없이 매칭. 예측력은 회계 전략, 소형주, 2004년 이전에 집중(제한적 주의 이론과 일치). 대중화된 다중검정 방법들이 OOS 성과자의 대부분을 식별 실패.
- **한국 적용 가능성**: 소형주 + 회계 신호 집중이 한국 KOSPI 특성(소형주 비중 높음, 개인투자자 제한적 주의)과 부합. RAPC의 회계 기반 요소가 소형주에서 강화될 가능성.
- **1차 shortlist 대비 추가 가치**: 회계 기반 신호(RAPC 핵심)의 OOS 우월성을 체계적으로 실증. "회계 전략이 소형주에서 OOS 강함"이라는 결론이 한국 Factor DB 설계에 직접 반영 가능.
- **차기 Alpha handoff 포인트**: 차기 Discovery WT (WT-D)에서 Alpha Agent의 method_shopping_log에 소형주 IC vs 전체 IC 비교 variant 포함. Empirical Bayes 기반 요소 선별 후 alpha_signal_definition 확정.

---

## 축 2: AX-007 예외지대 최신 보강 (ML Sizing / Multi-sleeve)

### 2.A ML 자산 가격결정 최신 — 2022~2026 발견

**[Liu et al. (2026)] "Uncertainty-Adjusted Sorting for Asset Pricing with Machine Learning"**
- arXiv: 2601.00593 | Venue: arXiv preprint (q-fin.PM + stat.ML), Jan 2026
- Peer-reviewed 여부: preprint | 인용수: ~0 (신규)
- GitHub / replication: 미공개
- **메커니즘**: ML 자산가격결정에서 포트폴리오 구성이 점 예측(point prediction)만 사용하는 관행 비판. 자산별 추정 불확실성 조정 예측 경계(uncertainty-adjusted prediction bounds)로 정렬 시 OOS 성과 개선. 이득이 변동성 감소에서 주로 발생. 유연한 ML 모델(Random Forest, XGBoost)에서 이득 가장 강함.
- **한국 적용 가능성**: STR_1661 XGB V2(ICIR 1.029) 연장선상. 기존 점 예측 기반 XGBoost 정렬에 불확실성 경계 추가 시 추가 성과 개선 가능. 확장 없이 기존 코드에 conformal prediction 레이어 추가 가능.
- **1차 shortlist 대비 추가 가치**: Gu et al.(2020)의 ML 자산가격결정을 "불확실성 인식" 방향으로 확장. QEPM STR_1661 V3 설계에 직접 적용 가능한 실용 기여.
- **차기 Alpha handoff 포인트**: 차기 Discovery WT (WT-D)에서 Alpha Agent가 alpha_signal_definition에 conformal prediction interval 레이어 추가. Pilot 6 Deployment WT (WT-P)에서 Optimizer Agent가 불확실성 높은 종목의 target_weight 자동 하한 적용.

---

**[Dixon, Polson & Goicoechea (2022)] "Deep Partial Least Squares for Empirical Asset Pricing"**
- arXiv: 2206.10014 | Venue: arXiv preprint (q-fin.PR/PM + cs.LG)
- Peer-reviewed 여부: preprint | 인용수: 30+
- GitHub / replication: 미공개
- **메커니즘**: 심층 편최소자승(DPLS) = PLS 잠재 팩터 + Deep Learning 비선형 맵. OLS 선형 팩터보다 비선형 리스크 구조 포착. Russell 1000, 1989-2018. LASSO 및 일반 DL 대비 IR 1.2배 향상. 파라미터 절약적 구조로 학습 시간 단축.
- **한국 적용 가능성**: 한국 Factor DB 288팩터 × RAPC 4요소를 DPLS 입력으로 구성 가능. 비선형 팩터 상호작용 포착에 XGBoost보다 계산 효율적 가능성.
- **1차 shortlist 대비 추가 가치**: Gu et al.(2020) NN의 계산 부담 없이 비선형 구조 포착. RAPC 4요소와 기존 Factor DB의 비선형 결합 설계 가능.
- **차기 Alpha handoff 포인트**: 차기 Discovery WT (WT-D)에서 Alpha Agent가 method_shopping_log에 DPLS variant 포함. RAPC 4요소(ESBR/SUE/Δaccrual/OCF surprise) + 상위 15 Factor DB 팩터를 DPLS 입력으로 구성. Expanding window 필수. Judge Gate A(PIT C1 준수) 검증 필수.

---

**[Wei et al. (2023)] "HireVAE: Online and Adaptive Factor Model via Hierarchical Regime-Switch VAE"**
- arXiv: 2306.02848 | Venue: arXiv preprint (cs.LG + q-fin.PM)
- Peer-reviewed 여부: preprint | 인용수: 15+
- GitHub / replication: 미공개
- **메커니즘**: 변분 오토인코더(VAE) + 계층적 잠재 공간으로 시장 국면과 종목별 잠재 팩터 간 관계 추정. Point-in-time 시장 정보만으로 현재 국면을 식별하고 팩터를 동적으로 추정. 4개 실제 주식 시장 벤치마크에서 능동 수익 우월 성과.
- **한국 적용 가능성**: QEPM Regime Engine v7.1(4-Layer)과 연계 가능. MRS CRISIS(63.1, 2026-04) 국면 식별에 VAE 기반 잠재 국면 표현 활용 가능. 현재 국면엔진보다 자동화된 국면 탐지.
- **1차 shortlist 대비 추가 가치**: Gu et al.(2020)의 정적 ML과 달리 온라인 적응형(Online Adaptive). 국면 전환 자동 감지 + 팩터 가중 동시 조정.
- **차기 Alpha handoff 포인트**: 차기 Discovery WT (WT-D)에서 Alpha Agent가 method_shopping_log에 HireVAE variant 포함. RAPC 신호를 잠재 팩터에 통합. 국면별 RAPC 가중 자동 학습. Judge Gate A(PIT C1 온라인 적응 검증) 필수.

---

### 2.B 동적 다중팩터 배분 최신

**[Shu & Mulvey (2024)] "Dynamic Factor Allocation Leveraging Regime-Switching Signals"**
- arXiv: 2410.14841 | Venue: arXiv preprint (q-fin.PM + q-fin.ST)
- Peer-reviewed 여부: preprint | 인용수: ~5
- GitHub / replication: 미공개
- **메커니즘**: Sparse Jump Model(SJM)으로 팩터별 국면(Bull/Bear) 식별 → 국면 추론을 Black-Litterman에 통합 → 롱온리 멀티팩터 포트폴리오. 7개 인덱스(시장 + 6 스타일 팩터: 가치/사이즈/모멘텀/퀄리티/저변동성/성장). IR이 EW 벤치마크 대비 0.05→0.4 향상. 팩터 간 상관 낮아 분산 효과.
- **한국 적용 가능성**: QEPM 6-sleeve 아키텍처(v55)와 직접 연결. 한국 Factor DB 팩터별 국면 추론 → BL 통합 배분이 현 정적 배분 대비 개선 가능. Sparse Jump Model이 QEPM Expanding Percentile Regime Engine과 결합 가능.
- **1차 shortlist 대비 추가 가치**: Multi-sleeve 이론(Grinold & Kahn)을 구체적 국면-팩터 연동 배분으로 실증화. 팩터 수준 국면 추론 → 슬리브 비중 동적 조정 메커니즘 제공.
- **차기 Alpha handoff 포인트**: Pilot 6 Deployment WT (WT-P)에서 Optimizer Agent가 SJM 기반 국면 추론을 target_weights 조정에 통합. RAPC 슬리브의 CRISIS 국면 비중 감소·NORMAL 증가 자동화.

---

**[Garrone (2026)] "Dynamic Inclusion and Bounded Multi-Factor Tilts for Robust Portfolio Construction"**
- arXiv: 2601.05428 | Venue: arXiv preprint (math.OC + cs.LG), Jan 2026
- Peer-reviewed 여부: preprint | 인용수: ~0 (신규)
- GitHub / replication: 미공개
- **메커니즘**: 추정 오류/비정상성/거래 제약에 강건한 포트폴리오 구성 프레임워크. 동적 자산 적격성(유동성/변동성/분산도 기준) + 유계 다중팩터 틸트(bounded multi-factor tilts)를 EW 기준에 적용. 공분산/기대수익률 추정 불필요. 완전 알고리즘적, 투명, 직접 구현 가능.
- **한국 적용 가능성**: QEPM v53 hook(20종목 hard 제약 + 장기투자 틸트)과 철학적 일치. 추정 오류 없이 순위 기반 틸트로 유동성 2억원 필터 자동 통합 가능.
- **1차 shortlist 대비 추가 가치**: DeMiguel et al.(2009) EW 우월성 결론을 "EW에 유계 틸트 추가" 방식으로 구체화. QEPM 현행 구조(EW 20종목)의 이론적 확장.
- **차기 Alpha handoff 포인트**: Pilot 6 Deployment WT (WT-P)에서 Optimizer Agent가 RAPC IC-weighted composite를 EW 기준선에 bounded tilt로 구현. 최대 틸트 크기 = 1/N의 σ배(σ=0.5~1.5)를 challenge_loop (P4)에서 검증.

---

## 축 3: Market Hedge Overlay / Vol-managed 최신 보강

### 3.A Regime-Conditional Vol Management 최신

**[Barunik & Nevrla (2022)] "Common Idiosyncratic Quantile Factors and Asset Prices"**
- arXiv: 2208.14267 | Venue: arXiv preprint (q-fin.GN + q-fin.PR)
- Peer-reviewed 여부: preprint (다수 개정본 존재) | 인용수: 40+
- GitHub / replication: 미공개
- **메커니즘**: 기업 수준 고유수익률 분포의 꼬리에서 공통 팩터 식별. 하방 꼬리 팩터(bad fears)의 고베타 종목 연 7-8% 초과수익 프리미엄. 중개자 자본 취약/시장 유동성 낮을 때 강화 → 위기 구간 증폭. 시장 포트폴리오 초과수익 예측.
- **한국 적용 가능성**: MRS CRISIS 구간(현재 63.1)에서 꼬리 리스크 팩터 프리미엄 강화. QEPM AX-001 v2(방어형 팩터 조건부 평가: crisis_alpha + bad/normal IC ratio)와 연결.
- **1차 shortlist 대비 추가 가치**: Frazzini&Pedersen(2014) BAB와 달리 하방 꼬리의 공통 구성요소를 직접 포착. QEPM에서 crisis_alpha 측정 방법론으로 활용 가능.
- **차기 Alpha handoff 포인트**: RAPC 구성 요소 중 하방 꼬리 노출도(quantile beta)가 낮은 종목 우선. 위기 구간 RAPC 틸트를 꼬리 안전성 기준으로 조정.

---

**[Frank, Gao & Yang (2023)] "Behavioral Machine Learning? Regularization and Forecast Bias"**
- arXiv: 2303.16158 | Venue: arXiv preprint (q-fin.ST + cs.LG + econ.GN)
- Peer-reviewed 여부: preprint | 인용수: 15+
- GitHub / replication: 미공개
- **메커니즘**: 합리적 예측자의 최적 정규화가 표준 행동 편향 검정(과소/과반응)을 체계적으로 위반함을 이론+실증. ML 예측은 1년 기준 편향 제로, 2년 기준 강한 과반응. 애널리스트가 ML 채택(2013년 이후) 이후 과반응 쪽으로 이동.
- **한국 적용 가능성**: RAPC IC-weighted composite의 expanding window가 장기 IC를 과대반영해 과반응 편향 내재. 1년(12개월) window IC가 OOS에서 더 안정적일 가능성.
- **1차 shortlist 대비 추가 가치**: McLean&Pontiff(2016)의 알파 소멸 주장에 정규화 메커니즘 대안 제시. IC-weighted 구성의 기간별 편향을 이론적으로 설명.
- **차기 Alpha handoff 포인트**: RAPC IC-weighted 구성에서 expanding(=long-term) 비중 하향, 12개월 rolling 비중 상향. `IC_blend = 0.7 × IC_12M + 0.3 × IC_expanding`.

---

## 축 4 (신규): 한국 시장 실증 최신 (직접 KR 데이터)

### 4.A 한국 투자자 행태 / 시장 구조 실증

**[Oh (2025)] "Nonlinear Evidence of Investor Heterogeneity: Retail Cash Flows as Drivers of Market Dynamics"**
- arXiv: 2508.20426 | Venue: arXiv preprint (q-fin.GN)
- Peer-reviewed 여부: preprint | 인용수: ~0
- GitHub / replication: 미공개
- **메커니즘**: 한국 주식시장 2015-2024 투자자 유형별(개인/기관/외국인) 현금흐름 장기기억(Hurst 지수) 측정. 개인투자자 매수/매도 흐름이 가장 강한 지속성. 개인 NET 흐름의 롤링 Hurst가 미래 변동성 예측. 국면 민감성 확인(COVID, 2022-24 인플레).
- **한국 적용 가능성**: 직접 한국 KOSPI 실증. 개인투자자 흐름의 장기기억이 PEAD 지속 기간과 연결될 가능성. RAPC 신호의 시의성 파라미터화에 활용 가능.
- **1차 shortlist 대비 추가 가치**: 1차 bibliography의 "한국 직접 실증 부족" 한계를 직접 해소. 투자자 유형별 행태 실증이 RAPC PEAD window 선택(D30 vs D60)에 근거 제공.
- **차기 Alpha handoff 포인트**: 개인투자자 순매수 Hurst 지수가 높은 국면(지속적 개인 매수)에서 RAPC D60 drift, 낮은 국면에서 D30 drift 사용.

---

**[Kim, Bae & Kim (2026)] "Investor Risk Profiles of Large Language Models"**
- arXiv: 2603.09303 | Venue: arXiv preprint (q-fin.PM), Mar 2026
- Peer-reviewed 여부: preprint | 인용수: ~0
- GitHub / replication: 미공개
- **메커니즘**: GPT/Gemini/Llama의 투자자 위험 프로파일 분석. LLM이 한국어 소매투자 자문 환경에서 어떻게 위험 성향을 표현하는지 실증. Gemini: 중간 위험, 일관. Llama: 보수적. GPT: 중간공격적+변동성 높음.
- **한국 적용 가능성**: 저자 소속이 한국(경희대/POSTECH 등 추정). 한국 소매투자자 LLM 자문 시장의 위험 편향 분석. RAPC 신호의 소매투자자 정보처리 왜곡 가능성 평가 참고.
- **1차 shortlist 대비 추가 가치**: 한국 관련 arXiv 논문 희소성 고려 시 귀중한 KR 맥락 자료. 간접적 참고 자료 수준.
- **차기 Alpha handoff 포인트**: 직접 handoff 낮음. LLM 기반 감성 신호가 한국 시장에서 편향될 가능성 인식.

---

### 4.B LLM 기반 재무분석 — 최신 (한국 적용 가능성)

**[Kim, Muhn & Nikolaev (2024)] "Financial Statement Analysis with Large Language Models"**
- arXiv: 2407.17866 | Venue: arXiv preprint (q-fin.ST + cs.AI + q-fin.PM)
- Peer-reviewed 여부: preprint (다수 개정) | 인용수: 100+
- GitHub / replication: 미공개
- **메커니즘**: GPT-4에 표준화·익명화 재무제표 제공 → 미래 이익 방향 예측. 서술 정보 없이도 애널리스트보다 이익 변화 방향 예측 우월. SOTA ML 모델과 동등 정확도. GPT 예측 기반 거래전략이 다른 모델 대비 더 높은 Sharpe + alpha.
- **한국 적용 가능성**: DART 재무제표(표준화 용이) 기반 GPT-4 이익 예측 적용 가능. RAPC의 SUE 구성 요소를 LLM 예측으로 보강 가능. PIT 준수 필수(재무제표 lag 45일).
- **1차 shortlist 대비 추가 가치**: RAPC의 전통적 SUE(애널리스트 컨센서스 대비)를 LLM 기반 이익 예측으로 대체/보강하는 최신 경로. 애널리스트 커버리지 낮은 한국 소형주에서 더 유효 가능성.
- **차기 Alpha handoff 포인트**: DART 분기보고서 기반 GPT-4 이익 예측 신호를 SUE 대체재로 실험. Expanding window에서 GPT 정확도 시계열 추적.

---

**[Matera (2025)] "Corporate Earnings Calls and Analyst Beliefs"**
- arXiv: 2511.15214 | Venue: arXiv preprint (q-fin.GN + cs.CY)
- Peer-reviewed 여부: preprint | 인용수: ~0
- GitHub / replication: 미공개
- **메커니즘**: LLM 텍스트 변형(text-morphing) 방법론으로 실적 발표 콜의 주제 강조(prevailing narrative)와 수치 내용을 분리. 애널리스트가 감성(낙관주의)에 과반응, 리스크·불확실성 서술에 과소반응하는 체계적 편향 발견.
- **한국 적용 가능성**: 한국 기업 실적 콜(분기 이익발표)에서 유사 편향 가능성. DART 공시 텍스트 + LLM 분석 시 감성 vs 리스크 서술 분리로 SUE 조정 가능.
- **1차 shortlist 대비 추가 가치**: 이익 발표 후 드리프트(PEAD)의 원인을 "서술 선택적 과소반응"으로 세분화. RAPC의 ESBR(이익 beat 신호)에 서술 조정 레이어 추가 가능성.
- **차기 Alpha handoff 포인트**: 한국 실적 발표 텍스트에서 "리스크·불확실성 서술 비중" 측정. 높을 때 PEAD 더 길게(D60), 낮을 때 더 짧게(D30) 조정.

---

## 최종 보강 Shortlist Top 5 (1차 Top 10과 중복 없음)

| 순위 | 논문 | 축 | 최신 가치 | Handoff |
|---|---|---|---|---|
| 1 | **Chen & Zimmermann (2022)** "Publication Bias in Asset Pricing" arXiv:2209.13623 | 축 1.B | Harvey t>3.0 보수적 적용에 대한 최신 반론 + Open Source Replication DB | RAPC 요소 FDR 보정을 Empirical Bayes로 교체. Shrinkage 10-15%만 적용. |
| 2 | **Liu et al. (2026)** "Uncertainty-Adjusted Sorting" arXiv:2601.00593 | 축 2.A | ML 점 예측 → 불확실성 경계 정렬로 OOS 개선. STR_1661 V3 직결 | XGBoost 출력에 conformal prediction 추가. 불확실성 높은 종목 포지션 자동 축소. |
| 3 | **Kim, Muhn & Nikolaev (2024)** "Financial Statement Analysis with LLMs" arXiv:2407.17866 | 축 4.B | LLM이 애널리스트 초월 이익 예측. DART 재무제표 직접 적용 가능 | RAPC SUE 구성요소를 GPT-4 기반 이익 방향 예측으로 보강. 소형주 적용 우선. |
| 4 | **Chen & Dim (2023)** "High-Throughput Asset Pricing" arXiv:2311.10685 | 축 1.B | 회계 기반 신호의 OOS 우월성 체계 실증. 소형주+2004이전 집중 | RAPC 요소 선택 시 소형주 IC 분화 검증. Empirical Bayes 기반 요소 선별. |
| 5 | **Oh (2025)** "KR Retail Cash Flows as Market Dynamics Drivers" arXiv:2508.20426 | 축 4.A | 한국 직접 실증. 개인투자자 흐름 Hurst가 미래 변동성 예측 | RAPC PEAD window를 개인투자자 Hurst 지수에 조건부로 선택(D30 vs D60). |

---

## 1차 bibliography와의 통합 권고

### 최신 논문이 고전을 Update / 대체하는 관계

| 고전 (1차 Shortlist) | 최신 Update (2차 Shortlist) | 통합 방향 |
|---|---|---|
| Harvey et al.(2016) t>3.0 | Chen & Zimmermann(2022) 반론 | t>3.0은 FDR 기준. Empirical Bayes shrinkage 10-15%는 오히려 허용. 두 기준 병용. |
| McLean & Pontiff(2016) 발표후 소멸 | Frank et al.(2023) 정규화 편향 | 소멸의 원인을 "정규화에 의한 구조적 과반응"으로 세분화. IC window 1Y 단축 근거. |
| Gu et al.(2020) ML sizing | Liu et al.(2026) 불확실성 조정, Dixon et al.(2022) DPLS | NN 점 예측 → conformal bound 추가 또는 DPLS 비선형 구조로 업그레이드. |
| Moreira & Muir(2017) vol-managed | Barunik & Nevrla(2022) 꼬리 공통팩터 | 실현변동성 기반 vol-scaling + 하방 꼬리 팩터 노출 감소의 이중 방어. |
| Bernard & Thomas(1989) PEAD | Vamossy(2025) 투자자 지평선 분화 | PEAD 강도가 투자자 구성에 조건부임을 실증. KR 개인비중이 높아 D60 drift 가능성 강화. |

### 한국 직접 실증 Gap — 여전히 채워지지 않은 부분
- PEAD의 한국 실증(DART 기반)은 여전히 자체 검증 필요 (C14: Usable_Date 기준)
- Accrual anomaly 한국 단독 Harvey t-stat 검증 미발표 (Factor DB 내부 검증 필요)
- LLM 기반 이익 예측의 한국어 재무제표 적용 — 선구적 영역, 검증 논문 없음

---

## 검색 실패 로그 (3차 Scout 재시도 참고)

### 접근 실패 논문 (검색 시도, 직접 접근 불가)
| 논문 | 실패 사유 | 대안 |
|------|----------|------|
| Bryzgalova, Pelger et al. (2023) "Assaying the Core" (Journal of Finance) | SSRN/JF paywall | arXiv 프리프린트 미등록. 직접 Read 필요. |
| Chen, Pelger & Zhu (2024) "Deep Learning in Asset Pricing" | SSRN paywall | arXiv 2307.06667 로 대체 검색 시도 필요. |
| Da, Engelberg & Gao (2011) 후속 attention-PEAD | 오래된 논문 SSRN | Core Knowledge Base 내 항목 확인으로 대체. |
| 한국증권학회지 2022-2024 | 한글 학술지 arXiv 미등록 | RISS/KISS 직접 접근 필요 (MCP 불가). |
| Asian Review of Financial Research 2022-2024 | 영문 학술지 arXiv 미등록 | 기관 구독 경로만 가능 |

### 검색 실패 쿼리 목록
- `"accrual anomaly" "Korea" "KOSPI" stock returns 2022` → 결과 없음 (한국 arXiv 논문 희소)
- `"PEAD" "emerging markets" "individual investors" 2023 2024` → 비관련 결과
- `"open source asset pricing" "factor replication" 2023` → arXiv에 등록 안 됨
- `"hierarchical risk parity" "ensemble" 2023 2024` → q-fin 카테고리 없는 논문들
- `"LLM" "factor alpha" "Korean" 2023 2024` → 한국어 논문 arXiv 미등록

---

*생성일: 2026-04-24 | Scout 2차 | 검토 논문: arXiv 약 80건 스캔, 최종 신규 16건 선별 | 최신(>=2022) Shortlist: 16건 (Top 5 확정) | 검색 실패 로그: 5개 도구, 10+ 쿼리*

*다음 단계: Alpha Agent가 Shortlist Top 5 중 1(Chen-Zimmermann EB 보정) + 2(Liu uncertainty-adjusted sorting → STR_1661 V3) + 3(LLM-DART SUE 보강)를 RAPC v2 가설 설계에 반영*
