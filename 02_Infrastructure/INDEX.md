# 02_Infrastructure INDEX

> 자동 생성 2026-09-24 00:34 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

## 데이터 (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `F1. QT_to_xts.r` | 퀀티와이즈 엑셀 시계열을 xts로 변환하는 헬퍼 함수 2종(QT_to_xts / QT_to_xts_macro) — 데이터 인제스트 빌더들의 공용 유틸 | active | 2026-06-07 | 643B |
| `data/` | 데이터 인제스트/캐시 계층 42건 — build_cache.R·build_index_cache.py·daily_refresh.sh·퀀티와이즈 파서(RAWDATA/benchmark parquet 생산) | active | 2026-09-23 | 10.8MB |
| `factor_db/` | Factor DB 계층 43건 — 월간 373팩터 + 일간 팩터 빌더·load_month_factors(C15 유일 진입점)·registry | active | 2026-09-23 | 2.3MB |

## 백테스트 (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `backtest_harness.R` | 공용 백테스트 하네스(시뮬레이션 엔진 62KB) — alpha_search 드라이버·contracts·data 빌더가 공통 source하는 실행 코어 | active | 2026-08-23 | 72KB |
| `factor_portfolios.R` | KR FF3/FF5/Carhart-4F 팩터 회귀(NW HAC alpha t) — strategy_analyzer의 Multi-Factor Regression 공급자(2026-06-04 재작성) | active | 2026-06-07 | 6KB |
| `strategy_analyzer.R` | 전략 진단 분석기 — 백테 후 IC/rolling/stress/sector/holdings CSV + analysis_report.md 생성(FF 회귀 포함) | active | 2026-08-02 | 38KB |

## 설정 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `config.R` | 전역 경로·상수 SOT(CACHE_DIR/QM_ROOT/LIQ_THRESHOLD 등) — 사실상 모든 R 스크립트의 진입 설정 | active | 2026-07-25 | 12KB |
| `config/` | 데이터 소스 설정 2건 — book_carrier_sources.json(북 캐리어 추출) + paper_recharge_sources.csv(논문 수집 소스) | active | 2026-08-29 | 13KB |

## 모드-QEPM(구 S0-S7) (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `factor_research_pipeline.R` | 구 S0-S7 프로세스 핵심 계산(S3 직교성/spanning, S4 ΔSharpe/IC_marginal, S7 lifecycle) — v55 리서치 파이프라인 코어 | legacy | 2026-06-07 | 17KB |
| `stage_gate_engine.R` | 구 S0~S7+PG0~PG3 스테이지 상태머신(sg_transition/sg_dashboard) — v55 stage gate 코어이나 현행 스크립트가 아직 배선 | legacy | 2026-07-24 | 60KB |
| `pipeline/` | v55_stage_gate_extensions.R 단일 — v55 stage gate 확장(구 S0-S7 판정 보조). 격리 대상이나 judge 프롬프트가 아직 참조 | legacy | 2026-06-07 | 9KB |

## 게이트 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hurdle_gate.R` | Screening tier 게이트 권위 구현(83KB — D002 turnover 1100%·D004 structural drawdown·verdict$screening·screen_route 라우팅) | active | 2026-08-23 | 102KB |

## 성능 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hurdle_gate_perf.cpp` | hurdle_gate·strategy_analyzer 병목 루프 Rcpp 가속(rolling_sharpe/rolling_mdd/stress_periods, O(N)) | active | 2026-06-07 | 8KB |
| `cpp/` | Rcpp 핫스팟 가속 모듈 — roll_beta_cpp(일간 팩터 DB 베타)·bootstrap_cpp + 로더 rcpp_hotspots.R | active | 2026-06-07 | 21KB |

## 레지스트리 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `strategy_registry.R` | 전략 fingerprint(중복탐지 해시)·팩터 라벨 taxonomy·lifecycle 상태 레지스트리(Lawbook Ch.17/19/21) | active | 2026-06-07 | 8KB |

## 훅 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `R/` | hook_batch_runner.R 단일 파일 — 훅 R 로직을 세션 1회 source로 통합하는 배치 래퍼(Block C 토큰/spawn 최적화) | active | 2026-08-02 | 14KB |
| `hooks/` | 하네스 강제 계층 64건 — qvest_hook_router.py + 47 훅(axiom_enforcement·graduation gate·backtest audit) + _archive_v55/_archive_4_6 격리분 | active | 2026-09-23 | 665KB |

