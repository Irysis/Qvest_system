# 전수점검 발견 원장 (오케스트레이터 Q · 2026-11-10 시작)

상태 표기: [V]=Q 직접 재확인 · [L]=레인 보고(미재확인) · [FIX]=수리함 · [DEC]=도훈 결정 필요 · [OTHER]=다른 세션 영역(손대지 않음)
레인 스크래치: C:/Users/User/AppData/Local/Temp/claude/bded445ba19315c7/9fe22a2f-3836-40d8-8087-87fddf9c12ec/scratchpad/lane{A..P}

## 사용자 지시 (순서대로)
1. Qvest 리서치 인프라 전수점검 시작
2. 인프라에 대한 전수점검이야
3. 1계층 리서치 프로세스, QEPM도 리서치 퀄리티 관점에서 점검 + 목표 달성률을 높이는 방향으로 개선
4. 각 프로세스에 간소화시킬 테스트들도 있는지 확인해서 간소화

## 제약
- 다른 세션 활동 중: "재무 v2 재측정 마무리 — v3.3 A 3칸"(fund_v2_remeasure_20261110/run.sh · 셀 작업자) · "Qvest"(주 세션). 재무 · 팩터 DB · 등급 v3.3 파일은 그쪽 영역 → 수정 금지, 보고만.
- 다른 세션에 임의 메시지 금지(도훈 10-20) — 도훈이 판단.
- 고정 축 · 등급 문턱 완화 금지. 감사 약화 금지. PIT 절대.
- 커밋: 내 경로만 `git add X && git commit` 한 명령(병렬 세션 index 공유).

## Q 직접 확인 (레인 전)
- Q1 [V] 리프레시 3밤 연속 실패 → RAWDATA · 벤치 11-06 정지. 11-10 로그: Benchmarks 시트는 00:17 에 11-09 로 전진(전진=True)했는데 갱신기 rc=1. OHLCVS 게이트 '공통 지평선 11-06'. EXCEL 충돌 3일 49건(combase c0000005 31 · c0000409 18) — 매일 밤 퀀티 단계와 겹침.
- Q2 [V] `.claude/rules/` 미추적 8개(artifact-naming · axiom-engine · caching · codex-round · factor-db · factor-rotation · harness · research_philosophy) = docs/rules 사본과 바이트 동일(factor-rotation == docs/rules/strategy-rotation.md). 무조건 로드 120.0KB 중 105.5KB 가 이것. 2026-06-10 c872957362 에서 git 삭제. `.claude/agents/{blender,strategy-implementer}.md` == agents_retired_v10 사본. `.claude/commands/{qlead,factor-rotation}.md` 도 미추적.
- Q3 [V] 야간 배터리(.cache/test_results/hook_dryrun_results.json · 03:32): 399 스위트 · pass 10,868 · fail 107(28 스위트 103 + 미측정 실패 4) · 미측정 침묵 10 · skip 12. 기준선 08-03 판(954). fail-soft · 결과 소비자 없음. 리프레시 후처리 01:04→03:34.
  실패 스위트: r_portability 38 · map_freshness_content 11 · remeasure_from_holdings 7 · inv13_beta_asof 5 · program_registry 5 · emission_identity_axes 4 · replication_exec_golden 4 · rf_fidelity_audit 4 · method_adapter_contract 3 · test_paper_intake_resolvers 2 · rawdata_size_from_quantiwise 2 · paper_atlas_run 2 · 1건씩: emission_guard · l2_pool_grade_floor · suite_enrollment_guard · benchmark_level_axis · label_eligibility_gate · cluster_power · orphan_run_scan · rf_audit_not_run_blocks_open · rf_weight_arms_explore · decision_register · refresh_barrier · test_c11_consumers · rf_overlay_pit_mask · mechanism_atlas · matched_controls · replication_slots_lane
  미측정 실패(exit 1): book/test_book_rebalance_preflight.py · contracts/test_module_admission_seam.R · data/test_naver_benchmark_confirmed_cutoff.py · programs/test_rx_round.R
  미측정 침묵: factor_db/test_fdb_state_gate.R · data/test_kr_factor_returns.R · factor_db/test_load_daily_factors.R · factor_db/test_factor_direction_basis.py · factor_db/test_direction_sync.py · factor_db/test_xf_fill_merge.R · ops/test_cleaner_distill.sh · ops/test_rp_commission_basis.R · ops/test_rp_count_paper.R · programs/test_round_core_measure_server.R
- Q4 [V] 주입 훅 axiom_context_inject.sh: '현재 최고 연구-tier 전략' = lcode_harvester.py::_pc_top_strategies(858~914) 가 module_catalog.json(1,039 · epoch 표식 없음)에서 PORT_t 순 — 구 축 5건(2건 F)을 모든 Agent 스폰에 주입. QVEST_CLEAN_LANE=1 일 때만 성과 줄 제외. superfan 스폰도 전 기간 성과 줄을 받음(τ_D 규율과 어긋남 — 확인 필요).
- Q5 [V] 저장소: 미푸시 0 · HEAD=origin/main(63a4433b3). 미커밋 M 206 · ?? 865 · D 10. ?? 중 npz 473(`_work/cache` 무시 규칙 없음) · stage_artifacts/l_code/paper_replication 54 · qepm/memory/axioms 10. 브랜치 127(미병합 37) · stash 1(08-02) · 워크트리 elastic-diffie(내용 merged_upstream · prune 후보로 안 잡힘).
- Q6 [V] 결정 대기 5건 전부 2026-10-18 개설(23일): CHARTER-GAPS-4/5/6/7 · P4-SKELETON-REVIEW-20261018(권고 C = 대기). P4 라운드 0. P0R01 verdict not_reached · 9칸 전액 현금 결함 위 측정이라 무효(결정문 근거).
- Q7 [V] health_full.sh = bootstrap.sh(1,241줄) — cleanup --execute · daily_refresh · harvester · cleaner sweep 를 백그라운드로 띄움 → 세션에서 '점검'으로 못 돌림.
- Q8 [V] 실행 환경: 세션 PATH R 4.6.2 · Py 3.15.2 · venv pandas 3.1.1/pyarrow 26.0.1 · R arrow 26.0.0 · PA 2.0.8. 디스크 C 128GB · G 1.4TB 여유. RAM 여유 7.8/31.8GB(06:5x). OneDrive PID 8000 동기 로그 활발. 노트북 게이트 로그 11-08 12:22 이후 없음.
- Q9 [V] 예약 작업: AuditWatch · AxiomActivate · ReinforceAutoLoop · WeightCatalogGrow Disabled / MonthlyDistill · WeeklyCleaner 이 기계 미실행 / FundV2Update rc1(11-09) / InfraCurrency .bat 있으나 작업 미등록.
- Q10 [V] 08_Tests/ops/test_morning_run_*.sh 가 실운영 morning_run.log 에 trigger=test 줄을 씀(02:11) · 실 LOCK 을 백업/복원하며 사용.
- Q11 [V] research-program SKILL §5 "예약작업은 2026-10-13 현재 전부 꺼져 있다" = 낡음.

## 레인 C — 측정 계약 · 등급 (도착 07:25)
- C1 [L→확인 예정] S2 급함: 프로그램 라운드 칸이 A 를 받아도 A 자격 관문 · Judge 트리거가 안 돈다. ops/rf_cell_worker.R(:20,:22,:90) → run_paper_replication.R:259-262,320-329,998 이 '강화 셀'로 취급 → 구판 judge_request.json 만. 수집 러너 reinforce_auto_parallel.R 는 삭제됨. programs · _lib 에 rf_a_eligibility 호출 0. judge.md:25 · DIRECTION_POLICY.md:78 과 불일치. 검사 test_replication_a_gate.R B2 가 구 동작 고정.
- C2 [L][OTHER] 저장 A 5건(현 축 3: P2R03_E3_RX0 · P2R03_E3_L2 · P2R04_E3_RX0 = 재무 v1 측정 · 알파 노치 B→A / 구 축 2) 보류 표식이 기계 판독 불가. judge_request.* 없음. a_eligibility_gate.json 에 fundamentals_v1 · epoch 코드 없음.
- C3 [L] 재채점이 하류 사본으로 전파 안 됨: module_catalog 965 중 267 불일치 · strategy_roles 1,309 중 549 · module_performance 71 중 26. 풀 술어는 사본을 읽음(regime/l2_pool_admission.R:82-91 · contracts/register_measured_module.R:110-125).
- C4 [L] epoch 혼합 방어 코드 0줄(build_module_performance · l2_pool_admission · register_module · register_measured_module · strategy_role* · book_registry · rf_factor_autoregister). 풀 71 = 축 없음 69 + 1 + 1.
- C5 [L] 벤치가 낡아도 측정 진행: load_rawdata 는 RAWDATA mtime 30일만(backtest_harness.R:170) · 내부 결합으로 벤치 없는 날 탈락(backtest_result_contract.R:563-565) · 감사 Check 5 는 벤치가 짧으면 항상 PASS(audit_bt_result.R:159-160). 09-23 측정 41건이 전략 끝 09-22 · 벤치 끝 09-21.
- C6 [L] BOOK writer 가 등급을 권위 파일에서 재판독 안 함(book_registry.R:89 인자 문자열만 · verdict-전략 대조 없음 :92-98).
- C7 [L] S3: UnfaithfulDisc 2009-03-31 이전 전부 결측 = 통과(factor_z_standard.R:84-89) → 2000-01~2009-03 불성실공시 제외 미적용 · 기록 없음.
- C8 [L] S3: 리터럴 중복(rolling_grade.R:27-29 · grade_v3.R:376 & behavior_card.R:268 의 24개월 · strategy_role.json t_A 2.95 · promote_global.R:53 · promote.R:94 · discovery_graduation_gate.sh:150 · beta_controlled_alpha.R:92 · run_paper_replication.R:419,711,725 의 15bps · 25종) · essence_score.R:574 cr_notch_basis 가 값만 · grade_v3_backfill.R:59 `A$dsr` 부분 일치 잠복 · 재채점은 stage_artifacts 만 훑음(120건 v3.3 아님 · 63건 판 표식 없음).
- C9 [L] 정상: 숫자 단일 출처 일치 · 재채점 3,148 = replication 2,959 + alpha_search 189 · essence_grade == grade_v3.grade 3,205/3,205 · 측정 축 주입 경로 · MC2 는 도훈 10-13 폐기(그래서 7/7) · 대기 Judge 요청 0.

## 레인 B — 팩터 DB (도착 07:35)
- B1 [V][OTHER] S1: 총부채 거짓 0. fundamental_derive_items.R:72-73 · data_collector_dart.R:917-918(결측→0). Q 재확인: A373220 TotalDebt FY2023~25 = 0(DART_RESTATED) · 차입금은 QW_V2_DELAYED 로 1년 뒤 날짜 · 202611 Q16==0 472/2,514 · LG화학도 0. 영향 팩터: Q15 · Q16 · Q17 · D60 · R17 · XF_LL01/LL02 · V07 · V13 · V14 · V19 · IN05 · AC05 류. 진행 중 재무 v2 재측정이 이 DB 위.
- B2 [L] S1(소비 좁음): 일간 DB — 성장 16열 2025-03 이전 무값 · 2025-03~2026-02 는 99% 0(phase6.R:407-410 · phase8.R:51-54) / phase 9 · 9b · 9c · 10 미실행(run_fdb_rebuild.sh 는 6 7 8) → 죽은 열 13 · 윈저라이즈 안 됨 / 접근자 라벨 winsorized_raw. 현행 1계층 측정의 일간 DB 호출 0.
- B3 [L] S2: 표준화 모집단에 가격 없는 종목 29~37%(202611 Q16 3,538행 중 1,024 · 재무 나이 중앙 4,908일) → 가격 있는 종목 Z 평균 −0.197. factor_db_builder.R:758-827 유니버스 필터 없음. (Q 재확인: 3538/2514/1024 일치)
- B4 [L] S2: load_month_factors as-of ≤ 신호일 미강제(factor_db_connector.R:367-379,400-404,456 attr 만) · rf_cell_engine.R:278 attr 미확인 → 월중(주간) 신호 때 잠복 미래참조.
- B5 [L] S2: 일간 DB 무인 갱신 경로 없음 · [6b] 경고는 로그뿐(daily_refresh.sh:731-763) · 문턱 5일 vs cache_registry 45일. 지금 lag 4일('47일'은 재빌드 전 값).
- B6 [L] S2: 엔진 패널 사용자 팩터 동결(RP_combo_1403 패널 끝 2026-08-31 → 202609~11 값 동일).
- B7 [L] S2: [5c] FF 요인 · [6e] 결합용 뷰 무인 실행 미실증(11-11 아침 확인 필요) · 결합용 뷰 cache_registry 미등재.
- B8 [L] S2: SE02_Consensus_Revision 28개 달 죽은 배출 · emission_report_gate.R 은 class_R 만.
- B9 [L] S3: 월간 폴더 옛 사본 2개를 discovery_explore.py:301 glob 이 집음 · conditional_ic_matrix.csv 옛 IC 기준 · ic_direction_cache_v1 13,072파일 · build_hash 표기 · factor-db.md 등 수치 낡음(등록 371 · 월간 360 · 일간 316열 · IC 345 · 파일 443).
- B10 [L] 정상: 월간 443파일 빠진 달 0 · 잃은 쓰기 0 · IC 프론티어 일치 · 결합용 뷰 첫 빌드 완료 · FF 요인 md5 = meta · 측정 디렉터리의 직접 읽기 0.

