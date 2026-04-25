# Challenge Note — WT-D20260425_007 MEGA_05 Regime-Σ MinCVaR (Iter 2)

작성: Alpha Research Agent | 2026-04-25
Common Charter Principle 8 (No Silent Override) 준수.

---

## 1. Iter 2 mandate vs Alpha Agent 권한 경계

**유지**: factor mix (C01_SUE + C04_ESBR + C02_EPS_Chg_1m + C06_TP_Gap + Q07 + AC21) — MEGA_05 PRIMARY 그대로.
**추가**: regime indicator (BULL / NORMAL / CAUTION / CRISIS) — alpha source의 일부 (예외 조항: 가설이 국면을 alpha로 사용).
**금지** (alpha agent 영역 밖): regime-conditional Σ 추정, MinCVaR weight 결정, Kelly_frac 비교, LW_constcor 교체. → Risk + Optimizer 영역.

Alpha 산출물은 **regime label per sig_date + conditional IC matrix** 까지. 이후 Σ / weight는 Risk(WT_007 risk_package) + Optimizer가 결정.

---

## 2. 핵심 발견 (Diagnostics)

| 지표 | 값 | 비고 |
|---|---|---|
| Overall rank_IC | 0.0489 | MEGA_05 baseline 동일 (factor mix unchanged) |
| Overall ICIR | 0.602 | Alpha Lab Gate 0.20 통과 |
| Harvey_t | 9.35 | t>3.0 통과 |
| Subperiod stability | 0.418 | <0.5 (RF-A1 borderline; baseline 동일) |
| Monotonicity | 0.939 | 강함 |
| DSR (R14 bootstrap) | 0.0007 | n_trials=5 단일 alpha → DSR 보수적 / Optimizer 단계 portfolio DSR 별도 산출 권장 |
| Turnover proxy | 6.45 (annualized churn 0.54) | Top-20 churn 기반 — Optimizer가 cost penalty 처리 |

### Composite IC by regime (conditional)

| Regime | mean IC | sd IC | ICIR | n_months |
|---|---|---|---|---|
| BULL | 0.0622 | 0.081 | 0.772 | 84 |
| NORMAL | 0.0473 | 0.082 | 0.576 | 127 |
| CAUTION | 0.0319 | 0.070 | 0.452 | 25 |
| CRISIS | -0.0466 | 0.057 | -0.818 | 5 |

**해석**:
- BULL/NORMAL에서 alpha 강도 양호. NORMAL ICIR 0.576은 Optimizer가 regime-Σ로 분리 최적화할 만한 충분한 신호.
- CRISIS에서 composite IC가 음수 — 이는 6F의 Core 성격(C-pref 4F + AC21) 때문이며, defense 역할이 약함. **Optimizer가 CRISIS regime에서 Σ 보수화 + max_weight tighten + crisis_alpha 의존도 축소를 고려해야 함.**
- CRISIS n=5만 → conditional IC 통계 변동성 크다. Risk Manager의 stress / EVT / DCC 분석에서 보강 필요.

### Per-factor by regime (highlight)

- **AC21_CF_to_Accrual_Ratio**: 모든 regime에서 양의 IC (BULL 0.0607, NORMAL 0.0467, CAUTION 0.0465, CRISIS 0.0302). **regime-robust** core diversifier.
- **Q07_Earnings_Stability**: CRISIS에서 가장 강함 (mean_IC 0.0569, ICIR 0.555) — L-121 재확인.
- **C06_TP_Gap**: CRISIS에서 mean_IC 0.0573 (ICIR 0.872) but BULL에서 -0.026 → regime-conditional 효용. NORMAL ICIR 0.10으로 매우 약함.
- **C01_SUE / C02_EPS_Chg_1m**: CRISIS에서 음수 IC — surprise/revision은 정상 회복 시 작동, 위기 진입 단계에서는 탐욕 신호로 변질될 수 있음 (해석: analyst revision lag).

→ Risk/Optimizer 단계에서 **regime-conditional Σ + MinCVaR**이 conditional IC의 비대칭성과 정합. Iter 2 가설(Optimizer 교체로 NORMAL SR 1.30+ 달성)을 alpha 신호 측면에서 **데이터적으로 뒷받침**함.

---

## 3. Regime indicator design (PIT 준수)

```
features (all built at month_end_t, applied at sig_date_{t+1}):
  rv60       = sd(BM_Ret over last ~60 trading days) * sqrt(252)
  ret_1m     = product return over last ~21 trading days
  dd_12m     = max drawdown over last ~252 trading days
  breadth60  = mean cross-section %{Ret>0} over last ~60 trading days  (KR internal — L-454)

score (higher = more crisis-like):
  s = 0.35 * pct(rv60) + 0.25 * pct(-ret_1m)
    + 0.25 * pct(-dd_12m) + 0.15 * pct(-breadth60)
  pct() = expanding percentile (strictly past data, C1)

state (expanding quantile thresholds):
  BULL    if s <= q_30
  NORMAL  if q_30 < s <= q_65
  CAUTION if q_65 < s <= q_85
  CRISIS  if s >  q_85
```

