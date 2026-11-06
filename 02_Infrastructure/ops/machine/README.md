# 두 대 운용 — 메인 PC 우선 (2026-11-01 도훈 지시)

> "메인 PC 나 노트북 둘 중 하나를 켜더라도 Qvest 문제없이 작업 가능하게 · 둘 다 켜져 있을 땐 메인 PC 우선"

작업 트리 하나(`.git` 포함)를 OneDrive 로 두 기계가 공유한다. 두 기계 모두 **같은 경로**
`C:\Users\99922\OneDrive\Quant_Module_Moltbot` 로 연다 — 메인 PC 는 `C:\Users\99922` → `C:\Users\User` 연결(junction ·
2_main.ps1). 코드 · venv(`pyvenv.cfg home = C:\Users\99922\AppData\Local\Programs\Python\Python312`) · 예약 작업이 박아 둔
경로가 두 기계에서 그대로 맞는다. 예약 작업은 두 기계에 같은 세트를 등록하고 게이트로 거른다.

| 파일 | 하는 일 |
|---|---|
| `machines.conf` | 기계 → 역할(`main` · `secondary` · 없으면 secondary) · 작업별 주기 덮어쓰기(`period <작업> <주기>`) |
| `qvest_machine.sh` | `role · status · heartbeat · gate · done · settled` — 규칙 전문 = 머리말 |
| `qvest_tasks.ps1` | 예약 작업 내보내기(Export) · 게이트 실행기로 감싸 등록(Apply) · 되돌림(Restore) · 생존 신호(Heartbeat) · Status |
| `install_hook_guard.sh` | SessionEnd 자동 커밋 · 푸시 훅에 '동기화 안정' 가드 블록을 끼운다(멱등 · `--uninstall`) |
| `qvest_sync.py` | 대조표(`write` · `compare`) · OneDrive 충돌 사본 정리(`conflicts`) · 항상 이 장치에 유지(`pin` — 메인은 `--no-all --files <대조표>` = 데이터 · 실행 필수 · 대조표 파일만, 결과물 폴더의 나머지는 열 때 내려받기 · OneDrive 를 G: 로 옮겼으면 제외 · 핵심 목록 없이 = 'all' = Qvest 폴더 전체(도훈 11-04)) |
| `r_packages.R` | R 패키지 판 맞추기 — `inventory`(설치 목록) · `bundle`(받는 기계에 없거나 판이 다른 것만 묶을 목록) · `restore`(묶음 → R_LIBS_USER, 없으면 CRAN) |
| `1_laptop.ps1` · `2_main.ps1` | 노트북 → 메인 PC 이전(1회분 · 다시 돌려도 같은 결과). **보통 PowerShell 에서 시작** — 다른 기계가 올린 파일(클라우드 전용일 수 있음)을 먼저 보통 권한으로 내려받고(항상 유지) 관리자 확인(UAC)을 스스로 띄운다(관리자 프로세스는 클라우드 전용 파일을 그 자리에서 못 내려받을 수 있다). 각 머리말 = 단계 목록. 공통 도우미 = `qvest_setup_common.ps1` |

