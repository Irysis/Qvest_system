# 팩터 방향 격리 재판정 — 자체 사양 엔진 4가족(밸류 · 성장 · 컨센서스 · 쏠림) · 2026-11-13

성과를 보지 않고, 팩터 정의 · 빌더 코드 · 문헌만으로 **기대수익 방향**을 다시 정한 뒤 등록부 `direction` 과 맞춰 보았습니다.
구성원 = `04_Research/strategies/FC_FAM_{value,growth,consensus,crowding}/own_spec.json` 의 `core.members` 73개(24 · 21 · 14 · 14).
방향은 모두 **저장 Raw_Value 기준**(소비자가 저장값에 곱하는 값 · `s_reg` = +1 ↔ higher_better)입니다. 구성원별 전체 표 = `directions.json`.

## 0. 우연히 본 것

- **우연 열람 1**: 읽어도 되는 문서로 받은 `02_Infrastructure/factor_db/DIRECTION_POLICY.md` §6 항목 7에 **다른 전략(P2R03 · P2R04 계열)의 재채점 등급과 팩터 알파 t 값**이 적혀 있었습니다. 이 팩터들의 방향과는 관계가 없고, 판정에 쓰지 않았습니다.
- **우연 열람 2**: 세션에 기본으로 들어오는 문맥(CLAUDE.md · pit.md · 메모리 색인)에도 다른 라운드의 성과 수치가 들어 있습니다. 판정에 쓰지 않았습니다.
- 커밋 메시지 두 개(6ec99a015 · 357cedcc4)에 나온 수치는 정렬값과 저장값의 순위상관 같은 **정의 점검 값**이고, 성과는 아닙니다.
- **열지 않은 것**: `direction_economic_evidence` 의 내용(있는지만 셈) · `labels.evidence_tier` · `lifecycle.research_stage` · `dedup.*` · `retired_dedup` · `direction_history` 의 reason · evidence 필드 · `direction_economic` · `factor_evidence.json` · IC 원장 · `conditional_ic_matrix.csv` · 결합용 뷰 부호표 · 감사 표 `06_Registry/factor_direction_audit.json` · 어떤 `results/`도 · `authoritative_remeasure.json` · `hypothesis_index` · 엔진 폴더의 `fce_diag.csv` · 텔레그램 · 레인 로그.

## 1. 요약

| 가족 | 구성원 | 일치 | 불일치 | 불명 |
|---|---:|---:|---:|---:|
| 밸류 (value) | 24 | 22 | 1 | 1 |
| 성장 (growth) | 21 | 19 | 0 | 2 |
| 컨센서스 (consensus) | 14 | 12 | 1 | 1 |
| 쏠림 (crowding) | 14 | 8 | 1 | 5 |
| **합계** | **73** | **61** | **3** | **9** |

- **불일치 3건**: `V23_RAFI_Weight` · `C08_Coverage` · `CR05_Short_Pressure_Proxy`. 세 건 모두 등록부는 higher_better, 문헌은 lower_better 쪽입니다.
- **불명 9건**: `V17_Payout_Ratio` · `GR01_Revenue_Growth` · `Q21_Revenue_Growth` · `C06_TP_Gap` · `CR07_Momentum_Crowding` · `CR08_Volume_Price_Divergence` · `CR10_Convergence_Premium` · `TR01_ADX_Proxy` · `TR02_Trend_Consistency`. 이 아홉 개의 등록부 방향은 모두 higher_better입니다.
- **출처 감사**: git으로 추적되는 범위에서는 등록부 `direction` 을 IC로 정한 흔적이 **없습니다**. 70개는 처음 추적된 판(2026-04-17)부터 값이 그대로이고, 3개는 2026-11-09 문헌 검토 때 바뀌었습니다(커밋 메시지에 'IC 미사용'). 다만 **최초 등재일인 2026-03-24 자체는 git 기록보다 앞서 있어서 그 단계는 판단할 수 없습니다.** 같은 시기의 소비자 코드(2026-04-17 판 `align_factor_direction`)는 **전기간 평균 IC 부호로 방향을 즉석에서 정했습니다.** 이 코드는 2026-04-22에 as-of로 수리됐습니다(L-168). 이것은 소비자 쪽 흔적이고, 등록부 필드에 쓴 흔적은 아닙니다(§6).

