# 감사 레인 A — 데이터 리프레시 · DB 관리 (2026-11-10)

## 1. 배선 지도 (코드 · 로그로 확인한 것)

- 예약 작업 → `C:\Users\User\AppData\Local\Qvest\jobs\<task>.cmd`(qvest_tasks.ps1 생성 · 11-07 15:54 · 기계 게이트 `qvest_machine.sh gate`) → `02_Infrastructure/ops/scheduler/<task>.bat` → 스크립트. `C:\Users\99922` = `C:\Users\User` 정션(경로 하드코딩은 정션으로 살아 있다).
- Qvest_DailyRefresh 00:03 (limit 72h · StartWhenAvailable) → `data/daily_refresh.sh`(잠금 `/tmp/qm_daily_refresh.lock`) :
  [0a] 베이스 xlsx 재빌드 → [0b] Update_File 증분 → [1pre] 벤치(quantiwise_fetch.py → build_index_cache.py) → [1pre-dk] 신규 상장 DATA_Key → [1pre-qw] 퀀티 Update_File 4종(qw_updatefile_unattended.sh · 목표일 = 벤치 최신일 기준 직전 거래일) → [1z] Size 채움 → [3] 유니버스 · 매핑 → [3b] BM_Ret 동기화 → [4] Arrow/FRED/KTRI/MSM as-of/국면 + cache_freshness_audit + [4gm] 거시 → [5a/5b] DART → [5c] FF 요인(build_kr_factor_returns.R) → [6a] 팩터 DB 월(update_factor_db_daily) → [6b] fdb_daily 감시(재빌드 꺼짐) → [6d] 백필 → [6f] 방향 동기화 → [6e] 결합용 뷰 → [6g] 대응표 → **[6v] 판 표식 원장 감시(신설)** → [6c] cond IC(월) · 비-return 원천 → [0c] freshness_audit.R(적재 후) → 잠금 해제 → [7] 텔레그램(서명 관문 dr_fail_signature) → [7.9] 위생 → [8] 산출물 색인 → [8.1] 배선 지도 → [8.1r] 역할 재분류 → [8.2] 모듈 성능 → [9] suite_totals_watch --collect(시험 배터리 전체) → exit(DR_FAILED ? 1 : 0).
- Qvest_MorningBrief 07:10 (limit 3h12m) → morning_briefing.sh [0/5] → `ops/ensure_data_current.sh`(edc): 사전 감사(freshness_audit.R · quiet) + 퀀티 축(krx_holidays.py currency = 벤치만) → stale 이면 daily_refresh.sh 를 **QVEST_REFRESH_TG=0** 으로 실행 → 사후 감사 → 스탬프 `.cache/data_currency_stamp.json`.
- Qvest_FundV2Update(주 1회 토 13:00) → `ops/qw_fund_v2_update.ps1`(퀀티 Peer 책 갱신 → `.cache/qw_fund_v2/*.parquet`) → 재무 v2(`06_Registry/fundamental_source.json` active = v2).
- Qvest_StrandedRepairs 12:00/20:00 → stranded_repairs_audit · handbook_facts · **scheduler_task_health.sh**(예약 작업 바깥 경계 · 텔레그램 1/일).
- Qvest_StressDaily 04:00 → 벤치 준비(krx_holidays currency)만 기다린 뒤 run_daily_stress.sh(RAWDATA · 수급 · 거시 사용).
- 측정 소비면: round.sh measure = "Daily Refresh v2 Done" 줄 증가(실패 완주도 셈) 또는 06~12시 → refresh_barrier.sh(잠금만) → precheck(등록 · 핀) → fingerprint.sh(RAWDATA · 벤치 · fundamental_merged(v1!) · 팩터 DB 크기 · mtime). **데이터 신선도 검사는 측정 경로에 없다.** BOOK 리밸만 book_rebalance_preflight.py 가 sig 도달을 막는다.

## 2. 오늘 결과 1 의 원인

