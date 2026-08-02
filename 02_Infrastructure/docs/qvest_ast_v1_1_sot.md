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
| 가설 | 구조화 JSON — **mechanism{agent, friction, path} 3필드 + falsification + regime_scope + pit{sig_date} 필수** | "시장이 비효율적" 류(주체·마찰 무명명)는 기계 반려. **falsification 정본 = 객체배열**(각 원소가 `field`/`fields`/`field_ref`/`leaf`/`group_id`/`factor` 중 하나로 field_dictionary 내 필드를 지목 — 2026-08-02 ALB-005 수리로 확정. 종전 schema는 string, gate는 배열을 요구해 **두 계층을 동시에 만족하는 패키지가 없었다**). 성과 동어반복 금지. regime_scope.weakens_or_reverses_in 빈 배열 금지. AST 위치는 `factors[].ast`(다중 팩터 정본) 또는 top-level — 게이트가 **전 팩터를 각각** 검사한다(ALB-006 수리) |
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
**✅ Q4 수리 완료 (2026-07-25 도훈 승인·집행)**: parse Q4→3/31 + 전기간 재빌드(월간 439 + fdb_daily + IC) + pin/A/B 완주 — **판정 tipping 0건 확정**, diff는 예측대로 pre-2015 재무-성장 계열 FEB 스냅샷에 국소화. registry 124엔트리 rule 정규형+discrepancy 해소, validator 전체 PASS. 상세 = `q4_lag_repair_plan_20260725.md` §5. (잔여: consensus 계열 저상관의 입력-드리프트 분리 귀속 1건)

**리프 계약 불변식 6종** (ast_field_map §5 권고 승격):
① `refresh_mode: manual` 리프는 cache_registry `max_lag_days` 연동 스테일 경보 의무 (멤버십 3/31 종점 사고 재발 방지) ② Date dtype(date32)·심볼 sanity 불변식 (벤치 실사고 계열) ③ STORED_SCORE provenance 3필드 ④ 국면/오버레이 도메인 리프는 `apply_cutoff: first_day_of_holding_month` 속성 내장 (C5 — BearProb 실사고) ⑤ DART 계열 corp_code≠stock_code 조인 가드 + rank-IC advisory/PORT_t 권위 그룹 라벨 (전이 벽 실측 도메인) ⑥ fdb_daily 전용 접근자 신설 후에만 일간 리프 허용 (C15 carve-out 해소).

## §4 Phase 1 — PIT 3중 구조 예방 + 정적검증

**회수의 본체 = 3중 구조 예방** (실사고 회고 실측 — verify() 단독 1/4, 3중 포함 최대 4/4):

1. **canonical 리프 강제**: AST 리프는 ast_field_map 등재 + registry 승격 스키마 통과분만. **저장 파생 패널의 FIELD 위장 금지** (사고2 유형 — §7b 기계화).
2. **컴파일러-소유 AS_OF 조인**: forge 컴파일러가 리프 로드·조인·정렬을 AS_OF 규율로 **생성**한다 — 수기 merge 금지. 백테와 배포가 동일 컴파일 경로 (사고1·3 유형 — 사고3의 배포 코드 `Date<AS_OF`가 clean했던 반사실이 근거).
   - **2-a 리프 행 라벨 = 소스가 보고한 as-of (합성 금지)** — 2026-08-02 신설, 실사고 회수. provider 는 리프 행의 `Date`(=avail_ts 기준)를 **요청한 sig_date 나 캘린더 규칙으로 만들어내지 않고**, 접근자가 보고한 실제 vintage 를 쓴다. `factor_db_monthly` 정본 = `load_month_factors()` 의 `attr(, "factor_db_asof_date")`(월 파일 Date 컬럼 = 거래일 월말). 미보고 시 **하드 중단**(요청일로 되돌리는 폴백 금지 — 그 폴백이 곧 결함이었다).
     - 원 결함: provider 가 캘린더 월말(각 월 1일−1)로 라벨했는데 eval 그리드는 거래일 월말이라, 거래말<캘린더말 인 **94/259 월(36.3%, 2004-12~2026-06)** 에서 AS_OF 조인이 전월 값을 당겼다 — 1개월 stale(lag 방향이라 look-ahead 아님, **측정 감쇠**). 소비자: WT_D20260802_004(6리프 전량)·006(WT-004 패널 재사용 진단).
     - **은폐 기전 = 검사가 결함과 같은 좌표계**: `tests/parity_factor_db.R` 의 EVAL_DATES 가 캘린더 월말 하드코딩이라 결함이 상쇄돼 rho=1.0 이 나왔다. 상설 검사(`08_Tests/contract_regression/test_ast_monthly_asof_label.R`)는 eval 그리드를 factor DB 와 **무관한** RAWDATA 거래일에서 만들고, 구판 라벨을 되돌리는 돌연변이 축으로 검출력을 매 실행 실증한다.
