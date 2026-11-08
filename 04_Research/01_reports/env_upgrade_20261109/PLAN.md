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

## 5. 실행 기록 (2026-11-08 오후 · 메인 PC — 도훈 "진행해줘. 다른 세션 작업에선 R이랑 파이썬, GPU 안써"로 11-09 계획을 하루 앞당김)

| 시각 | 단계 | 결과 |
|---|---|---|
| 15:38 | Python 3.15.2 사용자 설치(일회용 예약 작업) | OK · pip 26.2.2 · `C:\Users\User\AppData\Local\Programs\Python\Python315` |
| 15:40 · 16:50 | 시스템 Python 패키지 | openpyxl 3.1.5 · numpy 2.5.4 · pypdf 7.0.0 · jsonschema · **pymupdf 1.28.2**(16:50 추가 — 아래 ①) |
| 15:41 | R 4.6.2 관리자 설치(UAC = 도훈) | OK · `Rscript (R) version 4.6.2 (2026-10-29)` |
| 15:44~15:52 | R 사용자 라이브러리 `win-library/4.6` | 348개(대상 343 · 빠짐 0) · RDCOMClient 제외 · Matrix · boot · mgcv = R 4.6.2 기본 라이브러리 · Rcpp 컴파일(Rtools45) 5/5 |
| ~16:00 | venv 재생성(옛판 = `.venv_qvest_ml_py312_20261108`) | Python 3.15.2 · 68개 · torch 2.15.0+cu132 · `cuda.is_available() = True` · pandas 3.1.1 · pyarrow 26.0.1 · 특수 처리: pandas ≥3 휠만 · PyYAML 순수 빌드 · ngboost `--no-deps --ignore-requires-python` + fit 확인 · wrapt <2.6 |
| 16:03 | 사용자 환경 전환(`switch_env.ps1` · 백업 `.cache/installers/env_backup_20261108.json`) | Path(Python312 → 315 · R-4.5.2 → 4.6.2) · `QVEST_PY` · `QVEST_RSCRIPT` · `~/.Renviron` QVEST_PY · 되돌리기 = `switch_env.ps1 -Rollback` |
| 16:05~ | 대체 경로 51파일 | 커밋 40232a68f(판 번호 치환만 — 기계 대조 51/51) |
| 16:07~16:32 | P2R05 DT 시험(run_all_tests.R 느린 판) | 8/8 · 엔진 시운전 16/16 · 공통 난수 사실 = 기록대로(torch 판만 다름) |
| 16:05~16:45 | 데이터 경로 54 묶음 | 기준선(11-08 03:22 밤 배터리) 대비 나빠짐 0 · 나아짐 5 · 기존 실패 5 그대로 |
| 16:37 | P2R05 다시 고정 | 9ed7b23f → dedc7a49(커밋 3f6d3d50f · 등록부 supersede · 바뀐 잎 27 = 판 · 증거 md5 · 평가 2파일) · precheck --dry rc 0 · 본 대조 항목 전부 통과 · 워밍 센티널 없음(워밍은 새 판으로 처음부터) |
| 16:46~20:46 | 전체 배터리 1차(suite_totals_watch --collect · 도구 세션 밖) | **4시간 제한 종료** — 132/404번째 `test_revival_flags_sync.R` 가 17:36 부터 CPU 0 정지(아래 ③) |
| 20:47~21:00 | 회귀 수리 | arrow 26 IO 스레드 1 교착 → `failure_revival_monitor.R` 수리(커밋 bb134d3e7) · 정지 테스트가 오염시킨 실파일 2개 복구 |
| 20:57~22:54 | 전체 배터리 2차(제한 6시간) | 완주 · 기준선(03:22) 대비 실패 123 → 108 · 나아짐 12 · **나빠짐 2 · 측정 사라짐 2**(아래 ④~⑦) |
| 23:29 | PerformanceAnalytics 2.1.0 → 2.0.8 | CRAN Archive 소스 · R 4.6.2 빌드(일회용 예약 작업 33초) · 2.1.0 사본 `.cache/installers/pkg_backup_20261108/` · 보류 등록 `06_Registry/infra_holds.json` |
| 23:37 | P2R05 핀 맞춤(2차 재핀) | dedc7a49 → bf45f4e7 · 바뀐 잎 정확히 1(PA 판) · 등록부 writer 결함(이력 누락) 수리 뒤 이력 보충 · 커밋 b0c9c3c43 · 1d2abf6bd · 본 대조 ALL OK(워밍 센티널만 없음) |
| 23:45 | 최신화 도구 보류 · 역의존 | 커밋 d65df9671 · `Infra: R 4.6.2 ✓ · Python 3.15.2 ✓ · venv 0(보류 2) · 시스템Py 0(보류 1) · R패키지 0(보류 1) \| 고정 P2R05(걸림 1)` — ★ 없음 |
| 23:58~02:16 | 전체 배터리 3차(최종 판) | 기준선(03:22) 대비 **나빠짐 0** · 나아짐 13 · 실패 123 → 94 · 총 10680 → 10755 · 측정 사라짐 3 = 전부 환경(아래 ⑧) |
| 02:30~03:45 | 포트 예약 수리(⑥ · 도훈 "회귀 뒤에 고쳐줘") | `qv_psock_cluster()` · 운영 5곳 교체 · 금칙 ⑧ · 커밋 6f0e260e3 |
| 16:53 | 부팅 Infra 줄 | 커밋 fa0146100 · `Infra: ★최신화 필요 — R 4.6.2 ✓ · Python 3.15.2 ✓ · venv 1(보류 1) · 시스템Py 0(보류 1) · R패키지 0 \| 고정 P2R05` |

