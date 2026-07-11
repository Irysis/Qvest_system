# rawdata 2026-03-30~04-29 한 달 소실 사고 — 원인 규명 + 복구 + 재발방지 (2026-07-11)

## 요약 (TL;DR)

`.cache/rawdata.parquet`에서 **2026-03-30~2026-04-29 거래일 23일(~72,852행)이 소실**된 것을 실측 확인.
소실 시점은 mtime이 가리키는 07-11이 아니라 **2026-07-02 낮**(daily refresh 로그 행수 추이로 확정:
07-02 00:06 13,988,988행 → 07-03 00:03 시작 시 ~13.91M행·min 1990-01-04→01-05·max 07-01→06-30).
근본원인은 **QuantiWise 수출 커버리지 이음매 구멍**이며, 07-11 KRX API 백필로 복구 완료 + 가드 5종 배선.

## 인과 사슬 (5단)

1. **수출 이음매 구멍**: base `03_Universe/OHLCVS.xlsx`(6-8 수출)는 **1990-01-03~2026-03-27**,
   update `Update_File/OHLCVS_update.xlsx`(07-01 20:56 인입)는 **2026-04-30~2026-06-30**.
   → **2026-03-30~04-29는 어느 파일에도 없음.** 원인: `ops/qw_refresh.ps1`이 OHLCVS의
   B5(Period From)를 갱신하지 않고 파일의 기존 From(04-30)을 유지 ("RAWDATA는 KRX로 항상
   신선" 가정 — 데이터에는 맞지만 xlsx가 *캘린더 ground truth*라는 사실을 간과).
2. **캘린더 전사**: `trading_calendar.R`의 Layer 1 = base∪update xlsx 날짜열 합집합,
   Layer 2(benchmark)는 QW max **이후 꼬리만** 보충 → 내부 구멍이 캘린더에 그대로 상속
   (2026-04 거래일 = 1일). 07-02 00:04 캘린더 재빌드부터 구멍 상태.
3. **데이터 삭제 (07-02 07:23~12:55, 벤치마크 IKS200 수리 세션)**: `build_cache.R` 전체
   리빌드(base xlsx → 1990-01-05~2026-03-27, `!is.na(Ret)` 필터로 첫날 탈락) 후
   `incremental_update_file.R::incremental_ohlcvs()` 재인제스트(04-30~06-30) →
   rawdata가 xlsx 페어 내용으로 재구성되며 **구멍이 데이터에 전사**. KRX/Naver로 실수집돼
   있던 4월 실데이터 + 07-01이 이때 소실. (04-30 행의 Ret이 03-27 대비로 오염된 것이
   이 시퀀스의 지문 — sanitize 단독이면 BM_Ret도 오염됐어야 함.)
4. **침묵 지속**: 연속성 가드 전부(naver_merge 차단·`krx_detect_interior_gaps`)가 **같은
   캘린더 기준**이라 구멍이 가드의 사각지대. 부팅 검증에는 월별 연속성 체크 부재.
5. **관측 지연**: mtime은 매일 재기록(00:06)이라 소실일로 오인. SPEC-2가 측정창을
   266/269 리밸로 절단(verdict.json measurement_window_deviation)하며 표면화.

## 복구 (07-11 완료, 실측 검증)

- **캘린더**: `trading_calendar.R`에 **Layer 2b(interior fill)** 추가 — QW 범위 내부의
  benchmark 실세션 누락일을 `benchmark_interior`로 보충 + WARN. force 재빌드 →
  2026-03=21일·04=22일 복원 (`benchmark_interior` 23일).
- **rawdata**: KRX API 백필 (`krx_collect_range 20260330~20260429`, 캐시 12일 + 신규 11일)
  → +63,746행 (23거래일 × ~2,778종목) → 총 **13,998,866행**. 시임 Ret 재계산
  (오염된 04-30 median|Ret| 9.4%→1.9% 교정, prev close 부재 232행은 정직 NA),
  BM_Ret은 canonical benchmark 주입(오차 0), `apply_universe_mapping()`으로 메타 재충전
  (04-15 기준 K200=199·KQ150=149). source 태그 = `krx_api_backfill_20260711`.
- **검증**: 2026년 전 월 rawdata 거래일 수 = benchmark 완전 일치 / 삼성전자 시임 체인
  매끄러움 / 횡단 median Ret ↔ BM_Ret cor 0.910.
- **백업**: 수리 전 상태 `.cache/rawdata_backup_pre_aprilfix_20260711.parquet` 보존.

## 재발방지 가드 5종 (전부 배선·검증 완료)

| # | 위치 | 내용 |
|---|---|---|
| 0 | `ops/qw_refresh.ps1` | **근본 수리**: OHLCVS B5 = base xlsx 마지막 거래일+1 (`Get-QwBaseNext`, 캘린더 quantiwise-source max 활용, 실패 시 구 동작 fallback). 다음 QW refresh에서 이음매 구멍 자체 소멸 + 4월 KRX 백필분이 수정주가로 자동 승격 |
| 1 | `ops/bootstrap.sh` 4e2 | **월별 거래일 연속성 체크** (rawdata vs benchmark 13개월, 캘린더 독립이라 캘린더 구멍에 눈멀지 않음). 실사고 상태로 FAIL 발화 검증: `2026-03(19/21) 2026-04(1/22)`. ⚠ Windows Rscript 멀티라인 -e 함정 때문에 단일 라인 유지 필수 |
| 2 | `data/trading_calendar.R` | Layer 2b interior fill + WARN (위 복구 항목) |
| 3 | `data/rawdata_sanitize.R` Step 3 | 제거 대상 '비거래일'이 benchmark 실세션과 충돌하면 **삭제 중단** (캘린더 결손 의심) |
| 4 | `data/incremental_update_file.R` | base/update 이음매 거래일 감지 → rawdata 보유 시 WARN, 미보유 시 강경고(+재수출 B5 안내). `data/build_cache.R`: 기존 캐시가 신규 빌드보다 최신이면 `RAWDATA_prebuild_bak.parquet` 백업+경고, 최종 저장 temp-rename화(mmap 1224 회피) |

## 다운스트림 복구 (07-11 완료)

1. **factor_db_202607.parquet — 재빌드 완료** ✅. 07-03 빌드가 구멍 상태 rawdata를 읽어
   momentum/vol(260일 일간 lookback이 4월 가로지름) 오염. **정량 실측**(gap본 vs repaired
   재빌드): M08_Residual_Mom 종목 94.7%가 >1% 변동(median Δ0.130·max 40.3), M01_Mom_12_1
   92.3%(median Δ0.097), D35_RealVol_63d 95.8% — 거의 전 종목 왜곡. repaired 데이터로
   sig_date 2026-07-03 재빌드(842,017행, 구멍본 785,866행보다 증가 = 4월 복구로 lookback
   충족 종목 회복). 오염본 `factor_db_202607_gapcontam_bak_20260711.parquet` 백업.
   202603/202604(6-10)·202605/202606(07-02 02:51/03:12, 소실 전) = 클린 확인.
2. **SPEC-2 — 재측정 완료** ✅ (신규 `stage_artifacts/spec2_timing_luck_repaired/`). 원본
   `spec2_timing_luck/`은 공백-절단 기록으로 보존. repaired rawdata 신규 pin
   `spec2_timing_luck_repaired_20260711`(md5 323edc95) + 새 spec_id
   `SPEC2_TIMING_LUCK_20260711R`(설계·판정규칙 전부 원본 동일, 입력만 교정 — p-hacking 아님,
   손상 입력 교체). 결과는 아래 "SPEC-2 재측정 결과" 절.

### SPEC-2 재측정 결과 (실측, 07-11 17:49)

| 지표 | 원본(공백-절단) | 재측정(repaired) |
|---|---|---|
| 사용 리밸 | 266/269 (절단) | **269/269 (절단 없음)** |
| NAV 종점 | 2026-03-03 | **2026-06-01** |
| verdict | RANGE_EXCEEDED_TRANCHE_COMPUTED | **동일 (변화 없음)** |
| range_SR (thr 0.05) | 0.1871 | 0.1914 |
| SR k0~k5 | 1.519·1.480·1.467·1.430·1.374·1.332 | 1.524·1.485·1.473·1.435·1.377·1.332 |
| tranche SR/CAGR/MDD | 1.366 / 0.3766 / 0.4423 | 1.368 / **0.3895** / 0.4423 |
| harness parity (k0 vs recon) | — | cor 0.999997 · max\|diff\| 3.18e-03 (269월) |

→ **데이터 공백은 SPEC-2 결론을 바꾸지 않았다** (verdict 동일, 수치 근사). 절단이 제거돼
전 269월·2004-01~2026-06 완전창에서 재확인. G5 채택 판정은 여전히 도훈 영역(본 측정 권고 아님).

## 잔여 (도훈 판단/실행 영역)

3. **07-02~07-11 사이 rawdata를 소비한 산출물** (recon/오버레이 forward-row 등): 4월 구간을
   실제로 참조한 것만 영향. ramp_r3 pin(07-11)도 구멍 vintage.
4. **QuantiWise 재수출**: 다음 `qw_refresh.ps1` 실행이 B5=20260328로 자동 수출 → 4월 구간
   수정주가 승격 + `incremental_ohlcvs()`가 KRX 백필분 자동 교체. 별도 조치 불요, 실행만.
5. **KRX 백필분 품질 caveat**: KRX는 무수정주가. 04-30~07-01 사이 corporate action이 있는
   종목은 04-29/04-30 시임 Ret 왜곡 가능(사고 전 상태와 등가 품질 — 원래도 그 구간은
   Naver/KRX 실수집분). 위 4번 재수출로 근본 청산.

## 재현/검증 커맨드

```r
# 공백 검사 (벤치 대비 월별)
source("02_Infrastructure/config.R")
# → ops/bootstrap.sh 4e2 블록과 동일 로직 (CONTINUITY_OK/FAIL)
# 캘린더 재빌드
source("02_Infrastructure/data/trading_calendar.R"); build_trading_calendar(force=TRUE)
```
