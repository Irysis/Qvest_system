# 06_Registry INDEX

> 자동 생성 2026-08-02 00:37 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

## 데이터 (9)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `index_descriptions.json` | 존별 INDEX 큐레이션 DB (본 파일 — 사람 수동 보완, build_artifact_index.R이 소비해 INDEX.md 4개 생성) | active | 2026-07-26 | 45KB |
| `hygiene_report.json` | 일간 파일위생 감사 리포트 (ops/artifact_hygiene_audit.R 산출 — 자동정리 삭제 기록 + artifact-storage.md 위반 감지) | active | 2026-08-01 | 1KB |
| `artifact_index.json` | build_artifact_index.R이 daily_refresh 말미 자동 재생성하는 전체 산출물 기계가독 인덱스 | active | 2026-08-01 | 329KB |
| `book_carrier/` | PG2 book 수익 캐리어(carrier_STR_1715_*) + H1/H1b/H2 오버레이·가중 A/B 실측 결과 저장소 | active | 2026-06-18 | 727KB |
| `idea_registry.json` | 구 S0 아이디어 소싱 레지스트리 — telegram_notify.R이 아직 참조하나 갱신은 06-08 정지 | legacy | 2026-06-07 | 40KB |
| `live_track/STR_1715_on_M4_R05_noLayer4_PG2/` | 현행 PG2 book(noLayer4) 라이브 페이퍼트래킹 — daily_nav/paper_nav/holdout_interval, TaskScheduler 월간 소비 | active | 2026-08-01 | 156KB |
| `live_track/STR_1715_FaithTrend_on_M4_R05_overlay_PG2/` | 제거된 구 FaithTrend 오버레이 라이브트랙 — look-ahead 판명 후 rollback 보존분(도훈 지시) | legacy | 2026-07-13 | 5KB |
| `strategy_grades.json` | 전략 등급 레지스트리 — 검색 인덱스와 v8 readiness gate가 소비 (06-08 이후 정지 상태이나 게이트 의존) | active | 2026-06-07 | 79KB |
| `alpha_frontier_queue.json` | 상설 알파 프론티어 큐 SOT — '다음에 뭘 시도할지' EV순 (발굴 착수 전 확인·owner 표기 의무, dohoon_decision 항목 임의 착수 금지. v8.3 §4) | active | 2026-07-26 | 195KB |

## 계약 (5)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `factor_rotation_registry.json` | factor-rotation 모드 FR_XXXX 등록 레지스트리(현행 v6146B, 06-13 갱신) | active | 2026-06-13 | 6KB |
| `live_track/STR_1715_AR_on_M4_R05_overlay_PG2/` | holdout falsification 1호 등록(구간 [0.39,3.16]) 라이브트랙 — measurement-graduation §3 규약상 불변 봉인 | active | 2026-07-13 | 2KB |
| `module_catalog.json` | register_module 공용계약의 모듈 카탈로그(SOT) — 계약 floor 통과 모듈 표준 등록부, 07-03 갱신 | active | 2026-07-08 | 511KB |
| `module_quarantine.json` | register_module 계약 미충족 산출물 격리 보존소(v8.1 헌법이 보존 명시) | active | 2026-07-27 | 38KB |
| `overlay_candidate_queue.json` | screen_route=OVERLAY_CANDIDATE 라우팅 큐(게이트 2계층 소비 경로) — 07-03 갱신 | active | 2026-07-10 | 23KB |

## 훅 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hook_skip_audit.log` | backtest_contract_audit.sh가 hook skip 사유를 append하는 현행 감사 로그 | active | 2026-07-03 | 119B |

## 모드-alpha-search (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hypothesis_index.json` | alpha-search 가설/검증 이력 인덱스(중복 가설 방지용) — 07-04 갱신 중 | active | 2026-08-01 | 672KB |
| `paper_registry.json` | 논문 리서치 파이프라인 레지스트리(수집→라우터→alpha-search 큐) — 07-03 갱신 | active | 2026-07-27 | 276KB |

## 모드-FR (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `module_performance.json` | FR input-floor용 모듈 국면조건부 성과 매트릭스 — build_module_performance.R 산출, regime admission 소비 | active | 2026-07-03 | 281KB |
| `module_regime_admission.json` | RCMA(국면조건부 모듈 admission) 판정 결과 레지스트리 — FR 모드 소비 | active | 2026-06-12 | 393KB |
| `overlay_ab_results/` | 오버레이 후보(LH loser-harvest 등) A/B 실측 결과 — 07-03 스마트베타 LH 후속 소비 예정 | active | 2026-07-10 | 174KB |

## 보고서 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `quant_profile.md` | 도훈 퀀트 전략 선호 프로필 문서(팩터 구현 선호 우선순위) — 코드 소비 없음, 06-08 이후 정지 | report | 2026-06-07 | 4KB |

