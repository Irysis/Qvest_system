# 레인 H1 — 2단계(시험 정리 · 러너 개편) 실행 기록 · 2026-11-10

커밋 · 스테이징 없음(총괄이 스테이징). 롤백 태그 `pre-v10.2-prune-20261110`.

## 1. 지운 것 (파일 삭제 · git rm 아님)
- 시험 26: certain 14(naver 3 · 무인 레인 8 · 미등록 훅 1 · v8 readiness 2) + probable 12(호출처 0 계약 시험 8 · frontier 2 · rawdata_size_from_quantiwise 1 · battery_checklist.py 1) — 목록 = `h1_deleted.json`
- 대상 코드 10: `ops/claim_state.R` · `contracts/{harness_compliance,moment_fragility,proxy_axis,report_guard,subsample_null,census_helper,overlay_precheck}.R` · `ops/frontier_registry_coherence.R` · `data/rawdata_size_from_quantiwise.R`
  - 재확인: 어간 문자열 전역 git grep(99_Archive · stage_artifacts · mailbox 제외) → 남은 언급 = 등록부 백로그 json · 이벤트 로그 · wiring_map · 문서 · 주석(standalone_track_queue.R:426 주석)뿐 = `h1_stem_refs.txt`
- SUITES 24줄 → `# (2026-11-10 H1 삭제 — 사유) 경로` 주석으로 · nightly.exclude 9줄 · lean.exclude 토큰 3 · `_r_portability_baseline.json` 의 삭제 파일 항목 1(test_v8_readiness_gate.R:3)
- 남긴 것(probable 인데 보류): `factor_db/test_rebuild_fdb_columns.R`(대상이 factor_db/ — 다른 세션 수리 중 · 읽기 전용) · `hooks/test_ast_spec_gate.sh`(hook_e2e_battery.py · policies/router_dispatch.json · ast_verify.py 가 참조) · `hooks/test_continuity_w3_director_freeze.py`(handbook_facts_audit.sh(예약 작업) · milestone_commit.sh · memory_knowledge_health.R 가 research_continuity_guard.sh 참조) · `integration/_e2e_cleanup_guard.sh`(DECIDE 인 test_wt_lifecycle_e2e.R 가 source)
- DECIDE 12 손대지 않음.

## 2. TRIM
- `hooks/test_boot_currency.sh` V10~V15(매일 skipped 6) 제거 → 13/13 · skipped 0
- `data/test_benchmark_level_axis.R` S1 — 충실구현 감사 기록(strategies/<id>/FIDELITY.json · fidelity_*.json · prompt.txt) 제외 패턴 추가 · PINNED 에서 그 꼴 2줄 제거 · S3 양성 3 · 음성 4 예시 추가 → 37/37(야간 36/37)
- `data/test_parquet_atomic_write.R` D1 · D2 의 krx_build_rawdata.R 축 제거(케이스 수 불변) → 8/8
- `data/test_rawdata_bm_ret_sync.R` G2(krx 경로) 제거 → 49/49
- 나머지 TRIM 후보 20 은 손대지 않음 — 축 단위로 보면 다수가 '퇴역 경로가 다시 불리지 않는다'는 부재 가드(예: test_daily_refresh_qw_block.sh 는 일일 체인이 naver/krx 를 부르지 않음을 지킨다 → KEEP)라 기계적 제거가 감사 약화가 된다. 파일별 검토 필요.

## 3. 등록
- SUITES: 신규 3(grade_v3_backfill_mark · round_candidate_gate · standing_board_run) + ORPHAN 14 + 러너 양성 대조 1(test_runner_parallel_tiers.sh) + 오후 다른 레인 신규 3(rx_generator_scorecard · rf_cdar_construct · rf_factor_cov)
- 자동 편입: `AUTO_ENROLL_GLOBS=("08_Tests/scenarios/test_scn_*.R|sh|py")` — 실행 시 20개 편입(측정 시점)
- ORPHAN 중 등록 안 한 3: `02_Infrastructure/alpha_search/test_hurst_fe.R`(단언 없는 개발 스크립트 · 실 RAWDATA 2023~ 로드) · `02_Infrastructure/portfolio/test_weight_engine.R`(요약 줄 없음) · `02_Infrastructure/axiom/test_lcode_harvester_family.py`(axiom 폴더 처분 중)
- `ops/test_qvest_machine.sh` 요약 줄에 test 키 추가(없으면 미측정 계상) · `ops/test_paper_intake_resolvers.R` Sys.which 사례를 환경 무관 형태로(8/8)

