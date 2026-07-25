# Qvest AST 계층 v1.1 — 설계 SOT (Qvest-정합판)

**발효**: 2026-07-25 (도훈 승인 — 원안 v1.0 검토 지시 → 수정 채택 판정 → "v1.1 SOT 진행" 승인. Step 0 결정: C4 연간 = 익년 3/31 확정)
**계보**: 원안 v1.0(도훈 제시) → 편입 판정 `04_Research/01_reports/ast_layer_adoption_review_20260725.md`(4-agent 실측 검증, 수정 6건) → 본 SOT.
**목적**: alpha 에이전트의 가설 설계 실력 업그레이드 — PIT 정적 검증 → OOS 붕괴 귀속 → 커버리지 지도.
**대상 루프**: QEPM 모드 (`alpha → [PIT 정적검증] → risk/optimize → forge(IS) → judge(OOS·PIT) → governor`).
**field_dictionary 원천**: `06_Registry/ast_field_map_v0.json` (58 리프 그룹 실측 전수, 2026-07-25).

---

## §0 결정 대장 (v1.0 → v1.1 확정 변경)

| # | 결정 | 근거 (실측) |
|---|---|---|
| M1 | AST-단일 인터체인지 폐기 → **AST-우선 + escape 리프 4종** | 07월 실물 alpha_package 46건 중 ML 8~9·LLM 1·특수연산 2 = 환원 불가, 최신 cohort 7건 중 5건 ML. 헌장(방법론 완전 자율) 유지 |
| M2 | 신규 리프 주석 테이블 금지 → **factor_registry 기계가독 승격 + ast_field_map 참조** | registry lag_rule 373건이 이미 선언돼 있으나 코드 소비자 0 — 별도 테이블은 3중 SOT |
| M3 | Phase 1 = verify() 단독이 아니라 **3중 구조 예방** | 실사고 4건 회고: verify() 단독 1/4, 컴파일러-소유 AS_OF 조인 + 𝒪 한정 포함 시 최대 4/4 |
| M4 | 로깅 = **essence_score() 사이드카 JSONL** | backtest_registry = 죽은 스트림(3개월 22행). essence_score는 전 graduation 판정 경유 |
| M5 | judge 12점 HARD 게이트 폐기 → **기계 훅 4종 + Claude 축 1·4 screening advisory** | 축 2·3은 Gate A~F 중복. graduation HARD 3종·cap-w 권위 불변 |
| M6 | Phase 2 분석은 N≥30부터, escape 비중만큼 커버리지 절단 명시 | N=30 도달 실측 추정 2~4주(로깅 개시 후, escape lane 제외) |
| Step 0 | **C4 연간 availability = 익년 3/31 확정** (2026-07-25 도훈) | 현 구현(data_collector_dart.R:840) 기준. pit.md C4 행 동시 개정 완료 |

---

## §1 전략 스펙 3층 구조 (alpha 산출 계약)

| 층 | 형식 | 비고 |
|---|---|---|
| 가설 | 구조화 JSON — **mechanism{agent, friction, path} 3필드 + falsification + regime_scope 필수** | "시장이 비효율적" 류(주체·마찰 무명명)는 기계 반려. falsification은 field_dictionary 내 필드로 확인 가능한 부수 관측만(성과 동어반복 금지). regime_scope.weakens_or_reverses_in 빈 배열 금지 |
| 팩터 정의 | **AST** (formulaic lane 의무) — 단 escape 리프 4종 허용 | §2 |
| 결합 규칙 | enum (기존 Z_Score_Aligned 결합 컨벤션 계승) | 트리 기계장치 불요 |

공분산·비중은 risk/optimize 소관 (불변). **timing-overlay / factor-timing-meta 표면은 본 계층 범위 제외** (명시 선언 — 팩터식→종목스코어 형상이 아님).

## §2 연산자 라이브러리 𝒪 + escape 리프

**𝒪 초기 최소집합 = 원안 v1.0 §2 그대로 채택**: 횡단면(CS_RANK/ZSCORE/WINSORIZE/NEUTRALIZE/DEMEAN) · 시계열(TS_LAG/DELTA/MEAN/STD/RANK/MIN/MAX/SUM/CORR/BETA) · 산술(ADD/SUB/MUL/DIV가드/LOG/ABS/SIGN/SQRT) · 조건(CLIP/IF_ELSE/WHERE — 복잡도 별도 카운트) · PIT 정렬(AS_OF/VINTAGE). **LEAD·FUTURE_* 부재 원칙** (표현 불가 = 실수 불가. Cycle 50 double-negation 유형의 문법적 제거).

