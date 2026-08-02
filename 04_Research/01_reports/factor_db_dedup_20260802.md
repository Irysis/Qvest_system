# Factor DB 중복 팩터 전수 스캔 + registry de-dup

**작성**: 2026-08-02 · **계기**: WT-D20260802_003 risk 라운드 적발 (`D01_IdioVol ~ R12_Idiosyncratic_Risk` active-cor = 1.0000 → Ω rank 결핍으로 팩터 공분산 추정 전소, 2팩터 drop 후 재추정)
**metric_type**: `signal_zscore_cross_section` (Pearson) / `signal_rank` (Spearman 등가) / `deploy_active_series` — 전부 실측. proxy 없음.
**substrate**: 월간 factor DB, `load_month_factors()` 경유 (C15 준수, parquet 직접 read 0건) · `factor_db build_hash = 20260801204055_707d464b`
**기간**: 2005-01-31 ~ 2026-06-30, **258개월** (중복·결측 월 0 — 스크립트 내 `stopifnot` 강제)

---

## 0. 한 문단 요약

WT-003 이 보고한 1쌍은 **개별 사고가 아니라 계통**이었다. approved 102 팩터에서 **EXACT 중복 10쌍(rank basis 12쌍) / NEAR 8쌍(11쌍)**, 전체 registry 373 에서 **EXACT 59쌍 / NEAR 75쌍**이 실측됐다. 그중 7쌍은 소스코드에서 **같은 값을 두 번 계산하거나 한쪽을 다른 쪽에 리터럴 대입**한 것으로 계보가 확정됐다 (`R12_Idiosyncratic_Risk <- D01_IdioVol` 등). WT-003 의 ICIR top-20 풀은 이 때문에 **20슬롯 중 3개가 여분**(유효 폭 17)이었고, 변동성 잔차 하나가 EW 합성에서 **20% 비중**(정상 5%)을 차지했다. registry 에는 삭제·리넘버 없이 `dedup` 블록(canonical/alias/redundant, 44 클러스터 127 팩터)을 적재하고, 라벨이 실제로 소비되도록 `resolve_factor_canonical()` / `drop_alias_factors()` / `report_redundant_clusters()` 를 배선했다.

**중복을 쫓다 더 큰 걸 밟았다**: `V13_EV_Sales` 의 EV 항이 **값에 아무 영향을 못 주고 있다**(원천 재구성 시 cor 0.90 이어야 하는데 저장값은 1.000000). `V16_Tobins_Q` 의 `+TotalLiab` 항도 같은 증상이다. 중복보다 이쪽이 크다 — §3.1, 후속 큐 §7-1.

---

## 1. WT-003 적발 재현 (독립 계산)

WT-003 스크립트를 재실행하지 않고, 같은 패널에서 독립적으로 재측정했다.

| 쌍 | deploy basis (r6 active) | signal basis (median, 258mo) | WT-003 보고값 |
|---|---|---|---|
| `D01_IdioVol ~ R12_Idiosyncratic_Risk` | **+1.0000** (n=256) | **+1.0000** (n=258) | 1.0000 ✅ 일치 |
| `D01_IdioVol ~ D22_Tracking_Error` | +0.9791 (n=256) | +0.9984 (n=258) | 0.996 △ |
| `R12_Idiosyncratic_Risk ~ D22_Tracking_Error` | +0.9791 (n=256) | +0.9984 (n=258) | 0.996 △ |

`D22` 의 0.996 은 **basis 차이**다. WT-003 은 공선성 제거 단계에서 `pooled 60m z-cor > 0.97` 기준을 썼고(`run_wt003_risk.R:171-174`), 나는 전기간(258mo) median 을 signal/deploy 두 basis 로 쟀다. 세 수치 모두 근사-중복 판정에는 동일한 결론 — 실질 일치.

`D01 ~ R12` 는 상관이 아니라 **동일성**이다: `Z_Score_Aligned` 가 258/258 개월 전 종목에서 bit-identical (maxdiff = 0.000e+00).

---

## 2. 전수 스캔 결과

스캐너: `02_Infrastructure/factor_db/factor_dup_scan.R` · 실행: `04_Research/01_reports/run_factor_dup_scan_20260802.R`

| 범위 | basis | EXACT (\|med cor\| ≥ 0.99) | NEAR (≥ 0.95) |
|---|---|---|---|
| **approved 102** (의무 범위) | signal (Pearson-Z) | **10쌍** | **8쌍** |
| **approved 102** | signal (**rank**) | **12쌍** | **11쌍** |
| approved 102 | deploy (active 수익) | 10쌍 | 24쌍 |
| registry 373 (전체) | signal (Pearson-Z) | **59쌍** | 75쌍 |

세 basis 는 서로 다른 질문이다 — **signal** = 신호가 같은가(de-dup 판정 근거), **rank** = 선별이 소비하는 순위가 같은가(가장 넓은 기준), **deploy** = 배포 포트가 같은가. Pearson ∪ rank = **140쌍 / 44 클러스터**가 registry 처리 대상(§5.3).

### 2.1 approved 102 — signal basis (의무 산출)

