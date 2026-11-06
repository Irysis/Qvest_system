# 퀀티와이즈 데이터 확장 · 리프레시 병렬화 계획 (2026-11-06)

- **상태**: 계획(조사 · 설계만). 운영 파일 · 퀀티 단말 · Excel · git 은 건드리지 않았다. 이 파일 하나만 새로 썼다.
- **요청(도훈 11-06)**: ① 퀀티 glossary 를 받아 Qvest 에 적재할 만한 데이터를 찾는다 ② 기존 퀀티 리프레시 방식으로 적재하고 리프레시 체인에 건다 ③ 퀀티 갱신 중에도 다른 데이터 리프레시가 같이 돌게 바꾼다.
- **아직 적재 · 배선을 하지 않은 이유**: 원래 세션이 지금 단말로 재수급 중이고(09:44~ `qw_refresh.ps1 -SkipLogin -Only Universe_Support,Investor_Act,Consensus` ✔), 일일 리프레시 PID 491 이 실행 중이다(잠금 보유 ✔ · 10:05 현재 DART 단계 ✔). 실행 중인 bash 스크립트는 고치면 안 되고, 항목 사전은 단말 메뉴로만 받을 수 있다(§1).
- **표기**: ✔ = 이 계획을 쓰며 직접 다시 확인한 사실 · (조사) = 조사 단계 실측(부록 A) · (추측) = 확인 전.

---

## §0 요약

1. **항목 사전**: 엑셀 리본 Help › Glossary › Items Glossary(메뉴 9530) 등 벤더 공식 파일이 정본이다. 셸로 직접 받는 길은 벤더 호스트가 연결을 끊고(우회하지 않았다), 로컬 사전 DB 는 암호가 걸린 Jet DB 다(열지 않았다). → 퀀티가 놀 때 단말 메뉴로 받는다(§1.3).
2. **1차 적재 묶음**(사전으로 코드를 확인한 뒤): **A** 공매도 거래 · 공매도 잔고 · 대차잔고 · 신용잔고율(종목 일별 · 새 질의서 `ShortLending_update.xlsx`) / **B** 외국인 보유비중 · 한도소진율 · 연기금 · 투신 · 사모 · 금융투자 순매수(종목 일별 · `FlowDetail_update.xlsx`) / **C** 시장 증시자금(고객예탁금 · 신용융자 · 미수금 · 반대매매 · ECO 경로 · 있으면).
3. **적재 방식**: 기존과 같은 질의서 형식 · 같은 드라이버(`qw_refresh.ps1`) · 같은 무인 래퍼(`qw_updatefile_unattended.sh`). 다만 새 책은 `03_Universe/Update_File_ext/` 에 두고 자기 적재기(`qw_ext_ingest.py`)를 쓴다 — 지금 Update_File 적재기는 등록되지 않은 xlsx 를 '처리됨'으로 기록해 조용히 버린다 ✔(`incremental_update_file.R:81 · 838-865`).
4. **선행 수리(측정 신뢰 결함)**: 지금 경로에 실측 결함이 있어 새 데이터도 같이 물린다 — 이미 생긴 구멍 3건 ✔ · 신규 상장 53종의 위생 표식 NA ✔(위생 판정식이 NA 를 '정상'으로 통과시킨다 ✔) · 완료 수 오계산 ✔ · 대표 파일 하나만 보는 신선도 감사 ✔(§3.0).
5. **병렬화 1단계(출력 불변)**: 퀀티 단계는 전경에서 지금처럼 직렬로 두고, 퀀티와 무관한 DART · Arrow · ECOS 6통화 · 비-return 을 `[0b]` 직후 백그라운드 레인 2개로 띄워 `[0b']` 직전에 합류한다. 퀀티가 일하는 밤 잠금 · Done 이 약 29~35분 빨라진다(11-06 같은 분기 제출창이면 약 50분 · 추정). 퀀티가 멈춘 밤에도 그 넷은 갱신된다(지금은 0).
6. **새 질의서는 '퀀티 꼬리 레인'(3단계)에서** — 핵심 4책 수급이 끝난 직후 백그라운드에서 받는다. RAWDATA 체인을 늦추지 않는다.
7. **도훈 결정**: 배당 포함 총수익의 측정 축 편입 · 2015~ 재무 원천 · 파생 원천 · 병렬화 확장(퀀티 중 거시 · 국면 실행 = 출력 변화 · Done 조기화) · 벤더 문의(§5.3).

### 실행 순서

| 단계 | 내용 | 주체 | 전제 |
|---|---|---|---|
| 0 | 구멍 3건 복구 수급 · 완료 확인 | 원래 세션(단말) | 지금 재수급이 끝난 뒤 · 적재는 PID 491 잠금 해제 뒤 |
| 1 | 선행 수리 F1~F7 코드 + 시험 | Q(코드) | — |
| 2 | 병렬화 1단계 + 시험 → 설치 | Q | PID 491 이 Done 을 찍고 끝난 뒤 · 원래 세션 스크래치판(run_r 이름표 · MSM as-of) 설치 뒤 · 00:03 전 |
| 3 | 사전 수급 → 파싱 → 후보 코드 확정 · 권한 시험 | 원래 세션(단말) + Q(파싱) | 퀀티 유휴 |
| 4 | 등록부 · 새 질의서 2책 · 적재기 · 가용 규칙 · 시험 | 원래 세션(Excel) + Q | 공표 시각 공식 근거 확인 |
| 5 | 최초 이력 수급(1회 · 구간 분할) → 초기 적재 | 원래 세션 + Q | 4 |
| 6 | 퀀티 꼬리 레인 배선(3단계) → 그림자 실행 2~3밤 | Q | 2 · 5 |

---

## §1 항목 사전(glossary)

### 1.1 정본 = 벤더 공식 파일(엑셀 리본 Help 메뉴)

| 리본 경로(Quantiwise 7G 탭) | 메뉴 id | 파일(추정) | Qvest 용도 |
|---|---|---|---|
| Help › Glossary › **Items Glossary** | 9530 | `QW7_Glossary/Glossary.xlsx` | ★항목 사전(코드 · 이름 · 정의) |
| Help › Glossary › Data Information | 9520 | `QW7_Glossary/Data Information.pdf` | 갱신 시점 정보일 가능성(추측) — 공표 지연 근거 후보 |
| Help › Glossary › Economy Glossary | 9540 | `ECOWise_Glossary_Kor.xlsx` · `_Eng.xlsx` | ECO 심볼 사전 |
| Help › Glossary › Consensus Glossary | 9570 | 주소 미확인 | 컨센서스 정의 |
| Help › Glossary › Smart Consensus Methodology · Glossary | 9592 · 9593 | `Smart_Consensus_Glossary.xlsx` | 스마트 컨센서스 |
| Help › Glossary › Insider Glossary | 9550 | 주소 미확인 | 내부자 항목 |
| Help › Code › Account Code › K-IFRS | 9611 | `QW7_Account Code/IFRS Account Code(Kor).xls` | 재무 계정 코드 |
| Help › Code › Ratio Code › K-IFRS | 9621 | `IFRS Ratio(Kor).xlsx` | 재무 비율 코드 |
| Help › Code › WICS · WI26 · ETF Classif. | 9630 · 9640 · 9660 | pdf | 분류 체계 |

메뉴 정의 = `C:/WISEfn/Common/Bin/Addin/QW7menu.xml`(405~416행 · 380~394행), 주소 = `qwTool.dll` 문자열(@0xc9e40~)(조사). **메뉴 id 와 파일의 짝은 문자열이 메뉴 id 순서로 놓여 있다는 데서 나온 추정이다** — 첫 수급 때 확인한다.

### 1.2 다른 길이 막힌 이유(우회하지 않는다)

- **셸 다운로드**: `seven.quantiwise.com` · `bbs.wisefn.com` · `www.wisefn.com` 모두 연결이 끊겼다(대조군 example.com = 200). User-Agent 를 바꾸는 시도는 우회라서 하지 않는다(조사).
- **로컬 사전 DB**(`ui.dat` · `acccode.dat` · `ECOMaster.dat` · `Company.dat` · `workdate.dat`): 실체는 암호 걸린 Jet 4.0 MDB 다. 암호 해제나 페이지 직접 파싱은 벤더 보호 우회라 배제한다. qwMain 이 열고 있다(.ldb 잠금 07:31)(조사).
- **과거 사본 없음**: 다운로드 · 문서 · 바탕화면 · 브라우저 캐시 · Office MRU 모두 0건. 9530 은 2025-05-10 · 2025-11-21 에 실행된 기록만 있고 매번 2초 안에 끝났다(qwMain.log) → 브라우저로 열렸을 가능성(추측).

### 1.3 얻는 방법

