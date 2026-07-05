# Judge Self-Adversarial Challenge — WT-D20260705_004

**Agent**: judge (QEPM Opus 4.8 self-adversarial, v8.2 — AX-008 3-source 중 1개, self-adversarial replaces Codex Round)
**Date**: 2026-07-05
**verdict finalize 직전 자체 적대검증**. PIT 최종 판결자로서 self-rationalization 방어가 본질. Charter §8 No Silent Override.

## 판정 요약 (검증 대상)
- Verdict: **JUDGE_FAILED** (graduation/자본 tier). essence_score authoritative **Grade C**.
- Gate C (net alpha): forge-authoritative full PORT_t **0.970 < 2.95 HARD** → FAIL.
- 추가 HARD FAIL 2건: oos_retention −0.604 (<0.5 무조건 FAIL), Calmar 0.418 (<0.64).
- 3/4 graduation HARD 게이트 미달 (PORT_t / oos_retention / calmar). Sharpe 0.813·CAGR 17.56%만 통과.

---

## Concern J1 [HIGH] — AX-001 v2 conditional metric을 잘못 적용 안 했나 (defense 전기간 SR 평가 금지)?
**적대 제기**: score_eff는 defense sleeve를 포함한 composite. recent2017 음수를 근거로 FAIL 판정하면 AX-001 v2(방어형 조건부 평가) 위반 프레이밍 아닌가?
**진단**: score_eff는 **offense composite**(value/quality/momentum/flow/defense blend가 크로스섹션 alpha를 겨냥)이지 standalone 방어팩터가 아니다. 본 WT thesis = uncertainty-aware transition-wall recovery이지 crisis_alpha가 아님. graduation 축 = PORT_t(실현 active alpha)로 올바르다. AX-001 v2는 방어형 팩터를 crisis 조건부 성과로 평가하라는 규칙 — 여기엔 미적용 영역. crisis_alpha·MDD-완화 프레임 부적용.
**분류: REBUTTAL**. AX-001 v2 오적용 없음. 근거: WT thesis = transition probe, 게이트 = PORT_t authoritative.

## Concern J2 [HIGH] — Variant C의 recent2017 +0.528을 under-credit 하고 있지 않나?
**적대 제기**: C만 recent window 양수. confidence-band selection이 진짜 회복인데 dismiss?
**진단**: 독립 검증 — C는 **0/196월**만 ≥25종 conformal-eligible 포트를 구성(median 0, max 3). n_months=35 full/9 recent, rank_ic n=12/n=1, IC=−0.0/NaN. C의 양수 = **조건부-표집 생존편향 아티팩트**(1~3종 보유 소수 월만 측정). alpha agent가 이미 ACCEPT로 degenerate 처리. ΔPORT_t 판정서 정당 제외.
**분류: ACCEPT (self-rebuttal → verdict 불변)**. C를 성과로 세면 오독. 판정 유지.

## Concern J3 [MEDIUM] — optimizer grid-max(0.669 > EW-covered 0.583, +0.086)이 uncertainty 유효 증거?
**적대 제기**: 24-cell 스캔서 AWARE cell이 blind-covered 초과.
**진단**: argmax-of-24 = selection overfit(DSR selection-operator 영역). (a) 그 cell recent2017 = −1.01(OOS 역전), (b) true baseline-A EW(0.970 full/0.625 common) 못 넘음, (c) 승리 코너 = heavy shrinkage ≈ EW-mimic(σ̂ 활용이 아니라 EW를 닮아서 이김), (d) +0.086은 2.95 근처 아님. tuning-robust 우위 아님. 납품물 = pre-registered EW(chain).
**분류: REBUTTAL**. selection artifact. DSR 게이트는 chain 납품엔 부적용(sweep은 진단 라벨).

