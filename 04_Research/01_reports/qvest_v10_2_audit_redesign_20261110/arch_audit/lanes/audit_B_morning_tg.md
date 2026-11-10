# 감사 레인 B — 모닝 브리핑 · 텔레그램 (2026-11-10)

## 1. 배선 지도 (코드 · 로그로 확인)

- 예약 작업 `Qvest_MorningBrief`(07:10 매일 · ExecutionTimeLimit **PT3H12M** · IgnoreNew · StartWhenAvailable) → `pythonw hidden_launch.pyw`(창 없음 · `%LOCALAPPDATA%\Qvest\logs\Qvest_MorningBrief.log`) → `jobs\Qvest_MorningBrief.cmd`(machine gate) → `ops\scheduler\Qvest_MorningBrief.bat`(QVEST_UNATTENDED=1) → `ops/morning_run.sh cron` → 로그 `.cache/scheduler_logs/morning_run.log`.
- morning_run: 하루 1회 락(`/tmp/qm_morning_run_<YMD>.lock` + `.done` · 생존 PID 가드 · 경보 마커면 재시도 ≤3) → [0] paper_recharge(20분 상한) → [0.5] paper_router → [0.51] program_paper_sync.R → [0.52] paper_atlas → [0.58] factor_evidence → [0.7] scheduler_task_health → [0.75] cleaner_distill → 평일 [1] morning_briefing.sh · [2] mrs_daily_briefing.sh / 주말 [1w] ensure_data_current → 집계 경보 1통 · alerts_digest.
- morning_briefing.sh: [0/5] ensure_data_current(**stale 이면 daily_refresh.sh 전체를 동기 실행**) → [2] arrow_extend · ktri_rebuild → [3] fred_regime → [4.5] self_heal → [5] freshness_audit(무음) → [5a2] value_quality_spread → [5b] axiom 스텁 → [3b] BOOK_0001 MTM(발송) → [6] P3 추론 · brief · 9분면 · p3_brief_send(발송).
- mrs_daily_briefing.sh: regime_data_gate → freshness_audit 재감사(발송 가능) → mrs_regime_send(레짐 1통 + 사진 3) → ff5_brief_send(스타일 1통 + 차트).
- 발송기: `telegram_notify.R` — `tg_send`(구조화 반환 · 실패 원장 `qepm/observability/telegram_send_failures.jsonl`) · `tg_agent_brief`(섹션 검증 · 3900자 맞춤 · 중복 잠금 `.cache/tg_locks` TTL 30분 · 성공 본문 보관 `C:\tmp\qvest_tg_body_ARCHIVE`) · `tg_send_photo` · `tg_regime_briefing`. 1계층 = `program_report.R::prep_send`(force · relaxed · mute=!push · 길이 패딩).
- 무인 경보 발신처(실측): ① `superfan_watch.py` → `superfan_notify.R`(1시간 · `[Superfan·<구성요소>] 실패 이상 N건`) ② `_sched_failure_classify.sh::sched_alert_emit`(StrandedRepairs 12:00 의 task_health · `[무인] 스케줄러 경보 — task_health`) ③ paper_recharge 일일 요약 ④ claude_cli_update ⑤ BOOK MTM ⑥ FF5 · 레짐 · P3 브리프.

## 2. 핵심 과제 1 — "텔레그램에 오류창" 후보와 증거 순위

발송 이력 = `C:\tmp\qvest_tg_body_ARCHIVE`(tg_agent_brief 성공본만 · 11-07 이후 18통 · 이 PC 이전 전 이력 없음) + 실패 원장 + `_tg_alert_send.log` + `.cache/superfan_watch.json`.
tg_send 직송(레짐 · P3 · freshness) 은 보관되지 않는다 → 그 몫은 로그로만 확인.

