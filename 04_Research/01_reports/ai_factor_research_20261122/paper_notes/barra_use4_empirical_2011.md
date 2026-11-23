# Barra US Equity Model (USE4) Empirical Notes — 정리 (한국 재현용)

- 원문: Yang Liu · Jose Menchero · D. J. Orr · Jun Wang, "The Barra US Equity Model (USE4) Empirical Notes", MSCI Model Insight, 2011-09, 62쪽 (표지 RV May 2011).
- 읽은 범위: 1~62쪽 전부(글 뽑기) + 그림 쪽 17 · 19 · 20 · 21 · 27 · 29~33 · 36~48 · 59 · 60 쪽 그림 판독 + 식 쪽 51 · 52 · 55 · 56 · 57 · 58 쪽 그림으로 식 재확인. 18쪽은 빈 쪽(머리글 · 바닥글만). 53 · 54쪽 식(MLEV · DTOA · BLEV)은 뽑힌 글로 판독(단순 분수라 모호하지 않음).
- 표기: 수치는 원문 그대로. 차트 판독값은 '약'. 불확실 판독 = (?). 원문에 없는 것은 '원문에 없음'.
- 표본 기간(문서 전체 공통): 1995-06-30 ~ 2011-05-31, 191개월 수익(검정 구간 표기는 1995-07 ~ 2011-05).
- 짝 문서: USE4 Methodology Notes (Menchero, Orr, Wang 2011). 방법론 세부(고유위험 · 고유값 조정 · 변동성 국면 조정 식)는 그쪽 소관이고, 이 문서는 요약만 한다.

---

## 0. 모델 개요 (1~2장 요약 — 재현에 필요한 사실만)

- USE4 = 국가(Country) 팩터 1 + 업종 팩터 60 + 스타일 팩터 12 (= 73 팩터, 이 합계 숫자는 문서에 직접 적혀 있지 않고 구성에서 셈).
- 두 판: USE4S(단기 · 월 예측 지평에 더 민감) · USE4L(장기 · 안정성 우선). **팩터 노출과 팩터 수익은 동일**, 팩터 공분산과 고유위험 예측만 다르다. 반감기 등 S/L 판의 수치 모수는 원문에 없음(방법론 노트 소관).
- 주요 개선 9가지(1.1절): ① 최적화 편향 조정(Optimization Bias Adjustment — 고유팩터 위험을 몬테카를로로 편향 추정해 보정) ② 변동성 국면 조정(Volatility Regime Adjustment — 횡단면 편향 통계의 가중평균으로 팩터 변동성 · 고유위험을 현재 수준에 맞춤) ③ 국가 팩터 도입 ④ 일별 종목 고유수익 기반 고유위험 모델 ⑤ 고유위험의 베이즈 축소 ⑥ 팩터 · 고유 성분의 동일한 반응도 ⑦ GICS 기반 복수 업종 노출 ⑧ 연구 코드 · 운영 코드 이중 맹검 독립 검증 ⑨ 모든 구성요소 일간 갱신.
- 2.1 최적화 편향: 표본 공분산은 저변동 고유팩터 위험을 과소, 고변동 고유팩터 위험을 과대 예측. 고유팩터 편향을 없애면 최적화 포트폴리오 편향이 사실상 없어진다. 고유팩터 수 = 순수 팩터 수.
- 2.3 국가 팩터: 국가 팩터 포트폴리오 = 시가총액 가중 국가 포트폴리오로 해석. 국가 팩터가 있으면 업종 팩터 = 해당 업종 100% 롱 · 국가 팩터 100% 숏의 달러 중립 포트폴리오(업종 성과 = 시장 대비). 위기 때 업종 간 상관 상승을 국가 팩터 변동성 상승으로 더 빨리 잡는다.
- 2.4 고유위험 베이즈 축소: 시가총액 10분위로 나누고, 분위 안 고유위험 예측의 평균 · 표준편차를 계산해 예측값을 분위 평균 쪽으로 당긴다. 축소 강도는 평균에서 표준편차 몇 개 떨어졌는지에 따라 커진다. (축소 식 · 계수 q 는 원문에 없음 — 방법론 노트 소관.)
- 회귀: 팩터 공분산용으로는 **일별** 횡단면 회귀, 팩터 t 값(표 4.1 · 4.2)은 **월별** 횡단면 회귀. 회귀 가중 = **시가총액 제곱근**(4.3절 · 부록 B).

---

## 1. 추정 유니버스 (3.1절, 7쪽)

| 항목 | 원문 내용 |
|---|---|
| 정의 | 커버리지 유니버스 = 위험 예측을 내주는 전체 종목. 추정 유니버스(ESTU) = 모델 추정에 실제로 쓰는 부분집합 |
| 선정 원칙 3가지 | 대표성(representation) · 유동성(liquidity) · 안정성(stability) |
| 실제 규칙 | **MSCI USA IMI(Investable Market Index)** 구성 종목을 추정 유니버스로 사용 |
| IMI 의 범위 | 유동주식 조정 시가총액의 **99%** 를 목표로 함 |
| 안정성 | MSCI 지수 구성 방법론의 안정성 규칙을 그대로 승계 |
| 유동성 | 지수 방법론의 유동성 심사 규칙을 통과한 투자 가능 종목만 |
| 그 밖의 세부(최소 시총 · 거래대금 문턱 · 상장 기간 · 종목 유형 제외) | 원문에 없음(MSCI IMI 지수 방법론 문서 소관) |
| ESTU 종목 수 | 원문에 없음 |

- 업종 비중(표 3.1)은 ESTU 안에서 **총 시가총액**으로 계산. 스타일 표준화의 "시가총액 가중 평균 0"도 ESTU 기준(3.4절: "cap-weighted estimation universe ... is style neutral").

---

## 2. 업종 팩터 (3.2절, 7~13쪽, 표 3.1 · 3.2 · 3.3)

### 2-1. 설명
- GICS 계층: 섹터 10 · 산업그룹 24 · 그 아래 산업 · 세부산업(sub-industry). GICS 코드는 매년 재검토.
- 국가별로 업종 구조를 맞춤 설계: 섹터마다 어떤 산업 · 세부산업 조합이 시장 구조를 가장 잘 반영하는지, 경제적 직관과 설명력(in-sample R²)을 함께 고려해 고름.
- 팩터가 되는 업종은 변동성이 높고 비중이 큰 경향. 60개 업종 팩터는 세부산업 전체를 쓴 경우의 in-sample R² 대부분을 잡으면서 통계적 유의성은 훨씬 높다(R² 수치 원문에 없음).
- 보건의료 예시(본문): 산업그룹 3510 에서 세 팩터 — 351010 + 351030 → 보건의료 장비 · 기술(한 팩터), 351020 은 둘로 나눔 → 관리의료(35102030) · 의료 서비스 제공자(세부산업 3개). 산업그룹 3520 은 제약(352020)을 바이오(352010) · 생명과학(352030)에서 분리.

### 2-2. 섹터별 분할 수준 (표 3.2 에서 정리 — 정리자가 코드 자릿수로 판정)
GICS 코드 자릿수: 4자리 = 산업그룹 · 6자리 = 산업 · 8자리 = 세부산업.

| 섹터 | 팩터 수 | 분할 수준 |
|---|---|---|
| 에너지 | 4 | 전부 세부산업(8자리) 수준. 1010101x 시추 · 장비서비스 분리, 101020 은 탐사생산(10102020)만 떼고 나머지 세부산업 4개 묶음 |
| 소재 | 7 | 화학 151010 은 세부산업 수준(특수화학 15101050 분리, 나머지 4개 묶음) · 건설자재 · 용기포장 · 종이임산은 산업(6자리) · 금속광업 151040 은 세부산업으로 철강알루미늄(2개) · 귀금속금(3개)으로 분할 |
| 산업재 | 12 | 자본재 201010~201070 은 산업 수준, 단 기계 201060 은 세부산업 2개(건설농기계 · 산업기계)로 분할 · 상업전문서비스 = 산업그룹 2020 통째 · 운송 2030 은 산업 수준으로 항공화물해운(3개 묶음) · 항공사 · 도로철도 |
| 경기소비재 | 12 | 자동차 = 산업그룹 2510 통째 · 미디어 = 산업그룹 2540 통째 · 가계내구재 252010 은 세부산업으로 주택건설(25201030) 분리 · 레저 · 섬유의류 = 산업 2개 묶음 · 호텔레저 = 세부산업 3개 + 산업 253020 · 식당 = 세부산업 · 유통 255010+255030 묶음 · 인터넷판매 255020 · 전문소매 255040 은 세부산업 3분할(의류소매 25504010 · 전문소매 4개 · 전문점 25504040) |
| 필수소비재 | 4 | 식품소매 = 산업그룹 3010 · 음료+담배 = 산업 2개 묶음 · 식품 = 산업 · 가정개인용품 = 산업그룹 3030 |
| 보건의료 | 5 | 위 2-1 본문 설명(산업 + 세부산업 혼합) |
| 금융 | 5 | 은행 = 산업그룹 4010 · 다각화금융 = 산업그룹 4020 · 보험 403010 은 세부산업 수준 2분할 · 부동산 = 산업그룹 4040 |
| 정보기술 | 6 | 인터넷SW · IT서비스 = 산업 451010 + 세부산업 2개 · 소프트웨어 451030 · 통신장비 452010 · 컴퓨터전자 = 산업 3개 · 반도체장비 · 반도체 = 세부산업(각각 4520xxxx 와 4530xxxx 두 코드가 함께 실림 — GICS 개편 전후 코드를 함께 적은 것으로 보임 (?) · 원문 설명 없음) |
| 통신서비스 | 2 | 산업 수준 2개 |
| 유틸리티 | 3 | 전력 · 가스 = 산업, 복합 · 수도 · 발전 = 산업 3개 묶음 |
| 합계 | 60 | |

### 2-3. 표 3.1 — USE4 업종 팩터와 비중 (8~9쪽)
비중 = ESTU 안 총 시가총액 비중(%). 평균 = 1995-06-30 ~ 2011-05-31 표본 평균. **종목 수 열은 원문에 없음**(표 3.1 열 = GICS 섹터 · 코드 · 이름 · 평균 비중 · 2011-05-31 비중).

