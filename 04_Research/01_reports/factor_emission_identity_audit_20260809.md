# factor_db 배출 정체 검사 — 전수 감사 (2026-08-09)

**FQ**: FQ-210 · **성격**: 인프라 위생 라운드(알파 판정 아님) · **비용**: 기존 산출물 재판독만, factor_db 재빌드·재계산 없음 (총 실측 ~150초)
**대상 vintage**: `build_hash = 20260809203741_8c9befe0` (2026-08-09 440개월 전면 재빌드)
**계기**: FQ-198 / WT-D20260809_005 가 "신규 5종 해금" 중 3종을 가짜로 적발 — 같은 함정이 더 있는지 전수화.
**경로**: 전 구간 `load_month_factors()` 경유(C15 준수, parquet 직접 read 없음) + `emission_ledger.csv` 재판독.

---

## 0. 한 줄 결론

`emission_guard` 는 `n_rows > 0` 만 본다. 그래서 **다른 팩터와 값이 같은 배출**과 **횡단면 상수라 소비면에 0으로 도달하는 배출**을 원리적으로 못 본다. 두 축을 실측으로 채운 결과, **죽은 배출 3종(C15·D60·Q16)** 과 **미선언 중복 5쌍**이 나왔고, 그중 D60/Q16 은 **2015-01~2025-12 연속 11년** 동안 매월 2,753~2,968행을 배출하면서 소비자에게는 아무 값도 도달시키지 않았다.

---

## 1. 검사 규모 (a)

| 축 | 대상 | 격자 |
|---|---|---|
| 존재 | `emission_ledger.csv` 재판독 | 440개월 × 347팩터 = 122,554행 |
| 정체 | 커넥터 가시 331팩터 전 × 전 | 표본 6월 × 쌍 54,615 |
| 살아있음 | 배출 셀 전수 | 반기 격자 61개월(199606~202606) × 배출셀 19,090 |

- registry `active` **371종** / 원장 배출 이력 **347종** / 배출 이력 0 = **24종**(별도 Class S 침묵 — 기존 가드가 이미 보는 축)
- 표본 월(정체 축): `200506 · 201006 · 201406 · 201806 · 202206 · 202606` — 시대를 가르도록 선택
- 전 팩터 × 전 팩터 상관은 실제로는 **비싸지 않았다**: 331팩터 격자 1개월 = **0.85초**(6개월 5.1초 실측). 계열(prefix) 안으로 좁힐 필요가 없었고, 좁혔다면 **C11≡M25 같은 계열-교차 중복을 놓쳤다.**

---

## 2. 중복 배출 (b)

`|월별 횡단면 spearman|` 최대값 ≥ 0.99 쌍 = **139**. registry `dedup.cluster` 선언과 대조:

| 판정 | 기선언 | 미선언 | 계 |
|---|---|---|---|
| DUP_EXACT_BITWISE (6/6월 최대절대차 0.000e+00 ∧ 완전동일 1.000) | 14 | **2** | 16 |
| DUP_RANK_IDENTICAL (\|rho\| ≥ 0.999) | 52 | **3** | 55 |
| NEAR_DUP (0.99 ≤ \|rho\| < 0.999) | 35 | 33 | 68 |
| **계** | **101** | **38** | **139** |

### 미선언 EXACT/RANK 5쌍 — 정본 지정 필요

| # | 쌍 | max rho | min rho | 최대절대차 | 비고 |
|---|---|---|---|---|---|
| 1 | `C01_SUE` ≡ `C10_SUE_Persistence` | 1.000000 | 1.000000 | 0.000e+00 | 기확정(FQ-198). 완전동일 1.000 |
| 2 | `C04_ESBR` ≡ `C13_Revision_Breadth_3m` | 1.000000 | 1.000000 | 0.000e+00 | 기확정(FQ-198) |
| 3 | **`C11_Earnings_Streak` ≡ `M25_Earnings_Mom_Streak`** | 1.0000000 | 0.9999933 | 0.168 | **신규**. 계열 교차(C↔M) |
| 4 | **`C01_SUE` ≡ `C09_Earnings_Surprise_Sq`** | 0.9999982 | 0.9999838 | 1.852 | **신규**. 구조적 |
| 5 | **`C09_Earnings_Surprise_Sq` ≡ `C10_SUE_Persistence`** | 0.9999982 | 0.9999838 | 1.852 | 위 두 개의 추이적 귀결 |

