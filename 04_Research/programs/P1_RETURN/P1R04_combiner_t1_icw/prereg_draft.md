# P1R04_combiner_t1_icw 사전등록 초안 v2 (P1_RETURN)

- 코어 v3 · 매니페스트 4d00113a · 사양 md5 61c599a9 · τ_D 2022-12-31

## 목적 · 가설

팩터 척추 2단계 첫 결합기 — 결합기 T1(as-of IC 가중 · 설계 §4-2)을 P1R03 과 같은 구성원 · 같은 표준 구성(롱온리 25종 등가중 · 15bps · 유동성 2e8 · 현 측정 축)으로 재 수익 엔진 자격을 판정한다. 카테고리 14(카테고리 안 구성원 as-of ICIR⁺ 가중) + 토탈 1(카테고리 균형 as-of ICIR⁺ 가중)

같은 구성원 · 같은 카테고리 · 같은 표준 구성에서 결합 가중만 등가중(T0)에서 그 시점까지의 ICIR⁺ 가중(T1 — 팩터 가중 = max(s_reg × ICIR, 0) · ICIR = 정본 접근자 compute_rolling_ic_all(as-of, 36, 120) · 토탈은 카테고리 평균 가중으로 카테고리 균형)으로 바꾸면, 같은 배치에서 다시 잰 T0 기준 칸보다 보는 창 β-통제 알파가 유의하게 오른다 — 계보(카테고리 14 + 토탈 1)마다 월 수익 차(T1 − T0 기준)의 β-통제 알파(코어 R 계약 rc_pair_alpha · 보는 창)의 증분 t 를 읽는다. 지지 = 증분 t ≥ 2(tier_graduation.grade_b_min_portfolio_alpha_t)인 계보가 2개 이상이거나 토탈 계보의 증분 t ≥ 2. 반증 = 둘 다 아니면 '선형 as-of ICIR⁺ 가중' 수준의 결합 개선 가설이 반증된다(결합기 사다리 전체의 반증 아님 — 다음 = T2 횡단면 회귀 · T4 상태 조건부).

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
| P1R04_FACCR_R0 | FACCR | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FACCR_R0.json |
| P1R04_FCONS_R0 | FCONS | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FCONS_R0.json |
| P1R04_FCROW_R0 | FCROW | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FCROW_R0.json |
| P1R04_FDEFE_R0 | FDEFE | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FDEFE_R0.json |
| P1R04_FGROW_R0 | FGROW | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FGROW_R0.json |
| P1R04_FINVE_R0 | FINVE | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FINVE_R0.json |
| P1R04_FLEVE_R0 | FLEVE | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FLEVE_R0.json |
| P1R04_FLIQU_R0 | FLIQU | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FLIQU_R0.json |
| P1R04_FMOME_R0 | FMOME | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FMOME_R0.json |
| P1R04_FQUAL_R0 | FQUAL | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FQUAL_R0.json |
| P1R04_FREGI_R0 | FREGI | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FREGI_R0.json |
| P1R04_FRISK_R0 | FRISK | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FRISK_R0.json |
| P1R04_FTECH_R0 | FTECH | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FTECH_R0.json |
| P1R04_FVALU_R0 | FVALU | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_FVALU_R0.json |
| P1R04_TOTAL_R0 | TOTAL | reference | 04_Research/programs/P1_RETURN/P1R04_combiner_t1_icw/specs/P1R04_TOTAL_R0.json |

## 규칙(선언에서 생성 — 판정 코드와 같은 출처)

- 수익 엔진 자격 = [보는 창 β-통제 t(α): t_alpha_vis >= 2 (02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t · 미측정 = 미시험) ∧ 보는 창 상승 포착: uc_vis >= 0.55 (근거: 투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계) · 미측정 = 미시험)] 모두 (미측정 = 미시험)

