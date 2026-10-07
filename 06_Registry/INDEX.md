# 06_Registry INDEX

> 자동 생성 2026-10-07 00:41 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

## 데이터 (12)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `index_descriptions.json` | 존별 INDEX 큐레이션 DB (본 파일 — 사람 수동 보완, build_artifact_index.R이 소비해 INDEX.md 4개 생성) | active | 2026-09-05 | 46KB |
| `hygiene_report.json` | 일간 파일위생 감사 리포트 (ops/artifact_hygiene_audit.R 산출 — 자동정리 삭제 기록 + artifact-storage.md 위반 감지) | active | 2026-10-06 | 12KB |
| `artifact_index.json` | build_artifact_index.R이 daily_refresh 말미 자동 재생성하는 전체 산출물 기계가독 인덱스 | active | 2026-10-05 | 442KB |
| `book_carrier/` | PG2 book 수익 캐리어(carrier_STR_1715_*) + H1/H1b/H2 오버레이·가중 A/B 실측 결과 저장소 | active | 2026-08-29 | 912KB |
| `idea_registry.json` | 구 S0 아이디어 소싱 레지스트리 — telegram_notify.R이 아직 참조하나 갱신은 06-08 정지 | legacy | 2026-06-07 | 40KB |
| `live_track/STR_1715_on_M4_R05_noLayer4_PG2/` | 현행 PG2 book(noLayer4) 라이브 페이퍼트래킹 — daily_nav/paper_nav/holdout_interval, TaskScheduler 월간 소비 | active | 2026-08-01 | 156KB |
| `live_track/STR_1715_FaithTrend_on_M4_R05_overlay_PG2/` | 제거된 구 FaithTrend 오버레이 라이브트랙 — look-ahead 판명 후 rollback 보존분(도훈 지시) | legacy | 2026-07-13 | 5KB |
| `strategy_grades.json` | 전략 등급 레지스트리 — 검색 인덱스와 v8 readiness gate가 소비 (06-08 이후 정지 상태이나 게이트 의존) | active | 2026-06-07 | 79KB |
| `alpha_frontier_queue.json` | 상설 알파 프론티어 큐 SOT — '다음에 뭘 시도할지' EV순 (발굴 착수 전 확인·owner 표기 의무, dohoon_decision 항목 임의 착수 금지. v8.3 §4) | active | 2026-09-23 | 430KB |
| `wiring_map.json` | 표준↔소비자 배선 지도 (ops/wiring_map_build.R 산출 — contracts/validation 헬퍼 + 권위 판정 원장의 실코드 소비자 수. status: orphan/thin/wired. ★판정은 이 원장이 권위 — 소비자는 n_consumers 로 재판정 금지) | active | 2026-10-05 | 94KB |
| `wiring_map_baseline.json` | 배선 지도 래칫 기준선 — 소비자 수 감소(표준 우회 시작)만 드리프트로 경고. 자동 갱신 금지(자동이면 악화가 매일 흡수돼 래칫이 무력화) | active | 2026-08-08 | 6KB |
| `cleaner_protected_paths.json` | 무인 증류 레인(cleaner_distill_run.sh)의 삭제 집행 경계 정본 — 절대보존 목록 + ref_check_ignore(기록 vs 소비) + 집행 상한(건수·용량·mtime). 2026-09-05 도훈 '삭제 전면 무인' 지시로 신설. 코드가 아니라 레지스트리에 둔 이유 = 하드코딩 금지 + 도훈이 코드를 안 열고 경계를 조정 | active | 2026-09-05 | 7KB |

