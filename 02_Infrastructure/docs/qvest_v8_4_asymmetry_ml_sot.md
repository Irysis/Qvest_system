# Qvest v8.4 SOT — 비대칭 알파 중심 재편 (ML · 수리통계 주력)

**발효**: 2026-08-13 · **근거**: 도훈 mandate — *"v8.3의 비 return 주력 레인은 폐기해. 기존 데이터풀을 총동원해서 머신러닝 기법과 수학 통계적 기법을 통한 최적화 극대화를 통한 시장 비대칭 알파 도출을 주력 목표로 재편해."*

**대체 관계**: v8.3 SOT(`qvest_v8_3_alpha_discovery_sot.md`)의 **도달 경로 ①(비-return 신규 원천)을 주력에서 해제**한다. v8.3의 나머지 골격(벽-정합 측정 · dual-basis · 상설 프론티어 큐 · 지식 환류)은 **불변 승계**. Graduation HARD 3종 · cap-w 게이트 권위 · 6-agent · Production Constraints(INV-7) · governor 수동도 불변.

---

## §0 한 줄 요약

> 우리는 **월간 횡단면의 평균**을 16개월간 쟀다. 데이터는 **일별로 9,005일** 있고,
> 실측은 **평균과 중앙값의 부호가 갈린다**고 말한다. 주력을 그 갈라진 자리로 옮긴다.

---

## §1 왜 비-return 레인을 주력에서 내리는가 (실측 근거, 폐기 아닌 재배치)

도훈 지시는 "폐기"지만 **INV-7 정합 서술로 남긴다** — 구조 판결이 아니라 *현 시점 EV 판정*이다. 5개 레인의 실측 상태:

| FQ | 레인 | 실측 상태 (2026-08-13) |
|---|---|---|
| FQ-001 | DART exec-insider | **3-프레임 삼각-null** — selection(R9) · monitoring(R33/R37) · exclusion(WT-D20260718_002) 전부. 배제 각도는 base 훼손(cap-w 1.171→0.771 · paired −2.15%/yr t −1.35 · sweep 21/21 음) |
| FQ-002 | 계약수주 magnitude | 두 소비면 닫힘. 전구간 크롤 1.5~3.2일 지불 대비 EV 하락으로 보류 |
| FQ-003 | 공매도잔고 | **데이터 게이트 폐쇄** — 도훈 2026-08-09 "신용대차는 업데이트 계획 당분간 없어" |
| FQ-004 | 담보/질권 · 감사의견 | 3재료 전부 **SPARSITY_WALL** (월평균 1.3~1.7종목, exclusion delta <0.02%/yr, t<1.9) |
| FQ-005 | QW crowding | **데이터 게이트 폐쇄** — 동일 결정 |

⇒ 5 중 2는 **도훈 자신이 데이터를 막았고**, 3은 실측 negative다. 주력으로 유지할 근거가 실측에 없다.
★**부활 조건 (INV-7)**: FQ-003/005 는 QuantiWise export 재개 시 **즉시** 재개(스캐폴드 사전 준비 유지). FQ-002 는 FQ-193 이 천장 25%+ 회수 시 재검토. FQ-001/004 는 novel-method 신호(예: 아래 §3 비대칭 표적으로 재서술) 발화 시.

---

## §2 ML 트랙은 이미 126건 돌았다 — 어디서 죽었는지가 재편의 설계도

`hypothesis_index` 구조화 필드 `hypothesis_signature[0] == "ml_complexity"` 실측 = **126건** (2026-06 113 · 07 10 · 08 3).
**metric_type = `registry_record`** (원장 재판독 2026-08-13, `generated_at` 2026-08-13T06:48:35 — 성과 재측정 아님. 각 값은 그 라운드가 당시 기록한 값이다).

⚠**커버리지 먼저**: 126건 중 **sharpe 보유 84건 · 미보유 42건**. 따라서 이 트랙에 대한 **"126건 전부" 류 전수 주장은 성립하지 않는다**(아래 §2-끝 정정 절 참조).

### 죽은 자리 ① — ML을 **결합기(combiner)** 로 쓴 것

앙상블·스태킹·투표·수축·NCO·국면가중 변형이 다수. 실측 분포(84건):

| 지표 | min | p25 | median | p75 | max |
|---|---|---|---|---|---|
| sharpe | −0.405 | **0.492** | **0.493** | 0.585 | **0.756** |
| mdd | 36.01 | 54.57 | 57.27 | 57.27 | **98.62** |
| ir | **−0.810** | −0.162 | 0.014 | 0.044 | 0.391 |

