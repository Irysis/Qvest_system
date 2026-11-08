# 재무 원천 v2 전환 · 팩터 DB 전체 재빌드 절차서 (2026-11-09)

결정: 도훈 11-08 "퀀티를 메인으로 하고 다트를 서브로 하면 안돼?" → "위 방식대로 가자" · 11-09 "보충 끝나면 전체 재빌드해줘".
근거 · 시험 결과 = `README.md` §8. 등록부 = `06_Registry/fundamental_source.json`.

## 0. 무엇이 바뀌나

- 정본 두 개를 바꿉니다.
  - `.cache/fundamental_merged.parquet` — 병합 표(팩터 모듈 · 일간 phase 6/8 · 전략 엔진 약 40곳이 읽음)
  - `.cache/fundamental_xlsx.parquet` — 분기 표(XF 팩터 · `xlsx_factor_calculator.R` · 전략 엔진 2곳)
- 팩터 DB 를 전부 다시 만듭니다: 월간 전 기간 · 일간 · 월간 IC.
- 전환 뒤에는 월간 [5a2/7] 과 DART 보충 완료 단계가 v2 로 다시 만듭니다. 등록부가 `active = v2` 이면 `build_fundamental_derived.R` 이 `fundamental_produce_v2.R` 에 넘기기 때문입니다.

## 1. 시작 조건 (전부 충족)

1. DART 연간 보충이 끝났다: `.cache/dart/annual_backfill_status.json` → `complete: true` · `compute_done: true`(`fundamental_dart.parquet` 재계산 끝).
2. 1계층 라운드가 측정 중이 아니다.
   - P2R05 는 등록만 된 상태입니다. 측정 체인의 지문에 `fundamental_merged.parquet` 가 들어 있습니다(`P2R05_distribution_target/fingerprint.sh`). 그래서 전환 뒤에 측정하고, 지문은 필드 단위로 다시 핀합니다.
   - DART 보충 완료 단계도 이 파일을 옛 경로로 다시 씁니다. 따라서 P2R05 입력은 전환과 상관없이 바뀝니다.
3. 정규 갱신(00:03 체인)이 끝났고, DART 보충 창이 아니다. 시작 시각은 13시 전입니다. 재빌드에 약 9시간이 걸리므로 자정 전에 끝나야 합니다.
4. 퀀티 재무 DB(FundV2_*)의 마지막 리프레시 날짜를 확인합니다. 분기 보고서 마감(5/15 · 8/14 · 11/14)이나 사업보고서 마감(3/31) 직후라면 리프레시를 먼저 합니다(§7).

## 2. 후보 만들기 · 검사 (정본 그대로 · 약 3분)

```bash
Rscript 02_Infrastructure/data/fundamental_produce_v2.R --candidate-only
```

```bash
.venv_qvest_ml/Scripts/python.exe -I 04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/tools/fd_order_audit.py fundamental_v2/candidate_fundamental_merged.parquet fundamental_v2/candidate_fundamental_xlsx.parquet
```

생산기가 검사하는 것:
- 열 구성
- 항목 수(병합 181 · 분기 41)
- 종목 2,000 이상
- 날짜 순서 계약(겹침 0 · 역전 0)
- Factor_Date > 기간 말
- 전환 뒤에는 행 수가 지금 정본의 95% 미만이면 멈춤

## 3. 한 달 시범 (권장 · 약 15분)

```bash
Rscript 04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/tools/fdb_trial.R v2 .cache/fundamental_v2/candidate_fundamental_merged.parquet <출력폴더> --xlsx .cache/fundamental_v2/candidate_fundamental_xlsx.parquet 2012-06-29 2025-06-30
```

```bash
.venv_qvest_ml/Scripts/python.exe -I 04_Research/01_reports/quantiwise_data_expansion_20261106/fundamentals_v2/tools/trial_compare.py <출력폴더> old v2 20250630 --fresh
```

- `old` 는 같은 방식으로 지금 정본을 넣고 만듭니다(`fdb_trial.R old .cache/fundamental_merged.parquet <출력폴더> 2012-06-29 2025-06-30`).
- 통과 기준
  - 전 종목 같은 값으로 굳은 팩터가 늘지 않는다.
  - 차이는 README §8 의 세 범주로 설명된다: 옛 표 결함 · 정의 차이 · 날짜(엄격한 시점 기준).

## 4. 전환 (정본 교체 · 약 3분)

1. 등록부 `06_Registry/fundamental_source.json` 의 `active` 를 `"v1"` → `"v2"` 로 바꾸고, history 에 한 줄을 남깁니다(시각 · 이유).
2. 실행:
   ```bash
   Rscript 02_Infrastructure/data/build_fundamental_derived.R
   ```
   로그에 `[source] 재무 원천 = v2 — 위임` 이 찍히고, 생산기가 사본을 뜬 뒤 정본을 교체합니다. 사본 위치는 `.cache/fundamental_backup/pre_v2_<시각>/` 이고, 표식 파일은 `.cache/fundamental_backup/ACTIVE_V2` 입니다.
3. 확인: `fd_order_audit.py fundamental_merged.parquet fundamental_xlsx.parquet` 가 rc 0 이어야 합니다. 병합 표에 `Origin` 열이 있어야 합니다.

## 5. 팩터 DB 전체 재빌드 (약 9시간 · 무인)

```bash
bash 02_Infrastructure/factor_db/run_factor_db_full_rebuild.sh --dry-run
```

```bash
bash 02_Infrastructure/factor_db/run_factor_db_full_rebuild.sh
```

