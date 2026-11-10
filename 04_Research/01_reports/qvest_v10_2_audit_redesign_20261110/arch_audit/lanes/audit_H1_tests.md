# 레인 H1 — 시험 재고 · 분류 · 실행 시간 (1단계 · 읽기 전용)

작성 2026-11-10 13:xx · 시험 파일 수정 0 · 삭제 0 · SUITES 수정 0.

## 0. 산출물
- `tests_inventory.tsv` — 477행(08_Tests 471 + 08_Tests 밖 6 · `08_Tests/scenarios/` 제외 · `_archive*` 제외). 열: path · registered · targets · target_live · last_result · runtime_s · class · confidence · reason
- `tests_delete_plan.tsv` — DELETE 30행(SUITES 줄 · nightly.exclude 줄 · lean.exclude 토큰 · 전용 고정 자료 · 도우미 · 깨질 수 있는 참조)
- `h1_measure_when_quiet.txt` — 조용할 때 잴 목록(현 SUITES 433 경로 전부 — 스위트별 기록이 없다)
- 작업 자료: `h1_suites.json`(SUITES 현판/야간판 · 결과 정렬) · `h1_rows.json` · `h1_live.json`(도달 경로) · `h1_ret.json`(퇴역 표기 46 · 미등록 훅 57) · `h1_runs/`(부하 중 실측 15건 로그)

## 1. 방법(재현 가능)
- SUITES 파싱: `run_all_hooks.sh` 의 `SUITES=(` … `)` 사이 따옴표 줄(주석 제외). 현판 433 · 야간 03:32 판(커밋 357cedcc4) 413.
- 야간 결과 정렬: `hook_dryrun_results.json.tests`(399) 는 SUITES 순서로 쌓이고 미보고 14 는 빠진다 → 야간판 SUITES 순서에서 미보고를 건너뛰며 1:1 정렬. 이름 대조 불일치 0/399.
- 대상 추출: 시험 본문(주석 줄 제외)의 경로 리터럴 · `file.path("..","x.R")` · 파일명 토큰 → 생산 파일로 해석.
- 도달성: 진입점 = 예약 작업 bat(Ready 11 + 충실구현 레인 off cmd → reinforce_auto_tick.sh) · `.claude/settings.json` 등록 훅 · `.claude/**/*.md`(동결 WT 문서 제외) · `round.sh` · `suite_totals_watch.sh`. 생산 코드(주석 제외) 파일명 토큰 그래프 BFS. 동결 문서(qvest-worktask · commands/worktask · forge)에서만 닿으면 frozen.
  - ★한계: 파일명 토큰 BFS 는 과대 도달이다(독스트링 · 문서 언급도 간선) — KEEP 판정은 '죽었다는 증거 없음' 수준(certain 표기도 이 의미). DELETE 는 반대로 git grep -F 로 호출처를 따로 셌다.
- 퇴역 표기: 생산 파일 첫 8줄의 `★RETIRED` · `★★ 퇴역` · `DEPRECATED` (46개).

## 2. 분류 결과 (477)
| class | 개수 | certain / probable |
|---|---|---|
| KEEP | 374 | 358 / 16 |
| DELETE | 30 | 14 / 16 |
| TRIM | 24 | 2 / 22 |
| ORPHAN | 17 | 1 / 16 |
| FIX | 16 | 10 / 6 |
| DECIDE | 12 | 12 / 0 |
| REPIN | 4 | 3 / 1 |

양방향 대조: **SUITES 에 있는데 파일 없음 = 0**(총괄이 Axiom 6줄을 주석화한 뒤 기준). **파일 있는데 SUITES 없음 = 37**(도우미 · 의도적 수동 러너 20 · ORPHAN 17).

