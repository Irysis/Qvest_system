# FQ-058 Self-Adversarial Challenge Note

**Round**: FQ-058 method_frontier — structural-drawdown-aware construction (MinCDaR / MinCVaR vs MinVar/MVO/EW)
**Agent**: optimizer-research | **round_tag**: fq058_20260718_191740 | **pin_consumed**: fq057_20260718_171024
**metric_type**: canonical_screen (construction_ab_diagnostic) | 자본/졸업 주장 없음
**Verdict (pre-finalize)**: `config_scoped_negative` — 위험 measure를 분산→drawdown 으로 바꾼 WEIGHTING 목적함수는 이 재료/config 에서 structural DD·calmar 을 개선하지 못하고 EW(1/N)에 열위, turnover 상한 초과.

AX-008: self-adversarial 은 Forge·Architect 와 3-source 중 1. finalize 직전 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL 분류.

---

## C1. [alpha-drop 교란] 드로우다운 arm(MinCDaR/MinCVaR)이 basket 내 alpha 를 무시하므로, EW/MVO 대비 열위는 '위험 measure' 가 아니라 'alpha 미사용'을 재는 것 아닌가?
**분류: REBUTTAL (설계로 선제 차단) + PARTIAL (한 갈래 미검)**
- **REBUTTAL**: PRIMARY 판정축은 **MinCDaR vs MinVar** 이다. 둘 다 basket 내 alpha 를 쓰지 않고(pure risk-min), 동일 top-25 basket·동일 daily-120 표본·동일 제약에서 **위험 MEASURE(drawdown vs variance)만** 다르다 → alpha-drop 교란이 원천적으로 상쇄된다(사전등록 fq058_preregistration.json `arm_confound_control`). 그 축에서 결과 = paired NW-t **+0.49 / −0.15**(무의미) + structural DD **1/2 개선**. 즉 measure swap 자체가 DD 를 유의 개선하지 못한다 — alpha 와 무관한 결론.
- **PARTIAL(수용)**: alpha 를 유지한 **mean-CDaR(max α′w − κ·CDaR)** 는 미측정 — 이는 objective swap 의 또 다른 갈래로 `next_probe`. 단 pure risk-min 은 drawdown-통제의 **최대치** 설정이므로, 최대 drawdown-초점에서도 MinVar 대비 DD 개선이 없다는 사실은 measure-축 negative 의 상한 증거다(중간 κ 는 DD 를 덜 통제 → 더 좋아질 수 없음).

## C2. [재료 n=2·둘 다 모멘텀] 재료가 momentum 2종뿐 — negative 가 momentum-특이일 수 있고 일반화 불가.
**분류: PARTIAL ACCEPT (config-scoped 명시로 대응)**
- 사전등록 선정규칙(screen_pass ∧ calmar<0.64, MDD desc)이 실제로 **momentum 2종만** 자격부여(low_vol/reversal/small_size 는 screen_pass FAIL — 신호력 부족). 이는 결과-선택이 아니라 규칙의 결정론적 산출이나, **family 판결이 아님**을 verdict_type = `config_scoped_negative` 로 명시. 
- 기전(체계적 crash)은 momentum 특성이므로, drawdown 이 **종목-특이(idiosyncratic)** 인 재료라면 weighting-측 drawdown-통제가 먹힐 여지 존재 → 정확히 `live_trigger`/`next_probe`. 정직한 한계로 기록.

## C3. [pure risk-min corner·κ 미sweep] 코너 해라서 tuned κ 의 mean-CDaR 는 더 나은 tradeoff 를 낼 수 있다.
**분류: REBUTTAL (DD-축) + PARTIAL (return-tradeoff-축 open)**
- **REBUTTAL(DD-축)**: 본 라운드 질문 = "drawdown 목적이 **structural DD** 를 통제하는가". pure MinCDaR = drawdown-통제 최대 설정. 그것조차 MinVar 대비 DD 를 일관 개선 못 함(1/2) → DD-통제 능력 부재는 κ 와 무관하게 robust.
- **PARTIAL**: "drawdown 을 조금 통제하며 수익도 지키는" return-tradeoff-축은 mean-CDaR-with-alpha 로만 검증 가능 → next_probe. 단 EW 가 이미 calmar·port_t·turnover 3면 지배하므로 EV 보수적.

## C4. [turnover 상한 규약] MinVar/MinCDaR/MinCVaR one-way 연 12.6~15.8 로 실격 판정했는데, TO≤11/yr 이 one-way 인지 round-trip 인지 규약 모호.
**분류: PARTIAL ACCEPT (절대상한) + REBUTTAL (상대 결론 robust)**
- **ACCEPT**: 절대 상한의 one-way/round-trip 규약은 모호 → one-way·round-trip **둘 다 병기**(round-trip 25~32). 
- **REBUTTAL**: 규약 무관하게 **상대** 결론은 불변 — 드로우다운 arm 은 EW(one-way 7.5~9.8)보다 **엄격히 더 churn**(15bps delta 과금 함정, 큐 wall_check 확증)하면서 calmar 이득 0. 즉 회전↑·비용↑·성과 개선 無. Cycle-2 1/N 우위(DeMiguel-Garlappi-Uppal 2009)와 정합.

## C5. [daily-120 창 짧음] CDaR 을 120일(~6개월)로 추정하면 다년 crash 를 못 봄 — 창이 길면 다를 수 있다.
**분류: PARTIAL ACCEPT**
- 120일은 calc_cdar 표본기본값. 창을 늘리면 다년 drawdown 을 목적함수가 더 볼 수 있으나 LP 표본↓·lookback↑. next_probe(장기창 CDaR)로 등재. 단 월간 실현 structural DD(MDD/에피소드/수중기간)는 전기간 실측이며 그 축에서 개선 부재.

## C6. [oos 전 arm 음수 — 측정 자체가 noise?] 모든 arm oos_retention 음수 → active 시계열이 noise 라 비교 무의미.
**분류: ACCEPT (단 negative 를 강화)**
- 이 재료(calmar-FAIL momentum)의 active 는 construction 무관하게 OOS 미보전(oos 대부분 음). 이는 "**construction 이 붕괴하는 신호를 못 살린다**"는 본 라운드 결론을 강화 — 레버가 weighting 이 아님을 재확인. verdict 불변.

---

## LP 무결성 감사 (fabrication 방화벽)
- cccp 설치 후 **fallback summary: 5 arm × 394 cell 전부 fallback=0** (fq058_run02_meta.json). CDaR/CVaR LP status=optimal 매 rebalance 실해 — min-vol/inverse-ES 폴백 오염 없음. 위험 measure arm 은 진짜 Rockafellar-Uryasev/Chekhlov LP.
- hard constraint audit: 1970 weight cell **violations=0** (종목≤25·[0,0.20]·Σw=1·long-only). RF-O5/O6/O7 clean.

## Q-Lead escalate 판정
- Hard Constraint 위반 0 · RF-O9(single-snapshot) 아님(walk-forward 197m 시계열) · infeasibility silent override 없음. **escalate 불요.**

## 결론
자가검증 6건 중 measure-축 핵심(C1/C3/C4)은 REBUTTAL/robust, 재료폭·κ·창(C2/C5)은 PARTIAL 로 next_probe 흡수, C6 은 negative 강화. **판정 config_scoped_negative 유지** — construction(weighting) 은 systematic-crash 성 calmar-FAIL 에 MDD 레버가 아니며, 레버는 selection 또는 overlay 로 이월(FQ-059/FQ-006).
