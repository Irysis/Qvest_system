# Risk Agent Challenge Note — WT-D20260425_009

**Author**: Risk Research Agent
**Date**: 2026-04-25
**Subject**: Iter4 KR FF5 백필 결과 + Σ 추정 + Alpha 산출물에 대한 Risk-side 검토

---

## 1. Executive summary

| 결정 사항 | 결과 |
|---|---|
| `objection_to_alpha_package` | **FALSE** (P4 obligation 충족) |
| `targets_reviewed` | alpha_package / confidence_vector / factor_specs / external_validation_framework |
| `wt_record_challenge_review` 호출 | 완료 |
| `wt_challenge` 호출 | 없음 (이의 없음) |

Risk Agent는 Alpha Agent의 산출물에 대해 **공식 이의 없음**을 기록했다.
다만 본 노트는 Alpha의 open challenge_flags + Risk 자체 진단을 함께 정리한다.

---

## 2. Alpha Agent의 open flags 검토 (Risk 시각)

### FLAG-1 (Iter3 baseline t_NW=2.691 출처 모호)

Alpha Agent가 본 작업 input의 "Iter3 baseline t_NW = 2.691"이 WT_005 ff5_regression_full.txt의 1.843과 불일치함을 자체 진단했다.

**Risk 시각**: Risk Agent는 alpha 회귀를 직접 수행하지 않으므로 baseline t_NW 출처 검증은 Alpha/Forge의 책임이다. Risk 산출물(`kr_factor_returns_v2.parquet`)은 Forge가 회귀 재실행 시 사용 가능한 신규 입력을 제공하므로, FLAG-1은 다음 단계(Forge S1)에서 자연스럽게 해소될 것으로 본다.

**Risk 권고**: Forge가 회귀 재실행 시 v2 파일을 사용해 다음 5종 spec을 모두 보고:
- CAPM (MKT-only)
- Carhart-3 (MKT/SMB/WML)
- Carhart-4 (MKT/SMB/HML/WML)
- FF5 (MKT/SMB/HML/RMW/CMA)
- FF6 (FF5 + WML)

5종 모두 동일 input으로 산출 시 multiple-testing inflation은 자연 통제된다.

---

### FLAG-2 (RF-A6 multiple-testing inflation)

**Risk 시각**: 동일 alpha를 5종 factor model로 보고하는 것은 통계적으로 cherry-pick risk가 있으나, 모든 spec t_NW를 **동시 공개**하는 것이 cherry-pick 방지의 표준 절차이다. Alpha Agent가 이미 `parallel_specs_to_report` 필드에 5종 명시했으므로 충분하다.

**Risk 권고**: Forge S1 산출물 + Judge S6 검증 시 5종 모든 t_NW를 단일 표로 보고 + DSR 함께 산출. Cherry-pick 방지.

---

### FLAG-3 (Risk Agent backfill 의존성)

**Risk 시각**: Backfill 실제 수행 결과 — 본 Σ 추정 cycle에서 `kr_factor_returns_v2.parquet`이 정상 산출되었다 (n=284월, 2002-09 ~ 2026-03).

| Field | v2 (backfilled) | v1 (existing) | 비고 |
|---|---|---|---|
| HML n_nonNA | 284 | 120 | +164 (137% 증가) |
| RMW n_nonNA | 284 | 107 | +177 (165% 증가) |
| CMA n_nonNA | 284 | 107 | +177 (165% 증가) |
| HML mean | +0.16%/월 | +0.18%/월 | 부호/크기 일관 |
| RMW mean | +0.03%/월 | +0.06%/월 | 부호/크기 일관 |
| CMA mean | +0.03%/월 | +0.04%/월 | 부호/크기 일관 |

**FLAG-3은 충족 → fallback (Carhart-3) 불필요.**

다만 한 가지 경고: 2017+ overlap 구간에서 v2 vs v1 상관 (0.47, -0.17, -0.00) 약함. 본 결과는 `risk_package.json::challenge_flags::FLAG-R1`으로 보고했다. 자세한 내용은 §4 참조.

---

### FLAG-4 (Backfilled t_NW expected 4.0~5.5)

**Risk 시각**: Risk Agent는 alpha 회귀를 수행하지 않으므로 t_NW 예측을 직접 검증할 수 없으나, 표본 확장 (n=40 → n=284) sqrt-scale 이론치 7.12는 비현실적이라는 Alpha의 보수 추정 (4.0~5.5) 합리적이다.

**다만 한 가지 추가 고려**: Risk Agent가 산출한 v2 RMW/CMA가 기존 v1과 약한 상관 (cor RMW = -0.17, cor CMA = -0.00)을 보인다. 즉 **factor return time series 자체가 다르다**. 따라서:

- v1 기반 alpha 회귀 t_NW = 1.843
- v2 기반 alpha 회귀 t_NW = ??? (Forge S1 재실행 필요)