- **동일 (sharpe, mdd, ir) 3짝 클러스터**: 최대 **16건**(0.493 / 57.27 / 0.014) + 2위 **9건**(0.492 / 57.27 / 0.012) = 84건 중 **25건(30%)**. 서로 다른 결합 규칙이 **같은 점을 낸다** — 같은 5전략 재가중이라 새 정보가 없다는 진단의 실측 근거는 이 클러스터이지 "전부 수렴"이 아니다.
- **★MDD ≤ 25%(목표) 충족 = 0/84.**
- **★PORT_t 기록 10건 중 ≥ 2.95 = 0건** (범위 −1.377 ~ 2.362).
- ⚠**PG2 와의 대비는 basis 를 병기해야 한다**: SR 0.756 은 hurdle 표 sharpe 이고, 부팅 배너 `SR_geo 1.898` 은 **stored admit-baseline** 이다. `book_state.json`(`qepm/mailbox/governor/`) 의 게이트 정본 필드는 **`incumbent_book_ir` 1.416** (`ir_convention = net_active_recon_v1`). **세 수를 한 문장에 놓지 말 것**([[feedback-relative-basis-t-never-vs-graduation-threshold]] 의 SR 판).

### 죽은 자리 ② — ML을 **선택·사이징**에 쓴 것

`oos_retention` 기록 **17건 · 음수 10건 · 중앙 −0.481 · 최저 −1.499 · 게이트(≥0.7) 충족 2건**.

- **DPL**(2026-06-26): 8 config + GPU 전수 — settled-negative, 재구현 금지(measurement-graduation §5)
- **uncertainty-aware** selection·sizing 양 레벨(2026-07-05 2세션): robust FAIL
- **RAMP_R2_ML**(2026-07-05): PORT_t 1.418 · **oos_retention −0.481** (OOS 가 IS 의 부호를 반대로 뒤집음)
- **WT-D20260705_001**(2026-07-05): PORT_t 2.362 · **oos_retention 0.037** — 트랙 PORT_t 최대값인데도 게이트 미달

### 얕게만 시도된 자리 ③ — ML을 **월간 평균 예측기**로 쓴 것

"XGBoost 로 종목별 다음 달 수익률 직접 예측"(SR 0.493) · "RF 종목 선정"(0.493) · "ML Factor Return Prediction"(0.464).

### ★미측정 자리 — 여기가 재편 표적 (주장 강도 정정판)

**⚠2026-08-13 자기정정** — 초판은 *"126건 전부가 표적을 평균으로 놓았고 분포 표적 라운드는 0건"* 이라고 썼다. **그 주장은 근거가 없다**:
`key_metrics` 에 **예측 표적을 기록하는 구조화 필드가 없다.** 나는 title 산문을 읽고 전수 주장을 냈는데, 그것이 바로 이 저장소가 금지하는 **자유 형식 패턴 감사**다([[feedback-pattern-audit-of-freeform-fails-use-structure-target-or-behavior]]). 게다가 metric 보유가 84/126 이라 전수 서술 자체가 불가능하다.

**실측으로 말할 수 있는 것만 남기면**:
1. 트랙 84건 중 **MDD 목표 충족 0건**, PORT_t 기록 10건 중 **자본 문턱 통과 0건**, oos_retention 17건 중 **게이트 충족 2건** ⇒ **이 트랙은 자본 게이트를 하나도 통과하지 못했다**(강한 실측).
2. 표본 판독에서 **분포(분위·왜도·꼬리)를 예측 표적으로 명시한 라운드를 찾지 못했다** — 이는 *부재의 증명이 아니라 미발견*이다. ★"아무것도 없다"는 가장 비싼 주장이므로 그 강도로 쓰지 않는다.

⇒ **재편 근거는 ①(게이트 통과 0)이 지탱한다.** ②는 가설이며, Lane A 의 arm A(평균-표적 대조군) 재현이 그 가설의 **첫 시험**이다 — arm A 가 기존 SR ~0.49 대역을 재현하면 "평균 표적으로는 여기까지"가 실측으로 고정되고, 그때 비로소 표적 교체의 증분이 해석 가능해진다.

---

## §3 왜 비대칭인가 — 시스템이 이미 실측했다

