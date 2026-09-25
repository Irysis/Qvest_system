# PIT C1 표식 (SJM 블록 미래참조) — 02_Infrastructure/ramp

**상태:** 위반(상속) — `regime_jump_daily.parquet` 구판(jm_causal 표식 없음) 소비
**위반 근거:** C1. 구판 `regime_jump_model.R`은 refit 블록 (prev_end, end_i]의 상태를 end_i까지 적합한 창에서 Viterbi 역추적 경로, 중심점, 표준화로 매겼습니다. 그래서 블록 안 날짜 t의 `JM_State`와 `Bear_Prob`가 t 뒤 최대 125거래일의 정보를 씁니다. `_lag` 열도 같은 값을 하루 미룬 것일 뿐이라 이 결함을 씻지 못합니다.
**조치:** 표식만(코드·산출 무변경). 도훈 결정 `PIT-C11-JM-C1`

이 폴더의 아래 코드는 구판 `.cache/regime_jump_daily.parquet`의 `Bear_Prob` 또는 `Bear_Prob_lag`를 읽었습니다. 그 산출과 수치는 결론 근거로 인용하지 않습니다. 다시 쓰려면 수리판(`jm_causal:v1`)이 재빌드된 뒤 다시 실행해야 합니다. 읽는 쪽에서는 `jm_causal_status(panel) == "causal"`인지 확인하십시오.

- `run_ramp_regime_bakeoff.R`: 결정 범위 소비자입니다. Jump 팔(`Bear_Prob_lag`에서 월간 z를 만듦)을 씁니다. 산출물 `.cache/_ramp_bakeoff.txt`와 `.rds`는 2026-09-24 현재 없습니다.
- 같은 폴더의 JM 소비자:
  - `run_dfa_fm_exposure_r8.R`
  - `run_dfa_exposure_r9.R`
  - `run_dfa_crisis_alignment_audit.R`
  - `run_ramp_shumulvey_v5_daily.R`(H1 crisis 경로)
  - `run_ramp_shumulvey_v6_overlay.R`(mkt_jm)
  - 사전등록 `outputs/ramp/smv_v6_prereg_20260821.json`, `smv_v7_prereg_20260821.json`
- 이 폴더에는 C11 표식(`PIT_C11_NOTICE.md`)도 따로 걸려 있습니다. 두 표식은 서로 독립이라 둘 다 적용됩니다.

## 수리판과 구판 차이 (같은 입력, 스크래치 재빌드, 2026-09-24)

- **상태 일치율:** 86.3%(n = 8,529, 1992-02-07~2026-09-23). 2005년 이후는 87.6%, 최근 1년은 65.8%입니다.
- **Bear_Prob 상관:** Pearson 0.939, Spearman 0.914입니다.
- **bear 비율:** 수리판 38.7%, 구판 41.4%
- **연간 전환 횟수:** 수리판 1.27회, 구판 0.89회. 전방 필터는 스무딩된 구판 경로보다 늦고 더 자주 전환합니다.
- **미래 섭동(t* = 2020-05-15 이후 입력 교란):**
  - 수리판은 t* 이하 6,969행이 교란 전과 같습니다(identical).
  - 구판은 t* 이하 40행이 바뀝니다(블록 시작 2020-03-17부터, Bear_Prob 최대 차이 0.19).

## 참조

- 결정: `06_Registry/decision_register.json#PIT-C11-JM-C1`
- 레지스트리: `06_Registry/pit_jm_c1_consumer_notices.json`(id `ramp_regime_bakeoff`)
- 판독기: `02_Infrastructure/regime/regime_jump_model.R::jm_causal_status`
- 검사: `08_Tests/regime/test_jm_causal.R`