**기전**:

- **#4/#5 = 단조변환 재등록.** `compute_consensus.R:236-237` — `C09 = sign(sue) * sue^2`. `sign(x)·x²` 는 **순증가 단조변환**이므로 순위가 구조적으로 동일하다. 값은 다르므로 **최대절대차로는 안 잡히고 랭크로만 잡힌다**(주석은 "Distinct metric: amplifies large surprises" 라고 적혀 있으나, top-N 선별·rank-IC 어느 쪽에서도 증폭은 관측되지 않는다 — 순위가 같기 때문).
- **#3 은 코드에 이미 적혀 있었다.** `compute_consensus.R:258-260` 이 2026-08-08자로 "M25 와 식·원천·정렬이 동일 … 중복 판정을 별도 제안으로 올린다"고 기록했으나, **그 제안이 registry 에 도달하지 않았다.** 값으로 독립 재확인.

**정리**: consensus 계열에서 한 신호(SUE)가 `C01`/`C09`/`C10` **3중 등록**, ESBR 이 `C04`/`C13` 2중, streak 이 `C11`/`M25` 2중이다.

### 부수 발견 — 기선언 101쌍도 이중 투표 중

`factor_dup_scan.R` 의 소비 API(`drop_alias_factors()` · `resolve_factor_canonical()` · `report_redundant_clusters()`)는 **실코드 소비자 0**이다. 참조는 자기 자신 + 테스트 + `apply_factor_dedup.R` + 2026-08-02 일회성 리포트 스크립트 2개뿐이고, registry 의 `consumption_rule` 문자열(127종에 선언)을 읽는 코드는 없다. **선언은 있는데 배선이 없다** — 라벨이 행동으로 이어지지 않으므로, 기선언 101쌍도 선별·Ω 추정에서 그대로 두 번 투표한다.

---

## 3. 죽은 배출 (c)

정의: 원장 `n_rows > 0` 인데 **소비면(커넥터) 도달 0행**. 기전은 빌더에 확정적으로 박혀 있다 —

```
factor_db_builder.R:682   if (is.na(s) || s < 1e-12) rep(NA_real_, .N)     # s = sd(winsorized raw)
factor_db_builder.R:722   Coverage := !is.na(Raw_Value) & !is.na(Z_Score)
```

즉 **횡단면 sd < 1e-12 ⇒ Z 전건 NA ⇒ Coverage FALSE ⇒ 모든 소비자에게 0행**.

배출셀 19,090 중 소비면 도달 0 = **904셀**.

### 3a. DEAD_ALWAYS 16종 (797셀 전부)

| 분류 | 종수 | 팩터 |
|---|---|---|
| **정당 — 시장레벨 상수** | 15 | `RE01/02/03/10/11/12/13/14/15/16` · `MA05/06/07` · `CR03_Herding_Dispersion` · `M31_Breadth_Mom` |
| **★진짜 죽은 배출** | 1 | **`C15_Forecast_Error_Trend`** — 50/50월(200112~202606), 월 ~854행 |

시장레벨 15종은 빌더가 설계로 인정한 상태다(`factor_db_builder.R:719-721` 이 이름을 직접 열거). **이것이 "전면 stop 금지"의 실측 근거** — 상수 배출을 무조건 차단하면 매 빌드가 죽는다.

### 3b. DEAD_PARTIAL 24종 (1,240셀 중 107셀 사망) — ★버그 서명

| 팩터 | 사망/배출 | 사망 창 |
|---|---|---|
| **`D60_Leverage`** | 22/53월 (41.5%) | **201506 ~ 202512 전 구간** (월 2,753행) |
| **`Q16_Debt_to_Assets`** | 22/53월 (41.5%) | **201506 ~ 202512 전 구간** (월 2,968행) |
| `SE02_Consensus_Revision` | 10/53월 | 200006·200312·200412 + 201712~202512 격년 12월 |
| `L04_Bid_Ask_Proxy` | 7/61월 | 199606~199906 (초기 vintage) |
| 나머지 20종 | 각 1~4월 | 대부분 200106~200212 초기 vintage 집단 |

