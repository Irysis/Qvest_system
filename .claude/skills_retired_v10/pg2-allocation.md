<!-- ★RETIRED (v10 2026-09-02): PG2 슬리브 배분 가이드 — Governor·PG2 배분층 폐지 · 종목수 20(현행 25) · pg2_allocation() 은 legacy portfolio/portfolio_governor.R 에만 정의. v10 2계층 결합 정본 = strategy-rotation SKILL / dispatch-orchestrator. flat .md 라 Skill 로더 미노출이었음. 재열람 = git pre-v10-2layer -->
---
name: pg2-allocation
description: "PG2 슬리브 배분 시 적용 — Sleeve Assembly, EW→RP, regime-adjusted, 20종목"
---
## PG2 Sleeve Assembly & Allocation

### 호출
```r
alloc <- pg2_allocation("V7_ALLWEATHER_001", admitted_list)
```

### 배분 순서 (단순→복잡)
1. Equal Weight
2. Risk Parity
3. 최적화 (shrinkage + bounds + TO penalty 필수. unconstrained 금지.)
4. **CVaR LP** (Rockafellar-Uryasev, Pfaff Ch.12) — `calc_cvar_lp_weights()`
5. **CDaR 제약** (Chekhlov, Pfaff Ch.12) — `calc_cdar_weights()`
6. **MTD** (꼬리 의존성 최소, Pfaff Ch.11) — `calc_pmtd_weights()`
7. **Robust SOCP** (불확실성 집합, Pfaff Ch.10) — `solve_robust_socp_weights()`
8. **CVaR Parity** (위험기여 균등, Pfaff Ch.11) — `calc_cvar_budget_weights()`

### Regime 조정
| Regime | Core Alpha | Diversifier | Defense |
|--------|-----------|-------------|---------|
| RISK_OFF | -10% | -5% | **+15%** |
| CAUTION | -3% | -2% | +5% |
| NEUTRAL | 0% | 0% | 0% |
| RISK_ON | **+10%** | -5% | -5% |

### 규칙
- 총 종목수 **20개 이하** (멀티슬리브 포함, v53 신규)
- Core Alpha만으로 모든 목표 달성 시도 금지
- 한 family 전체 지배 금지 (max 35%)
