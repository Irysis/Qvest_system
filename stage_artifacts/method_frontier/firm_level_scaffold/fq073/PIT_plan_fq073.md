# FQ-073 PIT 규약 — 관세청 HS 수출 → KR 종목/섹터 tilt

**대상**: FQ-073 (관세청 품목별 수출입실적 15101609 · data.go.kr 1220000)
**적용 규칙**: `.claude/rules/pit.md` C1~C15 (특히 **C5 오버레이 타이밍**) + `measurement-graduation.md` §1/§3/§7 + `backtest-contract.md`
**승계**: FQ-064/065 `PIT_plan.md` §2 first-release vintage 보존 규약을 그대로 승계·확장
**상태**: 데이터 게이트(HTTP 403, 활용신청 미승인) 前 **계약 사전확정**. 러너 배선 완비 — 승인 시 STEP 1 pull만 채우면 1커맨드 측정.
**작성**: 2026-07-25

---

## §0 데이터 접근 상태 (게이트 사실관계)

| 항목 | 실측 |
|---|---|
| 엔드포인트 | `https://apis.data.go.kr/1220000/Itemtrade/getItemtradeList` |
| 현재 상태 | **HTTP 403 `Forbidden`** — 1220000 활용신청 미승인 |
| 키 유효성 | 유효 (위조키=401 vs 우리키=403 차별화 + 동일 키로 B552015·1230000 HTTP 200) |
| 필수 파라미터 | `serviceKey`, `strtYymm`, `endYymm` (`hsSgn` 옵션) |
| 구조 제약 | 조회기간 **1년 이내** · 페이지네이션 파라미터 없음 |
| 역사 depth | **미측정** (403). `fq073_probe_after_approval.py` 1회 실행으로 판정 |

★ depth 미확인은 PIT 리스크가 아니라 **측정가능성 리스크**(n_months·OOS 분할). §6-1 참조.

---

## §1 발표시차 실측 — 2단계 vintage (문서 원문 HTTP 200 근거)

측정 스크립트: `fq073/probe_publication_lag.py` · `fq073/probe_first_release.py`
증거 저장: `fq073/publication_lag_evidence.json` · `fq073/first_release_evidence.json`

### (a) 최초공표 = 익월 1일 (잠정치)

> "공표 주기와 제공범위: 주기 10일. 범위와 시기 1일~10일 통계는 11일에 제공, 1일~20일 통계는 21일에 제공, **1일~말일 통계는 익월 1일에 제공** ※ 수출입 신고의 정정, 취하 등 변경내역을 반영하여 전월까지의 자료를 현행화하되, **당월통계는 잠정치 기준으로 작성**"
> — data.go.kr 15157901 상세페이지, **HTTP 200** (165,746 bytes)

### (b) 개정(현행화) = 매월 15일경, 주기 1개월, **무기한 반복**

> "**매월 15일경 수출입 신고의 정정, 취하 등 변경내역을 반영하여 전월까지의 자료를 현행화**하고 있으며 주기는 1개월입니다."
> — data.go.kr **15101609**(타깃) / **15100475** / **15102108** 3개 데이터셋 상세페이지, **전부 HTTP 200 동일 문장**

### (c) 확정 타임라인

| 단계 | 시점 | 성격 |
|---|---|---|
| 잠정(first release) | data_ym **M+1월 1일** | 당월통계 = 잠정치 |
| 1차 현행화 | **M+1월 15일경** | 정정·취하 반영 |
| 계속 현행화 | M+2, M+3, … 매월 15일경 | "전월까지의 자료" 전체 refresh = **개정 종료일 없음** |

★ **개정은 종료되지 않는다**. "전월까지의 자료를 현행화"는 매월 과거 전체를 다시 덮어쓴다는 뜻이므로, 임의 과거월 값도 이후 재개정 가능. 이것이 §2 first-release 보존이 선택이 아니라 의무인 이유.

### (d) 미확정 1건 (정직 라벨)

15101609(품목별 수출입실적, **우리 타깃**) 상세페이지에는 최초공표일 문장이 **없다**. (a)의 "익월 1일"은 형제 데이터셋 15157901 문구를 원용한 것. → 타깃의 최초공표일 직접 근거는 **미확보**. 대응 = §3의 보수 lag가 이 불확실성을 흡수(잠정/확정 어느 쪽이든 스케줄 동일 — §3-c 증명).

---

## §2 first-release vintage 보존 (FQ-064 PIT_plan §2 승계 + 확장)

### (a) 구조적 한계 — 정직 서술