D60/Q16 은 `compute_quality.R:224` · `compute_defense.R:940` 에서 **`!is.na()` 필터를 통과한 행만** 배출한다. 따라서 그 2,753~2,968행은 **유한한 값이면서 횡단면 상수**다(전부 같은 값).

### 3c. 원인 축 국소화 — 부채 계열 시대분해 (내부 대조 포함)

가시 월의 `modal_frac`(최빈값 점유율) 중앙값:

| 팩터 | pre-2015 | 2015~2025 | 2026+ |
|---|---|---|---|
| `Q16_Debt_to_Assets` | 0.5714 | **가시 0월 (사망)** | 0.7727 |
| `D60_Leverage` | 0.5484 | **가시 0월 (사망)** | 0.7562 |
| `Q15_Debt_to_Equity` | 0.5283 | **0.9370** (준-사망) | 0.7141 |
| `XF_LL01_DebtToCapital` | 0.5283 | **0.9361** (준-사망) | 0.7108 |
| `R17_Market_Leverage` (시장가 혼합) | 0.1223 | 0.1054 | 0.1080 (**무변**) |

같은 부채 원천을 쓰는 4종이 2015 경계에서 사망 또는 준-사망으로 꺾이는데, **시장가를 섞는 R17 만 무변**이다 ⇒ 결손은 부채 원천 축에 국한되고 2015-01 이 경계다. (2026+ 회복은 표본 1개월이므로 방향만 표시 — 2026-08-08 DART 계정명 매칭 수리와의 인과는 **미확인, next_probe ①**.)

또한 pre-2015 의 0.53~0.57 자체가 이미 "절반 이상이 같은 값"이다 — 이 계열은 처음부터 절반쯤 퇴화해 있었고, 2015 에 완전히 넘어갔다.

### 3d. 준-죽은 배출 (가시분 `modal_frac`)

| 문턱 | 팩터 수 (331종 중) |
|---|---|
| `modal_frac ≥ 0.99` (경고) | **1** — `C08_Coverage` 1/49월 (0.9900) |
| `≥ 0.95` (관찰) | 3 — `SE02` 27/43월 · `L04_Bid_Ask_Proxy` 6/54월 · `C08` 1/49월 |
| `≥ 0.90` | 11 |

`SE02_Consensus_Revision` 이 유일하게 **상시** 경계선이다(중앙 0.957, 최소 고유값 비율 0.00127) — 사망 10/53월과 합치면 선별 자격 재판정 대상.

---

## 4. 대조군 (d) — 검사기가 살아 있는가

### 위반 주입 4/4 검거 (같은 실행, 202606 패널 `M26_Revenue_Mom` 기반)

| 주입 | 측정 | 검거 |
|---|---|---|
| ① 비트-동일 복제 | rho 1.000000 · maxdiff 0.000e+00 | O |
| ② 단조변환 복제 `exp(z)` | rho 1.000000 · maxdiff **52.35** | O — **rho 로만**. maxdiff 단독 축이면 놓친다 |
| ③ 전건 0 배출 | sd 0.000000 · modal_frac 1.0000 | O |
| ④ 99.5% 동일값 | modal_frac 0.9975 | O |

### 음성 대조 (기확정 결함을 실제로 잡는가)

- `C01_SUE ≡ C10_SUE_Persistence` → **DUP_EXACT_BITWISE** (rho 1.000000 · maxdiff 0.000e+00) ✔
- `C04_ESBR ≡ C13_Revision_Breadth_3m` → **DUP_EXACT_BITWISE** ✔
- `C15_Forecast_Error_Trend` → 축3a 검거, 표본 6/6월 → 전수 **50/50월** ✔

### 양성 대조 (정상 팩터가 정상으로 남는가)

`M26_Revenue_Mom` · `V01_BM` · `M01_Mom_12_1` · `Q02_ROE` · `C18_Earnings_CAR_3d` — 전부 EXACT/RANK 중복쌍 **0** · `quasi_dead` **FALSE**. 전체 331종 중 `modal_frac ≥ 0.99` 인 월이 하나라도 있는 팩터는 **1종뿐** ⇒ 오검거율이 낮다(검사기가 전부를 이상으로 칠하지 않는다).