3. **𝒪 표현공간 한정**: LEAD 부재 + 부호 없는 명시적 lag (사고4 유형 문법 제거).

**verify() 알고리즘 = 원안 v1.0 §4 그대로 채택** (리프 avail_ts 상향 전파, TS_LAG 완화·롤링 최신관측 구속·AS_OF resolve). 판정 3종: `PASS` / `FAIL_LOOKAHEAD`(alpha 반려, forge 사이클 0 소비) / `WARN_RESTATEMENT`(통과 + 스펙 플래그 → judge·governor 입력).

**동적 검정 병행 유지 (HARD 원칙)**: judge 경험적 PIT 검증·lag1 스트레스·strict A/B·vintage-swap·validate_label_direction은 **대체 불가** — 실사고 4건 전부 표준 통계검증을 통과하고 동적 도구로만 검거된 실측. 정적 PASS ∧ 동적 위반 징후 = **리프 메타 버그** → `06_Registry/ast_leaf_table_bugs.jsonl` 큐 적립 (인프라 버그 리포트, 전략 문제 아님).

## §5 Phase 2 — 구조특징 로깅 (적립은 즉시, 분석은 N≥30)

> **★ 개정 (2026-08-02, Q-Lead 야간 라운드 — M4 전제 실측 반증 + 배선점 확장)**
> 아래 원문의 "essence_score() 단독 배선점 = 전 graduation 판정 경유라 capture 구조 보장"은 **실측으로 반증됐다**. 8일간 무증상이었고 정기 검사도 통과했으나 **실전 레코드가 0건**이었다.
> - **실측 (2026-08-02 01:5x~02:2x)**: `06_Registry/ast_structure_log.jsonl` 399행 중 `ast_features` non-null **0** / `strategy_id` non-null **0**. 21행씩 동일-분 클러스터이며 2026-07-27·08-01 두 블록의 값 시퀀스가 **완전 동일** = 테스트 배터리 반복 산물. 실전 캡처 **0건**.
> - **원인 1 (설계)**: `02_Infrastructure/alpha_search/run_alpha_search.R:330` 권위측정 사다리 — `if (grade %in% c("A","A_NOVEL","A_DEF","B","B_DEF") || screen_remeasure)` 일 때만 `.authoritative_remeasure()` → `essence_score()` 를 호출한다. 즉 essence_score 는 **proxy hurdle 사다리를 통과한 소수만** 경유한다. 2026-07-27 alpha-search 3라운드는 grade F/C·`screen_pass=FALSE` 라 사다리를 생략했고 기록이 남지 않았다. 이는 본 절이 명문으로 요구한 **"governor 거절분 포함 전량 로깅(생존편향 방지)"의 정반대** 구조다 — 생존자만 남는다.
> - **원인 2 (커버리지)**: `canonical_screen_bt()` 는 essence_score 를 호출하지 않는다(주석 언급뿐). alpha 스크리닝 1급 지표 PORT_t 가 나오는 경로가 사이드카 미도달이었다.
> - **원인 3 (호출측)**: main 저장소 `essence_score()` 호출자 **35곳 전수**가 `ast_features`/`strategy_id` 를 전달하지 않았다(시그니처만 존재).
> - **원인 4 (트리 분기)**: worktree 6개 중 5개의 `essence_score.R` 이 사이드카 없는 구판.
> - **위험**: 이 상태로 Step 5 에 진입하면 `N=399 ≥ 30` 으로 오판해 **합성 데이터로 complexity_prior 를 추정**하고 그 숫자를 alpha 프롬프트에 주입하게 된다(AX-002 급).
>
> **수리 (2026-08-02)**:
> 1. 단일 writer 신설 `02_Infrastructure/contracts/ast_sidecar.R` — `ast_sidecar_log(lane, strategy_id, ast_features, metrics, extra)`.
> 2. **배선점 확장**: `lane="essence"`(essence_score) + `lane="canonical_screen"`(canonical_screen_bt 반환 직전). 후자는 **기각분이 반드시 지나는 지점**이라 생존편향 요건을 실제로 만족한다.
> 3. **실전/테스트 분리**: `run_context` 필드(기본 `live`, 배터리는 `QVEST_RUN_CONTEXT=test`) + `schema="ast_structure_log_v2"` 태그. 정직 카운터 `ast_sidecar_status()` 가 `live` / `live_with_ast` / `legacy_unlabeled` 를 분리 보고한다 — **Step 5 의 N 은 `live_with_ast` 로 센다.**
> 4. **침묵 실패 제거**: 구판은 `try(silent=TRUE)` + `dir.exists()` 조건이라 실패가 무흔적이었다. 신판은 stderr WARN + `06_Registry/.ast_sidecar_failures.log` 에 남긴다.
> 5. **루트 resolver marker 검증**: `CLAUDE.md` + `06_Registry` 동시 존재로 검증(경로 정규화 선행). 존재검사로 정체성검사를 대체하지 않는다.
> 6. **강제**: `08_Tests/contract_regression/test_ast_sidecar.R` — 양성 대조 + 위반 주입 **24/24 PASS**(가짜 루트 기각·기각분 포착·구판 행 live 미계상·음성 통제 포함).
>
> **개정 후 정직 실측**: `total=401 · live=0 · live_with_ast=0 · legacy_unlabeled=399`. **실전 표본은 0에서 다시 시작한다** — 구판 399행은 `schema` 필드 부재로 자동 배제되며 원장은 무변경 보존(append-only 원칙).
> **잔여**: run_alpha_search 사다리 자체는 비용 절약 설계라 유지하되, 스크리닝 lane 배선으로 커버리지를 확보했다. 부팅 상태라인 노출(재발 감지)은 후속.

