# 완비-대리판정 동형 패턴 전수 스캔 (P2)

- 일시: 2026-07-26
- 배경 라운드: R-ICGUARD-20260726 (P1) — `compute_all_factor_ic_monthly()`의 incomplete-terminal-pair guard를 2조건 OR로 강화
- 임무: P1과 **같은 기전**을 가진 지점을 전수 색출. **본 문서는 발견·판정만 — 코드 수리 없음**(수리는 별도 승인 사이클)
- 산출자: 서브에이전트 스캔 (읽기 전용 + 계측 스크립트 read-only)

---

## 0. 판정 기준

**동형 결함 정의**: 코드가 *경과 시간·달력·파일 존재·파일 mtime*으로 **"데이터가 준비됐다"**를 결론내는데, 실제로 필요한 명제는 **"데이터가 그 지점까지 실제로 차 있는가"**(max Date 도달 · 행수 · 기대 집합 대비 커버리지)인 경우.

P1의 원문 기전: *"달력이 끝났나"와 "이 파일이 그 달을 끝까지 담았나"는 다른 명제다.*

스캔 중 하위 4형이 구분되어 나왔습니다. 넷 다 같은 대체(존재/시각 → 도달)이며 심각도만 다릅니다.

| 형 | 대리 지표 | 필요한 명제 |
|---|---|---|
| **A형** 달력→도달 | Sys.Date 비교, `date +%d`, N일 경과, 월말 여부 | 데이터의 max Date가 그 지점에 도달했는가 |
| **B형** 존재/이름→도달 | 파일이 있다 / 파일명이 YYYYMM이다 | 그 파일의 **내용**이 그 라벨의 범위를 담았는가 |
| **C형** mtime/도장→반영 | 파일을 만졌다 / 북마크를 찍었다 | 그 쓰기가 **실제 병합**을 수행했는가 |
| **D형** max→커버리지 | 종점이 최신이다 | 내부(interior)에 구멍이 없는가 |

---

## 1. 요약

- 조사 지점 **23곳** (지시 최소 범위 + 확장)
- **동형 결함 15건** / 정합(대조군) **8건**
- 15건의 상태: **실현 확인 3건**(지금 데이터가 이미 틀어져 있음) · 정황 1건 · 과거 실사례 1건 · **잠재 10건**(기전 성립·현재 실현 0)
- 최대 발견: **DART 연간 재무제표 FY2025가 corps 714 → 50 (7.0%)로 결손**. 제출기한(2026-03-31) 경과 4개월. 자동 회복 경로 없음
- 두 번째 발견: 그 결손을 **감지해야 할 두 장치가 둘 다 구조적으로 침묵**(P2-02 · P2-03). "감지 0"이 건강의 증거가 아니라 계측 사망의 증거인 사례가 또 나왔습니다

---

## 2. 지점별 판정표

`✗` = 동형 결함 / `○` = 정합(대조군)

| ID | 지점 (파일:라인) | 현재 판정 기준 | 형 | 판정 | 실현 |
|---|---|---|---|---|---|
| P2-01 | `data/daily_refresh.sh:337` · `data/dart_daily_incremental.R:33,47` | `years = as.integer(format(Sys.Date(), "%Y"))` | A | ✗ | **실현** |
| P2-02 | `data/cache_freshness_audit.R:110-117` | 파일명 YYYYMM → 월말 → `data_lag = max(0, today - m_end)` | B | ✗ | **실현** |
| P2-03 | `data/cache_freshness_audit.R:127-128,150` | `date_col` 없으면 `lag <- mtime_lag` | C | ✗ | **실현** |
| P2-04 | `factor_db/factor_db_builder.R:1192-1207` | `setdiff(gap_yms, cached_ym)` + `last_first <- max(cached_ym)` | B·D | ✗ | 잠재 |
| P2-05 | `factor_db/factor_db_connector.R:189-202` | 요청 sig_date의 YYYYMM 파일을 무검증 반환, 부재 시 `max(ym_avail <= ym_tag)` | B | ✗ | 잠재 |
| P2-06 | `ramp/factor_validation.R:27-36` | `asof_close(d) = max(rawdata[Date <= d]$Date)` — 상한 없음 | A | ✗ | 잠재 |
| P2-07 | `data/refresh_nonreturn_sources.py:219-223,236` | 이번 달 파일명 스냅샷 존재 → no-op | B | ✗ | 잠재 |
| P2-08 | `data/daily_refresh.sh:331,433,459` (+ 락 `25-33`) | `DAY_OF_MONTH="01"` / `DAY_OF_WEEK="1"` — 캐치업 없음 | A | ✗ | 정황 |
| P2-09 | `data/trading_calendar.R:295-308` | `hour >= 16 && today %in% cal$Date` → 종가 확정 | A | ✗ | 잠재 |
| P2-10 | `data/krx_build_rawdata.R:55,64` | `cutoff <- Sys.Date() - 60L` 밖은 검사 없음 | A | ✗ | 과거 실사례 |
| P2-11 | `data/trading_calendar.R:232-240` | `bm_max > cal_max`일 때만 재빌드 | D | ✗ | 잠재 |
| P2-12 | `data/incremental_update_file.R:37-57,524` | mtime 북마크를 성공 여부와 무관하게 전진 | C | ✗ | 잠재 |
| P2-13 | `data/incremental_update_file.R:206-212,237` | 12개 메트릭의 증분 창을 `eps_1y` 하나의 max로 결정 | D | ✗ | 잠재 |
| P2-14 | `data/daily_refresh.sh:99` | `--start_date "$(date -d '10 days ago')"` 고정창 | A | ✗ | 잠재 |
| P2-15 | `data/incremental_cache_update.R:32-36,43,95,129,151` | `.xlsx_newer()` = mtime(xlsx) > mtime(parquet) | C | ✗ | 잠재 |
| — | `data/krx_build_rawdata.R:33-49` `krx_detect_gap()` | 저장 데이터 max Date vs 목표일 | — | ○ | — |
| — | `data/krx_build_rawdata.R:55-76` `krx_detect_interior_gaps()` (집합 비교부) | 기대 거래일 집합 `setdiff` 실측 | — | ○ | — |
| — | `data/cache_freshness_audit.R:53-56` `.trading_lag()` | 캘린더 커버리지 밖이면 fallback (lag 증가 안 함) | — | ○ | — |
| — | `data/us_update_merge.py:119-124` | `upd_max <= panel_max` — 데이터 기준 cache-hit | — | ○ | — |
| — | `data/data_collector_dart_quarterly.R:85-97` `.dart_season_bounds()` | reprt_code별 실제 제출창(11011 = bsns_year+1) 인지 | — | ○ | — |
| — | `data/dart_backfill_status.R:21-23` | 기대 월 집합 열거 → `file.exists` 대조 → `first_gap_month` | — | ○ | — |
| — | `factor_db/factor_db_connector.R:341-345` `load_daily_factors` | 부재 월을 WARN + `months_loaded` attr | — | ○ | — |
| — | `factor_db/factor_db_builder.R:1548-1568` (P1 수리분) | 달력 OR 파일 sig < 그달 RAWDATA 최종 거래일 | — | ○ | — |

