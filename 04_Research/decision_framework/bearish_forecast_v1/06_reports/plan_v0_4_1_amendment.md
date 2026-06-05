# Plan v0.4.1 Amendment — Rawdata Audit 통합

**Date**: 2026-05-19
**Q-Lead**: Claude Opus 4.7
**Owner**: 도훈
**Status**: pending 도훈님 final 승인 → S1 진입

---

## A. v0.4 → v0.4.1 변경점 요약

| Change | 분류 | 출처 |
|---|---|---|
| 5 추가 자원 통합 (macro_regime / fund_dart / krx_options 직접 / consensus / universe_v2) | feature 보강 | 도훈 mandate Q-A (a) |
| 4 중복/stale 정리 (`.bak` 2건 + `macro_fred` 복구 + `fundamentals` symlink retain) | infra 정리 | 도훈 mandate Q-B (a) |
| 신선도 갱신 3건 (ecos_bond + flow_features + fund_merged) | data refresh | 도훈 mandate Q-C (a) |
| ECOS bond collector 신규 작성 | infra 보강 | 도훈 mandate Q-E (가) |
| flow_features build script 발견 + 정합 검증 | 추적 | 도훈 mandate Q-D (a) |
| Q-Lead 자체 부정확 3건 정직 인정 + L-code 적립 | governance | meta |

---

## B. Rawdata Audit 결과 (정합성 + 활용 / 폐기)

### B.1 cache parquet 활용 정책 (v0.4.1)

| Cache | size | Last update | v0.4.1 활용 | Build script |
|---|---|---|---|---|
| `benchmark.parquet` | 196KB | **2026-05-19 FRESH** | Target | `build_cache.R` |
| `flow_features_daily.parquet` | 1.1GB | **2026-05-19 FRESH** ⭐ | H6 (X 20 cols, fwd_ 2건 denylist) | `04_Research/strategies/flow_concentration_ml/01_flow_features.R` |
| `fred_macro_wide.parquet` | 206KB | **2026-05-19 FRESH** | H5 wide 23 cols | `fred_robust.R` |
| `fred_macro.parquet` | 279KB | **2026-05-19 FRESH** | (long format) | `fred_robust.R` |
| `macro_fred.parquet` | 279KB | **2026-05-19 복구 완료** ⭐ | (daily_refresh truth source) | `data_collector_fred.R` |
| **`macro_regime.parquet`** ⭐⭐⭐ | 66KB | **2026-05-19 FRESH** | **H5 / State engine — 신규 통합** | `data_collector_fred.R::fred_compute_regime` |
| `ecos_bond_rates.parquet` | 145KB | **2026-05-19 FRESH** (Q-Lead fix) | **H4 — 6 series KR_Gov3Y/10Y + KR_CorpAA/BBB + KR_CD91 + KR_Call1D** | `data_collector_ecos.R::ecos_fetch_bond_rates` (v0.4.1 신규) |
| `ecos_krw_usd.parquet` | 63KB | **2026-05-19 FRESH** | H4 보조 (FRED와 중복) | `data_collector_ecos.R::ecos_fetch_krw` |
| `fundamental_merged.parquet` | 32MB | **2026-05-19 FRESH** ⭐ | H7 (5.4M rows long format) | `build_fundamental_derived.R` |
| **`fundamental_dart.parquet`** ⭐⭐ | 7.4MB | 2026-05-01 | **H7 — 178 cols PiotroskiF/AltmanZ/QualityScore/IsZombie 사전 계산 score** | `data_collector_dart.R` |
| `fundamental_dart_quarterly.parquet` | 9MB | 2026-05-19 | H7 보조 (분기) | `data_collector_dart.R` |
| `fundamental_xlsx_ttm.parquet` | 51MB | 2026-04-13 | H7 보조 (TTM) | (legacy) |
| `universe.parquet` | 221KB | 2026-05-01 | universe master | `apply_universe_mapping.R` |

### B.2 디렉토리 자원

