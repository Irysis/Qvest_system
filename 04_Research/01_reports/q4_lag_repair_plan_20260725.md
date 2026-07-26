# XLSX Q4 +45d 수리 계획서 (판정영향 — 코드 변경 전 계획 단계)

- 작성: 2026-07-25 (AST v1.1 SOT §3 판정영향 수리 항목, S3 서브에이전트)
- 상태: **계획서만 — 코드·데이터 무변경** (착수는 §4 조건 충족 후)
- 근거 판정: C4 연간(사업보고서) availability = **익년 3/31 확정** (도훈, 2026-07-25). AST 리프 맵 v0의 "C4 3-way 불일치" 항목의 수리 대상.

## 0. 문제 정의 (실측 확인)

`02_Infrastructure/data/parse_fundamental_xlsx.R:197-199`:

```r
dt[, Period_Date := yyyymm_to_qtr_end(Period)]
# Factor_Date: 분기말 + 45일 (PIT compliance)
dt[, Factor_Date := Period_Date + 45L]
```

전 분기 일률 +45d. Q1~Q3은 KR 분기보고서 법정기한 45일과 정합하나, **Q4(12월 결산 연간)는 사업보고서 기한 90일 → 확정 availability 익년 3/31**. 현행은 Q4 Factor_Date ≈ 익년 **2/14** (실측: XLSX Q4 전 행 lag=45일 단일값) = 3/31 대비 **약 45일 공격적 = 잠재 look-ahead**.

대조 실측: 같은 `fundamental_merged` 안의 DART Q4 행은 lag **90일(616,522행)/91일(229,121행)** — DART 파이프라인은 이미 3/31 규약과 정합. 불일치는 XLSX 계열(raw + derived)에만 존재.

## 1. 영향 범위 실측 (fundamental_merged.parquet, 2026-07-25 실행)

측정 스크립트: scratchpad `measure_q4.py` (pyarrow, read-only). 전체 5,427,832행 (XLSX 4,133,534 / DART 845,643 / xlsx_derived 448,655).

### 1.1 Source=XLSX · Q4(Period 말월=12) — dedupe 이후 merged 기준 생존

| 항목 | 실측값 |
|---|---|
| 행수 | **1,157,230** |
| Period_Date 범위 | 2000-12-31 ~ 2025-12-31 |
| Factor_Date 범위 | 2001-02-14 ~ 2026-02-14 (전 행 lag=45d) |
| 종목 | 3,559 unique |
| Item | 41 unique |
| 연도 분포 | 2000~2014: 연 56k~82k행 (41개 item 전량) / 2015+: 연 5.4k~6.3k행 |

추가: **Source=xlsx_derived Q4 = 111,174행, 전 행 lag=45d** — 파생 item도 parse 캐시의 Factor_Date를 그대로 상속(`build_fundamental_derived.R:46` xlsx_long에서 계승)하므로 동일 노출.

### 1.2 DART 우선 dedupe 이후의 실질 노출 구조 (§2(c) 실측 답)

DART 커버리지는 **Period 2015-12부터** 시작(실측 min 2015-12-31). 따라서:

- **2000~2014 (15개년): XLSX Q4 41개 item 전량 생존 = 1,095,004행** — dedupe가 전혀 보호하지 못하는 구간. 노출의 94.6%.
- 2015: 6,298행 (전환기 잔존)
- **2016+ 생존분 = 55,928행, item 단 2종: SBB(27,969) + ISSD(27,959)** — DART가 커버하지 않는 자사주매입·발행주식수만 잔존.

**결론: "DART 우선이라 실질 노출이 적다" 가설은 2016+ 구간에만 성립. pre-2015 역사 전체(백테스트 2005~ 구간의 2005~2014 10개년 포함)가 41개 item 전량 노출 — (c) 단독으로는 수리 불가.**

### 1.3 소비 factor_registry 엔트리 (373 중)

`data_source` 실측 분포: rawdata 167 / **fundamental 99** / consensus 33 / **fundamental_xlsx 25** / investor_flow 15 / price 15 / macro 14 / macro_fred 5.