---

## 3. 실결함 상세 (실현 확인 3건)

### P2-01 [HIGH] DART 연간 재무제표 = 달력연도 고정 → 직전 회계연도 영구 미수집

**판정 기준 인용**

```
02_Infrastructure/data/daily_refresh.sh:337
    tryCatch(dart_run_pipeline(years = as.integer(format(Sys.Date(), "%Y"))),

02_Infrastructure/data/dart_daily_incremental.R:33
  dart_daily_incremental <- function(current_year = as.integer(format(Sys.Date(), "%Y")),
02_Infrastructure/data/dart_daily_incremental.R:47
      dart_fetch_quarterly(years = current_year, resume = TRUE)
```

`dart_fetch_quarterly`는 태스크를 `CJ(corp_code, bsns_year = years, reprt_code = reprt_codes)`로 만듭니다(`data_collector_dart_quarterly.R:183-186`). `years`가 **달력 현재연도 1개**이므로, 2026년 내내 요청되는 것은 `bsns_year = 2026`뿐입니다.

**동형 판정: ✗ (A형).** 필요한 명제는 "bsns_year=2025의 사업보고서가 저장소에 차 있는가"인데, 코드는 "달력이 2026년이니 2025년 건은 (2025년 동안) 이미 받았겠지"로 대리 판정합니다. FY2025 사업보고서는 **2026년 3월**에 제출되므로, 2025년 내내 요청했을 때는 존재하지 않았고 2026년에는 아예 요청되지 않습니다.

**실측 (2026-07-26)**

| bsns_year | `dart_raw_financials` corps | `dart_raw_quarterly` 11011 corps |
|---|---|---|
| 2023 | 713 | 624 |
| 2024 | 714 | 621 |
| **2025** | **50** (7.0%) | **103** (16.6%) |
| 2026 | 26 | 27 |

파생 캐시로도 그대로 전파: `.cache/fundamental_dart.parquet` corps by bsns_year = {…, 2023: 713, 2024: 714, **2025: 50**, 2026: 26}.

**아이러니**: 올바른 검사가 같은 저장소에 이미 있습니다. `.dart_season_bounds()`(`data_collector_dart_quarterly.R:85-97`)는 `reprt_code == "11011"`의 제출창을 `bsns_year+1`의 01-01 ~ 04-15로 **정확히 알고 있습니다**. 그러나 그 로직은 `years`로 생성된 태스크 집합 *안에서만* 작동하므로, 태스크가 만들어지지 않는 bsns_year=2025에는 도달하지 못합니다. 즉 결함은 판정 로직이 아니라 **후보 집합 생성**에 있습니다.

**회복 경로 부재 확인**: `dart_backfill_status.R`은 insider 전용(`.cache/dart/insider_backfill/` 체크포인트 스캔)이며 연간 재무제표와 무관합니다. `dart_run_pipeline`/`dart_fetch_all`을 과거 연도로 호출하는 스케줄은 저장소 내에 없습니다(grep: 호출부 2곳 모두 `format(Sys.Date(), "%Y")`). → 방치 시간이 길어질수록 영구화됩니다.

**피해 정량 (정직 표기)**: `fundamental_merged.parquet`은 XLSX 우선 구조이고 Period=202512 커버가 XLSX 5,376행 + xlsx_derived 2,638행으로 존재합니다(DART 202512는 6,462행). 따라서 **XLSX가 커버하는 항목의 피해는 없고**, DART 전용 항목(RandD / InterestExp / DepAmort / EBITDA 구성요소 등 `fundamental_dart.parquet` 스키마 고유 열)의 FY2025 결손만 남습니다. 그 열들의 소비처별 영향은 **미측정 — 별건**.

**재현 절차**

