---
name: data-refresh
description: "데이터 최신화 오케스트레이터 — Update_File 증분 + KRX/Naver gap-fill + 검증"
---

## 핵심 철학

> QuantiWise 데이터가 가장 정확하나, 자동 업데이트가 불가능하기 때문에
> 그 부족분을 KRX API와 Naver 크롤링으로 **임시 보완**하는 것.
> QuantiWise 최신화 이후에는 기존 API/크롤링 데이터를 **완벽하게 대체**.
> **Factor DB 갱신은 QuantiWise 데이터 업데이트 시에만 허용.**

## 데이터 우선순위

```
[1순위] QuantiWise base (03_Universe/*.xlsx)       → 고정 캐시
[2순위] QuantiWise 증분 (Update_File/*_update.xlsx) → 증분 append
[3순위] KRX API                                     → 임시 gap-fill
[4순위] Naver                                       → KRX도 없을 때 최후 보완
         └─ QuantiWise 증분 도착 시 3/4순위 완벽 대체
```

## `/data-refresh` 실행 흐름

호출 시 자동으로 상태를 진단하고 필요한 작업만 실행합니다.

### Step 1. 상태 진단

```r
source("02_Infrastructure/config.R")
source("02_Infrastructure/trading_calendar.R")
source("02_Infrastructure/incremental_update_file.R")
```

확인 항목:
- `Update_File/*.xlsx` mtime → 신규/변경 감지 (`detect_update_changes()`)
- RAWDATA max date vs Update_File max date 비교
- source 컬럼으로 임시(krx_api/naver) 데이터 구간 식별
- `krx_detect_interior_gaps()` → 누락 거래일 탐지

### Step 2. QuantiWise 증분 처리 (Update_File 변경 시)

```r
result <- incremental_update_all()
```

내부 동작:
a. `incremental_ohlcvs()` — OHLCVS_update.xlsx → RAWDATA 증분 (base 이후 전구간 추출, KRX/Naver 교체)
b. `incremental_consensus()` — Consensus_update.xlsx → consensus/*.parquet 증분 append
c. `incremental_investor()` — Investor_Act_update.xlsx → investor_stock 증분
d. `incremental_universe_support()` — Universe_Support_update.xlsx → universe_support 증분
e. Ret, BM_Ret 재계산
f. **월간 Factor DB 해당 월 재빌드** (QuantiWise 증분이므로 허용)
g. **일간 Factor DB 전체 재빌드** (Phase 6→7→8 순차 실행, ~47분)
h. Regime signal 갱신

### Step 2g. 일간 Factor DB 갱신 (QuantiWise 증분 시에만)

```r
source("02_Infrastructure/factor_db_daily_incremental.R")
update_daily_fdb_range(affected_from_ym, affected_to_ym)
```

- RAWDATA 변경 영향 범위의 일간 parquet 재빌드
- 309팩터 (288 월간 매칭 + 21 일간 전용), Rcpp C++ 최적화
- Phase 6 (RAWDATA+Fund 172팩터) → Phase 7 (GAP 66팩터) → Phase 8 (GAP 57팩터)
- 소요: 전체 재빌드 ~47분, RAM 피크 ~16GB
- **KRX/Naver 임시 데이터로는 일간 Factor DB 갱신 금지** (월간과 동일 정책)

### Step 3. KRX/Naver gap-fill (QuantiWise 이후 구간)

QuantiWise max date ~ last_confirmed_trading_day() 사이 gap이 있으면:

```r
source("02_Infrastructure/krx_data_collector.R")
source("02_Infrastructure/krx_build_rawdata.R")
# KRX API 수집 → RAWDATA에 임시 append (source="krx_api")
# Factor DB 갱신 안 함
```

KRX도 실패하면 Naver fallback (source="naver").

### Step 4. 검증

```r
source("02_Infrastructure/rawdata_sanitize.R")
# 비거래일 = 0, 종목수 연속성, Ret 합리성 확인
```

### Step 5. 보고

처리 결과 요약:
- 변경된 날짜 범위, source 교체 건수
- Factor DB 갱신 여부
- 텔레그램 알림 (선택)

## 서브커맨드

| 커맨드 | 동작 |
|--------|------|
| `/data-refresh` | 전체 자동 (상태 진단 → 필요한 작업만) |
| `/data-refresh --status` | 현재 데이터 상태만 확인 (변경 없음) |
| `/data-refresh --force-fdb` | 월간+일간 Factor DB 강제 재빌드 |
| `/data-refresh --force-daily-fdb` | 일간 Factor DB만 강제 재빌드 (Phase 6→7→8) |
| `/data-refresh --sanitize` | RAWDATA 정화 (비거래일 제거 + Ret 재계산) |

## 금지 사항

- KRX/Naver 임시 데이터로 Factor DB 갱신 금지
- 전체 리빌드 금지 (base 고정 + 증분만)
- Fundamental_update.xlsx 증분은 이 파이프라인에서 제외 (DART API + 기초 데이터셋 별도)

## Cron 스케줄 (임시 gap-fill용)

| cron expression | 시간 | 역할 | Factor DB |
|-----------------|------|------|-----------|
| `10 8 * * 1-5` | 08:10 평일 | KRX T-1 확정 종가 임시 | 갱신 안 함 |
| `0 12 * * 1-5` | 12:00 평일 | KRX retry (실패 시) | 갱신 안 함 |
| `30 16 * * 1-5` | 16:30 평일 | Naver T+0 당일 확정 임시 | 갱신 안 함 |
| `0 3 * * 0` | 일요일 03:00 | cleanup.sh --execute | — |

**00:03 daily_refresh 폐기** (Naver 날짜 버그 원흉 — Session 52 확정).
QuantiWise 업데이트 트리거: **수동** — 도훈님이 Update_File 배치 후 `/data-refresh` 실행.

## 핵심 파일

| 파일 | 역할 |
|------|------|
| `02_Infrastructure/trading_calendar.R` | 영업일 캘린더 (QuantiWise ground truth) |
| `02_Infrastructure/incremental_update_file.R` | Update_File 증분 파서 |
| `02_Infrastructure/rawdata_sanitize.R` | RAWDATA 정화 |
| `02_Infrastructure/krx_build_rawdata.R` | KRX gap-fill + interior gap 탐지 |
| `02_Infrastructure/naver_data_collector.R` | Naver T+0 보완 |
| `02_Infrastructure/factor_db_daily_incremental.R` | 일간 Factor DB 증분 갱신 오케스트레이터 |
| `02_Infrastructure/factor_db_daily_phase6.R` | 일간 DB 통합 재구축 (RAWDATA+Fund 172팩터) |
| `02_Infrastructure/factor_db_daily_phase7.R` | 일간 DB GAP 추가 (RAWDATA+INV+Regime 66팩터) |
| `02_Infrastructure/factor_db_daily_phase8.R` | 일간 DB GAP 추가 (Fund+Consensus 57팩터) |
| `02_Infrastructure/factor_db_daily_rcpp.cpp` | Rcpp C++ 27개 롤링 함수 |

## 데이터 연속성 보장

```
RAWDATA = [base 1990~03/27] + [QW증분 03/28~QW최신] + [KRX/Naver 임시 QW최신+1~어제]
              고정                /data-refresh 시           cron이 매일
```
