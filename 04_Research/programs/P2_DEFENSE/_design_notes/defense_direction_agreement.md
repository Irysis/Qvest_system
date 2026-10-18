# 방어 팩터 정렬 방향 vs 이론 방향(보는 창 월말 2005-01 ~ 2022-12 · 2026-10-18)

- 정렬 = 그 월말의 as-of IC 부호(factor_db_connector.R · 36개월 확장창). 원값은 방어 쪽이 높게 저장된다(위험량 음수화 · compute_defense.R) → **defensive_share = ic_sign = +1 인 달의 비율** = 틸트가 방어 쪽으로 기운 달.
- agree_share(레지스트리 direction 과의 일치)는 참고용 — 레지스트리 lower_better 는 음수화 전 양을 가리켜 원값과 어긋난다(D01~D04 · D07 = 0 은 정렬 오류가 아니라 레지스트리 표기 불일치). IC 부족 구간의 레지스트리 대체 경로는 이 팩터들을 공격 쪽으로 뒤집는다 — 별도 수리.
- D16 공왜도는 원값 = −공왜도라 +1 정렬 = 음의 공왜도(위험 프리미엄 쪽) — 위기 방어 틸트가 아니다.

| Factor_Name | name | known | defensive_share | flips | registry_theory | agree_share | first_known |
|---|---|---|---|---|---|---|---|
| D15_Cond_Bear_Beta | Conditional Bear Beta | 216 | 1.000 | 0 | 1 | 1.000 | 2005-01-31 |
| D16_Coskewness | Co-Skewness | 216 | 1.000 | 0 | 1 | 1.000 | 2005-01-31 |
| D28_Unlevered_Beta | Unlevered Beta | 216 | 1.000 | 0 | 1 | 1.000 | 2005-01-31 |
| Q07_Earnings_Stability | Earnings Stability | 216 | 1.000 | 0 | 1 | 1.000 | 2005-01-31 |
| Q08_Composite_Quality | Composite Quality Score | 216 | 1.000 | 0 | 1 | 1.000 | 2005-01-31 |
| D25_Left_Tail_Beta | Left Tail Beta | 216 | 0.787 | 7 | 1 | 0.787 | 2005-01-31 |
| D01_IdioVol | Idiosyncratic Volatility | 216 | 1.000 | 0 | -1 | 0.000 | 2005-01-31 |
| D02_Beta | Market Beta | 216 | 1.000 | 0 | -1 | 0.000 | 2005-01-31 |
| D03_RealVol | Realized Volatility | 216 | 1.000 | 0 | -1 | 0.000 | 2005-01-31 |
| D04_Downside_Beta | Downside Beta | 216 | 1.000 | 0 | -1 | 0.000 | 2005-01-31 |
| D07_Beta_Asymmetry | Beta Asymmetry | 216 | 1.000 | 0 | -1 | 0.000 | 2005-01-31 |
| D08_Tail_Beta | Tail Beta | 0 | NA | NA | -1 | 0.000 | NA |