**escape 리프 4종** (AST 환원 불가 산출 수용 — 헌장 자율성 보존):

| 리프 | 대상 | PIT 계약 |
|---|---|---|
| `MODEL_SCORE` | ML 학습 스코어 (LightGBM 등) | 학습창 종점 ≤ t_d − 1 선언 의무 + 학습 데이터 리프 목록 첨부(각 리프는 본 맵 검증 대상) |
| `STORED_SCORE` | 저장 파생 패널 (insider 패널·국면 신호 등) | **provenance 3필드** {기반 store build_hash, 생성 코드 경로, 생성 시각} + `production_parity_verified` 라벨(§7b 기계화). 파생 패널을 FIELD로 위장 금지 |
| `LLM_SCORE` | 텍스트 LLM 채점 (사업보고서 등) | 채점 대상 문서 rcept_dt ≤ t_d + 프롬프트/모델 sha 동결 |
| `SPECIAL_OP` | TE/Kalman 등 특수연산 | 연산 정의 코드 경로 + walk-forward 여부 선언 |

**𝒪 확장 규율**: `operator_backlog`(`06_Registry/ast_operator_backlog.json`)에 `blocked_by_capability` verdict가 적립된 것만 근거로 확장. 선제 확장 금지. escape 리프 비중은 Phase 2 사이드카에서 분기별 집계 — 비중 상승 = 𝒪 확장 신호.

## §3 리프 스키마 — 단일 SOT 원칙

**신규 테이블 신설 금지.** 3계 구성:

1. **`06_Registry/ast_field_map_v0.json`** = 리프 그룹 카탈로그 (도메인·클래스·커버리지·위험 — 실측 스냅샷, 분기 재실측).
2. **factor_registry.json 기계가독 승격** (Step 1 본작업): 현행 자유문자열 `lag_rule`을 구조 필드로 승격 — `availability {type: fixed|regulatory|manual_export, days|rule}` + `restatement_prone` + `vintage_available` + `refresh_mode: auto|manual`. **강제값은 코드 강제점 기준** (선언≠구현 불일치 시 등록 거부). 13k줄 reformat 함정 — add_factor.R 라인-타겟 패턴 준수.
3. **파싱 하드코딩과의 정합 검증**: 등록 시 선언값 ↔ 강제점(파일:라인) 대조를 CI-성 체크로.

**Step 0 확정값 (C4)**: 연간(사업보고서 계열) availability = **익년 3/31** (DART 구현 기준, pit.md 개정 완료). 분기 = 45일 / DART 분기 고정일(5/15·8/15·11/15).
**⚠ 수리 항목 (판정영향 — 별도 사이클)**: xlsx 경로 Q4 일률 +45d(≈익년 2/14)는 3/31 대비 ~6주 공격적 = 잠재 look-ahead. 수리 = parse_fundamental_xlsx.R Q4 Factor_Date를 3/31로 상향 → **factor DB 재빌드 유발 + 기존 graduation 판정 변동 가능** — pin_cache 규약(§7) + 전후 A/B 계획과 함께 실행하고, 수리 전까지 Q4-민감 팩터 판정에 이 노출을 주석.

**리프 계약 불변식 6종** (ast_field_map §5 권고 승격):
① `refresh_mode: manual` 리프는 cache_registry `max_lag_days` 연동 스테일 경보 의무 (멤버십 3/31 종점 사고 재발 방지) ② Date dtype(date32)·심볼 sanity 불변식 (벤치 실사고 계열) ③ STORED_SCORE provenance 3필드 ④ 국면/오버레이 도메인 리프는 `apply_cutoff: first_day_of_holding_month` 속성 내장 (C5 — BearProb 실사고) ⑤ DART 계열 corp_code≠stock_code 조인 가드 + rank-IC advisory/PORT_t 권위 그룹 라벨 (전이 벽 실측 도메인) ⑥ fdb_daily 전용 접근자 신설 후에만 일간 리프 허용 (C15 carve-out 해소).

## §4 Phase 1 — PIT 3중 구조 예방 + 정적검증

**회수의 본체 = 3중 구조 예방** (실사고 회고 실측 — verify() 단독 1/4, 3중 포함 최대 4/4):