PIT 검증:
- C1: expanding percentile만 (no full-sample). 첫 12개월은 NORMAL 기본값.
- C2: regime built at month_end_t → applied at first day of (month_end + 1) → 1M lag.
- C9: rv/dd/breadth window 종료점이 month_end_t (포함), apply는 다음 월 → same-day circular 없음.
- C11: KR benchmark + KR cross-section breadth만 사용 — FRED leak zero.

Train window 분포 (1990-02 ~ 2024-01-22, n=408): BULL 158 / NORMAL 143 / CAUTION 66 / **CRISIS 41**.

---

## 4. Red Flags (challenge_flags)

| ID | severity | 내용 |
|---|---|---|
| RF-A1 | HIGH-borderline | subperiod stability 0.4183 < 0.5 (MEGA_05 baseline 그대로 — factor mix 보존 mandate) |
| RF-REGIME-SAMPLE | MEDIUM | CRISIS n=41 (regime panel) / n=5 (composite IC의 train 결합) — conditional IC 통계 변동성 크다. **Risk Manager EVT/DCC stress test 필수**. |
| OPT-HANDOFF | INFO | Alpha는 regime label만 제공. Σ/weight 결정은 Optimizer 단독 책임. **Common Charter 원칙 8** 명시. |

추가 자기 도전 항목:

- **RF-A4 (post-neutralization IC)**: alpha agent는 sector/size neutralization을 적용하지 않음 (factor mix preserved 원칙). Risk/Judge 단계에서 FF3/FF5 retention 확인 필요.
- **CRISIS 회피 미작동 위험**: CRISIS에서 composite mean_IC -0.047 → Optimizer가 CRISIS에서 6F α̂를 그대로 사용하면 손실 가능. **MinCVaR가 CRISIS Σ에서 보수화하는 것 만으로는 불충분**할 수 있음. Optimizer가 regime별 max_weight cap, exposure scaler, 또는 crisis_alpha sleeve 추가를 검토하도록 challenge.
- **NORMAL SR 1.30 달성 가능성**: NORMAL ICIR 0.576 + composite IC 0.0473 → 동일한 alpha 신호 위에서 Optimizer 교체만으로 SR 1.193 → 1.30 (gap 0.107) 달성은 **Σ 추정 quality 개선분에 의존**. Risk Manager가 LW vs DCC vs Gerber 비교, MinCVaR가 Kelly_frac05 대비 turnover/concentration 효과 정량화 필요.

---

## 5. Optimizer handoff contract (역할 분리 명시)

```
INPUT to Risk Agent:
  alpha_scores.parquet [sig_date, Ticker, Score, Ret_1m, regime_state, theta_json]
  regime_panel.parquet [sig_date, regime_state, regime_score, rv60, dd_12m, breadth60, ret_1m_bm]
  conditional_ic_factor_regime_wide.parquet  (regime × factor mean_IC)

DECIDED BY Risk Agent (NOT Alpha):
  - regime-conditional covariance Σ_r (DCC / LW / Gerber 자유 선택)
  - tail risk metrics (CVaR / CDaR / EVT)
  - regime stress test
  - factor common-risk decomposition (B Ω B' + D)

DECIDED BY Optimizer (NOT Alpha):
  - MinCVaR optimization formulation
  - regime-Σ vs blended-Σ 선택
  - Kelly_frac vs MinCVaR comparison
  - turnover/cost penalty calibration
  - max_weight bounds [0, 0.20] enforcement
```

Alpha agent는 위 의사결정에 어떤 silent override도 행하지 않았음.

---

## 6. Graduation gates (current vs threshold)

| Gate | value | threshold | pass |
|---|---|---|---|
| rank_IC | 0.0489 | 0.04 | PASS |
| ICIR | 0.602 | 0.20 | PASS |
| Harvey_t | 9.35 | 3.0 | PASS |
| Sub stability | 0.4183 | 0.5 | **FAIL (borderline)** |
| DSR | 0.0007 | 0.5 | FAIL (single alpha bootstrap caveat — portfolio DSR Optimizer 단계 별도) |

→ MEGA_05 baseline 그대로의 한계. Iter 2 가치는 **regime label addition** + Optimizer 교체에 의한 portfolio-level SR 개선 가능성에 있음. Alpha 단독으로는 Iter 1과 동일.

---

## 7. 권고 사항 (Risk / Optimizer 참고용 — Alpha 권한 외)

1. **Risk Manager**: regime-conditional Σ를 LW(constcor) vs DCC vs Gerber 3-way 비교. CRISIS regime은 n=5 thin이므로 shrinkage intensity 강화 고려.
2. **Optimizer**: MinCVaR는 regime별 Σ + regime별 confidence_vector scaling 고려. CAUTION/CRISIS에서 alpha confidence 자동 감소 (alpha_package.confidence_vector 활용).
3. **Governor**: Iter 1 (WT_003) vs Iter 2 (WT_007) PG2 admission 비교 시 regime-conditional SR 분포 (NORMAL 1.30+ 달성 여부)를 핵심 지표로.

---

**Alpha Agent: ALPHA_DONE 전이 완료. Risk Agent spawn 대기.**