| Dir | files | size | v0.4.1 활용 |
|---|---|---|---|
| **`krx_options/`** ⭐⭐ | **4023 일별 parquet** | 202MB | **H3 직접 빌드 (VKOSPI / 25Δ skew / put-call / OPNINT)** — `IMP_VOLT` + `RGHT_TP_NM` + `ACC_OPNINT_QTY` 컬럼 |
| **`consensus/`** ⭐⭐ | **13 parquet** | 65MB | **H7 보강 — `sue` + `esbr` + `eps_chg_1m` + `target_price`** (도훈님 L-274 SUE lagging 사례 정합) |
| **`universe_v2/`** ⭐ | **57 PIT snapshot** | 1.4MB | **생존편향 회피 — 매 시점 t에서 가까운 snapshot 사용** |
| `investor_stock/` | 6 | 703MB | (Phase 2 보조, 종목별 매매) |
| `factor_db/` | 442 | 5.0GB | 313 factor 월간 (S4 직교성 baseline) |
| `factor_db_daily/` | 437 | 23GB | 309 factor 일간 (Phase 2 reserved) |
| `sleeve_returns/` | 10 | 892KB | Phase 2 reserved (Phase 1 X) |
| `dart/` | 6 | 125MB | DART raw |
| `krx/` | 6 | 4.6MB | KRX 일반 |
| `consensus/` | 13 | 65MB | (위 H7) |

### B.3 CSV 자원 (313 factor IC matrix)

| CSV | rows / cols | v0.4.1 활용 |
|---|---|---|
| **`conditional_ic_matrix_4regime.csv`** ⭐⭐ | 313 factor × 16 cols (4 regime + ICIR + n_months) | **S4 직교성 검증 baseline + Codex Fix 3 trial accounting** |
| `factor_ic_shortsell_regime.csv` | 313 × 8 (ALLOW/BAN) | H6 공매도 regime 정합 |
| `factor_ic_kospi_kosdaq_split.csv` | 313 × 8 | universe split 검증 |
| `crisis_defense_factor_analysis.csv` | 33 × 8 | AX-001 v2 정합 baseline |

### B.4 폐기 / 정리 완료 (Q-B (a))

- ✅ `.bak` 2건 (`fred_macro.parquet.bak_20260518/19`) — 즉시 삭제 완료
- ✅ `macro_fred.parquet` 잘못된 폐기 → 즉시 복구 완료 (Q-Lead 부정확 사례 2번째)
- ✅ `fundamentals.parquet` 26byte → 실제는 symbolic link, retain
- ✅ `ecos_bond_rates.parquet` 항목 코드 오류 → 즉시 fix + 재 fetch 완료 (Q-Lead 부정확 사례 3번째)

---

## C. 5 추가 자원 통합 — Plan v0.4 Feature Blocks 갱신

### C.1 갱신된 Feature Block 표

**Hard cap 정책**: 8~10 features total (block 대표 합산, state block 포함). 사전 계산 composite score 활용으로 effective cap 여유.

| Block | v0.4 features | **v0.4.1 보강** | 합산 features |
|---|---|---|---|
| **H3 파생 stress** | VKOSPI z / 25Δ skew | **`krx_options/` 4023 daily files 직접 빌드** (IMP_VOLT + RGHT_TP_NM + OPNINT) | 1~2 |
| **H4 rates/credit** | 10y-3y term / AA-/BBB- credit | **`ecos_bond_rates` 7 series에서 직접 계산** (term spread = KR_Gov10Y - KR_Gov3Y / credit spread = KR_CorpBBB - KR_CorpAA) | 1~2 |
| **H5 글로벌 전이** | VIX log+diff+EWMA / 미10y-2y | **`macro_regime.parquet`에서 `Macro_Risk_Score` 1 feature composite** (VIX_Regime + Fin_Stress_Regime + Credit_Stress + KRW_Stress + Inflation_Regime + Macro composite) | 1~2 |
| **H6 flow/공매도** | 외인 net buy / 공매도 잔고 | (retain) | 1~2 |
| **H7 valuation (interaction only)** | K200 PER / forward EPS Δ | **`fundamental_dart.parquet`에서 `QualityScore` or `PiotroskiF` 1 feature composite** + `consensus/sue.parquet` (Standardized Unexpected Earnings) 1 feature | 1~2 |
| **State engine** | SJM_state / state_age / distance_to_centroid + M4 + R05 | (retain, KR-013 method transfer) | 3 |
| ~~H1 모멘텀~~ | — | DROP | 0 |
| ~~H2 변동성~~ | — | **DROP (도훈 mandate strict lock)** | 0 |
| **합계** | | | **8~10 strict** |

### C.2 핵심 보강 효과

