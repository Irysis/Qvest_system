#!/usr/bin/env bash
# P2R04 측정 런처(DESIGN §9 · P2R03 measure_now_vram.sh 형식) — measure_now.sh 에 GPU 메모리 할당 설정 한 줄만 더한다.
#   까닭(P2R03 10-18 04시 사건): DNN 재학습 중 PyTorch 캐싱 할당기가 달마다 조금 더 큰 학습 텐서를 새 세그먼트로 잡고 옛 세그먼트를 쥔 채
#         Windows 드라이버의 시스템 메모리 폴백으로 VRAM 을 넘어 PCIe 를 탔다(한 달 ~7분 → 1.5~3시간).
#   처치: 할당 크기를 2의 거듭제곱 2분할로 반올림 → 커지는 달도 같은 세그먼트를 재사용. 메모리 배치만 바꾼다 — 수치 결과 · 측정 절차(measure.sh) ·
#         사전등록 핀 파일은 그대로. 이 라운드는 P2R03 이 새 epoch 로 채운 DNN 내용 주소 캐시를 그대로 쓴다(적중이면 GPU 미사용 · 대비용).
export PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2
exec bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings/measure_now.sh