일치가 곧 IC로 고르지 않았다는 증명은 아닙니다. 다만 일치한 61개는 문헌의 사전 방향과 같으므로, 설령 IC로 골랐더라도 방향을 고른 과정에서 생긴 오염(C1)이 부호를 바꾸지는 않았습니다. 확인이 필요한 쪽은 불일치 3건과 불명 9건, 합쳐 12개입니다.

## 2. 방법

1. **구성원**: `own_spec.json` 에서 `core.members` 의 (id · s_reg · family)만 읽었습니다. 73개 모두 `s_reg` 와 등록부 `direction` 이 맞물립니다(스크립트에서 assert로 확인).
2. **정의**: 등록부에서는 `name` · `category` · `definition` · `data_source` · `update_freq` · `lag_rule` · `direction` · `direction_economic_basis`(열거값) · `stored_sign` · `direction_basis` 만 파이썬 `json` 으로 뽑았습니다. 73개 모두 `stored_sign = 1` · `direction_basis = stored_raw_value` 이고, 정의 문구 안의 'Negate' 가 저장값의 부호를 그대로 설명합니다.
3. **빌더 코드 대조**: `compute_value.R` · `compute_growth.R` · `compute_consensus.R` · `compute_crowding.R` · `compute_quality.R`(Q21 · Q22 · Q34) · `compute_quality_xf_native.R`(XF_GD) · `consensus_parser.R` 를 읽었습니다. '저장값이 클수록 무엇인가'를 코드로 다시 끌어냈습니다(음수화 위치 · 분모 · 차분 방향 · 창 길이). 성과를 계산하는 부분은 읽지 않았습니다.
4. **입력 성질 확인(성과 아님)**: 정의가 의심스러운 컨센서스 입력 `esbr` · `escr` 는 `.cache/consensus/*.parquet` 원값의 분포만 보았습니다. 본 것은 음수 비율 · 분위수 · 고유값 수이고, 수익과 결합하지 않았습니다. 같은 방식으로 재무 원천의 기록 빈도(`Freq` 표지)를 확인했습니다.
5. **문헌**: 구성원 정의에 맞는 원 논문을 찾았습니다. 인용한 DOI는 모두 Crossref API로 제목과 저자를 확인했습니다(틀리거나 찾지 못한 후보 DOI 8개는 바로잡거나 뺐습니다). SSRN 판 링크는 그렇다고 표시했습니다.
6. **판정 규칙**: 문헌의 부호가 분명하면 higher_better 또는 lower_better로 정했습니다. 기간 · 정의에 따라 문헌이 갈리거나, 저장값에 방향 정보가 없거나(부호를 지운 양), 그 양을 다룬 문헌이 없으면 '불명'으로 두었습니다. 신뢰도는 high · medium · low입니다.

## 3. 불일치 3건 — 근거