| 규칙 | 종류 | 지표 | 비교 | 값 | 출처 · 근거 | 미측정 |
|---|---|---|---|---|---|---|
| qualify | all_of |  |  |  |  | untested |
| · q_t_alpha | threshold | t_alpha_vis | >= | 2 | 02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t | untested |
| · q_uc | threshold | uc_vis | >= | 0.55 | 근거: 투자철학 헌장 — 강세 참여 ≥ 55%(P1R01 rules.qualify.uc_floor 승계) | untested |

## 선택 규칙

{
  "rule": "none",
  "text": "선택 없음 — 자격 엔진 목록이 P4 수익 엔진 후보(P4 에서 고를 때 시행 수로 센다)"
}

## 노출(τ_D)

- Q 는 시험 창(2023~) 성과를 본 상태다(다른 엔진 · 레인 기록) — 판정 규칙은 보는 창 열만 쓴다(코어 검사). 이 15개 T1 엔진의 성과는 아무도 계산하지 않았다(동작 확인은 점수 범위 · 개수만).
- Q 는 P1R03 의 보는 창 판정(results/evaluation_visible.json — 보는 창 전용 파일)을 본 뒤 이 라운드를 등록한다. T1 규칙(가중 = max(s_reg × ICIR, 0) · IC 창 36~120개월 · 카테고리 균형 · 대체 규칙) · 구성원 · 엔진 15개는 그 파일이 생기기 전에 고정했다(생성기 fc_combiner_gen.R md5 6b2a6e45 · 엔진 선언 11-13 07:23~07:29 · P1R03 평가 연쇄 07:28~). 판정을 본 뒤 정한 것은 가설 문장의 비교 기준(T0 자격 원천 수 = P1R03 보는 창 판정)과 읽는 법의 다음 단계 문장뿐이다. P1R03 의 verdict.json · 시험 창 열은 열지 않았다.
- Q 는 시험 · 동작 확인에서 IC 에서 나온 진단 값(2001-01~06 · 2022-08~11 의 양의 가중 구성원 수 · 양의 가중 카테고리 수)을 봤다 — 정보 경계 이전 · 포트폴리오 성과 아님 · 규칙에 쓰지 않았다.
- Q 는 과거 음성 조회(02_Infrastructure/tools/hypothesis_index.R lookup ICIR · IC 가중 · ic_weight · 팩터 모멘텀)로 구 측정 축 기록의 제목 · 판정 표식을 봤다(예: '안정성 가중 — ICIR 이 높은 팩터에 가중 확대' FAIL · DIST-QPM-014 · DIST-QPM-038 icir_illusion) — 사실 기록이지 금지 목록이 아니다 · 규칙에 쓰지 않았다.
- IC 원장(.cache/factor_db/factor_ic_monthly.parquet)은 정보 경계 뒤 달의 IC 도 담는다 — 엔진은 신호일마다 그날까지 공개된 IC(Usable_Date ≤ as-of)만 쓴다(PIT · 절단 시험이 확인). 판정 규칙은 보는 창 열만 쓴다.
- 구성원 선언의 노출은 P1R03 사양 exposures 그대로다(구성원 규칙 = 등록부 정적 필드 · 등록부 방향의 출처 — 구성원 334 중 방향 근거 필드 143). T1 은 그 선언을 옮겼고 등록부를 다시 읽지 않았다.
- Q 우연 열람 1건(11-13 07:36) — P1R03 evaluation_visible.json(보는 창 전용이라 적힌 파일)의 표에 보고 규칙 열 test_hold(자격 칸의 시험 창 연 알파 > 0 여부 · 부호만)가 함께 실려 있어 출력에 보였다. 이 라운드의 규칙 · 엔진 · 구성원 · IC 창은 그 전에 고정했고(07:23~07:29), 가설 문장의 비교 기준은 보는 창 자격 수(원천 5)만 쓴다 — test_hold 는 어디에도 쓰지 않았다. 보는 창 파일에 시험 창 파생 열이 섞이는 것은 코어 판정 파일 쓰기의 결함 후보(코어 v4 범위 · 감독에 알림)다.
- Q 는 등록 전 사이드카(tools/p1r04_lowrisk_share.R)를 스크래치 폴더로 한 번 돌려 꼬리표(유동성 · 기술적 · 토탈)를 봤다 — as-of IC 가중 몫(성과 아님 · 보는 창 달만)이고, 꼬리표 규칙은 그 전에 고정했다. 짝 읽기 도구는 P1R03 의 보는 창 진단 패킷으로 만든 가짜 짝 2개(FVALU↔FGROW · TOTAL↔FCROW — 비교 의미 없음)로 동작만 확인했고 그 값은 어디에도 쓰지 않았다.
- 판단 T1(R-20261113-001) · 철학 P1(R-20261113-004) · 격리 점검 v1 — 세 리뷰 모두 어떤 results 도 열지 않았다(각 리뷰의 정보 경계 선언).

