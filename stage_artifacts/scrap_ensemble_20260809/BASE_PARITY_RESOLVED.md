# base parity 불일치 — 원인 확정 (2026-08-09, Q-Lead 직접 실측)

> **arm 측정·적대검증·종합 담당자는 이 파일을 먼저 읽을 것.**
> base 가 다르면 arm-vs-base paired t 가 통째로 달라진다. 같은 필터가 base 에 따라
> ΔIR +0.169 / −0.149 로 뒤집힌 전례가 있다.

## 관측된 불일치

| 산출 | CAGR | SR | MDD |
|---|---|---|---|
| Q-Lead `p0g` (dedup 85) | 11.04% | 0.6204 | 40.5209% |
| power-bar 에이전트 `p1_power_bars.R` (dedup 85) | 11.64% | 0.6486 | 40.5209% |

MDD 만 소수 4자리까지 일치 → **구성은 같고 수익 시계열의 시작점이 다르다**는 신호.

## 원인 = `Return.portfolio` 의 weights 전달 형태 (한 달 오프셋)

```
A) weights = xts (수익과 동일 인덱스)  → n=253, 시작 2005-03
B) weights = 상수 벡터 + rebalance_on="months" → n=254, 시작 2005-02
겹치는 253개월 최대 절대차 = 2.220e-16   (= 기계 오차, 즉 동일 시계열)
B 에서 첫 달만 제거 → CAGR 11.04% · SR 0.6204  (A 와 정확히 일치)
```

weights 를 xts 로 주면 PerformanceAnalytics 는 "t 시점 가중은 t+1 부터 적용"으로 해석해
**첫 기간을 떨어뜨린다.** 상수 벡터로 주면 첫 기간이 남는다.

## 그 한 달이 왜 중요한가

**2005-02 의 폐지 풀 EW 수익 = +13.2091%** (표본 첫 달, 이상치).

254개월 중 이 한 달이 **CAGR 0.60%p · SR 0.028** 을 만든다.

## 기각된 후보 3종 (실측, `p0h_parity.log`)

| 후보 | 효과 |
|---|---|
| C1 `rebalance_on` NA vs "months" | ΔCAGR **+0.000%p** (무효과) |
| C2 dedup 대표 선택 규칙 (first/last/best_sr/worst_sr) | CAGR 폭 **0.010%p** |
| C3 성분 평균(대표 임의성 제거) | 대표 방식과 동일 |

즉 dedup 대표 선택은 base 를 흔들지 않는다 — 이 축은 안심해도 된다.

## 정본 규약 (본 라운드 전 arm 적용)

1. **base 와 arm 은 동일한 월 집합** 위에서 측정한다. paired 검정의 전제다.
2. 워크포워드 OOS 창(최초 IS 60개월 이후)에서 평가하면 2005-02 는 애초에 제외되므로
   이 불일치는 소멸한다. **평가 창을 OOS 로 통일하는 것이 정본.**
3. base 앵커를 전표본으로 인용할 때는 **n 을 함께 표기**한다
   (`EW85 CAGR 11.04% (n=253, 2005-03~)` 또는 `11.64% (n=254, 2005-02~)`).
   n 없이 두 수치를 나란히 놓고 방법론 차이로 읽지 말 것.
4. 어느 arm 이든 base 재산출값을 보고에 포함해 parity 를 명시한다.

## 재현

```bash
Rscript -e 'source("stage_artifacts/scrap_ensemble_20260809/p0h_base_parity.R")'
```

metric_type = diagnostic_precheck