① **메인 시스템 Python 에 pymupdf 가 없었다**(3.12 때도) — `00_Lawbook/tools/pdf_check.py` 가 QVEST_PY 로 돌아 PDF 생성이 검사 단계에서 rc 1(스트레스 일보 실측). 노트북엔 있었다 → 3.15 에 설치 · 일보 ②~④(PDF · 검사 포함) 통과.
② **판 효과 분리**: 스트레스 지수 빌드를 같은 코드 · 같은 데이터로 옛 venv(3.12 · pandas 2.3.3)와 새 venv(3.15 · pandas 3.1.1)에서 — 점수 max|d| = 0(부동소수 잡음 2.6e-13 두 열).
③ **회귀 1건(수리됨) — arrow 24.0.0 → 26.0.0 에서 IO 스레드 1개의 교착 조건이 넓어졌다.** 24 까지는 `mmap=FALSE` 와 겹칠 때만 멈췄는데(08-13 기록), 26 은 기본 `read_parquet` 도 CPU 0 으로 영원히 멈춘다.
   - 1차 배터리가 `test_revival_flags_sync.R`(refine_distilled → revival_monitor_run → `.rev_read_parquet`)에서 3시간 멈췄다.
   - 원인 = `failure_revival_monitor.R` 의 `set_io_thread_count(1L)`. 06-18 에 틀린 권고로 정정됐던 것이 남아 있었다. 같은 경로를 모닝브리핑 부활 감시 · axiom_approval_queue 가 타므로 다음 아침 체인도 멈출 자리였다.
   - 수리 = '2 미만이면 2'(저장소 관행 · 커밋 bb134d3e7).
   - 검증: 격자 16칸(cpu 1·기본 × io 2·기본 × mmap T/F × read/dataset) 정상(교착 = io 1 뿐) · `ARROW_IO_THREADS=1` 주입에도 정상 · 테스트 단독 7/7(62초).
   - 부수: 그 테스트는 실파일을 일부러 오염시키고 종료 때 되돌리는데, 강제 종료로 되돌리기가 안 돌았다. `.cache/failure_revival_flags.json` 의 `ZZSTALE_SYNC_TEST` 와 `DIST-AR-001.json` 의 `refined_by` 를 테스트 자체 백업으로 복구했다.
   - 남은 `set_io_thread_count(1)` = `04_Research/factor_rotation/fof_first_slice/*.R`(07-05 이후 쓰지 않는 연구 스크립트 · 다시 돌리면 같은 교착).
   - 운영 교훈: 일회용 예약 작업의 시간 제한은 powershell 만 끊는다. 그 아래 bash · R 은 고아로 남아 계속 돈다.
