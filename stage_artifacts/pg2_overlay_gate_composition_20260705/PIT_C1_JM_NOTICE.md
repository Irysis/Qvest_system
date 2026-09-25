# PIT C1 표식 (SJM 블록 미래참조) — axiom overlay selfdev · stage_artifacts/pg2_overlay_gate_composition_20260705

**상태:** 위반(상속). 구판 `regime_jump_daily.parquet`(`pinned_cache/` 고정 사본, 2026-07-05)의 `Bear_Prob`와 `Bear_Prob_lag`를 소비합니다.
**위반 근거:** C1. 구판 JM은 refit 블록의 상태를 블록 끝까지 적합한 창의 Viterbi 역추적 경로, 중심점, 표준화로 매겼습니다. 블록 안 t의 값이 t 뒤 최대 125거래일의 정보를 씁니다.
- 이 폴더 스크립트들의 `holdings_signal_cutoff`, strict-PIT, lag1 스트레스는 **날짜 라벨**만 통제합니다. 라벨 d의 값 자체에 d 이후 정보가 들어 있는 경우는 막지 못합니다.
- 그래서 이 표식은 C5 검사를 통과한 결과에도 적용됩니다.

**조치:** 표식만 합니다(코드·산출 무변경). 근거는 도훈 결정 `PIT-C11-JM-C1`입니다.

## 대상

- **코드:**
  - `02_Infrastructure/axiom/run_overlay_selfdev_r2.R`
  - 이 폴더의 JM 소비 스크립트 8종: `bull_conviction.R`, `cycleR1_riskoverlay.R`, `cycleR2_bearprob_verify.R`, `cycleR3_multilayer.R`, `cycleR4_forge_confirm.R`, `defensive_strict.R`, `explain_bearprob.R`, `pit_audit_bearprob.R`
- **산출:**
  - `overlay_selfdev_round2_results.csv`
  - `bull_conviction_results.csv`
  - `cycleR*_results.csv`
  - `defensive_strict_results.csv`
  - `pit_audit_bearprob_results.csv`
  - 위 스크립트의 실행 로그
- **표식 밖:** selfdev가 `lcode_emit`로 발행한 L-code는 원장 소관이라 이 표식에 포함하지 않았습니다.
- `pinned_cache/regime_jump_daily.parquet`는 2026-09-24 현재 이 폴더에 없습니다. 그래서 위 스크립트는 지금 그대로는 다시 실행할 수 없습니다.
  - 다시 실행하려면 수리판(`jm_causal:v1`) 재빌드본을 새로 고정해야 합니다.
  - 고정한 뒤 `jm_causal_status(panel) == "causal"`인지 확인해야 합니다.

## 수리판과 구판 차이 (같은 입력, 스크래치 재빌드, 2026-09-24)

- **상태 일치율:** 86.3%입니다. 최근 1년은 65.8%입니다.
- **Bear_Prob 상관:** Pearson 0.939입니다.
- **위기 구간 bear 비율:**

| 구간 | 수리판 | 구판 |
|---|---|---|
| GFC | 100% | 100% |
| COVID(2020-02-20~04-30) | 71.4% | 91.8% |
| 2022 | 93.1% | 100% |

- **미래 섭동:** 수리판은 t* 이하 출력이 identical입니다. 구판은 t* 이하가 바뀝니다(t* = 2020-05-15에서 40행).

## 참조

- **결정:** `06_Registry/decision_register.json#PIT-C11-JM-C1`
- **레지스트리:** `06_Registry/pit_jm_c1_consumer_notices.json` (id `axiom_overlay_selfdev`)
- **판독기:** `02_Infrastructure/regime/regime_jump_model.R::jm_causal_status`
- **검사:** `08_Tests/regime/test_jm_causal.R`