- **fundamental_xlsx 25종 (전량 xlsx-기원)**: XF_DU01~03, XF_LL01~05, XF_PR01~05, XF_EF01~04, XF_GD01~04, XF_RI01~03, XF_Q06_Op_Margin. 소비 경로 2원화: `xlsx_factor_calculator.R:84-89`가 **fundamental_xlsx.parquet 직접 read**(FUND 우회) + `compute_quality_xf_native.R:31`이 FUND 경유 — 양쪽 모두 `Factor_Date <= sig_d` 필터.
- **fundamental 99종**: `factor_db_builder.R:131` → fundamental_merged를 `.pit_fund()`(:389, `Factor_Date <= sig_d`)로 소비. **pre-2015 구간에서는 99종 전부가 xlsx-기원 Q4 행을 소비** (해당 구간 대체 소스 부재). 2016+에는 SBB/ISSD 파생 팩터만 xlsx-Q4 소비.
- **대표 팩터 5종**: ① V01_BM ② V02_EP ③ Q01_GPA (이상 fundamental — pre-2015 역사 전체 xlsx-기원) ④ V11_Shareholder_Yield (2016+에도 SBB 경유 잔존 노출; 유사 Q20/IN04_Net_Equity_Issuance = ISSD) ⑤ XF_Q06_Op_Margin (fundamental_xlsx 직접 경로).

## 2. 수리안 비교

### (a) parse 단계: Q4만 3/31로 상향 — **권고안**

`parse_fundamental_xlsx.R:199`를 조건부로: Period 말월=12 행만 `Factor_Date := as.Date(paste0(year(Period_Date)+1, "-03-31"))`, 나머지 분기는 +45d 유지. (+90d 산식은 윤년에 3/30~3/31로 흔들림 — DART의 90/91d 혼재가 그 증거. **명시적 3/31 고정**이 규약과 정확 일치.)

- 장점: **단일 상류 지점 수리로 전 하류 전파** — fundamental_xlsx.parquet(→ xlsx_factor_calculator 직접 경로), fundamental_xlsx_ttm.parquet, xlsx_derived(Factor_Date 상속), fundamental_merged 전부 재생성 시 자동 정합. dedupe 키(Ticker+Item+Factor_Date의 DART-overlap 제거 :463-467, 및 Ticker+Period+Item 우선순위 :484-490)도 새 날짜 기준으로 일관 재계산.
- 단점: parse → build_fundamental_derived → factor DB 재빌드 체인 필요 (§3).
- 부수 정합: DART-overlap 제거(:465)가 Factor_Date 키를 쓰므로, XLSX-Q4가 3/31이 되면 DART 연간(90/91d≈3/31~4/1)과 키가 근접·일부 일치하게 되어 중복 제거가 오히려 개선됨(현행은 2/14 vs 3/31로 키 불일치 — Period 키 dedupe에서만 잡힘).

### (b) 빌더 소비 단계 가드

`.pit_fund()`(factor_db_builder.R:389) 또는 FUND 로드 시 XLSX/xlsx_derived ∧ 말월=12 행에 유효일 = Period_Date+90d(또는 3/31) 적용.

- 장점: 캐시 파일 무변경, 빌더만 수정.
- **결격 사유 (실측)**: `xlsx_factor_calculator.R`이 fundamental_xlsx.parquet을 **FUND 우회 직접 read**(:84) — 가드 지점이 최소 2곳으로 분산되고, 향후 신규 소비자가 생기면 조용히 누락되는 구조적 위험. 또한 저장 캐시의 Factor_Date가 계속 거짓말을 하게 되어 AST field map·감사가 이중장부화됨. **기각 권고.**

### (c) 무수리(dedupe 의존)

§1.2 실측으로 **기각**: pre-2015 15개년 · 1.09M행 · 99+25 팩터 전량이 dedupe 밖. 2016+만이라면 SBB/ISSD 2종 국소였겠으나 역사 구간이 본체.

## 3. 재빌드 파급 + A/B 프로토콜

### 3.1 재빌드 범위

수리 시 값이 바뀌는 factor DB 스냅샷 = **Q4 가시성이 달라지는 sig_date 창 [2/14, 3/31)** 에 걸리는 월말 스냅샷 = **매년 2월말 1개** (3월말은 3/31 inclusive로 Q4 가시 유지 → 불변). 실측 파일 기준:

- 월간 factor DB: `.cache/factor_db/factor_db_YYYYMM.parquet` **439개** (1990-01~2026-07).
- 최소 재빌드 집합 = 2001-02~2026-02의 2월 스냅샷 **26개**. 보수 집합(3월 경계 검증 포함) = Feb+Mar **52개** (실측 파일 수 확인).
- 단, dedupe 키 변화(§2a 부수 정합)로 2월 외 월도 이론상 미세 변동 가능(DART-overlap 제거 행 변화) → **권고: 전기간 재빌드로 통일** (비용이 낮아 부분 재빌드의 검증 부담을 상회함, 아래 실측).

### 3.2 예상 소요 (실측 근거)

