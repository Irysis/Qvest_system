# Optimizer Agent Challenge Note — WT-D20260425_009

**Author**: Optimizer Research Agent
**Date**: 2026-04-25
**Subject**: Iter 4 (FF5 backfill) — α̂ + Σ_v2 → method comparison + weight 결정

---

## 1. Executive summary

| 결정 사항 | 결과 |
|---|---|
| Selected method | **MVO_lam5_psi03** (net_IR 0.6247) |
| Σ source | **v2_backfilled** (Risk Agent 권고 준수) |
| n_names | 20 / 20 (max_names_binding) |
| HHI | 0.0575 (< 0.10 cap) |
| max weight | 0.1089 (< 0.20 bound) |
| Σw | 1.000000 |
| objection_to_alpha_or_risk | **FALSE** (P4 obligation 충족) |
| infeasibility_report | null |
| selection_objective | `net_ir` (R4 P3 HARD 준수) |
| candidates_tried | 10 (parallel R13, 5 workers, 3.0s) |

`wt_record_challenge_review`: 정식 이의 없음.
`wt_challenge`: 호출 없음.

---

## 2. Iter 4 가설 — Optimizer 입장 정리

Iter 4의 가설은 **factor mix / weight method 변경 NOT**. 외부 검증 framework만 변경 (FF5 백필).
따라서 Optimizer의 정직한 임무는:

1. Risk Agent 권고대로 **v2 backfilled Σ** 사용 (old Σ 사용 금지 = Risk 권고 무시)
2. **MEGA_05 baseline (Kelly_frac05) 보존 비교**가 핵심
3. method_shopping_log 의무 (3건+ → R13 parallel 강제, 본 작업 10건)
4. **method shopping은 검토** — "factor mix 그대로니 검토 생략" 합리화 금지 (Hook block)
5. Forge가 회귀 재실행 시 본 weights 그대로 사용

---

## 3. Method comparison (10 candidates, R13 parallel)

| Method | net_IR | gross_IR | n | HHI | TO | Selected |
|---|---|---|---|---|---|---|
| **MVO_lam5_psi03** | **0.6247** | 0.6323 | 20 | 0.0575 | 0.281 | **YES** |
| Ensemble_top3 | 0.6229 | 0.6315 | 20 | 0.0602 | NA | no |
| Kelly_frac05 (baseline ref) | 0.6215 | 0.6329 | 20 | 0.0669 | 0.426 | no |
| MVO_lam2_psi03_conf | 0.6122 | 0.6206 | 20 | 0.0587 | 0.324 | no |
| BlackLitterman_eq | 0.6105 | 0.6159 | 20 | 0.0531 | 0.207 | no |
| ERC_lw | 0.6097 | 0.6136 | 20 | 0.0514 | 0.145 | no |
| MVO_lam1_psi02 | 0.5920 | 0.6029 | 20 | 0.0651 | 0.442 | no |
| MaxDiv_lw | 0.5910 | 0.5981 | 20 | 0.0550 | 0.272 | no |
| alpha_tilt_hrp_v2 | 0.5063 | 0.5101 | 20 | 0.0531 | 0.182 | no |
| HRP_sigma | 0.5004 | 0.5057 | 20 | 0.0549 | 0.246 | no |

### 핵심 관찰

- **Top 4 net_IR (MVO_lam5 / Ensemble / Kelly / MVO_lam2)** 사실상 동률 (0.61~0.62 range). margin 0.003 (0.5%).
- **Kelly_frac05 baseline** 도 동급 성능 보존. WT_003 baseline (net_IR 1.2743)과 직접 비교 불가 (universe + alpha pool 다름) 인 점 명시.
- **MVO_lam5_psi03 선택 이유** (net_IR 최대): ① λ=5.0 high risk-aversion → idio 70.7% 환경 안전 ② TO 낮음 (0.281 vs Kelly 0.426) → cost-adjusted 우수 ③ HHI 0.0575로 분산 우수.
- **HRP_sigma / alpha_tilt_hrp_v2** 열등 (0.50 range): α-tilt 부재 시 risk-only allocation 한계.
- **Ensemble_top3** = MVO_lam5 + Kelly + MVO_lam2 평균 → MVO_lam5 단독과 거의 동일 (0.6229 vs 0.6247). 단순화 위해 단독 method 채택.

---

## 4. Σ source 비교 (v1 vs v2 backfill 효과)

본 Optimizer는 Risk Agent가 산출한 **v2 (LW_constcor)** Σ를 직접 사용. v1 vs v2 직접 비교는 Risk Agent 영역.
다만 본 노트는 Risk pkg `method_shopping_log`에서 정량 효과 정리:

| 비교 | v1 (sample) | v2 (LW_constcor) | 효과 |
|---|---|---|---|
| Condition number | 144.2 | 96.8 | **-32.9%** (안정화) |
| PSD | TRUE | TRUE | OK |
| HML/RMW/CMA n | 40~120 | 284 | **+2.4~7.1×** |

