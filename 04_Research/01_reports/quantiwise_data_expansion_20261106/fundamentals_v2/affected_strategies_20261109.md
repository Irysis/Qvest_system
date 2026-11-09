# 재무 v2 전환 — 영향받는 전략 목록 (2026-11-09)

결정 `FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109` ④에 붙이는 목록입니다. 측정 축 `all_hyg_px1000_2000_v1`, 생성 2026-11-09T12:08:03+09:00, 읽기 전용 분석입니다(측정은 하지 않았습니다).
상세(근거 파일:행 · 팩터 · 변형)는 같은 폴더 `affected_strategies_20261109.json` 에 있습니다.

## 범위
- `stage_artifacts/replication/**/authoritative_remeasure.json` 중 이 축의 파일 99개에서 `_superseded` 4개를 뺀 **95개 · 전략 87개**를 봤습니다. 전략 단위는 strategy_name입니다(변형과 프로그램 셀을 각각 셉니다).
- 결정 메모의 '136개 · 84개'는 07:34 기준 수치입니다. 복제 산출 92개에 프로그램 라운드 사본 44개(`04_Research/programs/P2_DEFENSE/*/results/*/original/rx0_beta_scaled/`)를 더한 값이고, 전략은 84개입니다. 그 뒤에 Piotroski v2 3개 파일이 늘었습니다. 사본 44개는 RX0 측정 4개를 복사한 것이라 RX0 항목에 붙였습니다.

## 분류별 수

| 분류 | 전략 | 파일 | B 이상 |
|---|---:|---:|---:|
| 재무 표 직접 (`direct_table`) | 53 | 53 | 41 |
| 팩터 DB 재무 팩터 (`factor_db_fundamental`) | 19 | 19 | 7 |
| 가격만 (`price_only`) | 12 | 20 | 0 |
| 판단 불가 (`unknown`) | 0 | 0 | 0 |
| 해당 없음(v2 직접) (`v2_direct`) | 3 | 3 | 0 |
| 합계 | 87 | 95 | 48 |

- **v1 재무를 쓴 전략은 72개이고, B 이상은 48개입니다.** B 이상 48개가 모두 여기에 들어갑니다. A는 0개입니다. B 미만은 24개입니다(C 15 · F 9).
- 재무 표를 직접 읽는 전략 가운데 27개는 팩터 DB 재무 팩터도 함께 씁니다.
- 가격만 쓰는 전략은 12개입니다(2106.06164 5개 · 2604.16773 7개). 최고 등급은 F 12입니다.
- 판단 불가는 0개입니다. factor_engine_path 6종(셀 엔진의 기저 엔진까지 7개 파일)을 모두 찾아 읽었습니다.

## 재무 팩터 기준
- 레지스트리 필드로 판정했습니다. ① `data_source` ∈ {fundamental, fundamental_xlsx}에 해당하는 팩터가 124개입니다. ② `category` ∈ {value, quality, growth, leverage}이거나 이름에 EV가 들어가는 팩터를 더하면 합집합은 130개입니다.
- ②로만 걸리는 6개(`MK01_CAPM_Beta` · `V04_fPER` · `V05_fPBR` · `V06_fDY` · `V09_PEG` · `V21_Composite_Equity_Issuance`)는 재무 표를 읽지 않습니다. 그래서 `category_only`로 따로 표기했습니다. 이 기준 때문에 분류가 바뀐 전략은 없습니다.
- 등급 계산 쪽(essence · grade_v3 · MC8 짝 · 행동 카드)은 재무를 읽지 않습니다. 따라서 영향 여부는 엔진 입력만으로 정했습니다.

## B 이상 · v1 재무 사용 (48)