| 작업 | 원인(로그) | 성격 | 상태 |
|---|---|---|---|
| DailyRefresh 00:03 rc=1 | `build_index_cache.py:74` `pa.array(df[c].astype("float64"))` 가 BM_Src 문자열 열('quantiwise_iks200')을 float 로 캐스팅 — pandas 3(11-08 환경 최신화)이 문자열 열을 StringDtype 로 만들어 구판 `dtype == object` 판별이 빗나감 → 벤치 미갱신(11-06) → 캘린더 · 퀀티 목표일 11-06 → Update_File no_advance → RAWDATA 11-06 정지. 보고: `benchmark_currency(gate_rc=1,updater_rc=1) ingest_freshness` 텔레그램 1통 | 코드 결함 | 다른 세션이 07:49 수리(925b2e4a9 · is_numeric_dtype 판별). 07:17 벤치 11-09 재생성 확인 |
| 07:14 자가 복구 리프레시 rc=1 | edc(07:14)가 벤치 지연으로 리프레시 실행 → [1pre-qw] 퀀티 세션 **kicked 2회**(07:28 · 08:17) → done=0/4 → RAWDATA 11-06 그대로. `QVEST_REFRESH_TG=0` 이라 [7] 미발송, 사후 감사 FRESH → `refreshed_current` | 환경(퀀티 세션 경쟁 — 원인 주체 미확인) + **판정 결함(아래 F1)** | F1 수리로 다음부터 STALE + 사후 감사 텔레그램 1통 |
| MorningBrief 267014 | 실행 한도 3h12m(07:10 → 10:22) 초과로 작업 종료. 자식 리프레시는 12:15 까지 살아 있었고(부모 kill 이 자손을 못 죽임) 브리핑 로그는 12:17 끝 | 한도 · 고아 프로세스 | 미수리(제안 P3) |
| FundV2Update 11-09 rc=1 | FundV2_META_upd 의 CompInfo 시트(글자 항목 · 0셀) 를 NOT REFRESHED 로 셈 → rc=1. bat 의 `rc=%QV_RC%` 가 `1>>` 로 파싱돼 'end rc=' 빈 값 | 코드 결함 2 | 11-09 08:35 다른 세션 수리(207e801e1 · allow_empty) + 수동 재실행 rc=0. 작업 LastTaskResult 는 11-14 까지 1 로 남는다(task_health 는 '기보고'로 접음) |

연속성: DailyRefresh 는 11-08 · 11-09 · 11-10 사흘 연속 exit 1(task_health.log). 11-08 · 11-09 는 p3_forecast 외 원인 미확인(로그 회전 — /tmp 로그는 당일분만).

## 3. RAWDATA STALE_CRITICAL — 지금도 참

- 실측 13:2x: `RAWDATA max(Date) = 2026-11-06` · 벤치 2026-11-09 · 직전 거래일 2026-11-09 → **1 세션(11-09) 누락, 참**.
- 리프레시가 못 고친 이유: 00:03 = 벤치 writer 사망 → 목표일 11-06(정상 동작상 전진 0) · 07:14 = 퀀티 세션 kicked 2회.
- 두 감사기가 갈렸다: `cache_freshness_audit.R`(셀 단위 · registry max_lag 1 × 2) = STALE_CRITICAL, `freshness_audit.R`(edc · [0c] 가 쓰는 '정본') = FRESH(달력 lag 3d ≤ 3d). 정본이 틀린 쪽이었다.
- 낡은 채 측정이 시작될 수 있는가: **예.** round.sh 는 Done 줄(실패 완주 포함)과 잠금만 본다. 연구 측정(2000~ 이력)에서 1세션 지연의 수치 영향은 작지만, 시험 창 끝 · 행동 카드 최근 위기 · 스트레스 지수 · 국면 라벨 최근값은 낡은 축 위에서 '오늘 것'으로 표기된다. BOOK 리밸은 preflight 가 막는다.

## 4. 시나리오 표

