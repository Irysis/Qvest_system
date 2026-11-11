# P1S01_standing_qualification 사전등록 초안 v1 (P1_RETURN)

- 코어 v1 · 매니페스트 e70ac0af · 사양 md5 52d8eecc · τ_D 2022-12-31

## 목적 · 가설

P1 엔진 자격 규칙(P1R01 승계)을 프로그램 단위로 한 번 사전등록한다(도훈 10-20 'P1 상설 자격 등록' · L1-SPEED-LEVERS-20261020). 등록 뒤에는 충실구현 레인이 낸 엔진 가운데 롱온리로 쓸 수 있는 고정 방향 신호 엔진마다 표준 구성(P0R01 C0 형식 · 활성 측정 축)으로 라운드 의식 없이 자동 측정 · 판정한다. 시드 = P1R01 자격 엔진 E2 · E3 의 활성 epoch 같은 판본 재측정(같은 epoch 비교).

자격 = 보는 창 β-통제 t(α) ≥ tier_graduation 2.0 ∧ 보는 창 상승 포착 ≥ 0.55(P1R01 승계 · 위기별 하락노출 · 시험 창 α 는 보고 전용). 기대: 레인 엔진 대다수는 미달(수익 엔진은 드물다 — P1R01 · 1계층 1차 라운드 기록). 시드 E2 · E3 은 활성 epoch 에서도 자격 유지 예상 (같은 사양의 보는 창 결과를 본 상태 — 노출 고지). 판정은 엔진마다 독립 · 선택 없음(자격 목록 = P4 후보).

## 칸

| 칸 | 엔진 | 역할 | 사양 |
|---|---|---|---|
| P1S01_E2_C0 | E2 | reference | 04_Research/programs/P1_RETURN/P1S01_standing_qualification/specs/P1S01_E2_C0.json |
| P1S01_E3_RX0 | E3 | reference | 04_Research/programs/P1_RETURN/P1S01_standing_qualification/specs/P1S01_E3_RX0.json |

## 규칙(선언에서 생성 — 판정 코드와 같은 출처)

- 수익 엔진 자격 = [보는 창 β-통제 t(α): t_alpha_vis >= 2 (02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t · 미측정 = 미시험) ∧ 보는 창 상승 포착: uc_vis >= 0.55 (근거: 투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계) · 미측정 = 미시험)] 모두 (미측정 = 미시험)
- 시험 창 유지(사람 쪽 보고)(보고 전용 — 판정 아님): 'qualify' 참인 칸만 alpha_ann_test > 0 (근거: P1R01 rules.test_window 승계 — 자격 엔진만 · 판정 아님)

| 규칙 | 종류 | 지표 | 비교 | 값 | 출처 · 근거 | 미측정 |
|---|---|---|---|---|---|---|
| qualify | all_of |  |  |  |  | untested |
| · q_t_alpha | threshold | t_alpha_vis | >= | 2 | 02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t | untested |
| · q_uc | threshold | uc_vis | >= | 0.55 | 근거: 투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계) | untested |
| test_hold | report | alpha_ann_test | > | 0 | 근거: P1R01 rules.test_window 승계 — 자격 엔진만 · 판정 아님 | untested |

## 선택 규칙

{
  "rule": "none",
  "text": "선택 없음 — 자격 엔진 목록이 P4 수익 엔진 후보(P4 에서 고를 때 시행 수로 센다)"
}

## 노출(τ_D)

- Q 는 시험 창(2023~) 성과를 본 상태다 — 판정 규칙은 보는 창 열만 쓴다(코어 검사 rc_rules_test_window_use · 시험 창 α 는 보고 전용).
- Q 는 시드와 같은 사양(E2 · E3 × 활성 epoch — P2R03 · P2R04 RX0 칸)의 보는 창 결과를 본 상태다 — 규칙 · 문턱은 P1R01 승계로 고정(재량 없음).
- 레인 산출(재료 큐 인계 항목 · 충실도 감사 판정)을 본 상태다 — 입구 규칙은 성과 수치(인계 등급 · PORT_t · CR)를 읽지 않는다(시험 B6 · B7 음성 대조).
- 방향 층 정책(engine_native 만 허용)은 엔진 코드의 정적 특성(정본 커넥터 · 부호 층 사용)으로만 정했다 — 성과와 무관.
- (11-11 등록 전 고지) Q 는 11-10 v10.2 전수점검에서 이 계보(2002.06975) 저장 기록의 등급 분포(종합점수 · 근접 후보 · 시행 관문 — 전 기간 등급 포함)를 본 상태다 — 규칙 · 문턱은 P1R01 승계 그대로이고(재량 없음) 입구 규칙은 성과 수치를 읽지 않는다.
- (11-11 등록 전 고지) 입구의 방향 층 판정은 11-10 배선 감사(정적 코드 검사 · 설계 README §5-4 ④)에서 고쳐졌다 — 등록부 방향 상수(direction = "registry" | "defensive")로만 커넥터 · 결합용 뷰를 부르는 엔진 = factor_db_static(engine_native 허용 시 함께 허용) · 팩터 DB 수리 전 레인 측정은 입구에서 빼지 않고 표식(factor_db_vintage = stale)만 남긴다. Q 는 등록 전 입구 미리보기(scan --dry-run · 11-11 13:27 · 51 디렉터리 · 통과 1 — 사유 코드만 · 성과 수치 없음)를 본 상태이며, 미리보기 뒤 입구 규칙을 바꾸지 않았다.

## 결론 범위

- 자격 엔진 목록 = P4 수익 엔진 후보(활성 측정 축 · 같은 epoch 비교만). 자격 ≠ 권위 등급 · Judge · BOOK.
- 미달 = 표준 구성(롱온리 ≤25종 EW · 15bps · 활성 축)에서 이 규칙 미달 — 논문 기전 전체의 기각이 아니다(충실구현 등급은 레인 기록).
- 입구 제외(사유 코드) = 측정하지 않음 — 판정이 아니다. 정책이 바뀌면(새 판) 다시 볼 수 있다.
- 구 epoch(all_hyg_2000_v1) P1R01 판정은 그대로 남는다 — 활성 epoch 의 E2 · E3 자격은 P1S01 시드 판정으로 본다.

## 핀

- 파일 22 · 패키지 data.table 1.18.6.1 · jsonlite 2.0.0 · arrow 26.0.0 · PerformanceAnalytics 2.0.8 · bbdetection 1.0 · R version 4.6.2 (2026-10-29 ucrt)