이전 때 주고받는 곳 = `OneDrive\Qvest_sync\`(작업 트리 밖): `from_laptop\`(노트북 내보내기 — `DONE.txt` 목록대로 다
내려와야 메인이 쓴다 · 비밀(`secrets\` · `home\` · `claude\`)은 메인이 가져간 뒤 지운다) · `claude_memory\`(두 기계가 연결해
쓰는 Claude 메모리) · `conflicts\`(충돌 정리에서 진 판) · `logs\`(두 스크립트 기록) · `main_compare_*.txt`(대조 결과).

**OneDrive 를 다른 드라이브로(메인 · 11-03 도훈 "OneDrive 폴더 째로 G 드라이브로")**: 메인은 OneDrive 를 `G:\OneDrive` 로 옮긴다 —
폴더 백업(바탕 화면 · 문서)을 'OneDrive 에만'으로 끔 → 이 PC 연결 해제 → 다시 로그인하며 위치 변경 G:\ → 폴더 백업 다시 켬.
[Microsoft 안내](https://support.microsoft.com/en-us/office/change-the-location-of-your-onedrive-folder-f386fb81-1461-40a7-be2c-712676b2c4ae)는
'연결 해제 → 폴더 옮기기 → 다시 연결'이지만 여기서는 옮기지 않고 G: 에서 새로 받는다(옛 폴더는 대부분 클라우드 전용 — 논리 234 GB 중
로컬 38 GB · 확인용으로 남김). 공통 경로는 그대로다: 2_main [3] 이 `C:\Users\99922` → `C:\Users\User` 에 더해
`C:\Users\User\OneDrive` → `G:\OneDrive` 를 잇는다(옛 폴더는 `OneDrive.old_<시각>` 으로 이름만 바꿈 — OneDrive 계정 · 환경 변수
OneDrive* · 바탕 화면 · 문서가 아직 옛 폴더를 가리키면 멈춤, 사진 · 스크린샷 같은 다른 셸 폴더는 연결로 새 자리에 이어지므로 알림만).
[7] 은 세 경로 키(실제 `G--OneDrive-…` · 사용자 폴더 `C--Users-User-OneDrive-…` · 공통 `C--Users-99922-OneDrive-…`)를 공유
메모리에 잇는다. OneDrive 위치는 레지스트리(사용자 환경 변수)에서 읽는다 — 옮기기 전에 연 창의 `$env:OneDrive` 는 옛 값이다.
옮긴 뒤 [1] 은 Qvest 폴더 전체를 항상 유지로 표시한다(도훈 11-04 — 단계표 4번 오른쪽 클릭과 같은 결과 · 빈 공간이 모자라 'all' 이
아닌 계획이 골리면 경고). OneDrive 위치 자체는 바꾸지 않는다 — 개인 계정은 명령 · 정책으로 바꾸는 공식 경로가 없어 앱에서 사람이 한다.
[10] 은 대조할 파일(대조표의 D 아닌 줄)이 다 내려올 때까지 기다린 뒤 대조한다(`Wait-ManifestLocal` · 도훈 11-04 — UAC 한 번으로
끝까지). 관리자 프로세스라 읽어서 받지 않고 OneDrive 가 고정분을 받는 것을 지켜본다. 기다리는 동안 절전에 들지 않는다(전원 설정은 그대로).
그만 기다리는 때 = 첫 파일이 오기 전 3시간 · 온 뒤 1시간 줄지 않음 · 모두 24시간 — 그 뒤엔 그대로 대조한다. `-SkipPin` 이면 기다리지 않는다.

## 규칙

- **메인 우선.** 메인의 `Qvest_MachineHeartbeat`(5분 + 로그온)가 `.cache/machine/heartbeat_main.txt` 를 쓴다. 노트북
  게이트는 SETTLE(5분) 기다린 뒤 그 주기 몫에 다른 기계 표식이 있으면 건너뛰고, 메인이 살아 있고(15분 안) 그 작업을
  맡고 있으면 GRACE(5분) 더 기다려 다시 본다 — 그래도 없으면(메인이 놓침) 대신 돈다. 메인이 꺼져 있으면 바로 돈다.
  메인은 깨어난 직후 WAKE(3분) 기다려 노트북 표식이 내려올 시간을 준다. 수 분 간격 작업(period none)은 기다리지 않는다.
- **주기 표식**: `.cache/machine/runs/<작업>__<키>__<기계>.txt`(day · week · month · hour). 게이트 로그 =
  `.cache/machine/gate_<기계>.log`(기계별 파일 — 같은 파일을 두 기계가 쓰면 그 자체가 충돌 사본).
- **자동 커밋 · 푸시 가드**: `.git` 클라우드 전용 파일 · `.git` 충돌 사본 · 추적 파일 대량 삭제(>200) · 보류 표식
  `.cache/machine/hold_<기계>` 중 하나라도 있으면 SessionEnd 훅이 건너뛴다(훅 로그 `SKIP_UNSETTLED`).
- **Claude 는 한 기계에서만.** `qepm/observability/events.jsonl`(추적 파일)에 모든 도구 호출이 한 줄씩 붙는다 — 두
  기계가 같은 동기화 틈에 붙이면 OneDrive 충돌 사본이 생긴다. 생기면 `qvest_sync.py conflicts`(아래)가 줄 합집합으로 합친다.
- **예약 작업 계정**: 감싸 등록하면 로그온 방식이 InteractiveToken(로그인해 있을 때만)이 된다 — 암호를 저장하지 않고,
  OneDrive 파일은 사용자 세션이 있어야 내려온다.

## 점검

```bash
bash 02_Infrastructure/ops/machine/qvest_machine.sh status        # 역할 · 생존 신호 · 최근 표식 · settled
```
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 02_Infrastructure\ops\machine\qvest_tasks.ps1 -Mode Status
python 02_Infrastructure\ops\machine\qvest_sync.py conflicts . --device MAINCOMPUTER --device <노트북 이름>   # 계획만
```
창 없는 작업의 출력 = `%LOCALAPPDATA%\Qvest\logs\<작업>.log`.

