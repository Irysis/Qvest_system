# Risk Challenge Note — WT-D20260425_007 MEGA_05 Regime-Σ MinCVaR (Iter 2)

작성: Risk Research Agent | 2026-04-25
Common Charter Principle 8 (No Silent Override) 준수 — alpha_vector / regime label 변경 없음.

---

## 1. Mandate scope (자기 권한 경계)

**입력 (read-only)**: alpha_package.json (MEGA_05 6F + regime label) + regime_panel.parquet + alpha_scores.parquet + RAWDATA daily.

**산출물 (이번 단계만)**:
- 4-regime conditional Σ + pooled Σ (`covariance_per_regime.parquet`)
- 팩터 모형 분해 B Ω B' + D (`exposure_matrix / factor_covariance / specific_risk.parquet`)
- Tail risk per regime (CVaR 95/99, EVT-style empirical, lower-TDC) (`tail_risk.json`)
- 8 historical stress windows
- Regime transition cost + empirical transition matrix (`regime_transition_cost.json`)
- Crowding + 유동성 + sector concentration 진단

**금지 (수행하지 않음)**:
- alpha_vector / confidence_vector / regime label / factor mix 수정 — 모두 alpha_package 그대로 보존
- weight 결정 / MinCVaR 구현 / Kelly_frac 비교 — Optimizer 영역
- 포트폴리오 비중 제안 / "좋은 종목" 판단

---

## 2. 핵심 발견 (Σ estimation quality 관점)

### 2.1 Per-regime Σ — 핵심 한계: Top-20 panel 매칭 시 thin sample

| Regime | regime_panel T (months) | top20-panel T (months) | LW δ | cn (LW) | min_eig | 결과 |
|---|---|---|---|---|---|---|
| BULL    | 158 → train 118 | **84** | 1.000 | 29.6  | 1.6e-3 | OK |
| NORMAL  | 143 → train 101 | **61** | 1.000 | 52.8  | 1.3e-3 | OK |
| CAUTION |  66 → train  53 | **25** | 1.000 | 30.8  | 2.8e-3 | OK |
| CRISIS  |  41 → train  33 | **5**  | 0.850 | 3299  | 3.6e-5 | **FALLBACK to pooled Σ** (cn>500) |
| POOLED  | (전체 241)     |    241 | 0.907 | 24.9  | —      | OK (안정) |

**해석**: alpha agent가 우려한 RF-REGIME-SAMPLE은 regime_panel 단위(33개월)였지만, Σ는 **20-종목 monthly 수익률 panel** 위에서 추정해야 하므로 실제 thin sample 강도는 더 심함. 후기 listing tickers (LG에너지솔루션 A373220 등)가 CRISIS 시기에 미존재 → 5개월만 동시 관찰 가능. **CRISIS에서 regime-specific Σ는 추정 자체가 비현실적**이므로 pooled Σ로 fallback. 이는 alpha agent의 RF-REGIME-SAMPLE에 대한 risk-side 보강.

### 2.2 Shrinkage 강도 — 거의 모든 regime이 target로 수렴 (δ→1)

BULL/NORMAL/CAUTION 모두 **δ=1.000** (sample → constant-corr target 완전 대체). 이는:
- 표본 공분산 cn이 모두 276~351로 ill-conditioned (D=20 vs T=25~84)
- Ledoit-Wolf 통계량이 sample variance를 신뢰할 수 없다고 판정
- 결과적으로 regime-conditional Σ는 **"regime별 vol scaling이 다른 평균-상관 행렬"** 에 가까움

| Regime | avg σ (월간) | mean ρ | median ρ | p90 ρ |
|---|---|---|---|---|
| BULL    | 0.1009 | 0.125 | 0.125 | 0.125 |
| NORMAL  | 0.1108 | 0.126 | 0.126 | 0.126 |
| CAUTION | 0.1169 | 0.221 | 0.221 | 0.221 |
| CRISIS (fallback) | 0.1134 | 0.169 | 0.168 | 0.181 |

**관찰**: CAUTION에서 평균 상관 ρ=0.221이 BULL/NORMAL의 0.125 대비 76% 상승. 이것이 regime-Σ MinCVaR의 **근본 동력**: CAUTION/CRISIS 진입 시 분산 효과 감소 → Optimizer가 자동으로 max_weight 축소 + 종목 다변화 압력. POOLED Σ만 쓰면 이 정보 손실.

