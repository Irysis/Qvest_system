# 04_Research INDEX

> 자동 생성 2026-10-16 08:17 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

<details><summary><b>strategy-legacy</b> (3)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `strategies/ (STR_* 178+개 패턴 전체)` | QEPM 전 세대 전략 백테스트 결과 저장소(STR_XXX_name 178+) — 헌법·legacy boundary가 명시 보존하는 결과 아카이브 | legacy | 2026-10-15 | 5.2GB |
| `90_legacy/run_dart_strategies.sh` | DART 전략 일괄 실행 셸(v5x 시대) — DART insider 백필은 02_Infrastructure/data로 이관 | legacy | 2026-06-07 | 2KB |
| `90_legacy/` | [재편 2026-07-04] v55/S0-S7 등 legacy 러너·산출 격리 보존 카테고리 (삭제 아님·신규 사용 금지) | legacy | 2026-07-03 | 391KB |

</details>

<details><summary><b>active-pipeline</b> (2)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `decision_framework/` | bearish forecast v1~v3(예측 국면) + cross_section_distribution(DPL 피처 parquet) + smart_beta_regime·factor_untapped — 부팅·모닝브리핑·DPL 감사가 소비하는 활성 존 (409MB, 대부분 cross_section outputs 382MB) | active | 2026-10-15 | 418.4MB |
| `regime_comparison/` | KTRI/MSM 국면엔진 비교·검증·브리핑 발송 스크립트 — 일일 스케줄러(daily_refresh·모닝브리핑 ktri_rebuild)가 소비 중 | active | 2026-10-15 | 1.3MB |

</details>

<details><summary><b>모드-FR</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `factor_rotation/` | FR 모드(제3모드) 산출 존 — FR_002 워크포워드 앙상블 + fof_first_slice(KNS/IPCA/BMA/E2E/SPO+ 슈퍼팩터 4방법론 실측, 07-03) + smartbeta_allstock(전종목 국면배분) + predictive_overlay_ab. 1.4GB 최대 존 | active | 2026-10-15 | 1.3GB |

</details>

<details><summary><b>계약/데이터</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `grade_a_catalog.json` | Grade A 전략 카탈로그(모듈 등록·성과 빌드의 입력 데이터) — register_module/build_module_performance/milestone hook이 소비 | active | 2026-08-02 | 18KB |

</details>

<details><summary><b>데이터</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `lessons_sent.json` | 텔레그램 L-code 레슨 발송 이력 상태 파일 (중복 발송 방지) | active | 2026-06-07 | 122B |

</details>

<details><summary><b>지식-논문</b> (2)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `paper_notes/` | 논문 노트·전략 요약 모음(P204/P207, QMJ·Liquidity·SmartBeta 전략요약) — 검색 인덱스 빌더가 색인 | active | 2026-06-07 | 942KB |
| `paper_ensemble_hypotheses.md` | 2026-03 앙상블 가설 노트 — fe_varratio.R H-10 가설 출처로 참조되어 최상위 유지 | legacy | 2026-06-07 | 21KB |

</details>

<details><summary><b>지식-실패사례</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `strategy_postmortem.md` | 실패 전략 근본원인 체계 분석(SPMR) — alpha-search 러너가 참조하는 실패 지식 베이스 | active | 2026-06-07 | 26KB |

</details>

<details><summary><b>보고서-감사</b> (2)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `01_reports/architecture_audit_20260703.md + architecture_audit_20260703_data/` | 07-03 아키텍처 전면 감사(71 agents·1,107 tool calls, 종합 4.5/10 — '자동 강제 계층 침묵 사망' 진단) 보고서 + file:line 증거 데이터 | report | 2026-07-03 | 43KB |
| `01_reports/audits/` | batch_434 codegen 카탈로그 라벨 오염 감사(06-13) — 감사 스크립트+패치 플랜+NAV 클러스터 분석 | report | 2026-08-20 | 482KB |

</details>

<details><summary><b>보고서-모니터링</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `01_reports/monitoring/` | T30 AR(Absorption Ratio) 리뷰 판정(06-12) — 조건 verdict + 리뷰 보고 | report | 2026-06-11 | 26KB |

</details>

<details><summary><b>experiment</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `90_legacy/factor_scan.R + factor_scan_results.csv` | 초기 팩터 전수 스캔 스크립트와 결과(49KB) — artifact-storage 룰이 예시로 참조 | legacy | 2026-06-07 | 6KB |

</details>

