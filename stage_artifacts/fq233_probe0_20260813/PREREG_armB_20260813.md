# 사전등록 — FQ-233 Lane A / arm B (조건부 분위 표적)

**발행 2026-08-13, 측정 실행 전 고정.** round_id `FQ233_ARMB_20260813`. 발행자 Q-Lead session.
전제: arm A 관문 통과(`armA_result.json` REPRODUCED · total net SR 0.6039 · 198개월).

## 0. 질문

**표적을 평균 → 조건부 분위로 바꾸는 것만으로 신호력·실현 성과가 개선되는가.**
피처·유니버스·비용·워크포워드·종목수는 arm A 와 **완전 동일**하게 두고 **표적만** 바꾼다.

## 1. 고정 사양 (arm A 와 동일 — 변경 항목은 §2 뿐)

패널 `lane_a_feature_panel.parquet` · 피처 **324종**(중복 확정 alias 7종 드롭) ·
확장창 워크포워드 burn-in 60개월 · 결측은 월내 횡단면 중앙값 대체 ·
top-25 EW long-only · 15bps one-way · liq 2e8 · `canonical_screen_bt()` 측정 ·
벤치는 일별→월간 `apply.monthly`+`Return.cumulative` 후 **ym 키** 조인.

## 2. 바꾸는 것 = 표적뿐

- `lightgbm` `objective="quantile"`, `alpha ∈ {0.10, 0.50, 0.90}` — 분위 3종 각각 학습.
- **하이퍼파라미터 사전 고정 · HPO 미수행** (arm A 와 동일 규율):
  `n_estimators=300, learning_rate=0.05, num_leaves=15, min_child_samples=50,
   subsample=0.8, subsample_freq=1, colsample_bytree=0.8, reg_lambda=1.0, random_state=0`
  (`max_depth=4` 등가로 `num_leaves=15` 사용 — 트리 라이브러리 관례차이지 탐색 결과가 아니다.)

## 3. ★primary 스코어 = **q50 단독** (측정 전 고정)

`score = q50_pred`. 이유: arm A(평균)와의 **1요인 대조**를 유지해야 "표적 형태" 효과가 식별된다.
- **q10 / q90 은 secondary** — 산출·기록하되 **primary 를 이것으로 바꾸지 않는다.**
- ★q10·q90 을 섞는 결합(예: `q50 + λ(q90−q10)`)은 **본 라운드에서 금지** — λ 가 자유 파라미터라
  그 순간 sweep 이 되고 DSR 이 붙는다. 결합은 별도 사전등록 라운드에서.

## 4. 판정 (측정 전 고정)

**primary 검정** = arm B(q50) 월간 net 수익 − arm A 월간 net 수익의 **paired NW lag-3 t**
(동일 198개월 정렬, 짝 없는 달 제외).

| 결과 | 판정 |
|---|---|
| paired t ≥ **+2.0** | **분위 표적 개선 지지** |
| \|paired t\| < 2.0 | **개선 미지지** (= 표적 형태만으로는 안 움직인다) |
| paired t ≤ **−2.0** | **분위 표적 열등** (정보성 negative) |

병기 의무: 양 arm 의 total net SR · canonical PORT_t · MDD · Calmar · 회전율 · diag rank-IC.
★**basis 명시** — 1급 비교 축은 **total net SR** 과 **paired 월간 net 수익**이다.
계약의 `net_sr` 은 active SR(=IR)이므로 혼용 금지(arm A 에서 판정이 뒤집힐 뻔한 지점).

## 5. selection_type

**`chain`** — 하이퍼파라미터 사전 고정, HPO 없음, primary 단일 고정(q50), argmax 선택 없음.
⇒ DSR HARD 부적용, 단 **DSR 수치는 산출·기록**(진단).
★**재분류 조건**: 파라미터를 바꿔가며 백테를 돌리거나, q10/q50/q90 중 성과를 보고 primary 를 고르면
그 순간 **sweep** 이고 DSR ≥ 0.5 HARD 가 붙는다. arm A 의 chain 선언은 여기에 승계되지 않으며
본 선언은 arm B 에만 적용된다.

## 6. 주장하지 않는 것

자본 자격 아님. arm A 가 MDD 64% · PORT_t 0.63 인 대조군이므로, arm B 가 개선을 보여도
**그것은 '표적 형태 효과' 의 증거이지 편입 후보가 아니다.** graduation HARD 3종은 별도 문제.