1. **canonical 리프 강제**: AST 리프는 ast_field_map 등재 + registry 승격 스키마 통과분만. **저장 파생 패널의 FIELD 위장 금지** (사고2 유형 — §7b 기계화).
2. **컴파일러-소유 AS_OF 조인**: forge 컴파일러가 리프 로드·조인·정렬을 AS_OF 규율로 **생성**한다 — 수기 merge 금지. 백테와 배포가 동일 컴파일 경로 (사고1·3 유형 — 사고3의 배포 코드 `Date<AS_OF`가 clean했던 반사실이 근거).
3. **𝒪 표현공간 한정**: LEAD 부재 + 부호 없는 명시적 lag (사고4 유형 문법 제거).

**verify() 알고리즘 = 원안 v1.0 §4 그대로 채택** (리프 avail_ts 상향 전파, TS_LAG 완화·롤링 최신관측 구속·AS_OF resolve). 판정 3종: `PASS` / `FAIL_LOOKAHEAD`(alpha 반려, forge 사이클 0 소비) / `WARN_RESTATEMENT`(통과 + 스펙 플래그 → judge·governor 입력).

**동적 검정 병행 유지 (HARD 원칙)**: judge 경험적 PIT 검증·lag1 스트레스·strict A/B·vintage-swap·validate_label_direction은 **대체 불가** — 실사고 4건 전부 표준 통계검증을 통과하고 동적 도구로만 검거된 실측. 정적 PASS ∧ 동적 위반 징후 = **리프 메타 버그** → `06_Registry/ast_leaf_table_bugs.jsonl` 큐 적립 (인프라 버그 리포트, 전략 문제 아님).

## §5 Phase 2 — 구조특징 로깅 (적립은 즉시, 분석은 N≥30)

**배선점 = essence_score() 내부 append-only 사이드카** `06_Registry/ast_structure_log.jsonl` (전 graduation 판정 경유라 capture 구조 보장 + oos_retention_splits 유실 문제 동시 해소):

```json
{ "strategy_id", "ts",
  "ast_features": { "node_count", "max_depth", "free_param_count", "distinct_field_count",
                    "conditional_op_count", "window_variety", "restatement_exposure",
                    "escape_leaf_count", "escape_leaf_types" },
  "is_perf": {...}, "oos_retention", "oos_retention_splits", "port_t_nw",
  "active_regime", "judge_verdict", "governor_verdict", "selection_type" }
```

- 원안 필드 + **escape_leaf_count/types 추가** (커버리지 절단의 명시 — escape lane은 구조특징 사전분포 대상 외).
- governor 거절분 포함 전량 로깅 (생존편향 방지) + active_regime 라벨 (국면변화≠과적합 통제).
- **분석 규율 원안 채택**: N<30 회귀 금지(Spearman·분위 비교만) / 30~80 단변량 / 80+ 정규화 다변량. 산출은 alpha 프롬프트 `<complexity_prior>`에 숫자로 주입.
- decay 종속변수 = 기존 oos_retention v2·decay-pattern 라벨 **재사용** (재구축 금지). FQ-055 감쇠 지식과 상보.

## §6 Phase 3 — 커버리지 지도 (Phase 1 부산물, 후순위)

행렬 = ast_field_map의 FIELD + FIELD_REGISTRY_PTR 그룹 (escape 리프 제외). 집계·gap_score = 원안 §6 채택. 빈 셀 분류 4종(경제적 공백→`confirmed_voids` / 표현 한계→`operator_backlog` / 데이터 신규성 / 경로의존 사각→가설 설계 대상). **주입 원칙 불변**: 지도는 주의 힌트 — 메커니즘 없는 빈칸 채우기는 Phase 2가 벌하는 대상. `confirmed_voids`는 hypothesis_index와 교차 등재(재제안 방지).

## §7 judge 게이트 보강

**기계 훅 (신규 1개 — `ast_spec_gate.sh`, 라우터 dispatch 등록)**: ① mechanism 3필드 누락 → block ② falsification이 field_dictionary 밖 필드 참조 → block ③ regime_scope.weakens_or_reverses_in 빈 배열 → block ④ AST에 𝒪 밖 연산자(escape 리프 제외) → block ⑤ FAIL_LOOKAHEAD 도달 → block + 검증 계층 버그 경보. **작성 3의무 준수** (env-경유·raw-INPUT 조기-exit·additionalContext — harness.md 2026-07-24 정합 절).

**Claude 판정 (screening-tier advisory — HARD 아님)**: 축 1(메커니즘 구체성 — 주체·마찰 특정 가능성) + 축 4(국면 경계가 메커니즘에서 도출되는가). 각 0-3점, 합 3 미만 시 재설계 권고(반려 아님 — advisory). 축 2·3(반증가능성·가설-구현 정합의 PIT/성과 판정)은 기존 Gate A~F가 전담 — 신설 금지. **graduation HARD 3종(PORT_t 2.95·oos_retention 0.7·calmar 0.64)·cap-w 권위·DSR sweep 규칙 불변.**