| 순위 | 후보 | 14일 건수 | 근본 원인 | 조치 |
|---|---|---|---|---|
| 1 | **실패 알림 메시지**(Superfan · 스케줄러 경보) | 보관 18통 중 **9통**(11-07~11-10). superfan 원장 notified 10-27 이후 ≈14건 · task_health 경보 6건(10-28 · 11-01 · 11-06 · 11-07 · 11-09 · 11-10) | (a) 로그 원문 줄을 그대로 본문에 넣음(`=== Daily Refresh v2 Done — ★실패 2스텝: benchmark_currency(gate_rc=1,updater_rc=1) ingest_freshness @ …===`) (b) **같은 원인 2~3통**: 오늘 MorningBrief 종료 하나에 Superfan·아침 체인 11:17 + task_health 12:01 (c) **오탐**: `[Superfan·충실구현 레인] 파일 없음: reinforce_auto_{YYYYMMDD}.log — 35회`(레인 ReinforceAutoLoop 는 Disabled 인데 감시 규칙이 살아 있음 · 11-07 · 11-10 두 번) (d) task_health 본문 "task_health 가 … 사유로 **정지했습니다**" — 정지한 것은 다른 작업 · 고정 문구 "작업 스크립트가 실행 자체를 못 한 경우" 도 틀림 | 소유 밖(superfan_watch.py · superfan_components.json · _sched_failure_classify.sh) → 패치 제안 §5 |
| 2 | 화면의 **Excel 오류 창**(WER) | Application Error EXCEL.EXE **58건**(11-08~11-10 · 00시 14 · 07시 9 = 밤 리프레시 · 아침 자가 복구 시각) | 퀀티 Excel 수급 자동화 중 Excel 충돌 → '작동 중지' 창 | 레인 A(데이터 리프레시) 소관 |
| 3 | **Telegram Desktop 자체 충돌** | 1건(11-10 06:36 · Telegram.exe 7.2.5 · 0xc000041d) | 클라이언트 측 · 봇 발송과 인과 증거 없음 | 미확정 |
| 4 | 퀀티 단말 '예기치 않은 오류 … 종료합니다' 창 | 11-08 밤 사례(qw_dead_terminal.ps1 주석) | 단말 사망 창 | qw_dead_terminal.ps1 가 처리(레인 A) |
| 5 | API 오류로 깨진 메시지(400 · 4096 · 사진 누락 대체문) | **실장애 0건**(원장 554줄 중 541 = 검사 탐침 · 실장애 13건 마지막 09-05) | — | 사진 실패가 원장에 안 남던 결함은 수리(§4) |
| 6 | 예약 작업 콘솔 창 | 0 — 전 작업 hidden_launch.pyw(CREATE_NO_WINDOW) | — | — |

판정: **1순위 = 채널에 쌓이는 실패 알림(원문 로그 덤프 · 중복 · 오탐)** 이 가장 유력(채널 절반). 다만 '오류창'이 화면 대화상자(2 · 3)를 뜻할 수도 있어 **미확정 — 도훈 확인 필요**(채널 캡처 1장이면 확정).

추가 발견 — 검사가 **실제 API** 를 친다: `08_Tests/data/test_telegram_send_contract.R` T1 이 `api.telegram.org` 로 미종결 Markdown 을 보내 400 을 유도(채널 미도달이나 운영 원장에 쓰고 · 08-16 초판은 실제로 발송됨). 배터리(daily_refresh [8.x] suite_totals --collect)가 하루 3~5회 돌려 원장 탐침 541줄.

## 3. 핵심 과제 2 — 오늘 267014

타임라인(로그): 03:34 밤 DailyRefresh 가 벤치 단계 실패(rc 1) → 07:10:15 morning_run → 07:13 morning_briefing → 07:14 ensure_data_current: benchmark stale → **daily_refresh.sh 전체 동기 실행**(07:14→12:15 · 5시간) — 그 안에서 퀀티 Update_File 수급 2934초 · done 0/4, DART 08:25~08:55, 팩터 DB, [7.9]~[8.2] 위생 · 인덱스 · 배선 지도(09:00→09:15), 역할 재분류(→09:19), **suite_totals --collect = 전체 검사 배터리 09:19→12:15(2시간 56분)**.
→ 07:10:01 + 3:12 = **10:22 에 작업 시간 상한으로 Task Scheduler 가 pythonw 를 종료 = 267014(SCHED_S_TASK_TERMINATED)**. 자식 bash 트리는 살아 12:50 에 완주(고아) — gate `done` 단계 미기록 · hidden_launch rc 줄 없음. 브리핑 · BOOK · FF5 · 레짐은 07:30 대신 **12:17~12:50** 에 나갔다.
같은 배터리 실행이 09:44 · 10:16 · 12:12 의 원장 탐침 줄과 일치(라이브 API 탐침이 아침 체인 안에서 돌았다).

최근 14일(10-27~11-10) cron/reboot 실행:

