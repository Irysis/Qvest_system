# Cycle 58C Parallel Diagnostic — Prediction Diversity (Q autonomous)

**작성**: 2026-05-21 17:29 KST (Phase 2 진행 중, 자율 병렬 diagnostic)
**Source**: `cycle58c_prediction_correlation_diag.R` + `cycle58c_prediction_correlation_diag.json`

## 핵심 finding

12 mean5 q15 ensembles (OOS n=2039 dates) pairwise Spearman correlation 분석:

| Statistic | Value | Interpretation |
|-----------|-------|----------------|
| min | 0.16 | TRUE orthogonality 존재 |
| median | 0.60 | MODERATE diversity |
| mean | 0.62 | NOT 단일 cluster |
| max | 0.96 | 1쌍 redundant (53H_v5e vs 53H_v5e_FIXED) |
| pairs < 0.5 | 20/66 (30.3%) | architectural diversity 정량 입증 |
| pairs > 0.95 | 1/66 (1.5%) | 거의 redundancy 없음 |

## 4 distinct clusters (ρ>0.7 threshold)

| Cluster | n | Members | Identity |
|---------|---|---------|----------|
| 1 | 5 | 53B_v5b, 53H_v5e, 53I_v5f, 53H_v5e_FIXED, 53I_v5f_FIXED | pre-FIXED2 variants (FRED/BBVA contamination 잔존) |
| 2 | 1 | 54A_v3_patch7 | isolated (patch=7 unique architecture) |
| 3 | 3 | 54A_v4_dm32, 54A_v3_patch7_FIXED2, 54A_v4_dm32_FIXED2 | dm=32 family |
| 4 | 3 | 53B_v5b_FIXED2, 53H_v5e_FIXED2, 53I_v5g_cross_market | post-cleanup + cross-market |

## 최저 상관 pair (TRUE orthogonality)

- **53H_v5e vs 54A_v3_patch7_FIXED2**: ρ = 0.16 ⭐
- 53I_v5f_FIXED vs 54A_v3_patch7_FIXED2: ρ = 0.20
- 54A_v4_dm32_FIXED2 vs 53I_v5f_FIXED: ρ = 0.27

## 가설 정정

**이전 가설 (REJECTED)**: "모든 cycle PatchTST family이므로 systematic error 상관 → 단일 cluster"
- 실제 측정 mean ρ = 0.62 (NOT > 0.7)
- 4 clusters 확인 → **homogeneity 가정 틀림**

**수정 가설 (DATA-DRIVEN)**: Cross-cycle simple mean이 약한 이유:
1. Noisy 모델 weight 동등 → signal-to-noise 희석 (simple mean의 한계)
2. Cluster 내 redundancy 와 cluster 간 diversity 동등 취급 → effective diversity 손실
3. **Solution = stacking (meta-learner)** — cluster representative 1건씩 골라 XGB/Ridge로 가중 학습

## 58D direction (proposed autonomous next)

**Cycle 58D recommendation: STACKING_META_LEARNER**

Cluster representatives (best PR-AUC within cluster):
- Cluster 1: 53I_v5f_FIXED (FRED-fixed pre-BBVA)
- Cluster 2: 54A_v3_patch7
- Cluster 3: 54A_v3_patch7_FIXED2 (best dm=32 with cleanup)
- Cluster 4: 53I_v5g_cross_market (best post-cleanup) — current headline 0.2730

Meta-learner: Ridge or XGB (regression with log-loss).
- 입력 X = 4 cluster representative predictions (per-date probability)
- 출력 y = y_tail_q15 binary
- CV = walk-forward (purged), same as base models
- Hold out test period = same OOS
- Compare to current best 0.2730

Expected delta: +0.02~0.05 PR-AUC if cluster diversity truly orthogonal.

## 58C Phase 5 직후 launch 예정

- Phase 2 (191 v5g 10-seed) 완료 후
- Phase 5 (194 aggregator) 결과 종합 후
- 위 4 representatives 확정 → 58D launch

## L-code 후보 (Cycle 58 시리즈 마감 시 적립)

**L-XXX (Cycle 58 종료 후 후보)**: Cross-cycle simple mean ensemble은 cluster
homogeneity 가정에 기초. 실제 4 cluster 존재 시 → meta-learner stacking이
정합 경로. 이전 "cross-cycle ensemble 약함" 가설 → "simple mean 약함" 정정.
mean ρ=0.62 / 20 pairs < 0.5 / lowest ρ=0.16. Reference: cycle58c diagnostic.
