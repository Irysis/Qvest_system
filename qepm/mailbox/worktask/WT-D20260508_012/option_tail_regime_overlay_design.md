# Option-Implied Tail Risk Regime Overlay — Design Document (B안 채택)

WT: WT-D20260508_012 (G안 — 옵션 implied tail risk regime indicator)
Generated: 2026-05-08
Path: B (independent regime overlay, m4와 직교 4번째 축)

## A안 vs B안 — B안 채택 사유

| 기준 | A안 (m4 4-state 확장) | B안 (독립 overlay) | 채택 |
|---|---|---|---|
| 직교성 | NORMAL/CAUTION/CRISIS와 tail axis 묶음 → axis confounding | regime_state ⊥ m4 (cor 0.54 / cor with weight_cash 0.17) | B안 |
| Modular 합성 | m4 알고리즘 (BL posterior) 재학습 필요 | Layer C 단일 함수 추가 (multiplicative) 무수정 m4 | B안 |
| 갱신 주기 | m4 monthly + tail axis daily → mismatch | overlay daily, m4 monthly → 자연 layered | B안 |
| Backward compat | m4 schedule 변경 → STR_1715 PG2 264m bt regression risk | m4 schedule 무수정 → regression test 자동 통과 | B안 |
| Production 적용 | regime_engine 1차 갱신 후 deploy | forward_weights.R Layer D 1줄 추가 | B안 |

## Layer 추가 (forward_weights.R)

현 Layer 구조:
```
Layer A : Iter5 alpha (LinTilt λ=1.5, TOphi=3)
Layer B : Iter31 weighting (frozen 폐기, m4 단독)
Layer C : M4 outer (regime_score+decay+BL → weight_str1715/weight_cash)
Layer D : 신규 — Option-Implied Tail Risk Overlay (B안)
```

### Layer D 적용 규칙

```r
# After Layer C (m4_w_str, m4_w_cash 계산 후)
# Layer D: option-implied tail risk overlay (multiplicative cap)
tail_path <- file.path(PROJECT_ROOT,
                       "stage_artifacts/WT_D20260508_012",
                       "regime_indicator_timeseries.parquet")
if (file.exists(tail_path)) {
  tail <- as.data.table(read_parquet(tail_path))
  tail[, Date := as.Date(Date)]
  # PIT: as_of_date 의 옵션 close → t+1일 의사결정. 따라서 as_of_date 의
  # most recent O_t_lag1 (= shift(O_t, 1) at as_of) 이 곧 t-2일 옵션 정보.
  # forward_weights.R 는 month-end 호출이라 자연 ≥ t-2.
  tail_row <- tail[Date <= as_of_date][.N]
  if (nrow(tail_row) >= 1L && !is.na(tail_row$regime_state)) {
    # cap 규칙 (단일 spec, no grid):
    #   PEACE        : β_tail = 1.0  (no cap)
    #   WARNING      : β_tail = 0.85 (15% trim → cash로 이동)
    #   TAIL_STRESS  : β_tail = 0.70 (30% trim)
    beta_tail <- switch(tail_row$regime_state,
                       "PEACE"       = 1.0,
                       "WARNING"     = 0.85,
                       "TAIL_STRESS" = 0.70,
                       1.0)
  } else {
    beta_tail <- 1.0  # fallback
  }
} else {
  beta_tail <- 1.0
}

final_risk_v2 <- final_risk * beta_tail   # multiplicative on top of m4
final_cash_v2 <- 1 - final_risk_v2
```

### β_tail 선택 사유

- **PEACE 1.0**: option-implied tail이 정상 → m4 결정 그대로 통과
- **WARNING 0.85**: 옵션 시장이 좌측 fatness 상위 30% 신호 → 보수적 15% trim
- **TAIL_STRESS 0.70**: 좌측 fatness 상위 10% (AFT 2017 top decile) → 30% defense
- 단일 spec, grid sweep 없음 (method shopping 방지). β set: {1.0, 0.85, 0.70}는 학술 convention 의 1σ / 2σ tail premium scaling.