| 날짜 | 시작 | 끝 | 소요 | 결과 |
|---|---|---|---|---|
| 10-28 | 19:11 · 19:15 | — | — | 중단(.done 없음 · PC 이전기) |
| 10-29~10-31 · 11-02~11-06 | — | — | — | **미실행 8일**(PC 꺼짐/이전 · 11-06 은 Superfan '완료 표식 없음' 13회) |
| 11-01(일) | 11:53 | 12:44 | 51분 | 완주 · ensure_data_current rc 3 |
| 11-07(토) | 07:15 | 07:34 | 20분 | 완주 |
| 11-08(일) | 07:10 | 07:23 | 14분 | 완주 |
| 11-09(월) | 07:10 | 07:16 | 6분 | 완주 |
| 11-10(화) | 07:10 | 12:50 | 5시간 40분 | 작업 종료 267014 · 고아 완주 |

시나리오 실측(`test_scn_morning_chain.sh` · 임시 루트): 단계 실패는 격리된다(다음 단계 계속 · 오케스트레이터가 stage_exit 마커 1개 · 같은 날 재실행 시 재시도 1/3 → 상한 3) · 멈춘 단계는 20분 상한(paper_recharge 만) · 무경보 완주 뒤 재실행 skip · 생존 락이면 단계 0개.
**상한이 없는 단계**: [1] morning_briefing.sh(→ ensure_data_current → daily_refresh 전체)와 [2] — 오늘의 5시간이 여기다.
누가 알아채나: ① Superfan 감시(11:00 이후 '완료 표식 없음' — 11:17 1통) ② StrandedRepairs task_health(12:01 1통 · 다음 날 같은 사유면 또 1통) ③ 부팅 줄. 브리핑이 아예 안 나간 날(PC 꺼짐 8일)은 ①이 PC 켜진 뒤에만.

이중 실행: 생존 PID 가드 정상(시험 S6). 재시도는 경보 마커 사유마다 sched_retry_cap 이 상한을 덮는다(환경변수 MORNING_MAX_RETRY 는 경보 사유가 있으면 무시 — 시험 S3 에서 실측).

브리핑 내용의 v10.2 반영: 아침 체인에 1계층 상태(상설 판 · 강화 사슬 · 기저 풀 · 결과 원장 · 판 표식) 발송 **없음** — 발송 5종(BOOK MTM · P3 · 레짐 · FF5 · 논문 수집)은 v10 이전 계보. 1계층 소식은 라운드마다 prep_send 뿐.

## 4. 수리한 결함 (소유 경로)

1. `ops/morning_run.sh:15-44 · 175 · 187-301` — 시험 격리 덮어쓰기 4개(QVEST_MORNING_BASE · _LOG · _LOCK_DIR · _STAGE_LOG_DIR). 원인: `test_morning_run_live_pid_guard.sh` 가 운영 루트 스크립트를 운영 로그 · 운영 락으로 trigger=test 실행(11-06~11-10 운영 로그 15줄 오염 · superfan 아침 체인 감시 입력 오염 · 가드 회귀 시 운영 단계 실기동 위험). 운영 동작 불변(기본값 그대로 · CRLF 보존 · bash -n 통과). 검증: 시험 2개 + 기존 morning_run 시험 4종(45/45) 통과.
2. `08_Tests/ops/test_morning_run_live_pid_guard.sh` — 임시 루트로 재작성 + 운영 로그 무접촉 단정(4/4).
3. `telegram/telegram_notify.R::tg_send_photo` — 반환을 tg_send 와 같은 구조(list ok/kind/status/error)로 · 파일 없음/400/예외를 실패 원장에 기록. 원인: 사진 거부 · 누락이 어떤 표면에도 안 남음(반환을 읽는 호출자 0곳 — 계약 변경 안전). 돌연변이(원장 기록 제거 사본)로 검사 발화 실증(T9).
4. `tg_agent_brief` 차트 루프 — 없는 차트 · 실패 차트를 결과(`charts_missing` · `charts_failed`)와 로그 1줄로 노출(구판 조용히 건너뜀).
5. `tg_regime_briefing` — 발송 결과를 읽어 `sent_ok` · `charts_sent` · `send_error` 반환(구판은 반환을 버리고 파일 존재로 '보냄' 집계).
6. `morning_steps/mrs_regime_send.R` — 구판은 결과와 무관하게 "briefing sent OK" · stale 경보 실패를 tryCatch(error=) 로만 봄(tg_send 는 예외를 안 낸다) → 반환 판독.
7. `morning_steps/p3_brief_send.R` — 반환 판독 + 3900자 초과 시 글자 중간 절삭("…(truncated)") 대신 줄 단위로 덜어냄(SKILL §0.3 · Markdown 엔티티 반쪽 → 400 통째 유실 방지).
8. `telegram_notify.R` 보관 경로 덮어쓰기 `QVEST_TG_ARCHIVE_DIR`(시험이 유일한 발송 이력에 가짜 본문을 섞지 않게 · 운영 기본 불변).