**전제(모두 만족할 때만)**
- 퀀티를 쓰는 작업이 없다: `qw_refresh.ps1` · `qw_updatefile_unattended.sh` · `quantiwise_fetch.py` · `qw_excel_refresh.ps1` 프로세스 0 · 스크립트가 띄운 EXCEL 0.
- 원래 세션의 재수급 · 복구 수급(§5.2 ①②)이 끝났다. 일일 리프레시가 단말을 쓰는 구간(`[1pre]` · `[1pre-qw]` · `[4gm]`)이 아니다 — 00:03 밤 체인과 부팅 리프레시를 피한다.
- 단말이 로그인 상태다(다른 PC 중복 로그인 경고 #32770 'Quantiwise7G' 가 없다).

**수동(권장 · 위험 최소 — 도훈, 또는 원래 세션)**
1. Excel 을 열고 리본에 `Quantiwise 7G` 탭이 보이는지 확인한다(애드인 Quantiwise For Excel · LoadBehavior=3).
2. `Quantiwise 7G › Help › Glossary › Items Glossary` 를 누른다.
3. 열리는 형태를 본다. (a) Excel 통합문서로 열리면 다른 이름으로 저장 → `03_Universe/_reference/quantiwise_glossary/20261106/Glossary.xlsx` (b) 브라우저 다운로드면 다운로드 폴더의 파일을 같은 폴더로 옮긴다.
4. 같은 방법으로 Economy Glossary(Kor) · Data Information · Consensus Glossary · Smart Consensus Glossary · Insider Glossary · `Help › Code › Account Code › K-IFRS` · `Ratio Code › K-IFRS` 를 받는다.
5. Q 가 같은 폴더에 `provenance.json` 을 쓴다: 메뉴 id · 리본 경로 · 파일명 · 크기 · sha256 · 저장 시각 · 그 시점의 `C:/WISEfn/Common/Update/Ver/{ui,ECOMaster,acccode,company}.ver` 값.
6. git 에 넣지 않는다(벤더 저작물). `03_Universe/` 는 git 제외다 ✔(`.gitignore` 2행).

**반자동(단말 조작 스크립트 · 퀀티 유휴 확인 뒤)**: `qw_excel_refresh.ps1` 의 QBroker 블록(25~26 · 263~270행 · 조사)을 복제한 1회성 스크립트(`03_Universe/_probe_qw_20261106/glossary_fetch.ps1` · git 제외)로 `New-Object -ComObject qwMain.QBroker` → `$broker.Run([int16]9530, $xl, Missing×4)` 를 메뉴 id 만 바꿔 차례로 실행한다. 새 통합문서가 열리면 `SaveAs(…, 51)`, 아니면 시작 시각 뒤 다운로드 폴더에 생긴 파일을 옮긴다. 위험: 단말 기동 때 숨은 'Item Lookup' 모달이 `QBroker.Run` 을 막은 전례(10-20) — 그때는 리본 UI 자동화(`ribbon_eco.ps1` 방식)로 간다.

**보조(사전에 항목 코드 열이 없을 때만)**: Item Lookup(7200) 트리를 32비트 교차 프로세스 TVM/LVM 메시지로 덤프한다(`03_Universe/_probe_qw_20261020/ecow.ps1` 방식 · 잠금 화면에서도 동작 실측).

### 1.4 받은 뒤

1. 사본에서 openpyxl `read_only` 로 파싱해 `glossary_items.parquet`(코드 · 한/영 이름 · 범주 경로 · 주기 · 단위 · 정의 · 있으면 이력 시작)을 같은 `_reference` 폴더(git 제외)에 만든다. `.xls`(Account Code)는 venv 에 xlrd 가 없을 것으로 보여(추측) 퀀티 유휴 때 Excel 로 xlsx 로 바꾼다. 읽은 뒤 핸들을 닫는다(openpyxl `read_only` 는 핸들을 잡는다).
2. 범주별 항목 수와 §2 후보의 코드 · 주기 · 단위 · **날짜 의미(체결일 · 결제일 · 잔고 기준일)** 를 확정해 이 폴더에 `candidates.md`(코드 · 이름만 — 벤더 정의문은 옮겨 싣지 않는다)로 남긴다.
3. 권한: 계정별 항목 제한이 있다('아이템 조회 권한이 없는 ID입니다' — qwCom.dll 문자열 · 조사). §3.2 양성 대조에서 함께 확인한다.
4. 사전 갱신 감지: 위 `.ver` 4개와 `Data/*.dat` 의 크기 · 수정 시각만 stat 한다(DB 엔진 접촉 0). 바뀌면 사전을 다시 받는다. 현재 값: ui 33 · ECOMaster 156 · acccode 555 · company 204(조사).

### 1.5 범주 개요(사전 전 — 범주별 항목 수는 미확보)

| 묶음(qwCom.dll · QW7menu.xml) | 하위 | Qvest 현재 사용 |
|---|---|---|
| Stock Items | 일/주/월/년 · NXT · Beta · Dividend · Price Ratios · 업종상대 · **대차(StkSlb) · 공매도(StkSS) · 신용(StkMT)** · 블록/바스켓 · CFD · 시장위험프리미엄 | S 약 10(수정 OHLC · 거래량 · 시총 · 유동비율 · 평균시총/거래대금) |
| 수급 | Inv1 금액 · Inv2 비중(D/W/M/Y) | U 4(외국인 · 기관 · 개인 · 기타법인 순매수대금) |
| Consensus · Smart · Macro Consensus | Forecast · Rating & TP · Fwd 12/18/24M · Up&Down · Surprise · Guidance | E 12 |
| Financial Items | F/S · K-IFRS(COMP.) · C-IFRS | M 42(`Fundamental.xlsx` · 2014Q4 까지) |
| Information · Prospectus · Insider | 상태 · 주요제품 · 주주 · 임원 · 내부자 거래 | R 약 10(위생 · 지수 멤버십 · 섹터 · 상장/폐지일) |
| 지수 · ETF/ETN · ELW · DR · Warrant · K-OTC | | I 3 · W 2 |
| Money Flow · Derivative · Bond | 예탁금 · 펀드자금 · 유동성 · 프로그램 · 선물/옵션 · 금리/스프레드 | 0 |
| ESG · Patent · Gold Spot · Global | | 0 |
| ECO Wise 대분류 20 | MB · NA · BOP · HH · PI · MA · CBSI · PL · PF · CS · RSI · BO · RTP · CT · WI · WE · RE · MC · FSI · DC | WTI · CD91 + `KR_Macro.xlsx` 계열 |

코드 형식: 유형 문자(S · U · E · M · R · I · W) + 6자리. 재무 · 컨센서스 일부는 `.M` 접미(각 재무년월 주재무제표 기준 — 추측). ECO 는 `x` 로 시작하는 심볼(조사).

---

## §2 적재 후보

### 2.1 고른 기준

① 쓸 곳이 정해져 있다(프로그램 큐 · 데이터 대기열 · 충실구현 결손 · 팩터 대리변수 교체) ② 가용 시점을 정할 수 있다(공표 규칙이 있고, 확인 전에는 보수적으로 늦게 잡을 수 있다) ③ Time Series(Company · Sector) 일별 질의로 받는다 — 기존 Update_File 방식. 횡단면(Peer Analysis)은 `Period(To)` 행이 없어 지금 드라이버의 완료 판정이 영구 미완료가 된다 ✔(`qw_refresh.ps1:213-223`) ④ 다른 원천이 없거나 퀀티가 낫다 ⑤ 밤 시간 — 종목 일별 시트 1장 약 7분(11-06 OHLCVS 시트 스탬프 간격 · 09-19 컨센서스 시트당 6.8분 · 조사).

### 2.2 ★1차 적재 묶음

코드는 모두 사전 확인 전이다. 가용 규칙의 n 은 `fred_availability_rules.json` 의 `kr_trading_days_after`(관측일 이후 n번째 한국 거래일 15:30 결정부터 사용)이다. **확인 전 값은 보수(늦게 쓰는 쪽 = PIT 안전)** 이고, 공식 공표 규정 원문으로 확인한 뒤 basis 와 함께 확정한다.

| # | 데이터 | 퀀티 항목(코드) | 쓰는 연구 · 대기열 | 기대 가치(Q 판단 · 미측정) | PIT 가용 규칙(잠정) | 빈도 | 이력 시작 | 질의서 |
|---|---|---|---|---|---|---|---|---|
| A1 | 공매도 거래(종목 · 거래량 또는 대금 · 가능하면 비중) | Stock Items › 공매도(StkSS) · 코드 = 사전 | P1 수익: 미개척 경로(의견 차이 + 공매도 제약 · Miller 1977 · 선행 가설 0 — 07-06 카드) · P2 방어: 국면 라벨 부활 조건 '대차/공매도'(08-08) · 팩터 CR05 Short_Pressure_Proxy · CR06 DTC_Proxy 대리변수 교체 | **높음** — 다른 원천 없음(KRX MDC 로그인 벽 · Open API /srt/* 404) | 장 마감 뒤 당일 공표로 알려짐 → 확인 시 n=1 · 확인 전 **n=2** | 일 | 미확인 · 금지 기간 공백 구조(2008-10~2009-05 · 금융주는 2013-11 까지 이어진 것으로 알려짐 · 2011-08~11 · 2020-03-16~2021-05-02 · 2021-05~2023-11 대형주만 재개 · 2023-11-06~2025-03-30 — 모두 금융위 원문으로 확인) | 새 `ShortLending_update.xlsx` |
| A2 | 공매도 잔고(종목 · 수량/금액 · 가능하면 잔고 비율) | 같은 그룹 | A1 + 시장 합산 공매도의 시장 수익 예측(Rapach · Ringgenberg · Zhou 2016 JFE) — P2 | **높음** | T+2 공표로 알려짐 · 날짜 의미(결제일 기준?) 확인 필수 → 확인 전 **n=3** | 일 | 잔고 공시제도(2016-06-30 시행으로 알려짐) 이후일 가능성(추측) | 같은 책 |
| A3 | 대차잔고(종목 · 수량/금액) | Stock Items › 대차(StkSlb) | CR05 교체 · 공매도 잠재 수요(추측) · P1 · P2 | 중간~높음 | 예탁결제원 집계 T+1(추측) → 확인 전 **n=2** | 일 | 미확인 | 같은 책 |
| A4 | 신용잔고율(종목) | Stock Items › 신용(StkMT) | P2: 개인 레버리지 · 강제 청산 연쇄(위기 유형 사전 분류 재료) · 종목 신용 쏠림 | 중간 | T+1~T+2(추측) → 확인 전 **n=3** | 일 | 미확인 | 같은 책 |
| B1 | 외국인 보유비중(지분율) | 사전 확인 | `flow_features` foreign_own_proxy(누적 순매수/시총) 교체 · 대기열 2211.03287 · 팩터 CR04(회전율 대리) 교체 | 중간 | 당일 장 마감 뒤 확정(추측) → 확인 전 **n=2** | 일 | 미확인 | 새 `FlowDetail_update.xlsx` |
| B2 | 외국인 한도소진율 | 사전 확인 | B1 과 같음(한도 근접 종목의 수요 제약) | 중간 | B1 과 같음 | 일 | 미확인 | 같은 책 |
| B3~B6 | 연기금 · 투신 · 사모 · 금융투자 순매수대금(일간) | U 계열(끝자리 320 = 순매수대금 일간)과 같은 계열로 추정 — 사전 확인 | 2001.04185 크라우딩(P3 큐 · 충실구현) · 대기열 2508.20426 · 연기금 달력 수급(아이디어) · 수급 팩터 15종 확장 | 중간 | 기존 수급과 같은 규약: 장 마감 뒤 → **n=1**(`compute_investor.R` 의 `Date < sig_date` 와 같은 정보 기준) | 일 | 기존 수급(2000-01-04~)과 같은 원천일 것(추측) | 같은 책 |
| C | 시장 증시자금(고객예탁금 · 신용융자 잔고 · 미수금 · 반대매매) | Money Flow › Deposits · Liquidity(메뉴 2410 · 2430) · ECO 심볼 여부 미확인 | KR-CISS '개인 레버리지 축'(`DESIGN_v1_capital_market.md` §4.3 ④) · P2 위기 유형 사전 분류 | 중간~높음 — 선행성은 사전등록으로 검증(스트레스 지수는 동행이었다) | 금투협 집계 D+1(추측) → 확인 전 **n=2** · 시계열이라 기존 등록부에 그대로 맞는다 | 일 | 미확인 | ECO 심볼이면 `Global_Macro.xlsx` 열 추가(ECO Wise 대화상자) · 아니면 2차로 |

**밤 비용(가정)**: 시트당 약 7분을 그대로 쓰면 A 약 28분 · B 약 42분 · C 1분 미만(Global_Macro 실측 53초). 증분 창이 하루라 더 짧을 수 있다(추측 · 첫 밤 실측). 퀀티 꼬리 레인에서 RAWDATA 체인과 겹쳐 돈다(§4.3).

**1차 공통 원칙**
- **비율 우선**: 수준(주식 수 · 금액)보다 비율(비중 · 잔고율 · 지분율)을 받는다. '수정' 수준은 이후 기업행위를 반영한다 — 측정 축의 수정주가와 같은 PIT 경계로 기록한다.
- **숏 쪽 구동 위험**: 공매도 · 대차 신호는 주식선물 베이시스처럼 숏 쪽에서 나올 수 있다 → 라운드 사전등록에 롱 레그 분해를 넣는다.
- **공매도 금지 캘린더** = 정적 등록부(`06_Registry/short_sale_ban_calendar.json` · 금융위 발표 원문 링크) — 대기열 2609.08881 을 풀고, 적재 관문의 '금지 기간 채움 0 허용' 근거가 된다(§3.5).
- **B12 · D6 를 쓰지 않는 항목부터**: 1차는 S · U 계열 일별 항목이라 아직 의미를 모르는 B12(Base Date) · D6(Account Download 0 Full · 1 Point)에 기대지 않는다.

### 2.3 2차 · 보류

| # | 데이터 | 쓰는 곳 | 사유 · 조건 | 구분 |
|---|---|---|---|---|
| 5 | 컨센서스 세분(투자의견 평균/분포 · EPS · 목표주가 표준편차/최고/최저 · FY2 · 지배순이익 FY1) | 1806.01743(REC 패널) · 팩터 SE01 · C12 결손(SE01 이 찾는 eps_std · target_std 열이 없다) · 대기열 cond-mat/0410079 · 1301.6638 | 가치 중간 · B12 · D6 의미 미확인 · 의견 분산 효과는 대체로 숏 쪽 · '해당 연도 없으면 전년도로 대체' 옵션은 끈다(값이 묵는다 · 추측) | 2차 · 새 `EstimateDetail_update.xlsx`(이름에 'Consensus' 금지) |
| 6 | 투자자 매수/매도 분리 대금 + 나머지 세분(보험 · 은행 · 기타금융 · 국가) | 2001.04185 불균형 (buy−sell)/(buy+sell) | 시트가 많다 → 1차 B 안정 뒤 | 2차 |
| 7 | 파생 시장 상태(K200 선물 베이시스 · 미결제약정 · PCR · ATM IV · 스큐 · 선물/옵션 투자자별) | KR-CISS · P2 부활 조건 '옵션 IV' · `regime_derivatives.R`(코드만 · `.cache/krx_derivatives` 비어 있음) | 원천 선택 — 퀀티(이력 1996~ 가능성 · 추측) vs KRX Open API `/drv/`(수집기 있음 · 2010~ 추측) — 이력 확인 뒤 | 2차 · 도훈 결정 |
| 8 | 채권 · 외화 유동성(여전채 AA- · 은행채 · CP A2 · 전단채 · CRS/IRS) | KR-CISS §4.3 ②③⑦ | ECOS 817Y002 에 없다 · 퀀티 Bond · ECO 경로 확인 필요 | 2차 |
| 9 | 배당 포함 총수익 · 배당락 · 사건별 DPS | 충실구현 5편 반복 결손(1707.05552 · 2001.04185 · 2002.06975 · 2003.02515 · 2011.05381) | 등급 수익률에 넣으면 측정 축(epoch)이 바뀌고 벤치 TR 은 2011~ 뿐 → 도훈 결정. 측정 축 밖 충실구현 전용 패널은 가능하나 퀀티 일별 항목의 존재는 미확인(Corporate Actions 메뉴만 확인) | 보류 · 도훈 결정 |
| 10 | 재무 2015Q1~ 연장 + 설비투자 · R&D · 재고 · 감가상각 · 보고 EPS · 희석주식수 | 2002.06975 · 2202.05702(설비투자 = 반복 병목) · 2011.05381 · 1806.01743 · `compute_growth/quality` DATA_NEEDED | Peer Analysis(분기 · 기간 열)라 일별 Update_File 방식이 아니다 · 원천 정책(퀀티 vs DART) | 보류 · 도훈 결정 |
| 11 | ETF NAV · 순자산 · 설정/환매 · PDF | DP_LETF_NAV · DP_ETF_HOLDINGS(2608.22768) | 가치 낮음~중간 | 보류 |
| 12 | 실적 발표일 | C18 · earnings_proximity · 2111.06655 | DART 접수일이 정본(빈티지 없는 '예정일'은 쓰지 않는다) — 퀀티는 보조 | 보류(DART 우선) |
| 13 | ESG 등급 | 대기열 4건 | 발표일 정렬 미확인(평가 기준일 정렬이면 미래참조 · 추측) | 보류 |
| 14 | 지수 밸류에이션(P/E · P/B · DY) | 2003.02515 Welch-Goyal · 2계층 국면 | 퀀티 지수 P/E 의 재무 반영 시점이 미상 → RAWDATA 시총 + 재무(C4)로 직접 계산하는 편이 PIT 통제가 쉽다 | 보류 |

### 2.4 이미 보유 — 수급 불요 · 거짓 결손

- **보유**: V-KOSPI200(IKS221 · 2003-01-02~ · `indices`) · 외국인 순매수(2000~) · 지수 TR 4종(2011~) · 시가총액 · 유동주식비율 · 상장/폐지일 · CD91 · WTI · 자사주(DART 결정 2015-01~ · 퀀티 분기 기중취득 2000~2025Q4).
- **거짓 결손**: `02_Infrastructure/ops/paper_router_prompt.md:37` 의 보유 목록에 indices(V-KOSPI · TR) · DART 내부자/자사주 · 퀀티 WTI/CD91 · 퀀티 분기 자사주 · NPS · 관세청이 없다 → 1604.05598 · 2209.12863 · 1306.5302 가 data_pipeline_required 로 쌓였다(조사). 새 데이터를 적재할 때 이 목록을 함께 고치고, `06_Registry/data_pipeline_queue.json` 항목은 삭제 없이 status 만 전이한다(append-only).

### 2.5 퀀티로 못 푸는 것(요약)

텍스트(뉴스 · 어닝콜 · 리포트 · 공시 원문) 약 25건 · 인트라데이 · 호가 · 종가단일가 4건 · 공급망 네트워크 3건 · FOMC 영상 · LLM 체크포인트 · Google Trends · 13F 수준 기관 보유(한국은 5% 대량보유만) · 개별주식 옵션 IV(거래 희소 · 추측) · 한국 CDS · 미국 HY/BBB OAS 장기(라이선스 · 추측) · 산업별 임금(ECOS/KOSIS) · 외국인 채권 순투자 · 외환보유액(ECOS 정본).

---

## §3 적재 조리법(순서대로)

### 3.0 선행 수리 — 기존 결함(새 데이터도 같은 경로를 탄다)

CLAUDE.md 인프라 허용 범위 ②(측정 신뢰 훼손 · 침묵 실패)에 해당한다.

| # | 결함(실측) | 수리 | 위치 |
|---|---|---|---|
| F1 | PowerShell 5.1 에서 결과가 1개면 해시테이블 `.Count` = 키 수(3). 11-06 END 'done 3/4' 는 실제 1/4(OHLCVS 만)(조사 · state 파일 ✔). 3파일 선택에서 1개 완료면 'done 3/3' 으로 미완료가 숨는다. **새 2책 묶음이면 1/2 완료가 'done 3/2' → incomplete=0** | `$sel` · `$pending` · `$doneN` 을 `@(...)` 로 감싼다 | `qw_refresh.ps1:277 · 281 · 294` |
| F2 | 책당 앵커 1개(대표 parquet max+1)라 뒤처진 시트를 건너뛴다 → 구멍 3건 ✔. 게다가 max 기준 앵커는 **내부 구멍**(뒤 날짜가 차면)을 영영 못 본다 | 앵커 = 출력별(시트별 B5). 최소 '출력 전체의 min(max)+1', 권장 **'최근 L 거래일 안의 첫 채움 미달일, 없으면 max+1'**(구멍 인지 · L 은 근거와 함께 등록부에) | `qw_refresh.ps1:138-142 · 189 · 201` + 등록부 |
| F3 | 컨센서스 적재가 `eps_1y` 하나의 max 이후만 붙인다 → 지표별로 뒤처진 날을 영구 손실 ✔(4지표 10-16 · 나머지 10-19) | 지표별 '받은 창의 날짜 = 교체'(수급 · 유니버스 적재기와 같은 규약) | `incremental_update_file.R:515 · 558-590` |
| F4 | 시트별 지평선 · 채움 관문이 OHLCVS 에만 있다 ✔(`ohlcvs_update_gate` :151-181 · 채움 검사는 '0칸'만) → 부분 갱신본이 적재됐다(수급 10-20~10-30 외국인 835~841행 · 개인 · 기타법인 0행 ✔) | 관문 일반화: 시트 지평선 일치 · B6 괄호 ≥ 목표일 · **날짜별 채움 수 / 직전 W 거래일 중앙값 ≥ 문턱**(문턱은 항목 이력에서 산출한 하위 분위 — 하드코딩 금지) · prior/not_advanced · 거부 = 적재 0 · 처리 미기록 | 공용 함수로 분리 → 수급 · 컨센서스 · 유니버스 · 새 책 |
| F5 | Update_File 의 미등록 xlsx 는 '처리됨'으로 기록돼 영영 적재되지 않는다 · 이름에 부분 문자열이 들면 엉뚱한 적재기가 돈다 ✔ | 등록부로 이름 → 적재기 디스패치 · 미등록 = stop | `incremental_update_file.R:838-865` |
| F6 | 신선도 감사가 패널마다 대표 파일 1개(eps_1y · investor_all · us_k200)의 max 만 본다 ✔ → 세 구멍 모두 FRESH | 출력별(컨센서스 12 · 수급 4유형 · 유니버스 8) + 최신일 채움 검사 + 최근 L 거래일 구멍 검사. **F2 와 함께 넣는다** — 리프레시로 못 고치는 경보는 아침 전체 리프레시 반복을 부른다(10-16 R2 선례) | `freshness_audit.R:70-72` |
| F7 | DATA_Key 가 책마다 다르다: OHLCVS 3,717 · 나머지 3책 3,668 → 신규 상장 53종이 수급 · 컨센서스 · 위생 질의에서 빠졌다. RAWDATA 2026-11-05 위생 표식(AdminStock · TradingHalt · UnfaithfulDisc · K200 · KQ150) 53/53 NA ✔. 위생 판정식은 NA 를 '정상'으로 통과시킨다 ✔(`factor_z_standard.R:84-89`) → 측정 축 위생(MC1)이 이 53종을 판정하지 못한다 | 모든 책 DATA_Key = OHLCVS 정본 · 동일성 시험 · 53종 위생 · 멤버십 이력 보충 수급 · 신규 상장 동기화 주체 지정 | 3책 DATA_Key 시트 · 새 시험 |

### 3.1 등록부 — 단일 정본

`02_Infrastructure/data/qw_updatefile_registry.json`(새). 드라이버 · 래퍼 · 적재기 · 신선도 감사 · 시험이 모두 이 파일을 읽는다(수치는 여기 한 곳 · 근거 문장과 함께).

```json
{
  "schema": "qw_updatefile_registry/v1",
  "books": [
    {
      "name": "ShortLending", "group": "ext", "order": 10,
      "path": "03_Universe/Update_File_ext/ShortLending_update.xlsx",
      "loader": "02_Infrastructure/data/qw_ext_ingest.py",
      "sheets": [
        { "sheet": "SS_BAL", "item_code": "<사전에서 확정>", "item_name": "<사전 이름 — 14행 대조>",
          "freq": "D", "fill_nonbiz": 0, "value_kind": "ratio",
          "output": ".cache/short_lending/ss_bal.parquet",
          "anchor": { "mode": "hole_aware", "lookback_td": "<값 + 근거>" },
          "fill_gate": { "window_td": "<값 + 근거>", "min_ratio": "<항목 이력에서 산출>" },
          "ban_calendar": "06_Registry/short_sale_ban_calendar.json",
          "avail_id": "QW_STK_SS_BAL" }
      ]
    },
    { "name": "Investor_Act", "group": "core", "order": 4,
      "path": "03_Universe/Update_File/Investor_Act_update.xlsx",
      "loader": "02_Infrastructure/data/incremental_update_file.R::incremental_investor",
      "anchors": [ { "path": ".cache/investor_stock/investor_all.parquet", "group_col": "InvestorType" } ] }
  ]
}
```

- 핵심 5책(Benchmark · OHLCVS · Universe_Support · Investor_Act · Consensus)은 지금 값 그대로 옮기고 대조 시험으로 고정한다(앵커만 F2 로 바뀐다).
- 이름 규칙: 새 책 이름에 `OHLCVS` · `Consensus` · `Investor` · `Universe_Support` 부분 문자열을 넣지 않는다(F5 전의 방어 · 그래서 수급 세분 책은 `FlowDetail`).

### 3.2 질의서 생성(원래 세션 · 퀀티와 Excel 이 놀 때)

1. **틀** = `03_Universe/Update_File/OHLCVS_update.xlsx` 사본(린 · 18MB · 163행 · DATA_Key 3,717 · 조사). 수급 · 유니버스 · 컨센서스 책(272~654MB · 서식 행 9,368 × 1만 열)은 틀로 쓰지 않는다.
2. **새 경로** = `03_Universe/Update_File_ext/<Name>_update.xlsx`. Update_File 밖에 두는 이유: 지금 적재기가 Update_File 을 비재귀로 훑어 미등록 파일을 버리고(F5), 꼬리 레인이 저장하는 동안 `[0b']` 가 같은 폴더를 읽으면 잠금 파일 · 옛 내용을 적재할 수 있다(09-19 실사고 계열).
3. **Excel COM 으로 편집**(애드인 조작 아님): 질의 시트 1장만 남기고 항목마다 시트를 복사 → 시트 이름 = 출력 id(예 `SS_BAL`) → `B10` = 항목 코드 · `B4` = D · `D4` = 0(Business · 주식 규약) · `B5` = 첫 수급 시작일 · `B6` = `CPD-1TD` → 9 · 11 · 14행은 **내용만 지운다**(애드인이 채운다) · 15행 아래는 **행 삭제**(지우기가 아니라 삭제 — 비대 방지) · A1 하이퍼링크(ScreenTip `Quantiwise7G`)와 A5/A6 라벨은 유지한다(드라이버가 이것으로 시트를 찾는다 ✔ `qw_refresh.ps1:201-203`).
4. **양성 대조**(첫 갱신 · 짧은 창 `B5` = 최근 5거래일): B6 괄호 해석 · 14행 항목명 = 사전 이름 · 날짜별 채움 수 · 권한 오류 여부 · (가능하면) 공개 수치 1일 대조. 실패한 항목은 빼고 기록한다. **이것이 '손으로 바꾼 B10 새 코드를 애드인이 그대로 쓰는가'의 첫 직접 대조다** — 지금까지는 같은 템플릿 사본이라는 간접 증거(xr:uid 공유)뿐이다(조사).
5. 저장 · 닫기 · sha256 기록.

### 3.3 qw_refresh 목록(`02_Infrastructure/ops/qw_refresh.ps1`)

- `-Group core|ext`(기본 core = 지금 동작). `$FILES` 를 등록부의 그룹에서 만든다.
- **시트별 B5**: 지금은 책 B5 하나를 모든 `Period*From*` 시트에 쓴다(:201) → 등록부의 시트 → 출력 → 앵커(F2)로 시트마다 쓴다.
- F1 수리.
- **수급 Excel PID 기록**: `$xl.Hwnd` → `GetWindowThreadProcessId`(이미 Add-Type 에 있다 ✔ :56) → `.cache/qw_refresh_excel_pid.txt`(§4.9 감시기용).
- `-FromOverride <name>=<yyyymmdd>`: 구멍 복구용 1회 강제 시작일(로그에 남긴다). 그 파일에 한해 `Is-Done`(state 의 목표일 완료 기록 · :121)과 'cache already >= target' 건너뛰기(:191)도 무시해야 한다 — 오늘 Universe_Support 처럼 완료로 기록된 파일은 지금 경로로는 다시 받을 수 없다.
- `Save-State` 원자 쓰기(tmp → `Move-Item -Force`): 꼬리 레인이 상태 파일을 쓰는 동안 다른 소비자(BOOK 리밸 Gate A)가 읽을 수 있다. 지금은 `Set-Content` 직접 쓰기다 ✔(:119).

### 3.4 상태

- **다운로드 상태** = 기존 `.cache/qw_refresh_state.json` 공유(이름이 키 · 그룹 간 이름 중복 금지).
- **래퍼 기록** = 그룹별: `QWUF_ONLY=ShortLending,FlowDetail` · `QWUF_LOG=.cache/qw_updatefile_unattended_ext.json` — 래퍼가 이미 두 환경변수를 받는다 ✔(`qw_updatefile_unattended.sh:31 · 42`). 마지막 줄 표지는 `QWUF_TAG`(기본 QWUF)로 구분할 수 있게 한다(선택 — 지금 `^QWUF` 소비자는 daily_refresh 자기 임시 로그와 시험 2개뿐 ✔).
- **적재 상태** = `.cache/qw_ext/_ingest_state.json`: 출력별 {last_ingested · published_horizon · gate 판정 · 지평선 채움 수 · item_code · 14행 항목명 · run_at}. 14행 이름이 바뀌면 경보(벤더 개명 · 코드 오류).

### 3.5 목표일 판정

- **목표일** = 벤치 최신일(`Get-Target` · 불변).
- **질의 완료** = 모든 질의 시트 B6 괄호 ≥ 목표일(불변).
- **공표 지평선(새 · 적재기)**: 시트별로 '채움 수 / 직전 W 거래일 중앙값 ≥ 문턱'을 만족하는 마지막 날. 그 뒤 날짜는 미공표로 보고 적재하지 않는다 → 앵커가 그 자리에 머물러 다음 밤 다시 받는다(공표 지연 k 를 코드에 박지 않는다). `목표일 − 공표 지평선` 이 가용 규칙 n 보다 크면 '공표 지연 이상' 경보.
- **공매도 금지 기간**: 기대 채움이 0 이다 → 정적 금지 캘린더로 관문 예외를 둔다. 없으면 앵커가 금지 기간에 멈춘다.
- **0 과 빈칸**: 공매도 0 은 정상 값이다 — 채움은 '빈칸 아님'으로 센다. 벤더가 미공표일을 0 · 빈칸 · 전일값 중 무엇으로 주는지는 첫 수급에서 실측한다(D4 는 비영업일 채움 옵션일 뿐).

### 3.6 파서 · 적재기(`02_Infrastructure/data/qw_ext_ingest.py` · 새)

- **스트리밍 파싱**: `us_update_stream_parse.py` 형식 ✔ — openpyxl `read_only` · 8행 코드 · 10행 항목 코드 · 14행 항목명 · 15행~ 데이터 · 빈 날짜에서 조기 종료 · 끝 빈 코드 제거 · 중복 종목 = 오류 · `PARSE_OK` 센티널 · 핸들 닫기.
- **관문**(F4 공용) → 거부면 적재 0 · 상태 기록 · rc 3.
- **병합**: 출력별 긴 표(Date · Ticker · Value) · 받은 창의 날짜 = 교체 · 행마다 `first_fetched_at` 보존 + `last_fetched_at` 갱신(퀀티에 빈티지가 없으니 첫 수급 시각을 의사 빈티지로 남긴다 — 정정 폭을 재는 재료) · 원자 쓰기(tmp → `os.replace` · `global_macro_ingest.py:103-105` 선례 ✔).
- **금지**: RAWDATA · `trading_calendar.parquet` · 핵심 Update_File 접근 0 · `trading_calendar.R` source 0(`.load_calendar()` 자동 재빌드가 `[0b']` 와 경합한다) · **가용일 계산 0**(관측 라벨만 싣는다 — Global_Macro 선례 ✔ `global_macro_ingest.py:11`).
- **종료 코드**: 0 적재 · 2 새것 없음 · 3 관문 거부 · 1 오류 · `Update_File_ext` 의 미등록 xlsx = 1.
- **최초 적재 모드**: `--initial --from <구간 xlsx>`(§3.12).

### 3.7 .cache 배치

- `.cache/short_lending/{ss_vol, ss_bal, slb_bal, credit_ratio}.parquet`
- `.cache/flow_detail/{foreign_own, foreign_limit, nb_pension, nb_trust, nb_pe, nb_fininv}.parquet`
- `.cache/qw_ext/_ingest_state.json`
- C 가 ECO 면 기존 `.cache/qw_global_macro.parquet` — `global_macro_ingest.py` SERIES 매핑 추가(미등록 기호면 exit 2 · 조사).
- 출력 이름은 사전 확인 뒤 확정한다. 하위 폴더는 `cache_freshness_audit` 의 고아 검사(최상위만) 밖이다(조사) → 3.8 등재가 유일한 감시다.

### 3.8 cache_registry(`02_Infrastructure/data/cache_registry.json`)

출력마다 1항목 — 기존 형식 그대로 ✔(path · producer · entry_fn · schedule · date_col · max_lag_days · depends_on · tier · _note):

```json
{ "path": ".cache/short_lending/ss_bal.parquet",
  "producer": "02_Infrastructure/data/qw_ext_ingest.py", "entry_fn": "(source)",
  "schedule": "daily", "date_col": "Date",
  "max_lag_days": "<기존 일간 퀀티 패널 10일(freshness_audit.R:70-71) + (공표 지연 n − 1)>",
  "depends_on": [".cache/benchmark.parquet"], "tier": 2,
  "_note": "출처 · 항목 코드 · 가용 규칙 id · 소비자" }
```

### 3.9 freshness_audit(`02_Infrastructure/ops/morning_steps/freshness_audit.R`)

- 출력마다 `audits$…` 한 줄 + 최신일 채움 검사(대표 1개가 아니다 · F6).
- **소비자가 생기기 전 새 출력은 보고 전용**: 지금 `role = "downstream"` 항목이 `[0c]` 판정에서 빠지는 구조 ✔(`freshness_audit.R:56-58 · :84` · `daily_refresh.sh:817-823`)와 `ensure_data_current` 의 같은 선례(:128 · 조사)를 `report_only` 역할로 일반화한다. 안 그러면 새 데이터 정체가 아침 전체 리프레시를 다시 부른다.
- 팩터 · 엔진이 소비하기 시작하면 판정 역할로 올린다.

### 3.10 가용 규칙(`06_Registry/fred_availability_rules.json`)

- 계열마다 1항목 — 기존 스키마 ✔: `id` · `name` · `aliases`(항목 코드) · `source` · `frequency` · `date_meaning` · `status` · `bounds[{type: "kr_trading_days_after", n, basis}]` · `vintage{revisions, evidence}` · `verdict_rows`. `version` 을 올리고 `coverage_note` 와 `test_fred_availability.R` A축에 넣는다.
- **basis = 공식 공표 규정 원문 링크**(거래소 공매도 공시 · 예탁결제원 대차 · 금투협 통계 · 벤더 Data Information). 확인 전에는 §2.2 의 보수 n.
- **date_meaning** 에 체결일 · 결제일 · 잔고 기준일을 적는다(공매도 잔고는 결제 기준으로 알려짐 — 추측).
- **패널 결합**: `fred_avail_annotate(panel, id)` → `avail_date ≤ d` 로 거른다. 이 함수는 Series_ID 가 섞일 때만 거부하므로 종목 패널에 쓸 수 있다 ✔(`fred_availability.R:392-416`). `fred_asof_join` 은 같은 관측일 2행 이상이면 멈추므로 패널용이 아니다(조사).
- **등록 시점**: 첫 소비 전. 미등록 계열은 결합이 거부된다(fail-closed ✔ semantics.fail_closed). 적재기는 규칙이 필요 없다(3.6).
- (선택 · 별건) 기존 수급 4종 · 컨센서스 · 유니버스도 같은 규칙으로 등록하면, 지금 갈라진 소비자 관례 3종(수급 `Date < sig_date` · 컨센서스 `Date <= sig_d` · 유니버스 같은 날 roll)이 한 곳으로 모인다.

### 3.11 시험

| 시험 | 내용 |
|---|---|
| `08_Tests/data/test_qw_ext_ingest.py`(새) | 합성 책: PARSE_OK · 끝 빈 코드 · 중복 종목 → 오류 · 지평선 불일치 · 채움 미달 → 거부 · 공표 지평선 자르기 · 겹침 교체 + first_fetched_at 보존 · 원자 쓰기 중단 모사 · 미등록 xlsx → rc 1 · 금지 기간 예외. 뮤테이션: 채움 비율 검사를 지우면 시험이 실패해야 한다 |
| 등록부 시험(새) | 핵심 5책이 지금 `$FILES`(:42-48)와 같다 · 모든 책 DATA_Key = OHLCVS 목록 · 이름 부분 문자열 금지 |
| `test_qw_updatefile_unattended.R` | ext 그룹 환경변수 경로 · PID 기준 진행 감시(Excel 교체가 정체가 아님) · F1('done 1/3' → incomplete=1) |
| `test_incremental_update_file_guards.R` | 미등록 xlsx → stop · 컨센서스 지표별 겹침 교체 · 일반화 관문 뮤테이션 |
| freshness 출력별 시험(새) | 한 지표만 뒤처지게 주입 → STALE · report_only 는 판정 제외 |
| `test_fred_availability.R` | A축에 새 id(basis 비어 있으면 실패) |
| 하네스 규칙 | 종료코드로 판정하는 시험은 카나리아 사전 점검(죽은 프로세스 rc 가 성공 기대값과 겹치지 않는지) · `08_Tests/hooks/run_all_hooks.sh` SUITES 편입 → `06_Registry/suite_totals_baseline.json` 재승격 |

### 3.12 최초 이력 수급(1회 · 밤 체인 밖)

- 시작 = 2000-01-03(측정 축 시작) 또는 항목의 첫 가용일. 늦게 시작하는 계열은 MC3 실효 시작 규칙이 흡수한다.
- 구간 분할(연 단위 B5/B6 고정 날짜)로 사본 책에 받는다 → `qw_ext_ingest.py --initial` 로 적재 → 구간 경계 연속성 확인.
- 첫 구간에서 소요 시간을 재고 전체를 추정한다(지금은 근거 없음).
- 받은 뒤 일일 증분(앵커 = F2)으로 넘어간다. base 책은 두지 않는다 — `[0a]` 식 base 재빌드가 base 지평선 뒤 증분을 덮는 위험(`parse_investor_quantiwise.R` 덮어쓰기 · 조사)을 피한다.

### 3.13 체인 배선

§4.3 의 3단계(퀀티 꼬리 레인 X).

---

## §4 리프레시 병렬화

### 4.1 지금(11-06 부팅 실행 · 조사)

07:20:44 시작 → `[0b]` 약 10분 → `[1pre]` 벤치 약 2분 → **`[1pre-qw]` 112.5분**(07:32:42→09:25:16 · END 'done 3/4' · 실제 OHLCVS 1개) → `[0b']` 약 12분 → bm-gate · `[1z]` · `[3]` · `[3b]` 약 1분 → `[4/7]` 4분 17초 → `[4gm]` 약 1분 → 캐시 감사 → **DART 09:46~**(분기 제출창 · 분기만 약 49분 추정). 퀀티와 무관한 DART · Arrow · ECOS · 비-return 이 퀀티 113분을 기다렸다. 과거 실측: 잠금 보유 41분~3시간 26분 · 잠금 해제 → Done 1시간 22분~3시간 24분(그중 `[9]` 스위트 총계 1시간 11분~2시간 55분).

### 4.2 의존성 표

| 단계(현행 줄) | 퀀티 | 읽는 것 | 쓰는 것 | 1단계 배치 |
|---|---|---|---|---|
| `[0a]` :119 | — | base xlsx | RAWDATA 등(드묾) | main |
| `[0b]` :127 | — | Update_File · 달력 재빌드 | RAWDATA(비원자 :487) · consensus · investor · US · trading_calendar | main(레인 시작 전) |
| `[1pre]` :161 | ● | `Benchmark_price.xlsx` | benchmark · indices(비원자) | main |
| `[1pre-qw]` :206 | ● | benchmark(목표일) · 달력(QwBaseNext) · 앵커 parquet | Update_File xlsx 제자리 저장 · qw_refresh_state | main |
| `[0b']` :226 | — | Update_File | RAWDATA · 달력 | main(합류 뒤) |
| bm-gate :269 · `[1z]` :287 · `[3]` :307 · `[3b]` :327 | — | benchmark · RAWDATA · `.cache/krx/stk_info` | universe · RAWDATA(원자) | main |
| Arrow :349 | — | KRX API · `03_Universe/raw/arrow` · `.cache/krx` | `03_Universe/raw/arrow` · `.cache/arrow_work` | **레인 A** |
| FRED :363 | — | ecos_krw_usd(전날 값) · 달력 | macro_regime · macro_fred | main |
| KTRI :376 | — | Arrow 산출 | ktri_indices | main(Arrow 뒤) |
| KTRI v3 · MSM · 국면 후보 · 원장 · v2 · SJM :387-497 | — | RAWDATA · KTRI · FRED · ECOS(전날) · 달력 | 국면 계열 | main |
| ECOS 원/달러 · 채권 :503 | — | ECOS API | ecos_krw_usd(비원자) · ecos_bond_rates(원자) | main — FRED · 국면이 '전날 ECOS'를 읽는 순서를 지킨다 |
| `[4gm①]` :519 | — | ECOS API | ecos_fx_majors(원자) · 리프레시 안 소비자 0 ✔ | **레인 A** |
| `[4gm②]` :525 | ● | `Global_Macro.xlsx` | qw_global_macro(원자) · 소비자 = THGNN 엔진뿐 ✔ | main → 3단계 **레인 X** |
| 캐시 감사 :543 | — | 등록부 캐시 | 보고 | main |
| `[5a]`/`[5a2]` :561 · `[5b]` :592 | — | RAWDATA(티커만 쓰는데 전 열을 읽는다 ✔ `data_collector_dart.R:233` · `_quarterly.R:175`) · DART API | dart 캐시 · fundamental_merged | **레인 D** |
| `[6a]`~`[6.5]` :617-762 | — | RAWDATA · 팩터 · fundamental_merged | 팩터 DB 등 | main |
| 비-return :767 | — | NPS · 관세청 | 자기 파일 · 소비자 0 | **레인 A** |
| `[0c]` :803 → 잠금 해제 :848 → `[7]`~`[9]` → Done :1003 | — | | | main |

- 퀀티 단계(●)끼리는 상호배제다: 같은 qwMain 세션 · 애드인을 쓰고, 무인 수급기는 'T0 뒤 시작한 Excel'을 자기 것으로 본다 ✔(`qw_updatefile_unattended.sh:72-79`).
- 레인 A 의 셋은 RAWDATA · 정본 벤치(`.cache/benchmark.parquet`) · 거래일 달력을 읽지도 쓰지도 않는다 ✔(`krx_arrow_pipeline.R` · `data_collector_ecos.R` · `refresh_nonreturn_sources.py` 판독). Arrow 가 쓰는 자체 벤치 사본(`03_Universe/raw/arrow/Benchmark_price_sheet1_start8.parquet`)은 KTRI 만 읽는다 ✔(`ktri_index_collector.R`) — main 의 합류 뒤다.
- RAWDATA 를 쓰는 단계(`[0b]` · `[0b']` · `[3]` · `[3b]`)가 끝나야 RAWDATA 소비자가 돈다 — 퀀티가 오늘 데이터를 만드는 동안 그 데이터를 쓰는 단계는 겹칠 수 없다. 겹칠 수 있는 것은 퀀티 산출에 기대지 않는 단계뿐이다.

### 4.3 새 순서

**1단계(출력 불변 — 지금 구현)**

```
main   잠금 · env · QVENV_PY 탐색(현행 :163-167 을 위로) · DR_RUN_DIR
main   [0a] → [0b]                                      ← RAWDATA 쓰기 끝
 ├▶ 레인 D: [5a]+[5a2](달 스탬프) → [5b]
 └▶ 레인 A: Arrow → [4gm①] ECOS 6통화 → 비-return
main   [1pre] 벤치(퀀티) → [1pre-qw] Update_File 4종(퀀티 · 상한 없음 — 도훈 10-20)
main   ◀ 합류 D · A   (QWUF 판정 직후 · 현행 :225 와 :226 사이)
main   [0b'] → bm-gate → [1z] → [3] → [3b] → [4/7](Arrow 뺌 · 나머지 순서 그대로) → [4gm②] → 캐시 감사
main   → [6a] … [6.5] → [0c] → 잠금 해제(:848 그대로) → [7] … [9] → Done(그대로)
```

- 합류를 `[0b']` 앞 한 곳에 두면 그 뒤 main 은 직렬판과 같은 입력을 본다. 레인 D 의 RAWDATA 읽기는 `[0b]` 뒤 ~ 합류 전에만 일어나 RAWDATA 쓰기와 겹치지 않는다. 레인은 `[1pre]` · `[1pre-qw]` 가 쓰는 파일(Benchmark xlsx · benchmark/indices · Update_File · qw_refresh_state)을 읽지 않는다.
- 직렬판과 달라지는 것(데이터는 불변): DART 가 캐시 감사보다 먼저 끝난다(감사 보고가 DART 신선도를 더 새로 본다) · main 의 run_r 번호(r<N>)가 당겨진다(레인 스텝은 이름표 · `[7]` 실패 서명이 한 번 '원인 변경'으로 울릴 수 있다).
- 퀀티를 건너뛴 밤(벤치 rc=3): 합류 D 에서 DART 끝까지 기다린다 → 총시간은 직렬과 같다.

**3단계(새 퀀티 질의서와 함께 — 퀀티 꼬리 레인 X)**

```
main   [1pre-qw] 판정 직후(퀀티가 비었고 벤치 rc≠3 일 때만)
 └▶ 레인 X: qw_updatefile_unattended.sh(QWUF_ONLY=ShortLending,FlowDetail · QWUF_LOG=…_ext.json) → qw_ext_ingest.py
            → [4gm②] Global_Macro 수급 → global_macro_ingest.py
main   [0b'] → … → [4/7] → [6a] … [6.5]                (레인 X 와 겹친다)
main   ◀ 합류 X → 캐시 감사(여기로 옮김) → [0c] → 잠금 해제 …
```

- 레인 X 는 퀀티를 쓰는 유일한 레인이고 핵심 4책이 끝난 뒤에만 시작한다 → 퀀티는 여전히 한 줄로 선다.
- 레인 X 가 쓰는 것(`Update_File_ext/*.xlsx` · `Global_Macro.xlsx` · `.cache/short_lending` · `flow_detail` · `qw_global_macro` · 상태 JSON)은 main 이 그동안 쓰는 것과 겹치지 않는다. 달력 · RAWDATA 를 읽지 않는다(§3.6).
- **합류 위치 규칙**: `[6a]` 팩터가 레인 X 산출을 소비하기 시작하면 합류 X 를 `[6a]` 앞으로 옮긴다 — 시험 S9 가 이 규칙을 고정한다.
- 늘어나는 잠금 = max(0, 레인 X − main 의 `[0b']`~`[6.5]` 소요) — 실측(timeline)으로 판단한다.

### 4.4 구현 골격

```bash
DR_RUN_DIR=$(mktemp -d /tmp/qm_dr_run_XXXX); declare -A DR_LANE_PID
dr_lane_start(){ local n=$1 f=$2
  ( DR_FAILED=(); DR_LANE=$n
    trap 'printf "%s\n" "${DR_FAILED[@]+"${DR_FAILED[@]}"}" > "$DR_RUN_DIR/$n.failed"' EXIT
    "$f" ) > "$DR_RUN_DIR/$n.log" 2>&1 &
  DR_LANE_PID[$n]=$!; echo "$n $!" >> "$LOCKDIR/lanes"
  echo "[lane:$n] 시작 pid=$! 로그=$DR_RUN_DIR/$n.log"; }
dr_lane_join(){ local n=$1 rc x; wait "${DR_LANE_PID[$n]}"; rc=$?
  echo "──── [lane:$n] 재생(rc=$rc) ────"; cat "$DR_RUN_DIR/$n.log"; echo "──── [lane:$n] 끝 ────"
  if [ -f "$DR_RUN_DIR/$n.failed" ]; then
    while IFS= read -r x; do [ -n "$x" ] && DR_FAILED+=("$x"); done < "$DR_RUN_DIR/$n.failed"
  else DR_FAILED+=("lane_$n:no_report(rc=$rc)"); fi; }
```

- 레인 시작 때 `DR_FAILED=()` 로 비운다 — 서브셸은 부모 배열을 복사해 시작하므로 비우지 않으면 합류 때 중복된다(조사 프로브 실측).
- 레인 안 `run_r` 는 모두 이름표를 단다(`dart_annual` · `dart_daily` · `arrow` · `ecos_fx`) — 원래 세션 스크래치판 `run_r` 의 2번째 인자 ✔(`scratchpad/msm_switch/daily_refresh.sh:73-94`).
- `wait` 는 PID 를 지정한다(인자 없는 wait 금지). 끄기 스위치 `QVEST_DR_LANES=0` → start 는 등록만, join 이 그 함수를 동기 실행(직렬판 순서로 시험 가능).
- 레인이 끝나면 즉시 `.cache/dr_lanes_latest.json` 을 원자 기록한다 — 퀀티가 멈춘 밤에도 레인 결과를 볼 수 있다. `$DR_RUN_DIR/timeline.tsv`(레인 · 단계 · 시작/끝 epoch)로 단축을 실측한다.
- `daily_refresh.sh` 에는 `refresh_barrier` · `qm_rawdata_writer` 문자열을 주석에도 쓰지 않는다(`test_refresh_barrier.sh` H5).
- DART 의 RAWDATA 읽기를 `col_select = "Ticker"` 로 바꾼다(`data_collector_dart.R:233` · `_quarterly.R:175`) — 결과(고유 티커)는 같고 메모리 · 시간이 준다. 퀀티 컨센서스 갱신 Excel 커밋이 약 4.7GB(09-19)라 겹치는 구간이 생긴다. 지금 물리 메모리 31.7GB · 여유 8.9GB · 커밋 여유 49.9GB ✔(10:05).

### 4.5 실패 의미

| 상황 | 처리 | DR_FAILED 기록 | 다른 레인 · main |
|---|---|---|---|
| 레인 D/A 단계 실패(rc≠0) | 레인 안에서 이름표로 누적 → 합류 때 병합 | `dart_annual(rc=..)` · `dart_daily(rc=..)` · `arrow(rc=..)` · `ecos_fx(rc=..)` | 영향 없음 |
| 레인 프로세스 사망 | 실패 파일 없음 | `lane_<n>:no_report(rc=..)` — 정상으로 접지 않는다 | main 계속 |
| 벤치 수급 rc=3 | `[1pre-qw]` · 레인 X 건너뜀(지금과 같음) | `qw_updatefile_skipped` 등 | 레인 D/A 정상 |
| 퀀티 정지(상한 없음 · 11-01형) | main 이 `[1pre-qw]` 에서 대기 · 레인 D/A 는 끝까지 · 결과는 `dr_lanes_latest.json` | 합류 뒤에만 병합 | 잠금 held → 러너 대기(지금과 같음) |
| 레인 D 지연 | 합류 D 에서 대기(DART 요청마다 timeout 30 · 조사) | — | 총시간 ≤ 직렬 |
| 레인 X 실패 | 레인 안 누적 → 합류 X 때 병합 | `qw_ext_fetch(..)` · `qw_ext_ingest(rc=..)` · `global_macro_*` | RAWDATA 체인 무영향 |
| main 비정상 종료 | EXIT trap 이 살아 있는 레인을 **기다린 뒤** 잠금 삭제(§4.6) | — | — |
| 교착 | 없음 — 대기는 main → 레인 합류뿐, 레인은 main 을 기다리지 않는다 | | |

### 4.6 잠금

- `LOCKDIR="/tmp/qm_daily_refresh.lock"`(줄머리 · 시험 패리티) · pid = main `$$` · 해제 지점 `:848`(`[0c]` 뒤)은 그대로다. 모든 레인이 `[0c]` 전에 합류하므로 '잠금 해제 = 데이터 레인 전부 종료' 의미가 유지된다.
- 추가 = `$LOCKDIR/lanes`(레인 이름 · pid · winpid). `refresh_barrier` · `ensure_data_current` 는 pid 파일만 읽으니 무해하고, 레인은 main 의 MSYS 자손이라 배리어가 self 로 본다(조사).
- **강제 종료 대신 기다린다**: DART 분기 원장은 비원자 쓰기다 ✔(`data_collector_dart_quarterly.R:353 · 372`) → 중간 종료 = 파일 손상 위험. main 의 EXIT trap 과 고아 잠금 인계 모두 살아 있는 레인이 끝날 때까지 기다린다(고아 DART 와 새 DART 가 겹치면 일 10,000콜 쿼터를 이중으로 쓴다 — 06-11 재진입 가드의 이유).

### 4.7 Done · [7] 계약

- Done 줄 형식 · 위치(모든 후처리 뒤 · 실행당 1개) · 종료 코드는 그대로다.
- 레인 실패는 `[0c]` 전에 병합된다 → `export DR_FAILED_SO_FAR`(:855)에 들어간다 → `[7] tg_sent=TRUE reported=X` 의 X 와 Done 목록이 같다(`scheduler_task_health.sh` 면제 조건 유지).
- 레인 로그는 테두리 안에 원문 그대로 재생한다 → 줄머리 grep(`^QWUF` · `[0b'/7]` · `[regime-append/` · `[7] tg_sent=` · `=== Daily Refresh v2 Done`)과 Superfan 규칙(`06_Registry/superfan_components.json`)이 그대로 맞는다. 레인은 `=== Daily Refresh v2` 로 시작하는 줄을 쓰지 않는다(task_health 구간 경계).
- 연구 러너(P3R03 · P2R05 `measure.sh` · `round_core/round.sh`)의 'Done 줄 수 증가' 판정은 그대로다.

### 4.8 기대 단축

| 밤 유형 | 지금(직렬 · 실측) | 1단계 후 | 근거 |
|---|---|---|---|
| 퀀티가 일함(퀀티 창 113~157분) | DART 25.7~31.5분이 퀀티 뒤에 줄 선다 | 잠금 · Done 약 29~35분 빨라짐(10-18 잠금 3시간 26분 → 약 2시간 56분) | DART 6회 실측 + Arrow 약 1분 + ECOS 6통화 수십 초 |
| 11-06 같은 분기 제출창 | DART 약 49분(추정) | 약 50분 | 09:58 기준 800/3,292사 진행률 |
| 퀀티 건너뜀(10-20A형) | 퀀티 창 수 분 | 수 분 | 합류 D 에서 DART 를 기다림 — 확장 1b 로 개선 |
| 퀀티 정지(11-01형) | 이후 단계 0 | 시간 효과 없음 · DART · Arrow · ECOS 6통화 · 비-return 은 갱신 | — |
| 3단계(새 질의서 약 70분 · 가정) | 핵심 체인 안에 넣으면 RAWDATA 이후 전부 +70분 | RAWDATA 체인 지연 0 · 잠금 연장 = max(0, 레인 X − main 잔여) | 첫 밤 실측 |

- 참고: 임계 경로는 퀀티 자체다. OHLCVS 가 매일 base 끝(03-27) 다음 날부터 약 150일 창 전체를 다시 받고(11-06 약 43분 · 조정 계열이라 설계상 필요), 수급 · 유니버스 · 컨센서스 책은 서식만 있는 빈 셀이 시트당 약 2,400만 개다(조사). base 재수출 주기화 · 서식 행 정리 · 증분용 활성 종목 키(열 약 −31%)는 병렬화보다 클 수 있다(효과는 추측 · 실측 필요 · 별건).

### 4.9 정체 감시 오경보 수리(끝난 Excel 의 CPU 누적)

- **현상**: `progress()` = 'T0 뒤 시작한 모든 EXCEL 의 CPU 합' ✔(`qw_updatefile_unattended.sh:72-75`). 드라이버는 파일마다 Excel 을 띄우고 끈다 ✔(`qw_refresh.ps1:196 · 234`) → 한 파일이 끝나면 합이 떨어지고, 새 Excel 이 이전 누적을 넘을 때까지 '증가 없음'이 이어진다. 11-06: OHLCVS 완료 직후 '증가 없음' 31회 연속(2,611~4,565초) → 4,627초에 'CPU 1503초'로 복귀(조사). 기본값(STALL_N=0 · HARD=0)이라 끊지는 않지만, 끊기를 켜면 일하는 수급을 죽인다. `cleanup()` 도 같은 기준이라 동시에 뜬 다른 Excel(사람 · 다른 레인)까지 끊을 수 있다.
- **수리**: ① 드라이버가 자기가 띄운 Excel PID 를 파일에 남긴다(§3.3) ② 감시기는 그 PID 들의 CPU 만 본다 — PID 별 증분 합(새 PID 등장 = 진행 · 끝난 PID 는 마지막 값 유지 → 누적이 줄지 않는다) ③ `cleanup()` 은 그 PID 만 끝낸다.
- **시험**: `QWUF_PROGRESS_CMD` 주입으로 'Excel 교체' 순서(100 → 200 → 새 PID 50 → 60)를 주고 정체 0 을 단언한다. 뮤테이션(합산 방식으로 되돌림)에서 시험이 실패하는지 확인한다.

### 4.10 퀀티 뮤텍스(스크립트 간)

`/tmp/qm_qw.lock`(mkdir · pid). 잡는 쪽: `qw_updatefile_unattended.sh`(core · ext) · `quantiwise_fetch.py`(벤치 · Global_Macro) · `run_pg2_rebalance_full.sh` `[0]`(`qw_refresh.ps1` 직접 호출 · 조사) · 수동 스크립트. 정책 = 대기(로그만 · 상한 없음 — 10-20 '제한시간 없애'와 같은 기조). 오늘 원래 세션이 '[4gm] 을 지나면 시작'으로 손수 맞춘 직렬화 ✔(`qw_refresh_3files_relogin_20261106.log`)를 계약으로 만든다.

### 4.11 시험 계획(`08_Tests/data/test_daily_refresh_lanes.sh` · 새)

하네스: 실제 `daily_refresh.sh` · `dr_lanes.sh` 를 샌드박스로 복사 → LOCKDIR · LOGFILE 을 샌드박스 경로로 치환(운영 잠금 문자열이 남지 않았는지 단언) → `resolve_project.sh` 스텁 → PATH 앞 Rscript 스텁이 run_r 임시 .R 내용 · 스크립트 경로를 단계 id 로 매핑해 `<epoch> <레인> <단계> start/end` 를 기록하고 `STUB_DUR_<단계>` 만큼 자고 `STUB_RC_<단계>` 로 끝난다 → python · `qw_updatefile_unattended.sh` · `suite_totals_watch.sh` 스텁.

| 시나리오 | 단언 |
|---|---|
| S1 정상 | 간선마다 end(A) ≤ start(B) · 퀀티 3종 겹침 0 · DART 창 ∩ `[0b']`/`[3]`/`[3b]` = ∅ · 양성 대조(퀀티를 느리게 하면 DART 가 `[1pre-qw]` 와 실제로 겹친다) · Done 1줄 · exit 0 |
| S2 DART rc=1 | DR_FAILED 에 `dart_daily(rc=1)` 1회 · Done ★실패 · exit 1 · 퀀티 단계 전부 실행 |
| S3 벤치 rc=3 | `qw_updatefile_skipped` · `[4gm②]`(또는 레인 X) 건너뜀 · 레인 D/A 정상 |
| S4 레인 kill -9 | `lane_D:no_report` · main 무교착 · 잠금 해제 · Done 존재 |
| S5 합류 대기 | 퀀티가 빠르면 RAWDATA writer 시작 ≥ DART 끝 · 느리면 대기 ≈ 0 |
| S6 로그 | 레인 블록이 테두리 안에서 연속 · 앵커 표지 각 1회 · task_health 판정기 면제 일치 |
| S7 잠금 | 데이터 구간 held · 레인 자손 = self · 레인 종료 뒤에도 존재 · `[0c]` 뒤 해제 · ensure 대기가 해제를 감지 |
| S8 끄기 | `QVEST_DR_LANES=0` → 단계 겹침 0 · 순서 = 직렬판 |
| S9 레인 X | `Update_File_ext` 책을 `[0b']` 가 건드리지 않음 · 합류 X 가 `[0c]` 앞 · 팩터 코드가 레인 X 산출 경로를 참조하면 합류가 `[6a]` 앞이어야 통과 |

뮤테이션: M1 합류 D 삭제 → S5 실패 · M2 실패 파일 병합 삭제 → S2 실패 · M3 레인 DR_FAILED 리셋 삭제 → 중복 검출 · M4 레인 출력을 main stdout 으로 → S6 실패 · M5 잠금 해제를 합류 앞으로 → S7 실패 · M6 합류 X 를 `[0c]` 뒤로 → S9 실패. 뮤테이션은 소스 텍스트 치환으로 만들고 치환이 실제로 적용됐는지 확인한다(deparse 치환은 줄바꿈에서 조용히 빗나간다 — 10-15 교훈). SUITES 편입 → 기준선 재승격. 실전 그림자: 첫 2~3밤 timeline 을 예측과 대조하고 `[dart]` 티커 수 · Done/`[7]`/task_health 판정을 확인한다.

### 4.12 기존 시험 수정 지점

- `08_Tests/data/test_daily_refresh_qw_block.sh`: `# --- [1pre-qw]`~`# --- BMG-01` 을 잘라 실행한다 → 합류 D 가 그 안에 들어가므로 하네스에 `dr_lane_join(){ :; }` 스텁 1줄.
- `test_daily_refresh_r_blocks.R`: run_r 여닫기 수 교차계수 — 레인 함수 안에서도 `run_r '` … `' <이름표>` 형태 유지.
- `08_Tests/ops/test_refresh_barrier.sh`: :52 LOCKDIR 패리티 · :456 H5 금지 문자열.
- `test_rawdata_bm_ret_sync.R` F2: `[0b/7]` · `[0b'/7]` · `[3/7]` < `[3b]` < `[6a/7]` 텍스트 위치 — 레인 함수를 위쪽에 정의할 때 이 echo 문자열을 넣지 않는다.
- `test_regime_ledger_c11.R` T5 · T8: 무접촉(원장 루프 · 국면 블록은 main 에 남는다).
- `test_dart_candidate_years.R` E3: 레인 D 의 `dart_run_pipeline(` 호출에 `years=` 를 넣지 않는다.
- `08_Tests/hooks/test_scheduler_task_health_verdict.sh`: 레인 실패(레인 항목이 reported · Done 양쪽에 있음) 케이스 1건 추가.

### 4.13 설치 순서 · 주의

1. PID 491(07:20 시작 · 10:05 현재 DART 단계 ✔)이 **Done 줄을 찍고 끝난 뒤**에만 `daily_refresh.sh` 를 바꾼다. 실행 중인 bash 스크립트를 고치면 중도 사망한다(09-18 실사고) · Windows 는 실행 중 스크립트의 `os.replace` 를 거부한다(WinError 5). 기준은 잠금 해제가 아니라 프로세스 종료다(잠금 해제 뒤에도 후처리가 1시간 22분~3시간 24분 돈다).
2. 원래 세션의 스크래치판(`run_r` 이름표 · MSM as-of · `scratchpad/msm_switch/daily_refresh.sh` 1,023줄 ✔)을 먼저 설치하고 그 위에 레인을 얹는다.
3. 시험 통과 → 00:03 예약 전에 설치 → 첫 2~3밤 그림자 측정.
4. 레인 헬퍼를 별도 파일(`dr_lanes.sh`)로 둬도 같은 규칙(실행 중 교체 금지)을 따른다.

### 4.14 결정이 필요한 확장

- **1b DART 를 `[0b']` 뒤까지 겹치기**(티커 스냅숏 · 합류를 `[6a]`/`[0c]` 앞으로): 퀀티를 건너뛴 밤도 약 8~30분 단축 · 대가 = 그날 처음 적재된 신규 상장의 DART 수집이 하루 늦다.
- **1c FRED · ECOS 원/달러 · 채권 · regime_daily_v2 · SJM · MSM as-of 를 퀀티 중 레인으로**: 약 3~4분 + 퀀티가 멈춘 밤에도 거시 갱신 · 대가 = 출력 변화(FRED · 국면이 '전날 ECOS' 대신 '그날 ECOS'를 읽는다 · `[1pre]` 직후 달력을 일찍 재빌드해야 해 새 거래일의 source 라벨이 benchmark 로 남는다 — `Get-QwBaseNext` 영향 검증 필요).
- **2 Done 조기화**: 연구 러너 기준 1시간 22분~3시간 24분 빨라진다. (2a) `[8.2]` 뒤 Done 을 찍고 `[7.9]`~`[9]` 를 이어간다 (2b) 유지보수 꼬리를 분리 실행한다(작업 스케줄러가 자식을 끊는지 미검증) (2c) 잠금 해제 때 별도 'Data Done' 표지를 찍고 러너만 그것으로 옮긴다(Done 줄 불변). Q 권고 = 2c. 대가: 러너와 `[9]` 스위트 수집이 CPU 를 나눠 쓴다.
- `fred_robust_fetch_all`(fred_macro · fred_macro_wide 생산자 · 아침 체인 전용 · 11-06 lag 13 CRITICAL)을 밤 레인 A 에 넣기: 밤 국면 빌드 입력이 신선해지는 대신 출력이 바뀐다.
- KRX 휴장일 등록부 정기 fetch 를 레인 A 에 넣기: 임시공휴일을 반영해 부팅 '퀀티 미최신' 오탐을 막는다(지금 체인 밖).

---

## §5 원래 세션이 단말 · Excel 로 할 일 · 도훈 결정

### 5.1 지금 확인할 것(긴급)

1. **진행 중인 재수급(09:44~ · B5 = 캐시+1)은 구멍 3건을 메우지 못한다** ✔
   - Universe_Support: 'cache already >= target (next 20261106 > 20261105)'로 받지 않고 끝났고, state 에 20261105 완료로 기록됐다 ✔ → `us_sector_lv2` 의 10-30 월말 행이 없다(최신 10-19 ✔).
   - Investor_Act: B5=20261031 ✔ → 10-20~10-30(9거래일)의 개인 · 기타법인 0행 · 외국인 835~841행(평시 약 2,353행) ✔ 을 다시 받지 않는다.
   - Consensus: B5=20261020 이 될 차례 → coverage · esbr · escr · op_profit_fy1 의 10-19(최신 10-16 ✔)가 영구 결손이 된다.
   - ★이번 수급분이 적재되면 수급 · 컨센서스 구멍은 **내부 구멍**이 되어, max 기반 앵커로는 다시 보이지 않는다.
2. **완료 판정은 END 줄의 done 수가 아니라 `.cache/qw_refresh_state.json`** 으로 한다 — 3파일 선택에서 1개만 완료되면 'done 3/3' 으로 찍힌다(F1).
3. **적재(`incremental_update_all()`)는 PID 491 이 잠금을 놓은 뒤에** — 그 프로세스가 DART 다음 `[6a]` 팩터 빌드에서 컨센서스 · 수급을 읽는다. 아무것도 하지 않으면 오늘 밤 00:03 `[0b]` 가 지금 수급분을 자동 적재한다.

### 5.2 단말 · Excel 작업 순서와 위험(퀀티 · Excel 이 놀 때만 · 한 번에 하나)

| 순서 | 작업 | 위험 · 주의 |
|---|---|---|
| ① | 지금 재수급 마무리 → state 로 완료 확인 | 다른 PC 중복 로그인으로 끊기면 스탬프만 바뀐다 → 단말의 #32770 'Quantiwise7G' 상자부터 본다 · 재로그인은 상대 PC 세션을 끊으므로 도훈 확인 뒤 |
| ② | **구멍 복구 수급**: Investor_Act B5=20261020 · Universe_Support B5=20261030. `qw_refresh.ps1` 은 B5 를 캐시로 덮어쓰므로(:189 · :201) Excel 에서 B5 를 직접 고쳐 Refresh 링크를 누르거나 `-FromOverride` 수리 뒤 실행 → 잠금 해제 뒤 적재 → 10-20~10-30 4유형 일별 행 · `us_sector_lv2` 10-30 확인. Consensus 4지표 10-19 는 F3 수리 뒤 B5=20261019 | 수급 · 유니버스 적재기는 받은 창의 날짜를 통째로 교체한다 → 다시 받은 것도 부분이면 부분으로 덮는다 → **적재 전에 xlsx 날짜별 채움 수를 먼저 본다** · 대용량 책(272~654MB) 저장 수십 분 |
| ③ | 항목 사전 수급(§1.3) | 숨은 'Item Lookup' 모달 · 브라우저로 열릴 수 있음 · 벤더 파일 git 금지 |
| ④ | 후보 항목 양성 대조 · 권한 시험(사본 책 · 짧은 창) | '아이템 조회 권한이 없는 ID' · 14행 이름 불일치 = 코드 오류 |
| ⑤ | 새 질의서 2책 작성(§3.2) + (C) ECO 열 추가(ECO Wise 대화상자) | 틀은 린 OHLCVS_update 사본 · 이름 부분 문자열 금지 · ECO 손 추가의 갱신 여부는 미확인(10-20 시험은 끊긴 세션 중이었다) |
| ⑥ | 최초 이력 수급(구간 분할 · 밤 체인 밖) | 첫 구간으로 소요 측정 · 00:03 체인과 겹치지 않게 |
| ⑦ | DATA_Key 동기화(3책 → OHLCVS 3,717종 · **끝에 붙이기**) + 신규 상장 53종 위생 · 멤버십 이력 보충 수급(**전 종목 책 그대로 · 창만 넓혀**) — 단계 = 표 아래 '⑦ 절차' | 3책이 수백 MB — 저장 시간 · ~~보충은 해당 종목만 담은 사본 책으로~~ **정정(2026-11-06 · F7 2차 검증)**: 사본 책 보충 금지 — 세 적재기 모두 받은 창의 날짜를 **전 종목 통째로 교체**한다(`incremental_update_file.R` 작업 트리 수급 :1098 · 유니버스 :1242 · 컨센서스 :1016 / HEAD :665 · :781 · :591) → 53종만 담은 책을 적재하면 그 날짜의 나머지 약 3,670종 값이 지워진다(F7 보고서 §2.4 ③ 과 같은 판단) · 정렬 위치 삽입도 금지(수급 전 저장이면 전 종목 값이 이웃 열에 붙는다) |
| ⑧ | (선택) 3책 서식 행 정리(질의 시트 24:9368 행 삭제) | 백업 뒤 · 전후 갱신 시간 실측 |

**⑦ 절차**(2026-11-06 정정 · F7 2차 — 구 '보충은 해당 종목만 담은 사본 책으로'를 대체한다. 근거 · 실측 = F7 보고서 `04_Research/01_reports/quantiwise_data_expansion_20261106/F7_datakey_hygiene.md` §2.3 · §2.4(③ = 보충 수급 단계). 스크래치는 지워질 수 있어 단계를 여기 옮겨 둔다)

0. **전제**(하나라도 아니면 시작하지 않는다): 퀀티 자동화 0(`qw_refresh.ps1` · `qw_updatefile_unattended.sh` · `quantiwise_fetch.py` 프로세스 · 스크립트가 띄운 EXCEL 없음) · 일일 리프레시 잠금 없음(00:03 체인 · 부팅 리프레시를 피한다) · ② 구멍 복구와 같은 책을 동시에 만지지 않는다(합칠 수 있다 — 4단계 창이 그 구멍을 덮는다) · 단말 로그인.
1. **백업**: 3책(Universe_Support · Investor_Act · Consensus)을 `Copy-Item`(수정 시각 보존)으로 프로젝트 안 · Update_File 밖(예 `03_Universe/_backup_datakey_<YYYYMMDD>/`)에 둔다. Update_File 안에 `*.xlsx` 이름으로 두지 않는다(적재기가 새 파일로 집는다 — F5).
2. **DATA_Key 맞추기 = 끝에 붙이기**: 각 책 DATA_Key 의 기존 `D2:E3669`(3,668행)는 그대로 두고, OHLCVS 에만 있는 종목(11-06 실측 53)을 `D3670:E3722` 에 붙인다(Excel COM · 수급 없음). 정렬 위치 삽입 · 행 삭제 · 열 삽입 · 8행 직접 편집 · A/B 수식 수정 금지 — 질의 시트 8행이 `{=TRANSPOSE(DATA_Key!A2:A10002)}` 라 가운데 삽입 뒤 수급 전에 저장되면(드라이버 finally 저장 · 갱신 중 자동 저장 포함) 전 종목 값이 이웃 종목 열에 붙는다. 3책 전용 4종(A067250 · A194610 · A300090 · A402360)은 지우지 않는다(지우면 뒤 열이 밀린다).
3. **저장 전 검증**: DATA_Key `A3670:A3722` = 붙인 코드 · `A3723` 빈칸 · 각 질의 시트 8행 3,722열(EMD) = 마지막 붙인 코드 · 3,723열 빈칸 · 앞 3,668열(B~EKC) = 붙이기 전 배열과 같음 · 각 질의 시트 FilterMode = False(`_FilterDatabase` 는 책마다 둘 — 첫째 · 넷째 시트). 통과 = 저장 · 아니면 저장 없이 닫는다.
4. **보충 수급 = 그 전 종목 책 그대로, 창만 넓혀 1회**: `qw_refresh.ps1 -SkipLogin -Only <책> -FromOverride <책>=<YYYYMMDD>`(-FromOverride 판 = 커밋 2ee5f2973 이후). 창: Universe_Support `20221201`(53종 RAWDATA 첫 행 최소 2022-12-27 을 덮는 월초 · 월간 약 48 스냅숏 · 10-30 Sector_Lv2 구멍도 덮는다) · Investor_Act `20250617`(50종 전 구간 · 10-20~10-30 구멍도 덮는다 — 지슨 · 이전상장 2종의 그 전 구간까지 원하면 `20230517`) · Consensus 선택(F3 설치 뒤 · `20250617`). 완료 판정 = `.cache/qw_refresh_state.json` + 시트별 B6 괄호 ≥ 목표일(END 줄 아님).
5. **수급 뒤 확인(적재 전 · 사본에서)**: 8행 코드 3,721 · 10행 항목 코드 · 14행 항목명 유효 칸 3,721 · 붙인 53열의 9행 이름이 N/A 아님 · 최신 스냅숏의 53열 값 존재(상장 전 날짜 제외) · **창 안 날짜별 채움 수가 직전 수준** — 부분 수급본이면 적재하지 않는다(창 안 날짜가 부분값으로 통째로 바뀐다 · F4 관문의 날짜별 채움비 검사 대상).
6. **적재 · 사후 검증**: 일일 리프레시 잠금 해제 뒤 수동 `incremental_update_all()` 또는 00:03 `[0b]` → `[3]` `apply_universe_mapping()` 에서 RAWDATA 표식이 생긴다. us_* 에 53종 등장 · K200=1 개수 2025-11-28 이후 200 · KQ150=1 2026-03-27 이후 150 회복(양성 대조 — 회복 안 되면 다른 결손) · `Rscript 08_Tests/data/test_hygiene_flag_coverage.R` L1 gap 0.
7. **되돌리기**: 저장 전 실패 = 저장 없이 닫기 · 저장 뒤 · 적재 전 = 1단계 백업을 `Copy-Item` 으로 복원(수정 시각 보존이라 적재기가 변경으로 보지 않는다) · 적재 뒤 = 다음 정상 수급의 같은 창이 덮는다(교체 규약).
- 앞으로의 신규 상장도 4책 모두(OHLCVS 포함) 끝에 붙이고 같은 전 종목 창 보충으로 채운다.

공통: 퀀티 작업끼리 겹치지 않는다(같은 qwMain 세션) · 일일 리프레시 `[1pre]`~`[4gm]` 구간과 겹치지 않는다 · 2단계 인증이 뜨면 사람 몫 · 로그인 클릭 반복 금지(계정 잠금 · 08-29) · 실행 중 스크립트 교체 금지.

### 5.3 도훈 결정

| # | 결정 | Q 권고 |
|---|---|---|
| D1 | 배당 포함 총수익: 등급 수익률(측정 축 epoch)에 넣을지, 충실구현 전용 패널로만 둘지 — 넣으면 벤치도 TR(2011~ 뿐) | 전용 패널부터(퀀티 항목 확인 뒤) |
| D2 | 2015~ 재무 원천: 퀀티 Peer Analysis 연장(단일 원천 · 설비투자 포함) vs DART 유지(계정 매핑 확장 · 감가상각 커버리지 약 30%) | — (원천 정책) |
| D3 | 파생 원천: 퀀티 vs KRX Open API `/drv/` | 이력 길이 확인 뒤 |
| D4 | 병렬화 확장: 1b · 1c(출력 변화) · Done 조기화(2a/2b/2c) | 지금은 1단계만 · 2c 검토 |
| D5 | (선택) 벤더(WISEfn)에 공식 사전 내보내기 · 단말 밖 접근 방법 문의 | 필요할 때 |

### 5.4 결정 없이 Q 가 진행(보고만)

- 사전 수급(요청에 다운로드 지시가 있다) · 1차 묶음 A → B → C 순차 적재 · 퀀티 꼬리 레인 — 밤 시간이 문제면 그때 조정.
- 선행 수리 F1~F7 · 구멍 복구 · DATA_Key 단일화(OHLCVS 정본)와 신규 상장 동기화.
- 병렬화 1단계 · 정체 감시 수리 · 퀀티 뮤텍스(대기 정책).
- 종목 패널 가용 규칙은 `fred_availability_rules.json` 확장(정본 하나).
- 라우터 보유 목록 갱신과 데이터 대기열 상태 전이(append-only).

---

## 부록 A 근거 위치

- 사전: `C:/WISEfn/Common/Bin/Addin/QW7menu.xml` · `C:/WISEfn/Common/Bin/qwTool.dll` · `qwCom.dll` · `qwEconomy.dll` · `C:/WISEfn/Common/Data/maincfg.ini` · `C:/WISEfn/Common/Update/Ver/*.ver` · `qwMain.log`(조사 · 사본 판독)
- 수급 경로: `02_Infrastructure/ops/qw_refresh.ps1` ✔ · `02_Infrastructure/data/qw_updatefile_unattended.sh` ✔ · `02_Infrastructure/data/incremental_update_file.R` ✔ · `02_Infrastructure/data/qw_excel_refresh.ps1` · `quantiwise_fetch.py` · `global_macro_ingest.py` ✔ · `us_update_stream_parse.py` ✔
- 체인: `02_Infrastructure/data/daily_refresh.sh`(1,007줄 · md5 927c40cf ✔) · 원래 세션 스크래치판 `C:/Users/99922/AppData/Local/Temp/claude/9690c5033ea8579c/f9656758-3276-4837-b867-6b6a5febe96d/scratchpad/msm_switch/daily_refresh.sh`(1,023줄 ✔)
- 등록부: `06_Registry/fred_availability_rules.json`(version 2026-11-06.b6 · 계열 43 ✔) · `02_Infrastructure/data/cache_registry.json` ✔ · `02_Infrastructure/ops/morning_steps/freshness_audit.R` ✔ · `02_Infrastructure/data/fred_availability.R` ✔
- 위생: `02_Infrastructure/factor_db/factor_z_standard.R:84-89` ✔ · `02_Infrastructure/contracts/measurement_axis.R:152-155` ✔
- 데이터 실측(✔ 11-06 10:0x): `.cache/investor_stock/investor_all.parquet`(10-20~10-30 유형별 행 수) · `.cache/consensus/*.parquet` max · `.cache/universe_support/us_*.parquet` max · `.cache/RAWDATA.parquet`(2026-11-05 · 2,523종 · 위생 NA 53) · `.cache/qw_refresh_state.json` · `.cache/scheduler_logs/qw_refresh_3files_relogin_20261106.log`
- 결손 수요: `06_Registry/data_pipeline_queue.json` · `06_Registry/research_programs.json` · `04_Research/strategies/RP_AUTO_*/FIDELITY.json` · `04_Research/01_reports/kr_market_stress_index_20261106/DESIGN_v1_capital_market.md:136-147` · `02_Infrastructure/factor_db/compute_{crowding,consensus,defense,growth}.R` · `02_Infrastructure/ops/paper_router_prompt.md:35-44`
- 시간 실측: `.cache/scheduler_logs/ensure_data_current_qvest_boot_20261106.log` · `/tmp/qm_daily_refresh_2026101{6,7,8}.log` · `20261020.log` · `20261101.log` · `.cache/scheduler_logs/daily_refresh.log`