④ **회귀 — PerformanceAnalytics 2.1.0 이 측정 정의를 조용히 바꾼다 → 2.0.8 고정.** 같은 R 4.6.2 · xts 0.14.3 · zoo 1.9.1 에서 판만 바꿔 대조했다(2.0.8 = 옛 환경 값 비트 동일).
   - `Return.portfolio`(xts 날짜 비중 · `rebalance_on = NA`): 2.1.0 은 출력 날짜를 한 기간 앞으로 당긴다 — 값은 위치로 같고(d2 자산 수익으로 번 값) 날짜만 d1 로 붙는다 → 날짜로 벤치 · 다른 시계열과 합치면 하루 어긋난다. `test_fr_v4_measurement` 16/14(`재배분 행 ≠ Return.portfolio EOP 재도출`). 이름 붙은 **벡터 비중**(충실구현 하네스 `.leg_daily` · P2R05 `evaluate_fixture.R`)은 두 판이 같다.
   - `SharpeRatio.annualized`: `geometric` 기본값 TRUE → FALSE — 인자 없이 부르는 곳(충실구현 논문 기준 요약 `run_paper_replication.R:159` 등 11곳)의 연환산 Sharpe 가 산술로 바뀐다(실측 −0.664 → −0.598).
   - `UpDownRatios`: `geometric = TRUE` 신설 — 상승/하락 포착률이 바뀌고(일간 저장본 0.798 → 0.004 · 0.717 → 1.000) 상승 또는 하락 구간이 없는 입력에서 `dims [product 1] do not match` 오류 → `build_benchmark_compare` 중단 → `test_replication_harness` 1초 halt · STR_1715 등급 v3 B → NA.
   - 계약 지표(수익 · 낙폭 · Sharpe · 롤링 · 낙폭 표 · essence)는 저장본 13개 재계산에서 두 판 같았다 — 다른 건 위 셋뿐. 16:03 이후 새로 만든 `bt_result.rds` = 0건(2.1.0 산출물 없음).
   - 처치: 2.0.8 소스 빌드 → `test_replication_harness` 46/0 · `test_fr_v4_measurement` 50/0 · STR_1715 B · 수치 격자 53항목 옛과 동일. `06_Registry/infra_holds.json` 수동 보류(해제 조건 = 호출부를 판 무관하게 고정한 뒤 옛/새 판 대조 0 차이).
⑤ **회귀 — pandas 3 날짜 해상도.** `test_ae_c11_pit_features` 34/1 — pandas 3 는 핀 parquet 날짜를 `datetime64[s]` 로 읽고 운영 스파인은 `[ns]` · `merge_asof` 가 해상도 불일치로 거부. 운영 빌드(E1)는 통과 — 시험의 옛 라벨 재현 줄만 스파인 dtype 에 맞춤(커밋 2b6b6e42e · 새/옛 venv 36/0 · 위반 수 동일).
⑥ **업그레이드 무관(측정 사라짐 2건의 정체)**: `test_replication_harness` = ④ · `test_remeasure_from_holdings` = **Windows 포트 예약** — Hyper-V/WSL 이 TCP 11000–11999 중 531개(53%)를 예약해 `parallel::makePSOCKcluster` 의 무작위 포트가 절반쯤 `serverSocket` 실패(단독 3회 중 2회 · 실패 7건은 기준선과 같은 기존 실패). 메인 PC 기존 문제 · 운영 호출 5곳(remeasure 배치 · naver 수집 · grade_v3 backfill/retro · msm_asof) — 후속 과제.
⑦ **찾다가 고친 것 2**: (a) 등록부 writer `pr_record_round` 가 `modifyList` 로 합쳐 배열(이름 없는 리스트)을 버렸다 — P2R05 두 번째 supersede 이력이 등록부에 안 쌓였다 → `.pr_merge`(배열 = 통째 교체 · 커밋 b0c9c3c43 · 변종 red 실증) 뒤 사전등록 `repins[2]` 값으로 보충. (b) 최신화 도구가 mpmath 1.3.0 → 1.4.1 을 '올릴 것'으로 셌는데 sympy 1.14.0 이 `mpmath<1.4` 를 요구 — pip 모의 해석은 역의존 상한을 안 본다 → 역의존 판정 추가(커밋 d65df9671) · **mpmath 는 올리지 않음**.
⑧ **3차 배터리(최종 판 · 23:58~02:16) — 업그레이드 회귀 0.** 기준선 대비 나빠짐 0 · 나아짐 13 · 2차 대비 나아짐 4(④⑤⑦ 수리분) · 실패 123 → 94.
   - 측정 사라짐 3 = 전부 환경: `remeasure_from_holdings`(⑥ 포트 예약) · `rf_l2_driver` · `rf_overlay_adversary`(데일리 리프레시 잠금 — 잠금 중엔 미루게 만든 설계대로 `halt_refresh_lock` · `deferred_refresh_lock`). 둘은 2차(잠금 없음)에서 18/0 · 61/0 — 잠금이 풀린 뒤 다시 잰다.
   - 정정(퀀티 수집 세션 회신 03:40): 00:03 리프레시는 **멈춘 게 아니었다**. 감시 줄 'CPU 증가 없음'은 계측 착시(이 실행이 띄운 Excel CPU 합을 최댓값과 비교 → 책 하나가 끝나 Excel 이 닫히면 합이 떨어진다). 실제 = OHLCVS 00:57 · Universe_Support 02:03 · Investor_Act 02:35 저장 · Consensus 처리 중. 길어진 이유 = 신규 상장 99종의 보충 창 첫 수집. 계측 수리는 그 세션이 리프레시 뒤에 한다.
   - ⑥ 포트 예약은 이어서 수리(커밋 6f0e260e3 · `02_Infrastructure/ops/qv_psock.R` · r-portability.md 금칙 ⑧): `remeasure_from_holdings` 5회 연속 포트 오류 0(수리 전 3회 중 2회) · 도우미 시험 11/11(돌연변이 red · 운영 R 840개 직접 호출 0) · 관련 시험 기준선과 같음 · 등급 재채점 2종 · MSM 병렬 경로 실행 정상(적합 = 순차와 같음).