API에 **vintage 파라미터가 없다**. 오늘 pull하면 전 역사가 **최신 개정판(latest revised)** 으로 반환된다. 2015년 1월 수출값의 2015년 2월 시점 first-release는 **소급 복원 불가**.

→ 역사 백필로 만든 백테스트는 **개정판 기반**이며, 개정이 사후 정보(정정·취하 확정)를 담는 한 **원리적으로 미세한 미래참조를 포함**한다. 이것은 러너가 없앨 수 있는 버그가 아니라 **원천의 성질**이므로, 은폐하지 않고 라벨로 고정한다.

### (b) 강제 규약 (러너가 fail-closed로 강제)

1. **라벨 의무**: 모든 산출물에 `vintage_basis` 필수.
   - `revised_asof_pull` — 역사 백필(현 상태). 게이트 판정 시 **"개정-vintage 상한"** 으로만 해석.
   - `first_release` — 아래 (c) 스냅샷 스토어에서 재구성된 구간.
   - 라벨 부재 시 러너 **stop**.
2. **덮어쓰기 금지**: 신규 pull이 과거월 값을 **수정하지 않는다**. 매 pull은 `vintage_store/customs_hs_<PULLDATE>.parquet` 로 **append-only 스냅샷**.
3. **pin tag 기록**: HARD 게이트 판정·다중라운드 A/B는 고정 스냅샷 기준 + pin tag 산출물 기록 (measurement-graduation §7, [[project-cache-vintage-pinning]]).

### (c) 개정 크기 실측 설계 (지금 배선, 승인 후 자동 축적)

- **전향 축적**: 월 1회 pull → 스냅샷 2개 이상 확보 시 동일 `(hs_code, data_ym)` 값 차분 → 개정폭 분포 실측. `revision_magnitude.json` 산출.
- **즉시 부분 추정 (승인 즉시 가능)**: 15157901(수입 10대품목 10일 잠정치)의 `1일~말일` 잠정값 vs 15101609 확정값 대조 → 잠정↔확정 괴리 실측. 수입·10품목 한정이나 개정폭 **크기 order**를 즉시 준다.
- 개정폭이 신호 분산 대비 유의하면 → PRIMARY lane을 `first_release` 축적 구간으로 제한(측정기간 단축 감수).

---

## §3 C5 오버레이 타이밍 규약 (핵심)

`.claude/rules/pit.md` §오버레이 신호 타이밍 + `02_Infrastructure/validation/overlay_pit_guard.R`

### (a) 불변식 (한 줄)

> **홀딩월 H의 신호는 수출 데이터월 H−2 까지만 쓴다. 스코어는 H−1 의 거래 월말에 배치한다.**

### (b) 도출

| 기호 | 정의 |
|---|---|
| `data_ym = M` | 수출이 실제 발생한 캘린더 월 |
| `usable_date(M)` | `M+1월 15일` (1차 현행화 완료 = 확정 lane) |
| `score_date` | 스코어를 얹는 **거래 월말** |
| `holding_start` | 홀딩월 첫날 = `holdings_signal_cutoff(score_date)` (= month(score_date)+1 의 1일) |

`score_date = month-end(M+1)` 로 두면:
- `holding_start = (M+2)월 1일`
- `usable_date = (M+1)월 15일` **<** `holding_start` → 버퍼 **실측 14~17일** ✓
  (2026-07-25 배관 실행 실측: `buffer 14~17일`. 2월 = 14일(최소), 1·3·5월 = 17일(최대))
- 즉 **홀딩월 H = M+2**, 뒤집으면 **M = H−2**.

### (c) "잠정치를 쓰면 한 달 빨라지나?" — **아니다 (증명)**

월말 리밸런스 cadence에서 data_ym M을 쓸 수 있는 가장 이른 거래 월말은 `month-end(M+1)` 이다. 잠정(M+1월 1일)이든 확정(M+1월 15일)이든 **둘 다 그 월말 이전**이라 스케줄이 동일하다. 반대로 `month-end(M)` 시점엔 M 데이터가 아직 없다(최초공표 M+1월 1일).
→ **잠정/확정 구분은 타이밍 arm이 아니라 vintage arm**이다(§2). 타이밍은 확정 lane 하나로 유일하게 결정된다. §1-d의 미확정(최초공표일)이 결론을 바꾸지 못하는 이유도 이것.
→ 진짜 적시성 arm은 **순별 잠정(1~10일 / 1~20일)** 뿐이며(15157901 = 수입 10품목 한정), 수출 등가물 미확보 → **FQ 후속 arm으로 등재, 본 러너 미구현**.

### (d) 러너 강제 (HARD)