### ★검사기 고장 자가검출 — "0건"을 결론으로 쓰지 않은 지점

축3의 최초 통계로 `sd(Z_Score_Aligned)` 를 썼더니 **331종 전부 정확히 1.0000**이 나왔고, "죽은 배출 0종"이 산출됐다. 이는 결과가 아니라 **계측 사망**이다 — Z 는 횡단면 표준화 산물이라 sd=1 이 항등이고, 판별력이 원리적으로 0이다. 통계를 `modal_frac` + `커넥터 가시성`으로 교체하자 C15·D60·Q16 이 즉시 드러났다. **작업 명세의 "sd = 0" 축은 Raw_Value 면에서만 유효하고 Z 면에서는 무의미하다** — 아래 설계 제안이 이 구분을 반영한다.

---

## 5. `emission_guard` 정체 검사 축 설계 제안 (e)

> **제안만. 코드 수정·실배선 없음.** 아래는 배선 시의 설계이며, 이 라운드에서 `emission_guard.R` 은 손대지 않았다.

### 5.1 핵심 관찰 — 추가 IO 가 0이다

현행 진입점은 이미 필요한 것을 전부 손에 쥐고 있다:

```
factor_db_builder.R:928   setcolorder(result, c("Date","Ticker","Factor_Name","Raw_Value",
                                                "Z_Score","Z_Sector","Rank_Pct","Coverage"))
factor_db_builder.R:953   .emission_report <- factor_emission_guard(result, ...)
```

그런데 `factor_emission_guard()` 는 첫 줄에서 이것을 버린다:

```
emission_guard.R:218   result[, .(n_rows = .N, n_tickers = uniqueN(Ticker)), by = Factor_Name]
```

**`Raw_Value` · `Coverage` · `Z_Score` 를 그 자리에서 쓰면 세 축이 전부 추가 IO 없이 측정된다.**

### 5.2 제안 축 (전부 warn + 기록. `stop()` 없음 — 설계 원칙 ① 유지)

| 축 | 통계 (`result` 에서 직접) | 판정 | 실측 기대 발화 |
|---|---|---|---|
| **D — 무분산/죽은 배출** | `n_cov = sum(Coverage)`, `raw_sd = sd(Raw_Value)`, `raw_zero_frac` | `n_rows > 0 ∧ n_cov == 0` → `DEAD_EMISSION` | 미선언 1종(C15) + 창-국한 2종(D60·Q16). 시장레벨 15종은 선언으로 면제 |
| **T — 동률/준-죽은 배출** | `modal_frac = max(table(Raw_Value))/n`, `uniq_ratio` | `≥ 0.99` 경고 / `≥ 0.95` 관찰 기록 | 331종 중 1종(C08 1개월) — 오검거 사실상 0 |
| **I — 정체/중복 배출** | 그 달 `result` 안에서 팩터별 **랭크 벡터** 상관 | `\|rho\| ≥ 0.999` ∧ **registry `dedup` 미선언** → 경고 | 139쌍 중 미선언 38, EXACT/RANK 는 **5쌍만** |

**축 I 의 필수 설계점 3가지** (오늘 실측이 각각을 강제한다):

1. **값 차이가 아니라 랭크로 재야 한다.** 주입 ②(단조변환)와 실제 사례 `C09 = sign(sue)·sue²` 는 최대절대차가 각각 52.35 · 1.85 로 크지만 순위는 동일하다. `maxdiff == 0` 단독 축이면 **실제 중복 5쌍 중 3쌍을 놓친다**.
2. **계열(prefix) 안으로 좁히면 안 된다.** `C11 ≡ M25` 는 계열 교차다. 전 × 전 격자 비용이 **월 0.85초**로 실측됐으므로 좁힐 이유가 없다.
3. **선언 대조를 반드시 붙인다.** 대조 없이 쏘면 139쌍이 매달 울리고, 그 소음은 곧 무시된다(가드 설계 원칙 ②가 이미 경고한 실패 양식). 대조를 붙이면 **5쌍**이 남는다.

### 5.3 기준선 래칫 (기존 설계 ③ 답습)

