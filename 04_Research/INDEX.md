# 04_Research INDEX

> 자동 생성 2026-07-04 04:47 — 큐레이션 원본: `06_Registry/index_descriptions.json` (role/status/category 수동 보완처) · 재생성: `Rscript 02_Infrastructure/tools/build_artifact_index.R` (daily_refresh 말미 자동). 본 파일 직접 수정 금지 — 재생성 시 덮어씀.

<details><summary><b>strategy-legacy</b> (3)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `strategies/ (STR_* 178+개 패턴 전체)` | QEPM 전 세대 전략 백테스트 결과 저장소(STR_XXX_name 178+) — 헌법·legacy boundary가 명시 보존하는 결과 아카이브 | legacy | 2026-07-03 | 396.3MB |
| `{run_batch_s3*.R ×6, run_s3_*.R ×8, s0_*.R ×2, s3_*.R ×6} (S-stage 스크립트 22개)` | v55 S0~S7 파이프라인 시대의 스테이지 배치 러너·직교성 측정 스크립트군 (S0 가설토론, S3 백테 배치, 직교성 측정) | legacy | 2026-06-07 | 145KB |
| `run_dart_strategies.sh` | DART 전략 일괄 실행 셸(v5x 시대) — DART insider 백필은 02_Infrastructure/data로 이관 | legacy | 2026-06-07 | 2KB |

</details>

<details><summary><b>active-pipeline</b> (2)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `decision_framework/` | bearish forecast v1~v3(예측 국면) + cross_section_distribution(DPL 피처 parquet) + smart_beta_regime·factor_untapped — 부팅·모닝브리핑·DPL 감사가 소비하는 활성 존 (409MB, 대부분 cross_section outputs 382MB) | active | 2026-07-02 | 406.4MB |
| `regime_comparison/` | KTRI/MSM 국면엔진 비교·검증·브리핑 발송 스크립트 — 일일 스케줄러(daily_refresh·모닝브리핑 ktri_rebuild)가 소비 중 | active | 2026-07-03 | 1.3MB |

</details>

<details><summary><b>모드-FR</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `factor_rotation/` | FR 모드(제3모드) 산출 존 — FR_002 워크포워드 앙상블 + fof_first_slice(KNS/IPCA/BMA/E2E/SPO+ 슈퍼팩터 4방법론 실측, 07-03) + smartbeta_allstock(전종목 국면배분) + predictive_overlay_ab. 1.4GB 최대 존 | active | 2026-07-03 | 1.3GB |

</details>

<details><summary><b>모드-RAMP</b> (2)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `ramp/` | RAMP 모드 Gate3~6 실행 스크립트(run_ramp_gate*.R) + reports(Shu-Mulvey 충실복제·순수팩터 추출 보고 등) — /ramp 모드 활성 산출 존 | active | 2026-07-03 | 137KB |
| `regime/` | RAMP용 국면엔진 33개 인벤토리 + bakeoff 실측(06-19) — [[project-ramp-regime-engines]]의 원 데이터 | report | 2026-06-19 | 44KB |

</details>

<details><summary><b>계약/데이터</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `grade_a_catalog.json` | Grade A 전략 카탈로그(모듈 등록·성과 빌드의 입력 데이터) — register_module/build_module_performance/milestone hook이 소비 | active | 2026-06-12 | 16KB |

</details>

<details><summary><b>데이터</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `lessons_sent.json` | 텔레그램 L-code 레슨 발송 이력 상태 파일 (중복 발송 방지) | active | 2026-06-07 | 122B |

</details>

<details><summary><b>인프라-sink</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `logs/` | 리서치 로그 sink 디렉토리 — cleanup·주간 수집 스크립트의 대상 경로 (현재 비어 있음 = 정상 정리 상태) | active | - | - |

</details>

<details><summary><b>지식-논문</b> (4)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `paper_notes/` | 논문 노트·전략 요약 모음(P204/P207, QMJ·Liquidity·SmartBeta 전략요약) — 검색 인덱스 빌더가 색인 | active | 2026-06-07 | 942KB |
| `pg2_schur_weight/` | Cotton 2024 Schur 보완 가중 논문 지식노트 — HRP 프론티어 7논문 구현(07-03)의 원전 참조 문서 | active | 2026-07-02 | 7KB |
| `paper_collection/` | PG2 강화 논문 43편 수집 결과 노트(07-02) — W2/W3 후속 경로의 입력 | report | 2026-07-02 | 6KB |
| `{paper_ensemble_hypotheses.md, paper_inbox_2026-03-14.md, paper_research_latest_2026_03.md} (2026-03 논문 노트 3개)` | 2026-03 논문 인박스·앙상블 가설·최신 리서치 정리 노트 (현행 파이프는 paper_collection·stage_artifacts/paper_recharge로 이동) | legacy | 2026-06-07 | 46KB |

</details>

<details><summary><b>지식-실패사례</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `strategy_postmortem.md` | 실패 전략 근본원인 체계 분석(SPMR) — alpha-search 러너가 참조하는 실패 지식 베이스 | active | 2026-06-07 | 26KB |

</details>