| 섹터 | 코드 | 업종 팩터 | 평균 비중 | 2011-05-31 비중 |
|---|---|---|---|---|
| Energy | 1 | Oil and Gas Drilling | 0.50 | 0.40 |
| Energy | 2 | Oil and Gas Equipment and Services | 1.11 | 1.92 |
| Energy | 3 | Oil Gas and Consumable Fuels | 3.12 | 4.03 |
| Energy | 4 | Oil and Gas Exploration and Production | 2.14 | 4.15 |
| Materials | 5 | Chemicals | 1.43 | 1.71 |
| Materials | 6 | Specialty Chemicals | 0.73 | 0.90 |
| Materials | 7 | Construction Materials | 0.09 | 0.06 |
| Materials | 8 | Containers and Packaging | 0.31 | 0.33 |
| Materials | 9 | Aluminum Steel | 0.39 | 0.42 |
| Materials | 10 | Precious Metals Gold Mining | 0.46 | 0.81 |
| Materials | 11 | Paper and Forest Products | 0.33 | 0.20 |
| Industrials | 12 | Aerospace and Defense | 1.49 | 1.89 |
| Industrials | 13 | Building Products | 0.24 | 0.20 |
| Industrials | 14 | Construction and Engineering | 0.20 | 0.33 |
| Industrials | 15 | Electrical Equipment | 1.02 | 0.86 |
| Industrials | 16 | Industrial Conglomerates | 1.13 | 0.69 |
| Industrials | 17 | Construction and Farm Machinery | 0.48 | 0.92 |
| Industrials | 18 | Industrial Machinery | 1.18 | 1.38 |
| Industrials | 19 | Trading Companies and Distributors | 0.57 | 0.58 |
| Industrials | 20 | Commercial and Professional Services | 2.44 | 1.74 |
| Industrials | 21 | Transportation Air Freight and Marine | 0.79 | 0.72 |
| Industrials | 22 | Airlines | 0.24 | 0.21 |
| Industrials | 23 | Road and Rail | 0.87 | 1.12 |
| Consumer Discretionary | 24 | Automobiles and Components | 0.72 | 0.94 |
| Consumer Discretionary | 25 | Household Durables (non-Homebuilding) | 0.57 | 0.49 |
| Consumer Discretionary | 26 | Homebuilding | 0.20 | 0.15 |
| Consumer Discretionary | 27 | Leisure Products Textiles Apparel and Luxury | 0.80 | 0.91 |
| Consumer Discretionary | 28 | Hotels Leisure and Consumer Services | 1.05 | 1.26 |
| Consumer Discretionary | 29 | Restaurants | 0.82 | 1.15 |
| Consumer Discretionary | 30 | Media | 4.07 | 3.28 |
| Consumer Discretionary | 31 | Distributors Multiline Retail | 1.28 | 0.86 |
| Consumer Discretionary | 32 | Internet and Catalog Retail | 0.85 | 1.49 |
| Consumer Discretionary | 33 | Apparel and Textiles | 0.93 | 1.03 |
| Consumer Discretionary | 34 | Specialty Retail | 1.56 | 1.93 |
| Consumer Discretionary | 35 | Specialty Stores | 0.48 | 0.33 |
| Consumer Staples | 36 | Food and Staples Retailing | 1.66 | 1.81 |
| Consumer Staples | 37 | Beverages Tobacco | 2.81 | 3.36 |
| Consumer Staples | 38 | Food Products | 1.95 | 1.90 |
| Consumer Staples | 39 | Household and Personal Products | 2.09 | 1.95 |
| Health Care | 40 | Health Care Equipment and Technology | 2.07 | 2.47 |
| Health Care | 41 | Health Care Providers (non-HMO) | 1.34 | 1.20 |
| Health Care | 42 | Managed Health Care | 0.79 | 0.93 |
| Health Care | 43 | Biotechnology Life Sciences | 1.85 | 2.15 |
| Health Care | 44 | Pharmaceuticals | 6.41 | 4.68 |
| Financials | 45 | Banks | 6.12 | 3.00 |
| Financials | 46 | Diversified Financials | 7.02 | 6.75 |
| Financials | 47 | Insurance Brokers and Reinsurance | 3.20 | 2.41 |
| Financials | 48 | Life Health and Multi-line Insurance | 1.30 | 1.03 |
| Financials | 49 | Real Estate | 2.00 | 3.00 |
| Information Technology | 50 | Internet Software and IT Services | 2.64 | 4.17 |
| Information Technology | 51 | Software | 4.42 | 4.74 |
| Information Technology | 52 | Communications Equipment | 3.11 | 2.17 |
| Information Technology | 53 | Computers Electronics | 3.82 | 4.34 |
| Information Technology | 54 | Semiconductor Equipment | 0.45 | 0.39 |
| Information Technology | 55 | Semiconductors | 2.75 | 2.39 |
| Telecom | 56 | Diversified Telecommunication Services | 3.40 | 1.77 |
| Telecom | 57 | Wireless Telecommunication Services | 1.00 | 0.89 |
| Utilities | 58 | Electric Utilities | 2.07 | 1.66 |
| Utilities | 59 | Gas Utilities | 0.46 | 0.37 |
| Utilities | 60 | Multi-Utilities Water Utilities Power | 0.67 | 1.08 |

(표의 합계 행은 원문에 없음.)

### 2-4. 표 3.2 — 업종 팩터 ↔ GICS 코드 (10~11쪽)

| 코드 | 업종 팩터 | GICS 코드 |
|---|---|---|
| 1 | Oil and Gas Drilling | 10101010 |
| 2 | Oil and Gas Equipment and Services | 10101020 |
| 3 | Oil Gas and Consumable Fuels | 10102010, 10102030, 10102040, 10102050 |
| 4 | Oil and Gas Exploration and Production | 10102020 |
| 5 | Chemicals | 15101010, 15101020, 15101030, 15101040 |
| 6 | Specialty Chemicals | 15101050 |
| 7 | Construction Materials | 151020 |
| 8 | Containers and Packaging | 151030 |
| 9 | Aluminum Steel | 15104010, 15104050 |
| 10 | Precious Metals Gold Mining | 15104020, 15104030, 15104040 |
| 11 | Paper and Forest Products | 151050 |
| 12 | Aerospace and Defense | 201010 |
| 13 | Building Products | 201020 |
| 14 | Construction and Engineering | 201030 |
| 15 | Electrical Equipment | 201040 |
| 16 | Industrial Conglomerates | 201050 |
| 17 | Construction and Farm Machinery | 20106010 |
| 18 | Industrial Machinery | 20106020 |
| 19 | Trading Companies and Distributors | 201070 |
| 20 | Commercial and Professional Services | 2020 |
| 21 | Transportation Air Freight and Marine | 203010, 203030, 203050 |
| 22 | Airlines | 203020 |
| 23 | Road and Rail | 203040 |
| 24 | Automobiles and Components | 2510 |
| 25 | Household Durables (non-Homebuilding) | 25201010, 25201020, 25201040, 25201050 |
| 26 | Homebuilding | 25201030 |
| 27 | Leisure Products Textiles Apparel and Luxury | 252020, 252030 |
| 28 | Hotels Leisure and Consumer Services | 25301010, 25301020, 25301030, 253020 |
| 29 | Restaurants | 25301040 |
| 30 | Media | 2540 |
| 31 | Distributors Multiline Retail | 255010, 255030 |
| 32 | Internet and Catalog Retail | 255020 |
| 33 | Apparel and Textiles | 25504010 |
| 34 | Specialty Retail | 25504020, 25504030, 25504050, 25504060 |
| 35 | Specialty Stores | 25504040 |
| 36 | Food and Staples Retailing | 3010 |
| 37 | Beverages Tobacco | 302010, 302030 |
| 38 | Food Products | 302020 |
| 39 | Household and Personal Products | 3030 |
| 40 | Health Care Equipment and Technology | 351010, 351030 |
| 41 | Health Care Providers (non-HMO) | 35102010, 35102015, 35102020 |
| 42 | Managed Health Care | 35102030 |
| 43 | Biotechnology Life Sciences | 352010, 352030 |
| 44 | Pharmaceuticals | 352020 |
| 45 | Banks | 4010 |
| 46 | Diversified Financials | 4020 |
| 47 | Insurance Brokers and Reinsurance | 40301010, 40301040, 40301050 |
| 48 | Life Health and Multi-line Insurance | 40301020, 40301030 |
| 49 | Real Estate | 4040 |
| 50 | Internet Software and IT Services | 451010, 45102010, 45102020 |
| 51 | Software | 451030 |
| 52 | Communications Equipment | 452010 |
| 53 | Computers Electronics | 452020, 452030, 452040 |
| 54 | Semiconductor Equipment | 45205010, 45301010 |
| 55 | Semiconductors | 45205020, 45301020 |
| 56 | Diversified Telecommunication Services | 501010 |
| 57 | Wireless Telecommunication Services | 501020 |
| 58 | Electric Utilities | 551010 |
| 59 | Gas Utilities | 551020 |
| 60 | Multi-Utilities Water Utilities Power | 551030, 551040, 551050 |

### 2-5. 표 3.3 — 업종별 최대 종목(2011-05-31, 시가총액 십억 달러) (12~13쪽)
본문: 최대 종목 Exxon Mobil(>$420bn), 다음 Apple · Microsoft · IBM(모두 IT).

| 코드 | 업종 | 최대 종목 (시총) |
|---|---|---|
| 1 | Oil and Gas Drilling | NOBLE CORPORATION BAAR ($10.6) |
| 2 | Oil and Gas Equipment and Services | SCHLUMBERGER LTD ($117.0) |
| 3 | Oil Gas and Consumable Fuels | EXXON MOBIL CORP ($420.9) |
| 4 | Oil and Gas Exploration and Production | APACHE CORP ($47.6) |
| 5 | Chemicals | DU PONT E I DE NEMOURS & CO ($48.7) |
| 6 | Specialty Chemicals | LYONDELLBASELL INDUSTRIES N V ($24.8) |
| 7 | Construction Materials | VULCAN MATLS CO ($5.2) |
| 8 | Containers and Packaging | BALL CORP ($7.0) |
| 9 | Aluminum Steel | ALCOA INC ($17.2) |
| 10 | Precious Metals Gold Mining | FREEPORT-MCM GLD ($48.6) |
| 11 | Paper and Forest Products | INTL PAPER CO ($13.7) |
| 12 | Aerospace and Defense | UNITED TECHNOLOGIES CORP ($81.0) |
| 13 | Building Products | MASCO CORP ($5.1) |
| 14 | Construction and Engineering | FLUOR CORP NEW ($12.3) |
| 15 | Electrical Equipment | EMERSON ELEC CO ($41.1) |
| 16 | Industrial Conglomerates | GENERAL ELECTRIC CO ($209.3) |
| 17 | Construction and Farm Machinery | CATERPILLAR INC DEL ($67.2) |
| 18 | Industrial Machinery | DANAHER CORP DEL ($35.7) |
| 19 | Trading Companies and Distributors | GRAINGER W W INC ($10.4) |
| 20 | Commercial and Professional Services | WASTE MGMT INC DEL ($18.5) |
| 21 | Transportation Air Freight and Marine | UNITED PARCEL SERVICE INC ($53.6) |
| 22 | Airlines | SOUTHWEST AIRLS CO ($9.4) |
| 23 | Road and Rail | UNION PAC CORP ($51.8) |
| 24 | Automobiles and Components | FORD MTR CO DEL ($50.8) |
| 25 | Household Durables (non-Homebuilding) | STANLEY BLACK & DECKER INC ($12.3) |
| 26 | Homebuilding | NVR INC ($4.2) |
| 27 | Leisure Products Textiles Apparel and Luxury | NIKE INC ($32.8) |
| 28 | Hotels Leisure and Consumer Services | LAS VEGAS SANDS CORP ($28.4) |
| 29 | Restaurants | MCDONALDS CORP ($86.1) |
| 30 | Media | WALT DISNEY CO ($78.8) |
| 31 | Distributors Multiline Retail | TARGET CORP ($35.1) |
| 32 | Internet and Catalog Retail | AMAZON COM INC ($88.3) |
| 33 | Apparel and Textiles | TJX COS INC NEW ($21.0) |
| 34 | Specialty Retail | HOME DEPOT INC ($60.4) |
| 35 | Specialty Stores | STAPLES INC ($12.2) |
| 36 | Food and Staples Retailing | WAL MART STORES INC ($196.7) |
| 37 | Beverages Tobacco | COCA COLA CO ($155.1) |
| 38 | Food Products | KRAFT FOODS INC ($61.1) |
| 39 | Household and Personal Products | PROCTER & GAMBLE CO ($187.5) |
| 40 | Health Care Equipment and Technology | MEDTRONIC INC ($44.0) |
| 41 | Health Care Providers (non-HMO) | EXPRESS SCRIPTS INC ($31.3) |
| 42 | Managed Health Care | UNITEDHEALTH GROUP INC ($53.8) |
| 43 | Biotechnology Life Sciences | AMGEN INC ($57.2) |
| 44 | Pharmaceuticals | JOHNSON & JOHNSON ($184.8) |
| 45 | Banks | WELLS FARGO & CO NEW ($148.9) |
| 46 | Diversified Financials | JPMORGAN CHASE & CO ($169.0) |
| 47 | Insurance Brokers and Reinsurance | BERKSHIRE HATHAWAY [B] ($82.1) |
| 48 | Life Health and Multi-line Insurance | AMERICAN INTL GROUP INC ($54.1) |
| 49 | Real Estate | SIMON PPTY GROUP INC NEW ($34.6) |
| 50 | Internet Software and IT Services | INTERNATIONAL BUSINESS MACHS ($209.9) |
| 51 | Software | MICROSOFT CORP ($214.0) |
| 52 | Communications Equipment | QUALCOMM INC ($94.8) |
| 53 | Computers Electronics | APPLE INC ($319.1) |
| 54 | Semiconductor Equipment | APPLIED MATLS INC ($18.4) |
| 55 | Semiconductors | INTEL CORP ($125.6) |
| 56 | Diversified Telecommunication Services | AT&T INC ($186.5) |
| 57 | Wireless Telecommunication Services | AMERICAN TOWER CORP ($22.1) |
| 58 | Electric Utilities | SOUTHERN CO ($33.3) |
| 59 | Gas Utilities | ONEOK INC NEW ($7.6) |
| 60 | Multi-Utilities Water Utilities Power | DOMINION RES INC VA NEW ($27.7) |

