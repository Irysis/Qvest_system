# 사전등록 — FQ-233 Lane A / arm A (평균-표적 대조군 재현)

**발행 2026-08-13, 측정 실행 전 고정.** 이 문서 수정 = 사양 변경이며 그 사실을 명시해야 한다.
발행자 = Q-Lead session (/qvest 부팅 세션). round_id `FQ233_ARMA_20260813`.

## 0. 이 라운드가 답하는 질문 (딱 하나)

**수정 프레임에서 "평균-표적 ML" 이 기존 참조 대역 SR ≈ 0.49 를 재현하는가.**

재현이 목적이지 알파 발굴이 아니다. arm B/C(분포 표적)의 증분을 해석하려면 **비교 기준선**이 있어야 하고,
구 프레임 arm A(PORT_t 26.89 · Hit_Ratio 1.000)는 앵커 규약 오류 산물로 **무효**라 기준선이 지금 없다.

참조 대역 출처: `qvest_v8_4_asymmetry_ml_sot.md` §2 ③ — "XGBoost 로 종목별 다음 달 수익률 직접 예측"
SR **0.493** · "RF 종목 선정" 0.493 · "ML Factor Return Prediction" 0.464.

## 1. 데이터 (고정)

- 패널: `lane_a_feature_panel.parquet` (80,293 종목-월 · 259개월 2005-01~2026-08 · 331피처 · 표적 `fwd_ret_1m`)
- PIT: `load_month_factors()` + **`Z_Score_Aligned` 만**(C13/C15) · 팩터 Date **+1개월 스탬프**(앵커 규약)
  · forward = `build_monthly_forward_returns()` 정본 · 유니버스 K200∪KQ150(플래그 참, **ym 키**)
- **피처 = 324종** — `lane_a_panel_manifest.json` 이 실측한 **중복 확정 alias 7종 드롭**
  (V19_Debt_to_Market · M25_Earnings_Mom_Streak · M29_Mom_5d · C10_SUE_Persistence ·
   C13_Revision_Breadth_3m · R12_Idiosyncratic_Risk · CR04_Ownership_Concentration, 전부 cor>0.999).
  ★alias 선언이지만 상관이 낮은 4종(V20_SP 0.37 · XF_LL05_WorkingCapital 0.27 ·
  C09_Earnings_Surprise_Sq 0.89 · M27_Analyst_Rev_Mom 0.998)은 **유지**한다 — 별개 정보다.
- 결측: 월내 횡단면 중앙값 대체(0 아님 — z-score 패널이라 0 은 '평균' 이라는 정보를 주입한다).

## 2. 모델 (고정 — ★튜닝 없음)

- `xgboost.XGBRegressor` **하이퍼파라미터 사전 고정, HPO 미수행**:
  `n_estimators=300, max_depth=4, learning_rate=0.05, subsample=0.8, colsample_bytree=0.8,
   min_child_weight=10, reg_lambda=1.0, random_state=0, n_jobs=-1`
- 표적 = `fwd_ret_1m` **원값**(참조가 "다음 달 수익률 **직접** 예측" 이므로 변환하지 않는다).
- 워크포워드 = **확장창**. burn-in **60개월** → 첫 예측 61번째 달. 매월 재학습, 학습은 `sig_date < t` 만.
- ★**OOS 반복조회 금지** — 파라미터는 위에서 고정됐고 성과를 보고 되돌아가지 않는다.

## 3. 포트폴리오 · 측정 (고정)

- Python 은 **스코어까지만** 산출한다. 포트 수익률 손계산 금지(python-policy §4).
  → R `canonical_screen_bt()` 가 top-25 EW long-only · 15bps one-way · 유동성 2e8 로 실측.
- 1급 결과량 = **net SR(연율)** (참조 대역과 같은 축). 병기 = canonical **PORT_t** · MDD · Calmar · 회전율.
- `metric_type` = `canonical_screen`.

## 4. 판정 기준 (★측정 전 고정)

| 결과 | 판정 | 다음 |
|---|---|---|
| net SR ∈ **[0.30, 0.70]** | **재현 성립** | arm B/C 착수 — 증분 해석 가능 |
| net SR < 0.30 | 재현 실패(하방) | arm B/C 미착수. 기전 규명 우선 |
| net SR > 0.70 | 재현 실패(상방) | ★**누출 의심 우선 점검**(구 프레임 26.89 의 전례) |

밴드 근거: 참조 3건이 0.464~0.493 에 몰려 있고, 프레임·유니버스·기간이 완전히 같지 않으므로
점추정 일치를 요구하지 않는다. ±0.2 는 재현으로 읽을 수 있는 최대 폭으로 잡았다(사후 이동 금지).

**상방 실패 시 의무 점검 3종**: ①lag1 스트레스(신호 1개월 지연 시 붕괴하면 누출) ②학습창에 미래 월이
섞였는지 인덱스 감사 ③`Hit_Ratio` — 1.000 에 근접하면 즉시 중단(구 프레임의 지문).

## 5. selection_type 선언

**`chain`** — 근거: ①하이퍼파라미터를 사전 고정하고 **HPO 를 돌리지 않는다** ②열거된 후보 집합에서
argmax 로 최종안을 고르지 않는다(단일 사양 1회 측정) ③판정은 사전 고정 밴드와의 대조이지 최댓값 선택이 아니다.
- ⇒ **DSR HARD 게이트 부적용**(measurement-graduation §3 selection operator 경계).
- 단 **DSR 수치는 산출·기록**한다(게이트 아님, 진단용).
- ★**재분류 조건**: 이후 어떤 이유로든 파라미터를 바꿔가며 백테를 돌리면 그 순간 **sweep** 이고
  DSR ≥ 0.5 HARD 가 붙는다. "파라미터 수가 적다" 는 chain 근거가 아니다 —
  판별 질문은 **"이 값 바꿔가며 백테를 돌려봤나"** 다.
- ⚠이 선언은 구 `prereg_stance`(sweep+DSR 기본값)를 **arm A 에 한해** 대체한다. arm B/C 가 pinball
  하이퍼파라미터를 탐색하면 그쪽은 sweep 으로 재선언해야 한다.

## 6. 이 라운드가 주장하지 않는 것

- 자본 자격 주장 아님. arm A 는 **대조군**이고 graduation HARD 3종을 목표로 하지 않는다.
- R31~R33 의 패널 통계(중앙값 스프레드 등)와 **같은 문장에 놓지 않는다** — 저쪽은 분위 통계, 이쪽은 실현 포트.
