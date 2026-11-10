# 예약 작업 일괄 정리 절차 (2026-11-10 · 도훈 실행)

근거 = `../lanes/audit_H2_crosscut.md` §8 + 도훈 11-10 저녁 결정 카드. 예약 작업의 등록 · 변경은 Claude 세션 안에서 할 수 없다(세션의 HKCU · AppData 쓰기는 가상화된다) —
**도훈이 일반 PowerShell(관리자 불필요 · Claude 밖)** 에서 실행한다. 메인 PC 기준이다.

## ★11-11 08:02 적용 결과 — 남은 것은 아래 세 줄

도훈이 1단계를 붙여넣었다(11-11 08:02). Q 가 읽기 전용으로 확인한 결과:

- **된 것**: AxiomReview · MonthlyDistill 꺼짐 · AxiomActivate · WeightCatalogGrow 등록 해제 · **ReinforceAutoLoop 켜짐**(실행기 08:02 재작성 · 시작 관문 때문에 11-13 19:10 전에는 일하지 않는다) · noLayer4_Monthly_PaperTracking 은 이미 등록돼 있었다(다음 실행 12-03 09:00).
- **안 된 것**: `Qvest_InfraCurrency` · `Qvest_StandingBoard` 미등록 · 꺼진 Axiom 두 작업의 실행기가 `jobs\off` 로 안 옮겨짐.
- **원인 = 이 절차서의 결함(Q 의 실수)**: `powershell -File … -Name a,b,c` 는 쉼표 목록을 **문자열 하나**로 넘긴다 → 그런 이름의 작업이 없어 아무것도 하지 않고 조용히 끝났다(이름 하나짜리였던 레인 켜기만 적용됐다). 아래처럼 이름마다 한 번씩 부르면 된다(`-WhatIf` 로 두 작업 모두 APPLY 계획이 나오는 것을 확인했다). 1단계 블록도 같은 식으로 고쳤다.

```powershell
$R = 'G:\OneDrive\Quant_Module_Moltbot'
$Q = "$R\02_Infrastructure\ops\machine\qvest_tasks.ps1"
$X = "$R\02_Infrastructure\ops\scheduler\_task_xml_backup"
$T = "$env:USERPROFILE\Desktop\qvest_tasks_20261110"
foreach ($n in 'Qvest_InfraCurrency','Qvest_StandingBoard') { powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From $X -Name $n }
foreach ($n in 'Qvest_AxiomReview','Qvest_MonthlyDistill') { powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From "$T\after" -Name $n }
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Status
```

## 현재 상태와 할 일

| 작업 | 상태 | 할 일 | 근거 |
|---|---|---|---|
| DailyRefresh · MorningBrief · MorningReboot · StrandedRepairs · SuperfanWatch · StressDaily · FundV2Update · InsiderBackfill · ClaudeCliUpdate · MachineHeartbeat | 켜짐 | 유지 | — |
| WeeklyCleaner | 켜짐 · 이 PC 에서 아직 실행 기록 없음 | 유지 — 11-14(토) 09:00 첫 실행 확인 | — |
| AxiomReview · MonthlyDistill | 켜짐 | **끄기** | Axiom 처분(AXIOM-ENGINE-DISPOSITION-20261110) |
| AxiomActivate · WeightCatalogGrow | 꺼짐 | **등록 해제** | 퇴역 |
| InfraCurrency(신규) | 미등록 · XML 있음 | **등록**(매일 05:40 인프라 판 점검) | — |
| StandingBoard(신규) | 미등록 · bat · XML 만듦(11-10) | **등록**(매시 37분 · 상설 판 한 틱 뒤 강화 사슬 무인 틱 `chain_tick.sh` 을 이어서 부른다 — 11-10 밤 구축 · 열린 사슬이 없으면 무음) | CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110 "만들고 바로 켠다" |
| noLayer4_Monthly_PaperTracking | 작업 없음 · XML 있음 | **등록**(BOOK_0001 월간 트래킹) | BOOK-MONTHLY-TRACKING-TASK-20261110 |
| ReinforceAutoLoop | 꺼짐 | **켜기(1단계 6)** — 시작 관문 `not_before = 2026-11-13T19:10:00+09:00` 전에는 레인이 아무 일도 하지 않는다 · 1슬롯(`{"cpu":0,"gpu":1}`) | REPLICATION-LANE-RESTART-SLOTS-20261110 "충실구현레인 리셋 뒤 1슬롯 켜" |
| AuditWatch | 꺼짐 | 보류(켜지 않으면 주간 전수 점검의 C11 항목이 늘 미측정) | — |

