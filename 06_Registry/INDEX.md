# 06_Registry INDEX

> 자동 생성 2026-07-16 01:42 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

## 데이터 (10)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `index_descriptions.json` | 존별 INDEX 큐레이션 DB (본 파일 — 사람 수동 보완, build_artifact_index.R이 소비해 INDEX.md 4개 생성) | active | 2026-07-09 | 39KB |
| `hygiene_report.json` | 일간 파일위생 감사 리포트 (ops/artifact_hygiene_audit.R 산출 — 자동정리 삭제 기록 + artifact-storage.md 위반 감지) | active | 2026-07-15 | 4KB |
| `artifact_index.json` | build_artifact_index.R이 daily_refresh 말미 자동 재생성하는 전체 산출물 기계가독 인덱스 | active | 2026-07-14 | 311KB |
| `book_carrier/` | PG2 book 수익 캐리어(carrier_STR_1715_*) + H1/H1b/H2 오버레이·가중 A/B 실측 결과 저장소 | active | 2026-06-18 | 727KB |
| `idea_registry.json` | 구 S0 아이디어 소싱 레지스트리 — telegram_notify.R이 아직 참조하나 갱신은 06-08 정지 | legacy | 2026-06-07 | 40KB |
| `live_track/STR_1715_on_M4_R05_noLayer4_PG2/` | 현행 PG2 book(noLayer4) 라이브 페이퍼트래킹 — daily_nav/paper_nav/holdout_interval, TaskScheduler 월간 소비 | active | 2026-07-14 | 155KB |
| `live_track/STR_1715_FaithTrend_on_M4_R05_overlay_PG2/` | 제거된 구 FaithTrend 오버레이 라이브트랙 — look-ahead 판명 후 rollback 보존분(도훈 지시) | legacy | 2026-07-13 | 5KB |
| `strategy_grades.json` | 전략 등급 레지스트리 — 검색 인덱스와 v8 readiness gate가 소비 (06-08 이후 정지 상태이나 게이트 의존) | active | 2026-06-07 | 79KB |
| `strategy_registry.json` | 전략 마스터 레지스트리(178+ STR 메타) — telegram·strategy_registry.R 소비, 06-21 갱신 | active | 2026-07-08 | 275KB |
| `alpha_frontier_queue.json` | 상설 알파 프론티어 큐 SOT — '다음에 뭘 시도할지' EV순 (발굴 착수 전 확인·owner 표기 의무, dohoon_decision 항목 임의 착수 금지. v8.3 §4) | active | 2026-07-14 | 142KB |

## 계약 (5)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `factor_rotation_registry.json` | factor-rotation 모드 FR_XXXX 등록 레지스트리(현행 v6146B, 06-13 갱신) | active | 2026-06-13 | 6KB |
| `live_track/STR_1715_AR_on_M4_R05_overlay_PG2/` | holdout falsification 1호 등록(구간 [0.39,3.16]) 라이브트랙 — measurement-graduation §3 규약상 불변 봉인 | active | 2026-07-13 | 2KB |
| `module_catalog.json` | register_module 공용계약의 모듈 카탈로그(SOT) — 계약 floor 통과 모듈 표준 등록부, 07-03 갱신 | active | 2026-07-08 | 511KB |
| `module_quarantine.json` | register_module 계약 미충족 산출물 격리 보존소(v8.1 헌법이 보존 명시) | active | 2026-07-08 | 28KB |
| `overlay_candidate_queue.json` | screen_route=OVERLAY_CANDIDATE 라우팅 큐(게이트 2계층 소비 경로) — 07-03 갱신 | active | 2026-07-10 | 23KB |

## 훅 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hook_skip_audit.log` | backtest_contract_audit.sh가 hook skip 사유를 append하는 현행 감사 로그 | active | 2026-07-03 | 119B |

## 모드-alpha-search (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hypothesis_index.json` | alpha-search 가설/검증 이력 인덱스(중복 가설 방지용) — 07-04 갱신 중 | active | 2026-07-13 | 566KB |
| `paper_registry.json` | 논문 리서치 파이프라인 레지스트리(수집→라우터→alpha-search 큐) — 07-03 갱신 | active | 2026-07-14 | 260KB |

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

## 미분류 (20) — index_descriptions.json에 추가하세요

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `alpha_frontier_queue.json.bak` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-14 | 97KB |
| `axiom_recert_queue_20260704.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 7KB |
| `cache_cleanup_manifest_20260704.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 16KB |
| `cleanup_manifest_20260704.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-03 | 7KB |
| `continuity_cases.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-14 | 17KB |
| `distill_manifest_20260704.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 7KB |
| `distill_manifest_20260711.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-11 | 812B |
| `distilled_knowledge.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-11 | 151KB |
| `firewall_cases.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 16KB |
| `knowledge_index.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-11 | 84KB |
| `knowledge_index.md` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-11 | 52KB |
| `knowledge_recheck_queue.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 7KB |
| `layer_bottleneck_map.md` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-14 | 30KB |
| `lcode_distill_execution_20260704.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 1.0MB |
| `lcode_distill_manifest_20260704.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 8KB |
| `lcode_distill_plan_20260704.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 726KB |
| `overlay_candidate_queue.json.bak` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-10 | 23KB |
| `README.md` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-03 | 1KB |
| `research_ev_map.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-10 | 9KB |
| `revival_signals.json` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-07-04 | 6KB |

## stale 큐레이션 키 (4) — 디스크 부재, index_descriptions.json에서 제거 권장

- `briefing_config.json`
- `factor_rotation_registry.json.pre_c2ab_backup`
- `module_performance.FULL_B.json`
- `strategy_registry.json.backup_phaseE_20260425_220537`

