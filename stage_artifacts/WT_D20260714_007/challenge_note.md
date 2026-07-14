# R31 (FQ-047) Self-Adversarial Challenge Note

**규약**: v8.2 Opus 4.8 자체 적대검증 (외부 Codex 없음). finalize 직전 약점 ≥3건 자가제기 → ACCEPT/PARTIAL/REBUTTAL 분류 + 근거 + 합리화 자기검증. Charter §8 No Silent Override.
**AX-008**: self-adversarial = Forge·Architect와 3-source 중 1 (본 라운드 screening-tier·forge 미가동 → self-adversarial 단독 문서화, 자본 판정 아님).

---

## Concern 1 (prereg #1) — 하위축 상관 높으면 사실상 1테스트 (중복 trial)
**제기**: 7 밸류 정의가 서로 강상관이면 "7 독립 검정"이 아니라 사실상 1개 신호를 7번 잰 것 → 다중검정 회계 왜곡 + 전멸 결론의 정보량 과대.
**분류: REBUTTAL** (정량 근거).
- 근거: median cross-sectional corr(EBIT_EV 기준) BM 0.64·EP 0.57·SP 0.61·SHY 0.47·CFP 0.30·**FCF 0.07**. FCF·CFP·EP는 EBIT/EV와 독립축(FCF는 全정의와 거의 직교: BM 0.05·EP 0.04·SP 0.07·SHY −0.07). 전체 상관행렬 기준 유효 독립 검정 ~4~5개(FCF 독립 + EP 준독립 + BM-SP-SHY 군집 + CFP-FCF 군집).
- 함의: 전멸(EBIT/EV 유일 게이트 통과)은 상관된 1신호의 반복이 아니라 **독립축 밸류 정의 다수가 각각 게이트 미달** = 결론 강건. 특히 FCF(직교)가 paired −0.21로 최악 = 독립 신호도 못 넘음.
- L-code 1: reference-kr-value-factor-decay(24/24 감쇠, 정의 다수 커버). 정량 3축: corr 행렬·paired 분산(−0.21~2.38)·EW-uni 분산(4.64~6.73).

## Concern 2 (prereg #2) — factor DB 밸류 정의 PIT 정합 (재무제표 lag C4)
**제기**: 밸류 팩터는 재무제표 기반 → annual 5월·quarterly 45일 lag 위반 시 동월 look-ahead. off0 vintage가 진짜 T-1 clean인가.
**분류: REBUTTAL** (구조 + 실측).
- 구조: factor_db aligned-z는 PIT-빌드(재무제표 lag 내장). off0 = factor_db month M = AS_OF−1 (score-label M+1의 T-1) — R29가 vz_off0(T-1 clean) vs vz_off1(same-month look-ahead) parity로 clean vintage 확증(WT_005). R31은 동일 off0 경로 승계.
- 실측: lag1 value-shift stress — SP lag1=2.147(붕괴 없음), EP lag1=1.006(안정). 동월 look-ahead면 lag1이 붕괴(faith/BearProb 실사고 패턴) — 여기선 붕괴 없음 → PIT-safe. EBIT_EV B2가 R30(lag1 2.473 통과분) 정확 재현.
- 합리화 자기검증: "이미 R29서 검증됨"으로 넘기지 않고 lag1 stress를 신규 하위축(SP/EP)에 직접 재측정함(자기점검 통과).

## Concern 3 (prereg #3) — 저EV 라운드 다중검정 (chain 정당성)
**제기**: value family 누적 ~15 trial(R26~R31)인데 chain이라 DSR 게이트 면제 → best(SP 1.52) cherry-pick 위험.
**분류: PARTIAL** (chain 유효하나 공시 강화).
- REBUTTAL 부분: 각 하위축 = 독립 밸류 정의의 가설주도 검정(argmax로 최종안 고르는 sweep 아님) → measurement-graduation §3 chain 자격. 변경사유 = 정의축 mechanism(book/earnings/cashflow/…). IS-only 선택(OOS 반복조회 없음 — 전 하위축 동일 프레임 1회 측정).
- ACCEPT 부분: 저EV·다중검정 부담 인정 → ① value family 누적 ~15 trial 명시 공시 ② DSR 진단 산출 의무(게이트 아님) ③ **어차피 SP(best new)도 게이트 미달** — cherry-pick할 통과 후보 자체가 없음(EBIT/EV만 통과, 그것도 FQ-046 REJECT 기결). cherry-pick 리스크는 통과 후보 부재로 실질 무효화.
- 합리화 검증: "chain이니 DSR 무시해도 OK"로 끝내지 않고 누적 trial·DSR 진단 공시(자기점검 통과).

