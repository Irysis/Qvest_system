# P1R04_combiner_t1_icw 사전등록 초안 v1 (P1_RETURN)

- 코어 v3 · 매니페스트 4d00113a · 사양 md5 b53c6c89 · τ_D 2022-12-31

## 목적 · 가설

팩터 척추 2단계 첫 결합기 — 결합기 T1(as-of IC 가중 · 설계 §4-2)을 P1R03 과 같은 구성원 · 같은 표준 구성(롱온리 25종 등가중 · 15bps · 유동성 2e8 · 현 측정 축)으로 재 수익 엔진 자격을 판정한다. 가족 14(가족 안 구성원 as-of ICIR⁺ 가중) + 토탈 1(가족 균형 as-of ICIR⁺ 가중)

같은 구성원 · 같은 가족 · 같은 표준 구성에서 결합 가중만 등가중(T0 · P1R03)에서 그 시점까지의 ICIR⁺ 가중(T1 — 팩터 가중 = max(s_reg × ICIR, 0) · ICIR = 정본 접근자 compute_rolling_ic_all(as-of, 36, 120) · 토탈은 가족 평균 가중으로 가족 균형)으로 바꾸면, 보는 창 자격 규칙(β-통제 t(α) ≥ 2 ∧ 상승 포착 ≥ 0.55)을 통과하는 서로 다른 원천이 T0 의 5개(P1R03 보는 창 판정 — 컨센서스 · 쏠림 · 성장 · 밸류 · 저위험 묶음)보다 늘어나거나, 같은 계보 짝(T1 − T0)의 보는 창 t(α) 가 과반 계보(8/15 이상)에서 오른다. 반증 = T1 자격 원천 수 ≤ 5 ∧ 보는 창 t(α) 가 T0 보다 높은 계보 < 8/15 이면 '선형 as-of ICIR⁺ 가중' 수준의 결합 개선 가설이 반증된다(결합기 사다리 전체의 반증 아님 — 다음 = T2 횡단면 회귀 · T4 상태 조건부).

## 칸

| 칸 | 엔진 | 역할 | 사양 |
|---|---|---|---|
| P1R04_IQUAL_C0 | IQUAL | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IQUAL_C0.json |
| P1R04_IDEFE_C0 | IDEFE | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IDEFE_C0.json |
| P1R04_ILIQU_C0 | ILIQU | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_ILIQU_C0.json |
| P1R04_IMOME_C0 | IMOME | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IMOME_C0.json |
| P1R04_IACCR_C0 | IACCR | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IACCR_C0.json |
| P1R04_IVALU_C0 | IVALU | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IVALU_C0.json |
| P1R04_IGROW_C0 | IGROW | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IGROW_C0.json |
| P1R04_IINVE_C0 | IINVE | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IINVE_C0.json |
| P1R04_IRISK_C0 | IRISK | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IRISK_C0.json |
| P1R04_ICROW_C0 | ICROW | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_ICROW_C0.json |
| P1R04_ICONS_C0 | ICONS | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_ICONS_C0.json |
| P1R04_ITECH_C0 | ITECH | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_ITECH_C0.json |
| P1R04_IREGI_C0 | IREGI | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_IREGI_C0.json |
| P1R04_ILEVE_C0 | ILEVE | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_ILEVE_C0.json |
| P1R04_ITOTAL_C0 | ITOTAL | variant | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_ITOTAL_C0.json |

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

