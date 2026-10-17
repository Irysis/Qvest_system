#!/usr/bin/env bash
# P2R03 즉시 측정 진입점(도훈 10-17 20:05 '지금 바로 전략 실측해') — _lib/detached_env.sh 가 인자 없이 부르므로 인자를 여기서 고정한다.
#   --now = 갱신 완료 대기 생략(배리어 · precheck · 지문은 그대로) · --p=2 = 병렬 2(충실구현 레인이 같은 PC 에서 돌고 있어 메모리 여유용 · 결과 무관)
exec bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/measure.sh --now --p=2
