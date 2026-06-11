# B0 — 백테스트 엔진 거래비용 결함 진단 보고 (2026-06-10)

**발단**: 2026-06-10 아키텍처 감사 — "backtest_harness.R 리밸 경로 매도 수수료 누락, 고회전 전략 net 비용 ~50% 과소계상".
**수행**: B0 에이전트(진단·패치·pre-A/B) + Q-Lead(검수·post-A/B·판정·원복). metric_type=diagnostic.
**결론 1줄**: 매도 수수료 누락은 사실이나 **그게 본질이 아니다 — 엔진 비용모델 자체가 회전율 무관 flat 과금**이며, "매도 레그 추가" 패치는 A/B 실측으로 기각(원복). 올바른 수리 = **delta-based v2.4** (도훈 confirm 대기).

## 1. 코드 사실 (라인 근거)

엔진은 매 리밸마다 전 보유분을 share-재계산(전량매도→전량매수, netting 없음):
- **매수 레그**: `backtest_harness.R` Allocate 블록 — `cost <- shares * price_now * (1 + commission)` — **신규 포트 전체 명목에 15bps** (보유 지속 종목 포함, 매월).
- **매도 레그(리밸 경로)**: 0bps (누락 — 감사 지적 사실).
- **매도 레그(전량청산 경로)**: `proceeds * (1 - commission)` — 이쪽만 부과.

## 2. A/B 실측 (합성 산술 검증 — 가격고정 Close=10000, Ret=0 → NAV 감소 = 순수 비용)

| 케이스 (17 리밸, name-turnover) | pre-patch total_ret | post-patch(매도 flat 추가) |
|---|---|---|
| SYN_low (회전 0%) | **−2.52%** | **−4.84%** |
| SYN_high (회전 100%) | **−2.52%** | **−4.84%** |

- **0%와 100% 회전의 비용이 양쪽 모두 동일** → 엔진 비용은 실회전율에 *전혀* 반응하지 않음 (flat per-rebalance). 17리밸 × 15bps ≈ 2.52% ✓ / × ~30bps ≈ 4.84% ✓ (복리).
- 패치는 회전 민감성을 해결하지 못하고 flat을 2배로 만들 뿐 → **기각·원복**. **원복 회귀검증 PASS** (`b0_ab_reverted.json`, 2026-06-10 15시대): syn_low/syn_high total_ret −0.025194 둘 다 pre-patch와 일치, nav_end 원단위 동일 — 원복 하니스 = 원본과 수치적으로 동일 확인.
- 실데이터 레그(REAL_lowTO/highTO)는 pre/post 동일 에러("'names' attribute...")로 미산출 — 테스트 스크립트 결함(엔진 무관), 합성 케이스가 산술 증명으로 충분.

## 3. 보정(calibration) 진단 — 세 모델 비교 (월간 리밸 연환산)

| 모델 | 연 비용 | book(TO 5.57x/yr one-way) | 고회전(TO 12x) | 저회전(TO 2x) |
|---|---|---|---|---|
| 현행(매수 flat) | 12×15bps ≈ **1.8% 고정** | true 1.67% 대비 +0.13%p (≈정확) | true 3.6% 대비 **−50%** (감사 지적 구간) | true 0.6% 대비 **3× 과대** |
| 기각된 패치(양쪽 flat) | 24×15bps ≈ **3.6% 고정** | **+1.9%p 과대** (book SR 부당 −0.1급) | 정확 | 6× 과대 |
| **v2.4 delta-based (제안)** | 2×15bps×실회전 | 1.67% | 3.6% | 0.6% |

핵심 발견: **현행 flat 모델은 one-way TO≈6x/yr에서 정확히 보정**되어 있고, 현 book(5.57x)이 그 지점에 있다. 즉 기존 기록의 비용 왜곡은 book급 전략에선 무시 가능, **TO≳10x 전략에서만 과소(−50%까지), TO≲3x에서 과대**.

## 4. 처분

1. **패치 원복 완료** (수치 로직 원상복구, 진단 주석만 잔류 — comment-only diff + PARSE OK). 사유: 기존 전 기록과의 비교가능성 파괴 + 전형 TO 구간(2~8x) 2× 과대 과금 — 결함보다 보정이 나쁜 수리.
2. **올바른 수리 = cost_model v2.4 (delta-based)**: 리밸마다 종목별 |Δ보유 명목|에만 매수/매도 각 15bps. **cost_model_version bump = 전 전략 수치 이동(저TO 유리/고TO 불리) = 헌법급 — 도훈 confirm + 깨끗한 세션(hook 가동)에서 구현 + 기존 book 핵심수치 재측정 의무.**
3. **잠정 규율** (v2.4 전): TO > 10x/yr 전략의 게이트 판정 시 "비용 −최대 50% 과소계상" 경고 의무 (essence/judge 단계 — harness 주석에 명문화 완료).
4. 마켓임팩트 모델 부재(감사 別 지적)는 본 건 범위 밖 — v2.4 설계 시 동시 검토 권고.

## 5. 산출물
- `b0_explore.R` / `b0b_align_check.R` / `b0c_retorig_check.R` (진단 스크립트, B0 에이전트)
- `b0_fee_ab_test.R` (A/B 하니스) · `_prepatch_harness.R` (패치 전 스냅샷)
- `b0_ab_prepatch.json` / `b0_ab_postpatch.json` / `b0_ab_reverted.json` (실측)
- 본 보고서. n_trials 영향 없음(엔진 진단 — 전략 선택 아님).

## 6. 후속 — cost_model v2.4 구현 (2026-06-11, 도훈 confirm 후)

- **구현 완료 (opt-in)**: `run_monthly_simulation(..., cost_model_version)` — `"v2.3_flat"`(기본값, 기존과 비트단위 동일) / `"v2.4_delta"`(종목별 |Δ보유 명목|에 매수레그+매도레그 각 15bps, 보유 지속분 netting, 최초 진입 전액 매수레그, 전량청산 경로 매도 15bps 양 모드 동일). `judge_oos_helper.R::.joh_run_static_weight_sim`(flat ~30bps/리밸 독립 복제본)도 동일 파라미터 추가.
- **회귀 no-op PASS**: 기본값으로 SYN_low/SYN_high 재실행 → `b0_ab_reverted.json` 대비 nav_end 원단위 동일(97,480,600) + total_ret −0.025194 동일. judge helper도 prepatch baseline 대비 비트 동일.
- **v2.4 합성 산술 PASS + 회전율 단조성 입증**: SYN_low(0%) −0.150%, SYN_mid(50%, 신설) −2.523%, SYN_high(100%) −4.842% — 분석적 기대값 [−c, (1−c)^17−1, (1−c)(1−2c)^16−1] 대비 |diff| ≤ 5.9e-5. v2.3은 3케이스 전부 −2.52% (flat 무감도 재확인).
- **기본값 flip 미수행** — book 핵심수치 재측정 후 Q-Lead 별도 결정. 상세: `v24_ab_results.json` / `v24_fee_ab_test.R`.
