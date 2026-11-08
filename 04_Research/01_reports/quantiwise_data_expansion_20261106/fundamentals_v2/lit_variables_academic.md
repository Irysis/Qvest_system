# 재무제표 기반 팩터 문헌이 요구하는 원천 재무 항목 — 근거 표 (학술 문헌 판)

- 작성: 2026-11-08 · Q(조사 에이전트)
- 용도: 퀀티와이즈(FnGuide) 재무 수집 DB(분기 · 한국 전 상장 종목 · 1998~)의 **항목 목록**을 정하는 근거
- 단위: 팩터 정의가 아니라 **그 정의에 들어가는 원천 계정** (예: GP/A → 매출액 · 매출원가 · 자산총계)
- 인용 규칙: 실제로 연 원문 · 문서만 인용한다. 못 연 것은 **미확인**이다. 게재판을 못 열고 초고(working paper)만 연 경우 그 판을 적는다. **'Q 메모'는 문헌 근거가 아니라 설계 판단**이다(기준서 · 벤더 사전 미열람 — 검증 대상).
- 실행 제약: R · Python 실행 없음. 쓰기 = 이 파일 하나.

---

## 0. 읽는 법

**등급** (요청 규칙 그대로)
- **T1** = 표준 팩터(FF5 · q5 · QMJ · F-score) 구성에 쓰이거나, 특성 계열 3개 이상에서 쓰임
- **T2** = 문헌의 이상현상(JKP 153 특성 또는 C&Z 신호)에 쓰임
- **T3** = 대체식 · 보조 계산 또는 소수 신호에만 쓰임
- 괄호 안 = 판정 이유. `(기반)` = 계정은 아니지만 시점 · 표본 구성에 필수인 식별 정보.

**특성 계열** = JKP 문서 표 9 의 13개 테마 군(Accruals · Debt Issuance · Investment · Low Leverage · Low Risk · Momentum · Profit Growth · Profitability · Quality · Seasonality · Size · Short-Term Reversal · Value). "≥3군" = 그 원천 항목이 3개 이상 군의 특성에 들어감.

**주기 표기**
- `연` = 원 정의가 연간 자료만 씀
- `연+Q` = 원 정의는 연간이지만, JKP 처럼 분기 자료로 최신화하려면 분기 값(재무상태표 = 분기말 잔액, 손익 · 현금흐름 = 최근 4개 분기 합)이 필요 — JKP 는 연간 · 분기 특성을 따로 만들어 더 최신 값을 쓴다([JKP-d] §6.2)
- `Q필수` = 원 정의 자체가 분기 값(대개 발표일과 함께)을 씀

**특성명 표기**: JKP 코드명(예 `gp_at`) — 뒤의 논문은 JKP 표 9 가 붙인 원 논문. C&Z 신호는 `C&Z:약어`. "(원문 미확인)" = 그 논문 본문을 못 열어 JKP · C&Z 문서로만 항목을 확인했다는 뜻.

**근거 키**: §5 출처 목록(열람 상태 포함).

**백본 문서의 핵심 사실** (표 전체의 전제)
- JKP: 원천 변수 목록 = `avars_inc` · `avars_cf` · `avars_bs` · `avars_other`(emp) ([JKP-c]). 회계 자료는 회계기간 종료 **4개월 뒤** 공개로 가정하고 최대 18개월까지 사용(`lag_to_public=4, max_data_lag=18`) ([JKP-d] §6.2 · [JKP-m]). 분기 손익 · 현금흐름은 최근 4개 분기 합, 분기 항목 이름 = 연간 이름 + `q`(분기 값) 또는 `y`(연초 누계) ([JKP-d] §6.2–6.3).
- C&Z: 연간 = 결산월 + 6개월부터 12개월 사용, 분기 = 분기말 + 3개월(실적 발표월 RDQ 가 더 늦으면 그 달) · RDQ 가 분기말 + 6개월 초과면 버림. 추출 조건 `consol='C' · indfmt='INDL' · datafmt='STD' · popsrc='D' · curcd='USD'` ([CZ-a] · [CZ-q]).

---

## 1. 표 1 — 원천 항목 (74행)

### 1-A. 재무상태표 (BS) — 34행

