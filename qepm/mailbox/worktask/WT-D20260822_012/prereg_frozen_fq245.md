# 사전등록 초안 — FQ-245 방향성 일치 국면 조건부 macro-beta momentum

- WT: WT-D20260822_012 / 설계: alpha-hypothesis (fable) / 2026-08-22
- 지위: **초안** — alpha-research 가 측정 착수 전 이 문서를 사전등록으로 승격(동결)한다. 승격 후 그리드·문턱·판정규칙 변경 금지.
- 정본 설계: `alpha_hypothesis.json` (본 문서와 상충 시 JSON 이 정본)

## 1. 가설 (동결)

무조건부 macro-beta momentum 의 null(IC −0.0025 · PORT_t −1.265, AS-20260822)은 국면 간 부호 상쇄의 결과다. 3개 macro delta20(Term_Spread=T10Y2Y / VIX / KRW_USD)의 부호가 **모두 일치**하는 정렬 국면(실측 74/260개월)에서 top-25 score 선별의 조건부 활성수익은 양(+)이다.

## 2. 국면 라벨 (사전 규칙 — 사후 명명 금지)

- delta20_j = fred_j.shift(1) − fred_j.shift(21) (일별, ffill, Frequency=='d' 강제)
- 시그널 일자 = month-end. 라벨 = 그 시점 3개 delta20 부호.
- **aligned** = 3/3 동부호 (min_aligned=3 고정). delta==0 은 정렬 파괴.
- **min_aligned=2 는 설계에서 제외** — 발화 255/260(98.1%) 축퇴 실측(= 무조건부 재실행). 강건성 축 아님.
- 방향 소비: 정렬 월 top-25 = composite score 상위 25 (방향은 score 에 내장). mixed 월 = 무포지션(측정상 벤치마크).

## 3. Endpoint (동결)

| id | 정의 | n | 문턱 | 지위 |
|---|---|---|---|---|
| **E1 (PRIMARY)** | 정렬 월(양방향 pooled) top-25 EW 월별 활성수익 평균, NW lag-3 t | 74 | t ≥ 2.0 (screening) | 판정 권위 |
| S1 | aligned_up 단독 arm | 32 | 보고 전용 | secondary |
| S2 | 연속 정합도 C_t = \|Σz_j\|/Σ\|z_j\| 회귀 기울기 부호 (z = trailing 36m sd 표준화) | 260 | 보고 전용 | 기전 형태 진단 |
| E0 | 조건부 rank-IC (aligned vs mixed 분해) | — | — | advisory |

측정 = `canonical_screen_bt` 실측 경로(metric_type=canonical_screen), proxy 손계산 금지. selection_type = **single_prereg** (config argmax 없음 → DSR 게이트 비발동, 수치는 진단 산출).

## 4. Gate 0 산술 (측정 전 확정 — alpha_hypothesis.json 첫 필드)

- 함의 효과: pooled 연 13.4% / up 단독 18.4% (에피소드 n=4, **가설 생성용**)
- MDE80(실측 sd 0.06162, NW 1.011): pooled 24.4%/yr · up 단독 37.0%/yr
- ratio 0.55 / 0.50 ≥ 0.10 → **착수 허용**. 단 기대 t 1.54/1.39 → 기대검정력 ~34%/29% — 최빈 결말은 '미결'.
- **측정 착수 시(성과 개봉 전)**: 정렬 월 부분표본 active sd 재측정 — 전표본 sd 의 1.3배 초과 시 MDE 재산출 후 Gate 0 재판정.

## 5. 반증 조건 (동결 — 성과 동어반복 아님)

1. **F-flow (기전)**: 정렬 74개월에서 top-25 의 홀딩월 외국인 순매수 스프레드(investor_wide Foreign, Size 정규화, vs 유니버스 중앙값) NW-t ≤ 0 → flow 전달 기전 **기각** (수익이 나와도 기전 불명 강등, 성립 선언 불가).
2. **F-boundary (경계)**: |조건부 IC|_mixed ≥ |조건부 IC|_aligned → 정렬 경계 기각.
3. **F-MDD (그릇, 사전 예측)**: 조건부 전기간 MDD ≤ 45% 예측. E1 성립 ∧ MDD > 45% → standalone 불가, screen_route = OVERLAY_CANDIDATE / RCMA 조건부 specialist (사전 라우팅).

## 6. PIT 의무 (측정 단계 실행 항목)

- `assert_overlay_pit(used_cutoff=시그널 월말, holding_start=익월 첫 거래일)` **HARD**
- lag1 스트레스(신호 shift(1)) — 붕괴 시 동월 누출 의심
- strict-PIT A/B(`overlay_lookahead_ab`) — 인플레 >5% 시 strict 재판정
- macro_regime.parquet **미소비**(진행월 hazard 회피), fred_macro 일별 직접 + Frequency=='d' 코드 강제
- KQ150 백필: 청정창 2016-01~ 재추정 병기(r1)

## 7. 판정 규칙 (동결)

- `verdict_with_power` 경유 3분할: **성립 / 효과없음(powered null) / 미결(검정력)** — 라벨 구분 의무
- 2.95 미달 보고 시 창-도달가능성 상한 병기 (measurement-graduation §3)
- 미결 시 처분: 사전선언 next_probe(C4 bear_prob 조건화 · S2 연속 강도 승격)로 이관 — **동일 config 재실행 금지**
- 설계 후 확인(성과 개봉 전): 사전 규칙이 COVID 2020H1·Euro_Debt 2011H2 창에 정렬 월 ≥1 포함하는지 — 미포함 시 동기 서술 철회(가설 불변)
- 자본 경로 주장은 forge-authoritative 수치 없이 불가 — 본 라운드는 alpha 단계까지 (FQ-245 소비면 판정)
- FQ-233 비차단 근거: 표적 = 국면 조건부 **선별**, 분포-표적 아님 (alpha_hypothesis.json differentiation 절)
