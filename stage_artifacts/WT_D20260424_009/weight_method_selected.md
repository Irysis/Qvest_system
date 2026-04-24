# Weight Method Selection Report
## WT-D20260424_009 Pilot 11 — HRP 0.6 + Score 0.4 Frozen Hybrid

**Selection mode**: Q-Lead Override  
**Selected method**: HRP_0.6_Score_0.4_frozen_hybrid  
**Selection date**: 2026-04-24  
**Agent**: Optimizer Research Agent (claude-sonnet-4-6)

---

## 1. Q-Lead Override 배경

Pilot 4~10까지 10회 auto selection 모두 실패 (MinVar 후퇴 → ERC) 후, Q-Lead가 명시적으로 STR_1631 SYN_05 weight engineering 패턴을 지시. Auto selection 자율성 한계 인정 후 최적 판단.

**지시 내용**: STR_1631의 `0.6 × HRP + 0.4 × Score(t-1 frozen)` 패턴이 해당 전략의 Grade A 핵심인지 ablation. Pilot 9 alpha (Consensus RAPC v2) + Pilot 9 risk (LW Oracle cond 9.47)를 그대로 상속하여 optimizer method만 ERC → HRP+Score 교체.

---

## 2. Method Comparison (R13 Parallel, 5 cells)

| Method | net_IR | n_names | HHI | beta_port | max_w |
|--------|--------|---------|-----|-----------|-------|
| **HRP_0.6_Score_0.4** (PRIMARY) | **80.0464** | **20** | **0.0514** | **1.055** | **0.067** |
| ERC (Pilot 9 baseline) | 80.8040 | 20 | 0.0520 | 1.052 | 0.075 |
| Score_pure (HRP 0.0) | 79.8934 | 20 | 0.0517 | 1.045 | 0.068 |
| HRP_pure (Score 0.0) | 79.6322 | 20 | 0.0529 | 1.061 | 0.074 |
| MinVar_BetaSoft | 56.3383 | 7 | 0.1450 | 0.898 | 0.150 |

**Actually-best (net_IR 기준)**: ERC (80.8040) — Q-Lead override로 대체됨. 차이: 80.8040 - 80.0464 = 0.758 (0.94% 열위).

---

## 3. HRP vs Score 기여도 분해

| 구성요소 | alpha_port | HHI | beta | TE |
|---------|-----------|-----|------|----|
| HRP pure (0.6 비중 참고) | 3.1507 | 0.0529 | 1.061 | 0.0395 |
| Score pure (0.4 비중 참고) | 3.2421 | 0.0517 | 1.045 | 0.0405 |
| Hybrid 0.6+0.4 (실제) | 3.1872 | 0.0514 | 1.055 | 0.0397 |

**분해 해석**:
- Score가 HRP보다 alpha 0.0914 높음 (0.4 가중 → hybrid에 0.0366 기여)
- HRP의 clustering이 집중도를 약간 낮춤 (HHI 0.0529 → hybrid 0.0514)
- Hybrid beta는 두 순수 방식의 선형 중간값 (1.0547 = 0.6×1.061 + 0.4×1.045)
- Score contribution: 40% 비중이 alpha gap의 약 40% 기여 (예상과 일치)

**핵심 발견**: HRP와 Score의 alpha 차이가 미미 (0.0914). 두 방식 모두 동일한 top-20 universe에서 분산 최적화 → 지배적 차이는 clustering 기반 위험 분산 vs. alpha-proportional 배분. Hybrid가 두 가지를 균형.

---

## 4. Pilot 9 vs Pilot 11 비교

| 지표 | Pilot 9 (ERC) | Pilot 11 (HRP+Score) | 변화 |
|------|--------------|---------------------|------|
| net_IR | 26.1003 | 80.0464 | +206.7% |
| n_names | 16 | 20 | +4 |
| HHI | 0.0906 | 0.0514 | -43.3% |
| beta_port | 0.8842 | 1.0547 | +0.170 |
| max_w | 0.1505 | 0.0674 | -55.2% |

**주의**: net_IR 급상승은 동일 alpha/risk 패키지에서 universe 선발 차이에 기인. Pilot 9는 alpha_div_filter 후 16종목 집중 → Pilot 11은 20종 전체 균등 배분 → TE 감소 + breadth 증가.

---

## 5. 제약 준수 확인

- max_names: 20 / 20 (hard cap 충족)
- sum(w): 1.00000000 (Σw=1 충족)
- max_w: 0.067 <= 0.15 (weight bound 충족)
- HHI: 0.0514 <= 0.15 (cap 충족)
- long-only: 모든 weight >= 0 (충족)
- binding_constraints: 없음 (비구속)
- infeasibility_report: null

---

## 6. PIT 준수 확인

- **C2**: Score(t-1 frozen) — alpha_scores.parquet의 alpha_final이 이미 t-1 lag (alpha agent 확인)
- **C1**: 공분산은 36M rolling window LW Oracle (full-sample 통계 아님)
- 조용한 제약 완화: 없음 (HHI cap 0.15 여유 충분, infeasibility 없음)

---

## 7. Forge 핸드오프 메모

- Overlay: **없음** (Pilot 10 NEGATIVE 재확인, Pilot 12 예약)
- 측정 목적: HRP+Score hybrid weighting 순수 효과
- STR_1631 clone 회피: n=20 고정 (STR_1631은 자체 N_HOLD), overlay 없음
- benchmark_definition: KOSPI200_total_return
- cost_model: v2.3_kr_retail_15bps (15bps one-way)
- weights.csv: `stage_artifacts/WT_D20260424_009/weights.csv`

---

## 8. 방법론 근거 (Lopez de Prado 2016)

HRP는 Hierarchical Risk Parity로 상관관계 기반 클러스터링 후 재귀 이분법으로 위험 배분. 단일 역행렬 의존 MVO 대비 수치적 안정성이 높고, ill-conditioned 행렬에서도 robust. Score tilt는 alpha 신호를 포트폴리오에 직접 반영 (market-neutral 아닌 long-only 환경에서 alpha 손실 최소화).

STR_1631 SYN_05에서 이 조합이 Grade A (SR/CAGR/MDD 모두 통과)를 달성한 핵심 패턴으로 확인됨. Pilot 11은 해당 패턴이 alpha 독립적으로 작동하는지 검증.