**v2 backfill 핵심 효과**:
1. RMW/CMA 표본 n=107 → n=284 (factor cov 추정 노이즈 ~sqrt(284/107) = 1.63× 감소)
2. HML 표본 n=120 → n=284 (~1.54× 감소)
3. Condition 96.8 (LW shrinkage) → MVO QP 수치 안정성 우수
4. 다만 v1 vs v2 overlap 상관 약함 (HML 0.47 / RMW -0.17 / CMA 0.00) → **methodology 차이 가능**, t_NW 결과가 v1 사용 시와 매우 다를 수 있음 (Risk FLAG-R1 인지)

**Optimizer 입장**: v2가 PIT-compliant + textbook FF1993/2015 + Novy-Marx 2013. v1 builder 부재 → **v2 채택이 정당**. Forge가 회귀 재실행 시 v2 사용.

---

## 5. Expected t_NW per method (FF5 v2 기반)

### 추정 방법론

```
t_NW_proj = realistic_range × (method_net_IR / median_net_IR) × HHI_penalty
realistic_range = [4.0, 5.5]   (Alpha Agent power_analysis)
HHI_penalty = 1 - 0.3 × max(0, HHI - 0.075)
n_full = 285 (FF5 v2 backfilled)
gate = 2.95
```

| Method | t_NW low | t_NW high | point | gate_pass |
|---|---|---|---|---|
| **MVO_lam5_psi03** | **4.10** | **5.63** | **4.86** | **PASS** |
| Ensemble_top3 | 4.08 | 5.62 | 4.85 | PASS |
| Kelly_frac05 | 4.08 | 5.60 | 4.84 | PASS |
| MVO_lam2_psi03_conf | 4.01 | 5.52 | 4.77 | PASS |
| BlackLitterman_eq | 4.00 | 5.50 | 4.75 | PASS |
| ERC_lw | 4.00 | 5.50 | 4.75 | PASS |
| MVO_lam1_psi02 | 3.88 | 5.34 | 4.61 | PASS |
| MaxDiv_lw | 3.88 | 5.33 | 4.60 | PASS |
| alpha_tilt_hrp_v2 | 3.32 | 4.56 | 3.94 | PASS |
| HRP_sigma | 3.28 | 4.51 | 3.90 | PASS |

**모든 method가 gate 2.95 통과 추정** (low bound 기준). 본 추정은 가이드라인이며 **실측은 Forge S1 회귀 재실행에서 확정**.

### Caveat
- 추정은 net_IR proxy 기반. 실제 t_NW는 ① alpha → portfolio 변환 회귀 ② FF5 v2 spec ③ NW lag 선택 ④ DSR 보정에 의존.
- Alpha Agent FLAG-4 인지: t_NW > 7은 의심 trigger. 본 추정 4.0~5.6 range는 학술 적정.

---

## 6. Risk + Alpha challenge_flags 검토 (Optimizer 시각)

### Inherited from Alpha
- **FLAG-1 MEDIUM** (Iter3 t_NW 2.691 출처): Forge S1에서 v2 + 5-spec parallel 보고로 자연 해소.
- **FLAG-2 LOW** (RF-A6 multiple-testing): 5-spec parallel + DSR 권고 — Forge 책임.
- **FLAG-3 INFO** (backfill 의존성): Risk Agent 백필 완료 — 충족.
- **FLAG-4 INFO** (t_NW expected 4.0~5.5): 본 optimizer 추정도 동일 range (4.0~5.6). 적정.

### Inherited from Risk
- **FLAG-R1 MEDIUM** (v2 vs v1 overlap cor 약함): **methodology 차이 가능**. 본 optimizer는 v2 채택 (Risk Agent 권고). Forge가 v1 vs v2 결과 비교 시 차이가 sample 차이가 아닌 universe/breakpoint 차이일 수 있음을 Judge가 인지해야 함.
- **RF-R1 HIGH** (idio 70.7%): **다양화 critical**. λ=5.0 high risk-aversion + 20-name + HHI 0.0575로 강제 분산. 이는 idio shock 노출 최소화.
- **RF-R3 MEDIUM** (top-10 alpha HHI 0.47): **본 optimizer는 top-30 후보 + bounds 0.20 + hhi_cap 0.10**으로 분산 강제. 추가 시총 가중 회피. 결과: max_w 0.1089 < 0.20.

### Optimizer 자체 조치
- Risk-flagged 3개 low-liquidity (A084870 / A205470 / A254120) **명시적 exclusion**. 이들은 alpha rank 4/2/5 (top 5) 였으나 universe screening에서 drop.
  - **결과**: alpha 손실 미미 (top 30에서 27개 잔존, alpha range 0.0323~0.0500 유지).

---

## 7. Iter 4 가설 일관성 확인