- **월간 빌더 실측 (2026-06-10 전기간 재빌드의 파일 mtime 간격)**: 1990-01(14:26:20) → 2025-04(14:34:50) = 424개월 / 8.5분 ≈ **월당 ~1.2초**. 인접 파일 간격 실측 1.4~1.8초/월. → **전기간 439개월 ≈ 10~15분** (모듈 preload 포함), 부분 52개월 ≈ 1~2분.
- 상류 체인: parse_fundamental_xlsx + build_fundamental_derived — 과거 단독 실행 소요 미기록. **착수 시 실측 후 본 문서에 기입** (derived는 19M행 처리라 수십 분 가능성, 검증 안 됨 (가정)).
- **fdb_daily (일간 DB)**: phase6/7/8이 fundamental_merged 소비 (grep 실측) → 일간 전량 재빌드 필요 = **~48분 (기존 실측, `run_fdb_rebuild.sh` — memory: project-fdb-daily-rebuild-procedure)**. 단일월 증분은 bit-parity 미달 이슈가 있으므로 전량 재빌드 경로 사용.
- 파생 캐시 후속: factor_ic_monthly.parquet, z-winsorize 마커(`_rebuild_z_markers`) 등 factor DB 하류 캐시 재생성 확인 목록에 포함.

### 3.3 Graduation 판정 변동 위험 + A/B 프로토콜 (measurement-graduation §7 정합)

위험 기전: 2월말 리밸런스 시점의 fundamental 팩터 값이 Q4→Q3 데이터로 후퇴 → 연 12회 중 1회의 보유구성 변화가 PORT_t/oos_retention/calmar를 이동시킬 수 있음. 방향 예상: 현행이 look-ahead 우위이므로 수리 후 **소폭 약화 또는 중립** (예상 — A/B로 실측 확정). 캐시 재생성이 판정 tipping을 유발한 실사고 전례(F5 SR 2.224→2.161) 있으므로 §7 Vintage Pinning 의무 적용:

1. **사전 pin**: 재빌드 전 `pin_cache`(02_Infrastructure/data/pin_cache.R)로 현행 factor_db 월간 스냅샷(최소 Feb/Mar 52개 + 대조에 쓸 전 구간)과 fundamental_merged를 `.cache/pins/` 스냅샷 고정, pin tag 기록.
2. **shadow 빌드**: 수리판 산출은 임시 디렉터리(temp-rename 패턴, arrow mmap 잠금 회피)에 생성 — canonical 경로 교체는 A/B 판정 후.
3. **A/B 대조 (pinned old vs shadow new, 동일 코드·동일 유니버스)**:
   - 팩터 레벨: 대표 5종(§1.3) + SBB/ISSD 파생(Q20/IN04/V11)의 2월 스냅샷 값 diff 행수·분포, rank 상관.
   - 전략 레벨: `canonical_screen_bt()`로 대표 팩터 top-25 EW PORT_t(NW lag-3)·oos_retention·calmar 전후 대조 — HARD 3종 경계(2.95/0.7/0.64) 통과 상태가 뒤집히는 팩터 목록 산출.
   - book 레벨: incumbent base는 §7b대로 **05_Production 현행 코드 실산출**(read-only 실행)로만 — 저장 패널 재사용 금지. STR_1715_on_M4_R05_noLayer4_PG2 신호 경로가 fundamental 팩터를 소비하는지 확인 후 해당 시 book PORT_t 전후 대조.
4. **판정·기록**: 뒤집힘 발생 시 해당 전략/팩터 목록 + 방향을 도훈 보고 후 canonical 교체. 산출물에 pin tag + `metric_type` 라벨 명기. 구 스냅샷은 pin 보존(비교 재현성).

## 4. 권고 순서 + 착수 조건

권고안: **(a) parse 단계 Q4=3/31 고정** ((b) 기각 — 소비 경로 2원화 실측, (c) 기각 — pre-2015 1.09M행 비보호 실측).

실행 순서 (착수 승인 후):

1. pin_cache 스냅샷 + pin tag 기록 (§3.3-1)
2. parse_fundamental_xlsx.R:199 조건부 수정 (Q4→익년 3/31, Q1~Q3 +45d 불변; 12월 외 결산월 항목은 존재 시 별도 확인 — Period 말월=12만 대상이므로 보수 방향)
3. parse 재실행 → build_fundamental_derived 재실행 (소요 실측 기입) → merged 검증: XLSX/derived Q4 lag=90±1일·행수 보존·dedupe 행수 변화 기록
4. factor DB shadow 전기간 재빌드 (~10~15분 실측 근거) + fdb_daily 전량 재빌드 (~48분 실측 근거)
5. A/B 프로토콜 (§3.3-3) → 결과 보고
6. 도훈 confirm 후 canonical 교체 + AST field map v1.1 C4 항목 현행화 + factor_registry `lag_rule` 주석 갱신