| verdict | A | B | median cor | \|med\| | n | min | max | 부호역전 |
|---|---|---|---|---|---|---|---|---|
| EXACT | `M11_ST_Reversal` | `M29_Mom_5d` | +1.0000 | 1.0000 | 258 | +1.000 | +1.000 | 0 |
| EXACT | `D01_IdioVol` | `R12_Idiosyncratic_Risk` | +1.0000 | 1.0000 | 258 | +1.000 | +1.000 | 0 |
| EXACT | `Q31_WC_to_Assets` | `XF_LL05_WorkingCapital` | +1.0000 | 1.0000 | 258 | **−0.184** | +1.000 | **12** |
| EXACT | `V08_PSR` | `V13_EV_Sales` | +1.0000 | 1.0000 | 258 | +1.000 | +1.000 | 0 |
| EXACT | `CR04_Ownership_Concentration` | `L02_Turnover` | +1.0000 | 1.0000 | 258 | +0.998 | +1.000 | 0 |
| EXACT | `C02_EPS_Chg_1m` | `M27_Analyst_Rev_Mom` | +0.9992 | 0.9992 | 258 | +0.991 | +1.000 | 0 |
| EXACT | `R17_Market_Leverage` | `V19_Debt_to_Market` | +0.9989 | 0.9989 | 258 | +0.988 | +1.000 | 0 |
| EXACT | `D01_IdioVol` | `D22_Tracking_Error` | +0.9984 | 0.9984 | 258 | +0.970 | +1.000 | 0 |
| EXACT | `D22_Tracking_Error` | `R12_Idiosyncratic_Risk` | +0.9984 | 0.9984 | 258 | +0.970 | +1.000 | 0 |
| EXACT | `C01_SUE` | `C05_ESCR` | +0.9904 | 0.9904 | 258 | +0.981 | +0.995 | 0 |
| NEAR | `Q14_Current_Ratio` | `XF_LL04_QuickRatio` | +0.9746 | 0.9749 | 258 | **−0.975** | +0.988 | **10** |
| NEAR | `D53_Range_Vol` | `L18_Eff_Spread_Proxy` | +0.9708 | 0.9708 | 258 | +0.067 | +0.986 | 0 |
| NEAR | `L13_Vol_Variance_Ratio` | `L31_Vol_Concentration` | +0.9637 | 0.9637 | 258 | +0.888 | +0.990 | 0 |
| NEAR | `D16_Coskewness` | `R09_Coskewness` | +0.9568 | 0.9568 | 258 | +0.783 | +0.999 | 0 |
| NEAR | `L01_Amihud` | `L25_Amihud_Vol` | +0.9531 | 0.9531 | 258 | +0.694 | +0.997 | 0 |
| NEAR | `D01_IdioVol` | `D56_Up_Vol` | +0.9519 | 0.9519 | 258 | +0.886 | +0.995 | 0 |
| NEAR | `D56_Up_Vol` | `R12_Idiosyncratic_Risk` | +0.9519 | 0.9519 | 258 | +0.886 | +0.995 | 0 |
| NEAR | `D22_Tracking_Error` | `D56_Up_Vol` | +0.9515 | 0.9515 | 258 | +0.868 | +0.995 | 0 |

**부수 적발 2건** (중복과 별개 결함):
- `Q31 ~ XF_LL05`: 정의문이 **글자 그대로 동일**한데 12개월에서 부호가 역전(min −0.184). DART-네이티브와 xlsx 트윈이 특정 월에 서로 다른 값을 준다 = **소스 혼합**.
- `Q14 ~ XF_LL04`: 258개월 중 10개월에서 **정렬 후** 부호 역전(min −0.975). 정의는 실제로 다르므로(재고 포함/제외) 중복이 아니라, **C13 IC-기반 방향추론이 이 쌍에서 불안정**하다는 신호.

### 2.2 deploy basis 가 드러낸 signal basis 의 사각지대

deploy basis(배포존 top-25 EW 포트의 active 수익)에서 signal basis 가 놓친 쌍이 나왔다:

| 쌍 | deploy cor | Pearson-Z signal | 이유 |
|---|---|---|---|
| `V13_EV_Sales ~ V20_SP` | **+1.0000** | < 0.95 (미적발) | `V20_SP = Revenue/MarketCap` 은 `V08_PSR = MarketCap/Revenue` 의 **역수** — Pearson 은 1이 아니지만 **순위가 동일**해 top-N 선별에서 같은 포트를 만든다 |
| `V16_Tobins_Q ~ V18_AM` | **+1.0000** | < 0.95 (미적발) | 동일 기전(단조변환) |

→ 이것은 내 스캐너의 결함이었다. `scan_signal_dup(rank_transform = TRUE)` 를 추가해 rank basis 를 별도 실측했다(§2.3). **선별이 실제로 소비하는 정보는 순위**이므로 rank basis 가 de-dup 판정의 더 보수적인(넓은) 기준이다.

### 2.3 rank basis 보완 스캔 (approved 102)

`run_factor_dup_scan_rank_20260802.R` · 258개월 · 18.3분 · 97 후보쌍