| 시나리오 | 기대 | 수리 전 실제 | 조치 | 시험 |
|---|---|---|---|---|
| 주말 낀 1세션 누락(11-10 재현) | STALE | FRESH(달력 3d≤3d) — [0c] '전 소스 FRESH' · edc refreshed_current | F1 세션 축 | test_scn_data_freshness_session.R (S2 · S2-HEAD 로 수리 전 FRESH 재현) |
| 긴 연휴(2025 추석+한글날) | FRESH | FRESH | 회귀 없음 확인 | 같은 파일 S3 · S3b |
| 휴장일 등록부 없음 | 기존 동작 | — | 세션 축 NA · 달력 축 | S4 |
| 중간 단계 실패 | 누적 · 계속 · exit 1 | 정상 | — | test_scn_data_chain_failure.sh C1~C4 |
| 자가 복구 리프레시 rc=1 + 사후 FRESH | 경보 | refreshed_current · exit 0 · 텔레그램 0 | F1 로 사후 감사가 STALE → stale_after_refresh · 사후 감사 텔레그램 1통 | 같은 파일 E1(침묵 경로 기록) · E2 |
| 같은 영업일 재실행 | 재시도 0 · exit 3 | 정상 | — | E3 |
| 팩터 DB 수리 요약 ↔ 원장 누락 | 감지 | 감지기 없음(원장 수기) | F3 [6v] 감시 | test_scn_data_fdv_coverage.sh V1~V8 |
| 부분 수리 뒤 당월 옛 코드 | 감지 | [6a] 는 데이터 상태만 봄 — 7일 묵음 | F3 current_month 축 | V5 |
| 예약 작업 never_run(next_run 있음) | 경보 | 어느 축에도 안 걸림 | F2 첫 관측 기억 축 | test_scn_data_task_never_run.sh N1~N9 |
| 동시 실행 | 두 번째는 exit 0 | 정상(mkdir 잠금 · stale 인계) | — | 기존(refresh_barrier 시험) · 미추가 |
| 실행 중 스크립트 편집 | 영향 없음 | **suite_totals_watch.sh 10:08 편집 → 실행 중 [9] 가 line 249 구문 오류**(같은 기전 09-18 exit_2) | 제안 P2 | 미추가(실행 스냅숏이 필요) |

## 5. 수리한 결함

- **F1** `02_Infrastructure/ops/morning_steps/freshness_audit.R` — `.sess_lag()` + `check_freshness(max_sess=)` · rawdata · benchmark `max_sess = 0`. 세션 = (last, as_of] 평일 중 `06_Registry/krx_holidays.json` 휴장일 아닌 날. 근거: as_of 가 이미 직전 거래일이라 달력 3d 여유는 주말을 두 번 센다 · daily_refresh.log [0c] 이력 10-07 · 10-16 · 11-07 정상 실행 rawdata lag 0d · 퀀티 목표일 = 직전 거래일(로그 'target (last trading day)'). 이력 재생: 10-20 · 11-10 은 진짜 누락(벤치도 지연), 10-10(한글날)은 세션 0 으로 FRESH 유지. 시험 16/16 · 기존 test_dr_freshness_gate.py 16/16. ⚠ 미설치 F6 후보(`04_Research/01_reports/quantiwise_data_expansion_20261106/candidates_F6/freshness_audit.R`)를 설치할 때 이 변경을 합쳐야 한다.
- **F2** `02_Infrastructure/ops/scheduler_task_health.sh` 판정 블록 — never_run ∧ 시각 트리거 ∧ 활성 작업의 첫 관측 시각을 `.cache/scheduler_alerts/task_first_seen.json`(키 = COMPUTERNAME|작업)에 기억, 그 뒤 max_stale_days(수집기 값: 일 2 · 주 9 · 월 35) 초과 시 정체. 첫 관측 이전은 세지 않는다(오늘 설치 → WeeklyCleaner 는 11-14 에 안 돌면 11-19 경보). 시험 13/13 · 기존 test_scheduler_task_health_verdict.sh 41/41.
- **F3** `02_Infrastructure/data/factor_db_vintage_coverage.py`(신설 · 읽기 전용) + `daily_refresh.sh` [6v] 단계(GAP → DR_FAILED `factor_db_vintage_gap`, 판독 불가 → `factor_db_vintage_unmeasured`). 현재 운영 판정: OK · 결정 기록 누락 1(`FACTOR-DB-TOTALDEBT-ZERO-REPAIR-20261110` — decision_register 0건, 사실 확인). 시험 13/13.