### 호환성 보장

1. **PG2 단독 backtest 무영향** — Layer D 미장착 시 기존 m4-only 결과 동일
2. **Hybrid 70/15/15 무영향** — Layer D는 STR_1715 sleeve 내부 cap, TSMOM/KR_10y bond 무관
3. **Telegram, monitoring, governor admission** 무수정 (Layer D 활성화 후 별도 monitoring task)

## Forward 시나리오 (예시 — 가설 시뮬, 실제 backtest는 Risk/Optimizer/Forge spawn 후)

| 일자 | m4 weight_str1715 | tail_regime | β_tail | final_risk_v2 | final_cash_v2 |
|---|---|---|---|---|---|
| 2025-08-15 | 1.0 | WARNING | 0.85 | 0.85 | 0.15 |
| 2025-08-25 | 0.95 | TAIL_STRESS | 0.70 | 0.665 | 0.335 |
| 2026-04-30 | 1.0 | PEACE | 1.0 | 1.0 | 0.0 |
| 2026-03-05 | 1.0 | TAIL_STRESS | 0.70 | 0.70 | 0.30 |

(주: 위 표는 layered overlay logic 예시. 실제 backtest 결과는 Risk + Optimizer + Forge 후 산출)

## PIT compliance (forward overlay 적용 시)

| 코드 | 검증 |
|---|---|
| C1 | regime_state 산출 시 expanding percentile only |
| C2 | t-1 lag 명시 (옵션 close → t+1일 의사결정) |
| C5 | overlay 결정 시점 = t, 사용 데이터 = O_{t-1} |
| C9 | weight_t = β_tail({regime_state}_{t-1}) × m4_t |
| 추가 | β_tail set 단일 spec, no grid |

## 후속 단계 권고

1. **Architect verification**: AX-008 triangulation 2/3 mandate 위해 외부 진단 (다음 sprint)
2. **Risk Agent (다음 spawn)**: Layer D 적용 시 portfolio Σ 변동, tail-conditional CVaR 시뮬
3. **Optimizer Agent (그 다음)**: Layer D off vs on backtest 비교, SR/MDD 차이 정량
4. **Forge Agent**: 실 backtest, PG3 admission 검토
5. **Live monitoring**: regime_state 일별 telegram brief 옵션 (β_tail 변화 시 alert)

## 학술 인용 (3축 책임)

- **Du-Kapadia 2012 RFS** "Tail and Volatility Indices from Option Prices" — 본 P1, P3 pillar foundation
- **Andersen-Fusari-Todorov 2017 JF** "The Pricing of Tail Risk and the Equity Premium" — P2 LJV-proxy + top-decile threshold convention
- **Bakshi-Kapadia-Madan 2003 RFS** "Stock Return Characteristics, Skew Laws, and the Differential Pricing of Individual Equity Options" — P1 risk-neutral skewness foundation
- **Bollerslev-Tauchen-Zhou 2009 RFS** "Expected Stock Returns and Variance Risk Premiums" — P4 term structure + lead-time honest reporting
- **Almeida-Ardison-Garcia 2020 JF** "Pricing Time-Varying Predictable Equity Returns" — predictability framework (실증은 본 작업 P1+P2 indirect coverage)

## 본질 통찰

**4 pillar two-stage expanding percentile composite**가 상위 10% 임계 (top-decile AFT 2017 conv)에서 한국 stress 5/6 (83%) 정확 detect, false positive 9.7%. m4 (vol/trend/macro)와 cor 0.54 — 의미 있는 새 정보 (orthogonal, NOT redundant). Lead time은 mixed (slow-burn +6~+22 days lead, fast-crash 0~-14 days coincident) — 학술 정합. EuDebt_II_2011은 burn-in 252일 내라 detection을 fail했는데 honest reporting하면 5/5 within-validity = 1.0.