**rank basis: EXACT 12 / NEAR 11** (Pearson 10 / 8 보다 넓다). **6쌍이 rank 에서만 잡혔다**:

| verdict | 쌍 | rank median cor | Pearson-Z | 기전 |
|---|---|---|---|---|
| EXACT | `V13_EV_Sales ~ V20_SP` | **+1.0000** | 미적발 | 역수 |
| EXACT | `V08_PSR ~ V20_SP` | **+1.0000** | 미적발 | `V20 = Revenue/MarketCap` = `1 / V08` — **구성상 역수** |
| EXACT | `V16_Tobins_Q ~ V18_AM` | **+1.0000** | 미적발 | §3.1 — `+TotalLiab` 항 무력화 의심 |
| NEAR | `M01_Mom_12_1 ~ M13_VolAdj_Mom` | +0.9673 | 미적발 | vol 스케일링이 순위를 거의 안 바꿈 |
| NEAR | `L01_Amihud ~ L11_Kyle_Lambda` | +0.9666 | 미적발 | 유동성 비유동성 척도 |
| NEAR | `Q14_Current_Ratio ~ Q31_WC_to_Assets` | +0.9562 (min −0.963) | 미적발 | 방향추론 불안정 동반 |

또 `CR04~L02`·`R17~V19`·`C02~M27` 는 rank 에서 **정확히 1.0000** 으로 올라간다(Pearson 0.9989~0.9992) — 잔차가 표준화 잡음이었음을 확인.

→ **de-dup 판정은 두 basis 의 합집합**으로 한다(§5.3).

### 2.4 registry 전체 (373) — EXACT 59쌍

approved 밖에도 같은 계통이 넓게 깔려 있다 (전량 median cor 258개월):

- **베타 5중복**: `D02_Beta = D10_Blume_Adj_Beta = D31_Relative_Beta = MK01_CAPM_Beta = D11_FP_Beta` (전부 +1.0000)
- **발생액 4중복**: `AC01_Total_Accruals_CF = AC11_Accruals_to_Assets = AC18_Accrual_Quality = Q05_Accrual` (+1.0000)
- **규모 2중복**: `L26_Log_MktCap = S01_Size` (+1.0000), `S02_Float_Size` (+0.9986)
- **성장 xlsx 트윈**: `Q34_GP_Growth = XF_GD01_GrossProfit_Growth`, `GR06_OCF_Growth = XF_GD03_OCF_Growth`, `Q12_Asset_Turnover = XF_DU02_AssetTurnover` (전부 +1.0000)
- **VaR/CVaR 트윈**: `D47_CVaR_5pct = R03_CVaR_95` (+1.0000), `D48/D49 ~ R01/R02` (+0.9999)
- **approved 를 건드리는 것 5쌍**: `CR11_Idiosyncratic_Return ~ D24_Systematic_Risk_Prop`, `~ R11_Systematic_Risk` (+1.0000), `D53_Range_Vol ~ L41_Intraday_Vol_Proxy` (+0.9996), `D01_IdioVol ~ D03_RealVol` (+0.9968), `D03_RealVol ~ D22_Tracking_Error` (+0.9929)

전체 목록: `factor_dup_signal_pairs_20260802.parquet` (820 후보쌍 전수 통계) · 클러스터: `factor_dup_clusters_20260802.csv`

---

## 3. 계보 — 왜 중복이 생겼는가

소스코드까지 추적한 6쌍. **전부 "다른 데이터로 비슷한 걸 만들었다"가 아니라 "같은 계산을 두 번 등록했다"** 이다.

| # | 쌍 | 기전 (파일:라인) |
|---|---|---|
| 1 | `R12_Idiosyncratic_Risk` = `D01_IdioVol` | `factor_db_daily_phase6.R:286` — `R12_Idiosyncratic_Risk <- D01_IdioVol` **리터럴 대입**. 월간 경로도 같은 양: `compute_risk.R:126` `r12 = -sd(fit$residuals)` vs `compute_defense.R:69` D01 = CAPM 잔차 표준편차(252d). |
| 2 | `M29_Mom_5d` = `M11_ST_Reversal` | 같은 수식이 `compute_momentum.R` 안에 **두 번** — `:186` `m11 = prod(1+rets[(n-4):n])-1`, `:430` `M29 = prod(1+Ret[(n-4):n])-1`. 일간은 더 노골적: `factor_db_daily_phase6.R:144` `M11 <- cr5`, `:168` `M29 <- cr5` (같은 변수). ⚠ registry 방향 사전이 **서로 반대**(`lower_better` vs `higher_better`)인데 값은 동일. |
| 3 | `CR04_Ownership_Concentration` = `L02_Turnover` | `compute_crowding.R:155-172` = 20일 평균 회전율 `mean(Vol/est_shares)`, `compute_liquidity.R:57-74` L02 와 같은 양. 일간도 동일(`phase7.R:170` vs `phase6.R:245` 둘 다 `roll_mean_cpp(turn, 20L)`). ⚠ CR04 는 정의문이 *"Turnover Ratio inverse / low turnover = crowded"* 인데 **저장값은 회전율 그 자체** — 명명이 값과 반대. |
| 4 | `XF_LL05_WorkingCapital` = `Q31_WC_to_Assets` | 정의문 동일 `(CurrentAssets − CurrentLiab)/TotalAssets`. `data_source` 만 다름(DART vs xlsx). 소스 혼합으로 12개월 발산. |
| 5 | `M27_Analyst_Rev_Mom` = `C02_EPS_Chg_1m` | M27 registry 정의문이 그대로 `"eps_chg_1m. 1-month EPS revision (latest)."` — 같은 필드를 momentum 카테고리에 재등록. |
| 6 | `V19_Debt_to_Market` = `R17_Market_Leverage` | 동일 수식 `TotalDebt/MarketCap` (부호 반대). 일간은 **문자 그대로 같은 식이 두 phase 에** — `phase6.R:492` `R17 = safe_div(TotalDebt, Size)`, `phase8.R:194` `V19 := safe_div(TotalDebt, Size)`. 커버리지만 차이(V19 는 `TotalDebt>0` 게이트로 2026-06 기준 1900 vs R17 2130). |

