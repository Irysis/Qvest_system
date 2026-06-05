# Plan v0.4.2 Amendment — Rawdata 정합성 확보 + Q-Lead 자체 결정 4건

**Date**: 2026-05-19
**Q-Lead**: Claude Opus 4.7 (1M context)
**Owner**: 도훈
**Status**: S1 진입 — workspace + PIT loader PASS + target build PASS

---

## A. v0.4.1 → v0.4.2 변경점

| Change | 분류 | 출처 |
|---|---|---|
| H7 source 변경: fund_dart QualityScore → **factor_db Q08_Composite_Quality + V12_Composite_Value + sue** | feature 정합 | 도훈 mandate "쓰레기 넣으면 쓰레기" GIGO 정합 |
| FRED 1990-01부터 확장 (VIX 1990-01-02 / DGS10 1990-01-02 / T10Y2Y 1990-01-02 등 17/22 series) | data refresh | Q-Lead 자체 진행 |
| ECOS bond 1990-01부터 확장 (KR_CorpAA 1995-01-03 / KR_Call1D 1995-01-03 / KR_CPI 1990-01) | data refresh | Q-Lead 자체 진행 |
| macro_regime.parquet 재 build (1990-01~2026-05, Macro_Risk_Score 1990-01 cover) | composite | Q-Lead 자체 진행 |
| build_fundamental_derived.R + factor_db Quality 33 + Value 24 family 직접 활용 | infra | 도훈 mandate 정확 |
| Y_onset target build PASS (9.95% balanced prevalence) | target | Q-Lead 자체 실행 |
| PIT loader + unit test 7/7 PASS (S1 첫 gate) | infra | Q-Lead 자체 implement |

## B. 도훈님 mandate 따른 Q-Lead 자체 결정 4건

| Q | 결정 | 근거 |
|---|---|---|
| **Q-J' (Train cover)** | **(나) partial cover + NA imputation** | KRX Open API 2014~ 한계, historical fetch 비효율. H3/H6/H7 1995-1999 결측 → XGBoost native handling |
| **Q-O (H7 representative)** | **(가) Q08_Composite_Quality + V12_Composite_Value + sue** | factor_db Quality 33 + Value 24 family 사전 계산 (2005-05~) + GIGO 정합 |
| **Q-K (fund_dart QualityScore)** | **(나) 폐기** | factor_db Q08으로 대체. fund_dart 2016-03~ Train+Valid 결측, OOS only |
| **Q-N (Train start)** | **(가) 1995-01 retain + NA imputation** | 도훈님 원래 mandate retain. H5 Macro_Risk_Score + State engine + Target + H4 일부 cover |

---

## C. 데이터 확보 최종 매트릭스 (1990 확장 후)

### "모든 데이터 확보 최초 시점" — Plan v0.4.2 정책

| 시점 | "모든" 정의 | 본 plan 정합 |
|---|---|---|
| **2016-03-31** | STRICT (fund_dart QualityScore 포함) | ❌ 폐기 (Q-K) |
| **2010-01-04** | Plan v0.4.2 18 features cover (factor_db H7 + krx_options H3) | ✅ 부분 검증 — H3 (krx_options) cover from this date |
| **2005-05** | factor_db Quality 33 + Value 24 본격 cover | ✅ H7 cover (factor_db) |
| **2000-12-18** | H4 term spread (Gov10Y-Gov3Y) | ✅ |
| **2000-01-03** | H6 flow + sue + fund_merged | ✅ |
| **1995-01-03** | H5 Macro_Risk_Score + KR_Call1D + KR_CorpAA + benchmark + factor_db price-based + State engine | ✅ **Train 1995-01 cover 의무 부분 달성** |
| **1990-01-04** | Target + Macro_Risk_Score (composite) + factor_db price-based 22 factor + FRED 17 series + KR_CPI | ✅ |

### Plan v0.4.2 Train 1995-01 cover 비율

- **Cover (1995-01부터)**: Target + Macro_Risk_Score + VIX + T10Y2Y + KR_Call1D + KR_CorpAA + KR_CPI + factor_db price-based + State engine = **10개 features**
- **NA imputation (1995-1999 결측)**: vkospi_z / otm_skew_25d / kr_term_spread / kr_credit_spread / foreign_netbuy / short_interest / q08_composite_quality / v12_composite_value / sue_z = **8 features**
- **Cover 비율**: 10/18 = **55.6%** (NA imputation XGBoost native handling)

---

## D. Q-Lead 자체 부정확 누적 (총 3건)