## 1단계 — 지금 실행

```powershell
$R = 'G:\OneDrive\Quant_Module_Moltbot'
$Q = "$R\02_Infrastructure\ops\machine\qvest_tasks.ps1"
$X = "$R\02_Infrastructure\ops\scheduler\_task_xml_backup"
$T = "$env:USERPROFILE\Desktop\qvest_tasks_20261110"

# 0) 현재 원본 백업
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Export -Out $T

# 1) 쓰지 않는 작업 끄기
Disable-ScheduledTask -TaskName Qvest_AxiomReview
Disable-ScheduledTask -TaskName Qvest_MonthlyDistill

# 2) 퇴역 작업 등록 해제
Unregister-ScheduledTask -TaskName Qvest_AxiomActivate -Confirm:$false
Unregister-ScheduledTask -TaskName Qvest_WeightCatalogGrow -Confirm:$false

# 3) 끈 상태를 다시 내보내고 실행기를 jobs\off 로 옮긴다
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Export -Out "$T\after"
foreach ($n in 'Qvest_AxiomReview','Qvest_MonthlyDistill') { powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From "$T\after" -Name $n }

# 4) 새 작업 등록 — 인프라 판 점검 · 상설 판 + 사슬 틱 · BOOK 월간 트래킹
foreach ($n in 'Qvest_InfraCurrency','Qvest_StandingBoard') { powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From $X -Name $n }

# 5) 저장소 밖 고아 실행기 삭제(있는 것만)
Remove-Item "$env:LOCALAPPDATA\Qvest\jobs\Qvest_ZZ_wraptest.cmd","$env:LOCALAPPDATA\Qvest\jobs\off\DART_Insider_Backfill.cmd","$env:LOCALAPPDATA\Qvest\jobs\off\Qvest_AxiomActivate.cmd","$env:LOCALAPPDATA\Qvest\jobs\off\Qvest_WeightCatalogGrow.cmd" -ErrorAction SilentlyContinue

# 6) 충실구현 레인 켜기 — 지금 켜도 리셋(11-13 19:00 KST) 전에는 일하지 않는다(시작 관문 · 2단계 설명)
Enable-ScheduledTask -TaskName Qvest_ReinforceAutoLoop
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Export -Out "$T\lane"
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From "$T\lane" -Name Qvest_ReinforceAutoLoop

# 7) 확인
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Status
```

★레인 설정(시작 관문 · 1슬롯)은 11-10 22:35 에 Q 가 넣었다 — `config show` = `"not_before": "2026-11-13T19:10:00+09:00"` · `"slots": {"cpu": 0, "gpu": 1}`. 그래서 6) 을 지금 실행해도 리셋 전에는 레인이 일하지 않는다.

메모
- **StandingBoard**: `standing_board_run.sh --send` 를 매시 37분에 돈다. 등록된 상설 판이 없으면 아무 일도 하지 않고 끝난다(지금 상태 — 첫 판 P1S01 은 다음 세션에서 등록). 측정은 리프레시 잠금이 풀려 있을 때만 하고, 앞 틱이 아직 돌고 있으면 건너뛴다. 통과 엔진은 푸시 · 미달은 무음 일 요약. 이어서 강화 사슬 무인 틱(`chain_tick.sh` · 11-10 밤 구축)을 부른다 — 등록된 열린 사슬의 기준 칸 측정 · 걸음 측정 · 판정 · 다음 걸음 설계만 잇고(등록 · 닫기는 세션), 열린 사슬이 없으면 무음이다. 끄는 법 = `06_Registry/chain_tick.json` 의 `"enabled": false`. ⚠ 틱이 측정으로 오래 돌면 그동안 같은 작업의 매시 상설 판 틱이 건너뛰어진다(작업 설정 IgnoreNew) — 사슬이 열리면 틱을 별도 예약 작업으로 가르는 것을 권한다(도훈 결정).
- **noLayer4_Monthly_PaperTracking**: 매월 3일 09:00(작업 정의의 달력 트리거) · `02_Infrastructure/monitoring/run_nolayer4_monthly.sh`(11-06 리밸에 쓴 실행기 — 다른 작업 간섭 제거판). 실주문은 없다(모니터링 전용).

## 2단계 — 레인 재가동 (도훈 11-10 결정 REPLICATION-LANE-RESTART-SLOTS-20261110 "충실구현레인 리셋 뒤 1슬롯 켜")

