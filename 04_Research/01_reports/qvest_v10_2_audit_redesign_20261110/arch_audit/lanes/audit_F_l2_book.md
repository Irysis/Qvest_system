# 감사 레인 F — 2계층(로테이션 · 강화) · BOOK (2026-11-10)

## 1. 배선 지도 (코드 · 로그로 확인)
- 야간: `daily_refresh.sh:1091` [8.1r] `rf_role_classify_all.R` → `rf_role_register_reps.R`(strategy_roles.json · 카탈로그 등재) → `:1111` [8.2] `build_module_performance.R` → `06_Registry/module_performance.json`(11-10 생성 · 71 모듈 · 풀 모드 role).
- 1계층 → 풀 배선: `run_paper_replication.R:897` §7-c `rmm_register_measured` → `module_catalog.json`(변형 칸만 · `measure_cell.R:25` 기준/진단 칸은 QVEST_RP_REGISTER=0) → [8.1r] 역할 분류 → 역할 대표만 [8.2] 풀. 상설 판/기저 풀/P4 사슬(`round_core`)은 2계층 풀로 가는 **별도 배선 없음** — 카탈로그 경유뿐이고 epoch · 판 표식 정보는 카탈로그에 실리지 않는다.
- 측정: `reinforce_auto_tick.sh:66` → `rf_l2_auto.sh` → `rf_l2_auto.R`(요청 `06_Registry/l2_unit_request.json` pending ∧ `l2_auto.enabled` ∧ R1) → arm T/S/C `run_wf_ensemble.R`(C11 가용일 정렬 `overlay_pit_guard.R::c11_asof_align` + `assert_overlay_pit` · essence_score) → 원장 `reinforce_ledger_l2.json` → A 면 Judge 요청 파일.
- 상태: ReinforceAutoLoop Disabled · `l2_auto.enabled=false`(09-24 C11 봉쇄 — PIT-C11-REMEDIATION 은 resolved 인데 재개 5키 그대로) · 요청 발행자 `rf_director.R` 10-13 퇴역(파일 없음). 마지막 2계층 측정 = FR_003_n1(09-23 · C) 과 역할 슬리브 v0(10-10 · 5 arm 전부 C · v1 은 MC2 FAIL 로 단계 2 종료 · 원장 미등재).
- BOOK: `register_book_entry`(writer) → `06_Registry/book/book_registry.json` · 트래킹 = `run_nolayer4_monthly.sh`(수동 — 이 PC 예약 작업 없음) → `update_book_tracking` · 리밸 사전점검 `book_rebalance_preflight.py`(소비면 신선도 · 오버레이 축 생존 fail-closed · 시험 18/18).

## 2. 실측 사실
- 풀 71 = essence C 53 · B 13 · F 5. 측정 축: 기록 없음(구 축 K200_KQ150 — 표본 확인 `20260907_101130_20668/01_strategy_spec.json universe=K200_KQ150`) 69 · `all_hyg_2000_v1` 1 · 현 축 `all_hyg_px1000_2000_v1` 1. `fdv_stale` = 71/71 TRUE. 날짜 시작 2005 51개.
- 카탈로그 fr_eligible 848: 현 축 25(전부 B) · all_hyg_2000_v1 29 · 축 기록 없음 794.
- 풀 게이트(`l2_pool_admission.R::l2_admit`)에 epoch · 판 표식 검사 없음. 운영 모드 role 은 `build_module_performance.R:357` 에서 역할 대표를 essence 무관 `eligible = TRUE` 로 편입 → SKILL 의 'essence B+ 2단 게이트'는 legacy 모드 서술(정정함).
- L2 시행 회계: FR_003 n_trials_cumulative 566 · selection_type sweep. 러너는 essence_score 에 selection_check 를 넘기지 않는다 → v3.4 의 `dsr_legacy`(경과 규정) 경로. 시행 집합 계열이 저장되지 않아 선택 현실 점검을 제출할 수 없는 구조.
- 원장 교훈 입력: `rf_l2_auto.R:72` 가 `rf_lessons_digest` 를 읽지만 교훈 문자열에 붙일 뿐 다음 설계(요청) 생성기는 없다(디렉터 퇴역).
- BOOK_0001: mandate · judge_verdict 없음 · 등록부에 epoch · C11 표기 없음(PIT-C11-BOOK0001 '트래킹에 C11 미해소 게이트 표기' 미반영) · 트래킹 이력 5건 · 마지막 11-06(nav 11-05) · 10-07→11-06 사이 30일 무트래킹. 재측정 안 함(읽기만).

