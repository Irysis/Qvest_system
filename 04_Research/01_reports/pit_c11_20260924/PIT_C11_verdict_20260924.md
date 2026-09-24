# PIT C11 판정서: 해외(FRED) 시계열의 시간축 결합

2026-09-24 · 읽기 전용 종합 · 조사 4건(코드 A, 데이터 B, 소비자 C, 기존지식 D)과 적대 검증 3건(V1, V2, V3)을 합쳤습니다.
수치는 조사·검증 스크립트에서 재현된 것만 씁니다. **등급에 주는 영향은 하나도 측정하지 않았습니다.**

## 0. 판정 요지

1. **출발점(D32 VIX를 같은 날짜로 결합)은 C11 위반으로 확정입니다.**
   - FRED의 Date는 미국 관측일입니다. 휴장일 패턴, 요일 분포, 적재 시각, CBOE 실제 종가 네 가지가 모두 이를 뒷받침합니다.
   - 결합한 뒤 lag가 걸리지 않습니다.
   - 202608 D32 저장값은 같은 날짜 판과 2550/2550 일치합니다.
   - 이 팩터를 등급 산출에 쓴 곳은 없어 다시 잴 결과는 없습니다. 다만 B1 후보 풀에 적격으로 올라 있어 봉쇄가 필요합니다.
2. **위반은 VIX 한 지점이 아니라 규약 전체의 부재입니다.** 네 기전이 겹칩니다.
   - 공표형(주간·월간) 계열을 관측일로 결합
   - 같은 날짜 병합
   - 1행 lag 신호를 한국 종가→종가 수익에 적용
   - 최신 빈티지를 과거에 소급
3. **등급 결과에 닿은 경로는 셋입니다. A등급 칸은 0, 1계층 충실구현도 0입니다.**
   - L1 강화 최대 35칸: MA01 20칸(C 18, F 2), `pg2_risk_overlay_v1` 15칸(B 5, C 10)
   - 2계층 풀 B 모듈 5개와 FR_003(C)
   - BOOK_0001의 AE·m4 게이트
4. **반증된 조사 결론:** 소비자 조사(C)의 "B 노출 0", "2계층 풀 해외 노출은 MA04뿐", "m4 게이트 적합"은 V3에서 반증됐습니다.
5. **P0-04(close_t1)도 P0-05(보유 기반 재측정)도 C11을 해소하지 못합니다.**
   - close_t1은 미국 일간 종가 1세션분만 체결 뒤로 밉니다. 주간 0~6일, 월간 10~17일의 공표 누출과 빈티지 문제는 그대로 남습니다.
   - 오염은 보유 종목을 고른 신호 안에 들어 있습니다. 그래서 보유 기반 재측정으로는 씻기지 않습니다.

---

## ① 확정 위반 목록

### 1-1. 등급 결과에 닿은 위반 (소비 확정)