- Q 는 시험 창(2023~) 성과를 본 상태다(다른 엔진 · 레인 기록) — 판정 규칙은 보는 창 열만 쓴다(코어 검사). 이 15개 T1 엔진의 성과는 아무도 계산하지 않았다(동작 확인은 점수 범위 · 개수만).
- Q 는 P1R03 의 보는 창 판정(results/evaluation_visible.json — 보는 창 전용 파일)을 본 뒤 이 라운드를 등록한다. T1 규칙(가중 = max(s_reg × ICIR, 0) · IC 창 36~120개월 · 가족 균형 · 대체 규칙) · 구성원 · 엔진 15개는 그 파일이 생기기 전에 고정했다(생성기 fc_combiner_gen.R md5 6b2a6e45 · 엔진 선언 11-13 07:23~07:29 · P1R03 평가 연쇄 07:28~). 판정을 본 뒤 정한 것은 가설 문장의 비교 기준(T0 자격 원천 수 = P1R03 보는 창 판정)과 읽는 법의 다음 단계 문장뿐이다. P1R03 의 verdict.json · 시험 창 열은 열지 않았다.
- Q 는 시험 · 동작 확인에서 IC 에서 나온 진단 값(2001-01~06 · 2022-08~11 의 양의 가중 구성원 수 · 양의 가중 가족 수)을 봤다 — 정보 경계 이전 · 포트폴리오 성과 아님 · 규칙에 쓰지 않았다.
- Q 는 과거 음성 조회(02_Infrastructure/tools/hypothesis_index.R lookup ICIR · IC 가중 · ic_weight · 팩터 모멘텀)로 구 측정 축 기록의 제목 · 판정 표식을 봤다(예: '안정성 가중 — ICIR 이 높은 팩터에 가중 확대' FAIL · DIST-QPM-014 · DIST-QPM-038 icir_illusion) — 사실 기록이지 금지 목록이 아니다 · 규칙에 쓰지 않았다.
- IC 원장(.cache/factor_db/factor_ic_monthly.parquet)은 정보 경계 뒤 달의 IC 도 담는다 — 엔진은 신호일마다 그날까지 공개된 IC(Usable_Date ≤ as-of)만 쓴다(PIT · 절단 시험이 확인). 판정 규칙은 보는 창 열만 쓴다.
- 구성원 선언의 노출은 P1R03 사양 exposures 그대로다(구성원 규칙 = 등록부 정적 필드 · 등록부 방향의 출처 — 구성원 334 중 방향 근거 필드 143). T1 은 그 선언을 옮겼고 등록부를 다시 읽지 않았다.
- Q 우연 열람 1건(11-13 07:36) — P1R03 evaluation_visible.json(보는 창 전용이라 적힌 파일)의 표에 보고 규칙 열 test_hold(자격 칸의 시험 창 연 알파 > 0 여부 · 부호만)가 함께 실려 있어 출력에 보였다. 이 라운드의 규칙 · 엔진 · 구성원 · IC 창은 그 전에 고정했고(07:23~07:29), 가설 문장의 비교 기준은 보는 창 자격 수(원천 5)만 쓴다 — test_hold 는 어디에도 쓰지 않았다. 보는 창 파일에 시험 창 파생 열이 섞이는 것은 코어 판정 파일 쓰기의 결함 후보(코어 v4 범위 · 감독에 알림)다.

## 결론 범위

