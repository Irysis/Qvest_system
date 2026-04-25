# Weight Method Selected — WT-D20260425_009

**Method**: `MVO_lam5_psi03`
**Selection objective**: `net_ir`
**Decision date**: 2026-04-25
**Σ source**: v2_backfilled (Risk Agent FF5 백필)

---

## Selected method 정의

```r
mvo_weights(
  alpha = alpha_vec,             # FF5 + WML factor 노출 기반 confidence-scaled monthly α̂
  cov_matrix = Sigma_v2,          # 2300×2300 LW_constcor (cond=96.8 post-shrinkage)
  confidence = conf_vec,           # alpha_pkg confidence_vector (0.36~0.61)
  lambda = 5.0,                    # high risk-aversion (idio 70.7% 환경 대응)
  psi = 0.3,                       # confidence-weighted FU penalty
  bounds = c(0, 0.20),             # request hard_constraints
  max_names = 20,                  # request constraint
  min_names = 15L,                 # Grinold breadth (Task#26 L-192)
  hhi_cap = 0.10,                  # 분산 강제
  alpha_winsor = 2.0,              # cross-section ±2σ outlier clip
  active = FALSE                   # absolute weights (Σw = 1)
)
```

## 선택 근거

### 1. net_IR maximization (R4 P3 HARD 준수)

10개 method 병렬 비교 결과 net_IR 0.6247로 1위. 단, top-4 (MVO_lam5 / Ensemble / Kelly / MVO_lam2) 사실상 동률 (margin 0.5%) — 미세 우위.

### 2. Idio 70.7% 환경 대응

Risk RF-R1 HIGH (idio share 70.7%) 인지. λ=5.0 high risk-aversion으로 분산 강제:
- HHI 0.0575 (cap 0.10 대비 여유)
- max_w 0.1089 (bound 0.20 대비 여유)
- TE 0.0561 (가장 낮은 변동성 group)

### 3. Cost-adjusted 우수

- Turnover 0.281 (vs Kelly 0.426, MVO_lam2 0.324)
- TC cost 0.00042 (vs Kelly 0.00064)
- net_IR 0.6247 = gross_IR 0.6323 - cost_drag 0.0076

### 4. Iter 4 가설 일관성

Iter 4는 weight method 변경 NOT — 외부 framework 변경. 본 method는 Kelly_frac05 baseline과 net_IR 0.003 차이로 **사실상 동일 계열**. drift는 universe + Σ 변경으로 인한 자연 효과.

## 비선택 method 사유 (top alternatives)

| Method | 사유 |
|---|---|
| Kelly_frac05 (baseline) | net_IR 0.6215 (-0.5%) + TO 0.426 (vs 0.281) — cost-adjusted 약간 열세. **단, baseline 비교 anchor로 보존**. Forge 권고: 본 weights 외 Kelly 변형도 병렬 backtest. |
| Ensemble_top3 | net_IR 0.6229 (-0.3%). top-3 평균이 단독 MVO_lam5와 사실상 동일 → 단순화 위해 단독 채택. |
| MVO_lam2_psi03_conf | net_IR 0.6122 (-2.0%) — λ=2.0이 idio 70.7% 환경에서 약간 over-aggressive. |
| BlackLitterman_eq | net_IR 0.6105 — EW prior + view shrinkage 효과는 confidence-aware MVO와 본질 유사. 미세 열세. |
| HRP_sigma | net_IR 0.5004 (-20%) — α-tilt 부재 → risk-only allocation 한계. WT 시나리오 (alpha-driven) 부적합. |
| alpha_tilt_hrp_v2 | net_IR 0.5063 — HRP 기반 + α blend 0.4. risk-aversion 제어 부재로 열세. |

## 제약 만족 확인

| 제약 | 값 | 상태 |
|---|---|---|
| n_names ≤ 20 | 20 | **binding** |
| weight ∈ [0, 0.20] | max=0.1089 | non-binding |
| HHI ≤ 0.10 | 0.0575 | non-binding |
| min_names ≥ 15 | 20 | non-binding |
| Σw = 1 | 1.000000 | satisfied |
| long-only | min=0 | satisfied |
| liquidity 50M+ | 3 low-liq excluded | satisfied |
| PIT C1~C15 | inherited | PASS |

## Σ source 결정

**v2_backfilled** 채택 (Risk Agent 권고 준수).

- v1 (sample): condition 144.2
- v2 (LW_constcor, FF5 backfilled n=284): **condition 96.8 (-32.9%)**
- LW shrinkage → MVO QP 수치 안정성 우수
- HML/RMW/CMA 표본 ≥2.4× 확장 → factor cov 추정 노이즈 감소

**Risk FLAG-R1 인지**: v2 vs v1 overlap 상관 약함 (HML 0.47 / RMW -0.17 / CMA 0.00). v2가 PIT-compliant + textbook 표준 → 채택 정당.

## Expected portfolio metrics

| Metric | Value |
|---|---|
| Expected active return | 0.0355 (monthly proxy) |
| Expected tracking error | 0.0561 (monthly) |
| Expected gross IR | 0.6323 |
| **Expected net IR** | **0.6247** |
| Turnover | 0.281 (per rebalance) |
| Estimated cost | 0.00042 |
| HHI | 0.0575 |
| Effective breadth (Grinold) | 17.4 (= 1/HHI) |

## Expected t_NW (FF5 v2 기반)

| Method | Range | Point | Gate (2.95) |
|---|---|---|---|
| **MVO_lam5_psi03** | **[4.10, 5.63]** | **4.86** | **PASS** |
| Kelly_frac05 (anchor) | [4.08, 5.60] | 4.84 | PASS |

**Note**: Naive scaling 추정. **실측은 Forge S1 회귀 재실행에서 확정.** Alpha Agent FLAG-4 인지 (>7은 의심 trigger; 본 추정 4.0~5.6은 적정).

## Forge 인계

`weights.csv` (20 active names) + `optimization_package.json` 두 파일을 Forge가 직접 수신.

Forge S1 백테스트 권고:
1. v2 covariance + factor returns 사용
2. CAPM / Carhart-3 / Carhart-4 / FF5 / FF6 5-spec 동시 보고
3. DSR (Bailey-Lopez de Prado) 산출 (multi-spec inflation 보정)
4. Lockbox separation: train 2002-07~2023-12 / lockbox 2024-01~2026-03
5. Method comparison: 본 weights + Kelly_frac05 변형 병렬 실행 권고

---

**END Weight Method Selection Note**