```
# (1) 결손 실측 — 읽기 전용
<venv python> -c "import pyarrow.parquet as pq;t=pq.read_table('.cache/dart/dart_raw_financials.parquet',columns=['bsns_year','corp_code']).to_pandas();print(t.groupby('bsns_year').corp_code.nunique())"
# (2) 기전 확인 — 태스크 집합이 2026만 담는지
#     data_collector_dart_quarterly.R:183-186의 CJ(...) 직후 tasks[, unique(bsns_year)] 출력
# (3) 위반 주입 테스트: 시스템 날짜를 2027-01-02로 둔 가상 호출에서
#     years == 2027 단일값이 되는지 확인 → FY2026 연간도 같은 방식으로 누락 예정임을 사전 확인
```

---

### P2-02 [HIGH] 신선도 감사의 디렉토리형 캐시 = 파일을 열지 않고 파일명 월말로 lag 산출

**판정 기준 인용**

```r
02_Infrastructure/data/cache_freshness_audit.R:110-117
    } else {
      ym <- regmatches(latest_file, regexpr("[0-9]{6}", latest_file))
      if (length(ym) == 1) {
        m_start <- as.Date(paste0(ym, "01"), format = "%Y%m%d")
        m_end <- seq(m_start, by = "month", length.out = 2)[2] - 1
        data_lag <- max(0L, as.integer(today - m_end))
      }
    }
```

이 분기는 registry 항목에 `date_col`이 없을 때 탑니다. `.cache/factor_db/`가 정확히 그 경우입니다(`cache_registry.json`: `file_pattern` 있음 / `date_col` **없음**).

**동형 판정: ✗ (B형).** "파일 이름이 202607이다" → "이 파일은 2026-07-31까지 담았다"로 대리 판정합니다. 파일 내용은 **한 번도 읽지 않습니다**.

**실측 (`qepm/observability/cache_freshness_latest.json`, ran_at 2026-07-26T00:06:59)**

```json
{ "path": ".cache/factor_db/", "latest_file": "factor_db_202607.parquet",
  "n_files": 439, "mtime_lag": 1, "data_lag": 0, "lag_used": 0,
  "status": "FRESH", "severity": "OK" }
```

`data_lag = 0`은 `max(0, 2026-07-26 − 2026-07-31)`의 산물입니다. **당월 파일이 어떤 날짜에 얼어붙어 있어도 그 달 내내 lag=0/FRESH**입니다.

**대조 사고**: `factor_db_builder.R:1252-1260` 주석이 기록한 실사고 — *"factor_db_202607 stuck at Date=2026-07-03 for ~3 weeks while RAWDATA ran to 2026-07-24"*. 그 3주 동안 이 감사는 매일 `data_lag=0 / FRESH`를 보고했습니다. 즉 D2 수리(주간 리프레시)가 필요했던 이유 자체가 **감지장치가 구조적으로 침묵했기 때문**입니다.

**같은 코드가 registry 한 줄 차이로 갈립니다**: `.cache/factor_db_daily/`는 `date_col="Date"`라 같은 감사에서 `data_lag=2`(내용 기준 실측)를 산출합니다. 결함은 감사 코드가 아니라 **fallback 분기의 존재 + registry 선언 누락**의 결합입니다.

**재현 절차**

```
# 위반 주입 테스트 (읽기 전용으로는 재현 불가 — 사본에서 수행할 것)
# 1. .cache/factor_db/를 사본 디렉토리로 복사
# 2. 사본의 factor_db_202607.parquet을 Date=2026-07-03만 담은 파일로 교체
# 3. registry의 path를 사본으로 가리키게 한 뒤 cache_freshness_audit(telegram_alert=FALSE) 실행
# 4. 기대 결과(현행): data_lag=0 / FRESH  ← 검사가 잡지 못함을 확인
```

---

### P2-03 [HIGH] `date_col` 미선언 등록 캐시 = mtime만으로 신선도 판정

**판정 기준 인용**

```r
02_Infrastructure/data/cache_freshness_audit.R:127-128
    mtime <- file.info(cache_path)$mtime
    mtime_lag <- as.integer(today - as.Date(mtime))
02_Infrastructure/data/cache_freshness_audit.R:149-150
    # Pick worse of mtime_lag and data_lag for evaluation
    lag <- if (!is.na(data_lag)) data_lag else mtime_lag
```

(주석은 "worse of"라고 적혀 있으나 코드는 data_lag가 있으면 그것만 씁니다 — 이 방향은 우리 관심사에서는 안전한 쪽이므로 지적만 하고 넘어갑니다.)

**동형 판정: ✗ (C형).** `date_col`이 없으면 판정 근거가 "파일을 언제 만졌나"로만 남습니다. 내용이 비었든 잘렸든 과거만 담았든 구분하지 못합니다.

**해당 등록 캐시 (스케줄이 `on_demand`가 아닌 것만, `cache_registry.json` 실측 8건)**

`.cache/dart/dart_raw_financials.parquet`(monthly/35) · `.cache/dart/dart_raw_quarterly.parquet`(daily/100) · `.cache/fundamental_dart.parquet`(monthly/35) · `.cache/fundamental_merged.parquet`(monthly/35) · `.cache/value_quality_spread.parquet`(daily/7) · `.cache/fundamental_dart_quarterly.parquet`(daily/14) · `.cache/conditional_ic_matrix.csv`(weekly/10) · `stage_artifacts/.../nps_headcount_raw.parquet`(monthly/75) · `.../customs_hs_monthly.parquet`(monthly/45)