```r
source("02_Infrastructure/validation/overlay_pit_guard.R")
holding_start <- holdings_signal_cutoff(score_date)          # month(score_date)+1 의 1일
assert_overlay_pit(usable_date, holding_start, "FQ073")      # HARD stop
stopifnot(as.integer(holding_start - usable_date) >= MIN_BUFFER_DAYS)   # 기본 10일, 추가 강화
```

`assert_overlay_pit`은 `u > h` 만 차단(등호 통과)하므로, 등호-경계(razor edge)를 막기 위해 **MIN_BUFFER_DAYS(기본 10) 추가 게이트**를 러너가 자체 부과한다. 확정 lane 실제 버퍼 ≈ 16일 → 통과.

### (e) 의무 스트레스 2종

1. **LAG1 스트레스** (`.claude/rules/pit.md` C5 의무 2): `LAG_EXTRA=1` → 데이터월 H−3. base 대비 붕괴 시 동월 누출 의심. **PRIMARY와 항상 동반 실행**(러너 강제).
2. **strict-PIT A/B** (C5 의무 3): 본 케이스에선 (c)에 의해 타이밍 A/B가 성립하지 않으므로, **vintage A/B**(`revised_asof_pull` vs `first_release`)로 대체한다. `first_release` 스토어 축적 전에는 **실행 불가**로 정직 라벨(`ab_status="deferred_vintage_store"`) — "통과"로 기록 금지.
3. 보조: `score → forward-ret` IC 부호 양수 확인(윈도우 의미 실증, C5 의무 4).

---

## §4 HS → 종목 매핑의 PIT (2단 firm-level의 진짜 관문)

관세청 API는 **사업자·법인 식별자를 일절 반환하지 않는다**(관세법상 비공개). 종목-레벨은 전적으로 **자체 crosswalk 품질**에 종속된다.

### (a) ARM_S (1단, 섹터 tilt)

- `hs2 → Sector` 개념 concordance (러너 내 선언·CSV emit, FQ-066 `sector_ppi_map.csv` 선례).
- 매핑 자체는 **시점-불변 개념 대응**(HS 85 = 전기기기)이라 look-ahead 없음.
- 단 **HS 내 가중치**는 시변: 섹터 내 HS 비중 = **trailing 12M 수출액 비중, 데이터월 ≤ M 만 사용** → PIT-clean (전방 비중 사용 금지).

### (b) ARM_F (2단, 종목-레벨) — 매핑 자체가 PIT 대상

원천 = DART 사업보고서 "사업의 내용 / 제품별 매출". **2024년 제품믹스로 2015년 수출을 귀속하면 C1/C3 위반**(전기간 동일 믹스 = full-sample 정보).

강제 스키마 `maps/hs_firm_map.parquet`:

| 컬럼 | 의미 |
|---|---|
| `Ticker` / `hs_code` / `weight` | 귀속 비중 (Ticker별 Σweight = 1) |
| `disclosed_date` | 해당 사업보고서 **제출일**(DART 접수일) |
| `effective_from` | 관측가능일 = `disclosed_date`. 미상 시 C4 보수규약(annual = 사업연도+5월) |
| `source` | rcept_no 등 추적자 |

- **as-of join 의무**: `effective_from <= score_date` 인 것 중 **가장 최근 vintage 1건**만. 미래 vintage 참조 = 즉시 stop.
- `effective_from` 컬럼 부재 또는 전 행 동일(=static) → 러너가 `map_vintage_mode="static_current"` 라벨을 강제로 붙이고 **게이트 판정 금지**(진단 상한으로만 보고). fail-closed 아님(진단은 허용), 그러나 graduation 라인 진입 차단.

### (c) 귀속 왜곡 — 실측 census 의무 (승인 후)

1. **해외생산 누락**: 현대차 미국공장·삼성 베트남 수출은 KR 통관에 없다 → 대형주 커버리지 구조적 결손.
2. **상사 명의 수출**: 종합상사가 타사 제품을 자기 명의로 통관 → HS는 잡히나 귀속 firm이 틀림.
3. **위탁/중계무역**: 통관 주체 ≠ 이익 귀속 주체.
4. **HS 집중도**: 단일 HS 의존 firm(반도체·조선)만 clean, 다각화 firm은 희석.
→ `firm_map_census.json` 에 커버리지%·집중도(HHI)·미매칭 대형주 목록 산출 의무. 커버리지 편향이 비랜덤(대형주 편중 결손)이면 결과 해석에 반영.

### (c-2) 병행 세션 산출물 `firm_hs_crosswalk.parquet` 과의 접속 — ★현재 **게이트 부적격**