(본문은 Apple · Microsoft · IBM 이 Exxon 다음 3대 종목이라 적었으나, 표의 GE $209.3 은 IBM $209.9 보다 작아 일치. 문제 없음.)

---

## 3. 복수 업종 노출 (3.3절, 13~15쪽, 표 3.4)

### 3-1. 방법 (원문 절차)
1. 설명 변수 2개: **자산(Assets)** 과 **매출(Sales)**.
2. 업종마다 "업종 베타" = 가격 대 자산 비율 · 가격 대 매출 비율을 추정: **주 업종(primary industry) 안에서 기업 시가총액을 자산에 대해, 따로 매출에 대해 회귀**한 기울기(두 회귀는 별도).
3. 사업부문(segment) 공시에서 기업의 자산 · 매출을 업종별로 쪼갠다.
4. 업종별 자산 · 매출 × 해당 업종 베타 → 그 업종이 설명하는 기업 시가총액 추정.
5. 업종별 설명 시가총액 ÷ 기업 총 시가총액(설명분 합) = 복수 업종 노출.
6. 업종 노출은 **최대 5개**, 합 = **1**.
- 자산 기반과 매출 기반 추정을 어떻게 합치는지(가중 · 평균) · 회귀 절편 유무 · 회귀 가중 · 갱신 주기: 원문에 없음(방법론 노트 소관).
- 본문 오타: "a breakdown of the firm's Assets of Sales" (Assets and Sales 의 뜻으로 보임).

### 3-2. 표 3.4 — 업종 베타(자산 · 매출, 표본 평균 1995-06-30 ~ 2011-05-31)와 복수 업종 종목 비중(2011-05-31, %)
"Multi-Ind Weight" = 2011-05-31 현재 그 업종에서 복수 업종 노출을 가진 종목의 비중(%).

| 코드 | 업종 | 자산 베타 | 매출 베타 | 복수업종 비중 |
|---|---|---|---|---|
| 1 | Oil and Gas Drilling | 1.25 | 2.74 | 55.52 |
| 2 | Oil and Gas Equipment and Services | 1.38 | 1.43 | 80.25 |
| 3 | Oil Gas and Consumable Fuels | 0.88 | 0.60 | 90.61 |
| 4 | Oil and Gas Exploration and Production | 0.83 | 2.02 | 54.43 |
| 5 | Chemicals | 0.87 | 0.92 | 98.67 |
| 6 | Specialty Chemicals | 0.95 | 0.91 | 66.71 |
| 7 | Construction Materials | 0.93 | 1.25 | 100.00 |
| 8 | Containers and Packaging | 0.42 | 0.57 | 74.37 |
| 9 | Aluminum Steel | 0.57 | 0.47 | 77.20 |
| 10 | Precious Metals Gold Mining | 0.82 | 1.31 | 88.26 |
| 11 | Paper and Forest Products | 0.51 | 0.62 | 83.38 |
| 12 | Aerospace and Defense | 0.83 | 0.81 | 96.14 |
| 13 | Building Products | 0.71 | 0.51 | 94.49 |
| 14 | Construction and Engineering | 0.72 | 0.39 | 76.44 |
| 15 | Electrical Equipment | 1.24 | 1.16 | 88.69 |
| 16 | Industrial Conglomerates | 0.67 | 1.71 | 99.62 |
| 17 | Construction and Farm Machinery | 0.62 | 0.57 | 78.35 |
| 18 | Industrial Machinery | 0.99 | 0.91 | 88.82 |
| 19 | Trading Companies and Distributors | 0.96 | 0.53 | 76.91 |
| 20 | Commercial and Professional Services | 0.92 | 0.77 | 67.48 |
| 21 | Transportation Air Freight and Marine | 0.86 | 0.69 | 75.70 |
| 22 | Airlines | 0.22 | 0.23 | 10.98 |
| 23 | Road and Rail | 0.55 | 0.77 | 44.55 |
| 24 | Automobiles and Components | 0.26 | 0.22 | 89.85 |
| 25 | Household Durables (non-Homebuilding) | 0.80 | 0.65 | 54.48 |
| 26 | Homebuilding | 0.47 | 0.41 | 64.60 |
| 27 | Leisure Products Textiles Apparel and Luxury | 0.92 | 0.77 | 48.51 |
| 28 | Hotels Leisure and Consumer Services | 0.69 | 1.20 | 62.66 |
| 29 | Restaurants | 1.42 | 1.02 | 22.91 |
| 30 | Media | 0.76 | 1.87 | 53.16 |
| 31 | Distributors Multiline Retail | 0.68 | 0.48 | 45.07 |
| 32 | Internet and Catalog Retail | 1.26 | 1.04 | 37.74 |
| 33 | Apparel and Textiles | 1.45 | 0.71 | 73.71 |
| 34 | Specialty Retail | 1.53 | 0.72 | 55.19 |
| 35 | Specialty Stores | 0.68 | 0.43 | 37.18 |
| 36 | Food and Staples Retailing | 0.99 | 0.35 | 58.58 |
| 37 | Beverages Tobacco | 1.08 | 1.28 | 27.01 |
| 38 | Food Products | 0.84 | 0.59 | 75.13 |
| 39 | Household and Personal Products | 1.94 | 1.92 | 87.76 |
| 40 | Health Care Equipment and Technology | 1.69 | 2.15 | 54.99 |
| 41 | Health Care Providers (non-HMO) | 0.86 | 0.62 | 69.87 |
| 42 | Managed Health Care | 0.58 | 0.57 | 48.87 |
| 43 | Biotechnology Life Sciences | 2.48 | 5.53 | 22.63 |
| 44 | Pharmaceuticals | 2.73 | 3.71 | 43.71 |
| 45 | Banks | 0.15 | 2.06 | 29.94 |
| 46 | Diversified Financials | 0.14 | 1.60 | 53.15 |
| 47 | Insurance Brokers and Reinsurance | 0.36 | 1.35 | 49.44 |
| 48 | Life Health and Multi-line Insurance | 0.12 | 1.35 | 80.85 |
| 49 | Real Estate | 0.57 | 3.25 | 41.13 |
| 50 | Internet Software and IT Services | 1.17 | 1.20 | 30.94 |
| 51 | Software | 2.69 | 3.74 | 13.86 |
| 52 | Communications Equipment | 1.55 | 1.64 | 50.30 |
| 53 | Computers Electronics | 1.10 | 0.91 | 27.52 |
| 54 | Semiconductor Equipment | 1.86 | 2.25 | 51.06 |
| 55 | Semiconductors | 2.06 | 2.91 | 5.36 |
| 56 | Diversified Telecommunication Services | 0.80 | 1.52 | 84.09 |
| 57 | Wireless Telecommunication Services | 0.79 | 1.90 | 91.83 |
| 58 | Electric Utilities | 0.41 | 1.01 | 97.56 |
| 59 | Gas Utilities | 0.50 | 0.72 | 95.70 |
| 60 | Multi-Utilities Water Utilities Power | 0.47 | 0.87 | 75.71 |
| — | **Average** | **0.96** | **1.27** | **62.99** |

본문 판독: 매출 베타 최저 = 항공(0.23) · 자동차(0.22) · 식품소매(0.35) → 시총 대비 매출이 큼. 최고 = 바이오생명과학(5.53) · 소프트웨어(3.74) · 제약(3.71). 자산 베타 최저 = 금융 섹터(0.12~0.36 · 높은 레버리지). 복수업종 비중 최저 = 항공(10.98) · 반도체(5.36) → 사업이 가장 덜 다각화. 평균 복수업종 비중 거의 63%.
(주의: 본문은 "lowest ... Airlines, Automobiles, and Food & Staples Retailing" 순으로 적었지만 표 값으로는 자동차 0.22 < 항공 0.23 < 식품소매 0.35. 순서 차이일 뿐 내용 모순 아님.)

---

## 4. 스타일 팩터 (3.4절 15~17쪽 + 부록 A 51~55쪽)

### 4-1. 공통 규칙 (원문)
- 스타일 팩터는 기술자(descriptor)라 부르는 종목 속성들로 만든다.
- **표준화: 시가총액 가중 평균 0, 동일 가중 표준편차 1.** → 시가총액 가중 ESTU 는 스타일 중립.
- 스타일 팩터 수 = **12**.
- 기술자 단위 표준화 방식 · 결측치 대체 · 윈저화 문턱(몇 표준편차) · 기술자 결합 후 재표준화 여부: **원문에 없음**(NLS · NLB 에만 "윈저화 후 표준화"가 적혀 있고 문턱 수치는 없음).
- 직교화 2건만 명시: Residual Volatility ⟂ Beta · NLSIZE ⟂ Size · NLBETA ⟂ Beta (마지막 둘은 "regression-weighted basis" = 회귀 가중(시가총액 제곱근) 기반).

