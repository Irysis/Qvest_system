# v3 Algorithm Shortlist — Phase 5 Implementation Spec

**작성**: 2026-05-24 KST Session 84 (Phase 3)
**Owner**: Q-Lead / 도훈 mandate
**Source**: `PLAN.md` v0.5 + `paper_summary.md` + `paradigm_matrix.md` + `AMENDMENT_v0.5.md`
**상태**: Phase 3 산출물 2/2 — **Phase 5 implementation entry baseline**

---

## Lock-in (도훈 mandate 2026-05-24 + AMENDMENT_v0.5 confirmed)

| Component | Paradigm | Lock-in 이유 | Phase |
|---|---|---|---|
| **★ Primary: B1 LSTM × skewed-t** | B | KR 직접 검증 paper (B1 KOSPI 2025 LSTM-SSTD best CRPS 0.5165) | **5a-1** |
| **★ Primary: B5 NGBoost** | B | Boosting + 분포 parameter (도훈 ensemble 의도 핵심) | **5a-2** |
| **Tier 4 Ensemble: B1 + B5 + A + F + C Linear Pool** | B+A+F+C | Full Paradigm Mixture 도훈 mandate | **5d** |

---

## Phase 5 Implementation Order

### Phase 5a-1 — B1 prototype (LSTM × skewed-t)

**Spec (paper actual, AMENDMENT_v0.5 CR-V02)**:
```python
# Architecture (paper Table 1 + Figure 1)
LSTM_layer_1: hidden=128
LSTM_layer_2: hidden=64
LSTM_layer_3: hidden=32
Dense: units=p   # p ∈ {2 (Normal), 3 (Student-t), 4 (skewed-t)}

# Training (paper)
sequence_length = 10        # paper baseline (NOT 60-120)
optimizer = Adam(lr=0.002)
weight_decay (L2) = 0.002
dropout = 0.02
batch_size = 128
epochs = 300 + early_stopping_on_loss

# Window protocol (paper walk-forward expanding)
train_min = 1008
test = 504
expand_step = 504

# Loss (custom NLL, Fernandez-Steel transform for skewed-t)
L(ω) = -(1/n) Σ_t log f_D(r_t; ω)
D ∈ {Normal, Student-t, skewed-t}
```

**Reproduce baseline expected** (paper Table 2 KOSPI):
- LSTM-SSTD: LPS=1.2847, CRPS=0.5165 (best)
- LSTM-STD: LPS=1.2961, CRPS=0.5201
- LSTM-N: LPS=1.3240, CRPS=0.5246

**Reproduce 통과 기준**:
- 6 model 학습 (CNN-N/STD/SSTD + LSTM-N/STD/SSTD) on KOSPI data 2000-2021
- LSTM-SSTD CRPS < 0.520 (paper ± 1% tolerance)
- LSTM > CNN ordering (sequential pattern advantage)
- PIT histogram visualization (KOSPI reject 예상, but skewed-t > Normal calibration)

**Feature**: v2_alt_data 60 features inherit (audit 후) — paper는 returns + volatility만, v3는 alt data 추가 (시도)

**Failure trigger (Lock-in 재검토)**: LSTM-SSTD CRPS > 0.525 OR PIT calibration 명시적으로 N > SSTD (paper opposite)

---

### Phase 5a-2 — B5 NGBoost prototype

**Spec (paper Section 4 hyperparameter sweep)**:
```python
# NGBoost configuration
distribution ∈ {Normal, LogNormal, Laplace, Exponential, **skewed-t custom (v3 신규)**}
base_learner = DecisionTreeRegressor
tree_depth ∈ {3, 4, 5, 6}
n_estimators ∈ {500, 1000, 2000}
learning_rate ∈ {0.001, 0.01, 0.1}
minibatch_frac ∈ [0.5, 1.0]
natural_gradient = True (paper Section 3.2 정합)

# Stage 1 baseline: distribution=Normal, depth=4, n_est=500, lr=0.01

# 시계열 처리 (v3 신규, AMENDMENT CR-V04)
purging = True
embargo_days = 21
cv_splits = 5_walk_forward
```

**Skewed-t custom implementation 요구사항**:
- ngboost.distns.Distribution base class extend
- Fernandez-Steel 1998 4-parameter (μ, σ, ν, ξ)
- log-likelihood + d_log_likelihood/d_θ + Fisher Info I_L(θ)
- Score: log score (NLL) primary, CRPS secondary

**v3 신규 KR equity 적용**:
- ❌ paper에 KR/금융 검증 없음 — v3가 first
- Feature: v2_alt_data inherit + lagged returns + RV
- Target: KOSPI200 21-day forward return distribution
- Validation: walk-forward purged 5-fold (Lopez de Prado 2018)

**Baseline (Stage 1) 통과 기준**:
- Normal distribution + depth=4 NGBoost val NLL < SAFE_THRESHOLD (TBD by reproduction)
- Walk-forward CV stable (per-fold CRPS std < 0.05)
- Feature importance interpretable (top 5 economically rational)