**구성이 다른데 실측만 겹친 경우** (= 병합이 아니라 수리 대상):

| 쌍 | 실측 | 진단 |
|---|---|---|
| `V08_PSR ~ V13_EV_Sales` | median 1.0000 (258/258) — 단 **bit-identical 아님**(maxdiff ~1e-2) | **EV 항이 무력하다** — §3.1 참조. alias 가 아니라 **수리 대상**. |
| `C01_SUE ~ C05_ESCR` | median 0.9904 | 정의는 실제로 다르다(어닝 서프라이즈 vs 리비전 일관성). 승인 게이트 통계도 크게 다름(ic_ir 0.2228 vs 0.1074). **경험적 중복이지 구성적 중복이 아님** → 자동 병합 금지. |
| 변동성 잔차군 `D01 / D22 / D56` | 0.95~0.998 | `D01`=CAPM 잔차 std(추정 β), `D22`=시장상대 잔차 std(단위 β), `D56`=상승일 vol. 회귀가 달라 구성은 구별되나 KR 횡단면에서 사실상 한 신호. |

### 3.1 부수 적발 — EV 기반 팩터의 EV 항이 무력하다 (별건, 중복보다 큼)

`V13_EV_Sales` 를 alias 로 접으려다 기전을 재려고 원천에서 EV 를 직접 재구성했더니 **처음 세운 가설이 틀렸다**. 기록해 둔다.

원천 재구성 (2026-06-30, `fundamental_merged.parquet` + `RAWDATA.parquet::Size`, 2,582 종목):

| 항목 | 실측 |
|---|---|
| `TotalDebt == 0` (부채 항목 전부 결측) | 241 / 2,582 = **9.3%** |
| `Cash == 0` | 0 / 2,582 = **0.0%** |
| `NetDebt == 0` (즉 EV == MarketCap 이 되는 종목) | **0 / 2,582 = 0.0%** |
| `\|NetDebt\| / MarketCap` 중앙값 | **0.266** (75%p 1.133, 90%p 11.15) |
| `cor(MarketCap/Rev, EV/Rev)` Pearson | **0.900** |
| `cor(MarketCap/Rev, EV/Rev)` Spearman | **0.753** |

즉 **순부채는 실재하고 크다**. EV 를 제대로 넣으면 두 팩터의 상관은 0.90(순위 0.75)이어야 한다. 그런데 factor DB 에 저장된 `V13` 은 `V08` 과 **258/258 개월 cor = 1.000000** 이다.

→ **저장된 `V13_EV_Sales` 는 실질적으로 `MarketCap/Revenue` 다. EV 항이 값에 영향을 주지 못하고 있다.** (Z 가 bit-identical 이 아닌 것은 커버리지가 4종목 다르기 때문 — 표준화 모집단이 달라 상수 offset 이 생기지만 affine 관계라 Pearson 은 1.000000.)

기전 후보 (미확정): `compute_value.R:96-101` 이 `fund_cols_needed` 에 없는 컬럼을 `NA_real_` 로 채우고, `:109-111` 이 그 NA 를 **0으로 대체**한다 — `fund_wide` 에 `ShortTermBorr`/`LongTermBorr`/`CashAndEquiv` 가 도달하지 않으면 `TotalDebt=0, Cash=0` → `EV = MarketCap` 이 된다. 컬럼 목록 자체에는 세 항목이 들어 있으므로(`:98-99`), 끊기는 지점은 builder 가 모듈에 넘기는 `FUND` 사전필터(`factor_db_builder.R:747` 부근)로 의심되나 **확정하지 않았다**.

**영향 범위 (미측정)**: 같은 `EV` 변수를 쓰는 `V07_EV_EBITDA` · `V14_EBIT_EV` · `V22_FCFF_EV` 가 동일 결함을 공유할 수 있다. 실제로 deploy basis 에서 `V07_EV_EBITDA ~ V14_EBIT_EV` = +0.9796, `V10_FCF_Yield ~ V22_FCFF_EV` = **+1.0000**(registry-wide) 이 관측된다 — 정황은 일치하나 **본 라운드에서 확정하지 않았다**. §7-1 로 큐잉.