### DELETE certain 14 (퇴역 결정이 대상 헤더 · 결정 기록에 있음)
- naver 계열(RAWDATA-QW-ONLY-20261017 · BENCHMARK-QW-ONLY-20261017): `data/test_size_scale_integrity.R` · `hooks/test_benchmark_scale_seam.py` · `data/test_naver_benchmark_confirmed_cutoff.py`(야간 exit1 = 실패 1 계상)
- v10 08-29 무인 리서치 레인 퇴역(★RETIRED 헤더): `hooks/test_auto_alpha_gate_grade_axis.R` · `ops/test_auto_alpha_gate_tiers.sh` · `ops/test_effect_signature_progress.sh` · `ops/test_mode_queue_research_run.sh` · `ops/test_paper_dispatch_backfill.sh` · `ops/test_screen_axes_check.R` · `ops/test_sigma_ab_freshness_gate.R` · `ops/verify_modeq_run_effects.py`(도우미 · 참조 0)
- 미등록 훅 · 호출처 0: `hooks/test_hypothesis_precheck_gate.sh`
- v8 강제 계층(v8_readiness_gate.R 코드 호출처 0): `integration/test_v8_readiness_gate.R` · `validation/test_v8_readiness_hook_dryrun.R`
### DELETE probable 16 (대상 코드 자체가 호출처 0 — 코드 삭제와 짝으로)
contract_regression `test_claim_state` · `test_harness_compliance` · `test_moment_fragility` · `test_proxy_axis` · `test_report_guard` · `test_subsample_null` · contracts `test_census_helper` · hooks `test_overlay_precheck` · factor_db `test_rebuild_fdb_columns` · ops `test_frontier_citation_scan` + data `test_frontier_coherence`(둘 다 ops/frontier_registry_coherence.R) · data `test_rawdata_size_from_quantiwise`(09-23 1회성 도구) · hooks `test_ast_spec_gate`(미등록 훅) · hooks `test_continuity_w3_director_freeze`(미등록 훅) · integration `_e2e_cleanup_guard.sh` · ops `battery_checklist.py`
- ★주의: 살아 있는 대상의 일부 축만 죽은 것은 TRIM 으로 돌렸다(아래). `test_continuity_gate.py`(02_Infrastructure/tests · suite_totals 가 직접 실행)는 KEEP.

### 삭제 뒤 깨질 수 있는 참조
- `tests_delete_plan.tsv` 의 refs 열. 실제로 source 하는 참조는 0. 문서 언급만: `docs/rules/r-portability.md`(ast_spec_gate) · `docs/rules/continuity-firewall.md` · `08_Tests/hooks/_r_portability_baseline.json`(v8_readiness_gate 항목) · `CHANGELOG_constitution.md` · 생산 파일 `ops/frontier_registry_coherence.R` · `ops/paper_research_dispatch.R` 의 주석.
- `profiles/nightly.exclude` 의 11줄 + `lean.exclude` 정규식 토큰(test_ast_spec_gate · test_hypothesis_precheck_gate · test_v8_readiness_gate · test_v8_readiness_hook_dryrun)을 함께 지운다.
- 고정 자료: DELETE 전용 고정 자료 0. `08_Tests/fixtures/naver/` 는 TRIM 대상(test_naver_adjusted_collector · test_rawdata_size_guard)이 쓰므로 그 축을 걷어낼 때 같이 지운다.

### TRIM 24 (죽은 축만 제거)
- `hooks/test_boot_currency.sh` V10~V15(매일 skipped 6 — C9~C11b 은퇴 · AuditWatch Disabled)
- naver/KRX 축: data `test_naver_adjusted_collector` · `test_rawdata_size_guard` · `test_rawdata_source_priority` · `test_seam_scale_guard` · `test_parquet_atomic_write` · `test_rawdata_bm_ret_sync` · `test_daily_refresh_qw_block`
- 무인 리서치 레인 축(alpha_search_queue_run · factor_deep_recheck_run · mode_queue · paper_research_dispatch): ops `test_alpha_queue_pending.py` · `test_factor_recheck_pending.py` · `test_hypothesis_index_paper_lane.R` · `test_llm_lane_wiring.sh` · `test_llm_single_entry.sh` · `test_mode_queue_dispatch_schema.R` · `test_morning_run_rewire.sh` · `test_queue_id_schema_tolerance.R` · `test_research_pool_status_axes.py` · `test_risk_lane_verdict.R` · `test_run_completion_notify.sh` · `test_stage_timeout_and_recharge_stall.sh` · `test_stall_lock_alert.sh` · methods `test_ctx_characteristics.R`
- `data/test_benchmark_level_axis.R` S1(산출 json 까지 스캔해 새 충실구현마다 빨강) · `contract_regression/test_module_registry_exclusivity.R`(reconcile 축)
- (probable 이 많은 이유: 자동 판정 = '대상 일부가 퇴역 표기' — 축 단위 확인은 2단계에서 파일별로)

