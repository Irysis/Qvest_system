# WT-D20260514_013 (PENDING — 도훈 explicit go-ahead 필요)

**Status**: PRE-DRAFT, NOT YET LAUNCHED
**Reason**: agent spawn is destructive (compute + Codex Round 5단계 + risk-research/optimizer-research/forge/judge/governor agent chain). 도훈 explicit "alpha-research spawn 진행" 명시 후 실행.

## 목적

Sequential Admission FINAL admit cycle for **Path B Hybrid** — L-323 #3 + #4 supplement에서 발견한 마일스톤 5축 동시 안전 margin 달성 candidate.

### Candidates (2종 후보, 도훈 결정 필요)

| Spec | Blend SR | CAGR | MDD | TO_yr | Pareto cor |
|---|---|---|---|---|---|
| **M5_LGB top-30 bi-monthly 40%** + STR_1715 60% | 2.100 | 39.90% | -14.22% | 3.24 | -0.206 |
| **M6_Ensemble top-30 bi-monthly 40%** + STR_1715 60% ⭐⭐ | **2.263** | **44.82%** | -15.31% | 3.27 | -0.186 |

**Recommendation**: **M6_Ensemble** — ensemble robustness (rank-avg of 5 base models, single-model overfitting risk 분산) + SR 0.16 우월 + CAGR 4.9pp 우월. MDD trade-off 1pp (M5 -14.22% vs M6 -15.31%) negligible.

## Spec Highlights

- **wt_type**: discovery_to_deployment_blend (book_state v2.3 → v2.4 mutation)
- **graduation criteria**: SR ≥ 2.0 (PerformanceAnalytics standard) + MDD < -25% + TO ≤ 6.0/yr + Pareto cor < 0.40 + AX-008 ≥ 2/3
- **components** (도훈 selection 1순위 M6 Ensemble):
  - Existing: STR_1715_AR_on_M4_R05_PG2 (w=0.60, layer-5 sequential overlay)
  - Proposal: **M6_Ensemble_bi-monthly_top30** (w=0.40, ML rank-avg ensemble of 5 base models, Kelly Virtue 2024)
- **expected metrics (60m sample, must verify on 255m + Phase 1.B M7 + uncertainty discount)**:
  - **SR 2.263 / CAGR 44.82% / MDD -15.31% / Pareto cor -0.186 / eff_TO 3.27**

## Lifecycle 의무 (Codex Round 5단계 × 6 agents)

1. **alpha-research**: M5_LGB_bi-monthly_top30 alpha_package + Codex Round
2. **risk-research**: Σ + crowding_score_per_factor (P5 Phase 2.C 신규 정합) + Codex Round
3. **optimizer-research**: blend weights {0.40, 0.60} validate + Codex Round
4. **forge**: 255m PerfA standard backtest + 10-component bt_result + Codex Round
5. **judge**: Gate 0~5 + lockbox audit + Codex Round
6. **governor**: PG2 admission concord_certificate + book_state v2.4 mutation

## Prerequisites (필수)

- ✅ WT-D20260514_010 Full ML cycle GRADUATING (L-321)
- ✅ Phase 1.A/1.B implementation (L-322)
- ✅ Pareto cor measurement (L-323 #1/#2/#3)
- ⏳ **WT-D20260514_012 Phase 1 full run completion** (M7 cost-aware turnover 정량 검증)
- ❓ 도훈 explicit go-ahead

## 결정 후속

도훈 review 후:
- "go" → request.json finalize + alpha-research agent spawn
- "wait" → Phase 1 full run 추가 분석 후 재검토
- "modify" → spec amend (e.g., w_ML, top-N, rebalance freq 조정)

---

**L-323 #1 + #2 + #3 reference**: methodology_active.md
**Status as of 2026-05-14**: PENDING (도훈 review)