## 새 예약 작업을 만들었을 때

원래대로 등록한 기계에서 `qvest_tasks.ps1 -Mode Export -Out <폴더>` → `-Mode Apply -From <폴더>`, 다른 기계에서도 같은
폴더로 `-Mode Apply`(관리자). 감싼 작업을 Export 하면 원본(`jobs\orig`)이 나간다.

## 검사 (2026-11-01 메인 PC 실측)

- `bash 08_Tests/ops/test_qvest_machine.sh` — 게이트 · 생존 신호 · settled 34 축 `{"pass":34,"fail":0}`.
- 훅 회귀(가드 끼운 채): `08_Tests/hooks/test_auto_commit_valve.sh` 19 · `…_session_scope.sh` 51(`QVEST_PY` 필요) ·
  `…_worktree_target.sh` 28 — 전부 통과. 가드는 시험 저장소에서 `qvest_machine.sh` 를 못 찾으면 비켜 서고, 찾으면
  그 저장소 기준으로 판정한다. ★보류 표식이 있는 기계에서 valve 시험을 돌리면 그 표식 때문에 실패한다(메인 이전 중).
- `qvest_sync.py`: 시험 저장소로 compare(일치 · 낡은 사본 · 대조표 뒤 더 새 사본 · 빠짐 · 지운 파일 · .git 남는 ref ·
  허용 목록 · *.lock) 14 · conflicts(줄 합집합 · 노트북 판 이김 · 원본 이름 판 이김 · 같은 내용 · .git · 원본 없음 ·
  이름 중간의 기계명 · --stash 필수 · 멱등) 19.
- `qvest_sync.py pin`(11-03 메인): 합성 트리 `--apply` 14 축(폴더 고정 · 대조표 파일 단위 고정 · 제외 3종 · 결과물 안 남김 ·
  루트 파일 · 다시 돌려도 같음) + 돌연변이 3(`--files` 빠짐 → BAD 2 · `--no-all` 빠짐 → BAD 2 · 여유 초과 → 종료 3).
  메인 C: 계획만: 'essential' 내려받기 16.0 GB(폴더 12.1 + 대조표 파일 28,595개 4.17 GB) — 옛 'all' 이면 60.2 GB.
  파일 단위 고정(SetFileAttributesW)은 attrib 와 같은 속성 · OneDrive 는 고정 뒤 약 10~15분에 내려받기 시작(실물 1개).