**Failure trigger**: NGBoost val CRPS > LSTM-SSTD val CRPS + 5% (significant inferiority)

---

### Phase 5a-3 — B1 vs B5 비교 + within-B Linear Pool

**비교 metrics**:
- val CRPS (primary)
- val NLL
- PIT calibration (Christoffersen-style histogram + chi-square test)
- VaR 95% / 99% backtest (Kupiec + Christoffersen, paper E5)
- DM test (HAC lag ≥ 21, paper E6)
- Spearman ρ(B1, B5) — diversity check (target < 0.80)

**Within-B Linear Pool** (Geweke-Amisano 2011):
```
w_B1 = 1/val_CRPS_B1
w_B5 = 1/val_CRPS_B5
w_B1, w_B5 ← w_i / (w_B1 + w_B5)
F̂_B_ensemble = w_B1 · F̂_B1 + w_B5 · F̂_B5
```

**Stage 2 통과 기준**:
- B1 vs B5 val CRPS diff < 10% (둘 다 valid candidate)
- Spearman ρ < 0.80 (diversity confirmed → ensemble 의미)
- Within-B Linear Pool CRPS < min(B1, B5) (ensemble 효과 입증)

---

### Phase 5b — Conformal post-hoc (F1)

**Algorithm 선택**:
- **ACI (Adaptive Conformal Inference)** primary — KR regime switching (bull→bear) 강건 (F1 paper §3.3 mean shift result)
- **EnbPI alternative** — bootstrap ensemble base if compute available
- **WCP-exp fallback** — cheap + robust

**ACI hyperparameter**:
- α target = 0.05 (95% VaR)
- γ ∈ {0.005, 0.01, 0.05, 0.10} — adaptive sensitivity
- Calibration window: rolling 504 days (matches B1 test window)

**Phase 5b 통과 기준**:
- ACI long-run coverage ∈ [0.045, 0.055] (target 5% strict)
- Width < B1 raw 95% PI width × 1.5 (efficiency)
- KOSPI bear date (Lehman 2008, COVID 2020) breach handle 명확

---

### Phase 5c — LASSO Quantile baseline + Tier 3 Linear Pool

**LASSO Quantile Regression (Paradigm A spec)**:
```python
# τ-quantile loss + L1 penalty
β̂(τ) = arg min_β Σ_t ρ_τ(y_{t+h} - x_t' β) + λ ||β||_1
ρ_τ(u) = u · (τ - 𝟙{u<0})

# Multi-τ joint estimation
τ ∈ {0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95}
```

**Adrian-style GaR (Eq 1 paper A1)**:
- Predictor: v2_alt_data features (incl. KOSPI vol proxy + KR credit spread + KRW vol — KR NFCI proxy)
- Target: y_{t+21} KOSPI return 21-day forward

**Tier 3 Linear Pool**:
```
F̂_Tier3 = w_B · F̂_B_ensemble + w_A · F̂_A_GaR + w_F · F̂_F_conformal
```

**Phase 5c 통과 기준**:
- LASSO Quantile val pinball loss reasonable (sanity check baseline)
- A vs B vs F per-component diversity (Spearman pair-wise < 0.80)
- Tier 3 Linear Pool CRPS < min(individual) (ensemble 효과)

---

### Phase 5d — Tier 4 Full Paradigm Mixture (Neural Lévy + 5-component)

**Neural Lévy SDE C2 component**:
- Architecture: shared encoder 2 hidden × 64 + multi-h heads (1D / 21D primary)
- Jump distribution: Merton (Gaussian mix) baseline, Kou (double exp) alternative
- Trading: ❌ paper Sharpe ≈ 0 — **v3는 forecast component only, trading rule 별도** (AMENDMENT E10 lesson)

**Tier 4 Linear Pool**:
```
F̂_Tier4 = Σ_i w_i F̂_i,   i ∈ {B1, B5, A_GaR, F_conformal, C_Lévy}

Diversity Mandate (PLAN.md v0.5 §5.4.4):
  pair Spearman ρ(F̂_i VaR_95, F̂_j VaR_95) < 0.80 strict
  
Weight (Geweke-Amisano):
  w_i = (1/val_CRPS_i) / Σ_j (1/val_CRPS_j)
  
Stacking 배제 (v2 58D lesson)
```

**Phase 5d 통과 기준**:
- 5 components 모두 individual val CRPS < simple baseline
- 10 pair Spearman ρ all < 0.80
- Tier 4 ensemble val CRPS < Tier 3 (additional jump value)
- DM test sig (Tier 4 vs Tier 3, p < 0.05)

---

## Phase 5 Entry Criteria 종합 (AMENDMENT_v0.5 CR-V01~V06)

체크리스트 — Phase 5a-1 시작 전 ALL PASS 의무:

