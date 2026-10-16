# MSM as-of 전환 2단계 — 소비 경로 지도 · 최소 전환안 (2026-10-17 · 읽기 전용 조사)

작업: OP-20261015-MSM-A S2 (PIT-C1-MSM-PARAMS 안 A). 조사 = Explore 서브에이전트(코드 · file:line 근거) · 정리 = Q. 코드 · 데이터 변경 없음.
1단계 생산자 = `02_Infrastructure/regime/msm_asof.R` · `msm_asof_update.R` → `06_Registry/msm_param_schedule.json`(연말 확장 재적합 · 추가 전용) · `.cache/msm_asof_daily.parquet`(커밋 961202f6e).

## 한 줄 결론
- 구 MSM 캐시를 **직접 읽는 운영 코드는 `02_Infrastructure/regime/regime_signal.R` 하나**(로더 2개). 나머지는 통합 국면 신호(월 · 일)나 BOOK_0001 의 m4 패널을 거쳐 간접으로 받는다.
- 새 파일은 **완전한 대체가 아니다**: 열은 같지만(`Date`, `Crisis_Prob`) 월간 파일이 없고 · **2004-01-02 시작**(구 = 1990) · **아무것도 정기 실행하지 않는다**(신선도 감사 ORPHAN) · 두 로더 모두 C1 값을 조용히 되살리는 폴백이 있다(RData 분기 :63-101 · 빈 파일 재척도 :694-698/:993-994 · msm_daily_refit 평활 폴백).
- **재발행 원장 3종**: `regime_published`(월 · 일) · `m4_published`. 에폭 키는 지금 C11 키(`c11_avail:2026-09-24.b4:631e4f98`) 하나 — **`c11_regime_key` 에 MSM 표식을 덧붙이지 말 것**(정확 일치 C11 가드 9곳이 깨진다). MSM 추정기를 **별도 에폭 부분(`msm_estimator`)** 으로 둔다.
- **P3R03 핀과 겹치는 MSM 생산 · 소비 파일 없음**(이웃 = config.R · backtest_harness.R · refresh_barrier.sh — 전환에 손댈 필요 없음).

## 1 생산자
| # | 생산자 | 쓰는 것 | 실행 |
|---|---|---|---|
| P1 | `04_Research/regime_comparison/msm_update.R`(전 표본 고정 모수 — msm_param_pin.json → K_Fractal_Master_2026-01-20.xlsx :114-150) | `.cache/msm_daily_latest.parquet`(Date · Price · Vol_Est · Crisis_Prob) · `.cache/msm_hybrid_latest.parquet`(Avg_Prob = 월평균 :237) · `outputs/regime/output/MSM_updated_*.RData` | daily_refresh [4/7] :419-434 · morning self_heal(신선도 낡음 시) · nolayer4 월간 · pg2 리밸 · ensure_data_current · bootstrap |
| P2 | `02_Infrastructure/regime/msm_daily_refit.R`(평활 HMM γ — C1 이중) | msm_daily_latest + HMM_State | P1 실패 시만 |
| P3 | `05_Production/1.Regime_Def_Model/1-1.MSM/MSM.R`(오프라인 수동) | K_Fractal_Master · *_MSM.RData | 수동 — regime_signal.R RData 폴백의 숨은 공급원 |
| P4 | `regime_signal.R` 월 :504-641 · 일 :875-1107 | 통합 신호 후보 → 원장 · regime_current.json · 연구 사본 | daily_refresh :441-475 · fred_regime · self_heal |
| P5 | `qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R` | alpha_scores → m4_append_only → `06_Registry/m4_published/*` | run_pg2_forward_noLayer4.sh(AS_OF 행 없을 때만) |
| 신 | `msm_asof_update.R` | msm_param_schedule.json · msm_asof_daily.parquet(+ msm_fit_date · guard_action · 메타 msm_estimator=asof_yearly:v1) | **정기 실행 없음** |