## 계약 (5)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `factor_rotation_registry.json` | factor-rotation 모드 FR_XXXX 등록 레지스트리(현행 v6146B, 06-13 갱신) | active | 2026-09-23 | 26KB |
| `live_track/STR_1715_AR_on_M4_R05_overlay_PG2/` | holdout falsification 1호 등록(구간 [0.39,3.16]) 라이브트랙 — measurement-graduation §3 규약상 불변 봉인 | active | 2026-07-13 | 2KB |
| `module_catalog.json` | register_module 공용계약의 모듈 카탈로그(SOT) — 계약 floor 통과 모듈 표준 등록부, 07-03 갱신 | active | 2026-10-06 | 2.5MB |
| `module_quarantine.json` | register_module 계약 미충족 산출물 격리 보존소(v8.1 헌법이 보존 명시) | active | 2026-09-15 | 170KB |
| `overlay_candidate_queue.json` | screen_route=OVERLAY_CANDIDATE 라우팅 큐(게이트 2계층 소비 경로) — 07-03 갱신 | active | 2026-08-23 | 242KB |

## 훅 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hook_skip_audit.log` | backtest_contract_audit.sh가 hook skip 사유를 append하는 현행 감사 로그 | active | 2026-07-03 | 119B |

## 모드-alpha-search (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hypothesis_index.json` | alpha-search 가설/검증 이력 인덱스(중복 가설 방지용) — 07-04 갱신 중 | active | 2026-10-06 | 1.8MB |
| `paper_registry.json` | 논문 리서치 파이프라인 레지스트리(수집→라우터→alpha-search 큐) — 07-03 갱신 | active | 2026-10-03 | 614KB |

## 모드-FR (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `module_performance.json` | FR input-floor용 모듈 국면조건부 성과 매트릭스 — build_module_performance.R 산출, regime admission 소비 | active | 2026-10-05 | 1.2MB |
| `module_regime_admission.json` | RCMA(국면조건부 모듈 admission) 판정 결과 레지스트리 — FR 모드 소비 | active | 2026-06-12 | 393KB |
| `overlay_ab_results/` | 오버레이 후보(LH loser-harvest 등) A/B 실측 결과 — 07-03 스마트베타 LH 후속 소비 예정 | active | 2026-08-17 | 370KB |

## 보고서 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `quant_profile.md` | 도훈 퀀트 전략 선호 프로필 문서(팩터 구현 선호 우선순위) — 코드 소비 없음, 06-08 이후 정지 | report | 2026-06-07 | 4KB |

## 모드-RAMP (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ramp/` | RAMP 모드 레지스트리 존 — approved_factor_library.parquet(102 승인팩터)·CCS 13-score·Gate3/5 summary·ramp_registry·roadmap_status (07-04 갱신 중) | active | 2026-08-22 | 126KB |

## 레지스트리 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `strategy_registry.json` | 전략 레지스트리 — ★2세대 스키마 공존(2026-07-25 확인). 신세대 239건 = alpha_search register_strategy 산출(role/grade/score/committed_via, dir 필드 없음 = 설계). 구세대 150건 = v55 계보(id/name/dir/hurdle_*), dir 중 디스크 실재 2건뿐 — dir 신뢰 불가. 디스크 전략 디렉토리 429개를 담는 인덱스가 아니므로 '미등재'는 결손이 아님. 디렉토리 식별은 이 파일이 아니라 디렉토리명 전체로 할 것 | active | 2026-08-23 | 277KB |
| `*.bak (큐 백업본)` | 큐 파일 편집 전 백업본(alpha_frontier_queue·overlay_candidate_queue) — 원본이 정본 | archive | 2026-08-20 | 466KB |

