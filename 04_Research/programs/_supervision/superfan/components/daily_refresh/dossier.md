# 데이터 갱신 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: daily_refresh`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#daily_refresh` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 데이터 갱신(Qvest_DailyRefresh · daily_refresh.sh)
- 일정: Qvest_DailyRefresh 매일 00:03 · 아침 체인 ensure_data_current 가 stale 이면 재실행
- 코드: `02_Infrastructure/data/daily_refresh.sh` · `02_Infrastructure/ops/ensure_data_current.sh` · `02_Infrastructure/ops/refresh_barrier.sh` · `02_Infrastructure/ops/scheduler/Qvest_DailyRefresh.bat`
- 감시 규칙:
- `run_failed` (log_patterns): 실패 스텝, 치명, R 오류, 적재 신선도 미달, 역할 재분류 실패
- `log_fresh` (freshness): .cache/scheduler_logs/daily_refresh.log

## 알려진 고장 형태 (기억 카드 · 실측)

- 퀀티(QuantiWise) 원천은 인터넷이 아니라 이 PC 의 단말 + 엑셀 애드인으로 받는다 — 단말 미로그인 · 애드인 실패면 consensus · investor_act 가 멈춘다(기억 카드 reference-quantiwise-…-20260918).
- run_r 은 실패를 누적해 끝에서 비-0 종료 · 텔레그램 본문에 실패 스텝을 병기한다(2026-07-26 DR-01 수리) — 종료 코드 1 은 '그날 어느 스텝이 실패했다'는 뜻이다.
- 재진입 가드: /tmp/qm_daily_refresh.lock — 살아 있는 pid 면 중복 인스턴스 종료(정상), 죽은 pid 면 인계.
- 적재 신선도 [0c] 는 정본 감사기 판정 — ★적재 미달은 하류가 낡은 축을 쓴다는 경보다(판정 제외 하류 산출물은 보고만).
- 데이터 오염은 적재가 아니라 원천 이음매에 산다(기억 카드 reference-data-corruption-lives-at-source-seams…).
- ★(10-16 실측) **Update_File 3종(Consensus · Investor_Act · Universe_Support)은 일일 체인이 수급하지 못한다.** daily_refresh `[0b]` 는 적재만 하고, xlsx 갱신(`ops/qw_refresh.ps1`)은 수동 실행이나 BOOK full 러너 [0] 에서만 돈다(무인 제외 = 08-29 계정 잠금 위험 결정 · `run_nolayer4_monthly.sh:36-38`). 그래서 수동 갱신과 다음 수동 갱신 사이가 길어지면 consensus · investor_act 가 10일 문턱을 넘는다(STALE 구간 09-07~09-19 · 10-03~10-06 · 10-15~).
- ★(10-16) 수동 갱신을 `-Only Investor_Act,Consensus` 로 돌리면 Universe_Support 가 빠진다 — 08-29 뒤로 한 번도 갱신되지 않아 9월 말 스냅샷이 없다(10-10 부터 40일 문턱 초과).
- ★(10-16) **퀀티 무응답이 rc=2 'no_change'(원격 == 우리 것)로 찍힌다** — `qw_excel_refresh.ps1:271-274` 가 시트별 `responded` 를 판정에 쓰지 않는다. 무응답이면 1800초를 다 기다린다(실행당 약 30분). 판별: 응답 있음 · 전진 없음 = 정당한 rc=2(휴장 다음 날) / 응답 없음 = 세션 없음.
- ★(10-16) 로그인 실패 형태 셋: ① 중복 로그인 경고 `Quantiwise7G` '예' 클릭 뒤 창이 남거나 응답이 없다(공유 계정의 다른 PC 세션) ② `전면 전환 실패 — 키 입력을 보내지 않는다`(예약 실행이 로그인 창을 앞으로 못 올림 · 화면 잠금) ③ `terminal_start_failed`(런처가 qwMain 을 못 띄움). `LOGINCOMPLETE=0` 은 그 자체로는 판정 근거가 아니다(기억 카드) — 무응답과 같이 볼 때만 쓴다.
- ★(10-16) **ensure_data_current 가 퀀티 패널 낡음을 '리프레시로 고칠 수 있는 항목'으로 센다**(`_actionable` · 128-146행) → 퀀티 패널이 낡은 동안 영업일마다 첫 아침 호출이 2시간 넘는 헛 전체 재실행을 하고(10-05 07:14→09:22 · 10-16 07:12→09:37 · 같은 날 재시도는 3b 가드가 막는다) 모닝 브리핑이 늦어진다.
- ★(10-16) `[8.1r]` — `rf_role_register_reps.R:31` 은 미등재 대표 0건이면 0열 표에 `by = code` 를 써서 멈춘다. 분류 · `strategy_roles.json` 갱신 · [8.2] 풀 조립은 정상이다. 경고 문구 '직전 레지스트리로 풀 조립'은 이때 사실이 아니다.
- universe_support 표식은 `apply_universe_mapping.R:87` `roll = Inf` 로 기한 없이 이어진다 — 낡아도 RAWDATA 에는 값이 있다. 낡음은 [0c] 감사기와 BOOK 사전점검만 잡는다. 위생 판정식(`corp_action_member`)은 표식 NA 를 통과로 본다.

## 기준선 — 정상일 때의 모습

