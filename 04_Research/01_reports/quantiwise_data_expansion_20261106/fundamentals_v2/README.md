# 퀀티 재무 수집 DB v2 (fundamentals_v2) — 설계 · 근거 · 시험

- 작성: 2026-11-08 · Q
- 지시: 도훈 11-08 "권고대로 퀀티 중심으로 재무데이터 적재하는걸로 바꾸고 싶어. glossary 참고하고, 펀더멘털 팩터 설계관련한 논문, 전문가 텍스트들 참고해서 재무데이터 수집용 퀀티와이즈 DB도 만들어줘. 이미 유니버스에 펀더멘털이란 이름으로 엑셀파일 있을테니 그것도 참고해"
- 상위 문서: `../PLAN.md`(11-06 수집 체계 계획) · `../BUILD_20261108.md`(같은 날 실행 기록)

## 0. 요약

1. **만든 것**: 퀀티와이즈 Peer Analysis 분기 DB 4개(`03_Universe/Fundamental_v2/FundV2_{BS,IS,CF,META}.xlsx`)입니다.
   - 범위: 119개 항목 · 1998Q1~2026Q3(115분기) · 전 종목(DATA_Key 3,767 = 정본 목록 · 상장 폐지 포함).
   - 도구: 생성기 build 모드 · 리프레시 드라이버 · 적재기(관문 3종 · 개정 기록) · 시험.
2. **양성 대조(시험 DB 2개)에서 확인한 것**
   - `.M` 값은 기존 DB와 같습니다(201412 매출액 1,854종목 · 자산총계 2,296종목 차이 0).
   - 기존 Fundamental DB에 **오표기 2건**이 있었습니다. '이익잉여금' 시트는 자본잉여금을, '단기차입금' 시트는 유동성사채를 받고 있었습니다.
   - B 코드는 값이 오지 않습니다.
3. **퀀티 표준 재무 값은 정정 뒤 값으로 덮입니다.**
   - FY2024 보고서에서 FY2023 수치가 정정된 기업을 보면, 재무상태표 35/35건과 4분기 손익 131/140건이 정정 뒤 값입니다.
   - 정정이 없던 기업은 DART 최초 공시와 99% 일치합니다.
   - 11-08 권고에 달았던 조건("정정치면 결론이 뒤집힌다")이 발동했습니다. 그래서 2015~ 병합 순서는 **DART(최초 공시) 우선을 유지**하자고 권합니다. 퀀티는 1998~2014 · 빈칸 채움 · 공시일 · 잠정실적에 씁니다. 병합 순서는 도훈 님이 확정할 일입니다.
4. **PIT 실측**: 연간 보고서를 결산 뒤 90일을 넘겨 낸 기업이 해마다 52~383곳입니다. 지금 쓰는 고정 규칙(익년 3/31)으로는 월말 신호에서 한 달 이상 미래참조가 됩니다. 수리 방향은 실제 공시일 항목(M123955)을 쓰는 것입니다(§5).

## 1. 왜

- 기존 `03_Universe/Fundamental.xlsx`(41개 시트)는 39개 항목이 201412에서 끝납니다. 2015~ 재무는 DART 연간분뿐입니다.
- 그 DART 연간분이 상장 종목의 28~30%(FY2015~2024)에서 멈춰 있습니다. 원인은 수집기의 완결 판정이 직전 연도 수집량을 기준으로 삼기 때문입니다(11-08 DART 경로 점검 · 수리 세션 진행 중).
- QMJ(Asness · Frazzini · Pedersen 2019) 충실구현은 2000~ 전 종목의 재무 원천 계정이 필요합니다.

## 2. 구성

| 구성 | 위치 | 비고 |
|---|---|---|
| 항목 카탈로그 · DB 정의 | `02_Infrastructure/data/qw_updatefile_registry.json :: fundamentals_v2` | 119개 항목(시트 · 코드 · glossary 이름 · 재무제표 · 종류 · glossary 기준 · 등급 · 주의) · DB 4개 · 시험 근거 |
| 생성기 | `02_Infrastructure/ops/qw_fundamental_book.ps1 -Mode build -Db <name>` | 템플릿 = 기존 Fundamental.xlsx(조회 설정 · DATA_Key 상속) · 기간 = period_from~auto · 저장 전 검증(D9 · 기간 · 링크 · A열 · 빈 데이터) · 있는 파일은 `-Force` 없이 거부 |
| 리프레시 | `02_Infrastructure/ops/qw_peer_refresh.ps1 -Book <xlsx>` | 시트별 링크 Follow · 완료 = B1 'Last Update' 갱신 · 시트당 25~42초(115분기) |
| 적재기 | `02_Infrastructure/data/qw_fund_v2_ingest.py` | G1 리프레시됨 · G2 코드 · 시트 · 기간 일치 · G3 채움 급감 · 값이 바뀌면 `revisions.parquet` · DB 별 출력 `.cache/qw_fund_v2/<DB>.parquet` |
| 종목 목록 | `02_Infrastructure/ops/qw_datakey_sync.ps1` | fundamentals_v2 DB 를 peer 배치로 인식(11-08) · 정본 `06_Registry/qw_datakey_master.json` 끝 붙이기 |
| 시험 | `08_Tests/data/test_qw_fund_v2_ingest.py` | 9/9(뮤테이션 TM = G3 검출력) |