## 2 소비자 요약
- **A 직접**: `load_msm_daily`(:692-709 — 열은 같으나 일 척추가 2004 시작 → 2004 전 3,425행 소멸 · 파일 없으면 빈 표 → 90/50 조용한 재척도 · 낡으면 LOCF 가 숨김) · `load_msm_signal`(:48-102 — 월 파일 없음 → as-of Crisis_Prob 의 YM 평균으로 대체 · RData 폴백 제거 필요 · 2004 전: 1990-10~1999-12 111개월 소멸 · 2000-01~2003-12 48개월 MSM=NA 로 의미 변경) · Layer1(:401) · Category 단락(:442-444) — 코드 무변경 · 값 변경(0.8 포화 · 0.9/0.7 문턱은 C1 표본에서 정했다 — 나중 재점검 · PIT 문제 아님).
- **B 결정 경로(값만 바뀜)**: m4 factor_engine(BOOK_0001 · :148 · :188-189 · :615-628 · :666-742) · m4_append_only(PIT 대조 :259-309 · 에폭 불일치 = 경고만 :357-366) · m4 패널 독자(forward_weights_D3_M4gAE.R — sha1 핀 · **수정 금지** · STR_1715 forward_weights · rebalance_spec m4_baseline) · build_module_performance(per_regime — c11_regime_key 가 순수 C11 키여야 :59) · 2계층 FR/RCMA(l2_auto 꺼짐 · S4 재측정).
- **C 2계층 역할 로테이션**: 원형 `work/msm_asof_daily.parquet`(열 이름 · 창 규약 `[r_k, r_{k+1})` 다름 · 사전등록 해시 고정) — **건드리지 않는다**.
- **D 표시 · 감시**: 대부분 그대로 · 적응 필요 = freshness_audit.R :44-45(감사 이름 msm_daily 유지) · self_heal.R :30-56 · cache_registry.json :163-214. 아침 BOOK 추적(mark_nolayer4_daily)은 MSM 입력 없음.
- **E 세션 · 유산**: 오버레이 하네스 · 국면 예측기(regime_forecast_series* 재생성 또는 퇴역) · 연구 스크립트(BOOK_0001 D3 진단 2곳이 구 C1 MSM 사용 — 해석 주의).

## 3 스키마
| | msm_daily_latest | msm_hybrid_latest | msm_asof_daily |
|---|---|---|---|
| 열 | Date · Price · Vol_Est · Crisis_Prob | Date(월말) · Avg_Prob · Is_Uptrend · Regime · Target_Weight | Date · Price · Vol_Est · Crisis_Prob · msm_fit_date · guard_action + 메타 |
| 빈도 | 일 | 월(달력 월평균) | 일 |
| 시작 | 1990-01 | 1990-10 무렵 | **2004-01-02** |
| 신선 유지 | 밤 실행 | 밤 실행 | **없음** |

## 4 재발행 원장 · 에폭 키
- 키 공식 `fred_availability.R:486-490` → `c11_avail:<규칙판>:<md5 8>` · 찍는 곳 `regime_signal.R:596-600`(월) · :1023-1027(일).
- `06_Registry/regime_published/`(월 n=433 · 일 n=9,047): 에폭 판독 `regime_append_only.R:62-63, 137-154` · 같은 에폭 검사(불일치 exit 3) :260-265 · 재발행은 후보 키 = 규칙 키 :436-439 · 보관 이름 `pre_c11` 하드코딩 :64 · :422 · 사유 문구 :414(CLI 인자 없음 — R 함수는 reason= 수용).
- `06_Registry/m4_published/`(273행 · 2026-10-01 까지): 행마다 통합 신호 키 복사(factor_engine.R:163-180 · 627-628 · 813) · m4_append_only 경고만 · 재초기화 m4_epoch_reinit.R:71-75 · 97 · 104 · 207-208.
- **추가 방식**: `msm_estimator` 행 열 + 파일 속성을 C11 도장 옆에 찍고(값 = msm_asof.R:211-212 메타) 합성 키는 `.rl_epoch` 와 그 두 검사 안에서만 만든다(결손 = `msm:legacy`) · 재발행 호출에 합성 `rules_key=`.
- C11 정확 일치 가드(덧붙이면 깨짐): overlay_pit_guard.R:149-154 · build_module_performance.R:59 · run_wf_ensemble.R:221 · regime_module_admission.R:86 · regime_label_gate.R:93-94 · pg2_risk_overlay.R:131-137 · forward_weights_D3_M4gAE.R:161 · m4_append_only.R:361 · m4_epoch_reinit.R:97.