### 4-2. 3.4절 정성 설명 (요약)
- **Beta**: 대개 가장 중요한 스타일. 국가 팩터로 설명 안 되는 시장 위험. 초과수익을 시총가중 ESTU 에 시계열 회귀. 고베타 쏠림 롱온리 포트는 Beta(+) 와 Country 위험이 더해지고(두 팩터 시계열 상관이 매우 높음), 저베타 쏠림은 부분 상쇄.
- **Momentum**: 흔히 두 번째로 강함(때로 Beta 를 넘음). 직전 **6~12개월** 성과로 구분, 단기 반전 회피 위해 **최근 1개월(21일) 제외**. ★부록 A 정의는 T = 504 거래일(약 2년) 반감기 126일 — 본문 '6~12개월'과 다름(아래 표 참조, 지수가중 반감기 126일이 실효 창을 6~12개월로 만든다는 뜻으로 읽힘(?) — 원문 해명 없음).
- **Size**: 대형 vs 소형 수익 차. log(시가총액).
- **Earnings Yield**: 가장 중요한 기술자 = 애널리스트 12개월 선행 E/P.
- **Residual Volatility**: (a) 일별 초과수익 변동성 (b) 일별 잔차수익 변동성 (c) 최근 12개월 누적 범위. Beta 와 공선성이 높아 Beta 에 대해 직교화(Menchero 2010).
- **Growth**: 가장 중요한 기술자 = 애널리스트 장기 이익성장 예측. 그 밖에 직전 5년 매출 · 이익 성장.
- **Dividend Yield**: 직전 12개월 배당 ÷ 현재 가격.
- **Book-to-Price**: 최근 공시 보통주 장부가치 ÷ 현재 시가총액.
- **Leverage**: 시장 레버리지 · 장부 레버리지 · 부채/자산.
- **Liquidity**: 최근 창에서 거래된 주식 수의 총 발행주식 대비 비율.
- **Non-linear Size(NLS)**: 시총 스펙트럼에 걸친 Size 보상의 비선형성. 원 기술자 = Size 노출의 세제곱, Size 에 대해 직교화(모형 적합도에 영향 없음, 공선성 혼란만 줄이고 Size 의미 보존). 대략 "중형주 롱 · 소형주와 대형주 숏" 바벨 포트 위험.
- **Non-linear Beta(NLB)**: Beta 보상의 비선형성. Beta 를 세제곱 후 Beta 에 대해 직교화. 대략 "평균 베타(≈1) 롱 · 평균에서 크게 벗어난 베타 숏" 바벨 포트 위험.

### 4-3. 부록 A — 기술자 정의 전부

| 팩터 | 정의(가중치) | 기술자 | 식 · 창 · 반감기 · 시차 | 직교화 |
|---|---|---|---|---|
| Beta | 1.0·BETA | BETA (β) | r_t − r_ft = α + β·R_t + e_t (A1). r_t = 종목 수익, r_ft = 무위험 수익, R_t = **시가총액 가중 ESTU 초과수익**. 창 = 직전 **252 거래일**, 반감기 **63 거래일**(지수가중 회귀) | 없음 |
| Momentum | 1.0·RSTR | RSTR (Relative strength) | RSTR = Σ_{t=L}^{T+L} w_t·[ln(1+r_t) − ln(1+r_ft)] (A2). **T = 504 거래일**, **시차 L = 21 거래일**, w_t = 반감기 **126 거래일** 지수 가중. 즉 초과 로그수익의 지수가중 합 | 없음 |
| Size | 1.0·LNCAP | LNCAP | ln(기업 **총** 시가총액) | 없음 |
| Earnings Yield | 0.75·EPFWD + 0.15·CETOP + 0.10·ETOP | EPFWD (예측 E/P) | 12개월 선행 이익 ÷ 현재 시가총액. 선행 이익 = 당해 회계연도와 다음 회계연도 애널리스트 평균 예측 이익의 가중평균(가중 방식 원문에 없음) | 없음 |
| | | CETOP (현금이익/가격) | 직전 12개월 현금이익 ÷ 현재 **가격**(현금이익 정의 원문에 없음) | |
| | | ETOP (실적 E/P) | 직전 12개월 이익 ÷ 현재 시가총액. 직전 12개월 이익 = 최근 공시 회계연도 이익 + (당기 중간기 누적 − 전년 동기 중간기 누적) | |
| Residual Volatility | 0.75·DASTD + 0.15·CMRA + 0.10·HSIGMA | DASTD (일별 표준편차) | 일별 **초과**수익 변동성, 직전 **252 거래일**, 반감기 **42 거래일** | **Beta 에 대해 직교화**(공선성 감소) — 방식은 부록에 "orthogonalized to Beta" 만 있음(회귀 가중 여부 원문에 없음) |
| | | CMRA (누적 범위) | Z(T) = Σ_{τ=1}^{T} [ln(1+r_τ) − ln(1+r_fτ)] (A3), r_τ = 월 τ 의 종목 수익(**21 거래일 복리**), 월 = 직전 21 거래일 단위. CMRA = ln(1+Z_max) − ln(1+Z_min) (A4), Z_max = max{Z(T)}, Z_min = min{Z(T)}, **T = 1,…,12**(개월). 가중 없음 | |
| | | HSIGMA (σ) | σ = std(e_t) (A5), e_t = A1 회귀 잔차. 직전 **252 거래일**, 반감기 **63 거래일** | |
| Growth | 0.70·EGRLF + 0.20·EGRO + 0.10·SGRO | EGRLF | 애널리스트 장기(3~5년) 이익성장 예측 | 없음 |
| | | EGRO (직전 5년 이익성장) | 직전 **5개 회계연도** 연간 EPS 를 시간에 회귀 → 기울기 ÷ 평균 연간 EPS | |
| | | SGRO (직전 5년 매출성장) | 직전 5개 회계연도 연간 주당매출을 시간에 회귀 → 기울기 ÷ 평균 연간 주당매출 | |
| Dividend Yield | 1.0·YILD | YILD | 직전 12개월 주당배당 ÷ 현재 가격 | 없음 |
| Book-to-Price | 1.0·BTOP | BTOP | 최근 공시 보통주 장부가치 ÷ 현재 시가총액 | 없음 |
| Leverage | 0.75·MLEV + 0.15·DTOA + 0.10·BLEV | MLEV (시장 레버리지) | MLEV = (ME + PE + LD) / ME (A6). ME = 직전 거래일 보통주 시가, PE = 최근 우선주 장부가, LD = 최근 장기부채 장부가 | 없음 |
| | | DTOA (부채/자산) | DTOA = TD / TA (A7). TD = 총부채 장부가(장기부채 + 유동부채), TA = 최근 총자산 장부가 | |
| | | BLEV (장부 레버리지) | BLEV = (BE + PE + LD) / BE (A8). BE = 최근 보통주 장부가 | |
| Liquidity | 0.35·STOM + 0.35·STOQ + 0.30·STOA | STOM (1개월 회전율) | STOM = ln( Σ_{t=1}^{21} V_t / S_t ) (A9). V_t = 일 거래량, S_t = 발행주식수. 직전 **21 거래일** | 없음 |
| | | STOQ (3개월 평균 회전율) | STOQ = ln[ (1/T)·Σ_{τ=1}^{T} exp(STOM_τ) ] (A10), STOM_τ = 월 τ(21 거래일)의 회전율, **T = 3** 개월 | |
| | | STOA (12개월 평균 회전율) | STOA = ln[ (1/T)·Σ_{τ=1}^{T} exp(STOM_τ) ] (A11), **T = 12** 개월 | |
| Non-linear Size | 1.0·NLSIZE | NLSIZE (Size 세제곱) | 아래 4-4 | Size 에 대해(회귀 가중 기반) |
| Non-linear Beta | 1.0·NLBETA | NLBETA (Beta 세제곱) | 아래 4-4 | Beta 에 대해(회귀 가중 기반) |

부록에 없는 것: 각 기술자의 결측 시 가중치 재배분 · 재무 자료 공시 시차(PIT) · 애널리스트 자료 출처 · 무위험 수익 원천 · CETOP 의 '현금이익' 정의 · 부채의 '유동부채' 범위 정의 세부.

### 4-4. ★Non-linear Size · Non-linear Beta 구성 절차 (부록 A 55쪽 원문 순서 그대로)

**NLSIZE** (정의 1.0·NLSIZE, "Cube of Size")
1. **표준화된** Size 노출(= log 시가총액, 4-1 표준화: 시총가중 평균 0 · 동일가중 표준편차 1)을 **세제곱**한다.
2. 그 결과를 Size 팩터에 대해 **회귀 가중 기반(regression-weighted basis)으로 직교화**한다. (회귀 가중 = 시가총액 제곱근 — 부록 B · 4.3절.) 즉 세제곱값을 Size 에 가중 회귀하고 잔차를 취하는 것으로 읽힘(절편 포함 여부 원문에 없음).
3. 마지막으로 **윈저화하고 표준화**한다. (윈저화 문턱 원문에 없음. 표준화는 4-1 규칙으로 읽힘 (?).)
- 순서 주의: 세제곱 → 직교화 → 윈저화 → 표준화. (윈저화가 직교화 **뒤**.)
- 해석(3.4절): 중형주 롱 · 소형 · 대형주 숏 바벨. 직교화는 적합도에 영향 없음.

**NLBETA** (정의 1.0·NLBETA, "Cube of Beta")
1. **표준화된** Beta 노출을 **세제곱**한다.
2. Beta 팩터에 대해 **회귀 가중 기반으로 직교화**한다.
3. **윈저화하고 표준화**한다.
- 해석(3.4절): 평균 베타(≈1) 종목 롱 · 평균에서 크게 벗어난 베타 종목 숏 바벨.

---

## 5. 표 4.1 · 표 4.2 (22~26쪽)

### 5-1. 4.1절 설명
- 유의성 척도 = 팩터 수익의 t 값. 정규 가정에서 |t| > 2 = 95% 유의(순수 잡음이면 약 5% 확률).
- t 값은 **월별** 횡단면 회귀로 계산(공분산용은 일별) — 모델의 예측 지평에서의 설명력이 중요하기 때문.
- 국가 팩터: 평균 |t| 15.33, 거의 96% 의 달에 유의. 강한 업종은 에너지 · IT 에 몰림. 전체 팩터 평균 유의 비율 40.2%.
- 수익 · 변동성 · 샤프 · 상관은 **일별** 팩터 수익으로 계산 · 연율화. 국가 팩터: 연 5.57%, 변동성 20.25%, 샤프 0.28. 좋은 업종 = 에너지 · 보건의료 · IT, 나쁜 업종 = 산업재 · 금융 · 유틸리티. 에너지 팩터는 변동성 큼, 필수소비재는 낮음.
- ESTU 와 상관: 국가 팩터 0.999(사실상 같음). 업종 팩터(달러 중립)는 대체로 작음; 필수소비재 · 보건의료 · 유틸리티는 약한 음, IT 는 약한 양. 전기간 평균이며 국면별로는 크게 다를 수 있음.

### 5-2. 표 4.1 — 국가 · 업종 팩터 통계 (23~24쪽)
캡션: 처음 두 열 = 월별 횡단면 회귀 t 값, 나머지 네 열 = 일별 팩터 수익. 기간 1995-06-30 ~ 2011-05-31(191개월). 단위: 수익 · 변동성 = 연율 %, 상관 = ESTU 와의 상관.