DB 구성은 다음과 같습니다(등록부 `dbs`).
- BS 41: 자산 · 부채 · 자본 구성. 차입은 유동성차입 · 유동성사채 · 사채 · 장기차입 · CB · BW · EB로 나눴습니다. 자본은 지배 · 비지배 · 우선주 · 신종자본증권 · 자기주식으로 나눴습니다.
- IS 40: 매출~순이익 단계, 지배 · 비지배, 이자, R&D, 성격별 비용 6종(광고 · 종업원 · 상각손상 · 경상R&D · 원재료 · 임차), 2006년 이전 경상 · 특별손익.
- CF 18: 영업CF · 운전자본증감 · CAPEX · CF 감가상각 · 배당 · 자본증감 · 벤더 EBITDA · EBIT · IC · NOPLAT(대조용).
- META 20: 공시일 · 실적치 구분 · 연결 구분 · 잠정치 발표일 · 잠정실적 5종 · 주식 수 · 자사주 · 현금배당 · 수정 DPS.

## 3. 항목 선정 근거

- 원천 계정 요구 목록(문헌)은 두 파일에 있습니다. 학술은 `lit_variables_academic.md`(JKP 2023 특성 문서 · Chen-Zimmermann · FF · HXZ · AFP · Piotroski · Sloan · Altman · Ohlson · Beneish 등 원문 링크), 실무 · 전문가 텍스트는 `lit_variables_expert.md`(Penman · Damodaran · McKinsey · Barra · MSCI · KRX · 한국 공시 제도)입니다.
- 선정 = 문헌 요구 원천 계정 ∩ glossary 코드(1,066 IFRS · 772 GAAP 재무 항목) ∪ 기존 DB 41개(코드 정정)입니다. 문헌이 요구하지만 glossary 표준 항목에 없는 것은 등록부 `not_available` 에 적었습니다(당기법인세부채 · 금융업 고유 계정).
- 같은 M 코드라도 GAAP 와 IFRS 정의가 다른 항목은 `caveat` 에 적었습니다. 예: M111300 현금 범위, M112000 이연자산 · 이연법인세자산, M123000 EBITDA, M123100 EBIT.

**문헌 T1 원천 계정 대조** (학술 74행 중 T1 43 · 실무 58행 중 T1 35)

| 문헌 T1(Compustat · 실무 표기) | 이 DB | 상태 |
|---|---|---|
| AT · ACT · RECT · INVT · LT · LCT · AP · RE · SEQ · MIB | TotalAssets · CurrentAssets · AccountsRecv · Inventory · TotalLiab · CurrentLiab · AccountsPay · RetainedEarnings · TotalEquity · NonControllingInt | 수집 |
| CHE · IVST(현금 · 단기금융상품) | CashAndEquiv + (InterestBearingDebt − NetDebt − CashAndEquiv) | IFRS 순부채 정의에서 계산 · GAAP 는 M111300 이 이미 유가증권 포함 |
| IVAO · 관계기업투자 | Investments(투자자산) | 상위 집계로 근사 |
| DLC · DLTT · 총차입 | CurrentBorr + CurrentBonds · Bonds + LongTermBorr (+ CB · BW · EB) · InterestBearingDebt | 수집 |
| CEQ · 지배지분 · PSTK | EquityParent · PreferredCapital(액면) | 수집 — 우선주 청산가치(PSTKRV · PSTKL)는 없음 |
| SALE · COGS · XSGA · OIADP · XINT · PI · NI · 지배 · 비지배 순이익 | Revenue · COGS · SGAExpense · OperatingProfit · InterestExp · PretaxIncome · NetIncome · NetIncomeParent · NetIncomeNCI | 수집 |
| IB · 중단 · 일회성 | IncomeContOps · DiscontinuedOps · 2006년 이전 경상 · 특별손익 3종 | 수집 |
| XRD | RandD(판관비) · ExpOrdRandD(성격별 경상연구개발비) | 수집 — 제조원가 귀속분 포함은 성격별만 |
| DP · 무형자산상각 | DepAmortCF(현금흐름표) · DepAmortSGA · ExpDepAmortImpair | 수집 — 학술 표 지적대로 한국 매출원가 · 판관비에는 감가상각이 들어 있어 FF 영업이익 재현에 별도 값이 필요 |
| OIBDP | OperatingProfit + DepAmortCF | 계산 |
| OANCF · CAPX · SSTK(주식 발행) · 배당 | OperatingCF · Capex · EquityChangeCF · DividendsPaid · CashDivTotal · 중간 · 결산 DPS | 수집 |
| EPS · 주식 수(발행 · 유통 · 가중평균) · 수정계수 | EPSParentAdj · SharesCommonAdj · SharesCommonOutAdj · SharesCommonAvgAdj | 수집(INFO DB) |
| RDQ(발표일) · FYR · 연결 구분 | ReportDate · PrelimDate · 결산월(C 열) · ConsolType | 수집 |
| SIC(업종) | WICS · WI26 · 산업업종 코드 시계열(INFO DB) | 수집 — 시점 기준 업종 |
| TXDITC(이연법인세부채) · XPP · XACC · DRC · TXP · 영업권 · 순확정급여부채 | — | **glossary 표준 항목 없음** → DART 원장(2015~) · 등록부 `not_available` |