| # | 지점 | 계열 | 소비처(등급) | 미래 정보 크기 | 증거 |
|---|---|---|---|---|---|
| V-01 | `compute_regime.R:75-77`(.macro_beta :332-374, MA01 :412-415) | INDPRO, CPIAUCSL | **MA01_GDP_Sensitivity: L1 20칸(C 18, F 2)**, 명세 22건. `RP_20260902_191247_combo` 19칸, `RP_20260903_081538_1520_adapted_rulefast` 1칸. MA02는 소비 0 | 신호월(M-01 라벨) 관측치를 공표 전에 사용. 공식 공표 기준 CPI +10~17일, INDPRO 약 +15~20일(로컬 수신 기준 +16~23일). 월 회귀 약 12쌍 중 마지막 1쌍 | 202608 저장값 2503/2503 재현(INDPRO 8월분 도착 09-18~23). 202003 99.91%. 공표분만 쓰면 202608·202003 MA01이 **산출 불가**(n<12). 원장 vintage_flags의 "MA01 08-31 빌드 결손"이 라이브에서는 만들 수 없었다는 독립 증거 (V2, V3) |
| V-02 | `pg2_risk_overlay.R:90-91,155-173` ← AE 패널 + m4 패널(L1 신호일 종가 체결) | VIX, T10Y2Y(같은 날짜), STLFSI4, NFCI(미공표 주간), 빈티지 | **L1 15칸(B 5 = entry 10·58·59·60·61의 셀 B5_31, C 10)**. 카탈로그 15개 모듈 전부 fr_eligible. FR_003 결과 파일 3개에 B 모듈 4개 포함 | 같은 날짜 미국 월말 종가 218/223개월. STLFSI4 223/223, NFCI 187/223(0~6일). 게이트가 발화한 18개월 전부 해당 | V3 `s12_arm.R`. `assert_overlay_pit`는 날짜 라벨만 비교해 통과 |
| V-03 | `ae_regime_backfill.py:63-83,231-258`, `ae_regime_extend.py:32-47` → `05_Production/.../2-4.STR_1715_on_M4gAE.../forward_weights_R05_noLayer4_M4gAE.R:96` | StL_Fin_Stress, Chi_Fin_Cond(주간), 빈티지 | **BOOK_0001 AE 게이트** | 보유 시작(결정일 뒤 첫 한국 거래일 종가) 시점에 미공표(0~3일 전): STLFSI4 171/223, NFCI 140/223 결정. 실제 게이트(m4와 AE 동시 발화) 18개월 중 14개월 | V3 `s8_aeleak.R`. 이 보유 규약에서는 미국 일간 계열이 적합 |
| V-04 | `data_collector_fred.R:269-277,380-432` → unified 월간 → m4 `factor_engine.R:535-536` | STLFSI4, ICSA, NFCI 월말 관측 | **BOOK_0001 m4 게이트**, pg2 arm | 홀딩월 9월 행이 08-31 점수를 씀(Regime_Score_lag 40.00). 보유 시작 시점 미공표 월: STLFSI4 220, ICSA 183, NFCI 181(총 270개월). STLFSI4 축 점수가 17/270개월에서 뒤집힘. 예: 2020-02는 미공표값 0.681로 +5점, 공표 반영판 −0.439로는 0점 | V3 `s10_m4.R`, `s11_m4weekly.R` |
| V-05 | `regime_signal.R:806-850`(병합 :845-847) | VIX, HY, TS, BBB, FEDFUNDS, NFCI | unified_regime_signal_daily의 FRED_MRS → Category → RCMA, module_performance, **FR_003(C)** | 행 자체가 같은 날짜(미국 1세션) + NFCI 최대 5일 + FEDFUNDS 월초 LOCF | ΔFRED_MRS_t와 ΔVIX_t 상관 +0.838, ΔVIX_{t−1}과는 −0.079 (V1). lag0 적합 오차 mean\|d\| 0.04~0.09, lag1은 0.9~2.0 (V2) |
| V-06 | `apply_regime_overlay.R:67-131`, `regime_module_admission.R:66-67`, `build_module_performance.R:43-45`, `run_wf_ensemble.R:85-91` | 1행 lag된 MRS·Category | ramp r15/r23, STR_1642, RCMA 입장 심사, 모듈 성과, FR_003 | 한국 t−1 종가 뒤의 미국 t−1 세션(약 14시간). FR은 홀딩월 첫날 | r_t와 ΔMRS_t 상관 −0.072, ΔMRS_{t−1}과는 −0.001 (V1). C5 가드(`overlay_pit_guard.R:42`)는 라벨만 비교해 통과 |
| V-07 | `data_collector_fred.R:148-178`, `fred_robust.R:122-150`(ALFRED·realtime 미사용) | NFCI, STLFSI4(전 이력을 매주 재추정), M2SL, INDPRO, ICSA, PERMIT, DEXKOUS | 위의 모든 주간·월간 소비처와 AE 핀 | C1과 C11 동시 위반. 크기는 ALFRED가 없어 측정 불가 | 07-01 백업 대비 소급 수정: STLFSI4 1,375/1,378행, NFCI 1,221/1,378행, M2SL 313/317행, INDPRO 5행 (V1, V3). AE 핀(07-18)도 NFCI 1,053행이 다름 (V3) |

### 1-2. 저장값 오염, 현 등급 체계에서 소비 0 (봉쇄 대상)