## Concern 4 (self, 신규) — SP "2024+ 개선"이 소표본 아티팩트?
**제기**: post-2024 = ~30개월(2024-01~2026-06). paired_post 1.85·post17 1.88이 NW lag3 소표본 잡음일 수 있음 → "정의-특이 감쇠" 서사 과신.
**분류: ACCEPT (라벨링으로 처리)**.
- 인정: 30개월 paired는 시사적이지 확정 아님. verdict/validation에 "개선 계열은 full-period 약해 게이트 미달"·"suggestive not conclusive" 명시. next_probe P2를 **monitoring tripwire**(추가 관측으로 확증)로 설계 — 소표본을 standalone 결론이 아닌 관찰-지속 신호로 강등.
- 단 방향 근거: placebo p_emp 0.025(전기간 SP 실신호)·EW-uni 6.60(전기간 강함)·dIR_post +0.104(유일 양) — post-2024 개선이 순수 잡음일 확률은 낮으나 magnitude는 미확정. "개선"을 약주장으로 유지.

## Concern 5 (self, 신규) — cor_active 프록시로 "실낱 EV 반증" 주장 가능한가?
**제기**: cor_active(variant vs base)는 0.7 base + 0.3 틸트 구성상 **구조적으로 높다** → 정의 무관 0.9는 당연. 이걸로 "다른 정의도 덜 중복 안 됨(실낱 EV 반증)"을 주장하면 프록시 부적합을 결론으로 오용.
**분류: PARTIAL (주장 범위 축소)**.
- ACCEPT: cor_active는 정의-레벨 incumbent 중복을 해상 못 함(구성-바운드). risk-단계 realized corr vs STR_1715(EBIT/EV 0.98)이 권위인데 본 라운드 미가동.
- REBUTTAL: 하지만 결론은 유지 — 정확히 "잉여가 **구성-바운드**"라는 것이 발견(정의 무관 0.9). "실낱 EV"는 "덜 중복되는 정의가 있을 것"인데, 애초에 **게이트 통과 정의가 EBIT/EV뿐**이라 중복도 비교가 moot. verdict에 caveat 명시(프록시 한계 + moot 사유). 즉 "실낱 EV 반증"을 "구성-바운드 + 게이트 통과 부재로 moot"로 정련.
- 합리화 검증: "cor 0.9니까 다 중복"이라 단정하지 않고 프록시 한계를 명시 라벨.

## Concern 6 (self, 신규) — SHY 희소 커버리지로 주주환원 정의를 과소검정?
**제기**: SHY finite=37,106 (base 80,552행의 46%) — 배당/자사주 미실시 종목은 v_z=0(틸트 없음) → non-mega 틸트가 절반 종목서만 작동 → shareholder-yield 정의를 공정히 검정 못 함.
**분류: PARTIAL (라벨 + honest 한계)**.
- 인정: SHY 검정은 커버리지-제약(prereg에 SPARSE 명시). paired 1.275는 배당-payer 서브셋 효과. "주주환원 정의 완전 기각"이 아니라 "가용 커버리지 하 게이트 미달".
- 단 완화: SHY EW-uni 5.15·oos 0.46도 게이트급 아님(커버리지 무관 약함). 커버리지 확대해도 통과 가능성 낮으나 **확정 아님** — 필요시 배당-payer 유니버스 한정 재측정 가능(저순위, 저EV).

---

## 합리화 자동탐지 스캔 (measurement-graduation §금칙)
"미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일" 사용 = 0건. "유사/거의/추정/예상" 검증-증거 없이 사용 = 0건(모든 수치 = 실측 canonical/weighted_screen). SP "개선"은 약주장 라벨 + placebo/EW-uni 정량 근거 병기.

## Escalation 판정
HIGH severity: 0 (< 5). AX axiom hard FAIL: 0 (< 3). PIT C1(lockbox/lookahead) 위반: 0 (lag1 통과·off0 clean). **→ Q-Lead escalate 트리거 미발화.** screening-tier 완결 라운드 정상 종료.