**실현 확인 — P2-01을 P2-03이 못 잡습니다.** `.cache/fundamental_dart.parquet`의 mtime = 2026-06-30 22:57 → `mtime_lag = 26 < 35` → **FRESH/OK**. 그런데 그 파일의 내용은 FY2025 corps 50건(정상 714)입니다. 두 결함이 겹쳐 4개월 침묵이 성립했습니다.

**재현 절차**: 사본에서 `.cache/fundamental_dart.parquet`의 행을 1행만 남기고 `touch` → `cache_freshness_audit()` 실행 → 여전히 FRESH가 나오는지 확인(위반 주입 테스트).

---

## 4. 잠재 결함 상세 (기전 성립 · 현재 실현 0)

### P2-04 [MED-HIGH] `.fdb_gap_months` — 파일 존재 = 그 달 완비, 그리고 max 이전은 검사 밖

```r
02_Infrastructure/factor_db/factor_db_builder.R:1197-1206
  last_first <- as.Date(paste0(max(cached_ym), "01"), format = "%Y%m%d")
  ...
  gap_yms <- format(month_firsts[-c(1L, length(month_firsts))], "%Y%m")
  setdiff(gap_yms, cached_ym)
```

두 겹의 대리판정:
1. **B형** — `setdiff(..., cached_ym)`: 파일이 있으면 그 달은 gap이 아닙니다. 그 파일이 **월중 스냅샷**일 수 있다는 가능성은 검사되지 않습니다. 월중 스냅샷은 정상 산출물입니다 — D2 주간 리프레시가 `build_sig <- stale_chk$raw_d`(라인 1285)로 굽습니다.
2. **D형** — `last_first <- max(cached_ym)`: 최신 캐시 월 *이전*의 구멍은 `seq()` 범위에 들어오지 않아 영구 불가시.

**오작동 시나리오 (P1과 직결)**

1. 2026-07-28 daily_refresh: 당월 파일이 7일 넘게 뒤처져 주간 리프레시 발동 → `factor_db_202607.parquet`이 **sig = 2026-07-24**로 재생성
2. 2026-07-31(월말) 크론 미실행 — 머신 off 또는 재진입 락 `exit 0`(`daily_refresh.sh:31-32`)
3. 2026-08-01 이후 `.fdb_gap_months()`: 202607 파일이 존재 → gap 아님 → **영원히 월말 재빌드 안 됨**
4. `compute_all_factor_ic_monthly()`의 P1 가드(라인 1557 `.file_partial`)가 `sig_d_t1(07-24) < RAWDATA 7월 최종 거래일(07-31)`을 잡아 **그 쌍을 영구 skip** → **IC[2026-06]이 조용히 영구 결손**

즉 P1 수리는 *부분월 IC의 오기록*을 *침묵 결손*으로 바꿨을 뿐이고, **부분월 파일 자체를 고치는 주체가 없습니다.** P1의 필수 후속입니다.

**현재 실측(건강)**: factor_db 파일 439개, 부분월 0건, 월 구멍 0건. `factor_db_202607` sig = 2026-07-24 = RAWDATA 7월 최종 거래일(RAWDATA max 2026-07-24)이므로 현재는 partial이 아닙니다. IC 파일 max Date = 2026-05-29 / max Usable_Date = 2026-06-30 — 2026-06은 t+1(202607)이 달력상 미도달이라 **정상 skip**입니다(오탐 아님).

**재현 절차**: 사본 디렉토리에서 `factor_db_202607.parquet`의 Date를 2026-07-10으로 바꾼 뒤 ① `.fdb_gap_months(as.Date("2026-08-05"))` → `character(0)` 반환 확인(gap으로 안 잡힘) ② `compute_all_factor_ic_monthly()` → `[skip] ... 월말 재빌드 대기` 로그 + IC[202606] 부재 확인.

---

### P2-05 [MED-HIGH] `load_month_factors` — 요청 sig_date를 파일명으로만 해석, vintage 미검증·미노출

```r
02_Infrastructure/factor_db/factor_db_connector.R:190-201
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fpath)) {
    ...
    closest <- max(ym_avail[ym_avail <= ym_tag])
    ...
  }
02_Infrastructure/factor_db/factor_db_connector.R:222-225
    as.data.table(read_parquet(fpath,
      col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage")))   # Date 미포함
02_Infrastructure/factor_db/factor_db_connector.R:252
  attr(result, "factor_db_build_hash") <- build_hash                     # vintage attr 없음
```

**동형 판정: ✗ (B형).** 세 겹입니다.
1. 요청 sig_date와 파일 내용 sig(Date)의 관계를 **검사하지 않음**
2. `col_select`가 Date를 제외하므로 **소비자가 사후 감사할 수도 없음**
3. 파일 부재 시 이전 달 패널로 **침묵 대체**(`cat`도 warning도 없음) — 대체 거리에 상한 없음

**오작동 시나리오**: 소비자가 `load_month_factors("2026-07-31")` 호출. 당월 파일이 D2 이전 상태(sig=2026-07-03)면 **4주 낡은 횡단면**이 07-31 신호로 소비되고, 반환값 어디에도 그 사실이 없습니다. 신호 자체는 PIT를 어기지 않으나(과거값이므로) 측정 무결성은 깨집니다 — 같은 코드가 캐시 재생성 전후로 다른 값을 내며, 그 차이를 추적할 라벨이 없습니다([[project-cache-vintage-pinning]]의 tipping과 같은 부류).

**대조군이 같은 파일에 있습니다**: `load_daily_factors`는 부재 월을 `WARN`으로 알리고(`341-345`) `pit_max`/`months_loaded` attr을 붙입니다(`300-302`).