### 2.3 PCA 팩터 분해 — common-risk 적정

- PC1 share 25.9% (market proxy) — RF-R1 임계 40% 미만, 정상
- 평균 factor-explained share 48.0% (specific 37.6%) — Top-20 작은 universe 특성상 적정
- PCA cumulative: 25.9% / 34.9% / 43.4% / 50.9% / 56.8% / 62.4% (k=6 → 62%)

### 2.4 Tail risk (daily, EW 20 basket proxy)

| Regime | n (days) | CVaR 95 | CVaR 99 | skew | kurt | MDD | avg lower-TDC (q=0.10) |
|---|---|---|---|---|---|---|---|
| BULL    | 2522 | 0.0294 | 0.0476 | -0.45 | 6.43 | -0.27 | 0.193 |
| NORMAL  | 2194 | 0.0359 | 0.0513 | -0.13 | 4.85 | -0.39 | 0.236 |
| CAUTION | 1121 | 0.0570 | 0.0923 | -0.34 | 5.89 | -0.74 | **0.289** |
| CRISIS  |  750 | 0.0615 | 0.0909 | -0.67 | 6.88 | -0.79 | 0.221 |

**해석**: CAUTION에서 lower-TDC 0.289 = **하방 동조성 최강** — 위기 진입 단계에서 종목간 동시 손실 위험 가장 큼. CRISIS는 daily n=750으로 표본 충분하지만, CAUTION의 dispersion penalty가 더 시급. CVaR99 0.092 (CAUTION) 의미: 100일 중 1일은 EW 바스켓이 9.2%+ 손실.

### 2.5 8 historical stress windows (EW 20 proxy, daily compounded)

| Period | n | cum_ret | MDD |
|---|---|---|---|
| Terror_9_11    |  81 |  +9.1%  | -27.2% |
| **GFC_2008**   | 371 | **-43.5%** | **-68.1%** |
| Euro_Debt_2011 | 126 |  -1.0%  | -35.3% |
| China_Shock    | 186 |  -9.3%  | -19.0% |
| US_China_Trade | 204 | -13.6%  | -20.4% |
| COVID_2020     | 123 |  -0.4%  | -41.9% |
| Rate_2022      | 246 | -24.3%  | -28.9% |
| Iran_War_2026  |  57 | +36.7%  | -13.8% |

GFC -43.5% → RF-R4 HIGH 발화. 단, 이는 **과거 EW 20-name proxy** 손실이지 Optimizer의 weight 적용 후 portfolio 손실이 아님 (Optimizer 단계에서 MinCVaR/Kelly가 손실 완화).

### 2.6 Regime transition cost

- Total switches: 100 / 305 months ≈ **3.93 switches/year**
- Persistence (대각): BULL 0.822 / NORMAL 0.604 / CAUTION 0.481 / CRISIS 0.636
- BULL→CAUTION/CRISIS 직접 점프 = 0.034 / 0.000 (NORMAL/CAUTION 경유)
- CRISIS→BULL = 0.000 (회복 시 NORMAL/CAUTION 경유)

**Optimizer 함의**: 연 ~4회 regime switch → switch 시 Σ shift 폭이 큼 (특히 NORMAL↔CAUTION, ρ 0.126→0.221). turnover penalty를 regime switch frequency에 비례시켜 calibrate 필요.

---

## 3. Risk → Alpha challenge review (R3 P4 GAP-1 의무)

| 검토 대상 | Risk-side 평가 | 이의 제기 |
|---|---|---|
| alpha_vector (top 20 ticker scores) | 그대로 수신, 손대지 않음 | NO |
| confidence_vector | 그대로 수신 | NO |
| factor_specs (6F MEGA_05) | factor mix 보존 mandate 인정 | NO |
| regime_classification (4-state expanding pct) | C1+C2+C9+C11 PIT 검증 인정 | NO |
| **CRISIS 샘플 충분성** | 33 (regime_panel) → 5 (top-20 panel) | **WARNING** (informational) |
| **CRISIS alpha IC 음수** | composite -0.047 (CRISIS) | **WARNING** to Optimizer (informational) |

**objection**: TRUE (informational only — `RF-CRISIS-ALPHA-COUPLING` + `RF-CRISIS-THIN`)

