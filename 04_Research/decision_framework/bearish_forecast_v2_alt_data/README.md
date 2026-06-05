# Phase 1 v1.0 — KOSPI200 Forward Bearish Forecast (Alt Data Based)

**Plan Version**: v1.0 (2026-05-19)
**Owner**: 도훈 (Quant RA)
**Q-Lead**: Claude Opus 4.7 (1M context)
**Status**: 신규 cycle 결성 — v0.4.2 null result 학습 inherit

---

## 변경 핵심 (v0.4.2 → v1.0)

| 항목 | v0.4.2 (null result) | **v1.0** |
|---|---|---|
| **Feature source** | KR quant academic framework 내 (VRP / term spread / fundamental) | **framework 외부 alt data** (DART NLP / 뉴스 / Google Trends / US sector flow / options higher moments / global macro / 학술 discovery) |
| **Information source** | 기존 4종 (MRS/KTRI/M4/R05)과 중복 | **신규 source** (cor < 0.5 strict) |
| **IVA 예상** | 8/9 NEGATIVE 실증 | A1~A7 best mix 양 IVA 목표 |
| **학술 근거** | KR-001~023 23편 KR factor | alt data 전문 paper (Cohen-Malloy-Nguyen 2020 / Bybee-Kelly-Manela-Xiu 2024 / Da-Engelberg-Gao 2011 / BBVA 2026 / Bates 2008 등) |
| **Universe** | KOSPI200 (도훈 mandate retain) | KOSPI200 retain |
| **Target** | Y_onset + Y_tail_Q15 (off-by-one fix) | retain + fix |

## v0.4.2 학습 inherit (재사용 자원)

✅ **Infra (그대로 재사용)**:
- `00_pit_manifest_loader.R` (7/7 test PASS, denylist + fail-closed)
- `tests/test_pit_manifest_loader.R`
- `05_validation_suite.R` (5 gates + 1 uncertainty)
- `02_target_builder.R` (off-by-one fix 후 재사용)
- `config/feature_lag_table.csv` 패턴

✅ **데이터 인프라 (v0.4.2 결과)**:
- FRED 1990-01 확장 (17/22 series Train cover)
- ECOS bond 1990-01 확장 (KR_CorpAA/Call1D 1995-01-03 / KR_CPI 1990-01)
- macro_regime.parquet 1990-01~ build
- ecos_fetch_bond_rates() 신규 collector

✅ **학습 자원**:
- targets_full.parquet (Y_onset / Y_tail_Q15/Q10)
- cor_matrix_vs_4src.csv (8/9 NEGATIVE 입증)

---

## Feature Blocks A1~A7 (alt data 신규 source)

| Block | 신규 features | Source | 학술 근거 |
|---|---|---|---|
| **A1 DART NLP sentiment** | dart_tone_z / dart_risk_kw_freq | jina classify / KoBERT + DART 사업보고서 | Cohen-Malloy-Nguyen 2020 JoF (텍스트 마이닝 alpha) |
| **A2 KR 뉴스 sentiment** | news_sentiment_z / news_topic_dispersion | rss-reader 한경/조경/매경 + jina classify | Bybee-Kelly-Manela-Xiu 2024 (news topic models) |
| **A3 Cross-market US sector flow** | us_sector_etf_flow_z / kr_sector_lead_lag | yfinance MCP (XLF/XLK/XLE/XLE/XLE) + KR sector mapping | Asness-Moskowitz-Pedersen 2013 (global factor structure) |
| **A4 Google Trends attention** | kr_ticker_svi_chg / market_panic_keyword_chg | jina search KR ticker 검색량 | Da-Engelberg-Gao 2011 JoF SVI |
| **A5 Options higher moments** | k200_implied_skew_30d / k200_implied_kurt_30d | KRX options raw (ATM/OTM strikes 분리) | Bates 2008 JF / Conrad-Dittmar-Ghysels 2013 RFS |
| **A6 Global Macro 4-channel** | bbva_sovereign_stress / bbva_market_news_stress | FRED + BBVA framework (KR-016) | BBVA Research 2026 / Adrian-Boyarchenko-Giannone 2019 |
| A7 arxiv 학술 discovery (stretch) | (auto-discovered) | arxiv MCP search → factor proposals | Gu-Kelly-Xiu 2020 (ML asset pricing) |