| # | 개념 (영문 · 국문) | Compustat | 표 | 주기 | 이 항목을 쓰는 특성 (특성명 — 논문) | 근거 | 등급 |
|---|---|---|---|---|---|---|---|
| 1 | Total assets · 자산총계 | AT (ATQ) | BS | 연+Q | `at_gr1` — Cooper·Gulen·Schill 2008 · I/A — HXZ 2015 · Inv — FF 2015 · `gp_at` 분모 — Novy-Marx 2013 · ROA(IBQ/1분기 전 ATQ) — HXZ 2015 부록 · F-score ROA·CFO·ACCRUAL·TURN 분모 — Piotroski 2000 · JKP 13개 군 거의 전부의 분모 | [JKP-c] [JKP-d] [HXZ15] [KF] [NM13] [P00] | T1 (FF5·q5·QMJ·F) |
| 2 | Current assets · 유동자산 | ACT (ACTQ) | BS | 연+Q | ΔCA — Sloan 1996 · `cowc_gr1a`·`coa_gr1a` — RSST 2005(원문 미확인) · F-score ΔLIQUID(유동비율) — Piotroski · Z-score 운전자본 · O-score — QMJ 안전성(AFP) · `aliq_at`·`ca_cl` (JKP) | [S96] [JKP-d] [P00] [AFP] | T1 (F·QMJ) |
| 3 | Cash and short-term investments · 현금및현금성자산 + 단기금융상품 | CHE (CHEQ) | BS | 연+Q (CHS: Q필수) | ΔCash 차감 — Sloan 1996 · `cash_at` — Palazzo 2012 · `netdebt_me` — Penman·Richardson·Tuna 2007 · OA = AT − CHE — C&Z:NOA(HHTZ 2004) · CASHMTA — CHS 2008 · `kz_index` — Lamont 외 2001 · QMJ 운전자본에서 차감 — AFP | [S96] [JKP-d] [CZ-NOA] [CHS] [AFP] | T1 (QMJ·≥3군) |
| 4 | Receivables · 매출채권 | RECT | BS | 연+Q | ΔRECT 차감 — 현금기준 영업이익 Cop(BGLN 2016 · q5 Eg) · `dsale_drec` — Abarbanell·Bushee 1998 · `tangibility`(0.715×RECT) — Hahn·Lee 2009 · `rec_days`·`rec_turnover` (JKP) | [BGLN16] [GQ] [JKP-c] [JKP-d] | T1 (q5) |
| 5 | Inventories · 재고자산 | INVT | BS | 연+Q | `inv_gr1` — Belo·Lin 2012 · `inv_gr1a` — Thomas·Zhang 2002 · `ppeinv_gr1a` — Lyandres·Sun·Zhang 2008 · `dsale_dinv` — Abarbanell·Bushee 1998 · ΔINVT — Cop(BGLN · q5) · `tangibility`(0.547×INVT) | [JKP-d] [BGLN16] [GQ] | T1 (q5·≥3군) |
| 6 | Prepaid expenses · 선급비용 | XPP | BS | 연 | ΔXPP 차감 — Cop(BGLN 2016 부록 · q5 기술문서) | [BGLN16] [GQ] | T1 (q5) — JKP `cop_x` 는 발생액으로 대체해 XPP 없이 계산 |
| 7 | Other current assets · 기타유동자산 | ACO | BS | 연+Q | JKP `ca_x` 대체식(RECT+INVT+CHE+ACO) · C&Z:GrLTNOA(Fairfield 외 2003) | [JKP-c] [CZ] | T3 |
| 8 | Net PP&E · 유형자산(순액) | PPENT | BS | 연+Q | `lnoa_gr1a` — Fairfield·Whisenant·Yohn 2003 · `kz_index`(전년 PPENT 분모) — Lamont 외 2001 · C&Z:grcapx(capx·ppent) — Anderson·Garcia-Feijoo 2006 | [JKP-c] [JKP-d] [CZ] | T2 |
| 9 | Gross PP&E · 유형자산(취득원가 총액) | PPEGT | BS | 연+Q | `ppeinv_gr1a` — Lyandres 외 2008 · `tangibility`(0.535×PPEGT) — Hahn·Lee 2009 · C&Z:AbnormalAccruals — Xie 2001 | [JKP-c] [JKP-d] [CZ] | T2 |
| 10 | Intangible assets · 무형자산 | INTAN | BS | 연+Q | `lnoa_gr1a` — Fairfield 외 2003 · `aliq_at`(장부자산 유동성) — Ortiz-Molina·Phillips 2014 | [JKP-c] [JKP-d] | T2 |
| 11 | Goodwill · 영업권 | GDWL | BS | 연 | C&Z:AssetLiquidityBook/Market — Ortiz-Molina·Phillips 2014 · JKP 원천 목록에만 있음 | [CZ] [JKP-c] | T3 |
| 12 | Long-term investments · 장기투자자산(관계기업 · 장기금융상품 등) | IVAO | BS | 연+Q | `ncoa_gr1a`·`nncoa_gr1a`·`nfna_gr1a`·`lti_gr1a`·`taccruals_at` — 모두 RSST 2005(원문 미확인) · JKP 표 9 기준 Investment·Debt Issuance·Seasonality·Accruals 4개 군 · C&Z:DelLTI | [JKP-c] [JKP-d] [CZ] | T1 (≥3군) |
| 13 | Short-term investments · 단기투자자산 | IVST | BS | 연+Q | `sti_gr1a`·`nfna_gr1a`·`taccruals_at` — RSST 2005(원문 미확인) · 3개 군 · C&Z:DelSTI·DelNetFin | [JKP-d] [CZ] | T1 (≥3군) |
| 14 | Other assets · 기타비유동자산 | AO | BS | 연+Q | `lnoa_gr1a` — Fairfield 외 2003 · C&Z:GrLTNOA | [JKP-c] [CZ] | T2 |
| 15 | Total liabilities · 부채총계 | LT (LTQ) | BS | 연+Q (CHS: Q필수) | BE 3순위 AT − LT — FF/KF · HXZ 분기 ATQ − LTQ · `ncol_gr1a` — RSST · Z-score ME/LT · O-score 부채>자산 더미 (JKP) · TLMTA — CHS 2008 · `lt_gr1`·`cash_lt` (JKP) | [KF] [HXZ15] [JKP-c] [JKP-d] [CHS] | T1 (FF5·q5·QMJ) |
| 16 | Current liabilities · 유동부채 | LCT (LCTQ) | BS | 연+Q | ΔCL — Sloan 1996 · `cowc_gr1a`·`col_gr1a` — RSST · F-score ΔLIQUID — Piotroski · Z·O-score — QMJ | [S96] [JKP-d] [P00] [AFP] | T1 (F·QMJ) |
| 17 | Debt in current liabilities · 단기차입금 + 유동성장기부채 | DLC (DLCQ) | BS | 연+Q | ΔSTD 를 발생액에서 제외 — Sloan 1996 · `debt_gr3` — Lyandres 외 2008 · Tobin's q = (ME+DLTT+DLC)/AT — HMXZ q5 · LEV·DISS — AFP · `col_x` = CL − DLC (JKP) · `netdebt_me` | [S96] [JKP-c] [HMXZ] [GQ] [AFP] | T1 (q5·QMJ) |
| 18 | Accounts payable · 매입채무 | AP | BS | 연+Q | ΔAP 가산 — Cop(BGLN 2016 · q5) · `ap_days`·`ap_turnover` (JKP) | [BGLN16] [GQ] [JKP-c] | T1 (q5) |
| 19 | Income taxes payable · 미지급법인세(당기법인세부채) | TXP | BS | 연+Q | ΔTP 를 발생액에서 제외 — Sloan 1996 · QMJ 운전자본에 가산 — AFP · JKP `cl_x` 대체식 | [S96] [AFP] [JKP-c] | T1 (QMJ) |
| 20 | Accrued expenses · 미지급비용 | XACC | BS | 연 | ΔXACC 가산 — Cop(BGLN 2016 · q5) | [BGLN16] [GQ] | T1 (q5) |
| 21 | Deferred revenue (current · long-term) · 선수수익 · 계약부채 (유동 · 비유동) | DRC, DRLT | BS | 연 | Δ(DRC+DRLT) 가산 — Cop(BGLN 2016 · q5) · C&Z:DelDRC — Prakash·Sinha 2013 | [BGLN16] [GQ] [CZ] | T1 (q5) |
| 22 | Other current liabilities · 기타유동부채 | LCO | BS | 연+Q | JKP `cl_x` 대체식(AP+DLC+TXP+LCO) · C&Z:GrLTNOA | [JKP-c] [CZ] | T3 |
| 23 | Long-term debt · 장기차입금 · 사채 | DLTT (DLTTQ) | BS | 연+Q | F-score ΔLEVER — Piotroski(원 정의는 유동성 부분 포함) · Tobin's q — q5 · LEV·DISS — AFP · `debt_*`·`debtlt_*` (JKP) · `ncol_x` = LT − CL − DLTT — RSST · C&Z:NOA 영업부채 | [P00] [GQ] [AFP] [JKP-c] [CZ-NOA] | T1 (F·q5·QMJ) |
| 24 | Other liabilities · 기타비유동부채 | LO | BS | 연+Q | `lnoa_gr1a`(−LO) — Fairfield 외 2003 · JKP `at_x` 대체식 | [JKP-c] | T2 |
| 25 | Deferred taxes & investment tax credit (BS) · 이연법인세부채(· 투자세액공제) | TXDITC (TXDB, ITCB · TXDITCQ) | BS | 연+Q | BE 가산 — FF 1993 · HXZ 분기 BE(TXDITCQ) · Novy-Marx 2013(TXDITC → TXDB/ITCB) · JKP `be_x` · BGLN 2016(결측 = 0) | [FF93] [HXZ15] [NM13] [JKP-c] [BGLN16] | T1 (FF5·q5) |
| 26 | Minority (non-controlling) interest, BS · 비지배지분 | MIB (MIBQ) | BS | 연+Q | OP 분모 = BE + 비지배지분 — Ken French 현행 정의 · LEV = −(DLTT+DLC+MIB+PSTK)/AT 와 DISS — AFP · 주주지분 대체 AT − (LT + MIB) — AFP · C&Z:NOA 영업부채 · `bev_x` (JKP) | [KF] [AFP] [CZ-NOA] [JKP-c] | T1 (FF5 현행·QMJ) |
| 27 | Preferred stock — redemption · liquidating · par · 우선주(상환가액 · 청산가액 · 액면) | PSTKRV, PSTKL, PSTK (PSTKRQ, PSTKQ) | BS | 연+Q | BE 차감 위계 — FF 1993 · HXZ 분기(PSTKRQ → PSTKQ) · Daniel·Titman(item 56 → 10 → 130) · `fnl_gr1a`(부채+우선주) — RSST · LEV — AFP · C&Z:NetPayoutYield(pstkrv) | [FF93] [HXZ15] [DT] [JKP-c] [AFP] [CZ] | T1 (FF5·q5·QMJ) |
| 28 | Stockholders' equity · 자본총계(주주지분) | SEQ (SEQQ) | BS | 연+Q | BE 1순위 — FF 1993 · KF · Novy-Marx 2013 · HXZ(SEQQ) · JKP `seq_x` · Daniel·Titman(item 216) · `kz_db` (JKP) | [FF93] [KF] [NM13] [HXZ15] [JKP-c] [DT] | T1 (FF5·q5) |
| 29 | Common equity · 보통주 자본(장부) | CEQ (CEQQ) | BS | 연+Q | BE 2순위 CEQ + PSTK — KF · HXZ(CEQQ + PSTKQ) · Daniel·Titman(60 + 130) · CLS 2001(item 60) · C&Z:BM·OperProf·NOA | [KF] [HXZ15] [DT] [CLS] [CZ] | T1 (FF5·q5) |
| 30 | Retained earnings · 이익잉여금 | RE (REQ) | BS | 연+Q | Z-score RE/AT — `z_score`(Dichev 1998 귀속; Altman 1968 원문 미확인) · QMJ 안전성 — AFP · C&Z:ZScore | [JKP-d] [AFP] [CZ] | T1 (QMJ) |
| 31 | Invested capital · 투하자본 | ICAPT | BS | 연 | `bev_x` 1순위 (JKP) | [JKP-c] | T3 |
| 32 | Treasury stock · 자기주식 | TSTK (TSTKP) | BS | 연 | 자사주 변동으로 잰 환매(대안) — Boudoukh 외 2007 · C&Z:EBM·NetDebtPrice — Penman 외 2007 | [BMRR] [CZ] | T3 |
| 33 | Postretirement-benefit adjustment · 퇴직후급여 조정 | (DT: item 330 FASB106 조정 · BGLN: postretirement benefit liabilities) | BS | 연 | BE 조정 — Daniel·Titman 2006(차감) · BGLN 2016(가산) | [DT] [BGLN16] | T3 (미국 SFAS 106 특유) |
| 34 | Rare items · 희소 항목 묶음 | OB(수주잔고) · PBNAA 등(연금) · FATB/FATL(건물 · 토지) · DCVT/DM(전환 · 담보부채) | BS·주석 | 연 | C&Z:OrderBacklog(Rajgopal 외 2003) · C&Z:FR(Franzoni·Marin 2006) · C&Z:realestate(Tuzel 2010) · C&Z:ConvDebt·secured(Valta 2016) | [CZ] | T3 |

### 1-B. 손익계산서 (IS) — 22행

