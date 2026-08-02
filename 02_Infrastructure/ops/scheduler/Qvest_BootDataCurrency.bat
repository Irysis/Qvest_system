@echo off
REM Qvest_BootDataCurrency — 부팅(로그온) 직후 데이터 최신성 확보. 도훈 지시 2026-08-03.
REM
REM 왜 로그온 트리거인가 (AtStartup 아님):
REM   "시스템 시작 시" 트리거는 로그인 전 SYSTEM 계정으로 실행된다. 이 파이프라인은
REM   OneDrive 경로(C:\Users\99922\OneDrive\...)와 사용자 PATH 의 R/Python 을 쓰므로
REM   SYSTEM 컨텍스트에선 경로 자체가 없어 실패한다. 사용자 로그온이 정본 시점이다.
REM
REM 중복 실행 걱정 없음: ensure_data_current.sh 가 신선도를 실제로 재고
REM   이미 최신이면 아무것도 하지 않는다(no-op). 새벽 00:03 DailyRefresh 가
REM   정상 수행된 날엔 이 태스크는 감사 한 번만 돌고 즉시 끝난다.
REM
REM NOTE: keep this .bat ASCII-only - cmd.exe reads it in CP949 and mangles UTF-8.
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Users/99922/AppData/Local/Programs/Python/Python312:/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; export QVEST_REFRESH_TG=1; bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/ensure_data_current.sh >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/boot_data_currency.log 2>&1"