### V23_RAFI_Weight (밸류) — 등록부 higher_better → 제안 lower_better · 신뢰 낮음
- **저장값**: 유니버스 합계 대비 매출 · 영업CF · 자기자본 · 배당의 몫을 평균한 값입니다(`compute_value.R` V23). 가격으로 나누지 않으므로 **가치 비율이 아니라 '기본가치로 잰 규모'** 이고, 클수록 큰 회사입니다.
- **문헌**: 규모 프리미엄은 작을수록 수익이 높다는 것입니다(Banz 1981). 품질을 통제하면 시가가 아닌 규모 척도(자산 · 고용 등)에서도 이 프리미엄이 나타납니다(Asness · Frazzini · Israel · Moskowitz · Pedersen 2018). 반대로 Berk(1995)는 시장가가 아닌 규모 척도는 기대수익과 무관해야 한다고 주장합니다. **두 견해 모두 '클수록 좋다'를 지지하지 않습니다.**
- RAFI(Arnott · Hsu · Moore 2005)의 초과수익은 '기본가치 비중 ÷ 시가 비중', 곧 가치 기울기에서 나옵니다. 원 비중의 크기에서 나오는 것이 아닙니다. 가치 가족에 넣으려면 비중을 시가 비중으로 나눈 양이어야 정의와 이름이 맞습니다.
- 신뢰도가 낮은 이유: 비시장 규모 척도의 프리미엄은 품질 통제를 전제로 합니다. 무조건부로는 약합니다(Berk). 따라서 'lower_better 가 확정'이라기보다 **'higher_better 의 근거가 없다'** 는 판정입니다.

### C08_Coverage (컨센서스) — 등록부 higher_better → 제안 lower_better · 신뢰 중간
- **저장값**: 커버리지 애널리스트 수입니다(벤더 '커버리지' 원값 · 관측 범위 1~24명대).
- **문헌**: 증권사 폐쇄 · 합병으로 커버리지가 외생적으로 줄면 가격이 떨어지고 기대수익이 오릅니다(Kelly & Ljungqvist 2012 — 정보 비대칭 프리미엄의 인과 증거). 소외 기업일수록 초과수익이 있다는 소외 기업 효과도 같은 쪽입니다(Arbel · Carvell · Strebel 1983). Hong · Lim · Stein(2000)은 저커버리지에서 모멘텀이 강하다는 **조건부** 결과이고, 커버리지 수준이 높을수록 수익이 높다는 결과가 아닙니다.
- 등록부 정의는 'Attention signal'입니다. 그러나 주목도가 높을수록 수익이 높다는 문헌은 찾지 못했습니다. 커버리지 '개시'의 양의 반응은 변화량에 관한 결과이고, 이 팩터는 수준입니다.
- 신뢰도가 중간인 이유: 커버리지는 규모와 강하게 겹칩니다. 한국 시장만 다룬 문헌은 확인하지 못했습니다.

### CR05_Short_Pressure_Proxy (쏠림) — 등록부 higher_better → 제안 lower_better · 신뢰 낮음
- **저장값**: −(하락일 Amihud ÷ 상승일 Amihud)를 1년 창으로 잰 값입니다. Amihud = |수익| ÷ 거래량(주식 수)이고, 공매도 자료는 쓰지 않습니다. 저장값이 **작을수록**(더 음수일수록) 하락일의 가격충격이 상대적으로 큽니다.
- **문헌**: Amihud 비유동성 프리미엄은 **하락일 성분에서만** 나타납니다(Brennan · Huh · Subrahmanyam 2013 — 상승일 · 하락일 분해). 가격에 반영되는 것은 주로 매도 쪽 유동성입니다(Brennan · Chordia · Subrahmanyam · Tong 2012). 따라서 하락일 비유동성 비중이 클수록 기대수익이 높고, 음수화된 저장값은 **작을수록 좋다(lower_better)** 가 됩니다.
- 등록부의 근거는 정의 문구 'Higher on down days = short pressure' → 나쁨이라는 서사뿐입니다. 이 양에 대해 그 서사를 받치는 문헌은 찾지 못했습니다.
- 신뢰도가 낮은 이유: 문헌은 하락일 비유동성의 **수준**을 다룹니다. 이 팩터는 하락일 대 상승일의 **비율**이고, 분모도 거래대금이 아니라 주식 수입니다.

## 4. 불명 9건 — 이유

