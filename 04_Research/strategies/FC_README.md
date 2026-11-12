# FC_* — 팩터 척추 1단계(F0) 자체 사양 엔진 15개

2026-11-12 · 작성 Q · 결정 **FACTOR-SPINE-STAGE1-20261112**(D1 (나) · D2 (가) · D3 (가) 가족 14 + 토탈 1 · D4 (a) · D5 (가) · D6 (가))
설계 정본 = `04_Research/01_reports/factor_spine_design_20261111/README.md` §3-1 ~ §3-4

**상태 = 만들기만 했다(F0).** 등록 · 측정(자격 라운드 P1R03)은 판 2(P1S02) 시드 판정 뒤다(D6 (가)). 이 폴더들의 엔진은 아직 어느 라운드 · 등록부 · 기저 풀에도 들어가 있지 않다.

---

## 1. 무엇

| 폴더 | 엔진 | 점수 |
|---|---|---|
| `FC_FAM_<가족>/` 14개 | 팩터 가족 합성 | 종목마다 그 가족 구성원의 결합용 뷰 점수 가운데 값이 있는 것의 평균(하나도 없으면 결측) |
| `FC_TOTAL_EW/` 1개 | 토탈 스코어 v0 | 종목마다 가족 점수 14개 가운데 값이 있는 것의 평균(가족 균형 등가중 · 전부 결측이면 결측) |

- **결합용 뷰 점수** = 매 시점 횡단면 순위 [−1, 1](동순위 평균) × 등록부 기대수익 방향 — 설정 정본 `06_Registry/factor_combinable.json`(새 숫자 없음).
- **읽기 경로** = `fc_load_month(d, direction = "registry", factors = <구성원>, missing = "na", dedup = FALSE, family = TRUE)` 한 곳(C15). IC · 부호 층 함수를 부르지 않는다.
- **산출** = `FACTORS(Date, Ticker, Score)` 만(PORTFOLIO 없음). Date = 결합용 뷰의 그 달 as-of(월말 거래일 — 셀 경로 달 스냅에서 항등). 점수 결측 종목은 그 날 패널에서 뺀다(0 으로 채우지 않는다).
- **시작** = 러너 · 셀 경로가 넘기는 `.RP_START_DATE`, 없으면 측정 축 정본(`constraint_defaults.json::measurement_axis` 활성 epoch)의 시작일. as-of 가 시작일 이후인 달만.
- **방향 · 가족 고정** = 엔진 파일 안에 구성원 id · 등록부 부호 `s_reg` · 가족을 박고, 실행 때 뷰 메타의 `s_reg` · `category` · 빌더 판(`factor_combinable.R v1.1`)이 다르면 멈춘다 → 새 사양으로 다시 선언.
- **근거 문헌**(설계 §3-2 표): 변환 = Gu, Kelly & Xiu (2020) RFS 33(5) https://doi.org/10.1093/rfs/hhaa009 · 가족 평균 = Asness, Frazzini & Pedersen (2019) RAS 24(1) https://doi.org/10.1007/s11142-018-9470-2 · Jensen, Kelly & Pedersen (2023) JF 78(5) https://doi.org/10.1111/jofi.13249 · 토탈 v0 = 같은 규칙을 한 층 위에 · 결측 = 설정의 `missing = "na"`.
- 폴더마다 `engine.R`(생성기 산출 · **손 편집 금지**) + `own_spec.json`(사양 원문 — `core`(엔진을 정하는 전부 · 사양 md5 대상) · 근거 문헌 · `root_paper`(JKP 2023 · `paper_key` = 폴더 이름) · `family_root`(`FC:<가족>` · `FC:total`) · 규칙 메모 · 제외 목록과 사유 · 생성 때 뷰 대조 · 입력 md5 · 생성기 md5 · 엔진 md5 · 선언 시각).
- 진단(판정 입력 아님): 엔진이 실행되면 같은 폴더에 `fce_diag.csv`(날짜별 구성원 수 · 가족 수 · 점수 범위 · 종목별 유효 수 분포)를 남긴다. `options(fce.diag_dir = ...)` 로 바꾸고, 폴더가 없으면 쓰지 않는다.

## 2. 다시 만드는 명령(저장소 루트)

