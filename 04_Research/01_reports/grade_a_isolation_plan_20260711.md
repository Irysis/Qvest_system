# grade_a_catalog v53 착시 격리 계획서 (report-only)

- **작성**: 2026-07-11, M10 과제 4 (v8.3 F10 후속 — 조준 계기판 수리 동반 감사)
- **성격**: **제안서만 — 본 문서 작성 시점에 삭제/격리/이동은 일절 실행하지 않음.** 실행은 도훈 confirm 후 별도 세션.
- **대상**: `04_Research/grade_a_catalog.json` (schema v53_s2_15)

---

## 1. 현황 실측 (2026-07-11)

| 항목 | 실측값 |
|---|---|
| 총 entry | 39건 (grade_counts: A=39) |
| v53 스캔 산출 (builder) | **34건** — source가 `04_Research/strategies/*/output*/hurdle_result.json`(29) + `stage_artifacts/s6_judge_*.json`(5), source_mtime 2026-03(18)·2026-04(16) vintage |
| hurdle_gate 최근 append | **5건** — `STR_AS_*` (2026-06-12/13 4건 + 2026-07-09 1건), source=`stage_artifacts/alpha_search/*/hurdle_result.json`, `timestamp` 필드 보유 |
| `metric_type` 라벨 | **전 39건 부재** (measurement-graduation §1 라벨 의무 위반 상태의 구세대 산출물) |
| sim_result.rds 실존 (FR union 실기여) | 17건 = v53 12건(STR_944·943·1435·1439·1393·1028·1033·1571·1469·1562·**1555·1550**) + STR_AS 5건 |
| essence 권위 A | **0건** (staged 진단 입력 — grade 산정 권위 = `essence_score.R`, hurdle_gate 18-component는 proxy 진단용 강등: measurement-graduation §3) |

착시 구조: v53 시대 hurdle proxy 채점(A 34건)이 "Grade A 풀 존재"처럼 광고되나, 현행 권위(essence/HARD 3종) 기준 A는 0건. 부수: STR_1550/STR_1555는 `qepm/memory/registry/catalog_v53_expelled.md`에서 이미 expel 기록된 이력이 있음에도 catalog에 잔존.

## 2. 소비자 전수 (grep 전수, 코드 11파일 + 문서군)

| # | 파일 | 무엇을 읽나 | v53 34건 격리 시 영향 |
|---|---|---|---|
| 1 | `02_Infrastructure/validation/grade_a_catalog_builder.py` | **생성기** — v53 소스(hurdle_result/s6_judge) 재스캔 후 전체 재작성 | **재생성 리스크 #1**: 재실행 시 v53 34건 부활 + (글롭이 `04_Research/strategies/*`와 `stage_artifacts/s6_judge_*`만이라) STR_AS 5건은 **소실**되는 비대칭. catalog-only 격리는 builder 1회 실행으로 원복됨 → §3 동반 패치 필수 |
| 2 | `02_Infrastructure/hurdle_gate.R` L1802-1866 | **appender** — grade=="A" 시 entry append (중복 id만 체크, 기존 내용은 안 읽음) | 무영향 (파일 존재·strategies 배열만 있으면 동작). 단 hurdle A는 proxy이므로 append분에 `metric_type:"proxy"` 라벨 추가 권장 (§3-C) |
| 3 | `qepm/R/blender_scaffold.R::blender_check_activation` | `strategies` 길이 ≥4 → blender 활성화 판정 | 34건 격리 후 5건 잔존이면 여전히 activated=TRUE(착시 축소판). **전량 격리 시 FALSE = 정당한 결과**(essence A 0건이므로 blender 활성 신호 자체가 거짓이었음). blender는 ondemand라 운영 파급 없음 |
| 4 | `qepm/R/blender_scaffold_v55.R` | `strategies[].role` distinct ≥3 (v55 legacy) | 위와 동일. v55는 legacy boundary 대상 — 영향 무시 가능 |
| 5 | `02_Infrastructure/regime/build_module_performance.R` L94-104 | A건을 `legacy_qepm_grade_a`로 FR eligible union (hash 계약 없음 → WARN만) | **가장 실질적 소비자.** 격리 시 v53 proxy 모듈 12건이 FR 소비 풀에서 제거 — 의도된 효과. **FR 빌드 중단(L130 stop) 위험 없음**: module_catalog 계약 경로 fr_eligible **192건 실측**(contract_pass+frozen+backtested). STR_AS 5건은 module_catalog에도 계약 등재돼 있어 격리 후에도 contract 경로로 소비 유지(이중 등재 해소 부수효과) |
| 6 | `02_Infrastructure/contracts/register_module.R::register_existing_qepm_modules` | 선택적 마이그레이션 헬퍼 (기본 미실행) | 격리 = v53 proxy의 module_catalog 승격 소스 차단 — 의도된 효과 |
| 7 | `02_Infrastructure/validation/preflight_memory.R` L50-63 | 유사전략 중복 INFO | 사실상 무영향. **잠재버그 발견(report-only)**: `Filter(..., catalog)`가 `catalog$strategies`가 아닌 wrapper를 순회 → similar 체크가 현재도 항상 0건 no-op |
| 8 | `02_Infrastructure/validation/backlog_bucket_monitor.py::_collect_grade_a_families` | `strategies[].family/role` 집합 → s0 backlog bucket 분류 | stabilize 분류 감소·explore 흡수. 진단 도구(게이트 아님) — 오히려 정확해짐 |
| 9 | `02_Infrastructure/strategy_analyzer.R` L559-597 | role=="core" entry의 `output_dir`/holdings_detail.csv로 core overlap | 이미 대부분 no-op (builder 산출 34건엔 `output_dir` 필드 없음, hurdle append 5건에만 존재). 격리 후 core_overlap=NA — 현재와 실질 동일 |
| 10 | `02_Infrastructure/hooks/milestone_commit.sh` L146-151 | GRADE_A 마일스톤 시 catalog를 git add (내용 안 읽음) | 무영향 (파일이 같은 경로에 존재하면 됨 — **Option B의 파일 삭제는 금지 사유**) |
| 11 | 무영향 참조 3건 | `08_Tests/contract_regression/test_hurdle_gate.R`(주석: 안 읽음) · `02_Infrastructure/axiom/cluster_extractor.py` L204(note 문자열) · `04_Research/strategies/STR_1675_*/_recheck_L143.R`(과거 버그 주석) | 무영향 |