도훈 지시의 "시장 비대칭"은 새 발상이 아니라 **08-09 도훈 자신의 발안**(FQ-182: *"'위기 뒤 평균이 높은가' 대신 '꼬리·왜도가 바뀌는가'"*)의 연장이고, 그 사이 실측이 쌓였다:

| 실측 | 값 | 출처 등급 | 함의 |
|---|---|---|---|
| D03_EWMA Q5−Q1 **평균** 스프레드 | 연 **−5.10%** (NW t −1.07) | `stage_artifacts/WT_D20260808_001/alpha_validation.json` 에 문자열 확인 | 평균으로는 0 과 구별 불가 |
| 같은 쌍 **중앙값** 스프레드 | 연 **+12.01%** (t +2.57) | ⚠**구조화 출처 미확인** — 08-13 재탐색에서 해당 WT 산출물 전체에 `12.01` 문자열 **부재**. 현재 근거는 `layer_bottreneck_map.md` **산문 기록**뿐 | ★부호 반대 주장의 **핵심 수치인데 재현 경로가 없다** — R1 착수 전 재산출 필요 |
| 분위별 횡단면 왜도 | Q1 +0.96 → Q5 +0.69 | ⚠동일 (산문 기록) | 꼬리 비대칭 개입 주장 — 미재현 |
| 분위 프로파일 형태 | M26 단조 · Q01 **혹(hump)** · D03 **상단-역전** | 라운드 산출물 다수 | 선형 가정이 형태를 못 담는다 |
| 측정 도구의 성질 | rank-IC 는 **순위**라 이상치 둔감 · PORT_t 는 **평균**이라 꼬리 지배 | 구조적 사실 | 두 지표의 불일치 = 비대칭의 지문 |

★**정직 고지 (2026-08-13)**: 이 절의 **가장 강한 두 수치(중앙값 +12.01% · 왜도 Q1→Q5)가 산문에만 있다.**
자유 텍스트 기록은 사후 감사를 지탱하지 못한다([[project-freetext-records-cannot-be-audited-retroactively-20260810]]).
⇒ **Lane A(FQ-233) 착수 전 필수 0항 신설**: 이 두 수치를 구조화 산출물로 **재산출**한다. 재현되지 않으면 §3 의 "부호가 반대" 근거는 철회하고, 재편은 §2 ①(자본 게이트 통과 0)만으로 지탱한다 — 재편 방향 자체는 바뀌지 않으나 **동기 서술의 강도는 낮춘다**.

⇒ **평균 기반 선형 횡단면 측정이 놓치는 구조가 실측으로 존재한다.** β-drag(주장 A)와 왜도(주장 B)는 같은 사실의 경합 설명이며 **아직 분해되지 않았다**(WT-D20260808_001 적대검증). 재편은 이 미분해 지점을 정면으로 겨눈다.

계약 기반도 이미 있다: `02_Infrastructure/contracts/moment_fragility.R`(08-09 신설, 17/17) — **스케일 불변 ≠ 이상치 강건**을 실측으로 분리한다.

---

## §4 데이터풀 실측 인벤토리 — "총동원"의 실제 범위

★**핵심 발견: 우리 알파 리서치는 전부 월간 횡단면인데, 데이터는 일별로 9,005일 있다.**
`load_month_factors()` 경유 월말 z-score → 다음달 수익이 표준 경로였고, **월간으로 접는 순간 분포 정보가 소멸**한다. 비대칭은 접히기 전에만 관측된다.

| 패널 | 규모 | 기간 | 축 |
|---|---|---|---|
| `.cache/RAWDATA.parquet` | 14,064,459행 · 21열 | 1990-01-05 ~ 2026-08-11 (**9,005 거래일**) | 일별 OHLCV + Size + Sector_Lv2 + K200/KQ150 + BM_Ret |
| `.cache/flow_features_daily.parquet` | 9,362,399행 · 22열 · **1.25GB** | 2000-01-04 ~ 2026-07-01 (6,530일) | 기관/외국인/개인 순매수 5·20·60d · flow momentum · concentration · turnover_chg · foreign_own_chg · earnings_proximity |
| `.cache/fundamental_xlsx_derived` / `_ttm` | 14,119,364 / 4,133,534행 | long format | 재무 파생 · TTM |
| `.cache/regime_daily_v2.parquet` | 8,242행 · 22열 | 2000-01-01 ~ 2026-08-12 | MRS + 9축 z-score(VIX/HY/TS/BBB/KRW/FinStress/NFCI/Claims/Sentiment) |
| `.cache/fred_macro_wide.parquet` | 8,238행 · 24열 | 2000-01-01 ~ 2026-08-06 | 매크로 23계열 일별 |
| `.cache/ecos_bond_rates` · `ecos_krw_usd` | 37,315행 | 2001-01-01 ~ 2026-08-12 | 국내 금리·환율 |
| factor DB | 331 팩터 (선언 계열 **15종**) | 1990~ | 월간 — **전수 book-marginal 통과 0** |