## 모드-alpha-search (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `alpha_search/` | ② alpha-search 모드 실행 계층(91건) — run_alpha_search.R + 논문 복제 드라이버(run_qmj_paper·run_residmom_paper 등)·캐시 빌더·검증 스크립트 | active | 2026-09-23 | 956KB |

## 보고 (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `attribution/` | research_philosophy ⑦ Attribution 모듈 — Brinson 분해 + Carhart 4팩터 귀속(분기 트리거) | active | 2026-06-07 | 16KB |
| `report_templates/` | report_base.Rmd + report_style.css — LLM 보고 생성기 렌더링 소재 (구 KR/EN 템플릿 2건 2026-07-04 스윕 삭제) | active | 2026-06-07 | 29KB |
| `reports/` | 보고 생성기 4건 — mrs_dashboard.R(모니터링 대시보드)·report_agent_llm.R·report_charts·report_narrative | active | 2026-08-02 | 241KB |

## 공리엔진 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `axiom/` | Axiom 자가발전 엔진 구현 — L-code emit/schema/harvester·promote(mode-local→global)·rollback·weekly report·inject | active | 2026-09-23 | 779KB |

## 계약 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `contracts/` | 측정·계약 코어 16건 — build_bt_result/canonical_screen_bt/essence_score(Grade 권위)/register_module/holdout_falsification 등 실측-only 거버넌스의 구현체 | active | 2026-09-07 | 521KB |
| `schemas/` | JSON 스키마 계층 — certs/(5 certificate)·packages/(6 agent package)·state/(book_state·axiom 등) 스키마 정의 | active | 2026-06-07 | 20KB |

## 발굴 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `discovery/` | 발굴≠생산 substrate(P7) — pre-C13 raw 재조합 HGB 배터리(battery_phase0/round2·gate_phase0·phase1_raw) 발굴 인프라 | active | 2026-07-10 | 172KB |

## 문서 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `docs/` | 설계 SOT·확장 룰·CHANGELOG 계층 — qvest_v8_1_sot.md(Active SOT)·rules/ 확장 9·legacy_boundary·reference_textbooks | active | 2026-09-23 | 596KB |
| `README.md` | 인프라 존 진입 설명 (상세 목록은 INDEX.md) | active | 2026-07-03 | 1KB |

## 측정 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `eval/` | harness_perf_eval.R 단일 — v8.0 WS8-1 리서치 추론성능 before/after 측정 루프(2-tier: artifact + challenge_note) | active | 2026-06-29 | 11KB |

## 모드-QEPM (3)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `judge/` | judge_lockbox_harness.R 단일 — ★v10 2026-08-29 RETIRED(lockbox 제도 폐지, 진입점 제거·호출자 0). v10 Judge 는 PIT 전담(essence Grade A 후 스폰)이고 검증 계약은 judge_verdict_v2 · 08_Tests/worktask/test_judge_verdict_v2.R | retired | 2026-08-29 | 12KB |
| `prompts/` | agent spawn init 프롬프트 9건 — _shared_prefix.md(axiom derived cache) + alpha/risk/optimizer/forge/judge_init.md 등. 퇴역 5건(governor/execution/monitoring/qlead_init · qlead_spawn_template)은 _retired_v10/ (v10 2026-09-03) | active | 2026-09-23 | 213KB |
| `worktask/` | WT 계약 계층 — common_charter.md·cert_rules.R·constraint_defaults.json(graduation severity)·run_all_template.R(현행 forge 템플릿)·lineage_utils | active | 2026-09-23 | 310KB |

## 메모리 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `memory/` | 메모리·지식 헬스 파이프라인 — memory_knowledge_health.R(axiom 헬스게이트 hard6+warn6)·weekly/monthly_distill.sh·lcode_corpus_rebuild | active | 2026-09-23 | 185KB |

## ML (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ml_pipeline/` | ML/DPL 파이프라인 — dpl_portfolio.py(DPL pilot, §5 구성레이어)·PIT audit 스크립트·feature panel 빌더(venv qvest_ml 소비) | active | 2026-08-29 | 469KB |