| # | 지점 | 계열 | 저장·소비 상태 | 미래 정보 크기 | 증거 |
|---|---|---|---|---|---|
| V-08 | `factor_db_builder.R:293-319`(결합 :311-312) → `compute_defense.R:472-493` | VIXCLS | **D32_Beta_VIX(월간)**. Z값 유효, B1 풀(346종)에 적격. 명세 1,343개, L1·L2 원장, 카탈로그, BOOK에서 소비 0. 팩터 스크린 WT-D20260803_005/006이 소비 | 회귀 약 245쌍 중 마지막 1쌍에 신호일 미국 세션이 들어감(KRX 종가 뒤 13시간 45분~14시간 45분). 2005-01~2026-08 한국 월말 260개 중 255개에 같은 날짜 VIX가 있음 | 202608 2550/2550 일치(sig 행 VIX 14.92 = 미국 08-31, PIT 값은 14.43 = 미국 08-28). 202003 98.1%. close_d_legacy(`run_paper_replication.R:438`)에서 첫 보유 수익에 개입. 빌더식 ΔVIX(d)와 한국 d+1 수익 상관 −0.294, PIT 방식은 −0.025(n=5,359) (B, V2) |
| V-09 | `factor_db_daily_phase6.R:73-98,231-240` | VIXCLS | 일간 D32. roll_beta 창 [t−251, t]가 당일을 포함(`factor_db_daily_rcpp.cpp:64-78`) | 매일 미국 1세션 | fdb_daily_202003 1,200셀 100% 일치(lag1 판과는 0.2%). 2020-03-31 Spearman: 저장값 대 같은 날짜 판 1.0000, 저장값 대 PIT 판 0.2068 (V1, V2) |
| V-10 | `regime_engine_daily.R:257`, `:395-415`(setnames 이름 충돌) | VIXCLS | `regime_daily_v2.VIX_z_smooth`가 일간 RE_VIX_z(phase6:597), regime_jump_model의 VIX_z(:150)→Bear_Prob, forecaster v1tune·v2, ramp r24·r37·r38, regime_study로 흘러감 | 한국 d 행에 미국 d 값 | lag0 100%, lag1 0%(n=7,045) (V2). 같은 날 상관 +0.236, HY는 −0.045 (V1). 엔진 자체 검증(:631-667)은 ax1_VIX만 보고 출력 열은 안 봄 (D) |
| V-11 | `regime_engine_daily.R:89-131,355`(합친 날짜 격자 LOCF + 1행 shift) | ICSA, NFCI, STLFSI4, UMCSENT | MRS 주간·월간 축(ax6~9)이 RE_MRS, RE_exposure, RE04/RE05(일간 DB), regime_tilt, apply_regime_overlay, DPL ML 특성 3개(미채점), 05_Production 구 코드 2개로 흘러감 | ICSA·STLFSI4 약 4일, NFCI 약 3일, UMCSENT 수주 | 공표 미반영 재구성과 5,558일 100% 일치 (V1). Claims_z가 2020-03-23에 0.69→2.06(03-26 공표분을 4영업일 앞서 사용) (V2). 미공표 값 사용일 비율 NFCI 59.8%, STLFSI4 80.0%, ICSA 78.6%(5,843일, A 실측) |
| V-12 | `factor_db_daily_phase7.R:279-305` | VIX, HY, CPI | RE10·RE13(전표본 `frank/.N` = C1, 겸 같은 날짜), RE11(같은 날짜 EWMA), RE14(M-01부터 CPI, 최대 약 45일) | 위 기술 | RE10 2020-03-12 값 −0.9991059가 전표본 순위와 같음(누적 방식이면 −0.99941). RE11 2020-03-16 값이 같은 날짜 판과 일치. RE14 2020-03-02 값 −0.0149404가 3월 CPI(04-10 공표)와 같음 (V1, V2). RE13은 코드로만 확정 |
| V-13 | `compute_regime.R` RE14(:313-330), MA07(:497-524) 월간 | CPIAUCSL, INDPRO | 저장값이 신호월 값. 커넥터가 Z NA·Coverage FALSE로 걸러 **소비 경로 없음** | 위와 같음 | RE14가 202003 −0.0149404, 202208 −0.0822258, 202608 −0.0371296 (V1, V2) |
| V-14 | `data_collector_fred.R:262-277` → `macro_regime.parquet` | 월말 US 종가, 월내 주간값, 같은 달 CPI·IndProd·UNRATE | 같은 달을 조회하는 레거시 STR(STR_944 `run_all.R:46`, 1028/1033 consgate, 824, 943, 791 등. 카탈로그·원장·BOOK 밖), `backtest_harness` load_macro_regime(STR_930/933), m4 경로(V-04) | US 1세션 + 주간 3~6일 + CPI_YoY 약 2주 | 2026-08-31 행: VIX 14.92, NFCI·STLFSI4 08-28분(09-02 공표), ICSA 08-29분(09-03 공표), CPI 08-01분 (V2). 2020-03 행도 같은 구조 (V1) |

### 1-3. 잠재 위반 (코드로 확정, 호출부 0)

- `data_collector_fred.R:471-504` merge_regime_to_signals: lag 없는 roll 결합입니다. V1에서 부분 반증되어 잠재로 분류했습니다.
- `regime_signal.R:1168-1247` compute_bcs_daily: 같은 날짜 결합에 전표본 순위(C1)까지 씁니다. A 조사 단독 소견입니다.
- `ctx_providers.R:133-174` macro provider: 월간 계열을 시차 없이 반환합니다. 소비하는 어댑터가 0개입니다. A 조사 단독 소견입니다.

### 1-4. C11 밖에서 함께 확정된 C1 위반

- `factor_db_daily_phase6.R:218-229` D08_Tail_Beta: 전 이력으로 계산한 꼬리베타를 모든 날짜에 복제합니다. 2008-01 값과 2026-06 값이 1,177/1,177 종목에서 똑같습니다 (V2).
- 일간 RE10·RE13의 전표본 순위(V-12에 포함).
- 일간 RE04(`phase9b:64`)의 전표본 frank는 C 조사 단독 소견이라 **확정하지 않았습니다**.

### 1-5. 반증·정정된 판정 (목록에서 제외하거나 고친 것)

| 원 판정 | 출처 | 검증 결과 |
|---|---|---|
| RE_VIX_z 안전 | A | 반증. V-10으로 편입 |
| regime_jump_model 안전 | A | 반증(전제 오류). 입력 VIX_z가 lag 없는 값 |
| overlay_pit_guard가 u==h를 통과시켜 1일 어긋남 | A | 반증. cutoff가 배타 경계입니다(:9-11). 단 "시간대·공표 시차를 모른다"는 지적은 확정 |
| merge_regime_to_signals 위반 | A | 부분 반증. 호출부 0이라 잠재 |
| 월간 RE14·MA07이 소비되는 위반 | A, B | 소비 부분 반증(커넥터가 제외). 저장 오염(V-13)으로 유지 |
| D32 registry known_discrepancy "compute_regime −1일로 강제" | 레지스트리 | 반증. D32는 그 경로를 타지 않음 |
| B 노출 0, 2계층 풀 해외 노출은 MA04 4개뿐 | C | 반증 → V-02 |
| m4 게이트는 1개월 이상 지연이라 적합 | C | 반증 → V-04 |
| BOOK AE "225/225 결정, 발화 42개월 전부" | C | 과장. DEXKOUS(규약 미정)를 빼면 181/225. 보유 시작 규약을 적용하면 STLFSI4 171/223, NFCI 140/223. 42개월은 AE 단독 발화 수이고 실제 게이트는 18개월 중 14개월 |
| regime_label_gate를 소비처로 셈 | A | 정정. 경고 전용 진단 도구 (V3) |
| 주석 "T−2라서 필요 이상 엄격" | 코드 | 반증. 실제로는 T−1 |
| ast_field_map E4 "PIT-legitimate, 소비자 추가 lag 불필요" | 레지스트리 | 반증 (V-10) |
| WT-D20260803_005 "Δ≤0.0014라 판정 불변, 오염 수치 P_persist 0.5776 정본 유지" | challenge_note | pit.md가 금지하는 "결과 동일"형 합리화. 무효 대상 (D) |

