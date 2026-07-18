# D3 swap-in 준비 노트 — 도훈 아침 confirm 대기 (2026-07-19 03:xx)

## 상태: 측정 조건 충족 · 자동실행 불가(자본 게이트) · 현 시점 실효 0

도훈 지시("정확 비교 후 D3가 더 좋으면 대체 진행")에 대해 — **book_state 변경은 비가역 자본 게이트라 Q 자율 실행 금지**(measurement-graduation §4, governor 정지). 아래를 스테이징하고 **도훈 수동 confirm 1회**를 대기합니다.

## 1. 측정 조건 — 충족 (D3 파레토 우위, 정본 noLayer4 기준)
`stage_artifacts/WT_D20260718_007/d3_nolayer4_remeasure.rds` (weighted_screen_bt 계약수익, 2008~2026 221m):
| | 현행 PG2 (m4×r05) | D3 (M4∩AE gate×r05) |
|---|---|---|
| calmar | 2.089 | **2.341** (+0.252) |
| MDD | −22.1% | **−19.8%** (+2.3%p) |
| CAGR / SR | 0.461 / 1.824 | 0.463 / 1.836 (중립) |
→ 수익 동일, 낙폭 개선. 파레토 지배(무비용).

## 2. 현 시점 실효 — 0 (기다려도 손실/리스크 없음)
라이브 2026-07 배포 manifest(`WT-D20260702_002/output/20260701_noLayer4_manifest.json`): **m4=1.0(M4 미발화)** → D3 게이트(M4 AND AE) 무발동 → invested 0.30(전량 R05 CRISIS 꼬리) 동일. **D3 첫 실효 = M4가 발화하는 첫 달**(AE는 이미 발화 중, 2026-08~ 감시).

## 3. swap-in 시 실제 변경 (도훈 confirm 후)
- **구성 변경**: 오버레이 regime 승수를 `m4`(BOCPD 연속 스케줄) → `M4∩AE 게이트`(둘 다 발화 시 0.70, else 1.0)로 교체. R05 꼬리·알파·유니버스 전부 불변.
- **코드**: `05_Production` forward_weights 오버레이 함수 + 라이브 생성 경로에 AE 게이트 배선(read-only 소스 미러 → live_track).
- **book_state.json**: schedule_logic_version 갱신 + admitted_id 유지(오버레이 부품 교체이지 새 전략 아님). 
- **AE 신호 라이브화**: `ae_regime_extend.py`를 월간 파이프라인에 배선(현 2026-08 decision까지 실측 완료).

## 4. 미검(swap 전 권고, 비차단)
- deep-crisis floor 판정: M4가 깊게(<0.70) 발화+AE 발화한 과거 달에 D3 0.70 floor가 방어적/열세인지(2008-11 m4=0.756류 분해). 현재는 m4=1.0이라 무관하나, swap 후 깊은 위기 대비 확인 권고.

## 결론
아침에 이 노트 + `d3_nolayer4_remeasure.rds` 확인 후 **"D3 swap-in 승인"** 한 마디면 배선 진행. 현 시점 실효 0이라 서두를 이유 없음 — 2026-08 M4 발화 감시하며 그 시점 재측정 권장.