- 학술 표의 설계 영향 3가지를 반영했습니다. ① 감가상각 별도 수집 ② 2011 '개별(지분법) → 별도(원가법)' 단절 → `.M`(주재무제표) + 연결 구분 기록 ③ 분기 값 + 발표일.
- 학술 표는 열람한 한국 논문 가운데 연결/별도 · 지배 귀속 · 비12월 결산 처리를 밝힌 예가 없다고 적었습니다. 이 선택은 문헌 관례가 아니라 설계 결정입니다.
- 실무 표의 PIT 근거는 다음과 같습니다(§5 실측과 일치).
  - 2011~2014 연결 분기 · 반기 보고서 60일 기한(자본시장법 제160조 단서 · 금융위 2010 Q&A)
  - K-GAAP 시기 연결 사업보고서 120일(자산 2조 미만)
  - 사업보고서 5영업일 연장
  - 영업이익 정의 변경 2012 · 2027(K-IFRS 1118 예정)

## 4. 양성 대조 (시험 DB 2개 · 22 + 14개 항목)

시험 DB는 `03_Universe/Fundamental_v2/_pc/Fundamental_PC_20261108.xlsx`(8개 기간 200912~202506)와 `Fundamental_PC2_20261108.xlsx`(2개 기간)입니다. 항목 목록은 `pc_items.json` · `pc2_items.json` 입니다.

| 질문 | 결과 |
|---|---|
| `.M` 값이 기존 DB 와 같은가 | 201412 매출액 1,854종목 · 자산총계 2,296종목 **차이 0** |
| 기존 '이익잉여금' 시트 | **M115500(자본잉여금)** — 2,125종목 일치 · 진짜 이익잉여금(M115600)과는 전부 다름 |
| 기존 '단기차입금' 시트 | **M113400(유동성사채)** — 2,210종목 일치 · 유동성차입금(M113300)과는 1,917종목 다름 |
| 접미 | `.M` = 주재무제표(연결 우선). 접미 없음과 `.IP` 는 별도 · 개별로, 202412 매출액 2,598종목이 같고 `.M` 과는 1,910종목이 다름 |
| B 코드(FCF 상세) | `.M` 유무와 상관없이 **값 0** — 쓰지 않는다 |
| IFRS 로만 적힌 항목의 GAAP 기간 | CAPEX(M132010) · CF 감가상각(M132020) · 운전자본증감(M131025) · R&D(M121350)는 200912 에도 값이 옴 |
| 연결 구분(M140800) | IFRS 기간(201112~)만: 1 개별 · 2 연결 · 0 별도(소수) |
| 공시일(M123955) · 잠정치 발표일(M123900) | 200912 부터 YYYYMMDD |
| 주식 수 | M701500.M(기존 ISSD) = D503300.M — 전 기간 같은 값 |

**정정치 판별** (스크립트는 세션 작업 폴더 `restate_test.py` · `restate_flow.py`, 결과는 아래 표)

| 항목(202312) | 비교 가능 | 정정 있음 | 정정 기업에서 퀀티 = 최초 | = 정정 뒤 | 둘 다 아님 | 정정 없는 기업 일치 |
|---|---|---|---|---|---|---|
| 자산총계 | 693 | 20 | 0 | **20** | 0 | 667/673 |
| 지배주주 자본 | 622 | 15 | 0 | **15** | 0 | 602/607 |
| 매출액(4분기 단독) | 565 | 64 | 1 | **62** | 1 | 497/501 |
| 순이익(4분기 단독) | 593 | 37 | 0 | **35** | 2 | 550/556 |
| 지배주주 순이익(4분기) | 475 | 39 | 3 | **34** | 2 | 432/436 |