| id | 저장값 | 불명인 이유 |
|---|---|---|
| V17_Payout_Ratio | 배당 ÷ 순이익 | 배당성향 자체로 횡단면 수익을 예측한 문헌을 찾지 못했습니다. 높은 배당성향 → 높은 이익성장(Arnott & Asness 2003 · Zhou & Ruland 2006)은 이익을 예측한 결과입니다. 지급**수익률**(Boudoukh 외 2007)은 가격으로 나눈 다른 양입니다. |
| GR01_Revenue_Growth · Q21_Revenue_Growth | 최근 두 재무 기록 간 매출 변화율 | 기간에 따라 부호가 갈립니다. 다년 매출성장은 음입니다(LSV 1994 — 복제 연구에서 유의성 약화, Hou 외 2020). 분기 매출 서프라이즈는 양입니다(Jegadeesh & Livnat 2006). 저장값은 연간 YoY(DART 구간)와 연속 분기 QoQ(XLSX 구간)가 섞여 있어 어느 정의에도 정확히 맞지 않습니다. |
| C06_TP_Gap | (목표가 − 종가) ÷ 종가 | 업종 안 상대 순위로는 양이지만 업종 간에는 관계가 없습니다(Da & Schaumburg 2011). 내재수익률의 예측력은 약합니다(Dechow & You 2020). 목표가 분산이 크면 오히려 음입니다(Palley · Steffen · Zhang 2025). |
| CR07_Momentum_Crowding | −corr(종목, 12-1 승자 상위 20% 포트) | comomentum(Lou & Polk 2022)은 시장 전체의 시계열 신호입니다. 종목 단위로 승자 포트와의 상관을 쓴 횡단면 문헌은 없습니다. 승자 노출에는 모멘텀 프리미엄과 붕괴 위험(Daniel & Moskowitz 2016)이 함께 붙어 있습니다. |
| CR08_Volume_Price_Divergence | −\|21일 평균수익\| × \|log 거래량 변화\| | abs가 괴리의 부호를 지웁니다. 남는 양은 '움직임의 크기'뿐이고, 이 양을 다룬 문헌은 없습니다. |
| CR10_Convergence_Premium | −AR(1)(일간 수익) | 음의 자기상관은 호가 반등 · 비유동성의 흔적입니다(Roll 1984 · Avramov 외 2006). 자기상관 자체로 기대수익을 정렬한 문헌은 찾지 못했습니다. |
| TR01_ADX_Proxy | 평활하지 않은 DX(방향 없는 추세 강도) | 상승 추세와 하락 추세를 구분하지 않는 양입니다. 부호 있는 추세 신호의 문헌(Han · Zhou · Zhu 2016)은 여기에 적용되지 않습니다. |
| TR02_Trend_Consistency | \|상승일 비율 − 0.5\| × 2 | 방향 없는 일관성입니다. Frog-in-the-pan 효과(Da · Gurun · Warachka 2014)는 과거 수익 부호와 결합한 부호 있는 양에서 나옵니다. |

## 5. 함께 드러난 정의 · 코드 · 저장값 어긋남 (방향 판정과 별개 · 수리 후보)

