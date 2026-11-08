# 펀더멘털 팩터 원천 계정 — 실무·전문가 텍스트 근거 표

- **파일**: `fundamentals_v2/lit_variables_expert.md` · 작성 2026-11-08 · 조사 = Q 하위 에이전트(웹 문헌만 · R/Python 미실행 · 이 파일 외 쓰기 없음).
- **쓰임**: 퀀티와이즈(FnGuide) 재무 수집 DB(분기 · 한국 전 상장 종목 · 1998~)의 항목 목록 결정. 단위 = 팩터 정의가 아니라 **그 정의에 들어가는 원천 계정**(예: RNOA → 영업이익 · 법인세 · 순영업자산 = 영업자산 − 영업부채).
- **범위**: 실무·전문가 텍스트(교재 · 리스크 모형 · 지수 방법론 · 국내 제도). 학술 논문 목록은 다른 조사자 몫 — 겹치는 것(QMJ · Beneish · Piotroski)은 실무 문서가 쓰는 정의만 짧게 적었다.

**표기**
- 확인 수준: **✔ 원문** = 1차 문서 본문을 직접 열어 확인 · **◐ 개요** = 목차 · 공개 요약 · 학습목표 · 데이터시트만 · **◇ 2차** = 1차 문서를 못 열어 신뢰할 만한 2차 문서(AAII · 학술 초록 · 언론)로 확인 · **✗ 미확인** = 열지 못함(근거로 쓰지 않음).
- 등급: **T1** = 출처 계열 3개 이상이 공통으로 쓰는 핵심 · **T2** = 1~2개 계열의 특정 방법론에 필요 · **T3** = 드물거나 보조.
- 출처 계열(13): NP(Nissim·Penman) · DAM(Damodaran) · MCK(McKinsey Valuation) · CFA · GRA(Graham) · GRE(Greenblatt) · QV(Gray·Carlisle) · BAR(MSCI Barra) · MSQ(MSCI Quality 지수) · SPQ(S&P Quality 지수) · AQR · KRX(한국거래소) · REG(법령·금융위).
- 계정명은 K-IFRS 국문 관행 표기(퀀티 항목명·코드와의 대응은 별도 대조 필요). **'(추론)'** = 출처 문장이 아니라 Q 의 해석.

---

## §0 한눈에

1. **표 1 = 58행** (T1 35 · T2 19 · T3 4). 손익 20 · 재무상태 30 · 현금흐름 5 · 주식·기타 3.
2. **T1 (35)** — 손익: 매출액 · 매출원가(매출총이익) · 영업이익 · 감가상각비·무형자산상각비 · 이자비용 · 영업외손익 세부 · 법인세비용 · 중단영업·일회성 항목 · 당기순이익(총액) · 지배 귀속 순이익 · 비지배 귀속 순이익 · EPS · 배당(총액·주당 중간/결산). 재무상태: 자산총계 · 유동자산 · 현금·단기금융상품 · 매출채권 · 순유형자산 · 관계기업투자 · 유동부채 · 매입채무 · 단기차입금·유동성장기부채 · 사채·장기차입금 · 총차입금 · 순확정급여부채 · 부채총계 · 자본총계 · 지배기업 소유주지분 · 비지배지분 · 우선주 · 자기주식. 현금흐름: 영업활동현금흐름 · 유형자산 취득 · 주식 발행·자사주 취득/소각. 기타: 주식수(발행·분기말 유통·가중평균).
3. **국내 실무만 요구하는 원천**: 지배/비지배 분리(이익·자본 — KRX 지표 전부 지배 기준), 자본금(자본잠식률), 자기주식·유통주식수, 주당배당금 중간/결산 분리, 연결·별도 둘 다(KRX 관리종목 판단이 지표마다 다른 재무제표 기준).
4. **PIT 핵심 발견**(표 2): ① 2011~2014 연결 분·반기 **60일 특례** → Qvest pit.md C4 고정일(5/15·8/15·11/15)이 최대 약 2주 미래참조 ② K-GAAP 시기 연결 사업보고서 **120일**(자산 2조 미만) → '익년 3/31' 미래참조 ③ 사업보고서 **5영업일 연장** ④ IFRS 첫해의 2010 비교 수치 **재작성** ⑤ 영업이익 정의 단절(2011 ↔ 2012~ ↔ 2027~) ⑥ 분기보고서 2000년 시작(2차 확인). → 접수일 · 정정 · 잠정 · 연결 구분 메타가 원천 계정만큼 중요하다(§5).

---

## §1 출처 목록 (실제로 연 문서)

| 계열 | 문서 (판 · 날짜) | 이 조사에서 확인한 범위 | 수준 | 링크 |
|---|---|---|---|---|
| NP | Nissim & Penman, *Ratio Analysis and Equity Valuation* 워킹페이퍼(1999-03, Columbia 게시본) — RAST 6(1) 2001 출판판의 선행판 | 재구성 식 (2)~(7) · 부록 '변수 측정'(Compustat 항목 번호) 전부 | ✔ (출판판 본문 ✗) | [NP][np] |
| NP | Penman, *Financial Statement Analysis and Security Valuation* 5판(2013) 출판사 목차 | 10장 재무상태표·손익계산서 분석 · 12장 수익성 · 13장 성장·지속이익 · 18장 재무제표의 질 | ◐ (본문 유료 ✗) | [Penman][pen] |
| DAM | Damodaran, *Return on Capital (ROC), ROIC and ROE: Measurement and Implications*(2007-07) | ROIC 분자·분모·시점 · 현금 차감 · 비현금 ROE · Cash ROIC · CFROI · R&D 자본화 · 운용리스 부채화 | ✔ | [DAM][damr] |
| DAM | Damodaran, *Variables used in Data Set*(NYU Stern) | EV · 투하자본 · 재투자율 · 순자본적지출 · 비현금 운전자본 · EBITDA · 실효세율 · 부채 · 현금 · FCFF/FCFE · 배당 정의 | ✔ | [DAMV][damv] |
| DAM | Damodaran 스프레드시트 목록 | R&DConv.xls · oplease.xls · ratings.xls 설명문 | ◐ | [DAMS][dams] |
| MCK | Koller·Goedhart·Wessels, *Valuation* 7판(2020) 출판사 미리보기 | 목차: 8 ROIC · 11 재무제표 재구성 · 16 비영업자산·부채 성격 항목·하이브리드·비지배 · 18 EBITA/NOPAT 멀티플 · 20 세금 · 21 영업외·일회성·충당부채 · 22 리스 · 23 퇴직급여 · 24 비용 처리 투자의 자본화 | ◐ (정의식 본문 ✗ — 표 1 에서 MCK 를 근거로 든 칸은 장 제목에 기댄 항목 대응) | [MCK][mck] |
| CFA | 2026 L1 *Financial Analysis Techniques* 공개 요약·학습목표 | DuPont 5요소(세부담·이자부담·영업수익성·효율성·레버리지) · 비율 4분류 | ◐ | [CFA-F][cfaf] |
| CFA | 2026 L2 *Evaluating Quality of Financial Reports* 공개 요약·학습목표 | 이익의 질 지표(반복이익·지속성·발생액) · 현금흐름의 질 · 재무상태표의 질 · 부도 예측 | ◐ | [CFA-Q][cfaq] |
| CFA | McLeavey, Enterprising Investor(2013-07-29) | Beneish M-score 8변수 이름·계수·문턱(−1.78) · QV 3장 언급 | ✔ (변수 산식 ✗ — 표 1 의 Beneish 항목 대응은 변수 이름에 기댄 것, 산식은 학술 원전 몫) | [Beneish][cfab] |
| GRA | Thorp, AAII Journal(2011-04 · 2015 갱신) *Tweedy, Browne: What Has Worked in Investing* | NCAV = 유동자산 − 모든 부채(우선주·미적립 연금 포함) · 66% 기준 · 배당수익률·배당성향 | ◇ (Graham 원서 ✗) | [NCAV][gran] |
| GRA | Markowski, AAII Journal(2022-07) *Benjamin Graham's Defensive Investor Non-Utility Screen* | 매출 규모 · 유동비율 · 장기부채/운전자본 · 7년 흑자·배당 · EPS 성장 · P/E · P/E×P/B (AAII 구현값) | ◇ (원서 기준값 ✗) | [Graham][grad] |
| GRE | Bajkowski, AAII Journal(2006-01) *The Magic Formula Approach to Stockpicking* | ROC · EY · EV · 순운전자본 · 순유형자산 정의 · 제외 업종 | ◇ (원서 부록 ✗ · 공식 사이트엔 정의 없음) | [GRE][gre] |
| QV | Gray & Carlisle, *Quantitative Value*(Wiley 2013) 출판사 미리보기 | 목차: 3장 발생액·PROBM · 4장 재무 곤경 · 5장 프랜차이즈 · 6장 F_SCORE·FS_SCORE · 7~8장 가격 지표 | ◐ (본문 산식 ✗ — 산식은 아래 AAII · 인터뷰 · CXO 2차로만) | [QV][qvt] |
| QV | Gray, AAII Journal(2015-05) *Simple Methods to Improve the Piotroski F-Score* | F_SCORE 9신호 · FS_SCORE 10신호 정의 | ◇ | [FS][qvfs] |
| QV | Byrnes, Motley Fool(2013-02-21) Gray 인터뷰 | 8년 기하평균 ROA·ROC · 8년 누적 FCF ÷ 총자산 · 마진 성장·안정 | ◇ | [QV-FP][qvfp] |
| QV | CXO Advisory(2013-03-12) *A Few Notes on Quantitative Value* | EBIT/TEV · PFD(12개월 내 재무 곤경 확률) · STA·SNOA 이름 | ◇ (STA·SNOA·PMAN 산식 ✗) | [CXO][qvcxo] |
| BAR | MSCI *USE4L Data Sheet*(2012-07, Arcana 게시) + USE4 브로셔(msci.com) | USE4 스타일 설명자와 가중치 | ✔ (데이터시트) | [USE4L][baru] · [USE4][baruse4] |
| BAR | MSCI Model Insight *GEM3 Descriptor Details*(2013-09, Arcana 게시) | 설명자 정의 전부(ETOP 의 TTM 정의 · CETOP · EGRO·SGRO · YILD · BTOP · MLEV·DTOA·BLEV) | ✔ | [GEM3][barg3] |
| BAR | MSCI Model Insight *CNE5 Descriptor Details*(2013-09, 제3자 사이트 사본) | 중국 모형 설명자 정의·가중치 | ✔ | [CNE5][barc5] |
| BAR | MSCI *Datasheet — Barra Global Total Market Equity Model for Long-Term Investors (GEMLT)*(2015-12판 · © 2020, Arcana 게시) | 품질 계열 설명자 이름(Profitability · Investment Quality · Earnings Quality · Earnings Variability · Leverage) · '시점(PIT) 재무 데이터' 명시 | ◐ (설명자 산식 ✗) | [GEMLT][barlt] |
| BAR | Barra 한국 모형 KRE2(2004-05-02) · KRE3(2013-11-01) 연구 노트 | 초록만(설명자 이름·정의 없음) | ✗ | (MSCI 고객 문서) |
| MSQ | *MSCI Quality Indexes Methodology*(2025-05) | ROE · D/E · 이익 변동성 정의 · 결측 규칙 | ✔ | [MSQ][msq] |
| SPQ | Invesco S&P 500 Quality ETF *Summary Prospectus*(2025-08-28, SEC EDGAR) — S&P 지수 정의 요약 | ROE · 발생액 비율 · 금융 레버리지 정의 · 금융·부동산 예외 | ✔ (S&P 방법론 원문은 403 ✗) | [SPQ][spq] |
| AQR | Asness·Frazzini·Pedersen, *Quality Minus Junk*(RAST 2019 출판판) | 부록 변수 정의(수익성·성장·안전·배당) — Compustat 항목 | ✔ | [QMJ][qmj] |
| AQR | Asness·Frazzini·Israel·Moskowitz, *Fact, Fiction, and Value Investing*(JPM 2015) | 가치 지표 복합(BE/ME · E/P · CF/P · D/P) · 시의적(timely) 가격 | ✔ | [FFV][ffv] |
| KRX | 《투자지표 산출 상세안내》(KIND, 파일 생성 2024-11-29 · 본문에 날짜 없음 · 자료 제공 FnGuide) | PBR · PER · ROE · 배당성향 · 배당수익률 · TSR 산식 · 연결/개별 · 결산기 변경 · 기준 변경 합산 규칙 · 반영 시점 | ✔ | [KRX지표][krxi] |
| KRX | 보도자료 「코리아 밸류업 지수」 발표(2024-09-24, 네이버 금융 게시 사본) | 5단계 선별(시가총액 · 수익성 · 주주환원 · PBR · ROE) | ✔ | [밸류업][krxv] |
| KRX | 《유가증권시장 12월 결산법인 정기결산 관련 유의사항》(KIND, 2026-02) | 내부결산실적 공시(30%/15%) · 감사보고서 공시 · 사업보고서 기한·연장 · 공시기준 재무제표 · 자본잠식률 | ✔ | [KRX결산][krxy] |
| REG | 자본시장법 제159조 · 제160조 · 제164조 (정본 = 국가법령정보센터 · 본문 확인 = korea.legal 사본) | 90일 · 45일 · 60일 특례 · 정정명령 | ✔ (사본) | [§159][law159] · [§160][law160] · [§164][law164] · [법령][lawgo] |
| REG | 금융위원회 「IFRS 정보이용자 조찬간담회 개최」 Q&A(2010-05-10) | 의무 적용 시기 · 조기 적용 · 연결 중심 · 제출 기한(90/45/60/120일) · 첫 공시일 · 2조 판단 | ✔ | [금융위2010][fsc10] |
| REG | 금융위원회 보도자료 「'27년부터 K-IFRS 손익계산서가 변경되고, 영업손익의 개념이 확대됩니다」(2025-12-18) | '12~ 영업손익 표시 의무 · K-IFRS 1118 영업손익 · 시행·병기 | ✔ | [금융위2025][fsc25] |
| 2차 | 백정한·최종서(2014) 『경영과정보연구』 33(3) 초록 | 2012 영업이익 산출 방식 복원 | ◇ | [KCI-영업이익][kcioi] |
| 2차 | 조중석·조문희(2006) 『회계저널』 15(2) 초록 | 분기보고서 2000년 시작 | ◇ | [KCI-분기][kciq] |
| 2차 | 아주경제 「[공시학개론] 실적발표 시즌…」(2024-05-02) | 잠정실적 공시 명칭·유형 | ◇ | [아주][aju] |