### ORPHAN 17 (살아 있는 대상 · SUITES 미등록 → 등록)
data `test_freshness_audit_outputs.R`(다른 레인 신규) · `test_global_macro_ingest.py` · `test_hygiene_flag_coverage.R` · `test_qw_ext_ingest.py` · factor_db `test_fdc_read_fastpath.R` · methods `test_eigen_clean_markowitz.R` · `test_p3r03_adapters.R` · ops `test_qvest_machine.sh` · `test_rf_verify_report_composition.R` · `test_tg_scope_key.R` · programs `test_round_kit_pair_alpha.R` · `test_round_kit_shard.R` · reinforcement `test_rf_overlay_full_cash.R` · validation `test_lookahead_c17_comment.R` · 밖 3: `02_Infrastructure/alpha_search/test_hurst_fe.R` · `02_Infrastructure/portfolio/test_weight_engine.R` · `02_Infrastructure/axiom/test_lcode_harvester_family.py`(axiom 폴더 보관 계획과 함께 판단)
- `test_suite_enrollment.sh` 의 야간 실패 1 은 이 미편입을 정상 발화로 잡은 것일 가능성이 높다.

### DECIDE 12 (도훈 결정)
- QEPM WT 동결(QEPM-R0-FREEZE): `hooks/test_worktask_sequence_gate.sh` · `hooks/_worktask_sequence_cases.R` · `integration/test_wt_lifecycle_e2e.R` · `integration/test_execution_path_unified.R` · `worktask/test_wt_inflight_lock.R`(대상 호출처 0) · `integration/_cert_threshold_audit.R` · `hooks/test_sot_access_paths.R`(소비자 worktask_manager.R)
  - 동결을 지키는 시험(`worktask/test_qepm_freeze_*` · `test_qepm_advisor_contract.R`)과 등록 훅 `worktask_constraint_enforcer.sh` 시험은 KEEP.
- 구 pg2 BOOK 리밸 경로(`ops/run_pg2_rebalance_full.sh` 만 호출): `portfolio/test_deployed_holdings_check.sh` · `hooks/test_weight_bound_basis.sh` · `hooks/test_sot_access_paths_py.py`
- noLayer4 페이퍼 트래킹: `ops/test_book_runner_no_interference.sh`(cmd 파일은 있으나 Qvest* 예약 작업 목록 밖)
- AST v1.1: `02_Infrastructure/ast/tests/test_ast_compile.R`

## 3. 실패 107건 분해 (야간 2026-11-10 03:32 · 통과 10,868)
107 = 단언 실패 103(28 스위트) + 요약 없이 exit≠0 4 스위트(각 1). 별도로 UNMEASURED(exit 0 · 요약 없음) 10.