- **C04_ESBR · C05_ESCR**: 등록부 정의는 각각 '상향 애널리스트 비율'(0~1이어야 함)과 '개정 방향 일관성'(부호 없음)입니다. 그런데 저장 원값은 부호가 있고, 음수 비율이 약 0.58로 SUE(0.580)와 같은 수준입니다. ESCR은 관측 수까지 SUE와 거의 같고, ESBR은 분기에 한 번 바뀝니다(`compute_consensus.R` 주석). 벤더 항목 'ESBR(지배)' · 'ESCR(지배)'는 **지배주주순이익 기준의 서프라이즈 비율류**로 보입니다. 벤더 정의서는 웹에서 확인하지 못했습니다. 부호 있는 서프라이즈라면 두 팩터 모두 higher_better이고 등록부와 일치합니다. **등록부 정의 문구는 고쳐야 합니다.**
- **Q34_GP_Growth**: 정의는 '5년 GP/TA 성장'인데, 코드는 최근 두 기록 간 매출총이익 변화율입니다(`.compute_yoy_growth`).
- **GR04 · GR05 '5Y'**: 코드는 최근 5개 기록의 처음과 끝을 비교합니다. 그래서 분기 구간에서는 약 1년, 연간 구간에서는 약 4년이 됩니다.
- **GR01 · GR02 · GR06 · Q21 · Q22 'YoY'**: 코드는 Factor_Date 순으로 최근 두 기록을 씁니다. 살펴본 재무 캐시에서는 2014년 이전이 분기(XLSX), 2015년 이후가 연간(DART)이어서 분기 구간은 계절성이 섞인 QoQ가 됩니다. 재무 v2 판에서는 빈도가 다를 수 있습니다.
- **V11_Shareholder_Yield**: 정의는 '배당 + 자사주'인데 코드는 배당만 씁니다. 즉 후행 배당수익률입니다.
- **V23_RAFI_Weight**: 가치 가족에 속하지만 실제 양은 규모입니다(§3).
- **CR06_DTC_Proxy**: 공매도잔고가 없습니다. 주식 수 ÷ 20일 거래량 = 회전율의 역수입니다. 진짜 DTC(Hong 외 2015 — 높을수록 수익 낮음)와 이름만 같습니다. 회전율 문헌 기준으로 등록부 lower_better와 일치합니다.
- **CR04_Ownership_Concentration**: 이름은 '소유 집중'이지만 양은 20일 회전율입니다.
- **CR05**: 이름은 공매도 압력이지만, 실제 양은 비대칭 비유동성 비율(주식 수 거래량 기준)입니다.
- **SE01_Volatility_Uncertainty**: 컨센서스 분산 분기는 분산 열이 없어 실행되지 않습니다. 저장값은 늘 −21일 변동성입니다.
- **SE02_Consensus_Revision**: `eps_1y` 와 `target_price` 중 어느 열을 쓸지가 병합된 표의 열 순서에 달려 있습니다. 비교 구간도 최근 두 관측(일간) 사이여서 1일 변화입니다.
- **C12_Estimate_Dispersion_Proxy**: 애널리스트 간 분산이 아닙니다. (1개월 변화 − 3개월 변화)를 EPS **수준**으로 나눈 값이라 단위가 섞여 있습니다.
- **TR01_ADX_Proxy**: 평활한 ADX가 아니라 단기간 DX입니다.
- **CR08**: 정의 문구에 없는 |거래량 변화| 크기가 곱해집니다.
- **IN01 · IN02**: capex가 아니라 투자활동현금흐름 전체(금융자산 · 인수 포함)입니다. 부호(음수 = 투자)는 맞습니다.
- **MK01_CAPM_Beta**: 등록부 category가 growth입니다. 가족 배정이 어색할 뿐 방향과는 관계없습니다.

## 6. 출처 감사 (성과 수치 없음)

### 6.1 기록
- 저장소의 첫 커밋은 2026-04-10입니다(CLAUDE.md만 있음). `factor_registry.json` 이 처음 추적된 것은 **2026-04-17 `0ce36d19d`** 이고, 이후 이 파일을 건드린 커밋은 18개입니다.
- 등록부 `lifecycle.added_date` 는 **2026-03-24가 70개**, **2026-05-23이 3개**(Q21 · Q22 · Q34 — git에는 2026-06-05 `3f0d6c186` 에서 처음 나타남)입니다. 즉 **최초 등재는 git 기록보다 앞섭니다.**
- 18개 판을 모두 꺼내 73개 구성원의 `direction` 만 대조했습니다.
  - **70개는 처음 나타난 판부터 지금까지 값이 한 번도 바뀌지 않았습니다.**
  - 바뀐 것은 `CR02` · `CR04` · `CR06` 3개뿐이고, 모두 higher_better → lower_better입니다. 날짜는 2026-11-09, 커밋은 `357cedcc4`, 결정은 FACTOR-DIRECTION-TWO-VIEWS-20261109이며, 커밋 메시지에 '판단에 성과 · IC 미사용 · 문헌'이 적혀 있습니다. 세 건 모두 이번 격리 재판정과도 일치합니다.
  - 같은 날 `6ec99a015`(저장값 기준으로 71개 방향 수정 · 코드 감사 · 'IC 미사용')는 이 73개를 건드리지 않았습니다.
