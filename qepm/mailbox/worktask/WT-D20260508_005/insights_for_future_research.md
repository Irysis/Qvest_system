# WT-D20260508_005 후속 연구 활용 인사이트

**Status**: ARCHIVED_DISCOVERY (REJECT_GRADUATION 1M, 12M PARTIAL_SIGNAL)
**Date**: 2026-05-08
**Inheritance target**: 후속 alpha-research WT (Iter 9 family pivot + 12M horizon variant)

---

## 1. 핵심 보존 가치 (정량 입증)

### 1-A. 합성 희석 thesis 입증 ⭐
- WT_004 4 거시 composite ICIR = **0.110**
- WT_005 단일 KR Term Spread β ICIR = **0.183** (+0.073, 66% 개선)
- WT_004 raw ICIR 0.187 (전체 196개월) ↔ WT_005 post-burnin 0.183 (160개월) **재현성 PASS**
- → **단일 거시 source > 다거시 합성** (단순 평균 가중 시 신호 분산 dilute)
- 후속 mandate: **단일 거시 source 유지 + horizon 변경 또는 ML 비선형으로 신호 강화**

### 1-B. 12M long-horizon 부분 신호 ⭐
- 12M ICIR = **0.310** (1M 0.183 대비 +0.127, 69% 강화)
- 12M Harvey-NW t = 1.90 (3.0 미달, 보강 필요)
- 12M Subperiod 부호 = **3/3** (정상 / 위기 / 회복 모두 +)
- → 거시 충격이 종목 cross-section에 _장기간_ 반영. Cooper-Gulen-Schill 2008 / Asness-Moskowitz-Pedersen 2013 정합.
- 후속 mandate: **12M aggregation horizon variant 정식 검증 + DSR multi-trial 의무**

### 1-C. 직교성 견고 ⭐
- vs Hybrid 70/15/15 baseline (STR_1715 + TSMOM + KR_10y): max |cor| = **0.137** (< 0.25 PASS)
- AR / TSMOM / KR_10y 각 cor 0.10~0.14 → 신호 축 본질 다름 입증
- 1M FAIL이지만 _차원적 직교성_은 retain
- 후속 mandate: **신호 강화 시 4번째 직교 source 본질 자격**

### 1-D. DSR Bailey-Lopez de Prado strict 통과
- N_trials = 12 / 17 / 27 모두 z > 0.5 (z=6.61 ~ 6.97 보수)
- Multiple testing haircut에서 신호 robustness 입증
- 단 IC 자체 약함 (0.0193) — N_trials 통과는 신호 안정성, 실 graduation은 IC 절대치 필요

### 1-E. Universe v2 mid-cap marginal
- KR_top500_freefloat universe ICIR (12M) = +0.037 vs default
- → mid-cap inclusion 시 신호 약간 강화 (binding constraint 아님)
- 후속 mandate: universe restriction은 신호 약함의 _주요_ 원인 X

### 1-F. 섹터 매개 컴포넌트 인지
- Sector-neutral retention 0.42 (RF-A4 trigger)
- Raw IC 0.0193 → Sector-neutral IC ≈ 0.008 (58% 감소)
- → 신호의 절반 이상이 _섹터 베팅_으로 발생. Cyclical (반도체 / 자동차 / 금융) 비중 ↑ 시 term spread β ↑.
- 후속 mandate: **섹터 overlay 잠재 (Risk Agent 영역) — 거시 베타와 섹터 베팅 분리 검토**

---

## 2. 5 시도 누적 패턴 (Q-Lead 메타 인사이트)

### 본질 발견
한국 stock cross-section **월간 single-source 1M horizon 졸업 본질 어려움**:

| WT | 1M IC | 12M IC | 직교성 | FAIL 핵심 |
|---|---|---|---|---|
| 001 VRP | spurious 0.957 → 정정 -0.07 | — | — | lag-1 autocor + ML leakage |
| 002 v5 ML | 0.019 | — | — | PIT-proper 93% drop |
| 003 VRP 4-sub | 중단 | — | — | 한국 옵션 chain 부재 (해소 가능) |
| 004 거시 composite | 0.012 (1M) / 0.04 (12M) | 0.322 (12M) | 0.162 PASS | composite 희석 |
| **005 단일 KR Term Spread** | **0.019 (1M)** | **0.310 (12M)** | **0.137 PASS** | **1M 약함 / 12M 부분** |

### 패턴 1: 12M horizon 일관 강세
- WT_004 composite 12M ICIR 0.322
- WT_005 단일 12M ICIR 0.310
- 두 시도 모두 12M에서 부호 일관 + ICIR > 0.30 + Harvey-t > 1.90

### 패턴 2: 직교성 견고
- 두 시도 모두 max |cor| < 0.20 (vs Hybrid)
- 즉 신호 축 자체는 본질 새로움