### 1-6. 적합으로 확정된 것 (과잉 수리 방지용)

- compute_regime 일간 계열의 −1일 필터: MA03·MA04·MA05는 발표 반영판과 Spearman 1.0입니다. MA04를 쓴 4칸(C)도 적합합니다.
- RE_HY_z, RE_TS_z: 같은 날 상관 −0.045 / −0.008, 전일 상관 +0.289 / +0.240입니다.
- ECOS 원/달러(731Y001) lag 0: 값이 전 거래일 세션 기반입니다.
- 1계층 충실구현 경로(replication harness, RP_AUTO 엔진, alpha_search): 해외 결합 grep 0건입니다.
- BOOK 알파 팩터(C01·C02·C04·C06·Q07·M08·Q25), R05, 현재 국면 라벨: 모두 국내 데이터입니다.
- 레거시 STR 중 prev_ym(전월) 또는 1개월 shift 판: 적합합니다. 실제로는 2개월 지연입니다.

### 1-7. 판정 불가 또는 검증 미경유

- **DEXKOUS**: 시장 관측 기준(KST d+1 01:00)으로 볼지, H.10 공표 기준(주 1회, 도착 lag 중앙값 5.3~9.5일)으로 볼지는 규약 결정 사항입니다.
- **ICE OAS(HY·BBB)의 lag-1 충분성**: V2는 1표본으로 확정했습니다(09-23 15:27 KST에 09-22 값 없음). V1은 판정 불가로 봤습니다. HY 이력은 3년 롤링 창이라 재현성 문제도 있습니다.
- DGS10의 FRED 게시 시각. 다만 재무부 공개 기준으로는 적합합니다.
- 빈티지 소급의 크기.
- KR_Call1D와 ECOS 채권 금리의 소비처.
- Yahoo 보충값의 날짜 의미.
- 일간 DB 오염 팩터가 ast_compile 리프로 실제 쓰였는지.
- ramp r8·r9·v5_daily가 Bear_Prob을 어떻게 lag 처리하는지.
- AE 발화 월이 실제로 바뀌는지.
- m4 라이브 행이 도착한 값만 담는지.
- **pg2 B 칸을 부모로 삼은 승격 사슬이나 carry 후손 칸이 있는지(미대조).**
- **A 조사 단독(검증 미경유)**: regime_forecaster v1tune·v2·v3·v4, `regime_derivatives.R:471-540`, run_overlay_selfdev(_r2·_r3), vol_rate_matched·hurst_rate_matched 어댑터, `build_wt006_features.R:82-93`, decision_framework 483·331·333, regime_comparison, DVAA lab, 레거시 24개 폴더.

---

## ② 계열별 필요한 lag 규약

### 원칙

관측마다 가용 시각 `avail_ts`(KST)를 붙이고, 관측일이 아니라 이 시각으로 결합합니다. 소비 형태별 요건은 세 가지입니다.

- **(a) 한국 d일 종가에 결정하고, 수익이 d일 종가 이후 시작:** avail_ts ≤ 한국 d일 15:30.
- **(b) 노출을 한국 종가→종가 수익 r_t에 곱함(창 시작 = t−1일 15:30):** avail_ts ≤ 한국 t−1일 15:30.
  - 한국 날짜 격자에서 "1행 lag"를 걸면 미국 t−1일 값이 들어오므로 부족합니다. 미국 날짜 ≤ t−2여야 합니다.
- **(c) 월간 보유:** 수익 창이 실제로 시작하는 시점에 (a)를 적용합니다. close_d_legacy면 sig_d 종가, close_t1이면 집행일 종가입니다. 날짜 라벨(anchor, realized_ym)로 컷오프를 잡지 않습니다(pit.md C5와 같은 원칙).
- **빈티지:** 결정 시각 기준 as-of 빈티지(ALFRED realtime_start)를 씁니다. 없으면 "최신 빈티지" 라벨을 달고 C1·C11 미해소로 둡니다.

### 계열별 규약 (소비 형태 (a) 기준)