---

## §2 표 1 — 원천 항목

> 필요 주기: '분기 → TTM' = 분기 3개월값(또는 누적값)을 모아 최근 12개월을 만든다 · '분기말' = 잔액 · '연 이력 n' = 회계연도 n개 연속 필요.

### A. 손익계산서 (IS) — 20행

| # | 개념 (영문 · 국문) | 재무제표 | 필요 주기 | 이 항목을 쓰는 지표 (지표명 — 출처) | 근거 링크 | 등급 |
|---|---|---|---|---|---|---|
| A1 | Revenue / Sales · 매출액(영업수익) | IS | 분기 → TTM · 연 이력 5~8 | GPOA·GMAR·Altman Z·NPOP 분모 — AQR QMJ; SGRO(5 FY 주당매출을 시간에 회귀한 기울기 ÷ 평균) — Barra GEM3·CNE5·USE4; 매출 변동성·매출총이익률·자산회전율 — Barra GEMLT; PM·ATO(DuPont) — NP·CFA; FS_ΔMARGIN·FS_ΔTURN — QV; DSRI·GMI·SGI — Beneish; 매출 규모(TTM) — Graham 방어적; 매출액 50억 미만 관리종목 · 30%(대규모법인 15%) 변동 공시 — KRX; 영업이익률·순이익률 — DAM | [QMJ][qmj] [GEM3][barg3] [GEMLT][barlt] [NP][np] [CFA-F][cfaf] [FS][qvfs] [Beneish][cfab] [Graham][grad] [KRX결산][krxy] [DAMV][damv] | T1 |
| A2 | Cost of goods sold (+ reported gross profit) · 매출원가(+ 매출총이익 보고값 대조) | IS | 분기 → TTM · 연 이력 | GPOA = (매출 − 매출원가) ÷ 총자산 · GMAR = (매출 − 매출원가) ÷ 매출 — QMJ; Gross Profitability · Gross Profit Margin — Barra GEMLT; FS_ΔMARGIN(매출총이익률 개선) — QV; GMI — Beneish; 한국 영업이익을 K-GAAP 방식으로 산출(2012~) — 학술 초록(K-GAAP 영업이익 = 매출총이익 − 판관비는 통상 정의) | [QMJ][qmj] [GEMLT][barlt] [FS][qvfs] [Beneish][cfab] [KCI-영업이익][kcioi] | T1 |
| A3 | SG&A · 판매비와관리비 | IS (+주석 세부) | 분기 → TTM | SGAI — Beneish; 한국 영업이익 산식 구성요소(2012 K-GAAP 방식 복원 — 학술 초록 · 산식은 통상 정의) · 금융위('12~ 영업손익 표시 의무) | [Beneish][cfab] [KCI-영업이익][kcioi] [금융위2025][fsc25] | T2 |
| A4 | Operating income / EBIT · 영업이익 | IS | 분기 → TTM · 연 이력 8 | ROIC = EBIT(1−t) ÷ 전기말 투하자본 · EBITDA = EBIT + D&A — DAM; ROC = EBIT ÷ (순운전자본 + 순유형자산) · EY = EBIT ÷ EV — Greenblatt; EBIT/TEV — QV; Enterprise Multiple(EBIT to EV) — Barra GEMLT; DuPont 5요소 '영업수익성' — CFA; Altman Z 의 EBIT — QMJ; EBITA·NOPAT 멀티플(18장) — MCK; 영업손익 30%(15%) 변동 공시 — KRX. ⚠ 정의 단절 = 표 2 K8 | [DAM][damr] [GRE][gre] [CXO][qvcxo] [GEMLT][barlt] [CFA-F][cfaf] [QMJ][qmj] [MCK][mck] [KRX결산][krxy] | T1 |
| A5 | Depreciation & amortization · 감가상각비 · 무형자산상각비(분리 수집) | IS(주석) / CF 가산 항목 | 분기(누적) → TTM | EBITDA · 순자본적지출(capex − 감가상각) · Cash ROIC = (EBIT(1−t) + D&A) ÷ (총유형자산 + 비현금 운전자본) — DAM; CFOA = (NI + DP − ΔWC − CAPX) ÷ AT · ACC = −(ΔWC − DP) ÷ AT — QMJ; DEPI — Beneish; EBITA(이자·세금·상각 전 이익) 멀티플 — MCK 18장 목차 | [DAM][damr] [DAMV][damv] [QMJ][qmj] [Beneish][cfab] [MCK][mck] | T1 |
| A6 | Interest expense · 이자비용(금융원가 중 이자) | IS (주석) | 분기 → TTM | Core NFE = 이자비용 × (1 − 한계세율) + 우선주배당 − 이자수익 × (1 − t) · NBC = NFE ÷ 전기 NFO — NP; 세후영업이익 = NI + 이자비용(1−t) − 영업외이익(1−t) · 이자보상배율 → 합성 신용등급(ratings.xls) — DAM; 이자부담 — CFA DuPont(공개 요약엔 요소 이름만 · 산식 EBT ÷ EBIT 는 통상 정의) | [NP][np] [DAM][damr] [DAMS][dams] [CFA-F][cfaf] | T1 |
| A7 | Interest income · 이자수익(금융수익 중 이자) | IS (주석) | 분기 → TTM | 금융수익(NFE 차감; 운영 현금 이자를 분리할 수 없어 전액 금융으로) — NP; 비현금 ROE = (NI − 현금 이자수익(1−t)) ÷ (자본 − 현금) — DAM | [NP][np] [DAM][damr] | T2 |
| A8 | Non-operating income/expense detail · 영업외손익 세부(금융수익 · 금융원가 · 기타수익 · 기타비용) | IS (+주석) | 분기 → TTM | UOI = 세후 영업외손익(이자·지분법 제외) + 세후 특별항목 + 비경상·중단영업 + 환산조정 변동 — NP; 세후영업이익에서 영업외이익 제거 — DAM; 21장 *Nonoperating Expenses and One-Time Charges* — MCK | [NP][np] [DAM][damr] [MCK][mck] | T1 |
| A9 | Equity-method income · 지분법손익(관계·공동기업) | IS | 분기 → TTM | 'Other Items'(Compustat #55)로 매출 기반 영업이익에서 분리 — NP; 비영업자산 가치평가(16장) — MCK | [NP][np] [MCK][mck] | T2 |
| A10 | Pretax income · 법인세비용차감전순이익(계속영업) | IS | 분기 → TTM | 세부담 · 이자부담 — CFA DuPont 5요소(산식 NI ÷ EBT · EBT ÷ EBIT 는 통상 정의 — 공개 요약엔 요소 이름만); O-score FUTL = 세전이익 ÷ 부채총계 — QMJ | [CFA-F][cfaf] [QMJ][qmj] | T2 |
| A11 | Income tax expense (+ 법정 한계세율 = 메타) · 법인세비용 | IS (+주석 실효세율) | 분기 → TTM | EBIT(1−t) 의 t = 실효 또는 한계세율(실납부세액을 쓰면 부채 절세효과가 자본비용과 이중 계상된다는 경고) · 실효세율 = 납부세액 ÷ 과세소득 — DAM; 한계세율(법정세율)로 세후 금융손익 — NP; 영업 세금 · 이연법인세(20장) — MCK | [DAM][damr] [DAMV][damv] [NP][np] [MCK][mck] | T1 |
| A12 | Discontinued ops & unusual items · 중단영업손익 · 일회성 항목(구조조정·손상 등) | IS (+주석) | 분기 | UOI(특별항목 #17 · 비경상·중단 #48) — NP; 과거 구조조정 비용이 장부가·ROC 를 왜곡 — DAM; 21장 *One-Time Charges* — MCK; QMJ 수익성은 비경상 전 이익(IB) 기준 — AQR | [NP][np] [DAM][damr] [MCK][mck] [QMJ][qmj] | T1 |
| A13 | Net income (consolidated total) · 당기순이익(연결 총액) | IS | 분기 → TTM · 연 이력 | ROE · ROA 분자 — QMJ; F/FS_ROA · ACCRUAL — QV; ETOP(TTM 이익 ÷ 시가총액) — Barra; E/P(가치 복합) — AQR FFV; ROE(DuPont) — CFA; 당기순손익 30%(15%) 변동 공시 — KRX; 최근 2년 손익(적자 여부) — KRX 밸류업 | [QMJ][qmj] [FS][qvfs] [GEM3][barg3] [FFV][ffv] [CFA-F][cfaf] [KRX결산][krxy] [밸류업][krxv] | T1 |
| A14 | NI attributable to owners of parent · 지배기업 소유주 귀속 당기순이익 | IS | 분기(3개월) → 직전 4분기 합 | PER = 주가 ÷ (직전 4분기 지배지분 순이익 ÷ 가중평균 유통주식수) · ROE · 배당성향 분모 — KRX 지표(FnGuide 제공); 지주회사는 지배회사 지분 귀속 순이익으로 비교 — 금융위 2010; 보통주 귀속 포괄이익 CNI = NI − 우선주배당 + CSA — NP; TTM EPS(ROE) — MSCI · S&P (EPS 는 정의상 지배 보통주 기준 — 추론) | [KRX지표][krxi] [금융위2010][fsc10] [NP][np] [MSQ][msq] [SPQ][spq] | T1 |
| A15 | NI attributable to NCI · 비지배지분 귀속 순이익 | IS | 분기 | OI = NFE + CNI + MII(#49) — NP; 연결이면 지배지분 순이익, 개별이면 당기순이익을 합산 — KRX 지표; 비지배지분 가치(16장) — MCK | [NP][np] [KRX지표][krxi] [MCK][mck] | T1 |
| A16 | Other comprehensive income (flow) · 기타포괄손익(흐름) · 총포괄이익 | IS (포괄손익계산서) | 분기 | 포괄이익 기반 재구성(잔여이익 평가는 포괄이익이어야 함) · 청정잉여 조정 CSA = Δ환산조정 + Δ매도가능증권 평가 — NP | [NP][np] | T2 |
| A17 | EPS basic/diluted (reported) · 기본·희석 주당이익(보고값) | IS | 분기 · 연 이력 5~7 | ROE = TTM EPS ÷ 최근 BVPS — MSCI Quality · S&P Quality; 이익 변동성 = 최근 5 FY 전년 대비 EPS 증가율의 표준편차 — MSCI Quality; EGRO(5 FY 연간 EPS 를 시간에 회귀) — Barra; 7년 연속 흑자 · 7년 평균 EPS 성장 3% — Graham 방어적(AAII 구현); EPS = 지배 순이익 ÷ 가중평균 유통주식수 — KRX | [MSQ][msq] [SPQ][spq] [GEM3][barg3] [Graham][grad] [KRX지표][krxi] | T1 |
| A18 | R&D expense (+ capitalized development cost) · 연구개발비(비용분) · 개발비 자산화분 | IS(주석) / 사업보고서 / BS | 연 이력(상각연수만큼, 예 5~10) | R&D 자본화: 상각연수별 과거 R&D 누적 = 연구자산 · 조정 영업이익 = 영업이익 + 당기 R&D − 연구자산 상각 — DAM(논문 · R&DConv.xls); 24장 *Capitalizing Expensed Investments* — MCK; (추론) K-IFRS 는 개발비 일부를 무형자산으로 자산화하므로 비용분만 모으면 과소 | [DAM][damr] [DAMS][dams] [MCK][mck] | T2 |
| A19 | Leases · 운용리스료·리스 약정(주석) / 리스부채 · 사용권자산 · 리스 이자 | IS · BS · 주석 | 연 · 분기 | 운용리스 약정의 현재가치(세전 차입이자율 할인)를 부채로 · 조정 영업이익 = 영업이익 + 리스료 − 리스자산 감가상각 — DAM(논문 · oplease.xls); 22장 *Leases* — MCK; 리스 기준 전환 시점 = 표 2 K15 | [DAM][damr] [DAMS][dams] [MCK][mck] | T2 |
| A20 | Dividends · 현금배당금총액 · 주당배당금(중간·결산 분리) · 우선주 배당 | 기타(배당 공시·사업보고서) / CF '배당금의 지급' | 연(+중간배당 시점) | 배당성향 = 현금배당금총액 ÷ 지배 순이익 · 배당수익률 = (중간 + 결산) 주당배당금 ÷ 사업연도말 주가 — KRX; YILD = TTM 주당배당 ÷ 현재가 — Barra GEM3 · 예측 D/P — Barra GEMLT; D/P(가치 복합) — AQR FFV; 7년 연속 배당 — Graham(AAII); 배당수익률·배당성향 — Tweedy(AAII); 최근 2년 연속 배당 또는 자사주 소각 — KRX 밸류업; 배당성향·배당수익률 — DAM; 우선주배당 = 금융비용 — NP | [KRX지표][krxi] [GEM3][barg3] [GEMLT][barlt] [FFV][ffv] [Graham][grad] [NCAV][gran] [밸류업][krxv] [DAMV][damv] [NP][np] | T1 |

### B. 재무상태표 (BS) — 30행

| # | 개념 (영문 · 국문) | 재무제표 | 필요 주기 | 이 항목을 쓰는 지표 (지표명 — 출처) | 근거 링크 | 등급 |
|---|---|---|---|---|---|---|
| B1 | Total assets · 자산총계 | BS | 분기말 (+기초·평균) | GPOA · ROA · CFOA · LEV · Altman Z 분모 — QMJ; 발생액 비율 = 직전 FY 순영업자산 변화 ÷ 직전 2개 FY 평균 총자산 — S&P; DTOA — Barra; Total Assets Growth Rate(투자의 질) — Barra GEMLT; F_ROA(기초 총자산) · FS_FCFTA(최근 총자산) — QV; 영업자산 = 총자산 − 금융자산 — NP | [QMJ][qmj] [SPQ][spq] [GEM3][barg3] [GEMLT][barlt] [FS][qvfs] [NP][np] | T1 |
| B2 | Current assets · 유동자산 | BS | 분기말 | NCAV = 유동자산 − 모든 부채(우선주·미적립 연금 포함) — Graham(Tweedy); 유동비율 ≥ 2(최근 분기) — Graham 방어적; FS_ΔLIQUID — QV; WC · WCTA · CLCA · Altman — QMJ; 투하자본(자산법) = 고정자산 + 유동자산 − 유동부채 − 현금 — DAM | [NCAV][gran] [Graham][grad] [FS][qvfs] [QMJ][qmj] [DAM][damr] | T1 |
| B3 | Cash & short-term investments · 현금및현금성자산 + 단기금융상품(단기투자자산) | BS | 분기말 | 금융자산 FA(#1; 운영 현금 분리 불가 → 전액 금융) — NP; 투하자본 = 부채 + 자본 − 현금 · EV = 시가 자본 + 시가 부채 − 현금 — DAM; EV 에서 초과현금 차감 — Greenblatt; 운전자본에서 현금성 차감 — QMJ; 비영업자산(16장) — MCK | [NP][np] [DAMV][damv] [GRE][gre] [QMJ][qmj] [MCK][mck] | T1 |
| B4 | Trade receivables · 매출채권 | BS | 분기말 | 순운전자본 = 매출채권 + 재고 + 영업 필요 현금 − 매입채무(음수면 0) — Greenblatt; 비현금 운전자본 — DAM; DSRI — Beneish | [GRE][gre] [DAMV][damv] [Beneish][cfab] | T1 |
| B5 | Inventories · 재고자산 | BS | 분기말 | 순운전자본 — Greenblatt; 비현금 운전자본 — DAM (명시 출처 2계열 — 운전자본 핵심이지만 증거 기준으로 T2) | [GRE][gre] [DAMV][damv] | T2 |
| B6 | Other current operating assets/liabilities · 기타유동자산 · 기타유동부채(선급 · 미수 · 미지급 · 선수 등) | BS (+주석) | 분기말 | 비현금 운전자본 = 재고 + 기타유동자산 + 매출채권 − 매입채무 − 기타유동부채 — DAM | [DAMV][damv] | T2 |
| B7 | Net PP&E · 유형자산(순액) | BS | 분기말 | 순유형자산(유형 투하자본) — Greenblatt; 투하자본의 고정자산 — DAM; AQI · DEPI — Beneish | [GRE][gre] [DAM][damr] [Beneish][cfab] | T1 |
| B8 | Gross PP&E · accumulated depreciation · 유형자산 취득원가 · 감가상각누계액 | BS (주석) | 분기말 · 연 | Cash ROIC 분모(총유형자산) · CFROI — DAM; 순유형자산 = 유형자산 − 감가상각누계액 — Greenblatt | [DAM][damr] [GRE][gre] | T2 |
| B9 | Intangibles · goodwill · 무형자산 · 영업권 | BS | 분기말 | 유형 투하자본은 무형자산 제외(ROA 의 총자산과 대비) — Greenblatt; AQI(지출 자산화 탐지) — Beneish | [GRE][gre] [Beneish][cfab] | T2 |
| B10 | Investments in associates/JVs · 관계기업 · 공동기업 투자 | BS | 분기말 | 지분증권 투자는 관계사 영업에 대한 투자 → 영업자산(손익 = Other Items) — NP; 타사 소수지분 보유는 자산법 투하자본에서 빠지고 자본법엔 남는다 — DAM; 비영업자산 가치평가(16장) — MCK; (추론) 지주·계열 출자가 많은 한국에서 분류 선택이 RNOA·EV 를 크게 바꾼다 | [NP][np] [DAM][damr] [MCK][mck] | T1 |
| B11 | Other long-term financial assets · 장기금융상품 · 기타 금융자산(투자자산) | BS | 분기말 | 금융자산 FA 에 'investments and advances–other'(#32, 대부분 채무증권) 포함 — NP; 비영업자산 — MCK | [NP][np] [MCK][mck] | T2 |
| B12 | Deferred tax assets/liabilities · 이연법인세자산 · 부채 | BS | 분기말 | 이연법인세부채 = 영업부채, 암묵 이자 계산에서 제외(#35) — NP; 재구성 재무상태표의 이연법인세(20장) — MCK | [NP][np] [MCK][mck] | T2 |
| B13 | Current liabilities · 유동부채 | BS | 분기말 | 유동비율 — Graham; FS_ΔLIQUID — QV; WC · CLCA — QMJ; 투하자본(자산법) — DAM; DTOA 의 총부채 = 장기부채 + 유동부채(전체) — Barra GEM3 · CNE5 정의 | [Graham][grad] [FS][qvfs] [QMJ][qmj] [DAM][damr] [GEM3][barg3] | T1 |
| B14 | Trade payables · 매입채무 | BS | 분기말 | 순운전자본 차감 — Greenblatt; 비현금 운전자본 — DAM; 영업부채 예시(매입채무 · 미지급임금 · 연금 · 이연세) — NP | [GRE][gre] [DAMV][damv] [NP][np] | T1 |
| B15 | Income taxes payable · 당기법인세부채(미지급법인세) | BS | 분기말 | WC = 유동자산 − 유동부채 − 현금성 + 단기차입 + 미지급법인세 — QMJ | [QMJ][qmj] | T3 |
| B16 | Short-term borrowings & current portion of LTD · 단기차입금 · 유동성장기부채(유동성사채 포함) | BS (+주석 차입금 명세) | 분기말 | FO = 유동부채 중 차입금(#34) + 장기부채(#9) + 우선주 — NP; WC 정의 · LEV · TOTD 의 DLC — QMJ; 부채 = 단기 + 장기 차입(매입채무·무이자부채 제외) — DAM | [NP][np] [QMJ][qmj] [DAMV][damv] | T1 |
| B17 | Long-term debt · 사채 · 장기차입금 | BS | 분기말 | MLEV = (시가자본 + 우선주 + 장기부채) ÷ 시가자본 · BLEV = (자본 + 우선주 + 장기부채) ÷ 자본 — Barra; DLTT — QMJ; ΔLEVER(장기부채 ÷ 총자산) — QV(F/FS); 장기부채 ÷ 운전자본 0~100% — Graham 방어적; #9 — NP | [GEM3][barg3] [QMJ][qmj] [FS][qvfs] [Graham][grad] [NP][np] | T1 |
| B18 | Total (interest-bearing) debt · 총차입금(이자부부채) | BS | 분기말 · 최근 FY | D/E = 최근 FY 총부채 ÷ 장부가 — MSCI Quality; 금융 레버리지 = 최근 총부채 ÷ 장부가 — S&P; EV 의 이자부부채 — Greenblatt; 투하자본 · EV — DAM; TOTD = DLTT + DLC + MIBT + PSTK(DISS) — QMJ | [MSQ][msq] [SPQ][spq] [GRE][gre] [DAMV][damv] [QMJ][qmj] | T1 |
| B19 | Net defined benefit liability · 순확정급여부채(확정급여채무 − 사외적립자산) | BS (주석) | 분기말 · 연 | 연금부채 = 영업부채 — NP; 미적립 연금·의료 의무는 자본법 투하자본에선 빠지고 자산법엔 포함 — DAM; NCAV 에서 미적립 연금부채 차감 — Graham(Tweedy); 23장 *Retirement Obligations* — MCK | [NP][np] [DAM][damr] [NCAV][gran] [MCK][mck] | T1 |
| B20 | Provisions · 충당부채 | BS (주석) | 분기말 | 21장 *Provisions and Their Corresponding Reserves* — MCK | [MCK][mck] | T3 |
| B21 | Total liabilities · 부채총계 | BS | 분기말 | NCAV(모든 부채 차감) — Graham; OENEG = 1(부채 > 자산) · FUTL · BE 대체식(AT − LT − MIB) — QMJ; 부채 + 우선주 = 영업부채 + 금융부채 — NP | [NCAV][gran] [QMJ][qmj] [NP][np] | T1 |
| B22 | Total equity (incl. NCI) · 자본총계(연결, 비지배 포함) | BS | 분기말 | 투하자본 · ROE 의 장부 자본 — DAM; 주주지분 SEQ(BE 출발점) — QMJ; 자본잠식률 계산(연결은 비지배 제외해 적용) — KRX | [DAMV][damv] [QMJ][qmj] [KRX결산][krxy] | T1 |
| B23 | Equity attributable to owners of parent · 지배기업 소유주지분 | BS | 분기말 (기초·기말) | PBR = 주가 ÷ (분기말 지배지분 자본총계 ÷ 유통주식수) · ROE 분모(기초·기말 지배지분) — KRX 지표; BTOP = 최근 보고 보통주 장부가 ÷ 시가총액 — Barra; BE/ME — AQR FFV; ROE = TTM EPS ÷ 최근 BVPS — MSCI · S&P; BE = 주주지분 − 우선주 — QMJ; CSE — NP; PBR · ROE(최근 2년 평균) — KRX 밸류업 | [KRX지표][krxi] [GEM3][barg3] [FFV][ffv] [MSQ][msq] [SPQ][spq] [QMJ][qmj] [NP][np] [밸류업][krxv] | T1 |
| B24 | Non-controlling interests · 비지배지분 | BS | 분기말 | NOA = NFO + CSE + MI(#38) · FLEV = NFO ÷ (CSE + MI) · MSR = CSE ÷ (CSE + MI) — NP; LEV · TOTD 의 MIBT, BE 대체식의 MIB — QMJ; 16장 *Noncontrolling Interests* — MCK; 연결 자본총계에서 비지배 제외(자본잠식) — KRX | [NP][np] [QMJ][qmj] [MCK][mck] [KRX결산][krxy] | T1 |
| B25 | Share capital (common · preferred) · 자본금(보통주 · 우선주) | BS | 분기말 · 연 | 자본잠식률 = (자본금 − 자기자본) ÷ 자본금 · 50% 이상 관리종목 · 전액잠식 상장폐지 절차 — KRX 정기결산 안내; 최근 사업연도 자본잠식 종목 제외 — KRX 밸류업 | [KRX결산][krxy] [밸류업][krxv] | T2 |
| B26 | Preferred stock · 우선주(장부가 · 주식수 · 시가) | BS (+시장) | 분기말 | MLEV · BLEV 의 우선주(PE) — Barra; LEV · TOTD · BE 의 PSTK — QMJ; FO 에 우선주(#130) — NP; EV 에 우선주 포함 — Greenblatt; NCAV 에서 우선주 차감 — Graham(Tweedy); (추론) 한국 우선주는 대부분 자본·별도 상장이라 미국식 '금융부채' 처리를 그대로 옮기면 안 된다 | [GEM3][barg3] [QMJ][qmj] [NP][np] [GRE][gre] [NCAV][gran] | T1 |
| B27 | Retained earnings · 이익잉여금 | BS | 분기말 · 연 | Altman Z(1.4 × RE ÷ AT) — QMJ; 청정잉여 조정의 대안 계산(ΔRE − NI + 순배당; 주식배당·소각이 왜곡) — NP | [QMJ][qmj] [NP][np] | T2 |
| B28 | Treasury stock (amount · shares) · 자기주식(금액 · 주식수) | BS (+주식 현황) | 분기말 | 유통주식수 = 발행주식 − 자기주식(BPS · EPS) — KRX 지표; 자사주 소각(주주환원) — KRX 밸류업; FS_NEQISS(자사주 매입 − 발행) — QV; 우선주 자기주식(#227) — NP | [KRX지표][krxi] [밸류업][krxv] [FS][qvfs] [NP][np] | T1 |
| B29 | Accumulated OCI · 기타포괄손익누계액(해외사업환산 · 금융자산 평가 · 재측정 등) | BS | 분기말 | 누계 잔액(#230 · #238)의 변동 = 청정잉여 조정(CSA) — NP | [NP][np] | T2 |
| B30 | Hybrid capital · 신종자본증권(영구채) · 전환·상환우선주 등 | BS (자본/부채 · 주석) | 분기말 | 16장 *Valuing Hybrid Securities* — MCK; (추론) K-IFRS 에선 영구채가 자본(지배 또는 비지배)으로 잡혀 레버리지·BE 를 바꿀 수 있다 | [MCK][mck] | T3 |

### C. 현금흐름표 (CF) — 5행

| # | 개념 (영문 · 국문) | 재무제표 | 필요 주기 | 이 항목을 쓰는 지표 (지표명 — 출처) | 근거 링크 | 등급 |
|---|---|---|---|---|---|---|
| C1 | Cash flow from operations · 영업활동현금흐름 | CF | 분기(누적) → TTM · 연 이력 | F_CFO · F_ACCRUAL(CFO > ROA) · FS_ACCRUAL — QV(AAII); 이익의 발생액 성분과 평균회귀 · 현금흐름의 질 — CFA 학습목표; *Accruals – Cashflow Statement Version* — Barra GEMLT; STA(QV 3장 — 산식 미확인) | [FS][qvfs] [CFA-Q][cfaq] [GEMLT][barlt] [QV][qvt] | T1 |
| C2 | Capital expenditure · 유형자산의 취득(+ 무형자산의 취득) | CF | 분기(누적) → TTM · 연 이력 8 | 순자본적지출 = capex − 감가상각 · 재투자율 = (순 capex + Δ운전자본) ÷ EBIT(1−t) · FCFF — DAM; CFOA 의 CAPX — QMJ; FS_FCFTA(FCF ÷ 총자산) — QV; 8년 누적 FCF ÷ 총자산(프랜차이즈) — QV(Gray 인터뷰); *Capital Expenditure Growth*(투자의 질) — Barra GEMLT | [DAMV][damv] [QMJ][qmj] [FS][qvfs] [QV-FP][qvfp] [GEMLT][barlt] | T1 |
| C3 | Equity issuance · repurchases · retirements · 유상증자(주식 발행) · 자기주식 취득·처분 · 소각 | CF (+공시 · 주식 현황) | 분기 · 연 | F_EQISS(보통주 발행 없음) · FS_NEQISS(매입 > 발행) — QV; *Issuance Growth*(투자의 질) — Barra GEMLT; EISS = −log(분할조정 주식수 변화) — QMJ; 최근 2년 연속 배당 또는 자사주 소각 — KRX 밸류업 | [FS][qvfs] [GEMLT][barlt] [QMJ][qmj] [밸류업][krxv] | T1 |
| C4 | Net debt issuance · 차입금·사채의 차입·상환(순증감) | CF | 분기 · 연 | FCFE = NI − 순 capex − Δ비현금 운전자본 − 순채무상환 — DAM; DISS = −log(총부채 변화, 재무상태표 기반) — QMJ | [DAMV][damv] [QMJ][qmj] | T2 |
| C5 | Interest paid/received · income taxes paid · 이자의 지급·수취 · 법인세의 납부 | CF | 분기(누적) | 영업 세금 → 현금 영업 세금 전환(20장) — MCK; 실효세율 = 납부세액 ÷ 과세소득 — DAM; (추론) K-IFRS 는 이자·배당 현금흐름의 분류를 선택하게 해 CFO 비교성이 흔들릴 수 있다(원문 미확인) | [MCK][mck] [DAMV][damv] | T3 |

### D. 주식수 · 기타 — 3행

| # | 개념 (영문 · 국문) | 재무제표 | 필요 주기 | 이 항목을 쓰는 지표 (지표명 — 출처) | 근거 링크 | 등급 |
|---|---|---|---|---|---|---|
| D1 | Shares outstanding · 발행주식수(보통 · 우선) · 분기말 유통주식수(자기주식 제외) · 가중평균 유통주식수 | 기타(주식 현황) | 분기 | BPS · EPS 분모 — KRX 지표; BVPS · TTM EPS — MSCI · S&P; 5 FY 주당 매출·이익 회귀 — Barra; 분할조정 주식수(EISS) · 주당 성장 — QMJ | [KRX지표][krxi] [MSQ][msq] [SPQ][spq] [GEM3][barg3] [QMJ][qmj] | T1 |
| D2 | Split / bonus / consolidation adjustment · 주식분할 · 병합 · 무상증자 조정계수 | 기타(이벤트) | 이벤트 | 분할조정 주식수 SHROUT_ADJ — QMJ; 기업이벤트 조정 반영 — KRX 지표 | [QMJ][qmj] [KRX지표][krxi] | T2 |
| D3 | Analyst consensus (EPS · DPS · 장기 성장률 · 예측치 분산) · 컨센서스 | 기타(비재무제표 — 재무 DB 범위 밖) | 월 · 일 | 예측 E/P(EPIBS · EPFWD) · 장·단기 예측 성장(EGRLF · EGIBS) · 예측 D/P · 예측 E/P 표준편차(이익 변동성) — Barra USE4 · GEM3 · CNE5 · GEMLT | [USE4L][baru] [GEM3][barg3] [CNE5][barc5] [GEMLT][barlt] | T2 |

**표 1 보충 — 수집 형태에 주는 요구**
- **이력 길이**: QV 프랜차이즈 = 8년(기하평균 ROA·ROC · 8년 누적 FCF · 마진 성장·안정) · MSCI 이익 변동성 = 5 FY · Barra 성장 = 5 FY · QMJ 성장·NPOP = 5년 · QMJ EVOL = 분기 ROE 60분기(최소 12; 분기 없으면 연 ROE 5년). → 1998~ 분기 이력을 끊김 없이(단절 표식과 함께) 갖는 것이 곧 이 지표들의 성립 조건.
- **TTM 구성이 출처마다 다르다**: Barra ETOP = 최근 FY 이익 + (당기 누적 중간치 − 전년 동기 누적 중간치) · KRX = 직전 4개 분기의 3개월 실적 합. → 3개월값 · 누적값 · 연간값을 모두 수집. 4분기 단독값은 사업보고서 연간 − 3분기 누적으로 유도(추론).
- **'최근(latest)' 대 '최근 FY'**: BVPS · BTOP 은 최근 보고 잔액, MSCI D/E 는 최근 FY 잔액 → 분기말 잔액과 회계연도말 표식이 함께 필요.
- **시장 데이터 결합**: EV · MLEV · E/P · B/P · 배당수익률은 시가총액·주가가 필요 — 재무 DB 와 같은 날짜 축(가용일 기준)으로 붙여야 한다.
- **업종 예외**: S&P 는 금융·부동산에 발생액을 쓰지 않고 ROE·레버리지만 · Greenblatt 는 금융·유틸리티 제외 · MSCI 는 결측 규칙(ROE 또는 D/E 결측 → 제외, 이익 변동성 결측 → 두 변수로) → 업종 코드와 금융업 서식 계정 체계가 별도로 필요(퀀티 금융업 계정은 미확인).

### §2.1 Penman 재구성 → 원천 계정 대응 (NP 부록 측정 → K-IFRS 계정 · 대응은 추론)

| NP 개념 | NP 측정 (Compustat 항목 번호) | K-IFRS 대응 원천 (추론) |
|---|---|---|
| FA 금융자산 | 현금·단기투자(#1) + 기타 투자·대여(#32) | 현금및현금성자산 · 단기금융상품 · 장기금융상품 · 채무증권 · 대여금 |
| OA 영업자산 | 총자산(#6) − FA | 자산총계 − 위 |
| FO 금융부채 | 유동부채 중 차입금(#34) + 장기부채(#9) + 우선주(#130) − 우선주 자기주식(#227) + 우선주 미지급배당(#242) | 단기차입금 · 유동성장기부채·사채 · 사채 · 장기차입금 · (리스부채) · (우선주 처리 — 한국은 통상 자본, 결정 필요) |
| CSE 보통주 자본 | 보통주 자본(#60) + #227 − #242 | 지배기업 소유주지분(우선주 자본 처리 결정 후) |
| MI | 소수주주지분(#38) | 비지배지분 |
| NOA · OL | NOA = NFO + CSE + MI · OL = OA − NOA | 계산(매입채무 · 미지급비용 · 순확정급여부채 · 이연법인세부채 등이 OL) |
| Core NFE | 이자비용(#15) × (1 − t) + 우선주배당(#19) − 이자수익(#62) × (1 − t) | 금융원가 중 이자비용 · 금융수익 중 이자수익(주석) · 법정세율(메타) |
| UFE | Δ매도가능증권 평가조정(#238) | 기타포괄손익누계액 중 채무증권 평가 |
| CNI | 순이익(#172) − 우선주배당 + CSA(Δ#238 + Δ#230) | 지배 당기순이익 + 지배 기타포괄손익 |
| OI | NFE + CNI + MII(#49) | 계산 |
| UOI | (영업외손익 #190 − 지분법 #55) × (1 − t) + 특별항목(#17) × (1 − t) + 비경상·중단(#48) + Δ환산조정(#230) | 기타수익 · 기타비용 · 중단영업손익 · 해외사업환산손익 |
| Other Items | 지분법 이익(#55) | 지분법손익 |
| 한계세율 | 연방 법정세율 + 주세 2% | 법인세 법정세율(+지방소득세) — 외부 표 |
| io(영업부채 암묵 이자) | 1년 무위험이자율 × (OL − 이연세·ITC #35) | 시장 무위험이자율 · 이연법인세부채 |

### §2.2 구성 관례 — 출처 간 공통점과 차이

| 관례 | 출처별 선택 | 원천 DB 에 주는 요구 |
|---|---|---|
| 분모 시점 | DAM: 전기말 투하자본(평균을 쓰는 분석가도 있다고 명시) · NP: RNOA = OI_t ÷ NOA_{t−1} · KRX ROE: 기초·기말 지배 자본 · S&P: 2개 FY 평균 총자산 · Piotroski: 기초 총자산 대 FS: 최근 총자산 | 분기말 잔액 시계열(기초 = 전기말) |
| 현금 | NP: 현금 전액 금융자산 · DAM: 투하자본·EV 에서 현금 차감 · QMJ: 운전자본에서 현금성 차감 · Greenblatt: 초과현금만 EV 차감 | 현금 · 단기금융상품 · 장기금융상품 분리 |
| 세율 | DAM: 실효 또는 한계 — 실납부세액 금지 · NP: 법정 한계세율 | 법인세비용 · 세전이익 + 법정세율 표(외부) |
| 부채 범위 | MSCI·S&P: 총부채(Total Debt) · Barra DTOA: 장기부채 + 유동부채 전체 · QMJ: 장단기 차입 + 비지배 + 우선주 · DAM: 이자부부채(매입채무 제외) | 차입금 세부(단기 · 유동성장기 · 사채 · 장기 · 리스)와 유동부채 총액 둘 다 |
| 장부 자본 | Barra: 최근 보고 보통주 장부가 · QMJ: 주주지분 − 우선주(대체식 3단계) · KRX: 지배지분 자본총계 | 지배 · 비지배 · 우선주 자본 분리 |
| 영업/금융 분류 | S&P 발생액 = 순영업자산 변화 · GEMLT 발생액(재무상태표판·현금흐름표판) · NP NOA · MCK 11장 | 재무상태표 전 항목을 영업/금융으로 나눌 수 있는 세부 계정 |
| 이력 · 결측 | QV 8년 · MSCI·Barra 5 FY · QMJ 60분기 · MSCI 결측 규칙 | 연속 이력 + 결측 사유 표식 |

---

## §3 표 2 — 한국 구성 주의점 (제도 → 팩터 구성 · 시점)

| # | 제도 | 공식 출처가 정한 것 | 팩터 구성 · PIT 영향 | 근거 | 확인 |
|---|---|---|---|---|---|
| K1 | 사업보고서 기한 | 사업연도 경과 후 90일 이내 금융위·거래소 제출(자본시장법 제159조①). 12월 결산 2026년분 기한 3.31, 연장신고서 제출 시 5영업일 이내 연장, 미제출 시 다음날 관리종목(KRX 2026 안내) | 연간 확정치의 공개 상한은 3.31 이 아니라 회사별 접수일(연장 법인은 4월 초). pit.md C4 의 '연간 = 익년 3/31' 고정일은 연장 법인에서 최대 약 1주 미래참조 → **접수일 필드 필요**. 윤년·휴일 산정 규칙은 원문 미확인 — 고정일보다 실제 접수일이 안전 | [§159][law159] [KRX결산][krxy] | ✔ |
| K2 | 반기·분기보고서 기한 | 반기(6개월)·분기(3·9개월) 보고서를 기간 경과 후 45일 이내 제출(제160조①). 최초로 사업보고서 제출대상이 된 법인은 그날부터 5일 이내 직전 반기·분기보고서 제출(제160조② · 2025.1.21 신설) | 12월 결산 계산상 5/15 · 8/14 · 11/14(휴일 이월 전) — pit.md 고정일 5/15·8/15·11/15 는 통상 기간엔 보수적. 신규 상장사의 상장 전 분기 재무는 상장 무렵 한꺼번에 공개될 수 있음 → 접수일 기준 가용 처리 | [§160][law160] | ✔ |
| K3 | 연결 분·반기 60일 특례 | 연결재무제표 기준으로 작성한 반기·분기보고서는 '그 최초의 사업연도와 그 다음 사업연도'에 한해 60일 이내 제출 가능(제160조① 단서). 금융위 2010 Q&A: IFRS 도입 초기 2년 동안 15일 연장된 60일; 2011 의무적용사 중 자산 2조원 이상 = 2011~2012, 2조원 미만 = 2013~2014. 2011년 1분기 첫 IFRS 공시: 일반기업 5.16, 2조원 이상·종속회사 보유 = 개별·연결 5.30 | 해당 연도 연결 분·반기 값은 계산상 5/30 · 8/29 · 11/29 까지 늦을 수 있음 → **pit.md 고정일(5/15·8/15·11/15)을 쓰면 2011~2014 연결 분기치에서 최대 약 2주 미래참조**. 조문상 그 뒤에도 '연결 기준 최초 2개 사업연도'에 다시 적용될 수 있음 → 접수일 필수 | [§160][law160] [금융위2010][fsc10] | ✔ |
| K4 | K-GAAP 시기 연결 사업보고서 기한 | 금융위 2010 Q&A 각주: 종전 기준에서 개별 사업보고서 90일, 연결보고서는 자산 2조원 이상 90일 · 2조원 미만 120일(분·반기는 종전에도 45일) | 2010 회계연도 이전 연결 수치는 소형사의 경우 약 4월 말에야 공개 → '익년 3/31' 고정일 미래참조. 2010 이전 주된 공시는 개별 → 연결·개별 구분 저장과 구간별 기본값(2010 이전 = 개별) 결정 필요 | [금융위2010][fsc10] | ✔ |
| K5 | 2011 K-IFRS 의무 적용 | 조기 적용이 아닌 일반기업은 2011.1.1 이후 최초 개시 회계연도부터 IFRS; 2009년부터 적용 14사(유가 7 · 코스닥 7), 2010.3 현재 조기 적용 56사; 의무 적용 대상 1,925사(상장 1,735 · 2009.12 기준). 첫 IFRS 연도엔 직전연도 기초 재무상태표를 추가 비교 표시; 연결 범위는 실질지배력 기준 | 2009~2010 횡단면에 K-GAAP·K-IFRS 혼재 → 회계기준 표식. 2011 보고서의 2010 비교 수치는 IFRS 재작성치 — 벤더가 2010 값을 재작성치로 덮어썼다면 2010년 시점 판단에 미래 정보 → **최초 공시값 이력 필요**. 연결 범위 변화로 자산·부채·비지배지분 수준 단절 | [금융위2010][fsc10] | ✔ |
| K6 | 연결 중심 공시 · 주재무제표 | 금융위: 법적 실체보다 경제적 실체(연결) 중심으로 상장·공시 제도 개편(Q9). KRX '공시기준 재무제표': 종속회사 없음 = 개별, 있음 = 연결(자본잠식) · 연결/별도(매출액 50억), 지주회사 = 연결; 연결 자본총계는 비지배지분 제외. KRX 투자지표: 분기말 연결(종속회사 없으면 개별), 작성기준이 기중 바뀌면 분기별 3개월 실적 단순 합산(연결 = 지배지분 순이익, 개별 = 당기순이익) | 연결·별도 **둘 다** 수집 + 주재무제표 · 종속회사 유무 표식. 종속회사 취득·처분으로 기준이 바뀐 분기의 TTM 은 KRX 합산 규칙으로 재현 가능. 관리종목 판단(유니버스 위생)은 지표마다 다른 재무제표 기준 | [금융위2010][fsc10] [KRX결산][krxy] [KRX지표][krxi] | ✔ |
| K7 | 자산 2조원 미만 기업의 연결 분·반기 시작 | 금융위 2010 Q&A: 일반기업은 2011년 1분기 재무제표를 IFRS 로 5.16 까지 공시(Q12) · 연결 분·반기 60일 시기를 2조원 미만 = 2013~2014 로 적시(Q10 각주) | (해석) 2011~2012 소형사 분·반기는 개별(별도) 기준, 연간은 연결 → 같은 TTM 창 안에 기준이 섞인다. 2013년부터 연결 분·반기. 수집 후 분기별 기준 표식으로 실측 확인 | [금융위2010][fsc10] | ✔ (해석 포함) |
| K8 | 영업이익 표시 | 금융위 2025-12-18: IFRS 가 영업손익 등 중간합계를 규율하지 않아 국내는 영업손익 추가 표시를 의무화('12년~). 학술 초록(국문): K-IFRS 가 영업이익을 구체적으로 정의하지 않아 생긴 혼란 끝에 회계기준원이 2012년 9월 K-GAAP 과 같은 방법으로 산출·공시하도록 함(영문 초록은 2010년 9월 개정을 언급 — 도입기 규정으로 보이나 원문 확인 필요; K-GAAP 방식 = 매출총이익 − 판관비는 통상 정의). K-IFRS 1118: '27.1.1 이후 시작 회계연도(’26 조기 적용 허용) — 영업손익 = 투자·재무 범주에 속하지 않는 잔여 범주로 확대 · '현행 기준 영업손익'은 주석에 별도 기재(시행 3년 후 연장 검토) · 경영진 정의 성과측정치 주석 의무 | 영업이익 계열(EBIT/EV · ROC · 영업이익률)은 2011(및 재작성 2010) ↔ 2012~ ↔ 2027~(조기 적용 2026) 사이 정의 단절 → 회계연도별 '영업이익 정의' 표식. 2027~ 주석의 '현행 기준 영업손익'을 별도 항목으로 수집해야 시계열 연속성 유지. 조정영업이익(기업 자율 주석)은 비교 불가로 취급 | [금융위2025][fsc25] [KCI-영업이익][kcioi] | ✔ / ◇ |
| K9 | 지배주주 귀속 이익·자본 | KRX 투자지표: PER · ROE = 직전 4분기 지배지분 당기순이익, PBR · ROE = 지배지분 자본총계, 배당성향 = 지배 순이익 기준. KRX 정기결산: 연결 자본총계 적용 시 비지배지분 제외. 금융위 Q28: 지주회사는 지배회사 지분 귀속 순이익으로 비교 | 총액 · 지배 · 비지배를 모두 수집. E/P · B/P · ROE 는 지배 기준으로 계산해야 KRX·FnGuide 공표치와 맞는다. 비지배지분이 큰 지주·금융그룹에서 총액을 쓰면 왜곡. (K-GAAP 시기 소수주주지분 처리는 미확인) | [KRX지표][krxi] [KRX결산][krxy] [금융위2010][fsc10] | ✔ |
| K10 | 비12월 결산 · 결산기 변경 | 법정 기한은 '각 사업연도 경과 후' · '사업연도 개시일부터 6·3·9개월' 기준(제159·160조). KRX 투자지표: 12월 이외 결산법인은 반영 시점이 다름 · 결산기 변경 시 산출 대상 기간이 1년 미만일 수 있음 · 같은 사업연도에 보고서가 여럿이면 최근 1개만 | 저장 키 = (회계기간 시작·종료일, 보고서 종류) — 달력 분기 라벨로 쓰지 말 것. TTM 은 연속 4개 회계분기, 결산기 변경 연도는 기간 길이(개월) 표식. 가용 시점도 회계기간 종료일 기준으로 계산 | [§159][law159] [§160][law160] [KRX지표][krxi] | ✔ |
| K11 | 정정 공시 | 금융위는 사업보고서등 미제출 · 중요사항 거짓 기재 · 누락 시 이유를 제시·공고하고 정정을 명할 수 있음(제164조②). KRX 투자지표: 기업이벤트 조정 반영 · 정기보고서 미제출·지연 시 반영 누락·지연 | 정정으로 과거 값이 바뀐다 — 최신 정정값만 보관하면 as-of 재현 불가(미래참조). 원공시값 · 정정값 · 각 접수일을 함께 수집(퀀티가 원값을 보존하는지는 미확인 — 확인 대상). 자진 정정의 규정 조문은 미확인 | [§164][law164] [KRX지표][krxi] | ✔ / 일부 ✗ |
| K12 | 잠정실적 · 내부결산실적 공시 | KRX 정기결산: 주총 6주 전(연결 4주 전) 내부결산 → 확정 시 '매출액 · 영업손익 · 당기순손익 30%(대규모법인 15%) 이상 증감' 및 자본잠식 50% · 매출액 50억 미만 공시; 내부결산실적 관련 공시 유형에 '영업(잠정)실적(공정공시)' 포함. 언론(2024): '영업(잠정)실적' · '연결재무제표기준영업(잠정)실적' 명칭, 정기보고서 전에 나오는 공정공시의 일종 | 연간·분기 수치의 최초 공개는 정기보고서보다 이르다 → 정보 시점을 앞당길 근거이자, 감사 전 값이라 확정치와 다를 수 있음 → **잠정치 값 · 공시 시각을 확정치와 별도 열로**. pit.md 의 'Q4 +45d' 같은 앞당김은 회사별 잠정 공시가 있었을 때만 정당화 가능(해석). 잠정 공시 항목 구성의 규정 원문은 미확인 | [KRX결산][krxy] [아주][aju] | ✔ / ◇ |
| K13 | 감사보고서 | KRX 정기결산: 외부감사인은 주총 1주 전까지 회사에 감사보고서 제출, 상장법인은 받은 당일 공시(종속회사가 있으면 연결·별도 감사의견과 재무내용 모두); 감사의견 비적정 · 범위제한 한정 · 자본잠식 · 매출 50억 미만 → 관리종목·상장폐지 사유 | 감사 확정 연간치의 공개(대개 3월 중) ≠ 사업보고서 접수일 → 감사보고서 제출일 별도 수집. 감사의견은 관리종목·상장폐지 위험 표식(측정 축 위생 MC1 과 연결) | [KRX결산][krxy] | ✔ |
| K14 | 분기보고서 제도 시작 | 학술 초록: 분기보고서는 2000년 시작 | 1998~1999 은 반기·사업보고서만 있었을 가능성 → '분기 1998~' DB 의 1·3분기 값이 실제 공시인지 벤더 추정·보간인지 확인 필요 | [KCI-분기][kciq] | ◇ (공식 ✗) |
| K15 | 리스 회계 변경 | 공식 원문 미확인 | 운용리스 부채화 시점에 부채 · EV · EBITDA · ROIC 단절 가능 → Damodaran 식 리스 자본화 조정은 변경 이전 구간에만. 시행 연도·전환 방식은 수집 전 확인 | — | ✗ |
| K16 | 대규모법인(자산 2조원) | KRX: 대규모 법인 = 최근 사업연도말 자산총액 2조원 이상(15% 문턱). 금융위 Q13: IFRS 단계 적용의 2조원 판단은 2010년말 개별 재무제표 자산총액 | 2조원 표식이 공시 문턱 · 연결 60일 특례 시기를 가른다 → 연도별 '대규모법인' 표식 + 판단 기준 재무제표(개별/연결) | [KRX결산][krxy] [금융위2010][fsc10] | ✔ |
| K17 | 벤더(FnGuide) 산출 지표의 반영 시점 | KRX 투자지표(FnGuide 제공): 12월 결산 기준 사업보고서 → 다음해 5월, 1분기 → 6월, 반기 → 9월, 3분기 → 12월 반영(정기보고서 공시 시점에 따라 차이) | 벤더가 계산한 비율을 쓰면 반영 월이 PIT 시점. 원천 계정으로 직접 계산하면 접수일 기준으로 더 이르게(정확하게) 쓸 수 있다 → 원천 계정 수집의 이유 | [KRX지표][krxi] | ✔ |

---

## §4 확인 못 한 출처 (근거로 쓰지 않음)

- **Penman 교재 본문**(유료) — 5판 목차만. Nissim & Penman 2001 RAST **출판판 본문** — 1999 워킹페이퍼로 대체.
- **McKinsey Valuation 본문**(11장 NOPAT · 투하자본 정의식) — 목차만. McKinsey 기사 *A long-term look at ROIC* — 접속 시간 초과.
- **CFA 커리큘럼 본문**(회원 포털) — 공개 요약·학습목표만. Beneish 8변수 산식 — 블로그엔 이름·계수만.
- **Graham 원서**(*Security Analysis* · *The Intelligent Investor*) — AAII 2차만(방어적 스크린 기준값은 AAII 변형).
- **Greenblatt 원서 부록**(O'Reilly 403) · magicformulainvesting.com(정의 없음) — AAII 2006 2차만.
- **Quantitative Value 본문**(STA · SNOA · PROBM · PMAN · PFD 산식) · Alpha Architect 블로그(403) — 목차·2차만.
- **MSCI Barra**: USE4 Methodology/Empirical Notes(사본 403) · CNE6(미발견) · **KRE2·KRE3 설명자**(고객 문서 — 초록만) · GEMLT 설명자 산식.
- **S&P Quality Indices Methodology 원문**(spglobal.com 403) — Invesco 투자설명서로 대체.
- **AQR 실무 논고** — QMJ · FFV 외 미검토.
- **FnGuide 지수 방법론서**(FnIndex — 스크립트 구동 사이트, 브라우저 접속 거부) — 퀄리티 · 밸류 · 스마트베타 모두 미확인.
- **KRX 스마트베타 · 퀄리티 · 밸류 · 고배당 지수 방법론서** — 밸류업 지수 보도자료만 확인.
- **국내 증권사 퀀트 리포트의 팩터 정의** — 접근 가능한 공개본을 찾지 못함.
- **유가증권시장 공시규정 조문**(공정공시 제15조 등 · 잠정실적 항목 구성) — KRX 안내문·언론으로만.
- **K-IFRS 1001 원문 · 회계기준원 2012 개정 공표문 · 회계기준적용의견서 12-1**(조정영업이익) — 금융위 2025 보도자료 + 학술 초록으로만.
- **「증권의 발행 및 공시 등에 관한 규정」 정정보고서 조항** · **K-IFRS 1116(리스) 시행 공식 자료** · **분기보고서 도입(2000) 공식 근거** · **법정 기한 산정(초일 불산입 · 휴일 이월) 근거** — 미확인.

---

## §5 메타 항목이 필요한 이유 (요약)

원천 계정 값만으로는 "그 값을 **언제**, **어떤 기준으로** 알 수 있었나"를 재구성할 수 없다. 위 제도 사실이 각각 다음 메타를 요구한다.

| 메타 항목 | 필요한 이유 | 표 2 |
|---|---|---|
| 보고서 접수일(·시각) + 보고서 종류(사업/반기/분기) | 법정 기한(90일 · 45일)은 상한일 뿐 — 연결 60일 특례(2011~2014 집중), K-GAAP 연결 120일, 5영업일 연장이 있어 고정일 규칙(pit.md C4)은 일부 연도·회사에서 미래참조 | K1~K4 |
| 회계기간 시작·종료일 · 결산월 · 기간 구분(3개월/누적/연간) | 비12월 결산 · 결산기 변경(1년 미만 기간) · TTM 구성(KRX 4분기 합 · Barra 중간치 차감식) · 4분기 단독값 유도 | K10 |
| 연결/별도(개별) 구분 · 주재무제표 · 종속회사 유무 · 지주회사 표식 | KRX 공시기준이 지표마다 다르다(자본잠식 = 연결 지배, 매출 50억 = 연결/별도) · 2011~2012 소형사 분·반기 = 별도 · 기준 변경 분기의 합산 규칙 | K6 · K7 |
| 회계기준(K-GAAP/K-IFRS · 조기 적용) · 기준서 판(영업이익 2012 · 2027, 리스) | 정의 단절 — 표식이 없으면 영업이익·부채 계열은 연도 간 비교 불가 | K5 · K8 · K15 |
| 원공시값 / 정정값 + 각 접수일(as-first-reported) | 정정명령·자진 정정으로 과거 값이 바뀜 — 최신값만 쓰면 as-of 재현 불가. IFRS 첫해의 2010 재작성 비교치도 같은 문제 | K11 · K5 |
| 잠정실적 · 내부결산실적 값과 공시 시각 | 정기보고서보다 먼저 나온 정보(공정공시 · 30%/15% 변동 공시) — 정보 시점을 앞당길 근거이자 확정치와의 오차 원천 | K12 |
| 감사보고서 제출일 · 감사의견 | 감사 확정치의 가용 시점, 관리종목·상장폐지 사유(유니버스 위생) | K13 |
| 대규모법인(자산 2조) 표식 + 판단 기준 재무제표 | 공시 문턱(15%)과 연결 60일 특례 시기를 가른다 | K16 · K3 |
| 지배/비지배 귀속 구분 | KRX·FnGuide 지표가 지배 기준 — 총액과 섞으면 PER·ROE·PBR 이 공표치와 어긋난다 | K9 |
| 주식수 조정계수 · 단위 · 통화 | 주당 지표 이력(QMJ 분할조정 주식수 · KRX 기업이벤트 조정) | (표 1 D1·D2) |
| 벤더 지표 반영 월 | 벤더가 계산한 비율을 쓸 때는 반영 시점이 곧 PIT | K17 |
| 분기 공백 표식(1998~1999) | 분기보고서 2000년 시작(2차 확인) — 실제 공시 없는 분기를 추정치와 구분 | K14 |

업계도 같은 결론이다 — MSCI Barra GEMLT 데이터시트는 백테스트의 전방 편향을 줄이는 **시점(PIT) 재무 데이터**를 모형 개선점으로 내세운다([GEMLT][barlt]). Qvest 쪽에선 위 메타 중 **접수일 · 연결 구분 · 정정 이력** 세 가지가 pit.md C4 고정일 규칙을 실제 접수일 규칙으로 바꾸는 데 바로 필요하다.

<!-- 참조 링크 정의 -->
[np]: https://business.columbia.edu/sites/default/files-efs/pubfiles/1063/nissimpenmanratio.pdf
[pen]: https://www.mheducation.com/highered/product/financial-statement-analysis-and-security-valuation-penman.html
[damr]: https://pages.stern.nyu.edu/~adamodar/pdfiles/papers/returnmeasures.pdf
[damv]: https://pages.stern.nyu.edu/~adamodar/New_Home_Page/datafile/variable.htm
[dams]: https://pages.stern.nyu.edu/~adamodar/New_Home_Page/spreadsh.htm
[mck]: https://content.e-bookshelf.de/media/reading/L-14075493-e03ab943c2.pdf
[cfaf]: https://www.cfainstitute.org/insights/professional-learning/refresher-readings/2026/financial-analysis-techniques
[cfaq]: https://www.cfainstitute.org/en/membership/professional-development/refresher-readings/evaluating-quality-financial-reports
[cfab]: https://rpc.cfainstitute.org/blogs/enterprising-investor/2013/detetecting-earnings-manipulation-and-fraud-a-light-tutorial-on-probit-analysis
[gran]: https://www.aaii.com/journal/article/tweedy-browne-what-has-worked-in-investing-2
[grad]: https://www.aaii.com/journal/article/17789-benjamin-grahams-defensive-investor-non-utility-screen
[gre]: https://www.aaii.com/journal/article/the-magic-formula-approach-to-stockpicking
[qvt]: https://content.e-bookshelf.de/media/reading/L-725334-2e81a60553.pdf
[qvfs]: https://www.aaii.com/journal/article/simple-methods-to-improve-the-piotroski-f-score
[qvfp]: https://www.fool.com/investing/general/2013/02/21/what-does-a-high-quality-stock-really-mean.aspx
[qvcxo]: https://cxoadvisory.com/fundamental-valuation/a-few-notes-on-quantitative-value
[baru]: https://arcana-40407e622969.intercom-attachments-1.com/i/o/re6xlf6l/2354407926/74d54f9e1cbc828a6f9f36d5d564/Barra+U_S_+Equity+Model%E2%80%94Long-TermVersion+-+USE4L+Datasheet.pdf
[baruse4]: https://www.msci.com/documents/10199/242721/Barra_US_Equity_Model_USE4.pdf
[barg3]: https://arcana-40407e622969.intercom-attachments-1.com/i/o/re6xlf6l/2354385968/5f3f7ebebe5bbbd30e292f30b625/GEM3+Descriptor+Details.pdf
[barc5]: https://zhiqiang.org/media/images/notes/202106/ea021009818156021bdc3e00d100b151.pdf
[barlt]: https://arcana-40407e622969.intercom-attachments-1.com/i/o/re6xlf6l/2351156250/8af2d2a7fedd2f86e56ad49d61d1/GEMLTL+Datasheet+-+Barra+Global+Total+Market+Model+for+Long+Term+Investors.pdf
[msq]: https://www.msci.com/indexes/documents/methodology/2_MSCI_Quality_Indexes_Methodology_20250520.pdf
[spq]: https://www.sec.gov/Archives/edgar/data/1209466/000119312525190420/d56632d497k.htm
[qmj]: https://research-api.cbs.dk/ws/portalfiles/portal/60211462/lasse_heje_pedersen_et_al_quality_minus_junk_publishersversion.pdf
[ffv]: https://www.aqr.com/-/media/AQR/Documents/Journal-Articles/JPM-Fact-Fiction-and-Value-Investing.pdf
[krxi]: https://kind.krx.co.kr/external/dst/guidebook/Investment_Indicators_KOR.pdf
[krxv]: <https://files-scs.pstatic.net/2024/09/24/JUh7Blj8mX/(보도자료)+한국거래소,+「코리아+밸류업+지수」+발표.pdf>
[krxy]: https://kind.krx.co.kr/external/notice/dst/20260202/kospi_1.pdf
[fsc10]: https://www.fsc.go.kr/po020201/27291
[fsc25]: https://fsc.go.kr/po010105/85886
[law159]: https://korea.legal/wiki/%ec%9e%90%eb%b3%b8%ec%8b%9c%ec%9e%a5%ea%b3%bc-%ea%b8%88%ec%9c%b5%ed%88%ac%ec%9e%90%ec%97%85%ec%97%90-%ea%b4%80%ed%95%9c-%eb%b2%95%eb%a5%a0-%ec%a0%9c159%ec%a1%b0/
[law160]: https://korea.legal/wiki/%ec%9e%90%eb%b3%b8%ec%8b%9c%ec%9e%a5%ea%b3%bc-%ea%b8%88%ec%9c%b5%ed%88%ac%ec%9e%90%ec%97%85%ec%97%90-%ea%b4%80%ed%95%9c-%eb%b2%95%eb%a5%a0-%ec%a0%9c160%ec%a1%b0/
[law164]: https://korea.legal/wiki/%ec%9e%90%eb%b3%b8%ec%8b%9c%ec%9e%a5%ea%b3%bc-%ea%b8%88%ec%9c%b5%ed%88%ac%ec%9e%90%ec%97%85%ec%97%90-%ea%b4%80%ed%95%9c-%eb%b2%95%eb%a5%a0-%ec%a0%9c164%ec%a1%b0/
[lawgo]: <https://www.law.go.kr/법령/자본시장과금융투자업에관한법률>
[kcioi]: https://koreascience.kr/article/JAKO201420340967498.page?lang=ko
[kciq]: https://hanyang.scholarworks.kr/handle/2021.sw.hanyang/181310?mode=full
[aju]: https://www.ajunews.com/view/20240501141200270