## 지식-Axiom엔진 (8)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `{knowledge_index.json, knowledge_index.md}` | 지식 순차 인덱스(Law/Distilled/L-code 1..N 뷰) — weekly_cleaner_sweep [3.6] build_knowledge_index가 주간 재생성 | active | 2026-10-06 | 1.2MB |
| `distilled_knowledge.json` | Distilled 탐색지도 카드 SOT(DIST-*) — negative 지식의 재도전 대상 보관(INV-7) | active | 2026-10-06 | 4.5MB |
| `knowledge_recheck_queue.json` | 지식 재검 큐 — 부활신호/재도전 후보 대기열 | active | 2026-07-18 | 8KB |
| `revival_signals.json` | 부활신호 정의·발화 상태(INV-7) — settled-negative를 시스템이 먼저 un-bury하는 트리거 | active | 2026-10-03 | 10KB |
| `lcode_family_override.json` | L-code family 수동 오버라이드 — 하버스터 word-boundary 추론 보정(07-18 substring FP 수리 동반) | active | 2026-07-18 | 52KB |
| `layer_bottleneck_map.md` | 계층 병목 지도(상시 실측) — 목표 갭이 어느 계층에 막혀 있나. answer-principles 연속성 5호 의무 갱신 대상 | active | 2026-09-24 | 882B |
| `{distill_manifest_*.json, lcode_distill_*.json, cleanup_manifest_*.json, cache_cleanup_manifest_*.json, axiom_recert_queue_*.json} (날짜 스탬프 증류/정리 매니페스트)` | 주간 cleaner·증류 사이클이 실행마다 남기는 날짜 스탬프 매니페스트(감사 추적용, 1회성 기록) | archive | 2026-10-03 | 1.8MB |
| `lcode_id_collision_review_20260725.md` | L-code ID 충돌 5건 판정표 + 해소 기록(재발급 3·병합 2·초안이관 1). 갈래 분류 규칙과 소비면 인용 실측 근거 | active | 2026-07-25 | 11KB |

## 하네스-Continuity (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `{continuity_cases.json, firewall_cases.json}` | Continuity Firewall 자가발전 케이스 저장소 — continuity_gate.py --append-case 소비(우회어 학습) | active | 2026-08-16 | 41KB |

## 문서 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `README.md` | 레지스트리 존 진입 설명 | active | 2026-07-03 | 1KB |
| `handbook_facts.json` | 핸드북 사실 집합 — 세션 간 참조되는 확정 수치/규약 스냅샷 | active | 2026-10-06 | 1KB |

## AST-v1.1 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ast_field_map_v0.json` | AST 계층 v1.1 field_dictionary 정본 — 전 데이터 58그룹 실측 리프 맵(FIELD 22·PTR 11·STORED 15·LLM 2·EXT 5). SOT: docs/qvest_ast_v1_1_sot.md | active | 2026-09-24 | 153KB |

## 하네스-감시 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `stranded_repairs.json` | worktree 미커밋 수리 감사 산출 — stranded_repairs_audit.sh(무인 12/20시)가 파일 triage·충돌탐지·prune 후보 기록 | active | 2026-10-06 | 21KB |