| # | 사례 | 발견자 | 즉시 복구 |
|---|---|---|---|
| 1 | Phase 4 inventory 부재 ("research_output/korea_research/G1_01~G9_02 23건 실증") | Codex round 2 직접 grep | 메모리 stale 수정 |
| 2 | macro_fred.parquet 잘못된 폐기 권고 (daily_refresh.sh truth source) | Q-Lead 자체 (build script grep) | 복구 완료 (fred_macro에서 cp + 컬럼 순서 정합, 54,303 rows) |
| 3 | ECOS 항목 코드 초기 매핑 오류 (CorpAA 010320000 → 010300000 / CorpBBB 010330000 → 010320000) | Q-Lead 자체 (KR_CorpAA 2026-03-17 값 검증, 새 fetch 9.712 vs 기존 3.906 불일치) | 코드 수정 + 재 fetch 완료, 7 series cover 1995-01-03 / 1990-01 확장 |

### L-code 적립 권고 (Task 24 진행 중)

```yaml
L-XXX (TBA, methodology_active.md 적립):
  title: "Q-Lead 자체 부정확 3건 — 메모리/폐기/매핑 SOP 강화"
  context: Plan v0.4.2 진입 전 audit
  lesson:
    - 메모리 inherit 시 자원 실재 직접 검증 의무 (Phase 4 inventory)
    - 폐기 결정 시 build script + downstream 의존성 chain 추적 의무 (FRED_CACHE / daily_refresh)
    - 외부 API 코드 reverse engineering 시 기존 cache 정합 sample value 비교 의무
  tags: [governance, audit, codex_dialectic, q_lead_honesty, ecos_api, macro_fred]
  references: [Plan v0.4.2 amendment Section D]
  conditional: "비단순 작업 시 자원/코드/매핑 검증 의무"
```

---

## E. 1990 확장 결과 (FRED + ECOS)

### FRED 22 series (1990-01부터)

| Series | Start | End | Train 1995 cover |
|---|---|---|---|
| VIX (VIXCLS) | **1990-01-02** | 2026-05-15 | ✅ |
| US 10Y (DGS10) | 1990-01-02 | 2026-05-15 | ✅ |
| US 2Y (DGS2) | 1990-01-02 | 2026-05-15 | ✅ |
| Term Spread (T10Y2Y) | 1990-01-02 | 2026-05-18 | ✅ |
| 12 series 추가 (FEDFUNDS / CPI / INDPRO / M2SL / UNRATE / UMCSENT / Init_Claims / NFCI / PERMIT / Bank_Lending / KRW_USD) | 1990-01~ | 2026-04~ | ✅ |
| Copper (PCOPPUSDM) | 1992-01 | 2026-03 | partial |
| StL_Fin_Stress (STLFSI4) | 1993-12 | 2026-05 | partial |
| Breakeven (T10YIE / T5YIE) | 2003-01 | 2026-05 | ❌ |
| WALCL | 2002-12 | 2026-05 | ❌ |
| BAMLC0A4CBBB / BAMLH0A0HYM2 | 2023-05 | 2026-05 | ❌ |

**17/22 series Train 1995-01 cover** ⭐

### ECOS bond 7 series (1990-01부터)

| Series | Start | End | Train 1995 cover |
|---|---|---|---|
| KR_CorpAA | **1995-01-03** | 2026-05-18 | ✅ |
| KR_Call1D | **1995-01-03** | 2026-05-18 | ✅ |
| KR_CPI | **1990-01-01** | 2026-04-01 | ✅ |
| KR_Gov3Y | 2000-02-01 | 2026-05-18 | ❌ 5년 결측 |
| KR_Gov10Y | 2000-12-18 | 2026-05-18 | ❌ 5년 결측 |
| KR_CorpBBB | 2000-09-30 | 2026-05-18 | ❌ 5년 결측 |
| KR_CD91 | 2005-08-01 | 2026-05-18 | ❌ |

**3/7 series Train 1995-01 cover** (KR 금융 인프라 자체 한계 — IMF 후 도입)

### macro_regime.parquet (1990-01~2026-05)

```
Macro_Risk_Score / VIX_Regime / VIX_MA3 / VIX_Zscore
YC_Inversion / Term_Spread_MA3 / Fin_Stress_Regime / NFCI_Tight
Credit_Stress / KRW_Stress / Inflation_Regime / CPI_YoY
+ 32 cols 추가
```

→ **Plan v0.4.2 H5 + State engine block Macro_Risk_Score composite = Train 1995-01 완전 cover** ⭐⭐⭐

---

## F. PIT Loader test PASS (S1 첫 gate)

```
=== PIT Manifest Loader Unit Tests ===
  ✅ Test 1 PASS: fwd_returns_21d detected → stop()
  ✅ Test 2 PASS: 5 패턴 (future / lead / next / forward / ahead) 모두 detected → stop()
  ✅ Test 3 PASS: safe columns → no stop
  ✅ Test 4 PASS: STR_1678 forward target 2건 allowlist 적용
  ✅ Test 5 PASS: missing file → stop()
  ✅ Test 6 PASS: manifest loaded 19 features
  ✅ Test 7 PASS: close=15:30 KST / next_open=익영업일 09:00 KST
=== ALL UNIT TESTS COMPLETED ===
PIT Loader fail-closed semantics 검증 완료. S1 진입 ready.
```

→ **S1 첫 gate PASS. backtest 진행 가능.**

