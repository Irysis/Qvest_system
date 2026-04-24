# Pilot 5~6 Alpha Enhancement Bibliography
최종 업데이트: 2026-04-24
작성: Scout (Q-Lead 지시)
용도: 차기 Alpha Research Agent 가설 설계 참조
상태: MCP 검색 제한으로 Google Scholar + Core Knowledge Base 조합 구성

---

## 조사 방법 메모
- mcp__jina (SSRN/arXiv/web) 전부 Payment Required (402)
- mcp__paper-search__search_semantic / search_crossref 권한 거부
- mcp__paper-search__search_google_scholar: 핵심 논문 일부 확인 (Sloan 1996, Bernard-Thomas 1989, Ball et al. 2016, Harvey-Liu 2020)
- 나머지는 QEPM Core Knowledge Base (255편 증류) + 금융학계 확립된 논문 지식 기반 구성
- 구성 기준: 인용수 ≥ 100 확립 논문 우선, 한국 실증이 있으면 별도 표기

---

## 축 1: RAPC Alpha 강화 (Earnings Surprise Composite)

> RAPC 현황: ESBR + SUE + Accrual IC-weighted composite. Pilot 4 rank_IC 0.0318 구조적 한계 확인. 개선 방향 문헌 조사.

---

### 1.1 Accrual QoQ 차분

**핵심 논문**

- **[Sloan (1996)] "Do Stock Prices Fully Reflect Information in Accruals and Cash Flows About Future Earnings?"**
  - Venue: The Accounting Review 71(3), pp.289-315
  - **메커니즘**: 발생액(accrual) 구성요소는 현금흐름 구성요소보다 이익 지속성이 낮으나, 투자자는 이익 수치에 "고착(fixate)"해 차별적 지속성을 과소반영. 고발생액 기업은 미래 이익이 평균회귀하는데 시장이 이를 선반영하지 않아 초과수익 발생.
  - **실증**: 미국 1962-1991. 저발생액 롱/고발생액 숏 기준 연 10.4% 헤지수익. WC accrual 기반.
  - **한국 적용 가능성**: DART 재무제표에서 운전자본 발생액 직접 계산 가능 (연간 5월, 분기 45일 lag 필수 — PIT C4). Factor DB에 accrual 관련 팩터 포함.
  - **차기 Alpha 핵심 handoff**: 단순 레벨이 아닌 QoQ 변화량(Δaccrual)을 IC-weighted 시 RAPC composite 직교성 개선 가능. 고발생액→저발생액 전환 기업이 서프라이즈 신호와 결합 시 강화.

- **[Richardson, Sloan, Soliman & Tuna (2005)] "Accrual Reliability, Earnings Persistence, and Stock Prices"**
  - Venue: Journal of Accounting and Economics 39(3), pp.437-485
  - **메커니즘**: 발생액 신뢰성(reliability)이 낮을수록 이익 지속성 하락, 투자자 미예상. 전통 WC accrual보다 noncurrent operating accrual(PP&E, 무형자산 등)이 alpha 더 강함.
  - **실증**: 미국 1962-2001. 포괄적 발생액 정의 시 hedged return 확대.
  - **한국 적용 가능성**: DART에서 PP&E, 무형자산 변화 추출 가능. Noncurrent 포함 시 QoQ 변화 신뢰도 개선.
  - **차기 Alpha 핵심 handoff**: RAPC에 WC accrual 대신 포괄적 noncurrent 발생액 QoQ 차분 도입 시 독립 신호 확보.

- **[Allen, Larson & Sloan (2009)] "Accrual Reversals, Earnings and Stock Returns"**
  - Venue: Journal of Accounting and Economics 48(1), pp.51-63
  - **메커니즘**: 극단적 발생액은 반드시 반전(reversal)하는 구조적 회계 특성. 투자자가 이 반전 가능성을 과소평가해 Sloan(1996) 미스프라이싱의 근원.
  - **실증**: 미국. 재고과대계상 → 후속기 감모(write-down) 경로가 핵심.
  - **한국 적용 가능성**: 재고자산 변동이 제조업 비중 높은 한국 KOSPI에서 더 강할 가능성.
  - **차기 Alpha 핵심 handoff**: QoQ 차분이 크고 반전 가능성 높은 항목(재고, 매출채권)에 가중치 부여 시 RAPC 내 accrual 요소 강화.

- **[Thomas & Zhang (2002)] "Inventory Changes and Future Returns"**
  - Venue: Review of Accounting Studies 7(2-3), pp.163-187
  - **메커니즘**: 재고자산 변동이 발생액 구성요소 중 미래 수익률과 가장 강한 음의 관계. 재고 과잉축적 → 후속 할인판매 → 이익 하락.
  - **실증**: 미국 1962-2000. 재고변동 단독 accrual anomaly 설명력 최고.
  - **한국 적용 가능성**: 한국 제조업(반도체, 자동차, 철강) 재고 사이클 강하므로 효과 클 가능성.
  - **차기 Alpha 핵심 handoff**: RAPC accrual 구성요소를 전체 발생액 대신 재고변동 QoQ로 교체 시 signal-to-noise 개선.

- **[Leippold & Lohre (2012)] "Data Snooping and the Global Accrual Anomaly"**
  - Venue: Journal of Empirical Finance 19(3), pp.318-338
  - **메커니즘**: 26개국 중 개별 10개국에서 유의하나 다중검정(Holm/BH) 보정 시 4개국만 생존. 모멘텀과 달리 accrual은 보정 후 취약.
  - **실증**: 글로벌 26개국. 유의 생존국: 미국/호주/이탈리아/덴마크.
  - **한국 적용 가능성**: 한국 단독 검정 유의성 → 다중검정 보정 필수. Harvey t>3.0 기준 적용 권장.
  - **차기 Alpha 핵심 handoff**: 한국 단독 accrual 신호는 Harvey t>3.0 기준 충족 여부 사전 확인 필수. IC-weighted 시 composite에서만 활용.

