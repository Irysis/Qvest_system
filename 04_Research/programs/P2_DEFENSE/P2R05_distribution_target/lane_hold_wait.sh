#!/usr/bin/env bash
# P2R05 레인 자동 재개 감시 — _lib/detached_env.sh 로 세션 밖에 띄운다(인자 없이 불리므로 여기서 고정).
#   센티널 = P2R05 캐시 워밍 끝(warm_cache.sh 가 쓴다) · 마감 = 2026-10-19 20:00(워밍이 그때까지 안 끝나도 레인은 돌아온다).
exec /c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe -X utf8 \
  /c/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P2_DEFENSE/P2R05_distribution_target/lane_hold.py \
  wait-resume C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/_lib/night_state/p2r05_warm.done 2026-10-19T20:00