- 최초 = DART FY2023 사업보고서 당기 수치(4분기 = 연간 − 3분기 보고서 9개월 누적).
- 정정 뒤 = FY2024 사업보고서의 전기 수치(4분기 = 연간 − FY2024 3분기 보고서 전기 누적).
- 퀀티 분기 손익은 **분기 단독 값**입니다(4분기 = 연간 − 9개월).
- 정정 크기: 재무상태표 정정 35건의 평균 |변화| 3.7%, 1% 초과 19건, 최대 55%(지배자본).

## 5. PIT 실측 — 실제 공시일 (META DB 적재분 · `ReportDate` − 결산 분기말)

| 연도 | 연간 보고서 수 | 중앙값(일) | 90분위 | 90일 초과(3/31 넘김) |
|---|---|---|---|---|
| 2005 | 1,977 | 73 | 93 | 250 |
| 2010 | 2,125 | 75 | 90 | 211 |
| 2015 | 2,318 | 77 | 95 | 339 |
| 2019 | 2,582 | 78 | 97 | 383 |
| 2023 | 2,645 | 80 | 81 | 172 |
| 2025 | 2,584 | 77 | 82 | 52 |

- 기존 XLSX 경로(`parse_fundamental_xlsx.R:205`)는 분기를 분기말 + 45일, 4분기를 익년 3/31로 고정합니다. DART 연간(`data_collector_dart.R:1212`)도 3/31입니다.
- 3/31을 넘겨 낸 연간 보고서는 월말 신호에서 **한 달 이상 미래참조**가 됩니다(C4). 이런 보고서는 감사 지연 기업 쪽에 몰려 있을 가능성이 높습니다(미측정).
- 분기 보고서는 2011~2014년 90분위가 60일입니다(연결 분기보고서 기한으로 보임). 같은 달 안이라 월간 신호에는 영향이 없지만, 주간 · 일간 신호에는 영향이 있습니다.
- 공시일 값이 정정 공시일로 바뀌는지는 미확인입니다. 99분위 455~463일(2018~2021)은 정정 재제출일일 가능성이 있습니다. 공시일을 Factor_Date로 쓰면 이 경우 늦게 쓰는 쪽(보수적)이라 미래참조는 아닙니다.

## 6. 결론 · 권고 (도훈 확인 사항)

1. **2015~ 병합 순서**: DART(최초 공시 · 접수번호로 공시일 확인) > 퀀티 v2 > 기존 XLSX 순서를 권합니다. 퀀티를 위로 올리면 정정 기업(손익 6~11%, 재무상태표 약 3%)에서 다음 해 보고서로 알게 되는 숫자를 1년 먼저 쓰게 됩니다. DART 커버리지 수리(세션 'DART 재무 수집 범위 수리 · 2015~2024 보충')가 끝나야 이 순서가 실효를 냅니다.
2. **1998~2014**: 퀀티 v2 가 유일한 원천이라 기존 XLSX 를 대체합니다(오표기 2건 정정 · 항목 119개). 정정 덮어쓰기 오염은 그대로 남으니 문서로 밝히고 둡니다(원천이 따로 없음).
3. **공시일**: 병합의 Factor_Date 를 실제 공시일 기준으로 바꿉니다. 퀀티 M123955 와 DART rcept_no 를 쓰고, 공시일 다음 거래일부터 쓰고, 공시일이 없으면 지금 고정 규칙을 씁니다.
4. **개정 기록**: 적재기가 앞으로의 값 변화를 `revisions.parquet` 에 남깁니다. 정정 공시 자체도 연구할 수 있는 신호입니다.
5. 병합 순서 변경과 팩터 DB 재빌드는 각각 도훈 님 확인 뒤에 합니다(11-08 약속 그대로).

## 7. 남은 일

- [ ] DB 4개 리프레시 → 적재(META 완료 11-08 17:07 · 433만 행)
- [ ] 문헌 표 2개 도착 → §3 대조(빠진 원천 계정이 있으면 extend 모드로 시트 추가)
- [ ] 병합 경로 결정(§6 · 도훈) → `build_fundamental_derived.R` · `parse_fundamental_xlsx.R` 수정 · 팩터 DB 재빌드(도훈)
- [ ] 갱신용 DB(최근 8분기 창 · `window_quarters`) 등록 · 체인 단계(주간 또는 공시 시즌 매일)
- [ ] 금융업 고유 계정(은행 · 보험 · 증권)
- [ ] 기존 팩터 DB 가 기존 오표기 2건(RetainedEarnings · ShortTermBorr, ≤2014)을 쓰는 곳 영향 조사