## 운영 (4)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `monitoring/` | 라이브 페이퍼트래킹 — noLayer4 일별 마킹(mark_nolayer4_daily.R)·월간(run_nolayer4_monthly.sh)·holdout 대조(monitor_nolayer4_paper.R). 구 faithtrend 스크립트+.bak = deprecated rollback 보존 | active | 2026-09-02 | 60KB |
| `ops/` | 운영 계층 54건 — bootstrap.sh(/qvest 진입)·cleanup.sh·scheduler/(.bat 태스크)·헬스체크·paper router | active | 2026-09-23 | 2.7MB |
| `telegram/` | 텔레그램 계층 4건 — telegram_notify.R(발송)·telegram_listener.py·telegram_commands.R·start_listener.sh (qvest-telegram SOT의 구현체) | active | 2026-09-05 | 231KB |
| `tools/` | 운영 도구 16건 — build_artifact_index.R·paper_recharge_daily.R(논문 수집)·debate_helpers 등 | active | 2026-09-23 | 345KB |

## 관측 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `observability/` | 관측 CLI — qvest_observe/qvest_wt(WT 타임라인 조회)·emit_event.sh(이벤트 로그)·wt_timeline.R | active | 2026-07-26 | 38KB |
| `search/` | qvest_search CLI — 세션/artifact 검색 인덱스 빌드(build_index.R)·질의(_query.py) | active | 2026-07-25 | 47KB |

## 포트폴리오 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `portfolio/` | 포트폴리오 계층 31건 — BOOK_0001 리밸/트래킹 배관(forward_weights_D3_M4gAE·deployed_holdings_check 짝)·s5_mutation_runner·measurement_basis_audit. ★portfolio_governor.R 의 pg0~pg3 admission 진입점은 v10 봉인(BOOK = 06_Registry/book/book_registry.json + book_registry.R 승계) — book-marginal ΔIR 은 2계층 진단 도구로만 존치 | active | 2026-09-21 | 962KB |

## 모드-RAMP (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ramp/` | ④ RAMP 모드 구현 — 순수팩터 추출(_extract_*)·ccs_evaluator.R(CCS 13-score)·graduation·진단 스크립트 | active | 2026-09-07 | 18.7MB |

## 국면 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `regime/` | 국면엔진 계층 28건 — regime_engine.R v7.1·regime_module_admission.R(RCMA)·국면 분류기(factor-rotation·overlay 공급) | active | 2026-09-07 | 591KB |

## 리스크 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `risk/` | 리스크 측정 도구 — textbook_methods/(EVT 엔진 등 교과서 구현, WT에서 실사용). 루스 3건은 참조 0으로 2026-07-04 스윕 삭제(cleanup_manifest_20260704) | active | 2026-06-07 | 12KB |

## 검증 (2)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `sanity_checks/` | bear_date_audit.R 단일 — forward label 방향 PIT 의무 감사(Cycle 50 lookahead 재발 방지 게이트) | active | 2026-06-07 | 12KB |
| `validation/` | 검증 계층 26건 — pit_enforcement.R·lookahead_detector.R(PIT Level 0 구현)·v8_readiness_gate.R·preflight_check·stage_artifact_schemas | active | 2026-08-29 | 368KB |

## 설계 SOT (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `docs/qvest_v8_3_alpha_discovery_sot.md` | v8.3 알파 발굴 중심 재편 SOT (도훈 mandate 2026-07-10 — F1~F10 진단 + M1~M11 이행표 + frontier 큐 규약 + 도훈 결정 대기 D1~D4) | active | 2026-07-26 | 13KB |

## 테스트 (1)

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `tests` | 인프라 단위 테스트 — test_continuity_gate.py(Continuity Firewall L2 판정기 회귀) | active | 2026-08-02 | 32KB |

## 미분류 (6) — index_descriptions.json에 추가하세요

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ast` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-02 | 187KB |
| `book` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-30 | 41KB |
| `methods` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-29 | 210KB |
| `reinforcement` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-23 | 624KB |
| `replication` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-29 | 8KB |
| `utils` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-08-30 | 13KB |

## stale 큐레이션 키 (4) — 디스크 부재, index_descriptions.json에서 제거 권장

- `experiment_contract.R`
- `strategy_template.R`
- `04_Research/`
- `agents/`