- [x] **CR-V01 Plan v0.5 amendment 도훈 confirm** — ✅ 2026-05-24 Session 84 GO
- [ ] **CR-V02 B1 Phase 5a-1 baseline = paper actual (3-layer 128/64/32, seq=10)** — Phase 5a-1 코딩 시 적용
- [ ] **CR-V03 Hyperparameter expansion = paper baseline reproduce 우선** — Phase 5a Stage 1 → 2 protocol
- [ ] **CR-V04 NGBoost 시계열 = purging/embargo 5-fold CV 명시** — Phase 5a-2 spec 적용
- [ ] **CR-V05 Linear Pool weight = per-component val CRPS 의무 보고** — Phase 5a-3 / 5c / 5d 의무
- [ ] **CR-V06 Paper-cite 정량 = paper-direct verification or ACCESS_FAIL 명시** — 모든 phase 의무 (memory `feedback_paper_cite_verification.md` recurring)

Cycle 51 lesson (PLAN.md v0.5 §3.2):
- [x] bear_date_audit 4/4 PASS — 2026-05-24
- [x] validate_label_direction PASS — 2026-05-24
- [ ] data_table_shift_convention 정합 — Phase 5 코드 review 시
- [ ] AX-008 Verification Triangulation — Phase 5a-1 결과 검증 시

---

## Compute Cost 추정 (PLAN.md v0.5 §5.2 갱신)

| Phase | Component | Cost | Cum |
|---|---|---|---|
| 5a-1 | B1 LSTM 6 model × 100 trial (Stage 1) | 200-300h GPU | 200-300h GPU |
| 5a-1 | B1 LSTM Stage 2 top 5 × 15 seed | +50-75h GPU | 250-375h GPU |
| 5a-2 | B5 NGBoost 5 dist × 100 trial | 17-50h CPU | 250-375h GPU + 17-50h CPU |
| 5a-2 | B5 Stage 2 top 5 × 15 seed | +5-15h CPU | + 22-65h CPU |
| 5a-3 | B1 vs B5 비교 + within-B ensemble | <1h | + |
| 5b | Conformal ACI/EnbPI post-hoc | <1h CPU | + |
| 5c | LASSO Quantile GaR + Tier 3 LP | <2h CPU | + |
| 5d | Neural Lévy + Tier 4 LP | 10-20h GPU | + |
| **Total** | | **~260-395h GPU + ~22-67h CPU** | |

**v3 plan timeline (PLAN.md v0.5 §5.2)**:
- Phase 5 누적 14-23h GPU + 17-50h CPU (PLAN.md v0.5 §1.5.5 추정)
- **★ 실제 cost는 PLAN 추정의 ~15-20배 가능 (Stage 2 15-seed inflation)** — 도훈 mandate compute budget 확인 필요

---

## Risk Re-assessment (AMENDMENT_v0.5 §C.4)

| Risk | Level | Mitigation |
|---|---|---|
| R5 5-seed inflation | Medium | 15-seed strict + paired bootstrap CI (PLAN.md §5.3.6.2 정합) |
| **R13 Paper hallucination (★ v0.5 신규)** | **HIGH** | CR-V06 paper-direct verification 의무 |
| **R14 Architecture mismatch (★ v0.5 신규)** | **HIGH** | CR-V02 paper baseline 우선 reproduce |
| R12 Ensemble diversity | Medium | Spearman ρ < 0.80 strict, stacking 배제 |
| R8 Lock-in 변경 옵션 포기 | Medium | Phase 5a-1 reproduce 실패 trigger 명시 |
| R10 Compute cost 폭증 | High | Two-stage Optuna + 15-seed top-5만 |

---

## 도훈 confirm checkpoint (Phase 4)

다음 Phase 5a-1 실제 코딩 진입 전 도훈 confirm:

1. **Compute budget 승인**: ~260-395h GPU + ~22-67h CPU (Phase 5 전체 누적). 분산 옵션 또는 우선순위 (B1만 → B5 분리 진행 등) 결정.
2. **v2_alt_data feature inherit audit**: paper B1 baseline은 return + volatility only. v3 alt data 60 features 추가 효과 측정 plan?
3. **B1 reproduce 통과 기준 confirm**: paper KOSPI LSTM-SSTD CRPS 0.5165 ± 1% (0.510-0.522)?
4. **Tier 4 Linear Pool 활성화 조건 confirm**: 5 components 모두 val CRPS > baseline + Spearman ρ < 0.80 + DM sig?

---

## 참조

- `PLAN.md` v0.5 (도훈 GO 2026-05-24)
- `AMENDMENT_v0.5.md` (12건 정정 + CR-V01-V06 entry criteria)
- `paper_summary.md` Phase 1 7편 통합
- `paradigm_matrix.md` 7 paradigm × 6 dimension scoring
- `00_literature/paper_deep_read_subagent_output.md` 596줄 verification

---

## Change log

- 2026-05-24 Session 84 — v3_algorithm_shortlist 작성. Phase 5a-1 ~ 5d implementation spec + compute estimate + 도훈 confirm checkpoint.