<details><summary><b>전략-로드맵</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `pg2_reinforcement_roadmap_20260702.md` | PG2 강화 W1~W4 로드맵(07-02) — W1 완료(오버레이 부정·Layer4 제거), W2/W3 잔여 큐의 SOT | active | 2026-07-02 | 15KB |

</details>

<details><summary><b>보고서-감사</b> (3)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `architecture_audit_20260703.md + architecture_audit_20260703_data/` | 07-03 아키텍처 전면 감사(71 agents·1,107 tool calls, 종합 4.5/10 — '자동 강제 계층 침묵 사망' 진단) 보고서 + file:line 증거 데이터 | report | 2026-07-03 | 344KB |
| `pg2_forensics/` | PG2 법의학 패키지 — B0 비용모델 flat-bug, B1 STR_1715 4-family 분해, B2 governor overlap, realized_ym offset 검증 (11MB) | report | 2026-06-11 | 10.0MB |
| `audits/` | batch_434 codegen 카탈로그 라벨 오염 감사(06-13) — 감사 스크립트+패치 플랜+NAV 클러스터 분석 | report | 2026-06-13 | 367KB |

</details>

<details><summary><b>experiment</b> (13)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `composition_search/` | 16-cycle 조합탐색 실측 산출(cycle1/1b/1c/2 × track B/D/F/O/P/S/V/W + trackW 적대검증) — measurement-graduation v8.x 재설계의 실증 근거 (117MB) | report | 2026-06-12 | 115.4MB |
| `dvaa_dvfs_revalidation/` | DVFS/DVAA vol-target·paradigm 재측정 실험(rds/xlsx, 06-17) — critical 2건 발견, 도훈 confirm 대기 상태 | report | 2026-06-16 | 3.3MB |
| `asset_allocation/` | 인버스 ETF 헤지 Phase1/1b 실측(REJECT settled, 06-26) + DVAA/DVFS 강화 리서치 노트(06-13) | report | 2026-06-26 | 4.2MB |
| `factor_db/` | Factor DB census v3 targeted 전수조사 — 커버리지 sweep·probe (24MB) | report | 2026-06-11 | 22.8MB |
| `defense_2022_recon/` | 2022 방어 국면 lensB 스타일 재구성 실험(스크립트+로그, 06-12) | report | 2026-06-12 | 26KB |
| `strategy_distill/` | Grade A 증류(grade_a_distill.json) + 한계기여 스크리닝(marginal_screening) 실험 | report | 2026-06-07 | 60KB |
| `multi_sleeve_analysis/` | 멀티슬리브 조합 분석 실험(run_analysis.R + output, v5x~v6 시대) — AX-007 예외 4종 검토 계열 | report | 2026-06-07 | 362KB |
| `korea_research/` | 한국시장 리서치 배치 G1/G2/G7/RQ1~10 시리즈 출력(Gerber 공분산 등, v5x 시대) — 29MB | legacy | 2026-06-07 | 28.1MB |
| `ml_research/` | ML 베이스라인 리서치(linear/logistic/elastic-net/xgboost) 스크립트 + ml_research_summary.md 종합 보고 | report | 2026-06-07 | 2.3MB |
| `ml_overnight_output/` | overnight ML 배치 결과(ridge/xgb/logit NAV·IC summary, 84MB) — ML 베이스라인 실측 원 데이터 | report | 2026-06-07 | 83.6MB |
| `ml_elastic_net_output/` | elastic net 팩터선택 빈도 결과(csv+log) | report | 2026-06-07 | 28KB |
| `portfolios/` | PF_001/PF_ALPHASEARCH/V7_ALLWEATHER_001/V7_M11_REF 포트폴리오 정의(v5x~v7 시대) | legacy | - | - |
| `factor_scan.R + factor_scan_results.csv` | 초기 팩터 전수 스캔 스크립트와 결과(49KB) — artifact-storage 룰이 예시로 참조 | legacy | 2026-06-07 | 54KB |

</details>

<details><summary><b>보고서-실험</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `pg2_offense_overlay/` | W1 공격 오버레이 딥리서치 노트(07-02) — KR long-only 시장타이밍 4중 최종부정(settled-negative)의 기록 | report | 2026-07-02 | 11KB |

</details>

<details><summary><b>보고서-검토</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `proposal_review_pg2_roadmap_2026-06-10.md` | PG2 8-Phase 로드맵 검토 보고(채택 4·기각 3, 06-10) | report | 2026-06-10 | 9KB |

</details>

<details><summary><b>보고서-모니터링</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `monitoring/` | T30 AR(Absorption Ratio) 리뷰 판정(06-12) — 조건 verdict + 리뷰 보고 | report | 2026-06-11 | 26KB |

</details>

<details><summary><b>보고서-설계</b> (2)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `regime_system/` | 국면시스템 업그레이드 플랜 문서(06-14) 단일 md | report | 2026-06-14 | 18KB |
| `v6_architecture.png` | v6 시스템 아키텍처 다이어그램 이미지 (225KB) | legacy | 2026-06-07 | 220KB |

</details>