1. **`macro_regime.parquet` Macro_Risk_Score** — 1 feature로 multi-axis (VIX/Fin/Credit/KRW/Inflation) composite 활용 → cap 절약 + KR-relevant macro regime 통합 표현
2. **`fundamental_dart.parquet` QualityScore / PiotroskiF** — 사전 계산된 KR fundamental composite (RoE/RoA/Accrual/Leverage 등 9 components) → H7 cap 절약
3. **`krx_options/` 직접 빌드** — VKOSPI / 25Δ skew / put-call ratio 정확한 KR 옵션 raw data 활용 (cache .csv 한정 X)
4. **`consensus/sue.parquet`** — Standardized Unexpected Earnings (도훈님 L-274 SUE lagging 사례 정합 자원)
5. **`universe_v2/` PIT-clean snapshot** — 매 시점 t에서 가장 가까운 snapshot 사용 = 생존편향 회피 strict

### C.3 PIT loader denylist 정합 (v0.4.1 lock)

```r
deny_pattern <- "(^fwd_|^future_|^lead_|^next_|^t_plus_|^forward_|^ahead_)"
# analyst forecast 오인 차단 — target_price / op_profit_fy1 / revenue_fy1 / forward_eps 등은 t 시점 publish, leakage 아님
```

**검증 결과**:
- `flow_features_daily.parquet`: `fwd_inst_foreign_netbuy_21d` + `fwd_flow_top20` 2건 → denylist hit (STR_1678 의도적 forward target, 정상)
- 다른 모든 parquet: leakage 0건
- analyst forecast (target_price / forward_eps) → t 시점 publish, denylist 회피 (정상)

---

## D. Q-Lead 자체 부정확 3건 — L-code 적립 의무

| # | 사례 | 발견자 | 즉시 복구 |
|---|---|---|---|
| 1 | Phase 4 inventory 부재 ("research_output/korea_research/G1_01~G9_02 23건 실증") | Codex round 2 (직접 grep) | 메모리 stale 수정 |
| 2 | macro_fred.parquet 잘못된 폐기 권고 (daily_refresh truth source) | Q-Lead 자체 (build script grep) | 복구 완료 (fred_macro에서 cp) |
| 3 | ECOS 항목 코드 초기 매핑 오류 (CorpAA 010320000 → 010300000) | Q-Lead 자체 (정합 검증 fail) | 코드 수정 + 재 fetch 완료 |

### L-code 적립 권고 (S1 진입 직후)

```yaml
L-XXX (TBA):
  title: "Q-Lead 자체 부정확 3건 — 메모리/폐기/매핑 SOP 강화"
  context: Plan v0.4.1 진입 전 audit 단계
  lesson:
    - 메모리 inherit 시 자원 실재 직접 검증 의무
    - 폐기 결정 시 build script + downstream 의존성 추적 의무 (FRED_CACHE / daily_refresh 호출 chain)
    - 외부 API 코드 reverse engineering 시 기존 cache 정합 검증 의무 (sample value 비교)
  tags: [governance, audit, codex_dialectic, q_lead_honesty]
  references: [Plan v0.4.1 amendment Section D]
```

---

## E. 신선도 갱신 결과

| Cache | 이전 mtime | 신규 mtime | 갱신 방법 |
|---|---|---|---|
| `ecos_bond_rates.parquet` | 2026-03-17 | **2026-05-18** | Q-Lead 직접 (collector 신규 작성) |
| `flow_features_daily.parquet` | 2026-04-16 | **2026-05-19** | forge agent 위임 |
| `fundamental_merged.parquet` | 2026-04-13 | **2026-05-19** | forge agent 위임 |
| `macro_fred.parquet` | (폐기됨) | **2026-05-19 복구** | Q-Lead 직접 (cp from fred_macro) |
| daily_refresh.sh ecos_bond 호출 | (부재) | **TODO follow-up** | `daily_refresh.sh [4]`에 `ecos_fetch_bond_rates()` 추가 의무 (S1 진입 후) |

---

## F. v0.4.1 Final Plan (4 chapter)

### 1. 목표 (v0.4 retain)

```r
h = 21 거래일

Y_onset(t) = 1{ DD_252(t-1) > -0.10
                AND ∃ τ ∈ [t, t+h]: DD_252(τ) ≤ -0.10 최초 crossing }

Y_tail_Q15(t) = 1{ r(t, t+h) ≤ q_Q15_purged(t) }
Y_tail_Q10(t) = 1{ r(t, t+h) ≤ q_Q10_purged(t) }
```