- 실행 경로 · 로그: 예약 실행(.bat)만 `.cache/scheduler_logs/daily_refresh.log` 에 남는다. 아침 체인 · BOOK 러너 · 세션 실행은 `/tmp/qm_daily_refresh_YYYYMMDD.log`(Windows `%TEMP%` · 같은 날 여러 실행이 append)에만 남는다 — 이력을 볼 때는 둘 다 본다.
- `Qvest_DailyRefresh` 로그온 모드 = '대화형만'. PC 가 꺼져 있던 날은 다음 로그온 뒤 아침 체인(ensure_data_current)이 보충한다.
- 소요(10-16 실측): 데이터 구간 [0]~[0c] 00:03→00:45(이 중 퀀티 무응답 대기 약 30분 — 정상 세션이면 1분 미만) · 잠금 해제 뒤 후처리([7] 텔레그램 · [7.9] 위생 · [8] 인덱스 · [8.1] 배선 · [8.1r] 역할(분류 약 128초) · [8.2] · [9] suite-totals)까지 Done 02:57. DART 분기 예산 3000콜 ≈ 25분(backlog 는 resume 으로 이어진다).
- [1pre] 정상: 세션이 있으면 벤치 수급 전체가 1분 안에 끝난다(10-05: 실행 시작 00:03:01 → 정본 교체 00:03:50). 새 거래일이 있으면 rc=0 `updated`, 없으면 rc=2 + 응답 있음(10-06 13:44).
- [0b] `Update_File 변경 없음.` 은 그날 qw_refresh 가 돌지 않았다는 뜻이다(평상시 대부분).
- 아침 체인: 고칠 것이 없으면 ensure_data_current 가 `이미 최신` 으로 넘어가고 morning_run 은 07:12~07:19 에 끝난다(10-04 · 10-07). 리프레시를 다시 돌리면 09시대로 밀린다.
- [0c] 문턱(freshness_audit.R): rawdata · msm · ktri · regime 3d · benchmark 2d · fred 4d · consensus · investor_act 10d · universe_support 40d(월말 스냅샷) · fred_wide 14d · p3_forecast = 하류(판정 제외).
- [8.1r] 정상 4줄: `분류 n · 역할 B+ 보유 m` / `풀 대표 고유 전략 k · 계보 l` / `레지스트리 기록: N → strategy_roles.json` / `대상 j · 등재 실행`(10-16: 분류 1302 · 레지스트리 1320 · 역할 대표 82 · 칸/기저 69 · 카탈로그 1002).
- 상시 WARN(이상 아님 · 오늘 원인과 무관): `[mapping] Layer 1 (KRX) Sector NA = 100%`(섹터는 Layer 2 가 채운다) · `[6b] fdb_daily stale`(자동 재빌드 OFF 설계 — factor_db) · `[regime-append/daily] 동결 구간 재서술 시도 — 발행본 보존`(08-14 부터 매일 · FRED 소급 개정 드리프트 · 감시 규칙 없음) · cache freshness audit WARN 10건(등록부 미등재 캐시 등).
- 신선도 이력(소비 패널 max(Date)): consensus · investor_act 08-28 → 09-18(09-19 수동) → 10-02(10-06 수동) · universe_support 08-28(08-29 수동 뒤 없음).

## 사건 기록 (최신이 위)

- **2026-10-16 — ingest_freshness 실패 + [8.1r] R 오류** · 상태: 진단됨 · 수리 대기(도훈 퀀티 로그인 · R1~R3 Q 수리 · R4 도훈 결정)
  - 증상: 00:03 실행 `Done — ★실패 1스텝: ingest_freshness`(100207행) · `[0c] ★적재 미달: consensus 13d · investor_act 13d · universe_support 48d`(100154) · `[8.1r]` `object 'code' not found`(100196~100201). 07:12 아침 체인이 같은 3항목으로 전체 재실행 → 09:37 같은 결과.
  - 근본 원인: ① 퀀티 세션이 10-06 오후 이후 살아 있지 않다(login_required · login_failed(전면 전환 실패) · terminal_start_failed · 애드인 무응답 · 지금 qwMain 프로세스 없음) ② Update_File 수급 호출 계기 부재(구조) ③ 수동 갱신에서 Universe_Support 누락 ④ `rf_role_register_reps.R:31` 빈 대상 결함(10-09 · 10-10 · 10-16 재현 · 대상 ≥1 인 10-08 · 10-15 은 정상).
  - 부수: ensure_data_current 헛 재실행(모닝 브리핑 약 2.5시간 지연) · 퀀티 무응답 rc=2 오분류 · 30분 대기.
  - 영향: PIT 위반 없음. 측정 축 위생 · 지수 멤버십이 2026-09-30 신호일에 8월 말 표식(크기 미측정) · 202610 확정 빌드(10-30) 전 미복구 시 컨센서스 · 수급 팩터가 10-02 값으로 굳음 · BOOK_0001 11-01 리밸은 사전점검이 막는다(설계대로) · 모닝 브리핑 지연.
  - 수리안: R1 `rf_role_register_reps.R:29-33` 빈 대상 분기 · R2 `ensure_data_current.sh:128-146` 퀀티 적재 전용 항목 분리(xlsx -nt parquet 일 때만 대상) · R3 `qw_excel_refresh.ps1:203-223 · 271-274` 무응답 rc=3 + 300초 조기 중단 · R4(도훈 결정) 벤치 rc=0 인 밤에만 `qw_refresh.ps1 -SkipLogin -Only …` + [0b] 재적재.
  - 다른 구성요소: scheduler(10-11~10-14 실행 0 · 대화형만) · factor_db(확정 뒤 추격 적재 재빌드 계기 의심) · morning_chain(p3_forecast 10-02).
  - 보고서: `20261016_2100_diagnosis.md`
- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