### Q-Lead 자체 우선순위 (구현 순서)

1. **A6 (BBVA Global Macro)** ⭐ — 가장 직접 구현 가능 (FRED + 학술 framework, 빠른 검증)
2. **A4 (Google Trends SVI)** ⭐ — 정통 학술 + jina MCP 가능
3. **A3 (Cross-market US sector flow)** — yfinance MCP 직접
4. **A5 (Options higher moments)** — krx_options/ raw 재활용 (v0.4 infra)
5. **A1 (DART NLP)** — 가장 신규/직교 likely 단 구현 복잡
6. **A2 (뉴스 sentiment)** — rss-reader feed history 한계 우려
7. **A7 (arxiv discovery)** — 부수적

**1차 sprint = A6 + A4 + A3 + A5 (4 features)** → cor 측정 + IVA POSITIVE 검증 → 2차 sprint A1/A2 확장.

---

## Universe + Target (v0.4 retain)

```
Universe: KOSPI200 (도훈 mandate)
h = 21 거래일

Y_onset(t) = 1{ DD_252(t-1) > -0.10
                AND ∃ τ ∈ [t, t+h]: DD_252(τ) ≤ -0.10 최초 crossing }   # primary
Y_tail_Q15(t) = 1{ r(t, t+h) ≤ q_Q15_purged_60m(t) }                    # secondary

** v1.0 첫 작업 = 02_target_builder.R off-by-one fix (Codex round 4 critical) **
```

---

## Walk-forward (v0.4 retain)

```
Train       1995-01 ~ 2009-12 (leave-one-crisis-out)
Validation  2010-01 ~ 2015-12 (rolling-origin folds 6, threshold median lock)
OOS         2016-01 ~ 2026-04
purge       ≥ 21 trading days
embargo     21~63 trading days
NA imputation: alt data 시작 시점 결측 → XGBoost native handling
```

---

## 평가 (v0.4 retain — 5 gates + 1 uncertainty)

| # | Gate | 기준 |
|---|---|---|
| 1 | DM test (HAC lag ≥ 21) | p < 0.05 |
| 2 | Brier Skill Score | > 0 |
| 3 | Calibration (slope + ECE) | slope ∈ [0.8, 1.2] / ECE < 0.05 |
| 4 | Event recall @ top 20% | lift > 20% |
| 5 | PR-AUC | lift > 20% vs baseline |
| Report | Bootstrap CI | uncertainty |

**v1.0 신규 mandate**: **S4 IVA POSITIVE 의무** (cor < 0.5 vs 기존 4종 + residualized log-loss lift > 0).

→ S4 IVA fail features는 즉시 DROP. v0.4 NEGATIVE 8건 같은 결과 회피.

---

## v1.0 진입 절차 (Q-Lead 자체 진행)

### Sprint 1: v0.4.2 fix + v1.0 infra inherit

1. `02_target_builder.R` off-by-one fix (Y_onset shift 정정) + 재 build
2. v0.4.2 infra 4건 inherit (PIT loader / validation_suite / target_builder / feature_lag_table 패턴)
3. v1.0 config 작성:
   - `config/feature_lag_table.csv` (A1~A6 alt data publish timing)
   - `config/feature_set_v1_alt.json` (4~7 features + alt data source)
   - `README.md` (본 문서)

### Sprint 2: A6 + A4 build (1차 진입)

1. **A6 BBVA framework** — FRED 4-channel macro signal build
   - BBVA Research 2026 "Geopolitics, Geoeconomics, Sovereign Risk" paper inherit
   - FRED series: NFCI / VIX / TED / HY_spread + 추가 BBVA 4채널 변환
   - 기존 macro_regime.parquet 보강 (v0.4 inherit)
