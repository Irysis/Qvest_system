# 스트레스 일보 — 별도 예약 작업(도훈 11-06 결정)

매일 밤 데이터 리프레시(`Qvest_DailyRefresh` 00:03)가 끝난 뒤 `run_daily_stress.sh` 를 한 번 돌려 `daily/<기준일>/` · `daily/latest/` 에
PDF · 엑셀 · 차트를 갱신한다. `daily_refresh.sh` 는 건드리지 않는다(원 세션 소유) — 데이터 준비 신호는 **리프레시 잠금
`/tmp/qm_daily_refresh.lock` 의 해제**다(실측 잠금 유지 41분 ~ 3시간 26분).

| 파일 | 역할 |
|---|---|
| `run_daily_stress_task.sh` | 작업 실행기 — 잠금이 풀릴 때까지 60초 간격 대기(상한 `STRESS_MAX_WAIT_MIN` 기본 240분 · 넘기면 rc 7 로 그날은 건너뜀) → `run_daily_stress.sh` → rc 전달. 로그 `daily/logs/task_*.log` |
| `Qvest_StressDaily.bat` | 작업 스케줄러가 부르는 진입점(Git Bash 로 위 실행기 호출 · 기존 `02_Infrastructure/ops/scheduler/*.bat` 과 같은 꼴 · 자기 위치 기준 상대 경로라 기계 무관) |
| `make_task_xml.ps1` | 작업 원본 XML `Qvest_StressDaily.xml` 을 **이 기계의 경로**로 써 내는 생성기(기계마다 사용자 폴더 · QM_ROOT 가 달라 XML 을 저장소에 고정하지 않는다) — 매일 **04:00** 트리거(`-Time` 로 변경) · 실행 상한 5시간 · 놓친 실행은 켜지는 대로(StartWhenAvailable) · `Enabled=true` |

## 등록 (정본 = `02_Infrastructure/ops/machine/README.md` §"새 예약 작업을 만들었을 때")

작업 등록은 **사람이 연 관리자 PowerShell** 에서 한다(Claude Code 도구 세션 안에서는 프로젝트 밖 쓰기가 가상화돼 작업 스케줄러가 못 본다).
`qvest_tasks.ps1 -Mode Apply` 가 XML 을 '메인 우선 게이트' 실행기로 감싸 등록한다(두 대가 켜져 있으면 메인만 돈다 · 주기는 트리거에서 `day` 로 추정).

```powershell
# 1) 이 기계 경로로 원본 XML 생성 → 이전용 폴더(작업 트리 밖 · OneDrive 동기화 · 기본 = %OneDrive%\Qvest_sync\stress_daily_task_20261106)
$ops = "$env:QM_ROOT\04_Research\01_reports\kr_market_stress_index_20261106\ops"
$out = "$env:OneDrive\Qvest_sync\stress_daily_task_20261106"
powershell -ExecutionPolicy Bypass -File "$ops\make_task_xml.ps1" -Out $out        # -Time 04:00 기본

# 2) 등록(관리자 PowerShell · 계획만 보려면 -WhatIf)
powershell -ExecutionPolicy Bypass -File "$env:QM_ROOT\02_Infrastructure\ops\machine\qvest_tasks.ps1" -Mode Apply -From $out -Name Qvest_StressDaily

# 3) 확인
powershell -ExecutionPolicy Bypass -File "$env:QM_ROOT\02_Infrastructure\ops\machine\qvest_tasks.ps1" -Mode Status
Get-ScheduledTask Qvest_StressDaily | Get-ScheduledTaskInfo
```

- **메인 PC**: 메인에서 1) 을 다시 실행해(경로가 다르다 — XML 은 기계마다 새로 만든다) 2) 를 한다(관리자). 리프레시 잠금은 기계마다 자기 `%TEMP%` 에 생기므로, 리프레시가 도는 기계(메인)에서 등록해야 "데이터 끝난 뒤" 가 성립한다.
- **노트북(이 기계)**: 11-01 이후 예약 작업을 전부 꺼 둔 상태(메인 전환). 여기선 등록하지 않거나, 등록해도 `Disable-ScheduledTask Qvest_StressDaily` 로 꺼 두는 것을 권한다 — 리프레시가 안 도는 기계에서는 잠금이 없어 바로 돌고, 입력은 OneDrive 로 넘어온 전날 캐시가 된다.
- 되돌리기: `Unregister-ScheduledTask Qvest_StressDaily -Confirm:$false` (감싼 실행기 `%LOCALAPPDATA%\Qvest\jobs\Qvest_StressDaily.cmd` 와 원본 사본 `jobs\orig\Qvest_StressDaily.xml` 은 `qvest_tasks.ps1 -Mode Restore` / 수동 삭제).
- 손으로 한 번 돌려 보기(등록 없이): `bash ops/run_daily_stress_task.sh` — 잠금이 없으면 곧바로 체인을 돈다(약 2분). 잠금 대기 경로 시험: `QVEST_REFRESH_LOCK=<있는 파일> STRESS_MAX_WAIT_MIN=0 bash ops/run_daily_stress_task.sh` → rc 7.

## 하지 않는 것
`daily_refresh.sh` 수정 · 리프레시 직접 기동 · 텔레그램 발송(발송은 `tg_agent_brief()` 경유만 — 도훈 결정 전까지 끔) · 운영 폴더(`02_Infrastructure/`) 이전(도훈 결정).