## 3. 수리
1. `02_Infrastructure/ops/rf_l2_lib.R` — `l2_a_eligibility()` · `l2_judge_payload()` 신설: 풀 모듈 산출물의 `measurement_axis$epoch` 가 전부 현 축이고 `fdv_stale` 가 전부 FALSE 일 때만 eligible. 사유 코드 `pool_epoch_off_active:k/n` · `pool_factor_db_stale:k/n` · `pool_vintage_unknown` · `pool_unreadable_or_empty` · `active_epoch_unreadable`. 텔레그램 문구: A 보류 표기 · 퇴역 디렉터 언급 정정.
2. `02_Infrastructure/ops/rf_l2_auto.R:127-` — A 면 통과 = `l2_judge_request.json`(schema v1 유지 + a_eligibility) · 보류 = `l2_judge_request.held.json`(트리거 아님) · jlog `judge_held`.
3. `02_Infrastructure/book/book_registry.R` — `confirm` 필수 · `authoritative_path` 필수(mandate 제외)로 권위 등급 A 재도출 · 축 기록 없음/다른 epoch 거부 · 판 표식 낡음 거부 · 판결서 schema v2 ∧ strategy_id 일치 · `update_book_tracking` last_nav_date 역행 거부 · `%||%` 선정의.
4. 문서 사실 정정: `.claude/skills/strategy-rotation/SKILL.md`(§3 현행 role 모드 · 풀 실측 · A 보류 관문 · §5 `fr_id` 인자 없음) · `.claude/commands/book.md`(새 인자 · 관문).
5. 기존 시험 `08_Tests/contracts/test_book_registry.R` 를 새 API 에 맞춤(픽스처만 · 단언 8 그대로).

## 4. 못 고친 것 — 패치 제안
- P-1 `.claude/agents/judge.md:26` · `.claude/skills/reinforce/SKILL.md:3,31` "A 자격 관문 없음" → "A 자격 보류 관문(`rf_l2_lib.R::l2_a_eligibility` · 보류 = l2_judge_request.held.json)". 짝 수리 필수: `08_Tests/worktask/test_qepm_advisor_contract.R:454` `g_l2_gated` 정규식에 `l2_a_eligibility` 추가(지금은 문서가 '관문 없음'이어야 green — 코드와 문서가 다시 갈림). 같이 바꾸지 않으면 G6f/G6g red.
- P-2 `build_module_performance.R` 산출 모듈에 `measurement_epoch` · `fdv_stale` 필드 기록 + 최상위 `epoch_tally`(필터는 하지 않음 — 걸면 풀 71→1). `register_measured_module.R` 도 등재 때 `measurement_axis$epoch` 를 카탈로그에 복사.
- P-3 `run_wf_ensemble.R:684` — sweep 이면 시행 집합(모듈 조합 · hp) 수익 계열을 산출 폴더에 저장하고 `selection_reality_check.R::src_check_dirs` 결과를 essence_score(selection_check=)에 넘긴다. 없으면 2계층 A 는 영구히 경과 규정 DSR 경로.
- P-4 `boot_lean.sh:172` Book 줄에 마지막 트래킹 나이(일) · 35일 초과 ★ — 월간 트래킹 누락을 부팅이 말하게. 예약 작업 `noLayer4_Monthly_PaperTracking` 재등록 여부는 도훈 결정.
- P-5 `module_dispatcher.R:36-40` — n ≤ 3 이면 cap 0.25 와 Σw=1 이 양립 불가해 렌옴이 cap 을 조용히 넘긴다. `fr_diag$cap_infeasible = n*cap < 1` 기록 + 경고.
- P-6 `reinforce_auto_config.json::l2_auto` — paused_reason 의 결정(PIT-C11-REMEDIATION)은 resolved. 재개 여부와 무관하게 사유 문구를 '봉쇄 해제 결정됨 · 재개 조건 = 현 축 풀 재조립'으로 writer 경유 갱신.
- P-7 BOOK_0001 등록부 항목에 `measurement_axis = k200kq150_2005_v1(구 축)` · `c11_gate = unresolved` 표기(writer 에 `set_book_note()` 류가 없으므로 신설 필요 — 06_Registry 쓰기라 총괄 판단).

