# 예약 작업 일괄 정리 절차 (2026-11-10 · 도훈 실행)

근거 = `../lanes/audit_H2_crosscut.md` §8 + 도훈 11-10 저녁 결정 카드. 예약 작업의 등록 · 변경은 Claude 세션 안에서 할 수 없다(세션의 HKCU · AppData 쓰기는 가상화된다) —
**도훈이 일반 PowerShell(관리자 불필요 · Claude 밖)** 에서 실행한다. 메인 PC 기준이다.

## 현재 상태와 할 일

| 작업 | 상태 | 할 일 | 근거 |
|---|---|---|---|
| DailyRefresh · MorningBrief · MorningReboot · StrandedRepairs · SuperfanWatch · StressDaily · FundV2Update · InsiderBackfill · ClaudeCliUpdate · MachineHeartbeat | 켜짐 | 유지 | — |
| WeeklyCleaner | 켜짐 · 이 PC 에서 아직 실행 기록 없음 | 유지 — 11-14(토) 09:00 첫 실행 확인 | — |
| AxiomReview · MonthlyDistill | 켜짐 | **끄기** | Axiom 처분(AXIOM-ENGINE-DISPOSITION-20261110) |
| AxiomActivate · WeightCatalogGrow | 꺼짐 | **등록 해제** | 퇴역 |
| InfraCurrency(신규) | 미등록 · XML 있음 | **등록**(매일 05:40 인프라 판 점검) | — |
| StandingBoard(신규) | 미등록 · bat · XML 만듦(11-10) | **등록**(매시 37분 · 상설 판 한 틱. 강화 사슬 무인 틱 `chain_tick.sh` 은 **아직 없다** — 생기면 같은 작업이 이어서 부른다) | CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110 "만들고 바로 켠다" |
| noLayer4_Monthly_PaperTracking | 작업 없음 · XML 있음 | **등록**(BOOK_0001 월간 트래킹) | BOOK-MONTHLY-TRACKING-TASK-20261110 |
| ReinforceAutoLoop | 꺼짐 | **결정 대기** — 충실구현 레인 재가동 구성 | REPLICATION-LANE-RESTART-SLOTS-20261110(열림) |
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
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From "$T\after" -Name Qvest_AxiomReview,Qvest_MonthlyDistill

# 4) 새 작업 등록 — 인프라 판 점검 · 상설 판 + 사슬 틱 · BOOK 월간 트래킹
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From $X -Name Qvest_InfraCurrency,Qvest_StandingBoard,noLayer4_Monthly_PaperTracking

# 5) 저장소 밖 고아 실행기 삭제(있는 것만)
Remove-Item "$env:LOCALAPPDATA\Qvest\jobs\Qvest_ZZ_wraptest.cmd","$env:LOCALAPPDATA\Qvest\jobs\off\DART_Insider_Backfill.cmd","$env:LOCALAPPDATA\Qvest\jobs\off\Qvest_AxiomActivate.cmd","$env:LOCALAPPDATA\Qvest\jobs\off\Qvest_WeightCatalogGrow.cmd" -ErrorAction SilentlyContinue

# 6) 확인
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Status
```

메모
- **StandingBoard**: `standing_board_run.sh --send` 를 매시 37분에 돈다. 등록된 상설 판이 없으면 아무 일도 하지 않고 끝난다(지금 상태 — 첫 판 P1S01 은 다음 세션에서 등록). 측정은 리프레시 잠금이 풀려 있을 때만 하고, 앞 틱이 아직 돌고 있으면 건너뛴다. 통과 엔진은 푸시 · 미달은 무음 일 요약. 강화 사슬 무인 틱(`chain_tick.sh`)은 그 파일이 생기면 같은 작업이 이어서 부른다.
- **noLayer4_Monthly_PaperTracking**: 매월 3일 09:00(작업 정의의 달력 트리거) · `02_Infrastructure/monitoring/run_nolayer4_monthly.sh`(11-06 리밸에 쓴 실행기 — 다른 작업 간섭 제거판). 실주문은 없다(모니터링 전용).

## 2단계 — 레인 재가동(결정 뒤)

★계정 주간 사용량(전 모델)이 11-10 저녁 87%다(리셋 11-13 19:00 KST). 충실구현 레인은 논문마다 구현 · 감사 에이전트를 부르므로 리셋 전에 켜면
남은 한도를 먼저 쓴다 — 한도가 차면 아침 체인의 LLM 레인(논문 라우터 등)도 같이 멈추고 그 실패가 경보로 나간다. 켜는 시점은 리셋 뒤를 권한다.

```powershell
# 슬롯 수는 06_Registry/reinforce_auto_config.json::replication_lane.slots — 결정대로 Q 가 먼저 고친다
Enable-ScheduledTask -TaskName Qvest_ReinforceAutoLoop
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Export -Out "$T\lane"
powershell -NoProfile -ExecutionPolicy Bypass -File $Q -Mode Apply -From "$T\lane" -Name Qvest_ReinforceAutoLoop
```

## 주의

- 실행 전후로 `-Mode Status` 출력을 Q 에게 붙여 주면 감시기(구성요소 Superfan)의 '꺼진 작업' 판정과 대조한다.
- 메인 PC 를 쓰는 동안 노트북의 예약 작업은 꺼 둔다(두 대 동시 실행 금지 — 11-08 사고).