**배선점 (원문 — 2026-08-02 개정으로 확장됨)**: `essence_score()` 내부 append-only 사이드카 `06_Registry/ast_structure_log.jsonl` (~~전 graduation 판정 경유라 capture 구조 보장~~ → **반증됨, 위 개정 참조**. oos_retention_splits 유실 해소 효과는 유효):

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
Step 2 ✅ 완료 (2026-07-25 — wf_1c333719 S2a/S2b):
        · schema.json alpha_package v1.1 conditional(3층+escape 계약, 구식 하위호환 — 실물 183건 회귀 0,
          픽스처 11/11) + alpha_research_init.md v1.4 <ast_spec_v1_1> + qvest-worktask §3 계약 반영
        · 02_Infrastructure/ast/ 신설: operator_library.json(𝒪 28연산자+escape 4종, LEAD 부재)
          + ast_compile.R(리프 로드·AS_OF 조인 컴파일러-소유, ast_features manifest 산출 — 테스트 81/81)
Step 3 ✅ 완료 (2026-07-25 — S2c/S2d):
        · ast_verify.py 정적검증기(승격 registry+리프 맵 이중 소스, 상향 전파, 픽스처 5/5+적대엣지 8종
          — 실사고2 동월 vintage 형상 FAIL_LOOKAHEAD 검거 실증)
        · ast_spec_gate.sh 라우터 등재(dispatch 17, 3의무 준수) + hook_e2e_battery 15/15 PASS
        · parity(신규 컴파일러 vs factor DB): M01 rank corr ~0.95-0.97·M04 ~1.0(ic_sign 부호)·V01 1.0
        · 𝒪 확장 규율 첫 가동: BL-001(fundamental 리프 소스 부재) → 06_Registry/ast_operator_backlog.json
        ─── 손익분기 도달 (§4 3중 예방 + verify() + 게이트 실배선) ───
Step 4 ⚠️ 배선 완료 but **실전 캡처 0** (2026-07-25 배선 → 2026-08-02 결함 적발·수리).
        ★ 8일간 무증상·정기검사 통과 상태로 실전 레코드 0건이었다(399행 전부 테스트 배터리).
          근본 = essence_score 가 proxy 사다리 통과분만 경유(생존편향) + canonical_screen 미배선
          + 호출자 35곳 전수 인자 미전달 + worktree 5/6 구판. 상세·수리 = §5 개정 절.
          수리 후 정직 실측 live_with_ast=0 → **Step 5 의 N 은 여기서부터 다시 쌓인다.**
        (원 배선 내용) essence_score()에 ast_features/strategy_id/active_regime 인자 +
        06_Registry/ast_structure_log.jsonl append-only 사이드카 — 채점 무관여(양 모드 identical 실증)·
        fail-soft·비-AST 산출도 전량 로깅(ast_features null = escape 커버리지 표식, 생존편향 방지).
        judge/governor verdict는 strategy_id 사후 조인. **분석은 N≥30부터** (§5 규율 불변)
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
