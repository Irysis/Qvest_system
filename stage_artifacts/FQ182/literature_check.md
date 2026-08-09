# FQ-182 문헌 사전 확인 — 왜도 반전이 기존 지식인가

**목적**: 주장을 "발견"으로 프레이밍하기 전에, 이미 알려진 현상의 KR 재확인인지 가른다.
**시점**: 2026-08-09, 적대검증 워크플로(wf_03dc6cd7-f14) 대기 중 병행.

## 검색 실측

| 소스 | 질의 | 결과 |
|---|---|---|
| openalex/semantic/ssrn | conditional return skewness after drawdown / volatility feedback / leverage effect | semantic **0** · ssrn **0** · openalex 6건 **전부 무관**(포트폴리오 볼록성·stylized facts·IMF 보고서 등) |
| arxiv/semantic | conditional skewness time-varying sign negative to positive bear market | semantic **0** · arxiv 8건 **직접 대응 0**(가장 근접 = "Skewness Dispersion and Stock Market Returns" 2026 — 횡단면 왜도 **분산**의 시계열 예측력으로 **다른 질문**) |

## 판정 — ★"신규"라고 주장하지 않는다

두 번의 검색이 직접 대응 문헌을 못 찾았다는 것은 **신규성의 증거가 아니다**. 검색 도구의 한계일 수 있고,
무엇보다 **인접한 확립 지식이 명백히 존재한다**:

- **Leverage effect** (Black 1976) — 음의 수익 → 이후 변동성 상승. 본 라운드의 `sd` 증가(ratio 2.86~3.53)는 이것의 재확인이다.
- **Volatility feedback** (Campbell–Hentschel 1992) — 변동성 상승이 다시 수익에 되먹임.
- **Conditional skewness** (Harvey–Siddique 2000) — 조건부 왜도는 시변하며 가격에 반영된다.

즉 **"낙폭 뒤 변동성이 커진다"는 교과서**이고, 본 라운드가 더한 것은 그 위에서
**"왜도가 부호까지 뒤집는가"(−0.31 → +0.27)** 라는 더 구체적인 형태 진술이다.
그마저도 조건부 왜도 시변 문헌의 특수 사례일 개연이 높다.

## 프레이밍 규약 (본 라운드 산출물 전체에 적용)

1. **"발견" 금지** — "KR 벤치 1991~2026 실측 확인" 으로 서술한다.
2. `sd` 증가는 **leverage effect 재확인**으로 명시하고 신규 주장에서 제외한다.
3. 남는 신규성 후보는 **왜도 부호 반전의 크기·문턱 의존성**뿐이며, 그것도 적대검증 생존이 전제다.
4. 문헌 미발견을 근거로 우선권을 주장하지 않는다 — 검색 2회는 근거가 못 된다.

## 이것이 판정에 미치는 영향

**없음(방향)**. 알려진 현상이어도 KR 실측값은 여전히 의사결정 입력이다.
다만 **배분 함의**에는 영향이 있다 — leverage effect 가 확립 지식이라는 것은
"낙폭 뒤 변동성 확대"가 **예측 가능하고 이미 가격에 반영돼 있을** 개연을 높인다.
즉 왜도 개선이 있어도 그것이 **초과수익 기회**라는 보장은 없다. 이 긴장을 판정문에 담을 것.
