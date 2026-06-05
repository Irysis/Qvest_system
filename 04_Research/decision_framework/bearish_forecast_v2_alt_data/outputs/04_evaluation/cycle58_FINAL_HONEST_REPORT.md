# Cycle 58 Series — Final Honest Report (q15 / +21d Bear Probability)

**작성**: 2026-05-21 20:40 KST Q autonomous
**상태**: 7 cycles 완주 (58A → 58B → 58C → 58D → 58E → 58F → 58G)
**총 compute**: ~4 hours GPU + diagnostics
**전체 결론**: **statistical null** — 모든 통계 유의 진전 없음

## 1. 최종 Apples-to-Apples Leaderboard (15-seed standard)

| Rank | Method | PR-AUC | Δ vs Baseline | Paired Bootstrap |
|------|--------|--------|---------------|------------------|
| 1 | max(baseline, v5g) | 0.2601 | +0.0091 | NOT_SIG (P=0.88) |
| 2 | mean(baseline, v5g) | 0.2553 | +0.0043 | NOT_SIG (P=0.67) |
| 3 | **Baseline 57A v5f_FIXED** | **0.2510** | — | benchmark |
| 4 | v5g cross-market | 0.2476 | -0.0034 | NOT_SIG (P=0.41) |
| 5 | v5h interactions | 0.2261 | -0.0249 | marginal NEG (P=0.046) |
| 6 | v5i expanded (5-seed only) | 0.2174 | unreliable | REJECT |

## 2. 이전 보고 정정

### 잘못된 이전 보고:
- "58C v5h interactions PR-AUC 0.2762 sig +0.030 vs baseline ⭐"
- "58B cross-market features +0.035 ADDITIVE_STRONG"

### 진정 (apples-to-apples 15-seed):
- v5h interactions = 0.2261 (5-seed 0.2762 inflation -0.0501)
- v5g cross-market = 0.2476 (5-seed 0.273 inflation -0.0254)
- Baseline = 0.2510 (5-seed 0.2382 under-estimate +0.0128)
- 모든 비교 baseline 대비 NOT_SIG

### 잘못된 비교 원인:
58C aggregator가 **v5h 5-seed (0.2762) vs v5g 15-seed (0.2461)** 비교했음. 같은 n_seeds 정합 비교 시 v5h < v5g.

## 3. 5-seed Inflation 사례

| Cycle | 5-seed PR-AUC | 15-seed PR-AUC | Δ (drift) | Direction |
|-------|---------------|------------------|-----------|-----------|
| Baseline 57A | 0.2382 | 0.2510 | +0.0128 | UNDER |
| v5g cross-market (58C) | 0.273 | 0.2476 | -0.0254 | OVER |
| v5h interactions (58C) | 0.2762 | 0.2261 | -0.0501 | OVER (huge) |

**Pattern**: 5-seed measurements drift ±0.03-0.05 from 15-seed truth in random direction. Per-seed std ~0.045 → ΔPR-AUC < 0.05 statistically indistinguishable from noise.

## 4. Cross-cycle Spearman (interactions 가치 진단)

| Pair | Spearman ρ |
|------|------------|
| baseline & v5g | 0.468 (moderate diversity) |
| baseline & v5h | 0.393 (high diversity) |
| **v5g & v5h** | **0.977** (nearly identical) |

**Finding**: Interactions (v5h) 본질적으로 v5g raw cross-market 와 거의 동일 신호. 5 interactions이 새 정보 추가 안 함. ρ=0.977 = 4 cluster 분류 시 v5g + v5h가 같은 cluster (예전 진단의 cluster 5 = 사실 cluster 4 subset).

## 5. 7 Cycles 각 결과