## 6. 못 고친 결함(패치 제안)

- P1 `04_Research/programs/_lib/round_core/round.sh:61-69` — 대기 조건이 "Done 줄 증가"라 실패 완주도 통과. `qepm/observability/morning_freshness_latest.json` 의 `stale_count == 0`(또는 rawdata · benchmark FRESH) 확인을 배리어 뒤에 추가하거나, 최소한 미달이면 측정 로그 · 사전등록 산출에 `data_asof` 표기. (총괄 통합 중 경로)
- P1b `round_core/v1/fingerprint.sh:13` — equality 가 `fundamental_merged.parquet`(v1)을 본다. 재무 active = v2 → `fundamental_merged_v2.parquet` · `.cache/qw_fund_v2/` 추가(판본 비교가 v2 변경을 못 본다).
- P2 `daily_refresh.sh` 머리 — 실행 중 편집 방지: 시작 때 자신과 [9] 스크립트를 임시 사본으로 복사해 사본을 실행(경로 해석은 원본 디렉터리 인자로). 오늘 [9] 구문 오류 · 09-18 exit_2 가 같은 기전.
- P3 `Qvest_MorningBrief` 한도 3h12m 초과 시 자식 리프레시가 고아로 남음 — edc 의 리프레시 대기 상한을 작업 한도 안에 두거나, 리프레시를 별도 작업으로 기동. 그리고 edc 경로 리프레시도 [7] 을 서명 관문 경유로 발송(`QVEST_REFRESH_TG=1`)하면 kicked 같은 비데이터 실패가 보인다(서명 관문이 중복을 막음 — 확인 필요).
- P4 [9] suite_totals 를 밤 체인에서 빼거나 lean 프로필 · 별도 주간 작업으로(속도 §8).
- P5 `freshness_audit.R` consensus · investor_act(max 10d) · universe_support(40d) 는 10-17 부터 매일 퀀티로 들어오는데 문턱이 옛 주기 그대로 — 세션 축 적용 검토(10월 초 10d 초과 이력이 있어 소음 위험 → 도훈/Q 판단).
- P6 Stress 지수 — 준비 조건이 벤치뿐. 11-10 실행은 day=11-09 로 표기됐는데 RAWDATA 는 11-06(breadth · 수급 축 처리 방식 미확인 — ffill 이면 침묵).
- P7 `qw_fund_v2_update.ps1` — rc=1 안내 문구가 '(4 = kicked …)' 로 원인과 무관하게 찍힌다(오진 유도).
- P8 FundV2Update 작업에 같은 1회 트리거(2026-11-09T13:00) 4개 중복 — 무해하지만 qvest_tasks.ps1 Apply 정리 대상.

## 7. 업데이트 누락 감지 표

