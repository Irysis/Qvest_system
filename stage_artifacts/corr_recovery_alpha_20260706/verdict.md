# Verdict — Correlation-Recovery (post-crash de-correlation speed) alpha lane

**날짜**: 2026-07-06 · **모드**: alpha_research · **L-code**: L-AR-20260706_083725
**목표(마일스톤 기준)**: 현 PG2 book IR **1.416** (STR_1715_on_M4_R05_noLayer4) 초과. 이것만이 마일스톤.

---

## (A) 상관-회복 신호가 PG2(1.416)를 넘나?

**아니오 — 넘지 못했다. 그리고 넘을 수 있는지 판정하는 PORT_t 단계까지도 가지 못했다.**
cheap rank-IC screen에서 robust·sign-stable·recent-holding 횡단면 신호가 부재 → Canonical/PORT_t 전에 정직 STOP (canonical_result.json 미생성 = 프로토콜대로 "cheap screen서 신호 없으면 즉시 중단").

## (B) 못 넘었으면 어디서? 이 novel mechanics도 전이벽에 걸리나?

**벽에 걸린 지점 = 스크린 신호 부재 + KR post-2017 IC→PORT_t 전이벽 (둘 다).** book-marginal까지 가지도 못했다.

정량 근거 (panel 82,818행·270월 200401-202606·852종목, 독립 재현 완료):

| 신호 | full-period rank-IC t | mean IC | pre-2017 t | 2017+ t |
|---|---|---|---|---|
| RAW recovery_frac | **-2.05** (유의, 但 부호 음) | -0.0119 | -2.43 | **-0.57 (noise 붕괴)** |
| RESID corr_recov_resid | +1.70 (|t|<2 미달) | +0.0115 | **-0.56 (음)** | **+3.54 (양)** |

- **RAW**: full-period |t|>=2 통과하나 부호가 음(느린 회복=초과수익, 가설과 반대). **2017+ t=-0.57로 noise 붕괴** → 전이벽이 이 novel lane에도 적용.
- **RESID**: full-period t=1.70 미달. pre-2017 음(-0.56) vs 2017+ 양(+3.54) = **부호 역전** = subsample별 불안정.

**적대검증 5축 (전부 판정 지지):**
1. **부호 불안정**: RAW(-0.0119) vs RESID(+0.0115) full-period IC 부호 반대 = abs-corr 잔차화 하에서 sign-flip. robust edge 아님.
2. **cherry-pick 함정**: 유일 |t|>2인 RESID 2017+ (t=3.54)는 full-period 미달 subsample에서만 발생 = subsample-mining. gate가 "strongest full-period |t| primary + full AND 2017+ 지속" 규칙으로 정확히 refuse.
3. **lag+1 placebo (fwd 1M 추가 shift)**: RESID lead2 t=**+1.93** ≈ lead1 t=+1.70 → **미감쇠**. 진짜 1개월-ahead 신호라면 lead2에서 급감해야 하나 안 감 = persistence(자기상관) 구조이지 clean forward 예측 아님 (추가 red flag). 대조로 RAW lead2 t=-0.04 = 정상 감쇠(RAW의 lead1은 진짜지만 약하고 post-2017 죽음).
4. **PIT clean (코드 감사)**: 신호 = 월말 t까지 trailing daily Ret only, forward = next_ym(t+1), 동월 concurrent 없음, universe membership t 기준. → 스크린 FAIL은 look-ahead 결함이 아닌 **진짜 신호 부재**.
5. **직교성**: vs score_eff pooled -0.076 (<0.4) = 직교하나 "직교 ≠ 수익" (measurement-graduation §6). 낮은 상관이 신호를 구제하지 못함.

**결론**: 상관-회복(post-crash de-correlation speed) novel mechanics도 KR post-2017 신호감쇠 벽에 걸린다. return-derived crash-dynamics 계열 소진. 시장-타이밍이 아닌 횡단면 선택으로 구성했음에도(overlay 4중부정 회피) 신호 자체가 없다.

## (C) emit id + 다음

- **emit id**: `L-AR-20260706_083725` (stage_artifacts/l_code/alpha_research/l_code_AR_corr_recovery_crashdyn_20260706.json). tags: VALIDATED_NEGATIVE, CROSS_SECTIONAL, CRASH_DYNAMICS, CORR_RECOVERY, POST2017_DECAY_WALL. metric_type=canonical_screen(스크린-tier), grade=F. **병렬 세션 재중복 방지 = correlation-recovery/de-correlation-speed lane 테스트됨 기록 완료.**
- **다음 (저EV 재시도 금지 라벨)**: return-derived crash-dynamics 소진. 잔여 EV = **비-return crash-resilience 원천**(DART insider 역사파싱 backfill 진행중 · 유동성 회복 · 정보이론적 회복측정) — 단 TE net-sink는 이미 FALSIFIED(project-te-netsink-falsified). MEMORY의 IC→PORT_t 전이벽 확증군에 상관-회복 1건 추가.