| 계열 | 주기 | Date 의미 | 가용 시점(정보 기준) | 규약 |
|---|---|---|---|---|
| VIXCLS, SP500 | 일간 | 미국 거래일 | d+1일 05:00~06:15 KST | **미국 날짜 < 한국 날짜**(한국 다음 영업일부터) |
| DGS10, DGS2, T10Y2Y, T10YIE, T5YIE | 일간 | 미국 국채시장 거래일 | 재무부 d일 저녁 ET = d+1일 오전 KST | 미국 날짜 < 한국 날짜(정보 기준). FRED 적재 기준 라이브는 d+2 |
| BAMLH0A0HYM2, BAMLC0A4CBBB | 일간 | ICE 산출일 | 공개 원천이 FRED뿐. d+1일 밤 KST | **한국 d+2 영업일부터**(보수안). 도훈 님 결정 필요 |
| DEXKOUS | 일간(H.10은 주간 공표) | 미국 영업일, 뉴욕 정오 | 시장 기준 d+1일 01:00 / 공표 기준 다음 주 월요일 | 도훈 님 결정 필요. 권고는 ECOS 731Y001로 대체 |
| WALCL | 주간(수) | 수요일 잔액 | 금 05:30 KST | 라벨 +2일(한국 금요일) |
| NFCI | 주간(금) | 그 주 금요일 | 수 21:30 KST | 라벨 +6일(한국 목요일) |
| STLFSI4 | 주간(금) | 그 주 금요일 | 금 00:00 KST | 라벨 +7일(한국 금요일) |
| ICSA | 주간(토) | 그 주 토요일 | 목 21:30 KST | 라벨 +6일(한국 금요일) |
| FEDFUNDS | 월간 | M-01(M월 평균) | M+1월 첫 영업일 | **공표일 기준**: M+1월 셋째 한국 영업일부터 |
| UNRATE | 월간 | M-01 | M+1월 첫 금요일 | 공표 다음 한국 영업일 |
| CPIAUCSL | 월간 | M-01 | M+1월 10~15일경 | 라벨 +38~48일. 2025-10 관측이 없음 |
| INDPRO, PERMIT | 월간 | M-01 | M+1월 16~20일경 | 라벨 +47~54일 |
| M2SL | 월간 | M-01 | M+1월 넷째 화요일 | 라벨 +51~64일 |
| UMCSENT | 월간 | M-01 | 원천은 M월 말, FRED는 1개월 늦게 게시 | FRED 경유 기준 M+2월 5일경 |
| PCOPPUSDM / DRTSCILM | 월간 / 분기 | 기간 첫날 | — | 라벨 +42~51일 / +33~37일 |
| ECOS 원/달러 731Y001 | 일간 | 한국 적용일(값은 전 거래일 세션) | — | **lag 0 적합(검증됨)** |
| ECOS 채권 금리 817Y002 | 일간 | 한국 d일 | 시각 미검증 | lag 1 권장 |
| KR_Call1D | 일간 | 한국 d일 | d+1일 도착 | lag 1 이상 필수 |
| KR_CPI 901Y009 | 월간 | M-01 | M+1월 초 08:00 KST | 공표일부터 |

주간·월간 오프셋은 3개월치 스냅샷(계열당 공표 2~3회)에서 나온 상·하한입니다. 휴일로 밀린 공표나 셧다운 지연은 덮지 못합니다. **과거 백필의 정본은 ALFRED 실공표일**이고, 고정 오프셋은 상한값으로 쓰는 임시판입니다.

---

## ③ 영향 범위

| 층 | 오염 대상과 규모 |
|---|---|
| 팩터(월간 FDB) | D32: 저장 오염, 소비 0, B1 적격 · MA01: L1 20칸 · MA02: 소비 0(202607부터 결손. CPI 2025-10 부재가 원인으로 지목됨, V2·V3) · RE14·MA07: 저장 오염, 소비 불가 · MA03~05: 적합 |
| 일간 fdb | D32, RE10/11/13/14, RE_VIX_z, RE_MRS, RE_exposure, RE04/05, D08(C1). 소비는 DPL ML 특성 3개(미채점). 등급 소비는 0건 발견, ast_compile 사용 여부는 미확인 |
| 국면·오버레이 | regime_daily_v2, unified daily·monthly, macro_regime, Bear_Prob, apply_regime_overlay(ramp r15/r23, STR_1642), regime_tilt, RCMA, module_performance. 오버레이 후보 22건은 전부 기각(INFERIOR/INDETERMINATE)됐지만 오염된 신호 위에서 잰 결과라 **"깨끗한 음성"으로 인용하면 안 됩니다** |
| 강화 L1 | 전체 시도 1,281건(C 781, B 336, F 88, NA 약 76) 중 **오염은 최대 35칸(B 5, C 28, F 2)**. A는 0. MA01 칸과 pg2 칸의 중복은 대조하지 않았습니다. MA04 4칸(C)은 적합 |
| 2계층 L2 | FR_003(C): Category 경로에 pg2 B 모듈 4개 포함. S_lag1 판(PORT_t 1.437→1.296, Calmar 0.357→0.352, 등급 C 유지)도 pg2 B 모듈을 포함하므로 청정판이 아닙니다. 플랜 기록상 l2_auto가 활성이고 FR_003 T/S/C 요청이 발행된 상태라, **오염 입력이 지금도 소비되고 있습니다** |
| 2계층 풀 | 카탈로그 862개(A 0, B 278, C 433, F 148) 중 pg2 모듈 15개가 모두 fr_eligible. **B 풀 278개 중 5개가 오염**입니다: `RP_20260919_223831_9344`, `RP_20260921_074130_16308`, `RP_20260921_104337_26560`, `RP_20260921_145714_13072`, `RP_20260923_190423_24764` |
| BOOK | BOOK_0001(grade_basis = dohoon_mandate_20260829, judge_verdict_path null)의 AE 게이트(V-03), m4 게이트(V-04), 빈티지. 공식 지표(SR 1.595 등, gross 267개월)는 오염된 게이트 이력 위의 수치입니다. 라이브 AE는 결정 시점 핀이라 공표 기준으로 안전합니다(A 조사 E절). 즉 백테스트와 라이브가 비대칭입니다 |
| 05_Production(읽기만 집계, 4파일) | 2-4 STR_1715_on_M4gAE `forward_weights:96`(BOOK AE) · 1-1 STR_1631_VDplus_CoreAlpha `run_all.R:405-421`(regime_daily_v2) · 2-1 STR_1715_AR `run_4layer_production.R`(MRS) · 3-1 DVAA lab `:145-189`(Qvest 밖). 수정은 `promote_to_production()`로만 가능 |
| 1계층 충실구현 | 0 |
| WT·스크린 | WT-D20260803_005/006이 D32를 소비(스크린 PORT_t −1.20/−1.10). 오염 정본 P_persist 0.5776 |