| Cycle | 시도 | Verdict |
|-------|------|---------|
| 58A | 3-cycle ensemble (53H+53I+53B mean5) | INCONCLUSIVE |
| 58B | 7 cross-market raw 5-seed | "+0.035" 5-seed inflation |
| 58C | v5g 15-seed + v5h 5-seed + sig test | mismatched n_seeds bug |
| 58D | Meta-learner stacking (Ridge/XGB) | SIG_WORSE (-0.06) walk-forward |
| 58E | Expanded interactions (5→10) | REJECT (-0.06 5-seed) |
| 58F | v5h 15-seed validation | v5h SIG worse than v5g |
| 58G | Baseline 15-seed validation | baseline = 0.2510 (CEILING) |

## 6. Methodology Lessons

1. **5-seed PR-AUC UNRELIABLE for ΔPR-AUC < 0.05**. Sig tests MUST match n_seeds (apples-to-apples).
2. **Mismatched n_seeds 비교 = false positive winners** (58C 사례).
3. **Spearman correlation reveals feature value**. ρ > 0.95 = redundant.
4. **Per-fold variance massive** (0.07 to 0.47 across 4 folds) — regime-conditional behavior dominates.
5. **Cross-cycle ensemble simple methods (mean/max) NOT_SIG even with cluster diversity**. Real ensemble lift requires careful weighting.
6. **q15 PR-AUC ceiling ~0.25 plateau** for PatchTST + cross-market + KR macro + breadth + interactions features.

## 7. 가능한 진정 진전 경로 (도훈 의사결정 필요)

### Option A: 다른 Architecture (Mamba 15-seed on v5g panel) — ~3시간 GPU
- True different inductive bias (state-space vs Transformer)
- 정량 unknown — might break plateau OR confirm it
- Existing 164_mamba_5seed_strict.py adapt 가능

### Option B: 다른 label horizon (q63 → q15 ensemble) — ~5-7시간
- 도훈 q15 mandate 와 충돌 (재논의 필요)
- q63 더 예측 가능할 수 있음 (longer horizon = smoother signal)

### Option C: 다른 데이터 paradigm (options-implied / sentiment) — exploration
- 도훈 "텍스트 데이터 활용 안 함" mandate (DART text 제외)
- Options vol surface / put-call ratio = 가능
- 신규 data acquisition 필요

### Option D: Regime-conditional ensemble — 1-2시간
- m4 regime indicator (already used in STR_1715 overlay) 활용
- Fold 3 (CyprusTT, recent calm) v5h 0.47 vs baseline 0.21 ⭐
- Per-regime best model 선택 → ensemble
- 5-seed 학습 없이도 시도 가능 (existing 15-seed predictions)

### 추천 (Q autonomous, ROI 관점):
**Option D first (regime-conditional)** — existing predictions만 사용, 1-2시간 CPU work. Fold 3에서 v5h가 다른 모델 압도하는 정황 활용 가능.

만약 D도 NULL → **Option A (Mamba 15-seed)** 진정 architecture diversity 시도.

## 8. 도훈 의사결정 필요 사항

1. 위 4 options 중 어느 방향?
2. q15 mandate 유지? (Option B 풀려면 mandate 재논의)
3. 추가 자원 (alternative data) 확보 의향?

**Q stance**: 자율 mandate 유지 시 Option D + A 순차 launch 정합. 도훈 다른 mandate 시 즉시 전환.

---

## Appendix: 5-seed → 15-seed conversion factors

Empirical from 3 cycles measured:
- mean(|Δ|) = 0.029
- σ(Δ) = 0.020
- Direction = random (UNDER 1/3, OVER 2/3)

→ ΔPR-AUC ≥ 0.05 needed for any 5-seed claim to survive 15-seed validation.
→ ΔPR-AUC ≥ 0.10 needed for sig assertion at 5-seed level.

## Appendix: Reference baselines (5-seed era)

이전 보고 (5-seed inflation 미정정 상태):
- v1.3 C50 6-method: 0.1643
- v2 2-feat C43 best forward: 0.2129
- v4a C52 mean5: 0.2463
- 56A 53I_v5f mean5: 0.2356
- 57A 53I_v5f_FIXED 5-seed: 0.2382 → **15-seed: 0.2510**

15-seed 정합 비교 후 진정 ceiling **~0.25** 확인.