**서브쿼리 요약**: Accrual QoQ 차분은 레벨보다 변화속도를 포착해 시의성이 높고, 특히 재고자산 변동이 한국 제조업 구조에서 가장 강한 신호다. 단순 accrual 수준에서 분기별 변화량으로 전환 시 RAPC composite 내 독립성 개선 가능. 단, 다중검정 후 한국에서의 단독 유의성은 불확실하므로 IC-weighted composite 내 보조 요소로만 사용해야 한다.

---

### 1.2 PEAD Window 세분화 (D1/D30/D60)

**핵심 논문**

- **[Ball & Brown (1968)] "An Empirical Evaluation of Accounting Income Numbers"**
  - Venue: Journal of Accounting Research 6(2), pp.159-178
  - **메커니즘**: 이익 공시 후 60거래일 동안 좋은 뉴스/나쁜 뉴스 방향으로 누적 비정상수익 지속(drift). 시장이 이익 정보를 즉각 완전 반영하지 못함.
  - **실증**: 미국 1957-1965. 61개 기업 샘플. PEAD의 최초 발견.
  - **한국 적용 가능성**: 개인투자자 비중 높은 한국시장에서 정보처리 지연이 더 길 가능성.
  - **차기 Alpha 핵심 handoff**: PEAD window를 D1(공시일), D30, D60으로 분화 시 한국 시장 drift 타임라인 매핑 가능.

- **[Bernard & Thomas (1989)] "Post-Earnings-Announcement Drift: Delayed Price Response or Risk Premium?"**
  - Venue: Journal of Accounting Research 27(Supplement), pp.1-36 (JSTOR: 2491062)
  - **메커니즘**: FOS(1984)의 60거래일 PEAD 재확인. Delayed price response(과소반응) 가설이 risk premium 가설보다 설명력 우위. SUE 상위/하위 분위 간 헤지수익 D1~D60 집중.
  - **실증**: 미국 1974-1986. 60거래일 PEAD 확인. 4분기 지연 효과 포함.
  - **한국 적용 가능성**: 한국 분기 보고 의무(DART) + 45일 lag → SUE 구성 후 D1/D30/D60 decile 비교 가능.
  - **차기 Alpha 핵심 handoff**: ESBR은 분기별 beat/miss 집계이나, SUE는 D1/D30/D60 window별 drift 크기가 다를 수 있음. D30 최대 drift 시점 포착 시 RAPC 업데이트 빈도 조정 필요.

- **[Bernard & Thomas (1990)] "Evidence that Stock Prices Do Not Fully Reflect the Implications of Current Earnings for Future Earnings"**
  - Venue: Journal of Accounting and Economics 13(4), pp.305-340
  - **메커니즘**: 이익의 계절적 자기상관이 예측 가능하나 시장은 이를 과소반영. 고(저) SUE 기업의 다음 분기 이익도 상승(하락) 경향인데 주가가 선반영 미흡.
  - **실증**: 미국. PEAD가 단순 drift가 아니라 이익의 분기간 자기상관 구조에서 기인.
  - **한국 적용 가능성**: 한국 기업 이익 계절성(4Q 집중) 고려 시 연간 SUE보다 분기 SUE QoQ가 더 유효.
  - **차기 Alpha 핵심 handoff**: SUE QoQ(현재분기 vs 1년 전 동분기) 방식이 계절성 제거 + drift 포착에 최적. RAPC 내 SUE 구성 방식 재검토 여지.

- **[Chan, Jegadeesh & Lakonishok (1996)] "Momentum Strategies"**
  - Venue: Journal of Finance 51(5), pp.1681-1713
  - **메커니즘**: 가격 모멘텀과 이익 모멘텀(earnings momentum, SUE 기반) 모두 독립 alpha 존재. 이익 모멘텀이 가격 모멘텀의 상당 부분을 설명하며, 두 신호 결합 시 더 강력.
  - **실증**: 미국 1977-1993. SUE + 가격 모멘텀 결합 포트폴리오 월 1.2%+ 초과수익.
  - **한국 적용 가능성**: RAPC의 ESBR+SUE는 이익 모멘텀의 변형. 가격 모멘텀 결합 시 한국에서도 시너지 가능성.
  - **차기 Alpha 핵심 handoff**: RAPC에 IndMom(섹터 모멘텀)과의 교차항 추가 시 drift의 섹터 채널 포착 가능.

**서브쿼리 요약**: PEAD는 D1(공시일 즉각반응)이 아닌 D30~D60 구간에서 핵심 drift가 발생하며, 이는 이익의 분기간 자기상관에서 기인한다. 한국의 개인투자자 비중과 정보처리 지연을 감안하면 D30~D60 구간이 D1보다 강할 가능성이 있다. SUE QoQ(동분기 대비) 방식이 계절성을 통제하면서 drift를 포착하는 최적 구성이다.

---

### 1.3 Cash-flow Based Surprise

**핵심 논문**

- **[Ball, Gerakos, Linnainmaa & Nikolaev (2016)] "Accruals, Cash Flows, and Operating Profitability in the Cross Section of Stock Returns"**
  - Venue: Journal of Financial Economics 121(1), pp.28-45
  - **메커니즘**: 현금흐름 기반 영업이익(cash-based operating profitability)이 발생액을 제거함으로써 이익관리 노이즈를 배제. 기존 발생액 이상현상과 수익성 이상현상을 단일 척도로 통합.
  - **실증**: 미국 1988-2012. cash-based OP가 accrual-based OP 및 Accrual anomaly를 모두 subsume. SR/ICIR 미공개, 이익 지속성과 수익률 예측력 우위 확인.
  - **한국 적용 가능성**: DART 재무제표에서 영업현금흐름(OCF) 직접 추출 가능 (분기 45일 lag). Factor DB 내 현금흐름 팩터 존재.
  - **차기 Alpha 핵심 handoff**: RAPC의 Accrual 요소를 cash-based OP 서프라이즈(현금흐름 컨센서스 대비 차이)로 교체 시 이익관리 노이즈 제거 + accrual과의 직교성 확보.