- 순서: 사전 점검 → 월간 사본(`.cache/factor_db_backup/fund_v2_<시각>/factor_db` · 6~7 GB) → 월간 `build_factor_db_monthly(force = TRUE)`(07-25 실측 7.9시간) → 일간 `run_fdb_rebuild.sh`(~48분) → `compute_all_factor_ic_monthly()` → 요약 JSON · 텔레그램 1통.
- 사전 점검(걸리면 rc 3):
  - 등록부 `active = v2`
  - 13시 전
  - 리프레시 배리어 free(정규 갱신 · RAWDATA 쓰기 잠금)
  - 다른 팩터 빌드 없음
- 단계마다 시작 전에 배리어를 기다립니다(최대 2시간).
- 세션이 꺼져도 계속 돌도록, PowerShell `Start-Process` 로 세션과 떼어서 띄웁니다.
- 중간에 실패하면 요약 JSON(`.cache/scheduler_logs/factor_db_full_rebuild_<시각>.json`)에서 단계와 사본 경로를 보고, `--from daily` 또는 `--from ic` 로 이어서 돌립니다.

## 6. 검사 (Q)

- 월간 로그 `[FATAL]` 0 · emission_guard / identity_guard(굳은 팩터 · 회귀)
- `cache_freshness_audit` WARN 0 · `ic_frontier_check` CURRENT
- 덮음 대조(사본 = 옛 · 새)
  - 연도별 재무 팩터의 값 있는 종목 수
  - 부채비율 Q16 이 정확히 0 인 비율: 옛 99.9% → 새 약 36%(2025-06 시범)
- 스위트 총계 래칫: `bash 02_Infrastructure/ops/suite_totals_watch.sh --collect` → `--check`
- 기록: README §8 · 메모리 · decision_register(전환 사실)

## 7. 전환 뒤 정기 갱신 (11-09 등록 — 도훈 '2번 정기갱신 만든다')

- 예약 작업 `Qvest_FundV2Update`(커밋 510b30692)가 `ops/qw_fund_v2_update.ps1` 을 돈다. 갱신용 DB 5개(`FundV2_*_upd` · 최근 8분기)를 만들고 → DATA_Key 동기화 → 리프레시 → 부모 parquet 의 그 창을 교체한다(값 변화 = `revisions.parquet`).
  - 일정: 매주 토 13:00 + 공시 기한 다음 날(4/1 · 5/16 · 8/15 · 11/15) 13:00. 첫 실행은 11-14 13:00 이다.
  - 원본 XML = `ops/scheduler/_task_xml_backup/Qvest_FundV2Update.xml` · 실행기 = `ops/scheduler/Qvest_FundV2Update.bat` · 로그 = `.cache/scheduler_logs/fund_v2_update.log`.
  - 종료 코드: 0 = 끝 · 3 = 전제 조건 · 바쁨 · 세션 끊김 · 1 = 실패. 세션이 끊겨 있으면 재로그인하지 않고 3 으로 끝난다(재로그인은 드라이버 몫).
  - GAAP 은 2007년까지 항목이라 갱신 DB 가 없다.
- ✅실측(11-09 08:03~08:35 · 예약 작업 직접 실행 + META · INFO 재실행): BS 41/41 · IS 37/37 · CF 18/18 · META 20/20 · INFO 18/18.
  - 적재 결과는 신규 · 변경 · 삭제 모두 0 이다(11-08 밤 값과 같음). 1회 ≈ 25분(시트당 6~14초).
  - 첫 시도는 META 'CompInfo'(글 항목 · 늘 0칸 · 등록부 allow_empty)를 리프레시가 미갱신으로 세어 멈췄다 → 수리 커밋 207e801e1.
  - 그 전 07:40 에는 세션 끊김으로 BS 18/41 에서 멈췄고, 부분 책은 적재기 G1 이 거부했다. 재로그인 경위 = README §7.
  - 창 교체 논리 시험 = `test_qw_fund_v2_ingest.py` T9 · T9b.
- 첫 적재 전 부모 parquet 백업 = `.cache/fundamental_backup/qw_fund_v2_pre_upd_20261109/`(SHA256SUMS.txt).
- 월간 [5a2/7] 은 그대로 돕니다(v2 생산기에 위임). 입력(FundV2 parquet)이 새로워야 의미가 있습니다.

## 8. 되돌리기

1. 등록부 `active` 를 `"v1"` 로 바꾸고 history 를 남깁니다.
2. `.cache/fundamental_backup/pre_v2_<시각>/` 의 두 파일을 `.cache/` 로 복사하고, 표식 파일 `ACTIVE_V2` 를 지웁니다.
3. 팩터 DB
   - 월간: `.cache/factor_db_backup/<tag>_<시각>/factor_db` → `.cache/factor_db`(robocopy /MIR).
   - 일간: v1 원천으로 `run_fdb_rebuild.sh`(~48분).

## 9. 알려진 성질 (PIT)

- 정정 의심이거나 늦게 정정된 기간의 값은 정정 공시 뒤에만 씁니다. 그 사이에는 직전 기간 값이 쓰입니다(늦음).
  - '늦다'는 사실 자체가 나중에 정정된다는 정보를 담습니다. 그래서 자료 나이나 결측으로 표본을 거르지 않습니다.
- 날짜 순서 계약으로 버린 행(병합 2.5만 · 분기 18만)은 바로 뒤 기간의 '직전 기간 값' 자리를 비웁니다.
  - 소비자는 기간 차이를 보지 않기 때문에, 그 자리의 성장률은 두 기간 사이로 계산될 수 있습니다(병합 1.1만 · 분기 7.2만 곳).
- `Source` 는 옛 역할 표지(XLSX 분기 원계정 · xlsx_derived 분기 파생 · DART 연간)입니다. 실제 출처는 `Origin` 에 있습니다.