<details><summary><b>보고서-스캔</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `hypothesis_scan/` | QEPM 가설 전수 스캔 보고(06-11) 단일 md | report | 2026-06-11 | 17KB |

</details>

<details><summary><b>훅/캐시</b> (1)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `worktask_scratch/` | WT-D20260425_009 스크래치(KR FF5 백필·공분산 스텝 스크립트+rds) — 캐시 레지스트리가 경로 참조 | legacy | 2026-06-07 | 58KB |

</details>

<details><summary><b>report</b> (4)</summary>

| 항목 | 정체 | status | 최근 | 크기 |
|---|---|---|---|---|
| `{rescore_v22_final.csv, rescore_v22_summary.csv, residual_alpha_ranking.csv, residual_alpha_top20.csv} (결과 CSV 4개)` | v22 전략 재채점 결과 + 잔차 알파 랭킹 실측 결과 — v5x 시대 스캔 산출 데이터 | report | 2026-06-07 | 176KB |
| `{DESIGN_DELIVERABLE_STR_930_935.md, STR_930_935_Design_Summary.md, STR_930_935_Quick_Reference.md, STRATEGIC_SUMMARY_Behavioral_Bias_P008_P020.md} (STR_930~935 설계 문서 4개)` | 행동편향 논문군(P008~P020) 기반 STR_930~935 전략 설계 문서 세트 (v5x 시대) | report | 2026-06-07 | 49KB |
| `{FUNDAMENTAL_DATA_GAP_ANALYSIS.md, FUNDAMENTAL_DATA_TECHNICAL_SPECS.md, FUNDAMENTAL_QUICK_REFERENCE.txt} (펀더멘털 데이터 문서 3개)` | 재무데이터 갭 분석·기술 스펙·퀵레퍼런스 — 펀더멘털 데이터 확충 검토 보고 세트 | report | 2026-06-07 | 51KB |
| `{SCOUT_HYPOTHESES_SR2_SESSION38.md, scout_factor_vitality_scan_session45.txt} (Scout 산출 2개)` | Session 38/45 Scout의 SR2 가설 목록·팩터 생존성 스캔 결과 (Scout는 alpha-research로 대체된 구 역할) | legacy | 2026-06-07 | 15KB |

</details>

## 정리 후보 (status=dead) (10)

| 항목 | 정체 | 카테고리 | 최근 | 크기 |
|---|---|---|---|---|
| `ml_xgboost_pilot_output/` | XGBoost 파일럿 연도별 모델 바이너리(.rds 2018~2025, 2.3MB) — 결과 csv 없이 모델만 잔존 | experiment | 2026-06-07 | 2.2MB |
| `ml_linear_baseline_output/ + ml_logistic_output/` | ML 베이스라인 실행 로그(run_log.txt)만 잔존하는 빈 껍데기 출력 디렉토리 2개 | dead | - | - |
| `briefings/` | 빈 디렉토리 (브리핑 산출 예정지였으나 미사용 — 브리핑은 02_Infrastructure/ops로 정착) | dead | - | - |
| `defense_2022_scan/` | 빈 디렉토리 (defense_2022_recon의 스캔 산출 예정지, 미사용) | dead | - | - |
| `worktasks/` | run_alpha_iter20.R 단일 잔존 — 구 alpha iteration 러너 스크립트 (WT 체계는 qepm/mailbox로 정착) | dead | - | - |
| `stage_artifacts/` | WT_WT-D20260425_009 이중 접두 오명명 스테이지 사본 1건 (루트 stage_artifacts/와 별개) — CLAUDE.md 미완 항목 'WT_WT-* cleanup'의 대상 | dead | - | - |
| `nav_tracking/` | STR_905 일별 NAV csv 1건 — 구 수동 NAV 트래킹 (라이브 트래킹은 02_Infrastructure/monitoring으로 이관 완료) | dead | - | - |
| `regime_analysis/` | 구 국면 시각화 png(KTRI 9quad·3layer·MRS daily) + threshold 튜닝 스크립트(v5x 시대) | dead | 2026-07-02 | 665KB |
| `blog_archive/` | 2026-03-14 블로그 아카이브 JSON 1건 (외부 콘텐츠 스크랩) | dead | - | - |
| `{allocate_12_hypotheses.R, allocate_gap_hypotheses.R, c19_v24_interaction_analysis.R, c19_v24_syn05_analysis.R, crisis_defense_analysis.R, factcheck_defense_hypotheses.R, factcheck_hypothesis.R, factor_correlation_vs_C19.R, factor_db_deep_analysis.R, factor_db_deep_phase2.R, factor_db_fix_impact_audit.R, ml_overnight_research.R, mrs_stress_detection_analysis.R, residual_alpha_analysis.R, risk_m4_m6_analysis.R, risk_validation_rev4.R, risk_validation_rev5.R, pg_run_STR_1656_M05.R, validate_rcpp_speedup.R} (일회성 분석 스크립트 19개)` | v5x 시대 일회성 분석·팩트체크 스크립트군(C19/V24 상호작용, 위기방어, factor DB 심층분석, 리스크 검증 rev4/5, Rcpp 속도검증 등) — 결과 CSV/보고서는 별도 보존됨 | dead | - | - |