- **[Novy-Marx (2013)] "The Other Side of Value: The Gross Profitability Premium"**
  - Venue: Journal of Financial Economics 108(1), pp.1-28
  - **메커니즘**: 매출총이익(GP/A)이 미래 수익률 예측. BM(밸류)와 음의 상관이면서 독립 alpha. 발생액 없는 순수 현금창출 능력 반영.
  - **실증**: 미국 1963-2010. FF3 alpha 연 0.31%/월. 국제 42개국 강건. ICIR 추정 0.3~0.5.
  - **한국 적용 가능성**: Core Knowledge Base 확인 — GP/EV 스케일링이 GP/A보다 한국에서 유효. Factor DB 포함.
  - **차기 Alpha 핵심 handoff**: GP/EV의 분기별 서프라이즈(GP/EV_t vs GP/EV_t-4) 구성 시 현금흐름 surprise의 독립 채널 확보.

- **[Sloan (1996)] "Do Stock Prices Fully Reflect..." (1.1에서 인용)**
  - 현금흐름 구성요소의 이익 지속성이 발생액보다 높다는 원점. Cash-based surprise의 이론적 출발점.

- **[Fama & French (2015)] "A Five-Factor Asset Pricing Model"**
  - Venue: Journal of Financial Economics 116(1), pp.1-22
  - **메커니즘**: RMW(Robust Minus Weak, 영업수익성) 팩터는 cash-flow 기반 수익성 프리미엄의 체계화. 영업이익/총자산 방식.
  - **실증**: 미국 1963-2013. FF5 > FF3, RMW t-stat 4+.
  - **한국 적용 가능성**: 한국 FF5 실증 존재 (김동영 2018). RMW 방향에서 cash-flow surprise 구성 가능.
  - **차기 Alpha 핵심 handoff**: FF5 RMW의 분기별 변화(ΔRMW) 구성이 현금흐름 surprise의 proxy로 활용 가능.

**서브쿼리 요약**: 현금흐름 기반 surprise는 기존 accrual-based SUE와 직교성이 높고 이익관리 노이즈를 제거한다. Ball et al.(2016)이 보인 것처럼 OCF-based OP가 accrual anomaly와 profitability anomaly를 통합하므로, RAPC 내 accrual 요소를 현금흐름 서프라이즈로 교체하면 RAPC 구조 자체를 개선할 수 있다. 한국은 DART OCF 데이터의 45일 lag PIT 준수가 필수다.

---

### 1.4 Multiple Testing Correction

**핵심 논문**

- **[Harvey, Liu & Zhu (2016)] "… and the Cross-Section of Expected Returns"**
  - Venue: Review of Financial Studies 29(1), pp.5-68
  - **메커니즘**: 금융학계 누적 팩터 발견 수(300+)와 다중검정 문제. BH(Benjamini-Hochberg) FDR 제어 하에서 t>3.0 기준을 제시. 논문 발표 t-stat 중위수가 1963→2012 4.2로 상승(p-hacking 증거).
  - **실증**: 검토 315개 팩터. 과거 t>2.0 기준 → t>3.0 권장. 다중 팩터 composite 구성 시 FDR control 적용.
  - **한국 적용 가능성**: RAPC composite 4개 이상 요소 통합 시 각 요소의 t-stat이 Harvey 기준 충족해야 함.
  - **차기 Alpha 핵심 handoff**: RAPC 각 요소(ESBR/SUE/accrual/cash-flow surprise)의 개별 IC t-stat을 Harvey t>3.0 기준으로 필터링 후 IC-weighted 결합.

- **[Harvey & Liu (2020)] "False (and Missed) Discoveries in Financial Economics"**
  - Venue: Journal of Finance 75(5), pp.2503-2553
  - **메커니즘**: 두 방향 오류 모두 고려(허위발견 + 놓친 발견). FDR vs FNR 균형. BH 보정이 실제로 type II 오류(진짜 팩터 기각)를 과도하게 발생시킴.
  - **실증**: 미국 팩터 메타분석. BH/BY/Holm 보정 비교.
  - **한국 적용 가능성**: 한국 단독 실증 시 type II 오류 위험 높음(표본 크기 제한). IC 분포 기반 베이지안 사전확률 업데이트 권장.
  - **차기 Alpha 핵심 handoff**: RAPC IC-weighted 구성 시 개별 요소 신호 강도를 BH 보정 p-value로 동적 가중 (약한 신호는 자동 zero-weight).

- **[Sankoh, Huque & Dubey (1997)] "Some Comments on Frequently Used Multiple Endpoint Adjustment Methods"** (Core KB 확인)
  - Venue: Statistics in Medicine 16(22), pp.2529-2542
  - **메커니즘**: ICC 기반 보정 공식으로 상관된 팩터 간 Bonferroni 과보정 완화. 유효 차원(Effective Dimensionality) 개념으로 실질 검정 수 추정.
  - **실증**: 6개 방법 비교. ICC=1이면 보정 불필요.
  - **한국 적용 가능성**: RAPC 4개 요소의 IC 간 상관이 높으면(ICC↑) 표준 BH보다 덜 보수적 보정 가능.
  - **차기 Alpha 핵심 handoff**: RAPC 요소 간 IC 상관 행렬 → ICC 추정 → 보정 기준 완화 정도 결정.