| 팩터 | 평균 \|t\| | \|t\|>2 비율(%) | 연율 수익(%) | 연율 변동성(%) | 샤프 | ESTU 상관 |
|---|---|---|---|---|---|---|
| Country Factor | 15.33 | 95.8 | 5.57 | 20.25 | 0.28 | 0.999 |
| Oil and Gas Drilling | 3.14 | 60.4 | 5.12 | 32.96 | 0.16 | -0.04 |
| Oil and Gas Equipment and Services | 3.44 | 60.9 | 4.08 | 27.68 | 0.15 | -0.03 |
| Oil Gas and Consumable Fuels | 2.56 | 51.6 | 0.88 | 17.76 | 0.05 | -0.05 |
| Oil and Gas Exploration and Production | 4.06 | 70.3 | 2.38 | 22.17 | 0.11 | -0.04 |
| Chemicals | 1.71 | 32.8 | -0.88 | 15.64 | -0.06 | 0.00 |
| Specialty Chemicals | 1.16 | 18.2 | -5.69 | 10.85 | -0.52 | 0.08 |
| Construction Materials | 0.94 | 10.4 | -6.16 | 20.09 | -0.31 | 0.02 |
| Containers and Packaging | 1.18 | 18.8 | -5.26 | 14.93 | -0.35 | 0.00 |
| Aluminum Steel | 2.24 | 44.3 | -7.78 | 21.20 | -0.37 | 0.07 |
| Precious Metals Gold Mining | 2.20 | 44.8 | 6.40 | 26.53 | 0.24 | -0.10 |
| Paper and Forest Products | 1.58 | 30.7 | -8.08 | 20.78 | -0.39 | 0.04 |
| Aerospace and Defense | 1.97 | 40.6 | -1.47 | 14.33 | -0.10 | -0.09 |
| Building Products | 1.16 | 15.6 | -6.31 | 14.57 | -0.43 | 0.04 |
| Construction and Engineering | 1.27 | 19.3 | -2.01 | 15.78 | -0.13 | 0.04 |
| Electrical Equipment | 1.23 | 20.3 | -2.21 | 10.51 | -0.21 | 0.14 |
| Industrial Conglomerates | 1.13 | 16.1 | -7.50 | 32.93 | -0.23 | 0.01 |
| Construction and Farm Machinery | 1.60 | 27.6 | -0.16 | 16.58 | -0.01 | 0.08 |
| Industrial Machinery | 1.42 | 26.0 | -2.95 | 9.67 | -0.30 | 0.12 |
| Trading Companies and Distributors | 1.11 | 12.5 | -6.36 | 11.93 | -0.53 | 0.04 |
| Commercial and Professional Services | 1.52 | 27.6 | -2.91 | 6.27 | -0.46 | -0.05 |
| Transportation Air Freight and Marine | 1.25 | 21.4 | -1.03 | 13.85 | -0.07 | 0.03 |
| Airlines | 2.44 | 51.6 | -10.14 | 32.84 | -0.31 | 0.00 |
| Road and Rail | 1.63 | 32.8 | -0.02 | 14.46 | 0.00 | 0.03 |
| Automobiles and Components | 2.07 | 41.7 | -13.48 | 16.49 | -0.82 | 0.04 |
| Household Durables (non-Homebuilding) | 1.20 | 16.1 | -5.72 | 11.62 | -0.49 | 0.03 |
| Homebuilding | 2.23 | 47.4 | -2.35 | 25.87 | -0.09 | 0.06 |
| Leisure Products Textiles Apparel and Luxury | 1.65 | 31.3 | -5.06 | 11.21 | -0.45 | -0.01 |
| Hotels Leisure and Consumer Services | 2.06 | 46.4 | -3.45 | 12.57 | -0.27 | -0.04 |
| Restaurants | 1.87 | 39.1 | -0.68 | 13.21 | -0.05 | -0.07 |
| Media | 2.19 | 46.4 | -0.57 | 8.88 | -0.06 | -0.05 |
| Distributors Multiline Retail | 2.17 | 48.4 | -1.23 | 16.93 | -0.07 | -0.02 |
| Internet and Catalog Retail | 1.93 | 38.0 | 1.51 | 22.03 | 0.07 | 0.01 |
| Apparel and Textiles | 2.52 | 52.6 | 3.03 | 18.64 | 0.16 | -0.01 |
| Specialty Retail | 2.11 | 48.4 | 3.43 | 17.39 | 0.20 | 0.02 |
| Specialty Stores | 1.73 | 30.2 | -6.16 | 13.71 | -0.45 | 0.00 |
| Food and Staples Retailing | 1.70 | 33.9 | -1.97 | 11.55 | -0.17 | -0.16 |
| Beverages Tobacco | 1.61 | 30.7 | 3.22 | 12.21 | 0.26 | -0.23 |
| Food Products | 1.58 | 31.3 | -0.52 | 9.40 | -0.06 | -0.23 |
| Household and Personal Products | 1.46 | 26.6 | 1.78 | 12.33 | 0.14 | -0.14 |
| Health Care Equipment and Technology | 1.81 | 37.5 | 3.17 | 9.28 | 0.34 | -0.17 |
| Health Care Providers (non-HMO) | 2.19 | 43.8 | -0.21 | 12.06 | -0.02 | -0.15 |
| Managed Health Care | 2.40 | 50.0 | 2.41 | 22.29 | 0.11 | -0.10 |
| Biotechnology Life Sciences | 3.08 | 56.3 | 11.61 | 17.20 | 0.67 | -0.04 |
| Pharmaceuticals | 2.54 | 54.7 | 5.67 | 12.27 | 0.46 | -0.14 |
| Banks | 3.51 | 62.5 | -6.00 | 13.47 | -0.45 | 0.08 |
| Diversified Financials | 2.64 | 54.7 | 0.02 | 12.66 | 0.00 | 0.19 |
| Insurance Brokers and Reinsurance | 1.95 | 41.1 | -4.21 | 10.29 | -0.41 | -0.04 |
| Life Health and Multi-line Insurance | 1.54 | 29.2 | -10.12 | 18.76 | -0.54 | 0.14 |
| Real Estate | 2.23 | 44.8 | -4.56 | 13.64 | -0.33 | 0.05 |
| Internet Software and IT Services | 2.18 | 44.3 | -0.74 | 12.03 | -0.06 | 0.08 |
| Software | 2.50 | 51.6 | 5.24 | 11.62 | 0.45 | 0.09 |
| Communications Equipment | 2.83 | 56.8 | 5.34 | 14.37 | 0.37 | 0.10 |
| Computers Electronics | 2.90 | 56.8 | 2.15 | 11.56 | 0.19 | 0.08 |
| Semiconductor Equipment | 3.12 | 60.4 | -0.30 | 28.25 | -0.01 | 0.10 |
| Semiconductors | 4.14 | 71.9 | 5.94 | 21.51 | 0.28 | 0.09 |
| Diversified Telecommunication Services | 2.30 | 46.9 | -4.74 | 14.89 | -0.32 | -0.06 |
| Wireless Telecommunication Services | 1.89 | 35.4 | 3.79 | 19.41 | 0.20 | -0.04 |
| Electric Utilities | 2.34 | 51.0 | -5.53 | 14.06 | -0.39 | -0.15 |
| Gas Utilities | 1.15 | 17.2 | -5.48 | 11.65 | -0.47 | -0.07 |
| Multi-Utilities Water Utilities Power | 1.61 | 28.1 | -9.87 | 16.29 | -0.61 | -0.12 |
| **Average** | **2.27** | **40.2** | (빈칸) | **16.33** | (빈칸) | (빈칸) |

(Average 행의 16.33 이 변동성 열임을 쪽 그림으로 확인. 수익 · 샤프 · 상관 열 평균은 원문에 없음.)

### 5-3. 4.2절 설명
- 표본을 두 하위기간으로 나눔. 스타일 팩터 유의성은 전체적으로 업종보다 약간 큼.
- 변동성 · t 값 기준 가장 강한 팩터 = 대체로 **Beta · Momentum · Size**; Earnings Yield · Residual Volatility · Non-linear Size 도 상당히 강함.
- 1기(1995-06-30~2003-06-30): Momentum · Earnings Yield 매우 좋음, Residual Volatility · Size 나쁨. 2기(2003-06-30~2011-05-31)에도 상대 성과 지속, 크기는 작아짐. 1기(인터넷 버블 포함) Growth 의 유의성이 높음.
- ESTU 상관: 대체로 작음. 예외 Beta(1기 0.77 · 2기 0.90). Residual Volatility 도 양쪽 기간 큰 양의 상관.
- **팩터 안정 계수** = 한 달에서 다음 달로 팩터 노출의 횡단면 상관. 경험칙: **0.80 미만 = 모델 편입에 너무 불안정, 0.90 초과 = 바람직**. 스타일 평균 0.96(두 기간 모두).
- **VIF**(분산 팽창 계수): 팩터 간 공선성. 엄격한 상한은 없지만 **5 초과 = 문제**. USE4 스타일은 두 기간 모두 5 미만.
- 안정 계수와 VIF 는 **월별 자료 · 시가총액 제곱근 가중**으로 계산(표 캡션).

### 5-4. 표 4.2 — 스타일 팩터 통계 (26쪽)
캡션: 처음 두 열 = 월별 횡단면 회귀 t 값, 다음 네 열 = 일별 팩터 수익, 안정 계수 · VIF = 월별 · 시총 제곱근 가중. 전체 191개월을 두 하위기간으로 나눔. 단위: 수익 · 변동성 = 연율 %.

**A. 1995-06-30 ~ 2003-06-30 (96개월)**

| 팩터 | 평균 \|t\| | \|t\|>2 % | 연율 수익 | 연율 변동성 | 샤프 | ESTU 상관 | 안정 계수 | VIF |
|---|---|---|---|---|---|---|---|---|
| Beta | 3.96 | 64.9 | -1.34 | 8.95 | -0.15 | 0.77 | 0.96 | 3.74 |
| Momentum | 4.33 | 71.1 | 8.34 | 4.46 | 1.87 | 0.04 | 0.91 | 2.14 |
| Size | 3.60 | 70.1 | -4.06 | 3.42 | -1.19 | 0.27 | 1.00 | 4.38 |
| Earnings Yield | 2.86 | 55.7 | 6.68 | 3.05 | 2.19 | -0.17 | 0.97 | 2.21 |
| Residual Volatility | 3.06 | 57.7 | -6.08 | 4.16 | -1.46 | 0.44 | 0.96 | 3.50 |
| Growth | 2.17 | 50.5 | 1.34 | 2.51 | 0.53 | 0.23 | 0.98 | 2.19 |
| Dividend Yield | 1.37 | 23.7 | 1.53 | 2.08 | 0.74 | 0.12 | 0.99 | 2.93 |
| Book-to-price | 1.33 | 21.6 | 0.58 | 1.99 | 0.29 | -0.01 | 0.97 | 2.29 |
| Leverage | 1.46 | 27.8 | -0.53 | 1.66 | -0.32 | -0.01 | 0.99 | 1.72 |
| Liquidity | 1.91 | 36.1 | 2.91 | 2.89 | 1.00 | 0.33 | 0.97 | 2.48 |
| Non-linear Size | 2.23 | 52.6 | -0.12 | 3.40 | -0.03 | 0.21 | 0.98 | 1.42 |
| Non-linear Beta | 1.90 | 32.0 | -0.02 | 2.50 | -0.01 | 0.06 | 0.85 | 1.33 |
| **Average** | **2.52** | **46.99** | **0.77** | **3.42** | **0.29** | **0.19** | **0.96** | **2.53** |