이것이 `V13` 을 alias 로 접지 않은 이유다: 접으면 팩터 하나가 사라지는 게 아니라 **결함이 라벨 뒤로 사라진다**.

---

## 4. 선별 통계 오염 — 실측

`run_dedup_selection_impact_20260802.R` · 원장 = WT-003 저장 ICIR (anchor 2026-01-31, 102 후보, top-20)

**정직한 범위 제한**: 아래는 **선별 부기(bookkeeping) 재계산**이지 수익 재측정이 아니다 (`metric_type = selection_bookkeeping`). WT-003 의 동결 산출물은 읽기만 했다.

### 4.1 이중 승인 — 게이트 통계가 문자 그대로 같다

`approved_factor_library.parquet` 에서 두 팩터가 **동일한 통계로 각각 approved** 되었다:

| 쌍 | rank_ic_ir | portfolio_alpha_t_nw | net_sr |
|---|---|---|---|
| `M11_ST_Reversal` / `M29_Mom_5d` | 0.3291 / **0.3291** | −0.959 / **−0.959** | −0.378 / −0.378 |
| `D01_IdioVol` / `R12_Idiosyncratic_Risk` | 0.1640 / **0.1640** | −1.258 / **−1.258** | −0.455 / −0.455 |

승인 게이트는 팩터를 **개별로** 심사하므로 같은 신호가 두 번 통과하는 것을 막을 장치가 없었다. 102 라는 approved 모집단 자체가 실제로는 **더 좁다**.

### 4.2 풀 점유 — 20슬롯 중 3~4개가 여분

WT-003 ICIR top-20 실측:

| 클러스터 | 풀 안 멤버 | 여분 슬롯 | ICIR |
|---|---|---|---|
| `{C01_SUE, C05_ESCR}` | 2 | 1 | 0.743887 / 0.418281 |
| `{D01_IdioVol, D22_Tracking_Error, R12_Idiosyncratic_Risk}` | 3 | 2 | 0.360823 / 0.365602 / **0.360823** |
| (+ NEAR 포함 시 `D56_Up_Vol` 추가) | 4 | 3 | +0.360258 |

- **EXACT 기준: 여분 3 / 20 → 유효 폭 17**
- **EXACT+NEAR 기준: 여분 4 / 20 → 유효 폭 16**
- `D01` 과 `R12` 의 ICIR 은 소수점 6자리까지 동일(0.360823) — 이중 투표의 직접 증거.

### 4.3 EW 합성에서의 실효 비중

`base_icir_EW` 는 팩터 EW(각 5%)다. 중복 때문에:

| 클러스터 | 실제 비중 | de-dup 후 |
|---|---|---|
| 변동성 잔차 `{D01, D22, D56, R12}` | **20.0%** (4/20) | 5.0% |
| 어닝 `{C01_SUE, C05_ESCR}` | 10.0% (2/20) | 5.0% |

하나의 변동성 신호가 합성 알파의 1/5 를 차지했다.

### 4.4 붕괴 후 재선별 — 풀이 실제로 바뀐다

동일 선별 규율(trailing 36m ICIR top-20)에 중복만 접고 재선별:

| 기준 | 들어옴 | 나감 | Jaccard |
|---|---|---|---|
| EXACT | `L16_Turnover_Vol`, `L14_Price_Impact`, `R09_Coskewness` | `C05_ESCR`, `D01_IdioVol`, `R12_Idiosyncratic_Risk` | 0.739 |
| EXACT+NEAR | + `D05_MaxRet` | + `D56_Up_Vol` | 0.667 |

### 4.5 과거 라운드가 뒤집혔는가 — 판정

**과거 A/B 판정 자체는 뒤집히지 않는다. 다만 "왜 천장이었나"의 해석은 바뀐다.**

- **뒤집히지 않는 이유**: WT-003 은 *동일 풀을 공유한 가중치 A/B*(paired) 다. 중복은 base 와 W_portt 양 arm 에 **똑같이** 들어가므로 paired t (=2.569) 는 중복에 대해 1차적으로 불변이다. R6~R15 계보의 PORT_t-정렬 선별 역시 같은 substrate 를 공유한다.
- **그러나 바뀌는 것**:
  1. **유효 폭 과대보고**. "20팩터 풀"·"102 approved" 는 각각 17·(그보다 작은 수)로 읽어야 한다. 분산효과·`n_eff` 를 20 기준으로 인용한 서술은 과대다.
  2. **Ω 추정 실패의 원인이 확정**. WT-003 이 겪은 rank 결핍은 추정기 선택 문제가 아니라 **입력 중복**이었다. 같은 substrate 를 쓰는 후속 라운드는 de-dup 없이는 같은 자리에서 다시 막힌다.
  3. **가중 실험의 해석**. `theta ∝ ICIR` 은 중복 신호에 2× 비중을 준다 — W_icir arm 의 성격이 설계 의도와 달랐다. 대조군이라 채택 후보는 아니었으나, 이 arm 을 근거로 한 서술은 재검토가 필요하다.