## §8 도입 순서 + 산출물

```
Step 0 ✅ C4 연간 = 3/31 확정 (2026-07-25 도훈. pit.md 개정 완료)
Step 1 ✅ 완료 (2026-07-25 — wf_6e8ece74 S1/S2/S3):
        · registry 승격 373/373 (availability{type,rule,known_discrepancy 171}+restatement+vintage+refresh_mode,
          멱등 migrate + validator 2스크립트 + add_factor 템플릿 4필드 — 구식 append는 validator가 검거)
        · fdb_daily 접근자 load_daily_factors() (connector v2.3 — pushdown·C13 월간 ic_sign·PIT 이중강제.
          ⚠일간 값 = winsorized raw, z 아님 — 결합 전 표준화 caller 책임)
        · Q4 +45d 수리 계획서 (04_Research/01_reports/q4_lag_repair_plan_20260725.md — 노출 본체 pre-2015
          1,095,004행, 권고 (a) parse Q4→3/31 + 전기간 재빌드 ~15분 + pin/shadow A/B. **착수 = 도훈 confirm 대기**)
        · 동반 데이터 트랙: 멤버십 8패널·수급·컨센서스 2026-07-24 현행화 + factor_db 당월 재빌드
          (855,571행·주간 스테일 트리거) + IC 프론티어 판정(2026-05 = 구조적, guard 추가)
Step 2 alpha 출력 스키마 3층화(schema.json 개정 + alpha_research_init.md 개정 + escape 리프 계약)
        + forge AST→R 컴파일러(𝒪 연산자당 R 함수 1 — 산출은 기존 계약 canonical_screen_bt/
        build_bt_result 입력으로 접속, 자체합성 금지·Return.portfolio 경유 불변)
        ★ 컴파일러가 조인/정렬을 AS_OF 규율로 소유 (§4-2 — 회수의 본체)
Step 3 PIT 정적검증 삽입(alpha 직후) + ast_spec_gate.sh 등록
        ─── 손익분기 (§4 3중 예방 포함 조건) ───
Step 4 essence_score 사이드카 로깅 개시 (ast_structure_log.jsonl)
Step 5 N≥30 후 complexity_prior 추정 → alpha 프롬프트 주입
Step 6 커버리지 지도 (저비용 후순위)
```

**검증 기준**: Step 2 컴파일러는 기존 팩터 재현 parity(동일 리프 조합 → factor DB 값과 대조) / Step 3는 실사고 4건 재현 픽스처로 배터리 케이스(hook_e2e_battery 확장 — 사고2 유형 FAIL_LOOKAHEAD·사고4 유형 표현 불가 확인).

## §9 불변·경계 (헌법 정합)

- alpha 방법론 자율(헌장) **보존** — AST는 formulaic lane 의무 + escape 리프이지 방법론 제한 아님. 6-agent 구조·역할 경계 불변.
- C15(load_month_factors 경유)·§7b(production 코드 권위)·C5(오버레이 컷오프)·Production Constraints·INV-7 전부 불변 — 본 계층은 이들의 **기계화**다.
- 부활 조건: AST-단일 원안은 ML lane 구조 축소 또는 MODEL_SCORE 학습창 정적검증 성립 시 재검토. judge 축 advisory의 HARD 승격은 (IS,OOS) 표본으로 판별력 실증 후.

## §10 한계 (원안 §10 전부 유효 + 추가)

원안 6개 항목(리프 테이블 단일 실패점 / 𝒪 상·하한 / vintage 없는 재무 구제 불가 / N<30 무의미 / 지도 자기이력 편향 / 알파를 만들지 않음) 전부 유효. 추가: ① escape 리프 비중 상승 = 통제력·사전분포 커버리지 비례 감소 — 분기 모니터링(§2) ② 리프 메타 진실성은 사고2 회고가 실증한 전제조건 — judge 동적 검증 병행이 HARD 원칙(§4).

## 참조

- 원안 v1.0 (도훈 제시, 2026-07-25 대화) · 편입 판정 `04_Research/01_reports/ast_layer_adoption_review_20260725.md` · 리프 맵 `06_Registry/ast_field_map_v0.json` + 보고서 `ast_field_map_v0_report_20260725.md`
- 규범 연결: `.claude/rules/pit.md`(C4 개정 2026-07-25) · `measurement-graduation.md` §7b · `answer-principles.md` · `02_Infrastructure/docs/rules/harness.md`(훅 3의무)