### 패턴 3: 1M graduation 미달
- 1M Harvey-t < 3.0 일관
- DSR strict 통과 (Bailey-LdP) but 절대 IC 약함

→ **후속 핵심 design**:
1. **12M aggregation horizon shift** (1M → 12M monthly compounded signal)
2. **회전율 절감 long-horizon design** (rebalance 12개월 → 회전 50~150%)
3. **다요소 결합 시 비선형 / IPCA framework** (단순 합성 X)
4. **섹터 overlay 분리** (Risk Agent 영역)

---

## 3. 후속 연구 4 path 권고

### 3-A. WT_005 12M horizon variant (즉시 가능)
- 같은 KR Term Spread β 신호 + 12M aggregation
- 회전율 50~150% 추정 (한도 600% 정합)
- DSR Bailey-LdP strict 강화 N_trials 보수 검증
- Harvey-t > 3.0 path 보강 (sample 확장 또는 robust 분산)

### 3-B. Iter 9 family pivot (도훈 명시 후속)
- **Growth × Investor_Flow** — 한국 외국인 / 기관 net flow + Growth metric 결합
- **Skewness × CFO accrual** — Bali-Engle-Murray 2016 + Sloan 1996
- **Macro × Profitability conditional** — 거시 regime 조건부 quality factor

### 3-C. IPCA conditional latent (WT_006 진행 중)
- Kelly-Pruitt-Su 2019 framework
- 본 WT_005 단일 거시는 _IPCA 특성 1건_으로 볼 수 있음
- IPCA에서 다특성 instrumented latent 비교 시 gain 검증 가능

### 3-D. 섹터 overlay (Risk Agent 영역)
- 거시 β 신호의 섹터 매개 컴포넌트 (retention 0.42) → 명시 분리
- Risk Agent에 섹터 noise 차감 위임
- 또는 Optimizer Agent에서 섹터 neutralization 강제

---

## 4. 학술 출처 inheritance

본 WT 학술 baseline:
- **Cooper-Gulen-Schill 2008 RFS** "Asset Growth and the Cross-Section of Stock Returns" — 거시 베타 cross-section foundational
- **Belo-Lin-Vitorino 2014 RFS** "Brand Capital and Firm Value" — Investment-based AP
- **Asness-Moskowitz-Pedersen 2013 JF** "Value and Momentum Everywhere" — global cross-section
- **Chen-Roll-Ross 1986 JF** "Economic Forces and the Stock Market" — 거시 factor pricing foundational
- **Bailey-Lopez de Prado 2014** "Pseudo-Mathematics and Financial Charlatanism" — DSR multi-trial haircut

후속 보강:
- **Stambaugh-Yuan 2017 JFE** "The Short of It: Investor Sentiment and Anomalies" — sentiment overlay
- **Asness-Frazzini-Pedersen 2019 JFE** "Quality Minus Junk" — 12M horizon quality

---

## 5. L-code 신규 적립 (후속 세션)

**L-285 (예정)**: KR top universe single macro Term Spread β 1M graduation 미달, 12M long-horizon 부분 신호 (ICIR 0.310 + Harvey-t 1.90), 직교성 견고 (cor 0.137). 합성 희석 thesis 입증 (단일 0.183 > composite 0.110). 후속 path = 12M horizon variant + Iter 9 family + IPCA + 섹터 overlay 분리.

---

## 6. 산출물 inheritance (후속 WT 활용)

| 산출 | 경로 | 후속 활용 |
|---|---|---|
| `alpha_scores.parquet` | `stage_artifacts/WT_D20260508_005/` (66576 rows × 196 sig_dates) | 12M aggregation 직접 시도 |
| `alpha_scores_forward_2026-05.parquet` | 동일 dir (343 tickers) | 5월 forward 가설 검증 |
| `c13_audit.json` | 동일 | PIT-C13 dynamic alignment audit 재사용 |
| `c15_infeasibility_report.json` | 동일 | Factor DB bypass 정당화 retain |
| `codex_remediation_aggregate.json` | 동일 | DSR N=17/27 + universe v2 결과 |
| `orthogonality_vs_hybrid.json` | 동일 | 직교성 0.137 검증 정량 |
| `method_shopping_log.json` | 동일 | 17 candidates 자율 탐색 (재선정 가능) |
| `dsr_strict_bailey_ldp.json` | 동일 | Bailey-LdP haircut N=12/17/27 정량 |

---

## 7. 핵심 1줄 요약

**"WT_005 = 합성 희석 thesis 입증 + 12M horizon 0.310 부분 신호 + 직교성 0.137 견고. 1M graduation 미달이지만 후속 12M horizon variant + Iter 9 family pivot + IPCA + 섹터 overlay 분리 path 모두 본 WT 정량 baseline 활용 가능."**

inheritance 의무: 후속 alpha-research WT는 본 `insights_for_future_research.md` Read 후 path design.