## 미분류 (137) — index_descriptions.json에 추가하세요

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `_archive` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 594KB |
| `a_eligibility_gate.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-03 | 9KB |
| `adapter_axis_backfill_20260813.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-13 | 26KB |
| `adapter_feasibility_20260813.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-13 | 10KB |
| `adapter_registration_queue.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-13 | 35KB |
| `alpha_frontier_queue.json.bak_156b1b_181929` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 411KB |
| `alpha_frontier_queue.json.bak_165_134106` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 477KB |
| `alpha_frontier_queue.json.bak_176_144613` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 502KB |
| `alpha_frontier_queue.json.bak_20260802` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-01 | 225KB |
| `alpha_frontier_queue.json.bak_advcorr_131232` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 459KB |
| `alpha_frontier_queue.json.bak_armc_20260820` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-20 | 807KB |
| `alpha_frontier_queue.json.bak_armc_close` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-20 | 811KB |
| `alpha_frontier_queue.json.bak_c14_234548` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 429KB |
| `alpha_frontier_queue.json.bak_claim_130434` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 456KB |
| `alpha_frontier_queue.json.bak_depth_20260809` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 517KB |
| `alpha_frontier_queue.json.bak_fq093_20260808_115701` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 389KB |
| `alpha_frontier_queue.json.bak_fq094_20260808_120249` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 390KB |
| `alpha_frontier_queue.json.bak_fq099_20260808_210650` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 415KB |
| `alpha_frontier_queue.json.bak_fq123_220735` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 419KB |
| `alpha_frontier_queue.json.bak_fq130_20260808_120746` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 392KB |
| `alpha_frontier_queue.json.bak_fq138prereg_182636` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 412KB |
| `alpha_frontier_queue.json.bak_fq141_precheck_20260808_152736` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 393KB |
| `alpha_frontier_queue.json.bak_fq156_final_163628` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 405KB |
| `alpha_frontier_queue.json.bak_fq156_precheck_162001` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 400KB |
| `alpha_frontier_queue.json.bak_fq157_162521` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 402KB |
| `alpha_frontier_queue.json.bak_fq157c_164046` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 405KB |
| `alpha_frontier_queue.json.bak_fq160_164424` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 408KB |
| `alpha_frontier_queue.json.bak_fq161pow_235115` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 432KB |
| `alpha_frontier_queue.json.bak_fq164_130020` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 449KB |
| `alpha_frontier_queue.json.bak_fq235_20260821` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-20 | 811KB |
| `alpha_frontier_queue.json.bak_ic_133517` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 467KB |
| `alpha_frontier_queue.json.bak_ks_132102` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 474KB |
| `alpha_frontier_queue.json.bak_npa_20260808_154216` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 395KB |
| `alpha_frontier_queue.json.bak_q3_20260808_113105` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 387KB |
| `alpha_frontier_queue.json.bak_scopefix_215730` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 418KB |
| `alpha_frontier_queue.json.bak_vf_133905` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 482KB |
| `alpha_frontier_queue.json.bak_wt001_233505` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 437KB |
| `alpha_frontier_queue.json.bak_wt001_close` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-21 | 829KB |
| `alpha_frontier_queue.json.bak_wt002_close` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-21 | 829KB |
| `alpha_frontier_queue.json.bak_wt008` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-03 | 336KB |
| `ast_gate_alerts.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 2KB |
| `ast_leaf_table_bugs.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-02 | 22KB |
| `ast_operator_backlog.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-02 | 3KB |
| `ast_structure_log.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 6.6MB |
| `auto_spawn_config.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-16 | 208B |
| `auto_spawn_log.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 12KB |
| `auto_spawn_queue.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 27KB |
| `basis_break_registry.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-07 | 1.6MB |
| `benchmark_parity_history.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-05 | 3KB |
| `book` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-24 | 4KB |
| `bt_result_format_census_20260822.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 13KB |
| `cache_only_ledgers_snapshot_20260809_README.md` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 3KB |
| `combination_candidates.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-05 | 359KB |
| `continuity_blocks_snapshot_20260809.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 31KB |
| `data_pipeline_queue.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-17 | 19KB |
| `decision_dossier_lottery_filter_20260802.md` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-02 | 11KB |
| `decision_register.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-04 | 149KB |
| `defensive_score.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 2KB |
| `distribution_target_queue.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 2KB |
| `essence_regrade_20260824.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-24 | 250KB |
| `factor_evidence.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-05 | 171KB |
| `factor_panel_axis.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-03 | 96KB |
| `failure_revival_history_snapshot_20260809.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 50KB |
| `fred_availability_rules.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-24 | 82KB |
| `hygiene_manifest_snapshot_20260809.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 186KB |
| `improvement_potential.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 64KB |
| `infra_backlog.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 160KB |
| `l2_unit_request.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-23 | 1KB |
| `lean_carrier` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 117KB |
| `m4_published` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 1.6MB |
| `memory_inbox` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-25 | 4KB |
| `method_registry.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-29 | 74KB |
| `mfro_consolidated_verdict_20260822.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 285B |
| `mfro_index_turnover_audit_20260822.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 1KB |
| `mfro_rotation_signal_ic_by_year_20260822.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 1KB |
| `mfro_rotation_signal_ic_trajectory_20260822.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 6KB |
| `module_catalog.json.bak_20260907_103159` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-07 | 619KB |
| `module_catalog.json.bak_benchseam_20260809_145008` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 537KB |
| `module_catalog.json.bak_dup_audit_20260820_205802` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-20 | 539KB |
| `module_catalog.json.bak_pyfix_20260809_145310` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-09 | 537KB |
| `module_catalog.json.bak_skippedbase_20260907_110525` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-07 | 843KB |
| `module_performance.json.bak_20260808_pre_fq056` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-08 | 281KB |
| `next_session_task.md` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-07 | 37KB |
| `no_signal_queue_audit_r46_20260822.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 5KB |
| `no_signal_queue_audit_r46_clusters_20260822.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 659B |
| `no_signal_recheck_census_20260822.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-22 | 785B |
| `organic` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-03 | 3KB |
| `overlay_arm_ledger.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-05 | 14KB |
| `overlay_base_q1_share_20260810.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 4KB |
| `overlay_catalog.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-05 | 70KB |
| `overlay_mechanism_map.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-24 | 3KB |
| `overlay_probe_allowlist.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-26 | 8KB |
| `overlay_probe_future.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-24 | 3KB |
| `paper_feasibility_20260813.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-13 | 18KB |
| `pit_c11_consumer_notices.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-24 | 14KB |
| `pit_jm_c1_consumer_notices.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-25 | 8KB |
| `pit_quarantine.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-24 | 36KB |
| `prereg` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-04 | 929KB |
| `rawdata_source_priority.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-23 | 10KB |
| `regime_published` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 32.0MB |
| `reimplement_queue.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-07 | 10KB |
| `reinforce_auto_config.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 75KB |
| `reinforce_ladder_config.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-24 | 5KB |
| `reinforce_ladder_ledger.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-24 | 61KB |
| `reinforce_ledger_l1.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 11.0MB |
| `reinforce_ledger_l1.json.bak_20260904_174834` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 756KB |
| `reinforce_ledger_l1.json.bak_b2reset_211311` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 869KB |
| `reinforce_ledger_l1.json.bak_b5reset_192513` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 801KB |
| `reinforce_ledger_l1.json.bak_b5reset_192528` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 801KB |
| `reinforce_ledger_l1.json.bak_dupfill_202510` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 831KB |
| `reinforce_ledger_l2.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-23 | 8KB |
| `reinforce_program.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-03 | 56KB |
| `replication_clean_lane.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-03 | 9KB |
| `replication_request.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-05 | 1KB |
| `replication_skiplist.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-07 | 4KB |
| `retro_rolling_defensive_report.csv` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 54KB |
| `rf_arm_compat.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 24KB |
| `rf_decisions.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 20KB |
| `rf_diversification_gate.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 5KB |
| `rf_fidelity_axes.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-23 | 6KB |
| `rf_overlay_adversary_axes.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-23 | 8KB |
| `rf_preaudit.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-05 | 14KB |
| `rf_trial_log.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 34KB |
| `rolling_grade.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-04 | 2KB |
| `round_closures_snapshot_20260809.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 1.3MB |
| `round_closures_snapshot_20260809_index.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 100KB |
| `round_closures_snapshot_20260809_README.md` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-12 | 974B |
| `rule_axis_map_seed_20260813.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-13 | 135KB |
| `scheduler_task_health.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 7KB |
| `standalone_track_dispositions.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-20 | 31KB |
| `standalone_track_queue.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 5KB |
| `strategy_role.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 3KB |
| `strategy_roles.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-06 | 2.5MB |
| `suite_totals_baseline.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-03 | 399B |
| `vintage_cascade_20260923.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-23 | 1.5MB |
| `weight_catalog.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-05 | 50KB |
| `weight_variant_ledger.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-23 | 5KB |

## stale 큐레이션 키 (5) — 디스크 부재, index_descriptions.json에서 제거 권장

- `briefing_config.json`
- `factor_rotation_registry.json.pre_c2ab_backup`
- `module_performance.FULL_B.json`
- `strategy_registry.json.backup_phaseE_20260425_220537`
- `research_ev_map.json`