---

## G. Target build PASS (S3 1차)

```
[target_builder] PASS
  total rows: 8955 (1990-01-04 ~ 2026-05-19)
  y_onset events: 891 (9.95%)        ⭐ Primary, balanced prevalence
  y_tail_q15 events: 1161 (12.96%)
  y_tail_q10 events: 789 (8.81%)
  y_regime_strong events: 2680 (29.93%)  ⚠ 30% 다수, 학습 보조만
```

→ **Codex round 1 critique "Y_regime DD>10% 61.7% 라벨링 학습 무의미" 해결** (Y_onset event-onset 정의 → 9.95% balanced).

---

## H. v0.4.2 Final Plan (4 chapter 최종)

### 1. 목표

```r
h = 21 거래일

Y_onset(t) = 1{ DD_252(t-1) > -0.10
                AND ∃ τ ∈ [t, t+h]: DD_252(τ) ≤ -0.10 최초 crossing }   # primary, 9.95%
Y_tail_Q15(t) = 1{ r(t, t+h) ≤ q_Q15_purged(t) }                        # secondary, 12.96%
Y_tail_Q10(t) = 1{ r(t, t+h) ≤ q_Q10_purged(t) }                        # high-confidence, 8.81%
```

### 2. 데이터/피처 (Plan v0.4.2 갱신, 위 C/E 통합)

```
H3 파생: vkospi_z + otm_skew_25d (krx_options 2010~)
H4: kr_term_spread + kr_credit_spread (ecos_bond 2000-09/12~)
H5: macro_risk_score + vix_log_diff_ewma_21d (macro_regime/fred 1990~) ⭐
H6: foreign_netbuy_20d_z + short_interest_20d_z (flow_features 2000~)
H7: q08_composite_quality + v12_composite_value + sue_z (factor_db Q+V 2005~) ⭐ Q-Lead 자체 결정
State: sjm_state + state_age + distance + m4_lag1 + r05_lag1 (factor_db + regime 1990~)
DROP: H1 + H2 (도훈 mandate strict lock)
```

### 3. 모델 (v0.4 retain)

```
Baseline 0 → Elastic-Net Logistic → shallow XGBoost (depth ≤ 3) → SJM state engine 격하
Ensemble: Equal-weight default (validation 위기 다양성 부족 → 보수)
```

### 4. 평가 (Phase 1 = forecast validity, 5 gates + 1 uncertainty)

```
1. DM test (HAC lag ≥ 21) → p < 0.05
2. Brier Skill Score → > 0
3. Calibration (slope ∈ [0.8, 1.2] + ECE < 0.05)
4. Event-level recall @ alert-days → baseline +20%
5. PR-AUC → baseline +20%
REPORT: Bootstrap CI on p_bear (block bootstrap 12m, N=1000)
AUX: Spearman(p_bear, Y_tail) regime conditional bad/normal > 1

Phase 2 이동 lock: Harvey-t / DSR / AX-001 crisis_alpha / Net-of-cost
```

### 5. Walk-forward (v0.4 retain — 도훈 mandate)

```
Train       1995-01 ~ 2009-12   (leave-one-crisis-out)
Validation  2010-01 ~ 2015-12   (rolling-origin folds 6, threshold median lock)
OOS         2016-01 ~ 2026-04
purge       ≥ 21 trading days
embargo     21~63 trading days
HAC lag     ≥ 21 trading days
NA imputation: H3/H6/H7 1995-1999 결측 → XGBoost native handling
```

---

## I. S1 진입 완료 status

✅ workspace mkdir 완료 (config / scripts / tests / outputs / codex_round_log)
✅ config/feature_lag_table.csv 작성 (19 features × publish_timing_kst + decision_time + usable_lag)
✅ config/feature_set_v1.json 작성 (6 block × 1~2 representative + hard cap 10)
✅ README.md 작성 (workspace 헤더 + 진화 이력 v0.1~v0.4.2)
✅ scripts/00_pit_manifest_loader.R 작성 (denylist + timestamp allowlist + fail-closed)
✅ tests/test_pit_manifest_loader.R 작성 + **7/7 unit test PASS** (S1 첫 gate)
✅ scripts/01~06 R script 골격 작성 (thin wrapper, forge/risk-research 위임 detail)
✅ scripts/02_target_builder.R 실행 PASS (Y_onset 9.95% balanced + 4 target 모두 build)

🔄 forge agent S2/S5/S6/S8 spawn (feature panel build + model train)
🔄 risk-research agent S4/S7 spawn (orthogonality + SJM state engine)
🔄 L-code 적립 (Q-Lead 자체 부정확 3건 + plan 진화)

---

## 다음 step

1. forge + risk-research agent 병렬 spawn (background, Codex Round 5단계 retain)
2. agent 결과 도착 후 S9 validation suite 실행
3. plan v0.4.2 final 보고 (Phase 1 deliverable: forecast model + 5 gates 통과)
4. Phase 2 진입 검토 (decision system)