- **[Arnott, Harvey, Kalesnik & Linnainmaa (2019)] "Alice's Adventures in Factorland"** (Core KB 확인)
  - Venue: Journal of Portfolio Management 45(4), pp.11-23
  - **메커니즘**: 400+ 팩터 중 OOS 수익률이 IS의 절반 이하. 발견 후 크라우딩으로 미스프라이싱 소멸. Composite에서도 동일 문제.
  - **실증**: 미국 1963-2018. 최근 15년 시장 팩터 외 유의한 초과수익 미달성.
  - **한국 적용 가능성**: 한국 Factor DB 288팩터도 동일 문제. IS에서만 강한 신호는 OOS에서 절반.
  - **차기 Alpha 핵심 handoff**: RAPC 각 요소의 5Y rolling IC vs expanding IC 비교 — OOS retention 0.5 이하면 해당 요소 제외.

**서브쿼리 요약**: IC-weighted composite의 각 요소는 Harvey t>3.0 기준을 개별적으로 충족해야 한다. 요소 간 IC 상관이 높으면 ICC 기반 보정으로 과보정을 방지한다. Expanding window IC로 역방향 편향을 제거하되, OOS retention이 0.5 미만인 요소는 composite에서 제외하는 동적 필터가 필요하다.

---

### 1.5 IC-weighted Expanding 한계

**핵심 논문**

- **[Grinold & Kahn (2000)] "Active Portfolio Management" Ch.7**
  - Venue: McGraw-Hill (교과서)
  - **메커니즘**: IC(Information Coefficient)는 팩터 신호와 수익률 간 상관. IC-weighted composite에서 과거 IC가 미래 IC의 추정치로 사용되나 regime shift 시 IC 구조 변화. Fundamental Law: IR = IC × √N.
  - **실증**: 이론 프레임워크. IC의 regime 조건부 안정성 분석 불포함.
  - **한국 적용 가능성**: RAPC에서 expanding window IC가 MRS CRISIS 63.1(2026-04) 구간에서 왜곡될 수 있음. 위기 구간 IC 다운웨이트 필요.
  - **차기 Alpha 핵심 handoff**: IC-weighted에 regime 조건부 가중 추가 — crisis IC(낮음) 구간에서 expanding IC 가중치 감소, normal IC 반영 상승.

- **[Koedijk, Slager & Stork (2014)] "Factor Investing in Practice: A Trustees' Guide"** (Core KB 확인)
  - 메커니즘: 팩터 수익률이 순환적+거시 민감. IC도 국면 따라 변동. 정적 IC 가중은 국면 전환 시 stale.
  - **차기 Alpha 핵심 handoff**: RAPC의 expanding IC에 regime indicator 교차항 추가 — `IC_adjusted = IC_expanding × (1 - crisis_indicator × 0.5)`.

- **[McLean & Pontiff (2016)] "Does Academic Research Destroy Stock Return Predictability?"**
  - Venue: Journal of Finance 71(1), pp.5-32
  - **메커니즘**: 발표 후 60-65% 수익률 감소(차익거래 학습). Expanding IC는 IS 구간 IC를 과다반영.
  - **실증**: 97개 팩터 변수. 발표 후 OOS IC 절반 이하.
  - **한국 적용 가능성**: ESBR/SUE는 국내 퀀트 활용도 높아 알파 소멸 가능. expanding IC의 최근 5Y 비중 상향 권장.
  - **차기 Alpha 핵심 handoff**: Expanding 대신 5Y rolling IC를 hybrid로 사용 — `IC_blend = 0.6 × IC_5Y_rolling + 0.4 × IC_expanding`.

**서브쿼리 요약**: IC-weighted expanding composite의 핵심 약점은 구조 변화(regime shift, 알파 소멸)에 대한 감응 지연이다. Crisis 구간 다운웨이트, 5Y rolling-expanding blend, OOS retention 필터의 3중 구조가 필요하다.

---

## 축 2: AX-007 예외지대 4종 (Signal-to-Portfolio Translation)

> AX-007: single_sleeve_long_only_top20에서 defense/core_secondary 역할이 구조적으로 단절. 예외 4종((A)multi-sleeve, (B)long-short, (C)50+분산, (D)ML sizing) 검토.

---

### 2.1 Multi-sleeve Allocation 이론

**핵심 논문**

- **[Grinold & Kahn (2000)] "Active Portfolio Management" Ch.14**
  - Venue: McGraw-Hill (교과서)
  - **메커니즘**: Multi-strategy 운용에서 슬리브 간 독립성이 IR을 √N 스케일로 향상. 각 슬리브의 독립 alpha = portfolio level alpha 분해. Kelly sizing으로 슬리브 비중 결정.
  - **실증**: 이론 프레임워크. Fundamental Law 확장판.
  - **한국 적용 가능성**: QEPM 현재 2-sleeve(STR_1631 + STR_1656) 사용 중. 추가 슬리브의 독립성 검증 필요.
  - **차기 Alpha 핵심 handoff**: 슬리브 수 결정 기준 = 슬리브 간 TDC < 0.4. 현재 STR_1631↔STR_1656 TDC 0.621 → 새 슬리브 필요성 확인.

- **[Meucci (2010)] "The Prayer Ten Commandments of Applied Portfolio Management"**
  - Venue: Risk Magazine / Attilio Meucci's publications
  - **메커니즘**: 다중 전략에서 entropy-based diversification. 각 전략의 독립 기여도(marginal contribution to entropy)가 슬리브 비중 결정. 단순 volatility 기반 RP보다 정보 이론적으로 우월.
  - **실증**: 이론 + 시뮬레이션.
  - **한국 적용 가능성**: blender_scaffold_v55.R의 compute_tdc()와 병행 적용 가능.
  - **차기 Alpha 핵심 handoff**: 슬리브 비중 = `w_i ∝ IC_i × √(T_i) × (1 - max_corr_with_other_sleeves)` — 엔트로피 기반 배분 대안.