## 5. 못 고친 결함 — 패치 제안(소유 밖)

- P1 `02_Infrastructure/data/daily_refresh.sh:1124` — 검사 배터리(`suite_totals_watch.sh --collect`)를 리프레시 안에서 돌리지 않는다. 최소안: `[ "${QVEST_REFRESH_CONTEXT:-}" = "morning_selfheal" ] || bash … --collect` + `ops/ensure_data_current.sh:221` 의 호출에 `QVEST_REFRESH_CONTEXT=morning_selfheal` 를 붙인다. 근거: 오늘 2시간 56분 = 아침 체인 5시간 40분의 52% · 267014 의 직접 원인 · 배터리가 라이브 API 탐침 · 운영 로그 오염을 아침에 반복. 근본안: 배터리를 별도 예약 작업(야간 · 리프레시 뒤)으로.
- P2 `ops/ensure_data_current.sh:221` — 아침 자가 복구는 전체 리프레시 대신 실패 단계(벤치 · Update_File)만 또는 [7.9]~[8.x] 정리 단계를 건너뛰게(같은 env). 오늘 [7.9]~[8.2] 위생 · 인덱스 · 배선 지도 · 역할 재분류 = 21분.
- P3 `superfan_watch.py` / `06_Registry/superfan_components.json`(총괄 통합 중) — (a) replication_lane 의 `reinforce_auto_{YYYYMMDD}.log` 신선도 규칙을 ReinforceAutoLoop 상태(Disabled)에 묶거나 끈다(오탐 35회 · 2통) (b) 같은 날 같은 원인(예약 작업 실패)을 task_health 경보가 이미 보냈으면 scheduler · morning_chain 구성요소는 보내지 않는다(SKILL §0.4 '같은 원인 반복 발송 금지') (c) 본문 `x$text` 원문 로그 줄 대신 '무엇이 · 언제 · 몇 번' 요약 문장 + 원문은 로그 경로 포인터.
- P4 `ops/_sched_failure_classify.sh:432` — summary 를 "무인 파이프라인 ${comp} 가 … **정지했습니다**" 에서 comp=task_health 일 때 "예약 작업 실패 감지 — <작업>(<사유>)" 로. `scheduler_task_health.sh` 의 detail 고정 꼬리 "(작업 스크립트가 실행 자체를 못 한 경우 …)" 는 사유가 terminated/exit_N 일 때 틀린 서술 → 사유별 문구.
- P5 예약 작업 정의(`ops/machine/qvest_tasks.ps1` 생성) — MorningBrief PT3H12M 는 체인 실측 상한(오늘 5h40m)보다 짧고, 종료 시 자식 트리가 고아로 남아 gate done 이 안 찍힌다. P1 적용 뒤에도 남으면 상한 상향 또는 hidden_launch 가 Job Object 로 트리째 종료.
- P6 `08_Tests/data/test_telegram_send_contract.R` T1/T2 — 실 API 축을 기본 SKIP(QVEST_TG_LIVE_PROBE=1 일 때만) · 원장 경로를 임시 루트로. 같은 계약은 `test_scn_tg_emitter.R` T2 · T5 · T9 가 모의로 덮는다.
- P7 `morning_steps/freshness_audit.R` — 레인 A 가 거래 세션 지연 축을 작업 중(미커밋 diff 확인 · 손대지 않음). 함께: 발송 문구의 "brief 07:30" 고정 시각(오늘 12:50 발송) · tg_send 반환 미판독(:120 근처 `tryCatch(tg_send(msg), error=)`) 두 줄도 같은 판에서.
- P8 BOOK MTM · FF5 브리프 기준일 — 오늘 RAWDATA 11-06(퀀티 수급 0/4)인데 아침 감사는 FRESH(달력 lag 3 ≤ 3) → 두 브리프가 '11-06 기준' 으로 나감. P7 세션 축이 들어가면 해소 — 단 ensure_data_current 의 재실행 트리거도 바뀌므로 P1/P2 와 함께 적용할 것(아니면 5시간 자가 복구가 더 자주 돈다).

## 6. 업데이트 누락 감지 표