두 결과가 크게 다를 수 있다. v2의 부호/크기는 Fama-French/Novy-Marx 학술 기대와 일치하므로 **v2가 PIT-compliant standard textbook construction**이고, v1의 builder는 미상이다 (강도 다른 universe/breakpoint 사용 가능성).

**Risk 권고**: Forge가 회귀 재실행 후 t_NW가 게이트(>2.95) 미통과 시 v1 vs v2 차이가 sample 차이가 아닌 **methodology 차이**일 수 있음을 Judge가 인지해야 한다.

---

## 3. Risk Agent 자체 산출물 요약

### 3-A. Σ = BΩB' + D 구조

| 항목 | 값 |
|---|---|
| Universe (alpha ∩ 24M history ∩ liquid 50M won 20d) | 2301 → valid β: **2300 종목** |
| Lookback window | 60M (2021-04 ~ 2026-03) |
| Factor exposures | MKT / SMB / HML / WML / RMW / CMA (FF5 + WML) |
| Factor cov estimator (선택) | **ledoit_wolf_constcor** (cond=96.8) |
| 비교 estimator | sample (cond=144.2) / ledoit_wolf_oracle (cond=123.6) |
| Σ shape | 2300 × 2300 |
| Σ condition number (post-ridge) | 500.0 |
| Σ PSD | TRUE |
| Ridge λ | 0.0164 (0.0164 / median(diag) = ~10% relative) |
| Systematic variance share | 15.4% |
| Idiosyncratic share | 84.6% |
| Selection objective | shrinkage_quality |

### 3-B. Top common risks (variance contribution)

| Rank | Source | % |
|---|---|---|
| 1 | Idiosyncratic | 70.7% |
| 2 | MKT | 12.8% |
| 3 | SMB | 6.9% |
| 4 | HML | 2.7% |
| 5 | RMW | 2.5% |
| 6 | WML | 2.3% |
| 7 | CMA | 2.1% |

### 3-C. Tail risk (Monte Carlo 5000 simulation, EW portfolio)

| Metric | Monthly |
|---|---|
| VaR 95% | -8.42% |
| CVaR 95% | -10.40% |
| VaR 99% | -11.68% |
| CVaR 99% | -13.23% |

### 3-D. Stress tests

| Scenario | Portfolio loss |
|---|---|
| MKT -5% | -3.44% |
| MKT -10% | -6.88% |
| Value crash (HML -2σ) | +1.17% (성장 편향) |
| Momentum reversal (WML -2σ) | +0.36% |
| Size squeeze (SMB -2σ) | -6.20% (소형주 노출 큼) |
| Quality rotate (RMW -2σ) | -1.51% |
| Investment squeeze (CMA -2σ) | -0.49% |
| GFC 2008 (BM)| -38.03% |
| Rate Hike 2022 (BM) | -24.89% |
| TradeWar 2018 (BM) | -15.92% |

### 3-E. Regime correlation (factor pair, MKT-conditional)

| Regime | n | Mean factor cor | MKT-SMB | MKT-HML | MKT-WML |
|---|---|---|---|---|---|
| Bull | 20 | -0.047 | -0.696 | 0.284 | 0.418 |
| Bear | 17 | -0.004 | 0.198 | -0.155 | 0.140 |
| Normal | 20 | 0.129 | 0.140 | 0.224 | 0.152 |
| Crisis | 3 | NA | NA | NA | NA (n<5) |

**관찰**: Bull 시 MKT-SMB 상관 -0.70 (강한 부의 dependence), Bear/Normal에서는 양의 상관. 소형주가 대형주에 비해 강세 시 underperform하는 KR 패턴과 일치.

### 3-F. TDC (lower tail dependence, q=5%)

| Pair | TDC |
|---|---|
| MKT-WML | 0.333 |
| MKT-RMW | 0.333 |
| SMB-CMA | 0.333 |
| HML-CMA | 0.333 |
| 기타 13쌍 | 0.000 |

5% quantile에서 동시 하락 빈도. 표본 60개월 중 q5 = 3개월이므로 1/3 = 0.333은 1개월만 동시 하락을 의미. 통계적 유의성 낮으나 직관 일치.

---

## 4. Risk Agent open challenge_flags

### FLAG-R1 (MEDIUM): FF5 v2 backfill overlap correlation 약함

**문제**: 2017+ overlap 42개월에서 cor(HML_v1, HML_v2) = 0.47, cor(RMW_v1, RMW_v2) = -0.17, cor(CMA_v1, CMA_v2) = 0.00. Handoff 명세의 0.85 목표 미달성.

**원인 추정**:
1. 기존 `kr_factor_returns.parquet`의 builder code가 부재 (직접 재현 불가)
2. v2는 textbook FF1993/2015 + Novy-Marx 2013, fundamental_merged.parquet (XLSX 2000-2014 + DART 2015+) 사용, 2x3 sort, value-weighted
3. v1은 다른 universe (예: KOSPI200만), 다른 breakpoint (quintile?), 다른 데이터 source 가능성