## 레인 D — 무인 운영 (도착 07:30)
- D1 [L] S1: 충실구현 레인 약 70시간 정지. Qvest_ReinforceAutoLoop Disabled = 11-07 노트북에서 끈 것이 넘어온 '미이행'(의도 아님 · 인계 메모 "메인에서 Enable → Export → Apply"). 설정은 켜짐(reinforce_auto_config.json replication_lane.enabled=true). 마지막 틱 11-07 09:30(노트북). 슬롯 3편(1109.3488 · 2106.06164 · 2601.04602) in_progress 고정 · claim 3개(.cache/rf_replication.claim.cpu1|cpu2|gpu1) 소유 PID 없음. alpha-pending 76 · GPU 인계함 4 · 재구현 큐 5. 부팅 '슬롯 3/3' 은 _status.json 나이 미검사(boot_lean.sh:115-119). WeightCatalogGrow 도 같은 미이행. P2R05 GPU 연쇄도 11-07 01:09 에 끝(p2r05_warm.done 없음). → [DEC/도훈 실행] 보통 PowerShell: Enable 두 작업 → qvest_tasks.ps1 -Mode Export → Apply. 노트북 꺼짐 확인 먼저.
- D2 [L] S2: superfan_watch.py:186 — 상태형 이상(신선도 · 완료 표식 · JSON 필드 :319 :351 :374)은 해소 뒤 재위반해도 안 열림. 증거 키 98905f984e94 · 013729485111 · 03c1df5918cb(재발 17~33회 알림 0). 시험 08_Tests/programs/test_superfan_watch.R 에 축 없음.
- D3 [L] S2: 실패 알림 가림 — 감시기 키가 숫자/시각을 지워 task_health '신규실패 N' 이 한 이상(1d54b1add972)으로 묶임 · _sched_failure_classify.sh:415 하루 마커 1개 · dr_fail_signature.R 같은 서명 무음 → 연속 실패 격상 없음(11-08·09·10).
- D4 [L] S2: 검사가 운영 로그/잠금을 씀 — rf_replication_auto.sh:35 LOG 미격리(:107) · test_replication_slots_lane.sh 가 실제 루트 → replication_auto_날짜.log 에 가짜 논문 줄(run_all_hooks.sh:1937) · morning_run.log 머리 372 중 280 이 trigger=test · test_morning_run_live_pid_guard.sh 가 운영 잠금 교체.
- D5 [L] S2: 주간 클리너 텔레그램 8회 연속 FAIL — weekly_cleaner_sweep.R:1129 본문 119~120자 > telegram_notify.R:1084 상한 100. 감시 규칙 없음.
- D6 [L] S2: FundV2Update 11-09 rc1 원인(CompInfo 0칸) 수리됨(207e801e1) · 다음 실행은 살아 있는 퀀티 세션 전제(qw_peer_refresh.ps1:78 exit 3).
- D7 [L] S2: scheduler_task_health.ps1:48 은 Qvest* 만 → noLayer4_Monthly_PaperTracking(BOOK 월간 · 매월 3일) 감시 밖 · Running 무기한 보류(.sh:171) · DailyRefresh 한도 PT72H · StressDaily 건너뜀 무알림 · InsiderBackfill 무동작 + cmd 한글 REM 오류 · AxiomReview rc 항상 0.
- D8 [L] S2: OneDrive 정지 감지 없음 그대로(생존 신호는 로컬 쓰기만) · claim/session_resume PID 에 기계명 없음 · 공유 venv 가 Python315 지정.
- D9 [L] S3: 경보 마커 27 중 26 닫는 코드 없음(unattended_line 17 · replication_env 9) · 최고령 72.8일.
- D10 [L] S3: 작업 18개가 Python312 pythonw 로 hidden_launch.pyw 기동(11-07 등록 잔재) — 단일 실패점.
- D11 [L] S3: session_resume.json 진행 중 4건 전부 죽은 프로세스 → 부팅 줄 'THGNN GPU 학습 중' 허위.
- D12 [L] S3: 아침 체인 fail-soft(program_paper_sync · factor_evidence · morning_briefing · mrs_daily: morning_run.sh:218,248,290,294).
- D13 [L] S3/보안: C:/Users/User/AppData/Local/Qvest/env_backup_20261107_155122.json 에 토큰 · 키 평문. ★레인 D 가 마스킹 실수로 값 3개를 자기 도구 출력에 찍음(세션 기록에 남음 · 보고엔 없음) → 도훈에게 회전 여부 알릴 것.
- D14 [L] 정상: 등록 19개 실행 대상 26개 존재 · 생존 신호 5분 주기 · 아침 체인 11-09 완주 · 11-10 07:10 시작 후 재갱신으로 벤치 11-09 도달 · 주간 증류 W45 11-08 재시도 완주 · CLI 2.1.321 · OAuth 토큰 있음 · 노트북 재대행 없음 · 충돌 사본 0.

## 레인 A — 데이터 수집 체인 (도착 07:30)
- A1 [L] S1: 11-10 원인 = pandas 3(venv 11-08 16:03 에 3.1.1)에서 build_index_cache.py:71 `dtype == object` 가 빗나가 BM_Src 를 float 변환하다 ValueError(로그 273031). 퀀티 수급은 성공. indices.parquet 만 11-09 로 쓰고 종료 → benchmark 11-06 → qw_refresh.ps1 Get-Target(202~214)이 벤치 최신일을 목표로 써서 질의 없이 ALL DONE(273083) → RAWDATA 정지. KTRI 수집기도 bm_max 한도(ktri_index_collector.R:451~474). ★07:05 작업 트리에 `_write_parquet` 수리(미커밋 · 시험 BIC-W1 · 다른 세션 것) → 07:14 ensure_data_current 재실행 → 07:17 벤치 11-09 도달. 4책 수급 · RAWDATA 전진 최종 결과 미확인.
  권고: Get-Target · KTRI 한도 = max(벤치 parquet, krx_holidays 직전 거래일) · indices/benchmark 를 임시 파일에 쓴 뒤 함께 교체 · pandas 3 뒤 한 번도 안 돈 파이썬 진입점(BOOK 리밸 사전점검 · ae_regime_monthly · qw_ext_ingest · NPS append) 건식 실행.