## 모드-RAMP (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ramp/` | RAMP 모드 레지스트리 존 — approved_factor_library.parquet(102 승인팩터)·CCS 13-score·Gate3/5 summary·ramp_registry·roadmap_status (07-04 갱신 중) | active | 2026-07-03 | 116KB |

## 레지스트리 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `strategy_registry.json` | 전략 레지스트리 — ★2세대 스키마 공존(2026-07-25 확인). 신세대 239건 = alpha_search register_strategy 산출(role/grade/score/committed_via, dir 필드 없음 = 설계). 구세대 150건 = v55 계보(id/name/dir/hurdle_*), dir 중 디스크 실재 2건뿐 — dir 신뢰 불가. 디스크 전략 디렉토리 429개를 담는 인덱스가 아니므로 '미등재'는 결손이 아님. 디렉토리 식별은 이 파일이 아니라 디렉토리명 전체로 할 것 | active | 2026-07-08 | 275KB |
| `*.bak (큐 백업본)` | 큐 파일 편집 전 백업본(alpha_frontier_queue·overlay_candidate_queue) — 원본이 정본 | archive | 2026-07-14 | 120KB |

## 지식-Axiom엔진 (9)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `{knowledge_index.json, knowledge_index.md}` | 지식 순차 인덱스(Law/Distilled/L-code 1..N 뷰) — weekly_cleaner_sweep [3.6] build_knowledge_index가 주간 재생성 | active | 2026-08-01 | 249KB |
| `distilled_knowledge.json` | Distilled 탐색지도 카드 SOT(DIST-*) — negative 지식의 재도전 대상 보관(INV-7) | active | 2026-07-27 | 243KB |
| `knowledge_recheck_queue.json` | 지식 재검 큐 — 부활신호/재도전 후보 대기열 | active | 2026-07-18 | 8KB |
| `revival_signals.json` | 부활신호 정의·발화 상태(INV-7) — settled-negative를 시스템이 먼저 un-bury하는 트리거 | active | 2026-07-18 | 7KB |
| `lcode_family_override.json` | L-code family 수동 오버라이드 — 하버스터 word-boundary 추론 보정(07-18 substring FP 수리 동반) | active | 2026-07-18 | 52KB |
| `research_ev_map.json` | 리서치 EV 지도 — 라운드 선택 우선순위 입력 | active | 2026-07-10 | 9KB |
| `layer_bottleneck_map.md` | 계층 병목 지도(상시 실측) — 목표 갭이 어느 계층에 막혀 있나. answer-principles 연속성 5호 의무 갱신 대상 | active | 2026-07-27 | 53KB |
| `{distill_manifest_*.json, lcode_distill_*.json, cleanup_manifest_*.json, cache_cleanup_manifest_*.json, axiom_recert_queue_*.json} (날짜 스탬프 증류/정리 매니페스트)` | 주간 cleaner·증류 사이클이 실행마다 남기는 날짜 스탬프 매니페스트(감사 추적용, 1회성 기록) | archive | 2026-07-18 | 1.8MB |
| `lcode_id_collision_review_20260725.md` | L-code ID 충돌 5건 판정표 + 해소 기록(재발급 3·병합 2·초안이관 1). 갈래 분류 규칙과 소비면 인용 실측 근거 | active | 2026-07-25 | 11KB |

## 하네스-Continuity (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `{continuity_cases.json, firewall_cases.json}` | Continuity Firewall 자가발전 케이스 저장소 — continuity_gate.py --append-case 소비(우회어 학습) | active | 2026-07-18 | 40KB |

## 문서 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `README.md` | 레지스트리 존 진입 설명 | active | 2026-07-03 | 1KB |
| `handbook_facts.json` | 핸드북 사실 집합 — 세션 간 참조되는 확정 수치/규약 스냅샷 | active | 2026-08-01 | 1KB |

## AST-v1.1 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ast_field_map_v0.json` | AST 계층 v1.1 field_dictionary 정본 — 전 데이터 58그룹 실측 리프 맵(FIELD 22·PTR 11·STORED 15·LLM 2·EXT 5). SOT: docs/qvest_ast_v1_1_sot.md | active | 2026-07-25 | 136KB |

## 하네스-감시 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `stranded_repairs.json` | worktree 미커밋 수리 감사 산출 — stranded_repairs_audit.sh(무인 12/20시)가 파일 triage·충돌탐지·prune 후보 기록 | active | 2026-08-01 | 6KB |

## 미분류 (4) — index_descriptions.json에 추가하세요

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ast_operator_backlog.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-25 | 1KB |
| `ast_structure_log.jsonl` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-01 | 128KB |
| `scheduler_task_health.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-01 | 5KB |
| `suite_totals_baseline.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-26 | 371B |

## stale 큐레이션 키 (4) — 디스크 부재, index_descriptions.json에서 제거 권장

- `briefing_config.json`
- `factor_rotation_registry.json.pre_c2ab_backup`
- `module_performance.FULL_B.json`
- `strategy_registry.json.backup_phaseE_20260425_220537`