같은 디렉터리에 병행 세션이 구축한 `fq073/firm_hs_crosswalk.parquet` 이 실존한다(2026-07-25 실측). ARM_F 의 자연스러운 입력이나, **현 스키마로는 자본 게이트에 쓸 수 없다**. 실측 진단:

| 항목 | 실측값 | 판정 |
|---|---|---|
| 행 수 / Ticker | 474행 / 474종목, **ticker당 최대 1행** | **vintage 차원 없음 = 정적 현재-믹스** |
| `effective_from` | **부재** | 러너가 `map_vintage_mode="static_current"` 강제 → `gate_eligible=FALSE` |
| `dart_rcept_dt` | 474/474 non-null, 범위 **2023-08 ~ 2025-12** | 전부 최근 공시. 이 믹스로 2010년 수출을 귀속 = **C1/C3 위반** |
| HS 컬럼 | `hs4`(418 non-null) + `hs4_secondary`(196) | 러너 기대 `hs_code` 와 이름 불일치 |
| 가중치 | `weight` 컬럼 부재 (`explicit_shares` 323사 파싱됨) | 러너 기대 `weight` 부재 |
| 품질 라벨 | confidence A 290 / B 116 / X 53 / T 15 | X·T(비교역·중계상) 제외 규칙 필요 |

**게이트 적격화 조건 (그대로 실행하면 통과)**:
1. **vintage 전개**: ticker당 1행 → **(Ticker, hs_code, 사업보고서 연도) 다행**으로 확장. 각 연도 보고서의 접수일을 그 행의 `effective_from` 으로. 현재 `dart_rcept_dt` 는 *최신 1건*만이라 과거 연도 보고서를 추가 pull 해야 한다.
2. **컬럼 정합**: `hs4` → `hs_code`, `explicit_shares` → `weight`(Ticker별 Σ=1 정규화). 명시 share 없는 firm은 primary/secondary 고정비중(예: 0.7/0.3) 선언 + 라벨.
3. **품질 필터**: `confidence ∈ {A, B}` 만 채택, X/T 제외(비교역·중계상 = 귀속 왜곡 원천, §4-c-2/3).

★ 위 3건 완료 전까지 ARM_F 산출은 **진단 상한**이며, 러너가 자동으로 `gate_eligible=FALSE` + caveat 을 붙인다. 정적 맵을 그대로 넣고 "종목-레벨 검증 완료"로 보고하는 것이 본 규약이 막으려는 바로 그 실패다.

### (d) 유니버스 축소 (ARM_S 구조적 결과)

27개 RAWDATA 섹터 중 재화수출과 대응되는 것은 약 15개. 은행·증권·보험·통신서비스·소프트웨어·미디어 등은 **매핑 없음 → 스코어 NA → 선택 유니버스에서 제외**. 이는 버그가 아니라 신호의 정의역이며, **선택 유니버스 축소(=집중도 상승)를 산출물에 명시**한다(`n_sectors_mapped`, `univ_coverage_pct`).

### (e) 동률 처리 (ARM_S) — FQ-066 대비 개선점

섹터 스코어는 섹터 내 전 종목에 동일하게 부여되므로 top-25 선택에 **대량 동률**이 발생한다. FQ-066은 이를 `setorder(Date, -score)` 의 안정정렬 순서(=사실상 임의)에 맡겼다 — 숨은 선택 편향.
본 러너는 tie-break를 **사전등록 파라미터**로 노출한다:
- `neutral_hash` (**기본**) — 고정 seed 결정적 해시. 섹터 신호만 측정, 크기·유동성 베팅 혼입 없음. **다중 seed 로버스트니스 의무**.
- `size_desc` — 대형주 우선. [[project-captier-alpha-localization-20260706]] cap-w 트랩에 직결되므로 **기본 금지**, 로버스트니스 arm에서만.
- `liq_desc` — 유동성 우선.
`diag_dual_basis=TRUE` + `size_dt` 전달로 **cap-tier 분해 병기 의무**([[feedback-qepm-method-frontier-dualization]] risk `cap_tier_decomposition`).

---

## §5 ARM 사전등록 + selection_type (DSR 경계)

`measurement-graduation.md` §3 DSR 적용경계 = **sweep형 selection에서만**.

| ARM | 정의 | 역할 |
|---|---|---|
| **`S_3M`** | 섹터 tilt · 3M YoY · neutral_hash · LAG_EXTRA=0 | **PRIMARY (사전등록 단일 스펙)** |
| `S_3M_LAG1` | 동일 + LAG_EXTRA=1 | **의무 스트레스** (§3-e) |
| `S_6M` | horizon 6M | 로버스트니스 |
| `S_3M_seed*` | tie-break seed 변경 | 로버스트니스 (동률 편향 통제) |
| `S_3M_size` | tie-break=size_desc | 로버스트니스 (cap 편향 노출) |
| `F_3M` | 종목-레벨 HS 가중 | 2단 (map 존재 시) |