- A2 [L] S2: 11-08 = 두 기계 동시 실행(메인 OneDrive 충돌 → 노트북 main_absent). qvest_machine.sh '메인 없음' 판정이 OneDrive 로 옮겨지는 파일 하나(900초)뿐.
- A3 [L] S2: Excel 종료 충돌 49건 — 전부 정상 닫기(Close→Quit→Release) 1~6초 뒤 · 자료 손실 없음 · rc=1 과 무관. 이 기계 첫 발생 = 11-08 00:38. COM 애드인 = Quantiwise + Adobe PDFMaker + Terabox(LoadBehavior 3) — 뒤 둘이 후보(추정). DATA_Key 동기화가 매일 17책 여닫음(11-10 12/17 충돌) → 정본 목록 불변이면 책 안 열기. 애드인 끄기 = 도훈 결정. 07:16 로그인 때 뜬 빈 Excel(pid 40260) 잔존.
- A4 [L] S2: 신선도 감사 2개가 하루 결손 못 봄 — freshness_audit.R 문턱 달력 3일(로그 274206 rawdata FRESH lag=3d) · cache_freshness_audit.R `.trading_lag`(63~66) 가 벤치 파생 캘린더로 셈(같이 언다). → 기준 = krx_holidays 직전 거래일 · 일간 계열 문턱 0거래일.
- A5 [L] S2: DART 분기 증분이 시즌 후보의 46%만(3,289건×2콜 vs 예산 3,000 · 순서 고정 data_collector_dart_quarterly.R:251 → 뒤 1,787건 조회 0 · 로그 PASS). 10-16 부터 매일. 3분기 보고서 기한 11-16.
- A6 [L] S2(PIT 경계): 신규 상장 보충 수급(-FromOverride 2023-05-17)이 기존 종목 과거 값을 덮음 — 컨센서스 846일 창 bps 23,830칸 · eps 18,992 · 목표주가 16,229 등 변경(로그 247889~). 흔적 = 로그 한 줄. 팩터 DB 는 11-09 재빌드분(옛 판)과 섞임.
- A7 [L] S2: 재무 v2 주간 수급(Qvest_FundV2Update → .cache/qw_fund_v2/)과 fundamental_merged 재생성(월 1회 [5a2/7])이 안 이어짐 → 3분기 값 11-15 유입해도 병합 12-01. qw_fund_v2/* 신선도 미등재.
- A8 [L] S3: 11-09 r2 = OHLCVS 관문 오탐(a25239c25 로 수리) · dk_sync = FundV2_IS 책 잠금 / nps_headcount 163일(정규식 불일치 무로그 refresh_nonreturn_sources.py:126~134) / 죽은 대상(rawdata_pre_naveradj 1.28GB 등) / data_pipeline_queue open 59 중 43건 71~72일 전이 0 / qw_backfill_pending peer 7건 소비자 없음 / daily_refresh.log 33MB(11-10 26,454줄 중 24,933줄이 열 이름 알림) / ensure_data_current 자체 잠금 없음 / KRX 상장 스냅숏 전일 0행.
- A9 [L] 정상: krx_holidays 2009~2027 · 스트레스 일보 대기 로직(낡은 일보 안 냄) · 11-10 밤 재계산분은 날짜만 안 늘고 값 경로 동일 · ECOS/FRED/DART 내부자 최신 · 경보 전달(01:04 텔레그램 · 04:17 감시기).

## 레인 F — 등록부 · 원장 (도착 07:30)
- F1 [L] S1: 등급 사본이 폐기 판 grade_v921 에 묶임 — reinforce_ledger_l1 칸 등급 1,283 중 563(전부 = grade_v921) · module_catalog 965 중 267 · strategy_roles 1,309 중 549 · L1 base_grade 74 중 20. 소비: rf_diversification_gate.R:215(칸 등급 원장 값) · :273(A·B 만 비교 풀) → rf_role_classify_all.R:24,29 → build_module_performance.R:354-363 · daily_refresh.sh:1091,1111 매일 밤. 권고: rfd_members 가 .rfd_auth_grade()(:224)로 읽게. (레인 C3 과 같은 뿌리) 검증 스크립트 laneF/grade_sync.py.
- F2 [L] S2: 레인 죽은 상태가 진행 중으로(D1 과 같음) + 측정 끝난 산출 2개(20261106_123056_16904 · 20261106_202106_42836)가 원장 · 큐에 없음 · _gpu_inbox 재구현 3건 10-20 부터 대기 · engine.R 3건 치워져 engine_path 깨짐 · boot_lean.sh:121 이 읽는 grade_a_queue.json 은 writer 없음.
- F3 [L] S2: BOOK_0001 실현 월수익이 원장끼리 다름 — paper_nav.csv(7월 −8.28 · 8월 +3.37 · 9월 +2.86) vs live_book_series.csv · book_monthly_ledger.csv(−8.86 · +2.71 · +3.02). monitor_nolayer4_paper.R:57 이 없는 달만 덧붙임. last_nav_date 11-05 · daily_nav 87거래일 중 35행.
- F4 [L] S2: 06_Registry 미커밋 수정 33 · 미추적 4(skiplist 24일 · request/reimplement 20일 · L1 원장 +3,316줄 3.3일). replication_slots/ 미추적.
- F5 [L] S2: module_performance.json grade_floor "B" · n_floor_excluded 770 표기지만 실제 풀 71 = B 13 · C 53 · F 5(역할 대표 모드 10-06~ · build_module_performance.R:356,511-512). CLAUDE.md 'B+ 풀' · factor-rotation.md §3 낡음.
- F6 [L] S2: pit_quarantine.json 2건 active(PITQ-C1-MSM ledger_marks pending 31일).
- F7 [L] S2: 국면 발행 원장 frozen_through 11-06 · drift_hard 3회(2023-11-08 Regime_Score 47.34→47.64 · 2012-09-13 4.31→5.17) — 과거 값 변동 · 원인 미점검.
- F8 [L] S3: decision_register writer 우회 흔적 4건(10-10) · 문서가 인용하는 결정 id 6개 축약형 · 열린 결정 5건 blocks 전부 빔 → P4 가 ready/차단 없음으로 보임 · session_resume 4건 낡음 · alpha_frontier_queue 08-23 판(부팅 Queue 줄이 그 상위 2건 표시) · L2 원장 FR_003 active 47일 무진행 · paper_registry paper_key 빈 행 241 · 없는 path 235 · 비원자 쓰기(paper_recharge_daily.R:341) · index_descriptions 없는 키 50 · 절대 경로 담은 등록부 48개 · .bak 66개 git 추적 · 잠금 위치 주석 낙후.
- F9 [L] 정상: JSON 217개 전부 파싱 · 충돌 사본 0 · research_programs 부팅 줄 일치 · 사전등록 md5 12/12 일치 · decision_register 172건 중복 0 · q_judgment 대기 4(C-20261106-008~011) · 미검토 3(J-20261018-006 · 008 · J-20261106-005) · BOOK 엔트리 참조 실재 · 카탈로그 ∩ 격리 0.

## 레인 H — 헌법 · 규칙 · 스킬 정합 (도착 07:35 무렵)
- H1 [V] S2: .claude 미추적 12개(규칙 8 · agents 2 · commands 2) = 추적 사본과 바이트 동일(삭제 직전 blob 과는 다름). 삭제 커밋 c872957362(06-10) · 41eb287159(08-29) · 100314c304(09-03). 무인 레인 lane_provenance 주입 파일 10-17 까지 7개 → 11-01 17:45 부터 15개. 미추적 ∩ 삭제 이력 = 이 12개뿐(되살아난 코드 0). /qlead 는 frontmatter 무효라 모델 호출 가능 상태 · /factor-rotation 중복. 무조건 로드 120,078B → 정리 후 14,573B. 권고: 12개 삭제 + boot_lean 에 .claude 미추적 경보 + qvest_sync 대조 검사.
- H2 [L][DEC] S2: 보호 훅 matcher 에 PowerShell · NotebookEdit 없음(settings.json 49·67·81·91·105·115·127행 · safety_guard.sh:20-21 스스로 한계 명시 · arm_gen_read_guard.sh:42-43 09-25 실사고). 이 기계 기본 셸 = PowerShell. 프로덕션 · 문헌 폴더는 git 밖이라 사후 탐지도 없음. settings 변경 = 도훈 결정.
- H3 [L] S2: 부팅 'ctx ?/50000 ?' 계기 사망 — boot_lean.sh:178-184 CTX() 가 QM_ROOT(C:/Users/99922…) 키 폴더를 봄(실제 전사 = G--OneDrive-Quant-Module-Moltbot). 실측 첫 턴 문맥 163,535토큰(예산 50,000의 3배).
- H4 [L] S2: 판단 원장 11-06 12:47 정지(judgments 35 · 그 뒤 커밋 80개 — 등급 v3.3 발효 · 재무 v2 전환 등 미기록).
- H5 [L] S3: 등급 v3.3 · epoch 표기 전파 누락 — lean-loop.md(자동 로드) 'v3.2' · research-program SKILL §4 v3.1/v3.2 · investment_philosophy_charter.md v3.2 · alpha-search SKILL:16 · agents/alpha-search.md:19 'all_hyg_2000_v1'.
- H6 [L] S3: CLAUDE.md 13,090B / 8,192B — 09-03 부터 68일 초과(상한 = boot_lean.sh:185 · 강제 없음).
- H7 [L] S3: 문서 간 불일치 — 부팅 줄 수(6/5/8) · SKILL §5 '예약작업 전부 꺼짐' · §6 'Fable 미사용' · §4 '리밸 ≥ 주간' · alpha-search SKILL:8,109 'QEPM 은 강화 도구' · :73 보고 양식 · cleaner SKILL:142 없는 methodology_active.md. ★논문 지도 06_Registry/mechanism_atlas.jsonl 없음 — paper_atlas 12일치 로그 전부 '게이트 꺼짐 — 건너뜀'(QVEST_PAPER_ATLAS_ENABLE 미설정).
- H8 [L] S3: '동결' 기계 차단 — qvest-dossier-pipeline.js:31 · state_machine.R:176 은 막음 / qvest-multi-track.js 는 설명만 동결(코드는 alpha-research 병렬 스폰) · /worktask create 가드 없음.
- H9 [L] S3: settings.json allow 33(전면 허용 11 · deny 없음 · 죽은 MCP 9) · settings.local.json git 추적이라 늘 M · .claude/skills 낱개 3개는 로더가 안 실음.
- H10 [L] S3: MEMORY.md 25,550B(한도 여유 50B) · 색인 낡은 행 2(재무 v2 'active = v1' · '충돌 사본 81 승인 대기') · 색인 밖 카드 38.
- H11 [L] 정상: CLAUDE.md 경로 참조 48개 실재 · 훅 13 일치 · 자동 로드 2 + 경로 트리거 4 frontmatter 일치 · 에이전트 핀 · 충돌 사본 0 · 주입 훅 생존(1,944/2,000자).
- H12 [V] 부기(Q): safety_guard 가 Bash 명령에 보호 폴더 이름 + 리디렉션이 함께 있으면 대상이 다른 곳이어도 차단(오탐 — 원장에 쓰려던 heredoc 이 막힘).
- H13 [V] 쌍둥이: commands/qlead.md == commands_retired_v10/qlead.md · commands/factor-rotation.md == commands/strategy-rotation.md(md5 동일) · agents 2개 == agents_retired_v10.

## 레인 E — 훅 · 시험 배터리 (도착 07:50)
- E1 [L] S1: 배터리 08-14 이후 초록인 밤 없음(33 → 60 → 95(PC 이전 전) → 107). suite_totals_watch.sh:77-79 가 러너 stdout 을 버리고 stderr 는 /dev/null → 단언 내용 소실 · 스위트별 건수도 최신 1회분뿐. --collect fail-soft(daily_refresh.sh:1124) · --check 호출자 = bootstrap.sh:1207 뿐 · boot_lean/다이제스트/superfan/텔레그램 소비 0.
  107 분류: ① r_portability 38 = 신규 계약 위반(금칙4 루트 해석 순서 15 · 금칙6 12 · 금칙1 4 · 금칙3 2 + 기준선 2 · 대상 register_module.R · program_registry.R 포함) ② map_freshness_content 11 = 낡은 시험(08-23 폐지 W3/W8) ③ .py 2건 = 러너가 pandas 없는 QVEST_PY 사용 ④ 편입 누락 1 ⑤ emission 계열 5 + 3 = 다른 세션이 04:35 61868edf2 로 수리 ⑥ 데이터 낡음 후보 4(benchmark_level_axis 등) ⑦ 44건 + R 2건(test_rx_round · test_module_admission_seam) 미분류.
- E2 [L] S2: 래칫 무력 — 기준선 954(08-03) vs 10,975 · check 는 latest < baseline 만(:192 :202 unmeasured 미비교 · :221 null 경고만) · 승격은 null 있으면 거부(:232)인데 regime 이 09-12 부터 null → 승격 불가. regime null 원인 = regime/run_all.R 이 sys.source 하는 test_*.R 20개 중 15개가 quit() 호출(예 test_l2_pool_admission.R:223). regime R 20개는 SUITES 에도 전부 있음(이중). FINAL 없이 죽으면 3-part 폴백이 가짜 값.
- E3 [L] S2: 미측정 10 = 만성 5(test_fdb_state_gate.R · test_cleaner_distill.sh · test_rp_commission_basis.R · test_rp_count_paper.R · test_round_core_measure_server.R — 요약 JSON 줄 없음) + 신규 5(61868edf2 로 해소).
- E4 [L→재현 예정] S2: 역슬래시 경로에 눈먼 차단 훅 3개 — worktask_constraint_enforcer.sh:49 `*/optimization_package.json)` · discovery_graduation_gate.sh:81 `*/WT-P*/request.json)` · legacy_write_block.sh:93 `"/_archive_v55/"`. 실제 Write/Edit 경로는 역슬래시(events.jsonl 약 1.39만 대 2). 시험 · e2e 는 전부 슬래시라 초록. legacy 패턴 3개는 디스크 부재. 수리 = 비교 전 정규화(book_write_guard.sh:69 방식) + 역슬래시 사례/돌연변이.
- E5 [L][DEC] S2: safety_guard — PowerShell 미경유 · Bash Rule 2(:351) 는 같은 줄 `>|mv|cp|rm` 뒤 보호 폴더만(tee · cd 후 쓰기 · sed -i · python/Rscript 쓰기 · 소문자 통과) · 문헌 폴더는 Bash 규칙 없음 · 읽기 명령 오탐.
- E6 [L] S2: telegram_direct_call_guard — `Rscript\s+…-e` 만 봄(.exe 전체 경로 · --no-save · 둘째 -e · 스크립트 파일 통과 — 10형태 중 1 DENY).
- E7 [L] S2: backtest_contract_audit.sh:71 PROJECT 미정규화 → :111 R 문자열 역슬래시 구문 오류 → 항상 fail-closed(추정 포함) · find 가 전략 1,302폴더 훑어 45초 초과.
- E8 [L] S2: 미커밋 1,118건 = 레인 · Rscript 산출(자동 커밋 범위 밖 · '레인 무커밋' 10-14 뒤 담는 주체 없음) · factor_registry.json +35줄 미커밋 · 범위 판정이 git toplevel 접두어(:327) — C:\Users\99922 표기 세션은 n_repo 0.
- E9 [L] S3: 고아 시험 17/435(test_qvest_machine.sh · test_superfan_watch.R · test_lookahead_c17_comment.R 포함) · hook_e2e_battery 15사례 중 9가 미등록 훅 · 등록 13 중 10개 사례 없음 · events.jsonl 에 배터리 픽스처 기록(미등록 훅 fired 182/7일 · 약 8만 행) · `${QVEST_PY_BIN//\//}` 오타 38파일 · overlay_pit_grep 로그 전용(소비자 0) · 배터리 2시간 11분 · 06_Registry/layer_bottleneck_map.md 바이트 손상.
- FIX-1 [FIX 07:38] .claude 미추적 12개 삭제(쌍둥이 cmp 동일 + 쌍둥이가 추적 파일 + 대상이 미추적일 때만 rm). 무조건 로드 규칙 120,078B → 14,573B. `.claude/rules` = 추적 6개만.
- FIX-2 [FIX 07:39] .gitignore 에 `04_Research/strategies/*/_work/cache/` 추가(미커밋). 미추적 npz 488 → 0 · 미커밋 합계 1,118 → 623. 추적분 587개는 그대로(추적 해제는 별도 결정).
- C1 [V 07:38] 코드 재확인: run_paper_replication.R `.rp_a_route` 의 cell=TRUE 가지는 구판 judge_request.json 만 쓰고 주석이 "관문 판정 = 강화 러너(reinforce_auto_parallel.R)" — 그 러너는 삭제됨. 프로그램 라운드 칸 A 는 관문 · 트리거 없음. 최소 수리안: 칸 A 를 명시 보류(held:cell_gate_missing) + 부팅 노출 / 정식 수리 = 칸 어댑터(사전등록 변형 수 → 회계 · 계보 표식) — 측정 계약이라 다른 세션 · 도훈과 조율.
- Q13 [V] 충돌 사본 0(프로젝트 전체 + .git) · .git/index.lock.stale_20260925_2352 잔재 · 큰 폴더 .cache 53G · stage_artifacts 37G · 04_Research 11G. 아침 체인이 01_Literature/Alpha_Search_Recharge/20261110/ 에 수집 산출을 씀(설계상 수집기 출력처).
- Q12 [V] 추적 npz 591개(04_Research/strategies/RP_AUTO_2002_06975/_work/cache 587 — 10-13/14 자동 커밋이 쓸어 담음) + 같은 폴더 미추적 488개(10-14~11-10). 캐시가 일부만 추적 → 무시 규칙 + 추적 해제 후보(P2R05 핀 51파일과 겹치는지 먼저 확인).

## 레인 G — PIT 방어선 (도착 07:40 무렵)
- G1 [L][OTHER] S1: FF 요인 연간 정렬이 '나중에 정정될 회사'를 빼고 구성(v3.3 알파 노치 입력). build_kr_factor_returns.R:143-147 이 v2 1단계 표의 `Factor_Date > 구성일` 을 NA 로 빼는데, 그 표는 정정 의심 기업-연도를 다음 해 사업보고서 날로 미룸(build_fundamental_v2.py:211-224 · 같은 파일 22-24행이 '표본 거르기에 쓰지 말 것' 경고). n_sort/n_universe: 2015 0.99 → 2016 0.74 · 2018 0.70 · 2022 0.66 · 2025 0.70. 승급 4건 영향: B→A 3(P2R03_E3_RX0 · P2R03_E3_L2 · P2R04_E3_RX0 · t 최소 4.46) · C→B 1(Piotroski hl t 2.106). 권고: 정렬 편입 가용일 = 최초 공시일 판으로 재구성 + 두 판 재채점 · 수리 전 노치 승급분 잠정 표기.
- G2 [L] S1 잠재: 팩터 관문이 월중 신호일에 그 달 월말 패널(factor_db_connector.R:364-379,397-404 · 신호일 2020-03-10 → as-of 2020-03-31). 셀 엔진(월말) 무영향 · 팩터 DB 쓰는 충실구현 엔진 12종 중 11종 자체 가드. 주간 신호(MC4)에서 샘. (= B4)
- G3 [L] S2: τ_D 경계가 청정 레인 밖에서 기계 강제 안 됨 — arm_gen_read_guard.sh:130 표식 있을 때만(싣는 곳 rx_lane.sh:29 · rf_replication_auto.sh:1022) · 프로그램 라운드 14개 중 청정 레인 산출은 P2R01 하나(나머지는 시험 창을 본 Q 설계 · exposures 자유 서술) · 주입 훅이 Superfan 2종에도 전 기간 성과 줄 주입 · 보는 창/전 기간 구분은 audience 문자열뿐(round_core/v1/pair.R:11) · '시험 창 열람 뒤 설계 횟수' 계수 장치 없음 → A 의 OOS 관문이 반복으로 표본 내가 되어 감.
- G4 [L] S2: Judge 한 번도 가동 안 됨(stage_artifacts/judge 없음 · verdict v2 0건) · writer 는 pit_pass 만(book_registry.R:89-99) · test_judge_verdict_v2.R 은 judge.md 문구 검사 · 재채점 A 3건 관문 미경유.
- G5 [L] S2: overlay_pit_grep.sh 출력 항상 `{}` · 경보는 /tmp/overlay_pit_grep.log 로만(읽는 코드 0 · 훅 39,79-92행) · 11-08~09 경보 15건 전부 soft · 오버레이 연구 아님.
- G6 [L] S2: 정적 검출기는 넘겨받은 파일 하나만(셀 측정은 늘 rf_cell_engine.R — rf_cell_worker.R:88-90) · 주입 시험 없는 패턴 C4 · C6 · C8 · C9 · C12 · C13 · C14 · C15 · C16 · C18 · PY_C1 · PY_C9 · 파이썬 음수 shift 면제가 주석 문자열로도 걸림 · 실례: 11-09 F-Score 엔진 as-of 누출인데 CLEAN → B 발송 → 세션 검토로 발견 → C(e25eac43b). 권고: `data_cutoff` 절단 재실행 대조를 A 전 표준 점검으로.
- G7 [L] S2: 전환 전 등급 '인용 때 재측정' 가드 코드 0(대상 72 전략 · B 이상 48 · affected_strategies_20261109.json) · 권위 기록에 재무 원천/팩터 DB 빌드 해시 없음.
- G8 [L] S2: 재무 v2 잔여 경계 — ≤2014 정정 뒤 값 그대로(행의 46.6%) · 결산월 단일값(47종목) · 공시일 하한 없음(build_fundamental_v2.py:155-156) · TotalDebt 둘 다 결측이면 0(fundamental_derive_items.R:72-73 — 201212 1,090사 · 201912 335사 · 202412 184사). ★G 판독: 구 결함(Q16 0 비율 99.9%)은 사라짐(지금 37% 수준) — 남은 것은 '결측→0'과 '정정 의심 연도 0'(B1). → 사용자 보고 문구 정정: "수리 안 됨"이 아니라 "잔여 결함".
- G9 [L] S2: 호출 0 기계 — validation/pit_enforcement.R(pit.md 가 '상세 코드'로 지목) · c15_load_path_scan.R · 08_Tests/data/test_hygiene_flag_coverage.R(SUITES 밖) · suite_enrollment_check.sh(지금 FAIL 17/435 · 호출자 없음).
- G10 [L] S3: pit.md C4(연간 3/31 · 분기 고정일) ≠ v2 실제 공시일 규칙.
- G11 [L] S3/보안: 02_Infrastructure/config.R:73 에 API 키 평문(git 추적 · 원격에 올라감) → 도훈에게 회전 · 환경변수 이전 권고.
- G12 [L] 정상: 집행 t+1 · 유동성 t−1 · 위생 표식 전진(roll=Inf) · IC as-of 전 지점 · FF 빌더 내부 as-of(원천 표 문제 제외) · 셀 오버레이 assert · 청정 레인 τ_D 절단 시험 · 생존편향(상폐 1,142종목 포함 · 결측 수익 0 처리 · 상폐 수익률 규칙 없음 = D14 기록).
- C1~C15 대응표 요지: 살아 있는 기계 = C1/C3/C7(정적 검출기 → run_paper_replication.R:634 · audit_bt_result.R:521 · round_core standing.R:298) · C2(close_t1 하네스) · C5(assert_overlay_pit → rf_cell_engine.R:1077) · C10(measurement_axis.R:132-141) · C11(fred_availability + 계보) · C13/C14/C15(팩터 관문). 이름뿐 = C6 · C8 · C9(정규식 한 형태 · 주입 시험 0).
- 사용자 지시 5(07:40 이후): "1계층 전략강화 프로세스도 투자철학 준수 및 목표성과 초과달성 관점에서 개선" → 레인 Q(전략강화 프로세스 재설계) 추가.
- Q14 [V] 주입 훅이 레인 Q 스폰에도 전 기간 성과 줄(구 축 STR_AS… SR/CAGR/MDD/OOS + 최근 교훈 전 기간 SR)을 넣음 — τ_D 지시와 충돌하는 실례.

## 레인 L — 1계층 리서치 프로세스 품질 (도착 07:45 무렵)
- L1 [L] S1: A 경로 시행 회계 구멍 — 기준 · 진단 · 지연 칸 사양 45개가 N=216(10-13 값) 고정, 후보 칸은 238~264. 현 축 A 3기록 = 기준 칸 RX0(같은 칸 2기록) + 한 달 지연 진단 칸 L2 = 사전등록상 선택 대상 아님. 계약 산출: S 0.777/0.777/0.774(띠 B) · DSR 0.531/0.531/0.507 · N 216 · 보는 창 위기 방어 '약함' · 귀속 '노출'. 비후보 판별은 사양 최상위 control 만 읽는데(rf_runner_gates.R:873) 라운드 사양엔 그 필드 없음(45/45). 셀 경로 A 관문 없음(= C1). 개선: 사양 최상위 role(후보/기준/진단)을 재채점 · 관문이 읽기 · DSR N = 계보 누적(단일 원장) · 셀 경로 관문 소유자 · L2 로 위반 주입. [DEC] 비후보 A 처분 원칙.
- L2 [L][DEC] S1: 등급 규칙이 결과 미리 보기 뒤 바뀜 — decision_register GRADE-V33-*: 11-09 15:08 'P2R03_E3_RX0 B 유지(A 는 OOS 관문)' → 15:52 OOS 관문 교체 결정 근거란에 A 가 될 3기록 이름과 시험 창 값. 이 3기록엔 표본 밖 관문 아님. 개선(도훈): 규칙 변경은 익명 집계로 · 수혜 기록 표식 · BOOK 전 발효 뒤 전방 추적.
- L3 [L] S1: 설계자(Q) 정보 경계는 선언뿐 — 청정 레인은 P2R01 한 번 · 뒤 10라운드는 시험 창을 본 Q 설계(exposures 기재). 개선: Q 는 보는 창 파일만 열기 · 시험 창 열람 원장.
- L4 [L] S1: 검정력 · 다중성 명세 부재 — 방어 판정 = 깊은 위기 4개 과반 × 결합 조건 11개 × 같은 계보 두 구성 · 사전등록 11건에 최소 검출 효과/거짓 통과율 0 · 시스템 자체 추정: 32칸을 위기 4개로 판정하면 효과 없어도 한 칸 이상 3/4 확률 55~85%(P2T0_rl_probe/DESIGN.md:18) · required_effect_size.R 은 탐침 초안만 사용. 개선: round_core 사양 검사에 최소 검출 효과 기재 의무 · 위기 수 늘리는 엔진 우선.
- L5 [L] S1: 닫힌 10라운드 전부 재무 v2 · 팩터 재계산 전 측정(기준 엔진이 재무 원표 직접 읽음 RP_AUTO_2002_06975/engine.R:316) · 무효/대체 표식은 P2R02 뿐. P2R04 20칸은 방향 정렬 전부 IC 추정(등록부 대체 0/216)이라 방향 결함 영향 없을 수 있음. 개선: 기준 칸 2개를 새 판본으로 먼저 재서 차이를 시드 띠와 견줌.
- L6 [L] S2: 처리량 붕괴 — 10-13~18 6일에 10라운드 → 이후 23일 0. P2R05: 설계 10-18 → 등록 11-06(18.7일) + 미측정. 막은 것 = GPU 경합(레인 THGNN) → PC 이전 → 환경 최신화(사전등록 대체 2회) → 재무 · 팩터 재계산. GPU 임대 20.6시간 동안 워밍 완료 표식 없음. round_core 발효 · P1 상설 자격 · RL 탐침 · P4 판단이 전부 'P2R05 종료 뒤'. Q 자신 기록 J-20261018-006 '병목을 움직일 라운드로 기대하지 않음'. 속도 계획 발효 = 쓰기 잠금 · 레인 슬롯 · GPU 임대 · 훅 / 미발효 = round_core · 측정 서버 · P1 상설 자격 · 라운드 = 세션.
- L7 [L] S2: 수익 엔진 기아 — 32칸 판정 전부 한 계보 · 새 자격 엔진 0 · 레인 10-13 뒤 13건 = B 2 · F 11 · 청정 레인 21편 중 1차 통과 2 · 최종 misdeclared 10(반복 원인 = 팩터 접근자 IC 부호 정렬이 논문의 고정 방향을 뒤집음 · 4편) · P1 '재료 69' = 미구현 논문 65(자료 필요 31) + 엔진 4(B 1) · 다음 논문 = 큐 순서(next_replication.R:12 — 병목과 무관).
- L8 [L] S2: 학습 폐루프 끊김 — L-code 10라운드 중 1 · 실패 지도는 hypothesis_index 가 안 읽음 · 다음 탐침 소비 기록 없음 · R7 계수는 등록부 필드 아님 · 메커니즘 지도 없음 · round_core 에 교훈 단계 없음 · P0 지도 유효 칸 갱신 없음(P0R02 26일 미착수).
- L9 [L] S2: 결정 대기 5건 22.6일+ · P4 는 ready 인데 기본값 '착수 안 함' · CHARTER-GAPS-6 은 11-06 RL 결정문에 들어 있는데 open.
- L10 [L] S2: 감독 — 내용 실효(β 사본 · 다중 시도 문턱이 Superfan 도전에서 나옴 · 방향 판정 중립 3 · 역행 1 · 향함 0) / 운영은 수용 일변(응답 55 = 수용 54 · 철회 1 · 반박 0 · 중앙 4분) · 사전등록 22KB → 201KB · 칸 30/23/16(체계 상한 12 — q_autonomy_decision_framework.md:33) · T3 2회 · 열린 라운드 판단 23일 미검토 · RL 탐침 도전 4건 4일 무응답.
- L11 [L] S3: 초기 5라운드는 git 이 '등록 뒤 측정' 증명 못 함 · 2507.01964 재료 등록부 누락 · writer 는 사전등록 내용 항목 미검사 · 결과 재기록 이력 없음(program_registry.R:261-294).
- L12 [L] 강점: 판정 재현성(핀 · 지문 · 재판정 동일) · 통제 실험 수준(β 사본 · 무작위 짝 200 · 희석 · 용량 · 시드 띠 — 근거 없는 방어 주장 32/32 차단) · 음성 결과 정직 처리. 사전등록 11/11 md5 일치 · 등록 뒤 변경 0.
- L13 [L] 권고 5: ① P2R05 와 분리 — P1 상설 자격(P1S01) 지금 등록(선행 = round_core v1 출시 · 측정 서버 재핀) → 주 0 → 2~3라운드 · 독립 엔진 확보 ② A 경로 봉합 ③ 판본 전환 절차 + 살아 있는 실현 가능성 지도(저장된 보는 창 패킷으로 측정 0 갱신) ④ 사전등록 검정력 기재 + 라운드 열린 동안 환경/자료 변경 동결 ⑤ 종료 단계 기계화(L-code · 탐침 큐 · R7 · validity) + 다음 논문을 병목 엔진 수요로 가중. (부가) 대기 5건을 기본값 · 기한 붙여 한 장으로 재상신 · P4 상태 표기 정정.
- Q15 [V] 충실구현 레인 반복 기각 원인 확인: 청정 레인 엔진 21개 중 18개의 FIDELITY.json 이 'Z_Score_Aligned 는 확장 IC 부호로 방향이 뒤집힌다 — 논문 고정 방향을 못 지킨다'를 신고. 접근자는 11-09 부터 `load_month_factors(direction = c("ic_asof","registry","defensive"))` 지원(factor_db_connector.R:364-366 · registry = 등록부 기대수익 방향 고정 · 자료 무사용). 그런데 레인 구현 지침은 "Z_Score_Aligned 만 소비(C13)"(rf_replication_auto.sh:767 · :870)뿐 — direction 안내 없음. DIRECTION_POLICY.md §2 에도 '충실구현 = registry' 규정 없음. → 수리 후보 FIX-R1: 레인 지침 + 충실도 감사 지침에 '논문이 방향을 고정한 정렬은 direction="registry"' 추가(수동 반전 금지 유지).

## 레인 J — 지식 · 보고 · 텔레그램 (도착 07:50 무렵)
- J1 [L] S1: τ_D 대상 Superfan(판단 · 철학)이 주입 훅으로 전 기간 성과를 받음(샌드박스 렌더로 확인 · len 1944). 처방 3역은 헤드리스 청정 레인이라 안 받음(rx_lane.sh:29-32). 수리: axiom_context_inject.sh:286 CLEAN 판정에 τ_D 대상 에이전트 종류 추가(P3 제외) + test_rf_clean_lane.sh §I 칸.
- J2 [L] S2: 주간 증류 L-code 발행 6주 14건 유실 — lcode_emit.R:121 `.LCODE_MODE_PREFIX[[mode]] %||% "GEN"` 는 없는 이름에 오류(폴백 죽은 코드) · 증류 기본 mode "cleaner"(cleaner_distill_lib.R:478)가 맵에 없음 · distill_manifest_2026{0913,0919,0926,1017,1101,1108}.json lcodes 전부 ok=false "subscript out of bounds" · 로그는 '무인 증류 완주'. 수리: %in% names() 분기 + 요청>0 ∧ 성공 0 이면 rc≠0 + 유실분 재발행(.cache/cleaner_distill/<주>/distill_result.json).
- J3 [V] S2: 주간 스윕 텔레그램 8회 실패(= D5 · Q 확인) · cleaner_sweep_status.json n_fail_steps 읽는 코드 없음.
- J4 [L][DEC] S2: 공리 쓰기 10회 연속 전면 중단([ACTIVATION HOLD] — 09-26~11-07 '주입 길이 1980~2000 > 1900') · 최소 구성이 1,900 초과라 스스로 안 풀림 · proposed 발급 · review_log · 음성 자동 지도 정지 · 단계 상태는 OK 로 찍힘.
- J5 [L] S2: L-code 1,907개 · hypothesis_index 3,055건에 epoch 키 0 · 축 전환 뒤 61건이 구 축 1,846건과 한 코퍼스 · run_paper_replication.R:980 next_probe 고정 문구 "강화 프로세스 축 1 …"(10-13 퇴역)이 매 스폰 [최근 교훈] 꼬리에 · dead 줄 수치 낡음.
- J6 [L] S2: memory_knowledge_health.R HARD 검사 정기 실행자 없음(bootstrap.sh:94 뿐) · 최신 결과는 시험 부작용(test_revival_flags_sync.R:72 가 운영 스크립트 호출 · 운영 카드 제자리 변경 후 복원).
- J7 [L][DEC] S2: 논문 지도 한 번도 안 만들어짐(QVEST_PAPER_ATLAS_ENABLE 미설정 · Qvest_MorningBrief.bat 은 ROUTER_ENABLE 만).
- J8 [L] S2: 스트레스 일보 메일 실패 무음(run_daily_stress.sh:29 가 rc 삼킴).
- J9 [L] S2: hypothesis_index.R:1296 이 ^DISTILLED 전부를 NEG 로 셈 · '[Axiom 승인 대기 363건]' 은 distilled.R:430 이 줄 수로 부풀림(실제 proposed 79) · 승인 카드 22 중 17 만료일 경과 · 부활 발화 21건 미처리.
- J10 [L] S3: 텔레그램 실패 원장 549행 중 536 시험 행 · telegram_notify.R:3362 채널 ID · :76 개인 ID 기본값 리터럴(git 추적) · '신규 0편' 알림 10월부터 매일 · 잠금 1,811개 무정리 · listener 사문 / events.jsonl 81,280행 중 78,835 safety_guard · 30MB git 추적 · 회전은 bootstrap 경로뿐 · qvest_observe --since 무효 · 검색 색인 07-25 판 / lcode_sync_defect 죽은 표식 · index_descriptions 수동(09-05) · 수집 관련도순 고정이라 11월 신규 2편.
- J11 [L] 정상: 무인 활성 OFF(promote.R:663 기본 "0") · 전역 Law 4 · mode-local 0 · DIST 477(expired 300 · proposed 79 · pending 70 · distilled 22 · quarantined 6) · L-code 파싱 실패 0 · 11-14 주간 스윕 실행 조건 갖춰짐 · 텔레그램 토큰은 .env(미추적) · 마지막 성공 11-10 07:12 · PDF/차트 의존성 실재 · 수집 = 로컬 arxiv MCP(세션 MCP 와 무관).
- FIX-3 [FIX 08:0x · 미커밋] 주간 증류 L-code 발행 수리: lcode_emit.R:121 접두 폴백(이름 확인) · lcode_schema.R LCODE_VALID_MODES 에 "weekly_distill" · cleaner_distill_lib.R 에 cd_lcode_item_norm(모드 · 등급 서술 정규화 · record_type summary/process) + cd_lcode_emit_result(NULL = 실패 · 경로 = 성공 · l_code 되읽기) + 전부 실패 표식(jlog · 알림 줄). ★추가 확인(Q): 10-03 · 10-10 '성공' 4건도 디스크에 없음(구판 판독식이 NULL 을 "발행"으로, 실제 성공은 '$' 오류로 읽음) → 09-05 레인 도입 뒤 발행 성공 0건. 10-03 증류가 이 버그를 교훈으로 적었으나 그 교훈도 유실. 시험 08_Tests/ops/test_cleaner_distill_lcode.R 신설(SUITES 편입 · 재발행은 별도).

## 레인 P — 프로세스 내장 검사 간소화 (도착 08:00 무렵)
- P1 [L] 야간 리프레시 11-10: 합계 211분 = 데이터 61 + 후처리 150(위생 감사 1.5 · 색인 1.2 · 배선 지도 11.7 · 역할/모듈 2.9 · 시험 배터리 133). 후처리는 10-05 100분 → 150분으로 증가.
- P-S1 [L→실행 후보] 후처리를 리프레시에서 분리: daily_refresh.sh:1067-1124. 'Daily Refresh v2 Done' 줄을 기다리는 하류 = round.sh:59-67(측정 · 마감 06:00) · ensure_data_current.sh 4단계(`bash "$REFRESH_SH"` 동기 호출 → 아침 브리핑이 배터리 끝까지 대기 — 11-10 07:14 재실행 중) · 감시 규칙 run_failed(01:04 확정 실패가 04:17 알림). 최소판 = 대기 패턴을 `[lock] 데이터 갱신 완료` 로(선례 dart_annual_backfill.R:133). ★round.sh 는 P2R05 핀 파일 — 종료 뒤 손댐. ★daily_refresh.sh · ensure_data_current.sh · morning_run.sh 는 지금 실행 중(편집 금지 — 끝난 뒤).
- P-S2 [L] 시험 배터리 매일 수집 = 무소비(suite_totals_latest.json 소비자 = bootstrap.sh:1207 수동 · v8_readiness_gate.R 1회성) → 주 1회/별도 작업 + 결과를 감시/부팅에 연결.
- P-S3 [L] 검증만 재시도할 때 6축 감사 재실행(rf_fidelity_audit.sh `rm -f "$AUD"` · 팬아웃 41회 중 8회 = 엔진 보존 재시도 · 2601.04602 한 편에 8회) → 엔진 · FIDELITY · 원문 sha · 축 · 프롬프트 키로 재사용.
- P-S4 [L] 감사 앞에 엔진 실행 연기 시험(감사 10~16분 뒤 2분 만에 replication_error 6건).
- P-S5 [L] 측정 뒤 PIT 정규식(rf_replication_verify.R:924-933)을 측정 앞으로(정적 검사 3곳 — 이동).
- P-S6 [L] round_core 켜기 — 필수 지적 17건 중 문장↔코드 표류 11(규칙 단일 출처로 해소) · 미측정 의미 3 · τ_D 누출 1(코어에서 기계화) · 핀 범위 빈칸 3(미해결). v1 미출시(RELEASES 없음 · .cache/round_core/state 없음 · P1S01 미등록).
- P-S7 [L][DEC] 판단 T1/T2 와 철학 P1/P2 겹침(P2R04 T1 도전 3 중 2 · P2R05 3 중 2 가 P1 과 같은 사실) — 안 (a) T2 는 필요 때만 (b) 등록 전 리뷰 1회 + 채점표 2개. '대상마다 전담 1명' 설계 변경이라 도훈 결정.
- P-S8 [L] 등록~측정 사이 환경 판 올림 금지 창(P2R05: 점검 ok 11-06 → 판 올림 11-08 → 재핀 · 재등록).
- P-S9 [L] 신선도 판정 여러 곳 — 같은 실행에서 등록부 감사 RAWDATA CRITICAL vs [0c] FRESH(lag 3 ≤ 3) · 11-09 [0/5] '이미 최신' 직후 self_heal.R 이 STALE 로 재적합 · '직전 영업일' 구현 6곳 → 판정 함수 1개.
- P-S10 [L] 만성 CRITICAL 로 매일 텔레그램(최근 60회 중 52회 · cache_freshness_audit.R:599-600 · fqd05_claimstate.csv 60/60 · nps_headcount_raw 53/60 · rawdata_pre_* 고아) → 등록 또는 제외.
- P-S11 [L] 배선 지도 · 색인 · 위생 감사 주 1회(배선 지도 기준선 08-08 · 드리프트 경고 8회 같은 값 · 위생 경고 77 → 272 · 색인이 추적 INDEX.md 를 매일 다시 써 git 변경).
- P-S12 [L] DATA_Key 동기화 · 재적재를 변경 때만(잠금 창 약 18분).
- P-S13 [L] 같은 사건 다중 경보(리프레시 부분 실패: 00:31 · 01:04 · 04:17 + 아침 사후 감사 + 부팅 3줄).
- P-S14 [L] 경보 요약 open=33 중 17 = 요약 자신의 일일 마커 · 9 = 20~63일 묵은 환경 마커.
- P-S15 [L] 죽은 대상 감시(lane_alive 가 Disabled 작업을 29회 실패로 · l2_auto halt_disabled 틱 215회).
- P-S16 [L][DEC] bootstrap.sh 부작용 6개(:80 cleanup --execute · :87 논문 적재 · :132 코퍼스 재빌드 · :500 리프레시 · :506 하베스터 · :522 주간 스윕) → 읽기 전용 절만 남기거나 퇴역.
- P-S17 [L][DEC] 동결 QEPM 을 지키는 Write 훅 2개(discovery_graduation_gate · worktask_constraint_enforcer — Write 당 약 0.3초).
- P2 [L] 1계층 라운드 P2R04 실측: 설계+P1/T1 76분 · 격리 교차 점검 3회 103분 · 등록→측정+평가 46분 · T2/P2/종료/보고 56분(측정은 16%). 충실구현 레인: 구현 45회 평균 24.8분 · 6축 감사 41회 평균 12.1분(총 8.3시간) · 판정 42건 = misdeclared 30 · adapted 12 · 편당 구현 3.2회 · 감사 2.9회. 훅 지연 Bash 200ms · Edit 343ms · Write 417ms · Read 115ms.
- P3 [L] 줄이면 안 되는 것: 등록 조건 ①~⑧ · 등록→커밋→측정 · R2 md5 / 반증 · 선택 규칙 기계 판정 · τ_D 누출 검사 / 리프레시 배리어 · 칸별 데이터 지문 / 6축 감사 축 수 · 기각 기준 / 정적 PIT 3곳 · Judge / 벤치 게이트 4축 · Size 채움률 · BM_Ret 단일 writer · 배출 회귀 · 방향 동기화 / DR_FAILED 누적 / 철학 P1 등록 조건화 / BOOK 사전점검 / arm_gen_read_guard 전역 등록.

## 레인 N — 목표 달성 깔때기 (도착 08:05 무렵)
- N1 [L] 병목 순위: ① 처리량(라운드 10 → 0 → 0 → 0 · 레인 가동 29일 중 10일 122시간 = 17.5% · testable 86편 25.9일 대기) ② 측정 · 목적함수(현 축 99기록 중 S ≥ 1 = 0 · A 는 노치 3기록뿐 · gate:dsr_sweep 이 B 47 중 42 차단 · 위기 복원력 강함 0/165) ③ 재료의 질(새 축 충실구현 14편 A 0 · B 2 · F 12 · 재료 12건 중 PORT_t<0 9 · 롱숏 9 · 구현 의심 4 · 프로그램 칸 53개 전부 한 논문 엔진) ④ 후속 처리(유효 A 0).
- N2 [L] 깔때기(10-13 이후): 라우터 분류 224편 → 엔진 통과 135 → testable 88 / 충실구현 착수 17편 / 사전 검사 1차 통과 11/17 / 측정 완료 13 / 충실도 감사 1차 통과 4/17(24%) / 재료 큐 등재 11편 / B 이상 2 / 라운드에 쓰임 1편 / 라운드 완료 10 / eligible 0 · held 1 / Judge 0 / BOOK(경로 경유) 0.
- N3 [L] A 를 막는 하한(현 축 B 47): gate:dsr_sweep 42 · floor:port_t 32 · oos:test_window_calmar_vs_bench 15 · floor:sharpe 13 · floor:cagr 9 · floor:calmar 0. 팩터 알파 t ≥ 2.95 인 B 32건 중 남은 미달이 dsr 하나뿐 12건. DSR ≥ 0.5 는 스윕 90기록 중 6건(n_trials 216~260).
- N4 [L] S 성분(현 축): Calmar/0.64 중앙 0.416 · 상위 10% 0.677 · 최대 1.02 / PORT_t/2.95 중앙 0.371 · 상위 10% 0.808 · 최대 0.939 / S 중앙 0.383 · 최대 0.886. S>0 67건 중 Calmar 성분이 더 작은 쪽 66%. 저장 MDD 중앙 0.564(벤치 0.529). 프로그램 칸 53: Calmar 성분 중앙 0.514 · PORT_t 0.594.
- N5 [L] 행동 카드 165장: 위기 복원력 강함 0 · 보통 137 · 약함 27 / 방어 귀속 선택 48 · 크기 40 · 없음 19 · 라벨 없음 58 / 상승 포착 ≥ 0.55 = 111/164 / '강함 ∧ 상승 ≥ 0.55' 0장 / timing_defense_evidence 0건.
- N6 [L] 정지 사유: 모델 한도(10-15~16 33.3시간 · 실패 기동 57회 등) · 10-17 세션 중지 · 10-18 P2R05 GPU 보류 · 무인 체계 전체 무가동 15일 · 리프레시 잠금 대기 14구간 24시간(가동의 20% · 1회 1.1 → 6.9시간) · 11-07 09:30 뒤 틱 0 · GPU 슬롯은 2601.04602 가 10-17 부터 17회 기동 미완.
- N7 [L] 근접 후보 상위 10 전부 한 엔진(2002.06975) · S<1 · 재무 v1 영향. 1위 P2R03_E3_L7 S 0.886(B · dsr). 프로그램 칸 밖 최고 = RP_AUTO_160300751 S 0.627.
- N8 [L] 기타: 라우터 v5 가 3회 실행에서 531건 재분류(경로 뒤바뀜 37편 · 엔진 라벨 48편) · 수집 11회 실행에 새 후보 4 · 라운드 전용 코드 9 → 409 → 835KB · PORT_t = (전략 − KOSPI200) NW t(롱숏 충실구현은 구조적으로 F) · 현 축에서 지금 쓸 수 있는 B 이상 0(재무 v1 영향 72/87).
- FIX-4 [FIX 08:1x · 미커밋] 요약 JSON 줄이 없어 '미측정'이던 만성 5종에 한 줄씩 추가(test_cleaner_distill.sh 25 · test_fdb_state_gate.R 34 · test_rp_commission_basis.R 9 · test_rp_count_paper.R 6 · test_round_core_measure_server.R 34 = 108건이 측정됨 · 5종 모두 실행 통과 확인).
- FIX-5 [FIX 08:2x · 미커밋] 국면 일간 빌더 꼬리 가드 — regime_signal.R build_regime_signal_table_daily: 켜진 시장 자료 층(L1 MSM · L3 KTRI)이 모두 닿은 날까지만 행 생성(덜 온 입력 행의 영구 동결 차단 — 레인 K S1). 시험 08_Tests/regime/test_daily_tail_guard.R 13/13(돌연변이 포함) · 기존 test_regime_signal_merge 13/13 · test_regime_signal_msm_asof 80/80. ★SUITES 편입 · 월간 경로(월 바뀔 때 동결)는 미수리 — 12-01 전 필요.

## 레인 K — 국면 · BOOK · 2계층 배관 (도착 08:2x)
- K1 [V→FIX-5] S1: 국면 원장이 덜 온 입력 행을 영구 동결 가능(regime_signal.R:881,937-939,953-966 일간 · 297-304,550-553,592 월간 / regime_append_only.R:239,257-260,349-350). 월간: KTRI = 그 달 마지막 가용 행 → 월말에 RAWDATA 가 뒤처지면 11월 월간 행(12월 m4 Cash_Pct_lag 입력)이 낡은 층으로 굳음. 권고: 원장에 층별 입력 도달일 · 미도달 행 동결 제외.
- K2 [L] S2: 2계층 풀 축 3종 혼재(71 = 표식 없음 69 + 1 + 1) · 등재기/빌더에 epoch 조건 없음 · 메타 grade_floor "B" 인데 실제 role_rep(C 53 · F 5 · B 13). (= C4 · F5)
- K3 [L] S2: 신선도 정본이 1~3일 정체를 FRESH 로(freshness_audit.R:40-41,46-52) · MRS 브리프 게이트는 그 판정만 · P3 브리프 '오늘의' 고정 문구 · BOOK 일별은 같은 날짜 재발송(mark_nolayer4_daily.R:103,130). (= A4 · P-S9)
- K4 [L] S2: BOOK 월간 예약(noLayer4_Monthly_PaperTracking · 매월 3일 · 다음 12-03) — 이 기계 실행 0 · StartWhenAvailable False · task_health 감시 밖(scheduler_task_health.ps1:48) · 예약 경로에 Gate C/D 없음 · 생성기 실패 rc 0(run_nolayer4_monthly.sh:185-200) · 같은 AS_OF 파일 무조건 덮어씀(forward_weights_D3_M4gAE.R:212).
- K5 [L] S2: BOOK 트래킹 원장 불일치(paper_nav vs live_book_series 세 달 · 누적 약 1.0%p — = F3) · holdout_interval.json strategy_id 가 구 변형 · daily_nav 87거래일 중 35행 · 트래킹 대상이 legacy book_state.json::admitted_ids(resolve_admitted_slot.R:45).
- K6 [L] S2: 국면 계기 — ① regime 시험 러너가 test_c11_consumers.R finish() 의 무조건 quit() 로 죽음(:47-51,592 → 총계 regime null · 20개 중 2개만 실행) ② 동결 구간 재서술 경보 만성(일간 병합 80회 중 71회 · 원인 = ktri_v3_builder.R:143 창이 Sys.Date() 기준 · yfinance→FRED 잔차 · FRED 개정) ③ KTRI v3 `Market == "KOSPI"` 필터 무효(전 시장 — :144).
- K7 [L] S2: 스트레스 일보 메일이 메인 PC 에서 나간 적 없음('Gmail API 승인 전' 뒤 rc 0 · 무알림) · 준비 관문은 벤치만 · P3 일일 예측 45거래일 중 12행(결손 감지 없음).
- K8 [L] S3: '봉인' 주석뿐(portfolio_governor.R pg0~pg3 stop 없음 · run_alpha_search.R:1834,1841 호출 · book_optimizer.R:206-232 가 book_state.json 덮어쓰기 가능) · daily_refresh.sh:871-888 구 3전략 forward weights(10-15 판 'PG2 LIVE' 주식 100%) · 죽은 코드(mrs_dashboard.R · NAV 블록 · portfolio 6개) · 원장 우회 길(telegram_commands.R:57) · 발행 parquet git 밖 · .regen 사본 156개 38MB · 밤 로그 회당 290KB(KTRI 표 전체 출력).
- K9 [L] 정상: 벤치 낡으면 MSM/regime_daily_v2/jump 는 같은 날짜 재계산만 · MSM 모수 연말 재적합 · jump 126거래일마다(다음 약 9거래일 뒤) · t−1 지점 확인 · BOOK_0001 9~11월 비중 지문 = 등록부 · 사전 점검기 작동.

## 레인 M — QEPM 리서치 품질 (도착 08:2x)
- M1 [L] 과거 산출: WT 299(discovery 228 · reinforcement 16 …) · 권위 등급 4건뿐 전부 C(손작성 스키마) · 자기 적대검증 표본 5/5 구체적 · 4/5 가 결과를 바꿈 · 가설 표본 5/5 양질(구 축) · risk 가 결과 바꾼 건 2 · optimizer 가 EW 넘은 것 2/9 · 판정 바꾼 것 0.
- M2 [L] S2: 어드바이저 실사용 0(04_Research/advisor/ README 뿐 · 46일) — 같은 기간 도훈 아이디어 연구 3건은 01_reports 에 직접(rl_strategy_research_assessment · smartbeta_daily_mix · kr_market_stress_index).
- M3 [L] S2: 자문 정의 15개 파일이 현행 목적함수 · 축을 모름(τ_D 0 · epoch 0 · 등급 v3 1 · Σw≤1 0 · LT 위기 0). 낡은 조항: optimizer Σw=1(agents/optimizer-research.md:3,12,40,86 · prompts/optimizer_research_init.md:176,191,353-354,384 min_names 15 · HHI 0.10) · alpha KR_top342 · 18~25bps · LIQ 1e8(agents/alpha-research.md:3,45,60-68 · prompts/alpha_research_init.md:341-345,355,463 HARD 3종 · :37,63,161 PG0/PG1 · :67 DB 288 · :113,156 fable) · risk 이름 붙은 스트레스(prompts/risk_research_init.md:105,211) · 스타일 스킬(TO≤11 · Σw=1 · 훅 강제 표기) · qvest-advisor SKILL:98,136 · common_charter.md:23,205,206,258 · _shared_prefix.md:35,88 · qvest_research_philosophy.md.
- M4 [L] S2: hypothesis_index 3,055건 epoch 0 · A 31 중 25가 6~8월 구 판정 · IN_PROGRESS 31건은 폴더 mtime 착시(hypothesis_index.R:724) · INFLIGHT_STALE 132.
- M5 [L] S2: 검정력 사전 계산의 소비자가 1계층에 없음(QEPM 가설 설계가 쓰던 '착수 크기산술 관문') — round_core · P2R05 사전등록에 required_effect 0.
- M6 [L][DEC] S2: 철학 ⑥ 회전 상한이 살아 있는 등급 경로에 없음(turnover_hard_fail_annual 소비자 = 동결 worktask · 진단 hurdle_gate 뿐).
- M7 [L] S2 잠복: 어드바이저 레인의 A 는 시험 창 비격리(스킬에 τ_D · 노출 기록 없음).
- M8 [L][DEC] S2: QEPM-R0-FREEZE 근거 원문(감사 wf_5a0aea67-884) · 해제 기준이 저장소에 없음.
- M9 [L] S3: 비중 카탈로그 QEPM 유래 14종 중 7종 active 인데 EW 퇴화(MVO_grid · HRP · ERC · Protection_ES · PPO_RL · Genetic · DPL — rx_round.R:101 은 status 만 봄 · 엔진이 '측정 무효'로 멈춰 칸 낭비) · qvest-multi-track.js 조기 종료 없음 · 스텁 스킬 3종 동결 표지 없음.
- M10 [L] 철학 7항 지도: ① Factor Zoo 구현(충실구현 · 등록 371 · 결합용 뷰 · DSR · 알파 노치) / 빔(economic_rationale · redundancy_cluster_id 0/371) ② Cost 구현(15bps) / 빔(손실 함수 회전 벌점) ③ Uncertainty 구현(MC8 · DSR · P2R05 분위 표적) / 빔(μ̂−k·SE · 검정력) ④ DPL 없음 ⑤ Risk 구현(비중 카탈로그 58 · 진단 패킷) / 빔(요인 위험 모형 · 혼잡도 · EVT) ⑥ Implementation 구현(≤25 · LIQ · 15bps) / 빔(회전 상한 · 용량) ⑦ Attribution 구현(MC8 귀속 · β-통제 알파 · 팩터 알파) / 빔(Brinson · Carhart 자동).
- M11 [L] 재가동 3안(WT 체인 해제는 비권고): A 사전등록 설계 규율 이식(기전 주체 · 마찰 · 경로 / 성과 밖 반증 관측 / 판별력 — 기록만 · 차단 없음 · 첫 단계 = P2R03 · P2R04 · P3R03 소급 작성) B 위험 · 귀속 진단을 R 계약으로(diagnosis_packet 에 위기 때 보유 종목 동조 · 유효 종목 수 · 6요인 적재 · 수급 혼잡 — 보는 창 절단) C P4 처방 루프 역할 카드(낡은 조항 뺀 alpha/risk/optimizer 카드 → rx_lane 청정 레인 재료 · optimizer 를 구성 엔진으로 재가동은 비권고).

## 레인 I — 측정 엔진 · 실행 코어 (도착 08:3x)
- I1 [L] S1 조건부: τ_D 날짜 가드가 non-BMP 문자 뒤 날짜를 놓침(perl 없는 gregexpr+regmatches — R 재현) — programs/rx_round.R:178 · contracts/diagnosis_packet.R:66 · round_core/v1/util.R:52,72 · P2R05 evaluate.R:708. non-BMP 실물: RP_AUTO_2302_10175/engine.R 6자 · RP_AUTO_CLEAN_2210_12462/FIDELITY.json 3자. 수리 = perl = TRUE + non-BMP 양성 대조.
- I2 [L] S2: P2R05 운영 핀 드리프트 — prereg(md5 bf45f4e7 · 재핀 11-08 23:37) 운영 파일 50개 중 6개가 다름(run_paper_replication.R · replication_harness.R · grade_v3.R · essence_score.R · grade_v3.json · factor_db_connector.R) + 팩터 레지스트리 핀 4/4 → precheck rc 1 로 워밍 · 측정 불가. 부팅 줄은 패키지 보류만 셈.
- I3 [L] S2: 이식성 검사기 빨강(test_r_portability.R 23 pass / 35 fail · 운영 코드 신규 위반 17파일 — 금칙 ③1 · ④8 · ⑥8: rf_runner_gates.R · diagnosis_packet.R · rx_round.R 등) · 검사 범위(:56)에 04_Research/programs/_lib 없음.
- I4 [L] S2: 환경/계기 실패가 재구현 · 스킵리스트로 굳음 — 환경 분류기는 에이전트 단계 인증 · 한도뿐(rf_replication_auto.sh:1071-1076) · 검증 단계 오류는 전부 replication_error → failed_needs_session(rf_replication_verify.R:146-166,802,873) → 3회 뒤 unreproducible(auto.sh:219-253). 실례 10-17 패키지 스캐너가 'v,0,1' 을 패키지로 오독 → 재구현 21분.
- I5 [L] S2: 핀/지문/캐시 키가 손 목록 — round_core v1 기본 핀(pins.R:6-14)이 셀 측정 source 폐포 34개 중 26개 누락(replication_harness.R · backtest_result_contract.R · audit_bt_result.R · lookahead_detector.R · factor_db_connector.R 등) · 기저 캐시 보조 목록(rf_base_cache.R:44-46) · fingerprint.sh:13-16 에 없는 패널을 읽는 엔진 5개.
- I6 [L] S2: Rcpp 조용한 폴백(backtest_harness.R:61-100 · hurdle_gate.R:73) · Rcpp↔R 동등 시험 0 · 탄 경로가 산출물에 없음.
- I7 [L] S2: 벤치가 전략 창보다 짧아도 통과(= C5) · 측정 진입부 신선도 관문 없음.
- I8 [L] S2: PA 2.0.8 고정의 런타임 단정 없음 · 검증기는 무인 install.packages(verify.R:798).
- I9 [L] S3: C:/Users/99922 하드코딩 950곳/749파일 · 없는 기본값 G:/Quant_Module_Moltbot 42줄 · PATH 의 python3 = Anaconda 3.9.12 · 예약 작업 16/17 런처 Python312 · daily_refresh.sh:51 폴백 R-4.5.2 · R 구판 6개 · 끊긴 참조(daily_refresh.sh:1041 regime_change_detector.R 등) · 고아 코드(alpha_search 144 중 136 · ml_pipeline 52 중 50 · reinforcement 29 · methods 24) · 오늘 06:45 셀 측정이 산출 없이 끝나 panel.parquet 1.74GB 잔재 · 잠금/claim/GPU 임대가 동기화되는 .cache 에 있고 host 없음.
- I10 [L] 정상: 10-13 삭제분 호출 0 · 보관소 코드 호출 0 · R/venv 판과 P2R05 환경 핀 일치 · Rcpp 3모듈 11-08 재빌드 · generator_pins · msm_param_pin sha1 일치 · 리프레시 잠금 경로 동일(/tmp = %TEMP%) · GPU 임대 free · bare bash/makeCluster 직접 호출 0 · RETIRED 를 측정 경로가 source 하는 곳 0.
- E10 [L] 정상: 훅 13개 존재 · bash -n 0 · 필수 4종 fail-closed · 양성 대조 초록(safety_guard_memory 119 · hook_fastpath_equivalence 125 · book_write_guard 5 · constraint_v10 4 · backtest_contract_audit_gate 10 · arm_gen_read_guard 334 · auto_commit 98) · contract_regression 90 · continuity 31.

## 수리 기록 (이어서)
- FIX-6 (08:4x) axiom_context_inject.sh — Superfan 스폰(subagent_type/description/prompt 앞 1500자에 superfan)엔 변동부(성과 · 교훈 · dead) 제외 · 계측 tau_d_agent · 시험 test_axiom_inject_tau_d.sh 17/17(편입). 미확인: memory_knowledge_health.R HARD_10 이 마지막 주입 표식을 읽는데 tau_d/clean 주입을 면제하는지.
- FIX-7 (09:0x) τ_D 날짜 정규식 perl = TRUE — rx_round.R(.rx_assert_clean) · round_core/v1/util.R(2곳). diagnosis_packet.R:66 은 P2R05 핀이라 재핀 때 같이. 시험 test_tau_d_date_nonbmp.R 32/32(편입).
- FIX-8 (09:0x) rx_round.R .rx_strip_dated_notes — 팩터 등록부 정의문의 날짜 붙은 유지보수 주석(L35 · R19 · 11-09 추가)이 처방 도구 상자 생성을 막던 것 해소(검사 약화 아님 · F5). test_rx_round.R 35/35.

## 레인 R — Axiom 엔진 존치 검증 (도착 09:2x · 내가 재확인: HOLD 20줄 ✓ · round_core L-code 0줄 ✓ · 마지막 주입 1944자 9단 dist=false ✓ · DIST 인용 8종 ✓ · 활성 공리 4건 ✓)
- R1 가치는 '교훈 기록 · 조회'(L-code 원장 + hypothesis_index)에만. 프로그램 설계 13 중 3 라운드(P2R03 · P2R04 · P2R05) 인용 · 후보 제외 사유가 된 것 1건(P2R05 분포 회귀 — DIST-AR-056). 판단 원장 35 중 1.
- R2 승격 기계 · DIST 수명주기: 90일 결정 기여 0. 08-23 무인 승격 19건 → 09-23 전부 롤백(틀 문장 · positive 라벨인데 1승 5패). 승인 카드 22의 마지막 정제 08-23. 인용된 DIST 8종 전부 승인 상태 아님(proposed 6 · pending 1 · expired 1).
- R3 주입 훅: DIST 전달 0(감축 9/10단) · 무인 R 레인엔 닿지 않음 · 효용 절제 측정 AX-D7(09-23 승인) 미실시.
- R4 유지: 주간 스윕 3.5 = 10주 HOLD(★고장 아님 — 도훈 승인 정책 AX-D8) · 부활 발화 21건 stdout 뿐 · distilled_usage 08-23 뒤 정지 · 예약 3개(WeeklyCleaner · AxiomReview · MonthlyDistill) · AxiomActivate 꺼짐.
- R5 승격 0 원인: (d) round_core 가 L-code 를 안 만든다(프로그램 라운드 13 중 2만) + (c) L-code 1,907 · 색인 3,055 에 측정 축 표식 0 → 군집이 구 축/현 축 혼합 + (a) 실패 축 independence 119 · external 107 · falsification 90 · mechanism 70(리뷰 140 · 통과 0). (b) 문턱은 원인 아님.
- R6 ★오염 사례: P2R03 의 DIST 인용을 판단 Superfan 이 C-20261017-033 으로 도전(전기간 평균 = τ_D 뒤 포함).
- R7 코드: axiom/ 22파일 9,380줄 + 소비자 5종 5,069줄 + 시험 2,228줄 · 엔진 스위트 16개 403검사(실패 cluster_power 1) · 유지 커밋 8월 56 → 9월 16 → 10월 5 → 11월 3.
- R8 권고: (1) 기록 · 조회 존치 + 측정 축 표식 · τ_D 경고 (2) 승격 · DIST 수명주기 퇴역 · 보관 (3) 주입 변동부 퇴역 · 고정부는 CLAUDE.md 파생 유지 (4) 주간 3.5 · 월간 증류 · 승인 큐 퇴역.
- R9 의존 주의: continuity_gate.py(Continuity Firewall — 엔진 아님 · close_round · weekly_sweep · suite_totals 사용) · constraint_firewall.R(close_round:128 선택 사용) · lcode_emit/schema(run_paper_replication · cleaner_distill_lib) · lcode_harvester(색인 원천) · lcode_validity. promote.R 를 부르는 생산 코드 12곳 · hypothesis_index 참조 57파일.
- FIX-9 (09:4x) 충실구현 레인 방향 안내 — rf_replication_auto.sh 구현 지침(논문 고정 정렬 · 여러 시점 횡단면 학습엔 direction = "registry") + 감사 축 정본 rf_fidelity_axes.json signal 축 focus(구현자 자가 감사 · 감사자 동일 문구). 시험 7종 통과(rf_preaudit 100 · paper_text 20 · prompt_format_safety 7 · fidelity_fanout 37 · clean_lane 107 · fanout_merge_root 27 · llm_fallback 27).
- FIX-10 (10:0x) superfan_watch.py — 상태형 규칙(신선도 · 완료 표식 · JSON 필드)의 해소 뒤 재발이 'seen' 으로 묻혀 알림이 안 가던 것 → resolved 면 재개방. test_superfan_watch.R 41/41(+7 · 돌연변이 1). 감시 계열 3종(superfan_watch · q_judgment_ledger 50 · session_resume 13) 배터리 편입.
- FIX-11 (10:2x) 주간 클리너 스윕 보고(요약 120자 · 8회 연속 발송 실패) + 무인 증류 완료 보고(104자 · 매번 실패) — 짧은 헤드라인 + 불릿 + 초과 시 자르는 안전망(.tg_headline · cd_tg_headline). test_cleaner_tg_headline.R 20/20(편입). 다른 summary 발송부 전수 스캔 = 초과 없음.
- FIX-12 (10:4x) boot_lean.sh — LANE_TICK(레인 디스패처 틱 나이 · 문턱 = 감시 정의 lane_alive.max_age_h · 실측 '★틱 71h 전') + CTX 폴더 찾기(게이지 실측 ctx 163,535/50,000 — 좀비 룰 105KB 가 주범 추정 · 다음 새 세션에서 재측정). test_boot_lean_lane_tick.R 16/16(편입).
- FIX-13 (11:0x) 차단 훅 3종 역슬래시 경로 사각지대 — worktask_constraint_enforcer(26종 패키지) · discovery_graduation_gate · legacy_write_block: 정슬래시 block · 역슬래시 allow 실측 → 경로 정규화. safety_guard · book_write_guard 는 원래 양쪽 차단(확인). test_hook_backslash_paths.sh 20/20(편입) · fastpath_equivalence 125 · worktask_constraint_enforcer_v10 4 회귀 없음.
- FIX-14 (11:3x) telegram_direct_call_guard.sh — 페이로드 추출 확장(전체 경로 Rscript.exe · 다른 플래그 · 둘째 -e · R -e · 변수 실행기 · heredoc). 수리 전 차단 = 10형태 중 2(D1 · D8). test_telegram_guard_forms.sh 23/23(편입 · 음성 8 · 돌연변이) · fastpath_equivalence 125. 남는 한계 = 파일로 돌리는 꼴 · PowerShell 미경유(H2).
- FIX-15 (11:5x) backtest_contract_audit.sh — PROJECT 역슬래시 정규화 + 경로를 환경 변수로 R 에 전달 + 전략 폴더 전체 find → 두 깊이 glob(2초). 수리 전: 역슬래시 PROJECT 에서 integrity=PASS 도 '내부 오류'로 차단(돌연변이로 재현). test_backtest_contract_audit_gate.R 14/14(+4).
- 미해결 기록: legacy_write_block 대상 폴더 3종(_archive_v55 · legacy/v55 · _archive_4_6)은 디스크에 없다(99_Archive 밖 깊이 4 이내 0) — 죽은 대상 훅(보관소 99_Archive 로 재지정 또는 등록 해제 = v10.2 판단 항목).
- FIX-16 (09:0x) 월간 국면 원장 — 덜 온 입력으로 만든 지난달 행의 영구 동결 차단. regime_signal.R: .rs_month_last_session(자료와 독립 · 휴장일 등록부) + 표시 블록(파일 속성 input_incomplete_dates) / regime_append_only.R: 표시된 달 동결 보류(행은 실림) · allow_incomplete · --allow-incomplete · 결과/드리프트 로그 held_incomplete. test_monthly_incomplete_hold.R 25/25(편입 · 사고 재현 대조 D1/D2 · 돌연변이 2). 회귀: ledger_c11 142 · merge 13 · msm_asof 80 · tail_guard 13.
- FIX-17 (09:0x) memory_knowledge_health.R HARD_10 — 청정 레인 · 정보 경계 대상 스폰이 마지막 주입이면 마커 3종 부재가 정상 → 마커 검사 면제(길이 · 신선도는 그대로). 블록 추출 일회성 확인 5사례 정상.
- FIX-18 (09:1x) venv 삭제 감시 표식 재배치(.venv_qvest_ml/.canary_20261110 — 11-08 재생성 때 누락) → boot_currency 15/15. SACL 재적용은 관리자 PowerShell(도훈).
- 메모: 버전 표기 정합 검사 대상 = CLAUDE.md Active Version · bootstrap.sh 배너 2곳 + 상태 라벨 · .claude/commands/qvest.md 헤더 · 00_Lawbook/INDEX.md 헤더(v10.2 때 함께 갱신).
- 메모: 주간 증류 유실 교훈 = 18건(W37~W45 · .cache/cleaner_distill/<주>/distill_result.json) — 재발행은 Axiom 기록층 표식(측정 축 · τ_D) 결정 뒤로 미룸.
- (시각 정정) FIX-9~15 에 적은 시각(09:4x~11:5x)은 추정 오기 — 실제는 08:20~09:00 사이.

## 야간 배터리 빨간 스위트 분류 (11-10 03:32 결과 28종 103건 + 미측정 실패 4 · 09:20~09:40 재실행)
- [수리함] program_registry 5(운영 큐 · P4 상태 · 줄 수를 빌려 쓴 시험 → 사본에서 비움 · 32/32) · decision_register 1(부팅 줄 수 6 고정 → 머리말 선언과 대조 · 25/25) · r_portability 38 → 34(내 perl 수리로 2곳 해소).
- [지금은 통과] emission_identity_axes · emission_guard(밤에는 팩터 DB 재계산 중이라 실패).
- [데이터 판본 변경 → 골든 재핀 필요 · 팩터 DB 수리 뒤] remeasure_from_holdings 7(n_days 5336 vs 5337 · 비트 불일치) · replication_exec_golden 4 · inv13_beta_asof 5 · rf_overlay_pit_mask A4(1920 vs 1860행).
- [시험이 운영 상태 · 옛 구조에 의존] map_freshness_content 11(06_Registry/layer_bottleneck_map.md 손상 · 대상 훅 미등록) · rf_fidelity_audit 4(.slot_book_lock 함수 이동) · rawdata_size_from_quantiwise 2(설정 플래그) · paper_atlas_run 2 · mechanism_atlas 1 · orphan_run_scan 1(실 로그 의존) · benchmark_level_axis 1(새 레인 산출물 4개 미분류) · label_eligibility_gate 1 · rf_audit_not_run_blocks_open 1 · rf_weight_arms_explore 1 · refresh_barrier 1(E2 slots_tick_failed) · c11_consumers 1(G1a 원판 대조) · matched_controls 1 · paper_intake_resolvers 2(파이썬 경로) · cluster_power 1(계열 수 상수 15 vs 등록부 16 — 실제 드리프트).
- [실제 결함 후보] method_adapter_contract 3(HRP · NCO · ERC 가 픽스처에서 EW 와 동일 — 폴백인지 픽스처 한계인지 확인 필요 · P3 라운드 신뢰와 닿음) · l2_pool_grade_floor 1(2계층 풀에 F · C 수록 — 하한 B 위반 실재).
- 러너 수리: 스위트별 경로 · 초 · rc 기록(timings) · 파이썬 5회 → 1회 · 지문 재사용(스위트당 4.7초 → 2.2초 · 구판과 결과 동일 10종 359건) · suite_totals_watch 같은 날 재수집 건너뜀 · 출력 로그 보존 · regime 합계 = timings(중복 러너 제거). 시험 runner_accounting 11 · suite_totals_anchor 19.

## ★핵심 사실(도훈 '한계없이 고민 · 결론' 지시 뒤 확인)
- BOOK_0001 오버레이(pg2_risk_overlay_v1 · gate × β_R05)는 09-24 부터 suspended: 입력 AE · m4 패널이 C11(미공표 주간 STLFSI4/NFCI · 최신 빈티지) 위반 확정(PITQ-C11-20260924 active) + MSM 모수 전 표본 MLE(C1 · PITQ-C1-MSM-20261010 active — 11-06 as-of 전환). BOOK_0001 의 A 는 mandate(08-29 · gross 267m · 구 축) — 계약 경로 등급 · Judge 없음.
- 도훈 결정: PIT-C11-BOOK0001 '시간축 수리 뒤 게이트 이력 재산출 → A 면 Judge 스폰'(09-24 승인 · 미집행) · PIT-C1-MSM-PARAMS 'BOOK_0001 모수 핀 교체 · C11 2단계 재측정과 한 번에 → Judge'(미집행) · KQ150-PRELAUNCH(11-06) 'BOOK_0001 재측정은 하지마'(출범 전 KQ150 소급 투영 건 · 다시 상정하지 않는다).
- 오버레이 카탈로그 40팔(추세 3 · 변동성 목표 3 · 낙폭 2 · 결합 2 · 횡단면 20 등) active · book_spec 1 suspended.
- 프로그램 등록부: P0R01 not_reached · P2R03 falsified 14/14 · P2R04 falsified 8/8 · P3R03 partial · P4 라운드 0 · 열린 결정 5(23일).

## 마감 기록 (11-10)
- 레인 Q(전략강화 재설계) · 레인 O2(시험 목록 분류)는 보고 없이 중단됨(재개 불가 통지). 해당 영역의 결론은 README §2 · §3 · §5-2 — Q 직접 작성.
- 추가 수리(README §5): 시험 2종 운영 상태 의존 제거 · 감시 계열 3종 편입 · 러너 간소화(timings · 파이썬 1회 · 지문 재사용) · suite_totals_watch(같은 날 건너뛰기 · 로그 보존 · 국면 합계 · 밤/주 단계) · 결과 원장(round_core outcomes.R) · 시행 예산(trial_budget.R) · Axiom 처분 스위치.
- 커밋: 5c05969b80 · 72bae6a27 · 3b4651760 · 322d05514 · 98ddbcbf1(v10.2). 결정 상정 3건: LADDER-REFERENCE-ASSEMBLY-20261110 · DSR-GATE-FORM-20261110 · GRADE-V33-NOTCH-ASOF-AND-RULE-CHANGE-PROCEDURE-20261110.

## 마감 기록 2 (11-10 오후 — 도훈 추가 지시 뒤)
- 요구 정정: 'BOOK_0001급 재귀 도출' = 충실구현 레인의 알파 기저로 1계층 강화 프로세스가 스스로 찾게. 기준 사다리 상정 철회(LADDER-REFERENCE-ASSEMBLY-20261110 resolved) · P4-SKELETON-REVIEW-20261018 = B 방향.
- 커밋: 5b42d80f4(등급 v3.4) · e96f334ba(판 표식 · A 자격 상시 보류 · 재채점 도구 · C15) · 98b679826(셀 엔진 방향 · 규칙 문서) · 838f7147a(강화 사슬 · 생성기 판 · 상설 입구).
- 조사 보고 전문(같은 폴더): factor_db_wiring_audit.md(팩터 DB 수리 × v10.2 소비자 · 고칠 곳 13) · l1_reinforce_map.md(강화 프로세스 지도 · 끊긴 고리 13).
- 구현은 작업 레인 1개(강화 사슬)가 했고 Q 가 변경 범위 · 핵심 코드 · 시험 7종을 다시 확인했다. Q 가 고친 것: 상설 판 입구에서 낡은 레인 측정을 '제외'하던 것을 '표식만'으로(판이 통째로 멈추는 과한 차단).
- 운영 기저 풀: 엔진 재료 12 · 자격 0(factor_db_stale 12 · not_qualified 10 · needs_long_leg 9 · audit_not_passed 4 · implementation_suspect 4 · no_engine 2).
- 팩터 DB 총부채 수리: chain_state.json done/ok 11:15:32 · 요약 result 성공 · factor_db_202611.parquet 11:26 · 재계산 프로세스 0(직접 확인).
- 근거 문장 원문 확인(내려받은 PDF 에서 추출): Romano & Wolf 2016 알고리즘 4.1 · 'M = 1000' / Bailey 외 'S = 16' · 'PBO > 0.05' / Politis & White 2004 식 (6).