⚠**정직 고지**: factor DB 331 전수는 이미 소진됐다(통과 0). "총동원"의 증분은 **factor DB 가 아니라 일별 원천 패널**에 있다. 그리고 계열 수 15가 **구속 해상도**다 — 팩터를 더 만들어도 계열-군집 유의는 안 나온다([[project-family-count-is-the-binding-resolution-limit-20260810]]).

---

## §5 재편 후 주력 레인 (3 lane)

### Lane A — 분포-표적 학습 (Distribution-Target Learning) ★1순위
예측 표적을 **평균에서 분포로** 바꾼다. 같은 피처·같은 유니버스·같은 비용으로, **표적만 교체**한 A/B 가 1라운드다.
- 후보 표적: 조건부 분위(quantile regression / LightGBM pinball) · 조건부 왜도·첨도 · 하방편차 · 상방참여율 · 꼬리초과확률 P(ret > q90) − P(ret < q10)
- ★**대조군 의무**: 동일 파이프라인의 **평균-표적 판본**(= 기존 SR ~0.49 계열)을 같은 라운드에서 함께 돌린다. 표적 교체가 유일한 자유도여야 한다.
- 사전등록: 무엇이 나오면 lane 성립인지 착수 전 고정(§7).

### Lane B — 일별 축 정보 회수 (Intramonth / High-Frequency Structure)
월간으로 접기 **전**의 구조를 피처로 승격한다. 9,005 거래일 × 22 flow 피처가 미소비 표면이다.
- 후보: 월내 수익 분포의 적률(왜도·첨도·점프 빈도) · 일중 flow 비대칭(외국인-개인 반대부호 강도) · 실현 반변동성(하방/상방 분리) · 월내 최대낙폭
- ⚠ **PIT 최우선**: 월내 피처는 홀딩월 **시작 전**까지만(C5 오버레이 타이밍 규약 동형). `assert_overlay_pit()` HARD + lag1 스트레스 + strict-PIT A/B 의무.

### Lane D — 매크로 상태 조건부 비대칭 (도훈 추가 지시 2026-08-13 "매크로 데이터도 적극 활용해줘" · "이미 적재하고 있을텐데") ★2순위

**★도훈 확인 사항 — 맞다, 이미 적재 중이다.** 2026-08-13 07:04~07:07 갱신 실측: `macro_fred`(lag 1d) · `ecos_bond_rates`(1d) · `ecos_krw_usd`(1d) · `regime_daily_v2`(1d) · `unified_regime_signal_daily`(1d). **신규 수집 불요 — 소비 배관만 붙이면 된다.**
단 **착수 전 확인 4건**이 실측으로 나왔다(전부 소비 표면에 직접 닿는다):

**⚠2026-08-13 자기정정 — 초판이 낸 "정체 4건" 중 2건은 오진이었다.**
초판은 calendar-day lag 로 재고 "`fred_macro_wide` 5일 정체" · "`flow_features_daily` 43일 정체"를 배관 결손으로 신고했다.
**선언 정본(`02_Infrastructure/data/cache_registry.json`)과 감사 산출(`cache_freshness_latest.json`, 08-13 07:07 실행)을 읽으니 둘 다 FRESH 였다** —
`lag_basis`가 **`content+trading_days`** 라 달력 7일이 거래일 4일이고(`lag_used 4 ≤ max_lag 4`),
`flow_features_daily` 는 **weekly·tier 3·max_lag 90** 계약이라 `lag_used 43` 이 정상 범위다.
★기전 = **계약이 선언한 basis 가 아니라 내 basis 로 재고 차이를 결함으로 읽었다** — EW-basis 카드와 같은 병.
⇒ 규약: **패널 신선도는 `cache_registry.json` 선언(`schedule`/`max_lag_days`/`lag_basis`)과 감사 `lag_used` 로 판정한다. 직접 잰 calendar lag 로 결함을 선언하지 말 것.**

