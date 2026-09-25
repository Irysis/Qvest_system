# PIT C1 표식 (SJM 블록 미래참조) — FR Track1 · regime_forecaster_v4 산출

**상태:** 위반(상속) — 구판 `regime_jump_daily.parquet`(jm_causal 표식 없음)을 소비했습니다.
**위반 근거:** C1. 구판 JM은 refit 블록 (prev_end, end_i]의 상태를 end_i까지 적합한 창의 Viterbi 역추적 경로, 중심점, 표준화로 매겼습니다. 그 결과 블록 안 t의 값이 t 뒤 최대 125거래일의 정보를 씁니다.
**조치:** 표식만(코드·산출 무변경). 근거는 도훈 결정 `PIT-C11-JM-C1`입니다.

## 대상 (이 폴더의 산출 · 2026-06-08)

- **FR Track1**(`04_Research/factor_rotation/`):
  - `regime_jm_validation.json` ← `regime_jm_validation.R`
  - `regime_jm_ensemble_ab.json` ← `regime_jm_ensemble_ab.R`
  - `sjm_ep_ablation.json` ← `sjm_ep_ablation.R`
  - `sjm_ep_seed_check.json` ← `sjm_ep_seed_check.R`
- **regime_forecaster_v4:** `regime_forecast_v4.json` ← `02_Infrastructure/regime/regime_forecaster_v4.R`. 월말 roll로 `Bear_Prob_lag`와 `JM_State_lag`를 읽습니다.

위 산출의 다음 수치는 구판 산출이므로 결론 근거로 인용하지 않습니다. 같은 수치가 인용된 곳도 같은 취급입니다:
- churn 33.2%→7.1%
- 위기 적중 GFC 100%, COVID 94%, 2022 100%
- HMM parity 73%
- 앙상블 OOS SR A/B(SJM_SR_GAIN_NONROBUST)
- v4a·v4o 선행 전환 판정

인용된 곳:
- `02_Infrastructure/regime/regime_jump_model.R` 구 헤더(수리판에서 무효로 표기)
- `.claude/skills/strategy-rotation/SKILL.md`
- `04_Research/factor_rotation/regime_model_literature_review.md`

재측정은 수리판(`jm_causal:v1`)이 재빌드된 뒤 다시 실행하는 방식으로 합니다. 읽기 전에 `jm_causal_status(panel) == "causal"`를 확인하십시오.

⚠ **재실행 주의:** `regime_jm_validation.R`의 `DO_SWEEP` 경로는 `compute_jm_daily_signal(lambda = λ)`를 `write` 기본값(TRUE)으로 부릅니다. 그러면 운영 `.cache/regime_jump_daily.parquet`가 λ마다 덮어써지고, 마지막 λ = 200 판이 남습니다. 재실행할 때는 `write = FALSE`로 부르십시오. 이 표식은 코드를 바꾸지 않았습니다.

## 수리판과 구판 차이 (같은 입력, 스크래치 재빌드, 2026-09-24)

- **상태 일치율:** 86.3%(2005년 이후 87.6%)
- **Bear_Prob 상관:** Pearson 0.939
- **bear 비율:** 수리판 38.7%, 구판 41.4%
- **연간 전환:** 수리판 1.27회, 구판 0.89회
- **위기 구간 bear 비율:**

| 구간 | 수리판 | 구판 |
|---|---|---|
| GFC | 100% | 100% |
| COVID | 71.4% | 91.8% |
| 2022 | 93.1% | 100% |

구판의 "신속 탐지"는 일부가 블록 끝 정보를 쓴 효과입니다.

## 참조

- **결정:** `06_Registry/decision_register.json#PIT-C11-JM-C1`
- **레지스트리:** `06_Registry/pit_jm_c1_consumer_notices.json` (id `fr_track1` · `forecaster_v4`)
- **판독기:** `02_Infrastructure/regime/regime_jump_model.R::jm_causal_status`
- **검사:** `08_Tests/regime/test_jm_causal.R`