| 원인 | 건수 | 스위트(건) | 현재 |
|---|---|---|---|
| 골든 낡음 → 오늘 REPIN 완료(다른 담당) | 21 | remeasure_from_holdings 7 · inv13_beta_asof 5 · replication_exec_golden 4 · method_adapter_contract 3 · rf_overlay_pit_mask 1 · l2_pool_grade_floor 1 | 재실행 method_adapter 61/61 · l2_pool 9/9 |
| 오늘 04:35 커밋 61868edf2 로 수리 | 10 | program_registry 5 · emission_identity_axes 4 · emission_guard 1 | 재실행 32/32 · 48/48 · 35/35 |
| **진짜 결함 — 이식성 lint 신규 위반** | 38 | r_portability (오늘 41) | 예: `alpha_search/run_paper_replication.R` 금칙⑥ · `programs/program_registry.R` ④ · `programs/round_candidate_gate.R` ④ · `contracts/factor_db_vintage.R` ⑥ · `reinforcement/rf_diversification_gate.R` ③ · `ops/weekly_cleaner_sweep.R` ④ |
| 골든 · 실데이터 의존(REPIN · TRIM) | 15 | map_freshness_content 11 · benchmark_level_axis 1 · label_eligibility_gate 1 · orphan_run_scan 1 · decision_register 1 | 시험 쪽 수리 |
| **진짜 결함 의심** | 9 | rf_fidelity_audit 4(D7 · D7b · D7c · D8 보류 분기 — 충실구현 레인 핵심) · paper_atlas_run 2(작업 폴더 잔존 · 일감 누락 — 1계층 재료 큐) · cluster_power 1(등록부 16 ↔ 상수 15) · rf_weight_arms_explore 1(shrinkage 계열 도달 불가 '★실사고') · rf_audit_not_run_blocks_open 1(C4 rp_verify 호출 지점) | 소유 레인 수리 |
| 환경(Python 3.15 전환) | 2 | paper_intake_resolvers(Sys.which python3/python FALSE) | PATH 또는 해석기 정본화 |
| 대상 퇴역 | 3 | rawdata_size_from_quantiwise 2 · naver_benchmark_confirmed_cutoff 1(exit1) | DELETE |
| 편입 검사기 정상 발화(추정) | 1 | suite_enrollment | ORPHAN 등록으로 해소 |
| 원인 미확인(부하로 미실측) | 5 | refresh_barrier · c11_consumers · mechanism_atlas · matched_controls · replication_slots_lane 각 1 | 조용할 때 재실측 |
| 크래시(요약 없음 · exit1) | 3 | book_rebalance_preflight · module_admission_seam(요약 줄 자체가 소스에 없음) · rx_round | FIX |
| 합계 | **107** | | |

UNMEASURED 10(fdb_state_gate · kr_factor_returns · load_daily_factors · factor_direction_basis · direction_sync · xf_fill_merge · cleaner_distill · rp_commission_basis · rp_count_paper · round_core_measure_server)은 오늘 커밋들에서 요약 줄이 붙었다 — 다음 야간에서 확인(미확인).

### ★배터리 자체의 사고(새 발견 · probable)
- 오늘 두 번째 리프레시(07:14 시작 · 12:15 종료)의 수집 = `hooks=9(fail 0 · unmeasured ?)`(`/tmp/qm_daily_refresh_20261110.log:27801` · `.cache/suite_totals_latest.json`). 결과 파일 `hook_dryrun_results.json` 은 내용 ran_at 03:32 그대로(12:15 에 다시 쓰이지 않음).
- 그 실행 동안 `08_Tests/hooks/run_all_hooks.sh` 가 4번 커밋됐다(09:15 · 10:13 · 11:36 · 12:10). bash 는 스크립트를 바이트 오프셋으로 이어 읽으므로, 루프 뒤 꼬리(결과 JSON 쓰기 · FINAL 줄)가 밀린 오프셋에서 깨져 러너 FINAL 이 안 나오고, suite_totals 가 자식 시험의 `FINAL: … 9 total` 줄을 집은 것으로 보인다(메모리 카드 '실행 중 bash 스크립트 제자리 쓰기 위험'과 같은 계통).
- 패치 제안(러너 = 총괄 소유): `run_all_hooks.sh` 첫머리에서 자기 사본을 임시 파일로 복사해 `exec bash <사본> "$@"`(재진입 표식 env 로 1회만) — 실행 중 편집에 면역. 그리고 `suite_totals_watch.sh` 는 FINAL 을 못 찾으면(결과 파일 ran_at 이 이번 실행보다 오래됐으면) null 로 기록해야 한다(지금은 9 로 기록 → '총계 급감' 경보에만 기댄다).

## 4. 실행 시간
### 기록
- 스위트별 소요 시간 기록 = **없음**(03:32 판 러너는 timings 를 쓰지 않았다 · 오늘 러너에 `timings` 추가됨 → 다음 정상 야간부터 생긴다).
- 배터리 전체: 첫 리프레시에서 hygiene 시작 01:04 → 결과 ran_at 03:32 · 그 사이 hygiene · artifact_index · wiring(14,269 파일 스캔) · 8.1r · 8.2 가 있으므로 배터리 ≈ 130분(러너 주석 '130분'과 일치 · 정확한 시작 시각은 로그에 없음 — 미확인). 413 스위트 → 평균 약 19초.
- 부하 중 실측 15건(신뢰 낮음 · CPU 100% · 다른 레인 동시 실행): benchmark_level_axis 135s · rawdata_size_from_quantiwise 121s · emission_identity_axes 47s · orphan_run_scan 22s · paper_atlas_run 19s · rf_audit_not_run_blocks_open 17s · r_portability 17s · method_adapter_contract 8s · label_eligibility_gate 6s · 나머지 2~5s. map_freshness_content · suite_enrollment 은 300s 상한 전에 중단(총괄 지시로 실측 중지).
- 이 기계 기본 비용(부하 중): Rscript 콜드 스타트 ≈1.0s · `library(arrow)` ≈5s · Python 기동 ≈0.6s · bash 기동 ≈0.24s.