**착수 조건 — 도훈 confirm 필요 여부: 필요 (판정영향 항목).** 근거: ① graduation HARD 판정 입력(factor DB)이 바뀌는 canonical 캐시 변경 = measurement-graduation §7 pin 의무 + 판정 tipping 전례 ② book 대조가 §7b production 경로를 소비 ③ AST v1.1 SOT의 판정영향 분류 자체가 confirm 게이트. **본 계획서 승인(수리안 (a) + 전기간 재빌드 + A/B 프로토콜) 후에만 코드 변경 착수.**

잔여 확인 항목 (착수 시):
- parse/derived 단독 실행 소요 실측 (§3.2 미기록)
- 12월 외 결산 기업의 Period 라벨 semantics 확인 (현 수리는 Period 말월=12 한정 — 보수 방향이나 명시 검증)
- factor_ic_monthly 등 하류 캐시 재생성 목록 전수 (cache_registry.json 대조)

---

## §5 실행 결과 (2026-07-25 도훈 "전부승인" 집행 — wf_1c333719 Q4 + 체인 v2, 전 수치 실행 실측)

**집행**: §2(a) 그대로 — parse_fundamental_xlsx.R:205-209 Q4(말월=12)만 익년 3/31 명시 고정(fifelse, 윤년 ±1일 흔들림 회피), Q1~Q3 +45d 불변. pin 59파일 1.16GB(.cache/pins/q4_pre_20260725).
**정합 실측**: XLSX-Q4 1,157,230행 + derived-Q4 111,174행 전량 3/31(lag 90/91d) · 비-Q4 3,313,785행 45d 불변 · DART 불변 · fundamental_merged 총행 5,427,832 구본과 동일.
**재빌드 실측 소요** (§3.2 기입): parse 146s · derived 51s · **월간 전기간 439개월 ≈ 7.9시간**(13:05~21:01 — §3 추정 10~15분은 대오차: 초기 월 ~10s/월이 후기 월 ~67s/월로 증가, ETA 산정 시 후기 페이스 기준 필수) · IC 재계산 포함 · **fdb_daily 46분**(21:02~21:48, 439파일) · A/B+diff 8분.

**A/B canonical (old=pinned 구DB / new=수리 후, 259개월, metric_type=canonical_screen)**:

| 자산 | PORT_t old→new | Δ | HARD 2.95 교차 |
|---|---|---|---|
| V01_BM | 1.935 → 1.897 | −0.038 | 무 |
| V02_EP | 2.364 → 2.461 | +0.097 | 무 |
| Q01_GPA | −0.647 → −0.757 | −0.110 | 무 |
| V11_Shareholder_Yield | 0.005 → −0.041 | −0.046 | 무 |
| XF_Q06_Op_Margin | 0.788 → 0.568 | −0.219 | 무 |
| BOOK_STR1715_composite | 0.874 → 0.728 | −0.147 | 무 |

**판정 tipping = 0건 확정** — 6자산 전원 old/new 모두 HARD 미달 유지, "통과→미달"·"미달→통과" 어느 방향도 없음. 변화는 소폭·혼합이며 look-ahead 제거의 기대 방향(대체로 약화)과 정합 — 구 수치에 소량의 상방 편향이 있었음을 실증.

**팩터 레벨 diff 귀속** (snapshot_diff 52개월 + 상세): 변경 극단(rank corr 음수 −0.57~−0.26)은 **전부 재무-성장 계열의 pre-2015 FEB 스냅샷**(XF_GD04_Dividend_Growth·GR06/XF_GD03_OCF_Growth·GR01/Q21_Revenue_Growth·Q34/XF_GD01_GP_Growth 등) — §1 노출 본체(pre-2015 XLSX-Q4 1,095,004행) 예측과 정확 일치하는 look-ahead 제거 서명. 기전: FEB 시점에 old는 확정 연간실적(2/14~)을 봤고 new는 전년 Q3까지만 → YoY 기준분기 변경으로 순위 재배열. 가격계(M/D/L/R/MA)는 median rank corr 0.99+ 사실상 불변(정합). MAR 스냅샷은 2003+부터 변경 ~91-93팩터로 축소(3월말 sig≥3/31이면 양측 동일 가용 — 기대 정합).
**잔여 귀속 1건**: C(consensus) 계열 저상관(median 0.17)은 Q4 수리 외 **입력 드리프트 혼입 의심**(동일자 컨센서스 캐시 07-01→07-24 확장 — 벤더 소급수정 감지 불가 구조, §0 caveat ④) — 분리 귀속은 후속 확인 항목.

**후속 정합 완료**: registry fundamental 124엔트리 availability rule=`quarterly+45d;annual_3/31` 정규형 + known_discrepancy 해소(2사본 동기) · validator EXPECTED/DOMAINS_REQUIRING_KD 현행화 → **전체 PASS**. pit.md C4는 기확정(3/31). 구 vintage 소비 필요 시 pin 경로 사용.