**재현 절차**: 사본에서 `factor_db_202607.parquet`의 Date를 2026-07-03으로 바꾸고 `load_month_factors("2026-07-31")` 호출 → 경고 없이 반환되며 `attributes(result)`에 vintage 정보가 없음을 확인. 이어서 `factor_db_202606.parquet`을 임시 이동 후 `load_month_factors("2026-06-30")` → 202605 패널이 침묵 반환되는지 확인.

---

### P2-06 [MED] `build_monthly_forward_returns::asof_close` — as-of 대체 거리에 상한 없음

```r
02_Infrastructure/ramp/factor_validation.R:27-32
  asof_close <- function(d) {
    sub <- rawdata[Date <= d]
    if (nrow(sub) == 0) return(NULL)
    md <- max(sub$Date)
    rawdata[Date == md]
  }
```

**동형 판정: ✗ (A형).** "d 이하에 데이터가 있다" → "d 시점 데이터가 있다"로 대리 판정합니다. 얼마나 낡은 대체인지 검사·경고·라벨이 없습니다.

**오작동 시나리오 1 (터미널월)**: RAWDATA가 2026-07-24까지인데 `sig_dates`에 2026-07-31이 포함되면, `Ret_1m(2026-06)` = `Close(07-24)/Close(06-30) − 1` = **24일치 수익이 1개월 수익으로 라벨**되어 rank-IC·`canonical_screen_bt` 채점에 그대로 들어갑니다.

**오작동 시나리오 2 (데이터 구멍)**: 2026-04 소실사고(03-30~04-29 부재, [[project-rawdata-april-gap-incident-20260711]]) 재현 시 `asof_close(2026-04-30)` → 2026-03-27 횡단면 → `Ret_1m(2026-04)`가 **2개월 수익**이 됩니다.

기적립 사고([[reference-forward-returns-terminal-month-liq-gap]])는 같은 함수의 인접면(터미널월 liq NA-passthrough)이며, 그 수리는 "함수 무변경 + 러너측 보충"으로 이뤄졌습니다(frozen 소비처 다수). 본 면은 미수리 상태입니다.

**재현 절차**: 합성 rawdata(월말 6개월 + 마지막 달을 24일까지만)로 `build_monthly_forward_returns(raw, sig_dates=월말 7개)` 호출 → 마지막 `Ret_1m`의 실제 구간 길이가 1개월이 아님을 `returns_dt`와 원 종가로 대조.

---

### P2-07 [LOW-MED] `refresh_customs` — 이번 달 스냅샷 파일 존재 = 그 달 축적 완비

```python
02_Infrastructure/data/refresh_nonreturn_sources.py:220-223
    same_month = [f for f in existing if f[len("customs_hs_"):len("customs_hs_")+6] == today.strftime("%Y%m")]
    if same_month:
        log(f"관세청: 이번 달 스냅샷 존재({same_month[-1]}) — no-op")
        return {...}
02_Infrastructure/data/refresh_nonreturn_sources.py:236
    if not rows:      # ← 1행이라도 있으면 스냅샷 기록
```

**동형 판정: ✗ (B형).** HS 97장 × 최대 3개년 루프에서 예외는 `fail` 리스트에 쌓이기만 하고(라인 233-234) 게이트가 아닙니다. 대량 실패해도 남은 몇 행으로 스냅샷이 기록되면, 그 달의 나머지 호출은 전부 no-op이 되어 **부분 스냅샷이 그 달의 vintage로 확정**됩니다. 이어 §2-c 개정폭 실측(라인 261-273)이 *부분 vs 전량*을 비교해 개정폭을 과대 산출합니다.

부가 문제: 완결도의 흔적조차 남지 않습니다. `failures` 카운트는 스냅샷 생성 실행의 반환값에만 들어가는데, 같은 달 이후 실행의 no-op 결과가 `nonreturn_refresh_status.json`을 덮어씁니다(실측: 현재 status는 `{"source":"customs","action":"noop","snapshots":1}`뿐, 생성 실행의 failures 없음).

**현재 실측(건강)**: 스냅샷 1개(`customs_hs_20260726.parquet`), 289,792행 / HS 고유 10,985 — 부분 아님.

**재현 절차**: `vintage_store/`에 오늘 날짜 태그로 HS 2개짜리 소형 parquet을 두고 `--source customs` 실행 → "이번 달 스냅샷 존재 — no-op" 로그 확인.

---

### P2-08 [MED] daily_refresh 달력 게이트 3종 — 캐치업 없음

```bash
02_Infrastructure/data/daily_refresh.sh:331   if [ "$DAY_OF_MONTH" = "01" ]; then      # [5a] DART Annual + fundamental_merged
02_Infrastructure/data/daily_refresh.sh:433   if [ "$DAY_OF_WEEK" = "1" ]; then        # [6c] conditional_ic_matrix
02_Infrastructure/data/daily_refresh.sh:459   if [ "$DAY_OF_MONTH" = "01" ] || [ "$DAY_OF_MONTH" = "15" ]; then   # [6.5] forward weights
```

**동형 판정: ✗ (A형).** "오늘이 1일인가"만 보고 "이번 달에 이미 했는가"는 보지 않습니다. 놓치면 그 주기분은 회복되지 않습니다.

**오작동 시나리오**: 00:03에 전날 인스턴스가 아직 살아 있으면 재진입 가드가 `exit 0`으로 종료합니다(라인 30-32 — 정상 동작). 그날이 1일이면 그 달의 [5a] 전체(DART Annual + `build_fundamental_derived.R`)가 통째로 사라지고, 다음 기회는 **한 달 뒤**입니다. 실사례 정황: 저장소는 12시간 내 5중복 인스턴스를 관측한 이력을 주석에 기록하고 있습니다(라인 22-23).

