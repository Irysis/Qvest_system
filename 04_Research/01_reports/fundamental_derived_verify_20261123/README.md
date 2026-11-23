# 재무 캐시 파생지표 체계 검증 (2026-11-23)

도훈 11-22 "파생지표 계산도 검증했었나?" · "재빌드 끝나면 파생지표 체계 검증도 진행해줘" · 11-23 "이어가줘".
대상 = `.cache/fundamental_quarterly.parquet` · `.cache/fundamental_annual.parquet`(생산기 `02_Infrastructure/data/build_fundamental_caches.R` · 11-17 09:33 판).
방법 = 생산기를 쓰지 않고 Python 으로 정의에서 다시 계산해 캐시와 대조(`derived_verify.py`) · 전 캐시 값 범위(`derived_ranges.py`).
1년 전 값은 (종목, 기간 − 100) 조회로 찾는다 — 생산기의 '4행 전이 정확히 12개월 전' 행 이동과 다른 방식(독립 재도출).
표본 = 무작위 400종목 + 대형주 6(405종목 · 시드 20261123). 퀀티 값 자체는 검증 대상이 아니다(퀀티 파일이 기준).

## 결과

| 검사 | 결과 |
|---|---|
| A. 입력(분기 단독) → 캐시 원계정(TTM · 잔액 · 분기 단독 `_Q`) | 3,089,480쌍 불일치 0 · 캐시에만 있는 값 0 · 재계산에만 있는 3,706 = 날짜 순서 계약으로 버린 값(설계) |
| 흐름 항목이 분기 단독인가(TTM 합의 전제) | 예 — 삼성전자 2019 매출 4분기 합 230.4조 · 2020 주당배당 354×3 + 1,932 = 2,994 · SK하이닉스 배당은 4분기만 |
| 잔액 · 흐름 분류(48 · 64) | 재무상태표 + 주식 수 · 직원 수 = 잔액 · 나머지 = 흐름 — 맞다 |
| B. 파생 223(분기) · 224(연간) 재계산 | 분기 4,525,319쌍 · 연간 1,222,570쌍 — 차이는 전부 아래 두 원인 + 부동소수점 3행(표준편차 ≈ 0 끼리 1.5e-8 대 4e-9) |
| 연간 원계정 = 분기 표 같은 기간 TTM | 513,752행 불일치 0 · 연간 행은 모두 결산월 |
| C. 파생 날짜 ≥ 쓰인 해(10개 해)의 입력 날짜 | 위반 0(분기 · 연간) · 기간 말 이전 날짜 0 |
| D. 입력 날짜 규칙(pit.md C4 · 법정기한 + 45일) | 회계연도 말 최소 136일(≥ 135) · 분기 최소 91일(≥ 90) · 위반 0 |
| 팩터 층이 읽는 항목 이름 76개 | 캐시에 모두 있다(MC = RAWDATA 시가총액) · 재무 팩터 89개 모두 월간 DB 에 있다 |

연간 표의 `AccountingBeta`(D29)는 시장 중앙값 날짜 규칙 때문에 다시 계산하지 않았다(날짜 검사 C 는 통과).

### 차이의 두 원인(값 오류 아님)

1. **분기 표 1년 전 행 규칙** — 생산기는 '4행 전이 정확히 12개월 전'일 때만 1년 전 값을 쓴다. 분기 보고가 빠진 기간(예: A002750 2001~2006 은 12월 행만)은
   12개월 전 행이 있어도 1년 전 = NA → 분기 표의 전년 대비 지표(AssetGrowth · d_TotalAssets · Lag_TotalAssets · PF_EqIssue …)가 빈다.
   표본 39,030행 중 269행(0.7%) · 값 9,214개. 있는 값은 맞고 PIT 문제도 없다(빠질 뿐). 연간 표는 해당 없음.
2. **날짜 순서 계약으로 버린 원계정**(늦게 도착한 옛 기간) — 그 값을 쓰는 파생이 생산기에는 있고 재계산에는 없다(설계 · 1,760개).

## 발견 — 정의 결함 2개(팩터 영향 없음)

- `TreasuryShareRatio` = TreasuryShares ÷ SharesCommonAdj — **자기주식 수는 그때 주식 수(수정 안 됨)**, 분모는 이후 분할 · 병합으로 **수정한 주식 수**다.
  뒤에 병합 · 분할이 있었던 회사에서 비율이 1을 넘는다(분기 3,691행 · 232종목 · 최대 21만 · 2000~2006 에 몰림). 대조: 삼성전자는 수정 주식 수 차이 42.89M = 자기주식 수.
  같은 기준 정의 = (SharesCommonAdj − SharesCommonOutAdj) ÷ SharesCommonAdj.
- `BuybackRatio` = BuybackShares ÷ SharesCommonOutAdj — 같은 기준 섞임(>1 이 1,471행 · 최대 46만). 수정된 매입 주식 수 항목이 없다.
- 두 지표를 쓰는 팩터는 없다(팩터 층 grep 0). 다만 `fund_access.R` 옛 이름 `SBB` = BuybackShares(수정 안 됨) · `ISSD` = SharesCommonAdj(수정됨)를 함께 쓰는 논문 엔진이 있으면 같은 섞임이 생긴다.

## 관찰 — 계산은 맞고 원자료 값에서 오는 것(퀀티 파일이 기준 · 고치지 않음)

비율이 정의 범위를 벗어난 행: IntangibleRatio 748 · CashToAssets 36 · CashRatio 36 · RecvToAssets 13 · IBDebtToAssets 13 · LongTermDebtRatio 10 · ShortDebtShare 10 · DebtToAssets 5(분기 표 · 수십만 행 중) —
분자 원계정이 음수(무형자산 · 매출채권 · 현금 음수)인 행이다. `sdv()` 는 분모만 거른다. 극단값(PPE_Growth 최대 250만 · SharesGrowth 14억 배 · DaysPayable 6천만 일)도 원계정에서 온다.

## 파일

`derived_verify.py`(A · B · C · D · 원인 분류 E) · `derived_ranges.py`(전 캐시 범위) · `*_summary.json` · 항목별 표 `derived_verify_{quarterly,annual}.csv` · `derived_ranges_{quarterly,annual}.csv`.
재실행: `.venv_qvest_ml/Scripts/python.exe -X utf8 derived_verify.py <출력 폴더> 400`.