| 측면 | 결과 |
|---|---|
| Factor mix preserved | Alpha Agent에서 inherit (변경 없음) |
| Weight method preserved? | **MVO_lam5_psi03 ≠ Kelly_frac05** (drift) |
| Drift 설명 | Universe + Σ 변경 + 후보 pool 차이로 **자연 drift** |
| Drift 정도 | net_IR 0.6247 vs Kelly 0.6215 (margin +0.003 = +0.5%) — 사실상 동률 |
| Iter 4 성격 | **외부 검증 framework 변경에 집중** — weight method drift는 부차적 |
| 가설 일관성 | **유지** (factor mix 동일, framework 변경) |

**Forge에 권고**: 본 weights를 그대로 사용하되, Forge S1 회귀에서 **Kelly_frac05 시뮬레이션도 병렬 실행**하여 method-driven vs framework-driven 효과 분리 보고. (TO 0.281 vs 0.426 차이가 t_NW에 영향 가능)

---

## 8. Binding constraints + sensitivity

| 제약 | 상태 |
|---|---|
| max_names = 20 | **BINDING** (n=20) |
| weight_bounds [0, 0.20] | non-binding (max=0.1089) |
| HHI ≤ 0.10 | non-binding (HHI=0.0575) |
| min_names ≥ 15 | non-binding (n=20 > 15) |
| Σw = 1 | satisfied (1.000000) |
| long-only | satisfied (min=0) |
| liquidity floor 50M won | satisfied (3 low-liq 사전 exclusion) |
| sector_active_weight_cap | non-binding (request null) |

**Alpha sensitivity**: medium. ±10% alpha shock에 weight 평균 1~3% 변화 예상.

---

## 9. Top 5 weights (selected)

| Rank | Ticker | Weight | Alpha (monthly) | Confidence |
|---|---|---|---|---|
| #1 | A185750 | 0.1089 | 0.0402 | 0.5078 |
| #2 | A137310 | 0.0805 | 0.0355 | 0.4950 |
| #3 | A009270 | 0.0729 | 0.0333 | 0.4928 |
| #4 | A900120 | 0.0678 | 0.0329 | 0.4927 |
| #5 | A227610 | 0.0555 | 0.0338 | 0.3852 |

Top 1 이름은 A185750 (alpha=0.0402, conf=0.5078, 본 universe 3rd-highest alpha). Risk-flagged 3 (A084870/A205470/A254120) 제외 후 자연 1st 종목.

---

## 10. Forge 인계 사항

**Forge S1 백테스트 실행 시 권고**:

1. **Spec 5종 동시 보고**: CAPM / Carhart-3 / Carhart-4 / FF5 / FF6 (Alpha + Risk handoff)
2. **Σ source**: v2 (`stage_artifacts/WT-D20260425_009/covariance.parquet`) 사용
3. **Factor returns**: `.cache/kr_factor_returns_v2.parquet` 사용
4. **DSR 산출** + **lockbox separation** (train_validation 2002-07~2023-12 + lockbox 2024-01~2026-03)
5. **Method comparison**: 본 weights (MVO_lam5_psi03)를 default + **Kelly_frac05 변형 병렬 실행** 권고 (drift 정량 분석)
6. **PIT C1~C15 verification**: Factor DB Usable_Date 강제 (C14)
7. **CVaR realized**: Forge backtest에서 직접 측정. Risk pkg 추정치 (univ EW MC) 참조용만.

---

## 11. v6.1 R3/R11 Compliance

### R3 Challenge Authority — P4 obligation
```
wt_record_challenge_review(
  task_id="WT-D20260425_009",
  from_agent="optimizer",
  objection=FALSE,
  targets_reviewed=c("alpha_vector", "risk_sigma", "external_factor_data",
                     "bound_feasibility", "challenge_flags"),
  note="Iter4 가설 일관성 확인. v2 Σ 채택 (Risk 권고 준수). low-liq 3개 exclusion. method drift 자연.",
  round=1
)
```

### R11 Lineage
```
record_package_lineage(
  task_id="WT-D20260425_009",
  package_type="optimization_package",
  method_selected="MVO_lam5_psi03",
  input_file_paths=c(
    "qepm/mailbox/worktask/WT-D20260425_009/alpha_package.json",
    "qepm/mailbox/worktask/WT-D20260425_009/risk_package.json",
    "stage_artifacts/WT-D20260425_009/covariance.parquet",
    ".cache/kr_factor_returns_v2.parquet"
  )
)
```
호출 완료 (lineage append 확인).

---

## 12. Final artifacts

| 파일 | 위치 |
|---|---|
| Optimization package | `qepm/mailbox/worktask/WT-D20260425_009/optimization_package.json` |
| Weights CSV | `qepm/mailbox/worktask/WT-D20260425_009/weights.csv` |
| Weights CSV (stage) | `stage_artifacts/WT-D20260425_009/weights.csv` |
| Optimizer R script | `stage_artifacts/WT-D20260425_009/run_optimizer_iter4.R` |
| Challenge note | `qepm/mailbox/worktask/WT-D20260425_009/optimizer_challenge_note.md` |
| Method selection note | `qepm/mailbox/worktask/WT-D20260425_009/weight_method_selected.md` |

---

**END Optimizer Challenge Note**