| 묶음 | 전략(최고 등급 B) | 경로 | 재무 입력 |
|---|---|---|---|
| P2R03 셀(기저 = 2002.06975 DNN) | P2R03_E2_D1, P2R03_E2_D2, P2R03_E2_D4, P2R03_E2_L1, P2R03_E2_L2, P2R03_E2_L4, P2R03_E2_L7, P2R03_E2_RX0 | direct_table | fundamental_merged.parquet 14항목(기저 2002.06975) |
| P2R03 셀(기저 = 2002.06975 DNN) | P2R03_E3_D1, P2R03_E3_D2, P2R03_E3_D3, P2R03_E3_D4, P2R03_E3_D5, P2R03_E3_D6, P2R03_E3_D7, P2R03_E3_L1, P2R03_E3_L2, P2R03_E3_L3, P2R03_E3_L4, P2R03_E3_L5, P2R03_E3_L6, P2R03_E3_L7, P2R03_E3_RX0 | direct_table + factor_db_fundamental | fundamental_merged.parquet 14항목(기저 2002.06975) / V10_FCF_Yield |
| P2R04 셀(기저 = 2002.06975 DNN) | P2R04_E2_C1, P2R04_E2_C2, P2R04_E2_C3, P2R04_E2_N0, P2R04_E2_RX0, P2R04_E2_W1, P2R04_E2_W2, P2R04_E2_W3 | direct_table | fundamental_merged.parquet 14항목(기저 2002.06975) |
| P2R04 셀(기저 = 2002.06975 DNN) | P2R04_E2_C4, P2R04_E2_H4, P2R04_E2_W4 | direct_table + factor_db_fundamental | fundamental_merged.parquet 14항목(기저 2002.06975) / Q08_Composite_Quality |
| P2R04 셀(기저 = 2002.06975 DNN) | P2R04_E3_H2, P2R04_E3_RX0, P2R04_E3_W1, P2R04_E3_W2, P2R04_E3_W3 | direct_table + factor_db_fundamental | fundamental_merged.parquet 14항목(기저 2002.06975) / V10_FCF_Yield |
| P2R04 셀(기저 = 2002.06975 DNN) | P2R04_E3_H4, P2R04_E3_W4 | direct_table + factor_db_fundamental | fundamental_merged.parquet 14항목(기저 2002.06975) / V10_FCF_Yield · Q08_Composite_Quality |
| 1603.00751 Milosevic(2016) ML 8종 | RP_AUTO_160300751, RP_AUTO_160300751_v_bayes_net_sel11, RP_AUTO_160300751_v_smo_sel11 | factor_db_fundamental | V01_BM · V11_Shareholder_Yield · V04_fPER* · V02_EP · V05_fPBR* · V06_fDY* · Q14_Current_Ratio · XF_LL04_QuickRatio · Q15_Debt_to_Equity |
| 1603.00751 Milosevic(2016) ML 8종 | RP_AUTO_160300751_v_bayes_net_all, RP_AUTO_160300751_v_random_forest_all | factor_db_fundamental | V01_BM · V11_Shareholder_Yield · V04_fPER* · GR02_Earnings_Growth · GR01_Revenue_Growth · V02_EP · V05_fPBR* · V08_PSR · V06_fDY* · Q14_Current_Ratio · XF_LL04_QuickRatio · Q15_Debt_to_Equity · Q11_Net_Margin · XF_Q06_Op_Margin · Q12_Asset_Turnover |
| 2412.12350 Gkolemis-Lee-Roudani(2024) Lasso 다요인 | RP_AUTO_241212350, RP_AUTO_241212350_v_equal_weight | factor_db_fundamental | V20_SP · V01_BM · Q03_ROA · Q05_Accrual · Q12_Asset_Turnover · Q26_RnD_Intensity |

\* = `category_only`입니다(consensus 지표로, 재무 표를 읽지 않습니다). 같은 칸의 다른 팩터는 `data_source = fundamental` 계열입니다.

## 판단 불가 목록
- 없음(0개).

## 해당 없음 · 제외
- `RP_SESSION_piotroski2000_v2` 3개(대표 hl C · ha F · rank F)는 `.cache/fundamental_v2/fund_v2_quarterly.parquet`(v2)를 직접 읽었으므로 해당 없음(v2 직접)입니다.
- `_superseded` 4개(`20261109_102936_33072_superseded_pitcut`과 그 변형)는 범위에서 뺐습니다.

## 다시 잴 때 참고할 점
- 셀 53개(P2R03 · P2R04)는 모두 기저 엔진 `RP_AUTO_2002_06975/engine.R`가 v1 `fundamental_merged.parquet`(DART · XLSX 14항목)를 직접 읽습니다. 그래서 셀 사양에 붙은 팩터가 가격 팩터(D03 · D04 · D07)이거나 아예 없는 칸(RX0 · N0)도 재무를 쓴 측정입니다.
- 기저 신호 캐시 키에는 재무 표 도장이 들어 있습니다(`rf_base_cache.R:44`). 그래서 재측정할 때 v1 기저 캐시를 다시 쓰지 않습니다. v2 정본도 Source 표지를 유지합니다(실측 DART · XLSX · xlsx_derived). 그래서 기저 엔진의 `Source %in% c("DART","XLSX")` 필터가 v2에서도 행을 고릅니다.
- 2106.06164 엔진은 측정 뒤(11-07 09:32)에 다시 쓰였습니다. 측정 당시 판(`.pre_agent_snapshot/engine.R`, 11-06 20:00)으로 판정했고, 두 판 모두 가격만 씁니다.
- 등급 밖 진단은 따로 봐야 합니다. FF3 · FF5 · Carhart 회귀(`analysis_multifactor.csv`)는 `.cache/kr_factor_returns_v2.parquet`를 씁니다. 이 파일은 2026-06-08에 만들어져 전환보다 앞서고, HML · RMW · CMA는 정의상 재무로 만듭니다. 그래서 가격만 쓰는 전략이라도 이 진단 수치를 인용하면 v1 재무 기반입니다. 등급에는 들어가지 않습니다(`run_paper_replication.R:728` 등급 → `:730~` 진단).
- `v1_defect_overlap_doc`은 README §8 3단계에 적힌 v1 결함(부채 계열 2015~ 0 덮어쓰기 · ≤2014 순이익 낡음 · 단기차입금 오표기 · 2015~ 커버리지)과 입력이 겹치는지를 문서 기준으로만 표시한 것입니다. 크기는 재지 않았습니다.
