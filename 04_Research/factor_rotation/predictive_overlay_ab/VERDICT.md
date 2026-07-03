# 예측 forecaster를 *책 현금 오버레이* 신호로 A/B — VERDICT

**날짜**: 2026-06-26 · **모드**: factor-rotation 측정 · **규율**: chain(DSR 미적용 — 가설주도 단일검증, 자본 admit 없음·측정만)
**하니스**: `02_Infrastructure/ops/auto_regime_overlay_ab.R` 함수 재사용 + `build_forecast_cat_exposure()` 1개 추가
**실행**: `weighted_screen_bt`(contract-grade, NW lag-3), 가중=strategy 고정·exposure 스칼라만 변경. 269개월(2004-02~2026-06) vs KOSPI200, 15bps.

---

## 결정적 답: 부분 YES (standalone) / NO (책에 추가)

| 비교 | abs_SR | calmar | PORT_t | 판정 |
|---|---|---|---|---|
| **① fc_cat vs uni_cat** (예측 vs 동행, 동일 스케줄=순수 신호효과) | +0.045 | +0.176 | +0.175 | **예측 > 동행 ✓ (3/3)** |
| **② fc_cat_x_book vs book_L5** (예측이 현 책 오버레이에 추가가치?) | −0.009 | −0.057 | −0.549 | **추가가치 없음 ✗ (0/3)** |

- **① 예측 타이밍은 동행 타이밍을 이긴다 (standalone).** forecast 신호를 책 오버레이 스케줄로 쓰면, 동일한 디리스크 규칙(CAUTION 0.7 / CRISIS 0.4)을 동행 분류기 대신 예측 분류기로 구동했을 때 SR·calmar·PORT_t 전부 소폭 개선. MDD도 −29.0%→−26.2%로 개선. **예측이 디리스크 타이밍을 더 잘 잡는다.**
- **② 그러나 현 책 오버레이에 *스택*하면 개선 없음(미세 악화).** book_L5(현 동행 M4×AR×R05 오버레이)에 fc를 곱하면 SR −0.009·calmar −0.057·PORT_t −0.549. avg_exposure 0.795→0.760으로 **과디리스크**(정직 prior 적중). 현 책 오버레이가 이미 위기를 디리스크하므로 예측 신호는 중복 + 추가 현금화로 회복 랠리를 일부 더 놓침.

**결론**: 예측 forecaster는 *대체* 신호로는 동행보다 우수(①), *추가* 레버로는 무효(②). 현 책은 이미 오버레이가 있으므로 **현 시스템에 그대로 끼우면 개선 안 됨**. 가치가 있다면 "동행 오버레이를 예측 오버레이로 *교체*"하는 경로지, "stack"이 아니다.

---

## 전체 시나리오 표 (PIT-correct = decision_ym 매칭)

| scenario | abs_SR | abs_CAGR | abs_MDD | calmar | IR | PORT_t | avg_exp |
|---|---|---|---|---|---|---|---|
| bare | 1.536 | 45.5% | −40.7% | 1.118 | 1.649 | 7.236 | 1.000 |
| **book_L5** (현 책=baseline) | **1.685** | 38.9% | −23.3% | **1.672** | 1.209 | 5.142 | 0.795 |
| uni_cat (동행 standalone) | 1.572 | 43.0% | −29.0% | 1.482 | 1.415 | 6.143 | 0.959 |
| uni_cat_x_book | 1.670 | 37.8% | −23.3% | 1.624 | 1.096 | 4.610 | 0.777 |
| **fc_cat** (예측 standalone) | 1.617 | 43.4% | −26.2% | 1.657 | 1.428 | 6.318 | 0.932 |
| **fc_cat_x_book** (예측×책) | 1.676 | 37.6% | −23.3% | 1.615 | 1.080 | 4.593 | 0.760 |
| *fc_eval_lookahead* † | 1.665 | 44.7% | −25.0% | 1.786 | 1.479 | 6.625 | 0.930 |
| *fc_eval_x_book* † | 1.722 | 38.2% | −22.2% | 1.718 | 1.106 | 4.723 | 0.755 |

† **lookahead 진단 (PIT 위반, 비교 제외)**: eval_ym 매칭은 holding window가 시작되기 전엔 알 수 없는 1달-앞 예측을 쓴다. PIT path(fc_cat)보다 *강하게* 나오는 것이 정상 — 예측이 진짜 forward 정보를 담고 있고, 보고된 PIT path가 그 1달 peek을 정직하게 포기했음을 *확인*해 준다(leak 부재 검증). **의사결정 인용 금지.**