### 방어선이 C11을 못 잡은 이유

양성 대조가 없는 계기는 방어선으로 세지 않습니다. 현재 상태는 다음과 같습니다.

- **`lookahead_detector.R`**
  - `:236`의 C3 면제("Macro/regime lookups are OK")는 코드로 굳은 합리화입니다.
  - 주변 문자열 휴리스틱이라 돌연변이 두 종류에서 거짓 음성, 올바르게 lag한 파일 두 개에서 거짓 양성이 납니다. 실소비자 `compute_defense`는 통과시킵니다.
  - factor_db 빌더는 한 번도 스캔 대상이 된 적이 없고, C11 테스트는 0건입니다.
- **`pit_verify_fred_lag`**: 무조건 TRUE를 반환하고 호출부가 0개입니다.
- **`overlay_pit_guard`와 AE 가드**: 날짜 라벨만 비교합니다.
- **`ast_verify.py:360-361`**: 레지스트리의 "-1d" 선언을 그대로 믿습니다. RE_VIX_z의 거짓 선언도 통과했습니다.

---

## ④ 영향 크기 추정 방법 (등급 영향은 전부 미측정)

### 이미 재현한 것 (신호 수준, 등급 아님)

- **D32:** 같은 날짜 판과 라이브 판의 차이입니다 (V1).

  | sig | Spearman | 상위 5분위 교체 |
  |---|---|---|
  | 2026-08 | 0.99961 | 12종 |
  | 2020-03 | 0.99914 | 16종 |

  신호일 한 쌍만 떼어 내면 Spearman 0.9997(202608), 0.9986~0.9988(202003)입니다 (V2, V3).
- **MA01·MA02:** 코드판과 공표분판의 차이입니다.

  | 시점 | MA01 | MA02 |
  |---|---|---|
  | 2022-08 | Spearman 0.9936, 상위 5분위 34종 교체 | Spearman 0.9049, 152종 교체 |
  | 2015-06 | 0.982 | 0.935 |
  | 2020-03, 2026-08 | 공표분판 산출 불가 | 공표분판 산출 불가 |

- **누출 정보량:**
  - 한국 r(d)와 직전 미국 ΔlogVIX 상관 −0.287(n=6,333) / −0.305
  - 빌더식 ΔVIX(d)와 한국 d+1 수익 −0.294, PIT 방식은 −0.025(n=5,359)
  - r_t와 ΔMRS_t −0.072, ΔMRS_{t−1}과는 −0.001

### 측정 설계

| 대상 | 방법 | 판정 규칙 |
|---|---|---|
| MA01 20칸 | 공표 시차를 반영한 MA01(창 = 최근 공표 12관측)로 명세를 다시 실행 → essence | 정의가 바뀌므로 재측정이 아니라 새 명세 측정입니다. 원래 20칸은 결과와 무관하게 무효 |
| pg2 15칸, FR_003, BOOK_0001 | 1. AE 특성을 공표 시차 반영판으로 재구성 2. LSTM 재실행 3. fire_seq 차이(뒤집힌 발화 월 수) 확인 4. m4 공표판 재산출 5. 셀 엔진 재실행 6. FR_003 T/S/C 재실행 7. BOOK 트래킹 재현 | 차이가 0이어도 원판은 무효 처리하고 재측정판을 정본으로 씁니다. 차이 0을 원판 유지 근거로 쓰지 않습니다 |
| 일간 오버레이, RCMA, module_performance | pit.md C5 의무에 따라 lag1 스트레스 + strict-PIT A/B(`overlay_lookahead_ab` 인플레 >5%면 strict로 재판정) | pit.md 그대로 |
| D32 | 등급 소비가 0이라 등급 측정은 불필요. 수리 후 202608 저장값과 수리판을 비교해 수리 정확성만 확인 | — |
| 빈티지 | ALFRED 수집 후 as-of 판과 최신판 A/B | 현재 스냅샷 38개(07-01~09-24)로는 과거 크기를 추정할 수 없음 |
| WT-D20260803_005 | 측정이 아니라, 제외판(Δ≤0.0014로 기록된 판)을 정본으로 재지정 | — |

---

## ⑤ 수리안

### 공통 코드 수리 지점

1. **VIX 결합 키:** `factor_db_builder.R:311-312`, `factor_db_daily_phase6.R:86-90`을 avail 기준(미국 날짜 < 한국 날짜)으로 바꿉니다.
2. **`compute_regime.R:75-77`:** 계열별 가용일 필터를 넣습니다. 헤더의 "C11 compliant" 주석을 고칩니다.
3. **`regime_engine_daily.R`**
   - 이름 충돌(:257, :395-415)을 고칩니다.
   - 주간·월간 축을 avail로 결합합니다.
   - "T−2" 주석을 고치고, 자체 검증이 출력 열을 보게 합니다.