**이의 내용**: 
1. 6F factor mix 자체는 도전하지 않음 (mandate 보존). 
2. **CRISIS regime에서 alpha 신호가 음수 IC** 인 점 + **Σ_CRISIS가 pooled Σ로 fallback** 되는 점이 결합되면, regime-Σ MinCVaR만으로는 CRISIS 방어가 약함. Optimizer가 (a) confidence_vector를 regime별로 scaling하거나 (b) CRISIS 라벨링 시 alpha 의존도를 자동 축소하거나 (c) PG2 book의 STR_1656 sleeve(20%)를 유지하는 구조가 필요.
3. 이 challenge는 **alpha 설계 변경**을 요구하지 않으며 (alpha 6F는 Core 성격으로 명시됨), Optimizer가 받아 처리할 정보임.

**round = 1** (challenge_history 첫 진입). round ≤ 2 한도 내.

---

## 4. Red flags + Challenge flags (요약)

| ID | severity | 내용 |
|---|---|---|
| RF-R_CRISIS-THIN | HIGH | CRISIS top20-panel T=5 → pooled Σ fallback. δ=0.91. |
| RF-R3-crowding | MEDIUM | vol_z>2.5 (2026-04-25) 2건 (단일 dt, 일관성 낮음 — 주의 정도) |
| RF-R4-stress | HIGH | GFC EW basket -43.5% (Optimizer가 weight 적용으로 완화 기대) |
| RF-CRISIS-ALPHA-COUPLING | MEDIUM | alpha CRISIS IC -0.047 + Σ pooled fallback → Optimizer 보수화 권고 |

발화 안 됨:
- RF-R1 (PC1 share 25.9% < 40%) — 정상
- RF-R2 (pooled cn 24.9 < 500) — 정상 (CRISIS 단독은 발화하나 fallback으로 흡수)
- RF-R5 (factor 간 ρ > 0.8 pair) — Ω off-diag 모두 안정

---

## 5. PIT Compliance (C1~C15)

| 코드 | 상태 | 근거 |
|---|---|---|
| C1 | PASS | per-regime Σ는 expanding label 이후 추정. Pooled은 train window 내. full-sample 통계 비교 없음. |
| C2 | PASS | regime label 자체가 alpha-side에서 t-1 lag 적용된 것을 그대로 사용. |
| C9 | PASS | daily ret과 monthly regime label은 month-floor join. same-day VT/DD 구조 없음. |
| C11 | PASS | KR RAWDATA + KR benchmark + 알파 측 KR internals만 사용. FRED leak 0. |
| C13 | PASS | Z_Score_Aligned 사용은 alpha agent 책임. Risk는 raw return만 다룸. |
| C14 | PASS | IC time-axis 위반 없음. Σ는 Ret_1m post-listing 위에 계산. |
| C15 | PASS | RAWDATA parquet cache 경유. |

---

## 6. Optimizer Handoff (역할 분리 명시 — Common Charter §8)

```
INPUT (Optimizer 단계):
  alpha_package.json (alpha_vector, confidence_vector, regime label per sig_date)
  risk_package.json (Σ method, shrinkage 강도, fallback 정보, challenge_flags)
  covariance_per_regime.parquet (BULL/NORMAL/CAUTION/CRISIS/POOLED 5 Σ)
  tail_risk.json (per-regime CVaR / TDC / MDD)
  regime_transition_cost.json (3.93 switches/year, transition matrix)

DECIDED BY Optimizer (NOT Risk):
  - Regime-Σ MinCVaR formulation (objective + constraints)
  - turnover penalty calibration (regime switch ~4/yr proxy)
  - max_weight bounds [0, 0.20] enforcement
  - Kelly_frac vs MinCVaR comparison
  - CRISIS confidence scaling 처리
  - Σ_r 선택 vs pooled Σ 폴백 정책
  - portfolio DSR / SR / IR 측정
```

Risk Agent는 Optimizer의 어떤 결정에도 silent override를 행하지 않았음.

---

## 7. 다음 단계

- 상태 전이: ALPHA_DONE → **RISK_DONE** (status.json 업데이트 완료)
- artifact_lineage.json 추가 (method=ledoit_wolf_constcor_per_regime, seed=20260425, 입력 hash 3건)
- Optimizer Agent spawn 가능 — `qepm/mailbox/worktask/WT-D20260425_007/risk_package.json` 수신해 weight 결정.

---

**Risk Agent: RISK_DONE 전이 완료. Optimizer Agent spawn 대기.**