**정황 실측**: `.cache/fundamental_dart.parquet` mtime = 2026-06-30 22:57 — 2026-07-01의 [5a] 갱신 흔적이 없습니다(단, 이 파일의 writer 경로 특정은 미확인 — 정황이지 확정 아님).

**대조군**: 같은 저장소의 `.fdb_gap_months`는 놓친 월을 다음 실행이 캐치업합니다. 같은 파일 안에 두 방식이 공존합니다.

---

### P2-09 [MED] `last_confirmed_trading_day()` — 시계 16시로 종가 확정 판정

```r
02_Infrastructure/data/trading_calendar.R:304-307
  if (hour >= 16 && today %in% cal$Date) {
    return(today)
  }
  get_prev_trading_day(today)
```

**동형 판정: ✗ (A형).** `today %in% cal$Date`는 캘린더(= benchmark.parquet 유래)가 오늘 세션을 담았다는 것까지만 보증합니다. 소비자가 실제로 채우려는 저장소(RAWDATA)가 오늘을 담았는지는 검사하지 않는데, 함수 이름과 소비 방식은 "종가가 확정된 날"입니다.

**오작동 시나리오 (split-brain)**
1. `[1pre]`(라인 91-103) benchmark chart-API 성공 → `benchmark.parquet`에 오늘 추가 → `.load_calendar()` self-heal이 캘린더에 오늘 등록
2. `[1]`(라인 111-123) `naver_run_pipeline()` 실패 → RAWDATA는 어제까지 (코드는 WARN만 찍고 진행)
3. 16시 이후 `krx_detect_gap()`(`krx_build_rawdata.R:38-48`)이 `target = last_confirmed_trading_day() = 오늘`, `last_date = 어제` → `n_calendar_days = 1`
4. `daily_refresh.sh:142`의 조건은 `gap$n_calendar_days > 1` → **KRX fallback도 미발동**
5. 결과: 그날 RAWDATA 미수집. 다음날 gap이 2가 되면 회복되므로 **부분 자기치유**이지만, 그 사이 실행되는 당일 소비자(morning brief·regime·NAV)는 오늘이 확정된 것으로 취급합니다

---

### P2-10 [MED] `krx_detect_interior_gaps(60L)` — 경과 60일 밖은 검사 자체가 없음

```r
02_Infrastructure/data/krx_build_rawdata.R:64-65
  cutoff <- Sys.Date() - lookback_days      # daily_refresh.sh:139에서 60L
  recent_existing <- existing_dates[existing_dates >= cutoff]
```

**동형 판정: ✗ (A형).** 커버리지 검사의 *범위*를 경과 시간으로 정하므로, 60일을 살아남은 구멍은 그 뒤로 영구 불가시입니다.

**과거 실사례**: 2026-04 소실(03-30~04-29)은 2026-07-11에 적발됐습니다 — 발생 시점 기준 **73~103일 경과**, 즉 이 창이 이미 무력해진 뒤였습니다. 창 안에서 잡힌 것이 아니라 다른 경로로 발견됐습니다.

**현재 실측**: 캘린더 대비 RAWDATA 내부 결손 438일 — **전량 1990~1998년 토요일**(주5일제 이전 KRX 토요장). post-2000 결손 0건. 이 438건은 60일 창 밖이라 어떤 실행으로도 보고되지 않으며, 애초에 채워야 할 대상인지 여부(토요장 가격 패널의 정당한 부재인지)도 **미판정 — 별건**.

---

### P2-11 [LOW-MED] `.load_calendar()` self-heal — 종점만 비교

```r
02_Infrastructure/data/trading_calendar.R:237-240
    if (!is.na(bm_max) && !is.na(cal_max) && bm_max > cal_max) {
      .CALENDAR <<- build_trading_calendar(force = TRUE, verbose = FALSE)
    }
```

**동형 판정: ✗ (D형).** 종점이 같으면 내부 구멍이 생겨도 재빌드하지 않습니다. 내부 구멍을 메우는 Layer 2b(라인 168-183)는 **빌드 시점에만** 작동하므로, 마지막 빌드 이후 생긴 내부 결손은 다음 강제 빌드까지 방치됩니다.

**현재 실측(건강)**: 캘린더 9,433일, source 분포 = quantiwise 9,353 / quantiwise_update 40 / benchmark_interior 23 / benchmark 17. benchmark 내부 결손 0건, 캘린더가 놓친 benchmark 세션 1건(2024-12-30 = 임시휴장 manual 제외분 — 정상).

---

### P2-12 [MED] `detect_update_changes` mtime 북마크 — 시도 시점에 전진

```r
02_Infrastructure/data/incremental_update_file.R:51-53
    if (is.null(prev_mt) || mt > prev_mt) { changed <- c(changed, f) }
02_Infrastructure/data/incremental_update_file.R:524
  .save_last_processed(changes$mtimes)      # 각 서브처리 성공 여부와 무관
```

**동형 판정: ✗ (C형).** 북마크는 "이 파일의 내용이 캐시에 병합됐다"를 뜻해야 하는데, 실제로는 "이 파일의 mtime을 봤다"를 기록합니다.