- 첫 추적 판의 엔트리 키는 `category` · `data_source` · `definition` · `direction` · `labels` · `lag_rule` · `lifecycle` · `name` · `update_freq` 뿐입니다(키 이름만 확인). IC 관련 필드는 없었습니다.

### 6.2 'IC로 방향을 정했다'는 흔적 찾기
- **등록부 `direction` 을 쓰는 코드**: `add_factor.R`(인자로 직접 받음) · `compute_custom.R`(positive · negative를 수동 지정) · `rf_factor_autoregister.R`(엔진 점수에 higher_better 고정) · `apply_direction_basis.py`(11-09 감사 표 · 문헌)가 있습니다. **IC 부호를 등록부에 쓰는 코드는 첫 추적 판과 현행 어디에서도 찾지 못했습니다.** 첫 추적 판에서는 `02_Infrastructure`(factor_db 포함)의 R 파일을 대상으로 `direction` 대입문을 `git grep` 했습니다. 현행에서는 `02_Infrastructure` · `99_Archive` · `08_Tests` 의 R · py 파일을 대상으로 'IC 부호 → higher/lower_better' 패턴을 찾았는데, 걸린 것은 소비자 쪽 as-of 정렬뿐이었습니다.
- **빌더 주석**: 음수화마다 경제적 이유가 붙어 있습니다. 예를 들어 `compute_growth.R` 의 "Negate: low asset growth = better", `compute_crowding.R` 의 "high comove = crowded = bad" · "lower DTC = more liquid = better" · "Higher turnover = less concentrated = better"입니다. 이 주석들은 원래 등록부 방향(CR02 · CR04 · CR06의 옛 higher_better 포함)과 같은 쪽을 가리킵니다. 등재자가 사전 서사로 정한 값으로 보는 것이 자연스럽습니다. 정의 문구에도 Cooper–Gulen–Schill · Titman–Wei–Xie · Bhandari · Barbee 외 같은 문헌 이름이 들어 있습니다.
- **커밋 메시지**: 'direction'+'IC' · '방향'+'IC' · 'IC 부호' · 'ic_sign' 으로 찾았습니다. 걸린 커밋은 모두 11-09 이후의 수리 · 소비자 정렬 · 엔진 방향 선택에 관한 것입니다. 등록부 방향을 IC로 정했다는 메시지는 없습니다.
- **소비자 쪽 IC 흔적(중요)**: 첫 추적 판(2026-04-17) `factor_db_connector.R::align_factor_direction()` 은 "Uses IC sign to AUTOMATICALLY determine direction (no manual registry needed)"라는 설명 그대로 `factor_ic_monthly.parquet` **전 구간의 평균 IC 부호**로 방향을 정했습니다. 등록부는 IC가 없을 때만 쓰는 대체값이었습니다. 이는 전기간 통계로 방향을 고른 C1형 결함이고, **2026-04-22 `46423f6a5`(v2.0 · L-168)에서 `Usable_Date <= sig_date` as-of로 바뀌었습니다.** 이 코드는 등록부에 쓰지 않았습니다. 앞의 값 불변 기록을 보면 등록부로 되먹임된 흔적도 없습니다.

### 6.3 `direction_economic_basis` 열거값 분포
- **등록부 전체 371개**: `registry_original` 195 · `literature_mixed_defensive_tiebreak` 87 · `literature` 82 · `code_and_definition` 7. `direction_economic_evidence` 가 있는 엔트리는 169개로, literature 82 + tiebreak 87과 같습니다.
- **이번 구성원 73개**: `registry_original` 70 · `literature` 3(CR02 · CR04 · CR06). evidence가 있는 엔트리는 3개입니다.
- **카테고리별(등록부 전체)**