| # | 개념 (영문 · 국문) | Compustat | 표 | 주기 | 이 항목을 쓰는 특성 (특성명 — 논문) | 근거 | 등급 |
|---|---|---|---|---|---|---|---|
| 35 | Sales (net) · 매출액 | SALE (SALEQ) | IS | 연+Q (RS·`saleq_su`: Q필수) | `sale_gr1`·`sale_gr3` — LSV 1994 · `sale_me` — Barbee 외 1996 · `at_turnover` — Haugen·Baker 1996 · F-score MARGIN·TURN — Piotroski · GMAR 분모 — AFP · SURGE — Jegadeesh·Livnat · RS — HXZ 부록 · `saleq_gr1` (JKP) · `ocfq_saleq_std` — Huang 2009 | [JKP-d] [P00] [AFP] [JL] [HXZ15] | T1 (F·QMJ·≥3군) |
| 36 | Total revenue · 수익(매출) 합계 | REVT (REVTQ) | IS | 연+Q | GP = REVT − COGS — Novy-Marx 2013 · OP — BGLN 2016 · Cop — q5 · GPOA(revenue) — AFP · JKP `sale_x` = SALE → REVT 대체 | [NM13] [BGLN16] [GQ] [AFP] [JKP-c] | T1 (q5·QMJ) |
| 37 | Cost of goods sold · 매출원가 | COGS (COGSQ) | IS | 연+Q | GP — Novy-Marx 2013 · OP — FF 2015 · Cop — q5 · F-score MARGIN — Piotroski · `opex_at` = (COGS+XSGA)/AT — Novy-Marx 2011 · `inv_days` (JKP) · C&Z:GrGMToGrSales | [NM13] [FF15] [GQ] [P00] [NM11] | T1 (FF5·q5·QMJ·F) |
| 38 | SG&A · 판매비와관리비 | XSGA (XSGAQ) | IS | 연+Q | OP — FF 2015 · OP = … − (XSGA − XRD) — BGLN 2016 · Cop — q5 · `opex_at` — Novy-Marx 2011 · 조직자본(SG&A 누적) — Eisfeldt·Papanikolaou 2013 · 조직자본(SG&A 의 20%) — Peters·Taylor(2014 초고) · `dsale_dsga` — Abarbanell·Bushee | [FF15] [BGLN16] [GQ] [NM11] [EP] [PT] | T1 (FF5·q5) |
| 39 | R&D expense · 연구개발비 | XRD (XRDQ) | IS·주석 | 연+Q | OP·Cop 가산 — BGLN 2016 · q5(결측 = 0) · `op_at`·`op_atl1`·`cop_at` (JKP `op_x` = EBITDA + XRD) · `rd_me`·`rd_sale` — Chan·Lakonishok·Sougiannis 2001 · `rd5_at` — Li 2011(CLS 가중) · 지식자본 δ 15% — Peters·Taylor | [BGLN16] [GQ] [JKP-c] [CLS] [PT] | T1 (q5·≥3군) |
| 40 | Advertising · 광고선전비 | XAD | IS·주석 | 연 | C&Z:AdExp — Chan 외 2001 · C&Z:BrandInvest·BrandCapital — Belo 외 2014 · C&Z:GrAdExp — Lou 2014 · `adv_sale` (JKP, 153 밖) | [CZ] [JKP-c] | T2 |
| 41 | Staff expense · 인건비 | XLR | IS·주석 | 연 | `staff_sale` (JKP, 153 밖) | [JKP-c] | T3 |
| 42 | Depreciation & amortization · 감가상각비 · 무형자산상각비 | DP (DPQ) | IS·CF | 연+Q | 발생액 −Dep — Sloan 1996 · CFOA·ACC — AFP · O-score FFO = (PI+DP)/LT — JKP · `kz_cf` = (NI+DP)/PPENT — JKP · `lnoa_x`(+DP) — Fairfield · `ebit_x` 대체 EBITDA − DP (JKP) · CF/P — KF · Daniel·Titman · FCF = NI+DP−ΔWC−CAPX — Novy-Marx 2013 | [S96] [AFP] [JKP-d] [JKP-c] [KF] [DT] [NM13] | T1 (QMJ·≥3군) |
| 43 | Operating income after D&A (EBIT) · 영업이익(감가상각 후) | OIADP · EBIT (OIADPQ) | IS | 연+Q | 이익 정의(item 178) — Sloan 1996 · `ebit_bev`·`ebit_sale` — Soliman 2008 · Z-score EBIT — AFP 서술 · C&Z:roic | [S96] [JKP-d] [AFP] [CZ] | T1 (QMJ·≥3군) |
| 44 | Operating income before D&A (EBITDA) · 감가상각 전 영업이익 | OIBDP · EBITDA (OIBDPQ) | IS | 연+Q | `ebitda_mev` — Loughran·Wellman 2011 · FF OP 분자 = EBITDA − XINT(JKP `ope_x` 문서 주석) · JKP `z_score`(EBITDA 사용) · `profit_cl`·`ebitda_debt` (JKP) · C&Z:EntMult | [JKP-d] [JKP-c] [CZ] | T1 (FF5 분자·≥3군) |
| 45 | Interest expense · 이자비용 | XINT (XINTQ) | IS | 연+Q | OP = … − XINT — FF 2015(`ope_be`) · KF · `int_debt`·`ebit_int` (JKP) · JKP `pi_x` 대체식 · C&Z:OperProfLag_q(xintq) | [FF15] [KF] [JKP-c] [CZ] | T1 (FF5) |
| 46 | Non-operating income · special items · 영업외손익 · 특별항목 | NOPI, SPI | IS | 연 | JKP `pi_x` 대체식 · `spi_at`·`nri_at` (JKP, 153 밖) · C&Z:roic(nopi) | [JKP-c] [CZ] | T3 |
| 47 | Pretax income · 법인세비용차감전순이익 | PI (PIQ) | IS | 연+Q | O-score FFO — JKP · AFP(세전이익/총부채) · TI/BI = PI/NI — HXZ 2015 부록 · `pi_nix` — Lev·Nissim 2004 | [JKP-d] [AFP] [HXZ15] | T1 (QMJ — O-score) |
| 48 | Total income tax · 법인세비용 | TXT (TXTQ) | IS | 연+Q | `tax_gr1a` — Thomas·Zhang 2011 · 당기분 대체 TXT − TXDI — Lev·Nissim(#16 − #50) · `tax_pi` (JKP) · C&Z:ChTax(txtq · 분기) | [JKP-d] [LN04] [CZ] | T2 |
| 49 | Current tax (federal · foreign) · 당기법인세(국내 · 해외) | TXFED, TXFO | 주석 | 연 | TAX = (당기세 ÷ 최고 법정세율) × (1−t) ÷ IB — Lev·Nissim 2004(#63 · #64) · C&Z:Tax | [LN04] [CZ] | T2 |
| 50 | Deferred tax expense · 이연법인세비용 | TXDI | IS·CF | 연 | Lev·Nissim 대체식(#50) · CF/P 이연세 가산(#50) — Daniel·Titman · C&Z:KZ·Tax | [LN04] [DT] [CZ] | T2 |
| 51 | Income before extraordinary items · 계속영업이익(특별항목 전 이익) | IB (IBQ) | IS | 연+Q (ROE·dRoe: Q필수) | ROE = IBQ ÷ 1분기 전 BE — HXZ 2015 · dRoe — HMXZ q5 · ROA = IBQ ÷ 1분기 전 ATQ — HXZ 부록 · F-score ROA·ACCRUAL — Piotroski · E/P — FF 1993 · KF · `ni_be` — Haugen·Baker 1996 · `niq_be`·`niq_at`·`niq_su`·`ni_inc8q` (JKP) · `oaccruals_at` | [HXZ15] [GQ] [P00] [KF] [JKP-c] [JKP-d] | T1 (q5·F·≥3군) |
| 52 | Extraordinary items & discontinued operations · 중단영업손익(· 특별손익) | XIDO (XI, DO) | IS | 연+Q | IB ↔ NI 연결 (JKP `xido_x` · `ni_x` 대체식) · `xido_at`·`nri_at` (JKP, 153 밖) | [JKP-c] | T2 |
| 53 | Net income · 당기순이익 | NI (NIQ) | IS | 연+Q (CHS: Q필수) | ROE·ROA — AFP · `oaccruals_ni`·`taccruals_ni`(NI 절댓값 분모) — Hafzalla 외 2011(원문 미확인) · O-score — JKP · AFP · NIMTA — CHS 2008 · `pi_nix`·TI/BI 분모 — Lev·Nissim · HXZ | [AFP] [JKP-d] [CHS] [HXZ15] | T1 (QMJ) |
| 54 | Noncontrolling interest in income · 비지배지분 귀속 순이익 | MII | IS | 연+Q | JKP `ni_x` 대체식 PI − TXT − MII (Compustat IB 가 지배 귀속임을 전제) | [JKP-c] | T3 (문헌 직접 사용 드묾 — 한국은 §1-E·표 2 #19) |
| 55 | Preferred dividends · 우선주배당 | DVP | IS·이익처분 | 연 | E/P 지분이익 = IB + 손익 이연세 − 우선주배당 — FF 1993 · C&Z:RDS — Landsman 외 2011 | [FF93] [CZ] | T2 |
| 56 | EPS excluding extraordinary items · 주당순이익(계속영업) | EPSPX (EPSPXQ) | IS | 연+Q (SUE: Q필수) | SUE = 4분기 전 대비 EPSPXQ 변화 ÷ 그 변화의 표준편차(8분기, 최소 6) — HXZ 2015(Foster·Olsen·Shevlin 1984 계승; FOS 본문 미확인) · SUE(계속영업 EPS) — Jegadeesh·Livnat · C&Z:EarningsSurprise · C&Z:EarningsPersistence — Francis 외 2004 | [HXZ15] [JL] [CZ] | T2 |

### 1-C. 현금흐름표 (CF) — 10행

| # | 개념 (영문 · 국문) | Compustat | 표 | 주기 | 이 항목을 쓰는 특성 (특성명 — 논문) | 근거 | 등급 |
|---|---|---|---|---|---|---|---|
| 57 | Operating cash flow · 영업활동현금흐름 | OANCF (OANCFY = 연초 누계) | CF | 연+Q (`ocfq_saleq_std`: Q필수) | F-score CFO·ACCRUAL — Piotroski · `oaccruals_at` = (NI − OANCF)/AT (JKP) · `ocf_at`·`ocf_at_chg1` — Bouchaud 외 2019 · `ocf_me` — Desai·Rajgopal·Venkatachalam 2004 · `ocfq_saleq_std` — Huang 2009 · C&Z:cfp | [P00] [JKP-c] [JKP-d] [CZ] | T1 (F·≥3군) |
| 58 | Capital expenditures · 유형자산의 취득 | CAPX (CAPXY = 누계) | CF | 연+Q | `capx_gr1` — Xie 2001 · `capx_gr2`·`capx_gr3` — Anderson·Garcia-Feijoo 2006 · `capex_abn` — Titman·Wei·Xie 2004 · CFOA — AFP · `fcf_me` — LSV 1994 · 총투자율 — Peters·Taylor | [JKP-d] [AFP] [PT] | T1 (QMJ·≥3군) |
| 59 | Sale of common & preferred stock · 주식발행(유상증자) 수입 | SSTK (SSTKY) | CF | 연+Q | F-score EQ_OFFER(JKP `f_eqis` = SSTK = 0) — Piotroski · `eqnetis_at`·`netis_at` — Bradshaw·Richardson·Sloan 2006(원문 미확인) · 발행 차감(item 108) — Boudoukh 외 2007 · C&Z:XFIN·NetEquityFinance | [P00] [JKP-d] [BMRR] [CZ] | T1 (F) |
| 60 | Purchase of common & preferred stock · 자기주식 취득 | PRSTKC (PRSTKCY) · 글로벌 PURTSHR | CF | 연+Q | 환매 = item 115 + 우선주 감소 — Boudoukh 외 2007 · JKP `eqbb_x` → `eqnetis_at`·`eqnpo_me`·`eqpo_me` · C&Z:NetEquityFinance·ShareRepurchase | [BMRR] [JKP-c] [JKP-d] [CZ] | T2 |
| 61 | Dividends · 배당금(보통주 · 총) | DVC, DVT, DV (DVY · DVPSXQ) | CF·IS | 연+Q | 배당 = DVC(item 21) — Boudoukh 외 · JKP `div_x` = DVT → DV → `eqpo_me`·`eqnpo_me`·`kz_dv`·`intrinsic_value`(Frankel·Lee 1998) · 분기 BE clean-surplus 보충(DVPSXQ × 주식수) — global-q 기술문서 · R&D/배당 — CLS | [BMRR] [JKP-c] [GQ] [CLS] | T2 |
| 62 | LT debt issuance · reduction · 장기차입 증가 · 상환 | DLTIS, DLTR (LTDCH) | CF | 연 | `dbnetis_at`·`dltnetis` — BRS 2006(원문 미확인) · C&Z:NetDebtFinance·XFIN · C&Z:DebtIssuance — Spiess·Affleck-Graves 1999 | [JKP-c] [JKP-d] [CZ] | T2 |
| 63 | Change in current debt · 단기차입금 순증감 | DLCCH | CF | 연 | JKP `dstnetis_x` · C&Z:NetDebtFinance | [JKP-c] [CZ] | T2 |
| 64 | Financing · investing cash flows · 재무 · 투자활동현금흐름 | FINCF, IVNCF (FIAO, TXBCOF) | CF | 연 | C&Z:PctTotAcc — Hafzalla 외 2011 · C&Z:TotalAccruals — RSST 2005 · JKP `fincf_x` | [CZ] [JKP-c] | T3 |
| 65 | Working-capital changes (CF statement) · 영업활동 자산 · 부채 변동 | RECCH, INVCH, APALCH, WCAPCH · WCAPT | CF | 연 | Cop 현금흐름표판 — BGLN 2016 표 3 · FCF(WCAPCH) — Novy-Marx 2013 · JKP `ocf_x` 대체식(WCAPT) | [BGLN16] [NM13] [JKP-c] | T3 |
| 66 | Funds from operations · 운영자금 | FOPT (FOPTY) | CF | 연+Q | C&Z:AbnormalAccruals — Xie 2001 · C&Z:OScore · C&Z 분기 누계 변환 대상 | [CZ] [CZ-q] | T3 |

### 1-D. 기타 (주식 · 시점 · 식별 · 외부) — 8행

| # | 개념 (영문 · 국문) | Compustat | 표 | 주기 | 이 항목을 쓰는 특성 (특성명 — 논문) | 근거 | 등급 |
|---|---|---|---|---|---|---|---|
| 67 | Shares outstanding & adjustment factor · 발행주식수 · 수정계수 | CSHO, CSHOQ, CSHPRQ, AJEX · AJEXQ (CRSP SHROUT · CFACSHR) | 기타 | 연+Q(+월) | `chcsho_12m` — Pontiff·Woodgate 2008 · RS = SALEQ/(CSHPRQ × AJEXQ) — HXZ · EISS(분할 조정 주식수) — AFP · 분기 BE 보충(CSHOQ · AJEXQ) — global-q · C&Z:ShareIss1Y/5Y | [JKP-d] [HXZ15] [AFP] [GQ] [CZ] | T1 (q5·QMJ) |
| 68 | Market equity at fiscal year-end · 결산기 시가총액 | PRCC_F × CSHO (JKP ME_FISCAL) | 기타(가격) | 연 | Z-score ME/LT · `kz_q` (JKP) · BM(결산기 주식수 × 종가) — Piotroski · C&Z:NetDebtPrice(csho · prcc_f) | [JKP-d] [P00] [CZ] | T1 (QMJ — Z) · 재무 DB 밖(가격 자료) |
| 69 | Employees · 종업원수 | EMP | 기타(사업보고서) | 연 | `emp_gr1` — Belo·Lin·Bazdresch 2014 · `sale_emp_gr1` — Abarbanell·Bushee 1998 · `ni_emp`·`sale_emp` (JKP) | [JKP-c] [JKP-d] | T2 |
| 70 | Earnings announcement date · 실적 발표일 | RDQ | 기타 | Q필수 | ROE · ROA · SUE · RS · NEI 편입 시점(발표 직후 달) · RDQ > 분기말 검사 · 6개월 낡은 이익 배제 — HXZ 2015 · dRoe — q5 · C&Z 분기 가용월 | [HXZ15] [GQ] [CZ-q] | T1 (q5) |
| 71 | Fiscal period identifiers · 결산월 · 분기 · 기준일 | FYR, FQTR, FYEARQ, DATADATE | 기타 | 연+Q | JKP TTM 유효성(같은 회사 · 결산월 · 통화, fqtr 합 10) · C&Z 중복 제거(gvkey · fyearq · fqtr → 최신 datadate) · FF "역년 t−1 에 끝나는 회계연도" | [JKP-c] [CZ-q] [FF93] | T1 (기반) |
| 72 | Industry classification · 산업분류 | SIC (SICH) | 기타 | 연 | 금융업 제외 — Novy-Marx 2013 · 2011(SIC 6) · HXZ · Jegadeesh·Livnat(금융 · 유틸) · Han 외 2020(한국) · 산업 내 순위 — Eisfeldt·Papanikolaou(FF 17산업) | [NM13] [NM11] [HXZ12] [JL] [HLK20] [EP] | T1 (기반) |
| 73 | Consolidation · currency flags · 연결/별도 · 통화 구분 | CONSOL, CURCD · CURCDQ | 기타 | 연+Q | C&Z 추출 조건 consol='C' · JKP TTM 통화 일치 요건 | [CZ-a] [CZ-q] [JKP-c] | T1 (기반) — 한국은 연결 · 별도 구분자 필수 |
| 74 | Price index (external) · 물가지수 | CPI | 외부 | 연 | 조직자본 디플레이트 — Eisfeldt·Papanikolaou · O-score 자산 디플레이트 — AFP | [EP] [AFP] | T2 (재무 DB 밖) |

**등급 집계**: T1 43행(계정 38 · 가격 1 · 기반 4) · T2 18행 · T3 13행.

### 1-E. K-IFRS 대응 메모 (Q 메모 — 기준서 · 벤더 사전 미열람, 검증 대상)

1. **비용 분류와 감가상각**: K-IFRS 기능별 손익계산서의 매출원가 · 판관비에는 감가상각비가 들어 있다(Q 메모). 반면 Compustat 의 COGS + XSGA 는 감가상각을 뺀 값으로 다뤄진다 — JKP 대체식 EBITDA = SALE − (COGS + XSGA) 가 그 전제다([JKP-d] 표 5 · [JKP-c]; Compustat 매뉴얼 미열람). → 한국 "매출액 − 매출원가 − 판관비" ≈ 감가상각 **후** 영업이익. FF OP · JKP `ope_x` · `op_x` · EBITDA 재현에는 **감가상각비 · 무형자산상각비(분기 포함)** 를 따로 수집해야 한다(현금흐름표 간접법 가산 항목 또는 주석 '비용의 성격별 분류').
2. **영업이익 표시 규정**: K-IFRS 도입 초기 영업이익 구성(기타영업수익 · 비용 포함 여부)의 기준 변경 시점 — 미확인. 2011~2012 영업이익 계열은 따로 점검.
3. **연구개발비**: 판관비(경상연구개발비) · 매출원가(제조경비) · 개발비(자산화)로 흩어진다(Q 메모). BGLN 의 "XSGA − XRD" 는 R&D 가 판관비 안에 있을 때만 성립한다 — 판관비 내 R&D · 손익 비용 처리 총액 · 자산화분을 구분 수집.
4. **지배 · 비지배 귀속**: Compustat IB 는 지배 귀속(JKP 대체식 PI − TXT − MII), SEQ 는 비지배 제외(AFP 가 AT − (LT + MIB) 로 뺌). → 한국은 순이익 · 계속영업이익 · 자본 모두 **지배기업 소유주 귀속분과 비지배지분을 분리** 수집.
5. **이연법인세**: 자산 · 부채 상계 순액 표시가 가능하다(Q 메모) → 이연법인세자산 · 부채를 각각 수집.
6. **이연수익 · 계약부채(XPP · XACC · DRC · DRLT 대응)**: 선급비용 · 미지급비용 · 선수수익 · 선수금 · 계약부채의 계정명이 기준 개정(K-IFRS 1115 시행 시점 — 미확인) 전후로 바뀐다 → 매핑표 필요.
7. **현금흐름표 분기 값**: 분기보고서 현금흐름표는 누계만 있다(Q 메모) → 3개월 = 당기 누계 − 직전 누계, 4분기 = 연간 − 3분기 누계. 이자 · 배당의 영업/투자/재무 분류 선택 차이(미확인)는 OANCF 비교성에 영향.
8. **배당 시점**: 현금흐름표 '배당금의 지급'(지급 기준) vs 결산 배당 결의(다음 해 지급) — payout 특성의 시점 정의 필요.
9. **주식수**: 보통주 · 우선주 발행주식수 · 자기주식수 · 가중평균유통주식수 · 수정계수(액면분할 · 병합 · 무상증자 · 감자).
10. **식별 정보**: 연결/별도/개별 구분 · 주재무제표 여부 · 보고서 종류(1Q · 반기 · 3Q · 연간) · 접수일 · 정정 여부. 프로젝트 PLAN.md 98행은 벤더 재무 코드의 `.M` 접미를 "각 재무년월 주재무제표 기준(추측)"으로 적었다 — 사실이면 그 계열은 2011 에 개별 → 연결로 바뀐다(표 2 #19).
11. **1998~2010 K-GAAP 시기**: 연결은 부속(Doo·Yoon 2024 표 1), 분기 연결 자료 가용성은 미확인. '소수주주지분'(비지배지분의 옛 이름) 매핑 필요.

---

## 2. 표 2 — 정의 함정 (구성 관례 · 시점 관례) — 21행

| # | 주제 | 문헌별 관례 · 함정 | 근거 | 한국 DB 함의 |
|---|---|---|---|---|
| 1 | BE — 주주지분(SE) 위계 | FF 1993: Compustat 주주지분 + 재무상태표 이연세 · ITC − 우선주(p. 8) · KF: SE(Moody's/Compustat) → 보통주 + 우선주 액면 → 자산 − 부채 · Novy-Marx: SEQ → CEQ + PSTK → AT − LT · JKP: SEQ → CEQ + pstk → AT − LT · AFP: SEQ → CEQ + PSTK → AT − (LT + MIB) · HXZ 분기: SEQQ → CEQQ + PSTKQ → ATQ − LTQ(Davis·Fama·French 2000 의 분기판; SEQQ · CEQQ 가 1980 전 커버리지가 넓어서) · Daniel·Titman: 216 → 60+130 → 6−181 | [FF93] [KF] [NM13] [JKP-c] [AFP] [HXZ12] [DT] | K-IFRS 연결 '자본총계'는 비지배지분 포함 → Compustat SEQ 대응 = 지배기업 소유주지분. 연결 수치로 AT − LT 를 쓰면 비지배지분이 BE 에 섞인다(AFP 는 MIB 를 뺀다) |
| 2 | BE — 우선주 위계 | FF 1993 · KF · JKP: 상환 → 청산 → 액면 · HXZ 분기: 상환(PSTKRQ) → 장부(PSTKQ)(청산 단계 없음) · Daniel·Titman: 셋 다 결측이면 BE 결측 · Han 외(한국): 자본총계 − 우선주자본금 | [FF93] [JKP-c] [HXZ12] [DT] [HLK20] | Q 메모: 한국은 우선주 자본금(액면)만 일관 공시 → 위계 최하위만 적용 가능. 우선주 자본금 분리 항목 수집 |
| 3 | BE — 이연법인세 가산 | FF 1993 · KF · HXZ: 재무상태표 이연세 + ITC 가산 · BGLN 2016: 결측이면 0 · Novy-Marx: TXDITC → TXDB/ITCB · Han 외(한국): 가산 없음 | [FF93] [HXZ15] [BGLN16] [NM13] [HLK20] | 가산 여부는 측정 전 고정할 설계 결정. 수집은 이연법인세자산 · 부채 각각 |
| 4 | BE — 미국 특유 조정 | Daniel·Titman: FASB106 조정(item 330) 차감 · BGLN 2016: 퇴직후급여부채 가산 + Davis·Fama·French(2000) Moody's BE 로 결측 보충 | [DT] [BGLN16] | 한국 대응 없음(확정급여부채는 이미 부채) — 수집 불필요, 차이로만 기록 |
| 5 | OP 분자 — 이자 · R&D · 감가상각 | FF 2015: 매출 − 매출원가 − 판관비 − 이자비용("operating profitability minus interest expense") · BGLN 2016: REVT − COGS − (XSGA − XRD) — S&P 가 R&D 를 SG&A 에 합친 조정을 되돌림 · q5 Cop: … + XRD(결측 = 0) · JKP: `ope_x` = EBITDA − XINT 를 FF5 RMW 분자로 겨냥, `op_x` = EBITDA + XRD · C&Z:OperProf = (REVT−COGS−XSGA−XINT)/CEQ(FF 2006 귀속) | [FF15] [BGLN16] [GQ] [JKP-d] [JKP-c] [CZ] | §1-E ①③: 한국 매출원가 · 판관비는 감가상각 포함(Q 메모) → FF OP 재현에 감가상각비 별도 필요. Han 외(한국)는 원 식을 그대로 적용(Ope · Opa) |
| 6 | OP 분모 | FF 2015 초고: t−1 말 BE · KF 현행: BE + 비지배지분 · BGLN 2016: 전년말(t−1) 총자산 · q5 Cop: 총자산 · JKP: `ope_be`(당기 BE) · `ope_bel1`(전기 BE) · `op_at` · `op_atl1` | [FF15] [KF] [BGLN16] [GQ] [JKP-c] | 비지배지분 별도 수집 · 분모 시점(당기/전기)은 변형으로 측정 전 고정 |
| 7 | 매출 정의 — SALE vs REVT | JKP: SALE → REVT · Novy-Marx · BGLN · q5: REVT · Piotroski: net sales · HXZ RS: SALEQ · AFP: revenue / total sales | [JKP-c] [NM13] [GQ] [P00] [HXZ15] [AFP] | 한국: 매출액 vs 영업수익(지주 · 금융 · 서비스) — 둘 다 수집 |
| 8 | 연 · 분기 결합 · TTM | JKP: 연간 · 분기 특성을 따로 만들고 더 최신 값을 씀 · 분기 손익 · 현금흐름 = 최근 4개 분기 합(같은 회사 · 결산월 · 통화, fqtr 합 10일 때만) · 4분기 결측이면 연간으로 대체 · `y`(누계) 항목은 분기화 · C&Z: 누계 → 분기 변환은 sstky · prstkcy · oancfy · fopty 만(capxy · dvy 는 미변환) | [JKP-d] [JKP-c] [CZ-q] | §1-E ⑦: 손익 3개월 · 누계 구분 필드와 보고서 종류 보존 |
| 9 | 연간 자료 시점 | FF: 6월 t 에 역년 t−1 에 끝난 회계연도 · 수익률 7월 t ~ 6월 t+1("BE 가 알려졌음을 확실히") · B/M 의 ME = 12월 t−1(FF 2015: 그사이 주식수 변화 조정) · Novy-Marx: 다음 해 6월 말까지 시차 · JKP: 기말 + 4개월부터 최대 18개월 · C&Z: 결산월 + 6개월부터 12개월 · Sloan · CLS · Lev·Nissim: 기말 + 4개월 · Piotroski: 기말 후 5번째 달 · q5: 4개월 이상 지난 회계연도 · Daniel·Titman: 최소 6개월 · Han 외(한국): 6월 말 t, 회계연도 t−1 | [FF93] [FF15] [NM13] [JKP-d] [JKP-m] [CZ-a] [S96] [CLS] [LN04] [P00] [GQ] [DT] [HLK20] | 4개월은 미국 10-K 제출 관행 근거(Sloan 은 Alford 외 1994 인용) — 한국은 실제 접수일 또는 법정기한 규칙으로 바꾼다. 프로젝트 PIT C4: 연간 = 익년 3/31, 분기 45일+(`.claude/rules/pit.md`). 접수일 필드 필수 |
| 10 | 분기 자료 시점 — 발표일 | HXZ: RDQ 직후 달부터 사용(3/5 또는 3/25 발표 → 4월 초 편입, 분모 = 3분기 BE) · RDQ 가 분기말 이후여야(오류 기록 배제) · 그 분기말이 편입 6개월 이내(낡은 이익 배제) · RDQ 없던 1972 이전: 4개월 이상 지난 분기 · C&Z: 분기말 + 3개월 또는 RDQ 월 중 늦은 쪽, RDQ − 분기말 > 6개월이면 버림, 3개월 유지 · CHS: 2개월 시차 | [HXZ15] [HXZ12] [GQ] [CZ-q] [CHS] | RDQ 대응(Q 메모) = 정기보고서 접수일 또는 잠정실적 공시일. 정정 공시는 원 공시와 구분 보존 |
| 11 | 분기 BE 결측 보충 | global-q: 분기 BE 우선 → 4분기는 연간 BE → 둘 다 없으면 clean surplus 역산(기초 BE = 기말 BE − 분기이익 + 분기배당; 배당 = DVPSXQ × 주식수, AJEXQ 조정), 모든 자료가 편입월보다 4개월 이상 앞서게 | [GQ] | 분기 배당(중간 · 분기배당) · 분기말 주식수 필요 |
| 12 | 결산월 · 비12월 결산 | FF · HXZ · JKP: 결산월 무관('역년 t−1 에 끝나는 회계연도' 또는 기준일 + 시차) · JKP TTM: 4개 분기 결산월 동일 요건 · Eisfeldt·Papanikolaou: 12월 결산만 표본 · C&Z: 같은 fyearq · fqtr 중복은 최신 기준일 | [FF93] [JKP-c] [EP] [CZ-q] | 결산월 변경 이력 보존(변경 연도의 단축 · 연장 회계기간). 열람한 한국 논문 중 비12월 처리 기재 없음 — 미확인 |
| 13 | 표본 필터 — 금융업 · 음(−) BE · 등재 | Novy-Marx 2013 · 2011: SIC 6 제외 · HXZ: 금융 · 음수 BE 제외 · Jegadeesh·Livnat: 금융 · 유틸 · 전날 주가 $5 미만 제외 · Boudoukh: 비금융, BE > 0 · FF 1993: 음수 BE 는 분위 경계 · 포트폴리오에서 제외, CRSP 보통주만, Compustat 2년 등재 뒤 편입(생존 편향) · CHS: 조정 후 남은 음수 BE 는 작은 양수로 · AFP: B/M 은 BE > 0 · Han 외(한국): 금융업 · 자본잠식 기업 제외 | [NM13] [NM11] [HXZ12] [JL] [BMRR] [FF93] [CHS] [AFP] [HLK20] | 금융업 식별 업종코드 · 자본잠식 판정용 자본금 항목 수집(Q 메모) |
| 14 | 발생액 측정 방식 | Sloan: 재무상태표 방식(SFAS 95 가 30년 중 마지막 4년만 시행이라) (ΔCA − ΔCash) − (ΔCL − ΔSTD − ΔTP) − Dep, 평균총자산 · 이익 = OIADP · Piotroski: IB − CFO · JKP: NI − OANCF 우선, 없으면 Δ운전자본 + Δ순비유동영업자산 · BGLN: 변동 결측 = 0, 현금흐름표판(RECCH · INVCH · APALCH) 병행 · 퍼센트 발생액: 순이익 절댓값으로 나눔(Hafzalla — 원문 미확인; JKP `oaccruals_ni`) · Kim 외 2015(한국): 전통 발생액은 이상현상 없음, 퍼센트 발생액은 있음(초록) | [S96] [P00] [JKP-c] [BGLN16] [KKKL15] | 현금흐름표와 재무상태표 양쪽 수집 → 두 방식 모두 재현 가능 |
| 15 | F-score 세부 | Piotroski: LEVER = 장기부채(유동성 부분 포함) ÷ 평균총자산 · TURN = 매출 ÷ 기초총자산(본문) vs 평균총자산(표 1) — 원문 안에서 불일치 · EQ_OFFER = 보통주 발행 여부 · JKP: `f_lev` = DLTT/AT(유동성 부분 제외) · `f_aturn` = SALE/AT(t−12) · `f_eqis` = SSTK = 0 | [P00] [JKP-d] | 유동성장기부채를 단기차입금과 분리 수집해야 원 정의 재현 |
| 16 | Z · O-score 변형 | JKP Z: 1.2 WC/AT + 1.4 RE/AT + 3.3 EBITDA/AT + 0.6 ME/LT + 1.0 SALE/AT(EBIT 자리에 EBITDA) · C&Z:ZScore 변수 목록은 NI · XINT · TXT 로 EBIT 를 구성하는 것으로 보임(코드 미열람) · AFP: EBIT 서술, O-score 자산 = AT + 0.1(ME − BE), CPI 디플레이트 · Altman 1968 · Ohlson 1980 원문 미확인 · Han 외(한국): 연 1% 윈저라이즈 | [JKP-d] [CZ] [AFP] [HLK20] | 결산기 시가총액 · CPI(외부) 필요 |
| 17 | 과세소득 / 장부이익 | Lev·Nissim: 과세소득 = 당기법인세(연방 #63 + 외국 #64; 없으면 총 #16 − 이연 #50) ÷ 최고 법정세율(1973~2000: 48 → 46 → 40 → 34 → 35%), TAX = 과세소득 × (1−t) ÷ IB(#18), 기말 4개월 뒤 · HXZ: TI/BI = PI/NI(NI ≤ 0 제외)로 단순화 · Han 외(한국): 법인세차감전계속사업이익 ÷ 순이익 | [LN04] [HXZ15] [HLK20] | 당기 · 이연 법인세 분리(주석) 수집 여부 결정 · 연도별 법정세율표(외부) |
| 18 | 무형자본 · 조직자본 | CLS: RDC = RD + 0.8RD₋₁ + 0.6RD₋₂ + 0.4RD₋₃ + 0.2RD₋₄(연 20% 선형), 기말 4개월 뒤 4월 말 편성 · JKP `rd5_at` 같은 가중 · Peters·Taylor(2014 초고): 지식자본 δ 15% 영구재고법, 조직자본 = SG&A 의 20% · δ 20%, 초기값 = 업력별 계수 · Eisfeldt·Papanikolaou: O_t = (1−δ)O_{t−1} + SGA_t/CPI_t, δ 15%, O₀ = SGA₁/(g+δ), g 10%, 결측 SG&A = 0, FF 17산업 안 순위 | [CLS] [JKP-c] [PT] [EP] | Q 메모: 1998 시작이면 R&D 자본 첫 4년 미완 · 영구재고 초기값 편향 → 가능한 한 이전 연도까지 수집 |
| 19 | 연결 · 별도 · 지배 귀속 (한국 특유) | Doo·Yoon 2024: K-IFRS(2011) 전 주재무제표 = 개별(지분법), 연결 = 부속 · 2011 후 주재무제표 = 연결, 별도(대부분 원가법) = 부속 · 배당가능이익은 상법상 별도 기준 · Compustat: IB 지배 귀속 전제(JKP 대체식), SEQ 비지배 제외(AFP) | [DY24] [JKP-c] [AFP] | ① 2011 전 '개별'(지분법)과 2011 후 '별도'(원가법)는 같은 계열이 아니다 → 별도 시계열 단절 ② '주재무제표 기준' 계열은 2011 에 개별 → 연결로 바뀐다 ③ 연결 · 별도(개별) 양쪽 + 지배 · 비지배 분리 수집 |
| 20 | 주당 값 · 분할 조정 | HXZ: SUE = EPSPXQ 변화 · RS = SALEQ/(CSHPRQ × AJEXQ) · Jegadeesh·Livnat: 계속영업 EPS · 주당매출, 계절 랜덤워크 + 드리프트(8분기) · Pontiff·Woodgate: 분할 조정 주식수 변화(초록만) · Daniel·Titman: ι = log(ME_t/ME_{t−τ}) − r(t−τ, t) | [HXZ15] [JL] [PW] [DT] | 수정계수 · 가중평균주식수 수집 |
| 21 | 비율 분모 ME 의 시점 | FF: B/M = 12월 t−1 ME, size = 6월 t · Novy-Marx: ME 6개월 시차(모멘텀 회피) · AFP: 최신 ME · Piotroski: 결산기 ME · JKP: Z · KZ 는 결산기 ME, 그 밖은 최신 ME | [FF93] [NM13] [AFP] [P00] [JKP-d] | 결산일 종가 · 주식수(결산기 시가총액) 필드 필요 |

---

## 3. 분기 값 · 발표일이 꼭 필요한 항목

### (가) 원 정의 자체가 분기 값을 쓰는 것

| 원천 항목 | 쓰는 특성 | 근거 |
|---|---|---|
| IBQ (계속영업이익, 3개월) | ROE(÷ 1분기 전 BE) · ROA(÷ 1분기 전 ATQ) · dRoe(4분기 전 대비) · NEI · `ni_inc8q`(8분기 연속 증가) · `niq_su` · EVOL(분기 ROE 60분기 표준편차, 최소 12) · `roeq_be_std` | [HXZ15] [GQ] [JKP-c] [AFP] |
| 분기 BE 구성: SEQQ · CEQQ · PSTKQ · PSTKRQ · TXDITCQ · ATQ · LTQ | ROE 분모 | [HXZ15] [GQ] |
| ATQ | ROA 분모 · `niq_at` | [HXZ15] [JKP-c] |
| EPSPXQ (+ AJEXQ) | SUE | [HXZ15] [CZ] |
| SALEQ (+ CSHPRQ · AJEXQ) | RS · SURGE · `saleq_su` · `saleq_gr1` | [HXZ15] [JL] [JKP-c] |
| 분기 OANCF(누계 → 3개월) · DPQ · (WCAPTQ) | `ocfq_saleq_std`(16분기, 최소 8) | [JKP-c] |
| NIQ · LTQ · CHEQ (+ 분기 BE) | CHS 부실 지표 NIMTA · TLMTA · CASHMTA(2개월 시차) | [CHS] |
| TXTQ | 세금 변화(Thomas·Zhang 2011) · C&Z:ChTax | [JKP-d] [CZ] |
| DVPSXQ · CSHOQ · AJEXQ | 분기 BE clean-surplus 보충 | [GQ] |
| REVTQ · COGSQ · XSGAQ · XINTQ (· XRDQ) | 분기 수익성 요인 — 한국에서 연간보다 낫다는 결과(Kang·Kang·Kim 2019, 서두만 열람) · C&Z:OperProfLag_q · OperProfRDLagAT_q · CBOperProfLagAT_q | [KKK19] [CZ] |

### (나) 발표일

- **RDQ** — (가) 전부의 편입 시점(발표 직후 달) · 6개월 낡은 이익 배제 · RDQ > 분기말 검사 ([HXZ15] [GQ] [CZ-q]).
- 한국 대응(Q 메모): 정기보고서 접수일 + 잠정실적 공시일. 정정 공시는 원 공시와 구분 보존. 시차 규칙은 프로젝트 PIT C4(분기 45일+, DART 분기 고정일 5/15 · 8/15 · 11/15).

### (다) JKP 방식(연간 정의 특성을 분기 자료로 최신화)을 쓰려면 분기 값이 필요한 것

- 재무상태표 전 항목의 **분기말 잔액** (표 1 의 `연+Q` 행 전부).
- 손익 · 현금흐름 전 항목의 **분기 3개월 값**(최근 4개 분기 합산용). 현금흐름표는 누계만 있으면 차분 — CAPX · SSTK · PRSTKC · DV · DLTIS · DLTR 포함.
- 식별 정보: 기준일 · 분기 번호 · 결산월 · 통화 · 연결/별도 구분 (TTM 유효성 검사).

→ 정리: 연간 정의 특성까지 분기 최신화할 생각이면 BS · IS · CF 핵심 계정은 전부 분기로 수집해야 한다. 분기 없이 연간만 수집하면 (가)의 10개 묶음(q5 ROE · SUE · RS · CHS 등)이 통째로 빠진다.

---

## 4. 한국 실증 — 한국 고유 처리 중심

| 논문 | 다룬 팩터 | 데이터 · 표본 | 한국 고유 처리 | 열람 수준 |
|---|---|---|---|---|
| Han·Lee·Kang (2020) "Market anomalies in the Korean stock market", 선물연구 28(2) 3–50 | 148개 이상현상(가치 · 투자 · 수익성 · 무형 — Bm · Roe · dRoe · Gpa · Ope · Opa · Cop · I/A · Noa · Oa · Ta · Nsi · Cei · Rdm · Rds · Ol · F · O · Z · Tbi 등) | FnGuide DataGuide · KOSPI + KOSDAQ · 1995.01~2019.06(최종 2000.01~2019.06) | **금융업 · 자본잠식 기업 제외** · 6월 말 t 에 회계연도 t−1 · BE = 자본총계 − 우선주자본금(이연세 가산 없음) · Roe = 계속영업이익 ÷ 전년 BE · dRoe 는 연간 · Tbi = 법인세차감전계속사업이익 ÷ 순이익 · O · Z 연 1% 윈저라이즈 · **연결/별도 · K-IFRS · 비12월 결산: 열람 범위에 기재 없음** | 전문(html) |
| Doo·Yoon (2024) "Unconsolidated separate financial statements and dividends: Evidence from Korea", IJAEFA 18(2) 305–320 | (팩터 논문 아님 — 제도 배경) | 2001~2018 상장 지배기업 | K-IFRS 전: 주재무제표 = 개별(지분법), 연결 = 부속 · 후: 주재무제표 = 연결, 별도(대부분 원가법) = 부속 · 배당가능이익 = 상법상 별도 기준 → 별도 이익을 배당 목적으로 관리하는 기업 존재 | 전문(PDF) |
| Yoon·Son (2014) Journal of Distribution Science 12(5) 61–69 | 이익수익률 · 순주식발행 · 자산성장 · 유동성(경기 국면별) | WISEfn · KOSPI + KOSDAQ · 1991.07~2013.12 · 6월 말 정렬 | 연결/별도 · 금융업 처리: 열람분에 기재 없음 | 전문(PDF) |
| Kim·Kim·Kwon·Lee (2015) "Percent accruals and the accrual anomaly: Korean evidence", PBFJ 35 340–366 | 전통 발생액 vs 퍼센트 발생액 | 9,399 기업-연도 · 1994~2010 | 처리 미확인(초록만) · 결과: 퍼센트 발생액에서만 이상현상 | 초록 |
| 김민기·정진수·김동석 (2018) "한국 주식시장에서의 수익성 프리미엄 발생 요인 분석", 재무관리연구 35(4) 69–108 | 수익성 프리미엄 원천 | KSE + KOSDAQ · 2001.07~2017.06 | 처리 미확인(초록만) | 초록(KCI) |
| Kang·Kang·Kim (2019) "A Comparison of New Factor Models in the Korean Stock Market", AJFS 48(5) 593–614 | FF5 vs q-factor · 분기 수익성 | 2002.07~2015.06 | 수익성은 HXZ 처럼 분기 이익으로 — 분기 수익성 판 FF5 가 가장 잘 설명 · 데이터 처리 미확인(서두만) | 서두 |
| Bae·Kang·Park (2023) "Comprehensive Asset Pricing Tests in the Korean Stock Market", 한국재무학회 추계 | q5 · 오정가 요인 · DHS 3요인 | 97개 이상현상 포트폴리오 | q5 가 최고 Sharpe · 처리 미확인(초록만) | 초록 |

**요약**: 연결/별도 선택, 지배 귀속, 2011 전환, 비12월 결산을 **명시적으로 다룬 한국 팩터 논문은 이번에 열람한 범위에 없다**. 명시된 처리는 Han 외(2020)의 금융업 · 자본잠식 제외와 6월 말 연간 정렬뿐이다. 제도 사실(주재무제표 전환 · 별도 원가법 · 배당 기준)은 Doo·Yoon(2024)으로 확인했다. 따라서 표 2 #19 의 처리 방침은 문헌 관례가 아니라 **설계 결정**으로 다뤄야 한다(연결 · 별도 양쪽 수집 · 귀속 분리 · 전환점 표식).

---

## 5. 출처 (열람 상태)

### 백본
- [JKP-c] JKP 코드 `accounting_chars.sas` — **열람**(원천 변수 목록 · 파생 변수 · 특성 식)
- [JKP-m] JKP 코드 `main.sas` — **열람**(`lag_to_public=4 · max_data_lag=18`)
- [JKP-r] JKP 저장소 README — **열람**(SAS → Python 이전, 현행판 `bkelly-lab/jkp-data` 는 미열람)
- [JKP-d] Jensen·Kelly·Pedersen, *Global Factor Data Documentation* — **열람**(§6.2–6.4 · §8 · 표 9). 논문 자체(JF 78(5) 2465–2518, 2023)는 문서의 BibTeX 로 서지만 확인 · 본문 미열람
- [CZ] Chen·Zimmermann `SignalDoc.csv` — **열람**(신호별 Compustat 변수 목록)
- [CZ-a] · [CZ-q] · [CZ-NOA] C&Z `CompustatAnnual.py` · `CompustatQuarterly.py` · `Predictors/NOA.py` — **열람**
- [CZ-s] openassetpricing.com — **열람**(인용 = Chen & Zimmermann 2022, "Open Source Cross-Sectional Asset Pricing", Critical Finance Review, 207–264 · 권호 표기는 미확인 · 논문 본문 미열람)

### 핵심 논문
- [FF93] Fama·French (1993) JFE 33, 3–56 — **열람**(HEC 사본 · p. 8 BE 정의 · 7월 t 수익률 시점 · 2년 등재 요건)
- [KF] Ken French Data Library, Variable Definitions — **열람**(2026-11-08 · OP 분모 = BE + 비지배지분)
- [FF15] Fama·French "A Five-Factor Asset Pricing Model" SSRN 2287202 초고(2013-11) — **열람**(OP · Inv 정의) · JFE 116(1) 게재판 미열람
- [NM13] Novy-Marx, NBER w15940 (2010) — **열람**(GP = REVT − COGS · BE 위계 각주 3 · 6월 말 시차) · JFE 2013 게재판 미열람
- [BGLN15] Ball·Gerakos·Linnainmaa·Nikolaev (2015) "Deflating profitability" JFE 117(2) 225–248 — **초록만**(정의는 2016 초고 부록의 "Ball et al. (2014)를 따름" 문장으로만 확인)
- [BGLN16] 같은 저자 "Accruals, cash flows, and operating profitability…" 초고(2015-04-17, Ivey 사본) — **열람**(부록 OP · Cop · 현금흐름표판 · BE 정의)
- [HXZ15] Hou·Xue·Zhang (2015) "Digesting Anomalies" RFS 게재판(global-q 사본) — **열람**(부록 A.1: SUE · ROE · ROA · RS · NEI · TI/BI · 6개월 규칙 · RDQ 규칙)
- [HXZ12] 같은 논문 NBER w18435 — **열람**(요인 구성 · 분기 BE 각주 3)
- [HMXZ] Hou·Mo·Xue·Zhang NBER w24709 "q5"(2018) — **열람**(Tobin's q · Cop · dRoe · 4개월 규칙) · Review of Finance 2021 게재판 미열람
- [GQ] global-q *Technical Document: Factors* (2026-07) — **열람**(ROE 시점 · 분기 BE 보충 · Eg 예측 변수)
- [AFP] Asness·Frazzini·Pedersen "Quality Minus Junk" 초고(2013-10-09, NBER 학회) — **열람**(부록 A1–A3 정의 문장 · 수식은 이미지라 판독 불가 · 초고엔 Payout 구성요소가 있음) · RAS 2019 게재판 미열람
- [P00] Piotroski "Value Investing…" Chicago GSB Selected Paper 84 — **열람**(JAR 38 Supplement 2000 의 초고판 · 표 1 변수 정의 · §3.2 시점)
- [S96] Sloan (1996) TAR 71(3) — **열람**(CUHK 사본 · 발생액 식 · item 번호 · 4개월 규칙)
- [BMRR] Boudoukh·Michaely·Richardson·Roberts NBER w10651 — **열람**(배당 · 환매 · 발행 item 번호)
- [CLS] Chan·Lakonishok·Sougiannis NBER w7223 — **열람**(R&D 자본 식 · item 번호 · 4월 말 편성)
- [EP] Eisfeldt·Papanikolaou "Organization Capital…" AEA 2013 학회판 — **열람**(조직자본 식 · δ · 초기값 · 산업 순위 · 12월 결산 표본) · JF 2013 게재판 미열람
- [PT] Peters·Taylor "Intangible Capital and the Investment-q Relation" 초고(2014-03-05) — **열람**(지식자본 δ 15% · 조직자본 SG&A 20% · δ 20%) · JFE 2017 게재판 미열람(게재판의 SG&A 비율은 미확인)
- [LN04] Lev·Nissim (2004) TAR 79(4) 1039–1074 — **열람**(과세소득 추정 · item 번호 · 세율표)
- [NM11] Novy-Marx (2011) "Operating Leverage" Review of Finance 15 103–134 — **열람**((COGS + XSGA)/AT · 6월 말 갱신)
- [CHS] Campbell·Hilscher·Szilagyi NBER w12362 — **열람**(분기 자료 · NIMTA · TLMTA · CASHMTA · 2개월 시차)
- [DT] Daniel·Titman NBER w9743 — **열람**(부록 A BE · 이익 · 현금흐름 item 번호 · ι 정의)
- [JL] Jegadeesh·Livnat "Revenue Surprises and Stock Returns" 초고(Livnat 홈페이지) — **열람**(SUE · SURGE · 표본 제외) · JFE 2006 게재판 미열람
- [FOS] Foster·Olsen·Shevlin (1984) Stanford GSB WP 735 페이지 — **초록만**
- [BEN] Beneish (1999) FAJ 55(5) CFA Institute 페이지 — **초록만**
- [CGS] Cooper·Gulen·Schill (2008) JF 63(4) 1609–1651 — **초록만**(econpapers)
- [PW] Pontiff·Woodgate (2008) JF 63(2) 921–945 — **초록만**(econpapers)
- [HHTZ] Hirshleifer·Hou·Teoh·Zhang (2004) JAE 38 297–331 · Dice WP 2004-18 — **서지만**(econpapers · PDF 링크 404)

### 한국
- [HLK20] Han·Lee·Kang (2020) — **전문 열람**(Emerald html)
- [DY24] Doo·Yoon (2024) — **전문 열람**(PDF)
- [YS14] Yoon·Son (2014) — **전문 열람**(koreascience PDF)
- [KJK18] 김민기·정진수·김동석 (2018) — **초록만**(KCI 랜딩 · DOI 10.22510/kjofm.2018.35.4.004)
- [KKKL15] Kim·Kim·Kwon·Lee (2015) — **초록만**(econpapers)
- [KKK19] Kang·Kang·Kim (2019) — **서두만**(vLex · DOI 10.1111/ajfs.12274)
- [BKP23] Bae·Kang·Park (2023) — **초록만**(earticle)

### 내부
- `.claude/rules/pit.md` C4 (연간 = 익년 3/31 · 분기 45일+ · DART 분기 고정일)
- `04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md` 98행 (`.M` 접미 = 주재무제표 기준 — 추측으로 기록됨)

---

## 6. 미확인 목록 (이번에 열지 못한 것)

- **본문 미확인(항목은 JKP · C&Z 로만 확인)**: Richardson·Sloan·Soliman·Tuna 2005(JAE) · Hafzalla·Lundholm·Van Winkle 2011(TAR) · Bradshaw·Richardson·Sloan 2006(JAE) · Hirshleifer·Hou·Teoh·Zhang 2004(JAE) · Cooper·Gulen·Schill 2008 · Pontiff·Woodgate 2008 · Altman 1968(JF) · Ohlson 1980(JAR) · Foster·Olsen·Shevlin 1984(TAR).
- **Beneish 1999(M-score)**: 본문 미확인. M-score 의 변수 구성(어떤 계정 몇 개)은 이번에 근거 문서로 확인하지 못해 표 1 에 별도 행을 두지 않았다. 흔히 알려진 입력(매출채권 · 매출 · 매출원가 · 유동자산 · 유형자산 · 감가상각 · 판관비 · 유동부채 · 장기부채)은 모두 표 1 의 다른 근거로 이미 수집 대상이다(이 문장 자체는 미확인).
- **게재판 미열람(초고 · 학회판으로 대체)**: FF 2015 · Novy-Marx 2013 · BGLN 2015/2016 · HMXZ 2021 · AFP 2019 · Peters·Taylor 2017 · Eisfeldt·Papanikolaou 2013 · Jegadeesh·Livnat 2006 · Piotroski 2000 · Daniel·Titman 2006 · Boudoukh 외 2007 · Chan 외 2001 · CHS 2008.
- **논문 본문 미열람(문서 · 코드만)**: Jensen·Kelly·Pedersen 2023 · Chen·Zimmermann 2022.
- **기준 · 매뉴얼 미열람**: Compustat 데이터 정의(COGS · XSGA 의 감가상각 제외 · REVT vs SALE) · K-IFRS 기준서(기능별 분류의 감가상각 포함 · 영업이익 표시 · 계약부채 시행 시점 · 분기 연결 시행 시점 · 현금흐름 분류 선택).
- **한국 논문 본문**: 김민기 외 2018 · Kim 외 2015 · Kang 외 2019 · Bae 외 2023 (데이터 처리 절 미확인).
- **열었으나 판독 불가**: 일본 금융청 2012 한국 IFRS 자료(텍스트 추출 불가 — 인용 안 함).

[JKP-c]: https://github.com/bkelly-lab/ReplicationCrisis/blob/master/GlobalFactors/accounting_chars.sas
[JKP-m]: https://github.com/bkelly-lab/ReplicationCrisis/blob/master/GlobalFactors/main.sas
[JKP-r]: https://github.com/bkelly-lab/ReplicationCrisis
[JKP-d]: https://jkpfactors-data.s3.amazonaws.com/documents/Documentation.pdf
[CZ]: https://github.com/OpenSourceAP/CrossSection/blob/master/SignalDoc.csv
[CZ-a]: https://github.com/OpenSourceAP/CrossSection/blob/master/Signals/pyCode/DataDownloads/CompustatAnnual.py
[CZ-q]: https://github.com/OpenSourceAP/CrossSection/blob/master/Signals/pyCode/DataDownloads/CompustatQuarterly.py
[CZ-NOA]: https://github.com/OpenSourceAP/CrossSection/blob/master/Signals/pyCode/Predictors/NOA.py
[CZ-s]: https://www.openassetpricing.com/
[FF93]: https://people.hec.edu/rosu/wp-content/uploads/sites/43/2023/09/Fama-French-Common-risk-factors-1993.pdf
[KF]: https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/Data_Library/variable_definitions.html
[FF15]: https://www.johnhcochrane.com/s/FF_Five_Factor.pdf
[NM13]: https://www.nber.org/system/files/working_papers/w15940/w15940.pdf
[BGLN15]: https://econpapers.repec.org/RePEc:eee:jfinec:v:117:y:2015:i:2:p:225-248
[BGLN16]: https://www.ivey.uwo.ca/media/3775325/gerakos.pdf
[HXZ15]: http://global-q.org/uploads/1/2/2/6/122679606/houxuezhang2015rfs.pdf
[HXZ12]: https://www.nber.org/system/files/working_papers/w18435/w18435.pdf
[HMXZ]: https://www.nber.org/system/files/working_papers/w24709/w24709.pdf
[GQ]: http://global-q.org/uploads/1/2/2/6/122679606/factorstd_2026jul.pdf
[AFP]: https://conference.nber.org/conf_papers/f69835.pdf
[P00]: https://tevgeniou.github.io/EquityRiskFactors/bibliography/ValueInvestingReview.pdf
[S96]: https://www.cuhk.edu.hk/acy2/workshop/June2009Wasley/1996TAR).pdf
[BMRR]: https://www.nber.org/system/files/working_papers/w10651/w10651.pdf
[CLS]: https://www.nber.org/system/files/working_papers/w7223/w7223.pdf
[EP]: https://topcat.aeaweb.org/conference/2013/retrieve.php?pdfid=51
[PT]: https://www.stern.nyu.edu/sites/default/files/assets/documents/Wharton-Peters_taylor_Intangible%20capital%20%26%20Q.pdf
[LN04]: https://business.columbia.edu/sites/default/files-efs/imce-uploads/dnissim/publications/taxable%20income.pdf
[NM11]: https://tevgeniou.github.io/EquityRiskFactors/bibliography/OperatingLeverageFactor.pdf
[CHS]: https://www.nber.org/system/files/working_papers/w12362/w12362.pdf
[DT]: https://www.nber.org/system/files/working_papers/w9743/w9743.pdf
[JL]: https://pages.stern.nyu.edu/~jlivnat/JAE%20submission.pdf
[FOS]: https://www.gsb.stanford.edu/faculty-research/working-papers/earnings-releases-anomalies-behavior-security-returns
[BEN]: https://rpc.cfainstitute.org/research/financial-analysts-journal/1999/the-detection-of-earnings-manipulation
[CGS]: https://econpapers.repec.org/RePEc:bla:jfinan:v:63:y:2008:i:4:p:1609-1651
[PW]: https://econpapers.repec.org/RePEc:bla:jfinan:v:63:y:2008:i:2:p:921-945
[HHTZ]: https://econpapers.repec.org/RePEc:eee:jaecon:v:38:y:2004:i::p:297-331
[HLK20]: https://www.emerald.com/insight/content/doi/10.1108/JDQS-03-2020-0004/full/html
[DY24]: https://onlineacademicpress.com/index.php/IJAEFA/article/download/1396/892/4059
[YS14]: https://www.koreascience.or.kr/article/JAKO201416954328510.pdf
[KJK18]: http://www.kci.go.kr/kciportal/landing/article.kci?arti_id=ART002421442
[KKKL15]: https://econpapers.repec.org/RePEc:eee:pacfin:v:35:y:2015:i:pa:p:340-366
[KKK19]: https://law-journals-books.vlex.com/vid/comparison-of-new-factor-855640888
[BKP23]: https://www.earticle.net/Article/A437863