```bash
Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --dry-run          # 쓰지 않고 구성원 수 · 엔진 md5 표만
Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --write            # 15개 쓰기(같은 엔진이면 건드리지 않음 = unchanged · 선언 시각 보존)
Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --write --out DIR  # 다른 곳에 쓰기(대조용)
```

손 편집 · 생성기 변경 대조(R): `source("02_Infrastructure/factor_db/fc_engine_gen.R"); fce_verify("04_Research/strategies/FC_FAM_quality")`
→ `ok` = 파일 md5 · own_spec 에서 다시 만든 md5 · 기록 md5 가 같다 · `generator_drift` = 지금 생성기 ≠ 사양의 생성기.
엔진은 생성기 md5(파일 md5)를 본문에 박는다 — 생성기를 고치면 15개 모두 새 엔진(새 선언)이 된다.

## 3. 구성원 규칙(fce_rule_v0)

1. 등록부 `category` = 그 가족 · 2. `lifecycle.status = active` · 3. `06_Registry/factor_panel_axis.json` `panel_axis = cross_sectional` · 4. PIT 격리 목록(`validation/pit_quarantine.R::pitq_factor_ids`) 밖 · 5. `release_pending` 표식 없음 — 설계 §3-2 그대로.
6. **(v0 · PIT 우선 — 설계 원안을 바꿈)** 등록부 dedup · retired_dedup 표식(상관 · 군집 스캔 = 전기간 통계 측정)은 읽지 않는다(pit.md C1 · C14). 빼는 것은 **정의상 별칭**뿐 — 같은 가족 · 같은 `data_source` · 같은 `update_freq` 안에서 (F) `definition` 문장 전체가 같거나(공백 · 대소문자 정규화) (D) `definition` 이 다른 구성원을 `alias of <id>` · `identical to <id>` 로 선언한 것. 정의로 판별할 수 없으면 빼지 않는다.
   - **별칭 묶음에서 남기는 하나 = factor id 사전순 첫째(C 로캘 정렬)** — 성과를 읽지 않는 기계 규칙. 등록부 `dedup.canonical` · `dedup.reason` 같은 표식(전기간 통계 근거가 섞여 있다)은 남길 쪽을 정하는 데도 쓰지 않는다(판단 Superfan T1 참고 C-20261112-007).
   - 적용 범위 = 가족 안(가족 점수 = 가족 안 평균). 가족을 넘어 정의가 같은 구성원은 남기고 사양 메모에 적는다.
- 성과에서 나온 표식(`labels.evidence_tier` · `lifecycle.research_stage` · `factor_evidence.json` 단계)은 읽지 않는다. 등록부는 정본 판독기(`factor_db_connector.R::.load_registry`)로만 읽는다.
- 방향 = 등록부 기대수익 방향(`lower_better` → −1 · 그 밖 +1 — 결합용 뷰와 같은 규칙). 방어 계열(defense · risk · liquidity · regime)도 1단계는 기대수익 방향(D5 (가)).

| 가족 | 등록부 | 규칙 1~5 제외 | 정의상 별칭 제외 | **구성원** | 설계 §3-1 초안 |
|---|---:|---|---|---:|---:|
| quality | 47 | — | — | **47** | 42 |
| defense | 59 | 축 1 · 격리 1(D32_Beta_VIX) | — | **57** | 36 |
| liquidity | 44 | — | — | **44** | 36 |
| momentum | 32 | 축 1 | M29_Mom_5d(→ M11_ST_Reversal) | **30** | 27 |
| accrual | 25 | — | AC11_Accruals_to_Assets · AC18_Accrual_Quality(→ AC01_Total_Accruals_CF) | **23** | 20 |
| value | 24 | — | — | **24** | 19 |
| growth | 21 | — | — | **21** | 17 |
| investor_flow | 15 | — | — | **15** | 15 |
| risk | 19 | — | — | **19** | 13 |
| crowding | 16 | 축 2 | — | **14** | 13 |
| consensus | 19 | 상태 2 · 재빌드 대기 3 | — | **14** | 12 |
| technical | 12 | — | — | **12** | 12 |
| regime | 28 | 상태 2(MA01 · MA02 — 격리 겹침) · 축 18 | — | **8** | 8 |
| leverage | 6 | — | — | **6** | 5 |
| **합(토탈 구성원)** | 367 | 30 | 3 | **334** | 275 |