4. **`factor_db_daily_phase7.R:279-305`:** RE10·RE13을 누적 방식으로 바꾸고 lag를 걸며, RE11·RE14에도 lag를 겁니다.
5. **`regime_signal.R:806-850`과 `macro_regime` 월말 행:** 컷오프까지 공표된 값만 담게 합니다.
6. **소비자 4곳**(apply_regime_overlay, RCMA, module_performance, run_wf_ensemble): 규약 (b)를 적용합니다.
7. **AE:** backfill·extend와 pg2 arm의 주간 특성을 avail로 결합합니다.
8. **방어선**
   - `lookahead_detector:236`의 면제를 삭제합니다.
   - `pit_verify_fred_lag`를 실제로 구현합니다.
   - **C11 양성 대조 테스트**를 만듭니다. 같은 날짜 결합을 주입했을 때와 돌연변이에서 모두 red가 나야 합니다.
   - D32 known_discrepancy, RE_VIX_z 선언, ast_field_map E4를 고칩니다.
   - 05_Production 3개 파일은 `promote_to_production()` 경로로만 고칩니다.

### 안 A: 봉쇄와 무효 표식 (이력 재빌드 없음)

- **즉시 조치**
  - rf_factor_arms 후보에서 D32·MA01·MA02를 뺍니다.
  - 격자에서 pg2_risk_overlay_v1을 끕니다.
  - B 모듈 5개의 fr_eligible을 해제합니다.
  - l2_auto의 FR_003 요청을 보류합니다.
- **표식**
  - L1 35칸과 카탈로그 15개 모듈에 `pit_invalid:C11`을 답니다(AX-D10 180008 선례와 같은 어휘).
  - FR_003 결과 3개 파일을 무효로 합니다.
  - BOOK_0001 트래킹에 "C11 미해소 게이트"를 표기합니다.
  - WT-D20260803_005의 정본을 교체합니다.
- **코드:** 공통 지점 1·2·3·7·8을 우선 고칩니다.
- **비용:** 작습니다. writer 경유 표식, config 수정, 코드 몇 곳이면 되고 러너를 세울 필요가 없습니다.
- **위험**
  - 과거 저장 패널은 오염된 채로 남습니다: FDB 260개월의 D32·MA01, regime_daily_v2, unified, macro_regime, AE.
  - 게이트 밖 소비자(ramp, DPL ML, 레거시, 05_Production 구 코드)가 계속 읽습니다.
  - BOOK 공식 지표가 오염 이력 위에 그대로 남습니다.
  - B 풀이 278개에서 273개로 줄어듭니다.

### 안 B: 가용시점 층 + 표적 재빌드 + 오염 칸 재측정 (권고, 안 A 봉쇄를 0단계로 포함)

- **가용시점 층:** 수집기 산출에 계열별 `avail_ts` 열을 둡니다(②의 고정 오프셋 상한값). 모든 결합을 이 열로 합니다.
- **표적 재빌드**
  - 월간 FDB는 D32·MA01·MA02·RE14·MA07 **열만** 2005-01~2026-09 구간을 재계산합니다. 전체 재빌드는 202603~07 빈티지 불일치 사례처럼 다른 팩터를 흔들 수 있습니다.
  - 일간 fdb의 해당 열, regime_daily_v2, unified daily·monthly, macro_regime, AE(LSTM 재실행), m4도 다시 만듭니다.
- **재측정**
  - pg2 15칸은 셀 엔진을 다시 돌립니다(보유 기반 재측정이 아님).
  - FR_003 T/S/C를 다시 돌리고, BOOK_0001 트래킹을 재현합니다.
  - MA01 20칸은 무효를 유지하고, ⑥-5 결정이 나오면 새 명세로 잽니다.
  - pg2 재실행은 P0-04 close_t1 전환 뒤에 새 규약으로 한 번에 해 이중 재측정을 피합니다.
- **비용:** 중간입니다. LSTM 재실행, 260개월×5열 재계산, 패널 재빌드가 필요하고, 러너 배리어(wf_5e20d364-70d) 아래 idle 창이 있어야 합니다.
- **위험**
  - 고정 오프셋은 휴일·셧다운으로 늦어진 공표를 덮지 못합니다. 상한값으로 완화할 뿐 해소는 아닙니다.
  - 빈티지는 여전히 최신판이라 C1·C11이 남습니다. 라벨로 명시해야 합니다.
  - W-05 사이드카와 P0-07 지문 체계와의 순서를 조정해야 합니다.

### 안 C: 안 B + ALFRED 빈티지 (완전판)

- **내용**
  - data_pipeline_queue에 적재한 뒤 ALFRED realtime_start/end를 수집합니다. 대상은 NFCI, STLFSI4, M2SL, INDPRO, ICSA, PERMIT, DEXKOUS, CPIAUCSL, UNRATE, UMCSENT, FEDFUNDS 등입니다.
  - avail_ts를 실공표일로, 값을 as-of 빈티지로 바꿉니다.
  - 국면 신호를 쓰는 소비자 전체(ramp, DPL ML, 오버레이 후보 22건 포함)를 다시 잽니다.