**B. 2003-06-30 ~ 2011-05-31 (95개월)**

| 팩터 | 평균 \|t\| | \|t\|>2 % | 연율 수익 | 연율 변동성 | 샤프 | ESTU 상관 | 안정 계수 | VIF |
|---|---|---|---|---|---|---|---|---|
| Beta | 4.02 | 66.3 | -0.35 | 8.36 | -0.04 | 0.90 | 0.97 | 3.46 |
| Momentum | 3.50 | 64.2 | 1.12 | 3.69 | 0.30 | -0.18 | 0.89 | 1.88 |
| Size | 2.85 | 53.7 | -2.29 | 3.09 | -0.74 | 0.06 | 1.00 | 3.56 |
| Earnings Yield | 2.11 | 44.2 | 1.95 | 2.17 | 0.90 | 0.04 | 0.97 | 1.90 |
| Residual Volatility | 2.35 | 45.3 | -2.69 | 3.42 | -0.79 | 0.50 | 0.95 | 2.88 |
| Growth | 1.53 | 21.1 | 0.53 | 1.36 | 0.39 | 0.00 | 0.95 | 1.77 |
| Dividend Yield | 1.59 | 30.5 | -0.09 | 1.77 | -0.05 | 0.10 | 0.99 | 2.64 |
| Book-to-price | 1.70 | 33.7 | -0.06 | 1.88 | -0.03 | 0.19 | 0.98 | 1.90 |
| Leverage | 1.92 | 34.7 | -0.87 | 2.07 | -0.42 | 0.10 | 0.99 | 1.90 |
| Liquidity | 1.47 | 28.4 | 0.36 | 2.09 | 0.17 | -0.11 | 0.98 | 2.30 |
| Non-linear Size | 2.00 | 47.4 | 1.37 | 2.70 | 0.51 | 0.02 | 0.99 | 1.52 |
| Non-linear Beta | 1.59 | 35.8 | -0.33 | 1.53 | -0.22 | 0.05 | 0.91 | 1.47 |
| **Average** | **2.22** | **42.11** | **-0.11** | **2.84** | **0.00** | **0.14** | **0.96** | **2.26** |

판독 메모: 안정 계수 최저 = Non-linear Beta(1기 0.85) · Momentum(2기 0.89) — 둘 다 0.80 은 넘음. VIF 최고 = Size(1기 4.38). 전기간(191개월) 통합 수치는 원문에 없음.

---

## 6. 설명력 (4.3절 27~28쪽 · 그림 4.1 · 표 4.3 · 부록 B)

### 6-1. 본문
- R² 는 회귀 가중 · 추정 유니버스 · 기간에 민감 → 모델 간 비교 시 셋을 통제해야 함.
- 그림 4.1 비교는 같은 ESTU(MSCI USA IMI) · 같은 가중(시가총액 제곱근), 월별 횡단면 회귀.
- 두 모델 R² 는 1990년대 중반 30% 약간 아래 → 2009년 50% 약간 위.
- USE4 가 USE3 보다 평균 **66bp** 높음. 지속적이며 USE3 가 약간 앞선 때는 2004 · 2009 두 짧은 시기뿐.

### 6-2. 그림 4.1 (27쪽) — "Trailing 12-month total R-squared for USE4 and USE3 models"
- 보여 주는 것: 월별 횡단면 회귀 R² 의 직전 12개월 평균(USE4 실선 · USE3 점선, 왼축 −10~60%), 둘의 차이(오른축 −1~6%p, 붉은 점선).
- 판독: 1995~96 약 26~28% → 1999 약 38% → 2002~03 약 46~48% 고점 → 2006~07 약 32~35% → 2009~10 약 50~51% 고점 → 2011 약 42%. 차이는 대부분 약 +0.3~+1.6%p, 최대 약 +1.6%p(2002 무렵), 음수 구간 약 −0.2%p(2004) · 약 −0.3%p(2009 무렵).

### 6-3. 표 4.3 — USE4 대 USE3 설명력 (28쪽)
캡션: 1995-06-30 ~ 2011-05-31(191개월) 월별 R² 평균.

| 업종 | 스타일 | R² (%) | ΔR² (bp) |
|---|---|---|---|
| USE3 | USE3 | 37.25 | 0 |
| USE4 | USE3 | 37.81 | 56 |
| USE4 | USE4 | 37.91 | 66 |

→ 업종 교체로 +56bp, 스타일 교체로 추가 +10bp. 개선 대부분은 USE4 업종 덕.

### 6-4. 부록 B — RMS 수익 분해 식 (56쪽, 그림으로 재확인)
- (B1) r_n = Σ_k X_nk·f_k + u_n — r_n = 종목 n 의 초과수익, X_nk = 종목 n 의 팩터 k 노출, f_k = 매기 횡단면 회귀로 추정한 팩터 수익, u_n = 고유수익. 고유수익은 서로 · 팩터와 무상관 가정.
- (B2) 총 R²: R²_T = 1 − (Σ_n v_n·u_n²) / (Σ_n v_n·r_n²), v_n = 종목 n 의 회귀 가중(**시가총액 제곱근에 비례**).
- (B3) RMS = sqrt( Σ_n v_n·r_n² ) — 0 수익 기준 횡단면 분산. (v_n 의 합이 1 로 정규화되는지는 원문에 명시 없음 — RMS 가 수익 단위가 되려면 합 1 이어야 함(?).)
- (B4) 횡단면 x-sigma-rho 공식: RMS = Σ_k f_k·σ(X_k)·ρ(X_k, r) + σ(u)·ρ(u, r). σ(X_k) = 팩터 k 노출의 RMS 분산, ρ(X_k, r) = 팩터 k 노출과 자산 수익의 횡단면 상관, 마지막 항 = 고유 기여. (Menchero & Morozov 2011)
- CSV(횡단면 변동성)는 평균 기준 분산 — 국가 팩터 기여 0. RMS 는 0 기준 — 국가 팩터 기여 있음(4.4절).

---

## 7. 횡단면 분산(4.4) · 고유 위험(4.5)

### 7-1. 그림 4.2 (29쪽) — "Total monthly cross-sectional dispersion as measured by root mean square (RMS) return. Also displayed are the stock-specific and factor contributions." (12개월 이동평균)
- 본문 수치: 인터넷 버블 월 RMS 고점 **18%**, 금융위기 고점 **17%**. 버블 고점은 넓게(수년), 위기 고점은 짧게. 대부분 기간 고유 기여가 지배, 금융위기 때만 팩터가 주동인.
- 판독: Total 1995 약 8.5% → 2000~01 약 18.5% 고점 → 2007 약 7% 저점 → 2009 약 17% → 2011 약 9%. Specific 약 6% → 2000~01 약 11% 고점 → 2006 약 4.7% → 2009 약 7.5~8%. Factors 약 2.3% → 2001 약 8% → 2007 약 2% → 2009 약 9.3% 고점(이때 Specific 을 넘음) → 2011 약 4.3%.

### 7-2. 그림 4.3 (30쪽) — 국가 · 업종 · 스타일의 RMS 기여 (12개월 이동평균)
- 본문: 셋 다 비슷하게 중요, 시기별로 지배 요인이 바뀜. 국가 = 1997~1999 · 2009~2011 최대, 업종 = 2000 · 2004~2008 지배, 스타일 = 인터넷 버블 직후 지배.
- 판독: Country 고점 약 4.6%(2009~10), 약 2.7%(1999), 약 2.9%(2003 무렵); Styles 고점 약 3.8%(2001~02); Industries 고점 약 3.1%(2000~01), 2004~08 약 1.2~1.5%; 2007 무렵 셋 다 약 0.5~1%.

### 7-3. 그림 4.4 (31쪽) — Beta · Momentum · Size 의 RMS 기여
- 본문: Beta 가 2001~2003 큰 고점. Size 는 1996~1998 최대 기여자였지만 월 25bp 미만. Momentum 은 2008 폭락 뒤 반등기 2009 에 지배.
- 판독: Beta 고점 약 1.6%(2001~02), 2009~11 약 0.6~0.7%; Momentum 고점 약 0.85%(2009~10), 약 0.6%(2001~02); Size 약 0.2~0.25%(1996~98), 약 0.45%(2002 무렵 (?)).

### 7-4. 4.5절 · 그림 4.5 (32쪽) — "Histogram of USE4S specific-risk forecasts as of 31-May-2011"
- 본문: 대부분 10~45%, 가장 변동 큰 종목 60% 초과. 평균 약 **25%**.
- 판독: 분포는 약 8% 부터 시작, 최빈 구간 약 17~18%(도수 약 235), 오른쪽 꼬리 약 65%(도수 약 12). 도수 축 0~250. 히스토그램 종목 총수 원문에 없음.

### 7-5. 그림 4.6 (33쪽) — "Specific risk levels versus time for USE4S" (5분위 · 평균 · 95분위)
- 본문: 5분위 약 10~25%(최대 2008 말) · 평균 25~65%(고점 2008 말, 버블기도 비슷) · 95분위 2007 저점 40% ~ 버블 · 위기 120% 초과.
- 판독: 95분위 고점 약 123%(2000~01) · 약 124%(2008 말); 평균 고점 약 64%(2000) · 약 66%(2008 말), 2004~07 약 22~25%; 5분위 고점 약 30%(2008 말 (?)) — 본문 '10~25%'와 그림이 약간 어긋남(그림은 25% 위로 보임 (?)), 1990년대 약 13~15%, 2011 약 11%.

---

## 8. 예측 정확도 (5장 34~49쪽 · 그림 5.1~5.13 · 표 5.1 · 부록 C)

### 8-1. 시험 방법 (5.1절)
- 편향 통계(bias statistic) = 실현 위험 ÷ 예측 위험의 표본외 척도. 이상값 1. 95% 신뢰구간 밖이면 예측 부정확으로 판정.
- 두꺼운 꼬리면 표준 신뢰구간 안 비율이 95% 보다 작다.
- 표본 191개월(1995-07 ~ 2011-05). 긴 창은 과대 · 과소 예측이 상쇄될 수 있어 **12개월 롤링 창**에 집중.
- 네 척도: 롤링 12개월 편향 통계의 **평균**, **5분위(P5)** · **95분위(P95)**, **MRAD**. 정규 · 완벽 예측이면 P5 ≈ **0.66**, P95 ≈ **1.34**, MRAD 기대값 **0.17**.
- 첨도: USE4S 월별 표준화 순수 팩터 수익 첨도 약 **4.0**(16년), 무작위 액티브 포트(그림 5.4) 평균 첨도 약 **3.5**. 첨도 3.5~4.0 → 완벽 예측의 MRAD 약 **0.19**. 예: 하한 0.19 일 때 MRAD 0.23 → 0.21 = 초과 MRAD **50%** 감소.
- MRAD 는 통계량이라 우연히 0.17 아래로 갈 수 있지만, 다양한 포트 집합이면 지속적으로 크게 밑돌기 어렵다.
- 시뮬레이션: 100개 수익 집합 × 191개월. ① 표준정규 ② 표준편차 1 · 첨도 4 의 t 분포. 예측 변동성 = 1(완벽).
- 롤링 12개월 수치는 1996-07 부터 그림.