- **정량 한계 (명시)**: 위 재선별은 **anchor 2026-01-31 1개 시점**에서만 계산했다. WT-003 은 cadence 6m 다중 anchor 이며, 시점별 풀은 저장돼 있지 않다. 전 anchor 영향 추정은 WT 재실행이 필요하고 그것은 동결 산출물 범위 밖이다 — **미측정으로 남긴다**.

---

## 5. registry de-dup 처리

**삭제 0건 · 리넘버 0건.** 코드는 안정 식별자다([[reference-code-identity-stability]]) — 기존 이름 조회는 전부 계속 유효하다.

### 5.1 왜 `lifecycle.status = "deprecated"` 로 하지 않았나

실측: `lifecycle.status` 를 **읽는 코드가 저장소에 없다** (writer 는 `factor_research_pipeline.R:417` 하나뿐, reader 0건). 여기에 `"deprecated"` 를 쓰면 **라벨만 바뀌고 이중 투표는 그대로** 남는다 — 이 저장소가 반복해서 밟은 "존재/라벨 검사로 행동 검사를 대체" 계통이다. 그래서 별도 `dedup` 블록을 만들고 **소비 함수를 함께** 배선했다.

### 5.2 스키마

```json
"R12_Idiosyncratic_Risk": {
  "...": "기존 필드 전부 불변",
  "dedup": {
    "role": "alias",
    "canonical": "D01_IdioVol",
    "cluster": "DUPC-0NN",
    "deprecated_for_selection": true,
    "adjudicated": true,
    "mechanism": "factor_db_daily_phase6.R:286 R12 <- D01_IdioVol (리터럴 복사) ...",
    "reason": "D01 = evidence_tier A + 원본.",
    "evidence": { "median_abs_cor": 1.0, "n_months": 258, "basis": "...", "report": "..." },
    "consumption_rule": "선별/Ω 추정에서는 canonical 만. 코드 조회는 계속 유효."
  }
}
```

**role 3종**:

| role | 의미 | 자동 처리 |
|---|---|---|
| `canonical` | 그 정보의 정본. `aliases[]` 역참조 보유 | 유지 |
| `alias` | **구성상 같은 양**. 접어도 정보 손실 0 | `drop_alias_factors()` 가 제거 |
| `redundant` | 구성은 다른데 실측이 겹침 | **자동 병합 금지** — `report_redundant_clusters()` 가 보고만, 선언은 사람 |

`redundant` 를 따로 둔 이유: `V08_PSR ~ V13_EV_Sales` 를 alias 로 접으면 EV 항 결함이 라벨 뒤로 사라진다. `C01_SUE ~ C05_ESCR` 은 정의가 실제로 다르다. **계보로 동일성이 증명된 것만 alias** 로 한다(`adjudicated: true`); 계보 미추적분은 `needs_review: true`.

### 5.3 적용 결과

`02_Infrastructure/factor_db/apply_factor_dedup.R` (Pearson ∪ rank = 140쌍 → **44 클러스터 / 127 팩터**)

```
[dedup] duplicate pairs (union of bases): 140
[dedup] clusters: 44
[dedup] blocks: 127  (alias 7 / canonical 7 / redundant 113)
```

**alias 7건 (계보 확정 — `adjudicated: true`)**

| alias | → canonical | 근거 |
|---|---|---|
| `R12_Idiosyncratic_Risk` | `D01_IdioVol` | `phase6.R:286` 리터럴 대입 · 258/258 bit-identical |
| `M29_Mom_5d` | `M11_ST_Reversal` | 같은 수식 2회 등록 · 258/258 bit-identical |
| `CR04_Ownership_Concentration` | `L02_Turnover` | 같은 20d 회전율 · rank 1.0000 |
| `XF_LL05_WorkingCapital` | `Q31_WC_to_Assets` | 정의문 동일, xlsx 트윈 |
| `M27_Analyst_Rev_Mom` | `C02_EPS_Chg_1m` | 정의문이 곧 `eps_chg_1m` |
| `V19_Debt_to_Market` | `R17_Market_Leverage` | 같은 식 2 phase 중복 |
| `V20_SP` | `V08_PSR` | 구성상 역수 (rank 1.0000) — **Pearson 만 돌렸으면 놓쳤음** |

**redundant 113건** — 자동 병합하지 않는다. 그중 `adjudicated: true` 는 클러스터 라벨이 붙은 9종(`volatility_residual` / `sales_to_price` / `assets_to_market` / `earnings_surprise` / `liquidity_ratio` / `coskewness` / `range_volatility` / `amihud_illiquidity` / `volume_concentration`); 나머지는 **`needs_review: true`** (대부분 approved 밖 — 베타 5중복·발생액 4중복 등). `needs_review` 는 "아직 계보를 안 봤다"는 정직 라벨이지 판정이 아니다.

**쓰기 안전장치**: 백업(`factor_registry.json.bak_20260802_dedup`) → tmp 기록 → **재파싱해 엔트리 수·키 순서 검증** → atomic rename → 2벌 md5 대조. read→write 왕복이 무손실임은 사전 실측(373/373 deep-equal, 라인 수 동일).