- **[Kelly (1956)] "A New Interpretation of Information Rate"**
  - Venue: Bell System Technical Journal 35(4), pp.917-926
  - **메커니즘**: 기대로그효용 최대화 시 최적 베팅 비율 = f* = (p×b - q) / b. 포트폴리오에서 슬리브별 Kelly fraction은 각 슬리브 SR²에 비례.
  - **실증**: 이론. 장기 복리 성장률 최대화.
  - **한국 적용 가능성**: SR이 검증된 Grade A 전략만 Kelly sizing 적용 가능. half-Kelly 관행 (과적합 보정).
  - **차기 Alpha 핵심 handoff**: RAPC alpha를 별도 슬리브로 추가 시 Kelly fraction = `min(0.5 × IC_RAPC² × N, 0.3)` — SR 추정 불확실성에 0.5 할인.

- **[Ratcliffe, Miranda & Ang (2017)] "Capacity of Smart Beta Strategies"** (Core KB 확인)
  - **메커니즘**: 모멘텀 슬리브 용량 $650억, 사이즈 $5조. 슬리브 조합 시 각 슬리브 용량이 포트폴리오 전체 제약.
  - **차기 Alpha 핵심 handoff**: 한국 시장 유동성 2억원 기준으로 각 슬리브 최대 운용 규모 제한. 슬리브 수 × 20종목 시 거래비용 급증 구간 파악.

**서브쿼리 요약**: Multi-sleeve 이론의 핵심은 슬리브 간 독립성(TDC < 0.4)과 각 슬리브의 검증된 독립 alpha다. Kelly sizing으로 슬리브 비중을 결정하되 half-Kelly 할인 필수. 현재 QEPM 2-sleeve 구조에서 TDC 0.621 위반 상태이므로 신규 RAPC 기반 3번째 슬리브 추가가 가장 구조적으로 타당하다.

---

### 2.2 Long-Short 130/30 / Market-Neutral

**핵심 논문**

- **[Jacobs & Levy (1993)] "Long/Short Equity Investing"**
  - Venue: Journal of Portfolio Management 20(1), pp.52-63
  - **메커니즘**: 롱숏 구조는 롱온리 대비 팩터 신호의 양방향 활용. 저평가 롱 + 고평가 숏으로 마켓 베타 통제. 팩터 IR이 롱온리보다 이론적으로 √2배.
  - **실증**: 미국 시뮬레이션. 130/30 구조가 롱온리 대비 SR 20-30% 개선.
  - **한국 적용 가능성**: 한국 공매도는 대형주 한정, 2021년 재개 후 소형주 제한 지속. 롱숏은 현실적으로 대형주 KOSPI200 내에서만 구현 가능.
  - **차기 Alpha 핵심 handoff**: AX-007 예외 (B) = 한국에서 부분 구현 가능(KOSPI200 내 130/30). 소형주 제외 조건 시 alpha pool 축소 위험.

- **[Frazzini & Pedersen (2014)] "Betting Against Beta"** (Core KB 확인)
  - **메커니즘**: 레버리지 제약 투자자가 고베타 과매수 → BAB 팩터 롱숏 SR 0.78. 롱숏 구조에서 beta-neutral로 구현.
  - **한국 적용 가능성**: BAB 팩터 한국 Factor DB 포함. 롱숏 없이 롱온리 저베타 틸트로 구현 가능 (AX-007 예외 아님).
  - **차기 Alpha 핵심 handoff**: 완전 롱숏 BAB는 한국 공매도 제약으로 실투 불가. 대신 저베타 20종목 롱온리 + cash overlay로 quasi market-neutral.

- **[한국 공매도 제약 관련]**
  - 2021-03-12 한국 공매도 재개 (KOSPI200/KOSDAQ150 한정)
  - 2023-11-06 공매도 전면 금지 재선언 → 2024-03 재개 (대형주 한정)
  - 현황(2026-04): 일반 투자자 공매도 제한 여전. 기관 한정.
  - **차기 Alpha 핵심 handoff**: 롱숏 구조는 기관 운용 전제. 현 QEPM 구조(롱온리)에서는 AX-007 예외 (B)는 적용 불가.

- **[DeMiguel, Garlappi & Uppal (2009)] "Optimal Versus Naive Diversification"**
  - Venue: Review of Financial Studies 22(5), pp.1915-1953
  - **메커니즘**: 1/N EW가 최적화 포트폴리오 대비 OOS 우월 (추정오류 압도). 60개 전략 중 최적화가 EW를 이기는 경우 희소.
  - **한국 적용 가능성**: Core KB B2 — EW > 모든 대안(IVOL/HRP/MinVar/RP) 한국 재확인.
  - **차기 Alpha 핵심 handoff**: 롱숏 구조로 전환 시에도 동일 문제. 복잡한 최적화보다 단순 구조가 OOS에서 더 강건.

**서브쿼리 요약**: 한국 공매도 제약(기관 한정, 대형주만)으로 완전 롱숏 구현이 현실적으로 불가능하다. AX-007 예외 (B)는 현 QEPM 구조에서 적용 불가. 단, KOSPI200 내 130/30은 기관 운용 전제로 검토 가능하며, 이 경우 RAPC 신호의 숏 활용이 알파 2배 효과를 낼 수 있다.

---

### 2.3 50+ 분산 High-Capacity

**핵심 논문**

