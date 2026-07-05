@echo off
cd /d C:\Users\99922\OneDrive\Quant_Module_Moltbot
set BUDGET=6000
set BF_START=2015-01
set BF_END=2024-02
"C:\Program Files\Git\bin\bash.exe" -lc "cd 'C:/Users/99922/OneDrive/Quant_Module_Moltbot' && BUDGET=6000 RESET_EPOCH=0 BF_START=2015-01 BF_END=2024-02 bash stage_artifacts/dart_sleeve_test/code/gated_priority_launch.sh"