## 5. 업데이트 누락 감지
| 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 |
|---|---|---|---|---|---|
| module_performance.json | daily_refresh [8.2] | 매일 | rf_l2_auto `stale_pool_days`=7 → 재빌드 | run_wf_ensemble · rf_diversification_gate | 레인 정지 중이라 소비 없음 · 축/판 혼합은 새 A 보류 관문만 잡음 |
| strategy_roles.json | [8.1r] | 매일 | 없음(fail-soft · 직전 판 사용) | [8.2] · register_measured_module | 조용히 직전 판 |
| l2_unit_request.json | (퇴역 디렉터) · 수동 | — | 없음 | rf_l2_auto | 발행자 부재 = 2계층 무기한 정지를 아무도 알리지 않음 |
| reinforce_ledger_l2.json | rf_l2_auto | 시행마다 | 없음 | 세션 Step 0 | 09-23 이후 1건 고정 |
| book_registry.json tracking | run_nolayer4_monthly.sh(수동) | 월 | 부팅 줄에 last_nav_date 만(나이 · 경보 없음) | /book · 부팅 | 30일 공백을 아무도 알리지 않음(10-07→11-06 실측) |
| 리밸 입력 소비면 | 데이터 리프레시 | 매일 | preflight fail-closed(max_lag_days · 앵커) | 리밸 러너 | BLOCK(정상) |

## 6. 속도
- 2계층 1단위 실측(원장): T 23.9분 · S 23.6분 · C 8.8분 = 56.3분/단위(풀 561). 상위 시간 = T · S 의 WF 전체 재실행 · C 의 변형 풀 재빌드. S 는 T 와 같은 IS 추정을 국면만 1달 미뤄 다시 함 → 같은 프로세스 안에서 T 의 IS 모듈 계열 적재를 공유하면 판정 무변 단축(미구현 · 제안).
- 야간 [8.1r]+[8.2]: 유일 측정 소비자 정지 중 — 시간 미측정(로그에 단계 시각 없음). 레인 재개 전까지 [8.2] 를 주 1회로 줄이는 안은 rf_diversification_gate 의 module_performance 소비 때문에 결정 필요.
- 새 시험: test_scn_l2_a_gate.R 42초 · test_scn_book_registration.R 7초.

## 7. P/L 우상향 관점 최대 제약
1. **2계층이 31일째(역할 슬리브 v0 10-10 이후 · 무인 레인은 09-23 이후 48일) 아무것도 재지 않는다** — 요청 생성기 퇴역(10-13) + 레인 정지(09-24) + 역할 슬리브 v1 은 MC2 FAIL 로 중단(10-10). 전천후 결합 층이 비어 있다.
2. **풀이 측정 축 밖이다** — 71 중 69 구 축 · 71/71 판 낡음 · C/F 58. 현 축 B 25개는 카탈로그에 있으나 역할 분류 대표로 거의 못 올라간다(풀 현 축 1). 지금 2계층을 돌리면 결과는 인용 불가.
3. **방어 역할 라벨이 미래로 이어지지 않는다** — v0 MC2: as-of 방어 슬리브의 약세월 잔차 −0.25%/월(t −0.59) · 예측기 방향 AUC 0.675(단순 추세와 동급) · EW_all 이 로테이션보다 나음(PORT_t −0.24 vs T_var −1.00). 국면 라벨 병목이 설계상 그대로.

## 8. 도훈 결정
- D-1 2계층 재개 경로: (가 · 권고) 현 축 1계층 B+ 가 일정 수 쌓일 때까지 정지 유지 + [8.2] 풀에 epoch/판 표식 기록(P-2) · 재개 조건 = '현 축 · 판 최신 모듈 ≥ N'(N 은 v0 슬리브 크기 실측에서) (나) π₀ 레인을 지금 재개(결과는 A 여도 보류 — 새 관문) (다) 레인 퇴역 · 역할 슬리브 v1 만 세션 리서치로.
- D-2 BOOK 월간 트래킹: (가 · 권고) 예약 작업 재등록(월 1회 · 리밸 preflight 통과 때만) (나) 수동 유지 + 부팅 나이 경보(P-4).
- D-3 2계층 A 보류 관문 문서화(P-1) — 1계층 관문과 같은 원칙이라 권고는 승인.
