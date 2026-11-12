# 데이터 갱신 전담 Superfan — dossier

> 이 구성요소의 전담 Superfan(`superfan-component` · `구성요소: daily_refresh`)의 기억이다. 사건마다 한 건씩 위에 쌓는다(최신이 위).
> 정의 = `06_Registry/superfan_components.json#daily_refresh` · 규약 = `00_Lawbook/specs/superfan_protocol.md` §10.

## 담당 범위

- 이름: 데이터 갱신(Qvest_DailyRefresh · daily_refresh.sh)
- 일정: Qvest_DailyRefresh 매일 00:03 · 아침 체인 ensure_data_current 가 stale 이면 재실행
- 코드: `02_Infrastructure/data/daily_refresh.sh` · `02_Infrastructure/ops/ensure_data_current.sh` · `02_Infrastructure/ops/refresh_barrier.sh` · `02_Infrastructure/ops/scheduler/Qvest_DailyRefresh.bat`
- 함께 보는 코드(11-12 추가 · 정의에는 없음): 퀀티 4종 래퍼 `data/qw_updatefile_unattended.sh` · 드라이버 `ops/qw_refresh.ps1` · 세션 확인 `ops/qw_session_ensure.sh` · 복구 계획기 `data/dr_heal_plan.py` · 매시 틱 `ops/data_selfheal_tick.sh`(예약 작업 Qvest_StandingBoard :37) · 적재기 `data/incremental_update_file.R` · 신선도 판정 `ops/morning_steps/freshness_audit.R`
- 감시 규칙:
- `run_failed` (log_patterns): 실패 스텝, 치명, R 오류, 적재 신선도 미달, 역할 재분류 실패
- `log_fresh` (freshness): .cache/scheduler_logs/daily_refresh.log
- ★(11-12) 빈틈: 'Done 이 나왔는가' · '자가 복구 뒤에도 낡았는가'(`.cache/data_currency_stamp.json`) · 자가 복구 로그(`/tmp/qm_morning_briefing_*.log`)를 재는 규칙이 없다 — 수리안 W1~W4(20261112_2201_diagnosis.md §4)

## 알려진 고장 형태 (기억 카드 · 실측)

- 퀀티(QuantiWise) 원천은 인터넷이 아니라 이 PC 의 단말 + 엑셀 애드인으로 받는다 — 단말 미로그인 · 애드인 실패면 consensus · investor_act 가 멈춘다(기억 카드 reference-quantiwise-…-20260918).
- run_r 은 실패를 누적해 끝에서 비-0 종료 · 텔레그램 본문에 실패 스텝을 병기한다(2026-07-26 DR-01 수리) — 종료 코드 1 은 '그날 어느 스텝이 실패했다'는 뜻이다.
- 재진입 가드: /tmp/qm_daily_refresh.lock — 살아 있는 pid 면 중복 인스턴스 종료(정상), 죽은 pid 면 인계.
- 적재 신선도 [0c] 는 정본 감사기 판정 — ★적재 미달은 하류가 낡은 축을 쓴다는 경보다(판정 제외 하류 산출물은 보고만).
- 데이터 오염은 적재가 아니라 원천 이음매에 산다(기억 카드 reference-data-corruption-lives-at-source-seams…).
- ★(10-16 실측) **Update_File 3종(Consensus · Investor_Act · Universe_Support)은 일일 체인이 수급하지 못한다.** daily_refresh `[0b]` 는 적재만 하고, xlsx 갱신(`ops/qw_refresh.ps1`)은 수동 실행이나 BOOK full 러너 [0] 에서만 돈다(무인 제외 = 08-29 계정 잠금 위험 결정 · `run_nolayer4_monthly.sh:36-38`). 그래서 수동 갱신과 다음 수동 갱신 사이가 길어지면 consensus · investor_act 가 10일 문턱을 넘는다(STALE 구간 09-07~09-19 · 10-03~10-06 · 10-15~).
  - (11-12 갱신 · 사료) 10-17 부터는 `[1pre-qw]` 가 4종(OHLCVS → Universe_Support → Investor_Act → Consensus)을 `-SkipLogin` 으로 매일 받는다(RAWDATA-QW-ONLY-20261017 · 10-16 진단 R4 의 확장). 지금의 고장 형태는 아래 11-12 항목들이다.