## 4. 러너 변경 (`08_Tests/hooks/run_all_hooks.sh`) · 양성 대조 `08_Tests/hooks/test_runner_parallel_tiers.sh` 26/26
| 변경 | 양성 대조 |
|---|---|
| 자기 사본 exec(QVEST_RUNNER_COPY/ORIG · 끄기 QVEST_RUNNER_NO_COPY=1) | C1/C2 실행 중 원본 통째 덮어써도 FINAL · 결과 JSON 그대로 · C3 사본 끄면 FINAL 소실(사고 재현) |
| 병렬 슬롯(--jobs > QVEST_SUITES_JOBS > 4) · lane=parallel 만 · 집계는 같은 코드 | A1~A7 슬롯 1 = 4(FINAL · rc · total_fail) · 실패 → rc≠0 · n_parallel 5 · timings 5 |
| 병렬 구간 등록부 지문(구간 앞뒤) | B1/B2 병렬 스텁의 method_registry 쓰기 → registry_dirty · rc≠0 · B3 돌연변이(비교 끔) → 놓침 |
| 층(--tier > QVEST_BATTERY_TIER > full) · profiles/suite_tiers.tsv · 미배정 = nightly | D1~D8 fast ⊂ nightly ⊂ weekly · 미배정 수 표시 · tier 필드 · 알 수 없는 층 rc 2 |
| 자동 편입 + 편입 검사기(ops/suite_enrollment_check.sh) 글롭 인식 | E1 시나리오 실행 · E2 검사기 계상 · E3 돌연변이(글롭 줄 제거) → 미편입 검출 |
| 등록부 지문 묶음(_fp_many: md5sum 1 + stat 1) | 출력 바이트 동일(존재 4 + 부재 1 대조 · FP_EQUAL) · 3회 7.5s → 1.3s |
| 결과 JSON: tier · jobs · n_parallel · n_selected · n_declared · n_unassigned_tier(+ 기존 timings · elapsed_sec) | A5 · D1b · D5b |
| 기존 러너 시험 회귀 | runner_accounting 11/11 · prereq_skip_contract 42/42 · resolve_project_marker 17/17 · suite_totals_anchor 33/33 |

`suite_totals_watch.sh`: 층 = QVEST_BATTERY_TIER(없으면 tiers.json 요일 규칙 · full → weekly)를 러너에 넘김 · 밤 층이면 nightly.exclude 도 · 결과 파일 mtime < 실행 시작 또는 FINAL 없음 → 총계 null(경고 줄) · weekly 를 full 과 같은 단계로 비교/기준선 승격 허용.

## 5. 층 계약 (데이터 레인 · daily_refresh.sh [9] 용)
- 호출: `bash 08_Tests/hooks/run_all_hooks.sh [--tier fast|nightly|weekly|full] [--jobs N]` · 또는 env `QVEST_BATTERY_TIER=fast|nightly|weekly` (인자 우선 · 둘 다 없으면 full=전부)
- 수집 경로: `QVEST_BATTERY_TIER=<층> bash 02_Infrastructure/ops/suite_totals_watch.sh --collect` (env 를 러너에 그대로 전달)
- 종료 코드: 실패 + 미측정(상한 250) · 알 수 없는 층 = 2 · 0 = 전부 통과
- 합계 파일: `.cache/test_results/hook_dryrun_results.json` — `tier`(fast|nightly|weekly|full) · `status` · `total_*` · `timings[]{suite,secs,rc,pass,fail,skipped}` · `n_selected` 등. `.cache/suite_totals_latest.json` 의 `tier` 도 같은 값.
- 층 정의: `08_Tests/hooks/profiles/suite_tiers.tsv` — fast 55 · nightly 352 · weekly 44(451 행 · 병렬 227)

## 6. 미완
- 느린 스위트 코드 단축(safety_guard_memory · refresh_barrier · claude_cli_update · arm_gen_read_guard · auto_commit_*) 미착수 — 해당 스위트는 nightly/weekly 층으로 배정만.
- benchmark_level_axis git grep 전환: 대조 결과 git grep 이 05_Production/4.Statistical-Technical/4-1.Samsara_Protocol 4파일을 못 본다(원인 미확인 — 중첩 저장소 추정) → 분모가 달라져 보류.

## 7. 실측 (11-10 오후 · 기계 포화 중 · 신뢰 낮음)
- fast 1차(71 스위트 · --jobs 1): 2,516s · 1426/16 — 스위트 합 1,855s · 러너 오버헤드 ≈ 9s/스위트(등록부 지문 ≈5s + 요약 파싱 0.7s). timings 로 15s 초과 비핵심 16개를 nightly 로 내림(test_selection_accounting 397s · test_map_freshness_content 374s · test_ax001_defense_scope 158s 등).
- fast 2차(55 스위트 · --jobs 2 · 병렬 20 · _fp_many 적용): **570s** · 1047 pass / 4 fail / 2 skipped / 0 unmeasured · registry_dirty 0 · 결과 JSON 작성 확인.
  실패 4 = test_cluster_power 1(상수 15 ↔ 등록부 16 — 진짜 결함) · test_factor_db_vintage 2(contracts/factor_db_vintage.R — 총괄 통합 경로 · 미조사)
- suite_totals_watch --collect 샌드박스: 자식 FINAL 만 내고 결과 파일 안 쓰는 러너 → hooks null + 경고 · 정상 러너 → hooks 6 · tier 필드 기록(양방향).
- 결과 파일 `.cache/test_results/hook_dryrun_results.json` 은 지금 fast 층 결과(tier=fast)다 — 오늘 밤 체인이 덮어쓴다.