## 결론 범위

- 자격 = 수익 엔진 자격(보는 창 β-통제 t(α) ≥ 2 ∧ 보는 창 상승 포착 ≥ 0.55) · 자격 ≠ 권위 등급 · Judge · BOOK · 기저 풀 입구(상설 판 통과만 — 자체 사양 입구는 코어 다음 판 · 결정 D4 (a)).
- 미달 = 표준 구성(롱온리 ≤25종 EW · 15bps · 활성 축 · 월말 · 월간)에서 '선형 as-of ICIR⁺ 가중(T1)' 수준의 미달 — 결합기 사다리 전체 · 팩터 척추 전체의 반증이 아니다(다음 = T2 횡단면 회귀 · T4 상태 조건부 · T5 상위 꼬리).
- T1 의 뜻: 구성원 = P1R03 선언 그대로(334 · 정의상 별칭 3개만 뺐다) — 근사 중복 구성원도 그대로다. IC 가중은 근사 중복 묶음의 무게를 바꾸지만 없애지 않는다(ICIR 이 비슷한 중복은 함께 무게를 받는다). 카테고리를 넘는 같은 식 12쌍(P1R03 결론 범위)도 그대로다.
- IC 원장의 한계(설계 §9): IC = 전 종목 · 원값 · 1개월 지평 — 측정 축(위생 · 동전주 바닥 · 유동성) 위 IC 가 아니다(품질 문제 · PIT 문제 아님). 원장은 지금 판 팩터 DB(11-09~10 수리 뒤)로 계산한 IC 다 — 당시 판이 아니다(판본 문제 · 엔진 논리의 미래 참조 아님). 36개월 미만 팩터는 가중 0 이라 재무 · 컨센서스 · 수급 구성원은 2003~2005 전에는 빠진다 — 초기의 T1 은 가격 계열 쪽으로 더 기운다.
- 카테고리 엔진의 대체: 그 달 그 카테고리 구성원 가중이 모두 0 이면 등가중(T0 와 같은 값)으로 둔다 — 대체 달 수는 엔진 폴더 진단(fce_diag.csv · 정보 경계 이전 행만)에 남는다. 대체가 잦은 카테고리는 T1 ≈ T0 다. 토탈은 W_f = 0 인 카테고리를 뺀다(모두 0 인 달만 T0).
- 시행 회계(판단 T1 C-20261112-026 승계): 계보(카테고리 · 토탈)마다 T0(P1R03) 1 + T1(P1R04) 1 = 2(칸 n_family 2). 자격 판정은 보는 창 성과로 거르는 선택이므로, 이 두 라운드의 자격 엔진을 기저로 쓰는 사슬은 코어 v4 자체 사양 입구가 '원천 라운드의 전 칸(P1R03 15 + P1R04 15)을 사슬 시행 집합에 넣고 빠지면 등록 거부'를 갖춘 뒤에만 등록한다.
- 자격 = 수익 엔진 자격(보는 창 β-통제 알파 ∧ 강세 참여 하한 — 헌장 원칙 5 · 6 쪽). 위기 방어 · 꾸준함(헌장 §5 빈칸 18)은 판정하지 않는다 — 통과를 철학 적합으로 보고하지 않는다(위기 하락노출은 보고 열).
- 위기 하락노출(원장 · 보고)은 시장 대비 귀속 전 원값이다 — MC8 귀속 · 하락/상승 β 가 없다. 낮은 값은 β 축소 · 크기 · 숨은 현금에서도 나오므로 방어 근거로 쓰지 않는다.
- 추첨 행운은 해당 없음(결정론 엔진 · 학습 난수 없음). 소형주 착시(유동성 구간 귀속) · 크기 짝 선택 알파는 미측정이다. 기저 풀(코어)은 보는 창 상승 포착 중앙값만 읽는다 — 강세 구간별 참여 · 집중 · 숨은 현금은 재지 않는다.
- 통과 엔진마다 철학 P2 판독(방향 · 실패 형태 · 귀속)이 있어야 사슬 판이 그 기저를 받는다 — 코어 v4 자체 사양 입구는 기저 풀 사유 philosophy_unread 를 갖춰 출시한다(철학 P1 C-20261112-023 승계).
- 원천 수는 카테고리 수로 세지 않는다 — 토탈은 독립 원천이 아니고(카테고리 점수의 가중 평균) 저위험 4 카테고리(defense · risk · liquidity · regime)은 한 원천으로 센다(P1R03 과 같은 셈법).
- '값이 있는 구성원 가중 평균'은 유효 구성원이 적은 종목의 점수를 극단으로 밀 수 있다(소형주 · 희소 종목 쏠림 경로) — 양의 가중 구성원만 세면 T0 보다 그 경로가 넓어진다. 철학 P2 판독에서 보유 종목의 유효 구성원 수를 같은 날 전 종목 중앙값과 대조한다(P1R03 C-025 승계).
- P1R03 보는 창 판정(results/evaluation_visible.json · 11-13 07:35 · 보고 열 test_hold 는 읽지 않는다): 자격 8/15 — FCONS · FCROW · FDEFE · FGROW · FLIQU · FRISK · FVALU · TOTAL · 셈법의 서로 다른 원천 = 5(컨센서스 · 쏠림 · 성장 · 밸류 · 저위험 묶음[방어 · 위험 · 유동성]) → 등록된 읽는 법의 '3개 이상' 가지 = 코어 v4 자체 사양 입구 → 블렌딩 사슬.
- 이 라운드는 Q 재량의 앞당김이다(판단 T1 C-20261113-004 수용): 등록된 P1R03 읽는 법 문장에서 결합기 T1 앞당김은 '1~2개' 가지의 처방이고 '3개 이상' 가지에는 없다. 근거 = 설계 정본 §3-8 표의 '3개 이상' 행('풀 입구 → 블렌딩 사슬 1호 · 결합기 사다리') · T1 은 점수 패널 엔진이라 코어 v4 · 사슬과 의존이 없어 그 임계 경로(코어 v4 출시 → 자체 사양 판 측정 → 사슬 등록) 밖에서 나란히 잰다. 비용 = 계보마다 시행 +1(15) · CPU 약 90분(T1 15 + T0 기준 15) · LLM 0.
- 사슬 1호의 기저 · 블렌딩 부품은 지금 고정한다(판단 T1 C-20261113-004 수용 · 측정 전): P1R03 자격 엔진 가운데 저위험 보류 밖만 — 보류 = 방어 FDEFE · 위험 FRISK(철학 보류 C-20261112-021) + P1R03 철학 P2 판독이 더하는 엔진(저β · 강세 공백 — 철학 P1 C-20261113-034 가 짚은 병렬 P2 판독 · 도훈 확인 전). 이 라운드의 T1 엔진(자격이 나와도)은 사슬 1호의 기저 · 부품이 아니다 — 사슬 2호부터이며, 그때 두 라운드의 전 칸(P1R03 15 + P1R04 T1 15)을 사슬 시행 집합에 넣는다. 그래서 사슬 1호의 원천 시행 집합은 P1R03 15 그대로다.
- T0 기준 칸 15(역할 reference · 코드 P1R04_<T0 엔진>_R0): P1R03 의 같은 칸(같은 엔진 · 같은 표준 구성)을 같은 배치에서 다시 잰다(판단 T1 C-20261113-001 수용 — P1R03 은 다른 자료 판에서 쟀다). 짝 비교의 기준일 뿐 새 시행이 아니고(n_family = P1R03 과 같은 1) 판정 대상도 아니다 — 기준 칸의 자격 표기는 보고 열로만 읽는다.
- 읽는 법(측정 전 고정 · 기계 판독 = tools/p1r04_pair_reading.R · 핀 · 보는 창 값만 출력): ① 칸 자격 = 위 규칙(변형 칸 = T1 만 셈) ② 계보 짝 = 계보마다 rc_pair_alpha(T1 칸 산출, 같은 배치 T0 기준 칸 산출, τ_D)$visible 의 증분 t(월 수익 차 · NW lag 3 · 겹치는 달만 — 칸마다 실효 시작이 달라도 맞다) ③ 판정 = 증분 t ≥ 문턱(tier_graduation.grade_b_min_portfolio_alpha_t)인 계보 ≥ 2 또는 토탈 계보 증분 t ≥ 문턱이면 지지 · 아니면 반증 · 짝이 하나라도 미측정이면 미시험 ④ 원천 수(서술) = P1R03 셈법으로 T1 자격 원천을 세되, 같은 배치 T0 기준에 없던 원천은 그 계보의 증분 t ≥ 문턱일 때만 'T1 이 연 원천'으로 센다(문턱 근처 칸이 잡음으로 넘는 것을 원천으로 세지 않는다 — 판단 T1 C-001) ⑤ 부호 셈(서술) = 증분 t > 0 인 계보 수.
- 지지 → T1 자격 엔진은 T0 자격 엔진과 함께 코어 v4 자체 사양 입구로 기저 풀 후보(사슬 2호부터 · 시행 = 두 라운드 30칸) · 결합기 다음 단계 = T2 횡단면 회귀(카테고리 점수 14 · 차원 통제)를 같은 짝 비교로. 반증 → T1 엔진은 '결합 개선' 근거로 쓰지 않는다(자격 칸이 있어도) · 다음 = T2 회귀 · T4 상태 조건부 결합(as-of 조건부 IC) · 팩터 성적표 IC 층(설계 §5)으로 카테고리 안 분산을 본다.
- T0 에서 보는 창 알파가 음수였던 카테고리(수급 · 기술적)가 T1 에서 짝 증분 t 문턱을 넘으면, 등록부 기대수익 방향과 as-of IC 방향이 어긋난 구성원이 그 카테고리를 끌어내렸다는 뜻이다 — 이 라운드는 부호를 뒤집지 않고(C13) 빼기만 하므로, 등록부 방향 재검토는 별도 과제(방향 정책 DIRECTION_POLICY.md 경로 · 성과 무참조 근거)로 남긴다.
- 결합기 입력의 저위험 4 카테고리(방어 · 위험 · 유동성 · 국면 — 원 세션 요청): T1 은 T0 와 같은 입력 집합을 쓴다(짝 비교를 위해 입력을 바꾸지 않는다 · 가중은 as-of IC 가 정한다). 철학 보류 C-20261112-021 의 대상은 저위험 카테고리 엔진을 P4 기저 · 블렌딩 부품으로 올리는 일이고 자격 심사는 막지 않는다 — IDEFE · IRISK · IREGI 는 FDEFE · FRISK · FREGI 와 같이 도훈 확인 전 P4 부품에서 뺀다. 토탈(TOTAL · ITOTAL)은 저위험 카테고리를 입력으로 품으므로, P4 부품으로 올릴 때 저위험 카테고리의 가중 몫(τ_D 이전 · 엔진 결정론 재계산)을 함께 보고하고 그 몫이 보류 범위에 드는지는 철학 P2 판독과 도훈 확인으로 정한다.
- T1 엔진의 기저 풀 입구(판단 T1 C-20261113-002 수용): T1 엔진은 IC 를 읽어 정적 방향 층이 orientation_layer 다 — 판 1 · 판 2 입구는 이 층을 동적 부호(dynamic_sign)로 뺀다. 코어 v4 자체 사양 입구는 orientation_layer 를 자체 사양 판에서만, '엔진 본문 = 생성기 산출(재생성 md5 대조)' ∧ '본문 실행 단정(부호 = 등록부 고정 · 가중 ≥ 0)'일 때 허용하고, 두 장치를 양성 대조(본문 1바이트 수정 → own_generator_mismatch · 음의 가중 돌연변이 → 실행 멈춤)로 확인한 뒤 출시한다. 출시 전이면 T1 엔진은 기저 풀에 들어가지 않는다.
- 이 라운드의 보는 창 판정 파일에는 보고 열 test_hold 가 없다(보고 전용 규칙 test_hold 를 이 라운드 규칙에서 뺐다 — 코어 v3 보는 창 파일이 '_test' 로 끝나는 열만 빼는 결함 · 판단 T1 C-20261113-003 · 원장 J-20261113-007). 사람 쪽 시험 창 α 는 verdict.json 에서 읽는다(감독 · 처방 레인 열람 금지 파일).
- 결합용 뷰는 칸 데이터 지문과 기저 캐시 키 밖이고, IC 원장은 칸 데이터 지문(fingerprint.sh equality — 크기 · 수정 시각) 안이지만 기저 캐시 키 밖이다(격리 점검 v1 R-1 정정) — 측정 셸(tools/p1r04_measure.sh)이 측정 앞뒤로 두 입력의 지문을 대조하고 10분 안정을 기다린다. 바뀌면 보고하지 않고 재측정한다(results 의 P1R04 칸 파일 30 과 측정 시작 뒤 생긴 .cache/rf_base_signal 파일을 함께 치운 뒤 — DESIGN §8).
- 칸마다 실효 시작(MC3 B안 — 신호 폭 ≥ 보유 × 2 첫 신호일)이 다를 수 있다 — 칸 판정은 각 칸의 실효 시작 뒤 보는 창으로 읽고, 칸 사이 비교(계보 짝)는 rc_pair_alpha 가 겹치는 달만 쓴다(P1R03 결론 범위 '칸 사이 비교는 겹치는 창으로만' 승계 · 철학 P1 N1).
- 초기 구간의 T1 은 IC 이력 36개월 조건 때문에 양의 가중 후보가 적다 — 2000-01~2003-01 방어 0(~2003-04) · 퀄리티 2/47 · 밸류 1/24 · 성장 2/21 · 컨센서스 0(~2004-05)(격리 점검 v1 R-2 재도출). 이 구간의 짝 차이는 'as-of IC 가중'과 '이력 부족 구성원 제외'가 섞인 값이다 — 카테고리 엔진은 가중이 모두 0 인 달을 T0 로 대체하므로 그 달의 짝 차이는 0 이다.
- 짝의 한쪽이라도 미측정 · 평가 실패면 그 짝은 셈에서 빠진다(지지 · 반증 어느 쪽에도 넣지 않는다). 지지는 측정된 짝만으로도 낼 수 있지만, 반증은 15 짝이 모두 측정됐을 때만 낸다 — 아니면 미시험(격리 점검 v1 R-4).
- 측정은 판 2(P1S02) 시드 판정 전이다(시드 감시 = 도훈 11-13 '더 미루고'로 중단) — 시드 판정에서 셀 경로 결함이 나오면 30칸을 다시 잰다(P1R03 결론 범위 승계 · 격리 점검 v1 R-6).
- T1 짝 개선이 상승 포착 손실(강세 상승 포착 중앙값 < T0 − (1 − 0.8)·|T0| · 헌장 §5 빈칸 4 (B) · 13 · 값 = round_core p4.R RC_P4_UC_SEG_KEEP) 또는 위기 악화(위기 하락노출 중앙값 > T0)와 함께 나오면 저변동 쪽 이동이지 결합 개선이 아니다 — 읽기 도구가 그런 짝을 셈에서 뺀다(철학 P1 C-20261113-026). 짝 기록(판정 아님): 강세 구간별 보존 비 · 깊은 위기 비악화 비 · 위기 하락노출 최악 · CDaR · β 를 T1 · T0 로 나란히.
- T1 에서 저위험 몫은 정적 비율이 아니라 as-of 무게다(철학 P1 C-20261113-027) — 사이드카 tools/p1r04_lowrisk_share.R(측정 뒤 짝 읽기 전 · 보는 창 as-of 달만 · 성과 무참조)가 카테고리별 방어 부호 가중 몫 · 유효 구성원 수 · 비저위험 카테고리의 저위험 쌍둥이(V19_Debt_to_Market · Q15_Debt_to_Equity · Q16_Debt_to_Assets · T14_HLRange) 가중 몫 · 토탈의 저위험 4 카테고리 몫을 기록하고, 몫 > T0 기준(개수 비율)인 보는 창 달 비율 > behavior_card.json::majority_share 이면 '저위험 쏠림' 꼬리표를 단다(유동성 · 비저위험 카테고리 · 토탈). 꼬리표 카테고리는 원천 셈에서 저위험 묶음에 넣는다.
- P4 기저 · 블렌딩 부품으로 올리기 전 도훈 확인 범위(철학 보류 C-20261112-021 · C-20261113-027): IDEFE · IRISK · IREGI · ILIQU · ICROW · ITOTAL(조건 없이) + 사이드카 '저위험 쏠림' 꼬리표가 붙은 카테고리 — 확인 묶음에 사이드카 기록을 붙인다. 자격 · 미달 모두 방어 증거가 아니다. 등록 · 측정 · 다른 엔진 흐름은 막지 않는다. 과거 음성: P2R04 방어 틸트 β 짝 0/8 · 같은 카테고리의 방어 방향판 = 같은 계보 시행 +1(P1R03 결론 범위 승계 · 철학 P1 N1).
- T1 의 가중은 측정 축 밖(전 종목 · 위생 · 동전주 바닥 · 유동성 필터 없는 순위 IC)에서 배운다 — 소형주 착시의 두 번째 경로(철학 P1 C-20261113-028). 짝 개선이 크기 성분(동일가중−시총가중 · 연환산) 증가 ∧ 선택 성분 감소와 함께 나오면 '크기 틸트 개선'이고 결합 개선으로 세지 않는다(읽기 도구 표식). 다음 결합기(T2 이후)도 측정 축 위 IC 가 생길 때까지 같은 한계를 적는다.
- 같은 카테고리의 T0 · T1 은 한 원천 · 한 계보다(헌장 빈칸 17 · 철학 P1 N2) — 블렌딩 사슬에서 둘을 섞는 것은 두 원천이 아니라 한 원천의 결합 가중 시행 둘이다. 쌍둥이 무게가 큰 카테고리 쌍은 원천 셈에서 함께 센다(사이드카 기록 · 자격 엔진 쌍 보유 겹침으로 확인).
- 기전 반대 가설(철학 P1 N3): 36~120개월 ICIR 의 양의 부분은 타이밍 신호라기보다 '오래 맞아 온 팩터'의 품질 가중에 가깝고(Ehsani & Linnainmaa 2022 의 주결과는 지난 1년 형성 창이다 · 긴 창 팩터 타이밍의 증거는 약하다 — Asness, Chandra, Ilmanen & Israel (2017) JPM 43(5)), 경기순응이라 위기 직전 · 반등 초입에 늦을 수 있다 — 짝 기록의 강세 구간 · 깊은 위기 비가 이것을 잰다.

## 핀

- 파일 124 · 패키지 data.table 1.18.6.1 · jsonlite 2.0.0 · arrow 26.0.0 · PerformanceAnalytics 2.0.8 · bbdetection 1.0 · R version 4.6.2 (2026-10-29 ucrt)