| 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 |
|---|---|---|---|---|---|
| RAWDATA | [0b]/[1pre-qw] 퀀티 | 매일 | freshness_audit(세션 0 · **수리**) · cache_freshness_audit | 측정 전부 · 팩터 DB · 스트레스 | [0c] DR_FAILED + 텔레그램 · edc stale_after_refresh · **측정은 침묵** |
| benchmark | [1pre] | 매일 | 둘 다 + bm-gate | 캘린더 · 등급 벤치 | 차단 아님 · 경고 |
| 재무 v2 | FundV2Update(주) · [1pre-dk] | 주 1회 | **없음**(cache_freshness_audit WARN 만: fundamental_merged_v2) | 팩터 DB · FF 요인 | 침묵 |
| 팩터 DB 월 | [6a] | 데이터 경계 변경 시 · 당월 7일 묵음 | EMISSION_GATE(배출) · [6v](수리 뒤 당월) | 측정 · 상설 판 | 침묵(데이터 정지 땐 빌드 0 이 정상으로 보임) |
| fdb_daily | 수동(재빌드 꺼짐) | — | [6b] WARN | 일간 접근자 | 경고만 |
| 결합용 뷰 | [6e] | 매일 증분 | 잠금 · rc | fc_load_month | 경고 |
| FF 요인 | [5c] | 매일 | rc · meta md5 일치(등급 노치) | grade_v3 노치 | 노치 미계산(침묵에 가까움) |
| 판 표식 원장 | 수기(Q) | 수리마다 | **[6v] 신설** | A 자격 · P4 | DR_FAILED |
| 거시 ECOS/FRED | [4] · [4gm] | 매일 | freshness_audit fred(4d) · fred_wide(14d) | 국면 · 스트레스 | [0c] |
| 컨센서스 · 수급 | [1pre-qw] | 매일 | 10d(옛 주기) | 팩터 · 스트레스 | 10일까지 침묵 |
| 내부자 | [5b] · InsiderBackfill | 매일 | 없음 | 팩터 | 침묵 |
| 국면 라벨(unified_regime_daily) | [4] | 매일 | 3d 달력 | 2계층 · 오버레이 | 1세션 누락 침묵(세션 축 미적용) |
| 스트레스 지수 | StressDaily | 매일 | 벤치 준비만 | 브리핑 | 침묵(P6) |
| 예약 작업 실행 자체 | Windows | — | task_health(rc · 나이 · 다음 실행 · **never_run 신설**) | 사람 | 텔레그램 1/일 |

## 8. 속도 (11-10 로그 · 산출물 mtime)

- 1차(00:03): 적재 [0]~[0c] 61분(00:03 → 01:04) · 후처리 [7]~[9] **150분**(01:04 → 03:34).
- 2차(07:14): 퀀티 대기 63분(kicked) · DART 등 → 08:57 · 후처리 **197분**: 위생 1분 · 색인 1분 · 배선 지도 15분(09:00 → 09:15) · 역할 4분 · 모듈 9초 · **[9] 스위트 총계 176분**(09:19 → 12:15 · 시험 10,975개 실행).
- 상위 3: ① [9] suite_totals(전 배터리) 2~3시간 ② [5b] DART 증분 31분 ③ [0b] Update_File 증분 ≈14분 / 배선 지도 15분.
- 단축안(판정 불변): [9] 을 주 1회 별도 작업(또는 lean 프로필)로 — 밤 체인 3시간 감소 · 잠금 해제 뒤라 측정 대기는 이미 없지만 CPU · 디스크 경합과 실행 중 편집 사고 창이 사라진다. 배선 지도 · 색인은 git 변경 없을 때 건너뛰기.

## 9. P/L 우상향 관점 최대 제약 3

1. **판정 정본이 틀릴 때 아무 것도 막지 않는다** — 11-10 두 감사기가 갈렸고 소비자가 쓰는 쪽(freshness_audit)이 FRESH 였다. 측정 경로엔 신선도 검사가 없어(round.sh = Done 줄 · 잠금) 낡은 축 위 결과가 '오늘 것'으로 남는다(시험 창 끝 · 위기 복원력 최근 구간).
2. **팩터 DB 판 관리가 수기** — 11-08~11-10 세 번의 큰 수리 · 원장은 손으로 한 줄씩(결정 기록에는 1건 누락). [6a] 는 코드 판을 모른다. 기저 풀 · A 자격이 '낡음' 판정을 이 원장 하나에 의존한다 → [6v] 로 감시만 추가.
3. **퀀티 단일 원천** — 10-17 이후 보충 원천 0. 벤치 writer 1줄 · 세션 kicked 1회가 RAWDATA 전체를 하루 멈춘다(11-08~11-10 사흘 연속 exit 1). 재시도는 다음 밤뿐.

## 10. 도훈 결정이 필요한 것

- D1 [9] 시험 배터리를 밤 체인에서 빼서 주간 작업으로(권고: 예 — 3시간 · 실행 중 편집 사고 제거).
- D2 컨센서스 · 수급 문턱(10d) 을 세션 축으로 좁힐지(권고: 2주 관찰 뒤 — 10월 초 10d 초과 이력).
- D3 퀀티 세션 kicked 시 같은 밤 재시도 정책(권고: 07:10 edc 1회 재시도는 이미 있음 — 그 이후는 사람 로그인. 바꾸지 않음).

