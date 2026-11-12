# P1S02_standing_qualification 상설 자격 규칙 — 판 2 (rc_standing_rules_md 가 사양에서 생성 · 손으로 고치지 않는다)

## 1. 판정 규칙(선언에서 생성 — 판정 코드와 같은 출처)

- 수익 엔진 자격 = [보는 창 β-통제 t(α): t_alpha_vis >= 2 (02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t · 미측정 = 미시험) ∧ 보는 창 상승 포착: uc_vis >= 0.55 (근거: 투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계) · 미측정 = 미시험)] 모두 (미측정 = 미시험)
- 시험 창 유지(사람 쪽 보고)(보고 전용 — 판정 아님): 'qualify' 참인 칸만 alpha_ann_test > 0 (근거: P1R01 rules.test_window 승계 — 자격 엔진만 · 판정 아님)

| 규칙 | 종류 | 지표 | 비교 | 값 | 출처 · 근거 | 미측정 |
|---|---|---|---|---|---|---|
| qualify | all_of |  |  |  |  | untested |
| · q_t_alpha | threshold | t_alpha_vis | >= | 2 | 02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t | untested |
| · q_uc | threshold | uc_vis | >= | 0.55 | 근거: 투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계) | untested |
| test_hold | report | alpha_ann_test | > | 0 | 근거: P1R01 rules.test_window 승계 — 자격 엔진만 · 판정 아님 | untested |

## 2. 처치 = 표준 구성(생성 함수 핀)

- 생성 함수 `rc_p1_cell_spec` md5 80f8311f3f61e6fd4e8fb5b250521f58 · 선례 `04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/P0R01_E2_C0.json` md5 080cfea84f6412c244e0eeecfda689de
- 정본 고정 축: 측정 축 all_hyg_px1000_2000_v1 · 종목 ≤ 25 · 비용 15 bps · 유동성 하한 200,000,000원 · 롱온리 TRUE
- 칸 사양은 등록 뒤 이 함수가 재량 없이 만들고, 측정 · 판정 직전 다시 만들어 md5 를 대조한다(다르면 그 항목 미시험 · r2_violation).

## 3. 레인 스캔 규칙(자격 큐 입구 — 성과 수치를 읽지 않는다)

- 원천: `04_Research/strategies/RP_AUTO_*` 디렉터리 × 등록부 인계 기록(kind = engine) · 인계 프로그램 = P1_RETURN · 허용 감사 판정 = faithful · adapted · 허용 방향 층 = engine_native · factor_db_static · 롱 레그 창 = visible(τ_D 2022-12-31 이전) · PIT 정적 검사 = 켬
- 방향 층: engine_native = 엔진 고유 특성(커넥터 부호를 쓰지 않음) · factor_db_static = 커넥터 · 결합용 뷰를 등록부 방향(`direction = "registry"` | `"defensive"` 문자열 상수)으로만 부름(engine_native 허용 시 함께 허용) · factor_db_asof = 정본 커넥터 `load_month_factors`/`load_daily_factors` · 결합용 뷰 `fc_load_month(s)`/`fc_daily` 를 방향 인자 없이 · `ic_asof` · 판정 불가 값으로 부름(as-of IC 부호) · orientation_layer = `align_factor_direction`/`compute_rolling_ic_all` 호출 또는 부호 층 식별자(R 파서 토큰 — 주석 · 문자열 제외)
- 한 디렉터리의 모든 실패 사유를 모은다. 통과 + 처음 보는 엔진(md5)만 인계 시각 순으로 넣는다. 같은 엔진은 판 사이에서도 다시 판정하지 않는다(새 판의 rejudge_prior_editions = true 일 때만).