## Concern J4 [MEDIUM] — Lockbox Extension Audit 의무를 discharge 했나 ("unavailable" 단순처리 금지)?
**적대 제기**: 프롬프트가 "lockbox unavailable" 단순처리를 의무회피로 간주.
**진단**: lockbox-scope.md에 따라 forge/monitoring lockbox는 폐기이나, **실질 OOS 측정은 존재** — recent2017(112m, 2017-2026)이 deployment-analog OOS이고 forge가 authoritative(−0.725)로 측정. frozen-weights buy-and-hold OOS extension = recent2017 window와 동형. equity_curve.png + oos_zoom_chart.png 둘 다 2026까지 연속(끊김 없음) → OOS_CHART_INCOMPLETE flag 불요. OOS는 측정됐고, 완전하며, FAIL.
**분류: REBUTTAL / discharged**. OOS 측정·차트 완결 확인. 의무 이행.

## Concern J5 [MEDIUM] — Screening tier screen-route(OVERLAY_CANDIDATE)를 부여해야 하나?
**적대 제기**: SR 0.813≥0.7 ∧ CAGR 17.56%≥12% ∧ no-PIT → screen_pass 기준 충족.
**진단**: screening signal력은 실재하나 **기저 composite(score_eff)에 귀속** — 이미 알려진/등록된 신호. 본 WT의 novelty(uncertainty 차원)는 ΔPORT_t < 0로 FAIL. screen-route 크레딧은 incumbent score_eff 몫이지 이 WT 기여 아님. recent2017 −0.725 = cohort-wide 2017+ decay-pattern(§3 decay, overfit 아님).
**분류: PARTIAL/ACCEPT**. screen_pass=TRUE 기록하되 **base-composite 귀속** 명시, 신규 module 라우팅 없음. novelty(uncertainty)는 clean FAIL.

---

## Role Honesty Audit (6종)
1. **alpha**: α̂ mean(score_eff) + σ̂(NGBoost/conformal)만 산출. Σ/weight 미침범. ✓
2. **risk**: Σ + tail + stress + crowding만. alpha·weight 불변(R1 degenerate-LW 자가수정, R4 RF-R1 structural 라벨). ✓
3. **optimizer**: weights(EW top-25)만. alpha/risk 재해석 없음. validity anchor로 baseline A 정확 재현(4dp). ✓
4. **forge**: pure function. hash 6/6 무수정, weights.csv as-is, alpha_scores는 returns(F1) 공급용만. ✓
5. **challenge_note 실재**: 4-agent 자가반증 실재 확인 — alpha C 생존편향 ACCEPT + look-ahead REBUTTAL(3축 정량), risk R1 자가결함 ACCEPT+수정, optimizer 24-cell overfit 코너 REBUTTAL, forge CF-F1~F5. ✓
6. **metric_type 라벨 정직**: alpha/optimizer=canonical_screen/weighted_screen(estimated), forge=backtested(authoritative). proxy 손계산 0. ✓

## AX-008 Verification Triangulation (3-source ≥2/3)
- **Forge**: authoritative build_benchmark_compare full 0.9698/recent −0.7248, audit 12 PASS/0 FAIL. **PASS**.
- **Self-Adversarial (본 절)**: J1~J5 처리, HIGH 2건 자율분류, escalate 0. **PASS**.
- Architect: 비호출(capital-grade off table, mechanical). 2/3 충족 ✓.

## Escalate trigger 점검
- HIGH severity 2건 (< 5) / AX axiom hard FAIL 0 / PIT C1 hard violation 0 → **자동 escalate 불요**. Q-Lead 정상 핸드오프.

## 회피표현 자기검사
"미미/관행/보수적이면 OK/대부분 동일" 미사용. C 양수를 성과로 포장 안 함(생존편향 명시). grid-max +0.086을 uncertainty 유효로 포장 안 함(selection artifact 명시). full 0.97을 "약한 성공"으로 포장 안 함(clean FAIL). 실측 수치·n_months·NW-t 근거만.

## Bottom line
불확실성-인지 α̂ 예측(calibrated σ̂ +0.207)과 신뢰기반 selection/sizing이 IC→PORT_t 전이를 **회복하지 못함**(clean FAIL). PIT look-ahead 부재 입증(μ̂ IC 0.031≤0.036 + σ̂ calib + strict window). 전이 벽이 selection AND sizing 양 레벨서 uncertainty 차원에 robust. **JUDGE_FAILED (graduation tier), Grade C.** 판정 = 측정 PASS(계약충족·audit clean) / 졸업 FAIL(정직, AX-000 reframe). L-code L-JG-20260705_200604 emit(negative ledger).