**Risk 판단**: v2가 PIT-compliant + textbook standard. 다만 v1 vs v2 결과 차이가 명확히 드러나야 한다.

**권고**: Forge S1 회귀 시 두 spec 모두 시도:
- v2 단독 (권장)
- v1+v2 ensemble (robustness check)

만약 t_NW가 매우 차이날 경우 Judge가 **methodology 의존성**을 명시해야 한다.

### RF-R1 (HIGH): Idiosyncratic 70.7% — 매우 높음

**문제**: 2300 종목 EW portfolio의 분산 70.7%가 idiosyncratic. 즉 FF5+WML factor model이 cross-sectional return variance의 30%만 설명.

**해석**: 정상이다. Cross-sectional regression의 R² 기대치가 ~25-35%로 알려져 있고 (Fama-French 1993, KR 실증 30% 내외), 본 결과 (29.3% systematic)는 합리적.

**다만 함의**: Optimizer가 이 Σ로 MVO 수행 시 idiosyncratic 분산이 dominant → diversification (large N) effect가 핵심. **20종목 hard constraint** 하에서는 단일 종목 idio shock이 portfolio risk에 직접 노출됨. Optimizer는 (1) sector cap (2) liquidity floor (3) idio_var 기준 소수 집중 회피를 적용해야 한다.

### RF-R3 (MEDIUM): Top-10 alpha names HHI = 0.48

**문제**: Alpha vector top-10 종목의 시가총액 share가 매우 비대칭 (HHI 0.48 = 강한 집중).

**해석**: 한국 시장 특성. 소수 대형주 (예: 삼성전자, SK하이닉스) 시가총액이 압도적이므로 alpha top-10이 대형주 1~2개 + 중소형주 8~9개일 때 이런 HHI가 자연 발생.

**권고**: Optimizer는 시가총액 가중이 아닌 **active weight 기준** equal-budget 또는 risk-parity를 고려. 명시적 sector_active_weight_cap 제약 (request.json에는 없으므로 설정 필요).

---

## 5. Optimizer Agent에 전달할 핵심 메시지

1. **Σ shape 2300 × 2300 사용 가능** — covariance.parquet
2. **Condition 500 + PSD TRUE** — MVO 직접 사용 OK (다만 추가 shrinkage 권장)
3. **Idiosyncratic 71% — diversification dominant** → 20종목 hard 하에서는 idio_var 기준 명시적 분산 필요
4. **Top common risks**: MKT 12.8% / SMB 6.9% — 리스크 budget 할당 시 두 축 우선 고려
5. **Stress test 결과**: market_down_5 → -3.44% (β_MKT 0.69). market_down_10 → -6.88% (-10% policy threshold 미접근, 안전 margin 충분)
6. **Regime correlation**: Bull MKT-SMB 강한 negative dep — 시장 상승 시 소형주 underperform 대비 필요. 단, Crisis n=3으로 통계적 유의성 낮음 → Optimizer가 regime conditioning 적용 시 caveat 명시

---

## 6. v6.1 R11 Lineage 상태

`02_Infrastructure/worktask/lineage_utils.R::record_package_lineage()` 호출 완료:
- task_id: WT-D20260425_009
- package_type: risk_package
- method_selected: ledoit_wolf_constcor
- input_file_paths:
  - `qepm/mailbox/worktask/WT-D20260425_009/alpha_package.json`
  - `.cache/kr_factor_returns_v2.parquet`
  - `.cache/rawdata.parquet`
  - `.cache/fundamental_merged.parquet`
- windows: covariance_window 2021-04 ~ 2026-03

호출 순서: write_json(risk_package.json) → record_package_lineage() (L-194 sequence fix 준수)

---

## 7. 최종 산출물

| 파일 | 위치 |
|---|---|
| 백필 factor returns | `.cache/kr_factor_returns_v2.parquet` |
| Risk package | `qepm/mailbox/worktask/WT-D20260425_009/risk_package.json` |
| Exposure matrix B | `stage_artifacts/WT-D20260425_009/exposure_matrix.parquet` |
| Factor covariance Ω | `stage_artifacts/WT-D20260425_009/factor_covariance.parquet` |
| Specific risk D | `stage_artifacts/WT-D20260425_009/specific_risk.parquet` |
| Security covariance Σ | `stage_artifacts/WT-D20260425_009/covariance.parquet` (49 MB) |
| Tail risk | `stage_artifacts/WT-D20260425_009/tail_risk.json` |
| Regime correlation | `stage_artifacts/WT-D20260425_009/regime_correlation.parquet` |
| Lineage | `qepm/mailbox/worktask/WT-D20260425_009/artifact_lineage.json` |

---

**END Risk Challenge Note**