| # | 실측 | 판정 |
|---|---|---|
| ~~1~~ | ~~`fred_macro_wide` 파생 정체~~ | **철회** — `lag_used 4 ≤ max 4` (content+trading_days), status FRESH |
| ⚠2 | **계열별 시차 불균질** — 23계열 lag **중앙 12일 · 범위 7~73일**. 최악 Copper_Price·US_CPI·US_M2·UMich_Sentiment·Housing_Permits·US_IndProd = **73일**(월간 발표), 최선 VIX·Term_Spread·HY/BBB_Spread·SP500 = 7일(일별) | **유효** — 하나의 "매크로 상태" 벡터로 묶으면 **가장 느린 계열이 전체를 지배**한다. PIT C11 상 계열별 발표시차가 다르므로 **계열별로 다루거나 느린 계열 기준으로 지연** |
| ⚠3 | **`macro_regime` 마지막 행이 미래 날짜**(2026-08-31). 판별 실행: **월말 스탬프 320/320 = 100%** ⇒ look-ahead 아님(월 라벨 관례). **그러나** 그 행은 **진행 중인 8월의 부분 관측**인데 31열 중 **22열에 값이 차 있고**, 그 입력(`fred_macro`)은 08-06 까지다 | **유효, 그리고 감사 사각**: freshness 감사는 이 행의 `data_lag = −18`(미래)을 **`lag_used = 0` 으로 clamp** 해 **FRESH 로 판정한다** ⇒ **미래-날짜 스탬프를 잡는 검사가 없다.** ⇒ 규약: **월말-스탬프 매크로는 홀딩월 시작 전 컷오프로 재매핑 + 진행 중인 월(마지막 행) 소비 금지** |
| ~~4~~ | ~~`flow_features_daily` 43일 정체~~ | **철회** — weekly·max_lag 90 계약, status FRESH. 단 **content 가 2026-07-01 에서 끝나므로 Lane B 의 데이터 지평이 거기까지**라는 *커버리지 제약*은 유효(결함이 아니라 설계 입력) |
| ★5 | **`RAWDATA::value` · `benchmark::value` = VALUE_FAIL CRITICAL** (`\|BM_Ret\|>0.15`, max 0.1998 @ 2026-07-31) — 부팅이 crit 2 로 매일 띄우던 것 | **오탐 확정**. cap-weighted 재구성으로 판별: 2026-07-31 저장 BM **+19.98%** vs **t-1 Size 가중 재구성 +18.43%**(EW +5.43%). 49거래일 **cor 0.9989 · \|gap\| 중앙 0.0029 · \|gap\|>0.02 인 날 0/49**. ⇒ **저장 벤치는 구성종목과 정합하며 결함이 아니다** — 초대형주가 실제로 폭등한 날이고, cap-w 평균이 EW 분위 범위를 벗어나는 것은 쏠림의 정상 귀결이다. 검사기 쪽 문제 = **고정 문턱 `\|BM_Ret\|>0.15`** 가 분포가 이동한 국면에서 실제 값을 결함으로 신고 |
| ★6 | **2026년 벤치 일간 변동성이 역사의 2.6배** — sd **0.0444**(2026, n=150) vs **0.0170**(전체, n=9,006). 역사 \|수익\| 상위 8건 중 **4건이 2026년**(07-31 +19.98 · 03-04 −11.94 · 07-28 −11.55 · 06-23 −10.53) | ★**v8.4 lane 설계에 직접 영향** — ⓐ비대칭을 재려는 바로 그 시기에 시장이 실제로 비대칭적으로 움직이고 있다(표적 타당성 ↑) ⓑ **최근 구간이 판정을 지배할 위험**(시대-분해 병기 의무) |

우리 매크로 자산 (전부 기존 보유):