★계정 주간 사용량(전 모델)이 11-10 저녁 87%다(리셋 11-13 19:00 KST). 충실구현 레인은 논문마다 구현 · 감사 에이전트를 부르므로 리셋 전에 일하면
남은 한도를 먼저 쓴다. 그래서 레인에 **시작 관문**을 넣었다 — 작업은 1단계 6)에서 **지금** 켜고, 레인이 리셋 뒤부터 일한다.

- **시작 관문** `replication_lane.not_before = "2026-11-13T19:10:00+09:00"`(리셋 19:00 + 10분 여유). 그 시각 전 틱은 `rf_replication_auto.sh` 가 스위치 검사 바로 뒤에서
  아무 일도 하지 않고 0 으로 끝난다 — claim · 요청 발행 · 슬롯 디스패치 · 에이전트(LLM) · 측정 전부 없음(디스패처 · 슬롯 작업자 · 구판 단일 슬롯 모두).
  저널(`.cache/reinforce_auto_log.jsonl`)에 `halt_not_before state=wait` 한 줄 · 일별 틱 로그(`.cache/scheduler_logs/reinforce_auto_<날짜>.log`)에 '시작 관문 대기' 한 줄.
  틱 래퍼가 매 틱 그 일별 로그를 쓰므로 Superfan `lane_alive`(신선도 8시간)는 산 레인으로 읽고, 대기 줄은 `lane_errors` 어느 패턴에도 걸리지 않는다(시험 F1~F3).
  값이 해석 불가 · 시간대 없음이면 **닫힘**(일하지 않음 · `halt_not_before state=invalid`) — 키 없음 · 빈 값 = 관문 없음.
- **1슬롯** = `slots {"cpu":0,"gpu":1}` — GPU 슬롯 하나가 모든 논문을 받는다(CPU 슬롯이 없으면 무엇이든). 동시 실행 1 · GPU 인계함(`_gpu_inbox`)의 torch 논문을 큐보다 먼저 · GPU 임대 존중.
  `{"cpu":1,"gpu":0}` 은 쓰지 않는다 — 인계함을 영영 비우지 않고(GPU 슬롯에서만 소비) torch 논문이 임대를 보지 않은 채 GPU 를 쓴다.
  ⚠ GPU 임대(P2R05 등)가 살아 있는 동안은 1슬롯 전체가 새 착수를 보류한다(CPU 논문 포함 · 임대 상한 12시간이 끝).
  옛 `cpu1` · `cpu2` 슬롯의 멈춘 요청(1109.3488 · 2106.06164 — 11-07 중단)은 11-10 22:35 에 정식 인계 명령(`rf_replication_slots.py handoff`)으로 GPU 인계함에 넘겼다(논문 잠금도 함께 이전).
  **관문 뒤 처리 순서** = `gpu1` 의 THGNN(2601.04602 · 11-06 중단분 재개) → 인계함 6편(넘어온 순서: 1309.7119 · 2411.13555 · 2412.12516 · 2507.01964 · 1109.3488 · 2106.06164) → 큐(다음 논문 순서 규칙).
- **설정(11-10 22:35 적용 완료 — 아래는 기록 · Git Bash · 저장소 루트)**:
  ```bash
  "$QVEST_PY" 02_Infrastructure/ops/rf_replication_slots.py --root G:/OneDrive/Quant_Module_Moltbot config not-before 2026-11-13T19:10:00+09:00
  "$QVEST_PY" 02_Infrastructure/ops/rf_replication_slots.py --root G:/OneDrive/Quant_Module_Moltbot config enable --cpu 0 --gpu 1
  "$QVEST_PY" 02_Infrastructure/ops/rf_replication_slots.py --root G:/OneDrive/Quant_Module_Moltbot config show
  ```
- **되돌리기**: 레인 정지 = `Disable-ScheduledTask -TaskName Qvest_ReinforceAutoLoop` 뒤 1단계 6)의 Export → Apply 두 줄(`-Out "$T\lane_off"` · `-From "$T\lane_off"`) ·
  관문 해제(즉시 일하게) = `config not-before clear` · 관문 미루기 = `config not-before <새 시각>` · 3슬롯 복귀 = `config enable --cpu 2 --gpu 1` · 구판 단일 슬롯 = `config disable`.
- **확인(11-13 19:10 뒤)**: 저널에 `slots_tick` · `slot_launched slot=gpu1` 이 보이면 재가동 · 그 전에는 `halt_not_before` 만 보인다.

## 주의

- 실행 전후로 `-Mode Status` 출력을 Q 에게 붙여 주면 감시기(구성요소 Superfan)의 '꺼진 작업' 판정과 대조한다.
- 메인 PC 를 쓰는 동안 노트북의 예약 작업은 꺼 둔다(두 대 동시 실행 금지 — 11-08 사고).