**오작동 시나리오**: `incremental_consensus()`는 오류를 `tryCatch`로 삼키고(라인 259-265) 정상 복귀합니다. `incremental_universe_support()`는 `n_merged == 0`(전 시트 스킵)도 경고만 찍고 정상 복귀합니다(라인 475-477). 두 경우 모두 라인 524가 실행되어 mtime이 전진 → **그 update xlsx는 다시는 처리 대상이 되지 않습니다.**

**정황 실측**: `.cache/update_file_last_processed.rds` mtime = 2026-07-01 17:47 vs `03_Universe/Update_File/OHLCVS_update.xlsx` mtime = 2026-07-24 23:47. (단 이 경로는 daily_refresh에 배선돼 있지 않고 수동/ops 스크립트에서만 호출되므로 — `daily_refresh.sh:82`가 부르는 것은 **동명 다른 함수** `incremental_cache_update.R::incremental_update_all()` — 위 간격 자체는 결함 증거가 아니라 수동 실행 이력입니다. 동명 함수 2파일 함정은 [[project-us-incremental-parser-promoted-20260725]]에 기적립.)

---

### P2-13 [LOW-MED] consensus 증분 창을 단일 메트릭 파일의 max로 결정

```r
02_Infrastructure/data/incremental_update_file.R:206-212
  ref_file <- file.path(cons_cache_dir, "eps_1y.parquet")
  ...
  base_max <- max(ref$Date, na.rm = TRUE)
02_Infrastructure/data/incremental_update_file.R:237
      new_rows <- tmp_dt[Date > base_max]
```

**동형 판정: ✗ (D형).** 12개 메트릭 파일 전체의 증분 창을 `eps_1y` 하나의 종점으로 정합니다. 한 메트릭이 뒤처져 있으면(과거 부분 실패 등) 그 구간은 어떤 실행으로도 채워지지 않습니다.

**현재 실측(건강)**: `.cache/consensus/` 12개 parquet 전부 max Date = 2026-07-24 (발산 0). `ticker_map.parquet`은 Date 컬럼 없음(스키마 차이 — 정상).

---

### P2-14 [MED] benchmark 보충 창 = 고정 10일 경과

```bash
02_Infrastructure/data/daily_refresh.sh:99
  "$QVENV_PY" data/naver_benchmark_update.py --start_date "$(date -d '10 days ago' +%Y-%m-%d)"
```

**동형 판정: ✗ (A형).** 저장 파일의 실제 종점이 아니라 **고정 경과창**으로 보충 범위를 정합니다. 11일 이상 중단(머신 off, API 연속 실패)되면 그 구멍은 이후 어떤 실행으로도 메워지지 않습니다.

**파급이 큰 이유**: `benchmark.parquet`은 (a) `trading_calendar` Layer 2·2b의 근거 (b) RAWDATA `BM_Ret`의 소스 (c) `.extract_bm_dates()` 기반 self-heal의 기준 — 세 가드의 공통 뿌리입니다. 여기 구멍이 나면 세 가드가 동시에 눈이 멉니다.

**현재 실측(건강)**: benchmark max 2026-07-24, 내부 결손 0건.

---

### P2-15 [LOW-MED] `.xlsx_newer()` — base xlsx 반영 여부를 두 파일의 mtime 대소로 판정

```r
02_Infrastructure/data/incremental_cache_update.R:32-36
  .xlsx_newer <- function(xlsx_path, ref_path) {
    if (!file.exists(xlsx_path)) return(FALSE)
    if (!file.exists(ref_path)) return(TRUE)
    file.mtime(xlsx_path) > file.mtime(ref_path)
  }
```

**동형 판정: ✗ (C형).** "참조 parquet이 xlsx보다 나중에 쓰였다" → "그 parquet은 이 xlsx의 내용을 담았다"로 대리 판정합니다. 그러나 참조 parquet은 **다른 경로들도 다시 씁니다**(`incremental_ohlcvs()` 라인 185, `krx_build_rawdata`, `rawdata_sanitize` 등).

**오작동 시나리오**: 새 base `OHLCVS.xlsx`(수정주가 재조정 반영)를 08-01 09:00에 복사 → 같은 날 12:00에 운영자가 KRX 백필을 돌려 `rawdata.parquet` 재작성(mtime 12:00) → 다음 daily_refresh `[0]`에서 `.xlsx_newer` = FALSE → *"OHLCVS.xlsx not newer — skip"* → **새 base 수출본이 영구히 반영되지 않음.** 수정주가 재조정은 전 구간 값이 바뀌는 변경이라 침묵 미반영의 대가가 큽니다.

**현재 mtime 실측**: `OHLCVS.xlsx` 2026-06-07 15:47 / `rawdata.parquet` 2026-07-26 06:23 (정상 skip 상태 — 새 수출본 없음). `Consensus.xlsx` 2026-06-07 15:45 / `eps_1y.parquet` 2026-07-25 04:15. `Fundamental.xlsx` 2026-06-07 15:22 / `fundamental_xlsx.parquet` 2026-07-25 04:47.

---

## 5. 수리 우선순위 (제안 — 승인 대상, 본 임무에서 미집행)