## 5 최소 전환안(순서)
0. **관문(쓰기 없음)**: P3R03 평가 완료 센티널 · 밤 갱신 미실행(잠금) · 낮 창 · 2~4단계 같은 날 · 2026-11-03 09:00(월간 추적) · 11월 BOOK 리밸 전. **도훈 결정 D1~D4 먼저**(결정 기록부 MSM-ASOF-SWITCH-20261017).
1. 생산자 신선도(지금도 안전): `Rscript 02_Infrastructure/regime/msm_asof_update.R`(2026 은 새 적합 없음 · 캐시만 다시 씀) · 검사 test_msm_asof.R 9/0.
2. 코드 커밋 1개: regime_signal.R 로더(as-of 파일 · 결손/추정기 불일치/낡음이면 멈춤 · YM 평균 · RData 폴백 제거 · msm_estimator 도장) · regime_append_only.R(합성 에폭 · reason 인자 · 보관 태그 설정) · m4(factor_engine 표식 + 검사 또는 관문 전용 검사) · 배선(daily_refresh :414-434 폴백 없이 msm_asof_update.R · 잠금 :24 와 Done 줄 :993/:996 불변 — P3R03 · refresh_barrier 의존) · self_heal · freshness_audit(이름 유지) · cache_registry · 검사(test_regime_c11_asof NEED · run_all_hooks 에 test_msm_asof · test_msm_daily_refit 퇴역). 건식: (i) 양성 대조 — 새 코드 + 구 MSM 입력 = 표식 열 외 차이 0 (ii) 스크래치 후보로 as-of 후보 빌드 → 발행 원장과 비교(감사 부록 A 기대: 월 반전 22/132 IS · 14/120 OOS · Cash_Pct 14개월 · 일 반전 1,116/5,441 + 커버리지 변화) (iii) `--dry-run` exit 3 = 가드 작동.
3. 국면 재발행(같은 창): `regime_ledger_republish(..., rules_key=<합성>, archive_dir=..._archive_pre_msm_asof_YYYYMMDD, reason="PIT-C1-MSM-PARAMS 안 A", plan_out=P)` → 계획 검토(diff_vs_old · month_gaps · avail_na · MAX_PATH) → expect_plan=P, execute=TRUE.
4. m4 재초기화: PG2_AS_OF=2026-10-01 로 패널 재생성 → 음성 대조 m4_append_only --dry-run(exit 1 · 재서술 행 목록) → m4_epoch_reinit.R --report(2026-03 · 04 · 08 — 포화 MSM 0.985~1.0 에서 나온 디리스크 달 집중 확인) → --apply(도훈 승인 시) / 아니면 m4_append_only 로 원장 재동기.
5. 하류: module_performance(백업 · QVEST_L2_DRY_RUN=1 비교 · [8.2] 재빌드 — 입력 경로 :57 하드코딩이라 3단계 뒤) · regime_forecast_series* 재생성 또는 퇴역 → S4(pg2 15칸 · FR_003 · BOOK_0001 관문 이력 재측정) → S5(격리 갱신 · Judge 점검 항목).

## 6 위험
1 **혼합 원장** — 로더만 바꾸고 에폭을 안 바꾸면 동결된 C1 이력 위에 as-of 행이 붙는다(exit 1 — 이미 매일 밤 61회 경고라 아무도 모른다). 2 **숨은 C1 폴백**(RData 분기 · 빈 파일 재척도 · 평활 폴백). 3 **에폭 창** — 2·3단계 사이 통합 신호가 멈춘다(3일 뒤 regime_daily STALE → MRS 브리핑 차단 · 월 경계면 m4 PIT 검사 exit 4). 4 **배포된 BOOK 월 재서술 가능**(10월: 운영 CRISIS vs as-of CAUTION — 실시간 라벨이 눈에 띄게 바뀐다). 5 건식 부작용(--republish --rebuild 가 밤 후보를 지우고 regime_current.json 을 다시 씀). 6 격리 정규식 `Crisis_?Prob(?!_?asof)` 가 as-of 열 `Crisis_Prob` 도 막는다(안전 방향 · S5 에서 에폭 인지로). 7 PIT 아님 · 기록: 0.8 · 0.9 · 0.7 문턱 as-of 재점검 · AE 상수 M4_FIRE_RATE 0.12(C1 m4 보정) · ast_field_map 의 MSM_updated_*.RData '빈티지' 표기(실은 C1).

## 도훈 결정 필요(결정 기록부 MSM-ASOF-SWITCH-20261017)
- D1 2004 전 이력: 통합 신호를 2004-01 에서 자를지 · MSM=NA 로 남길지
- D2 m4 재초기화가 이미 배포된 2026 월을 재서술해도 되는지(선례 PIT-C11-M4-S7-APPLY)
- D3 3단계가 사실상 BOOK_0001 의 m4 입력을 다음 실행에서 바꾼다(= S3) — 그 시점 수용 여부
- D4 BOOK 엔진 factor_engine.R(동결 QEPM 메일박스) 수정 vs 관문 전용 표식