## 11. 바꾼 파일 · 시험

- 수정: `02_Infrastructure/ops/morning_steps/freshness_audit.R` · `02_Infrastructure/ops/scheduler_task_health.sh` · `02_Infrastructure/data/daily_refresh.sh`([6v] 블록만)
- 신설: `02_Infrastructure/data/factor_db_vintage_coverage.py` · `08_Tests/scenarios/test_scn_data_freshness_session.R`(16/16 · 35s) · `test_scn_data_task_never_run.sh`(13/13 · 33s) · `test_scn_data_fdv_coverage.sh`(13/13 · 24s) · `test_scn_data_chain_failure.sh`(11/11 · 62s)
- 회귀: test_dr_freshness_gate.py 16/16 · test_scheduler_task_health_verdict.sh 41/41
- 운영 반영 시 첫 효과: 다음 freshness_audit 실행이 RAWDATA(11-06)를 STALE 로 낸다(퀀티 미복구 시) → 텔레그램 1통(사후 감사) · [0c] DR_FAILED.
- 미확인: 11-08 · 11-09 DailyRefresh exit 1 원인(로그 회전) · 07:28 kicked 주체 · WeeklyCleaner 가 11-08 09:00 에 왜 안 돌았는지(등록 시각 판독 불가) · 스트레스 지수 RAWDATA 결손 처리 · edc 경로 리프레시의 기계 게이트 우회 여부(/qvest 부팅 백그라운드).

## 12. 2단계(총괄 지시) — 일일 체인 · 아침 자가 복구 수리

- daily_refresh.sh: ① 실행 사본(시작 때 /tmp/qm_dr_snapshot_*.sh 로 exec · 원본 디렉터리 QVEST_DR_SRC_DIR · 2일 지난 사본 정리) ② 단계 8개
  (ingest qw universe macro dart krf fdb nonret) + 상태 파일 .cache/daily_refresh_state.json(단계:ok|failed:초 · failed 목록 · reported) ·
  QVEST_DR_ONLY_STAGES 로 단계 선택 · 건너뜀 로그 1줄 ③ QVEST_DR_MODE=selfheal → 후처리 · 배터리 생략 ④ [9] 층 QVEST_BATTERY_TIER
  (평일 밤 nightly · 토요일 밤 = 일요일 00:03 실행 weekly) · QVEST_DR_SKIP_BATTERY=1 ⑤ [7] QVEST_DR_REPORT_TG=1 이면 자가 복구에서도 서명 관문 1통 ·
  RAWDATA 2열만 읽기 ⑥ --dry-run(잠금 · 적재 · 발송 없음 · DR_PLAN 줄).
- dr_heal_plan.py(신설): 실패 · 미완 단계 + 하류(DOWN 표) · 모르면 FULL.
- ensure_data_current.sh: 계획 → selfheal 실행(배경) · 상한 QVEST_EDC_HEAL_TIMEOUT_MIN=150(근거 = 적재 구간 실측 15회 중 13회 ≤104분 · 작업 상한 192분)
  · 초과 시 MSYS 자손 + 윈도 트리 종료 · 죽인 실행의 잠금 정리 · 알림 1통(보고 전 사망 · 상한) · [7] 보고가 나갔으면 사후 감사 조용.
- freshness_audit.R: --check 진입점(계약 = 파일 머리) · 날짜 열만 읽기.
- 스트레스 일보: 시작 조건에 RAWDATA ≥ 직전 거래일 추가(P6). FundV2: 중단 사유 rc 별 문구(P7).
- 11-08 exit 1 = 퀀티 애드인 무응답(no_response · 환경) · 11-09 exit 1 = [0b] OHLCVS 관문 not_advanced 거짓 실패(11-09 07:33 a25239c25 수리 완료) +
  dk_sync rc=3(FundV2_IS 책이 다른 세션에 열려 있음 · 동시 실행).
