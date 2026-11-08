# 환경 최신화 계획 — R · Python · 패키지 (실행 2026-11-09 낮 · 메인 PC)

도훈 지시(11-08): "R과 파이썬, 그리고 각종 사용 패키지들도 최신화" → 시점 = "지금 전부 · P2R05 다시 고정"(교체는 11-09 낮)
→ 목표 판 = "R 은 r-project.org 에서 안정화된 버전 확인 · 파이썬도 공식 홈페이지 확인 · 전부 최신화".

## 1. 목표 판 (11-08 공식 사이트 확인)

| 대상 | 지금 | 목표 | 근거 |
|---|---|---|---|
| R | 4.5.2 (C:/Program Files/R/R-4.5.2) | **4.6.2** | r-project.org "R version 4.6.2 (Diversified Portfolio) has been released on 2026-10-29" · CRAN VERSION-INFO Release 4.6.2 · 4.5.3 = 4.5 계열 wrap-up(old-release) |
| Rtools | Rtools45 | 그대로 | CRAN Rtools45 페이지: "used for R 4.5 and later" — R 4.5.x · 4.6.x · R-devel |
| R 패키지(사용자 라이브러리) | 347개(181개 오래됨) | R 4.6 바이너리로 전부 재설치 | CRAN 4.6 Windows 바이너리에 346개 있음 · RDCOMClient(0.96-1 · 코드 사용처 0) 만 없음 → 제외 |
| Python(시스템 · QVEST_PY) | 3.12.10 (pip 26.3 · openpyxl · numpy · pypdf · jsonschema) | **3.15.2** | python.org "Download Python 3.15.2" |
| venv `.venv_qvest_ml` | Python 3.12.10 · 66개(44개 오래됨) | Python 3.15.2 로 재생성 · 전부 최신 | PyPI: 63개 전부 cp315 Windows 휠 있음(autograd-gamma · PyYAML 은 소스 설치) |
| torch | 2.12.1+cu126 | **2.15.0+cu132** | download.pytorch.org cp315 win_amd64 = 2.15.0 cu132/cu134 · 메인 RTX 4080 SUPER 드라이버 610.88(CUDA 13.2 지원) |

메이저 변경(코드 영향 점검 대상): pandas 2.3 → 3.1(copy-on-write 기본 · 문자열 dtype 기본) · pyarrow 24 → 26 · optuna 4 → 5 · pypdf 6 → 7 ·
pillow 12 → 13 · python-dateutil 2 → 4 · torch 2.12 → 2.15 · R data.table 1.17 → 1.18 · arrow 24 → 26 · PerformanceAnalytics 2.0.8 → 2.1.0.

## 2. 먼저 막아야 할 것

1. **하드코딩 경로**: `R-4.5.2` = 살아 있는 파일 73개(daily_refresh.sh · run_fdb_incremental.sh · 예약 .bat 등) · `Python312` = 약 32개
   (+ venv `pyvenv.cfg` · 예약 작업 16개의 런처 `Python312\pythonw.exe`). 새 판 번호로 바꿔 박지 않고 **판 해석기**로 바꾼다
   (`QVEST_RSCRIPT` · `QVEST_PY` 덮어쓰기 → 설치된 것 중 최신 자동 탐색). 4.5.2 · 3.12 상태에서 같은 경로가 나오는지 먼저 확인한다(무변화 커밋).
2. **P2R05 고정값**(사전등록 · 결과 전): `operational_pins` = r_version 4.5.2 · bbdetection 1.0 · PerformanceAnalytics 2.0.8 · data.table 1.17.8 ·
   arrow 24.0.0 / `engines.python` = 3.12.10 · torch 2.12.1+cu126 · numpy 2.4.6 · pandas 2.3.3 · pyarrow 24.0.0 → 최신화 뒤 새 판으로 다시 고정
   (도훈 11-08 승인). 같이: P2R05 precheck/evaluate 의 bare `bash` → `qv_bash()`(메인 WSL 에서 지문 불일치 — 11-07 미수리분).
3. **노트북 동일성**: venv 는 OneDrive 로 공유된다 → Python 3.15 venv 가 되면 노트북은 Python 3.15.2 · R 4.6.2 · NVIDIA 드라이버(CUDA 13.2)를
   맞추기 전까지 venv 를 못 쓴다. **노트북은 맞출 때까지 켜지 않는다**(켜면 예약 작업이 메인 대행으로 돌다 실패).
4. **동시 세션**: Qvest(593bf0) 세션이 11-08 저녁~밤 venv · R 을 쓴다(퀀티 질의서 · xlsx 파싱 · R 적재) — 교체 직전 그 세션에 알리고 긴 작업이 끝난 뒤 시작.
   00:03~03:30 일일 리프레시 · 07:10 모닝 체인 창은 피한다. 11-10 00:03 = 첫 거래일 리프레시 → 그 전에 회귀까지 끝낸다.
