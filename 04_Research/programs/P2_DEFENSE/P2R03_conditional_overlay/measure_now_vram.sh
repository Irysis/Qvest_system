#!/usr/bin/env bash
# P2R03 재기동 런처(2026-10-18 04시 · 도훈 승인 "재기동") — measure_now.sh 에 GPU 메모리 할당 설정 한 줄만 더한다.
#   사건: E2 RX0 의 DNN 재학습(새 epoch 261개월)이 자정 무렵부터 한 달 ~7분 → 1.5~3시간으로 느려졌다(캐시 secs 471 → 5,983 → 11,453).
#   원인: PyTorch 캐싱 할당기가 달마다 조금 더 큰 학습 텐서(Xt 186 → 230MB · 2MB 단위 반올림)를 새 세그먼트로 잡고 옛 세그먼트를 쥐고 있다.
#         Windows 드라이버의 시스템 메모리 폴백 탓에 OOM 이 나지 않아 할당기가 캐시를 비우지 않고, VRAM 12GB 를 넘은 몫(공유 2.8GB)이
#         시스템 메모리로 넘어가 매 스텝이 PCIe 를 탄다(워커 8 · 전용 11.7GB + 공유 2.8GB 실측).
#   처치: 할당 크기를 2의 거듭제곱 2분할(128 · 192 · 256MB …)로 반올림 → 커지는 달도 같은 세그먼트를 재사용(시험: 커지는 할당 12회 예약 66MB → 24MB).
#         메모리 배치만 바꾼다 — 수치 결과 · 측정 절차(measure.sh) · 사전등록 핀 파일(engine.R 등)은 그대로. 완료된 달은 내용 주소 캐시에서 재사용.
export PYTORCH_CUDA_ALLOC_CONF=roundup_power2_divisions:2
exec bash /c/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay/measure_now.sh