빠진 계열: `size`(설계 §3-1 — 원안 규칙에서 구성원 1개 · v0 규칙이면 2개지만 D3 (가) 그대로 뺀다) · `custom`(논문 엔진 동결 패널 2건 — 자체 사양 아님).
제외 사유 전문(id · 규칙 · 근거)은 각 `own_spec.json::excluded`.

## 4. 설계와 달라진 점

1. **규칙 6 → v0 판**(위 §3) — 통계 dedup 표식을 쓰지 않아 구성원이 275 → 334 로 늘었다(정의상 별칭 제외 3).
2. 시험(설계 §3-7 1~7) · 돌연변이 대조 · `08_Tests/factor_db/test_fc_engine_gen.R` 를 만들지 않았다(도훈 "테스트 좀 그만하자"). 만들면서 확인 셋만 했다(§6). F0-2(수리 뒤 중복 재스캔)도 하지 않았다.
3. 설계 §3-1 표의 '시작 월'(커버리지 표 기준)은 내지 않았다 — 생성기는 결합용 뷰 저장본(`fc_coverage.parquet`)을 직접 읽지 않는다. 실효 시작은 측정 계약(MC3)이 정한다.
4. 설계에 없던 엔진 세부: ① RAWDATA 는 거래일 달력(월말 거래일 · 끝 달)으로만 쓴다 ② 패널 마지막 달을 뷰가 아직 못 따라왔으면(그 달 파일 없음 · as-of 가 패널 끝보다 늦음) **그 달만** 뺀다 — 그 밖의 달에서 같은 일이 나면 멈춘다 ③ `s_reg` 뿐 아니라 `category` · 뷰 빌더 판 · 읽기 인자도 고정 단정 ④ 진단 파일 위치 · 옵션 ⑤ 같은 엔진이면 쓰지 않는다(선언 시각 보존).
5. 핀의 '생성기 함수 md5'(설계 §3-4)는 **생성기 파일 md5** 로 구현했다(주석 한 줄을 고쳐도 15개가 다시 선언된다 — 보수 쪽).

## 5. 한계

- **근사 중복**: 규칙 6 v0 는 정의상 별칭만 빼므로, 정의는 다르지만 신호가 비슷한 구성원(예: 변동성 · 베타 · 꼬리위험 변형이 많은 defense 57 · risk 19)이 가족 안에 그대로 남는다 — '등가중 가족'은 사실상 그 신호 묶음에 더 무게를 준다. **P1R03 의 결론은 '이 구성원 집합의 등가중 가족 합성' 수준으로 한정한다**(고치는 것은 결합기의 일 — 설계 §4 · §9).
- 가족을 넘어 정의가 같은 구성원은 남겼다 — 토탈에서는 그 양이 두 가족에 한 번씩 들어간다(설계 §9 '가족 구분의 겹침'). 기계 규칙 (F) 로 잡힌 쌍: D46_Sortino(defense) ↔ R15_Sortino(risk).
- 종목마다 값이 있는 가족 수가 다르다(2022-10 ~ 12 진단: 최소 1 · 중앙 14) — 값이 적은 종목의 토탈은 몇 가족의 점수 그대로다.
- 등록부 방향을 그대로 믿는다(설계 §9 — 방향 근거가 문헌인 팩터는 일부).
- 등록부는 작업 트리 판(md5 `4995af5ad30ec401c7dc7cc2099f6b11` · 미커밋 변경 포함 가능)으로 선언했다. 등록 전에 등록부 구성원 · 부호 · 가족이 바뀌면 `--write` 로 다시 선언한다(엔진은 바뀐 채로는 실행 때 멈춘다).
- 엔진이 결합용 뷰 모듈을 싣기 때문에 측정 프로세스에 그 접근자의 패키지(dplyr · arrow 등)가 붙는다 — 정본 접근자를 쓰는 다른 엔진과 같다.

## 6. 확인(만들면서 셋만 · 2026-11-12)

