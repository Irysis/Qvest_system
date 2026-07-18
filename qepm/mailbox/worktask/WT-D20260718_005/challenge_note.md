# Self-Adversarial Challenge — WT-D20260718_005 (Transformer 팩터 밸류에이션 → 팩터 타이밍)

**규율**: v8.2 Self-Adversarial (Opus 4.8 native, 외부 Codex 없음). finalize 직전 약점 ≥3 자가제기 → ACCEPT/PARTIAL/REBUTTAL 분류 + 근거. Charter §8 No Silent Override.
**판정 요약**: 1차 방법(transformer / factor-valuation timing) = **NEGATIVE (config-scoped)**. 부수 발견(factor-momentum timing) = **screen-tier(비-졸업, 감쇠)**.
**Vintage pin**: RAWDATA_pin20260703 + benchmark_pin20260703 (재현성). 유니버스 KOSPI200∪KOSDAQ150 (~313/mo), top-25 EW long-only, cap-w KOSPI200 벤치, 15bps, liq 2e8.

---

## Concern 1 — [ACCEPT] HKS 과적합: transformer가 OOS서 trivial baseline에 지배됨
**약점**: 저차원(6 family)·데이터빈곤(223 usable months) 문제에 from-scratch transformer = HKS/Arnott가 경고한 IS-강/OOS-취약 전형. 
**실측 (동일 OOS 2012-12~2026-06, 163mo)**:
- transformer_ensemble port_t=0.911, paired_vs_static_t=1.855 (static 대비 개선은 有)
- **그러나 paired_vs_momentum_t = −0.673** (단순 factor-momentum 규칙 대비 **열위**), 전 seed 음수(−1.209/−1.697/−0.650)
- seed port_t 분산 0.476~0.853 (불안정 = 과적합 지문), turnover 10.2 (momentum 7.3보다 높음)
- **oos_retention 전부 <0.7 HARD FAIL** (static −0.93 / momentum −0.25 / transformer −0.31~−0.70; full-sample momentum −0.145 = <0.5 무조건 FAIL)
**처리**: pre-registered kill ② (oos_retention<0.7·OOS 붕괴) 정확 발화. transformer는 자기 method 기준으로 실패 — **NEGATIVE 정직 보고**. 합리화 없음.

## Concern 2 — [PARTIAL] Factor-momentum 부수발견의 multiple-testing (12 rule sweep)
**약점**: 단순 timing 규칙 12개(4 rule × 3 config) 중 momentum이 이겼다 = 선택 편의 가능.
**반증 근거**: 
- **placebo 대칭**: reversal(momentum 반대) paired_t −2.7~−2.9, val_reversal 음수 → 방향성 실재(노이즈 아님)
- **DSR=0.883** (N_trials=12 보정, Bailey-LdP 근사) > 0.5 → sweep 보정 IS 생존
- factor momentum은 a priori 효과(Gupta-Kelly 2019 "Factor Momentum Everywhere"), data-mined 아님
**처리**: momentum-timing 신호력은 실재하나 **oos_retention −0.145 HARD FAIL + cap-w port_t 1.28~2.49 < 2.95** → **졸업 불가·screen-tier**로만 라벨. 자본 주장 없음. DSR IS 생존은 결정 반전 근거 아님(oos_retention이 바인딩).

## Concern 3 — [REBUTTAL/ADDRESSED] Look-ahead (밸류에이션·factor-momentum 신호 PIT)
**약점**: val_spread·factor-momentum 특성이 동월 정보를 흘리면 momentum 결과 부풀림 가능(overlay 동월-누출 재발 우려).
**반증 (PIT 검증)**:
- val_spread = factor_db@t (load_month_factors, IC-expanding PIT). factor-momentum tr_12m = forward-return을 shift(1)로 지연(실현 <t만).
- **lag-1 PIT 스트레스(의무)**: momentum port_t 2.487 → +1lag 2.066 → +2lag 1.962. **완만 감쇠, 붕괴 없음** — 동월 누출이면 lag1서 ~0 붕괴(BearProb 사건 패턴). → 누출 부재 실증.
**처리**: PIT-clean. kill ③(look-ahead) 미발화.

## Concern 4 — [PARTIAL] 벤치/유니버스 basis (request liq 5e7·max500 vs 사용 2e8·top25)
**약점**: request.json 유니버스는 liq 5e7·max500(KR_TOP500 계열)인데 canonical HARD basis(cap-w K200∪KQ150·top-25·liq 2e8)를 사용.
**근거**: paired delta(timed−static)는 base·treatment가 유니버스·liq 공유 → basis 불변. dual-basis EW-uni 진단서도 순서 동일(OOS: momentum 3.03 > transformer 2.64 > static 1.39) — cap-w/EW 양쪽서 transformer가 momentum에 열위. 결론 invariant.
**처리**: 표준 canonical basis 사용 명시. 결론 basis-robust.

## Concern 5 — [REBUTTAL] static_EW base가 불리하게 낮게 잡혀 timing이 쉽게 이긴 것 아닌가
**약점**: base가 약하면(OOS static port_t −0.05) 아무 tilt나 이길 수 있음.
**근거**: base가 약해도 **transformer가 momentum 대비 열위**라는 핵심 판정은 base와 무관(둘 다 같은 base 대비). 더 강한 static base는 timing 문턱만 올림 → transformer NEGATIVE 결론 강화. 
**처리**: 결론 불변.

---

## 자기-합리화 auto-detection
"미미/관행적/보수적이면 OK/대부분 동일" 미사용. NEGATIVE 판정은 pre-registered kill ②(oos_retention HARD FAIL) + transformer-dominated-by-baseline 실측에 근거 — 합리화 아님.

## Q-Lead escalation trigger 점검
- HIGH severity ≥5: NO (해당 없음)
- AX axiom hard FAIL ≥3: NO
- PIT C1(lockbox·lookahead) 위반: NO (lag-1 스트레스 clean)
→ **escalate 불요.**

## Next-probe (continuity, ≥2)
1. **factor-momentum을 overlay/FR regime 입력으로** 소비 — screen-tier 신호(감쇠)의 국면-조건부 부활 검증(2020+ 감쇠가 mega-cap 레짐 얽힘인지: EW-uni oos_retention 재측정).
2. **FM(pre-trained TS) 각도** — from-scratch와 별개, capacity-gated FQ-061(venv 패키지 부재). 부활조건 = 패키지 확보 시.
부활조건: factor-momentum oos_retention이 EW-uni/regime-conditional서 ≥0.7 회복 시 재도전.
