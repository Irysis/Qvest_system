# 사전등록 — FQ-233 Lane A / arm C (꼬리초과확률·왜도 표적)

**발행 2026-08-20, 측정 실행 전 고정.** round_id `FQ233_ARMC_20260820`. 발행자 Q-Lead session 8a45d0cf.
전제: arm A 관문 통과(REPRODUCED, total net SR 0.6039 · 198개월) + arm B 완료(NOT_SUPPORTED, paired NW3 t −1.25).

## 0. 질문

**표적을 평균 → 꼬리초과확률(비대칭의 확률 표현)로 바꾸는 것만으로 신호력·실현 성과가 개선되는가.**
피처·유니버스·비용·워크포워드·종목수·하이퍼파라미터는 arm A/B 와 **완전 동일**, **표적만** 바꾼다.
arm B 가 "분위 점예측(q50)" 로 물었고 미지지였다 — arm C 는 분포의 **꼬리 비대칭을 확률로** 묻는다
(R32 기전 실측 cor(왜도기울기, 중앙값−평균 gap) = −0.728 의 소비 가능형 시험).

## 1. 고정 사양 (arm A/B 와 동일 — 변경 항목은 §2 뿐)

패널 `lane_a_feature_panel.parquet` · 피처 324종 · 확장창 워크포워드 burn-in 60개월 ·
결측 월내 횡단면 중앙값 대체 · top-25 EW long-only · 15bps one-way · liq 2e8 ·
`canonical_screen_bt()` 측정 · 벤치 일별→월간 `apply.monthly`+`Return.cumulative` 후 ym 키 조인.
하이퍼파라미터 = arm B 와 동일 고정 (`n_estimators=300, learning_rate=0.05, num_leaves=15,
min_child_samples=50, subsample=0.8, subsample_freq=1, colsample_bytree=0.8, reg_lambda=1.0,
random_state=0`) · **HPO 미수행**.

## 2. 바꾸는 것 = 표적뿐

- 라벨 (학습월 t 의 forward 월 수익 y, 월내 횡단면 기준):
  `y_up = 1[y > q90_cs(월)]` · `y_dn = 1[y < q10_cs(월)]` (q10/q90 = 해당 월 횡단면 분위 — 라벨 구성이며
  워크포워드 학습창 안에서만 소비되므로 PIT 무결).
- LightGBM `objective="binary"` 2모델(up/dn), 동일 고정 파라미터.
- ★**primary 스코어 = `P_up − P_dn`** (꼬리초과확률 스프레드) — 측정 전 고정.

## 3. secondary (기록 전용 — primary 교체 금지)

- **Bowley 왜도** `(q90+q10−2·q50)/(q90−q10)` — arm B 가 이미 산출한 분위 예측 3종에서 **추가 학습 0회**로
  파생. arm B 예측 파일이 종목-월 단위로 보존돼 있지 않으면 정직하게 `unavailable` 기록(재학습 금지 —
  재학습하면 자유도가 늘어 arm 간 대조가 깨진다).
- 진단 병기: CRPS(properscoring, q10/50/90 예측 대비 실현 — 채점 진단), diag rank-IC.

## 4. 판정 (측정 전 고정 — arm B §4 와 동일 규약)

**primary 검정** = arm C 월간 net 수익 − arm A 월간 net 수익의 **paired NW lag-3 t** (동월 정렬).

| 결과 | 판정 |
|---|---|
| paired t ≥ +2.0 | 꼬리확률 표적 개선 지지 |
| \|paired t\| < 2.0 | 개선 미지지 |
| paired t ≤ −2.0 | 꼬리확률 표적 열등 (정보성 negative) |

병기 의무: 양 arm total net SR · canonical PORT_t · MDD · Calmar · 회전율 · diag rank-IC.
★basis 명시 — 1급 비교 축 = **total net SR + paired 월간 net**. 계약 `net_sr`(=active IR)과 혼용 금지.

## 5. selection_type = `chain`

하이퍼파라미터 사전 고정 · HPO 없음 · primary 단일 고정(P_up−P_dn) · argmax 선택 없음
⇒ DSR HARD 부적용, DSR 수치는 산출·기록(진단). **재분류 조건**: 파라미터 변경 재백테, 또는
up/dn/스프레드 변형 중 성과를 보고 primary 를 고르는 순간 sweep + DSR ≥ 0.5 HARD.
본 선언은 arm C 에만 적용(arm A/B 선언 승계 불가·불승계).

## 6. 인접 라운드 경계 (중복 방지 — Step 0 lookup 실측)

- **WT-D20260813_001** (in-flight, SPEC_APPROVED): "상방 분위 q90 **점예측** 표적" — 그쪽 소관.
  본 라운드는 **확률 스프레드** 표적이며 q90 점예측을 primary 로 삼지 않는다(arm B §3 금지의 승계).
- wt002_regime_tail_target: MECHANISM_GATE_FAIL (국면-조건부 꼬리 — 층이 다름, 본 라운드는 무조건부).

## 7. 주장하지 않는 것

자본 자격 아님 — arm A 가 MDD 64% 대조군. 개선이 나와도 '표적 형태 효과'의 증거이지 편입 후보가
아니다. graduation HARD 3종 별도. 4-arm 서열 관찰(armB striking_pattern)에 arm C 를 추가하는 것은
서술 갱신이지 검정이 아니다(n=5 비독립 — 동일 caution 승계).