| 순위 | ID | 근거 | 수리 방향 스케치 |
|---|---|---|---|
| **P0-1** | P2-01 | 유일한 **실현 데이터 결손**. 자동 회복 경로 없음 → 방치할수록 영구화 | 태스크 집합을 `years = current_year`에서 **제출창 기반 후보 집합**으로 교체. `.dart_season_bounds()`가 이미 창을 알고 있으므로 후보를 `bsns_year ∈ {y-1, y}`로 넓히고 `resume` 원장이 걸러내게 하면 됨 |
| **P0-2** | P2-02 | 감지장치 침묵 = 다른 모든 결함의 발견을 막는 상위 원인 | registry `.cache/factor_db/`에 `date_col: "Date"` 선언(코드 무변경으로 해소). 나아가 파일명-월말 fallback 분기 자체를 **경고 동반**으로 강등 |
| **P0-3** | P2-03 | P2-01을 놓친 직접 원인. 8개 등록 캐시가 mtime만으로 판정 | 각 캐시의 도달 지표를 선언(날짜형은 `date_col`, 비-날짜형은 `bsns_year` 등 커버리지 체크). 선언 불가면 `NO_COVERAGE_CHECK`로 **명시 라벨**해 "검사됨"과 구분 |
| P1-1 | P2-04 | P1 수리의 필수 후속 — 지금은 오기록이 침묵 결손으로 바뀐 상태 | gap 판정을 존재가 아닌 **도달**로: 각 월 파일의 sig가 그 달 RAWDATA 최종 거래일에 도달했는지 검사(P1이 IC 쪽에 쓴 검사와 동일 술어를 재사용) |
| P1-2 | P2-05 | 측정 무결성·vintage 추적 | 반환값에 vintage attr(파일 sig Date) 부착 + 침묵 대체를 WARN으로. `load_daily_factors`가 이미 정답 형태 |
| P2-1 | P2-14 | 파급 大(캘린더·BM_Ret·self-heal 공통 뿌리), 현재 실현 0 | 고정 10일 창 → `benchmark.parquet` max Date 기준 동적 창 |
| P2-2 | P2-09 | split-brain으로 당일 수집 손실 | "확정"의 정의에 소비 저장소 도달 검사 추가, 또는 함수를 분리(캘린더 확정 vs 저장소 확정) |
| P2-3 | P2-08 | 주기분 통째 손실 | 달력 게이트 → "이번 주기에 수행했는가" 상태 기반 게이트(캐치업) |
| P2-4 | P2-12 | 침묵 미반영 | 북마크 전진을 각 서브처리의 **성공 반환**에 종속 |
| P2-5 | P2-06 | 게이트 수치 오염 가능 | `asof_close`에 최대 대체 거리 인자 + 초과 시 NULL/경고 (소비처 동결 고려해 러너측 검사도 대안) |
| P3 | P2-07 · P2-10 · P2-11 · P2-13 · P2-15 | 현재 실현 0 + 파급 국소 | 각 항 본문의 시나리오 참조 |

**수리 시 공통 요구(제안)**: 각 수리에 **위반 주입 테스트**를 동반할 것 — 일부러 부분월/부분 스냅샷/잘린 캐시를 주입해 검사가 실제로 잡는지 확인해야 합니다. 본 스캔에서 확인된 바와 같이, **오탐이 0인 검사와 죽은 검사는 겉보기가 같습니다**(P2-02가 3주 동안 `FRESH`를 보고한 사례 = "경고 0"이 최고 위험 신호였던 지점).

---

## 6. 미조사 영역 (정직 표기)

- `factor_db/factor_db_daily_phase6~10*.R`의 당월 처리 — 파일 규모상 이번 스캔에서 미열람. `daily_refresh.sh:389-421`의 fdb_daily 신선도 블록만 확인(latest 파일 1개 + 달력일 lag `> 5` 기준 — P2-02/P2-10과 같은 형태이나 여기서는 `date_col` 경로로 내용을 읽으므로 B형은 아님)
- `regime/*` 캐시 생산자들의 내부 완비 검사 — `daily_refresh` 호출부만 확인
- P2-01의 하류 피해 정량(DART 전용 항목의 FY2025 결손이 어느 팩터/전략까지 도달하는지) — 별건
- 1990~1998 토요장 438일의 정당성 판정 — 별건

---

## 7. 다음 탐침 (next_probe)

1. **P2-01 지평 확장**: `bsns_year`처럼 *회계 라벨*과 *달력*이 어긋나는 축이 다른 곳에도 있는지 — 분기 보고서 45일 lag, C4 연간 3/31, 컨센서스 FY1/FY2 라벨. 같은 스캔 술어("후보 집합이 달력으로 생성되는가")를 라벨 축에 적용
2. **검사 실효 배터리**: 본 문서의 15건 각각에 대해 위반 주입 케이스를 1건씩 만들어, 수리 전 **전부 통과(= 잡지 못함)** 를 먼저 실측 기록 → 수리 후 전부 차단으로 뒤집히는지 대조. P2-02는 이미 재현 절차가 있으므로 시작점
3. **부활 조건**: 본 스캔은 `02_Infrastructure/{factor_db,data}` + trading_calendar + distill 트리거 범위. 소비처(`04_Research`, `qepm/`, `05_Production`)에서 같은 술어로 재스캔하면 새 표면이 나올 수 있음 — 특히 "최근 N개월" 윈도우로 리서치 데이터를 자르는 코드(P2-10과 동형)

---

## 참조

- P1 수리분: `02_Infrastructure/factor_db/factor_db_builder.R:1543-1568`
- 관련 메모리: [[reference-forward-returns-terminal-month-liq-gap]] · [[project-rawdata-april-gap-incident-20260711]] · [[project-cache-vintage-pinning]] · [[reference-benchmark-parquet-date32-writer]] · [[project-us-incremental-parser-promoted-20260725]] · [[reference-python3-windows-stub-use-qvest-py]](계측 사망 = 총계 0)
- 계측 스크립트(임시, 읽기 전용): scratchpad `scan_measure.py`
