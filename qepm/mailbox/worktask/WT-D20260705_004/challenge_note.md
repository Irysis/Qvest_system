# Self-Adversarial Challenge — WT-D20260705_004 (Alpha Research)

**Agent**: alpha-research (QEPM Opus 4.8 self-adversarial, v8.2 — AX-008 3-source 중 1개)
**Date**: 2026-07-05
**Finalize 직전 자체 적대검증**. 각 concern ACCEPT/PARTIAL/REBUTTAL 분류 + 근거. Charter §8 No Silent Override.

---

## 산출물 요약 (검증 대상)
- α̂ mean = established composite `score_eff` (rank-IC 0.042, ICIR 0.34, 256m — 실IC 보유·신규신호 아님).
- 예측 불확실성 σ̂ = NGBoost Normal.scale (expanding-window PIT), conformal lb = MAPIE SplitConformalRegressor 68%.
- 4 변형 동일 μ̂ mean 위 선택규칙만 변경: A point-top25 / B μ̂/σ̂ / C confidence-band(conformal lb>0) / D σ̂-shrunk.
- 실측: canonical_screen_bt (build_benchmark_compare, NW lag-3, metric_type=canonical_screen).

## 핵심 결과 (like-for-like, 196 full / 112 recent2017 월)
| 변형 | full PORT_t | recent2017 PORT_t | n_months(full) |
|---|---|---|---|
| A baseline | 0.970 | −0.725 | 196 |
| B risk_adj | 0.378 | −1.646 | 196 |
| C confband | 0.525 | +0.528 | **35 (degenerate)** |
| D shrunk | 0.566 | −1.196 | 196 |

**ΔPORT_t (best like-for-like B/D − A)**: full −0.40, recent 더 음. **FAIL** (2.95 게이트 근처도 아님).

---

## Concern 1 [HIGH] — Variant C "positive"를 성과로 오독할 위험 (프롬프트 concern ii/iii)
**적대 제기**: C가 full 0.525 / recent2017 +0.528로 유일하게 양수 — "confidence-band가 전이를 회복"으로 헤드라인?
**진단**: C의 n_months = full 35 / recent2017 **9** (A는 196/112). 정밀 진단: **196개월 중 0개월**만 conformal lb68>0 종목이 ≥25개(median 0, max 3). 즉 C는 실제로 25종 포트를 **한 번도 구성 못 함** — 1~3종 보유한 소수 월만 측정됨. rank_ic n=12/n=1.
**분류: ACCEPT (자기 반증)**. C의 양수는 **조건부-표집 생존편향 아티팩트**이지 like-for-like 개선 아님. → alpha_package·보고에서 C를 INVALID/degenerate로 명시, ΔPORT_t 판정에서 제외. 프롬프트가 경계하라 한 (ii)(iii)를 정확히 포착.
**근거**: `variant_results.json` C.full.n_months=35 vs A=196; 진단 스크립트 "months with >=25 confband-eligible names: 0/196". 1M active return의 68% conformal 하한이 양수인 종목이 사실상 없음(1M active는 노이즈 지배 — 당연).

## Concern 2 [HIGH] — σ̂가 look-ahead로 부풀려진 것 아닌가 (프롬프트 concern i)
**적대 제기**: expanding-window라 주장하나 NGBoost 재학습·MAPIE 캘리브가 미래 F1을 봤을 가능성?
**진단**: (a) 코드상 재학습은 `months[:ti]` 엄격히 t 이전만; MAPIE fit=months[:ti-24], conformalize=최근 과거 24m. (b) **누출 signature 검사**: PIT μ̂의 rank-IC = 0.031 ≤ score_eff mean IC 0.036 (동일 rows). 누출 모델이면 IC가 established mean을 **크게 상회**해야 하나 오히려 이하 → 부풀림 없음. (c) σ̂ 캘리브: within-month corr(σ̂, |realized active|) = **+0.207** — σ̂가 실현 분산을 유의하게 예측(진짜 정보). 캘리브가 진짜라 σ̂ 자체는 유효하나 그래도 선택개선 실패 → 결론 강화.
**분류: REBUTTAL (근거有)**. look-ahead 부재 입증(IC 비-부풀림 + 엄격 window). 학술: Duan et al. NGBoost 2020, Angelopoulos-Bates conformal 2023. L-code: [[reference-alpha-trends-2024-2026]] uncertainty-aware. 정량 3축: (IC 0.031≤0.036) + (σ̂-|active| corr +0.207) + (엄격 window months[:ti]).

## Concern 3 [MEDIUM] — 실패가 방법(NGBoost/MAPIE) 탓, 다른 확률모델이면 다를까
**적대 제기**: NGBoost 1종·MAPIE 1종만 시험. LightGBM-quantile/NGBoost-다분포면 회복?
**진단**: σ̂가 이미 calibrated(+0.207)인데도 selection/sizing이 A를 못 이김 = 병목은 σ̂ 추정 품질이 아니라 **1M long-only top-25 active의 IC→PORT_t 전이 자체**(신호계열·horizon·원천 무관 10-lead sweep으로 기확정, [[project-dart-insider-exec-nonreturn-frontier]]). σ̂ 차원 추가도 이 벽을 못 넘음이 본 WT의 확증 기여.
**분류: PARTIAL**. 다른 확률추정기 후속 EV는 존재하나(하한), calibrated σ̂ 실패는 **추정기 교체로 뒤집힐 결과 아님**(sizing 차원이 벽에 무력). 보고에 "추정기 1종 한계 — 단 calibrated σ̂ 실패라 낮은 EV" 명시.
**자기합리화 검사**: "다른 모델이면 될 것"은 조기-낙관 — 회피. 실측(calibrated σ̂ 무력)이 근거.

## Concern 4 [MEDIUM] — full-period 양수(A 0.97)를 "약한 성공"으로 볼 여지?
**적대 제기**: A full PORT_t 0.97 > 0, recent만 음 — 부분 성공?
**진단**: 0.97 ≪ 2.95 게이트. recent2017 −0.725 = cohort-wide decay(§6). full 양수는 2010-2016 기여분. 어떤 변형도 게이트 근처 아님. 자본급 아님.
**분류: ACCEPT**. "약한 성공" 라벨 금지 — clean FAIL. AX-000 정직보고: 탐색 중단 근거 아니나 본 경로(uncertainty selection)는 negative.

---

## 처리 결과 (반영)
1. C를 degenerate/INVALID 명시 — ΔPORT_t 판정은 A vs {B,D} like-for-like만. **ΔPORT_t < 0 = FAIL**.
2. look-ahead 부재·σ̂ 캘리브를 alpha_validation에 정량 기록(REBUTTAL 근거).
3. 판정: 불확실성-인지 선택/사이징은 IC→PORT_t 전이 **회복 실패**. 전이 벽이 sizing/selection 차원에 robust함을 추가 확증.
4. Axiom emit 대상(negative): return-composite mean 위 uncertainty-selection도 KR post-2017 감쇠벽 못 넘음.

## Escalate trigger 점검
- HIGH severity 2건 (< 5) / AX axiom hard FAIL 0 / PIT C1 위반 0 → **자동 escalate 불요**. Q-Lead 정상 핸드오프.

## 회피표현 자기검사
"미미/관행/보수적이면 OK" 미사용. C 양수를 "개선"으로 포장 안 함(생존편향 명시). 실측 수치·n_months 근거만.