**적용 범위 (정직 표기)**: 이 worktree 에는 registry 사본이 **1벌**뿐이다(`.cache/factor_db` 미설치). 배포 트리에서는 2벌 모두 갱신되며 md5 대조가 hard fail 로 작동한다 — 스크립트가 그 사실을 출력한다.

**소비 실증** (WT-003 실제 풀 20개에 적용):

```
resolve_factor_canonical:  R12_Idiosyncratic_Risk -> D01_IdioVol
                           XF_LL05_WorkingCapital -> Q31_WC_to_Assets
drop_alias_factors:        20 -> 19   (제거분을 출력 — 조용한 축소 없음)
report_redundant_clusters: DUPC-005 {C01_SUE, C05_ESCR}
                           DUPC-010 {D01_IdioVol, D22_Tracking_Error, D56_Up_Vol}
미등록 이름 NOT_A_FACTOR_XYZ -> 그대로 반환 (조회 안 깨짐)
```

⚠ **자동 축소는 20→19 뿐이다.** §4.2 의 "여분 3슬롯"은 EXACT 클러스터 기준 산술이고, 그중 자동으로 접히는 것은 **alias 1건(R12)** 이다. `D22`/`D56` 은 회귀 구성이 실제로 달라 `redundant` 로 두었으므로 **사람이 선언**해야 접힌다 — 설계상 보수적으로 만든 것이지 누락이 아니다.

### 5.4 소비 배선

`02_Infrastructure/factor_db/factor_dup_scan.R`:

```r
resolve_factor_canonical(names)   # alias -> canonical, 미등록 이름은 그대로 (조회 절대 안 깨짐)
drop_alias_factors(names)         # 선별/Ω 입력에서 alias 제거 (제거분을 반드시 출력 — 조용한 축소 금지)
report_redundant_clusters(names)  # 같은 cluster 가 2개 이상 들어오면 보고 (자동 제거 아님)
```

**미배선 지점 (정직 보고)**: 아래는 아직 이 함수들을 호출하지 않는다. 라벨은 적재됐지만 **행동은 호출부를 고쳐야 바뀐다**.

| 소비자 | 위치 | 필요 조치 |
|---|---|---|
| RAMP 승인 라이브러리 생성 | `06_Registry/ramp/approved_factor_library.parquet` 생성기 | 승인 심사 전 `drop_alias_factors()` |
| ICIR/relevance 선별 | WT 라운드 스크립트 (`run_wt*_*.R` 계열) | 풀 확정 전 `drop_alias_factors()` + `report_redundant_clusters()` |
| Ω / 팩터 공분산 | risk 라운드 `Sigma = BΩB' + D` | 입력 팩터 목록에 `drop_alias_factors()` |

→ **후속 태스크로 분리**한다(칩). 본 라운드 범위는 적발·계보·라벨·소비 API·검사기까지.

---

## 6. 검사기 — 위반 주입 + 음성 대조

`08_Tests/hooks/test_factor_dup_scan.R` (배터리 편입 대상)

| # | 검사 | 방식 |
|---|---|---|
| 1 | 완전 중복 검거 | 합성 패널에 `F_EXACT_B := F_EXACT_A` 주입 → EXACT_DUP 나와야 |
| 2 | 근사 중복 검거 | `rho ≈ 0.97` 주입 → NEAR_DUP |
| 3 | **부호 반전 중복** 검거 | `F_MIRROR_B := −F_MIRROR_A` → \|cor\| 기준이 아니면 놓친다 |
| 4 | **판별력** | `rho ≈ 0.80` 대조쌍을 중복으로 부르지 않아야 (문턱 붕괴 검출) |
| 5 | **대조쌍 생존 확인** | screen 을 낮춰 그 쌍을 실제로 등장시키고 median\|cor\| ∈ (0.72, 0.88) 확인 — *픽스처 이름을 오타내도 4번은 통과하므로* |
| 6 | min_obs 게이트 | 공통관측 10개 쌍은 판정 자체를 하지 않아야 |
| 7 | 음성 대조 | 독립 6팩터 패널 → 적발 0건 |
| 8 | 경계값 | 0.9899/0.99/0.9499/0.95/0.9 → NEAR/EXACT/OK/NEAR/OK |
| 9 | registry 계약 | canonical 실재 / alias 체인 금지 / 양방향 역참조 일치 / 적발 쌍 라벨 존재 |
| 10 | 2벌 정합 | `02_Infrastructure` ↔ `.cache` md5 동일 (미설치 트리에선 **SKIP 을 명시 출력** — 결손을 통과로 위장 금지) |

**결과: 11 PASS / 0 FAIL / 1 SKIP** (`run_all_hooks.sh` 배터리 등재 완료)