### bare가 PORT_t/SR에서 왜 높아 보이나
bare PORT_t 7.24 > 모든 오버레이. 오버레이는 active(−BM) 변동성을 *키워* PORT_t를 깎는다(현금화가 강세장 active 수익을 줄임). 오버레이의 가치는 PORT_t가 아니라 **MDD/calmar**(bare −40.7%/1.12 → book −23.3%/1.67)에 있다. 따라서 오버레이 간 비교(① ②)에서 PORT_t·calmar·SR을 함께 본 것이며, bare는 "오버레이 없음" 레퍼런스일 뿐 우승 후보 아님.

---

## AX-001 v2 crisis-conditional (forecast가 CRISIS/CAUTION 라벨한 31개월)

| forecast_crisis | n | bare 월평균 | book 월평균 | fc 월평균 | fc×book 월평균 |
|---|---|---|---|---|---|
| FALSE (평시 238m) | 238 | +3.70% | +3.27% | +3.70% | +3.27% |
| **TRUE (예측 위기 31m)** | 31 | **+2.83%** | +1.39% | **+1.15%** | +0.56% |

- 평시(238m): fc standalone은 bare와 동일(디리스크 안 함) → 정상. book은 동행 오버레이가 평시에도 일부 디리스크해 −0.43%p.
- 예측-위기(31m): bare +2.83% → fc +1.15%로 **손실/수익을 1.68%p 추가 축소**. 단 이 31개월 bare 평균이 *양수*라는 점이 핵심 — 예측 위기월이 실제로는 상승월도 많아(반등 포함) 디리스크가 수익을 깎는다. 이것이 ②(stack 무효)의 메커니즘: 예측이 위기를 잡되 그 중 일부는 회복 랠리라 과현금화.

## 신호 일치도 (디리스크 발동 월)
269개월 중 예측 디리스크 31m / 동행 디리스크 24m, 둘 다 발동 21m. **예측이 7개월 더 일찍/넓게 디리스크** → ①의 우위 원천(선제적). 단 그 추가 7개월이 ②에서 과현금화로 작용.

---

## PIT 노트 (핵심 — 이중 lag 회피 + decision_ym 선택)
- forecaster `ym`(`regime_forecaster.R` L41/L87) = `format(month-end Date,"%Y%m")` = **예측 대상월**, 직전 월말(`unified_regime_signal_daily`의 해당 월 마지막 레코드, 예: 200401→2004-01-31)에 emit(≤t 데이터로 t+1 예측, L50-71 walk-forward).
- 캐리어 holding window = `(decision_date, eval_date]`. eval_ym은 decision 다음 달이다(예: decision 2004-01-01, eval 2004-02-02, eval_ym=200402).
- **eval_ym 매칭은 lookahead**: ym=200402 예측은 2004-01-31에 emit → decision_date 2004-01-01에 미지(未知). 순진하게 eval_ym으로 매칭하면 1달-앞 peek = leak.
- **PIT-correct = decision_ym 매칭**: decision_date 2004-01-01에 known한 예측은 ym=200401(2003-12-31 emit)이고, 이는 holding window가 덮는 1월 국면 예측이다. 따라서 `forecast_regime[ym == format(decision_date,"%Y%m")]`. 과제 지침의 "`.prev_month_ym` 이중 lag 금지"를 준수 — `.prev_month_ym`(동행용)을 쓰지 않고 forecast의 사전예측 성질에 맞춰 decision_ym 직매칭. 결측월 → exposure=1.0.
- lookahead 버전(†)을 별도 산출해 PIT path가 그보다 약함을 확인(leak 부재 입증).

## 캐비엇
- fc_cat의 ① 우위는 작다(ΔSR +0.045). chain·단일검증이라 DSR 미적용이나, holdout/placebo 미수행 → **capital-grade 아님, 측정 라벨**.
- forecaster는 챔피언(`02_Infrastructure/regime/regime_forecaster.R`, hit 0.74~0.84>persistence). 새 신호 sweep 하지 않음(지침 준수). 단 `.cache/regime_forecast_series.parquet`는 2026-06-08 생성 — 2026-06 예측 포함(202606=CRISIS). 최신 재생성 미수행(기존 캐시 사용).
- 비용: 오버레이 리밸 비용은 β-schedule이 모든 시나리오에 동일 적용돼 cross-scenario 비교서 상쇄(weighted_screen_bt 라벨). standalone fc의 디리스크-리스크 회전 비용은 별도 미과금(현 책 오버레이도 동일 처리).

## 산출물
- `predictive_overlay_ab.csv` (8-시나리오 표)
- `predictive_overlay_crisis_eval.csv` (AX-001 forecast-conditional)
- `predictive_overlay_signal_agreement.csv` (예측 vs 동행 일치도)
- `fc_exposure_series.csv` (월별 fc exposure, PIT decision_ym)
- 스크립트: scratchpad `predictive_overlay_ab.R` (하니스 재사용 + builder 1개)
