# PG2 공격형 오버레이 설계 연구 노트 (2026-07-02, Rounds 1~3 종결)

**지시**: 도훈 — "현 PG2 오버레이는 방어형 — 공격형 오버레이 설계해보자"
**대상**: `STR_1715_FaithTrend_on_M4_R05_overlay_PG2` (W1: 강세장 참여 부족)
**방법**: layer5 panel(269개월) 위 스칼라 오버레이 변형 sweep. **n_trials 누적 = 31** (R1 13 + R2 9 + R2.5 5 + R3 4). selection_type=sweep — graduation 시 DSR 적용 대상. metric_type = backtested(panel-overlay), **diagnostic-tier** (forge-authoritative 아님).

## 결론 (클린-타이밍 최종 판정)

**공격형 오버레이 후보 전원 기각. 그 과정에서 panel 타이밍 결함(동월 신호 적용 의심)을 발견 — 이것이 본 스레드의 실제 성과.**

| 단계 | leaky(발견 전) | clean(+1개월 lag) | 판정 |
|---|---|---|---|
| incumbent faith 레이어 | SR 2.116 (기록) | 1.787 — **no_faith(1.897)보다 나쁨 (Δ−0.110)** | 클린 기준 유해 의심 |
| F5 세미분산 (R1 승자) | 2.161~2.224 | 1.782 (vs C1cl t=0.17) | 부가가치 소멸 |
| G3b bull-floor (R2 승자) | 2.228 (t 3.34) | 1.776 (vs F5cl SR −0.006) | **look-ahead 아티팩트 확정** |
| C2_no_faith (R05×m4만) | 1.897 | 1.897 (신호-무관) | **클린 챔피언** (TO 22.5% 최저, oos 1.073) |

- 전 변형 SR이 클린에서 **약 0.35~0.4 하락** = panel 타이밍 누출의 인플레이션 크기.
- G3b는 R2.5 검증에서 OOS 1.119·placebo 100%·subperiod 통과 — 그러나 **신호 1개월 지연에서 붕괴**(2.228→1.995, t 3.34→0.75)가 결정적 단서였음. placebo(순환시프트)·OOS는 동월 누출을 구분하지 못함 — **지연 스트레스가 유일한 판별 검정**이었다는 방법론 교훈.

## 타이밍 결함 (핵심 발견, 별도 감사 이관)

- β-스캔 실증: panel row의 ret_orig 수익 윈도우 = **(anchor[r−1], anchor[r]] — realized_ym 라벨보다 1개월 앞의 달력월** (backward cor 0.731/β 0.881 vs forward 0.058; long-only β≈0.9는 backward에서만 성립).
- 따라서 canonical `run_layer5_faith_overlay.R`의 "S 월말→익월 row" merge는 신호를 자기 수익 윈도우 종료 ~3일 전에 적용. panel 빌더(`run_layer5_rerun_extended.R` L36/600)는 t−1→t를 의도했으나 라벨 정렬이 어긋남 — **m4/β_R05/β_AR (*_lag) 컬럼도 동일 의심** (∴ 클린 라운드의 절대수치 1.7~1.9도 추가 하향 여지, head-to-head만 공정).
- **배포는 클린**: forward_weights_R05_FAITH.R는 전월말 신호→익월 보유. 오염 의심은 panel *백테 진단수치*(SR 2.111 등)와, forge 검증(1.875)이 panel 경유였는지 여부.
- 후속: 감사 태스크 발행 (chip `task_0cf402fb` "PG2 layer5 panel 신호-수익 윈도우 정렬 감사"). pit.md 위반 확정 시 처리 절차 그쪽에서 진행.
- 동근원 선행 발견(같은 날 타 세션): benchmark IKS001→IKS200 버그 수리(10:13 재생성 — 본 스레드 vintage 사건의 원인), 리포팅 realized_ym 정렬 오류.

## 방법론 교훈 (메모리 등재)
1. **data.table by-group 전역벡터 = 조용한 오염** ([[project-r-datatable-bygroup-global-vector]]) — R1 "F3≡C2" 가짜 결과의 원인. 그룹집계 상수성 sanity 의무화.
2. **캐시 vintage 고정** ([[project-cache-vintage-pinning]]) — 라운드 간 benchmark 재생성으로 F5 2.224→2.161 tipping. pinned 스냅샷 + 외부(yfinance) 교차검증.
3. **오버레이류 신호 검증에 지연 스트레스 필수** — placebo/OOS/subperiod 전부 통과해도 lag1 하나로 판별됨.

## 산출물
`stage_artifacts/pg2_offense_overlay/`: R1 `offense_battery_*` / R2 `offense_round2_*` / R2.5 `offense_verify_*` + `bt_result_g3b_candidate.rds`(audit FAIL 표식) / R3 `offense_round3_clean_*` / `benchmark_pinned_20260702.parquet` / 스크립트 3본(버그 수리 주석 포함)

## 남은 경로 (W1은 감사 종결 후 재개)
- 감사 결과에 따라: (a) faith 레이어가 forge-레벨에서도 무가치/유해면 book 구성 재검토(도훈 결정), (b) panel 정렬 수리 후 공격형 후보 재평가 여지(클린 기준 G3b_on_faith_cl 1.801이 클린 조합 최상이었음 — 단 no_faith 1.897 미달).
- 수집 논문 43편 큐는 유효 (W2 earnings@3M·W3 DART insider 경로는 본 결함과 무관).
