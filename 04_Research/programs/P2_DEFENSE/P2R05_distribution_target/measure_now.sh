#!/usr/bin/env bash
# P2R05 즉시 측정 진입점(P2R04 measure_now.sh 형식) — _lib/detached_env.sh 가 인자 없이 부르므로 인자를 여기서 고정한다.
#   --now = 갱신 완료 대기 생략(배리어 · precheck · 워밍 센티널 단정 · 지문은 그대로) · --p=2 = 나머지 칸 병렬 2(메모리 여유 · 결과 무관).
#   워밍이 낡았으면 측정하지 않는다(--rewarm 은 넣지 않는다 — 다시 워밍은 Q 가 warm_cache.sh 로 띄운다 · 레인 GPU 배분 = 도훈 확인 사항).
exec bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P2_DEFENSE/P2R05_distribution_target/measure.sh --now --p=2