| 사유 코드 | 제외 조건 |
|---|---|
| `no_engine` | engine.R 없음 또는 200바이트 미만(검증기 하한) |
| `no_handoff` | 레인 인계 기록 없음 — 등록부 재료 큐 · 소비 기록 · 미분류 보류에 kind = engine 항목이 없다(구판 · 검증 미완) |
| `not_routed` | 인계 프로그램 ≠ 이 판의 프로그램(라우터 v5 분류 — 다른 엔진 재료 · 미분류) |
| `combination` | 결합(combination) — 단일 논문 엔진이 아니다(결합은 P4 · 도훈 확인) |
| `audit_not_passed` | 충실도 감사 판정이 허용 목록 밖(인계 기록 · fidelity_audit.json 둘 다 본다) |
| `implementation_suspect` | 구현 의심(재구현 뒤 감사 기각 · 측정 뒤 보유 대조 어긋남) — 꼬리표 판독 불가도 제외 |
| `engine_changed_since_handoff` | 인계 뒤 엔진이 바뀌었다(인계 engine_md5 ≠ 지금 · md5 미기록이면 파일 시각 > 인계 시각 · 인계 시각 없음) |
| `engine_parse_failed` | 엔진 파싱 실패(정적 검사 불가) |
| `output_contract_unknown` | FACTORS · PORTFOLIO 대입을 찾지 못했다 |
| `portfolio_only_base` | 포트폴리오만 내는 엔진 — FACTORS 대입이 없다(정적 검사 · v3). 표준 구성은 점수로 상위 N 을 고르는데, 셀 경로는 비중을 점수로 읽게 된다(설계 §2-2 · §6-4) |
| `breadth_insufficient` | 후보 폭 부족 — 레인 점수 패널(factors_panel.parquet · Date · Ticker 만 읽는다)의 보는 창(τ_D 이전 — 세기 전에 자른다) 신호일 가운데 종목 수 ≥ 보유 상한(tier_soft_deployment.max_names) × 배수(측정 축 effective_start.breadth_mult)인 날이 없다(v3). ★필요조건일 뿐이다 — 레인 패널의 개수는 셀 필터(위생 · 유동성 · 동전주 · 그날 유니버스) 전 값이라 통과해도 셀에서 미달일 수 있다. 패널 없음 · 판독 불가 · 보는 창 날짜 0 이면 이 사유를 붙이지 않는다(측정의 실효 시작 규칙이 가른다) |
| `base_off_month_grid` | 주간 · 일간 신호 엔진 — 셀 경로는 월말 표본이 되므로 판정하지 않는다(측정 축: 주간 신호면 주간 리밸 · 셀 엔진 주간 신호 미구현). 판독 = 레인 점수 패널의 보는 창(τ_D 이전) 신호일 중 한 달력 월에 2개 이상인 달이 있다(v3 · 판단 Superfan T4 R-20261111-008 · 모수 없음 · 패널 판독 불가면 사유 없음) |
| `dynamic_sign` | 동적 부호 — 방향 층이 허용 목록 밖(factor_db_asof = 정본 커넥터 · 결합용 뷰의 as-of IC 부호(방향 인자 없음 · ic_asof · 판정 불가) · orientation_layer = 엔진이 부호 · IC 를 스스로 다룸 · factor_db_static(등록부 방향 registry · defensive)은 engine_native 를 허용하면 함께 허용) |
| `long_leg_absent` | 보는 창 신호일 중 롱 레그(비중 > 0)가 없는 날이 있다 — 시계열 방향 · 현금 타이밍 층(표준 구성이 그날 숏 대상을 사거나 비게 된다) |
| `long_leg_unverifiable` | 레인 측정 보유(04_holdings.csv)를 읽지 못해 롱 레그를 확인할 수 없다 |
| `pit_static` | PIT 정적 검사(lookahead_detector) 위반 또는 미스캔 |
| `paper_meta_missing` | 논문 url · 제목 · 키를 정하지 못했다 |

## 4. 항목마다 R2

- 판 단위: 사전등록 md5 = 등록부 · 사양 md5 = 등록본 · 생성 함수 핀 = 지금 · 판정 경로 핀(rc_pins_mismatches) — 하나라도 다르면 넣기 · 측정 · 판정을 멈춘다(새 판 등록).
- 항목 단위: 엔진 md5 · 칸 사양 md5 = 원장(넣을 때) · 시드 = 등록본 칸 md5 · 스캔 항목 = 생성 함수로 다시 만든 md5. 측정 중 데이터 지문이 바뀌면 그 측정은 쓰지 않는다(1회 재측정).
- 인프라 실패(측정 ok ≠ true · 지문 불일치 · 칸 평가 예외 · 판정 지표 계산 예외)는 판정이 아니다 — 다시 재거나 다시 평가하고, 2번째 실패면 사람이 본다(standing-status). R2 대조 실패는 그 항목만 멈춘다.
- 더 높은 판이 등록되면 옛 판은 새 항목을 받지 않는다(옛 판정 유지).

## 5. 원장 · 보고 · Superfan

- 원장 = 사전등록 정본 옆 `standing_ledger.jsonl`(추가 전용 · 줄마다 앞 줄 md5 사슬 · 보는 창 값만). 사람 쪽 판정 파일 = `results/standing/<code>.verdict.json`(시험 창 열 포함).
- 보고: 통과 = push_each · 미달 · 미시험 = daily_summary(qvest-telegram §0.1 단위 · §0.4 푸시).
- Superfan(규약 §11-1 · §12): 등록 = T1 · P1 1회 · 통과 = 즉시 T2 · P2 · 미달 = daily_batch.