2. **A4 Google Trends SVI** — jina MCP `search_web` 활용
   - KR_panic / KR_경기침체 / KR_bear_market keyword 검색량
   - weekly granularity → daily forward-fill
   - PIT: Google Trends data weekly Sunday publish + 1d lag

### Sprint 3: A3 + A5 build (2차 진입)

1. **A3 US sector flow** — yfinance MCP `get_price_history` (XLF/XLK/XLE/XLY/XLI)
   - US sector daily return → KR sector lead-lag (5d/21d EWMA)
2. **A5 Options higher moments** — krx_options/ raw 재활용
   - ATM/OTM strikes 분리 + implied skew/kurt 계산 (Bates 2008 framework)

### Sprint 4: S4 IVA 검증 (critical gate)

각 신규 feature × 기존 4종 cor + residualized log-loss lift 측정. NEGATIVE features 즉시 DROP.

### Sprint 5: Model + S9 evaluation

1. Elastic-Net + XGBoost + Ensemble (v0.4 04_model_runner.R 재사용)
2. S9 5 gates evaluation
3. Plan v1.0 final report

---

## 도훈님 mandate 정합

- ✅ "자체 진행" — Q-Lead 자체 결정 + 진입
- ✅ "쓰레기 넣으면 쓰레기" GIGO — alt data IVA strict 검증
- ✅ "원래 계획대로 (Train 1995-01)" — retain (alt data 결측은 XGBoost native handling)
- ✅ AX-002 process honesty — null result 정직 적립 + 다음 cycle 결성

---

## 작업 디렉토리

```
04_Research/decision_framework/bearish_forecast_v2_alt_data/
├── README.md                          # 본 문서
├── config/
│   ├── feature_lag_table.csv          # alt data PIT publish timing
│   └── feature_set_v1_alt.json        # A1~A6 alt features mapping
├── scripts/
│   ├── 00_pit_manifest_loader.R       # ← v0.4.2 inherit (재사용)
│   ├── 02_target_builder.R            # ← v0.4.2 inherit + off-by-one fix
│   ├── 03_orthogonality_audit.R       # ← v0.4.2 inherit (재사용)
│   ├── 05_validation_suite.R          # ← v0.4.2 inherit (재사용)
│   ├── A1_dart_nlp_builder.R          # ← 신규 (sprint 3+)
│   ├── A2_news_sentiment_builder.R    # ← 신규 (sprint 3+)
│   ├── A3_us_sector_flow_builder.R    # ← 신규 (sprint 3)
│   ├── A4_google_trends_builder.R     # ← 신규 (sprint 2)
│   ├── A5_options_higher_moments.R    # ← 신규 (sprint 3)
│   ├── A6_bbva_macro_builder.R        # ← 신규 (sprint 2)
│   └── 04_model_runner.R              # ← v0.4.2 inherit (FEATURE_COLS expand)
├── tests/
│   └── test_pit_manifest_loader.R     # ← v0.4.2 inherit
├── outputs/
│   ├── 01_data/feature_panel_v1_alt.parquet
│   ├── 02_targets/
│   ├── 03_models/
│   ├── 04_evaluation/
│   ├── 05_orthogonality/
│   └── 06_reports/
└── codex_round_log/                   # v1.0 Codex dialectic
```

---

## 다음 step (Q-Lead 자체 진행)

1. **L-331 적립** (v0.4.2 null result + v1.0 cycle 결성) — Task 31
2. **Sprint 1**: v0.4.2 → v1.0 infra inherit + target off-by-one fix
3. **Sprint 2**: A6 + A4 build (가장 빠른 검증 가능)
4. **Sprint 3**: A3 + A5
5. **Sprint 4**: S4 IVA 검증
6. **Sprint 5**: Model + S9

Sprint 2~5 진입 시 별도 agent spawn 또는 Q-Lead 직접 구현.

도훈님 redirect 있으시면, 없으면 즉시 Sprint 1 진입.
