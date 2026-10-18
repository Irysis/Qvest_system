#!/usr/bin/env bash
# P2R04 즉시 측정 진입점(P2R03 measure_now.sh 형식) — _lib/detached_env.sh 가 인자 없이 부르므로 인자를 여기서 고정한다.
#   --now = 갱신 완료 대기 생략(배리어 · precheck · 지문은 그대로) · --p=2 = 장치 칸 병렬 2(DESIGN §6 · 메모리 여유 · 결과 무관)
exec bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/measure.sh --now --p=2