| 패널 | 규모 | 기간 | 내용 |
|---|---|---|---|
| `.cache/fred_macro_wide.parquet` | 8,238행 · **23계열** | 2000-01-01 ~ 2026-08-06 (⚠파생 정체) | VIX · HY_Spread · BBB_Spread · Term_Spread · Breakeven_5Y/Infl · Chi_Fin_Cond · StL_Fin_Stress · Init_Claims · UMich_Sentiment · US_2Y/10Y · US_CPI · US_M2 · US_IndProd · US_Unemployment · Fed_Funds/BalSheet · Bank_Lending_Std · Housing_Permits · Copper_Price · SP500 · KRW_USD |
| `.cache/regime_daily_v2.parquet` | 8,242행 · 22열 | 2000-01-01 ~ 2026-08-12 | MRS + exposure + n_axes_firing + **9축 z-smooth**(VIX/HY/TS/BBB/KRW/FinStress/NFCI/Claims/Sentiment) |
| `.cache/ecos_bond_rates.parquet` | 37,315행 | 2001-01-01 ~ 2026-08-12 | 국내 금리 계열(long) |
| `.cache/ecos_krw_usd.parquet` · `macro_regime` · `indices` | — | — | 환율 · 매크로 국면 · 지수 |

- 후보 질문: **매크로 상태가 비대칭의 크기·부호를 조건짓는가** — 예: 신용스프레드 확대 구간에서 분위 프로파일이 단조→역전으로 뒤집히는가 · 꼬리초과확률의 예측력이 유동성 국면에 조건부인가 · 금리·환율 충격 후 횡단면 왜도가 이동하는가
- 매크로를 **알파로 쓰는 게 아니라 조건변수로 쓴다** — 매크로 타이밍(레짐 스위칭 배분)은 이미 여러 차례 negative 이고, 이 lane 은 **횡단면 비대칭의 조건부성**을 묻는다(층이 다르다)
- ⚠**함정 3종 (전부 실측 전례 있음)**:
  ① **매크로는 미국 시간대·발표 시차**가 있다 — PIT C11(FRED 시차) HARD. 발표일 기준이지 관측월 기준이 아니다
  ② **국면 라벨 자격 관문**(`label_eligibility()`)을 통과하지 못한 라벨로 소비면을 측정하지 말 것 — 판별력 없는 라벨은 중립이 아니라 발화 월수에 비례해 유해. ★단 그 관문 자체가 현재 p 단독이라 n-구동이다([[project-label-gate-is-p-only-so-verdict-is-n-driven-20260813]], 도훈 결정 대기) — **연속 상태변수로 쓰면 이 문제를 우회**한다(이분 라벨화가 유효표본을 에피소드 수로 붕괴시키는 것도 함께 회피)
  ③ **국면-조건부로 쪼개면 구속하는 것은 개월수가 아니라 에피소드 수** — 46개월이 블록 4개면 유효표본 ≈4([[project-episode-count-not-month-count-binds-20260809]]). 분할 **전에** `required_effect_size.R`

### Lane C — 수리통계 구조 추정 (비-ML 축)
ML 없이도 비대칭을 잡는 정통 통계 축. Lane A 의 **음성 대조이자 보완**이다.
- 후보: 조건부 분위회귀 · copula 기반 꼬리의존 · 극단값이론(EVT/GPD) 꼬리지수 · 상태전환(regime-switching) 모수 · 로버스트 적률(윈저화·MAD 기반)
- ⇒ ML 이 이기는지 **정통 통계 대비**로 판정한다. "ML 이라서 좋다"는 주장을 원천 차단.

---

## §6 실패 방화벽 — 과거 126건을 반복하지 않기 위한 금지 4종

INV-7 정합: 아래는 **구조 판결이 아니라 경로-scoped 금지**다. 부활 조건을 각각 명시한다.

1. **ML 을 결합기로 쓰는 라운드 금지.** 앙상블·스태킹·투표·전략가중은 §2 ①에서 같은 점으로 수렴했다. *부활*: 결합 대상이 **새 lane 산출물**이고 개별 arm 이 먼저 PORT_t 를 통과했을 때만.
2. **ML 사이징·selection 금지.** DPL(06-26) · uncertainty(07-05 2세션) settled-negative. *부활*: INV-7 부활신호 발화 시.
3. **표적이 "다음 달 평균 수익률"인 ML 라운드 금지** — 그건 §2 ③이고 SR ~0.49 로 이미 값이 찍혔다. 평균 표적은 **대조군으로만** 등장한다.
4. **sweep 은 DSR 게이트 필수.** ML HPO·모델 grid 는 `selection_type="sweep"` 이며 DSR ≥ 0.5 HARD 가 붙는다. 가설주도 순차개선(chain)으로 위장 금지 — chain 자격요건 3항(변경사유 기록 · **iteration 선택은 IS-only** · holdout 최종 1회) 전부 충족해야 chain 이다.

---

## §7 판정 규약 (불변 승계 + 이 lane 고유 추가)