- 자격 = 수익 엔진 자격(보는 창 β-통제 t(α) ≥ 2 ∧ 보는 창 상승 포착 ≥ 0.55) · 자격 ≠ 권위 등급 · Judge · BOOK · 기저 풀 입구(상설 판 통과만 — 자체 사양 입구는 코어 다음 판 · 결정 D4 (a)).
- 미달 = 표준 구성(롱온리 ≤25종 EW · 15bps · 활성 축 · 월말 · 월간)에서 '선형 as-of ICIR⁺ 가중(T1)' 수준의 미달 — 결합기 사다리 전체 · 팩터 척추 전체의 반증이 아니다(다음 = T2 횡단면 회귀 · T4 상태 조건부 · T5 상위 꼬리).
- T1 의 뜻: 구성원 = P1R03 선언 그대로(334 · 정의상 별칭 3개만 뺐다) — 근사 중복 구성원도 그대로다. IC 가중은 근사 중복 묶음의 무게를 바꾸지만 없애지 않는다(ICIR 이 비슷한 중복은 함께 무게를 받는다). 가족을 넘는 같은 식 12쌍(P1R03 결론 범위)도 그대로다.
- IC 원장의 한계(설계 §9): IC = 전 종목 · 원값 · 1개월 지평 — 측정 축(위생 · 동전주 바닥 · 유동성) 위 IC 가 아니다(품질 문제 · PIT 문제 아님). 원장은 지금 판 팩터 DB(11-09~10 수리 뒤)로 계산한 IC 다 — 당시 판이 아니다(판본 문제 · 엔진 논리의 미래 참조 아님). 36개월 미만 팩터는 가중 0 이라 재무 · 컨센서스 · 수급 구성원은 2003~2005 전에는 빠진다 — 초기의 T1 은 가격 계열 쪽으로 더 기운다.
- 가족 엔진의 대체: 그 달 그 가족 구성원 가중이 모두 0 이면 등가중(T0 와 같은 값)으로 둔다 — 대체 달 수는 엔진 폴더 진단(fce_diag.csv · 정보 경계 이전 행만)에 남는다. 대체가 잦은 가족은 T1 ≈ T0 다. 토탈은 W_f = 0 인 가족을 뺀다(모두 0 인 달만 T0).
- 시행 회계(판단 T1 C-20261112-026 승계): 계보(가족 · 토탈)마다 T0(P1R03) 1 + T1(P1R04) 1 = 2(칸 n_family 2). 자격 판정은 보는 창 성과로 거르는 선택이므로, 이 두 라운드의 자격 엔진을 기저로 쓰는 사슬은 코어 v4 자체 사양 입구가 '원천 라운드의 전 칸(P1R03 15 + P1R04 15)을 사슬 시행 집합에 넣고 빠지면 등록 거부'를 갖춘 뒤에만 등록한다.
- 자격 = 수익 엔진 자격(보는 창 β-통제 알파 ∧ 강세 참여 하한 — 헌장 원칙 5 · 6 쪽). 위기 방어 · 꾸준함(헌장 §5 빈칸 18)은 판정하지 않는다 — 통과를 철학 적합으로 보고하지 않는다(위기 하락노출은 보고 열).
- 위기 하락노출(원장 · 보고)은 시장 대비 귀속 전 원값이다 — MC8 귀속 · 하락/상승 β 가 없다. 낮은 값은 β 축소 · 크기 · 숨은 현금에서도 나오므로 방어 근거로 쓰지 않는다.
- 추첨 행운은 해당 없음(결정론 엔진 · 학습 난수 없음). 소형주 착시(유동성 구간 귀속) · 크기 짝 선택 알파는 미측정이다. 기저 풀(코어)은 보는 창 상승 포착 중앙값만 읽는다 — 강세 구간별 참여 · 집중 · 숨은 현금은 재지 않는다.
- 통과 엔진마다 철학 P2 판독(방향 · 실패 형태 · 귀속)이 있어야 사슬 판이 그 기저를 받는다 — 코어 v4 자체 사양 입구는 기저 풀 사유 philosophy_unread 를 갖춰 출시한다(철학 P1 C-20261112-023 승계).
- 저위험 계열: IC 가중은 부호를 바꾸지 않는다(부호 = 등록부 기대수익 · 저위험 구성원 다수는 방어 부호와 같다 — defense 54/57 · risk 15/19 · regime 8/8 · liquidity 23/44). IDEFE · IRISK · IREGI 는 FDEFE · FRISK · FREGI 와 같이, 자격이 나와도 P4 기저 · 블렌딩 부품으로 올리기 전에 도훈 확인(철학 보류 C-20261112-021 승계). 자격 · 미달 모두 방어 증거가 아니다.
- 원천 수는 가족 수로 세지 않는다 — 토탈은 독립 원천이 아니고(가족 점수의 가중 평균) 저위험 4 가족(defense · risk · liquidity · regime)은 한 원천으로 센다(P1R03 과 같은 셈법).
- '값이 있는 구성원 가중 평균'은 유효 구성원이 적은 종목의 점수를 극단으로 밀 수 있다(소형주 · 희소 종목 쏠림 경로) — 양의 가중 구성원만 세면 T0 보다 그 경로가 넓어진다. 철학 P2 판독에서 보유 종목의 유효 구성원 수를 같은 날 전 종목 중앙값과 대조한다(P1R03 C-025 승계).
- 결합용 뷰 · IC 원장(엔진의 두 입력)은 칸 데이터 지문과 기저 캐시 키에 들어 있지 않다(코어 v3) — 측정 셸(tools/p1r04_measure.sh)이 측정 앞뒤로 두 입력의 지문을 대조하고 10분 안정을 기다린다. 바뀌면 보고하지 않고 재측정한다(results 의 P1R04 칸 파일 15개와 측정 시작 뒤 생긴 .cache/rf_base_signal 파일을 함께 치운 뒤 — DESIGN §8).
- 가족마다 양의 가중 구성원이 생기는 때가 달라 실효 시작(MC3 B안 — 신호 폭 ≥ 보유 × 2 첫 신호일)이 칸마다 다를 수 있고, 같은 계보의 T0 칸과도 다를 수 있다 — 칸 판정은 각 칸의 실효 시작 뒤 보는 창으로 읽는다. 아래 계보 짝 비교는 각 칸의 판정 지표(t_alpha_vis)를 그대로 쓰며, 창이 다르면 그 사실을 함께 적는다.
- P1R03 보는 창 판정(results/evaluation_visible.json · 11-13 07:35): 자격 8/15 — FCONS · FCROW · FDEFE · FGROW · FLIQU · FRISK · FVALU · TOTAL · 위 셈법의 서로 다른 원천 = 5(컨센서스 · 쏠림 · 성장 · 밸류 · 저위험 묶음[방어 · 위험 · 유동성]). 설계 §3-8 읽는 법의 '3개 이상' 가지 — 코어 v4 자체 사양 입구 → 블렌딩 사슬 · 결합기 사다리. 이 라운드는 그 가지의 결합기 사다리 1단(T1)이다.
- 읽는 법(측정 전 고정 · 두 라운드의 보는 창 판정 파일만 쓴다): ① 칸 자격 = 위 규칙 그대로 ② 원천 수 = P1R03 과 같은 셈법(토탈 제외 · 저위험 4 가족 = 한 원천)으로 T1 자격 원천을 센다 — T0 의 5 와 비교 ③ 계보 짝 = 같은 계보(가족 · 토탈) T1 칸과 T0 칸의 보는 창 t(α)(t_alpha_vis) 차이의 부호를 센다(15 짝 · 동률 = 개선 아님).
- 지지(반증 조건 밖) → T1 자격 엔진은 T0 자격 엔진과 함께 코어 v4 자체 사양 입구로 기저 풀 후보가 된다(시행 = 두 라운드 30칸) · 결합기 다음 단계 = T2 횡단면 회귀(가족 점수 14 · 차원 통제)로 T1 과 같은 짝 비교. 반증 → T1 엔진은 입구에 올리지 않는다(자격 칸이 있어도 '결합 개선' 근거로 쓰지 않는다) · 다음 = T2 회귀 · T4 상태 조건부 결합(as-of 조건부 IC) · 팩터 성적표 IC 층(설계 §5)으로 가족 안 분산을 본다.
- T0 에서 보는 창 알파가 음수였던 가족(투자자 수급 · 기술적)이 T1 에서 자격을 얻으면, 등록부 기대수익 방향과 as-of IC 방향이 어긋난 구성원이 그 가족을 끌어내렸다는 뜻이다 — 이 라운드는 부호를 뒤집지 않고(C13) 빼기만 하므로, 등록부 방향 재검토는 별도 과제(방향 정책 DIRECTION_POLICY.md 경로 · 성과 무참조 근거)로 남긴다.

## 핀

- 파일 76 · 패키지 data.table 1.18.6.1 · jsonlite 2.0.0 · arrow 26.0.0 · PerformanceAnalytics 2.0.8 · bbdetection 1.0 · R version 4.6.2 (2026-10-29 ucrt)