**규약**: PRIMARY는 착수 前 고정된 단일 스펙 → `selection_type="chain"`. 로버스트니스 arm 중 **argmax를 최종안으로 고르는 순간 `selection_type="sweep"` 으로 재분류되고 DSR ≥ 0.5 HARD가 부활**한다. 러너는 실행된 arm 수(`n_arms_run`)와 선언 라벨을 산출물에 기록해 사후 감사를 가능하게 한다.
HARD 게이트(불변): `portfolio_alpha_t_nw` ≥ 2.95 · `oos_retention` ≥ 0.7 · `calmar` ≥ 0.64 — **cap-w 벤치 basis 단일 권위**. EW-유니버스/cap-tier는 병기 진단(비바인딩).

---

## §6 잔여 리스크 (승인 후 실측 검증 항목)

1. **역사 depth 미확인** — 403으로 미측정. FQ-073 요구선(2010+ 월별) 충족 여부 미검증. `fq073_probe_after_approval.py` 1회로 판정. 미달 시 n_months·OOS 3분할 성립 불가 → 측정 자체 재설계.
2. **개정-vintage 백필** (§2-a) — 정량 불가. 스냅샷 축적으로만 해소. 그 전까지 `revised_asof_pull` 상한 라벨.
3. **최초공표일 직접근거 부재** (§1-d) — §3-c 증명으로 스케줄 무영향. 단 순별 잠정 arm 설계 시 재확인 필요.
4. **HS 코드 체계 개정** — HS 2012/2017/2022 판 개정으로 6자리 코드가 신설·폐지·재편된다. 장기 시계열에서 `hs_code` 단위 YoY가 **코드 단절로 인한 가짜 증감**을 만든다. 대응 = (i) HS 2자리(chapter) 기준을 PRIMARY로(개정 영향 최소) (ii) 6자리 사용 시 concordance 필수 (iii) 러너가 `hs_code` 신설/소멸 월을 census 하여 단절 후보 리포트.
5. **환율 혼입** — `expDlr` = USD 기준. KR 종목 실적은 KRW. USD 기준 YoY는 원화절하기에 수출 증가를 과소평가한다. PRIMARY = USD 기준 유지(원천 그대로), KRW 변환은 별도 arm(ECOS 환율 필요, 그 자체가 또 하나의 발표시차 원천 → 미도입).
6. **survivorship (C6)** — `firm_crosswalk.parquet` 은 2023+ 유니버스 합집합(474사) 기반이라 과거 상장폐지사 결측. ARM_S는 RAWDATA `K200/KQ150` 시점 플래그로 필터하므로 영향 없음(표준 `build_monthly_forward_returns` line 39). **ARM_F는 crosswalk 의존 → C6 노출** → delisted corp_code 보강 전까지 ARM_F 결과에 `survivorship_exposed=TRUE` 라벨.
7. **결측월 처리** — API는 실적 있는 (hs, ym) 행만 반환. 활동구간 **내부** 결측 = 실적 0으로 채움, 구간 **밖**(신설 전/폐지 후) = NA. 이 규약이 YoY 분모를 좌우하므로 러너에 명시 + 소액 분모 하한(`YOY_BASE_MIN_USD`)으로 폭발 방지.
8. **호출수 예산** — 1년 윈도우 · 페이지네이션 없음 · 개발계정 10,000회/일. `hsSgn` 생략 시 반환 행수 미측정 → 승인 직후 실측으로 백필 설계 확정.

---

## §7 참조

- 실측 증거: `fq073/publication_lag_evidence.json` · `fq073/first_release_evidence.json`
- 러너: `fq073/run_fq073_export.R` · pull: `fq073/pull_customs_hs.py`
- 승계: `stage_artifacts/method_frontier/firm_level_scaffold/PIT_plan.md` (FQ-064/065) §2
- 규칙: `.claude/rules/pit.md`(C5) · `measurement-graduation.md`(§1 실측·§3 게이트·§7 pin) · `backtest-contract.md`
- 가드: `02_Infrastructure/validation/overlay_pit_guard.R` · `02_Infrastructure/contracts/canonical_screen_bt.R`
- 선례: `stage_artifacts/method_frontier/fq066_ppi_margin/fq066_harness.R` (섹터 tilt 측정 패턴 · sector_ppi_map 선언 방식)