| category | 분포 |
|---|---|
| value | registry_original 24 |
| growth | registry_original 21 |
| consensus | registry_original 19 |
| crowding | registry_original 13 · literature 3 |
| quality | registry_original 42 · literature 2 · code_and_definition 3 |
| momentum | registry_original 28 · literature 4 |
| accrual | registry_original 19 · literature 2 · code_and_definition 4 |
| investor_flow | registry_original 15 |
| technical | registry_original 12 |
| custom | registry_original 2 |
| defense | literature 33 · tiebreak 26 |
| liquidity | literature 28 · tiebreak 16 |
| regime | literature 1 · tiebreak 27 |
| risk | literature 7 · tiebreak 12 |
| leverage | tiebreak 6 |
| size | literature 2 |

### 6.4 결론
**IC로 정한 흔적: 없음(git 추적 범위).** 근거는 값이 불변이라는 기록, IC 필드가 없다는 점, IC→등록부 writer가 없다는 점, 빌더 주석의 경제적 서사입니다. 다만 2026-03-24 최초 등재 과정은 git 이전이어서 **그 단계는 판단할 수 없습니다.** 같은 시기 소비자가 전기간 IC 부호를 즉석에서 썼다는 사실은 사실 기록으로 남깁니다. 그 경로를 거친 4월 이전 산출물은 별개의 C1 문제입니다.

## 7. 한계

- **열람 범위**: 문헌은 초록 · 2차 요약 · 기억에 기댄 부분이 있습니다. 특히 Chang & Luo 2010(CR01 · CR11), Bennett & Sias 2001(CR09), Brennan · Huh · Subrahmanyam 2013(CR05)은 원문 표를 직접 보지 않았습니다. CR01 · CR11 · CR09의 '일치'는 신뢰도가 낮습니다.
- **한국 문헌**: 한국 시장만 다룬 문헌은 시간 안에 확인하지 못했습니다. 국제 · 신흥시장 표본 문헌(Rouwenhorst 1999 · Watanabe 외 2013 · Titman 외 2013 · McLean 외 2009 · Kaniel 외 2012 · Blitz 외 2013)만 함께 적었고, 한국이 표본에 들어 있는지는 원문 표본표로 다시 확인해야 합니다.
- **벤더 정의**: ESBR · ESCR의 벤더 정의서를 확보하지 못했습니다. 판정은 저장값 성질에서 추론한 것입니다.
- **재무 빈도**: 재무 기록의 빈도는 지금 캐시(`fundamental_merged.parquet`) 몇 종목으로만 확인했습니다. 재무 v2 판의 빈도는 확인하지 않았습니다.
- **판정 단위**: 판정은 팩터 하나씩 단독으로 했습니다. 가족 합성 안에서 서로 겹치는 정도(예: GR01 ≈ Q21, GR02 ≈ Q22, CR04 ≈ CR06 같은 양)는 따지지 않았습니다.
- **불명의 처리**: '불명'을 어떻게 다룰지는 정책 결정입니다. DIRECTION_POLICY의 동률 규칙(기대수익 = 방어 방향)은 방어 방향이 있는 범위 계열에만 적용되는데, 이번 4가족에는 대부분 방어 방향이 없습니다.
- **수정 범위**: 등록부 · 감사 표는 고치지 않았습니다. 바꾸려면 DIRECTION_POLICY §5 경로(감사 표 → `apply_direction_basis.py`)를 따라야 합니다.

## 8. 파일

- `README.md` — 이 문서
- `directions.json` — 구성원 73개 `{id, category, registry_direction, proposed_direction, agree, basis, refs[{ref, url}], confidence}` + 참고 필드(`registry_category` · `s_reg` · `registry_basis` · `verdict` · `stored_meaning` · `def_code_note`) + 가족별 집계