5. **도구 세션 가상화**: `%LOCALAPPDATA%`(Python 사용자 설치 · R 사용자 라이브러리 · `Qvest\jobs`) 쓰기는 Claude 도구 세션에서 가짜가 된다 →
   설치는 일회용 예약 작업(Interactive · Limited)으로 띄우거나 도훈이 보통 PowerShell 에서. 프로젝트 안 venv 는 도구 세션에서 바로 된다.

## 3. 순서 (11-09 낮 · 약 4~6시간)

0. 기준선: R 패키지 목록 · pip freeze(시스템 · venv) · `run_all_hooks.sh` 전체 · 계약 회귀 · regime · continuity · 훅 배터리 결과를 남긴다.
1. 판 해석기 배선(R · bash · Python 공용) + 하드코딩 교체 → 지금 판에서 무변화 확인 → 커밋.
2. Python 3.15.2 사용자 설치(일회용 예약 작업) → `QVEST_PY` 갱신(사용자 환경 변수 · `~/.Renviron`) → 시스템 패키지 설치.
3. venv: 옛판 보관(`.venv_qvest_ml_py312_20261109`) → Python 3.15.2 로 새로 만듦 → 패키지 전부 최신 + torch 2.15.0+cu132 →
   import 전수 · `torch.cuda.is_available()` · 실동작 1회(xgboost fit · CRPS · optuna 짧은 탐색).
4. R 4.6.2 설치 → 사용자 라이브러리 `win-library/4.6` 에 347개(−RDCOMClient) 재설치 → Rcpp `sourceCpp` 컴파일 확인(Rtools45).
5. 예약 작업 런처 경로 재등록(`qvest_tasks.ps1 -Mode Export → Apply` · 도구 세션 밖).
6. 회귀: 0번 기준선과 같은 묶음 전체 → 새 실패는 원인을 찾아 고친다(판 차이로 결과가 바뀐 건 기록).
7. P2R05 다시 고정 → `precheck.R --dry` 통과.
8. 기록: 메모리 · `python-policy.md` 설치 실측 · 키트(1_laptop/2_main)에 시스템 Python · 드라이버 단계 추가 · 노트북 맞춤 절차.

되돌리기: R 4.5.2 · Python 3.12 는 지우지 않는다(`QVEST_RSCRIPT` · `QVEST_PY` 로 되돌림) · venv 옛판은 보관 폴더에서 이름만 되돌린다.

## 4. 결정 · 준비

- ✅ R 4.6.2 = **관리자 설치**(`C:\Program Files\R\R-4.6.2` · 도훈 11-08 "관리자 설치(PC 앞)") — UAC [예]는 도훈이 PC 앞에서(약 100초 안 · 원격 불가).
- ✅ 설치 파일(11-08 받음 · `.cache\installers\` · OneDrive 로 노트북에도 간다):
  - `R-4.6.2-win.exe` 91,363,600 B · MD5 `d01b7413cce5540a35eaf8295ef32197` = CRAN `md5sum.R-4.6.2.txt` · 서명 Valid(CN=Martyn Plummer)
  - `python-3.15.2-amd64.exe` 37,694,360 B · SHA-256 `06e225a2…f15aa` = python.org API · 서명 Valid(CN=Python Software Foundation)
- ✅ 설치 스크립트(이 폴더 · UTF-8 BOM — PowerShell 5.1 이 BOM 없는 UTF-8 을 CP949 로 읽어 한글이 깨진다) · `-DryRun` 통과(11-08):
  - `install_r462_admin.ps1` — 대조 → 관리자 아니면 스스로 UAC → 조용한 설치 → `Rscript --version` → `.cache\installers\R-4.6.2-install.result.txt`
  - `install_py3152_user.ps1` — 대조 → 사용자 설치(PATH · 연결 · py 런처 무접촉) → `python --version` · pip → `…\python-3.15.2-install.result.txt`
    (도구 세션 밖에서 — 일회용 예약 작업 또는 보통 PowerShell)
- 실행 방법(11-09): 도훈 "자리에 왔어" → Q 가 일회용 예약 작업(Interactive · Limited)으로 `install_r462_admin.ps1` 을 띄운다 → 화면 UAC [예]
  (또는 도훈이 보통 PowerShell 에서 `powershell -NoProfile -ExecutionPolicy Bypass -File <이 폴더>\install_r462_admin.ps1`).
- 남음: 노트북 NVIDIA 드라이버 갱신 시점(노트북을 다시 쓸 때 · 지금 581.08 → CUDA 13.2 지원판).
