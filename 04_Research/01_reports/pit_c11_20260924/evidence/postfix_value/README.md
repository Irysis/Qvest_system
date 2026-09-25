# postfix 값 대조 증거 (PIT C11 · 2026-09-24 · B1·B2)

규칙 b2 → b3 수리의 근거다. 공표일을 빈티지 **날짜**가 아니라 **값의 첫 등장**으로 잡는다.
날짜만 보는 대조(r1_alfred/check_bounds.R 의 R1·R*)는 개정 전용 판(그 관측 값이 없는 판)을 공표로 셌다.
그 결과 INDPRO 2건과 PERMIT 5건의 가용일이 실제 공표보다 일렀다.

| 파일 | 내용 |
|---|---|
| `initial_release.csv` | FRED API `series/observations` `output_type=4`(Initial Release Only)의 `realtime_start` = 관측별 첫 공표일. INDPRO·PERMIT 외 11계열 |
| `alfred_asof_*.csv` | keyless `alfred.stlouisfed.org/graph/alfredgraph.csv?vintage_date=` as-of 스냅샷 원문. 두 번째 출처 대조용 |
| `fetch_initial_release.R` | `initial_release.csv` 재수집 스크립트. 키는 `.env` 에서 읽고 출력하지 않는다 |

재현: `r1_alfred/` 에서 `Rscript check_bounds.R <규칙 경로> <출력 csv> ../postfix_value/initial_release.csv` 를 돌린다.
출력의 `위반_V` 가 값 대조 판정이다.

| 규칙 | INDPRO 위반_V | PERMIT 위반_V | PCOPPUSDM 위반_V | WALCL 위반_V |
|---|---|---|---|---|
| b2 | 2 | 5 | 21 | 1 |
| b3 | 0 | 0 | 21(범위 밖 · 미수리) | 1(ALFRED 공백 의심 · 미수리) |

b2 가 7건을 공표보다 먼저 썼다(한국 거래일 기준).

| 관측 | b2 가용일 | 실공표(미국) | b3 가용일 | 조기 사용 |
|---|---|---|---|---|
| INDPRO 2025-09 | 2025-11-25 | 2025-12-03 | 2025-12-04 | 7일 |
| INDPRO 2025-10 | 2025-12-04 | 2025-12-23 | 2025-12-24 | 14일 |
| PERMIT 2019-01 | 2019-03-05 | 2019-03-08 | 2019-03-11 | 4일 |
| PERMIT 2025-11 | 2026-01-12 | 2026-02-18 | 2026-02-19 | 25일 |
| PERMIT 2025-12 | 2026-02-03 | 2026-02-18 | 2026-02-19 | 9일 |
| PERMIT 2026-01 | 2026-03-04 | 2026-03-12 | 2026-03-13 | 7일 |
| PERMIT 2026-02 | 2026-03-31 | 2026-04-29 | 2026-04-30 | 22일 |