- (a) 재현: 생성 진입점을 두 번(저장소 · 빈 임시 폴더, 별도 프로세스) 돌려 엔진 15개 바이트 동일 · 두 번째 저장소 실행은 15개 모두 `unchanged` · `own_spec.json` 에서 다시 만든 md5 = 파일 md5 15/15.
- (b) 정적: 15개 모두 `parse()` 통과 · 코드 줄의 `fc_load_month(` 호출 1곳 · 그 호출에 `direction = "registry"` 상수 · 다른 읽기 함수 0 · `arrow` · `read_parquet` · `.cache` 0(grep).
- (c) 동작 1회: `FC_TOTAL_EW` 를 저장소 밖 임시 래퍼로 2022-10 ~ 12 만(셀 경로 없음 · 엔진 파일 md5 전후 같음 · 진단은 임시 폴더로) — 열 = Date · Ticker · Score · 11,243행(3,747 · 3,748 · 3,748) · Date = 그 달 as-of = 패널 월말 거래일 3/3 · (Date, Ticker) 중복 0 · 결측 0 · 점수 [−1, 1] 안 · 구성원 334개 전부 방향 · 가족 고정 단정 통과. 성과는 계산하지 않았다.
- 하지 않은 것(지시): 상설 판 정적 분류(`rc_standing_static`) · PIT 정적 스캔(`lookahead_detector`) — F1 사전 점검 때 돌린다. 본문은 두 검사의 알려진 패턴(방향 인자 상수 · 부호 층 식별자 · 'sig' 문맥 등)을 피해 썼다.

## 7. F1(P1R03 사양 · 등록) 때 쓸 것

- `rc_init_p1(..., engines = ...)` 항목: `engine_path` = `04_Research/strategies/<폴더>/engine.R` · `paper` = `own_spec.json::root_paper` · `family_root` = `own_spec.json::family_root`.
- 핀(`pins.files`) 후보: `02_Infrastructure/factor_db/factor_combinable.R` · `06_Registry/factor_combinable.json` · `02_Infrastructure/factor_db/fc_engine_gen.R` · 각 `own_spec.json`(엔진 파일은 칸 사양이 가리키면 자동). 등록부는 실행 때 가족(category) 판독에 쓰이므로 핀으로 물지는 라운드 설계에서 정한다.
- 등록 직전 `--dry-run` 으로 md5 가 그대로인지 본다(바뀌었으면 `--write` 뒤 새 선언 시각).

생성 시점 엔진 md5(정본 = 각 `own_spec.json::engine.md5` · 생성기 md5 `e31ad11fa6be218017e961c47b06bbdc`):

| 폴더 | 구성원 | engine.R md5 |
|---|---:|---|
| FC_FAM_quality | 47 | 44ee47336a59440b802df7f8b806ce12 |
| FC_FAM_defense | 57 | 9ce4d35e0abcafe3bcae50fb403f776f |
| FC_FAM_liquidity | 44 | 025542f5add248da990b54ede664b5ed |
| FC_FAM_momentum | 30 | c01054627224104417203bed9713dca7 |
| FC_FAM_accrual | 23 | fb3e57168e808786a59e12fc37231069 |
| FC_FAM_value | 24 | faba4b417a0757942ef20a44bdae36ed |
| FC_FAM_growth | 21 | 25e5b0737fcaf17d83f2d4cb39e2dfb5 |
| FC_FAM_investor_flow | 15 | a0c3c6348cdf641e54bbf82538844c20 |
| FC_FAM_risk | 19 | 95fe3b0f46d27adbecea3e9a41c65077 |
| FC_FAM_crowding | 14 | d558c7c7d48f86aa57a62022a3fc89b5 |
| FC_FAM_consensus | 14 | 2e1d57186c64bf58ba9255943d9406b2 |
| FC_FAM_technical | 12 | 2d98ab8ab4412c54f9659909b64b939a |
| FC_FAM_regime | 8 | 2422c1c492d528f1944c4cef9003dd08 |
| FC_FAM_leverage | 6 | 8899e5934fcf11e22289a1364975e383 |
| FC_TOTAL_EW | 334 | 55e6f27f1b660ef349d1f95ec2b98d75 |

## P1R03 등록 약속(판단 Superfan T1 C-20261112-001 · T3 C-20261112-011 수용 · 11-12)

- 설계 §3-7 시험 1(절단 불변성) · 2(양성 대조)는 생략하지 않는다 — `08_Tests/factor_db/test_fc_engine_gen.R` 로 만들어 P1R03 사양 `tests` 에 넣고 **`rc_register(run_tests = TRUE)`** 로 등록 때 반드시 한 번 돈다(판 2 의 `run_tests = FALSE` 선례를 따르지 않는다). 나머지 시험 3~7 은 생략(도훈 11-12 "테스트 좀 그만하자").