### 8-2. 부록 C — 편향 통계 식 (57~58쪽, 그림으로 재확인)
- (C1) b_nt = R_nt / σ_nt — R_nt = 포트 n 의 기간 t 수익, σ_nt = 기간 **시작 시점** 변동성 예측. 완벽 예측이면 b 의 표준편차 기대 1.
- (C2) B_n = sqrt[ (1/(T−1))·Σ_{t=1}^{T} (b_nt − b̄_n)² ] — 표준화 수익의 실현 표준편차(평균 차감 · T−1 분모). T = 관측 창 기간 수.
- (C3) 정규 · 완벽 예측 · 큰 T 에서 약 95% 가 B_n ∈ [1 − sqrt(2/T), 1 + sqrt(2/T)]. 밖이면 '예측 정확' 귀무가설 기각.
- 첨도 5 · T = 120 이면 구간 안 비율 **86%** 뿐.
- (C4) 롤링 12개월: B_n^τ = sqrt[ (1/11)·Σ_{t=τ}^{τ+11} (b_nt − b̄_n)² ], τ = 12개월 창의 첫 달. 한 달씩 전진, 포트마다 T − 11 개 겹치는 창.
- (C5) B̄^τ = (1/N)·Σ_n B_n^τ — N 개 포트 평균.
- B^τ(5%) · B^τ(95%) = 시점별 롤링 편향 통계의 5 · 95 분위; 정규 · 완벽이면 0.66 · 1.34 중심.
- (C6) MRAD^τ = (1/N)·Σ_n |B_n^τ − 1|. 정규 · 완벽이면 기대값 0.17.

### 8-3. 그림 C1 (59쪽) — 신뢰구간 1 ± sqrt(2/T) 안 관측 비율 대 T
- 정규(k=3) · t 분포 k=5 · k=10, 표준편차 1. 판독: k=3 은 T≈5 에서 약 93.5% → T≈20 이후 약 95~95.5%; k=5 는 약 91% → T=140 무렵 약 86%(본문: T=120 에서 86%); k=10 은 약 89.5% → T=140 무렵 약 77.5%.

### 8-4. 그림 C2 (60쪽) — 완벽 예측의 12개월 MRAD 대 첨도 (t 분포 시뮬레이션)
- 판독: k=3 0.17 · k≈3.7 약 0.19 · k=4 약 0.194 · k=5 약 0.209 · k=6 약 0.218 · k=7 약 0.224 · k=8 약 0.229 · k=10 약 0.236. 본문: 3.5~4.0 에서 약 0.19.

### 8-5. 시험 포트폴리오 종류 (5.2절)

| 그림 | 모델 | 포트 종류 | 구성 |
|---|---|---|---|
| 5.1 | 시뮬레이션 | 완벽 예측 기준선 | 100개 포트, 왼쪽 정규 · 오른쪽 t(첨도 4) |
| 5.2 / 5.3 | S / L | 순수 팩터(Pure Factors) | 각 모델의 순수 팩터. USE3 대부분은 순롱 업종, USE4 업종은 달러 중립 → 엄밀한 동일 조건 비교 아님 |
| 5.4 / 5.5 | S / L | 무작위 액티브 100개 | 무작위 500종목 시가총액 가중 롱 − 시가총액 가중 USE4 ESTU 숏(달러 중립). 두 모델 같은 포트 → 동일 조건 비교 |
| 5.6 / 5.7 | S / L | 팩터 틸트 롱온리 163개 | USE3 업종 55 + USE4 업종 60 (주 업종 노출 종목 시총가중) + USE3 스타일 12 · USE4 스타일 12 의 상위 · 하위 5분위 시총가중(각 2개) = 55 + 60 + 24 + 24 = 163 |
| 5.8 / 5.9 | S / L | 팩터 틸트 액티브 163개 | 5.6 의 163개 롱 − USE4 ESTU 숏 |
| 5.10 / 5.11 | S / L | 최적화 스타일 24개 | 각 모델 12 스타일을 '알파 신호'로 단위 알파 제약(alpha = 1) 아래 최소 위험 포트, 무작위 500종목 두 번 추출 → 12 × 2 = 24 |
| 5.12 / 5.13 | S / L | 고유위험 | USE4 ESTU 전 종목의 고유수익, 시가총액 가중 집계. USE3 는 S · L 이 같은 고유위험 예측 사용 |

### 8-6. 그림별 내용 (모두 두 판넬: 왼쪽 USE3 · 오른쪽 USE4, 롤링 12개월 P95(적) · 평균(청) · P5(녹) · MRAD(흑), 점선 = 이상 위치 1.34 · 1.0 · 0.66 · 0.17, 축 0~2.0, 1996~2011)
- **그림 5.1 (36쪽)** 완벽 예측: 정규판은 선이 이상 위치 근처(MRAD ≈ 0.17 중심). 첨도 4 판: P5 평균 **0.61**, P95 평균 **1.40**, MRAD 약 **0.19**. 선의 잡음은 포트 수에 의존.
- **그림 5.2 (37쪽)** S 순수 팩터: USE4S 가 더 안정 · 이상 위치에 가까움. 둘 다 2010 초 과대 예측, USE4S 평균이 1 에 훨씬 가까움. USE3S 는 2004 과대 예측, USE4S 는 1 근처. USE3S 는 1998-08 러시아 디폴트에 급등(USE3 순롱 업종 탓), USE4S 엔 거의 없음. 판독: USE3S P95 고점 약 1.75(1998~99), 평균 약 1.37, MRAD 약 0.37(1998) · 약 0.36(2009~10), 2010 무렵 평균 약 0.6 (?); USE4S MRAD 약 0.2~0.25 로 평탄.
- **그림 5.3 (38쪽)** L 순수 팩터: USE3L 2003~2008 과대 예측; USE4L 도 일부 과대지만 폭 작음. 둘 다 2008 위기 진입 과소 · 진정기 과대. USE4S(5.2)가 USE4L 보다 일관되게 이상값에 가까움. 판독: USE3L P95 고점 약 1.93(1999), MRAD 약 0.48(1998~99) · 약 0.45(2008~09); USE4L P95 고점 약 1.87(2008), MRAD 약 0.36(2008~09) (?).
- **그림 5.4 (39쪽)** S 무작위 액티브: USE3S 는 대부분 기간 과대 예측(특히 2002~2005 · 2009 말~2011 중반). USE4S 는 평균 ≈ 1, MRAD 이상값 근처; 2009 말 과대 예측했으나 변동성 국면 조정이 2010 말까지 바로잡음. 판독: USE3S 평균 저점 약 0.65(2002~05 · 2010), MRAD 고점 약 0.33(2009~10); USE4S 평균 저점 약 0.6(2009~10), MRAD 고점 약 0.29.
- **그림 5.5 (40쪽)** L 무작위 액티브: USE3L 대부분 과대 예측. USE4L 은 대체로 1 에 가까우나 2010 크게 과대 예측, 2011-05 에 다시 1 근처. 판독: USE4L 평균 저점 약 0.35(2010), MRAD 고점 약 0.63(2010); USE3L MRAD 고점 약 0.33.
- **그림 5.6 (41쪽)** S 팩터 틸트 롱온리 163개: USE3S MRAD 의 세 특징 — ① 1998-08 러시아 디폴트(1998-07 말 정보로 예측 불가한 이상 사건) ② 2004 과대 예측(USE4 에는 거의 없음 = 변동성 국면 조정이 하락 추세 변동성에 빨리 맞춤) ③ 2010 과대 예측(USE4S 도 위기 직후 과대였으나 훨씬 작음). 판독: USE3S P95 고점 약 1.72(1998~99), MRAD 고점 약 0.4(1998) · 약 0.42(2004 (?)) · 약 0.37(2010); USE4S P95 고점 약 1.8(1998~99), MRAD 고점 약 0.37(1998).
- **그림 5.7 (42쪽)** L 팩터 틸트 롱온리: USE3L 2004~2008 크게 과대 예측, 2008 위기 진입 과소 → 진정 과대. USE4L 은 같은 모양이지만 편향 크기가 훨씬 작음(변동성 국면 조정). 판독: USE3L P95 고점 약 1.88(1999), MRAD 고점 약 0.52(1998~99) · 약 0.5(2009 (?)); USE4L P95 고점 약 1.9(1998~99), MRAD 고점 약 0.48(1998~99).
- **그림 5.8 (43쪽)** S 팩터 틸트 액티브 163개: USE3S 버블기 크게 과소 예측 → 2003~04 과대 → 위기 후 크게 과대. USE4S 는 전기간 매우 안정 · 이상값 근처(버블기 과소 · 위기 후 과대 모두 경미). 판독: USE3S P95 고점 약 2.15(2000), MRAD 고점 약 0.46(2000~01); USE4S P95 고점 약 1.85(2000), MRAD 약 0.2~0.3.
- **그림 5.9 (44쪽)** L 팩터 틸트 액티브: USE3L 버블기 크게 과소 → 5년 과대 → 위기 진입 과소(원문은 여기서 "USE3S Model" 이라 적었으나 맥락상 USE3L 오기로 보임 (?)) → 위기 후 과대. USE4L 은 대체로 더 정확, 2010 짧게 크게 과대 예측. 판독: USE3L P95 고점 약 2.25(2000~01), MRAD 고점 약 0.55(2000~01); USE4L 평균 저점 약 0.55(2010), MRAD 고점 약 0.4(2010).
- **그림 5.10 (45쪽)** S 최적화 스타일 24개: USE3S 평균 > 1 대부분(최적화 포트 위험 과소 예측). USE4S 평균은 훨씬 1 에 가까움 = 최적화 편향 조정 효과. USE4S 에서 2007-08 퀀트 멜트다운이 뚜렷. 판독: USE3S P95 고점 약 2.2(2002 무렵), 평균 약 1.1~1.3; USE4S P95 고점 약 2.05(2007~08), 평균 약 1.0~1.1, MRAD 고점 약 0.38(2007~08).
- **그림 5.11 (46쪽)** L 최적화 스타일: USE3L 편향 통계가 대부분 위로 치우침(과소 예측). USE4L 평균은 1 에 더 가깝고 2010 과대 경향. 판독: USE3L P95 고점 약 2.25(2001), 약 2.1(2008), 평균 고점 약 1.4(2008), MRAD 고점 약 0.45(2008~09); USE4L P95 고점 약 2.0(2008).
- **그림 5.12 (47쪽)** S 고유위험(시총가중): USE3S 는 버블기 빼고 고유위험 과대 예측. USE4S 평균 거의 1; 2009 말 약간 과대였으나 2010 말까지 1 근처로 복귀. 판독: USE3S 평균 약 0.8(2003~07), P5 약 0.5, MRAD 약 0.25~0.3; USE4S 평균 저점 약 0.65(2009~10 (?)), MRAD 약 0.2~0.25.
- **그림 5.13 (48쪽)** L 고유위험: USE3 는 S · L 같은 고유위험 예측. USE4L 평균 대부분 1 근처, 2009 말~2010 초 과대 → 2011 초 1 근처 복귀. 판독: USE4L P95 고점 약 2.0(2009), 평균 저점 약 0.65(2010), P5 저점 약 0.35, MRAD 고점 약 0.38(2010).