문서/인덱스 참조 (내용 갱신만 필요, 코드 아님): `.claude/agents/blender.md` · `.claude/skills/factor-rotation/SKILL.md` · `02_Infrastructure/docs/rules/artifact-storage.md` · `04_Research/INDEX.md` · `06_Registry/artifact_index.json`/`index_descriptions.json` · `02_Infrastructure/docs/qvest_v8_3_alpha_discovery_sot.md`(F10 진단 원문).

## 3. 안전 격리 방법 제안 (권장 = A + 동반 패치)

**Option A (권장) — 스키마-보존 in-place quarantine**
1. catalog 내 `strategies`에서 v53 34건을 신규 배열 `strategies_quarantined_v53_proxy`로 이동 (entry 원형 보존 + 각 entry에 `quarantine_reason:"v53_hurdle_proxy_scoring — essence 권위 A 아님 (measurement-graduation §3)"`, `metric_type:"proxy"` 라벨 부착).
2. `grade_counts`/`n_strategies`는 잔존 `strategies` 기준 재계산, wrapper에 `quarantined_at`/`quarantine_basis` 기록.
3. 소비자 5곳(blender×2, build_module_performance, backlog_monitor, register_module)은 전부 `$strategies`만 읽으므로 **코드 수정 0으로 자동 격리**. 파일 경로 불변 → milestone_commit/존재성 체크 무영향.
- 지식 보존: 삭제 아님 — INV-7 failure-ledger 정합 (v53 채점 이력은 quarantine 배열 + git으로 영구 보존).

**동반 패치 (필수 — 없으면 원복됨)**
- **A-1 builder 게이트**: `grade_a_catalog_builder.py`에 (i) v53 소스 스캔분을 `strategies_quarantined_v53_proxy`로 라우팅(예: cutoff `source_mtime < 2026-05-29` = v8.x measurement-graduation 발효일) 또는 (ii) essence 산출물 확인분만 `strategies`에 수용. 그리고 재작성 시 기존 quarantine 배열과 hurdle-append 항목(현행 글롭 밖 `stage_artifacts/alpha_search/*`)을 보존/병합하도록 수정 — 현행 builder는 재실행만으로 34건 부활 + STR_AS 5건 소실.
- **A-2 appender 라벨**: `hurdle_gate.R` append entry에 `metric_type:"proxy"` + `grade_authority:"hurdle_screening(진단용)"` 필드 추가 (스키마 additive — 소비자 필드 불변).

**Option B (비권장) — 파일 이동 + 빈 스키마 재생성**: `grade_a_catalog_v53_quarantined_20260711.json`로 이동 후 원 경로에 n=0 스키마. 정보 손실은 없으나 quarantine-사유가 entry에 남지 않고, builder/appender 재유입 문제는 그대로 남음.

**Option C (비권장) — 소비자측 게이트**: 소비자 5곳에 각각 essence 검증 추가. 침습 크고 신규 소비자에 자동 적용 안 됨.

## 4. 실행 전 체크리스트 (실행 세션용)

1. 도훈 confirm (v53 34건 격리 범위 + STR_AS 5건 처리 방침: proxy 라벨 유지 잔존 vs 동반 격리).
2. FR 안전 재확인: `module_catalog.json` fr_eligible ≥1 (2026-07-11 실측 192건 — stop 위험 없음 확인 완료).
3. 격리 직전 원본 백업: `04_Research/grade_a_catalog.json.bak_pre_quarantine_YYYYMMDD` + git 커밋.
4. 격리 직후 검증: `blender_check_activation()` 반환 확인 + `build_module_performance` 드라이런(eligible 소스가 contract 경로로 유지되는지) + `backlog_bucket_monitor.py` 정상 종료.
5. 문서 참조 6건(§2 하단) 갱신.

## 5. 요지

- v53 proxy A 34건은 **소비자 5곳 중 실질 파급이 있는 곳은 build_module_performance(FR legacy union) 하나**이고, 그 경로는 contract fr_eligible 192건이 받치고 있어 격리 안전.
- blender 활성화 판정이 꺼지는 것은 부작용이 아니라 **착시 제거의 목적 그 자체** (essence 권위 A 0건).
- catalog-only 격리는 builder 재실행 1회로 원복되므로 **builder 게이트 동반 패치가 격리의 본체**다.