```
inject_exact_caught            median_abs=1.0000
inject_near_caught             median_abs=0.9675
inject_mirror_caught           median_cor=-1.0000
discriminates_merely_correlated  rho~0.80 -> 미적발
mild_pair_is_alive_and_ok      median_abs=0.8046 verdict=OK
min_obs_gate_blocks_thin_pair  공통관측 10 < 30 -> 배제
negative_control_clean         독립 6팩터 -> 0건
classify_boundaries            NEAR/EXACT/OK/NEAR/OK
dedup_block_present            127 팩터
dedup_block_integrity          canonical 실재 / 체인 없음 / 양방향 일치
incident_pair_labelled         R12_Idiosyncratic_Risk -> D01_IdioVol
SKIP registry_two_copies_identical  (worktree — factor DB 미설치)
```

**검사기가 실제로 잡은 것 2건** (개발 중 자기검출):
1. `role: "redundant"` 도입 시 계약 검사가 `canonical|alias` 만 허용해 5건 FAIL — 스키마 확장이 계약과 어긋난 것을 검사기가 먼저 잡았다. `redundant` 전용 계약(cluster 필수 / partners 비어있지 않음 / partner 실재 / 동일 cluster / needs_review 표기)을 추가해 해소.
2. 4번 대조(rho~0.80)가 처음엔 `NA` 로 통과했는데 — **픽스처 이름을 오타내도 같은 NA 가 나온다**. 5번(대조쌍 생존 확인)을 추가해 그 쌍이 실제로 존재하고 median\|cor\| 0.8046 임을 확인하도록 보강.
3. **등재 ≠ 집계.** 배터리(`run_all_hooks.sh:303-334`)는 각 suite 의 **마지막 유효 요약 JSON 라인**을 파싱해 총계를 낸다. 처음엔 그 줄을 안 냈다 — 목록에 올라가 있어도 `UNREPORTED` 로 빠진다. `{"test":"factor_dup_scan","pass":11,"fail":0,"total":11,"skip":1}` 를 추가하고 배터리와 동일한 방식으로 파싱되는지 확인했다. `skip` 은 `pass` 에 섞지 않는다 — 검사하지 않은 것이 총계에서 통과로 보이면 안 된다.

**SKIP 을 남긴 이유**: worktree 에는 `.cache/factor_db` 가 없다. 여기서 "PASS" 를 찍으면 검사하지 않은 것이 통과로 기록된다 — 그래서 별도 `SKIP` 카운터로 **총계에 보이게** 출력한다(`11 PASS / 0 FAIL / 1 SKIP`). 배포 트리에서 2벌 정합이 실제로 검사된다.

**부수 확인**: `08_Tests/hooks/test_r_portability.R` 12/12 PASS — 신규 R 파일 4종이 이식성 금칙 위반 0건.

---

## 7. 남은 것 (next_probe)

1. **EV 항 수리** — `compute_value.R:155` `EV = MarketCap + TotalDebt − Cash` 가 횡단면에서 `MarketCap` 으로 퇴화하는지 원천 확인. 퇴화가 사실이면 `V07_EV_EBITDA` / `V14_EBIT_EV` / `V22_FCFF_EV` 도 같은 결함을 공유한다(EV 를 쓰는 팩터 전부). **미측정 — 이번 라운드 범위 밖.**
2. **C13 방향추론 불안정** — `Q14 ~ XF_LL04` 10개월, `Q31 ~ XF_LL05` 12개월 부호 역전. IC-기반 `ic_sign` 이 근사-중복 쌍에서 월별로 갈리는 구간의 원인 진단.
3. **소비자 배선** — §5.4 표 3곳.
4. **미판정 클러스터 계보 추적** — `needs_review: true` 인 클러스터(대부분 approved 밖). 베타 5중복·발생액 4중복부터.
5. **승인 게이트에 de-dup 전치** — 개별 심사 구조상 같은 신호가 두 번 통과하는 것을 막는 지점은 승인 *이전*이다.

---

## 부록 — 산출물

| 파일 | 내용 |
|---|---|
| `02_Infrastructure/factor_db/factor_dup_scan.R` | 스캐너 + 소비 API (재사용 코드) |
| `02_Infrastructure/factor_db/apply_factor_dedup.R` | registry writer (2벌 원자적 갱신 + 정합 확인) |
| `04_Research/01_reports/run_factor_dup_scan_20260802.R` | signal+deploy 스캔 실행기 |
| `04_Research/01_reports/run_factor_dup_scan_rank_20260802.R` | rank basis 보완 스캔 |
| `04_Research/01_reports/run_dedup_selection_impact_20260802.R` | 선별 오염 평가 |
| `04_Research/01_reports/factor_dup_signal_pairs_20260802.parquet` | 후보쌍 820 전수 통계 (Pearson) |
| `04_Research/01_reports/factor_dup_rank_pairs_20260802.parquet` | rank basis 통계 |
| `04_Research/01_reports/factor_dup_deploy_pairs_20260802.parquet` | deploy basis 5151쌍 |
| `04_Research/01_reports/factor_dup_clusters_20260802.csv` | 클러스터 ↔ 멤버 ↔ role |
| `04_Research/01_reports/dedup_selection_impact_20260802.json` | 재선별 결과 |
| `08_Tests/hooks/test_factor_dup_scan.R` | 위반 주입 + 음성 대조 검사기 |
