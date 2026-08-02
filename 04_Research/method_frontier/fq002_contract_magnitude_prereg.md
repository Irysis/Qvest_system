# FQ-002 계약수주 magnitude — 사전등록 (측정 계획)

**작성 2026-08-02, 데이터 수집 착수 *전*.** 이 문서는 크롤이 돌기 전에 고정된다 —
값을 본 뒤 셀을 고르는 것을 구조적으로 막기 위함이다.

- 라운드 ID: `FQ002-contract-magnitude-pilot`
- lane: `non_return` (CLAUDE.md 도달경로 ① 비-return 신규 원천)
- 게이트 3단: **전부 통과** — hypothesis_index `contract`/`수주` 선례 0 · frontier 큐 owner 미지정·`dohoon_decision` 아님 · EV-지도 D4 가 "occurrence-형은 소진 — magnitude-형(FQ-002)만 미검"으로 직접 지목

---

## 1. 가설

공시 계약금액의 **상대 규모**가 long-side directional 알파다.
발생 여부(occurrence)는 이미 null(t=0.59)로 소진 — 크기(magnitude)는 미검증.

**벽 회피 논리**: long-side 신호이므로 `short-side-견인 × no-short 미하베스트` 벽을 우회할 가능성.
단 IC→PORT_t 전이는 여전히 미검증이며, 이 라운드가 검정하는 것은 **IC 단계까지**다.

## 2. 데이터 (게이트 실측 완료)

| 항목 | 확정값 |
|---|---|
| 공시유형 | `pblntf_ty="I"` (거래소공시). A/B/C/D/E/F/J 7종 전부 0건 |
| 필터 | `report_nm` 에 `단일판매` ∧ `체결`, 유니버스 corp_code 한정 |
| 발생률 | 87건/월 (체결·정정제외 40건/월), 유니버스 348사 |
| 파서 | `dart_contract_doc_parser.R` — 실측 3/3 + 위반주입 1/1 |
| 단위 | 계약금액·최근매출액 **모두 원**. 변환 불요 |
| 파일럿 범위 | 2023-08 ~ 2026-07 (36개월), ≈4,680 호출 |

## 3. PIT 규약 (사전 고정)

- 신호월 M 값 = **`rcept_dt` 가 M 말일 이전인 공시만** 누적. 월말 시그널 → 홀딩월 M+1.
- **기재정정 제외** (공급계약류의 52%). 사후 수정본을 과거에 쓰면 2026-07-06 오버레이 동월
  look-ahead 와 동형이 된다. 정정본은 누출검증용으로만 보존.
- 검증: 정정 반영판을 별도로 만들어 A/B — **정정판이 더 좋으면 그것이 누출 지문**이다.

## 4. 사전등록 측정 격자 (4셀, 전량 보고)

`selection_type = "chain"` **아님**. 4셀을 동시에 돌리고 **전부 보고**한다.
argmax 로 한 셀을 고르지 않는다 — 고르는 순간 `selection_type="sweep"` 이 되어
DSR ≥ 0.5 HARD 가 적용된다(measurement-graduation §3). 이 라운드는 셀 선택을 하지 않는다.

| 축 | 값 | 고정 사유 |
|---|---|---|
| DENOM | `revenue`, `size` | revenue=공시 네이티브(조인 불요), size=원 가설 분모 |
| weight | `equal`, `ivol` | 2026-08-02 T_RetAutoCorr 라운드 선례와 동일 |
| n_holdings | **20** (고정) | 동 선례 |
| WINDOW_M | **12** (고정) | 40건/월 → 월 커버리지 ~11%. 1개월 창은 이벤트 더미가 된다 |
| SCOPE | **all** (고정) | 변경계약 분리는 next_probe. 이 라운드는 혼합 판정 |
| universe | K200∪KQ150 + 20d ATV ≥ 2e8 (t-1 PIT) | 표준 |
| start_date | 2005-01-01 표준이나 **파일럿은 2023-08** | 데이터 범위 한계. 표준 판정 근거 아님 — `pilot_scope` 라벨 의무 |
| commission | 15bps | 표준 |

**WINDOW_M·SCOPE 를 격자에 넣지 않은 이유**: 넣으면 2×2×k×2 로 sweep 이 되고 DSR 게이트가
붙는다. 1차는 최소 격자로 신호 실재만 보고, 창·범위 민감도는 신호가 있을 때 next_probe 로 연다.

## 5. 판정 기준 (사전 고정)

이 라운드는 **파일럿**이며 자본 게이트가 아니다.

- **1차 판정 = IC 부호·크기와 그 안정성** (rank-IC, FMB t). 4셀 중 **최소 3셀에서 부호가 일치**해야
  "신호 실재" 로 본다. 부호가 셀마다 뒤집히면 그것은 신호가 아니라 구성 아티팩트다.
- **PORT_t·graduation HARD 3종은 이 라운드에 적용하지 않는다** — 36개월 표본으로 자본 판정을
  내리지 않는다(holdout 규약 §3: 18~24개월 Sharpe SE ±0.7~0.8 → 성과 채점 금지와 같은 취지).
- 전구간(2005~) 확장은 **1차 판정 통과 시에만**. 확장 후에야 canonical 측정·graduation 논의.

## 6. 사전 부정 조건 (falsification)

아래 중 하나라도 나오면 이 config 는 미달로 기록한다 — 사후에 기준을 옮기지 않는다.

1. 4셀 중 IC 부호 일치가 2셀 이하
2. 정정 A/B 에서 **정정 반영판이 유의하게 우수** → 누출 지문. 그 경우 원본체결판만 유효하며,
   원본판이 null 이면 이 라운드는 null 이다
3. 신호보유 종목이 월평균 10종 미만 → top-20 포트를 채우지 못해 측정 프레임 자체가 성립 안 함
   (이 경우 WINDOW_M 확대가 next_probe 이지 판정 실패가 아니다)

## 7. 부활 조건 (INV-7)

파일럿이 null 이어도 영구 판결이 아니다.

- **2005~2016 구간 미검**: 공시 규정·임계가 달라 커버리지가 다르고, 조선·건설 수주는 10년 사이클이라
  36개월은 사이클 일부만 본다
- **신규/변경 미분리**: 혼합 null 은 희석일 수 있다 — 분리 후 재도전 자격 유지
- **분모 축**: revenue·size 둘 다 null 이어도 계약금액 절대규모·계약기간·상대_최근계약 대비 증분 등
  미검 파생이 남는다
- **데이터 재활용**: FQ-002 가 null 이어도 수집 패널은 FQ-004(담보/질권)·RAMP 재료로 소비 가능

## 8. 산출물

- 크롤: `.cache/dart/contract_backfill/<YYYYMM>.csv`
- 패널: `.cache/dart/contract_panel.parquet`
- 팩터: `02_Infrastructure/alpha_search/factor_engine_contract.R` (DENOM env)
- 측정: `run_alpha_search()` × 4셀, 전량 보고
- 검사기: `08_Tests/data/test_contract_panel.R` (합성 픽스처 8/8, 배터리 편입)