- **비용:** 큽니다. 새 수집기와 테스트가 필요하고, NFCI·STLFSI4는 매주 전 이력을 다시 추정하므로 빈티지 수가 관측 수(약 1,380개) 규모입니다.
- **위험**
  - ICE OAS 등 일부 계열에 ALFRED 빈티지가 있는지 확인하지 못했습니다.
  - 일정이 늦어지는 동안 안 B 판으로 운영해야 합니다.
  - P0-07 지문과 버전을 이중으로 관리해야 합니다.

### P0-05·06 편입 여부

- P0-05는 04_holdings에서 WEIGHTS를 복원해 다시 시뮬레이션합니다. C11 오염은 보유를 고른 신호(MA01 선택, AE·m4 게이트) 안에 있어서 보유 재측정으로는 씻기지 않습니다.
- close_t1 판도 미국 일간 종가 1세션분만 해소합니다.
- 따라서 35칸을 P0-05 1·2단계에 일반 칸으로 넣으면 **오염된 보유가 rebase된 essence(`essence_history`)로 세탁됩니다.**
- **권고:** 재측정 경로에는 **편입하지 않습니다.** 대신 다음을 공유합니다.
  1. P0-05/06이 `pit_invalid:C11` 칸을 건너뛰거나 표식을 승계하도록 하는 술어
  2. C11 데이터 수리를 P0-07 `measurement_regime`/지문의 한 키로 기록해, 수리 전후 칸을 구분
  3. P0-06 writer(`rf_rebase_essence`)의 append-only history에 C11 regime을 추가
- **순서:** 안 A 봉쇄 → 코드 수리 → (P0-04 전환) → 안 B 표적 재빌드 → pg2·FR_003·BOOK 재측정 → P0-05 2단계에서 C11 표식 칸이 빠졌는지 확인.

---

## ⑥ 도훈 님 결정이 필요한 사항

1. **DEXKOUS 기준:** 시장 관측과 H.10 공표 중 무엇으로 볼지. 권고는 ECOS 731Y001로 대체하는 것입니다. BOOK AE의 원/달러 특성 처리도 이 결정에 따릅니다.
2. **ICE OAS(HY·BBB) 기준:** FRED 게시 기준(한국 d+2, 근거 1표본)과 ICE 산출 기준(d+1) 중 무엇으로 할지.
3. **공표 시차 구현 수준:** 고정 오프셋 상한판(안 B)부터 할지, ALFRED 실공표일(안 C)로 갈지. 플랜의 미결 항목 "vintage 정책"과 합쳐서 정해야 합니다.
4. **수리안 선택:** A / B(권고) / C.
5. **MA01·MA02 명세:** 현재 창(12개월·최소 12관측)으로는 PIT 판을 만들 수 없습니다. 창을 "최근 공표 12관측"으로 다시 정의할지(근거 제시 필요), 퇴역시킬지.
6. **무효 범위:**
   - L1 35칸(B 5, C 28, F 2)
   - 카탈로그 15개 모듈의 fr_eligible 해제(B 5 포함)
   - FR_003 결과 무효
   - 진행 중인 l2_auto FR_003 T/S/C 요청 보류
7. **BOOK_0001** (mandate로 A, Judge 없음, AE·m4 게이트 C11 오염). 선택지는 셋입니다.
   - (a) 등록을 유지하고 트래킹에 C11을 표기
   - (b) 트래킹 중지
   - (c) 재산출 후 Judge 스폰
   - 운영 코드 수정은 `promote_to_production()` 승인이 필요합니다. 10-01 결정일이 가깝습니다.
8. **WT-D20260803_005/006:** 오염 정본(P_persist 0.5776)을 무효로 하고 제외판을 정본으로 지정할지.
9. **P0-05·06 편입 방식:** 권고는 재측정 경로 비편입, 표식·epoch 공유입니다.
10. **방어선 수리 포함 여부:** 면제 삭제, `pit_verify_fred_lag` 구현, C11 양성 대조 테스트, 레지스트리 선언 정정. 하네스 파일 쓰기라 승인이 필요합니다.
11. **C11 밖 C1 동시 수리 여부:** D08_Tail_Beta와 RE10·RE13. RE04(phase9b:64)는 먼저 검증해야 합니다.
12. **CPIAUCSL 2025-10 부재:** 행 기준 shift(12)가 13개월 변화가 되는 문제입니다. RE14·MA07을 왜곡하고 MA02 결손의 원인으로 지목됐습니다. 날짜 기준 12개월 변화로 고칠지 정해야 합니다. PIT가 아니라 데이터 결함입니다.
13. **등급 체계 밖 소비자:** 레거시 STR 24개 폴더, ramp, DPL ML, 05_Production 구 코드 2개(1-1, 2-1)를 수리 대상에 넣을지, 표식만 할지.

---

증거 스크립트는 모두 읽기 전용으로 만들었고, 운영 파일 쓰기는 0건입니다.
- `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/a_code/` (A)
- `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/b_data/` (B)
- `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/work/` (C)
- `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/d_knowledge/` (D)
- `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/v_adv/` (V1)
- `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/adv_q3/` (V2)
- `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/adv/` (V3)

P0-05·06 대조에 쓴 파일: `C:/Users/99922/.claude/plans/qvest-1-drifting-eclipse.md`(:96-98, :553-558), `C:/Users/99922/OneDrive/Quant_Module_Moltbot/06_Registry/book/book_registry.json`(BOOK_0001)