| 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 |
|---|---|---|---|---|---|
| benchmark.parquet | daily_refresh [1pre] | 매일 00:03 | freshness_audit(달력 2일) + ensure_data_current 퀀티 축(KRX 직전 거래일) | P3 · 전 측정 | 아침 체인이 리프레시 전체 재실행(오늘 5시간) |
| RAWDATA.parquet | daily_refresh [0b'] 퀀티 Update_File | 매일 | freshness_audit 달력 3일(**1세션 누락 통과** · 레인 A 수리 중) · cache_freshness_audit 는 STALE_CRITICAL | BOOK MTM · FF5 · 측정 | 브리프가 낡은 기준일로 발송(표기는 됨) |
| P3_daily.parquet | morning_briefing [6a] | 평일 | freshness_audit(downstream · 판정 제외) + p3_brief_send 게이트(brief 날짜 < 벤치 최신 → 보류 + 경보) | P3 브리프 | 보류 + 1통 |
| regime/msm/ktri | morning_briefing [2][3] | 평일 | freshness_audit 3일 + mrs_regime_send 게이트 | 레짐 브리프 | 보류 + 1통 |
| morning_run 완주 | morning_run.sh | 매일 | Superfan(11:00 이후 done 줄) · task_health(작업 rc) | 사람 | 1~2통(중복) |
| 텔레그램 발송 성공 | 발송기 | 매 발송 | 실패 원장(text · **사진은 11-10 부터**) · superfan telegram_emitter | Superfan | 원장 1줄 · 감시 알림 |
| 아침 브리핑 미도착 | — | — | **없음** — PC 꺼진 날은 켜진 뒤 Superfan 만 | — | 침묵(8일 사례) |

## 7. 속도

임계 경로 실측(11-10): 07:10 → 12:50 = 340분. 상위 3: ① suite_totals 검사 배터리 176분(09:19→12:15) ② 퀀티 Update_File 수급 ~49분(정체 감시 2934초 · 전진 0) + Global_Macro 수급 ③ DART 증분 29분(08:25→08:55). 정상일(11-09) = 6분.
단축안(판정 불변): P1(배터리 분리) −176분 · P2(자가 복구 = 실패 단계만) −50분 이상 · 자가 복구가 필요한 날만 해당.

## 8. P/L 우상향 관점 최대 제약 3

1. **신호 대 잡음** — 채널 절반이 실패 · 오탐 알림(18통 중 9) · 같은 원인 2~3통 · 원문 로그 덤프. 결과 보고(prep_send)가 이 소음 속에 묻힌다(학습된 무시 — morning_run.sh:318 주석이 이미 경고한 기전).
2. **아침 자가 복구가 측정 창을 먹는다** — 데이터가 하루 늦은 날 아침 체인이 5시간 전체 리프레시 + 3시간 검사 배터리를 돌려 같은 시각 측정 작업과 충돌(11-10 DNN OOM · 지문 불일치 · 첫 칸 43분 폐기 — 메모리 11-10 카드).
3. **낡은 데이터 통과** — 1세션 누락이 아침 감사를 통과해 BOOK · 스타일 브리프가 11-06 기준으로 나갔다(레인 A 수리 중). 아침 체인에는 1계층 연구 진척(상설 판 · 사슬 · 결과 원장)을 알리는 면이 없다 — 매일 아침 보는 것이 v10 이전 브리프 5종이다.

## 9. 도훈 결정

- D1 '오류창'이 무엇인지(채널 메시지 / 화면 Excel 창 / 텔레그램 앱 충돌) 1장 확인.
- D2 아침 자가 복구 범위: (a) 현행 전체 리프레시 (b) **실패 단계만 + 정리 · 검사 배터리 생략(권고)** (c) 아침엔 재감사만 하고 리프레시는 밤으로.
- D3 무인 실패 알림 채널 정책: (a) 현행 (b) **하루 1통 집계 + 원인별 1회 · 오탐 규칙 정리(권고)** (c) 실패 알림 무음.
- D4 아침 브리프 5종(BOOK MTM · P3 · 레짐 · FF5 · 논문 수집 0편 일일 요약)의 존치/무음 — SKILL §0.4 '평상 무음' 과 충돌(논문 0편 · 같은 깨진 링크 2건을 매일 푸시).

## 10. 바꾼 파일 · 시험

바꾼 파일: `02_Infrastructure/ops/morning_run.sh` · `02_Infrastructure/telegram/telegram_notify.R` · `02_Infrastructure/ops/morning_steps/mrs_regime_send.R` · `02_Infrastructure/ops/morning_steps/p3_brief_send.R` · `08_Tests/ops/test_morning_run_live_pid_guard.sh`.
새 시험: `08_Tests/scenarios/test_scn_morning_chain.sh`(16/16 · 약 70~90초 — 60초 목표 초과 · Windows bash 기동 비용) · `08_Tests/scenarios/test_scn_tg_emitter.R`(24/24 · 6초).
돌린 기존 시험: test_morning_run_live_pid_guard 4/4 · test_morning_run_rewire 13/13 · test_orchestrator_stage_gate 11/11 · test_morning_run_retry_marker 9/9 · test_stage_timeout_and_recharge_stall 12/12 · test_program_report 34/34 · test_rp_telegram_relaxed 7/7. 운영 원장 554줄 · 보관 18개 시험 전후 불변.
확인 못 한 것: 텔레그램 채널 실제 화면 · tg_send 직송분(레짐 · P3)의 14일 발송 수(보관 없음) · Task Scheduler 운영 이벤트 로그(조회 결과 0 — 로그 비활성 추정) · Telegram.exe 충돌 원인 · 11-01 이전 보관(이 PC 이전 뒤 C:\tmp 신규).

## 11. 2단계(경보 소음 수리 · 아침 1계층 상태) — 11-10 오후

- 공유 저장소 `02_Infrastructure/ops/alert_dedup.py`(신규 · `.cache/alert_dedup.json` · 원인 키 task:<작업> / task_health:digest / sf:<구성요소>:<키> · 하루 1통 · 억제 = 건수만 · 해소 = task_health resolve-healthy(rc 0 · 꺼짐) · Superfan 정상 복귀 · ack fixed · 발신 실패 = release).
- `_sched_failure_classify.sh::sched_alert_emit` — 인자 4 원인 키 · 인자 5 요약 · 값은 환경변수 전달(R 소스 끼우기 제거) · '정지했습니다' 기본 문구 제거 · 원인 키가 있으면 저장소가 스로틀(마커는 해소를 모름).
- `scheduler_task_health.sh` 경보 발신부만 — 사유별 문구(_th_phrase) · 작업별 원인 키 · resolve-healthy. 판정 논리 무접촉(41/41 · 13/13 재확인).
- `superfan_watch.py` — sched_task Disabled 면 신선도 · 완료 표식 규칙 생략(미수록 · 판독 실패 = 켜짐) · 원인 키 claim · notify=false · 요약/위치 payload · 시험 격리(감시 상태 경로 재정의 시 저장소도 그 옆).
- `06_Registry/superfan_components.json` — sched_task 5개(daily_refresh · factor_db = DailyRefresh · morning_chain · book_tracking = MorningBrief · replication_lane = ReinforceAutoLoop) · scheduler cause_key = task_health:digest.
- `superfan_notify.R` — 본문 = 요약 한 문장 · 처음 · 횟수 · 위치(원문 줄 없음).
- `test_telegram_send_contract.R` — 모의 발송기 · 임시 원장 기본 · QVEST_TG_LIVE_PROBE=1 일 때만 실 API. 운영 원장 탐침 541줄은 그대로(삭제 안 함).
- 아침 1계층 상태: `morning_steps/l1_status_send.R`(신규 · 무음 · 7칸 · 칸별 판독 불가) + `morning_briefing.sh` [5c].
- 시험: `08_Tests/scenarios/test_scn_tg_alert_noise.py` 30/30(돌연변이 5) · test_superfan_watch.R 63/63 · test_scn_tg_emitter 24/24 · test_telegram_send_contract 15/15 · task_health verdict 41/41 · never_run 13/13.
- 재계산(보관 11-07~11-10 · 실패형 9통): 꺼진 레인 2통(11-07 · 11-10) + 같은 원인 중복 1통(11-10 12:01) = −3 → 6통. 10-27~11-06 은 보관 없음(이 PC 이전) — superfan_watch.json 기준 11-06 scheduler 요약 1통 · 10-28 · 11-01 의 task_health/아침 체인 겹침은 작업명 기록이 없어 미확정.
- 남은 것: `08_Tests/regime/test_briefing_partial.R` 이 127.0.0.1 탐침으로 운영 원장에 쓴다(소유 밖 · .tg_lock_root 를 임시로 돌리면 됨) · 다른 sched_alert_emit 호출자(paper_router · mode_queue · factor_deep_recheck)는 원인 키 없이 구판 스로틀.