### 8-7. 표 5.1 — 평균 편향 통계와 MRAD 요약 (49쪽)
본문: 거의 모든 경우 USE4 평균 편향이 1 에 더 가깝고, 모든 포트 종류에서 USE4 MRAD 가 더 작음. 평균 개선 = **S · L 모두 174bp**(우연의 일치). 순수 팩터 제외 시 S **200bp 초과**, L **약 200bp**. 하한 0.19 기준 USE4S 의 초과 MRAD 감소 **50% 초과**.

**S 모델**

| 그림 | MRAD (USE3S) | 평균 B (USE3S) | MRAD (USE4S) | 평균 B (USE4S) | MRAD 차이 (bp) | 포트 종류 |
|---|---|---|---|---|---|---|
| 5.2 | 0.2111 | 0.96 | 0.2109 | 1.00 | 2 | Pure Factors |
| 5.4 | 0.2070 | 0.91 | 0.1884 | 0.99 | 186 | Random Active |
| 5.6 | 0.2186 | 0.96 | 0.2025 | 0.98 | 161 | Factor Tilts Long |
| 5.8 | 0.2305 | 1.02 | 0.2060 | 1.03 | 245 | Factor Tilts Active |
| 5.10 | 0.2365 | 1.09 | 0.2151 | 1.00 | 214 | Optimized Styles |
| 5.12 | 0.2399 | 0.93 | 0.2162 | 1.00 | 237 | Specific Risk |
| Average | 0.2239 | 0.98 | 0.2065 | 1.00 | 174 | |

**L 모델**

| 그림 | MRAD (USE3L) | 평균 B (USE3L) | MRAD (USE4L) | 평균 B (USE4L) | MRAD 차이 (bp) | 포트 종류 |
|---|---|---|---|---|---|---|
| 5.3 | 0.2630 | 0.95 | 0.2542 | 0.96 | 88 | Pure Factors |
| 5.5 | 0.2199 | 0.90 | 0.2136 | 0.95 | 63 | Random Active |
| 5.7 | 0.2716 | 0.96 | 0.2358 | 0.95 | 358 | Factor Tilts Long |
| 5.9 | 0.2732 | 1.02 | 0.2338 | 1.00 | 394 | Factor Tilts Active |
| 5.11 | 0.2409 | 1.06 | 0.2305 | 0.98 | 104 | Optimized Styles |
| 5.13 | 0.2399 | 0.93 | 0.2364 | 0.97 | 35 | Specific Risk |
| Average | 0.2514 | 0.97 | 0.2341 | 0.97 | 174 | |

어긋남 메모: 본문은 "virtually every case" 평균 편향이 USE4 쪽이 1 에 더 가깝다고 했으나, 표에서 S 팩터 틸트 액티브(1.02 → 1.03) · L 팩터 틸트 롱(0.96 → 0.95)은 USE4 가 약간 더 멂 — '거의 모든' 이라는 표현과 일치. 차이 열(bp)은 MRAD 차 × 10,000(예: 0.2070 − 0.1884 = 0.0186 → 186bp). L 평균 차이 0.2514 − 0.2341 = 0.0173 → 표는 174(반올림 · 각 행 평균 차이로 보임 (?)).

---

## 9. 선택 팩터의 성과 (3.5절 17~21쪽, 그림 3.1~3.4)
국가 팩터 수익 = 사실상 시가총액 가중 국가 포트의 초과수익(무위험 대비). 업종 팩터 = 달러 중립, 모든 스타일 노출 0 의 순수 업종 대 시장 성과. 스타일 팩터 = 해당 스타일에만 노출, 모든 업종 순비중 0 · 다른 스타일 노출 0 의 순수 팩터 포트(Menchero 2010).

| 그림 | 쪽 | 제목 | 모양 · 눈에 띄는 시기 (판독은 '약') |
|---|---|---|---|
| 3.1 | 17 | Cumulative returns of USE4 Country factor and Biotechnology Life Sciences factor | Country: 세 차례 강세장(1995~2000 · 2003~2007 · 2009~2011), 버블 붕괴 약세 · 2008 폭락이 뚜렷. 2000 약 +130%, 2002~03 약 +60~70% 로 하락, 2007 약 +150% 고점, 2009 초 약 +10~20% 저점, 2011 약 +135%. 본문: 16년간 100% 넘게 상승. Biotech: 표본 내내 매우 좋음, 특히 2000~2002(약 +40% → 약 +380%); 2009 약 +530% 고점, 끝 약 +480% |
| 3.2 | 19 | Cumulative returns of Automobiles factor and Airlines factor | 본문: Airlines 약 −80%, Automobiles 약 −90%(16년). 판독: 둘 다 1996~97 약 +10~20% 뒤 2001~2004 급락; Airlines 2009 초 약 −60% 까지 반등 후 약 −80%; Autos 2009 약 −93% 저점, 끝 약 −90% |
| 3.3 | 20 | Cumulative returns of Earnings Yield and Momentum factors | EY: 전체적으로 매우 좋음(가치 프리미엄, Basu 1977). 예외 1999 버블기 부진(약 +17% → 2000 초 약 +5%), 2007-08 퀀트 멜트다운 '아래 깜빡임'. 2001~03 급등 약 +60%, 끝 약 +97%. Momentum: 좋음(Jegadeesh-Titman 1993) — 2002 말 큰 하락(약 +112% → 약 +90%, 2000~2002 약세 뒤 반등기) · 2009-03 시작 큰 하락(약 +147% → 약 +100%, 2008 폭락 뒤 회복기). 끝 약 +107% |
| 3.4 | 21 | Cumulative returns of Beta and Size factors | Beta: Country 와 모양 비슷(높은 상관)하나 국가 대비 뚜렷한 음의 표류 — 2003~2007 랠리 불참, 16년 누적 음수(국가는 +100% 초과). CAPM 과 불일치, Fama-French 1992 와 일치. 판독: 2000 약 +24% 고점 → 2002 약 −15% → 2009 초 약 −27% 저점 → 끝 약 −13%. Size: 일관된 하락 표류, **1998 빼고 16년 매년 음수**(소형주 프리미엄, Banz 1981). 끝 약 −40% |

---

## 10. 그림 · 표 목록 (쪽 · 번호 · 제목 · 내용 위치)

| 쪽 | 번호 | 제목(원문) | 본 정리 위치 |
|---|---|---|---|
| 8~9 | 표 3.1 | USE4 Industry Factors | 2-3 (전부) |
| 10~11 | 표 3.2 | Mapping of USE4 industry factors to GICS codes | 2-4 (전부) |
| 12~13 | 표 3.3 | Largest stock within each industry as of 31-May-2011 | 2-5 (전부) |
| 14~15 | 표 3.4 | Industry betas for Assets and Sales | 3-2 (전부) |
| 17 | 그림 3.1 | Cumulative returns of USE4 Country factor and Biotechnology Life Sciences factor | 9 |
| 19 | 그림 3.2 | Cumulative returns of Automobiles factor and Airlines factor | 9 |
| 20 | 그림 3.3 | Cumulative returns of Earnings Yield and Momentum factors | 9 |
| 21 | 그림 3.4 | Cumulative returns of Beta and Size factors | 9 |
| 23~24 | 표 4.1 | Industry factor summary statistics | 5-2 (전부) |
| 26 | 표 4.2 | Style factor summary statistics (A · B) | 5-4 (전부) |
| 27 | 그림 4.1 | Trailing 12-month total R-squared for USE4 and USE3 models | 6-2 |
| 28 | 표 4.3 | Explanatory power of USE4 factors versus USE3 | 6-3 (전부) |
| 29 | 그림 4.2 | Total monthly cross-sectional dispersion (RMS) + specific · factor | 7-1 |
| 30 | 그림 4.3 | RMS contributions from Country, industries, styles | 7-2 |
| 31 | 그림 4.4 | RMS contributions from Beta, Momentum, Size | 7-3 |
| 32 | 그림 4.5 | Histogram of USE4S specific-risk forecasts as of 31-May-2011 | 7-4 |
| 33 | 그림 4.6 | Specific risk levels versus time for USE4S | 7-5 |
| 36 | 그림 5.1 | Simulated results ... perfect forecasts (Normal · K=4) | 8-6 |
| 37 | 그림 5.2 | USE3S vs USE4S pure factors | 8-6 |
| 38 | 그림 5.3 | USE3L vs USE4L pure factors | 8-6 |
| 39 | 그림 5.4 | USE3S vs USE4S 100 random active portfolios | 8-6 |
| 40 | 그림 5.5 | USE3L vs USE4L 100 random active portfolios | 8-6 |
| 41 | 그림 5.6 | USE3S vs USE4S industry and style-tilt long-only portfolios | 8-6 |
| 42 | 그림 5.7 | USE3L vs USE4L industry and style-tilt long-only portfolios | 8-6 |
| 43 | 그림 5.8 | USE3S vs USE4S industry and style-tilt active portfolios | 8-6 |
| 44 | 그림 5.9 | USE3L vs USE4L industry and style-tilt active portfolios | 8-6 |
| 45 | 그림 5.10 | USE3S vs USE4S 24 optimized portfolios | 8-6 |
| 46 | 그림 5.11 | USE3L vs USE4L optimized portfolios | 8-6 |
| 47 | 그림 5.12 | USE3S vs USE4S specific risk | 8-6 |
| 48 | 그림 5.13 | USE3L vs USE4L specific risk | 8-6 |
| 49 | 표 5.1 | Summary of mean bias statistics and MRAD for USE3 and USE4 Models | 8-7 (전부) |
| 59 | 그림 C1 | Percent of observations falling within the confidence interval 1 ± sqrt(2/T) | 8-3 |
| 60 | 그림 C2 | 12-month MRAD versus kurtosis levels for perfect risk forecasts | 8-4 |

---

## 부록: 원문에 없어 이 문서로는 정할 수 없는 것 (재현 시 방법론 노트 · 다른 출처 필요)
1. ESTU 세부 문턱(시총 · 유동성 · 상장 기간) — MSCI IMI 방법론 소관.
2. 기술자 표준화 · 윈저화 문턱 · 결측 대체 · 기술자 합성 후 재표준화 규칙.
3. Residual Volatility 의 Beta 직교화가 회귀 가중인지(NLS · NLB 만 '회귀 가중' 명시).
4. EPFWD 의 FY1 · FY2 가중 방식, CETOP 현금이익 정의, 재무자료 공시 시차.
5. 복수 업종 노출에서 자산 · 매출 추정의 결합 방식 · 업종 베타 회귀 상세.
6. 팩터 공분산 · 고유위험의 반감기 · 뉴이-웨스트 시차 · 최적화 편향 조정 · 변동성 국면 조정 · 베이즈 축소의 수치 모수(USE4S · USE4L 별).
7. 횡단면 회귀의 제약(국가 팩터와 업종 팩터 공선성 해소 — 업종 수익 시총가중 합 0 제약 등) — 본문은 국가 팩터 포트 = 시총가중 국가 포트, 업종 팩터 = 달러 중립이라는 결과만 서술.
8. ESTU · 커버리지 종목 수, 업종별 종목 수.
9. 표 4.1 · 4.2 의 전기간 통합 스타일 통계, 표 4.1 의 수익 · 샤프 · 상관 평균.