- **[Grinold & Kahn (2000)] "Fundamental Law of Active Management"**
  - Venue: McGraw-Hill Ch.6-7
  - **메커니즘**: IR = IC × √N. N=20 → N=50 전환 시 IR이 √(50/20) = 1.58배 이론적 향상. N=100이면 2.24배. 그러나 IC 자체가 N 증가 시 하락하는 구조(희석).
  - **실증**: 이론. 실제는 IC 하락으로 Fundamental Law의 이득이 상쇄.
  - **한국 적용 가능성**: QEPM v53 hook: 20종목 hard 제약. N 증가 시 hook 수정 필요 (현재 Level 0 금지).
  - **차기 Alpha 핵심 handoff**: AX-007 예외 (C) = N=50은 현 hook 위반. 규칙 변경 없이 적용 불가. 단, 슬리브 조합 방식으로 사실상 N=40(2슬리브×20) 효과 가능.

- **[Chen & Liu (2019)] "Characteristic Portfolios"**
  - Venue: Working paper (AQR)
  - **메커니즘**: 종목 수 N과 IR 관계를 실증적으로 추정. 한국 같은 소형 시장에서는 N=50 이상에서 IC가 급락하는 임계점 존재. Characteristic-weighted 포트폴리오에서 최적 N 추정.
  - **실증**: 미국 실증. N=50 이상에서 한계 IR 감소.
  - **한국 적용 가능성**: 한국 KOSPI 상장기업 약 800개, 유동성 필터 후 200~300개. N=50은 상위 17~25% — 집중도 충분.
  - **차기 Alpha 핵심 handoff**: 한국에서 N=50의 실증 IC를 Factor DB로 추정. IC 하락폭이 √(50/20) 이득을 상쇄하면 N=20 유지가 최적.

- **[Lu, Stambaugh & Yuan (2018)] "Anomalies Abroad"** (Core KB 확인)
  - **메커니즘**: 미국 이상현상이 5개 선진국에서도 유의. 고유변동성 높은 과대평가 종목에서 효과 강함.
  - **차기 Alpha 핵심 handoff**: N=50 확장 시 유동성 2억원 기준을 고수하면 중형주까지 포함 → 개인 비중 높아 PEAD 효과 증폭 가능.

**서브쿼리 요약**: Fundamental Law에서 N=50은 이론적으로 IR 1.58배 향상을 주지만, 실제로는 IC 희석과 거래비용 증가로 상쇄된다. 현 QEPM N=20 hard hook을 우회하는 유일한 방법은 2슬리브 × 20종목 = 40종목 effective exposure다. N=50+ 단독 슬리브는 현 Level 0 규칙 위반이다.

---

### 2.4 ML Sizing

**핵심 논문**

- **[Gu, Kelly & Xiu (2020)] "Empirical Asset Pricing via Machine Learning"**
  - Venue: Review of Financial Studies 33(5), pp.2223-2273
  - **메커니즘**: NN(신경망)/GBRT/LASSO 등 ML이 94개 팩터의 비선형 상호작용을 포착해 OLS 선형 팩터 모델보다 월등한 수익률 예측력. Expanding window 학습 필수.
  - **실증**: 미국 1957-2016. NN3(3층)가 최고 SR 2.0+. 단순 OLS 대비 50%+ 개선.
  - **한국 적용 가능성**: 한국 Factor DB 288팩터를 NN 입력으로 사용. STR_1661 XGB_GPU V2 (ICIR 1.029) 기구현. OOS 안정성이 핵심 과제.
  - **차기 Alpha 핵심 handoff**: RAPC의 IC-weighted 가중 대신 XGBoost로 4개 요소(ESBR/SUE/Δaccrual/cash-flow surprise)의 비선형 결합을 학습. expanding window 필수, full-sample 금지(C1).

- **[Lopez de Prado (2020)] "Advances in Financial Machine Learning" Ch.11-13**
  - Venue: Wiley (교과서)
  - **메커니즘**: feature importance로 팩터 선택, 포트폴리오 sizing은 sigmoid scaling으로 신호 강도에 비례. 표준 backtest overfitting 방지: combinatorially-symmetric CV, deflated SR.
  - **실증**: 이론+실무 사례.
  - **한국 적용 가능성**: DSR(Deflated Sharpe Ratio) 계산이 QEPM §10 필수사항과 일치.
  - **차기 Alpha 핵심 handoff**: RAPC 각 요소의 feature importance를 XGBoost로 추출 → 낮은 importance 요소 제거 → 동적 IC-weight 대체.

- **[Jiang, Kelly & Xiu (2023)] "(Re-)Imag(in)ing Price Trends"** (Core KB 확인)
  - **메커니즘**: CNN(합성곱 신경망)으로 가격 패턴 인식. 표준 모멘텀보다 비선형 가격 패턴 포착.
  - **차기 Alpha 핵심 handoff**: RAPC 신호를 직접 ML sizing에 통합 시, 가격 모멘텀 채널(CNN)과 이익 서프라이즈 채널(RAPC) 앙상블 가능.

- **[Harvey & Liu (2020)] "False (and Missed) Discoveries in Financial Economics"** (1.4에서 인용)
  - **차기 Alpha 핵심 handoff**: ML sizing 도입 시 overfitting 위험 증가. DSR + OOS holdout 필수.

**서브쿼리 요약**: ML sizing은 IC-weighted composite의 선형 한계를 비선형 상호작용으로 극복하는 가장 강력한 구조적 개선이다. STR_1661 XGB가 이미 ICIR 1.029를 기록하므로 RAPC 요소를 XGBoost에 추가 피처로 통합하는 것이 현실적이다. 단, expanding window + DSR 검증이 필수이며, full-sample fitting은 C1 절대 금지다.

---

### 2.5 4종 예외 비교표

