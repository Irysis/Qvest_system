# 스트레스 일보 — 별도 예약 작업 `Qvest_StressDaily`(도훈 11-06 결정 · 같은 날 "노트북 활성화 · 메인 PC 에서도")

매일 **04:00** 에 깨어나 데이터가 준비되면 `run_daily_stress.sh` 를 한 번 돌려 `daily/<기준일>/` · `daily/latest/` 에 PDF · 엑셀 · 차트 · 방법론을
갱신한다(OneDrive 동기화 폴더라 두 기계 어디서나 `daily/latest/kr_stress_daily_latest.pdf` 로 본다). `daily_refresh.sh` 는 건드리지 않는다(원 세션 소유).

**데이터 준비 = 둘 다 만족**: (a) 밤 리프레시 잠금 `/tmp/qm_daily_refresh.lock` 이 없다 (b) 벤치(퀀티) 최신일 ≥ KRX 직전 거래일
(`02_Infrastructure/data/krx_holidays.py currency` — 부팅 · ensure_data_current 와 같은 판정). (b) 가 없으면 04:00 에 리프레시가 아직 시작 전일 때
묵은 데이터로 일보가 나간다. 60초 간격 · 상한 480분(12:00) — 넘기면 rc 7 로 그날은 건너뛴다(묵은 데이터로 일보를 내지 않는다).

| 파일 | 역할 |
|---|---|
| `install_task.ps1` | **한 줄 설치**(노트북 · 메인 공통) — 아래 둘을 차례로 부르고 등록 상태 · 다음 실행 시각을 보여 준다. `-WhatIf` · `-RunNow` · `-Time` |
| `make_task_xml.ps1` | 이 기계 경로로 원본 XML 생성(`%OneDrive%\Qvest_sync\stress_daily_task_<컴퓨터 이름>` · 기계마다 사용자 폴더 · QM_ROOT 가 달라 저장소에 고정하지 않는다) — 매일 04:00 · 실행 상한 9시간 · 놓친 실행은 켜지는 대로 |
| `Qvest_StressDaily.bat` | 작업 진입점(Git Bash → 아래 실행기 · ASCII 전용 · 자기 위치 기준 경로) · 로그 `.cache/scheduler_logs/stress_daily.log` |
| `run_daily_stress_task.sh` | 실행기 — 데이터 준비 대기 → 체인(수급 → 지수 → 차트 → 일보 PDF · 엑셀 → 메일) → rc 전달 · 로그 `daily/logs/task_*.log` |
| `send_daily_mail.py` · `mail_config.json` | 메일 단계 — 아래 §메일 |

등록은 `02_Infrastructure/ops/machine/qvest_tasks.ps1 -Mode Apply` 로 다른 Qvest 예약 작업과 똑같이 **'메인 우선 게이트' 실행기**에 감싼다
(`%LOCALAPPDATA%\Qvest\jobs\Qvest_StressDaily.cmd` · 창 없는 실행 · 주기 `day`). 두 대가 다 켜져 있으면 메인만 돌고, 메인이 꺼져 있으면 노트북이 돈다.

## 설치

```powershell
powershell -ExecutionPolicy Bypass -File "$env:QM_ROOT\04_Research\01_reports\kr_market_stress_index_20261106\ops\install_task.ps1"
```

- **노트북(RAZER_BLADE_16)**: 11-06 설치 완료 — 상태 Ready · 다음 실행 11-07 04:00 · 작업 스케줄러로 한 번 실제 실행해 확인(DESIGN §7).
- **메인 PC(MAINCOMPUTER)**: 메인에서 위 한 줄을 실행(보통 PowerShell 로 충분 · 실패하면 관리자). OneDrive 로 이 폴더가 넘어오면 바로 된다. 사전 조건 = 메인의 `QM_ROOT` · `.venv_qvest_ml` · R 4.5.2 · Git Bash · Edge(다른 Qvest 작업과 같음). '오늘의 해설' 단계는 메인의 `claude` CLI 와 `CLAUDE_CODE_OAUTH_TOKEN` 이 있어야 하며, 없으면 해설 없이 정상 발행된다.
- ★Claude Code 도구 세션 안에서 설치하면 프로젝트 밖 쓰기가 가상화돼 실행기 파일이 작업 스케줄러에 안 보일 수 있다 — 설치기가 `%LOCALAPPDATA%\Qvest\jobs\Qvest_StressDaily.cmd` 존재를 확인해 경고한다(11-06 노트북 설치는 샌드박스 밖에서 실행해 실물 확인).

## 메일(도훈 11-06 — 일보 PDF + 엑셀 대시보드만 · 해설 없는 확정본 v1 · 방법론 제외)

체인 ⑤ `ops/send_daily_mail.py` 가 `daily/latest` 의 두 파일을 `ops/mail_config.json` 수신자(`dhkim@hmsec.com`)에게 **기준일당 1통** 보낸다
(보낸 뒤 `daily/<기준일>/mail_sent.json` · 재발송은 `--force`). 첨부 합계 약 10 MB.
발신은 Gmail SMTP(앱 비밀번호) — 자격은 저장소에 두지 않고 **사용자 환경 변수**로만 읽는다. 자격이 없으면 메일만 건너뛰고 일보는 정상.

설정(도훈이 직접 · 한 번 · 두 기계 각각): Google 계정 → 보안 → 2단계 인증 → 앱 비밀번호 생성(16자리) → PowerShell 에서

```powershell
[Environment]::SetEnvironmentVariable('QVEST_MAIL_USER', '<보낼 Gmail 주소>', 'User')
[Environment]::SetEnvironmentVariable('QVEST_MAIL_APP_PASSWORD', '<앱 비밀번호 16자리>', 'User')
# 오늘 것 한 번 보내 보기
& "$env:QM_ROOT\.venv_qvest_ml\Scripts\python.exe" "$env:QM_ROOT\04_Research\01_reports\kr_market_stress_index_20261106\ops\send_daily_mail.py"
```

미리보기(보내지 않음): `send_daily_mail.py --dry-run` · 끄기: `mail_config.json` 의 `enabled` 를 false 또는 `KRSI_NO_MAIL=1`.

## 확인 · 되돌리기

```powershell
Get-ScheduledTask Qvest_StressDaily | Get-ScheduledTaskInfo          # 마지막 실행 · 결과(0 정상 · 7 데이터 미준비로 건너뜀)
Get-Content "$env:LOCALAPPDATA\Qvest\logs\Qvest_StressDaily.log" -Tail 20
Unregister-ScheduledTask Qvest_StressDaily -Confirm:$false            # 되돌리기
```

- 손으로 한 번(등록 없이): `bash ops/run_daily_stress_task.sh`. 대기 경로 시험: `QVEST_REFRESH_LOCK=<있는 파일> STRESS_MAX_WAIT_MIN=0 …` → rc 7 · `QVEST_KRX_TODAY=<미래 날짜> STRESS_MAX_WAIT_MIN=0 …` → rc 7.

## 하지 않는 것
`daily_refresh.sh` 수정 · 리프레시 직접 기동 · 텔레그램 발송(발송은 `tg_agent_brief()` 경유만 — 도훈 결정 전까지 끔) · 운영 폴더(`02_Infrastructure/`) 이전(도훈 결정).