**불변 (v8.3 승계)**: graduation HARD 3종 = PORT_t ≥ 2.95(forge-authoritative NW lag-3) · oos_retention ≥ 0.7(v2 3분할 중앙값) · calmar ≥ 0.64. admission = book-marginal ΔIR ≥ 0.05. cap-w 판정 권위 + dual-basis 진단 의무. governor 수동.

**이 lane 고유 추가 (전부 착수 전 사전등록)**:
- **①비대칭 주장은 basis 를 병기한다.** 평균-basis 와 분위/중앙값-basis 는 **부호가 갈릴 수 있다**(§3 실측 −5.10 vs +12.01). 한 문장에 둘을 섞지 않는다.
- **②EW-basis 는 t 배율기다** — se 비율 0.729 ⇒ **×1.371 부호무관 배율**. cap-w 판정 불변, EW 는 진단으로만([[project-ew-basis-is-a-t-magnifier-not-handicap-removal-20260809]]).
- **③적률 기반 통계량은 `moment_fragility.R` 경유** — 스케일 불변이 이상치 강건을 뜻하지 않는다. 왜도·첨도를 표적으로 쓰는 lane 이므로 이 계약은 선택이 아니라 필수.
- **④검정력을 착수 전에 계산** — `required_effect_size.R`. 국면-조건부로 쪼개면 구속하는 것은 개월수가 아니라 **에피소드 수**다.
- **⑤대조군은 base 가 아니라 동일강도 무작위.** 그리고 **양성 대조를 보존**한다(규칙을 바꿨더니 양성이 t 0.776 이 된 전례).
- **⑥소비면 7종 순회 의무** — 재료가 능력을 확립하면 ①팩터 랭킹 ②유니버스 필터 ③오버레이/국면 입력 ④위험모델·β예산 ⑤monitoring ⑥선별 라벨 ⑦타 모드 이식. **소비 경로가 판정을 바꾼다**는 것은 실증된 사실이다(MAX5: 랭킹 죽음 → 필터 ΔIR +0.169 · FQ-168: 유니버스 유효 → PG2 내부 부호 반대).

---

## §8 첫 라운드 (R1) 착수 조건

**질문**: 같은 피처·같은 유니버스·같은 비용에서 **예측 표적을 평균 → 분포로 바꾸는 것만으로** 횡단면 신호력이 개선되는가.

**설계 골격** (사전등록 문서는 라운드 착수 시 별도 발행):
- arm A(대조): 월간 평균-표적 (기존 §2 ③ 재현 — SR ~0.49 가 나와야 재현 성립)
- arm B: 조건부 분위 표적 (q10 / q50 / q90 pinball)
- arm C: 조건부 왜도·꼬리초과확률 표적
- 유니버스 K200∪KQ150 · 2005~ · top-25 EW · 15bps · cap-w 1급 + EW-uni 진단 병기
- 1급 결과량 = **canonical PORT_t** (rank-IC 는 advisory)

**착수 전 필수 확인 (라운드 설계를 바꾼 전례가 있음)**:
1. arm A 재현이 실제로 SR ~0.49 를 내는가 — 안 나오면 **비교 기준선이 없다**
2. 검정력 사전 계산 — 3 arm 은 sweep 인가 chain 인가(DSR 적용 여부가 갈린다)
3. PIT — 월내 피처 도입 시 홀딩월 시작 전 컷오프 · lag1 스트레스
4. in-flight 중복 — 배분 **전에** 큐를 훑는다

---

## §9 이 문서가 바꾸는 것 / 안 바꾸는 것

**바꾼다**: 주력 레인(비-return → 비대칭 ML/수리통계) · 세션 기본 자원 배분 방향 · 프론티어 큐 우선순위.

**안 바꾼다**: Production Constraints 7종 + PIT C1~C15(AX-000 따름정리 — 제약은 문제의 고정 축이지 레버가 아니다) · graduation HARD 3종 · cap-w 권위 · 6-agent 구조 · governor 수동 · 정직 라벨(`metric_type`) · 실측-only 거버넌스.

관련 SOT: `qvest_v8_3_alpha_discovery_sot.md`(골격 승계) · `qvest_v8_1_sot.md` · `qvest_ast_v1_1_sot.md` · rules `measurement-graduation.md` · `axiom-engine.md`(INV-7) · `python-policy.md`(ML 은 venv `qvest_ml`, 계약은 R 브릿지 경유)