- ★(10-16) 수동 갱신을 `-Only Investor_Act,Consensus` 로 돌리면 Universe_Support 가 빠진다 — 08-29 뒤로 한 번도 갱신되지 않아 9월 말 스냅샷이 없다(10-10 부터 40일 문턱 초과).
- ★(10-16) **퀀티 무응답이 rc=2 'no_change'(원격 == 우리 것)로 찍힌다** — `qw_excel_refresh.ps1:271-274` 가 시트별 `responded` 를 판정에 쓰지 않는다. 무응답이면 1800초를 다 기다린다(실행당 약 30분). 판별: 응답 있음 · 전진 없음 = 정당한 rc=2(휴장 다음 날) / 응답 없음 = 세션 없음.
- ★(10-16) 로그인 실패 형태 셋: ① 중복 로그인 경고 `Quantiwise7G` '예' 클릭 뒤 창이 남거나 응답이 없다(공유 계정의 다른 PC 세션) ② `전면 전환 실패 — 키 입력을 보내지 않는다`(예약 실행이 로그인 창을 앞으로 못 올림 · 화면 잠금) ③ `terminal_start_failed`(런처가 qwMain 을 못 띄움). `LOGINCOMPLETE=0` 은 그 자체로는 판정 근거가 아니다(기억 카드) — 무응답과 같이 볼 때만 쓴다.
- ★(10-16) **ensure_data_current 가 퀀티 패널 낡음을 '리프레시로 고칠 수 있는 항목'으로 센다**(`_actionable` · 128-146행) → 퀀티 패널이 낡은 동안 영업일마다 첫 아침 호출이 2시간 넘는 헛 전체 재실행을 하고(10-05 07:14→09:22 · 10-16 07:12→09:37 · 같은 날 재시도는 3b 가드가 막는다) 모닝 브리핑이 늦어진다.
- ★(10-16) `[8.1r]` — `rf_role_register_reps.R:31` 은 미등재 대표 0건이면 0열 표에 `by = code` 를 써서 멈춘다. 분류 · `strategy_roles.json` 갱신 · [8.2] 풀 조립은 정상이다. 경고 문구 '직전 레지스트리로 풀 조립'은 이때 사실이 아니다.
- universe_support 표식은 `apply_universe_mapping.R:87` `roll = Inf` 로 기한 없이 이어진다 — 낡아도 RAWDATA 에는 값이 있다. 낡음은 [0c] 감사기와 BOOK 사전점검만 잡는다. 위생 판정식(`corp_action_member`)은 표식 NA 를 통과로 본다.
- ★(11-12) **`dofork … exit code 0xC000026B` = 로그오프 · 재시작 중**(STATUS_DLL_INIT_FAILED_LOGOFF — 창 스테이션이 닫히는 중)이지 자원 고갈이 아니다. 같은 실행의 예약 작업 결과는 `0x40010004`. 이 로그에서 5회(06-22 · 07-08 · 08-28 · 09-02 · 11-12) — 모두 Done 없는 중도 사망과 짝이다. 원인은 System 로그 1074(누가 · 무엇으로 재시작했나)에서 찾는다.
- ★(11-12) **자가 복구 상한 150분 < 퀀티 4종 수급 약 250분** — 퀀티 단계가 든 자가 복구는 완주하지 못한다(`ensure_data_current.sh:280` · 근거 주석 266-269 는 4종 매일 수급 이전 표본). 게다가 [0b'] 재적재는 래퍼가 4종을 다 끝낸 뒤에만 돌아(`daily_refresh.sh:344-352`) 상한에 끊기면 **디스크에 저장된 OHLCVS 도 RAWDATA 에 안 실린다.**
- ★(11-12) **상한 종료가 COM Excel 을 고아로 남긴다** — `_kill_tree`(`ensure_data_current.sh:297-301`)는 MSYS · 윈도 트리만 끝내는데 COM Excel 의 부모는 svchost(DcomLaunch)다. 래퍼 `cleanup` 은 래퍼가 먼저 죽어 안 돈다. 11-12 실측: pid 23220(Consensus_update.xlsx 연 채 · 4.5 GB) 22시까지 생존.
- ★(11-12) **같은 영업일 재시도 규칙 ②는 벤치 지연(`QW_BEHIND`)만 본다**(`ensure_data_current.sh:225`) — 벤치는 최신 · RAWDATA 만 낡으면 매시 틱이 하루 종일 `재시도하지 않음` + 틀린 안내('리프레시로 고쳐지지 않는 항목'). 계획기는 rawdata → qw 로만 매핑해(`dr_heal_plan.py:40`) 밤 실행 상태가 있는 날 [0b](ingest)를 건너뛴다.
- ★(11-12) **밤 경로에는 퀀티 세션 확인이 없다** — 11-11 결정(QW-SELFHEAL-SESSION-ENSURE)은 자가 복구 경로만. 날짜 문맥이 멈춘 세션은 벤치 수급 스탬프만 새로 찍고 `CPD-1TD` 를 하루 늦게 푼다(11-11 00:12 `[20261109]`) → 4종 수급 `session kicked` → 0/4.
- ★(11-12) **드라이버 완료 판정('OK')은 B6 괄호만 본다**(`qw_refresh.ps1:506-516`) — 11-11 16:26 Universe_Support 저장본은 'OK' 인데 다섯 시트(K200 · KQ150 · 유동주식비율 · Sector_Lv1 · Lv2)에 날짜 행이 없었다 → [0b] `date_axis_missing` 거부(오염 없음 · 하루 지연).
- ★(11-12) 래퍼의 드라이버 출력은 임시 파일(`mktemp` → `/tmp/tmp.*`)에 모았다가 끝날 때만 로그로 옮긴다(`qw_updatefile_unattended.sh:108 · 139`) — 래퍼가 죽으면 책별 진행은 그 임시 파일에만 남는다.
- ★(11-12) 아침 체인이 부팅 직후(trigger=reboot) 돌면 그날 07:10 정규 실행은 '오늘 이미 완주 · 무경보'로 건너뛴다(morning_chain 몫) — 부팅 실행의 자가 복구가 실패해도 그날 아침 재시도는 없다.

## 기준선 — 정상일 때의 모습

- 실행 경로 · 로그: 예약 실행(.bat)만 `.cache/scheduler_logs/daily_refresh.log` 에 남는다. 아침 체인 · BOOK 러너 · 세션 실행은 `/tmp/qm_daily_refresh_YYYYMMDD.log`(Windows `%TEMP%` · 같은 날 여러 실행이 append)에만 남는다 — 이력을 볼 때는 둘 다 본다.
  - (11-12 실측) 자가 복구의 판정 줄(`[edc …]` · 상한 종료 · 사후 감사)은 `/tmp/qm_morning_briefing_YYYYMMDD.log` 에, 매시 틱은 `.cache/scheduler_logs/data_selfheal_tick.log` 에, 최신 판정은 `.cache/data_currency_stamp.json`(verdict) 에 있다. `/tmp` 의 지난날 qm_* 로그는 남아 있지 않을 수 있다(11-12 에 11-11 로그 없음).
- `Qvest_DailyRefresh` 로그온 모드 = '대화형만'. PC 가 꺼져 있던 날은 다음 로그온 뒤 아침 체인(ensure_data_current)이 보충한다.
- 소요(10-16 실측): 데이터 구간 [0]~[0c] 00:03→00:45(이 중 퀀티 무응답 대기 약 30분 — 정상 세션이면 1분 미만) · 잠금 해제 뒤 후처리([7] 텔레그램 · [7.9] 위생 · [8] 인덱스 · [8.1] 배선 · [8.1r] 역할(분류 약 128초) · [8.2] · [9] suite-totals)까지 Done 02:57. DART 분기 예산 3000콜 ≈ 25분(backlog 는 resume 으로 이어진다).
- (11-12 실측) **퀀티 4종 수급(새 거래일 밤)** = 약 250분: 11-07 254분(OHLCVS 44 · Universe_Support 70 · Investor_Act 35 · Consensus 105) · 11-09 251분(46 · 66 · 32 · 107) · 11-12 자가 복구 42 · 59 · 30 · (Consensus 9분째 종료). 조회 창 길이와 거의 무관하다 — Consensus 는 스탬프 기준 조회 2분 · 저장 · 닫기 약 103분(추정). 새 거래일이 없으면 드라이버는 3초 만에 끝난다(11-10 00:24:54→57).
- (11-12 실측) 정기 실행의 단계 시간(11-11): ingest 568초 · qw 399초(수급 0/4) · universe 52 · macro 292 · dart 1697 · krf 147 · fdb 23 · nonret 3. 정상 Done 시각 02:19~07:12 · 토요 전체 배터리 날 09:36(11-07).
- (11-12) 신선도 관문(측정 경로 · `round_core v3 freshness.R`)은 `freshness_audit.R --check --items rawdata,benchmark` 다. rawdata 달력 3일 ∧ 세션 지연 0 · benchmark 2일 ∧ 세션 0. 기준일 = 직전 평일(거래 달력 휴일 보정) → 금요일 아침이면 목요일 행이 있어야 한다.
- [1pre] 정상: 세션이 있으면 벤치 수급 전체가 1분 안에 끝난다(10-05: 실행 시작 00:03:01 → 정본 교체 00:03:50). 새 거래일이 있으면 rc=0 `updated`, 없으면 rc=2 + 응답 있음(10-06 13:44).
  - (11-12) 응답 있음(스탬프 갱신)이어도 `CPD-1TD` 괄호가 직전 거래일보다 하루 늦으면 날짜 문맥이 멈춘 세션이다(11-11 00:12). 정상 밤의 괄호 = 직전 거래일(11-07 00:19 · 11-10 00:17 · 11-12 00:31).
- [0b] `Update_File 변경 없음.` 은 그날 qw_refresh 가 돌지 않았다는 뜻이다(평상시 대부분).
- 아침 체인: 고칠 것이 없으면 ensure_data_current 가 `이미 최신` 으로 넘어가고 morning_run 은 07:12~07:19 에 끝난다(10-04 · 10-07). 리프레시를 다시 돌리면 09시대로 밀린다.
- [0c] 문턱(freshness_audit.R): rawdata · msm · ktri · regime 3d · benchmark 2d · fred 4d · consensus · investor_act 10d · universe_support 40d(월말 스냅샷) · fred_wide 14d · p3_forecast = 하류(판정 제외). (11-10~) rawdata · benchmark 는 세션 지연 0 도 요구.
- [8.1r] 정상 4줄: `분류 n · 역할 B+ 보유 m` / `풀 대표 고유 전략 k · 계보 l` / `레지스트리 기록: N → strategy_roles.json` / `대상 j · 등재 실행`(10-16: 분류 1302 · 레지스트리 1320 · 역할 대표 82 · 칸/기저 69 · 카탈로그 1002).
- 상시 WARN(이상 아님 · 오늘 원인과 무관): `[mapping] Layer 1 (KRX) Sector NA = 100%`(섹터는 Layer 2 가 채운다) · `[6b] fdb_daily stale`(자동 재빌드 OFF 설계 — factor_db) · `[regime-append/daily] 동결 구간 재서술 시도 — 발행본 보존`(08-14 부터 매일 · FRED 소급 개정 드리프트 · 감시 규칙 없음) · cache freshness audit WARN 10건(등록부 미등재 캐시 등).
- 신선도 이력(소비 패널 max(Date)): consensus · investor_act 08-28 → 09-18(09-19 수동) → 10-02(10-06 수동) · universe_support 08-28(08-29 수동 뒤 없음).
- (11-12) 이 PC 의 시작 메뉴 재시작(이벤트 1074 · StartMenuExperienceHost) 11-01 뒤 6회 — 11-01 22:59 · 11-04 00:01 · 11-05 07:51 · 11-06 22:50 · 11-08 13:41 · 11-12 00:10. Windows 사용 시간 06:00~24:00 → 00:00~06:00 이 자동 재시작 허용 시간대(재시작 대기 업데이트가 있을 때).
- (11-12) 한국어 시각 표기 '오전 12:15' = 00:15 — 프로세스 시작 시각을 읽을 때 12시로 오독하지 않는다(가동 시간 · LastBootUpTime 으로 교차 확인).

## 사건 기록 (최신이 위)

- **2026-11-12 — 정기 실행 Done 없음(재시작) → 자가 복구 상한 종료 → 종일 재시도 없음 · RAWDATA 11-10 정체** · 상태: 진단됨 · 수리 대기(O1 고아 Excel 정리 · R1~R8 · W1~W4 Q 수리 · R6 결정 · 재시작 시간대 도훈 부탁)
  - 증상: 00:03 정기 실행이 [0b] 수급 시트 판독 중 `dofork … 0xC000026B` × 3 으로 끝남(daily_refresh.log 331880~331885 · Done 없음 · 작업 결과 0x40010004). 감시기 새 이상 0.
    - 00:26 아침 자가 복구(trigger=reboot · 계획 FULL)는 벤치를 11-11 로 올렸다. OHLCVS(01:19:51) · Universe_Support(02:18:40) · Investor_Act(02:48:11)를 저장한 뒤 Consensus 도중 02:56:57 상한 9000s 로 종료(rc=124) → [0b'] 미실행.
    - 03:37~21:37 매시 틱 19회 '복구 생략'. 07:10 정규 아침 체인은 '오늘 이미 완주'로 건너뜀. 22:01 RAWDATA 11-10 · 벤치 11-11 · `--check` STALE(sess 1).
  - 근본 원인:
    - ① 00:10:13 시작 메뉴 '다시 시작'(사용자 세션 · KB5132061 적용 · 00:13:06 TrustedInstaller 재시작)
    - ② 자가 복구 상한 150분 < 4종 수급 약 250분 · [0b'] 가 4종 끝난 뒤에만
    - ③ 재시도 규칙 ②가 벤치만 본다 · 계획기 rawdata → qw
    - ④ 강제 종료가 COM Excel 23220 을 남김
    - ⑤ 감시 규칙에 Done 기대 · 소비면 판정 · 자가 복구 로그가 없음
  - 세션 진술 정정: 'claude · explorer 12:15 시작'은 '오전 12:15' = 00:15(재부팅 1회 · 00:13:31) · 'pre_boot 01:17'은 00:18:03 · 00:26:01 틱(reinforce_auto_20261112.log).
  - 영향: PIT 위반 없음(관문이 막음).
    - 오늘 측정 경로는 종일 data_stale 이지만 P1S01 tick_hold 라 실제 막힌 측정은 없음.
    - 내일 08:20~11:45 판 2 시드 측정은 오늘 밤 [0b'] 로 RAWDATA 11-12 가 들어와야 풀린다(정상 경로 예상 04:30~04:45). 실패 시 자동 복구로는 창 안에 안 풀릴 가능성이 높다 → Q 표적 복구(진단 §5).
    - 오늘 밤 [0b] 는 디스크의 OHLCVS 11-11 을 먼저 싣는다(6시트 지평선 11-11 · 11-11 행 값 2,563~2,572칸 확인).
  - 수리안: O1 고아 Excel 23220 저장 없이 종료(23:50 전) · O2 단말 읽기 확인 · R1 OHLCVS 먼저 · 즉시 적재(`daily_refresh.sh:331-352`) · R2 자가 복구는 OHLCVS 만 · R3 `dr_heal_plan.py:40` rawdata → ingest · R4 `ensure_data_current.sh:225 · 236-239` 재시도 조건 · 문구 · R5 상한 종료 뒤 `/automation` Excel 정리(326-330) · R6 밤 경로 세션 확인(`daily_refresh.sh:266-270` · 결정 필요) · R7 감시 W1~W4 · R8 드라이버 A열 날짜 확인.
  - 다른 구성요소: morning_chain(07:10 건너뜀 · MorningReboot 0x41306 상한) · scheduler(0x40010004) · book_tracking(11-11 평가 미확인) · factor_db(202611 진행 스냅샷).
  - 보고서: `20261112_2201_diagnosis.md`
- **2026-11-11 — 이상 `719b0d70546a`(Done ★실패 qw_updatefile_incomplete(done=0/4) · ingest_freshness) · `6d4d405b3d11`([0c] benchmark · rawdata lag 1d)** · 상태: 진단됨(known 권고)
  - 증상: 00:12:42 벤치 수급 스탬프만 갱신 · `CPD-1TD [20261109]`(직전 거래일 11-10 이어야 함) → rc=2. 00:18:27 · 00:18:47 수급 `session kicked` × 2 → done 0/4 → [0c] benchmark · rawdata STALE 1d.
  - 근본 원인: 밤 퀀티 세션 죽음 · 날짜 문맥 멈춤(환경 — 공유 계정) + 밤 경로에 세션 확인 없음(코드 공백). 낮 재로그인(09:25 · 13:42 · 15:54 중복 로그인 종료 → 15:55)으로 11-10 복구(RAWDATA 11-11 11:29 · 그 적재 경로는 미확인). 16:26 Universe_Support 저장본은 다섯 시트 빈 채 'OK' → 다음 [0b] 에서 거부.
  - 보고서: `20261112_2201_diagnosis.md` §2-D
- **2026-10-16 — ingest_freshness 실패 + [8.1r] R 오류** · 상태: 진단됨 · 수리 대기(도훈 퀀티 로그인 · R1~R3 Q 수리 · R4 도훈 결정)
  - 증상: 00:03 실행 `Done — ★실패 1스텝: ingest_freshness`(100207행) · `[0c] ★적재 미달: consensus 13d · investor_act 13d · universe_support 48d`(100154) · `[8.1r]` `object 'code' not found`(100196~100201). 07:12 아침 체인이 같은 3항목으로 전체 재실행 → 09:37 같은 결과.
  - 근본 원인: ① 퀀티 세션이 10-06 오후 이후 살아 있지 않다(login_required · login_failed(전면 전환 실패) · terminal_start_failed · 애드인 무응답 · 지금 qwMain 프로세스 없음) ② Update_File 수급 호출 계기 부재(구조) ③ 수동 갱신에서 Universe_Support 누락 ④ `rf_role_register_reps.R:31` 빈 대상 결함(10-09 · 10-10 · 10-16 재현 · 대상 ≥1 인 10-08 · 10-15 은 정상).
  - 부수: ensure_data_current 헛 재실행(모닝 브리핑 약 2.5시간 지연) · 퀀티 무응답 rc=2 오분류 · 30분 대기.
  - 영향: PIT 위반 없음. 측정 축 위생 · 지수 멤버십이 2026-09-30 신호일에 8월 말 표식(크기 미측정) · 202610 확정 빌드(10-30) 전 미복구 시 컨센서스 · 수급 팩터가 10-02 값으로 굳음 · BOOK_0001 11-01 리밸은 사전점검이 막는다(설계대로) · 모닝 브리핑 지연.
  - 수리안: R1 `rf_role_register_reps.R:29-33` 빈 대상 분기 · R2 `ensure_data_current.sh:128-146` 퀀티 적재 전용 항목 분리(xlsx -nt parquet 일 때만 대상) · R3 `qw_excel_refresh.ps1:203-223 · 271-274` 무응답 rc=3 + 300초 조기 중단 · R4(도훈 결정) 벤치 rc=0 인 밤에만 `qw_refresh.ps1 -SkipLogin -Only …` + [0b] 재적재.
    - (11-12 기록) R4 는 10-16 결정(QW-UPDATEFILE-UNATTENDED 안 A) → 10-17 4종 매일로 넓혀 시행됐다.
  - 다른 구성요소: scheduler(10-11~10-14 실행 0 · 대화형만) · factor_db(확정 뒤 추격 적재 재빌드 계기 의심) · morning_chain(p3_forecast 10-02).
  - 보고서: `20261016_2100_diagnosis.md`
- 2026-10-16 — dossier 초기화(구성요소 Superfan 신설).