### 2. 데이터/피처 (v0.4.1 갱신, 위 C.1)

8~10 features:
- H3: VKOSPI z (krx_options 직접) + 25Δ skew
- H4: term spread (KR_Gov10Y - KR_Gov3Y from ecos_bond) + credit spread (KR_CorpBBB - KR_CorpAA)
- H5: **Macro_Risk_Score** (macro_regime 1 feature composite)
- H6: 외인 net buy z (lag-1, flow_features) + 공매도 잔고 z
- H7: **QualityScore** (fund_dart composite) + sue (consensus)
- State engine: SJM_state(t-1) + state_age + distance_to_centroid + M4(t-1) + R05_regime(t-1)

### 3. 모델 (v0.4 retain)

- Baseline 0: Prevalence + lagged-Y_{t-h-1} naive
- 1차: Elastic-Net Logistic (R glmnet)
- 2차: Monotone GAM or shallow XGBoost (depth ≤ 3)
- 3차 격하: SJM state engine만
- Ensemble: Equal-weight (default) / BMA / Ridge-stacked

### 4. 평가 (v0.4 retain — 5 performance gates + 1 uncertainty report)

| # | Gate | 기준 |
|---|---|---|
| 1 | DM test (HAC lag ≥ 21) | p < 0.05 |
| 2 | Brier Skill Score | > 0 |
| 3 | Calibration (slope + ECE) | slope ∈ [0.8, 1.2], ECE < 0.05 |
| 4 | Event-level recall @ fixed alert-days | baseline +20% |
| 5 | PR-AUC | baseline +20% |
| — | Bootstrap CI on p_bear (uncertainty report) | — |
| (보조) | Spearman(p_bear, Y_tail) regime conditional | ratio > 1 |

Walk-forward: 1995~2009 train / 2010~2015 valid / 2016~2026 OOS / purge ≥ 21 / embargo 21~63 / leave-one-crisis-out.

Phase 2 이동 lock: Harvey-t / DSR / AX-001 crisis_alpha / Net-of-cost simulation.

---

## G. S1 진입 준비 status

✅ workspace mkdir 완료 (Session 11)
✅ rawdata audit 완료 (Q-A~F 모두 a/가/나 진입)
✅ 신선도 갱신 완료 (ecos_bond + flow_features + fund_merged)
✅ 폐기/복구 완료 (.bak + macro_fred + ECOS 항목 코드 fix)
✅ 5 추가 자원 통합 결정 (macro_regime / fund_dart / krx_options / consensus / universe_v2)
🔄 v0.4.1 amendment 작성 완료 (본 문서)

### S1 진입 시 첫 작업 (재확인)

```
[Step 1] config 파일 작성
         - config/feature_lag_table.csv (변수별 publish lag, PIT 의무)
         - config/feature_set_v1.json (8~10 features + source mapping)
         - README.md (plan v0.4.1 요약)

[Step 2] PIT loader 첫 gate (필수)
         - scripts/00_pit_manifest_loader.R 신규
           (denylist + timestamp allowlist + fail-closed)
         - tests/test_pit_manifest_loader.R 신규
           (mock leakage data로 stop() 검증)
         - test PASS 확인

[Step 3] PIT loader PASS 후
         - S2 (feature panel build) → forge agent spawn
         - S4 (직교성 vs MRS/KTRI v3/M4/R05) → risk-research agent spawn
         - 병렬

[Step 4] L-code 적립 (S1 진입 직후)
         - 3-round Codex dialectic
         - Q-Lead 자체 부정확 3건
         - H2 DROP 도훈 mandate
         - macro_regime / fund_dart 신규 통합

[Step 5] follow-up TODO
         - daily_refresh.sh [4]에 ecos_fetch_bond_rates() 호출 추가
         - KR-006 econstor 본문 확보 (soft → hard anchor 승격)
         - .bak 재발 root cause 추적 (Session 80 이후 재발 source)
```

---

## H. 도훈님 final 승인 요청

위 v0.4.1 amendment **승인 시 즉시 S1 진입** (Step 1~3).

답주시면 즉시:
1. `config/feature_lag_table.csv` 작성
2. `config/feature_set_v1.json` 작성
3. `scripts/00_pit_manifest_loader.R` + `tests/test_pit_manifest_loader.R` 작성
4. PIT loader test PASS 확인 후 S2 + S4 agent 병렬 spawn
5. L-code 적립

수정 사항 있으시면 1~2줄 지시.