- 시장레벨 상수 15종처럼 **정당한 상수**는 `emission_expected_absent.json` 과 같은 방식으로 `emission_declared_identity.json`(가칭)에 `{factor, axis: D|T|I, reason, diagnosed}` 로 선언 → 선언분은 침묵, **`diagnosed == false` 항목 수는 매 빌드 표시**해 묻히지 않게 한다.
- 축 I 의 기선언은 registry `dedup.cluster` 를 그대로 읽으면 되므로 새 원장이 필요 없다.

### 5.4 함께 고쳐야 배선이 완성되는 것 (별건, 칩 분리 권장)

축 I 를 붙여도 **경고만 늘고 선별은 그대로**다. `drop_alias_factors()` 의 소비자가 0이기 때문이다. 팩터 선별·Ω 추정 진입점에서 canonical 축약을 실제로 호출하지 않으면, 기선언 101쌍은 계속 이중 투표한다.

---

## 6. next_probe (f)

1. **C15/D60/Q16 의 상수값 정체 규명** — `Raw_Value` 가 정확히 0 인지 다른 상수인지. C15 는 `.cons_history()` 가 4분기가 아니라 4영업일을 보는 기전이 이미 지목돼 있다(`sue[1] == sue[2]` → delta 0). D60/Q16 의 2015-01 경계가 2026-08-08 DART 계정명 매칭 수리와 정합하는지 **vintage-swap 통제**로 확인. 소비면 영향: 부채/레버리지 팩터를 쓰는 모든 선별·Ω 추정이 2015~2025 구간에서 **팩터 2종을 빈손으로** 돌렸다.
2. **단조변환 재등록 전수** — `C09` 형(순위 동일·값 상이)이 다른 계열에도 있는지 `Raw_Value` 기준으로 재측정. 오늘 격자는 커넥터 `Z_Score_Aligned` 위였으므로 winsorize(1/99 clip)·±3 clip·재표준화에 가려진 쌍이 더 있을 수 있다.
3. **축 I 경보량 dry-run** — 미선언 38쌍이 실제 월 빌드에서 몇 건 발화하는지 측정 후 문턱 확정(`stage_artifacts/fq163/guard_dryrun_*` 패턴 재사용). 소음이면 무시되므로 문턱은 실측으로 정한다.
4. **`SE02_Consensus_Revision` 자격 재판정** — `modal_frac` 중앙 0.957(27/43월 ≥ 0.95) + 사망 10/53월. 현재 선별 풀에 들어가고 있는지 확인 후 screen 자격 판정.

---

## 7. 산출물 (g)

| 경로 | 내용 |
|---|---|
| `stage_artifacts/infra/factor_emission_identity_20260809/s1_existence.R` (+`s1_existence_by_factor.csv`, `s1_registry_meta.csv`) | 존재 축 — 원장 재판독 |
| `.../s2_identity_liveness.R` (+`s2_identity_verdict.csv`, `s2_identity_pair_months.csv`, `s2_liveness_by_factor_month.csv`, `s2_dead_verdict.csv`) | 정체 축 6월 격자 + 최초(고장난) 살아있음 축 |
| `.../s3_classify.R` (+`s3_identity_classified.csv`, `s3_liveness_stats.csv`, `s3_liveness_verdict.csv`, `s3_invisible_verdict.csv`) | 선언 대조 · 위반 주입 · 양성/음성 대조 |
| `.../s4_scope.R` (+`s4_scope_by_month.csv`) | 의심 팩터 시간 범위 확정 |
| `.../s5_census.R` (+`s5_census_month_factor.csv`, `s5_dead_census_verdict.csv`) | 죽은 배출 61개월 전수 센서스 |
| `.../s6_liveness_full.R` (+`s6_liveness_month_factor.csv`, `s6_liveness_verdict.csv`) | 살아있음 61개월 전수 + 부채 계열 시대분해 |
| `.../s7_fq_read.R` · `s8_fq_register.R` · `FQ_ID.txt` | 큐 등재(번호 = 쓰기 시점 max+1, 재읽기 확인) |
| `06_Registry/alpha_frontier_queue.json` | **FQ-210** 등재 (`frontier_open`) |
| `04_Research/01_reports/factor_emission_identity_audit_20260809.md` | 본 문서 |

**미수행(의도적)**: `emission_guard.R` 코드 수정 · factor_db 재빌드/재계산 · registry `dedup` 갱신 · `05_Production` / `01_Literature` 접근.