### 느린 원인(코드 정독 · 상위)
| 스위트 | 원인(코드) | 단축안(검출력 불변) |
|---|---|---|
| data/test_benchmark_level_axis.R | `:333-345` 02_Infrastructure · 05_Production · 04_Research/strategies 를 `list.files(recursive=TRUE)` 후 파일마다 readLines(OneDrive 수천 파일) | `git ls-files -z` 로 목록 · 텍스트 검색은 `git grep -l -F BM_Close`(색인) — 같은 분모 · 같은 판정 |
| data/test_rawdata_size_from_quantiwise.R | 실 xlsx · RAWDATA 크기 자료 로드(data 토큰 38) | DELETE 대상 |
| hooks/test_r_portability.R · ops/test_qv_bash.R · data/test_dart_candidate_years.R · hooks/test_c15_load_path_scan.R · hooks/test_telegram_entity_scan.R 등 정적 lint 류 | 각자 저장소 전체를 다시 나열 · 읽음 | 러너가 한 번 만든 파일 목록 + 내용 캐시(`QVEST_TEST_FILE_INDEX`)를 공유 · 또는 lint 류를 한 R 프로세스에서 일괄 |
| hooks/test_safety_guard_memory.sh | 사례 16군 × 무인/평시 × 돌연변이 사본마다 `bash safety_guard.sh` 새로 기동 · 훅이 `_shared_parse.sh` 에서 python 으로 JSON 파싱(사례마다 bash+python ≈0.85s · 119 사례 + 돌연변이) | 훅 판정 함수를 source 해 한 bash 안에서 사례 루프(stdin 대신 변수) · 실제 프로세스 기동 경로는 대표 사례 몇 개만 남김 |
| hooks/test_arm_gen_read_guard.sh(1144줄 · 서브셸 162) · ops/test_llm_single_entry.sh(70) · hooks/test_inject_usage_ranking.sh(70) · hooks/test_auto_commit_*(git init 샌드박스 사례마다) · test_scheduler_task_health_verdict.sh(97) · portfolio/test_deployed_holdings_check.sh(42) | 사례마다 훅/스크립트 프로세스 새로 띄움 · git 샌드박스 반복 생성 | 샌드박스 1회 생성 후 `git stash`/복사로 재사용 · 판정 함수 직접 호출 |
| ops/test_refresh_barrier.sh | `sleep 300` 보유자 + `timeout 300/120` · 대기 루프 `sleep 0.1×50` · Rscript 21 | 보유자 sleep 은 kill 로 끝나 실제 대기는 짧음 — 병목은 Rscript 21회 기동 → R 쪽 판정을 한 프로세스로 |
| ops/test_claude_cli_update.sh | 고정 sleep 2 · 1×10 · 2 · 3 ≈ 17s(잠금 경쟁 재현) | 잠금 대기 상한을 env 로 낮춘 판(예: 0.2s 단위)으로 같은 경쟁 재현 |
| ops/test_rf_clean_lane.sh(서브셸 232 · Rscript 9) · ops/test_replication_slots_lane.sh(111) · ops/test_replication_lane.sh(67) · ops/test_rf_overlay_audit.sh(75) | 가짜 claude/Rscript 를 둔 레인 동적 시험 — 사례마다 레인 셸 전체 기동 | 레인 단계 함수를 source 해 단계별로 · 동적 끝단 시험은 대표 2~3개 |
| validation/test_pit_c11_positive_control.R · regime/test_regime_signal_msm_asof.R · factor_db/test_daily_fdb_pit_c11.R · reinforcement/test_rf_selection_asof.R · regime/test_regime_c11_asof.R | `library(arrow)` + 실 parquet 로드(arrow 토큰 5~11) | 실데이터 축은 주간 층으로 · 밤 층은 합성 소형 parquet(같은 판정 함수) |
| factor_db/test_emission_identity_axes.R(47s) | 실 패널 별칭 9쌍 일치(N6) | N6 만 주간 층 |