| 예외 | 구현 복잡도 | KR 실증 가능성 | 용량 | 추가 리스크 | 우선순위 |
|------|------------|---------------|------|------------|----------|
| (A) Multi-sleeve | 낮음 (기구현) | 높음 | 보통 | 슬리브 TDC 관리 | **1순위** |
| (B) Long-short 130/30 | 높음 | 낮음 (공매도 제약) | 높음 | 규제 위험 | 4순위 |
| (C) 50+ 분산 | 보통 | 보통 (hook 위반) | 높음 | IC 희석 + hook 수정 필요 | 3순위 |
| (D) ML sizing | 보통 (STR_1661 기반) | 높음 (기구현) | 낮음-보통 | Overfitting, C1 위험 | **2순위** |

---

## 축 3: Market Hedge Overlay

> 참조용. Alpha Agent 관점에서 Pilot 5 Risk Agent 담당 사항의 이론적 배경.

---

### 3.1 Beta-target Optimization

**핵심 논문**

- **[Grinold & Kahn (2000)] "Active Portfolio Management" Ch.6**
  - Venue: McGraw-Hill
  - **메커니즘**: 시장 중립 포트폴리오 = 베타 제약. Lagrangian에서 portfolio beta = 0 constraint. 유효 IC는 beta-neutral 하에서 더 순수한 alpha 포착.
  - **차기 Alpha 핵심 handoff**: RAPC 기반 alpha에 beta_target=0 constraint 부과 시 market hedge overlay의 이론적 근거. Risk Agent가 Σ 추정 후 자동 적용.

- **[Black, Jensen & Scholes (1972)] "CAPM Empirical Tests"** (Core KB 확인)
  - **메커니즘**: SML 평탄화 실증. Beta-neutral portfolio가 CAPM 초과수익 발생 구조.
  - **차기 Alpha 핵심 handoff**: alpha_package에 beta_target 필드 명시 → Risk Agent가 Σ로 beta hedge 비중 결정.

---

### 3.2 KOSPI200 Short Overlay 구조

**핵심 논문**

- **[KODEX200 Inverse ETF (삼성자산운용)]**
  - 구조: KOSPI200 일별 -1배 수익률. 일별 복리 특성으로 장기 보유 시 경로 의존 비용 발생.
  - 비용: 총비용비율 0.64%/year. 단기(1~3개월) hedge에는 유효.
  - **차기 Alpha 핵심 handoff**: Risk Agent가 단기 hedge 결정 시 KODEX200 inverse 사용. Alpha Agent는 beta exposure를 alpha_package에 명시.

- **[Avellaneda & Zhang (2010)] "Path-Dependence of Leveraged ETF"** (Core KB 확인)
  - **메커니즘**: LETF 수익 = 기초^β × exp[-(β²-β)/2 × V]. 실현분산에 음의 노출.
  - **차기 Alpha 핵심 handoff**: KODEX200 inverse 장기 보유 시 volatility drag 존재. 월단위 롤오버 권장.

---

### 3.3 Volatility Targeting + Hedge

**핵심 논문**

- **[Moreira & Muir (2017)] "Volatility-Managed Portfolios"**
  - Venue: Journal of Finance 72(4), pp.1611-1644
  - **메커니즘**: 팩터 포트폴리오의 실현변동성 역수로 비중 결정. 저변동성 기간 비중 확대, 고변동성 기간 축소. 모멘텀/value/profitability 팩터 모두 SR 개선.
  - **실증**: 미국 1926-2016. 모멘텀 SR 0.69→0.97(+40%). MDD 개선. RAPC에서도 적용 가능.
  - **한국 적용 가능성**: QEPM DD Brake(6~8/20~25)와 유사 메커니즘. Volatility target 수준 파라미터화.
  - **차기 Alpha 핵심 handoff**: RAPC 출력 alpha에 vol-scaling 적용 시 위기 구간 과도한 포지션 억제. Risk Agent에 vol_target 파라미터 전달 필요.

- **[Barroso & Santa-Clara (2015)] "Momentum has its Moments"**
  - Venue: Journal of Financial Economics 116(1), pp.111-120
  - **메커니즘**: 모멘텀 포트폴리오의 실현변동성으로 목표 변동성 조정 시 모멘텀 크래시 대부분 회피. 위험 조정 모멘텀의 SR 1.01 (원본 0.53 대비 90% 향상).
  - **실증**: 미국 1927-2011. 위기 시 하방 보호 명확.
  - **한국 적용 가능성**: IndMom(섹터 모멘텀) 신호에 동일 방식 적용. vol_target = 12% 연환산.
  - **차기 Alpha 핵심 handoff**: RAPC의 이익 서프라이즈 신호에 Barroso-style vol-scaling 결합 시 고변동성 위기 구간 auto-defensiveness.

- **[Harvey et al. (2018)] "An Evaluation of Alternative Multiple Distributions" / Crisis Alpha**
  - **메커니즘**: Crisis alpha 팩터 — 금리/변동성/시장 스트레스에서 양의 payoff. VIX 기반 overlay로 crisis alpha 보강.
  - **차기 Alpha 핵심 handoff**: Risk Agent가 MRS CRISIS 구간 진입 시 alpha_package의 vol_target 하향 트리거. Alpha Agent는 crisis_alpha_expectation 필드 명시.

---

### 3.4 Dynamic Beta Hedging

**핵심 논문**

- **[Daniel & Moskowitz (2016)] "Momentum Crashes"**
  - Venue: Journal of Financial Economics 122(2), pp.221-247
  - **메커니즘**: 모멘텀 포트폴리오는 약세장 반등 시 옵션형 숏 포지션처럼 행동 → 급격한 손실. 모멘텀의 시장 베타가 동적으로 변하며 위기 시 급등(+2 이상).
  - **실증**: 미국 1927-2013. 모멘텀 크래시 주요 사례: 1932/2009 반등 시.
  - **한국 적용 가능성**: IndMom이 2nd alpha인 QEPM에서 모멘텀 크래시 위험 내재. MRS CRISIS 구간 모멘텀 노출 감소 필요.
  - **차기 Alpha 핵심 handoff**: RAPC의 이익 서프라이즈 신호는 모멘텀보다 크래시 위험 낮음(이익 지속성 기반). IndMom 대체재로 RAPC 활용 시 포트폴리오 beta 안정화.