남은 일: ⓐ 노트북 = Python 3.15.2 · R 4.6.2(+패키지) · NVIDIA 드라이버(CUDA 13.2) 맞출 때까지 켜지 않는다(공유 venv 가 3.15 를 가리킨다) ·
ⓑ Claude 앱 재시작 — 앱은 시작 때 PATH 를 들고 있어 세션 Bash 의 `Rscript` · `python` 이 아직 4.5.2 · 3.12(옛 판을 지우지 않아 동작은 함 · 예약 작업은 새 판) ·
ⓒ 예약 작업 Qvest_InfraCurrency 등록(도훈 PowerShell) · ⓓ `daily_refresh.sh` 의 R-4.5.2 · Python312 대체 경로(다른 세션 편집 중이라 제외 — PATH 를 먼저 보므로 동작 영향 없음) ·
ⓔ 옛 R 4.5.2 · Python 3.12 · venv 사본 삭제는 노트북까지 맞춘 뒤 ·
ⓕ 예약 작업 17개의 실행기 = `Python312\pythonw.exe hidden_launch.pyw …`(감싼 `.cmd` 안에는 옛 경로 없음) — 3.12 를 지우기 전에 `qvest_tasks.ps1 -Mode Export → Apply` 로 다시 감싼다(실행기 탐색이 Python3* 최신을 고른다 · 도구 세션 밖) ·
ⓖ 노트북도 R 4.6 라이브러리에 **PerformanceAnalytics 2.0.8** 을 소스로 깐다(`.cache/installers/install_pa208.R` 그대로 · 아래 §6 4번 뒤) — 안 하면 노트북만 2.1.0 이 되어 두 대 값이 갈린다 ·
ⓗ ~~메인 PC 포트 예약(⑥)으로 `makePSOCKcluster` 가 절반쯤 실패~~ → ✅ 11-09 수리(커밋 6f0e260e3) — 노트북도 같은 코드라 별도 조치 없음(예약 범위는 기계마다 다를 수 있다).

## 6. 노트북(RAZER_BLADE_16) 맞춤 절차 — 메인과 같은 판으로(켜기 전에 · 도훈 PC 앞)

venv(`.venv_qvest_ml`)는 OneDrive 로 공유되고 이미 3.15.2 를 가리킨다 → 노트북은 아래를 끝내기 전엔 Python 작업이 전부 실패한다. 순서(메인 11-08 에 쓴 스크립트 그대로 · 설치 파일은 `.cache\installers\` 에 이미 있다):
1. 노트북을 켜면 예약 작업이 먼저 돈다 → 켜자마자 `qvest_tasks.ps1 -Mode Status` 로 보고, 맞추는 동안은 Claude 를 노트북에서 띄우지 않는다(두 대 동시 금지).
2. `install_py3152_user.ps1`(사용자 설치 · 보통 PowerShell) → `install_py315_syspkgs.ps1`(openpyxl · numpy · pypdf · jsonschema · pymupdf).
3. `install_r462_admin.ps1`(UAC [예]) → `install_r46_packages.ps1`(그 기계의 win-library/4.5 목록을 4.6 바이너리로 · RDCOMClient 제외) →
   **`.cache\installers\install_pa208.ps1`**(PerformanceAnalytics 2.1.0 → 2.0.8 소스 빌드 · `06_Registry/infra_holds.json` 보류 — 안 하면 노트북만 측정 정의가 바뀐다 · 확인 = `Rscript -e "packageVersion('PerformanceAnalytics')"` = 2.0.8).
4. NVIDIA 드라이버를 CUDA 13.2 지원판으로(지금 581.08 · 메인은 610.88 에서 torch 2.15.0+cu132 학습 확인).
5. `switch_env.ps1`(사용자 Path · QVEST_PY · QVEST_RSCRIPT · 백업 · 되돌리기 `-Rollback`) → `~/.Renviron` 의 QVEST_PY 는 같은 경로라 그대로.
6. 확인: `Rscript --version` = 4.6.2 · `.venv_qvest_ml\Scripts\python.exe -c "import torch; print(torch.__version__, torch.cuda.is_available())"` = 2.15.0+cu132 True ·
   `python 02_Infrastructure/ops/infra_currency.py` → `Infra:` 줄 R · Python ✓ · 그 뒤 `qvest_tasks.ps1 -Mode Export → Apply`(실행기 3.15) · Qvest_InfraCurrency 등록.