<details><summary><b>보고서-카테고리</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `01_reports/` | [재편 2026-07-04] 감사·검토·제안·로드맵 보고서와 그 증거 데이터 카테고리 (실행코드 참조 0 확인분 수용) | active | 2026-10-15 | 272.8MB |

</details>

<details><summary><b>문서</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `README.md` | 04_Research 존 안내 README (2026-07-04 재편 구조 + 탐색 가이드 1페이지) | active | 2026-10-14 | 3KB |

</details>

<details><summary><b>리서치-작업존</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `{insider, dart_census}` | DART insider 비-return 원천 라인 — exec netbuy 신호 빌드/비교, pledge·census 감사(07-13~15) | active | 2026-07-12 | 221KB |

</details>

## 정리 후보 (status=dead) (1)

| 항목 | 정체 | 카테고리 | 최근 | 크기 |
|---|---|---|---|---|
| `regime_analysis/` | 구 국면 시각화 png(KTRI 9quad·3layer·MRS daily) + threshold 튜닝 스크립트(v5x 시대) | dead | 2026-10-15 | 618KB |

## 미분류 (3) — index_descriptions.json에 추가하세요

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `advisor` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-09-25 | 3KB |
| `l2_role_rotation` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-10 | 27.8MB |
| `programs` | (미분류 — index_descriptions.json에 추가하세요) | - | 2026-10-15 | 12.1MB |

## stale 큐레이션 키 (37) — 디스크 부재, index_descriptions.json에서 제거 권장

- `ramp/`
- `logs/`
- `pg2_schur_weight/`
- `pg2_reinforcement_roadmap_20260702.md`
- `pg2_forensics/`
- `composition_search/`
- `01_reports/paper_collection/`
- `01_reports/pg2_offense_overlay/`
- `01_reports/proposal_review_pg2_roadmap_2026-06-10.md`
- `02_experiments/dvaa_dvfs_revalidation/`
- `02_experiments/asset_allocation/`
- `regime/`
- `01_reports/regime_system/`
- `01_reports/hypothesis_scan/`
- `korea_research/`
- `briefings/`
- `worktasks/`
- `worktask_scratch/`
- `stage_artifacts/`
- `nav_tracking/`
- `portfolios/`
- `blog_archive/`
- `01_reports/v6_architecture.png`
- `90_legacy/{run_batch_s3*.R ×6, run_s3_*.R ×8, s0_*.R ×2, s3_*.R ×6} (S-stage 스크립트 22개)`
- `{allocate_12_hypotheses.R, allocate_gap_hypotheses.R, c19_v24_interaction_analysis.R, c19_v24_syn05_analysis.R, crisis_defense_analysis.R, factcheck_defense_hypotheses.R, factcheck_hypothesis.R, factor_correlation_vs_C19.R, factor_db_deep_analysis.R, factor_db_deep_phase2.R, factor_db_fix_impact_audit.R, ml_overnight_research.R, mrs_stress_detection_analysis.R, residual_alpha_analysis.R, risk_m4_m6_analysis.R, risk_validation_rev4.R, risk_validation_rev5.R, pg_run_STR_1656_M05.R, validate_rcpp_speedup.R} (일회성 분석 스크립트 19개)`
- `90_legacy/{rescore_v22_final.csv, rescore_v22_summary.csv, residual_alpha_ranking.csv, residual_alpha_top20.csv} (결과 CSV 4개)`
- `01_reports/{DESIGN_DELIVERABLE_STR_930_935.md, STR_930_935_Design_Summary.md, STR_930_935_Quick_Reference.md, STRATEGIC_SUMMARY_Behavioral_Bias_P008_P020.md} (STR_930~935 설계 문서 4개)`
- `01_reports/{FUNDAMENTAL_DATA_GAP_ANALYSIS.md, FUNDAMENTAL_DATA_TECHNICAL_SPECS.md, FUNDAMENTAL_QUICK_REFERENCE.txt} (펀더멘털 데이터 문서 3개)`
- `90_legacy/{SCOUT_HYPOTHESES_SR2_SESSION38.md, scout_factor_vitality_scan_session45.txt} (Scout 산출 2개)`
- `01_reports/{paper_inbox_2026-03-14.md, paper_research_latest_2026_03.md} (2026-03 논문 노트 2개)`
- `02_experiments/`
- `method_frontier`
- `decay_fit`
- `factor_selection_program`
- `pg2_carry_convention`
- `champions_revalidation`
- `pg2_overlay_beyond_r05m4_20260705.md`