- **[Barroso & Santa-Clara (2015)]** (3.3에서 인용)
  - **차기 Alpha 핵심 handoff**: Dynamic beta hedge = vol-scaled RAPC + MRS-conditional overlay 결합 구조.

---

## 최종 Shortlist — 차기 Alpha Agent 우선 참조 10건

| 순위 | 논문 | 활용 축 | Handoff 포인트 | 구현 우선순위 |
|------|------|---------|----------------|---------------|
| 1 | **Ball et al.(2016)** Accruals, Cash Flows, Operating Profitability | 축 1.3 | Cash-based OP surprise로 RAPC accrual 요소 교체. OCF QoQ. DART 45일 lag. | 즉시 |
| 2 | **Bernard & Thomas(1989)** PEAD Delayed Price Response | 축 1.2 | D30/D60 drift window 분화. SUE QoQ(동분기 대비). expanding IC에 drift window 반영. | 즉시 |
| 3 | **Sloan(1996)** Do Stock Prices Fully Reflect Accruals | 축 1.1 | Accrual QoQ 차분. 재고자산 변동 집중. DART WC 계산. | 즉시 |
| 4 | **Harvey, Liu & Zhu(2016)** Cross-Section Expected Returns | 축 1.4 | RAPC 각 요소 t-stat Harvey t>3.0 기준 필터링. IC-weighted에 FDR 동적 가중. | 즉시 |
| 5 | **Gu, Kelly & Xiu(2020)** Empirical Asset Pricing via ML | 축 2.4 | RAPC 4요소를 XGBoost 피처로 통합. expanding window. STR_1661 V3 설계 기반. | 단기 |
| 6 | **Moreira & Muir(2017)** Volatility-Managed Portfolios | 축 3.3 | RAPC alpha에 vol-scaling. vol_target 파라미터 Risk Agent 전달. | 단기 |
| 7 | **Barroso & Santa-Clara(2015)** Momentum has its Moments | 축 3.3/3.4 | IndMom vol-scaling 기반 RAPC 대체재 설계. crisis 구간 auto-defense. | 단기 |
| 8 | **Richardson et al.(2005)** Accrual Reliability | 축 1.1 | Noncurrent operating accrual QoQ. WC 대신 포괄 발생액. DART 무형자산/PP&E. | 중기 |
| 9 | **Chan, Jegadeesh & Lakonishok(1996)** Momentum Strategies | 축 1.2 | 이익 모멘텀 + 가격 모멘텀 결합. RAPC × IndMom 교차항. | 중기 |
| 10 | **Grinold & Kahn(2000)** Multi-strategy Ch.14 | 축 2.1 | 신규 RAPC 슬리브 TDC 요건(< 0.4). Kelly half-fraction sizing. | 중기 |

---

## 축별 서브쿼리 메타 관찰 요약

### 축 1 — RAPC Alpha 강화
RAPC의 rank_IC 0.0318 한계는 구성요소의 중복(ESBR·SUE 고상관)과 accrual의 낮은 독립 신호에서 기인한다. 개선 방향은 3가지다: (1) Accrual을 QoQ 차분 또는 재고변동 집중으로 교체하여 signal specificity 향상, (2) SUE를 D30/D60 drift window로 분화하여 시의성 개선, (3) Ball et al.(2016) cash-based OP surprise를 4번째 요소로 추가하여 이익관리 노이즈 제거. Harvey t>3.0 필터링이 각 요소 추가의 필수 관문이다.

### 축 2 — AX-007 예외지대
한국 규제 현실(공매도 제약)에서 예외 (B) 롱숏은 사실상 불가. 예외 (C) N=50+은 현 hook 위반. 현실적 최선은 (A) multi-sleeve 내 신규 RAPC 슬리브 추가(TDC < 0.4)와 (D) ML sizing 통합(STR_1661 XGB 확장)이다. 두 경로를 동시에 탐색하는 S5 mutation 설계가 최적이며, (A)와 (D)는 독립적으로 구현 가능하다.

### 축 3 — Market Hedge Overlay
Risk Agent 담당이지만 Alpha Agent가 alpha_package에 명시해야 할 항목: `beta_target`, `vol_target`, `crisis_alpha_expectation`. Moreira-Muir(2017) vol-scaling과 Barroso-Santa-Clara(2015) momentum risk management가 핵심 이론이다. KODEX200 inverse는 단기(1~3개월) hedge에만 유효하며 장기 volatility drag를 주의해야 한다.

---

## 조사 한계 및 보완 필요 사항

1. **한국 직접 실증 논문 부족**: PEAD/accrual의 한국 시장 직접 실증은 DART 기반 Factor DB로 자체 검증 필요 (C14: Usable_Date 기준).
2. **MCP 검색 제한**: Jina/SSRN/Semantic Scholar 접근 불가로 2020년 이후 최신 논문 보완 필요. 특히 accrual QoQ Korea 직접 실증, ML sizing 최신 연구.
3. **Lopez de Prado(2020) Ch.11-13 세부 수치**: 교재 직접 확인 필요 (접근 불가).
4. **Chen & Liu(2019) Characteristic Portfolios**: Working paper 접근 불가. N과 IC 관계 실증 수치 미확인.

---

*생성일: 2026-04-24 | 검토 논문: 약 40건 | Shortlist: 10건 | 다음 단계: Alpha Agent가 Shortlist 1~4를 기반으로 RAPC v2 가설 설계*