- 2_main OneDrive 이동 지원(11-03 메인 · 모래상자 = 세션 임시 폴더): `Get-OneDriveRoot` · `Get-PathPlan` · `Get-FolderUsers` ·
  `Set-OneDriveJunction` 20 축 — 옛 창 `$env:OneDrive` 무시 · 경로 계획 7(G: · C: · onedrive 키 없음 · 사용자 폴더 밖 · 깊이 다름 ·
  대소문자 · 끝 `\` · 노트북 OneDrive 가 사용자 폴더 밖) · 실물 사용 표시 3(계정 · 바탕 화면 · 문서 · 환경 변수 = 멈춤, 사진 ·
  스크린샷 등 4 = 알림 · 무관 폴더 0 · 이름 앞부분 0) · 연결 9(점검만 · 이름 바꿔 보관 · 다시 · 다른 대상 · 안에 연 파일 → 멈춤 ·
  닫은 뒤 · 아직 가리킴 → 멈춤 · 점검만도 멈춤 · 알림만 → 연결) + 돌연변이 5(OdMoved 고정 → 3 · 환경 변수만 → 1 · 가드 없음 → 2 ·
  경계 없음 → 1 · 전부 알림 → 1). 2_main 본체는 파서 통과까지(관리자 · 실제 이동이 필요).
- 2_main [1] G: 분기(11-04 메인 · 모래상자 = 세션 임시 폴더): 파서 3 · [1] 블록을 흉내 함수로 돌린 분기 5(G: = `pin` 제외 없음 +
  루트 attrib · 'all' 아닌 계획 → 경고 · rc 3 → 경고 · C: = 그대로 Invoke-Pin -Files -NoAll · -SkipPin = 아무것도 안 함) +
  돌연변이 3(G: 분기 없음 → 3 · 'all' 확인 없음 → 1 · 루트 attrib 없음 → 1) · 합성 트리 실물 `pin --apply`(제외 없음) = PIN all ·
  10개 전부 고정 · 여유 초과 → rc 3 — 10/10.
- `Wait-ManifestLocal` · 2_main [10] 기다림(11-04 메인 · 모래상자): 파서 3 · 실물 3(모두 로컬 → 바로 0 · 클라우드 전용 2개가 안 옴 →
  시작 한도에서 2 · 하나가 내려온 뒤 멈춤 → 1(보통 권한 프로세스가 읽어 실제로 내려받게 함)) · [10] 블록 흉내 3(대조 전에 기다림 ·
  남으면 경고 뒤 대조 · -SkipPin 이면 안 기다림) + 돌연변이 4(클라우드 판정 뒤집기 → 2 · 바로 끝내기 없음 → 1 · 멈춤 감지 없음 → 1 ·
  -SkipPin 분기 없음 → 1) — 10/10.
- 감싼 작업 실물(작업 스케줄러 · 18/18): .bat(종료 3) · bash(종료 5, 작업 폴더 · `%` · `>>`) → LastTaskResult 3 · 5,
  다른 기계 표식 → 건너뜀 rc 0, 표식 기록, `-Visible`, Restore, Heartbeat.
- 이전 스크립트 도우미(`qvest_setup_common.ps1` · 51): 외부 명령 종료 코드 · 내보내기 목록(빠짐 · 내용 · 가져간 묶음 건너뜀) ·
  메모리 합치기(MEMORY.md 줄 합집합 · 같은 이름 다른 내용 곁에 · 멱등) · 메모리 연결(멱등) · bash 시험 판정(죽은 시험 =
  실패) · R 묶음(translations 제외 · 같은 판 제외 — 메인 자기 목록 대조 0개 · 전체 268개 0.63 GB) · Claude settings.json
  병합(없는 키만) · 환경 변수 JSON 1 · 2개 왕복 · 훅 가드 블록 10줄 · 클라우드 전용 판별(실제 OneDrive 자리표시 1 · 로컬 0) ·
  내려받기 기다림(Offline 속성으로 흉내 → 시간 초과 시 남은 수 1 · 속성 지우면 0 · 없는 경로 건너뜀) · 충돌 정리 종료 코드 3
  가르기(GIT 줄 = 사람 판단 · ERROR 만 = 내려받기 뒤 다시). 두 스크립트 본체는 PowerShell 파서 통과까지 — 관리자 실행은
  두 기계에서 사람이 한다(관리자 프로세스의 OneDrive 그 자리 내려받기 여부는 여기서 실측 불가 — 그래서 고정 + 기다림).
- ★Claude Code 도구 세션 안에서는 프로젝트 밖 쓰기(예 `%LOCALAPPDATA%`)가 가상화돼 작업 스케줄러가 못 본다 — 실물 시험은
  `-Base` 를 프로젝트 안(`.cache/machine/zz_test`)으로 두고, 실제 설치(연결 · 환경 변수 · 작업 등록)는 사람이 연 관리자
  PowerShell 에서 한다(1_laptop.ps1 · 2_main.ps1).
