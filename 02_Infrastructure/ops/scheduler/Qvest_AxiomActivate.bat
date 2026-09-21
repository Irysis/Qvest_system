@echo off
REM Qvest_AxiomActivate.bat — 주간 공리(+정책) 자동 활성화 (2026-09-21 도훈 승인 플랜 Part 3 · D5)
REM ★왜 이 파일이 필요한가: 작업 스케줄러 Qvest_AxiomActivate 의 액션이 `bash.exe -lc "Rscript 02_Infrastructure/ops/rf_axiom_activate.R >> .cache/scheduler_logs/..."`
REM   였고 Start-In 이 비어 있어 C:\Windows\System32 에서 상대경로 리디렉션이 실패 → 2026-08-30 등록 이후 매주 rc=1 로 죽었다(무인 실행 0회).
REM   Qvest_WeeklyCleaner.bat 형(PATH·QM_ROOT·cd 명시)으로 감싼다. 태스크 액션을 이 .bat 로 바꾸는 것은 도훈 확인 뒤:
REM     schtasks /Change /TN Qvest_AxiomActivate /TR "C:\Users\99922\OneDrive\Quant_Module_Moltbot\02_Infrastructure\ops\scheduler\Qvest_AxiomActivate.bat"
REM   검증: 다음 토요일 10:30 뒤 .cache/scheduler_logs/axiom_activate.log 존재 + reinforce_auto_log.jsonl 에 src="axiom_activate" 이벤트.
REM   --tree policies 는 promote.R policy tier 배선(D5 잔여) 뒤에 두 번째 줄로 추가한다.
"C:\Program Files\Git\bin\bash.exe" -c "export PATH='/c/Users/99922/AppData/Local/Programs/Python/Python312:/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QM_ROOT=C:/Users/99922/OneDrive/Quant_Module_Moltbot; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; export LANG=C.UTF-8; export LC_ALL='English_United States.utf8'; cd /c/Users/99922/OneDrive/Quant_Module_Moltbot; mkdir -p .cache/scheduler_logs; Rscript 02_Infrastructure/ops/rf_axiom_activate.R >> /c/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/scheduler_logs/axiom_activate.log 2>&1"