### 러너 구조
1. 완전 직렬(`for test_script in SUITES`) — 대부분 시험이 mktemp 샌드박스라 병렬 가능. 등록부 격리 가드(스위트마다 md5+mtime)는 병렬에서 귀속이 흐려진다 → (a) 등록부를 읽기만 하는 스위트 = 병렬 슬롯 4 · (b) 실 등록부 · .cache 를 건드리는 스위트(이번 정독에서 test_rf_fidelity_audit · test_c11_consumers 등은 샌드박스였다) = 직렬 레인, 가드는 레인 경계 + 직렬 레인 스위트마다.
2. 가드 비용: Distilled 카드 477장 md5 를 스위트마다 1회(오늘 2→1회로 줄임 · 러너 주석 ≈1.4s × 433 ≈ 10분) → 먼저 `stat` mtime 합만 비교하고 달라질 때만 md5(쓰기 검출 축은 mtime 이라 검출력 동일).
3. 요약 파싱: 오늘 python 4회 → 1회로 줄임(주석 ≈0.8s × 400). 남은 python 1회(스위트당 ≈0.6s · ≈4분)도 bash 정규식으로 대체 가능.
4. 층 분리: 커밋 전 층(정적 lint · 훅 판정 · 5초 미만) / 밤 층 / 주간 층(실데이터 · 60초 이상). `tiers.json` 골격은 있으나 밤 층에서 빼는 것은 퇴역 11종뿐.
5. 실행 중 편집 면역(§3 사고) — 자기 사본 exec.

### 예상 시간(근거 = 위 기록 · 부하 중 실측 · 러너 주석의 오버헤드 실측치)
- 현재: ≈130분(직렬 · 03:32 판). 오늘 러너 간소화(지문 2→1 · 파싱 4→1)로 ≈(1.4+0.8×0.75)×413 ≈ 14분 감소 추정 → ≈115분.
- DELETE 30 제거: 스위트별 기록이 없어 평균 19s 로 계산 ≈ −9분 → ≈106분.
- 병렬 4 슬롯(직렬 레인 분리): 부하 없는 때 ≈ 106/3.5 ≈ 30분 전후(정확값은 timings 1회 수집 뒤 — 미확인).
- 실데이터 · 60초+ 스위트 주간 층 이동 + lint 일괄: 밤 층 ≈ 20~25분 목표(추정).

## 5. 도훈 결정이 필요한 것
1. QEPM WT 체인 시험 7(+도우미) — 동결 유지 중 삭제할지(권고: 동결 해제 계획이 없으면 시험과 state_machine/cert 코드를 함께 보관소로 · 동결 가드 시험은 남김).
2. 구 pg2 BOOK 리밸 경로(deployed_holdings_check · run_pg2_rebalance_full) 시험 3 — book-rebalance 스킬로 대체됐는지.
3. noLayer4 페이퍼 트래킹(run_nolayer4_monthly) — 예약 작업이 살아 있는지(목록에 Qvest_ 접두 없이 등록돼 있을 수 있음 · 미확인).
4. AST v1.1(ast_compile · ast_verify · ast_spec_gate) 경로를 v10.2 에서 계속 쓰는지.
5. 호출처 0 계약 모듈 10개(claim_state · harness_compliance · moment_fragility · proxy_axis · report_guard · subsample_null · census_helper · overlay_precheck · rebuild_fdb_columns · frontier_registry_coherence) — 코드째 보관소로(결정 불요 · Q 판단 범위로 보임).

## 6. 확인 못 한 것
- 스위트별 실행 시간(기록 없음 · 총괄 지시로 실측 중지) → `h1_measure_when_quiet.txt`.
- 원인 미확인 5 · 크래시 3(부하로 미실측).
- KEEP 판정의 도달성은 파일명 토큰 그래프 근사(과대 도달) — DELETE 쪽은 git grep 으로 따로 셌다.
- TRIM 22건(probable)의 축 단위 확인.
